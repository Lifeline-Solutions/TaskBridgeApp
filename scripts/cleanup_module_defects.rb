# Usage:
#   Dry run (default): rails runner scripts/cleanup_module_defects.rb
#   Execute delete:    rails runner scripts/cleanup_module_defects.rb DELETE

module_name = 'Module'
target_module = QaModule.find_by(name: module_name)

unless target_module
  puts "Module '#{module_name}' not found. Exiting."
  exit 1
end

puts "Found Module: #{target_module.name} (ID: #{target_module.id})"

# Find defects with this module (ALL of them, regardless of labels)
candidates = Defect.where(qa_module_id: target_module.id)

count = candidates.count

puts "Found #{count} defects with module '#{module_name}' and NO labels."

if count > 0
  puts "\nSample of defects to be deleted:"
  candidates.first(5).each do |d|
    puts "- #{d.defect_unique} (Status: #{d.statuses.pluck(:name).join(', ')}, Created By: #{d.creator&.email})"
  end
end

if ARGV[0] == 'DELETE'
  puts "\nDELETING #{count} defects..."
  
  deleted_count = 0
  
  candidates.find_each do |d|
    d.destroy
    deleted_count += 1
    print "." if deleted_count % 10 == 0
  end
  
  puts "\n\nSuccessfully deleted #{deleted_count} defects."
else
  puts "\n[DRY RUN] No records were deleted."
  puts "To enforce deletion, run with 'DELETE' argument:"
  puts "rails runner scripts/cleanup_module_defects.rb DELETE"
end
