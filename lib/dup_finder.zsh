#!/usr/bin/env zsh
# ============================================================================
# Duplicate Finder - jdupes Integration
# ============================================================================
#
# Cada grupo de duplicados se guarda en DUP_GROUPS como un único string:
#     tamaño<US>archivo1<US>archivo2...
# donde <US> es el carácter ASCII "Unit Separator" (0x1F), que no aparece en
# nombres de archivo reales (a diferencia de '|'). El primer archivo es la
# copia sugerida para conservar.

typeset -ga DUP_GROUPS=()
typeset -ga KEEP_FILES=()
typeset -ga REMOVE_FILES=()
typeset -gA REMOVE_SET=()
typeset -gi DUP_WASTED_BYTES=0
typeset -ga PROTECTED_DIRS   # definido en protect.zsh

# Separa un grupo en el array global `reply`: (tamaño archivo1 archivo2 ...)
split_group() {
    reply=("${(@ps:\x1f:)1}")
}

scan_duplicates() {
    local source_dir="$1"
    local output_file="$2"
    local err_file="${output_file}.err"
    local item

    # -r recursivo, -j salida JSON, -q sin barra de progreso, -H incluir hardlinks
    local -a cmd=(jdupes -r -j -q -H)

    # Mismas exclusiones que scan_files (filtro "nostr" = la ruta contiene el
    # texto), así jdupes ni siquiera calcula hashes de esos archivos:
    # todo lo oculto ("/."), carpetas de sistema, datos de apps Android,
    # carpetas protegidas (programas/juegos/proyectos) y el destino.
    if [[ "$source_dir" != */.* ]]; then
        cmd+=(-X "nostr:/.")
    else
        cmd+=(-X "nostr:/._" -X "nostr:/.DS_Store" -X "nostr:/.thumbnails/" -X "nostr:${TMP_SUFFIX}")
    fi
    for item in "${SYSTEM_DIRS[@]}"; do cmd+=(-X "nostr:/$item/"); done
    cmd+=(-X "nostr:/Android/data/" -X "nostr:/Android/obb/" -X "nostr:/Thumbs.db" -X "nostr:/desktop.ini")
    for item in "${PROTECTED_DIRS[@]}"; do cmd+=(-X "nostr:$item/"); done
    if [[ -n "${DEST_ROOT:-}" && "$DEST_ROOT" == "$source_dir"/* ]]; then
        cmd+=(-X "nostr:$DEST_ROOT/")
    fi

    print_info "Buscando duplicados con jdupes (en discos grandes puede tardar)..."
    # Solo stdout va al JSON; los avisos de stderr (permisos, etc.) van aparte
    # para no corromper el JSON.
    "${cmd[@]}" "$source_dir" > "$output_file" 2> "$err_file"
    local rc=$?

    if ! jq -e '.matchSets' "$output_file" >/dev/null 2>&1; then
        print_error "jdupes falló (código $rc):"
        head -5 "$err_file" >&2
        rm -f "$err_file"
        return 1
    fi

    local warn_count=$(grep -c . "$err_file" 2>/dev/null)
    if (( ${warn_count:-0} > 0 )); then
        print_warn "jdupes no pudo leer algunos archivos ($warn_count avisos); se ignoraron."
    fi
    rm -f "$err_file"

    local group_count=$(jq '.matchSets | length' "$output_file")
    print_success "Grupos de duplicados encontrados: $group_count"
    return 0
}

# Convierte el JSON de jdupes en DUP_GROUPS con una sola llamada a jq.
# Ordena cada grupo para sugerir como "original" el archivo cuyo nombre no
# parece una copia (copia, copy, "(1)") y, a igualdad, la ruta más corta.
parse_jdupes_output() {
    local json_file="$1"
    local line
    DUP_GROUPS=()
    DUP_WASTED_BYTES=0

    while IFS= read -r -d $'\0' line; do
        [[ -n "$line" ]] && DUP_GROUPS+=("$line")
    done < <(jq -j '
        .matchSets[]
        | ([.fileList[].filePath]
           | sort_by([ (split("/")[-1] | test("(?i)copia|copy|duplicad|\\(\\d+\\)")), length ])) as $files
        | ([(.fileSize | tostring)] + $files | join("\u001f")) + "\u0000"
    ' "$json_file" 2>/dev/null)

    local group
    for group in "${DUP_GROUPS[@]}"; do
        split_group "$group"
        (( DUP_WASTED_BYTES += reply[1] * (${#reply[@]} - 2) ))
    done
}

# Muestra un resumen en pantalla (máx. 20 grupos) y guarda el reporte completo.
display_duplicate_report() {
    local report_file="${1:-}"
    local total=${#DUP_GROUPS[@]}
    (( total == 0 )) && return 0

    local max_show=20
    local group_num=0 group f size
    local -a files

    print_section "REPORTE DE DUPLICADOS"
    printf "${COLORS[BOLD]}%d grupos de archivos idénticos · espacio recuperable: %s${COLORS[RESET]}\n\n" \
        "$total" "$(format_bytes $DUP_WASTED_BYTES)" >&2

    [[ -n "$report_file" ]] && : > "$report_file"

    for group in "${DUP_GROUPS[@]}"; do
        (( ++group_num ))
        split_group "$group"
        size="${reply[1]}"
        files=("${reply[@]:1}")

        if [[ -n "$report_file" ]]; then
            {
                printf "Grupo %d · %s · %d archivos\n" "$group_num" "$(format_bytes $size)" "${#files[@]}"
                printf "  CONSERVAR  %s\n" "${files[1]}"
                for f in "${files[@]:1}"; do printf "  omitir     %s\n" "$f"; done
                printf "\n"
            } >> "$report_file"
        fi

        (( group_num > max_show )) && continue
        printf "${COLORS[BG_BLUE]}${COLORS[WHITE]}${COLORS[BOLD]} GRUPO %d ${COLORS[RESET]} ${COLORS[DIM]}%s c/u │ %d archivos${COLORS[RESET]}\n" \
            "$group_num" "$(format_bytes $size)" "${#files[@]}" >&2
        printf "  ${COLORS[GREEN]}%s${COLORS[RESET]} %s ${COLORS[DIM]}(se conserva)${COLORS[RESET]}\n" "${SYMBOLS[CHECK]}" "${files[1]#$SOURCE_DIR/}" >&2
        for f in "${files[@]:1}"; do
            printf "  ${COLORS[RED]}%s${COLORS[RESET]} %s\n" "${SYMBOLS[CROSS]}" "${f#$SOURCE_DIR/}" >&2
        done
        printf "\n" >&2
    done

    if (( total > max_show )); then
        print_info "... y $(( total - max_show )) grupos más."
    fi
    [[ -n "$report_file" ]] && print_info "Reporte completo: $report_file"
}

# Marca la posición `keep` como conservada y el resto como duplicados a omitir.
_mark_group() {
    local keep="$1"; shift
    local -a group_files=("$@")
    local i
    for (( i=1; i<=${#group_files[@]}; i++ )); do
        if (( i == keep )); then
            KEEP_FILES+=("${group_files[i]}")
        else
            REMOVE_FILES+=("${group_files[i]}")
        fi
    done
}

_build_remove_set() {
    local f
    REMOVE_SET=()
    for f in "${REMOVE_FILES[@]}"; do
        REMOVE_SET[$f]=1
    done
}

# Devuelve 1 si el usuario cancela la operación.
resolve_duplicates_interactive() {
    KEEP_FILES=()
    REMOVE_FILES=()
    local total=${#DUP_GROUPS[@]}
    (( total == 0 )) && return 0

    print_section "RESOLUCIÓN DE DUPLICADOS"
    local n=0 group g f mtime choice nf
    local -a files menu_options

    for group in "${DUP_GROUPS[@]}"; do
        (( ++n ))
        split_group "$group"
        local size="${reply[1]}"
        files=("${reply[@]:1}")
        nf=${#files[@]}

        menu_options=()
        for f in "${files[@]}"; do
            mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null)
            menu_options+=("Conservar: ${f#$SOURCE_DIR/} ($mtime)")
        done
        menu_options+=(
            "Conservar todos (no omitir ninguno)"
            "Usar la sugerencia en este y todos los grupos restantes"
            "Cancelar operación"
        )

        choice=$(select_menu "Grupo $n/$total · $(format_bytes $size) c/u" "${menu_options[@]}")

        if (( choice <= nf )); then
            _mark_group "$choice" "${files[@]}"
        elif (( choice == nf + 1 )); then
            KEEP_FILES+=("${files[@]}")
        elif (( choice == nf + 2 )); then
            for g in "${(@)DUP_GROUPS[n,-1]}"; do
                split_group "$g"
                _mark_group 1 "${reply[@]:1}"
            done
            break
        else
            return 1
        fi
    done

    _build_remove_set
    return 0
}

# Conserva la copia sugerida (la primera) de cada grupo.
resolve_duplicates_auto() {
    KEEP_FILES=()
    REMOVE_FILES=()
    local group
    for group in "${DUP_GROUPS[@]}"; do
        split_group "$group"
        _mark_group 1 "${reply[@]:1}"
    done
    _build_remove_set
}

is_duplicate_to_remove() {
    (( ${+REMOVE_SET[$1]} ))
}
