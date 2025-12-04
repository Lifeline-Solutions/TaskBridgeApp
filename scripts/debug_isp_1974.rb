#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'base64'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

def discover_custom_fields
  url = "#{JIRA_BASE_URL}/rest/api/3/field"
  uri = URI.parse(url)
  
  puts "Discovering custom fields from #{url}..."
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  
  response = http.request(request)
  
  unless response.is_a?(Net::HTTPSuccess)
    puts "Error fetching fields: #{response.code} #{response.message}"
    return nil
  end
  
  fields = JSON.parse(response.body)
  
  puts "\n--- Searching for Module Fields ---"
  fields.each do |field|
    name = field['name']&.downcase || ''
    if name.include?('imarisha') && name.include?('module')
      puts "Found candidate: ID='#{field['id']}', Name='#{field['name']}'"
    end
  end
  
  module_field = nil
  submodule_field = nil
  
  fields.each do |field|
    name = field['name']&.downcase || ''
    field_id = field['id']
    
    # Exact logic from production_import_erp.rb
    if name == 'imarisha  erp modules'
      module_field = field_id
      puts "\n[MATCH] Module field (double space): #{field_id} - #{field['name']}"
    elsif name == 'imarisha  erp modules / sub-modules'
      submodule_field = field_id
      puts "[MATCH] Submodule field (double space): #{field_id} - #{field['name']}"
    elsif name == 'imarisha erp modules'
      puts "[POSSIBLE MATCH] Module field (single space): #{field_id} - #{field['name']}"
    elsif name == 'imarisha erp modules / sub-modules'
      puts "[POSSIBLE MATCH] Submodule field (single space): #{field_id} - #{field['name']}"
    end
  end
  
  [module_field, submodule_field]
end

def fetch_issue(key, module_field, submodule_field)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{key}"
  uri = URI.parse(url)
  
  puts "\nFetching issue #{key}..."
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  
  response = http.request(request)
  
  unless response.is_a?(Net::HTTPSuccess)
    puts "Error fetching issue: #{response.code} #{response.message}"
    return
  end
  
  issue = JSON.parse(response.body)
  fields = issue['fields'] || {}
  
  puts "\n--- Field Values for #{key} ---"
  
  if module_field
    val = fields[module_field]
    puts "Module Field (#{module_field}): #{val.inspect}"
    puts "  -> Extracted: #{extract_custom_field_value(val)}"
  else
    puts "Module Field: NOT IDENTIFIED"
  end
  
  if submodule_field
    val = fields[submodule_field]
    puts "Submodule Field (#{submodule_field}): #{val.inspect}"
    puts "  -> Extracted: #{extract_custom_field_value(val)}"
  else
    puts "Submodule Field: NOT IDENTIFIED"
  end
  
  # Check for other potential fields containing the data
  puts "\n--- Checking all fields for 'Contracts' ---"
  fields.each do |k, v|
    str_val = v.to_s
    if str_val.include?('Contracts') && k.start_with?('customfield_')
      puts "Field #{k}: #{str_val[0..100]}..."
    end
  end
end

def extract_custom_field_value(field_data)
  return '' if field_data.nil?
  return field_data.to_s.strip if field_data.is_a?(String)

  if field_data.is_a?(Hash)
    return field_data['value'].to_s.strip if field_data['value'].present?
    return field_data['name'].to_s.strip if field_data['name'].present?
    return field_data['key'].to_s.strip if field_data['key'].present?
    return field_data['id'].to_s.strip if field_data['id'].present?
  end

  if field_data.is_a?(Array) && field_data.any?
    first_item = field_data.first
    if first_item.is_a?(Hash)
      return extract_custom_field_value(first_item)
    else
      return first_item.to_s.strip
    end
  end

  field_data.to_s.strip
end

# Main execution
mod_id, sub_id = discover_custom_fields
fetch_issue('ISP-1974', mod_id, sub_id)
