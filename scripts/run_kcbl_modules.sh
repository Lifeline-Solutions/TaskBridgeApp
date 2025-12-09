#!/bin/bash
# Quick command reference for KCBL modules setup

echo "KCBL Modules & Submodules - Quick Reference"
echo "=============================================="
echo ""
echo "Step 1: Preview changes (DRY RUN)"
echo "  rails runner scripts/fix_submodules.rb --project KCBL --dry-run -e production"
echo ""
echo "Step 2: Apply changes (EXECUTE)"
echo "  rails runner scripts/fix_submodules.rb --project KCBL -e production"
echo ""
echo "Step 3: Verify in database"
echo "  rails c -e production"
echo "  > Defect.where('defect_unique LIKE ?', 'KCBL%').pluck(:defect_unique, :qa_module_id, :submodule_id).first(10)"
echo ""
echo "Expected result:"
echo "  Both qa_module_id and submodule_id should point to 'KCBL Modules/Submodules' module"
echo ""

