#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'set'

# Configuration Setup
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

# JQL provided by user
JQL = 'project = SMC AND issuetype = Task AND labels = QA AND "BankingType[Dropdown]" = "Core Banking" order by created DESC'

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_all_jira_keys
  keys = Set.new
  next_page_token = nil
  base_url = "#{JIRA_BASE_URL}/rest/api/3/search/jql"
  
  loop do
    log "Fetching Jira issues..."
    uri = URI(base_url)
    
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    
    payload = { jql: JQL, maxResults: 100, fields: ['key'] }
    payload[:nextPageToken] = next_page_token if next_page_token

    req.body = payload.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) do |http|
      http.request(req)
    end

    unless res.is_a?(Net::HTTPSuccess)
      log "Error fetching Jira issues: #{res.code} #{res.message}"
      log "Body: #{res.body}"
      break
    end

    json = JSON.parse(res.body)
    issues = json['issues'] || []
    
    if issues.empty?
       log "No issues found in response."
       break 
    end

    # DEBUG: Print first issue structure
    if keys.empty?
      log "DEBUG: First issue structure: #{issues.first.inspect}"
    end


    # Fix: Correctly add keys to Set
    issues.each { |i| keys.add(i['key']) }
    log "  Fetched #{issues.count} issues. Total so far: #{keys.size}"

    next_page_token = json['nextPageToken']
    break unless next_page_token
  end
  
  keys
end

log "Starting SMC Analysis..."
jira_keys = fetch_all_jira_keys
log "Total Jira Issues (Truth): #{jira_keys.size}"

db_defects = Defect.where("defect_unique LIKE 'SMC-%'").pluck(:defect_unique).to_set
log "Total TaskBridge Defects: #{db_defects.size}"

extra_in_db = db_defects - jira_keys
missing_in_db = jira_keys - db_defects

log "--- Analysis Results ---"
log "Present in DB but NOT in Jira Filter (Extras): #{extra_in_db.size}"
if extra_in_db.any?
  log "Sample Extras: #{extra_in_db.to_a.first(10).join(', ')}"
end

log "Present in Jira but NOT in DB (Missing): #{missing_in_db.size}"
if missing_in_db.any?
  log "Sample Missing: #{missing_in_db.to_a.first(10).join(', ')}"
end
