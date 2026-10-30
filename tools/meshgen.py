#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate models.dat for SPACE.cob.

Every model is a set of convex parts. A part is the convex hull of a point
set; coplanar hull triangles are merged into convex polygons whose vertices
run clockwise seen from outside, so (B-A) x (C-A) points out of the solid.
The COBOL program sorts whole parts by depth (painter's algorithm), so a
part never needs internal sorting: back-face culling settles a convex solid.

Parts glued onto a big hull carry a "mount plane". The renderer draws such a
part after the hull when the camera is on the outside of that plane and
before the hull otherwise, which is how the cruiser's decks, towers and
turrets stay in front of (or hidden behind) its hull without a z-buffer.

Record layout (one line per record, fixed columns, read by an FD):
  col 1        record type  M mesh, P part, V vertex, F face, G glow sprite
  col 2-109    12 fields of S9(5)V9(3) SIGN LEADING SEPARATE (9 chars each)

  M  id, bounding radius
  P  centre x y z, mounted (0/1), plane normal x y z, plane d
  V  x y z
  F  vertex count, v1..v6 (1-based within the mesh), ramp, flags, part, shade
  G  x y z, size, ramp, shade
"""
import math
import random
import sys

import numpy as np
from scipy.spatial import ConvexHull

EMIT = 1        # face colour is its fixed shade, no lighting
TWO_SIDED = 2   # never back-face culled
CAP = 4         # only drawn once the object has broken apart

# palette ramps (see the COBOL program's RAMP-DATA)
R_GRAY, R_HULL, R_BLUE, R_GUN, R_RED, R_STEEL, R_DARK, R_FIRE = range(8)
R_LGREEN, R_LRED, R_TAN, R_RUST, R_CREAM, R_RING, R_HUD, R_GLASS = range(8, 16)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


class Mesh:
    def __init__(self, ident):
        self.ident = ident
        self.verts = []
        self.vindex = {}
        self.faces = []
        self.parts = []
        self.glows = []

    def part(self, center, mount=None):
        """mount: (normal, point on plane) or None."""
        self.parts.append((tuple(center), mount))
        return len(self.parts)

    def vertex(self, p):
        key = tuple(int(round(float(c) * 1000)) for c in p)
        if key not in self.vindex:
            self.verts.append(tuple(k / 1000.0 for k in key))
            self.vindex[key] = len(self.verts)
        return self.vindex[key]

    def face(self, idx, ramp, flags, part, shade=0):
        assert 3 <= len(idx) <= 6, idx
        self.faces.append((list(idx), ramp, flags, part, shade))

    def glow(self, p, size, ramp, shade):
        self.glows.append((tuple(p), size, ramp, shade))

    def radius(self):
        r = max(np.linalg.norm(v) for v in self.verts)
        for p, s, _, _ in self.glows:
            r = max(r, np.linalg.norm(p) + s)
        return r


def hull_polygons(points):
    """Convex polygons (outward normal, ordered vertex coordinates)."""
    pts = np.array(points, float)
    h = ConvexHull(pts)
    groups = []
    scale = np.abs(pts).max() + 1.0
    for simplex, eq in zip(h.simplices, h.equations):
        n, d = eq[:3], eq[3]
        for g in groups:
            if np.dot(g[0], n) > 1 - 1e-7 and abs(g[1] - d) < 1e-6 * scale:
                g[2].update(simplex)
                break
        else:
            groups.append((n, d, set(simplex)))
    polys = []
    for n, d, idx in groups:
        p = pts[list(idx)]
        c = p.mean(axis=0)
        u = unit(p[0] - c)
        v = np.cross(n, u)
        ang = [math.atan2(np.dot(q - c, v), np.dot(q - c, u)) for q in p]
        order = [p[i] for i in np.argsort(ang)]
        # drop collinear points
        clean = []
        m = len(order)
        for i in range(m):
            a, b, cc = order[i - 1], order[i], order[(i + 1) % m]
            if np.linalg.norm(np.cross(b - a, cc - b)) > 1e-9 * scale * scale:
                clean.append(b)
        poly = clean
        newell = np.zeros(3)
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            newell += np.array([(a[1] - b[1]) * (a[2] + b[2]),
                                (a[2] - b[2]) * (a[0] + b[0]),
                                (a[0] - b[0]) * (a[1] + b[1])])
        if np.dot(newell, n) < 0:
            poly = poly[::-1]
        polys.append((np.array(n), poly))
    return polys


def split_poly(poly):
    """Polygons over 6 vertices become a fan of quads/triangles."""
    out = []
    i = 1
    while i < len(poly) - 1:
        piece = [poly[0]] + poly[i:i + 3]
        if len(piece) < 3:
            break
        out.append(piece)
        i += 2
    return [p for p in out if len(p) >= 3]


def add_convex(mesh, points, rule, mount=None, center=None):
    """rule(normal) -> (ramp, flags, shade)."""
    pts = np.array(points, float)
    pid = mesh.part(center if center is not None else pts.mean(axis=0), mount)
    for n, poly in hull_polygons(points):
        ramp, flags, shade = rule(n)
        pieces = [poly] if len(poly) <= 6 else split_poly(poly)
        for piece in pieces:
            idx = [mesh.vertex(q) for q in piece]
            mesh.face(idx, ramp, flags, pid, shade)
    return pid


def add_flat(mesh, poly, ramp, flags=0, shade=0, mount=None, normal=None):
    """A single polygon (decal). Vertices are reordered clockwise seen from
    the side the normal points to."""
    poly = [np.array(p, float) for p in poly]
    newell = np.zeros(3)
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        newell += np.array([(a[1] - b[1]) * (a[2] + b[2]),
                            (a[2] - b[2]) * (a[0] + b[0]),
                            (a[0] - b[0]) * (a[1] + b[1])])
    if normal is not None and np.dot(newell, normal) < 0:
        poly = poly[::-1]
    pid = mesh.part(np.mean(poly, axis=0), mount)
    idx = [mesh.vertex(q) for q in poly]
    mesh.face(idx, ramp, flags, pid, shade)
    return pid


def solid(ramp):
    return lambda n: (ramp, 0, 0)


def box(x0, x1, y0, y1, z0, z1):
    return [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def prism_z(cx, cy, z0, r0, z1, r1, n=8, rot=math.pi / 8):
    pts = []
    for z, r in ((z0, r0), (z1, r1)):
        for k in range(n):
            a = rot + 2 * math.pi * k / n
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), z))
    return pts


def mirror(points):
    return [(-x, y, z) for x, y, z in points]


def section(z, w, h, b):
    """Beveled rectangle cross-section at z."""
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts.append((sx * w, sy * (h - b), z))
            pts.append((sx * (w - b), sy * h, z))
    return pts


UP = (0, 1, 0)
DOWN = (0, -1, 0)


def plane(normal, point):
    return (unit(normal), np.asarray(point, float))


# --------------------------------------------------------------- fighters
def build_kestrel(ident):
    """Friendly interceptor: dart fuselage, anhedral wings, twin pods."""
    m = Mesh(ident)
    fus = [(0, 0.05, 3.6)]
    for z, s in ((1.6, 0.8), (-1.0, 1.0), (-2.6, 0.8)):
        fus += [(0.7 * s, 0.0, z), (-0.7 * s, 0.0, z), (0.5 * s, 0.48 * s, z),
                (-0.5 * s, 0.48 * s, z), (0, 0.6 * s, z), (0.45 * s, -0.38 * s, z),
                (-0.45 * s, -0.38 * s, z), (0, -0.45 * s, z)]

    def fus_rule(n):
        if n[2] < -0.9:
            return (R_DARK, 0, 0)
        if n[1] < -0.6:
            return (R_BLUE, 0, 0)
        return (R_HULL, 0, 0)
    add_convex(m, fus, fus_rule)
    canopy = [(0, 0.47, 1.9), (0.22, 0.40, 1.3), (-0.22, 0.40, 1.3), (0, 0.74, 0.8),
              (0.28, 0.48, 0.3), (-0.28, 0.48, 0.3), (0, 0.68, -0.2), (0.2, 0.55, -0.7),
              (-0.2, 0.55, -0.7), (0, 0.6, -0.8)]
    add_convex(m, canopy, solid(R_GLASS))
    wing = [(0.55, 0.06, 0.9), (0.55, -0.06, 0.9), (0.65, 0.06, -2.1), (0.65, -0.06, -2.1),
            (3.1, -0.42, -0.9), (3.1, -0.54, -0.9), (3.1, -0.42, -2.0), (3.1, -0.54, -2.0)]

    def wing_rule(n):
        return (R_BLUE, 0, 0) if n[1] > 0.5 else (R_HULL, 0, 0)
    for side in (1, -1):
        w = wing if side == 1 else mirror(wing)
        add_convex(m, w, wing_rule)
        pod = prism_z(1.15 * side, -0.12, 0.6, 0.2, -0.5, 0.36) + \
            prism_z(1.15 * side, -0.12, -2.6, 0.36, -2.9, 0.28)

        def pod_rule(n):
            if n[2] < -0.95:
                return (R_FIRE, EMIT, 13)
            return (R_DARK, 0, 0)
        add_convex(m, pod, pod_rule)
        m.glow((1.15 * side, -0.12, -3.05), 0.30, R_FIRE, 12)
        gun = box(3.02, 3.22, -0.56, -0.40, -1.4, 1.7)
        add_convex(m, gun if side == 1 else mirror(gun), solid(R_DARK))
        barrel = box(3.08, 3.16, -0.52, -0.44, 1.7, 2.5)
        add_convex(m, barrel if side == 1 else mirror(barrel), solid(R_GRAY))
        fin = [(1.0, 0.18, -1.3), (1.05, 0.18, -2.75), (1.4, 0.98, -2.55), (1.37, 0.98, -2.05)]
        fin = fin + [(x + 0.07, y - 0.02, z) for x, y, z in fin]
        add_convex(m, fin if side == 1 else mirror(fin), solid(R_BLUE))
    return m


def build_wraith(ident):
    """Enemy flying wing: arrowhead body, spine, trailing-edge engines."""
    m = Mesh(ident)
    body = [(0, 0.05, 3.0), (0, 0.32, 1.0), (0, 0.42, -0.6), (0, 0.3, -1.4),
            (0.9, 0.18, 0.4), (-0.9, 0.18, 0.4), (2.9, -0.12, -1.3), (-2.9, -0.12, -1.3),
            (2.6, -0.14, -1.75), (-2.6, -0.14, -1.75), (0.8, 0.0, -1.55), (-0.8, 0.0, -1.55),
            (0, -0.25, 1.0), (0, -0.32, -0.8), (0.9, -0.14, 0.0), (-0.9, -0.14, 0.0),
            (2.7, -0.24, -1.4), (-2.7, -0.24, -1.4)]

    def body_rule(n):
        if n[1] < -0.5:
            return (R_RED, 0, 0)
        return (R_GUN, 0, 0)
    add_convex(m, body, body_rule)
    spine = [(0, 0.3, 1.7), (0.2, 0.36, 0.8), (-0.2, 0.36, 0.8), (0, 0.62, 0.2),
             (0.22, 0.44, -0.4), (-0.22, 0.44, -0.4), (0, 0.55, -1.1), (0, 0.38, -1.3)]
    add_convex(m, spine, solid(R_RED))
    for side in (1, -1):
        eng = box(0.45, 1.05, -0.2, 0.2, -1.95, -0.7)
        eng = eng if side == 1 else mirror(eng)

        def eng_rule(n):
            if n[2] < -0.95:
                return (R_LRED, EMIT, 14)
            return (R_GUN, 0, 0)
        add_convex(m, eng, eng_rule)
        m.glow((0.75 * side, 0.0, -2.1), 0.24, R_LRED, 12)
        fin = [(2.72, -0.12, -1.65), (2.72, -0.12, -0.95), (2.78, -0.78, -1.5), (2.78, -0.78, -1.15)]
        fin = fin + [(x + 0.08, y, z) for x, y, z in fin]
        add_convex(m, fin if side == 1 else mirror(fin), solid(R_RED))
        m.glow((0.24 * side, 0.3, 1.45), 0.12, R_LRED, 15)
    return m


# ---------------------------------------------------------------- cruiser
STERN_DECK = plane(UP, (0, 20, 0))


def deck_plane_bow(z):
    """Top hull plane of the bow segment that contains z."""
    if z <= 120:
        a, b = np.array([0, 20, 0.0]), np.array([0, 18, 120.0])
    else:
        a, b = np.array([0, 18, 120.0]), np.array([0, 12, 200.0])
    t = unit(b - a)
    n = unit(np.cross(t, (1, 0, 0)))
    if n[1] < 0:
        n = -n
    return n, a


def deck_y_bow(z):
    if z <= 120:
        return 20 - 2 * z / 120
    return 18 - 6 * (z - 120) / 80


def turret(m, x, z, y, mount, big=False):
    """Base, rotating head and twin barrels pointing forward (+z)."""
    s = 1.8 if big else 1.0
    base = box(x - 4 * s, x + 4 * s, y - 0.6, y + 4 * s, z - 4 * s, z + 4 * s)
    add_convex(m, base, solid(R_DARK), mount=mount)
    top = y + 4 * s
    head_mount = plane(UP, (x, top, z))
    head = box(x - 3 * s, x + 3 * s, top, top + 2.6 * s, z - 3 * s, z + 3 * s)
    add_convex(m, head, solid(R_STEEL), mount=head_mount)
    for dx in (-1.1 * s, 1.1 * s):
        b = box(x + dx - 0.45 * s, x + dx + 0.45 * s, top + 0.8 * s, top + 1.7 * s,
                z + 3 * s, z + 3 * s + 8 * s)
        add_convex(m, b, solid(R_GRAY), mount=head_mount)


def runway(m, x0, x1, z0, z1, deck_y, mount, step=14.0):
    """Dark deck plates plus amber guide lights for the strafing run."""
    z = z0
    k = 0
    while z + 10 <= z1:
        y, y2 = deck_y(z) + 0.06, deck_y(z + 10) + 0.06
        add_flat(m, [(x0, y, z), (x1, y, z), (x1, y2, z + 10), (x0, y2, z + 10)],
                 R_DARK, 0, 0, mount=mount, normal=UP)
        for lx in (x0 - 1.2, x1 + 1.2):
            ly = deck_y(z + 1) + 0.08
            add_flat(m, [(lx - 0.5, ly, z), (lx + 0.5, ly, z), (lx + 0.5, ly, z + 2),
                         (lx - 0.5, ly, z + 2)], R_FIRE, EMIT, 9 if k % 2 else 7,
                     mount=mount, normal=UP)
        z += step
        k += 1


def build_stern(ident):
    m = Mesh(ident)
    hull = section(-225, 42, 17, 6) + section(-215, 46, 20, 7) + section(0, 46, 20, 7)

    def hull_rule(n):
        if n[2] > 0.99:
            return (R_FIRE, EMIT | CAP, 6)
        return (R_STEEL, 0, 0)
    add_convex(m, hull, hull_rule, center=(0, 0, -110))
    deck = STERN_DECK
    # superstructure
    add_convex(m, box(-20, 20, 19.5, 32, -190, -10), solid(R_STEEL), mount=deck)
    add_convex(m, box(-14, 14, 31.5, 42, -170, -40), solid(R_STEEL), mount=plane(UP, (0, 32, 0)))
    add_convex(m, box(-6, 6, 41.5, 64, -150, -130), solid(R_DARK), mount=plane(UP, (0, 42, 0)))
    add_convex(m, box(-16, 16, 63.5, 72, -153, -127), solid(R_STEEL), mount=plane(UP, (0, 64, 0)))
    add_convex(m, box(-14, 14, 67, 69.5, -127, -126.4), lambda n: (R_GLASS, EMIT, 13),
               mount=plane((0, 0, 1), (0, 0, -127)))
    add_convex(m, box(-0.6, 0.6, 72, 92, -141, -139.8), solid(R_DARK), mount=plane(UP, (0, 72, 0)))
    add_convex(m, box(-6, 6, 86, 87, -141, -140), solid(R_DARK), mount=plane(UP, (0, 72, 0)))
    for side in (1, -1):
        sx = side
        for z in (-175, -135, -95, -55):
            v = box(20, 21.6, 23, 29, z, z + 14)
            add_convex(m, v if side == 1 else mirror(v), solid(R_DARK),
                       mount=plane((sx, 0, 0), (20 * sx, 0, 0)))
        for z in (-175, -135, -95, -55, -15):
            turret(m, 37 * sx, z, 20, deck)
        # sponson with side guns
        sp = box(46, 53, -9, 7, -170, -30)
        add_convex(m, sp if side == 1 else mirror(sp), solid(R_STEEL),
                   mount=plane((sx, 0, 0), (46 * sx, 0, 0)))
        for z in (-150, -100, -50):
            g = box(53, 57, -3, 3, z - 3, z + 3)
            add_convex(m, g if side == 1 else mirror(g), solid(R_DARK),
                       mount=plane((sx, 0, 0), (53 * sx, 0, 0)))
            b = box(57, 64, -0.5, 0.5, z - 0.5, z + 0.5)
            add_convex(m, b if side == 1 else mirror(b), solid(R_GRAY),
                       mount=plane((sx, 0, 0), (53 * sx, 0, 0)))
    # a red band and rows of lit windows down both flanks
    for side in (1, -1):
        sx = side
        n = (sx, 0, 0)
        mnt = plane(n, (46 * sx, 0, 0))
        x = 46.05 * sx
        add_flat(m, [(x, 9.2, -212), (x, 11.0, -212), (x, 11.0, -4), (x, 9.2, -4)],
                 R_RED, 0, 0, mount=mnt, normal=n)
        for row, y in enumerate((4.5, 0.5, -3.5)):
            z = -208 + row * 3
            while z + 8 < -6:
                if (int(z) // 9 + row) % 4 != 0:
                    add_flat(m, [(x, y, z), (x, y + 1.3, z), (x, y + 1.3, z + 7), (x, y, z + 7)],
                             R_CREAM, EMIT, 12 if row != 1 else 10, mount=mnt, normal=n)
                z += 9
    # strafing lanes either side of the superstructure
    runway(m, 24.5, 30.5, -210, -2, lambda z: 20.0, deck)
    runway(m, -30.5, -24.5, -210, -2, lambda z: 20.0, deck)
    # keel and hangar light
    add_convex(m, box(-12, 12, -32, -19.5, -205, -15), solid(R_DARK), mount=plane(DOWN, (0, -20, 0)))
    add_flat(m, [(-9, -32.06, -120), (9, -32.06, -120), (9, -32.06, -60), (-9, -32.06, -60)],
             R_GLASS, EMIT, 9, mount=plane(DOWN, (0, -32, 0)), normal=DOWN)
    # engine block and nozzles
    rear = plane((0, 0, -1), (0, 0, -225))
    add_convex(m, box(-30, 30, -13, 13, -240, -224.5), solid(R_DARK), mount=rear)
    for cx in (-15, 15):
        for cy in (-6.5, 6.5):
            def noz(n):
                if n[2] < -0.95:
                    return (R_FIRE, EMIT, 14)
                return (R_STEEL, 0, 0)
            add_convex(m, prism_z(cx, cy, -240.5, 6, -252, 7.5), noz,
                       mount=plane((0, 0, -1), (0, 0, -240)))
            m.glow((cx, cy, -255), 6.5, R_FIRE, 12)
    return m


def build_bow(ident):
    m = Mesh(ident)
    hull = section(0, 46, 20, 7) + section(120, 40, 18, 6) + section(200, 22, 12, 5) + \
        section(232, 6, 5, 2)

    def hull_rule(n):
        if n[2] < -0.99:
            return (R_FIRE, EMIT | CAP, 6)
        return (R_STEEL, 0, 0)
    add_convex(m, hull, hull_rule, center=(0, 0, 100))
    # flank band and windows on the first bow segment (side plane tapers)
    for side in (1, -1):
        sx = side

        def wx(z, off=0.05):
            return sx * (46 - 6 * z / 120 + off)
        a, b = np.array([wx(0, 0), 0, 0]), np.array([wx(120, 0), 0, 120])
        n = unit(np.cross((0, 1, 0), b - a)) * (1 if sx > 0 else -1)
        if n[0] * sx < 0:
            n = -n
        mnt = (n, a)
        add_flat(m, [(wx(2), 9.2, 2), (wx(2), 11.0, 2), (wx(110), 10.5, 110), (wx(110), 8.8, 110)],
                 R_RED, 0, 0, mount=mnt, normal=n)
        for row, y in enumerate((4.5, 0.5, -3.5)):
            z = 4 + row * 3
            while z + 8 < 112:
                if (int(z) // 9 + row) % 4 != 0:
                    add_flat(m, [(wx(z), y, z), (wx(z), y + 1.3, z), (wx(z + 7), y + 1.3, z + 7),
                                 (wx(z + 7), y, z + 7)], R_CREAM, EMIT, 12 if row != 1 else 10,
                             mount=mnt, normal=n)
                z += 9
    # reactor: raised frame around a glowing vent
    zc0, zc1 = 48.0, 82.0
    mount = deck_plane_bow(65)
    y0 = deck_y_bow(zc1) - 0.6
    yt = deck_y_bow(zc0) + 2.6
    for part in (box(-13, -8, y0, yt, zc0, zc1), box(8, 13, y0, yt, zc0, zc1),
                 box(-8, 8, y0, yt, zc1 - 4, zc1), box(-8, 8, y0, yt, zc0, zc0 + 4)):
        add_convex(m, part, solid(R_DARK), mount=mount)
    vy0, vy1 = deck_y_bow(zc0 + 4) + 0.35, deck_y_bow(zc1 - 4) + 0.35
    add_flat(m, [(-8, vy0, zc0 + 4), (8, vy0, zc0 + 4), (8, vy1, zc1 - 4), (-8, vy1, zc1 - 4)],
             R_FIRE, EMIT, 10, mount=mount, normal=UP)
    for side in (1, -1):
        turret(m, 36 * side, 14, deck_y_bow(14), deck_plane_bow(14))
        turret(m, 31 * side, 104, deck_y_bow(104), deck_plane_bow(104))
        x0, x1 = (24.5, 30.5) if side == 1 else (-30.5, -24.5)
        runway(m, x0, x1, 2, 92, deck_y_bow, deck_plane_bow(60))
    for z in (125, 160):
        turret(m, 0, z, deck_y_bow(z), deck_plane_bow(z), big=True)
    return m


# ----------------------------------------------------------------- planet
def build_planet(ident):
    """Banded giant with a two-band ring; unit radius (object scale sets it)."""
    m = Mesh(ident)
    nlon, nlat = 24, 14
    bands = [R_CREAM, R_TAN, R_TAN, R_RUST, R_CREAM, R_TAN, R_RUST,
             R_RUST, R_TAN, R_CREAM, R_TAN, R_RUST, R_TAN, R_CREAM]
    pid = m.part((0, 0, 0))

    def pt(i, j):
        lat = -math.pi / 2 + math.pi * i / nlat
        lon = 2 * math.pi * j / nlon
        return (math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon))
    for i in range(nlat):
        for j in range(nlon):
            a, b = pt(i, j), pt(i, j + 1)
            c, d = pt(i + 1, j + 1), pt(i + 1, j)
            if i == 0:
                poly = [a, d, c]
            elif i == nlat - 1:
                poly = [a, b, c]
            else:
                poly = [a, b, c, d]
            poly = [np.array(p) for p in poly]
            cen = np.mean(poly, axis=0)
            newell = np.zeros(3)
            for k in range(len(poly)):
                p, q = poly[k], poly[(k + 1) % len(poly)]
                newell += np.array([(p[1] - q[1]) * (p[2] + q[2]), (p[2] - q[2]) * (p[0] + q[0]),
                                    (p[0] - q[0]) * (p[1] + q[1])])
            if np.dot(newell, cen) < 0:
                poly = poly[::-1]
            ramp = bands[i]
            if i == 5 and j in (7, 8):
                ramp = R_RUST
            idx = [m.vertex(p) for p in poly]
            m.face(idx, ramp, 0, pid, 0)
    nseg = 48
    for (r0, r1, ramp) in ((1.38, 1.72, R_TAN), (1.78, 2.15, R_RING)):
        for j in range(nseg):
            a0 = 2 * math.pi * j / nseg
            a1 = 2 * math.pi * (j + 1) / nseg
            quad = [(r0 * math.cos(a0), 0, r0 * math.sin(a0)), (r1 * math.cos(a0), 0, r1 * math.sin(a0)),
                    (r1 * math.cos(a1), 0, r1 * math.sin(a1)), (r0 * math.cos(a1), 0, r0 * math.sin(a1))]
            add_flat(m, quad, ramp, TWO_SIDED, 0, normal=UP)
    return m


def build_chunk(ident, seed):
    """Irregular hull fragment for the cruiser break-up."""
    rnd = random.Random(seed)
    m = Mesh(ident)
    pts = []
    for _ in range(11):
        pts.append((rnd.uniform(-5, 5), rnd.uniform(-3.5, 3.5), rnd.uniform(-7, 7)))

    def rule(n):
        return (R_DARK, 0, 0) if n[1] < -0.3 else (R_STEEL, 0, 0)
    add_convex(m, pts, rule, center=(0, 0, 0))
    return m


def fmt(v):
    n = int(round(v * 1000))
    if abs(n) > 99999999:
        raise ValueError(f"value out of range: {v}")
    return ('+' if n >= 0 else '-') + f"{abs(n):08d}"


def record(kind, fields):
    fields = list(fields) + [0] * (12 - len(fields))
    return kind + ''.join(fmt(f) for f in fields)


def emit(meshes, out):
    lines = []
    for m in meshes:
        lines.append(record('M', [m.ident, m.radius()]))
        for center, mount in m.parts:
            if mount is None:
                lines.append(record('P', list(center) + [0]))
            else:
                n, p = mount
                lines.append(record('P', list(center) + [1] + list(n) + [float(np.dot(n, p))]))
        for v in m.verts:
            lines.append(record('V', v))
        for idx, ramp, flags, part, shade in m.faces:
            vs = idx + [0] * (6 - len(idx))
            lines.append(record('F', [len(idx)] + vs + [ramp, flags, part, shade]))
        for p, s, ramp, shade in m.glows:
            lines.append(record('G', list(p) + [s, ramp, shade]))
    with open(out, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    return lines


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'models.dat'
    meshes = [build_kestrel(1), build_wraith(2), build_bow(3), build_stern(4),
              build_planet(5), build_chunk(6, 11), build_chunk(7, 23), build_chunk(8, 37)]
    lines = emit(meshes, out)
    for m in meshes:
        print(f"mesh {m.ident}: {len(m.verts)} vertices, {len(m.faces)} faces, "
              f"{len(m.parts)} parts, {len(m.glows)} glows, radius {m.radius():.1f}",
              file=sys.stderr)
    print(f"{len(lines)} records -> {out}", file=sys.stderr)


if __name__ == '__main__':
    main()
