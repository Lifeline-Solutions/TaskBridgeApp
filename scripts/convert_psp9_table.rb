#!/usr/bin/env ruby
# Script to convert PSP-9 table data from JSON to HTML
# Usage:
#   1. Paste the Jira description JSON content into tmp/psp9_description.json
#   2. Run: ruby scripts/convert_psp9_table.rb

require 'json'
require 'cgi'

# ADF to HTML conversion functions
def convert_adf_to_html(content_array)
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |block|
    next unless block.is_a?(Hash)

    block_html = convert_adf_block_to_html(block)
    html_parts << block_html if block_html.present?
  end

  html_parts.join("\n")
end

def convert_adf_block_to_html(block)
  return '' if block.nil? || !block.is_a?(Hash)

  block_type = block['type']&.to_s&.downcase
  content = block['content'] || []

  case block_type
  when 'paragraph'
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<p>#{inner_html}</p>" : ''

  when 'table'
    convert_adf_table_to_html(block)

  when 'heading'
    inner_html = convert_adf_inline_to_html(content)
    level = block.dig('attrs', 'level') || 1
    inner_html.present? ? "<h#{level}>#{inner_html}</h#{level}>" : ''

  when 'bulletlist', 'bullet_list'
    list_html = convert_adf_list_to_html(content, 'ul')
    list_html.present? ? "<ul>#{list_html}</ul>" : ''

  when 'orderedlist', 'ordered_list'
    list_html = convert_adf_list_to_html(content, 'ol')
    list_html.present? ? "<ol>#{list_html}</ol>" : ''

  else
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<div>#{inner_html}</div>" : ''
  end
end

def convert_adf_table_to_html(table_block)
  return '' unless table_block.is_a?(Hash) && table_block['content']

  rows = table_block['content']
  return '' if rows.empty?

  html = '<table class="table table-bordered">'

  rows.each_with_index do |row, _row_idx|
    next unless row.is_a?(Hash) && row['type'] == 'tableRow'

    cells = row['content'] || []
    html << '<tr>'

    cells.each do |cell|
      next unless cell.is_a?(Hash)

      cell_type = cell['type']
      is_header = (cell_type == 'tableHeader')
      tag = is_header ? 'th' : 'td'

      # Get cell content
      cell_content = cell['content'] || []
      cell_html = convert_adf_to_html(cell_content)

      # Get cell attributes
      attrs = cell['attrs'] || {}
      colspan = attrs['colspan']
      rowspan = attrs['rowspan']

      attr_str = ''
      attr_str << %( colspan="#{colspan}") if colspan && colspan > 1
      attr_str << %( rowspan="#{rowspan}") if rowspan && rowspan > 1

      html << "<#{tag}#{attr_str}>#{cell_html}</#{tag}>"
    end

    html << '</tr>'
  end

  html << '</table>'
  html
end

def convert_adf_list_to_html(list_items, _list_type)
  return '' if list_items.nil? || list_items.empty?

  html_parts = []
  list_items.each do |item|
    next unless item.is_a?(Hash) && item['type'] == 'listItem'

    item_content = item['content'] || []
    item_html = convert_adf_to_html(item_content)
    html_parts << "<li>#{item_html}</li>" if item_html.present?
  end

  html_parts.join("\n")
end

def convert_adf_inline_to_html(content)
  return '' if content.nil? || !content.is_a?(Array)

  html_parts = []

  content.each do |node|
    next unless node.is_a?(Hash)

    node_type = node['type']&.to_s&.downcase

    case node_type
    when 'text'
      text = CGI.escapeHTML(node['text'] || '')

      # Apply marks (bold, italic, etc.)
      marks = node['marks'] || []
      marks.each do |mark|
        mark_type = mark['type']&.to_s&.downcase
        case mark_type
        when 'strong'
          text = "<strong>#{text}</strong>"
        when 'em'
          text = "<em>#{text}</em>"
        when 'code'
          text = "<code>#{text}</code>"
        when 'underline'
          text = "<u>#{text}</u>"
        when 'strike'
          text = "<s>#{text}</s>"
        end
      end

      html_parts << text

    when 'hardbreak'
      html_parts << '<br>'

    when 'mention'
      display_name = node.dig('attrs', 'text') || node.dig('attrs', 'id') || 'User'
      html_parts << "<span class=\"mention\">@#{CGI.escapeHTML(display_name)}</span>"

    when 'emoji'
      shortname = node.dig('attrs', 'shortName') || node.dig('attrs', 'text') || ''
      html_parts << CGI.escapeHTML(shortname)

    when 'inlinecode', 'inline_code'
      text = CGI.escapeHTML(node['text'] || '')
      html_parts << "<code>#{text}</code>"

    else
      # Handle nested content
      if node['content']
        nested_html = convert_adf_inline_to_html(node['content'])
        html_parts << nested_html if nested_html.present?
      end
    end
  end

  html_parts.join
end

class String
  def present?
    !nil? && !empty?
  end
end

class NilClass
  def present?
    false
  end
end

# Main script
puts 'PSP-9 Table Converter'
puts '=' * 60

input_file = 'tmp/psp9_description.json'

unless File.exist?(input_file)
  puts "❌ File not found: #{input_file}"
  puts ''
  puts 'Please create the file with the Jira description JSON content.'
  puts "The JSON should contain the 'content' array from the description field."
  puts ''
  puts 'Example format:'
  puts '{'
  puts '  "type": "doc",'
  puts '  "version": 1,'
  puts '  "content": ['
  puts '    {'
  puts '      "type": "table",'
  puts '      "content": [...]'
  puts '    }'
  puts '  ]'
  puts '}'
  exit 1
end

begin
  data = JSON.parse(File.read(input_file))

  puts "✓ Loaded JSON from #{input_file}"
  puts ''

  # Check structure
  if data.is_a?(Hash)
    if data['content']
      content = data['content']
      puts "Found #{content.length} top-level block(s)"

      content.each_with_index do |block, i|
        puts "  Block #{i}: #{block['type']}"
      end

      # Convert to HTML
      html = convert_adf_to_html(content)

      puts ''
      puts '=' * 60
      puts 'CONVERTED HTML:'
      puts '=' * 60
      puts html
      puts ''
      puts '=' * 60

      # Save to file
      output_file = 'tmp/psp9_converted.html'
      File.write(output_file, html)
      puts "✓ Saved to: #{output_file}"

      # Also create a Trix-wrapped version
      trix_html = %(<div class="trix-content">\n  #{html}\n</div>)
      trix_file = 'tmp/psp9_trix.html'
      File.write(trix_file, trix_html)
      puts "✓ Saved Trix version to: #{trix_file}"

    elsif data.is_a?(Array)
      # Content array directly
      puts "Found #{data.length} block(s)"
      html = convert_adf_to_html(data)

      puts ''
      puts '=' * 60
      puts 'CONVERTED HTML:'
      puts '=' * 60
      puts html
      puts ''

      output_file = 'tmp/psp9_converted.html'
      File.write(output_file, html)
      puts "✓ Saved to: #{output_file}"
    else
      puts '❌ Unexpected JSON structure'
      puts "Top-level keys: #{data.keys.join(', ')}"
    end
  elsif data.is_a?(Array)
    puts "Found array with #{data.length} block(s)"
    html = convert_adf_to_html(data)

    puts ''
    puts '=' * 60
    puts 'CONVERTED HTML:'
    puts '=' * 60
    puts html
    puts ''

    output_file = 'tmp/psp9_converted.html'
    File.write(output_file, html)
    puts "✓ Saved to: #{output_file}"
  end
rescue JSON::ParserError => e
  puts "❌ JSON Parse Error: #{e.message}"
rescue StandardError => e
  puts "❌ Error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
