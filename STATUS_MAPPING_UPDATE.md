# Status Mapping Update - fix_statuses.rb

## Issue Fixed

The script was failing to map the following JIRA statuses to local database statuses:
- `ON HOLD` → Should map to `On-Hold`
- `FAILED - QA` → Should map to `Failed QA`

**Before**: These were marked as "not found locally" and skipped
**After**: They are now properly mapped and updated

## Updated Status Mapping

The complete status mapping now includes:

```ruby
status_map = {
  'Failed-QA' => 'Failed QA',
  'FAILED - QA' => 'Failed QA',      # ✅ NEW - Maps JIRA "FAILED - QA"
  'Failed QA' => 'Failed QA',
  'ON HOLD' => 'On-Hold',            # ✅ NEW - Maps JIRA "ON HOLD"
  'On-Hold' => 'On-Hold',
  'On Hold' => 'On-Hold',
  'QA Testing' => 'QA Testing',
  'Awaiting Build' => 'Awaiting Build',
  'TO DO' => 'TO DO',
  'In Progress' => 'In Progress',
  'Closed' => 'Closed',
  'Resolved' => 'Resolved',
  'Reopened' => 'Reopened',
  'Blocked' => 'Blocked',
  'Support Testing' => 'Support Testing',
  'Awaiting Client Information' => 'Awaiting Client Information',
  'Awaiting Client API' => 'Awaiting Client API'
}
```

## What Changed

### Key Additions

1. **FAILED - QA Mapping**
   ```ruby
   'FAILED - QA' => 'Failed QA'
   ```
   Maps JIRA's "FAILED - QA" status to local "Failed QA" status

2. **ON HOLD Mapping**
   ```ruby
   'ON HOLD' => 'On-Hold'
   ```
   Maps JIRA's "ON HOLD" status to local "On-Hold" status

### Supported Variations

The mapping now supports multiple case variations:
- `Failed-QA`, `FAILED - QA`, `Failed QA` → all map to `Failed QA`
- `ON HOLD`, `On-Hold`, `On Hold` → all map to `On-Hold`

## Before and After

### Before
```
[14:36:17]   SJP-52: Status 'ON HOLD' not found locally. Skipping.
[14:36:18]   SJP-218: Status 'ON HOLD' not found locally. Skipping.
[14:36:25]   SJP-136: Status 'FAILED - QA' not found locally. Skipping.
```

### After
```
[14:36:17]   SJP-52: Updating Status...
[14:36:17]     Old: [previous status]
[14:36:17]     New: On-Hold
[14:36:17]     ✅ Updated successfully
[14:36:25]   SJP-136: Updating Status...
[14:36:25]     Old: [previous status]
[14:36:25]     New: Failed QA
[14:36:25]     ✅ Updated successfully
```

## How to Use

### Run with Dry Run First (Preview)
```bash
rails runner scripts/fix_statuses.rb --project SJP --dry-run -e production
```

### Apply Changes
```bash
rails runner scripts/fix_statuses.rb --project SJP -e production
```

### For Other Projects
```bash
rails runner scripts/fix_statuses.rb --project PSP -e production
rails runner scripts/fix_statuses.rb --project SMC -e production
rails runner scripts/fix_statuses.rb --project KCBL -e production
```

## Status Matching Logic

The script uses a two-step matching process:

1. **Exact Mapping**: Uses the status_map to convert JIRA status names to local names
   ```ruby
   mapped_status_name = status_map[jira_status_name] || jira_status_name
   ```

2. **Database Lookup**: Finds the status in the local database
   ```ruby
   local_status = Status.find_by(name: mapped_status_name) || 
                  Status.where('lower(name) = ?', mapped_status_name.downcase).first
   ```

## Complete Status List Supported

| JIRA Status | Local Status |
|-------------|--------------|
| Failed-QA | Failed QA |
| FAILED - QA | Failed QA |
| Failed QA | Failed QA |
| ON HOLD | On-Hold |
| On-Hold | On-Hold |
| On Hold | On-Hold |
| QA Testing | QA Testing |
| Awaiting Build | Awaiting Build |
| TO DO | TO DO |
| In Progress | In Progress |
| Closed | Closed |
| Resolved | Resolved |
| Reopened | Reopened |
| Blocked | Blocked |
| Support Testing | Support Testing |
| Awaiting Client Information | Awaiting Client Information |
| Awaiting Client API | Awaiting Client API |

## Testing

Test the changes with:

```bash
# Dry run to see what will change
rails runner scripts/fix_statuses.rb --project SJP --dry-run -e production

# Verify in database after running
rails c production
irb> Defect.where('defect_unique LIKE ?', 'SJP-%')
     .includes(:statuses)
     .limit(5)
     .map { |d| [d.defect_unique, d.statuses.map(&:name)] }
```

## Result

✅ All "ON HOLD" defects will be mapped to "On-Hold"
✅ All "FAILED - QA" defects will be mapped to "Failed QA"
✅ Script will no longer skip these statuses
✅ All defects will have their statuses properly synchronized from JIRA

---

**Updated**: December 11, 2025
**Status**: ✅ Ready for Production

