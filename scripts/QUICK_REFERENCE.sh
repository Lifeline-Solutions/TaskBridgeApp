#!/bin/bash
# Quick Reference: Comment Attachment Verification System
# ========================================================

cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════╗
║                COMMENT ATTACHMENT VERIFICATION SYSTEM                  ║
║                         Quick Reference Guide                          ║
╚════════════════════════════════════════════════════════════════════════╝

┌────────────────────────────────────────────────────────────────────────┐
│ PRODUCTION SETUP (First Time)                                         │
└────────────────────────────────────────────────────────────────────────┘

1. Create storage directory:
   $ sudo ./scripts/fix_storage_permissions.sh

2. Verify setup:
   $ ./scripts/quick_attachment_check.sh

3. Restart Rails app:
   $ sudo systemctl restart taskbridge

┌────────────────────────────────────────────────────────────────────────┐
│ RUN IMPORT WITH VERIFICATION                                          │
└────────────────────────────────────────────────────────────────────────┘

Development:
   $ rails runner scripts/import_jira_with_modules.rb \
       --project PSP --verbose

Production:
   $ RAILS_ENV=production rails runner scripts/import_jira_with_modules.rb \
       --project PSP --verbose

What happens during import:
✅ Each attachment is downloaded and verified
✅ Failed uploads are automatically retried (up to 2 times)
✅ Missing files are identified and re-uploaded
✅ Each defect is fully verified before moving to next
✅ Detailed statistics are logged for each comment

┌────────────────────────────────────────────────────────────────────────┐
│ VERIFY EXISTING ATTACHMENTS                                           │
└────────────────────────────────────────────────────────────────────────┘

Check all comment attachments:
   $ rails runner scripts/verify_and_fix_comment_attachments.rb \
       --check-all --verbose

Check specific defect:
   $ rails runner scripts/verify_and_fix_comment_attachments.rb \
       --defect-unique PSP-123 --verbose

Check all attachments (issue + comment level):
   $ rails runner scripts/verify_attachments.rb --verbose

┌────────────────────────────────────────────────────────────────────────┐
│ FIX MISSING ATTACHMENTS                                               │
└────────────────────────────────────────────────────────────────────────┘

Step 1: Identify missing attachments
   $ rails runner scripts/verify_and_fix_comment_attachments.rb --check-all

Step 2: Re-run import (will skip duplicates, fix missing)
   $ rails runner scripts/import_jira_with_modules.rb \
       --project PSP --verbose

Step 3: Verify fix worked
   $ rails runner scripts/verify_and_fix_comment_attachments.rb --check-all

┌────────────────────────────────────────────────────────────────────────┐
│ DIAGNOSTIC TOOLS                                                      │
└────────────────────────────────────────────────────────────────────────┘

Quick health check:
   $ ./scripts/quick_attachment_check.sh

Check storage permissions:
   $ ls -la /var/www/uploads  # Production
   $ ls -la storage/          # Development

Test storage write access:
   $ touch /var/www/uploads/.test && rm /var/www/uploads/.test
   $ echo "Storage is writable!"

Check Rails storage config:
   $ RAILS_ENV=production rails runner \
       "puts ActiveStorage::Blob.service.class.name"

┌────────────────────────────────────────────────────────────────────────┐
│ VERIFICATION LEVELS                                                   │
└────────────────────────────────────────────────────────────────────────┘

Level 1: Per-Attachment
   • Download verified (HTTP 200)
   • Upload to storage successful
   • Blob record created in database
   • File physically exists in storage

Level 2: Per-Comment
   • Expected count matches actual count
   • All files verified in storage
   • Missing files identified and retried
   • Statistics tracked (uploaded/skipped/failed)

Level 3: Per-Defect
   • Issue-level attachments verified
   • Comment-level attachments verified
   • Total counts and statistics reported
   • Warnings for any missing files
   • Prevents moving to next defect if incomplete

┌────────────────────────────────────────────────────────────────────────┐
│ UNDERSTANDING THE OUTPUT                                              │
└────────────────────────────────────────────────────────────────────────┘

During Import:
   [ATTACH] Attaching 3 file(s) (2.5 MB total) to comment 123...
   ✅ [OK] Attached comment file 'screenshot.png' (1.2 MB)
   ✅ [OK] Attached comment file 'document.pdf' (1.0 MB)
   ✅ [OK] Attached comment file 'data.xlsx' (0.3 MB)
   [OK] Successfully attached all 3 file(s) to comment 123

   [VERIFY] Final verification for defect: PSP-123
   [VERIFY] Comment-level attachments:
   [VERIFY]   Total comments: 5
   [VERIFY]   Comments with attachments: 3
   [VERIFY]   Total attachment files: 7
   [VERIFY]   Verified in storage: 7
   [VERIFY]   ✅ All comment-level files verified in storage
   [VERIFY] ✅ DEFECT PSP-123: All 10 attachment(s) verified!

After Import:
   Defects checked: 39
   Comments with attachments: 76
   Total attachment records: 87
   Verified in storage: 87 (100.0%)
   Missing from storage: 0 (0.0%)
   ✅ All comment-level attachments verified successfully!

┌────────────────────────────────────────────────────────────────────────┐
│ COMMON ISSUES & SOLUTIONS                                             │
└────────────────────────────────────────────────────────────────────────┘

Issue: "Storage directory NOT FOUND"
Solution: 
   $ sudo mkdir -p /var/www/uploads
   $ sudo chown -R www-data:www-data /var/www/uploads

Issue: "Storage directory is NOT writable"
Solution:
   $ sudo chmod -R 755 /var/www/uploads
   $ sudo chown -R www-data:www-data /var/www/uploads

Issue: "Partial upload: 2/3 files"
Solution: Re-run import (automatic retry will handle missing files)
   $ rails runner scripts/import_jira_with_modules.rb --project PSP --verbose

Issue: "File MISSING FROM STORAGE"
Solution:
   1. Check storage directory exists and is writable
   2. Re-run import to re-download missing files
   3. Import will skip duplicates and only upload missing

┌────────────────────────────────────────────────────────────────────────┐
│ DOCUMENTATION                                                         │
└────────────────────────────────────────────────────────────────────────┘

Full Troubleshooting Guide:
   ATTACHMENT_TROUBLESHOOTING.md

Implementation Details:
   COMMENT_ATTACHMENT_IMPROVEMENTS.md

Scripts Location:
   scripts/import_jira_with_modules.rb
   scripts/verify_and_fix_comment_attachments.rb
   scripts/fix_storage_permissions.sh
   scripts/quick_attachment_check.sh

╔════════════════════════════════════════════════════════════════════════╗
║                    System is now production-ready!                     ║
╚════════════════════════════════════════════════════════════════════════╝

EOF
