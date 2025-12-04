#!/usr/bin/env ruby
# scripts/cleanup_duplicate_messages.rb
# Remove duplicate defect messages from the database
# Usage: rails runner scripts/cleanup_duplicate_messages.rb [DRY_RUN=true]

DRY_RUN = ENV['DRY_RUN'].to_s.downcase == 'true'

puts "\n" + "=" * 80
puts "🧹 DEFECT MESSAGE DUPLICATE CLEANUP"
puts "=" * 80
puts "Mode: #{DRY_RUN ? 'DRY RUN (no changes)' : 'LIVE (will delete duplicates)'}"
puts "\n"

def normalize_html(html)
  return '' if html.nil?
  html.to_s.gsub(/\s+/, ' ').strip.downcase
end

# Find all defects
defects = Defect.where(deleted_on: nil).where("defect_unique ~ '^[A-Z]+-[0-9]+$'")

puts "Scanning #{defects.count} defects for duplicate messages...\n\n"

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
else
  puts "Defects with duplicates removed:"
  duplicates_removed.each do |key, count|
    puts "  • #{key}: #{count} duplicate(s) #{DRY_RUN ? '(would be deleted)' : 'deleted'}"
  end
  
  puts "\n"
  if DRY_RUN
    puts "🔍 DRY RUN: #{duplicates_removed.values.sum} duplicate(s) would be deleted"
    puts "\nTo actually remove duplicates, run:"
    puts "  rails runner scripts/cleanup_duplicate_messages.rb"
  else
    puts "✅ LIVE RUN: #{total_deleted} duplicate message(s) successfully deleted"
    puts "\nVerify the cleanup with:"
    puts "  rails runner scripts/verify_no_duplicates.rb"
  end
end

puts "\n" + "=" * 80
puts "\n"

