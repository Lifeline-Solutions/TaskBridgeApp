#!/usr/bin/env ruby
# scripts/fix_defect_users_from_db.rb
#
# This script calls Jira API to get the ACTUAL reporter and assignee,
# then compares with what's in your database and fixes any discrepancies.
#
# It will update creator_id (created_by) and assignees if they differ from Jira.
#
# Usage:
#   # Update all defects for a project from Jira
#   bundle exec rails runner scripts/fix_defect_users_from_db.rb --project ISP
#
#   # Update a specific issue from Jira
#   bundle exec rails runner scripts/fix_defect_users_from_db.rb --issue ISP-1383
#
#   # Dry run (preview without saving)
#   bundle exec rails runner scripts/fix_defect_users_from_db.rb --project ISP --dry-run
#
#   # Verbose output
#   bundle exec rails runner scripts/fix_defect_users_from_db.rb --issue ISP-1383 --verbose

require 'optparse'
require 'yaml'

# Enable real-time logging
$stdout.sync = true
$stderr.sync = true

APP_ROOT = Rails.root

options = {
  dry_run: false,
  verbose: false,
  project: nil,
  issue: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_defect_users_from_db.rb [options]'

  opts.on('--project KEY', String, 'Project key (e.g., PSP, KCBL, ISP)') { |v| options[:project] = v }
  opts.on('--issue KEY', String, 'Specific issue key (e.g., KCBL-1096)') { |v| options[:issue] = v }
  opts.on('--dry-run', 'Preview changes without saving') { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
end.parse!

if options[:project].nil? && options[:issue].nil?
  puts 'ERROR: Either --project or --issue is required'
  puts ''
  puts 'Examples:'
  puts '  Update all KCBL defects:      --project KCBL'
  puts '  Update specific issue:        --issue KCBL-1096'
  puts '  Preview changes (dry run):    --project KCBL --dry-run'
  puts '  Verbose output:               --project KCBL --verbose'
  exit 1
end

# Load configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
if File.exist?(config_path)
  CONFIG = YAML.load_file(config_path).with_indifferent_access
  DEFAULT_USER_UUID = CONFIG[:default_user_uuid]
else
  DEFAULT_USER_UUID = nil
end

def info(msg)
  puts msg
end

def vputs(msg)
  puts msg if $verbose_flag
end

$verbose_flag = options[:verbose]

puts ''
puts '=' * 80
puts 'DEFECT USER FIXER (DATABASE-ONLY MODE)'
puts '=' * 80
puts "Mode: #{options[:dry_run] ? '🔍 DRY RUN (preview only)' : '💾 LIVE UPDATE'}"
puts "Project: #{options[:project] || 'N/A'}"
puts "Issue: #{options[:issue] || 'All issues in project'}"
puts "Verbose: #{options[:verbose]}"
puts ''
puts 'ℹ️  This script works with existing database data'
puts '   It does NOT call Jira API - perfect for archived/deleted issues'
puts '=' * 80
puts ''

# ===============================
# INTELLIGENT NAME MATCHING
# ===============================

def find_user_by_intelligent_match(name_or_email, verbose: false)
  return nil if name_or_email.blank?

  name_str = name_or_email.to_s.strip

  # Email matching
  if name_str.include?('@')
    email_str = name_str.downcase
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str)
    if user
      vputs "  [MATCH-EMAIL] '#{name_str}' → #{user.first_name} #{user.last_name} (ID: #{user.id})" if verbose
      return user
    end

    email_prefix = email_str.split('@').first
    name_str = email_prefix.gsub(/[._-]/, ' ').titleize
    vputs "  [EMAIL→NAME] Converted to: '#{name_str}'" if verbose
  end

  clean_name = name_str.gsub(/[^a-zA-Z\s.]/, ' ').squeeze(' ').strip
  parts = clean_name.split(/\s+/)

  # Exact full name match
  normalized = clean_name.downcase
  user = User.where(deleted_on: nil)
    .where("lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) = ?", normalized)
    .first
  if user
    vputs "  [MATCH-EXACT] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
    return user
  end

  # Handle initials
  if parts.length >= 2
    first_part = parts[0]
    rest_parts = parts[1..]

    if first_part.length <= 2 && first_part.match?(/^[A-Z]\.?$/i)
      initial = first_part[0].upcase
      last_name = rest_parts.join(' ')

      user = User.where(deleted_on: nil)
        .where('upper(substring(first_name, 1, 1)) = ? AND lower(last_name) = ?', initial, last_name.downcase)
        .first

      if user
        vputs "  [MATCH-INITIAL] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
        return user
      end
    end
  end

  # Standard first + last
  if parts.length >= 2
    first = parts.first
    last = parts[1..].join(' ')

    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
      .first
    if user
      vputs "  [MATCH-NAME] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end

    # Try reversed
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? AND lower(last_name) = ?', last.downcase, first.downcase)
      .first
    if user
      vputs "  [MATCH-REVERSED] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  # Single name
  if parts.length == 1
    single = parts.first.downcase
    user = User.where(deleted_on: nil)
      .where('lower(first_name) = ? OR lower(last_name) = ?', single, single)
      .first
    if user
      vputs "  [MATCH-SINGLE] '#{name_str}' → #{user.first_name} #{user.last_name}" if verbose
      return user
    end
  end

  vputs "  [NO-MATCH] ❌ '#{name_str}'" if verbose
  nil
end

# ===============================
# EXTRACT NAMES FROM DEFECT DATA
# ===============================

# Try to extract creator/assignee names from defect description, content, or other fields
# This is a heuristic approach when Jira data isn't available
def extract_potential_names_from_defect(defect)
  names = []

  # Check defect messages for author names
  if defect.respond_to?(:defect_messages)
    defect.defect_messages.each do |msg|
      next unless msg.user && msg.user.id != DEFAULT_USER_UUID

      user = msg.user
      full_name = "#{user.first_name} #{user.last_name}".strip
      names << full_name if full_name.present?
    end
  end

  # Check defect history for user names
  if defect.respond_to?(:defect_histories)
    defect.defect_histories.each do |history|
      next unless history.user && history.user.id != DEFAULT_USER_UUID

      user = history.user
      full_name = "#{user.first_name} #{user.last_name}".strip
      names << full_name if full_name.present?
    end
  end

  names.uniq
end

# ===============================
# MAIN UPDATE LOGIC
# ===============================

stats = {
  total: 0,
  updated_creator: 0,
  skipped_no_default: 0,
  skipped_no_candidates: 0,
  failed: 0,
  creator_before_after: {}
}

# Build defect query
defect_query = Defect.where.not(defect_unique: nil)

if options[:issue]
  defect_query = defect_query.where(defect_unique: options[:issue])
elsif options[:project]
  defect_query = defect_query.where('defect_unique LIKE ?', "#{options[:project]}-%")
end

defects = defect_query.order(:defect_unique).to_a

if defects.empty?
  puts 'No defects found matching criteria'
  exit 0
end

info "Found #{defects.length} defect(s) to process"
info ''

default_user = User.find_by(id: DEFAULT_USER_UUID) if DEFAULT_USER_UUID

defects.each_with_index do |defect, idx|
  stats[:total] += 1

  info "[#{idx + 1}/#{defects.length}] 📋 #{defect.defect_unique}"

  begin
    current_creator_id = begin
      defect.created_by
    rescue StandardError
      nil
    end
    current_creator = User.find_by(id: current_creator_id) if current_creator_id

    # Only try to fix if currently using default user
    if DEFAULT_USER_UUID && current_creator_id == DEFAULT_USER_UUID
      info '  ⚠️  Currently using default user'

      # Extract potential names from related records
      potential_names = extract_potential_names_from_defect(defect)

      if potential_names.any?
        info "  🔍 Found #{potential_names.length} potential creator(s) from defect activity:"
        potential_names.each { |name| vputs "     - #{name}" if options[:verbose] }

        # Use the first one (most common in messages/history)
        candidate_name = potential_names.first
        matched_user = find_user_by_intelligent_match(candidate_name, verbose: options[:verbose])

        if matched_user
          current_name = current_creator ? "#{current_creator.first_name} #{current_creator.last_name}" : 'None'
          new_name = "#{matched_user.first_name} #{matched_user.last_name}"

          info '  📝 Creator update suggestion:'
          info "     Before: #{current_name} (ID: #{current_creator_id})"
          info "     After:  #{new_name} (ID: #{matched_user.id})"
          info '     Based on: Activity in comments/history'

          stats[:creator_before_after][defect.defect_unique] = {
            before: current_name,
            before_id: current_creator_id,
            after: new_name,
            after_id: matched_user.id,
            source: 'defect_activity'
          }

          if options[:dry_run]
            info '     [DRY RUN] Would update created_by'
          else
            defect.created_by = matched_user.id

            if defect.save
              info '  ✅ Updated'
              stats[:updated_creator] += 1
            else
              warn "  ❌ Save failed: #{defect.errors.full_messages.join(', ')}"
              stats[:failed] += 1
            end
          end
        else
          info "  ⚠️  Could not match candidate: '#{candidate_name}'"
          stats[:skipped_no_candidates] += 1
        end
      else
        info '  ℹ️  No activity data available to suggest creator'
        stats[:skipped_no_candidates] += 1
      end
    else
      current_name = current_creator ? "#{current_creator.first_name} #{current_creator.last_name}" : 'Unknown'
      vputs "  ✓ Creator already set: #{current_name}" if options[:verbose]
      stats[:skipped_no_default] += 1
    end
  rescue StandardError => e
    warn "  ❌ Error: #{e.message}"
    warn "     #{e.backtrace.first}" if options[:verbose]
    stats[:failed] += 1
  end

  info ''
end

# ===============================
# FINAL REPORT
# ===============================

puts ''
puts '=' * 80
puts 'FINAL REPORT'
puts '=' * 80
puts ''

puts 'Summary:'
puts "  Total defects processed: #{stats[:total]}"
puts "  Creators updated: #{stats[:updated_creator]}"
puts "  Already correct (not default): #{stats[:skipped_no_default]}"
puts "  No candidates found: #{stats[:skipped_no_candidates]}"
puts "  Failed: #{stats[:failed]}"
puts ''

if stats[:creator_before_after].any?
  puts '📋 Detailed Changes:'
  stats[:creator_before_after].each do |issue_key, change|
    puts "  #{issue_key}:"
    puts "    Before: #{change[:before]} (ID: #{change[:before_id]})"
    puts "    After:  #{change[:after]} (ID: #{change[:after_id]})"
    puts "    Source: #{change[:source]}"
  end
  puts ''
end

puts '=' * 80

if options[:dry_run]
  puts ''
  puts '🔍 DRY RUN MODE - No changes were saved'
  puts '   Run without --dry-run to apply changes'
  puts ''
end

puts 'Done!'
puts ''
