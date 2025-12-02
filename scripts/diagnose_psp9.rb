#!/usr/bin/env ruby
# Diagnose PSP-9 issue structure

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

# Load configuration from jira_import.yml
config_path = File.join(__dir__, '..', 'config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).transform_keys(&:to_sym)

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

issue_key = "PSP-9"

url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
uri = URI.parse(url)

uri.query = URI.encode_www_form({
                                  expand: 'renderedFields',
                                  fields: 'description,summary'
                                })

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 30

request = Net::HTTP::Get.new(uri.request_uri)
request['Accept'] = 'application/json'
request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

puts "Fetching #{issue_key}..."

begin
  response = http.request(request)

  if response.is_a?(Net::HTTPSuccess)
    data = JSON.parse(response.body)

    # Save full response
    File.write('/home/abol-ger/Desktop/Projects/tasker/CSPM/tmp/jira_psp9_full.json', JSON.pretty_generate(data))
    puts "✅ Saved full response to tmp/jira_psp9_full.json"

    # Analyze structure
    puts "\n=== TOP LEVEL KEYS ==="
    puts data.keys.join(', ')

    if data['fields']
      puts "\n=== FIELDS KEYS ==="
      puts data['fields'].keys.sort.join(', ')

      desc = data['fields']['description']
      puts "\n=== DESCRIPTION ==="
      puts "Type: #{desc.class}"

      if desc.nil?
        puts "❌ Description is nil!"
      elsif desc.is_a?(Hash)
        puts "Keys: #{desc.keys.join(', ')}"

        if desc['content']
          puts "\n=== CONTENT BLOCKS ==="
          desc['content'].each_with_index do |block, i|
            puts "Block #{i}: #{block['type']}"
            if block['type'] == 'table'
              puts "  - Table with #{block['content']&.length || 0} rows"
              # Save just the table structure
              File.write('/home/abol-ger/Desktop/Projects/tasker/CSPM/tmp/jira_psp9_table.json', JSON.pretty_generate(block))
              puts "  - Saved table block to tmp/jira_psp9_table.json"
            end
          end
        end
      elsif desc.is_a?(String)
        puts "Description is a string: #{desc[0..100]}"
      end
    end

    if data['renderedFields']
      puts "\n=== RENDERED FIELDS ==="
      rendered_desc = data['renderedFields']['description']
      if rendered_desc
        puts "Rendered description length: #{rendered_desc.length} chars"
        puts "Has table: #{rendered_desc.include?('<table')}"
        puts "Has ADF macro: #{rendered_desc.include?('<!-- ADF macro')}"
        File.write('/home/abol-ger/Desktop/Projects/tasker/CSPM/tmp/jira_psp9_rendered.html', rendered_desc)
        puts "Saved to tmp/jira_psp9_rendered.html"
      else
        puts "No rendered description"
      end
    end

  else
    puts "❌ HTTP Error: #{response.code} #{response.message}"
    puts response.body
  end
rescue => e
  puts "❌ Exception: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

