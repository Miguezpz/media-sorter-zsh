# Implementation Plan: File Organizer and Duplicate Finder for macOS

**Branch**: `001-file-organizer` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-file-organizer/spec.md`

## Summary

A ZSH script (`organize.zsh`) for macOS (M2) that organizes phone backup files from an external drive into a structured destination. Uses `jdupes` for fast duplicate detection and `exiftool` for EXIF-based renaming. Features interactive menu, category-based sorting (Images/Videos/Audio/Documents), backup-context subfolders, safe copy mode, empty folder cleanup, and operation logging.

## Technical Context

**Language/Version**: ZSH 5.9 (macOS default)

**Primary Dependencies**: 
- `jdupes` (duplicate detection via Homebrew)
- `exiftool` (metadata extraction via Homebrew)
- Standard BSD tools: `find`, `cp`, `mkdir`, `rmdir`, `stat`, `md5`

**Storage**: Local filesystem (source external drive → destination local/external)

**Testing**: Manual test suite with mock data; shellcheck for linting

**Target Platform**: macOS 14+ (Sonoma) on Apple Silicon M2

**Project Type**: CLI utility script

**Performance Goals**: 
- Process 10,000+ files in <5 minutes
- Duplicate scan on 100GB in <2 minutes (jdupes optimized)

**Constraints**: 
- Must preserve source files (copy-only by default)
- Must handle filenames with spaces/Unicode
- Ghostty terminal ANSI color support

**Scale/Scope**: 
- Single script (~500 lines)
- Handles multiple backup sources sequentially
- No database - uses filesystem and jdupes output

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Single script project (no multi-repo complexity)
- [x] No external API dependencies
- [x] Local-only execution
- [x] Minimal dependencies (2 Homebrew packages)

## Project Structure

### Documentation (this feature)

```text
specs/001-file-organizer/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (N/A for CLI script)
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
file-management/
├── specs/
│   └── 001-file-organizer/
├── organize.zsh          # Main script (to be created)
├── lib/
│   ├── ui_helpers.zsh    # Colors, menu, progress helpers
│   ├── file_ops.zsh      # Copy, categorize, rename logic
│   ├── dup_finder.zsh    # jdupes integration
│   └── exif_rename.zsh   # exiftool integration
├── tests/
│   ├── create_mock_data.sh
│   └── test_organize.sh
└── SPECIFICATION.md      # Original spec (legacy)
```

**Structure Decision**: Modular ZSH with lib/ for separation of concerns. Main script sources lib modules. Tests in tests/ directory.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A - No violations | Constitution check passed | N/A |

## Phase 0: Research (Completed)

- Verified `jdupes` and `exiftool` availability on macOS via Homebrew
- Confirmed ZSH capabilities for interactive menus and ANSI colors
- Validated `find -print0` / `xargs -0` for safe filename handling

## Phase 1: Design

### Data Model (data-model.md)

Key data structures used in the script:

1. **FileRecord** (implicit, passed via pipes): `source_path|dest_path|category|hash|exif_date|size`
2. **DuplicateGroup**: Array of FileRecords with identical hash
3. **Config**: `source_dir`, `dest_dir`, `backup_id`, `mode`, `rename_enabled`, `cleanup_enabled`

### Quickstart (quickstart.md)

```bash
# 1. Install dependencies
brew install jdupes exiftool

# 2. Make script executable
chmod +x organize.zsh

# 3. Run interactively
./organize.zsh

# 4. Follow menu prompts:
#    - Select source directory (drag & drop in Ghostty)
#    - Select destination directory
#    - Enter backup identifier (e.g., "iPhone_8_Backup")
#    - Choose options: [Organize] [Find Duplicates] [Smart Rename] [Cleanup]
#    - Confirm and run
```

## Phase 2: Tasks (to be generated via /speckit-tasks)

### Module Breakdown

1. **ui_helpers.zsh**: Color constants, `print_header`, `print_info`, `print_warn`, `print_error`, `confirm`, `select_menu`, `progress_bar`
2. **file_ops.zsh**: `categorize_file`, `ensure_dest_dir`, `copy_file`, `cleanup_empty_dirs`
3. **dup_finder.zsh**: `scan_duplicates`, `parse_jdupes_output`, `interactive_dedup`
4. **exif_rename.zsh**: `get_exif_date`, `generate_new_name`, `apply_rename`
5. **organize.zsh**: Main orchestrator - sources libs, runs menu, coordinates workflow

### Testing Strategy

- `create_mock_data.sh`: Generates test tree with duplicates, EXIF/non-EXIF files, empty dirs
- `test_organize.sh`: Runs script on mock data, verifies output structure, logs, and duplicate handling

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| jdupes not installed | High | High | Auto-detect and prompt `brew install` |
| exiftool missing EXIF | Medium | Medium | Fallback to filesystem date |
| Filename collisions | Medium | High | Counter suffix `_1`, `_2` on conflict |
| Large file copy failure | Low | High | Use `cp -p` preserve mode; verify with `stat` |
| User cancels mid-run | Medium | Medium | Log progress; skip existing files on resume |

## Verification Checklist

- [ ] Script runs without syntax errors (`zsh -n organize.zsh`)
- [ ] Shellcheck passes (`shellcheck organize.zsh lib/*.zsh`)
- [ ] Mock data test passes (all categories, duplicates, renaming)
- [ ] Log file contains expected entries
- [ ] Empty folders cleaned up when enabled
- [ ] Source files unmodified after copy operation