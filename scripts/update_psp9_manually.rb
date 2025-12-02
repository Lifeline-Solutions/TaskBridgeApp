#!/usr/bin/env ruby
# Manual script to update PSP-9 with proper table HTML
# This script helps when the Jira API has issues or returns incomplete data

# Load Rails environment
require_relative '../config/environment'

require 'json'

puts "=" * 80
puts "PSP-9 Manual Table Update Script"
puts "=" * 80
puts ""

# Find the defect
defect = Defect.find_by(defect_unique: 'PSP-9')

if defect.nil?
  puts "❌ Defect PSP-9 not found in database"
  exit 1
end

puts "✓ Found defect PSP-9"
puts "  Current content length: #{defect.content.to_s.length} characters"
puts ""

# Check for converted HTML file
html_file = 'tmp/psp9_converted.html'
trix_file = 'tmp/psp9_trix.html'

if File.exist?(trix_file)
  puts "✓ Found converted Trix HTML file: #{trix_file}"
  new_content = File.read(trix_file)

  puts "  New content length: #{new_content.length} characters"
  puts "  Has table: #{new_content.include?('<table')}"
  puts ""

  puts "Preview of new content (first 500 chars):"
  puts "-" * 80
  puts new_content[0..500]
  puts "-" * 80
  puts ""

  print "Do you want to update PSP-9 with this content? (yes/no): "
  response = gets.chomp.downcase

  if response == 'yes' || response == 'y'
    defect.content = new_content
    if defect.save(validate: false)
      puts "✅ Successfully updated PSP-9 description"
      puts "  New length: #{defect.content.length} characters"
    else
      puts "❌ Failed to save: #{defect.errors.full_messages.join(', ')}"
    end
  else
    puts "❌ Update cancelled"
  end

elsif File.exist?(html_file)
  puts "✓ Found converted HTML file: #{html_file}"
  html_content = File.read(html_file)

  # Wrap in Trix div
  new_content = %(<div class="trix-content">\n  #{html_content}\n</div>)

  puts "  New content length: #{new_content.length} characters"
  puts "  Has table: #{new_content.include?('<table')}"
  puts ""

  puts "Preview of new content (first 500 chars):"
  puts "-" * 80
  puts new_content[0..500]
  puts "-" * 80
  puts ""

  print "Do you want to update PSP-9 with this content? (yes/no): "
  response = gets.chomp.downcase

  if response == 'yes' || response == 'y'
    defect.content = new_content
    if defect.save(validate: false)
      puts "✅ Successfully updated PSP-9 description"
      puts "  New length: #{defect.content.length} characters"
    else
      puts "❌ Failed to save: #{defect.errors.full_messages.join(', ')}"
    end
  else
    puts "❌ Update cancelled"
  end

else
  puts "❌ No converted HTML files found"
  puts ""
  puts "Please follow these steps:"
  puts "1. Get the Jira description JSON for PSP-9"
  puts "2. Save it to tmp/psp9_description.json"
  puts "3. Run: ruby scripts/convert_psp9_table.rb"
  puts "4. Run this script again"
  puts ""
  puts "Or you can manually provide HTML content:"
  puts ""

  # Option to manually paste HTML
  print "Do you want to paste HTML content directly? (yes/no): "
  response = gets.chomp.downcase

  if response == 'yes' || response == 'y'
    puts ""
    puts "Paste the HTML content (end with a line containing only 'END'):"
    puts ""

    lines = []
    while (line = gets.chomp) != 'END'
      lines << line
    end

    new_content = lines.join("\n")

    # Wrap in Trix div if not already wrapped
    unless new_content.include?('trix-content')
      new_content = %(<div class="trix-content">\n  #{new_content}\n</div>)
    end

    puts ""
    puts "Preview (first 500 chars):"
    puts "-" * 80
    puts new_content[0..500]
    puts "-" * 80
    puts ""

    print "Save this content to PSP-9? (yes/no): "
    confirm = gets.chomp.downcase

    if confirm == 'yes' || confirm == 'y'
      defect.content = new_content
      if defect.save(validate: false)
        puts "✅ Successfully updated PSP-9 description"
        puts "  New length: #{defect.content.length} characters"
      else
        puts "❌ Failed to save: #{defect.errors.full_messages.join(', ')}"
      end
    else
      puts "❌ Update cancelled"
    end
  end
end

puts ""
puts "Current database content for PSP-9:"
puts "=" * 80
puts defect.content
puts "=" * 80

