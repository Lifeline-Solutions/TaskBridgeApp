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

# SC Juza Configuration
PROJECT_KEY = 'SJP'
PRODUCT_ID = 'c7961971-c399-4f00-a2f7-df2d8a3f96e4'
MODULE_FIELD_ID = 'customfield_10136' # "Module - SC Juza"
FALLBACK_QA_MODULE_ID = CONFIG[:fallback_qa_module_id]
FALLBACK_SUBMODULE_ID = CONFIG[:fallback_submodule_id]
CREATE_MISSING_MODULES = true

options = {
  dry_run: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_sc_juza.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data.to_s.strip if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    return field_data['value'].to_s.strip if field_data['value'].present?
    return field_data['name'].to_s.strip if field_data['name'].present?
    return field_data['key'].to_s.strip if field_data['key'].present?
    return field_data['id'].to_s.strip if field_data['id'].present?
  end

  field_data.to_s.strip
end

def parse_module_and_submodule(full_string)
  return [nil, nil] if full_string.blank?

  # For SC Juza (SJP) we treat the entire custom field value as the module name
  # and intentionally do NOT split on '-' to extract a submodule. This ensures
  # the full name is preserved as the module and submodule is left blank.
  module_name = full_string.to_s.strip
  submodule_name = nil

  [module_name.presence, submodule_name]
end

def find_or_create_modules(module_name:, submodule_name:, product_id:, created_by:)
  parent = nil
  child = nil

  # Step 1: Find or create parent module
  if module_name.present?
    parent = QaModule.where('lower(name) = ? AND parent_id IS NULL AND product_id = ?', module_name.downcase, product_id).first
    if parent.nil? && CREATE_MISSING_MODULES
      parent = QaModule.create!(name: module_name, product_id: product_id)
      # parent.update_columns(created_by: created_by, modified_by: created_by) if parent.respond_to?(:created_by)
    end
  end

  # Step 2: Find or create child module
  if submodule_name.present? && parent
    child = QaModule.where('lower(name) = ? AND parent_id = ? AND product_id = ?', submodule_name.downcase, parent.id, product_id).first
    if child.nil? && CREATE_MISSING_MODULES
      child = QaModule.create!(name: submodule_name, parent_id: parent.id, product_id: product_id)
      # child.update_columns(created_by: created_by, modified_by: created_by) if child.respond_to?(:created_by)
    end
  end

  [parent, child]
end

# Main Execution
log "Starting SC Juza (SJP) submodule fix script (Dry Run: #{options[:dry_run]})"

# Get all SJP defects
defects = Defect.where('defect_unique LIKE ?', "#{PROJECT_KEY}-%")
log "Found #{defects.count} defects to check."

stats = { updated: 0, skipped: 0, errors: 0 }

defects.find_each do |defect|
  begin
    # Fetch from Jira
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

    raw_val = fields[MODULE_FIELD_ID]
    full_string = extract_custom_field_value(raw_val)

    if full_string.blank?
      # log "  #{defect.defect_unique}: No module data found (Field #{MODULE_FIELD_ID} empty). Skipping."
      stats[:skipped] += 1
      next
    end

    module_name, submodule_name = parse_module_and_submodule(full_string)

    current_module = defect.qa_module&.name
    current_submodule = defect.submodule&.name

    if current_module == module_name && current_submodule == submodule_name
      # log "  #{defect.defect_unique}: No change needed"
      stats[:skipped] += 1
      next
    end

    log "  #{defect.defect_unique}: Updating..."
    log "    Source: '#{full_string}'"
    log "    Old: Module='#{current_module}', Sub='#{current_submodule}'"
    log "    New: Module='#{module_name}', Sub='#{submodule_name}'"

    unless options[:dry_run]
      parent, child = find_or_create_modules(
        module_name: module_name,
        submodule_name: submodule_name,
        product_id: PRODUCT_ID,
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
    log e.backtrace.join("\n")
    stats[:errors] += 1
  end
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
