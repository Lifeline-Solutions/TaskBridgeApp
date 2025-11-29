# Rich Text Content Repair Guide

## Overview

This guide explains how to validate and repair rich text content for defects and comments imported from Jira to ensure they have proper formatting including:

- ✅ Ordered and unordered lists
- ✅ Tables with proper structure
- ✅ Text and background colors
- ✅ Bold, italic, underline, strikethrough
- ✅ Images
- ✅ Code blocks
- ✅ Links
- ✅ Headings
- ✅ Blockquotes
- ✅ All HTML formatting

## Scripts Available

### 1. Main Import Script (Enhanced)
**File:** `scripts/import_jira_with_modules.rb`

This is the main import script that now includes enhanced rich text conversion with:
- Full ADF (Atlassian Document Format) to HTML conversion
- Support for text and background colors
- Support for subscript and superscript
- Comprehensive list and table formatting
- Image embedding

**Usage:**
```bash
# Import from single project
rails runner scripts/import_jira_with_modules.rb --project KCBL

# Import from multiple projects
rails runner scripts/import_jira_with_modules.rb --project KCBL,PSP,FLOW

# Dry run (test without saving)
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run

# Verbose mode (detailed logging)
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose
```

### 2. Rich Text Repair Script (New)
**File:** `scripts/repair_rich_text_content.rb`

This script validates and repairs existing defect content and comments by:
- Re-fetching data from Jira
- Comparing current content with Jira content
- Updating only mismatched content
- Converting all content to proper rich text HTML format
- Creating missing comments

**Usage:**
```bash
# Run repair for all defects
rails runner scripts/repair_rich_text_content.rb
```

**What it does:**
1. Finds all defects with Jira keys (format: `ABC-1234`)
2. For each defect:
   - Fetches fresh data from Jira API
   - Compares description with current database content
   - Updates if content differs
   - Fetches all comments from Jira
   - Compares each comment with database
   - Updates mismatched comments
   - Creates missing comments

**Output Example:**
```
🔧 JIRA RICH TEXT CONTENT REPAIR SCRIPT
================================================================================

🔍 Finding all defects with Jira keys...
   Found 845 defect(s) with Jira keys

================================================================================
🔧 STARTING REPAIR PROCESS
================================================================================

[1/845] Processing KCBL-1
  📄 Checking KCBL-1 description... ✅ UPDATED (2456 chars)
  💬 Checking KCBL-1 comments...
    Found 4 comment(s) in Jira
    [1/4] Comment by John Doe... ✅ UPDATED (512 chars)
    [2/4] Comment by Jane Smith... ✅ OK (already in sync)
    [3/4] Comment by Bob Wilson... ✅ UPDATED (1024 chars)
    [4/4] Comment by Alice Brown... ✅ OK (already in sync)

[2/845] Processing KCBL-2
  📄 Checking KCBL-2 description... ✅ OK (already in sync)
  💬 Checking KCBL-2 comments... ⏭️  SKIP (no comments in Jira)

...

================================================================================
📊 REPAIR COMPLETE - FINAL STATISTICS
================================================================================

Defects:
  Total defects found:       845
  Defects checked:           845
  Descriptions updated:      127
  Description update failed: 0

Comments:
  Total comments checked:    2856
  Comments updated/created:  234
  Comments update failed:    0
  Empty comments skipped:    12

Success Rates:
  Defect descriptions:       15.03%
  Comments:                  8.19%

✅ All items processed successfully!
```

## How Rich Text is Stored

Both `Defect` and `DefectMessage` models use Rails ActionText:

```ruby
# app/models/defect.rb
class Defect < ApplicationRecord
  has_rich_text :content  # Stores description as rich HTML
  # ...
end

# app/models/defect_message.rb
class DefectMessage < ApplicationRecord
  has_rich_text :content  # Stores comment as rich HTML
  # ...
end
```

When you assign HTML to the `content` attribute, Rails automatically:
1. Creates a record in `action_text_rich_texts` table
2. Parses and sanitizes the HTML
3. Stores attachments separately in ActiveStorage
4. Provides `.to_s` to render HTML and `.to_plain_text` for plain text

## Rich Text Features Supported

### 1. Lists
**Ordered Lists:**
```html
<ol>
  <li>First item</li>
  <li>Second item</li>
</ol>
```

**Unordered Lists:**
```html
<ul>
  <li>Bullet point 1</li>
  <li>Bullet point 2</li>
</ul>
```

### 2. Tables
```html
<table>
  <tr>
    <th>Header 1</th>
    <th>Header 2</th>
  </tr>
  <tr>
    <td>Cell 1</td>
    <td>Cell 2</td>
  </tr>
</table>
```

### 3. Colors
**Text Color:**
```html
<span style="color: #ff0000">Red text</span>
```

**Background Color:**
```html
<span style="background-color: #ffff00">Highlighted text</span>
```

### 4. Text Formatting
```html
<strong>Bold</strong>
<em>Italic</em>
<u>Underline</u>
<s>Strikethrough</s>
<code>Inline code</code>
```

### 5. Images
```html
<img src="https://example.com/image.png" alt="Description">
```

### 6. Code Blocks
```html
<pre><code class="language-ruby">
def hello
  puts "Hello World"
end
</code></pre>
```

## Troubleshooting

### Problem: Comments showing as plain text
**Solution:** Run the repair script to convert them to rich HTML:
```bash
rails runner scripts/repair_rich_text_content.rb
```

### Problem: Tables or lists not rendering correctly
**Solution:**
1. Check if the content is stored as HTML in the database
2. Run the repair script to re-fetch and convert from Jira
3. Verify the view template is using `<%= defect.content %>` (not `.to_plain_text`)

### Problem: Colors not displaying
**Solution:**
1. Ensure CSS styles are not being stripped
2. Check ActionText sanitizer configuration
3. The repair script includes color support in the conversion

### Problem: Some defects not updating
**Solution:**
1. Check Jira API credentials in `config/jira_import.yml`
2. Verify the defect exists in Jira with the correct key format
3. Check for API rate limiting (the script includes delays)

## Verification

After running the repair script, verify the results:

```ruby
# In Rails console
defect = Defect.find_by(defect_unique: 'KCBL-1')

# Check if content is rich text
defect.content.class  # Should be ActionText::RichText

# View HTML
puts defect.content.to_s

# View plain text
puts defect.content.to_plain_text

# Check comments
defect.defect_messages.each do |msg|
  puts "Comment by #{msg.user.first_name}: #{msg.content.to_s[0..100]}..."
end
```

## Performance Notes

- The repair script processes one defect at a time to avoid API rate limits
- Includes 0.5 second delay between defects
- Fetches only defects with Jira keys (format: `XXX-123`)
- Skips defects already in sync (no unnecessary updates)
- Can be safely re-run multiple times (idempotent)

## Maintenance

**Regular Checks:**
1. Run repair script weekly to catch any missed updates
2. Monitor failed updates in the output
3. Check for empty comments being created

**After Jira Changes:**
- If Jira content is edited, run the repair script to sync changes
- The script detects differences and updates only what changed

## Support

If you encounter issues:
1. Check the script output for error messages
2. Verify Jira API connectivity
3. Ensure database permissions for updates
4. Check Rails logs: `log/development.log` or `log/production.log`
