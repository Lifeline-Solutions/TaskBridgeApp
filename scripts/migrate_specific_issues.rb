#!/usr/bin/env ruby
# scripts/migrate_specific_issues.rb

ISSUES = %w[ISP-1698 ISP-1598 ISP-1503 ISP-1484].freeze
JQL = "key IN (#{ISSUES.join(', ')})".freeze

puts "=== STARTING MIGRATION FOR: #{ISSUES.join(', ')} ==="

# 1. Import (Create) Defects
puts "\n[STEP 1] Importing Missing Defects..."
cmd_import = "bin/rails runner scripts/production_import_erp.rb --jql '#{JQL}' --verbose"
puts "Running: #{cmd_import}"
system(cmd_import) || abort('Import failed!')

# 2. Fix/Sync Details & Comments (Ensure attachments and formatting)
puts "\n[STEP 2] Syncing Comments & Attachments..."
cmd_fix = "bin/rails runner scripts/fix_defect_details_and_comments.rb --defect-unique #{ISSUES.join(',')}"
puts "Running: #{cmd_fix}"
system(cmd_fix) || abort('Fix failed!')

puts "\n=== MIGRATION COMPLETE ==="
