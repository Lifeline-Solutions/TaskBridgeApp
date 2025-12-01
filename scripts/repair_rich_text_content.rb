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

# Accept project key filter (e.g., KCBL)
PROJECT_KEY = (ENV['PROJECT'] || ENV['JIRA_PROJECT'] || ARGV[0]).to_s.strip.upcase

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

puts "=" * 80
puts "🔧 JIRA RICH TEXT CONTENT REPAIR SCRIPT"
puts "=" * 80
puts ""
if PROJECT_KEY.present?
  puts "Target project: #{PROJECT_KEY}"
else
  puts "Target project: (all projects)"
  puts "Tip: Run for a single project: rails runner scripts/repair_rich_text_content.rb KCBL"
end
puts ""

# ===============================
# ADF TO HTML CONVERSION (ENHANCED)
# ===============================

# Convert Jira ADF (Atlassian Document Format) to HTML for ActionText
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

# Convert a single ADF block to HTML
def convert_adf_block_to_html(block)
  return '' if block.nil? || !block.is_a?(Hash)

  block_type = block['type']&.to_s&.downcase
  content = block['content'] || []

  case block_type
  when 'paragraph'
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<p>#{inner_html}</p>" : ''

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

  when 'table'
    convert_adf_table_to_html(block)

  when 'codeblock', 'code_block'
    code_text = convert_adf_inline_to_html(content)
    if code_text.present?
      lang = block.dig('attrs', 'language') || 'plaintext'
      "<pre><code class=\"language-#{lang}\">#{CGI.escapeHTML(code_text)}</code></pre>"
    else
      ''
    end

  when 'blockquote'
    inner_html = convert_adf_inline_to_html(content)
    inner_html.present? ? "<blockquote>#{inner_html}</blockquote>" : ''

  when 'horizontalrule', 'horizontal_rule', 'hr'
    '<hr>'

  when 'image'
    src = block.dig('attrs', 'src')
    alt = block.dig('attrs', 'alt') || 'image'
    src.present? ? "<img src=\"#{CGI.escapeHTML(src)}\" alt=\"#{CGI.escapeHTML(alt)}\">" : ''

  when 'panel'
    # Jira panels (info, warning, error, success, note)
    panel_type = block.dig('attrs', 'panelType') || 'info'
    inner_html = convert_adf_to_html(content)
    if inner_html.present?
      "<div class=\"panel panel-#{panel_type}\">#{inner_html}</div>"
    else
      ''
    end

  else
    # For unknown types with content, try to process nested content
    convert_adf_to_html(content) if content.is_a?(Array)
  end
end

# Convert ADF inline content (text, mentions, etc) to HTML
def convert_adf_inline_to_html(content_array)
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
      marked_text = text
      marks.each do |mark|
        mark_type = mark['type']&.to_s&.downcase
        case mark_type
        when 'bold', 'strong'
          marked_text = "<strong>#{marked_text}</strong>"
        when 'italic', 'em'
          marked_text = "<em>#{marked_text}</em>"
        when 'code'
          marked_text = "<code>#{CGI.escapeHTML(marked_text)}</code>"
        when 'underline'
          marked_text = "<u>#{marked_text}</u>"
        when 'strikethrough'
          marked_text = "<s>#{marked_text}</s>"
        when 'link'
          href = mark.dig('attrs', 'href') || '#'
          marked_text = "<a href=\"#{CGI.escapeHTML(href)}\">#{marked_text}</a>"
        when 'textcolor', 'textColor'
          # Support for text color formatting
          color = mark.dig('attrs', 'color') || '#000000'
          marked_text = "<span style=\"color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'backgroundcolor', 'backgroundColor'
          # Support for background color formatting
          color = mark.dig('attrs', 'color') || '#ffffff'
          marked_text = "<span style=\"background-color: #{CGI.escapeHTML(color)}\">#{marked_text}</span>"
        when 'subsup'
          # Support for superscript/subscript
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
      html_parts << "<span class=\"mention\">#{CGI.escapeHTML(mention_text)}</span>"

    when 'hardbreak'
      html_parts << '<br>'

    when 'emoji'
      emoji_text = item.dig('attrs', 'text') || '😊'
      html_parts << emoji_text

    when 'inlinecard', 'card'
      url = item.dig('attrs', 'url')
      title = item.dig('attrs', 'title') || url
      url.present? ? html_parts << "<a href=\"#{CGI.escapeHTML(url)}\">#{CGI.escapeHTML(title)}</a>" : nil

    else
      # Recursively handle nested content
      if item['content'].is_a?(Array)
        nested_html = convert_adf_inline_to_html(item['content'])
        html_parts << nested_html if nested_html.present?
      end
    end
  end

  html_parts.join('')
end

# Convert ADF list to HTML
def convert_adf_list_to_html(items, tag)
  return '' if items.nil? || !items.is_a?(Array)

  list_items = []
  items.each do |item|
    next unless item.is_a?(Hash) && item['type'] == 'listitem'

    item_content = item['content'] || []
    item_html = convert_adf_to_html(item_content)
    # Extract text if it's wrapped in <p> tags
    item_html = item_html.gsub(/<p>(.*?)<\/p>/, '\1')
    list_items << "<li>#{item_html}</li>" if item_html.present?
  end

  list_items.join("\n")
end

# Convert ADF table to HTML
def convert_adf_table_to_html(table_block)
  return '' if table_block.nil?

  table_rows = table_block['content'] || []
  return '' if table_rows.empty?

  rows_html = []
  table_rows.each do |row|
    next unless row.is_a?(Hash) && row['type'] == 'tablerow'

    cells = row['content'] || []
    cells_html = []
    cells.each do |cell|
      next unless cell.is_a?(Hash)

      cell_type = cell['type'] == 'tablehead' ? 'th' : 'td'
      cell_content = cell['content'] || []
      cell_html = convert_adf_to_html(cell_content)
      # Remove wrapping p tags
      cell_html = cell_html.gsub(/<p>(.*?)<\/p>/, '\1')
      cells_html << "<#{cell_type}>#{cell_html}</#{cell_type}>"
    end

    rows_html << "<tr>#{cells_html.join('')}</tr>" if cells_html.any?
  end

  rows_html.any? ? "<table>#{rows_html.join("\n")}</table>" : ''
end

# Extract description from Jira field
def extract_description(field)
  return '' if field.nil?
  return field if field.is_a?(String)

  if field.is_a?(Hash)
    # Jira description is in ADF format - convert to HTML
    html = convert_adf_to_html(field['content'] || [])
    return html.present? ? html : ''
  end
  field.to_s
end

# Prefer rendered HTML description if present
def extract_issue_description_html(jira_issue)
  # Jira Cloud provides renderedFields when requested via expand
  rendered_desc = jira_issue.dig('renderedFields', 'description') || jira_issue.dig('fields', 'renderedFields', 'description')
  return rendered_desc.to_s if rendered_desc.present?

  # Fall back to raw field and ADF conversion
  jira_description_field = jira_issue.dig('fields', 'description')
  extract_description(jira_description_field)
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
def repair_defect_content(defect)
  issue_key = defect.defect_unique

  print "  📄 Checking #{issue_key} description... "

  # Fetch fresh data from Jira
  jira_issue = fetch_jira_issue(issue_key)
  unless jira_issue
    puts "❌ FAILED (could not fetch from Jira)"
    $STATS[:defect_content_failed] += 1
    return false
  end

  # Extract description from Jira (prefer rendered HTML)
  jira_description_html = extract_issue_description_html(jira_issue)

  # Get current description from database
  current_description = defect.content.to_s.strip

  # Normalize for comparison
  jira_normalized = normalize_html(jira_description_html)
  current_normalized = normalize_html(current_description)

  if jira_normalized == current_normalized
    puts "✅ OK (already in sync)"
    return false
  end

  # Content differs - update it
  begin
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
def repair_defect_messages(defect)
  issue_key = defect.defect_unique

  print "  💬 Checking #{issue_key} comments... "

  # Fetch fresh comments from Jira
  jira_comments = fetch_jira_comments(issue_key)

  if jira_comments.empty?
    puts "⏭️  SKIP (no comments in Jira)"
    return { updated: 0, failed: 0 }
  end

  puts ""
  puts "    Found #{jira_comments.length} comment(s) in Jira"

  stats = { updated: 0, failed: 0 }

  jira_comments.each_with_index do |jira_comment, idx|
    $STATS[:comments_checked] += 1

    # Extract comment data
    comment_id = jira_comment['id']
    author_name = jira_comment.dig('author', 'displayName')
    created_at_str = jira_comment['created']
    created_at = Time.parse(created_at_str) rescue nil

    # Prefer rendered HTML body
    jira_body_html = jira_comment['renderedBody']

    # Fall back to ADF body -> HTML if rendered not available
    if jira_body_html.blank?
      body_field = jira_comment['body']
      if body_field.is_a?(Hash)
        jira_body_html = convert_adf_to_html(body_field['content'] || [])
      elsif body_field.is_a?(String)
        jira_body_html = body_field.strip
      else
        jira_body_html = body_field.to_s.strip
      end
    end

    # Skip empty comments
    if jira_body_html.blank?
      $STATS[:comments_empty_skipped] += 1
      next
    end

    print "    [#{idx + 1}/#{jira_comments.length}] Comment by #{author_name}... "

    # Try to find matching comment in database
    # Match by timestamp (most reliable) or by content similarity
    existing_message = nil

    if created_at
      # Try to find by timestamp (within 5 second window)
      existing_message = defect.defect_messages.find do |dm|
        dm.created_at && (dm.created_at - created_at).abs < 5
      end
    end

    # If not found by timestamp, try by content similarity
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
        puts "✅ OK (already in sync)"
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
      # Comment doesn't exist in database - create it
      begin
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

puts "🔍 Finding all defects with Jira keys..."
if PROJECT_KEY.present?
  # Constrain to a single project key like KCBL
  # Using ~ for regex and anchoring at start to the project key
  defects = Defect.where("defect_unique ~ ?", "^#{Regexp.escape(PROJECT_KEY)}-[0-9]+$").where(deleted_on: nil).order(:defect_unique)
else
  defects = Defect.where("defect_unique ~ '^[A-Z]+-[0-9]+$'").where(deleted_on: nil).order(:defect_unique)
end
$STATS[:total_defects] = defects.count

puts "   Found #{$STATS[:total_defects]} defect(s) with Jira keys"
puts ""

if $STATS[:total_defects] == 0
  puts "No defects found to repair. Exiting."
  exit 0
end

puts "=" * 80
puts "🔧 STARTING REPAIR PROCESS"
puts "=" * 80
puts ""

defects.each_with_index do |defect, idx|
  $STATS[:defects_checked] += 1

  puts "[#{idx + 1}/#{$STATS[:total_defects]}] Processing #{defect.defect_unique}"

  # Repair defect description
  repair_defect_content(defect)

  # Repair defect comments
  comment_stats = repair_defect_messages(defect)
  $STATS[:total_comments] += comment_stats[:updated] + comment_stats[:failed]

  puts ""

  # Small delay to avoid overwhelming Jira API
  sleep 0.5
end

# ===============================
# FINAL REPORT
# ===============================

puts "=" * 80
puts "📊 REPAIR COMPLETE - FINAL STATISTICS"
puts "=" * 80
puts ""

puts "Defects:"
puts "  Total defects found:       #{$STATS[:total_defects]}"
puts "  Defects checked:           #{$STATS[:defects_checked]}"
puts "  Descriptions updated:      #{$STATS[:defect_content_updated]}"
puts "  Description update failed: #{$STATS[:defect_content_failed]}"
puts ""

puts "Comments:"
puts "  Total comments checked:    #{$STATS[:comments_checked]}"
puts "  Comments updated/created:  #{$STATS[:comments_updated]}"
puts "  Comments update failed:    #{$STATS[:comments_failed]}"
puts "  Empty comments skipped:    #{$STATS[:comments_empty_skipped]}"
puts ""

success_rate_defects = $STATS[:defects_checked] > 0 ?
  (($STATS[:defect_content_updated].to_f / $STATS[:defects_checked]) * 100).round(2) : 0

success_rate_comments = $STATS[:comments_checked] > 0 ?
  (($STATS[:comments_updated].to_f / $STATS[:comments_checked]) * 100).round(2) : 0

puts "Success Rates:"
puts "  Defect descriptions:       #{success_rate_defects}%"
puts "  Comments:                  #{success_rate_comments}%"
puts ""

if $STATS[:defect_content_failed] > 0 || $STATS[:comments_failed] > 0
  puts "⚠️  Some items failed to update. Check the errors above for details."
else
  puts "✅ All items processed successfully!"
end

puts ""
puts "=" * 80
