#!/usr/bin/env ruby
# Quick diagnostic for PSP-9 to see what Jira is actually returning

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

ISSUE_KEY = ARGV[0] || 'PSP-9'

puts "=" * 100
puts "QUICK DIAGNOSTIC FOR #{ISSUE_KEY}"
puts "=" * 100
puts ""

# Fetch issue
url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{ISSUE_KEY}"
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

puts "Fetching from Jira..."
response = http.request(request)

unless response.is_a?(Net::HTTPSuccess)
  puts "❌ Failed: #{response.code} #{response.message}"
  exit 1
end

data = JSON.parse(response.body)

# Save to file
require 'fileutils'
FileUtils.mkdir_p('tmp')
filename = "tmp/jira_#{ISSUE_KEY.gsub('-', '_')}_diagnostic.json"
File.write(filename, JSON.pretty_generate(data))
puts "✅ Saved full response to: #{filename}"
puts ""

# Check rendered HTML
puts "1️⃣  RENDERED HTML"
puts "-" * 100
rendered = data.dig('renderedFields', 'description')
if rendered
  puts rendered
  puts ""
  puts "Length: #{rendered.length}"
  puts "Has <table>: #{rendered.include?('<table')}"
  puts "Has ADF macro: #{rendered.include?('<!-- ADF macro')}"
else
  puts "❌ No rendered description"
end
puts ""

# Check raw description field
puts "2️⃣  RAW DESCRIPTION FIELD"
puts "-" * 100
desc = data.dig('fields', 'description')
if desc.nil?
  puts "❌ Description field is NULL"
elsif desc.is_a?(String)
  puts "Description is a STRING:"
  puts desc
elsif desc.is_a?(Hash)
  puts "Description is a HASH (ADF format):"
  puts "Keys: #{desc.keys.join(', ')}"

  if desc['content']
    puts "Content array length: #{desc['content'].length}"
    puts "Content block types: #{desc['content'].map { |b| b['type'] }.join(', ')}"
    puts ""
    puts "Full ADF structure:"
    puts JSON.pretty_generate(desc)
  else
    puts "❌ No 'content' key in description hash"
    puts "Full description:"
    puts JSON.pretty_generate(desc)
  end
else
  puts "❌ Description is unknown type: #{desc.class}"
  puts desc.inspect
end
puts ""

# Summary
puts "=" * 100
puts "SUMMARY"
puts "=" * 100
if desc.nil?
  puts "❌ PROBLEM: Description field is NULL/missing in Jira"
  puts "   → The issue might not have a description"
  puts "   → Or permissions issue with Jira API"
elsif desc.is_a?(String) && desc.blank?
  puts "❌ PROBLEM: Description is empty string"
  puts "   → The issue has no description in Jira"
elsif desc.is_a?(Hash) && (!desc['content'] || desc['content'].empty?)
  puts "❌ PROBLEM: Description ADF has no content"
  puts "   → The description exists but is empty"
elsif desc.is_a?(Hash) && desc['content']
  has_table = desc['content'].any? { |b| b['type'] == 'table' }
  puts "✅ Description has ADF content with #{desc['content'].length} block(s)"
  puts "   Has table: #{has_table}"
  if has_table
    puts "   → Table exists in ADF!"
    puts "   → Check conversion function"
  else
    puts "   → No table in description"
  end
else
  puts "⚠️  Unexpected format"
end
puts ""
puts "Full response saved to: #{filename}"
puts "Run: cat #{filename} | jq '.fields.description'"
puts ""
puts "=" * 100

