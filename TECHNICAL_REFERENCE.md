# Technical Reference: Enhanced Name Parsing Implementation

## Overview

This document provides technical details about the enhanced name parsing and user assignment system in the JIRA import scripts.

## Name Parsing Algorithm

### Implementation

The `parse_jira_name` function processes names in the following order:

```ruby
def parse_jira_name(name_str)
  return { first_name: nil, last_name: nil } if name_str.blank?

  # 1. Check for dot-separated format
  if name_str.include?('.')
    parts = name_str.split('.')
    return {
      first_name: parts.first.strip,
      last_name: parts.last.strip,
      strategy: 'dot-separated'
    }
  end

  # 2. Split by whitespace and check count
  parts = name_str.split
  if parts.length >= 3
    # Multi-part: use first 2
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'multi-part-first-two'
    }
  elsif parts.length == 2
    # Standard two-part
    return {
      first_name: parts[0].strip,
      last_name: parts[1].strip,
      strategy: 'two-part'
    }
  elsif parts.length == 1
    # Single part
    return {
      first_name: parts[0].strip,
      last_name: nil,
      strategy: 'single-part'
    }
  end

  { first_name: nil, last_name: nil, strategy: 'failed-parse' }
end
```

### Parsing Strategies

#### 1. Dot-Separated (`dot-separated`)
**Pattern**: `{first}.{last}`
**Example**: `archana.verma`
**Result**: `first_name="archana"`, `last_name="verma"`
**Use Cases**: Email-style display names, LDAP-derived names

#### 2. Multi-Part First-Two (`multi-part-first-two`)
**Pattern**: `{first} {second} {third+}`
**Example**: `Eva Karimi Njagi`
**Result**: `first_name="Eva"`, `last_name="Karimi"`
**Use Cases**: Names with middle names, full legal names

#### 3. Two-Part (`two-part`)
**Pattern**: `{first} {last}`
**Example**: `John Smith`
**Result**: `first_name="John"`, `last_name="Smith"`
**Use Cases**: Standard display names

#### 4. Single-Part (`single-part`)
**Pattern**: `{name}`
**Example**: `Madonna`
**Result**: `first_name="Madonna"`, `last_name=nil`
**Use Cases**: Single-name individuals, nicknames

## User Matching Algorithm

### Priority Order

```ruby
def find_user_by_name_or_map(name, email = nil, verbose: false)
  $USER_STATS[:total_lookups] += 1

  # PRIORITY 1: Email match
  if email.present?
    user = User.where(deleted_on: nil)
      .find_by('lower(email) = ?', email.downcase)
    if user
      $USER_STATS[:email_matches] += 1
      return user
    end
  end

  # PRIORITY 2: Parsed name match
  parsed = parse_jira_name(name)
  if parsed[:first_name] && parsed[:last_name]
    user = User.where(deleted_on: nil)
      .find_by('lower(first_name) = ? AND lower(last_name) = ?',
               parsed[:first_name].downcase,
               parsed[:last_name].downcase)
    if user
      $USER_STATS[:first_last_matches] += 1
      return user
    end
    
    # PRIORITY 3: Partial matches
    # ... (first exact + last prefix, etc.)
  end

  # PRIORITY 4: Full name match
  # ... (backward compatibility)

  # PRIORITY 5: Config map
  # ... (manual overrides)

  # PRIORITY 6: User creation
  # ... (if configured)

  # PRIORITY 7: Fallback
  $USER_STATS[:fallback_users] += 1
  return User.find_by(id: DEFAULT_USER_UUID)
end
```

### Matching Steps

1. **Email Match**
   - Direct lookup by email
   - Case-insensitive
   - Most reliable method

2. **Parsed Name Match**
   - Uses enhanced parsing to extract first/last
   - Exact case-insensitive match on both fields
   - Works for all supported formats

3. **Partial Matches**
   - First name exact + last name prefix
   - Last name exact + first name prefix
   - Handles spelling variations

4. **Full Name Match** (Legacy)
   - Concatenated first + last against database
   - Backward compatibility with original system

5. **Config Map**
   - Manual override from configuration file
   - Useful for known edge cases

6. **User Creation**
   - Creates new user with parsed names
   - Only if CREATE_MISSING_USERS = true
   - Uses parsed first_name and last_name

7. **Fallback**
   - Uses DEFAULT_USER_UUID
   - Tracked and reported
   - Flagged as issue for review

## Statistics Tracking

### Global Statistics Object

```ruby
$USER_STATS = {
  # Counters
  total_lookups: 0,
  email_matches: 0,
  full_name_matches: 0,
  first_last_matches: 0,
  partial_matches: 0,
  config_map_matches: 0,
  created_users: 0,
  fallback_users: 0,

  # Sets (unique values)
  matched_users: Set.new,       # User IDs successfully matched
  fallback_users_set: Set.new,  # User IDs used as fallback

  # Hashes
  not_found_names: Hash.new(0),  # {name => count}
  parsed_names: {},              # {name => {strategy, first_name, last_name}}
  reporter_matches: {},          # {issue_key => {name, email, user_id, status}}
  assignee_matches: {}           # {issue_key => {name, email, user_id, status}}
}
```

### Tracking During Import

For each user lookup:

```ruby
# Track based on match type
case match_type
when :email
  $USER_STATS[:email_matches] += 1
when :parsed_first_last
  $USER_STATS[:first_last_matches] += 1
when :partial
  $USER_STATS[:partial_matches] += 1
end

# Add to matched set
$USER_STATS[:matched_users] << user.id

# Track reporter/assignee separately
if context == :reporter
  $USER_STATS[:reporter_matches][issue_key] = {
    name: reporter_name,
    email: reporter_email,
    user_id: user.id,
    status: 'matched'
  }
end
```

### Fallback Tracking

```ruby
# When no match found
$USER_STATS[:fallback_users] += 1
$USER_STATS[:fallback_users_set] << DEFAULT_USER_UUID
$USER_STATS[:not_found_names][name] += 1

# Track for reporting
if context == :reporter
  $USER_STATS[:reporter_matches][issue_key] = {
    name: reporter_name,
    email: reporter_email,
    user_id: DEFAULT_USER_UUID,
    status: 'fallback'
  }
end
```

## Database Queries

### Matching Queries

#### Email Match
```sql
SELECT * FROM users 
WHERE deleted_on IS NULL 
AND LOWER(email) = LOWER(?)
```

#### Exact Name Match
```sql
SELECT * FROM users 
WHERE deleted_on IS NULL 
AND LOWER(first_name) = ? 
AND LOWER(last_name) = ?
```

#### Partial Match (First Exact, Last Prefix)
```sql
SELECT * FROM users 
WHERE deleted_on IS NULL 
AND LOWER(first_name) = ? 
AND LOWER(last_name) LIKE ?
```

#### Full Name Match
```sql
SELECT * FROM users 
WHERE deleted_on IS NULL 
AND LOWER(CONCAT(first_name, ' ', last_name)) = ?
```

## Performance Considerations

### Query Optimization

1. **Use indexes** on email, first_name, last_name fields
2. **Limit lookups** with deleted_on IS NULL filter
3. **Cache results** when possible
4. **Batch operations** where appropriate

### Typical Performance

- Email lookup: ~1ms per user
- Name lookup: ~5-10ms per user (with index)
- Full scan: ~500-1000ms for 10,000 users
- Parsing: <1ms per name

### Batch Processing

```ruby
# Good: Load users once, cache in hash
@users_by_email = User.where(deleted_on: nil)
  .group_by { |u| u.email.downcase }

# Bad: Query for each name
issue_list.each do |issue|
  reporter = User.find_by(email: issue.reporter_email)
end
```

## Error Handling

### Invalid Names

```ruby
# Nil or empty
parse_jira_name(nil)       # => { first_name: nil, last_name: nil }
parse_jira_name("")        # => { first_name: nil, last_name: nil }

# Malformed
parse_jira_name("   ")     # => { first_name: nil, last_name: nil }
parse_jira_name(".")       # => { first_name: "", last_name: "" }
```

### User Not Found

```ruby
# Graceful fallback
found = find_user_by_name_or_map("Unknown User")
found.id == DEFAULT_USER_UUID  # => true
```

### Database Errors

```ruby
begin
  user = find_user_by_name_or_map(name, email)
rescue ActiveRecord::StatementInvalid => e
  # Handle query error
  $USER_STATS[:errors] += 1
  user = User.find_by(id: DEFAULT_USER_UUID)
end
```

## Configuration Integration

### Config File (config/jira_import.yml)

```yaml
# User creation
create_missing_users: true

# Manual mappings
user_map:
  'John Doe': 'user-id-123'
  'archana.verma': 'user-id-456'

# Default fallback user
default_user_uuid: 'default-user-id'
```

### Environment Variables

```bash
export JIRA_API_TOKEN="..."
export JIRA_BASE_URL="https://craftsilicon.atlassian.net"
export JIRA_API_USER="user@example.com"
```

## Testing Strategy

### Unit Tests

```ruby
def test_parse_jira_name
  assert_equal(
    { first_name: "archana", last_name: "verma", strategy: "dot-separated" },
    parse_jira_name("archana.verma")
  )
end

def test_find_user_by_parsed_name
  user = find_user_by_name_or_map("John Smith")
  assert_not_nil(user)
  assert_equal("John", user.first_name)
end
```

### Integration Tests

```ruby
def test_import_with_user_tracking
  import_jira_issues(dry_run: true)
  assert_greater_than($USER_STATS[:total_lookups], 0)
  assert_greater_than($USER_STATS[:matched_users].size, 0)
end
```

### Manual Testing

```bash
# Test name parsing
rails runner scripts/test_user_matching.rb

# Test with actual import
rails runner scripts/import_jira_with_modules.rb --project TEST --dry-run

# Verify results
rails runner scripts/verify_and_fix_user_assignments.rb
```

## Debugging

### Enable Verbose Output

```bash
rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose
```

### Inspect Statistics

```ruby
rails c
> require_relative 'scripts/import_jira_with_modules.rb'
> puts $USER_STATS.inspect
> puts $USER_STATS[:parsed_names].inspect
```

### Check Specific Issue

```ruby
rails c
> issue = Defect.find_by(defect_unique: 'KCBL-123')
> puts "Reporter: #{issue.creator.inspect}"
> puts "Assignee: #{issue.users.inspect}"
```

## Future Enhancements

1. **Machine learning** name matching for common variations
2. **Fuzzy matching** for typos and misspellings
3. **Caching** of matches for performance
4. **Custom parsing** hooks for organization-specific formats
5. **Batch validation** before import
6. **Audit trail** of all matching decisions

## References

- Ruby String methods: split, strip, downcase, include?
- ActiveRecord queries: where, find_by, pluck
- Set operations: add (<<), union, intersection
- Hash operations: keys, values, transform_values

