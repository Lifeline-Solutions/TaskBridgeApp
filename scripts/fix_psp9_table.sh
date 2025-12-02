#!/bin/bash
# Quick-start script for fixing PSP-9 table display issue

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "================================================================================"
echo "PSP-9 Table Fix - Quick Start"
echo "================================================================================"
echo ""

# Step 1: Check current status
echo "Step 1: Checking current PSP-9 status..."
echo "--------------------------------------------------------------------------------"
timeout 60 bundle exec rails runner scripts/check_psp9_status.rb || {
    echo "⚠️  Rails is taking too long or failed. Continuing anyway..."
}
echo ""

# Step 2: Run repair script with diagnostics
echo "Step 2: Running enhanced repair script..."
echo "--------------------------------------------------------------------------------"
echo "This will fetch PSP-9 from Jira and attempt to fix the table display."
echo "Files will be saved to tmp/ directory for inspection."
echo ""

timeout 120 bundle exec rails runner scripts/repair_rich_text_content.rb PSP-9 || {
    echo "⚠️  Repair script timed out or failed"
    echo ""
    echo "This could mean:"
    echo "  - Rails is slow to load (normal on first run)"
    echo "  - Jira API is slow or unreachable"
    echo "  - There's an error in the script"
    echo ""
    echo "Checking if files were created..."
}

echo ""
echo "Step 3: Checking saved files..."
echo "--------------------------------------------------------------------------------"

if [ -f "tmp/jira_response_PSP_9.json" ]; then
    echo "✓ Found: tmp/jira_response_PSP_9.json"
    SIZE=$(stat -f%z "tmp/jira_response_PSP_9.json" 2>/dev/null || stat -c%s "tmp/jira_response_PSP_9.json" 2>/dev/null || echo "?")
    echo "  Size: $SIZE bytes"
else
    echo "✗ Not found: tmp/jira_response_PSP_9.json"
fi

if [ -f "tmp/jira_PSP_9_description.json" ]; then
    echo "✓ Found: tmp/jira_PSP_9_description.json"
    SIZE=$(stat -f%z "tmp/jira_PSP_9_description.json" 2>/dev/null || stat -c%s "tmp/jira_PSP_9_description.json" 2>/dev/null || echo "?")
    echo "  Size: $SIZE bytes"

    # Try to identify table blocks
    if command -v jq &> /dev/null; then
        TABLE_COUNT=$(jq '[.content[]? | select(.type == "table")] | length' tmp/jira_PSP_9_description.json 2>/dev/null || echo "?")
        echo "  Tables found: $TABLE_COUNT"
    fi
else
    echo "✗ Not found: tmp/jira_PSP_9_description.json"
    echo ""
    echo "  This means the description field was not in the Jira API response."
    echo "  You may need to use the manual workflow."
fi

if [ -f "tmp/jira_PSP_9_rendered.html" ]; then
    echo "✓ Found: tmp/jira_PSP_9_rendered.html"
    SIZE=$(stat -f%z "tmp/jira_PSP_9_rendered.html" 2>/dev/null || stat -c%s "tmp/jira_PSP_9_rendered.html" 2>/dev/null || echo "?")
    echo "  Size: $SIZE bytes"

    if grep -q "<table" "tmp/jira_PSP_9_rendered.html" 2>/dev/null; then
        echo "  Contains: <table> tag ✓"
    fi

    if grep -q "<!-- ADF macro" "tmp/jira_PSP_9_rendered.html" 2>/dev/null; then
        echo "  Contains: ADF macro placeholders (needs conversion)"
    fi
else
    echo "✗ Not found: tmp/jira_PSP_9_rendered.html"
fi

if [ -f "tmp/psp9_current_content.html" ]; then
    echo "✓ Found: tmp/psp9_current_content.html (current DB content)"
    SIZE=$(stat -f%z "tmp/psp9_current_content.html" 2>/dev/null || stat -c%s "tmp/psp9_current_content.html" 2>/dev/null || echo "?")
    echo "  Size: $SIZE bytes"
fi

echo ""
echo "Step 4: Next actions..."
echo "--------------------------------------------------------------------------------"

if [ -f "tmp/jira_PSP_9_description.json" ]; then
    echo "✓ Description JSON found - attempting automatic conversion..."
    echo ""

    # Copy to psp9_description.json for the converter
    cp tmp/jira_PSP_9_description.json tmp/psp9_description.json

    # Run conversion
    echo "Running: ruby scripts/convert_psp9_table.rb"
    ruby scripts/convert_psp9_table.rb || {
        echo "❌ Conversion failed"
        exit 1
    }

    echo ""
    if [ -f "tmp/psp9_trix.html" ]; then
        echo "✓ Conversion successful!"
        echo "  Output: tmp/psp9_converted.html"
        echo "  Output: tmp/psp9_trix.html"
        echo ""
        echo "Preview of converted content:"
        echo "----------------------------------------"
        head -20 tmp/psp9_trix.html
        echo "..."
        echo "----------------------------------------"
        echo ""
        echo "To update the database, run:"
        echo "  bundle exec rails runner scripts/update_psp9_manually.rb"
    fi
else
    echo "❌ Description JSON not found - manual workflow required"
    echo ""
    echo "Please follow these steps:"
    echo ""
    echo "1. Check if Jira API returned any data:"
    echo "   cat tmp/jira_response_PSP_9.json | head -50"
    echo ""
    echo "2. If the file exists, check for description:"
    echo "   cat tmp/jira_response_PSP_9.json | jq '.fields.description'"
    echo ""
    echo "3. If description is null or missing:"
    echo "   - The issue might be empty in Jira"
    echo "   - There might be an API permission issue"
    echo "   - You may need to manually get the description from Jira UI"
    echo ""
    echo "4. Save the description JSON to tmp/psp9_description.json"
    echo ""
    echo "5. Run: ruby scripts/convert_psp9_table.rb"
    echo ""
    echo "6. Run: bundle exec rails runner scripts/update_psp9_manually.rb"
    echo ""
    echo "See PSP9_TABLE_FIX_GUIDE.md for detailed instructions."
fi

echo ""
echo "================================================================================"
echo "Quick reference:"
echo "  - Full guide: cat PSP9_TABLE_FIX_GUIDE.md"
echo "  - Summary: cat PSP9_FIX_SUMMARY.md"
echo "  - Check status: bundle exec rails runner scripts/check_psp9_status.rb"
echo "  - Manual update: bundle exec rails runner scripts/update_psp9_manually.rb"
echo "================================================================================"

