#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Build SPACE.cob with yaccc and play the demo live in an ffplay window.
# The renderer runs faster than real time, so ffplay paces it at 30 fps.
#   YACCC  the yaccc launcher (default: yaccc on PATH)
set -euo pipefail
cd "$(dirname "$0")"
YACCC="${YACCC:-yaccc}"
command -v "$YACCC" >/dev/null || { echo "yaccc not found: set YACCC to the yaccc launcher in your clone" >&2; exit 1; }
command -v ffplay >/dev/null || { echo "ffplay not found" >&2; exit 1; }

"$YACCC" space.cob -o space
./space | ffplay -autoexit -loglevel error -window_title "DATA DIVISION" \
    -f rawvideo -pixel_format gbrp -video_size 320x224 -framerate 30 \
    -vf "scale=960:672:flags=neighbor" -i -
