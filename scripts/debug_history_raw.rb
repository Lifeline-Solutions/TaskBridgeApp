#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'
require 'base64'
require 'yaml'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_DOMAIN = 'craftsilicon.atlassian.net'.freeze
EMAIL = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

def auth_header
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
end

# Test JQL Search
jql = 'key = GBCBS-3303'
jql_enc = URI.encode_www_form_component(jql)
url = URI("https://#{JIRA_DOMAIN}/rest/api/3/search?jql=#{jql_enc}&maxResults=1")
http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true
req = Net::HTTP::Get.new(url, auth_header)
res = http.request(req)

if res.is_a?(Net::HTTPSuccess)
  data = JSON.parse(res.body)
  puts "Search Success! Found: #{data['total']}"
else
  puts "Search Error: #{res.code} #{res.message}"
end
