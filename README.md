# SPACE.cob

**DATA DIVISION**: a 73-second flat-shaded polygon space demo, written in
COBOL and compiled with [yaccc](https://github.com/luckyseoul/yaccc).

![The strafing run](media/preview.gif)

A fighter squadron, a dogfight, a cockpit pass, a strafing run down the deck
of a capital ship, and the ship coming apart, in the style of the 32X /
Saturn era. There are no controls: it is a scripted attract-mode film.

The program draws every frame itself (transform, clipping, lighting, polygon
fill, sprites, particles, the HUD and the vector font) and writes raw frames
to standard output. ffmpeg only encodes them.

The whole film: [space.mp4](https://github.com/luckyseoul/SPACE.cob/releases/download/v1.0/space.mp4)
(1280×896, 30 fps, 7 MB).

![Dogfight, cockpit, strafing run, break-up](media/screenshot.png)

## Requirements

- [yaccc](https://github.com/luckyseoul/yaccc), which needs Python 3.11+ and gcc or clang
- ffmpeg, and ffplay for live playback
- numpy and scipy, only to regenerate `models.dat`

## Run

```
./render.sh          # builds ./space and writes space.mp4
./play.sh            # builds ./space and plays it live in ffplay
```

If `yaccc` is not on your PATH, set `YACCC` to the launcher in your yaccc
clone.

By hand:

```
yaccc space.cob
./space | ffmpeg -f rawvideo -pixel_format gbrp -video_size 320x224 \
    -framerate 30 -i - space.mp4
```

`DEMO_START` (first frame to output) and `DEMO_FRAMES` (how many) select a
range; earlier frames are still simulated so particles and wreckage are where
they should be. The full 2,190 frames render in about 23 seconds on one core,
about three times faster than they play. Every run produces the same bytes.

## Files

| File | |
|---|---|
| `space.cob` | the demo (free format COBOL, about 3,850 lines) |
| `font.cpy` | 41-glyph stroke font, copied into WORKING-STORAGE |
| `models.dat` | ships, cruiser, planet and wreckage: parts, vertices, faces, engine glows |
| `script.dat` | the choreography: spline keyframes, laser bursts, explosions |
| `tools/meshgen.py` | rebuilds `models.dat` |
| `tools/fontgen.py` | rebuilds `font.cpy` |

## How it works

- **Frame buffer.** 320x224, one byte per pixel, through a palette of 16 ramps
  of 16 shades. A frame goes out as three planes (G, B, R): each is the frame
  buffer run through `INSPECT ... CONVERTING` with that channel's palette, then
  one `WRITE` to a sequential file assigned to `DISPLAY`.
- **Polygons.** Convex polygons are filled by walking their edges into per-row
  left and right limits; each row is then a single reference-modified `MOVE`
  from a row pre-filled with that colour. Faces are flat shaded from a fixed
  sun, back-face culled in object space and clipped against the near plane
  (Sutherland–Hodgman).
- **Depth.** No z-buffer. Everything goes into an ordering table, 6 layers by
  4,096 depth buckets of linked lists, and is drawn back to front. Models are
  built from convex parts sorted by their centres. A part glued onto the
  cruiser's hull carries a mount plane and is drawn after the hull when the
  camera is in front of that plane, before it otherwise.
- **Effects.** Engine glows, fireballs and the sun are screen-facing sprite
  polygons, with a checkerboard dither for transparency. Sparks and laser
  bolts are clipped lines; debris is tumbling lit triangles; dust streaks with
  camera motion; the explosions flash the palette and shake the camera.
- **Motion.** Ships fly Catmull–Rom splines through the keyframes in
  `script.dat`, read with `UNSTRING` and `FUNCTION NUMVAL`, and bank into
  their turns from the path's lateral acceleration. Paths are defined in a
  frame that can move: the formation's frame, or the cruiser's.
- **Numbers.** Geometry is COMP-2. Float-to-integer conversions use the
  1.5 × 2^52 trick: add the constant and read the low 32 bits of the double
  through a `REDEFINES` (little-endian hosts, so x86-64 and ARM64). That is
  more than 100 times faster than a `COMPUTE` into a binary item, which goes
  through the decimal path. Sine and cosine come from a 4,096-entry table.

## Note on yaccc

In yaccc, a `COMPUTE` that divides by a full-precision intrinsic result
(`1 / FUNCTION SQRT(2)`, `1 / FUNCTION PI`) gives 0, whatever the receiving
item. `cob_d_div` scales the dividend to 37 digits, but an irrational
function result has 38 significant digits, so the integer quotient is 0. Exact
results such as `SQRT(4)` are fine. `space.cob` computes the function into a
COMP-2 item first and divides by that.

## Credits

Inspired by [FPS.cob](https://github.com/icitry/FPS.cob).

## License

MIT. See [LICENSE](LICENSE).
