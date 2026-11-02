# Feature Specification: File Organizer and Duplicate Finder for macOS

**Feature Branch**: `001-file-organizer`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "File organizer and duplicate finder for macOS using ZSH with jdupes and exiftool integration. A script to organize backups from multiple old phones on an external hard drive. Must categorize files (images, videos, audio, documents), handle duplicates, preserve backup context via subfolders, rename files using EXIF dates, and log all operations."

## User Scenarios & Testing

### User Story 1 - Scan and Organize Files by Category (Priority: P1)
As a user with a messy external hard drive full of phone backups, I want to scan a source folder and copy all files into a structured destination organized by file type (Images, Videos, Audio, Documents), so that I can easily browse my media.

**Why this priority**: This is the core value proposition - turning chaos into structure.

**Independent Test**: Can be fully tested by pointing the script at a folder with mixed file types and verifying they appear in the correct category folders at the destination.

**Acceptance Scenarios**:
1. **Given** a source folder containing JPG, MP4, MP3, PDF files, **When** I run the organize command, **Then** files are copied to `Destination/Images/`, `Destination/Videos/`, `Destination/Audio/`, `Destination/Documents/` respectively.
2. **Given** files with HEIC and MOV extensions (iPhone formats), **When** organized, **Then** they are correctly categorized as Images and Videos.

### User Story 2 - Preserve Backup Context with Subfolders (Priority: P1)
As a user with multiple phone backups, I want to specify a backup name (e.g., "iPhone_6_Backup") so that organized files go into `Category/Backup_Name/` subfolders, so I know which device each file came from.

**Why this priority**: Critical for managing multiple device backups without mixing them up.

**Independent Test**: Run script with backup name "iPhone_X_Backup" and verify files land in `Images/iPhone_X_Backup/`.

**Acceptance Scenarios**:
1. **Given** I enter "Pixel_3_Backup" as the backup identifier, **When** files are organized, **Then** they appear under `Destination/Images/Pixel_3_Backup/`, `Destination/Videos/Pixel_3_Backup/`, etc.

### User Story 3 - Detect and Report Duplicate Files (Priority: P1)
As a user with many duplicate photos across backups, I want the script to scan for bit-identical files using jdupes and show me a report before taking action, so I can reclaim space safely.

**Why this priority**: Duplicate detection is the main pain point - user explicitly mentioned "muchas fotos duplicadas entre backups".

**Independent Test**: Create two identical files with different names in source, run duplicate scan, verify both are detected and reported.

**Acceptance Scenarios**:
1. **Given** source contains `photo.jpg` and `copy_of_photo.jpg` with identical content, **When** I run duplicate scan, **Then** both files are listed in the duplicate report.
2. **Given** duplicate scan completes, **When** I review the report, **Then** I can choose to keep one copy and move/delete the others.

### User Story 4 - Smart Rename Using EXIF Metadata (Priority: P2)
As a user with files named `IMG_0001.JPG` from different phones, I want files renamed to `YYYYMMDD_HHMMSS.ext` based on their actual capture date from EXIF data, so filenames are unique and chronological.

**Why this priority**: Solves filename collisions and makes browsing intuitive.

**Independent Test**: Provide a JPEG with EXIF date "2023:10:25 14:30:05", run organize with renaming enabled, verify output filename is `20231025_143005.jpg`.

**Acceptance Scenarios**:
1. **Given** a photo with valid EXIF DateTimeOriginal, **When** organized with renaming, **Then** the destination file is named `YYYYMMDD_HHMMSS.jpg`.
2. **Given** a file without EXIF data (e.g., screenshot), **When** organized, **Then** it keeps its original name or uses filesystem date as fallback.

### User Story 5 - Clean Empty Folders and Log Operations (Priority: P2)
As a user, I want the script to optionally remove empty folders left behind in the source after copying, and generate a detailed log file, so my source drive is cleaned up and I have an audit trail.

**Why this priority**: Housekeeping and auditability for large operations.

**Independent Test**: Create nested empty folders in source, run organize with cleanup enabled, verify empty folders are removed. Check `management_log.txt` for entries.

**Acceptance Scenarios**:
1. **Given** source has empty folders after file copy, **When** cleanup runs, **Then** those empty folders are deleted.
2. **Given** any operation completes, **When** I check `Destination/management_log.txt`, **Then** it contains timestamped entries for each file copied, renamed, or skipped.

---

## Requirements

### Functional Requirements

- **FR-001**: System MUST scan a user-specified source directory recursively for all files.
- **FR-002**: System MUST categorize files into: Images, Videos, Audio, Documents, Others based on file extension.
- **FR-003**: System MUST accept a user-provided backup identifier to create subfolder structure: `Destination/Category/Backup_ID/`.
- **FR-004**: System MUST copy (not move) files by default to preserve source data.
- **FR-005**: System MUST integrate `jdupes` to detect bit-identical duplicate files across the source tree.
- **FR-006**: System MUST present a duplicate report showing groups of identical files before any deletion.
- **FR-007**: System MUST allow user to select which duplicate copies to keep/remove.
- **FR-008**: System MUST integrate `exiftool` to extract capture date from image/video metadata.
- **FR-009**: System MUST rename files to `YYYYMMDD_HHMMSS.ext` format when EXIF date is available.
- **FR-010**: System MUST fall back to original filename or filesystem modification date when EXIF is absent.
- **FR-011**: System MUST optionally remove empty directories from source after successful copy.
- **FR-012**: System MUST generate a log file `management_log.txt` in the destination root with timestamped operations.
- **FR-013**: System MUST check for required dependencies (`jdupes`, `exiftool`) and prompt to install via Homebrew if missing.
- **FR-014**: System MUST provide an interactive menu in the terminal (Ghostty compatible) with colored output.
- **FR-015**: System MUST handle filenames with spaces, special characters, and Unicode correctly.

### Key Entities

- **Source Directory**: The user-selected folder containing raw backups (read-only during copy phase).
- **Destination Directory**: The user-selected folder where organized structure is created.
- **Backup Identifier**: User-provided string (e.g., "iPhone_8_2021") used as subfolder name.
- **File Record**: Represents a single file with attributes: source path, destination path, category, hash, EXIF date, size.
- **Duplicate Group**: A set of 2+ File Records with identical content hash.
- **Operation Log**: Append-only text file recording every copy, rename, skip, and delete action.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Script organizes 10,000+ files in under 5 minutes on M2 MacBook Air (using jdupes for duplicates).
- **SC-002**: Duplicate detection finds 100% of bit-identical files (verified by manual spot-check).
- **SC-003**: EXIF renaming correctly applies to 95%+ of photos with valid metadata.
- **SC-004**: Zero data loss - source files remain intact after copy operation (verified by file count comparison).
- **SC-005**: Log file contains one entry per processed file with action taken.

---

## Assumptions

- User is on macOS (Apple Silicon M2) with Homebrew installed.
- User has Ghostty terminal (supports ANSI colors).
- Source files are on a locally mounted external drive (not network).
- `jdupes` and `exiftool` are available via Homebrew (`brew install jdupes exiftool`).
- User has read access to source and write access to destination.
- Backups are from iOS/Android devices (common formats: HEIC, MOV, JPG, MP4).
- Script runs in ZSH (default shell on macOS).

---

## Edge Cases

- What happens when two different files have the same EXIF timestamp? → Append counter: `20231025_143005_1.jpg`, `20231025_143005_2.jpg`.
- How does system handle read-only files or permission errors? → Log error, skip file, continue processing.
- What if destination already has a file with the same target name? → Compare hashes; if identical, skip. If different, append counter.
- How does system handle very large files (>4GB)? → Use `cp` with appropriate flags; jdupes handles large files natively.
- What if user cancels mid-operation? → Log partial progress; allow resume by skipping already-copied files (check destination exists).
- How to handle symbolic links in source? → Follow links and copy the target file (default `cp` behavior).