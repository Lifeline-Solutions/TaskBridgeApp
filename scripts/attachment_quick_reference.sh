#!/bin/bash
# Quick Reference: Attachment Import & Verification
# Usage: ./scripts/attachment_quick_reference.sh

cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                 ATTACHMENT IMPORT & VERIFICATION - QUICK GUIDE             ║
╚════════════════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 WHAT YOU'LL SEE DURING IMPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. PER-ISSUE ATTACHMENT SUMMARY
   ════════════════════════════════════════════════════════════════
   📎 ATTACHMENTS FOR PSP-123
   ════════════════════════════════════════════════════════════════
   Total attachments in Jira: 8

   Attachment Details:
     1. screenshot.png (2.5 MB, created: 2025-01-15T10:30:00.000Z)
     2. error_log.txt (0.15 MB, created: 2025-01-15T10:32:00.000Z)
     ...

   Attachment Categorization:
     Comment-level attachments: 3
       1. file1.png (1.9 MB) → Will attach to comment
       ...
     Issue-level attachments: 5
       1. file2.png (2.5 MB) → Will attach to defect
       ...

2. ISSUE-LEVEL DOWNLOADS (Files attached to defect)
   ════════════════════════════════════════════════════════════════
   📥 DOWNLOADING ISSUE-LEVEL ATTACHMENTS FOR PSP-123
      Total files: 5 (57.63 MB)

      [1/5] 📥 Downloading file1.png (2.5 MB)... ✅ OK (1.23s)
      [2/5] 📥 Downloading file2.txt (0.15 MB)... ✅ OK (0.34s)
      [3/5] 📥 Downloading file3.sql (45.2 MB)... ✅ OK (23.45s)
      ...

   Issue-level attachment summary:
     ✅ Uploaded: 5
     ⏭️  Skipped: 0
     ❌ Failed: 0

3. COMMENT-LEVEL DOWNLOADS (Files attached to comments)
   ════════════════════════════════════════════════════════════════
   📎 DOWNLOADING COMMENT ATTACHMENTS
      Comment ID: 12345 (Jira: 67890)
      Files: 3 (1.97 MB total)

     [1/3] 📥 file1.png (1.9 MB)... ✅ OK (1.05s)
     [2/3] 📥 file2.yml (0.02 MB)... ✅ OK (0.12s)
     [3/3] 📥 file3.txt (0.05 MB)... ✅ OK (0.08s)

      Comment attachment summary:
        ✅ All 3 file(s) uploaded and verified

4. FINAL VERIFICATION
   ════════════════════════════════════════════════════════════════
   [VERIFY] Final verification for defect: PSP-123
   [VERIFY] Issue-level attachments: 5 file(s)
   [VERIFY]   ✅ All issue-level files verified in storage
   [VERIFY] Comment-level attachments:
   [VERIFY]   Total attachment files: 3
   [VERIFY]   ✅ All comment-level files verified in storage
   [VERIFY] ✅ DEFECT PSP-123: All 8 attachment(s) verified!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 STATUS INDICATORS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ OK       → Downloaded, uploaded, and verified in storage
⏭️  SKIP     → File already exists (duplicate)
❌ FAILED   → Download or upload error
⚠️  PARTIAL  → Downloaded but not verified in storage
🔄 RETRY    → Automatic retry in progress

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🗂️  WHERE ATTACHMENTS ARE STORED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ISSUE-LEVEL ATTACHMENTS → Defect Record
  Database: active_storage_attachments
    - record_type = 'Defect'
    - record_id = defect.id
  Storage: storage/ab/cd/abcd1234... (by blob key)
  UI: Defect detail page, main attachments section

COMMENT-LEVEL ATTACHMENTS → DefectMessage Record
  Database: active_storage_attachments
    - record_type = 'DefectMessage'
    - record_id = defect_message.id
  Storage: storage/ef/gh/efgh5678... (by blob key)
  UI: Comment section, inline with comment text

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RUN IMPORT (with enhanced reporting):
  rails runner scripts/import_jira_with_modules.rb \
    --project PSP,KCBL,FLOW \
    --verbose

CHECK STORAGE HEALTH:
  ./scripts/check_comment_attachments_health.sh

VERIFY SPECIFIC DEFECT:
  rails runner scripts/verify_and_fix_comment_attachments.rb \
    --defect-unique PSP-123 \
    --verbose

VERIFY ALL DEFECTS:
  rails runner scripts/verify_and_fix_comment_attachments.rb \
    --check-all \
    --verbose

COUNT ATTACHMENTS IN DATABASE:
  rails runner "
    puts 'Issue-level: ' + ActiveStorage::Attachment.where(record_type: 'Defect').count.to_s
    puts 'Comment-level: ' + ActiveStorage::Attachment.where(record_type: 'DefectMessage').count.to_s
  "

CHECK SPECIFIC DEFECT ATTACHMENTS:
  rails runner "
    defect = Defect.find_by(defect_unique: 'PSP-123')
    puts 'Issue files: ' + defect.attachments.count.to_s
    total_comment_files = defect.defect_messages.sum { |m| m.attachments.count }
    puts 'Comment files: ' + total_comment_files.to_s
  "

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PROBLEM: "DefectMessage does not support attachments"
FIX:     Add to app/models/defect_message.rb:
         has_many_attached :attachments

PROBLEM: "Storage directory is NOT writable"
FIX:     sudo chown -R $(whoami):$(whoami) storage/

PROBLEM: "Downloaded but not verified in storage"
FIX:     Check disk space: df -h storage/
         Check permissions: ls -la storage/

PROBLEM: Partial upload (2/3 files)
FIX:     Script will auto-retry. If still fails, re-run import.
         Script skips duplicates and retries only failed files.

PROBLEM: All downloads fail
FIX:     Check JIRA_API_TOKEN is valid
         Check network connectivity: ping craftsilicon.atlassian.net

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ SUCCESS CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

□ Per-issue summary shows correct total count
□ Issue-level downloads show ✅ OK for all files
□ Comment-level downloads show ✅ OK for all files
□ Issue-level summary: Failed = 0
□ Comment summary: All X file(s) uploaded and verified
□ Final verification: All X attachment(s) verified successfully
□ No ❌ FAILED or ⚠️ PARTIAL indicators
□ Total count = Issue-level + Comment-level

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📚 DOCUMENTATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ENHANCED_ATTACHMENT_REPORTING.md
  → Complete guide to new features

ATTACHMENT_REPORTING_COMPLETE.md
  → Summary of what was delivered

COMMENT_ATTACHMENTS_INTEGRATION.md
  → Technical details on integration

INTEGRATION_SUMMARY.md
  → Overall integration status

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

