# Audit Global Jira Comments
# Usage: bin/rails runner scripts/audit_jira_comments.rb

require 'net/http'
require 'json'
require 'uri'
require 'base64'

# Configuration
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_DOMAIN = 'craftsilicon.atlassian.net'
# Use config or fallbacks matching debug script
EMAIL = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] } 

def auth_header
  auth = Base64.strict_encode64("#{EMAIL}:#{API_TOKEN}")
  { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
end

def fetch_issue(key)
  url = URI("https://#{JIRA_DOMAIN}/rest/api/3/issue/#{key}")
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  req = Net::HTTP::Get.new(url, auth_header)
  res = http.request(req)
  
  if res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  else
    nil
  end
end

def extract_text_from_adf(content)
  return "" unless content
  text = ""
  if content.is_a?(Hash) && content['content']
    content['content'].each do |block|
      if block['type'] == 'paragraph' && block['content']
        block['content'].each do |node|
          text += node['text'] if node['type'] == 'text'
        end
        text += " "
      end
    end
  elsif content.is_a?(String)
    text = content
  end
  text.strip
end

# ===============================
# INTELLIGENT NAME MATCHING (9-STRATEGY)
# Copied from scripts/sync_defect_users_from_jira.rb
# ===============================

def find_user_by_intelligent_match(name_or_email)
  return nil if name_or_email.blank?

  name_str = name_or_email.to_s.strip
  
  # Strategy 1: Email matching
  if name_str.include?('@')
    email_str = name_str.downcase
    user = User.where(deleted_on: nil).find_by('lower(email) = ?', email_str)
    return user if user
    
    # Convert email prefix to name
    email_prefix = email_str.split('@').first
    name_str = email_prefix.gsub(/[._-]/, ' ').titleize
  # Strategy 1b: Username format
  elsif name_str.include?('.') || name_str.include?('_') || name_str.include?('-')
    name_str = name_str.gsub(/[._-]/, ' ').titleize
  end

  clean_name = name_str.gsub(/[^a-zA-Z\s.]/, ' ').squeeze(' ').strip
  parts = clean_name.split(/\s+/).reject(&:empty?)
  return nil if parts.empty?

  # Strategy 2: Exact full name match
  normalized = clean_name.downcase
  user = User.where(deleted_on: nil).where("lower(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) = ?", normalized).first
  return user if user

  # Strategy 3: First part is initial
  if parts.length >= 2
    first_part = parts[0]
    if first_part.length <= 2 && first_part.match?(/^[A-Z]\.?$/i)
      initial = first_part[0].upcase
      rest_name = parts[1..].join(' ')
      user = User.where(deleted_on: nil).where('upper(substring(first_name, 1, 1)) = ? AND lower(last_name) = ?', initial, rest_name.downcase).first
      return user if user
    end
  end

  # Strategy 4: Last part is initial
  if parts.length >= 2
    last_part = parts[-1]
    if last_part.length <= 2 && last_part.match?(/^[A-Z]\.?$/i)
      initial = last_part[0].upcase
      rest_name = parts[0..-2].join(' ')
      user = User.where(deleted_on: nil).where('lower(first_name) = ? AND upper(substring(last_name, 1, 1)) = ?', rest_name.downcase, initial).first
      return user if user
    end
  end

  # Strategy 5: Standard first + last
  if parts.length >= 2
    first = parts[0]
    last = parts[1..].join(' ')
    user = User.where(deleted_on: nil).where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase).first
    return user if user
    
    # Try reversed
    user = User.where(deleted_on: nil).where('lower(first_name) = ? AND lower(last_name) = ?', last.downcase, first.downcase).first
    return user if user
  end

  # Strategy 6: Partial match
  if parts.length >= 2
    first = parts[0]
    last_parts = parts[1..].join(' ')
    user = User.where(deleted_on: nil).where('lower(first_name) = ? AND lower(last_name) ILIKE ?', first.downcase, "%#{last_parts.downcase}%").first
    return user if user

    # Reverse
    user = User.where(deleted_on: nil).where('lower(first_name) ILIKE ? AND lower(last_name) = ?', "%#{first.downcase}%", last_parts.downcase).first
    return user if user
  end

  # Strategy 7: Multi-part matching
  if parts.length >= 3
    first_combo = parts[0..1].join(' ')
    last_combo = parts[2..].join(' ')
    user = User.where(deleted_on: nil).where('lower(first_name) ILIKE ? AND lower(last_name) ILIKE ?', "%#{first_combo.downcase}%", "%#{last_combo.downcase}%").first
    return user if user

    user = User.where(deleted_on: nil).where('lower(first_name) ILIKE ? AND lower(last_name) ILIKE ?', "%#{parts[0].downcase}%", "%#{parts[1..].join(' ').downcase}%").first
    return user if user
  end
  
  # Strategy 7b: Match on word combinations
  if parts.length >= 2
    first_word = parts.first.downcase
    last_word = parts.last.downcase
    User.where(deleted_on: nil).each do |u|
      user_full = "#{u.first_name} #{u.last_name}".downcase
      return u if user_full.include?(first_word) && user_full.include?(last_word)
    end
  end

  # Strategy 8: Single word match
  if parts.length == 1
    single = parts.first.downcase
    user = User.where(deleted_on: nil).where('lower(first_name) = ? OR lower(last_name) = ?', single, single).first
    return user if user
  end

  return nil
end

# ... (Logging setup remains below) ...

log_file = File.open('audit_comments.log', 'w')
log_file.sync = true
STDOUT.sync = true

def log(msg, file)
  puts msg
  file.puts msg
end

log "Starting Global Jira Comments Audit (Smart Match Enabled)...", log_file

# Find defects with format PROJECT-NUMBER (e.g. SMC-1, SJP-100)
defects = Defect.where("defect_unique ~ '^[A-Z]+-\\d+$'").order(:defect_unique)
log "Found #{defects.count} potential Jira defects locally.", log_file

defects.each_with_index do |defect, idx|
  log "Processing #{idx+1}/#{defects.count}: #{defect.defect_unique}..." , log_file if idx % 50 == 0

  jira_data = fetch_issue(defect.defect_unique)
  unless jira_data
    next
  end

  jira_comments = jira_data['fields']['comment']['comments'] rescue []
  local_messages = defect.defect_messages.includes(:user).where(archive_status: false)

  # 1. Audit Missing Comments
  jira_comments.each do |j_comment|
    j_author_name = j_comment['author']['displayName']
    j_body = extract_text_from_adf(j_comment['body'])
    j_created = DateTime.parse(j_comment['created'])
    
    found_match = false
    local_messages.each do |l_msg|
      l_body = l_msg.content.to_plain_text.strip
      l_author = l_msg.user.first_name + " " + (l_msg.user.last_name || "") rescue "Unknown"
      
      # Strict Time Match?
      time_diff = (l_msg.created_at.to_i - j_created.to_i).abs
      content_match = l_body.include?(j_body[0..20])
      
      if time_diff < 5 || content_match
         found_match = true
         
         # Check Author using Smart Match
         matched_user = find_user_by_intelligent_match(j_author_name)

         if matched_user
            if l_msg.user_id != matched_user.id
                log "[WRONG AUTHOR] #{defect.defect_unique}: Jira: '#{j_author_name}' (matched to #{matched_user.first_name} #{matched_user.last_name}) vs DB: '#{l_author}' (ID: #{l_msg.id})", log_file
            end
         else
            # Simple fallback check if smart match failed
             j_first = j_author_name.split(' ').first.downcase
             l_first = l_author.split(' ').first.downcase
             unless l_first == j_first || l_author.downcase.include?(j_first)
                log "[WRONG AUTHOR - NO MATCH] #{defect.defect_unique}: Jira: '#{j_author_name}' vs DB: '#{l_author}' (ID: #{l_msg.id})", log_file
             end
         end
      end
    end
    
    unless found_match
      log "[MISSING] #{defect.defect_unique}: Comment by #{j_author_name} @ #{j_created}", log_file
    end
  end

  # 2. Audit Duplicates
  # Group by content & author
  grouped = local_messages.group_by { |m| [m.content.to_plain_text.strip, m.user_id] }
  grouped.each do |key, msgs|
    if msgs.count > 1
      log "[DUPLICATE] #{defect.defect_unique}: Found #{msgs.count} copies of comment by User #{key[1]}", log_file
    end
  end

end

log "Audit Complete. Check audit_comments.log", log_file
log_file.close
