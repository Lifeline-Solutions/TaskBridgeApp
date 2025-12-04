#!/usr/bin/env ruby
# 🔍 RUN THIS NOW: Diagnose PSP-9 (or any issue with missing tables)

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

def fetch_issue(params = {})
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{TEST_ISSUE_KEY}"
  uri = URI.parse(url)
  uri.query = URI.encode_www_form(params) if params.any?

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)
  response.is_a?(Net::HTTPSuccess) ? JSON.parse(response.body) : nil
end

puts '=' * 100
puts "🔍 DIAGNOSING MISSING TABLE DATA FOR: #{TEST_ISSUE_KEY}"
puts '=' * 100
puts ''

# STEP 1: Check rendered HTML
puts "STEP 1: Checking Jira's Rendered HTML"
puts '-' * 100

data = fetch_issue(expand: 'renderedFields', fields: 'description')

if data
  rendered = data.dig('renderedFields', 'description')

  if rendered
    has_table_tag = rendered.include?('<table')
    has_adf_macro = rendered.include?('<!-- ADF macro')

    puts '✅ Rendered HTML retrieved'
    puts "   Length: #{rendered.length} characters"
    puts "   Has <table> tag: #{has_table_tag}"
    puts "   Has ADF macro comment: #{has_adf_macro}"

    puts ''
    if has_table_tag
      puts '✅ GOOD NEWS: Rendered HTML contains table!'
      puts '   → The repair script WILL capture this table'
      puts ''
      puts 'Preview of table HTML:'
      table_match = rendered.match(%r{<table.*?</table>}m)
      puts table_match[0][0..500] if table_match
    elsif has_adf_macro
      puts '⚠️  ISSUE: Rendered HTML has ADF macro placeholder'
      puts '   → Jira is NOT rendering the table to HTML'
      puts '   → Need to check raw ADF data...'
    else
      puts 'ℹ️  No table found in rendered HTML'
    end
  else
    puts '❌ No rendered HTML available'
  end
else
  puts '❌ Failed to fetch issue'
  exit 1
end

puts ''
puts ''

# STEP 2: Check raw ADF
puts 'STEP 2: Checking Raw ADF (Atlassian Document Format)'
puts '-' * 100

adf = data.dig('fields', 'description')

if adf.is_a?(Hash) && adf['content']
  content_blocks = adf['content']
  table_blocks = content_blocks.select { |b| b['type'] == 'table' }

  puts '✅ ADF data retrieved'
  puts "   Total content blocks: #{content_blocks.length}"
  puts "   Block types: #{content_blocks.map { |b| b['type'] }.join(', ')}"
  puts "   Table blocks found: #{table_blocks.length}"

  puts ''
  if table_blocks.any?
    puts "✅ FOUND #{table_blocks.length} TABLE(S) IN ADF!"

    table_blocks.each_with_index do |table, idx|
      puts ''
      puts "Table #{idx + 1}:"
      rows = table['content'] || []
      puts "  Rows: #{rows.length}"

      if rows.empty?
        puts '  ⚠️  WARNING: Table has no rows (empty table block)'
        puts '  → This means the table structure exists but has no data'
        puts '  → Possible causes:'
        puts '     - Table was created but never filled in'
        puts '     - Data was deleted'
        puts '     - Jira API limitation'
      else
        puts "  ✅ Table has #{rows.length} row(s) with data!"

        # Analyze first row
        first_row = rows[0]
        if first_row && first_row['content']
          cells = first_row['content']
          puts "  First row cells: #{cells.length}"

          cells.each_with_index do |cell, cell_idx|
            cell_type = cell['type']
            cell_content = cell['content']

            # Extract text from cell
            text = if cell_content && cell_content[0]
                     if cell_content[0]['type'] == 'paragraph' && cell_content[0]['content']
                       cell_content[0]['content'].map do |c|
                         c['text']
                       rescue StandardError
                         ''
                       end.join(' ')
                     else
                       begin
                         cell_content[0]['text']
                       rescue StandardError
                         '(complex content)'
                       end
                     end
                   else
                     '(empty)'
                   end

            puts "    Cell #{cell_idx + 1} (#{cell_type}): #{text[0..60]}#{'...' if text.length > 60}"
          end
        end
      end

      # Show full JSON structure
      puts ''
      puts 'Full JSON structure:'
      puts JSON.pretty_generate(table)[0..1000]
      puts '...' if JSON.pretty_generate(table).length > 1000
    end
  else
    puts '❌ NO TABLE BLOCKS FOUND IN ADF'
    puts "   → The table data is completely missing from Jira's API response"
  end
else
  puts '❌ No ADF data available or invalid format'
end

puts ''
puts ''

# STEP 3: Summary and Recommendations
puts '=' * 100
puts '📊 SUMMARY & RECOMMENDATIONS'
puts '=' * 100
puts ''

rendered_has_table = data.dig('renderedFields', 'description')&.include?('<table')
data.dig('renderedFields', 'description')&.include?('<!-- ADF macro')
adf_has_table = adf && adf['content']&.any? { |b| b['type'] == 'table' }
adf_table_empty = false

if adf_has_table
  table_block = adf['content'].find { |b| b['type'] == 'table' }
  adf_table_empty = table_block && (table_block['content'] || []).empty?
end

if rendered_has_table
  puts '✅ STATUS: TABLE IS FULLY AVAILABLE'
  puts ''
  puts "The table exists in Jira's rendered HTML and will be imported correctly."
  puts ''
  puts '✅ Action: Run the repair script normally'
  puts '   bin/rails runner scripts/repair_rich_text_content.rb PSP'

elsif adf_has_table && !adf_table_empty
  puts '✅ STATUS: TABLE DATA IS IN ADF (needs conversion)'
  puts ''
  puts 'Rendered HTML has ADF macro, but complete table data exists in ADF format.'
  puts 'The repair script will detect the macro and convert from ADF.'
  puts ''
  puts '✅ Action: Run the repair script with debug mode'
  puts '   DEBUG=true bin/rails runner scripts/repair_rich_text_content.rb PSP'
  puts ''
  puts 'You should see:'
  puts '   [Rendered HTML has ADF macros - using ADF conversion instead]'
  puts '   [ADF blocks: paragraph, table, ...]'

elsif adf_has_table && adf_table_empty
  puts '⚠️  STATUS: TABLE EXISTS BUT IS EMPTY'
  puts ''
  puts 'A table block exists in ADF but has no rows/data.'
  puts 'This could mean:'
  puts '  - Table was created but never filled in'
  puts '  - Data was deleted from Jira'
  puts '  - Jira API returned incomplete data'
  puts ''
  puts '⚠️  Action: Manual verification needed'
  puts '   1. Check issue in Jira web UI:'
  puts "      #{JIRA_BASE_URL}/browse/#{TEST_ISSUE_KEY}"
  puts '   2. If table is visible there, contact Atlassian support'
  puts '   3. If table is empty there too, nothing to import'

else
  puts '❌ STATUS: TABLE DATA IS MISSING'
  puts ''
  puts 'No table found in either rendered HTML or ADF data.'
  puts "The table either doesn't exist or Jira API cannot retrieve it."
  puts ''
  puts '❌ Action Required:'
  puts '   1. Verify table exists in Jira web UI:'
  puts "      #{JIRA_BASE_URL}/browse/#{TEST_ISSUE_KEY}"
  puts ''
  puts '   2. If table IS visible in web UI:'
  puts '      → File support ticket with Atlassian'
  puts '      → API is not returning complete data'
  puts '      → May need alternative export method'
  puts ''
  puts '   3. If table is NOT visible in web UI:'
  puts '      → Table was deleted or never existed'
  puts '      → Nothing to import'
  puts ''
  puts '   4. Alternative: Export issue as JSON/XML from Jira'
  puts "      → Use Jira's export feature"
  puts '      → Parse exported file directly'
end

puts ''
puts '=' * 100
puts ''
puts 'Next Steps:'
puts '  1. Review the analysis above'
puts "  2. Check #{JIRA_BASE_URL}/browse/#{TEST_ISSUE_KEY} in browser"
puts '  3. Run appropriate action based on status'
puts ''
puts 'For more details, see: DIAGNOSE_MISSING_TABLES.md'
puts ''
puts '=' * 100
