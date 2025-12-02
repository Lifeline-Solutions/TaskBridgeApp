#!/usr/bin/env ruby
# Quick database check for PSP-9

require_relative '../config/environment'

puts "=" * 80
puts "PSP-9 Database Status Check"
puts "=" * 80
puts ""

begin
  defect = Defect.find_by(defect_unique: 'PSP-9')

  if defect.nil?
    puts "❌ Defect PSP-9 not found in database"
    exit 1
  end

  puts "✓ Defect found: PSP-9"
  puts "  ID: #{defect.id}"
  puts "  Summary: #{defect.summary}"
  puts "  Status: #{defect.defect_status&.status_name || 'N/A'}"
  puts "  Product: #{defect.product&.product_name || 'N/A'}"
  puts ""

  content = defect.content.to_s
  puts "Description/Content:"
  puts "  Length: #{content.length} characters"
  puts "  Has <table> tag: #{content.include?('<table')}"
  puts "  Has <div class=\"trix-content\">: #{content.include?('trix-content')}"
  puts "  Has <p> tags: #{content.include?('<p')}"
  puts ""

  if content.include?('<table')
    # Count table rows
    row_count = content.scan(/<tr[^>]*>/).length
    header_count = content.scan(/<th[^>]*>/).length
    cell_count = content.scan(/<td[^>]*>/).length
    puts "  Table structure:"
    puts "    - Rows: #{row_count}"
    puts "    - Headers: #{header_count}"
    puts "    - Cells: #{cell_count}"
    puts ""
  end

  puts "Full content:"
  puts "-" * 80
  puts content
  puts "-" * 80
  puts ""

  # Save to file for inspection
  output_file = 'tmp/psp9_current_content.html'
  File.write(output_file, content)
  puts "✓ Saved current content to: #{output_file}"

rescue => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

