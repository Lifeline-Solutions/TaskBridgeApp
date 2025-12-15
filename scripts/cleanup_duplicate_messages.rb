#!/usr/bin/env ruby
# scripts/cleanup_duplicate_messages.rb
# Remove duplicate defect messages from the database
# Usage:
#   rails runner scripts/cleanup_duplicate_messages.rb                           # All defects
#   rails runner scripts/cleanup_duplicate_messages.rb --project ISP             # All ISP project defects
#   rails runner scripts/cleanup_duplicate_messages.rb --project ISP-100         # Specific defect ISP-100
#   DRY_RUN=true rails runner scripts/cleanup_duplicate_messages.rb --project ISP

require 'optparse'

options = {
  dry_run: false,
  project: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/cleanup_duplicate_messages.rb [options]'
  opts.on('--project PROJECT', 'Project key (e.g., ISP) or specific defect (e.g., ISP-100)') do |p|
    options[:project] = p.to_s.strip.upcase
  end
  opts.on('--dry-run', 'Simulate cleanup without actually deleting') do
    options[:dry_run] = true
  end
end.parse!

DRY_RUN = options[:dry_run] || ENV['DRY_RUN'].to_s.downcase == 'true'
PROJECT_OR_TICKET = options[:project]

puts "\n#{'=' * 80}"
puts '🧹 DEFECT MESSAGE DUPLICATE CLEANUP'
puts '=' * 80
puts "Mode: #{DRY_RUN ? 'DRY RUN (no changes)' : 'LIVE (will delete duplicates)'}"
if PROJECT_OR_TICKET.present?
  if PROJECT_OR_TICKET.include?('-')
    puts "Target: Specific defect: #{PROJECT_OR_TICKET}"
  else
    puts "Target: Project: #{PROJECT_OR_TICKET} (all defects)"
  end
else
  puts "Target: All defects"
end
puts "\n"

def normalize_html(html)
  return '' if html.nil?

  html.to_s.gsub(/\s+/, ' ').strip.downcase
end

# Find defects (specific, project, or all)
defects = if PROJECT_OR_TICKET.present?
            if PROJECT_OR_TICKET.include?('-')
              # Specific defect (e.g., ISP-100)
              Defect.where(defect_unique: PROJECT_OR_TICKET, deleted_on: nil)
            else
              # Project key (e.g., ISP) - match all defects with that prefix
              Defect.where('defect_unique LIKE ? AND deleted_on IS NULL', "#{PROJECT_OR_TICKET}-%")
            end
          else
            # All defects
            Defect.where(deleted_on: nil).where("defect_unique ~ '^[A-Z]+-[0-9]+$'")
          end

if defects.empty?
  if PROJECT_OR_TICKET.present?
    if PROJECT_OR_TICKET.include?('-')
      puts "❌ No defects found with key: #{PROJECT_OR_TICKET}"
    else
      puts "❌ No defects found with project key: #{PROJECT_OR_TICKET}"
    end
  else
    puts "❌ No defects found"
  end
  puts 'Please check the project key or defect key and try again.'
  exit 1
end

puts "Scanning #{defects.count} defect(s) for duplicate messages...\n\n"

total_deleted = 0
duplicates_removed = {}

defects.find_each do |defect|
  messages = defect.defect_messages
  next if messages.empty?

  # Find duplicates
  seen_normalized = {}
  duplicates_to_remove = []

  messages.each do |msg|
    normalized = normalize_html(msg.content.to_s)

    if seen_normalized[normalized]
      # This is a duplicate
      duplicates_to_remove << msg
    else
      # First occurrence, mark as seen
      seen_normalized[normalized] = msg.id
    end
  end

  if duplicates_to_remove.any?
    puts "#{defect.defect_unique}: Found #{duplicates_to_remove.count} duplicate message(s)"

    duplicates_to_remove.each do |msg|
      preview = msg.content.to_s[0..60].gsub("\n", ' ')
      puts "  └─ #{msg.created_at.strftime('%Y-%m-%d %H:%M')} | ID: #{msg.id} | \"#{preview}...\""

      unless DRY_RUN
        msg.destroy!
        total_deleted += 1
      end
    end

    duplicates_removed[defect.defect_unique] = duplicates_to_remove.count
  end
end

puts "\n#{'=' * 80}"
puts '📊 CLEANUP SUMMARY'
puts '=' * 80
puts "\n"

if duplicates_removed.empty?
  puts '✅ NO DUPLICATES FOUND TO REMOVE'
  if PROJECT_OR_TICKET.present?
    if PROJECT_OR_TICKET.include?('-')
      puts "Target: Defect #{PROJECT_OR_TICKET} is clean!"
    else
      puts "Target: Project #{PROJECT_OR_TICKET} is clean!"
    end
  else
    puts "Target: All defects are clean!"
  end
else
  puts 'Defects with duplicates removed:'
  duplicates_removed.each do |key, count|
    puts "  • #{key}: #{count} duplicate(s) #{DRY_RUN ? '(would be deleted)' : 'deleted'}"
  end

  puts "\n"
  if DRY_RUN
    puts "🔍 DRY RUN: #{duplicates_removed.values.sum} duplicate(s) would be deleted"
    puts "\nTo actually remove duplicates, run:"
    if PROJECT_OR_TICKET.present?
      puts "  rails runner scripts/cleanup_duplicate_messages.rb --project #{PROJECT_OR_TICKET}"
    else
      puts '  rails runner scripts/cleanup_duplicate_messages.rb'
    end
  else
    puts "✅ LIVE RUN: #{total_deleted} duplicate message(s) successfully deleted"
    puts "\nVerify the cleanup with:"
    puts '  rails runner scripts/verify_no_duplicates.rb'
  end
end

puts "\n#{'=' * 80}"
puts "\n"
