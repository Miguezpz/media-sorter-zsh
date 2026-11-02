#!/usr/bin/env zsh
# ============================================================================
# UI Helpers for File Organizer - Colors, Menus, Progress
# ============================================================================

# Color constants for Ghostty (ANSI)
typeset -gA COLORS
COLORS=(
    RESET       $'\033[0m'
    BOLD        $'\033[1m'
    DIM         $'\033[2m'
    RED         $'\033[31m'
    GREEN       $'\033[32m'
    YELLOW      $'\033[33m'
    BLUE        $'\033[34m'
    MAGENTA     $'\033[35m'
    CYAN        $'\033[36m'
    WHITE       $'\033[37m'
    BRIGHT_RED  $'\033[91m'
    BRIGHT_GREEN $'\033[92m'
    BRIGHT_YELLOW $'\033[93m'
    BRIGHT_BLUE $'\033[94m'
    BRIGHT_MAGENTA $'\033[95m'
    BRIGHT_CYAN $'\033[96m'
    BG_RED      $'\033[41m'
    BG_GREEN    $'\033[42m'
    BG_YELLOW   $'\033[43m'
    BG_BLUE     $'\033[44m'
)

# Unicode symbols
typeset -gA SYMBOLS
SYMBOLS=(
    CHECK       "✓"
    CROSS       "✗"
    ARROW       "→"
    STAR        "★"
    GEAR        "⚙"
    FOLDER      "📁"
    FILE        "📄"
    SEARCH      "🔍"
    WARNING     "⚠"
    INFO        "ℹ"
    PROGRESS    "█"
    EMPTY       "░"
)

# Print functions
print_header() {
    local text="$1"
    local width=70
    local padding=$(( (width - ${#text}) / 2 ))
    printf "${COLORS[BOLD]}${COLORS[CYAN]}"
    printf "╔%*s╗\n" $width | tr ' ' '═'
    printf "║%*s%s%*s║\n" $padding "" "$text" $((width - padding - ${#text})) ""
    printf "╚%*s╝\n" $width | tr ' ' '═'
    printf "${COLORS[RESET]}"
}

print_section() {
    local text="$1"
    printf "\n${COLORS[BOLD]}${COLORS[BLUE]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[GEAR]}" "$text" >&2
    printf "${COLORS[DIM]}%s${COLORS[RESET]}\n" "$(printf '─%.0s' {1..60})" >&2
}

print_info() {
    printf "${COLORS[CYAN]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[INFO]}" "$1" >&2
}

print_success() {
    printf "${COLORS[GREEN]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[CHECK]}" "$1" >&2
}

print_warn() {
    printf "${COLORS[YELLOW]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[WARNING]}" "$1" >&2
}

print_error() {
    printf "${COLORS[RED]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[CROSS]}" "$1" >&2
}

print_step() {
    local current="$1"
    local total="$2"
    local text="$3"
    printf "${COLORS[BOLD]}${COLORS[MAGENTA]}[%d/%d]${COLORS[RESET]} %s\n" "$current" "$total" "$text"
}

# Progress bar
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    printf "\r${COLORS[CYAN]}["
    printf "%*s" $filled | tr ' ' "${SYMBOLS[PROGRESS]}"
    printf "%*s" $empty | tr ' ' "${SYMBOLS[EMPTY]}"
    printf "] %3d%% (%d/%d)${COLORS[RESET]}" "$percent" "$current" "$total"

    if [[ $current -eq $total ]]; then
        printf "\n"
    fi
}

# Input helpers
read_path() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"

    while true; do
        if [[ -n "$default" ]]; then
            printf "${COLORS[CYAN]}%s [%s]: ${COLORS[RESET]}" "$prompt" "$default"
        else
            printf "${COLORS[CYAN]}%s: ${COLORS[RESET]}" "$prompt"
        fi

        read -r input
        input="${input:-$default}"

        # Remove surrounding quotes if dragged from Finder
        input="${input//\'/}"
        input="${input//\"/}"
        # Expand tilde
        input="${input/#\~/$HOME}"

        if [[ -z "$input" ]]; then
            print_error "Path cannot be empty"
            continue
        fi

        if [[ ! -e "$input" ]]; then
            print_error "Path does not exist: $input"
            continue
        fi

        # Convert to absolute path
        input="$(cd "$input" && pwd)" || return 1

        eval "$var_name=\"$input\""
        print_success "Set to: $input"
        return 0
    done
}

read_string() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local validator="${4:-}"

    while true; do
        if [[ -n "$default" ]]; then
            printf "${COLORS[CYAN]}%s [%s]: ${COLORS[RESET]}" "$prompt" "$default"
        else
            printf "${COLORS[CYAN]}%s: ${COLORS[RESET]}" "$prompt"
        fi

        read -r input
        input="${input:-$default}"

        if [[ -z "$input" && -z "$default" ]]; then
            print_error "Value cannot be empty"
            continue
        fi

        if [[ -n "$validator" ]] && ! eval "$validator \"$input\""; then
            print_error "Invalid input"
            continue
        fi

        eval "$var_name=\"$input\""
        print_success "Set to: $input"
        return 0
    done
}

# Validation functions
validate_backup_id() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local response

    if [[ "$default" == "Y" ]]; then
        printf "${COLORS[YELLOW]}%s [Y/n]: ${COLORS[RESET]}" "$prompt"
    else
        printf "${COLORS[YELLOW]}%s [y/N]: ${COLORS[RESET]}" "$prompt"
    fi

    read -r response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy]$ ]]
}

select_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local key

    print_section "$title" >&2

    for i in {1..${#options[@]}}; do
        printf "  ${COLORS[DIM]}[%d]${COLORS[RESET]} %s\n" "$i" "${options[$i]}" >&2
    done

    while true; do
        printf "${COLORS[CYAN]}Select [1-%d]: ${COLORS[RESET]}" "${#options[@]}" >&2
        read -r key

        if [[ "$key" =~ ^[0-9]+$ ]] && (( key >= 1 && key <= ${#options[@]} )); then
            selected=$key
            break
        fi
        print_error "Invalid selection" >&2
    done

    echo $selected
}

select_multiple() {
    local title="$1"
    shift
    local options=("$@")
    local -a selected=()
    local key

    print_section "$title"
    print_info "Enter numbers separated by spaces (e.g., '1 3'), or 'all'"

    for i in {1..${#options[@]}}; do
        printf "  ${COLORS[DIM]}[%d]${COLORS[RESET]} %s\n" "$i" "${options[$i]}"
    done

    while true; do
        printf "${COLORS[CYAN]}Select: ${COLORS[RESET]}"
        read -r key

        if [[ "$key" == "all" ]]; then
            selected=({1..${#options[@]}})
            break
        fi

        local valid=1
        for num in ${(z)key}; do
            if [[ ! "$num" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#options[@]} )); then
                valid=0
                break
            fi
            selected+=($num)
        done

        if [[ $valid -eq 1 && ${#selected[@]} -gt 0 ]]; then
            break
        fi
        print_error "Invalid selection"
    done

    echo "${selected[@]}"
}

# Spinner for long operations
spinner_pid=0
start_spinner() {
    local msg="$1"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    (
        while true; do
            printf "\r${COLORS[CYAN]}%s %s${COLORS[RESET]}" "${spin_chars[i++ % ${#spin_chars} + 1]}" "$msg"
            sleep 0.1
        done
    ) &
    spinner_pid=$!
}

stop_spinner() {
    if [[ $spinner_pid -ne 0 ]]; then
        kill $spinner_pid 2>/dev/null
        wait $spinner_pid 2>/dev/null
        spinner_pid=0
        printf "\r%*s\r" $(tput cols) ""
    fi
}

# Cleanup on exit
cleanup_spinner() {
    stop_spinner
}
trap cleanup_spinner EXIT INT TERM

# ============================================================================
# Volume Selection
# ============================================================================

# Interactive source directory selection with external volume detection
# Usage: select_source_directory VAR_NAME
# Sets the variable VAR_NAME to the selected path
select_source_directory() {
    local var_name="$1"

    # Detect external volumes
    local -a volumes=()
    while IFS= read -r vol; do
        [[ -n "$vol" ]] && volumes+=("$vol")
    done < <(detect_external_volumes)

    if [[ ${#volumes[@]} -gt 0 ]]; then
        print_section "EXTERNAL VOLUMES DETECTED"
        print_info "Select a volume, or choose 'Manual Entry' to type/drag a path"

        local -a options=()
        local -a volume_info=()

        for vol in "${volumes[@]}"; do
            local info=$(get_volume_info "$vol")
            local vol_name="${info%%|*}"
            local vol_path="${info#*|}"
            vol_path="${vol_path%|*}"
            local free_space="${info##*|}"

            options+=("$vol_name ($vol_path) - ${free_space} free")
            volume_info+=("$info")
        done
        options+=("Manual Entry (type or drag path)")

        local choice
        choice=$(select_menu "Select source directory" "${options[@]}")

        if (( choice <= ${#volumes[@]} )); then
            # User selected a volume
            local selected_info="${volume_info[$choice]}"
            local selected_vol="${selected_info#*|}"
            selected_vol="${selected_vol%|*}"

            if confirm "Use entire volume '$(basename "$selected_vol")' as source?" "Y"; then
                eval "$var_name=\"$selected_vol\""
                print_success "Source set to: $selected_vol"
                return 0
            else
                # Let user navigate into the volume
                read_path "Subdirectory in $(basename "$selected_vol") (or press Enter for root)" "$var_name" "$selected_vol"
                return 0
            fi
        else
            # Manual entry
            read_path "Source directory" "$var_name"
            return 0
        fi
    else
        print_info "No external volumes detected. Using manual entry."
        read_path "Source directory" "$var_name"
        return 0
    fi
}