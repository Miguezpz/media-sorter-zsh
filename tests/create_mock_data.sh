#!/usr/bin/env zsh
# ============================================================================
# Create Mock Test Data for File Organizer
# ============================================================================

set -euo pipefail

TEST_ROOT="${1:-${TMPDIR:-/tmp}/file_organizer_test_$(date +%s)}"
SOURCE_DIR="$TEST_ROOT/source"

rm -rf "$TEST_ROOT" 2>/dev/null || true
mkdir -p "$SOURCE_DIR"

S="$SOURCE_DIR"
mkdir -p "$S/iPhone_8_Backup/DCIM/100APPLE" "$S/iPhone_8_Backup/DCIM/101APPLE" \
         "$S/Pixel_3_Backup/DCIM/Camera" "$S/Pixel_3_Backup/Download" \
         "$S/OldBackup/WhatsApp/Media/WhatsApp Images" "$S/OldBackup/WhatsApp/Media/WhatsApp Video" \
         "$S/EmptyFolder1/EmptySubfolder" "$S/EmptyFolder2" "$S/Rara [1] \$dir"

# JPEG real de 1x1 px (para que exiftool pueda escribir metadatos)
TINY_JPEG='/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA='
make_jpeg() {
    local file="$1" date="$2"
    print -r -- "$TINY_JPEG" | base64 -d > "$file"
    exiftool -q -overwrite_original -DateTimeOriginal="$date" "$file"
}

# Imágenes con fecha EXIF real
make_jpeg "$S/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" "2023:10:25 14:30:05"
make_jpeg "$S/iPhone_8_Backup/DCIM/100APPLE/IMG_0002.JPG" "2023:11:01 09:15:30"
echo "fake heic content" > "$S/iPhone_8_Backup/DCIM/100APPLE/IMG_0003.HEIC"
echo "fake png content"  > "$S/Pixel_3_Backup/DCIM/Camera/photo_2023.png"
echo "fake webp content" > "$S/Pixel_3_Backup/DCIM/Camera/screenshot.webp"

# Duplicados de IMG_0001.JPG (mismo contenido)
cp "$S/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" "$S/iPhone_8_Backup/DCIM/101APPLE/IMG_0001_COPY.JPG"
cp "$S/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" "$S/OldBackup/WhatsApp/Media/WhatsApp Images/IMG_0001_WHATSAPP.JPG"

# Videos (+ duplicado)
echo "fake mov content" > "$S/iPhone_8_Backup/DCIM/100APPLE/VID_0001.MOV"
echo "fake mp4 content" > "$S/Pixel_3_Backup/DCIM/Camera/video_2023.mp4"
echo "fake mov content" > "$S/OldBackup/WhatsApp/Media/WhatsApp Video/VID_0001_COPY.MOV"

# Audio
echo "fake m4a content" > "$S/iPhone_8_Backup/Recording.m4a"
echo "fake mp3 content" > "$S/Pixel_3_Backup/Download/song.mp3"

# Documentos (no deben renombrarse)
echo "fake pdf content" > "$S/iPhone_8_Backup/Document.pdf"
echo "fake txt content" > "$S/Pixel_3_Backup/notes.txt"
echo "nombre raro"      > "$S/Rara [1] \$dir/Informe (final) *v2*.docx"

# Otros (incluye un .tmp legítimo del usuario)
echo "fake unknown" > "$S/OldBackup/random.xyz"
echo "user tmp"     > "$S/OldBackup/session.tmp"

# Basura de sistema que NO debe procesarse
echo "x" > "$S/._IMG_0001.JPG"
echo "x" > "$S/.DS_Store"
echo "x" > "$S/EmptyFolder2/.DS_Store"
mkdir -p "$S/.Trashes/501" "$S/.Spotlight-V100/Store"
echo "borrado" > "$S/.Trashes/501/deleted.jpg"
echo "indice"  > "$S/.Spotlight-V100/Store/index.jpg"

echo "$SOURCE_DIR"
