#!/usr/bin/env zsh
# ============================================================================
# File Organizer & Duplicate Finder for macOS
# Main entry point - orchestrates all modules
# ============================================================================

# Strict mode
set -euo pipefail
setopt NULL_GLOB
setopt EXTENDED_GLOB

# Script directory
SCRIPT_DIR="${0:A:h}"
LIB_DIR="$SCRIPT_DIR/lib"

# Source libraries
source "$LIB_DIR/ui_helpers.zsh"
source "$LIB_DIR/file_ops.zsh"
source "$LIB_DIR/dup_finder.zsh"
source "$LIB_DIR/exif_rename.zsh"

# Global configuration
typeset -g SOURCE_DIR=""
typeset -g DEST_ROOT=""
typeset -g BACKUP_ID=""
typeset -g MODE="full"          # full, duplicates, organize
typeset -g COPY_MODE="copy"     # copy, move
typeset -g RENAME_ENABLED=true
typeset -g CLEANUP_ENABLED=true
typeset -g DRY_RUN=false
typeset -g LOG_FILE=""
typeset -g DUP_JSON_FILE=""

# Duplicate tracking arrays
typeset -ga DUP_GROUPS=()
typeset -ga KEEP_FILES=()
typeset -ga REMOVE_FILES=()

# Statistics
typeset -gi STAT_TOTAL=0
typeset -gi STAT_PROCESSED=0
typeset -gi STAT_COPIED=0
typeset -gi STAT_SKIPPED_DUP=0
typeset -gi STAT_SKIPPED_EXIST=0
typeset -gi STAT_RENAMED=0
typeset -gi STAT_ERRORS=0

# ============================================================================
# Dependency Checking
# ============================================================================

check_dependencies() {
    print_section "CHECKING DEPENDENCIES"

    local missing=()

    # Check jdupes
    if ! command -v jdupes >/dev/null 2>&1; then
        missing+=("jdupes")
    else
        local jdupes_path=$(command -v jdupes)
        print_success "jdupes found: $jdupes_path"
    fi

    # Check exiftool
    if ! command -v exiftool >/dev/null 2>&1; then
        missing+=("exiftool")
    else
        local exiftool_path=$(command -v exiftool)
        print_success "exiftool found: $exiftool_path"
    fi

    # Check jq (for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    else
        print_success "jq found: $(command -v jq)"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warn "Missing dependencies: ${missing[*]}"
        print_info "Install with: brew install ${missing[*]}"

        if confirm "Install missing dependencies now?"; then
            brew install "${missing[@]}"
            print_success "Dependencies installed"
        else
            print_error "Cannot continue without required dependencies"
            exit 1
        fi
    fi

    print_success "All dependencies satisfied"
}

# ============================================================================
# User Input / Configuration
# ============================================================================

get_user_config() {
    print_header "FILE ORGANIZER & DUPLICATE FINDER"
    print_info "macOS M2 Edition - ZSH + jdupes + exiftool"

    # Source directory - with external volume detection
    print_section "SOURCE DIRECTORY"
    select_source_directory SOURCE_DIR

    # Destination directory
    print_section "DESTINATION DIRECTORY"
    read_path "Destination directory" DEST_ROOT

    # Backup identifier
    print_section "BACKUP IDENTIFIER"
    print_info "Name for this backup batch (alphanumeric, underscore, dash only)"
    read_string "Backup ID" BACKUP_ID "" validate_backup_id

    # Operation mode
    print_section "OPERATION MODE"
    local mode_options=(
        "Full Process (Find Duplicates + Organize)"
        "Find Duplicates Only"
        "Organize Only (Skip Duplicate Scan)"
    )
    local mode_choice
    mode_choice=$(select_menu "Select mode" "${mode_options[@]}")

    case $mode_choice in
        1) MODE="full" ;;
        2) MODE="duplicates" ;;
        3) MODE="organize" ;;
    esac
    print_success "Mode: $MODE"

    # Options
    print_section "OPTIONS"

    if confirm "Enable Smart Rename (EXIF dates)?" "Y"; then
        RENAME_ENABLED=true
        print_success "Smart Rename: ON"
    else
        RENAME_ENABLED=false
        print_info "Smart Rename: OFF (keep original filenames)"
    fi

    if [[ "$MODE" != "duplicates" ]]; then
        if confirm "Clean empty folders in source after copy?" "Y"; then
            CLEANUP_ENABLED=true
            print_success "Cleanup Empty Folders: ON"
        else
            CLEANUP_ENABLED=false
            print_info "Cleanup Empty Folders: OFF"
        fi
    fi

    if confirm "Dry Run (preview only, no changes)?" "N"; then
        DRY_RUN=true
        print_warn "DRY RUN MODE ENABLED - No files will be modified"
    else
        DRY_RUN=false
        print_info "Live mode - files will be copied"
    fi

    # Summary
    print_section "CONFIGURATION SUMMARY"
    printf "  ${COLORS[BOLD]}Source:${COLORS[RESET]}      %s\n" "$SOURCE_DIR"
    printf "  ${COLORS[BOLD]}Destination:${COLORS[RESET]}  %s\n" "$DEST_ROOT"
    printf "  ${COLORS[BOLD]}Backup ID:${COLORS[RESET]}     %s\n" "$BACKUP_ID"
    printf "  ${COLORS[BOLD]}Mode:${COLORS[RESET]}          %s\n" "$MODE"
    printf "  ${COLORS[BOLD]}Copy Mode:${COLORS[RESET]}      %s\n" "$COPY_MODE"
    printf "  ${COLORS[BOLD]}Smart Rename:${COLORS[RESET]}    %s\n" "$([[ $RENAME_ENABLED == true ]] && echo ON || echo OFF)"
    printf "  ${COLORS[BOLD]}Cleanup:${COLORS[RESET]}         %s\n" "$([[ $CLEANUP_ENABLED == true ]] && echo ON || echo OFF)"
    printf "  ${COLORS[BOLD]}Dry Run:${COLORS[RESET]}         %s\n" "$([[ $DRY_RUN == true ]] && echo ON || echo OFF)"

    # Disk space summary
    local free_dest=$(get_free_space_human "$DEST_ROOT")
    printf "  ${COLORS[BOLD]}Free space at dest:${COLORS[RESET]} %s\n" "$free_dest"

    local est_size=$(estimate_source_size "$SOURCE_DIR")
    if [[ $est_size -gt 0 ]]; then
        printf "  ${COLORS[BOLD]}Est. size:${COLORS[RESET]}      %s\n" "$(format_bytes $est_size)"
        if [[ "$COPY_MODE" == "copy" ]]; then
            local free_bytes=$(get_free_space_bytes "$DEST_ROOT")
            local needed_bytes=$((est_size * 110 / 100))
            if [[ $free_bytes -lt $needed_bytes ]]; then
                printf "  ${COLORS[RED]}⚠ SPACE WARNING: Phased processing may be needed${COLORS[RESET]}\n"
            fi
        fi
    fi

    if ! confirm "Proceed with this configuration?"; then
        print_info "Cancelled by user"
        exit 0
    fi

    # Initialize log file
    LOG_FILE="$DEST_ROOT/management_log.txt"
    mkdir -p "$DEST_ROOT"
    echo "# File Organizer Log - $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
    echo "# Source: $SOURCE_DIR" >> "$LOG_FILE"
    echo "# Backup ID: $BACKUP_ID" >> "$LOG_FILE"
    echo "# Mode: $MODE" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    # Temp file for jdupes output
    DUP_JSON_FILE=$(mktemp /tmp/duplicates_XXXXXX.json)
}

# ============================================================================
# Duplicate Scanning Phase
# ============================================================================

run_duplicate_scan() {
    if [[ "$MODE" == "organize" ]]; then
        print_info "Skipping duplicate scan (organize-only mode)"
        return 0
    fi

    print_section "DUPLICATE SCANNING"

    scan_duplicates "$SOURCE_DIR" "$DUP_JSON_FILE"

    parse_jdupes_output "$DUP_JSON_FILE" "DUP_GROUPS"

    # Get count
    local dup_count
    eval "dup_count=\${#DUP_GROUPS[@]}"
    if [[ $dup_count -eq 0 ]]; then
        print_success "No duplicates found"
        return 0
    fi

    display_duplicate_report "DUP_GROUPS"

    if [[ "$MODE" == "duplicates" ]]; then
        # Just report, don't organize
        print_info "Duplicate-only mode: scan complete"
        if confirm "Save duplicate report to destination?"; then
            cp "$DUP_JSON_FILE" "$DEST_ROOT/duplicate_report_$(date '+%Y%m%d_%H%M%S').json"
            print_success "Report saved"
        fi
        return 0
    fi

    # Resolve duplicates
    if confirm "Resolve duplicates interactively?" "Y"; then
        resolve_duplicates_interactive "DUP_GROUPS" "KEEP_FILES" "REMOVE_FILES"
    else
        print_info "Auto-resolving: keeping first file in each group"
        resolve_duplicates_auto "DUP_GROUPS" "KEEP_FILES" "REMOVE_FILES" "first"
    fi
}

# ============================================================================
# File Organization Phase
# ============================================================================

organize_files() {
    if [[ "$MODE" == "duplicates" ]]; then
        return 0
    fi

    print_section "ORGANIZING FILES"

    # Check disk space first
    if ! check_disk_space "$SOURCE_DIR" "$DEST_ROOT" "$COPY_MODE"; then
        print_warn "Insufficient disk space for single-pass operation"
        print_info "Available: $(get_free_space_human "$DEST_ROOT")"
        local est_size=$(estimate_source_size "$SOURCE_DIR")
        print_info "Estimated needed: $(format_bytes $((est_size * 110 / 100))) (with 10% margin)"

        if [[ "$COPY_MODE" == "copy" ]]; then
            print_info "Enabling phased processing (copy + cleanup source after each phase)..."
            if ! confirm "Proceed with phased processing?"; then
                print_info "Operation cancelled"
                return 0
            fi
            organize_files_phased "$SOURCE_DIR" "$DEST_ROOT" "$BACKUP_ID" "$RENAME_ENABLED"
            return 0
        else
            # Move mode on same filesystem - no extra space needed
            print_info "Move mode on same filesystem - proceeding without extra space"
        fi
    fi

    # Collect all files first (for progress bar)
    local -a all_files=()
    print_info "Scanning source directory..."

    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(scan_files "$SOURCE_DIR")

    STAT_TOTAL=${#all_files[@]}
    print_info "Found $STAT_TOTAL files to process"

    if [[ $STAT_TOTAL -eq 0 ]]; then
        print_warn "No files found in source directory"
        return 0
    fi

    # Check EXIF availability if renaming
    if [[ "$RENAME_ENABLED" == "true" ]]; then
        check_exif_availability "${all_files[@]}"
    fi

    print_info "Starting organization..."
    local processed=0

    for file in "${all_files[@]}"; do
        ((processed++))
        show_progress "$processed" "$STAT_TOTAL"

        # Skip if marked as duplicate to remove
        if is_duplicate_to_remove "$file" "REMOVE_FILES"; then
            ((STAT_SKIPPED_DUP++))
            log_operation "$LOG_FILE" "SKIP_DUP" "$file" "" "Duplicate of kept file"
            continue
        fi

        # Categorize
        local category
        category=$(categorize_file "$file")

        # Determine destination directory
        local dest_dir
        dest_dir=$(ensure_dest_dir "$DEST_ROOT" "$category" "$BACKUP_ID")

        # Determine filename
        local new_name
        if [[ "$RENAME_ENABLED" == "true" ]]; then
            new_name=$(determine_filename "$file" "$dest_dir" true)
            if [[ "$new_name" != "${file##*/}" ]]; then
                ((STAT_RENAMED++))
            fi
        else
            new_name=$(generate_unique_name "$dest_dir" "${file##*/}" "$file")
        fi

        local dest_path="$dest_dir/$new_name"

        # Check if already exists at destination (same content)
        if [[ -f "$dest_path" ]]; then
            local src_hash dest_hash
            src_hash=$(get_file_hash "$file")
            dest_hash=$(get_file_hash "$dest_path")
            if [[ "$src_hash" == "$dest_hash" && -n "$src_hash" ]]; then
                ((STAT_SKIPPED_EXIST++))
                log_operation "$LOG_FILE" "SKIP_EXIST" "$file" "$dest_path" "hash=$src_hash"
                continue
            fi
        fi

        # Copy file
        local details="hash=$(get_file_hash "$file")"
        if [[ "$RENAME_ENABLED" == "true" ]]; then
            local exif_date
            exif_date=$(get_exif_date "$file" 2>/dev/null || echo "none")
            details+=" exif=$exif_date"
        fi

        if copy_file "$file" "$dest_path" "$LOG_FILE" "COPY" "$details"; then
            ((STAT_COPIED++))
        else
            ((STAT_ERRORS++))
        fi
    done

    printf "\n"
    print_success "Organization complete"
}

# ============================================================================
# Cleanup Phase
# ============================================================================

run_cleanup() {
    if [[ "$CLEANUP_ENABLED" != "true" ]] || [[ "$MODE" == "duplicates" ]]; then
        return 0
    fi

    print_section "CLEANUP"
    cleanup_empty_dirs "$SOURCE_DIR" "$LOG_FILE"
}

# ============================================================================
# Final Report
# ============================================================================

show_final_report() {
    print_header "OPERATION COMPLETE"

    printf "${COLORS[BOLD]}Statistics:${COLORS[RESET]}\n"
    printf "  ${COLORS[GREEN]}Files copied:${COLORS[RESET]}        %d\n" "$STAT_COPIED"
    printf "  ${COLORS[YELLOW]}Duplicates skipped:${COLORS[RESET]}  %d\n" "$STAT_SKIPPED_DUP"
    printf "  ${COLORS[BLUE]}Already existed:${COLORS[RESET]}      %d\n" "$STAT_SKIPPED_EXIST"
    printf "  ${COLORS[MAGENTA]}Files renamed:${COLORS[RESET]}       %d\n" "$STAT_RENAMED"
    printf "  ${COLORS[RED]}Errors:${COLORS[RESET]}               %d\n" "$STAT_ERRORS"
    printf "\n"

    printf "${COLORS[BOLD]}Output:${COLORS[RESET]}\n"
    printf "  ${COLORS[CYAN]}Organized files:${COLORS[RESET]}     %s\n" "$DEST_ROOT"
    printf "  ${COLORS[CYAN]}Log file:${COLORS[RESET]}            %s\n" "$LOG_FILE"

    if [[ -f "$DUP_JSON_FILE" ]]; then
        printf "  ${COLORS[CYAN]}Duplicate report:${COLORS[RESET]}    %s\n" "$DUP_JSON_FILE"
    fi

    # Show destination structure
    print_section "DESTINATION STRUCTURE"
    if command -v tree >/dev/null 2>&1; then
        tree -L 3 "$DEST_ROOT" 2>/dev/null | head -50
    else
        find "$DEST_ROOT" -maxdepth 3 -type f | head -20 | while read f; do
            printf "  %s\n" "${f#$DEST_ROOT/}"
        done
        local total_files
        total_files=$(find "$DEST_ROOT" -type f | wc -l | tr -d ' ')
        printf "  ${COLORS[DIM]}... and $((total_files - 20)) more files${COLORS[RESET]}\n"
    fi

    print_success "Done! Your files are organized at: $DEST_ROOT"
}

# ============================================================================
# Argument Parsing (for non-interactive mode)
# ============================================================================

typeset -g INTERACTIVE=true

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source)
                SOURCE_DIR="$2"
                shift 2
                ;;
            --dest)
                DEST_ROOT="$2"
                shift 2
                ;;
            --backup-id)
                BACKUP_ID="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            --rename)
                RENAME_ENABLED=true
                shift
                ;;
            --no-rename)
                RENAME_ENABLED=false
                shift
                ;;
            --cleanup)
                CLEANUP_ENABLED=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_ENABLED=false
                shift
                ;;
            --help|-h)
                cat <<EOF
Usage: organize.zsh [options]

Options:
  --source DIR          Source directory
  --dest DIR            Destination directory
  --backup-id NAME      Backup identifier
  --mode MODE           Mode: full, duplicates, organize
  --dry-run             Preview only, no changes
  --no-interactive      Run without prompts (requires all args)
  --rename              Enable EXIF renaming
  --no-rename           Disable EXIF renaming
  --cleanup             Enable empty folder cleanup
  --no-cleanup          Disable empty folder cleanup
  --help                Show this help

Interactive mode (default): Run without arguments for guided setup.
EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

validate_config() {
    local errors=0

    if [[ -z "$SOURCE_DIR" ]]; then
        print_error "Source directory not specified"
        ((errors++))
    elif [[ ! -d "$SOURCE_DIR" ]]; then
        print_error "Source directory does not exist: $SOURCE_DIR"
        ((errors++))
    fi

    if [[ -z "$DEST_ROOT" ]]; then
        print_error "Destination directory not specified"
        ((errors++))
    fi

    if [[ -z "$BACKUP_ID" ]]; then
        print_error "Backup ID not specified"
        ((errors++))
    elif ! validate_backup_id "$BACKUP_ID"; then
        print_error "Invalid backup ID (alphanumeric, underscore, dash only)"
        ((errors++))
    fi

    if [[ ! "$MODE" =~ ^(full|duplicates|organize)$ ]]; then
        print_error "Invalid mode: $MODE (must be full, duplicates, or organize)"
        ((errors++))
    fi

    # Convert to absolute paths
    SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
    DEST_ROOT="$(mkdir -p "$DEST_ROOT" && cd "$DEST_ROOT" && pwd)"

    # Validate source and destination are not the same or nested
    local abs_source="$SOURCE_DIR"
    local abs_dest="$DEST_ROOT"

    if [[ "$abs_dest" == "$abs_source"* ]]; then
        print_error "Destination cannot be inside source directory"
        print_error "  Source:      $abs_source"
        print_error "  Destination: $abs_dest"
        ((errors++))
    elif [[ "$abs_source" == "$abs_dest"* && "$abs_source" != "$abs_dest" ]]; then
        print_error "Source cannot be inside destination directory"
        print_error "  Source:      $abs_source"
        print_error "  Destination: $abs_dest"
        ((errors++))
    elif [[ "$abs_source" == "$abs_dest" ]]; then
        print_error "Source and destination cannot be the same directory"
        print_error "  Path: $abs_source"
        ((errors++))
    fi

    # Check if same filesystem
    local src_dev=$(stat -f "%d" "$abs_source" 2>/dev/null || echo "")
    local dest_dev=$(stat -f "%d" "$abs_dest" 2>/dev/null || echo "")
    if [[ -n "$src_dev" && -n "$dest_dev" && "$src_dev" == "$dest_dev" ]]; then
        print_warn "Source and destination are on the same filesystem"
        print_warn "Moving files will be fast (rename), but copying will use extra space"
        if ! confirm "Continue with same filesystem?"; then
            ((errors++))
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        exit 1
    fi

    # Initialize log file
    LOG_FILE="$DEST_ROOT/management_log.txt"
    mkdir -p "$DEST_ROOT"
    echo "# File Organizer Log - $(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"
    echo "# Source: $SOURCE_DIR" >> "$LOG_FILE"
    echo "# Backup ID: $BACKUP_ID" >> "$LOG_FILE"
    echo "# Mode: $MODE" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    # Temp file for jdupes output
    DUP_JSON_FILE=$(mktemp /tmp/duplicates_XXXXXX.json)
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Handle Ctrl+C gracefully
    trap 'print_error "Interrupted"; exit 130' INT

    # Parse arguments
    parse_args "$@"

    # If running interactively (no args or --no-interactive not set)
    if [[ $# -eq 0 ]] || [[ "${INTERACTIVE:-true}" == "true" ]]; then
        if [[ -z "$SOURCE_DIR" ]]; then
            check_dependencies
            get_user_config
        else
            # Non-interactive but args provided
            validate_config
            check_dependencies
            print_section "CONFIGURATION"
            printf "  ${COLORS[BOLD]}Source:${COLORS[RESET]}      %s\n" "$SOURCE_DIR"
            printf "  ${COLORS[BOLD]}Destination:${COLORS[RESET]}  %s\n" "$DEST_ROOT"
            printf "  ${COLORS[BOLD]}Backup ID:${COLORS[RESET]}     %s\n" "$BACKUP_ID"
            printf "  ${COLORS[BOLD]}Mode:${COLORS[RESET]}          %s\n" "$MODE"
            printf "  ${COLORS[BOLD]}Smart Rename:${COLORS[RESET]}    %s\n" "$([[ $RENAME_ENABLED == true ]] && echo ON || echo OFF)"
            printf "  ${COLORS[BOLD]}Cleanup:${COLORS[RESET]}         %s\n" "$([[ $CLEANUP_ENABLED == true ]] && echo ON || echo OFF)"
            printf "  ${COLORS[BOLD]}Dry Run:${COLORS[RESET]}         %s\n" "$([[ $DRY_RUN == true ]] && echo ON || echo OFF)"
        fi
    else
        # Non-interactive mode
        validate_config
        check_dependencies
    fi

    local start_time
    start_time=$(date +%s)

    run_duplicate_scan
    organize_files
    run_cleanup

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    show_final_report
    print_info "Total time: ${duration}s"

    # Cleanup temp file
    [[ -f "$DUP_JSON_FILE" ]] && rm -f "$DUP_JSON_FILE"
}

# Run main
main "$@"