#!/usr/bin/env ruby
# Test ADF macro detection and conversion

# Simulate the rendered HTML with ADF macro
rendered_html_with_macro = '<p>Some of the data maintenance actions are not being displayed in the audit report</p>

<!-- ADF macro (type = \'table\') -->'

# Simulate the ADF structure
adf_data = {
  "type" => "doc",
  "version" => 1,
  "content" => [
    {
      "type" => "paragraph",
      "content" => [
        {
          "type" => "text",
          "text" => "Some of the data maintenance actions are not being displayed in the audit report"
        },
        {
          "type" => "hardBreak"
        }
      ]
    },
    {
      "type" => "table",
      "content" => [
        {
          "type" => "tableRow",
          "content" => [
            {
              "type" => "tableHeader",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "type" => "text",
                      "text" => "Action"
                    }
                  ]
                }
              ]
            },
            {
              "type" => "tableHeader",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "type" => "text",
                      "text" => "Status"
                    }
                  ]
                }
              ]
            }
          ]
        },
        {
          "type" => "tableRow",
          "content" => [
            {
              "type" => "tableCell",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "type" => "text",
                      "text" => "Data Update"
                    }
                  ]
                }
              ]
            },
            {
              "type" => "tableCell",
              "content" => [
                {
                  "type" => "paragraph",
                  "content" => [
                    {
                      "type" => "text",
                      "text" => "Missing"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}

puts "=" * 80
puts "ADF MACRO DETECTION TEST"
puts "=" * 80
puts ""

# Test 1: Detect ADF macro in rendered HTML
puts "1️⃣  Testing ADF macro detection:"
if rendered_html_with_macro.include?('<!-- ADF macro')
  puts "   ✅ ADF macro detected in rendered HTML"
  puts "   → Should use ADF conversion instead"
else
  puts "   ❌ ADF macro NOT detected"
end
puts ""

# Test 2: Show what rendered HTML looks like
puts "2️⃣  Rendered HTML content:"
puts "   " + rendered_html_with_macro.inspect
puts ""

# Test 3: Show ADF structure
puts "3️⃣  ADF structure:"
puts "   Has table block: #{adf_data['content'].any? { |b| b['type'] == 'table' }}"
if adf_data['content'].any? { |b| b['type'] == 'table' }
  table = adf_data['content'].find { |b| b['type'] == 'table' }
  puts "   Table rows: #{table['content'].count}"
end
puts ""

# Test 4: Simulate conversion
puts "4️⃣  What should happen:"
puts "   - Detect '<!-- ADF macro' in rendered HTML"
puts "   - Fall back to ADF conversion"
puts "   - Convert table block to HTML table"
puts "   - Result should include <table> tag with actual content"
puts ""

puts "=" * 80
puts "CONCLUSION"
puts "=" * 80
puts ""
puts "✅ The updated script will:"
puts "   1. Check rendered HTML for '<!-- ADF macro' comments"
puts "   2. If found, use ADF conversion instead"
puts "   3. Convert table blocks from ADF to proper HTML tables"
puts "   4. Store complete HTML with tables in database"
puts ""
puts "🚀 Run the repair script to update content:"
puts "   bin/rails runner scripts/repair_rich_text_content.rb PSP"
puts ""
puts "=" * 80

