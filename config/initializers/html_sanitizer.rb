# Configure Rails HTML sanitizer to allow inline styles for rich text content
# This enables colors, highlights, and other formatting to be preserved

Rails.application.config.after_initialize do
  # Patch the SafeListSanitizer to allow all CSS in style attributes
  module AllowInlineStyles
    def scrub_css(css)
      # Return the CSS unchanged instead of filtering it
      # This allows colors, backgrounds, and other inline styles
      css
    end

    def scrub_attribute(attr_name)
      # Don't scrub the style attribute
      return if attr_name == 'style'
      super
    end
  end

  Rails::Html::SafeListSanitizer.prepend(AllowInlineStyles)
end
