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

PROJECT_KEY = 'SMC'
MODULE_FIELD_ID = 'customfield_10156' # Sofia Modules_Submodules (Cascading)
PRODUCT_ID = 'e618ac94-3d46-4e77-96c8-389d0a343652'

options = { dry_run: false, specific: nil }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_smc_full_sync.rb [options]'
  opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  opts.on('--specific KEY', 'Run for specific defect (e.g. SMC-1400)') { |v| options[:specific] = v }
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
  
  # Normalize email if missing
  email = normalize_email(display_name) if email.blank?
  
  user = User.find_by('lower(email) = ?', email.downcase)
  
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
    
    if defect.attachments.blobs.any? { |blob| blob.filename.to_s == filename }
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
scope = if options[:specific]
          Defect.where(defect_unique: options[:specific])
        else
          Defect.where("defect_unique LIKE 'SMC-%'").order(:defect_unique)
        end

log "Found #{scope.count} SMC defects to sync."

scope.each do |defect|
  log "Processing #{defect.defect_unique}..."
  
  jira_data = fetch_issue_details(defect.defect_unique)
  next unless jira_data
  
  fields = jira_data['fields']
  changes = false
  
  # 1. Assignee
  if fields['assignee']
    assignee = find_or_create_user(fields['assignee'])
    if assignee
      current_ids = defect.user_ids
      unless current_ids.include?(assignee.id)
        defect.users = [assignee]
        changes = true
        log "    -> Set Assignee: #{assignee.name}"
      end
    end
  end
  
  # 2. Modules
  module_val = fields[MODULE_FIELD_ID]
  if module_val.present? && module_val.is_a?(Hash)
    parent_name = module_val['value']
    child_name = module_val['child'] ? module_val['child']['value'] : nil
    
    qa_module = find_or_create_module(parent_name)
    submodule = find_or_create_submodule(child_name, qa_module)
    
    if defect.qa_module_id != qa_module&.id || defect.submodule_id != submodule&.id
        defect.qa_module = qa_module
        defect.submodule = submodule
        changes = true
        log "    -> Set Module: #{parent_name} | #{child_name}"
    end
  end
  
  # 3. Dates
  j_created = DateTime.parse(fields['created'])
  j_updated = DateTime.parse(fields['updated'])
  
  if (defect.created_at.to_i - j_created.to_i).abs > 5
    defect.created_at = j_created 
    changes = true
  end
  if (defect.updated_at.to_i - j_updated.to_i).abs > 5
    defect.updated_at = j_updated
    changes = true
  end
  
  # 4. Description (Rich Text)
  if fields['description']
     html_content = ""
     if fields['description'].is_a?(Hash) && fields['description']['content']
       # Use Enhanced Converter
       html_content = convert_adf_to_html_enhanced(fields['description']['content'])
     elsif fields['description'].is_a?(String)
       html_content = fields['description']
     end
     
     # Check if content changed (simple string match might fail due to HTML gen differences, so valid update may happen)
     # We update if rich text body is different
     current_body = defect.content.body.to_s rescue ""
     
     if html_content.present? && current_body != html_content
        defect.content = html_content 
        changes = true
        log "    -> Updated Description (Rich Text)"
     end
  end

  # 5. Status
  if fields['status']
    status_name = fields['status']['name']
    if status_name.present?
      # Ensure status exists
      system_user_id = User.order(:created_at).first&.id || 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
      
      status = Status.where('lower(name) = ?', status_name.downcase).first
      unless status
         log "    -> Creating missing status: #{status_name}"
         status = Status.create!(name: status_name, user_id: system_user_id, created_by: system_user_id, modified_by: system_user_id)
      end
      
      if status && !defect.statuses.include?(status)
         defect.statuses = [status]
         changes = true
         log "    -> Set Status: #{status.name}"
      end
    end
  end

  unless options[:dry_run]
    if changes
      defect.save!(validate: false)
      log "    ✅ Saved changes."
    else
      log "    No changes."
    end
    
    # 5. Attachments (Always run check)
    sync_attachments(defect, fields['attachment'])
  else
    log "    [Dry Run] Changes detected: #{changes}"
  end
end
