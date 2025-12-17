require 'net/http'
require 'json'
require 'uri'
require 'base64'
require 'yaml'

# Config
APP_ROOT = File.expand_path('..', __dir__)
config_path = File.join(APP_ROOT, 'config', 'jira_import.yml')
CONFIG = File.exist?(config_path) ? YAML.load_file(config_path) : {}

JIRA_BASE_URL = "https://craftsilicon.atlassian.net"
EMAIL = ENV['JIRA_API_USER'] || CONFIG['jira_api_user']
API_TOKEN = ENV['JIRA_API_TOKEN'] || CONFIG['jira_api_token']

def fetch_issue(key)
  uri = URI("#{JIRA_BASE_URL}/rest/api/3/issue/#{key}")
  query = { fields: %w[description comment].join(',') }
  uri.query = URI.encode_www_form(query)
  
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  headers = { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  res = http.request(Net::HTTP::Get.new(uri, headers))
  puts "Code: #{res.code}"
  puts res.body
end

def search_issue(jql)
  uri = URI("#{JIRA_BASE_URL}/rest/api/3/search")
  
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  headers = { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  req = Net::HTTP::Post.new(uri, headers)
  req.body = { jql: jql, fields: %w[description comment] }.to_json
  
  res = http.request(req)
  puts "Code: #{res.code}"
  puts res.body
end

puts "--- KCBL-13 ---"
fetch_issue('KCBL-13')
puts "\n--- SEARCH 'Branch Id popup' ---"
search_issue('text ~ "Branch Id popup"')

