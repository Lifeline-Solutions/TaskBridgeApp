# Audit SMC Comments
# Usage: bin/rails runner scripts/audit_smc_comments.rb

require 'net/http'
require 'json'
require 'uri'
require 'base64'

# Configuration
JIRA_DOMAIN = 'craftsilicon.atlassian.net'.freeze
EMAIL = 'robert.kanyoro@craftsilicon.com'.freeze
API_TOKEN = 'ATATT3xFfGF0h7S_c46b5k_YyCjhE-tD0vF02L1vF6yQ1hA4yG8_1x5C4hG3jK2lF9vD5nB7mJ4h-4A3sD2fG6hH8jK1lZ9xC3vB5n'.freeze # Placeholder, will use ENV or hardcoded in previous scripts
PROJECT_KEY = 'SMC'.freeze

# Auth Header
def auth_header
  token = 'ATATT3xFfGF0h7S_c46b5k_YyCjhE-tD0vF02L1vF6yQ1hA4yG8_1x5C4hG3jK2lF9vD5nB7mJ4h-4A3sD2fG6hH8jK1lZ9xC3vB5n' # Replace with actual if needed from other scripts
  auth = Base64.strict_encode64("#{EMAIL}:#{token}")
  { 'Authorization' => "Basic #{auth}", 'Content-Type' => 'application/json' }
end

def fetch_issue(key)
  url = URI("https://#{JIRA_DOMAIN}/rest/api/3/issue/#{key}")
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  req = Net::HTTP::Get.new(url, auth_header)
  res = http.request(req)

  return unless res.is_a?(Net::HTTPSuccess)

  JSON.parse(res.body)
end

def extract_text_from_adf(content)
  return '' unless content

  text = ''
  if content.is_a?(Hash) && content['content']
    content['content'].each do |block|
      next unless block['type'] == 'paragraph' && block['content']

      block['content'].each do |node|
        text += node['text'] if node['type'] == 'text'
      end
      text += ' '
    end
  elsif content.is_a?(String)
    text = content
  end
  text.strip
end

log_file = File.open('audit_comments.log', 'w')
def log(msg, file)
  puts msg
  file.puts msg
end

log 'Starting SMC Comments Audit...', log_file

defects = Defect.where("defect_unique LIKE 'SMC-%'").order(:defect_unique)
log "Found #{defects.count} SMC defects locally.", log_file

defects.each do |defect|
  jira_data = fetch_issue(defect.defect_unique)
  unless jira_data
    log "[MISSING JIRA] #{defect.defect_unique}: Could not fetch from Jira", log_file
    next
  end

  jira_comments = begin
    jira_data['fields']['comment']['comments']
  rescue StandardError
    []
  end
  local_messages = defect.defect_messages.where(archive_status: false)

  # 1. Count Mismatch
  log "[COUNT MISMATCH] #{defect.defect_unique}: Jira(#{jira_comments.count}) vs DB(#{local_messages.count})", log_file if jira_comments.count != local_messages.count

  # 2. Author & Content Audit
  jira_comments.each do |j_comment|
    j_author_name = j_comment['author']['displayName']
    j_body = extract_text_from_adf(j_comment['body'])

    # Attempt to find matching local message (fuzzy match on body, exact on author?)
    # Since body might differ slightly due to ADF conversion, we look for messages by this author
    # or messages with similar content.

    found_match = false
    local_messages.each do |l_msg|
      l_body = l_msg.content.to_plain_text.strip
      l_author = begin
        "#{l_msg.user.first_name} #{l_msg.user.last_name}"
      rescue StandardError
        'Unknown'
      end

      # Simple content inclusion check (first 20 chars)
      next unless l_body.include?(j_body[0..20])

      found_match = true
      # Check Author
      log "[WRONG AUTHOR] #{defect.defect_unique}: Comment '#{j_body[0..30]}...' | Jira: #{j_author_name} | DB: #{l_author}", log_file unless l_author.downcase.include?(j_author_name.split.first.downcase)
    end

    log "[MISSING COMMENT] #{defect.defect_unique}: Jira comment by #{j_author_name} not found in DB.", log_file unless found_match
  end

  # 3. Duplicate Local Comments
  next unless local_messages.count > jira_comments.count

  bodies = local_messages.map { |m| m.content.to_plain_text.strip }
  duplicates = bodies.select { |b| bodies.count(b) > 1 }.uniq
  log "[DUPLICATES] #{defect.defect_unique}: Found #{duplicates.count} duplicate contents.", log_file if duplicates.any?
end

log 'Audit Complete.', log_file
log_file.close
