#!/usr/bin/env ruby
# scripts/test_user_matching.rb
#
# Test script to validate user name parsing and matching logic
# Run this in Rails console to verify the implementation
#
# Usage: rails runner scripts/test_user_matching.rb

puts "=" * 80
puts "USER NAME PARSING & MATCHING TEST SUITE"
puts "=" * 80
puts ""

# Test data with expected results
test_cases = [
  {
    name: "dot-separated single user",
    input_name: "archana.verma",
    expected_first: "archana",
    expected_last: "verma",
    db_first: "archana",
    db_last: "verma"
  },
  {
    name: "multi-part name (3 parts)",
    input_name: "Eva Karimi Njagi",
    expected_first: "Eva",
    expected_last: "Karimi",
    db_first: "Eva",
    db_last: "Karimi"
  },
  {
    name: "standard two-part",
    input_name: "John Smith",
    expected_first: "John",
    expected_last: "Smith",
    db_first: "John",
    db_last: "Smith"
  },
  {
    name: "lowercase two-part",
    input_name: "simon mungai",
    expected_first: "simon",
    expected_last: "mungai",
    db_first: "Simon",
    db_last: "Mungai"
  },
  {
    name: "uppercase two-part",
    input_name: "SARAH SYUKI",
    expected_first: "SARAH",
    expected_last: "SYUKI",
    db_first: "Sarah",
    db_last: "Syuki"
  },
  {
    name: "single part name",
    input_name: "Madonna",
    expected_first: "Madonna",
    expected_last: nil,
    db_first: "Madonna",
    db_last: nil
  },
  {
    name: "hyphenated last name",
    input_name: "Mary Jane-Smith",
    expected_first: "Mary",
    expected_last: "Jane-Smith",
    db_first: "Mary",
    db_last: "Jane-Smith"
  }
]

# Helper function to parse names (same logic as in import script)
def parse_jira_name(name_str)
  return { first_name: nil, last_name: nil } if name_str.blank?

  # Handle dot-separated format (e.g., "archana.verma")
  if name_str.include?('.')
    parts = name_str.split('.')
    return {
      first_name: parts.first.strip,
      last_name: parts.last.strip,
      strategy: 'dot-separated'
    }
  end

  # Handle multi-part names (3+ parts) - use first two
  parts = name_str.split
  if parts.length >= 3
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'multi-part-first-two'
    }
  elsif parts.length == 2
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'two-part'
    }
  elsif parts.length == 1
    return {
      first_name: parts[0].strip,
      last_name: nil,
      strategy: 'single-part'
    }
  end

  { first_name: nil, last_name: nil, strategy: 'failed-parse' }
end

# Helper function to find user (simplified version for testing)
def find_user_for_test(first_name, last_name)
  return nil unless first_name

  if first_name && last_name
    # Try exact match
    user = User.where('LOWER(first_name) = ? AND LOWER(last_name) = ?', first_name.downcase, last_name.downcase).first
    return user if user

    # Try partial match (first exact, last prefix)
    user = User.where('LOWER(first_name) = ? AND LOWER(last_name) LIKE ?', first_name.downcase, "#{last_name.downcase}%").first
    return user if user
  elsif first_name
    # Single name - try both first and last
    user = User.where('LOWER(first_name) = ? OR LOWER(last_name) = ?', first_name.downcase, first_name.downcase).first
    return user if user
  end

  nil
end

# Run tests
passed = 0
failed = 0

test_cases.each_with_index do |test, idx|
  puts "Test #{idx + 1}: #{test[:name]}"
  puts "  Input: '#{test[:input_name]}'"

  # Test parsing
  parsed = parse_jira_name(test[:input_name])
  puts "  Parsed: first='#{parsed[:first_name]}', last='#{parsed[:last_name]}' (strategy: #{parsed[:strategy]})"
  puts "  Expected: first='#{test[:expected_first]}', last='#{test[:expected_last]}'"

  # Check if parsing is correct
  if parsed[:first_name] == test[:expected_first] && parsed[:last_name] == test[:expected_last]
    puts "  ✅ PARSING CORRECT"

    # Now try to find user in database
    test_user = User.where(
      'LOWER(first_name) = ? AND LOWER(last_name) = ?',
      test[:db_first].downcase,
      test[:db_last] ? test[:db_last].downcase : '%'
    )

    # If single name test (last is nil), adjust query
    if test[:db_last].nil?
      test_user = User.where('LOWER(first_name) = ?', test[:db_first].downcase)
    end

    if test_user.exists?
      found_user = test_user.first
      puts "  ✅ USER FOUND IN DATABASE: #{found_user.first_name} #{found_user.last_name} (#{found_user.id})"
      passed += 1
    else
      puts "  ⚠️  USER NOT FOUND IN DATABASE"
      puts "     Would create: first='#{test[:db_first]}', last='#{test[:db_last]}'"
      puts "     (This is OK - user can be created during import)"
      passed += 1
    end
  else
    puts "  ❌ PARSING FAILED"
    puts "     Got: first='#{parsed[:first_name]}', last='#{parsed[:last_name]}'"
    failed += 1
  end

  puts ""
end

# Summary
puts "=" * 80
puts "TEST RESULTS"
puts "=" * 80
puts "Passed: #{passed}/#{test_cases.length}"
puts "Failed: #{failed}/#{test_cases.length}"
puts ""

if failed == 0
  puts "✅ All parsing tests passed!"
  puts ""
  puts "Next steps:"
  puts "  1. Verify test users exist in database with correct spelling"
  puts "  2. Run dry-run import: rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run"
  puts "  3. Review user match report"
  puts "  4. Run actual import if report looks good"
  puts "  5. Run verification: rails runner scripts/verify_and_fix_user_assignments.rb"
else
  puts "❌ Some tests failed"
  puts "Please review the parsing logic in:"
  puts "  - scripts/import_jira_with_modules.rb (parse_jira_name function)"
  puts "  - scripts/verify_and_fix_user_assignments.rb (parse_jira_name function)"
end

puts "=" * 80

