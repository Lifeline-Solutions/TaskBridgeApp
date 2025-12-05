module DefectHelper
  # Clean duplicate bullets/numbers and Word/Docs artifacts from list items
  # This fixes Word/Google Docs paste issues comprehensively
  def clean_list_html(html)
    return '' if html.blank?

    # Step 1: Remove Word/Docs XML comments and conditional tags
    cleaned = html.gsub(/<!--\[if.*?\]>.*?<!\[endif\]-->/m, '')
                  .gsub(/<!--.*?-->/m, '')

    # Step 2: Remove Office namespace tags
    cleaned = cleaned.gsub(/<\/?o:p[^>]*>/i, '')
                    .gsub(/<\/?w:[^>]*>/i, '')
                    .gsub(/<\/?m:[^>]*>/i, '')

    # Step 3: Remove MS Word/Docs CSS classes
    cleaned = cleaned.gsub(/\s*class=["']?Mso[a-zA-Z0-9]*["']?/i, '')
                    .gsub(/\s*class=["']?[^"']*\bmso-[^"']*["']?/i, '')

    # Step 4: Remove mso-list spans (critical for duplicate bullets)
    cleaned = cleaned.gsub(/<span[^>]*mso-list[^>]*>.*?<\/span>/im, '')
                    .gsub(/<span[^>]*style=["'][^"']*mso-list[^"']*["'][^>]*>.*?<\/span>/im, '')

    # Step 5: Clean inline bullets/numbers from list items
    # Remove various bullet unicode characters
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[•●○◦▪▫■□✓✔➢➣➤►▶⇒→➔➜]\s*/i, '\1')
    # Remove dash/asterisk bullets
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[\-\*·‣⁃]\s+/i, '\1')
    # Remove numbered lists (1. 2) 3. etc.)
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*\d+[\.\)]\s*/i, '\1')
    # Remove lettered lists (A. B) a. etc.)
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[a-zA-Z][\.\)]\s*/i, '\1')

    # Step 6: Remove font tags and font-family styles
    cleaned = cleaned.gsub(/<\/?font[^>]*>/i, '')
                    .gsub(/\s*style=["'][^"']*font-family[^"']*["']/i, '')

    # Step 7: Clean up empty tags
    cleaned = cleaned.gsub(/<p[^>]*>\s*<\/p>/i, '')
                    .gsub(/<span[^>]*>\s*<\/span>/i, '')
                    .gsub(/<div[^>]*>\s*<\/div>/i, '')

    # Step 8: Remove empty class/style attributes
    cleaned = cleaned.gsub(/\s*class=["']\s*["']/i, '')
                    .gsub(/\s*style=["']\s*["']/i, '')

    # Step 9: Normalize whitespace in list items
    cleaned = cleaned.gsub(/(<li[^>]*>)\s+/i, '\1')
                    .gsub(/\s+(<\/li>)/i, '\1')

    cleaned
  end
  def priority_badge_class(priority)
    case priority.to_s.downcase
    when 'severity 1', 'high' then 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300'
    when 'severity 2', 'medium' then 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300'
    when 'severity 3', 'low' then 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300'
    else 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
    end
  end

  def format_history_with_highlights(defect_history)
    return defect_history.history unless defect_history.history.present?

    history_text = defect_history.history

    # Match pattern: "Something changed from A to B by C"
    match = history_text.match(/(.+?)\s+from\s+(.+?)\s+to\s+(.+?)\s+by\s+(.+)$/i)

    return history_text unless match

    action = match[1]
    old_value = match[2].strip
    new_value = match[3].strip
    actor = match[4].strip

    # Check if values are user names (for assignee changes)
    is_assignee_change = action.downcase.include?('assignee')

    content_tag(:div, class: 'flex items-center gap-2 flex-wrap') do
      output = []

      # Old value
      output << if is_assignee_change && old_value.downcase != 'none'
                  render_user_badge(old_value, 'line-through text-red-600')
                else
                  content_tag(:span, old_value, class: 'px-2 py-0.5 bg-red-50 text-red-700 rounded line-through font-medium')
                end

      # Arrow
      output << content_tag(:span, '→', class: 'text-gray-400 font-bold')

      # New value
      output << if is_assignee_change && new_value.downcase != 'none'
                  render_user_badge(new_value, 'text-green-700 font-medium')
                else
                  content_tag(:span, new_value, class: 'px-2 py-0.5 bg-green-50 text-green-700 rounded font-medium')
                end

      # Actor (by C)
      output << content_tag(:span, 'by', class: 'text-gray-400 text-xs')
      output << render_user_badge(actor, 'text-blue-700 font-medium')

      safe_join(output)
    end
  end

  def render_user_badge(name, additional_classes = '')
    initials = name.split.map(&:first).join.upcase[0..1]

    avatar = content_tag(:span, initials, class: 'inline-flex items-center justify-center w-5 h-5 bg-blue-600 text-white text-xs rounded-full')
    name_span = content_tag(:span, name, class: 'text-sm')

    content_tag(:span, class: "inline-flex items-center gap-1 #{additional_classes}") do
      avatar + name_span
    end
  end
end
