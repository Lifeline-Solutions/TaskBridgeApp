#!/usr/bin/env ruby
# Test script for enhanced ADF (Atlassian Document Format) extraction
# This demonstrates the new extraction capabilities for:
# - Tables
# - Bullet lists
# - Ordered lists
# - Code blocks
# - Headings
# - Blockquotes

# Sample Jira ADF content with various element types
sample_adf_content = {
  'content' => [
    # Heading
    {
      'type' => 'heading',
      'attrs' => { 'level' => 1 },
      'content' => [
        { 'type' => 'text', 'text' => 'Bug Description' }
      ]
    },
    # Regular paragraph
    {
      'type' => 'paragraph',
      'content' => [
        { 'type' => 'text', 'text' => 'This is a test bug with various content types.' }
      ]
    },
    # Bullet list
    {
      'type' => 'bulletList',
      'content' => [
        {
          'type' => 'listItem',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'First issue found' }
              ]
            }
          ]
        },
        {
          'type' => 'listItem',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'Second issue found' }
              ]
            }
          ]
        }
      ]
    },
    # Ordered list
    {
      'type' => 'orderedList',
      'content' => [
        {
          'type' => 'listItem',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'Step one to reproduce' }
              ]
            }
          ]
        },
        {
          'type' => 'listItem',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'Step two to reproduce' }
              ]
            }
          ]
        }
      ]
    },
    # Code block
    {
      'type' => 'codeBlock',
      'attrs' => { 'language' => 'ruby' },
      'content' => [
        {
          'type' => 'text',
          'text' => "def test_method\n  puts 'This is code'\nend"
        }
      ]
    },
    # Blockquote
    {
      'type' => 'blockquote',
      'content' => [
        {
          'type' => 'paragraph',
          'content' => [
            { 'type' => 'text', 'text' => 'This is an important note from the user' }
          ]
        }
      ]
    },
    # Table
    {
      'type' => 'table',
      'content' => [
        {
          'type' => 'tableRow',
          'content' => [
            {
              'type' => 'tableHeader',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Environment' }
                  ]
                }
              ]
            },
            {
              'type' => 'tableHeader',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Status' }
                  ]
                }
              ]
            }
          ]
        },
        {
          'type' => 'tableRow',
          'content' => [
            {
              'type' => 'tableCell',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Production' }
                  ]
                }
              ]
            },
            {
              'type' => 'tableCell',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Broken' }
                  ]
                }
              ]
            }
          ]
        },
        {
          'type' => 'tableRow',
          'content' => [
            {
              'type' => 'tableCell',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Staging' }
                  ]
                }
              ]
            },
            {
              'type' => 'tableCell',
              'content' => [
                {
                  'type' => 'paragraph',
                  'content' => [
                    { 'type' => 'text', 'text' => 'Working' }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}

# Load the extraction functions
require_relative '../scripts/import_jira_with_modules'

puts '=' * 80
puts 'Testing Enhanced ADF Extraction'
puts '=' * 80
puts ''

# Test extraction
result = extract_description(sample_adf_content)

puts 'EXTRACTED CONTENT:'
puts '-' * 80
puts result
puts '-' * 80
puts ''

puts '✅ Extraction successful!'
puts ''

# Verify key content is present
checks = [
  ['Heading present', result.include?('# Bug Description')],
  ['Bullet list present', result.include?('• First issue found')],
  ['Ordered list present', result.include?('1. Step one to reproduce')],
  ['Code block present', result.include?('```ruby')],
  ['Blockquote present', result.include?('> This is an important note')],
  ['Table present', result.include?('[Table]') && result.include?('Production | Broken')]
]

puts 'Content Validation:'
puts '-' * 80
checks.each do |check_name, passed|
  status = passed ? '✅ PASS' : '❌ FAIL'
  puts "#{status}: #{check_name}"
end
puts '-' * 80
puts ''

all_passed = checks.all? { |_, passed| passed }
if all_passed
  puts '🎉 All content extraction tests passed!'
else
  puts '⚠️  Some content extraction tests failed. Review the output above.'
end
