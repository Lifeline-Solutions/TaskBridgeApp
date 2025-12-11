# Module & Submodule Configuration Update - fix_submodules.rb

## Summary

Updated `fix_submodules.rb` script to properly handle four new project types with fixed module names and no submodules:
- **SJP** → Module: `Modules SC Juza` | Submodule: `(empty)`
- **KUP** → Module: `Components (K-Unity)` | Submodule: `(empty)`
- **GBCBS** → Module: `Module` | Submodule: `(empty)`
- **GBCBU2** → Module: `Components` | Submodule: `(empty)`

## What Changed

### 1. Field Discovery Logic (Lines 65-145)

Added new `when` cases for each project:

**SJP Project**
```ruby
when 'SJP'
  if name.include?('modules') && name.include?('sc juza')
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field = 'SKIP' # Skip submodule for SJP
```

**KUP Project**
```ruby
when 'KUP'
  if name.include?('components') && (name.include?('k-unity') || name.include?('kunity'))
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field = 'SKIP' # Skip submodule for KUP
```

**GBCBS Project**
```ruby
when 'GBCBS'
  if name == 'module'
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field = 'SKIP' # Skip submodule for GBCBS
```

**GBCBU2 Project**
```ruby
when 'GBCBU2'
  if name == 'components' || name.include?('components ')
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field = 'SKIP' # Skip submodule for GBCBU2
```

### 2. Defect Processing Logic (Lines 340-365)

Added logic to set fixed module names for special projects:

```ruby
# For projects with no submodules, clear submodule_name
case project_key.upcase
when 'SJP'
  module_name = 'Modules SC Juza'
  submodule_name = '' # Always blank for SJP
when 'KUP'
  module_name = 'Components (K-Unity)'
  submodule_name = '' # Always blank for KUP
when 'GBCBS'
  module_name = 'Module'
  submodule_name = '' # Always blank for GBCBS
when 'GBCBU2'
  module_name = 'Components'
  submodule_name = '' # Always blank for GBCBU2
else
  # For other projects, apply normal parsing logic
```

### 3. Product ID Resolution (Lines 395-423)

Added automatic product ID detection for new projects:

```ruby
when 'SJP'
  unless product_id
    sjp_product = Product.where('jira_key ILIKE ?', '%SJP%').first
    product_id = sjp_product&.id
  end
when 'KUP'
  unless product_id
    kup_product = Product.where('jira_key ILIKE ?', '%KUP%').first
    product_id = kup_product&.id
  end
when 'GBCBS'
  unless product_id
    gbcbs_product = Product.where('jira_key ILIKE ?', '%GBCBS%').first
    product_id = gbcbs_product&.id
  end
when 'GBCBU2'
  unless product_id
    gbcbu2_product = Product.where('jira_key ILIKE ?', '%GBCBU2%').first
    product_id = gbcbu2_product&.id
  end
```

## How It Works

### For SJP Defects (SJP-1, SJP-52, etc.)
1. Script discovers the module field from JIRA
2. Regardless of JIRA value, sets module to `Modules SC Juza`
3. Always sets submodule to empty
4. Finds or creates the QaModule
5. Updates defect with the correct module

### For KUP Defects (KUP-1, KUP-123, etc.)
1. Script discovers the components field from JIRA
2. Regardless of JIRA value, sets module to `Components (K-Unity)`
3. Always sets submodule to empty
4. Finds or creates the QaModule
5. Updates defect with the correct module

### For GBCBS Defects (GBCBS-1, GBCBS-456, etc.)
1. Script discovers the module field from JIRA
2. Regardless of JIRA value, sets module to `Module`
3. Always sets submodule to empty
4. Finds or creates the QaModule
5. Updates defect with the correct module

### For GBCBU2 Defects (GBCBU2-1, GBCBU2-789, etc.)
1. Script discovers the components field from JIRA
2. Regardless of JIRA value, sets module to `Components`
3. Always sets submodule to empty
4. Finds or creates the QaModule
5. Updates defect with the correct module

## Usage

### Process All SJP Defects
```bash
rails runner scripts/fix_submodules.rb --project SJP -e production
```

### Process All KUP Defects
```bash
rails runner scripts/fix_submodules.rb --project KUP -e production
```

### Process All GBCBS Defects
```bash
rails runner scripts/fix_submodules.rb --project GBCBS -e production
```

### Process All GBCBU2 Defects
```bash
rails runner scripts/fix_submodules.rb --project GBCBU2 -e production
```

### Test (Dry Run)
```bash
rails runner scripts/fix_submodules.rb --project SJP --dry-run -e production
```

### Process Single Defect
```bash
rails runner scripts/fix_submodules.rb --defect SJP-52 -e production
```

### Process All Projects
```bash
rails runner scripts/fix_submodules.rb --all -e production
```

## Module Structure Created

After running the script, the following QaModule structure will be created:

### SJP Module Structure
```
Parent Module: Modules SC Juza
├── No submodules
└── All defects assigned to parent
```

### KUP Module Structure
```
Parent Module: Components (K-Unity)
├── No submodules
└── All defects assigned to parent
```

### GBCBS Module Structure
```
Parent Module: Module
├── No submodules
└── All defects assigned to parent
```

### GBCBU2 Module Structure
```
Parent Module: Components
├── No submodules
└── All defects assigned to parent
```

## Existing Projects (No Changes)

The following projects remain unchanged with their full module/submodule structure:
- **RMP** → Rafiki Modules / Rafiki Modules - Sub Modules
- **KCBL** → KCBL Modules / KCBL Modules/Submodules
- **PSP** → Kenya Police Modules / Kenya Police Modules / Sub Modules
- **SMC** → Components - Sofia Credit / Sofia Modules_Submodules

## Expected Output

### Dry Run Example
```
[14:25:00] Starting submodule fix script (Dry Run: true)
[14:25:00] Processing project: SJP
[14:25:00] Setting up Modules SC Juza...
[14:25:00]   Creating parent module: Modules SC Juza for product [UUID]
[14:25:00] Discovered fields - Module: customfield_XXXX, Submodule: SKIP
[14:25:00] Found 52 defect(s) to check.
[14:25:00]   SJP-52: Updating...
[14:25:00]     Old: Module='[previous]', Sub='[previous]'
[14:25:00]     New: Module='Modules SC Juza', Sub=''
[14:25:00] Project SJP Results:
[14:25:00]   Updated: 52, Skipped: 0, Errors: 0
```

### Actual Run
```
[14:25:00]   SJP-52: Updating...
[14:25:00]     Old: Module='[previous]', Sub='[previous]'
[14:25:00]     New: Module='Modules SC Juza', Sub=''
[14:25:00]     ✅ Updated successfully
```

## Verification

After running the script:

```bash
rails c production

# Check SJP modules
Defect.where('defect_unique LIKE ?', 'SJP-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }

# Check KUP modules
Defect.where('defect_unique LIKE ?', 'KUP-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }

# Check GBCBS modules
Defect.where('defect_unique LIKE ?', 'GBCBS-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }

# Check GBCBU2 modules
Defect.where('defect_unique LIKE ?', 'GBCBU2-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
```

Expected output:
```ruby
[["SJP-52", "Modules SC Juza", nil],
 ["SJP-136", "Modules SC Juza", nil],
 ["SJP-245", "Modules SC Juza", nil]]

[["KUP-10", "Components (K-Unity)", nil],
 ["KUP-20", "Components (K-Unity)", nil]]

[["GBCBS-5", "Module", nil],
 ["GBCBS-10", "Module", nil]]

[["GBCBU2-1", "Components", nil],
 ["GBCBU2-2", "Components", nil]]
```

## Files Updated

- `/home/abol-ger/Desktop/Projects/tasker/CSPM/scripts/fix_submodules.rb`

## Status

✅ **Complete and Production Ready**

The script now properly handles:
- ✅ SJP project with fixed module name
- ✅ KUP project with fixed module name
- ✅ GBCBS project with fixed module name
- ✅ GBCBU2 project with fixed module name
- ✅ Automatic product ID detection for all projects
- ✅ Backward compatibility with existing projects (RMP, KCBL, PSP, SMC)

---

**Updated**: December 11, 2025
**Status**: ✅ Production Ready

