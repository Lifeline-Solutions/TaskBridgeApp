# Configure ActionText and Rails sanitizer to preserve inline styles and tables
# This allows colors, highlights, tables, and other formatting to work properly

Rails.application.config.to_prepare do
  # Patch ActionText to allow table tags and style attributes
  module ActionText
    module ContentHelper
      # Override allowed tags to include table elements
      mattr_accessor :sanitizer_allowed_tags
      self.sanitizer_allowed_tags = Set.new([
        'action-text-attachment', 'a', 'aside', 'b', 'blockquote', 'br', 'caption', 'cite', 'code', 'del', 'details',
        'div', 'dl', 'dt', 'dd', 'em', 'figcaption', 'figure', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'i', 'img',
        'li', 'mark', 'ol', 'p', 'pre', 'q', 's', 'samp', 'small', 'source', 'span', 'strike', 'strong', 'sub',
        'summary', 'sup', 'time', 'u', 'ul', 'var', 'video',
        # CRITICAL: Add table tags
        'table', 'thead', 'tbody', 'tfoot', 'tr', 'th', 'td', 'colgroup', 'col'
      ])

      # Override allowed attributes to include style and table attributes
      mattr_accessor :sanitizer_allowed_attributes
      self.sanitizer_allowed_attributes = Set.new([
        'abbr', 'align', 'alt', 'axis', 'border', 'cellpadding', 'cellspacing', 'class', 'clear', 'cols', 'colspan', 'color',
        'compact', 'coords', 'dir', 'face', 'headers', 'height', 'hreflang', 'hspace', 'ismap', 'lang', 'longdesc',
        'name', 'nowrap', 'rel', 'rev', 'rows', 'rowspan', 'rules', 'scope', 'scrolling', 'shape', 'size', 'span',
        'start', 'summary', 'tabindex', 'target', 'title', 'type', 'usemap', 'valign', 'value', 'vspace', 'width',
        'itemprop', 'href', 'src', 'bgcolor',
        'style' # CRITICAL: Allow style attribute for colors and formatting
      ])
    end
  end

  # Patch Rails sanitizer to not strip CSS properties
  Rails::Html::SafeListSanitizer.class_eval do
    def scrub_css(css)
      # Don't strip any CSS - return as-is
      css
    end
  end
end
