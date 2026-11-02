# media-sorter-zsh

A robust, modular, and fast ZSH script designed to organize large media collections (photos, videos, audio) on macOS, specifically tailored for managing multiple backup sources.

## Features

- **Duplicate Detection**: Powered by `jdupes` for high-speed identification of identical files.
- **Smart Renaming**: Automatically renames files to `YYYYMMDD_HHMMSS` based on EXIF metadata (or filesystem date as fallback).
- **Categorized Hierarchy**: Organizes media into structured folders: `Images/`, `Videos/`, `Audio/`, `Documents/`, and `Others/`.
- **Backup Context**: Maintains organization by creating subfolders based on a user-defined "Backup ID".
- **Safety First**: Features a **Dry Run** mode to preview actions without modifying files, and comprehensive logging of all operations.
- **Interactive CLI**: A user-friendly, color-coded menu interface designed for terminals like [Ghostty](https://ghostty.org/).
- **External Volume Detection**: Automatically detects connected external drives in `/Volumes/` and presents them in an interactive menu for easy source selection (or fallback to manual entry).

## Prerequisites

This script requires a few standard tools on macOS. If missing, the script will prompt you to install them via [Homebrew](https://brew.sh/).

```bash
brew install jdupes exiftool jq
```

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Miguezpz/media-sorter-zsh.git
   cd media-sorter-zsh
   ```

2. Make the script executable:
   ```bash
   chmod +x organize.zsh
   ```

## Usage

### Interactive Mode (Recommended)
Simply run the script without arguments for a guided setup:

```bash
./organize.zsh
```

**New: Automatic External Volume Detection**  
When running interactively, the script will automatically scan `/Volumes/` for connected external drives (excluding macOS system volumes like "Macintosh HD", "Recovery", etc.). It will present an interactive menu showing:
- Volume name and path
- Available free space
- Option to use the entire volume as source, or navigate to a subdirectory
- "Manual Entry" fallback for typing or dragging a path

### CLI Mode (Non-interactive)
You can run the script in non-interactive mode by providing arguments:

```bash
./organize.zsh --source /path/to/source --dest /path/to/dest --backup-id PhoneBackup --mode full
```

#### Available Options:
| Flag | Description |
| :--- | :--- |
| `--source` | Path to the source directory. |
| `--dest` | Path to the destination directory. |
| `--backup-id` | Name for this backup batch. |
| `--mode` | Operation mode: `full`, `duplicates`, or `organize`. |
| `--dry-run` | Preview actions without making changes. |
| `--rename` / `--no-rename` | Enable/Disable EXIF-based renaming. |
| `--cleanup` / `--no-cleanup` | Enable/Disable empty folder cleanup in source. |

## License
MIT
