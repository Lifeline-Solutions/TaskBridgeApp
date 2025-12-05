#!/usr/bin/env ruby
# scripts/run_jira_import.rb
#
# Direct Jira import runner - use this to import Jira issues
# Usage: rails runner scripts/run_jira_import.rb --project KCBL [--dry-run] [--verbose]
# Examples:
#   rails runner scripts/run_jira_import.rb --project KCBL
#   rails runner scripts/run_jira_import.rb --project KCBL,PSP --verbose
#   rails runner scripts/run_jira_import.rb --project KCBL --dry-run

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'optparse'
require 'yaml'
require 'base64'

APP_ROOT = Rails.root

options = {
  dry_run: false,
  verbose: false,
  projects: [],
  days_back: 2000
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/run_jira_import.rb --project PROJECT_KEY [options]'

  opts.on('--project KEY1,KEY2,...', Array, 'Jira project key(s) (e.g. PSP or PSP,KCBL,FLOW)') { |v| options[:projects] = v }
  opts.on('--dry-run', "Don't save; only show what would happen") { options[:dry_run] = true }
  opts.on('--verbose', 'Verbose logging') { options[:verbose] = true }
  opts.on('--days N', Integer, 'How many days back to fetch (default 2000)') { |v| options[:days_back] = v }
end.parse!

if options[:projects].empty?
  puts 'ERROR: --project is required. Examples:'
  puts '  Single project:   --project PSP'
  puts '  Multiple projects: --project PSP,KCBL,FLOW'
  exit 1
end

# Now load the main import script
begin
  script_path = APP_ROOT.join('scripts', 'import_jira_with_modules.rb')
  exec "ruby #{script_path} #{ARGV.join(' ')}"
rescue StandardError => e
  puts "ERROR: Failed to execute import script: #{e.message}"
  exit 1
end
