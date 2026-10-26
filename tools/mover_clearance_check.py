#!/usr/bin/env python3
"""Moving platforms never overlap anything: `tools/mover_clearance_check.py [level.json ... | --levels 29,30] [--min-gap 0.3] [--step 0.05] [--poses]`.

Sweeps every `slide` / `lift` mover of a level over a full period (0.05 s steps, finer where it gets close) and measures the gap between the mover's
collision shapes (boxes and cylinders as boxes, turned as the level turns them) and
  * every other `slide` / `lift` mover (swept together over the common period of the two),
  * every static block of the level (floors, walls, pillars, rails, gate frames, belts, eyes),
  * every `spin` / `swing` part (hubs, masts, bars at every pose) and a `blink` block at its solid place.
The gap is the Euclidean distance between the two boxes (negative: how deep they interpenetrate). Any gap under MIN_GAP (0.3 m) fails, printed as
level, both names, level clock and gap. Two exemptions, both by construction and nothing else:
  * a wall that stands on a floor (a mover with `hit`: a crate sliding along the court; a gate door, which no longer has `hit`, shutting onto its sill) is in contact with the top it
    stands on: a floor whose top the wall's bottom reaches (within 1 mm) at some pose is not counted for the poses where the wall is over it in plan
    and not below its top (the wall comes down onto it, slides on it); every other side of the floor counts;
  * a gate door (every part `tone door`, `tools/gate_piece.py`) shuts a doorway of its frame, so the frame's piers and core (`tone arch`) and the wall
    around it (`tone navy`) are not counted for it; it is checked against every other block, mover and spinner.
Pure data: same motion formulas as levels/hazards.gd `cycle` / `pose` (the real clock is cross-checked by `tools/mover_pose_check.gd`, which calls
`--poses`). Exit status 1 when any gap is under the limit. Standard library only."""
import json
import math
import sys
from itertools import combinations
from pathlib import Path

MIN_GAP = 0.3
STEP = 0.05
FINE = 0.01          # a pair closer than CLOSE_BAND at a sample is re-sampled at this step through the whole sample step
CLOSE_BAND = 1.0
ROOT = Path(__file__).resolve().parent.parent
MOVERS = ("slide", "lift")
SOLID_HAZARDS = ("spin", "swing", "blink")
EPS = 1e-9


# --- motion: the same as levels/hazards.gd -------------------------------------------------------------------------------------------------------------------

def cycle(tau, period, pause, ease, hold=-1.0):
    top = pause if hold < 0.0 else hold
    moving = max((period - pause - top) * 0.5, 0.001)
    m = tau % period
    if m < pause:
        f = 0.0
    elif m < pause + moving:
        f = (m - pause) / moving
    elif m < pause + moving + top:
        f = 1.0
    else:
        f = 1.0 - (m - pause - moving - top) / moving
    f = min(max(f, 0.0), 1.0)
    if ease == "sine":
        f = 0.5 - 0.5 * math.cos(f * math.pi)
    return f


def vec(v, fallback=(0.0, 0.0, 0.0)):
    if isinstance(v, (list, tuple)) and len(v) >= 3:
        return (float(v[0]), float(v[1]), float(v[2]))
    return fallback


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def euler(v):
    """Godot's Basis.from_euler(..., EULER_ORDER_YXZ) of degrees: Y * X * Z."""
    x, y, z = (math.radians(a) for a in vec(v))
    return mat_mul(mat_mul(rot_y(y), rot_x(x)), rot_z(z))


def axis_basis(axis, degrees):
    a = math.radians(degrees)
    return rot_x(a) if axis == "x" else rot_z(a) if axis == "z" else rot_y(a)


def apply(m, v):
    return tuple(sum(m[i][j] * v[j] for j in range(3)) for i in range(3))


def hazard_pose(h, t):
    """(position, basis) of a mover at level clock t."""
    tau = t + float(h.get("phase", 0.0))
    pivot = vec(h.get("p"))
    base = euler(h.get("r"))
    k = h["k"]
    if k == "slide":
        to = vec(h.get("to"))
        f = cycle(tau, max(float(h.get("period", 4.0)), 0.25), float(h.get("pause", 0.0)), h.get("ease", "sine"))
        return tuple(pivot[i] + to[i] * f for i in range(3)), base
    if k == "lift":
        pause = float(h.get("pause", 1.0))
        f = cycle(tau, max(float(h.get("period", 8.0)), 0.25), pause, h.get("ease", "sine"), float(h.get("hold", pause)))
        return (pivot[0], pivot[1] + float(h.get("rise", 4.0)) * f, pivot[2]), base
    if k == "spin":
        return pivot, mat_mul(base, axis_basis(h.get("axis", "y"), (float(h.get("rate", 30.0)) * tau) % 360.0))
    if k == "swing":
        a0, a1 = float(h.get("a0", -60.0)), float(h.get("a1", 60.0))
        f = cycle(tau, max(float(h.get("period", 4.0)), 0.25), float(h.get("pause", 0.0)), h.get("ease", "sine"))
        return pivot, mat_mul(base, axis_basis(h.get("axis", "x"), a0 + (a1 - a0) * f))
    return pivot, base  # blink: its solid place (it only ever falls away from it)


def period_of(h):
    if h["k"] in MOVERS:
        return max(float(h.get("period", 4.0 if h["k"] == "slide" else 8.0)), 0.25)
    if h["k"] == "swing":
        return max(float(h.get("period", 4.0)), 0.25)
    if h["k"] == "spin":
        rate = abs(float(h.get("rate", 30.0)))
        return 360.0 / rate if rate > 0 else 1.0
    return 1.0


# --- shapes --------------------------------------------------------------------------------------------------------------------------------------------------

def shape_size(part):
    if part.get("k", "box") == "cyl":
        d = float(part.get("d", 1.0))
        return (d, float(part.get("h", 1.0)), d)
    return vec(part.get("s"), (1.0, 1.0, 1.0))


def parts_of(h):
    if isinstance(h.get("parts"), list):
        return h["parts"]
    if "s" in h and h["k"] in MOVERS + SOLID_HAZARDS:
        return [{"k": "box", "p": [0.0, 0.0, 0.0], "s": h["s"]}]
    return []


def aabb(center, basis, size):
    """The box of a shape: `size` turned by `basis` about `center` (a box turned by a quarter turn is exact, any other turn is the enclosing box)."""
    lo, hi = [], []
    for i in range(3):
        ext = sum(abs(basis[i][j]) * size[j] * 0.5 for j in range(3))
        lo.append(center[i] - ext)
        hi.append(center[i] + ext)
    return (tuple(lo), tuple(hi))


def static_box(b):
    return aabb(vec(b.get("p")), euler(b.get("r")), shape_size(b))


def part_boxes(h, position, basis):
    out = []
    for part in parts_of(h):
        local = apply(basis, vec(part.get("p")))
        center = tuple(position[i] + local[i] for i in range(3))
        out.append(aabb(center, mat_mul(basis, euler(part.get("r"))), shape_size(part)))
    return out


def gap(a, b):
    """Euclidean distance of two boxes; negative (the smallest overlap depth) when they overlap."""
    sq = 0.0
    depth = math.inf
    for i in range(3):
        d = max(a[0][i] - b[1][i], b[0][i] - a[1][i])
        if d > 0:
            sq += d * d
        depth = min(depth, -d)
    return math.sqrt(sq) if sq > 0 else -depth


def boxes_gap(xs, ys):
    best = math.inf
    for x in xs:
        for y in ys:
            best = min(best, gap(x, y))
    return best


def union(boxes):
    return (tuple(min(b[0][i] for b in boxes) for i in range(3)), tuple(max(b[1][i] for b in boxes) for i in range(3)))


def swept(h, step=0.1):
    """The box that holds every pose of a hazard over its period (parts united)."""
    period = period_of(h)
    out = []
    n = max(int(math.ceil(period / step)), 1)
    for i in range(n + 1):
        pos, basis = hazard_pose(h, period * i / n)
        out.extend(part_boxes(h, pos, basis))
    return union(out)


def is_gate_door(h):
    parts = parts_of(h)
    return bool(parts) and all(p.get("tone") == "door" for p in parts)


def plan_overlap(part, floor):
    return part[0][0] < floor[1][0] and floor[0][0] < part[1][0] and part[0][2] < floor[1][2] and floor[0][2] < part[1][2]


def stands_on(part, floor):
    """The part's bottom lies on the floor's top (within 1 mm) with the two overlapping in plan: the contact of a wall that stands on a floor."""
    return abs(part[0][1] - floor[1][1]) <= 1e-3 and plan_overlap(part, floor)


def over(part, floor):
    """The part is over the floor in plan and not below its top (within 1 mm)."""
    return part[0][1] >= floor[1][1] - 1e-3 and plan_overlap(part, floor)


def common_period(a, b):
    """The period of two movers together: the least common multiple on the 1/8 s grid (capped at 600 s)."""
    ia, ib = round(a * 8), round(b * 8)
    return min(ia * ib // math.gcd(ia, ib) / 8.0, 600.0)


# --- the sweep -----------------------------------------------------------------------------------------------------------------------------------------------

def inflate(box, m):
    return (tuple(v - m for v in box[0]), tuple(v + m for v in box[1]))


def overlap(a, b):
    return all(a[0][i] <= b[1][i] and b[0][i] <= a[1][i] for i in range(3))


def sweep(level, min_gap=MIN_GAP, step=STEP):
    """Hits of one level: [(gap, time, name_a, name_b)] (one per pair and per static block: the closest moment)."""
    hazards = [h for h in level.get("hazards", []) if isinstance(h, dict)]
    names = {}
    for h in hazards:
        names[id(h)] = h.get("id") or f"{h['k']}#{hazards.index(h)}"
    movers = [h for h in hazards if h["k"] in MOVERS]
    others = [h for h in hazards if h["k"] in SOLID_HAZARDS]
    statics = []
    for index, b in enumerate(level.get("blocks", [])):
        tone = b.get("tone", "")
        statics.append((f"block#{index}({b.get('k', 'box')} {tone or 'plain'} @{b.get('p')})", static_box(b), tone))
    for h in others:
        if h["k"] == "blink":
            statics.extend((f"{names[id(h)]}(blink)", box, "") for box in part_boxes(h, *hazard_pose(h, 0.0)))
    hits = []
    margin = min_gap + 0.01
    spun = [h for h in others if h["k"] in ("spin", "swing")]
    reach = {id(h): swept(h) for h in movers + spun}

    for h in movers:
        period = period_of(h)
        n = int(math.ceil(period / step))
        poses = [part_boxes(h, *hazard_pose(h, period * i / n)) for i in range(n + 1)]
        # a mover against the static blocks: its own period, the blocks near its run only
        door = is_gate_door(h)
        standing = bool(h.get("hit")) or door   # a door shuts onto its sill (gates never bonk: `hit` is false)
        near = [s for s in statics if overlap(inflate(reach[id(h)], margin + 0.5), s[1]) and not (door and s[2] in ("arch", "navy"))]
        for name, box, _tone in near:
            worst = (math.inf, 0.0)
            floor = standing and any(stands_on(part, box) for boxes in poses for part in boxes)
            for i, boxes in enumerate(poses):
                g = math.inf
                for part in boxes:
                    if floor and over(part, box):
                        continue
                    g = min(g, gap(part, box))
                if g < worst[0]:
                    worst = (g, period * i / n)
            if worst[0] < min_gap:
                hits.append((worst[0], worst[1], names[id(h)], name))
    # mover against mover / spinner: together over the common period
    for a in movers:
        for b in movers + spun:
            if b is a or (b["k"] in MOVERS and id(b) < id(a)):
                continue
            if not overlap(inflate(reach[id(a)], margin + 0.5), reach[id(b)]):
                continue
            total = common_period(period_of(a), period_of(b))
            n = int(math.ceil(total / step))
            worst = (math.inf, 0.0)
            for i in range(n + 1):
                t = total * i / n
                g = boxes_gap(part_boxes(a, *hazard_pose(a, t)), part_boxes(b, *hazard_pose(b, t)))
                if g < CLOSE_BAND:  # the sample step may have jumped over the closest moment: look at it finely
                    fine_n = max(int(round(total / n / FINE)), 1)
                    for j in range(-fine_n, fine_n + 1):
                        tt = t + total / n * j / fine_n
                        g = min(g, boxes_gap(part_boxes(a, *hazard_pose(a, tt)), part_boxes(b, *hazard_pose(b, tt))))
                        if g < worst[0]:
                            worst = (g, tt % total)
                if g < worst[0]:
                    worst = (g, t)
            if worst[0] < min_gap:
                hits.append((worst[0], worst[1], names[id(a)], names[id(b)]))
    return sorted(hits, key=lambda x: (x[2], x[3]))


def check(level, min_gap=MIN_GAP, step=STEP):
    """Error texts of one level (the lint's hook): one per hit."""
    number = level.get("number", "?")
    return [f"level {number}: mover {a} comes within {g:+.2f} m of {b} at t={t:.2f} s (at least {min_gap} m): moving platforms never overlap or crowd anything (tools/mover_clearance_check.py)"
            for g, t, a, b in sweep(level, min_gap, step)]


def level_number(path, level):
    return int(level.get("number", 0)) or path.stem


def check_file(path, min_gap=MIN_GAP, step=STEP):
    level = json.loads(Path(path).read_text())
    return level_number(Path(path), level), sweep(level, min_gap, step), level


def dump_poses(paths):
    """`id t x y z` of every mover of the levels at fixed clock values: the real world's `Hazards.pose` must give the same (tools/mover_pose_check.gd)."""
    for path in paths:
        level = json.loads(Path(path).read_text())
        for h in level.get("hazards", []):
            if h["k"] in MOVERS:
                for t in POSE_TIMES:
                    pos, _ = hazard_pose(h, t)
                    print(f"{Path(path).name} {h.get('id', '')} {t:.4f} {pos[0]:.5f} {pos[1]:.5f} {pos[2]:.5f}")
    return 0


POSE_TIMES = (0.0, 0.5, 1.37, 2.9, 4.25, 7.77, 11.1, 13.6, 19.3, 23.99, 31.5, 57.25, 101.9)


def main(argv):
    min_gap, step = MIN_GAP, STEP
    files = []
    poses = False
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--min-gap":
            min_gap = float(args.pop(0))
        elif a == "--step":
            step = float(args.pop(0))
        elif a == "--levels":
            files += [ROOT / "demo" / "levels" / f"level_{n}.json" for n in args.pop(0).split(",")]
        elif a == "--poses":
            poses = True
        else:
            files.append(Path(a))
    if not files:
        files = [ROOT / "demo" / "levels" / f"level_{n}.json" for n in (29, 30, 31, 32)]
    if poses:
        return dump_poses(files)
    total = 0
    for path in files:
        number, hits, level = check_file(path, min_gap, step)
        movers = sum(1 for h in level.get("hazards", []) if h.get("k") in MOVERS)
        print(f"level {number}: {movers} movers, {len(hits)} clearance hit(s) under {min_gap} m")
        for g, t, a, b in hits:
            print(f"  level {number}: {a} / {b}  t={t:.2f} s  gap={g:+.2f} m")
        total += len(hits)
    print("mover_clearance_check: " + ("OK" if total == 0 else f"{total} hit(s)"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
