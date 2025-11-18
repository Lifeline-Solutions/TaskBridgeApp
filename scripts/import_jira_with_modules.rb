#!/usr/bin/env ruby
# scripts/import_jira_with_modules.rb

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'optparse'
require 'yaml'
require 'base64'

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

def find_user_by_name_or_map(name, email = nil, verbose: false)
  name_str = name.to_s.strip
  email_str = email.to_s.strip

  return nil if name_str.blank? && email_str.blank?

  # PRIORITY 1: Try email lookup (most reliable identifier)
  if email_str.present? && email_str.downcase != 'restricted'
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str.downcase)
    if user
      vputs "[USER-MATCH] Matched '#{name_str}' by email: #{email_str} -> #{user.id}" if verbose
      return user
    end
  end

  # PRIORITY 2: Dynamic first_name + last_name matching from Jira displayName
  # This replaces hardcoded user_map with intelligent name comparison
  if name_str.present?
    # Try exact full name match (case-insensitive)
    normalized = name_str.downcase
    user = User.where(deleted_on: nil)
      .where("lower(coalesce(first_name,'') || ' ' || coalesce(last_name,'')) = ?", normalized)
      .first
    if user
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
        vputs "[USER-MATCH] Matched '#{name_str}' by first+last name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end

      # Try partial match: first name matches and last name starts with provided last name
      user = User.where(deleted_on: nil)
        .where('lower(first_name) = ? AND lower(last_name) LIKE ?', first.downcase, "#{last.downcase}%")
        .first
      if user
        vputs "[USER-MATCH] Matched '#{name_str}' by partial last name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end

      # Try reverse: last name matches and first name matches
      user = User.where(deleted_on: nil)
        .where('lower(last_name) = ? AND lower(first_name) LIKE ?', last.downcase, "#{first.downcase}%")
        .first
      if user
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
        vputs "[USER-MATCH] Matched '#{name_str}' by single name: #{user.first_name} #{user.last_name} -> #{user.id}" if verbose
        return user
      end
    end
  end

  # PRIORITY 3: Fallback to explicit config map (optional override)
  # This allows manual overrides for edge cases where automatic matching fails
  if USER_UUID_MAP[name_str]
    uid = USER_UUID_MAP[name_str]
    user = User.find_by(id: uid)
    if user
      vputs "[USER-MATCH] Matched '#{name_str}' by config map -> #{user.id}" if verbose
      return user
    end
  end

  # Try downcased map key
  if USER_UUID_MAP[name_str.downcase]
    uid = USER_UUID_MAP[name_str.downcase]
    user = User.find_by(id: uid)
    if user
      vputs "[USER-MATCH] Matched '#{name_str}' by config map (lowercase) -> #{user.id}" if verbose
      return user
    end
  end

  # PRIORITY 4: Optionally create new user if allowed
  if CREATE_MISSING_USERS && email_str.present? && email_str.downcase != 'restricted'
    attrs = {
      email: email_str.downcase,
      first_name: name_str.split(' ').first || 'Imported',
      last_name: name_str.split(' ')[1..]&.join(' ') || 'User',
      created_by: DEFAULT_CREATED_BY,
      modified_by: DEFAULT_CREATED_BY
    }
    created = User.create(attrs)
    if created.persisted?
      vputs "[USER-CREATE] Created new user '#{name_str}' (#{email_str}) -> #{created.id}" if verbose
      return created
    end
  end

  # PRIORITY 5: Final fallback to default user
  default_user = User.find_by(id: DEFAULT_USER_UUID)
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

def extract_description(field)
  return '' if field.nil?
  return field if field.is_a?(String)

  if field.is_a?(Hash)
    text_parts = []
    (field['content'] || []).each do |block|
      (block['content'] || []).each do |sub|
        text_parts << sub['text'] if sub['type'] == 'text' && sub['text']
      end
    end
    return text_parts.join(' ')
  end
  field.to_s
end

def extract_comment_body(body_field)
  return '' if body_field.nil?
  return body_field if body_field.is_a?(String)

  if body_field.is_a?(Hash)
    text_parts = []
    (body_field['content'] || []).each do |block|
      (block['content'] || []).each do |sub|
        text_parts << sub['text'] if sub['type'] == 'text' && sub['text']
      end
    end
    return text_parts.join(' ')
  end
  body_field.to_s
end

def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    if field_data.key?('value')
      return field_data['value']
    elsif field_data.key?('name')
      return field_data['name']
    elsif field_data.key?('key')
      return field_data['key']
    else
      return field_data.to_s
    end
  end
  field_data.to_s
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
  return if attachments_array.nil? || attachments_array.empty?

  require 'stringio'
  require 'tempfile'

  attachments_array.each do |att|
    filename = att['filename'] || att['name'] || 'attachment'
    content_url = att['content'] || att['contentUrl'] || att['self']
    content_type = att['mimeType'] || att['contentType'] || att['mediaType']

    next unless content_url

    # Skip if a file with same filename already attached
    already = defect.attachments.detect { |a| a.filename.to_s == filename }
    if already
      vputs "[SKIP] attachment #{filename} already attached to defect #{defect.defect_unique}" if verbose
      next
    end

    uri = URI.parse(content_url)
    max_redirects = 6
    redirects = 0
    resp = nil

    begin
      loop do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = 300

        request = Net::HTTP::Get.new(uri.request_uri)
        # preserve auth for Jira-hosted redirects
        request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

        vputs "Downloading attachment #{filename} from #{uri.to_s[0..120]}..." if verbose

        resp = http.request(request)

        # Follow redirects (303/302/301)
        if resp.is_a?(Net::HTTPRedirection)
          location = resp['location']
          break unless location

          redirects += 1
          if redirects > max_redirects
            warn "Too many redirects (#{redirects}) for attachment #{filename}"
            resp = nil
            break
          end
          uri = URI.parse(location)
          next
        end

        break
      end

      unless resp && resp.is_a?(Net::HTTPSuccess)
        if resp
          warn "Failed to download attachment #{filename}: #{resp.code} #{resp.message}"
        else
          warn "Failed to download attachment #{filename}: no successful response"
        end
        next
      end

      # Stream to tempfile to avoid large memory usage
      tf = Tempfile.new(['jira_attach', File.extname(filename)])
      tf.binmode
      tf.write(resp.body)
      tf.rewind

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
      vputs "Attached #{filename} to defect #{defect.defect_unique} (service_exists=#{exists})" if verbose

      # cleanup tempfile
      tf.close!

      # Pause between downloads to avoid overwhelming the server
      sleep 0.5
    rescue StandardError => e
      warn "Error attaching file #{att.inspect} to #{defect.defect_unique}: #{e.class}: #{e.message}"
      next
    end
  rescue StandardError => e
    warn "Error attaching file #{att.inspect} to #{defect.defect_unique}: #{e.class}: #{e.message}"
    next
  end
end

# Download attachments and attach them to an ActionText-rich record (e.g. DefectMessage)
def fetch_and_attach_to_rich_text(rich_record, attachments_array, verbose: false)
  return if attachments_array.nil? || attachments_array.empty?

  require 'tempfile'

  attachments_array.each do |att|
    filename = att['filename'] || att['name'] || 'attachment'
    content_url = att['content'] || att['contentUrl'] || att['self']
    content_type = att['mimeType'] || att['contentType'] || att['mediaType']

    next unless content_url

    uri = URI.parse(content_url)
    max_redirects = 6
    redirects = 0
    resp = nil

    begin
      loop do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = 300

        request = Net::HTTP::Get.new(uri.request_uri)
        request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

        vputs "Downloading comment attachment #{filename} from #{uri.to_s[0..120]}..." if verbose

        resp = http.request(request)

        if resp.is_a?(Net::HTTPRedirection)
          location = resp['location']
          break unless location

          redirects += 1
          if redirects > max_redirects
            warn "Too many redirects (#{redirects}) for comment attachment #{filename}"
            resp = nil
            break
          end
          uri = URI.parse(location)
          next
        end

        break
      end

      unless resp && resp.is_a?(Net::HTTPSuccess)
        if resp
          warn "Failed to download comment attachment #{filename}: #{resp.code} #{resp.message}"
        else
          warn "Failed to download comment attachment #{filename}: no successful response"
        end
        next
      end

      tf = Tempfile.new(['jira_comment_attach', File.extname(filename)])
      tf.binmode
      tf.write(resp.body)
      tf.rewind

      # Ensure the rich text record exists (ActionText::RichText). We attach the
      # uploaded blob to the RichText record so Trix/ActionText will show it as
      # a comment-level attachment. Create an ActiveStorage::Blob and then an
      # ActiveStorage::Attachment that points to the ActionText::RichText record.
      rich_text = rich_record.content

      unless rich_text && rich_text.persisted?
        vputs "[WARN] Rich text not persisted for record id=#{rich_record.id}; reloading..." if verbose
        begin
          rich_record.reload
          rich_text = rich_record.content
        rescue StandardError
          # If reload fails, skip attaching to avoid orphaned blobs
          warn "Could not reload record to attach comment file #{filename}; skipping"
          tf.close!
          next
        end
      end

      # Create and upload blob to the configured ActiveStorage service
      begin
        blob = ActiveStorage::Blob.create_and_upload!(io: tf, filename: filename, content_type: content_type)

        # Attach the blob to the ActionText::RichText record. The attachment name
        # for ActionText rich text body is 'body' so that dm.content.body.attachments
        # will include the uploaded blob.
        ActiveStorage::Attachment.create!(name: 'body', record: rich_text, blob: blob)

        exists = begin
          ActiveStorage::Blob.service.exist?(blob.key)
        rescue StandardError
          false
        end
        vputs "Attached comment file #{filename} to rich text (blob_exists=#{exists})" if verbose
      rescue StandardError => e
        warn "Failed to create/upload blob for comment attachment #{filename}: #{e.class}: #{e.message}"
      ensure
        tf.close!
        sleep 0.15
      end
    rescue StandardError => e
      warn "Error attaching comment file #{att.inspect}: #{e.class}: #{e.message}"
      next
    end
  end
end

# Fetch and attach Jira comment attachments to ActionText (direct attach with fallback)
def fetch_and_attach_to_rich_text_jira(rich_record, attachments, verbose: false)
  return { uploaded: 0, skipped: 0, failed: 0 } if attachments.nil? || attachments.empty?

  require 'tempfile'
  stats = { uploaded: 0, skipped: 0, failed: 0 }

  attachments.each do |att|
    filename = att['filename'] || att['name'] || "attachment_#{att['id']}"
    content_type = att['mimeType'] || att['contentType'] || 'application/octet-stream'
    download_url = att['content'] || att['contentUrl'] || att['self'] || att['url']
    size = att['size'] || 0

    begin
      if download_url.to_s.strip.empty?
        vputs "[SKIP] attachment #{filename} has no download URL" if verbose
        next
      end

      # Check if this attachment is already attached to this comment
      begin
        already_attached = rich_record.attachments.any? { |a| a.filename.to_s == filename }
        if already_attached
          vputs "  [SKIP] Attachment '#{filename}' already attached to comment #{rich_record.id}" if verbose
          stats[:skipped] += 1
          next
        end
      rescue NoMethodError => e
        # DefectMessage may not have attachments association in older versions
        warn "[ERROR] DefectMessage does not support attachments: #{e.message}"
        warn "[ERROR] Please add 'has_many_attached :attachments' to app/models/defect_message.rb"
        stats[:failed] += 1
        return stats
      end

      uri = URI.parse(download_url)
      max_redirects = 6
      redirects = 0
      resp = nil

      loop do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        # Increased timeouts for large files (up to 10 minutes for very large attachments)
        http.read_timeout = 600 # 10 minutes to download large files
        http.open_timeout = 60 # 1 minute to establish connection
        http.write_timeout = 300 # 5 minutes for upload (if supported)

        request = Net::HTTP::Get.new(uri.request_uri)
        request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

        file_size_mb = (size / 1024.0 / 1024.0).round(2)
        vputs "Downloading comment attachment #{filename} (#{file_size_mb} MB) from #{uri.to_s[0..120]}..." if verbose

        resp = http.request(request)

        if resp.is_a?(Net::HTTPRedirection)
          location = resp['location']
          break unless location

          redirects += 1
          if redirects > max_redirects
            warn "Too many redirects (#{redirects}) for comment attachment #{filename}"
            resp = nil
            break
          end
          uri = URI.parse(location)
          next
        end

        break
      end

      unless resp && resp.is_a?(Net::HTTPSuccess)
        warn "[WARN] Unable to download attachment #{filename} (HTTP #{resp&.code})"
        stats[:failed] += 1
        next
      end

      tmp = Tempfile.new([filename.gsub(/[^0-9A-Za-z.-]/, '_')])
      tmp.binmode
      tmp.write(resp.body)
      tmp.rewind

      # Attach directly to DefectMessage using has_many_attached :attachments
      # This stores comment attachments in active_storage_attachments with record_type='DefectMessage'
      begin
        # Verify storage service is accessible before attempting upload
        storage_service = ActiveStorage::Blob.service
        storage_root = storage_service.respond_to?(:root) ? storage_service.root : 'N/A'

        # Attach file to DefectMessage record using ActiveStorage
        File.open(tmp.path, 'rb') do |file|
          rich_record.attachments.attach(io: file, filename: filename, content_type: content_type)
        end

        # Verify attachment was created and uploaded successfully
        rich_record.reload
        attached = rich_record.attachments.find { |a| a.filename.to_s == filename }
        if attached && attached.blob
          blob_key = attached.blob.key
          blob_byte_size = attached.blob.byte_size

          # Check if blob physically exists in storage
          exists = begin
            ActiveStorage::Blob.service.exist?(blob_key)
          rescue StandardError => e
            warn "[STORAGE-ERROR] Failed to verify blob existence for #{filename}: #{e.message}"
            false
          end

          file_size_mb = (size / 1024.0 / 1024.0).round(2)

          if exists
            vputs "  [OK] Attached comment file '#{filename}' to DefectMessage #{rich_record.id} (#{file_size_mb} MB, blob_key=#{blob_key}, storage=#{storage_root})" if verbose
            stats[:uploaded] += 1
          else
            warn "[STORAGE-WARN] Blob record created for '#{filename}' but file not found in storage (key=#{blob_key}, storage=#{storage_root})"
            warn '[STORAGE-WARN] This may cause 404 errors when trying to view/download the attachment'
            stats[:failed] += 1
          end
        else
          warn "[WARN] Attachment created but blob not found for #{filename}"
          stats[:failed] += 1
        end
      rescue StandardError => e
        warn "[ERROR] Failed to attach file #{filename} to DefectMessage #{rich_record.id}: #{e.class}: #{e.message}"
        warn "[ERROR] Backtrace: #{e.backtrace.first(3).join(', ')}" if verbose
        stats[:failed] += 1
      ensure
        tmp.close
        tmp.unlink
      end

      # Add delay between large file downloads to avoid overwhelming server/network
      sleep(size > 5_000_000 ? 2.0 : 0.5) # 2 seconds for files > 5MB, 0.5s otherwise
    rescue StandardError => e
      warn "[ERROR] Failed to attach #{filename} to comment #{rich_record.id}: #{e.class}: #{e.message}"
      stats[:failed] += 1
      next
    end
  end

  stats
end

# Import comments for a defect into DefectMessage (preserves author mapping and timestamps)
# Returns hash with import statistics: { imported: n, skipped: n }
def import_comments_for_defect(defect, comments_array, verbose: false)
  return { imported: 0, skipped: 0 } if comments_array.nil? || comments_array.empty?

  stats = { imported: 0, skipped: 0 }

  comments_array.each do |c|
    author = c['author'] || {}
    author_name = author['displayName'].to_s.strip
    author_email = author['emailAddress'].to_s.strip

    user = find_user_by_name_or_map(author_name, author_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)

    body = extract_comment_body(c['body'] || c['content'] || c['body']).to_s.strip
    jira_comment_id = c['id'].to_s.strip # Unique Jira comment identifier

    # Check if this comment has attachments matched to it
    has_attachments = c.is_a?(Hash) && c['_comment_attachments'].is_a?(Array) && c['_comment_attachments'].any?
    is_synthetic = c['_synthetic'] == true

    # Skip ONLY if both body and comment are completely empty (no content at all)
    # This ensures all real Jira comments are imported
    next if body.blank? && !has_attachments && !is_synthetic

    created_at = try_parse_time(c['created'])
    updated_at = try_parse_time(c['updated'])

    # ROBUST DUPLICATE DETECTION - check multiple criteria for distinctness:
    # 1. Jira comment ID (most reliable for non-synthetic comments)
    # 2. Exact timestamp match (unix timestamp comparison)
    # 3. User + timestamp + content match (for synthetic comments without Jira ID)

    # First check: Query DB for comments with same timestamp (most efficient)
    if created_at
      existing_by_time = defect.defect_messages.where(created_at: created_at).to_a

      if existing_by_time.any?
        duplicate = existing_by_time.any? do |em|
          # Extract plain text from ActionText for comparison
          existing_body = if em.content.respond_to?(:to_plain_text)
                            em.content.to_plain_text.strip
                          else
                            em.content.to_s.strip
                          end

          # Consider duplicate if:
          # - Same timestamp AND same user AND same content (strong match)
          # - OR for non-synthetic: same timestamp AND same content (Jira ensures uniqueness)
          same_content = existing_body == body || existing_body == (has_attachments ? 'Attachment(s) uploaded' : '[Empty comment]')
          same_user = em.user_id == user&.id

          (same_user && same_content) || (!is_synthetic && same_content)
        end

        if duplicate
          stats[:skipped] += 1
          vputs "[SKIP] Duplicate comment detected: #{jira_comment_id} by #{author_name} at #{created_at} on #{defect.defect_unique}" if verbose
          next
        end
      end
    end

    # Second check: For comments without timestamp, check by user + content
    if created_at.nil? && body.present?
      content_to_check = body
      existing_by_content = defect.defect_messages.where(user_id: user&.id).to_a.select do |em|
        existing_body = if em.content.respond_to?(:to_plain_text)
                          em.content.to_plain_text.strip
                        else
                          em.content.to_s.strip
                        end
        existing_body == content_to_check
      end

      if existing_by_content.any?
        stats[:skipped] += 1
        vputs "[SKIP] Duplicate comment (by content) detected: #{jira_comment_id} by #{author_name} on #{defect.defect_unique}" if verbose
        next
      end
    end

    dm = DefectMessage.new(defect: defect, user: user, modified_by: user)
    # ActionText will store rich text; assign plain text (or HTML if present)
    # Only use placeholder text if body is empty - otherwise use actual comment content
    dm.content = if body.present?
                   body
                 else
                   (has_attachments ? 'Attachment(s) uploaded' : '[Empty comment]')
                 end
    dm.created_at = created_at if created_at
    dm.updated_at = updated_at if updated_at

    # Attempt to save with duplicate handling (in case of race conditions)
    begin
      dm.save!
    rescue ActiveRecord::RecordNotUnique => e
      # If we hit a uniqueness violation (rare but possible in concurrent imports),
      # skip this comment as it's already been imported
      stats[:skipped] += 1
      vputs "[SKIP] Duplicate comment detected during save (race condition): #{jira_comment_id} on #{defect.defect_unique}" if verbose
      next
    end

    stats[:imported] += 1
    comment_type = is_synthetic ? 'synthetic comment with attachment(s)' : 'comment'
    vputs "[IMPORT] Added #{comment_type} by #{author_name} to #{defect.defect_unique} (id=#{dm.id})" if verbose

    # IMPORTANT: Only attach files that were explicitly matched to THIS comment
    # DO NOT attach unmatched attachments to comments that don't have them
    # Each comment gets ONLY its own attachments (if any)
    if has_attachments
      # Check if DefectMessage supports attachments (may not be available in all environments)
      unless dm.respond_to?(:attachments)
        warn '[SKIP] DefectMessage model does not support attachments. Comment attachments will not be uploaded.'
        warn "[SKIP] Please ensure 'has_many_attached :attachments' is defined in app/models/defect_message.rb"
        next
      end

      comment_att_count = c['_comment_attachments'].length
      total_size_mb = (c['_comment_attachments'].sum { |att| att['size'] || 0 } / 1024.0 / 1024.0).round(2)

      vputs "[ATTACH] Attaching #{comment_att_count} file(s) (#{total_size_mb} MB total) to comment #{dm.id}..." if verbose

      max_retries = 2
      retry_count = 0
      upload_stats = nil
      success = false

      while retry_count <= max_retries && !success
        begin
          # Attach comment attachments to the DefectMessage's ActionText content
          # (attachments will display automatically in Trix editor without appending HTML)
          upload_stats = fetch_and_attach_to_rich_text_jira(dm, c['_comment_attachments'], verbose: verbose)

          # Verify attachments were uploaded successfully
          dm.reload
          attached_count = dm.attachments.count
          expected_count = comment_att_count

          # Check if all attachments were uploaded and physically exist in storage
          all_exist = dm.attachments.all? do |att|
            ActiveStorage::Blob.service.exist?(att.blob.key)
          rescue StandardError
            false
          end

          if attached_count == expected_count && all_exist
            vputs "  [OK] Successfully attached all #{attached_count} file(s) to comment #{dm.id}" if verbose
            vputs "    - Uploaded: #{upload_stats[:uploaded]}, Skipped: #{upload_stats[:skipped]}, Failed: #{upload_stats[:failed]}" if upload_stats && verbose
            success = true
          elsif attached_count > 0
            vputs "  [PARTIAL] Attached #{attached_count}/#{expected_count} file(s) to comment #{dm.id}" if verbose

            # Identify missing attachments and retry
            attached_filenames = dm.attachments.map { |a| a.filename.to_s }
            expected_filenames = c['_comment_attachments'].map { |a| a['filename'] || a['name'] }
            missing_filenames = expected_filenames - attached_filenames

            if missing_filenames.any? && retry_count < max_retries
              retry_count += 1
              warn "[RETRY] Attempting to upload #{missing_filenames.length} missing file(s) (attempt #{retry_count}/#{max_retries})"

              # Find the attachment data for missing files
              missing_attachments = c['_comment_attachments'].select do |a|
                filename = a['filename'] || a['name']
                missing_filenames.include?(filename)
              end

              # Retry upload for missing files
              sleep(2) # Brief delay before retry
              retry_stats = fetch_and_attach_to_rich_text_jira(dm, missing_attachments, verbose: verbose)
              vputs "  [RETRY-RESULT] Uploaded: #{retry_stats[:uploaded]}, Failed: #{retry_stats[:failed]}" if verbose

              # Re-verify after retry
              dm.reload
              attached_count = dm.attachments.count

              # Check if we got all files now
              success = true if attached_count == expected_count
            else
              # Can't retry anymore
              warn "[WARN] Incomplete upload for comment #{dm.id} on #{defect.defect_unique}: #{attached_count}/#{expected_count} files"
              break
            end
          else
            # Failed to attach any files
            warn "[WARN] Failed to attach any files to comment #{dm.id} on #{defect.defect_unique}"

            break unless retry_count < max_retries

            retry_count += 1
            warn "[RETRY] Retrying full attachment upload for comment #{dm.id} (attempt #{retry_count}/#{max_retries})"
            sleep(2)
            # Loop will retry

          end
        rescue StandardError => e
          warn "[ERROR] Failed to attach #{comment_att_count} file(s) to comment #{dm.id} on #{defect.defect_unique}: #{e.class}: #{e.message}"

          # Retry on error
          break unless retry_count < max_retries

          retry_count += 1
          warn "[RETRY] Retrying after error (attempt #{retry_count}/#{max_retries})"
          sleep(2)
          # Loop will retry
        end
      end
    end
  rescue StandardError => e
    vputs "[COMMENT-SKIP] Error importing comment for #{defect.defect_unique}: #{e.class}: #{e.message}" if verbose
    next
  end

  vputs "[IMPORT] Comment import complete for #{defect.defect_unique}: #{stats[:imported]} imported, #{stats[:skipped]} duplicates skipped" if verbose && (stats[:imported] > 0 || stats[:skipped] > 0)
  stats
end

# If a defect has issue-level attachments, make them visible in the comments
# area by creating (if needed) a DefectMessage that contains the filenames and
# attaches the same blobs to the ActionText-rich record. This helps ensure the
# UI shows issue attachments alongside comments.
def ensure_issue_attachments_visible_in_comments(defect, verbose: false)
  return unless defect && defect.persisted?
  return if defect.attachments.none?

  begin
    defect_blob_ids = defect.attachments.map(&:blob_id).compact.uniq
    return if defect_blob_ids.empty?

    # If any existing message already contains all these blobs, nothing to do
    found = false
    defect.defect_messages.each do |dm|
      msg_blob_ids = dm.content&.body&.attachments&.map(&:blob_id) || []
      next if msg_blob_ids.empty?

      if (defect_blob_ids - msg_blob_ids).empty?
        vputs "[INFO] Defect #{defect.defect_unique} already has a comment with issue attachments" if verbose
        found = true
        break
      end
    rescue StandardError
      next
    end
    return if found

    # Create a summary comment that lists the filenames
    filenames = defect.attachments.map { |a| a.filename.to_s }
    user = User.find_by(id: DEFAULT_USER_UUID)
    dm = DefectMessage.create!(defect: defect, user: user, modified_by: user, content: "Jira issue attachments: #{filenames.join(', ')}")

    # Attach existing blobs to the new message's ActionText rich text record
    defect.attachments.each do |att|
      blob = att.blob
      next unless blob

      ActiveStorage::Attachment.create!(name: 'body', record: dm.content, blob: blob)
    rescue StandardError => e
      vputs "[WARN] Could not attach existing blob #{att&.filename} to comment #{dm.id}: #{e.class}: #{e.message}" if verbose
      next
    end

    vputs "[INFO] Created comment #{dm.id} to surface #{filenames.length} issue-level attachment(s) for #{defect.defect_unique}" if verbose
  rescue StandardError => e
    warn "[ERROR] ensure_issue_attachments_visible_in_comments failed for #{defect.defect_unique}: #{e.class}: #{e.message}"
  end
end

# ===============================
# IMPORT LOGIC - WITH MODULE MAPPING
# ===============================
# Import or update a Jira issue as a Defect record
# - Creates new defect if defect_unique doesn't exist
# - Updates existing defect if defect_unique already exists (syncs with latest Jira data)
# - Prevents duplication of comments, attachments, labels, and history entries
# - All relationships (assignee, status, modules, banking type) are synchronized
def import_issue_with_modules(issue, custom_fields, dry_run: true, verbose: false)
  fields = issue['fields'] || {}
  issue_key = issue['key'].to_s.strip

  jira_project_name = fields.dig('project', 'name').to_s
  jira_project_key = fields.dig('project', 'key').to_s
  product_id = PROJECT_UUID_MAP[jira_project_key] || PROJECT_UUID_MAP[jira_project_name] || DEFAULT_PRODUCT_UUID

  unless product_id
    puts "[SKIP] #{issue_key}: no product mapping for project #{jira_project_key}/#{jira_project_name}"
    return :skipped
  end

  summary = fields['summary'].to_s.strip
  description = extract_description(fields['description']) || ''
  jira_status_name = (fields.dig('status', 'name') || '').to_s.strip
  jira_priority = (fields.dig('priority', 'name') || DEFAULT_PRIORITY).to_s.strip.presence || DEFAULT_PRIORITY
  issue_type = (fields.dig('issuetype', 'name') || 'Bug').to_s.strip.presence || 'Bug'

  # Handle missing reporter/assignee data
  reporter_data = fields['reporter'] || {}
  reporter_name = (reporter_data['displayName'] || '').to_s.strip
  reporter_email = (reporter_data['emailAddress'] || '').to_s.strip

  assignee_data = fields['assignee'] || {}
  assignee_name = (assignee_data['displayName'] || '').to_s.strip
  assignee_email = (assignee_data['emailAddress'] || '').to_s.strip

  created_at = try_parse_time(fields['created'])
  updated_at = try_parse_time(fields['updated'])

  # Extract module, submodule, and banking type from custom fields
  module_name = extract_custom_field_value(fields[custom_fields[:module_field]] || '') if custom_fields[:module_field]
  submodule_name = extract_custom_field_value(fields[custom_fields[:submodule_field]] || '') if custom_fields[:submodule_field]
  banking_type_name = extract_custom_field_value(fields[custom_fields[:banking_type_field]] || '') if custom_fields[:banking_type_field]

  # Fallback to project-based values if custom fields are empty
  module_name = jira_project_name if module_name.blank?
  banking_type_name = jira_project_key if banking_type_name.blank?

  comments_container = fields.dig('comment') || {}
  comments_array = (comments_container['comments'] || []).select { |c| c.is_a?(Hash) }
  attachments_array = (fields['attachment'] || fields['attachments'] || []).select { |a| a.is_a?(Hash) }
  labels_array = (fields['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)

  # DEBUG: Log raw labels data
  if $verbose_flag
    vputs "[DEBUG-LABELS] Total labels found for #{issue_key}: #{labels_array.length}"
    vputs "[DEBUG-LABELS]   Labels: #{labels_array.inspect}" if labels_array.any?
  end

  # DEBUG: Log raw attachment data
  if $verbose_flag && attachments_array.any?
    vputs "[DEBUG-ATTACHMENTS] Total attachments found: #{attachments_array.length}"
    attachments_array.each_with_index do |att, idx|
      vputs "[DEBUG-ATTACHMENTS]   [#{idx}] id=#{att['id']}, filename=#{att['filename']}, created=#{att['created']}, keys=#{att.keys.join(',')}"
    end
  end

  # DEBUG: Log raw comment data
  if $verbose_flag && comments_array.any?
    vputs "[DEBUG-COMMENTS] Total comments found: #{comments_array.length}"
    comments_array.each_with_index do |c, idx|
      c_created = try_parse_time(c['created'])
      vputs "[DEBUG-COMMENTS]   [#{idx}] id=#{c['id']}, created=#{c_created}, has_attachment=#{c.key?('attachment')}, keys=#{c.keys.join(',')}"
    end
  end

  # Split attachments that belong to specific comments vs issue-level attachments.
  # Strategy: Look for attachment metadata embedded in Jira comment JSON that references which attachments belong to comments.
  # Jira includes 'created' timestamp on attachments; comments also have 'created' timestamp.
  # Match attachments to comments if the attachment was created around the same time as the comment (within 1 hour window).

  # Check each comment for attachment references
  (comments_array || []).each do |c|
    next unless c.is_a?(Hash)

    comment_attachments = []
    comment_created = try_parse_time(c['created'])
    body_text = extract_comment_body(c['body'] || c['content']) || ''

    vputs "[DEBUG] Processing comment #{c['id']} created=#{comment_created}, body_length=#{body_text.length}" if $verbose_flag

    # Strategy 1: Check if this comment has direct attachment array (Jira stores these under comment.attachment)
    if c.key?('attachment') && c['attachment'].is_a?(Array) && c['attachment'].any?
      c['attachment'].each do |att|
        next unless att.is_a?(Hash)

        att_id = att['id']
        att_fname = att['filename']
        vputs "[DEBUG]   Found direct comment.attachment: id=#{att_id}, filename=#{att_fname}" if $verbose_flag
        comment_attachments << att
      end
    end

    # Strategy 2: Match by exact attachment ID in comment's attachment reference field (if present)
    if c.key?('attachment_ids') && c['attachment_ids'].is_a?(Array)
      c['attachment_ids'].each do |att_id|
        matching_att = (attachments_array || []).find { |a| a['id'] == att_id }
        if matching_att
          vputs "[DEBUG]   Found attachment by ID match: #{att_id}" if $verbose_flag
          comment_attachments << matching_att
        end
      end
    end

    # Strategy 3: Match by creation time proximity (attachment created within 5 minutes of comment)
    # Use a tight time window to ensure attachments with different timestamps go to different comments
    (attachments_array || []).each do |att|
      next if comment_attachments.any? { |ca| ca['id'] == att['id'] }

      att_created = try_parse_time(att['created'])
      if att_created && comment_created
        time_diff = (att_created - comment_created).abs
        # If attachment was created within 5 minutes of comment, consider it as comment attachment
        # This tight window ensures attachments with different timestamps are not grouped together
        if time_diff < 300 # 5 minutes (300 seconds)
          vputs "[DEBUG]   Found attachment by time match (#{time_diff}s apart): #{att['filename']}" if $verbose_flag
          comment_attachments << att
        elsif $verbose_flag
          vputs "[DEBUG]   Skipped attachment #{att['filename']} (time diff #{time_diff}s > 5min)" if $verbose_flag
        end
      elsif $verbose_flag
        vputs "[DEBUG]   Skipped attachment #{att['filename']} (missing created timestamp)" if $verbose_flag
      end
    end

    # Strategy 4: Match by filename in comment body text
    (attachments_array || []).each do |att|
      next if comment_attachments.any? { |ca| ca['id'] == att['id'] }

      fname = att['filename'].to_s.strip
      if fname.present? && body_text.include?(fname)
        vputs "[DEBUG]   Found attachment by filename match in body: #{fname}" if $verbose_flag
        comment_attachments << att
      end
    end

    if comment_attachments.any?
      # Validate: Check if attachments have significantly different timestamps
      # If they do, only keep the ones closest to the comment timestamp
      att_with_times = comment_attachments.map do |att|
        { att: att, created: try_parse_time(att['created']), id: att['id'] }
      end

      # Filter out attachments with timestamps if we have multiple and they're not close together
      if att_with_times.length > 1 && comment_created
        # Calculate time difference for each attachment from comment
        att_with_times.each do |awt|
          awt[:time_diff] = awt[:created] ? (awt[:created] - comment_created).abs : Float::INFINITY
        end

        # Check if attachments have widely different timestamps (> 1 minute apart from each other)
        timestamps = att_with_times.map { |awt| awt[:created] }.compact.sort
        if timestamps.length > 1
          max_spread = (timestamps.last - timestamps.first).abs

          if max_spread > 60 # More than 1 minute spread between attachments
            # Only keep attachments that are closest to comment timestamp
            min_diff = att_with_times.map { |awt| awt[:time_diff] }.min

            # Keep only attachments within 1 minute of the closest one
            filtered = att_with_times.select { |awt| (awt[:time_diff] - min_diff).abs <= 60 }

            if filtered.length < comment_attachments.length
              vputs "[DEBUG]   Filtered out #{comment_attachments.length - filtered.length} attachment(s) with divergent timestamps (spread: #{max_spread}s)" if $verbose_flag
              comment_attachments = filtered.map { |awt| awt[:att] }
            end
          end
        end
      end

      # Mark attachments as belonging to this comment so import_comments_for_defect can attach them
      c['_comment_attachments'] = comment_attachments.uniq { |x| x['id'] || x['filename'] }
      vputs "[DEBUG]   Comment #{c['id']} has #{comment_attachments.length} attachment(s)" if $verbose_flag
    elsif $verbose_flag
      vputs "[DEBUG]   Comment #{c['id']} has no attachments" if $verbose_flag
    end
  end

  # Determine ids/names of attachments referenced by comments - remove these from issue-level attachments
  # Only attachments explicitly matched to comments will be removed from the defect-level
  comment_att_ids = comments_array.flat_map { |c| (c['_comment_attachments'] || []).map { |a| a['id'] || a['filename'] } }

  if $verbose_flag
    vputs "[DEBUG-FILTER] Total attachments: #{attachments_array.length}"
    vputs "[DEBUG-FILTER] Matched to comments: #{comment_att_ids.length}"
  end

  # Remove comment attachments from issue-level array - remaining attachments stay on the defect
  if comment_att_ids.any?
    attachments_array = (attachments_array || []).reject { |a| comment_att_ids.include?(a['id'] || a['filename']) }
    vputs "[INFO] #{comment_att_ids.length} attachment(s) matched to comments; will import as comment-level attachments" if $verbose_flag
    vputs "[DEBUG-FILTER] After filtering: #{attachments_array.length} issue-level attachments remaining (will be attached to defect)" if $verbose_flag
  end

  # Map users with fallbacks (using dynamic first+last name matching)
  reporter_user = find_user_by_name_or_map(reporter_name, reporter_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)
  assignee_user = find_user_by_name_or_map(assignee_name, assignee_email, verbose: verbose) || User.find_by(id: DEFAULT_USER_UUID)

  # ID used for created_by/modified_by when creating related records
  created_by_uid = reporter_user&.id || DEFAULT_CREATED_BY || DEFAULT_USER_UUID

  # Determine or create status using dynamic name matching
  status = nil
  begin
    status = find_or_create_status(jira_status_name, created_by: created_by_uid, verbose: verbose) if jira_status_name.present?
  rescue StandardError => e
    vputs "[WARN] Could not find/create status #{jira_status_name}: #{e.class}: #{e.message}" if verbose
    status = Status.where('lower(name) = ?', jira_status_name.to_s.downcase).first
  end

  # Banking type (create or fallback using dynamic matching)
  banking = nil
  begin
    if banking_type_name.present?
      banking = find_or_create_banking_type(banking_type_name, product_id: product_id, created_by: created_by_uid, verbose: verbose)
      vputs "[INFO] Banking type for #{issue_key}: '#{banking_type_name}' -> #{banking&.id || 'FALLBACK'}" if verbose
    end
  rescue StandardError => e
    vputs "[WARN] Could not find/create banking type #{banking_type_name}: #{e.class}: #{e.message}" if verbose
    banking = BankingType.find_by(id: FALLBACK_BANKING_TYPE_ID) if FALLBACK_BANKING_TYPE_ID
  end

  # Apply fallback if no banking type found
  if banking.nil? && defined?(FALLBACK_BANKING_TYPE_ID) && FALLBACK_BANKING_TYPE_ID
    banking = BankingType.find_by(id: FALLBACK_BANKING_TYPE_ID)
    vputs "[BANKING-FALLBACK] Using fallback banking type -> #{FALLBACK_BANKING_TYPE_ID}" if verbose && banking
  end

  # Create/find modules
  parent_module, child_module = find_or_create_modules(
    module_name: module_name,
    submodule_name: submodule_name,
    product_id: product_id,
    created_by: created_by_uid
  )

  # Apply fallbacks if modules weren't created/found
  parent_module ||= QaModule.find_by(id: FALLBACK_QA_MODULE_ID) if defined?(FALLBACK_QA_MODULE_ID) && FALLBACK_QA_MODULE_ID
  child_module ||= QaModule.find_by(id: FALLBACK_SUBMODULE_ID) if defined?(FALLBACK_SUBMODULE_ID) && FALLBACK_SUBMODULE_ID

  # DRY RUN: Just show what would happen
  if dry_run
    # Count comment attachments for dry-run output
    comment_att_count = comments_array.flat_map { |c| (c['_comment_attachments'] || []).length }.sum
    issue_att_count = attachments_array.length

    vputs "[DRY] Would process Defect #{issue_key}:"
    vputs "      summary: #{summary.inspect}"
    vputs "      product_id: #{product_id}"
    vputs "      reporter: #{reporter_name.presence || 'MISSING'} -> #{reporter_user&.id}"
    vputs "      assignee: #{assignee_name.presence || 'MISSING'} -> #{assignee_user&.id}"
    vputs "      status: #{jira_status_name} -> #{status&.id}"
    vputs "      priority: #{jira_priority}"
    vputs "      module: #{module_name} -> #{parent_module&.id || ('FALLBACK:' + FALLBACK_QA_MODULE_ID.to_s)}"
    vputs "      submodule: #{submodule_name} -> #{child_module&.id || ('FALLBACK:' + FALLBACK_SUBMODULE_ID.to_s)}"
    vputs "      banking: #{banking_type_name} -> #{banking&.id || ('FALLBACK:' + FALLBACK_BANKING_TYPE_ID.to_s)}"
    vputs "      labels: #{labels_array.length} #{labels_array.inspect}"
    vputs "      comments: #{comments_array.length}"
    vputs "      attachments (issue-level): #{issue_att_count}"
    if issue_att_count > 0
      issue_names = (attachments_array || []).map { |a| a['filename'] || a['name'] || a['id'] }
      vputs "        - #{issue_names.join(', ')}"
    end
    vputs "      attachments (comment-level): #{comment_att_count}"
    if comment_att_count > 0
      comment_names = comments_array.flat_map { |c| (c['_comment_attachments'] || []).map { |a| a['filename'] || a['name'] || a['id'] } }
      vputs "        - #{comment_names.join(', ')}"
    end
    return :ok
  end

  # ACTUAL IMPORT - find or create defect by defect_unique
  saved_defect = nil
  result = nil
  ActiveRecord::Base.transaction do
    # Try to find or initialize; track if it's new
    defect = Defect.find_or_initialize_by(defect_unique: issue_key)
    created_flag = defect.new_record?

    # ALWAYS update core attributes (even for existing records) to sync with latest Jira data
    defect.product_id = product_id
    defect.summary = summary if summary.present?
    defect.content = description if description.present?
    defect.priority = jira_priority if jira_priority.present?
    defect.issue_type = issue_type if issue_type.present?

    # ALWAYS update relationships with actual module data
    defect.qa_module_id = parent_module&.id || FALLBACK_QA_MODULE_ID
    defect.submodule_id = child_module&.id || FALLBACK_SUBMODULE_ID
    defect.banking_type_id = banking&.id || FALLBACK_BANKING_TYPE_ID

    if verbose
      vputs "[DEFECT-UPDATE] Setting relationships for #{issue_key}:"
      vputs "  - qa_module_id: #{defect.qa_module_id}"
      vputs "  - submodule_id: #{defect.submodule_id}"
      vputs "  - banking_type_id: #{defect.banking_type_id}"
    end

    # Update audit fields (preserve creator for existing, set for new)
    if created_flag
      # New record: set creator fields
      defect.creator_id = reporter_user.id if defect.respond_to?(:creator_id) && reporter_user
      defect.created_by = reporter_user.id if defect.respond_to?(:created_by) && reporter_user
      defect.created_at = created_at if created_at
    end
    # Always update modified_by and updated_at for both new and existing records
    defect.modified_by = reporter_user.id if defect.respond_to?(:modified_by) && reporter_user
    defect.updated_at = updated_at if updated_at

    defect.draft = false if defect.respond_to?(:draft)
    defect.retest_count = 0 if defect.respond_to?(:retest_count)

    begin
      defect.save!
      if verbose
        vputs "[DEFECT-SAVED] Successfully saved #{issue_key}"
        vputs "  - Defect ID: #{defect.id}"
        vputs "  - Banking Type ID in DB: #{defect.reload.banking_type_id}"
      end
    rescue ActiveRecord::RecordNotUnique
      # Race: another process inserted same defect_unique between find and save.
      defect = Defect.find_by(defect_unique: issue_key)
      created_flag = false

      # Re-apply attributes and persist update
      defect.product_id = product_id
      defect.summary = summary if summary.present?
      defect.content = description if description.present?
      defect.priority = jira_priority if jira_priority.present?
      defect.issue_type = issue_type if issue_type.present?
      defect.qa_module_id = parent_module&.id || FALLBACK_QA_MODULE_ID
      defect.submodule_id = child_module&.id || FALLBACK_SUBMODULE_ID
      defect.banking_type_id = banking&.id || FALLBACK_BANKING_TYPE_ID
      defect.creator_id = reporter_user.id if defect.respond_to?(:creator_id) && reporter_user
      defect.created_by = reporter_user.id if defect.respond_to?(:created_by) && reporter_user
      defect.modified_by = reporter_user.id if defect.respond_to?(:modified_by) && reporter_user
      defect.updated_at = updated_at if updated_at
      defect.draft = false if defect.respond_to?(:draft)
      defect.save!
      if verbose
        vputs "[DEFECT-SAVED] Successfully updated #{issue_key} after race condition"
        vputs "  - Banking Type ID in DB: #{defect.reload.banking_type_id}"
      end
    end

    # Update assignee (sync with Jira: always replace to match latest Jira state)
    # Always set assignee if we have a valid user, overwriting any existing assignment
    if assignee_user
      defect.user_ids = [assignee_user.id]
      vputs "[ASSIGNEE] Set assignee to #{assignee_user.first_name} #{assignee_user.last_name} (#{assignee_user.id})" if verbose
    end

    # Update status (sync with Jira: always replace to match latest Jira state)
    defect.status_ids = [status.id] if status

    # Log action and track changes
    if created_flag
      vputs "[IMPORT] Created defect #{issue_key} id=#{defect.id}"
    elsif verbose
      vputs "[IMPORT] Updated defect #{issue_key} id=#{defect.id} (synced with latest Jira data)"
    end
    # commit transaction and then perform attachment uploads to ensure files are persisted even if transaction rolls back elsewhere
    saved_defect = defect
    # end transaction block
    result = created_flag ? :created : :updated
    result
  end
  # After transaction, perform attachments (outside transaction to ensure service upload completes)
  begin
    fetch_and_attach_attachments(saved_defect, attachments_array, verbose: verbose) if %i[created updated].include?(result) && attachments_array && attachments_array.any?
  rescue StandardError => e
    warn "[WARN] Failed to attach files for #{issue_key}: #{e.class}: #{e.message}"
  end

  # Attach labels (after transaction to ensure defect is persisted)
  begin
    if %i[created updated].include?(result) && labels_array && labels_array.any?
      # Reload defect to ensure it's fully persisted before attaching labels
      saved_defect.reload
      attach_labels_to_defect(saved_defect, labels_array, created_by: created_by_uid, verbose: verbose)

      # Verify labels were attached
      if verbose
        label_count = saved_defect.labels.count
        vputs "[INFO] Defect #{issue_key} now has #{label_count} label(s) attached"
      end
    end
  rescue StandardError => e
    warn "[WARN] Failed to attach labels for #{issue_key}: #{e.class}: #{e.message}"
    warn "  Backtrace: #{e.backtrace.first(3).join("\n  ")}" if verbose
  end

  # Import comments (after attachments so attachments are already present)
  begin
    if %i[created updated].include?(result) && comments_array && comments_array.any?
      vputs "[COMMENTS] Importing #{comments_array.length} comment(s) for #{issue_key}..." if verbose
      comment_stats = import_comments_for_defect(saved_defect, comments_array, verbose: verbose)

      # Verify comments were saved
      if verbose && comment_stats[:imported] > 0
        comment_count = saved_defect.defect_messages.count
        vputs "[COMMENTS-VERIFY] DefectMessage records in DB for #{issue_key}: #{comment_count}"
        if comment_count > 0
          latest = saved_defect.defect_messages.order(created_at: :desc).first
          user = User.find_by(id: latest.user_id)
          user_name = user ? "#{user.first_name} #{user.last_name}" : 'UNKNOWN'
          content_preview = begin
            latest.content.to_plain_text.truncate(60)
          rescue StandardError
            'N/A'
          end
          attachment_count = latest.attachments.count
          vputs "  - Latest: by #{user_name} at #{latest.created_at}"
          vputs "  - Content: #{content_preview}"
          vputs "  - Attachments: #{attachment_count}" if attachment_count > 0
        end
      end
    end
  rescue StandardError => e
    warn "[WARN] Failed to import comments for #{issue_key}: #{e.class}: #{e.message}"
  end

  # Fetch and import issue changelog/history
  begin
    if %i[created updated].include?(result)
      vputs "[HISTORY] Fetching changelog for #{issue_key}..." if verbose
      changelog = fetch_issue_changelog(issue_key, verbose: verbose)

      if changelog && changelog.any?
        vputs "[HISTORY] Retrieved #{changelog.length} changelog entries from Jira for #{issue_key}" if verbose

        # Parse all changelog entries into structured format
        all_history_entries = changelog.flat_map do |history|
          parse_changelog_entry(history, issue_key, verbose: verbose)
        end

        if verbose && all_history_entries.any?
          # Show summary of event types captured
          event_types = all_history_entries.group_by { |h| h[:history_type] }.transform_values(&:count)
          vputs "[HISTORY] Captured #{all_history_entries.length} total events for #{issue_key}:"
          event_types.sort_by { |_k, v| -v }.each do |type, count|
            vputs "  - #{type}: #{count} event(s)"
          end
        end

        # Sort history entries by timestamp (oldest first for logical import order)
        all_history_entries.sort_by! { |h| h[:created_at] || Time.at(0) }

        # Import the parsed history entries into DefectHistory
        if all_history_entries.any?
          import_histories_for_defect(saved_defect, all_history_entries, verbose: verbose)

          # Verify history was saved
          if verbose
            history_count = saved_defect.defect_histories.count
            vputs "[HISTORY-VERIFY] DefectHistory records in DB for #{issue_key}: #{history_count}"
            if history_count > 0
              latest = saved_defect.defect_histories.order(created_at: :desc).first
              vputs "  - Latest: #{latest.history_type} at #{latest.created_at}"
            end
          end
        end
      elsif verbose
        vputs "[HISTORY] No changelog entries found for #{issue_key}"
      end
    end
  rescue StandardError => e
    warn "[WARN] Failed to import history for #{issue_key}: #{e.class}: #{e.message}"
  end

  # COMPREHENSIVE VERIFICATION: Check all attachments before moving to next defect
  begin
    if %i[created updated].include?(result)
      vputs '' if verbose
      vputs '[VERIFY] ' + ('=' * 70) if verbose
      vputs "[VERIFY] Final verification for defect: #{saved_defect.defect_unique}" if verbose
      vputs '[VERIFY] ' + ('=' * 70) if verbose

      # Reload to ensure we have latest data
      saved_defect.reload

      # Verify issue-level attachments
      issue_level_files = saved_defect.attachments.map { |a| a.filename.to_s }
      issue_level_missing = []

      saved_defect.attachments.each do |att|
        exists = ActiveStorage::Blob.service.exist?(att.blob.key)
        issue_level_missing << att.filename.to_s unless exists
      rescue StandardError => e
        issue_level_missing << att.filename.to_s
        warn "[VERIFY-ERROR] Failed to verify issue-level attachment #{att.filename}: #{e.message}"
      end

      vputs "[VERIFY] Issue-level attachments: #{issue_level_files.length} file(s)" if verbose
      if issue_level_files.any?
        vputs "[VERIFY]   Files: #{issue_level_files.join(', ')}" if verbose
        if issue_level_missing.any?
          warn "[VERIFY] ⚠️  Missing from storage: #{issue_level_missing.join(', ')}"
        elsif verbose
          vputs '[VERIFY]   ✅ All issue-level files verified in storage'
        end
      end

      # Verify comment-level attachments with detailed reporting
      comment_level_stats = {
        total_comments: 0,
        comments_with_attachments: 0,
        total_files: 0,
        verified_files: 0,
        missing_files: []
      }

      saved_defect.defect_messages.each do |dm|
        comment_level_stats[:total_comments] += 1

        # Check if DefectMessage has attachments association (may not be available in older versions)
        next unless dm.respond_to?(:attachments)

        begin
          next unless dm.attachments.any?

          comment_level_stats[:comments_with_attachments] += 1

          dm.attachments.each do |att|
            comment_level_stats[:total_files] += 1
            filename = att.filename.to_s

            begin
              exists = ActiveStorage::Blob.service.exist?(att.blob.key)
              if exists
                comment_level_stats[:verified_files] += 1
              else
                comment_level_stats[:missing_files] << "#{filename} (comment #{dm.id})"
              end
            rescue StandardError => e
              comment_level_stats[:missing_files] << "#{filename} (comment #{dm.id}, error: #{e.message})"
            end
          end
        rescue NoMethodError => e
          # DefectMessage model may not have attachments association in older versions
          vputs "[VERIFY-SKIP] DefectMessage attachments not available: #{e.message}" if verbose
        end
      end

      vputs '[VERIFY] Comment-level attachments:' if verbose
      vputs "[VERIFY]   Total comments: #{comment_level_stats[:total_comments]}" if verbose
      vputs "[VERIFY]   Comments with attachments: #{comment_level_stats[:comments_with_attachments]}" if verbose
      vputs "[VERIFY]   Total attachment files: #{comment_level_stats[:total_files]}" if verbose
      vputs "[VERIFY]   Verified in storage: #{comment_level_stats[:verified_files]}" if verbose

      if comment_level_stats[:missing_files].any?
        warn "[VERIFY] ⚠️  Missing comment attachments (#{comment_level_stats[:missing_files].length}):"
        comment_level_stats[:missing_files].each do |missing|
          warn "[VERIFY]     - #{missing}"
        end
      elsif verbose
        vputs '[VERIFY]   ✅ All comment-level files verified in storage'
      end

      # Overall summary
      total_attachments = issue_level_files.length + comment_level_stats[:total_files]
      total_missing = issue_level_missing.length + comment_level_stats[:missing_files].length

      vputs '' if verbose
      if total_missing > 0
        warn "[VERIFY] ⚠️  DEFECT #{saved_defect.defect_unique}: #{total_missing}/#{total_attachments} attachment(s) missing from storage!"
        warn '[VERIFY] This will cause 404 errors when users try to view/download these files.'
        warn '[VERIFY] Consider re-running the import for this defect to retry failed uploads.'
      elsif verbose
        vputs "[VERIFY] ✅ DEFECT #{saved_defect.defect_unique}: All #{total_attachments} attachment(s) verified successfully!"
      end
      vputs '[VERIFY] ' + ('=' * 70) if verbose
      vputs '' if verbose
    end
  rescue StandardError => e
    warn "[VERIFY-ERROR] Could not complete verification for #{issue_key}: #{e.class}: #{e.message}"
    warn "[VERIFY-ERROR] Backtrace: #{e.backtrace.first(3).join(', ')}" if verbose
  end

  :ok
rescue ActiveRecord::RecordInvalid => e
  warn "[ERROR] Failed to save defect #{issue_key}: #{e.record.errors.full_messages.join(', ')}"
  :error
rescue StandardError => e
  warn "[EXCEPTION] issue=#{issue_key} #{e.class}: #{e.message}"
  :error
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

      next unless defect

      info "  Verified #{index + 1}/#{issues.length} defects..." if (index + 1) % 100 == 0

      fields = issue['fields'] || {}

      # Verify comments
      expected_comments = (fields.dig('comment', 'comments') || []).length
      actual_comments = defect.defect_messages.count
      if expected_comments > actual_comments
        verification_stats[:missing_comments] += (expected_comments - actual_comments)
        vputs "[VERIFY] #{issue_key}: Missing #{expected_comments - actual_comments} comment(s)" if options[:verbose]

        # Re-import missing comments
        begin
          comments_array = fields.dig('comment', 'comments') || []
          import_comments_for_defect(defect, comments_array, verbose: false) if comments_array.any?
          new_count = defect.defect_messages.count
          if new_count > actual_comments
            verification_stats[:fixed_comments] += (new_count - actual_comments)
            vputs "[FIX] #{issue_key}: Added #{new_count - actual_comments} missing comment(s)" if options[:verbose]
          end
        rescue StandardError => e
          vputs "[ERROR] Failed to fix comments for #{issue_key}: #{e.message}" if options[:verbose]
        end
      end

      # Verify attachments
      expected_attachments = (fields['attachment'] || fields['attachments'] || []).length
      actual_attachments = defect.attachments.count
      if expected_attachments > actual_attachments
        verification_stats[:missing_attachments] += (expected_attachments - actual_attachments)
        vputs "[VERIFY] #{issue_key}: Missing #{expected_attachments - actual_attachments} attachment(s)" if options[:verbose]

        # Re-import missing attachments
        begin
          attachments_array = (fields['attachment'] || fields['attachments'] || []).select { |a| a.is_a?(Hash) }
          fetch_and_attach_attachments(defect, attachments_array, verbose: false) if attachments_array.any?
          new_count = defect.attachments.count
          if new_count > actual_attachments
            verification_stats[:fixed_attachments] += (new_count - actual_attachments)
            vputs "[FIX] #{issue_key}: Added #{new_count - actual_attachments} missing attachment(s)" if options[:verbose]
          end
        rescue StandardError => e
          vputs "[ERROR] Failed to fix attachments for #{issue_key}: #{e.message}" if options[:verbose]
        end
      end

      # Verify labels
      expected_labels = (fields['labels'] || []).compact.length
      actual_labels = defect.labels.count
      if expected_labels > actual_labels
        verification_stats[:missing_labels] += (expected_labels - actual_labels)
        vputs "[VERIFY] #{issue_key}: Missing #{expected_labels - actual_labels} label(s)" if options[:verbose]

        # Re-import missing labels
        begin
          labels_array = (fields['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)
          reporter_user = find_user_by_name_or_map(fields.dig('reporter', 'displayName'), fields.dig('reporter', 'emailAddress'), verbose: false) || User.find_by(id: DEFAULT_USER_UUID)
          created_by_uid = reporter_user&.id || DEFAULT_CREATED_BY || DEFAULT_USER_UUID
          defect.reload
          attach_labels_to_defect(defect, labels_array, created_by: created_by_uid, verbose: false) if labels_array.any?
          new_count = defect.labels.count
          if new_count > actual_labels
            verification_stats[:fixed_labels] += (new_count - actual_labels)
            vputs "[FIX] #{issue_key}: Added #{new_count - actual_labels} missing label(s)" if options[:verbose]
          end
        rescue StandardError => e
          vputs "[ERROR] Failed to fix labels for #{issue_key}: #{e.message}" if options[:verbose]
        end
      end

      # Verify history entries and re-import if missing
      current_history_count = defect.defect_histories.count
      next unless current_history_count == 0

      verification_stats[:missing_history] += 1
      vputs "[VERIFY] #{issue_key}: No history entries found, fetching from Jira..." if options[:verbose]

      # Fetch and re-import history
      begin
        changelog = fetch_issue_changelog(issue_key, verbose: false)
        if changelog && changelog.any?
          # Parse all changelog entries
          all_history_entries = changelog.flat_map do |history|
            parse_changelog_entry(history, issue_key, verbose: false)
          end

          # Sort and import
          all_history_entries.sort_by! { |h| h[:created_at] || Time.at(0) }

          if all_history_entries.any?
            import_histories_for_defect(defect, all_history_entries, verbose: false)
            new_history_count = defect.defect_histories.count
            if new_history_count > current_history_count
              verification_stats[:fixed_history] += (new_history_count - current_history_count)
              vputs "[FIX] #{issue_key}: Added #{new_history_count - current_history_count} history entries" if options[:verbose]
            end
          end
        end
      rescue StandardError => e
        vputs "[ERROR] Failed to fix history for #{issue_key}: #{e.message}" if options[:verbose]
      end
    end

    info '✅ Verification complete!'
    if verification_stats[:missing_comments] > 0 || verification_stats[:missing_attachments] > 0 || verification_stats[:missing_labels] > 0 || verification_stats[:missing_history] > 0
      info "\n⚠️  Issues Found and Fixed:"
      info "  Missing comments: #{verification_stats[:missing_comments]} (fixed: #{verification_stats[:fixed_comments]})"
      info "  Missing attachments: #{verification_stats[:missing_attachments]} (fixed: #{verification_stats[:fixed_attachments]})"
      info "  Missing labels: #{verification_stats[:missing_labels]} (fixed: #{verification_stats[:fixed_labels]})"
      info "  Missing history: #{verification_stats[:missing_history]} (fixed: #{verification_stats[:fixed_history]})"
    else
      info '  ✓ All data verified - no issues found!'
    end
  end
rescue StandardError => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
