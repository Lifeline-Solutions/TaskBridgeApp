#!/usr/bin/env ruby
# scripts/update_attachment_dates.rb

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'optparse'
require 'yaml'

APP_ROOT = Rails.root

options = {
  dry_run: false,
  verbose: true,
  projects: ['ISP'],
  days_back: 2000,
  custom_jql: 'project = ISP AND labels = QA AND issuetype = Bug AND status IN ("Awaiting Build", "Awaiting client API", "Awaiting Client Information", BLOCKED, Failed-QA, "In Progress", On-Hold, "QA Testing", Reopened, Resolved, "Support Testing", "To Do", Closed) AND cf[10141] = "ERP" ORDER BY created DESC'
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/update_attachment_dates.rb [options]'

  opts.on('--project KEY1,KEY2,...', Array, 'Override Jira project key(s)') { |v| options[:projects] = v }
  opts.on('--jql JQL', 'Override Custom JQL query') { |v| options[:custom_jql] = v }
  opts.on('--dry-run', "Don't save; only show what would happen") { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
  opts.on('--days N', Integer, 'How many days back to fetch (default 2000)') { |v| options[:days_back] = v }
end.parse!

config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

# Jira credentials
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

def info(msg)
  puts msg
end

def vputs(msg)
  puts msg if $verbose_flag
end

$verbose_flag = options[:verbose]

def fetch_jira_issues(custom_jql: nil, max_results: 100)
  issues = []
  next_page_token = nil

  loop do
    url = "#{JIRA_BASE_URL}/rest/api/3/search/jql"
    uri = URI.parse(url)

    # We only need key and attachment fields
    fields = %w[key attachment comment]

    query_params = {
      jql: custom_jql,
      maxResults: max_results,
      fields: fields.join(',')
    }

    query_params[:nextPageToken] = next_page_token if next_page_token.present?

    uri.query = URI.encode_www_form(query_params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    vputs "Fetching issues from Jira (nextPageToken: #{next_page_token})..."

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      warn "❌ Failed to fetch issues: #{response.code} #{response.message}"
      break
    end

    data = JSON.parse(response.body)
    batch = data['issues'] || []

    issues.concat(batch)
    vputs "Fetched #{batch.length} issues (Total: #{issues.length})"

    next_page_token = data['nextPageToken']
    break if next_page_token.nil? || batch.empty?
  end

  issues
end

def update_attachment_dates(issue, dry_run: false)
  issue_key = issue['key']
  fields = issue['fields'] || {}
  jira_attachments = fields['attachment'] || []

  # Also check comments for attachments
  comments = fields.dig('comment', 'comments') || []
  comments.each do |comment|
    # Jira API v3 might structure comment attachments differently or they might be embedded
    # But often they are just in the main attachment list if attached to issue
    # We'll focus on the main attachment list first as that's where file uploads usually go
  end

  if jira_attachments.empty?
    vputs "[SKIP] #{issue_key}: No attachments in Jira"
    return
  end

  defect = Defect.find_by(defect_unique: issue_key)
  unless defect
    vputs "[SKIP] #{issue_key}: Defect not found in TaskBridge"
    return
  end

  # Get all attachments for this defect (including those in rich text)
  local_attachments = defect.all_attachments

  if local_attachments.empty?
    vputs "[SKIP] #{issue_key}: No local attachments found"
    return
  end

  jira_attachments.each do |jira_att|
    filename = jira_att['filename']
    created_str = jira_att['created']
    jira_created_at = Time.parse(created_str)

    # Find matching local attachment by filename
    # Note: filenames might be slightly different if duplicates were handled, but usually match
    match = local_attachments.find { |la| la.filename.to_s == filename }

    if match
      if match.created_at == jira_created_at
        vputs "[OK] #{issue_key} attachment '#{filename}' date already matches"
      elsif dry_run
        info "[DRY] Would update #{issue_key} attachment '#{filename}' date: #{match.created_at} -> #{jira_created_at}"
      else
        # Update ActiveStorage::Attachment and Blob
        # We update both to be safe, though Attachment is the join record
        match.update_columns(created_at: jira_created_at)
        match.blob.update_columns(created_at: jira_created_at)
        info "[UPDATE] Updated #{issue_key} attachment '#{filename}' date to #{jira_created_at}"
      end
    else
      vputs "[WARN] #{issue_key}: Jira attachment '#{filename}' not found locally"
    end
  end
end

# Main Execution
begin
  info 'Fetching issues...'
  issues = fetch_jira_issues(custom_jql: options[:custom_jql])

  if issues.empty?
    info 'No issues found.'
    exit 0
  end

  info "Processing #{issues.length} issues..."

  issues.each do |issue|
    update_attachment_dates(issue, dry_run: options[:dry_run])
  end

  info 'Done!'
end
