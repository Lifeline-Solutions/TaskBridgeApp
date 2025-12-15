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

def discover_juza_fields
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)
  unless response.is_a?(Net::HTTPSuccess)
    puts "Error: #{response.code} - #{response.message}"
    return
  end

  fields = JSON.parse(response.body)
  puts "Searching for 'Juza' in #{fields.count} fields..."

  fields.each do |field|
    name = field['name']
    if name.to_s.downcase.include?('juza')
      puts "FOUND: Name='#{name}', ID='#{field['id']}', Schema=#{field['schema']}"
    end
  end
end

discover_juza_fields
