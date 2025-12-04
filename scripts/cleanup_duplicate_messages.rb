#!/usr/bin/env ruby
# scripts/cleanup_duplicate_messages.rb
# Remove duplicate defect messages from the database
# Usage:
#   rails runner scripts/cleanup_duplicate_messages.rb              # All defects
#   rails runner scripts/cleanup_duplicate_messages.rb PSP-114      # Specific ticket
#   DRY_RUN=true rails runner scripts/cleanup_duplicate_messages.rb [TICKET]

DRY_RUN = ENV['DRY_RUN'].to_s.downcase == 'true'
SPECIFIC_TICKET = (ENV['TICKET'] || ARGV[0]).to_s.strip.upcase
SPECIFIC_TICKET = nil if SPECIFIC_TICKET.empty?

puts "\n" + "=" * 80
puts "🧹 DEFECT MESSAGE DUPLICATE CLEANUP"
puts "=" * 80
puts "Mode: #{DRY_RUN ? 'DRY RUN (no changes)' : 'LIVE (will delete duplicates)'}"
puts "Target: #{SPECIFIC_TICKET.present? ? "Single ticket: #{SPECIFIC_TICKET}" : 'All defects'}"
puts "\n"

def normalize_html(html)
  return '' if html.nil?
  html.to_s.gsub(/\s+/, ' ').strip.downcase
end

# Find defects (specific or all)
defects = if SPECIFIC_TICKET.present?
            Defect.where(defect_unique: SPECIFIC_TICKET, deleted_on: nil)
          else
            Defect.where(deleted_on: nil).where("defect_unique ~ '^[A-Z]+-[0-9]+$'")
          end

if defects.empty?
  puts "❌ No defects found#{SPECIFIC_TICKET.present? ? " with key: #{SPECIFIC_TICKET}" : ''}"
  puts "Please check the ticket number and try again."
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
      preview = msg.content.to_s[0..60].gsub(/\n/, ' ')
      puts "  └─ #{msg.created_at.strftime('%Y-%m-%d %H:%M')} | ID: #{msg.id} | \"#{preview}...\""
      
      unless DRY_RUN
        msg.destroy!
        total_deleted += 1
      end
    end
    
    duplicates_removed[defect.defect_unique] = duplicates_to_remove.count
  end
end

puts "\n" + "=" * 80
puts "📊 CLEANUP SUMMARY"
puts "=" * 80
puts "\n"

if duplicates_removed.empty?
  puts "✅ NO DUPLICATES FOUND TO REMOVE"
  puts "Target: #{SPECIFIC_TICKET.present? ? "Ticket #{SPECIFIC_TICKET}" : 'All defects'} is clean!"
else
  puts "Defects with duplicates removed:"
  duplicates_removed.each do |key, count|
    puts "  • #{key}: #{count} duplicate(s) #{DRY_RUN ? '(would be deleted)' : 'deleted'}"
  end
  
  puts "\n"
  if DRY_RUN
    puts "🔍 DRY RUN: #{duplicates_removed.values.sum} duplicate(s) would be deleted"
    puts "\nTo actually remove duplicates, run:"
    if SPECIFIC_TICKET.present?
      puts "  rails runner scripts/cleanup_duplicate_messages.rb #{SPECIFIC_TICKET}"
    else
      puts "  rails runner scripts/cleanup_duplicate_messages.rb"
    end
  else
    puts "✅ LIVE RUN: #{total_deleted} duplicate message(s) successfully deleted"
    puts "\nVerify the cleanup with:"
    if SPECIFIC_TICKET.present?
      puts "  rails runner scripts/verify_no_duplicates.rb"
      puts "\nOr verify just this ticket:"
      puts "  rails c"
      puts "  Defect.find_by(defect_unique: '#{SPECIFIC_TICKET}').defect_messages.count"
    else
      puts "  rails runner scripts/verify_no_duplicates.rb"
    end
  end
end

puts "\n" + "=" * 80
puts "\n"

