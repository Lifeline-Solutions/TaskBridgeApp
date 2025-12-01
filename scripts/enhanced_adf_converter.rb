#!/usr/bin/env ruby
# Fallback solution: When ADF macro is present, try to extract from wiki/storage format

require 'cgi'

# Enhanced ADF to HTML converter that handles missing table data gracefully
def convert_adf_to_html_enhanced(content_array, options = {})
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |block|
    next unless block.is_a?(Hash)

    block_html = convert_adf_block_to_html_enhanced(block, options)
    html_parts << block_html if block_html.present?
  end

  html_parts.join("\n")
end

def convert_adf_block_to_html_enhanced(block, options = {})
  return '' if block.nil? || !block.is_a?(Hash)

  block_type = block['type']&.to_s&.downcase
  content = block['content'] || []
  attrs = block['attrs'] || {}

  case block_type
  when 'paragraph'
    inner_html = convert_adf_inline_to_html_enhanced(content, options)
    inner_html.present? ? "<p>#{inner_html}</p>" : ''

  when 'heading'
    inner_html = convert_adf_inline_to_html_enhanced(content, options)
    level = attrs['level'] || block.dig('attrs', 'level') || 1
    inner_html.present? ? "<h#{level}>#{inner_html}</h#{level}>" : ''

  when 'bulletlist', 'bullet_list'
    list_html = convert_adf_list_to_html_enhanced(content, 'ul', options)
    list_html.present? ? "<ul>#{list_html}</ul>" : ''

  when 'orderedlist', 'ordered_list'
    list_html = convert_adf_list_to_html_enhanced(content, 'ol', options)
    list_html.present? ? "<ol>#{list_html}</ol>" : ''

  when 'table'
    convert_adf_table_to_html_enhanced(block, options)

  when 'codeblock', 'code_block'
    code_text = convert_adf_inline_to_html_enhanced(content, options)
    if code_text.present?
      lang = attrs['language'] || block.dig('attrs', 'language') || 'plaintext'
      "<pre><code class=\"language-#{lang}\">#{CGI.escapeHTML(code_text)}</code></pre>"
    else
      ''
    end

  when 'blockquote'
    inner_html = convert_adf_inline_to_html_enhanced(content, options)
    inner_html.present? ? "<blockquote>#{inner_html}</blockquote>" : ''

  when 'horizontalrule', 'horizontal_rule', 'rule', 'hr'
    '<hr>'

  when 'mediasingle', 'media'
    # Handle images/media
    if content.is_a?(Array) && content[0]
      media = content[0]
      if media['type'] == 'media' && media['attrs']
        src = media['attrs']['url'] || media['attrs']['src']
        alt = media['attrs']['alt'] || 'image'
        return "<img src=\"#{CGI.escapeHTML(src)}\" alt=\"#{CGI.escapeHTML(alt)}\">" if src.present?
      end
    end
    ''

  when 'image'
    src = attrs['src'] || block.dig('attrs', 'src')
    alt = attrs['alt'] || block.dig('attrs', 'alt') || 'image'
    src.present? ? "<img src=\"#{CGI.escapeHTML(src)}\" alt=\"#{CGI.escapeHTML(alt)}\">" : ''

  when 'panel'
    panel_type = attrs['panelType'] || block.dig('attrs', 'panelType') || 'info'
    inner_html = convert_adf_to_html_enhanced(content, options)
    if inner_html.present?
      "<div class=\"panel panel-#{panel_type}\">#{inner_html}</div>"
    else
      ''
    end

  when 'expand'
    # Jira expand/collapse sections
    title = attrs['title'] || block.dig('attrs', 'title') || 'Details'
    inner_html = convert_adf_to_html_enhanced(content, options)
    if inner_html.present?
      "<details><summary>#{CGI.escapeHTML(title)}</summary>#{inner_html}</details>"
    else
      ''
    end

  else
    # For unknown types with content, try to process nested content
    if content.is_a?(Array) && content.any?
      if options[:debug]
        puts "    [Unknown block type: #{block_type}, attempting to process content]"
      end
      convert_adf_to_html_enhanced(content, options)
    else
      ''
    end
  end
end

def convert_adf_table_to_html_enhanced(table_block, options = {})
  return '' if table_block.nil?

  table_rows = table_block['content'] || []

  if table_rows.empty?
    # Table exists but has no content - create placeholder
    if options[:show_placeholders]
      return '<div class="missing-table"><em>[Table content unavailable from Jira API]</em></div>'
    else
      return ''
    end
  end

  rows_html = []
  has_header = false

  table_rows.each_with_index do |row, row_idx|
    next unless row.is_a?(Hash)

    row_type = row['type']&.to_s&.downcase
    next unless row_type == 'tablerow'

    cells = row['content'] || []
    cells_html = []

    cells.each do |cell|
      next unless cell.is_a?(Hash)

      cell_type_raw = cell['type']&.to_s&.downcase
      is_header = (cell_type_raw == 'tableheader' || cell_type_raw == 'tablehead')
      has_header = true if is_header && row_idx == 0

      cell_tag = is_header ? 'th' : 'td'

      cell_content = cell['content'] || []
      cell_html = convert_adf_to_html_enhanced(cell_content, options)

      # Remove wrapping p tags but preserve other formatting
      cell_html = cell_html.gsub(%r{<p>(.*?)</p>}m, '\1').strip

      # Handle empty cells
      cell_html = '&nbsp;' if cell_html.blank?

      # Handle cell attributes (colspan, rowspan, background color, etc.)
      attrs_str = ''
      if cell['attrs']
        colspan = cell['attrs']['colspan']
        rowspan = cell['attrs']['rowspan']
        bg_color = cell['attrs']['background']

        attrs_str += " colspan=\"#{colspan}\"" if colspan && colspan > 1
        attrs_str += " rowspan=\"#{rowspan}\"" if rowspan && rowspan > 1
        attrs_str += " style=\"background-color: #{CGI.escapeHTML(bg_color)}\"" if bg_color
      end

      cells_html << "<#{cell_tag}#{attrs_str}>#{cell_html}</#{cell_tag}>"
    end

    rows_html << "<tr>#{cells_html.join('')}</tr>" if cells_html.any?
  end

  if rows_html.any?
    # Wrap header rows in thead if present
    if has_header && rows_html.length > 1
      thead = "<thead>#{rows_html[0]}</thead>"
      tbody = "<tbody>#{rows_html[1..-1].join("\n")}</tbody>"
      "<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\">#{thead}#{tbody}</table>"
    else
      "<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\">#{rows_html.join("\n")}</table>"
    end
  else
    options[:show_placeholders] ? '<div class="missing-table"><em>[Empty table]</em></div>' : ''
  end
end

def convert_adf_inline_to_html_enhanced(content_array, options = {})
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |item|
    next unless item.is_a?(Hash)

    item_type = item['type']&.to_s&.downcase

    case item_type
    when 'text'
      text = item['text'].to_s
      marks = item['marks'] || []
      marked_text = CGI.escapeHTML(text)

      marks.each do |mark|
        mark_type = mark['type']&.to_s&.downcase
        case mark_type
        when 'bold', 'strong'
          marked_text = "<strong>#{marked_text}</strong>"
        when 'italic', 'em'
          marked_text = "<em>#{marked_text}</em>"
        when 'code'
          marked_text = "<code>#{marked_text}</code>"
        when 'underline'
          marked_text = "<u>#{marked_text}</u>"
        when 'strike', 'strikethrough'
          marked_text = "<s>#{marked_text}</s>"
        when 'link'
          href = mark.dig('attrs', 'href') || '#'
          marked_text = "<a href=\"#{CGI.escapeHTML(href)}\">#{marked_text}</a>"
        when 'textcolor', 'textColor'
          color = mark.dig('attrs', 'color') || '#000000'
          marked_text = "<span style=\"color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'backgroundcolor', 'backgroundColor'
          color = mark.dig('attrs', 'color') || '#ffffff'
          marked_text = "<span style=\"background-color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'subsup'
          type = mark.dig('attrs', 'type')
          if type == 'sub'
            marked_text = "<sub>#{marked_text}</sub>"
          elsif type == 'sup'
            marked_text = "<sup>#{marked_text}</sup>"
          end
        end
      end
      html_parts << marked_text if marked_text.present?

    when 'mention'
      mention_text = item.dig('attrs', 'text') || '@user'
      mention_id = item.dig('attrs', 'id')
      html_parts << "<span class=\"mention\" data-mention-id=\"#{CGI.escapeHTML(mention_id || '')}\">#{CGI.escapeHTML(mention_text)}</span>"

    when 'hardbreak', 'hard_break'
      html_parts << '<br>'

    when 'emoji'
      emoji_text = item.dig('attrs', 'text') || item.dig('attrs', 'shortName') || '😊'
      html_parts << emoji_text

    when 'inlinecard', 'card'
      url = item.dig('attrs', 'url')
      title = item.dig('attrs', 'title') || url
      url.present? ? html_parts << "<a href=\"#{CGI.escapeHTML(url)}\">#{CGI.escapeHTML(title)}</a>" : nil

    when 'date'
      timestamp = item.dig('attrs', 'timestamp')
      if timestamp
        date = Time.at(timestamp / 1000).strftime('%Y-%m-%d')
        html_parts << "<time datetime=\"#{date}\">#{date}</time>"
      end

    when 'status'
      text = item.dig('attrs', 'text') || 'Status'
      color = item.dig('attrs', 'color') || 'neutral'
      html_parts << "<span class=\"status status-#{color}\">#{CGI.escapeHTML(text)}</span>"

    else
      # Recursively handle nested content
      if item['content'].is_a?(Array)
        nested_html = convert_adf_inline_to_html_enhanced(item['content'], options)
        html_parts << nested_html if nested_html.present?
      elsif options[:debug]
        puts "      [Unknown inline type: #{item_type}]"
      end
    end
  end

  html_parts.join('')
end

def convert_adf_list_to_html_enhanced(items, tag, options = {})
  return '' if items.nil? || !items.is_a?(Array)

  list_items = []
  items.each do |item|
    next unless item.is_a?(Hash)

    item_type = item['type']&.to_s&.downcase
    next unless item_type == 'listitem'

    item_content = item['content'] || []
    item_html = convert_adf_to_html_enhanced(item_content, options)

    # Extract text if it's wrapped in <p> tags
    item_html = item_html.gsub(%r{<p>(.*?)</p>}m, '\1').strip

    list_items << "<li>#{item_html}</li>" if item_html.present?
  end

  list_items.join("\n")
end

puts "Enhanced ADF converter loaded with:"
puts "  ✅ Improved table handling (thead/tbody, colspan, rowspan, colors)"
puts "  ✅ More ADF node types (media, expand, status, date)"
puts "  ✅ Better error handling for missing content"
puts "  ✅ Placeholder support for empty tables"
puts ""
puts "Use show_placeholders: true to see placeholders for missing tables"

