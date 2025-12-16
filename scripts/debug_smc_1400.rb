# Configuration
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_DOMAIN = 'craftsilicon.atlassian.net'
# Use config or fallbacks matching debug script
EMAIL = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] } 

def auth_header
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
end

require 'net/http'
require 'json'
require 'uri'
require 'base64'

def fetch_issue(key)
  url = URI("https://#{JIRA_DOMAIN}/rest/api/3/issue/#{key}")
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  req = Net::HTTP::Get.new(url, auth_header)
  res = http.request(req)
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    puts "Error: #{res.code} #{res.body}"
    nil
  end
end

data = fetch_issue('SMC-1400')
if data
  status = data['fields']['status']
  puts "=== STATUS ==="
  puts "Name: #{status['name']}"
  puts "ID: #{status['id']}"
  puts "Category: #{status['statusCategory']['name']}"

  puts "\n=== DESCRIPTION ==="
  desc = data['fields']['description']
  puts desc.inspect
end
