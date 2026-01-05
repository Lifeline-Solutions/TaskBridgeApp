# scripts/cleanup_kup_defects.rb

def cleanup_kup_defects
  puts 'Starting cleanup of KUP defects with no labels...'

  # Find defects starting with 'KUP-'
  kup_defects = Defect.where("defect_unique LIKE 'KUP-%'")
  puts "Found #{kup_defects.count} total defects starting with 'KUP-'"

  count_deleted = 0

  ActiveRecord::Base.transaction do
    kup_defects.find_each do |defect|
      # Check if labels are empty
      if defect.labels.empty?
        puts "Deleting defect: #{defect.defect_unique} (ID: #{defect.id})"
        defect.destroy
        count_deleted += 1
      end
    end
  end

  puts 'Cleanup complete.'
  puts "Total deleted defects: #{count_deleted}"
end

cleanup_kup_defects
