>>SOURCE FORMAT FREE
*> SPDX-License-Identifier: MIT
*> =====================================================================
*>  SPACE.cob - DATA DIVISION
*>  A flat-shaded polygon space demo, written in COBOL.
*>
*>  Renders 320x224 frames through a 256-colour palette, sorts polygons
*>  with a layered ordering table (painter's algorithm, no z-buffer) and
*>  writes every frame to standard output as raw planar RGB, ready for
*>  ffmpeg (pixel format gbrp, 30 frames a second):
*>
*>    ./space | ffmpeg -f rawvideo -pixel_format gbrp
*>                       -video_size 320x224 -framerate 30 -i - out.mp4
*>
*>  models.dat  ships, cruiser and planet (written by tools/meshgen.py)
*>  script.dat  keyframed flight paths, laser bursts and explosions
*>
*>  Environment: DEMO_START   first frame to emit (earlier frames are
*>                            simulated but not drawn)
*>               DEMO_FRAMES  number of frames to emit
*> =====================================================================
IDENTIFICATION DIVISION.
PROGRAM-ID. SPACE-COB.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT FRAME-FILE ASSIGN TO DISPLAY
        ORGANIZATION IS SEQUENTIAL.
    SELECT MODEL-FILE ASSIGN TO "models.dat"
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS MODEL-STATUS.
    SELECT SCRIPT-FILE ASSIGN TO "script.dat"
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS SCRIPT-STATUS.

DATA DIVISION.
FILE SECTION.
FD  FRAME-FILE.
01  FRAME-REC.
    05 PLANE-G                 PIC X(71680).
    05 PLANE-B                 PIC X(71680).
    05 PLANE-R                 PIC X(71680).

FD  MODEL-FILE.
01  MODEL-REC.
    05 MR-TYPE                 PIC X.
    05 MR-FLD                  PIC S9(5)V9(3) SIGN LEADING SEPARATE
                               OCCURS 12.

FD  SCRIPT-FILE.
01  SCRIPT-REC                 PIC X(200).

WORKING-STORAGE SECTION.
78  MAX-MESH                   VALUE 12.
78  MAX-VERT                   VALUE 3600.
78  MAX-FACE                   VALUE 2400.
78  MAX-PART                   VALUE 600.
78  MAX-GLOW                   VALUE 16.
78  MAX-OBJ                    VALUE 32.
78  MAX-TV                     VALUE 1600.
78  MAX-PB                     VALUE 7000.
78  OT-SIZE                    VALUE 24576.
78  MAX-PT                     VALUE 1500.
78  MAX-LZ                     VALUE 300.
78  MAX-STAR                   VALUE 700.
78  MAX-DUST                   VALUE 70.
78  MAX-TEXT                   VALUE 10.
78  MAX-KEY                    VALUE 700.
78  MAX-PATH                   VALUE 900.
78  MAX-BURST                  VALUE 100.
78  MAX-BOOM                   VALUE 100.
78  NGLYPH                     VALUE 41.

*> ---------------------------------------------------------------- files
01  MODEL-STATUS               PIC XX.
01  SHOW-1                     PIC Z(5)9.
01  SHOW-2                     PIC Z(5)9.
01  SHOW-3                     PIC Z(5)9.
01  SHOW-4                     PIC Z(5)9.
01  SCRIPT-STATUS              PIC XX.
01  FILE-EOF                   PIC 9.

*> ---------------------------------------------------------------- clock
01  FRAME-NO                   BINARY-LONG.
01  TOTAL-FRAMES               BINARY-LONG VALUE 2190.
01  START-FRAME                BINARY-LONG VALUE 0.
01  END-FRAME                  BINARY-LONG.
01  ENV-TEXT                   PIC X(16).
01  NOW-T                      COMP-2.
01  DT                         COMP-2.

*> ---------------------------------------------------------------- number tricks
*> Adding 1.5 * 2**52 to a double leaves the nearest integer in the low
*> 32 bits of its mantissa, so float-to-integer is one COMPUTE and a MOVE.
01  MAGIC-K                    COMP-2 VALUE 6755399441055744.0.
01  MAGIC-D                    COMP-2.
01  MAGIC-PARTS REDEFINES MAGIC-D.
    05 MAGIC-LO                BINARY-LONG.
    05 MAGIC-HI                BINARY-LONG.
01  BYTE-N                     BINARY-CHAR UNSIGNED.
01  BYTE-C REDEFINES BYTE-N    PIC X.
01  TWO-PI                     COMP-2 VALUE 6.283185307179586.
01  SIN-TAB.
    05 SIN-V                   COMP-2 OCCURS 4097.
01  RNG-SEED                   BINARY-DOUBLE VALUE 20261029.
01  RND                        COMP-2.
01  ANG                        COMP-2.
01  SN                         COMP-2.
01  CS                         COMP-2.
01  SC-TURN                    COMP-2.
01  SC-POS                     COMP-2.
01  SC-FR                      COMP-2.
01  SC-I                       BINARY-LONG.
01  SC-J                       BINARY-LONG.
01  A1                         COMP-2.
01  A2                         COMP-2.
01  A3                         COMP-2.
01  A4                         COMP-2.
01  A5                         COMP-2.
01  A6                         COMP-2.
01  IX                         BINARY-LONG.
01  JX                         BINARY-LONG.
01  KX                         BINARY-LONG.
01  VEC-X                      COMP-2.
01  VEC-Y                      COMP-2.
01  VEC-Z                      COMP-2.
01  VEC-L                      COMP-2.

*> ---------------------------------------------------------------- palette
*> 16 ramps of 16 shades: colour at shade 0, shade 10 and shade 15 (RGB).
01  RAMP-DATA.
    05 FILLER PIC X(27) VALUE "000000000170170180255255255".
    05 FILLER PIC X(27) VALUE "014016022178182190245245240".
    05 FILLER PIC X(27) VALUE "006010030040090210150200255".
    05 FILLER PIC X(27) VALUE "012010016100096118190186210".
    05 FILLER PIC X(27) VALUE "024004006190030040255140120".
    05 FILLER PIC X(27) VALUE "014015014120126118210214200".
    05 FILLER PIC X(27) VALUE "008009010070074080150156165".
    05 FILLER PIC X(27) VALUE "040000000255120020255255200".
    05 FILLER PIC X(27) VALUE "000030000040255060220255220".
    05 FILLER PIC X(27) VALUE "040000000255040030255220210".
    05 FILLER PIC X(27) VALUE "020014008196160110250230190".
    05 FILLER PIC X(27) VALUE "018008004170090055240170130".
    05 FILLER PIC X(27) VALUE "022020016225215180255250235".
    05 FILLER PIC X(27) VALUE "012011010140128112215205190".
    05 FILLER PIC X(27) VALUE "000020008040220110200255220".
    05 FILLER PIC X(27) VALUE "002010014030120150170240255".
01  RAMP-TAB REDEFINES RAMP-DATA.
    05 RAMP-ENT                OCCURS 16.
       10 RAMP-C               PIC 999 OCCURS 9.
01  BASE-PAL.
    05 BASE-ENT                OCCURS 256.
       10 BASE-R               COMP-2.
       10 BASE-G               COMP-2.
       10 BASE-B               COMP-2.
01  RI                         BINARY-LONG.
01  SI                         BINARY-LONG.
01  FX-FADE                    COMP-2 VALUE 1.
01  FX-FLASH                   COMP-2 VALUE 0.
01  FX-FLASH-RATE              COMP-2 VALUE 1.
01  FX-SHAKE                   COMP-2 VALUE 0.

*> ---------------------------------------------------------------- frame buffer
01  FB                         PIC X(71680).
01  FILL-ROWS.
    05 FILL-ROW                PIC X(320) OCCURS 256.
01  IDENT-256.
    05 IDENT-C                 PIC X OCCURS 256.
01  PAL-R-STR.
    05 PAL-R                   PIC X OCCURS 256.
01  PAL-G-STR.
    05 PAL-G                   PIC X OCCURS 256.
01  PAL-B-STR.
    05 PAL-B                   PIC X OCCURS 256.

*> ---------------------------------------------------------------- camera
01  CAM-PX                     COMP-2.
01  CAM-PY                     COMP-2.
01  CAM-PZ                     COMP-2.
01  CAM-TX                     COMP-2.
01  CAM-TY                     COMP-2.
01  CAM-TZ                     COMP-2.
01  CAM-UPX                    COMP-2.
01  CAM-UPY                    COMP-2.
01  CAM-UPZ                    COMP-2.
01  CAM-ROLL                   COMP-2.
01  CAM-RX                     COMP-2.
01  CAM-RY                     COMP-2.
01  CAM-RZ                     COMP-2.
01  CAM-UX                     COMP-2.
01  CAM-UY                     COMP-2.
01  CAM-UZ                     COMP-2.
01  CAM-FX                     COMP-2.
01  CAM-FY                     COMP-2.
01  CAM-FZ                     COMP-2.
01  CAM-OLDX                   COMP-2.
01  CAM-OLDY                   COMP-2.
01  CAM-OLDZ                   COMP-2.
01  CAM-VX                     COMP-2.
01  CAM-VY                     COMP-2.
01  CAM-VZ                     COMP-2.
01  CAM-CUT                    BINARY-LONG VALUE 1.
01  FOCAL                      COMP-2 VALUE 210.
01  ZNEAR                      COMP-2 VALUE 0.5.
01  ZFAR                       COMP-2 VALUE 90000.
01  FR-KX                      COMP-2.
01  FR-KY                      COMP-2.
01  SUN-X                      COMP-2.
01  SUN-Y                      COMP-2.
01  SUN-Z                      COMP-2.
01  AMBIENT                    COMP-2 VALUE 3.1.
01  DIFFUSE                    COMP-2 VALUE 10.4.
01  WX                         COMP-2.
01  WY                         COMP-2.
01  WZ                         COMP-2.
01  CX                         COMP-2.
01  CY                         COMP-2.
01  CZ                         COMP-2.

*> ---------------------------------------------------------------- models
01  MESH-COUNT                 BINARY-LONG.
01  MESH-TAB.
    05 MESH-ENT                OCCURS 12.
       10 MS-V0                BINARY-LONG.
       10 MS-NV                BINARY-LONG.
       10 MS-F0                BINARY-LONG.
       10 MS-NF                BINARY-LONG.
       10 MS-P0                BINARY-LONG.
       10 MS-NP                BINARY-LONG.
       10 MS-G0                BINARY-LONG.
       10 MS-NG                BINARY-LONG.
       10 MS-RAD               COMP-2.
01  VERT-COUNT                 BINARY-LONG.
01  VERT-TAB.
    05 VERT-ENT                OCCURS 3600.
       10 VX                   COMP-2.
       10 VY                   COMP-2.
       10 VZ                   COMP-2.
01  FACE-COUNT                 BINARY-LONG.
01  FACE-TAB.
    05 FACE-ENT                OCCURS 2400.
       10 FC-N                 BINARY-LONG.
       10 FC-V                 BINARY-LONG OCCURS 6.
       10 FC-RAMP              BINARY-LONG.
       10 FC-EMIT              BINARY-LONG.
       10 FC-2SIDE             BINARY-LONG.
       10 FC-CAP               BINARY-LONG.
       10 FC-PART              BINARY-LONG.
       10 FC-SHADE             BINARY-LONG.
       10 FC-NX                COMP-2.
       10 FC-NY                COMP-2.
       10 FC-NZ                COMP-2.
01  PART-COUNT                 BINARY-LONG.
01  PART-TAB.
    05 PART-ENT                OCCURS 600.
       10 PA-CX                COMP-2.
       10 PA-CY                COMP-2.
       10 PA-CZ                COMP-2.
       10 PA-MOUNT             BINARY-LONG.
       10 PA-NX                COMP-2.
       10 PA-NY                COMP-2.
       10 PA-NZ                COMP-2.
       10 PA-D                 COMP-2.
       10 PW-Z                 COMP-2.
       10 PW-LAYER             BINARY-LONG.
01  GLOW-COUNT                 BINARY-LONG.
01  GLOW-TAB.
    05 GLOW-ENT                OCCURS 16.
       10 GW-X                 COMP-2.
       10 GW-Y                 COMP-2.
       10 GW-Z                 COMP-2.
       10 GW-SIZE              COMP-2.
       10 GW-RAMP              BINARY-LONG.
       10 GW-SHADE             BINARY-LONG.
01  FLAGS-W                    BINARY-LONG.
01  FLAGS-Q                    BINARY-LONG.
01  NX-ACC                     COMP-2.
01  NY-ACC                     COMP-2.
01  NZ-ACC                     COMP-2.
01  VA                         BINARY-LONG.
01  VB                         BINARY-LONG.
01  FI                         BINARY-LONG.

*> ---------------------------------------------------------------- objects
*> 1 planet, 2-5 friendly fighters, 6-11 enemy fighters,
*> 12 cruiser stern, 13 cruiser bow, 14-25 wreckage
01  OBJ-TAB.
    05 OBJ-ENT                 OCCURS 32.
       10 OB-ACTIVE            BINARY-LONG.
       10 OB-HIDE              BINARY-LONG.
       10 OB-MESH              BINARY-LONG.
       10 OB-LAYER             BINARY-LONG.
       10 OB-BROKEN            BINARY-LONG.
       10 OB-PATHED            BINARY-LONG.
       10 OB-DRIFT             BINARY-LONG.
       10 OB-DEBRIS            BINARY-LONG.
       10 OB-PX                COMP-2.
       10 OB-PY                COMP-2.
       10 OB-PZ                COMP-2.
       10 OB-XX                COMP-2.
       10 OB-XY                COMP-2.
       10 OB-XZ                COMP-2.
       10 OB-YX                COMP-2.
       10 OB-YY                COMP-2.
       10 OB-YZ                COMP-2.
       10 OB-ZX                COMP-2.
       10 OB-ZY                COMP-2.
       10 OB-ZZ                COMP-2.
       10 OB-SCALE             COMP-2.
       10 OB-VX                COMP-2.
       10 OB-VY                COMP-2.
       10 OB-VZ                COMP-2.
       10 OB-WX                COMP-2.
       10 OB-WY                COMP-2.
       10 OB-WZ                COMP-2.
       10 OB-WRATE             COMP-2.
01  OI                         BINARY-LONG.
01  OJ                         BINARY-LONG.

*> per-object transform work
01  SO-MI                      BINARY-LONG.
01  SO-V0                      BINARY-LONG.
01  SO-S                       COMP-2.
01  SO-DX                      COMP-2.
01  SO-DY                      COMP-2.
01  SO-DZ                      COMP-2.
01  SO-TX                      COMP-2.
01  SO-TY                      COMP-2.
01  SO-TZ                      COMP-2.
01  SO-RAD                     COMP-2.
01  SO-M11                     COMP-2.
01  SO-M12                     COMP-2.
01  SO-M13                     COMP-2.
01  SO-M21                     COMP-2.
01  SO-M22                     COMP-2.
01  SO-M23                     COMP-2.
01  SO-M31                     COMP-2.
01  SO-M32                     COMP-2.
01  SO-M33                     COMP-2.
01  SO-CLX                     COMP-2.
01  SO-CLY                     COMP-2.
01  SO-CLZ                     COMP-2.
01  SO-LLX                     COMP-2.
01  SO-LLY                     COMP-2.
01  SO-LLZ                     COMP-2.
01  SO-FLICK                   BINARY-LONG.
01  SO-I                       BINARY-LONG.
01  SO-G                       BINARY-LONG.
01  SO-RZ                      COMP-2.
01  TV-TAB.
    05 TV-ENT                  OCCURS 1600.
       10 TV-X                 COMP-2.
       10 TV-Y                 COMP-2.
       10 TV-Z                 COMP-2.
       10 TV-SX                COMP-2.
       10 TV-SY                COMP-2.

*> per-face work
01  GF                         BINARY-LONG.
01  GV                         BINARY-LONG.
01  SF-VIS                     COMP-2.
01  SF-L                       COMP-2.
01  SF-K                       BINARY-LONG.
01  SF-LV                      BINARY-LONG.
01  SF-BEHIND                  BINARY-LONG.
01  SF-SHADE                   BINARY-LONG.
01  SF-COL                     BINARY-LONG.
01  SF-P                       BINARY-LONG.
01  CL-N                       BINARY-LONG.
01  CL-VERTS.
    05 CL-V                    OCCURS 8.
       10 CL-X                 COMP-2.
       10 CL-Y                 COMP-2.
       10 CL-Z                 COMP-2.
       10 CL-SX                COMP-2.
       10 CL-SY                COMP-2.
01  CP-K                       BINARY-LONG.
01  CP-PREV                    BINARY-LONG.
01  CP-OUT                     BINARY-LONG.
01  CP-T                       COMP-2.
01  CP-X                       COMP-2.
01  CP-Y                       COMP-2.

*> ---------------------------------------------------------------- ordering table
*> Six layers of 4096 depth buckets, drawn back to front. Layer 0 is the
*> sky, layers 1-3 the cruiser (behind / hull / in front of its mount
*> planes), layer 4 everything else.
01  PB-COUNT                   BINARY-LONG.
01  NEW-PB                     BINARY-LONG.
01  PB-TAB.
    05 PB-ENT                  OCCURS 7000.
       10 PB-NEXT              BINARY-LONG.
       10 PB-TYPE              BINARY-LONG.
       10 PB-N                 BINARY-LONG.
       10 PB-COL               BINARY-LONG.
       10 PB-COL2              BINARY-LONG.
       10 PB-MESH              BINARY-LONG.
       10 PB-X                 COMP-2 OCCURS 16.
       10 PB-Y                 COMP-2 OCCURS 16.
01  OT-TAB.
    05 OT-HEAD                 BINARY-LONG OCCURS 24576.
01  OT-Z                       COMP-2.
01  OT-LAYER                   BINARY-LONG.
01  OT-B                       BINARY-LONG.
01  OT-I                       BINARY-LONG.
01  DO-L                       BINARY-LONG.
01  DO-B                       BINARY-LONG.
01  DO-P                       BINARY-LONG.
01  DO-K                       BINARY-LONG.

*> ---------------------------------------------------------------- rasteriser
01  RP-N                       BINARY-LONG.
01  RP-COL                     BINARY-LONG.
01  RP-MESH                    BINARY-LONG.
01  RP-VERTS.
    05 RP-V                    OCCURS 16.
       10 RP-X                 COMP-2.
       10 RP-Y                 COMP-2.
01  XL-TAB.
    05 XL                      COMP-2 OCCURS 224.
01  XR-TAB.
    05 XR                      COMP-2 OCCURS 224.
01  RS-YMIN                    COMP-2.
01  RS-YMAX                    COMP-2.
01  RS-XMIN                    COMP-2.
01  RS-XMAX                    COMP-2.
01  RS-EX1                     COMP-2.
01  RS-EY1                     COMP-2.
01  RS-EX2                     COMP-2.
01  RS-EY2                     COMP-2.
01  RS-SLOPE                   COMP-2.
01  RS-XC                      COMP-2.
01  RS-T                       COMP-2.
01  RS-K                       BINARY-LONG.
01  RS-K2                      BINARY-LONG.
01  RS-J                       BINARY-LONG.
01  RS-J0                      BINARY-LONG.
01  RS-J1                      BINARY-LONG.
01  RS-JA                      BINARY-LONG.
01  RS-JB                      BINARY-LONG.
01  RS-XS                      BINARY-LONG.
01  RS-XE                      BINARY-LONG.
01  RS-SPAN                    BINARY-LONG.
01  RS-OFF                     BINARY-LONG.
01  RS-ROW                     BINARY-LONG.
01  BIG-POS                    COMP-2 VALUE 1.0E9.
01  BIG-NEG                    COMP-2 VALUE -1.0E9.

*> ---------------------------------------------------------------- lines
01  LN-X1                      COMP-2.
01  LN-Y1                      COMP-2.
01  LN-X2                      COMP-2.
01  LN-Y2                      COMP-2.
01  LN-COL                     BINARY-LONG.
01  LN-W                       BINARY-LONG.
01  LN-DX                      COMP-2.
01  LN-DY                      COMP-2.
01  LN-T0                      COMP-2.
01  LN-T1                      COMP-2.
01  LN-P                       COMP-2.
01  LN-Q                       COMP-2.
01  LN-R                       COMP-2.
01  LN-REJECT                  BINARY-LONG.
01  LN-AX                      COMP-2.
01  LN-AY                      COMP-2.
01  LN-LEN                     COMP-2.
01  LN-SX                      COMP-2.
01  LN-SY                      COMP-2.
01  LN-CX                      COMP-2.
01  LN-CY                      COMP-2.
01  LN-N                       BINARY-LONG.
01  LN-I                       BINARY-LONG.
01  PL-X                       BINARY-LONG.
01  PL-Y                       BINARY-LONG.
01  PL-X0                      BINARY-LONG.
01  PL-X1                      BINARY-LONG.
01  PL-Y0                      BINARY-LONG.
01  PL-Y1                      BINARY-LONG.
01  PL-OFF                     BINARY-LONG.
01  PL-LEN                     BINARY-LONG.
01  PL-ROW                     BINARY-LONG.

*> ---------------------------------------------------------------- sprites
01  DIR-TAB.
    05 DIR-ENT                 OCCURS 16.
       10 DIR-C                COMP-2.
       10 DIR-S                COMP-2.
01  JIT-TAB.
    05 JIT                     COMP-2 OCCURS 32.
01  SPR-CX                     COMP-2.
01  SPR-CY                     COMP-2.
01  SPR-R                      COMP-2.
01  SPR-SPIKE                  COMP-2.
01  SPR-NV                     BINARY-LONG.
01  SPR-MESH                   BINARY-LONG.
01  SPR-JAMT                   COMP-2.
01  SPR-A                      COMP-2.
01  SPR-SEED                   BINARY-LONG.
01  SPR-COL                    BINARY-LONG.
01  SPR-K                      BINARY-LONG.
01  SPR-D                      BINARY-LONG.

*> ---------------------------------------------------------------- stars and dust
01  STAR-TAB.
    05 STAR-ENT                OCCURS 700.
       10 SR-X                 COMP-2.
       10 SR-Y                 COMP-2.
       10 SR-Z                 COMP-2.
       10 SR-COL               BINARY-LONG.
01  ST-I                       BINARY-LONG.
01  ST-Z                       COMP-2.
01  ST-K                       COMP-2.
01  ST-SX                      BINARY-LONG.
01  ST-SY                      BINARY-LONG.
01  ST-OFF                     BINARY-LONG.
01  DUST-ON                    BINARY-LONG.
01  DUST-TAB.
    05 DUST-ENT                OCCURS 70.
       10 DU-X                 COMP-2.
       10 DU-Y                 COMP-2.
       10 DU-Z                 COMP-2.

*> ---------------------------------------------------------------- particles
*> type 1 fireball, 2 spark, 3 debris triangle, 4 smoke
01  PT-TAB.
    05 PT-ENT                  OCCURS 1500.
       10 PT-TYPE              BINARY-LONG.
       10 PT-RAMP              BINARY-LONG.
       10 PT-X                 COMP-2.
       10 PT-Y                 COMP-2.
       10 PT-Z                 COMP-2.
       10 PT-VX                COMP-2.
       10 PT-VY                COMP-2.
       10 PT-VZ                COMP-2.
       10 PT-AGE               COMP-2.
       10 PT-LIFE              COMP-2.
       10 PT-SIZE              COMP-2.
       10 PT-DELAY             COMP-2.
       10 PT-DRAG              COMP-2.
       10 PT-ROT               COMP-2.
       10 PT-ROTV              COMP-2.
       10 PT-AX                COMP-2.
       10 PT-AY                COMP-2.
       10 PT-AZ                COMP-2.
       10 PT-BX                COMP-2.
       10 PT-BY                COMP-2.
       10 PT-BZ                COMP-2.
       10 PT-NX                COMP-2.
       10 PT-NY                COMP-2.
       10 PT-NZ                COMP-2.
01  PT-CURSOR                  BINARY-LONG VALUE 1.
01  EF-I                       BINARY-LONG.
01  EF-NEW                     BINARY-LONG.
01  EF-K                       BINARY-LONG.
01  EF-F                       COMP-2.
01  EF-S                       COMP-2.
01  EF-PX                      COMP-2.
01  EF-PY                      COMP-2.
01  EF-PZ                      COMP-2.
01  EF-QX                      COMP-2.
01  EF-QY                      COMP-2.
01  EF-QZ                      COMP-2.
01  EF-AX                      COMP-2.
01  EF-AY                      COMP-2.
01  EF-AZ                      COMP-2.
01  EF-NX                      COMP-2.
01  EF-NY                      COMP-2.
01  EF-NZ                      COMP-2.
01  EF-SHADE                   BINARY-LONG.

*> explosion request
01  EX-X                       COMP-2.
01  EX-Y                       COMP-2.
01  EX-Z                       COMP-2.
01  EX-VX                      COMP-2.
01  EX-VY                      COMP-2.
01  EX-VZ                      COMP-2.
01  EX-SIZE                    COMP-2.
01  EX-RAMP                    BINARY-LONG.
01  EX-I                       BINARY-LONG.
01  EX-N                       BINARY-LONG.
01  EX-SPD                     COMP-2.

*> new particle request
01  NP-TYPE                    BINARY-LONG.
01  NP-RAMP                    BINARY-LONG.
01  NP-X                       COMP-2.
01  NP-Y                       COMP-2.
01  NP-Z                       COMP-2.
01  NP-VX                      COMP-2.
01  NP-VY                      COMP-2.
01  NP-VZ                      COMP-2.
01  NP-LIFE                    COMP-2.
01  NP-SIZE                    COMP-2.
01  NP-DELAY                   COMP-2.
01  NP-DRAG                    COMP-2.

*> ---------------------------------------------------------------- lasers
01  LZ-TAB.
    05 LZ-ENT                  OCCURS 300.
       10 LZ-ON                BINARY-LONG.
       10 LZ-RAMP              BINARY-LONG.
       10 LZ-KILL              BINARY-LONG.
       10 LZ-X                 COMP-2.
       10 LZ-Y                 COMP-2.
       10 LZ-Z                 COMP-2.
       10 LZ-VX                COMP-2.
       10 LZ-VY                COMP-2.
       10 LZ-VZ                COMP-2.
       10 LZ-AGE               COMP-2.
       10 LZ-LIFE              COMP-2.
       10 LZ-K                 COMP-2.
       10 LZ-BOOM              COMP-2.
01  LZ-CURSOR                  BINARY-LONG VALUE 1.

*> ---------------------------------------------------------------- text
01  TEXT-COUNT                 BINARY-LONG.
01  TEXT-TAB.
    05 TEXT-ENT                OCCURS 10.
       10 TX-STR               PIC X(40).
       10 TX-LEN               BINARY-LONG.
       10 TX-X                 COMP-2.
       10 TX-Y                 COMP-2.
       10 TX-SCALE             COMP-2.
       10 TX-COL               BINARY-LONG.
       10 TX-GLOW              BINARY-LONG.
       10 TX-REVEAL            COMP-2.
01  TD-I                       BINARY-LONG.
01  TD-C                       BINARY-LONG.
01  TD-G                       BINARY-LONG.
01  TD-S                       BINARY-LONG.
01  TD-PASS                    BINARY-LONG.
01  TD-DONE                    COMP-2.
01  TD-X0                      COMP-2.
01  TD-FR                      COMP-2.
01  NEW-TEXT                   PIC X(40).
01  NEW-TX                     COMP-2.
01  NEW-TY                     COMP-2.
01  NEW-SCALE                  COMP-2.
01  NEW-COL                    BINARY-LONG.
01  NEW-GLOW                   BINARY-LONG.
01  NEW-REVEAL                 COMP-2.
01  NEW-CENTER                 BINARY-LONG.
01  NEW-LEN                    BINARY-LONG.
01  GLYPH-IX-TAB.
    05 GLYPH-IX                BINARY-LONG OCCURS 256.
COPY "font.cpy".

*> ---------------------------------------------------------------- script data
01  SCR-W.
    05 SW                      PIC X(16) OCCURS 18.
01  SW-N                       BINARY-LONG.
01  SCR-NUM.
    05 SV                      COMP-2 OCCURS 18.
01  KEY-COUNT                  BINARY-LONG.
01  KEY-TAB.
    05 KEY-ENT                 OCCURS 700.
       10 KF-PATH              BINARY-LONG.
       10 KF-T                 COMP-2.
       10 KF-X                 COMP-2.
       10 KF-Y                 COMP-2.
       10 KF-Z                 COMP-2.
       10 KF-ROLL              COMP-2.
01  PATH-DIR.
    05 PD-ENT                  OCCURS 900.
       10 PD-FIRST             BINARY-LONG.
       10 PD-COUNT             BINARY-LONG.
01  BURST-COUNT                BINARY-LONG.
01  BURST-TAB.
    05 BURST-ENT               OCCURS 100.
       10 BU-SCENE             BINARY-LONG.
       10 BU-SHOOTER           BINARY-LONG.
       10 BU-TARGET            BINARY-LONG.
       10 BU-T0                COMP-2.
       10 BU-COUNT             BINARY-LONG.
       10 BU-GAP               COMP-2.
       10 BU-HIT               BINARY-LONG.
       10 BU-SPREAD            COMP-2.
       10 BU-SPEED             COMP-2.
       10 BU-RAMP              BINARY-LONG.
       10 BU-BOOM              COMP-2.
       10 BU-SX                COMP-2.
       10 BU-SY                COMP-2.
       10 BU-SZ                COMP-2.
       10 BU-TX                COMP-2.
       10 BU-TY                COMP-2.
       10 BU-TZ                COMP-2.
01  BOOM-COUNT                 BINARY-LONG.
01  BOOM-TAB.
    05 BOOM-ENT                OCCURS 100.
       10 BM-SCENE             BINARY-LONG.
       10 BM-T                 COMP-2.
       10 BM-OBJ               BINARY-LONG.
       10 BM-KILL              BINARY-LONG.
       10 BM-SIZE              COMP-2.
       10 BM-X                 COMP-2.
       10 BM-Y                 COMP-2.
       10 BM-Z                 COMP-2.

*> spline evaluation
01  SP-PATH                    BINARY-LONG.
01  SP-T                       COMP-2.
01  SP-X                       COMP-2.
01  SP-Y                       COMP-2.
01  SP-Z                       COMP-2.
01  SP-ROLL                    COMP-2.
01  SP-OK                      BINARY-LONG.
01  SP-F                       BINARY-LONG.
01  SP-L                       BINARY-LONG.
01  SP-I                       BINARY-LONG.
01  SP-I0                      BINARY-LONG.
01  SP-I1                      BINARY-LONG.
01  SP-H                       COMP-2.
01  SP-S                       COMP-2.
01  SP-S2                      COMP-2.
01  SP-S3                      COMP-2.
01  SP-H00                     COMP-2.
01  SP-H10                     COMP-2.
01  SP-H01                     COMP-2.
01  SP-H11                     COMP-2.
01  SP-M0X                     COMP-2.
01  SP-M0Y                     COMP-2.
01  SP-M0Z                     COMP-2.
01  SP-M1X                     COMP-2.
01  SP-M1Y                     COMP-2.
01  SP-M1Z                     COMP-2.
01  SP-TA                      COMP-2.
01  SP-TB                      COMP-2.

*> ---------------------------------------------------------------- script state
01  SC-SCENE                   BINARY-LONG VALUE 0.
01  SC-LAST                    BINARY-LONG VALUE 0.
01  SC-T0                      COMP-2.
01  SC-U                       COMP-2.
01  SC-FRAME                   BINARY-LONG.
01  HUD-ON                     BINARY-LONG.
01  EVT                        COMP-2.
01  EV-HIT                     BINARY-LONG.
01  BI                         BINARY-LONG.
01  BS                         BINARY-LONG.
01  SHOT-T                     COMP-2.
01  SHOT-LAST                  BINARY-LONG.
01  FT                         COMP-2.
01  MZ-X                       COMP-2.
01  MZ-Y                       COMP-2.
01  MZ-Z                       COMP-2.
01  AIM-X                      COMP-2.
01  AIM-Y                      COMP-2.
01  AIM-Z                      COMP-2.
01  LX                         COMP-2.
01  LY                         COMP-2.
01  LZ                         COMP-2.

*> paths in scene frames
01  PE-OBJ                     BINARY-LONG.
01  PE-T                       COMP-2.
01  PE-X                       COMP-2.
01  PE-Y                       COMP-2.
01  PE-Z                       COMP-2.
01  PE-ROLL                    COMP-2.
01  PE-OK                      BINARY-LONG.
01  FRAME-KIND                 BINARY-LONG.
01  FRAME-W                    COMP-2.
01  P0X                        COMP-2.
01  P0Y                        COMP-2.
01  P0Z                        COMP-2.
01  P1X                        COMP-2.
01  P1Y                        COMP-2.
01  P1Z                        COMP-2.
01  P2X                        COMP-2.
01  P2Y                        COMP-2.
01  P2Z                        COMP-2.
01  OR-FX                      COMP-2.
01  OR-FY                      COMP-2.
01  OR-FZ                      COMP-2.
01  OR-RX                      COMP-2.
01  OR-RY                      COMP-2.
01  OR-RZ                      COMP-2.
01  OR-UX                      COMP-2.
01  OR-UY                      COMP-2.
01  OR-UZ                      COMP-2.
01  OR-ROLL                    COMP-2.
01  OR-LAT                     COMP-2.

*> cruiser frame
01  CR-Q0X                     COMP-2.
01  CR-Q0Y                     COMP-2.
01  CR-Q0Z                     COMP-2.
01  CR-QX                      COMP-2.
01  CR-QY                      COMP-2.
01  CR-QZ                      COMP-2.
01  CR-XX                      COMP-2.
01  CR-XY                      COMP-2.
01  CR-XZ                      COMP-2.
01  CR-YX                      COMP-2.
01  CR-YY                      COMP-2.
01  CR-YZ                      COMP-2.
01  CR-ZX                      COMP-2.
01  CR-ZY                      COMP-2.
01  CR-ZZ                      COMP-2.
01  CR-SPEED                   COMP-2 VALUE 8.
01  CR-SET                     BINARY-LONG VALUE 0.

*> chase camera parameters
01  CC-OBJ                     BINARY-LONG.
01  CC-BACK                    COMP-2.
01  CC-UP                      COMP-2.
01  CC-SIDE                    COMP-2.
01  CC-AHEAD                   COMP-2.
01  CC-UPW                     COMP-2.
01  CC-LOOK                    COMP-2.

*> HUD
01  HD-I                       BINARY-LONG.
01  HD-BEST                    BINARY-LONG.
01  HD-BZ                      COMP-2.
01  HD-SX                      COMP-2.
01  HD-SY                      COMP-2.
01  HD-SZ                      COMP-2.
01  HD-B                       COMP-2.
01  HD-RANGE                   PIC 9(4).
01  HD-TEXT                    PIC X(12).

PROCEDURE DIVISION.
MAIN-LINE.
    PERFORM INIT-ALL
    OPEN OUTPUT FRAME-FILE
    PERFORM VARYING FRAME-NO FROM 0 BY 1 UNTIL FRAME-NO >= END-FRAME
        COMPUTE NOW-T = FRAME-NO / 30
        PERFORM RUN-SCRIPT
        PERFORM UPDATE-EFFECTS
        IF FRAME-NO >= START-FRAME
            PERFORM RENDER-FRAME
            PERFORM EMIT-FRAME
        END-IF
    END-PERFORM
    CLOSE FRAME-FILE
    STOP RUN.

*> =====================================================================
*>  INITIALISATION
*> =====================================================================
INIT-ALL.
    COMPUTE DT = 1 / 30
    MOVE SPACES TO ENV-TEXT
    ACCEPT ENV-TEXT FROM ENVIRONMENT "DEMO_START"
    IF ENV-TEXT NOT = SPACES
        COMPUTE START-FRAME = FUNCTION NUMVAL(ENV-TEXT)
    END-IF
    MOVE TOTAL-FRAMES TO END-FRAME
    MOVE SPACES TO ENV-TEXT
    ACCEPT ENV-TEXT FROM ENVIRONMENT "DEMO_FRAMES"
    IF ENV-TEXT NOT = SPACES
        COMPUTE END-FRAME = START-FRAME + FUNCTION NUMVAL(ENV-TEXT)
        IF END-FRAME > TOTAL-FRAMES
            MOVE TOTAL-FRAMES TO END-FRAME
        END-IF
    END-IF
    PERFORM INIT-TABLES
    PERFORM BUILD-BASE-PALETTE
    PERFORM LOAD-MODELS
    PERFORM LOAD-SCRIPT
    PERFORM INIT-STARS
    PERFORM INIT-DUST
    PERFORM INIT-WORLD.

INIT-TABLES.
    PERFORM VARYING IX FROM 0 BY 1 UNTIL IX > 255
        MOVE IX TO BYTE-N
        MOVE BYTE-C TO IDENT-C(IX + 1)
        INSPECT FILL-ROW(IX + 1) REPLACING CHARACTERS BY BYTE-C
    END-PERFORM
    PERFORM VARYING IX FROM 0 BY 1 UNTIL IX > 4096
        COMPUTE A1 = IX * TWO-PI / 4096
        COMPUTE SIN-V(IX + 1) = FUNCTION SIN(A1)
    END-PERFORM
    PERFORM VARYING IX FROM 0 BY 1 UNTIL IX > 15
        COMPUTE A1 = IX * TWO-PI / 16
        COMPUTE DIR-C(IX + 1) = FUNCTION COS(A1)
        COMPUTE DIR-S(IX + 1) = FUNCTION SIN(A1)
    END-PERFORM
    PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > 32
        PERFORM NEXT-RANDOM
        COMPUTE JIT(IX) = 0.62 + RND * 0.38
    END-PERFORM
    PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > 256
        MOVE 0 TO GLYPH-IX(IX)
    END-PERFORM
    PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > NGLYPH
        MOVE GL-CHAR(IX) TO BYTE-C
        MOVE IX TO GLYPH-IX(BYTE-N + 1)
    END-PERFORM
    COMPUTE A1 = FOCAL * FOCAL + 160 * 160
    COMPUTE A1 = FUNCTION SQRT(A1)
    COMPUTE FR-KX = 1 / A1
    COMPUTE A1 = FOCAL * FOCAL + 112 * 112
    COMPUTE A1 = FUNCTION SQRT(A1)
    COMPUTE FR-KY = 1 / A1
    MOVE 0.55 TO VEC-X
    MOVE 0.50 TO VEC-Y
    MOVE -0.67 TO VEC-Z
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO SUN-X
    MOVE VEC-Y TO SUN-Y
    MOVE VEC-Z TO SUN-Z.

BUILD-BASE-PALETTE.
    PERFORM VARYING RI FROM 0 BY 1 UNTIL RI > 15
        PERFORM VARYING SI FROM 0 BY 1 UNTIL SI > 15
            COMPUTE KX = RI * 16 + SI + 1
            IF SI <= 10
                COMPUTE A1 = SI / 10
                COMPUTE BASE-R(KX) = RAMP-C(RI + 1, 1)
                    + (RAMP-C(RI + 1, 4) - RAMP-C(RI + 1, 1)) * A1
                COMPUTE BASE-G(KX) = RAMP-C(RI + 1, 2)
                    + (RAMP-C(RI + 1, 5) - RAMP-C(RI + 1, 2)) * A1
                COMPUTE BASE-B(KX) = RAMP-C(RI + 1, 3)
                    + (RAMP-C(RI + 1, 6) - RAMP-C(RI + 1, 3)) * A1
            ELSE
                COMPUTE A1 = (SI - 10) / 5
                COMPUTE BASE-R(KX) = RAMP-C(RI + 1, 4)
                    + (RAMP-C(RI + 1, 7) - RAMP-C(RI + 1, 4)) * A1
                COMPUTE BASE-G(KX) = RAMP-C(RI + 1, 5)
                    + (RAMP-C(RI + 1, 8) - RAMP-C(RI + 1, 5)) * A1
                COMPUTE BASE-B(KX) = RAMP-C(RI + 1, 6)
                    + (RAMP-C(RI + 1, 9) - RAMP-C(RI + 1, 6)) * A1
            END-IF
        END-PERFORM
    END-PERFORM.

*> ---------------------------------------------------------------------
*>  models.dat: M mesh, P part, V vertex, F face, G glow
*> ---------------------------------------------------------------------
LOAD-MODELS.
    OPEN INPUT MODEL-FILE
    IF MODEL-STATUS NOT = "00"
        DISPLAY "space: cannot open models.dat, status " MODEL-STATUS
            UPON SYSERR
        STOP RUN
    END-IF
    MOVE 0 TO MESH-COUNT VERT-COUNT FACE-COUNT PART-COUNT GLOW-COUNT
    MOVE 0 TO FILE-EOF
    PERFORM UNTIL FILE-EOF = 1
        READ MODEL-FILE
            AT END MOVE 1 TO FILE-EOF
            NOT AT END PERFORM LOAD-MODEL-RECORD
        END-READ
    END-PERFORM
    CLOSE MODEL-FILE
    PERFORM VARYING FI FROM 1 BY 1 UNTIL FI > FACE-COUNT
        PERFORM FACE-NORMAL
    END-PERFORM
    MOVE MESH-COUNT TO SHOW-1
    MOVE VERT-COUNT TO SHOW-2
    MOVE FACE-COUNT TO SHOW-3
    MOVE PART-COUNT TO SHOW-4
    DISPLAY "space: " FUNCTION TRIM(SHOW-1) " meshes, " FUNCTION TRIM(SHOW-2)
        " vertices, " FUNCTION TRIM(SHOW-3) " faces, " FUNCTION TRIM(SHOW-4)
        " parts" UPON SYSERR.

LOAD-MODEL-RECORD.
    EVALUATE MR-TYPE
        WHEN "M"
            ADD 1 TO MESH-COUNT
            MOVE VERT-COUNT TO MS-V0(MESH-COUNT)
            MOVE FACE-COUNT TO MS-F0(MESH-COUNT)
            MOVE PART-COUNT TO MS-P0(MESH-COUNT)
            MOVE GLOW-COUNT TO MS-G0(MESH-COUNT)
            MOVE 0 TO MS-NV(MESH-COUNT) MS-NF(MESH-COUNT)
            MOVE 0 TO MS-NP(MESH-COUNT) MS-NG(MESH-COUNT)
            COMPUTE MS-RAD(MESH-COUNT) = MR-FLD(2)
        WHEN "P"
            ADD 1 TO PART-COUNT
            ADD 1 TO MS-NP(MESH-COUNT)
            COMPUTE PA-CX(PART-COUNT) = MR-FLD(1)
            COMPUTE PA-CY(PART-COUNT) = MR-FLD(2)
            COMPUTE PA-CZ(PART-COUNT) = MR-FLD(3)
            COMPUTE PA-MOUNT(PART-COUNT) = MR-FLD(4)
            COMPUTE PA-NX(PART-COUNT) = MR-FLD(5)
            COMPUTE PA-NY(PART-COUNT) = MR-FLD(6)
            COMPUTE PA-NZ(PART-COUNT) = MR-FLD(7)
            COMPUTE PA-D(PART-COUNT) = MR-FLD(8)
        WHEN "V"
            ADD 1 TO VERT-COUNT
            ADD 1 TO MS-NV(MESH-COUNT)
            COMPUTE VX(VERT-COUNT) = MR-FLD(1)
            COMPUTE VY(VERT-COUNT) = MR-FLD(2)
            COMPUTE VZ(VERT-COUNT) = MR-FLD(3)
        WHEN "F"
            ADD 1 TO FACE-COUNT
            ADD 1 TO MS-NF(MESH-COUNT)
            COMPUTE FC-N(FACE-COUNT) = MR-FLD(1)
            PERFORM VARYING KX FROM 1 BY 1 UNTIL KX > 6
                IF KX <= FC-N(FACE-COUNT)
                    COMPUTE FC-V(FACE-COUNT, KX) =
                        MR-FLD(KX + 1) + MS-V0(MESH-COUNT)
                ELSE
                    MOVE 0 TO FC-V(FACE-COUNT, KX)
                END-IF
            END-PERFORM
            COMPUTE FC-RAMP(FACE-COUNT) = MR-FLD(8)
            COMPUTE FLAGS-W = MR-FLD(9)
            COMPUTE FC-PART(FACE-COUNT) = MR-FLD(10) + MS-P0(MESH-COUNT)
            COMPUTE FC-SHADE(FACE-COUNT) = MR-FLD(11)
            DIVIDE FLAGS-W BY 2 GIVING FLAGS-Q REMAINDER FC-EMIT(FACE-COUNT)
            DIVIDE FLAGS-Q BY 2 GIVING FLAGS-W REMAINDER FC-2SIDE(FACE-COUNT)
            MOVE FLAGS-W TO FC-CAP(FACE-COUNT)
        WHEN "G"
            ADD 1 TO GLOW-COUNT
            ADD 1 TO MS-NG(MESH-COUNT)
            COMPUTE GW-X(GLOW-COUNT) = MR-FLD(1)
            COMPUTE GW-Y(GLOW-COUNT) = MR-FLD(2)
            COMPUTE GW-Z(GLOW-COUNT) = MR-FLD(3)
            COMPUTE GW-SIZE(GLOW-COUNT) = MR-FLD(4)
            COMPUTE GW-RAMP(GLOW-COUNT) = MR-FLD(5)
            COMPUTE GW-SHADE(GLOW-COUNT) = MR-FLD(6)
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

*> Newell's method: robust normal of a planar polygon
FACE-NORMAL.
    MOVE 0 TO NX-ACC NY-ACC NZ-ACC
    PERFORM VARYING KX FROM 1 BY 1 UNTIL KX > FC-N(FI)
        MOVE FC-V(FI, KX) TO VA
        IF KX = FC-N(FI)
            MOVE FC-V(FI, 1) TO VB
        ELSE
            MOVE FC-V(FI, KX + 1) TO VB
        END-IF
        COMPUTE NX-ACC = NX-ACC + (VY(VA) - VY(VB)) * (VZ(VA) + VZ(VB))
        COMPUTE NY-ACC = NY-ACC + (VZ(VA) - VZ(VB)) * (VX(VA) + VX(VB))
        COMPUTE NZ-ACC = NZ-ACC + (VX(VA) - VX(VB)) * (VY(VA) + VY(VB))
    END-PERFORM
    MOVE NX-ACC TO VEC-X
    MOVE NY-ACC TO VEC-Y
    MOVE NZ-ACC TO VEC-Z
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO FC-NX(FI)
    MOVE VEC-Y TO FC-NY(FI)
    MOVE VEC-Z TO FC-NZ(FI).

*> ---------------------------------------------------------------------
*>  script.dat: free-form records split with UNSTRING
*>   K path time x y z [roll]
*>   B scene shooter target t0 count gap hit spread speed ramp boom
*>     [sx sy sz tx ty tz]
*>   X scene time object kill size [x y z]
*> ---------------------------------------------------------------------
LOAD-SCRIPT.
    OPEN INPUT SCRIPT-FILE
    IF SCRIPT-STATUS NOT = "00"
        DISPLAY "space: cannot open script.dat, status " SCRIPT-STATUS
            UPON SYSERR
        STOP RUN
    END-IF
    MOVE 0 TO KEY-COUNT BURST-COUNT BOOM-COUNT
    PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > MAX-PATH
        MOVE 0 TO PD-FIRST(IX) PD-COUNT(IX)
    END-PERFORM
    MOVE 0 TO FILE-EOF
    PERFORM UNTIL FILE-EOF = 1
        READ SCRIPT-FILE
            AT END MOVE 1 TO FILE-EOF
            NOT AT END PERFORM LOAD-SCRIPT-RECORD
        END-READ
    END-PERFORM
    CLOSE SCRIPT-FILE
    MOVE KEY-COUNT TO SHOW-1
    MOVE BURST-COUNT TO SHOW-2
    MOVE BOOM-COUNT TO SHOW-3
    DISPLAY "space: " FUNCTION TRIM(SHOW-1) " keyframes, " FUNCTION TRIM(SHOW-2)
        " laser bursts, " FUNCTION TRIM(SHOW-3) " explosions" UPON SYSERR.

LOAD-SCRIPT-RECORD.
    IF SCRIPT-REC(1:1) = "*" OR SCRIPT-REC = SPACES
        EXIT PARAGRAPH
    END-IF
    MOVE SPACES TO SCR-W
    MOVE 0 TO SW-N
    UNSTRING SCRIPT-REC DELIMITED BY ALL SPACE
        INTO SW(1) SW(2) SW(3) SW(4) SW(5) SW(6) SW(7) SW(8) SW(9)
             SW(10) SW(11) SW(12) SW(13) SW(14) SW(15) SW(16) SW(17) SW(18)
        TALLYING IN SW-N
    END-UNSTRING
    PERFORM VARYING IX FROM 2 BY 1 UNTIL IX > 18
        IF SW(IX) = SPACES
            MOVE 0 TO SV(IX)
        ELSE
            COMPUTE SV(IX) = FUNCTION NUMVAL(SW(IX))
        END-IF
    END-PERFORM
    EVALUATE SW(1)
        WHEN "K"
            ADD 1 TO KEY-COUNT
            COMPUTE KF-PATH(KEY-COUNT) = SV(2)
            MOVE SV(3) TO KF-T(KEY-COUNT)
            MOVE SV(4) TO KF-X(KEY-COUNT)
            MOVE SV(5) TO KF-Y(KEY-COUNT)
            MOVE SV(6) TO KF-Z(KEY-COUNT)
            MOVE SV(7) TO KF-ROLL(KEY-COUNT)
            MOVE KF-PATH(KEY-COUNT) TO IX
            IF PD-COUNT(IX) = 0
                MOVE KEY-COUNT TO PD-FIRST(IX)
            END-IF
            ADD 1 TO PD-COUNT(IX)
        WHEN "B"
            ADD 1 TO BURST-COUNT
            COMPUTE BU-SCENE(BURST-COUNT) = SV(2)
            COMPUTE BU-SHOOTER(BURST-COUNT) = SV(3)
            COMPUTE BU-TARGET(BURST-COUNT) = SV(4)
            MOVE SV(5) TO BU-T0(BURST-COUNT)
            COMPUTE BU-COUNT(BURST-COUNT) = SV(6)
            MOVE SV(7) TO BU-GAP(BURST-COUNT)
            COMPUTE BU-HIT(BURST-COUNT) = SV(8)
            MOVE SV(9) TO BU-SPREAD(BURST-COUNT)
            MOVE SV(10) TO BU-SPEED(BURST-COUNT)
            COMPUTE BU-RAMP(BURST-COUNT) = SV(11)
            MOVE SV(12) TO BU-BOOM(BURST-COUNT)
            MOVE SV(13) TO BU-SX(BURST-COUNT)
            MOVE SV(14) TO BU-SY(BURST-COUNT)
            MOVE SV(15) TO BU-SZ(BURST-COUNT)
            MOVE SV(16) TO BU-TX(BURST-COUNT)
            MOVE SV(17) TO BU-TY(BURST-COUNT)
            MOVE SV(18) TO BU-TZ(BURST-COUNT)
        WHEN "X"
            ADD 1 TO BOOM-COUNT
            COMPUTE BM-SCENE(BOOM-COUNT) = SV(2)
            MOVE SV(3) TO BM-T(BOOM-COUNT)
            COMPUTE BM-OBJ(BOOM-COUNT) = SV(4)
            COMPUTE BM-KILL(BOOM-COUNT) = SV(5)
            MOVE SV(6) TO BM-SIZE(BOOM-COUNT)
            MOVE SV(7) TO BM-X(BOOM-COUNT)
            MOVE SV(8) TO BM-Y(BOOM-COUNT)
            MOVE SV(9) TO BM-Z(BOOM-COUNT)
        WHEN OTHER
            CONTINUE
    END-EVALUATE.

INIT-STARS.
    PERFORM VARYING ST-I FROM 1 BY 1 UNTIL ST-I > MAX-STAR
        PERFORM NEXT-RANDOM
        COMPUTE A1 = RND * 2 - 1
        PERFORM NEXT-RANDOM
        COMPUTE A2 = RND * TWO-PI
        COMPUTE A3 = 1 - A1 * A1
        COMPUTE A3 = FUNCTION SQRT(A3)
        COMPUTE A4 = FUNCTION COS(A2)
        COMPUTE A5 = FUNCTION SIN(A2)
        COMPUTE SR-X(ST-I) = A3 * A4
        MOVE A1 TO SR-Y(ST-I)
        COMPUTE SR-Z(ST-I) = A3 * A5
        PERFORM NEXT-RANDOM
        COMPUTE MAGIC-D = RND * RND * 11 + 3.5 + MAGIC-K
        MOVE MAGIC-LO TO SR-COL(ST-I)
        PERFORM NEXT-RANDOM
        IF RND < 0.10
            ADD 192 TO SR-COL(ST-I)
        ELSE
            IF RND > 0.93
                ADD 240 TO SR-COL(ST-I)
            END-IF
        END-IF
    END-PERFORM.

INIT-DUST.
    PERFORM VARYING IX FROM 1 BY 1 UNTIL IX > MAX-DUST
        PERFORM NEXT-RANDOM
        COMPUTE DU-X(IX) = RND * 120 - 60
        PERFORM NEXT-RANDOM
        COMPUTE DU-Y(IX) = RND * 120 - 60
        PERFORM NEXT-RANDOM
        COMPUTE DU-Z(IX) = RND * 120 - 60
    END-PERFORM.

INIT-WORLD.
    MOVE LOW-VALUES TO OBJ-TAB
    MOVE LOW-VALUES TO PT-TAB
    MOVE LOW-VALUES TO LZ-TAB
    PERFORM VARYING OI FROM 1 BY 1 UNTIL OI > MAX-OBJ
        MOVE 1 TO OB-SCALE(OI)
        MOVE 4 TO OB-LAYER(OI)
        MOVE 1 TO OB-XX(OI)
        MOVE 1 TO OB-YY(OI)
        MOVE 1 TO OB-ZZ(OI)
    END-PERFORM
    *> the planet: a banded giant with rings, fixed in the sky
    MOVE 1 TO OI
    MOVE 1 TO OB-ACTIVE(OI)
    MOVE 5 TO OB-MESH(OI)
    MOVE 0 TO OB-LAYER(OI)
    MOVE 3000 TO OB-SCALE(OI)
    MOVE -6000 TO OB-PX(OI)
    MOVE -2000 TO OB-PY(OI)
    MOVE 13000 TO OB-PZ(OI)
    MOVE 0.25 TO OR-FX
    MOVE -0.42 TO OR-FY
    MOVE 1 TO OR-FZ
    MOVE 0.38 TO OR-ROLL
    PERFORM ORIENT-OBJECT
    PERFORM VARYING OI FROM 2 BY 1 UNTIL OI > 5
        MOVE 1 TO OB-MESH(OI)
    END-PERFORM
    PERFORM VARYING OI FROM 6 BY 1 UNTIL OI > 11
        MOVE 2 TO OB-MESH(OI)
    END-PERFORM
    MOVE 4 TO OB-MESH(12)
    MOVE 3 TO OB-MESH(13)
    MOVE 2 TO OB-LAYER(12)
    MOVE 2 TO OB-LAYER(13)
    PERFORM VARYING OI FROM 14 BY 1 UNTIL OI > 25
        COMPUTE OB-MESH(OI) = 6 + FUNCTION MOD(OI, 3)
    END-PERFORM.

*> =====================================================================
*>  SMALL MATHS
*> =====================================================================
NEXT-RANDOM.
    COMPUTE RNG-SEED = FUNCTION MOD(RNG-SEED * 1103515245 + 12345, 2147483648)
    COMPUTE RND = RNG-SEED / 2147483648.

NORMALIZE-VEC.
    COMPUTE VEC-L = VEC-X * VEC-X + VEC-Y * VEC-Y + VEC-Z * VEC-Z
    IF VEC-L > 1.0E-20
        COMPUTE VEC-L = FUNCTION SQRT(VEC-L)
        COMPUTE VEC-L = 1 / VEC-L
        COMPUTE VEC-X = VEC-X * VEC-L
        COMPUTE VEC-Y = VEC-Y * VEC-L
        COMPUTE VEC-Z = VEC-Z * VEC-L
    ELSE
        MOVE 0 TO VEC-X VEC-Y
        MOVE 1 TO VEC-Z
    END-IF.

*> sine and cosine of ANG (radians) from a 4096-entry table, interpolated
SINCOS.
    COMPUTE SC-TURN = ANG / TWO-PI
    COMPUTE MAGIC-D = SC-TURN - 0.5 + MAGIC-K
    COMPUTE SC-TURN = SC-TURN - MAGIC-LO
    COMPUTE SC-POS = SC-TURN * 4096
    COMPUTE MAGIC-D = SC-POS - 0.5 + MAGIC-K
    MOVE MAGIC-LO TO SC-I
    COMPUTE SC-FR = SC-POS - SC-I
    IF SC-I < 0
        ADD 4096 TO SC-I
    END-IF
    IF SC-I > 4095
        SUBTRACT 4096 FROM SC-I
    END-IF
    COMPUTE SN = SIN-V(SC-I + 1) + (SIN-V(SC-I + 2) - SIN-V(SC-I + 1)) * SC-FR
    COMPUTE SC-J = SC-I + 1024
    IF SC-J > 4095
        SUBTRACT 4096 FROM SC-J
    END-IF
    COMPUTE CS = SIN-V(SC-J + 1) + (SIN-V(SC-J + 2) - SIN-V(SC-J + 1)) * SC-FR.

*> world point (WX WY WZ) to camera space (CX CY CZ)
WORLD-TO-CAM.
    COMPUTE A4 = WX - CAM-PX
    COMPUTE A5 = WY - CAM-PY
    COMPUTE A6 = WZ - CAM-PZ
    COMPUTE CX = A4 * CAM-RX + A5 * CAM-RY + A6 * CAM-RZ
    COMPUTE CY = A4 * CAM-UX + A5 * CAM-UY + A6 * CAM-UZ
    COMPUTE CZ = A4 * CAM-FX + A5 * CAM-FY + A6 * CAM-FZ.

*> object OI axes from forward (OR-FX..) and roll (OR-ROLL); world up hint
ORIENT-OBJECT.
    MOVE OR-FX TO VEC-X
    MOVE OR-FY TO VEC-Y
    MOVE OR-FZ TO VEC-Z
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO OR-FX
    MOVE VEC-Y TO OR-FY
    MOVE VEC-Z TO OR-FZ
    MOVE OR-FZ TO VEC-X
    MOVE 0 TO VEC-Y
    COMPUTE VEC-Z = 0 - OR-FX
    IF VEC-X * VEC-X + VEC-Z * VEC-Z < 1.0E-8
        MOVE 1 TO VEC-X
        MOVE 0 TO VEC-Z
    END-IF
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO OR-RX
    MOVE VEC-Y TO OR-RY
    MOVE VEC-Z TO OR-RZ
    COMPUTE OR-UX = OR-FY * OR-RZ - OR-FZ * OR-RY
    COMPUTE OR-UY = OR-FZ * OR-RX - OR-FX * OR-RZ
    COMPUTE OR-UZ = OR-FX * OR-RY - OR-FY * OR-RX
    MOVE OR-ROLL TO ANG
    PERFORM SINCOS
    COMPUTE OB-XX(OI) = OR-RX * CS - OR-UX * SN
    COMPUTE OB-XY(OI) = OR-RY * CS - OR-UY * SN
    COMPUTE OB-XZ(OI) = OR-RZ * CS - OR-UZ * SN
    COMPUTE OB-YX(OI) = OR-UX * CS + OR-RX * SN
    COMPUTE OB-YY(OI) = OR-UY * CS + OR-RY * SN
    COMPUTE OB-YZ(OI) = OR-UZ * CS + OR-RZ * SN
    MOVE OR-FX TO OB-ZX(OI)
    MOVE OR-FY TO OB-ZY(OI)
    MOVE OR-FZ TO OB-ZZ(OI).

*> object OI local point (LX LY LZ) to world (WX WY WZ)
OBJ-TO-WORLD.
    COMPUTE WX = OB-PX(OI) + (OB-XX(OI) * LX + OB-YX(OI) * LY + OB-ZX(OI) * LZ) * OB-SCALE(OI)
    COMPUTE WY = OB-PY(OI) + (OB-XY(OI) * LX + OB-YY(OI) * LY + OB-ZY(OI) * LZ) * OB-SCALE(OI)
    COMPUTE WZ = OB-PZ(OI) + (OB-XZ(OI) * LX + OB-YZ(OI) * LY + OB-ZZ(OI) * LZ) * OB-SCALE(OI).

*> cruiser frame local point (LX LY LZ) to world (WX WY WZ)
CRUISER-TO-WORLD.
    COMPUTE WX = CR-QX + CR-XX * LX + CR-YX * LY + CR-ZX * LZ
    COMPUTE WY = CR-QY + CR-XY * LX + CR-YY * LY + CR-ZY * LZ
    COMPUTE WZ = CR-QZ + CR-XZ * LX + CR-YZ * LY + CR-ZZ * LZ.

*> =====================================================================
*>  FRAME OUTPUT
*> =====================================================================
BUILD-PALETTE.
    PERFORM VARYING KX FROM 1 BY 1 UNTIL KX > 256
        COMPUTE A1 = BASE-R(KX) * FX-FADE
        COMPUTE MAGIC-D = A1 + (255 - A1) * FX-FLASH + MAGIC-K
        MOVE MAGIC-LO TO BYTE-N
        MOVE BYTE-C TO PAL-R(KX)
        COMPUTE A1 = BASE-G(KX) * FX-FADE
        COMPUTE MAGIC-D = A1 + (255 - A1) * FX-FLASH + MAGIC-K
        MOVE MAGIC-LO TO BYTE-N
        MOVE BYTE-C TO PAL-G(KX)
        COMPUTE A1 = BASE-B(KX) * FX-FADE
        COMPUTE MAGIC-D = A1 + (255 - A1) * FX-FLASH + MAGIC-K
        MOVE MAGIC-LO TO BYTE-N
        MOVE BYTE-C TO PAL-B(KX)
    END-PERFORM.

*> palette lookup is INSPECT CONVERTING: one pass per colour plane
EMIT-FRAME.
    MOVE FB TO PLANE-G PLANE-B PLANE-R
    INSPECT PLANE-G CONVERTING IDENT-256 TO PAL-G-STR
    INSPECT PLANE-B CONVERTING IDENT-256 TO PAL-B-STR
    INSPECT PLANE-R CONVERTING IDENT-256 TO PAL-R-STR
    WRITE FRAME-REC.

*> =====================================================================
*>  RENDERING
*> =====================================================================
RENDER-FRAME.
    MOVE LOW-VALUES TO FB
    MOVE LOW-VALUES TO OT-TAB
    MOVE 0 TO PB-COUNT
    PERFORM DRAW-STARS
    PERFORM SUBMIT-SUN
    PERFORM VARYING OI FROM 1 BY 1 UNTIL OI > MAX-OBJ
        IF OB-ACTIVE(OI) = 1 AND OB-HIDE(OI) = 0
            PERFORM SUBMIT-OBJECT
        END-IF
    END-PERFORM
    PERFORM SUBMIT-PARTICLES
    PERFORM SUBMIT-LASERS
    IF DUST-ON = 1
        PERFORM SUBMIT-DUST
    END-IF
    PERFORM DRAW-OT
    IF HUD-ON = 1
        PERFORM DRAW-HUD
    END-IF
    PERFORM DRAW-TEXTS
    PERFORM BUILD-PALETTE.

BUILD-CAMERA.
    COMPUTE CAM-VX = CAM-PX - CAM-OLDX
    COMPUTE CAM-VY = CAM-PY - CAM-OLDY
    COMPUTE CAM-VZ = CAM-PZ - CAM-OLDZ
    COMPUTE A1 = CAM-VX * CAM-VX + CAM-VY * CAM-VY + CAM-VZ * CAM-VZ
    IF A1 > 900 OR FRAME-NO = START-FRAME
        MOVE 1 TO CAM-CUT
    ELSE
        MOVE 0 TO CAM-CUT
    END-IF
    MOVE CAM-PX TO CAM-OLDX
    MOVE CAM-PY TO CAM-OLDY
    MOVE CAM-PZ TO CAM-OLDZ
    COMPUTE VEC-X = CAM-TX - CAM-PX
    COMPUTE VEC-Y = CAM-TY - CAM-PY
    COMPUTE VEC-Z = CAM-TZ - CAM-PZ
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO CAM-FX
    MOVE VEC-Y TO CAM-FY
    MOVE VEC-Z TO CAM-FZ
    COMPUTE VEC-X = CAM-UPY * CAM-FZ - CAM-UPZ * CAM-FY
    COMPUTE VEC-Y = CAM-UPZ * CAM-FX - CAM-UPX * CAM-FZ
    COMPUTE VEC-Z = CAM-UPX * CAM-FY - CAM-UPY * CAM-FX
    PERFORM NORMALIZE-VEC
    MOVE VEC-X TO CAM-RX
    MOVE VEC-Y TO CAM-RY
    MOVE VEC-Z TO CAM-RZ
    COMPUTE CAM-UX = CAM-FY * CAM-RZ - CAM-FZ * CAM-RY
    COMPUTE CAM-UY = CAM-FZ * CAM-RX - CAM-FX * CAM-RZ
    COMPUTE CAM-UZ = CAM-FX * CAM-RY - CAM-FY * CAM-RX
    IF CAM-ROLL NOT = 0
        MOVE CAM-ROLL TO ANG
        PERFORM SINCOS
        COMPUTE A1 = CAM-RX * CS - CAM-UX * SN
        COMPUTE A2 = CAM-RY * CS - CAM-UY * SN
        COMPUTE A3 = CAM-RZ * CS - CAM-UZ * SN
        COMPUTE CAM-UX = CAM-UX * CS + CAM-RX * SN
        COMPUTE CAM-UY = CAM-UY * CS + CAM-RY * SN
        COMPUTE CAM-UZ = CAM-UZ * CS + CAM-RZ * SN
        MOVE A1 TO CAM-RX
        MOVE A2 TO CAM-RY
        MOVE A3 TO CAM-RZ
    END-IF.

*> stars sit at infinity: only the camera's rotation moves them
DRAW-STARS.
    PERFORM VARYING ST-I FROM 1 BY 1 UNTIL ST-I > MAX-STAR
        COMPUTE ST-Z = SR-X(ST-I) * CAM-FX + SR-Y(ST-I) * CAM-FY
            + SR-Z(ST-I) * CAM-FZ
        IF ST-Z > 0.3
            COMPUTE ST-K = FOCAL / ST-Z
            COMPUTE MAGIC-D = 159.5 + (SR-X(ST-I) * CAM-RX + SR-Y(ST-I) * CAM-RY
                + SR-Z(ST-I) * CAM-RZ) * ST-K + MAGIC-K
            MOVE MAGIC-LO TO ST-SX
            COMPUTE MAGIC-D = 111.5 - (SR-X(ST-I) * CAM-UX + SR-Y(ST-I) * CAM-UY
                + SR-Z(ST-I) * CAM-UZ) * ST-K + MAGIC-K
            MOVE MAGIC-LO TO ST-SY
            IF ST-SX >= 0 AND ST-SX < 320 AND ST-SY >= 0 AND ST-SY < 224
                COMPUTE ST-OFF = ST-SY * 320 + ST-SX + 1
                MOVE FILL-ROW(SR-COL(ST-I) + 1)(1:1) TO FB(ST-OFF:1)
            END-IF
        END-IF
    END-PERFORM.

SUBMIT-SUN.
    COMPUTE A1 = SUN-X * CAM-FX + SUN-Y * CAM-FY + SUN-Z * CAM-FZ
    IF A1 > 0.25
        COMPUTE A2 = FOCAL / A1
        COMPUTE SPR-CX = 160 + (SUN-X * CAM-RX + SUN-Y * CAM-RY + SUN-Z * CAM-RZ) * A2
        COMPUTE SPR-CY = 112 - (SUN-X * CAM-UX + SUN-Y * CAM-UY + SUN-Z * CAM-UZ) * A2
        MOVE 0 TO OT-LAYER
        MOVE 1.0E7 TO OT-Z
        MOVE 1 TO SPR-SEED
        MOVE 16 TO SPR-NV
        MOVE 0.08 TO SPR-JAMT
        MOVE 0 TO SPR-MESH
        MOVE 6 TO SPR-R
        MOVE 207 TO SPR-COL
        PERFORM SUBMIT-SPRITE
        MOVE 1 TO SPR-MESH
        MOVE 10 TO SPR-R
        MOVE 204 TO SPR-COL
        PERFORM SUBMIT-SPRITE
        MOVE 8 TO SPR-NV
        MOVE 0.3 TO SPR-SPIKE
        MOVE 26 TO SPR-R
        MOVE 196 TO SPR-COL
        PERFORM SUBMIT-SPRITE
    END-IF.

*> ---------------------------------------------------------------------
*>  objects: transform, cull, light, clip and queue every visible face
*> ---------------------------------------------------------------------
SUBMIT-OBJECT.
    MOVE OB-MESH(OI) TO SO-MI
    MOVE MS-V0(SO-MI) TO SO-V0
    MOVE OB-SCALE(OI) TO SO-S
    COMPUTE SO-DX = OB-PX(OI) - CAM-PX
    COMPUTE SO-DY = OB-PY(OI) - CAM-PY
    COMPUTE SO-DZ = OB-PZ(OI) - CAM-PZ
    COMPUTE SO-TX = SO-DX * CAM-RX + SO-DY * CAM-RY + SO-DZ * CAM-RZ
    COMPUTE SO-TY = SO-DX * CAM-UX + SO-DY * CAM-UY + SO-DZ * CAM-UZ
    COMPUTE SO-TZ = SO-DX * CAM-FX + SO-DY * CAM-FY + SO-DZ * CAM-FZ
    COMPUTE SO-RAD = MS-RAD(SO-MI) * SO-S
    IF SO-TZ + SO-RAD < ZNEAR OR SO-TZ - SO-RAD > ZFAR
        EXIT PARAGRAPH
    END-IF
    IF (FOCAL * SO-TX - 160 * SO-TZ) * FR-KX > SO-RAD
        EXIT PARAGRAPH
    END-IF
    IF (0 - FOCAL * SO-TX - 160 * SO-TZ) * FR-KX > SO-RAD
        EXIT PARAGRAPH
    END-IF
    IF (FOCAL * SO-TY - 112 * SO-TZ) * FR-KY > SO-RAD
        EXIT PARAGRAPH
    END-IF
    IF (0 - FOCAL * SO-TY - 112 * SO-TZ) * FR-KY > SO-RAD
        EXIT PARAGRAPH
    END-IF
    COMPUTE SO-M11 = (CAM-RX * OB-XX(OI) + CAM-RY * OB-XY(OI) + CAM-RZ * OB-XZ(OI)) * SO-S
    COMPUTE SO-M12 = (CAM-RX * OB-YX(OI) + CAM-RY * OB-YY(OI) + CAM-RZ * OB-YZ(OI)) * SO-S
    COMPUTE SO-M13 = (CAM-RX * OB-ZX(OI) + CAM-RY * OB-ZY(OI) + CAM-RZ * OB-ZZ(OI)) * SO-S
    COMPUTE SO-M21 = (CAM-UX * OB-XX(OI) + CAM-UY * OB-XY(OI) + CAM-UZ * OB-XZ(OI)) * SO-S
    COMPUTE SO-M22 = (CAM-UX * OB-YX(OI) + CAM-UY * OB-YY(OI) + CAM-UZ * OB-YZ(OI)) * SO-S
    COMPUTE SO-M23 = (CAM-UX * OB-ZX(OI) + CAM-UY * OB-ZY(OI) + CAM-UZ * OB-ZZ(OI)) * SO-S
    COMPUTE SO-M31 = (CAM-FX * OB-XX(OI) + CAM-FY * OB-XY(OI) + CAM-FZ * OB-XZ(OI)) * SO-S
    COMPUTE SO-M32 = (CAM-FX * OB-YX(OI) + CAM-FY * OB-YY(OI) + CAM-FZ * OB-YZ(OI)) * SO-S
    COMPUTE SO-M33 = (CAM-FX * OB-ZX(OI) + CAM-FY * OB-ZY(OI) + CAM-FZ * OB-ZZ(OI)) * SO-S
    *> the camera and the sun in the object's own coordinates
    COMPUTE SO-CLX = (0 - SO-DX * OB-XX(OI) - SO-DY * OB-XY(OI) - SO-DZ * OB-XZ(OI)) / SO-S
    COMPUTE SO-CLY = (0 - SO-DX * OB-YX(OI) - SO-DY * OB-YY(OI) - SO-DZ * OB-YZ(OI)) / SO-S
    COMPUTE SO-CLZ = (0 - SO-DX * OB-ZX(OI) - SO-DY * OB-ZY(OI) - SO-DZ * OB-ZZ(OI)) / SO-S
    COMPUTE SO-LLX = SUN-X * OB-XX(OI) + SUN-Y * OB-XY(OI) + SUN-Z * OB-XZ(OI)
    COMPUTE SO-LLY = SUN-X * OB-YX(OI) + SUN-Y * OB-YY(OI) + SUN-Z * OB-YZ(OI)
    COMPUTE SO-LLZ = SUN-X * OB-ZX(OI) + SUN-Y * OB-ZY(OI) + SUN-Z * OB-ZZ(OI)
    COMPUTE SO-FLICK = FUNCTION MOD(FRAME-NO + OI, 3) - 1
    PERFORM VARYING SO-I FROM 1 BY 1 UNTIL SO-I > MS-NV(SO-MI)
        COMPUTE GV = SO-V0 + SO-I
        COMPUTE TV-X(SO-I) = SO-M11 * VX(GV) + SO-M12 * VY(GV) + SO-M13 * VZ(GV) + SO-TX
        COMPUTE TV-Y(SO-I) = SO-M21 * VX(GV) + SO-M22 * VY(GV) + SO-M23 * VZ(GV) + SO-TY
        COMPUTE TV-Z(SO-I) = SO-M31 * VX(GV) + SO-M32 * VY(GV) + SO-M33 * VZ(GV) + SO-TZ
        IF TV-Z(SO-I) >= ZNEAR
            COMPUTE SO-RZ = FOCAL / TV-Z(SO-I)
            COMPUTE TV-SX(SO-I) = 160 + TV-X(SO-I) * SO-RZ
            COMPUTE TV-SY(SO-I) = 112 - TV-Y(SO-I) * SO-RZ
        END-IF
    END-PERFORM
    *> each part gets one depth (its centre) and a layer from its mount plane
    PERFORM VARYING SO-I FROM 1 BY 1 UNTIL SO-I > MS-NP(SO-MI)
        COMPUTE SO-G = MS-P0(SO-MI) + SO-I
        COMPUTE PW-Z(SO-G) = SO-M31 * PA-CX(SO-G) + SO-M32 * PA-CY(SO-G)
            + SO-M33 * PA-CZ(SO-G) + SO-TZ
        IF PA-MOUNT(SO-G) = 1
            COMPUTE A1 = PA-NX(SO-G) * SO-CLX + PA-NY(SO-G) * SO-CLY
                + PA-NZ(SO-G) * SO-CLZ - PA-D(SO-G)
            IF A1 > 0
                COMPUTE PW-LAYER(SO-G) = OB-LAYER(OI) + 1
            ELSE
                COMPUTE PW-LAYER(SO-G) = OB-LAYER(OI) - 1
            END-IF
        ELSE
            MOVE OB-LAYER(OI) TO PW-LAYER(SO-G)
        END-IF
    END-PERFORM
    PERFORM VARYING SO-I FROM 1 BY 1 UNTIL SO-I > MS-NF(SO-MI)
        COMPUTE GF = MS-F0(SO-MI) + SO-I
        PERFORM SUBMIT-FACE
    END-PERFORM
    PERFORM VARYING SO-I FROM 1 BY 1 UNTIL SO-I > MS-NG(SO-MI)
        COMPUTE SO-G = MS-G0(SO-MI) + SO-I
        PERFORM SUBMIT-GLOW
    END-PERFORM.

SUBMIT-FACE.
    IF FC-CAP(GF) = 1 AND OB-BROKEN(OI) = 0
        EXIT PARAGRAPH
    END-IF
    MOVE FC-V(GF, 1) TO GV
    COMPUTE SF-VIS = FC-NX(GF) * (SO-CLX - VX(GV)) + FC-NY(GF) * (SO-CLY - VY(GV))
        + FC-NZ(GF) * (SO-CLZ - VZ(GV))
    IF SF-VIS <= 0 AND FC-2SIDE(GF) = 0
        EXIT PARAGRAPH
    END-IF
    MOVE FC-N(GF) TO CL-N
    MOVE 0 TO SF-BEHIND
    PERFORM VARYING SF-K FROM 1 BY 1 UNTIL SF-K > CL-N
        COMPUTE SF-LV = FC-V(GF, SF-K) - SO-V0
        MOVE TV-X(SF-LV) TO CL-X(SF-K)
        MOVE TV-Y(SF-LV) TO CL-Y(SF-K)
        MOVE TV-Z(SF-LV) TO CL-Z(SF-K)
        MOVE TV-SX(SF-LV) TO CL-SX(SF-K)
        MOVE TV-SY(SF-LV) TO CL-SY(SF-K)
        IF TV-Z(SF-LV) < ZNEAR
            ADD 1 TO SF-BEHIND
        END-IF
    END-PERFORM
    IF SF-BEHIND = CL-N
        EXIT PARAGRAPH
    END-IF
    IF FC-EMIT(GF) = 1
        COMPUTE SF-SHADE = FC-SHADE(GF) + SO-FLICK
    ELSE
        COMPUTE SF-L = FC-NX(GF) * SO-LLX + FC-NY(GF) * SO-LLY + FC-NZ(GF) * SO-LLZ
        IF SF-VIS < 0
            COMPUTE SF-L = 0 - SF-L
        END-IF
        IF SF-L < 0
            MOVE 0 TO SF-L
        END-IF
        COMPUTE MAGIC-D = AMBIENT + DIFFUSE * SF-L + MAGIC-K
        MOVE MAGIC-LO TO SF-SHADE
    END-IF
    IF SF-SHADE < 0
        MOVE 0 TO SF-SHADE
    END-IF
    IF SF-SHADE > 15
        MOVE 15 TO SF-SHADE
    END-IF
    COMPUTE SF-COL = FC-RAMP(GF) * 16 + SF-SHADE
    IF PB-COUNT >= MAX-PB
        EXIT PARAGRAPH
    END-IF
    ADD 1 TO PB-COUNT
    MOVE PB-COUNT TO NEW-PB
    IF SF-BEHIND = 0
        MOVE CL-N TO PB-N(NEW-PB)
        PERFORM VARYING SF-K FROM 1 BY 1 UNTIL SF-K > CL-N
            MOVE CL-SX(SF-K) TO PB-X(NEW-PB, SF-K)
            MOVE CL-SY(SF-K) TO PB-Y(NEW-PB, SF-K)
        END-PERFORM
    ELSE
        PERFORM CLIP-NEAR
        IF PB-N(NEW-PB) < 3
            SUBTRACT 1 FROM PB-COUNT
            EXIT PARAGRAPH
        END-IF
    END-IF
    MOVE 1 TO PB-TYPE(NEW-PB)
    MOVE 0 TO PB-MESH(NEW-PB)
    MOVE SF-COL TO PB-COL(NEW-PB)
    MOVE FC-PART(GF) TO SF-P
    MOVE PW-Z(SF-P) TO OT-Z
    MOVE PW-LAYER(SF-P) TO OT-LAYER
    PERFORM OT-INSERT.

*> Sutherland-Hodgman against the near plane, projecting as it goes
CLIP-NEAR.
    MOVE 0 TO CP-OUT
    MOVE CL-N TO CP-PREV
    PERFORM VARYING CP-K FROM 1 BY 1 UNTIL CP-K > CL-N
        IF CL-Z(CP-K) >= ZNEAR
            IF CL-Z(CP-PREV) < ZNEAR
                PERFORM CLIP-CROSSING
            END-IF
            ADD 1 TO CP-OUT
            MOVE CL-SX(CP-K) TO PB-X(NEW-PB, CP-OUT)
            MOVE CL-SY(CP-K) TO PB-Y(NEW-PB, CP-OUT)
        ELSE
            IF CL-Z(CP-PREV) >= ZNEAR
                PERFORM CLIP-CROSSING
            END-IF
        END-IF
        MOVE CP-K TO CP-PREV
    END-PERFORM
    MOVE CP-OUT TO PB-N(NEW-PB).

CLIP-CROSSING.
    COMPUTE CP-T = (ZNEAR - CL-Z(CP-PREV)) / (CL-Z(CP-K) - CL-Z(CP-PREV))
    COMPUTE CP-X = CL-X(CP-PREV) + (CL-X(CP-K) - CL-X(CP-PREV)) * CP-T
    COMPUTE CP-Y = CL-Y(CP-PREV) + (CL-Y(CP-K) - CL-Y(CP-PREV)) * CP-T
    ADD 1 TO CP-OUT
    COMPUTE PB-X(NEW-PB, CP-OUT) = 160 + CP-X * FOCAL / ZNEAR
    COMPUTE PB-Y(NEW-PB, CP-OUT) = 112 - CP-Y * FOCAL / ZNEAR.

*> engine glow: a sprite behind the nozzle, seen only from behind
SUBMIT-GLOW.
    IF SO-CLZ > GW-Z(SO-G) + GW-SIZE(SO-G)
        EXIT PARAGRAPH
    END-IF
    COMPUTE CX = SO-M11 * GW-X(SO-G) + SO-M12 * GW-Y(SO-G) + SO-M13 * GW-Z(SO-G) + SO-TX
    COMPUTE CY = SO-M21 * GW-X(SO-G) + SO-M22 * GW-Y(SO-G) + SO-M23 * GW-Z(SO-G) + SO-TY
    COMPUTE CZ = SO-M31 * GW-X(SO-G) + SO-M32 * GW-Y(SO-G) + SO-M33 * GW-Z(SO-G) + SO-TZ
    IF CZ < ZNEAR + 0.2
        EXIT PARAGRAPH
    END-IF
    COMPUTE A1 = FOCAL / CZ
    COMPUTE SPR-CX = 160 + CX * A1
    COMPUTE SPR-CY = 112 - CY * A1
    COMPUTE SPR-R = GW-SIZE(SO-G) * SO-S * A1 * 0.7
    IF SPR-R < 0.6
        MOVE 0.6 TO SPR-R
    END-IF
    COMPUTE SPR-SEED = FRAME-NO + SO-G
    MOVE 4 TO OT-LAYER
    COMPUTE OT-Z = CZ - 0.05
    MOVE 16 TO SPR-NV
    MOVE 0.25 TO SPR-JAMT
    MOVE 0 TO SPR-MESH
    COMPUTE SPR-COL = GW-RAMP(SO-G) * 16 + 15
    PERFORM SUBMIT-SPRITE
    IF SPR-R > 1.5
        COMPUTE SPR-R = SPR-R * 1.9
        MOVE 1 TO SPR-MESH
        COMPUTE SPR-COL = GW-RAMP(SO-G) * 16 + GW-SHADE(SO-G) - 2 + SO-FLICK
        PERFORM SUBMIT-SPRITE
    END-IF.

*> a screen-facing polygon at SPR-CX/CY, radius SPR-R: SPR-NV 8 gives a
*> star (alternate points at SPR-SPIKE), 16 a ragged blob (SPR-JAMT),
*> SPR-MESH 1 draws it as a checkerboard
SUBMIT-SPRITE.
    IF SPR-CX + SPR-R < 0 OR SPR-CX - SPR-R > 320
        EXIT PARAGRAPH
    END-IF
    IF SPR-CY + SPR-R < 0 OR SPR-CY - SPR-R > 224
        EXIT PARAGRAPH
    END-IF
    IF PB-COUNT >= MAX-PB
        EXIT PARAGRAPH
    END-IF
    ADD 1 TO PB-COUNT
    MOVE PB-COUNT TO NEW-PB
    MOVE 1 TO PB-TYPE(NEW-PB)
    MOVE SPR-COL TO PB-COL(NEW-PB)
    MOVE SPR-MESH TO PB-MESH(NEW-PB)
    IF SPR-NV = 16
        MOVE 16 TO PB-N(NEW-PB)
        PERFORM VARYING SPR-K FROM 1 BY 1 UNTIL SPR-K > 16
            COMPUTE IX = FUNCTION MOD(SPR-K + SPR-SEED, 16) + 1
            COMPUTE JX = FUNCTION MOD(SPR-SEED * 7 + SPR-K * 5, 32) + 1
            COMPUTE SPR-A = SPR-R * (1 - SPR-JAMT + SPR-JAMT * JIT(JX))
            COMPUTE PB-X(NEW-PB, SPR-K) = SPR-CX + DIR-C(IX) * SPR-A
            COMPUTE PB-Y(NEW-PB, SPR-K) = SPR-CY - DIR-S(IX) * SPR-A
        END-PERFORM
    ELSE
        MOVE 8 TO PB-N(NEW-PB)
        COMPUTE SPR-D = FUNCTION MOD(SPR-SEED, 2)
        PERFORM VARYING SPR-K FROM 1 BY 1 UNTIL SPR-K > 8
            COMPUTE IX = (SPR-K - 1) * 2 + SPR-D + 1
            IF IX > 16
                SUBTRACT 16 FROM IX
            END-IF
            COMPUTE JX = FUNCTION MOD(SPR-SEED * 7 + SPR-K * 5, 32) + 1
            IF FUNCTION MOD(SPR-K, 2) = 0
                COMPUTE SPR-A = SPR-R * SPR-SPIKE * JIT(JX)
            ELSE
                COMPUTE SPR-A = SPR-R * (0.5 + JIT(JX) * 0.5)
            END-IF
            COMPUTE PB-X(NEW-PB, SPR-K) = SPR-CX + DIR-C(IX) * SPR-A
            COMPUTE PB-Y(NEW-PB, SPR-K) = SPR-CY - DIR-S(IX) * SPR-A
        END-PERFORM
    END-IF
    PERFORM OT-INSERT.

*> one new polygon or line (NEW-PB) into the ordering table at OT-Z
OT-INSERT.
    IF OT-Z < 0.05
        MOVE 0.05 TO OT-Z
    END-IF
    COMPUTE MAGIC-D = 4095 * OT-Z / (OT-Z + 300) + MAGIC-K
    MOVE MAGIC-LO TO OT-B
    IF OT-B > 4095
        MOVE 4095 TO OT-B
    END-IF
    IF OT-B < 0
        MOVE 0 TO OT-B
    END-IF
    COMPUTE OT-I = OT-LAYER * 4096 + OT-B + 1
    MOVE OT-HEAD(OT-I) TO PB-NEXT(NEW-PB)
    MOVE NEW-PB TO OT-HEAD(OT-I).

*> back to front: layer by layer, far bucket to near bucket
DRAW-OT.
    PERFORM VARYING DO-L FROM 0 BY 1 UNTIL DO-L > 5
        PERFORM VARYING DO-B FROM 4095 BY -1 UNTIL DO-B < 0
            COMPUTE OT-I = DO-L * 4096 + DO-B + 1
            MOVE OT-HEAD(OT-I) TO DO-P
            PERFORM UNTIL DO-P = 0
                PERFORM DRAW-PB
                MOVE PB-NEXT(DO-P) TO DO-P
            END-PERFORM
        END-PERFORM
    END-PERFORM.

DRAW-PB.
    IF PB-TYPE(DO-P) = 1
        MOVE PB-N(DO-P) TO RP-N
        PERFORM VARYING DO-K FROM 1 BY 1 UNTIL DO-K > RP-N
            MOVE PB-X(DO-P, DO-K) TO RP-X(DO-K)
            MOVE PB-Y(DO-P, DO-K) TO RP-Y(DO-K)
        END-PERFORM
        MOVE PB-COL(DO-P) TO RP-COL
        MOVE PB-MESH(DO-P) TO RP-MESH
        PERFORM RASTER-POLY
    ELSE
        MOVE PB-X(DO-P, 1) TO LN-X1
        MOVE PB-Y(DO-P, 1) TO LN-Y1
        MOVE PB-X(DO-P, 2) TO LN-X2
        MOVE PB-Y(DO-P, 2) TO LN-Y2
        MOVE PB-COL(DO-P) TO LN-COL
        MOVE PB-N(DO-P) TO LN-W
        PERFORM DRAW-LINE
        IF PB-COL2(DO-P) > 0
            MOVE PB-X(DO-P, 1) TO LN-X1
            MOVE PB-Y(DO-P, 1) TO LN-Y1
            MOVE PB-X(DO-P, 2) TO LN-X2
            MOVE PB-Y(DO-P, 2) TO LN-Y2
            MOVE PB-COL2(DO-P) TO LN-COL
            MOVE 1 TO LN-W
            PERFORM DRAW-LINE
        END-IF
    END-IF.

*> ---------------------------------------------------------------------
*>  convex polygon fill: walk every edge into per-row left/right limits,
*>  then each row is one MOVE from a row of that colour
*> ---------------------------------------------------------------------
RASTER-POLY.
    MOVE RP-Y(1) TO RS-YMIN RS-YMAX
    MOVE RP-X(1) TO RS-XMIN RS-XMAX
    PERFORM VARYING RS-K FROM 2 BY 1 UNTIL RS-K > RP-N
        IF RP-Y(RS-K) < RS-YMIN
            MOVE RP-Y(RS-K) TO RS-YMIN
        END-IF
        IF RP-Y(RS-K) > RS-YMAX
            MOVE RP-Y(RS-K) TO RS-YMAX
        END-IF
        IF RP-X(RS-K) < RS-XMIN
            MOVE RP-X(RS-K) TO RS-XMIN
        END-IF
        IF RP-X(RS-K) > RS-XMAX
            MOVE RP-X(RS-K) TO RS-XMAX
        END-IF
    END-PERFORM
    IF RS-YMAX <= 0 OR RS-YMIN >= 224 OR RS-XMAX <= 0 OR RS-XMIN >= 320
        EXIT PARAGRAPH
    END-IF
    IF RS-YMIN < -1
        MOVE -1 TO RS-YMIN
    END-IF
    IF RS-YMAX > 225
        MOVE 225 TO RS-YMAX
    END-IF
    COMPUTE MAGIC-D = RS-YMIN + MAGIC-K
    MOVE MAGIC-LO TO RS-J0
    COMPUTE MAGIC-D = RS-YMAX + MAGIC-K
    COMPUTE RS-J1 = MAGIC-LO - 1
    IF RS-J0 < 0
        MOVE 0 TO RS-J0
    END-IF
    IF RS-J1 > 223
        MOVE 223 TO RS-J1
    END-IF
    IF RS-J0 > RS-J1
        EXIT PARAGRAPH
    END-IF
    PERFORM VARYING RS-J FROM RS-J0 BY 1 UNTIL RS-J > RS-J1
        MOVE BIG-POS TO XL(RS-J + 1)
        MOVE BIG-NEG TO XR(RS-J + 1)
    END-PERFORM
    PERFORM VARYING RS-K FROM 1 BY 1 UNTIL RS-K > RP-N
        IF RS-K = RP-N
            MOVE 1 TO RS-K2
        ELSE
            COMPUTE RS-K2 = RS-K + 1
        END-IF
        IF RP-Y(RS-K) <= RP-Y(RS-K2)
            MOVE RP-X(RS-K) TO RS-EX1
            MOVE RP-Y(RS-K) TO RS-EY1
            MOVE RP-X(RS-K2) TO RS-EX2
            MOVE RP-Y(RS-K2) TO RS-EY2
        ELSE
            MOVE RP-X(RS-K2) TO RS-EX1
            MOVE RP-Y(RS-K2) TO RS-EY1
            MOVE RP-X(RS-K) TO RS-EX2
            MOVE RP-Y(RS-K) TO RS-EY2
        END-IF
        IF RS-EY2 - RS-EY1 > 1.0E-9
            IF RS-EY1 < -1
                COMPUTE MAGIC-D = -1 + MAGIC-K
            ELSE
                COMPUTE MAGIC-D = RS-EY1 + MAGIC-K
            END-IF
            MOVE MAGIC-LO TO RS-JA
            IF RS-EY2 > 225
                COMPUTE MAGIC-D = 225 + MAGIC-K
            ELSE
                COMPUTE MAGIC-D = RS-EY2 + MAGIC-K
            END-IF
            COMPUTE RS-JB = MAGIC-LO - 1
            IF RS-JA < RS-J0
                MOVE RS-J0 TO RS-JA
            END-IF
            IF RS-JB > RS-J1
                MOVE RS-J1 TO RS-JB
            END-IF
            IF RS-JA <= RS-JB
                COMPUTE RS-SLOPE = (RS-EX2 - RS-EX1) / (RS-EY2 - RS-EY1)
                COMPUTE RS-XC = RS-EX1 + (RS-JA + 0.5 - RS-EY1) * RS-SLOPE
                PERFORM VARYING RS-J FROM RS-JA BY 1 UNTIL RS-J > RS-JB
                    IF RS-XC < XL(RS-J + 1)
                        MOVE RS-XC TO XL(RS-J + 1)
                    END-IF
                    IF RS-XC > XR(RS-J + 1)
                        MOVE RS-XC TO XR(RS-J + 1)
                    END-IF
                    ADD RS-SLOPE TO RS-XC
                END-PERFORM
            END-IF
        END-IF
    END-PERFORM
    COMPUTE RS-ROW = RS-J0 * 320 + 1
    PERFORM VARYING RS-J FROM RS-J0 BY 1 UNTIL RS-J > RS-J1
        IF XR(RS-J + 1) > XL(RS-J + 1)
            IF XL(RS-J + 1) < -1
                MOVE 0 TO RS-XS
            ELSE
                COMPUTE MAGIC-D = XL(RS-J + 1) + MAGIC-K
                MOVE MAGIC-LO TO RS-XS
            END-IF
            IF XR(RS-J + 1) > 321
                MOVE 319 TO RS-XE
            ELSE
                COMPUTE MAGIC-D = XR(RS-J + 1) + MAGIC-K
                COMPUTE RS-XE = MAGIC-LO - 1
            END-IF
            IF RS-XS < 0
                MOVE 0 TO RS-XS
            END-IF
            IF RS-XE > 319
                MOVE 319 TO RS-XE
            END-IF
            IF RS-XS <= RS-XE
                IF RP-MESH = 0
                    COMPUTE RS-SPAN = RS-XE - RS-XS + 1
                    COMPUTE RS-OFF = RS-ROW + RS-XS
                    MOVE FILL-ROW(RP-COL + 1)(1:RS-SPAN) TO FB(RS-OFF:RS-SPAN)
                ELSE
                    *> mesh transparency: every other pixel, checkerboard
                    IF FUNCTION MOD(RS-XS + RS-J, 2) = 1
                        ADD 1 TO RS-XS
                    END-IF
                    COMPUTE RS-OFF = RS-ROW + RS-XS
                    PERFORM VARYING RS-XS FROM RS-XS BY 2 UNTIL RS-XS > RS-XE
                        MOVE FILL-ROW(RP-COL + 1)(1:1) TO FB(RS-OFF:1)
                        ADD 2 TO RS-OFF
                    END-PERFORM
                END-IF
            END-IF
        END-IF
        ADD 320 TO RS-ROW
    END-PERFORM.

*> ---------------------------------------------------------------------
*>  lines: Liang-Barsky clip to the screen, then a DDA of square dots
*> ---------------------------------------------------------------------
DRAW-LINE.
    COMPUTE LN-DX = LN-X2 - LN-X1
    COMPUTE LN-DY = LN-Y2 - LN-Y1
    MOVE 0 TO LN-T0
    MOVE 1 TO LN-T1
    MOVE 0 TO LN-REJECT
    COMPUTE LN-P = 0 - LN-DX
    COMPUTE LN-Q = LN-X1 + 2
    PERFORM LINE-CLIP-EDGE
    MOVE LN-DX TO LN-P
    COMPUTE LN-Q = 322 - LN-X1
    PERFORM LINE-CLIP-EDGE
    COMPUTE LN-P = 0 - LN-DY
    COMPUTE LN-Q = LN-Y1 + 2
    PERFORM LINE-CLIP-EDGE
    MOVE LN-DY TO LN-P
    COMPUTE LN-Q = 226 - LN-Y1
    PERFORM LINE-CLIP-EDGE
    IF LN-REJECT = 1
        EXIT PARAGRAPH
    END-IF
    COMPUTE LN-AX = LN-X1 + LN-DX * LN-T0
    COMPUTE LN-AY = LN-Y1 + LN-DY * LN-T0
    COMPUTE LN-DX = LN-DX * (LN-T1 - LN-T0)
    COMPUTE LN-DY = LN-DY * (LN-T1 - LN-T0)
    IF LN-DX < 0
        COMPUTE LN-LEN = 0 - LN-DX
    ELSE
        MOVE LN-DX TO LN-LEN
    END-IF
    IF LN-DY < 0
        IF 0 - LN-DY > LN-LEN
            COMPUTE LN-LEN = 0 - LN-DY
        END-IF
    ELSE
        IF LN-DY > LN-LEN
            MOVE LN-DY TO LN-LEN
        END-IF
    END-IF
    COMPUTE MAGIC-D = LN-LEN + 0.5 + MAGIC-K
    MOVE MAGIC-LO TO LN-N
    IF LN-N < 1
        MOVE 1 TO LN-N
    END-IF
    COMPUTE LN-SX = LN-DX / LN-N
    COMPUTE LN-SY = LN-DY / LN-N
    MOVE LN-AX TO LN-CX
    MOVE LN-AY TO LN-CY
    PERFORM VARYING LN-I FROM 0 BY 1 UNTIL LN-I > LN-N
        COMPUTE MAGIC-D = LN-CX - 0.5 + MAGIC-K
        MOVE MAGIC-LO TO PL-X
        COMPUTE MAGIC-D = LN-CY - 0.5 + MAGIC-K
        MOVE MAGIC-LO TO PL-Y
        PERFORM PLOT-DOT
        ADD LN-SX TO LN-CX
        ADD LN-SY TO LN-CY
    END-PERFORM.

LINE-CLIP-EDGE.
    IF LN-REJECT = 1
        EXIT PARAGRAPH
    END-IF
    IF LN-P = 0
        IF LN-Q < 0
            MOVE 1 TO LN-REJECT
        END-IF
        EXIT PARAGRAPH
    END-IF
    COMPUTE LN-R = LN-Q / LN-P
    IF LN-P < 0
        IF LN-R > LN-T1
            MOVE 1 TO LN-REJECT
        ELSE
            IF LN-R > LN-T0
                MOVE LN-R TO LN-T0
            END-IF
        END-IF
    ELSE
        IF LN-R < LN-T0
            MOVE 1 TO LN-REJECT
        ELSE
            IF LN-R < LN-T1
                MOVE LN-R TO LN-T1
            END-IF
        END-IF
    END-IF.

*> a LN-W by LN-W dot of colour LN-COL at PL-X, PL-Y
PLOT-DOT.
    IF LN-W = 3
        COMPUTE PL-X0 = PL-X - 1
        COMPUTE PL-Y0 = PL-Y - 1
    ELSE
        MOVE PL-X TO PL-X0
        MOVE PL-Y TO PL-Y0
    END-IF
    COMPUTE PL-X1 = PL-X0 + LN-W - 1
    COMPUTE PL-Y1 = PL-Y0 + LN-W - 1
    IF PL-X0 < 0
        MOVE 0 TO PL-X0
    END-IF
    IF PL-X1 > 319
        MOVE 319 TO PL-X1
    END-IF
    IF PL-Y0 < 0
        MOVE 0 TO PL-Y0
    END-IF
    IF PL-Y1 > 223
        MOVE 223 TO PL-Y1
    END-IF
    IF PL-X0 > PL-X1 OR PL-Y0 > PL-Y1
        EXIT PARAGRAPH
    END-IF
    COMPUTE PL-LEN = PL-X1 - PL-X0 + 1
    PERFORM VARYING PL-ROW FROM PL-Y0 BY 1 UNTIL PL-ROW > PL-Y1
        COMPUTE PL-OFF = PL-ROW * 320 + PL-X0 + 1
        MOVE FILL-ROW(LN-COL + 1)(1:PL-LEN) TO FB(PL-OFF:PL-LEN)
    END-PERFORM.

*> a 3D segment (EF-P to EF-Q, world) into the ordering table as a line
SUBMIT-LINE3D.
    MOVE EF-PX TO WX
    MOVE EF-PY TO WY
    MOVE EF-PZ TO WZ
    PERFORM WORLD-TO-CAM
    MOVE CX TO EF-AX
    MOVE CY TO EF-AY
    MOVE CZ TO EF-AZ
    MOVE EF-QX TO WX
    MOVE EF-QY TO WY
    MOVE EF-QZ TO WZ
    PERFORM WORLD-TO-CAM
    IF EF-AZ < ZNEAR AND CZ < ZNEAR
        EXIT PARAGRAPH
    END-IF
    IF EF-AZ < ZNEAR
        COMPUTE A1 = (ZNEAR - CZ) / (EF-AZ - CZ)
        COMPUTE EF-AX = CX + (EF-AX - CX) * A1
        COMPUTE EF-AY = CY + (EF-AY - CY) * A1
        MOVE ZNEAR TO EF-AZ
    END-IF
    IF CZ < ZNEAR
        COMPUTE A1 = (ZNEAR - EF-AZ) / (CZ - EF-AZ)
        COMPUTE CX = EF-AX + (CX - EF-AX) * A1
        COMPUTE CY = EF-AY + (CY - EF-AY) * A1
        MOVE ZNEAR TO CZ
    END-IF
    IF PB-COUNT >= MAX-PB
        EXIT PARAGRAPH
    END-IF
    ADD 1 TO PB-COUNT
    MOVE PB-COUNT TO NEW-PB
    MOVE 2 TO PB-TYPE(NEW-PB)
    MOVE 1 TO PB-N(NEW-PB)
    MOVE 6 TO PB-COL(NEW-PB)
    MOVE 0 TO PB-COL2(NEW-PB)
    COMPUTE PB-X(NEW-PB, 1) = 160 + EF-AX * FOCAL / EF-AZ
    COMPUTE PB-Y(NEW-PB, 1) = 112 - EF-AY * FOCAL / EF-AZ
    COMPUTE PB-X(NEW-PB, 2) = 160 + CX * FOCAL / CZ
    COMPUTE PB-Y(NEW-PB, 2) = 112 - CY * FOCAL / CZ
    COMPUTE OT-Z = (EF-AZ + CZ) / 2
    MOVE 4 TO OT-LAYER
    PERFORM OT-INSERT.

*> ---------------------------------------------------------------------
*>  particles, lasers and dust into the ordering table
*> ---------------------------------------------------------------------
SUBMIT-PARTICLES.
    PERFORM VARYING EF-I FROM 1 BY 1 UNTIL EF-I > MAX-PT
        IF PT-TYPE(EF-I) > 0
            IF PT-DELAY(EF-I) <= 0
                EVALUATE PT-TYPE(EF-I)
                    WHEN 1 PERFORM SUBMIT-FIREBALL
                    WHEN 2 PERFORM SUBMIT-SPARK
                    WHEN 3 PERFORM SUBMIT-DEBRIS
                    WHEN 4 PERFORM SUBMIT-SMOKE
                END-EVALUATE
            END-IF
        END-IF
    END-PERFORM.

SUBMIT-FIREBALL.
    MOVE PT-X(EF-I) TO WX
    MOVE PT-Y(EF-I) TO WY
    MOVE PT-Z(EF-I) TO WZ
    PERFORM WORLD-TO-CAM
    IF CZ < ZNEAR + 0.3
        EXIT PARAGRAPH
    END-IF
    COMPUTE EF-F = PT-AGE(EF-I) / PT-LIFE(EF-I)
    COMPUTE EF-S = PT-SIZE(EF-I) * (0.3 + 0.9 * EF-F * (2 - EF-F))
    COMPUTE A1 = FOCAL / CZ
    COMPUTE SPR-CX = 160 + CX * A1
    COMPUTE SPR-CY = 112 - CY * A1
    MOVE 4 TO OT-LAYER
    MOVE CZ TO OT-Z
    MOVE 16 TO SPR-NV
    MOVE 0.42 TO SPR-JAMT
    *> inserted front to back: the ordering table draws a bucket newest first
    IF EF-F < 0.55
        COMPUTE SPR-R = EF-S * A1 * 0.5 * (1 - EF-F * 1.5)
        COMPUTE MAGIC-D = 15.4 - EF-F * 5 + MAGIC-K
        COMPUTE SPR-COL = PT-RAMP(EF-I) * 16 + MAGIC-LO
        COMPUTE SPR-SEED = EF-I * 3 + 1
        MOVE 0 TO SPR-MESH
        IF SPR-R > 0.4
            PERFORM SUBMIT-SPRITE
        END-IF
    END-IF
    COMPUTE SPR-R = EF-S * A1 * 0.8
    COMPUTE MAGIC-D = 13.6 - EF-F * 10 + MAGIC-K
    MOVE MAGIC-LO TO EF-SHADE
    IF EF-SHADE < 1
        MOVE 1 TO EF-SHADE
    END-IF
    COMPUTE SPR-COL = PT-RAMP(EF-I) * 16 + EF-SHADE
    MOVE EF-I TO SPR-SEED
    IF EF-F > 0.72
        MOVE 1 TO SPR-MESH
    ELSE
        MOVE 0 TO SPR-MESH
    END-IF
    IF SPR-R > 0.5
        PERFORM SUBMIT-SPRITE
    END-IF
    IF EF-F < 0.8
        COMPUTE SPR-R = EF-S * A1 * 1.15
        COMPUTE MAGIC-D = 9.4 - EF-F * 8 + MAGIC-K
        MOVE MAGIC-LO TO EF-SHADE
        IF EF-SHADE < 1
            MOVE 1 TO EF-SHADE
        END-IF
        COMPUTE SPR-COL = PT-RAMP(EF-I) * 16 + EF-SHADE
        COMPUTE SPR-SEED = EF-I * 5 + 2
        MOVE 1 TO SPR-MESH
        IF SPR-R > 1.5
            PERFORM SUBMIT-SPRITE
        END-IF
    END-IF.

SUBMIT-SMOKE.
    MOVE PT-X(EF-I) TO WX
    MOVE PT-Y(EF-I) TO WY
    MOVE PT-Z(EF-I) TO WZ
    PERFORM WORLD-TO-CAM
    IF CZ < ZNEAR + 0.3
        EXIT PARAGRAPH
    END-IF
    COMPUTE EF-F = PT-AGE(EF-I) / PT-LIFE(EF-I)
    COMPUTE A1 = FOCAL / CZ
    COMPUTE SPR-CX = 160 + CX * A1
    COMPUTE SPR-CY = 112 - CY * A1
    COMPUTE SPR-R = PT-SIZE(EF-I) * (0.5 + EF-F) * A1
    COMPUTE MAGIC-D = 5.4 - EF-F * 3.5 + MAGIC-K
    COMPUTE SPR-COL = 96 + MAGIC-LO
    MOVE 16 TO SPR-NV
    MOVE 0.35 TO SPR-JAMT
    MOVE 1 TO SPR-MESH
    MOVE EF-I TO SPR-SEED
    MOVE 4 TO OT-LAYER
    COMPUTE OT-Z = CZ + 0.5
    IF SPR-R > 0.6
        PERFORM SUBMIT-SPRITE
    END-IF.

SUBMIT-SPARK.
    COMPUTE EF-F = PT-AGE(EF-I) / PT-LIFE(EF-I)
    MOVE PT-X(EF-I) TO EF-PX
    MOVE PT-Y(EF-I) TO EF-PY
    MOVE PT-Z(EF-I) TO EF-PZ
    COMPUTE EF-QX = PT-X(EF-I) - PT-VX(EF-I) * 0.045
    COMPUTE EF-QY = PT-Y(EF-I) - PT-VY(EF-I) * 0.045
    COMPUTE EF-QZ = PT-Z(EF-I) - PT-VZ(EF-I) * 0.045
    MOVE 0 TO NEW-PB
    PERFORM SUBMIT-LINE3D
    IF NEW-PB > 0 AND PB-TYPE(NEW-PB) = 2 AND PB-COUNT = NEW-PB
        COMPUTE MAGIC-D = 15 - EF-F * 10 + MAGIC-K
        COMPUTE PB-COL(NEW-PB) = PT-RAMP(EF-I) * 16 + MAGIC-LO
        MOVE 1 TO PB-N(NEW-PB)
        MOVE 0 TO PB-COL2(NEW-PB)
    END-IF.

*> a tumbling triangle: corners A*u + B*v rotated about B
SUBMIT-DEBRIS.
    MOVE PT-ROT(EF-I) TO ANG
    PERFORM SINCOS
    COMPUTE EF-AX = PT-AX(EF-I) * CS + PT-NX(EF-I) * SN
    COMPUTE EF-AY = PT-AY(EF-I) * CS + PT-NY(EF-I) * SN
    COMPUTE EF-AZ = PT-AZ(EF-I) * CS + PT-NZ(EF-I) * SN
    COMPUTE EF-NX = PT-NX(EF-I) * CS - PT-AX(EF-I) * SN
    COMPUTE EF-NY = PT-NY(EF-I) * CS - PT-AY(EF-I) * SN
    COMPUTE EF-NZ = PT-NZ(EF-I) * CS - PT-AZ(EF-I) * SN
    MOVE PT-SIZE(EF-I) TO EF-S
    MOVE 0 TO SF-BEHIND
    PERFORM VARYING EF-K FROM 1 BY 1 UNTIL EF-K > 3
        EVALUATE EF-K
            WHEN 1
                COMPUTE WX = PT-X(EF-I) + EF-AX * EF-S
                COMPUTE WY = PT-Y(EF-I) + EF-AY * EF-S
                COMPUTE WZ = PT-Z(EF-I) + EF-AZ * EF-S
            WHEN 2
                COMPUTE WX = PT-X(EF-I) - EF-AX * EF-S * 0.6 + PT-BX(EF-I) * EF-S * 0.8
                COMPUTE WY = PT-Y(EF-I) - EF-AY * EF-S * 0.6 + PT-BY(EF-I) * EF-S * 0.8
                COMPUTE WZ = PT-Z(EF-I) - EF-AZ * EF-S * 0.6 + PT-BZ(EF-I) * EF-S * 0.8
            WHEN OTHER
                COMPUTE WX = PT-X(EF-I) - EF-AX * EF-S * 0.4 - PT-BX(EF-I) * EF-S * 0.9
                COMPUTE WY = PT-Y(EF-I) - EF-AY * EF-S * 0.4 - PT-BY(EF-I) * EF-S * 0.9
                COMPUTE WZ = PT-Z(EF-I) - EF-AZ * EF-S * 0.4 - PT-BZ(EF-I) * EF-S * 0.9
        END-EVALUATE
        PERFORM WORLD-TO-CAM
        IF CZ < ZNEAR
            MOVE 1 TO SF-BEHIND
        ELSE
            COMPUTE RP-X(EF-K) = 160 + CX * FOCAL / CZ
            COMPUTE RP-Y(EF-K) = 112 - CY * FOCAL / CZ
        END-IF
    END-PERFORM
    IF SF-BEHIND = 1 OR PB-COUNT >= MAX-PB
        EXIT PARAGRAPH
    END-IF
    COMPUTE SF-L = EF-NX * SUN-X + EF-NY * SUN-Y + EF-NZ * SUN-Z
    IF SF-L < 0
        COMPUTE SF-L = 0 - SF-L
    END-IF
    COMPUTE MAGIC-D = AMBIENT + DIFFUSE * SF-L + MAGIC-K
    MOVE MAGIC-LO TO SF-SHADE
    IF SF-SHADE > 15
        MOVE 15 TO SF-SHADE
    END-IF
    ADD 1 TO PB-COUNT
    MOVE PB-COUNT TO NEW-PB
    MOVE 1 TO PB-TYPE(NEW-PB)
    MOVE 0 TO PB-MESH(NEW-PB)
    MOVE 3 TO PB-N(NEW-PB)
    COMPUTE PB-COL(NEW-PB) = PT-RAMP(EF-I) * 16 + SF-SHADE
    PERFORM VARYING EF-K FROM 1 BY 1 UNTIL EF-K > 3
        MOVE RP-X(EF-K) TO PB-X(NEW-PB, EF-K)
        MOVE RP-Y(EF-K) TO PB-Y(NEW-PB, EF-K)
    END-PERFORM
    MOVE PT-X(EF-I) TO WX
    MOVE PT-Y(EF-I) TO WY
    MOVE PT-Z(EF-I) TO WZ
    PERFORM WORLD-TO-CAM
    MOVE CZ TO OT-Z
    MOVE 4 TO OT-LAYER
    PERFORM OT-INSERT.

SUBMIT-LASERS.
    PERFORM VARYING EF-I FROM 1 BY 1 UNTIL EF-I > MAX-LZ
        IF LZ-ON(EF-I) = 1
            MOVE LZ-X(EF-I) TO EF-PX
            MOVE LZ-Y(EF-I) TO EF-PY
            MOVE LZ-Z(EF-I) TO EF-PZ
            COMPUTE EF-QX = LZ-X(EF-I) - LZ-VX(EF-I) * LZ-K(EF-I)
            COMPUTE EF-QY = LZ-Y(EF-I) - LZ-VY(EF-I) * LZ-K(EF-I)
            COMPUTE EF-QZ = LZ-Z(EF-I) - LZ-VZ(EF-I) * LZ-K(EF-I)
            MOVE 0 TO NEW-PB
            PERFORM SUBMIT-LINE3D
            IF NEW-PB > 0 AND PB-COUNT = NEW-PB AND PB-TYPE(NEW-PB) = 2
                COMPUTE PB-COL(NEW-PB) = LZ-RAMP(EF-I) * 16 + 10
                COMPUTE PB-COL2(NEW-PB) = LZ-RAMP(EF-I) * 16 + 15
                MOVE 2 TO PB-N(NEW-PB)
            END-IF
        END-IF
    END-PERFORM.

*> dust drifts in a box around the camera and streaks with its motion
SUBMIT-DUST.
    PERFORM VARYING EF-I FROM 1 BY 1 UNTIL EF-I > MAX-DUST
        COMPUTE A1 = DU-X(EF-I) - CAM-PX + 60
        COMPUTE MAGIC-D = A1 / 120 - 0.5 + MAGIC-K
        COMPUTE DU-X(EF-I) = DU-X(EF-I) - MAGIC-LO * 120
        COMPUTE A1 = DU-Y(EF-I) - CAM-PY + 60
        COMPUTE MAGIC-D = A1 / 120 - 0.5 + MAGIC-K
        COMPUTE DU-Y(EF-I) = DU-Y(EF-I) - MAGIC-LO * 120
        COMPUTE A1 = DU-Z(EF-I) - CAM-PZ + 60
        COMPUTE MAGIC-D = A1 / 120 - 0.5 + MAGIC-K
        COMPUTE DU-Z(EF-I) = DU-Z(EF-I) - MAGIC-LO * 120
        IF CAM-CUT = 0
            MOVE DU-X(EF-I) TO EF-PX
            MOVE DU-Y(EF-I) TO EF-PY
            MOVE DU-Z(EF-I) TO EF-PZ
            COMPUTE EF-QX = DU-X(EF-I) + CAM-VX * 1.5
            COMPUTE EF-QY = DU-Y(EF-I) + CAM-VY * 1.5
            COMPUTE EF-QZ = DU-Z(EF-I) + CAM-VZ * 1.5
            MOVE 0 TO NEW-PB
            PERFORM SUBMIT-LINE3D
            IF NEW-PB > 0 AND PB-COUNT = NEW-PB AND PB-TYPE(NEW-PB) = 2
                COMPUTE MAGIC-D = 9 - OT-Z / 9 + MAGIC-K
                MOVE MAGIC-LO TO EF-SHADE
                IF EF-SHADE < 2
                    MOVE 2 TO EF-SHADE
                END-IF
                MOVE EF-SHADE TO PB-COL(NEW-PB)
                MOVE 0 TO PB-COL2(NEW-PB)
                MOVE 1 TO PB-N(NEW-PB)
            END-IF
        END-IF
    END-PERFORM.

*> =====================================================================
*>  EFFECTS SIMULATION
*> =====================================================================
UPDATE-EFFECTS.
    PERFORM VARYING EF-I FROM 1 BY 1 UNTIL EF-I > MAX-PT
        IF PT-TYPE(EF-I) > 0
            IF PT-DELAY(EF-I) > 0
                SUBTRACT DT FROM PT-DELAY(EF-I)
            ELSE
                ADD DT TO PT-AGE(EF-I)
                IF PT-AGE(EF-I) >= PT-LIFE(EF-I)
                    MOVE 0 TO PT-TYPE(EF-I)
                ELSE
                    COMPUTE PT-X(EF-I) = PT-X(EF-I) + PT-VX(EF-I) * DT
                    COMPUTE PT-Y(EF-I) = PT-Y(EF-I) + PT-VY(EF-I) * DT
                    COMPUTE PT-Z(EF-I) = PT-Z(EF-I) + PT-VZ(EF-I) * DT
                    COMPUTE PT-VX(EF-I) = PT-VX(EF-I) * PT-DRAG(EF-I)
                    COMPUTE PT-VY(EF-I) = PT-VY(EF-I) * PT-DRAG(EF-I)
                    COMPUTE PT-VZ(EF-I) = PT-VZ(EF-I) * PT-DRAG(EF-I)
                    COMPUTE PT-ROT(EF-I) = PT-ROT(EF-I) + PT-ROTV(EF-I) * DT
                END-IF
            END-IF
        END-IF
    END-PERFORM
    PERFORM VARYING EF-I FROM 1 BY 1 UNTIL EF-I > MAX-LZ
        IF LZ-ON(EF-I) = 1
            ADD DT TO LZ-AGE(EF-I)
            IF LZ-AGE(EF-I) >= LZ-LIFE(EF-I)
                MOVE 0 TO LZ-ON(EF-I)
                PERFORM LASER-IMPACT
            ELSE
                COMPUTE LZ-X(EF-I) = LZ-X(EF-I) + LZ-VX(EF-I) * DT
                COMPUTE LZ-Y(EF-I) = LZ-Y(EF-I) + LZ-VY(EF-I) * DT
                COMPUTE LZ-Z(EF-I) = LZ-Z(EF-I) + LZ-VZ(EF-I) * DT
            END-IF
        END-IF
    END-PERFORM
    PERFORM VARYING OJ FROM 1 BY 1 UNTIL OJ > MAX-OBJ
        IF OB-ACTIVE(OJ) = 1 AND OB-DRIFT(OJ) = 1
            PERFORM DRIFT-OBJECT
        END-IF
    END-PERFORM
    IF FX-FLASH > 0
        COMPUTE FX-FLASH = FX-FLASH - DT * FX-FLASH-RATE
        IF FX-FLASH < 0
            MOVE 0 TO FX-FLASH
        END-IF
    END-IF
    IF FX-SHAKE > 0
        COMPUTE FX-SHAKE = FX-SHAKE * 0.94 - 0.01
        IF FX-SHAKE < 0
            MOVE 0 TO FX-SHAKE
        END-IF
    END-IF.

LASER-IMPACT.
    IF LZ-KILL(EF-I) > 0
        MOVE LZ-KILL(EF-I) TO OJ
        IF OB-ACTIVE(OJ) = 1
            MOVE LZ-BOOM(EF-I) TO EX-SIZE
            PERFORM KILL-OBJECT
        END-IF
    ELSE
        IF LZ-BOOM(EF-I) > 0
            MOVE LZ-X(EF-I) TO EX-X
            MOVE LZ-Y(EF-I) TO EX-Y
            MOVE LZ-Z(EF-I) TO EX-Z
            MOVE 0 TO EX-VX EX-VY EX-VZ
            MOVE LZ-BOOM(EF-I) TO EX-SIZE
            MOVE 6 TO EX-RAMP
            PERFORM SPAWN-EXPLOSION
        END-IF
    END-IF.

*> object OJ explodes; EX-SIZE set by the caller
KILL-OBJECT.
    MOVE OB-PX(OJ) TO EX-X
    MOVE OB-PY(OJ) TO EX-Y
    MOVE OB-PZ(OJ) TO EX-Z
    MOVE OB-VX(OJ) TO EX-VX
    MOVE OB-VY(OJ) TO EX-VY
    MOVE OB-VZ(OJ) TO EX-VZ
    IF OB-MESH(OJ) = 1
        MOVE 1 TO EX-RAMP
    ELSE
        MOVE 3 TO EX-RAMP
    END-IF
    PERFORM SPAWN-EXPLOSION
    MOVE 0 TO OB-ACTIVE(OJ).

*> spin about (OB-WX..) at OB-WRATE radians a second and coast
DRIFT-OBJECT.
    COMPUTE OB-PX(OJ) = OB-PX(OJ) + OB-VX(OJ) * DT
    COMPUTE OB-PY(OJ) = OB-PY(OJ) + OB-VY(OJ) * DT
    COMPUTE OB-PZ(OJ) = OB-PZ(OJ) + OB-VZ(OJ) * DT
    COMPUTE ANG = OB-WRATE(OJ) * DT
    PERFORM SINCOS
    MOVE OB-XX(OJ) TO VEC-X
    MOVE OB-XY(OJ) TO VEC-Y
    MOVE OB-XZ(OJ) TO VEC-Z
    PERFORM ROTATE-VEC
    MOVE VEC-X TO OB-XX(OJ)
    MOVE VEC-Y TO OB-XY(OJ)
    MOVE VEC-Z TO OB-XZ(OJ)
    MOVE OB-YX(OJ) TO VEC-X
    MOVE OB-YY(OJ) TO VEC-Y
    MOVE OB-YZ(OJ) TO VEC-Z
    PERFORM ROTATE-VEC
    MOVE VEC-X TO OB-YX(OJ)
    MOVE VEC-Y TO OB-YY(OJ)
    MOVE VEC-Z TO OB-YZ(OJ)
    MOVE OB-ZX(OJ) TO VEC-X
    MOVE OB-ZY(OJ) TO VEC-Y
    MOVE OB-ZZ(OJ) TO VEC-Z
    PERFORM ROTATE-VEC
    MOVE VEC-X TO OB-ZX(OJ)
    MOVE VEC-Y TO OB-ZY(OJ)
    MOVE VEC-Z TO OB-ZZ(OJ).

*> Rodrigues: VEC about unit axis (OB-WX.. of OJ) by the angle in SN/CS
ROTATE-VEC.
    COMPUTE A1 = OB-WX(OJ) * VEC-X + OB-WY(OJ) * VEC-Y + OB-WZ(OJ) * VEC-Z
    COMPUTE A2 = OB-WY(OJ) * VEC-Z - OB-WZ(OJ) * VEC-Y
    COMPUTE A3 = OB-WZ(OJ) * VEC-X - OB-WX(OJ) * VEC-Z
    COMPUTE A4 = OB-WX(OJ) * VEC-Y - OB-WY(OJ) * VEC-X
    COMPUTE VEC-X = VEC-X * CS + A2 * SN + OB-WX(OJ) * A1 * (1 - CS)
    COMPUTE VEC-Y = VEC-Y * CS + A3 * SN + OB-WY(OJ) * A1 * (1 - CS)
    COMPUTE VEC-Z = VEC-Z * CS + A4 * SN + OB-WZ(OJ) * A1 * (1 - CS).

*> one particle from the NP- fields; EF-NEW is its slot (0 if full)
SPAWN-PARTICLE.
    MOVE 0 TO EF-NEW
    PERFORM VARYING EF-K FROM 1 BY 1 UNTIL EF-K > MAX-PT OR EF-NEW > 0
        IF PT-TYPE(PT-CURSOR) = 0
            MOVE PT-CURSOR TO EF-NEW
        END-IF
        ADD 1 TO PT-CURSOR
        IF PT-CURSOR > MAX-PT
            MOVE 1 TO PT-CURSOR
        END-IF
    END-PERFORM
    IF EF-NEW = 0
        EXIT PARAGRAPH
    END-IF
    MOVE NP-TYPE TO PT-TYPE(EF-NEW)
    MOVE NP-RAMP TO PT-RAMP(EF-NEW)
    MOVE NP-X TO PT-X(EF-NEW)
    MOVE NP-Y TO PT-Y(EF-NEW)
    MOVE NP-Z TO PT-Z(EF-NEW)
    MOVE NP-VX TO PT-VX(EF-NEW)
    MOVE NP-VY TO PT-VY(EF-NEW)
    MOVE NP-VZ TO PT-VZ(EF-NEW)
    MOVE NP-LIFE TO PT-LIFE(EF-NEW)
    MOVE NP-SIZE TO PT-SIZE(EF-NEW)
    MOVE NP-DELAY TO PT-DELAY(EF-NEW)
    MOVE NP-DRAG TO PT-DRAG(EF-NEW)
    MOVE 0 TO PT-AGE(EF-NEW) PT-ROT(EF-NEW) PT-ROTV(EF-NEW).

*> random unit vector in VEC-X/Y/Z
RANDOM-DIR.
    PERFORM NEXT-RANDOM
    COMPUTE VEC-X = RND * 2 - 1
    PERFORM NEXT-RANDOM
    COMPUTE VEC-Y = RND * 2 - 1
    PERFORM NEXT-RANDOM
    COMPUTE VEC-Z = RND * 2 - 1
    PERFORM NORMALIZE-VEC.

*> fireballs, smoke, sparks and tumbling debris at EX-X/Y/Z
SPAWN-EXPLOSION.
    MOVE 1 TO NP-TYPE
    MOVE 7 TO NP-RAMP
    MOVE EX-X TO NP-X
    MOVE EX-Y TO NP-Y
    MOVE EX-Z TO NP-Z
    COMPUTE NP-VX = EX-VX * 0.3
    COMPUTE NP-VY = EX-VY * 0.3
    COMPUTE NP-VZ = EX-VZ * 0.3
    COMPUTE NP-LIFE = 0.8 + EX-SIZE / 60
    MOVE EX-SIZE TO NP-SIZE
    MOVE 0 TO NP-DELAY
    MOVE 0.97 TO NP-DRAG
    PERFORM SPAWN-PARTICLE
    *> secondary fireballs
    COMPUTE EX-N = 3 + EX-SIZE / 8
    IF EX-N > 9
        MOVE 9 TO EX-N
    END-IF
    PERFORM VARYING EX-I FROM 1 BY 1 UNTIL EX-I > EX-N
        PERFORM RANDOM-DIR
        PERFORM NEXT-RANDOM
        COMPUTE NP-X = EX-X + VEC-X * EX-SIZE * 0.55 * RND
        COMPUTE NP-Y = EX-Y + VEC-Y * EX-SIZE * 0.55 * RND
        COMPUTE NP-Z = EX-Z + VEC-Z * EX-SIZE * 0.55 * RND
        COMPUTE NP-VX = EX-VX * 0.3 + VEC-X * EX-SIZE * 0.6
        COMPUTE NP-VY = EX-VY * 0.3 + VEC-Y * EX-SIZE * 0.6
        COMPUTE NP-VZ = EX-VZ * 0.3 + VEC-Z * EX-SIZE * 0.6
        PERFORM NEXT-RANDOM
        COMPUTE NP-SIZE = EX-SIZE * (0.35 + RND * 0.35)
        COMPUTE NP-LIFE = 0.5 + RND * 0.5 + EX-SIZE / 80
        PERFORM NEXT-RANDOM
        COMPUTE NP-DELAY = RND * 0.35
        MOVE 1 TO NP-TYPE
        MOVE 7 TO NP-RAMP
        MOVE 0.95 TO NP-DRAG
        PERFORM SPAWN-PARTICLE
    END-PERFORM
    *> smoke
    PERFORM VARYING EX-I FROM 1 BY 1 UNTIL EX-I > 3
        PERFORM RANDOM-DIR
        COMPUTE NP-X = EX-X + VEC-X * EX-SIZE * 0.3
        COMPUTE NP-Y = EX-Y + VEC-Y * EX-SIZE * 0.3
        COMPUTE NP-Z = EX-Z + VEC-Z * EX-SIZE * 0.3
        COMPUTE NP-VX = EX-VX * 0.4 + VEC-X * EX-SIZE * 0.25
        COMPUTE NP-VY = EX-VY * 0.4 + VEC-Y * EX-SIZE * 0.25
        COMPUTE NP-VZ = EX-VZ * 0.4 + VEC-Z * EX-SIZE * 0.25
        COMPUTE NP-SIZE = EX-SIZE * 0.7
        COMPUTE NP-LIFE = 1.6 + EX-SIZE / 40
        COMPUTE NP-DELAY = 0.25 + EX-I * 0.05
        MOVE 4 TO NP-TYPE
        MOVE 6 TO NP-RAMP
        MOVE 0.97 TO NP-DRAG
        PERFORM SPAWN-PARTICLE
    END-PERFORM
    *> sparks
    COMPUTE EX-N = 10 + EX-SIZE * 2
    IF EX-N > 40
        MOVE 40 TO EX-N
    END-IF
    PERFORM VARYING EX-I FROM 1 BY 1 UNTIL EX-I > EX-N
        PERFORM RANDOM-DIR
        PERFORM NEXT-RANDOM
        COMPUTE EX-SPD = EX-SIZE * (5 + RND * 14) + 10
        MOVE EX-X TO NP-X
        MOVE EX-Y TO NP-Y
        MOVE EX-Z TO NP-Z
        COMPUTE NP-VX = EX-VX + VEC-X * EX-SPD
        COMPUTE NP-VY = EX-VY + VEC-Y * EX-SPD
        COMPUTE NP-VZ = EX-VZ + VEC-Z * EX-SPD
        PERFORM NEXT-RANDOM
        COMPUTE NP-LIFE = 0.35 + RND * 0.6
        MOVE 0 TO NP-SIZE NP-DELAY
        MOVE 0.96 TO NP-DRAG
        MOVE 2 TO NP-TYPE
        MOVE 7 TO NP-RAMP
        PERFORM SPAWN-PARTICLE
    END-PERFORM
    *> debris
    COMPUTE EX-N = 6 + EX-SIZE
    IF EX-N > 30
        MOVE 30 TO EX-N
    END-IF
    PERFORM VARYING EX-I FROM 1 BY 1 UNTIL EX-I > EX-N
        PERFORM RANDOM-DIR
        PERFORM NEXT-RANDOM
        COMPUTE EX-SPD = EX-SIZE * (1.5 + RND * 4) + 4
        MOVE EX-X TO NP-X
        MOVE EX-Y TO NP-Y
        MOVE EX-Z TO NP-Z
        COMPUTE NP-VX = EX-VX * 0.6 + VEC-X * EX-SPD
        COMPUTE NP-VY = EX-VY * 0.6 + VEC-Y * EX-SPD
        COMPUTE NP-VZ = EX-VZ * 0.6 + VEC-Z * EX-SPD
        PERFORM NEXT-RANDOM
        COMPUTE NP-LIFE = 1.4 + RND * 1.8
        PERFORM NEXT-RANDOM
        COMPUTE NP-SIZE = EX-SIZE * (0.06 + RND * 0.12) + 0.15
        MOVE 0 TO NP-DELAY
        MOVE 0.995 TO NP-DRAG
        MOVE 3 TO NP-TYPE
        MOVE EX-RAMP TO NP-RAMP
        PERFORM SPAWN-PARTICLE
        IF EF-NEW > 0
            PERFORM RANDOM-DIR
            MOVE VEC-X TO PT-AX(EF-NEW)
            MOVE VEC-Y TO PT-AY(EF-NEW)
            MOVE VEC-Z TO PT-AZ(EF-NEW)
            PERFORM RANDOM-DIR
            COMPUTE PT-BX(EF-NEW) = PT-AY(EF-NEW) * VEC-Z - PT-AZ(EF-NEW) * VEC-Y
            COMPUTE PT-BY(EF-NEW) = PT-AZ(EF-NEW) * VEC-X - PT-AX(EF-NEW) * VEC-Z
            COMPUTE PT-BZ(EF-NEW) = PT-AX(EF-NEW) * VEC-Y - PT-AY(EF-NEW) * VEC-X
            MOVE PT-BX(EF-NEW) TO VEC-X
            MOVE PT-BY(EF-NEW) TO VEC-Y
            MOVE PT-BZ(EF-NEW) TO VEC-Z
            PERFORM NORMALIZE-VEC
            MOVE VEC-X TO PT-BX(EF-NEW)
            MOVE VEC-Y TO PT-BY(EF-NEW)
            MOVE VEC-Z TO PT-BZ(EF-NEW)
            COMPUTE PT-NX(EF-NEW) = PT-AY(EF-NEW) * PT-BZ(EF-NEW) - PT-AZ(EF-NEW) * PT-BY(EF-NEW)
            COMPUTE PT-NY(EF-NEW) = PT-AZ(EF-NEW) * PT-BX(EF-NEW) - PT-AX(EF-NEW) * PT-BZ(EF-NEW)
            COMPUTE PT-NZ(EF-NEW) = PT-AX(EF-NEW) * PT-BY(EF-NEW) - PT-AY(EF-NEW) * PT-BX(EF-NEW)
            PERFORM NEXT-RANDOM
            COMPUTE PT-ROTV(EF-NEW) = (RND - 0.5) * 18
        END-IF
    END-PERFORM
    IF EX-SIZE >= 30
        COMPUTE A1 = EX-SIZE / 160
        IF A1 > FX-FLASH
            MOVE A1 TO FX-FLASH
        END-IF
    END-IF
    IF EX-SIZE >= 14
        COMPUTE A1 = EX-SIZE / 30
        IF A1 > FX-SHAKE
            MOVE A1 TO FX-SHAKE
        END-IF
    END-IF.

*> muzzle flash and smoke-free puff (flak) at NP-X/Y/Z, size NP-SIZE
SPAWN-PUFF.
    MOVE 1 TO NP-TYPE
    MOVE 7 TO NP-RAMP
    MOVE 0 TO NP-VX NP-VY NP-VZ NP-DELAY
    MOVE 0.9 TO NP-DRAG
    PERFORM SPAWN-PARTICLE.

*> =====================================================================
*>  TEXT AND HUD
*> =====================================================================
*> add NEW-TEXT (NEW-LEN characters) to this frame's text list
ADD-TEXT.
    IF TEXT-COUNT >= MAX-TEXT
        EXIT PARAGRAPH
    END-IF
    ADD 1 TO TEXT-COUNT
    MOVE NEW-TEXT TO TX-STR(TEXT-COUNT)
    MOVE NEW-LEN TO TX-LEN(TEXT-COUNT)
    MOVE NEW-SCALE TO TX-SCALE(TEXT-COUNT)
    MOVE NEW-TY TO TX-Y(TEXT-COUNT)
    IF NEW-CENTER = 1
        COMPUTE TX-X(TEXT-COUNT) = 160 - (NEW-LEN * 6 - 2) * NEW-SCALE / 2
    ELSE
        MOVE NEW-TX TO TX-X(TEXT-COUNT)
    END-IF
    MOVE NEW-COL TO TX-COL(TEXT-COUNT)
    MOVE NEW-GLOW TO TX-GLOW(TEXT-COUNT)
    MOVE NEW-REVEAL TO TX-REVEAL(TEXT-COUNT).

DRAW-TEXTS.
    PERFORM VARYING TD-I FROM 1 BY 1 UNTIL TD-I > TEXT-COUNT
        IF TX-GLOW(TD-I) > 0
            MOVE 1 TO TD-PASS
            PERFORM DRAW-ONE-TEXT
        END-IF
        MOVE 2 TO TD-PASS
        PERFORM DRAW-ONE-TEXT
    END-PERFORM.

*> pass 1 draws a 3-pixel glow, pass 2 the core strokes
DRAW-ONE-TEXT.
    MOVE 0 TO TD-DONE
    PERFORM VARYING TD-C FROM 1 BY 1 UNTIL TD-C > TX-LEN(TD-I)
        MOVE TX-STR(TD-I)(TD-C:1) TO BYTE-C
        MOVE GLYPH-IX(BYTE-N + 1) TO TD-G
        IF TD-G > 0
            COMPUTE TD-X0 = TX-X(TD-I) + (TD-C - 1) * 6 * TX-SCALE(TD-I)
            PERFORM VARYING TD-S FROM 1 BY 1 UNTIL TD-S > GL-NSEG(TD-G)
                IF TD-DONE < TX-REVEAL(TD-I)
                    COMPUTE LN-X1 = TD-X0 + GL-X1(TD-G, TD-S) * TX-SCALE(TD-I)
                    COMPUTE LN-Y1 = TX-Y(TD-I) + (6 - GL-Y1(TD-G, TD-S)) * TX-SCALE(TD-I)
                    COMPUTE LN-X2 = TD-X0 + GL-X2(TD-G, TD-S) * TX-SCALE(TD-I)
                    COMPUTE LN-Y2 = TX-Y(TD-I) + (6 - GL-Y2(TD-G, TD-S)) * TX-SCALE(TD-I)
                    COMPUTE TD-FR = TX-REVEAL(TD-I) - TD-DONE
                    IF TD-FR < 1
                        COMPUTE LN-X2 = LN-X1 + (LN-X2 - LN-X1) * TD-FR
                        COMPUTE LN-Y2 = LN-Y1 + (LN-Y2 - LN-Y1) * TD-FR
                    END-IF
                    IF TD-PASS = 1
                        MOVE TX-GLOW(TD-I) TO LN-COL
                        MOVE 3 TO LN-W
                    ELSE
                        MOVE TX-COL(TD-I) TO LN-COL
                        IF TX-SCALE(TD-I) >= 3
                            MOVE 2 TO LN-W
                        ELSE
                            MOVE 1 TO LN-W
                        END-IF
                    END-IF
                    PERFORM DRAW-LINE
                END-IF
                ADD 1 TO TD-DONE
            END-PERFORM
        END-IF
    END-PERFORM.

*> screen-space polygon helper for the cockpit: RP- vertices already set
HUD-POLY.
    MOVE 0 TO RP-MESH
    PERFORM RASTER-POLY.

HUD-LINE.
    PERFORM DRAW-LINE.

DRAW-HUD.
    *> canopy frame and dashboard
    MOVE 4 TO RP-N
    MOVE 0 TO RP-X(1)
    MOVE 0 TO RP-Y(1)
    MOVE 17 TO RP-X(2)
    MOVE 0 TO RP-Y(2)
    MOVE 70 TO RP-X(3)
    MOVE 170 TO RP-Y(3)
    MOVE 48 TO RP-X(4)
    MOVE 170 TO RP-Y(4)
    MOVE 98 TO RP-COL
    PERFORM HUD-POLY
    MOVE 4 TO RP-N
    MOVE 303 TO RP-X(1)
    MOVE 0 TO RP-Y(1)
    MOVE 320 TO RP-X(2)
    MOVE 0 TO RP-Y(2)
    MOVE 272 TO RP-X(3)
    MOVE 170 TO RP-Y(3)
    MOVE 250 TO RP-X(4)
    MOVE 170 TO RP-Y(4)
    PERFORM HUD-POLY
    MOVE 4 TO RP-N
    MOVE 0 TO RP-X(1)
    MOVE 0 TO RP-Y(1)
    MOVE 320 TO RP-X(2)
    MOVE 0 TO RP-Y(2)
    MOVE 320 TO RP-X(3)
    MOVE 6 TO RP-Y(3)
    MOVE 0 TO RP-X(4)
    MOVE 6 TO RP-Y(4)
    PERFORM HUD-POLY
    MOVE 6 TO RP-N
    MOVE 0 TO RP-X(1)
    MOVE 224 TO RP-Y(1)
    MOVE 0 TO RP-X(2)
    MOVE 184 TO RP-Y(2)
    MOVE 48 TO RP-X(3)
    MOVE 168 TO RP-Y(3)
    MOVE 272 TO RP-X(4)
    MOVE 168 TO RP-Y(4)
    MOVE 320 TO RP-X(5)
    MOVE 184 TO RP-Y(5)
    MOVE 320 TO RP-X(6)
    MOVE 224 TO RP-Y(6)
    MOVE 99 TO RP-COL
    PERFORM HUD-POLY
    MOVE 48 TO LN-X1
    MOVE 168 TO LN-Y1
    MOVE 272 TO LN-X2
    MOVE 168 TO LN-Y2
    MOVE 104 TO LN-COL
    MOVE 1 TO LN-W
    PERFORM HUD-LINE
    *> reticle
    PERFORM VARYING HD-I FROM 1 BY 2 UNTIL HD-I > 16
        COMPUTE IX = HD-I + 2
        IF IX > 16
            SUBTRACT 16 FROM IX
        END-IF
        COMPUTE LN-X1 = 160 + DIR-C(HD-I) * 15
        COMPUTE LN-Y1 = 112 - DIR-S(HD-I) * 15
        COMPUTE LN-X2 = 160 + DIR-C(IX) * 15
        COMPUTE LN-Y2 = 112 - DIR-S(IX) * 15
        MOVE 233 TO LN-COL
        MOVE 1 TO LN-W
        PERFORM HUD-LINE
    END-PERFORM
    MOVE 1 TO LN-W
    MOVE 236 TO LN-COL
    MOVE 136 TO LN-X1
    MOVE 112 TO LN-Y1
    MOVE 143 TO LN-X2
    MOVE 112 TO LN-Y2
    PERFORM HUD-LINE
    MOVE 177 TO LN-X1
    MOVE 112 TO LN-Y1
    MOVE 184 TO LN-X2
    MOVE 112 TO LN-Y2
    PERFORM HUD-LINE
    MOVE 160 TO LN-X1
    MOVE 88 TO LN-Y1
    MOVE 160 TO LN-X2
    MOVE 95 TO LN-Y2
    PERFORM HUD-LINE
    MOVE 160 TO LN-X1
    MOVE 129 TO LN-Y1
    MOVE 160 TO LN-X2
    MOVE 136 TO LN-Y2
    PERFORM HUD-LINE
    *> radar scope
    PERFORM VARYING HD-I FROM 1 BY 1 UNTIL HD-I > 16
        COMPUTE IX = HD-I + 1
        IF IX > 16
            MOVE 1 TO IX
        END-IF
        COMPUTE LN-X1 = 160 + DIR-C(HD-I) * 22
        COMPUTE LN-Y1 = 197 - DIR-S(HD-I) * 22
        COMPUTE LN-X2 = 160 + DIR-C(IX) * 22
        COMPUTE LN-Y2 = 197 - DIR-S(IX) * 22
        MOVE 230 TO LN-COL
        PERFORM HUD-LINE
    END-PERFORM
    MOVE 228 TO LN-COL
    MOVE 138 TO LN-X1
    MOVE 197 TO LN-Y1
    MOVE 182 TO LN-X2
    MOVE 197 TO LN-Y2
    PERFORM HUD-LINE
    MOVE 160 TO LN-X1
    MOVE 175 TO LN-Y1
    MOVE 160 TO LN-X2
    MOVE 219 TO LN-Y2
    PERFORM HUD-LINE
    MOVE 0 TO HD-BEST
    MOVE 1.0E9 TO HD-BZ
    PERFORM VARYING HD-I FROM 2 BY 1 UNTIL HD-I > 11
        IF OB-ACTIVE(HD-I) = 1 AND OB-HIDE(HD-I) = 0
            MOVE OB-PX(HD-I) TO WX
            MOVE OB-PY(HD-I) TO WY
            MOVE OB-PZ(HD-I) TO WZ
            PERFORM WORLD-TO-CAM
            COMPUTE LN-X1 = 160 + CX / 30
            COMPUTE LN-Y1 = 197 - CZ / 30
            COMPUTE A1 = (LN-X1 - 160) * (LN-X1 - 160) + (LN-Y1 - 197) * (LN-Y1 - 197)
            IF A1 < 400
                MOVE LN-X1 TO LN-X2
                MOVE LN-Y1 TO LN-Y2
                MOVE 2 TO LN-W
                IF HD-I > 5
                    MOVE 157 TO LN-COL
                ELSE
                    MOVE 238 TO LN-COL
                END-IF
                PERFORM HUD-LINE
            END-IF
            IF HD-I > 5 AND CZ > 5 AND CZ < HD-BZ
                COMPUTE HD-SX = 160 + CX * FOCAL / CZ
                COMPUTE HD-SY = 112 - CY * FOCAL / CZ
                IF HD-SX > 20 AND HD-SX < 300 AND HD-SY > 12 AND HD-SY < 160
                    MOVE HD-I TO HD-BEST
                    MOVE CZ TO HD-BZ
                    MOVE HD-SX TO HD-SZ
                    MOVE HD-SY TO HD-B
                END-IF
            END-IF
        END-IF
    END-PERFORM
    *> target brackets on the nearest enemy ahead
    IF HD-BEST > 0
        MOVE HD-SZ TO HD-SX
        MOVE HD-B TO HD-SY
        COMPUTE HD-B = 3.5 * FOCAL / HD-BZ + 5
        IF HD-B > 40
            MOVE 40 TO HD-B
        END-IF
        MOVE 157 TO LN-COL
        MOVE 1 TO LN-W
        PERFORM VARYING HD-I FROM 1 BY 1 UNTIL HD-I > 4
            EVALUATE HD-I
                WHEN 1
                    COMPUTE A1 = HD-SX - HD-B
                    COMPUTE A2 = HD-SY - HD-B
                    MOVE 1 TO A3
                    MOVE 1 TO A4
                WHEN 2
                    COMPUTE A1 = HD-SX + HD-B
                    COMPUTE A2 = HD-SY - HD-B
                    MOVE -1 TO A3
                    MOVE 1 TO A4
                WHEN 3
                    COMPUTE A1 = HD-SX - HD-B
                    COMPUTE A2 = HD-SY + HD-B
                    MOVE 1 TO A3
                    MOVE -1 TO A4
                WHEN OTHER
                    COMPUTE A1 = HD-SX + HD-B
                    COMPUTE A2 = HD-SY + HD-B
                    MOVE -1 TO A3
                    MOVE -1 TO A4
            END-EVALUATE
            MOVE A1 TO LN-X1
            MOVE A2 TO LN-Y1
            COMPUTE LN-X2 = A1 + A3 * 5
            MOVE A2 TO LN-Y2
            PERFORM HUD-LINE
            MOVE A1 TO LN-X1
            MOVE A2 TO LN-Y1
            MOVE A1 TO LN-X2
            COMPUTE LN-Y2 = A2 + A4 * 5
            PERFORM HUD-LINE
        END-PERFORM
        IF HD-BZ < 9999
            COMPUTE HD-RANGE = HD-BZ
        ELSE
            MOVE 9999 TO HD-RANGE
        END-IF
        MOVE SPACES TO HD-TEXT
        STRING "RNG " HD-RANGE DELIMITED BY SIZE INTO HD-TEXT
        MOVE HD-TEXT TO NEW-TEXT
        MOVE 8 TO NEW-LEN
        MOVE 1 TO NEW-SCALE
        COMPUTE NEW-TX = HD-SX - 23
        COMPUTE NEW-TY = HD-SY + HD-B + 4
        MOVE 0 TO NEW-CENTER
        MOVE 157 TO NEW-COL
        MOVE 0 TO NEW-GLOW
        MOVE 999 TO NEW-REVEAL
        PERFORM ADD-TEXT
    END-IF
    *> gauges
    MOVE "SHIELD" TO NEW-TEXT
    MOVE 6 TO NEW-LEN
    MOVE 1 TO NEW-SCALE
    MOVE 22 TO NEW-TX
    MOVE 194 TO NEW-TY
    MOVE 0 TO NEW-CENTER
    MOVE 235 TO NEW-COL
    MOVE 0 TO NEW-GLOW
    MOVE 999 TO NEW-REVEAL
    PERFORM ADD-TEXT
    MOVE "LASER" TO NEW-TEXT
    MOVE 5 TO NEW-LEN
    MOVE 270 TO NEW-TX
    PERFORM ADD-TEXT
    MOVE 4 TO RP-N
    MOVE 22 TO RP-X(1)
    MOVE 205 TO RP-Y(1)
    MOVE 74 TO RP-X(2)
    MOVE 205 TO RP-Y(2)
    MOVE 74 TO RP-X(3)
    MOVE 209 TO RP-Y(3)
    MOVE 22 TO RP-X(4)
    MOVE 209 TO RP-Y(4)
    MOVE 229 TO RP-COL
    PERFORM HUD-POLY
    MOVE 4 TO RP-N
    MOVE 22 TO RP-X(1)
    MOVE 205 TO RP-Y(1)
    MOVE 62 TO RP-X(2)
    MOVE 205 TO RP-Y(2)
    MOVE 62 TO RP-X(3)
    MOVE 209 TO RP-Y(3)
    MOVE 22 TO RP-X(4)
    MOVE 209 TO RP-Y(4)
    MOVE 236 TO RP-COL
    PERFORM HUD-POLY
    MOVE 4 TO RP-N
    MOVE 264 TO RP-X(1)
    MOVE 205 TO RP-Y(1)
    MOVE 300 TO RP-X(2)
    MOVE 205 TO RP-Y(2)
    MOVE 300 TO RP-X(3)
    MOVE 209 TO RP-Y(3)
    MOVE 264 TO RP-X(4)
    MOVE 209 TO RP-Y(4)
    COMPUTE KX = FRAME-NO / 3
    COMPUTE RP-COL = 229 + FUNCTION MOD(KX, 2) * 6
    PERFORM HUD-POLY.

*> =====================================================================
*>  THE SCRIPT
*> =====================================================================
RUN-SCRIPT.
    EVALUATE TRUE
        WHEN NOW-T < 6.5
            MOVE 1 TO SC-SCENE
            MOVE 0 TO SC-T0
        WHEN NOW-T < 12
            MOVE 2 TO SC-SCENE
            MOVE 6.5 TO SC-T0
        WHEN NOW-T < 26
            MOVE 3 TO SC-SCENE
            MOVE 12 TO SC-T0
        WHEN NOW-T < 32
            MOVE 4 TO SC-SCENE
            MOVE 26 TO SC-T0
        WHEN NOW-T < 40
            MOVE 5 TO SC-SCENE
            MOVE 32 TO SC-T0
        WHEN NOW-T < 51
            MOVE 6 TO SC-SCENE
            MOVE 40 TO SC-T0
        WHEN NOW-T < 63
            MOVE 7 TO SC-SCENE
            MOVE 51 TO SC-T0
        WHEN OTHER
            MOVE 8 TO SC-SCENE
            MOVE 63 TO SC-T0
    END-EVALUATE
    COMPUTE SC-U = NOW-T - SC-T0
    EVALUATE SC-SCENE
        WHEN 1 MOVE 0 TO FRAME-KIND
        WHEN 2 MOVE 0 TO FRAME-KIND
        WHEN 3 MOVE 1 TO FRAME-KIND
        WHEN 4 MOVE 1 TO FRAME-KIND
        WHEN 8 MOVE 1 TO FRAME-KIND
        WHEN OTHER MOVE 2 TO FRAME-KIND
    END-EVALUATE
    IF SC-SCENE NOT = SC-LAST
        PERFORM SCENE-ENTER
        MOVE SC-SCENE TO SC-LAST
    END-IF
    MOVE 0 TO TEXT-COUNT HUD-ON
    MOVE 1 TO DUST-ON
    MOVE 1 TO FX-FADE
    MOVE 0 TO CAM-UPX CAM-UPZ CAM-ROLL
    MOVE 1 TO CAM-UPY
    *> cruiser frame at this moment (the ship drifts forward slowly)
    COMPUTE A1 = (NOW-T - 32) * CR-SPEED
    COMPUTE CR-QX = CR-Q0X + CR-ZX * A1
    COMPUTE CR-QY = CR-Q0Y + CR-ZY * A1
    COMPUTE CR-QZ = CR-Q0Z + CR-ZZ * A1
    PERFORM VARYING OI FROM 2 BY 1 UNTIL OI > 11
        IF OB-ACTIVE(OI) = 1 AND OB-PATHED(OI) = 1
            PERFORM PLACE-ON-PATH
        END-IF
    END-PERFORM
    IF OB-ACTIVE(12) = 1 AND OB-DRIFT(12) = 0
        PERFORM PLACE-CRUISER
    END-IF
    PERFORM PROCESS-EVENTS
    EVALUATE SC-SCENE
        WHEN 1 PERFORM SCENE-1
        WHEN 2 PERFORM SCENE-2
        WHEN 3 PERFORM SCENE-3
        WHEN 4 PERFORM SCENE-4
        WHEN 5 PERFORM SCENE-5
        WHEN 6 PERFORM SCENE-6
        WHEN 7 PERFORM SCENE-7
        WHEN OTHER PERFORM SCENE-8
    END-EVALUATE
    IF FX-SHAKE > 0
        PERFORM NEXT-RANDOM
        COMPUTE CAM-PX = CAM-PX + (RND - 0.5) * FX-SHAKE
        PERFORM NEXT-RANDOM
        COMPUTE CAM-PY = CAM-PY + (RND - 0.5) * FX-SHAKE
    END-IF
    PERFORM BUILD-CAMERA.

*> objects with a keyframed path in this scene appear, the rest go
SCENE-ENTER.
    MOVE LOW-VALUES TO LZ-TAB
    PERFORM VARYING OI FROM 2 BY 1 UNTIL OI > 11
        COMPUTE IX = SC-SCENE * 100 + OI
        IF PD-COUNT(IX) > 0
            MOVE 1 TO OB-ACTIVE(OI)
            MOVE 1 TO OB-PATHED(OI)
        ELSE
            MOVE 0 TO OB-ACTIVE(OI)
            MOVE 0 TO OB-PATHED(OI)
        END-IF
        MOVE 0 TO OB-HIDE(OI)
    END-PERFORM
    IF SC-SCENE >= 5 AND SC-SCENE <= 7
        IF CR-SET = 0
            PERFORM SETUP-CRUISER
        END-IF
    ELSE
        MOVE 0 TO OB-ACTIVE(12) OB-ACTIVE(13)
    END-IF
    IF SC-SCENE = 8
        PERFORM VARYING OI FROM 12 BY 1 UNTIL OI > 25
            MOVE 0 TO OB-ACTIVE(OI)
        END-PERFORM
        MOVE LOW-VALUES TO PT-TAB
        MOVE 0 TO FX-FLASH FX-SHAKE
    END-IF
    IF SC-SCENE = 5 OR SC-SCENE = 3
        MOVE LOW-VALUES TO PT-TAB
    END-IF.

SETUP-CRUISER.
    MOVE 1 TO CR-SET
    MOVE 3000 TO CR-Q0X
    MOVE 400 TO CR-Q0Y
    MOVE 3000 TO CR-Q0Z
    MOVE 12 TO OI
    MOVE 0.10 TO OR-FX
    MOVE 0.02 TO OR-FY
    MOVE 1 TO OR-FZ
    MOVE 0.06 TO OR-ROLL
    PERFORM ORIENT-OBJECT
    MOVE OB-XX(12) TO CR-XX
    MOVE OB-XY(12) TO CR-XY
    MOVE OB-XZ(12) TO CR-XZ
    MOVE OB-YX(12) TO CR-YX
    MOVE OB-YY(12) TO CR-YY
    MOVE OB-YZ(12) TO CR-YZ
    MOVE OB-ZX(12) TO CR-ZX
    MOVE OB-ZY(12) TO CR-ZY
    MOVE OB-ZZ(12) TO CR-ZZ
    MOVE 1 TO OB-ACTIVE(12) OB-ACTIVE(13).

PLACE-CRUISER.
    MOVE CR-QX TO OB-PX(12)
    MOVE CR-QY TO OB-PY(12)
    MOVE CR-QZ TO OB-PZ(12)
    MOVE CR-XX TO OB-XX(12)
    MOVE CR-XY TO OB-XY(12)
    MOVE CR-XZ TO OB-XZ(12)
    MOVE CR-YX TO OB-YX(12)
    MOVE CR-YY TO OB-YY(12)
    MOVE CR-YZ TO OB-YZ(12)
    MOVE CR-ZX TO OB-ZX(12)
    MOVE CR-ZY TO OB-ZY(12)
    MOVE CR-ZZ TO OB-ZZ(12)
    COMPUTE OB-VX(12) = CR-ZX * CR-SPEED
    COMPUTE OB-VY(12) = CR-ZY * CR-SPEED
    COMPUTE OB-VZ(12) = CR-ZZ * CR-SPEED
    MOVE OBJ-ENT(12) TO OBJ-ENT(13)
    MOVE 3 TO OB-MESH(13).

*> ---------------------------------------------------------------------
*>  paths: keyframe spline in the scene's frame, then to world space
*> ---------------------------------------------------------------------
EVAL-PATH.
    COMPUTE SP-PATH = SC-SCENE * 100 + PE-OBJ
    MOVE PE-T TO SP-T
    PERFORM EVAL-SPLINE
    MOVE SP-OK TO PE-OK
    MOVE SP-ROLL TO PE-ROLL
    EVALUATE FRAME-KIND
        WHEN 0
            MOVE SP-X TO PE-X
            MOVE SP-Y TO PE-Y
            MOVE SP-Z TO PE-Z
        WHEN 1
            *> the formation frame drifts along a long lazy curve
            COMPUTE FRAME-W = SC-T0 + PE-T - 12
            COMPUTE ANG = FRAME-W * 0.11
            PERFORM SINCOS
            COMPUTE PE-X = SP-X + 260 * SN
            COMPUTE ANG = FRAME-W * 0.17
            PERFORM SINCOS
            COMPUTE PE-Y = SP-Y + 40 * SN + 10
            COMPUTE PE-Z = SP-Z + 2000 + 75 * FRAME-W
        WHEN OTHER
            COMPUTE A1 = (SC-T0 + PE-T - 32) * CR-SPEED
            COMPUTE PE-X = CR-Q0X + CR-ZX * A1 + CR-XX * SP-X + CR-YX * SP-Y + CR-ZX * SP-Z
            COMPUTE PE-Y = CR-Q0Y + CR-ZY * A1 + CR-XY * SP-X + CR-YY * SP-Y + CR-ZY * SP-Z
            COMPUTE PE-Z = CR-Q0Z + CR-ZZ * A1 + CR-XZ * SP-X + CR-YZ * SP-Y + CR-ZZ * SP-Z
    END-EVALUATE
    *> a little life in formation flying
    IF PE-OBJ >= 2 AND PE-OBJ <= 11
        COMPUTE ANG = PE-T * 1.3 + PE-OBJ * 1.7
        PERFORM SINCOS
        COMPUTE PE-X = PE-X + 0.6 * SN
        COMPUTE ANG = PE-T * 1.1 + PE-OBJ * 2.3
        PERFORM SINCOS
        COMPUTE PE-Y = PE-Y + 0.4 * SN
    END-IF.

*> Catmull-Rom (non-uniform, as a cubic Hermite) through path SP-PATH
EVAL-SPLINE.
    MOVE 0 TO SP-OK SP-ROLL
    IF SP-PATH < 1 OR SP-PATH > MAX-PATH
        EXIT PARAGRAPH
    END-IF
    MOVE PD-FIRST(SP-PATH) TO SP-F
    MOVE PD-COUNT(SP-PATH) TO SP-L
    IF SP-L = 0
        EXIT PARAGRAPH
    END-IF
    MOVE 1 TO SP-OK
    IF SP-L = 1
        MOVE KF-X(SP-F) TO SP-X
        MOVE KF-Y(SP-F) TO SP-Y
        MOVE KF-Z(SP-F) TO SP-Z
        MOVE KF-ROLL(SP-F) TO SP-ROLL
        EXIT PARAGRAPH
    END-IF
    COMPUTE SP-L = SP-F + SP-L - 1
    *> before the first key or after the last: keep going in a straight line
    IF SP-T <= KF-T(SP-F)
        COMPUTE SP-H = (SP-T - KF-T(SP-F)) / (KF-T(SP-F + 1) - KF-T(SP-F))
        COMPUTE SP-X = KF-X(SP-F) + (KF-X(SP-F + 1) - KF-X(SP-F)) * SP-H
        COMPUTE SP-Y = KF-Y(SP-F) + (KF-Y(SP-F + 1) - KF-Y(SP-F)) * SP-H
        COMPUTE SP-Z = KF-Z(SP-F) + (KF-Z(SP-F + 1) - KF-Z(SP-F)) * SP-H
        MOVE KF-ROLL(SP-F) TO SP-ROLL
        EXIT PARAGRAPH
    END-IF
    IF SP-T >= KF-T(SP-L)
        COMPUTE SP-H = (SP-T - KF-T(SP-L)) / (KF-T(SP-L) - KF-T(SP-L - 1))
        COMPUTE SP-X = KF-X(SP-L) + (KF-X(SP-L) - KF-X(SP-L - 1)) * SP-H
        COMPUTE SP-Y = KF-Y(SP-L) + (KF-Y(SP-L) - KF-Y(SP-L - 1)) * SP-H
        COMPUTE SP-Z = KF-Z(SP-L) + (KF-Z(SP-L) - KF-Z(SP-L - 1)) * SP-H
        MOVE KF-ROLL(SP-L) TO SP-ROLL
        EXIT PARAGRAPH
    END-IF
    MOVE SP-F TO SP-I
    PERFORM UNTIL SP-I >= SP-L - 1 OR KF-T(SP-I + 1) > SP-T
        ADD 1 TO SP-I
    END-PERFORM
    COMPUTE SP-H = KF-T(SP-I + 1) - KF-T(SP-I)
    COMPUTE SP-S = (SP-T - KF-T(SP-I)) / SP-H
    *> tangent at key I
    IF SP-I = SP-F
        MOVE SP-I TO SP-I0
    ELSE
        COMPUTE SP-I0 = SP-I - 1
    END-IF
    COMPUTE SP-TA = KF-T(SP-I + 1) - KF-T(SP-I0)
    COMPUTE SP-M0X = (KF-X(SP-I + 1) - KF-X(SP-I0)) / SP-TA
    COMPUTE SP-M0Y = (KF-Y(SP-I + 1) - KF-Y(SP-I0)) / SP-TA
    COMPUTE SP-M0Z = (KF-Z(SP-I + 1) - KF-Z(SP-I0)) / SP-TA
    *> tangent at key I + 1
    IF SP-I + 1 = SP-L
        COMPUTE SP-I1 = SP-I + 1
    ELSE
        COMPUTE SP-I1 = SP-I + 2
    END-IF
    COMPUTE SP-TB = KF-T(SP-I1) - KF-T(SP-I)
    COMPUTE SP-M1X = (KF-X(SP-I1) - KF-X(SP-I)) / SP-TB
    COMPUTE SP-M1Y = (KF-Y(SP-I1) - KF-Y(SP-I)) / SP-TB
    COMPUTE SP-M1Z = (KF-Z(SP-I1) - KF-Z(SP-I)) / SP-TB
    COMPUTE SP-S2 = SP-S * SP-S
    COMPUTE SP-S3 = SP-S2 * SP-S
    COMPUTE SP-H00 = 2 * SP-S3 - 3 * SP-S2 + 1
    COMPUTE SP-H10 = (SP-S3 - 2 * SP-S2 + SP-S) * SP-H
    COMPUTE SP-H01 = 3 * SP-S2 - 2 * SP-S3
    COMPUTE SP-H11 = (SP-S3 - SP-S2) * SP-H
    COMPUTE SP-X = SP-H00 * KF-X(SP-I) + SP-H10 * SP-M0X
        + SP-H01 * KF-X(SP-I + 1) + SP-H11 * SP-M1X
    COMPUTE SP-Y = SP-H00 * KF-Y(SP-I) + SP-H10 * SP-M0Y
        + SP-H01 * KF-Y(SP-I + 1) + SP-H11 * SP-M1Y
    COMPUTE SP-Z = SP-H00 * KF-Z(SP-I) + SP-H10 * SP-M0Z
        + SP-H01 * KF-Z(SP-I + 1) + SP-H11 * SP-M1Z
    COMPUTE SP-ROLL = KF-ROLL(SP-I) + (KF-ROLL(SP-I + 1) - KF-ROLL(SP-I)) * SP-S.

*> position, heading and bank of ship OI from its path
PLACE-ON-PATH.
    MOVE OI TO PE-OBJ
    COMPUTE PE-T = SC-U - 0.06
    PERFORM EVAL-PATH
    MOVE PE-X TO P0X
    MOVE PE-Y TO P0Y
    MOVE PE-Z TO P0Z
    COMPUTE PE-T = SC-U + 0.06
    PERFORM EVAL-PATH
    MOVE PE-X TO P2X
    MOVE PE-Y TO P2Y
    MOVE PE-Z TO P2Z
    MOVE SC-U TO PE-T
    PERFORM EVAL-PATH
    MOVE PE-X TO P1X
    MOVE PE-Y TO P1Y
    MOVE PE-Z TO P1Z
    MOVE PE-X TO OB-PX(OI)
    MOVE PE-Y TO OB-PY(OI)
    MOVE PE-Z TO OB-PZ(OI)
    COMPUTE OB-VX(OI) = (P2X - P0X) / 0.12
    COMPUTE OB-VY(OI) = (P2Y - P0Y) / 0.12
    COMPUTE OB-VZ(OI) = (P2Z - P0Z) / 0.12
    COMPUTE OR-FX = P2X - P0X
    COMPUTE OR-FY = P2Y - P0Y
    COMPUTE OR-FZ = P2Z - P0Z
    *> bank into the turn: lateral acceleration along the level right axis
    MOVE OR-FZ TO VEC-X
    MOVE 0 TO VEC-Y
    COMPUTE VEC-Z = 0 - OR-FX
    PERFORM NORMALIZE-VEC
    COMPUTE OR-LAT = ((P2X - 2 * P1X + P0X) * VEC-X + (P2Z - 2 * P1Z + P0Z) * VEC-Z) / 0.0036
    COMPUTE OR-ROLL = OR-LAT * 0.012
    IF OR-ROLL > 1.2
        MOVE 1.2 TO OR-ROLL
    END-IF
    IF OR-ROLL < -1.2
        MOVE -1.2 TO OR-ROLL
    END-IF
    COMPUTE OR-ROLL = OR-ROLL + PE-ROLL
    PERFORM ORIENT-OBJECT.

*> ---------------------------------------------------------------------
*>  bursts of laser fire and scripted explosions for this scene
*> ---------------------------------------------------------------------
PROCESS-EVENTS.
    PERFORM VARYING BI FROM 1 BY 1 UNTIL BI > BURST-COUNT
        IF BU-SCENE(BI) = SC-SCENE
            PERFORM VARYING BS FROM 0 BY 1 UNTIL BS >= BU-COUNT(BI)
                COMPUTE SHOT-T = BU-T0(BI) + BS * BU-GAP(BI)
                IF SHOT-T >= SC-U AND SHOT-T < SC-U + DT
                    PERFORM FIRE-SHOT
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM
    PERFORM VARYING BI FROM 1 BY 1 UNTIL BI > BOOM-COUNT
        IF BM-SCENE(BI) = SC-SCENE
            IF BM-T(BI) >= SC-U AND BM-T(BI) < SC-U + DT
                PERFORM FIRE-BOOM
            END-IF
        END-IF
    END-PERFORM.

FIRE-SHOT.
    IF BS = BU-COUNT(BI) - 1
        MOVE 1 TO SHOT-LAST
    ELSE
        MOVE 0 TO SHOT-LAST
    END-IF
    *> muzzle
    IF BU-SHOOTER(BI) > 0
        MOVE BU-SHOOTER(BI) TO OI
        IF OB-ACTIVE(OI) = 0
            EXIT PARAGRAPH
        END-IF
        IF OB-MESH(OI) = 1
            IF FUNCTION MOD(BS, 2) = 0
                MOVE 3.12 TO LX
            ELSE
                MOVE -3.12 TO LX
            END-IF
            MOVE -0.48 TO LY
            MOVE 2.6 TO LZ
        ELSE
            MOVE 0 TO LX
            MOVE -0.1 TO LY
            MOVE 3.1 TO LZ
        END-IF
        PERFORM OBJ-TO-WORLD
    ELSE
        MOVE BU-SX(BI) TO LX
        MOVE BU-SY(BI) TO LY
        MOVE BU-SZ(BI) TO LZ
        PERFORM SCENE-TO-WORLD
    END-IF
    MOVE WX TO MZ-X
    MOVE WY TO MZ-Y
    MOVE WZ TO MZ-Z
    *> aim at where the target will be when the bolt arrives
    MOVE 0.3 TO FT
    PERFORM AIM-POINT
    COMPUTE A1 = (AIM-X - MZ-X) * (AIM-X - MZ-X) + (AIM-Y - MZ-Y) * (AIM-Y - MZ-Y)
        + (AIM-Z - MZ-Z) * (AIM-Z - MZ-Z)
    COMPUTE FT = FUNCTION SQRT(A1)
    COMPUTE FT = FT / BU-SPEED(BI)
    IF FT < 0.04
        MOVE 0.04 TO FT
    END-IF
    PERFORM AIM-POINT
    IF SHOT-LAST = 0 OR BU-HIT(BI) = 0
        PERFORM RANDOM-DIR
        COMPUTE AIM-X = AIM-X + VEC-X * BU-SPREAD(BI)
        COMPUTE AIM-Y = AIM-Y + VEC-Y * BU-SPREAD(BI)
        COMPUTE AIM-Z = AIM-Z + VEC-Z * BU-SPREAD(BI)
    END-IF
    *> a free laser slot
    MOVE 0 TO JX
    PERFORM VARYING KX FROM 1 BY 1 UNTIL KX > MAX-LZ OR JX > 0
        IF LZ-ON(LZ-CURSOR) = 0
            MOVE LZ-CURSOR TO JX
        END-IF
        ADD 1 TO LZ-CURSOR
        IF LZ-CURSOR > MAX-LZ
            MOVE 1 TO LZ-CURSOR
        END-IF
    END-PERFORM
    IF JX = 0
        EXIT PARAGRAPH
    END-IF
    MOVE 1 TO LZ-ON(JX)
    MOVE BU-RAMP(BI) TO LZ-RAMP(JX)
    MOVE MZ-X TO LZ-X(JX)
    MOVE MZ-Y TO LZ-Y(JX)
    MOVE MZ-Z TO LZ-Z(JX)
    COMPUTE LZ-VX(JX) = (AIM-X - MZ-X) / FT
    COMPUTE LZ-VY(JX) = (AIM-Y - MZ-Y) / FT
    COMPUTE LZ-VZ(JX) = (AIM-Z - MZ-Z) / FT
    MOVE 0 TO LZ-AGE(JX) LZ-KILL(JX) LZ-BOOM(JX)
    COMPUTE LZ-K(JX) = 7 / BU-SPEED(BI)
    IF SHOT-LAST = 1 AND BU-HIT(BI) = 1
        MOVE FT TO LZ-LIFE(JX)
        MOVE BU-TARGET(BI) TO LZ-KILL(JX)
        MOVE BU-BOOM(BI) TO LZ-BOOM(JX)
    ELSE
        COMPUTE LZ-LIFE(JX) = FT * 2.2
    END-IF
    MOVE MZ-X TO NP-X
    MOVE MZ-Y TO NP-Y
    MOVE MZ-Z TO NP-Z
    MOVE 0.08 TO NP-LIFE
    MOVE 0.7 TO NP-SIZE
    PERFORM SPAWN-PUFF
    IF EF-NEW > 0
        COMPUTE PT-RAMP(EF-NEW) = BU-RAMP(BI)
    END-IF.

*> where the burst's target is FT seconds from now: AIM-X/Y/Z
AIM-POINT.
    IF BU-TARGET(BI) > 0
        MOVE BU-TARGET(BI) TO PE-OBJ
        IF OB-PATHED(PE-OBJ) = 1
            COMPUTE PE-T = SC-U + FT
            PERFORM EVAL-PATH
            MOVE PE-X TO AIM-X
            MOVE PE-Y TO AIM-Y
            MOVE PE-Z TO AIM-Z
        ELSE
            COMPUTE AIM-X = OB-PX(PE-OBJ) + OB-VX(PE-OBJ) * FT
            COMPUTE AIM-Y = OB-PY(PE-OBJ) + OB-VY(PE-OBJ) * FT
            COMPUTE AIM-Z = OB-PZ(PE-OBJ) + OB-VZ(PE-OBJ) * FT
        END-IF
    ELSE
        MOVE BU-TX(BI) TO LX
        MOVE BU-TY(BI) TO LY
        MOVE BU-TZ(BI) TO LZ
        PERFORM SCENE-TO-WORLD
        MOVE WX TO AIM-X
        MOVE WY TO AIM-Y
        MOVE WZ TO AIM-Z
    END-IF.

*> a point in the current scene's frame (LX LY LZ) to world (WX WY WZ)
SCENE-TO-WORLD.
    EVALUATE FRAME-KIND
        WHEN 0
            MOVE LX TO WX
            MOVE LY TO WY
            MOVE LZ TO WZ
        WHEN 1
            COMPUTE FRAME-W = NOW-T - 12
            COMPUTE ANG = FRAME-W * 0.11
            PERFORM SINCOS
            COMPUTE WX = LX + 260 * SN
            COMPUTE ANG = FRAME-W * 0.17
            PERFORM SINCOS
            COMPUTE WY = LY + 40 * SN + 10
            COMPUTE WZ = LZ + 2000 + 75 * FRAME-W
        WHEN OTHER
            PERFORM CRUISER-TO-WORLD
    END-EVALUATE.

*> X record: explode an object (and remove it if KILL), or explode a
*> point given in an object's frame (OBJ 12/13) or the scene's frame
FIRE-BOOM.
    MOVE BM-SIZE(BI) TO EX-SIZE
    IF BM-OBJ(BI) > 0
        MOVE BM-OBJ(BI) TO OJ
        IF OB-ACTIVE(OJ) = 0
            EXIT PARAGRAPH
        END-IF
        IF BM-KILL(BI) = 1
            PERFORM KILL-OBJECT
            EXIT PARAGRAPH
        END-IF
        MOVE OJ TO OI
        MOVE BM-X(BI) TO LX
        MOVE BM-Y(BI) TO LY
        MOVE BM-Z(BI) TO LZ
        PERFORM OBJ-TO-WORLD
        MOVE OB-VX(OJ) TO EX-VX
        MOVE OB-VY(OJ) TO EX-VY
        MOVE OB-VZ(OJ) TO EX-VZ
    ELSE
        MOVE BM-X(BI) TO LX
        MOVE BM-Y(BI) TO LY
        MOVE BM-Z(BI) TO LZ
        PERFORM SCENE-TO-WORLD
        MOVE 0 TO EX-VX EX-VY EX-VZ
    END-IF
    MOVE WX TO EX-X
    MOVE WY TO EX-Y
    MOVE WZ TO EX-Z
    MOVE 5 TO EX-RAMP
    PERFORM SPAWN-EXPLOSION.

*> ---------------------------------------------------------------------
*>  cameras
*> ---------------------------------------------------------------------
*> behind ship CC-OBJ, in its own frame; CC-UPW mixes in the ship's bank
CHASE-CAMERA.
    MOVE CC-OBJ TO OI
    MOVE CC-SIDE TO LX
    MOVE CC-UP TO LY
    COMPUTE LZ = 0 - CC-BACK
    PERFORM OBJ-TO-WORLD
    MOVE WX TO CAM-PX
    MOVE WY TO CAM-PY
    MOVE WZ TO CAM-PZ
    MOVE 0 TO LX
    MOVE CC-LOOK TO LY
    MOVE CC-AHEAD TO LZ
    PERFORM OBJ-TO-WORLD
    MOVE WX TO CAM-TX
    MOVE WY TO CAM-TY
    MOVE WZ TO CAM-TZ
    COMPUTE CAM-UPX = OB-YX(OI) * CC-UPW
    COMPUTE CAM-UPY = OB-YY(OI) * CC-UPW + (1 - CC-UPW)
    COMPUTE CAM-UPZ = OB-YZ(OI) * CC-UPW.

*> eye on path S99 and target on path S98 of the current scene
PATH-CAMERA.
    MOVE 99 TO PE-OBJ
    MOVE SC-U TO PE-T
    PERFORM EVAL-PATH
    MOVE PE-X TO CAM-PX
    MOVE PE-Y TO CAM-PY
    MOVE PE-Z TO CAM-PZ
    MOVE PE-ROLL TO CAM-ROLL
    MOVE 98 TO PE-OBJ
    PERFORM EVAL-PATH
    MOVE PE-X TO CAM-TX
    MOVE PE-Y TO CAM-TY
    MOVE PE-Z TO CAM-TZ
    IF FRAME-KIND = 2
        MOVE CR-YX TO CAM-UPX
        MOVE CR-YY TO CAM-UPY
        MOVE CR-YZ TO CAM-UPZ
    END-IF.

*> scene-local time window [A1, A2) -> A3 runs 0..1 smoothly
SMOOTH-STEP.
    IF SC-U <= A1
        MOVE 0 TO A3
    ELSE
        IF SC-U >= A2
            MOVE 1 TO A3
        ELSE
            COMPUTE A3 = (SC-U - A1) / (A2 - A1)
            COMPUTE A3 = A3 * A3 * (3 - 2 * A3)
        END-IF
    END-IF.

*> ---------------------------------------------------------------------
*>  1  title
*> ---------------------------------------------------------------------
SCENE-1.
    MOVE 0 TO DUST-ON
    MOVE 0 TO CAM-PX
    COMPUTE CAM-PY = 60 + SC-U * 4
    COMPUTE CAM-PZ = -500 + SC-U * 22
    COMPUTE CAM-TX = -9400 + SC-U * 90
    MOVE 1800 TO CAM-TY
    MOVE 10400 TO CAM-TZ
    MOVE 0 TO A1
    MOVE 1.6 TO A2
    PERFORM SMOOTH-STEP
    MOVE A3 TO FX-FADE
    MOVE 15 TO KX
    IF SC-U > 5.2
        COMPUTE MAGIC-D = 15 - (SC-U - 5.2) * 15 + MAGIC-K
        MOVE MAGIC-LO TO KX
        IF KX < 0
            MOVE 0 TO KX
        END-IF
    END-IF
    MOVE "DATA DIVISION" TO NEW-TEXT
    MOVE 13 TO NEW-LEN
    MOVE 3.6 TO NEW-SCALE
    MOVE 40 TO NEW-TY
    MOVE 1 TO NEW-CENTER
    COMPUTE NEW-COL = 192 + KX
    COMPUTE NEW-GLOW = 112 + KX * 0.6
    COMPUTE NEW-REVEAL = (SC-U - 0.5) * 32
    IF KX > 0
        PERFORM ADD-TEXT
    END-IF
    MOVE "A FLAT SHADED SPACE DEMO IN COBOL" TO NEW-TEXT
    MOVE 33 TO NEW-LEN
    MOVE 1.25 TO NEW-SCALE
    MOVE 84 TO NEW-TY
    COMPUTE NEW-COL = KX * 0.8
    MOVE 0 TO NEW-GLOW
    COMPUTE NEW-REVEAL = (SC-U - 2.3) * 70
    IF KX > 1
        PERFORM ADD-TEXT
    END-IF.

*> ---------------------------------------------------------------------
*>  2  the squadron goes past
*> ---------------------------------------------------------------------
SCENE-2.
    PERFORM PATH-CAMERA.

*> ---------------------------------------------------------------------
*>  3  dogfight: chase camera, swinging out to the side for wave two
*> ---------------------------------------------------------------------
SCENE-3.
    MOVE 2 TO CC-OBJ
    COMPUTE ANG = SC-U * 0.42
    PERFORM SINCOS
    COMPUTE CC-SIDE = SN * 3.5
    COMPUTE CC-BACK = 15 + CS * 1.5
    MOVE 4.4 TO CC-UP
    MOVE 3.7 TO CC-LOOK
    MOVE 34 TO CC-AHEAD
    MOVE 0.55 TO CC-UPW
    IF OB-ACTIVE(2) = 1
        PERFORM CHASE-CAMERA
    END-IF.

*> ---------------------------------------------------------------------
*>  4  cockpit
*> ---------------------------------------------------------------------
SCENE-4.
    MOVE 1 TO HUD-ON
    MOVE 1 TO OB-HIDE(2)
    MOVE 2 TO OI
    MOVE 0 TO LX
    MOVE 0.62 TO LY
    MOVE 1.0 TO LZ
    PERFORM OBJ-TO-WORLD
    MOVE WX TO CAM-PX
    MOVE WY TO CAM-PY
    MOVE WZ TO CAM-PZ
    MOVE 60 TO LZ
    PERFORM OBJ-TO-WORLD
    MOVE WX TO CAM-TX
    MOVE WY TO CAM-TY
    MOVE WZ TO CAM-TZ
    MOVE OB-YX(2) TO CAM-UPX
    MOVE OB-YY(2) TO CAM-UPY
    MOVE OB-YZ(2) TO CAM-UPZ
    MOVE 5.4 TO A1
    MOVE 6.0 TO A2
    PERFORM SMOOTH-STEP
    COMPUTE FX-FADE = 1 - A3.

*> ---------------------------------------------------------------------
*>  5  the cruiser
*> ---------------------------------------------------------------------
SCENE-5.
    PERFORM PATH-CAMERA
    MOVE 0 TO A1
    MOVE 0.8 TO A2
    PERFORM SMOOTH-STEP
    MOVE A3 TO FX-FADE
    IF SC-U > 5.5
        PERFORM FLAK
    END-IF.

*> ---------------------------------------------------------------------
*>  6  the strafing run, chasing the lead fighter along the deck
*> ---------------------------------------------------------------------
SCENE-6.
    IF SC-U < 7.6
        MOVE 2 TO CC-OBJ
        MOVE 12.5 TO CC-BACK
        MOVE 3.5 TO CC-UP
        MOVE 3.0 TO CC-LOOK
        MOVE 0 TO CC-SIDE
        MOVE 28 TO CC-AHEAD
        MOVE 0.5 TO CC-UPW
        IF OB-ACTIVE(2) = 1
            PERFORM CHASE-CAMERA
        END-IF
    ELSE
        *> above the bow, looking back at the reactor going up
        MOVE 45 TO LX
        MOVE 75 TO LY
        MOVE 210 TO LZ
        PERFORM CRUISER-TO-WORLD
        MOVE WX TO CAM-PX
        MOVE WY TO CAM-PY
        MOVE WZ TO CAM-PZ
        MOVE 0 TO LX
        MOVE 22 TO LY
        MOVE 60 TO LZ
        PERFORM CRUISER-TO-WORLD
        MOVE WX TO CAM-TX
        MOVE WY TO CAM-TY
        MOVE WZ TO CAM-TZ
        MOVE CR-YX TO CAM-UPX
        MOVE CR-YY TO CAM-UPY
        MOVE CR-YZ TO CAM-UPZ
    END-IF
    IF SC-U < 7.5
        PERFORM FLAK
    END-IF.

*> turret flak: puffs above the deck around the lead fighter
FLAK.
    PERFORM NEXT-RANDOM
    IF RND < 0.13
        PERFORM RANDOM-DIR
        PERFORM NEXT-RANDOM
        COMPUTE A1 = 16 + RND * 34
        COMPUTE NP-X = OB-PX(2) + VEC-X * A1 + OB-VX(2) * 1.1
        COMPUTE NP-Y = OB-PY(2) + VEC-Y * A1 * 0.3 + 9
        COMPUTE NP-Z = OB-PZ(2) + VEC-Z * A1 + OB-VZ(2) * 1.1
        PERFORM NEXT-RANDOM
        COMPUTE NP-SIZE = 1.4 + RND * 1.4
        MOVE 0.55 TO NP-LIFE
        PERFORM SPAWN-PUFF
        MOVE 4 TO NP-TYPE
        MOVE 6 TO NP-RAMP
        COMPUTE NP-SIZE = NP-SIZE * 1.2
        MOVE 1.6 TO NP-LIFE
        MOVE 0.15 TO NP-DELAY
        PERFORM SPAWN-PARTICLE
    END-IF.

*> ---------------------------------------------------------------------
*>  7  the cruiser comes apart
*> ---------------------------------------------------------------------
SCENE-7.
    PERFORM PATH-CAMERA
    MOVE 3.2 TO EVT
    PERFORM AT-TIME
    IF EV-HIT = 1
        PERFORM BREAK-CRUISER
    END-IF
    MOVE 6.4 TO EVT
    PERFORM AT-TIME
    IF EV-HIT = 1
        PERFORM VAPORISE-CRUISER
    END-IF
    MOVE 10.6 TO A1
    MOVE 12.0 TO A2
    PERFORM SMOOTH-STEP
    COMPUTE FX-FADE = 1 - A3.

AT-TIME.
    IF EVT >= SC-U AND EVT < SC-U + DT
        MOVE 1 TO EV-HIT
    ELSE
        MOVE 0 TO EV-HIT
    END-IF.

*> the hull splits at the reactor: both halves drift and tumble apart
BREAK-CRUISER.
    MOVE 1 TO OB-BROKEN(12) OB-BROKEN(13)
    MOVE 1 TO OB-DRIFT(12) OB-DRIFT(13)
    COMPUTE OB-VX(13) = CR-ZX * 14 - CR-YX * 5
    COMPUTE OB-VY(13) = CR-ZY * 14 - CR-YY * 5
    COMPUTE OB-VZ(13) = CR-ZZ * 14 - CR-YZ * 5
    MOVE CR-XX TO OB-WX(13)
    MOVE CR-XY TO OB-WY(13)
    MOVE CR-XZ TO OB-WZ(13)
    MOVE 0.09 TO OB-WRATE(13)
    COMPUTE OB-VX(12) = CR-ZX * 2 + CR-YX * 2
    COMPUTE OB-VY(12) = CR-ZY * 2 + CR-YY * 2
    COMPUTE OB-VZ(12) = CR-ZZ * 2 + CR-YZ * 2
    MOVE CR-XX TO OB-WX(12)
    MOVE CR-XY TO OB-WY(12)
    MOVE CR-XZ TO OB-WZ(12)
    MOVE -0.05 TO OB-WRATE(12)
    MOVE CR-QX TO EX-X
    MOVE CR-QY TO EX-Y
    MOVE CR-QZ TO EX-Z
    MOVE 0 TO EX-VX EX-VY EX-VZ
    MOVE 40 TO EX-SIZE
    MOVE 5 TO EX-RAMP
    PERFORM SPAWN-EXPLOSION.

*> the big one: white-out, and the halves become flying wreckage
VAPORISE-CRUISER.
    MOVE 1 TO FX-FLASH
    MOVE 0.75 TO FX-FLASH-RATE
    MOVE 6 TO FX-SHAKE
    MOVE OB-PX(12) TO EX-X
    MOVE OB-PY(12) TO EX-Y
    MOVE OB-PZ(12) TO EX-Z
    MOVE 0 TO EX-VX EX-VY EX-VZ
    MOVE 90 TO EX-SIZE
    MOVE 5 TO EX-RAMP
    PERFORM SPAWN-EXPLOSION
    PERFORM VARYING OJ FROM 14 BY 1 UNTIL OJ > 25
        MOVE 1 TO OB-ACTIVE(OJ)
        MOVE 1 TO OB-DRIFT(OJ)
        MOVE 4 TO OB-LAYER(OJ)
        PERFORM RANDOM-DIR
        PERFORM NEXT-RANDOM
        COMPUTE A1 = 40 + RND * 120
        IF OJ < 20
            MOVE 13 TO OI
        ELSE
            MOVE 12 TO OI
        END-IF
        COMPUTE OB-PX(OJ) = OB-PX(OI) + VEC-X * 25 + OB-ZX(OI) * (OJ - 19.5) * 30
        COMPUTE OB-PY(OJ) = OB-PY(OI) + VEC-Y * 25 + OB-ZY(OI) * (OJ - 19.5) * 30
        COMPUTE OB-PZ(OJ) = OB-PZ(OI) + VEC-Z * 25 + OB-ZZ(OI) * (OJ - 19.5) * 30
        COMPUTE OB-VX(OJ) = VEC-X * A1 * 0.35
        COMPUTE OB-VY(OJ) = VEC-Y * A1 * 0.35
        COMPUTE OB-VZ(OJ) = VEC-Z * A1 * 0.35
        PERFORM NEXT-RANDOM
        COMPUTE OB-SCALE(OJ) = 1.2 + RND * 2.2
        PERFORM RANDOM-DIR
        MOVE VEC-X TO OB-WX(OJ)
        MOVE VEC-Y TO OB-WY(OJ)
        MOVE VEC-Z TO OB-WZ(OJ)
        PERFORM NEXT-RANDOM
        COMPUTE OB-WRATE(OJ) = 0.4 + RND * 1.6
        MOVE OJ TO OI
        PERFORM RANDOM-DIR
        MOVE VEC-X TO OR-FX
        MOVE VEC-Y TO OR-FY
        MOVE VEC-Z TO OR-FZ
        MOVE 0 TO OR-ROLL
        PERFORM ORIENT-OBJECT
    END-PERFORM
    MOVE 0 TO OB-ACTIVE(12) OB-ACTIVE(13).

*> ---------------------------------------------------------------------
*>  8  home, and the credits
*> ---------------------------------------------------------------------
SCENE-8.
    PERFORM PATH-CAMERA
    MOVE 0 TO A1
    MOVE 1.0 TO A2
    PERFORM SMOOTH-STEP
    MOVE A3 TO FX-FADE
    MOVE 8.6 TO A1
    MOVE 10.0 TO A2
    PERFORM SMOOTH-STEP
    COMPUTE FX-FADE = FX-FADE * (1 - A3)
    MOVE 1 TO NEW-CENTER
    MOVE 0 TO NEW-GLOW
    IF SC-U > 1.0 AND SC-U < 5.4
        MOVE "WRITTEN IN COBOL" TO NEW-TEXT
        MOVE 16 TO NEW-LEN
        MOVE 2 TO NEW-SCALE
        MOVE 40 TO NEW-TY
        MOVE 207 TO NEW-COL
        MOVE 119 TO NEW-GLOW
        COMPUTE NEW-REVEAL = (SC-U - 1.0) * 40
        PERFORM ADD-TEXT
        MOVE 0 TO NEW-GLOW
    END-IF
    IF SC-U > 2.0 AND SC-U < 5.4
        MOVE "COMPILED WITH YACCC" TO NEW-TEXT
        MOVE 19 TO NEW-LEN
        MOVE 1.25 TO NEW-SCALE
        MOVE 64 TO NEW-TY
        MOVE 12 TO NEW-COL
        COMPUTE NEW-REVEAL = (SC-U - 2.0) * 60
        PERFORM ADD-TEXT
    END-IF
    IF SC-U > 5.8
        MOVE "THE END" TO NEW-TEXT
        MOVE 7 TO NEW-LEN
        MOVE 3 TO NEW-SCALE
        MOVE 52 TO NEW-TY
        MOVE 207 TO NEW-COL
        MOVE 119 TO NEW-GLOW
        COMPUTE NEW-REVEAL = (SC-U - 5.8) * 30
        PERFORM ADD-TEXT
    END-IF.
