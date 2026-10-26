#!/usr/bin/env python3
"""Generates demo/levels/level_32.json (GATE RUSH, round r32), standard library only, same output on every run.

  python3 tools/gen_level_32.py            # writes demo/levels/level_32.json
  python3 tools/gen_level_32.py --report   # also prints the rows, the door schedule and the length

A straight hall (one leg along -Z, 30 m wide) with six gate rows and a slime slope, laid out for our courier (a run of about 5 m/s, the level clock in
seconds). Sections in order: the start pen and
deck, row 1 (3 doors, one opens at a time: 1, 3, 2), row 2 (4 doors, 1+4 then 2+3), row 3 (4 doors, a wave 1 2 3 4), row 4 (8 doors: the left four open
1 2 3 4 one at a time, the right four 8 7 6 5), row 5 (5 doors, a wave from the middle: 3, 2+4, 1+5), the slime slope (a wedge: low friction, a push downhill,
jumps add speed), row 6 (3 doors, 1 2 3, faster) at its foot and the finish deck.

A row is a frame of masonry pillars (1.5 m deep) between the doors, a lintel over every opening (3.5 m high) and a blue chevron door per opening: a `lift`
hazard (`hit: true`, a part of tone "door") that hangs in front of the frame, shut = its foot on the floor, open = lifted 3.5 m up beside the lintel, where it stays in
view. Every schedule is a pure function of the level clock (`period`; `pause` = dwell shut, `hold` = dwell open, the rest is the move up and down, `phase` = offset);
a door that comes down on a courier only nudges it out of the way (LevelWorld.door_nudge), it never throws or traps. Under every floor stand posts down to the laser plane (tools/laser_plane.py), no kill
volume. Coordinates: x across (the hall is -15..15), f = metres forward from the start (z = -f), y up.
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import laser_plane  # noqa: E402
import item_boxes_gen  # noqa: E402
import gate_piece  # noqa: E402

NUMBER = 32
W = 30.0              # the hall's width
HALF = W / 2
PILLAR_W = 1.5        # the wall between two openings (the piece's frames stand 0.5 m wide piers inside it)
WALL_H = 3.5          # the quilted wall between the frames (tools/gate_piece.py wall_h)
OPEN_H = 3.5          # an opening's height: a jump (apex 1.44 m, 3.24 m with the head) clears the lifted door
GROOVE = 3.5          # the strip a row stands on (depth, along the course)
FLOOR_T = 2.0         # thickness of every floor box
DROP = 5.0            # the slope's fall
SLOPE_F0, SLOPE_F1 = 98.0, 128.0
FINISH_F = 140.0
END_F = 148.0

# one entry per row: f (distance of the frame's middle), n doors of width d, `outer` the width of the two pillars at the walls, the schedule (s): `period`, `hold` (dwell open),
# `move` (up or down), and `offsets`: the time in s at which each door starts to open.
ROWS = [
    {"name": "g1", "f": 26.25, "n": 3, "d": 8.0, "outer": 1.5, "period": 3.75, "hold": 0.75, "move": 0.5, "offsets": [0.0, 2.5, 1.25]},                    # 1, 3, 2
    {"name": "g2", "f": 41.25, "n": 4, "d": 5.5, "outer": 1.75, "period": 3.5, "hold": 0.75, "move": 0.5, "offsets": [0.0, 1.75, 1.75, 0.0]},             # 1+4, then 2+3
    {"name": "g3", "f": 56.25, "n": 4, "d": 5.5, "outer": 1.75, "period": 3.5, "hold": 0.5, "move": 0.5, "offsets": [0.0, 0.75, 1.5, 2.25]},              # the wave 1 2 3 4
    {"name": "g4", "f": 72.25, "n": 8, "d": 2.0, "outer": 1.75, "period": 3.5, "hold": 0.5, "move": 0.25, "offsets": [0.0, 0.75, 1.5, 2.25, 2.25, 1.5, 0.75, 0.0]},  # left 1 2 3 4, right 8 7 6 5
    {"name": "g5", "f": 90.25, "n": 5, "d": 4.0, "outer": 2.0, "period": 3.75, "hold": 0.75, "move": 0.5, "offsets": [2.5, 1.25, 0.0, 1.25, 2.5]},       # 3, then 2+4, then 1+5
    {"name": "g6", "f": 130.25, "n": 3, "d": 8.0, "outer": 1.5, "period": 3.0, "hold": 0.5, "move": 0.25, "offsets": [0.0, 1.0, 2.0], "y": -DROP},       # 1 2 3, faster, at the foot of the slope
]


def q(v):
    return round(v * 4.0) / 4.0


def qs(v):
    return round(v * 2.0) / 2.0


class Level:
    def __init__(self):
        self.blocks = []
        self.hazards = []
        self.rows = []

    def box(self, x, y, f, w, h, d, **kw):
        b = {"k": "box", "p": [q(x), q(y), q(-f)], "s": [q(w), q(h), q(d)]}
        b.update(kw)
        self.blocks.append(b)

    def slab(self, x0, x1, f0, f1, top, thick=FLOOR_T, **kw):
        self.box((x0 + x1) / 2, top - thick / 2, (f0 + f1) / 2, x1 - x0, thick, f1 - f0, **kw)

    def wall(self, x0, x1, f0, f1, y0, y1, **kw):
        self.box((x0 + x1) / 2, (y0 + y1) / 2, (f0 + f1) / 2, x1 - x0, y1 - y0, f1 - f0, **kw)

    def row(self, spec):
        """A gate row: a warm-tone floor strip and the shared gate wall (tools/gate_piece.py: quilted wall, an arch frame per opening, two eyes, a lift door per opening that slides up into the frame).
        The piece's doors rest open with a symmetric pause; this row's doors dwell open `hold` and shut for the rest, each starting to open at its own offset (solid, never a bonk: `hit` false)."""
        f0, n, d, outer = spec["f"], spec["n"], spec["d"], spec["outer"]
        top = spec.get("y", 0.0)
        centres = []
        cursor = -HALF + outer
        for i in range(n):
            centres.append(cursor + d / 2)
            cursor += d + PILLAR_W
        assert abs(cursor - PILLAR_W + outer - HALF) < 1e-9, (spec["name"], cursor)
        self.slab(-HALF, HALF, f0 - GROOVE / 2, f0 + GROOVE / 2, top, tone="warm")
        period, hold, move = spec["period"], spec["hold"], spec["move"]
        pause = period - hold - 2 * move                      # dwell shut
        assert pause >= 0.5, spec["name"]
        piece = gate_piece.gate_wall(lambda ua, ub, fa, fb: (ua, ub, -fb, -fa), f0 - 0.5, top, -HALF, HALF, [(q(c), d, 0.0) for c in centres], spec["name"],
                                     wall_h=WALL_H, h=OPEN_H, period=period, pause=hold)
        self.blocks.extend(piece["blocks"])
        doors = [h for h in piece["hazards"] if h["k"] == "lift"]
        assert len(doors) == n, (spec["name"], len(doors))
        names = []
        for i, h in enumerate(doors):
            offset = spec["offsets"][i]
            h.update({"id": f"{spec['name']}_{i + 1}", "period": period, "pause": q(hold), "hold": q(pause), "phase": q((period - move - offset) % period), "hit": False})
            self.hazards.append(h)
            names.append((h["id"], centres[i], offset))
        self.rows.append({"name": spec["name"], "f": f0, "doors": names, "door_w": d, "spec": spec})
        return centres


def build():
    L = Level()
    # ---- start pen and deck (the pen of every show race: rails, the gate, the banner posts) --------------------------
    L.slab(-9, 9, -8.5, 11, 0.0, 2.0)
    L.wall(-9.0, -8.5, -8.5, 11.0, -1.0, 1.0)
    L.wall(8.5, 9.0, -8.5, 11.0, -1.0, 1.0)
    L.wall(-9.0, 9.0, -9.0, -8.5, -1.0, 1.0)
    L.hazards.append({"k": "blink", "id": "gate", "slot": "gate", "p": [0.0, 2.0, -4.75], "s": [17.0, 4.0, 0.5], "on": 4.0, "off": 600.0, "warn": 1.0, "hit": False})
    for ux in (-8.75, 8.75):
        L.wall(ux - 0.25, ux + 0.25, 9.75, 10.25, -1.0, 7.0)
    L.box(0.0, 8.25, 10.0, 16.5, 2.5, 0.5)

    # ---- the hall: the course floor (default tone) between the rows, warm-tone floors where a row stands ------------------------------------------------------
    stops = [11.0]
    for spec in ROWS:
        if spec["f"] < SLOPE_F0:
            stops += [spec["f"] - GROOVE / 2, spec["f"] + GROOVE / 2]
    stops.append(SLOPE_F0)
    for i in range(0, len(stops), 2):
        L.slab(-HALF, HALF, stops[i], stops[i + 1], 0.0)
    centres = {}
    for spec in ROWS:
        centres[spec["name"]] = L.row(spec)

    # ---- the slime slope: a wedge from the top edge (f SLOPE_F0, y 0) down to the foot (f SLOPE_F1, y -DROP) -------------------------------------------------
    length = SLOPE_F1 - SLOPE_F0
    POST_FOOT = -12.5
    L.box(0.0, -DROP / 2, (SLOPE_F0 + SLOPE_F1) / 2, W, DROP, length, k="wedge", m="slime", tone="slime")
    L.slab(-HALF, HALF, SLOPE_F0, SLOPE_F1, -DROP, 2.0)     # under the wedge (closes its underside)
    # ---- the foot: the row 6 floor is on the lower floor; the finish deck behind it ------------------------------------------------------
    g6 = ROWS[-1]["f"]
    L.slab(-HALF, HALF, SLOPE_F1, g6 - GROOVE / 2, -DROP)
    L.slab(-HALF, HALF, g6 + GROOVE / 2, FINISH_F - 1.0, -DROP)
    L.slab(-HALF, HALF, FINISH_F - 1.0, FINISH_F + 1.0, -DROP, tone="finish")
    L.slab(-HALF, HALF, FINISH_F + 1.0, END_F, -DROP)

    # ---- the end wall only: no rails along the hall, a courier who steps off falls into the lasers -------------------------------------------------
    L.wall(-HALF - 0.5, HALF + 0.5, END_F, END_F + 0.5, -DROP, 3.0 - DROP)

    # ---- posts under the floors down to the laser plane (tools/laser_plane.py): the floors' undersides are at -2 (the course) and -7 (the lower deck) --------
    for ff in (16.0, 34.0, 49.0, 64.0, 81.0, 95.0):
        for px in (-10.0, 10.0):
            L.box(px, (-2.0 + POST_FOOT) / 2, ff, 1.5, -2.0 - POST_FOOT, 1.5, tone="stone_plain")
    for ff in (106.0, 120.0, 135.0, 144.0):
        for px in (-10.0, 10.0):
            L.box(px, (-DROP - 2.0 + POST_FOOT) / 2, ff, 1.5, -DROP - 2.0 - POST_FOOT, 1.5, tone="stone_plain")

    # ---- path: through the middle door of every row (the walking surface), a waypoint every 5 m ----------------------------------------------
    def surface(ff):
        if ff <= SLOPE_F0:
            return 0.0
        if ff >= SLOPE_F1:
            return -DROP
        return -DROP * (ff - SLOPE_F0) / length

    door_x = {}
    for spec in ROWS:
        row_c = centres[spec["name"]]
        door_x[spec["f"]] = row_c[len(row_c) // 2]

    def x_at(ff):
        best = 0.0
        for rf, dx in door_x.items():
            if abs(ff - rf) <= 6.0:
                best = dx * (1.0 - (abs(ff - rf) - 3.0) / 3.0) if abs(ff - rf) > 3.0 else dx
        return best

    path = [[0.0, 0.0, 0.0]]
    ff = 5.0
    while ff < FINISH_F:
        path.append([q(x_at(ff)), q(surface(ff)), q(-ff)])
        ff += 5.0
    path.append([0.0, -DROP, q(-FINISH_F)])

    goal = {"p": [0.0, -DROP + 2.0, q(-FINISH_F)], "s": [W, 4.0, 2.0], "yaw": 0.0}
    cps = []     # a checkpoint stands on the landing after a row (3 m behind its frame), so it triggers only once the row is passed: a failed row respawns before it
    for spec in ROWS:
        top = spec.get("y", 0.0)
        cps.append({"p": [0.0, top + 3.0, q(-(spec["f"] + 4.5))], "s": [W, 6.0, 3.0], "yaw": 0.0})

    slots = [
        {"id": "arch_start", "p": [0.0, 5.5, -6.5], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "arch_finish", "p": [0.0, -DROP + 5.5, q(-FINISH_F - 4.0)], "yaw": 0.0, "size": [8.0, 1.5]},
        {"id": "floor_finish", "p": [0.0, -DROP, q(-FINISH_F)], "yaw": 0.0, "size": [5.0, 5.0]},
    ]
    data = {
        "format": "level-1",
        "number": NUMBER,
        "title": "GATE RUSH",
        "blurb": "Run the gate rows: jump through the doors that sink, then slide down the slime.",
        "rule": "DODGE THE DOORS  ·  SLIDE TO THE FINISH",
        "hint": "JUMP THROUGH THE GAPS AS THE DOORS SINK",
        "modes": ["show"],
        "pool": False,
        "show": "race",
        "world": "daylight",
        "camera": "stage",
        "note": "Race course for our courier and clock: a 30 m hall 148 m long, six gate rows (3, 4, 4, 8, 5, 3 doors), a slime slope and the finish. A door is a lift that hangs in front of a lintel and slides up.",
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


def main(argv):
    data, L = build()
    out = Path(__file__).resolve().parent.parent / "demo" / "levels" / "level_32.json"
    out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    if "--report" in argv:
        print(f"{out}: {len(L.blocks)} blocks, {len(L.hazards)} hazards, {len(data['path'])} path points")
        length = sum(math.dist(a, b) for a, b in zip(data["path"], data["path"][1:]))
        print(f"path length {length:.1f} m, at 5 m/s {length / 5.0:.0f} s")
        for r in L.rows:
            s = r["spec"]
            print(f"{r['name']} f={r['f']:.2f} doors={s['n']} door_w={s['d']} period={s['period']} open dwell={s['hold']} move={s['move']} shut dwell={s['period'] - s['hold'] - 2 * s['move']:.2f} offsets={s['offsets']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
