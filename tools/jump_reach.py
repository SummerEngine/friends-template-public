#!/usr/bin/env python3
"""Jump reach of the courier's normal movement (demo/courier/courier_motion.gd constants), computed with the same
per-tick rules: run-up acceleration, jump 7 m/s up, gravity 17, no dash. Used to size gaps in the race levels.

  python3 tools/jump_reach.py                 # the table
  from jump_reach import max_gap              # max_gap(dh, run_up=None, coyote=0.0) -> metres

`dh` is the landing surface's height above the take-off edge (negative: lower). `run_up` is the metres of
flat ground before the edge (None = enough to be at full speed, 3 m is 0.83 m of acceleration at most).
The jump leaves from the edge (coyote 0): that is what a player who jumps on time gets. Measured gap = edge to edge.
The courier is a capsule of radius 0.35, so it may land with its centre 0.2 m inside the far edge, and the take-off
is at the edge's brink, which is what `max_gap` assumes (centre at the edge).
"""
WALK = 5.0
ACCEL = 15.0
JUMP = 7.0
G = 17.0
MAX_FALL = 40.0
DT = 1.0 / 60.0
LAND_INSET = 0.2 # the centre may land this far inside the far edge (capsule radius 0.35 stands on the brink)


def run_speed(run_up: float | None) -> float:
    if run_up is None:
        return WALK
    v2 = 2.0 * ACCEL * max(run_up, 0.0)
    return min(WALK, v2 ** 0.5)


def max_gap(dh: float, run_up: float | None = None, coyote: float = 0.0, air_speed: float | None = None) -> float:
    """Longest edge-to-edge gap a jump from the brink clears to a surface `dh` m higher (0 = level), or 0 if the height cannot be reached."""
    v = run_speed(run_up) if air_speed is None else air_speed
    t, vy = 0.0, JUMP
    # coyote: the courier has run off the brink and fell for `coyote` s before the press
    y = -0.5 * G * coyote * coyote
    x = v * coyote
    while t < 3.0:
        vy = max(vy - G * DT, -MAX_FALL)
        y += vy * DT
        x += v * DT
        t += DT
        if vy < 0.0 and y <= dh:
            return max(x + LAND_INSET, 0.0)
    return 0.0


AIR_BRAKE = 15.0 # courier_motion.gd FALL_BRAKE: above the walk speed the air slows the courier by this much, even with the stick held


def pad_flight(v_h: float, v_y: float, dh: float = 0.0, forward: bool = True) -> tuple[float, float, float]:
    """A launch pad throws the courier (override: horizontal speed `v_h` along the throw, up `v_y`). Returns (distance along the throw, flight time, apex height) until
    the courier is back at `dh` (height of the landing surface above the pad's floor) and falling. `forward`: the stick is held along the throw (a runner does), so the
    horizontal speed falls from `v_h` at AIR_BRAKE to the walk speed and stays there; without input it falls to 0 at AIR_BRAKE (the courier stops in the air)."""
    x, y, vy, t, s = 0.0, 0.0, v_y, 0.0, v_h
    top = 0.0
    floor = WALK if forward else 0.0
    while t < 6.0:
        s = max(s - AIR_BRAKE * DT, floor) if s > floor else min(s + 0.75 * ACCEL * DT, floor) if forward else s
        vy = max(vy - G * DT, -MAX_FALL)
        y += vy * DT
        x += s * DT
        t += DT
        top = max(top, y)
        if vy < 0.0 and y <= dh:
            return x, t, top
    return x, t, top


def solve_pad(distance: float, v_y: float, dh: float = 0.0) -> float:
    """The horizontal throw speed that lands `distance` m along the throw (stick held forward) on a surface `dh` above the pad's floor, for a throw up of `v_y`."""
    lo, hi = 0.0, 40.0
    for _ in range(40):
        mid = (lo + hi) / 2
        if pad_flight(mid, v_y, dh)[0] < distance:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def apex() -> float:
    return JUMP * JUMP / (2.0 * G)


if __name__ == "__main__":
    print("pad_flight(16.5, 11) =", tuple(round(v, 2) for v in pad_flight(16.5, 11.0)), " solve_pad(30 m, vy 11) =", round(solve_pad(30.0, 11.0), 1))
    print(f"apex {apex():.2f} m, air time on the level {2 * JUMP / G:.2f} s")
    print("dh(m)  gap@full-speed  gap@3m-run-up  gap@1m-run-up")
    for dh in (-3.0, -1.5, -0.5, 0.0, 0.5, 0.75, 1.0, 1.25, 1.4):
        print(f"{dh:5.2f}  {max_gap(dh):8.2f}  {max_gap(dh, 3.0):8.2f}  {max_gap(dh, 1.0):8.2f}")
