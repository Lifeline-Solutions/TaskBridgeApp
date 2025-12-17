#!/usr/bin/env ruby
# scripts/fix_defect_details_and_comments.rb
#
# USAGE:
#   bin/rails runner scripts/fix_defect_details_and_comments.rb [options]
#
# OPTIONS:
#   --dry-run                 : Show what would happen without making changes
#   --defect-unique <KEY>     : Run for a specific defect (e.g. KEY-123)
#   --project <PROJECT_KEY>   : Run for all defects in a project
#   --check-all               : Run for all defects with regex match

require 'net/http'
require 'json'
require 'uri'
require 'base64'
require 'optparse'
require 'securerandom'
require 'date' # [ADDED]
require 'stringio' # [ADDED]
require_relative 'enhanced_adf_converter'

# Configuration
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = File.exist?(config_path) ? YAML.load_file(config_path).with_indifferent_access : {}

JIRA_DOMAIN = 'craftsilicon.atlassian.net'
JIRA_BASE_URL = "https://#{JIRA_DOMAIN}"
EMAIL = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user])
API_TOKEN = ENV.fetch('JIRA_API_TOKEN', CONFIG[:jira_api_token])

unless EMAIL && API_TOKEN
  puts "ERROR: Jira Credentials missing (JIRA_API_USER / JIRA_API_TOKEN)"
  exit 1
end

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = "Usage: fix_defect_details_and_comments.rb [options]"
  opts.on("-d", "--dry-run", "Run without making changes") { options[:dry_run] = true }
  opts.on("-u", "--defect-unique DEFECT_ID", "Run for a specific defect only") { |v| options[:specific] = v }
  opts.on("-p", "--project PROJECT_KEY", "Run for a specific project") { |v| options[:project] = v }
  opts.on("-a", "--check-all", "Run for all defects") { options[:check_all] = true }
end.parse!

if !options[:specific] && !options[:project] && !options[:check_all]
  puts "ERROR: Must specify --defect-unique, --project, or --check-all"
  exit 1
end

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def auth_header
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
end

def fetch_issue(key)
  uri = URI("#{JIRA_BASE_URL}/rest/api/3/issue/#{key}")
  query = { fields: %w[description comment reporter attachment].join(',') }
  uri.query = URI.encode_www_form(query)
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  req = Net::HTTP::Get.new(uri, auth_header)
  res = http.request(req)
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    log "  [ERROR] Failed to fetch #{key}: #{res.code} #{res.message}"
    nil
  end
end

def normalize_email(display_name)
  name_parts = display_name.to_s.strip.split(/[\s\.]+/)
  return "unknown.user-#{SecureRandom.hex(4)}@craftsilicon.com" if name_parts.empty?
  first = name_parts.first.gsub(/[^a-zA-Z0-9]/, '').downcase
  last = name_parts.length > 1 ? name_parts.last.gsub(/[^a-zA-Z0-9]/, '').downcase : ''
  email_local = last.present? ? "#{first}.#{last}" : first
  "#{email_local}@craftsilicon.com"
end

def find_or_create_strict_user(jira_author)
  return nil unless jira_author
  
  display_name = jira_author['displayName']
  email = jira_author['emailAddress']
  
  # 1. Strict Email Match
  if email.present?
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email.downcase)
    return user if user
  end
  
  # 2. Strict Full Name Match
  if display_name.present?
    user = User.where(deleted_on: nil).where("lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) = ?", display_name.downcase).first
    return user if user
  end
  
  # 3. Create Disabled User
  # Do not fallback to 'admin' or fuzzy match. Create exact representation.
  
  # Generate email if missing
  user_email = email.present? ? email : normalize_email(display_name)
  
  # Ensure email uniqueness for creation
  if User.exists?(email: user_email)
    # If we are here, it means we didn't match by email earlier, so this email exists but maybe case sensitivity or whitespace issue?
    # Or strict name match failed but email exists.
    # In any case, fetch it.
    return User.find_by(email: user_email)
  end

  parts = display_name.split(' ')
  first_name = parts.first || 'Unknown'
  last_name = parts.drop(1).join(' ').presence || 'User'
  
  log "    -> [CREATE-USER] #{display_name} (#{user_email}) - Inactive"
  
  password = SecureRandom.hex(16)
  user = User.new(
    first_name: first_name,
    last_name: last_name,
    email: user_email,
    password: password, 
    password_confirmation: password,
    active: false, # DISABLED
    confirmed_at: Time.now
  )
  
  # user.skip_confirmation! if user.respond_to?(:skip_confirmation!)
  user.save!(validate: false)
  user
end

def download_attachment(att)
  content_url = att['content']
  filename = att['filename']
  uri = URI(content_url)
  
  max_retries = 4
  attempts = 0
  
  loop do
    attempts += 1
    
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      
      # Increased timeouts for large video files
      http.open_timeout = 60
      http.read_timeout = 600 # 10 minutes
      
      req = Net::HTTP::Get.new(uri, auth_header)
      
      res = http.request(req)
      
      if res.is_a?(Net::HTTPRedirection)
        location = res['location']
        if attempts < max_retries
          log "      [REDIRECT] Following redirect for #{filename}..."
          uri = URI(location)
          next
        end
      end
      
      unless res.is_a?(Net::HTTPSuccess)
        log "      [ERROR] HTTP #{res.code} for #{filename}"
        return nil
      end
      
      return res.body

    rescue StandardError => e
      if attempts < max_retries
        wait_time = attempts * 3
        log "      [RETRY] Error downloading #{filename} (#{e.class}: #{e.message}). Retrying in #{wait_time}s..."
        sleep wait_time
        next
      else
        log "      [FAIL] Failed to download #{filename} after #{max_retries} attempts."
        return nil 
      end
    end
  end
end

# [NEW] Map attachments to comments (Time < 5m)
def map_comment_attachments(jira_issue)
  fields = jira_issue['fields'] || {}
  all_atts = (fields['attachment'] || []).select { |a| a.is_a?(Hash) }
  comments = (fields.dig('comment', 'comments') || []).select { |c| c.is_a?(Hash) }
  
  mapping = Hash.new { |h, k| h[k] = [] }
  
  comments.each do |c|
    c_created = DateTime.parse(c['created']).to_time
    # 1. Explicit nested attachments (rare in v3 but possible)
    if c['attachment'].is_a?(Array)
       mapping[c['id']] += c['attachment']
       next
    end
    # 2. Time proximity (5 mins)
    all_atts.each do |att|
      a_created = DateTime.parse(att['created']).to_time
      diff = (a_created - c_created).abs
      mapping[c['id']] << att if diff < 300
    end
  end
  # Unique
  mapping.transform_values { |arr| arr.uniq { |x| x['id'] } }
end

# [NEW] Sync attachments to message
def sync_message_attachments(message, attachments, dry_run: false)
  return if attachments.empty?
  
  attachments.each do |att|
    filename = att['filename']
    # Check if exists
    next if message.attachments.any? { |a| a.filename.to_s == filename }
    
    log "      [ATTACH] Attaching #{filename} to Comment #{message.id}..."
    next if dry_run
    
    data = download_attachment(att)
    next unless data
    
    io = StringIO.new(data)
    message.attachments.attach(io: io, filename: filename, content_type: att['mimeType'])
  end
end

# Main Processor
log "Starting Defect Cleanup... (Dry Run: #{options[:dry_run]})"

scope = if options[:specific]
          Defect.where(defect_unique: options[:specific])
        elsif options[:project]
          Defect.where("defect_unique LIKE ?", "#{options[:project]}-%")
        else
          Defect.where("defect_unique ~ '^[A-Z]+-\\d+$'")
        end

log "Found #{scope.count} defects to process."

scope.find_each do |defect|
  log "Processing #{defect.defect_unique}..."
  
  jira_issue = fetch_issue(defect.defect_unique)
  unless jira_issue
    log "  [SKIP] Could not fetch from Jira."
    next
  end
  
  fields = jira_issue['fields']
  attachment_map = map_comment_attachments(jira_issue)
  
  # 1. Sync Description
  jira_desc_adf = fields['description']
  new_description_html = convert_adf_to_html_enhanced(jira_desc_adf.is_a?(Hash) ? jira_desc_adf['content'] : [])
  
  # Check if update needed
  if defect.content.to_s != new_description_html
    log "  [UPDATE] Description mismatch. Updating..."
    # log "    Old: #{defect.content.to_s[0..50]}..."
    # log "    New: #{new_description_html[0..50]}..."
    unless options[:dry_run]
       defect.update(content: new_description_html)
    end
  else
    log "  [OK] Description matches."
  end
  
  # 2. Sync Comments
  jira_comments = fields['comment']['comments'] || []
  local_messages = defect.defect_messages.where(archive_status: false).to_a
  
  jira_comments.each do |j_comment|
    j_id = j_comment['id']
    j_body_adf = j_comment['body']
    j_html = convert_adf_to_html_enhanced(j_body_adf.is_a?(Hash) ? j_body_adf['content'] : [])
    
    # Fallback for plain string body
    j_html = j_body_adf if j_html.blank? && j_body_adf.is_a?(String)
    j_html = "" if j_html.nil?
    
    j_author = find_or_create_strict_user(j_comment['author'])
    j_created = DateTime.parse(j_comment['created'])
    
    # Identify match
    # Match criteria: 
    # 1. Exact content AND Author AND Time closeness (very strict)
    # 2. Just content AND Author (if time skewed)
    
    # Normalize HTML for comparison (strip whitespace)
    j_html_clean = j_html.gsub(/\s+/, ' ').strip
    
    match = local_messages.find do |m|
      m_html_clean = m.content.to_s.gsub(/\s+/, ' ').strip
      # Compare content
      content_match = (m_html_clean == j_html_clean)
      # Compare author
      author_match = (m.user_id == j_author.id)
      # Compare time (within 1 minute)
      time_match = (m.created_at.to_i - j_created.to_i).abs < 60
      
      # [RELAXED MATCH] If Author and Time match, trust it is the same comment (and update content later)
      # This handles cases where local content has poor formatting but is the same 'logical' comment
      (author_match && time_match) || (content_match && author_match)
    end
    
    # Secondary sloppy match for "Imported from Jira" or slightly different formatting
    unless match
      match = local_messages.find do |m|
        m_content = m.content.to_s.gsub(/\s+/, ' ').strip
        # Relaxed fall back: correct author + roughly similar content (start matches)
        # or Author + Time (wider window of 2m)
        ((m_content.include?(j_html_clean[0..20]) || j_html_clean.include?(m_content[0..20])) && (m.user_id == j_author.id)) ||
        ((m.user_id == j_author.id) && (m.created_at.to_i - j_created.to_i).abs < 120)
      end
    end

    if match
      # Update Timestamp if needed
      updates = {}
      if (match.created_at.to_i - j_created.to_i).abs > 5
         updates[:created_at] = j_created
         log "    [FIX-TIME] Comment #{match.id} time adjusted."
      end
      
      # Ensure content is exactly synced (better formatting)
      if match.content.to_s != j_html
         # We can't use update_columns for rich text, need to update attribute
         log "    [FIX-CONTENT] Comment #{match.id} content refined."
         match.content = j_html unless options[:dry_run]
         match.save(validate: false) unless options[:dry_run]
      end
      
      if updates.any? && !options[:dry_run]
        match.update_columns(updates)
      end
      
      # Remove from local list so we know what's left
      local_messages.delete(match)
    else
      log "    [CREATE] New comment by #{j_author.name}..."
      
      # [ENHANCEMENT] Embed attachments in comment body if referenced
      # If comment says "Refer attached video" but no link, we can try to append links if we find matching attachments
      # For now, just create the comment.
      
      unless options[:dry_run]
        msg = defect.defect_messages.create!(
          user: j_author,
          content: j_html,
          created_at: j_created,
          updated_at: j_created,
          archive_status: false
        )
        match = msg 
      end
    end
    
    # 3. Sync Attachments for this comment
    atts = attachment_map[j_id] || []
    if match && atts.any?
       sync_message_attachments(match, atts, dry_run: options[:dry_run])
    end
    
    # 3. Sync Attachments for this comment
    # Use verify_and_fix_comment_attachments.rb logic simplified
    # (Checking basic existence)
    # Note: Jira 'attachment' field is top-level, not always nested in comments in all API versions,
    # but we can try mapping if needed. But usually users just want the files present on the defect or comment.
    # For now, we'll rely on the dedicated attachment fixer for complex mapping, 
    # but we can handle plain attachments if present in comment json (rare in v3 API, usually separate).
    
  end
  
  # Remaining local_messages are likely duplicates or local-only.
  # If they have "Imported from Jira" or similar signs, they might be bad duplicates.
  local_messages.each do |orphan|
    # Heuristic: If we just processed Jira comments and this orphan is VERY close in time to one of them, it's a double.
    # But for safety, we won't auto-delete unless we're sure.
    # The requirement said "cleanup... duplicate comments with wrong commenter".
    # If the user is system/default and content exists in Jira under real user, it's a dupe.
    
    is_dupe = jira_comments.any? do |jc|
       jc_created = DateTime.parse(jc['created'])
       # Time match (Very strict < 2s for orphans implies it's a generated duplicate)
       # OR Time match < 60s AND content matches roughly
       time_exact = (orphan.created_at.to_i - jc_created.to_i).abs < 2
       time_close = (orphan.created_at.to_i - jc_created.to_i).abs < 60
       content_rough = orphan.content.to_s.gsub(/\s+/, '').include?(convert_adf_to_html_enhanced(jc['body']['content']).gsub(/\s+/, '')[0..20])
       
       time_exact || (time_close && content_rough)
    end
    
    if is_dupe
       log "    [DELETE-DUPE] Removing duplicate/wrong-author comment #{orphan.id} (User: #{orphan.user&.name})"
       orphan.destroy unless options[:dry_run]
    end
  end

end

log "Done."
