#!/usr/bin/env ruby
# scripts/assign_modules_and_submodules.rb
# Assign modules and submodules to defects based on extracted module/submodule data
# Ensures full module and submodule names are captured (not just before hyphen)
#
# Usage:
#   # Process single defect
#   rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114
#
#   # Process all defects in project
#   rails runner scripts/assign_modules_and_submodules.rb --project PSP
#
#   # Process all defects
#   rails runner scripts/assign_modules_and_submodules.rb --all
#
#   # Dry run to preview changes
#   DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --all
#
#   # Verbose output
#   VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

require 'optparse'

options = {
  dry_run: ENV['DRY_RUN'].to_s.downcase == 'true',
  verbose: ENV['VERBOSE'].to_s.downcase == 'true',
  mode: :none,
  defect_key: nil,
  project_key: nil,
  module_name: nil,
  submodule_name: nil,
  extract_from_existing: true  # Default: extract from current module name
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/assign_modules_and_submodules.rb [OPTIONS]'

  opts.on('--defect KEY', 'Process single defect (e.g., PSP-114)') do |v|
    options[:mode] = :single_defect
    options[:defect_key] = v.upcase.strip
  end

  opts.on('--project KEY', 'Process all defects in project (e.g., PSP)') do |v|
    options[:mode] = :project
    options[:project_key] = v.upcase.strip
  end

  opts.on('--all', 'Process all defects in database') do
    options[:mode] = :all
  end

  opts.on('--module MODULE', 'Module name to assign (e.g., "Core Banking")') do |v|
    options[:module_name] = v.to_s.strip
    options[:extract_from_existing] = false
  end

  opts.on('--submodule SUBMODULE', 'Submodule name to assign (e.g., "Accounts - Savings")') do |v|
    options[:submodule_name] = v.to_s.strip
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
    puts "\n1. Extract modules from existing data:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --project PSP"
    puts ""
    puts "2. Assign specific module/submodule to one defect:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114 --module \"Core Banking\" --submodule \"Accounts\""
    puts ""
    puts "3. Assign module/submodule to entire project:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --project PSP --module \"Core Banking\" --submodule \"Deposits\""
    puts ""
    puts "4. Assign module/submodule to all defects:"
    puts "   rails runner scripts/assign_modules_and_submodules.rb --all --module \"Mobile App\" --submodule \"Android\""
    puts ""
    puts "5. Preview changes before applying:"
    puts "   DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP --module \"Core Banking\""
    puts ""
    puts "6. Assign with verbose output:"
    puts "   VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114 --module \"Core Banking\" --submodule \"Accounts\""
    puts ""
    puts "7. Extract + verbose to see current state:"
    puts "   VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114"
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

puts "\n" + "=" * 100
puts "📦 DEFECT MODULE & SUBMODULE ASSIGNMENT"
puts "=" * 100
puts "Mode: #{case options[:mode]
             when :single_defect then "Single Defect (#{options[:defect_key]})"
             when :project then "Project (#{options[:project_key]})"
             when :all then "All Defects"
             else "Not specified"
             end}"
puts "Assignment Type: #{if options[:module_name].present?
                         "MANUAL - Module: #{options[:module_name]}, Submodule: #{options[:submodule_name] || '(none)'}"
                       else
                         "AUTO-EXTRACT - from existing module/product name"
                       end}"
puts "Dry Run: #{DRY_RUN ? 'YES' : 'NO'}"
puts "Verbose: #{VERBOSE ? 'YES' : 'NO'}"
puts "=" * 100
puts ""

# ===============================
# HELPER FUNCTIONS
# ===============================

# Enhanced parsing: Extract full module and submodule from text
# Handles formats like:
#   "Core Banking" => ["Core Banking", nil]
#   "Core Banking - Accounts" => ["Core Banking", "Accounts"]
#   "Core Banking - Accounts - Savings" => ["Core Banking", "Accounts - Savings"]
#   "Mobile App / Android / Login" => ["Mobile App", "Android / Login"]
def extract_module_and_submodule(text)
  return [nil, nil] if text.blank?

  text = text.to_s.strip
  return [nil, nil] if text.empty?

  # Try splitting on various delimiters: - (hyphen), – (en dash), — (em dash), / (slash), | (pipe)
  # Split on FIRST occurrence only, keeping everything after as submodule
  delimiters_regex = /\s*[-\u2013\u2014\/|]\s*/

  parts = text.split(delimiters_regex, 2)

  if parts.length == 2
    module_name = parts[0].strip
    submodule_name = parts[1].strip
    return [module_name, submodule_name]
  end

  # No delimiter found - treat entire text as module name
  [text, nil]
end

# Find or create module in database
def find_or_create_module(module_name, product_id, created_by)
  return nil if module_name.blank?

  module_name = module_name.to_s.strip
  return nil if module_name.empty?

  # Try to find existing module
  module_rec = QaModule.where(
    product_id: product_id,
    deleted_on: nil
  ).find_by('LOWER(name) = ?', module_name.downcase)

  if module_rec
    vputs "[MODULE-FOUND] #{module_name} (ID: #{module_rec.id})"
    return module_rec
  end

  # Create new module
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

  # Try to find existing submodule
  submodule_rec = Submodule.where(
    qa_module_id: parent_module.id,
    deleted_on: nil
  ).find_by('LOWER(name) = ?', submodule_name.downcase)

  if submodule_rec
    vputs "[SUBMODULE-FOUND] #{submodule_name} (ID: #{submodule_rec.id}, Parent: #{parent_module.name})"
    return submodule_rec
  end

  # Create new submodule
  begin
    submodule_rec = Submodule.create!(
      name: submodule_name,
      qa_module_id: parent_module.id,
      created_by: created_by,
      modified_by: created_by
    )
    vputs "[SUBMODULE-CREATED] #{submodule_name} (ID: #{submodule_rec.id}, Parent: #{parent_module.name})"
    return submodule_rec
  rescue StandardError => e
    puts "❌ ERROR: Failed to create submodule '#{submodule_name}': #{e.message}"
    return nil
  end
end

# Assign module and submodule to defect
def assign_modules_to_defect(defect, module_name, submodule_name, product_id, created_by, dry_run: false)
  return { status: :skipped, reason: 'no_module_data' } if module_name.blank? && submodule_name.blank?

  vputs "\n[PROCESSING] #{defect.defect_unique}"
  vputs "  Current Module: #{defect.qa_module&.name} (ID: #{defect.qa_module_id})"
  vputs "  Current Submodule: #{defect.submodule&.name} (ID: #{defect.submodule_id})"
  vputs "  New Module: #{module_name}"
  vputs "  New Submodule: #{submodule_name}"

  # Find or create parent module
  parent_module = find_or_create_module(module_name, product_id, created_by)
  return { status: :error, reason: 'failed_to_create_module' } unless parent_module

  # Find or create submodule (if provided)
  child_module = nil
  if submodule_name.present?
    child_module = find_or_create_submodule(submodule_name, parent_module, created_by)
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
  total: 0,
  updated: 0,
  skipped: 0,
  errors: 0,
  previewed: 0
}

# Fetch default user for created_by
default_user = User.where(deleted_on: nil).first
created_by = default_user&.id || '00000000-0000-0000-0000-000000000000'

# Fetch defects based on mode
defects = case options[:mode]
          when :single_defect
            Defect.where(defect_unique: options[:defect_key], deleted_on: nil)
          when :project
            Defect.where(deleted_on: nil).where('defect_unique ~ ?', "^#{Regexp.escape(options[:project_key])}-[0-9]+$")
          when :all
            Defect.where(deleted_on: nil).where('defect_unique ~ ?', '^[A-Z]+-[0-9]+$')
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
  # Determine which module/submodule to assign
  if options[:module_name].present?
    # Use provided module/submodule
    module_to_assign = options[:module_name]
    submodule_to_assign = options[:submodule_name]
  else
    # Extract from existing module name or derive from product
    module_text = defect.qa_module&.name
    module_text ||= defect.product&.name || defect.defect_unique.split('-').first
    module_to_assign, submodule_to_assign = extract_module_and_submodule(module_text)
  end

  result = assign_modules_to_defect(
    defect,
    module_to_assign,
    submodule_to_assign,
    defect.product_id,
    created_by,
    dry_run: DRY_RUN
  )

  case result[:status]
  when :updated
    stats[:updated] += 1
    puts "✅ #{defect.defect_unique}: Module=#{result[:module]}, Submodule=#{result[:submodule]}"
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

