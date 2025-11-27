#!/usr/bin/env ruby
# Test script to verify improved user matching logic
# Usage: rails runner scripts/test_user_matching.rb

puts "="*80
puts "TESTING IMPROVED USER MATCHING"
puts "="*80
puts ""

# Test cases for name matching
test_cases = [
  # Dot-separated names
  { name: "archana.verma", email: nil, expected: "should match archana verma" },
  { name: "eva.karimi", email: nil, expected: "should match eva karimi njagi or similar" },

  # 3+ part names
  { name: "Sebastian Morris Smith", email: nil, expected: "should match Sebastian Morris or Morris Smith" },
  { name: "Eva Karimi Njagi", email: nil, expected: "should match Eva Njagi or Eva Karimi" },

  # Regular 2-part names
  { name: "Irene Yego", email: nil, expected: "should match Irene Yego" },
  { name: "Kunjal Shah", email: nil, expected: "should match Kunjal Shah" },

  # Email-based matching (most reliable)
  { name: "Unknown Name", email: "david.ger@craftsilicon.com", expected: "should match by email" },

  # Edge cases
  { name: "simon mungai", email: nil, expected: "should match Simon Mungai (case insensitive)" },
  { name: "SARAH SYUKI", email: nil, expected: "should match Sarah Syuki (case insensitive)" },
]

# Helper function to test matching (copy from import script)
def find_user_by_name_or_map(name, email = nil, verbose: true)
  name_str = name.to_s.strip
  email_str = email.to_s.strip

  return nil if name_str.blank? && email_str.blank?

  # PRIORITY 1: Try email lookup (most reliable identifier)
  if email_str.present? && email_str.downcase != 'restricted'
    user = User.where(deleted_on: nil, active: true).find_by('lower(email) = ?', email_str.downcase)
    if user
      puts "  [EMAIL-MATCH] '#{name_str}' -> #{user.first_name} #{user.last_name} (#{user.email})" if verbose
      return user
    end
  end

  # PRIORITY 2: Handle dot-separated names (e.g., "archana.verma" -> first: archana, last: verma)
  if name_str.present? && name_str.include?('.')
    dot_parts = name_str.split('.')
    if dot_parts.length == 2
      first_dot = dot_parts[0].strip
      last_dot = dot_parts[1].strip

      users = User.where(deleted_on: nil, active: true)
        .where('lower(first_name) = ? AND lower(last_name) = ?', first_dot.downcase, last_dot.downcase)
        .to_a

      if users.length == 1
        puts "  [DOT-MATCH] '#{name_str}' -> #{users.first.first_name} #{users.first.last_name}" if verbose
        return users.first
      elsif users.length > 1
        craft_user = users.find { |u| u.email&.downcase&.end_with?('@craftsilicon.com') }
        if craft_user
          puts "  [DOT-MATCH-CRAFT] '#{name_str}' -> #{craft_user.first_name} #{craft_user.last_name} (#{craft_user.email})" if verbose
          return craft_user
        end
        puts "  [DOT-MATCH-FIRST] '#{name_str}' -> #{users.first.first_name} #{users.first.last_name}" if verbose
        return users.first
      end
    end
  end

  # PRIORITY 3: Dynamic first_name + last_name matching
  if name_str.present?
    parts = name_str.split
    if parts.length >= 2
      first = parts.first
      last = parts[1..].join(' ')

      users = User.where(deleted_on: nil, active: true)
        .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last.downcase)
        .to_a

      if users.length == 1
        puts "  [EXACT-MATCH] '#{name_str}' -> #{users.first.first_name} #{users.first.last_name}" if verbose
        return users.first
      elsif users.length > 1
        craft_user = users.find { |u| u.email&.downcase&.end_with?('@craftsilicon.com') }
        if craft_user
          puts "  [EXACT-MATCH-CRAFT] '#{name_str}' -> #{craft_user.first_name} #{craft_user.last_name} (#{craft_user.email})" if verbose
          return craft_user
        end
        puts "  [EXACT-MATCH-FIRST] '#{name_str}' -> #{users.first.first_name} #{users.first.last_name}" if verbose
        return users.first
      end

      # Try 3+ name parts
      if parts.length >= 3
        # First + last word
        last_word = parts.last
        user = User.where(deleted_on: nil, active: true)
          .where('lower(first_name) = ? AND lower(last_name) = ?', first.downcase, last_word.downcase)
          .first
        if user
          puts "  [3-PART-MATCH] '#{name_str}' -> #{user.first_name} #{user.last_name}" if verbose
          return user
        end
      end
    end
  end

  puts "  [NO-MATCH] '#{name_str}' -> NOT FOUND" if verbose
  nil
end

puts "\nTesting user matching:\n"
puts "-"*80

test_cases.each_with_index do |test, idx|
  puts "\n#{idx + 1}. Testing: #{test[:name].inspect} (email: #{test[:email].inspect})"
  puts "   Expected: #{test[:expected]}"

  user = find_user_by_name_or_map(test[:name], test[:email], verbose: true)

  if user
    puts "   ✅ MATCHED: #{user.first_name} #{user.last_name} (#{user.email}, active: #{user.active})"
  else
    puts "   ❌ NO MATCH"
  end
end

puts "\n" + "="*80
puts "CHECKING FOR DUPLICATE USERS (same first_name + last_name)"
puts "="*80

duplicates = User.where(deleted_on: nil, active: true)
  .group(:first_name, :last_name)
  .having('count(*) > 1')
  .count

if duplicates.any?
  puts "\nFound #{duplicates.length} duplicate name combinations:"
  duplicates.each do |name_combo, count|
    first, last = name_combo
    users = User.where(deleted_on: nil, active: true, first_name: first, last_name: last).to_a
    puts "\n  #{first} #{last} (#{count} users):"
    users.each do |u|
      craft = u.email&.end_with?('@craftsilicon.com') ? ' [CRAFT]' : ''
      puts "    - #{u.email}#{craft}"
    end
  end
else
  puts "\n✅ No duplicate users found"
end

puts "\n" + "="*80
puts "TEST COMPLETE"
puts "="*80

