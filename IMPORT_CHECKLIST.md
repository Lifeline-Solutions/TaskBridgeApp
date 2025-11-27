# JIRA Import Implementation Checklist

## Pre-Import Preparation

### Database Setup
- [ ] Verify all reporter/assignee users exist in database
- [ ] Check that first_name and last_name fields are properly populated
- [ ] For dot-separated names (e.g., archana.verma), ensure database has matching first_name and last_name
- [ ] Review users with multi-part names (3+ parts) - verify first 2 parts match database
- [ ] Create any missing users before import

### Configuration
- [ ] Set `create_missing_users: true` or `false` in config/jira_import.yml
- [ ] Add manual user mappings if needed for known edge cases
- [ ] Verify DEFAULT_USER_UUID is set to a valid user
- [ ] Test Jira API credentials (JIRA_API_TOKEN)

### Testing
- [ ] Run: `rails runner scripts/test_user_matching.rb`
- [ ] Review output - all parsing tests should pass
- [ ] Verify that test users are found in database

## Import Phase

### Dry-Run
- [ ] Run: `rails runner scripts/import_jira_with_modules.rb --project PROJECTKEY --dry-run`
- [ ] Review the user match statistics report
- [ ] Check for fallback to default user - note which issues are affected
- [ ] Verify parsing strategies used (dot-separated, multi-part, etc.)
- [ ] If needed, create missing users and re-run dry-run

### Actual Import
- [ ] Run: `rails runner scripts/import_jira_with_modules.rb --project PROJECTKEY`
- [ ] Monitor for errors (check console output)
- [ ] Note the final user match statistics
- [ ] Identify any issues with fallback to default user

## Post-Import Verification

### Automated Verification
- [ ] Run: `rails runner scripts/verify_and_fix_user_assignments.rb`
- [ ] Review the verification report
- [ ] Check how many issues were auto-fixed
- [ ] Note any issues that couldn't be fixed

### Manual Review
- [ ] Query database for issues with default user assignment
- [ ] Sample check: pick 5 random issues and verify reporter/assignee match Jira
- [ ] Check attachment download status (from import report)
- [ ] Verify all labels were attached correctly

### Report Analysis
- [ ] Look for patterns in unmatched names
- [ ] Identify common name formats not handled well
- [ ] Check for case sensitivity issues
- [ ] Review any parsing strategy failures

## Troubleshooting (if needed)

### Unmatched Names
- [ ] Check exact spelling in both Jira and database
- [ ] For dot-separated: verify format is "first.last"
- [ ] For multi-part: verify first 2 parts match database
- [ ] Check for special characters or extra spaces
- [ ] Create missing users and re-run verification

### Fallback to Default
- [ ] Review which issues were affected
- [ ] Manually assign correct users if needed
- [ ] Or create missing users and run verification again

### Parsing Issues
- [ ] Check if names match expected formats
- [ ] Add custom parsing logic if needed (modify parse_jira_name function)
- [ ] Test changes with test_user_matching.rb
- [ ] Re-run import if changes were needed

## Final Cleanup

### Data Validation
- [ ] Verify total number of imported issues matches Jira count
- [ ] Check that no issues have nil reporter (except if Jira had none)
- [ ] Verify attachments are accessible (spot check a few)
- [ ] Confirm all comments were imported

### Documentation
- [ ] Document any custom name parsing added
- [ ] Note any manual fixes applied
- [ ] Record any issues with the import
- [ ] Update user mapping config for future imports

### Archive Results
- [ ] Save import reports to archive
- [ ] Document final statistics
- [ ] Create backup of changes
- [ ] Prepare rollback plan (if needed)

## Sign-Off

- [ ] Import completed successfully
- [ ] User assignments verified
- [ ] All issues accessible
- [ ] Attachments working
- [ ] Team notified of completion
- [ ] System ready for production use

---

## Checklist for Each Project Import

When importing multiple projects, repeat this checklist for each:

### Project: _________________

#### Pre-Import
- [ ] Database users exist
- [ ] Configuration updated
- [ ] Test parsing (if first time)

#### Import
- [ ] Dry-run passed
- [ ] Actual import ran
- [ ] Review final report

#### Post-Import
- [ ] Verification script run
- [ ] Issues reviewed
- [ ] Manual fixes applied (if any)

#### Sign-Off
- [ ] Ready for production
- [ ] Team notified

---

## Common Issues Quick Reference

| Issue | Cause | Solution |
|-------|-------|----------|
| Name falls back to default | User doesn't exist | Create user in database |
| Dot-separated not matching | Wrong database format | Ensure first_name and last_name are separate |
| Multi-part name fails | Using wrong parts | Verify first 2 parts match database |
| Case sensitivity | Case mismatch | Check database consistency |
| Email not matching | Extra spaces or domain issue | Verify exact email match |

## Useful Commands

```bash
# Test name parsing
rails runner scripts/test_user_matching.rb

# Dry-run import
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run --verbose

# Actual import
rails runner scripts/import_jira_with_modules.rb --project KCBL

# Verify and fix assignments
rails runner scripts/verify_and_fix_user_assignments.rb

# Check for issues with default user
rails c
> Defect.joins(:users).where(users: { id: 'default-user-id' }).count

# Find issues with nil assignee
rails c
> Defect.where('NOT EXISTS (SELECT 1 FROM defect_users WHERE defect_id = defects.id)').count
```

## Notes

- All matching is **case-insensitive**
- Email matching takes priority over name matching
- Multi-part names use **first 2 parts only**
- Dot-separated format: **"first.last"**
- Default user assignment is **tracked and reported**
- Verification script can **auto-fix** most mismatches

---

**Status**: Ready for implementation

**Last Updated**: November 27, 2025

**Next Review**: After first project import

