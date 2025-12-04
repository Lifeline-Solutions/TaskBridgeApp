#!/usr/bin/env ruby
# scripts/validate_description_import.rb
# Validate that descriptions were imported properly as rich text

puts '=' * 80
puts 'DESCRIPTION IMPORT VALIDATION'
puts '=' * 80
puts ''

# Get recent defects
recent_defects = Defect.where('updated_at >= ?', 24.hours.ago).includes(:defect_message)

puts '📊 DESCRIPTION SUMMARY'
puts '-' * 80

defects_with_content = recent_defects.select { |d| d.content.present? }
defects_without_content = recent_defects.select { |d| d.content.blank? }

puts "✅ Defects with content: #{defects_with_content.count}"
puts "❌ Defects without content: #{defects_without_content.count}"
puts "Total processed: #{recent_defects.count}"
puts ''

if defects_without_content.any?
  puts '⚠️  DEFECTS MISSING CONTENT:'
  puts '-' * 80
  defects_without_content.first(10).each do |defect|
    puts "#{defect.defect_unique}: #{defect.summary}"
  end
  puts "... and #{defects_without_content.count - 10} more" if defects_without_content.count > 10
  puts ''
end

# Sample content checks
puts '📝 CONTENT SAMPLE CHECKS'
puts '-' * 80

content_stats = {
  plain_text: 0,
  html_formatted: 0,
  has_tables: 0,
  has_lists: 0,
  very_short: 0,
  very_long: 0
}

defects_with_content.each do |defect|
  content_text = begin
    defect.content.to_plain_text
  rescue StandardError
    defect.content.to_s
  end

  content_stats[:plain_text] += 1 if content_text.is_a?(String)

  # Check for HTML content
  content_stats[:html_formatted] += 1 if content_text.include?('<') || content_text.include?('[~')

  # Check for tables
  content_stats[:has_tables] += 1 if content_text.include?('<table') || content_text.include?('|')

  # Check for lists
  content_stats[:has_lists] += 1 if content_text.include?('<ul') || content_text.include?('<ol') || content_text.include?('- ')

  # Check size
  content_stats[:very_short] += 1 if content_text.length < 50
  content_stats[:very_long] += 1 if content_text.length > 5000
end

puts "Plain text content: #{content_stats[:plain_text]} defects"
puts "HTML formatted content: #{content_stats[:html_formatted]} defects"
puts "Content with tables: #{content_stats[:has_tables]} defects"
puts "Content with lists: #{content_stats[:has_lists]} defects"
puts "Very short content (<50 chars): #{content_stats[:very_short]} defects"
puts "Very long content (>5000 chars): #{content_stats[:very_long]} defects"
puts ''

# Show sample defects
puts '📋 SAMPLE DEFECTS'
puts '-' * 80

defects_with_content.first(3).each do |defect|
  puts "\n#{defect.defect_unique}:"
  puts "Summary: #{defect.summary}"

  content_preview = begin
    defect.content.to_plain_text.truncate(200)
  rescue StandardError
    defect.content.to_s.truncate(200)
  end

  puts "Content: #{content_preview}"
end

puts ''
puts '=' * 80
puts 'END VALIDATION'
puts '=' * 80
