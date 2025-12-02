# Quick Reference: Description Validation in Jira Import

## What's New
The import script now properly handles description content extraction and validation:
- ✅ Tables (with proper formatting)
- ✅ Bullet lists
- ✅ Ordered lists
- ✅ Code blocks
- ✅ Block quotes
- ✅ Headings (all levels)
- ✅ Images and links
- ✅ Smart update: Only updates if content changed

## Running the Import

### Basic Import (single project)
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL
```

### Import Multiple Projects
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL,PSP,FLOW
```

### With Verbose Output (see all details)
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose
```

### Dry Run (test without saving)
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run
```

### Set Date Range (how many days back to fetch)
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --days 365
```

## What Happens During Import

1. **Fetch Issues**: Get all issues from Jira
2. **Import**: Create/update defects in database
3. **Repair Pass**: Fix any missing items
   - **Description Validation**: ← NEW STEP
     - Checks each defect's description against Jira
     - Updates only if content differs
     - Reports: Checked, Updated, Skipped, Errors
4. **Verification**: Generate detailed reports

## Output Example

```
Starting direct Jira import with modules for project(s): KCBL (dry_run: false)

[Fetching issues...]
✓ Page 1: Fetched 100 issues...
✓ Page 2: Fetched 85 issues...
📊 Total issues fetched from Jira: 185 (across 2 pages)

[Processing...]
Processing issue 1/185: KCBL-1
[Creating defect...]

...

🎉 Import completed!
Summary:
  Projects processed: KCBL
  Total issues processed: 185
  Successfully imported: 185
    - Created: 125
    - Updated: 60
  Skipped: 0
  Errors: 0

🔧 Running repair pass for missing items...
  Validating and updating descriptions...
    - Checked: 185
    - Updated: 12
    - Skipped (no changes): 173
    - Errors: 0
🔧 Repair pass complete!

📋 DETAILED IMPORT VERIFICATION REPORT
================================================================================
KCBL-1           -> OK    (comments: 5/5, issue_atts: 3/3, comment_atts: 2/2, labels: 1/1, history: 8/8)
KCBL-2           -> OK    (comments: 2/2, issue_atts: 0/0, comment_atts: 0/0, labels: 0/0, history: 3/3)
...
Overall Success Summary:
  Issues fully OK: 185/185 (100%)
  Issues with problems: 0
```

## Understanding the Description Repair Output

### Status Indicators
- `[DESCRIPTION-REPAIRED]` - Description was updated
- `[DESCRIPTION-VALIDATE]` - Checking a description
- `[DESCRIPTION-UPDATE]` - Actually updating the description
- `[DESCRIPTION-ERROR]` - Error during update

### Verbose Mode Details

With `--verbose`, you see:

```
[DESCRIPTION-VALIDATE] KCBL-123: new_len=2847, existing_len=2100
```
- `new_len=2847`: New description from Jira is 2847 characters
- `existing_len=2100`: Current description in database is 2100 characters
- Difference detected → Will update

```
[DESCRIPTION-UPDATE] KCBL-123: Updated description (2847 chars)
  Previous: This is the old description...
  Updated: This is the new description with tables...
```
- Shows first 100 chars of old and new descriptions

## Checking Results

### Are descriptions correct?
✅ Check the "OK" status in the verification report

### Count of Updated Descriptions
Look in the repair pass output:
```
[Updated: 12]  ← 12 descriptions were updated
```

### List of Changed Issues
Use verbose mode and grep for updates:
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose 2>&1 | grep "DESCRIPTION-REPAIRED"
```

### If Something Went Wrong
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose 2>&1 | grep "ERROR"
```

## Content Extraction Examples

### Tables
Extracted as:
```
[Table]
Column1 | Column2 | Column3
Value1  | Value2  | Value3
[/Table]
```

### Lists
Extracted as:
```
• First item
• Second item
• Third item

1. First step
2. Second step
3. Third step
```

### Code Blocks
Extracted as:
````
```language
code here
```
````

### Headings
Extracted as:
```
# Main heading (level 1)
## Sub heading (level 2)
### Sub-sub heading (level 3)
```

## Smart Update Logic

The script only updates if:
1. **Content actually differs** - Not just whitespace
2. **Case matters** - Different capitalization = different content
3. **Format preserved** - Tables, lists, code blocks maintained

**Example**:
- JIRA: "  Hello  World  " (extra spaces)
- DB: "hello world" (different case, no spaces)
- **Result**: UPDATE (normalized forms differ)

## Troubleshooting

### Issue: "Description not updating"
**Check**: Is the defect already in the database?
```bash
rails console
Defect.find_by(defect_unique: "KCBL-123")
```

### Issue: "Errors during description update"
**Check**: Database constraints or permissions
```bash
# View the error log
tail -f log/development.log | grep "DESCRIPTION-ERROR"
```

### Issue: "All descriptions skipped"
**Check**: Descriptions might already match
- This is normal if descriptions haven't changed in Jira
- Verify with a test issue that definitely changed

## Performance Tips

1. **First run** (many new issues):
   - Expect longer processing time
   - Use smaller project list if needed
   - `--project KCBL` instead of all projects

2. **Subsequent runs** (mostly updates):
   - Much faster (only changes applied)
   - Safe to run frequently
   - No risk of re-importing

3. **Large descriptions**:
   - Script handles automatically
   - May take longer to extract tables
   - Monitored with progress indicators

## Getting Help

To see all available options:
```bash
rails runner scripts/import_jira_with_modules.rb --help
```

Output:
```
Usage: rails runner scripts/import_jira_with_modules.rb --project PROJECT_KEY [options]

Options:
    --project KEY1,KEY2,...    Jira project key(s) (e.g. PSP or PSP,KCBL,FLOW)
    --dry-run                  Don't save; only show what would happen
    --verbose                  Verbose logging
    --days N                   How many days back to fetch (default 2000)
```

## Summary

- ✅ Descriptions with all content types are properly extracted
- ✅ Smart validation ensures only necessary updates
- ✅ Detailed reporting shows exactly what changed
- ✅ Integrated into the main import workflow
- ✅ Safe to run multiple times
- ✅ Full error handling and recovery

