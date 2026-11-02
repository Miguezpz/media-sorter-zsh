#!/usr/bin/env zsh
# ============================================================================
# File Operations - Categorize, Copy, Cleanup
# ============================================================================

# Category extensions mapping
# Spanish folder names as per SPECIFICATION.md
typeset -gA CATEGORIES
CATEGORIES=(
    Imagenes    "jpg jpeg png gif heic heif webp raw cr2 nef arw dng tiff tif bmp"
    Videos      "mp4 mov avi mkv m4v 3gp mpg mpeg wmv flv webm"
    Audio       "mp3 wav aac flac m4a ogg wma aiff aif"
    Documentos  "pdf doc docx txt xls xlsx ppt pptx md rtf odt ods odp"
)

# Get category for a file extension
categorize_file() {
    local filepath="$1"
    local ext="${filepath##*.}"
    ext="${ext:l}"  # lowercase

    for category in "${(@k)CATEGORIES}"; do
        local extensions="${CATEGORIES[$category]}"
        if [[ " $extensions " == *" $ext "* ]]; then
            echo "$category"
            return 0
        fi
    done

    echo "others"
    return 0
}

# Get category display name (used for display, returns the key since keys are Spanish names)
get_category_display() {
    local category="$1"
    case "$category" in
        Imagenes)    echo "Imágenes" ;;
        Videos)      echo "Videos" ;;
        Audio)       echo "Audio" ;;
        Documentos)  echo "Documentos" ;;
        *)           echo "Otros" ;;
    esac
}

# Ensure destination directory exists
ensure_dest_dir() {
    local dest_root="$1"
    local category="$2"
    local backup_id="$3"

    local dest_dir="$dest_root/$category/$backup_id"
    mkdir -p "$dest_dir"
    echo "$dest_dir"
}

# Generate unique destination filename
generate_dest_filename() {
    local dest_dir="$1"
    local filename="$2"
    local ext="${filename##*.}"
    local base="${filename%.*}"
    local counter=0
    local new_name="$filename"

    while [[ -e "$dest_dir/$new_name" ]]; do
        # If same file (same size and hash), we'll handle at caller level
        # For now, just add counter
        counter=$((counter + 1))
        new_name="${base}_${counter}.${ext}"
    done

    echo "$new_name"
}

# Copy file with progress logging
copy_file() {
    local src="$1"
    local dest="$2"
    local log_file="$3"
    local action="${4:-COPY}"
    local details="${5:-}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_operation "$log_file" "$action" "$src" "$dest" "$details (DRY RUN)"
        return 0
    fi

    # Copy preserving metadata
    if cp -p "$src" "$dest" 2>/dev/null; then
        log_operation "$log_file" "$action" "$src" "$dest" "$details"
        return 0
    else
        log_operation "$log_file" "ERROR" "$src" "$dest" "Copy failed: $details"
        return 1
    fi
}

# Move file with progress logging
move_file() {
    local src="$1"
    local dest="$2"
    local log_file="$3"
    local action="${4:-MOVE}"
    local details="${5:-}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_operation "$log_file" "$action" "$src" "$dest" "$details (DRY RUN)"
        return 0
    fi

    # Move (copy + remove source)
    if cp -p "$src" "$dest" 2>/dev/null && rm -f "$src" 2>/dev/null; then
        log_operation "$log_file" "$action" "$src" "$dest" "$details"
        return 0
    else
        log_operation "$log_file" "ERROR" "$src" "$dest" "Move failed: $details"
        # If copy succeeded but remove failed, we may have a duplicate
        return 1
    fi
}

# Log operation to management log
log_operation() {
    local log_file="$1"
    local action="$2"
    local src="$3"
    local dest="$4"
    local details="$5"
    local timestamp

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Make paths relative to dest_root for cleaner logs
    local rel_dest="$dest"
    if [[ "$dest" == "$DEST_ROOT"* ]]; then
        rel_dest="${dest#$DEST_ROOT/}"
    fi

    printf "%s | %-8s | %s | %s | %s\n" \
        "$timestamp" "$action" "$src" "$rel_dest" "$details" >> "$log_file"
}

# Clean up empty directories in source
cleanup_empty_dirs() {
    local source_dir="$1"
    local log_file="$2"
    local count=0

    print_info "Cleaning empty directories in source..."

    # Usando el globbing ZSH recursivo inverso (/Nod = Null glob, Solo directorios, Ordernar por profundidad)
    # Reemplazo de `find | sort -z` que es incompatible con macOS
    for dir in "$source_dir"/**/*(/Nod); do
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_operation "$log_file" "CLEANUP" "$dir" "" "(DRY RUN)"
                ((count++))
            else
                if rmdir "$dir" 2>/dev/null; then
                    log_operation "$log_file" "CLEANUP" "$dir" "" "Removed empty directory"
                    ((count++))
                fi
            fi
        fi
    done

    print_success "Cleaned $count empty directories"
    echo "$count"
}

# Scan all files in source directory
scan_files() {
    local source_dir="$1"

    # Use find with null delimiter for safe handling of special chars
    find "$source_dir" -type f -print0 2>/dev/null
}

# ============================================================================
# Volume Detection
# ============================================================================

# Detect external volumes mounted in /Volumes/
# Returns array of volume paths (excluding system volumes)
detect_external_volumes() {
    local -a volumes=()

    # List directories in /Volumes excluding system volumes
    for vol in /Volumes/*(/N); do
        local vol_name="${vol##*/}"

        # Skip macOS system volumes
        if [[ "$vol_name" =~ ^(Macintosh HD|Recovery|Preboot|VM|Update|Data)$ ]]; then
            continue
        fi

        # Check if it's a mounted external volume and writable
        if [[ -d "$vol" && -w "$vol" ]]; then
            volumes+=("$vol")
        fi
    done

    # Return volumes as newline-separated for array assignment
    for vol in "${volumes[@]}"; do
        echo "$vol"
    done
}

# Get volume info (name, path, free space)
get_volume_info() {
    local vol_path="$1"
    local vol_name="${vol_path##*/}"
    local free_space=$(df -h "$vol_path" 2>/dev/null | awk 'NR==2 {print $4}')

    echo "$vol_name|$vol_path|${free_space:-Unknown}"
}

# ============================================================================
# Disk Space Management
# ============================================================================

# Get free space in bytes for a path
get_free_space_bytes() {
    local path="$1"
    /bin/df -k "$path" 2>/dev/null | /usr/bin/awk 'NR==2 {print $4 * 1024}'
}

# Get free space in human readable format
get_free_space_human() {
    local path="$1"
    /bin/df -h "$path" 2>/dev/null | /usr/bin/awk 'NR==2 {print $4}'
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    if [[ $bytes -ge 1099511627776 ]]; then
        echo "$(( bytes / 1099511627776 )) TB"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 )) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 )) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "${bytes} B"
    fi
}

# Estimate total size of files in source directory
estimate_source_size() {
    local source_dir="$1"
    local total_size=0
    local count=0

    while IFS= read -r -d '' file; do
        total_size=$((total_size + $(get_file_size "$file")))
        ((count++))
    done < <(scan_files "$source_dir")

    echo "$total_size"
}

# Check if destination has enough space for source files
check_disk_space() {
    local source_dir="$1"
    local dest_dir="$2"
    local copy_mode="${3:-copy}"

    local free_dest=$(get_free_space_bytes "$dest_dir")
    local needed=$(estimate_source_size "$source_dir")

    # If move mode, we don't need extra space in destination
    if [[ "$copy_mode" == "move" ]]; then
        needed=0
    fi

    # Safety margin 10%
    local needed_with_margin=$((needed * 110 / 100))

    if [[ $free_dest -lt $needed_with_margin ]]; then
        return 1  # Insufficient space
    fi
    return 0  # Sufficient space
}

# Get file size in bytes
get_file_size() {
    local filepath="$1"
    stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null
}

# Get file hash (md5 for compatibility, but jdupes uses its own)
get_file_hash() {
    local filepath="$1"
    md5 -q "$filepath" 2>/dev/null
}

# ============================================================================
# Phased Processing (for low disk space scenarios)
# ============================================================================

# Process a chunk of files
process_chunk() {
    local -n files_ref=$1
    local dest_root="$2"
    local backup_id="$3"
    local rename_enabled="$4"
    local copy_mode="${5:-copy}"

    for file in "${files_ref[@]}"; do
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
        dest_dir=$(ensure_dest_dir "$dest_root" "$category" "$backup_id")

        # Determine filename
        local new_name
        if [[ "$rename_enabled" == "true" ]]; then
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
            # Use cached hash from generate_unique_name if available
            if [[ -n "$SOURCE_HASH" ]]; then
                src_hash="$SOURCE_HASH"
            else
                src_hash=$(get_file_hash "$file")
            fi
            dest_hash=$(get_file_hash "$dest_path")
            if [[ "$src_hash" == "$dest_hash" && -n "$src_hash" ]]; then
                ((STAT_SKIPPED_EXIST++))
                log_operation "$LOG_FILE" "SKIP_EXIST" "$file" "$dest_path" "hash=$src_hash"
                continue
            fi
        fi

        # Copy or Move file based on copy_mode
        local details
        # Use cached hash if available
        if [[ -n "$SOURCE_HASH" ]]; then
            details="hash=$SOURCE_HASH"
        else
            details="hash=$(get_file_hash "$file")"
        fi
        if [[ "$rename_enabled" == "true" ]]; then
            local exif_date
            exif_date=$(get_exif_date "$file" 2>/dev/null || echo "none")
            details+=" exif=$exif_date"
        fi

        local action="COPY"
        local result=0
        if [[ "$copy_mode" == "move" ]]; then
            action="MOVE"
            move_file "$file" "$dest_path" "$LOG_FILE" "$action" "$details"
            result=$?
        else
            copy_file "$file" "$dest_path" "$LOG_FILE" "$action" "$details"
            result=$?
        fi

        if [[ $result -eq 0 ]]; then
            ((STAT_COPIED++))
        else
            ((STAT_ERRORS++))
        fi
    done
}

# Clean up processed files from source after successful copy
cleanup_processed_source() {
    local -n files_ref=$1
    local source_dir="$2"
    local log_file="$3"
    local removed=0

    print_info "Removing processed files from source..." >&2

    for file in "${files_ref[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_operation "$log_file" "CLEANUP_SRC" "$file" "" "(DRY RUN)"
        else
            if rm -f "$file" 2>/dev/null; then
                log_operation "$log_file" "CLEANUP_SRC" "$file" "" "Removed after successful copy"
                ((removed++))
            fi
        fi
    done

    # Clean empty directories in source
    cleanup_empty_dirs "$source_dir" "$log_file"

    print_success "Removed $removed files from source" >&2
}

# Organize files in phases when disk space is limited
organize_files_phased() {
    local source_dir="$1"
    local dest_root="$2"
    local backup_id="$3"
    local rename_enabled="${4:-true}"
    local chunk_files="${5:-5000}"
    local chunk_bytes="${6:-53687091200}"  # 50GB default

    print_section "PHASED PROCESSING (Limited Disk Space)"
    print_info "Source: $source_dir"
    print_info "Destination: $dest_root"
    print_info "Chunk size: $chunk_files files or $(format_bytes $chunk_bytes) per phase"

    # Collect all files first
    local -a all_files=()
    print_info "Scanning source directory..."

    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(scan_files "$source_dir")

    local total_files=${#all_files[@]}
    STAT_TOTAL=$total_files

    if [[ $total_files -eq 0 ]]; then
        print_warn "No files found in source directory"
        return 0
    fi

    print_info "Found $total_files files to process"

    # Check EXIF availability if renaming
    if [[ "$rename_enabled" == "true" ]]; then
        check_exif_availability "${all_files[@]}"
    fi

    local processed=0
    local phase=1

    while [[ $processed -lt $total_files ]]; do
        print_section "PHASE $phase"

        # Calculate chunk boundaries
        local remaining=$((total_files - processed))
        local chunk_end=$((processed + chunk_files))
        [[ $chunk_end -gt $total_files ]] && chunk_end=$total_files

        # Check space before phase
        local free_dest=$(get_free_space_bytes "$dest_root")
        local needed=0
        for ((i=processed; i<chunk_end; i++)); do
            needed=$((needed + $(get_file_size "${all_files[i]}")))
        done
        needed=$((needed * 110 / 100))  # 10% margin

        local free_dest_human=$(get_free_space_human "$dest_root")
        local needed_human=$(format_bytes $needed)

        print_info "Free space: $free_dest_human | Needed for this phase: $needed_human"

        if [[ $free_dest -lt $needed ]]; then
            print_warn "Insufficient space for next chunk!"
            print_warn "Available: $free_dest_human, Required: $needed_human"

            if [[ "$COPY_MODE" == "copy" ]]; then
                print_info "Since we're in copy mode, phased processing will DELETE files from SOURCE after each phase to free space."
                print_warn "This means your source files will be removed as they are copied!"
                print_info "Alternative: Run the script in 'move' mode, or free space manually."
                if ! confirm "Continue with phased processing (DELETE source files after copy)?"; then
                    print_error "Aborted by user"
                    return 1
                fi
            fi
        fi

        print_info "Processing files $((processed+1)) to $chunk_end of $total_files"

        # Extract chunk
        local -a chunk=("${all_files[@]:processed:chunk_end-processed}")

        # Process chunk
        process_chunk chunk "$dest_root" "$backup_id" "$rename_enabled" "$COPY_MODE"

        # If copy mode: remove processed files from source to free space
        if [[ "$COPY_MODE" == "copy" ]]; then
            cleanup_processed_source chunk "$source_dir" "$LOG_FILE"
        fi

        processed=$chunk_end
        ((phase++))

        # Show progress
        show_progress "$processed" "$total_files"
    done

    printf "\n"
    print_success "Phased processing complete"
}
