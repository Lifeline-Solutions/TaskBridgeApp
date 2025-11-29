#!/usr/bin/env ruby
# scripts/check_defect_message_attachments.rb
# Check if DefectMessage model has attachments association configured

puts '=' * 80
puts 'DefectMessage Attachments Configuration Check'
puts '=' * 80
puts ''

# Check if DefectMessage is loaded
begin
  dm_class = DefectMessage
  puts '✅ DefectMessage model loaded'
rescue NameError => e
  puts "❌ DefectMessage model not found: #{e.message}"
  exit 1
end

puts ''

# Check if attachments association exists
has_attachments = dm_class.reflect_on_all_attachments.any? { |a| a.name == :attachments }

if has_attachments
  puts "✅ DefectMessage has 'attachments' association configured"

  # Get association details
  attachment_reflection = dm_class.reflect_on_attachment(:attachments)
  puts "   Association type: #{attachment_reflection.macro}"
  puts "   Association name: #{attachment_reflection.name}"
else
  puts "❌ DefectMessage does NOT have 'attachments' association"
  puts ''
  puts 'To fix this, ensure the following line is in app/models/defect_message.rb:'
  puts '   has_many_attached :attachments'
  puts ''
end

puts ''

# Check if instance responds to attachments
begin
  dm = DefectMessage.new
  if dm.respond_to?(:attachments)
    puts '✅ DefectMessage instances respond to .attachments method'
  else
    puts '❌ DefectMessage instances do NOT respond to .attachments method'
  end
rescue StandardError => e
  puts "⚠️  Could not create DefectMessage instance: #{e.message}"
end

puts ''

# Check ActiveStorage tables
puts 'Checking ActiveStorage database tables:'
puts ''

active_storage_tables = %w[
  active_storage_blobs
  active_storage_attachments
  active_storage_variant_records
]

active_storage_tables.each do |table_name|
  if ActiveRecord::Base.connection.table_exists?(table_name)
    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM #{table_name}").first['count']
    puts "✅ #{table_name}: exists (#{count} records)"
  else
    puts "❌ #{table_name}: MISSING"
  end
end

puts ''

# Check for DefectMessage attachments in database
begin
  defect_message_attachments = ActiveStorage::Attachment
    .where(record_type: 'DefectMessage')
    .count

  puts "DefectMessage attachments in database: #{defect_message_attachments}"

  if defect_message_attachments.positive?
    puts "✅ Found #{defect_message_attachments} DefectMessage attachment(s) in database"

    # Sample a few
    samples = ActiveStorage::Attachment
      .where(record_type: 'DefectMessage')
      .limit(5)
      .includes(:blob)

    puts ''
    puts 'Sample attachments:'
    samples.each do |att|
      puts "  - Record ID: #{att.record_id}, Blob: #{att.blob.filename} (#{att.blob.byte_size} bytes)"
    end
  else
    puts '⚠️  No DefectMessage attachments found in database'
  end
rescue StandardError => e
  puts "❌ Error checking attachments: #{e.message}"
end

puts ''

# Check if we need to run migrations
begin
  puts '✅ No pending migrations' if defined?(ActiveRecord::Migration) && ActiveRecord::Migration.check_pending!
rescue ActiveRecord::PendingMigrationError => e
  puts '❌ PENDING MIGRATIONS DETECTED!'
  puts '   Run: rails db:migrate RAILS_ENV=production'
  puts "   Error: #{e.message}"
rescue StandardError => e
  puts "⚠️  Could not check migration status: #{e.message}"
end

puts ''
puts '=' * 80
puts 'Diagnostic Summary'
puts '=' * 80

if has_attachments
  puts '✅ DefectMessage is configured correctly for attachments'
  puts ''
  puts "If you're still seeing NoMethodError, try:"
  puts '1. Restart your Rails application to reload the model'
  puts '2. Run: rails db:migrate RAILS_ENV=production'
  puts '3. Check that app/models/defect_message.rb is deployed correctly'
else
  puts '❌ DefectMessage needs to be configured for attachments'
  puts ''
  puts 'Required steps:'
  puts '1. Add this line to app/models/defect_message.rb:'
  puts '     has_many_attached :attachments'
  puts '2. Ensure ActiveStorage migrations have been run:'
  puts '     rails active_storage:install'
  puts '     rails db:migrate RAILS_ENV=production'
  puts '3. Restart your Rails application'
  puts '4. Deploy the updated model to production'
end

puts '=' * 80
