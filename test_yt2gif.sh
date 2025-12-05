#!/usr/bin/env bash

# Test script for yt2gif.sh
# This script tests various scenarios for yt2gif.sh and exits with an error code if any test fails.

set -uo pipefail

readonly TEST_SCRIPT="test_yt2gif.sh"
readonly TARGET_SCRIPT="./yt2gif.sh"
readonly TEST_DIR="$(mktemp -d)"
readonly TEST_VIDEO_URL="https://www.youtube.com/watch?v=ih7DZk-9US8"
readonly OUTPUT_GIF="$TEST_DIR/test_output.gif"
readonly LOG_FILE="$TEST_DIR/test_log.txt"
readonly FAILURES_FILE="$TEST_DIR/failures.txt"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Cleanup on exit
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

log() {
    echo "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

run_command() {
    local cmd="$1"
    if $VERBOSE; then
        eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
    else
        eval "$cmd" &>> "$LOG_FILE"
    fi
    return $?
}

assert_succeeds() {
    local test_name="$1"
    local cmd="$2"
    log ""
    log "=== Running test: $test_name ==="
    if run_command "$cmd"; then
        log "PASS: $test_name"
    else
        log "FAIL: $test_name (unexpected failure)"
        echo "$test_name" >> "$FAILURES_FILE"
    fi
}

assert_fails() {
    local test_name="$1"
    local cmd="$2"
    log ""
    log "=== Running test: $test_name ==="
    if run_command "$cmd"; then
        log "FAIL: $test_name (expected failure, but command succeeded)"
        echo "$test_name" >> "$FAILURES_FILE"
    else
        log "PASS: $test_name"
    fi
}

# Initialize failures file
> "$FAILURES_FILE"

assert_succeeds "Help message" "$TARGET_SCRIPT -h"

assert_fails "Missing arguments" "$TARGET_SCRIPT"

assert_fails "Invalid time format" "$TARGET_SCRIPT $TEST_VIDEO_URL '99:99:99' '100:100:100' '$OUTPUT_GIF'"

assert_succeeds "Valid arguments" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 15 '$OUTPUT_GIF'"

assert_succeeds "Custom FPS and width" "$TARGET_SCRIPT -f 10 -w 600 $TEST_VIDEO_URL 10 15 '$TEST_DIR/custom.gif'"

assert_succeeds "No subtitles" "$TARGET_SCRIPT --no-subs $TEST_VIDEO_URL 10 15 '$TEST_DIR/no_subs.gif'"

assert_succeeds "Custom subtitle text" "$TARGET_SCRIPT -t 'Test Subtitle' $TEST_VIDEO_URL 10 15 '$TEST_DIR/custom_text.gif'"

assert_succeeds "Best quality" "$TARGET_SCRIPT -q $TEST_VIDEO_URL 10 15 '$TEST_DIR/best_quality.gif'"

assert_fails "Output file without .gif extension" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 15 '$TEST_DIR/no_extension'"

# Check for failures
if [ -s "$FAILURES_FILE" ]; then
    log ""
    log "=== The following tests FAILED: ==="
    cat "$FAILURES_FILE"
    log ""
    log "See $LOG_FILE for details."
    exit 1
else
    log ""
    log "=== All tests PASSED ==="
    log "Test log saved to: $LOG_FILE"
    exit 0
fi

