# Quickstart: File Organizer and Duplicate Finder

## Prerequisites

- macOS 14+ (Sonoma) on Apple Silicon (M1/M2/M3)
- Homebrew installed
- ZSH (default shell)
- Ghostty terminal (recommended for best color support)

## Installation

```bash
# 1. Install dependencies
brew install jdupes exiftool

# 2. Clone or navigate to project
cd /path/to/file-management

# 3. Make script executable
chmod +x organize.zsh

# 4. Run the script
./organize.zsh
```

## Usage Walkthrough

### First Run

```bash
$ ./organize.zsh

╔═══════════════════════════════════════════════════════════════════╗
║              FILE ORGANIZER & DUPLICATE FINDER                    ║
║                         macOS M2 Edition                          ║
╚═══════════════════════════════════════════════════════════════════╝

[1] Select Source Directory
    → Drag & drop folder from Finder into Ghostty, or type path
    → Example: /Volumes/ExternalDrive/PhoneBackups

[2] Select Destination Directory
    → Where organized files will be copied
    → Example: ~/Pictures/OrganizedBackups

[3] Enter Backup Identifier
    → Name for this backup batch (creates subfolders)
    → Example: iPhone_8_Backup_2021

[4] Choose Operation Mode
    ┌─────────────────────────────────────────────┐
    │  [1] Full Process (Duplicates + Organize)   │  ← Recommended
    │  [2] Find Duplicates Only                   │
    │  [3] Organize Only (Skip Duplicate Scan)    │
    └─────────────────────────────────────────────┘

[5] Configure Options
    ┌─────────────────────────────────────────────┐
    │  ☑ Smart Rename (EXIF dates)                │
    │  ☑ Clean Empty Folders (after copy)         │
    │  ☐ Dry Run (Preview Only)                   │
    └─────────────────────────────────────────────┘

[6] Confirm & Run
    → Review summary, press Enter to start
```

### Example Session

```bash
$ ./organize.zsh

════════════════════════════════════════════════════════════════════
  FILE ORGANIZER & DUPLICATE FINDER - macOS M2 Edition
════════════════════════════════════════════════════════════════════

[INFO] Checking dependencies...
[OK] jdupes found: /opt/homebrew/bin/jdupes
[OK] exiftool found: /opt/homebrew/bin/exiftool

📁 SOURCE DIRECTORY
Drag folder here or type path: /Volumes/MyPassport/OldPhoneBackups
✓ Source set: /Volumes/MyPassport/OldPhoneBackups

📁 DESTINATION DIRECTORY
Drag folder here or type path: ~/Pictures/OrganizedPhotos
✓ Destination set: /Users/jonathan/Pictures/OrganizedPhotos

🏷️  BACKUP IDENTIFIER
Enter name for this backup (e.g., iPhone_6_Backup): iPhone_XS_Backup_2020
✓ Backup ID: iPhone_XS_Backup_2020

⚙️  OPERATION MODE
[1] Full Process (Duplicates + Organize)  ← SELECTED
[2] Find Duplicates Only
[3] Organize Only

🔧 OPTIONS
[1] Smart Rename (EXIF)        : ON
[2] Clean Empty Folders        : ON
[3] Dry Run                    : OFF

📋 SUMMARY
Source:      /Volumes/MyPassport/OldPhoneBackups
Destination: /Users/jonathan/Pictures/OrganizedPhotos
Backup ID:   iPhone_XS_Backup_2020
Mode:        Full Process
Options:     Smart Rename, Clean Empty Folders

Press Enter to start or Ctrl+C to cancel...

[SCAN] Scanning for duplicates with jdupes...
[SCAN] Found 1,247 files, 23 duplicate groups (156 duplicate files)
[REPORT] Duplicate groups saved to /tmp/duplicates_XXXXXX.json

[DUPLICATE REVIEW]
Group 1 (hash: a1b2c3d4...): 3 files, 4.2 MB each
  1. /Volumes/MyPassport/OldPhoneBackups/iPhone_XS/DCIM/IMG_001.JPG
  2. /Volumes/MyPassport/OldPhoneBackups/iCloud/IMG_001.JPG
  3. /Volumes/MyPassport/OldPhoneBackups/Backup_2/IMG_001.JPG
Action: [K]eep first, [N]ewest, [O]ldest, [M]anual, [S]kip → K

[ORGANIZE] Processing 1,091 unique files...
[████████████████████████████████████████] 100% (1091/1091)

[CLEANUP] Removing 47 empty directories from source...

[DONE] ✓ Organized 1,091 files
       ✓ Skipped 156 duplicates
       ✓ Renamed 987 files with EXIF dates
       ✓ Cleaned 47 empty folders
       ✓ Log: ~/Pictures/OrganizedPhotos/management_log.txt
```

## Directory Structure After Run

```
~/Pictures/OrganizedPhotos/
├── Images/
│   └── iPhone_XS_Backup_2020/
│       ├── 20200115_083045.jpg
│       ├── 20200115_083122.heic
│       └── 20200220_142210.png
├── Videos/
│   └── iPhone_XS_Backup_2020/
│       ├── 20200115_083500.mov
│       └── 20200310_194530.mp4
├── Audio/
│   └── iPhone_XS_Backup_2020/
│       └── 20200501_120000.m4a
├── Documents/
│   └── iPhone_XS_Backup_2020/
│       └── 20200615_103000.pdf
├── Others/
│   └── iPhone_XS_Backup_2020/
│       └── unknown_file.xyz
└── management_log.txt
```

## Log File Format

```
2026-11-01 15:30:45 | COPY    | /Volumes/Backup/DCIM/IMG_001.JPG | Images/iPhone_XS_Backup_2020/20200115_083045.jpg | hash=a1b2c3d4 exif=2020:01:15 08:30:45
2026-11-01 15:30:46 | SKIP_DUP| /Volumes/Backup/iCloud/IMG_001.JPG | (duplicate of IMG_001.JPG)                      | hash=a1b2c3d4
2026-11-01 15:30:47 | RENAME  | /Volumes/Backup/DCIM/IMG_002.JPG | Images/iPhone_XS_Backup_2020/20200115_083122.heic | hash=e5f6g7h8 exif=2020:01:15 08:31:22
2026-11-01 15:35:12 | CLEANUP | /Volumes/Backup/DCIM/EmptyFolder | (removed empty directory)                       |
```

## Running Tests

```bash
# Create mock test data
./tests/create_mock_data.sh

# Run tests
./tests/test_organize.sh

# Clean up test data
rm -rf /tmp/file_organizer_test_*
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `command not found: jdupes` | Run `brew install jdupes` |
| `command not found: exiftool` | Run `brew install exiftool` |
| Permission denied | Run `chmod +x organize.zsh` |
| Colors not showing | Ensure using Ghostty or ANSI-compatible terminal |
| "Resource busy" on external drive | Unmount other apps using the drive, or run `lsof /Volumes/DriveName` |

## Uninstall

Simply delete the project folder. No system-wide installation performed.