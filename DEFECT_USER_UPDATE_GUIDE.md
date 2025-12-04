# Defect User Assignment Update Guide

This guide explains how to update creator (reporter) and assignee fields for defects imported from Jira using intelligent name matching.

## Overview

The `update_defect_user_mappings.rb` script updates user assignments for defects by:
- Fetching the latest data from Jira
- Using intelligent name matching to handle initials, reversed names, and partial matches
- Updating creator (reporter) and assignee fields
- Providing detailed reports of changes and unmatched names

## Features

### Intelligent Name Matching

The script handles various name formats:

1. **Initials**: `V. Kaunda` → matches `Vincent Kaunda`
2. **Reversed names**: `Kaunda Vincent` → matches `Vincent Kaunda`
3. **Partial names**: `Kaunda` → matches `Vincent Kaunda`
4. **Email addresses**: `archana.verma@example.com` → matches user by email
5. **Dot-separated usernames**: `archana.verma` → matches `Archana Verma`
6. **Case-insensitive matching**: All comparisons ignore case

### Matching Strategies (Priority Order)

1. **Email exact match** (highest priority)
2. **Exact full name match** (case-insensitive)
3. **Initial + last name** (e.g., `V. Kaunda`)
4. **First name + initial** (e.g., `Vincent K.`)
5. **Standard first + last split**
6. **Reversed name matching**
7. **Partial name matching**
8. **Single name matching** (checks both first and last)
9. **Fuzzy matching** (contains all parts)

## Usage

### Basic Commands

#### Update all defects for a project
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP
```

#### Update a specific issue
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --issue PSP-113
```

#### Preview changes without saving (DRY RUN)
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project KCBL --dry-run
```

#### Verbose output (shows matching details)
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project ISP --verbose
```

#### Combine options
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP --dry-run --verbose
```

## Workflow

### Step 1: Preview Changes (Dry Run)

Always start with a dry run to see what would change:

```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP --dry-run --verbose
```

This will show you:
- Which users will be matched
- Before/after values
- Names that cannot be matched

### Step 2: Review the Report

The script provides detailed reports:

#### Successfully Matched Names
```
✅ Creator Names Successfully Matched (5 unique):
  ✓ 'Pratik Mehta' (729 occurrences)
  ✓ 'Lydia Okoth' (239 occurrences)
  ...
```

#### Unmatched Names
```
❌ Creator Names That Could NOT Be Matched (3 unique):
  ✗ 'JoeChris' (2 occurrences)
  ✗ 'Jacqueline.Mwaura@sc.com' (1 occurrence)
```

#### Detailed Changes
```
📋 Detailed Creator Changes:
  PSP-113:
    Jira name: 'V. Kaunda'
    Before: Stephen Mungai (ID: b3613172-fc54-4742-b2ba-c10b97d15bf4)
    After:  Vincent Kaunda (ID: a1b2c3d4-e5f6-7890-abcd-1234567890ab)
```

### Step 3: Handle Unmatched Names

For names that couldn't be matched:

1. **Check for typos** in TaskBridge user records
2. **Add missing users** to TaskBridge
3. **Run again** to pick up newly added users

### Step 4: Apply Changes (Live Update)

Once you're satisfied with the preview, run without `--dry-run`:

```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP
```

**⚠️ Important**: This will modify your database. Make sure you've reviewed the dry run output first.

## Project Keys

Common project keys in your system:
- `PSP` - PSP defects
- `KCBL` - KCBL defects  
- `ISP` - ISP defects
- `FLOW` - Flow defects

Check `config/jira_import.yml` for the complete list of project mappings.

## Examples

### Example 1: Update all PSP defects (preview)
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project PSP --dry-run
```

### Example 2: Update all ISP defects (live)
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project ISP
```

### Example 3: Fix a specific issue with verbose output
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --issue PSP-1234 --verbose
```

### Example 4: Update all KCBL defects and save output to file
```bash
bundle exec rails runner scripts/update_defect_user_mappings.rb --project KCBL --verbose | tee kcbl_update_report.txt
```

## Output Explanation

### Summary Section
```
Summary:
  Total defects processed: 150
  Creators updated: 85
  Assignees updated: 42
  No change needed: 23
  Skipped (Jira fetch failed): 0
  Failed: 0
```

- **Total defects processed**: Number of defects examined
- **Creators updated**: Number of defects where creator was changed
- **Assignees updated**: Number of defects where assignee was added/changed
- **No change needed**: Defects already assigned correctly
- **Skipped**: Defects that couldn't be fetched from Jira
- **Failed**: Defects that had errors during save

### Matched Names
Shows names that were successfully matched to TaskBridge users, with occurrence count.

### Unmatched Names
Shows names that couldn't be matched. These may need manual attention:
- Create the user in TaskBridge
- Fix typos in existing user records
- Check if the name format is unusual

### Detailed Changes
Lists before/after values for each changed defect, useful for auditing.

## Troubleshooting

### Issue: "No defects found matching criteria"

**Cause**: No defects in database match the project key

**Solution**: 
- Check the project key is correct
- Verify defects have been imported with `defect_unique` values
- Use `--project PSP` format (not `PSP-113`)

### Issue: "Could not fetch from Jira - skipping"

**Cause**: Issue doesn't exist in Jira (local test data) or API error

**Solution**:
- This is expected for local test data (like KCBL)
- For real projects, check Jira API credentials in `config/jira_import.yml`
- Verify the issue exists in Jira

### Issue: Many names show as "No match"

**Cause**: Users don't exist in TaskBridge or name format is different

**Solution**:
1. Check user records in TaskBridge
2. Add missing users manually
3. Verify `first_name` and `last_name` fields are populated correctly
4. Run the script again after adding users

### Issue: "Failed to save" errors

**Cause**: Validation errors on Defect model

**Solution**:
- Check error message for specific validation failures
- Ensure all required fields are present
- Check database constraints

## Best Practices

1. **Always run dry-run first** to preview changes
2. **Use verbose mode** when debugging matching issues
3. **Save output to file** for large updates: `| tee update_report.txt`
4. **Update one project at a time** for better control
5. **Review unmatched names** and add missing users before updating
6. **Backup database** before running live updates on production

## Safety Features

- **Dry run mode**: Preview without making changes
- **No data deletion**: Only updates fields, never deletes records
- **Detailed logging**: Full audit trail of all changes
- **Error handling**: Script continues even if individual defects fail
- **Verbose matching**: Shows exactly how names were matched

## Configuration

The script uses settings from `config/jira_import.yml`:

```yaml
jira_base_url: "https://craftsilicon.atlassian.net"
jira_api_user: "your.email@example.com"
jira_api_token: "your-jira-api-token"

project_uuid_map:
  PSP: "uuid-for-psp-project"
  KCBL: "uuid-for-kcbl-project"
  ...

default_user_uuid: "uuid-for-default-user"
```

## Support

If you encounter issues:
1. Check this guide for troubleshooting steps
2. Run with `--verbose` to see detailed matching logic
3. Review the final report for specific unmatched names
4. Check Jira API connectivity and credentials

## Advanced: Understanding the Matching Process

When the script encounters a name like "V. Kaunda", it:

1. **Checks if it's an email** → Match by email if found
2. **Tries exact full name** → "v. kaunda" vs full names
3. **Detects initial "V."** → Searches for first_name starting with 'V' AND last_name = 'Kaunda'
4. **Tries standard split** → first='V.', last='Kaunda'
5. **Tries reversed** → first='Kaunda', last='V.'
6. **Fuzzy match** → Users containing both 'V' and 'Kaunda'

Each strategy is tried in order until a match is found. Verbose mode shows which strategy succeeded.
