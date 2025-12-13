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

# KUnity Product ID from previous analysis
KUNITY_PRODUCT_ID = '4dd0b55f-e02f-4973-93e1-f3ef040b7167' 
CREATE_MISSING_MODULES = CONFIG.fetch(:create_missing_modules, true)
FALLBACK_QA_MODULE_ID = CONFIG[:fallback_qa_module_id]
FALLBACK_SUBMODULE_ID = CONFIG[:fallback_submodule_id]

options = {
  dry_run: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_kunity_modules.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
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
log "Starting KUnity module migration (Dry Run: #{options[:dry_run]})"

# Get all KUnity defects
defects = Defect.where('defect_unique LIKE ?', "KUP-%")
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
    
    # Check 'Components (K-Unity)' custom field
    # ID: customfield_10152
    field_data = fields['customfield_10152']
    
    component_name = nil
    if field_data.is_a?(Hash)
      component_name = field_data['value'].to_s.strip
    elsif field_data.is_a?(String)
      component_name = field_data.strip
    end
    
    if component_name.blank?
      # log "  #{defect.defect_unique}: No KUnity component found. Skipping."
      stats[:skipped] += 1
      next
    end

    # Parse Module - Submodule
    # Expected format: "Admin Portal-Customer Management"
    parts = component_name.split('-', 2)
    
    if parts.length == 2
      module_name = parts[0].strip
      submodule_name = parts[1].strip
    else
      # Fallback if no dash: treat as Module, no submodule
      module_name = parts[0].strip
      submodule_name = nil
    end

    # Check if update is needed
    current_module = defect.qa_module&.name
    current_submodule = defect.submodule&.name

    if current_module == module_name && current_submodule == submodule_name
      # log "  #{defect.defect_unique}: No change needed"
      stats[:skipped] += 1
      next
    end

    log "  #{defect.defect_unique}: Updating..."
    log "    Source Component: '#{component_name}'"
    log "    Old: Module='#{current_module}', Sub='#{current_submodule}'"
    log "    New: Module='#{module_name}', Sub='#{submodule_name}'"

    unless options[:dry_run]
      parent, child = find_or_create_modules(
        module_name: module_name,
        submodule_name: submodule_name,
        product_id: KUNITY_PRODUCT_ID,
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
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
