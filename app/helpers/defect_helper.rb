module DefectHelper
  # Clean duplicate bullets/numbers and Word/Docs artifacts from list items
  # This fixes Word/Google Docs paste issues comprehensively
  def clean_list_html(html)
    return '' if html.blank?

    # Step 1: Remove Word/Docs XML comments and conditional tags
    cleaned = html.gsub(/<!--\[if.*?\]>.*?<!\[endif\]-->/m, '')
      .gsub(/<!--.*?-->/m, '')

    # Step 2: Remove Office namespace tags
    cleaned = cleaned.gsub(%r{</?o:p[^>]*>}i, '')
      .gsub(%r{</?w:[^>]*>}i, '')
      .gsub(%r{</?m:[^>]*>}i, '')

    # Step 3: Remove MS Word/Docs CSS classes
    cleaned = cleaned.gsub(/\s*class=["']?Mso[a-zA-Z0-9]*["']?/i, '')
      .gsub(/\s*class=["']?[^"']*\bmso-[^"']*["']?/i, '')

    # Step 4: Remove mso-list spans (critical for duplicate bullets)
    cleaned = cleaned.gsub(%r{<span[^>]*mso-list[^>]*>.*?</span>}im, '')
      .gsub(%r{<span[^>]*style=["'][^"']*mso-list[^"']*["'][^>]*>.*?</span>}im, '')

    # Step 5: Clean inline bullets/numbers from list items
    # Remove various bullet unicode characters
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[•●○◦▪▫■□✓✔➢➣➤►▶⇒→➔➜]\s*/i, '\1')
    # Remove dash/asterisk bullets
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[-*·‣⁃]\s+/i, '\1')
    # Remove numbered lists (1. 2) 3. etc.)
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*\d+[.)]\s*/i, '\1')
    # Remove lettered lists (A. B) a. etc.)
    cleaned = cleaned.gsub(/(<li[^>]*>)\s*[a-zA-Z][.)]\s*/i, '\1')

    # Step 6: Remove font tags and font-family styles
    cleaned = cleaned.gsub(%r{</?font[^>]*>}i, '')
      .gsub(/\s*style=["'][^"']*font-family[^"']*["']/i, '')

    # Step 7: Clean up empty tags
    cleaned = cleaned.gsub(%r{<p[^>]*>\s*</p>}i, '')
      .gsub(%r{<span[^>]*>\s*</span>}i, '')
      .gsub(%r{<div[^>]*>\s*</div>}i, '')

    # Step 8: Remove empty class/style attributes
    cleaned = cleaned.gsub(/\s*class=["']\s*["']/i, '')
      .gsub(/\s*style=["']\s*["']/i, '')

    # Step 9: Normalize whitespace in list items
    cleaned.gsub(/(<li[^>]*>)\s+/i, '\1')
      .gsub(%r{\s+(</li>)}i, '\1')
  end

  # Sanitize rich text content while preserving colors, highlights, and other formatting
  def sanitize_rich_text(content)
    return '' if content.blank?

    # Use Rails' built-in sanitize but with extended allowed attributes
    # This preserves the style attribute which contains colors, backgrounds, etc.
    ActionController::Base.helpers.sanitize(content.to_s,
      tags: %w[
        strong em b i u s strike del ins mark sub sup
        p br span div
        h1 h2 h3 h4 h5 h6
        blockquote pre code
        ul ol li
        a
        table thead tbody tfoot tr th td caption colgroup col
        figure figcaption
        hr
      ],
      attributes: %w[
        href style class title id
        colspan rowspan scope align valign
        cellpadding cellspacing border
        width height bgcolor
      ]
    ).html_safe
  end

  def priority_badge_class(priority)
    case priority.to_s.downcase
    when 'severity 1', 'high' then 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300'
    when 'severity 2', 'medium' then 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300'
    when 'severity 3', 'low' then 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300'
    else 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
    end
  end

  # Sanitize HTML for safe rendering in history display
  # Preserves formatting like lists, tables, bold, italic, etc.
  def strip_html_for_history(content)
    return content if content.blank?

    # Check if content contains HTML tags
    if content.include?('<')
      # Sanitize HTML to allow safe formatting tags
      sanitize_rich_text(content)
    else
      content
    end
  end

  def parse_history_item(content)
    # Default fallback
    result = { action: 'updated', field: nil, from: nil, to: nil }

    return result if content.blank?

    # Pattern 1: "State changed from X to Y" (Standard)
    # Regex handles "Status changed from Open to Done" or "Priority changed from High to Low"
    if match = content.match(/^(.+?)\s+(?:changed|updated)\s+from\s+(.+?)\s+to\s+(.+?)(?:\s+(?:by|at)|$)/i)
      result[:field] = match[1].strip
      result[:action] = "changed the #{result[:field]}"
      result[:from] = strip_html_for_history(match[2].strip)
      result[:to] = strip_html_for_history(match[3].strip)

    # Pattern 2: "X -> Y" (Arrow format)
    elsif content.include?('→')
      parts = content.split('→').map(&:strip)
      if parts.length == 2
        result[:field] = 'Description' # Likely description if using arrow format
        result[:action] = 'updated the Description'
        result[:from] = strip_html_for_history(parts[0])
        result[:to] = strip_html_for_history(parts[1])
      end

    # Pattern 3: "Added attachment: X"
    elsif match = content.match(/^Added attachment:\s*(.+)$/i)
      result[:action] = 'attached'
      result[:field] = 'Attachment'
      result[:to] = match[1].strip

    # Pattern 4: "Created the Work item"
    elsif content.match?(/created/i)
      result[:action] = 'created'
      result[:field] = 'Defect'

    else
      # Fallback for plain text updates
      result[:action] = 'updated'
      result[:field] = 'Info'
      result[:to] = strip_html_for_history(content)
    end

    result
  end

  def history_badge_class(value, type = :neutral)
    base = "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium "
    case type
    when :old
      base + "bg-red-50 text-red-700 dark:bg-red-900/30 dark:text-red-400 line-through"
    when :new
      base + "bg-green-50 text-green-700 dark:bg-green-900/30 dark:text-green-400"
    else
      base + "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
    end
  end

  def render_user_avatar(user, size_class = "w-8 h-8")
    return nil unless user
    initials = user.name.split.map(&:first).join.upcase[0..1]
    color_class = "bg-blue-600 dark:bg-blue-500" # Could be randomized based on ID

    content_tag(:div, class: "#{size_class} rounded-full #{color_class} flex items-center justify-center text-white font-medium text-xs ring-2 ring-white dark:ring-gray-800") do
      initials
    end
  end

  # Keep old method for backward compatibility if needed, but alias or deprecate
  def format_history_with_highlights(defect_history)
    # Placeholder to prevent breaking old views if partially deployed
    defect_history.history
  end
end
