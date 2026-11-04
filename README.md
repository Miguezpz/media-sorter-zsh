# media-sorter-zsh

A robust, modular, and extremely fast ZSH script designed to organize large media collections (photos, videos, audio) on macOS. Specifically tailored for managing massive backup sources with intelligent disk space management and a modern, interactive terminal UI.

## Features

- **Modern Interactive TUI**: A polished, TrueColor (24-bit) command-line interface featuring arrow-key navigation, Nerd Font icons, smooth progress bars, and real-time ETA calculations. Optimized for modern emulators like [Ghostty](https://ghostty.org/).
- **Disk Space Check**: Before copying, it computes the exact size of the files that will be copied (duplicates excluded) and stops with a clear message if the destination lacks space. Moving within the same disk needs no extra space.
- **In-Place Reorganization**: Use the same directory for Source and Destination and the files are organized into a `_Organized` subfolder, which is always excluded from later scans.
- **Duplicate Detection**: Powered by `jdupes` for byte-by-byte identification of identical files. One copy per group is kept (it prefers names that don't look like copies, e.g. without "copia"/"copy"/"(1)"), and you can choose manually. Duplicates are never deleted: they are simply not copied/moved. A full report is saved as `duplicados_<fecha>.txt`.
- **Smart Renaming (photos & videos only)**: Renames images and videos to `YYYYMMDD_HHMMSS` using the capture date from metadata (`exiftool`), falling back to the file modification date. Documents, audio and other files keep their original names.
- **Categorized Hierarchy**: Files go to `Imagenes/`, `Videos/`, `Audio/`, `Documentos/` and `Otros/` (optionally under a batch subfolder), preserving the original folder structure inside each category.
- **macOS junk filtering**: `._*` AppleDouble files (common on exFAT/FAT USB drives), `.DS_Store`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, etc. are ignored.
- **External Volume Detection & fzf Integration**: Detects connected drives in `/Volumes/` (including read-only NTFS drives). Paths can be typed, dragged into the terminal, or picked with `fzf` (searches `$HOME` and `/Volumes`).
- **Safety First**: **Dry Run** mode creates nothing in the destination (its log goes to a temp file), copies are atomic with size verification, moves are verified by hash before deleting the source, and every action is logged in `management_log.txt`.

## Prerequisites

This script requires a few standard tools on macOS. If missing, the script will automatically prompt you to install them via [Homebrew](https://brew.sh/).

- **Core Dependencies:** `jdupes`, `exiftool`, `jq`
- **Recommended:** `fzf` (for fuzzy path searching)
- **UI Requirement:** A terminal configured with a **Nerd Font** (e.g., FiraCode Nerd Font, MesloLGS NF) to render the UI icons correctly.

```bash
brew install jdupes exiftool jq fzf
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
Simply run the script without arguments for a fully guided, color-coded setup using your keyboard arrows:

```bash
./organize.zsh
```

**Workflow Highlights:**
1. **Source Selection:** Pick an external drive from the auto-detected list or use `fzf` to find your folder.
2. **Destination Selection:** Choose between reorganizing *In-Place* (same as source) or selecting a new directory.
3. **Mode Selection:** Run a full duplicate scan + organization, just find duplicates, or skip duplicates and just organize.
4. **Resolution:** Review interactive duplicate reports and confirm actions.

### CLI Mode
Pass arguments to skip the wizard. Add `--no-interactive` to never prompt (duplicates are resolved automatically), e.g. for cron jobs:

```bash
./organize.zsh --source /path/to/source --dest /path/to/dest --backup-id PhoneBackup --mode full
```

#### Available Options:
| Flag | Description |
| :--- | :--- |
| `--source` | Path to the source directory or drive. |
| `--dest` | Path to the destination directory (created if missing). If equal to the source, `<source>/_Organized` is used. |
| `--backup-id` | Optional batch subfolder inside each category (letters, numbers, `-`, `_`). |
| `--mode` | Operation mode: `full`, `duplicates`, or `organize`. |
| `--copy` / `--move` | `copy` preserves the source. `move` deletes the source after a successful transfer (saves space). |
| `--dry-run` | Preview actions without making changes. |
| `--rename` / `--no-rename` | Enable/Disable date-based renaming of photos and videos (default: on). |
| `--cleanup` / `--no-cleanup` | Remove folders left empty in the source after `--move` (default: on). |
| `--no-interactive` | Never prompt; duplicates are resolved automatically. |
| `-h`, `--help` | Show usage. |

### Tests
```bash
zsh tests/test_organize.sh
```

## License
MIT