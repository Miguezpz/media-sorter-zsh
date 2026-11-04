#!/usr/bin/env zsh
# ============================================================================
# Fechas de fotos y videos: nombre del archivo, EXIF y Google Takeout
# ============================================================================
#
# Orden de preferencia (media_date_for):
#   1. Fecha en el NOMBRE del archivo (IMG_20230115_143000, IMG-20230115-WA0001,
#      20230115_143000, Screenshot_2023-01-15-14-30-00, FB_IMG_<milisegundos>…).
#      Es la más fiable: la pone el teléfono al crear el archivo. En ese caso el
#      archivo conserva su nombre.
#   2. Metadatos EXIF/QuickTime (exiftool).
#   3. JSON de Google Takeout (photoTakenTime).
# La fecha de modificación del archivo NO se usa: al copiar un respaldo suele
# quedar la fecha de la copia, no la de la foto. Sin fecha fiable, el archivo
# conserva su nombre y va a "Sin_fecha".
#
# Rendimiento: exiftool cuesta ~50 ms por proceso, así que las fechas EXIF se
# leen todas con una sola ejecución (preload_media_dates) y se guardan en caché.

zmodload -F zsh/stat b:zstat 2>/dev/null
zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS 2>/dev/null

# ruta -> YYYYMMDD_HHMMSS, o "-" si el archivo no tiene fecha en metadatos
typeset -gA MEDIA_DATES=()

# Resultado de media_date_for
typeset -g MEDIA_DATE=""        # YYYYMMDD_HHMMSS
typeset -g MEDIA_DATE_SRC=""    # nombre | exif | takeout | (vacío = sin fecha)

typeset -gi CURRENT_YEAR
strftime -s CURRENT_YEAR '%Y' $EPOCHSECONDS

# Año(19xx|20xx) Mes Día con separadores opcionales, y opcionalmente la hora.
# Grupos: 2=año 4=mes 5=día 8=hora 9=min 10=seg
typeset -g DATE_NAME_RE='(^|[^0-9])((19|20)[0-9]{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12][0-9]|3[01])([-_ T.]*(a las |at )?([01][0-9]|2[0-3])[-_.:]?([0-5][0-9])[-_.:]?([0-5][0-9])|[^0-9]|$)'
# Marca de tiempo en milisegundos (13 dígitos), p. ej. FB_IMG_1577836800000
# (FB_IMG_ con 17 dígitos se trata aparte: 10 dígitos de segundos + 7 extra)
typeset -g EPOCH_MS_RE='(^|[^0-9])(1[2-9][0-9]{11})([^0-9]|$)'

# Etiquetas por orden de preferencia:
# - DateTimeOriginal: fotos (EXIF)
# - CreateDate / MediaCreateDate: videos (QuickTime) y algunas fotos
# QuickTimeUTC convierte las fechas de video (guardadas en UTC) a hora local.
typeset -ga EXIF_DATE_ARGS=(
    -q -q -m -api QuickTimeUTC -d '%Y%m%d_%H%M%S'
    -DateTimeOriginal -CreateDate -MediaCreateDate
)

# Deja en REPLY la fecha (YYYYMMDD_HHMMSS) contenida en el nombre, o falla.
# Si el nombre solo trae el día (WhatsApp), la hora queda en 000000.
date_from_filename() {
    local name="${1:t}"
    name="${name%.*}"
    REPLY=""
    local -a match mbegin mend

    if [[ "$name" =~ $DATE_NAME_RE ]]; then
        local -i y=${match[2]}
        if (( y >= 1995 && y <= CURRENT_YEAR )); then
            REPLY="${match[2]}${match[4]}${match[5]}_${match[8]:-00}${match[9]:-00}${match[10]:-00}"
            return 0
        fi
    fi
    local -i secs=0
    if [[ "$name" =~ '^FB_IMG_(1[2-9][0-9]{8})[0-9]*' ]]; then
        # Facebook: los primeros 10 dígitos son segundos Unix
        secs=${match[1]}
        if (( secs <= EPOCHSECONDS )); then
            strftime -s REPLY '%Y%m%d_%H%M%S' $secs
            return 0
        fi
    fi
    if [[ "$name" =~ $EPOCH_MS_RE ]]; then
        secs=$(( ${match[2]} / 1000 ))
        if (( secs <= EPOCHSECONDS )); then
            strftime -s REPLY '%Y%m%d_%H%M%S' $secs
            return 0
        fi
    fi
    return 1
}

# Lee con UNA sola ejecución de exiftool las fechas de los archivos dados.
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

    # Los que exiftool no devolvió (ilegibles, nombres raros) se marcan sin fecha
    local f
    for f in "${files[@]}"; do
        (( ${+MEDIA_DATES[$f]} )) || MEDIA_DATES[$f]="-"
    done
    rm -f "$argfile"
}

# Deja en REPLY la fecha EXIF/QuickTime o falla.
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

# ¿Es un JSON de metadatos de Google Takeout? (acompaña a una foto; no se organiza)
is_takeout_sidecar() {
    local lp="${1:l}"
    [[ "$lp" == *.json ]] || return 1
    [[ "$1" == */Takeout/* ]] && return 0
    [[ "${lp:t}" == *.(jpg|jpeg|png|heic|heif|gif|webp|mp4|mov|m4v|3gp|avi|mkv|dng|tif|tiff)(|.*).json ]]
}

# Deja en REPLY la fecha (photoTakenTime) del JSON de Takeout de una foto.
# Nombres posibles del JSON:
#   foto.jpg.supplemental-metadata.json   (y versiones truncadas .supplemental-met.json…)
#   foto.jpg.json  /  foto.json
#   foto-editado.jpg      -> usa el JSON de foto.jpg
#   foto(1).jpg           -> foto.jpg.supplemental-metadata(1).json / foto.jpg(1).json
takeout_date_for() {
    local f="$1" dir="${1:h}" name="${1:t}"
    local base="${name%.*}" ext="${name##*.}" j ts
    local -a match mbegin mend
    local -a cands=("$f".supplemental-metadata.json "$f".s*.json(N) "$f".json "$dir/$base".json)

    if [[ "$base" =~ '^(.*)-(edited|editado|EFFECTS|ANIMATION|COLLAGE)$' ]]; then
        cands+=("$dir/${match[1]}.$ext".s*.json(N) "$dir/${match[1]}.$ext".json)
    fi
    if [[ "$base" =~ '^(.*)(\([0-9]+\))$' ]]; then
        cands+=("$dir/${match[1]}.$ext".s*"${match[2]}".json(N) "$dir/${match[1]}.$ext${match[2]}".json)
    fi

    REPLY=""
    for j in "${cands[@]}"; do
        [[ -f "$j" ]] || continue
        ts=$(jq -r '.photoTakenTime.timestamp // empty' "$j" 2>/dev/null)
        if [[ "$ts" == <1-> ]]; then
            strftime -s REPLY '%Y%m%d_%H%M%S' "$ts"
            return 0
        fi
    done
    return 1
}

# Fecha de una foto/video según el orden de preferencia descrito arriba.
# Deja el resultado en MEDIA_DATE y MEDIA_DATE_SRC; falla si no hay fecha fiable.
media_date_for() {
    MEDIA_DATE=""
    MEDIA_DATE_SRC=""
    if date_from_filename "$1"; then
        MEDIA_DATE="$REPLY"; MEDIA_DATE_SRC="nombre"
    elif get_media_date "$1"; then
        MEDIA_DATE="$REPLY"; MEDIA_DATE_SRC="exif"
    elif takeout_date_for "$1"; then
        MEDIA_DATE="$REPLY"; MEDIA_DATE_SRC="takeout"
    else
        return 1
    fi
    return 0
}
