#!/usr/bin/env ruby
# scripts/update_defect_user_mappings.rb
#
# This script updates creator (reporter) and assignee fields for defects imported from Jira.
# It uses intelligent name matching to handle:
#   - Initials (e.g., "V. Kaunda" matches "Vincent Kaunda")
#   - Reversed names (e.g., "Kaunda Vincent" matches "Vincent Kaunda")
#   - Partial names (e.g., "Kaunda" matches "Vincent Kaunda")
#   - Email addresses
#   - Dot-separated usernames (e.g., "archana.verma")
#
# Usage:
#   # Update all defects for a project
#   bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP
#
#   # Update a specific issue
#   bundle exec rails runner scripts/update_defect_user_mappings.rb --issue PSP-113
#
#   # Dry run (preview without saving)
#   bundle exec rails runner scripts/update_defect_user_mappings.rb --project KCBL --dry-run
#
#   # Verbose output
#   bundle exec rails runner scripts/update_defect_user_mappings.rb --project ISP --verbose

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
  opts.banner = 'Usage: rails runner scripts/update_defect_user_mappings.rb [options]'

  opts.on('--project KEY', String, 'Jira project key (e.g., PSP, KCBL, ISP)') { |v| options[:project] = v }
  opts.on('--issue KEY', String, 'Specific issue key (e.g., PSP-113)') { |v| options[:issue] = v }
  opts.on('--dry-run', 'Preview changes without saving') { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
end.parse!

if options[:project].nil? && options[:issue].nil?
  puts 'ERROR: Either --project or --issue is required'
  puts ''
  puts 'Examples:'
  puts '  Update all PSP defects:       --project PSP'
  puts '  Update specific issue:        --issue PSP-113'
  puts '  Preview changes (dry run):    --project KCBL --dry-run'
  puts '  Verbose output:               --project ISP --verbose'
  exit 1
end

# Load configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

# Jira API credentials
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user])
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

DEFAULT_USER_UUID = CONFIG[:default_user_uuid]

def info(msg)
  puts msg
end

def vputs(msg)
  puts msg if $verbose_flag
end

$verbose_flag = options[:verbose]

puts ''
puts '=' * 80
puts 'DEFECT USER ASSIGNMENT UPDATER'
puts '=' * 80
puts "Mode: #{options[:dry_run] ? '🔍 DRY RUN (preview only - NO CHANGES SAVED)' : '💾 LIVE UPDATE (changes will be saved)'}"
puts "Project: #{options[:project] || 'N/A'}"
puts "Issue: #{options[:issue] || 'All issues in project'}"
puts "Verbose: #{options[:verbose]}"
puts '=' * 80
puts ''

# ===============================
# INTELLIGENT NAME MATCHING
# ===============================

# Enhanced user matching with support for:
# - Initials (e.g., "V. Kaunda" → "Vincent Kaunda")
# - Reversed names (e.g., "Kaunda Vincent" → "Vincent Kaunda")
# - Partial names (e.g., "Kaunda" → "Vincent Kaunda")
# - Email addresses
# - Dot-separated usernames (e.g., "archana.verma")
# - Case-insensitive matching
def find_user_by_intelligent_match(name_or_email, verbose: false)
  return nil if name_or_email.blank?

  name_str = name_or_email.to_s.strip

  # STRATEGY 1: Email matching
  if name_str.include?('@')
    email_str = name_str.downcase
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str)
    if user
      vputs "  [MATCH-EMAIL] '#{name_str}' → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end

    # Try extracting name from email prefix
    email_prefix = email_str.split('@').first
    name_str = email_prefix.gsub(/[._-]/, ' ').titleize
    vputs "  [EMAIL→NAME] Converted '#{name_or_email}' → '#{name_str}'" if verbose
  end

  # Clean up the name (remove special chars, normalize spaces)
  clean_name = name_str.gsub(/[^a-zA-Z\s.]/, ' ').squeeze(' ').strip
  parts = clean_name.split(/\s+/)

  # STRATEGY 2: Exact full name match (case-insensitive)
  normalized = clean_name.downcase
  user = User.where(deleted_on: nil)
    .where("lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) = ?", normalized)
    .first
  if user
    vputs "  [MATCH-EXACT] '#{name_str}' → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
    return user
  end

  # STRATEGY 3: Handle initials
  # Example: "V. Kaunda" or "V Kaunda" → matches "Vincent Kaunda"
  if parts.length >= 2
    first_part = parts[0]
    rest_parts = parts[1..]

    # Check if first part is an initial (single letter or letter + period)
    if first_part.length <= 2 && first_part.match?(/^[A-Z]\.?$/i)
      initial = first_part[0].upcase
      last_name = rest_parts.join(' ')

      # Find users where first_name starts with initial and last_name matches
      user = User.where(deleted_on: nil)
        .where('upper(substring(first_name, 1, 1)) = ? AND lower(last_name) = ?', initial, last_name.downcase)
        .first

      if user
        vputs "  [MATCH-INITIAL-FIRST] '#{name_str}' (initial '#{initial}' + '#{last_name}') → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
        return user
      end
    end

    # Check if last part is an initial
    # Example: "Kaunda V." → matches "Kaunda Vincent"
    last_part = parts[-1]
    first_parts = parts[0..-2]

    if last_part.length <= 2 && last_part.match?(/^[A-Z]\.?$/i)
      initial = last_part[0].upcase
      first_name = first_parts.join(' ')

      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? AND upper(substring(last_name, 1, 1)) = ?', first_name.downcase, initial)
        .first

      if user
        vputs "  [MATCH-INITIAL-LAST] '#{name_str}' ('#{first_name}' + initial '#{initial}') → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
        return user
      end
    end
  end

  # STRATEGY 4: Standard first + last name split
  if parts.length >= 2
    first = parts.first
    last = parts[1..].join(' ')

    # Exact first + last match
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
      .first
    if user
      vputs "  [MATCH-FIRST-LAST] '#{name_str}' → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end

    # Try reversed (last first)
    # Example: "Kaunda Vincent" → matches "Vincent Kaunda"
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', last.downcase, first.downcase)
      .first
    if user
      vputs "  [MATCH-REVERSED] '#{name_str}' (reversed to '#{last} #{first}') → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end

    # Partial match: first name exact, last name starts with provided
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) LIKE ?', first.downcase, "#{last.downcase}%")
      .first
    if user
      vputs "  [MATCH-PARTIAL-LAST] '#{name_str}' (partial '#{first}' + '#{last}%') → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end

    # Partial match: last name exact, first name starts with provided
    user = User.where(deleted_on: nil)
      .where('lower(last_name) = ? AND lower(first_name) LIKE ?', last.downcase, "#{first.downcase}%")
      .first
    if user
      vputs "  [MATCH-PARTIAL-FIRST] '#{name_str}' (partial '#{first}%' + '#{last}') → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end
  end

  # STRATEGY 5: Single name - match first OR last name
  if parts.length == 1
    single = parts.first.downcase
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? OR lower(last_name) = ?', single, single)
      .first
    if user
      vputs "  [MATCH-SINGLE] '#{name_str}' → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end
  end

  # STRATEGY 6: Fuzzy match - find users containing all name parts
  # Example: "Kaunda V" might match "Vincent Kaunda" if other strategies failed
  if parts.length >= 2
    # Build query matching users where ALL parts appear in first_name or last_name
    conditions = parts.map do |part|
      sanitized_part = ActiveRecord::Base.connection.quote_string(part.downcase)
      "(lower(first_name) LIKE '%#{sanitized_part}%' OR lower(last_name) LIKE '%#{sanitized_part}%')"
    end.join(' AND ')

    users = User.where(deleted_on: nil).where(conditions).to_a

    # If exactly one match, use it
    if users.length == 1
      user = users.first
      vputs "  [MATCH-FUZZY] '#{name_str}' (fuzzy match) → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    elsif users.length > 1
      vputs "  [MATCH-FUZZY-AMBIGUOUS] '#{name_str}' matched #{users.length} users - skipping to avoid ambiguity" if verbose
    end
  end

  vputs "  [NO-MATCH] ❌ Could not match '#{name_str}'" if verbose
  nil
end

# ===============================
# JIRA API INTEGRATION
# ===============================

def fetch_jira_issue(issue_key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
  uri = URI.parse(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    warn "  ⚠️  HTTP #{response.code}: #{response.message}"
    nil
  end
rescue StandardError => e
  warn "  ⚠️  Failed to fetch from Jira: #{e.message}"
  nil
end

# ===============================
# MAIN UPDATE LOGIC
# ===============================

# Track statistics
stats = {
  total: 0,
  updated_creator: 0,
  updated_assignee: 0,
  no_change_needed: 0,
  failed: 0,
  skipped_jira_fetch_failed: 0,
  creator_matches: Hash.new(0),
  creator_no_matches: Hash.new(0),
  creator_before_after: {},
  assignee_matches: Hash.new(0),
  assignee_no_matches: Hash.new(0),
  assignee_before_after: {}
}

# Build defect query
defect_query = Defect.where.not(defect_unique: nil)

if options[:issue]
  # Specific issue
  defect_query = defect_query.where(defect_unique: options[:issue])
elsif options[:project]
  # All issues for project (e.g., PSP-%)
  defect_query = defect_query.where('defect_unique LIKE ?', "#{options[:project]}-%")
end

defects = defect_query.order(:defect_unique).to_a

if defects.empty?
  puts 'No defects found matching criteria'
  puts ''
  puts 'Check that:'
  puts '  - The project key is correct'
  puts '  - Defects have been imported with defect_unique values'
  exit 0
end

info "Found #{defects.length} defect(s) to process"
info ''

defects.each_with_index do |defect, idx|
  stats[:total] += 1

  info "[#{idx + 1}/#{defects.length}] 📋 #{defect.defect_unique}"

  begin
    # Fetch issue from Jira
    jira_data = fetch_jira_issue(defect.defect_unique)

    unless jira_data
      warn '  ⚠️  Could not fetch from Jira - skipping'
      stats[:skipped_jira_fetch_failed] += 1
      info ''
      next
    end

    fields = jira_data['fields'] || {}

    # Get reporter (creator in TaskBridge)
    reporter_data = fields['reporter'] || {}
    reporter_name = reporter_data['displayName'].to_s.strip
    reporter_email = reporter_data['emailAddress'].to_s.strip

    # Get assignee
    assignee_data = fields['assignee'] || {}
    assignee_name = assignee_data['displayName'].to_s.strip
    assignee_email = assignee_data['emailAddress'].to_s.strip

    # Current state
    current_creator_id = begin
      defect.creator_id
    rescue StandardError
      nil
    end
    current_creator = User.find_by(id: current_creator_id) if current_creator_id
    current_assignees = begin
      defect.users.to_a
    rescue StandardError
      []
    end

    creator_changed = false
    assignee_changed = false
    changes_made = false

    # === UPDATE CREATOR (REPORTER) ===
    if reporter_name.present? || reporter_email.present?
      search_str = reporter_email.present? ? reporter_email : reporter_name
      matched_creator = find_user_by_intelligent_match(search_str, verbose: options[:verbose])

      if matched_creator
        if current_creator_id == matched_creator.id
          current_name = "#{matched_creator.first_name} #{matched_creator.last_name}"
          vputs "  ✓ Creator already correct: #{current_name} (ID: #{matched_creator.id})" if options[:verbose]
          stats[:no_change_needed] += 1
        else
          current_name = current_creator ? "#{current_creator.first_name} #{current_creator.last_name}" : 'None'
          new_name = "#{matched_creator.first_name} #{matched_creator.last_name}"

          info "  📝 Creator: '#{reporter_name}' → #{new_name}"
          info "     Before: #{current_name} (ID: #{current_creator_id})"
          info "     After:  #{new_name} (ID: #{matched_creator.id})"

          stats[:creator_before_after][defect.defect_unique] = {
            jira_name: reporter_name,
            before: current_name,
            before_id: current_creator_id,
            after: new_name,
            after_id: matched_creator.id
          }

          if options[:dry_run]
            info '     [DRY RUN] Would update created_by'
          else
            defect.created_by = matched_creator.id
            creator_changed = true
            changes_made = true
          end

          stats[:updated_creator] += 1
          stats[:creator_matches][reporter_name] += 1
        end
      else
        info "  ⚠️  No match for creator: '#{reporter_name}'"
        stats[:creator_no_matches][reporter_name] += 1
      end
    end

    # === UPDATE ASSIGNEE ===
    if assignee_name.present? || assignee_email.present?
      search_str = assignee_email.present? ? assignee_email : assignee_name
      matched_assignee = find_user_by_intelligent_match(search_str, verbose: options[:verbose])

      if matched_assignee
        # Check if already assigned
        already_assigned = current_assignees.any? { |u| u.id == matched_assignee.id }

        if already_assigned
          vputs "  ✓ Assignee already correct: #{matched_assignee.first_name} #{matched_assignee.last_name}" if options[:verbose]
          stats[:no_change_needed] += 1
        else
          current_names = current_assignees.map { |u| "#{u.first_name} #{u.last_name}" }.join(', ')
          current_names = 'None' if current_names.blank?
          new_name = "#{matched_assignee.first_name} #{matched_assignee.last_name}"

          info "  👤 Assignee: '#{assignee_name}' → #{new_name}"
          info "     Before: #{current_names}"
          info "     After:  #{new_name} (added)"

          stats[:assignee_before_after][defect.defect_unique] = {
            jira_name: assignee_name,
            before: current_names,
            after: new_name,
            after_id: matched_assignee.id
          }

          if options[:dry_run]
            info '     [DRY RUN] Would add assignee'
          else
            defect.users << matched_assignee unless defect.users.include?(matched_assignee)
            assignee_changed = true
            changes_made = true
          end

          stats[:updated_assignee] += 1
          stats[:assignee_matches][assignee_name] += 1
        end
      else
        info "  ⚠️  No match for assignee: '#{assignee_name}'"
        stats[:assignee_no_matches][assignee_name] += 1
      end
    end

    # Save changes
    if !options[:dry_run] && changes_made
      if defect.save
        info '  ✅ Changes saved'
      else
        warn "  ❌ Failed to save: #{defect.errors.full_messages.join(', ')}"
        stats[:failed] += 1
      end
    elsif changes_made
      info '  🔍 [DRY RUN] Changes previewed (not saved)'
    end
  rescue StandardError => e
    warn "  ❌ Error processing #{defect.defect_unique}: #{e.message}"
    warn "     #{e.backtrace.first(3).join("\n     ")}" if options[:verbose]
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
puts "  Creators updated: #{stats[:updated_creator]}"
puts "  Assignees updated: #{stats[:updated_assignee]}"
puts "  No change needed: #{stats[:no_change_needed]}"
puts "  Skipped (Jira fetch failed): #{stats[:skipped_jira_fetch_failed]}"
puts "  Failed: #{stats[:failed]}"
puts ''

if stats[:creator_matches].any?
  puts "✅ Creator Names Successfully Matched (#{stats[:creator_matches].keys.length} unique):"
  stats[:creator_matches].sort_by { |name, count| -count }.each do |name, count|
    puts "  ✓ '#{name}' (#{count} occurrence#{'s' if count > 1})"
  end
  puts ''
end

if stats[:creator_no_matches].any?
  puts "❌ Creator Names That Could NOT Be Matched (#{stats[:creator_no_matches].keys.length} unique):"
  stats[:creator_no_matches].sort_by { |name, count| -count }.each do |name, count|
    puts "  ✗ '#{name}' (#{count} occurrence#{'s' if count > 1})"
  end
  puts ''
  puts '  💡 Tip: These names may need to be added manually to TaskBridge,'
  puts '          or check for typos in the user records.'
  puts ''
end

if stats[:assignee_matches].any?
  puts "✅ Assignee Names Successfully Matched (#{stats[:assignee_matches].keys.length} unique):"
  stats[:assignee_matches].sort_by { |name, count| -count }.each do |name, count|
    puts "  ✓ '#{name}' (#{count} occurrence#{'s' if count > 1})"
  end
  puts ''
end

if stats[:assignee_no_matches].any?
  puts "❌ Assignee Names That Could NOT Be Matched (#{stats[:assignee_no_matches].keys.length} unique):"
  stats[:assignee_no_matches].sort_by { |name, count| -count }.each do |name, count|
    puts "  ✗ '#{name}' (#{count} occurrence#{'s' if count > 1})"
  end
  puts ''
end

# Detailed change log
if stats[:creator_before_after].any?
  puts '📋 Detailed Creator Changes:'
  stats[:creator_before_after].each do |issue_key, change|
    puts "  #{issue_key}:"
    puts "    Jira name: '#{change[:jira_name]}'"
    puts "    Before: #{change[:before]} (ID: #{change[:before_id]})"
    puts "    After:  #{change[:after]} (ID: #{change[:after_id]})"
  end
  puts ''
end

if stats[:assignee_before_after].any?
  puts '📋 Detailed Assignee Changes:'
  stats[:assignee_before_after].each do |issue_key, change|
    puts "  #{issue_key}:"
    puts "    Jira name: '#{change[:jira_name]}'"
    puts "    Before: #{change[:before]}"
    puts "    After:  #{change[:after]} (ID: #{change[:after_id]})"
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
