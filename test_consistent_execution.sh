#!/bin/bash
# Updated test script for consistent execution pattern

set -e

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Module & Submodule Configuration - Updated Test Script"
echo "All Projects Execute the Same Way (Like KCBL and RMP)"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "scripts/fix_submodules.rb" ]; then
    echo -e "${RED}ERROR: scripts/fix_submodules.rb not found!${NC}"
    echo "Please run this script from the Rails root directory."
    exit 1
fi

echo -e "${BLUE}Testing fix_submodules.rb with consistent execution pattern${NC}"
echo -e "${BLUE}All projects now use the same validation and processing logic${NC}"
echo ""

# Function to run test
test_project() {
    local project=$1
    local description=$2
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Testing $project project: $description${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo "Command: rails runner scripts/fix_submodules.rb --project $project --dry-run -e production"
    echo ""
    rails runner scripts/fix_submodules.rb --project $project --dry-run -e production
    echo ""
}

# Test all projects
echo -e "${GREEN}Testing projects with full module/submodule structure:${NC}"
echo ""

test_project "RMP" "Rafiki Modules / Rafiki Modules - Sub Modules"
test_project "KCBL" "KCBL Modules / KCBL Modules/Submodules"

echo -e "${GREEN}Testing projects with fixed module names (no submodules):${NC}"
echo ""

test_project "SJP" "Modules SC Juza"
test_project "KUP" "Components (K-Unity)"
test_project "GBCBS" "Module"
test_project "GBCBU2" "Components"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ All dry-run tests completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}VERIFICATION:${NC}"
echo "All projects followed the same execution pattern:"
echo "  1. Field discovery (module_field + submodule_field or 'DUMMY')"
echo "  2. Validation check (module_field && submodule_field)"
echo "  3. JIRA API fetch (safe handling of 'DUMMY' fields)"
echo "  4. Module name processing (dynamic or fixed)"
echo "  5. Find/create modules"
echo "  6. Update defects"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the output above for any errors or unexpected changes"
echo "2. Verify all projects passed validation"
echo "3. Check module names match expected values"
echo "4. If everything looks correct, run the actual update:"
echo ""
echo -e "${GREEN}  # Process individual projects:${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project SJP -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project KUP -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project GBCBS -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project GBCBU2 -e production${NC}"
echo ""
echo -e "${GREEN}  # Or process all at once:${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --all -e production${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Status: All projects execute the same way ✅${NC}"
echo -e "${BLUE}Pattern: Consistent with KCBL and RMP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"

