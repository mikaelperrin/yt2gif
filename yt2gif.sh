#!/usr/bin/env bash

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly TEMP_DIR="$(mktemp -d)"
readonly DEFAULT_FPS=15
readonly DEFAULT_WIDTH=800
readonly DEFAULT_SUBTITLE_SIZE=24

# Cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] <youtube_url> <start_time> <end_time> <output_gif>

Create an animated GIF from a YouTube video segment with optional subtitles.

Arguments:
    youtube_url     YouTube video URL
    start_time      Start time (HH:MM:SS or MM:SS or seconds)
    end_time        End time (HH:MM:SS or MM:SS or seconds)
    output_gif      Output GIF filename

Options:
    -f, --fps N         Frame rate (default: $DEFAULT_FPS)
    -w, --width N       Width in pixels (default: $DEFAULT_WIDTH, height auto)
    -s, --subtitle-size Size of subtitles (default: $DEFAULT_SUBTITLE_SIZE)
    -t, --text TEXT     Add custom subtitle text (overrides downloaded subs)
    -n, --no-subs       Skip subtitle download/embedding
    -q, --quality       Use best quality (slower, larger file)
    -h, --help          Show this help message

Examples:
    $SCRIPT_NAME https://youtu.be/example 10 15 output.gif
    $SCRIPT_NAME -f 20 -w 640 https://youtu.be/example 00:00:10 00:00:15 output.gif
    $SCRIPT_NAME --no-subs https://youtu.be/example 1:30 1:45 output.gif
    $SCRIPT_NAME -t "Hello World!" https://youtu.be/example 5 10 output.gif

EOF
    exit "${1:-0}"
}

log() {
    echo "[$(date +'%H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

check_dependencies() {
    local missing=()
    for cmd in yt-dlp ffmpeg; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

validate_youtube_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?://(www\.)?(youtube\.com|youtu\.be) ]]; then
        error "Invalid YouTube URL: $url"
    fi
}

normalize_time() {
    local time="$1"

    # If it's just a number, treat as seconds
    if [[ "$time" =~ ^[0-9]+$ ]]; then
        echo "$time"
        return
    fi

    # Support HH:MM:SS, MM:SS, or seconds
    if [[ "$time" =~ ^([0-9]+:)?[0-9]+:[0-9]+$ ]]; then
        echo "$time"
        return
    fi

    error "Invalid time format: $time (use HH:MM:SS, MM:SS, or seconds)"
}

time_to_seconds() {
    local time="$1"

    # If already in seconds
    if [[ "$time" =~ ^[0-9]+$ ]]; then
        echo "$time"
        return
    fi

    # Parse time format
    IFS=':' read -r -a parts <<< "$time"
    local seconds=0

    case ${#parts[@]} in
        3) seconds=$((10#${parts[0]} * 3600 + 10#${parts[1]} * 60 + 10#${parts[2]})) ;;
        2) seconds=$((10#${parts[0]} * 60 + 10#${parts[1]})) ;;
        *) error "Invalid time format: $time" ;;
    esac

    echo "$seconds"
}

seconds_to_srt_time() {
    local total_seconds="$1"
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))
    local milliseconds=$(echo "$total_seconds" | awk '{printf "%03d", ($1 - int($1)) * 1000}')
    
    printf "%02d:%02d:%02d,%s" "$hours" "$minutes" "$seconds" "$milliseconds"
}

validate_time_range() {
    local start="$1"
    local end="$2"

    local start_sec=$(time_to_seconds "$start")
    local end_sec=$(time_to_seconds "$end")

    if [ "$start_sec" -ge "$end_sec" ]; then
        error "Start time ($start) must be before end time ($end)"
    fi

    local duration=$((end_sec - start_sec))
    if [ "$duration" -gt 60 ]; then
        log "WARNING: GIF duration is ${duration}s. Large GIFs may have poor quality."
    fi
}

download_video() {
    local url="$1"
    local output="$2"
    local quality_flag="${3:-}"

    log "Downloading video..."
    log "WARNING: Downloading copyrighted content may violate YouTube's Terms of Service and copyright law."
    log "Use this tool responsibly and only for lawful purposes."

    local format_opt
    if [ "$quality_flag" = "best" ]; then
        format_opt="bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]"
    else
        format_opt="bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]"
    fi

    yt-dlp -f "$format_opt" --no-warnings --quiet --progress \
        "$url" -o "$output" || error "Failed to download video"
}

create_manual_subtitle() {
    local text="$1"
    local start="$2"
    local end="$3"
    local output="$4"

    local start_sec=$(time_to_seconds "$start")
    local end_sec=$(time_to_seconds "$end")
    local duration=$((end_sec - start_sec))
    
    # Create subtitle that spans the entire clip duration
    local end_time=$(seconds_to_srt_time "$duration")
    
    cat > "$output" << EOF
1
00:00:00,000 --> $end_time
$text

EOF

    log "Created manual subtitle: \"$text\" (duration: ${duration}s)"
}

adjust_subtitle_timing() {
    local input_srt="$1"
    local output_srt="$2"
    local start_offset="$3"
    
    local offset_seconds=$(time_to_seconds "$start_offset")
    
    log "Adjusting subtitle timing (offset: -${offset_seconds}s)..."
    
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
    ' "$input_srt" > "$output_srt"
    
    local line_count=$(wc -l < "$output_srt")
    log "Adjusted subtitle file created: $output_srt ($line_count lines)"
}

download_subtitles() {
    local url="$1"
    local output="$2"
    local subtitle_output=""

    log "Downloading subtitles..."

    # Try manual CC first (higher quality)
    yt-dlp --write-sub --skip-download --convert-subs srt --quiet "$url" -o "$output" 2>/dev/null || true

    # Check for any .srt file
    for srt_file in "$output"*.srt; do
        if [ -f "$srt_file" ] && [ -s "$srt_file" ]; then
            subtitle_output="$srt_file"
            log "Found manual CC subtitles: $srt_file"
            return 0
        fi
    done

    # Fall back to auto-generated
    log "Manual CC not found, trying auto-generated..."
    yt-dlp --write-auto-sub --skip-download --convert-subs srt --quiet "$url" -o "$output" 2>/dev/null || true

    # Check again for any .srt file
    for srt_file in "$output"*.srt; do
        if [ -f "$srt_file" ] && [ -s "$srt_file" ]; then
            subtitle_output="$srt_file"
            log "Found auto-generated subtitles: $srt_file"
            return 0
        fi
    done

    log "No subtitles available for this video"
    return 1
}

create_gif() {
    local video="$1"
    local start="$2"
    local end="$3"
    local output="$4"
    local subtitle_file="$5"
    local fps="$6"
    local width="$7"
    local subtitle_size="$8"

    log "Creating GIF..."

    # Build filter chain
    local filter_complex=""

    if [ -n "$subtitle_file" ] && [ -f "$subtitle_file" ]; then
        log "Embedding subtitles from: $subtitle_file"
        # Escape the subtitle file path for ffmpeg
        local escaped_srt="${subtitle_file//\\/\\\\}"
        escaped_srt="${escaped_srt//:/\\:}"
        escaped_srt="${escaped_srt//\'/\\\'}"
        
        filter_complex="[0:v]fps=${fps},scale=${width}:-1:flags=lanczos,subtitles='${escaped_srt}':force_style='Fontsize=${subtitle_size},PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,Outline=2,BackColour=&H80000000&,BorderStyle=4,MarginV=20'[scaled];"
        filter_complex+="[scaled]split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"
    else
        log "No subtitles found, creating GIF without them..."
        filter_complex="[0:v]fps=${fps},scale=${width}:-1:flags=lanczos[scaled];"
        filter_complex+="[scaled]split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"
    fi

    ffmpeg -y -ss "$start" -to "$end" -i "$video" \
        -filter_complex "$filter_complex" -loop 0 "$output" \
        -hide_banner -loglevel info -stats || error "Failed to create GIF"
}

main() {
    local fps=$DEFAULT_FPS
    local width=$DEFAULT_WIDTH
    local subtitle_size=$DEFAULT_SUBTITLE_SIZE
    local skip_subs=false
    local quality="normal"
    local manual_text=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage 0
                ;;
            -f|--fps)
                fps="$2"
                shift 2
                ;;
            -w|--width)
                width="$2"
                shift 2
                ;;
            -s|--subtitle-size)
                subtitle_size="$2"
                shift 2
                ;;
            -t|--text)
                manual_text="$2"
                shift 2
                ;;
            -n|--no-subs)
                skip_subs=true
                shift
                ;;
            -q|--quality)
                quality="best"
                shift
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    # Check required arguments
    if [ $# -ne 4 ]; then
        usage 1
    fi

    local youtube_url="$1"
    local start_time="$2"
    local end_time="$3"
    local output_gif="$4"

    # Validate inputs
    check_dependencies
    validate_youtube_url "$youtube_url"
    start_time=$(normalize_time "$start_time")
    end_time=$(normalize_time "$end_time")
    validate_time_range "$start_time" "$end_time"

    if [[ ! "$output_gif" =~ \.gif$ ]]; then
        error "Output file must end with .gif"
    fi

    # Setup temporary files
    local temp_video="$TEMP_DIR/video.mp4"
    local subtitle_file=""

    # Download content
    download_video "$youtube_url" "$temp_video" "$quality"

    # Handle subtitles
    if [ -n "$manual_text" ]; then
        # User provided manual text - create subtitle file
        create_manual_subtitle "$manual_text" "$start_time" "$end_time" "$TEMP_DIR/manual.srt"
        subtitle_file="$TEMP_DIR/manual.srt"
    elif [ "$skip_subs" = false ]; then
        # Download subtitles from YouTube
        if download_subtitles "$youtube_url" "$TEMP_DIR/video"; then
            # Find the first available .srt file
            for srt_file in "$TEMP_DIR/video"*.srt; do
                if [ -f "$srt_file" ] && [ -s "$srt_file" ]; then
                    # Adjust subtitle timing to match the clip
                    local adjusted_srt="$TEMP_DIR/adjusted.srt"
                    adjust_subtitle_timing "$srt_file" "$adjusted_srt" "$start_time"
                    subtitle_file="$adjusted_srt"
                    log "Subtitle timing adjusted for clip starting at $start_time"
                    break
                fi
            done
        else
            log "No subtitle file found"
        fi
    fi

    # Create GIF
    create_gif "$temp_video" "$start_time" "$end_time" "$output_gif" \
        "$subtitle_file" "$fps" "$width" "$subtitle_size"

    log "Success! GIF created: $output_gif"
    log "File size: $(du -h "$output_gif" | cut -f1)"
}

main "$@"