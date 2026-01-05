#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'optparse'
require 'securerandom'

begin
  # Configuration Setup
  APP_ROOT = Rails.root
  config_path = APP_ROOT.join('config', 'jira_import.yml')
  CONFIG = YAML.load_file(config_path).with_indifferent_access

  JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
  JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
  JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

  PROJECT_KEY = 'SJP'.freeze

  options = {
    dry_run: false
  }

  OptionParser.new do |opts|
    opts.banner = 'Usage: rails runner scripts/fix_sjp_reporters.rb [options]'
    opts.on('--dry-run', 'Simulate changes') { options[:dry_run] = true }
  end.parse!

  def log(msg)
    puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
  end

  def normalize_email(display_name)
    # "First Last" -> "First.Last@craftsilicon.com"
    # "first.last" -> "First.Last@craftsilicon.com"
    name_parts = display_name.to_s.strip.split(/[\s.]+/)
    return "unknown.user-#{SecureRandom.hex(4)}@craftsilicon.com" if name_parts.empty?

    first = name_parts.first.gsub(/[^a-zA-Z0-9]/, '')
    last = name_parts.length > 1 ? name_parts.last.gsub(/[^a-zA-Z0-9]/, '') : ''

    email_local = last.present? ? "#{first}.#{last}" : first
    "#{email_local}@craftsilicon.com"
  end

  log "Starting SJP Reporter Fix (Dry Run: #{options[:dry_run]})"

  defects = Defect.where('defect_unique LIKE ?', "#{PROJECT_KEY}-%")
  log "Found #{defects.count} defects to check."

  stats = { updated: 0, created_users: 0, skipped: 0, errors: 0 }

  # Cache users to avoid repeated DB lookups
  user_cache = {} # email -> user
  name_cache = {} # display_name -> user

  defects.find_each do |defect|
    # Fetch from Jira
    url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{defect.defect_unique}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    request = Net::HTTP::Get.new(uri.request_uri)
    request['Accept'] = 'application/json'
    request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      log "Failed to fetch #{defect.defect_unique}: #{response.code}"
      stats[:errors] += 1
      next
    end

    issue = JSON.parse(response.body)
    reporter_data = issue['fields'] ? issue['fields']['reporter'] : nil

    unless reporter_data
      # log "  #{defect.defect_unique}: No reporter data in Jira. Skipping."
      stats[:skipped] += 1
      next
    end

    display_name = reporter_data['displayName']
    jira_email = reporter_data['emailAddress']

    # Logic to identify target user
    user = nil

    # 1. Try finding by Jira Email
    user = user_cache[jira_email.downcase] ||= User.find_by('lower(email) = ?', jira_email.downcase) if jira_email.present?

    # 2. Try constructed email
    constructed_email = normalize_email(display_name)
    user ||= user_cache[constructed_email.downcase] ||= User.find_by('lower(email) = ?', constructed_email.downcase)

    # 3. Try finding by Name (handling dots and variations)
    if !user && display_name.present?
      clean_name = display_name.tr('.', ' ').strip
      # Safe concatenation
      user = name_cache[display_name.downcase] ||= User.where("lower(first_name) || ' ' || lower(last_name) = ?", clean_name.downcase).first

      # Fallback to name column just in case
      user ||= begin
        User.where('lower(name) = ?', clean_name.downcase).first
      rescue StandardError
        nil
      end
    end

    # Create user if missing
    if user.nil?
      log "  User not found for '#{display_name}' (#{jira_email}). creating as #{constructed_email}"

      parts = display_name.split(/[\s.]+/, 2)
      first_name = parts[0]
      last_name = parts[1] || ''

      if options[:dry_run]
        log "    [Dry Run] Would create user #{constructed_email} (Active: false)"
        # Mock user for dry run
        user = User.new(id: 'mock-id', email: constructed_email, first_name: first_name, last_name: last_name)
      else
        password = SecureRandom.hex(12)
        user = User.new(
          first_name: first_name,
          last_name: last_name,
          email: constructed_email,
          password: password,
          password_confirmation: password,
          active: false, # Disabled as requested
          confirmed_at: Time.now
        )

        if user.save
          log "    ✅ Created user #{user.email} (Active: false)"
          stats[:created_users] += 1
          user_cache[user.email.downcase] = user
        else
          log "    ❌ Failed to create user: #{user.errors.full_messages.join(', ')}"
          stats[:errors] += 1
          next
        end
      end
    end

    # Check if update needed
    # Compare with current created_by / creator_id
    updated_needed = if user.id == 'mock-id'
                       true
                     else
                       defect.created_by != user.id || defect.creator_id != user.id
                     end

    if updated_needed
      current_reporter_name = defect.creator ? defect.creator.name : (defect.creator_id || 'Nil')

      log "  #{defect.defect_unique}: Updating Reporter"
      log "    Jira: #{display_name} (#{jira_email})"
      log "    Current DB: #{current_reporter_name}"
      log "    New User: #{display_name} (#{user.email})"

      if options[:dry_run]
        stats[:updated] += 1
      else
        # Update both columns
        defect.created_by = user.id
        defect.creator_id = user.id
        if defect.save
          log '    ✅ Updated'
          stats[:updated] += 1
        else
          log "    ❌ Failed to update defect: #{defect.errors.full_messages.join(', ')}"
          stats[:errors] += 1
        end
      end
    else
      # log "  #{defect.defect_unique}: Match. Skipping."
      stats[:skipped] += 1
    end
  rescue StandardError => e
    log "ERROR processing #{defect.defect_unique}: #{e.message}"
    log e.backtrace.join("\n")
    stats[:errors] += 1
  end

  log "Done! Updated: #{stats[:updated]}, Created Users: #{stats[:created_users]}, Skipped: #{stats[:skipped]}, Errors: #{stats[:errors]}"
rescue StandardError => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end
