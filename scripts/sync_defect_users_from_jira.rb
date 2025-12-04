#!/usr/bin/env ruby
# scripts/sync_defect_users_from_jira.rb
#
# This script calls Jira API to get the ACTUAL reporter and assignee,
# then compares with what's in your database and fixes any discrepancies.
#
# It fetches the real reporter/assignee from Jira and updates your database if different.
#
# Usage:
#   # Update all defects for a project from Jira
#   bundle exec rails runner scripts/sync_defect_users_from_jira.rb --project ISP
#
#   # Update a specific issue from Jira
#   bundle exec rails runner scripts/sync_defect_users_from_jira.rb --issue ISP-1383
#
#   # Dry run (preview without saving)
#   bundle exec rails runner scripts/sync_defect_users_from_jira.rb --project ISP --dry-run
#
#   # Verbose output
#   bundle exec rails runner scripts/sync_defect_users_from_jira.rb --issue ISP-1383 --verbose

require 'optparse'
require 'yaml'
require 'net/http'
require 'uri'
require 'json'

# Enable real-time logging
$stdout.sync = true
$stderr.sync = true

APP_ROOT = Rails.root

options = {
  dry_run: false,
  verbose: false,
  project: nil,
  issue: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/sync_defect_users_from_jira.rb [options]'

  opts.on('--project KEY', String, 'Project key (e.g., PSP, ISP)') { |v| options[:project] = v }
  opts.on('--issue KEY', String, 'Specific issue key (e.g., ISP-1383)') { |v| options[:issue] = v }
  opts.on('--dry-run', 'Preview changes without saving') { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
end.parse!

if options[:project].nil? && options[:issue].nil?
  puts 'ERROR: Either --project or --issue is required'
  puts ''
  puts 'Examples:'
  puts '  Update all ISP defects:      --project ISP'
  puts '  Update specific issue:       --issue ISP-1383'
  puts '  Preview changes (dry run):   --project ISP --dry-run'
  puts '  Verbose output:              --issue ISP-1383 --verbose'
  exit 1
end

# Load configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
if File.exist?(config_path)
  CONFIG = YAML.load_file(config_path).with_indifferent_access
  JIRA_BASE_URL = CONFIG[:jira_base_url]
  JIRA_API_USER = CONFIG[:jira_api_user]
  JIRA_API_TOKEN = CONFIG[:jira_api_token]
  DEFAULT_USER_UUID = CONFIG[:default_user_uuid]
else
  puts 'ERROR: config/jira_import.yml not found'
  exit 1
end

unless JIRA_BASE_URL && JIRA_API_USER && JIRA_API_TOKEN
  puts 'ERROR: Missing Jira configuration in config/jira_import.yml'
  exit 1
end

def info(msg)
  puts msg
end

def vputs(msg)
  puts msg if $verbose_flag
end

$verbose_flag = options[:verbose]

puts ''
puts '=' * 80
puts 'DEFECT USER SYNC FROM JIRA'
puts '=' * 80
puts "Mode: #{options[:dry_run] ? '🔍 DRY RUN (preview only)' : '💾 LIVE UPDATE'}"
puts "Project: #{options[:project] || 'N/A'}"
puts "Issue: #{options[:issue] || 'All issues in project'}"
puts "Verbose: #{options[:verbose]}"
puts ''
puts '🌐 Fetching data from Jira API and comparing with local database'
puts '   Will update creator and assignees if they differ'
puts '=' * 80
puts ''

# ===============================
# JIRA API FETCH
# ===============================

def fetch_jira_issue(issue_key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
  uri = URI.parse(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 30

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    nil
  end
rescue StandardError => e
  vputs "  [ERROR] Exception fetching #{issue_key}: #{e.message}" if $verbose_flag
  nil
end

# ===============================
# INTELLIGENT NAME MATCHING (9-STRATEGY)
# ===============================

def find_user_by_intelligent_match(name_or_email, verbose: false)
  return nil if name_or_email.blank?

  name_str = name_or_email.to_s.strip

  # Strategy 1: Email matching
  if name_str.include?('@')
    email_str = name_str.downcase
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str)
    if user
      vputs "  [1-MATCH-EMAIL] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end

    email_prefix = email_str.split('@').first
    name_str = email_prefix.gsub(/[._-]/, ' ').titleize
    vputs "  [EMAIL→NAME] Converted to: '#{name_str}'" if verbose
  end

  clean_name = name_str.gsub(/[^a-zA-Z\s.]/, ' ').squeeze(' ').strip
  parts = clean_name.split(/\s+/).reject(&:empty?)

  return nil if parts.empty?

  # Strategy 2: Exact full name match (all parts)
  normalized = clean_name.downcase
  user = User.where(deleted_on: nil)
    .where("lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) = ?", normalized)
    .first
  if user
    vputs "  [2-MATCH-EXACT] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
    return user
  end

  # Strategy 3: First part is initial (e.g., "R. mbugua kanyoro")
  if parts.length >= 2
    first_part = parts[0]
    if first_part.length <= 2 && first_part.match?(/^[A-Z]\.?$/i)
      initial = first_part[0].upcase
      rest_name = parts[1..].join(' ')

      user = User.where(deleted_on: nil)
        .where('upper(substring(first_name, 1, 1)) = ? AND lower(last_name) = ?', initial, rest_name.downcase)
        .first

      if user
        vputs "  [3-MATCH-INITIAL] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
        return user
      end
    end
  end

  # Strategy 4: Last part is initial (e.g., "robert mbugua K")
  if parts.length >= 2
    last_part = parts[-1]
    if last_part.length <= 2 && last_part.match?(/^[A-Z]\.?$/i)
      initial = last_part[0].upcase
      rest_name = parts[0..-2].join(' ')

      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? AND upper(substring(last_name, 1, 1)) = ?', rest_name.downcase, initial)
        .first

      if user
        vputs "  [4-MATCH-LAST-INITIAL] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
        return user
      end
    end
  end

  # Strategy 5: Standard first + last (two-part names)
  if parts.length >= 2
    first = parts[0]
    last = parts[1..].join(' ')

    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
      .first
    if user
      vputs "  [5-MATCH-FIRST-LAST] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end

    # Try reversed (last first, rest as first name)
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', last.downcase, first.downcase)
      .first
    if user
      vputs "  [5b-MATCH-REVERSED] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  # Strategy 6: Partial match - first exact, last contains
  if parts.length >= 2
    first = parts[0]
    last_parts = parts[1..].join(' ')

    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) ILIKE ?', first.downcase, "%#{last_parts.downcase}%")
      .first
    if user
      vputs "  [6-MATCH-PARTIAL-LAST] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end

    # Reverse: last exact, first contains
    user = User.where(deleted_on: nil)
      .where('lower(first_name) ILIKE ? AND lower(last_name) = ?', "%#{first.downcase}%", last_parts.downcase)
      .first
    if user
      vputs "  [6b-MATCH-PARTIAL-FIRST] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  # Strategy 7: Multi-part matching (for names like "robert mbugua kanyoro")
  # Try combinations of parts
  if parts.length >= 3
    # Try first two parts as first name, rest as last
    first_combo = parts[0..1].join(' ')
    last_combo = parts[2..].join(' ')

    user = User.where(deleted_on: nil)
      .where('lower(first_name) ILIKE ? AND lower(last_name) ILIKE ?', "%#{first_combo.downcase}%", "%#{last_combo.downcase}%")
      .first
    if user
      vputs "  [7-MATCH-MULTI1] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end

    # Try first part as first, rest as last
    user = User.where(deleted_on: nil)
      .where('lower(first_name) ILIKE ? AND lower(last_name) ILIKE ?', "%#{parts[0].downcase}%", "%#{parts[1..].join(' ').downcase}%")
      .first
    if user
      vputs "  [7-MATCH-MULTI2] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  # Strategy 7b: Match on word combinations - smart matching
  # For "Robert Mbugua Kanyoro" find "Robert Kanyoro" by checking key parts
  if parts.length >= 2
    # Check if first and last words exist in any user's full name
    first_word = parts.first.downcase
    last_word = parts.last.downcase

    # Look for users where both first_word and last_word appear
    User.where(deleted_on: nil).each do |user|
      user_full = "#{user.first_name} #{user.last_name}".downcase
      if user_full.include?(first_word) && user_full.include?(last_word)
        vputs "  [7b-MATCH-KEY-WORDS] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
        return user
      end
    end
  end

  # Strategy 7c: Match on ANY significant word - flexible matching
  # For "Robert Mbugua Kanyoro" find anyone with Robert OR Kanyoro
  best_matches = []

  User.where(deleted_on: nil).each do |user|
    user_full_name = "#{user.first_name} #{user.last_name}".downcase
    user_words = user_full_name.split(/\s+/).reject(&:empty?)

    # Count how many Jira name parts appear in the user's full name
    matched_parts = parts.count { |part| user_words.any? { |word| word.include?(part.downcase) || part.downcase.include?(word) } }

    # If at least 2 parts match (e.g., Robert AND Kanyoro both found)
    best_matches << [user, matched_parts] if matched_parts >= 2 && matched_parts >= (parts.length * 0.5)
  end

  if best_matches.any?
    # Pick the one with most matches
    user = best_matches.max_by { |_, score| score }.first
    vputs "  [7c-MATCH-FLEXIBLE] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
    return user
  end

  # Strategy 8: Single word match
  if parts.length == 1
    single = parts.first.downcase
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? OR lower(last_name) = ?', single, single)
      .first
    if user
      vputs "  [8-MATCH-SINGLE] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  # Strategy 9: STRICT fuzzy match - requires at least 2 exact word matches
  if parts.length >= 2
    best_match = nil
    best_score = 0

    User.where(deleted_on: nil).each do |user|
      user_first = user.first_name.to_s.downcase.split(/\s+/)
      user_last = user.last_name.to_s.downcase.split(/\s+/)
      user_parts = (user_first + user_last).reject(&:empty?)

      next if user_parts.empty?

      # Count exact matches
      exact_matches = parts.count { |p| user_parts.any? { |up| up == p } }

      # Calculate similarity score (exact matches / total parts)
      score = exact_matches.to_f / [parts.length, user_parts.length].max

      # Require at least 2 exact word matches AND 50% similarity
      if exact_matches >= 2 && score >= 0.5 && score > best_score
        best_match = user
        best_score = score
      end
    end

    if best_match
      vputs "  [9-MATCH-STRICT] '#{name_str}' → #{best_match.first_name} #{best_match.last_name} (score: #{(best_score * 100).round}%)" if verbose
      return best_match
    end
  end

  vputs "  [NO-MATCH] ❌ '#{name_str}'" if verbose
  nil
end

# ===============================
# MAIN SYNC LOGIC
# ===============================

stats = {
  total: 0,
  jira_fetch_failed: 0,
  creator_updated: 0,
  assignee_updated: 0,
  no_changes: 0,
  failed: 0,
  changes: []
}

# Build defect query
defect_query = Defect.where.not(defect_unique: nil)

if options[:issue]
  defect_query = defect_query.where(defect_unique: options[:issue])
elsif options[:project]
  defect_query = defect_query.where('defect_unique LIKE ?', "#{options[:project]}-%")
end

defects = defect_query.order(:defect_unique).to_a

if defects.empty?
  puts 'No defects found matching criteria'
  exit 0
end

info "Found #{defects.length} defect(s) to process"
info ''

defects.each_with_index do |defect, idx|
  stats[:total] += 1

  info "[#{idx + 1}/#{defects.length}] 📋 #{defect.defect_unique}"

  begin
    # Fetch from Jira
    jira_data = fetch_jira_issue(defect.defect_unique)

    unless jira_data
      info '  ⚠️  HTTP Error: Could not fetch from Jira'
      stats[:jira_fetch_failed] += 1
      info ''
      next
    end

    # Get reporter (creator)
    jira_reporter = jira_data.dig('fields', 'reporter')
    jira_reporter_name = jira_reporter&.dig('displayName') || jira_reporter&.dig('name') if jira_reporter

    # Get assignee(s)
    jira_assignee = jira_data.dig('fields', 'assignee')
    jira_assignee_name = jira_assignee&.dig('displayName') || jira_assignee&.dig('name') if jira_assignee

    # Get current local values
    local_creator = User.find_by(id: defect.created_by) if defect.created_by
    local_assignees = begin
      defect.users
    rescue StandardError
      []
    end

    local_creator_name = local_creator ? "#{local_creator.first_name} #{local_creator.last_name}" : 'None'
    local_assignee_names = local_assignees.map { |u| "#{u.first_name} #{u.last_name}" }.join(', ')

    any_changes = false

    # ===============================
    # CHECK CREATOR
    # ===============================
    if jira_reporter_name
      vputs "  [JIRA] Reporter: #{jira_reporter_name}" if options[:verbose]
      vputs "  [LOCAL] Creator: #{local_creator_name}" if options[:verbose]

      matched_creator = find_user_by_intelligent_match(jira_reporter_name, verbose: options[:verbose])

      if matched_creator && matched_creator.id != defect.created_by
        info '  📝 Creator mismatch detected:'
        info "     Jira:  #{jira_reporter_name}"
        info "     Local: #{local_creator_name}"
        info "     Match: #{matched_creator.first_name} #{matched_creator.last_name}"

        if options[:dry_run]
          info '     [DRY RUN] Would update'
        else
          defect.created_by = matched_creator.id
          if defect.save
            info '     ✅ Updated'
            stats[:creator_updated] += 1
          else
            info "     ❌ Save failed: #{defect.errors.full_messages.join(', ')}"
            stats[:failed] += 1
          end
        end

        stats[:changes] << {
          issue: defect.defect_unique,
          field: 'creator',
          before: local_creator_name,
          after: "#{matched_creator.first_name} #{matched_creator.last_name}",
          jira_source: jira_reporter_name
        }
        any_changes = true
      elsif matched_creator && matched_creator.id == defect.created_by
        vputs '  ✓ Creator already correct' if options[:verbose]
      elsif jira_reporter_name && !matched_creator
        info "  ⚠️  Could not match Jira reporter: '#{jira_reporter_name}'"
      end
    end

    # ===============================
    # CHECK ASSIGNEES
    # ===============================
    if jira_assignee_name
      vputs "  [JIRA] Assignee: #{jira_assignee_name}" if options[:verbose]
      vputs "  [LOCAL] Assignees: #{local_assignee_names}" if options[:verbose]

      matched_assignee = find_user_by_intelligent_match(jira_assignee_name, verbose: options[:verbose])

      if matched_assignee
        current_assignee_ids = local_assignees.map(&:id)

        if !current_assignee_ids.include?(matched_assignee.id)
          info '  👥 Assignee mismatch detected:'
          info "     Jira:  #{jira_assignee_name}"
          info "     Local: #{local_assignee_names.empty? ? 'None' : local_assignee_names}"
          info "     Match: #{matched_assignee.first_name} #{matched_assignee.last_name}"

          if options[:dry_run]
            info '     [DRY RUN] Would update'
          else
            defect.users = [matched_assignee]
            if defect.save
              info '     ✅ Updated'
              stats[:assignee_updated] += 1
            else
              info "     ❌ Save failed: #{defect.errors.full_messages.join(', ')}"
              stats[:failed] += 1
            end
          end

          stats[:changes] << {
            issue: defect.defect_unique,
            field: 'assignee',
            before: local_assignee_names.empty? ? 'None' : local_assignee_names,
            after: "#{matched_assignee.first_name} #{matched_assignee.last_name}",
            jira_source: jira_assignee_name
          }
          any_changes = true
        elsif current_assignee_ids.include?(matched_assignee.id)
          vputs '  ✓ Assignee already correct' if options[:verbose]
        end
      elsif jira_assignee_name && !matched_assignee
        info "  ⚠️  Could not match Jira assignee: '#{jira_assignee_name}'"
      end
    end

    if !any_changes && (jira_reporter_name || jira_assignee_name)
      vputs '  ✓ No changes needed' if options[:verbose]
      stats[:no_changes] += 1
    end
  rescue StandardError => e
    info "  ❌ Error: #{e.message}"
    info "     #{e.backtrace.first}" if options[:verbose]
    stats[:failed] += 1
  end

  info ''
end

# ===============================
# FINAL REPORT
# ===============================

puts ''
puts '=' * 80
puts 'FINAL REPORT'
puts '=' * 80
puts ''

puts 'Summary:'
puts "  Total defects processed: #{stats[:total]}"
puts "  Jira fetch failed: #{stats[:jira_fetch_failed]}"
puts "  Creator updated: #{stats[:creator_updated]}"
puts "  Assignee updated: #{stats[:assignee_updated]}"
puts "  No changes needed: #{stats[:no_changes]}"
puts "  Failed: #{stats[:failed]}"
puts ''

if stats[:changes].any?
  puts '📋 Detailed Changes:'
  stats[:changes].each do |change|
    puts "  #{change[:issue]} - #{change[:field].upcase}:"
    puts "    From: #{change[:before]} (from #{change[:jira_source]} in Jira)"
    puts "    To:   #{change[:after]}"
  end
  puts ''
end

puts '=' * 80

if options[:dry_run]
  puts ''
  puts '🔍 DRY RUN MODE - No changes were saved'
  puts '   Run without --dry-run to apply changes'
  puts ''
end

puts 'Done!'
puts ''
