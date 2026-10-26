#!/usr/bin/env python3
"""Belt crossing jobs of the race levels for tools/belt_cross_probe.gd (standard library only):

  python3 tools/belt_jobs.py out.json [--level=29,30,31,32]

Reads demo/levels/level_NN.json (the level file IS the one source of a belt's speed: `belt` [vx, vz] is what carries the courier and what the chevrons of
style/belt_look.gdshader scroll at) and classifies every conveyor block against the route (`path`, the nearest segment, snapped to an axis, gives the course direction u there):

  * cross: the flow is across the course (|flow . u| < 0.5 |flow|). Strips that touch along the course are one group (a maze of rows). The courier starts STANDING on the
    group's first strip at its entry edge (CROSS_START m in), at lateral offsets 1 m apart over the strip's width, runs straight along u (jumping a little short of every edge
    that steps up, tools/belt_cross_probe.gd JUMP_SHORT) and has crossed when it stands on the group's last strip's far end.
  * lane: the flow is along the course (a treadmill that runs back at the racer). The courier starts standing at the belt's start, in the lane's middle, and runs along u to
    the far end.
  * stand: for every belt a courier standing still at the lateral middle / at the upstream end; the probe times how long it takes to be carried off the belt.

Job: {level, name, kind, u [x, z], flow [x, z], speed, strips [{rect [x0, x1, z0, z1], top, flow}], starts [[x, z]], jumps [the along of every edge that steps up], end_along, end_top, along_min}.
"""
import json
import math
import sys
from pathlib import Path

LEVELS = Path(__file__).resolve().parent.parent / "demo" / "levels"
CROSS_START = 0.3   # m in from the entry edge where a crossing starts
GROUP_GAP = 0.6     # m along the course: strips closer than this are one group


def course_dir(path, x, z):
    best = (1e18, (0.0, -1.0))
    for a, b in zip(path, path[1:]):
        dx, dz = b[0] - a[0], b[2] - a[2]
        n = math.hypot(dx, dz)
        if n < 1e-6:
            continue
        t = max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[2]) * dz) / (n * n)))
        d = math.hypot(a[0] + dx * t - x, a[2] + dz * t - z)
        if d < best[0]:
            best = (d, (dx / n, dz / n))
    dx, dz = best[1]   # the legs of the courses run along an axis: snap the (wiggly) route direction to it
    return (math.copysign(1.0, dx), 0.0) if abs(dx) >= abs(dz) else (0.0, math.copysign(1.0, dz))


def strip(b):
    x, y, z = b["p"]
    sx, sy, sz = b["s"]
    return {"rect": [x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2], "top": y + sy / 2, "flow": list(b["belt"])}


def along_range(s, u):
    x0, x1, z0, z1 = s["rect"]
    vals = [x * u[0] + z * u[1] for x in (x0, x1) for z in (z0, z1)]
    return min(vals), max(vals)


def across_range(s, u):
    x0, x1, z0, z1 = s["rect"]
    vals = [-x * u[1] + z * u[0] for x in (x0, x1) for z in (z0, z1)]   # the lateral axis (-u.z, u.x)
    return min(vals), max(vals)


def point(u, along, across):
    """The level-local point at `along` the course and `across` it (lateral axis (-u.z, u.x))."""
    return [round(u[0] * along - u[1] * across, 4), round(u[1] * along + u[0] * across, 4)]


def jobs_of(number):
    data = json.loads((LEVELS / f"level_{number:02d}.json").read_text())
    path = data["path"]
    strips = []
    for b in data["blocks"]:
        if b.get("m") == "belt" and (b["belt"][0] or b["belt"][1]):
            s = strip(b)
            cx, cz = (s["rect"][0] + s["rect"][1]) / 2, (s["rect"][2] + s["rect"][3]) / 2
            u = course_dir(path, cx, cz)
            flow = s["flow"]
            speed = math.hypot(*flow)
            kind = "lane" if abs(flow[0] * u[0] + flow[1] * u[1]) >= 0.5 * speed else "cross"
            s.update({"u": list(u), "kind": kind, "speed": speed})
            strips.append(s)
    jobs = []
    lanes = [s for s in strips if s["kind"] == "lane"]
    cross = [s for s in strips if s["kind"] == "cross"]
    for i, s in enumerate(sorted(lanes, key=lambda s: (s["rect"][2], s["rect"][0]))):
        u = s["u"]
        lo, hi = along_range(s, u)
        a0, a1 = across_range(s, u)
        mid = (a0 + a1) / 2
        jobs.append({"level": number, "name": f"L{number} lane {i + 1} ({s['speed']:g} m/s)", "kind": "lane", "u": u, "flow": s["flow"], "speed": s["speed"], "strips": [s],
                     "starts": [point(u, lo + CROSS_START, mid)], "jumps": [], "end_along": hi - 0.3, "end_top": s["top"], "along_min": lo})
    # cross strips: chains along the course (same direction of the course u within a chain)
    cross.sort(key=lambda s: (s["u"], along_range(s, s["u"])[0]))
    chains = []
    for s in cross:
        lo, hi = along_range(s, s["u"])
        for chain in chains:
            c_u = chain[0]["u"]
            if c_u == s["u"] and abs(along_range(chain[-1], c_u)[1] - lo) <= GROUP_GAP and abs(chain[-1]["top"] - s["top"]) <= 3.0 \
               and math.dist(chain[-1]["rect"][::2], s["rect"][::2]) < 40.0:
                chain.append(s)
                break
        else:
            chains.append([s])
    for i, chain in enumerate(chains):
        u = chain[0]["u"]
        lo = along_range(chain[0], u)[0]
        hi = along_range(chain[-1], u)[1]
        a0, a1 = across_range(chain[0], u)
        starts = []
        t = a0 + 0.5
        while t <= a1 - 0.5 + 1e-6:
            starts.append(point(u, lo + CROSS_START, t))
            t += 1.0
        jumps = []
        for prev, nxt in zip(chain, chain[1:]):
            if nxt["top"] > prev["top"] + 0.3:
                jumps.append(round(along_range(nxt, u)[0], 3))
        speeds = sorted({s["speed"] for s in chain})
        jobs.append({"level": number, "name": f"L{number} cross {i + 1} ({len(chain)} strip{'s' if len(chain) > 1 else ''}, {'/'.join(f'{v:g}' for v in speeds)} m/s)", "kind": "cross",
                     "u": u, "flow": chain[0]["flow"], "speed": speeds[-1], "strips": chain, "starts": starts, "jumps": jumps, "end_along": hi - 0.3,
                     "end_top": chain[-1]["top"], "along_min": lo, "depth": hi - lo, "width": a1 - a0})
    return jobs


def main(argv):
    levels = [29, 30, 31, 32]
    for a in argv:
        if a.startswith("--level="):
            levels = [int(v) for v in a.split("=", 1)[1].split(",")]
    plain = [a for a in argv if not a.startswith("--")]
    jobs = []
    for n in levels:
        jobs += jobs_of(n)
    out = {"jobs": jobs}
    Path(plain[0] if plain else "/dev/stdout").write_text(json.dumps(out, indent=1))
    for j in jobs:
        print(f"{j['name']}: {j['kind']} u={j['u']} starts={len(j['starts'])} jumps={j['jumps']} end_along={j['end_along']:.2f}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
