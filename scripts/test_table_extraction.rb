#!/usr/bin/env ruby
# Test script to verify table extraction from Jira

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

# Test with an issue that has a table (you can change this)
TEST_ISSUE_KEY = ARGV[0] || 'KCBL-1114'

puts "Testing table extraction for #{TEST_ISSUE_KEY}"
puts '=' * 80

# Fetch issue
url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{TEST_ISSUE_KEY}"
uri = URI.parse(url)
uri.query = URI.encode_www_form({
                                  expand: 'renderedFields',
                                  fields: 'description'
                                })

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 120

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

response = http.request(request)

if response.is_a?(Net::HTTPSuccess)
  data = JSON.parse(response.body)

  # Check rendered HTML
  rendered_desc = data.dig('renderedFields', 'description')

  puts "\n📄 RENDERED HTML DESCRIPTION:"
  puts '-' * 80
  if rendered_desc
    puts rendered_desc
    puts '-' * 80

    if rendered_desc.include?('<table')
      puts "\n✅ TABLE FOUND in rendered HTML!"
      puts 'Table preview:'
      table_match = rendered_desc.match(%r{<table.*?</table>}m)
      puts table_match[0] if table_match
    else
      puts "\n⚠️  NO TABLE found in rendered HTML"
    end
  else
    puts 'No rendered description available'
  end

  # Check raw ADF
  raw_desc = data.dig('fields', 'description')
  puts "\n📋 RAW ADF DESCRIPTION:"
  puts '-' * 80
  puts JSON.pretty_generate(raw_desc)
  puts '-' * 80

  if raw_desc.is_a?(Hash)
    content = raw_desc['content'] || []
    table_blocks = content.select { |block| block['type'] == 'table' }

    if table_blocks.any?
      puts "\n✅ #{table_blocks.count} TABLE BLOCK(S) found in ADF!"
      table_blocks.each_with_index do |table, idx|
        puts "\nTable #{idx + 1}:"
        puts JSON.pretty_generate(table)
      end
    else
      puts "\n⚠️  NO TABLE blocks found in ADF"
    end
  end

else
  puts "❌ Failed to fetch issue: #{response.code} #{response.message}"
end

puts "\n#{'=' * 80}"
