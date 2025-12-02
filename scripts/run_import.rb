#!/usr/bin/env ruby
# scripts/run_import.rb
#
# Proper script runner for Jira import with correct execution context
# Usage: rails runner scripts/run_import.rb --project KCBL [--dry-run] [--verbose]
#
# This script loads the import_jira_with_modules.rb script in the correct context
# to ensure all methods are properly defined before execution.

# Parse command line arguments BEFORE loading the main script
require 'optparse'

# Store original ARGV for parsing in the loaded script
ARGV_COPY = ARGV.dup

# Quick validation
if ARGV.empty? || !ARGV.any? { |arg| arg.include?('--project') }
  puts 'ERROR: --project is required. Examples:'
  puts '  rails runner scripts/run_import.rb --project PSP'
  puts '  rails runner scripts/run_import.rb --project PSP,KCBL,FLOW --verbose'
  puts '  rails runner scripts/run_import.rb --project KCBL --dry-run'
  exit 1
end

# Load the main import script
script_path = File.join(Rails.root, 'scripts', 'import_jira_with_modules.rb')

if !File.exist?(script_path)
  puts "ERROR: Import script not found at #{script_path}"
  exit 1
end

puts "Loading import script from: #{script_path}"

# Read and execute the script in the current context
# This ensures all methods and constants are properly loaded before execution
begin
  script_content = File.read(script_path)

  # Use eval with binding to execute in current context
  # This ensures method definitions happen before the main execution block
  eval(script_content, binding, script_path)

rescue SystemExit => e
  # Allow normal script exits
  exit e.status
rescue Interrupt
  puts "\n\nImport interrupted by user"
  exit 1
rescue StandardError => e
  puts "\n❌ FATAL ERROR: #{e.class} - #{e.message}"
  puts "\nFull backtrace:"
  puts e.backtrace.join("\n")
  exit 1
end

