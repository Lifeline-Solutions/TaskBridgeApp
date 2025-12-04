#!/usr/bin/env ruby
# scripts/user_assignment_report.rb
# Generate a detailed report on user assignments from the last import

puts "=" * 80
puts "USER ASSIGNMENT REPORT"
puts "=" * 80
puts ""

# Get all defects created/updated in the last 24 hours
recent_defects = Defect.where('updated_at >= ?', 24.hours.ago).includes(:user, :defect_users)

puts "📊 DEFECT SUMMARY"
puts "-" * 80
puts "Total recent defects: #{recent_defects.count}"
puts ""

# Categorize by assignment status
assigned_count = recent_defects.where.not(user_id: nil).count
unassigned_count = recent_defects.where(user_id: nil).count
default_user_count = 0

# Get DEFAULT_USER from config or environment
begin
  config_path = Rails.root.join('config', 'jira_import.yml')
  config = YAML.load_file(config_path).with_indifferent_access
  default_user_id = config[:default_user_uuid]

  if default_user_id
    default_user = User.find_by(id: default_user_id)
    default_user_count = recent_defects.where(user_id: default_user_id).count
  end
rescue => e
  puts "⚠️  Could not load config: #{e.message}"
end

puts "✅ Properly assigned: #{assigned_count - default_user_count}"
puts "⚠️  Assigned to DEFAULT_USER: #{default_user_count}"
puts "❌ Unassigned: #{unassigned_count}"
puts ""

# User assignment breakdown
puts "👥 USERS ASSIGNED TO DEFECTS"
puts "-" * 80

user_assignments = recent_defects
  .where.not(user_id: nil)
  .group(:user_id)
  .count
  .sort_by { |_k, v| -v }

user_assignments.each do |user_id, count|
  user = User.find_by(id: user_id)
  if user
    status = user.active? ? "✅" : "⚠️"
    puts "#{status} #{user.first_name} #{user.last_name} (#{user.email}): #{count} defect(s)"
  else
    puts "❌ User ID #{user_id}: #{count} defect(s) - USER NOT FOUND"
  end
end

puts ""
puts "📋 MULTIPLE ASSIGNEES PER DEFECT"
puts "-" * 80

multi_user_defects = recent_defects.select { |d| d.user_ids.length > 1 }
if multi_user_defects.any?
  multi_user_defects.each do |defect|
    puts "#{defect.defect_unique}: #{defect.user_ids.length} users"
    defect.defect_users.each do |du|
      user = du.user
      puts "  • #{user.first_name} #{user.last_name} (#{user.email})"
    end
  end
else
  puts "No defects with multiple assignees"
end

puts ""
puts "=" * 80
puts "END REPORT"
puts "=" * 80

