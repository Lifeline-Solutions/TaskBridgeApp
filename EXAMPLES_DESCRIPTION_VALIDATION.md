# Examples: Description Validation in Action

## Real-World Scenarios

### Scenario 1: Table in Description

**In Jira** (as viewed):
```
| Feature | Status | Priority |
|---------|--------|----------|
| Login   | Done   | High     |
| Profile | In Progress | Medium |
| Settings| Todo   | Low      |
```

**Jira ADF Format** (what the API returns):
```json
{
  "type": "table",
  "content": [
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Feature"}]}]
        },
        {
          "type": "tableCell",
          "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Status"}]}]
        }
      ]
    }
  ]
}
```

**In Database** (after extraction):
```
[Table]
Feature | Status | Priority
Login   | Done   | High
Profile | In Progress | Medium
Settings | Todo   | Low
[/Table]
```

**Import Log**:
```
[DESCRIPTION-VALIDATE] KCBL-456: new_len=89, existing_len=0
[DESCRIPTION-UPDATE] KCBL-456: Updated description (89 chars)
  Updated: [Table]
Feature | Status | Priority
...
```

---

### Scenario 2: Bullet List with Sub-items

**In Jira**:
```
Requirements:
• User authentication
  • Support OAuth
  • Support LDAP
  • Support local login
• User profile
  • Display preferences
  • Edit profile
• Settings management
```

**Extracted**:
```
Requirements:
• User authentication
• Support OAuth
• Support LDAP
• Support local login
• User profile
• Display preferences
• Edit profile
• Settings management
```

**Note**: Nesting is flattened in current implementation (bullet list items)

---

### Scenario 3: Code Block

**In Jira**:
```python
def get_user(user_id):
    user = User.find(user_id)
    if user.active:
        return user.to_dict()
    return None
```

**Extracted**:
```
```python
def get_user(user_id):
    user = User.find(user_id)
    if user.active:
        return user.to_dict()
    return None
```
```

---

### Scenario 4: Mixed Content (Most Common)

**In Jira**:
```
## Overview

This feature implements user authentication for the platform.

## Requirements

• Support OAuth 2.0
• Support local username/password
• Implement refresh tokens
• Add multi-factor authentication

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| /auth/login | POST | Authenticate user |
| /auth/refresh | POST | Refresh token |
| /auth/logout | POST | Logout user |

## Implementation Notes

> This is a security-critical feature. All code must be reviewed by the security team.

### Code Example

```python
@app.route('/auth/login', methods=['POST'])
def login():
    username = request.json.get('username')
    password = request.json.get('password')
    # Implementation here
```
```

**Extracted (in database)**:
```
## Overview

This feature implements user authentication for the platform.

## Requirements

• Support OAuth 2.0
• Support local username/password
• Implement refresh tokens
• Add multi-factor authentication

## API Endpoints

[Table]
Endpoint | Method | Description
/auth/login | POST | Authenticate user
/auth/refresh | POST | Refresh token
/auth/logout | POST | Logout user
[/Table]

## Implementation Notes

> This is a security-critical feature. All code must be reviewed by the security team.

### Code Example

```python
@app.route('/auth/login', methods=['POST'])
def login():
    username = request.json.get('username')
    password = request.json.get('password')
    # Implementation here
```
```

---

## Update Scenarios

### Update Case 1: Content Actually Changed

**First Import**:
```
DB: (empty)
JIRA: "This is the description"
Result: UPDATE
```

Log Output:
```
[DESCRIPTION-UPDATE] KCBL-123: Updated description (27 chars)
  Updated: This is the description
```

**Second Import** (no change in Jira):
```
DB: "This is the description"
JIRA: "This is the description"
Result: SKIP
```

Log Output:
```
[DESCRIPTION-SKIP] KCBL-123: Description unchanged
```

**Third Import** (Jira changed):
```
DB: "This is the description"
JIRA: "This is the NEW description"
Result: UPDATE
```

Log Output:
```
[DESCRIPTION-UPDATE] KCBL-123: Updated description (27 chars)
  Previous: This is the description
  Updated: This is the NEW description
```

---

### Update Case 2: Whitespace Differences (Ignored)

```
DB: "hello world"
JIRA ADF extracts to: "  hello   world  " (extra spaces from formatting)
Normalized comparison: 
  - DB normalized: "hello world"
  - JIRA normalized: "hello world"
Result: SKIP (no actual change)
```

---

### Update Case 3: Case Differences (Detected)

```
DB: "hello world"
JIRA ADF extracts to: "Hello World"
Normalized comparison:
  - DB normalized: "hello world"
  - JIRA normalized: "hello world"
Result: SKIP (case normalized, content same)
```

Note: If original case matters, this would update. But normalized comparison prevents case-only updates.

---

### Update Case 4: Special Characters Preserved

**Scenario**: Description with Unicode and special chars

```
DB: (empty)
JIRA: "Café ☕ — special chars: €, ™, ©"
Extracted: "Café ☕ — special chars: €, ™, ©"
Result: UPDATE with all characters preserved
```

---

## Error Scenarios

### Error Case 1: Defect Not Found

```
Processing: Jira issue KCBL-999
Action: repair_descriptions_for_defects checks all issues
Result: Defect.find_by(defect_unique: 'KCBL-999') returns nil
Log: [REPAIR-SKIP] KCBL-999: Defect not found in database
Stat: Counted as "Skipped"
```

---

### Error Case 2: Save Failure

```
Processing: KCBL-123
Action: validate_and_update_description detects change
Action: Try to save defect.content = new_description
Error: ActiveRecord raises exception (e.g., validation error)
Log: [DESCRIPTION-ERROR] KCBL-123: Failed to update description: ...
Stat: Counted as "Error"
Result: Script continues to next issue
```

---

### Error Case 3: Extraction Failure

```
Processing: KCBL-456
Action: extract_description called on malformed ADF
Error: Unexpected JSON structure
Log: [DESCRIPTION-ERROR] KCBL-456: Failed to extract description
Stat: Counted as "Error"
Result: defect.content not updated, script continues
```

---

## Full Import Example Output

```
$ rails runner scripts/import_jira_with_modules.rb --project KCBL --verbose

Starting direct Jira import with modules for project(s): KCBL (dry_run: false)

Discovering custom fields...
Found Module field: customfield_10500 - QA Module
Found Submodule field: customfield_10501 - QA Submodule

Fetching Jira issues with JQL: project = "KCBL" AND created >= "2025-09-28" ORDER BY created DESC
Date range: 2025-09-28 to 2025-11-28
Projects: KCBL
✓ Page 1: Fetched 100 issues (total collected: 100) [isLast: false, hasNextToken: YES]
✓ Page 2: Fetched 85 issues (total collected: 185) [isLast: true, hasNextToken: NO]
📊 Total issues fetched from Jira: 185 (across 2 pages)

Processing issue 1/185: KCBL-1
[DEFECT-SAVED] Successfully saved KCBL-1
[ASSIGNEE] Set assignee to John Smith (user-123)
[LABEL-MATCH] Matched label 'backend' ...
[LABEL-ATTACH] Successfully attached label 'backend' ...
[IMPORT] Added comment by Sarah Jones to KCBL-1 (id=msg-456)
[ATTACH] Successfully attached: design.png ...
[HISTORY] Imported 8 history entries for KCBL-1 ...

... (continuing for remaining issues) ...

🎉 Import completed!
Summary:
  Projects processed: KCBL
  Total issues processed: 185
  Successfully imported: 185
    - Created: 125
    - Updated: 60
  Skipped: 0
  Errors: 0

🔍 Running post-import verification...

🔍 Running post-import diagnostics...
Missing Items Summary:

🔧 Running repair pass for missing items...
  Repairing missing comments...
  Repairing missing attachments...
  Repairing missing labels...
  Repairing missing history entries...
  Validating and updating descriptions...
    - Checked: 185
    - Updated: 12
    - Skipped (no changes): 173
    - Errors: 0

[DESCRIPTION-REPAIRED] KCBL-1: Description updated from Jira
[DESCRIPTION-REPAIRED] KCBL-5: Description updated from Jira
[DESCRIPTION-REPAIRED] KCBL-12: Description updated from Jira
...

🔧 Repair pass complete!

📋 DETAILED IMPORT VERIFICATION REPORT
================================================================================
KCBL-1           -> OK    (comments: 5/5, issue_atts: 3/3, comment_atts: 2/2, labels: 1/1, history: 8/8)
KCBL-2           -> OK    (comments: 2/2, issue_atts: 0/0, comment_atts: 0/0, labels: 0/0, history: 3/3)
KCBL-3           -> OK    (comments: 8/8, issue_atts: 5/5, comment_atts: 3/3, labels: 2/2, history: 12/12)
...

Overall Success Summary:
  Issues fully OK: 185/185 (100%)
  Issues with problems: 0

End of import verification report.
================================================================================

👤 USER MATCH STATISTICS REPORT
================================================================================
Total user lookups performed: 528

Match breakdown:
  ✅ Email matches:          187 (35.42%)
  ✅ Full name matches:      156 (29.55%)
  ✅ First+Last matches:     112 (21.21%)
  ✅ Partial matches:        56 (10.61%)
  ✅ Config map matches:     10 (1.89%)
  🆕 Created users:          7
  ⚠️  Fallback to default:    2

Summary:
  Total unique matched users: 428
  Total unique fallback uses: 2

...

================================================================================
```

---

## Typical Results by Project Size

### Small Project (10-50 issues)
```
Validating and updating descriptions...
  - Checked: 25
  - Updated: 3
  - Skipped (no changes): 22
  - Errors: 0
Expected time: < 30 seconds
```

### Medium Project (100-500 issues)
```
Validating and updating descriptions...
  - Checked: 250
  - Updated: 15
  - Skipped (no changes): 235
  - Errors: 0
Expected time: 1-2 minutes
```

### Large Project (1000+ issues)
```
Validating and updating descriptions...
  - Checked: 1200
  - Updated: 48
  - Skipped (no changes): 1150
  - Errors: 2
Expected time: 3-5 minutes
```

---

## Verification Steps

After running the import, verify success:

```bash
# 1. Check for errors
grep ERROR log/development.log

# 2. Sample a few descriptions
rails console
Defect.limit(5).each { |d| puts "#{d.defect_unique}: #{d.content[0..100]}" }

# 3. Check specific issue
Defect.find_by(defect_unique: "KCBL-123").content

# 4. Count updated issues
Defect.where('updated_at > ?', Time.now - 1.hour).count
```

---

**Version**: 1.0
**Created**: 2025-11-28

