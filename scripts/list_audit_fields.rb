require 'net/http'
require 'json'
require 'yaml'

config_path = Rails.root.join('config', 'jira_import.yml')
config = YAML.load_file(config_path).with_indifferent_access

base_url = ENV['JIRA_BASE_URL'] || config[:jira_base_url] || 'https://craftsilicon.atlassian.net'
user = ENV['JIRA_API_USER'] || config[:jira_api_user] || 'boniface.nemwel@craftsilicon.com'
token = ENV['JIRA_API_TOKEN'] || config[:jira_api_token]

url = "#{base_url}/rest/api/3/field"
uri = URI.parse(url)

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri.request_uri)
request.basic_auth(user, token)

response = http.request(request)
fields = JSON.parse(response.body)

puts "Searching for 'Audit' fields:"
fields.each do |f|
  puts "#{f['id']} - #{f['name']}" if f['name'].downcase.include?('audit')
end
