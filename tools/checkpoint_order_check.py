#!/usr/bin/env python3
"""Checkpoint order check of the show race levels (standard library only):

  python3 tools/checkpoint_order_check.py [--level=29,30] [--verbose]

A racer who dies respawns at the middle of the floor of the last checkpoint volume it stood in (`levels/level_world.gd` `team_start`, `checkpoint_spot`; the rules keep the
highest index). So dying at an obstacle must never put the racer behind it: dying skips an obstacle exactly when the respawn spot lies downstream of an obstacle the racer has
not passed. Rule for every checkpoint volume (route progress = arc length of the level's `path` at the nearest path point):

  1. the whole volume lies downstream of every blocking obstacle that is upstream of its spot (a racer can only be inside it once it has passed them), and
  2. its spot (the respawn) is not inside the reach of an obstacle, and
  3. the checkpoints follow the route in order.

Blocking obstacles: a hazard that hurts or moves a wall (`hit`: spin, swing, sweeping slide / lift, cannon, ball, spikes, fire, laser; a `lift` / `slide` whose parts wear a `tone` is
a gate wall or door) and belts, whose reach touches the route (closer than BLOCK_GROW to the path); an obstacle beside the route that never touches it does not block.
Exit code 1 on a violation. `check(data)` returns the list of messages (used by tools/level_lint.py).
"""
import json
import math
import sys
from pathlib import Path

DISC_GAP = 0.3      # m: a spinner's base disc keeps this much visible gap from the floors round it
DISC_TOUCH = 0.05   # m: ... unless it joins them flush
STEP = 0.25         # m between the samples of the route
BLOCK_GROW = 1.0    # m: an obstacle whose swept box is farther than this from the route does not block it
TOUCH_GROW = 0.35   # m (a courier's radius): the stretch of the route an obstacle covers
MARGIN = 0.75       # m of route progress that count as "the same place"
LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"
BLOCKING = ("spin", "swing", "slide", "lift", "cannon", "ball", "spikes", "fire", "laser", "blink")


def seg_progress(path):
    """The route as dense samples [(arc length, (x, y, z))], one every STEP m."""
    out = []
    acc = 0.0
    for a, b in zip(path, path[1:]):
        length = math.dist(a, b)
        n = max(1, int(math.ceil(length / STEP)))
        for k in range(n):
            t = k / n
            out.append((acc + t * length, tuple(a[j] + t * (b[j] - a[j]) for j in range(3))))
        acc += length
    out.append((acc, tuple(path[-1])))
    return out


def progress(samples, p):
    """Arc length of the route sample nearest to the point p (x, y, z)."""
    return min(samples, key=lambda sp: math.dist(sp[1], p))[0]


def euler(r):
    """Godot YXZ basis (rows) of degrees [rx, ry, rz]."""
    rx, ry, rz = (math.radians(v) for v in (r or [0, 0, 0]))
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    ry_ = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx_ = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz_ = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return mul(mul(ry_, rx_), rz_)


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def apply(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def axis_rot(axis, deg):
    return euler([deg, 0, 0] if axis == "x" else [0, deg, 0] if axis == "y" else [0, 0, deg])


def part_corners(part):
    """The 8 corners of a box part (a cylinder: the box round it) relative to the hazard's pivot, before the hazard's own turn."""
    if part.get("k", "box") == "cyl":
        d, h = part.get("d", 1.0), part.get("h", 1.0)
        half = [d / 2, h / 2, d / 2]
    else:
        half = [c / 2 for c in part.get("s", [1, 1, 1])]
    m = euler(part.get("r"))
    p = part.get("p", [0, 0, 0])
    return [[p[i] + apply(m, [sx * half[0], sy * half[1], sz * half[2]])[i] for i in range(3)] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]


def swept_box(h):
    """(lo, hi) world axis aligned box of everything a hazard sweeps (every pose of its cycle, sampled)."""
    parts = h.get("parts") or [{"k": "box", "p": [0, 0, 0], "s": h.get("s", [1, 1, 1])}]
    corners = [c for part in parts for c in part_corners(part)]
    base = euler(h.get("r"))
    k = h["k"]
    poses = [euler(None)]
    if k == "spin":
        poses = [axis_rot(h.get("axis", "y"), a) for a in range(0, 360, 10)]
    elif k == "swing":
        a0, a1 = h.get("a0", -60), h.get("a1", 60)
        poses = [axis_rot(h.get("axis", "x"), a0 + (a1 - a0) * i / 12) for i in range(13)]
    offsets = [[0.0, 0.0, 0.0]]
    if k == "slide":
        offsets = [[0.0, 0.0, 0.0], list(h.get("to", [0, 0, 0]))]
    elif k == "lift":
        offsets = [[0.0, 0.0, 0.0], [0.0, h.get("rise", 4.0), 0.0]]
    pts = []
    for pose in poses:
        for c in corners:
            w = apply(base, apply(pose, c))
            for off in offsets:
                pts.append([h["p"][i] + w[i] + off[i] for i in range(3)])
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]


def inside(box, p, grow):
    """p (a point a courier's middle height over the route) in the box grown by `grow` in plan and by 0.6 m in height."""
    lo, hi = box
    return all(lo[i] - (grow if i != 1 else 0.6) <= p[i] <= hi[i] + (grow if i != 1 else 0.6) for i in range(3))


def obstacles(data, samples):
    boxes = []
    for h in data.get("hazards", []):
        k = h.get("k")
        if k not in BLOCKING or not h.get("p"):
            continue
        toned = any("tone" in part for part in (h.get("parts") or []))
        if k in ("slide", "lift", "blink") and not (h.get("hit") or toned):
            continue   # a ferry / lift that carries riders; the start gate
        if k == "blink" and h.get("slot") == "gate":
            continue
        if k in ("cannon", "ball", "laser", "fire", "spikes") and not h.get("parts") and not h.get("s"):
            p = h.get("p") or h["path"][0]
            boxes.append((f"{k} {h.get('id', '')}".strip(), ([p[0] - 1, p[1] - 1, p[2] - 1], [p[0] + 1, p[1] + 1, p[2] + 1])))
            continue
        boxes.append((f"{k} {h.get('id', '')}".strip(), swept_box(h)))
    for i, b in enumerate(data.get("blocks", [])):
        if b.get("m") == "belt":
            x, y, z = b["p"]
            sx, sy, sz = b["s"]
            boxes.append((f"belt blocks[{i}]", ([x - sx / 2, y - sy / 2, z - sz / 2], [x + sx / 2, y + sy / 2, z + sz / 2])))
    result = []
    for name, box in boxes:
        # y: a courier stands up to 1.8 m over the floor, an obstacle that sweeps lower or higher than the route's deck by a lot is not on it
        near = [s for s, p in samples if inside(box, (p[0], p[1] + 0.5, p[2]), BLOCK_GROW)]
        if not near:
            continue
        span = [s for s, p in samples if inside(box, (p[0], p[1] + 0.5, p[2]), TOUCH_GROW)] or near
        result.append({"name": name, "lo": min(span), "hi": max(span), "mid": (min(near) + max(near)) / 2})
    return result


def volume_samples(c, samples):
    x, y, z = c["p"]
    sx, sy, sz = c["s"]
    box = ([x - sx / 2, y - sy / 2, z - sz / 2], [x + sx / 2, y + sy / 2, z + sz / 2])
    return [s for s, p in samples if inside(box, (p[0], p[1] + 0.5, p[2]), 0.0)]


def check(data):
    path = data.get("path") or []
    cps = data.get("checkpoints") or []
    if len(path) < 2 or not cps:
        return disc_gaps(data)
    samples = seg_progress(path)
    obs = obstacles(data, samples)
    messages = disc_gaps(data)
    last = -1.0
    for i, c in enumerate(cps):
        label = f"checkpoints[{i}]"
        spot = (c["p"][0], c["p"][1] - c["s"][1] / 2 + 0.5, c["p"][2])
        s = progress(samples, spot)
        inside_route = volume_samples(c, samples)
        lo = min(inside_route) if inside_route else s
        if s < last - 1e-6:
            messages.append(f"{label}: its spot (route progress {s:.1f} m) lies before the checkpoint {i - 1} ({last:.1f} m): the checkpoints must follow the route")
        last = max(last, s)
        for o in obs:
            if o["mid"] < s - MARGIN and lo < o["hi"] - MARGIN:
                messages.append(f"{label}: its volume starts at route progress {lo:.1f} m, before {o['name']} ({o['lo']:.1f}..{o['hi']:.1f} m), but its respawn spot (progress {s:.1f} m) is behind it: a racer could stand in it without passing the obstacle, or die at it and skip it")
            elif o["lo"] + MARGIN < s < o["hi"] - MARGIN:
                messages.append(f"{label}: its respawn spot (progress {s:.1f} m) is inside the reach of {o['name']} ({o['lo']:.1f}..{o['hi']:.1f} m)")
    return messages


def disc_gaps(data):
    """Every spinner base disc (a cylinder block with tone `disc`) must keep a visible gap of at least DISC_GAP from every other floor at its height (a box or another disc):
    touching flush (a gap under DISC_TOUCH, the floors join) is fine, a disc that cuts into a walkway or stands a sliver away is not."""
    discs = [b for b in data.get("blocks", []) if b.get("k") == "cyl" and b.get("tone") == "disc"]
    messages = []

    def plan_gap(b1, b2):
        dx = max(abs(b1["p"][0] - b2["p"][0]) - (b1["s"][0] + b2["s"][0]) / 2, 0.0)
        dz = max(abs(b1["p"][2] - b2["p"][2]) - (b1["s"][2] + b2["s"][2]) / 2, 0.0)
        return math.hypot(dx, dz)

    for i, d in enumerate(discs):
        near = []   # (index, block, gap) of the floors at the disc's height
        cx, cy, cz = d["p"]
        r = d["d"] / 2
        top = cy + d["h"] / 2
        for j, b in enumerate(data.get("blocks", [])):
            if b is d or b.get("tone") in ("hub",) or b.get("hit"):
                continue
            x, y, z = b["p"]
            if b.get("k") == "cyl":
                if b.get("tone") != "disc":
                    continue
                dist = math.hypot(x - cx, z - cz) - r - b["d"] / 2
                btop, bbot = y + b["h"] / 2, y - b["h"] / 2
            else:
                sx, sy, sz = b["s"]
                dx = max(abs(cx - x) - sx / 2, 0.0)
                dz = max(abs(cz - z) - sz / 2, 0.0)
                if dx == 0.0 and dz == 0.0:
                    dist = -r   # the centre is over the box: it cuts in
                else:
                    dist = math.hypot(dx, dz) - r
                btop, bbot = y + sy / 2, y - sy / 2
            if btop < top - 1.0 or bbot > top - 0.05 or btop > top + 1.0:
                continue   # not a floor at the disc's height (a pillar far under it, a wall tall over it that the disc does not touch)
            near.append((j, b, dist))
        flush = [b for _, b, dist in near if -DISC_TOUCH <= dist <= DISC_TOUCH]
        for j, b, dist in near:
            if -DISC_TOUCH <= dist <= DISC_TOUCH:
                continue
            if 0 < dist < DISC_GAP and b.get("k", "box") == "box" and any(f.get("k", "box") == "box" and plan_gap(f, b) <= DISC_TOUCH for f in flush):
                continue   # the curve of a disc that touches a floor flush leaves slivers beside the contact: those belong to it
            if dist < DISC_GAP:
                what = "cuts into" if dist < 0 else "stands only %.2f m from" % dist
                messages.append(f"disc at {[round(c, 2) for c in d['p']]} (d {d['d']:g}) {what} blocks[{j}] at {[round(c, 2) for c in b['p']]} (gap {dist:.2f} m, wanted at least {DISC_GAP} m or flush)")
    return messages


def main(argv):
    only = None
    for a in argv:
        if a.startswith("--level="):
            only = {int(n) for n in a.split("=")[1].split(",")}
    bad = 0
    for f in sorted(LEVELS.glob("level_*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        if data.get("show") != "race" or (only and data.get("number") not in only):
            continue
        msgs = check(data)
        print(f"{f.name}: {'ok' if not msgs else str(len(msgs)) + ' problems'}")
        for m in msgs:
            print("  " + m)
        bad += len(msgs)
    print(f"checkpoint_order_check: {'ok' if not bad else 'FAIL'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
