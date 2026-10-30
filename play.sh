#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build SPACE.cob with yaccc and play the demo in an ffplay window, with sound.
#
# The demo renders faster than real time, so the whole film is muxed to a
# temporary MP4 first and then played: that keeps picture and soundtrack in
# step without a synchronisation clock of our own.
#   YACCC  the yaccc launcher (default: yaccc on PATH)
set -euo pipefail
cd "$(dirname "$0")"
YACCC="${YACCC:-yaccc}"
command -v "$YACCC" >/dev/null || { echo "yaccc not found: set YACCC to the yaccc launcher in your clone" >&2; exit 1; }
command -v ffplay >/dev/null || { echo "ffplay not found" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

"$YACCC" space.cob -o space

TMP="$(mktemp -d -t spaceplayXXXXXX)"
trap 'rm -rf "$TMP"' EXIT

DEMO_AUDIO="$TMP/audio.pcm" ./space > /dev/null

./space | ffmpeg -loglevel error -y \
    -f rawvideo -pixel_format gbrp -video_size 320x224 -framerate 30 -i - \
    -f s16le -ar 22050 -ac 1 -i "$TMP/audio.pcm" \
    -c:v libx264 -preset ultrafast -crf 20 \
    -c:a aac -b:a 96k -shortest "$TMP/space.mp4"

ffplay -autoexit -loglevel error -window_title "DATA DIVISION" \
    -vf "scale=960:672:flags=neighbor" "$TMP/space.mp4"
