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

# ----------------------------------------------------------------------------
section "1. Funciones de librería"
# ----------------------------------------------------------------------------
source "$PROJECT_DIR/lib/ui_helpers.zsh"
source "$PROJECT_DIR/lib/file_ops.zsh"
source "$PROJECT_DIR/lib/dup_finder.zsh"
source "$PROJECT_DIR/lib/exif_rename.zsh"
trap 'rm -rf "$TEST_ROOT"' EXIT   # (ui_helpers define su propio trap EXIT)
new_data

check_eq "jpg → Imagenes"          Imagenes   "$(categorize_file photo.jpg)"
check_eq "HEIC → Imagenes"         Imagenes   "$(categorize_file photo.HEIC)"
check_eq "MP4 → Videos"            Videos     "$(categorize_file video.MP4)"
check_eq "mp3 → Audio"             Audio      "$(categorize_file song.mp3)"
check_eq "pdf → Documentos"        Documentos "$(categorize_file doc.pdf)"
check_eq "xyz → Otros"             Otros      "$(categorize_file random.xyz)"
check_eq "sin extensión → Otros"   Otros      "$(categorize_file README)"

check_eq "nombre desde EXIF" "20231025_143005.jpg" \
    "$(generate_exif_filename "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG")"

check_eq "ruta arrastrada con '\\ ' y espacio final" "/Volumes/STORAGE X" \
    "$(normalize_path_input '/Volumes/STORAGE\ X ')"
check_eq "ruta entre comillas" "/Volumes/STORAGE X" \
    "$(normalize_path_input "'/Volumes/STORAGE X'")"

LIBT="$TEST_ROOT/libtest"; mkdir -p "$LIBT/a" "$LIBT/b"
cp "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0002.JPG" "$LIBT/a/  espacio inicial.jpg"
cp "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" "$LIBT/a/Ñandú café.JPG"
preload_media_dates "$LIBT/a/  espacio inicial.jpg" "$LIBT/a/Ñandú café.JPG"
determine_filename "$LIBT/a/  espacio inicial.jpg" "$LIBT/b"
check_eq "fecha EXIF con espacios al inicio del nombre" "20231101_091530.jpg" "$REPLY"
determine_filename "$LIBT/a/Ñandú café.JPG" "$LIBT/b"
check_eq "fecha EXIF con acentos en el nombre" "20231025_143005.jpg" "$REPLY"

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

DEST_ROOT=""
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
run --source "$SRC" --dest "$DEST" --bogus;          check "opción desconocida falla"       '(( RC != 0 ))'
run --source "$TEST_ROOT/nope" --dest "$DEST";      check "origen inexistente falla"       '(( RC != 0 ))'
run --source "$SRC" --dest "$DEST" --mode raro;      check "modo inválido falla"            '(( RC != 0 ))'
run --source "$SRC/OldBackup" --dest "$SRC";         check "origen dentro del destino falla" '(( RC != 0 ))'
run --source "$SRC" --dest "$DEST" --no-rename --no-cleanup --dry-run
check "--no-rename / --no-cleanup aceptados" '(( RC == 0 ))'

# ----------------------------------------------------------------------------
section "3. Simulación (dry run)"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --dry-run --no-interactive
check "termina sin error"          '(( RC == 0 ))'
check "no crea la carpeta destino" '[[ ! -e "$DEST" ]]'

# ----------------------------------------------------------------------------
section "4. Ejecución real (copiar), sin --no-interactive"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$DEST" --backup-id Lote1
check    "termina sin error" '(( RC == 0 ))'
check    "existe el log"     '[[ -f "$DEST/management_log.txt" ]]'
check_eq "archivos copiados (17 - 3 duplicados)" 14 "$(count_files "$DEST")"
check "foto renombrada por EXIF"         '[[ -f "$DEST/Imagenes/Lote1/iPhone_8_Backup/DCIM/100APPLE/20231025_143005.jpg" ]]'
check "documento conserva su nombre"     '[[ -f "$DEST/Documentos/Lote1/iPhone_8_Backup/Document.pdf" ]]'
check "nombre con caracteres raros"      '[[ -f "$DEST/Documentos/Lote1/Rara [1] \$dir/Informe (final) *v2*.docx" ]]'
check ".tmp del usuario se copia"        '[[ -f "$DEST/Otros/Lote1/OldBackup/session.tmp" ]]'
check "duplicado de WhatsApp omitido"    '[[ ! -d "$DEST/Imagenes/Lote1/OldBackup" ]]'
check "sin archivos AppleDouble (._*)"   '[[ -z "$(find "$DEST" -name "._*")" ]]'
check "sin contenido de .Trashes/.Spotlight" '[[ -z "$(find "$DEST" -name .Trashes -o -name .Spotlight-V100)" ]]'
check "origen intacto en modo copiar"    '[[ -f "$SRC/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" ]]'

run --source "$SRC" --dest "$DEST" --backup-id Lote1 --no-interactive
check_eq "re-ejecución: no copia nada nuevo" 14 "$(grep -c '| COPY ' "$DEST/management_log.txt")"

# ----------------------------------------------------------------------------
section "5. Mover dentro del mismo origen + limpieza"
# ----------------------------------------------------------------------------
new_data
run --source "$SRC" --dest "$SRC" --move --no-interactive
check "termina sin error"                 '(( RC == 0 ))'
check "usa la carpeta _Organized"         '[[ -f "$SRC/_Organized/Documentos/iPhone_8_Backup/Document.pdf" ]]'
check "el original se movió"              '[[ ! -f "$SRC/iPhone_8_Backup/Document.pdf" ]]'
check "carpetas vacías eliminadas"        '[[ ! -d "$SRC/EmptyFolder1" ]]'
check "carpeta con solo .DS_Store eliminada" '[[ ! -d "$SRC/EmptyFolder2" ]]'
check "duplicados omitidos siguen en el origen" '[[ -f "$SRC/OldBackup/WhatsApp/Media/WhatsApp Images/IMG_0001_WHATSAPP.JPG" ]]'
check ".Trashes no se toca"               '[[ -f "$SRC/.Trashes/501/deleted.jpg" ]]'

# ----------------------------------------------------------------------------
printf "\n\033[1mResultado: %d correctas, %d fallidas\033[0m\n" "$PASSED" "$FAILED"
(( FAILED == 0 ))
