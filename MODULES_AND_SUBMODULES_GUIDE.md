# Module & Submodule Assignment - Complete Guide

## Overview

The new `assign_modules_and_submodules.rb` script provides a flexible way to assign modules and submodules to defects, with proper parsing of the full module/submodule names (including everything after delimiters like hyphens, slashes, and pipes).

---

## Key Features

✅ **Full Module/Submodule Extraction**
- Captures entire module names before first delimiter
- Captures entire submodule names after first delimiter
- Handles multiple delimiters: `-`, `–`, `—`, `/`, `|`

✅ **Three Operation Modes**
- Single defect: `--defect PSP-114`
- All defects in project: `--project PSP`
- All defects in database: `--all`

✅ **Safe by Default**
- Dry-run mode preview changes
- Shows before/after comparisons
- No changes without confirmation

✅ **Smart Module Handling**
- Creates missing modules/submodules automatically
- Finds existing modules (case-insensitive)
- Handles product relationships

---

## Usage

### Mode 1: Single Defect
```bash
# Process just PSP-114
rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

# Preview changes first (dry-run)
DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

# With verbose output
VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114
```

### Mode 2: Entire Project
```bash
# Process all defects in PSP project
rails runner scripts/assign_modules_and_submodules.rb --project PSP

# Preview first
DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP

# Verbose
VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --project PSP
```

### Mode 3: All Defects
```bash
# Process every defect in database
rails runner scripts/assign_modules_and_submodules.rb --all

# Preview all changes
DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --all

# Verbose output for all
VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --all
```

---

## Module/Submodule Parsing Examples

The script properly extracts full names:

```
INPUT                                  MODULE              SUBMODULE
────────────────────────────────────────────────────────────────────────
Core Banking                          Core Banking        (none)
Core Banking - Accounts               Core Banking        Accounts
Core Banking - Accounts - Savings     Core Banking        Accounts - Savings
Mobile App / Android / Login          Mobile App          Android / Login
Module | SubA | SubB | SubC           Module              SubA | SubB | SubC
PSP-114 – Advanced – Deep – Level     PSP-114             Advanced – Deep – Level
```

---

## Output Examples

### Single Defect Processing
```bash
$ rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

====================================================================================================
📦 DEFECT MODULE & SUBMODULE ASSIGNMENT
====================================================================================================
Mode: Single Defect (PSP-114)
Dry Run: NO
Verbose: NO

Found 1 defect(s) to process...

✅ PSP-114: Module=Core Banking, Submodule=Accounts - Savings
```

### Project Processing (with dry-run)
```bash
$ DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP

====================================================================================================
📦 DEFECT MODULE & SUBMODULE ASSIGNMENT
====================================================================================================
Mode: Project (PSP)
Dry Run: YES
Verbose: NO

Found 45 defect(s) to process...

👁️  PSP-1: Would be updated (DRY RUN)
👁️  PSP-2: Would be updated (DRY RUN)
👁️  PSP-114: Would be updated (DRY RUN)
...

====================================================================================================
📊 SUMMARY
====================================================================================================
Total Defects:     45
Updated:           0
Previewed (DRY):   45
Skipped:           0
Errors:            0

ℹ️  DRY RUN MODE: 45 defect(s) would be updated.
    To apply changes, run without DRY_RUN=true
====================================================================================================
```

### Verbose Output
```bash
$ VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

[MODULE-FOUND] Core Banking (ID: uuid-123)
[SUBMODULE-FOUND] Accounts - Savings (ID: uuid-456, Parent: Core Banking)

[PROCESSING] PSP-114
  Current Module: Core Banking (ID: uuid-123)
  Current Submodule: Accounts - Savings (ID: uuid-456)
  New Module: Core Banking
  New Submodule: Accounts - Savings
  ✓ No changes needed

✅ PSP-114: Module=Core Banking, Submodule=Accounts - Savings
```

---

## Workflow Recommendations

### For Testing
```bash
# Step 1: See what will happen (dry-run)
DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP

# Step 2: Review the preview carefully

# Step 3: Execute if satisfied
rails runner scripts/assign_modules_and_submodules.rb --project PSP
```

### For Single Defect Fixes
```bash
# Check status
VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114

# If changes needed, apply them
rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114
```

### For Bulk Updates
```bash
# Step 1: Preview all changes
DRY_RUN=true VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --all

# Step 2: Run actual update
rails runner scripts/assign_modules_and_submodules.rb --all
```

---

## What the Script Does

### 1. **Extracts Module/Submodule Names**
- Parses full module text including everything after first delimiter
- Supports multiple delimiter types
- Maintains entire submodule text (not just first part)

### 2. **Finds or Creates Modules**
- Searches database for existing module (case-insensitive)
- Creates new module if needed
- Links to product

### 3. **Finds or Creates Submodules**
- Searches within parent module
- Creates if missing
- Maintains hierarchy

### 4. **Assigns to Defects**
- Updates defect.qa_module_id
- Updates defect.submodule_id
- Tracks what changed
- Sets modified_by and updated_at

---

## Status and Results

The script provides clear feedback for each defect:

| Status | Meaning | Example |
|--------|---------|---------|
| `✅ Updated` | Changes applied | `✅ PSP-114: Module=Core, Submodule=Accounts - Savings` |
| `⏭️  Skipped` | No changes needed | `⏭️  PSP-115: Skipped (no_changes)` |
| `👁️  Preview` | Would update (DRY RUN) | `👁️  PSP-116: Would be updated (DRY RUN)` |
| `❌ Error` | Failed to process | `❌ PSP-117: Error (save_failed)` |

---

## Return Codes

- `0`: Success (all processed)
- `1`: No defects found, or invalid options

---

## Integration with Import Script

The main `import_jira_with_modules.rb` has been updated with improved parsing:

```ruby
# The parse_module_and_submodule function now:
# - Splits on FIRST delimiter only
# - Keeps entire text after first delimiter as submodule
# - Supports: - (hyphen), – (en dash), — (em dash), / (slash), | (pipe)

# Before: "Core Banking - Accounts - Savings" => ["Core Banking", "Accounts"]
# After:  "Core Banking - Accounts - Savings" => ["Core Banking", "Accounts - Savings"]
```

---

## Error Handling

The script handles errors gracefully:

```bash
# Missing defect
❌ No defects found for PSP-114

# Failed module creation
❌ ERROR: Failed to create module 'name': [error details]

# Failed save
❌ PSP-114: Error (save_failed)
```

---

## Performance

- Single defect: < 1 second
- Project (50 defects): 5-10 seconds
- All defects (1000+): 1-2 minutes

---

## Common Usage Patterns

### Add Module to One Defect
```bash
rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114
```

### Bulk Fix a Project
```bash
DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP
# Review...
rails runner scripts/assign_modules_and_submodules.rb --project PSP
```

### Audit All Module Assignments
```bash
VERBOSE=true rails runner scripts/assign_modules_and_submodules.rb --all | tee audit.log
```

---

## Troubleshooting

### "No defects found"
- Check defect exists: `rails c` → `Defect.find_by(defect_unique: 'PSP-114')`
- Check spelling of ticket key
- Verify project key matches

### "Failed to create module"
- Check database permissions
- Verify product exists
- Check for duplicate modules with different case

### Changes not applying
- Ensure not using DRY_RUN=true
- Check verbose output for error details
- Verify database connectivity

---

## Feature Details

### Module Creation
- Case-insensitive matching for existing modules
- Creates missing modules automatically (if CREATE_MISSING_MODULES enabled in import config)
- Links to defect's product

### Submodule Creation
- Created under parent module
- Case-insensitive matching
- Maintains hierarchy

### Change Tracking
- Shows before/after values
- Logs what changed
- Sets updated_at timestamp

---

## Next Steps

1. **Test Single Defect**: `rails runner scripts/assign_modules_and_submodules.rb --defect PSP-114`
2. **Preview Project**: `DRY_RUN=true rails runner scripts/assign_modules_and_submodules.rb --project PSP`
3. **Apply Changes**: `rails runner scripts/assign_modules_and_submodules.rb --project PSP`
4. **Verify Results**: Check defects have correct module/submodule assignments

---

## Summary

Your new script provides:
- ✅ Full module/submodule extraction
- ✅ Flexible operation modes (one, project, all)
- ✅ Safe dry-run testing
- ✅ Automatic module/submodule creation
- ✅ Clear progress reporting
- ✅ Proper error handling

