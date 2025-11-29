# Rich Text Implementation for Jira Description Import

## Overview
Updated the Jira import script (`scripts/import_jira_with_modules.rb`) to properly handle Jira descriptions as **rich text (HTML)** instead of plain text. This ensures that Jira formatting like tables, lists, headings, code blocks, and other rich content are preserved when imported into the CSPM system.

## Key Changes

### 1. **New ADF-to-HTML Conversion Pipeline**
Added comprehensive methods to convert Jira's Atlassian Document Format (ADF) to proper HTML:

- **`extract_description(field)`** - Main entry point that detects ADF vs plain text and converts to HTML
- **`convert_adf_to_html(content_array)`** - Converts ADF content blocks to HTML
- **`convert_adf_block_to_html(block)`** - Handles individual block types (paragraphs, headings, tables, code, etc.)
- **`convert_adf_inline_to_html(content_array)`** - Handles inline formatting (bold, italic, links, mentions, etc.)
- **`convert_adf_list_to_html(items, tag)`** - Converts bullet and ordered lists to HTML `<ul>` and `<ol>`
- **`convert_adf_table_to_html(table_block)`** - Converts Jira tables to proper HTML `<table>` elements

### 2. **Supported Rich Content**
The HTML conversion now properly handles:

- **Headings** (`h1` through `h6`)
- **Paragraphs** with proper `<p>` tags
- **Text Formatting**:
  - Bold (`<strong>`)
  - Italic (`<em>`)
  - Code/Monospace (`<code>`)
  - Underline (`<u>`)
  - Strikethrough (`<s>`)
  - Links (`<a href>`)
  - Mentions (`<span class="mention">`)
- **Lists**:
  - Unordered lists (`<ul>/<li>`)
  - Ordered lists (`<ol>/<li>`)
- **Tables** with proper HTML `<table>`, `<tr>`, `<th>`, `<td>` structure
- **Code Blocks** with language specification
- **Block Quotes** (`<blockquote>`)
- **Horizontal Rules** (`<hr>`)
- **Images** with alt text
- **Emojis** and special characters

### 3. **ActionText Integration**
The Defect model uses Rails ActionText's `has_rich_text :content`:

```ruby
has_rich_text :content
```

When an HTML string is assigned to `defect.content`, Rails automatically:
1. Creates an `ActionText::RichText` record
2. Stores the HTML content in the database
3. Allows proper rendering in views with `simple_format` or ActionText helpers

### 4. **Content Assignment**
Updated defect creation/update to properly assign rich HTML:

```ruby
if description.present?
  # ActionText will automatically create/update the rich text record
  # when we assign HTML string to the rich_text attribute
  defect.content = description
end
```

## Benefits

✅ **Preserves Formatting** - Tables, lists, and text formatting now display correctly  
✅ **Better Readability** - Rich content is more readable than plain text or markdown  
✅ **Rails Integration** - Uses native ActionText which integrates with Rails views  
✅ **Security** - HTML is properly escaped to prevent XSS attacks  
✅ **Backward Compatible** - Plain text descriptions still work (converted to `<p>` tags)  
✅ **Standards Compliant** - Generates valid semantic HTML  

## Implementation Details

### CGI HTML Escaping
All user-input content (text, URLs, alt text, etc.) is properly escaped using `CGI.escapeHTML()` to prevent XSS vulnerabilities:

```ruby
CGI.escapeHTML(content)  # Converts < > & " ' to HTML entities
```

### ADF Format Handling
Jira's Atlassian Document Format (ADF) is a hierarchical JSON structure. Example:

```json
{
  "type": "paragraph",
  "content": [
    {
      "type": "text",
      "text": "Hello ",
      "marks": [{"type": "bold"}]
    }
  ]
}
```

This is converted to: `<p><strong>Hello</strong></p>`

### Table Conversion
Jira tables in ADF are converted to semantic HTML:

**ADF Input:**
```json
{
  "type": "table",
  "content": [
    {
      "type": "tablerow",
      "content": [
        {"type": "tableheader", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Name"}]}]},
        {"type": "tablecell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Value"}]}]}
      ]
    }
  ]
}
```

**HTML Output:**
```html
<table>
  <tr>
    <th>Name</th>
    <td>Value</td>
  </tr>
</table>
```

## Testing

To verify rich text is being imported correctly:

### 1. In Rails Console
```ruby
# Check that content is stored as rich text
defect = Defect.find_by(defect_unique: "JIRA-123")
defect.content.body.to_html  # Returns the HTML string
```

### 2. In Views
```erb
<!-- Simple approach - renders with p tags -->
<%= simple_format(@defect.content) %>

<!-- ActionText approach - renders as-is -->
<%= @defect.content %>

<!-- Custom styling -->
<div class="defect-content">
  <%= sanitize(@defect.content, tags: %w[p h1 h2 h3 ul ol li table thead tbody tr td th code pre blockquote a em strong u s], attributes: %w[href class]) %>
</div>
```

## Migration for Existing Content

If there are defects with plain text content that need to be converted to rich HTML:

```ruby
# In Rails console
Defect.find_each do |defect|
  next if defect.content.blank?
  
  current_content = defect.content.to_plain_text
  if current_content.present?
    # Wrap in paragraph tags
    html_content = "<p>#{CGI.escapeHTML(current_content)}</p>"
    defect.content = html_content
    defect.save!
  end
end
```

## Future Enhancements

- [ ] Add support for Jira Macros (code snippets, embedded content)
- [ ] Add support for attachments within descriptions
- [ ] Add support for Jira Status badges and mentions
- [ ] Implement content validation before import
- [ ] Add description integrity checks post-import

## References

- [Jira Atlassian Document Format (ADF)](https://developer.atlassian.com/cloud/jira/platform/apis/document/adf/)
- [Rails ActionText](https://guides.rubyonrails.org/action_text_overview.html)
- [HTML Semantics](https://html.spec.whatwg.org/)
- [XSS Prevention with CGI.escapeHTML](https://ruby-doc.org/stdlib-2.5.0/libdoc/cgi/rdoc/CGI.html#method-c-escapeHTML)

