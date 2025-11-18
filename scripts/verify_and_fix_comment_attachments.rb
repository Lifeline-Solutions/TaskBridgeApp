#!/usr/bin/env ruby
# scripts/verify_and_fix_comment_attachments.rb
# Verify and optionally fix comment-level attachments for defects

require 'optparse'

options = {
  verbose: false,
  fix: false,
  defect_id: nil,
  defect_unique: nil,
  check_all: false
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner scripts/verify_and_fix_comment_attachments.rb [options]'

  opts.on('--defect-id ID', 'Check specific defect by ID') { |v| options[:defect_id] = v }
  opts.on('--defect-unique KEY', 'Check specific defect by unique key (e.g., PSP-123)') { |v| options[:defect_unique] = v }
  opts.on('--check-all', 'Check all defects with comments') { options[:check_all] = true }
  opts.on('--fix', 'Attempt to fix missing attachments (requires re-download from Jira)') { options[:fix] = true }
  opts.on('--verbose', 'Verbose output') { options[:verbose] = true }
end.parse!

puts '=' * 80
puts 'Comment-Level Attachment Verification'
puts '=' * 80
puts ''

# Determine which defects to check
defects = if options[:defect_id]
            Defect.where(id: options[:defect_id])
          elsif options[:defect_unique]
            Defect.where(defect_unique: options[:defect_unique])
          elsif options[:check_all]
            Defect.joins(:defect_messages).distinct
          else
            puts 'ERROR: Please specify --defect-id, --defect-unique, or --check-all'
            exit 1
          end

if defects.none?
  puts 'No defects found matching criteria.'
  exit 0
end

puts "Checking #{defects.count} defect(s)..."
puts ''

overall_stats = {
  defects_checked: 0,
  defects_with_comments: 0,
  total_comments: 0,
  comments_with_attachments: 0,
  total_attachment_records: 0,
  verified_attachments: 0,
  missing_attachments: 0,
  defects_with_issues: []
}

defects.find_each do |defect|
  overall_stats[:defects_checked] += 1

  messages = defect.defect_messages.includes(attachments_attachments: :blob)

  next if messages.none?

  overall_stats[:defects_with_comments] += 1
  overall_stats[:total_comments] += messages.count

  defect_stats = {
    comments: messages.count,
    comments_with_attachments: 0,
    total_files: 0,
    verified_files: 0,
    missing_files: []
  }

  messages.each do |message|
    next if message.attachments.none?

    defect_stats[:comments_with_attachments] += 1
    overall_stats[:comments_with_attachments] += 1

    message.attachments.each do |attachment|
      defect_stats[:total_files] += 1
      overall_stats[:total_attachment_records] += 1

      filename = attachment.filename.to_s
      blob = attachment.blob

      begin
        exists = ActiveStorage::Blob.service.exist?(blob.key)

        if exists
          defect_stats[:verified_files] += 1
          overall_stats[:verified_attachments] += 1

          puts "  ✅ #{defect.defect_unique} - Comment #{message.id}: #{filename} (#{blob.byte_size} bytes)" if options[:verbose]
        else
          defect_stats[:missing_files] << {
            message_id: message.id,
            filename: filename,
            blob_key: blob.key,
            size: blob.byte_size
          }
          overall_stats[:missing_attachments] += 1

          puts "  ❌ #{defect.defect_unique} - Comment #{message.id}: #{filename} - FILE MISSING FROM STORAGE"
        end
      rescue StandardError => e
        defect_stats[:missing_files] << {
          message_id: message.id,
          filename: filename,
          blob_key: blob&.key || 'N/A',
          error: e.message
        }
        overall_stats[:missing_attachments] += 1

        puts "  ❌ #{defect.defect_unique} - Comment #{message.id}: #{filename} - ERROR: #{e.message}"
      end
    end
  end

  # Report defect-level summary if there are issues
  if defect_stats[:missing_files].any?
    overall_stats[:defects_with_issues] << {
      defect: defect,
      stats: defect_stats
    }

    puts ''
    puts "📋 DEFECT: #{defect.defect_unique} (ID: #{defect.id})"
    puts "   Comments: #{defect_stats[:comments]} total, #{defect_stats[:comments_with_attachments]} with attachments"
    puts "   Attachments: #{defect_stats[:verified_files]}/#{defect_stats[:total_files]} verified"
    puts "   ⚠️  Missing: #{defect_stats[:missing_files].length} file(s)"

    defect_stats[:missing_files].each do |missing|
      puts "      - #{missing[:filename]} (message #{missing[:message_id]})"
    end
    puts ''
  elsif options[:verbose] && defect_stats[:total_files] > 0
    puts "✅ #{defect.defect_unique}: All #{defect_stats[:total_files]} attachment(s) verified"
  end
end

# Overall summary
puts ''
puts '=' * 80
puts 'SUMMARY'
puts '=' * 80
puts "Defects checked: #{overall_stats[:defects_checked]}"
puts "Defects with comments: #{overall_stats[:defects_with_comments]}"
puts "Total comments: #{overall_stats[:total_comments]}"
puts "Comments with attachments: #{overall_stats[:comments_with_attachments]}"
puts ''
puts "Total attachment records: #{overall_stats[:total_attachment_records]}"
puts "Verified in storage: #{overall_stats[:verified_attachments]} (#{overall_stats[:total_attachment_records] > 0 ? ((overall_stats[:verified_attachments].to_f / overall_stats[:total_attachment_records]) * 100).round(2) : 0}%)"
puts "Missing from storage: #{overall_stats[:missing_attachments]} (#{overall_stats[:total_attachment_records] > 0 ? ((overall_stats[:missing_attachments].to_f / overall_stats[:total_attachment_records]) * 100).round(2) : 0}%)"
puts ''

if overall_stats[:defects_with_issues].any?
  puts "⚠️  #{overall_stats[:defects_with_issues].length} defect(s) have missing comment attachments:"
  overall_stats[:defects_with_issues].each do |issue|
    puts "   - #{issue[:defect].defect_unique}: #{issue[:stats][:missing_files].length} missing file(s)"
  end
  puts ''

  if options[:fix]
    puts '=' * 80
    puts 'FIX MODE: Attempting to re-import missing attachments'
    puts '=' * 80
    puts ''
    puts 'NOTE: This feature requires the import_jira_with_modules.rb script to be updated'
    puts 'with the ability to re-download specific attachments from Jira.'
    puts ''
    puts 'Recommended approach:'
    puts '1. Re-run the full import for affected defects:'
    puts '   rails runner scripts/import_jira_with_modules.rb --project <KEY> --verbose'
    puts ''
    puts '2. The import script will:'
    puts '   - Skip duplicate defects and comments (based on timestamps)'
    puts '   - Re-download missing attachments'
    puts '   - Verify each upload before moving to next defect'
    puts ''
  else
    puts 'To attempt fixing, run with --fix flag:'
    puts '  rails runner scripts/verify_and_fix_comment_attachments.rb --check-all --fix --verbose'
    puts ''
    puts 'Or re-run the import for specific defects:'
    puts '  rails runner scripts/import_jira_with_modules.rb --project <KEY> --verbose'
  end
else
  puts '✅ All comment-level attachments verified successfully!'
  puts ''
  puts "All #{overall_stats[:total_attachment_records]} attachment file(s) are present in storage."
end

puts '=' * 80

# Additional diagnostics
if overall_stats[:missing_attachments] > 0
  puts ''
  puts 'DIAGNOSTIC INFORMATION'
  puts '=' * 80

  # Check storage configuration
  service = ActiveStorage::Blob.service
  storage_root = service.respond_to?(:root) ? service.root : 'N/A'

  puts "Storage Service: #{service.class.name}"
  puts "Storage Root: #{storage_root}"
  puts "Rails Environment: #{Rails.env}"
  puts ''

  if storage_root != 'N/A'
    if Dir.exist?(storage_root)
      puts "✅ Storage directory exists: #{storage_root}"

      # Check if writable
      test_file = File.join(storage_root, ".write_test_#{Time.now.to_i}")
      begin
        File.write(test_file, 'test')
        File.delete(test_file)
        puts '✅ Storage directory is writable'
      rescue StandardError => e
        puts "❌ Storage directory is NOT writable: #{e.message}"
        puts "   Fix: sudo chown -R $(whoami):$(whoami) #{storage_root}"
      end
    else
      puts "❌ Storage directory does NOT exist: #{storage_root}"
      puts "   Fix: sudo mkdir -p #{storage_root} && sudo chown -R $(whoami):$(whoami) #{storage_root}"
    end
  end

  puts ''
  puts 'Possible causes for missing files:'
  puts '1. Import was interrupted before files finished uploading'
  puts '2. Storage directory was deleted or moved after import'
  puts '3. Permissions prevented file writing during import'
  puts '4. Network issues during download from Jira'
  puts '5. Database was restored but storage files were not'
  puts ''
  puts 'Recommended fix:'
  puts '1. Ensure storage directory exists and is writable (see above)'
  puts '2. Re-run the import script with --verbose to see detailed progress'
  puts '3. The script will now verify each upload and retry failures'
  puts '=' * 80
end
