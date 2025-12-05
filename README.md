# yt2gif

> Ensure `yt-dlp` and `ffmpeg` have already been installed and are available in your PATH

Usage: 
```bash
yt2gif.sh [OPTIONS] <youtube_url> <start_time> <end_time> <output_gif>
```

Create an animated GIF from a YouTube video segment with optional subtitles.

## Arguments:

    youtube_url     YouTube video URL
    start_time      Start time (HH:MM:SS or MM:SS or seconds)
    end_time        End time (HH:MM:SS or MM:SS or seconds)
    output_gif      Output GIF filename

## Options:
    
    -f, --fps N         Frame rate (default: 15)
    -w, --width N       Width in pixels (default: 800, height auto)
    -s, --subtitle-size Size of subtitles (default: 24)
    -t, --text TEXT     Add custom subtitle text (overrides downloaded subs)
    -n, --no-subs       Skip subtitle download/embedding
    -q, --quality       Use best quality (slower, larger file)
    -h, --help          Show this help message

## Examples:
    
    yt2gif.sh https://youtu.be/example 10 15 output.gif
    yt2gif.sh -f 20 -w 640 https://youtu.be/example 00:00:10 00:00:15 output.gif
    yt2gif.sh --no-subs https://youtu.be/example 1:30 1:45 output.gif
    yt2gif.sh -t "Hello World!" https://youtu.be/example 5 10 output.gif

## Run Test

```
./test_yt2gif.sh [--verbose]
```
