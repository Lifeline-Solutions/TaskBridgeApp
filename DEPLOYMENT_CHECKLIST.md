# Deployment Checklist - Import Script Fix

## ✅ Issue Resolved
- **Error**: `NoMethodError: undefined method 'import_issue_with_modules' for main`
- **Cause**: Missing function definition in script
- **Status**: **FIXED** ✅

## 📋 Pre-Deployment Validation

### 1. Syntax Validation
```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM
ruby -c scripts/import_jira_with_modules.rb
```
**Expected**: `Syntax OK`
**Status**: ✅ PASSED

### 2. Function Existence Check
```bash
grep "def import_issue_with_modules" scripts/import_jira_with_modules.rb
```
**Expected**: Function definition found
**Status**: ✅ PASSED (Found at line 1956)

### 3. Integration Check
```bash
grep "import_issue_with_modules(issue" scripts/import_jira_with_modules.rb | wc -l
```
**Expected**: At least 1 call to the function
**Status**: ✅ READY

## 🚀 Deployment Steps

### Step 1: Test on Development
```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM

# Dry run to verify script loads without errors
rails runner scripts/import_jira_with_modules.rb --project PSP --dry-run --verbose

# Expected output:
# - No errors
# - "Processing issue" messages
# - "Would process Defect" messages in verbose mode
```

### Step 2: Run Actual Test Import (Staging)
```bash
# If you have a staging environment, test there first
rails runner scripts/import_jira_with_modules.rb --project PSP --verbose

# Monitor:
# - Import progress output
# - Defects created/updated count
# - Any error messages
```

### Step 3: Production Deployment
```bash
# Update the deployed code
cd /home/deploy/CSPM/releases/[CURRENT_RELEASE]/
# Ensure scripts/import_jira_with_modules.rb has the fix

# Run the import on production
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose

# Monitor logs
tail -f log/production.log | grep -E "(Processing|created|updated|ERROR)"
```

## 📊 Verification Checklist

- [ ] **Syntax Check**: `ruby -c scripts/import_jira_with_modules.rb` passes
- [ ] **Function Exists**: `grep "def import_issue_with_modules"` finds the function
- [ ] **Dry Run Succeeds**: No errors, processes issues in dry-run mode
- [ ] **Test Import Works**: Creates/updates defects successfully
- [ ] **Logs Clean**: No ERROR entries in logs
- [ ] **Defects Visible**: Check database for imported defects
- [ ] **Attachments Work**: Files are attached correctly
- [ ] **Comments Imported**: Comments and conversations present
- [ ] **Labels Applied**: Issue labels correctly assigned
- [ ] **Descriptions Present**: Content captured from Jira

## 🔍 Post-Deployment Verification

### Check 1: Verify Defects Imported
```bash
rails console
Defect.where('updated_at >= ?', 1.day.ago).count
# Should show number of recently imported defects
```

### Check 2: Check Sample Defect
```bash
Defect.find_by(defect_unique: 'KCBL-1')
# Should show full defect with content, assignee, status
```

### Check 3: Verify Attachments
```bash
Defect.find_by(defect_unique: 'KCBL-1').attachments.count
# Should show number of attached files (if any)
```

### Check 4: Check Comments
```bash
Defect.find_by(defect_unique: 'KCBL-1').defect_messages.count
# Should show imported comments
```

### Check 5: Monitor Error Logs
```bash
grep ERROR log/production.log | tail -20
# Should be empty or only show non-critical warnings
```

## 🚨 Rollback Plan

If issues occur:

### Option 1: Quick Rollback
```bash
# Revert to previous release (if using Capistrano)
cap production deploy:rollback
```

### Option 2: Restore Database
```bash
# Restore from backup if data integrity issues
pg_restore -d cspm_production /path/to/backup.sql
```

### Option 3: Fix and Redeploy
```bash
# Make corrections to script
# Re-run deployment
cap production deploy
```

## 📝 Documentation References

- **Quick Start**: See `DESCRIPTION_VALIDATION_QUICK_REF.md`
- **Technical Details**: See `DESCRIPTION_VALIDATION_IMPLEMENTATION.md`
- **Testing Guide**: See `TESTING_CHECKLIST.md`
- **Examples**: See `EXAMPLES_DESCRIPTION_VALIDATION.md`

## 🎯 Success Criteria

The deployment is successful when:

1. ✅ Script runs without `NoMethodError`
2. ✅ Issues are imported from Jira
3. ✅ Defects appear in database with all related data
4. ✅ No critical errors in logs
5. ✅ Sample defects can be viewed in the application
6. ✅ Attachments, comments, and labels are accessible

## 📞 Support Contacts

- **Script Issues**: Check `FIX_SUMMARY.md`
- **Database Issues**: Check deployment logs
- **Import Failures**: Review verbose output
- **Error Tracking**: Check Sentry or error logs

## ✅ Final Sign-Off

- [ ] All syntax checks passed
- [ ] Function properly defined and integrated
- [ ] Dry-run successful
- [ ] Test import successful
- [ ] Post-deployment verification complete
- [ ] Documentation reviewed
- [ ] Team approved deployment
- [ ] Ready for production

---

**Deployment Date**: _____________
**Deployed By**: _____________
**Verified By**: _____________
**Notes**: _______________________________________________

---

**Status**: 🟢 **READY FOR DEPLOYMENT**
**Last Updated**: 2025-11-28

