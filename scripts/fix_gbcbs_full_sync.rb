#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'securerandom'
require 'date'
require 'fileutils'
require 'open-uri'
require 'optparse'

# Load Enhanced ADF Converter
require_relative 'enhanced_adf_converter'

# Configuration Setup
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

PRODUCT_ID = 'daca16f6-0ca6-45f7-a40d-a948b576cd71' # GBCBS Project
MODULE_FIELD_ID = 'customfield_10103' # GBCBS Module (Client Maintenance/Approval etc)

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_gbcbs_full_sync.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_issues_via_jql(jql, start_at = 0)
  url = URI("#{JIRA_BASE_URL}/rest/api/3/search")
  params = {
    jql: jql,
    startAt: start_at,
    maxResults: 50,
    fields: "summary,status,reporter,assignee,created,updated,description,#{MODULE_FIELD_ID}"
  }
  url.query = URI.encode_www_form(params)
  
  req = Net::HTTP::Get.new(url)
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json'

  res = Net::HTTP.start(url.hostname, url.port, use_ssl: (url.scheme == 'https')) { |http| http.request(req) }
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    log "Error fetching JQL: #{res.code} #{res.message}"
    nil
  end
end

# Validated Intelligent Match + User Creation (Disabled)
def normalize_email(display_name)
  name_parts = display_name.to_s.strip.split(/[\s\.]+/)
  return "unknown.user-#{SecureRandom.hex(4)}@craftsilicon.com" if name_parts.empty?
  
  first = name_parts.first.gsub(/[^a-zA-Z0-9]/, '')
  last = name_parts.length > 1 ? name_parts.last.gsub(/[^a-zA-Z0-9]/, '') : ''
  email_local = last.present? ? "#{first}.#{last}" : first
  "#{email_local}@craftsilicon.com"
end

def find_or_create_user(jira_user_data)
  return nil unless jira_user_data
  
  # 1. Try accountId first (most reliable)
  account_id = jira_user_data['accountId']
  # We don't verify accountId locally yet, so skip to email/name
  
  email = jira_user_data['emailAddress']
  display_name = jira_user_data['displayName']
  
  # Normalize email if missing
  email = normalize_email(display_name) if email.blank?
  
  # 2. Try exact email match
  user = User.find_by('lower(email) = ?', email.downcase)
  
  # 3. Intelligent Name Match strategies if email fails
  unless user
    # (Simplified for this script to avoid duplicating the huge logic block, 
    # ensuring consistent behavior with other scripts if we import the helper,
    # but here I will include the core matching to be safe)
    
    # Try First Last
    parts = display_name.split
    if parts.size >= 2
       user = User.where("lower(first_name) = ? AND lower(last_name) = ?", parts.first.downcase, parts.last.downcase).first
    end
  end

  unless user
    log "    -> [CREATE] Creating DISABLED user: #{display_name} (#{email})"
    password = SecureRandom.hex(12)
    user = User.new(
      first_name: display_name.split(' ').first,
      last_name: display_name.split(' ').drop(1).join(' '),
      email: email,
      password: password, 
      password_confirmation: password,
      active: false, # DISABLED
      confirmed_at: Time.now
    )
    user.save!(validate: false)
  end
  user
end

def find_or_create_module(module_name)
  return nil if module_name.blank?
  QaModule.find_or_create_by!(name: module_name, product_id: PRODUCT_ID)
end

# Main Execution
log "Starting GBCBS Sync..."
jql = 'project = GBCBS ' \
      'AND issuetype = Defect ' \
      'AND status in ("BANK TO CLARIFY", Blocked, BLOCKED, Closed, CLOSED, Deferred, "DEV TO CLARIFY", FAILED-QA, "FIXED READY TO UPLOAD", "In Progress", "IN PROGRESS", "NEW REQUIREMENT", "NICE TO HAVE", "NOT A DEFECT", "ON HOLD", "On Hold", "On hold", "R & D", "READY FOR TEST - QA", "Testing- Support", "To Do", UI) ' \
      'AND reporter in (5e4680753011ed0c8f8a5bed, 5d0deca321a5d30bc4e09e24, 5cdd42f8f593d10d74a6f29b, 5cb08478e5f5e936798c9f4e, 603e3a7dcc13b6006995a3a6, 5fb22cda47ac91006f45808f, 5d491c970fa6d40d14fc5a30, 606c6692ef87dd006853547c) ' \
      'AND "Module[Dropdown]" = Treasury ' \
      'ORDER BY reporter DESC, created DESC'

start_at = 0
total_processed = 0

loop do
  log "Fetching batch from #{start_at}..."
  data = fetch_issues_via_jql(jql, start_at)
  break if data.nil? || data['issues'].empty?
  
  data['issues'].each do |issue_data|
    fields = issue_data['fields']
    key = issue_data['key']
    
    defect = Defect.find_or_initialize_by(defect_unique: key)
    changes = false
    
    # 1. Product ID
    if defect.product_id != PRODUCT_ID
      defect.product_id = PRODUCT_ID
      changes = true
      log "  #{key}: Set Product ID"
    end

    # 2. Summary
    if defect.summary != fields['summary']
      defect.summary = fields['summary']
      changes = true
    end

    # 3. Reporter (Creator)
    # The user provided list of reporters in JQL, so they are filtered, but we still map them.
    if fields['reporter']
       creator = find_or_create_user(fields['reporter'])
       if defect.creator_id != creator.id
          defect.creator = creator
          changes = true
       end
    end

    # 4. Assignee
    if fields['assignee']
      assignee = find_or_create_user(fields['assignee'])
      if assignee
        unless defect.user_ids.include?(assignee.id)
          defect.users = [assignee]
          changes = true
        end
      end
    end

    # 5. Status
    if fields['status']
      status_name = fields['status']['name']
      status = Status.where('lower(name) = ?', status_name.downcase).first
      unless status
        log "    -> [CREATE] Creating status: #{status_name}"
        sys_user = User.first&.id || 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
        status = Status.create!(name: status_name, user_id: sys_user, created_by: sys_user, modified_by: sys_user)
      end
      
      if !defect.statuses.include?(status)
         defect.statuses = [status]
         changes = true
         log "    -> Set Status: #{status.name}"
      end
    end
    
    # 6. Dates
    j_created = DateTime.parse(fields['created'])
    j_updated = DateTime.parse(fields['updated'])
    if defect.created_at.nil? || (defect.created_at.to_i - j_created.to_i).abs > 5
      defect.created_at = j_created
      changes = true
    end
    if defect.updated_at.nil? || (defect.updated_at.to_i - j_updated.to_i).abs > 5
      defect.updated_at = j_updated
      changes = true
    end

    # 7. Module (Treasury check handled by JQL, but we parse it into QaModule)
    module_data = fields[MODULE_FIELD_ID]
    if module_data.present?
       # Can be Hash {"value"=>"Treasury", ...} or similar
       val = module_data.is_a?(Hash) ? module_data['value'] : module_data.to_s
       
       qa_module = find_or_create_module(val)
       if defect.qa_module_id != qa_module.id
          defect.qa_module = qa_module
          changes = true
          log "    -> Set Module: #{val}"
       end
    end

    # 8. Description (Rich Text)
    if fields['description']
       html_content = ""
       if fields['description'].is_a?(Hash) && fields['description']['content']
         html_content = convert_adf_to_html_enhanced(fields['description']['content'])
       elsif fields['description'].is_a?(String)
         html_content = fields['description']
       end
       
       current_body = defect.content.body.to_s rescue ""
       if html_content.present? && current_body != html_content
          defect.content = html_content
          changes = true
          log "    -> Updated Description"
       end
    end

    # SAVE
    unless options[:dry_run]
       if changes || defect.new_record?
          defect.save!(validate: false)
          log "  ✅ Saved #{key}"
       else
          # log "  No changes for #{key}"
       end
    else
       log "  [Dry Run] Changes for #{key}: #{changes}"
    end
    
    total_processed += 1
  end
  
  start_at += 50
end

log "Total Processed: #{total_processed}"
