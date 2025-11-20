# Comment Attachments Integration - Complete Guide

## Overview
The `import_jira_with_modules.rb` script has been enhanced with **comprehensive comment attachment verification** to ensure all files from Jira comments are properly downloaded and stored in ActiveStorage.

## What Was Changed

### ✅ Integration Complete
The verification logic from `verify_and_fix_comment_attachments.rb` has been **fully integrated** into `import_jira_with_modules.rb`. You now have a **single unified script** that:

1. **Imports all Jira data** (defects, comments, attachments, labels, history)
2. **Downloads comment attachments** from Jira during import
3. **Stores attachments** using ActiveStorage with `has_many_attached :attachments` on DefectMessage
4. **Verifies uploads in real-time** (during import, per defect)
5. **Runs deep post-import verification** (after all imports complete)
6. **Provides detailed diagnostics** for any missing files

## How It Works

### 1. Comment Attachment Matching (Lines 1850-1940)
The script intelligently matches Jira attachments to specific comments using **4 strategies**:

```ruby
# Strategy 1: Direct comment.attachment array from Jira
if c.key?('attachment') && c['attachment'].is_a?(Array)
  # Use Jira's explicit attachment reference
end

# Strategy 2: Match by attachment ID
if c.key?('attachment_ids')
  # Match attachments by their Jira IDs
end

# Strategy 3: Match by creation time proximity (±5 minutes)
if (att_created - comment_created).abs < 300
  # Tight time window to ensure correct grouping
end

# Strategy 4: Match by filename in comment body text
if body_text.include?(filename)
  # Filename mentioned in comment = likely attached
end
```

**Result**: Comment attachments are separated from issue-level attachments and attached to the correct DefectMessage records.

### 2. Real-Time Upload Verification (Lines 2230-2340)
Each comment attachment is verified **immediately after upload**:

```ruby
# Attach file to DefectMessage
File.open(tmp.path, 'rb') do |file|
  rich_record.attachments.attach(io: file, filename: filename, content_type: content_type)
end

# Verify upload succeeded
rich_record.reload
attached = rich_record.attachments.find { |a| a.filename.to_s == filename }
exists = ActiveStorage::Blob.service.exist?(attached.blob.key)

if exists
  vputs "✅ Attached and verified: #{filename}"
  stats[:uploaded] += 1
else
  warn "⚠️ Blob created but file missing from storage!"
  stats[:failed] += 1
end
```

**Retry Logic**: Failed uploads are retried up to 2 times with exponential backoff.

### 3. Post-Import Deep Verification (NEW - Lines 3060-3220)
After all imports complete, a **comprehensive storage check** runs:

```ruby
# Check every DefectMessage attachment in the database
imported_defects.find_each do |defect|
  defect.defect_messages.each do |message|
    message.attachments.each do |attachment|
      # Verify physical file exists in ActiveStorage
      exists = ActiveStorage::Blob.service.exist?(attachment.blob.key)
      
      if exists
        ✅ verified_attachments += 1
      else
        ⚠️ missing_attachments += 1
        # Record detailed info for diagnostics
      end
    end
  end
end
```

**Output**: Detailed report showing:
- Total attachments in database vs verified in storage
- Which defects have missing files
- Exact filenames and message IDs of missing files
- Storage diagnostics (path, permissions, disk space)

## Usage

### Basic Import with Verification
```bash
# Import with full verification enabled
rails runner scripts/import_jira_with_modules.rb \
  --project PSP,KCBL,FLOW \
  --verbose
```

### What You'll See

#### During Import (Per-Defect Verification)
```
[ATTACH] Attaching 3 file(s) (12.5 MB total) to comment 12345...
  [OK] Attached comment file 'screenshot.png' to DefectMessage 12345 (5.2 MB, blob_key=abc123, storage=/path/to/storage)
  [OK] Attached comment file 'log.txt' to DefectMessage 12345 (2.1 MB, blob_key=def456, storage=/path/to/storage)
  [OK] Attached comment file 'report.pdf' to DefectMessage 12345 (5.2 MB, blob_key=ghi789, storage=/path/to/storage)
  [OK] Successfully attached all 3 file(s) to comment 12345
    - Uploaded: 3, Skipped: 0, Failed: 0
```

#### After Import (Deep Verification)
```
🔍 Running deep comment attachment verification...
  Verified storage for 50/150 defects...
  Verified storage for 100/150 defects...
  Verified storage for 150/150 defects...

========================================
COMMENT ATTACHMENT STORAGE VERIFICATION SUMMARY
========================================
Defects checked: 150
Defects with comments: 142
Total comments: 856
Comments with attachments: 234

Total attachment records in DB: 687
Verified in storage: 687 (100.0%)
Missing from storage: 0 (0.0%)

✅ All comment-level attachments verified successfully in storage!

All 687 attachment file(s) are present in ActiveStorage.
========================================
```

#### If Issues Found
```
⚠️  3 defect(s) have comment attachments missing from storage:
   - PSP-123: 2 missing file(s)
   - PSP-456: 1 missing file(s)
   - PSP-789: 3 missing file(s)

RECOMMENDED ACTION:
1. Re-run the import for affected defects to retry failed uploads:
   rails runner scripts/import_jira_with_modules.rb --project PSP --verbose

2. Check storage configuration and permissions (see diagnostics below)

========================================
STORAGE DIAGNOSTIC INFORMATION
========================================
Storage Service: ActiveStorage::Service::DiskService
Storage Root: /home/user/app/storage
Rails Environment: production

✅ Storage directory exists: /home/user/app/storage
✅ Storage directory is writable

Possible causes for missing files:
1. Import was interrupted before files finished uploading
2. Storage directory was deleted or moved after import
3. Permissions prevented file writing during import
4. Network issues during download from Jira
5. Database was restored but storage files were not
6. Insufficient disk space during upload
========================================
```

## Database Schema

### DefectMessage Model
The script expects DefectMessage to have:

```ruby
class DefectMessage < ApplicationRecord
  belongs_to :defect
  belongs_to :user
  has_rich_text :content  # ActionText for comment body
  has_many_attached :attachments  # ⬅️ CRITICAL: Comment attachments stored here
end
```

### Storage Tables
ActiveStorage creates these records automatically:

```
active_storage_blobs (stores file metadata)
  - id
  - key (unique storage identifier)
  - filename
  - content_type
  - byte_size
  - checksum
  - created_at

active_storage_attachments (links blobs to records)
  - id
  - name ('attachments')
  - record_type ('DefectMessage')  ⬅️ Comment attachments
  - record_id (defect_message.id)
  - blob_id
  - created_at
```

## File Storage Location

### Default Disk Storage
```
storage/
├── ab/
│   └── cd/
│       └── abcd1234efgh5678...  (actual file, named by blob key)
├── ef/
│   └── gh/
│       └── efgh5678ijkl9012...
...
```

Each file is stored with its `blob.key` as the filename, organized in subdirectories based on the first 4 characters of the key.

## Troubleshooting

### Problem: "DefectMessage does not support attachments"
**Cause**: Missing `has_many_attached :attachments` in model

**Fix**:
```ruby
# app/models/defect_message.rb
class DefectMessage < ApplicationRecord
  # ...existing code...
  has_many_attached :attachments  # ⬅️ Add this line
end
```

### Problem: "Blob record created but file not found in storage"
**Causes**:
1. Disk full during upload
2. Permissions issue writing to storage directory
3. Network timeout downloading from Jira
4. Process killed mid-upload

**Fix**:
```bash
# Check disk space
df -h /home/user/app/storage

# Check permissions
ls -la /home/user/app/storage
sudo chown -R $(whoami):$(whoami) /home/user/app/storage

# Re-run import to retry failed uploads
rails runner scripts/import_jira_with_modules.rb --project PSP --verbose
```

### Problem: Attachments show in DB but 404 when viewing
**Cause**: Physical files missing from storage directory

**Verification**:
```bash
# Run verification script
rails runner scripts/import_jira_with_modules.rb --project PSP --verbose

# Or run standalone verification (if you kept the old script)
rails runner scripts/verify_and_fix_comment_attachments.rb --check-all --verbose
```

**Fix**: Re-run import to re-download missing files.

## Performance Considerations

### Large Imports
For imports with thousands of attachments:

1. **Network**: Downloads are throttled (0.5s-2s between files)
2. **Disk I/O**: Files written to tempfiles first, then moved
3. **Memory**: Tempfiles prevent large memory usage
4. **Timeouts**: Increased to 10 minutes for very large files

### Typical Performance
- **Small files** (<1MB): ~2-3 seconds per file
- **Medium files** (1-10MB): ~5-15 seconds per file
- **Large files** (>10MB): ~30-120 seconds per file

Example: 100 defects with 500 comment attachments (avg 2MB each) ≈ **45-60 minutes** total import time.

## Verification Only (No Import)

If you want to **only verify** existing attachments without importing:

```bash
# Check all defects
rails runner scripts/verify_and_fix_comment_attachments.rb --check-all --verbose

# Check specific defect
rails runner scripts/verify_and_fix_comment_attachments.rb --defect-unique PSP-123 --verbose

# Check by ID
rails runner scripts/verify_and_fix_comment_attachments.rb --defect-id 456 --verbose
```

## Success Indicators

### ✅ Successful Import
1. **Real-time verification**: "✅ All N file(s) to comment M"
2. **Post-import verification**: "100.0% verified in storage"
3. **No warnings**: Only `info` and `✅` messages
4. **File counts match**: Jira attachments = DB records = Storage files

### ⚠️ Issues to Watch For
1. **Partial uploads**: "Attached 2/3 file(s) to comment"
2. **Missing files**: "0.0% verified in storage"
3. **Storage errors**: "Storage directory is NOT writable"
4. **Download failures**: "Unable to download attachment (HTTP 404)"

## Migration from Old Script

The standalone `verify_and_fix_comment_attachments.rb` script is **no longer needed** if you're using the enhanced `import_jira_with_modules.rb`. However, you can keep it for:

1. **Quick verification** without full import
2. **Debugging** specific defects
3. **Monitoring** in production (scheduled checks)

Both scripts use the **same verification logic**, so results will be consistent.

## Summary

### What's Automated
- ✅ Matching attachments to comments
- ✅ Downloading from Jira
- ✅ Storing in ActiveStorage
- ✅ Real-time verification (per-defect)
- ✅ Deep post-import verification (all defects)
- ✅ Retry logic (up to 2 retries)
- ✅ Detailed diagnostics

### What You Need to Do
1. Ensure `has_many_attached :attachments` in DefectMessage model
2. Ensure storage directory exists and is writable
3. Run import: `rails runner scripts/import_jira_with_modules.rb --project <KEY> --verbose`
4. Review verification output at end of import
5. Re-run import if any files missing (script will skip duplicates and retry only failed uploads)

### Expected Outcome
After running the import script, you should see:
- All comment attachments downloaded from Jira
- Files stored in `storage/` directory (organized by blob key)
- Database records in `active_storage_attachments` with `record_type='DefectMessage'`
- 100% verification rate in post-import check
- Comments with attachments visible in UI (Trix editor shows attached files)

