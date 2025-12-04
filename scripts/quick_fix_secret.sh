#!/bin/bash
# Simple one-liner fix - just copy files to a clean branch

cd /home/abol-ger/Desktop/Projects/tasker/CSPM

echo "========================================="
echo "QUICK FIX: Create Clean Branch"
echo "========================================="
echo ""

# Save current files to tmp
echo "Saving current (fixed) files to /tmp/psp9_fixed..."
mkdir -p /tmp/psp9_fixed
cp -r scripts/*.rb /tmp/psp9_fixed/ 2>/dev/null || true
cp -r scripts/*.sh /tmp/psp9_fixed/ 2>/dev/null || true
cp *.md /tmp/psp9_fixed/ 2>/dev/null || true

echo "✓ Files saved"
echo ""

echo "Files to copy:"
ls -1 /tmp/psp9_fixed/

echo ""
echo "========================================="
echo "Run these commands manually:"
echo "========================================="
echo ""
echo "# 1. Create clean branch"
echo "git checkout -b psp9-table-fix upstream/main-prod"
echo ""
echo "# 2. Copy fixed files"
echo "cp /tmp/psp9_fixed/diagnose_psp9.rb scripts/"
echo "cp /tmp/psp9_fixed/convert_psp9_table.rb scripts/"
echo "cp /tmp/psp9_fixed/update_psp9_manually.rb scripts/"
echo "cp /tmp/psp9_fixed/check_psp9_status.rb scripts/"
echo "cp /tmp/psp9_fixed/fetch_jira_issue.rb scripts/"
echo "cp /tmp/psp9_fixed/fix_psp9_table.sh scripts/"
echo "cp /tmp/psp9_fixed/repair_rich_text_content.rb scripts/"
echo "cp /tmp/psp9_fixed/*.md ."
echo ""
echo "# 3. Verify no secrets"
echo "grep -r 'ATATT3xFfGF0' scripts/ || echo 'Clean!'"
echo ""
echo "# 4. Stage and commit"
echo "git add scripts/ *.md"
echo "git commit -m 'Add PSP-9 table fix utilities (secure)'"
echo ""
echo "# 5. Push"
echo "git push upstream psp9-table-fix"
echo ""
echo "========================================="

