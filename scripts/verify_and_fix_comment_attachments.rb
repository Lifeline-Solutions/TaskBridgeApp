#!/usr/bin/env ruby
# scripts/verify_and_fix_comment_attachments.rb
# Verify and optionally fix comment-level attachments for defects

require 'optparse'
require 'yaml'
require 'net/http'
require 'uri'
require 'json'

options = {
  verbose: false,
  fix: false,
  defect_id: nil,
  defect_unique: nil,
  check_all: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/verify_and_fix_comment_attachments.rb [options]'

  opts.on('--defect-id ID', 'Check specific defect by ID') { |v| options[:defect_id] = v }
  opts.on('--defect-unique KEY', 'Check specific defect by unique key (e.g., PSP-123)') { |v| options[:defect_unique] = v }
  opts.on('--check-all', 'Check all defects with comments') { options[:check_all] = true }
  opts.on('--fix', 'Attempt to fix missing attachments (requires Jira credentials)') { options[:fix] = true }
  opts.on('--verbose', 'Verbose output') { options[:verbose] = true }
end.parse!

$verbose_flag = options[:verbose]

def vputs(msg)
  puts msg if $verbose_flag
end

# ---- Jira config (same as import script) ----
CONFIG = begin
  cfg_path = Rails.root.join('config', 'jira_import.yml')
  File.exist?(cfg_path) ? YAML.load_file(cfg_path).with_indifferent_access : {}
rescue
  {}
end

JIRA_BASE_URL  = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER  = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || '')
JIRA_API_TOKEN = ENV['JIRA_API_TOKEN'] || CONFIG[:jira_api_token]
DEFAULT_USER_UUID = CONFIG[:default_user_uuid] || User.first&.id

if options[:fix] && (!JIRA_API_USER.present? || !JIRA_API_TOKEN.present?)
  warn '⚠️  --fix requested but Jira credentials are missing (JIRA_API_USER/JIRA_API_TOKEN). Proceeding in verify-only mode.'
  options[:fix] = false
end

# ---- Helpers ----

def try_parse_time(val)
  return nil if val.nil? || val.to_s.strip.empty?
  Time.parse(val) rescue nil
end

# Find user via email or displayName (case-insensitive); fallback to default user

def find_user_by_name_or_email(name, email)
  email_str = email.to_s.strip.downcase
  if email_str.present? && email_str != 'restricted'
    u = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str)
    return u if u
  end
  name_str = name.to_s.strip.downcase
  if name_str.present?
    u = User.where(deleted_on: nil)
            .where("lower(coalesce(first_name,'') || ' ' || coalesce(last_name,'')) = ?", name_str)
            .first
    return u if u
  end
  User.find_by(id: DEFAULT_USER_UUID) || User.first
end

# Jira: fetch attachments and comments for an issue key

def jira_get_issue(issue_key)
  uri = URI.parse("#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}")
  # request minimal fields for speed
  query = { fields: %w[attachment comment reporter].join(',') }
  uri.query = URI.encode_www_form(query)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 600
  http.open_timeout = 60

  req = Net::HTTP::Get.new(uri.request_uri)
  req['Accept'] = 'application/json'
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  resp = http.request(req)
  raise "Jira error #{resp.code} #{resp.message}" unless resp.is_a?(Net::HTTPSuccess)
  JSON.parse(resp.body)
rescue => e
  warn "[JIRA] Failed to fetch #{issue_key}: #{e.message}"
  nil
end

# Map Jira attachments to comments using creation time proximity (<= 5 minutes)

def map_comment_attachments(jira_issue)
  fields = jira_issue['fields'] || {}
  all_atts = (fields['attachment'] || []).select { |a| a.is_a?(Hash) }
  comments = (fields.dig('comment', 'comments') || []).select { |c| c.is_a?(Hash) }

  # Build result: { jira_comment_id => [attachments] }
  mapping = Hash.new { |h,k| h[k] = [] }

  comments.each do |c|
    c_created = try_parse_time(c['created'])
    next unless c_created

    # prefer explicit comment.attachment if present
    if c.key?('attachment') && c['attachment'].is_a?(Array) && c['attachment'].any?
      mapping[c['id']] += c['attachment']
      next
    end

    # otherwise use time proximity window 5 minutes
    all_atts.each do |att|
      a_created = try_parse_time(att['created'])
      next unless a_created
      diff = (a_created - c_created).abs
      mapping[c['id']] << att if diff < 300 # 5 minutes
    end
  end

  # Unique by id/filename
  mapping.transform_values do |arr|
    arr.uniq { |x| x['id'] || x['filename'] }
  end
end

# Download attachment body from Jira (supports redirects)

def download_jira_attachment(att)
  filename = att['filename'] || att['name'] || 'attachment'
  content_url = att['content'] || att['contentUrl'] || att['self']
  mime = att['mimeType'] || att['contentType'] || 'application/octet-stream'
  return nil unless content_url

  uri = URI.parse(content_url)
  redirects = 0
  max_redirects = 8
  resp = nil

  loop do
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 900 # 15 min for large files
    http.open_timeout = 90

    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    resp = http.request(req)
    if resp.is_a?(Net::HTTPRedirection)
      loc = resp['location']
      break unless loc
      redirects += 1
      raise 'Too many redirects' if redirects > max_redirects
      uri = URI.parse(loc)
      next
    end
    break
  end

  return nil unless resp && resp.is_a?(Net::HTTPSuccess)

  [resp.body, filename, mime]
rescue => e
  warn "[JIRA] Download failed for #{filename}: #{e.message}"
  nil
end

# Attach binary to Defect (issue-level)

def ensure_issue_attachment(defect, att)
  fname = att['filename'] || att['name']
  return 0 unless fname
  # Skip if already attached by filename
  if defect.attachments.any? { |a| a.filename.to_s == fname }
    return 0
  end
  data = download_jira_attachment(att)
  return 0 unless data
  body, filename, mime = data
  io = StringIO.new(body)
  defect.attachments.attach(io: io, filename: filename, content_type: mime)
  1
rescue => e
  warn "[FIX] Failed to attach issue file #{fname} to #{defect.defect_unique}: #{e.message}"
  0
end

# Ensure comment exists and return DefectMessage

def ensure_comment_record(defect, jira_comment)
  created_at = try_parse_time(jira_comment['created'])
  author = jira_comment['author'] || {}
  user = find_user_by_name_or_email(author['displayName'], author['emailAddress'])

  # Match by timestamp primarily
  if created_at
    existing = defect.defect_messages.where(created_at: created_at).first
    return existing if existing
  end

  # Fallback: match by same user and similar content text (prefix)
  body_text = begin
    # Jira cloud comment body may be rich text; use simple string if available
    raw = jira_comment['body']
    if raw.is_a?(String)
      raw
    elsif raw.is_a?(Hash)
      # attempt extracting text
      (raw['content'] || []).flat_map { |blk| (blk['content'] || []).map { |s| s['text'] } }.compact.join(' ')
    else
      raw.to_s
    end
  rescue
    ''
  end
  snippet = body_text.to_s.strip[0..60]
  if user && snippet.present?
    dm = defect.defect_messages.where(user_id: user.id).detect do |m|
      begin
        (m.content.try(:to_plain_text) || m.content.to_s).to_s.start_with?(snippet)
      rescue
        false
      end
    end
    return dm if dm
  end

  # Create if not found
  dm = DefectMessage.new(defect: defect, user: user, modified_by: user)
  dm.content = body_text.presence || '[Imported from Jira]'
  dm.created_at = created_at if created_at
  dm.updated_at = try_parse_time(jira_comment['updated']) || created_at
  dm.save!
  dm
end

# Attach binary to DefectMessage (comment-level)

def ensure_comment_attachment(dm, att)
  fname = att['filename'] || att['name']
  return 0 unless fname
  # Skip if already attached by filename
  if dm.respond_to?(:attachments) && dm.attachments.any? { |a| a.filename.to_s == fname }
    return 0
  end
  data = download_jira_attachment(att)
  return 0 unless data
  body, filename, mime = data
  io = StringIO.new(body)
  dm.attachments.attach(io: io, filename: filename, content_type: mime)
  1
rescue => e
  warn "[FIX] Failed to attach comment file #{fname} to message #{dm.id}: #{e.message}"
  0
end

puts '=' * 80
puts 'Comment-Level Attachment Verification'
puts '=' * 80
puts ''

# Determine which defects to check
defects = if options[:defect_id]
            Defect.where(id: options[:defect_id])
          elsif options[:defect_unique]
            Defect.where(defect_unique: options[:defect_unique])
          elsif options[:check_all]
            Defect.joins(:defect_messages).distinct
          else
            puts 'ERROR: Please specify --defect-id, --defect-unique, or --check-all'
            exit 1
          end

if defects.none?
  puts 'No defects found matching criteria.'
  exit 0
end

puts "Checking #{defects.count} defect(s)..."
puts ''

overall_stats = {
  defects_checked: 0,
  defects_with_comments: 0,
  total_comments: 0,
  comments_with_attachments: 0,
  total_attachment_records: 0,
  verified_attachments: 0,
  missing_attachments: 0,
  defects_with_issues: []
}

defects.find_each do |defect|
  overall_stats[:defects_checked] += 1

  messages = defect.defect_messages.includes(attachments_attachments: :blob)

  next if messages.none?

  overall_stats[:defects_with_comments] += 1
  overall_stats[:total_comments] += messages.count

  defect_stats = {
    comments: messages.count,
    comments_with_attachments: 0,
    total_files: 0,
    verified_files: 0,
    missing_files: []
  }

  messages.each do |message|
    next if message.attachments.none?

    defect_stats[:comments_with_attachments] += 1
    overall_stats[:comments_with_attachments] += 1

    message.attachments.each do |attachment|
      defect_stats[:total_files] += 1
      overall_stats[:total_attachment_records] += 1

      filename = attachment.filename.to_s
      blob = attachment.blob

      begin
        exists = ActiveStorage::Blob.service.exist?(blob.key)

        if exists
          defect_stats[:verified_files] += 1
          overall_stats[:verified_attachments] += 1

          puts "  ✅ #{defect.defect_unique} - Comment #{message.id}: #{filename} (#{blob.byte_size} bytes)" if options[:verbose]
        else
          defect_stats[:missing_files] << {
            message_id: message.id,
            filename: filename,
            blob_key: blob.key,
            size: blob.byte_size
          }
          overall_stats[:missing_attachments] += 1

          puts "  ❌ #{defect.defect_unique} - Comment #{message.id}: #{filename} - FILE MISSING FROM STORAGE"
        end
      rescue StandardError => e
        defect_stats[:missing_files] << {
          message_id: message.id,
          filename: filename,
          blob_key: blob&.key || 'N/A',
          error: e.message
        }
        overall_stats[:missing_attachments] += 1

        puts "  ❌ #{defect.defect_unique} - Comment #{message.id}: #{filename} - ERROR: #{e.message}"
      end
    end
  end

  # Report defect-level summary if there are issues
  if defect_stats[:missing_files].any?
    overall_stats[:defects_with_issues] << {
      defect: defect,
      stats: defect_stats
    }

    puts ''
    puts "📋 DEFECT: #{defect.defect_unique} (ID: #{defect.id})"
    puts "   Comments: #{defect_stats[:comments]} total, #{defect_stats[:comments_with_attachments]} with attachments"
    puts "   Attachments: #{defect_stats[:verified_files]}/#{defect_stats[:total_files]} verified"
    puts "   ⚠️  Missing: #{defect_stats[:missing_files].length} file(s)"

    defect_stats[:missing_files].each do |missing|
      puts "      - #{missing[:filename]} (message #{missing[:message_id]})"
    end
    puts ''
  elsif options[:verbose] && defect_stats[:total_files] > 0
    puts "✅ #{defect.defect_unique}: All #{defect_stats[:total_files]} attachment(s) verified"
  end
end

# Overall summary
puts ''
puts '=' * 80
puts 'SUMMARY'
puts '=' * 80
puts "Defects checked: #{overall_stats[:defects_checked]}"
puts "Defects with comments: #{overall_stats[:defects_with_comments]}"
puts "Total comments: #{overall_stats[:total_comments]}"
puts "Comments with attachments: #{overall_stats[:comments_with_attachments]}"
puts ''
puts "Total attachment records: #{overall_stats[:total_attachment_records]}"
puts "Verified in storage: #{overall_stats[:verified_attachments]} (#{overall_stats[:total_attachment_records] > 0 ? ((overall_stats[:verified_attachments].to_f / overall_stats[:total_attachment_records]) * 100).round(2) : 0}%)"
puts "Missing from storage: #{overall_stats[:missing_attachments]} (#{overall_stats[:total_attachment_records] > 0 ? ((overall_stats[:missing_attachments].to_f / overall_stats[:total_attachment_records]) * 100).round(2) : 0}%)"
puts ''

if overall_stats[:defects_with_issues].any?
  puts "⚠️  #{overall_stats[:defects_with_issues].length} defect(s) have missing comment attachments:"
  overall_stats[:defects_with_issues].each do |issue|
    puts "   - #{issue[:defect].defect_unique}: #{issue[:stats][:missing_files].length} missing file(s)"
  end
  puts ''

  if options[:fix]
    puts '=' * 80
    puts 'FIX MODE: Attempting to re-import missing comment attachments from Jira'
    puts '=' * 80
    puts ''

    fixed_total = 0
    failed_total = 0

    overall_stats[:defects_with_issues].each_with_index do |issue, idx|
      defect = issue[:defect]
      missing = issue[:stats][:missing_files]

      puts "[#{idx + 1}/#{overall_stats[:defects_with_issues].length}] #{defect.defect_unique}: fixing #{missing.length} file(s)"

      jira_issue = jira_get_issue(defect.defect_unique)
      if jira_issue.nil?
        puts "   ❌ Could not fetch Jira issue data; skipping"
        failed_total += missing.length
        next
      end

      mapping = map_comment_attachments(jira_issue)
      fields = jira_issue['fields'] || {}
      all_jira_atts = (fields['attachment'] || []).select { |a| a.is_a?(Hash) }

      fixed_for_defect = 0
      failed_for_defect = 0

      missing.each do |miss|
        message_id = miss[:message_id]
        filename = miss[:filename]
        dm = defect.defect_messages.find_by(id: message_id)
        unless dm
          puts "   ❌ Comment #{message_id} not found; skipping #{filename}"
          failed_for_defect += 1
          next
        end

        # Find attachment data from Jira for this comment
        jira_comment = (fields.dig('comment', 'comments') || []).find { |c| c['id'].to_s == message_id.to_s }
        att = nil
        if jira_comment && mapping[jira_comment['id']]
          att = mapping[jira_comment['id']].find { |a| (a['filename'] || a['name']).to_s == filename.to_s }
        end
        # Fallback: search all issue atts by filename
        att ||= all_jira_atts.find { |a| (a['filename'] || a['name']).to_s == filename.to_s }

        unless att
          puts "   ❌ Jira attachment metadata not found for #{filename}; skipping"
          failed_for_defect += 1
          next
        end

        added = ensure_comment_attachment(dm, att)
        if added > 0
          puts "   ✅ Re-attached #{filename} to comment #{dm.id}"
          fixed_for_defect += 1
        else
          puts "   ❌ Failed to attach #{filename} to comment #{dm.id}"
          failed_for_defect += 1
        end
      end

      # Verify after fix
      dm_after = defect.defect_messages.includes(attachments_attachments: :blob)
      newly_verified = 0
      missing_after = 0
      dm_after.each do |m|
        next unless m.respond_to?(:attachments)
        m.attachments.each do |a|
          begin
            newly_verified += 1 if ActiveStorage::Blob.service.exist?(a.blob.key)
          rescue
            next
          end
        end
      end

      fixed_total += fixed_for_defect
      failed_total += failed_for_defect

      puts "   ➕ Fixed: #{fixed_for_defect}, ❌ Failed: #{failed_for_defect}"
      puts ''
    end

    puts 'FIX SUMMARY'
    puts "  Total files fixed: #{fixed_total}"
    puts "  Total files failed: #{failed_total}"
    puts ''
  else
    puts 'To attempt fixing, run with --fix flag:'
    puts '  rails runner scripts/verify_and_fix_comment_attachments.rb --check-all --fix --verbose'
    puts ''
    puts 'Or re-run the import for specific defects:'
    puts '  rails runner scripts/import_jira_with_modules.rb --project <KEY> --verbose'
  end
else
  puts '✅ All comment-level attachments verified successfully!'
  puts ''
  puts "All #{overall_stats[:total_attachment_records]} attachment file(s) are present in storage."
end

puts '=' * 80

# Additional diagnostics
if overall_stats[:missing_attachments] > 0
  puts ''
  puts 'DIAGNOSTIC INFORMATION'
  puts '=' * 80

  # Check storage configuration
  service = ActiveStorage::Blob.service
  storage_root = service.respond_to?(:root) ? service.root : 'N/A'

  puts "Storage Service: #{service.class.name}"
  puts "Storage Root: #{storage_root}"
  puts "Rails Environment: #{Rails.env}"
  puts ''

  if storage_root != 'N/A'
    if Dir.exist?(storage_root)
      puts "✅ Storage directory exists: #{storage_root}"

      # Check if writable
      test_file = File.join(storage_root, ".write_test_#{Time.now.to_i}")
      begin
        File.write(test_file, 'test')
        File.delete(test_file)
        puts '✅ Storage directory is writable'
      rescue StandardError => e
        puts "❌ Storage directory is NOT writable: #{e.message}"
        puts "   Fix: sudo chown -R $(whoami):$(whoami) #{storage_root}"
      end
    else
      puts "❌ Storage directory does NOT exist: #{storage_root}"
      puts "   Fix: sudo mkdir -p #{storage_root} && sudo chown -R $(whoami):$(whoami) #{storage_root}"
    end
  end

  puts ''
  puts 'Possible causes for missing files:'
  puts '1. Import was interrupted before files finished uploading'
  puts '2. Storage directory was deleted or moved after import'
  puts '3. Permissions prevented file writing during import'
  puts '4. Network issues during download from Jira'
  puts '5. Database was restored but storage files were not'
  puts ''
  puts 'Recommended fix:'
  puts '1. Ensure storage directory exists and is writable (see above)'
  puts '2. Re-run the import script with --verbose to see detailed progress'
  puts '3. The script will now verify each upload and retry failures'
  puts '=' * 80
end
