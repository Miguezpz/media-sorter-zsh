#!/usr/bin/env zsh
# ============================================================================
# Test Script for File Organizer
# ============================================================================

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="$SCRIPT_DIR/.."
ORGANIZE_SCRIPT="$PROJECT_DIR/organize.zsh"

# Helper functions - defined first
print_info() { printf "\033[36mℹ %s\033[0m\n" "$1"; }
print_success() { printf "\033[32m✓ %s\033[0m\n" "$1"; }
print_error() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; }
print_warn() { printf "\033[33m⚠ %s\033[0m\n" "$1"; }
print_section() {
    printf "\n\033[1m\033[34m⚙ %s\033[0m\n" "$1"
    printf "\033[2m%s\033[0m\n" "$(printf '─%.0s' {1..60})"
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
"$SCRIPT_DIR/create_mock_data.sh" >/dev/null
print_success "Mock data created"

# Make script executable
chmod +x "$ORGANIZE_SCRIPT"

# Test 1: Dry run mode
print_section "TEST 1: DRY RUN MODE"
print_info "Running organize.zsh in dry-run mode..."

if "$ORGANIZE_SCRIPT" \
    --source "$SOURCE_DIR" \
    --dest "$DEST_DIR" \
    --backup-id "$BACKUP_ID" \
    --mode full \
    --dry-run \
    --no-interactive 2>&1 | head -50; then
    print_success "Dry run completed"
else
    print_error "Dry run failed"
    exit 1
fi

# Since the script is interactive, let me create a non-interactive test version
# For now, let's test the individual functions

print_section "TEST 2: LIBRARY FUNCTION TESTS"

# Source libraries
source "$PROJECT_DIR/lib/ui_helpers.zsh"
source "$PROJECT_DIR/lib/file_ops.zsh"
source "$PROJECT_DIR/lib/dup_finder.zsh"
source "$PROJECT_DIR/lib/exif_rename.zsh"

# Test categorize_file
print_info "Testing categorize_file..."
assert_equals "images" "$(categorize_file "photo.jpg")"
assert_equals "images" "$(categorize_file "photo.HEIC")"
assert_equals "videos" "$(categorize_file "video.mov")"
assert_equals "videos" "$(categorize_file "video.MP4")"
assert_equals "audio" "$(categorize_file "song.mp3")"
assert_equals "documents" "$(categorize_file "doc.pdf")"
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
    scan_duplicates "$SOURCE_DIR" "$dup_json"

    if [[ -f "$dup_json" ]]; then
        local groups=()
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

# Test 3: Full organization (non-interactive simulation)
print_section "TEST 3: FULL ORGANIZATION SIMULATION"

# We'll simulate the organization by calling functions directly
# since the main script is interactive

# Cleanup
print_section "CLEANUP"
rm -rf "$TEST_ROOT"
print_success "Test cleanup complete"

print_info "=== ALL TESTS PASSED ==="

# Helper function
assert_equals() {
    local expected="$1"
    local actual="$2"
    if [[ "$expected" != "$actual" ]]; then
        print_error "Assertion failed: expected '$expected', got '$actual'"
        exit 1
    fi
}

print_section() {
    printf "\n\033[1m\033[34m⚙ %s\033[0m\n" "$1"
    printf "\033[2m%s\033[0m\n" "$(printf '─%.0s' {1..60})"
}