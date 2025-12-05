#!/usr/bin/env ruby
# scripts/verify_no_duplicates.rb
# Verify that the deduplication fix is working correctly
# Usage: rails runner scripts/verify_no_duplicates.rb

puts "\n" + "=" * 80
puts "🔍 DEFECT MESSAGE DEDUPLICATION VERIFICATION"
puts "=" * 80
puts "\n"

# Find all defects
defects = Defect.where(deleted_on: nil).where("defect_unique ~ '^[A-Z]+-[0-9]+$'")

puts "Checking #{defects.count} defects for duplicate messages..."
puts "\n"

duplicates_found = false
total_messages = 0
total_distinct = 0
issues_with_duplicates = []

defects.find_each do |defect|
  messages = defect.defect_messages
  next if messages.empty?

  total_count = messages.count
  distinct_count = messages.select(:content).distinct.count

  total_messages += total_count
  total_distinct += distinct_count

  if total_count > distinct_count

    duplicates_found = true
    duplicate_count = total_count - distinct_count
    issues_with_duplicates << {
      key: defect.defect_unique,
      total: total_count,
      distinct: distinct_count,
      duplicates: duplicate_count
    }

    puts "❌ #{defect.defect_unique}: #{total_count} total messages, #{distinct_count} distinct (#{duplicate_count} duplicates)"

    # Show the duplicate content
    message_contents = messages.pluck(:content).group_by { |c| c }.select { |_, v| v.size > 1 }
    message_contents.each do |content, occurrences|
      preview = content.to_s[0..80].gsub(/\n/, ' ')
      puts "   └─ Duplicate (#{occurrences.size}x): \"#{preview}...\""
    end
  else
    puts "✅ #{defect.defect_unique}: #{total_count} messages (all distinct)"
  end
end

puts "\n" + "=" * 80
puts "📊 SUMMARY"
puts "=" * 80
puts "\n"

puts "Total Defects Checked:      #{defects.count}"
puts "Total Messages:             #{total_messages}"
puts "Total Distinct Messages:    #{total_distinct}"
puts "Potential Duplicates:       #{total_messages - total_distinct}"
puts "\n"

if duplicates_found
  puts "❌ DUPLICATES DETECTED"
  puts "\nIssues with duplicates:"
  issues_with_duplicates.each do |issue|
    puts "  • #{issue[:key]}: #{issue[:duplicates]} duplicate(s) found"
  end
  puts "\nRun the repair script to fix these duplicates:"
  puts "  rails runner scripts/repair_rich_text_content.rb"
else
  puts "✅ NO DUPLICATES FOUND"
  puts "\nYour defect messages are clean and distinct!"
end

puts "\n" + "=" * 80
puts "\n"

