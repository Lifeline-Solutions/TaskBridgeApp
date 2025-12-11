#!/bin/bash
# Test script for Module & Submodule Configuration Update
# This script runs the fix_submodules.rb script with dry-run for all new projects

set -e

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "Module & Submodule Configuration - Test Script"
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

echo -e "${BLUE}Testing fix_submodules.rb with dry-run mode${NC}"
echo ""

# Function to run test
test_project() {
    local project=$1
    echo -e "${YELLOW}Testing $project project...${NC}"
    echo "Command: rails runner scripts/fix_submodules.rb --project $project --dry-run -e production"
    echo ""
    rails runner scripts/fix_submodules.rb --project $project --dry-run -e production
    echo ""
}

# Test all new projects
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "Test 1: SJP Project (Modules SC Juza)"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
test_project "SJP"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "Test 2: KUP Project (Components K-Unity)"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
test_project "KUP"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "Test 3: GBCBS Project (Module)"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
test_project "GBCBS"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo "Test 4: GBCBU2 Project (Components)"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════════════${NC}"
test_project "GBCBU2"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ All dry-run tests completed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo "Next Steps:"
echo "1. Review the output above for any errors or unexpected changes"
echo "2. If everything looks correct, run the actual update:"
echo ""
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project SJP -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project KUP -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project GBCBS -e production${NC}"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --project GBCBU2 -e production${NC}"
echo ""
echo "Or run all at once:"
echo -e "${YELLOW}  rails runner scripts/fix_submodules.rb --all -e production${NC}"
echo ""

