#!/usr/bin/env zsh
# ============================================================================
# EXIF Rename - exiftool Integration for Smart Renaming
# ============================================================================

# Extract EXIF DateTimeOriginal from file
get_exif_date() {
    local filepath="$1"
    local date_str

    # Try multiple EXIF tags in order of preference
    # DateTimeOriginal > CreateDate > ModifyDate > FileModifyDate
    date_str=$(exiftool -s -s -s \
        -DateTimeOriginal \
        -CreateDate \
        -ModifyDate \
        -FileModifyDate \
        "$filepath" 2>/dev/null | head -1)

    if [[ -n "$date_str" && "$date_str" != "-" ]]; then
        echo "$date_str"
        return 0
    fi

    return 1
}

# Format EXIF date to YYYYMMDD_HHMMSS
format_exif_date() {
    local exif_date="$1"

    # EXIF format: "2023:10:25 14:30:05" or "2023:10:25 14:30:05+01:00"
    # Convert to: "20231025_143005"

    # Remove timezone if present
    exif_date="${exif_date%%+*}"
    exif_date="${exif_date%%-*}"  # Handle negative timezone

    # Replace colons and space
    local formatted="${exif_date//:}"
    formatted="${formatted/ /_}"

    echo "$formatted"
}

# Generate new filename based on EXIF date
generate_exif_filename() {
    local filepath="$1"
    local ext="${filepath##*.}"
    ext="${ext:l}"

    local exif_date
    exif_date=$(get_exif_date "$filepath")

    if [[ -n "$exif_date" ]]; then
        local formatted
        formatted=$(format_exif_date "$exif_date")
        echo "${formatted}.${ext}"
        return 0
    fi

    return 1
}

# Get filesystem modification date as fallback
get_fs_date() {
    local filepath="$1"
    # Format: YYYYMMDD_HHMMSS
    stat -f "%Sm" -t "%Y%m%d_%H%M%S" "$filepath" 2>/dev/null
}

# Generate unique filename in destination directory
# If src_file is provided, checks for identical content to avoid duplicates
# Sets global SOURCE_HASH to the source file's hash for reuse
generate_unique_name() {
    local dest_dir="$1"
    local proposed_name="$2"
    local src_file="${3:-}"  # Optional source file for hash comparison
    local ext="${proposed_name##*.}"
    local base="${proposed_name%.*}"
    local counter=0
    local final_name="$proposed_name"

    while [[ -e "$dest_dir/$final_name" ]]; do
        # Check if it's the same file (same content)
        if [[ -f "$dest_dir/$final_name" && -n "$src_file" ]]; then
            local src_hash dest_hash
            src_hash=$(md5 -q "$src_file" 2>/dev/null)
            dest_hash=$(md5 -q "$dest_dir/$final_name" 2>/dev/null)
            if [[ "$src_hash" == "$dest_hash" && -n "$src_hash" ]]; then
                # Same file, we'll skip at higher level
                SOURCE_HASH="$src_hash"
                echo "$final_name"
                return 0
            fi
        fi

        counter=$((counter + 1))
        final_name="${base}_${counter}.${ext}"
    done

    # Calculate and cache hash for the source file if provided
    if [[ -n "$src_file" ]]; then
        SOURCE_HASH=$(md5 -q "$src_file" 2>/dev/null)
    else
        SOURCE_HASH=""
    fi

    echo "$final_name"
}

# Main function: determine final filename for a file
# Also sets global SOURCE_HASH for the processed file to avoid recalculation
determine_filename() {
    local filepath="$1"
    local dest_dir="$2"
    local use_exif="${3:-true}"

    local original_name="${filepath##*/}"
    local new_name=""

    if [[ "$use_exif" == "true" ]]; then
        # Try EXIF-based rename
        new_name=$(generate_exif_filename "$filepath")

        if [[ -n "$new_name" ]]; then
            # Ensure uniqueness (pass source file for hash comparison)
            new_name=$(generate_unique_name "$dest_dir" "$new_name" "$filepath")
            echo "$new_name"
            return 0
        fi
    fi

    # Fallback: try filesystem date
    local fs_date
    fs_date=$(get_fs_date "$filepath")
    if [[ -n "$fs_date" ]]; then
        local ext="${original_name##*.}"
        ext="${ext:l}"
        new_name="${fs_date}.${ext}"
        new_name=$(generate_unique_name "$dest_dir" "$new_name" "$filepath")
        echo "$new_name"
        return 0
    fi

    # Last resort: keep original name but ensure uniqueness
    new_name=$(generate_unique_name "$dest_dir" "$original_name" "$filepath")
    echo "$new_name"
    return 0
}

# Batch check EXIF availability for progress reporting
check_exif_availability() {
    local -a files=("$@")
    local total=${#files[@]}
    local with_exif=0
    local without_exif=0

    for f in "${files[@]}"; do
        if get_exif_date "$f" >/dev/null 2>&1; then
            ((with_exif++))
        else
            ((without_exif++))
        fi
    done

    print_info "EXIF check: $with_exif/$total files have EXIF dates, $without_exif will use fallback"
}