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

# Discover custom fields for modules, submodules, and banking types based on project
def discover_custom_fields(project_key)
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

  # Project-specific field mapping with exact patterns
  project_patterns = {
    'RMF' => {
      module_pattern: /^Rafiki\s+Modules?$/i,
      submodule_pattern: %r{^Rafiki\s+Modules?\s*/\s*Sub\s*Modules?$}i
    },
    'RMP' => {
      module_pattern: /^Imarisha\s+Mobile\s+Banking\s+Modules?$/i,
      submodule_pattern: %r{^Imarisha\s+Mobile\s+Banking\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'KCBL' => {
      module_pattern: /^KCBL\s+Modules?$/i,
      submodule_pattern: %r{^KCBL\s+Modules?\s*/\s*Submodules?$}i
    },
    'NCBA' => {
      module_pattern: /^NCBA\s+Modules?$/i,
      submodule_pattern: %r{^NCBA\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'ISP' => {
      module_pattern: /^Imarisha\s+Internet\s+Banking\s+Modules?$/i,
      submodule_pattern: %r{^Imarisha\s+Internet\s+Banking\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'IAB' => {
      module_pattern: /^Imarisha\s+Agency\s+Banking\s+Modules?$/i,
      submodule_pattern: %r{^Imarisha\s+Agency\s+Banking\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'IEP' => {
      module_pattern: /^Imarisha\s+ERP\s+Modules?$/i,
      submodule_pattern: %r{^Imarisha\s+ERP\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'KPS' => {
      module_pattern: /^Kenya\s+Police\s+Modules?$/i,
      submodule_pattern: %r{^Kenya\s+Police\s+Modules?\s*/\s*Sub-Modules?$}i
    },
    'AUD' => {
      module_pattern: /^Imarisha\s+Audit\s+Modules?$/i,
      submodule_pattern: %r{^Imarisha\s+Audit\s+Modules?\s*/\s*Sub-Modules?$}i
    }
  }

  # Get patterns for this project
  # Special handling: treat any RMP-like project keys as Rafiki projects
  patterns = if project_key.to_s.upcase.start_with?('RMP')
               {
                 module_pattern: /^Rafiki\s+Modules?$/i,
                 submodule_pattern: %r{^Rafiki\s+Modules?\s*/\s*Sub\s*Modules?$}i
               }
             else
               project_patterns[project_key] || {}
             end

  # Collect all matching fields for debugging
  all_module_fields = []
  all_submodule_fields = []

  fields.each do |field|
    name = field['name'] || ''
    name_lower = name.downcase
    field_id = field['id']

    # Check for banking type field (common across projects)
    if name_lower.include?('banking') && name_lower.include?('type')
      banking_type_field = field_id
      vputs "Found Banking Type field: #{field_id} - #{field['name']}"
      next
    end

    # Project-specific module/submodule detection (exact match)
    if patterns[:module_pattern] && name =~ patterns[:module_pattern]
      module_field = field_id
      info "✓ Matched Module field for #{project_key}: #{field_id} - #{field['name']}"
    elsif patterns[:submodule_pattern] && name =~ patterns[:submodule_pattern]
      submodule_field = field_id
      info "✓ Matched Submodule field for #{project_key}: #{field_id} - #{field['name']}"
    # Collect all module/submodule fields for fallback
    elsif name_lower.include?('module')
      if name_lower.include?('sub') || name_lower.include?('/')
        all_submodule_fields << { id: field_id, name: field['name'] }
        vputs "  Found submodule candidate: #{field_id} - #{field['name']}"
      else
        all_module_fields << { id: field_id, name: field['name'] }
        vputs "  Found module candidate: #{field_id} - #{field['name']}"
      end
    end
  end

  # Fallback: if no specific match found, use generic detection
  if module_field.nil? && patterns.empty? && all_module_fields.any?
    module_field = all_module_fields.first[:id]
    vputs "Using fallback module field: #{module_field} - #{all_module_fields.first[:name]}"
  end

  if submodule_field.nil? && patterns.empty? && all_submodule_fields.any?
    submodule_field = all_submodule_fields.first[:id]
    vputs "Using fallback submodule field: #{submodule_field} - #{all_submodule_fields.first[:name]}"
  end

  # Validation message
  if module_field || submodule_field
    info "Project #{project_key} - Module: #{module_field || 'Not found'}, Submodule: #{submodule_field || 'Not found'}"
  else
    warn "⚠️  No module/submodule fields found for project #{project_key}"
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

# Extract module and submodule from cascading select field
def extract_cascading_field(field_data)
  return [nil, nil] if field_data.nil?

  parent_value = nil
  child_value = nil

  if field_data.is_a?(Hash)
    # Extract parent (module)
    parent_value = field_data['value'].to_s.strip if field_data['value'].present?
    parent_value ||= field_data['name'].to_s.strip if field_data['name'].present?

    # Extract child (submodule) from cascading select
    if field_data['child'].is_a?(Hash)
      child_value = field_data['child']['value'].to_s.strip if field_data['child']['value'].present?
      child_value ||= field_data['child']['name'].to_s.strip if field_data['child']['name'].present?
    end
  end

  [parent_value.presence, child_value.presence]
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
    elsif parent
      vputs "[MODULE-MATCH] Found parent module '#{module_name}' -> #{parent.id}"
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
      elsif child
        vputs "[SUBMODULE-MATCH] Found submodule '#{submodule_name}' -> #{child.id}"
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

  # Debug: Show what fields we're looking for
  vputs "\n[DEBUG] Custom fields to fetch:"
  vputs "  Module field: #{custom_fields[:module_field]}"
  vputs "  Submodule field: #{custom_fields[:submodule_field]}"
  vputs "  Banking type field: #{custom_fields[:banking_type_field]}"

  # Debug: Show raw field values from Jira
  if custom_fields[:module_field]
    raw_module = fields[custom_fields[:module_field]]
    vputs "[DEBUG] Raw module field value: #{raw_module.inspect}"
  end

  if custom_fields[:submodule_field]
    raw_submodule = fields[custom_fields[:submodule_field]]
    vputs "[DEBUG] Raw submodule field value: #{raw_submodule.inspect}"
  end

  if custom_fields[:banking_type_field]
    raw_banking = fields[custom_fields[:banking_type_field]]
    vputs "[DEBUG] Raw banking type field value: #{raw_banking.inspect}"
  end

  # Extract metadata from Jira
  module_name = nil
  submodule_name = nil

  # Try to extract from module field (could be cascading select)
  if custom_fields[:module_field]
    module_field_data = fields[custom_fields[:module_field]]
    parent_mod, child_mod = extract_cascading_field(module_field_data)

    if parent_mod.present?
      module_name = parent_mod
      # If cascading field has a child, use it as submodule
      submodule_name = child_mod if child_mod.present?
      vputs "[CASCADING] Extracted from module field - Parent: '#{parent_mod}', Child: '#{child_mod}'"
    end
  end

  # Try to extract from separate submodule field (could also be cascading select)
  if custom_fields[:submodule_field]
    submodule_field_data = fields[custom_fields[:submodule_field]]
    parent_sub, child_sub = extract_cascading_field(submodule_field_data)

    if parent_sub.present?
      # If we don't have a module yet, use the parent from submodule field
      module_name ||= parent_sub
      # If cascading field has a child, use it as submodule
      submodule_name = child_sub if child_sub.present?
      # If no child but parent exists and module is already set, use parent as submodule
      submodule_name ||= parent_sub if module_name.present? && module_name != parent_sub
      vputs "[CASCADING] Extracted from submodule field - Parent: '#{parent_sub}', Child: '#{child_sub}'"
    end
  end

  banking_type_name = extract_custom_field_value(fields[custom_fields[:banking_type_field]] || '') if custom_fields[:banking_type_field]
  labels_array = (fields['labels'] || []).compact.map(&:to_s).map(&:strip).reject(&:empty?)

  # Debug: Show extracted values
  vputs '[DEBUG] Extracted values:'
  vputs "  Module: '#{module_name}'"
  vputs "  Submodule: '#{submodule_name}'"
  vputs "  Banking type: '#{banking_type_name}'"
  vputs "  Labels: #{labels_array.inspect}"

  # Parse module/submodule
  if module_name.present? && submodule_name.to_s.strip.empty?
    original_module = module_name.dup
    module_name, submodule_name = parse_module_and_submodule(module_name, submodule_name)
    vputs "[MODULE-PARSE] Derived module/submodule from '#{original_module}' => module='#{module_name}', submodule='#{submodule_name}'" if submodule_name.present?
  end

  created_by_uid = DEFAULT_CREATED_BY || DEFAULT_USER_UUID

  updated = false

  # Update modules - always update if present in Jira
  if module_name.present?
    parent_module, child_module = find_or_create_modules(
      module_name: module_name,
      submodule_name: submodule_name,
      product_id: product_id,
      created_by: created_by_uid
    )

    if parent_module
      if defect.qa_module_id == parent_module.id
        vputs "[KEEP] Module already set to '#{parent_module.name}' for #{issue_key}"
      else
        defect.qa_module_id = parent_module.id
        updated = true
        info "[UPDATE] Updated module for #{issue_key}: #{parent_module.name}"
      end
    end

    if child_module
      if defect.submodule_id == child_module.id
        vputs "[KEEP] Submodule already set to '#{child_module.name}' for #{issue_key}"
      else
        defect.submodule_id = child_module.id
        updated = true
        info "[UPDATE] Updated submodule for #{issue_key}: #{child_module.name}"
      end
    end
  elsif submodule_name.present?
    # Handle case where only submodule is provided
    _, child_module = find_or_create_modules(
      module_name: module_name,
      submodule_name: submodule_name,
      product_id: product_id,
      created_by: created_by_uid
    )

    if child_module
      if defect.submodule_id == child_module.id
        vputs "[KEEP] Submodule already set to '#{child_module.name}' for #{issue_key}"
      else
        defect.submodule_id = child_module.id
        updated = true
        info "[UPDATE] Updated submodule for #{issue_key}: #{child_module.name}"
      end
    end
  end

  # Update banking type - always update if present in Jira
  if banking_type_name.present?
    banking = find_or_create_banking_type(banking_type_name, product_id: product_id, created_by: created_by_uid)
    if banking
      if defect.banking_type_id == banking.id
        vputs "[KEEP] Banking type already set to '#{banking.name}' for #{issue_key}"
      else
        defect.banking_type_id = banking.id
        updated = true
        info "[UPDATE] Updated banking type for #{issue_key}: #{banking.name}"
      end
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
  labels_added = 0
  if labels_array.any?
    initial_label_count = defect.labels.count
    attach_labels_to_defect(defect, labels_array, created_by: created_by_uid)
    labels_added = defect.labels.count - initial_label_count
  end

  {
    updated: updated,
    labels_count: labels_array.length,
    labels_added: labels_added,
    module: module_name,
    submodule: submodule_name,
    banking_type: banking_type_name
  }
end

# ===============================
# MAIN EXECUTION
# ===============================

begin
  # Discover custom fields based on project
  custom_fields_array = discover_custom_fields(options[:project])
  custom_fields = {
    module_field: custom_fields_array[0],
    submodule_field: custom_fields_array[1],
    banking_type_field: custom_fields_array[2]
  }

  info "\nUsing custom fields:"
  info "  Module: #{custom_fields[:module_field] || 'Not found'}"
  info "  Submodule: #{custom_fields[:submodule_field] || 'Not found'}"
  info "  Banking Type: #{custom_fields[:banking_type_field] || 'Not found'}"
  info ''

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
    labels_attached: 0,
    labels_added: 0,
    modules_updated: 0,
    submodules_updated: 0,
    banking_types_updated: 0
  }

  # Detailed report for each defect
  detailed_report = []

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
    stats[:labels_added] += result[:labels_added]
    stats[:modules_updated] += 1 if result[:module].present?
    stats[:submodules_updated] += 1 if result[:submodule].present?
    stats[:banking_types_updated] += 1 if result[:banking_type].present?

    # Add to detailed report
    detailed_report << {
      defect_unique: options[:defect_unique],
      status: result[:updated] ? 'Updated' : 'No Change',
      module: result[:module] || 'N/A',
      submodule: result[:submodule] || 'N/A',
      banking_type: result[:banking_type] || 'N/A',
      labels: result[:labels_count],
      labels_added: result[:labels_added]
    }
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
        stats[:labels_added] += result[:labels_added]
        stats[:modules_updated] += 1 if result[:module].present?
        stats[:submodules_updated] += 1 if result[:submodule].present?
        stats[:banking_types_updated] += 1 if result[:banking_type].present?

        # Add to detailed report
        detailed_report << {
          defect_unique: issue_key,
          status: result[:updated] ? 'Updated' : 'No Change',
          module: result[:module] || 'N/A',
          submodule: result[:submodule] || 'N/A',
          banking_type: result[:banking_type] || 'N/A',
          labels: result[:labels_count],
          labels_added: result[:labels_added]
        }
      rescue StandardError => e
        warn "[ERROR] Failed to sync #{issue_key}: #{e.class}: #{e.message}"
        stats[:errors] += 1
        detailed_report << {
          defect_unique: issue_key,
          status: 'Error',
          module: 'N/A',
          submodule: 'N/A',
          banking_type: 'N/A',
          labels: 0,
          labels_added: 0,
          error: "#{e.class}: #{e.message}"
        }
      end
    end
  end

  # Summary Statistics
  info "\n#{'=' * 80}"
  info '📊 SYNC SUMMARY'
  info '=' * 80
  info "Total defects processed: #{stats[:total]}"
  info "  ✅ Updated: #{stats[:updated]}"
  info "  ⏭️  No changes: #{stats[:no_change]}"
  info "  ⚠️  Not found in DB: #{stats[:not_found]}"
  info "  ❌ Errors: #{stats[:errors]}"
  info ''
  info 'Metadata Statistics:'
  info "  📦 Modules synced: #{stats[:modules_updated]}"
  info "  📂 Submodules synced: #{stats[:submodules_updated]}"
  info "  🏦 Banking types synced: #{stats[:banking_types_updated]}"
  info "  🏷️  Total labels in Jira: #{stats[:labels_attached]}"
  info "  ➕ New labels added: #{stats[:labels_added]}"
  info '=' * 80

  # Detailed Report
  if detailed_report.any?
    info "\n#{'=' * 80}"
    info '📋 DETAILED REPORT'
    info '=' * 80

    # Group by status
    updated_items = detailed_report.select { |r| r[:status] == 'Updated' }
    no_change_items = detailed_report.select { |r| r[:status] == 'No Change' }
    error_items = detailed_report.select { |r| r[:status] == 'Error' }

    if updated_items.any?
      info "\n✅ UPDATED DEFECTS (#{updated_items.length}):"
      info '-' * 80
      updated_items.each do |report|
        info report[:defect_unique].to_s
        info "  Module: #{report[:module]}"
        info "  Submodule: #{report[:submodule]}"
        info "  Banking Type: #{report[:banking_type]}"
        info "  Labels: #{report[:labels]} (#{report[:labels_added]} new)"
        info ''
      end
    end

    if no_change_items.any? && options[:verbose]
      info "\n⏭️  NO CHANGES (#{no_change_items.length}):"
      info '-' * 80
      no_change_items.each do |report|
        vputs "#{report[:defect_unique]} - Module: #{report[:module]}, Submodule: #{report[:submodule]}, Banking: #{report[:banking_type]}, Labels: #{report[:labels]}"
      end
      info ''
    end

    if error_items.any?
      info "\n❌ ERRORS (#{error_items.length}):"
      info '-' * 80
      error_items.each do |report|
        info "#{report[:defect_unique]}: #{report[:error]}"
      end
      info ''
    end

    info '=' * 80
  end

  info "\n✅ Sync completed successfully!"
  info "Report generated at: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
rescue StandardError => e
  warn "\n❌ Fatal error: #{e.class}: #{e.message}"
  warn e.backtrace.first(5).join("\n")
  exit 1
end
