require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'cgi'
require 'date'

# Configuration
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', nil)
JIRA_API_USER = ENV.fetch('JIRA_API_USER', nil)
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN', nil)
PRODUCT_ID = 'daca16f6-0ca6-45f7-a40d-a948b576cd71'.freeze # GBCBS Product ID

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def fetch_issue_data(key)
  base_url = ENV.fetch('JIRA_BASE_URL', nil)
  log "DEBUG: JIRA_BASE_URL=[#{base_url}]"

  url = "#{base_url}/rest/api/2/issue/#{key}?expand=changelog"
  log "DEBUG: Requesting URL=[#{url}]"

  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    log "❌ Invalid URI scheme: #{uri.scheme}"
    return nil
  end

  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Basic #{Base64.strict_encode64("#{JIRA_API_USER}:#{JIRA_API_TOKEN}")}"
  request['Content-Type'] = 'application/json'

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if response.code == '200'
    JSON.parse(response.body)
  else
    log "❌ Failed to fetch #{key}: #{response.code}"
    nil
  end
end

def find_or_create_system_user
  email = 'jira.system@craftsilicon.com'
  user = User.find_by(email: email)
  unless user
    password = SecureRandom.hex(12)
    user = User.create!(
      first_name: 'Jira',
      last_name: 'System',
      email: email,
      password: password,
      password_confirmation: password,
      active: false,
      confirmed_at: Time.now
    )
  end
  user
end

def normalize_email(display_name)
  return nil if display_name.blank?

  parts = display_name.split
  return nil if parts.empty?

  if parts.length == 1
    # "FirstName" -> "firstname@craftsilicon.com"
    "#{parts[0].downcase}@craftsilicon.com"
  else
    # "First Last" -> "first.last@craftsilicon.com"
    "#{parts[0].downcase}.#{parts[1].downcase}@craftsilicon.com"
  end
end

def find_or_create_user(jira_user_data)
  return find_or_create_system_user unless jira_user_data

  email = jira_user_data['emailAddress']
  display_name = jira_user_data['displayName']

  email = normalize_email(display_name) if email.blank?

  user = User.find_by('lower(email) = ?', email.downcase)

  unless user
    log "    -> [CREATE] Creating DISABLED user: #{display_name} (#{email})"
    password = SecureRandom.hex(12)
    user = User.new(
      first_name: display_name.split.first,
      last_name: display_name.split.drop(1).join(' '),
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

def sync_history(defect, changelog)
  return unless defect && changelog

  log "  Found #{changelog['histories'].size} history entries."

  # Clear existing history
  DefectHistory.where(defect_id: defect.id).destroy_all

  histories = changelog['histories'] || []
  histories.each do |history_item|
    history_item['items'].each do |item|
      field = item['field']
      log "    Processing field: '#{field}' (Type: #{item['fieldtype']})"

      from_string = item['fromString']
      to_string = item['toString']

      # Determine User
      author_data = history_item['author']
      user = find_or_create_user(author_data)
      history_user = user # Strict usage

      created_at = begin
        DateTime.parse(history_item['created'])
      rescue StandardError
        Time.now
      end

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
      when 'summary'
        history_type = 'Summary Updated'
        history_text = "Summary updated from \"#{from_string}\" to \"#{to_string}\""
      when 'resolution'
        history_type = 'Resolution Changed'
        history_text = "Resolution changed from #{from_string || 'Unresolved'} to #{to_string}"
      when 'parent'
        history_type = 'Parent Changed'
        history_text = "Parent changed from #{from_string || 'None'} to #{to_string || 'None'}"
      when 'link', 'issuelink'
        history_type = 'Link Changed'
        history_text = "Link #{to_string} #{from_string ? 'removed' : 'added'}"
      when 'attachment'
        history_type = 'Attachment Added'
        history_text = "Attachment #{to_string} added by #{user&.name || 'Unknown'}"
      end

      if history_type
        log "      ✅ matched type: #{history_type}"
        DefectHistory.create!(
          defect: defect,
          user: history_user,
          history_type: history_type,
          history: history_text,
          created_at: created_at
        )
      else
        log "      ⚠️ Ignored field: #{field}"
      end
    end
  end
end

# Main Execution
target_keys = %w[GBCBS-3258 GBCBS-2716]

target_keys.each do |key|
  log '---------------------------------------------------'
  log "debugging #{key}..."

  data = fetch_issue_data(key)
  next unless data

  # Ensure defect exists locally
  defect = Defect.find_by(defect_unique: key)
  unless defect
    log "Defect #{key} not found locally! Creating dummy..."
    # Ideally we expect it to exist, but for debug we might need to skip
    next
  end

  # Perform Sync
  sync_history(defect, data['changelog'])

  # Verify
  log "Verification for #{key}:"
  defect.reload.defect_histories.order(created_at: :desc).each do |h|
    log "  - [#{h.created_at}] #{h.history_type}: #{h.history} (User: #{h.user.name})"
  end
end
