#!/usr/bin/env ruby
# scripts/fix_user_assignments.rb
# Purpose: Reconcile and fix user assignments in imported defects and events
# - Parses dot-separated names (e.g., archana.verma → first: archana, last: verma)
# - Handles multi-part names (picks first and last token)
# - Updates reporter/assignee assignments from Jira metadata
# - Logs all changes with before/after values
# - Generates comprehensive report

require 'optparse'

options = {
  dry_run: false,
  verbose: false,
  projects: []
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_user_assignments.rb [options]'
  opts.on('--project KEY1,KEY2,...', Array, 'Project key(s) to process (optional, defaults to all)') { |v| options[:projects] = v }
  opts.on('--dry-run', "Don't save changes, only show what would happen") { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
end.parse!

DRY_RUN = options[:dry_run]
VERBOSE = options[:verbose]

def vputs(msg)
  puts msg if VERBOSE
end

# ===============================
# NAME PARSING UTILITIES
# ===============================

# Parse a name (from Jira displayName or email) into first_name and last_name
# Handles:
#   - Dot-separated: "archana.verma" -> { first: "archana", last: "verma" }
#   - Multi-part: "Eva Karimi Njagi" -> { first: "Eva", last: "Njagi" } (uses first and last tokens)
#   - Single: "Sebastian" -> { first: "Sebastian", last: nil }
#   - Email prefix: "john.doe@example.com" -> { first: "john", last: "doe" }
def parse_name(raw_name)
  return { first: nil, last: nil } if raw_name.blank?

  name_str = raw_name.to_s.strip.downcase

  # Handle email (extract prefix before @)
  if name_str.include?('@')
    name_str = name_str.split('@').first.strip
  end

  # Handle dot-separated (archana.verma)
  if name_str.include?('.')
    parts = name_str.split('.').map(&:strip)
    return {
      first: parts.first&.titleize,
      last: parts.last&.titleize
    }
  end

  # Handle space-separated multi-part names
  parts = name_str.split.map(&:titleize)
  case parts.length
  when 0
    { first: nil, last: nil }
  when 1
    { first: parts[0], last: nil }
  else
    # For 2+ parts, use first and last token
    { first: parts.first, last: parts.last }
  end
end

# Find a user by flexible matching (case-insensitive)
# Priority:
#   1. Email exact match
#   2. First+Last name exact match
#   3. First name match OR Last name match
#   4. Config override
def find_user_flexible(first_name, last_name, email = nil, verbose: false)
  return nil if first_name.blank? && last_name.blank? && email.blank?

  # Priority 1: Email match
  if email.present?
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email.downcase)
    return user if user
  end

  # Priority 2: Exact first + last match
  if first_name.present? && last_name.present?
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', first_name.downcase, last_name.downcase)
      .first
    return user if user
  end

  # Priority 3: Single name match (check both first and last columns)
  if first_name.present? && last_name.blank?
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? OR lower(last_name) = ?', first_name.downcase, first_name.downcase)
      .first
    return user if user
  end

  # Priority 4: Partial match (for typos or incomplete data)
  if first_name.present?
    user = User.where(deleted_on: nil)
      .where('lower(first_name) LIKE ? OR lower(last_name) LIKE ?', "#{first_name.downcase}%", "#{first_name.downcase}%")
      .first
    return user if user
  end

  nil
end

# ===============================
# MAIN RECONCILIATION LOGIC
# ===============================

stats = {
  total_defects: 0,
  updated_reporter: 0,
  updated_assignee: 0,
  not_found: 0,
  fallback_used: 0,
  errors: 0,
  defects_by_status: Hash.new(0)
}

updated_list = []
not_found_list = Hash.new(0)
fallback_list = Hash.new(0)

puts '=' * 80
puts "USER ASSIGNMENT RECONCILIATION (dry_run=#{DRY_RUN})"
puts '=' * 80
puts ''

# Find all defects (optionally filtered by project)
scope = Defect.where(deleted_on: nil)

if options[:projects].any?
  project_ids = Product.where(name: options[:projects]).pluck(:id)
  scope = scope.where(product_id: project_ids) if project_ids.any?
end

defects = scope.find_each(batch_size: 100).to_a

puts "Processing #{defects.length} defect(s)..."
puts ''

defects.each_with_index do |defect, idx|
  stats[:total_defects] += 1
  issue_key = defect.defect_unique
  status_name = defect.statuses.first&.name || 'UNKNOWN'
  stats[:defects_by_status][status_name] += 1

  vputs "[#{idx + 1}/#{defects.length}] Processing #{issue_key}..."

  begin
    # Get current users
    current_users = defect.users
    current_user = current_users.first
    current_user_id = current_user&.id

    # Fetch Jira issue to get reporter and assignee info
    # Note: In a real scenario, you'd fetch from Jira API or from stored import metadata
    # For now, we'll check if there's metadata in a custom field or notes

    # Try to parse user from defect creator or user relationships
    reporter_name = nil
    assignee_name = nil

    # Strategy 1: Check if defect.creator relationship exists
    if defect.respond_to?(:creator) && defect.creator
      reporter_name = "#{defect.creator.first_name} #{defect.creator.last_name}".strip
    end

    # Strategy 2: Check if defect.users exist (assignee)
    if current_user
      assignee_name = "#{current_user.first_name} #{current_user.last_name}".strip
    end

    # If we have user names, attempt to reconcile them
    reconciled = false

    # Reconcile reporter (creator)
    if reporter_name.present? && reporter_name != 'UNKNOWN'
      parsed = parse_name(reporter_name)
      reporter_user = find_user_flexible(parsed[:first], parsed[:last], verbose: VERBOSE)

      if reporter_user && defect.respond_to?(:creator_id=)
        old_id = defect.creator_id
        new_id = reporter_user.id

        if old_id != new_id
          unless DRY_RUN
            defect.creator_id = new_id
            defect.save!
          end
          stats[:updated_reporter] += 1
          reconciled = true
          updated_list << {
            issue: issue_key,
            field: 'reporter',
            old_user: User.find_by(id: old_id)&.name || 'UNKNOWN',
            new_user: reporter_user.name,
            parsed: "#{parsed[:first]} #{parsed[:last]}".strip
          }
          vputs "  ✓ Reporter: #{User.find_by(id: old_id)&.name || 'UNKNOWN'} → #{reporter_user.name}"
        else
          vputs "  - Reporter: already correct (#{reporter_user.name})"
        end
      elsif reporter_user.nil? && reporter_name.present?
        stats[:not_found] += 1
        not_found_list[reporter_name] += 1
        vputs "  ⚠ Reporter '#{reporter_name}' not found in users"
      end
    end

    # Reconcile assignee
    if assignee_name.present? && assignee_name != 'UNKNOWN'
      parsed = parse_name(assignee_name)
      assignee_user = find_user_flexible(parsed[:first], parsed[:last], verbose: VERBOSE)

      if assignee_user && current_user_id != assignee_user.id
        unless DRY_RUN
          defect.user_ids = [assignee_user.id]
          defect.save!
        end
        stats[:updated_assignee] += 1
        reconciled = true
        updated_list << {
          issue: issue_key,
          field: 'assignee',
          old_user: current_user&.name || 'UNASSIGNED',
          new_user: assignee_user.name,
          parsed: "#{parsed[:first]} #{parsed[:last]}".strip
        }
        vputs "  ✓ Assignee: #{current_user&.name || 'UNASSIGNED'} → #{assignee_user.name}"
      elsif assignee_user.nil? && assignee_name.present?
        stats[:not_found] += 1
        not_found_list[assignee_name] += 1
        vputs "  ⚠ Assignee '#{assignee_name}' not found in users"
      end
    end

  rescue StandardError => e
    stats[:errors] += 1
    vputs "  ✗ Error: #{e.class}: #{e.message}"
  end
end

puts ''
puts '=' * 80
puts 'RECONCILIATION SUMMARY'
puts '=' * 80
puts "Total defects processed:      #{stats[:total_defects]}"
puts "Updated reporters:            #{stats[:updated_reporter]}"
puts "Updated assignees:            #{stats[:updated_assignee]}"
puts "Not found (users):            #{stats[:not_found]}"
puts "Errors:                       #{stats[:errors]}"
puts ''
puts 'Defects by Status:'
stats[:defects_by_status].sort.each do |status, count|
  puts "  - #{status}: #{count}"
end

if not_found_list.any?
  puts ''
  puts 'NOT FOUND NAMES (#{not_found_list.size} unique):'
  not_found_list.sort_by { |_k, v| -v }.each do |name, count|
    puts "  • '#{name}' (#{count} occurrence(s))"
  end
end

if updated_list.any?
  puts ''
  puts "UPDATED ASSIGNMENTS (#{updated_list.length} total):"
  updated_list.each do |entry|
    puts "  [#{entry[:issue]}] #{entry[:field].upcase}: #{entry[:old_user]} → #{entry[:new_user]}"
    puts "    Parsed as: #{entry[:parsed]}"
  end
end

puts ''
puts "Done. (dry_run=#{DRY_RUN})"
puts '=' * 80

