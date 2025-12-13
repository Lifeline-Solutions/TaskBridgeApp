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

defect_unique = 'KUP-335'

puts "Fetching #{defect_unique}..."
url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{defect_unique}"
uri = URI.parse(url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 10 # 10 seconds timeout

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

begin
  response = http.request(request)
  puts "Response Code: #{response.code}"
  
  if response.is_a?(Net::HTTPSuccess)
    issue = JSON.parse(response.body)
    fields = issue['fields'] || {}

    target_field_id = 'customfield_10152'
    puts "Components (K-Unity) Field Raw: #{fields[target_field_id].inspect}"
    
    val = fields[target_field_id]
    if val.is_a?(Hash) && val['value']
        puts "Value: #{val['value']}"
    elsif val.is_a?(Array) && val.first.is_a?(Hash) && val.first['value']
        puts "Value (from array): #{val.first['value']}"
    else
        puts "Value: #{val}"
    end
  else
    puts "Error body: #{response.body}"
  end
rescue => e
  puts "Exception: #{e.message}"
end
