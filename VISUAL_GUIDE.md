# Submodules Sync - Visual Guide

## 🎯 Project Modules Overview

### SMC (Sofia Credit) - Components - Sofia Credit
```
Jira Fields:
  ├─ Module Field: customfield_10500 (Components - Sofia Credit)
  └─ Submodule Field: customfield_10501 (Sofia Modules_Submodules)

Database Structure:
  Components - Sofia Credit (Parent Module)
    └─ Sofia Modules_Submodules (Child Module/Submodule)
```

### PSP (Kenya Police Service) - Kenya Police Modules
```
Jira Fields:
  ├─ Module Field: customfield_10164 (Kenya Police Modules)
  └─ Submodule Field: customfield_10163 (Kenya Police Modules / Sub-Modules)

Database Structure:
  Kenya Police Modules (Parent Module)
    └─ [Example: Authentication] (Child Module/Submodule)
        ├─ Login Flow
        ├─ Password Reset
        └─ Token Management
```

### KCBL (Kenya Commercial Bank) - KCBL Modules
```
Jira Fields:
  ├─ Module Field: customfield_xxxx (KCBL Modules)
  └─ Submodule Field: customfield_xxxx (KCBL Modules / Submodules)

Database Structure:
  KCBL Modules (Parent Module)
    └─ [Example: Core Banking] (Child Module/Submodule)
        ├─ Account Management
        ├─ Transactions
        └─ Reporting

Special Features:
  ✓ Banking Type: Core Banking (auto-assigned)
  ✓ Product ID: c1469eb7-97d1-4611-9e67-3fce1d0bb1ac
```

### RMP (Rafiki Mobile Platform) - Rafiki Modules
```
Jira Fields:
  ├─ Module Field: customfield_xxxx (Rafiki Modules)
  └─ Submodule Field: customfield_xxxx (Rafiki Modules / Sub-Modules)

Database Structure:
  Rafiki Modules (Parent Module)
    └─ [Example: Mobile] (Child Module/Submodule)
        ├─ UI Components
        ├─ API Integration
        └─ Data Sync
```

## 📊 Command Decision Tree

```
START
  │
  ├─ Want to preview changes?
  │  └─ YES → Add --dry-run flag
  │
  ├─ What to process?
  │  │
  │  ├─ Single Defect?
  │  │  └─ rails runner scripts/fix_submodules.rb --project [PSP/SMC/etc] --defect [PSP-1] -e production
  │  │
  │  ├─ Entire Project?
  │  │  └─ rails runner scripts/fix_submodules.rb --project [PSP/SMC/etc] -e production
  │  │
  │  └─ All Projects?
  │     └─ rails runner scripts/fix_submodules.rb --all -e production
  │
  └─ Add --dry-run for preview
     └─ rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production
```

## 🔄 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         JIRA                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Defect: PSP-1                                             │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ customfield_10164: Kenya Police Modules                   │  │
│  │ customfield_10163: Login Flow                             │  │
│  └───────────────────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ API Call
                             │ fetch_from_jira(PSP-1)
                             │
                             ▼
         ┌───────────────────────────────────────────────┐
         │   extract_custom_field_value()                │
         │   ├─ Module: "Kenya Police Modules"           │
         │   └─ Submodule: "Login Flow"                  │
         └───────────────┬───────────────────────────────┘
                         │
                         │ Validate & Parse
                         │
                         ▼
         ┌───────────────────────────────────────────────┐
         │  parse_module_and_submodule()                 │
         │  └─ Clean and normalize names                 │
         └───────────────┬───────────────────────────────┘
                         │
                         │ Check if needs update
                         │
                         ▼
         ┌───────────────────────────────────────────────┐
         │  find_or_create_modules()                     │
         │  ├─ Find/Create Parent: "Kenya Police..."    │
         │  └─ Find/Create Child: "Login Flow"          │
         └───────────────┬───────────────────────────────┘
                         │
                         │ Save to DB
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DATABASE                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Defect: PSP-1                                             │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ qa_module_id: [Parent Module ID]                          │  │
│  │ submodule_id: [Child Module ID]                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ QA Module: Kenya Police Modules                           │  │
│  │ ├─ id: xxx                                                │  │
│  │ ├─ name: Kenya Police Modules                             │  │
│  │ └─ children:                                              │  │
│  │    └─ QA Module: Login Flow                               │  │
│  │       ├─ id: yyy                                          │  │
│  │       ├─ name: Login Flow                                 │  │
│  │       └─ parent_id: xxx                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## 📈 Processing Timeline

```
Timeline for 10 Defects:

Time  | Event
------|-------────────────────────────────────────────────
0s    | Script starts
1s    | Discover custom fields from JIRA
2s    | Get list of 10 defects
3s    | ├─ Defect 1: Fetch from JIRA ............ 25% ✅
5s    | ├─ Defect 2: Fetch from JIRA ............ 50% ✅
7s    | ├─ Defect 3: Fetch from JIRA ............ 75% ✅
9s    | ├─ Defect 4: Fetch from JIRA ............ 100% ⏭️
10s   | ├─ Defect 5: Fetch from JIRA ............ 100% ✅
12s   | ├─ Defect 6: Fetch from JIRA ............ 100% ❌
14s   | ├─ Defect 7: Fetch from JIRA ............ 100% ⏭️
16s   | ├─ Defect 8: Fetch from JIRA ............ 100% ✅
18s   | ├─ Defect 9: Fetch from JIRA ............ 100% ✅
20s   | └─ Defect 10: Fetch from JIRA ........... 100% ✅
22s   | Summary: Updated: 7, Skipped: 2, Errors: 1
23s   | Script complete
```

## 🎨 Status Indicators

| Symbol | Meaning | Description |
|--------|---------|-------------|
| ✅ | Updated | Successfully updated the defect |
| ⏭️ | Skipped | No changes needed (already correct) |
| ❌ | Error | Something went wrong |
| 🔄 | Processing | Currently fetching from JIRA |
| 📋 | Preview | Dry run mode (no changes applied) |

## 🗂️ File Organization

```
/home/abol-ger/Desktop/Projects/tasker/CSPM/
│
├── scripts/
│   └── fix_submodules.rb .............. Main script (UPDATED)
│
├── Documentation/
│   ├── COMMAND_CHEAT_SHEET.md ......... Quick commands reference
│   ├── SUBMODULES_SYNC_GUIDE.md ....... Detailed guide
│   ├── SUBMODULES_QUICK_REFERENCE.md .. Quick lookup
│   ├── SUBMODULES_IMPLEMENTATION.md ... Technical details
│   └── IMPLEMENTATION_COMPLETE.md ..... This implementation summary
│
└── logs/ (created during execution)
    ├── psp_sync_20251211_150000.log
    ├── smc_sync_20251211_150005.log
    └── ...
```

## 🚀 Quick Start Sequence

### For First Time Users
```
1. READ: COMMAND_CHEAT_SHEET.md
   └─ Understand basic commands

2. RUN: Dry run on single defect
   └─ rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 --dry-run -e production

3. READ: Output carefully
   └─ Check what would be changed

4. RUN: Actual single defect
   └─ rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production

5. VERIFY: In database or UI
   └─ Check if modules were created correctly

6. RUN: Dry run for entire project
   └─ rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production

7. RUN: Full project update
   └─ rails runner scripts/fix_submodules.rb --project PSP -e production

8. REPEAT: For other projects (SMC, KCBL, RMP)
   └─ Follow same process
```

## 💡 Pro Tips

### Tip 1: Monitor Large Operations
```bash
# Keep log file while running
tail -f log/production.log &
rails runner scripts/fix_submodules.rb --all -e production
```

### Tip 2: Batch Process with Delays
```bash
# Run one project at a time
for project in PSP SMC KCBL RMP; do
  echo "Processing $project..."
  rails runner scripts/fix_submodules.rb --project $project -e production
  sleep 5
done
```

### Tip 3: Save Logs for Audit
```bash
# Capture output with timestamp
rails runner scripts/fix_submodules.rb --project PSP -e production \
  | tee log/psp_sync_$(date +%Y%m%d_%H%M%S).log
```

### Tip 4: Check Results After
```bash
# Verify in Rails console
rails c production
irb> Defect.where('defect_unique LIKE ?', 'PSP-%')
     .limit(5)
     .map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }
```

---

**Version**: 1.0
**Last Updated**: December 11, 2025
**Status**: ✅ Ready for Production

