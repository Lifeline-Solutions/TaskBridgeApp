# Configuration Setup
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

def fetch_issue(key)
  uri = URI("#{JIRA_BASE_URL}/rest/api/3/issue/#{key}")
  req = Net::HTTP::Get.new(uri)
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json'

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) do |http|
    http.request(req)
  end

  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    puts "Error: #{res.code} #{res.message}"
    nil
  end
end

puts "Fetching SMC-1..."
data = fetch_issue('SMC-1')

if data
  fields = data['fields']
  puts "=== FINDING MODULE FIELD ==="
  fields.each do |k, v|
    next unless k.start_with?('customfield_')
    # Check both value and field name if possible (but we only have value here usually)
    # Value for SMC-1 according to screenshot is "Client Maintenance/Approval - Client Registration-[Corporate]"
    if v.to_s.include?('Client Maintenance') || v.to_s.include?('Sofia Modules')
       puts "FOUND: #{k} => #{v.inspect}" 
    end
  end
end
