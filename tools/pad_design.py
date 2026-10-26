"""Throw design for launch pads (the push hazards of the race levels): a pad on a floor `src_top` at `src` (world x, z) has to land a courier at `aim` on a floor `aim_top`
inside `target_rect` (x0, x1, z0, z1). The flight is jump_reach.pad_flight (the stick held along the throw: the air brake takes the horizontal speed down to the walk speed
and no further). Used by tools/gen_level_29.py (the start pads, which throw over the lane band) and tools/gen_level_30.py."""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jump_reach import pad_flight, solve_pad, G  # noqa: E402


def qs(v):
    return round(v * 2.0) / 2.0


def ray_rect(p, d, rect):
    """Distances along the ray p + t d (d a unit 2D vector) at which it enters and leaves the rect (x0, x1, z0, z1); None when it misses."""
    x0, x1, z0, z1 = rect
    lo, hi = 0.0, 1e9
    for pi, di, a, b in ((p[0], d[0], x0, x1), (p[1], d[1], z0, z1)):
        if abs(di) < 1e-9:
            if pi < a or pi > b:
                return None
            continue
        t1, t2 = (a - pi) / di, (b - pi) / di
        lo, hi = max(lo, min(t1, t2)), min(hi, max(t1, t2))
    return (lo, hi) if lo <= hi else None


def design_pad(src, src_top, aim, aim_top, target_rect, max_speed=13.5, vys=(12.0, 14.0, 16.0, 18.0, 20.0)):
    """A push pad on a floor of height src_top at src (x, z) that throws a courier (stick held along the throw, which is what jump_reach.pad_flight models) to land
    at `aim` on a floor of height aim_top inside target_rect. Takes the lowest throw-up speed vy whose horizontal speed stays under max_speed, then the
    0.5 m/s grid velocity (vx, vz) whose real landing is closest to aim. Returns (v, info) with info the landing, distance, apex, margin to the target's
    edges and the clearance over its near edge."""
    dx, dz = aim[0] - src[0], aim[1] - src[1]
    dist = math.hypot(dx, dz)
    dh = aim_top - src_top
    d = (dx / dist, dz / dist)
    for vy in vys:
        if vy * vy / (2 * G) <= dh + 0.5:
            continue
        vh = solve_pad(dist, vy, dh)
        if vh <= max_speed:
            break
    best = None
    for ix in range(-3, 4):
        for iz in range(-3, 4):
            vx, vz = qs(vh * d[0]) + 0.5 * ix, qs(vh * d[1]) + 0.5 * iz
            s = math.hypot(vx, vz)
            if s < 0.1 or s > max_speed + 0.01:
                continue
            reach = pad_flight(s, vy, dh)[0]
            land = (src[0] + vx / s * reach, src[1] + vz / s * reach)
            err = math.hypot(land[0] - aim[0], land[1] - aim[1])
            if best is None or err < best[0]:
                best = (err, vx, vz, s, reach, land)
    _, vx, vz, s, reach, land = best
    x0, x1, z0, z1 = target_rect
    margin = min(land[0] - x0, x1 - land[0], land[1] - z0, z1 - land[1])
    ray = ray_rect(src, (vx / s, vz / s), target_rect)
    clearance = None
    if ray is not None:
        lo, hi = dh, vy * vy / (2 * G)
        for _ in range(40):
            mid = (lo + hi) / 2
            if pad_flight(s, vy, mid)[0] >= ray[0]:
                lo = mid
            else:
                hi = mid
        clearance = lo - dh
    info = {"land": [round(land[0], 2), round(land[1], 2)], "dist": round(reach, 2), "apex": round(src_top + vy * vy / (2 * G), 2), "margin": round(margin, 2),
            "clearance": None if clearance is None else round(clearance, 2), "speed": round(s, 2)}
    return [vx, vy, vz], info
