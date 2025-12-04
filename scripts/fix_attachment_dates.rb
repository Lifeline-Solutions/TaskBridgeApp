#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'optparse'
require 'time'

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

options = {
  dry_run: false,
  project: 'ISP'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_attachment_dates.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--project KEY', 'Project key (default ISP)') { |v| options[:project] = v }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_jira_issue(key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{key}"
  uri = URI.parse(url)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)
  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

# Main Execution
log "Starting attachment date fix script for project #{options[:project]} (Dry Run: #{options[:dry_run]})"

# Get all defects for the project that have attachments
defects = Defect.where('defect_unique LIKE ?', "#{options[:project]}-%")
  .joins(:attachments_attachments)
  .distinct

log "Found #{defects.count} defects with attachments to check."

stats = { updated: 0, skipped: 0, errors: 0 }

defects.find_each do |defect|
  issue = fetch_jira_issue(defect.defect_unique)
  unless issue
    log "Failed to fetch #{defect.defect_unique} from Jira"
    stats[:errors] += 1
    next
  end

  jira_attachments = issue['fields']['attachment'] || []

  if jira_attachments.empty?
    log "  #{defect.defect_unique}: No attachments in Jira (but has local ones?)"
    next
  end

  # Process each local attachment
  defect.attachments.each do |local_att|
    # Find matching Jira attachment by filename and size
    # Normalizing filename: Jira sometimes has spaces, local might have them too or underscores depending on how it was saved
    # But based on debug output, filenames seem preserved.

    matched_jira_att = jira_attachments.find do |ja|
      ja['filename'] == local_att.filename.to_s && ja['size'].to_i == local_att.byte_size
    end

    unless matched_jira_att
      # Try looser match on filename only if exact match fails (and only one file with that name)
      candidates = jira_attachments.select { |ja| ja['filename'] == local_att.filename.to_s }
      matched_jira_att = candidates.first if candidates.length == 1
    end

    if matched_jira_att
      jira_created = Time.parse(matched_jira_att['created'])

      # Check if update is needed (allow 1 minute tolerance for timezone/parsing diffs, though usually exact)
      if (local_att.created_at - jira_created).abs < 60
        # log "  #{defect.defect_unique}: #{local_att.filename} date already correct"
        next
      end

      log "  #{defect.defect_unique}: Updating #{local_att.filename}"
      log "    Current: #{local_att.created_at}"
      log "    Target:  #{jira_created}"

      unless options[:dry_run]
        # Update both attachment and blob creation dates
        local_att.update_columns(created_at: jira_created)
        local_att.blob.update_columns(created_at: jira_created)
        log '    ✅ Updated'
      end
      stats[:updated] += 1
    else
      log "  #{defect.defect_unique}: Could not match local attachment '#{local_att.filename}' (#{local_att.byte_size} bytes) to Jira"
      stats[:skipped] += 1
    end
  end
rescue StandardError => e
  log "ERROR processing #{defect.defect_unique}: #{e.message}"
  stats[:errors] += 1
end

log "Done! Updated: #{stats[:updated]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
