#!/usr/bin/env ruby
# scripts/assign_modules_from_jira.rb
# Fetch modules and submodules from Jira API and assign to defects
# Pulls custom field data directly from Jira for accurate module/submodule assignment
#
# Usage:
#   # Fetch from Jira and assign to single defect
#   rails runner scripts/assign_modules_from_jira.rb --defect PSP-114
#
#   # Fetch from Jira and assign to all defects in project
#   rails runner scripts/assign_modules_from_jira.rb --project PSP
#
#   # Fetch from Jira and assign to all defects
#   rails runner scripts/assign_modules_from_jira.rb --all
#
#   # Preview without saving
#   DRY_RUN=true rails runner scripts/assign_modules_from_jira.rb --all
#
#   # Verbose output with details
#   VERBOSE=true rails runner scripts/assign_modules_from_jira.rb --project PSP

require 'net/http'
require 'uri'
require 'json'
require 'optparse'
require 'yaml'

options = {
  dry_run: ENV['DRY_RUN'].to_s.downcase == 'true',
  verbose: ENV['VERBOSE'].to_s.downcase == 'true',
  mode: :none,
  defect_key: nil,
  project_key: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/assign_modules_from_jira.rb [OPTIONS]'

  opts.on('--defect KEY', 'Process single defect from Jira (e.g., PSP-114)') do |v|
    options[:mode] = :single_defect
    options[:defect_key] = v.upcase.strip
  end

  opts.on('--project KEY', 'Fetch all defects from Jira project (e.g., PSP)') do |v|
    options[:mode] = :project
    options[:project_key] = v.upcase.strip
  end

  opts.on('--all', 'Fetch all defects from all projects in Jira') do
    options[:mode] = :all
  end

  opts.on('--dry-run', "Preview changes without saving") do
    options[:dry_run] = true
  end

  opts.on('--verbose', 'Verbose output with detailed info') do
    options[:verbose] = true
  end

  opts.on('--help', 'Show help message') do
    puts opts
    puts "\n" + "=" * 100
    puts "EXAMPLES"
    puts "=" * 100
    puts "\n1. Fetch and assign for single defect from Jira:"
    puts "   rails runner scripts/assign_modules_from_jira.rb --defect PSP-114"
    puts ""
    puts "2. Fetch and assign for entire project from Jira:"
    puts "   rails runner scripts/assign_modules_from_jira.rb --project PSP"
    puts ""
    puts "3. Fetch and assign all defects from Jira:"
    puts "   rails runner scripts/assign_modules_from_jira.rb --all"
    puts ""
    puts "4. Preview changes before applying:"
    puts "   DRY_RUN=true rails runner scripts/assign_modules_from_jira.rb --project PSP"
    puts ""
    puts "5. Verbose output with fetch details:"
    puts "   VERBOSE=true rails runner scripts/assign_modules_from_jira.rb --defect PSP-114"
    puts ""
    puts "6. Dry run + verbose:"
    puts "   DRY_RUN=true VERBOSE=true rails runner scripts/assign_modules_from_jira.rb --project PSP"
    puts "\n" + "=" * 100
    exit 0
  end
end.parse!

if options[:mode] == :none
  puts "ERROR: Please specify --defect, --project, or --all"
  exit 1
end

APP_ROOT = Rails.root
DRY_RUN = options[:dry_run]
VERBOSE = options[:verbose]

# Load Jira configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user])
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN', CONFIG[:jira_api_token])

unless JIRA_API_USER && JIRA_API_TOKEN
  puts "ERROR: JIRA_API_USER and JIRA_API_TOKEN must be set in environment or config"
  exit 1
end

# Custom field IDs for module and submodule (from import config)
MODULE_FIELD = CONFIG[:module_field] || 'customfield_10141'
SUBMODULE_FIELD = CONFIG[:submodule_field] || 'customfield_10142'

def vputs(msg)
  puts msg if VERBOSE
end

puts "\n" + "=" * 100
puts "🔗 FETCH MODULES FROM JIRA & ASSIGN TO DEFECTS"
puts "=" * 100
puts "Mode: #{case options[:mode]
             when :single_defect then "Single Defect (#{options[:defect_key]})"
             when :project then "Project (#{options[:project_key]})"
             when :all then "All Defects"
             else "Not specified"
             end}"
puts "Data Source: JIRA API (#{JIRA_BASE_URL})"
puts "Dry Run: #{DRY_RUN ? 'YES (no changes)' : 'NO (will save)'}"
puts "Verbose: #{VERBOSE ? 'YES' : 'NO'}"
puts "=" * 100
puts ""

# ===============================
# JIRA API FUNCTIONS
# ===============================

def fetch_from_jira(jql)
  url = "#{JIRA_BASE_URL}/rest/api/3/search"
  uri = URI.parse(url)
  uri.query = URI.encode_www_form({ jql: jql, maxResults: 100 })

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    puts "❌ ERROR: Jira API returned #{response.code}: #{response.message}"
    return []
  end

  data = JSON.parse(response.body)
  data['issues'] || []
rescue StandardError => e
  puts "❌ ERROR fetching from Jira: #{e.class}: #{e.message}"
  []
end

def extract_custom_field_value(field_value)
  return nil if field_value.nil?

  return field_value if field_value.is_a?(String)

  if field_value.is_a?(Hash)
    return field_value['value'] if field_value['value'].present?
    return field_value['name'] if field_value['name'].present?
  end

  if field_value.is_a?(Array) && field_value.any?
    return field_value.first if field_value.first.is_a?(String)
    return field_value.first['value'] if field_value.first.is_a?(Hash) && field_value.first['value'].present?
    return field_value.first['name'] if field_value.first.is_a?(Hash) && field_value.first['name'].present?
  end

  nil
end

def extract_module_and_submodule(text)
  return [nil, nil] if text.blank?

  text = text.to_s.strip
  return [nil, nil] if text.empty?

  # Split on FIRST delimiter, keeping everything after as submodule
  parts = text.split(/\s*[-\u2013\u2014\/|]\s*/, 2)

  if parts.length == 2
    module_name = parts[0].strip
    submodule_name = parts[1].strip
    return [module_name, submodule_name]
  end

  [text, nil]
end

# Find or create module in database
def find_or_create_module(module_name, product_id, created_by)
  return nil if module_name.blank?

  module_name = module_name.to_s.strip
  return nil if module_name.empty?

  module_rec = QaModule.where(
    product_id: product_id,
    deleted_on: nil
  ).find_by('LOWER(name) = ?', module_name.downcase)

  if module_rec
    vputs "[MODULE-FOUND] #{module_name} (ID: #{module_rec.id})"
    return module_rec
  end

  begin
    module_rec = QaModule.create!(
      name: module_name,
      product_id: product_id,
      created_by: created_by,
      modified_by: created_by
    )
    vputs "[MODULE-CREATED] #{module_name} (ID: #{module_rec.id})"
    return module_rec
  rescue StandardError => e
    puts "❌ ERROR: Failed to create module '#{module_name}': #{e.message}"
    return nil
  end
end

# Find or create submodule in database
def find_or_create_submodule(submodule_name, parent_module, created_by)
  return nil if submodule_name.blank? || parent_module.nil?

  submodule_name = submodule_name.to_s.strip
  return nil if submodule_name.empty?

  submodule_rec = Submodule.where(
    qa_module_id: parent_module.id,
    deleted_on: nil
  ).find_by('LOWER(name) = ?', submodule_name.downcase)

  if submodule_rec
    vputs "[SUBMODULE-FOUND] #{submodule_name} (ID: #{submodule_rec.id})"
    return submodule_rec
  end

  begin
    submodule_rec = Submodule.create!(
      name: submodule_name,
      qa_module_id: parent_module.id,
      created_by: created_by,
      modified_by: created_by
    )
    vputs "[SUBMODULE-CREATED] #{submodule_name} (ID: #{submodule_rec.id})"
    return submodule_rec
  rescue StandardError => e
    puts "❌ ERROR: Failed to create submodule '#{submodule_name}': #{e.message}"
    return nil
  end
end

# Assign module and submodule to defect
def assign_modules_to_defect(defect, module_name, submodule_name, product_id, created_by, dry_run: false)
  return { status: :skipped, reason: 'no_module_data' } if module_name.blank?

  vputs "\n[PROCESSING] #{defect.defect_unique}"
  vputs "  Current Module: #{defect.qa_module&.name} (ID: #{defect.qa_module_id})"
  vputs "  Current Submodule: #{defect.submodule&.name} (ID: #{defect.submodule_id})"
  vputs "  From Jira - Module: #{module_name}, Submodule: #{submodule_name}"

  # Find or create modules
  parent_module = find_or_create_module(module_name, product_id, created_by)
  return { status: :error, reason: 'failed_to_create_module' } unless parent_module

  child_module = nil
  if submodule_name.present?
    child_module = find_or_create_submodule(submodule_name, parent_module, created_by)
  end

  # Check if assignment changed
  module_changed = defect.qa_module_id != parent_module.id
  submodule_changed = defect.submodule_id != child_module&.id

  if !module_changed && !submodule_changed
    vputs "  ✓ No changes needed"
    return { status: :skipped, reason: 'no_changes' }
  end

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
    defect.modified_by = created_by
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
  fetched_from_jira: 0,
  assigned: 0,
  skipped: 0,
  errors: 0,
  previewed: 0
}

default_user = User.where(deleted_on: nil).first
created_by = default_user&.id || '00000000-0000-0000-0000-000000000000'

# Build JQL based on mode
jql = case options[:mode]
      when :single_defect
        "key = #{options[:defect_key]}"
      when :project
        "project = #{options[:project_key]} ORDER BY created DESC"
      when :all
        "ORDER BY updated DESC"
      end

puts "📡 Fetching from Jira API with JQL: #{jql}\n\n"

# Fetch issues from Jira
jira_issues = fetch_from_jira(jql)

if jira_issues.empty?
  puts "❌ No issues found in Jira for: #{jql}"
  exit 1
end

puts "✅ Fetched #{jira_issues.length} issue(s) from Jira\n\n"

# Process each Jira issue
jira_issues.each do |jira_issue|
  issue_key = jira_issue['key']
  fields = jira_issue['fields'] || {}

  vputs "\n[JIRA-FETCH] #{issue_key}"

  # Extract module and submodule from Jira custom fields
  module_field_value = fields[MODULE_FIELD]
  submodule_field_value = fields[SUBMODULE_FIELD]

  jira_module = extract_custom_field_value(module_field_value)
  jira_submodule = extract_custom_field_value(submodule_field_value)

  vputs "  Jira Module Field: #{jira_module.inspect}"
  vputs "  Jira Submodule Field: #{jira_submodule.inspect}"

  # If module field has delimiter, parse it
  if jira_module.present? && jira_submodule.blank?
    parsed_module, parsed_submodule = extract_module_and_submodule(jira_module)
    jira_module = parsed_module
    jira_submodule = parsed_submodule
    vputs "  Parsed - Module: #{jira_module}, Submodule: #{jira_submodule}"
  end

  # Skip if no module found in Jira
  unless jira_module.present?
    stats[:skipped] += 1
    vputs "⏭️  #{issue_key}: Skipped (no module in Jira)"
    next
  end

  stats[:fetched_from_jira] += 1

  # Find or create defect in database
  defect = Defect.find_or_create_by(defect_unique: issue_key)

  # Get product from defect or Jira project
  product_id = defect.product_id
  unless product_id
    # Try to find product by project key
    project_key = issue_key.split('-').first
    product = Product.find_by(jira_key: project_key) || Product.first
    product_id = product&.id
  end

  unless product_id
    stats[:errors] += 1
    puts "❌ #{issue_key}: Error (no product found)"
    next
  end

  # Assign modules from Jira
  result = assign_modules_to_defect(
    defect,
    jira_module,
    jira_submodule,
    product_id,
    created_by,
    dry_run: DRY_RUN
  )

  case result[:status]
  when :updated
    stats[:assigned] += 1
    puts "✅ #{issue_key}: Module=#{result[:module]}, Submodule=#{result[:submodule]} (from Jira)"
  when :skipped
    stats[:skipped] += 1
    vputs "⏭️  #{issue_key}: Skipped (#{result[:reason]})"
  when :preview
    stats[:previewed] += 1
    puts "👁️  #{issue_key}: Would be updated (DRY RUN)"
  when :error
    stats[:errors] += 1
    puts "❌ #{issue_key}: Error (#{result[:reason]})"
  end
end

puts "\n" + "=" * 100
puts "📊 SUMMARY"
puts "=" * 100
puts "Fetched from Jira:   #{stats[:fetched_from_jira]}"
puts "Assigned to DB:      #{stats[:assigned]}"
puts "Previewed (DRY):     #{stats[:previewed]}"
puts "Skipped:             #{stats[:skipped]}"
puts "Errors:              #{stats[:errors]}"
puts ""

if DRY_RUN && stats[:previewed] > 0
  puts "ℹ️  DRY RUN MODE: #{stats[:previewed]} defect(s) would be updated from Jira data."
  puts "   To apply changes, run without DRY_RUN=true"
elsif stats[:assigned] > 0
  puts "✅ SUCCESS: #{stats[:assigned]} defect(s) updated with modules/submodules from Jira"
else
  puts "ℹ️  No changes were made."
end

puts "=" * 100
puts "\n"

