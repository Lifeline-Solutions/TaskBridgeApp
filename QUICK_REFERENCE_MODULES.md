# Quick Reference - Module & Submodule Configuration

## Updated Projects

| Project | Module Name | Submodule | Command |
|---------|-------------|-----------|---------|
| **SJP** | `Modules SC Juza` | Empty | `rails runner scripts/fix_submodules.rb --project SJP -e production` |
| **KUP** | `Components (K-Unity)` | Empty | `rails runner scripts/fix_submodules.rb --project KUP -e production` |
| **GBCBS** | `Module` | Empty | `rails runner scripts/fix_submodules.rb --project GBCBS -e production` |
| **GBCBU2** | `Components` | Empty | `rails runner scripts/fix_submodules.rb --project GBCBU2 -e production` |

## Test First (Dry Run)

```bash
rails runner scripts/fix_submodules.rb --project SJP --dry-run -e production
rails runner scripts/fix_submodules.rb --project KUP --dry-run -e production
rails runner scripts/fix_submodules.rb --project GBCBS --dry-run -e production
rails runner scripts/fix_submodules.rb --project GBCBU2 --dry-run -e production
```

## Run Production

```bash
# Process SJP defects
rails runner scripts/fix_submodules.rb --project SJP -e production

# Process KUP defects
rails runner scripts/fix_submodules.rb --project KUP -e production

# Process GBCBS defects
rails runner scripts/fix_submodules.rb --project GBCBS -e production

# Process GBCBU2 defects
rails runner scripts/fix_submodules.rb --project GBCBU2 -e production
```

## Single Defect

```bash
# Process single SJP defect
rails runner scripts/fix_submodules.rb --defect SJP-52 -e production

# Process single KUP defect
rails runner scripts/fix_submodules.rb --defect KUP-123 -e production

# Process single GBCBS defect
rails runner scripts/fix_submodules.rb --defect GBCBS-456 -e production

# Process single GBCBU2 defect
rails runner scripts/fix_submodules.rb --defect GBCBU2-789 -e production
```

## All Projects at Once

```bash
rails runner scripts/fix_submodules.rb --all -e production
```

## Verify Results

```bash
rails c production

# Check SJP
Defect.where('defect_unique LIKE ?', 'SJP-%').includes(:qa_module).map { |d| [d.defect_unique, d.qa_module&.name] }

# Check KUP
Defect.where('defect_unique LIKE ?', 'KUP-%').includes(:qa_module).map { |d| [d.defect_unique, d.qa_module&.name] }

# Check GBCBS
Defect.where('defect_unique LIKE ?', 'GBCBS-%').includes(:qa_module).map { |d| [d.defect_unique, d.qa_module&.name] }

# Check GBCBU2
Defect.where('defect_unique LIKE ?', 'GBCBU2-%').includes(:qa_module).map { |d| [d.defect_unique, d.qa_module&.name] }
```

## What It Does

### SJP (Modules SC Juza)
- ✅ All SJP defects get module: `Modules SC Juza`
- ✅ No submodules (always empty)
- ✅ Automatic product detection from jira_key

### KUP (Components K-Unity)
- ✅ All KUP defects get module: `Components (K-Unity)`
- ✅ No submodules (always empty)
- ✅ Automatic product detection from jira_key

### GBCBS (Module)
- ✅ All GBCBS defects get module: `Module`
- ✅ No submodules (always empty)
- ✅ Automatic product detection from jira_key

### GBCBU2 (Components)
- ✅ All GBCBU2 defects get module: `Components`
- ✅ No submodules (always empty)
- ✅ Automatic product detection from jira_key

## Status

✅ **Ready to Run**

---

**Updated**: December 11, 2025

