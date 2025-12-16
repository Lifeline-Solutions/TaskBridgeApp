#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'set'
require 'securerandom'

# Configuration Setup
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

PROJECT_KEY = 'SMC'
PRODUCT_ID = 'e618ac94-3d46-4e77-96c8-389d0a343652'
BANKING_TYPE_ID = '2901cd48-75e6-4ca3-907c-b62a31571814' # Core Banking
DEFAULT_LABEL = 'QA'

# JQL for the master list
JQL = 'project = SMC AND issuetype = Task AND labels = QA AND "BankingType[Dropdown]" = "Core Banking" order by created DESC'

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_smc_reporters.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def normalize_email(display_name)
  name_parts = display_name.to_s.strip.split(/[\s\.]+/)
  return "unknown.user-#{SecureRandom.hex(4)}@craftsilicon.com" if name_parts.empty?
  
  first = name_parts.first.gsub(/[^a-zA-Z0-9]/, '')
  last = name_parts.length > 1 ? name_parts.last.gsub(/[^a-zA-Z0-9]/, '') : ''
  email_local = last.present? ? "#{first}.#{last}" : first
  "#{email_local}@craftsilicon.com"
end

def fetch_all_jira_issues
  issues_map = {}
  next_page_token = nil
  base_url = "#{JIRA_BASE_URL}/rest/api/3/search/jql"
  
  loop do
    log "Fetching page..."
    uri = URI(base_url)
    req = Net::HTTP::Post.new(uri)
    req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'
    
    # Fetch key, reporter, summary, priority in one go
    payload = { jql: JQL, maxResults: 100, fields: ['key', 'reporter', 'summary', 'priority'] }
    payload[:nextPageToken] = next_page_token if next_page_token
    req.body = payload.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) { |http| http.request(req) }
    
    unless res.is_a?(Net::HTTPSuccess)
      log "Error fetching issues: #{res.code} #{res.message}"
      break
    end

    json = JSON.parse(res.body)
    batch = json['issues'] || []
    break if batch.empty?
    
    batch.each do |i| 
      issues_map[i['key']] = i
    end
    log "  Fetched #{batch.count} issues. Total: #{issues_map.size}"
    
    next_page_token = json['nextPageToken']
    break unless next_page_token
  end
  issues_map
end

def map_priority(jira_priority)
  name = jira_priority ? jira_priority['name'].to_s.downcase : ''
  case name
  when /highest/
    'Severity 1'
  when /high/
    'Severity 2'
  when /medium/, /normal/
    'Severity 3'
  when /low/, /lowest/
    'Severity 4'
  else
    'Severity 3'
  end
end

def find_or_create_user(reporter_data, cache)
  return nil unless reporter_data
  
  display_name = reporter_data['displayName']
  jira_email = reporter_data['emailAddress']
  
  # Check cache
  return cache[:email][jira_email.downcase] if jira_email.present? && cache[:email][jira_email.downcase]
  
  constructed_email = normalize_email(display_name)
  return cache[:email][constructed_email.downcase] if cache[:email][constructed_email.downcase]
  
  # DB Lookup
  user = nil
  user = User.find_by('lower(email) = ?', jira_email.downcase) if jira_email.present?
  user ||= User.find_by('lower(email) = ?', constructed_email.downcase)
  
  if !user && display_name.present?
    clean_name = display_name.tr('.', ' ').strip
    user ||= User.where("lower(first_name) || ' ' || lower(last_name) = ?", clean_name.downcase).first
    user ||= User.where('lower(name) = ?', clean_name.downcase).first rescue nil
  end
  
  # Create if missing
  if user.nil?
    log "    Creating user for '#{display_name}' -> #{constructed_email}"
    parts = display_name.split(/[\s\.]+/, 2)
    pwd = SecureRandom.hex(12)
    
    unless options[:dry_run]
      user = User.new(
        first_name: parts[0],
        last_name: parts[1] || '',
        email: constructed_email,
        password: pwd,
        password_confirmation: pwd,
        active: false,
        confirmed_at: Time.now
      )
      
      unless user.save
        log "    ❌ Failed to create user: #{user.errors.full_messages}"
        return nil
      end
    else
        log "    [Dry Run] Would create user #{constructed_email}"
        user = User.new(id: 'mock-id', email: constructed_email, first_name: parts[0])
    end
  end
  
  # Update cache
  if user.id != 'mock-id'
    cache[:email][user.email.downcase] = user
    cache[:email][jira_email.downcase] = user if jira_email.present?
  end
  user
end

# Main Execution
log "Starting SMC Sync (Optimized) (Dry Run: #{options[:dry_run]})"

# 1. Fetch Master List (with details)
jira_issues = fetch_all_jira_issues
if jira_issues.empty?
  log "❌ No issues fetched from Jira. Aborting to prevent deletion."
  exit 1
end

stats = { updated: 0, created: 0, deleted: 0, skipped: 0, errors: 0 }
user_cache = { email: {}, name: {} }

# 2. Sync Valid Issues (Create/Update)
jira_issues.each do |key, issue_data|
  begin
    defect = Defect.find_by(defect_unique: key)
    
    fields = issue_data['fields'] || {}
    reporter_data = fields['reporter']
    summary = fields['summary']
    priority_data = fields['priority']
    target_priority = map_priority(priority_data)

    # Resolve User
    user = find_or_create_user(reporter_data, user_cache)
    unless user
       log "  #{key}: Could not resolve user. Skipping."
       stats[:errors] += 1
       next
    end

    if defect.nil?
      # CREATE
      log "  #{key}: Creating defect..."
      unless options[:dry_run]
        defect = Defect.new(
          defect_unique: key,
          product_id: PRODUCT_ID,
          banking_type_id: BANKING_TYPE_ID,
          summary: summary,
          priority: target_priority,
          created_by: user.id,
          creator_id: user.id
        )

        if defect.save
          log "    ✅ Created"
          stats[:created] += 1
        else
          log "    ❌ Create failed: #{defect.errors.full_messages}"
          stats[:errors] += 1
        end
      else
        stats[:created] += 1
      end
    else
      # UPDATE
      # Compare reporter, priority, etc.
      update_needed = false
      if user.id != 'mock-id'
         if defect.created_by != user.id || defect.creator_id != user.id
            update_needed = true
         end
         if defect.banking_type_id != BANKING_TYPE_ID
            update_needed = true
         end
         if defect.product_id != PRODUCT_ID
            update_needed = true
         end
         if defect.priority != target_priority
            update_needed = true
         end
      end

      if update_needed
        log "  #{key}: Updating fields (Reporter/Product/BankingType/Priority)"
        unless options[:dry_run]
          defect.created_by = user.id
          defect.creator_id = user.id
          defect.banking_type_id = BANKING_TYPE_ID
          defect.product_id = PRODUCT_ID
          defect.priority = target_priority
          defect.save
        end
        stats[:updated] += 1
      else
        stats[:skipped] += 1
      end
    end

  rescue StandardError => e
    log "Error processing #{key}: #{e.message}"
    log e.backtrace.join("\n")
    stats[:errors] += 1
  end
end

# 3. Delete Extras
log "Checking for extras to delete..."
# Find all defects starting with SMC-
db_defects = Defect.where("defect_unique LIKE 'SMC-%'")
db_defects.each do |d|
  unless jira_issues.key?(d.defect_unique)
    log "  Extra found: #{d.defect_unique} - Deleting"
    unless options[:dry_run]
      d.destroy 
      stats[:deleted] += 1
    else
      stats[:deleted] += 1
    end
  end
end

log "Done! Created: #{stats[:created]}, Updated: #{stats[:updated]}, Deleted: #{stats[:deleted]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
