# ✅ FINAL UPDATE - Module Configuration Script

## Summary

Updated `fix_submodules.rb` to execute **all projects the same way**, following the KCBL and RMP pattern. All projects now use the same field discovery and processing logic.

## What Changed

### Previous Issue
- SJP, KUP, GBCBS, GBCBU2 used 'SKIP' for submodule fields
- Different validation logic than KCBL/RMP

### New Implementation
- **All projects now use 'DUMMY' instead of 'SKIP'**
- **Same validation and field discovery pattern for all projects**
- **Consistent JIRA field fetching logic**

## Key Changes Made

### 1. Field Discovery (Lines 110-178)
Now all projects follow the same pattern:

```ruby
when 'SJP'
  if name.include?('modules') && name.include?('sc juza')
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  # For SJP, we'll set a dummy submodule field to pass validation
  # The actual submodule value will be ignored in processing
  submodule_field ||= 'DUMMY'

when 'KUP'
  if name.include?('components') && (name.include?('k-unity') || name.include?('kunity') || name.include?('k unity'))
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field ||= 'DUMMY'

when 'GBCBS'
  if name == 'module' || (name.include?('module') && !name.include?('submodule'))
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field ||= 'DUMMY'

when 'GBCBU2'
  if name == 'components' || (name == 'component')
    module_field = field_id
    log "✓ Matched Module field: #{field['name']} (#{field_id})"
  end
  submodule_field ||= 'DUMMY'
```

### 2. JIRA Field Fetching (Lines 347-349)
Added safe handling for 'DUMMY' submodule fields:

```ruby
raw_module = fields[module_field]
# Only fetch submodule from JIRA if it's a real field (not 'DUMMY')
raw_submodule = (submodule_field && submodule_field != 'DUMMY') ? fields[submodule_field] : nil

module_name = extract_custom_field_value(raw_module)
submodule_name = extract_custom_field_value(raw_submodule)
```

### 3. Module Name Override (Lines 352-367)
Consistent with all other projects:

```ruby
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
  # For other projects (RMP, KCBL, PSP, SMC), apply parsing logic
```

## How All Projects Work Now

### Execution Pattern (Same for All)

1. **Field Discovery**
   - Script discovers custom field IDs from JIRA
   - For projects without submodules, sets `submodule_field = 'DUMMY'`
   - Passes validation check: `module_field && submodule_field`

2. **JIRA API Fetch**
   - Fetches issue data from JIRA
   - For `module_field`: Retrieves actual value from JIRA
   - For `submodule_field == 'DUMMY'`: Sets to `nil`, doesn't query JIRA

3. **Module Name Processing**
   - For SJP/KUP/GBCBS/GBCBU2: Overrides with fixed module name
   - For RMP/KCBL/PSP/SMC: Uses value from JIRA with parsing

4. **Module Creation/Update**
   - Finds or creates QaModule with the correct name
   - Updates defect with module and submodule IDs
   - Logs all changes for verification

### Comparison: Before vs After

#### Before (Inconsistent)
```
KCBL: module_field + submodule_field (real fields)
RMP: module_field + submodule_field (real fields)
SJP: module_field + 'SKIP'  ❌ Different validation
KUP: module_field + 'SKIP'  ❌ Different validation
```

#### After (Consistent) ✅
```
KCBL: module_field + submodule_field (real fields)
RMP: module_field + submodule_field (real fields)
SJP: module_field + 'DUMMY' ✅ Same validation pattern
KUP: module_field + 'DUMMY' ✅ Same validation pattern
GBCBS: module_field + 'DUMMY' ✅ Same validation pattern
GBCBU2: module_field + 'DUMMY' ✅ Same validation pattern
```

## Project Configuration Table

| Project | Module Field | Submodule Field | Module Name | Submodule |
|---------|--------------|-----------------|-------------|-----------|
| **RMP** | Rafiki Modules | Rafiki Modules/Sub Modules | From JIRA | From JIRA |
| **KCBL** | KCBL Modules | KCBL Modules/Submodules | From JIRA | From JIRA |
| **PSP** | Kenya Police Modules | Kenya Police Modules/Sub Modules | From JIRA | From JIRA |
| **SMC** | Components - Sofia Credit | Sofia Modules_Submodules | From JIRA | From JIRA |
| **SJP** | Modules SC Juza | 'DUMMY' | `Modules SC Juza` | Empty |
| **KUP** | Components (K-Unity) | 'DUMMY' | `Components (K-Unity)` | Empty |
| **GBCBS** | Module | 'DUMMY' | `Module` | Empty |
| **GBCBU2** | Components | 'DUMMY' | `Components` | Empty |

## Usage (Same for All)

```bash
# Test any project (dry run)
rails runner scripts/fix_submodules.rb --project SJP --dry-run -e production
rails runner scripts/fix_submodules.rb --project KUP --dry-run -e production
rails runner scripts/fix_submodules.rb --project GBCBS --dry-run -e production
rails runner scripts/fix_submodules.rb --project GBCBU2 --dry-run -e production

# Run production
rails runner scripts/fix_submodules.rb --project SJP -e production
rails runner scripts/fix_submodules.rb --project KUP -e production
rails runner scripts/fix_submodules.rb --project GBCBS -e production
rails runner scripts/fix_submodules.rb --project GBCBU2 -e production

# Process all projects at once
rails runner scripts/fix_submodules.rb --all -e production

# Process single defect
rails runner scripts/fix_submodules.rb --defect SJP-52 -e production
rails runner scripts/fix_submodules.rb --defect KUP-123 -e production
```

## Expected Output (Same for All)

```
[14:25:00] Starting submodule fix script (Dry Run: true)
[14:25:00] Processing project: SJP
[14:25:00] Projects to process: SJP
[14:25:00] ================================================================================
[14:25:00] Processing project: SJP
[14:25:00] ================================================================================
[14:25:00] Found field: modules sc juza (customfield_10050)
[14:25:00] ✓ Matched Module field: Modules SC Juza (customfield_10050)
[14:25:00] Discovered fields - Module: customfield_10050, Submodule: DUMMY
[14:25:00] Found 52 defect(s) to check.
[14:25:00]   SJP-52: Updating...
[14:25:00]     Old: Module='null', Sub='null'
[14:25:00]     New: Module='Modules SC Juza', Sub=''
[14:25:00]   SJP-136: Updating...
[14:25:00]     Old: Module='Old Value', Sub='null'
[14:25:00]     New: Module='Modules SC Juza', Sub=''
[14:25:00] 
[14:25:00] Project SJP Results:
[14:25:00]   Updated: 52, Skipped: 0, Errors: 0
[14:25:00] 
[14:25:00] ================================================================================
[14:25:00] Script completed!
[14:25:00] ================================================================================
```

## Verification (Same for All)

```bash
rails c production

# Verify SJP
Defect.where('defect_unique LIKE ?', 'SJP-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
# Expected: [["SJP-52", "Modules SC Juza", nil], ...]

# Verify KUP
Defect.where('defect_unique LIKE ?', 'KUP-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
# Expected: [["KUP-10", "Components (K-Unity)", nil], ...]

# Verify GBCBS
Defect.where('defect_unique LIKE ?', 'GBCBS-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
# Expected: [["GBCBS-5", "Module", nil], ...]

# Verify GBCBU2
Defect.where('defect_unique LIKE ?', 'GBCBU2-%')
  .includes(:qa_module, :submodule)
  .limit(5)
  .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
# Expected: [["GBCBU2-1", "Components", nil], ...]
```

## Benefits of This Approach

✅ **Consistent Validation**
- All projects pass the same validation: `module_field && submodule_field`
- No special cases in validation logic

✅ **Consistent Field Discovery**
- All projects follow the same pattern
- Easy to add new projects

✅ **Consistent JIRA Fetching**
- All projects use the same JIRA API calls
- Safe handling of 'DUMMY' fields

✅ **Consistent Processing**
- All projects go through the same processing pipeline
- Same logging, error handling, and statistics

✅ **Easy to Maintain**
- One pattern for all projects
- Easy to understand and debug

## Status

✅ **Complete and Production Ready**

The script now executes **all projects the same way** with:
- ✅ Consistent field discovery pattern
- ✅ Same validation logic
- ✅ Same JIRA API fetching
- ✅ Same processing pipeline
- ✅ Same logging and error handling

---

**Updated**: December 11, 2025
**Status**: ✅ Production Ready
**Pattern**: All projects execute the same way (like KCBL and RMP)

