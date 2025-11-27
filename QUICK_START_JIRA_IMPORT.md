# Quick Start Guide - Enhanced JIRA Import

## 30-Second Summary

The updated `import_jira_with_modules.rb` script now intelligently parses Jira user names (including dot-separated format like `archana.verma` and multi-part names like `Eva Karimi Njagi`) and provides comprehensive tracking and reporting of user matching results.

## Step-by-Step Guide

### Step 1: Test in Dry-Run Mode (No Changes)

```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run
```

This will:
- Fetch issues from Jira
- Parse user names using new strategies
- Show what would be imported
- Print user match statistics
- **NOT** change database

### Step 2: Review the Final Report

Look for this section in the output:

```
👤 USER MATCH STATISTICS REPORT
============================================================
Total user lookups performed: X

Match breakdown:
  ✅ Email matches:          X (X%)
  ✅ Full name matches:      X (X%)
  ✅ First+Last matches:     X (X%)
  ✅ Partial matches:        X (X%)
  ✅ Config map matches:     X
  🆕 Created users:          X
  ⚠️  Fallback to default:    X
```

### Step 3: Check for Issues

Look for:

**"Issues where reporter fell back to default user:"**
- If few: OK, proceed
- If many: Review the names listed

**"Issues where assignee fell back to default user:"**
- If few: OK, proceed
- If many: Review the names listed

**"Names that could not be matched:"**
- Review the list
- If critical users are missing: Add them to system before importing

### Step 4: Run Real Import

Once satisfied with dry-run results:

```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL
```

This will:
- Actually create/update defects
- Download attachments
- Import comments and history
- Generate final verification report

### Step 5: Verify Import Results

The script will show:

```
📋 DETAILED IMPORT VERIFICATION REPORT
============================================================
[Issue Key]  -> OK/ISSUES  (comments: X/Y, issue_atts: X/Y, ...)
```

Check for any "ISSUES" status and review the details.

## Common Name Formats & How They're Parsed

| Format | Example | Parsed As | Strategy |
|--------|---------|-----------|----------|
| Dot-separated | `archana.verma` | first: archana, last: verma | dot-separated |
| Multi-part | `Eva Karimi Njagi` | first: Eva, last: Karimi | multi-part-first-two |
| Standard | `John Smith` | first: John, last: Smith | standard-split |
| Single | `simon` | first: simon, last: (none) | single-part |
| Mixed Case | `SARAH SYUKI` | first: SARAH, last: SYUKI | standard-split |

## Key Improvements

✅ **Dot-separated names**: `archana.verma` now correctly parses as first="archana", last="verma"

✅ **Multi-part names**: `Eva Karimi Njagi` uses first 2 parts to avoid matching issues

✅ **Tracking**: Every user match/fallback is tracked and reported

✅ **Reporter/Assignee**: Each issue tracks which user was assigned and why

✅ **Statistics**: Final report shows exactly what was matched and what fell back to default

## If Something Goes Wrong

### Too many fallback users?

1. Run with `--verbose` to see detailed matching attempts
2. Check `$USER_STATS[:not_found_names]` for which names couldn't be matched
3. Add missing users to system or update `user_map` in config

### Names parsing incorrectly?

1. Check the "Name Parsing Strategies Used" section in final report
2. Run test script: `ruby scripts/test_user_name_parsing.rb`
3. Adjust `parse_jira_name` function if needed

### Wrong users assigned?

1. Review "Issues where [reporter/assignee] fell back to default user" section
2. Check if users exist in system with same email
3. Verify user first_name and last_name fields match Jira names

## Multi-Project Import

```bash
# Import multiple projects at once
rails runner scripts/import_jira_with_modules.rb --project KCBL,PSP,FLOW --dry-run
```

Output will show:
- Issues per project
- User matches per project
- Separate statistics for better analysis

## Validation Scripts

Before main import, you can test:

```bash
# Test name parsing logic (standalone)
ruby scripts/test_user_name_parsing.rb

# Test parsing against actual database users
rails runner scripts/validate_user_parsing.rb
```

## Key Configuration (config/jira_import.yml)

```yaml
# Control user behavior
create_missing_users: true          # Auto-create users if not found

# Optional: Manual user mappings
user_map:
  "john.smith": "user-uuid-here"
  "archana.verma": "user-uuid-here"

# Fallback for unmatched users
default_user_uuid: "default-uuid"
```

## Performance Tips

- First run: Add `--verbose` to see progress
- Large projects: Run with `--days 30` to limit scope
- Multiple projects: Run in sequence, not parallel
- Typical: ~1000 issues takes 5-10 minutes

## Next Steps

1. ✓ Run `--dry-run` first
2. ✓ Review user statistics
3. ✓ Check for fallback users
4. ✓ Add any missing users if needed
5. ✓ Run full import without `--dry-run`
6. ✓ Review verification report

## Questions?

See detailed documentation: `JIRA_IMPORT_ENHANCEMENTS.md`

Common scenarios covered:
- Handling duplicate users
- Name parsing edge cases
- Email-based matching
- Multi-pass matching logic
- Troubleshooting guides

