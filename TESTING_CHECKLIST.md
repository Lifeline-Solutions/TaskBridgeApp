# Testing Checklist: Description Validation Implementation

## Pre-Deployment Testing

### Code Quality
- [x] Syntax validation passed
- [x] No undefined variables or method calls
- [x] Proper error handling implemented
- [x] Logging statements in place
- [x] Comments explain complex logic
- [x] Backward compatible (no breaking changes)

### Functionality Testing

#### 1. Content Extraction Tests
**To verify**: All content types are properly extracted

- [ ] **Paragraphs**: Plain text paragraphs extracted correctly
  ```
  Expected: "This is a paragraph"
  ```

- [ ] **Headings**: Converted to markdown format
  ```
  Expected: "# Heading 1", "## Heading 2", "### Heading 3"
  ```

- [ ] **Bullet Lists**: Extracted with bullet points
  ```
  Expected:
  • Item 1
  • Item 2
  • Item 3
  ```

- [ ] **Ordered Lists**: Extracted with numbers
  ```
  Expected:
  1. First
  2. Second
  3. Third
  ```

- [ ] **Tables**: Extracted with pipe delimiters
  ```
  Expected:
  [Table]
  Column1 | Column2
  Value1  | Value2
  [/Table]
  ```

- [ ] **Code Blocks**: Extracted with language marker
  ```
  Expected:
  ```ruby
  def hello
    puts "world"
  end
  ```
  ```

- [ ] **Block Quotes**: Extracted with > prefix
  ```
  Expected:
  > This is a quote
  > Multi-line quote
  ```

- [ ] **Mixed Content**: Issue with multiple content types
  ```
  Expected: All types extracted in correct order
  ```

#### 2. Description Validation Tests
**To verify**: Descriptions are compared correctly

- [ ] **No change detected**: Same description skipped
  ```
  Action: Run import on same project twice
  Expected: Second run shows "Skipped" for descriptions
  ```

- [ ] **Change detected**: Different description updated
  ```
  Action: Manually update description in Jira, re-run import
  Expected: Updated count increases, old content replaced
  ```

- [ ] **Whitespace ignored**: Extra spaces don't trigger update
  ```
  DB: "hello world"
  Jira: "  hello    world  "
  Expected: Skipped (normalized forms identical)
  ```

- [ ] **Case sensitive**: Different case triggers update
  ```
  DB: "hello world"
  Jira: "Hello World"
  Expected: Updated (different normalized forms)
  ```

#### 3. Integration Tests
**To verify**: Description validation integrates correctly

- [ ] **Repair pass runs**: After comments, attachments, labels, history
  ```
  Action: Run full import
  Expected: Output shows "Validating and updating descriptions..."
  ```

- [ ] **Stats reported**: Checked/Updated/Skipped/Errors counts shown
  ```
  Expected output:
    - Checked: 185
    - Updated: 12
    - Skipped (no changes): 173
    - Errors: 0
  ```

- [ ] **No conflicts**: Description update doesn't interfere with other repairs
  ```
  Action: Run import with all content types
  Expected: All repairs complete successfully
  ```

### Database Testing

- [ ] **Data integrity**: No descriptions corrupted
  ```
  Check: Sample defects have readable, complete descriptions
  ```

- [ ] **No orphans**: All defects have descriptions (or none if expected)
  ```
  Check: No NULL descriptions created unintentionally
  ```

- [ ] **Encoding correct**: Special characters preserved
  ```
  Check: Unicode, accents, symbols all display correctly
  ```

### Logging and Reporting Tests

- [ ] **Verbose output**: With `--verbose` flag shows detailed logs
  ```
  Command: rails runner scripts/import_jira_with_modules.rb --project TEST --verbose | grep DESCRIPTION
  Expected: Multiple DESCRIPTION-* log lines
  ```

- [ ] **Error logging**: Errors clearly reported
  ```
  Check: Any errors show [DESCRIPTION-ERROR] prefix
  ```

- [ ] **Summary reporting**: Stats displayed at end
  ```
  Expected: Final output shows repair pass statistics
  ```

### Edge Cases

- [ ] **Empty description**: Jira has no description
  ```
  Expected: Empty/nil handled gracefully, no errors
  ```

- [ ] **Very large description**: 50+ KB description
  ```
  Expected: Extracted completely, no truncation
  ```

- [ ] **Complex table**: Multi-row, multi-column table
  ```
  Expected: All cells preserved, structure intact
  ```

- [ ] **Nested lists**: Bullet lists inside numbered lists
  ```
  Expected: Proper hierarchy maintained
  ```

- [ ] **Malformed ADF**: Jira returns invalid structure
  ```
  Expected: Graceful error handling, logged appropriately
  ```

### Performance Testing

- [ ] **Single issue**: < 500ms extraction and comparison
  ```
  Command: rails runner scripts/import_jira_with_modules.rb --project SINGLE_ISSUE --verbose
  Expected: Completes in < 2 seconds
  ```

- [ ] **Batch (100 issues)**: < 30 seconds total
  ```
  Command: rails runner scripts/import_jira_with_modules.rb --project MEDIUM --verbose
  Expected: Completes in < 1 minute
  ```

- [ ] **Large batch (1000 issues)**: < 5 minutes total
  ```
  Command: rails runner scripts/import_jira_with_modules.rb --project LARGE --verbose
  Expected: Completes in < 10 minutes
  ```

### Regression Testing

- [ ] **Existing functionality unchanged**: All other import features work
  ```
  Check:
  - Comments imported correctly
  - Attachments downloaded
  - Labels attached
  - History entries created
  - Users matched properly
  ```

- [ ] **Database constraints**: No integrity violations
  ```
  Check: Run import, verify no DB errors in logs
  ```

- [ ] **Rollback safe**: Can rollback changes if needed
  ```
  Action: Run import, revert descriptions to NULL, re-run
  Expected: Works correctly second time
  ```

## Deployment Testing

### Pre-Production Testing
- [ ] Run on test/staging database
- [ ] Test with representative sample from production
- [ ] Verify backup exists before deployment
- [ ] Test rollback procedure

### Production Readiness
- [ ] All tests pass
- [ ] Documentation complete
- [ ] Team aware of changes
- [ ] Monitoring configured for errors
- [ ] Backup created before deployment

## Post-Deployment Verification

### Day 1 Monitoring
- [ ] Monitor error logs for new errors
- [ ] Check description samples in UI
- [ ] Verify import runs without issues
- [ ] Check repair pass statistics

### Week 1 Monitoring
- [ ] Run import 2-3 times, verify consistency
- [ ] Sample random defects, check description quality
- [ ] Verify no data corruption occurred
- [ ] Get user feedback on description quality

### Ongoing
- [ ] Monitor import duration (should be similar or faster)
- [ ] Check error rates (should remain at 0)
- [ ] Periodically verify description content
- [ ] Keep documentation up to date

## Test Report Template

```
Date: YYYY-MM-DD
Tester: [Name]
Environment: [Dev/Staging/Production]

Overall Result: [PASS/FAIL]

Test Results:
- Content Extraction: [PASS/FAIL] [Notes if FAIL]
- Description Validation: [PASS/FAIL] [Notes if FAIL]
- Integration: [PASS/FAIL] [Notes if FAIL]
- Database: [PASS/FAIL] [Notes if FAIL]
- Logging: [PASS/FAIL] [Notes if FAIL]
- Edge Cases: [PASS/FAIL] [Notes if FAIL]
- Performance: [PASS/FAIL] [Notes if FAIL]
- Regression: [PASS/FAIL] [Notes if FAIL]

Issues Found:
1. [Issue] - Severity: [High/Medium/Low]
2. ...

Recommendations:
- ...

Sign-off: [Tester Name/Date]
```

## Success Criteria

✅ All tests pass
✅ No regressions detected
✅ Performance acceptable
✅ Error rate = 0
✅ Description content verified correct
✅ Team agreement to deploy

## Failure Criteria

❌ Syntax errors
❌ Content extraction incorrect
❌ Database corruption
❌ Existing functionality broken
❌ Performance significantly degraded
❌ Error rate > 1%

## Quick Command Reference for Testing

```bash
# Syntax check
ruby -c scripts/import_jira_with_modules.rb

# Dry run (test without saving)
rails runner scripts/import_jira_with_modules.rb --project TEST --dry-run

# Verbose run (see all details)
rails runner scripts/import_jira_with_modules.rb --project TEST --verbose

# Monitor logs
tail -f log/development.log | grep DESCRIPTION

# Check for errors
tail log/development.log | grep ERROR

# View specific issue description
rails console
Defect.find_by(defect_unique: "TEST-123").content
```

---

**Version**: 1.0
**Created**: 2025-11-28
**Last Updated**: 2025-11-28

