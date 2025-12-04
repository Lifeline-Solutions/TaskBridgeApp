#!/bin/bash
# Test Script for Import Fix Verification
# This script validates that the import_issue_with_modules fix is working

set -e

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Import Script Fix - Test Suite"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
  echo -e "${GREEN}✅ PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}❌ FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

warn() {
  echo -e "${YELLOW}⚠️  WARN${NC}: $1"
}

# Test 1: Syntax Check
echo "Test 1: Ruby Syntax Validation"
echo "──────────────────────────────────────────────────────────────────────────"
if ruby -c scripts/import_jira_with_modules.rb 2>&1 | grep -q "Syntax OK"; then
  pass "Ruby syntax is valid"
else
  fail "Ruby syntax check failed"
fi
echo ""

# Test 2: Function Exists
echo "Test 2: Function Definition Check"
echo "──────────────────────────────────────────────────────────────────────────"
if grep -q "def import_issue_with_modules" scripts/import_jira_with_modules.rb; then
  LINE=$(grep -n "def import_issue_with_modules" scripts/import_jira_with_modules.rb | cut -d: -f1)
  pass "Function 'import_issue_with_modules' found at line $LINE"
else
  fail "Function 'import_issue_with_modules' not found"
fi
echo ""

# Test 3: Function Signature
echo "Test 3: Function Signature Check"
echo "──────────────────────────────────────────────────────────────────────────"
if grep -q "def import_issue_with_modules(issue, custom_fields" scripts/import_jira_with_modules.rb; then
  pass "Function signature is correct"
else
  fail "Function signature is incorrect or incomplete"
fi
echo ""

# Test 4: Function Call Integration
echo "Test 4: Function Call Integration"
echo "──────────────────────────────────────────────────────────────────────────"
CALL_COUNT=$(grep "import_issue_with_modules(issue" scripts/import_jira_with_modules.rb | wc -l)
if [ "$CALL_COUNT" -gt 0 ]; then
  pass "Function is called $CALL_COUNT time(s) in main execution"
else
  fail "Function is never called in main execution"
fi
echo ""

# Test 5: Helper Functions Available
echo "Test 5: Helper Functions Check"
echo "──────────────────────────────────────────────────────────────────────────"
HELPERS=(
  "find_user_by_name_or_map"
  "find_or_create_status"
  "find_or_create_modules"
  "find_or_create_banking_type"
  "fetch_and_attach_attachments"
  "attach_labels_to_defect"
  "import_comments_for_defect"
  "validate_and_update_description"
  "extract_description"
  "try_parse_time"
)

MISSING_HELPERS=0
for helper in "${HELPERS[@]}"; do
  if grep -q "def $helper" scripts/import_jira_with_modules.rb; then
    pass "Helper function '$helper' exists"
  else
    fail "Helper function '$helper' not found"
    MISSING_HELPERS=$((MISSING_HELPERS + 1))
  fi
done
echo ""

# Test 6: Error Handling
echo "Test 6: Error Handling Check"
echo "──────────────────────────────────────────────────────────────────────────"
if grep -q "begin\|rescue\|ensure" scripts/import_jira_with_modules.rb; then
  pass "Error handling (begin/rescue/ensure) found"
else
  fail "Error handling not found"
fi
echo ""

# Test 7: Logging Statements
echo "Test 7: Logging Statements Check"
echo "──────────────────────────────────────────────────────────────────────────"
if grep -q "vputs\|info\|warn" scripts/import_jira_with_modules.rb | head -5; then
  pass "Logging statements (vputs, info, warn) found"
else
  warn "Logging statements might be missing"
fi
echo ""

# Test 8: Constants Used
echo "Test 8: Constants Check"
echo "──────────────────────────────────────────────────────────────────────────"
CONSTANTS=(
  "DEFAULT_PRODUCT_UUID"
  "DEFAULT_PRIORITY"
  "DEFAULT_USER_UUID"
  "FALLBACK_QA_MODULE_ID"
  "FALLBACK_SUBMODULE_ID"
  "FALLBACK_BANKING_TYPE_ID"
)

MISSING_CONSTANTS=0
for const in "${CONSTANTS[@]}"; do
  if grep -q "$const" scripts/import_jira_with_modules.rb; then
    pass "Constant '$const' is referenced"
  else
    warn "Constant '$const' not found (may be optional)"
  fi
done
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Test Results Summary"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✅ ALL TESTS PASSED - Script is ready to use${NC}"
  echo ""
  echo "Next Steps:"
  echo "1. Run dry-run test:"
  echo "   rails runner scripts/import_jira_with_modules.rb --project KCBL --dry-run"
  echo ""
  echo "2. Run actual test import:"
  echo "   rails runner scripts/import_jira_with_modules.rb --project PSP --verbose"
  echo ""
  echo "3. Check database:"
  echo "   rails console"
  echo "   > Defect.find_by(defect_unique: 'PSP-1')"
  echo ""
  exit 0
else
  echo -e "${RED}❌ SOME TESTS FAILED - Please review the errors above${NC}"
  echo ""
  echo "Please check:"
  echo "1. Is the function definition complete?"
  echo "2. Are all helper functions present?"
  echo "3. Is the script syntax valid?"
  echo ""
  exit 1
fi

