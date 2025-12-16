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

# Configuration Setup
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

PROJECT_KEY = 'SMC'
MODULE_FIELD_ID = 'customfield_10156' # Sofia Modules_Submodules (Cascading)
PRODUCT_ID = 'e618ac94-3d46-4e77-96c8-389d0a343652'

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_smc_full_sync.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_issue_details(key)
  uri = URI("#{JIRA_BASE_URL}/rest/api/3/issue/#{key}")
  req = Net::HTTP::Get.new(uri)
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json'

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) { |http| http.request(req) }
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    log "Error fetching #{key}: #{res.code} #{res.message}"
    nil
  end
end

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
  
  # Normalize email if missing
  email = normalize_email(display_name) if email.blank?
  
  user = User.find_by('lower(email) = ?', email.downcase)
  
  unless user
    log "    Creating user: #{display_name} (#{email})"
    password = SecureRandom.hex(12)
    user = User.new(
      first_name: display_name.split(' ').first,
      last_name: display_name.split(' ').drop(1).join(' '),
      email: email,
      password: password, 
      password_confirmation: password,
      active: true,
      confirmed_at: Time.now
    )
    user.save!(validate: false) # Skip strict validation if needed
  end
  user
end

def find_or_create_module(module_name)
  return nil if module_name.blank?
  # Clean up module name (e.g., replace / with space or - if needed, but keeping original is safer for now)
  QaModule.find_or_create_by!(name: module_name, product_id: PRODUCT_ID)
end

def find_or_create_submodule(submodule_name, parent_module)
  return nil if submodule_name.blank? || parent_module.nil?
  QaModule.find_or_create_by!(name: submodule_name, parent_id: parent_module.id, product_id: PRODUCT_ID)
end

def sync_attachments(defect, attachments_data)
  return if attachments_data.blank?
  
  attachments_data.each do |att|
    filename = att['filename']
    url = att['content']
    mime_type = att['mimeType']
    
    # Check if already attached to :attachments
    if defect.attachments.blobs.any? { |blob| blob.filename.to_s == filename }
      log "      Attachment #{filename} exists. Skipping."
      next
    end
    
    log "      Downloading attachment: #{filename}"
    begin
      downloaded_file = URI.open(url, "Authorization" => "Basic #{Base64.strict_encode64("#{JIRA_API_USER}:#{JIRA_API_TOKEN}")}")
      defect.attachments.attach(io: downloaded_file, filename: filename, content_type: mime_type)
    rescue => e
      log "      ❌ Failed to attach #{filename}: #{e.message}"
    end
  end
end

# Main Loop
defects = Defect.where("defect_unique LIKE 'SMC-%'").order(:defect_unique)
log "Found #{defects.count} SMC defects in DB."

defects.each do |defect|
  log "Processing #{defect.defect_unique}..."
  
  jira_data = fetch_issue_details(defect.defect_unique)
  next unless jira_data
  
  fields = jira_data['fields']
  
  # 1. Assignee
  if fields['assignee']
    assignee = find_or_create_user(fields['assignee'])
    if assignee
      # Defect uses HABTM users for assignment. Replace existing assignees to match Jira.
      defect.users = [assignee] 
    end
  end
  
  # 2. Modules (Cascading Select)
  module_val = fields[MODULE_FIELD_ID]
  if module_val.present? && module_val.is_a?(Hash)
    parent_name = module_val['value']
    child_name = module_val['child'] ? module_val['child']['value'] : nil
    
    qa_module = find_or_create_module(parent_name)
    submodule = find_or_create_submodule(child_name, qa_module)
    
    defect.qa_module = qa_module
    defect.submodule = submodule
    
    log "    Module: #{parent_name} | Submodule: #{child_name}"
  end
  
  # 3. Dates
  if fields['created']
    defect.created_at = DateTime.parse(fields['created'])
  end
  if fields['updated']
    defect.updated_at = DateTime.parse(fields['updated'])
  end
  
  # 4. Description (Basic ADF to text)
  if fields['description']
     text = ""
     if fields['description'].is_a?(Hash) && fields['description']['content']
       fields['description']['content'].each do |block|
         if block['type'] == 'paragraph' && block['content']
           block['content'].each do |node|
             text += node['text'] if node['type'] == 'text'
           end
           text += "\n\n"
         end
       end
     elsif fields['description'].is_a?(String)
       text = fields['description']
     end
     # defect has_rich_text :content, not description column
     defect.content = text if text.present?
  end

  # 5. Status
  if fields['status']
    status_name = fields['status']['name']
    if status_name.present?
      # Map 'Done' to 'Closed' if preferred, or just sync correctly. 
      # User said Jira="Closed", System="Resolved". So we sync what Jira says.
      # Fix: Status requires user_id. Use first user (Admin) or system default.
      system_user_id = User.order(:created_at).first&.id || 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
      
      status = Status.find_or_create_by(name: status_name) do |s|
        s.user_id = system_user_id
        s.created_by = system_user_id
        s.modified_by = system_user_id
      end
      
      if status
         defect.statuses = [status]
         log "    Status: #{status_name}"
      end
    end
  end

  unless options[:dry_run]
    if defect.changed?
      log "    Updating defect keys: #{defect.changes.keys}"
      defect.save!(validate: false)
    else
      log "    No changes."
    end
    
    # 5. Attachments
    sync_attachments(defect, fields['attachment'])
  else
    log "    [Dry Run] Changes: #{defect.changes}"
  end
end
