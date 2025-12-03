# scripts/cleanup_isp_data.rb
# Deletes all defects starting with 'ISP-' and their associated data.

puts "Starting cleanup of ISP data..."

# Use with_deleted to find ALL records including soft-deleted ones
defects = Defect.with_deleted.where("defect_unique LIKE 'ISP-%'")
count = defects.count

puts "Found #{count} defects (including soft-deleted) to delete."

defects.find_each do |defect|
  print "Deleting #{defect.defect_unique}... "
  
  # Manually destroy dependent associations since we are using delete
  # Use delete_all on the class with where clause to ensure we catch soft-deleted records too
  DefectMessage.unscoped.where(defect_id: defect.id).delete_all
  DefectLabel.unscoped.where(defect_id: defect.id).delete_all
  DefectHistory.unscoped.where(defect_id: defect.id).delete_all
  DefectFailureReport.unscoped.where(defect_id: defect.id).delete_all
  DefectLink.unscoped.where(source_defect_id: defect.id).delete_all
  DefectLink.unscoped.where(target_defect_id: defect.id).delete_all
  
  # Clear HABTM associations (removes from join tables)
  defect.statuses.clear
  defect.users.clear
  
  # Explicitly purge attachments to ensure they are removed from storage
  defect.images.purge_later
  defect.videos.purge_later
  defect.attachments.purge_later
  
  # Permanently delete the defect (skips callbacks, but we handled dependents)
  defect.delete
  puts "Done."
end

puts "Cleanup complete. Deleted #{count} defects."
