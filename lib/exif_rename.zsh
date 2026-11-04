#!/usr/bin/env zsh
# ============================================================================
# EXIF Rename - exiftool Integration for Smart Renaming
# ============================================================================
#
# Solo se usa para fotos y videos (ver is_media_category). Documentos, audio y
# otros conservan su nombre original.

# Fecha de captura en formato YYYYMMDD_HHMMSS leída de los metadatos, o nada.
# - DateTimeOriginal: fotos (EXIF)
# - CreateDate / MediaCreateDate: videos (QuickTime) y algunas fotos
# QuickTimeUTC convierte las fechas de video (guardadas en UTC) a hora local.
# Se ignoran fechas vacías o en cero ("0000:00:00 00:00:00").
get_media_date() {
    local filepath="$1"
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[0-9]{8}_[0-9]{6}$ && "$line" != 0000* ]]; then
            echo "$line"
            return 0
        fi
    done < <(exiftool -q -q -s3 -api QuickTimeUTC -d '%Y%m%d_%H%M%S' \
        -DateTimeOriginal -CreateDate -MediaCreateDate "$filepath" 2>/dev/null)
    return 1
}

# Nombre "YYYYMMDD_HHMMSS.ext" a partir de los metadatos, o falla.
generate_exif_filename() {
    local filepath="$1"
    local ext="${${filepath:t}##*.}"
    local media_date
    media_date=$(get_media_date "$filepath") || return 1
    echo "${media_date}.${ext:l}"
}

# Fecha de modificación del archivo como respaldo: YYYYMMDD_HHMMSS
get_fs_date() {
    stat -f "%Sm" -t "%Y%m%d_%H%M%S" "$1" 2>/dev/null
}

# Nombre final (único en dest_dir) para una foto o video:
# metadatos > fecha de modificación > nombre original.
determine_filename() {
    local filepath="$1"
    local dest_dir="$2"
    local original_name="${filepath:t}"
    local new_name=""

    new_name=$(generate_exif_filename "$filepath")
    if [[ -z "$new_name" ]]; then
        local fs_date=$(get_fs_date "$filepath")
        if [[ -n "$fs_date" && "$original_name" == *.* ]]; then
            new_name="${fs_date}.${${original_name##*.}:l}"
        else
            new_name="$original_name"
        fi
    fi

    generate_unique_name "$dest_dir" "$new_name" "$filepath"
}
