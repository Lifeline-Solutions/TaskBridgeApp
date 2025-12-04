#!/usr/bin/env ruby
# Script to identify and fix incorrect DEFAULT_USER assignments
# Usage: rails runner scripts/fix_default_user_assignments.rb [--dry-run]

require 'optparse'

options = { dry_run: true }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_default_user_assignments.rb [options]'
  opts.on('--execute', 'Actually make changes (default is dry-run)') { options[:dry_run] = false }
  opts.on('--dry-run', 'Show what would be changed without making changes') { options[:dry_run] = true }
end.parse!

DEFAULT_USER_UUID = 'b3613172-fc54-4742-b2ba-c10b97d15bf4'.freeze

puts '=' * 80
puts 'ANALYZING DEFAULT_USER ASSIGNMENTS'
puts "Mode: #{options[:dry_run] ? 'DRY RUN (no changes)' : 'EXECUTE (will make changes)'}"
puts '=' * 80
puts ''

# Find all defects assigned to DEFAULT_USER
defects = Defect.where(assignee_id: DEFAULT_USER_UUID).includes(:events)
puts "Found #{defects.count} defects assigned to DEFAULT_USER"

# Find all events with DEFAULT_USER
events = Event.where(assigned_user_id: DEFAULT_USER_UUID)
puts "Found #{events.count} events with DEFAULT_USER"
puts ''

# Helper to match user
def find_better_match(name_str)
  return nil if name_str.blank?

  # Try dot-separated
  if name_str.include?('.')
    parts = name_str.split('.')
    if parts.length == 2
      users = User.where(deleted_on: nil, active: true)
        .where('lower(first_name) = ? AND lower(last_name) = ?',
               parts[0].downcase, parts[1].downcase)
        .to_a
      return users.find { |u| u.email&.end_with?('@craftsilicon.com') } || users.first
    end
  end

  # Try regular name split
  parts = name_str.split
  return nil if parts.length < 2

  first = parts.first
  last = parts[1..].join(' ')

  users = User.where(deleted_on: nil, active: true)
    .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
    .to_a

  users.find { |u| u.email&.end_with?('@craftsilicon.com') } || users.first
end

# Analyze defects
puts '-' * 80
puts 'DEFECT ANALYSIS'
puts '-' * 80

corrections = []

defects.each do |defect|
  # Look at events to find who was actually assigned
  assigned_events = defect.events.where("details ILIKE '%assigned to%'").order(:created_at)

  next if assigned_events.empty?

  # Parse first assignment event
  first_assignment = assigned_events.first
  next unless (match = first_assignment.details.match(/assigned to\s+([^,\n]+?)(?:\s+at|\s+on|\s+with|,|$)/i))

  assigned_name = match[1].strip

  # Try to find better match
  better_user = find_better_match(assigned_name)

  next unless better_user && better_user.id != DEFAULT_USER_UUID

  corrections << {
    type: :defect,
    id: defect.id,
    defect_unique: defect.defect_unique,
    current_assignee: DEFAULT_USER_UUID,
    suggested_assignee: better_user.id,
    suggested_name: "#{better_user.first_name} #{better_user.last_name}",
    suggested_email: better_user.email,
    source_name: assigned_name
  }
end

puts "\nFound #{corrections.length} defects that can be corrected:"

corrections.each_with_index do |corr, idx|
  puts "\n#{idx + 1}. #{corr[:defect_unique]}"
  puts "   Source name: '#{corr[:source_name]}'"
  puts "   Suggested: #{corr[:suggested_name]} (#{corr[:suggested_email]})"
end

# Apply corrections if not dry-run
if !options[:dry_run] && corrections.any?
  puts "\n#{'=' * 80}"
  puts 'APPLYING CORRECTIONS'
  puts '=' * 80

  corrections.each do |corr|
    defect = Defect.find(corr[:id])
    defect.update(assignee_id: corr[:suggested_assignee])
    puts "✅ Updated #{corr[:defect_unique]} -> #{corr[:suggested_name]}"
  end

  puts "\n✅ Updated #{corrections.length} defects"
else
  puts "\n💡 Run with --execute to apply these corrections"
end

# Analyze events
puts "\n#{'-' * 80}"
puts 'EVENT ANALYSIS'
puts '-' * 80

event_corrections = []

Event.where(assigned_user_id: DEFAULT_USER_UUID)
  .where("details ILIKE '%assigned%' OR details ILIKE '%was assigned%'")
  .find_each(batch_size: 100) do |event|
  # Try to extract name from details
  if (match = event.details.match(/assigned to\s+([^,\n]+?)(?:\s+at|\s+on|\s+with|,|$)/i))
    assigned_name = match[1].strip
    better_user = find_better_match(assigned_name)

    if better_user && better_user.id != DEFAULT_USER_UUID
      event_corrections << {
        event_id: event.id,
        ticket_id: event.ticket_id,
        current: DEFAULT_USER_UUID,
        suggested: better_user.id,
        suggested_name: "#{better_user.first_name} #{better_user.last_name}",
        source_name: assigned_name
      }
    end
  elsif (match = event.details.match(/([^,\n]+?)\s+was assigned/i))
    assigned_name = match[1].strip
    better_user = find_better_match(assigned_name)

    if better_user && better_user.id != DEFAULT_USER_UUID
      event_corrections << {
        event_id: event.id,
        ticket_id: event.ticket_id,
        current: DEFAULT_USER_UUID,
        suggested: better_user.id,
        suggested_name: "#{better_user.first_name} #{better_user.last_name}",
        source_name: assigned_name
      }
    end
  end
end

puts "\nFound #{event_corrections.length} events that can be corrected"
puts 'Showing first 20:'

event_corrections.first(20).each_with_index do |corr, idx|
  puts "#{idx + 1}. Event #{corr[:event_id][0..7]}... - '#{corr[:source_name]}' -> #{corr[:suggested_name]}"
end

# Apply event corrections if not dry-run
if !options[:dry_run] && event_corrections.any?
  puts "\n#{'=' * 80}"
  puts 'APPLYING EVENT CORRECTIONS'
  puts '=' * 80

  event_corrections.each_with_index do |corr, idx|
    Event.where(id: corr[:event_id]).update_all(assigned_user_id: corr[:suggested])
    print '.' if ((idx + 1) % 50).zero?
  end

  puts "\n✅ Updated #{event_corrections.length} events"
else
  puts "\n💡 Run with --execute to apply these corrections"
end

puts "\n#{'=' * 80}"
puts 'SUMMARY'
puts '=' * 80
puts "Defect corrections available: #{corrections.length}"
puts "Event corrections available:  #{event_corrections.length}"
puts "Total corrections available:  #{corrections.length + event_corrections.length}"
puts ''

if options[:dry_run]
  puts 'This was a DRY RUN - no changes were made'
  puts 'Run with --execute to apply corrections'
else
  puts '✅ Corrections have been applied'
end

puts '=' * 80
