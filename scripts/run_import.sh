#!/bin/bash
# Comprehensive import validation and execution helper
# Usage: ./scripts/run_import.sh [PROJECT_KEY(S)] [OPTIONS]

set -e  # Exit on error

# ============================================
# CONFIGURATION
# ============================================
PROJECT_KEY="${1:-KCBL}"
VERBOSE="${2:---verbose}"
DRY_RUN="${3}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# FUNCTIONS
# ============================================

print_header() {
    echo ""
    echo "=========================================="
    echo -e "${BLUE}$1${NC}"
    echo "=========================================="
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================
# MAIN SCRIPT
# ============================================

print_header "JIRA Import Execution Helper"

echo "Configuration:"
echo "  Project(s): ${PROJECT_KEY}"
echo "  Verbose: ${VERBOSE}"
echo "  Dry Run: ${DRY_RUN}"
echo ""

# Step 1: Validate scripts
print_header "Step 1: Validating Scripts"

echo "Checking import script syntax..."
if ruby -c scripts/import_jira_with_modules.rb > /dev/null 2>&1; then
    print_success "Import script syntax OK"
else
    print_error "Import script has syntax errors"
    ruby -c scripts/import_jira_with_modules.rb
    exit 1
fi

echo "Checking test script syntax..."
if ruby -c scripts/test_user_matching.rb > /dev/null 2>&1; then
    print_success "Test script syntax OK"
else
    print_error "Test script has syntax errors"
    ruby -c scripts/test_user_matching.rb
    exit 1
fi

echo "Checking fix script syntax..."
if ruby -c scripts/fix_default_user_assignments.rb > /dev/null 2>&1; then
    print_success "Fix script syntax OK"
else
    print_error "Fix script has syntax errors"
    ruby -c scripts/fix_default_user_assignments.rb
    exit 1
fi

# Step 2: Check for improvements
print_header "Step 2: Verifying Improvements"

check_improvement() {
    local pattern="$1"
    local description="$2"

    if grep -q "$pattern" scripts/import_jira_with_modules.rb; then
        print_success "$description"
    else
        print_warning "$description not found"
    fi
}

check_improvement "dot-separated" "Dot-separated name parsing"
check_improvement "3-part" "3-part name matching"
check_improvement "@craftsilicon.com" "Craftsilicon email preference"
check_improvement "active: true" "Active user filtering"
check_improvement "size_mb > 20" "Dynamic retry logic"

# Step 3: Test user matching
print_header "Step 3: Testing User Matching (Optional)"

echo "Would you like to test user matching? (y/n)"
read -t 10 -n 1 test_matching
echo ""

if [[ $test_matching == "y" || $test_matching == "Y" ]]; then
    print_info "Running user matching tests..."
    rails runner scripts/test_user_matching.rb
else
    print_info "Skipping user matching tests"
fi

# Step 4: Check existing DEFAULT_USER assignments
print_header "Step 4: Checking DEFAULT_USER Assignments"

echo "Would you like to check for incorrect DEFAULT_USER assignments? (y/n)"
read -t 10 -n 1 check_default
echo ""

if [[ $check_default == "y" || $check_default == "Y" ]]; then
    print_info "Checking DEFAULT_USER assignments (dry-run)..."
    rails runner scripts/fix_default_user_assignments.rb

    echo ""
    echo "Would you like to fix these assignments? (y/n)"
    read -t 10 -n 1 fix_default
    echo ""

    if [[ $fix_default == "y" || $fix_default == "Y" ]]; then
        print_info "Fixing DEFAULT_USER assignments..."
        rails runner scripts/fix_default_user_assignments.rb --execute
        print_success "Assignments fixed"
    else
        print_info "Skipping fixes"
    fi
else
    print_info "Skipping DEFAULT_USER check"
fi

# Step 5: Run import
print_header "Step 5: Running Import"

if [[ -n "$DRY_RUN" ]]; then
    print_warning "Dry run mode - no changes will be made"
    IMPORT_CMD="rails runner scripts/import_jira_with_modules.rb --project ${PROJECT_KEY} ${VERBOSE} --dry-run"
else
    print_info "Live import mode - changes will be saved"
    IMPORT_CMD="rails runner scripts/import_jira_with_modules.rb --project ${PROJECT_KEY} ${VERBOSE}"
fi

echo ""
echo "Import command:"
echo "  ${IMPORT_CMD}"
echo ""
echo "Ready to run import. Continue? (y/n)"
read -t 10 -n 1 run_import
echo ""

if [[ $run_import == "y" || $run_import == "Y" ]]; then
    print_info "Starting import for ${PROJECT_KEY}..."
    echo ""

    # Run the import
    eval $IMPORT_CMD

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        print_success "Import completed successfully!"
    else
        print_error "Import failed with exit code ${EXIT_CODE}"
        exit $EXIT_CODE
    fi
else
    print_info "Import cancelled by user"
    exit 0
fi

# Step 6: Post-import checks
print_header "Step 6: Post-Import Checks"

echo "Would you like to check for remaining DEFAULT_USER assignments? (y/n)"
read -t 10 -n 1 check_after
echo ""

if [[ $check_after == "y" || $check_after == "Y" ]]; then
    print_info "Checking post-import DEFAULT_USER assignments..."
    rails runner scripts/fix_default_user_assignments.rb
fi

# Final summary
print_header "Import Process Complete"

print_success "All steps completed for project(s): ${PROJECT_KEY}"
echo ""
echo "Next steps:"
echo "  1. Review import logs for any warnings"
echo "  2. Check attachment success rate"
echo "  3. Verify user assignments are correct"
echo "  4. Run fix script if needed: rails runner scripts/fix_default_user_assignments.rb --execute"
echo ""
print_info "Import completed at $(date)"

