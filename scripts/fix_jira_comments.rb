# Fix Global Jira Comments
# Usage: bin/rails runner scripts/fix_jira_comments.rb [--dry-run]

require 'net/http'
require 'json'
require 'uri'
require 'base64'
require 'optparse'

# Configuration
APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_DOMAIN = 'craftsilicon.atlassian.net'
# Use config or fallbacks matching debug script
EMAIL = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] } 

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: fix_jira_comments.rb [options]"
  opts.on("-d", "--dry-run", "Run without making changes") do |v|
    options[:dry_run] = v
  end
  opts.on("-s", "--specific DEFECT_ID", "Run for a specific defect only") do |v|
    options[:specific] = v
  end
end.parse!

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

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
    if user
      # log "  [1-MATCH-EMAIL] '#{name_str}' -> #{user.first_name} #{user.last_name}"
      return user
    end
    
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

def normalize_email(display_name)
  name_parts = display_name.to_s.strip.split(/[\s\.]+/)
  return "unknown.user-#{SecureRandom.hex(4)}@craftsilicon.com" if name_parts.empty?
  first = name_parts.first.gsub(/[^a-zA-Z0-9]/, '')
  last = name_parts.length > 1 ? name_parts.last.gsub(/[^a-zA-Z0-9]/, '') : ''
  email_local = last.present? ? "#{first}.#{last}" : first
  "#{email_local}@craftsilicon.com"
end

def find_or_create_user(jira_author)
  return nil unless jira_author
  
  display_name = jira_author['displayName']
  email = jira_author['emailAddress']
  
  # 1. Try Intelligent Match First
  user = find_user_by_intelligent_match(display_name)
  
  # 2. Try Email Match if explicit email provided
  if !user && email.present?
     user = User.where(deleted_on: nil).find_by('lower(email) = ?', email.downcase)
  end
  
  # 3. Create if not found
  unless user
    # Normalize email if missing
    if email.blank?
       email = normalize_email(display_name)
       # Double check normalized email doesn't exist
       user = User.find_by('lower(email) = ?', email.downcase)
    end
    
    unless user
        log "    -> [CREATE] Creating user: #{display_name} (#{email})"
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
  end
  user
end

log "Starting Jira Comments Fix... (Dry Run: #{options[:dry_run]})"

scope = if options[:specific]
          Defect.where(defect_unique: options[:specific])
        else
          Defect.where("defect_unique ~ '^[A-Z]+-\\d+$'").order(:defect_unique)
        end

scope.each_with_index do |defect, idx|
  log "Processing #{defect.defect_unique}..." if idx % 50 == 0

  jira_data = fetch_issue(defect.defect_unique)
  unless jira_data
    log "  [WARN] #{defect.defect_unique} not found in Jira."
    next
  end

  jira_comments = jira_data['fields']['comment']['comments'] rescue []
  local_messages = defect.defect_messages.where(archive_status: false).to_a # Load to array for modification

  jira_comments.each do |j_comment|
    j_body = extract_text_from_adf(j_comment['body'])
    j_author = find_or_create_user(j_comment['author'])
    j_created = DateTime.parse(j_comment['created'])
    
    next unless j_author # Should not happen with find_or_create

    # Find matches in local_messages
    matches = local_messages.select do |m|
      l_body = m.content.to_plain_text.strip
      time_diff = (m.created_at.to_i - j_created.to_i).abs
      # Match by content OR exact time (within 10s)
      l_body.include?(j_body[0..20]) || time_diff < 10
    end

    if matches.empty?
      # Missing Comment -> Create
      log "  [create] #{defect.defect_unique}: Adding comment by #{j_author.name}..."
      unless options[:dry_run]
        msg = defect.defect_messages.create!(
          user: j_author,
          content: j_body, # ActionText handles string assignment
          created_at: j_created,
          updated_at: j_created
        )
      end
      
    else
      # Matches found -> Check duplicates & integrity
      
      # 1. Deduplicate
      if matches.count > 1
        log "  [duplicates] #{defect.defect_unique}: Found #{matches.count} duplicates. keeping best match."
        
        # Prefer match with correct author
        best_match = matches.find { |m| m.user_id == j_author.id } || matches.first
        
        # Delete others
        matches.each do |m|
           next if m == best_match
           log "    -> Deleting duplicate ID: #{m.id}"
           m.destroy unless options[:dry_run]
           local_messages.delete(m) # Remove from memory list so we don't process again
        end
        matches = [best_match]
      end
      
      # 2. Fix Author/Timestamp
      match = matches.first
      updates = {}
      
      if match.user_id != j_author.id
        updates[:user_id] = j_author.id
        log "  [fix-author] #{defect.defect_unique}: ID #{match.id} -> #{j_author.name}"
      end
      
      if (match.created_at.to_i - j_created.to_i).abs > 2
        updates[:created_at] = j_created
        log "  [fix-date] #{defect.defect_unique}: ID #{match.id} -> #{j_created}"
      end
      
      if updates.any? && !options[:dry_run]
        match.update_columns(updates) # user update_columns to skip callbacks/timestamp update
      end
      
      # Remove handled message from local_messages list so we can see what's left
      local_messages.delete(match)
    end
    
  end

  # Remainder in local_messages are comments NOT in Jira.
  # We leave them alone (assumed new local comments).

end

log "Fix Complete."
