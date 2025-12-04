#!/usr/bin/env ruby
# Enhanced test to see FULL ADF response from Jira

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

TEST_ISSUE_KEY = ARGV[0] || 'PSP-9'
SAVE_TO_FILE = ENV['SAVE_RESPONSE'].to_s.downcase == 'true'

puts "=" * 100
puts "COMPREHENSIVE JIRA CONTENT ANALYSIS FOR: #{TEST_ISSUE_KEY}"
puts "=" * 100
puts ""

# Fetch issue with ALL expansion options
url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{TEST_ISSUE_KEY}"
uri = URI.parse(url)
uri.query = URI.encode_www_form({
  expand: 'renderedFields,names,schema,operations,editmeta,changelog,versionedRepresentations',
  fields: '*all'
})

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 120

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

puts "📡 Fetching from Jira API..."
response = http.request(request)

unless response.is_a?(Net::HTTPSuccess)
  puts "❌ Failed: #{response.code} #{response.message}"
  exit 1
end

data = JSON.parse(response.body)

puts "✅ Successfully fetched issue"

# Save complete response to file if requested
if SAVE_TO_FILE
  filename = "tmp/jira_response_#{TEST_ISSUE_KEY.gsub('-', '_')}.json"
  File.write(filename, JSON.pretty_generate(data))
  puts "💾 Complete response saved to: #{filename}"
end

puts ""

# 1. RENDERED HTML
puts "=" * 100
puts "1️⃣  RENDERED HTML DESCRIPTION (what Jira pre-renders)"
puts "=" * 100
rendered_desc = data.dig('renderedFields', 'description')

if rendered_desc
  puts rendered_desc
  puts ""
  puts "📊 Analysis:"
  puts "  Length: #{rendered_desc.length} characters"
  puts "  Has <table>: #{rendered_desc.include?('<table')}"
  puts "  Has <!-- ADF macro: #{rendered_desc.include?('<!-- ADF macro')}"
  puts "  Has <p>: #{rendered_desc.include?('<p>')}"
  puts "  Has <ul> or <ol>: #{rendered_desc.include?('<ul>') || rendered_desc.include?('<ol>')}"
else
  puts "❌ No rendered description available"
end
puts ""

# 2. RAW ADF - COMPLETE STRUCTURE
puts "=" * 100
puts "2️⃣  RAW ADF DESCRIPTION (complete structure)"
puts "=" * 100
raw_desc = data.dig('fields', 'description')

if raw_desc
  puts JSON.pretty_generate(raw_desc)
  puts ""

  if raw_desc.is_a?(Hash) && raw_desc['content']
    content_blocks = raw_desc['content']

    puts "📊 ADF Structure Analysis:"
    puts "  Total blocks: #{content_blocks.length}"

    content_blocks.each_with_index do |block, idx|
      block_type = block['type']
      puts "  Block #{idx + 1}: #{block_type}"

      case block_type
      when 'table'
        rows = block['content']&.length || 0
        puts "    → Table with #{rows} row(s)"

        if rows > 0
          # Analyze table structure
          first_row = block['content'][0]
          if first_row && first_row['content']
            cells = first_row['content'].length
            puts "    → First row has #{cells} cell(s)"

            first_row['content'].each_with_index do |cell, cell_idx|
              cell_type = cell['type']
              cell_content = cell['content']
              text = if cell_content && cell_content[0] && cell_content[0]['content']
                cell_content[0]['content'].map { |c| c['text'] }.join(' ')
              else
                '(empty)'
              end
              puts "      Cell #{cell_idx + 1} (#{cell_type}): #{text[0..50]}"
            end
          end
        end

      when 'paragraph'
        text_nodes = block['content']&.select { |c| c['type'] == 'text' } || []
        text_preview = text_nodes.map { |t| t['text'] }.join(' ')[0..100]
        puts "    → Text: #{text_preview}#{'...' if text_preview.length >= 100}"

      when 'bulletList', 'orderedList', 'bullet_list', 'ordered_list'
        items = block['content']&.length || 0
        puts "    → List with #{items} item(s)"
      end
    end
  end
else
  puts "❌ No raw ADF description available"
end
puts ""

# 3. CONVERSION TEST
puts "=" * 100
puts "3️⃣  ADF TO HTML CONVERSION TEST"
puts "=" * 100

if raw_desc && raw_desc.is_a?(Hash)
  # Load the conversion functions from repair script
  load 'scripts/repair_rich_text_content.rb'

  converted_html = convert_adf_to_html(raw_desc['content'] || [])

  puts "Converted HTML:"
  puts "-" * 100
  puts converted_html
  puts "-" * 100
  puts ""
  puts "📊 Conversion Analysis:"
  puts "  Length: #{converted_html.length} characters"
  puts "  Has <table>: #{converted_html.include?('<table')}"
  puts "  Has <p>: #{converted_html.include?('<p>')}"
  puts "  Has <ul> or <ol>: #{converted_html.include?('<ul>') || converted_html.include?('<ol>')}"

  if converted_html.include?('<table')
    table_count = converted_html.scan(/<table/).length
    puts "  Number of tables: #{table_count}"
  end
else
  puts "⚠️  Cannot convert - no valid ADF data"
end
puts ""

# 4. RECOMMENDATION
puts "=" * 100
puts "4️⃣  RECOMMENDATION"
puts "=" * 100

has_adf_macro = rendered_desc && rendered_desc.include?('<!-- ADF macro')
has_table_in_adf = raw_desc && raw_desc['content']&.any? { |b| b['type'] == 'table' }

if has_adf_macro
  puts "⚠️  ISSUE DETECTED: Rendered HTML contains ADF macro placeholders"
  puts ""
  puts "Action taken by repair script:"
  puts "  1. Detect '<!-- ADF macro' in rendered HTML"
  puts "  2. Fall back to ADF conversion"

  if has_table_in_adf
    puts "  3. ✅ Convert table from ADF to HTML"
    puts "  4. ✅ Store complete HTML in database"
    puts ""
    puts "✅ RESULT: Table content WILL be captured"
  else
    puts "  3. ⚠️  WARNING: No table found in ADF either!"
    puts ""
    puts "❌ ISSUE: Table is missing from Jira's API response entirely"
    puts "   This means:"
    puts "   - The table might not exist in Jira"
    puts "   - Or Jira API is not returning complete data"
    puts "   - Need to verify in Jira web interface"
  end
else
  if rendered_desc && rendered_desc.include?('<table')
    puts "✅ GOOD: Rendered HTML has table - will use it directly"
  elsif has_table_in_adf
    puts "✅ GOOD: No rendered HTML but ADF has table - will convert"
  else
    puts "ℹ️  INFO: No table detected in this issue"
  end
end

puts ""
puts "=" * 100

