# Submodules Sync Script - Command Cheat Sheet

## 🚀 Quick Start Commands

### Test Mode (Preview Only)
```bash
# Preview all changes
rails runner scripts/fix_submodules.rb --all --dry-run -e production
```

### PSP (Kenya Police Service)
```bash
# Dry run - preview changes
rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production

# Apply changes to all PSP defects
rails runner scripts/fix_submodules.rb --project PSP -e production

# Apply changes to single defect
rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production
rails runner scripts/fix_submodules.rb --project PSP --defect PSP-100 -e production
```

### SMC (Sofia Credit)
```bash
# Dry run - preview changes
rails runner scripts/fix_submodules.rb --project SMC --dry-run -e production

# Apply changes to all SMC defects
rails runner scripts/fix_submodules.rb --project SMC -e production

# Apply changes to single defect
rails runner scripts/fix_submodules.rb --project SMC --defect SMC-1 -e production
rails runner scripts/fix_submodules.rb --project SMC --defect SMC-5 -e production
```

### KCBL (Kenya Commercial Bank)
```bash
# Dry run - preview changes
rails runner scripts/fix_submodules.rb --project KCBL --dry-run -e production

# Apply changes to all KCBL defects
rails runner scripts/fix_submodules.rb --project KCBL -e production

# Apply changes to single defect
rails runner scripts/fix_submodules.rb --project KCBL --defect KCBL-1 -e production
rails runner scripts/fix_submodules.rb --project KCBL --defect KCBL-50 -e production
```

### RMP (Rafiki Mobile Platform)
```bash
# Dry run - preview changes
rails runner scripts/fix_submodules.rb --project RMP --dry-run -e production

# Apply changes to all RMP defects
rails runner scripts/fix_submodules.rb --project RMP -e production

# Apply changes to single defect
rails runner scripts/fix_submodules.rb --project RMP --defect RMP-1 -e production
rails runner scripts/fix_submodules.rb --project RMP --defect RMP-200 -e production
```

### All Projects
```bash
# Dry run - preview all changes across all projects
rails runner scripts/fix_submodules.rb --all --dry-run -e production

# Apply changes to all defects across all projects
rails runner scripts/fix_submodules.rb --all -e production
```

## 📋 Command Structure

```
rails runner scripts/fix_submodules.rb [OPTIONS] -e production
```

### Options

| Option | Value | Example | Description |
|--------|-------|---------|-------------|
| `--all` | (no value) | `--all` | Process all projects |
| `--project` | KEY | `--project PSP` | Process specific project (PSP/SMC/KCBL/RMP) |
| `--defect` | UNIQUE | `--defect PSP-1` | Process single defect |
| `--dry-run` | (no value) | `--dry-run` | Preview changes without applying |

## 🎯 Recommended Workflow

### 1️⃣ Test with Dry Run
```bash
rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production
```
Check the output to see what will be changed

### 2️⃣ Test Single Defect First
```bash
rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production
```
Apply to one defect to verify it works

### 3️⃣ Apply to Entire Project
```bash
rails runner scripts/fix_submodules.rb --project PSP -e production
```
Apply to all defects in the project

### 4️⃣ Verify Results
- Open Rails console and check defects
- View defects in UI to confirm modules are correct

## 📊 Output Reading Guide

### Success Indicator
```
[15:22:45]   PSP-1: Updating...
[15:22:45]     Old: Module='', Sub=''
[15:22:45]     New: Module='Authentication', Sub='Login Flow'
[15:22:45]     ✅ Updated successfully
```
✅ = Change was successfully applied

### Skipped Indicator
```
[15:22:45]   PSP-3: No change needed
```
⏭️ = Defect was skipped (already has correct values)

### Error Indicator
```
[15:22:45] ERROR processing PSP-50: Connection timeout
```
⚠️ = Something went wrong, check the error message

### Summary
```
[15:22:46] Project PSP Results:
[15:22:46]   Updated: 2, Skipped: 2, Errors: 0
```
Shows final count of changes

## 🔐 Production Safety Tips

1. **Always test first with `--dry-run`**
   ```bash
   rails runner scripts/fix_submodules.rb --project PSP --dry-run -e production
   ```

2. **Test single defect before bulk operation**
   ```bash
   rails runner scripts/fix_submodules.rb --project PSP --defect PSP-1 -e production
   ```

3. **Check database before and after**
   ```bash
   rails c production
   irb> Defect.where('defect_unique LIKE ?', 'PSP-%').map { |d| [d.defect_unique, d.qa_module&.name, d.submodule&.name] }.first(5)
   ```

4. **Run during off-peak hours for large operations**
   - Bulk operations might take time
   - Better to run when fewer users are using the system

5. **Keep logs for audit trail**
   ```bash
   # Capture output to file
   rails runner scripts/fix_submodules.rb --project PSP -e production > logs/psp_sync_$(date +%Y%m%d_%H%M%S).log
   ```

## 🆚 Comparison of Modes

| Aspect | Dry Run | Normal | Single Defect |
|--------|---------|--------|--------------|
| Database Changes | ❌ No | ✅ Yes | ✅ Yes |
| Scope | Project or All | Project or All | One defect |
| Best For | Preview | Actual update | Testing |
| Risk Level | 🟢 None | 🟡 Low | 🟢 None |
| Speed | ⚡ Fast | 🔄 Moderate | ⚡ Very Fast |

## 📞 Common Issues & Solutions

### Issue: "Custom fields not found"
```bash
# Check if project exists in JIRA
# Run dry-run with verbose logging
rails runner scripts/fix_submodules.rb --project SMC --dry-run -e production
```

### Issue: "Product not found"
```bash
# The script uses default UUID
# Check if product needs to be created or mapped differently
rails c production
irb> Product.where('document_name ILIKE ?', '%Sofia%')
```

### Issue: "JIRA API authentication failed"
```bash
# Check environment variables
echo $JIRA_API_TOKEN
echo $JIRA_API_USER

# Or check config file
cat config/jira_import.yml | grep -E 'api_user|api_token'
```

### Issue: Script seems stuck
```bash
# Kill the process (if running in background)
pkill -f "rails runner scripts/fix_submodules.rb"

# Check logs
tail -f log/production.log
```

## 📈 Performance Notes

- **Dry run**: ~1-2 seconds per defect
- **Normal run**: ~2-5 seconds per defect (includes JIRA API call)
- **100 defects**: ~3-8 minutes estimated
- **1000 defects**: ~30-80 minutes estimated

For large bulk operations, consider:
- Running during off-peak hours
- Running with `--all` to process all projects efficiently
- Checking logs periodically to monitor progress

## ✅ Success Checklist

After running the script:

- [ ] Ran dry-run first to preview changes
- [ ] Tested with single defect
- [ ] Applied to entire project
- [ ] Verified results in database
- [ ] Checked UI to confirm modules display correctly
- [ ] Reviewed final summary statistics
- [ ] Saved logs for audit trail

