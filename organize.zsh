#!/usr/bin/env zsh
# ============================================================================
# File Organizer & Duplicate Finder for macOS
# Main entry point - orchestrates all modules
# ============================================================================

set -u
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
typeset -g CLEANUP_ENABLED=true # solo aplica en modo move
typeset -g DRY_RUN=false
typeset -g INTERACTIVE=true
typeset -g LOG_FILE=""
typeset -g DUP_JSON_FILE=""
typeset -g DUP_REPORT_FILE=""

# Statistics
typeset -gi STAT_TOTAL=0
typeset -gi STAT_COPIED=0
typeset -gi STAT_SKIPPED_DUP=0
typeset -gi STAT_SKIPPED_EXIST=0
typeset -gi STAT_RENAMED=0
typeset -gi STAT_ERRORS=0
typeset -g  ABORT_REASON=""

die() {
    print_error "$1"
    exit 1
}

usage() {
    cat <<'EOF'
Uso:
  ./organize.zsh                      Asistente interactivo (recomendado)
  ./organize.zsh --source DIR --dest DIR [opciones]

Opciones:
  --source DIR          Carpeta o disco de origen
  --dest DIR            Carpeta de destino (si es igual al origen se usa DIR/_Organized)
  --backup-id NOMBRE    Subcarpeta de lote dentro de cada categoría (opcional)
  --mode MODO           full | duplicates | organize   (por defecto: full)
  --copy | --move       Copiar (por defecto) o mover los archivos
  --rename | --no-rename    Renombrar fotos/videos por fecha de captura (por defecto: sí)
  --cleanup | --no-cleanup  Borrar carpetas vacías del origen tras mover (por defecto: sí)
  --dry-run             Simular sin modificar nada
  --no-interactive      No hacer preguntas (los duplicados se resuelven automáticamente)
  -h, --help            Mostrar esta ayuda
EOF
}

# ============================================================================
# Dependency Checking
# ============================================================================

check_dependencies() {
    print_section "VERIFICANDO DEPENDENCIAS"
    local -a missing=()
    local dep

    for dep in jdupes exiftool jq; do
        if command -v "$dep" >/dev/null 2>&1; then
            print_success "$dep encontrado"
        else
            missing+=("$dep")
        fi
    done
    command -v fzf >/dev/null 2>&1 || print_info "Tip: instala 'fzf' para elegir carpetas más fácilmente."

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warn "Faltan dependencias: ${missing[*]}"
        if [[ "$INTERACTIVE" == "true" ]] && confirm "¿Instalarlas ahora con Homebrew?"; then
            command -v brew >/dev/null 2>&1 || die "Homebrew no está instalado (https://brew.sh)."
            brew install "${missing[@]}" || die "No se pudieron instalar las dependencias."
        else
            die "No se puede continuar sin: ${missing[*]}  (brew install ${missing[*]})"
        fi
    fi
}

# ============================================================================
# User Input / Configuration
# ============================================================================

get_user_config() {
    print_header "FILE ORGANIZER & DUPLICATE FINDER"

    # 1. Origen
    print_section "ORIGEN"
    select_source_directory SOURCE_DIR

    # 2. Destino
    print_section "DESTINO"
    local -a dest_options=(
        "Dentro del mismo origen (carpeta '_Organized')"
        "Elegir otra carpeta o disco de destino"
    )
    local dest_choice=$(select_menu "¿Dónde guardar los archivos organizados?" "${dest_options[@]}")
    if [[ "$dest_choice" == "1" ]]; then
        DEST_ROOT="$SOURCE_DIR/_Organized"
        print_success "Destino: $DEST_ROOT"
    else
        read_path "Carpeta de destino" DEST_ROOT "" true
    fi

    # 3. Subcarpeta de lote (opcional)
    print_section "SUBCARPETA DE LOTE (OPCIONAL)"
    print_info "Por defecto los archivos van directo a su categoría (Imagenes/, Videos/...)."
    print_info "Si quieres agruparlos bajo un nombre (ej. iPhone_2023), escríbelo; si no, pulsa Enter."
    while true; do
        printf "${COLORS[CYAN]}%s ${COLORS[RESET]}Nombre del lote (opcional): " "${SYMBOLS[FILE]}" >&2
        read -r BACKUP_ID || BACKUP_ID=""
        BACKUP_ID="${BACKUP_ID// /_}"
        if [[ -z "$BACKUP_ID" ]] || validate_backup_id "$BACKUP_ID"; then
            break
        fi
        print_error "Usa solo letras, números, guion y guion bajo."
    done
    [[ -n "$BACKUP_ID" ]] && print_success "Lote: $BACKUP_ID" || print_info "Sin subcarpeta de lote"

    # 4. Modo de operación
    print_section "MODO DE OPERACIÓN"
    local -a mode_options=(
        "Completo: buscar duplicados y organizar sin ellos"
        "Solo buscar duplicados (reporte, no copia nada)"
        "Solo organizar (sin buscar duplicados)"
    )
    case $(select_menu "Selecciona el modo" "${mode_options[@]}") in
        1) MODE="full" ;;
        2) MODE="duplicates" ;;
        3) MODE="organize" ;;
    esac
    print_success "Modo: $MODE"

    # 5. Opciones
    if [[ "$MODE" != "duplicates" ]]; then
        print_section "OPCIONES"
        if confirm "¿Renombrar fotos y videos por fecha de captura (YYYYMMDD_HHMMSS)?" "Y"; then
            RENAME_ENABLED=true
        else
            RENAME_ENABLED=false
        fi

        local -a copy_mode_options=(
            "Copiar (el origen queda intacto)"
            "Mover (libera espacio en el origen)"
        )
        case $(select_menu "¿Copiar o mover?" "${copy_mode_options[@]}") in
            1) COPY_MODE="copy" ;;
            2) COPY_MODE="move" ;;
        esac

        if [[ "$COPY_MODE" == "move" ]]; then
            if confirm "¿Borrar las carpetas que queden vacías en el origen?" "Y"; then
                CLEANUP_ENABLED=true
            else
                CLEANUP_ENABLED=false
            fi
        fi
    fi

    if confirm "¿Simulación (dry run: muestra qué haría sin modificar nada)?" "N"; then
        DRY_RUN=true
        print_warn "MODO SIMULACIÓN ACTIVADO"
    else
        DRY_RUN=false
    fi

    # Resumen
    print_config_summary
    local est_size=$(estimate_source_size "$SOURCE_DIR")
    (( est_size > 0 )) && printf "  ${COLORS[BOLD]}Tamaño origen:${COLORS[RESET]}   %s\n" "$(format_bytes $est_size)" >&2

    confirm "¿Continuar con esta configuración?" || exit 0
}

print_config_summary() {
    print_section "RESUMEN DE CONFIGURACIÓN"
    printf "  ${COLORS[BOLD]}Origen:${COLORS[RESET]}          %s\n" "$SOURCE_DIR" >&2
    printf "  ${COLORS[BOLD]}Destino:${COLORS[RESET]}         %s\n" "$DEST_ROOT" >&2
    printf "  ${COLORS[BOLD]}Lote:${COLORS[RESET]}            %s\n" "${BACKUP_ID:-(ninguno)}" >&2
    printf "  ${COLORS[BOLD]}Modo:${COLORS[RESET]}            %s\n" "$MODE" >&2
    if [[ "$MODE" != "duplicates" ]]; then
        printf "  ${COLORS[BOLD]}Copiar/Mover:${COLORS[RESET]}    %s\n" "$COPY_MODE" >&2
        printf "  ${COLORS[BOLD]}Renombrar:${COLORS[RESET]}       %s\n" "$([[ $RENAME_ENABLED == true ]] && echo 'sí (solo fotos/videos)' || echo no)" >&2
    fi
    [[ "$DRY_RUN" == "true" ]] && printf "  ${COLORS[BOLD]}Simulación:${COLORS[RESET]}      sí\n" >&2
    return 0
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --source|--dest|--backup-id|--mode)
                [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "Falta el valor para $1"
                case "$1" in
                    --source)    SOURCE_DIR="$2" ;;
                    --dest)      DEST_ROOT="$2" ;;
                    --backup-id) BACKUP_ID="$2" ;;
                    --mode)      MODE="$2" ;;
                esac
                shift 2 ;;
            --dry-run)        DRY_RUN=true; shift ;;
            --move)           COPY_MODE="move"; shift ;;
            --copy)           COPY_MODE="copy"; shift ;;
            --rename)         RENAME_ENABLED=true; shift ;;
            --no-rename)      RENAME_ENABLED=false; shift ;;
            --cleanup)        CLEANUP_ENABLED=true; shift ;;
            --no-cleanup)     CLEANUP_ENABLED=false; shift ;;
            --no-interactive) INTERACTIVE=false; shift ;;
            -h|--help)        usage; exit 0 ;;
            *)
                print_error "Opción desconocida: $1"
                usage >&2
                exit 1 ;;
        esac
    done
}

validate_config() {
    [[ -n "$SOURCE_DIR" ]] || die "Falta el origen (--source)."
    [[ -n "$DEST_ROOT" ]]  || die "Falta el destino (--dest)."

    SOURCE_DIR=$(normalize_path_input "$SOURCE_DIR")
    DEST_ROOT=$(normalize_path_input "$DEST_ROOT")
    [[ -d "$SOURCE_DIR" ]] || die "El origen no existe o no es una carpeta: $SOURCE_DIR"

    SOURCE_DIR="${SOURCE_DIR:A}"
    DEST_ROOT="${DEST_ROOT:A}"

    case "$MODE" in
        full|duplicates|organize) ;;
        *) die "Modo inválido: '$MODE' (usa full, duplicates u organize)" ;;
    esac

    BACKUP_ID="${BACKUP_ID// /_}"
    if [[ -n "$BACKUP_ID" ]] && ! validate_backup_id "$BACKUP_ID"; then
        die "Nombre de lote inválido: '$BACKUP_ID' (solo letras, números, - y _)"
    fi

    # Origen y destino iguales: organizar dentro de una subcarpeta del origen
    if [[ "$DEST_ROOT" == "$SOURCE_DIR" ]]; then
        DEST_ROOT="$SOURCE_DIR/_Organized"
        print_info "Origen y destino son iguales; se usará: $DEST_ROOT"
    fi

    if [[ "$SOURCE_DIR/" == "$DEST_ROOT/"* ]]; then
        die "El origen no puede estar dentro del destino."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        # La simulación no debe crear nada en el destino: el log va a un temporal.
        LOG_FILE=$(mktemp -t media-sorter-dryrun) || die "No se pudo crear el log temporal."
    else
        mkdir -p "$DEST_ROOT" 2>/dev/null || die "No se pudo crear el destino: $DEST_ROOT"
        [[ -w "$DEST_ROOT" ]] || die "No hay permiso de escritura en el destino: $DEST_ROOT"
        LOG_FILE="$DEST_ROOT/management_log.txt"
    fi
    {
        echo "# ===== $(date '+%Y-%m-%d %H:%M:%S') ====="
        echo "# Origen: $SOURCE_DIR"
        echo "# Destino: $DEST_ROOT"
        echo "# Modo: $MODE | $COPY_MODE | rename=$RENAME_ENABLED | dry_run=$DRY_RUN"
    } >> "$LOG_FILE"

    DUP_REPORT_FILE="${LOG_FILE:h}/duplicados_$(date '+%Y%m%d_%H%M%S').txt"
    DUP_JSON_FILE=$(mktemp -t media-sorter-dups) || die "No se pudo crear un archivo temporal."
}

# ============================================================================
# Pipeline
# ============================================================================

run_duplicate_scan() {
    [[ "$MODE" == "organize" ]] && return 0
    print_section "BUSCANDO DUPLICADOS"

    if ! scan_duplicates "$SOURCE_DIR" "$DUP_JSON_FILE"; then
        [[ "$MODE" == "duplicates" ]] && die "No se pudo completar la búsqueda de duplicados."
        if [[ "$INTERACTIVE" == "true" ]] && confirm "¿Continuar organizando SIN omitir duplicados?" "N"; then
            return 0
        fi
        die "Operación cancelada: falló la búsqueda de duplicados."
    fi

    parse_jdupes_output "$DUP_JSON_FILE"
    if (( ${#DUP_GROUPS[@]} == 0 )); then
        print_success "No se encontraron duplicados"
        return 0
    fi

    display_duplicate_report "$DUP_REPORT_FILE"
    [[ "$MODE" == "duplicates" ]] && return 0

    if [[ "$INTERACTIVE" == "true" ]] && confirm "¿Elegir manualmente qué copia conservar en cada grupo? (No = usar la sugerencia)" "N"; then
        if ! resolve_duplicates_interactive; then
            print_warn "Operación cancelada por el usuario."
            exit 0
        fi
    else
        resolve_duplicates_auto
    fi
    print_info "Se omitirán ${#REMOVE_FILES[@]} copias duplicadas (se conserva una de cada grupo)."
}

organize_files() {
    [[ "$MODE" == "duplicates" ]] && return 0
    print_section "ORGANIZANDO ARCHIVOS"

    local -a all_files=()
    local file
    print_info "Escaneando el origen..."
    while IFS= read -r -d '' file; do
        all_files+=("$file")
    done < <(scan_files "$SOURCE_DIR")

    STAT_TOTAL=${#all_files[@]}
    print_info "Archivos encontrados: $STAT_TOTAL"
    (( STAT_TOTAL == 0 )) && return 0

    # Mover dentro del mismo disco = rename instantáneo, sin espacio adicional.
    MOVE_SAME_FS=false
    if [[ "$COPY_MODE" == "move" ]] && same_filesystem "$SOURCE_DIR" "$DEST_ROOT"; then
        MOVE_SAME_FS=true
    fi

    # Espacio necesario: solo lo que realmente se va a copiar.
    local -i needed=0
    if [[ "$MOVE_SAME_FS" != "true" ]]; then
        local -a st
        for file in "${all_files[@]}"; do
            is_duplicate_to_remove "$file" && continue
            zstat -A st +size -- "$file" 2>/dev/null && (( needed += st[1] ))
        done
    fi
    local -i free_dest=$(get_free_space_bytes "$DEST_ROOT")
    local -i needed_with_margin=$(( needed + needed / 20 ))   # +5 % de margen
    if (( needed_with_margin > free_dest )); then
        local msg="Espacio insuficiente en el destino: se necesitan $(format_bytes $needed_with_margin) y hay $(format_bytes $free_dest) libres."
        if [[ "$DRY_RUN" == "true" ]]; then
            print_warn "$msg (simulación: se continúa igualmente)"
        else
            print_error "$msg"
            if [[ "$COPY_MODE" == "copy" ]] && same_filesystem "$SOURCE_DIR" "$DEST_ROOT"; then
                print_info "Sugerencia: origen y destino están en el mismo disco; usa el modo Mover (--move), que no necesita espacio extra."
            fi
            ABORT_REASON="espacio insuficiente en el destino"
            return 1
        fi
    else
        print_info "Espacio necesario: $(format_bytes $needed) · libre: $(format_bytes $free_dest)"
    fi

    cleanup_temp_files "$DEST_ROOT" "$LOG_FILE"

    # Leer las fechas de todas las fotos/videos con una sola ejecución de exiftool
    if [[ "$RENAME_ENABLED" == "true" ]]; then
        local -a media_files=()
        local media_cat=""
        for file in "${all_files[@]}"; do
            is_duplicate_to_remove "$file" && continue
            categorize_file "$file" media_cat
            is_media_category "$media_cat" && media_files+=("$file")
        done
        if (( ${#media_files[@]} > 0 )); then
            print_info "Leyendo fechas de ${#media_files[@]} fotos y videos..."
            preload_media_dates "${media_files[@]}"
        fi
    fi

    local category="" rel_path="" rel_dir="" dest_dir="" new_name="" dest_path="" orig_name="" action=""
    local -i idx=0 result=0
    action="COPY"; [[ "$COPY_MODE" == "move" ]] && action="MOVE"
    # Redibujar la barra ~500 veces como máximo, no una vez por archivo
    local -i progress_step=$(( STAT_TOTAL / 500 > 0 ? STAT_TOTAL / 500 : 1 ))

    init_progress
    for (( idx=1; idx<=STAT_TOTAL; idx++ )); do
        file="${all_files[idx]}"
        (( idx % progress_step == 0 || idx == STAT_TOTAL )) && show_progress "$idx" "$STAT_TOTAL"

        if is_duplicate_to_remove "$file"; then
            (( ++STAT_SKIPPED_DUP ))
            log_operation "$LOG_FILE" "SKIP_DUP" "$file" "" "duplicate"
            continue
        fi

        categorize_file "$file" category

        # Se conserva la estructura de carpetas original dentro de cada categoría
        rel_path="${file#$SOURCE_DIR/}"
        rel_dir=""
        [[ "$rel_path" == */* ]] && rel_dir="${rel_path%/*}"

        dest_dir="$DEST_ROOT/$category"
        [[ -n "$BACKUP_ID" ]] && dest_dir+="/$BACKUP_ID"
        [[ -n "$rel_dir" ]] && dest_dir+="/$rel_dir"

        if [[ "$DRY_RUN" != "true" && ! -d "$dest_dir" ]]; then
            if ! mkdir -p "$dest_dir" 2>/dev/null; then
                log_operation "$LOG_FILE" "ERROR" "$file" "$dest_dir" "mkdir failed"
                (( ++STAT_ERRORS ))
                continue
            fi
        fi

        orig_name="${file:t}"
        if [[ "$RENAME_ENABLED" == "true" ]] && is_media_category "$category"; then
            determine_filename "$file" "$dest_dir"
        else
            generate_unique_name "$dest_dir" "$orig_name" "$file"
        fi
        new_name="${REPLY:-$orig_name}"
        dest_path="$dest_dir/$new_name"

        # generate_unique_name solo devuelve un nombre existente si el contenido es idéntico
        if [[ -f "$dest_path" ]]; then
            (( ++STAT_SKIPPED_EXIST ))
            log_operation "$LOG_FILE" "SKIP_EXIST" "$file" "$dest_path" "identical file already in destination"
            continue
        fi

        result=0
        if [[ "$COPY_MODE" == "move" ]]; then
            move_file "$file" "$dest_path" "$LOG_FILE" "$action" "" || result=$?
        else
            copy_file "$file" "$dest_path" "$LOG_FILE" "$action" "" || result=$?
        fi

        if (( result == 0 )); then
            (( ++STAT_COPIED ))
            [[ "$new_name" != "$orig_name" ]] && (( ++STAT_RENAMED ))
        else
            (( ++STAT_ERRORS ))
        fi
    done
    finish_progress
    return 0
}

run_cleanup() {
    [[ "$CLEANUP_ENABLED" == "true" && "$COPY_MODE" == "move" && "$MODE" != "duplicates" ]] || return 0
    [[ -n "$ABORT_REASON" ]] && return 0
    print_section "LIMPIEZA"
    cleanup_empty_dirs "$SOURCE_DIR" "$LOG_FILE"
}

show_final_report() {
    local verb="copiados"
    [[ "$COPY_MODE" == "move" ]] && verb="movidos"
    [[ "$DRY_RUN" == "true" ]] && verb+=" (simulado)"

    print_header "RESULTADO"
    if [[ "$MODE" == "duplicates" ]]; then
        printf "\n  ${COLORS[BOLD]}Duplicados:${COLORS[RESET]}\n" >&2
        printf "  %-28s %d\n" "Grupos encontrados:" "${#DUP_GROUPS[@]}" >&2
        printf "  %-28s %s\n" "Espacio recuperable:" "$(format_bytes $DUP_WASTED_BYTES)" >&2
        (( ${#DUP_GROUPS[@]} > 0 )) && printf "  %-28s %s\n" "Reporte:" "$DUP_REPORT_FILE" >&2
    else
        printf "\n  ${COLORS[BOLD]}Estadísticas:${COLORS[RESET]}\n" >&2
        printf "  ${COLORS[GREEN]}%-28s${COLORS[RESET]} %d\n" "Archivos $verb:" "$STAT_COPIED" >&2
        printf "  ${COLORS[YELLOW]}%-28s${COLORS[RESET]} %d\n" "Duplicados omitidos:" "$STAT_SKIPPED_DUP" >&2
        printf "  ${COLORS[BLUE]}%-28s${COLORS[RESET]} %d\n" "Ya existían en destino:" "$STAT_SKIPPED_EXIST" >&2
        printf "  ${COLORS[MAGENTA]}%-28s${COLORS[RESET]} %d\n" "Renombrados por fecha:" "$STAT_RENAMED" >&2
        printf "  ${COLORS[RED]}%-28s${COLORS[RESET]} %d\n" "Errores:" "$STAT_ERRORS" >&2
    fi
    printf "\n" >&2

    if [[ -n "$ABORT_REASON" ]]; then
        print_error "No se organizó nada: $ABORT_REASON."
    elif (( STAT_ERRORS > 0 )); then
        print_warn "Terminado con $STAT_ERRORS errores. Revisa el log: $LOG_FILE"
    elif [[ "$DRY_RUN" == "true" ]]; then
        print_success "Simulación terminada: no se modificó nada. Detalle en: $LOG_FILE"
    else
        print_success "Proceso terminado correctamente. Log: $LOG_FILE"
    fi
}

main() {
    trap 'finish_progress 2>/dev/null; print_error "Interrumpido"; exit 130' INT

    if (( $# == 0 )); then
        [[ -t 0 ]] || die "El modo interactivo necesita una terminal. Usa --help para el modo por argumentos."
        check_dependencies
        get_user_config
    else
        parse_args "$@"
        [[ -t 0 ]] || INTERACTIVE=false
        check_dependencies
    fi
    validate_config
    (( $# > 0 )) && print_config_summary

    local start_time=$SECONDS
    run_duplicate_scan
    organize_files
    run_cleanup
    show_final_report
    print_info "Tiempo total: $(( SECONDS - start_time ))s"

    [[ -f "$DUP_JSON_FILE" ]] && rm -f "$DUP_JSON_FILE"
    [[ -n "$ABORT_REASON" ]] && exit 1
    (( STAT_ERRORS > 0 )) && exit 2
    exit 0
}

main "$@"
