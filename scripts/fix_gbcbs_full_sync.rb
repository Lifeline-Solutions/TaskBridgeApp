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

PROJECT_KEY = 'GBCBS'
# Find product ID from existing GBCBS defect or fallback
existing_product_id = Defect.where("defect_unique LIKE 'GBCBS-%'").first&.product_id
PRODUCT_ID = existing_product_id || 'e618ac94-3d46-4e77-96c8-389d0a343652'

# JQL from User Request (Corrected to remove contradictory AND reporter=...)
JQL_QUERY = 'project = GBCBS AND issuetype = Defect AND status in ("BANK TO CLARIFY", "Blocked", "BLOCKED", "Closed", "CLOSED", "Deferred", "DEV TO CLARIFY", "FAILED-QA", "FIXED READY TO UPLOAD", "In Progress", "IN PROGRESS", "NEW REQUIREMENT", "NICE TO HAVE", "NOT A DEFECT", "ON HOLD", "On Hold", "On hold", "R & D", "READY FOR TEST - QA", "Testing- Support", "To Do", "UI") AND reporter in (5e4680753011ed0c8f8a5bed, 5d0deca321a5d30bc4e09e24, 5cdd42f8f593d10d74a6f29b, 5cb08478e5f5e936798c9f4e, 603e3a7dcc13b6006995a3a6, 5fb22cda47ac91006f45808f, 5d491c970fa6d40d14fc5a30, 606c6692ef87dd006853547c) ORDER BY reporter DESC, created DESC'

options = { dry_run: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/fix_gbcbs_full_sync.rb [options]'
  opts.on('--dry-run', 'Simulate changes (especially deletions)') { options[:dry_run] = true }
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_jql_keys(jql)
  keys = []
  next_page_token = nil
  max_results = 100

  loop do
    log "  Fetching JQL page..."
    uri = URI("#{JIRA_BASE_URL}/rest/api/3/search/jql")
    params = { jql: jql, maxResults: max_results, fields: 'key' }
    params[:nextPageToken] = next_page_token if next_page_token
    uri.query = URI.encode_www_form(params)

    req = Net::HTTP::Get.new(uri.request_uri)
    req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
    req['Content-Type'] = 'application/json'
    req['Accept'] = 'application/json'

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) { |http| http.request(req) }

    unless res.is_a?(Net::HTTPSuccess)
      log "  ❌ Error searching JIRA: #{res.code} #{res.message}"
      break
    end

    data = JSON.parse(res.body)
    issues = data['issues'] || []
    break if issues.empty?

    keys += issues.map { |i| i['key'] }
    
    next_page_token = data['nextPageToken']
    break if data['isLast']
    break unless next_page_token
  end
  keys
end

def fetch_issue_details(key)
  uri = URI("#{JIRA_BASE_URL}/rest/api/2/issue/#{key}?expand=changelog")
  req = Net::HTTP::Get.new(uri)
  req.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)
  req['Content-Type'] = 'application/json'
  req['Accept'] = 'application/json'

  retries = 0
  loop do
    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https')) { |http| http.request(req) }
      
      if res.is_a?(Net::HTTPSuccess)
        return JSON.parse(res.body)
      elsif res.code == '429' && retries < 5
        log "  ⚠️ Rate limited (429) on #{key}. Sleeping..."
        sleep(2 ** retries)
        retries += 1
        next
      else
        log "Error fetching #{key}: #{res.code} #{res.message}"
        return nil
      end
    rescue => e
      log "  ❌ Exception fetching #{key}: #{e.message}"
      return nil
    end
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

def sync_history(defect, changelog)
  return unless defect && changelog
  
  # Clear existing history to prevent duplicates and remove incorrect entries
  DefectHistory.where(defect_id: defect.id).destroy_all

  histories = changelog['histories'] || []
  histories.each do |history_item|
    author_data = history_item['author']
    user = find_or_create_user(author_data)
    created_at = DateTime.parse(history_item['created']) rescue Time.now

    history_item['items'].each do |item|
      field = item['field']
      from_string = item['fromString']
      to_string = item['toString']
      
      history_type = nil
      history_text = nil
      
      case field.downcase
      when 'assignee'
        history_type = 'Assignee Changed'
        history_text = "Assignee changed from #{from_string || 'Unassigned'} to #{to_string || 'Unassigned'} by #{user&.name || 'Unknown'}"
      when 'status'
        history_type = 'Status Changed'
        history_text = "Status changed from #{from_string} to #{to_string} by #{user&.name || 'Unknown'}"
      when 'priority'
        history_type = 'Priority Updated'
        history_text = "Priority changed from #{from_string} to #{to_string}"
      when 'description'
        history_type = 'Description Updated'
        history_text = "Description updated by #{user&.name || 'Unknown'}"
      when 'attachment'
        history_type = 'Attachment Added'
         # JIRA attachment history usually just says it was added. 
         # We can try to construct a message. item['to'] usually contains local ID, toString filename
         history_text = "Attachment #{to_string} added by #{user&.name || 'Unknown'}"
      end

      if history_type && history_text
        DefectHistory.create!(
          defect: defect, 
          user: user || User.first, # Fallback to prevent validation error
          history_type: history_type, 
          history: history_text, 
          created_at: created_at
        )
      end
    end
  end
end

def convert_jira_wiki_to_html(text)
  return "" if text.blank?

  # Escape HTML characters first
  html = CGI.escapeHTML(text)

  # 1. Colors {color:red}text{color} or {color:#hex}text{color}
  # The JIRA format is often {color:red} text {color}
  html.gsub!(/\{color:([^}]+)\}(.*?)\{color\}/m) do
    color = $1
    content = $2
    "<span style='color: #{color}'>#{content}</span>"
  end

  # 2. Text Effects
  html.gsub!(/\*([^*\n]+)\*/) { "<strong>#{$1}</strong>" } # *bold*
  html.gsub!(/\_([^\_\n]+)\_/) { "<em>#{$1}</em>" }       # _italic_
  html.gsub!(/\+([^\+\n]+)\+/) { "<u>#{$1}</u>" }         # +underline+
  html.gsub!(/\{\{([^}]+)\}\}/) { "<code>#{$1}</code>" }  # {{monospace}}
  
  # 3. Headings
  html.gsub!(/^h(\d)\.\s+(.*)$/) { "<h#{$1}>#{$2}</h#{$1}>" }

  # 4. Links [text|url] or [url]
  html.gsub!(/\[([^|\]]+)\|([^\]]+)\]/) { "<a href='#{$2}'>#{$1}</a>" }
  html.gsub!(/\[([^\]]+)\]/) do
    match = $1
    if match =~ URI::regexp
      "<a href='#{match}'>#{match}</a>"
    else
      match # It might be a citation or something else, leave as is if not URL
    end
  end

  # 5. Lists (Simple handling)
  # Convert * Item to <li>Item</li>, need to wrap in <ul> if multiple?
  # For simplicity, let's just use <br/> for newlines and maybe bullets to &bull;
  html.gsub!(/^(\*|-)\s+(.*)$/) { "<li>#{$2}</li>" }
  
  # 6. Newlines to <br>
  html.gsub!("\n", "<br>")

  html
end

MODULE_FIELD_ID = 'customfield_10103' # Corrected via inspection

log "Starting GBCBS Sync..."
log "Product ID resolving to: #{PRODUCT_ID}"

# 1. Fetch valid keys from JIRA
jira_keys = fetch_jql_keys(JQL_QUERY)
log "Found #{jira_keys.count} valid defects in JIRA."

# 2. Cleanup Local Defects
local_defects = Defect.where("defect_unique LIKE 'GBCBS-%'")
local_keys = local_defects.pluck(:defect_unique)

to_delete = local_keys - jira_keys
log "Found #{to_delete.count} local defects that are NOT in JIRA filter (to be deleted)."

if to_delete.any?
  if options[:dry_run]
    log "  [Dry Run] Would delete: #{to_delete.first(5).join(', ')}..."
  else
    log "  Deleting #{to_delete.count} defects..."
    Defect.where(defect_unique: to_delete).destroy_all
    log "  ✅ Deletion complete."
  end
end

# 3. Sync/Update Valid Defects
log "Syncing #{jira_keys.count} defects..."

jira_keys.each_with_index do |key, idx|
  log "[#{idx+1}/#{jira_keys.count}] Processing #{key}..."
  
  # Fetch full details including changelog
  jira_data = fetch_issue_details(key)
  unless jira_data
    log "  Skipping #{key} due to fetch error."
    next
  end

  # Sync History (Changelog)
  sync_history(Defect.find_by(defect_unique: key), jira_data['changelog']) if jira_data['changelog']


  fields = jira_data['fields']
  
  # Find or Initialize
  defect = Defect.with_deleted.find_or_initialize_by(defect_unique: key)
  
  # If it was deleted, restore it? The requirements imply strict sync.
  # If it's in the JIRA list, it should be present and active.
  if defect.deleted_on.present?
    log "  Restoring soft-deleted defect..."
    # defect.recover if defect.respond_to?(:recover)
    defect.deleted_on = nil
  end

  changes = false

  # Basic Fields
  defect.product_id = PRODUCT_ID
  defect.summary = fields['summary']
  defect.priority = fields['priority']['name'] if fields['priority']
  defect.issue_type = fields['issuetype']['name'] if fields['issuetype']
  
  # 1. Assignee
  if fields['assignee']
    assignee = find_or_create_user(fields['assignee'])
    if assignee
      current_ids = defect.user_ids
      unless current_ids.include?(assignee.id)
        defect.users = [assignee]
        changes = true
      end
    end
  end

  # Reporter (Creator)
  if fields['creator'] # JIRA 'creator' or 'reporter'? Filter says reporter. Let's use reporter for creator field often.
     # Usually map reporter -> created_by
     reporter_user = find_or_create_user(fields['reporter'])
     if reporter_user && defect.created_by != reporter_user.id
        defect.creator = reporter_user
        changes = true
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
    end
  end

  # 3. Dates
  j_created = DateTime.parse(fields['created'])
  j_updated = DateTime.parse(fields['updated'])
  
  if defect.created_at.nil? || (defect.created_at.to_i - j_created.to_i).abs > 5
    defect.created_at = j_created 
    changes = true
  end
  # We might not want to overwrite updated_at if we want local activity tracking, 
  # but for sync usually we respect JIRA. Reference script does it.
  if defect.updated_at.nil? || (defect.updated_at.to_i - j_updated.to_i).abs > 5
    defect.updated_at = j_updated
    changes = true
  end

  # 4. Description (Rich Text)
  if fields['description']
     html_content = ""
     if fields['description'].is_a?(Hash) && fields['description']['content']
       html_content = convert_adf_to_html_enhanced(fields['description']['content'])
     elsif fields['description'].is_a?(String)
       html_content = convert_jira_wiki_to_html(fields['description'])
     end
     
     current_body = defect.content.body.to_s rescue ""
     if html_content.present? && current_body != html_content
        defect.content = html_content 
        changes = true
     end
  end

  # 5. Status
  if fields['status']
    status_name = fields['status']['name']
    if status_name.present?
      system_user_id = User.order(:created_at).first&.id || 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
      
      # Normalize status name (e.g. "ON HOLD" -> "ON-HOLD")
      status_name_normalized = status_name.upcase == 'ON HOLD' ? 'ON-HOLD' : status_name

      status = Status.where('lower(name) = ?', status_name_normalized.downcase).first
      unless status
         log "    -> Creating missing status: #{status_name_normalized}"
         status = Status.create!(name: status_name_normalized, user_id: system_user_id, created_by: system_user_id, modified_by: system_user_id)
      end
      
      if status && !defect.statuses.include?(status)
         defect.statuses = [status]
         changes = true
      end
    end
  end

  if defect.new_record? || changes
    if options[:dry_run]
       log "  [Dry Run] Changes detected (New/Update)."
    else
       if defect.save(validate: false)
         # Attachments
         sync_attachments(defect, fields['attachment'])
         log "  ✅ Saved."
       else
         log "  ❌ Failed to save: #{defect.errors.full_messages.join(', ')}"
       end
    end
  else
    log "  No changes."
  end

end

log "[DONE] Sync complete."
