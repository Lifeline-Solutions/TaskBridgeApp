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

puts 'Fetching SMC-1...'
data = fetch_issue('SMC-1')

if data
  data['fields']
  puts '=== FINDING COMMENTS ==='
  comments = begin
    data['fields']['comment']['comments']
  rescue StandardError
    []
  end
  comments.each do |c|
    author = c['author']
    puts "Author: #{author['displayName']} | Email: #{author['emailAddress']} | AccountID: #{author['accountId']}"
  end
end
