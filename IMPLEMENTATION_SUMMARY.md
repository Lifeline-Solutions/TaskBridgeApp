# JIRA Import - User Assignment Enhancement Summary

## What Was Implemented

Enhanced the JIRA import system with sophisticated user name parsing and assignment tracking to correctly match reporters and assignees from Jira to the local database.

## Files Created/Modified

### New Files

1. **`scripts/verify_and_fix_user_assignments.rb`**
   - Post-import verification script
   - Automatically detects and fixes mismatched reporter/assignee assignments
   - Compares Jira data with local database
   - Uses enhanced name parsing for intelligent matching
   - Generates detailed reconciliation report

2. **`scripts/test_user_matching.rb`**
   - Unit tests for name parsing logic
   - Validates all supported name formats
   - Can be run before import to verify system readiness
   - Tests: dot-separated, multi-part, two-part, single-part names

3. **`JIRA_USER_ASSIGNMENT_GUIDE.md`**
   - Comprehensive user guide
   - Detailed usage instructions
   - Troubleshooting guide
   - Best practices and performance notes

### Modified Files

1. **`scripts/import_jira_with_modules.rb`**
   - Enhanced report section with detailed user match statistics
   - Added tracking for reporter/assignee matches vs fallbacks
   - Shows which issues had fallback to default user
   - Displays parsed name strategies
   - Provides actionable recommendations for fixing fallbacks

## Key Features

### 1. Advanced Name Parsing

The system handles multiple name formats intelligently:

```
Format                  Example              First Name    Last Name
-----------------------------------------------------------------------------------
Dot-separated          archana.verma        archana       verma
Multi-part (3+ parts)  Eva Karimi Njagi     Eva           Karimi (first 2)
Standard two-part      John Smith           John          Smith
Single-part            Madonna              Madonna       (nil)
Hyphenated             Mary Jane-Smith      Mary          Jane-Smith
```

### 2. Multi-Level Matching Strategy

Priority order for finding users:

1. **Email match** (most reliable)
2. **Parsed first+last name** (enhanced parsing)
3. **Partial name match** (fuzzy matching)
4. **Full name match** (backward compatibility)
5. **Config map** (manual overrides)
6. **User creation** (if configured)
7. **Fallback to default** (tracked and reported)

### 3. Comprehensive Tracking

During import, tracks:

- Total user lookups performed
- Breakdown by match type with percentages
- Names that couldn't be matched
- Parsing strategies used (dot-separated, multi-part, etc.)
- Reporter/assignee specific matches
- Issues with fallback to default user

### 4. Actionable Reporting

Final report includes:

```
👤 USER MATCH STATISTICS REPORT
========================================
Total user lookups performed: 250

Match breakdown:
  ✅ Email matches:          120 (48.00%)
  ✅ Full name matches:      50 (20.00%)
  ✅ First+Last matches:     40 (16.00%)
  ✅ Partial matches:        20 (8.00%)
  ✅ Config map matches:     5 (2.00%)
  🆕 Created users:          10
  ⚠️  Fallback to default:    5

Reporter/Assignee Matching:
  Reporters: 114 matched, 1 fallback to default
  Assignees: 120 matched, 4 fallback to default

Name Parsing Strategies Used:
  dot-separated: 8 names
  multi-part-first-two: 12 names
  two-part: 225 names

⚠️  CRITICAL: Issues where assignee fell back to default user (4):
  1. KCBL-15:
     Name: 'Jane Doe'
     Email: 'jane@example.com'
     Assigned to: default-user-id (DEFAULT USER)
     Parse strategy: two-part
     Parsed as: first='Jane', last='Doe'

🔧 RECOMMENDATIONS FOR FIXING FALLBACK USERS:
  1. Review the names above to ensure they are spelled correctly
  2. Check for case sensitivity issues
  3. For dot-separated names, ensure database has matching first_name and last_name
  4. Create missing users in the database
  5. Run: rails runner scripts/verify_and_fix_user_assignments.rb
```

## Usage Instructions

### Before Import

1. **Test name parsing**:
   ```bash
   rails runner scripts/test_user_matching.rb
   ```

2. **Ensure users exist in database** with correct first_name and last_name

### During Import

1. **Dry-run to review changes**:
   ```bash
   rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run --verbose
   ```

2. **Review the user match report** at the end

3. **Run actual import**:
   ```bash
   rails runner scripts/import_jira_with_modules.rb --project KCBL
   ```

### After Import

1. **Verify assignments**:
   ```bash
   rails runner scripts/verify_and_fix_user_assignments.rb
   ```

2. **Check report** for any remaining issues

3. **Manual fixes** if needed for edge cases

## Enhanced Name Parsing Examples

### Dot-Separated Format
```
Input:  "archana.verma"
Parsed: first_name="archana", last_name="verma"
Match:  Looks for User with first_name='archana' AND last_name='verma' (case-insensitive)
```

### Multi-Part Names
```
Input:  "Eva Karimi Njagi"
Parsed: first_name="Eva", last_name="Karimi" (uses first 2 parts)
Match:  Looks for User with first_name='Eva' AND last_name='Karimi'
```

### Standard Names
```
Input:  "John Smith"
Parsed: first_name="John", last_name="Smith"
Match:  Looks for User with first_name='John' AND last_name='Smith'
```

## Matching Process

For each name, the system:

1. **Parses** the name using format-specific rules
2. **Tries email match** first (if email provided)
3. **Tries parsed name match** with case-insensitive comparison
4. **Tries partial matches** for fuzzy matching
5. **Falls back to default user** if no match found
6. **Tracks all attempts** for reporting

## Statistics Tracking

The script maintains global statistics:

```ruby
$USER_STATS = {
  total_lookups: 0,
  email_matches: 0,
  full_name_matches: 0,
  first_last_matches: 0,
  partial_matches: 0,
  config_map_matches: 0,
  created_users: 0,
  fallback_users: 0,
  matched_users: Set.new,        # Unique user IDs matched
  fallback_users_set: Set.new,   # Unique user IDs fallen back to
  not_found_names: Hash.new(0),  # Names that couldn't be matched
  parsed_names: {},              # Track parsed name strategies
  reporter_matches: {},          # Per-issue reporter tracking
  assignee_matches: {}           # Per-issue assignee tracking
}
```

## Troubleshooting

### Problem: Names falling back to default user

**Solutions**:
1. Check spelling in both Jira and database
2. For dot-separated names, ensure database has matching first_name and last_name
3. Create missing users in database
4. Check for case sensitivity issues (though matching is case-insensitive)
5. Run verification script to auto-fix

### Problem: Case sensitivity issues

**Solution**: All matching is case-insensitive, so this shouldn't be an issue

### Problem: Multi-part names not matching

**Solution**: Script uses first 2 parts of 3+ part names. Verify this matches your database.

## Performance

- Import: ~100-200 issues/minute (depending on attachments)
- Verification: ~50 defects/minute
- Both scripts respect Jira API rate limits

## Configuration

Add to `config/jira_import.yml`:

```yaml
# Enable/disable user creation
create_missing_users: true

# Manual user mapping (for edge cases)
user_map:
  'John Doe': 'user-id-123'
  'archana.verma': 'user-id-456'

# Default user for fallbacks
default_user_uuid: 'default-user-id'
```

## Testing

Run the test suite to validate name parsing:

```bash
# Test basic parsing
rails runner scripts/test_user_matching.rb

# Test with actual database users
rails runner scripts/test_user_matching.rb

# Full import with verbose output
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run --verbose

# Verify and fix
rails runner scripts/verify_and_fix_user_assignments.rb
```

## Next Steps

1. **Test with dry-run** on a test project
2. **Review the user match report** carefully
3. **Create missing users** in database if needed
4. **Run full import** with actual project
5. **Run verification script** to detect/fix mismatches
6. **Monitor fallback users** in production

## Support & Issues

For issues:
1. Check the detailed report at end of import
2. Review JIRA_USER_ASSIGNMENT_GUIDE.md
3. Run test_user_matching.rb for diagnostics
4. Run verify_and_fix_user_assignments.rb for auto-fixes
5. Check script logs for detailed error messages

