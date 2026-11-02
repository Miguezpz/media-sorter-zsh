#!/usr/bin/env zsh
# ============================================================================
# Duplicate Finder - jdupes Integration
# ============================================================================

# Scan for duplicates using jdupes
# Output: JSON file with duplicate groups
scan_duplicates() {
    local source_dir="$1"
    local output_file="$2"

    print_info "Scanning for duplicates with jdupes..."

    # jdupes options:
    # -r  : recursive
    # -j  : JSON output
    # -S  : show size
    # -H  : show hash
    # -q  : quiet (no progress to stdout, but we'll capture stderr for progress)

    local jdupes_cmd="jdupes -r -j -S -H \"$source_dir\""

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warn "DRY RUN: Would run: $jdupes_cmd"
        echo '{"matchSets":[]}' > "$output_file"
        return 0
    fi

    # Run jdupes and capture JSON output
    # stderr shows progress, stdout is JSON
    if eval "$jdupes_cmd" > "$output_file" 2>&1; then
        local group_count
        group_count=$(jq '.matchSets | length' "$output_file" 2>/dev/null || echo "0")
        print_success "Found $group_count duplicate groups"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            # jdupes returns 1 when no duplicates found
            print_success "No duplicates found"
            echo '{"matchSets":[]}' > "$output_file"
            return 0
        else
            print_error "jdupes failed with exit code $exit_code"
            cat "$output_file" >&2
            return 1
        fi
    fi
}

# Parse jdupes JSON output into ZSH arrays
parse_jdupes_output() {
    local json_file="$1"
    local groups_ref_name="$2"

    # Clear the target array
    eval "$groups_ref_name=()"

    # Parse JSON using jq - jdupes uses "matchSets" not "duplicates"
    local group_count
    group_count=$(jq '.matchSets | length' "$json_file" 2>/dev/null || echo "0")

    for ((i=0; i<group_count; i++)); do
        local group_json
        group_json=$(jq ".matchSets[$i]" "$json_file")

        local first_file
        first_file=$(echo "$group_json" | jq -r '.fileList[0].filePath')
        
        # Recuperar el hash directamente del JSON de jdupes, o recalcular si falla
        local hash
        hash=$(echo "$group_json" | jq -r '.fileList[0].fileHash // empty')
        if [[ -z "$hash" || "$hash" == "null" ]]; then
            hash=$(md5 -q "$first_file" 2>/dev/null || echo "unknown")
        fi

        local size
        size=$(echo "$group_json" | jq -r '.fileSize')

        local -a files=()
        local file_count
        file_count=$(echo "$group_json" | jq '.fileList | length')

        for ((j=0; j<file_count; j++)); do
            local file_path
            file_path=$(echo "$group_json" | jq -r ".fileList[$j].filePath")
            files+=("$file_path")
        done

        # Store as: hash|size|file1|file2|...
        local group_str="$hash|$size"
        for f in "${files[@]}"; do
            group_str+="|$f"
        done
        eval "$groups_ref_name+=(\"\$group_str\")"
    done
}

# Display duplicate report
display_duplicate_report() {
    local groups_ref_name="$1"

    # Get array contents via eval (proper ZSH indirect array reference)
    local -a groups_ref
    eval "groups_ref=(\${(P)groups_ref_name})"

    if [[ ${#groups_ref[@]} -eq 0 ]]; then
        print_info "No duplicates to display"
        return 0
    fi

    print_section "DUPLICATE REPORT"
    printf "${COLORS[BOLD]}Found %d duplicate groups:${COLORS[RESET]}\n\n" "${#groups_ref[@]}"

    local group_num=1
    for group_str in "${groups_ref[@]}"; do
        local parts=("${(@s:|:)group_str}")
        local hash="${parts[1]}"
        local size="${parts[2]}"
        # ZSH array slicing is 0-based, so :2 skips first 2 elements (indices 0,1 = parts[1], parts[2])
        local files=("${parts[@]:2}")

        local size_mb=$(( size / 1024 / 1024 ))
        local size_kb=$(( size / 1024 ))

        printf "${COLORS[YELLOW]}Group %d${COLORS[RESET]} (hash: ${COLORS[DIM]}%s...${COLORS[RESET]}, size: %d MB, %d files)\n" \
            "$group_num" "${hash:0:12}" "$size_mb" "${#files[@]}"

        local file_idx=1
        for f in "${files[@]}"; do
            local rel_path="${f#$SOURCE_DIR/}"
            printf "  ${COLORS[DIM]}%d.${COLORS[RESET]} %s\n" "$file_idx" "$rel_path"
            ((file_idx++))
        done
        printf "\n"
        ((group_num++))
    done
}

# Interactive duplicate resolution
resolve_duplicates_interactive() {
    local groups_ref_name="$1"
    local keep_files_ref_name="$2"
    local remove_files_ref_name="$3"

    eval "$keep_files_ref_name=()"
    eval "$remove_files_ref_name=()"

    # Get groups array
    local -a groups_ref
    eval "groups_ref=(\${(P)groups_ref_name})"

    if [[ ${#groups_ref[@]} -eq 0 ]]; then
        return 0
    fi

    print_section "DUPLICATE RESOLUTION"
    print_info "For each group, choose which file to KEEP. Others will be marked for removal."
    print_info "Options: [1-N] keep that file, [A]ll keep first, [S]kip group, [Q]uit"

    local group_num=1
    for group_str in "${groups_ref[@]}"; do
        local parts=("${(@s:|:)group_str}")
        local hash="${parts[1]}"
        local size="${parts[2]}"
        local files=("${parts[@]:3}")

        printf "\n${COLORS[BOLD]}Group %d/%d${COLORS[RESET]} (hash: ${COLORS[DIM]}%s...${COLORS[RESET]})\n" \
            "$group_num" "${#groups_ref[@]}" "${hash:0:12}"

        local file_idx=1
        for f in "${files[@]}"; do
            local rel_path="${f#$SOURCE_DIR/}"
            local mtime
            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null)
            printf "  ${COLORS[CYAN]}[%d]${COLORS[RESET]} %s ${COLORS[DIM]}(%s)${COLORS[RESET]}\n" \
                "$file_idx" "$rel_path" "$mtime"
            ((file_idx++))
        done

        while true; do
            printf "${COLORS[YELLOW]}Action [1-%d, A=keep first, S=skip, Q=quit]: ${COLORS[RESET]}" "${#files[@]}"
            read -r choice

            if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
                # Keep selected, remove others
                eval "$keep_files_ref_name+=(\"\${files[$choice]}\")"
                for ((i=1; i<=${#files[@]}; i++)); do
                    if (( i != choice )); then
                        eval "$remove_files_ref_name+=(\"\${files[$i]}\")"
                    fi
                done
                break
            elif [[ "$choice" == "A" || "$choice" == "a" ]]; then
                # Keep first (oldest in jdupes output)
                eval "$keep_files_ref_name+=(\"\${files[1]}\")"
                for ((i=2; i<=${#files[@]}; i++)); do
                    eval "$remove_files_ref_name+=(\"\${files[$i]}\")"
                done
                print_info "Keeping first file, removing ${#files[@]}-1 duplicates"
                break
            elif [[ "$choice" == "S" || "$choice" == "s" ]]; then
                # Skip - keep all
                for f in "${files[@]}"; do
                    eval "$keep_files_ref_name+=(\"\$f\")"
                done
                print_info "Skipping group - keeping all files"
                break
            elif [[ "$choice" == "Q" || "$choice" == "q" ]]; then
                print_warn "Quitting duplicate resolution"
                return 1
            else
                print_error "Invalid choice"
            fi
        done

        ((group_num++))
    done

    # Get final counts
    local -a keep_files
    local -a remove_files
    eval "keep_files=(\"\${$keep_files_ref_name[@]}\")"
    eval "remove_files=(\"\${$remove_files_ref_name[@]}\")"

    print_success "Duplicate resolution complete"
    print_info "Files to keep: ${#keep_files[@]}"
    print_info "Files to remove: ${#remove_files[@]}"
    return 0
}

# Auto-resolve duplicates (keep first/oldest/newest)
resolve_duplicates_auto() {
    local groups_ref_name="$1"
    local keep_files_ref_name="$2"
    local remove_files_ref_name="$3"
    local strategy="${4:-first}"  # first, oldest, newest

    eval "$keep_files_ref_name=()"
    eval "$remove_files_ref_name=()"

    # Get groups array
    local -a groups_ref
    eval "groups_ref=(\${(P)groups_ref_name})"

    for group_str in "${groups_ref[@]}"; do
        local parts=("${(@s:|:)group_str}")
        local files=("${parts[@]:3}")

        case "$strategy" in
            oldest)
                # Find oldest by mtime
                local oldest_idx=1
                local oldest_time=$(stat -f "%m" "${files[1]}" 2>/dev/null)
                for ((i=2; i<=${#files[@]}; i++)); do
                    local t=$(stat -f "%m" "${files[$i]}" 2>/dev/null)
                    if (( t < oldest_time )); then
                        oldest_time=$t
                        oldest_idx=$i
                    fi
                done
                eval "$keep_files_ref_name+=(\"\${files[$oldest_idx]}\")"
                for ((i=1; i<=${#files[@]}; i++)); do
                    (( i != oldest_idx )) && eval "$remove_files_ref_name+=(\"\${files[$i]}\")"
                done
                ;;
            newest)
                # Find newest by mtime
                local newest_idx=1
                local newest_time=$(stat -f "%m" "${files[1]}" 2>/dev/null)
                for ((i=2; i<=${#files[@]}; i++)); do
                    local t=$(stat -f "%m" "${files[$i]}" 2>/dev/null)
                    if (( t > newest_time )); then
                        newest_time=$t
                        newest_idx=$i
                    fi
                done
                eval "$keep_files_ref_name+=(\"\${files[$newest_idx]}\")"
                for ((i=1; i<=${#files[@]}; i++)); do
                    (( i != newest_idx )) && eval "$remove_files_ref_name+=(\"\${files[$i]}\")"
                done
                ;;
            first|*)
                # Keep first (jdupes order)
                eval "$keep_files_ref_name+=(\"\${files[1]}\")"
                for ((i=2; i<=${#files[@]}; i++)); do
                    eval "$remove_files_ref_name+=(\"\${files[$i]}\")"
                done
                ;;
        esac
    done
}

# Check if a file is in the "remove" list
is_duplicate_to_remove() {
    local filepath="$1"
    local remove_ref_name="$2"

    local -a remove_ref
    eval "remove_ref=(\${(P)remove_ref_name})"

    for f in "${remove_ref[@]}"; do
        if [[ "$f" == "$filepath" ]]; then
            return 0
        fi
    done
    return 1
}

# Check if a file is in the "keep" list
is_duplicate_to_keep() {
    local filepath="$1"
    local keep_ref_name="$2"

    local -a keep_ref
    eval "keep_ref=(\${(P)keep_ref_name})"

    for f in "${keep_ref[@]}"; do
        if [[ "$f" == "$filepath" ]]; then
            return 0
        fi
    done
    return 1
}
