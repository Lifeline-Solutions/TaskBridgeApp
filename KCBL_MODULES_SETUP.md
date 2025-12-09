# KCBL Modules & Submodules Setup

## Overview
This document explains how to update all KCBL defects with the correct module and submodule configuration.

## Configuration
For KCBL project:
- **Module Name:** `KCBL Modules/Submodules`
- **Submodule Name:** `KCBL Modules/Submodules` (same as parent)
- **Applies to:** All defects with `defect_unique` starting with `KCBL`

## Script Usage

The `fix_submodules.rb` script has been updated to support KCBL project with automatic module creation and assignment.

### Dry-run mode (preview changes)
```bash
rails runner scripts/fix_submodules.rb --project KCBL --dry-run -e production
```

### Execute mode (apply changes)
```bash
rails runner scripts/fix_submodules.rb --project KCBL -e production
```

## What the script does for KCBL

1. **Discovers JIRA custom fields** matching `KCBL Modules` and `KCBL Modules/Submodules` patterns
2. **Creates or finds** the `KCBL Modules/Submodules` module in the database
3. **Iterates through all KCBL defects** (defect_unique starts with `KCBL`)
4. **Assigns module and submodule:**
   - Sets `qa_module_id` to the KCBL Modules/Submodules module ID
   - Sets `submodule_id` to the same module ID (both parent and child point to the same module)
5. **Skips** defects that already have correct assignment
6. **Reports** total updated, skipped, and error counts

## Example Output

```
[HH:MM:SS] Starting submodule fix script for project KCBL (Dry Run: false)
[HH:MM:SS] ✓ Matched Module field: KCBL Modules (customfield_10430)
[HH:MM:SS] ✓ Matched Submodule field: KCBL Modules/Submodules (customfield_10431)
[HH:MM:SS] Found 52 defects to check.
[HH:MM:SS] Setting up KCBL Modules/Submodules...
[HH:MM:SS]   ✓ Parent Module: KCBL Modules/Submodules (uuid-here)
[HH:MM:SS]   ✓ Submodule: KCBL Modules/Submodules (uuid-here)
[HH:MM:SS]   KCBL-1: Updating to KCBL Modules/Submodules...
[HH:MM:SS]     ✅ Updated successfully
[HH:MM:SS]   KCBL-2: Updating to KCBL Modules/Submodules...
[HH:MM:SS]     ✅ Updated successfully
...
[HH:MM:SS] Done! Updated: 52, Skipped: 0, Errors: 0
```

## Key Features

✅ **Automatic Module Creation:** If `KCBL Modules/Submodules` doesn't exist, it's created automatically  
✅ **Dry-Run Support:** Preview changes with `--dry-run` flag without modifying database  
✅ **Smart Skipping:** Skips defects that already have correct module assignment  
✅ **Error Handling:** Continues processing on errors, reports them in summary  
✅ **Project-Specific:** Works with KCBL custom field patterns (`KCBL Modules`, `KCBL Modules/Submodules`)  
✅ **Logging:** Detailed timestamp logging for each operation  

## Configuration Notes

The script reads from `config/jira_import.yml`:
- `default_product_id` - Used for creating the KCBL module if it doesn't exist
- `fallback_qa_module_id` - Fallback if module creation fails (optional)
- `fallback_submodule_id` - Fallback if submodule creation fails (optional)

## Troubleshooting

### No defects found
- Verify that defects exist with `defect_unique` starting with `KCBL`
- Check the project key spelling (case-sensitive)

### Custom fields not found
- The script logs all discovered fields
- Check JIRA field names match: `KCBL Modules` and `KCBL Modules/Submodules`
- Run with `--project KCBL --dry-run` to see all discovered fields in logs

### Database connection errors
- Ensure JIRA_API_TOKEN is set in environment or `config/jira_import.yml`
- Verify Rails environment: `-e production` or `-e development`

## Next Steps

1. **Test dry-run:** `rails runner scripts/fix_submodules.rb --project KCBL --dry-run -e production`
2. **Review output** to ensure correct defect count and module names
3. **Execute:** `rails runner scripts/fix_submodules.rb --project KCBL -e production`
4. **Verify** in database: `SELECT defect_unique, qa_module_id, submodule_id FROM defects WHERE defect_unique LIKE 'KCBL%' LIMIT 5;`

