#!/usr/bin/env zsh
# ============================================================================
# File Operations - Categorize, Copy, Cleanup, Atomic Write
# ============================================================================

zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS 2>/dev/null

# true cuando origen y destino están en el mismo sistema de archivos y se
# está moviendo: entonces basta un rename (mv), instantáneo y sin espacio extra.
typeset -g MOVE_SAME_FS=false

typeset -gA CATEGORIES
CATEGORIES=(
    Imagenes    "jpg jpeg png gif heic heif webp raw cr2 cr3 nef arw dng tiff tif bmp"
    Videos      "mp4 mov avi mkv m4v 3gp mpg mpeg wmv flv webm mts m2ts"
    Audio       "mp3 wav aac flac m4a ogg wma aiff aif"
    Documentos  "pdf doc docx txt xls xlsx ppt pptx md rtf odt ods odp pages numbers key csv"
)

# Extensión -> categoría (se construye una vez a partir de CATEGORIES)
typeset -gA EXT_CATEGORY=()
() {
    local c e
    for c in "${(@k)CATEGORIES}"; do
        for e in ${=CATEGORIES[$c]}; do EXT_CATEGORY[$e]="$c"; done
    done
}

# Qué NO se procesa nunca:
# - Todo lo oculto (nombre que empieza por "."): .DS_Store, AppleDouble ._*,
#   .Trashes, .Spotlight-V100, .thumbnails de Android, .Statuses de WhatsApp,
#   .git, temporales propios (.*.msort-tmp)...
# - Carpetas de sistema de Windows y salidas previas de este programa.
# - Datos internos de apps Android (Android/data, Android/obb). OJO:
#   Android/media SÍ se procesa: ahí guarda WhatsApp las fotos y videos.
typeset -ga SYSTEM_DIRS=('$RECYCLE.BIN' 'System Volume Information' _Organized)
typeset -ga SYSTEM_DIR_PATHS=('*/Android/data' '*/Android/obb')
typeset -ga SYSTEM_FILES=(Thumbs.db desktop.ini)

# Escapa los comodines de una ruta para usarla en "find -path" (rutas con [ ] * ?)
glob_escape() {
    setopt localoptions extendedglob
    REPLY="${1//(#m)[][*?\\]/\\$MATCH}"
}

# ¿Debe ignorarse esta ruta (relativa al origen) por ser de sistema u oculta?
is_system_rel_path() {
    local rel="/$1" comp
    [[ "$rel" == */.* ]] && return 0
    [[ "$rel" == */Android/(data|obb)(|/*) ]] && return 0
    for comp in "${(@s:/:)1}"; do
        (( ${SYSTEM_DIRS[(Ie)$comp]} )) && return 0
    done
    return 1
}

# Sufijo de los temporales de copia atómica (solo se limpian los nuestros).
typeset -g TMP_SUFFIX=".msort-tmp"

# Nombres de destino ya asignados durante una simulación (dry run)
typeset -gA DRY_RESERVED=()

# categorize_file RUTA [VARIABLE]
# Deja la categoría en REPLY y, si se indica, también en VARIABLE (asignación
# indirecta, funciona aunque VARIABLE sea local del llamador). Sin VARIABLE,
# la imprime.
categorize_file() {
    local _cf_ext="${1:t}"
    if [[ "$_cf_ext" == ?*.* ]]; then
        _cf_ext="${${_cf_ext##*.}:l}"
        REPLY="${EXT_CATEGORY[$_cf_ext]:-Otros}"
    else
        REPLY="Otros"
    fi

    if [[ -n "${2:-}" ]]; then
        : ${(P)2::=$REPLY}
    else
        echo "$REPLY"
    fi
}

is_media_category() {
    [[ "$1" == "Imagenes" || "$1" == "Videos" ]]
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

    local tmp_dest="${dest:h}/.${dest:t}${TMP_SUFFIX}"
    if ! cp -p "$src" "$tmp_dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Copy failed: $details"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    if ! same_size "$src" "$tmp_dest"; then
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

    # Mismo disco: rename atómico, sin copiar datos.
    if [[ "$MOVE_SAME_FS" == "true" ]]; then
        if [[ -e "$dest" ]] || ! mv -n "$src" "$dest" 2>/dev/null || [[ -e "$src" || ! -f "$dest" ]]; then
            log_operation "$log_file" "ERROR" "$src" "$dest" "Rename failed: $details"
            return 1
        fi
        log_operation "$log_file" "$action" "$src" "$dest" "$details"
        return 0
    fi

    # Otro disco: copiar a temporal, verificar tamaño y hash, y luego borrar el origen.
    local tmp_dest="${dest:h}/.${dest:t}${TMP_SUFFIX}"
    if ! cp -p "$src" "$tmp_dest" 2>/dev/null; then
        log_operation "$log_file" "ERROR" "$src" "$dest" "Move phase failed: $details"
        rm -f "$tmp_dest" 2>/dev/null || true
        return 1
    fi
    if ! same_size "$src" "$tmp_dest"; then
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
    local timestamp
    strftime -s timestamp '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS

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

# Carpetas protegidas: si lib/protect.zsh no está cargado, ninguna.
(( ${+functions[is_protected_path]} )) || is_protected_path() { return 1; }

# Elimina carpetas vacías del origen (las que solo contienen .DS_Store y
# similares también cuentan como vacías). Nunca toca el destino ni el propio origen.
cleanup_empty_dirs() {
    local source_dir="$1"
    local log_file="$2"
    local count=0 dir entry
    local -a entries real junk

    print_info "Limpiando carpetas vacías en el origen..."
    # Nota: -prune no funciona junto con -depth, por eso se filtra en el bucle.
    while IFS= read -r -d '' dir; do
        [[ -n "${DEST_ROOT:-}" && ( "$dir" == "$DEST_ROOT" || "$dir" == "$DEST_ROOT"/* ) ]] && continue
        # Nunca tocar carpetas de sistema/ocultas ni nada dentro de una protegida
        is_system_rel_path "${dir#$source_dir/}" && continue
        (( ${+PROT_SET[$dir]} )) && continue
        is_protected_path "$dir/x" && continue

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

# Lista (separada por NUL) los archivos a organizar, excluyendo lo oculto, lo
# de sistema, salidas _Organized previas y el destino si está dentro del origen.
# Además emite las carpetas ".git" (sin recorrerlas) para detectar proyectos.
scan_files() {
    local source_dir="$1"
    local -a prune=(-name '.*') skip=(-not -name '.*')
    local item

    for item in "${SYSTEM_DIRS[@]}"; do prune+=(-o -name "$item"); done
    for item in "${SYSTEM_DIR_PATHS[@]}"; do prune+=(-o -path "$item"); done
    if [[ -n "${DEST_ROOT:-}" && "$DEST_ROOT" == "$source_dir"/* ]]; then
        glob_escape "$DEST_ROOT"
        prune+=(-o -path "$REPLY")
    fi
    for item in "${SYSTEM_FILES[@]}"; do skip+=(-not -name "$item"); done

    find "$source_dir" -mindepth 1 \
        \( -type d -name .git -print0 -prune \) -o \
        \( -type d \( "${prune[@]}" \) -prune \) -o \
        \( -type f "${skip[@]}" -print0 \) 2>/dev/null
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
    local dir=$(nearest_existing_dir "$1")
    /bin/df -k "$dir" 2>/dev/null | /usr/bin/awk 'NR==2 {printf "%.0f", $4 * 1024}'
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

# ¿Tienen ambos archivos el mismo tamaño? (sin crear subprocesos)
same_size() {
    local -a sa sb
    zstat -A sa +size -- "$1" 2>/dev/null || return 1
    zstat -A sb +size -- "$2" 2>/dev/null || return 1
    [[ "${sa[1]}" == "${sb[1]}" ]]
}

get_file_hash() {
    local filepath="$1"
    md5 -q "$filepath" 2>/dev/null || echo ""
}

# Deja en REPLY un nombre libre en dest_dir. Si ya existe un archivo con el
# mismo nombre Y el mismo contenido que src_file, deja ese nombre (el llamador
# lo detecta con -f y lo omite). El hash solo se calcula si hay colisión de
# nombre y además los tamaños coinciden.
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

    # En simulación no se crea nada, así que se recuerdan los nombres ya
    # asignados para mostrar colisiones reales (DRY_RESERVED).
    while [[ -e "$dest_dir/$candidate" ]] || (( ${+DRY_RESERVED[$dest_dir/$candidate]} )); do
        if [[ -n "$src_file" && -f "$dest_dir/$candidate" ]] && same_size "$src_file" "$dest_dir/$candidate"; then
            [[ -z "$src_hash" ]] && src_hash=$(get_file_hash "$src_file")
            dest_hash=$(get_file_hash "$dest_dir/$candidate")
            if [[ -n "$src_hash" && "$src_hash" == "$dest_hash" ]]; then
                REPLY="$candidate"
                return 0
            fi
        fi
        candidate="${base}_${counter}${ext}"
        (( ++counter ))
    done

    REPLY="$candidate"
}
