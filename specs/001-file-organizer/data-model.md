# Data Model: File Organizer and Duplicate Finder

## Core Entities

### Config (Global State)
Represents the user's choices for a single run.

| Field | Type | Description |
|-------|------|-------------|
| `source_dir` | string | Absolute path to source directory (read-only) |
| `dest_dir` | string | Absolute path to destination root |
| `backup_id` | string | User-provided identifier (e.g., "iPhone_8_2021") |
| `mode` | enum | `organize`, `duplicates`, `full` |
| `copy_mode` | boolean | `true` = copy (default), `false` = move |
| `rename_enabled` | boolean | Enable EXIF-based renaming |
| `cleanup_enabled` | boolean | Remove empty dirs in source after copy |
| `dry_run` | boolean | Preview only, no filesystem changes |

### FileRecord (Implicit - passed via pipelines)
Represents a single file being processed. Not stored as struct - flows through pipes.

| Field | Type | Source |
|-------|------|--------|
| `src_path` | string | `find` output |
| `dest_path` | string | Computed: `$dest_dir/$category/$backup_id/$new_name` |
| `category` | enum | `images`, `videos`, `audio`, `documents`, `others` |
| `ext` | string | Lowercase extension (e.g., "jpg") |
| `size` | int | Bytes (from `stat`) |
| `hash` | string | MD5/xxHash (from `jdupes`) |
| `exif_date` | string | `YYYY:MM:DD HH:MM:SS` from exiftool |
| `new_name` | string | `YYYYMMDD_HHMMSS.ext` or original |

### DuplicateGroup
A collection of FileRecords sharing the same content hash.

| Field | Type | Description |
|-------|------|-------------|
| `hash` | string | Content hash (MD5) |
| `files` | array[FileRecord] | 2+ files with identical content |
| `action` | enum | `keep_first`, `keep_newest`, `keep_oldest`, `manual`, `skip` |

### OperationLogEntry
Single line in `management_log.txt`.

| Field | Type | Format |
|-------|------|--------|
| `timestamp` | string | `YYYY-MM-DD HH:MM:SS` |
| `action` | enum | `COPY`, `RENAME`, `SKIP_DUP`, `SKIP_EXIST`, `ERROR`, `CLEANUP_DIR` |
| `src_path` | string | Relative or absolute source path |
| `dest_path` | string | Destination path (if applicable) |
| `details` | string | Extra info (hash, exif_date, error msg) |

Example log line:
```
2026-11-01 15:30:45 | COPY | /Volumes/Backup/DCIM/IMG_001.JPG | /Users/jonathan/Organized/Images/iPhone_8_Backup/20231025_143005.jpg | hash=a1b2c3d4 exif=2023:10:25 14:30:05
```

## Category Mapping

| Category | Extensions |
|----------|------------|
| `images` | jpg, jpeg, png, gif, heic, heif, webp, raw, cr2, nef, arw, dng, tiff, tif, bmp |
| `videos` | mp4, mov, avi, mkv, m4v, 3gp, mpg, mpeg, wmv, flv, webm |
| `audio` | mp3, wav, aac, flac, m4a, ogg, wma, aiff, aif |
| `documents` | pdf, doc, docx, txt, xls, xlsx, ppt, pptx, md, rtf, odt, ods, odp |
| `others` | (fallback for unrecognized extensions) |

## State Transitions

```
Config Init → Dependency Check → Source Scan → Duplicate Scan (optional)
    → User Confirmation → File Processing Loop → Cleanup → Log Finalization
```

File Processing Loop per file:
```
Find File → Categorize → Get EXIF (if rename) → Compute Dest Path
    → Check Duplicate (if mode) → Check Dest Exists → Copy/Rename → Log
```

## Storage

- **Config**: In-memory variables (ZSH associative arrays)
- **File Records**: Streamed via pipes between functions (no persistent storage)
- **Duplicate Groups**: Parsed from `jdupes` JSON output into ZSH arrays
- **Logs**: Append-only text file at `$dest_dir/management_log.txt`