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

def fetch_jira_issue(key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{key}"
  uri = URI.parse(url)
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  
  response = http.request(request)
  return nil unless response.is_a?(Net::HTTPSuccess)
  
  JSON.parse(response.body)
end

issue_key = 'ISP-1289'
puts "--- Inspecting Jira Data for #{issue_key} ---"
issue = fetch_jira_issue(issue_key)

if issue
  attachments = issue['fields']['attachment'] || []
  puts "Found #{attachments.length} attachments in Jira:"
  attachments.each do |att|
    puts "  Filename: #{att['filename']}"
    puts "  Size: #{att['size']} bytes"
    puts "  Created: #{att['created']}"
    puts "  ID: #{att['id']}"
    puts "  ---"
  end
else
  puts "Could not fetch issue from Jira"
end

puts "\n--- Inspecting Local Data for #{issue_key} ---"
defect = Defect.find_by(defect_unique: issue_key)

if defect
  puts "Found defect in DB (ID: #{defect.id})"
  puts "Attachments: #{defect.attachments.count}"
  defect.attachments.each do |att|
    puts "  Filename: #{att.filename}"
    puts "  Size: #{att.byte_size} bytes"
    puts "  Created At: #{att.created_at}"
    puts "  Blob Created At: #{att.blob.created_at}"
    puts "  ID: #{att.id}"
    puts "  ---"
  end
else
  puts "Defect not found in DB"
end
