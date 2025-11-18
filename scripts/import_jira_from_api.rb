#!/usr/bin/env ruby
# scripts/import_jira_direct.rb

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
  project: nil,
  days_back: 2000
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/import_jira_direct.rb --project PROJECT_KEY [options]'

  opts.on('--project KEY', 'Jira project key (e.g. PSP)') { |v| options[:project] = v }
  opts.on('--dry-run', "Don't save; only show what would happen") { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
  opts.on('--days N', Integer, 'How many days back to fetch (default 2000)') { |v| options[:days_back] = v }
end.parse!

unless options[:project]
  puts 'ERROR: --project is required. Example: --project PSP'
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

info "Starting direct Jira import for project: #{options[:project]} (dry_run: #{options[:dry_run]})"

# ===============================
# JIRA API FETCHER - WITH CORRECT PAGINATION USING startAt
# ===============================
def fetch_jira_issues(project_key:, max_results: 100, days_back: 2000)
  issues = []
  next_page_token = nil
  page_count = 0
  max_pages = 500 # Safety limit to prevent infinite loops

  start_date = (Time.now - (days_back * 24 * 60 * 60)).strftime('%Y-%m-%d')
  end_date = Time.now.strftime('%Y-%m-%d')
  jql_query = "project = \"#{project_key}\" AND created >= \"#{start_date}\" ORDER BY created DESC"

  info "Fetching Jira issues with JQL: #{jql_query}"
  info "Date range: #{start_date} to #{end_date}"

  loop do
    page_count += 1

    # Safety check: don't loop forever
    if page_count > max_pages
      warn "Reached maximum page limit (#{max_pages}). Stopping pagination."
      break
    end

    # Build query parameters for /rest/api/3/search/jql endpoint
    query_params = {
      jql: jql_query,
      maxResults: max_results,
      fields: 'summary,status,reporter,assignee,created,updated,description,project,comment,priority,issuetype,parent,epic,customfield_10014'
    }

    # Add nextPageToken if available (for pagination)
    query_params[:nextPageToken] = next_page_token if next_page_token.present?

    # Build URI with query parameters
    uri = URI.parse("#{JIRA_BASE_URL}/rest/api/3/search/jql") # issues end
    uri.query = URI.encode_www_form(query_params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    # Use GET request with all parameters in query string
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

    # If no issues fetched, we've reached the end
    if fetched.empty?
      info "✓ Page #{page_count}: No issues returned - pagination complete (no more data)"
      break
    end

    issues.concat(fetched)
    total_fetched = issues.length

    # Get pagination info from Jira response
    next_page_token = data['nextPageToken'] # Use the token from response
    is_last_page = data['isLast'] == true

    # Show progress with pagination details
    info "✓ Page #{page_count}: Fetched #{fetched.length} issues (total collected: #{total_fetched}) [isLast: #{is_last_page}, hasNextToken: #{next_page_token.present? ? 'YES' : 'NO'}]"

    vputs "Page #{page_count}: Fetched #{fetched.length} distinct issues - nextPageToken available: #{next_page_token.present?}, isLast: #{is_last_page}"

    # STOP CONDITION 1: Jira explicitly says this is the last page
    if is_last_page
      info '✓ Jira indicates last page (isLast: true) - pagination complete'
      break
    end

    # STOP CONDITION 2: No more pages available (no nextPageToken)
    unless next_page_token.present?
      info '✓ No nextPageToken provided - reached end of results'
      break
    end

    # Continue to next page (use the token from Jira response)
    sleep 0.5 # Rate limiting to avoid throttling
  end

  info "📊 Total issues fetched from Jira: #{issues.length} (across #{page_count} pages)"
  issues
end # ===============================

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

def find_user_by_name_or_map(name, email = nil)
  name_str = name.to_s.strip
  email_str = email.to_s.strip

  # Handle cases where reporter might be nil
  return nil if name_str.blank? && email_str.blank?

  # 1. check explicit map (config)
  if USER_UUID_MAP[name_str]
    uid = USER_UUID_MAP[name_str]
    user = User.find_by(id: uid)
    return user if user
  end

  # try downcased map key
  if USER_UUID_MAP[name_str.downcase]
    uid = USER_UUID_MAP[name_str.downcase]
    user = User.find_by(id: uid)
    return user if user
  end

  # 2. try email lookup
  if email_str.present? && email_str.downcase != 'restricted'
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str.downcase)
    return user if user
  end

  # 3. try matching first_name + last_name
  if name_str.present?
    normalized = name_str.downcase
    user = User.where(deleted_on: nil)
      .where("lower(coalesce(first_name,'') || ' ' || coalesce(last_name,'')) = ?", normalized)
      .first
    return user if user

    parts = name_str.split
    if parts.length >= 2
      first = parts.first
      last = parts[1..].join(' ')
      user = User.where(deleted_on: nil).find_by('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
      return user if user
    end
  end

  # 4. optionally create minimal user
  if CREATE_MISSING_USERS && email_str.present? && email_str.downcase != 'restricted'
    attrs = {
      email: email_str.downcase,
      first_name: name_str.split(' ').first || 'Imported',
      last_name: name_str.split(' ')[1..]&.join(' ') || 'User',
      created_by: DEFAULT_CREATED_BY,
      modified_by: DEFAULT_CREATED_BY
    }
    created = User.create(attrs)
    return created if created.persisted?
  end

  # 5. fallback to default user
  User.find_by(id: DEFAULT_USER_UUID)
end

def find_or_create_label(name, created_by:)
  return nil if name.blank?

  normalized = name.strip
  label = Label.where('lower(name) = ?', normalized.downcase).first
  return label if label
  return nil unless CREATE_MISSING_LABELS

  Label.create!(name: normalized, created_by: created_by, modified_by: created_by)
end

def find_or_create_status(name, created_by:)
  return nil if name.blank?

  name_str = name.to_s.strip

  if STATUS_UUID_MAP[name_str]
    sid = STATUS_UUID_MAP[name_str]
    s = Status.find_by(id: sid)
    return s if s
  end

  status = Status.where('lower(name) = ?', name_str.downcase).first
  return status if status
  return nil unless CREATE_MISSING_STATUSES

  # Create status with default user_id to avoid null constraint violation
  default_user = User.find_by(id: DEFAULT_USER_UUID) || User.first
  default_user_id = default_user&.id || DEFAULT_USER_UUID

  Status.create!(
    name: name_str,
    created_by: created_by,
    modified_by: created_by,
    user_id: default_user_id # Set default user to satisfy not-null constraint
  )
end

def find_or_create_banking_type(name, product_id:, created_by:)
  return nil if name.blank?

  bt = BankingType.where('lower(name) = ? AND product_id = ?', name.to_s.strip.downcase, product_id).first
  return bt if bt
  return nil unless CREATE_MISSING_BANKING

  BankingType.create!(name: name.to_s.strip, product_id: product_id, created_by_id: created_by, modified_by_id: created_by)
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

# ===============================
# IMPORT LOGIC - WITH FALLBACKS FOR MISSING DATA
# ===============================
def import_issue(issue, dry_run: true, verbose: false)
  fields = issue['fields'] || {}
  issue_key = issue['key'].to_s.strip # Use Jira issue key as defect_unique

  jira_project_name = fields.dig('project', 'name').to_s
  jira_project_key = fields.dig('project', 'key').to_s
  product_id = PROJECT_UUID_MAP[jira_project_key] || PROJECT_UUID_MAP[jira_project_name] || DEFAULT_PRODUCT_UUID

  unless product_id
    puts "[SKIP] #{issue_key}: no product mapping for project #{jira_project_key}/#{jira_project_name}"
    return :skipped
  end

  summary = fields['summary'].to_s.strip
  description = extract_description(fields['description'])
  jira_status_name = fields.dig('status', 'name').to_s.strip
  jira_priority = fields.dig('priority', 'name').to_s.strip.presence || DEFAULT_PRIORITY
  issue_type = fields.dig('issuetype', 'name').to_s.strip.presence || 'Bug'

  # Handle missing reporter data gracefully
  reporter_data = fields['reporter'] || {}
  reporter_name = reporter_data['displayName'].to_s.strip
  reporter_email = reporter_data['emailAddress'].to_s.strip

  # Handle missing assignee data gracefully
  assignee_data = fields['assignee'] || {}
  assignee_name = assignee_data['displayName'].to_s.strip
  assignee_email = assignee_data['emailAddress'].to_s.strip

  created_at = try_parse_time(fields['created'])
  updated_at = try_parse_time(fields['updated'])

  # Get module/submodule info
  epic_key = fields.dig('epic', 'key') || fields['customfield_10014'] || ''
  parent_key = fields.dig('parent', 'key') || ''
  banking_type_name = jira_project_key

  comments_container = fields.dig('comment') || {}
  comments_array = comments_container['comments'] || []

  # Map users with fallbacks for missing data
  reporter_user = find_user_by_name_or_map(reporter_name, reporter_email) || User.find_by(id: DEFAULT_USER_UUID)
  assignee_user = find_user_by_name_or_map(assignee_name, assignee_email) || User.find_by(id: DEFAULT_USER_UUID)

  created_by_uid = reporter_user&.id || DEFAULT_CREATED_BY

  # Determine module names with fallbacks
  module_name = epic_key.present? ? "Epic: #{epic_key}" : jira_project_name
  submodule_name = parent_key.present? ? "Parent: #{parent_key}" : nil

  # Find/create related objects with fallbacks
  status = find_or_create_status(jira_status_name, created_by: created_by_uid) if jira_status_name.present?

  # Use fallback banking type if none found
  banking = find_or_create_banking_type(banking_type_name, product_id: product_id, created_by: created_by_uid)
  banking ||= BankingType.find_by(id: FALLBACK_BANKING_TYPE_ID) if FALLBACK_BANKING_TYPE_ID

  # Use fallback modules if none found
  parent_module, child_module = find_or_create_modules(
    module_name: module_name,
    submodule_name: submodule_name,
    product_id: product_id,
    created_by: created_by_uid
  )

  # Apply fallbacks if modules weren't created/found
  parent_module ||= QaModule.find_by(id: FALLBACK_QA_MODULE_ID) if FALLBACK_QA_MODULE_ID
  child_module ||= QaModule.find_by(id: FALLBACK_SUBMODULE_ID) if FALLBACK_SUBMODULE_ID

  # DRY RUN: Just show what would happen
  if dry_run
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
    vputs "      comments: #{comments_array.length}"
    return :ok
  end

  # ACTUAL IMPORT - find or create defect by defect_unique (mapped from issue_key)
  ActiveRecord::Base.transaction do
    # Find or initialize defect using issue_key as defect_unique
    defect = Defect.find_or_initialize_by(defect_unique: issue_key)
    created_flag = defect.new_record?

    # Set core attributes
    defect.product_id = product_id
    defect.summary = summary if summary.present?
    defect.content = description if description.present?
    defect.priority = jira_priority if jira_priority.present?
    defect.issue_type = issue_type if issue_type.present?

    # Assign relationships with fallbacks
    defect.qa_module_id = parent_module&.id || FALLBACK_QA_MODULE_ID
    defect.submodule_id = child_module&.id || FALLBACK_SUBMODULE_ID
    defect.banking_type_id = banking&.id || FALLBACK_BANKING_TYPE_ID

    # Audit fields with fallbacks
    defect.creator_id = reporter_user.id if defect.respond_to?(:creator_id) && reporter_user
    defect.created_by = reporter_user.id if defect.respond_to?(:created_by) && reporter_user
    defect.modified_by = reporter_user.id if defect.respond_to?(:modified_by) && reporter_user

    # Preserve Jira timestamps
    defect.created_at = created_at if created_flag && created_at
    defect.updated_at = updated_at if updated_at

    defect.draft = false if defect.respond_to?(:draft)
    defect.retest_count = 0 if defect.respond_to?(:retest_count)

    begin
      defect.save!
    rescue ActiveRecord::RecordNotUnique
      # Race condition: another process inserted the same defect_unique after our lookup.
      # Reload the now-existing record and update it instead of creating a duplicate.
      defect = Defect.find_by(defect_unique: issue_key)
      created_flag = false

      # Re-apply attributes to the reloaded record
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
    end

    # Assign assignee (only if we have one)
    defect.user_ids = [assignee_user.id] if assignee_user && assignee_user.id != DEFAULT_USER_UUID && !defect.user_ids.include?(assignee_user.id)

    # Assign status
    defect.status_ids = [status.id] if status && !defect.status_ids.include?(status.id)

    action = created_flag ? 'Created' : 'Updated'
    vputs "[IMPORT] #{action} defect #{issue_key} id=#{defect.id}"
    return :ok
  end
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
  # Step 1: Fetch from Jira API with CORRECT pagination
  # Use batch size of 100 (Jira's recommended default for stability)
  issues = fetch_jira_issues(
    project_key: options[:project],
    max_results: 100,
    days_back: options[:days_back]
  )

  if issues.empty?
    info 'No issues fetched from Jira. Exiting.'
    exit 0
  end

  info "Successfully fetched #{issues.length} issues from Jira"

  # Step 2: Import into database
  stats = { total: 0, ok: 0, skipped: 0, errors: 0 }

  issues.each_with_index do |issue, index|
    stats[:total] += 1
    info "Processing issue #{index + 1}/#{issues.length}: #{issue['key']}" if options[:verbose]

    result = import_issue(issue, dry_run: options[:dry_run], verbose: options[:verbose])

    case result
    when :ok
      stats[:ok] += 1
    when :skipped
      stats[:skipped] += 1
    when :error
      stats[:errors] += 1
    end
  end

  # Summary
  info "\n🎉 Import completed!"
  info 'Summary:'
  info "  Total issues processed: #{stats[:total]}"
  info "  Successfully imported: #{stats[:ok]}" unless options[:dry_run]
  info "  Would import: #{stats[:ok]}" if options[:dry_run]
  info "  Skipped: #{stats[:skipped]}"
  info "  Errors: #{stats[:errors]}"
rescue StandardError => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
