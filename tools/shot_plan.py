#!/usr/bin/env python3
"""The life of a ball or cannon ball, level-local and clock-free: where it starts, where it is swallowed. The exact twin of `demo/levels/hazards.gd`
(`ball_ports`, `shot_plan`), used by tools/level_lint.py to check that no ball pops in or out in view, and to size a cannon's `life` / `period`.

    python3 tools/shot_plan.py demo/levels/level_23.json      # prints every ball's two ports and every cannon's plan

Keep the constants and the arithmetic in step with hazards.gd (the unit tests in tools/test_shot_plan.py pin the numbers)."""
import functools
import json
import math
import sys

GRAVITY = 17.0
RESTITUTION = 0.5     # a cannon ball keeps this share of its fall speed on a bounce ...
FRICTION = 0.85       # ... and of its flat speed
REST_SPEED = 2.5      # a bounce slower than this (m/s) is a roll
MAX_ARCS = 10
MAX_ROLL = 40.0       # m
ROLL_STEP = 0.25
FALL_DEPTH = 14.0     # a ball that leaves a floor falls this far, then it is gone
WALL_REACH = 0.3      # a ball start / end this near a wall (centre distance - radius) is in that wall's slot
PORT_TIME = 0.5       # s a ball takes to come up out of / sink into a floor hole
SWALLOW = 0.1         # m past fully inside a wall
PEN_TOL = 0.05        # m a rolling ball may sink into a block (rounding of the grid)
TURN_MIN = 5.0       # degrees: a smaller bend of a ball's path is no bend (nothing to explain)
BOUNCE_TOL = 6.0      # degrees: a bend is a bounce when the way out mirrors the way in this closely
SLOT_SQUARE = 0.985   # cos 10 deg: a path end meets its wall's slot at least this square on (the slot is round and flat on the wall)
SWEEP_STEP = 0.25     # m between the points at which a path is tested against the blocks


def euler_basis(r):
    """Godot YXZ Euler order, degrees; columns are the basis vectors."""
    x, y, z = (math.radians(a) for a in r)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    xz = [[sum(rx[i][k] * rz[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return [[sum(ry[i][k] * xz[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _planes(b):
    k = b.get("k", "box")
    s = b.get("s", [1, 1, 1])
    if k == "cyl":
        h = b.get("h", 1.0) / 2
        return [([0, 1, 0], h), ([0, -1, 0], h)]
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    out = [([1, 0, 0], hx), ([-1, 0, 0], hx)]
    if k == "box":
        out += [([0, 1, 0], hy), ([0, -1, 0], hy), ([0, 0, 1], hz), ([0, 0, -1], hz)]
    else:  # wedge
        out += [([0, -1, 0], hy), ([0, 0, 1], hz), ([0, 1, -s[1] / s[2]], 0.0)]
    return out


def ray_hit(b, origin, direction):
    """Distance along the ray at which it enters block `b` (a dict of a level file's block); math.inf when it misses; 0 when it starts inside."""
    rot = euler_basis(b.get("r", [0, 0, 0]))
    centre = b.get("p", [0, 0, 0])
    rel = [origin[i] - centre[i] for i in range(3)]
    o = [sum(rot[k][i] * rel[k] for k in range(3)) for i in range(3)]       # inverse = transpose
    d = [sum(rot[k][i] * direction[k] for k in range(3)) for i in range(3)]
    t_in, t_out = -math.inf, math.inf
    for n, c in _planes(b):
        denom = sum(n[i] * d[i] for i in range(3))
        num = c - sum(n[i] * o[i] for i in range(3))
        if abs(denom) < 1e-9:
            if num < 0:
                return math.inf
            continue
        t = num / denom
        if denom > 0:
            t_out = min(t_out, t)
        else:
            t_in = max(t_in, t)
    if b.get("k") == "cyl":
        r = b.get("d", 1.0) / 2
        a = d[0] ** 2 + d[2] ** 2
        c = o[0] ** 2 + o[2] ** 2 - r * r
        if a < 1e-9:
            if c > 0:
                return math.inf
        else:
            bb = 2 * (o[0] * d[0] + o[2] * d[2])
            disc = bb * bb - 4 * a * c
            if disc < 0:
                return math.inf
            root = math.sqrt(disc)
            t_in = max(t_in, (-bb - root) / (2 * a))
            t_out = min(t_out, (-bb + root) / (2 * a))
    if t_in > t_out or t_out < 0:
        return math.inf
    return max(t_in, 0.0)


def floor_y(blocks, at):
    """The top of the highest block under `at` (a ray straight down), None for none."""
    best = math.inf
    for b in blocks:
        best = min(best, ray_hit(b, at, [0, -1, 0]))
    return None if best == math.inf else at[1] - best


def wall_distance(blocks, at, direction):
    """Distance along the horizontal-ish ray to the nearest block, math.inf for none."""
    return min((ray_hit(b, at, direction) for b in blocks), default=math.inf)


def _norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return [c / n for c in v] if n > 1e-9 else [0.0, 0.0, 0.0]


def _add(a, b, k=1.0):
    return [a[i] + b[i] * k for i in range(3)]


@functools.lru_cache(maxsize=None)
def _basis(r):
    return euler_basis(list(r))


def _local(b, p):
    """`p` in the block's own frame, and the block's basis (world = basis * local)."""
    rot = _basis(tuple(b.get("r", [0, 0, 0])))
    centre = b.get("p", [0, 0, 0])
    rel = [p[i] - centre[i] for i in range(3)]
    return [sum(rot[k][i] * rel[k] for k in range(3)) for i in range(3)], rot


def surface_gap(b, p):
    """Distance from point `p` to block `b` (a box or an upright cylinder; 0 inside); math.inf for any other shape (not tested)."""
    o, _ = _local(b, p)
    k = b.get("k", "box")
    if k == "cyl":
        return math.hypot(max(math.hypot(o[0], o[2]) - b.get("d", 1.0) / 2, 0.0), max(abs(o[1]) - b.get("h", 1.0) / 2, 0.0))
    if k != "box":
        return math.inf
    s = b.get("s", [1, 1, 1])
    return math.sqrt(sum(max(abs(o[i]) - s[i] / 2, 0.0) ** 2 for i in range(3)))


def wall_face(blocks, at, direction):
    """(distance, outward unit normal) of the nearest face a ray from `at` along `direction` enters (a box or a cylinder); (math.inf, None) for none."""
    best = (math.inf, None)
    for b in blocks:
        t = ray_hit(b, at, direction)
        if t == math.inf or t <= 0.0 or t >= best[0]:
            continue
        o, rot = _local(b, _add(at, direction, t))
        if b.get("k", "box") == "cyl":
            r, h = b.get("d", 1.0) / 2, b.get("h", 1.0) / 2
            n_local = [0, 1 if o[1] > 0 else -1, 0] if abs(o[1]) >= h - 1e-6 and math.hypot(o[0], o[2]) < r - 1e-6 else _norm([o[0], 0.0, o[2]])
        else:
            half = [c / 2 for c in b.get("s", [1, 1, 1])]
            axis = max(range(3), key=lambda i: abs(o[i]) / half[i] if half[i] > 0 else 0.0)
            n_local = [0, 0, 0]
            n_local[axis] = 1 if o[axis] > 0 else -1
        best = (t, [sum(rot[i][j] * n_local[j] for j in range(3)) for i in range(3)])
    return best


def _angle(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, sum(a[i] * b[i] for i in range(3))))))


# ---------------------------------------------------------------- rolling balls


def ball_port(blocks, at, direction, rad):
    """The housing of one end of a ball's path: the ball (centre `at`, radius `rad`) leaves / enters along `direction`.
    {"kind": "wall", "point", "normal", "hide"}: a wall within reach, the ball goes through a round slot in it, `hide` m of centre travel to be fully inside;
    {"kind": "floor", "point"}: it comes up out of / sinks into a hole in the floor under it; {"kind": "none"}: nothing hides it (the ball pops)."""
    wd = wall_distance(blocks, at, direction)
    if wd <= rad + WALL_REACH:
        return {"kind": "wall", "point": _add(at, direction, wd), "normal": [-c for c in direction], "hide": wd + rad + SWALLOW}
    fy = floor_y(blocks, at)
    if fy is not None and at[1] - fy <= rad + WALL_REACH:
        return {"kind": "floor", "point": [at[0], fy, at[2]]}
    return {"kind": "none"}


def ball_ports(h, blocks):
    """{"enter": port, "leave": port, "run": s on the path, "lead_in": s, "lead_out": s, "gap": s of the period outside the path} for a `ball` hazard dict (level file keys)."""
    path = h["path"]
    rad = float(h.get("rad", 1.0))
    speed = max(float(h.get("speed", 4.0)), 0.5)
    period = max(float(h.get("period", 8.0)), 0.25)
    first = _norm([path[1][i] - path[0][i] for i in range(3)])
    last = _norm([path[-1][i] - path[-2][i] for i in range(3)])
    port_in = ball_port(blocks, path[0], [-c for c in first], rad)
    port_out = ball_port(blocks, path[-1], last, rad)
    length = sum(math.dist(path[i], path[i - 1]) for i in range(1, len(path)))
    run = length / speed
    gap = max(period - run, 0.0)
    lead_in = lead_time(port_in, speed)
    lead_out = lead_time(port_out, speed)
    if lead_in + lead_out > gap:  # not both fit: they share the gap
        scale = gap / (lead_in + lead_out) if lead_in + lead_out > 0 else 0.0
        lead_in, lead_out = lead_in * scale, lead_out * scale
    return {"enter": port_in, "leave": port_out, "run": run, "lead_in": lead_in, "lead_out": lead_out, "gap": gap}


def lead_time(port, speed):
    if port["kind"] == "wall":
        return port["hide"] / speed
    if port["kind"] == "floor":
        return PORT_TIME
    return 0.0


def ball_hidden(plan, h):
    """True when both ends are housed and their lead times fit in the gap of the period (nobody sees the ball pop)."""
    speed = max(float(h.get("speed", 4.0)), 0.5)
    need = sum(lead_time(plan[end], speed) for end in ("enter", "leave"))
    return plan["enter"]["kind"] != "none" and plan["leave"]["kind"] != "none" and need <= plan["gap"] + 1e-6


# ---------------------------------------------------------------- cannon balls


def solve_landing(dy, vy):
    """Seconds until a ball `dy` (>= 0) over its resting height with vertical speed `vy` is back on it."""
    return (vy + math.sqrt(vy * vy + 2.0 * GRAVITY * max(dy, 0.0))) / GRAVITY


def shot_plan(h, blocks):
    """The path of a cannon ball (hazard dict, level file keys: p, v, rad) as ballistic arcs and floor bounces, then a roll, until a wall swallows it or
    the floor ends. {"segments": [[t0, p0, v0, g, spin0], ...], "hit": s the ball can hurt, "end": s it is gone, "kind": "wall" | "edge" | "none",
    "port": the wall's slot (kind wall), "land": [x, y, z] first floor contact (None when it never lands)}."""
    rad = float(h.get("rad", 0.5))
    p = list(h["p"])
    v = list(h["v"])
    t = 0.0
    spin = 0.0
    segments = []
    kind = "none"
    port = {}
    hit = None
    land = None
    for _ in range(MAX_ARCS):
        fy = floor_y(blocks, [p[0], p[1], p[2]])
        flat = [v[0], 0.0, v[2]]
        speed = math.hypot(v[0], v[2])
        heading = _norm(flat)
        if fy is None:  # no floor: it falls
            fall = math.sqrt(2.0 * FALL_DEPTH / GRAVITY)
            segments.append([t, p, v, GRAVITY, spin])
            t += fall
            hit = t
            kind = "edge"
            break
        rest = fy + rad
        rolling = p[1] <= rest + 1e-3 and v[1] <= 1e-3
        if not rolling:
            s = solve_landing(p[1] - rest, v[1])
            wd = wall_distance(blocks, [p[0], rest, p[2]], heading) if speed > 0.01 else math.inf
            if wd - rad < speed * s:  # a wall before the ground: swallowed in the air
                s = max(wd - rad, 0.0) / speed
                segments.append([t, p, v, GRAVITY, spin])
                hit = t + s
                end = _add(_add(p, v, s), [0.0, 1.0, 0.0], -0.5 * GRAVITY * s * s)
                kind = "wall"
                port = {"point": _add(end, heading, rad), "normal": [-c for c in heading], "hide": 2.0 * rad + SWALLOW}
                t = hit + port["hide"] / speed
                break
            segments.append([t, p, v, GRAVITY, spin])
            spin += speed * s
            t += s
            p = _add(_add(p, v, s), [0.0, 1.0, 0.0], -0.5 * GRAVITY * s * s)
            p[1] = rest
            if land is None:
                land = list(p)
            vy = RESTITUTION * (GRAVITY * s - v[1])
            v = [v[0] * FRICTION, 0.0, v[2] * FRICTION]
            if vy < REST_SPEED:
                v[1] = 0.0
            else:
                v[1] = vy
            continue
        # rolling on the floor at `rest`
        if speed < 0.01:
            break
        wd = wall_distance(blocks, [p[0], rest, p[2]], heading)
        edge = math.inf
        steps = int(MAX_ROLL / ROLL_STEP)
        for i in range(1, steps + 1):
            probe = _add(p, heading, i * ROLL_STEP)
            probe_floor = floor_y(blocks, [probe[0], rest, probe[2]])
            if probe_floor is None or abs(probe_floor - fy) > 0.3:
                edge = (i - 1) * ROLL_STEP
                break
        run = min(wd - rad, edge, MAX_ROLL)
        run = max(run, 0.0)
        segments.append([t, p, v, 0.0, spin])
        t += run / speed
        spin += run
        p = _add(p, heading, run)
        if wd - rad <= edge and wd - rad <= MAX_ROLL:
            hit = t
            kind = "wall"
            port = {"point": _add(p, heading, rad), "normal": [-c for c in heading], "hide": 2.0 * rad + SWALLOW}
            t += port["hide"] / speed
        elif edge < MAX_ROLL:
            segments.append([t, p, v, GRAVITY, spin])
            t += math.sqrt(2.0 * FALL_DEPTH / GRAVITY)
            hit = t
            kind = "edge"
        else:
            hit = t
        break
    if hit is None:
        hit = t
    return {"segments": segments, "hit": hit, "end": t, "kind": kind, "port": port, "land": land}


# ---------------------------------------------------------------- the lint rule (tools/level_lint.py calls it)


def _vec(value):
    return isinstance(value, list) and len(value) == 3 and all(isinstance(c, (int, float)) and not isinstance(c, bool) for c in value)


def _grid_up(seconds, step=0.25):
    return math.ceil(seconds / step - 1e-9) * step


def lint_ball_path(rep, where, h, blocks, plan):
    """A ball rolls where it can: its centre never sinks into a block along the path (it would pass through a wall; a block that holds an end of the path, a ball that starts
    inside a thick wall, is its housing and is left out), every bend of a path is a bounce (a wall within reach of the bend, the way out the mirror image of the way in),
    and a wall slot at an end is met square on (a slanted end would cut the round slot across the wall face)."""
    path = h["path"]
    rad = float(h.get("rad", 1.0))
    housing = {index for index, blk in enumerate(blocks) if surface_gap(blk, path[0]) == 0.0 or surface_gap(blk, path[-1]) == 0.0}
    for i in range(1, len(path)):
        a, b = path[i - 1], path[i]
        steps = max(1, math.ceil(math.dist(a, b) / SWEEP_STEP - 1e-9))
        sunk = None
        for s in range(steps + 1):
            p = [a[j] + (b[j] - a[j]) * s / steps for j in range(3)]
            for index, blk in enumerate(blocks):
                if index in housing:
                    continue
                depth = rad - surface_gap(blk, p)
                if depth > PEN_TOL and (sunk is None or depth > sunk[0]):
                    sunk = (depth, index, p)
        if sunk is not None:
            rep.error(f"{where}: the path from {a} to {b} rolls {sunk[0]:.2f} m into blocks[{sunk[1]}] at {[round(c, 2) for c in sunk[2]]} (a ball cannot pass through a wall: "
                      f"keep its centre at least `rad` {rad} m from every block, floors included)")
            return
    for i in range(1, len(path) - 1):
        d_in = _norm([path[i][j] - path[i - 1][j] for j in range(3)])
        d_out = _norm([path[i + 1][j] - path[i][j] for j in range(3)])
        if _angle(d_in, d_out) <= TURN_MIN:
            continue
        t, n = wall_face(blocks, path[i], d_in)
        gap = t * -sum(d_in[j] * n[j] for j in range(3)) if n is not None else math.inf
        if abs(gap - rad) > WALL_REACH:
            rep.error(f"{where}: path[{i}] {path[i]} is a bend with no wall to bounce off (the nearest wall straight ahead is {gap:.2f} m away, a ball of `rad` {rad} bounces at "
                      f"{rad} m: a bend of a path is a bounce, put the bend {rad} m from the wall)")
            continue
        mirror = [d_in[j] - 2.0 * sum(d_in[m] * n[m] for m in range(3)) * n[j] for j in range(3)]
        if _angle(d_out, mirror) > BOUNCE_TOL:
            rep.error(f"{where}: path[{i}] {path[i]} bounces the wrong way: it leaves {_angle(d_out, mirror):.0f} degrees off the mirror image of the way in "
                      f"(it should leave along {[round(c, 2) for c in mirror]})")
    for end, name, direction in (("enter", "starts", [-c for c in _norm([path[1][j] - path[0][j] for j in range(3)])]),
                                 ("leave", "ends", _norm([path[-1][j] - path[-2][j] for j in range(3)]))):
        if plan[end]["kind"] != "wall":
            continue
        at = path[0] if end == "enter" else path[-1]
        _, n = wall_face(blocks, at, direction)
        if n is not None and -sum(direction[j] * n[j] for j in range(3)) < SLOT_SQUARE:
            rep.error(f"{where}: the ball {name} against a wall at a slant (the round slot is drawn flat on the wall face): end the path square to the wall, or at a floor hole")


def lint_shots(rep, hazards, blocks):
    """Nothing pops in or out in view. A `ball` starts and ends at a wall (a round slot in it) or over a floor (a hole in it), and the period holds the path plus the
    time to come out of / go into those housings; a `cannon` ball starts inside its barrel, lands, bounces, rolls and ends in a wall's slot or off a floor's edge, all
    within `life` and `period`."""
    for i, h in enumerate(hazards):
        if not isinstance(h, dict):
            continue
        k = h.get("k")
        where = f"hazards[{i}] ({k}{' ' + h['id'] if isinstance(h.get('id'), str) else ''})"
        if k == "ball":
            path = h.get("path")
            if not isinstance(path, list) or len(path) < 2 or not all(_vec(p) for p in path):
                continue
            plan = ball_ports(h, blocks)
            for end, name in (("enter", "starts"), ("leave", "ends")):
                if plan[end]["kind"] == "none":
                    rep.error(f"{where}: the ball {name} in open view, with no wall within {WALL_REACH} m of its end and no floor under it to hide in: it would pop "
                              f"{'in' if end == 'enter' else 'out'} (put the end against a wall, or on a floor)")
            if plan["enter"]["kind"] != "none" and plan["leave"]["kind"] != "none" and not ball_hidden(plan, h):
                speed = max(float(h.get("speed", 4.0)), 0.5)
                need = lead_time(plan["enter"], speed) + lead_time(plan["leave"], speed)
                rep.error(f"{where}: period {h.get('period', 8.0)} s is too short for the ball to roll out of and into its housings: the path takes {plan['run']:.2f} s "
                          f"and the housings {need:.2f} s more (period at least {_grid_up(plan['run'] + need):.2f})")
            lint_ball_path(rep, where, h, blocks, plan)
        elif k == "cannon":
            if not _vec(h.get("p")) or not _vec(h.get("v")):
                continue
            plan = shot_plan(h, blocks)
            period = max(float(h.get("period", 4.0)), 0.25)
            cap = min(float(h.get("life", 3.0)), period)
            if plan["kind"] == "none":
                rep.error(f"{where}: the cannon ball never reaches a wall or the end of a floor (it bounces and rolls on): a wall must stand in its way, on the far side of the road")
            elif plan["end"] > cap + 1e-6:
                rep.error(f"{where}: the cannon ball is in play for {plan['end']:.2f} s (arc, bounces, roll, the wall's slot) but life / period allow {cap:.2f} s: it would "
                          f"vanish in view (life and period at least {_grid_up(plan['end']):.2f}, or shoot it faster across the road)")


# ---------------------------------------------------------------- command line


def main(argv):
    for name in argv[1:] or []:
        data = json.load(open(name))
        blocks = data.get("blocks", [])
        for h in data.get("hazards", []):
            if h.get("k") == "ball":
                plan = ball_ports(h, blocks)
                print(f"{name} {h.get('id', '?')}: in {plan['enter']['kind']} out {plan['leave']['kind']} lead {plan['lead_in']:.2f}+{plan['lead_out']:.2f} of gap {plan['gap']:.2f}")
            elif h.get("k") == "cannon":
                plan = shot_plan(h, blocks)
                print(f"{name} {h.get('id', '?')}: {plan['kind']} hit {plan['hit']:.2f} end {plan['end']:.2f} period {h.get('period', 4.0)} land {plan['land']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
