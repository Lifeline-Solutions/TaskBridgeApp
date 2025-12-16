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
MODULE_FIELD_ID = 'customfield_10103' # GBCBS Module
ALLOWED_REPORTERS = %w[
  5e4680753011ed0c8f8a5bed 5d0deca321a5d30bc4e09e24 5cdd42f8f593d10d74a6f29b
  5cb08478e5f5e936798c9f4e 603e3a7dcc13b6006995a3a6 5fb22cda47ac91006f45808f
  5d491c970fa6d40d14fc5a30 606c6692ef87dd006853547c
]
ALLOWED_STATUSES = [
  "BANK TO CLARIFY", "Blocked", "BLOCKED", "Closed", "CLOSED", "Deferred",
  "DEV TO CLARIFY", "FAILED-QA", "FIXED READY TO UPLOAD", "In Progress",
  "IN PROGRESS", "NEW REQUIREMENT", "NICE TO HAVE", "NOT A DEFECT", "ON HOLD",
  "On Hold", "On hold", "R & D", "READY FOR TEST - QA", "Testing- Support",
  "To Do", "UI"
].map(&:downcase).uniq

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_gbcbs_full_sync.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_issue_direct(key)
  url = URI("#{JIRA_BASE_URL}/rest/api/3/issue/#{key}")
  req = Net::HTTP::Get.new(url)
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json'

  res = Net::HTTP.start(url.hostname, url.port, use_ssl: (url.scheme == 'https')) { |http| http.request(req) }
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  elsif res.code == '404'
    log "Warning: Issue #{key} not found in Jira (404)"
    nil
  else
    log "Error fetching #{key}: #{res.code} #{res.message}"
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
  
  email = jira_user_data['emailAddress']
  display_name = jira_user_data['displayName']
  
  email = normalize_email(display_name) if email.blank?
  
  user = User.find_by('lower(email) = ?', email.downcase)
  
  unless user
    # Intelligent match logic (simplified for brevity but effective)
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
      active: false,
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
log "Starting GBCBS Sync (Direct Fetch Mode)..."
log "Target Product ID: #{PRODUCT_ID}"
log "Filtering for Module: Treasury"

scope = Defect.where("defect_unique LIKE 'GBCBS-%'").order(:defect_unique)
total_local = scope.count
log "Found #{total_local} local GBCBS candidates."

processed = 0
matched = 0
skipped = 0

scope.find_each(batch_size: 50) do |defect|
  key = defect.defect_unique
  
  # Fetch from Jira
  data = fetch_issue_direct(key)
  unless data
    skipped += 1
    next
  end
  
  fields = data['fields']
  
  # --- FILTER CHECKS ---
  
  # 1. Module Check
  module_val = fields[MODULE_FIELD_ID]
  actual_module = module_val.is_a?(Hash) ? module_val['value'] : module_val.to_s
  
  unless actual_module == 'Treasury'
    # log "  Skipping #{key}: Module is '#{actual_module}' (Expected: Treasury)"
    skipped += 1
    next
  end

  # 2. Status Check
  status_name = fields['status']['name']
  unless ALLOWED_STATUSES.include?(status_name.downcase)
    # log "  Skipping #{key}: Status '#{status_name}' not in allowed list"
    skipped += 1
    next
  end

  # 3. Reporter Check
  reporter_account_id = fields['reporter'] ? fields['reporter']['accountId'] : nil
  # If reporter is missing in Jira, we skip? Or include? User said "reporter in (...)"
  # If reporter data exists but ID is not in list, skip.
  if reporter_account_id.present? && !ALLOWED_REPORTERS.include?(reporter_account_id)
    # log "  Skipping #{key}: Reporter #{reporter_account_id} not in allowed list"
    skipped += 1
    next
  end

  # --- SYNC LOGIC ---
  matched += 1
  changes = false

  # 1. Product ID
  if defect.product_id != PRODUCT_ID
    defect.product_id = PRODUCT_ID
    changes = true
  end

  # 2. Summary
  if fields['summary'] && defect.summary != fields['summary']
    defect.summary = fields['summary']
    changes = true
  end

  # 3. Assignee
  if fields['assignee']
    assignee = find_or_create_user(fields['assignee'])
    if assignee
      unless defect.user_ids.include?(assignee.id)
        defect.users = [assignee]
        changes = true
      end
    end
  end

  # 4. Status (Ensure ID exists locally)
  status_obj = Status.where('lower(name) = ?', status_name.downcase).first
  unless status_obj
    log "    -> [CREATE] Creating status: #{status_name}"
    sys_user = User.first&.id || 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
    status_obj = Status.create!(name: status_name, user_id: sys_user, created_by: sys_user, modified_by: sys_user)
  end
  if !defect.statuses.include?(status_obj)
     defect.statuses = [status_obj]
     changes = true
  end
  
  # 5. Dates
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

  # 6. Module (Sync value to QaModule)
  if actual_module.present?
     qa_module = find_or_create_module(actual_module)
     if defect.qa_module_id != qa_module.id
        defect.qa_module = qa_module
        changes = true
     end
  end
  
  # 7. Description
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
        log "    -> Updated Description for #{key}"
     end
  end

  # SAVE
  unless options[:dry_run]
    if changes
      defect.save!(validate: false)
      log "  ✅ Synced #{key}"
    end
  else
    if changes
      log "  [Dry Run] Changes detected for #{key}"
    end
  end
  
  processed += 1
  print "." if processed % 10 == 0
end

puts "\n"
log "Completed."
log "Total Local Candidates: #{total_local}"
log "Skipped (Filters/Missing): #{skipped}"
log "Matched & Processed: #{matched}"
