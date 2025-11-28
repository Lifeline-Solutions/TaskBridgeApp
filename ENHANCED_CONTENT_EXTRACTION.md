# Enhanced Jira Content Extraction - Documentation

## Overview

The script has been updated to extract **complete descriptions and comments** from Jira issues, including all content types:

- ✅ **Tables** - Converted to readable pipe-separated format
- ✅ **Bullet Lists** - Preserved with bullet point markers (•)
- ✅ **Ordered Lists** - Preserved with numbers (1. 2. 3.)
- ✅ **Code Blocks** - Preserved with language markers (```ruby, etc.)
- ✅ **Headings** - Preserved with markdown notation (#, ##, etc.)
- ✅ **Blockquotes** - Preserved with quote markers (>)
- ✅ **Regular Paragraphs** - Plain text preserved
- ✅ **Images** - Referenced with [Image: alt_text]
- ✅ **Links** - Referenced with [Link: URL]
- ✅ **Mentions** - User mentions preserved with @username

## What Was Changed

### Before (Limited Extraction)
```ruby
def extract_description(field)
  if field.is_a?(Hash)
    text_parts = []
    (field['content'] || []).each do |block|
      (block['content'] || []).each do |sub|
        text_parts << sub['text'] if sub['type'] == 'text' && sub['text']
      end
    end
    return text_parts.join(' ')  # Only extracted text, lost formatting
  end
  field.to_s
end
```

**Problems:**
- Only captured `text` nodes
- Ignored tables, lists, code blocks
- Lost all formatting and structure
- Produced incomplete descriptions

### After (Complete Content Extraction)
```ruby
def extract_description(field)
  if field.is_a?(Hash)
    text_parts = []
    process_adf_content(field['content'] || [], text_parts)
    return text_parts.join("\n").strip  # Preserves structure
  end
  field.to_s
end
```

**Improvements:**
- Processes all ADF (Atlassian Document Format) block types
- Handles nested content recursively
- Preserves formatting with markdown
- Returns complete, well-structured content

## Functions Added

### 1. `process_adf_content(content_array, text_parts = [])`
Main recursive processor for ADF blocks. Handles:
- Paragraphs
- Headings (with level markers)
- Bullet/Ordered lists
- Tables (with row/column structure)
- Code blocks (with language specification)
- Blockquotes
- HR/separators
- Images, mentions, links

### 2. `extract_adf_text_from_block(content_array = [])`
Extracts inline text content from ADF nodes. Handles:
- Text nodes
- Mention nodes
- Hard breaks
- Nested content recursion

### 3. `extract_table_as_text(table_block)`
Converts Jira table ADF to readable text format:
```
[Table]
Header1 | Header2 | Header3
Row1Col1 | Row1Col2 | Row1Col3
Row2Col1 | Row2Col2 | Row2Col3
[/Table]
```

## Example Output

### Input (Jira ADF)
```json
{
  "type": "bulletList",
  "content": [
    {"type": "listItem", "content": [...]}
  ]
}
```

### Output (Extracted Text)
```
• First item
• Second item
• Third item
```

## Impact on Data Import

### Issue Descriptions
- **Before**: "This is a test" (only plain text extracted)
- **After**: 
  ```
  # Bug Description
  This is a test bug with various content types.
  • First issue found
  • Second issue found
  1. Step one to reproduce
  2. Step two to reproduce
  ```ruby
  def test_method
    puts 'This is code'
  end
  ```
  > This is an important note from the user
  [Table]
  Environment | Status
  Production | Broken
  [/Table]
  ```

### Comments
- Same enhancement applied to all comment extraction
- Preserves complete context with all formatting

## Testing

A test script is included: `scripts/test_adf_extraction.rb`

Run it to verify extraction works:
```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM
ruby scripts/test_adf_extraction.rb
```

Expected output:
```
========================================
Testing Enhanced ADF Extraction
========================================

EXTRACTED CONTENT:
────────────────────────────────────────
# Bug Description
This is a test bug with various content types.
• First issue found
• Second issue found
...
────────────────────────────────────────

✅ Extraction successful!

Content Validation:
────────────────────────────────────────
✅ PASS: Heading present
✅ PASS: Bullet list present
✅ PASS: Ordered list present
✅ PASS: Code block present
✅ PASS: Blockquote present
✅ PASS: Table present
────────────────────────────────────────

🎉 All content extraction tests passed!
```

## Implementation Details

### ADF Support
The script now fully supports Jira's Atlassian Document Format (ADF), which uses:
- `content` arrays for nested structure
- `type` field to identify element type
- `attrs` for element attributes (heading level, language, etc.)
- Recursive block nesting for complex structures

### Backward Compatibility
- Still handles simple string descriptions
- Falls back gracefully for unexpected content types
- No breaking changes to existing functionality

## Database Impact

### Description Field
Descriptions now contain:
- Complete, formatted content from Jira
- Structured text that preserves intent
- No data loss from tables or lists
- Better readability in plaintext form

### Comment Fields
Comments with tables/lists/code:
- Fully captured and preserved
- Can be rendered with markdown formatting
- Searchable across all content types

## Usage in Import

When running the import script:

```bash
# Dry-run mode (test extraction without saving)
rails runner scripts/import_jira_with_modules.rb \
  --project KCBL,PSP,FLOW \
  --dry-run \
  --verbose

# Actual import (extracts and saves complete content)
rails runner scripts/import_jira_with_modules.rb \
  --project KCBL,PSP,FLOW
```

All descriptions and comments will now include:
- ✅ Tables
- ✅ Lists (bullet and ordered)
- ✅ Code blocks
- ✅ Headings
- ✅ Blockquotes
- ✅ All other structured content

## Benefits

1. **Completeness**: No more lost content from complex formatting
2. **Searchability**: All text content is searchable
3. **Readability**: Markdown-like formatting aids human readers
4. **Data Integrity**: Full fidelity transfer from Jira to CSPM
5. **Maintenance**: Easier to understand ticket details later

## Troubleshooting

If extraction seems incomplete:

1. **Check Jira ADF format**: The enhancement supports standard ADF
2. **Review extracted content**: Run test script to validate
3. **Check for edge cases**: Some custom Jira plugins may use non-standard ADF
4. **Enable verbose logging**: 
   ```bash
   rails runner scripts/import_jira_with_modules.rb --project X --verbose
   ```

## Notes

- Line breaks within content are preserved as `\n`
- Long content is not truncated (save to database field width)
- Tables are text-based, not actual table objects
- Image/link references are preserved but not downloaded

