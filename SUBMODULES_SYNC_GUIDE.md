# Submodules Sync Script Guide

## Overview
The `fix_submodules.rb` script automatically synchronizes module and submodule information from JIRA to the database for multiple projects (RMP, KCBL, PSP, SMC).

## Supported Projects

### 1. **RMP - Rafiki Mobile Platform**
   - **Module Field**: Rafiki Modules
   - **Submodule Field**: Rafiki Modules / Sub-Modules
   - **Module Structure**: Parent → Child modules

### 2. **KCBL - Kenya Commercial Bank Limited**
   - **Module Field**: KCBL Modules
   - **Submodule Field**: KCBL Modules / Submodules
   - **Banking Type**: Core Banking (auto-assigned)
   - **Product ID**: c1469eb7-97d1-4611-9e67-3fce1d0bb1ac

### 3. **PSP - Kenya Police Service**
   - **Module Field**: Kenya Police Modules
   - **Submodule Field**: Kenya Police Modules / Sub-Modules
   - **Product Lookup**: By document_name containing "Kenya Police" or jira_key "PSP"

### 4. **SMC - Sofia Credit**
   - **Module Field**: Components - Sofia Credit
   - **Submodule Field**: Sofia Modules_Submodules
   - **Product Lookup**: By document_name containing "Sofia" or jira_key "SMC"

## Usage Examples

### Process All Defects Across All Projects
```bash
rails runner scripts/fix_submodules.rb --all -e production
```

### Process Entire Project (All Defects)
```bash
# PSP Project
rails runner scripts/fix_submodules.rb --project PSP -e production

# SMC Project
rails runner scripts/fix_submodules.rb --project SMC -e production

# KCBL Project
rails runner scripts/fix_submodules.rb --project KCBL -e production

# RMP Project
rails runner scripts/fix_submodules.rb --project RMP -e production
```

### Process Single Defect
```bash
# Process PSP-1
rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production

# Process SMC-5
rails runner scripts/fix_submodules.rb --project SMC --defect SMC-5 -e production

# Process KCBL-100
rails runner scripts/fix_submodules.rb --project KCBL --defect KCBL-100 -e production
```

### Dry Run (Preview Changes Without Applying)
```bash
# Preview all changes for PSP project
rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production

# Preview single defect changes
rails runner scripts/fix_submodules.rb --project SMC --defect SMC-5 --dry-run -e production

# Preview all projects
rails runner scripts/fix_submodules.rb --all --dry-run -e production
```

## Output Example

```
[15:22:45] Starting submodule fix script (Dry Run: false)
[15:22:45] Processing project: PSP
[15:22:45] Processing project: PSP
[15:22:45] ================================================================================
[15:22:45] Processing project: PSP
[15:22:45] ================================================================================
[15:22:45] Discovered fields - Module: customfield_10164, Submodule: customfield_10163
[15:22:45] Found 4 defect(s) to check.
[15:22:45]   PSP-1: Updating...
[15:22:45]     Old: Module='', Sub=''
[15:22:45]     New: Module='Authentication', Sub='Login Flow'
[15:22:45]     ✅ Updated successfully
[15:22:45]   PSP-2: Updating...
[15:22:45]     Old: Module='', Sub=''
[15:22:45]     New: Module='Authentication', Sub='Password Reset'
[15:22:45]     ✅ Updated successfully
[15:22:45] 
[15:22:45] Project PSP Results:
[15:22:45]   Updated: 2, Skipped: 2, Errors: 0
[15:22:45] 
[15:22:45] ================================================================================
[15:22:45] Script completed!
[15:22:45] ================================================================================
```

## Field Discovery

The script automatically discovers the correct custom field IDs from JIRA for each project by matching field names:

**RMP**: 
- Looks for "Rafiki Modules" and "Rafiki Modules / Sub-Modules"

**KCBL**:
- Looks for "KCBL Modules" and "KCBL Modules / Submodules"

**PSP**:
- Looks for "Kenya Police Modules" and "Kenya Police Modules / Sub-Modules"

**SMC**:
- Looks for "Components - Sofia Credit" and "Sofia Modules_Submodules"

## Features

✅ **Automatic Field Discovery** - Finds custom fields by project key
✅ **Multi-Project Support** - Process one or all projects
✅ **Single Defect Support** - Target specific defects
✅ **Dry Run Mode** - Preview changes before applying
✅ **Auto Module Creation** - Creates parent/child modules if they don't exist
✅ **Smart Parsing** - Handles cascading select fields correctly
✅ **Product Mapping** - Automatically maps products by name or JIRA key
✅ **Banking Type Assignment** - Sets project-specific banking types
✅ **Detailed Logging** - Shows exactly what was updated

## Error Handling

- Skipped defects are logged when they have no module data
- Errors are caught and logged without stopping the script
- Each project runs independently so errors don't affect other projects
- Summary statistics provided at the end

## Requirements

- Rails environment with database connection
- JIRA API credentials in config/jira_import.yml
- Defect records in the database
- Custom fields configured in JIRA for each project

## Advanced Features

### Manual Field Configuration
If the field discovery fails, you can manually configure field IDs in the `discover_custom_fields` method by adding specific project patterns.

### Product Auto-Detection
- **KCBL**: Uses hardcoded UUID
- **PSP**: Looks for product with "Kenya Police" in name or "PSP" in jira_key
- **SMC**: Looks for product with "Sofia" in name or "SMC" in jira_key
- **RMP**: Uses default product UUID from config

### Banking Type Assignment
- **KCBL**: Auto-assigns "Core Banking" banking type
- **SMC**: Can be configured with banking type UUID
- **Others**: Not auto-assigned

## Notes

- Always run with `--dry-run` first to preview changes
- The script is idempotent - running it multiple times is safe
- Requires valid JIRA API credentials
- Database updates are transactional
- Cascade select fields are properly handled (parent/child extraction)

