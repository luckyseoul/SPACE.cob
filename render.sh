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

# Two passes. The soundtrack has to be complete before ffmpeg opens it, and the
# first pass writes nothing but audio. The second pass re-simulates the film to
# pipe the frames; it produces the same bytes, which is what keeps picture and
# sound in step without a clock of our own.
AUDIO="$(mktemp -t spaceaudioXXXXXX.pcm)"
trap 'rm -f "$AUDIO"' EXIT
DEMO_AUDIO="$AUDIO" ./space > /dev/null

./space | ffmpeg -y \
    -f rawvideo -pixel_format gbrp -video_size 320x224 -framerate 30 -i - \
    -f s16le -ar 22050 -ac 1 -i "$AUDIO" \
    -vf "scale=1280:896:flags=neighbor,format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 18 -movflags +faststart \
    -c:a aac -b:a 96k -shortest "$OUT"
echo "wrote $OUT"
