#!/usr/bin/env zsh
# ============================================================================
# Test Suite for File Organizer
# Uso: zsh tests/test_organize.sh
# ============================================================================

set -uo pipefail
setopt EXTENDED_GLOB NULL_GLOB

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
ORGANIZE="$PROJECT_DIR/organize.zsh"

typeset -i PASSED=0 FAILED=0
pass() { printf "\033[32m  ✓ %s\033[0m\n" "$1"; (( ++PASSED )); }
fail() { printf "\033[31m  ✗ %s\033[0m\n" "$1"; (( ++FAILED )); }
section() { printf "\n\033[1m\033[34m▸ %s\033[0m\n" "$1"; }
# check "descripción" 'condición evaluada con eval'
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
check_eq() { [[ "$2" == "$3" ]] && pass "$1" || fail "$1 (esperado '$2', obtenido '$3')"; }

TEST_ROOT=$(mktemp -d -t media_sorter_test)
TEST_ROOT="${TEST_ROOT:A}"
SRC="$TEST_ROOT/source"
DEST="$TEST_ROOT/dest"

new_data() { "$SCRIPT_DIR/create_mock_data.sh" "$TEST_ROOT" >/dev/null; rm -rf "$DEST"; }
run() { zsh "$ORGANIZE" "$@" </dev/null >"$TEST_ROOT/last_run.log" 2>&1; RC=$?; }
count_files() { find "$1" -type f -not -name 'management_log.txt' -not -name 'duplicados_*' 2>/dev/null | wc -l | tr -d ' '; }
exists_glob() { local -a m=($~1); (( ${#m} > 0 )); }

# ----------------------------------------------------------------------------
section "1. Funciones de librería"
# ----------------------------------------------------------------------------
source "$PROJECT_DIR/lib/ui_helpers.zsh"
source "$PROJECT_DIR/lib/file_ops.zsh"
source "$PROJECT_DIR/lib/dup_finder.zsh"
source "$PROJECT_DIR/lib/exif_rename.zsh"
source "$PROJECT_DIR/lib/protect.zsh"
trap 'rm -rf "$TEST_ROOT"' EXIT   # (ui_helpers define su propio trap EXIT)
new_data

check_eq "jpg → Imagenes"          Imagenes   "$(categorize_file photo.jpg)"
check_eq "HEIC → Imagenes"         Imagenes   "$(categorize_file photo.HEIC)"
check_eq "MP4 → Videos"            Videos     "$(categorize_file video.MP4)"
check_eq "mp3 → Audio"             Audio      "$(categorize_file song.mp3)"
check_eq "pdf → Documentos"        Documentos "$(categorize_file doc.pdf)"
check_eq "xyz → Otros"             Otros      "$(categorize_file random.xyz)"
check_eq "sin extensión → Otros"   Otros      "$(categorize_file README)"
f_cat() { local cat_name=""; categorize_file "x/y.mov" cat_name; echo "$cat_name"; }
check_eq "categoría en variable local del llamador" Videos "$(f_cat)"

check_eq "nombre desde EXIF" "20231025_143005.jpg" \
    "$(generate_exif_filename "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG")"

typeset -A name_cases=(
    "IMG_20230115_143000.jpg"                       20230115_143000
    "IMG_20230115_143000123_HDR.jpg"                20230115_143000
    "20231208_233423.mp4"                           20231208_233423
    "IMG20230115143000.jpg"                         20230115_143000
    "IMG-20210513-WA0059.jpg"                       20210513_000000
    "Screenshot_2023-01-15-14-30-00.png"            20230115_143000
    "Captura de pantalla 2023-01-15 a las 14.30.00.png" 20230115_143000
    "WhatsApp Image 2023-01-15 at 14.30.00.jpeg"    20230115_143000
)
for n in "${(@k)name_cases}"; do
    REPLY=""; date_from_filename "$n"
    check_eq "fecha del nombre: $n" "${name_cases[$n]}" "$REPLY"
done
for n in DSC_0001.JPG IMG_1234.HEIC 1000171187.jpg VID_34261207_111012_042.mp4 photo_2023.png; do
    check "sin fecha en el nombre: $n" '! date_from_filename "$n"'
done
REPLY=""; date_from_filename FB_IMG_15401296052513054.jpg
check "FB_IMG_ con 17 dígitos → 2018-10" '[[ "$REPLY" == 201810* ]]'

TK="$SRC/google photos backup/Takeout/Google Photos/Photos from 2015"
check "JSON de Takeout detectado como metadatos" 'is_takeout_sidecar "$TK/foto_playa.jpg.supplemental-metadata.json"'
check "una foto no es JSON de Takeout"           '! is_takeout_sidecar "$TK/foto_playa.jpg"'
REPLY=""; takeout_date_for "$TK/foto_playa.jpg"
check "fecha leída del JSON de Takeout (2015-01-13)" '[[ "$REPLY" == 20150113_* ]]'

normalize_check() { check_eq "$1" "/Volumes/STORAGE X" "$(normalize_path_input "$2")"; }
normalize_check "ruta arrastrada con '\\ ' y espacio final" '/Volumes/STORAGE\ X '
normalize_check "ruta entre comillas" "'/Volumes/STORAGE X'"

# Archivos especiales
LIBT="$TEST_ROOT/libtest"; mkdir -p "$LIBT/a" "$LIBT/b"
cp "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0002.JPG" "$LIBT/a/  espacio inicial.jpg"
cp "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" "$LIBT/a/Ñandú café.JPG"
preload_media_dates "$LIBT/a/  espacio inicial.jpg" "$LIBT/a/Ñandú café.JPG"
get_media_date "$LIBT/a/  espacio inicial.jpg"
check_eq "EXIF con espacios al inicio del nombre" "20231101_091530" "$REPLY"
get_media_date "$LIBT/a/Ñandú café.JPG"
check_eq "EXIF con acentos en el nombre" "20231025_143005" "$REPLY"

DRY_RUN=false; DEST_ROOT="$LIBT/b"
echo uno > "$LIBT/a/m1.txt"; echo dos > "$LIBT/a/m2.txt"
MOVE_SAME_FS=true;  move_file "$LIBT/a/m1.txt" "$LIBT/b/m1.txt" ""
check "mover en el mismo disco (rename)"        '[[ -f "$LIBT/b/m1.txt" && ! -e "$LIBT/a/m1.txt" ]]'
MOVE_SAME_FS=false; move_file "$LIBT/a/m2.txt" "$LIBT/b/m2.txt" ""
check "mover entre discos (copia verificada)"   '[[ "$(<$LIBT/b/m2.txt)" == dos && ! -e "$LIBT/a/m2.txt" ]]'
echo otro > "$LIBT/a/m3.txt"; MOVE_SAME_FS=true
check "mover no sobrescribe un archivo existente" '! move_file "$LIBT/a/m3.txt" "$LIBT/b/m1.txt" "" && [[ "$(<$LIBT/b/m1.txt)" == uno ]]'
generate_unique_name "$LIBT/b" "m1.txt" "$LIBT/a/m3.txt"
check_eq "colisión con contenido distinto → sufijo _1" "m1_1.txt" "$REPLY"
cp "$LIBT/b/m1.txt" "$LIBT/a/m1_igual.txt"
generate_unique_name "$LIBT/b" "m1.txt" "$LIBT/a/m1_igual.txt"
check_eq "colisión con contenido idéntico → mismo nombre" "m1.txt" "$REPLY"

# Escaneo y carpetas protegidas
DEST_ROOT=""; SOURCE_DIR="$SRC"
found=(); while IFS= read -r -d '' f; do found+=("$f"); done < <(scan_files "$SRC")
check "escaneo ignora .thumbnails"          '[[ -z "${(M)found:#*/.thumbnails/*}" ]]'
check "escaneo ignora Android/data"         '[[ -z "${(M)found:#*/Android/data/*}" ]]'
check "escaneo incluye Android/media (WhatsApp)" '[[ -n "${(M)found:#*/Android/media/*WA0059.jpg}" ]]'
check "escaneo ignora ._*, .DS_Store, .Trashes" '[[ -z "${(M)found:#*/.(_*|DS_Store|Trashes/*)}" ]]'
compute_protected_dirs "$SRC" "${found[@]}"
check "juego con .dll protegido"            '(( ${+PROT_SET[$SRC/Juegos]} ))'
check "proyecto con package.json protegido" '(( ${+PROT_SET[$SRC/Code]} ))'
check "repositorio git protegido"           '(( ${+PROT_SET[$SRC/Code2]} ))'
check ".exe suelto con documentos NO protege" '! is_protected_path "$SRC/USB MAMA/carta.docx"'
check "el origen nunca se protege"          '(( ! ${+PROT_SET[$SRC]} ))'

DEST_ROOT=""; PROTECTED_DIRS=()
scan_duplicates "$SRC" "$TEST_ROOT/dupes.json" 2>/dev/null
parse_jdupes_output "$TEST_ROOT/dupes.json"
check_eq "2 grupos de duplicados (jpg y mov)" 2 "${#DUP_GROUPS[@]}"
resolve_duplicates_auto
check_eq "3 copias a omitir (2 jpg + 1 mov)" 3 "${#REMOVE_FILES[@]}"
check "se conserva el original, no la copia" '(( ${KEEP_FILES[(I)*/100APPLE/IMG_0001.JPG]} ))'
check "los grupos no incluyen basura del sistema" '[[ "${DUP_GROUPS[*]}" != *(/._|.Trashes|.Spotlight)* ]]'

# ----------------------------------------------------------------------------
section "2. Validaciones de argumentos"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --bogus;          check "opción desconocida falla"        '(( RC != 0 ))'
run --source "$TEST_ROOT/nope" --dest "$DEST";      check "origen inexistente falla"        '(( RC != 0 ))'
run --source "$SRC" --dest "$DEST" --mode raro;      check "modo inválido falla"             '(( RC != 0 ))'
run --source "$SRC" --dest "$DEST" --layout raro;    check "organización inválida falla"     '(( RC != 0 ))'
run --source "$SRC/OldBackup" --dest "$SRC";         check "origen dentro del destino falla" '(( RC != 0 ))'
run --source "$SRC" --dest "$DEST" --no-rename --no-cleanup --no-protect --layout original --dry-run
check "opciones válidas aceptadas" '(( RC == 0 ))'

# ----------------------------------------------------------------------------
section "3. Simulación (dry run)"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --dry-run --no-interactive
check "termina sin error"          '(( RC == 0 ))'
check "no crea la carpeta destino" '[[ ! -e "$DEST" ]]'
dry_log=$(grep -o '/[^ ]*media-sorter-dryrun[^ ]*' "$TEST_ROOT/last_run.log" | tail -1)
check "la simulación reserva nombres (sin destinos repetidos)" \
    '[[ -z "$(awk -F" [|] " "\$2 ~ /COPY/ {print \$4}" "$dry_log" | sort | uniq -d)" ]]'

# ----------------------------------------------------------------------------
section "4. Ejecución real (copiar, organización por fecha)"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --backup-id Lote1
check "termina sin error" '(( RC == 0 ))'
check "existe el log"     '[[ -f "$DEST/management_log.txt" ]]'
I="$DEST/Imagenes/Lote1"; V="$DEST/Videos/Lote1"
check "foto con EXIF: renombrada y en Año/Mes"     '[[ -f "$I/2023/2023-10/20231025_143005.jpg" ]]'
check "WhatsApp: fecha del nombre, nombre intacto" '[[ -f "$I/2021/2021-05/IMG-20210513-WA0059.jpg" ]]'
check "video Samsung: conserva su nombre"          '[[ -f "$V/2023/2023-12/20231208_233423.mp4" ]]'
check "FB_IMG_: fecha del nombre"                  'exists_glob "$I/2018/2018-10/FB_IMG_15401296052513054.jpg"'
check "Takeout: fecha del JSON y renombrada"       'exists_glob "$I/2015/2015-01/20150113_*.jpg"'
check "JSON de Takeout no se mueve a Otros"        '[[ -z "$(find "$DEST" -name "*.json")" ]]'
check "sin fecha fiable → Sin_fecha (nombre intacto)" '[[ -f "$I/Sin_fecha/iPhone_8_Backup/DCIM/100APPLE/IMG_0003.HEIC" ]]'
check "nunca se usa la fecha de modificación"      '[[ -z "$(find "$I" -path "*/$(date +%Y)/*")" ]]'
check "documento conserva nombre y ruta"           '[[ -f "$DEST/Documentos/Lote1/iPhone_8_Backup/Document.pdf" ]]'
check "nombre con caracteres raros"                '[[ -f "$DEST/Documentos/Lote1/Rara [1] \$dir/Informe (final) *v2*.docx" ]]'
check ".exe suelto se organiza (Otros)"            '[[ -f "$DEST/Otros/Lote1/USB MAMA/instalador.exe" ]]'
check "juego protegido: nada en destino"           '[[ -z "$(find "$DEST" -name "engine.dll" -o -name "preview.png")" ]]'
check "proyectos protegidos: nada en destino"      '[[ -z "$(find "$DEST" -name "index.js" -o -name "logo.png" -o -name "main.py")" ]]'
check "miniaturas y datos de apps ignorados"       '[[ -z "$(find "$DEST" -name "1000171187.jpg" -o -name "img.jpg")" ]]'
check "duplicado de WhatsApp omitido"              '[[ -z "$(find "$DEST" -name "*WHATSAPP*")" ]]'
check "sin AppleDouble ni .Trashes"                '[[ -z "$(find "$DEST" -name "._*" -o -name .Trashes)" ]]'
check "origen intacto en modo copiar"              '[[ -f "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" ]]'
copied=$(grep -c '| COPY ' "$DEST/management_log.txt")
check_eq "archivos copiados = archivos en destino" "$copied" "$(count_files "$DEST")"

run --source "$SRC" --dest "$DEST" --backup-id Lote1 --no-interactive
check_eq "re-ejecución: no copia nada nuevo" "$copied" "$(grep -c '| COPY ' "$DEST/management_log.txt")"

# ----------------------------------------------------------------------------
section "5. Organización con rutas originales (--layout original)"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --layout original --no-interactive
check "termina sin error"               '(( RC == 0 ))'
check "foto en su ruta original"        '[[ -f "$DEST/Imagenes/iPhone_8_Backup/DCIM/100APPLE/20231025_143005.jpg" ]]'
check "WhatsApp en su ruta original"    '[[ -f "$DEST/Imagenes/Mama_OPPO/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/IMG-20210513-WA0059.jpg" ]]'

# ----------------------------------------------------------------------------
section "6. Mover dentro del mismo origen + limpieza"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$SRC" --move --no-interactive
check "termina sin error"                 '(( RC == 0 ))'
check "usa la carpeta _Organized"         '[[ -f "$SRC/_Organized/Documentos/iPhone_8_Backup/Document.pdf" ]]'
check "el original se movió"              '[[ ! -f "$SRC/iPhone_8_Backup/Document.pdf" ]]'
check "carpetas vacías eliminadas"        '[[ ! -d "$SRC/EmptyFolder1" ]]'
check "carpeta con solo .DS_Store eliminada" '[[ ! -d "$SRC/EmptyFolder2" ]]'
check "duplicados omitidos siguen en el origen" '[[ -f "$SRC/OldBackup/WhatsApp/Media/WhatsApp Images/IMG_0001_WHATSAPP.JPG" ]]'
check "juego intacto en el origen"        '[[ -f "$SRC/Juegos/MiJuego/engine.dll" && -f "$SRC/Juegos/MiJuego/preview.png" ]]'
check "proyecto intacto en el origen"     '[[ -f "$SRC/Code/app/logo.png" && -f "$SRC/Code2/repo/.git/HEAD" ]]'
check "JSON de Takeout sigue en el origen" '[[ -f "$TK/foto_playa.jpg.supplemental-metadata.json" ]]'
check ".Trashes no se toca"               '[[ -f "$SRC/.Trashes/501/deleted.jpg" ]]'
check "Android/data no se toca"           '[[ -f "$SRC/Mama_OPPO/Android/data/com.app/cache/img.jpg" ]]'

# ----------------------------------------------------------------------------
printf "\n\033[1mResultado: %d correctas, %d fallidas\033[0m\n" "$PASSED" "$FAILED"
(( FAILED == 0 ))
