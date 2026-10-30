#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build SPACE.cob with yaccc and render the demo to an MP4.
#   YACCC  the yaccc launcher (default: yaccc on PATH)
#   OUT    the movie to write (default: space.mp4)
set -euo pipefail
cd "$(dirname "$0")"
YACCC="${YACCC:-yaccc}"
OUT="${OUT:-space.mp4}"
command -v "$YACCC" >/dev/null || { echo "yaccc not found: set YACCC to the yaccc launcher in your clone" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

"$YACCC" space.cob -o space
# 320x224 planar RGB at 30 fps, scaled 4x with hard pixel edges
./space | ffmpeg -loglevel error -y \
    -f rawvideo -pixel_format gbrp -video_size 320x224 -framerate 30 -i - \
    -vf "scale=1280:896:flags=neighbor,format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 18 -movflags +faststart "$OUT"
echo "wrote $OUT"
