#!/usr/bin/env ruby
# scripts/test_rich_text_import.rb
# Quick test to verify rich text description import is working correctly

puts "=" * 80
puts "RICH TEXT IMPORT TEST"
puts "=" * 80

# Test 1: Verify CGI is loaded
begin
  require 'cgi'
  test_string = "<script>alert('xss')</script>"
  escaped = CGI.escapeHTML(test_string)
  puts "✅ CGI HTML Escaping: #{escaped}"
  puts "   (Should show escaped entities, not raw script tag)"
rescue => e
  puts "❌ CGI Error: #{e.message}"
end

# Test 2: Check Defect model for rich_text support
begin
  defect = Defect.new
  if defect.respond_to?(:content)
    puts "✅ Defect has content attribute"
  else
    puts "❌ Defect missing content attribute"
  end
rescue => e
  puts "❌ Defect Model Error: #{e.message}"
end

# Test 3: Sample ADF to HTML conversion (manual test)
sample_adf = {
  'content' => [
    {
      'type' => 'paragraph',
      'content' => [
        {
          'type' => 'text',
          'text' => 'This is bold: ',
          'marks' => []
        },
        {
          'type' => 'text',
          'text' => 'bold text',
          'marks' => [{ 'type' => 'bold' }]
        }
      ]
    },
    {
      'type' => 'bulletlist',
      'content' => [
        {
          'type' => 'listitem',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                {
                  'type' => 'text',
                  'text' => 'First item'
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}

puts "\n📝 Sample ADF Input:"
puts JSON.pretty_generate(sample_adf)

puts "\n✅ Test Setup Complete!"
puts "=" * 80
puts ""
puts "MANUAL TESTS TO RUN IN 'rails c':"
puts ""
puts "1. Test ADF-to-HTML Conversion:"
puts "   sample_adf = { 'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'Test' }] }] }"
puts "   result = convert_adf_to_html(sample_adf['content'])"
puts "   puts result"
puts ""
puts "2. Test Full Description Import:"
puts "   jira_description = { 'content' => [...] }  # Your Jira description object"
puts "   html = extract_description(jira_description)"
puts "   puts html"
puts ""
puts "3. Verify Existing Defect Rich Text:"
puts "   defect = Defect.first"
puts "   puts defect.content.class  # Should be ActionText::RichText"
puts "   puts defect.content.to_html  # HTML string"
puts "   puts defect.content.to_plain_text  # Plain text version"
puts ""
puts "4. Create Test Defect with Rich Content:"
puts "   html_content = '<p>Test with <strong>bold</strong> and <em>italic</em></p>'"
puts "   defect = Defect.create!"
puts "   defect.content = html_content"
puts "   defect.save!"
puts "   puts defect.content.body.to_html"
puts ""
puts "=" * 80

