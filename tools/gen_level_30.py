#!/usr/bin/env python3
"""Generates demo/levels/level_30.json (FERRY CROSSING, round r30), standard library only, same output on every run.

  python3 tools/gen_level_30.py                       # writes demo/levels/level_30.json
  python3 tools/gen_level_30.py --report              # also prints the counts, the table of the required jumps and the launch pads
  python3 tools/gen_level_30.py --emit-jumps out.json # writes every required static -> static jump (and the movers) for tools/race_jump_probe.gd

Layout: planned section by section on a tile grid, 1 E (a plan tile's edge) = 2.0 m, time x1.44.
Sections in order: start deck behind the gate, a field of stepping stones / launch pads / a short ferry, two 4-lane belt strips ending in a row of
three spinner discs, a court with two gate walls (blue chevron doors that slide up into their frames and down again), the first ferry crossing (rail ferry, two windmills, stepping stones,
three landing pillars with gates), a second court with two gate walls, the second ferry crossing (the same again), a 3-lane belt strip, a gate wall,
a small court with a 5-gate wall, a maze of cross belts, a turn deck with a launch pad, a stone and checker field, a big windmill over a ledge, a
field of six spinner discs, a long deck, a long checker deck, plates, three launch pads and the goal deck.

The course is ~550 m long, the level may not leave +-150 m, so it has four legs: leg 1 runs towards -Z from the start (to court 1), leg 2 runs
towards +X along z = -128 (crossing 1, court 2), leg 3 runs towards +Z along x = 99 (crossing 2, belts, court 3, maze, turn deck, then the stones,
ledge, discs and long deck), leg 4 runs towards -X along z = 85.5 (checker deck, plates, pads, goal).

The safe decks are narrow walkways with void on both sides (docs/level-format.md "Narrow safe decks"): courts 1 and 2 are 8 m necks (NECK) under their gate walls, turning into 12 m corner
walks, the turn deck is 8.5 m, the long deck 8 m with an 8 m arm towards the checker deck, the checker deck 8 m; the start deck, the pad decks, court 3 (crates), the landing apron
of the pillars and the goal deck keep their size.

Coordinates: a Leg maps (u, f) = (metres to the right of the leg's axis, metres run forward) to the world; every box is axis aligned.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jump_reach import max_gap, pad_flight, solve_pad  # noqa: E402
from pad_design import design_pad, ray_rect  # noqa: E402
import gate_piece  # noqa: E402
import laser_plane  # noqa: E402
import item_boxes_gen  # noqa: E402
import kit_grid  # noqa: E402

NUMBER = 30
G = 17.0
BELT = 7.0           # m/s: a belt across the course is 1.4 x the courier's walk (5 m/s, CourierMotion.WALK_SPEED): standing still is thrown off within about a second, a crossing is a straight run (tools/belt_cross_probe.gd)
BELT_LANE = 2.5      # m/s: a belt that runs back along the course (the lane strips) stays under the walk: faster than 5 m/s could not be run up at all
DOOR_W = 2.0
# Spinner rates (deg/s): a big wheel at 150 deg/s (5.0 deg per frame at 30 fps), the discs of the disc field about 165, the windmill pair of the ferry crossing 120,
# scaled for our courier (time x1.44) by 0.69: 150 x 0.69 = 105 for windmills, 105 and 120 for discs.
DISC_A = 105
DISC_B = 120       # the field of small discs (a cross of two bars: 4 blades) under the big windmill turns at the same original rate as every other spinner (nothing is slowed)
SPIN_X = 105
# the ferry crossing's windmills (two per crossing, one over each stone route)
WIND_U = 8.5       # m either side of the rail's axis
WIND_F = 27.25    # the plane of the arms: over the gap between the 5th and the 6th stone of each chain (a jump through the sweep, the stones either side are the pockets)
WIND_Y = 5.5       # hub height over the stones (top 0): the lowest tip sweeps 0.5 m over a stone
WIND_ARM = 5.0
WIND_THICK = 1.25
WIND_RATE = SPIN_X
# the big windmill over the ledge (14 m wide): arms that span it, the lowest tip 0.5 m over the ledge
BIG_ARM = 7.5
BIG_THICK = 1.5
BIG_RATE = SPIN_X
BIG_F = 35.5       # the arms' plane on the 3.5 m deep ledge (f 34.5..38): 1.3 m of ledge behind the sweep to wait on after the crossing
NECK = 4.0       # m: half the width of the 8 m necks of the courts (the gate walls of courts 1 and 2 span exactly the neck; their two doors stand at +-1.5)
DOCK_RUN = 4.5   # m: how far a dock pad slides along the rail (docks 8 m apart, 3 m long: 8 - 3 - 4.5 = 0.5 m between neighbours at the worst moment, at least 0.3 m is required)
WALL_H = 4.0    # m: the navy wall of a gate wall (tools/gate_piece.py: door period 4 s, open 1.25 s, shut 1.25 s)


def q(v):
    return round(v * 4.0) / 4.0


def dome_offset(thick):
    """m from a windmill's plane to the centre of the 1.25 m deep post or hanger that carries its hub: the hub's dome (style/spinner_look.gd `_hub_top`: hub radius 0.9 x the bar's, a cap 0.34 over
    the bar's face, a dome 0.64 of the hub radius less 6 cm) reaches 1.076 x thick + 0.33 from the plane, and the carrier's face meets it. Blocks stand on the 0.25 grid, so the face ends up
    5 to 7 cm inside the dome's tip (thick 1.25 and 1.5): the join has no gap."""
    return q(1.076 * thick + 0.33 - 0.05 + 0.625)


def qs(v):
    return round(v * 2.0) / 2.0


class Leg:
    """(u, f): u metres to the right of the axis, f metres forward; heading 'N' = -Z, 'E' = +X, 'S' = +Z, 'W' = -X."""

    def __init__(self, ox, oz, head):
        self.ox, self.oz = ox, oz
        self.fw = {"N": (0.0, -1.0), "E": (1.0, 0.0), "S": (0.0, 1.0), "W": (-1.0, 0.0)}[head]
        self.rt = {"N": (1.0, 0.0), "E": (0.0, 1.0), "S": (-1.0, 0.0), "W": (0.0, -1.0)}[head]
        self.yaw = {"N": 0, "E": -90, "S": 180, "W": 90}[head]   # yaw that turns a hazard's local +z towards the courier behind (a windmill's axis z)

    def pt(self, u, f):
        return (self.ox + u * self.rt[0] + f * self.fw[0], self.oz + u * self.rt[1] + f * self.fw[1])

    def rect(self, u0, u1, f0, f1):
        (xa, za), (xb, zb) = self.pt(u0, f0), self.pt(u1, f1)
        return (min(xa, xb), max(xa, xb), min(za, zb), max(za, zb))

    def vec(self, du, df):
        return (du * self.rt[0] + df * self.fw[0], du * self.rt[1] + df * self.fw[1])


def rect_center(r):
    return ((r[0] + r[1]) / 2, (r[2] + r[3]) / 2)


class Level:
    def __init__(self):
        self.blocks = []
        self.hazards = []
        self.jumps = []
        self.movers = []
        self.pads = []
        self.n_doors = 0

    # ---- blocks -------------------------------------------------------------------------------------------------
    def box(self, x, y, z, w, h, d, **kw):
        b = {"k": "box", "p": [q(x), q(y), q(z)], "s": [q(w), q(h), q(d)]}
        b.update(kw)
        self.blocks.append(b)

    def cyl(self, x, y, z, d, h, **kw):
        b = {"k": "cyl", "p": [q(x), q(y), q(z)], "d": q(d), "h": q(h)}
        b.update(kw)
        self.blocks.append(b)

    def slab(self, rect, top, thick=1.0, **kw):
        x0, x1, z0, z1 = rect
        self.box((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2, x1 - x0, thick, z1 - z0, **kw)

    def belt(self, rect, top, vel):
        self.slab(rect, top, m="belt", belt=[qs(vel[0]), qs(vel[1])])

    def wall_box(self, rect, y0, y1, **kw):
        x0, x1, z0, z1 = rect
        self.box((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, x1 - x0, y1 - y0, z1 - z0, **kw)

    # ---- hazards ------------------------------------------------------------------------------------------------
    def disc(self, cx, cz, d, top, hid, rate, arms):
        """Static disc with a hub, and bars (2 or 4 arms) lying just over it turning about y."""
        self.cyl(cx, top - 0.5, cz, d, 1.0, tone="disc")    # the yellow disc
        self.cyl(cx, top + 0.5, cz, 1.5, 1.0, tone="hub")  # the blue hub
        arm = d / 2 - 0.25
        parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [q(2 * arm), 1.0, 1.0]}]
        if arms == 4:
            parts.append({"k": "box", "p": [0.0, 0.0, 0.0], "s": [q(2 * arm), 1.0, 1.0], "r": [0, 90, 0]})
        self.hazards.append({"k": "spin", "id": hid, "p": [q(cx), q(top + 0.75), q(cz)], "axis": "y", "rate": rate, "hit": True, "parts": parts})

    def windmill(self, hid, leg, u, f, y, arm, rate, thick=1.0):
        """Four arms (a + of two crossing bars) in the plane across the leg, turning about the leg's axis."""
        x, z = leg.pt(u, f)
        L = q(2 * arm)
        parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [L, thick, thick]}, {"k": "box", "p": [0.0, 0.0, 0.0], "s": [thick, L, thick]}]
        self.hazards.append({"k": "spin", "id": hid, "p": [q(x), q(y), q(z)], "r": [0, leg.yaw, 0], "axis": "z", "rate": rate, "hit": True, "parts": parts})

    def leg_box(self, leg, u, f, y0, y1, wu, wf, **kw):
        """A box of width wu across the leg and wf along it, centred on (u, f), from y0 to y1."""
        x, z = leg.pt(u, f)
        w, d = (wf, wu) if leg.fw[0] != 0 else (wu, wf)
        self.box(x, (y0 + y1) / 2, z, w, y1 - y0, d, **kw)

    def windmill_frame(self, leg, f, us, y, arm, thick, post_u):
        """The frame that carries windmills of `arm` m with hubs at (u in us, f) and height y: it stands `dome_offset` m before their plane; each hub's dome touches the face of a 2.5 m wide bracket
        that drops from the lintel to a metre under the hub; the 1.5 m high lintel (1.75 m deep) has its underside 0.5 m over the sweep and rests on two masonry posts (2 m wide, 1.25 m deep, the
        kit's plain stone) outside the sweep (u +-post_u) that rise from under the world (a racer who is flung off meets nothing)."""
        fg = f - dome_offset(thick)
        under = math.ceil((y + arm + thick / 2 + 0.5) * 4.0) / 4.0
        lintel_y = under + 0.75
        for u in us:
            self.leg_box(leg, u, fg, y - 1.0, lintel_y, 2.5, 1.25, tone="frame")      # the bracket under the lintel, behind the hub
        for u in (-post_u, post_u):
            self.leg_box(leg, u, fg, -12.0, lintel_y + 1.0, 2.0, 1.25, tone="stone_plain")
        self.leg_box(leg, 0.0, fg, lintel_y - 0.75, lintel_y + 0.75, 2 * post_u, 1.75, tone="frame")      # a quarter metre deeper than the posts and brackets: no coplanar faces

    def ferry(self, hid, rect_start, top, size, to, period, pause, phase=0.0):
        cx, cz = rect_center(rect_start)
        w, d = size
        h = {"k": "slide", "id": hid, "p": [q(cx), q(top - 0.25), q(cz)], "to": [q(to[0]), 0.0, q(to[1])], "period": period, "pause": pause,
             "s": [q(w), 0.5, q(d)], "hit": False}
        if phase:
            h["phase"] = phase
        self.hazards.append(h)
        self.movers.append({"id": hid, "kind": "slide", "p": [q(cx), q(top), q(cz)], "to": [q(to[0]), 0.0, q(to[1])], "period": period, "pause": pause,
                            "size": [q(w), q(d)], "phase": phase})

    def pad(self, hid, x, top, z, aim, aim_top, target_rect, size=3.0, full=False):
        """A push pad on a floor of height `top` at (x, z); the throw is designed (design_pad) to land at `aim` on a floor `aim_top` inside target_rect. The pad is a round button of `size` m
        on exactly a 2 x 2 block of the platform's tiles (tools/kit_grid.py): the platform is widened when it has no such cell, the pad centre moves to the cell's centre.
        `full`: the platform is a small stone that only holds this pad: the pad is centred on it and covers the whole tile grid (size = the grid's side less 0.2 m)."""
        block = kit_grid.block_under(self.blocks, x, z, top)
        if full:
            # a small stone that exists to hold this pad: one round pad over the whole tile grid (3 x 3 tiles on a 4.5 m stone), centred on the stone
            cell = kit_grid.full_cell(block) if block is not None else None
            assert cell, f"{hid}: no n x n tile stone under the pad"
            x, z, size = cell[0], cell[1], round(cell[2] - 0.2, 1)
        elif block is not None:
            kit_grid.grow_for_cell(block, x, z)
            x, z = kit_grid.snap(self.blocks, x, z, top, [tuple(p["from"]) for p in self.pads])
        v, info = design_pad((x, z), top, aim, aim_top, target_rect, MAX_PAD_SPEED)
        self.pads.append({"id": hid, "from": [round(x, 2), round(z, 2)], "from_top": top, "v": v, "target_top": aim_top, "target": [round(c, 2) for c in target_rect], "flight": info})
        self.hazards.append({"k": "push", "id": hid, "g": "cyl", "p": [round(x, 2), q(top + 1.0), round(z, 2)], "d": q(size), "h": 0.5, "v": [qs(v[0]), qs(v[1]), qs(v[2])]})

    # ---- gate wall ----------------------------------------------------------------------------------------------
    def gate_wall(self, leg, name, f0, u0, u1, y0, gates, phase=0.0):
        """A gate wall across u0..u1 at f0..f0+1 on a floor whose top is y0 (tools/gate_piece.py): one navy quilted wall per stretch between the frames, a frame with two eyes and a
        sliding chevron door per gate; gates: [(u, width)], two side by side need 1.0 m between their openings."""
        piece = gate_piece.gate_wall(leg.rect, f0, y0, u0, u1, gates, name, wall_h=WALL_H, phase=phase)
        self.blocks.extend(piece["blocks"])
        self.hazards.extend(piece["hazards"])
        self.n_doors += piece["doors"]

    def fence(self, rect, top, skip=()):
        """1 m rail boxes round a rectangle; skip: world sides among 'n' (z0), 's' (z1), 'w' (x0), 'e' (x1)."""
        x0, x1, z0, z1 = rect
        h = 1.0
        if "n" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z0 + 0.25, x1 - x0, h, 0.5, tone="frame")
        if "s" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z1 - 0.25, x1 - x0, h, 0.5, tone="frame")
        if "w" not in skip:
            self.box(x0 + 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0, tone="frame")
        if "e" not in skip:
            self.box(x1 - 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0, tone="frame")

    # ---- jumps --------------------------------------------------------------------------------------------------
    def jump(self, name, frm, to, from_top, top, run_up=3.0, ref_gap_E=None, on_belt=False, along=None, brink=None):
        """frm / to: world rects (x0, x1, z0, z1). Euclidean gap between the closest points (brink -> landing point), run-up on the take-off rect."""
        (fx0, fx1, fz0, fz1), (tx0, tx1, tz0, tz1) = frm, to
        cx = min(max((tx0 + tx1) / 2, fx0), fx1)
        cz = min(max((tz0 + tz1) / 2, fz0), fz1)
        px = min(max(cx, tx0), tx1)
        pz = min(max(cz, tz0), tz1)
        bx = min(max(px, fx0), fx1)
        bz = min(max(pz, fz0), fz1)
        if brink is not None:      # a take-off point given by the caller (a disc: a point on its rim, off the hub)
            bx, bz = brink
        qx = min(max(bx, tx0), tx1)
        qz = min(max(bz, tz0), tz1)
        d = math.hypot(qx - bx, qz - bz)
        if d < 1e-6:
            u = along        # touching rects (a step up): the brink is the shared edge, the run-up comes along the course
        else:
            u = ((qx - bx) / d, (qz - bz) / d)
        run = ray_exit((bx, bz), (-u[0], -u[1]), frm)
        run = min(run_up, run)
        start = (bx - u[0] * run, bz - u[1] * run)
        dh = top - from_top
        j = {"level": NUMBER, "name": name, "start": [q(start[0]), q(start[1])], "u": [round(u[0], 4), round(u[1], 4)], "edge": [q(bx), q(bz)],
             "from_top": from_top, "top": top, "poly": [[tx0, tz0], [tx1, tz0], [tx1, tz1], [tx0, tz1]], "gap": round(d, 3), "run_up": round(run, 2),
             "dh": round(dh, 3), "max_gap": round(max_gap(dh, run), 2), "ref_gap_E": ref_gap_E}
        if on_belt:
            j["on_belt"] = True
        self.jumps.append(j)


def ray_exit(p, u, rect):
    x0, x1, z0, z1 = rect
    best = 1e9
    for pi, ui, lo, hi in ((p[0], u[0], x0, x1), (p[1], u[1], z0, z1)):
        if abs(ui) < 1e-9:
            continue
        best = min(best, ((hi if ui > 0 else lo) - pi) / ui)
    return max(best, 0.0)


def resample(path, step=5.5):
    out = [path[0]]
    for a, b in zip(path, path[1:]):
        flat = math.hypot(b[0] - a[0], b[2] - a[2])
        n = max(1, math.ceil(flat / step))
        for i in range(1, n + 1):
            out.append([q(a[k] + (b[k] - a[k]) * i / n) for k in range(3)])
    return out


MAX_PAD_SPEED = 13.5   # m/s horizontal cap of a throw
MARGIN_MIN = 1.5       # m the landing keeps from every edge of its target


def build():
    L = Level()
    path = []
    counter = {"pad": 0}

    def P(leg, u, f, y):
        x, z = leg.pt(u, f)
        path.append([q(x), q(y), q(z)])

    def pad_id():
        counter["pad"] += 1
        return f"pad_{counter['pad']}"

    leg1 = Leg(0.0, 0.0, "N")          # start -> court 1
    leg2 = Leg(20.0, -128.0, "E")      # crossing 1, court 2
    leg3 = Leg(99.0, -116.0, "S")      # crossing 2, belts, court 3, maze, turn deck
    leg3b = Leg(99.0, 11.0, "S")       # stones, ledge, discs, step, long deck
    leg4 = Leg(89.0, 85.5, "W")        # long checker deck, plates, pads, goal
    r1, r2, r3, r3b, r4 = leg1.rect, leg2.rect, leg3.rect, leg3b.rect, leg4.rect

    def chain(name, start_rect, start_top, stones, leg, end=None, warm=(), run_ups=None):
        """warm: indexes of the stones drawn as cream-and-orange checker plates. run_ups: {stone index: m} a shorter run-up for the jump from that stone (the first 3 m of a 3 m stone can lie in a windmill's sweep: timing, not reach)."""
        prev, prev_top = start_rect, start_top
        for i, (u, f, w, d, top) in enumerate(stones):
            rect = leg.rect(u - w / 2, u + w / 2, f - d / 2, f + d / 2)
            L.slab(rect, top, 1.0, **({"tone": "warm"} if i in warm else {}))
            L.jump(f"{name} {i + 1}", prev, rect, prev_top, top, **({"run_up": run_ups[i - 1]} if run_ups and (i - 1) in run_ups else {}))
            prev, prev_top = rect, top
        if end:
            L.jump(f"{name} out", prev, end[0], prev_top, end[1])
        return prev

    # ====================== LEG 1 =================================================================================
    # court 1: an 8 m neck over the two gate walls (f 90.5..121.5), then a 12.5 m deep corner walk to the crossing's dock (z -134..-121.5, x -4..20); the walls' doors stay at +-1.5
    court1 = r1(-NECK, NECK, 90.5, 121.5)
    corner1 = r1(-NECK, 20.0, 121.5, 134.0)
    # ---- start deck and pen (copy of the show start: pen walls, gate, arch) -----------------------------------
    pen_deck = r1(-9, 9, -8.5, 11)         # the pen: as wide as its rails, so nobody can hop a rail onto a deck beside it and skip the gate
    start_deck = r1(-18, 18, 11, 20)       # the deck in front of the pen
    L.slab(pen_deck, 0.0, 2.0)
    L.slab(start_deck, 0.0, 2.0)
    # 1 m rails round the pen, not walls: the stage camera orbits 12 m from the courier and ignores collision, so a wall of the pen's height would put the camera inside it
    L.wall_box(r1(-9.0, -8.5, -8.5, 11.0), -1.0, 1.0)
    L.wall_box(r1(8.5, 9.0, -8.5, 11.0), -1.0, 1.0)
    L.wall_box(r1(-9.0, 9.0, -9.0, -8.5), -1.0, 1.0)
    L.hazards.append({"k": "blink", "id": "gate", "slot": "gate", "p": [0.0, 2.0, -4.75], "s": [17.0, 4.0, 0.5], "on": 4.0, "off": 600.0, "warn": 1.0, "hit": False})
    for ux in (-8.75, 8.75):                # two thin posts carry the banner beam
        L.wall_box(r1(ux - 0.3, ux + 0.3, 9.75, 10.25), -1.0, 7.0)
    L.box(0.0, 8.25, -10.0, 16.5, 2.5, 0.5)   # banner beam over the pen's front

    # ---- S1: stepping stones, two launch-pad islands, a short ferry (centre) -----------------------------------
    belt_L = r1(-12, -4, 52, 82)
    belt_R = r1(4, 12, 52, 82)
    left = [  # (u, f, w, d, top)
        (-10.0, 23.5, 3, 3, -0.5), (-10.0, 28.5, 3, 3, 0.0), (-10.0, 34.5, 4.5, 4.5, -0.5), (-8.0, 41.25, 3, 3, 0.0),
        (-8.0, 46.5, 3, 3, -0.5), (-8.0, 50.0, 3, 3, 0.0)]
    right = [
        (10.0, 22.5, 3, 3, -1.0), (9.5, 27.5, 3, 3, -0.5), (10.0, 33.5, 4.5, 4.5, -1.0), (8.5, 40.25, 3, 3, -0.5),
        (8.0, 45.5, 3, 3, 0.0), (8.0, 49.5, 3, 3, 0.0)]
    chain("S1 left stone", start_deck, 0.0, left, leg1, end=(belt_L, 0.0))
    chain("S1 right stone", start_deck, 0.0, right, leg1, end=(belt_R, 0.0))
    # centre: the short ferry from the deck edge to an island between the belt strips; it waits at the deck when the gate opens. 0.5 m of air at both ends of its run (a mover keeps at least 0.3 m
    # off every block, tools/mover_clearance_check.py)
    island_c = r1(-3, 3, 47, 52)
    L.slab(island_c, 0.0, 1.0)
    L.ferry("ferry_a", r1(-2.25, 2.25, 20.5, 25.0), 0.0, (4.5, 4.5), (0.0, -21.0), 24.0, 3.0, phase=17.0)
    L.jump("S1 island to belt L", island_c, belt_L, 0.0, 0.0)
    L.jump("S1 island to belt R", island_c, belt_R, 0.0, 0.0)
    # launch pads on two side islands (off the stone chains): they throw the courier onto the strips, skipping the last stones
    isl_l = r1(-15.75, -11.25, 42.25, 46.75)
    isl_r = r1(11.25, 15.75, 41.75, 46.25)
    L.slab(isl_l, 0.0, 1.0)
    L.slab(isl_r, -0.5, 1.0)
    L.jump("S1 left stone 4 to pad island", r1(-9.5, -6.5, 39.75, 42.75), isl_l, 0.0, 0.0)
    L.jump("S1 right stone 5 to pad island", r1(6.5, 9.5, 44.0, 47.0), isl_r, -0.0, -0.5)
    pl, pr = leg1.pt(-13.5, 44.5), leg1.pt(13.5, 44.0)
    L.pad(pad_id(), pl[0], 0.0, pl[1], leg1.pt(-7.0, 54.5), 0.0, belt_L, full=True)
    L.pad(pad_id(), pr[0], -0.5, pr[1], leg1.pt(9.0, 54.5), 0.0, belt_R, full=True)

    # ---- S2: two 4-lane strips, every lane a belt back towards the start (no static lane to walk past them on) ---
    for x0 in (-12, 4):
        for lane in range(4):
            u0 = x0 + 2 * lane
            L.belt(r1(u0, u0 + 2, 52, 82), 0.0, leg1.vec(0.0, -BELT_LANE))

    # ---- S3: a row of three spinner discs (a cross of 2 bars, 4 blades, each) -------------------------------------------------------
    for i, (u, rate) in enumerate(((-8.0, DISC_A), (0.0, -DISC_A), (8.0, DISC_A))):
        cx, cz = leg1.pt(u, 86.25)
        L.disc(cx, cz, 7.5, 0.0, f"disc_a{i + 1}", rate, 4)

    # ---- S4: court 1, two gate walls --------------------------------------------------------------------------
    L.slab(court1, 0.0, 4.0, tone="court")
    L.slab(corner1, 0.0, 4.0, tone="court")
    L.gate_wall(leg1, "w1a", 100.0, -NECK, NECK, 0.0, [(-1.5, DOOR_W), (1.5, DOOR_W)], phase=0.0)
    L.gate_wall(leg1, "w1b", 118.0, -NECK, NECK, 0.0, [(-1.5, DOOR_W), (1.5, DOOR_W)], phase=1.0)

    # ====================== FERRY CROSSING (twice: leg 2 and leg 3) ===============================================
    left2 = [(-7.0, 4.0, 3, 3, -0.5), (-7.5, 9.0, 3, 3, 0.0), (-8.0, 14.0, 3, 3, -0.5), (-9.0, 19.5, 4.5, 4.5, 0.0),
             (-8.0, 24.5, 3, 3, 0.5), (-8.5, 29.0, 3, 3, 0.0), (-8.0, 33.5, 3, 3, -0.5)]
    right2 = [(7.75, 4.5, 3, 3, 0.0), (8.0, 9.0, 3, 3, -0.5), (8.0, 14.5, 3, 3, 0.0), (9.0, 20.0, 4.5, 4.5, -0.5),
              (8.0, 25.5, 3, 3, 0.0), (8.5, 30.0, 3, 3, 0.5), (8.0, 34.5, 3, 3, 0.0)]

    def crossing(leg, tag, ferry_id, start_rect):
        """Rail ferry (31.5 m), two windmills over it, stepping stones either side, two launch pads and three landing pillars with a gate pair each."""
        rr = leg.rect
        pillar_L = rr(-8.5, -3.5, 37, 42.5)
        pillar_C = rr(-2.5, 2.5, 37, 42.5)
        pillar_R = rr(3.5, 8.5, 37, 42.5)
        chain(f"S5{tag} left stone", start_rect, 0.0, left2, leg, end=(pillar_L, 0.0), run_ups={5: 1.8})
        chain(f"S5{tag} right stone", start_rect, 0.0, right2, leg, end=(pillar_R, 0.0))
        L.ferry(ferry_id, rr(-2.25, 2.25, 0.5, 5.0), 0.0, (4.5, 4.5), tuple(leg.vec(0.0, 31.5)), 30.0, 2.0)   # 0.5 m of air to the court and to the pillar at the ends of its run
        # the docked pads beside the rail (blue machines): three 3 x 3 m ones (2 x 2 tiles) at the dock on the right of the rail, each running 4.5 m along it and back (the docks are 8 m apart and 3 m long, so two neighbours at opposite ends of their runs still stand 0.5 m apart; a longer run lets them meet)
        for k, f0 in enumerate((0.5, 8.5, 16.5)):
            dock = rr(2.85, 5.85, f0, f0 + 3.0)
            L.ferry(f"{ferry_id}_dock{k + 1}", dock, 0.0, (dock[1] - dock[0], dock[3] - dock[2]), tuple(leg.vec(0.0, DOCK_RUN)), 12.0, 1.5, phase=4.0 * k)
        # windmills over the two stone routes (the ferry in the middle stays clear: 2.25 m either side of the rail): each hub stands over the stone the route crosses at the arms'
        # plane (u -+8.5, f 27.25: over the gap before the stone), arms 5.0 m (a 10 m + bar pair) so the sweep covers the whole width of the stone, the lowest tip 0.5 m over the stone's top (hub 5.5 m up)
        for k, u in enumerate((-WIND_U, WIND_U)):
            L.windmill(f"wind_{tag}{k + 1}", leg, u, WIND_F, WIND_Y, WIND_ARM, WIND_RATE, thick=WIND_THICK)
        L.windmill_frame(leg, WIND_F, (-WIND_U, WIND_U), WIND_Y, WIND_ARM, WIND_THICK, 15.0)
        # pads on two side islands beside the stone chains (off the route): they throw the courier onto the landing pillar in front of the gates
        isl_l = rr(-15.75, -11.25, 29.25, 33.75)
        isl_r = rr(11.25, 15.75, 29.75, 34.25)
        L.slab(isl_l, 0.0, 1.0)
        L.slab(isl_r, -0.5, 1.0)
        L.jump(f"S5{tag} left stone 6 to pad island", rr(-10.0, -7.0, 27.5, 30.5), isl_l, 0.0, 0.0)
        L.jump(f"S5{tag} right stone 6 to pad island", rr(7.0, 10.0, 28.5, 31.5), isl_r, 0.5, -0.5)
        lp, rp = leg.pt(-13.5, 31.5), leg.pt(13.5, 32.0)
        L.pad(pad_id(), lp[0], 0.0, lp[1], leg.pt(-6.0, 39.25), 0.0, rr(-8.5, -3.5, 37.0, 41.5), full=True)
        L.pad(pad_id(), rp[0], -0.5, rp[1], leg.pt(6.0, 39.25), 0.0, rr(3.5, 8.5, 37.0, 41.5), full=True)
        # landing pillars: stone pillars with a gate pair each (the two doors slide up and down half a period apart)
        for k, (nm, pr_, uc) in enumerate(((f"p{tag}l", pillar_L, -6.0), (f"p{tag}c", pillar_C, 0.0), (f"p{tag}r", pillar_R, 6.0))):
            L.slab(pr_, 0.0, 6.0)
            L.gate_wall(leg, nm, 41.5, uc - 2.5, uc + 2.5, 0.0, [(uc - 1.25, 1.5), (uc + 1.25, 1.5)], phase=1.0 * k)

    # ====================== LEG 2: crossing 1 and court 2 ==========================================================
    crossing(leg2, "a", "ferry_b", corner1)
    # court 2: the 17 m apron the landing pillars open onto (5.5 m deep), an 8 m neck over the two gate walls, and a 12 m corner walk (x 92.75..105, z -134..-116) that turns into leg 3
    apron2 = r2(-8.5, 8.5, 42.5, 48.0)
    neck2 = r2(-NECK, NECK, 48.0, 72.75)
    corner2 = r2(-6.0, 12.0, 72.75, 85.0)
    for part in (apron2, neck2, corner2):
        L.slab(part, 0.0, 4.0, tone="court")
    L.gate_wall(leg2, "w2a", 50.0, -NECK, NECK, 0.0, [(-1.5, DOOR_W), (1.5, DOOR_W)], phase=0.5)
    L.gate_wall(leg2, "w2b", 68.0, -NECK, NECK, 0.0, [(-1.5, DOOR_W), (1.5, DOOR_W)], phase=1.5)

    # ====================== LEG 3: crossing 2, belts, court 3, maze, turn deck =====================================
    crossing(leg3, "b", "ferry_c", corner2)
    L.slab(r3(-8.5, 8.5, 42.5, 47), 0.0, 1.0)
    for u0 in (-4.5, -1.5, 1.5):
        L.belt(r3(u0, u0 + 3, 47, 70), 0.0, leg3.vec(0.0, -BELT_LANE))        # back along the course, all three lanes
    court3 = r3(-12, 12, 70, 87)
    L.slab(court3, 0.0, 4.0, tone="court")
    L.gate_wall(leg3, "w3", 70.0, -12, 12, 0.0, [(-8.0, DOOR_W), (-3.0, DOOR_W), (0.0, DOOR_W), (3.0, DOOR_W), (8.0, DOOR_W)], phase=0.0)
    # four crates slide across the court (the two near ones towards the middle, the two far ones away from it: the middle lane keeps 3 m)
    for i, (u, f, du) in enumerate(((-8.0, 75.0, 5.0), (8.0, 75.0, -5.0), (-3.5, 82.0, -5.0), (3.5, 82.0, 5.0))):
        cx, cz = leg3.pt(u, f)
        vx, vz = leg3.vec(du, 0.0)
        L.hazards.append({"k": "slide", "id": f"crate_{i + 1}", "p": [q(cx), 1.5, q(cz)], "to": [q(vx), 0.0, q(vz)], "period": 9.0, "pause": 0.5, "phase": 1.5 * i, "hit": True,
                          "parts": [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [3.0, 3.0, 3.0], "tone": "crate"}]})
    L.gate_wall(leg3, "w4", 86.0, -12, 12, 0.0, [(-8.0, DOOR_W), (-4.0, DOOR_W), (0.0, DOOR_W), (4.0, DOOR_W), (8.0, DOOR_W)], phase=1.0)

    # ---- cross-belt maze: seven rows, each 0.5 m higher than the one before ------------------------------------
    rows = [(-12, 6, +1), (-5, 12, -1), (-12, 6, +1), (-5, 12, -1), (-12, 6, +1), (-5, 12, -1), (-12, 6, +1)]
    row_rects = []
    for i, (u0, u1, d) in enumerate(rows):
        f0 = 87.0 + 3.5 * i
        rr_ = r3(u0, u1, f0, f0 + 3.5)
        top = -0.5 + 0.5 * i
        L.belt(rr_, top, leg3.vec(d * BELT, 0.0))
        row_rects.append((rr_, top))
    for i in range(len(rows) - 1):
        (a, ta), (b, tb) = row_rects[i], row_rects[i + 1]
        # up the step on the strip's overlap: run-up along the course (the belt carries sideways)
        ou0, ou1 = max(rows[i][0], rows[i + 1][0]), min(rows[i][1], rows[i + 1][1])
        um = (ou0 + ou1) / 2
        step_from = r3(um - 1.0, um + 1.0, 87.0 + 3.5 * i, 87.0 + 3.5 * (i + 1))
        step_to = r3(um - 1.0, um + 1.0, 87.0 + 3.5 * (i + 1), 87.0 + 3.5 * (i + 2))
        L.jump(f"S7 row {i + 1} to {i + 2} (step {tb - ta:.1f})", step_from, step_to, ta, tb, run_up=2.5, on_belt=True, along=leg3.fw)
    turn_deck = r3(-3.25, 5.25, 111.5, 127)   # 8.5 m wide, the route on its left, the pad's tile cell (u 1.5..4.5) beside it
    L.slab(turn_deck, 3.0, 4.0)
    last_rect, last_top = row_rects[-1]
    L.jump("S7 last row to deck (step 0.5)", r3(-1, 1, 108.5, 111.5), r3(-1, 1, 111.5, 114.5), last_top, 3.0, run_up=2.5, on_belt=True, along=leg3.fw)

    # ====================== LEG 3b: stone field, big windmill, discs, step, long deck ===============================
    stones3 = [(0.0, 4.5, 4.5, 4.5, 2.0), (-1.0, 10.0, 4.5, 4.5, 2.0), (3.0, 16.0, 4.5, 4.5, 2.5), (-1.0, 21.5, 4.5, 4.5, 2.0), (-5.0, 27.0, 4.5, 4.5, 2.5), (0.0, 32.0, 4.5, 4.5, 3.0)]
    ledge = r3b(-7, 7, 34.5, 38.0)
    chain("S8 stone", turn_deck, 3.0, stones3, leg3b, end=(ledge, 3.0), warm=(1, 3))
    L.slab(ledge, 3.0, 3.0)
    # two side stones off the chain (the second carries a pad that throws onto the ledge) and a pad on the turn deck beside the route
    side_a = r3b(5.5, 10.0, 18.0, 22.5)
    side_b = r3b(6.0, 10.5, 23.5, 28.0)
    L.slab(side_a, 2.0, 1.0)
    L.slab(side_b, 2.0, 1.0)
    L.jump("S8 stone 3 to side stone A", r3b(0.75, 5.25, 13.75, 18.25), side_a, 2.5, 2.0)
    L.jump("S8 side stone A to B", side_a, side_b, 2.0, 2.0)
    pp1 = leg3b.pt(3.0, -1.5)
    pp2 = leg3b.pt(8.0, 25.5)
    L.pad(pad_id(), pp1[0], 3.0, pp1[1], leg3b.pt(-1.0, 10.0), 2.0, r3b(-3.25, 1.25, 7.75, 12.25))
    L.pad(pad_id(), pp2[0], 2.0, pp2[1], leg3b.pt(4.0, 36.25), 3.0, ledge, full=True)
    # big windmill over the ledge: its lowest arm sweeps 0.5 m above the ledge, the circle of the arms spans the whole 14 m of the ledge
    L.windmill("wind_big", leg3b, 0.0, BIG_F, 3.0 + BIG_ARM + 0.5, BIG_ARM, BIG_RATE, thick=BIG_THICK)
    L.windmill_frame(leg3b, BIG_F, (0.0,), 3.0 + BIG_ARM + 0.5, BIG_ARM, BIG_THICK, 9.5)

    # a field of six spinner discs (4 blades each) in two rows of three with a static stone between the rows to wait on: with the windmill's pocket on the ledge, the courier crosses
    # one sweep at a time (tools/spinner_pass_check.gd proves the crossing: a steady walk set off at the right moment, or one that waits on the stones, gets through)
    discs = []
    for f, us in ((42.0, (-7.75, 0.0, 7.75)), (57.0, (-7.75, 0.0, 7.75))):
        for u in us:
            discs.append((u, f))
    for i, (u, f) in enumerate(discs):
        cx, cz = leg3b.pt(u, f)
        L.disc(cx, cz, 7.0, 2.0, f"disc_b{i + 1}", DISC_B if i % 2 == 0 else -DISC_B, 4)
    L.slab(r3b(-9.0, 9.0, 47.0, 51.5), 2.0, 1.0)      # the stone between the rows (no arm reaches it: the discs' bars sweep 3.25 m from their hubs)

    step = r3b(-4, 4, 62.5, 65.5)
    teal = r3b(-4, 4, 67, 78.5)               # the long deck: an 8 m walkway that turns west towards the checker deck (teal_e), so the whole course turns on 8 m of floor
    teal_e = r3b(4, 10, 70.5, 78.5)           # its arm: the same 8 m (z 81.5..89.5) as the checker deck it jumps to
    L.slab(step, 3.0, 1.0)
    L.slab(teal, 4.0, 3.0)
    L.slab(teal_e, 4.0, 3.0)
    dc = r3b(-3.75, 3.75, 53.25, 60.75)       # a disc's bounding square on the near side
    disc_brink = leg3b.pt(1.5, 57.0 + math.sqrt(3.75 ** 2 - 1.5 ** 2))   # on the disc's rim, 1.5 m beside the hub's line
    L.jump("S10 disc to step (+1.0)", dc, step, 2.0, 3.0, run_up=2.5, brink=disc_brink)
    L.jump("S10 step to long deck (+1.0)", step, teal, 3.0, 4.0)

    # ====================== LEG 4: long checker deck, plates, pads, goal ===========================================
    checker = r4(-4, 4, 2.5, 28.5)            # 8 m wide
    plate1 = r4(-2.25, 2.25, 31.25, 35.75)
    plate2 = r4(-2.25, 2.25, 36.25, 40.75)
    q1 = r4(-3, 3, 43.25, 47.75)
    pad_stones = [r4(-8.25, -3.75, 50.25, 54.75), r4(-2.25, 2.25, 50.25, 54.75), r4(3.75, 8.25, 50.25, 54.75)]
    goal_deck = r4(-10, 10, 61, 77)
    L.slab(checker, 5.0, 3.0, tone="warm")
    L.slab(plate1, 5.0, 1.0, tone="warm")
    L.slab(plate2, 5.5, 1.0, tone="warm")
    L.slab(q1, 5.5, 1.0)
    for ps in pad_stones:
        L.slab(ps, 5.5, 1.0)
    L.jump("S10 long deck to checker deck (+1.0)", teal_e, checker, 4.0, 5.0)
    L.jump("S10 checker deck to plate 1", checker, plate1, 5.0, 5.0)
    L.jump("S10 plate 1 to plate 2 (+0.5)", plate1, plate2, 5.0, 5.5)
    L.jump("S10 plate 2 to stone", plate2, q1, 5.5, 5.5)
    L.jump("S10 stone to pad stone L", q1, pad_stones[0], 5.5, 5.5)
    L.jump("S10 stone to pad stone C", q1, pad_stones[1], 5.5, 5.5)
    L.jump("S10 stone to pad stone R", q1, pad_stones[2], 5.5, 5.5)
    # the goal deck: a tower, three pads throw the courier up onto it
    L.slab(goal_deck, 14.0, 1.0)
    L.fence(goal_deck, 14.0, skip=("e",))   # the finish deck keeps its railing (the one exception to 'no rails')
    for k, (ya, yb) in enumerate(((-14.0, -7.0), (-7.0, 0.0), (0.0, 6.5), (6.5, 13.0))):   # the tower: a stack of navy and grey crate tiers
        L.wall_box(goal_deck, ya, yb, **({"tone": "crate"} if k % 2 == 1 else {"tone": "navy"}))
    for k, ps in enumerate(pad_stones):
        c = rect_center(ps)
        L.pad(pad_id(), c[0], 5.5, c[1], leg4.pt((-6.0, 0.0, 6.0)[k], 63.0), 14.0, goal_deck, full=True)

    # ---- path (walkable on foot: stones, no ferry) -----------------------------------------------------------------
    def crossing_path(leg):
        P(leg, 0, 0, 0)
        for (u, f, w, d, top) in left2:
            P(leg, u, f, top)
        P(leg, -6, 39.5, 0)
        P(leg, -7.5, 42, 0)

    P(leg1, 0, 0, 0)
    P(leg1, 0, 10, 0)
    P(leg1, -8, 18, 0)
    for (u, f, w, d, top) in left:
        P(leg1, u, f, top)
    for f in (56, 62, 68, 74, 80):
        P(leg1, -7, f, 0)
    P(leg1, -8, 86.25, 0)
    P(leg1, -3, 93, 0)
    P(leg1, 1.5, 98, 0)
    P(leg1, 1.5, 103, 0)
    P(leg1, 1.5, 112, 0)
    P(leg1, 1.5, 118, 0)
    P(leg1, 1.5, 124, 0)
    P(leg1, 14, 128, 0)
    crossing_path(leg2)
    P(leg2, -4, 45, 0)
    P(leg2, 0, 47.5, 0)
    P(leg2, 1.5, 49, 0)
    P(leg2, 1.5, 53, 0)
    P(leg2, 1.5, 58, 0)
    P(leg2, 1.5, 63, 0)
    P(leg2, 1.5, 67, 0)
    P(leg2, 1.5, 71, 0)
    P(leg2, 1.5, 75, 0)
    P(leg2, 6.0, 79, 0)
    crossing_path(leg3)
    P(leg3, -7.5, 44.5, 0)   # straight out of the gate onto the platform before the belts
    P(leg3, -1, 44.75, 0)
    P(leg3, 0, 48.5, 0)
    for f in (50, 56, 62, 68):
        P(leg3, 0, f, 0)
    P(leg3, 0, 71, 0)
    P(leg3, 0, 76, 0)
    P(leg3, 0, 80, 0)
    P(leg3, 0, 84, 0)
    P(leg3, 0, 86.5, 0)
    for i, (u0, u1, d) in enumerate(rows):
        um = 0.0 if i == 0 else (max(u0, rows[i - 1][0]) + min(u1, rows[i - 1][1])) / 2
        P(leg3, um, 87.0 + 3.5 * i + 1.75, -0.5 + 0.5 * i)
    P(leg3, 0, 114, 3.0)
    P(leg3, 0, 119, 3.0)
    P(leg3, 0, 124, 3.0)
    P(leg3b, 0, -1.5, 3.0)
    for (u, f, w, d, top) in stones3:
        P(leg3b, u, f, top)
    P(leg3b, 0, 36.5, 3.0)
    P(leg3b, 2.0, 41.0, 2.0)
    P(leg3b, 2.0, 49.5, 2.0)
    P(leg3b, 2.0, 57.0, 2.0)
    P(leg3b, 0, 64.0, 3.0)
    for f in (70, 74.5):
        P(leg3b, 0, f, 4.0)
    P(leg3b, 5, 74.5, 4.0)
    P(leg3b, 9, 74.5, 4.0)
    for f in (4, 9, 14, 19, 24, 28):
        P(leg4, 0, f, 5.0)
    P(leg4, 0, 33.5, 5.0)
    P(leg4, 0, 38.5, 5.5)
    P(leg4, 0, 45.5, 5.5)
    P(leg4, 0, 52.5, 5.5)
    P(leg4, 0, 57.0, 10.0)
    P(leg4, 0, 63.0, 14.0)
    P(leg4, 0, 69.0, 14.0)

    gx4, gz4 = leg4.pt(0.0, 69.0)
    goal = {"p": [q(gx4), 16.0, q(gz4)], "s": [10.0, 4.0, 14.0], "yaw": 0.0}

    def cp(leg, f, y, size_u, size_f):
        x, z = leg.pt(0.0, f)
        s = [size_f, 6.0, size_u] if leg.fw[1] == 0 else [size_u, 6.0, size_f]
        return {"p": [q(x), y, q(z)], "s": [q(s[0]), 6.0, q(s[2])], "yaw": 0.0}

    cps = [
        {"p": [0.0, 3.0, leg1.pt(0, 95)[1]], "s": [2 * NECK, 6.0, 9.0], "yaw": 0.0},   # before the first gate wall
        cp(leg1, 122.0, 3.0, 2 * NECK, 6.0),    # court 1 after its second gate wall (the ring stands on the neck and the corner walk)
        cp(leg2, 45.5, 3.0, 17.0, 5.0),         # crossing 1: past the landing pillars' gates (the respawn ring stands on the apron, clear of the pillar gate wall)
        cp(leg2, 79.0, 3.0, 10.0, 12.0),        # court 2 after its second gate wall (the corner walk)
        cp(leg3, 44.75, 3.0, 17.0, 4.5),        # crossing 2: past the landing pillars' gates, before the belts
        cp(leg3, 78.25, 3.0, 24.0, 13.5),       # court 3
        cp(leg3, 119.25, 6.0, 6.5, 15.5),      # turn deck
        cp(leg3b, 72.75, 7.0, 8.0, 11.5),       # long deck
        cp(leg4, 15.5, 8.0, 8.0, 26.0),         # long checker deck
        cp(leg4, 45.5, 8.5, 8.0, 4.5),          # the stone after the plates
    ]
    slots = [
        {"id": "arch_start", "p": [0.0, 5.5, -6.5], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "arch_finish", "p": [q(gx4), 19.5, q(gz4)], "yaw": float(leg4.yaw), "size": [8.0, 1.5]},
        {"id": "floor_finish", "p": [q(gx4), 14.0, q(gz4)], "yaw": 0.0, "size": [5.0, 5.0]},
    ]
    data = {
        "format": "level-1",
        "number": NUMBER,
        "title": "FERRY CROSSING",
        "blurb": "Ride the ferry, pick the open gates, cross belts and spinner discs.",
        "rule": "CHOOSE THE OPEN GATES  ·  REACH THE END",
        "hint": "THE GATES OPEN AND SHUT: WAIT FOR AN OPEN ONE",
        "modes": ["show"],
        "pool": False,
        "show": "race",
        "world": "daylight",
        "camera": "stage",
        "cap": 300,
        "note": "Race course at 1 E = 2.0 m, time x1.44. The course is ~560 m long, so it turns three times (leg 1 along -Z, leg 2 along +X at z = -128, leg 3 along +Z at x = 99, leg 4 along -X at z = 85) to stay inside the +-150 m box. Gate walls are one navy wall with a frame and a chevron door per gate (tools/gate_piece.py: the door is a lift that slides up into its frame), the crates in court 3 slide.",
        "start": {"p": [0, 0, 0], "yaw": 0},
        "goal": goal,
        "path": resample(path),
        "void_y": laser_plane.void_y(L.blocks),
        "kill": [],
        "checkpoints": cps,
        "blocks": L.blocks,
        "hazards": L.hazards,
        "slots": slots,
    }
    item_boxes_gen.rows_for(NUMBER, data)
    return data, L, discs


def pad_report(L):
    """Every launch pad as the real courier flies it (jump_reach.pad_flight: stick held along the throw): throw speed, distance, apex, where it lands, the
    margin from that landing to the nearest edge of its target and the clearance over the target's near edge."""
    print(f"{'pad':7s} {'vx':>5s} {'vy':>5s} {'vz':>5s} {'dist':>6s} {'apex':>6s} {'land x':>7s} {'land z':>7s} {'margin':>6s} {'clr':>5s}  target rect")
    for p in L.pads:
        f = p["flight"]
        ok = f["margin"] >= MARGIN_MIN and (f["clearance"] is None or f["clearance"] >= 0.3) and f["speed"] <= MAX_PAD_SPEED + 0.01
        clr = "  -  " if f["clearance"] is None else f"{f['clearance']:5.2f}"
        print(f"{p['id']:7s} {p['v'][0]:5.1f} {p['v'][1]:5.1f} {p['v'][2]:5.1f} {f['dist']:6.2f} {f['apex']:6.2f} {f['land'][0]:7.2f} {f['land'][1]:7.2f} {f['margin']:6.2f} {clr}  {p['target']} {'ok' if ok else 'CHECK'}")


def bad_pads(L):
    return [p["id"] for p in L.pads if p["flight"]["margin"] < MARGIN_MIN or (p["flight"]["clearance"] is not None and p["flight"]["clearance"] < 0.3)
            or p["flight"]["speed"] > MAX_PAD_SPEED + 0.01]


def main(argv):
    data, L, discs = build()
    out = Path(__file__).resolve().parent.parent / "demo" / "levels" / "level_30.json"
    text = json.dumps(data, indent=1, ensure_ascii=False)
    out.write_text(text + "\n", encoding="utf-8")
    over = [j for j in L.jumps if j["gap"] > 0.8 * j["max_gap"] + 1e-9 or j["dh"] > 1.1]
    if "--emit-jumps" in argv:
        dest = Path(argv[argv.index("--emit-jumps") + 1])
        dest.write_text(json.dumps({"jumps": L.jumps, "movers": L.movers, "pads": L.pads}, indent=1) + "\n", encoding="utf-8")
    if "--report" in argv:
        print(f"{out}: {len(L.blocks)} blocks, {len(L.hazards)} hazards ({L.n_doors} cycling doors), {len(data['path'])} path points")
        length = sum(math.dist(a, b) for a, b in zip(data["path"], data["path"][1:]))
        print(f"path length {length:.1f} m (3D along the waypoints), at 5 m/s {length / 5.0:.0f} s")
        print(f"{'jump':44s} {'gap':>5s} {'dh':>5s} {'max':>5s} {'0.8max':>6s} {'margin':>6s}")
        for j in L.jumps:
            lim = 0.8 * j["max_gap"]
            print(f"{j['name']:44s} {j['gap']:5.2f} {j['dh']:5.2f} {j['max_gap']:5.2f} {lim:6.2f} {lim - j['gap']:6.2f}{'  OVER' if j['gap'] > lim + 1e-9 or j['dh'] > 1.1 else ''}")
        pad_report(L)
    weak = bad_pads(L)
    if weak:
        print("PADS OUT OF MARGIN:", ", ".join(weak), file=sys.stderr)
    if over:
        print("JUMPS OVER THE DESIGN RULE:", ", ".join(j["name"] for j in over), file=sys.stderr)
    if over or weak:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
