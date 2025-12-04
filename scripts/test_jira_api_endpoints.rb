#!/usr/bin/env ruby
# Test different Jira API endpoints to find complete table data

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

def fetch_jira(url_path, params = {})
  url = "#{JIRA_BASE_URL}#{url_path}"
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
rescue StandardError => e
  puts "  Error: #{e.message}"
  nil
end

puts '=' * 100
puts "TESTING DIFFERENT JIRA API ENDPOINTS FOR: #{TEST_ISSUE_KEY}"
puts '=' * 100
puts ''

# Method 1: Standard API v3 with renderedFields
puts '1️⃣  API v3 with renderedFields'
puts '-' * 100
data1 = fetch_jira("/rest/api/3/issue/#{TEST_ISSUE_KEY}", {
                     expand: 'renderedFields',
                     fields: 'description'
                   })

if data1
  rendered = data1.dig('renderedFields', 'description')
  puts "Rendered HTML length: #{rendered&.length || 0}"
  puts "Has table: #{rendered&.include?('<table') || false}"
  puts "Has ADF macro: #{rendered&.include?('<!-- ADF macro') || false}"
else
  puts 'Failed to fetch'
end
puts ''

# Method 2: API v3 with regular fields (ADF)
puts '2️⃣  API v3 with ADF fields'
puts '-' * 100
data2 = fetch_jira("/rest/api/3/issue/#{TEST_ISSUE_KEY}", {
                     fields: 'description'
                   })

if data2
  adf = data2.dig('fields', 'description')
  if adf && adf['content']
    blocks = adf['content'].map { |b| b['type'] }.join(', ')
    puts "ADF blocks: #{blocks}"
    has_table = adf['content'].any? { |b| b['type'] == 'table' }
    puts "Has table block: #{has_table}"

    if has_table
      table_block = adf['content'].find { |b| b['type'] == 'table' }
      puts "Table rows: #{table_block['content']&.length || 0}"
    end
  end
else
  puts 'Failed to fetch'
end
puts ''

# Method 3: Try API v2 (older but might have different rendering)
puts '3️⃣  API v2 (older endpoint)'
puts '-' * 100
data3 = fetch_jira("/rest/api/2/issue/#{TEST_ISSUE_KEY}", {
                     expand: 'renderedFields',
                     fields: 'description'
                   })

if data3
  rendered = data3.dig('renderedFields', 'description')
  adf = data3.dig('fields', 'description')

  if rendered.is_a?(String)
    puts "Rendered HTML length: #{rendered.length}"
    puts "Has table: #{rendered.include?('<table')}"
  elsif adf
    puts 'ADF format (v2 returns ADF)'
    puts "ADF blocks: #{adf['content']&.map { |b| b['type'] }&.join(', ') || 'none'}"
  end
else
  puts 'Failed to fetch'
end
puts ''

# Method 4: Try versionedRepresentations
puts '4️⃣  Versioned Representations'
puts '-' * 100
data4 = fetch_jira("/rest/api/3/issue/#{TEST_ISSUE_KEY}", {
                     expand: 'versionedRepresentations',
                     fields: 'description'
                   })

if data4
  versioned = data4.dig('versionedRepresentations', 'description')
  if versioned
    puts "Available formats: #{versioned.keys.join(', ')}"

    # Try different format variations
    %w[storage view editor atlassian_document_format wiki].each do |format|
      next unless versioned[format]

      content = versioned[format]
      puts "\n  #{format.upcase}:"
      if content.is_a?(String)
        puts "    Type: String, Length: #{content.length}"
        puts "    Has table: #{content.include?('<table') || content.include?('table')}"
        puts "    Preview: #{content[0..200]}"
      elsif content.is_a?(Hash)
        puts '    Type: Hash'
        puts "    Keys: #{content.keys.join(', ')}"
        if content['content']
          blocks = content['content'].map do |b|
            b['type']
          rescue StandardError
            'unknown'
          end.join(', ')
          puts "    Blocks: #{blocks}"
        end
      end
    end
  else
    puts 'No versioned representations available'
  end
else
  puts 'Failed to fetch'
end
puts ''

# Method 5: Direct HTML rendering endpoint (if exists)
puts '5️⃣  Direct Rendering Endpoint'
puts '-' * 100
data5 = fetch_jira("/rest/api/3/issue/#{TEST_ISSUE_KEY}", {
                     expand: 'renderedFields,versionedRepresentations',
                     fields: '*all'
                   })

if data5
  # Check all possible locations for rendered content
  locations = [
    %w[renderedFields description],
    %w[fields description rendered],
    %w[versionedRepresentations description storage],
    %w[versionedRepresentations description view]
  ]

  locations.each do |path|
    content = data5.dig(*path)
    next unless content

    puts "Found at: #{path.join(' → ')}"
    if content.is_a?(String)
      puts "  Length: #{content.length}"
      puts "  Has <table>: #{content.include?('<table')}"
      puts "  Has ADF macro: #{content.include?('<!-- ADF macro')}"
      puts "  Preview: #{content[0..200]}"
    end
    puts ''
  end
end
puts ''

puts '=' * 100
puts 'CONCLUSION'
puts '=' * 100
puts ''
puts 'If NO endpoint returns actual table HTML/data:'
puts '  → The table data is truly missing from Jira API'
puts '  → Possible reasons:'
puts '    1. Table was created with unsupported Jira markup'
puts "    2. Table is corrupted in Jira's database"
puts "    3. API permissions don't include full content"
puts "    4. Need to use Jira's internal storage format"
puts ''
puts 'Next step: Check the issue in Jira web UI to confirm table exists'
puts ''
puts '=' * 100
