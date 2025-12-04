#!/usr/bin/env ruby
# scripts/assign_modules_and_submodules.rb
# Fetch modules and submodules from Jira API and assign to defects
# Ensures full module and submodule names are captured from Jira
#
# Usage:
#   # Process single defect (fetches from Jira)
#   rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114
#
#   # Process all defects in project (fetches from Jira)
#   rails runner scripts/assign_modules_and_submodules.rb --project PSP
#
#   # Process all defects (fetches from Jira)
#   rails runner scripts/assign_modules_and_submodules.rb --all
#
#   # Dry run to preview changes
#   DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --all
#
#   # Verbose output
#   VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

require 'optparse'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'

options = {
  dry_run: ENV['DRY_RUN'].to_s.downcase == 'true',
  verbose: ENV['VERBOSE'].to_s.downcase == 'true',
  mode: :none,
  defect_key: nil,
  project_key: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/assign_modules_and_submodules.rb [OPTIONS]'

  opts.on('--defect KEY', 'Process single defect from Jira (e.g., PSP-114)') do |v|
    options[:mode] = :single_defect
    options[:defect_key] = v.upcase.strip
  end

  opts.on('--project KEY', 'Process all defects in project from Jira (e.g., PSP)') do |v|
    options[:mode] = :project
    options[:project_key] = v.upcase.strip
  end

  opts.on('--all', 'Process all defects in database (fetch from Jira)') do
    options[:mode] = :all
  end

  opts.on('--dry-run', "Preview changes without saving") do
    options[:dry_run] = true
  end

  opts.on('--verbose', 'Verbose output') do
    options[:verbose] = true
  end

  opts.on('--help', 'Show help message') do
    puts opts
    puts "\n" + "=" * 100
    puts "EXAMPLES"
    puts "=" * 100
    puts "\n1. Fetch and assign for single defect from Jira:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114"
    puts ""
    puts "2. Fetch and assign for entire project from Jira:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --project PSP"
    puts ""
    puts "3. Fetch and assign all defects from Jira:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --all"
    puts ""
    puts "4. Preview changes before applying:"
    puts "   DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP"
    puts ""
    puts "5. Verbose output with fetch details:"
    puts "   VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114"
    puts ""
    puts "6. Dry run + verbose:"
    puts "   DRY_RUN=true VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --project PSP"
    puts "\n" + "=" * 100
    exit 0
  end
end.parse!

if options[:mode] == :none
  puts "ERROR: Please specify --defect, --project, or --all"
  exit 1
end

DRY_RUN = options[:dry_run]
VERBOSE = options[:verbose]

def vputs(msg)
  puts msg if VERBOSE
end

# ===============================
# JIRA CONFIGURATION & DISCOVERY
# ===============================

# Load Jira configuration
config_path = Rails.root.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL') { CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net' }
JIRA_API_USER = ENV.fetch('JIRA_API_USER') { CONFIG[:jira_api_user] }
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_USER && JIRA_API_TOKEN
  puts "ERROR: JIRA_API_USER and JIRA_API_TOKEN must be set"
  exit 1
end

def discover_custom_fields
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)

  vputs 'Discovering custom fields from Jira...'

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

    # Specific check for Imarisha ERP Modules
    if name == 'imarisha  erp modules' # NOTE: double space in name
      module_field = field_id
      vputs "✓ Found TARGET Module field: #{field_id} - #{field['name']}"
    elsif name == 'imarisha  erp modules / sub-modules'
      submodule_field = field_id
      vputs "✓ Found TARGET Submodule field: #{field_id} - #{field['name']}"
    # Fallback to generic discovery if not already found
    elsif module_field.nil? && name.include?('module') && !name.include?('sub')
      module_field = field_id
      vputs "✓ Found Module field: #{field_id} - #{field['name']}"
    elsif submodule_field.nil? && (name.include?('submodule') || (name.include?('module') && name.include?('sub')))
      submodule_field = field_id
      vputs "✓ Found Submodule field: #{field_id} - #{field['name']}"
    elsif name.include?('banking') && name.include?('type')
      banking_type_field = field_id
      vputs "✓ Found Banking Type field: #{field_id} - #{field['name']}"
    end
  end

  [module_field, submodule_field, banking_type_field]
end

# Discover custom fields
vputs "Loading Jira configuration and discovering custom fields..."
MODULE_FIELD, SUBMODULE_FIELD, BANKING_TYPE_FIELD = discover_custom_fields

unless MODULE_FIELD && SUBMODULE_FIELD
  puts "❌ ERROR: Could not discover module/submodule fields from Jira"
  puts "   Please ensure Jira credentials are correct and fields exist"
  exit 1
end

vputs "Configuration loaded:"
vputs "  Jira URL: #{JIRA_BASE_URL}"
vputs "  Module Field ID: #{MODULE_FIELD}"
vputs "  Submodule Field ID: #{SUBMODULE_FIELD}"
vputs "  Banking Type Field ID: #{BANKING_TYPE_FIELD || 'Not found'}"


puts "\n" + "=" * 100
puts "📦 DEFECT MODULE & SUBMODULE ASSIGNMENT"
puts "=" * 100
puts "Mode: #{case options[:mode]
             when :single_defect then "Single Defect (#{options[:defect_key]})"
             when :project then "Project (#{options[:project_key]})"
             when :all then "All Defects"
             else "Not specified"
             end}"
puts "Data Source: Existing Database Module Names"
puts "Dry Run: #{DRY_RUN ? 'YES' : 'NO'}"
puts "Verbose: #{VERBOSE ? 'YES' : 'NO'}"
puts "=" * 100
puts ""


# ===============================
# JIRA API FUNCTIONS
# ===============================

def fetch_from_jira(issue_key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issues/#{issue_key}"
  uri = URI.parse(url)

  vputs "[JIRA] GET #{url}"

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  begin
    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      vputs "[JIRA] Error: #{response.code} - #{response.message}"
      return nil
    end

    data = JSON.parse(response.body)
    vputs "[JIRA] Fetched: #{data['key']}"
    return data
  rescue StandardError => e
    vputs "[JIRA] Exception: #{e.message}"
    return nil
  end
end

def extract_from_jira_fields(jira_issue)
  return [nil, nil] if jira_issue.nil?

  fields = jira_issue['fields'] || {}

  # Get raw values from custom fields
  module_field_value = fields[MODULE_FIELD]
  submodule_field_value = fields[SUBMODULE_FIELD]

  vputs "[JIRA FIELDS]"
  vputs "  Module Field (#{MODULE_FIELD}): #{module_field_value.inspect}"
  vputs "  Submodule Field (#{SUBMODULE_FIELD}): #{submodule_field_value.inspect}"

  # Extract string values from various formats
  jira_module = extract_field_value(module_field_value)
  jira_submodule = extract_field_value(submodule_field_value)

  vputs "[EXTRACTED]"
  vputs "  Module: #{jira_module.inspect}"
  vputs "  Submodule: #{jira_submodule.inspect}"

  # Parse if module has delimiter but no explicit submodule
  if jira_module.present? && jira_submodule.blank?
    parsed_module, parsed_submodule = extract_module_and_submodule(jira_module)
    if parsed_submodule.present?
      jira_module = parsed_module
      jira_submodule = parsed_submodule
      vputs "[PARSED FROM MODULE]"
      vputs "  Module: #{jira_module}"
      vputs "  Submodule: #{jira_submodule}"
    end
  end

  [jira_module, jira_submodule]
end

def extract_field_value(field_value)
  return nil if field_value.nil?
  return field_value if field_value.is_a?(String)

  if field_value.is_a?(Hash)
    return field_value['value'] if field_value['value'].present?
    return field_value['name'] if field_value['name'].present?
    return field_value['displayValue'] if field_value['displayValue'].present?
  end

  if field_value.is_a?(Array) && field_value.any?
    if field_value.first.is_a?(String)
      return field_value.first
    elsif field_value.first.is_a?(Hash)
      return field_value.first['value'] if field_value.first['value'].present?
      return field_value.first['name'] if field_value.first['name'].present?
      return field_value.first['displayValue'] if field_value.first['displayValue'].present?
    end
  end

  nil
end

# ===============================
# HELPER FUNCTIONS
# ===============================

# Enhanced parsing: Extract full module and submodule from text
# Handles formats like:
#   "Admin Portal – Bulk – Supervision" => Module="Admin Portal-Bulk", Submodule="Bulk-Supervision"
#   "Core Banking – Accounts – Savings" => Module="Core Banking-Accounts", Submodule="Accounts-Savings"
#   "Module - Submodule - Description - ..." => Module="Module-Submodule", Submodule="Submodule-Description"
#   "" or nil => Module=nil, Submodule=nil (returns nil for blank)
#
# Logic:
# 1. Return nil for blank/empty text (safe)
# 2. Split on em-dashes (–) or space-hyphen-space ( - ) or regular hyphen (-)
# 3. Take first N parts (before description)
# 4. Module = parts[0] - parts[1]
# 5. Submodule = parts[1] - parts[2] (if exists)
def extract_module_and_submodule(text)
  return [nil, nil] if text.blank?

  text = text.to_s.strip
  return [nil, nil] if text.empty?

  # Split on em-dashes or space-hyphen-space or regular hyphens
  # Priority: em-dash (–) > space-hyphen-space ( - ) > regular hyphen (-)
  parts = []
  if text.include?('–')
    parts = text.split('–').map(&:strip).reject(&:empty?)
  elsif text.include?(' - ')
    parts = text.split(' - ').map(&:strip).reject(&:empty?)
  elsif text.include?('-')
    parts = text.split('-').map(&:strip).reject(&:empty?)
  else
    # No delimiters found - return nil (don't treat as module)
    vputs "[EXTRACT] No delimiters found in: '#{text}'"
    return [nil, nil]
  end

  # Return nil if we don't have enough parts
  if parts.length < 2
    vputs "[EXTRACT] Only 1 part after split: '#{parts[0]}'"
    return [nil, nil]
  end

  # Module = parts[0] - parts[1]
  module_name = "#{parts[0]}-#{parts[1]}"

  # Submodule = parts[1] - parts[2] (if exists)
  submodule_name = nil
  if parts.length >= 3
    submodule_name = "#{parts[1]}-#{parts[2]}"
  end

  vputs "[EXTRACT] Found hierarchy: Module='#{module_name}', Submodule='#{submodule_name || '(none)'}'"
  [module_name, submodule_name]
end

# Find or create module in database
def find_or_create_module(module_name, product_id, _created_by)
  return nil if module_name.blank?

  module_name = module_name.to_s.strip
  return nil if module_name.empty?

  # Try to find existing module
  module_rec = QaModule.where(product_id: product_id).find_by('LOWER(name) = ?', module_name.downcase)

  if module_rec
    vputs "[MODULE-FOUND] #{module_name} (ID: #{module_rec.id})"
    return module_rec
  end

  # Create new module
  begin
    module_rec = QaModule.create!(
      name: module_name,
      product_id: product_id
    )
    vputs "[MODULE-CREATED] #{module_name} (ID: #{module_rec.id})"
    return module_rec
  rescue StandardError => e
    puts "❌ ERROR: Failed to create module '#{module_name}': #{e.message}"
    return nil
  end
end

# Find or create submodule in database
# Note: Submodules are QaModules with a parent_id set to the parent module
# They also need product_id to be set
def find_or_create_submodule(submodule_name, parent_module, product_id, _created_by)
  return nil if submodule_name.blank? || parent_module.nil?

  submodule_name = submodule_name.to_s.strip
  return nil if submodule_name.empty?

  # Try to find existing submodule (QaModule with parent_id)
  submodule_rec = QaModule.where(parent_id: parent_module.id).find_by('LOWER(name) = ?', submodule_name.downcase)

  if submodule_rec
    vputs "[SUBMODULE-FOUND] #{submodule_name} (ID: #{submodule_rec.id}, Parent: #{parent_module.name})"
    return submodule_rec
  end

  # Create new submodule (as a child QaModule)
  begin
    submodule_rec = QaModule.create!(
      name: submodule_name,
      parent_id: parent_module.id,
      product_id: product_id
    )
    vputs "[SUBMODULE-CREATED] #{submodule_name} (ID: #{submodule_rec.id}, Parent: #{parent_module.name})"
    return submodule_rec
  rescue StandardError => e
    puts "❌ ERROR: Failed to create submodule '#{submodule_name}': #{e.message}"
    return nil
  end
end

# Assign module and submodule to defect
def assign_modules_to_defect(defect, module_name, submodule_name, product_id, _created_by, dry_run: false)
  return { status: :skipped, reason: 'no_module_data' } if module_name.blank? && submodule_name.blank?

  vputs "\n[ASSIGN] #{defect.defect_unique}"
  vputs "  Current Module: #{defect.qa_module&.name} (ID: #{defect.qa_module_id})"
  vputs "  Current Submodule: #{defect.submodule&.name} (ID: #{defect.submodule_id})"
  vputs "  From Jira - Module: #{module_name}, Submodule: #{submodule_name || '(none)'}"

  # Find or create parent module
  parent_module = find_or_create_module(module_name, product_id, nil)
  return { status: :error, reason: 'failed_to_create_module' } unless parent_module

  # Find or create submodule (if provided)
  child_module = nil
  if submodule_name.present?
    child_module = find_or_create_submodule(submodule_name, parent_module, product_id, nil)
    return { status: :error, reason: 'failed_to_create_submodule' } unless child_module
  end

  # Check if assignment has changed
  module_changed = defect.qa_module_id != parent_module.id
  submodule_changed = defect.submodule_id != child_module&.id

  if !module_changed && !submodule_changed
    vputs "  ✓ No changes needed"
    return { status: :skipped, reason: 'no_changes' }
  end

  # Show what will change
  if module_changed
    old_name = defect.qa_module&.name || 'NONE'
    vputs "  CHANGE: Module #{old_name} → #{parent_module.name}"
  end

  if submodule_changed
    old_name = defect.submodule&.name || 'NONE'
    new_name = child_module&.name || 'NONE'
    vputs "  CHANGE: Submodule #{old_name} → #{new_name}"
  end

  return { status: :preview } if dry_run

  # Save changes
  begin
    defect.qa_module_id = parent_module.id
    defect.submodule_id = child_module&.id
    defect.updated_at = Time.current
    defect.save!

    vputs "  ✅ SAVED"
    return { status: :updated, module: parent_module.name, submodule: child_module&.name }
  rescue StandardError => e
    puts "  ❌ ERROR: Failed to save defect: #{e.message}"
    return { status: :error, reason: 'save_failed' }
  end
end

# ===============================
# MAIN EXECUTION
# ===============================

stats = {
  total: 0,
  updated: 0,
  skipped: 0,
  errors: 0,
  previewed: 0
}


# Fetch defects based on mode
defects = case options[:mode]
          when :single_defect
            Defect.where(defect_unique: options[:defect_key])
          when :project
            Defect.where('defect_unique ~ ?', "^#{Regexp.escape(options[:project_key])}-[0-9]+$")
          when :all
            Defect.where('defect_unique ~ ?', '^[A-Z]+-[0-9]+$')
          end

stats[:total] = defects.count

if defects.empty?
  puts "❌ No defects found for #{case options[:mode]
                                 when :single_defect then "#{options[:defect_key]}"
                                 when :project then "project #{options[:project_key]}"
                                 when :all then "the database"
                                 end}"
  exit 1
end

puts "Found #{stats[:total]} defect(s) to process...\n\n"

defects.find_each do |defect|
  vputs "\n[PROCESSING] #{defect.defect_unique}"

  # Extract module and submodule from defect summary or module name
  # Priority: Summary (has full hierarchy) > Module Name > Product Name > Project Key
  module_text = defect.summary
  module_text ||= defect.qa_module&.name
  module_text ||= defect.product&.name

  vputs "  Source Text: #{module_text}"

  if module_text.blank?
    stats[:skipped] += 1
    vputs "⏭️  #{defect.defect_unique}: Skipped (no summary, module name, or product)"
    next
  end

  module_to_assign, submodule_to_assign = extract_module_and_submodule(module_text)

  if module_to_assign.blank?
    stats[:skipped] += 1
    vputs "⏭️  #{defect.defect_unique}: Skipped (no valid module hierarchy found)"
    next
  end


  result = assign_modules_to_defect(
    defect,
    module_to_assign,
    submodule_to_assign,
    defect.product_id,
    nil,
    dry_run: DRY_RUN
  )

  case result[:status]
  when :updated
    stats[:updated] += 1
    puts "✅ #{defect.defect_unique}: Module=#{result[:module]}, Submodule=#{result[:submodule] || '(none)'}"
  when :skipped
    stats[:skipped] += 1
    vputs "⏭️  #{defect.defect_unique}: Skipped (#{result[:reason]})"
  when :preview
    stats[:previewed] += 1
    puts "👁️  #{defect.defect_unique}: Would be updated (DRY RUN)"
  when :error
    stats[:errors] += 1
    puts "❌ #{defect.defect_unique}: Error (#{result[:reason]})"
  end
end

puts "\n" + "=" * 100
puts "📊 SUMMARY"
puts "=" * 100
puts "Total Defects:     #{stats[:total]}"
puts "Updated:           #{stats[:updated]}"
puts "Previewed (DRY):   #{stats[:previewed]}"
puts "Skipped:           #{stats[:skipped]}"
puts "Errors:            #{stats[:errors]}"
puts ""

if DRY_RUN && stats[:previewed] > 0
  puts "ℹ️  DRY RUN MODE: #{stats[:previewed]} defect(s) would be updated."
  puts "   To apply changes, run without DRY_RUN=true"
elsif stats[:updated] > 0
  puts "✅ SUCCESS: #{stats[:updated]} defect(s) updated with module/submodule assignments"
else
  puts "ℹ️  No changes were made."
end

puts "=" * 100
puts "\n"

