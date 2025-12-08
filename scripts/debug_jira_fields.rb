#!/usr/bin/env ruby
# Quick script to check Jira custom field values for a specific issue

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

# Get issue key from command line
issue_key = ARGV[0] || 'ISP-1382'

# Load config
config_path = Rails.root.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL') { CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net' }
JIRA_API_USER = ENV.fetch('JIRA_API_USER') { CONFIG[:jira_api_user] }
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

puts '=' * 80
puts "Fetching Jira issue: #{issue_key}"
puts '=' * 80

# Fetch issue
url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
uri = URI.parse(url)

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 60

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

response = http.request(request)

unless response.is_a?(Net::HTTPSuccess)
  puts "❌ Failed to fetch: #{response.code} #{response.message}"
  exit 1
end

data = JSON.parse(response.body)

puts "\n✓ Issue fetched successfully"
puts "\nKey: #{data['key']}"
puts "Summary: #{data['fields']['summary']}"

puts "\n#{'=' * 80}"
puts 'CUSTOM FIELDS WITH VALUES:'
puts '=' * 80

data['fields'].each do |key, value|
  next unless key.start_with?('customfield_')
  next if value.nil?
  next if value.respond_to?(:empty?) && value.empty?

  puts "\n#{key}:"
  puts "  Value: #{value.inspect}"

  # Try to extract field name
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  field_response = http.request(request)
  next unless field_response.is_a?(Net::HTTPSuccess)

  fields = JSON.parse(field_response.body)
  field_def = fields.find { |f| f['id'] == key }
  puts "  Name: #{field_def['name']}" if field_def
end

puts "\n#{'=' * 80}"
puts 'TARGET FIELDS:'
puts '=' * 80

module_field = 'customfield_10465'
submodule_field = 'customfield_10464'

puts "\nModule Field (#{module_field}):"
puts "  Value: #{data['fields'][module_field].inspect}"

puts "\nSubmodule Field (#{submodule_field}):"
puts "  Value: #{data['fields'][submodule_field].inspect}"

puts "\n#{'=' * 80}"
