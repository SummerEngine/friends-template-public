#!/usr/bin/env python3
"""Where a `blink` block is while it is not solid: under the level. The exact twin of `demo/levels/hazards.gd` (`_blink_fall`, `blink_depth`), used by
tools/level_lint.py (the shortest `off` that still lets a block fall out of reach) and pinned by tools/test_blink_drop.py.

Nothing in the game vanishes into nowhere: a blink block that stops being solid falls away (an accelerating fall, BLINK_FALL_TIME to cover its own
height plus BLINK_CLEAR), hangs there, and climbs back so that it arrives exactly when it is solid again. A block that stays gone for the round
(`off` of BLINK_AWAY_OFF or more) falls on, out of sight, to BLINK_AWAY_DEPTH. The schedule (`on`, `off`, `warn`, `phase`) is untouched.

    python3 tools/blink_drop.py demo/levels/level_14.json      # prints every blink hazard's height, depth and the depth at the key moments

Keep the constants and the arithmetic in step with hazards.gd."""
import json
import sys

from shot_plan import euler_basis

CLEAR = 2.0        # m under its own underside a gone block hangs, out of reach
FALL_TIME = 0.4    # s the fall to that depth takes
RISE_TIME = 0.5    # s the climb back takes, ending when it is solid again
AWAY_OFF = 20.0    # an `off` this long or longer: gone for the round
AWAY_DEPTH = 60.0  # m
AWAY_RISE = 2.0    # s the climb back from there takes at most (a swoosh seen only over its last metres)
MIN_OFF = FALL_TIME + RISE_TIME


def _apply(basis, v):
    return [sum(basis[i][k] * v[k] for k in range(3)) for i in range(3)]


def height(h):
    """The vertical extent (m) of the hazard's parts at rest: their corners, turned by the part's and the hazard's rotation."""
    base = euler_basis(h.get("r", [0, 0, 0]))
    parts = h.get("parts")
    if parts is None:
        parts = [{"k": "box", "p": [0, 0, 0], "s": h.get("s", [1, 1, 1])}]
    low, high = float("inf"), float("-inf")
    for part in parts:
        s = part.get("s", [1, 1, 1])
        if part.get("k") == "cyl":
            d, hh = part.get("d", 1.0), part.get("h", 1.0)
            s = [d, hh, d]
        half = [c / 2 for c in s]
        turn = euler_basis(part.get("r", [0, 0, 0]))
        at = part.get("p", [0, 0, 0])
        for corner in range(8):
            c = [half[0] if corner & 1 else -half[0], half[1] if corner & 2 else -half[1], half[2] if corner & 4 else -half[2]]
            local = _apply(turn, c)
            y = _apply(base, [local[i] + at[i] for i in range(3)])[1]
            low, high = min(low, y), max(high, y)
    return high - low if high > low else 1.0


def fall(h):
    """{sink, accel, rise_time, on, off}: how deep the block falls (m), its acceleration (m/s²) and the length of its climb (s)."""
    clear = height(h) + CLEAR
    on, off = max(float(h.get("on", 3.0)), 0.25), max(float(h.get("off", 3.0)), 0.25)
    away = off >= AWAY_OFF
    return {"sink": AWAY_DEPTH if away else clear, "accel": 2.0 * clear / (FALL_TIME * FALL_TIME),
            "rise_time": min(AWAY_RISE, off * 0.5) if away else RISE_TIME, "on": on, "off": off}


def depth(f, m):
    """How far under its place the block hangs `m` seconds into its cycle (0 while solid)."""
    if m < f["on"]:
        return 0.0
    s = m - f["on"]
    d = min(0.5 * f["accel"] * s * s, f["sink"])
    until = f["on"] + f["off"] - m
    if until < f["rise_time"]:
        u = max(until, 0.0) / f["rise_time"]
        d = min(d, f["sink"] * u * u)
    return d


def main(argv):
    for name in argv:
        for h in json.load(open(name)).get("hazards", []):
            if h.get("k") != "blink":
                continue
            f = fall(h)
            total = f["on"] + f["off"]
            probes = [f["on"] + FALL_TIME, f["on"] + 1.0, total - RISE_TIME, total - 0.1]
            print(f"{h.get('id', '?'):14} height {height(h):5.2f}  sink {f['sink']:5.2f}  " + "  ".join(f"{depth(f, m):5.2f}" for m in probes))


if __name__ == "__main__":
    main(sys.argv[1:])
