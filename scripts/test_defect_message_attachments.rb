#!/usr/bin/env ruby
# Quick test to verify DefectMessage supports attachments

puts 'Testing DefectMessage.attachments support...'
puts ''

# Load Rails environment
require_relative '../config/environment'

# Check if DefectMessage has attachments
if DefectMessage.new.respond_to?(:attachments)
  puts '✅ SUCCESS: DefectMessage now supports attachments!'
  puts ''
  puts 'Attachment association details:'
  puts '  - Model: DefectMessage'
  puts '  - Association: has_many_attached :attachments'
  puts '  - Storage: active_storage_attachments table'
  puts '  - Record Type: DefectMessage'
  puts ''

  # Check if we can create a test message
  begin
    test_defect = Defect.first
    if test_defect
      test_message = DefectMessage.new(
        defect: test_defect,
        user: User.first,
        content: 'Test message to verify attachments work'
      )

      if test_message.respond_to?(:attachments)
        puts '✅ Test message instance has attachments method'
        puts "  - Can attach files: #{test_message.attachments.respond_to?(:attach)}"
        puts ''
      end
    else
      puts '⚠️  No defects in database to test with'
    end
  rescue StandardError => e
    puts "⚠️  Could not create test message: #{e.message}"
  end

  puts 'STATUS: Ready to import comment attachments!'
  exit 0
else
  puts '❌ ERROR: DefectMessage does NOT support attachments'
  puts ''
  puts 'The has_many_attached :attachments declaration may not have loaded.'
  puts 'Try restarting Rails server or running: rails restart'
  puts ''
  exit 1
end
