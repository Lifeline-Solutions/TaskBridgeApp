#!/usr/bin/env ruby
# Test script for enhanced user name parsing in JIRA import
# Demonstrates dot-separated and multi-part name parsing strategies

require_relative '../config/environment'

# Test cases for name parsing
test_names = [
  'archana.verma',                    # dot-separated
  'Eva Karimi Njagi',                 # multi-part (3+ parts) -> use first 2
  'John Smith',                       # standard split
  'sarah.syuki',                      # dot-separated
  'David Ger',                        # standard split
  'Brian Wafula Kariuki',             # multi-part (3+ parts) -> use first 2
  'simon',                            # single part
  'SARAH SYUKI',                      # uppercase
]

puts "=" * 80
puts "USER NAME PARSING TEST"
puts "=" * 80
puts ""

test_names.each do |name|
  puts "Input: '#{name}'"

  # Replicate the parsing logic from import script
  name_str = name.to_s.strip

  # STRATEGY 1: Check for dot-separated format
  if name_str.include?('.')
    parts = name_str.split('.')
    if parts.length >= 2
      first = parts[0].strip.presence
      last = parts[1].strip.presence
      if first && last
        puts "  ✓ Parsed via: dot-separated"
        puts "    first_name: '#{first}'"
        puts "    last_name:  '#{last}'"
        puts ""
        next
      end
    end
  end

  # STRATEGY 2: Check for multi-part name (3+ parts) - use first 2 parts
  parts = name_str.split(/\s+/).reject(&:empty?)

  if parts.length >= 3
    first_two = [parts[0], parts[1]].map(&:strip).reject(&:empty?)
    if first_two.length == 2
      puts "  ✓ Parsed via: multi-part-first-two"
      puts "    first_name: '#{first_two[0]}'"
      puts "    last_name:  '#{first_two[1]}'"
      puts ""
      next
    end
  end

  # STRATEGY 3: Standard split (2 parts or less)
  if parts.length >= 2
    first = parts[0].strip.presence
    last = parts[1..-1].map(&:strip).join(' ').presence
    if first && last
      puts "  ✓ Parsed via: standard-split"
      puts "    first_name: '#{first}'"
      puts "    last_name:  '#{last}'"
      puts ""
      next
    end
  end

  # STRATEGY 4: Single part - treat as first name only
  if parts.length == 1
    first = parts[0].strip.presence
    if first
      puts "  ✓ Parsed via: single-part"
      puts "    first_name: '#{first}'"
      puts "    last_name:  nil"
      puts ""
      next
    end
  end

  puts "  ✗ Failed to parse"
  puts ""
end

puts "=" * 80
puts "TEST COMPLETE"
puts "=" * 80

