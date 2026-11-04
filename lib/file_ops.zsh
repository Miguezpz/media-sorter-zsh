#!/usr/bin/env zsh
# ============================================================================
# File Operations - Categorize, Copy, Cleanup, Atomic Write
# ============================================================================

zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -gA CATEGORIES
CATEGORIES=(
    Imagenes    "jpg jpeg png gif heic heif webp raw cr2 cr3 nef arw dng tiff tif bmp"
    Videos      "mp4 mov avi mkv m4v 3gp mpg mpeg wmv flv webm mts m2ts"
    Audio       "mp3 wav aac flac m4a ogg wma aiff aif"
    Documentos  "pdf doc docx txt xls xlsx ppt pptx md rtf odt ods odp pages numbers key csv"
)

# Carpetas de sistema que nunca deben procesarse (macOS, Windows y la propia salida).
typeset -ga SYSTEM_DIRS=(
    .Trashes .Spotlight-V100 .fseventsd .TemporaryItems .DocumentRevisions-V100
    .PKInstallSandboxManager .PKInstallSandboxManager-SystemSoftware
    '$RECYCLE.BIN' 'System Volume Information' _Organized
)

# Archivos basura: metadatos de Finder, AppleDouble (._*) en discos exFAT/FAT,
# miniaturas de Windows y temporales propios de este programa.
typeset -ga SYSTEM_FILES=(
    .DS_Store '._*' .localized Thumbs.db desktop.ini '*.msort-tmp'
)

# Sufijo de los temporales de copia atómica (solo se limpian los nuestros).
typeset -g TMP_SUFFIX=".msort-tmp"

categorize_file() {
    local filepath="$1"
    local out_var="${2:-}"
    local ext="${filepath:t}"
    if [[ "$ext" == *.* ]]; then
        ext="${${ext##*.}:l}"
    else
        ext=""
    fi
    local result="Otros" cat_name

    if [[ -n "$ext" ]]; then
        for cat_name in "${(@k)CATEGORIES}"; do
            if [[ " ${CATEGORIES[$cat_name]} " == *" $ext "* ]]; then
                result="$cat_name"
                break
            fi
        done
    fi

    if [[ -n "$out_var" ]]; then
        typeset -g "$out_var=$result"
    else
        echo "$result"
    fi
}

is_media_category() {
    [[ "$1" == "Imagenes" || "$1" == "Videos" ]]
}

# Ruta del temporal para una copia atómica: oculto y junto al destino.
tmp_path_for() {
    local dest="$1"
    echo "${dest:h}/.${dest:t}${TMP_SUFFIX}"
}

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

    local tmp_dest=$(tmp_path_for "$dest")
    if ! cp -p "$src" "$tmp_dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Copy failed: $details"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    local src_size=$(get_file_size "$src")
    local tmp_size=$(get_file_size "$tmp_dest")
    if [[ "$src_size" != "$tmp_size" ]]; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Size mismatch after copy"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    if ! mv "$tmp_dest" "$dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Failed atomic rename"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    log_operation "$log_file" "$action" "$src" "$dest" "$details"
    return 0
}

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

    local tmp_dest=$(tmp_path_for "$dest")
    if ! cp -p "$src" "$tmp_dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Move phase failed: $details"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    local src_size=$(get_file_size "$src")
    local tmp_size=$(get_file_size "$tmp_dest")
    if [[ "$src_size" != "$tmp_size" ]]; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Size mismatch after copy"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    local src_hash=$(get_file_hash "$src")
    local tmp_hash=$(get_file_hash "$tmp_dest")
    if [[ -z "$src_hash" || "$src_hash" != "$tmp_hash" ]]; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Hash mismatch after copy"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    if ! mv "$tmp_dest" "$dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Failed atomic rename"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    if ! rm -f "$src" 2>/dev/null; then
        log_operation "$log_file" "WARN" "$src" "$dest" "Moved ok but source deletion failed"
        return 0
    fi
    log_operation "$log_file" "$action" "$src" "$dest" "$details"
    return 0
}

# Borra solo los temporales que este programa dejó en una ejecución interrumpida.
cleanup_temp_files() {
    local dest_root="$1"
    local log_file="$2"
    local count=0 tmp_file
    [[ "$DRY_RUN" == "true" || ! -d "$dest_root" ]] && return 0
    while IFS= read -r -d '' tmp_file; do
        if rm -f "$tmp_file" 2>/dev/null; then
            log_operation "$log_file" "CLEAN_TMP" "$tmp_file" "" "Removed orphaned temp file"
            (( ++count ))
        fi
    done < <(find "$dest_root" -type f -name "*${TMP_SUFFIX}" -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        print_info "Limpiados $count archivos temporales de una ejecución anterior."
    fi
    return 0
}

log_operation() {
    local log_file="$1"
    local action="$2"
    local src="$3"
    local dest="$4"
    local details="$5"
    [[ -z "$log_file" ]] && return 0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local rel_dest="$dest"
    if [[ -n "${DEST_ROOT:-}" && "$dest" == "$DEST_ROOT"/* ]]; then
        rel_dest="${dest#$DEST_ROOT/}"
    fi
    printf "%s | %-8s | %s | %s | %s\n" "$timestamp" "$action" "$src" "$rel_dest" "$details" >> "$log_file" 2>/dev/null || true
}

# ¿Es un archivo basura que no impide considerar vacía una carpeta?
is_junk_file() {
    local name="${1:t}"
    [[ "$name" == (.DS_Store|._*|.localized|Thumbs.db|desktop.ini) ]]
}

# Elimina carpetas vacías del origen (las que solo contienen .DS_Store y
# similares también cuentan como vacías). Nunca toca el destino ni el propio origen.
cleanup_empty_dirs() {
    local source_dir="$1"
    local log_file="$2"
    local count=0 dir entry
    local -a entries real junk
    local comp skip_dir

    print_info "Limpiando carpetas vacías en el origen..."
    # Nota: -prune no funciona junto con -depth, por eso se filtra en el bucle.
    while IFS= read -r -d '' dir; do
        [[ -n "${DEST_ROOT:-}" && ( "$dir" == "$DEST_ROOT" || "$dir" == "$DEST_ROOT"/* ) ]] && continue
        skip_dir=false
        for comp in "${(@s:/:)${dir#$source_dir/}}"; do
            if (( ${SYSTEM_DIRS[(Ie)$comp]} )); then skip_dir=true; break; fi
        done
        [[ "$skip_dir" == "true" ]] && continue

        entries=("$dir"/*(DN))
        real=() junk=()
        for entry in "${entries[@]}"; do
            if [[ -f "$entry" ]] && is_junk_file "$entry"; then
                junk+=("$entry")
            else
                real+=("$entry")
            fi
        done
        (( ${#real[@]} > 0 )) && continue

        if [[ "$DRY_RUN" == "true" ]]; then
            log_operation "$log_file" "CLEANUP" "$dir" "" "(DRY RUN)"
            (( ++count ))
        else
            (( ${#junk[@]} )) && rm -f -- "${junk[@]}" 2>/dev/null
            if rmdir "$dir" 2>/dev/null; then
                log_operation "$log_file" "CLEANUP" "$dir" "" "Removed empty directory"
                (( ++count ))
            fi
        fi
    done < <(find "$source_dir" -mindepth 1 -depth -type d -print0 2>/dev/null)
    print_success "Carpetas vacías eliminadas: $count"
}

# Lista (separada por NUL) los archivos a organizar, excluyendo basura del
# sistema, carpetas _Organized previas y el destino si está dentro del origen.
scan_files() {
    local source_dir="$1"
    local -a prune=() skip=()
    local item

    for item in "${SYSTEM_DIRS[@]}"; do prune+=(-name "$item" -o); done
    if [[ -n "${DEST_ROOT:-}" && "$DEST_ROOT" == "$source_dir"/* ]]; then
        prune+=(-path "$DEST_ROOT" -o)
    fi
    prune[-1]=()   # quitar el último -o

    for item in "${SYSTEM_FILES[@]}"; do skip+=(-not -name "$item"); done

    find "$source_dir" -mindepth 1 \( -type d \( "${prune[@]}" \) -prune \) -o \
        -type f "${skip[@]}" -print0 2>/dev/null
}

detect_external_volumes() {
    local vol vol_name
    for vol in /Volumes/*(/N); do
        vol_name="${vol##*/}"
        if [[ "$vol_name" =~ ^(Macintosh\ HD|Recovery|Preboot|VM|Update|Data|com\.apple\..*)$ ]]; then
            continue
        fi
        # No se exige escritura: los discos NTFS se montan como solo lectura
        # en macOS y siguen siendo un origen válido.
        [[ -d "$vol" && -r "$vol" ]] && echo "$vol"
    done
}

get_volume_info() {
    local vol_path="$1"
    local vol_name="${vol_path##*/}"
    local free_space=$(df -h "$vol_path" 2>/dev/null | awk 'NR==2 {print $4}')
    local ro=""
    [[ -w "$vol_path" ]] || ro=" (solo lectura)"
    echo "$vol_name|$vol_path|${free_space:-?}${ro}"
}

# Carpeta existente más cercana (para medir espacio de un destino aún no creado).
nearest_existing_dir() {
    local p="$1"
    while [[ -n "$p" && ! -d "$p" ]]; do
        p="${p:h}"
    done
    echo "${p:-/}"
}

get_free_space_bytes() {
    local path=$(nearest_existing_dir "$1")
    /bin/df -k "$path" 2>/dev/null | /usr/bin/awk 'NR==2 {printf "%.0f", $4 * 1024}'
}

# ¿Están ambas rutas en el mismo sistema de archivos?
same_filesystem() {
    local a=$(nearest_existing_dir "$1") b=$(nearest_existing_dir "$2")
    local -a da db
    zstat -A da +device -- "$a" 2>/dev/null || return 1
    zstat -A db +device -- "$b" 2>/dev/null || return 1
    [[ "${da[1]}" == "${db[1]}" ]]
}

format_bytes() {
    local bytes="${1:-0}"
    if (( bytes >= 1099511627776 )); then
        printf "%.1f TB\n" $(( bytes / 1099511627776.0 ))
    elif (( bytes >= 1073741824 )); then
        printf "%.1f GB\n" $(( bytes / 1073741824.0 ))
    elif (( bytes >= 1048576 )); then
        printf "%.1f MB\n" $(( bytes / 1048576.0 ))
    elif (( bytes >= 1024 )); then
        printf "%.1f KB\n" $(( bytes / 1024.0 ))
    else
        echo "${bytes} B"
    fi
}

estimate_source_size() {
    local source_dir="$1"
    local kb=$(/usr/bin/du -sk "$source_dir" 2>/dev/null | /usr/bin/awk '{print $1}')
    if [[ -n "$kb" && "$kb" =~ ^[0-9]+$ ]]; then
        echo $(( kb * 1024 ))
    else
        echo "0"
    fi
}

get_file_size() {
    local -a st
    if zstat -A st +size -- "$1" 2>/dev/null; then
        echo "${st[1]}"
    else
        echo "0"
    fi
}

get_file_hash() {
    local filepath="$1"
    md5 -q "$filepath" 2>/dev/null || echo ""
}

# Devuelve un nombre libre en dest_dir. Si ya existe un archivo con el mismo
# nombre Y el mismo contenido que src_file, devuelve ese nombre (el llamador
# lo detecta con -f y lo omite). El hash solo se calcula cuando hay colisión.
generate_unique_name() {
    local dest_dir="$1"
    local filename="$2"
    local src_file="${3:-}"

    local base="${filename%.*}"
    local ext="${filename##*.}"
    if [[ "$base" == "$filename" || -z "$base" ]]; then
        base="$filename"
        ext=""
    else
        ext=".$ext"
    fi

    local candidate="$filename"
    local counter=1
    local src_hash="" dest_hash

    while [[ -e "$dest_dir/$candidate" ]]; do
        if [[ -n "$src_file" && -f "$dest_dir/$candidate" ]]; then
            [[ -z "$src_hash" ]] && src_hash=$(get_file_hash "$src_file")
            dest_hash=$(get_file_hash "$dest_dir/$candidate")
            if [[ -n "$src_hash" && "$src_hash" == "$dest_hash" ]]; then
                echo "$candidate"
                return 0
            fi
        fi
        candidate="${base}_${counter}${ext}"
        (( ++counter ))
    done

    echo "$candidate"
}
