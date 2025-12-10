# Configure ActionText and Rails sanitizer to preserve inline styles
# This allows colors, highlights, tables, and other formatting to work properly

Rails.application.config.to_prepare do
  # Patch the Loofah scrubber that ActionText uses
  # This preserves all CSS properties in style attributes
  module ActionText
    module ContentHelper
      # Override sanitizer_allowed_attributes to include style
      mattr_accessor :sanitizer_allowed_attributes
      self.sanitizer_allowed_attributes = Set.new([
        'abbr', 'align', 'alt', 'axis', 'border', 'cellpadding', 'cellspacing', 'class', 'clear', 'cols', 'colspan', 'color',
        'compact', 'coords', 'dir', 'face', 'headers', 'height', 'hreflang', 'hspace', 'ismap', 'lang', 'longdesc',
        'name', 'nowrap', 'rel', 'rev', 'rows', 'rowspan', 'rules', 'scope', 'scrolling', 'shape', 'size', 'span',
        'start', 'summary', 'tabindex', 'target', 'title', 'type', 'usemap', 'valign', 'value', 'vspace', 'width',
        'itemprop', 'href', 'src',
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
