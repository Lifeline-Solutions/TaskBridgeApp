#!/usr/bin/env ruby
# Quick script to fetch a single Jira issue and save the response

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

# Load configuration
config_path = File.join(__dir__, '..', 'config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).transform_keys(&:to_sym)

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

issue_key = ARGV[0] || 'PSP-9'

url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
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

response = http.request(request)

if response.is_a?(Net::HTTPSuccess)
  data = JSON.parse(response.body)
  output_file = File.join(__dir__, '..', 'tmp', "jira_response_#{issue_key.gsub('-', '_')}.json")
  File.write(output_file, JSON.pretty_generate(data))
  puts "✅ Saved to: #{output_file}"

  # Show description field info
  desc_field = data.dig('fields', 'description')
  puts "\nDescription field type: #{desc_field.class}"
  if desc_field.is_a?(Hash)
    puts "Description keys: #{desc_field.keys.join(', ')}"
    if desc_field['content']
      puts "Content blocks: #{desc_field['content'].length}"
      desc_field['content'].each_with_index do |block, i|
        puts "  Block #{i}: #{block['type']}"
      end
    end
  end
else
  puts "❌ Failed: #{response.code} #{response.message}"
  puts response.body
end
