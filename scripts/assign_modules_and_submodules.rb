#!/usr/bin/env ruby
# scripts/assign_modules_and_submodules.rb
# Fetch modules and submodules from Jira API and assign to defects
# Automatically discovers custom fields and matches Jira issues to database defects
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
    if name == 'imarisha  erp modules'
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

# ===============================
# JIRA API FUNCTIONS
# ===============================

def fetch_jira_issues_with_modules(project_keys:, custom_jql: nil, max_results: 100, days_back: 2000)
  # First discover custom fields
  module_field, submodule_field, banking_type_field = discover_custom_fields

  issues = []
  next_page_token = nil
  page_count = 0
  max_pages = 500

  start_date = (Time.now - (days_back * 24 * 60 * 60)).strftime('%Y-%m-%d')
  end_date = Time.now.strftime('%Y-%m-%d')

  jql_query = if custom_jql.present?
                custom_jql
              else
                # Build JQL for multiple projects using IN operator
                project_clause = if project_keys.length == 1
                                   "project = \"#{project_keys.first}\""
                                 else
                                   "project IN (#{project_keys.map { |p| "\"#{p}\"" }.join(', ')})"
                                 end
                "#{project_clause} AND created >= \"#{start_date}\" ORDER BY created DESC"
              end

  vputs "Fetching Jira issues with JQL: #{jql_query}"
  vputs "Date range: #{start_date} to #{end_date}" unless custom_jql.present?
  vputs "Projects: #{project_keys.join(', ')}"
  puts "DEBUG: Project keys received: #{project_keys.inspect}"
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
    http.read_timeout = 120
    http.open_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    vputs "Page #{page_count}: Requesting with nextPageToken=#{next_page_token.present? ? "#{next_page_token[0..20]}..." : 'nil'}" if VERBOSE

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      warn "❌ Failed to fetch from Jira: #{response.code} #{response.message}"
      warn "Response body: #{response.body[0..500]}"
      break
    end

    data = JSON.parse(response.body)
    fetched = data['issues'] || []

    if fetched.empty?
      vputs "✓ Page #{page_count}: No issues returned - pagination complete (no more data)"
      break
    end

    issues.concat(fetched)
    total_fetched = issues.length

    next_page_token = data['nextPageToken']
    is_last_page = data['isLast'] == true

    vputs "✓ Page #{page_count}: Fetched #{fetched.length} issues (total collected: #{total_fetched}) [isLast: #{is_last_page}, hasNextToken: #{next_page_token.present? ? 'YES' : 'NO'}]"

    if is_last_page
      vputs '✓ Jira indicates last page (isLast: true) - pagination complete'
      break
    end

    unless next_page_token.present?
      vputs '✓ No nextPageToken provided - reached end of results'
      break
    end

    sleep 1.0 # Delay between pages to avoid rate limiting
  end

  puts "📊 Total issues fetched from Jira: #{issues.length} (across #{page_count} pages)"

  # Return both issues and discovered field IDs
  {
    issues: issues,
    module_field: module_field,
    submodule_field: submodule_field,
    banking_type_field: banking_type_field
  }
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
def extract_module_and_submodule(text)
  return [nil, nil] if text.blank?

  text = text.to_s.strip
  return [nil, nil] if text.empty?

  # Split on em-dashes or space-hyphen-space or regular hyphens
  parts = []
  if text.include?('–')
    parts = text.split('–').map(&:strip).reject(&:empty?)
  elsif text.include?(' - ')
    parts = text.split(' - ').map(&:strip).reject(&:empty?)
  elsif text.include?('-')
    parts = text.split('-').map(&:strip).reject(&:empty?)
  else
    vputs "[EXTRACT] No delimiters found in: '#{text}'"
    return [nil, nil]
  end

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

puts "\n" + "=" * 100
puts "📦 DEFECT MODULE & SUBMODULE ASSIGNMENT FROM JIRA"
puts "=" * 100
puts "Mode: #{case options[:mode]
             when :single_defect then "Single Defect (#{options[:defect_key]})"
             when :project then "Project (#{options[:project_key]})"
             when :all then "All Defects"
             else "Not specified"
             end}"
puts "Data Source: Jira API with Custom Field Discovery"
puts "Dry Run: #{DRY_RUN ? 'YES' : 'NO'}"
puts "Verbose: #{VERBOSE ? 'YES' : 'NO'}"
puts "=" * 100
puts ""

stats = {
  total: 0,
  updated: 0,
  skipped: 0,
  errors: 0,
  previewed: 0,
  jira_issues_fetched: 0,
  jira_matched: 0
}

# Determine which projects to fetch from Jira
jira_projects = case options[:mode]
                when :single_defect
                  # Extract project key from defect (e.g., PSP-114 → PSP)
                  [options[:defect_key].split('-').first]
                when :project
                  [options[:project_key]]
                else # :all
                  # Get all unique project keys from database
                  Defect.pluck('DISTINCT LOWER(defect_unique)').map do |unique|
                    unique.split('-').first.upcase
                  end.uniq
                end

vputs "Jira projects to fetch: #{jira_projects.inspect}"

# Fetch issues from Jira with custom field discovery
jira_result = fetch_jira_issues_with_modules(
  project_keys: jira_projects,
  max_results: 100,
  days_back: 2000
)

jira_issues = jira_result[:issues]
module_field = jira_result[:module_field]
submodule_field = jira_result[:submodule_field]

stats[:jira_issues_fetched] = jira_issues.length

vputs "Discovered custom fields:"
vputs "  Module Field: #{module_field}"
vputs "  Submodule Field: #{submodule_field}"

# Create a mapping of Jira keys to issues
jira_issues_map = {}
jira_issues.each do |issue|
  jira_issues_map[issue['key']] = issue
end

vputs "Created Jira issues map with #{jira_issues_map.length} issues"

# Fetch defects based on mode
defects = case options[:mode]
          when :single_defect
            Defect.where(defect_unique: options[:defect_key])
          when :project
            Defect.where('defect_unique ~ ?', "^#{Regexp.escape(options[:project_key])}-[0-9]+$")
          else # :all
            Defect.where('defect_unique ~ ?', '^[A-Z]+-[0-9]+$')
          end

stats[:total] = defects.count

if defects.empty?
  puts "❌ No defects found"
  exit 1
end

puts "Found #{stats[:total]} defect(s) to process...\n\n"

defects.find_each do |defect|
  vputs "\n[PROCESSING] #{defect.defect_unique}"

  # Try to find matching Jira issue
  jira_issue = jira_issues_map[defect.defect_unique]

  if jira_issue.nil?
    vputs "⏭️  #{defect.defect_unique}: Skipped (not found in Jira)"
    stats[:skipped] += 1
    next
  end

  stats[:jira_matched] += 1

  # Extract module and submodule from Jira custom fields
  module_to_assign = nil
  submodule_to_assign = nil

  # Try to get from custom fields first
  if module_field && jira_issue['fields'][module_field].present?
    module_to_assign = extract_field_value(jira_issue['fields'][module_field])
    vputs "  [From Module Field] #{module_to_assign}"
  end

  if submodule_field && jira_issue['fields'][submodule_field].present?
    submodule_to_assign = extract_field_value(jira_issue['fields'][submodule_field])
    vputs "  [From Submodule Field] #{submodule_to_assign}"
  end

  # If module not found in custom field, try extracting from summary
  if module_to_assign.blank?
    summary = jira_issue['fields']['summary']
    if summary.present?
      vputs "  [From Summary] #{summary[0..50]}..."
      module_to_assign, submodule_from_summary = extract_module_and_submodule(summary)
      submodule_to_assign ||= submodule_from_summary
    end
  end

  if module_to_assign.blank?
    stats[:skipped] += 1
    vputs "⏭️  #{defect.defect_unique}: Skipped (no module found in Jira)"
    next
  end

  vputs "  Extracted: Module='#{module_to_assign}', Submodule='#{submodule_to_assign || '(none)'}'"

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
puts "Jira Issues Fetched: #{stats[:jira_issues_fetched]}"
puts "Jira Issues Matched: #{stats[:jira_matched]}"
puts "Total Defects:       #{stats[:total]}"
puts "Updated:             #{stats[:updated]}"
puts "Previewed (DRY):     #{stats[:previewed]}"
puts "Skipped:             #{stats[:skipped]}"
puts "Errors:              #{stats[:errors]}"
puts ""

if DRY_RUN && stats[:previewed] > 0
  puts "ℹ️  DRY RUN MODE: #{stats[:previewed]} defect(s) would be updated."
  puts "   To apply changes, run without DRY_RUN=true"
elsif stats[:updated] > 0
  puts "✅ SUCCESS: #{stats[:updated]} defect(s) updated with modules/submodules from Jira"
else
  puts "ℹ️  No changes were made."
end

puts "=" * 100
puts "\n"

