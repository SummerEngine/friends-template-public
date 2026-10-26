#!/usr/bin/env python3
"""Generates demo/levels/level_31.json (SPINNER GARDEN, round r31), standard library only, same output on every run.

  python3 tools/gen_level_31.py                          # writes demo/levels/level_31.json
  python3 tools/gen_level_31.py --report                 # also prints the gaps, the counts and the run-time estimate
  python3 tools/gen_level_31.py --emit-jumps out.json    # every required static -> static jump for tools/race_jump_probe.gd (the discs are checked by tools/disc_ride_check.gd)
  python3 tools/gen_level_31.py --emit-views out.json    # views for tools/race_view_frames.gd (and the plan renders)

The layout is the plan of a small spinner course: a wide start deck, a drop into a diamond of four turning discs, a hall with a
turning bar, a hex room with low bumps, a row of three small turning bars, two ramps topped by a turning bar each, a landing ring, a big turning disc 13 m past it (no jump or dash jump reaches it: the way over is the three small turning discs
a side) and a narrow walkway (2.25 m; the plan's ramp is 1.75) past a four-paddle wheel to the finish deck (12 x 12 m, railed like level 29's). One unit of the plan = 5.5 m (the plan's bar is 0.98 units = 5.4 m, the same size as the bars of level 30).
The course runs towards -Z; `u` is the distance from the start pad along it (z = -u), `x` is sideways (the runner's right is +X).
Rotating floors: `spin` hazards with `hit: false` and a cylinder part (a disc a courier rides: the mover under the feet carries it by its transform delta).
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jump_reach import max_gap  # noqa: E402
import laser_plane  # noqa: E402
import item_boxes_gen  # noqa: E402

NUMBER = 31
FLOOR = -4.0  # the disc floor (the plan's low level)
HALL = -2.0   # hall, hex room, tan floors and the disc field
RAMP_TOP = -0.5
BRIDGE_TOP = -1.75  # the walkway and the finish deck: 0.25 m over the disc field (a step the courier walks up), the wheel's lowest tip 0.75 m over it
# The disc field after the last ramp: the static landing ring (d 5, u 62.5) and the big turning disc (d 8.25) are further apart than any jump, dash jump included: the way over is the
# small discs (three a side). Longest gap a courier clears to a surface of the same height: a walking jump 4.28 m (tools/jump_reach.py max_gap, a hop of the chain stays under 3.4 m), a ground dash into a jump with an air dash on
# top 11.23 m (tools/exploit_check.py ledge_flights, one air dash per airtime, DASH_COOLDOWN 1.5 s), stretched by the audit's 5 % reach margin.
RING_U, RING_D = 62.5, 5.0
BIG_U, BIG_D = 82.25, 8.25
DASH_JUMP_GAP = 11.23 * 1.05
SMALL_D = 3.75
BUMP_D = 4.5            # the pointer bar of a turning floor at least this wide bounces whoever touches it (the four discs of the diamond and the big disc)
SMALL_DISCS = ((5.5, 67.0, 75), (9.0, 72.25, -75), (7.5, 78.0, 75))     # (x, u, rate): left x -= .. right x += .., the left turns the other way
TAIL = BIG_U - 70.25    # the thin ramp, the wheel and the finish are shifted this far along u with the big disc


def q(v):
    return round(v * 4.0) / 4.0


class Level:
    def __init__(self):
        self.blocks = []
        self.hazards = []
        self.jumps = []
        self.cps = []
        self.views = []

    def box(self, x, y, z, w, h, d, **kw):
        b = {"k": "box", "p": [q(x), q(y), q(z)], "s": [q(w), q(h), q(d)]}
        b.update(kw)
        self.blocks.append(b)

    def floor(self, u0, u1, half, top, x=0.0, thick=1.0, **kw):
        """A floor box over u0..u1 (towards -Z), centred on x, `half` m to each side, top face at `top`."""
        self.box(x, top - thick / 2, -(u0 + u1) / 2, 2 * half, thick, u1 - u0, **kw)

    def wedge(self, u0, u1, w, y0, y1, down=True):
        """A ramp over u0..u1 (towards -Z). down: the surface falls from y1 (at u0) to y0 (at u1); else it rises towards -Z (y0 at u0 to y1 at u1)."""
        lo, hi = min(y0, y1), max(y0, y1)
        r = [0, 0, 0] if down else [0, 180, 0]
        self.blocks.append({"k": "wedge", "p": [0.0, q((lo + hi) / 2), q(-(u0 + u1) / 2)], "s": [q(w), q(hi - lo), q(u1 - u0)], "r": r})

    def disc_floor(self, hid, x, u, d, top, rate, phase=0.0, pointer=True):
        """A rotating floor: a cylinder part on a `spin` that does not hit (couriers ride it), with a flat pointer bar on top so the turn can be seen. The pointer of a disc of BUMP_D m or
        more is a bumper (`bump`: it bounces the courier that touches it away, levels/level_world.gd bump_at); the small discs keep a plain bar (they are the way over, a bounce would
        throw a courier off a 3.75 m disc)."""
        parts = [{"k": "cyl", "p": [0.0, -0.5, 0.0], "d": q(d), "h": 1.0}]
        if pointer:
            bar = {"k": "box", "p": [q(d / 4), 0.0, 0.0], "s": [q(d / 2 - 0.25), 0.5, 0.5]}
            if d >= BUMP_D:
                bar["bump"] = True
            parts.append(bar)
        h = {"k": "spin", "id": hid, "p": [q(x), q(top), q(-u)], "axis": "y", "rate": rate, "hit": False, "parts": parts}
        if phase:
            h["phase"] = phase
        self.hazards.append(h)

    def bars(self, hid, x, y, u, length, thick, rate, phase=0.0, bars=1):
        """A bar through the hub turning in the XY plane (facing the runner): `bars` 1 = one straight bar (2 tips), 2 = a cross (4 blades). The level's turning bars stay single: tools/spinner_pass_check.gd finds
        every one of them impassable as a cross at 120..135 deg/s (a cross of wind_1, of the wall of three small bars or of either ramp bar: no steady or waiting walker gets through), single it passes."""
        parts = [{"k": "box", "p": [0.0, 0.0, 0.0], "s": [q(thick), q(length), q(thick)]}]
        if bars == 2:
            parts.append({"k": "box", "p": [0.0, 0.0, 0.0], "s": [q(length), q(thick), q(thick)]})
        h = {"k": "spin", "id": hid, "p": [q(x), q(y), q(-u)], "axis": "z", "rate": rate, "hit": True, "parts": parts}
        if phase:
            h["phase"] = phase
        self.hazards.append(h)

    def frame(self, u, hub_y, floor_y, half, hubs=(0.0,)):
        """The arch a hub hangs from: two posts and a rod at hub height 1.0 m behind the bar's plane (towards the start), an axle from the rod to each hub."""
        ub = u - 1.0
        bottom = floor_y - 1.0
        size = math.ceil((hub_y + 0.5 - bottom) * 2) / 2
        for sgn in (-1, 1):
            self.box(sgn * half, bottom + size / 2, -ub, 0.75, size, 0.75, tone="frame")
        self.box(0.0, hub_y, -ub, 2 * half + 0.75, 0.75, 0.75, tone="frame")
        for hx in hubs:
            self.box(hx, hub_y, -(u - 0.5), 0.5, 0.5, 0.75, tone="frame")

    def view(self, name, feet, dir_, back=6.0, up=3.0, ahead=5.0, clock=2.0):
        self.views.append({"name": name, "feet": [q(feet[0]), q(feet[1]), q(feet[2])], "dir": [dir_[0], dir_[1]], "clock": clock, "back": back, "up": up, "ahead": ahead})

    def pillar(self, x, u, w, top, bottom=-12.0):
        """A post from `top` down to `bottom` under a floor: the laser plane lies 0.75 m over its foot (tools/laser_plane.py)."""
        self.box(x, (top + bottom) / 2, -u, w, top - bottom, w)

    def fence(self, x0, x1, z0, z1, top, skip=()):
        """Thin 1 m rail boxes round a rectangle (hit false; style/finish_rails.gd draws them as the finish railings); skip: names among 'n', 's', 'e', 'w' (n = the -Z side, s = +Z, w = -X, e = +X)."""
        h = 1.0
        if "n" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z0 + 0.25, x1 - x0, h, 0.5)
        if "s" not in skip:
            self.box((x0 + x1) / 2, top + h / 2, z1 - 0.25, x1 - x0, h, 0.5)
        if "w" not in skip:
            self.box(x0 + 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0)
        if "e" not in skip:
            self.box(x1 - 0.25, top + h / 2, (z0 + z1) / 2, 0.5, h, z1 - z0 - 1.0)

    def jump(self, name, gap, dh):
        self.jumps.append({"name": name, "gap": gap, "dh": dh, "max_gap": max_gap(dh)})


def build():
    L = Level()

    # 1. start deck: 14 x 6 m (no rails: the way off is down), the start gate in front of the pad
    L.floor(-3.0, 3.0, 7.0, 0.0)
    L.hazards.append({"k": "blink", "id": "gate", "slot": "gate", "p": [0.0, 2.0, -2.5], "s": [14.5, 4.0, 0.5], "on": 4.0, "off": 600.0, "warn": 1.0, "hit": False})

    # 2. the drop: ramp 3 -> 7.25 (41 degrees), a funnel, the landing (checkpoint 1)
    L.wedge(3.0, 7.5, 14.0, FLOOR, 0.0, down=True)
    L.floor(7.5, 8.5, 7.0, FLOOR)
    L.floor(8.5, 9.5, 5.5, FLOOR)
    L.floor(9.5, 12.5, 3.5, FLOOR)

    # 3. diamond of four turning discs (d 5, centres on the plan's cluster: B, two sides, A)
    L.disc_floor("disc_b", 0.0, 15.25, 4.75, FLOOR, 65)
    L.disc_floor("disc_t", 3.0, 19.75, 4.75, FLOOR, -75)
    L.disc_floor("disc_m", -3.0, 19.75, 4.75, FLOOR, -60)
    L.disc_floor("disc_a", 0.0, 24.25, 4.75, FLOOR, 70)

    # 4. ramp up out of the diamond, the entry hall with the first bar (axis along the course); the floor under its sweep is as wide as the sweep, there are no walls
    L.wedge(27.0, 31.5, 4.5, FLOOR, HALL, down=False)
    L.floor(31.5, 33.0, 4.25, HALL)
    L.floor(33.0, 36.0, 2.75, HALL)  # narrow under the bar's sweep (no walls: whoever stands beside the sweep is hit or falls)
    L.frame(34.75, HALL + 3.0, HALL, 3.5)
    L.bars("wind_1", 0.0, HALL + 3.0, 34.75, 5.25, 0.75, 135)

    # 5. hex room: widest in the middle, seven low bumps
    L.floor(36.0, 38.0, 4.5, HALL)
    L.floor(38.0, 40.0, 5.0, HALL)
    L.floor(40.0, 43.0, 5.5, HALL)
    for u, xs in ((37.5, (-2.25, 2.25)), (40.0, (-3.5, 0.0, 3.5)), (42.5, (-2.25, 2.25))):
        for x in xs:
            L.box(x, HALL + 0.25, -u, 1.25, 0.5, 1.25, tone="warm")

    # 6. three small bars on a rod, parallel, a wall of paddles across the lane
    L.floor(43.0, 46.5, 2.75, HALL)
    L.frame(44.75, HALL + 3.0, HALL, 5.5, hubs=(-2.0, 0.0, 2.0))
    for i, x in enumerate((-2.0, 0.0, 2.0)):
        L.bars("wind_s%d" % (i + 1), x, HALL + 3.0, 44.75, 3.75, 0.5, 120)

    # 7. tan floor, ramp 1 with a bar at its top, a drop, tan floor (checkpoint 3), ramp 2 with a bar at its top
    L.floor(46.5, 47.5, 3.5, HALL, tone="warm")
    L.wedge(47.5, 52.0, 5.5, HALL, RAMP_TOP, down=False)
    L.frame(51.0, RAMP_TOP + 3.0, HALL, 3.5)
    L.bars("wind_3", 0.0, RAMP_TOP + 3.0, 51.0, 5.25, 0.75, -135)
    L.floor(52.0, 56.0, 3.5, HALL, tone="warm")
    L.wedge(56.0, 59.5, 5.5, HALL, RAMP_TOP, down=False)
    L.frame(59.0, RAMP_TOP + 3.0, HALL, 3.5)
    L.bars("wind_4", 0.0, RAMP_TOP + 3.0, 59.0, 5.25, 0.75, 135)

    # 8. the landing disc (a still ring) and the turning discs: a big one, six small ones around
    L.blocks.append({"k": "cyl", "p": [0.0, HALL - 0.5, q(-RING_U)], "d": RING_D, "h": 1.0, "tone": "court"})
    L.disc_floor("disc_big", 0.0, BIG_U, BIG_D, HALL, 60)
    for i, (x, u, rate) in enumerate(SMALL_DISCS):
        L.disc_floor("disc_l%d" % (i + 1), -x, u, SMALL_D, HALL, -rate)
        L.disc_floor("disc_r%d" % (i + 1), x, u, SMALL_D, HALL, rate)
    # no jump from the ring reaches the big disc, a dash jump neither; the small discs chain walkable hops (turning discs: a hop is the gap less a safety share)
    ring_to_big = BIG_U - RING_U - RING_D / 2 - BIG_D / 2
    assert ring_to_big > DASH_JUMP_GAP + 1.0, ring_to_big
    chain = [(0.0, RING_U, RING_D)] + [(x, u, SMALL_D) for x, u, _ in SMALL_DISCS] + [(0.0, BIG_U, BIG_D)]
    for (xa, ua, da), (xb, ub, db) in zip(chain, chain[1:]):
        hop = math.hypot(xb - xa, ub - ua) - da / 2 - db / 2
        assert 1.5 <= hop <= 3.4, (xa, ua, xb, ub, hop)

    # 9. the walkway past the four-paddle wheel (a kit platform 2.25 x 10.5 m: a row of inset tiles in a rim; the plan's ramp had no tiles) and the finish deck (12 x 12 m like level 29's, railed on three
    # sides, the way in open): the plan's wheel, a cross of two thin rods with a paddle at the end of each arm, turning at -120 deg/s, its lowest tip 0.75 m over the walkway
    L.floor(74.75 + TAIL, 85.25 + TAIL, 1.125, BRIDGE_TOP)
    parts = []
    for i in range(4):
        parts.append({"k": "box", "p": [0.0, 1.25, 0.0], "s": [0.75, 1.0, 0.5], "r": [0, 0, 90 * i]})
    parts.append({"k": "box", "p": [0.0, 0.0, 0.0], "s": [3.5, 0.25, 0.25]})
    parts.append({"k": "box", "p": [0.0, 0.0, 0.0], "s": [0.25, 3.5, 0.25], })
    L.hazards.append({"k": "spin", "id": "wheel", "p": [0.0, 0.75, q(-(76.25 + TAIL))], "axis": "z", "rate": -120, "hit": True, "parts": parts})
    L.floor(85.25 + TAIL, 97.25 + TAIL, 6.0, BRIDGE_TOP)
    L.fence(-6.0, 6.0, -(97.25 + TAIL), -(85.25 + TAIL), BRIDGE_TOP, skip=("s",))   # the finish deck keeps its railing; the way in (+Z side) is open, the hanging GOAL sign (show) comes over it

    # ---- posts under the floors (the laser plane lies at their feet), a post under the axis of every turning disc
    for x, u, top in ((-4.0, 0.0, -1.0), (4.0, 0.0, -1.0), (0.0, 11.0, FLOOR - 1.0), (0.0, 33.5, HALL - 1.0), (-3.5, 41.0, HALL - 1.0), (3.5, 41.0, HALL - 1.0), (0.0, 45.0, HALL - 1.0),
                      (0.0, 54.0, HALL - 1.0), (0.0, RING_U, HALL - 1.0), (0.0, 80.0 + TAIL, BRIDGE_TOP - 1.0), (-4.5, 88.5 + TAIL, BRIDGE_TOP - 1.0), (4.5, 88.5 + TAIL, BRIDGE_TOP - 1.0)):
        L.pillar(x, u, 2.0, top)
    for h in L.hazards:
        if h["k"] == "spin" and not h["hit"]:
            L.pillar(h["p"][0], -h["p"][2], 1.5, h["p"][1] - 1.0)

    # ---- checkpoints
    def cp(u0, u1, half, top, height=6.0):
        return {"p": [0.0, q(top + height / 2), q(-(u0 + u1) / 2)], "s": [q(2 * half), height, q(u1 - u0)], "yaw": 0.0}

    L.cps = [
        cp(8.5, 12.5, 3.5, FLOOR),
        cp(36.0, 43.0, 4.5, HALL),
        cp(52.0, 56.0, 3.5, HALL),
        cp(60.75, 64.25, 2.25, HALL),  # the donut, after the last ramp bar: a fall in the disc field or at the wheel returns here, never before an uncleared bar
    ]

    # ---- route (feet heights): over the discs the courier walks on them
    path = [
        (0, 0, 0), (3, 0, 0), (5.25, 0, -1.9), (8.5, 0, FLOOR), (12.0, 0, FLOOR), (15.25, 0, FLOOR), (18.5, 1.75, FLOOR), (21.5, 1.75, FLOOR), (24.25, 0, FLOOR),
        (27.5, 0, FLOOR + 0.1), (29.5, 0, -3.0), (32.5, 0, HALL), (36.0, 0, HALL), (40.0, 0, HALL), (43.5, 0, HALL), (46.5, 0, HALL), (49.5, 0, -1.2), (51.5, 0, RAMP_TOP),
        (54.0, 0, HALL), (57.0, 0, HALL + 0.4), (59.25, 0, RAMP_TOP), (62.25, 0, HALL), (64.5, -2.75, HALL), (67.0, -SMALL_DISCS[0][0], HALL), (72.25, -SMALL_DISCS[1][0], HALL), (78.0, -SMALL_DISCS[2][0], HALL),
        (80.0, -4.0, HALL), (BIG_U, 0, HALL),
        (74.0 + TAIL, 0, HALL), (76.0 + TAIL, 0, BRIDGE_TOP), (80.0 + TAIL, 0, BRIDGE_TOP), (85.25 + TAIL, 0, BRIDGE_TOP), (88.0 + TAIL, 0, BRIDGE_TOP), (91.25 + TAIL, 0, BRIDGE_TOP),
    ]
    path = [[q(x), q(y), q(-u)] for u, x, y in path]

    goal = {"p": [0.0, BRIDGE_TOP + 2.0, q(-(91.25 + TAIL))], "s": [8.0, 4.0, 8.0], "yaw": 0.0}   # 8 x 8 m inside the 12 x 12 m deck, its floor point is the deck's top
    slots = [
        {"id": "arch_start", "p": [0.0, 5.0, -1.0], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "arch_finish", "p": [0.0, BRIDGE_TOP + 5.5, -(91.25 + TAIL)], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "floor_finish", "p": [0.0, BRIDGE_TOP, -(91.25 + TAIL)], "yaw": 0.0, "size": [5.0, 5.0]},
    ]

    data = {
        "format": "level-1",
        "number": NUMBER,
        "title": "SPINNER GARDEN",
        "blurb": "Ride the turning discs, dodge the turning bars, cross the thin ramp.",
        "rule": "RIDE THE DISCS  ·  DODGE THE BARS",
        "hint": "THE DISCS CARRY YOU  ·  TIME THE BARS",
        "modes": ["show"],
        "pool": False,
        "show": "race",
        "world": "daylight",
        "camera": "stage",
        "note": "Layout of a small spinner course, 1 plan unit = 5.5 m, run towards -Z. The turning bars are faster than the hazard grid of earlier levels (up to 135 deg/s).",
        "start": {"p": [0, 0, 0], "yaw": 0},
        "goal": goal,
        "path": path,
        "void_y": laser_plane.void_y(L.blocks),
        "kill": [],
        "checkpoints": L.cps,
        "blocks": L.blocks,
        "hazards": L.hazards,
        "slots": slots,
    }
    item_boxes_gen.rows_for(NUMBER, data)
    return data, L


def views(L):
    """Camera views shared with the plan's renders (tools outside the repo map a view to the plan's own camera): feet level-local, dir [dx, dz], the camera `back` m behind and `up` m over the feet, looking `ahead` m."""
    N = (0, -1)
    d = (-0.7071, -0.7071)
    v = L.view
    v("v01_start_deck", (0, 0, 0.5), N, back=4.5, up=3.5, ahead=12.0)
    v("v02_discs", (0, FLOOR, -9.5), N, back=5.0, up=4.5, ahead=10.0)
    v("v03_hall_bar", (0, HALL, -31.75), N, back=5.0, up=3.5, ahead=6.0, clock=1.0)
    v("v04_hex_room", (0, HALL, -38.0), N, back=5.0, up=4.5, ahead=8.0, clock=1.0)
    v("v05_three_bars", (0, HALL, -41.5), N, back=4.5, up=3.5, ahead=6.0, clock=0.5)
    v("v06_ramps", (0, HALL, -47.5), N, back=5.0, up=4.5, ahead=9.0, clock=1.0)
    v("v07_disc_field", (0, HALL, -60.0), N, back=5.0, up=6.0, ahead=12.0, clock=1.5)
    v("v08_wheel_ramp", (0, HALL, -(72.5 + TAIL)), N, back=6.0, up=4.5, ahead=14.0, clock=1.0)
    v("v09_overview", (0, -1.0, -45.0), d, back=60.0, up=55.0, ahead=0.0, clock=1.0)
    v("v10_overview_end", (0, -1.0, -62.0), (0.7071, -0.7071), back=45.0, up=40.0, ahead=0.0, clock=1.0)


def main(argv):
    data, L = build()
    out = Path(__file__).resolve().parent.parent / "demo" / "levels" / "level_31.json"
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if "--emit-views" in argv:
        views(L)
        Path(argv[argv.index("--emit-views") + 1]).write_text(json.dumps({"level": NUMBER, "views": L.views}, indent=1) + "\n", encoding="utf-8")
    if "--report" in argv:
        plane = sum(math.hypot(a[0] - b[0], a[2] - b[2]) for a, b in zip(data["path"], data["path"][1:]))
        print(f"{out}: {len(L.blocks)} blocks, {len(L.hazards)} hazards, {len(data['checkpoints'])} checkpoints; path {plane:.1f} m planar; clean run at 5 m/s about {plane / 5 * 1.15:.0f} s")


if __name__ == "__main__":
    main(sys.argv[1:])
