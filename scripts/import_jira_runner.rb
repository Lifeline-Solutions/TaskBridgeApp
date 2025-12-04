#!/usr/bin/env ruby
# scripts/import_jira_runner.rb
#
# Wrapper script to run import_jira_with_modules.rb with proper error handling
# Run with: rails runner scripts/import_jira_runner.rb --project KCBL

# Ensure we can execute the script in this context
begin
  script_path = File.join(Rails.root, 'scripts', 'import_jira_with_modules.rb')

  # Read and eval the script to ensure all methods are defined in main context
  script_content = File.read(script_path)
  eval(script_content, binding, script_path)
rescue SystemExit => e
  # Allow normal script exits (exit 0 or exit 1)
  exit e.status
rescue Interrupt
  # Allow Ctrl+C to gracefully exit
  puts "\n\nImport interrupted by user"
  exit 1
rescue StandardError => e
  # Catch any errors from the script
  puts "\n❌ FATAL ERROR: #{e.class} - #{e.message}"
  puts "\nBacktrace (first 20 lines):"
  puts e.backtrace.first(20).join("\n")
  exit 1
end
