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
  opts.banner = 'Usage: rails runner scripts/fix_statuses.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--project KEY', 'Project key (default KCBL)') { |v| options[:project] = v }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

# Main Execution
log "Starting status fix script for project #{options[:project]} (Dry Run: #{options[:dry_run]})"

# Get all defects for the project
defects = Defect.where('defect_unique LIKE ?', "#{options[:project]}-%")
log "Found #{defects.count} defects to check."

stats = { updated: 0, skipped: 0, errors: 0, missing_status: 0 }
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

    jira_status_name = fields.dig('status', 'name')

    if jira_status_name.blank?
      log "  #{defect.defect_unique}: No status found in Jira. Skipping."
      stats[:skipped] += 1
      next
    end

    # Status Mapping - Maps JIRA status names to local database names
    status_map = {
      'Failed-QA' => 'Failed QA',
      'FAILED - QA' => 'Failed QA',
      'Failed QA' => 'Failed QA',
      'ON HOLD' => 'On-Hold',
      'On-Hold' => 'On-Hold',
      'On Hold' => 'On-Hold',
      'QA Testing' => 'QA Testing',
      'Awaiting Build' => 'Awaiting Build',
      'TO DO' => 'TO DO',
      'In Progress' => 'In Progress',
      'Closed' => 'Closed',
      'Resolved' => 'Resolved',
      'Reopened' => 'Reopened',
      'Blocked' => 'Blocked',
      'Support Testing' => 'Support Testing',
      'Awaiting Client Information' => 'Awaiting Client Information',
      'Awaiting Client API' => 'Awaiting Client API'
    }

    mapped_status_name = status_map[jira_status_name] || jira_status_name

    # Find local status
    # Try exact match first, then case-insensitive
    local_status = Status.find_by(name: mapped_status_name) ||
                   Status.where('lower(name) = ?', mapped_status_name.downcase).first

    unless local_status
      log "  #{defect.defect_unique}: Status '#{jira_status_name}' not found locally. Skipping."
      stats[:missing_status] += 1
      next
    end

    # Check if update is needed
    current_statuses = defect.statuses
    if current_statuses.one? && current_statuses.first.id == local_status.id
      # log "  #{defect.defect_unique}: Status match ('#{jira_status_name}'). No change."
      stats[:skipped] += 1
      next
    end

    log "  #{defect.defect_unique}: Updating Status..."
    log "    Old: #{current_statuses.map(&:name).join(', ')}"
    log "    New: #{local_status.name}"

    unless options[:dry_run]
      defect.statuses = [local_status]
      # We don't need to call save! when assigning to has_and_belongs_to_many, it saves immediately.
      # But let's touch the defect to update updated_at
      defect.touch
      log '    ✅ Updated successfully'
    end

    stats[:updated] += 1
  rescue StandardError => e
    log "ERROR processing #{defect.defect_unique}: #{e.message}"
    stats[:errors] += 1
  end
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}, Missing Status: #{stats[:missing_status]}"
