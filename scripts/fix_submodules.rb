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
  project: nil,
  defect_unique: nil,
  all: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_submodules.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--project KEY', 'Project key (e.g., KCBL, RMP, PSP, SMC)') { |v| options[:project] = v }
  opts.on('--defect UNIQUE', 'Process a single defect by its unique ID (e.g., PSP-1, SMC-5)') { |v| options[:defect_unique] = v }
  opts.on('--all', 'Process all defects across all projects') { options[:all] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def discover_custom_fields(project_key = 'RMP')
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

  # Define field patterns per project
  patterns = case project_key.upcase
             when 'RMP'
               {
                 module: /^rafiki\s+modules?$/i,
                 submodule: /^rafiki\s+modules?\s*\/\s*sub\s*modules?$/i
               }
             when 'KCBL'
               {
                 module: /^kcbl\s+modules?$/i,
                 submodule: /^kcbl\s+modules?\s*\/\s*submodules?$/i
               }
             when 'PSP'
               {
                 module: /^kenya\s+police\s+modules?$/i,
                 submodule: /^kenya\s+police\s+modules?\s*\/\s*sub\s*modules?$/i
               }
             when 'SMC'
               {
                 module: /^components?\s*-\s*sofia\s+credit$/i,
                 submodule: /^sofia\s+modules?\s*[_-]\s*submodules?$/i
               }
             when 'SJP'
               {
                 module: /^modules?\s+sc\s+juza$/i,
                 submodule: /^(ignore|empty)$/i
               }
             when 'KUP'
               {
                 module: /^components?\s*\(\s*k[\s-]?unity\s*\)$/i,
                 submodule: /^(ignore|empty)$/i
               }
             when 'GBCBS'
               {
                 module: /^module$/i,
                 submodule: /^(ignore|empty)$/i
               }
             when 'GBCBU2'
               {
                 module: /^components?$/i,
                 submodule: /^(ignore|empty)$/i
               }
             else
               {
                 module: /modules/i,
                 submodule: /sub.*module/i
               }
             end

  fields.each do |field|
    name = field['name']&.downcase || ''
    field_id = field['id']
    
    # Debug log for project fields
    log "Found field: #{name} (#{field_id})" if name.include?('kcbl') || name.include?('kenya police') || name.include?('sofia') || name.include?('components') || name.include?('modules sc juza') || name.include?('k-unity') || name.include?('k unity')

    case project_key.upcase
    when 'KCBL'
      if name == 'kcbl modules'
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      elsif name.include?('kcbl modules') && (name.include?('submodules') || name.include?('sub-modules') || name.include?('sub modules'))
        submodule_field = field_id
        log "✓ Matched Submodule field: #{field['name']} (#{field_id})"
      end
    when 'PSP'
      if name == 'kenya police modules'
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      elsif name.include?('kenya police modules') && (name.include?('submodules') || name.include?('sub-modules') || name.include?('sub modules'))
        submodule_field = field_id
        log "✓ Matched Submodule field: #{field['name']} (#{field_id})"
      end
    when 'RMP'
      if name == 'rafiki modules'
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      elsif name.include?('rafiki modules') && (name.include?('submodules') || name.include?('sub-modules') || name.include?('sub modules'))
        submodule_field = field_id
        log "✓ Matched Submodule field: #{field['name']} (#{field_id})"
      end
    when 'SMC'
      if name.include?('components') && name.include?('sofia credit')
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      elsif name.include?('sofia') && name.include?('modules') && name.include?('submodules')
        submodule_field = field_id
        log "✓ Matched Submodule field: #{field['name']} (#{field_id})"
      end
    when 'SJP'
      if name.include?('modules') && name.include?('sc juza')
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      end
      # For SJP, we'll set a dummy submodule field to pass validation
      # The actual submodule value will be ignored in processing
      submodule_field ||= 'DUMMY'
    when 'KUP'
      if name.include?('components') && (name.include?('k-unity') || name.include?('kunity') || name.include?('k unity'))
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      end
      # For KUP, we'll set a dummy submodule field to pass validation
      submodule_field ||= 'DUMMY'
    when 'GBCBS'
      if name == 'module' || (name.include?('module') && !name.include?('submodule'))
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      end
      # For GBCBS, we'll set a dummy submodule field to pass validation
      submodule_field ||= 'DUMMY'
    when 'GBCBU2'
      if name == 'components' || (name == 'component')
        module_field = field_id
        log "✓ Matched Module field: #{field['name']} (#{field_id})"
      end
      # For GBCBU2, we'll set a dummy submodule field to pass validation
      submodule_field ||= 'DUMMY'
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
log "Starting submodule fix script (Dry Run: #{options[:dry_run]})"

# Validate options
if options[:all]
  log "Processing ALL defects across all projects"
elsif options[:project]
  log "Processing project: #{options[:project]}"
  if options[:defect_unique]
    log "  Filtering to single defect: #{options[:defect_unique]}"
  end
else
  log "ERROR: Must specify --project, --defect, or --all"
  exit 1
end

module_field = nil
submodule_field = nil

# Determine which projects to process
projects_to_process = if options[:all]
                        # Get all unique project keys from defects
                        Defect.where.not(defect_unique: nil)
                          .select('DISTINCT SUBSTRING(defect_unique FROM 1 FOR POSITION(\'-\' IN defect_unique) - 1) as project_key')
                          .map(&:project_key)
                          .compact
                          .uniq
                      elsif options[:project]
                        [options[:project]]
                      else
                        []
                      end

log "Projects to process: #{projects_to_process.join(', ')}"

projects_to_process.each do |project_key|
  log "\n" + "=" * 80
  log "Processing project: #{project_key}"
  log "=" * 80

  module_field, submodule_field = discover_custom_fields(project_key)
  log "Discovered fields - Module: #{module_field}, Submodule: #{submodule_field}"

  unless module_field && submodule_field
    log 'WARNING: Could not find required custom fields for this project. Skipping.'
    next
  end

  # Get defects for this project
  if options[:defect_unique]
    # Single defect lookup
    defects = Defect.where(defect_unique: options[:defect_unique])
    unless defects.exists?
      log "ERROR: Defect #{options[:defect_unique]} not found"
      next
    end
  else
    # All defects for the project
    defects = Defect.where('defect_unique LIKE ?', "#{project_key}-%")
  end

  log "Found #{defects.count} defect(s) to check."

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

      raw_module = fields[module_field]
      # Only fetch submodule from JIRA if it's a real field (not 'DUMMY')
      raw_submodule = (submodule_field && submodule_field != 'DUMMY') ? fields[submodule_field] : nil

      module_name = extract_custom_field_value(raw_module)
      submodule_name = extract_custom_field_value(raw_submodule)

      # For projects with no submodules, clear submodule_name
      case project_key.upcase
      when 'SJP'
        module_name = 'Modules SC Juza'
        submodule_name = '' # Always blank for SJP
      when 'KUP'
        module_name = 'Components (K-Unity)'
        submodule_name = '' # Always blank for KUP
      when 'GBCBS'
        module_name = 'Module'
        submodule_name = '' # Always blank for GBCBS
      when 'GBCBU2'
        module_name = 'Components'
        submodule_name = '' # Always blank for GBCBU2
      else
        # For other projects, apply parsing logic
        if module_name.blank? && submodule_name.blank?
          stats[:skipped] += 1
          next
        end

        # Apply parsing logic
        if module_name.present? && submodule_name.to_s.strip.empty?
          module_name, submodule_name = parse_module_and_submodule(module_name, submodule_name)
        elsif module_name.present? && submodule_name.present?
          # If submodule contains parent name, strip it
          prefix_pattern = /^#{Regexp.escape(module_name)}\s*[-\u2013\u2014]\s*/i
          if submodule_name.match?(prefix_pattern)
            new_sub = submodule_name.sub(prefix_pattern, '')
            submodule_name = new_sub
          end
        end
      end

      # Check if update is needed
      current_module = defect.qa_module&.name
      current_submodule = defect.submodule&.name

      if current_module == module_name && current_submodule == submodule_name
        stats[:skipped] += 1
        next
      end

      log "  #{defect.defect_unique}: Updating..."
      log "    Old: Module='#{current_module}', Sub='#{current_submodule}'"
      log "    New: Module='#{module_name}', Sub='#{submodule_name}'"

      # Determine Product ID based on project
      product_id = defect.product_id
      case project_key.upcase
      when 'KCBL'
        product_id ||= 'c1469eb7-97d1-4611-9e67-3fce1d0bb1ac'
      when 'PSP'
        unless product_id
          psp_product = Product.where('document_name ILIKE ?', '%Kenya Police%').first ||
                        Product.where('jira_key ILIKE ?', '%PSP%').first
          product_id = psp_product&.id
        end
      when 'SMC'
        unless product_id
          smc_product = Product.where('document_name ILIKE ?', '%Sofia%').first ||
                        Product.where('jira_key ILIKE ?', '%SMC%').first
          product_id = smc_product&.id
        end
      when 'SJP'
        unless product_id
          sjp_product = Product.where('jira_key ILIKE ?', '%SJP%').first
          product_id = sjp_product&.id
        end
      when 'KUP'
        unless product_id
          kup_product = Product.where('jira_key ILIKE ?', '%KUP%').first
          product_id = kup_product&.id
        end
      when 'GBCBS'
        unless product_id
          gbcbs_product = Product.where('jira_key ILIKE ?', '%GBCBS%').first
          product_id = gbcbs_product&.id
        end
      when 'GBCBU2'
        unless product_id
          gbcbu2_product = Product.where('jira_key ILIKE ?', '%GBCBU2%').first
          product_id = gbcbu2_product&.id
        end
      end
      product_id ||= DEFAULT_PRODUCT_UUID

      unless options[:dry_run]
        parent, child = find_or_create_modules(
          module_name: module_name,
          submodule_name: submodule_name,
          product_id: product_id,
          created_by: defect.created_by || 1
        )

        defect.qa_module_id = parent&.id || FALLBACK_QA_MODULE_ID
        defect.submodule_id = child&.id || FALLBACK_SUBMODULE_ID

        # Project-specific banking type assignments
        case project_key.upcase
        when 'KCBL'
          # Core Banking ID for KCBL product
          defect.banking_type_id = '7fc78d1b-c21f-4077-a2b4-e8cad57ca71c'
        when 'SMC'
          # Sofia Credit specific banking type (if configured)
          # defect.banking_type_id = 'SMC_BANKING_TYPE_UUID' # Update with actual UUID if needed
        end

        defect.save!
        log '    ✅ Updated successfully'
      end

      stats[:updated] += 1
    rescue StandardError => e
      log "ERROR processing #{defect.defect_unique}: #{e.message}"
      stats[:errors] += 1
    end
  end

  log "\nProject #{project_key} Results:"
  log "  Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
end

log "\n" + "=" * 80
log "Script completed!"
log "=" * 80
