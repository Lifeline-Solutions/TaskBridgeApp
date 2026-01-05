#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'optparse'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

options = {
  dry_run: false,
  project: 'KCBL'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_priorities.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--project KEY', 'Project key (default KCBL)') { |v| options[:project] = v }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

# Main Execution
log "Starting priority fix script for project #{options[:project]} (Dry Run: #{options[:dry_run]})"

# Get all defects for the project
defects = Defect.where('defect_unique LIKE ?', "#{options[:project]}-%")
log "Found #{defects.count} defects to check."

stats = { updated: 0, skipped: 0, errors: 0, missing_priority: 0 }
count = 0

defects.find_each do |defect|
  count += 1
  log "Processed #{count} defects..." if (count % 50).zero?
  sleep 0.2 # Avoid rate limiting
  begin
    # Fetch from Jira
    url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{defect.defect_unique}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      log "Failed to fetch #{defect.defect_unique}: #{response.code}"
      stats[:errors] += 1
      next
    end

    issue = JSON.parse(response.body)
    fields = issue['fields'] || {}

    jira_priority_name = fields.dig('priority', 'name')

    if jira_priority_name.blank?
      log "  #{defect.defect_unique}: No priority found in Jira. Skipping."
      stats[:skipped] += 1
      next
    end

    # Check if update is needed
    current_priority = defect.priority

    # Simple string comparison (case-insensitive just in case)
    if current_priority&.downcase == jira_priority_name.downcase
      # log "  #{defect.defect_unique}: Priority match ('#{jira_priority_name}'). No change."
      stats[:skipped] += 1
      next
    end

    log "  #{defect.defect_unique}: Updating Priority..."
    log "    Old: #{current_priority}"
    log "    New: #{jira_priority_name}"

    unless options[:dry_run]
      defect.priority = jira_priority_name
      defect.save!
      log '    ✅ Updated successfully'
    end

    stats[:updated] += 1
  rescue StandardError => e
    log "ERROR processing #{defect.defect_unique}: #{e.message}"
    stats[:errors] += 1
  end
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}, Missing Priority: #{stats[:missing_priority]}"
