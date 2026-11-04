# media-sorter-zsh

A robust, modular, and extremely fast ZSH script designed to organize large media collections (photos, videos, audio) on macOS. Specifically tailored for managing massive backup sources with intelligent disk space management and a modern, interactive terminal UI.

## Features

- **Modern Interactive TUI**: A polished, TrueColor (24-bit) command-line interface featuring arrow-key navigation, Nerd Font icons, smooth progress bars, and real-time ETA calculations. Optimized for modern emulators like [Ghostty](https://ghostty.org/).
- **Disk Space Check**: Before copying, it computes the exact size of the files that will be copied (duplicates excluded) and stops with a clear message if the destination lacks space. Moving within the same disk needs no extra space.
- **In-Place Reorganization**: Use the same directory for Source and Destination and the files are organized into a `_Organized` subfolder, which is always excluded from later scans.
- **Duplicate Detection**: Powered by `jdupes` for byte-by-byte identification of identical files. One copy per group is kept (it prefers names that don't look like copies, e.g. without "copia"/"copy"/"(1)"), and you can choose manually. Duplicates are never deleted: they are simply not copied/moved. A full report is saved as `duplicados_<fecha>.txt`.
- **Reliable capture dates**: The date of each photo/video comes, in this order, from (1) its **file name** (`IMG_20230115_143000`, `IMG-20230115-WA0001`, `20230115_143000`, `Screenshot_2023-01-15-14-30-00`, `FB_IMG_…`), (2) EXIF/QuickTime metadata, (3) the **Google Takeout** `.json` sidecar (`photoTakenTime`). The file modification date is **never** used: on copied backups it is the copy date, not the photo date. Files without a reliable date go to `Sin_fecha/`.
- **Smart Renaming (photos & videos only)**: Files whose name already contains the date keep their name. The rest are renamed to `YYYYMMDD_HHMMSS` from metadata. Documents, audio and other files always keep their names.
- **Organized by date**: Photos and videos go to `Imagenes/<Año>/<Año-Mes>/` and `Videos/<Año>/<Año-Mes>/` (or keep their original paths with `--layout original`). Audio, documents and others keep their original folder structure under their category.
- **Protected folders**: Programs, games, code projects and macOS bundles (`.dll`, `.cab`, `.msi`, `package.json`, `.git`, `node_modules`, `*.app`, `*.photoslibrary`…) are left untouched as a unit instead of being split into categories. A lone `.exe` (e.g. an installer next to personal documents) does not protect a folder.
- **Junk filtering**: Everything hidden is ignored (`._*` AppleDouble files on exFAT/FAT drives, `.DS_Store`, `.Trashes`, `.Spotlight-V100`, Android `.thumbnails`, WhatsApp `.Statuses`…), as well as Android app data (`Android/data`, `Android/obb`). `Android/media` (where WhatsApp stores photos) **is** processed. Google Takeout `.json` sidecars are left in place.
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
| `--layout fecha\|original` | Photos/videos in `Año/Año-Mes` folders (default) or in their original paths. |
| `--rename` / `--no-rename` | Rename by date the photos/videos whose name doesn't include it (default: on). |
| `--no-protect` | Don't protect program, game and code-project folders. |
| `--cleanup` / `--no-cleanup` | Remove folders left empty in the source after `--move` (default: on). |
| `--no-interactive` | Never prompt; duplicates are resolved automatically. |
| `-h`, `--help` | Show usage. |

### Tests
```bash
zsh tests/test_organize.sh
```

## License
MIT