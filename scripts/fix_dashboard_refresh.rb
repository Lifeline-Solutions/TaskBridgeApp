#!/usr/bin/env ruby
# Script to fix dashboards with invalid refresh intervals (0 or < 300)
# Usage: rails runner scripts/fix_dashboard_refresh.rb

puts "Checking for dashboards with auto_refresh_interval < 300..."

dashboards = Dashboard.where("auto_refresh_interval < 300 AND auto_refresh_interval IS NOT NULL")
count = dashboards.count

if count == 0
  puts "No invalid dashboards found."
else
  puts "Found #{count} dashboards with invalid refresh interval."
  puts "Updating them to 300 seconds (5 minutes)..."
  
  dashboards.find_each do |d|
    puts "  Fixing Dashboard ID: #{d.id}, Name: #{d.name}, Interval: #{d.auto_refresh_interval}"
    d.update_column(:auto_refresh_interval, 300) # Use update_column to bypass validation if other fields are invalid, but we want valid data.
  end
  
  puts "Done."
end
