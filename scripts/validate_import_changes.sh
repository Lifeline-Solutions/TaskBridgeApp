#!/bin/bash
# Quick validation script for import improvements

# ============================================
# CONFIGURATION - Change these as needed
# ============================================
# Default project(s) for examples (can be single: "KCBL" or multiple: "PSP,KCBL,FLOW")
DEFAULT_PROJECT="${1:-KCBL}"

echo "=========================================="
echo "JIRA Import Script Validation"
echo "=========================================="
echo "Project(s) to use in examples: ${DEFAULT_PROJECT}"
echo ""

# Check syntax
echo "1. Checking Ruby syntax..."
ruby -c scripts/import_jira_with_modules.rb
if [ $? -eq 0 ]; then
  echo "   ✅ Syntax OK"
else
  echo "   ❌ Syntax errors found"
  exit 1
fi

echo ""
echo "2. Checking test script syntax..."
ruby -c scripts/test_user_matching.rb
if [ $? -eq 0 ]; then
  echo "   ✅ Test script syntax OK"
else
  echo "   ❌ Test script syntax errors"
  exit 1
fi

echo ""
echo "3. Checking fix script syntax..."
ruby -c scripts/fix_default_user_assignments.rb
if [ $? -eq 0 ]; then
  echo "   ✅ Fix script syntax OK"
else
  echo "   ❌ Fix script syntax errors"
  exit 1
fi

echo ""
echo "4. Checking for key improvements..."
grep -q "dot-separated" scripts/import_jira_with_modules.rb && echo "   ✅ Dot-separated name parsing added" || echo "   ⚠️  Dot-separated parsing not found"
grep -q "3-part" scripts/import_jira_with_modules.rb && echo "   ✅ 3-part name matching added" || echo "   ⚠️  3-part matching not found"
grep -q "@craftsilicon.com" scripts/import_jira_with_modules.rb && echo "   ✅ Craftsilicon email preference added" || echo "   ⚠️  Email preference not found"
grep -q "active: true" scripts/import_jira_with_modules.rb && echo "   ✅ Active user filtering added" || echo "   ⚠️  Active filtering not found"
grep -q "size_mb > 20" scripts/import_jira_with_modules.rb && echo "   ✅ Dynamic retry logic added" || echo "   ⚠️  Dynamic retry not found"

echo ""
echo "=========================================="
echo "Validation Complete!"
echo "=========================================="
echo ""
echo "Usage Examples:"
echo "---------------"
echo ""
echo "Test user matching:"
echo "  rails runner scripts/test_user_matching.rb"
echo ""
echo "Run import for ${DEFAULT_PROJECT}:"
echo "  rails runner scripts/import_jira_with_modules.rb --project ${DEFAULT_PROJECT} --verbose"
echo ""
echo "Run import for multiple projects:"
echo "  rails runner scripts/import_jira_with_modules.rb --project PSP,KCBL,FLOW --verbose"
echo ""
echo "Fix existing DEFAULT_USER assignments (dry-run):"
echo "  rails runner scripts/fix_default_user_assignments.rb"
echo ""
echo "Fix existing DEFAULT_USER assignments (execute):"
echo "  rails runner scripts/fix_default_user_assignments.rb --execute"
echo ""
echo "=========================================="
echo "To change the project for examples, run:"
echo "  $0 PROJECT_KEY"
echo "Example: $0 PSP"
echo "Example: $0 PSP,KCBL,FLOW"
echo "=========================================="

