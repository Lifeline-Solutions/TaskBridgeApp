# IMMEDIATE FIX - Push Without Secret

## Problem
Commit `1c2054e6` contains a hardcoded API token that GitHub is blocking.

## FASTEST SOLUTION - Bypass and Delete Old Branch

Since you've already merged upstream/main-prod and the file is fixed, do this:

### Step 1: Check out a fresh branch from upstream
```bash
cd /home/abol-ger/Desktop/Projects/tasker/CSPM
git fetch upstream
git checkout -b psp9-clean upstream/main-prod
```

### Step 2: Copy ONLY the fixed file(s) from your working directory
```bash
# The file is already fixed in your current directory
# Just copy it to the new branch
cp scripts/diagnose_psp9.rb /tmp/diagnose_psp9_fixed.rb

# Now it's in the new branch, stage it
git checkout -b psp9-clean upstream/main-prod  # If not already
cp /tmp/diagnose_psp9_fixed.rb scripts/diagnose_psp9.rb
git add scripts/diagnose_psp9.rb
```

### Step 3: Copy all other PSP-9 files
```bash
# List all PSP-9 related new files:
git checkout main-prod -- \
  scripts/convert_psp9_table.rb \
  scripts/update_psp9_manually.rb \
  scripts/check_psp9_status.rb \
  scripts/fix_psp9_table.sh \
  scripts/fetch_jira_issue.rb \
  scripts/repair_rich_text_content.rb \
  README_PSP9_FIX.md \
  PSP9_FIX_SUMMARY.md \
  PSP9_TABLE_FIX_GUIDE.md

# Make sure diagnose_psp9.rb is the FIXED version
cp /tmp/diagnose_psp9_fixed.rb scripts/diagnose_psp9.rb
```

### Step 4: Verify NO secrets
```bash
# This should return NOTHING
grep -r "ATATT3xFfGF0Mq4A6TnDi9Qx205Dg3eFCNL1xTshkyiEvP6ude7eWLp4GxEc3hmAxAuLCpJaECc44tLuwXJU" scripts/

# This should show the CORRECT credential loading:
grep "JIRA_API_TOKEN" scripts/diagnose_psp9.rb
# Should show: JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }
```

### Step 5: Commit and push
```bash
git add scripts/ *.md
git commit -m "Add PSP-9 table fix utilities with secure credential management

New diagnostic and fix scripts for PSP-9 table display issues:
- All scripts load credentials from config/jira_import.yml
- No hardcoded secrets
- Complete documentation included"

# Push the CLEAN branch
git push upstream psp9-clean
```

### Step 6: Merge to main-prod (via GitHub PR or directly)
```bash
# Option A: Create PR on GitHub and merge through UI

# Option B: Merge directly (if you have permissions)
git checkout main-prod
git merge psp9-clean
git push upstream main-prod
```

### Step 7: Clean up old branch
```bash
git branch -D pull-main-prod  # Delete the branch with the secret
```

## ALTERNATIVE - Use GitHub's Bypass (Not Recommended)

If you're in a hurry, GitHub provides a bypass link:
https://github.com/Kanyorok/TaskBridgeApp/security/secret-scanning/unblock-secret/36HwJrYrVCnmRBUBUDtWXwKQnCn

**WARNING**: This keeps the secret in git history. Only use if you plan to rotate the API token immediately after.

## Verify Your Current File

The file `/home/abol-ger/Desktop/Projects/tasker/CSPM/scripts/diagnose_psp9.rb` is already fixed.

Run this to confirm:
```bash
head -20 /home/abol-ger/Desktop/Projects/tasker/CSPM/scripts/diagnose_psp9.rb
```

Should show:
```ruby
#!/usr/bin/env ruby
# Diagnose PSP-9 issue structure

require 'net/http'
require 'uri'
require 'json'
require 'yaml'

# Load configuration from jira_import.yml
config_path = File.join(__dir__, '..', 'config', 'jira_import.yml')
CONFIG = YAML.load_file(config_path).transform_keys(&:to_sym)

JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', CONFIG[:jira_base_url] || 'https://craftsilicon.atlassian.net')
JIRA_API_USER = ENV.fetch('JIRA_API_USER', CONFIG[:jira_api_user] || 'boniface.nemwel@craftsilicon.com')
JIRA_API_TOKEN = ENV.fetch('JIRA_API_TOKEN') { CONFIG[:jira_api_token] }
```

✅ = CORRECT (loads from config)
❌ = Would show hardcoded token

## Summary

1. **Your file is already fixed** ✅
2. **The problem is in git history** (old commit)
3. **Solution**: Create new branch from clean base
4. **Copy files** from working directory (not from git)
5. **Push new branch** without the bad commit

This takes 2 minutes and you're done!

