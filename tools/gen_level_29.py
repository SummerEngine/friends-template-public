#!/usr/bin/env python3
"""Generates demo/levels/level_29.json (ROOFTOP RUN, round r29), standard library only, same output on every run.

  python3 tools/gen_level_29.py                          # writes demo/levels/level_29.json
  python3 tools/gen_level_29.py --report                 # also prints the jump table, the pad ballistics, the counts and the run-time estimate
  python3 tools/gen_level_29.py --emit-jumps out.json    # every required static -> static jump (+ the pads' ballistics, no movers) for tools/race_jump_probe.gd

Layout: planned section by section on a tile grid, 1 E (a plan tile's edge) = 2.0 m,
time x1.44. The course is longer than the +-150 m box, so it turns twice:
  leg 1 runs towards -Z   (start deck ... slab S1 with the first gantry spinner)
  leg 2 runs towards -X   (bridge, launch platforms A / C, slab B, stairs, long deck D, entry slab with the third gantry spinner)
  leg 3 runs towards +Z   (disc field, launch platform E, goal deck)
Helper rects: R1(x0, x1, s0, s1) leg 1 (z = -s), R2(t0, t1, l0, l1) leg 2 (x = -t, z = Z2 + l), R3(d0, d1, u0, u1) leg 3 (x = XC + d, z = Z3(u)).
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jump_reach import max_gap, pad_flight, solve_pad, AIR_BRAKE, WALK, ACCEL, G as GRAV, DT, MAX_FALL  # noqa: E402
from pad_design import design_pad  # noqa: E402
import gate_piece  # noqa: E402
import laser_plane  # noqa: E402
import item_boxes_gen  # noqa: E402
import kit_grid  # noqa: E402

NUMBER = 29
PEDESTAL_SPEED = 36.0  # m/s: the most a far throw (the pedestals) gives (level_lint allows 36 m/s per component for a push pad); the air brake takes it down to the walk speed
SH = 7.0  # the gate deck is 12 - SH = 5 m deep (the wall stands ~1.5 E beyond the last belt strip), everything after it moved SH m towards the start
Z2 = -140.0 + SH  # leg 2 centre line (world z)
XC = -106.0  # leg 3 centre line (world x)
Z3_0 = -133.0 + SH  # world z where leg 3 starts (the entry slab's +Z edge)
W1 = 82.0 - SH  # wall 1 front (s)
W2 = 91.0 - SH  # wall 2 front (s)
BELT = 7.0       # m/s: a belt across the course is 1.4 x the courier's walk (5 m/s, CourierMotion.WALK_SPEED): standing still is thrown off within about a second, a crossing is a straight run (tools/belt_cross_probe.gd)
BELT_LANE = 3.5  # m/s: a belt that runs back along the course (the lane band) stays under the walk: faster than 5 m/s could not be run up at all
WALL_H = 3.5    # m: the navy wall of a gate wall (tools/gate_piece.py: door period 4 s, open 1.25 s, shut 1.25 s)
DOOR_W = 1.5
# Spinner rates (deg/s): a big wheel at 150 deg/s (5.0 deg per frame at 30 fps), the discs of the disc field about 165, scaled for our courier (time x1.44) by
# 0.69: wheel and gantry spinners 150 x 0.69 = 105, discs 105 and 120.
DISC_A = 105
DISC_B = 120
SPIN_X = 105
SPIN_WHEEL = 105
# The three gantry windmills (X shape, the bars turn through a full circle of `arm` m): the hub stands `arm` + 0.5 m over the deck so the lowest tip sweeps 0.5 m over it, the arms
# reach across the whole floor under them (x1: the 9 m slab, x2: the 4 m bridge, x3: the 14 m entry slab).
X1_ARM, X1_THICK, X1_Y = 5.0, 1.25, 1.5 + 0.5 + 5.0
X2_ARM, X2_THICK, X2_Y = 4.0, 1.0, 1.5 + 0.5 + 4.0
X3_ARM, X3_THICK, X3_Y = 7.0, 1.5, 15.0 + 0.5 + 7.0


def q(v):
    return round(v * 4.0) / 4.0


def qs(v):
    return round(v * 2.0) / 2.0


def dome_offset(thick):
    """m from a windmill's plane to the centre of the 1.25 m deep post or hanger that carries its hub: the hub's dome (style/spinner_look.gd `_hub_top`: hub radius 0.9 x the bar's, a cap 0.34 over
    the bar's face, a dome 0.64 of the hub radius less 6 cm) reaches 1.076 x thick + 0.33 from the plane, and the carrier's face meets it. Blocks stand on the 0.25 grid, so the face ends up
    5 to 7 cm inside the dome's tip (thick 1.25 and 1.5): the join has no gap."""
    return q(1.076 * thick + 0.33 - 0.05 + 0.625)


def Z3(u):
    return Z3_0 + u


def R1(x0, x1, s0, s1):
    return (x0, x1, -s1, -s0)


def R2(t0, t1, l0, l1):
    return (-t1, -t0, Z2 + l0, Z2 + l1)


def R3(d0, d1, u0, u1):
    return (XC + d0, XC + d1, Z3(u0), Z3(u1))


class Level:
    def __init__(self):
        self.blocks = []
        self.hazards = []
        self.jumps = []
        self.movers = []
        self.pads = []

    # ---- blocks -------------------------------------------------------------------------------------------------
    def box(self, x, y, z, w, h, d, **kw):
        b = {"k": "box", "p": [q(x), q(y), q(z)], "s": [q(w), q(h), q(d)]}
        b.update(kw)
        self.blocks.append(b)

    def cyl(self, x, y, z, d, h, **kw):
        b = {"k": "cyl", "p": [q(x), q(y), q(z)], "d": q(d), "h": q(h)}
        b.update(kw)
        self.blocks.append(b)

    def slab(self, x0, x1, z0, z1, top, thick=1.0, **kw):
        """Floor box from (x0..x1, z0..z1), top face at `top`."""
        self.box((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2, x1 - x0, thick, z1 - z0, **kw)

    def slab_r(self, rect, top, thick=1.0, **kw):
        self.slab(rect[0], rect[1], rect[2], rect[3], top, thick, **kw)

    def pillar(self, x, z, w, top, bottom=-12.0):
        self.box(x, (top + bottom) / 2, z, w, top - bottom, w)

    def belt(self, rect, top, vx, vz):
        self.slab_r(rect, top, m="belt", belt=[qs(vx), qs(vz)])

    def disc(self, cx, cz, d, top, hub=True):
        self.blocks.append({"k": "cyl", "p": [q(cx), q(top - 0.5), q(cz)], "d": q(d), "h": 1.0, "tone": "disc"})
        if hub:
            self.cyl(cx, top + 0.75, cz, 1.5, 1.5, tone="hub")

    def bars(self, hid, cx, cz, top, d, rate, bars=2, length=None):
        """Spinner bars lying on a disc of diameter d: `bars` crossing bars (2 = a cross with 4 blades, the default; 1 = a straight bar with 2 arms, only where a cluster is impassable with 4), rotating about y."""
        length = q(d - 1.0 if length is None else length)
        parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [length, 1.0, 1.0]}]
        if bars == 2:
            parts.append({"k": "box", "p": [0.0, 0.0, 0.0], "s": [length, 1.0, 1.0], "r": [0, 90, 0]})
        self.hazards.append({"k": "spin", "id": hid, "p": [q(cx), q(top + 0.75), q(cz)], "axis": "y", "rate": rate, "hit": True, "parts": parts})

    def windmill(self, hid, p, axis, arm, rate, thick=1.0):
        """Two crossing bars (an X, 4 arms) turning in the plane perpendicular to `axis` ('z': the XY plane, 'x': the YZ plane)."""
        length = q(2 * arm)
        if axis == "z":
            parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [length, thick, thick], "r": [0, 0, 45]},
                     {"k": "box", "p": [0.0, 0.0, 0.0], "s": [length, thick, thick], "r": [0, 0, -45]}]
        else:
            parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [thick, thick, length], "r": [45, 0, 0]},
                     {"k": "box", "p": [0.0, 0.0, 0.0], "s": [thick, thick, length], "r": [-45, 0, 0]}]
        self.hazards.append({"k": "spin", "id": hid, "p": [q(p[0]), q(p[1]), q(p[2])], "axis": axis, "rate": rate, "hit": True, "parts": parts})

    def mast(self, axis, hub, top, thick=1.0):
        """A spinner hub carried by ONE masonry pillar (2 m wide across the plane, 1.25 m deep, the kit's plain stone) standing behind the spinner's plane on the floor `top` and reaching 1.5 m over
        the hub, its face touching the hub's dome (see `dome_offset`): nothing stands beside the walkway in the way of a racer the spinner flings sideways. axis 'z' (spinner in the XY plane): the
        pillar is centred at z - offset; 'x' (YZ plane): at x - offset."""
        hx, hy, hz = hub
        mid, size = (top + hy + 1.5) / 2, hy + 1.5 - top
        off = dome_offset(thick)
        if axis == "z":
            self.box(hx, mid, hz - off, 2.0, size, 1.25, tone="stone_plain")
        else:
            self.box(hx - off, mid, hz, 1.25, size, 2.0, tone="stone_plain")

    def carrier(self, axis, hub, arm, thick, post_span, side):
        """The frame of a hub over a walkway too narrow for a mast: two masonry posts (2 m wide, 1.25 m deep) at +-post_span / 2 across the spinner's plane (outside the walkway and the sweep),
        rising from under the world, carry a 1.5 m high lintel (1.75 m deep, a quarter metre proud of the posts) whose underside is 0.5 m over the sweep; the frame stands `dome_offset` m to `side`
        (+1 / -1 along the plane's normal) of the plane, and a 2.5 m wide bracket drops from the lintel to a metre under the hub, its face touching the hub's dome."""
        hx, hy, hz = hub
        off = side * dome_offset(thick)
        under = math.ceil((hy + arm + thick / 2 + 0.5) * 4.0) / 4.0
        lintel = under + 0.75
        top = lintel + 1.0
        for sgn in (-1, 1):
            if axis == "z":
                self.box(hx + sgn * post_span / 2, (top - 12.0) / 2, hz + off, 2.0, top + 12.0, 1.25, tone="stone_plain")
            else:
                self.box(hx + off, (top - 12.0) / 2, hz + sgn * post_span / 2, 1.25, top + 12.0, 2.0, tone="stone_plain")
        if axis == "z":
            self.box(hx, lintel, hz + off, post_span, 1.5, 1.75, tone="frame")
            self.box(hx, (lintel + hy - 1.0) / 2, hz + off, 2.5, lintel - hy + 1.0, 1.25, tone="frame")
        else:
            self.box(hx + off, lintel, hz, 1.75, 1.5, post_span, tone="frame")
            self.box(hx + off, (lintel + hy - 1.0) / 2, hz, 1.25, lintel - hy + 1.0, 2.5, tone="frame")

    def pad(self, hid, x, top, z, d, v, target=None):
        """target = (top, world rect) the launch must land on, checked by `--report` (ballistics, gravity 17, no air control)."""
        if target:
            self.pads.append({"id": hid, "from": [round(x, 2), round(z, 2)], "from_top": top, "v": [qs(v[0]), qs(v[1]), qs(v[2])], "target_top": target[0], "target": list(target[1])})
        self.hazards.append({"k": "push", "id": hid, "g": "cyl", "p": [round(x, 2), q(top + 1.0), round(z, 2)], "d": q(d), "h": 0.5, "v": [qs(v[0]), qs(v[1]), qs(v[2])]})

    def launch(self, hid, x, top, z, d, u, target_top, rect, aim):
        """A launch pad at (x, z) on a floor `top` throwing along the axis direction `u` onto the box top `rect` (world x0, x1, z0, z1) at `target_top`. The throw is tuned with the real
        flight rule of the courier (jump_reach.pad_flight, the stick held forward): the landing is `aim` m along the throw (the middle of the part of the target we want to land on),
        at least 1.5 m inside both edges, at least 1.0 m clear over the near edge, v_y <= 18, v_h <= 14, on the 0.5 grid."""
        # the pad is a round button on exactly a 2 x 2 block of the platform's tiles (tools/kit_grid.py): it moves to the nearest such cell, the throw keeps its landing
        if kit_grid.block_under(self.blocks, x, z, top) is not None:
            x_was, z_was = x, z
            x, z = kit_grid.snap(self.blocks, x, z, top, [tuple(p["from"]) for p in self.pads])
            aim -= (x - x_was) * u[0] + (z - z_was) * u[1]
        x0, x1, z0, z1 = rect
        if u == (-1, 0):
            near, far = x - x1, x - x0
        elif u == (1, 0):
            near, far = x0 - x, x1 - x
        elif u == (0, 1):
            near, far = z0 - z, z1 - z
        else:
            near, far = z - z1, z - z0
        dh = target_top - top
        best = None
        for shift in (0.0, -0.5, 0.5, -1.0, 1.0, -1.5, 1.5, -2.0, 2.0, -2.5, 2.5):  # the pad stands on a tile cell: aim the nearest landing that a throw still reaches
            for vy2 in range(24, 37):  # v_y 12.0 .. 18.0
                vy = vy2 / 2
                vh = min(14.0, round(solve_pad(aim + shift, vy, dh) * 2) / 2)
                dist, t_flight, apex = pad_flight(vh, vy, dh)
                clear = flight_height(vh, vy, near) - dh
                if not (near + 1.5 <= dist <= far - 1.5) or clear < 1.0:
                    continue
                key = (abs(dist - aim - shift), vy)
                if best is None or key < best[0]:
                    best = (key, vh, vy)
            if best is not None:
                break
        assert best, f"{hid}: no throw lands {aim} m ahead between {near} and {far}"
        v = (u[0] * best[1], best[2], u[1] * best[1])
        self.pad(hid, x, top, z, d, v, target=(target_top, rect))

    def pedestal(self, hid, x, z, floor_top, aim=None, target_top=None, rect=None):
        """A 3 x 3 x 1 pedestal (two by two tiles, kit_grid: a 3 m stone) with a round pad over its whole grid. With `aim` (x, z), `target_top` and `rect` the pad is a far throw
        (pad_design.design_pad, any direction, up to PEDESTAL_SPEED m/s along the ground, the stick held along the throw) that carries the courier over the obstacles ahead to land at
        `aim` on the deck `rect` (world x0, x1, z0, z1) at `target_top`; without them it only hops straight up."""
        self.box(x, floor_top + 0.5, z, 3.0, 1.0, 3.0)
        if aim is None:
            self.pad(hid, x, floor_top + 1.0, z, 3.0, (0, 9, 0))
            return
        v, info = design_pad((x, z), floor_top + 1.0, aim, target_top, rect, PEDESTAL_SPEED, (18.0, 20.0, 22.0, 24.0))
        assert max(abs(c) for c in v) <= PEDESTAL_SPEED and info["margin"] >= 1.5 and (info["clearance"] is None or info["clearance"] >= 1.0), f"{hid}: {info}"
        self.pad(hid, x, floor_top + 1.0, z, 3.0, tuple(v), target=(target_top, rect))
        self.pads[-1]["flight"] = info

    # ---- gate wall ----------------------------------------------------------------------------------------------
    def gate_wall(self, hid, s0, half, gates, phase=0.0):
        """A gate wall across x -half..half at s0..s0+1 (tools/gate_piece.py): one navy quilted wall, a frame with two eyes and a sliding chevron door per gate (the x of each in
        `gates`, opening DOOR_W; two doors side by side need 2.5 m between their middles), on a floor slab."""
        self.slab(-half, half, -(s0 + 1.0), -s0, 0.0)
        piece = gate_piece.gate_wall(R1, s0, 0.0, -half, half, [(x, DOOR_W) for x in gates], hid, wall_h=WALL_H, phase=phase)
        self.blocks.extend(piece["blocks"])
        self.hazards.extend(piece["hazards"])

    def fence(self, x0, x1, z0, z1, top, skip=()):
        """Thin 1 m rail boxes round a rectangle (hit false); skip: names among 'n', 's', 'e', 'w' (n = the -Z side, s = +Z, w = -X, e = +X)."""
        h = 1.0
        if "n" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z0 + 0.25, x1 - x0, h, 0.5)
        if "s" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z1 - 0.25, x1 - x0, h, 0.5)
        if "w" not in skip:
            self.box(x0 + 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0)
        if "e" not in skip:
            self.box(x1 - 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0)

    # ---- jumps -----------------------------------------------------------------------------------------------
    def jump(self, name, frm, to, from_top, top, run_up=3.0, brink=None, u=None, ref_gap_E=None):
        """frm / to: world rects (x0, x1, z0, z1); brink + u = where the jump is pressed and its direction (default: the closest pair of points).
        Gap = edge to edge along u; the run-up is taken back along -u on the take-off rect."""
        (fx0, fx1, fz0, fz1), (tx0, tx1, tz0, tz1) = frm, to
        if brink is None:
            cx = min(max((tx0 + tx1) / 2, fx0), fx1)
            cz = min(max((tz0 + tz1) / 2, fz0), fz1)
            px = min(max(cx, tx0), tx1)
            pz = min(max(cz, tz0), tz1)
            brink = (min(max(px, fx0), fx1), min(max(pz, fz0), fz1))
            qx = min(max(brink[0], tx0), tx1)
            qz = min(max(brink[1], tz0), tz1)
            d = math.hypot(qx - brink[0], qz - brink[1])
            u = ((qx - brink[0]) / d, (qz - brink[1]) / d)
            gap = d
        else:
            gap = ray_hit(brink, u, to)
        run = min(run_up, ray_exit(brink, (-u[0], -u[1]), frm))
        start = (brink[0] - u[0] * run, brink[1] - u[1] * run)
        dh = top - from_top
        self.jumps.append({
            "level": NUMBER, "name": name, "start": [q(start[0]), q(start[1])], "u": [round(u[0], 4), round(u[1], 4)],
            "edge": [q(brink[0]), q(brink[1])], "from_top": from_top, "top": top,
            "poly": [[tx0, tz0], [tx1, tz0], [tx1, tz1], [tx0, tz1]], "gap": round(gap, 3), "run_up": round(run, 2),
            "dh": round(dh, 3), "max_gap": round(max_gap(dh, run), 2), "ref_gap_E": ref_gap_E,
        })



def flight_height(v_h, v_y, dist):
    """Height above the pad's floor when the courier (thrown with v_h along the throw, up v_y, stick held forward, jump_reach.pad_flight's rule) has gone `dist` m along the throw."""
    x, y, vy, t, sp = 0.0, 0.0, v_y, 0.0, v_h
    while t < 6.0:
        sp = max(sp - AIR_BRAKE * DT, WALK) if sp > WALK else min(sp + 0.75 * ACCEL * DT, WALK)
        vy = max(vy - GRAV * DT, -MAX_FALL)
        y += vy * DT
        x += sp * DT
        t += DT
        if x >= dist:
            return y
    return y


def ray_hit(p, u, rect):
    x0, x1, z0, z1 = rect
    tmin, tmax = 0.0, 1e9
    for pi, ui, lo, hi in ((p[0], u[0], x0, x1), (p[1], u[1], z0, z1)):
        if abs(ui) < 1e-9:
            if pi < lo or pi > hi:
                return float("inf")
            continue
        t1, t2 = (lo - pi) / ui, (hi - pi) / ui
        tmin, tmax = max(tmin, min(t1, t2)), min(tmax, max(t1, t2))
    return tmin if tmin <= tmax else float("inf")


def ray_exit(p, u, rect):
    x0, x1, z0, z1 = rect
    best = 1e9
    for pi, ui, lo, hi in ((p[0], u[0], x0, x1), (p[1], u[1], z0, z1)):
        if abs(ui) < 1e-9:
            continue
        best = min(best, ((hi if ui > 0 else lo) - pi) / ui)
    return max(best, 0.0)


def resample(path, step=5.5):
    """Insert points on every segment longer than `step` so the waypoints are about 4-6 m apart (heights interpolated)."""
    out = [path[0]]
    for a, b in zip(path, path[1:]):
        n = max(1, math.ceil(math.dist(a, b) / step))
        for i in range(1, n + 1):
            out.append([q(a[k] + (b[k] - a[k]) * i / n) for k in range(3)])
    return out


def build():
    L = Level()
    path = []

    def P(x, y, z):
        path.append([q(x), q(y), q(z)])

    # =============================================================== LEG 1 (towards -Z; s = metres forward, z = -s)
    # 1. start deck (teal, 16 m between the start and the lane band: a runner needs ~2.3 s at run speed), no rails (a racer who runs off falls), two pedestals with a hop pad beside the lane band
    L.slab(-10, 10, -16, 6, 0.0)
    # the two start pedestals are real launch pads: they throw the courier over the lane band, disc A and the first cross belt onto the dark deck of step 5 (s 44.5..52.5)
    dark_deck = (-3.5, 3.5, -52.5, -44.5)
    L.pedestal("hop_start_l", -7.5, -14.5, 0.0, aim=(-1.0, -48.5), target_top=0.0, rect=dark_deck)
    L.pedestal("hop_start_r", 7.5, -14.5, 0.0, aim=(1.0, -48.5), target_top=0.0, rect=dark_deck)
    L.hazards.append({"k": "blink", "id": "gate", "slot": "gate", "p": [0.0, 2.0, -4.75], "s": [19.0, 4.0, 0.5], "on": 4.0, "off": 600.0, "warn": 1.0, "hit": False})

    # 2. lane band s 16..30: five lanes, every one a belt towards the start (no static lane: nothing to walk past the belts on)
    for x0, x1 in ((-5.25, -2.75), (-2.75, -1.25), (-1.25, 1.25), (1.25, 2.75), (2.75, 5.25)):
        L.belt((x0, x1, -30.0, -16.0), 0.0, 0.0, BELT_LANE)

    # 3. disc A (central, 4 arms) s 30..38.5
    L.disc(0, -34.25, 8.5, 0.0)
    L.bars("disc_a", 0, -34.25, 0.0, 8.5, DISC_A)

    # 4. cross belt 1 s 38.5..44.5, one belt over the whole strip, flows towards -X
    L.belt((-7, 7, -44.5, -38.5), 0.0, -BELT, 0.0)

    # 5. dark deck with a disc each side s 44.5..52.5, then the central disc C (4 arms) s 52.5..61.5
    L.slab(-3.5, 3.5, -52.5, -44.5, 0.0)
    L.disc(-7.0, -48.5, 7.0, 0.0)
    L.disc(7.0, -48.5, 7.0, 0.0)
    L.bars("disc_l", -7.0, -48.5, 0.0, 7.0, -DISC_A)
    L.bars("disc_r", 7.0, -48.5, 0.0, 7.0, DISC_A)
    L.disc(0, -57.0, 9.0, 0.0)
    L.bars("disc_c", 0, -57.0, 0.0, 9.0, -DISC_A)

    # 6. cross belt 2 s 61.5..70, one belt over the whole strip, flows towards -X
    L.belt((-9, 9, -70.0, -61.5), 0.0, -BELT, 0.0)

    # 7. gate deck s 70..75 (the wall stands ~1.5 E past the last belt strip), wall 1 (O C O O) s 75..76, corridor 76..84, wall 2 (O O O C) s 84..85
    w1, w2 = W1, W2
    L.slab(-9, 9, -w1, -70.0, 0.0)
    L.gate_wall("wall1", w1, 8.75, [-6.0, -1.0, 1.5, 6.5], phase=0.0)
    L.slab(-8.75, 8.75, -w2, -(w1 + 1.0), 0.0)
    L.gate_wall("wall2", w2, 8.75, [-6.0, -1.0, 1.5, 6.5], phase=1.0)

    # 8. stepping stones F1..F7 then slab S1 (9 x 11, top 1.5, s 127.5..138.5) with the first gantry spinner
    stones = [
        ("F1", 0.0, 96.0 - SH, 14.0, 5.0, -0.5),
        ("F2", -5.0, 103.0 - SH, 5.0, 4.0, 0.0),
        ("F3", 1.0, 109.0 - SH, 5.0, 4.5, 0.5),
        ("F4", 6.5, 114.5 - SH, 4.0, 4.0, 1.0),
        ("F5", 1.5, 120.0 - SH, 5.0, 4.5, 1.0),
        ("F6", -4.5, 125.5 - SH, 4.5, 4.0, 1.5),
        ("F7", 0.5, 131.0 - SH, 5.0, 4.0, 1.5),
    ]
    rects = {}
    for name, xc, sc, w, d, top in stones:
        L.slab(xc - w / 2, xc + w / 2, -(sc + d / 2), -(sc - d / 2), top)
        rects[name] = (R1(xc - w / 2, xc + w / 2, sc - d / 2, sc + d / 2), top)
        if name in ("F1", "F3", "F5", "F7"):
            L.pillar(xc, -sc, 2.0, top - 1.0)
    L.slab(-4.5, 4.5, -(145.5 - SH), -(134.5 - SH), 1.5)
    rects["S1"] = ((-4.5, 4.5, -(145.5 - SH), -(134.5 - SH)), 1.5)
    L.pillar(0, Z2, 3.0, 0.5)
    L.mast("z", (0.0, X1_Y, Z2 + 3.5), 1.5, X1_THICK)
    L.windmill("spin_x1", (0.0, X1_Y, Z2 + 3.5), "z", X1_ARM, -SPIN_X, thick=X1_THICK)

    # jumps of leg 1
    L.jump("gate 2 -> F1", R1(0.75, 2.25, w2, w2 + 1.0), rects["F1"][0], 0.0, -0.5, brink=(1.5, -(w2 + 1.0)), u=(0.0, -1.0), ref_gap_E=0.75)
    order = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "S1"]
    for a, b in zip(order, order[1:]):
        L.jump(f"{a} -> {b}", rects[a][0], rects[b][0], rects[a][1], rects[b][1])

    # =============================================================== LEG 2 (towards -X, centre line z = Z2; x = -t)
    # 9. bridge t 4.5..25.5 (4 m wide, top 1.5), no rails, the second gantry spinner at t 21.5
    L.slab(-25.5, -4.5, Z2 - 2.0, Z2 + 2.0, 1.5)
    L.carrier("x", (-21.5, X2_Y, Z2), X2_ARM, X2_THICK, 9.0, +1)
    L.windmill("spin_x2", (-21.5, X2_Y, Z2), "x", X2_ARM, SPIN_X, thick=X2_THICK)
    bridge = R2(4.5, 25.5, -2.0, 2.0)

    # 10. launch platform A t 27..35 (top 1.0, 8 m wide), two pads at t 28.8; slab B t 36..48 (top 7.0, 12 m wide) above two pillars
    padA = R2(27, 35, -5.5, 5.5)
    L.slab_r(padA, 1.0)
    L.jump("bridge -> launch platform A", bridge, padA, 1.5, 1.0, brink=(-25.5, Z2), u=(-1.0, 0.0), ref_gap_E=0.75)
    slabB = R2(36, 48, -6, 6)
    for i, dz in enumerate((-3.0, 3.0)):
        L.launch(f"pad_a{i + 1}", -28.8, 1.0, Z2 + dz, 3.0, (-1, 0), 7.0, slabB, aim=13.2)
    L.slab_r(slabB, 7.0)
    for dz in (-4.5, 4.5):
        L.pillar(-37.5, Z2 + dz, 2.0, 6.0)

    # 11. stairs (0.75 per step) t 48..51 and 51..54, launch platform C t 54..61.5 (top 9.25, 8 m wide), two pads at t 59.9
    st1, st2, padC = R2(48, 51, -5, 5), R2(51, 54, -4, 4), R2(54, 61.5, -5, 5)
    L.slab_r(st1, 7.75)
    L.slab_r(st2, 8.5)
    L.slab_r(padC, 9.25)
    L.jump("slab B -> step 1", slabB, st1, 7.0, 7.75, brink=(-48.0, Z2), u=(-1.0, 0.0))
    L.jump("step 1 -> step 2", st1, st2, 7.75, 8.5, brink=(-51.0, Z2), u=(-1.0, 0.0))
    L.jump("step 2 -> launch platform C", st2, padC, 8.5, 9.25, brink=(-54.0, Z2), u=(-1.0, 0.0))
    deckD = R2(65, 99, -4, 4)
    for dz in (-3.0, 3.0):
        L.launch(f"pad_c{1 if dz < 0 else 2}", -59.9, 9.25, Z2 + dz, 3.0, (-1, 0), 15.0, deckD, aim=11.0)

    # 12. long railed deck D t 65..99 (top 15.0, 8 m wide), arch pillars under its near end
    L.slab_r(deckD, 15.0)
    for dz in (-2.5, 2.5):
        L.pillar(-66.5, Z2 + dz, 2.0, 14.0)

    # 13. entry slab (the corner) t 99..113 (14 wide, top 15.0): the third gantry spinner at t 101, two hop pedestals at t 104
    entry = R2(99, 113, -7, 7)
    L.slab_r(entry, 15.0)
    L.mast("x", (-101.0, X3_Y, Z2), 15.0, X3_THICK)
    L.windmill("spin_x3", (-101.0, X3_Y, Z2), "x", X3_ARM, -SPIN_X, thick=X3_THICK)
    # the two entry pedestals throw over the disc field (three rows of spinners and belts, 33 m) onto the plain teal deck before the tower-base cluster (u 33.5..40.5)
    teal_deck = R3(-5, 5, 33.5, 40.5)
    L.pedestal("hop_entry_l", XC - 3.5, Z2 + 5.5, 15.0, aim=(XC - 3.0, Z3(36.0)), target_top=15.0, rect=teal_deck)
    L.pedestal("hop_entry_r", XC + 3.5, Z2 + 5.5, 15.0, aim=(XC + 3.0, Z3(36.0)), target_top=15.0, rect=teal_deck)

    # =============================================================== LEG 3 (towards +Z, centre line x = XC; z = Z3(u), u = metres forward from the entry slab)
    # 14. disc field. Row 1: three discs d 7 touching the slab; cross strips u 7..9 / 9..11, running opposite ways (+X / -X)
    for i, dx in enumerate((-7.5, 0.0, 7.5)):
        L.disc(XC + dx, Z3(3.5), 7.0, 15.0)
        L.bars(f"disc_r1_{i + 1}", XC + dx, Z3(3.5), 15.0, 7.0, DISC_B if i != 1 else -DISC_B)
    L.belt(R3(-11, 11, 7, 9), 15.0, BELT, 0.0)
    L.belt(R3(-11, 11, 9, 11), 15.0, -BELT, 0.0)
    # Row 2: a 4 m centre deck u 11..18.5 between two discs d 7 (u 14.75), then strips u 18.5..22.5 both running -X
    L.slab_r(R3(-1.5, 1.5, 11, 18.5), 15.0)
    for i, dx in enumerate((-5.25, 5.25)):   # base discs d 6.5 keep 0.5 m from the walkway and from the strips; the bars (8.5 m) overhang the rim and still sweep 1.25 m onto the walkway
        L.disc(XC + dx, Z3(14.75), 6.5, 15.0)
        L.bars(f"disc_r2_{i + 1}", XC + dx, Z3(14.75), 15.0, 6.5, DISC_A if i == 0 else -DISC_A, length=8.5)
    L.belt(R3(-11, 11, 18.5, 20.5), 15.0, -BELT, 0.0)
    L.belt(R3(-11, 11, 20.5, 22.5), 15.0, -BELT, 0.0)
    # Row 3: three discs d 7 (u 26), strips u 29.5..31.5 / 31.5..33.5 running opposite ways
    for i, dx in enumerate((-7.5, 0.0, 7.5)):
        L.disc(XC + dx, Z3(26.0), 7.0, 15.0)
        # the middle disc keeps ONE bar: with 4 blades no walker of tools/spinner_pass_check.gd crosses this row (0 of 60 steady starts, 0 of 24 waiting ones); with one bar the waiting walker does
        L.bars(f"disc_r3_{i + 1}", XC + dx, Z3(26.0), 15.0, 7.0, -DISC_B if i != 1 else DISC_B, bars=1 if i == 1 else 2)
    L.belt(R3(-11, 11, 29.5, 31.5), 15.0, -BELT, 0.0)
    L.belt(R3(-11, 11, 31.5, 33.5), 15.0, BELT, 0.0)
    # plain teal deck before the cluster u 33.5..40.5 (10 wide: the pedestal throws land 3 m either side of the middle, 2 m inside the edges)
    L.slab_r(teal_deck, 15.0)
    # Row 4: the tower-base cluster: centre disc d 10 (4 arms) u 40.5..50.5, side discs d 6 at dx +-9
    L.disc(XC, Z3(45.5), 10.0, 15.0)
    L.bars("disc_r4_c", XC, Z3(45.5), 15.0, 10.0, DISC_A)
    for dx in (-9.5, 9.5):
        L.disc(XC + dx, Z3(43.5), 6.0, 15.0)
        L.bars(f"disc_r4_{'l' if dx < 0 else 'r'}", XC + dx, Z3(43.5), 15.0, 6.0, DISC_B if dx < 0 else -DISC_B)

    # 15. launch platform E u 52..62 (top 15.0, 16 m wide), three pads at u 60; landing deck u 67..77 (top 21.0, 12 m wide), then a 8 m wide causeway u 77..89 with the big wheel
    # across it (hub at u 83, the lowest arm sweeps 0.75 m over the deck: the wheel has to be timed, a courier cannot walk round it), then the goal deck u 89..101
    platE = R3(-8, 8, 52, 62)
    L.slab_r(platE, 15.0)
    # from the centre disc's rim 2 m right of the middle (the arms of the cross lie along the middle line at clock 0), rim at u = 45.5 + sqrt(5^2 - 2^2)
    L.jump("disc r4 -> launch platform E", R3(1, 3, 49.0, 50.08), platE, 15.0, 15.0, run_up=1.0, brink=(XC + 2.0, Z3(50.08)), u=(0.0, 1.0))
    land_deck = R3(-6, 6, 67, 77)
    for i, dx in enumerate((-4.5, 0.0, 4.5)):
        L.launch(f"pad_e{i + 1}", XC + dx, 15.0, Z3(60.0), 3.0, (0, 1), 21.0, land_deck, aim=13.0)
    L.slab_r(land_deck, 21.0)
    for dx in (-4.5, 4.5):
        L.pillar(XC + dx, Z3(68.5), 2.0, 20.0)
    causeway = R3(-4, 4, 77, 89)
    L.slab_r(causeway, 21.0)
    for u in (80.0, 86.0):
        L.pillar(XC, Z3(u), 2.0, 20.0)
    L.carrier("z", (XC, 27.25, Z3(83.0)), 5.5, 1.25, 13.0, -1)
    L.windmill("wheel", (XC, 27.25, Z3(83.0)), "z", 5.5, SPIN_WHEEL, thick=1.25)
    goal_deck = R3(-6, 6, 89, 101)
    L.slab_r(goal_deck, 21.0)
    L.fence(XC - 6, XC + 6, Z3(89), Z3(101), 21.0, skip=("n",))   # the finish deck keeps its railing (the one exception: the show adds the hanging GOAL sign there)
    for dx in (-4.5, 4.5):
        L.pillar(XC + dx, Z3(91.5), 2.0, 20.0)

    # ---- path (walking surface, along the clean line)
    for p in [(0, 0, 0), (-2, 0, -16), (-2, 0, -30), (-2.5, 0, -34.25), (-2.5, 0, -40), (-2, 0, -43), (-1.5, 0, -48.5), (-1.5, 0, -52.5),
              (-2.5, 0, -57), (-2, 0, -61.5), (0, 0, -66), (1.5, 0, -70), (1.5, 0, -72.5), (1.5, 0, -w1), (1.5, 0, -(w1 + 5.0)), (1.5, 0, -(w2 + 1.0))]:
        P(*p)
    for name in order:
        r, top = rects[name]
        if name == "S1":
            P(2.5, top, Z2 + 2.0)   # round the first spinner's mast (x 0, z Z2 + 2, 2 m wide)
            P(2.5, top, Z2)
        P((r[0] + r[1]) / 2, top, (r[2] + r[3]) / 2)
    for t in (-7.0, -12.0, -16.0, -20.0, -24.0):
        P(t, 1.5, Z2)
    P(-28.8, 1.0, Z2 - 3.0)   # the route runs over a pad of each pair (a bot that follows it is thrown, as a player who steps on one is)
    P(-39.0, 7.0, Z2 - 3.0)
    for t, y in ((-44.0, 7.0), (-49.5, 7.75), (-52.5, 8.5), (-56.0, 9.25)):
        P(t, y, Z2)
    P(-59.9, 9.25, Z2 - 3.0)
    P(-68.0, 15.0, Z2 - 3.0)
    for t in (-74.0, -80.0, -86.0, -92.0, -98.0):
        P(t, 15.0, Z2)
    for t in (-100.0, -102.0, -104.0):
        P(t, 15.0, Z2 + 2.0)   # round the third spinner's mast (x -102.5, z Z2)
    P(XC, 15.0, Z2 + 2.0)
    for u in (3.5, 9.0, 14.75, 20.5, 26.0, 31.5, 37.0, 45.5, 51.0, 56.0):
        P(XC - (3.0 if u == 3.5 else 2.0) if u in (3.5, 26.0, 45.5) else XC, 15.0, Z3(u))
    for u in (64.0, 71.0, 77.0, 81.0, 85.0, 89.0, 93.0, 96.0):
        P(XC, 21.0 if u > 66.0 else 15.0, Z3(u))
    path = resample(path)

    # ---- checkpoints, one per landing of a section; the respawn ring (1.75 m round the middle of the volume's floor) stands on static floor clear of pads and bars
    def cp(rect, top, height=6.0):
        x0, x1, z0, z1 = rect
        return {"p": [q((x0 + x1) / 2), q(top + height / 2), q((z0 + z1) / 2)], "s": [q(x1 - x0), height, q(z1 - z0)], "yaw": 0.0}

    cps = [
        cp(R1(-3.5, 3.5, 44.5, 52.5), 0.0),
        cp(R1(-9.0, 9.0, 70.0, w1), 0.0),
        cp(R1(-8.75, 8.75, w1 + 1.0, w2), 0.0),
        cp(rects["F1"][0], -0.5),
        cp((-4.5, 4.5, rects["S1"][0][2], -130.5), 1.5),   # past the first gantry spinner (its arms sweep z -130..-129)
        cp(bridge, 1.5),
        cp(padA, 1.0),
        cp(slabB, 7.0),
        cp(padC, 9.25),
        cp(R2(65, 77, -4, 4), 15.0),
        cp(R2(102.5, 113, -7, 7), 15.0),                   # past the third gantry spinner (t 101)
        cp(R3(-8, 8, 52, 59), 15.0),
        cp(land_deck, 21.0),
    ]
    goal = {"p": [q(XC), 23.0, q(Z3(95.0))], "s": [8.0, 4.0, 8.0], "yaw": 0.0}
    L.cps = cps

    slots = [
        {"id": "arch_start", "p": [0.0, 5.5, -6.5], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "arch_finish", "p": [XC, 26.5, Z3(95.0)], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "floor_finish", "p": [XC, 21.0, Z3(95.0)], "yaw": 0.0, "size": [5.0, 5.0]},
    ]

    data = {
        "format": "level-1",
        "number": NUMBER,
        "title": "ROOFTOP RUN",
        "blurb": "Belts, spinning bars, gate walls, stepping stones, launch pads: reach the tower.",
        "rule": "CROSS THE ROOFTOPS  ·  REACH THE TOWER",
        "hint": "STAY ON THE DARK LANES  ·  PADS LAUNCH YOU UP",
        "modes": ["show"],
        "pool": False,
        "show": "race",
        "world": "daylight",
        "camera": "stage",
        "cap": 240,
        "note": "Race course at 1 E = 2.0 m. The course is ~350 m long, so it turns left twice (leg 1 along -Z, leg 2 along -X, leg 3 along +Z) to stay inside the +-150 m box.",
        "start": {"p": [0, 0, 0], "yaw": 0},
        "goal": goal,
        "path": path,
        "void_y": laser_plane.void_y(L.blocks),
        "kill": [],
        "checkpoints": cps,
        "blocks": L.blocks,
        "hazards": L.hazards,
        "slots": slots,
    }
    item_boxes_gen.rows_for(NUMBER, data)
    return data, L


def ring_check(L):
    """The respawn ring of 2..8 players (1.75 m round the middle of each checkpoint volume's floor, any turn) must stand on a static box top and stay clear of every launch pad."""
    bad = []
    pads = [h for h in L.hazards if h["k"] == "push"]
    for n, c in enumerate(L.cps):
        cx, cz = c["p"][0], c["p"][2]
        top = c["p"][1] - c["s"][1] / 2
        for deg in range(0, 360, 5):
            x, z = cx + 1.75 * math.cos(math.radians(deg)), cz + 1.75 * math.sin(math.radians(deg))
            tops = [b["p"][1] + b["s"][1] / 2 for b in L.blocks if b["k"] == "box" and abs(x - b["p"][0]) <= b["s"][0] / 2 and abs(z - b["p"][2]) <= b["s"][2] / 2
                    and abs(b["p"][1] + b["s"][1] / 2 - top) < 1.5 and b["s"][1] < 5.0 and b.get("m") != "belt"]
            if not tops:
                bad.append(f"checkpoint {n + 1}: no static floor at ring angle {deg}")
                break
            for h in pads:
                if h["p"][1] - 0.25 > top + 1.5 or h["p"][1] + 0.25 < top - 1.5:
                    continue
                if math.hypot(x - h["p"][0], z - h["p"][2]) < h["d"] / 2 + 0.4:
                    bad.append(f"checkpoint {n + 1}: ring angle {deg} touches pad {h['id']}")
                    break
    return bad


def main(argv):
    data, L = build()
    out = Path(__file__).resolve().parent.parent / "demo" / "levels" / "level_29.json"
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if "--emit-jumps" in argv:
        dest = Path(argv[argv.index("--emit-jumps") + 1])
        dest.write_text(json.dumps({"jumps": L.jumps, "movers": L.movers, "pads": L.pads}, indent=1) + "\n", encoding="utf-8")
    if "--report" in argv:
        report(data, L, out)


def pad_report(L):
    """The real flight of every launch pad (jump_reach.pad_flight: air brake to the walk speed, stick held forward): where it lands along the throw, the height over the target's near edge."""
    print(f"{'pad':8s} {'v_h':>5s} {'v_y':>5s} {'apex':>6s} {'edge+':>6s} {'land':>6s} {'near':>6s} {'far':>6s} {'to near':>7s} {'to far':>7s}")
    for p in L.pads:
        vx, vy, vz = p["v"]
        vh = math.hypot(vx, vz)
        x0, z0 = p["from"]
        tx0, tx1, tz0, tz1 = p["target"]
        if abs(vx) > abs(vz):
            near, far = ((x0 - tx1, x0 - tx0) if vx < 0 else (tx0 - x0, tx1 - x0))
        else:
            near, far = ((tz0 - z0, tz1 - z0) if vz > 0 else (z0 - tz1, z0 - tz0))
        dh = p["target_top"] - p["from_top"]
        dist, t_flight, apex = pad_flight(vh, vy, dh)
        edge = flight_height(vh, vy, near) - dh
        ok = near + 1.5 <= dist <= far - 1.5 and edge >= 1.0
        print(f"{p['id']:8s} {vh:5.1f} {vy:5.1f} {apex:6.2f} {edge:6.2f} {dist:6.2f} {near:6.1f} {far:6.1f} {dist - near:7.2f} {far - dist:7.2f} {'ok' if ok else 'CHECK'}")


def report(data, L, out):
    print(f"{out}: {len(L.blocks)} blocks, {len(L.hazards)} hazards, {len(data['checkpoints'])} checkpoints, path {len(data['path'])} points")
    plane = sum(math.hypot(a[0] - b[0], a[2] - b[2]) for a, b in zip(data["path"], data["path"][1:]))
    length = sum(math.dist(a, b) for a, b in zip(data["path"], data["path"][1:]))
    pads = len([p for p in L.pads])
    clean = plane / 5.0 * 1.10 + pads / 2 * 0.5 + 3 * 1.0  # +10 % for detours round bars and doors, launches and jumps ~0.5 s each, three stair steps
    print(f"path length {plane:.1f} m planar, {length:.1f} m in 3D; clean run at 5 m/s about {clean:.0f} s; median of ordinary players (x1.4) about {clean * 1.4:.0f} s")
    for line in ring_check(L) or ["respawn rings: static floor, clear of every pad"]:
        print(line)
    pad_report(L)
    print(f"{'jump':32s} {'gap':>5s} {'dh':>5s} {'max':>5s} {'0.8max':>6s} {'margin':>6s}")
    for j in L.jumps:
        lim = 0.8 * j["max_gap"]
        print(f"{j['name']:32s} {j['gap']:5.2f} {j['dh']:5.2f} {j['max_gap']:5.2f} {lim:6.2f} {lim - j['gap']:6.2f}{'  OVER' if j['gap'] > lim + 1e-9 else ''}")


if __name__ == "__main__":
    main(sys.argv[1:])
