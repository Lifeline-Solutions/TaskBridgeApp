#!/usr/bin/env ruby
# scripts/repair_rich_text_content.rb
# This script validates and repairs defect content and defect message content
# to ensure they match Jira data and have proper rich text formatting

require 'net/http'
require 'uri'
require 'json'
require 'time'
require 'yaml'
require 'cgi'

APP_ROOT = Rails.root

# Load configuration
config_path = APP_ROOT.join('config', 'jira_import.yml')
unless File.exist?(config_path)
  puts "ERROR: Missing config file: #{config_path}"
  exit 1
end

CONFIG = YAML.load_file(config_path).with_indifferent_access

# Jira credentials
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }

unless JIRA_API_TOKEN
  puts 'ERROR: JIRA_API_TOKEN not found in environment or config'
  exit 1
end

# Accept project key filter (e.g., KCBL) or specific issue (e.g., PSP-9)
INPUT_ARG = (ENV['PROJECT'] || ENV['JIRA_PROJECT'] || ARGV[0]).to_s.strip.upcase
SINGLE_ISSUE = INPUT_ARG =~ /^[A-Z]+-\d+$/ ? INPUT_ARG : nil
PROJECT_KEY = SINGLE_ISSUE ? nil : INPUT_ARG

# Enable debug mode to see detailed HTML extraction info
DEBUG_MODE = ENV['DEBUG'].to_s.downcase == 'true' || ENV['DEBUG'] == '1' || SINGLE_ISSUE.present?

# ===============================
# BACKGROUND EXECUTION SUPPORT
# ===============================
ALLOW_BACKGROUND = ENV.fetch('ALLOW_BACKGROUND', 'true').downcase == 'true'
BACKGROUND_LOGDIR = Rails.root.join('log', 'repairs').to_s
BACKGROUND_PIDFILE = File.join(BACKGROUND_LOGDIR, "repair_#{Time.now.strftime('%Y%m%d_%H%M%S')}.pid")
BACKGROUND_LOGFILE = File.join(BACKGROUND_LOGDIR, "repair_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")

# Ensure log directory exists
FileUtils.mkdir_p(BACKGROUND_LOGDIR)

# Write PID file for process tracking
File.write(BACKGROUND_PIDFILE, Process.pid.to_s)

# Redirect output to both console and log file
def setup_logging(logfile)
  File.open(logfile, 'a') do |_f|
    def $stdout.write(str)
      File.open(BACKGROUND_LOGFILE, 'a') { |f| f.write(str) }
      begin
        super
      rescue StandardError
        nil
      end
    end
  end
end

# Handle graceful shutdown on signals
$shutdown_requested = false
$current_issue_key = nil
$repair_start_time = Time.now

Signal.trap('TERM') do
  puts "\n\n⚠️  Received SIGTERM - will finish current issue then exit gracefully"
  $shutdown_requested = true
end

Signal.trap('INT') do
  puts "\n\n⚠️  Received SIGINT - will finish current issue then exit gracefully"
  $shutdown_requested = true
end

# Setup logging if running in background
setup_logging(BACKGROUND_LOGFILE) if ALLOW_BACKGROUND

# Statistics tracking
$STATS = {
  total_defects: 0,
  defects_checked: 0,
  defect_content_updated: 0,
  defect_content_failed: 0,
  total_comments: 0,
  comments_checked: 0,
  comments_updated: 0,
  comments_failed: 0,
  comments_empty_skipped: 0
}

puts '=' * 80
puts '🔧 JIRA RICH TEXT CONTENT REPAIR SCRIPT'
puts '=' * 80
puts ''
puts "Time: #{Time.now}"
puts "PID: #{Process.pid}"
puts "Log: #{BACKGROUND_LOGFILE}"
puts "Background Mode: #{ALLOW_BACKGROUND ? 'ENABLED' : 'DISABLED'}"
puts ''
if SINGLE_ISSUE.present?
  puts "Target: Single issue #{SINGLE_ISSUE}"
  puts 'Debug mode: ENABLED (auto-enabled for single issue)'
elsif PROJECT_KEY.present?
  puts "Target project: #{PROJECT_KEY}"
  puts "Debug mode: #{DEBUG_MODE ? 'ENABLED' : 'disabled'}"
else
  puts 'Target project: (all projects)'
  puts "Debug mode: #{DEBUG_MODE ? 'ENABLED' : 'disabled'}"
  puts 'Tip: Run for a single project: rails runner scripts/repair_rich_text_content.rb KCBL'
end
puts 'Tip: Run for a single issue: rails runner scripts/repair_rich_text_content.rb PSP-9'
puts ''

# ===============================
# ADF TO HTML CONVERSION (ENHANCED)
# ===============================

# Convert Jira ADF (Atlassian Document Format) to HTML for ActionText
def convert_adf_to_html(content_array, debug: false)
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |block|
    next unless block.is_a?(Hash)

    block_html = convert_adf_block_to_html(block, debug: debug)

    # Ensure we capture the content - don't skip if we get a result
    if block_html.present?
      html_parts << block_html
    elsif debug || DEBUG_MODE
      # Log blocks that returned empty
      block_type = block['type']&.to_s&.downcase
      if block_type == 'table'
        puts '      [WARNING: Table block returned empty HTML - checking content]'
        puts "      [Block structure: #{block.keys.join(', ')}]"
      end
    end
  end

  html_parts.join("\n")
end

# Convert a single ADF block to HTML
def convert_adf_block_to_html(block, debug: false)
  return '' if block.nil? || !block.is_a?(Hash)

  block_type = block['type']&.to_s&.downcase
  content = block['content'] || []
  attrs = block['attrs'] || {}

  case block_type
  when 'paragraph'
    inner_html = convert_adf_inline_to_html(content, debug: debug)
    inner_html.present? ? "<p>#{inner_html}</p>" : ''

  when 'heading'
    inner_html = convert_adf_inline_to_html(content, debug: debug)
    level = attrs['level'] || block.dig('attrs', 'level') || 1
    inner_html.present? ? "<h#{level}>#{inner_html}</h#{level}>" : ''

  when 'bulletlist', 'bullet_list'
    list_html = convert_adf_list_to_html(content, 'ul', debug: debug)
    list_html.present? ? "<ul>#{list_html}</ul>" : ''

  when 'orderedlist', 'ordered_list'
    list_html = convert_adf_list_to_html(content, 'ol', debug: debug)
    list_html.present? ? "<ol>#{list_html}</ol>" : ''

  when 'table'
    table_html = convert_adf_table_to_html(block, debug: debug)
    if debug || DEBUG_MODE
      if table_html.present?
        puts "      [Table converted successfully: #{table_html.length} chars]"
      else
        puts '      [WARNING: Table block found but conversion returned empty]'
        puts "      [Table keys: #{block.keys.join(', ')}]"
        puts "      [Table content count: #{(block['content'] || []).length}]"
      end
    end
    table_html

  when 'codeblock', 'code_block'
    code_text = convert_adf_inline_to_html(content, debug: debug)
    if code_text.present?
      lang = attrs['language'] || block.dig('attrs', 'language') || 'plaintext'
      "<pre><code class=\"language-#{lang}\">#{CGI.escapeHTML(code_text)}</code></pre>"
    else
      ''
    end

  when 'blockquote'
    inner_html = convert_adf_inline_to_html(content, debug: debug)
    inner_html.present? ? "<blockquote>#{inner_html}</blockquote>" : ''

  when 'horizontalrule', 'horizontal_rule', 'rule', 'hr'
    '<hr>'

  when 'mediasingle', 'media'
    # Handle images/media embedded in content
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
    # Jira panels (info, warning, error, success, note)
    panel_type = attrs['panelType'] || block.dig('attrs', 'panelType') || 'info'
    inner_html = convert_adf_to_html(content, debug: debug)
    if inner_html.present?
      "<div class=\"panel panel-#{panel_type}\">#{inner_html}</div>"
    else
      ''
    end

  when 'expand'
    # Jira expand/collapse sections
    title = attrs['title'] || block.dig('attrs', 'title') || 'Details'
    inner_html = convert_adf_to_html(content, debug: debug)
    if inner_html.present?
      "<details><summary>#{CGI.escapeHTML(title)}</summary>#{inner_html}</details>"
    else
      ''
    end

  else
    # For unknown types with content, try to process nested content
    if content.is_a?(Array) && content.any?
      puts "      [Unknown block type: #{block_type}, processing nested content]" if debug || DEBUG_MODE
      convert_adf_to_html(content, debug: debug)
    else
      ''
    end
  end
end

# Convert ADF inline content (text, mentions, etc) to HTML
def convert_adf_inline_to_html(content_array, debug: false)
  return '' if content_array.nil? || !content_array.is_a?(Array)

  html_parts = []
  content_array.each do |item|
    next unless item.is_a?(Hash)

    item_type = item['type']&.to_s&.downcase

    case item_type
    when 'text'
      text = item['text'].to_s
      # Apply marks (bold, italic, code, colors, etc)
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
        date = begin
          Time.at(timestamp / 1000).strftime('%Y-%m-%d')
        rescue StandardError
          timestamp.to_s
        end
        html_parts << "<time datetime=\"#{date}\">#{date}</time>"
      end

    when 'status'
      text = item.dig('attrs', 'text') || 'Status'
      color = item.dig('attrs', 'color') || 'neutral'
      html_parts << "<span class=\"status status-#{color}\">#{CGI.escapeHTML(text)}</span>"

    else
      # Recursively handle nested content
      if item['content'].is_a?(Array)
        nested_html = convert_adf_inline_to_html(item['content'], debug: debug)
        html_parts << nested_html if nested_html.present?
      elsif debug || DEBUG_MODE
        puts "      [Unknown inline type: #{item_type}]"
      end
    end
  end

  html_parts.join
end

# Convert ADF list to HTML
def convert_adf_list_to_html(items, _tag, debug: false)
  return '' if items.nil? || !items.is_a?(Array)

  list_items = []
  items.each do |item|
    next unless item.is_a?(Hash) && item['type'] == 'listitem'

    item_content = item['content'] || []
    item_html = convert_adf_to_html(item_content, debug: debug)
    # Extract text if it's wrapped in <p> tags
    item_html = item_html.gsub(%r{<p>(.*?)</p>}, '\1')
    list_items << "<li>#{item_html}</li>" if item_html.present?
  end

  list_items.join("\n")
end

# Convert ADF table to HTML (Enhanced with CSS styling)
def convert_adf_table_to_html(table_block, debug: false)
  return '' if table_block.nil?

  table_rows = table_block['content'] || []

  if table_rows.empty?
    # Table block exists but has no rows
    if debug || DEBUG_MODE
      puts '      [WARNING: Table block found but has no content]'
      puts '      [Checking table block structure...]'
      puts "      [Table block keys: #{table_block.keys.join(', ')}]"
    end
    return ''
  end

  rows_html = []
  has_header = false
  total_cells = 0

  # CSS styling for the table wrapper and elements
  table_wrapper_style = 'width: 100%; border-collapse: collapse; margin: 10px 0; display: table;'
  table_style = 'border: 1px solid #ccc; border-collapse: collapse; width: 100%; font-family: Arial, sans-serif; font-size: 14px;'
  header_style = 'border: 1px solid #ccc; padding: 10px; background-color: #e8e8e8; font-weight: bold; text-align: left; vertical-align: top;'
  cell_style = 'border: 1px solid #ccc; padding: 10px; text-align: left; vertical-align: top;'

  table_rows.each_with_index do |row, row_idx|
    next unless row.is_a?(Hash)

    # Handle both 'tablerow' and 'tableRow' (case variations)
    row_type = row['type']&.to_s&.downcase
    next unless row_type == 'tablerow'

    cells = row['content'] || []
    cells_html = []

    cells.each do |cell|
      next unless cell.is_a?(Hash)

      # Handle tableHeader, tableCell, tablehead, tableHead variations
      cell_type_raw = cell['type']&.to_s&.downcase
      is_header = %w[tableheader tablehead].include?(cell_type_raw)
      has_header = true if is_header && row_idx.zero?

      cell_tag = is_header ? 'th' : 'td'
      cell_inline_style = is_header ? header_style : cell_style

      cell_content = cell['content'] || []

      # Recursively convert cell content to HTML
      cell_html = if cell_content.any?
                    convert_adf_to_html(cell_content, debug: debug)
                  else
                    '&nbsp;'
                  end

      # Remove wrapping p tags but preserve other formatting (lists, tables within cells, etc)
      cell_html = cell_html.gsub(%r{<p>(.*?)</p>}m, '\1').strip

      # Preserve HTML content without extra escaping
      cell_html = '&nbsp;' if cell_html.blank?

      total_cells += 1

      # Build cell attributes string
      attrs_str = " style=\"#{cell_inline_style}"

      # Handle cell attributes (colspan, rowspan, background color)
      if cell['attrs']
        colspan = cell['attrs']['colspan']
        rowspan = cell['attrs']['rowspan']
        bg_color = cell['attrs']['background']

        attrs_str += " background-color: #{CGI.escapeHTML(bg_color)};" if bg_color
      end

      attrs_str += '"'

      # Add colspan and rowspan attributes
      if cell['attrs']
        colspan = cell['attrs']['colspan']
        rowspan = cell['attrs']['rowspan']
        attrs_str += " colspan=\"#{colspan}\"" if colspan && colspan > 1
        attrs_str += " rowspan=\"#{rowspan}\"" if rowspan && rowspan > 1
      end

      cells_html << "<#{cell_tag}#{attrs_str}>#{cell_html}</#{cell_tag}>"
    end

    rows_html << "<tr>#{cells_html.join}</tr>" if cells_html.any?
  end

  puts "      [Table: #{table_rows.length} rows, #{total_cells} total cells, #{rows_html.length} rendered rows]" if debug || DEBUG_MODE

  if rows_html.any?
    # Build complete table with proper styling
    table_content = if has_header && rows_html.length > 1
                      thead = "<thead>#{rows_html[0]}</thead>"
                      tbody = "<tbody>#{rows_html[1..].join("\n")}</tbody>"
                      "#{thead}#{tbody}"
                    else
                      "<tbody>#{rows_html.join("\n")}</tbody>"
                    end

    # Wrap table with comprehensive styling for rich text display
    table_html = "<div style=\"#{table_wrapper_style}\"><table style=\"#{table_style}\">#{table_content}</table></div>"

    if debug || DEBUG_MODE
      puts "      [Table HTML generated: #{table_html.length} chars]"
      puts "      [Starts with: #{table_html[0..80]}...]"
    end

    table_html
  else
    ''
  end
end

# Extract description from Jira field
def extract_description(field, debug: false)
  return '' if field.nil?
  return field if field.is_a?(String)

  if field.is_a?(Hash)
    # Jira description is in ADF format - convert to HTML
    content_blocks = field['content'] || []

    if debug && content_blocks.any?
      block_types = content_blocks.map { |b| b['type'] }.compact
      puts "    [ADF blocks: #{block_types.join(', ')}]"
    end

    html = convert_adf_to_html(content_blocks)
    return html.present? ? html : ''
  end
  field.to_s
end

# Prefer rendered HTML description if present
def extract_issue_description_html(jira_issue, debug: false)
  # Jira Cloud provides renderedFields when requested via expand
  rendered_desc = jira_issue.dig('renderedFields', 'description') || jira_issue.dig('fields', 'renderedFields', 'description')

  if rendered_desc.present?
    # Check if rendered HTML contains ADF macro placeholders instead of actual content
    # These appear as <!-- ADF macro (type = 'table') --> or similar
    if rendered_desc.include?('<!-- ADF macro')
      puts '    [Rendered HTML has ADF macros - using ADF conversion instead]' if debug
      jira_description_field = jira_issue.dig('fields', 'description')

      # Debug: Show what we're getting from Jira
      if debug || DEBUG_MODE
        if jira_description_field.nil?
          puts '    [ERROR: No description field in Jira response!]'
        elsif jira_description_field.is_a?(String) && jira_description_field.blank?
          puts '    [ERROR: Description field is empty string]'
        elsif jira_description_field.is_a?(Hash)
          content = jira_description_field['content']
          if content.nil?
            puts "    [ERROR: Description has no 'content' key]"
            puts "    [Description keys: #{jira_description_field.keys.join(', ')}]"
          elsif content.is_a?(Array) && content.empty?
            puts '    [WARNING: Description content array is empty]'
          elsif content.is_a?(Array)
            puts "    [ADF has #{content.length} block(s)]"
          end
        end
      end

      return extract_description(jira_description_field, debug: debug)
    end

    puts '    [Using rendered HTML]' if debug
    return rendered_desc.to_s
  end

  # Fall back to raw field and ADF conversion
  puts '    [No rendered HTML available - using ADF conversion]' if debug
  jira_description_field = jira_issue.dig('fields', 'description')

  puts '    [ERROR: No description field found in Jira response]' if (debug || DEBUG_MODE) && jira_description_field.nil?

  extract_description(jira_description_field, debug: debug)
end

# ===============================
# JIRA API FUNCTIONS
# ===============================

# Fetch a single issue from Jira with full details
def fetch_jira_issue(issue_key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}"
  uri = URI.parse(url)

  # Request all fields including description, comments, etc.
  uri.query = URI.encode_www_form({
                                    expand: 'renderedFields,names,schema,operations,editmeta,changelog,versionedRepresentations',
                                    fields: '*all'
                                  })

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    warn "  ❌ Failed to fetch #{issue_key} from Jira: #{response.code} #{response.message}"
    return nil
  end

  JSON.parse(response.body)
rescue StandardError => e
  warn "  ❌ Error fetching #{issue_key}: #{e.class}: #{e.message}"
  nil
end

# Fetch comments for an issue (prefer rendered HTML)
def fetch_jira_comments(issue_key)
  url = "#{JIRA_BASE_URL}/rest/api/3/issue/#{issue_key}/comment"
  uri = URI.parse(url)

  # Ask Jira to include renderedBody for comments
  uri.query = URI.encode_www_form({ expand: 'renderedBody' })

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 120

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Accept'] = 'application/json'
  request.basic_auth(JIRA_API_USER, JIRA_API_TOKEN)

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    warn "  ❌ Failed to fetch comments for #{issue_key}: #{response.code} #{response.message}"
    return []
  end

  data = JSON.parse(response.body)
  data['comments'] || []
rescue StandardError => e
  warn "  ❌ Error fetching comments for #{issue_key}: #{e.class}: #{e.message}"
  []
end

# ===============================
# CONTENT COMPARISON & UPDATE
# ===============================

# Normalize HTML for comparison (remove whitespace differences)
def normalize_html(html)
  return '' if html.nil?

  html.to_s.gsub(/\s+/, ' ').strip.downcase
end

# Compare and update defect description
def repair_defect_content(defect, debug: false)
  issue_key = defect.defect_unique

  print "  📄 Checking #{issue_key} description... "

  # Fetch fresh data from Jira
  jira_issue = fetch_jira_issue(issue_key)
  unless jira_issue
    puts '❌ FAILED (could not fetch from Jira)'
    $STATS[:defect_content_failed] += 1
    return false
  end

  # For single issue mode, save the response for inspection
  if SINGLE_ISSUE.present?
    require 'fileutils'
    FileUtils.mkdir_p('tmp')
    filename = "tmp/jira_response_#{issue_key.gsub('-', '_')}.json"
    File.write(filename, JSON.pretty_generate(jira_issue))
    puts "\n    [Saved full Jira response to: #{filename}]"
  end

  puts '' if debug

  # Extract description from Jira (prefer rendered HTML)
  jira_description_html = extract_issue_description_html(jira_issue, debug: debug)

  # Get current description from database
  current_description = defect.content.to_s.strip

  # Debug: show what we're getting
  if debug || DEBUG_MODE
    puts "    [Current DB content: #{current_description.length} chars]"
    puts "    [Jira content: #{jira_description_html.length} chars]"
    puts '    [✅ Jira has table content]' if jira_description_html.include?('<table')
  end

  # Normalize for comparison
  jira_normalized = normalize_html(jira_description_html)
  current_normalized = normalize_html(current_description)

  if jira_normalized == current_normalized
    puts '✅ OK (already in sync)'
    return false
  end

  # Content differs - update it
  begin
    # Ensure we're not saving empty content
    if jira_description_html.blank? && current_description.present?
      puts '⚠️  SKIPPED (Jira returned empty, keeping current content)'
      return false
    end

    defect.content = jira_description_html
    defect.save!(validate: false)

    puts "✅ UPDATED (#{jira_description_html.length} chars)"
    $STATS[:defect_content_updated] += 1
    true
  rescue StandardError => e
    puts "❌ FAILED (#{e.message})"
    $STATS[:defect_content_failed] += 1
    false
  end
end

# Compare and update defect messages (comments)
def repair_defect_messages(defect, debug: false)
  issue_key = defect.defect_unique

  print "  💬 Checking #{issue_key} comments... "

  # Fetch fresh comments from Jira
  jira_comments = fetch_jira_comments(issue_key)

  if jira_comments.empty?
    puts '⏭️  SKIP (no comments in Jira)'
    return { updated: 0, failed: 0 }
  end

  puts ''
  puts "    Found #{jira_comments.length} comment(s) in Jira"

  stats = { updated: 0, failed: 0 }

  # Track processed Jira comment IDs to prevent duplicates
  processed_jira_ids = Set.new

  # Collect all existing messages to avoid multiple database queries
  existing_messages = defect.defect_messages.index_by { |dm| dm.id }

  jira_comments.each_with_index do |jira_comment, idx|
    $STATS[:comments_checked] += 1

    # Extract comment data
    jira_comment_id = jira_comment['id'].to_s

    # Skip if we've already processed this Jira comment in this run
    if processed_jira_ids.include?(jira_comment_id)
      puts "    [#{idx + 1}/#{jira_comments.length}] Comment #{jira_comment_id}... ⚠️  DUPLICATE (skipped, already processed in this run)"
      next
    end

    processed_jira_ids.add(jira_comment_id)

    author_name = jira_comment.dig('author', 'displayName')
    created_at_str = jira_comment['created']
    created_at = begin
      Time.parse(created_at_str)
    rescue StandardError
      nil
    end

    # Prefer rendered HTML body
    jira_body_html = jira_comment['renderedBody']

    # Check if rendered HTML contains ADF macro placeholders
    if jira_body_html.present? && jira_body_html.include?('<!-- ADF macro')
      puts "    [Comment #{idx + 1}: Rendered HTML has ADF macros - using ADF conversion instead]" if debug
      jira_body_html = nil # Force fallback to ADF conversion
    elsif debug && jira_body_html.present?
      puts "    [Comment #{idx + 1}: Using rendered HTML]"
    end

    # Fall back to ADF body -> HTML if rendered not available or has macros
    if jira_body_html.blank?
      puts "    [Comment #{idx + 1}: Using ADF conversion]" if debug
      body_field = jira_comment['body']
      jira_body_html = if body_field.is_a?(Hash)
                         convert_adf_to_html(body_field['content'] || [], debug: debug)
                       elsif body_field.is_a?(String)
                         body_field.strip
                       else
                         body_field.to_s.strip
                       end
    end

    # Skip empty comments
    if jira_body_html.blank?
      $STATS[:comments_empty_skipped] += 1
      next
    end

    print "    [#{idx + 1}/#{jira_comments.length}] Comment by #{author_name}... "

    # Try to find matching comment in database using multiple strategies
    existing_message = nil

    if created_at
      # Strategy 1: Find by timestamp (within 5 second window) - most reliable
      existing_message = defect.defect_messages.find do |dm|
        dm.created_at && (dm.created_at - created_at).abs < 5
      end
    end

    # Strategy 2: If not found by timestamp, try by normalized content
    unless existing_message
      jira_normalized = normalize_html(jira_body_html)
      existing_message = defect.defect_messages.find do |dm|
        current_content = dm.content.to_s.strip
        current_normalized = normalize_html(current_content)
        current_normalized == jira_normalized
      end
    end

    if existing_message
      # Found existing message - check if content matches
      current_content = existing_message.content.to_s.strip
      current_normalized = normalize_html(current_content)
      jira_normalized = normalize_html(jira_body_html)

      if current_normalized == jira_normalized
        puts '✅ OK (already in sync)'
      else
        # Content differs - update it
        begin
          existing_message.content = jira_body_html
          existing_message.save!(validate: false)

          puts "✅ UPDATED (#{jira_body_html.length} chars)"
          $STATS[:comments_updated] += 1
          stats[:updated] += 1
        rescue StandardError => e
          puts "❌ FAILED (#{e.message})"
          $STATS[:comments_failed] += 1
          stats[:failed] += 1
        end
      end
    else
      # Comment doesn't exist in database - create it, but ensure it's distinct
      begin
        # Final check: ensure no duplicate content before creating
        jira_normalized = normalize_html(jira_body_html)
        final_check = defect.defect_messages.any? do |dm|
          current_normalized = normalize_html(dm.content.to_s.strip)
          current_normalized == jira_normalized
        end

        if final_check
          puts "⚠️  SKIPPED (duplicate content detected, not creating)"
          next
        end

        # Try to find user by name
        user = User.find_by('first_name || \' \' || last_name ILIKE ?', "%#{author_name}%") || User.first

        dm = DefectMessage.new(
          defect: defect,
          user: user,
          modified_by: user,
          created_at: created_at || Time.current
        )
        dm.content = jira_body_html
        dm.save!(validate: false)

        puts "✅ CREATED (#{jira_body_html.length} chars)"
        $STATS[:comments_updated] += 1
        stats[:updated] += 1
      rescue StandardError => e
        puts "❌ FAILED to create (#{e.message})"
        $STATS[:comments_failed] += 1
        stats[:failed] += 1
      end
    end
  end

  stats
end

# ===============================
# MAIN EXECUTION
# ===============================

puts '🔍 Finding all defects with Jira keys...'
defects = if SINGLE_ISSUE.present?
            # Process a single specific issue
            Defect.where(defect_unique: SINGLE_ISSUE).where(deleted_on: nil)
          elsif PROJECT_KEY.present?
            # Constrain to a single project key like KCBL
            # Using ~ for regex and anchoring at start to the project key
            Defect.where('defect_unique ~ ?', "^#{Regexp.escape(PROJECT_KEY)}-[0-9]+$").where(deleted_on: nil).order(:defect_unique)
          else
            # All projects
            Defect.where("defect_unique ~ '^[A-Z]+-[0-9]+$'").where(deleted_on: nil).order(:defect_unique)
          end
$STATS[:total_defects] = defects.count

if SINGLE_ISSUE.present?
  if $STATS[:total_defects].zero?
    puts "   ❌ Issue #{SINGLE_ISSUE} not found in database"
    puts '   Tip: Check if the issue has been imported from Jira'
    exit 1
  else
    puts "   ✅ Found issue #{SINGLE_ISSUE}"
  end
else
  puts "   Found #{$STATS[:total_defects]} defect(s) with Jira keys"
end
puts ''

if $STATS[:total_defects].zero?
  puts 'No defects found to repair. Exiting.'
  exit 0
end

puts '=' * 80
puts '🔧 STARTING REPAIR PROCESS'
puts '=' * 80
puts ''

defects.each_with_index do |defect, idx|
  # Check for shutdown signal - complete current issue then exit
  if $shutdown_requested
    puts "\n⏹️  Shutdown signal received - completing current issue then exiting..."
    puts "Processed #{$STATS[:defects_checked]} of #{$STATS[:total_defects]} defects before shutdown"
    break
  end

  $STATS[:defects_checked] += 1
  issue_key = defect.defect_unique
  $current_issue_key = issue_key

  puts "[#{idx + 1}/#{$STATS[:total_defects]}] Processing #{defect.defect_unique}"

  # For single issue, show current content
  if SINGLE_ISSUE.present?
    puts ''
    puts '=' * 80
    puts 'CURRENT CONTENT IN DATABASE'
    puts '=' * 80
    current_content = defect.content.to_s
    puts "Length: #{current_content.length} characters"
    puts "Has <table>: #{current_content.include?('<table')}"
    puts "Has <ul> or <ol>: #{current_content.include?('<ul>') || current_content.include?('<ol>')}"
    puts ''
    puts 'Content preview (first 1000 chars):'
    puts '-' * 80
    puts current_content[0..1000]
    puts '-' * 80
    puts ''
  end

  # Repair defect description
  description_updated = repair_defect_content(defect, debug: DEBUG_MODE)

  # For single issue, show updated content
  if SINGLE_ISSUE.present? && description_updated
    puts ''
    puts '=' * 80
    puts 'UPDATED CONTENT FROM JIRA'
    puts '=' * 80
    updated_content = defect.reload.content.to_s
    puts "Length: #{updated_content.length} characters"
    puts "Has <table>: #{updated_content.include?('<table')}"
    puts "Has <ul> or <ol>: #{updated_content.include?('<ul>') || updated_content.include?('<ol>')}"
    puts ''
    puts 'Full updated content:'
    puts '-' * 80
    puts updated_content
    puts '-' * 80
    puts ''
  end

  # Repair defect comments
  comment_stats = repair_defect_messages(defect, debug: DEBUG_MODE)
  $STATS[:total_comments] += comment_stats[:updated] + comment_stats[:failed]

  puts ''

  # Small delay to avoid overwhelming Jira API (skip for single issue)
  sleep 0.5 unless SINGLE_ISSUE.present?
end

# ===============================
# FINAL REPORT
# ===============================

puts '=' * 80
puts '📊 REPAIR COMPLETE - FINAL STATISTICS'
puts '=' * 80
puts ''

puts 'Defects:'
puts "  Total defects found:       #{$STATS[:total_defects]}"
puts "  Defects checked:           #{$STATS[:defects_checked]}"
puts "  Descriptions updated:      #{$STATS[:defect_content_updated]}"
puts "  Description update failed: #{$STATS[:defect_content_failed]}"
puts ''

puts 'Comments:'
puts "  Total comments checked:    #{$STATS[:comments_checked]}"
puts "  Comments updated/created:  #{$STATS[:comments_updated]}"
puts "  Comments update failed:    #{$STATS[:comments_failed]}"
puts "  Empty comments skipped:    #{$STATS[:comments_empty_skipped]}"
puts ''

success_rate_defects = if $STATS[:defects_checked].positive?
                         (($STATS[:defect_content_updated].to_f / $STATS[:defects_checked]) * 100).round(2)
                       else
                         0
                       end

success_rate_comments = if $STATS[:comments_checked].positive?
                          (($STATS[:comments_updated].to_f / $STATS[:comments_checked]) * 100).round(2)
                        else
                          0
                        end

puts 'Success Rates:'
puts "  Defect descriptions:       #{success_rate_defects}%"
puts "  Comments:                  #{success_rate_comments}%"
puts ''

if $STATS[:defect_content_failed].positive? || $STATS[:comments_failed].positive?
  puts '⚠️  Some items failed to update. Check the errors above for details.'
else
  puts '✅ All items processed successfully!'
end

puts ''
puts '=' * 80

# ===============================
# CLEANUP & FINAL SUMMARY
# ===============================
puts "\n#{'=' * 80}"
puts '✅ REPAIR PROCESS COMPLETED'
puts '=' * 80
puts "Completion Time: #{Time.now}"
puts "Total Runtime: #{(Time.now - $repair_start_time).round(2)} seconds"
puts ''
puts 'Summary:'
puts "  Process ID: #{Process.pid}"
puts "  Log File: #{BACKGROUND_LOGFILE}"
puts "  PID File: #{BACKGROUND_PIDFILE}"
puts ''

# Mark as complete
completion_file = File.join(BACKGROUND_LOGDIR, "repair_#{Time.now.strftime('%Y%m%d_%H%M%S')}.complete")
File.write(completion_file, "Completed at #{Time.now}\nTotal defects: #{$STATS[:total_defects]}\nSuccessful: #{$STATS[:defect_content_updated]}\nErrors: #{$STATS[:defect_content_failed]}")

puts '✅ Repair process finished successfully!'
puts '=' * 80

# Clean up PID file
FileUtils.rm_f(BACKGROUND_PIDFILE)
