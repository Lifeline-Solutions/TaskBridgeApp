# Description Validation and Update Implementation

## Overview
Enhanced the JIRA import script to comprehensively handle description content extraction and validation, ensuring all content from JIRA descriptions (including tables, bullets, and formatted text) is properly imported and updated in the database.

## Key Features Implemented

### 1. Enhanced Content Extraction Functions

#### `process_adf_content(content_array, text_parts = [])`
- Processes Jira ADF (Atlassian Document Format) recursively
- Handles multiple content types:
  - **Paragraphs**: Plain text content
  - **Headings**: Converted to markdown format with appropriate level (#, ##, etc.)
  - **Lists**: 
    - Bullet lists: Converted to `• item` format
    - Ordered lists: Converted to `1. item` format
  - **Tables**: Extracted to readable text with `[Table]...[/Table]` markers
  - **Code blocks**: Preserved with language specification
  - **Block quotes**: Converted to `> quote` format
  - **Images**: Captured with alt text
  - **Mentions**: Preserved with @user format
  - **Links**: Captured as `[Link: url]`

#### `extract_adf_text_from_block(content_array = [])`
- Extracts plain text from inline ADF content
- Handles:
  - Text nodes
  - Mentions
  - Hard breaks (line breaks)
  - Nested content

#### `extract_table_as_text(table_block)`
- Converts Jira tables to readable pipe-delimited format
- Shows table structure clearly: `[Table] ... [/Table]`
- Supports complex table cells with multiple paragraphs

### 2. Description Validation and Update

#### `validate_and_update_description(defect, jira_description_field, issue_key, verbose: false)`
- **Primary Function**: Validates if a defect's description matches current JIRA data
- **Behavior**:
  - Extracts description using enhanced extraction functions
  - Normalizes whitespace for comparison (ignores formatting differences)
  - Compares case-insensitively
  - Updates ONLY if content differs
  - Logs changes in verbose mode
  - Returns `true` if updated, `false` if no changes needed
- **Features**:
  - Prevents unnecessary database writes
  - Tracks what was changed
  - Handles errors gracefully

#### `repair_descriptions_for_defects(issues, verbose: false)`
- **Purpose**: Post-import validation and repair pass
- **Behavior**:
  - Iterates through all imported issues
  - Calls `validate_and_update_description` for each
  - Tracks statistics (total, updated, skipped, errors)
  - Reports summary and individual changes
- **Returns**: Statistics hash with counts

### 3. Integration into Import Flow

The description repair pass is integrated into the main import workflow:
```
1. Fetch issues from JIRA
2. Import issues into database
3. Repair pass:
   - Repair missing defects
   - Repair missing comments
   - Repair missing attachments (issue-level)
   - Repair missing labels
   - Repair missing history entries
   → Validate and update descriptions  ← NEW STEP
4. Generate verification reports
```

## Content Types Handled

### Tables
**Before (in JIRA ADF)**:
```json
{
  "type": "table",
  "content": [
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "content": [
            {
              "type": "paragraph",
              "content": [{"type": "text", "text": "Header 1"}]
            }
          ]
        }
      ]
    }
  ]
}
```

**After (in database)**:
```
[Table]
Header 1 | Header 2
Cell 1 | Cell 2
[/Table]
```

### Bullet Lists
**Before**:
```json
{
  "type": "bulletList",
  "content": [
    {
      "type": "listItem",
      "content": [{"type": "paragraph", "content": [...]}]
    }
  ]
}
```

**After**:
```
• Item 1
• Item 2
• Item 3
```

### Ordered Lists
**After**:
```
1. First item
2. Second item
3. Third item
```

### Code Blocks
**After**:
````
```python
def hello():
    print("world")
```
````

### Block Quotes
**After**:
```
> This is a quote
> It can span multiple lines
```

### Headings
**Before (in JIRA ADF)**:
```json
{
  "type": "heading",
  "attrs": {"level": 2},
  "content": [{"type": "text", "text": "My Heading"}]
}
```

**After**:
```
## My Heading
```

## Usage

### Running the Import with Description Validation

```bash
# Standard import
rails runner scripts/import_jira_with_modules.rb --project KCBL

# Multiple projects
rails runner scripts/import_jira_with_modules.rb --project PSP,KCBL,FLOW

# With verbose output to see all description updates
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose

# Dry run (shows what would happen)
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run
```

### Description Validation Output

During the repair pass, you'll see:

```
🔧 Running repair pass for missing items...
  Validating and updating descriptions...
    - Checked: 1120
    - Updated: 47
    - Skipped (no changes): 1073
    - Errors: 0
```

For each updated issue, a log message appears:

```
[DESCRIPTION-REPAIRED] KCBL-123: Description updated from Jira
```

With `--verbose` flag, you also see:

```
[DESCRIPTION-VALIDATE] KCBL-123: new_len=2847, existing_len=2100
[DESCRIPTION-UPDATE] KCBL-123: Updated description (2847 chars)
  Previous: This is the old description...
  Updated: This is the new description with tables...
```

## Comparison Strategy

The script uses smart comparison logic:
1. **Exact match first**: If descriptions are identical, skip
2. **Normalized comparison**: Ignores extra whitespace and case differences
3. **Update on difference**: If content differs after normalization, update

## Error Handling

- **Defect not found**: Skips issue with notification
- **Save failure**: Logs error with details and continues
- **Description extraction failure**: Logs warning, skips description update

## Verification

All descriptions are validated during the repair pass and detailed verification reports are generated:

```
📋 DETAILED IMPORT VERIFICATION REPORT
========================================
KCBL-123         -> OK    (comments: 5/5, issue_atts: 3/3, comment_atts: 2/2, labels: 1/1, history: 8/8)
```

The "OK" status confirms that descriptions and all other fields match expected values.

## Performance Considerations

- **Efficient comparison**: Normalizes once before comparing
- **Selective updates**: Only updates if changes detected
- **No unnecessary writes**: Prevents database churn
- **Batch processing**: All issues checked in single pass
- **Minimal I/O**: Single read/write per defect update

## Logging and Debugging

Enable verbose logging to see:
- Description validation for each issue
- Character count changes
- Previous vs. updated content previews
- Parse strategy used for each field type
- All data extraction operations

```bash
--verbose  # Shows all of the above
```

## Summary

This implementation ensures that:
1. ✅ All description content from JIRA is properly extracted (including tables, bullets, etc.)
2. ✅ Descriptions are validated and updated only when necessary
3. ✅ The process is integrated into the existing import/repair workflow
4. ✅ Clear logging and reporting of what changed
5. ✅ No data loss or corruption
6. ✅ Efficient processing with selective updates
7. ✅ Comprehensive error handling and recovery

The script now provides complete description management for JIRA imports with full content fidelity.

