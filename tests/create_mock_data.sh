#!/usr/bin/env zsh
# ============================================================================
# Create Mock Test Data for File Organizer
# ============================================================================

set -euo pipefail

# Allow passing a custom test root or use default
TEST_ROOT="${1:-/tmp/file_organizer_test_$(date +%s)}"
SOURCE_DIR="$TEST_ROOT/source"
DEST_DIR="$TEST_ROOT/dest"

print_info() { printf "\033[36mℹ %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
print_warn() { printf "\033[33m⚠ %s\033[0m\n" "$1"; }

print_info "Creating test data at: $TEST_ROOT"

# Clean previous environment if exists
rm -rf "$TEST_ROOT" 2>/dev/null || true
mkdir -p "$SOURCE_DIR"
mkdir -p "$DEST_DIR"

# Create source structure simulating multiple phone backups
mkdir -p "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE"
mkdir -p "$SOURCE_DIR/iPhone_8_Backup/DCIM/101APPLE"
mkdir -p "$SOURCE_DIR/Pixel_3_Backup/DCIM/Camera"
mkdir -p "$SOURCE_DIR/Pixel_3_Backup/Download"
mkdir -p "$SOURCE_DIR/OldBackup/WhatsApp/Media/WhatsApp Images"
mkdir -p "$SOURCE_DIR/EmptyFolder1/EmptySubfolder"
mkdir -p "$SOURCE_DIR/EmptyFolder2"

# Create test files with various extensions
# Images
echo "fake jpg content 1" > "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG"
echo "fake jpg content 2" > "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0002.JPG"
echo "fake heic content" > "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0003.HEIC"
echo "fake png content" > "$SOURCE_DIR/Pixel_3_Backup/DCIM/Camera/photo_2023.png"
echo "fake webp content" > "$SOURCE_DIR/Pixel_3_Backup/DCIM/Camera/screenshot.webp"

# Duplicate images (same content as IMG_0001.JPG)
echo "fake jpg content 1" > "$SOURCE_DIR/iPhone_8_Backup/DCIM/101APPLE/IMG_0001_COPY.JPG"
echo "fake jpg content 1" > "$SOURCE_DIR/OldBackup/WhatsApp/Media/WhatsApp Images/IMG_0001_WHATSAPP.JPG"

# Videos
echo "fake mov content" > "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/VID_0001.MOV"
echo "fake mp4 content" > "$SOURCE_DIR/Pixel_3_Backup/DCIM/Camera/video_2023.mp4"

# Duplicate video
mkdir -p "$SOURCE_DIR/OldBackup/WhatsApp/Media/WhatsApp Video"
echo "fake mov content" > "$SOURCE_DIR/OldBackup/WhatsApp/Media/WhatsApp Video/VID_0001_COPY.MOV"

# Audio
echo "fake m4a content" > "$SOURCE_DIR/iPhone_8_Backup/Recording.m4a"
echo "fake mp3 content" > "$SOURCE_DIR/Pixel_3_Backup/Download/song.mp3"

# Documents
echo "fake pdf content" > "$SOURCE_DIR/iPhone_8_Backup/Document.pdf"
echo "fake txt content" > "$SOURCE_DIR/Pixel_3_Backup/notes.txt"

# Others
echo "fake unknown" > "$SOURCE_DIR/OldBackup/random.xyz"

# Create a file with EXIF data using exiftool if available
if command -v exiftool >/dev/null 2>&1; then
    print_info "Adding EXIF data to test images..."

    # Add EXIF to a few files
    exiftool -overwrite_original \
        -DateTimeOriginal="2023:10:25 14:30:05" \
        -CreateDate="2023:10:25 14:30:05" \
        "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG" >/dev/null 2>&1

    exiftool -overwrite_original \
        -DateTimeOriginal="2023:11:01 09:15:30" \
        -CreateDate="2023:11:01 09:15:30" \
        "$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0002.JPG" >/dev/null 2>&1

    exiftool -overwrite_original \
        -DateTimeOriginal="2022:05:15 18:45:00" \
        -CreateDate="2022:05:15 18:45:00" \
        "$SOURCE_DIR/Pixel_3_Backup/DCIM/Camera/photo_2023.png" >/dev/null 2>&1

    print_success "EXIF data added"
else
    print_warn "exiftool not found - EXIF tests will use filesystem dates"
fi

print_success "Test data created at: $SOURCE_DIR"
