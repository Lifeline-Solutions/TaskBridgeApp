# Jira Import Quick Reference

## Quick Commands

```bash
# Import single project (PSP)
rails runner scripts/run_import.rb --project PSP

# Import multiple projects
rails runner scripts/run_import.rb --project KCBL,PSP,FLOW

# Preview without saving (dry-run)
rails runner scripts/run_import.rb --project KCBL --dry-run

# Verbose output (shows all decisions)
rails runner scripts/run_import.rb --project KCBL --verbose

# Import last 90 days only
rails runner scripts/run_import.rb --project KCBL --days 90

# Combined: verbose + dry-run + 30 days
rails runner scripts/run_import.rb --project KCBL --verbose --dry-run --days 30
```

## Expected Output Summary

After import completes, you'll see:

```
🎉 Import completed!
Summary:
  Projects processed: PSP
  Total issues processed: 114
  Successfully imported: 96
    - Created: 42
    - Updated: 54
  Skipped: 3
  Errors: 15

📊 Per-Project Breakdown:
  PSP:
    - Issues: 114
    - Comments: 287
    - Attachments: 542
    - Labels: 156

📊 Module Mapping Summary:
  Banking Types created/found: 5
  QA Modules created/found: 12
  Submodules created/found: 28

📁 Data Import Summary:
  Labels created/attached: 156
  Comments imported: 287
  Attachments (defect-level): 428
  Attachments (comment-level): 114
  History entries imported: 1205
```

## User Matching Report

The script tracks user matching success:

```
USER MATCHING STATISTICS:
  Total user lookups: 284
  ✅ Email matches: 156 (55.0%)
  ✅ Full name matches: 78 (27.5%)
  ✅ First+Last name matches: 32 (11.3%)
  ✅ Partial matches: 12 (4.2%)
  ✅ Config map matches: 0 (0.0%)
  ✅ Created new users: 3 (1.1%)
  ⚠️ Fallback to DEFAULT_USER: 3 (1.1%)

NOT FOUND NAMES:
  • 'Unknown User' (5 occurrences)
  • 'System Account' (2 occurrences)

MATCHED USERS (24 unique):
  • David Ger (123 assignments)
  • John Doe (87 assignments)
  • Jane Smith (64 assignments)
  ...

FALLBACK USERS (3):
  • DEFAULT_USER (3 assignments)
```

## Troubleshooting Quick Fixes

| Issue | Solution |
|-------|----------|
| "No issues fetched" | Check credentials, verify project key (case-sensitive) |
| "Connection timeout" | Check internet, try `--days 30` for smaller batches |
| "User not found" warnings | Set `create_missing_users: true` in config |
| "Attachment download failed" | Check disk space, network, try rerun (skips done ones) |
| "No comments imported" | This is normal if issues have no comments |
| "Database error" | Check permissions, disk space, rails logs |

## Configuration Checklist

Before running import, ensure:

- [ ] `config/jira_import.yml` exists and has correct values
- [ ] `JIRA_API_TOKEN` is set (env var or config file)
- [ ] Jira project keys are correct
- [ ] Product UUIDs match database
- [ ] Default user UUID exists in database
- [ ] Enough disk space for attachments
- [ ] Database backups created

## File Structure Expected

```
config/
  jira_import.yml          ← Configuration file
app/middleware/
  error_notifier_middleware.rb  ← Error handling
scripts/
  run_import.rb            ← Main runner (use this!)
  import_jira_with_modules.rb  ← Import logic
```

## Key Features

✅ Rich-text descriptions (tables, lists, formatting)  
✅ Rich-text comments (full formatting preserved)  
✅ Intelligent attachment handling (smart retry, progress tracking)  
✅ Smart user matching (dot names, multi-part, email fallback)  
✅ Complete history/changelog import  
✅ Label creation and attachment  
✅ Module and banking type mapping  
✅ Comprehensive error reporting  
✅ Dry-run mode for verification  
✅ Support for multiple projects in one run  

## User Name Format Support

| Format | Example | Parsed As |
|--------|---------|-----------|
| Dot-separated | archana.verma | Archana Verma |
| Two-part | John Smith | John Smith |
| Three-part | Eva Njagi Kirimi | Eva Kirimi (picks 1st & last) |
| With email | john.smith@domain.com | john smith (from email) |

## Performance Tips

1. **Use `--dry-run` first** - Always preview before saving
2. **Import in batches** - Use `--days 90` for large projects
3. **Off-peak times** - Run during low-traffic hours  
4. **Monitor logs** - Watch `tail -f log/production.log` during import
5. **Check disk** - Ensure 2-3x attachment total size available
6. **Database backup** - Always backup before large imports

## Support Files

- **Usage Guide:** `JIRA_IMPORT_USAGE.md` (full documentation)
- **This file:** `JIRA_IMPORT_QUICK_REFERENCE.md` (quick commands)
- **Examples:** See any `--dry-run` output for expected results
- **Logs:** Check `log/production.log` for details

