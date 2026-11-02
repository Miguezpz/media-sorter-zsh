#!/usr/bin/env zsh
# ============================================================================
# File Operations - Categorize, Copy, Cleanup
# ============================================================================

# Category extensions mapping
typeset -gA CATEGORIES
CATEGORIES=(
    images      "jpg jpeg png gif heic heif webp raw cr2 nef arw dng tiff tif bmp"
    videos      "mp4 mov avi mkv m4v 3gp mpg mpeg wmv flv webm"
    audio       "mp3 wav aac flac m4a ogg wma aiff aif"
    documents   "pdf doc docx txt xls xlsx ppt pptx md rtf odt ods odp"
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

# Get category display name
get_category_display() {
    local category="$1"
    case "$category" in
        images)      echo "Images" ;;
        videos)      echo "Videos" ;;
        audio)       echo "Audio" ;;
        documents)   echo "Documents" ;;
        *)           echo "Others" ;;
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

    # Find and remove empty directories (bottom-up)
    while IFS= read -r -d '' dir; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
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
    done < <(find "$source_dir" -type d -print0 2>/dev/null | sort -z -r)

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