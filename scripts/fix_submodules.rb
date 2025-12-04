#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'optparse'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

DEFAULT_PRODUCT_UUID = CONFIG[:default_product_id]
CREATE_MISSING_MODULES = CONFIG.fetch(:create_missing_modules, true)
FALLBACK_QA_MODULE_ID = CONFIG[:fallback_qa_module_id]
FALLBACK_SUBMODULE_ID = CONFIG[:fallback_submodule_id]

options = {
  dry_run: false,
  project: 'ISP'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_submodules.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--project KEY', 'Project key (default ISP)') { |v| options[:project] = v }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def discover_custom_fields
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)
  return nil unless response.is_a?(Net::HTTPSuccess)

  fields = JSON.parse(response.body)
  module_field = nil
  submodule_field = nil

  fields.each do |field|
    name = field['name']&.downcase || ''
    field_id = field['id']

    if name == 'imarisha  erp modules'
      module_field = field_id
    elsif name == 'imarisha  erp modules / sub-modules'
      submodule_field = field_id
    end
  end

  [module_field, submodule_field]
end

def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data.to_s.strip if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    # Special handling for Cascading Select fields (parent/child)
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

def parse_module_and_submodule(module_name_str, submodule_name_str)
  mod = module_name_str.to_s.strip
  sub = submodule_name_str.to_s.strip

  return [mod, sub] if sub.present?
  return [mod, sub] if mod.blank?

  parts = mod.split(/\s*[-\u2013\u2014]\s*/, 2)
  return [parts[0].strip, parts[1].strip] if parts.length == 2

  [mod, sub]
end

def find_or_create_modules(module_name:, submodule_name:, product_id:, created_by:)
  parent = nil
  child = nil

  # Step 1: Find or create parent module
  if module_name.present?
    parent = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', module_name.strip.downcase, product_id).first
    if parent.nil? && CREATE_MISSING_MODULES
      parent = QaModule.create!(name: module_name.strip, product_id: product_id)
      parent.update_columns(created_by: created_by, modified_by: created_by) if parent.respond_to?(:created_by)
    end
  end

  # Step 2: Find or create child module
  if submodule_name.present?
    if parent
      child = QaModule.where('lower(name) = ? AND parent_id = ? AND product_id = ?', submodule_name.strip.downcase, parent.id, product_id).first
      if child.nil? && CREATE_MISSING_MODULES
        child = QaModule.create!(name: submodule_name.strip, parent_id: parent.id, product_id: product_id)
        child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
      end
    else
      # Try to find existing submodule with a parent
      child = QaModule.where('lower(name) = ? AND parent_id IS NOT NULL AND product_id = ?', submodule_name.strip.downcase, product_id).first
      if child && child.parent_id.present?
        parent = QaModule.find_by(id: child.parent_id)
      else
        child = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', submodule_name.strip.downcase, product_id).first
        if child.nil? && CREATE_MISSING_MODULES
          child = QaModule.create!(name: submodule_name.strip, product_id: product_id)
          child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
        end
      end
    end
  end

  [parent, child]
end

# Main Execution
log "Starting submodule fix script for project #{options[:project]} (Dry Run: #{options[:dry_run]})"

module_field, submodule_field = discover_custom_fields
log "Discovered fields - Module: #{module_field}, Submodule: #{submodule_field}"

unless module_field && submodule_field
  log 'ERROR: Could not find required custom fields. Exiting.'
  exit 1
end

# Get all defects for the project
defects = Defect.where('defect_unique LIKE ?', "#{options[:project]}-%")
log "Found #{defects.count} defects to check."

stats = { updated: 0, skipped: 0, errors: 0 }

defects.find_each do |defect|
  # Fetch current data from Jira
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{defect.defect_unique}"
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)
  unless response.is_a?(Net::HTTPSuccess)
    log "Failed to fetch #{defect.defect_unique}: #{response.code}"
    stats[:errors] += 1
    next
  end

  issue = JSON.parse(response.body)
  fields = issue['fields'] || {}

  raw_module = fields[module_field]
  raw_submodule = fields[submodule_field]

  module_name = extract_custom_field_value(raw_module)
  submodule_name = extract_custom_field_value(raw_submodule)

  # Apply parsing logic
  module_name, submodule_name = parse_module_and_submodule(module_name, submodule_name) if module_name.present? && submodule_name.to_s.strip.empty?

  # Check if update is needed
  current_module = defect.qa_module&.name
  current_submodule = defect.submodule&.name

  if current_module == module_name && current_submodule == submodule_name
    # log "  #{defect.defect_unique}: No change needed"
    stats[:skipped] += 1
    next
  end

  log "  #{defect.defect_unique}: Updating..."
  log "    Old: Module='#{current_module}', Sub='#{current_submodule}'"
  log "    New: Module='#{module_name}', Sub='#{submodule_name}'"

  unless options[:dry_run]
    parent, child = find_or_create_modules(
      module_name: module_name,
      submodule_name: submodule_name,
      product_id: defect.product_id || DEFAULT_PRODUCT_UUID,
      created_by: defect.created_by || 1
    )

    defect.qa_module_id = parent&.id || FALLBACK_QA_MODULE_ID
    defect.submodule_id = child&.id || FALLBACK_SUBMODULE_ID
    defect.save!
    log '    ✅ Updated successfully'
  end

  stats[:updated] += 1
rescue StandardError => e
  log "ERROR processing #{defect.defect_unique}: #{e.message}"
  stats[:errors] += 1
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
