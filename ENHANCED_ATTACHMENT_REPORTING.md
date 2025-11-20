# Enhanced Attachment Reporting - Complete Guide

## What Was Added

I've enhanced `import_jira_with_modules.rb` with **comprehensive per-issue attachment statistics and detailed download progress tracking**. The script now shows exactly what happens to every attachment.

## New Features

### 1. ✅ Per-Issue Attachment Summary (Before Import)

For **each Jira issue**, you now see:

```
================================================================================
📎 ATTACHMENTS FOR PSP-123
================================================================================
Total attachments in Jira: 8

Attachment Details:
  1. screenshot1.png (2.5 MB, created: 2025-01-15T10:30:00.000Z)
  2. error_log.txt (0.15 MB, created: 2025-01-15T10:32:00.000Z)
  3. database_dump.sql (45.2 MB, created: 2025-01-15T11:00:00.000Z)
  4. test_report.pdf (3.8 MB, created: 2025-01-15T14:20:00.000Z)
  5. screenshot2.png (1.9 MB, created: 2025-01-15T15:45:00.000Z)
  6. config_file.yml (0.02 MB, created: 2025-01-15T15:46:00.000Z)
  7. architecture_diagram.png (5.1 MB, created: 2025-01-16T09:15:00.000Z)
  8. notes.txt (0.05 MB, created: 2025-01-16T09:16:00.000Z)

Attachment Categorization:
  Comment-level attachments: 3
    1. screenshot2.png (1.9 MB) → Will attach to comment
    2. config_file.yml (0.02 MB) → Will attach to comment
    3. notes.txt (0.05 MB) → Will attach to comment
  Issue-level attachments: 5
    1. screenshot1.png (2.5 MB) → Will attach to defect
    2. error_log.txt (0.15 MB) → Will attach to defect
    3. database_dump.sql (45.2 MB) → Will attach to defect
    4. test_report.pdf (3.8 MB) → Will attach to defect
    5. architecture_diagram.png (5.1 MB) → Will attach to defect
```

**What It Shows**:
- ✅ Total number of attachments found in Jira
- ✅ Each file's name, size, and creation timestamp
- ✅ Which files will attach to the defect record
- ✅ Which files will attach to specific comments
- ✅ Clear categorization so you know where each file goes

### 2. ✅ Real-Time Issue-Level Attachment Download Progress

When downloading attachments for the defect itself:

```
📥 DOWNLOADING ISSUE-LEVEL ATTACHMENTS FOR PSP-123
   Total files: 5 (57.63 MB)

   [1/5] 📥 Downloading screenshot1.png (2.5 MB)... ✅ OK (1.23s, stored: abc123def456789...)
   [2/5] 📥 Downloading error_log.txt (0.15 MB)... ✅ OK (0.34s, stored: def456ghi789abc...)
   [3/5] 📥 Downloading database_dump.sql (45.2 MB)... ✅ OK (23.45s, stored: ghi789jkl012def...)
   [4/5] 📥 Downloading test_report.pdf (3.8 MB)... ✅ OK (2.11s, stored: jkl012mno345ghi...)
   [5/5] 📥 Downloading architecture_diagram.png (5.1 MB)... ✅ OK (2.67s, stored: mno345pqr678jkl...)

Issue-level attachment summary for PSP-123:
  ✅ Uploaded: 5
  ⏭️  Skipped: 0
  ❌ Failed: 0
```

**What It Shows**:
- ✅ Progress indicator ([1/5], [2/5], etc.)
- ✅ Download status (📥 = downloading)
- ✅ File name and size for each file
- ✅ Download duration in seconds
- ✅ Storage key (first 16 chars) to verify file location
- ✅ Final summary: uploaded, skipped, failed counts

**Status Indicators**:
- ✅ **OK** - Downloaded, uploaded, and verified in storage
- ⏭️ **SKIP** - File already exists (duplicate)
- ❌ **FAILED** - Download or upload error
- ⚠️ **PARTIAL** - Downloaded but not verified in storage

### 3. ✅ Real-Time Comment Attachment Download Progress

When downloading attachments for comments:

```
📎 DOWNLOADING COMMENT ATTACHMENTS
   Comment ID: 12345 (Jira: 67890)
   Files: 3 (1.97 MB total)

  [1/3] 📥 screenshot2.png (1.9 MB)... ✅ OK (1.05s, abc123def456...)
  [2/3] 📥 config_file.yml (0.02 MB)... ✅ OK (0.12s, def456ghi789...)
  [3/3] 📥 notes.txt (0.05 MB)... ✅ OK (0.08s, ghi789jkl012...)

   Comment attachment summary for comment 12345:
     ✅ All 3 file(s) uploaded and verified
```

**What It Shows**:
- ✅ Which comment the files belong to (both internal ID and Jira ID)
- ✅ Total number of files and total size
- ✅ Progress for each file download
- ✅ Verification that all files uploaded successfully

### 4. ✅ Automatic Retry with Progress

If a download fails, you see the retry attempt:

```
📎 DOWNLOADING COMMENT ATTACHMENTS
   Comment ID: 12345 (Jira: 67890)
   Files: 3 (25.5 MB total)

  [1/3] 📥 large_file1.zip (10.5 MB)... ✅ OK (8.23s, abc123...)
  [2/3] 📥 large_file2.zip (12.0 MB)... ❌ FAILED (HTTP 500)
  [3/3] 📥 large_file3.zip (3.0 MB)... ✅ OK (2.15s, def456...)

   ⚠️  Comment attachment summary for comment 12345:
     Partial upload: 2/3 file(s)

   🔄 RETRY: Attempting 1 missing file(s) (attempt 1/2)
     Missing: large_file2.zip

  [1/1] 📥 large_file2.zip (12.0 MB)... ✅ OK (9.87s, ghi789...)

   Retry results:
     Uploaded: 1, Failed: 0

   ✅ All files uploaded after retry
```

**What It Shows**:
- ✅ Which files failed on first attempt
- ✅ Automatic retry (up to 2 attempts)
- ✅ Retry results
- ✅ Final success confirmation

### 5. ✅ Clear Error Messages

If uploads fail after all retries:

```
   ❌ INCOMPLETE: 2/3 files for comment 12345 on PSP-123
      Re-run import to retry failed uploads
```

## How Attachments Are Placed

### Issue-Level Attachments → Defect Record

```ruby
# Stored in: active_storage_attachments
# Where: record_type = 'Defect', record_id = defect.id

defect.attachments.attach(io: file, filename: filename)
```

**Storage Location**: `storage/ab/cd/abcd1234...` (organized by blob key)

**Database Records**:
- `active_storage_blobs` - file metadata (size, checksum, content type)
- `active_storage_attachments` - links blob to defect

**UI Location**: Defect detail page, main attachments section

### Comment-Level Attachments → DefectMessage Record

```ruby
# Stored in: active_storage_attachments
# Where: record_type = 'DefectMessage', record_id = defect_message.id

defect_message.attachments.attach(io: file, filename: filename)
```

**Storage Location**: `storage/ef/gh/efgh5678...` (organized by blob key)

**Database Records**:
- `active_storage_blobs` - file metadata
- `active_storage_attachments` - links blob to defect_message

**UI Location**: Comment section, shown inline with comment text

## Example Full Output

Here's what you see for a typical issue with both types of attachments:

```bash
Processing issue 5/150: PSP-123

================================================================================
📎 ATTACHMENTS FOR PSP-123
================================================================================
Total attachments in Jira: 8

Attachment Details:
  1. screenshot1.png (2.5 MB, created: 2025-01-15T10:30:00.000Z)
  2. error_log.txt (0.15 MB, created: 2025-01-15T10:32:00.000Z)
  3. database_dump.sql (45.2 MB, created: 2025-01-15T11:00:00.000Z)
  4. test_report.pdf (3.8 MB, created: 2025-01-15T14:20:00.000Z)
  5. screenshot2.png (1.9 MB, created: 2025-01-15T15:45:00.000Z)
  6. config_file.yml (0.02 MB, created: 2025-01-15T15:46:00.000Z)
  7. architecture_diagram.png (5.1 MB, created: 2025-01-16T09:15:00.000Z)
  8. notes.txt (0.05 MB, created: 2025-01-16T09:16:00.000Z)

Attachment Categorization:
  Comment-level attachments: 3
    1. screenshot2.png (1.9 MB) → Will attach to comment
    2. config_file.yml (0.02 MB) → Will attach to comment
    3. notes.txt (0.05 MB) → Will attach to comment
  Issue-level attachments: 5
    1. screenshot1.png (2.5 MB) → Will attach to defect
    2. error_log.txt (0.15 MB) → Will attach to defect
    3. database_dump.sql (45.2 MB) → Will attach to defect
    4. test_report.pdf (3.8 MB) → Will attach to defect
    5. architecture_diagram.png (5.1 MB) → Will attach to defect

[IMPORT] Created defect PSP-123 id=456

📥 DOWNLOADING ISSUE-LEVEL ATTACHMENTS FOR PSP-123
   Total files: 5 (57.63 MB)

   [1/5] 📥 Downloading screenshot1.png (2.5 MB)... ✅ OK (1.23s, stored: abc123def456789...)
   [2/5] 📥 Downloading error_log.txt (0.15 MB)... ✅ OK (0.34s, stored: def456ghi789abc...)
   [3/5] 📥 Downloading database_dump.sql (45.2 MB)... ✅ OK (23.45s, stored: ghi789jkl012def...)
   [4/5] 📥 Downloading test_report.pdf (3.8 MB)... ✅ OK (2.11s, stored: jkl012mno345ghi...)
   [5/5] 📥 Downloading architecture_diagram.png (5.1 MB)... ✅ OK (2.67s, stored: mno345pqr678jkl...)

Issue-level attachment summary for PSP-123:
  ✅ Uploaded: 5
  ⏭️  Skipped: 0
  ❌ Failed: 0

[COMMENTS] Importing 2 comment(s) for PSP-123...
[IMPORT] Added comment by John Doe to PSP-123 (id=12345)

📎 DOWNLOADING COMMENT ATTACHMENTS
   Comment ID: 12345 (Jira: 67890)
   Files: 3 (1.97 MB total)

  [1/3] 📥 screenshot2.png (1.9 MB)... ✅ OK (1.05s, abc123def456...)
  [2/3] 📥 config_file.yml (0.02 MB)... ✅ OK (0.12s, def456ghi789...)
  [3/3] 📥 notes.txt (0.05 MB)... ✅ OK (0.08s, ghi789jkl012...)

   Comment attachment summary for comment 12345:
     ✅ All 3 file(s) uploaded and verified

[VERIFY] ======================================================================
[VERIFY] Final verification for defect: PSP-123
[VERIFY] ======================================================================
[VERIFY] Issue-level attachments: 5 file(s)
[VERIFY]   Files: screenshot1.png, error_log.txt, database_dump.sql, test_report.pdf, architecture_diagram.png
[VERIFY]   ✅ All issue-level files verified in storage
[VERIFY] Comment-level attachments:
[VERIFY]   Total comments: 2
[VERIFY]   Comments with attachments: 1
[VERIFY]   Total attachment files: 3
[VERIFY]   Verified in storage: 3
[VERIFY]   ✅ All comment-level files verified in storage

[VERIFY] ✅ DEFECT PSP-123: All 8 attachment(s) verified successfully!
[VERIFY] ======================================================================
```

## Benefits

### For Monitoring
- ✅ **Real-time progress** - See exactly what's happening
- ✅ **Clear failures** - Know immediately if something fails
- ✅ **Retry visibility** - See automatic retries in action
- ✅ **Storage verification** - Confirm files actually saved

### For Debugging
- ✅ **Attachment categorization** - Know where each file goes
- ✅ **Download timing** - Identify slow/timeout issues
- ✅ **Storage keys** - Verify files in storage directory
- ✅ **Error context** - See which file/comment failed

### For Auditing
- ✅ **Complete statistics** - Total, uploaded, skipped, failed
- ✅ **Per-issue breakdown** - Exact count for each defect
- ✅ **Comment-level tracking** - Which comments have files
- ✅ **Verification proof** - Confirmed storage existence

## Running the Import

Same command as before:

```bash
rails runner scripts/import_jira_with_modules.rb --project PSP --verbose
```

**New Output Features**:
- Per-issue attachment summary (before import)
- Real-time download progress (with file counts)
- Storage verification (with blob keys)
- Clear success/failure indicators
- Automatic retry with progress
- Final verification summary

## What to Look For

### ✅ Success Indicators

**Issue-Level Attachments**:
```
Issue-level attachment summary for PSP-123:
  ✅ Uploaded: 5
  ⏭️  Skipped: 0
  ❌ Failed: 0
```

**Comment-Level Attachments**:
```
Comment attachment summary for comment 12345:
  ✅ All 3 file(s) uploaded and verified
```

**Final Verification**:
```
[VERIFY] ✅ DEFECT PSP-123: All 8 attachment(s) verified successfully!
```

### ⚠️ Warning Signs

**Partial Upload**:
```
⚠️  Comment attachment summary for comment 12345:
  Partial upload: 2/3 file(s)
```
**Action**: Script will automatically retry. Check final result.

**Failed Upload**:
```
❌ INCOMPLETE: 2/3 files for comment 12345 on PSP-123
   Re-run import to retry failed uploads
```
**Action**: Re-run import for this project. Script will skip duplicates and retry only failed files.

**Storage Issue**:
```
[1/5] 📥 Downloading file.pdf (5.0 MB)... ⚠️  PARTIAL (downloaded but not in storage)
```
**Action**: Check storage directory permissions and disk space.

## Database Schema Verification

### Ensure DefectMessage Has Attachments Support

```bash
# Check model
grep "has_many_attached :attachments" app/models/defect_message.rb
```

**Expected**:
```ruby
class DefectMessage < ApplicationRecord
  # ...existing code...
  has_many_attached :attachments  # ← Must have this
end
```

### Verify Storage Tables

```bash
rails runner "
  puts 'Defect attachments: ' + ActiveStorage::Attachment.where(record_type: 'Defect').count.to_s
  puts 'Comment attachments: ' + ActiveStorage::Attachment.where(record_type: 'DefectMessage').count.to_s
"
```

## Summary of Changes

### Modified Functions

1. **`import_issue_with_modules`** (Lines ~1800-1900)
   - Added per-issue attachment summary
   - Shows total count, file details, categorization

2. **`fetch_and_attach_attachments`** (Lines ~800-920)
   - Added progress indicators ([1/5], [2/5], etc.)
   - Shows download duration and storage key
   - Returns statistics (uploaded, skipped, failed)

3. **`fetch_and_attach_to_rich_text_jira`** (Lines ~1050-1250)
   - Added per-file progress for comment attachments
   - Shows which comment each file belongs to
   - Clear success/failure status

4. **`import_comments_for_defect`** (Lines ~1350-1500)
   - Added comment attachment summary header
   - Shows retry attempts and results
   - Clear final status (success/partial/failed)

### New Output Sections

1. **📎 ATTACHMENTS FOR {issue-key}** - Per-issue summary
2. **📥 DOWNLOADING ISSUE-LEVEL ATTACHMENTS** - Defect file progress
3. **📎 DOWNLOADING COMMENT ATTACHMENTS** - Comment file progress
4. **Comment attachment summary** - Per-comment results

## Files Remain Unchanged

- Storage location (still `storage/` directory)
- Database schema (still `active_storage_*` tables)
- Attachment matching logic (still 4 strategies)
- Retry logic (still up to 2 retries)
- Verification logic (still checks blob existence)

## Next Steps

1. ✅ Run import with enhanced output:
   ```bash
   rails runner scripts/import_jira_with_modules.rb --project PSP --verbose
   ```

2. ✅ Watch for attachment summaries in output

3. ✅ Verify final counts match Jira:
   - Check "Total attachments in Jira: X"
   - Check "Issue-level attachments: Y"
   - Check "Comment-level attachments: Z"
   - Verify X = Y + Z

4. ✅ Check final verification shows 100% success:
   ```
   [VERIFY] ✅ DEFECT PSP-123: All X attachment(s) verified successfully!
   ```

5. ✅ If any failures, re-run import to retry

---

**Status**: ✅ **COMPLETE**

The import script now provides **complete visibility** into attachment downloads, showing exactly which files go where, real-time progress for each download, and verification that all files are correctly stored in ActiveStorage.

