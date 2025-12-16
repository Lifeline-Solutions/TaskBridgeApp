# Usage:
#   Dry run (default): rails runner scripts/cleanup_gbcbs_defects.rb
#   Execute delete:    rails runner scripts/cleanup_gbcbs_defects.rb DELETE

AUTHORIZED_REPORTERS = [
  'archana.verma',
  'Mitali Vaghela',
  'Edgar Kaptum',
  'Ponic Kambi',
  'manasseh.wanyoike',
  'nicholas.mbithuka',
  'gideon',
  'Lawrence Kimani'
].map(&:downcase)

puts "Authorized Reporters: #{AUTHORIZED_REPORTERS.join(', ')}"

defects_scope = Defect.left_joins(:creator).where("defects.defect_unique LIKE 'GBCBS-%'")

# Normalize creator names for comparison: "FirstName LastName" or just "FirstName" if LastName is missing
# We'll use Ruby to filter because SQL concatenation and case-insensitivity might be tricky across different DBs 
# and we want to be precise with the provided list.
# However, for performance on large datasets, SQL is better. 
# Given the likely size, we can iterate or use SQL. Let's try to be efficient with SQL where possible but exact with Ruby.

candidates = defects_scope.select { |d|
  # Construct reporter name similar to how the dashboard likely does it or simply join first/last
  # The image shows "archana.verma" which looks like a username or email prefix, 
  # but "Mitali Vaghela" is clearly a full name.
  # "gideon" is just a first name.
  
  user = d.creator
  next true if user.nil? # If no creator, it's not in the authorized list, so it's a candidate for deletion? 
                         # Assumption: Yes, if no creator, they aren't on the authorized list.

  # Try to match against various forms
  full_name = "#{user.first_name} #{user.last_name}".strip.downcase
  first_name = user.first_name.to_s.strip.downcase
  username_part = user.email.split('@').first.downcase

  # Check if ANY of the representations match the authorized list
  is_authorized = AUTHORIZED_REPORTERS.include?(full_name) || 
                  AUTHORIZED_REPORTERS.include?(first_name) ||
                  AUTHORIZED_REPORTERS.include?(username_part)

  !is_authorized
}

count = candidates.count

puts "Found #{count} defects starting with 'GBCBS-' created by unauthorized reporters."

if count > 0
  puts "\nSample of defects to be deleted:"
  candidates.first(5).each do |d|
    creator_name = d.creator ? "#{d.creator.first_name} #{d.creator.last_name} (#{d.creator.email})" : "No Creator"
    puts "- #{d.defect_unique} (Reporter: #{creator_name}, Status: #{d.statuses.pluck(:name).join(', ')})"
  end
end

if ARGV[0] == 'DELETE'
  puts "\nDELETING #{count} defects..."
  
  deleted_count = 0
  
  # Delete in batches if needed, but for this script straightforward destroy is fine for safety logic
  candidates.each do |d|
    # Use destroy to ensure callbacks run (linked defects, etc)
    d.destroy
    deleted_count += 1
    print "." if deleted_count % 10 == 0
  end
  
  puts "\n\nSuccessfully deleted #{deleted_count} defects."
else
  puts "\n[DRY RUN] No records were deleted."
  puts "To enforce deletion, run with 'DELETE' argument:"
  puts "rails runner scripts/cleanup_gbcbs_defects.rb DELETE"
end
