# JIRA Import - User Assignment & Name Parsing Guide

## Overview

The enhanced JIRA import scripts include sophisticated user name parsing and matching to ensure that reporters and assignees are correctly mapped from Jira to the local database.

## Features

### 1. Enhanced Name Parsing

The import script can parse user names in multiple formats:

#### **Dot-Separated Format** (e.g., `archana.verma`)
- Split on the dot (.)
- First part becomes `first_name` ("archana")
- Second part becomes `last_name` ("verma")

#### **Multi-Part Names** (e.g., `Eva Karimi Njagi`)
- Names with 3+ parts use the first 2 parts
- First part: "Eva"
- Second part: "Karimi"
- Middle/additional parts are ignored

#### **Standard Two-Part Names** (e.g., `John Smith`)
- First part: "John"
- Second part: "Smith"

#### **Single-Part Names**
- Used as-is for matching against first or last name in database

### 2. Multi-Level User Matching

The script uses a priority-based matching strategy:

1. **Email Match** (Most reliable)
   - Direct email lookup in database
   - Case-insensitive

2. **Parsed First + Last Name Match**
   - Uses enhanced name parsing
   - Exact match (case-insensitive)

3. **Partial Name Matching**
   - First name exact + last name prefix
   - Last name exact + first name prefix

4. **Full Name Match** (Backward compatibility)
   - Concatenated first + last against database

5. **Config Map Override**
   - Manual mapping from configuration file
   - Useful for known edge cases

6. **User Creation** (If configured)
   - Creates new users with parsed names
   - Uses EMAIL_CREATES_USERS config option

7. **Fallback to Default User**
   - Last resort if no matches found
   - Issues are flagged in report for manual review

### 3. Match Statistics Tracking

During import, the script tracks:

- Total user lookups
- Breakdown by match type (email, parsed, partial, etc.)
- Created users
- Fallback to default users
- Unmatched names

## Usage

### Running the Import

```bash
# Dry-run (no changes)
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run

# Actual import
rails runner scripts/import_jira_with_modules.rb --project KCBL

# Multiple projects
rails runner scripts/import_jira_with_modules.rb --project PSP,KCBL,FLOW

# Verbose mode (detailed output)
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose
```

### Understanding the Report

At the end of the import, you'll see:

```
👤 USER MATCH STATISTICS REPORT
========================================
Total user lookups performed: 250

Match breakdown:
  ✅ Email matches:          120 (48.00%)
  ✅ Full name matches:      50 (20.00%)
  ✅ First+Last matches:     40 (16.00%)
  ✅ Partial matches:        20 (8.00%)
  ✅ Config map matches:     5 (2.00%)
  🆕 Created users:          10
  ⚠️  Fallback to default:    5

Summary:
  Total unique matched users: 245
  Total unique fallback uses: 1

Reporter/Assignee Matching:
  Reporters: 114 matched, 1 fallback to default
  Assignees: 120 matched, 4 fallback to default

Name Parsing Strategies Used:
  dot-separated: 8 names
  multi-part-first-two: 12 names
  two-part: 225 names
  single-part: 5 names

Dot-separated names parsed:
  - 'archana.verma' → first: 'archana', last: 'verma'
  - 'simon.mungai' → first: 'simon', last: 'mungai'

Multi-part names (using first 2 parts):
  - 'Eva Karimi Njagi' → first: 'Eva', last: 'Karimi'

⚠️  CRITICAL: Issues where reporter fell back to default user (1):
  1. PSP-1:
     Name: 'Unknown User'
     Email: ''
     Assigned to: default-user-id (DEFAULT USER)

⚠️  CRITICAL: Issues where assignee fell back to default user (4):
  1. KCBL-15:
     Name: 'Jane Doe'
     Email: 'jane@example.com'
     Assigned to: default-user-id (DEFAULT USER)
     Parse strategy: two-part
     Parsed as: first='Jane', last='Doe'
```

### Verifying and Fixing Assignments

After import, use the verification script to check and fix any mismatches:

```bash
rails runner scripts/verify_and_fix_user_assignments.rb
```

This script will:
1. Check each defect's reporter and assignee against Jira data
2. Use enhanced name parsing to find correct users
3. Attempt to automatically fix mismatches
4. Report all findings

Example output:
```
⚠️  REPORTER MISMATCH: KCBL-42
   Jira: Jane Smith (jane.smith@example.com)
   Expected user: Jane Smith (id-123)
   Current user: Default User (id-default)
   ✅ FIXED

VERIFICATION & RECONCILIATION REPORT
=====================================
Reporter Verification:
  ✅ Correct: 950
  🔧 Fixed: 45
  ❌ Could not fix: 5

Assignee Verification:
  ✅ Correct: 960
  🔧 Fixed: 35
  ❌ Could not fix: 10
```

## Configuration

Add to `config/jira_import.yml`:

```yaml
# User creation during import
create_missing_users: true  # Set to false to skip creating new users

# Manual user mapping (for edge cases)
user_map:
  'John Doe': 'user-id-123'
  'archana.verma': 'user-id-456'

# Default user for unmatched names
default_user_uuid: 'default-user-id'
```

## Troubleshooting

### Issue: Names falling back to default user

**Cause**: User doesn't exist in database or name format is unexpected

**Solution**:
1. Check spelling in both Jira and database
2. For dot-separated names, ensure database has matching first_name and last_name
3. For multi-part names, verify the first 2 parts match the database
4. Create missing users in database
5. Re-run verification script

### Issue: Case sensitivity problems

**Cause**: Name case doesn't match (e.g., "john smith" vs "John Smith")

**Solution**: The matching is case-insensitive, so this shouldn't be an issue. However, check the database for consistency.

### Issue: Email-based matching not working

**Cause**: Email in Jira doesn't exactly match database email

**Solution**:
1. Check for extra spaces or special characters
2. Verify domain names match exactly
3. Try using name-based matching instead

## Advanced: Custom Name Parsing

To add custom name parsing logic, edit the `parse_jira_name` function in:
- `scripts/import_jira_with_modules.rb`
- `scripts/verify_and_fix_user_assignments.rb`

Example for handling special cases:

```ruby
def parse_jira_name(name_str)
  # Custom handling for specific formats
  if name_str.match?(/\(.*\)/)
    # Remove parenthetical notes
    name_str = name_str.gsub(/\s*\(.*\)\s*/, '')
  end
  
  # ... rest of parsing logic
end
```

## Best Practices

1. **Ensure data consistency**: Keep Jira names and database names in sync before importing
2. **Test with dry-run**: Always run with `--dry-run` first to review changes
3. **Monitor fallbacks**: Check the report for any names falling back to default user
4. **Use verification script**: Run `verify_and_fix_user_assignments.rb` after import
5. **Document manual fixes**: If you manually update users after import, document the changes

## Performance

- Import script processes ~100-200 issues per minute (depending on attachments)
- Verification script checks all defects at ~50 per minute
- Both scripts respect Jira API rate limits with automatic delays

## Support

For issues or questions:
1. Check the detailed report at the end of import
2. Run verification script for additional diagnostics
3. Review this guide for common issues
4. Check `scripts/import_jira_with_modules.rb` for implementation details

