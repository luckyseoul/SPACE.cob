# SPACE.cob

**DATA DIVISION** — a 100-second flat-shaded space demo, written in COBOL
and compiled with [yaccc](https://github.com/luckyseoul/yaccc). The program
renders every frame and synthesises every sample itself; no graphics or audio
library is involved.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Language: COBOL 85](https://img.shields.io/badge/language-COBOL%2085-1f425f.svg)](space.cob)

![The strafing run](media/preview.gif)

A squadron crosses a ringed giant. A dogfight, a cockpit pass, a strafing run
down the deck of a capital ship, the ship breaking apart, an aftermath pass
over the wreck, and an end card. The visual target is the 32X / Saturn era:
flat-shaded convex polygons on a 256-colour palette, sorted rather than
z-buffered.

There are no controls. It is a scripted attract-mode film.

**[Watch the whole film](https://github.com/luckyseoul/SPACE.cob/releases/download/v1.0/space.mp4)** —
1280×896, 30 fps, 100 s, with sound (8.4 MiB). Or render it yourself; see below.

![The squadron, the cockpit, the strafing run, the ending](media/screenshot.png)

## Specifications

| Property | Value |
|---|---|
| Resolution | 320×224, upscaled 4× for output |
| Colour | 256-entry palette: 16 ramps of 16 shades |
| Frame rate | 30 fps, 3,000 frames |
| Audio | 22,050 Hz mono, 16-bit |
| Source | 4,207 lines of free-format COBOL, one file |
| Geometry | 8 meshes, 2,781 vertices, 1,673 faces, 505 parts |
| Choreography | 195 spline keyframes, 28 laser bursts, 32 explosions |
| Depth | Ordering table, 6 layers × 4,096 buckets |
| Build | ~15 s to compile, ~36 s to render on one core |

## Quick start

Requirements:

- [yaccc](https://github.com/luckyseoul/yaccc), which needs Python 3.11+ and
  gcc or clang
- ffmpeg; ffplay as well if you want `play.sh`
- numpy and scipy, only to regenerate `models.dat`

```
./render.sh          # builds ./space, writes space.mp4
./play.sh            # builds ./space, plays it in ffplay
```

If yaccc is not on `PATH`, point `YACCC` at the launcher in your clone:

```
YACCC=../yaccc/yaccc ./render.sh
```

## Usage

`render.sh` runs the demo twice. The first pass writes only the soundtrack;
the second re-simulates the film and pipes the frames to ffmpeg. Two passes are
needed because ffmpeg has to see a complete file when it opens the audio
input, and the re-simulation produces identical bytes, which is what keeps
picture and sound in step without a synchronisation clock.

The same pipeline by hand:

```
yaccc space.cob
DEMO_AUDIO=space.pcm ./space > /dev/null          # pass 1: soundtrack
./space | ffmpeg -f rawvideo -pixel_format gbrp -video_size 320x224 \
    -framerate 30 -i - -f s16le -ar 22050 -ac 1 -i space.pcm \
    -c:v libx264 -crf 18 -c:a aac -shortest space.mp4
```

Environment variables:

| Variable | Meaning |
|---|---|
| `DEMO_START` | first frame to emit; earlier frames are still simulated, so particles and wreckage arrive in the right state |
| `DEMO_FRAMES` | how many frames to emit |
| `DEMO_AUDIO` | file to write the soundtrack to; when unset the demo produces no audio |

A partial render produces a partial soundtrack covering exactly the frames
emitted. Every run is deterministic: the same frame range produces the same
bytes, which is what makes the two-pass mux safe.

## The film

| # | Time | Scene |
|---|---|---|
| 1 | 0:00–0:06 | Title over the ringed giant |
| 2 | 0:06–0:12 | The squadron passes |
| 3 | 0:12–0:26 | Dogfight |
| 4 | 0:26–0:32 | Cockpit pass |
| 5 | 0:32–0:40 | The cruiser |
| 6 | 0:40–0:51 | Strafing run down the deck |
| 7 | 0:51–1:03 | The ship breaks apart |
| 8 | 1:03–1:13 | End card |
| 9 | 1:13–1:29 | Aftermath: the wreck turns |
| 10 | 1:29–1:40 | Closing card |

## Files

| File | Purpose |
|---|---|
| `space.cob` | the demo; free-format COBOL, 4,207 lines including the audio synthesiser |
| `font.cpy` | 41-glyph stroke font, copied into WORKING-STORAGE |
| `models.dat` | ships, cruiser, planet and wreckage: parts, vertices, faces, engine glows |
| `script.dat` | the choreography: spline keyframes, laser bursts, explosions |
| `render.sh` | build and encode to MP4 |
| `play.sh` | build and play in ffplay |
| `tools/meshgen.py` | rebuilds `models.dat` |
| `tools/fontgen.py` | rebuilds `font.cpy` |

## Architecture

```
space.cob
├─ INIT-ALL                 tables, palette, meshes, script, stars, dust
└─ per frame
  ├─ RUN-SCRIPT             scene clock, spline paths, camera, events
  ├─ UPDATE-EFFECTS         particles, lasers, drifting wreckage
  ├─ RENDER-AUDIO           735 samples for this frame
  ├─ RENDER-FRAME
  │  ├─ DRAW-STARS
  │  ├─ SUBMIT-*            sun, objects, particles, lasers, dust to the table
  │  ├─ DRAW-OT             back to front
  │  ├─ DRAW-HUD, DRAW-TEXTS
  │  └─ BUILD-PALETTE       palette flash and fade
  └─ EMIT-FRAME             three palette-mapped planes
```

**Frame buffer.** One byte per pixel, indexed into a palette of 16 ramps of 16
shades. A frame is emitted as three planes (G, B, R): each is the frame buffer
run through `INSPECT ... CONVERTING` with that channel's palette, then one
`WRITE` to a sequential file assigned to `DISPLAY`.

**Polygons.** Convex polygons are filled by walking their edges into per-row
left and right limits; each row is then a single reference-modified `MOVE`
from a row pre-filled with the colour. Faces are flat shaded from a fixed sun,
back-face culled in object space and clipped against the near plane
(Sutherland–Hodgman).

**Depth.** No z-buffer. Everything is inserted into an ordering table of six
layers by 4,096 depth buckets of linked lists and drawn back to front. Models
are built from convex parts sorted by their centres. A part glued to the
cruiser's hull carries a mount plane: it draws after the hull when the camera
is in front of that plane and before it otherwise.

**Effects.** Engine glows, fireballs and the sun are screen-facing sprite
polygons with a checkerboard dither for transparency. Sparks and laser bolts
are clipped lines; debris is tumbling lit triangles; dust streaks with camera
motion; explosions flash the palette and shake the camera.

**Motion.** Ships fly Catmull–Rom splines through the keyframes in
`script.dat`, read with `UNSTRING` and `FUNCTION NUMVAL`, and bank into their
turns from the path's lateral acceleration. Paths are defined in a frame that
can itself move: the formation's, or the cruiser's.

**Sound.** No mixer and no buffer. Each video frame synthesises 735 samples
and appends them to the file named by `DEMO_AUDIO`. Only the weapons sound: a
cannon report per laser shot and a sub-bass thump per explosion, with digital
silence between them. The cannon fundamental falls from 190 Hz to 90 Hz across
a burst; the blast starts at 22 Hz; the noise component of each is a one-pole
low pass at roughly 70 Hz.

**Numbers.** Geometry is COMP-2 throughout. Float-to-integer conversion uses
the 1.5 × 2⁵² trick — add the constant, read the low 32 bits of the double
through a `REDEFINES` — which is more than a hundred times faster than a
`COMPUTE` into a binary item, since that goes through the decimal path. Sine
and cosine come from a 4,096-entry table.

## Implementation notes

Three things cost more time than they should have. They are recorded because
each produced a result that looked plausible and was wrong.

**Rounding to even, not down.** The float-to-integer conversion above is
correct, but subtracting 0.5 before the add — to round to nearest — breaks
when the value is already an integer: `x − 0.5` lands exactly on a tie, and
round-half-to-even then alternates. Passing 0, 1, 2, 3, 4 through it gives
0, 0, 2, 2, 4. A one-pixel stroke loses every other dot, and a line's step
comes out doubled. That is what rendered the HUD labels as hollow dotted
boxes.

**A falling pitch is not `sin(t · f(t))`.** With `f` shrinking, the
instantaneous frequency is `f + t·f′`. A 190 Hz tone that is lowering after
fourteen seconds lands tens of kilohertz below zero and aliases into hiss. The
first version of the soundtrack measured 73–99% of its energy above 500 Hz for
this reason alone. Phase is now integrated from each cue's onset,
`f₀ · (d − k·d²/2)`, which gives the sweep it was meant to be: 90–99% of the
energy below 150 Hz.

**Clipping is not neutral.** Pinning a low sine to the rail adds harmonics,
and the result measures as bright. The mix is soft-limited at 0.72 rather than
0.95 for that reason.

## Compiler notes

Two yaccc defects turned up while making this, one fixed and one open.

**Division by an inexact intrinsic result — fixed.** `COMPUTE A = 1 /
FUNCTION PI` used to yield 0, because `cob_d_div` scaled the dividend to 37
digits while an irrational function result carries 38, leaving an integer
quotient of 0. Fixed upstream in
[yaccc@2a20fae](https://github.com/luckyseoul/yaccc/commit/2a20fae) by
rounding divisors of more than 19 significant digits;
`tests/cases/divirr.cbl` there checks eight such divisions against `cobc`.
`space.cob` still divides through a COMP-2 item rather than dividing by the
function directly, so it also builds with older compilers.

**`**` does not compile — open.** `COMPUTE X = 2.718 ** (-Y * 3)` generates
`pow()` in the C and never emits `#include <math.h>`, so the build fails with
an implicit-declaration error. The exponential envelopes here use
`FUNCTION EXP` instead. Anything else raising a value to a computed power will
hit it.

## Credits

Inspired by [FPS.cob](https://github.com/icitry/FPS.cob).

## License

MIT. See [LICENSE](LICENSE).
