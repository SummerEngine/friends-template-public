#!/usr/bin/env python3
"""Generate the carried items: the glass pane (the default) and the two paintings (a small landscape, a big gilded
wedding portrait).

Writes demo/assets/paintings/painting_items.json: for each item a set of low-poly flat-shaded pieces. A painting is frame
bars and corners, torn canvas pieces and a cover of glass shards; the glass pane is angular shards cut from one sheet
(a few cracks through an impact point, then straight cuts) inside a metal edge strip and two rubber end caps where the
hands grip. Vertex colours index a per-item palette; canvas faces carry UVs into assets/paintings/painting_atlas.png,
pane faces UVs over the whole pane (the shader draws the etched print from them). The intact item is the union of the
pieces at rest, so one data set draws both the carried item and the break (style/carry_item.gd, game/painting_shards.gd).
Pure standard library; deterministic (seeded), re-run to reproduce:

    python3 tools/build_painting_items.py            # writes the file above
    python3 tools/build_painting_items.py --check    # fail if the file on disk differs

Frame: x = across the painting (the walking direction, the gameplay camera is behind, at -x), y = up (the face
normal), z = along the carry axis (between the two carriers). The painting's plane is y=0 and its centre the origin.

Shape: a flat rectangle, LENGTH (z) x ACROSS (x), carried like a tray, picture up, a thin low-profile frame edge
around it, no stand, runners or cradle.

Layout: frame 12 (4 corner blocks, 8 bars: each side in two halves; stepped moulding) +
canvas 10 (5 x 2 torn pieces, the picture on both faces) + glass shards 8 (4 columns x 2 triangles).
Glass pane: 36 shards ("pane", COLOR.a 0.5 on the cut edges) + edge strip 6 (each long side in three) + end caps 4 (two halves each).
"""
import json
import math
import random
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "demo/assets/paintings/painting_items.json"
ROUND = 3
LENGTH = 3.25  # along the carry axis (item z) ...
ACROSS = 1.25  # ... and across it (item x, the walking direction)
ATLAS = (512, 404)  # assets/paintings/painting_atlas.png (tools/make_painting_atlas.py)
PICTURE = "#ffffff00"  # palette entry with alpha 0: the shader samples the picture texture there
GLASS = "#bfe9f5"
CANVAS_SIDE = "#cdbd9abf"  # alpha 0.75: no ink outline (carry_item_outline.gdshader), so no dark seams between the torn pieces


def hexcolor(value):
    value = value.lstrip("#")
    return [int(value[i:i + 2], 16) / 255.0 for i in range(0, len(value), 2)]


def sub(a, b): return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


class Piece:
    """One piece: flat-shaded triangles plus bookkeeping."""

    def __init__(self, name, kind="solid"):
        self.name = name
        self.kind = kind  # "solid" | "glass" (own material in the game)
        self.tris = []  # (a, b, c, color_name, uvs or None), outward-facing, Godot front winding
        self.points = []

    def _add(self, a, b, c, color, hint, uvs=None):
        n = cross(sub(b, a), sub(c, a))
        if dot(n, hint) > 0:  # Godot front faces are clockwise: right-hand normal points inward
            b, c = c, b
            if uvs is not None:
                uvs = [uvs[0], uvs[2], uvs[1]]
        self.tris.append((a, b, c, color, uvs))

    def prism(self, poly, w0, w1, top, side, bottom=None, mapper=None, top_uv=None, bottom_uv=None):
        """Extrude a convex polygon of (u, v) points between w=w0 and w=w1. Default mapper is u=x, v=z, w=y.
        top_uv / bottom_uv(u, v) -> (s, t) give the top / bottom face UVs (canvas)."""
        m = mapper or (lambda u, v, w: [u, w, v])
        lo = [m(u, v, w0) for u, v in poly]
        hi = [m(u, v, w1) for u, v in poly]
        center = [sum(p[i] for p in lo + hi) / (2 * len(poly)) for i in range(3)]
        self.points += lo + hi
        for i in range(1, len(poly) - 1):
            for face, col, uv_fn in ((hi, top, top_uv), (lo, bottom or side, bottom_uv)):
                tri = (face[0], face[i], face[i + 1])
                idx = (0, i, i + 1)
                uvs = [uv_fn(*poly[k]) for k in idx] if uv_fn else None
                self._add(*tri, col, sub([sum(p[k] for p in tri) / 3 for k in range(3)], center), uvs)
        for i in range(len(poly)):
            j = (i + 1) % len(poly)
            a, b, c, d = lo[i], lo[j], hi[j], hi[i]
            hint = sub([(a[k] + c[k]) / 2 for k in range(3)], center)
            self._add(a, b, c, side, hint)
            self._add(a, c, d, side, hint)

    def cone(self, poly, w0, apex_w, color, side=None, mapper=None):
        """Pyramid: convex base polygon (u, v) at w0, apex above its centroid at apex_w."""
        m = mapper or (lambda u, v, w: [u, w, v])
        base = [m(u, v, w0) for u, v in poly]
        cu = sum(p[0] for p in poly) / len(poly)
        cv = sum(p[1] for p in poly) / len(poly)
        apex = m(cu, cv, apex_w)
        center = [sum(p[i] for p in base) / len(base) for i in range(3)]
        center = [(center[i] + apex[i]) / 2 for i in range(3)]
        self.points += base + [apex]
        down = sub(m(cu, cv, w0 - 1.0), m(cu, cv, w0))
        for i in range(1, len(base) - 1):
            self._add(base[0], base[i], base[i + 1], side or color, down)
        for i in range(len(base)):
            j = (i + 1) % len(base)
            mid = [(base[i][k] + base[j][k] + apex[k]) / 3 for k in range(3)]
            self._add(base[i], base[j], apex, color, sub(mid, center))


def finish(piece, palette):
    """Piece -> dict: the mesh (item frame), its bounding-box centre and half extents."""
    positions, normals, colors, indices, uvs = [], [], [], [], []
    textured = any(t[4] is not None for t in piece.tris)
    for a, b, c, color, tri_uv in piece.tris:
        n = cross(sub(b, a), sub(c, a))
        length = math.sqrt(dot(n, n))
        if length < 1e-9:
            continue
        n = [-v / length for v in n]  # outward: the stored order is clockwise
        if color not in palette:
            palette.append(color)
        base = len(positions)
        for k, v in enumerate((a, b, c)):
            positions.append([round(x, ROUND) for x in v])
            normals.append([round(x, 2) for x in n])
            colors.append(palette.index(color))
            uvs.append([round(x, 5) for x in tri_uv[k]] if tri_uv else [0.0, 0.0])
        indices += [base, base + 1, base + 2]
    unique = sorted({tuple(round(x, ROUND) for x in p) for p in piece.points})
    mins = [min(p[i] for p in unique) for i in range(3)]
    maxs = [max(p[i] for p in unique) for i in range(3)]
    result = {
        "name": piece.name,
        "kind": piece.kind,
        "centre": [round((mins[i] + maxs[i]) / 2.0, ROUND) for i in range(3)],
        "half": [round((maxs[i] - mins[i]) / 2.0, ROUND) for i in range(3)],
        "positions": positions, "normals": normals, "colors": colors, "indices": indices,
    }
    if textured or piece.kind == "glass":
        result["uvs"] = uvs
    return result


# ----------------------------------------------------------------------------- paintings

PAINTINGS = {
    # frame width (m), frame crown height above the painting plane, atlas rect (x, y, w, h px), colours
    "landscape": {
        "frame_w": 0.07, "crown": 0.055, "atlas": (0, 0, 512, 211), "ornate": False,
        "colors": {"frame": "#c98c4b", "frame_side": "#b87a3c", "ridge": "#e3ad6a", "corner": "#a8672e", "frame_back": "#b5793a",
                   "canvas_side": CANVAS_SIDE},
        "flecks": ["#4f9de0", "#7fc15b", "#e86a3a", "#f7d95a", "#fff8e8", "#2f7d46"],
        "seed": 1019,
        "burst": {"outward": 1.0, "up": 1.7, "spin": 5.5},
    },
    "portrait": {
        "frame_w": 0.10, "crown": 0.06, "atlas": (0, 212, 512, 192), "ornate": True,
        "colors": {"frame": "#e8b33a", "frame_side": "#d29a22", "ridge": "#ffd966", "corner": "#f3c340", "frame_back": "#d9a02b",
                   "corner_knob": "#fff0a8", "canvas_side": CANVAS_SIDE},
        "flecks": ["#9c1c2e", "#f3a9b8", "#fff4e6", "#e8b33a", "#2a2f4f", "#6aa84f"],
        "seed": 2019,
        "burst": {"outward": 0.9, "up": 1.6, "spin": 5.0},
    },
}


def build_painting(name, spec, palette):
    """A flat picture frame: LENGTH (z, the carry axis) x ACROSS (x), centred on the origin,
    its back just under the plane, the picture facing up. Piece polygons are (x, z) points, extruded along y."""
    c = spec["colors"]
    fw, top = spec["frame_w"], spec["crown"]
    ax, ay, aw, ah = spec["atlas"]
    L, D = LENGTH, ACROSS
    W, H = L - 2 * fw, D - 2 * fw  # the opening (picture): W along the carry axis, H across
    base = -0.025  # frame back
    step = top - 0.025  # the flat of the moulding; the inner ridge rises from here to the crown
    rng = random.Random(spec["seed"])

    # picture -> atlas: s along +z (screen right from the camera behind), t down the picture (the top is the far side, +x).
    # The atlas keeps its own aspect: the longer side of the opening is covered, the other is cropped around the centre.
    open_aspect, atlas_aspect = W / H, aw / ah
    s_span, t_span = (1.0, atlas_aspect / open_aspect) if open_aspect > atlas_aspect else (open_aspect / atlas_aspect, 1.0)

    def pic_uv(x, z, back=False):  # the back shows the same picture, not mirrored
        s = (z + W / 2) / W
        s = 1.0 - s if back else s
        t = (H / 2 - x) / H
        s = 0.5 + (s - 0.5) * s_span
        t = 0.5 + (t - 0.5) * t_span
        s = min(max(s, 0.5 / aw), 1 - 0.5 / aw)
        t = min(max(t, 0.5 / ah), 1 - 0.5 / ah)
        return ((ax + s * aw) / ATLAS[0], (ay + t * ah) / ATLAS[1])

    pieces = []
    # frame: 4 corner blocks, 8 bars (each side in 2 halves), a stepped moulding (base + inner ridge)
    corner_top = top + (0.012 if spec["ornate"] else 0.0)

    def bar(name_, x0, x1, z0, z1, inner_side):
        """inner_side: which edge of the (x, z) box faces the opening: 'x+', 'x-', 'z+', 'z-'."""
        p = Piece(name_)
        box = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
        p.prism(box, base, step, c["frame"], c["frame_side"], c["frame_back"])
        t = 0.45  # inner ridge share of the bar width
        if inner_side == "x-": ridge = [(x0, z0), (x0 + (x1 - x0) * t, z0), (x0 + (x1 - x0) * t, z1), (x0, z1)]
        elif inner_side == "x+": ridge = [(x1 - (x1 - x0) * t, z0), (x1, z0), (x1, z1), (x1 - (x1 - x0) * t, z1)]
        elif inner_side == "z-": ridge = [(x0, z0), (x1, z0), (x1, z0 + (z1 - z0) * t), (x0, z0 + (z1 - z0) * t)]
        else: ridge = [(x0, z1 - (z1 - z0) * t), (x1, z1 - (z1 - z0) * t), (x1, z1), (x0, z1)]
        p.prism(ridge, step, top, c["ridge"], c["frame_side"])
        return p

    for sx, tag in ((1, "far"), (-1, "near")):  # the long sides, walking-direction far / near, two halves each
        x0, x1 = (D / 2 - fw, D / 2) if sx > 0 else (-D / 2, -D / 2 + fw)
        side = "x-" if sx > 0 else "x+"
        pieces.append(bar("%sA" % tag, x0, x1, 0.0, L / 2 - fw, side))
        pieces.append(bar("%sB" % tag, x0, x1, -L / 2 + fw, 0.0, side))
    for sz, tag in ((1, "endA"), (-1, "endB")):  # the short ends at the carriers' hands, two halves each
        z0, z1 = (L / 2 - fw, L / 2) if sz > 0 else (-L / 2, -L / 2 + fw)
        side = "z-" if sz > 0 else "z+"
        pieces.append(bar(tag + "0", 0.0, D / 2 - fw, z0, z1, side))
        pieces.append(bar(tag + "1", -D / 2 + fw, 0.0, z0, z1, side))
    for k, (cx, cz) in enumerate([(-1, -1), (-1, 1), (1, -1), (1, 1)]):
        x0, x1 = (-D / 2, -D / 2 + fw) if cx < 0 else (D / 2 - fw, D / 2)
        z0, z1 = (-L / 2, -L / 2 + fw) if cz < 0 else (L / 2 - fw, L / 2)
        p = Piece("corner%d" % k)
        p.prism([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], base, corner_top, c["corner"], c["frame_side"], c["frame_back"])
        if spec["ornate"]:
            mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
            r = fw * 0.34
            p.cone([(mx - r, mz), (mx, mz - r), (mx + r, mz), (mx, mz + r)], corner_top, corner_top + fw * 0.3, c["corner_knob"], c["frame_side"])
        pieces.append(p)
    # canvas: 5 x 2 torn pieces; the interior cut points are jittered, the boundary runs under the frame
    nz, nx = 5, 2
    pad = 0.012
    zs = [-W / 2 - pad + (W + 2 * pad) * i / nz for i in range(nz + 1)]
    xs = [-H / 2 - pad + (H + 2 * pad) * j / nx for j in range(nx + 1)]
    grid = [[(zs[i] + (rng.uniform(-0.2, 0.2) * W / nz if 0 < i < nz else 0.0),
              xs[j] + (rng.uniform(-0.18, 0.18) * H / nx if 0 < j < nx else 0.0)) for j in range(nx + 1)] for i in range(nz + 1)]
    canvas_top = 0.02
    for j in range(nx):
        for i in range(nz):
            quad = [(g[1], g[0]) for g in (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])]  # (x, z)
            p = Piece("canvas%d_%d" % (i, j))
            p.prism(quad, canvas_top - 0.018, canvas_top, PICTURE, c["canvas_side"], PICTURE, top_uv=pic_uv, bottom_uv=lambda x, z: pic_uv(x, z, True))
            pieces.append(p)
    # glass: 4 columns x 2 triangles over the opening, slanted cuts, a sheet in front of the canvas (below the frame crown)
    g0, g1 = 0.03, 0.037
    gw, gh = W - 0.012, H - 0.012
    gz = lambda f: -gw / 2 + gw * f
    cuts_a = [0.0] + [(k + 1) / 4 + rng.uniform(-0.06, 0.06) - 0.04 for k in range(3)] + [1.0]  # far edge
    cuts_b = [0.0] + [(k + 1) / 4 + rng.uniform(-0.06, 0.06) + 0.04 for k in range(3)] + [1.0]  # near edge
    xa, xb = gh / 2, -gh / 2
    def glass_uv(x, z): return ((z + W / 2) / W, (H / 2 - x) / H)
    for k in range(4):
        bl, br = (xb, gz(cuts_b[k])), (xb, gz(cuts_b[k + 1]))  # near edge, (x, z)
        tr, tl = (xa, gz(cuts_a[k + 1])), (xa, gz(cuts_a[k]))
        tris = [[bl, br, tr], [bl, tr, tl]] if k % 2 == 0 else [[bl, br, tl], [br, tr, tl]]
        for h, tri in enumerate(tris):
            p = Piece("glass%d_%d" % (k, h), kind="glass")
            p.prism(tri, g0, g1, GLASS, GLASS, top_uv=glass_uv)
            pieces.append(p)
    return pieces


# ----------------------------------------------------------------------------- the glass pane

GLASS_PANE = {
    "strip_w": 0.03, "cap_w": 0.16,  # the long sides' metal strip, the rubber caps on the short ends (the hands hold them)
    "thick": 0.024,  # the sheet; strip and caps stand a little proud of it
    "shards": 36, "cracks": 4, "seed": 3019,
    "colors": {"strip": "#c4ced6", "strip_side": "#9aa8b4", "cap": "#34404c", "cap_side": "#262f38", "cap_ridge": "#46535f",
               "pane": "#d2f0eb", "pane_edge": "#5fbfb280"},  # alpha 0.5: the cut edges of a shard (glass_pane.gdshader)
    "flecks": ["#a8e0d8", "#c9eef7", "#eefcff", "#86cfc5", "#ffffff"],
    "burst": {"outward": 1.25, "up": 1.9, "spin": 7.0},
}


def area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def centroid(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def split(poly, point, angle):
    """Cut a convex polygon by the line through `point` at `angle`: the two convex halves (either may be empty)."""
    nx, nz = -math.sin(angle), math.cos(angle)
    side = [(p[0] - point[0]) * nx + (p[1] - point[1]) * nz for p in poly]
    left, right = [], []
    for i, p in enumerate(poly):
        j = (i + 1) % len(poly)
        (left if side[i] >= 0 else right).append(p)
        if (side[i] >= 0) != (side[j] >= 0):
            t = side[i] / (side[i] - side[j])
            q = (p[0] + (poly[j][0] - p[0]) * t, p[1] + (poly[j][1] - p[1]) * t)
            left.append(q)
            right.append(q)
    clean = lambda half: [q for k, q in enumerate(half) if math.dist(q, half[k - 1]) > 1e-6] if half else half
    return clean(left), clean(right)


def sliver(poly):
    """True for a piece too thin to read: its area over its longest side."""
    longest = max(math.dist(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))
    return abs(area(poly)) < 0.01 or abs(area(poly)) / longest < 0.045


def shatter(rect, count, cracks, rng):
    """Angular convex shards of the (x, z) rectangle: `cracks` lines through an impact point near the middle, then the
    largest piece is cut by a straight line near its centre (across its long side) until there are `count`."""
    (x0, z0), (x1, z1) = rect
    pieces = [[(x0, z0), (x1, z0), (x1, z1), (x0, z1)]]
    impact = ((x0 + x1) / 2 + rng.uniform(-0.15, 0.15) * (x1 - x0), (z0 + z1) / 2 + rng.uniform(-0.12, 0.12) * (z1 - z0))
    for k in range(cracks):
        angle = math.pi * (k + rng.uniform(0.2, 0.8)) / cracks
        pieces = [half for piece in pieces for half in split(piece, impact, angle) if len(half) >= 3 and abs(area(half)) > 1e-4]
    tries = 0
    while len(pieces) < count and tries < 2000:
        tries += 1
        pieces.sort(key=lambda p: -abs(area(p)))
        pick = 0 if tries % 7 else rng.randrange(min(4, len(pieces)))
        piece = pieces[pick]
        xs, zs = [p[0] for p in piece], [p[1] for p in piece]
        long_z = (max(zs) - min(zs)) > (max(xs) - min(xs))
        angle = (0.0 if long_z else math.pi / 2) + rng.uniform(-0.6, 0.6)  # cut across the long side
        c = centroid(piece)
        point = (c[0] + rng.uniform(-0.15, 0.15) * (max(xs) - min(xs)), c[1] + rng.uniform(-0.15, 0.15) * (max(zs) - min(zs)))
        a, b = split(piece, point, angle)
        if len(a) < 3 or len(b) < 3 or sliver(a) or sliver(b):
            continue
        pieces = [a, b] + pieces[:pick] + pieces[pick + 1:]
    # a stable order: across the sheet from one carrier to the other
    return sorted(pieces, key=lambda p: (round(centroid(p)[1], 3), round(centroid(p)[0], 3)))


def build_glass(spec, palette):
    """A clear pane, LENGTH (z, the carry axis) x ACROSS (x), centred on the origin, the sheet around y=0. Shard polygons are
    (x, z) points, extruded along y; their faces carry UVs over the visible pane (s along +z, t down: the top is the far
    side, +x), the back mirrored, so the etched print reads the right way round from either side."""
    c = spec["colors"]
    sw, cw, th = spec["strip_w"], spec["cap_w"], spec["thick"]
    L, D = LENGTH, ACROSS
    PZ, PX = L / 2 - cw + 0.005, D / 2 - sw + 0.005  # the sheet runs a little under the strip and the caps
    rng = random.Random(spec["seed"])

    def pane_uv(x, z, back=False):
        s = (z + PZ) / (2 * PZ)
        return (1.0 - s if back else s, (PX - x) / (2 * PX))

    pieces = []
    for k, poly in enumerate(shatter(((-PX, -PZ), (PX, PZ)), spec["shards"], spec["cracks"], rng)):
        if area(poly) < 0:
            poly = poly[::-1]
        p = Piece("shard%d" % k, kind="pane")
        p.prism(poly, -th / 2, th / 2, c["pane"], c["pane_edge"], c["pane"], top_uv=pane_uv, bottom_uv=lambda x, z: pane_uv(x, z, True))
        pieces.append(p)
    # the long sides: a thin metal strip, each in three, standing a little proud of the sheet
    for sx, tag in ((1, "far"), (-1, "near")):
        x0, x1 = (D / 2 - sw, D / 2) if sx > 0 else (-D / 2, -D / 2 + sw)
        cuts = [-L / 2 + cw, -L / 6, L / 6, L / 2 - cw]
        for k in range(3):
            p = Piece("strip_%s%d" % (tag, k))
            p.prism([(x0, cuts[k]), (x1, cuts[k]), (x1, cuts[k + 1]), (x0, cuts[k + 1])], -th / 2 - 0.006, th / 2 + 0.008, c["strip"], c["strip_side"])
            pieces.append(p)
    # the short ends: rubber caps the hands hold (painting.gd GRIP_ALONG), each in two halves, a raised grip ridge on top
    for sz, tag in ((1, "capA"), (-1, "capB")):
        z0, z1 = (L / 2 - cw, L / 2) if sz > 0 else (-L / 2, -L / 2 + cw)
        for k, (x0, x1) in enumerate(((0.0, D / 2), (-D / 2, 0.0))):
            p = Piece("%s%d" % (tag, k))
            p.prism([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], -th / 2 - 0.012, th / 2 + 0.014, c["cap"], c["cap_side"])
            rz0, rz1 = z0 + (z1 - z0) * 0.3, z0 + (z1 - z0) * 0.7
            rx0, rx1 = (x0 + 0.06, x1 - 0.02) if k == 0 else (x0 + 0.02, x1 - 0.06)
            p.prism([(rx0, rz0), (rx1, rz0), (rx1, rz1), (rx0, rz1)], th / 2 + 0.014, th / 2 + 0.024, c["cap_ridge"], c["cap_side"])
            pieces.append(p)
    return pieces


def item(name, spec):
    palette = []
    pieces = build_glass(spec, palette) if name == "glass" else build_painting(name, spec, palette)
    pieces_out = [finish(piece, palette) for piece in pieces]
    result = {
        "sound_id": "glass_break" if name == "glass" else "break_painting",
        "lifetime": 30.0,
        "burst": spec["burst"],
        "flecks": {"colors": spec["flecks"], "count": 56, "glints": 26 if name == "glass" else 14, "radius": 1.5},
        "palette": [[round(c, 3) for c in hexcolor(h)] for h in palette],
        "pieces": pieces_out,
    }
    result["height"] = round(max(f["centre"][1] + f["half"][1] for f in pieces_out), 3)
    result["half_width"] = round(max(abs(f["centre"][0]) + f["half"][0] for f in pieces_out), 3)
    return result


def build():
    return {
        "format": "painting-items-1",
        "tool": "tools/build_painting_items.py",
        "frame": "x across (walking direction), y up, z along the carry axis; metres",
        "picture": "assets/paintings/painting_atlas.png",
        "items": {name: item(name, spec) for name, spec in [*PAINTINGS.items(), ("glass", GLASS_PANE)]},
    }


def main():
    text = json.dumps(build(), separators=(",", ":")) + "\n"
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text() != text:
            raise SystemExit("painting_items.json is stale: run tools/build_painting_items.py")
        print("painting_items.json is current")
        return
    OUT.write_text(text)
    data = json.loads(text)
    for name, entry in data["items"].items():
        verts = sum(len(f["positions"]) for f in entry["pieces"])
        kinds = {}
        for f in entry["pieces"]:
            kinds[f["kind"]] = kinds.get(f["kind"], 0) + 1
        print("%s: %d pieces %s, %d vertices, height %.2f m, half width %.2f m" % (name, len(entry["pieces"]), kinds, verts, entry["height"], entry["half_width"]))
    print("wrote %s (%d bytes)" % (OUT, len(text)))


if __name__ == "__main__":
    main()
