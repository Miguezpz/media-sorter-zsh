#!/usr/bin/env zsh
# ============================================================================
# UI Helpers for File Organizer - Interfaz Moderna Interactiva
# ============================================================================

# Paleta de colores mejorada (esquema moderno/pastel)
typeset -gA COLORS
COLORS=(
    RESET       $'\033[0m'
    BOLD        $'\033[1m'
    DIM         $'\033[2m'
    ITALIC      $'\033[3m'
    RED         $'\033[38;5;203m'
    GREEN       $'\033[38;5;114m'
    YELLOW      $'\033[38;5;221m'
    BLUE        $'\033[38;5;111m'
    MAGENTA     $'\033[38;5;170m'
    CYAN        $'\033[38;5;80m'
    WHITE       $'\033[38;5;231m'
    BRIGHT_RED  $'\033[38;5;210m'
    BRIGHT_BLUE $'\033[38;5;117m'
    BG_BLUE     $'\033[48;5;111m'
)

# Iconos Nerd Fonts para una interfaz moderna
typeset -gA SYMBOLS
SYMBOLS=(
    CHECK       ""
    CROSS       ""
    ARROW       "➜"
    STAR        ""
    GEAR        ""
    FOLDER      "󰉋"
    FILE        "󰈙"
    SEARCH      ""
    WARNING     ""
    INFO        ""
    CLOCK       ""
)

print_header() {
    local text="$1"
    printf "\n${COLORS[BOLD]}${COLORS[CYAN]}╭%s╮${COLORS[RESET]}\n" "$(printf '─%.0s' {1..70})"
    printf "${COLORS[BOLD]}${COLORS[CYAN]}│${COLORS[RESET]} %-68s ${COLORS[BOLD]}${COLORS[CYAN]}│${COLORS[RESET]}\n" "$text"
    printf "${COLORS[BOLD]}${COLORS[CYAN]}╰%s╯${COLORS[RESET]}\n" "$(printf '─%.0s' {1..70})"
}

print_section() {
    local text="$1"
    printf "\n${COLORS[BOLD]}${COLORS[MAGENTA]}%s %s${COLORS[RESET]}\n" "${SYMBOLS[STAR]}" "$text" >&2
}

print_info() {
    printf "${COLORS[BLUE]}%s ${COLORS[RESET]}%s\n" "${SYMBOLS[INFO]}" "$1" >&2
}

print_success() {
    printf "${COLORS[GREEN]}%s ${COLORS[RESET]}%s\n" "${SYMBOLS[CHECK]}" "$1" >&2
}

print_warn() {
    printf "${COLORS[YELLOW]}%s ${COLORS[RESET]}%s\n" "${SYMBOLS[WARNING]}" "$1" >&2
}

print_error() {
    printf "${COLORS[RED]}%s ${COLORS[RESET]}%s\n" "${SYMBOLS[CROSS]}" "$1" >&2
}

select_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=1
    local key

    print_section "$title" >&2
    printf "${COLORS[DIM]}Usa las flechas (↑/↓) para navegar y Enter para seleccionar${COLORS[RESET]}\n\n" >&2
    printf "\033[?25l" >&2

    for ((i=1; i<=${#options[@]}; i++)); do
        printf "\n" >&2
    done
    printf "\033[%dA" "${#options[@]}" >&2
    printf "\033[s" >&2

    while true; do
        printf "\033[u" >&2
        for i in {1..${#options[@]}}; do
            printf "\r\033[2K" >&2
            if [[ $i -eq $selected ]]; then
                printf "  ${COLORS[CYAN]}${SYMBOLS[ARROW]} ${COLORS[BOLD]}%s${COLORS[RESET]}" "${options[$i]}" >&2
            else
                printf "    ${COLORS[DIM]}%s${COLORS[RESET]}" "${options[$i]}" >&2
            fi
            if [[ $i -lt ${#options[@]} ]]; then
                printf "\n" >&2
            fi
        done

        read -rs -k 1 key
        if [[ "$key" == $'\e' ]]; then
            read -rs -k 2 key
            case "$key" in
                "[A") ((selected--));;
                "[B") ((selected++));;
            esac
        elif [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
            printf "\n" >&2
            break
        fi

        if (( selected < 1 )); then selected=${#options[@]}; fi
        if (( selected > ${#options[@]} )); then selected=1; fi
    done
    printf "\033[?25h" >&2
    echo "$selected"
}

# Pregunta sí/no. Lee una línea completa (requiere Enter), así un Enter de más
# no responde por accidente la siguiente pregunta. Acepta y/yes/s/si/sí.
confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local response=""
    if [[ "$default" == "Y" ]]; then
        printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s ${COLORS[DIM]}[S/n]: ${COLORS[RESET]}" "${SYMBOLS[ARROW]}" "$prompt" >&2
    else
        printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s ${COLORS[DIM]}[s/N]: ${COLORS[RESET]}" "${SYMBOLS[ARROW]}" "$prompt" >&2
    fi
    if ! read -r response; then
        printf "\n" >&2
        return 1
    fi
    response="${response//[[:space:]]/}"
    response="${${response:-$default}:l}"
    [[ "$response" == (y|yes|s|si|sí) ]]
}

# Limpia una ruta escrita o arrastrada a la terminal:
#   '/Volumes/STORAGE X'   "/Volumes/STORAGE X"   /Volumes/STORAGE\ X␠
normalize_path_input() {
    setopt localoptions extendedglob
    local p="$1"
    p="${p##[[:space:]]##}"
    p="${p%%[[:space:]]##}"
    p="${(Q)p}"
    p="${p/#\~/$HOME}"
    print -r -- "$p"
}

# Selector de carpetas con fzf. Por defecto busca en $HOME y en /Volumes.
pick_dir_fzf() {
    local -a roots=("$@")
    (( ${#roots[@]} )) || roots=("$HOME" /Volumes)
    find "${roots[@]}" -maxdepth 4 \
        \( -name '.*' -o -name Library -o -name node_modules \) -prune -o -type d -print 2>/dev/null \
        | fzf --prompt="Selecciona carpeta> " --height=40% --layout=reverse --border
}

# read_path PROMPT VAR [DEFAULT] [ALLOW_NEW]
# ALLOW_NEW=true acepta una carpeta que aún no existe si su carpeta padre sí
# existe (útil para el destino; se crea más tarde).
read_path() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local allow_new="${4:-false}"
    local input has_fzf=false
    command -v fzf >/dev/null 2>&1 && has_fzf=true

    while true; do
        if [[ "$has_fzf" == "true" ]]; then
            printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s ${COLORS[DIM]}(escribe/arrastra la ruta, o Enter para buscar con fzf): ${COLORS[RESET]}" "${SYMBOLS[FOLDER]}" "$prompt" >&2
        elif [[ -n "$default" ]]; then
            printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s ${COLORS[DIM]}[%s]: ${COLORS[RESET]}" "${SYMBOLS[FOLDER]}" "$prompt" "$default" >&2
        else
            printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s: ${COLORS[RESET]}" "${SYMBOLS[FOLDER]}" "$prompt" >&2
        fi

        input=""
        read -r input || return 1

        if [[ -z "${input//[[:space:]]/}" && "$has_fzf" == "true" ]]; then
            print_info "Abriendo fzf (flechas para navegar, Enter para elegir, Esc para cancelar)..."
            if [[ -n "$default" ]]; then
                input=$(pick_dir_fzf "$default")
            else
                input=$(pick_dir_fzf)
            fi
            if [[ -z "$input" ]]; then
                print_error "Selección cancelada."
                continue
            fi
        fi

        input=$(normalize_path_input "$input")
        input="${input:-$default}"

        if [[ -z "$input" ]]; then
            print_error "La ruta no puede estar vacía"
            continue
        fi

        if [[ -d "$input" ]]; then
            input="${input:A}"
        elif [[ -e "$input" ]]; then
            print_error "No es una carpeta: $input"
            continue
        elif [[ "$allow_new" == "true" && -d "${input:h}" ]]; then
            input="${input:A}"
            print_info "La carpeta no existe; se creará: $input"
        else
            print_error "La ruta no existe: $input"
            continue
        fi

        typeset -g "$var_name=$input"
        print_success "Carpeta asignada: $input"
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
            printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s ${COLORS[DIM]}[%s]: ${COLORS[RESET]}" "${SYMBOLS[FILE]}" "$prompt" "$default"
        else
            printf "${COLORS[CYAN]}%s ${COLORS[RESET]}%s: ${COLORS[RESET]}" "${SYMBOLS[FILE]}" "$prompt"
        fi

        read -r input
        input="${input:-$default}"

        if [[ -z "$input" && -z "$default" ]]; then
            print_error "El valor no puede estar vacío"
            continue
        fi

        if [[ -n "$validator" ]] && ! eval "$validator \"$input\""; then
            print_error "Entrada inválida"
            continue
        fi

        typeset -g "$var_name=$input"
        print_success "Valor asignado"
        return 0
    done
}

validate_backup_id() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# ============================================================================
# Progreso y Feedback Dinámico (Fase 3 Optimizada)
# ============================================================================

typeset -g PROGRESS_START_TIME=0

init_progress() {
    PROGRESS_START_TIME=$SECONDS
    printf "\033[?25l" >&2 # Ocultar cursor
}

finish_progress() {
    printf "\n\033[?25h\n" >&2 # Restaurar cursor
}

show_progress() {
    local current="$1"
    local total="$2"
    local width=30
    local percent=$(( current * 100 / total ))
    
    local elapsed=$(( SECONDS - PROGRESS_START_TIME ))
    [[ $elapsed -eq 0 ]] && elapsed=1
    
    local items_per_sec=$(( current / elapsed ))
    local remaining_items=$(( total - current ))
    local eta=0
    if [[ $items_per_sec -gt 0 ]]; then
        eta=$(( remaining_items / items_per_sec ))
    fi
    
    local eta_min=$(( eta / 60 ))
    local eta_sec=$(( eta % 60 ))
    
    local blocks=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉" "█")
    local filled_chars=$(( current * width / total ))
    local partial_idx=$(( (current * width * 8 / total) % 8 ))
    
    # MUY IMPORTANTE: Se añadió >&2 a todo el printf para evitar 
    # el buffering invisible (glitch visual de terminal).
    printf "\r\033[2K${COLORS[CYAN]}%s [" "${SYMBOLS[GEAR]}" >&2
    
    for ((i=0; i<width; i++)); do
        if (( i < filled_chars )); then
            printf "%s" "${blocks[9]}" >&2
        elif (( i == filled_chars && partial_idx > 0 )); then
            printf "%s" "${blocks[partial_idx+1]}" >&2
        else
            printf "${COLORS[DIM]}┈${COLORS[CYAN]}" >&2
        fi
    done
    
    printf "] %3d%% (%d/%d) ${COLORS[DIM]}│ %d it/s │ ETA: %02d:%02d${COLORS[RESET]}" \
        "$percent" "$current" "$total" "$items_per_sec" "$eta_min" "$eta_sec" >&2
}

spinner_pid=0
start_spinner() {
    setopt localoptions no_monitor
    local msg="$1"
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    printf "\033[?25l" >&2
    (
        while true; do
            printf "\r\033[K${COLORS[CYAN]}%s ${COLORS[RESET]}%s" "${spin_chars[i++ % ${#spin_chars} + 1]}" "$msg" >&2
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
        printf "\r\033[2K\033[?25h" >&2
    fi
}

cleanup_spinner() {
    stop_spinner
    printf "\033[?25h" >&2
}
trap cleanup_spinner EXIT INT TERM

# ============================================================================
# Volume Selection
# ============================================================================

select_source_directory() {
    local var_name="$1"
    local -a volumes=()
    
    while IFS= read -r vol; do
        [[ -n "$vol" ]] && volumes+=("$vol")
    done < <(detect_external_volumes)

    if [[ ${#volumes[@]} -gt 0 ]]; then
        print_section "VOLÚMENES EXTERNOS DETECTADOS"
        
        local -a options=()
        local -a volume_info=()

        for vol in "${volumes[@]}"; do
            local info=$(get_volume_info "$vol")
            local vol_name="${info%%|*}"
            local vol_path="${info#*|}"
            vol_path="${vol_path%|*}"
            local free_space="${info##*|}"

            options+=("$vol_name ($vol_path) - ${free_space} libres")
            volume_info+=("$info")
        done
        options+=("Ingreso Manual (Escribir, arrastrar ruta o usar FZF)")

        local choice=$(select_menu "Selecciona el origen:" "${options[@]}")

        if (( choice <= ${#volumes[@]} )); then
            local selected_info="${volume_info[$choice]}"
            local selected_vol="${selected_info#*|}"
            selected_vol="${selected_vol%|*}"

            if confirm "¿Usar el volumen completo '$(basename "$selected_vol")' como origen?" "Y"; then
                typeset -g "$var_name=$selected_vol"
                print_success "Origen: $selected_vol"
                return 0
            else
                read_path "Subdirectorio en $(basename "$selected_vol")" "$var_name" "$selected_vol"
                return 0
            fi
        else
            read_path "Directorio de origen" "$var_name"
            return 0
        fi
    else
        print_info "No se detectaron discos externos ni USB en /Volumes."
        read_path "Directorio de origen" "$var_name"
        return 0
    fi
}
