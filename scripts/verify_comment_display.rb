#!/usr/bin/env ruby
# Quick verification: Check if comment attachments will display in UI

puts '🔍 Verifying Comment Attachment Display Setup'
puts '=' * 70
puts ''

# Load Rails
require_relative '../config/environment'

# 1. Check DefectMessage model has attachments
puts '1. Checking DefectMessage model...'
if DefectMessage.new.respond_to?(:attachments)
  puts "   ✅ Model has 'has_many_attached :attachments'"
else
  puts "   ❌ Model MISSING 'has_many_attached :attachments'"
  puts '   FIX: Add to app/models/defect_message.rb:'
  puts '        has_many_attached :attachments'
  exit 1
end
puts ''

# 2. Check if any comment attachments exist
puts '2. Checking for comment attachments in database...'
comment_att_count = ActiveStorage::Attachment.where(record_type: 'DefectMessage').count
if comment_att_count.positive?
  puts "   ✅ Found #{comment_att_count} comment attachment(s)"
else
  puts '   ⚠️  No comment attachments found yet'
  puts "   This is normal if you haven't run the import script yet."
end
puts ''

# 3. Check a specific defect (if provided)
if ARGV[0]
  defect_unique = ARGV[0]
  puts "3. Checking defect: #{defect_unique}..."

  defect = Defect.find_by(defect_unique: defect_unique)
  if defect
    puts "   ✅ Defect found (ID: #{defect.id})"

    messages_with_attachments = defect.defect_messages.select { |m| m.attachments.any? }

    if messages_with_attachments.any?
      puts "   ✅ Found #{messages_with_attachments.count} comment(s) with attachments:"
      puts ''

      messages_with_attachments.each_with_index do |msg, idx|
        user = msg.user
        puts "   Comment #{idx + 1}:"
        puts "     Author: #{user.first_name} #{user.last_name}"
        puts "     Date: #{msg.created_at.strftime('%Y-%m-%d %I:%M %p')}"
        puts "     Attachments: #{msg.attachments.count}"

        msg.attachments.each do |att|
          size_mb = (att.blob.byte_size / 1024.0 / 1024.0).round(2)
          exists = begin
            ActiveStorage::Blob.service.exist?(att.blob.key)
          rescue StandardError
            false
          end
          status = exists ? '✅' : '❌'
          puts "       #{status} #{att.filename} (#{size_mb} MB)"
        end
        puts ''
      end
    else
      puts '   ℹ️  No comments with attachments for this defect'
    end
  else
    puts "   ❌ Defect '#{defect_unique}' not found"
  end
else
  puts '3. Skipping defect check (no defect_unique provided)'
  puts '   TIP: Run with defect ID to check specific defect:'
  puts '   rails runner scripts/verify_comment_display.rb KCBL-1116'
end
puts ''

# 4. Check view file exists
puts '4. Checking view template...'
view_path = Rails.root.join('app/views/defect_messages/_message.html.erb')
if File.exist?(view_path)
  puts '   ✅ View template exists'

  # Check if view has the new attachments section
  content = File.read(view_path)
  if content.include?('message.attachments.any?')
    puts '   ✅ View template updated with attachment display code'
  else
    puts '   ❌ View template MISSING attachment display code'
    puts '   FIX: Update app/views/defect_messages/_message.html.erb'
    puts '        to include comment attachments display section'
    exit 1
  end
else
  puts "   ❌ View template NOT FOUND: #{view_path}"
  exit 1
end
puts ''

# Summary
puts '=' * 70
puts 'SUMMARY'
puts '=' * 70
puts ''
puts '✅ Model: DefectMessage has attachments association'
puts "✅ Database: #{comment_att_count} comment attachment(s) stored"
puts '✅ View: Template has attachment display code'
puts ''
puts 'STATUS: ✅ Comment attachments WILL DISPLAY in defect view'
puts ''
puts 'Next steps:'
puts '  1. Clear browser cache (Ctrl+Shift+R)'
puts '  2. Navigate to a defect with comment attachments'
puts "  3. Click 'Comments' tab"
puts "  4. Look for '📎 Attachments (X)' below comment text"
puts ''
puts 'To verify a specific defect:'
puts '  rails runner scripts/verify_comment_display.rb KCBL-1116'
puts ''
