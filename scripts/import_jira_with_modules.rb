#!/usr/bin/env ruby
# scripts/import_jira_with_modules.rb

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'optparse'
require 'yaml'
require 'base64'
require 'cgi'

APP_ROOT = Rails.root

options = {
  dry_run: false,
  verbose: false,
  projects: [],
  days_back: 2000
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/import_jira_with_modules.rb --project PROJECT_KEY [options]'

  opts.on('--project KEY1,KEY2,...', Array, 'Jira project key(s) (e.g. PSP or PSP,KCBL,FLOW)') { |v| options[:projects] = v }
  opts.on('--dry-run', "Don't save; only show what would happen") { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
  opts.on('--days N', Integer, 'How many days back to fetch (default 2000)') { |v| options[:days_back] = v }
end.parse!

if options[:projects].empty?
  puts 'ERROR: --project is required. Examples:'
  puts '  Single project:   --project PSP'
  puts '  Multiple projects: --project PSP,KCBL,FLOW'
  exit 1
end

config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

# Jira credentials - use from environment variables or config
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

# Configuration
PROJECT_UUID_MAP = CONFIG[:project_uuid_map] || {}
USER_UUID_MAP = CONFIG[:user_map] || {}
STATUS_UUID_MAP = CONFIG[:status_map] || {}
DEFAULT_PRODUCT_UUID = CONFIG[:default_product_id]
DEFAULT_USER_UUID = CONFIG[:default_user_uuid]
DEFAULT_CREATED_BY = CONFIG[:default_created_by] || DEFAULT_USER_UUID
CREATE_MISSING_USERS = CONFIG.fetch(:create_missing_users, true)
CREATE_MISSING_STATUSES = CONFIG.fetch(:create_missing_statuses, true)
CREATE_MISSING_LABELS = CONFIG.fetch(:create_missing_labels, true)
CREATE_MISSING_MODULES = CONFIG.fetch(:create_missing_modules, true)
CREATE_MISSING_BANKING = CONFIG.fetch(:create_missing_banking_types, true)

FALLBACK_QA_MODULE_ID = CONFIG[:fallback_qa_module_id]
FALLBACK_SUBMODULE_ID = CONFIG[:fallback_submodule_id]
FALLBACK_BANKING_TYPE_ID = CONFIG[:fallback_banking_type_id]
DEFAULT_PRIORITY = CONFIG[:default_priority] || 'Severity 4'

def info(msg)
  puts msg
end

def vputs(msg)
  puts msg if $verbose_flag
end

$verbose_flag = options[:verbose]

# Global tracking for user match statistics
$USER_STATS = {
  total_lookups: 0,
  email_matches: 0,
  full_name_matches: 0,
  first_last_matches: 0,
  partial_matches: 0,
  config_map_matches: 0,
  created_users: 0,
  fallback_users: 0,
  matched_users: Set.new,      # Set of user IDs successfully matched
  fallback_users_set: Set.new,  # Set of user IDs that fell back to default
  not_found_names: Hash.new(0), # Names that couldn't be matched
  parsed_names: {},             # Track parsed names for reporting
  reporter_matches: {},         # Track reporter matches per issue
  assignee_matches: {}          # Track assignee matches per issue
}

project_list = options[:projects].map(&:strip).reject(&:empty?)

# Debug output to verify projects are parsed correctly
puts "DEBUG: Parsed projects from command line: #{options[:projects].inspect}"
puts "DEBUG: Cleaned project list: #{project_list.inspect}"

if project_list.empty?
  puts 'ERROR: No valid projects found after parsing. Check your --project argument.'
  puts "  Received: #{options[:projects].inspect}"
  exit 1
end

info "Starting direct Jira import with modules for project(s): #{project_list.join(', ')} (dry_run: #{options[:dry_run]})"

# ===============================
# CUSTOM FIELD DISCOVERY
# ===============================
def discover_custom_fields
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)

  vputs 'Discovering custom fields...'

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    warn "❌ Failed to fetch custom fields: #{response.code} #{response.message}"
    return nil, nil, nil
  end

  fields = JSON.parse(response.body)

  module_field = nil
  submodule_field = nil
  banking_type_field = nil

  fields.each do |field|
    name = field['name']&.downcase || ''
    field_id = field['id']

    if name.include?('module') && !name.include?('sub')
      module_field = field_id
      vputs "Found Module field: #{field_id} - #{field['name']}"
    elsif name.include?('submodule') || (name.include?('module') && name.include?('sub'))
      submodule_field = field_id
      vputs "Found Submodule field: #{field_id} - #{field['name']}"
    elsif name.include?('banking') && name.include?('type')
      banking_type_field = field_id
      vputs "Found Banking Type field: #{field_id} - #{field['name']}"
    end
  end

  [module_field, submodule_field, banking_type_field]
end

# ===============================
# JIRA API FETCHER - WITH MODULE FIELDS
# ===============================
def fetch_jira_issues_with_modules(project_keys:, max_results: 100, days_back: 2000)
  # First discover custom fields
  module_field, submodule_field, banking_type_field = discover_custom_fields

  issues = []
  next_page_token = nil
  page_count = 0
  max_pages = 500

  start_date = (Time.now - (days_back * 24 * 60 * 60)).strftime('%Y-%m-%d')
  end_date = Time.now.strftime('%Y-%m-%d')

  # Build JQL for multiple projects using IN operator
  project_clause = if project_keys.length == 1
                     "project = \"#{project_keys.first}\""
                   else
                     "project IN (#{project_keys.map { |p| "\"#{p}\"" }.join(', ')})"
                   end

  jql_query = "#{project_clause} AND created >= \"#{start_date}\" ORDER BY created DESC"

  info "Fetching Jira issues with JQL: #{jql_query}"
  info "Date range: #{start_date} to #{end_date}"
  info "Projects: #{project_keys.join(', ')}"
  puts "DEBUG: Project keys received: #{project_keys.inspect}"
  puts "DEBUG: Project clause: #{project_clause}"
  puts "DEBUG: Full JQL: #{jql_query}"

  # Build fields list
  fields_to_fetch = %w[key summary status reporter assignee created updated
                       description project comment priority issuetype parent epic attachment labels]

  # Add custom fields if found
  fields_to_fetch << module_field if module_field
  fields_to_fetch << submodule_field if submodule_field
  fields_to_fetch << banking_type_field if banking_type_field

  loop do
    page_count += 1

    if page_count > max_pages
      warn "Reached maximum page limit (#{max_pages}). Stopping pagination."
      break
    end

    # Build query parameters
    query_params = {
      jql: jql_query,
      maxResults: max_results,
      fields: fields_to_fetch.join(',')
    }

    query_params[:nextPageToken] = next_page_token if next_page_token.present?

    uri = URI.parse("#{JIRA_BASE_URL}/rest/api/3/search/jql")
    uri.query = URI.encode_www_form(query_params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120 # Increased from 60 to 120 seconds for large datasets
    http.open_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    vputs "Page #{page_count}: Requesting with nextPageToken=#{next_page_token.present? ? next_page_token[0..20] + '...' : 'nil'}" if $verbose_flag

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      warn "❌ Failed to fetch from Jira: #{response.code} #{response.message}"
      warn "Response body: #{response.body[0..500]}"
      break
    end

    data = JSON.parse(response.body)
    fetched = data['issues'] || []

    if fetched.empty?
      info "✓ Page #{page_count}: No issues returned - pagination complete (no more data)"
      break
    end

    issues.concat(fetched)
    total_fetched = issues.length

    next_page_token = data['nextPageToken']
    is_last_page = data['isLast'] == true

    info "✓ Page #{page_count}: Fetched #{fetched.length} issues (total collected: #{total_fetched}) [isLast: #{is_last_page}, hasNextToken: #{next_page_token.present? ? 'YES' : 'NO'}]"

    if is_last_page
      info '✓ Jira indicates last page (isLast: true) - pagination complete'
      break
    end

    unless next_page_token.present?
      info '✓ No nextPageToken provided - reached end of results'
      break
    end

    sleep 1.0 # Increased delay between pages to avoid rate limiting
  end

  info "📊 Total issues fetched from Jira: #{issues.length} (across #{page_count} pages)"

  # Return both issues and discovered field IDs
  {
    issues: issues,
    module_field: module_field,
    submodule_field: submodule_field,
    banking_type_field: banking_type_field
  }
end

# ===============================
# HELPER METHODS
# ===============================
def try_parse_time(val)
  return nil if val.nil? || val.to_s.strip.empty?

  begin
    Time.parse(val)
  rescue StandardError
    nil
  end
end

# ===============================
# ENHANCED NAME PARSING HELPERS
# ===============================
# Parse Jira displayName into first_name and last_name components
# Handles formats like:
#   "Eva Karimi Njagi" -> first: "Eva", last: "Karimi" (use first 2 parts)
#   "archana.verma" -> first: "archana", last: "verma" (split by dot)
#   "John Smith" -> first: "John", last: "Smith" (standard split)
def parse_jira_name(full_name)
  return { first_name: nil, last_name: nil } if full_name.blank?

  name_str = full_name.to_s.strip

  # STRATEGY 1: Check for dot-separated format (e.g., "archana.verma")
  if name_str.include?('.')
    parts = name_str.split('.')
    if parts.length >= 2
      first = parts[0].strip.presence
      last = parts[1].strip.presence
      if first && last
        $USER_STATS[:parsed_names][name_str] = { strategy: 'dot-separated', first_name: first, last_name: last }
        return { first_name: first, last_name: last }
      end
    end
  end

  # STRATEGY 2: Check for multi-part name (3+ parts) - generate multiple parsing strategies
  # Example: "Eva Karimi Njagi" -> try first: "Eva", last: "Karimi"
  # Then try "Eva" + "Njagi", then "Karimi" + "Njagi", etc.
  parts = name_str.split(/\s+/).reject(&:empty?)

  if parts.length >= 3
    # Generate list of name combinations to try, in priority order:
    # 1. First + Second (original strategy)
    # 2. First + Third (if 3+ parts)
    # 3. Second + Last (if 3+ parts)
    # 4. First + Last (if 4+ parts)
    combinations = [
      [parts[0], parts[1]],  # First + Second
      parts.length >= 3 ? [parts[0], parts[2]] : nil,  # First + Third
      parts.length >= 3 ? [parts[1], parts[-1]] : nil,  # Second + Last
      parts.length >= 4 ? [parts[0], parts[-1]] : nil,  # First + Last
    ].compact

    # Return all combinations as a special marker for later use
    $USER_STATS[:parsed_names][name_str] = {
      strategy: 'multi-part-combinations',
      combinations: combinations.map { |combo| { first_name: combo[0], last_name: combo[1] } }
    }
    return { first_name: parts[0], last_name: parts[1], combinations: combinations }
  end

  # STRATEGY 3: Standard split (2 parts or less)
  if parts.length >= 2
    first = parts[0].strip.presence
    last = parts[1..-1].map(&:strip).join(' ').presence
    if first && last
      $USER_STATS[:parsed_names][name_str] = { strategy: 'standard-split', first_name: first, last_name: last }
      return { first_name: first, last_name: last }
    end
  end

  # STRATEGY 4: Single part - treat as first name only
  if parts.length == 1
    first = parts[0].strip.presence
    if first
      $USER_STATS[:parsed_names][name_str] = { strategy: 'single-part', first_name: first, last_name: nil }
      return { first_name: first, last_name: nil }
    end
  end

  $USER_STATS[:parsed_names][name_str] = { strategy: 'failed-parse', first_name: nil, last_name: nil }
  { first_name: nil, last_name: nil }
end

# Helper function to try matching a first+last name combination
# Tries exact match, then partial matches (first exact + last prefix, or vice versa)
def try_match_user_combination(first_name, last_name)
  return nil if first_name.blank? || last_name.blank?

  # Try exact first + last name match (case-insensitive)
  user = User.where(deleted_on: nil)
    .where('lower(first_name) = ? AND lower(last_name) = ?', first_name.downcase, last_name.downcase)
    .first
  return user if user

  # Try partial match: first name exact, last name prefix
  user = User.where(deleted_on: nil)
    .where('lower(first_name) = ? AND lower(last_name) LIKE ?', first_name.downcase, "#{last_name.downcase}%")
    .first
  return user if user

  # Try reverse: last name exact, first name prefix
  user = User.where(deleted_on: nil)
    .where('lower(last_name) = ? AND lower(first_name) LIKE ?', last_name.downcase, "#{first_name.downcase}%")
    .first
  return user if user

  nil
end

def find_user_by_name_or_map(name, email = nil, verbose: false)
  $USER_STATS[:total_lookups] += 1

  name_str = name.to_s.strip
  email_str = email.to_s.strip

  return nil if name_str.blank? && email_str.blank?

  # PRIORITY 1: Try email lookup (most reliable identifier)
  if email_str.present? && email_str.downcase != 'restricted'
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str.downcase)
    if user
      $USER_STATS[:email_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by email: #{email_str} -> #{user.id}" if verbose
      return user
    end
  end

  # PRIORITY 2: Parse name using enhanced parsing (handles dot-separated and multi-part)
  parsed = parse_jira_name(name_str)
  parsed_first = parsed[:first_name]
  parsed_last = parsed[:last_name]
  combinations = parsed[:combinations]  # For multi-part names, this contains multiple name combinations to try

  # For multi-part names with combinations, try each combination in priority order
  if combinations.present?
    combinations.each do |combo|
      combo_first = combo[0].strip
      combo_last = combo[1].strip
      user = try_match_user_combination(combo_first, combo_last)
      if user
        $USER_STATS[:first_last_matches] += 1
        $USER_STATS[:matched_users] << user.id
        strategy_desc = "#{combo_first}+#{combo_last}"
        vputs "[USER-MATCH] Matched '#{name_str}' by parsed first+last (#{strategy_desc}): #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end
    end
  elsif parsed_first && parsed_last
    # Standard two-part name matching
    user = try_match_user_combination(parsed_first, parsed_last)
    if user
      $USER_STATS[:first_last_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by parsed first+last: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
      return user
    end
  elsif parsed_first
    # Only first name available - try single name match
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? OR lower(last_name) = ?', parsed_first.downcase, parsed_first.downcase)
      .first
    if user
      $USER_STATS[:partial_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by single name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
      return user
    end
  end

  # PRIORITY 3: Try dynamic first_name + last_name matching from Jira displayName (backward compat)
  if name_str.present?
    # Try exact full name match (case-insensitive)
    normalized = name_str.downcase
    user = User.where(deleted_on: nil)
      .where("lower(coalesce(first_name,'') || ' ' || coalesce(last_name,'')) = ?", normalized)
      .first
    if user
      $USER_STATS[:full_name_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by full name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
      return user
    end

    # Try splitting name into first and last parts for individual matching
    parts = name_str.split
    if parts.length >= 2
      first = parts.first
      last = parts[1..].join(' ')

      # Exact first + last name match (case-insensitive)
      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
        .first
      if user
        $USER_STATS[:first_last_matches] += 1
        $USER_STATS[:matched_users] << user.id
        vputs "[USER-MATCH] Matched '#{name_str}' by first+last name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end

      # Try partial match: first name matches and last name starts with provided last name
      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? AND lower(last_name) LIKE ?', first.downcase, "#{last.downcase}%")
        .first
      if user
        $USER_STATS[:partial_matches] += 1
        $USER_STATS[:matched_users] << user.id
        vputs "[USER-MATCH] Matched '#{name_str}' by partial last name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end

      # Try reverse: last name matches and first name matches
      user = User.where(deleted_on: nil)
        .where('lower(last_name) = ? AND lower(first_name) LIKE ?', last.downcase, "#{first.downcase}%")
        .first
      if user
        $USER_STATS[:partial_matches] += 1
        $USER_STATS[:matched_users] << user.id
        vputs "[USER-MATCH] Matched '#{name_str}' by partial first name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end
    elsif parts.length == 1
      # Single name provided - try matching against first name or last name
      single = parts.first.downcase
      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? OR lower(last_name) = ?', single, single)
        .first
      if user
        $USER_STATS[:partial_matches] += 1
        $USER_STATS[:matched_users] << user.id
        vputs "[USER-MATCH] Matched '#{name_str}' by single name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end
    end
  end

  # PRIORITY 4: Fallback to explicit config map (optional override)
  if USER_UUID_MAP[name_str]
    uid = USER_UUID_MAP[name_str]
    user = User.find_by(id: uid)
    if user
      $USER_STATS[:config_map_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by config map -> #{user.id}" if verbose
      return user
    end
  end

  # Try downcased map key
  if USER_UUID_MAP[name_str.downcase]
    uid = USER_UUID_MAP[name_str.downcase]
    user = User.find_by(id: uid)
    if user
      $USER_STATS[:config_map_matches] += 1
      $USER_STATS[:matched_users] << user.id
      vputs "[USER-MATCH] Matched '#{name_str}' by config map (lowercase) -> #{user.id}" if verbose
      return user
    end
  end

  # PRIORITY 5: Optionally create new user if allowed
  if CREATE_MISSING_USERS && email_str.present? && email_str.downcase != 'restricted'
    # Use parsed names if available, otherwise fall back to simple split
    if parsed_first
      first_name = parsed_first
      last_name = parsed_last || 'User'
    else
      parts = name_str.split(' ')
      first_name = parts.first || 'Imported'
      last_name = parts[1..]&.join(' ') || 'User'
    end

    attrs = {
      email: email_str.downcase,
      first_name: first_name,
      last_name: last_name,
      created_by: DEFAULT_CREATED_BY,
      modified_by: DEFAULT_CREATED_BY
    }
    created = User.create(attrs)
    if created.persisted?
      $USER_STATS[:created_users] += 1
      $USER_STATS[:matched_users] << created.id
      vputs "[USER-CREATE] Created new user '#{name_str}' (#{email_str}) with first='#{first_name}', last='#{last_name}' -> #{created.id}" if verbose
      return created
    end
  end

  # PRIORITY 6: Final fallback to default user
  default_user = User.find_by(id: DEFAULT_USER_UUID)
  $USER_STATS[:fallback_users] += 1
  $USER_STATS[:fallback_users_set] << DEFAULT_USER_UUID if default_user
  $USER_STATS[:not_found_names][name_str] += 1
  vputs "[USER-FALLBACK] Using default user for '#{name_str}' -> #{DEFAULT_USER_UUID}" if verbose
  default_user
end

def find_or_create_label(name, created_by:, verbose: false)
  return nil if name.blank?

  normalized = name.strip

  # Label model normalizes names (lowercase, spaces->hyphens, strip special chars)
  # So we search using the normalized form
  search_name = normalized.downcase.gsub(/\s+/, '-').gsub(/-+/, '-')

  # Try to find existing label by normalized name (case-insensitive)
  label = Label.where('lower(name) = ?', search_name).first
  if label
    vputs "[LABEL-MATCH] Found existing label '#{normalized}' (stored as '#{label.name}') -> #{label.id}" if verbose
    return label
  end

  # Create new label if allowed
  return nil unless CREATE_MISSING_LABELS

  begin
    # Label model will normalize the name automatically via before_validation callback
    label = Label.new(name: normalized, created_by: created_by, modified_by: created_by)

    if label.save
      vputs "[LABEL-CREATE] Created new label '#{normalized}' (stored as '#{label.name}') -> #{label.id}" if verbose
      label
    else
      vputs "[LABEL-ERROR] Failed to create label '#{normalized}': #{label.errors.full_messages.join(', ')}" if verbose
      nil
    end
  rescue ActiveRecord::RecordInvalid => e
    vputs "[LABEL-ERROR] Validation error creating label '#{normalized}': #{e.message}" if verbose
    nil
  rescue StandardError => e
    vputs "[LABEL-ERROR] Exception creating label '#{normalized}': #{e.class}: #{e.message}" if verbose
    nil
  end
end

# Attach labels to a defect; creates missing labels if configured
def attach_labels_to_defect(defect, labels_array, created_by:, verbose: false)
  return if labels_array.nil? || labels_array.empty?

  vputs "[LABEL] Processing #{labels_array.length} label(s) for #{defect.defect_unique}" if verbose && labels_array.any?

  labels_array.each do |label_name|
    next if label_name.blank?

    begin
      label = find_or_create_label(label_name, created_by: created_by, verbose: verbose)

      unless label
        vputs "[LABEL-SKIP] Could not find or create label '#{label_name}' for #{defect.defect_unique}" if verbose
        next
      end

      # Skip if already attached
      if defect.labels.exists?(label.id)
        vputs "[LABEL-SKIP] Label '#{label.name}' already attached to #{defect.defect_unique}" if verbose
        next
      end

      # Attach label to defect (creates entry in defect_labels join table)
      defect.labels << label

      # Verify the attachment was successful
      if defect.labels.exists?(label.id)
        # Update audit fields on the join table record if needed
        join_record = defect.defect_labels.find_by(label_id: label.id)
        join_record.update_columns(created_by: created_by, modified_by: created_by) if join_record && join_record.respond_to?(:created_by=)

        vputs "[LABEL-ATTACH] Successfully attached label '#{label.name}' (ID: #{label.id}) to #{defect.defect_unique}" if verbose
      elsif verbose
        vputs "[LABEL-ERROR] Failed to attach label '#{label.name}' to #{defect.defect_unique} (attachment not verified)"
      end
    rescue StandardError => e
      vputs "[LABEL-ERROR] Exception attaching label '#{label_name}' to #{defect.defect_unique}: #{e.class}: #{e.message}" if verbose
      next
    end
  end

  vputs "[LABEL] Completed processing labels for #{defect.defect_unique}. Total attached: #{defect.labels.count}" if verbose
end

def find_or_create_status(name, created_by:, verbose: false)
  return nil if name.blank?

  name_str = name.to_s.strip

  # PRIORITY 1: Dynamic name matching (case-insensitive)
  # Try exact name match first
  status = Status.where('lower(name) = ?', name_str.downcase).first
  if status
    vputs "[STATUS-MATCH] Matched status '#{name_str}' by name: #{status.name} -> #{status.id}" if verbose
    return status
  end

  # Try partial name matching for common variations
  # e.g., "In Progress" matches "In-Progress" or "InProgress"
  normalized_search = name_str.downcase.gsub(/[\s\-_]+/, '')
  status = Status.all.find do |s|
    s.name.downcase.gsub(/[\s\-_]+/, '') == normalized_search
  end
  if status
    vputs "[STATUS-MATCH] Matched status '#{name_str}' by normalized name: #{status.name} -> #{status.id}" if verbose
    return status
  end

  # PRIORITY 2: Fallback to explicit config map (optional override)
  # This allows manual overrides for edge cases where automatic matching fails
  if STATUS_UUID_MAP[name_str]
    sid = STATUS_UUID_MAP[name_str]
    s = Status.find_by(id: sid)
    if s
      vputs "[STATUS-MATCH] Matched status '#{name_str}' by config map -> #{s.id}" if verbose
      return s
    end
  end

  # PRIORITY 3: Create new status if allowed
  return nil unless CREATE_MISSING_STATUSES

  default_user = User.find_by(id: DEFAULT_USER_UUID) || User.first
  default_user_id = default_user&.id || DEFAULT_USER_UUID

  status = Status.create!(
    name: name_str,
    created_by: created_by,
    modified_by: created_by,
    user_id: default_user_id
  )
  vputs "[STATUS-CREATE] Created new status '#{name_str}' -> #{status.id}" if verbose
  status
end

def find_or_create_banking_type(name, product_id:, created_by:, verbose: false)
  return nil if name.blank?

  name_str = name.to_s.strip

  # Try to find existing banking type by name (case-insensitive) and product
  bt = BankingType.where('lower(name) = ? AND product_id = ?', name_str.downcase, product_id).first
  if bt
    vputs "[BANKING-MATCH] Found existing banking type '#{name_str}' -> #{bt.id}" if verbose
    return bt
  end

  # Create new banking type if allowed
  return nil unless CREATE_MISSING_BANKING

  begin
    bt = BankingType.create!(name: name_str, product_id: product_id, created_by_id: created_by, modified_by_id: created_by)
    vputs "[BANKING-CREATE] Created new banking type '#{name_str}' -> #{bt.id}" if verbose
    bt
  rescue StandardError => e
    vputs "[BANKING-ERROR] Failed to create banking type '#{name_str}': #{e.class}: #{e.message}" if verbose
    nil
  end
end

def find_or_create_modules(module_name:, submodule_name:, product_id:, created_by:)
  parent = nil
  child = nil

  if module_name.present?
    parent = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', module_name.strip.downcase, product_id).first
    if parent.nil? && CREATE_MISSING_MODULES
      parent = QaModule.create!(name: module_name.strip, product_id: product_id)
      parent.update_columns(created_by: created_by, modified_by: created_by) if parent.respond_to?(:created_by)
    end
  end

  if submodule_name.present?
    if parent
      child = QaModule.where('lower(name) = ? AND parent_id = ? AND product_id = ?', submodule_name.strip.downcase, parent.id, product_id).first
      if child.nil? && CREATE_MISSING_MODULES
        child = QaModule.create!(name: submodule_name.strip, parent_id: parent.id, product_id: product_id)
        child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
      end
    else
      child = QaModule.where('lower(name) = ? AND product_id = ?', submodule_name.strip.downcase, product_id).first
      if child && child.parent_id.present?
        parent = QaModule.find_by(id: child.parent_id)
      elsif child.nil? && CREATE_MISSING_MODULES
        child = QaModule.create!(name: submodule_name.strip, product_id: product_id)
        child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
      end
    end
  end

  [parent, child]
end

# Extract Jira description and convert to rich HTML for ActionText storage
# Handles both plain text and Jira ADF (Atlassian Document Format) content
def extract_description(field)
  return '' if field.nil?
  return field if field.is_a?(String)

  if field.is_a?(Hash)
    # Jira description is in ADF format - convert to HTML
    html = convert_adf_to_html(field['content'] || [])
    return html.present? ? html : ''
  end
  field.to_s
end

# Convert Jira ADF (Atlassian Document Format) to HTML for ActionText
# This preserves formatting like tables, lists, headings, etc.
def convert_adf_to_html(content_array)
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |block|
    next unless block.is_a?(Hash)

    block_html = convert_adf_block_to_html(block)
    html_parts << block_html if block_html.present?
  end

  html_parts.join("\n")
end

# Convert a single ADF block to HTML
def convert_adf_block_to_html(block)
  return '' if block.nil? || !block.is_a?(Hash)

  block_type = block['type']&.to_s&.downcase
  content = block['content'] || []

  case block_type
  when 'paragraph'
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<p>#{inner_html}</p>" : ''

  when 'heading'
    inner_html = convert_adf_inline_to_html(content)
    level = block.dig('attrs', 'level') || 1
    inner_html.present? ? "<h#{level}>#{inner_html}</h#{level}>" : ''

  when 'bulletlist', 'bullet_list'
    list_html = convert_adf_list_to_html(content, 'ul')
    list_html.present? ? "<ul>#{list_html}</ul>" : ''

  when 'orderedlist', 'ordered_list'
    list_html = convert_adf_list_to_html(content, 'ol')
    list_html.present? ? "<ol>#{list_html}</ol>" : ''

  when 'table'
    convert_adf_table_to_html(block)

  when 'codeblock', 'code_block'
    code_text = convert_adf_inline_to_html(content)
    if code_text.present?
      lang = block.dig('attrs', 'language') || 'plaintext'
      "<pre><code class=\"language-#{lang}\">#{CGI.escapeHTML(code_text)}</code></pre>"
    else
      ''
    end

  when 'blockquote'
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<blockquote>#{inner_html}</blockquote>" : ''

  when 'horizontalrule', 'horizontal_rule', 'hr'
    '<hr>'

  when 'image'
    src = block.dig('attrs', 'src')
    alt = block.dig('attrs', 'alt') || 'image'
    src.present? ? "<img src=\"#{CGI.escapeHTML(src)}\" alt=\"#{CGI.escapeHTML(alt)}\">" : ''

  else
    # For unknown types with content, try to process nested content
    convert_adf_to_html(content) if content.is_a?(Array)
  end
end

# Convert ADF inline content (text, mentions, etc) to HTML
def convert_adf_inline_to_html(content_array)
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |item|
    next unless item.is_a?(Hash)

    item_type = item['type']&.to_s&.downcase

    case item_type
    when 'text'
      text = item['text'].to_s
      # Apply marks (bold, italic, code, etc)
      marks = item['marks'] || []
      marked_text = text
      marks.each do |mark|
        mark_type = mark['type']&.to_s&.downcase
        case mark_type
        when 'bold', 'strong'
          marked_text = "<strong>#{marked_text}</strong>"
        when 'italic', 'em'
          marked_text = "<em>#{marked_text}</em>"
        when 'code'
          marked_text = "<code>#{CGI.escapeHTML(marked_text)}</code>"
        when 'underline'
          marked_text = "<u>#{marked_text}</u>"
        when 'strikethrough'
          marked_text = "<s>#{marked_text}</s>"
        when 'link'
          href = mark.dig('attrs', 'href') || '#'
          marked_text = "<a href=\"#{CGI.escapeHTML(href)}\">#{marked_text}</a>"
        when 'textcolor', 'textColor'
          # Support for text color formatting
          color = mark.dig('attrs', 'color') || '#000000'
          marked_text = "<span style=\"color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'backgroundcolor', 'backgroundColor'
          # Support for background color formatting
          color = mark.dig('attrs', 'color') || '#ffffff'
          marked_text = "<span style=\"background-color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'subsup'
          # Support for superscript/subscript
          type = mark.dig('attrs', 'type')
          if type == 'sub'
            marked_text = "<sub>#{marked_text}</sub>"
          elsif type == 'sup'
            marked_text = "<sup>#{marked_text}</sup>"
          end
        end
      end
      html_parts << marked_text if marked_text.present?

    when 'mention'
      mention_text = item.dig('attrs', 'text') || '@user'
      html_parts << "<span class=\"mention\">#{CGI.escapeHTML(mention_text)}</span>"

    when 'hardbreak'
      html_parts << '<br>'

    when 'emoji'
      emoji_text = item.dig('attrs', 'text') || '😊'
      html_parts << emoji_text

    when 'inlinecard', 'card'
      url = item.dig('attrs', 'url')
      title = item.dig('attrs', 'title') || url
      url.present? ? html_parts << "<a href=\"#{CGI.escapeHTML(url)}\">#{CGI.escapeHTML(title)}</a>" : nil

    else
      # Recursively handle nested content
      if item['content'].is_a?(Array)
        nested_html = convert_adf_inline_to_html(item['content'])
        html_parts << nested_html if nested_html.present?
      end
    end
  end

  html_parts.join('')
end

# Convert ADF list to HTML
def convert_adf_list_to_html(items, tag)
  return '' if items.nil? || !items.is_a?(Array)

  list_items = []
  items.each do |item|
    next unless item.is_a?(Hash) && item['type'] == 'listitem'

    item_content = item['content'] || []
    item_html = convert_adf_to_html(item_content)
    # Extract text if it's wrapped in <p> tags
    item_html = item_html.gsub(/<p>(.*?)<\/p>/, '\1')
    list_items << "<li>#{item_html}</li>" if item_html.present?
  end

  list_items.join("\n")
end

# Convert ADF table to HTML
def convert_adf_table_to_html(table_block)
  return '' if table_block.nil?

  table_rows = table_block['content'] || []
  return '' if table_rows.empty?

  rows_html = []
  table_rows.each do |row|
    next unless row.is_a?(Hash) && row['type'] == 'tablerow'

    cells = row['content'] || []
    cells_html = []
    cells.each do |cell|
      next unless cell.is_a?(Hash)

      cell_type = cell['type'] == 'tablehead' ? 'th' : 'td'
      cell_content = cell['content'] || []
      cell_html = convert_adf_to_html(cell_content)
      # Remove wrapping p tags
      cell_html = cell_html.gsub(/<p>(.*?)<\/p>/, '\1')
      cells_html << "<#{cell_type}>#{cell_html}</#{cell_type}>"
    end

    rows_html << "<tr>#{cells_html.join('')}</tr>" if cells_html.any?
  end

  rows_html.any? ? "<table>#{rows_html.join("\n")}</table>" : ''
end

# Process Jira ADF (Atlassian Document Format) content recursively
# Handles: text, paragraphs, lists, tables, code blocks, headings, etc.
def process_adf_content(content_array, text_parts = [])
  return text_parts if content_array.nil? || !content_array.is_a?(Array)

  content_array.each do |block|
    next unless block.is_a?(Hash)

    block_type = block['type']&.to_s&.downcase

    case block_type
    when 'paragraph'
      para_text = extract_adf_text_from_block(block['content'] || [])
      text_parts << para_text if para_text.present?

    when 'heading'
      heading_text = extract_adf_text_from_block(block['content'] || [])
      level = block.dig('attrs', 'level') || 1
      prefix = '#' * level
      text_parts << "#{prefix} #{heading_text}" if heading_text.present?

    when 'bulletlist', 'bullet_list', 'orderedlist', 'ordered_list', 'list'
      list_items = block['content'] || []
      list_items.each_with_index do |item, idx|
        next unless item.is_a?(Hash) && item['type'] == 'listitem'

        item_text = extract_adf_text_from_block(item['content'] || [])
        next if item_text.blank?

        if %w[orderedlist ordered_list].include?(block_type)
          text_parts << "#{idx + 1}. #{item_text}"
        else
          text_parts << "• #{item_text}"
        end
      end

    when 'table'
      table_text = extract_table_as_text(block)
      text_parts << table_text if table_text.present?

    when 'codeblock', 'code_block'
      code_text = extract_adf_text_from_block(block['content'] || [])
      language = block.dig('attrs', 'language') || 'code'
      if code_text.present?
        text_parts << "```#{language}"
        text_parts << code_text
        text_parts << '```'
      end

    when 'blockquote'
      quote_text = extract_adf_text_from_block(block['content'] || [])
      if quote_text.present?
        quoted_lines = quote_text.split("\n").map { |line| "> #{line}" }
        text_parts.concat(quoted_lines)
      end

    when 'horizontalrule', 'horizontal_rule', 'hr'
      text_parts << '---'

    when 'image'
      alt_text = block.dig('attrs', 'alt') || 'image'
      text_parts << "[Image: #{alt_text}]"

    when 'mention'
      mention_text = block.dig('attrs', 'text') || "@user"
      text_parts << mention_text

    when 'inlinecard', 'card', 'embed'
      url = block.dig('attrs', 'url')
      text_parts << "[Link: #{url}]" if url.present?

    else
      nested_text = extract_adf_text_from_block(block['content'] || [])
      text_parts << nested_text if nested_text.present?
    end
  end

  text_parts
end

# Extract plain text from ADF inline content
def extract_adf_text_from_block(content_array = [])
  return '' if content_array.nil? || !content_array.is_a?(Array)

  text_parts = []
  content_array.each do |item|
    next unless item.is_a?(Hash)

    if item['type'] == 'text'
      text = item['text'].to_s
      text_parts << text if text.present?
    elsif item['type'] == 'mention'
      mention_name = item.dig('attrs', 'text') || '@user'
      text_parts << mention_name
    elsif item['type'] == 'hardbreak'
      text_parts << "\n"
    elsif item['content'].is_a?(Array)
      nested = extract_adf_text_from_block(item['content'])
      text_parts << nested if nested.present?
    end
  end

  text_parts.join('')
end

# Convert Jira table ADF to readable text format
def extract_table_as_text(table_block)
  return '' if table_block.nil?

  table_rows = table_block['content'] || []
  return '' if table_rows.empty?

  lines = []
  lines << '[Table]'

  table_rows.each do |row|
    next unless row.is_a?(Hash) && row['type'] == 'tableRow'

    cells = row['content'] || []
    row_text = cells.map do |cell|
      next unless cell.is_a?(Hash)

      cell_content = cell['content'] || []
      cell_text = extract_adf_text_from_block(cell_content)
      cell_text.present? ? cell_text : '-'
    end.compact.join(' | ')

    lines << row_text if row_text.present?
  end

  lines << '[/Table]'
  lines.join("\n")
end

def extract_comment_body(body_field)
  return '' if body_field.nil?
  return body_field if body_field.is_a?(String)

  if body_field.is_a?(Hash)
    text_parts = []
    process_adf_content(body_field['content'] || [], text_parts)
    return text_parts.join("\n").strip
  end
  body_field.to_s
end

# Extract value from a custom field (handles various formats from Jira API)
def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data.to_s.strip if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    # Try common field value keys used by Jira
    return field_data['value'].to_s.strip if field_data['value'].present?
    return field_data['name'].to_s.strip if field_data['name'].present?
    return field_data['key'].to_s.strip if field_data['key'].present?
    return field_data['id'].to_s.strip if field_data['id'].present?
  end

  if field_data.is_a?(Array) && field_data.any?
    # For arrays, try to extract first item's value
    first_item = field_data.first
    if first_item.is_a?(Hash)
      return extract_custom_field_value(first_item)
    else
      return first_item.to_s.strip
    end
  end

  field_data.to_s.strip
end

# ===============================
# JIRA HISTORY/CHANGELOG FETCHER
# ===============================
# Fetch complete changelog for a single Jira issue with pagination support
def fetch_issue_changelog(issue_key, verbose: false)
  all_changes = []
  start_at = 0
  max_results = 100
  page_count = 0

  loop do
    page_count += 1
    url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}/changelog"
    uri = URI.parse(url)
    uri.query = URI.encode_www_form({ startAt: start_at, maxResults: max_results })

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120 # Increased timeout for changelog
    http.open_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    vputs "[HISTORY] Fetching changelog for #{issue_key} (page #{page_count}, start_at=#{start_at})..." if verbose

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      warn "❌ Failed to fetch changelog for #{issue_key}: #{response.code} #{response.message}"
      break
    end

    data = JSON.parse(response.body)
    histories = data['values'] || []
    total = data['total'] || 0

    all_changes.concat(histories)
    vputs "[HISTORY] Fetched #{histories.length} changelog entries for #{issue_key} (total so far: #{all_changes.length}/#{total})" if verbose

    break if start_at + histories.length >= total
    break if histories.empty?

    start_at += histories.length
    sleep 0.3 # Increased delay to avoid rate limiting
  end

  vputs "[HISTORY] Completed fetching #{all_changes.length} changelog entries for #{issue_key}" if verbose
  all_changes
rescue StandardError => e
  warn "[ERROR] Failed to fetch changelog for #{issue_key}: #{e.class}: #{e.message}"
  []
end

# Parse a single changelog entry into structured history rows
def parse_changelog_entry(history, issue_key, verbose: false)
  rows = []
  author = history['author'] || {}
  author_name = author['displayName'].to_s.strip
  author_email = author['emailAddress'].to_s.strip
  created_str = history['created'].to_s.strip
  created_at = try_parse_time(created_str)

  items = history['items'] || []

  # Log all raw items if in verbose mode to ensure we're capturing everything
  if verbose && items.any?
    vputs "[HISTORY-DEBUG] Processing #{items.length} changelog items for #{issue_key}"
    items.each_with_index do |item, idx|
      vputs "[HISTORY-DEBUG]   Item #{idx + 1}: field='#{item['field']}', fieldtype='#{item['fieldtype']}', from='#{item['fromString']}', to='#{item['toString']}'"
    end
  end

  items.each do |item|
    field = item['field'].to_s.strip
    field_type = item['fieldtype'].to_s.strip
    from_val = item['fromString'].to_s.strip
    to_val = item['toString'].to_s.strip
    from_id = item['from'].to_s.strip
    to_id = item['to'].to_s.strip

    # Map Jira field names to more readable history types
    # This comprehensive mapping ensures ALL event types are captured
    history_type = case field.downcase
                   when 'status'
                     'Status Changed'
                   when 'assignee'
                     'Assignee Changed'
                   when 'priority'
                     'Priority Changed'
                   when 'resolution'
                     'Resolution Changed'
                   when 'fix versions', 'fixversions', 'fixversion'
                     'Fix Version Changed'
                   when 'versions', 'version', 'affects versions', 'affectsversions'
                     'Affects Version Changed'
                   when 'labels', 'label'
                     'Labels Changed'
                   when 'description'
                     'Description Updated'
                   when 'summary'
                     'Summary Updated'
                   when 'issuetype', 'type'
                     'Issue Type Changed'
                   when 'reporter'
                     'Reporter Changed'
                   when 'component', 'components'
                     'Components Changed'
                   when 'attachment'
                     'Attachment Changed'
                   when 'link'
                     'Link Changed'
                   when 'comment'
                     'Comment Changed'
                   when 'worklogid'
                     'Work Log Changed'
                   when 'timespent'
                     'Time Spent Changed'
                   when 'timeestimate', 'remaining estimate'
                     'Time Estimate Changed'
                   when 'timeoriginalestimate', 'original estimate'
                     'Original Estimate Changed'
                   when 'environment'
                     'Environment Changed'
                   when 'security', 'security level'
                     'Security Level Changed'
                   when 'project'
                     'Project Changed'
                   when 'parent', 'parent link'
                     'Parent Changed'
                   when 'epic link'
                     'Epic Link Changed'
                   when 'sprint'
                     'Sprint Changed'
                   when 'story points'
                     'Story Points Changed'
                   when 'rank'
                     'Rank Changed'
                   when 'flagged'
                     'Flag Changed'
                   when 'duedate', 'due date'
                     'Due Date Changed'
                   else
                     # Capture ANY field that wasn't explicitly mapped
                     # This ensures ALL events are recorded, not just known ones
                     "#{field.titleize} Changed"
                   end

    # Build history description text
    # Handle special cases where values might be IDs or complex data
    from_display = from_val.presence || from_id.presence || 'None'
    to_display = to_val.presence || to_id.presence || 'None'

    # For certain field types, enhance the description
    description = case field.downcase
                  when 'attachment'
                    if to_val.present?
                      "Added attachment: #{to_val}"
                    elsif from_val.present?
                      "Removed attachment: #{from_val}"
                    else
                      'Attachment changed'
                    end
                  when 'link'
                    if to_val.present?
                      "Added link: #{to_val}"
                    elsif from_val.present?
                      "Removed link: #{from_val}"
                    else
                      'Link changed'
                    end
                  when 'comment'
                    "Comment activity: #{to_display}"
                  else
                    "#{field.titleize} changed from #{from_display} to #{to_display}"
                  end

    rows << {
      issue_key: issue_key,
      author_name: author_name,
      author_email: author_email,
      created_at: created_at,
      history_type: history_type,
      field: field,
      field_type: field_type,
      from_value: from_val,
      to_value: to_val,
      from_id: from_id,
      to_id: to_id,
      description: description
    }
  end

  vputs "[HISTORY] Parsed #{rows.length} change items from changelog entry for #{issue_key} at #{created_at&.strftime('%Y-%m-%d %H:%M:%S')}" if verbose && rows.any?
  rows
rescue StandardError => e
  warn "[ERROR] Failed to parse changelog entry for #{issue_key}: #{e.class}: #{e.message}"
  []
end

# Import changelog entries as DefectHistory records
def import_histories_for_defect(defect, changelog_entries, verbose: false)
  return if changelog_entries.nil? || changelog_entries.empty?

  imported_count = 0
  skipped_count = 0

  changelog_entries.each do |entry|
    author_name = entry[:author_name]
    author_email = entry[:author_email]
    created_at = entry[:created_at]
    history_type = entry[:history_type]
    description = entry[:description]

    # Skip empty descriptions
    next if description.blank?

    # Find or map the user who made the change
    user = find_user_by_name_or_map(author_name, author_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)
    next unless user

    # Check for duplicate history entries (same defect, user, type, timestamp)
    existing = DefectHistory.where(
      defect_id: defect.id,
      user_id: user.id,
      history_type: history_type,
      created_at: created_at
    ).exists?

    if existing
      skipped_count += 1
      vputs "[SKIP] History entry already exists: #{history_type} at #{created_at} for #{defect.defect_unique}" if verbose
      next
    end

    # Create the history record
    begin
      dh = DefectHistory.new(
        defect: defect,
        user: user,
        history_type: history_type,
        history: description,
        created_at: created_at,
        updated_at: created_at || Time.current
      )
      dh.save!
      imported_count += 1
      timestamp_display = created_at ? created_at.strftime('%Y-%m-%d %H:%M:%S') : 'no timestamp'
      vputs "[IMPORT] Created history: #{history_type} for #{defect.defect_unique} at #{timestamp_display}" if verbose
    rescue StandardError => e
      warn "[ERROR] Failed to save history for #{defect.defect_unique}: #{e.class}: #{e.message}"
      next
    end
  end

  if imported_count > 0
    info "[HISTORY] Imported #{imported_count} history entries for #{defect.defect_unique} (skipped #{skipped_count} duplicates)"
  elsif verbose
    vputs "[HISTORY] No new history entries for #{defect.defect_unique} (#{skipped_count} duplicates skipped)"
  end
rescue StandardError => e
  warn "[ERROR] import_histories_for_defect failed for #{defect.defect_unique}: #{e.class}: #{e.message}"
  warn "  Backtrace: #{e.backtrace.first(3).join("\n  ")}" if verbose
end

# Download attachments from Jira and attach to the defect using ActiveStorage.
def fetch_and_attach_attachments(defect, attachments_array, verbose: false)
  return { uploaded: 0, skipped: 0, failed: 0 } if attachments_array.nil? || attachments_array.empty?

  require 'stringio'
  require 'tempfile'
  require 'openssl'

  stats = { uploaded: 0, skipped: 0, failed: 0 }
  total_files = attachments_array.length
  total_size_mb = (attachments_array.sum { |a| a['size'] || 0 } / 1024.0 / 1024.0).round(2)

  puts "📥 DOWNLOADING ISSUE-LEVEL ATTACHMENTS FOR #{defect.defect_unique}"
  puts "   Total files: #{total_files} (#{total_size_mb} MB)"
  puts ""

  attachments_array.each_with_index do |att, idx|
    filename = att['filename'] || att['name'] || 'attachment'
    content_url = att['content'] || att['contentUrl'] || att['self']
    content_type = att['mimeType'] || att['contentType'] || att['mediaType']
    size = att['size'] || 0
    size_mb = (size / 1024.0 / 1024.0).round(2)

    next unless content_url

    # Skip if a file with same filename already attached
    already = defect.attachments.detect { |a| a.filename.to_s == filename }
    if already
      puts "   [#{idx + 1}/#{total_files}] ⏭️  SKIP: #{filename} (already attached)"
      stats[:skipped] += 1
      next
    end

    puts "   [#{idx + 1}/#{total_files}] 📥 Downloading: #{filename} (#{size_mb} MB)"

    # Retry logic with exponential backoff - increased retries for large files
    max_download_retries = size_mb > 20 ? 5 : 3
    download_attempt = 0
    download_success = false
    tf = nil

    while download_attempt < max_download_retries && !download_success
      download_attempt += 1

      begin
        uri = URI.parse(content_url)
        max_redirects = 6
        redirects = 0
        resp = nil

        loop do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')

          # Enhanced SSL and timeout configuration for large files
          if http.use_ssl?
            http.ssl_version = :TLSv1_2
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.ca_file = nil  # Use system CA certs
            # Set cipher suites for better compatibility
            http.ciphers = 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4'
            http.ssl_timeout = 90
          end

          # Generous timeouts for large files (31+ MB) - increased based on file size
          timeout_multiplier = size_mb > 30 ? 2 : 1
          http.open_timeout = 90 * timeout_multiplier
          http.read_timeout = 900 * timeout_multiplier  # Up to 30 minutes for very large files
          http.write_timeout = 90 * timeout_multiplier if http.respond_to?(:write_timeout=)
          http.keep_alive_timeout = 60

          request = Net::HTTP::Get.new(uri.request_uri)
          # preserve auth for Jira-hosted redirects
          request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

          # Add headers for better connection handling
          request['Connection'] = 'keep-alive'
          request['Accept-Encoding'] = 'identity'  # Disable compression for stability
          request['User-Agent'] = 'JiraImporter/1.0'

          vputs "  Attempt #{download_attempt}/#{max_download_retries}: Downloading from #{uri.to_s[0..120]}..." if verbose

          resp = http.request(request)

          # Follow redirects (303/302/301)
          if resp.is_a?(Net::HTTPRedirection)
            location = resp['location']
            break unless location

            redirects += 1
            if redirects > max_redirects
              warn "  Too many redirects (#{redirects}) for attachment #{filename}"
              resp = nil
              break
            end
            uri = URI.parse(location)
            vputs "  Following redirect #{redirects}/#{max_redirects} to: #{location[0..120]}..." if verbose
            next
          end

          break
        end

        unless resp && resp.is_a?(Net::HTTPSuccess)
          if resp
            warn "  Failed to download (HTTP #{resp.code}): #{resp.message}"
          else
            warn "  Failed to download: no successful response"
          end

          # Exponential backoff before retry
          if download_attempt < max_download_retries
            wait_time = [2 ** download_attempt, 30].min  # Cap at 30 seconds
            puts "  ⏳ Waiting #{wait_time}s before retry (attempt #{download_attempt}/#{max_download_retries})..."
            sleep wait_time
          end
          next
        end

        # Stream to tempfile to avoid large memory usage
        tf = Tempfile.new(['jira_attach', File.extname(filename)])
        tf.binmode

        # Write response body in chunks for large files
        bytes_written = 0
        chunk_size = 1024 * 1024  # 1MB chunks

        if resp.body
          resp.body.each_char.each_slice(chunk_size) do |chunk|
            tf.write(chunk.join)
            bytes_written += chunk.length

            # Progress indicator for large files
            if size_mb > 10 && bytes_written % (10 * 1024 * 1024) == 0
              progress_mb = (bytes_written / 1024.0 / 1024.0).round(1)
              vputs "  📊 Downloaded #{progress_mb}/#{size_mb} MB..." if verbose
            end
          end
        end

        tf.rewind

        vputs "  ✅ Downloaded #{bytes_written} bytes successfully" if verbose

        # attach directly from tempfile (ActiveStorage will create blob and upload)
        File.open(tf.path, 'rb') do |f|
          defect.attachments.attach(io: f, filename: filename, content_type: content_type)
        end

        # find the blob we just attached and verify file exists in service (Disk)
        attached_blob = defect.attachments.order(created_at: :desc).limit(1).first&.blob
        exists = if attached_blob
                   begin
                     ActiveStorage::Blob.service.exist?(attached_blob.key)
                   rescue StandardError
                     false
                   end
                 else
                   false
                 end

        if exists
          puts "   ✅ Successfully attached: #{filename} (verified in storage)"
          stats[:uploaded] += 1
          download_success = true
        else
          warn "   ⚠️  Attachment created but not verified in storage: #{filename}"

          # Retry if verification failed but we haven't exhausted retries
          if download_attempt < max_download_retries
            wait_time = 2 ** download_attempt
            puts "  ⏳ Storage verification failed, retrying in #{wait_time}s..."
            sleep wait_time
          else
            stats[:failed] += 1
          end
        end

        vputs "  Attached #{filename} to defect #{defect.defect_unique} (service_exists=#{exists})" if verbose

      rescue OpenSSL::SSL::SSLError => e
        warn "  SSL Error on attempt #{download_attempt}/#{max_download_retries}: #{e.message}"
        warn "  Details: #{e.class}"

        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 30].min
          puts "  ⏳ Retrying in #{wait_time}s due to SSL error..."
          sleep wait_time
        else
          warn "  ❌ FAILED after #{max_download_retries} attempts (SSL error)"
          stats[:failed] += 1
        end

      rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
        warn "  Connection error on attempt #{download_attempt}/#{max_download_retries}: #{e.class} - #{e.message}"

        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 30].min
          puts "  ⏳ Retrying in #{wait_time}s due to connection error..."
          sleep wait_time
        else
          warn "  ❌ FAILED after #{max_download_retries} attempts (connection error)"
          stats[:failed] += 1
        end

      rescue StandardError => e
        warn "  Error on attempt #{download_attempt}/#{max_download_retries}: #{e.class}: #{e.message}"
        warn "  Backtrace: #{e.backtrace[0..2].join("\n           ")}" if verbose

        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 15].min
          puts "  ⏳ Retrying in #{wait_time}s..."
          sleep wait_time
        else
          warn "  ❌ FAILED after #{max_download_retries} attempts"
          stats[:failed] += 1
        end

      ensure
        # cleanup tempfile
        if tf
          begin
            tf.close!
          rescue StandardError
            # Ignore cleanup errors
          end
        end
      end
    end

    # Pause between downloads to avoid overwhelming the server
    sleep 1.5 if download_success

  rescue StandardError => e
    warn "Outer error attaching file #{att.inspect} to #{defect.defect_unique}: #{e.class}: #{e.message}"
    stats[:failed] += 1
  end

  puts ""
  puts "📊 Attachment Summary for #{defect.defect_unique}:"
  puts "   ✅ Uploaded: #{stats[:uploaded]}"
  puts "   ⏭️  Skipped: #{stats[:skipped]}"
  puts "   ❌ Failed: #{stats[:failed]}"
  puts ""

  stats
end

# Download attachments and attach them to an ActionText-rich record (e.g. DefectMessage)
def fetch_and_attach_to_rich_text(rich_record, attachments_array, verbose: false)
  return if attachments_array.nil? || attachments_array.empty?

  require 'tempfile'
  require 'openssl'

  attachments_array.each do |att|
    filename = att['filename'] || att['name'] || 'attachment'
    content_url = att['content'] || att['contentUrl'] || att['self']
    content_type = att['mimeType'] || att['contentType'] || att['mediaType']
    size = att['size'] || 0
    size_mb = (size / 1024.0 / 1024.0).round(2)

    next unless content_url

    # Retry logic
    max_download_retries = size_mb > 20 ? 5 : 3
    download_attempt = 0
    download_success = false
    tf = nil

    while download_attempt < max_download_retries && !download_success
      download_attempt += 1

      begin
        uri = URI.parse(content_url)
        max_redirects = 6
        redirects = 0
        resp = nil

        loop do
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')

          if http.use_ssl?
            http.ssl_version = :TLSv1_2
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.ca_file = nil
            http.ciphers = 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4'
            http.ssl_timeout = 90
          end

          http.read_timeout = 1800
          http.open_timeout = 120
          http.write_timeout = 900 if http.respond_to?(:write_timeout=)
          http.keep_alive_timeout = 300

          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
          request['Connection'] = 'keep-alive'
          request['Accept-Encoding'] = 'identity'

          vputs "  Attempt #{download_attempt}/#{max_download_retries}: Downloading comment attachment #{filename} (#{size_mb} MB)..." if verbose

          resp = http.request(request)

          if resp.is_a?(Net::HTTPRedirection)
            location = resp['location']
            break unless location

            redirects += 1
            if redirects > max_redirects
              warn "  Too many redirects for comment attachment #{filename}"
              resp = nil
              break
            end
            uri = URI.parse(location)
            vputs "  Following redirect #{redirects}/#{max_redirects}..." if verbose
            next
          end

          download_success = true
          break
        end

      rescue OpenSSL::SSL::SSLError => e
        download_success = false
        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 30].min
          warn "  SSL error on attempt #{download_attempt}, retrying in #{wait_time}s..."
          sleep wait_time
        else
          warn "  SSL error after #{max_download_retries} attempts: #{e.message}"
        end

      rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, Net::ReadTimeout, Net::OpenTimeout => e
        download_success = false
        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 30].min
          warn "  Connection error (#{e.class}), retrying in #{wait_time}s..."
          sleep wait_time
        else
          warn "  Connection error after #{max_download_retries} attempts: #{e.class}"
        end

      rescue StandardError => e
        download_success = false
        warn "  Error downloading comment attachment: #{e.class}: #{e.message}"
        if download_attempt < max_download_retries
          wait_time = [2 ** download_attempt, 15].min
          warn "  Retrying in #{wait_time}s..."
          sleep wait_time
        else
          break
        end
      end
    end

    # Skip if download failed
    next unless resp && download_success && resp.is_a?(Net::HTTPSuccess)

    # Process downloaded file
    begin
      tf = Tempfile.new(['jira_comment_attach', File.extname(filename)])
      tf.binmode

      bytes_written = 0
      chunk_size = 1024 * 1024
      if resp.body
        resp.body.each_char.each_slice(chunk_size) do |chunk|
          tf.write(chunk.join)
          bytes_written += chunk.length

          # Progress for large files
          if size_mb > 10 && bytes_written % (10 * 1024 * 1024) == 0
            progress_mb = (bytes_written / 1024.0 / 1024.0).round(1)
            vputs "  📊 Downloaded #{progress_mb}/#{size_mb} MB..." if verbose
          end
        end
      end
      tf.rewind

      vputs "  Downloaded #{bytes_written} bytes for comment attachment #{filename}" if verbose

      rich_text = rich_record.content

      unless rich_text && rich_text.persisted?
        vputs "  [WARN] Rich text not persisted, reloading..." if verbose
        begin
          rich_record.reload
          rich_text = rich_record.content
        rescue StandardError
          warn "  Could not reload record to attach comment file #{filename}"
          next
        ensure
          tf.close! if tf
        end
      end

      blob = ActiveStorage::Blob.create_and_upload!(io: tf, filename: filename, content_type: content_type)
      ActiveStorage::Attachment.create!(name: 'body', record: rich_text, blob: blob)

      exists = begin
        ActiveStorage::Blob.service.exist?(blob.key)
      rescue StandardError
        false
      end

      if exists
        vputs "  ✅ Successfully attached comment file #{filename}" if verbose
      else
        warn "  ⚠️  Comment attachment created but not verified: #{filename}"
      end

    rescue StandardError => e
      warn "  Error creating/uploading comment attachment #{filename}: #{e.class}: #{e.message}"
    ensure
      if tf
        begin
          tf.close!
        rescue StandardError
          # Ignore cleanup errors
        end
      end
      sleep 0.5
    end
  end
end

# Fetch and attach Jira comment attachments to ActionText (direct attach with fallback)
def fetch_and_attach_to_rich_text_jira(rich_record, attachments, verbose: false)
  return { uploaded: 0, skipped: 0, failed: 0 } if attachments.nil? || attachments.empty?

  require 'tempfile'
  require 'openssl'
  stats = { uploaded: 0, skipped: 0, failed: 0 }

  attachments.each_with_index do |att, file_idx|
    filename = att['filename'] || att['name'] || "attachment_#{att['id']}"
    content_type = att['mimeType'] || att['contentType'] || 'application/octet-stream'
    download_url = att['content'] || att['contentUrl'] || att['self'] || att['url']
    size = att['size'] || 0
    size_mb = (size / 1024.0 / 1024.0).round(2)

    begin
      if download_url.to_s.strip.empty?
        vputs "  [#{file_idx + 1}/#{attachments.length}] ⏭️  SKIP: #{filename} (no download URL)" if verbose
        next
      end

      # Check if already attached
      begin
        already_attached = rich_record.attachments.any? { |a| a.filename.to_s == filename }
        if already_attached
          vputs "  [#{file_idx + 1}/#{attachments.length}] ⏭️  SKIP: #{filename} (already attached)" if verbose
          stats[:skipped] += 1
          next
        end
      rescue NoMethodError => e
        warn "[ERROR] DefectMessage does not support attachments: #{e.message}"
        stats[:failed] += 1
        return stats
      end

      print "  [#{file_idx + 1}/#{attachments.length}] 📥 #{filename} (#{size_mb} MB)... " if verbose

      # Retry logic
      max_download_retries = 3
      download_attempt = 0
      download_success = false
      resp = nil
      download_start = Time.now

      while download_attempt < max_download_retries && !download_success
        download_attempt += 1

        begin
          uri = URI.parse(download_url)
          max_redirects = 6
          redirects = 0

          loop do
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')

            if http.use_ssl?
              http.ssl_version = :TLSv1_2
              http.verify_mode = OpenSSL::SSL::VERIFY_PEER
              http.ca_file = nil
              http.ciphers = 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4'
              http.ssl_timeout = 120
            end

            http.read_timeout = 1800
            http.open_timeout = 120
            http.write_timeout = 900 if http.respond_to?(:write_timeout=)
            http.keep_alive_timeout = 300

            request = Net::HTTP::Get.new(uri.request_uri)
            request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
            request['Connection'] = 'keep-alive'
            request['Accept-Encoding'] = 'identity'

            print "." if verbose && size > 10_000_000 && download_attempt == 1

            resp = http.request(request)

            if resp.is_a?(Net::HTTPRedirection)
              location = resp['location']
              break unless location

              redirects += 1
              if redirects > max_redirects
                puts "❌ FAILED (too many redirects)" if verbose
                resp = nil
                break
              end
              uri = URI.parse(location)
              print "→" if verbose
              next
            end

            download_success = true
            break
          end

        rescue OpenSSL::SSL::SSLError => e
          download_success = false
          if download_attempt < max_download_retries
            wait_time = 2 ** download_attempt
            print " [SSL retry in #{wait_time}s]" if verbose
            sleep wait_time
          else
            puts "❌ SSL ERROR" if verbose
            warn "[ERROR] SSL error downloading #{filename} after #{max_download_retries} attempts"
            stats[:failed] += 1
          end

        rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, Net::ReadTimeout, Net::OpenTimeout => e
          download_success = false
          if download_attempt < max_download_retries
            wait_time = 2 ** download_attempt
            print " [Connection retry in #{wait_time}s]" if verbose
            sleep wait_time
          else
            puts "❌ CONNECTION ERROR" if verbose
            warn "[ERROR] Connection error downloading #{filename} after #{max_download_retries} attempts"
            stats[:failed] += 1
          end
        end
      end

      # Skip if download failed
      next unless resp && download_success

      unless resp.is_a?(Net::HTTPSuccess)
        puts "❌ FAILED (HTTP #{resp&.code})" if verbose
        stats[:failed] += 1
        next
      end

      download_duration = (Time.now - download_start).round(2)
      puts "" if verbose && size > 10_000_000

      tmp = Tempfile.new([filename.gsub(/[^0-9A-Za-z.-]/, '_')])
      tmp.binmode

      bytes_written = 0
      if resp.body.respond_to?(:read)
        while chunk = resp.body.read(1_048_576)
          tmp.write(chunk)
          bytes_written += chunk.bytesize
        end
      else
        tmp.write(resp.body)
        bytes_written = resp.body.bytesize
      end
      tmp.rewind

      if size > 0 && bytes_written < size
        puts "⚠️  PARTIAL (#{bytes_written}/#{size} bytes)" if verbose
      end

      begin
        upload_start = Time.now
        max_upload_retries = 3
        upload_retry_count = 0
        upload_success = false

        while upload_retry_count < max_upload_retries && !upload_success
          begin
            File.open(tmp.path, 'rb') do |file|
              rich_record.attachments.attach(io: file, filename: filename, content_type: content_type)
            end
            upload_success = true
          rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT => e
            upload_retry_count += 1
            if upload_retry_count < max_upload_retries
              backoff_time = 2 ** upload_retry_count
              print " [Upload retry in #{backoff_time}s]" if verbose
              sleep(backoff_time)
            else
              raise e
            end
          end
        end

        upload_duration = (Time.now - upload_start).round(2)

        rich_record.reload
        attached = rich_record.attachments.find { |a| a.filename.to_s == filename }
        if attached && attached.blob
          exists = begin
            ActiveStorage::Blob.service.exist?(attached.blob.key)
          rescue StandardError
            false
          end

          if exists
            total_time = download_duration + upload_duration
            speed_mbps = size > 0 ? ((size / 1024.0 / 1024.0) / total_time).round(2) : 0
            puts "✅ OK (#{total_time.round(1)}s, #{speed_mbps} MB/s)" if verbose
            stats[:uploaded] += 1
          else
            puts "⚠️  PARTIAL (not in storage)" if verbose
            stats[:failed] += 1
          end
        else
          puts "⚠️  FAILED (not created)" if verbose
          stats[:failed] += 1
        end
      rescue Net::ReadTimeout => e
        puts "❌ TIMEOUT" if verbose
        warn "[ERROR] Upload timeout for #{filename}"
        stats[:failed] += 1
      rescue Errno::ENOSPC => e
        puts "❌ DISK FULL" if verbose
        warn "[ERROR] No disk space for #{filename}"
        stats[:failed] += 1
      rescue StandardError => e
        puts "❌ ERROR (#{e.class.name})" if verbose
        warn "[ERROR] Failed to attach #{filename}: #{e.message}"
        stats[:failed] += 1
      ensure
        tmp.close
        tmp.unlink
      end

      if size > 100_000_000
        sleep 5.0
      elsif size > 50_000_000
        sleep 3.0
      elsif size > 10_000_000
        sleep 2.0
      else
        sleep 0.5
      end
    rescue StandardError => e
      puts "❌ ERROR (#{e.class.name})" if verbose
      warn "[ERROR] Failed to process #{filename}: #{e.message}"
      stats[:failed] += 1
    end
  end

  stats
end

# Repair and update defect description from Jira data
# - Checks if existing description is different from current Jira data
# - Updates only if necessary
# - Returns true if updated, false if no changes needed
def validate_and_update_description(defect, jira_description_field, issue_key, verbose: false)
  return false unless defect && jira_description_field

  # Extract full formatted description from Jira field
  new_description = extract_description(jira_description_field).to_s.strip
  existing_description = (defect.content.to_s.strip if defect.respond_to?(:content)) || ''

  vputs "[DESCRIPTION-VALIDATE] #{issue_key}: new_len=#{new_description.length}, existing_len=#{existing_description.length}" if verbose

  # Compare descriptions (normalize whitespace for comparison)
  new_normalized = new_description.gsub(/\s+/, ' ').downcase
  existing_normalized = existing_description.gsub(/\s+/, ' ').downcase

  if new_normalized == existing_normalized
    vputs "[DESCRIPTION-SKIP] #{issue_key}: Description unchanged" if verbose
    return false
  end

  # Description differs - update it
  begin
    defect.content = new_description
    defect.save!

    vputs "[DESCRIPTION-UPDATE] #{issue_key}: Updated description (#{new_description.length} chars)" if verbose

    # Log what was changed
    if verbose && existing_description.present?
      vputs "  Previous: #{existing_description[0..100]}..." if existing_description.length > 100
      vputs "  Updated: #{new_description[0..100]}..." if new_description.length > 100
    end

    return true
  rescue StandardError => e
    warn "[DESCRIPTION-ERROR] #{issue_key}: Failed to update description: #{e.class}: #{e.message}"
    return false
  end
end

# Repair and validate descriptions for all defects
def repair_descriptions_for_defects(issues, verbose: false)
  return { total: 0, updated: 0, skipped: 0, errors: 0 } if issues.nil? || issues.empty?

  stats = { total: 0, updated: 0, skipped: 0, errors: 0 }

  issues.each do |issue|
    issue_key = issue['key']
    fields = issue['fields'] || {}
    jira_description_field = fields['description']

    stats[:total] += 1

    begin
      defect = Defect.find_by(defect_unique: issue_key)

      unless defect
        vputs "[REPAIR-SKIP] #{issue_key}: Defect not found in database" if verbose
        stats[:skipped] += 1
        next
      end

      # Validate and update description if changed
      was_updated = validate_and_update_description(defect, jira_description_field, issue_key, verbose: verbose)

      if was_updated
        stats[:updated] += 1
        info "[DESCRIPTION-REPAIRED] #{issue_key}: Description updated from Jira"
      else
        stats[:skipped] += 1
      end

    rescue StandardError => e
      stats[:errors] += 1
      warn "[REPAIR-ERROR] #{issue_key}: Failed to repair description: #{e.class}: #{e.message}"
    end
  end

  stats
end

# Import comments for a defect into DefectMessage (with rich text support)
# Each comment body is converted to HTML/rich text format and stored as ActionText
def import_comments_for_defect(defect, comments_array, verbose: false)
  return { imported: 0, skipped: 0, dropped: 0 } if comments_array.nil? || comments_array.empty?

  stats = { imported: 0, skipped: 0, dropped: 0 }

  comments_array.each_with_index do |c, comment_idx|
    next unless c.is_a?(Hash)

    author = c['author'] || {}
    author_name = author['displayName'].to_s.strip
    author_email = author['emailAddress'].to_s.strip

    # Find the user who made the comment
    user = find_user_by_name_or_map(author_name, author_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)

    # Extract comment body as rich HTML content (preserves formatting like lists, tables, colors, etc)
    # The extract_comment_body handles both plain text and ADF format
    body_field = c['body'] || c['content']

    # For ADF format, convert to HTML; for plain text, return as-is
    if body_field.is_a?(Hash)
      # Jira ADF format - convert to HTML with full rich text support
      body_html = convert_adf_to_html(body_field['content'] || [])
      body = body_html.present? ? body_html : ''
      
      # Log rich text conversion if verbose
      if verbose && body_html.present?
        has_table = body_html.include?('<table>')
        has_list = body_html.include?('<ul>') || body_html.include?('<ol>')
        has_color = body_html.include?('style=')
        has_image = body_html.include?('<img')
        
        features = []
        features << 'table' if has_table
        features << 'list' if has_list
        features << 'color' if has_color
        features << 'image' if has_image
        
        if features.any?
          vputs "[RICH-TEXT] Comment #{comment_idx + 1} contains: #{features.join(', ')}" if verbose
        end
      end
    elsif body_field.is_a?(String)
      # Plain text - keep as-is
      body = body_field.strip
    else
      body = body_field.to_s.strip
    end

    # Skip empty comments (unless they have attachments)
    if body.blank?
      stats[:dropped] += 1
      vputs "[SKIP] Empty comment at index #{comment_idx} for #{defect.defect_unique}" if verbose
      next
    end

    created_at = try_parse_time(c['created'])
    updated_at = try_parse_time(c['updated'])

    # Check for duplicate comments (by timestamp, user, and content)
    if created_at
      existing = defect.defect_messages.where(created_at: created_at, user_id: user&.id).detect do |dm|
        existing_body = dm.content.respond_to?(:to_plain_text) ? dm.content.to_plain_text.strip : dm.content.to_s.strip
        # Normalize for comparison
        existing_normalized = existing_body.gsub(/\s+/, ' ').strip.downcase
        body_normalized = body.gsub(/\s+/, ' ').strip.downcase
        existing_normalized == body_normalized
      end

      if existing
        stats[:skipped] += 1
        vputs "[SKIP] Duplicate comment for #{defect.defect_unique}: already exists" if verbose
        next
      end
    end

    # Create DefectMessage with rich text content
    begin
      dm = DefectMessage.new(defect: defect, user: user, modified_by: user)
      # Assign to content attribute which is ActionText and accepts HTML
      # This will automatically create the rich_text record with proper formatting
      dm.content = body
      dm.created_at = created_at if created_at
      dm.updated_at = updated_at || created_at || Time.current

      dm.save!
      stats[:imported] += 1
      vputs "[IMPORT] Added rich text comment by #{author_name} to #{defect.defect_unique} (id=#{dm.id}, length=#{body.length})" if verbose
    rescue StandardError => e
      warn "[ERROR] Failed to save comment for #{defect.defect_unique}: #{e.class}: #{e.message}"
      stats[:dropped] += 1
    end
  end

  stats
end

# ===============================
# IMPORT LOGIC - MAIN FUNCTION
# ===============================
# Import or update a Jira issue as a Defect record
def import_issue_with_modules(issue, custom_fields, dry_run: true, verbose: false)
  fields = issue['fields'] || {}
  issue_key = issue['key'].to_s.strip

  jira_project_name = fields.dig('project', 'name').to_s
  jira_project_key = fields.dig('project', 'key').to_s
  product_id = PROJECT_UUID_MAP[jira_project_key] || PROJECT_UUID_MAP[jira_project_name] || DEFAULT_PRODUCT_UUID

  unless product_id
    vputs "[SKIP] #{issue_key}: no product mapping for project #{jira_project_key}/#{jira_project_name}" if verbose
    return :skipped
  end

  summary = fields['summary'].to_s.strip
  description = extract_description(fields['description']) || ''
  jira_status_name = (fields.dig('status', 'name') || '').to_s.strip
  jira_priority = (fields.dig('priority', 'name') || DEFAULT_PRIORITY).to_s.strip.presence || DEFAULT_PRIORITY
  issue_type = (fields.dig('issuetype', 'name') || 'Bug').to_s.strip.presence || 'Bug'

  reporter_data = fields['reporter'] || {}
  reporter_name = (reporter_data['displayName'] || '').to_s.strip
  reporter_email = (reporter_data['emailAddress'] || '').to_s.strip

  assignee_data = fields['assignee'] || {}
  assignee_name = (assignee_data['displayName'] || '').to_s.strip
  assignee_email = (assignee_data['emailAddress'] || '').to_s.strip

  created_at = try_parse_time(fields['created'])
  updated_at = try_parse_time(fields['updated'])

  module_name = extract_custom_field_value(fields[custom_fields[:module_field]] || '') if custom_fields[:module_field]
  submodule_name = extract_custom_field_value(fields[custom_fields[:submodule_field]] || '') if custom_fields[:submodule_field]
  banking_type_name = extract_custom_field_value(fields[custom_fields[:banking_type_field]] || '') if custom_fields[:banking_type_field]

  module_name = jira_project_name if module_name.blank?
  banking_type_name = jira_project_key if banking_type_name.blank?

  comments_container = fields.dig('comment') || {}
  comments_array = (comments_container['comments'] || []).select { |c| c.is_a?(Hash) }
  attachments_array = (fields['attachment'] || fields['attachments'] || []).select { |a| a.is_a?(Hash) }
  labels_array = (fields['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)

  vputs "[DEBUG-LABELS] Total labels found for #{issue_key}: #{labels_array.length}" if $verbose_flag && labels_array.any?

  # Map users
  reporter_user = find_user_by_name_or_map(reporter_name, reporter_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)
  assignee_user = find_user_by_name_or_map(assignee_name, assignee_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)

  created_by_uid = reporter_user&.id || DEFAULT_CREATED_BY || DEFAULT_USER_UUID

  # DRY RUN
  if dry_run
    vputs "[DRY] Would process Defect #{issue_key}: summary=#{summary.inspect}" if verbose
    return :ok
  end

  # ACTUAL IMPORT
  saved_defect = nil
  result = nil

  begin
    ActiveRecord::Base.transaction do
      defect = Defect.find_or_initialize_by(defect_unique: issue_key)
      created_flag = defect.new_record?

      defect.product_id = product_id
      defect.summary = summary if summary.present?
      # Assign description as rich HTML content for ActionText storage
      if description.present?
        # ActionText will automatically create/update the rich text record
        # when we assign HTML string to the rich_text attribute
        defect.content = description
      end
      defect.priority = jira_priority if jira_priority.present?
      defect.issue_type = issue_type if issue_type.present?

      # Find or create status
      status = find_or_create_status(jira_status_name, created_by: created_by_uid, verbose: verbose) if jira_status_name.present?

      # Find or create modules
      parent_module, child_module = find_or_create_modules(
        module_name: module_name,
        submodule_name: submodule_name,
        product_id: product_id,
        created_by: created_by_uid
      )

      defect.qa_module_id = parent_module&.id || FALLBACK_QA_MODULE_ID
      defect.submodule_id = child_module&.id || FALLBACK_SUBMODULE_ID

      # Banking type
      banking = find_or_create_banking_type(banking_type_name, product_id: product_id, created_by: created_by_uid, verbose: verbose) if banking_type_name.present?
      defect.banking_type_id = banking&.id || FALLBACK_BANKING_TYPE_ID

      if created_flag
        defect.creator_id = reporter_user&.id if defect.respond_to?(:creator_id) && reporter_user
        defect.created_by = reporter_user&.id if defect.respond_to?(:created_by) && reporter_user
        defect.created_at = created_at if created_at
      end

      defect.modified_by = reporter_user&.id if defect.respond_to?(:modified_by) && reporter_user
      defect.updated_at = updated_at if updated_at
      defect.draft = false if defect.respond_to?(:draft)

      defect.save!

      # Update assignee
      defect.user_ids = [assignee_user.id] if assignee_user

      # Update status
      defect.status_ids = [status.id] if status

      saved_defect = defect
      result = created_flag ? :created : :updated
    end

    # After transaction: attach files
    begin
      fetch_and_attach_attachments(saved_defect, attachments_array, verbose: verbose) if %i[created updated].include?(result) && attachments_array && attachments_array.any?
    rescue StandardError => e
      warn "[WARN] Failed to attach files for #{issue_key}: #{e.class}: #{e.message}"
    end

    # Attach labels
    begin
      if %i[created updated].include?(result) && labels_array && labels_array.any?
        saved_defect.reload
        attach_labels_to_defect(saved_defect, labels_array, created_by: created_by_uid, verbose: verbose)
      end
    rescue StandardError => e
      warn "[WARN] Failed to attach labels for #{issue_key}: #{e.class}: #{e.message}"
    end

    # Import comments
    begin
      if %i[created updated].include?(result) && comments_array && comments_array.any?
        vputs "[COMMENTS] Importing #{comments_array.length} comment(s) for #{issue_key}..." if verbose
        import_comments_for_defect(saved_defect, comments_array, verbose: verbose)
      end
    rescue StandardError => e
      warn "[WARN] Failed to import comments for #{issue_key}: #{e.class}: #{e.message}"
    end

    # Validate and update description
    begin
      if %i[created updated].include?(result)
        validate_and_update_description(saved_defect, fields['description'], issue_key, verbose: verbose)
      end
    rescue StandardError => e
      warn "[WARN] Failed to validate description for #{issue_key}: #{e.class}: #{e.message}"
    end

    result
  rescue ActiveRecord::RecordInvalid => e
    warn "[ERROR] Failed to save defect #{issue_key}: #{e.record.errors.full_messages.join(', ')}"
    :error
  rescue StandardError => e
    warn "[EXCEPTION] issue=#{issue_key} #{e.class}: #{e.message}"
    :error
  end
end

# ===============================
# MAIN EXECUTION
# ===============================
begin
  # Step 1: Fetch from Jira API with module fields for all specified projects
  fetch_result = fetch_jira_issues_with_modules(
    project_keys: project_list,
    max_results: 100,
    days_back: options[:days_back]
  )

  issues = fetch_result[:issues]
  custom_fields = {
    module_field: fetch_result[:module_field],
    submodule_field: fetch_result[:submodule_field],
    banking_type_field: fetch_result[:banking_type_field]
  }

  if issues.empty?
    info 'No issues fetched from Jira. Exiting.'
    exit 0
  end

  info "Successfully fetched #{issues.length} issues from Jira across #{project_list.length} project(s)"
  info "Using custom fields - Module: #{custom_fields[:module_field]}, Submodule: #{custom_fields[:submodule_field]}, Banking Type: #{custom_fields[:banking_type_field]}"

  # Group issues by project for summary
  issues_by_project = issues.group_by { |i| i.dig('fields', 'project', 'key') }
  info "\nIssues per project:"
  issues_by_project.each do |proj_key, proj_issues|
    info "  - #{proj_key}: #{proj_issues.length} issue(s)"
  end

  # Step 2: Import into database
  stats = {
    total: 0,
    ok: 0,
    created: 0,
    updated: 0,
    skipped: 0,
    errors: 0,
    labels_attached: 0,
    comments_imported: 0,
    attachments_imported: 0,
    histories_imported: 0
  }

  # Track per-project stats
  project_stats = Hash.new { |h, k| h[k] = { created: 0, updated: 0 } }


  # Collector for per-issue import/verification reports (used by repair pass)
  $IMPORT_REPORTS = []

  issues.each_with_index do |issue, index|
    stats[:total] += 1
    project_key = issue.dig('fields', 'project', 'key')
    info "Processing issue #{index + 1}/#{issues.length}: #{issue['key']}" if options[:verbose]

    result = import_issue_with_modules(issue, custom_fields, dry_run: options[:dry_run], verbose: options[:verbose])

    case result
    when :created
      stats[:ok] += 1
      stats[:created] += 1
      project_stats[project_key][:created] += 1 if project_key
    when :updated
      stats[:ok] += 1
      stats[:updated] += 1
      project_stats[project_key][:updated] += 1 if project_key
    when :skipped
      stats[:skipped] += 1
    when :error
      stats[:errors] += 1
    end
  end

  # Post-import stats from DB (if not dry-run)
  unless options[:dry_run]
    _defects_imported = Defect.where('updated_at >= ?', Time.now - 10.minutes).count
    _total_labels = Label.count
    _total_comments = DefectMessage.count
    _total_attachments = ActiveStorage::Attachment.where(record_type: 'Defect').count
    _total_histories = DefectHistory.count
  end

  # Summary
  info "\n🎉 Import completed!"
  info 'Summary:'
  info "  Projects processed: #{project_list.join(', ')}"
  info "  Total issues processed: #{stats[:total]}"
  unless options[:dry_run]
    info "  Successfully imported: #{stats[:ok]}"
    info "    - Created: #{stats[:created]}"
    info "    - Updated: #{stats[:updated]}"
  end
  info "  Would import: #{stats[:ok]}" if options[:dry_run]
  info "  Skipped: #{stats[:skipped]}"
  info "  Errors: #{stats[:errors]}"

  # Show detailed per-project breakdown
  info "\n📊 Per-Project Breakdown:"
  issues_by_project.each do |proj_key, proj_issues|
    info "  #{proj_key}:"
    info "    - Issues: #{proj_issues.length}"

    # Show created/updated breakdown if not dry-run
    unless options[:dry_run]
      created = project_stats[proj_key][:created]
      updated = project_stats[proj_key][:updated]
      info "      • Created: #{created}"
      info "      • Updated: #{updated}"
    end

    # Count comments for this project
    comment_count = proj_issues.sum do |issue|
      comments = issue.dig('fields', 'comment', 'comments') || []
      comments.length
    end
    info "    - Comments: #{comment_count}"

    # Count attachments for this project (issue-level)
    attachment_count = proj_issues.sum do |issue|
      attachments = issue.dig('fields', 'attachment') || issue.dig('fields', 'attachments') || []
      attachments.length
    end
    info "    - Attachments: #{attachment_count}"

    # Count labels for this project
    label_count = proj_issues.sum do |issue|
      labels = issue.dig('fields', 'labels') || []
      labels.length
    end
    info "    - Labels: #{label_count}"
  end

  # Show module mapping summary
  unless options[:dry_run]
    info "\n📊 Module Mapping Summary:"
    info "  Banking Types created/found: #{BankingType.where(product_id: DEFAULT_PRODUCT_UUID).count}"
    info "  QA Modules created/found: #{QaModule.where(product_id: DEFAULT_PRODUCT_UUID).count}"
    info "  Submodules created/found: #{QaModule.where.not(parent_id: nil).where(product_id: DEFAULT_PRODUCT_UUID).count}"

    info "\n📁 Data Import Summary:"
    info "  Labels created/attached: #{Label.count}"
    info "  Comments imported: #{DefectMessage.count}"
    info "  Attachments (defect-level): #{ActiveStorage::Attachment.where(record_type: 'Defect').count}"
    info "  Attachments (comment-level): #{ActiveStorage::Attachment.where(record_type: 'DefectMessage').count}"
    info "  History entries imported: #{DefectHistory.count}"

    # Post-import verification and correction
    info "\n🔍 Running post-import verification..."

    verification_stats = {
      missing_comments: 0,
      missing_attachments: 0,
      missing_labels: 0,
      missing_history: 0,
      fixed_comments: 0,
      fixed_attachments: 0,
      fixed_labels: 0,
      fixed_history: 0
    }

    issues.each_with_index do |issue, index|
      issue_key = issue['key']
      defect = Defect.find_by(defect_unique: issue_key)

      # Build per-issue report entry
      report = {
        issue_key: issue_key,
        status: defect ? 'imported' : 'missing_defect',
        expected: {},
        actual: {},
        missing: {},
        fields_status: {},
        errors: []
      }

      begin
        fields = issue['fields'] || {}

        # expected counts
        expected_issue_files = (fields['attachment'] || fields['attachments'] || []).select { |a| a.is_a?(Hash) }.map { |a| (a['filename'] || a['name'] || a['id']).to_s }
        expected_comment_files = (fields.dig('comment','comments') || []).flat_map { |c| (c['_comment_attachments'] || []).map { |a| (a['filename']||a['name']||a['id']).to_s } }

        # Count only non-empty comments (matching import logic)
        all_comments = fields.dig('comment','comments') || []
        expected_comments = all_comments.count do |c|
          body = extract_comment_body(c['body'] || c['content']).to_s.strip
          has_attachments = c.is_a?(Hash) && c['_comment_attachments'].is_a?(Array) && c['_comment_attachments'].any?
          is_synthetic = c['_synthetic'] == true
          # Count comment if it has body OR attachments OR is synthetic
          body.present? || has_attachments || is_synthetic
        end

        expected_labels = (fields['labels'] || []).compact.length

        report[:expected][:issue_attachments] = expected_issue_files.length
        report[:expected][:comment_attachments] = expected_comment_files.length
        report[:expected][:comments] = expected_comments
        report[:expected][:labels] = expected_labels

        if defect
          # actual counts
          actual_issue_files = defect.attachments.map { |a| a.filename.to_s }
          actual_comment_files = defect.defect_messages.flat_map { |dm| dm.respond_to?(:attachments) ? dm.attachments.map { |att| att.filename.to_s } : [] }
          actual_comments = defect.defect_messages.count
          actual_labels = defect.labels.count

          report[:actual][:issue_attachments] = actual_issue_files.length
          report[:actual][:comment_attachments] = actual_comment_files.length
          report[:actual][:comments] = actual_comments
          report[:actual][:labels] = actual_labels

          # missing lists (expected - actual)
          missing_issue = expected_issue_files - actual_issue_files
          missing_comment = expected_comment_files - actual_comment_files

          report[:missing][:issue_files] = missing_issue
          report[:missing][:comment_files] = missing_comment

          # field-wise status
          report[:fields_status][:issue_attachments] = missing_issue.empty?
          report[:fields_status][:comment_attachments] = missing_comment.empty?
          report[:fields_status][:comments] = (expected_comments == actual_comments)
          report[:fields_status][:labels] = (expected_labels == actual_labels)

        else
          report[:errors] << 'Defect record missing in DB after import'
          report[:actual][:issue_attachments] = 0
          report[:actual][:comment_attachments] = 0
          report[:actual][:comments] = 0
          report[:actual][:labels] = 0
          report[:missing][:issue_files] = expected_issue_files
          report[:missing][:comment_files] = expected_comment_files
          report[:fields_status][:issue_attachments] = false
          report[:fields_status][:comment_attachments] = false
          report[:fields_status][:comments] = false
          report[:fields_status][:labels] = false
        end

        # Add history status
        history_count = defect ? defect.defect_histories.count : 0
        report[:expected][:history] = (fetch_issue_changelog(issue_key, verbose: false) || []).length
        report[:actual][:history] = history_count
        report[:fields_status][:history] = report[:actual][:history] >= report[:expected][:history]

      rescue StandardError => e
        report[:errors] << "Verification error: #{e.class}: #{e.message}"
      ensure
        $IMPORT_REPORTS << report
      end
    end

  # Post-import diagnostics and reporting
  info "\n🔍 Running post-import diagnostics..."

  # Collector for missing issues/comments/attachments
  missing_collector = {
    issues: [],
    comments: [],
    attachments: [],
    labels: [],
    histories: []
  }

  # Reported issues from import
  reported_issues = {}

  # Iterate over each issue and compare expected vs actual data
  $IMPORT_REPORTS.each do |report|
    issue_key = report[:issue_key]
    next if reported_issues[issue_key]

    reported_issues[issue_key] = true

    # Check for missing defect records
    if report[:status] == 'missing_defect'
      missing_collector[:issues] << issue_key
      next
    end

    # Check for missing comments
    if report[:expected][:comments].to_i > report[:actual][:comments].to_i
      missing_count = report[:expected][:comments].to_i - report[:actual][:comments].to_i
      missing_collector[:comments] << { issue: issue_key, count: missing_count }
    end

    # Check for missing attachments (issue-level)
    if report[:expected][:issue_attachments].to_i > report[:actual][:issue_attachments].to_i
      missing_count = report[:expected][:issue_attachments].to_i - report[:actual][:issue_attachments].to_i
      missing_collector[:attachments] << { issue: issue_key, type: 'issue', count: missing_count }
    end

    # Check for missing attachments (comment-level)
    if report[:expected][:comment_attachments].to_i > report[:actual][:comment_attachments].to_i
      missing_count = report[:expected][:comment_attachments].to_i - report[:actual][:comment_attachments].to_i
      missing_collector[:attachments] << { issue: issue_key, type: 'comment', count: missing_count }
    end

    # Check for missing labels
    if report[:expected][:labels].to_i > report[:actual][:labels].to_i
      missing_count = report[:expected][:labels].to_i - report[:actual][:labels].to_i
      missing_collector[:labels] << { issue: issue_key, count: missing_count }
    end

    # Check for missing history entries
    if report[:expected][:history].to_i > report[:actual][:history].to_i
      missing_count = report[:expected][:history].to_i - report[:actual][:history].to_i
      missing_collector[:histories] << { issue: issue_key, count: missing_count }
    end
  end

  # Summary of missing items
  info "Missing Items Summary:"
  if missing_collector[:issues].any?
    info "  Issues: #{missing_collector[:issues].length} defect(s) missing"
  end
  if missing_collector[:comments].any?
    info "  Comments: #{missing_collector[:comments].length} comment(s) missing"
  end
  if missing_collector[:attachments].any?
    info "  Attachments: #{missing_collector[:attachments].length} attachment(s) missing"
  end
  if missing_collector[:labels].any?
    info "  Labels: #{missing_collector[:labels].length} label(s) missing"
  end
  if missing_collector[:histories].any?
    info "  Histories: #{missing_collector[:histories].length} history entry(ies) missing"
  end

  # ===============================
  # REPAIR PASS: Attempt to fix missing items
  # ===============================
  if missing_collector.values.flatten.any?
    info "\n🔧 Running repair pass for missing items..."

    # Retry logic for repairs
    max_retries = 3
    retry_delay = 5

    # Helper to perform repairs with retries
    perform_repair = lambda do |action, item, retries|
      begin
        action.call(item)
        true
      rescue StandardError => e
        retries -= 1
        if retries > 0
          warn "  ⚠️  Error: #{e.message}. Retrying in #{retry_delay} seconds..."
          sleep retry_delay
          perform_repair.call(action, item, retries)
        else
          warn "  ❌ Failed to repair #{item[:issue]}: #{e.message}"
          false
        end
      end
    end

    # Repair missing defects
    if missing_collector[:issues].any?
      info "  Repairing missing defects..."
      missing_collector[:issues].each do |issue_key|
        perform_repair.call(->(key) { Defect.find_or_create_by!(defect_unique: key) }, { issue: issue_key }, max_retries)
      end
    end

    # Repair missing comments
    if missing_collector[:comments].any?
      info "  Repairing missing comments..."
      missing_collector[:comments].each do |entry|
        issue_key = entry[:issue]
        defect = Defect.find_by(defect_unique: issue_key)
        next unless defect

        # Re-fetch issue from Jira and extract comments
        jira_issue = fetch_result[:issues].find { |i| i['key'] == issue_key }
        next unless jira_issue

        comments_array = jira_issue.dig('fields', 'comment', 'comments') || []
        next if comments_array.empty?

        # Import missing comments
        import_comments_for_defect(defect, comments_array, verbose: false)
      end
    end

    # Repair missing attachments (issue-level and comment-level)
    if missing_collector[:attachments].any?
      info "  Repairing missing attachments..."
      missing_collector[:attachments].each do |entry|
        issue_key = entry[:issue]
        defect = Defect.find_by(defect_unique: issue_key)
        next unless defect

        # Re-fetch issue from Jira and extract attachments
        jira_issue = fetch_result[:issues].find { |i| i['key'] == issue_key }
        next unless jira_issue

        attachments_array = (jira_issue['fields']['attachment'] || jira_issue['fields']['attachments'] || []).select { |a| a.is_a?(Hash) }
        next if attachments_array.empty?

        # Attach missing files
        fetch_and_attach_attachments(defect, attachments_array, verbose: false)
      end
    end

    # Repair missing labels
    if missing_collector[:labels].any?
      info "  Repairing missing labels..."
      missing_collector[:labels].each do |entry|
        issue_key = entry[:issue]
        defect = Defect.find_by(defect_unique: issue_key)
        next unless defect

        # Re-fetch issue from Jira
        jira_issue = fetch_result[:issues].find { |i| i['key'] == issue_key }
        next unless jira_issue

        labels_array = (jira_issue['fields']['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)
        next if labels_array.empty?

        # Attach missing labels
        reporter_user = find_user_by_name_or_map(jira_issue.dig('fields', 'reporter', 'displayName'), jira_issue.dig('fields', 'reporter', 'emailAddress'), verbose: false) || User.find_by(id: DEFAULT_USER_UUID)
        created_by_uid = reporter_user&.id || DEFAULT_CREATED_BY || DEFAULT_USER_UUID
        attach_labels_to_defect(defect, labels_array, created_by: created_by_uid, verbose: false)
      end
    end

    # Repair missing history entries
    if missing_collector[:histories].any?
      info "  Repairing missing history entries..."
      missing_collector[:histories].each do |entry|
        issue_key = entry[:issue]
        defect = Defect.find_by(defect_unique: issue_key)
        next unless defect

        # Re-fetch issue changelog from Jira
        changelog = fetch_issue_changelog(issue_key, verbose: false)
        next if changelog.nil? || changelog.empty?

        # Parse and import missing history entries
        all_history_entries = changelog.flat_map do |history|
          parse_changelog_entry(history, issue_key, verbose: false)
        end

        all_history_entries.sort_by! { |h| h[:created_at] || Time.at(0) }

        import_histories_for_defect(defect, all_history_entries, verbose: false)
      end
    end

    info "🔧 Repair pass complete!"
  end

    # Final detailed per-issue report and overall success metrics
    info "\n📋 DETAILED IMPORT VERIFICATION REPORT"
  info '=' * 80

  total_issues = $IMPORT_REPORTS.length
  fields_monitored = %i[issue_attachments comment_attachments comments labels history]

  overall_pass_count = 0
  per_issue_failures = []

  $IMPORT_REPORTS.each do |r|
    issue = r[:issue_key]
    # Determine if all monitored fields passed
    passed = fields_monitored.all? { |f| r[:fields_status][f] }
    overall_pass_count += 1 if passed

    unless passed
      # collect failing fields for this issue
      failed_fields = fields_monitored.select { |f| !r[:fields_status][f] }
      per_issue_failures << { issue: issue, failed: failed_fields, missing: r[:missing] }
    end

    # Print per-issue line
    status_str = passed ? 'OK' : 'ISSUES'
    info "#{issue.ljust(20)} -> #{status_str}    (comments: #{r[:actual][:comments]}/#{r[:expected][:comments]}, issue_atts: #{r[:actual][:issue_attachments]}/#{r[:expected][:issue_attachments]}, comment_atts: #{r[:actual][:comment_attachments]}/#{r[:expected][:comment_attachments]}, labels: #{r[:actual][:labels]}/#{r[:expected][:labels]}, history: #{r[:actual][:history]}/#{r[:expected][:history]})"
  end

  success_pct = total_issues > 0 ? ((overall_pass_count.to_f / total_issues) * 100).round(2) : 100.0
  info '\nOverall Success Summary:'
  info "  Issues fully OK: #{overall_pass_count}/#{total_issues} (#{success_pct}%)"
  info "  Issues with problems: #{per_issue_failures.length}"

  if per_issue_failures.any?
    info '\nIssues with failures (details):'
    per_issue_failures.each do |entry|
      info " - #{entry[:issue]} -> failed fields: #{entry[:failed].join(', ')}"
      missing = entry[:missing] || {}
      if missing[:issue_files] && missing[:issue_files].any?
        info "     Missing issue files: #{missing[:issue_files].join(', ')}"
      end
      if missing[:comment_files] && missing[:comment_files].any?
        info "     Missing comment files: #{missing[:comment_files].join(', ')}"
      end
    end
  end

  info '\nEnd of import verification report.'
  info '=' * 80
  end  # Close unless options[:dry_run]

  # ===============================
  # USER MATCH STATISTICS REPORT
  # ===============================
  unless options[:dry_run]
    info "\n" + "=" * 80
    info "👤 USER MATCH STATISTICS REPORT"
    info "=" * 80

    total_lookups = $USER_STATS[:total_lookups]
    info "\nTotal user lookups performed: #{total_lookups}"
    info ""
    info "Match breakdown:"
    info "  ✅ Email matches:          #{$USER_STATS[:email_matches]} (#{total_lookups > 0 ? (($USER_STATS[:email_matches].to_f / total_lookups) * 100).round(2) : 0}%)"
    info "  ✅ Full name matches:      #{$USER_STATS[:full_name_matches]} (#{total_lookups > 0 ? (($USER_STATS[:full_name_matches].to_f / total_lookups) * 100).round(2) : 0}%)"
    info "  ✅ First+Last matches:     #{$USER_STATS[:first_last_matches]} (#{total_lookups > 0 ? (($USER_STATS[:first_last_matches].to_f / total_lookups) * 100).round(2) : 0}%)"
    info "  ✅ Partial matches:        #{$USER_STATS[:partial_matches]} (#{total_lookups > 0 ? (($USER_STATS[:partial_matches].to_f / total_lookups) * 100).round(2) : 0}%)"
    info "  ✅ Config map matches:     #{$USER_STATS[:config_map_matches]}"
    info "  🆕 Created users:          #{$USER_STATS[:created_users]}"
    info "  ⚠️  Fallback to default:    #{$USER_STATS[:fallback_users]}"
    info ""

    total_matched = $USER_STATS[:matched_users].length
    info "Summary:"
    info "  Total unique matched users: #{total_matched}"
    info "  Total unique fallback uses: #{$USER_STATS[:fallback_users_set].length}"
    info ""

    # Reporter/Assignee specific report
    info "Reporter/Assignee Matching:"
    reporter_matched = $USER_STATS[:reporter_matches].values.count { |v| v[:status] == 'matched' }
    reporter_fallback = $USER_STATS[:reporter_matches].length - reporter_matched

    assignee_matched = $USER_STATS[:assignee_matches].values.count { |v| v[:status] == 'matched' }
    assignee_fallback = $USER_STATS[:assignee_matches].length - assignee_matched

    info "  Reporters: #{reporter_matched} matched, #{reporter_fallback} fallback to default"
    info "  Assignees: #{assignee_matched} matched, #{assignee_fallback} fallback to default"
    info ""

    # Name parsing strategies report
    if $USER_STATS[:parsed_names].any?
      info "Name Parsing Strategies Used:"
      strategies = $USER_STATS[:parsed_names].values.group_by { |v| v[:strategy] }
      strategies.each do |strategy, entries|
        info "  #{strategy}: #{entries.length} name(s)"
      end
      info ""

      # Show details of dot-separated names parsed
      dot_separated = $USER_STATS[:parsed_names].select { |_, v| v[:strategy] == 'dot-separated' }
      if dot_separated.any?
        info "  Dot-separated names parsed:"
        dot_separated.each do |name, parsed|
          info "    - '#{name}' → first: '#{parsed[:first_name]}', last: '#{parsed[:last_name]}'"
        end
        info ""
      end

      # Show details of multi-part names
      multi_part = $USER_STATS[:parsed_names].select { |_, v| v[:strategy] == 'multi-part-first-two' }
      if multi_part.any?
        info "  Multi-part names (using first 2 parts):"
        multi_part.each do |name, parsed|
          info "    - '#{name}' → first: '#{parsed[:first_name]}', last: '#{parsed[:last_name]}'"
        end
        info ""
      end
    end

    # Not found names
    if $USER_STATS[:not_found_names].any?
      info "Names that could not be matched (fell back to default user):"
      $USER_STATS[:not_found_names].sort_by { |_, count| -count }.each do |name, count|
        info "  - '#{name}' (#{count} occurrence#{'s' if count > 1})"
      end
      info ""
    end

    # Issues with reporter/assignee fallback to default
    reporter_fallback_issues = $USER_STATS[:reporter_matches].select { |_, v| v[:status] == 'fallback' }
    assignee_fallback_issues = $USER_STATS[:assignee_matches].select { |_, v| v[:status] == 'fallback' }

    if reporter_fallback_issues.any?
      info "\n⚠️  CRITICAL: Issues where reporter fell back to default user (#{reporter_fallback_issues.length}):"
      reporter_fallback_issues.each_with_index do |(issue_key, data), idx|
        info "  #{idx + 1}. #{issue_key}:"
        info "     Name: '#{data[:name]}'"
        info "     Email: '#{data[:email]}'"
        info "     Assigned to: #{data[:user_id]} (DEFAULT USER)"

        # Check if name was parsed and show parsing strategy
        parsed_info = $USER_STATS[:parsed_names][data[:name]]
        if parsed_info
          info "     Parse strategy: #{parsed_info[:strategy]}"
          info "     Parsed as: first='#{parsed_info[:first_name]}', last='#{parsed_info[:last_name]}'"
        end

        if idx < reporter_fallback_issues.length
          info ""
        end
      end
      info ""
    end

    if assignee_fallback_issues.any?
      info "\n⚠️  CRITICAL: Issues where assignee fell back to default user (#{assignee_fallback_issues.length}):"
      assignee_fallback_issues.each_with_index do |(issue_key, data), idx|
        info "  #{idx + 1}. #{issue_key}:"
        info "     Name: '#{data[:name]}'"
        info "     Email: '#{data[:email]}'"
        info "     Assigned to: #{data[:user_id]} (DEFAULT USER)"

        # Check if name was parsed and show parsing strategy
        parsed_info = $USER_STATS[:parsed_names][data[:name]]
        if parsed_info
          info "     Parse strategy: #{parsed_info[:strategy]}"
          info "     Parsed as: first='#{parsed_info[:first_name]}', last='#{parsed_info[:last_name]}'"
        end

        if idx < assignee_fallback_issues.length
          info ""
        end
      end
      info ""
    end

    # Recommendation for fixing fallback users
    if reporter_fallback_issues.any? || assignee_fallback_issues.any?
      total_fallback = reporter_fallback_issues.length + assignee_fallback_issues.length
      info "🔧 RECOMMENDATIONS FOR FIXING FALLBACK USERS:"
      info "  1. Review the names above to ensure they are spelled correctly in both Jira and the local user database"
      info "  2. Check for case sensitivity issues (e.g., 'John Smith' vs 'john smith')"
      info "  3. For dot-separated names (e.g., archana.verma), ensure the local database has matching first_name and last_name"
      info "  4. For multi-part names (3+ parts), the script uses first 2 parts - verify this matches your database"
      info "  5. Create missing users in the database if they don't exist"
      info "  6. Run: rails runner scripts/verify_and_fix_user_assignments.rb"
      info "  7. The verification script will attempt to fix #{total_fallback} incorrectly assigned issue(s)"
      info ""
    end

    info "=" * 80
  end
end
