#!/usr/bin/env python3
"""Item boxes of the race levels 29-32 (docs/level-format.md "Item boxes", docs/items.md): where the rows stand, and a helper to find and check spots.

  python3 tools/item_boxes_gen.py --check              # every row of ROWS through the lint's own geometry (floor, pedestal, cube, hazards, kill volumes) and the route rules
  python3 tools/item_boxes_gen.py --propose 29         # candidate spots along the level's route: flat static floor, clear of every hazard, not at a landing; ranges per 1 m
  python3 tools/item_boxes_gen.py --propose 29 --n 2 --from 60 --to 120 --step 1.8

The level generators (tools/gen_level_29.py .. 32) call `rows_for(NUMBER, data)`, so a regenerated level keeps its boxes. The rows are chosen by hand from --propose and a look at the
course (frames of a runner's view), on the rule of the design: two or three rows of two or three boxes spread along the route (about 25 %, 55 %, 80 % of it), the start area and the
last 15 m free, each row ACROSS the way (its axis perpendicular to the travel direction, centred on the route, 1.8 m between boxes), every box on plain static floor, nowhere that a
mover, a launch pad's landing or a drop throws the player, and where a runner has a moment to react (after a landing or a flat run)."""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import level_lint  # noqa: E402

LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"
START_FREE = 18.0     # m of the route from the start pad with no box (a level's own ROWS may be nearer the start when its start deck is short: see `start_free`)
GOAL_FREE = 15.0      # m before the goal with no box
LANDING_FREE = 4.0    # m after a jump's landing or a launch pad's landing with no box (the player has time to look)
TAKEOFF_FREE = 2.0    # m before a jump's take-off with no box (a runner is at speed, looking at the gap)
FLAT_RUN = 2  # m either side of a row, along the route, the floor is within 0.1 m of the row's (a runner meets the boxes on the level, not on a slope)
ROW_GAP = 7.0         # m of route between two rows (a level with little static floor has its rows near each other)
OFF_ROUTE = 3.0       # m a row's middle may be off the path (the path wobbles to the open door; the row is centred on the floor and the way)
ACROSS_TOL = 18.0     # degrees a row may be off the right angle to the way (the path's own wobble)
GAP_MIN = 2.0         # an unsupported stretch of the route at least this long is a jump

# the rows, per level number: p is the middle on the floor (level-local), n boxes, step 1.8, yaw the row's axis (degrees: 0 across a course that runs towards -Z).
# Chosen from --propose and the frames of tools/modes/items/boxes_scenario.gd; --check proves them.
ROWS = {
    # ROOFTOP RUN: the corridor between the two gate walls, the slab after the first launch platform, the plain deck before the tower-base discs
    29: [{"p": [0, 0, -80], "n": 3, "step": 1.8, "yaw": 0},
         {"p": [-45, 7, -133], "n": 3, "step": 1.8, "yaw": 90},
         {"p": [-106, 15, -89.5], "n": 3, "step": 1.8, "yaw": 0}],
    # FERRY CROSSING: the court between the two gate walls of leg 1, the run into the corner of the second court (leg 2), the checker deck at the start of leg 4
    30: [{"p": [0, 0, -110], "n": 3, "step": 1.8, "yaw": 0},
         {"p": [93.83, 0, -126.5], "n": 3, "step": 1.8, "yaw": -102.3},
         {"p": [99, 4, 80.2], "n": 3, "step": 1.8, "yaw": 0}],
    # SPINNER GARDEN: the landing between the two ramps, the still landing disc (the only static floors outside the start deck, the drop and the goal pad)
    31: [{"p": [0, -2, -54.75], "n": 3, "step": 1.8, "yaw": 0},
         {"p": [0, -2, -63.0], "n": 2, "step": 1.8, "yaw": 25}],
    # GATE HALL: three of the courts between the gate rows
    32: [{"p": [0, 0, -35.5], "n": 3, "step": 1.8, "yaw": 0},
         {"p": [0, 0, -63], "n": 3, "step": 1.8, "yaw": 0},
         {"p": [0, 0, -85], "n": 3, "step": 1.8, "yaw": 0}],
}


def rows_for(number, data):
    """Puts the level's rows into its data (a generator calls this just before it writes the file)."""
    rows = ROWS.get(number, [])
    if rows:
        data["item_boxes"] = [dict(row) for row in rows]
    return data


# ---- the route ----
def route_of(data):
    """[(u, [x, y, z])]: the level's path points with the distance walked (planar) from the first."""
    path = data["path"]
    out, run = [], 0.0
    for i, p in enumerate(path):
        if i:
            run += math.hypot(p[0] - path[i - 1][0], p[2] - path[i - 1][2])
        out.append((run, p))
    return out


def route_at(route, u):
    """The point of the route `u` m along it: [x, y, z]."""
    if u <= route[0][0]:
        return list(route[0][1])
    for (u0, a), (u1, b) in zip(route, route[1:]):
        if u0 <= u <= u1 and u1 > u0:
            t = (u - u0) / (u1 - u0)
            return [a[i] + (b[i] - a[i]) * t for i in range(3)]
    return list(route[-1][1])


def heading(route, u, reach=2.5):
    """The planar travel direction (unit [dx, dz]) of the route around `u`."""
    a, b = route_at(route, u - reach), route_at(route, u + reach)
    d = math.hypot(b[0] - a[0], b[2] - a[2]) or 1.0
    return [(b[0] - a[0]) / d, (b[2] - a[2]) / d]


def row_yaw(direction):
    """Degrees of a row that lies across `direction` ([dx, dz]): 0 for a course towards -Z (the row runs along +X)."""
    return round(math.degrees(math.atan2(-direction[0], -direction[1])), 1)


def static_blocks(data):
    return [b for b in data["blocks"] if b.get("k", "box") in ("box", "cyl", "wedge")]


def landings(data, route):
    """Route distances where a player lands after a jump or a launch: the end of every unsupported stretch (no static floor within 1.5 m under the route) and the landing of every launch pad
    (the ballistic arc of its velocity, 17 m/s^2, until it is back under the pad's own height)."""
    blocks = static_blocks(data)
    total = route[-1][0]
    spans, start, u = [], None, 0.0
    while u <= total:
        p = route_at(route, u)
        supported = level_lint.floor_below(blocks, p, reach=1.5) is not None
        if not supported and start is None:
            start = u
        if supported and start is not None:
            if u - start >= GAP_MIN:
                spans.append((start, u))
            start = None
        u += 0.5
    ends = [(a, b) for a, b in spans]
    for h in data["hazards"]:
        if h.get("k") != "push" or not level_lint.vec(h.get("v")):
            continue
        vx, vy, vz = h["v"]
        t_flight = (vy + math.sqrt(vy * vy + 2 * 17.0 * 2.0)) / 17.0   # back down to 2 m under the pad's height at the latest
        land = [h["p"][0] + vx * t_flight, h["p"][1], h["p"][2] + vz * t_flight]
        near = min(route, key=lambda r: math.hypot(r[1][0] - land[0], r[1][2] - land[2]))
        pad = min(route, key=lambda r: math.hypot(r[1][0] - h["p"][0], r[1][2] - h["p"][2]))
        ends.append((pad[0], near[0]))
    return ends


def propose(data, n=3, step=1.8, start=None, stop=None, every=1.0, yaw=None):
    """[(u, row, problems)] for rows centred on the route every `every` m: the row's own problems (the lint's geometry), plus route rules in `problems` text."""
    route = route_of(data)
    total = route[-1][0]
    blocks = static_blocks(data)
    jumps = landings(data, route)
    shapes = level_lint.hazard_shape_list(data["hazards"])
    out = []
    u = max(start if start is not None else START_FREE, 0.0)
    stop = min(stop if stop is not None else total - GOAL_FREE, total - GOAL_FREE)
    while u <= stop:
        p = route_at(route, u)
        floor_y = level_lint.floor_below(blocks, p, reach=1.5)
        problems = []
        if floor_y is None:
            out.append((u, None, ["no floor"]))
            u += every
            continue
        d = heading(route, u)
        row = {"p": [round(p[0], 2), round(floor_y, 2), round(p[2], 2)], "n": n, "step": step, "yaw": row_yaw(d) if yaw is None else yaw}
        for index, spot in enumerate(level_lint.item_box_spots(row)):
            problems += [f"box {index}: {text}" for text in level_lint.box_spot_problems(spot, blocks, data["hazards"], data.get("kill", []), middle=False, shapes=shapes)]
        for a, b in jumps:
            if b - 0.5 <= u <= b + LANDING_FREE:
                problems.append(f"{u - b:.1f} m after a landing (jump {a:.0f}-{b:.0f})")
            if a - TAKEOFF_FREE <= u < a + 0.5:
                problems.append(f"{a - u:.1f} m before a take-off (jump {a:.0f}-{b:.0f})")
        for k in range(-FLAT_RUN, FLAT_RUN + 1):
            q = route_at(route, u + k)
            y = level_lint.floor_below(blocks, q, reach=1.5)
            if y is None or abs(y - floor_y) > 0.1:
                problems.append(f"not flat along the route at {k:+d} m")
                break
        out.append((u, row, problems))
        u += every
    return out


def ranges(found):
    """Contiguous runs of problem-free candidates: [(u0, u1)]."""
    runs, current = [], None
    for u, row, problems in found:
        if row is not None and not problems:
            current = (current[0], u) if current else (u, u)
        elif current:
            runs.append(current)
            current = None
    if current:
        runs.append(current)
    return runs


def load(number):
    return json.loads((LEVELS / f"level_{number:02d}.json").read_text(encoding="utf-8"))


def check_rows(number):
    """The problems of this level's ROWS (the lint's own geometry, and the route rules the lint cannot know): [] when they are all fine."""
    data = load(number)
    data["item_boxes"] = [dict(row) for row in ROWS.get(number, [])]
    problems = []
    route = route_of(data)
    total = route[-1][0]
    blocks = static_blocks(data)
    jumps = landings(data, route)
    rows = data["item_boxes"]
    if not 2 <= len(rows) <= 3:
        problems.append(f"level {number}: {len(rows)} rows (the design: 2 or 3)")
    last_u = -1e9
    for index, row in enumerate(rows):
        where = f"level {number} row {index} {row['p']}"
        nearest = min(route_samples(route), key=lambda r: math.hypot(r[1][0] - row["p"][0], r[1][2] - row["p"][2]))
        u, there = nearest
        share = u / total
        if not 2 <= row["n"] <= 3:
            problems.append(f"{where}: {row['n']} boxes (2 or 3 per row)")
        if u < START_FREE or u > total - GOAL_FREE:
            problems.append(f"{where}: {u:.0f} m along a route of {total:.0f} m (the first {START_FREE:.0f} m and the last {GOAL_FREE:.0f} m stay free)")
        if u - last_u < ROW_GAP:
            problems.append(f"{where}: only {u - last_u:.0f} m after the row before")
        last_u = u
        off = math.hypot(there[0] - row["p"][0], there[2] - row["p"][2])
        if off > OFF_ROUTE:
            problems.append(f"{where}: {off:.1f} m off the route (rows are centred on the way, within {OFF_ROUTE} m of the path)")
        d = heading(route, u, reach=8.0)
        along = [math.cos(math.radians(row.get("yaw", 0.0))), -math.sin(math.radians(row.get("yaw", 0.0)))]
        slant = math.degrees(math.asin(min(1.0, abs(along[0] * d[0] + along[1] * d[1]))))
        if slant > ACROSS_TOL:
            problems.append(f"{where}: the row is {slant:.0f} degrees off the right angle to the way (the way: {d})")
        if abs(row.get("step", 1.8) - 1.8) > 1e-6:
            problems.append(f"{where}: step {row.get('step')} (1.8)")
        for a, b in jumps:
            if b - 0.5 <= u <= b + LANDING_FREE:
                problems.append(f"{where}: {u - b:.1f} m after a landing")
            if a - TAKEOFF_FREE <= u < a + 0.5:
                problems.append(f"{where}: {a - u:.1f} m before a take-off")
        print(f"  level {number} row {index}: {row['n']} boxes at {u:.0f} m of {total:.0f} ({share * 100:.0f} %), yaw {row.get('yaw', 0)}")
    import tempfile
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / f"level_{number:02d}.json"
        path.write_text(json.dumps(data))
        report = level_lint.lint_level(path, number)
    problems += [f"level {number}: lint: {text}" for text in report.errors if "item_boxes" in text]
    return problems


def route_samples(route, every=0.5):
    out, u = [], 0.0
    while u <= route[-1][0]:
        out.append((u, route_at(route, u)))
        u += every
    return out


def main(argv):
    if "--check" in argv:
        failed = 0
        for number in (29, 30, 31, 32):
            problems = check_rows(number)
            for text in problems:
                print("  ERROR", text)
            failed += len(problems)
        print(f"item_boxes_gen: {'ok' if not failed else str(failed) + ' problems'}")
        return 1 if failed else 0
    if "--propose" in argv:
        number = int(argv[argv.index("--propose") + 1])
        n = int(argv[argv.index("--n") + 1]) if "--n" in argv else 3
        step = float(argv[argv.index("--step") + 1]) if "--step" in argv else 1.8
        yaw = float(argv[argv.index("--yaw") + 1]) if "--yaw" in argv else None
        lo = float(argv[argv.index("--from") + 1]) if "--from" in argv else None
        hi = float(argv[argv.index("--to") + 1]) if "--to" in argv else None
        data = load(number)
        found = propose(data, n, step, lo, hi, yaw=yaw)
        total = route_of(data)[-1][0]
        print(f"level {number}: route {total:.1f} m; free runs (u from-to, share):")
        if "--list" in argv:
            for u, row, problems in found:
                print(f"  u {u:6.1f} {'ok ' if row and not problems else 'no '} {row['p'] if row else None} {'; '.join(t[:50] for t in problems[:2])}")
        for a, b in ranges(found):
            mid = (a + b) / 2
            row = next(r for u, r, p in found if u == a)
            print(f"  {a:6.1f} - {b:6.1f} m ({a / total * 100:3.0f} - {b / total * 100:3.0f} %)  first row {row['p']} yaw {row['yaw']}")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
