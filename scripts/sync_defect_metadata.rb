#!/usr/bin/env ruby
# scripts/sync_defect_metadata.rb
#
# Purpose: Sync metadata (modules, submodules, labels, banking types) from Jira to local defects
# Usage:
#   - Whole project: rails runner scripts/sync_defect_metadata.rb --verbose --project ISP -e production
#   - Specific defect: rails runner scripts/sync_defect_metadata.rb --verbose --project ISP-1999 -e production

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
  verbose: false,
  project: nil,
  defect_unique: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/sync_defect_metadata.rb [options]'

  opts.on('--project PROJECT', 'Project key (e.g., ISP) or specific issue key (e.g., ISP-1999)') { |v| options[:project] = v }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
  opts.on('-h', '--help', 'Display this help message') do
    puts opts
    exit
  end
end.parse!

# Determine if we're syncing a whole project or a specific defect
if options[:project].nil?
  puts 'ERROR: --project is required'
  puts 'Examples:'
  puts '  Whole project: rails runner scripts/sync_defect_metadata.rb --verbose --project ISP -e production'
  puts '  Specific defect: rails runner scripts/sync_defect_metadata.rb --verbose --project ISP-1999 -e production'
  exit 1
end

# Parse project argument to determine if it's a project key or issue key
if options[:project].include?('-') && options[:project].match?(/[A-Z]+-\d+/)
  # Specific issue key (e.g., ISP-1999)
  options[:defect_unique] = options[:project]
  options[:project] = options[:project].split('-').first
  puts "Mode: Syncing specific defect #{options[:defect_unique]}"
else
  # Whole project (e.g., ISP)
  puts "Mode: Syncing all defects in project #{options[:project]}"
end

# Load configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

# Jira credentials
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

# Configuration
PROJECT_UUID_MAP = CONFIG[:project_uuid_map] || {}
DEFAULT_PRODUCT_UUID = CONFIG[:default_product_id]
DEFAULT_USER_UUID = CONFIG[:default_user_uuid]
DEFAULT_CREATED_BY = CONFIG[:default_created_by] || DEFAULT_USER_UUID
CREATE_MISSING_LABELS = CONFIG.fetch(:create_missing_labels, true)
CREATE_MISSING_MODULES = CONFIG.fetch(:create_missing_modules, true)
CREATE_MISSING_BANKING = CONFIG.fetch(:create_missing_banking_types, true)

$verbose_flag = options[:verbose]

def vputs(msg)
  puts msg if $verbose_flag
end

def info(msg)
  puts msg
end

# ===============================
# JIRA API METHODS
# ===============================

# Discover custom fields for modules, submodules, and banking types
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
    return [nil, nil, nil]
  end

  fields = JSON.parse(response.body)
  module_field = nil
  submodule_field = nil
  banking_type_field = nil

  fields.each do |field|
    name = field['name']&.downcase || ''
    field_id = field['id']

    # Look for module-related fields
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

# Fetch a single Jira issue by key
def fetch_jira_issue(issue_key, custom_fields)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
  uri = URI.parse(url)

  # Build fields list
  fields_to_fetch = %w[key summary labels]
  fields_to_fetch << custom_fields[:module_field] if custom_fields[:module_field]
  fields_to_fetch << custom_fields[:submodule_field] if custom_fields[:submodule_field]
  fields_to_fetch << custom_fields[:banking_type_field] if custom_fields[:banking_type_field]

  uri.query = URI.encode_www_form({ fields: fields_to_fetch.join(',') })

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  vputs "Fetching Jira issue: #{issue_key}..."

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    warn "❌ Failed to fetch issue #{issue_key}: #{response.code} #{response.message}"
    return nil
  end

  JSON.parse(response.body)
end

# Fetch all issues from a project
def fetch_project_issues(project_key, custom_fields)
  issues = []
  start_at = 0
  max_results = 100

  # Build fields list
  fields_to_fetch = %w[key summary labels]
  fields_to_fetch << custom_fields[:module_field] if custom_fields[:module_field]
  fields_to_fetch << custom_fields[:submodule_field] if custom_fields[:submodule_field]
  fields_to_fetch << custom_fields[:banking_type_field] if custom_fields[:banking_type_field]

  loop do
    url = "#{JIRA_BASE_URL}/rest/api/3/search"
    uri = URI.parse(url)

    jql = "project = #{project_key} ORDER BY created DESC"
    query_params = {
      jql: jql,
      startAt: start_at,
      maxResults: max_results,
      fields: fields_to_fetch.join(',')
    }

    uri.query = URI.encode_www_form(query_params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    vputs "Fetching issues from project #{project_key} (start_at=#{start_at})..."

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      warn "❌ Failed to fetch issues: #{response.code} #{response.message}"
      break
    end

    data = JSON.parse(response.body)
    fetched = data['issues'] || []
    total = data['total'] || 0

    issues.concat(fetched)

    vputs "Fetched #{fetched.length} issues (total so far: #{issues.length}/#{total})"

    break if issues.length >= total
    break if fetched.empty?

    start_at += fetched.length
    sleep 0.5 # Rate limiting
  end

  info "📊 Total issues fetched: #{issues.length}"
  issues
end

# ===============================
# HELPER METHODS
# ===============================

# Extract custom field value
def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data.to_s.strip if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    # Handle cascading select fields
    return field_data['child']['value'].to_s.strip if field_data['child'].is_a?(Hash) && field_data['child']['value'].present?

    return field_data['value'].to_s.strip if field_data['value'].present?
    return field_data['name'].to_s.strip if field_data['name'].present?
    return field_data['key'].to_s.strip if field_data['key'].present?
    return field_data['id'].to_s.strip if field_data['id'].present?
  end

  if field_data.is_a?(Array) && field_data.any?
    first_item = field_data.first
    return extract_custom_field_value(first_item) if first_item.is_a?(Hash)
    return first_item.to_s.strip
  end

  field_data.to_s.strip
end

# Parse module and submodule from a single string
def parse_module_and_submodule(module_name_str, submodule_name_str)
  mod = module_name_str.to_s.strip
  sub = submodule_name_str.to_s.strip

  return [mod, sub] if sub.present?
  return [mod, sub] if mod.blank?

  # Split on first hyphen
  parts = mod.split(/\s*[-\u2013\u2014]\s*/, 2)
  if parts.length == 2
    derived_mod = parts[0].strip
    derived_sub = parts[1].strip
    return [derived_mod, derived_sub]
  end

  [mod, sub]
end

# Find or create label
def find_or_create_label(name, created_by:)
  return nil if name.blank?

  normalized = name.strip
  search_name = normalized.downcase.gsub(/\s+/, '-').gsub(/-+/, '-')

  label = Label.where('lower(name) = ?', search_name).first
  if label
    vputs "[LABEL-MATCH] Found existing label '#{normalized}' -> #{label.id}"
    return label
  end

  return nil unless CREATE_MISSING_LABELS

  begin
    label = Label.new(name: normalized, created_by: created_by, modified_by: created_by)
    if label.save
      vputs "[LABEL-CREATE] Created new label '#{normalized}' -> #{label.id}"
      label
    else
      vputs "[LABEL-ERROR] Failed to create label '#{normalized}': #{label.errors.full_messages.join(', ')}"
      nil
    end
  rescue StandardError => e
    vputs "[LABEL-ERROR] Exception creating label '#{normalized}': #{e.class}: #{e.message}"
    nil
  end
end

# Attach labels to defect
def attach_labels_to_defect(defect, labels_array, created_by:)
  return if labels_array.nil? || labels_array.empty?

  vputs "[LABEL] Processing #{labels_array.length} label(s) for #{defect.defect_unique}"

  labels_array.each do |label_name|
    next if label_name.blank?

    begin
      label = find_or_create_label(label_name, created_by: created_by)
      next unless label

      if defect.labels.exists?(label.id)
        vputs "[LABEL-SKIP] Label '#{label.name}' already attached to #{defect.defect_unique}"
        next
      end

      defect.labels << label

      if defect.labels.exists?(label.id)
        join_record = defect.defect_labels.find_by(label_id: label.id)
        join_record.update_columns(created_by: created_by, modified_by: created_by) if join_record.respond_to?(:created_by=)
        vputs "[LABEL-ATTACH] Successfully attached label '#{label.name}' to #{defect.defect_unique}"
      end
    rescue StandardError => e
      vputs "[LABEL-ERROR] Exception attaching label '#{label_name}': #{e.class}: #{e.message}"
      next
    end
  end

  vputs "[LABEL] Completed processing labels for #{defect.defect_unique}. Total attached: #{defect.labels.count}"
end

# Find or create banking type
def find_or_create_banking_type(name, product_id:, created_by:)
  return nil if name.blank?

  name_str = name.to_s.strip
  product = Product.find_by(id: product_id)
  return nil unless product

  bt = BankingType.where('lower(name) = ?', name_str.downcase).first

  if bt
    vputs "[BANKING-MATCH] Found existing banking type '#{name_str}' -> #{bt.id}"
  else
    return nil unless CREATE_MISSING_BANKING

    begin
      bt = BankingType.create!(
        name: name_str,
        created_by_id: created_by,
        modified_by_id: created_by
      )
      vputs "[BANKING-CREATE] Created new banking type '#{name_str}' -> #{bt.id}"
    rescue StandardError => e
      vputs "[BANKING-ERROR] Failed to create banking type '#{name_str}': #{e.class}: #{e.message}"
      return nil
    end
  end

  # Ensure association with product
  if bt && !bt.products.exists?(product.id)
    begin
      bt.products << product
      vputs "[BANKING-LINK] Linked banking type '#{bt.name}' to product '#{product.document_name}'"
    rescue StandardError => e
      vputs "[BANKING-ERROR] Failed to link banking type: #{e.message}"
    end
  end

  bt
end

# Find or create modules
def find_or_create_modules(module_name:, submodule_name:, product_id:, created_by:)
  parent = nil
  child = nil

  # Find or create parent module
  if module_name.present?
    parent = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', module_name.strip.downcase, product_id).first
    if parent.nil? && CREATE_MISSING_MODULES
      parent = QaModule.create!(name: module_name.strip, product_id: product_id)
      parent.update_columns(created_by: created_by, modified_by: created_by) if parent.respond_to?(:created_by)
      vputs "[MODULE-CREATE] Created parent module '#{module_name}' -> #{parent.id}"
    else
      vputs "[MODULE-MATCH] Found parent module '#{module_name}' -> #{parent.id}" if parent
    end
  end

  # Find or create child module (submodule)
  if submodule_name.present?
    if parent
      child = QaModule.where('lower(name) = ? AND parent_id = ? AND product_id = ?', submodule_name.strip.downcase, parent.id, product_id).first
      if child.nil? && CREATE_MISSING_MODULES
        child = QaModule.create!(name: submodule_name.strip, parent_id: parent.id, product_id: product_id)
        child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
        vputs "[SUBMODULE-CREATE] Created submodule '#{submodule_name}' -> #{child.id}"
      else
        vputs "[SUBMODULE-MATCH] Found submodule '#{submodule_name}' -> #{child.id}" if child
      end
    else
      child = QaModule.where('lower(name) = ? AND parent_id IS NOT NULL AND product_id = ?', submodule_name.strip.downcase, product_id).first
      if child && child.parent_id.present?
        parent = QaModule.find_by(id: child.parent_id)
        vputs "[SUBMODULE-MATCH] Found submodule '#{submodule_name}' with parent -> #{child.id}"
      else
        child = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', submodule_name.strip.downcase, product_id).first
        if child.nil? && CREATE_MISSING_MODULES
          child = QaModule.create!(name: submodule_name.strip, product_id: product_id)
          child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
          vputs "[SUBMODULE-CREATE] Created standalone submodule '#{submodule_name}' -> #{child.id}"
        end
      end
    end
  end

  [parent, child]
end

# ===============================
# SYNC LOGIC
# ===============================

def sync_defect_metadata(defect, jira_issue, custom_fields, product_id)
  fields = jira_issue['fields'] || {}
  issue_key = jira_issue['key']

  # Extract metadata from Jira
  module_name = extract_custom_field_value(fields[custom_fields[:module_field]] || '') if custom_fields[:module_field]
  submodule_name = extract_custom_field_value(fields[custom_fields[:submodule_field]] || '') if custom_fields[:submodule_field]
  banking_type_name = extract_custom_field_value(fields[custom_fields[:banking_type_field]] || '') if custom_fields[:banking_type_field]
  labels_array = (fields['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)

  # Parse module/submodule
  if module_name.present? && submodule_name.to_s.strip.empty?
    original_module = module_name.dup
    module_name, submodule_name = parse_module_and_submodule(module_name, submodule_name)
    vputs "[MODULE-PARSE] Derived module/submodule from '#{original_module}' => module='#{module_name}', submodule='#{submodule_name}'" if submodule_name.present?
  end

  created_by_uid = DEFAULT_CREATED_BY || DEFAULT_USER_UUID

  updated = false

  # Update modules
  if module_name.present? || submodule_name.present?
    parent_module, child_module = find_or_create_modules(
      module_name: module_name,
      submodule_name: submodule_name,
      product_id: product_id,
      created_by: created_by_uid
    )

    if parent_module && defect.qa_module_id != parent_module.id
      defect.qa_module_id = parent_module.id
      updated = true
      vputs "[UPDATE] Updated module for #{issue_key}: #{parent_module.name}"
    end

    if child_module && defect.submodule_id != child_module.id
      defect.submodule_id = child_module.id
      updated = true
      vputs "[UPDATE] Updated submodule for #{issue_key}: #{child_module.name}"
    end
  end

  # Update banking type
  if banking_type_name.present?
    banking = find_or_create_banking_type(banking_type_name, product_id: product_id, created_by: created_by_uid)
    if banking && defect.banking_type_id != banking.id
      defect.banking_type_id = banking.id
      updated = true
      vputs "[UPDATE] Updated banking type for #{issue_key}: #{banking.name}"
    end
  end

  # Save changes
  if updated
    defect.save!
    info "[SAVED] Updated metadata for #{issue_key}"
  else
    vputs "[NO-CHANGE] No metadata changes for #{issue_key}"
  end

  # Update labels (always check for new labels)
  attach_labels_to_defect(defect, labels_array, created_by: created_by_uid) if labels_array.any?

  { updated: updated, labels_count: labels_array.length }
end

# ===============================
# MAIN EXECUTION
# ===============================

begin
  # Discover custom fields
  custom_fields_array = discover_custom_fields
  custom_fields = {
    module_field: custom_fields_array[0],
    submodule_field: custom_fields_array[1],
    banking_type_field: custom_fields_array[2]
  }

  info "\nUsing custom fields:"
  info "  Module: #{custom_fields[:module_field] || 'Not found'}"
  info "  Submodule: #{custom_fields[:submodule_field] || 'Not found'}"
  info "  Banking Type: #{custom_fields[:banking_type_field] || 'Not found'}"
  info ""

  # Get product ID
  product_id = PROJECT_UUID_MAP[options[:project]] || DEFAULT_PRODUCT_UUID
  unless product_id
    puts "ERROR: No product mapping found for project #{options[:project]}"
    exit 1
  end

  stats = {
    total: 0,
    updated: 0,
    no_change: 0,
    not_found: 0,
    errors: 0,
    labels_attached: 0
  }

  if options[:defect_unique]
    # Sync specific defect
    info "Syncing defect: #{options[:defect_unique]}"

    jira_issue = fetch_jira_issue(options[:defect_unique], custom_fields)
    unless jira_issue
      puts "ERROR: Failed to fetch Jira issue #{options[:defect_unique]}"
      exit 1
    end

    defect = Defect.find_by(defect_unique: options[:defect_unique])
    unless defect
      puts "ERROR: Defect #{options[:defect_unique]} not found in local database"
      exit 1
    end

    stats[:total] = 1
    result = sync_defect_metadata(defect, jira_issue, custom_fields, product_id)
    if result[:updated]
      stats[:updated] = 1
    else
      stats[:no_change] = 1
    end
    stats[:labels_attached] = result[:labels_count]
  else
    # Sync all defects in project
    info "Syncing all defects in project: #{options[:project]}"

    jira_issues = fetch_project_issues(options[:project], custom_fields)

    if jira_issues.empty?
      puts 'No issues found in Jira'
      exit 0
    end

    jira_issues.each_with_index do |jira_issue, idx|
      issue_key = jira_issue['key']
      stats[:total] += 1

      info "\n[#{idx + 1}/#{jira_issues.length}] Processing #{issue_key}..."

      defect = Defect.find_by(defect_unique: issue_key)
      unless defect
        vputs "[SKIP] Defect #{issue_key} not found in local database"
        stats[:not_found] += 1
        next
      end

      begin
        result = sync_defect_metadata(defect, jira_issue, custom_fields, product_id)
        if result[:updated]
          stats[:updated] += 1
        else
          stats[:no_change] += 1
        end
        stats[:labels_attached] += result[:labels_count]
      rescue StandardError => e
        warn "[ERROR] Failed to sync #{issue_key}: #{e.class}: #{e.message}"
        stats[:errors] += 1
      end
    end
  end

  # Summary
  info "\n" + ('=' * 80)
  info '📊 SYNC SUMMARY'
  info '=' * 80
  info "Total defects processed: #{stats[:total]}"
  info "  ✅ Updated: #{stats[:updated]}"
  info "  ⏭️  No changes: #{stats[:no_change]}"
  info "  ⚠️  Not found in DB: #{stats[:not_found]}"
  info "  ❌ Errors: #{stats[:errors]}"
  info "  🏷️  Labels processed: #{stats[:labels_attached]}"
  info '=' * 80

  info "\n✅ Sync completed successfully!"
rescue StandardError => e
  warn "\n❌ Fatal error: #{e.class}: #{e.message}"
  warn e.backtrace.first(5).join("\n")
  exit 1
end
