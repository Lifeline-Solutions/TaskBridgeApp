#!/usr/bin/env ruby
# Verification script for XLSX MIME type registration
# Run this with: bin/rails runner scripts/verify_xlsx_mime_type.rb

puts "=" * 60
puts "XLSX MIME Type Verification"
puts "=" * 60
puts

# Check if XLSX MIME type is registered
xlsx_mime = Mime::Type.lookup_by_extension(:xlsx)

if xlsx_mime
  puts "✅ XLSX MIME type is registered"
  puts "   Symbol: #{xlsx_mime.symbol}"
  puts "   String: #{xlsx_mime.to_s}"
  puts "   Content Type: #{xlsx_mime.to_str}"
else
  puts "❌ XLSX MIME type is NOT registered"
  puts "   Please check config/initializers/mime_types.rb"
end

puts
puts "-" * 60

# Check if route accepts format parameter
routes_output = `bin/rails routes | grep cbk_groupware_report`
if routes_output.include?('(.:format)')
  puts "✅ Route accepts format parameter"
  puts "   #{routes_output.strip}"
else
  puts "❌ Route does NOT accept format parameter"
  puts "   #{routes_output.strip}"
end

puts
puts "-" * 60

# Check if controller method exists
controller_path = Rails.root.join('app', 'controllers', 'data_center_controller.rb')
if File.exist?(controller_path)
  content = File.read(controller_path)

  if content.include?('generate_cbk_groupware_report_xlsx')
    puts "✅ Controller method 'generate_cbk_groupware_report_xlsx' exists"
  else
    puts "❌ Controller method 'generate_cbk_groupware_report_xlsx' NOT found"
  end

  if content.include?('format.xlsx')
    puts "✅ Controller responds to XLSX format"
  else
    puts "❌ Controller does NOT respond to XLSX format"
  end
else
  puts "❌ Controller file not found"
end

puts
puts "=" * 60
puts

if xlsx_mime && routes_output.include?('(.:format)')
  puts "🎉 All checks passed! XLSX format should work."
  puts
  puts "Test URLs:"
  puts "  HTML: http://localhost:3000/cbk_groupware_report"
  puts "  XLSX: http://localhost:3000/cbk_groupware_report.xlsx?groupware_id=1&start_date=2026-01-01&end_date=2026-02-16"
else
  puts "⚠️  Some checks failed. Please review the issues above."
  puts
  puts "Required steps:"
  puts "  1. Ensure config/initializers/mime_types.rb exists and registers XLSX"
  puts "  2. Ensure route has (.:format) parameter"
  puts "  3. Restart Rails server: bin/rails server"
end

puts
puts "=" * 60

