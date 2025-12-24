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

assert_file_exists() {
    local test_name="$1"
    local file_path="$2"
    
    log ""
    log "=== Running test: $test_name ==="
    
    if [ -f "$file_path" ] && [ -s "$file_path" ]; then
        log "PASS: $test_name (file exists and is not empty)"
    else
        log "FAIL: $test_name (file does not exist or is empty)"
        echo "$test_name" >> "$FAILURES_FILE"
    fi
}

create_test_subtitle() {
    local srt_file="$1"
    cat > "$srt_file" << 'EOF'
1
00:00:10,000 --> 00:00:12,000
This appears at 10 seconds

2
00:00:15,000 --> 00:00:18,000
This appears at 15 seconds

3
00:00:20,000 --> 00:00:22,000
This appears at 20 seconds

EOF
}

# Helper functions for subtitle timing tests (extracted from main script)
time_to_seconds_test() {
    local time="$1"
    if [[ "$time" =~ ^[0-9]+$ ]]; then
        echo "$time"
        return
    fi
    IFS=':' read -r -a parts <<< "$time"
    local seconds=0
    case ${#parts[@]} in
        3) seconds=$((10#${parts[0]} * 3600 + 10#${parts[1]} * 60 + 10#${parts[2]})) ;;
        2) seconds=$((10#${parts[0]} * 60 + 10#${parts[1]})) ;;
        *) echo "0" ;;
    esac
    echo "$seconds"
}

test_subtitle_timing_adjustment() {
    local test_name="$1"
    local start_offset="$2"
    local expected_first_start="$3"
    local expected_first_end="$4"
    
    log ""
    log "=== Running test: $test_name ==="
    
    # Create test subtitle file
    local test_srt="$TEST_DIR/test_input.srt"
    local adjusted_srt="$TEST_DIR/test_adjusted.srt"
    create_test_subtitle "$test_srt"
    
    # Calculate offset in seconds
    local offset_seconds=$(time_to_seconds_test "$start_offset")
    
    # Use AWK to adjust timestamps (same logic as in main script)
    awk -v offset="$offset_seconds" '
    function time_to_ms(time) {
        split(time, parts, /[:,]/)
        hours = parts[1]
        minutes = parts[2]
        seconds = parts[3]
        ms = parts[4]
        return (hours * 3600 + minutes * 60 + seconds) * 1000 + ms
    }
    
    function ms_to_time(ms) {
        if (ms < 0) ms = 0
        hours = int(ms / 3600000)
        ms = ms % 3600000
        minutes = int(ms / 60000)
        ms = ms % 60000
        seconds = int(ms / 1000)
        milliseconds = ms % 1000
        return sprintf("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    /^[0-9]/ && /-->/ {
        split($0, times, / --> /)
        start_ms = time_to_ms(times[1])
        end_ms = time_to_ms(times[2])
        
        # Adjust by offset
        start_ms -= offset * 1000
        end_ms -= offset * 1000
        
        # Skip subtitles that are completely before the clip
        if (end_ms <= 0) {
            skip = 1
            next
        }
        
        # Adjust start time if it begins before the clip
        if (start_ms < 0) start_ms = 0
        
        skip = 0
        print ms_to_time(start_ms) " --> " ms_to_time(end_ms)
        next
    }
    
    !skip { print }
    ' "$test_srt" > "$adjusted_srt" 2>> "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log "FAIL: $test_name (AWK processing failed)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Check if adjusted file exists and has content
    if [ ! -f "$adjusted_srt" ] || [ ! -s "$adjusted_srt" ]; then
        log "FAIL: $test_name (adjusted subtitle file not created or empty)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Extract first timestamp line
    local first_timestamp=$(grep -m 1 " --> " "$adjusted_srt")
    
    if [ -z "$first_timestamp" ]; then
        log "FAIL: $test_name (no timestamp found in adjusted file)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Check if timestamps match expected values
    if [[ "$first_timestamp" == "$expected_first_start --> $expected_first_end" ]]; then
        log "PASS: $test_name"
        log "  Expected: $expected_first_start --> $expected_first_end"
        log "  Got:      $first_timestamp"
    else
        log "FAIL: $test_name (timestamp mismatch)"
        log "  Expected: $expected_first_start --> $expected_first_end"
        log "  Got:      $first_timestamp"
        echo "$test_name" >> "$FAILURES_FILE"
    fi
}

test_manual_subtitle_duration() {
    local test_name="$1"
    local start_time="$2"
    local end_time="$3"
    local expected_end_time="$4"
    
    log ""
    log "=== Running test: $test_name ==="
    
    local manual_srt="$TEST_DIR/test_manual.srt"
    
    # Calculate duration
    local start_sec=$(time_to_seconds_test "$start_time")
    local end_sec=$(time_to_seconds_test "$end_time")
    local duration=$((end_sec - start_sec))
    
    # Create manual subtitle using same logic as main script
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    local end_timestamp=$(printf "%02d:%02d:%02d,000" "$hours" "$minutes" "$seconds")
    
    cat > "$manual_srt" << EOF
1
00:00:00,000 --> $end_timestamp
Test Text

EOF
    
    if [ $? -ne 0 ]; then
        log "FAIL: $test_name (failed to create manual subtitle file)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Check if manual subtitle file exists
    if [ ! -f "$manual_srt" ] || [ ! -s "$manual_srt" ]; then
        log "FAIL: $test_name (manual subtitle file not created or empty)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Extract timestamp line
    local timestamp=$(grep " --> " "$manual_srt")
    
    if [ -z "$timestamp" ]; then
        log "FAIL: $test_name (no timestamp found in manual subtitle)"
        echo "$test_name" >> "$FAILURES_FILE"
        return
    fi
    
    # Check if it matches expected end time
    if [[ "$timestamp" == "00:00:00,000 --> $expected_end_time" ]]; then
        log "PASS: $test_name"
        log "  Timestamp: $timestamp"
    else
        log "FAIL: $test_name (timestamp mismatch)"
        log "  Expected: 00:00:00,000 --> $expected_end_time"
        log "  Got:      $timestamp"
        echo "$test_name" >> "$FAILURES_FILE"
    fi
}

# Initialize failures file
> "$FAILURES_FILE"

log "=== BASIC FUNCTIONALITY TESTS ==="

assert_succeeds "Help message" "$TARGET_SCRIPT -h"

assert_fails "Missing arguments" "$TARGET_SCRIPT"

assert_fails "Invalid time format" "$TARGET_SCRIPT $TEST_VIDEO_URL '99:99:99' '100:100:100' '$OUTPUT_GIF'"

assert_succeeds "Valid arguments" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 15 '$OUTPUT_GIF'"

assert_file_exists "Output GIF created" "$OUTPUT_GIF"

assert_succeeds "Custom FPS and width" "$TARGET_SCRIPT -f 10 -w 600 $TEST_VIDEO_URL 10 15 '$TEST_DIR/custom.gif'"

assert_succeeds "No subtitles" "$TARGET_SCRIPT --no-subs $TEST_VIDEO_URL 10 15 '$TEST_DIR/no_subs.gif'"

assert_succeeds "Custom subtitle text" "$TARGET_SCRIPT -t 'Test Subtitle' $TEST_VIDEO_URL 10 15 '$TEST_DIR/custom_text.gif'"

assert_succeeds "Best quality" "$TARGET_SCRIPT -q $TEST_VIDEO_URL 10 15 '$TEST_DIR/best_quality.gif'"

assert_fails "Output file without .gif extension" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 15 '$TEST_DIR/no_extension'"

log ""
log "=== SUBTITLE TIMING TESTS ==="

# Test subtitle timing adjustment with 10 second offset
test_subtitle_timing_adjustment \
    "Subtitle timing: 10 second offset" \
    "10" \
    "00:00:00,000" \
    "00:00:02,000"

# Test subtitle timing adjustment with 15 second offset
test_subtitle_timing_adjustment \
    "Subtitle timing: 15 second offset" \
    "15" \
    "00:00:00,000" \
    "00:00:03,000"

# Test subtitle timing adjustment with MM:SS format
test_subtitle_timing_adjustment \
    "Subtitle timing: MM:SS format (00:10)" \
    "00:10" \
    "00:00:00,000" \
    "00:00:02,000"

# Test subtitle timing adjustment with HH:MM:SS format
test_subtitle_timing_adjustment \
    "Subtitle timing: HH:MM:SS format (00:00:10)" \
    "00:00:10" \
    "00:00:00,000" \
    "00:00:02,000"

# Test manual subtitle duration for 5 second clip
test_manual_subtitle_duration \
    "Manual subtitle: 5 second duration" \
    "10" \
    "15" \
    "00:00:05,000"

# Test manual subtitle duration for 10 second clip
test_manual_subtitle_duration \
    "Manual subtitle: 10 second duration" \
    "5" \
    "15" \
    "00:00:10,000"

# Test manual subtitle duration with MM:SS format
test_manual_subtitle_duration \
    "Manual subtitle: MM:SS format duration" \
    "00:10" \
    "00:20" \
    "00:00:10,000"

log ""
log "=== TIME FORMAT TESTS ==="

assert_succeeds "Time format: seconds only" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 15 '$TEST_DIR/seconds.gif'"

assert_succeeds "Time format: MM:SS" "$TARGET_SCRIPT $TEST_VIDEO_URL 00:10 00:15 '$TEST_DIR/mmss.gif'"

assert_succeeds "Time format: HH:MM:SS" "$TARGET_SCRIPT $TEST_VIDEO_URL 00:00:10 00:00:15 '$TEST_DIR/hhmmss.gif'"

assert_succeeds "Time format: mixed formats" "$TARGET_SCRIPT $TEST_VIDEO_URL 10 00:15 '$TEST_DIR/mixed.gif'"

assert_fails "Time format: invalid format" "$TARGET_SCRIPT $TEST_VIDEO_URL 'invalid' '15' '$TEST_DIR/invalid.gif'"

assert_fails "Time format: end before start" "$TARGET_SCRIPT $TEST_VIDEO_URL 20 10 '$TEST_DIR/backwards.gif'"

log ""
log "=== OPTION COMBINATION TESTS ==="

assert_succeeds "Multiple options: FPS + width + subtitle size" \
    "$TARGET_SCRIPT -f 20 -w 640 -s 28 $TEST_VIDEO_URL 10 15 '$TEST_DIR/multi_opts.gif'"

assert_succeeds "Multiple options: quality + no-subs" \
    "$TARGET_SCRIPT -q --no-subs $TEST_VIDEO_URL 10 15 '$TEST_DIR/quality_nosubs.gif'"

assert_succeeds "Multiple options: custom text + size" \
    "$TARGET_SCRIPT -t 'Custom Text' -s 30 $TEST_VIDEO_URL 10 15 '$TEST_DIR/text_size.gif'"

assert_fails "Invalid option" "$TARGET_SCRIPT --invalid-option $TEST_VIDEO_URL 10 15 '$OUTPUT_GIF'"

log ""
log "=== EDGE CASE TESTS ==="

assert_succeeds "Edge case: very short clip (1 second)" \
    "$TARGET_SCRIPT $TEST_VIDEO_URL 10 11 '$TEST_DIR/short.gif'"

assert_succeeds "Edge case: start at 0" \
    "$TARGET_SCRIPT $TEST_VIDEO_URL 0 5 '$TEST_DIR/start_zero.gif'"

assert_succeeds "Edge case: very small width" \
    "$TARGET_SCRIPT -w 200 $TEST_VIDEO_URL 10 15 '$TEST_DIR/small_width.gif'"

assert_succeeds "Edge case: very low FPS" \
    "$TARGET_SCRIPT -f 5 $TEST_VIDEO_URL 10 15 '$TEST_DIR/low_fps.gif'"

# Check for failures
if [ -s "$FAILURES_FILE" ]; then
    log ""
    log "=== The following tests FAILED: ==="
    cat "$FAILURES_FILE" | tee -a "$LOG_FILE"
    log ""
    log "See $LOG_FILE for details."
    exit 1
else
    log ""
    log "=== All tests PASSED ==="
    log "Test log saved to: $LOG_FILE"
    exit 0
fi