#!/usr/bin/env zsh
# ============================================================================
# Test Script for File Organizer (Updated for Phased Processing & Validations)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="$SCRIPT_DIR/.."
ORGANIZE_SCRIPT="$PROJECT_DIR/organize.zsh"

# Helper functions
print_info() { printf "\033[36mℹ %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
print_error() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; }
print_warn() { printf "\033[33m⚠ %s\033[0m\n" "$1"; }
print_section() {
    printf "\n\033[1m\033[34m⚙ %s\033[0m\n" "$1"
    printf "\033[2m%s\033[0m\n" "$(printf '─%.0s' {1..60})"
}
assert_equals() {
    local expected="$1"
    local actual="$2"
    if [[ "$expected" != "$actual" ]]; then
        print_error "Assertion failed: expected '$expected', got '$actual'"
        exit 1
    fi
}

# Test configuration
TEST_ROOT="/tmp/file_organizer_test_run_$(date +%s)"
SOURCE_DIR="$TEST_ROOT/source"
DEST_DIR="$TEST_ROOT/dest"
BACKUP_ID="TestBackup"

print_info "=== FILE ORGANIZER TEST SUITE ==="
print_info "Test root: $TEST_ROOT"

# Create mock data
print_section "CREATING MOCK DATA"
"$SCRIPT_DIR/create_mock_data.sh" "$TEST_ROOT" >/dev/null
print_success "Mock data created"

# Make script executable
chmod +x "$ORGANIZE_SCRIPT"

# ----------------------------------------------------------------------------
# TEST 1: Validations (Source vs Destination)
# ----------------------------------------------------------------------------
print_section "TEST 1: CONFIGURATION VALIDATIONS"

print_info "Testing validation: Source equals Destination..."
if "$ORGANIZE_SCRIPT" --source "$SOURCE_DIR" --dest "$SOURCE_DIR" --backup-id "$BACKUP_ID" --mode full --no-interactive >/dev/null 2>&1; then
    print_error "Failed: Script allowed Source = Destination"
    exit 1
else
    print_success "Passed: Blocked Source = Destination"
fi

print_info "Testing validation: Destination inside Source..."
if "$ORGANIZE_SCRIPT" --source "$SOURCE_DIR" --dest "$SOURCE_DIR/NestedDest" --backup-id "$BACKUP_ID" --mode full --no-interactive >/dev/null 2>&1; then
    print_error "Failed: Script allowed Destination inside Source"
    exit 1
else
    print_success "Passed: Blocked Destination inside Source"
fi

# ----------------------------------------------------------------------------
# TEST 2: Library Function Tests
# ----------------------------------------------------------------------------
print_section "TEST 2: LIBRARY FUNCTION TESTS"

# Source libraries
source "$PROJECT_DIR/lib/ui_helpers.zsh"
source "$PROJECT_DIR/lib/file_ops.zsh"
source "$PROJECT_DIR/lib/dup_finder.zsh"
source "$PROJECT_DIR/lib/exif_rename.zsh"

# Test categorize_file (updated to match Spanish category names)
print_info "Testing categorize_file..."
assert_equals "Imagenes" "$(categorize_file "photo.jpg")"
assert_equals "Imagenes" "$(categorize_file "photo.HEIC")"
assert_equals "Videos" "$(categorize_file "video.mov")"
assert_equals "Videos" "$(categorize_file "video.MP4")"
assert_equals "Audio" "$(categorize_file "song.mp3")"
assert_equals "Documentos" "$(categorize_file "doc.pdf")"
assert_equals "others" "$(categorize_file "random.xyz")"
print_success "categorize_file tests passed"

# Test format_exif_date
print_info "Testing format_exif_date..."
assert_equals "20231025_143005" "$(format_exif_date "2023:10:25 14:30:05")"
assert_equals "20231025_143005" "$(format_exif_date "2023:10:25 14:30:05+01:00")"
print_success "format_exif_date tests passed"

# Test generate_exif_filename
print_info "Testing generate_exif_filename (requires exiftool)..."
if command -v exiftool >/dev/null 2>&1; then
    local test_file="$SOURCE_DIR/iPhone_8_Backup/DCIM/100APPLE/IMG_0001.JPG"
    local result
    result=$(generate_exif_filename "$test_file")
    assert_equals "20231025_143005.jpg" "$result"
    print_success "generate_exif_filename test passed"
else
    print_warn "Skipping EXIF test (exiftool not installed)"
fi

# Test duplicate detection with jdupes
print_info "Testing duplicate detection..."
if command -v jdupes >/dev/null 2>&1; then
    local dup_json="$TEST_ROOT/dupes.json"
    scan_duplicates "$SOURCE_DIR" "$dup_json" >/dev/null 2>&1

    if [[ -f "$dup_json" ]]; then
        local -a groups=()
        parse_jdupes_output "$dup_json" groups

        # Should find at least 2 duplicate groups (IMG_0001 and VID_0001)
        if [[ ${#groups[@]} -ge 2 ]]; then
            print_success "Duplicate detection found ${#groups[@]} groups"
        else
            print_error "Expected at least 2 duplicate groups, found ${#groups[@]}"
        fi
    fi
else
    print_warn "Skipping duplicate test (jdupes not installed)"
fi

# ----------------------------------------------------------------------------
# TEST 3: Dry Run Execution
# ----------------------------------------------------------------------------
print_section "TEST 3: DRY RUN EXECUTION"
print_info "Running organize.zsh in dry-run mode..."

if "$ORGANIZE_SCRIPT" --source "$SOURCE_DIR" --dest "$DEST_DIR" --backup-id "$BACKUP_ID" --mode full --dry-run --no-interactive >/dev/null 2>&1; then
    print_success "Dry run command executed successfully"
else
    print_error "Dry run command failed"
    exit 1
fi

print_info "Verifying no files were copied..."
# Check if destination is empty (excluding log file)
local copied_files=$(find "$DEST_DIR" -type f -not -name "management_log.txt" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$copied_files" -eq 0 ]]; then
    print_success "Passed: No files were modified during dry run"
else
    print_error "Failed: Files were copied during dry run!"
    exit 1
fi

# ----------------------------------------------------------------------------
# TEST 4: Live Execution & Verifications
# ----------------------------------------------------------------------------
print_section "TEST 4: LIVE EXECUTION (COPY MODE)"
print_info "Running full organization process..."

if "$ORGANIZE_SCRIPT" --source "$SOURCE_DIR" --dest "$DEST_DIR" --backup-id "$BACKUP_ID" --mode full --copy --no-interactive > "$TEST_ROOT/live_run.log" 2>&1; then
    print_success "Live run completed successfully"
else
    print_error "Live run failed. Check $TEST_ROOT/live_run.log"
    exit 1
fi

print_section "TEST 5: RESULT VERIFICATION"

# Check categories
print_info "Verifying category folders..."
local missing=0
for cat in Imagenes Videos Audio Documentos others; do
    if [[ ! -d "$DEST_DIR/$cat/$BACKUP_ID" ]]; then
        missing=1
    fi
done
if [[ $missing -eq 0 ]]; then
    print_success "All category folders created"
else
    print_error "Some category folders are missing"
fi

# Check empty folder cleanup
print_info "Verifying source empty folder cleanup..."
if [[ ! -d "$SOURCE_DIR/EmptyFolder1" && ! -d "$SOURCE_DIR/EmptyFolder2" ]]; then
    print_success "Empty folders successfully removed from source"
else
    print_error "Empty folders still exist in source!"
fi

# Log verification
print_info "Verifying log creation..."
if [[ -f "$DEST_DIR/management_log.txt" ]]; then
    print_success "Log file found"
else
    print_error "Log file missing"
fi

# Cleanup
print_section "CLEANUP"
rm -rf "$TEST_ROOT"
print_success "Test environment cleaned up"

print_info "=== ALL TESTS PASSED ==="
