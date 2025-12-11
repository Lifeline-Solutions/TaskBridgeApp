# Submodules Sync - Quick Reference

## Quick Commands

```bash
# Process all projects
rails runner scripts/fix_submodules.rb --all -e production

# Process single project
rails runner scripts/fix_submodules.rb --project PSP -e production
rails runner scripts/fix_submodules.rb --project SMC -e production
rails runner scripts/fix_submodules.rb --project KCBL -e production
rails runner scripts/fix_submodules.rb --project RMP -e production

# Process single defect
rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production
rails runner scripts/fix_submodules.rb --project SMC --defect SMC-5 -e production

# Dry run (preview only)
rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production
rails runner scripts/fix_submodules.rb --all --dry-run -e production
```

## Projects Configuration

| Project | Module Field | Submodule Field | Product Key |
|---------|--------------|-----------------|-------------|
| **RMP** | Rafiki Modules | Rafiki Modules / Sub-Modules | RMP |
| **KCBL** | KCBL Modules | KCBL Modules / Submodules | KCBL |
| **PSP** | Kenya Police Modules | Kenya Police Modules / Sub-Modules | PSP |
| **SMC** | Components - Sofia Credit | Sofia Modules_Submodules | SMC |

## Module Structure

For all projects, modules follow this pattern:

```
Parent Module (e.g., "Authentication")
  ├─ Child Module 1 (e.g., "Login Flow")
  ├─ Child Module 2 (e.g., "Password Reset")
  └─ Child Module 3 (e.g., "Token Management")
```

## Workflow

1. **Preview Changes** (Dry Run)
   ```bash
   rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production
   ```

2. **Apply Changes**
   ```bash
   rails runner scripts/fix_submodules.rb --project PSP -e production
   ```

3. **Check Results** - Script outputs summary:
   - Updated: Number of defects updated
   - Skipped: Defects with no changes
   - Errors: Failed updates

## Output Format

```
[15:22:45] Starting submodule fix script (Dry Run: false)
[15:22:45] Processing project: PSP
[15:22:45] ================================================================================
[15:22:45] Processing project: PSP
[15:22:45] Discovered fields - Module: customfield_10164, Submodule: customfield_10163
[15:22:45] Found 4 defect(s) to check.
[15:22:45]   PSP-1: Updating...
[15:22:45]     Old: Module='', Sub=''
[15:22:45]     New: Module='Authentication', Sub='Login Flow'
[15:22:45]     ✅ Updated successfully
[15:22:45] 
[15:22:45] Project PSP Results:
[15:22:45]   Updated: 2, Skipped: 2, Errors: 0
```

## Options Explained

- `--dry-run`: Preview changes without applying them
- `--project KEY`: Process specific project (KCBL, RMP, PSP, SMC)
- `--defect UNIQUE`: Process single defect (e.g., PSP-1)
- `--all`: Process all defects across all projects

## Product Auto-Detection

- **KCBL**: Uses fixed UUID `c1469eb7-97d1-4611-9e67-3fce1d0bb1ac`
- **PSP**: Searches by name "Kenya Police" or key "PSP"
- **SMC**: Searches by name "Sofia" or key "SMC"
- **RMP**: Uses default product UUID from config

## Special Features

✅ Auto-creates missing parent/child modules
✅ Smart cascading select field handling
✅ Transactional database updates
✅ Detailed change logging
✅ Error resilience (continues on errors)
✅ Project-specific banking type assignment

