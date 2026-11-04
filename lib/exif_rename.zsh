#!/usr/bin/env zsh
# ============================================================================
# EXIF Rename - exiftool Integration for Smart Renaming
# ============================================================================
#
# Solo se usa para fotos y videos (ver is_media_category). Documentos, audio y
# otros conservan su nombre original.
#
# Rendimiento: lanzar exiftool cuesta ~50 ms por proceso, así que antes de
# organizar se leen las fechas de TODOS los archivos con una sola ejecución
# (preload_media_dates). get_media_date consulta esa caché y solo recurre a
# exiftool individual para archivos que no estén en ella.

zmodload -F zsh/stat b:zstat 2>/dev/null

# ruta -> YYYYMMDD_HHMMSS, o "-" si el archivo no tiene fecha en metadatos
typeset -gA MEDIA_DATES=()

# Etiquetas por orden de preferencia:
# - DateTimeOriginal: fotos (EXIF)
# - CreateDate / MediaCreateDate: videos (QuickTime) y algunas fotos
# QuickTimeUTC convierte las fechas de video (guardadas en UTC) a hora local.
typeset -ga EXIF_DATE_ARGS=(
    -q -q -m -api QuickTimeUTC -d '%Y%m%d_%H%M%S'
    -DateTimeOriginal -CreateDate -MediaCreateDate
)

preload_media_dates() {
    local -a files=("$@")
    (( ${#files[@]} )) || return 0

    local argfile date src_path
    argfile=$(mktemp -t media-sorter-exif) || return 1
    print -rl -- "${files[@]}" > "$argfile"

    # Se ignoran fechas vacías o en cero ("0000:00:00 00:00:00").
    while IFS=$'\t' read -r -d $'\0' date src_path; do
        [[ -n "$src_path" ]] && MEDIA_DATES[$src_path]="$date"
    done < <(exiftool -j "${EXIF_DATE_ARGS[@]}" -@ "$argfile" 2>/dev/null | jq -j '
        .[]
        | ( first( (.DateTimeOriginal, .CreateDate, .MediaCreateDate)
                   | strings
                   | select(test("^[0-9]{8}_[0-9]{6}$") and (startswith("0000") | not)) )
            // "-" ) as $d
        | $d + "\t" + .SourceFile + "\u0000"
    ' 2>/dev/null)

    rm -f "$argfile"
}

# Deja en REPLY la fecha de captura (YYYYMMDD_HHMMSS) o falla si no hay.
get_media_date() {
    local filepath="$1" line
    REPLY=""

    if (( ${+MEDIA_DATES[$filepath]} )); then
        [[ "${MEDIA_DATES[$filepath]}" == "-" ]] && return 1
        REPLY="${MEDIA_DATES[$filepath]}"
        return 0
    fi

    # No estaba en la caché: consulta individual
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]{8}_[0-9]{6}$ && "$line" != 0000* ]]; then
            REPLY="$line"
            return 0
        fi
    done < <(exiftool -s3 "${EXIF_DATE_ARGS[@]}" "$filepath" 2>/dev/null)
    return 1
}

# Imprime "YYYYMMDD_HHMMSS.ext" a partir de los metadatos, o falla.
generate_exif_filename() {
    local filepath="$1"
    local ext="${${filepath:t}##*.}"
    get_media_date "$filepath" || return 1
    echo "${REPLY}.${ext:l}"
}

# Deja en REPLY la fecha de modificación del archivo: YYYYMMDD_HHMMSS
get_fs_date() {
    local -a st
    REPLY=""
    zstat -F '%Y%m%d_%H%M%S' -A st +mtime -- "$1" 2>/dev/null || return 1
    REPLY="${st[1]}"
}

# Deja en REPLY el nombre final (único en dest_dir) para una foto o video:
# metadatos > fecha de modificación > nombre original.
determine_filename() {
    local filepath="$1"
    local dest_dir="$2"
    local original_name="${filepath:t}"
    local ext="" new_name=""

    [[ "$original_name" == ?*.* ]] && ext=".${${original_name##*.}:l}"

    if [[ -n "$ext" ]] && get_media_date "$filepath"; then
        new_name="${REPLY}${ext}"
    elif [[ -n "$ext" ]] && get_fs_date "$filepath"; then
        new_name="${REPLY}${ext}"
    else
        new_name="$original_name"
    fi

    generate_unique_name "$dest_dir" "$new_name" "$filepath"
}
