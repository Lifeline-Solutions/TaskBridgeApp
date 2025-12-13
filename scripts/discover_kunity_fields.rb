#!/usr/bin/env ruby
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

puts "Fetching all fields..."
url = "#{JIRA_BASE_URL}/rest/api/3/field"
uri = URI.parse(url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

response = http.request(request)
if response.is_a?(Net::HTTPSuccess)
  fields = JSON.parse(response.body)
  puts "Found #{fields.count} fields. Searching for 'component'..."
  
  fields.each do |field|
    name = field['name']
    id = field['id']
    if name.downcase.include?('component') || name.downcase.include?('kunity') || name.downcase.include?('k-unity')
      puts "MATCH: #{name} (ID: #{id})"
    end
  end
else
  puts "Error: #{response.code} #{response.body}"
end
