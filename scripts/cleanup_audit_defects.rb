#!/usr/bin/env ruby
# scripts/cleanup_audit_defects.rb

PRODUCT_ID = '6609f311-3fc7-44c6-884a-c1190aaadb76'.freeze
BANKING_TYPE_NAME = 'Audit'.freeze

puts "Starting cleanup of '#{BANKING_TYPE_NAME}' defects for Product ID: #{PRODUCT_ID}..."

# Find defects matching criteria
# Note: Using case-insensitive match for banking type name just in case
defects = Defect.joins(:banking_type)
  .where(product_id: PRODUCT_ID)
  .where('lower(banking_types.name) = ?', BANKING_TYPE_NAME.downcase)

count = defects.count
puts "Found #{count} defects to delete."

if count.zero?
  puts 'No defects found. Exiting.'
  exit 0
end

defects.find_each do |defect|
  print "Deleting #{defect.defect_unique} (Banking Type: #{defect.banking_type.name})... "

  begin
    # Manually destroy dependent associations to ensure hard deletion
    # Use delete_all on the class with where clause to catch soft-deleted records too
    DefectMessage.unscoped.where(defect_id: defect.id).delete_all
    DefectLabel.unscoped.where(defect_id: defect.id).delete_all
    DefectHistory.unscoped.where(defect_id: defect.id).delete_all
    DefectFailureReport.unscoped.where(defect_id: defect.id).delete_all
    DefectLink.unscoped.where(source_defect_id: defect.id).delete_all
    DefectLink.unscoped.where(target_defect_id: defect.id).delete_all

    # Clear HABTM associations
    defect.statuses.clear
    defect.users.clear

    # Purge attachments
    defect.images.purge_later
    defect.videos.purge_later
    defect.attachments.purge_later

    # Permanently delete the defect
    defect.delete
    puts 'Done.'
  rescue StandardError => e
    puts "FAILED: #{e.message}"
  end
end

puts 'Cleanup complete.'
