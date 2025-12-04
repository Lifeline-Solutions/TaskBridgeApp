#!/usr/bin/env ruby
# scripts/verify_and_fix_user_assignments.rb
#
# This script verifies and fixes user assignments on imported defects.
# It checks if the reporter and assignee match between Jira and the local database.
# If they don't match, it attempts to reconcile them using enhanced name parsing.

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'yaml'

puts '=' * 80
puts 'JIRA USER ASSIGNMENT VERIFICATION & RECONCILIATION'
puts '=' * 80
puts ''

APP_ROOT = Rails.root
config_path = APP_ROOT.join('config', 'jira_import.yml')

unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

DEFAULT_USER_UUID = CONFIG[:default_user_uuid]

def parse_jira_name(name_str)
  return { first_name: nil, last_name: nil } if name_str.blank?

  # Handle dot-separated format (e.g., "archana.verma")
  if name_str.include?('.')
    parts = name_str.split('.')
    return {
      first_name: parts.first.strip,
      last_name: parts.last.strip,
      strategy: 'dot-separated'
    }
  end

  # Handle multi-part names (3+ parts) - use first two
  parts = name_str.split
  if parts.length >= 3
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'multi-part-first-two'
    }
  elsif parts.length == 2
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'two-part'
    }
  elsif parts.length == 1
    return {
      first_name: parts[0].strip,
      last_name: nil,
      strategy: 'single-part'
    }
  end

  { first_name: nil, last_name: nil, strategy: 'failed-parse' }
end

def find_user_by_parsed_name(first_name, last_name)
  return nil unless first_name

  if first_name && last_name
    # Try exact match
    user = User.where('LOWER(first_name) = ? AND LOWER(last_name) = ?', first_name.downcase, last_name.downcase).first
    return user if user

    # Try partial match (first exact, last prefix)
    user = User.where('LOWER(first_name) = ? AND LOWER(last_name) LIKE ?', first_name.downcase, "#{last_name.downcase}%").first
    return user if user

    # Try reverse partial (last exact, first prefix)
    user = User.where('LOWER(last_name) = ? AND LOWER(first_name) LIKE ?', last_name.downcase, "#{first_name.downcase}%").first
    return user if user
  elsif first_name
    # Single name - try both first and last
    user = User.where('LOWER(first_name) = ? OR LOWER(last_name) = ?', first_name.downcase, first_name.downcase).first
    return user if user
  end

  nil
end

def fetch_jira_issue(issue_key)
  uri = URI.parse("#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}")

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60
  http.open_timeout = 30

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  return nil unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
rescue StandardError => e
  puts "ERROR fetching #{issue_key}: #{e.message}"
  nil
end

# ===============================
# MAIN VERIFICATION LOGIC
# ===============================

stats = {
  total_defects: 0,
  reporter_correct: 0,
  reporter_fixed: 0,
  reporter_could_not_fix: 0,
  assignee_correct: 0,
  assignee_fixed: 0,
  assignee_could_not_fix: 0,
  errors: 0
}

mismatches = {
  reporter: [],
  assignee: []
}

puts "Starting verification of #{Defect.count} defects..."
puts ''

Defect.find_each(batch_size: 100) do |defect|
  stats[:total_defects] += 1

  begin
    issue_key = defect.defect_unique
    next unless issue_key.present?

    # Fetch Jira issue data
    jira_issue = fetch_jira_issue(issue_key)
    next unless jira_issue

    fields = jira_issue['fields'] || {}

    # Get reporter info
    jira_reporter_name = fields.dig('reporter', 'displayName').to_s.strip
    jira_reporter_email = fields.dig('reporter', 'emailAddress').to_s.strip

    # Get assignee info
    jira_assignee_name = fields.dig('assignee', 'displayName').to_s.strip
    jira_assignee_email = fields.dig('assignee', 'emailAddress').to_s.strip

    # ===============================
    # Check Reporter
    # ===============================
    defect_creator = defect.creator || defect.created_by_user

    if jira_reporter_name.present?
      # Try to find the user using parsed name
      parsed = parse_jira_name(jira_reporter_name)
      correct_user = find_user_by_parsed_name(parsed[:first_name], parsed[:last_name])

      if correct_user
        if defect_creator&.id == correct_user.id
          stats[:reporter_correct] += 1
        else
          # Mismatch detected
          puts "⚠️  REPORTER MISMATCH: #{issue_key}"
          puts "   Jira: #{jira_reporter_name} (#{jira_reporter_email})"
          puts "   Expected user: #{correct_user.first_name} #{correct_user.last_name} (#{correct_user.id})"
          puts "   Current user: #{defect_creator&.first_name} #{defect_creator&.last_name} (#{defect_creator&.id})"

          # Attempt to fix
          begin
            if defect.respond_to?(:creator_id=)
              defect.creator_id = correct_user.id
              defect.save!
              stats[:reporter_fixed] += 1
              puts '   ✅ FIXED'
            else
              stats[:reporter_could_not_fix] += 1
              puts '   ❌ Cannot update creator_id field'
            end
          rescue StandardError => e
            stats[:reporter_could_not_fix] += 1
            puts "   ❌ Error updating: #{e.message}"
          end
          mismatches[:reporter] << { issue: issue_key, jira_name: jira_reporter_name, expected_user_id: correct_user.id, actual_user_id: defect_creator&.id }
        end
      end
    end

    # ===============================
    # Check Assignee
    # ===============================
    defect_assignee = defect.users.first

    if jira_assignee_name.present?
      # Try to find the user using parsed name
      parsed = parse_jira_name(jira_assignee_name)
      correct_user = find_user_by_parsed_name(parsed[:first_name], parsed[:last_name])

      if correct_user
        if defect_assignee&.id == correct_user.id
          stats[:assignee_correct] += 1
        else
          # Mismatch detected
          puts "⚠️  ASSIGNEE MISMATCH: #{issue_key}"
          puts "   Jira: #{jira_assignee_name} (#{jira_assignee_email})"
          puts "   Expected user: #{correct_user.first_name} #{correct_user.last_name} (#{correct_user.id})"
          puts "   Current user: #{defect_assignee&.first_name} #{defect_assignee&.last_name} (#{defect_assignee&.id})"

          # Attempt to fix
          begin
            defect.user_ids = [correct_user.id]
            stats[:assignee_fixed] += 1
            puts '   ✅ FIXED'
          rescue StandardError => e
            stats[:assignee_could_not_fix] += 1
            puts "   ❌ Error updating: #{e.message}"
          end
          mismatches[:assignee] << { issue: issue_key, jira_name: jira_assignee_name, expected_user_id: correct_user.id, actual_user_id: defect_assignee&.id }
        end
      end
    end

    sleep 0.5 # Rate limiting to avoid Jira API overload
  rescue StandardError => e
    stats[:errors] += 1
    puts "ERROR processing #{defect.defect_unique}: #{e.class}: #{e.message}"
  end
end

# ===============================
# FINAL REPORT
# ===============================
puts ''
puts '=' * 80
puts 'VERIFICATION & RECONCILIATION REPORT'
puts '=' * 80
puts ''

puts 'Reporter Verification:'
puts "  ✅ Correct: #{stats[:reporter_correct]}"
puts "  🔧 Fixed: #{stats[:reporter_fixed]}"
puts "  ❌ Could not fix: #{stats[:reporter_could_not_fix]}"
puts ''

puts 'Assignee Verification:'
puts "  ✅ Correct: #{stats[:assignee_correct]}"
puts "  🔧 Fixed: #{stats[:assignee_fixed]}"
puts "  ❌ Could not fix: #{stats[:assignee_could_not_fix]}"
puts ''

puts 'Summary:'
puts "  Total defects checked: #{stats[:total_defects]}"
puts "  Total fixed: #{stats[:reporter_fixed] + stats[:assignee_fixed]}"
puts "  Errors encountered: #{stats[:errors]}"
puts ''

if mismatches[:reporter].any?
  puts "Reporter Mismatches (#{mismatches[:reporter].length}):"
  mismatches[:reporter].each do |m|
    puts "  - #{m[:issue]}: Jira='#{m[:jira_name]}' Expected=#{m[:expected_user_id]} Actual=#{m[:actual_user_id]}"
  end
  puts ''
end

if mismatches[:assignee].any?
  puts "Assignee Mismatches (#{mismatches[:assignee].length}):"
  mismatches[:assignee].each do |m|
    puts "  - #{m[:issue]}: Jira='#{m[:jira_name]}' Expected=#{m[:expected_user_id]} Actual=#{m[:actual_user_id]}"
  end
  puts ''
end

puts '=' * 80
puts 'Verification complete!'
puts '=' * 80
