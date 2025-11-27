# JIRA Import Script - Enhanced User Name Parsing & Tracking

## Overview

The enhanced `import_jira_with_modules.rb` script now includes sophisticated user name parsing, comprehensive tracking of reporter/assignee matching, and detailed reporting of user match statistics.

## Key Features Added

### 1. Enhanced Name Parsing (`parse_jira_name` function)

Handles multiple name formats from Jira:

#### Strategy 1: Dot-Separated Names
- **Format**: `archana.verma`, `sarah.syuki`
- **Parsing**: Split by dot
- **Result**: first_name = "archana", last_name = "verma"

#### Strategy 2: Multi-Part Names (3+ parts)
- **Format**: `Eva Karimi Njagi`, `Brian Wafula Kariuki`
- **Parsing**: Uses first two parts
- **Result**: first_name = "Eva", last_name = "Karimi"
- **Rationale**: Handles cases where actual surname is in the 2nd position

#### Strategy 3: Standard Two-Part Names
- **Format**: `John Smith`, `David Ger`
- **Parsing**: Split on whitespace, first part is first_name, rest is last_name
- **Result**: first_name = "John", last_name = "Smith"

#### Strategy 4: Single Part Names
- **Format**: `simon`
- **Parsing**: Used as first_name only
- **Result**: first_name = "simon", last_name = nil

### 2. Intelligent User Matching

The `find_user_by_name_or_map` function now:

1. **Email-based matching** (most reliable)
   - Direct email lookup in User table
   - Case-insensitive comparison

2. **Parsed name matching**
   - Uses output from `parse_jira_name` for intelligent matching
   - Tries exact first+last name match
   - Falls back to partial matching (prefix matches)

3. **Full name matching** (backward compatible)
   - Tries concatenated first+last name match
   - Standard first+last token matching

4. **Config map fallback**
   - Allows manual overrides via config file
   - Both exact and lowercase key matching

5. **User creation**
   - Creates new users if configured
   - Uses parsed names for better accuracy
   - Sets email as primary identifier

6. **Default user fallback**
   - Uses configured DEFAULT_USER_UUID if all matching fails
   - Tracks these fallback instances

### 3. Comprehensive User Tracking

#### Global Statistics (`$USER_STATS`)

Tracks:
- Total user lookups performed
- Breakdown by match type:
  - Email matches
  - Full name matches
  - First+Last name matches
  - Partial matches
  - Config map matches
  - Created users
  - Fallback to default user

- Unique matched users (Set)
- Unique fallback uses (Set)
- Names that couldn't be matched (Hash with counts)
- Parsing strategies used (Hash)
- Per-issue reporter matches
- Per-issue assignee matches

### 4. Enhanced Reporter/Assignee Assignment

Now tracks:
- Each reporter and assignee resolution
- Match status ('matched' or 'fallback')
- User ID assigned
- Jira name and email
- Match type (reporter or assignee)

### 5. Final Detailed Report

At the end of the import, generates comprehensive report showing:

#### User Match Summary
```
✅ Email matches:          X (Y%)
✅ Full name matches:      X (Y%)
✅ First+Last matches:     X (Y%)
✅ Partial matches:        X
✅ Config map matches:     X
🆕 Created users:          X
⚠️  Fallback to default:    X
```

#### Name Parsing Strategies
- Shows which parsing strategies were used
- Lists specific examples of dot-separated names parsed
- Lists specific examples of multi-part names parsed

#### Issues with Fallback Users
- Reporter fallbacks: Shows which issues and user names
- Assignee fallbacks: Shows which issues and user names

#### Not Found Names
- Lists names that couldn't be matched
- Shows occurrence count for each

## Usage Examples

### Basic Import with Dry-Run
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run
```

### Import Multiple Projects with Verbose Output
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL,PSP,FLOW --verbose
```

### Full Import (Commit Changes)
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL
```

### Import with Custom Date Range
```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --days 90
```

## Test & Validation Scripts

### Test Name Parsing
```bash
ruby scripts/test_user_name_parsing.rb
```

Demonstrates the parsing logic with various name formats.

### Validate User Parsing in Rails Console
```bash
rails runner scripts/validate_user_parsing.rb
```

Checks if parsed names match existing users in the database.

## Configuration

Edit `config/jira_import.yml`:

```yaml
# User creation settings
create_missing_users: true              # Auto-create users if not found

# User mapping overrides (optional)
user_map:
  "john.smith": "uuid-of-john"
  "archana.verma": "uuid-of-archana"

# Default fallback
default_user_uuid: "uuid-of-default-user"
```

## Interpreting the Final Report

### Perfect Import
```
✅ All matches successful
  - Few fallbacks
  - Most users matched by email or parsed name
```

### Issues Found
```
⚠️  Some fallbacks to default user
  - Check the "Issues with fallback users" section
  - May indicate:
    - User doesn't exist in system
    - Email doesn't match Jira
    - Name parsing didn't work
```

### Action Items
1. Review not-found names
2. Add missing users to the system
3. Update name mappings in config if needed
4. Re-run import

## Advanced Features

### Duplicate User Handling

For names appearing multiple times in Jira:
- Tracks each unique name parsed
- Groups by parsing strategy
- Shows which names need duplicate user resolution

### Email-Based Resolution

Even if names don't match, script tries email:
- Extracts email from Jira displayName if available
- Most reliable way to match existing users
- Avoids creating duplicate users

### Multi-Pass Matching

1st Pass: Try email match
2nd Pass: Try parsed name match
3rd Pass: Try full name match
4th Pass: Try config map
5th Pass: Create new user (if configured)
6th Pass: Use default fallback

## Troubleshooting

### Names Not Parsing Correctly

Check `parse_jira_name` function:
```ruby
$USER_STATS[:parsed_names]  # Shows how each name was parsed
```

### Too Many Fallbacks

Review:
```ruby
$USER_STATS[:not_found_names]  # Names that couldn't be matched
$USER_STATS[:fallback_users_set]  # Set of fallback user IDs
```

### Duplicate Users for Same Person

Check:
```ruby
$USER_STATS[:reporter_matches]  # Which user was assigned to each issue
$USER_STATS[:assignee_matches]  # Same for assignees
```

## Performance Notes

- Email-based matching is fastest
- Name matching requires case-insensitive LIKE queries
- For 1000+ issues, expect 5-10 minutes
- Dry-run mode only differs in not saving to DB

## Future Improvements

Possible enhancements:
1. Fuzzy name matching for typos
2. ML-based name parsing
3. Historical user mapping learning
4. Batch user creation from Jira users list
5. Email domain verification

## Related Files

- `scripts/import_jira_with_modules.rb` - Main import script
- `scripts/test_user_name_parsing.rb` - Test name parsing
- `scripts/validate_user_parsing.rb` - Validate against DB
- `config/jira_import.yml` - Configuration file

## Support

For issues or questions:
1. Run with `--verbose` flag for detailed logging
2. Check the final statistics report
3. Review not-found names list
4. Validate parsing with test scripts

