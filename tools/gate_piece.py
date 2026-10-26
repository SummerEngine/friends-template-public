"""The gate wall of the daylight race levels (29, 30, and any level that wants the same doors): ONE navy quilted wall with a crafted doorway frame set into it
for every gate, a pair of small green eyes on each frame and a blue chevron door that slides up into the top of the frame and down again. Returns plain
blocks and hazards for the level file; standard library only. `gate_wall(...)` is the whole API (docs/level-format.md, "Gate walls").

Geometry of one gate, metres, u across the wall, f along the course (the courier comes from small f), y up from the floor top `y0`; o = OUTLINE = 0.5:
  wall      navy block, 1.0 m deep (f0 .. f0 + 1), `wall_h` tall, one block per stretch of wall between the frames (`tone navy`: quilted sides)
  frame     two piers (o wide, 2h + o tall), a beam over them (o tall) and the core between the piers over the opening (h .. 2h): all `tone arch`, 1.5 m deep (0.25 proud of the
            wall on each side). The look draws ONE rounded-arch frame (teal, a yellow lip round the opening) from the core (style/gate_look.gd); the blocks are collision only.
  eyes      two `eye` discs, d 0.5, 0.25 thick, standing on the beam facing along the course (small flat discs with a dark X)
  door      a `lift` (no `hit`) with one part of `tone door` (blue, raised chevrons: style/pillar_kit.gd door_chevrons), W x h x 0.5, in front of the core (f0 - 0.25 .. f0 + 0.25).
            `hit` (default False): a door is solid and never throws anybody: a shut door only blocks, and one that comes down on a courier only nudges it out of its volume
            (levels/level_world.gd `door_nudge`: a depenetration of a few cm per tick, no launch, no bonk). Its rest pose is OPEN (up, in the top half of the frame, in front of the core, never under the floor); it comes down (`rise` -h) to shut: `pause` s open, a slow
            sine down, `pause` s shut, back up. `period` and `pause` are the lift's own keys (levels/hazards.gd cycle); an open door is clear for a courier (1.8 m) all the time
            it rests and for a good part of the way down / up.
The frame is 2h + o tall (h = 2.5: 5.5 m, the eyes' tops 6.0 m, the camera-layer blocks stay at 5.5 m under the stage camera at 6.6 m over the feet). Two frames side by side need a gap of 2 * o = 1.0 m between
their openings (the piers touch); `gate_wall` asserts it. Doors are grouped into lifts by `tag`: gate i belongs to set a when i is even, b when odd (set b runs half a period
later), so about half of a wall stands open at any time; a gate may carry its own phase offset (u, width, offset) and then forms a set of its own.
"""
OUTLINE = 0.5       # m: pier and beam width of a frame
DEPTH = 1.5         # m: frame depth (the wall is WALL_THICK, the frame stands 0.25 m proud on each side)
WALL_THICK = 1.0
CORE_THICK = 0.25   # m: the panel behind the door over the opening (the look finds a frame by it: the only `arch` box with a 0.25 m side)
DOOR_THICK = 0.5
EYE_D = 0.5         # m: a small flat disc standing on its rim on the beam, its faces (the green disc with the dark X) towards the course and away from it
EYE_H = 0.25
PERIOD = 4.0        # s: one open - shut - open round of a door
PAUSE = 1.25        # s: open and shut rests; the doors travel (PERIOD - 2 * PAUSE) / 2 = 0.75 s each way
OPEN_HEIGHT = 2.5   # m: the opening's height h (the frame is 2h + OUTLINE tall)


def q(v):
    return round(v * 4.0) / 4.0


def gate_wall(place, f0, y0, u0, u1, gates, name, wall_h=3.5, h=OPEN_HEIGHT, period=PERIOD, pause=PAUSE, phase=0.0, hit=False):
    """Blocks and hazards of one gate wall across u0..u1 at f0 .. f0 + 1 on a floor whose top is `y0` (the floor is the level's own).

    place(ua, ub, fa, fb) -> (x0, x1, z0, z1): the world rectangle of the u / f rectangle (a level's own axis mapping, e.g. gen_level_30.Leg.rect).
    gates: [(u, width)] or [(u, width, phase offset)]; name: the hazard ids are `<name>_a`, `<name>_b` (or `<name>_<i>` for a gate with its own phase).
    Returns {"blocks": [...], "hazards": [...], "doors": n}."""
    blocks, hazards = [], []
    o = OUTLINE
    gs = sorted(gates, key=lambda g: g[0])
    for a, b in zip(gs, gs[1:]):
        assert (b[0] - b[1] / 2) - (a[0] + a[1] / 2) >= 2 * o - 1e-9, f"{name}: gates {a[0]} and {b[0]} are closer than two pier widths"
    frame_h = 2 * h + o

    def box(rect, ya, yb, **kw):
        x0, x1, z0, z1 = rect
        blocks.append({"k": "box", "p": [q((x0 + x1) / 2), q((ya + yb) / 2), q((z0 + z1) / 2)], "s": [q(x1 - x0), q(yb - ya), q(z1 - z0)], **kw})

    fa, fb = f0 - (DEPTH - WALL_THICK) / 2, f0 + WALL_THICK + (DEPTH - WALL_THICK) / 2
    cursor = u0
    for g in gs:
        left = g[0] - g[1] / 2 - o
        assert left >= u0 - 1e-9 and g[0] + g[1] / 2 + o <= u1 + 1e-9, f"{name}: gate {g[0]} does not fit between {u0} and {u1}"
        if left - cursor >= 0.25:
            box(place(cursor, left, f0, f0 + WALL_THICK), y0, y0 + wall_h, tone="navy")
        cursor = g[0] + g[1] / 2 + o
    if u1 - cursor >= 0.25:
        box(place(cursor, u1, f0, f0 + WALL_THICK), y0, y0 + wall_h, tone="navy")
    for g in gs:
        uc, w = g[0], g[1]
        a, b = uc - w / 2, uc + w / 2
        box(place(a - o, a, fa, fb), y0, y0 + frame_h, tone="arch")                       # piers
        box(place(b, b + o, fa, fb), y0, y0 + frame_h, tone="arch")
        box(place(a, b, fa, fb), y0 + 2 * h, y0 + frame_h, tone="arch")                    # beam
        box(place(a, b, f0 + WALL_THICK / 2 - CORE_THICK / 2, f0 + WALL_THICK / 2 + CORE_THICK / 2), y0 + h, y0 + 2 * h, tone="arch")   # the core: the look's marker, the door's backstop
        turn = [90, 0, 0] if place(0.0, 1.0, 0.0, 0.0)[1] > place(0.0, 1.0, 0.0, 0.0)[0] + 0.5 else [0, 0, 90]   # the axis of the disc along f (a cylinder's axis is y)
        for du in (-1.0, 1.0):
            ex0, ex1, ez0, ez1 = place(uc + du * (w / 2 - 0.1), uc + du * (w / 2 - 0.1), f0 + WALL_THICK / 2, f0 + WALL_THICK / 2)
            blocks.append({"k": "cyl", "p": [q(ex0), q(y0 + frame_h + EYE_D / 2), q(ez0)], "d": EYE_D, "h": EYE_H, "r": turn, "tone": "eye"})
    sets = {}   # tag -> (phase, [gate])
    for i, g in enumerate(gs):
        if len(g) > 2:
            sets[str(i)] = (phase + g[2], [g])
        else:
            tag = "ab"[i % 2]
            sets.setdefault(tag, (phase + (i % 2) * period / 2, []))[1].append(g)
    for tag, (ph, members) in sets.items():
        ru = [place(g[0] - g[1] / 2, g[0] + g[1] / 2, f0 - DOOR_THICK / 2, f0 + DOOR_THICK / 2) for g in members]
        cx = q(sum((r[0] + r[1]) / 2 for r in ru) / len(ru))
        cz = q(sum((r[2] + r[3]) / 2 for r in ru) / len(ru))
        cy = y0 + 1.5 * h
        parts = [{"k": "box", "p": [q((r[0] + r[1]) / 2 - cx), 0.0, q((r[2] + r[3]) / 2 - cz)], "s": [q(r[1] - r[0]), q(h), q(r[3] - r[2])], "tone": "door"} for r in ru]
        hazards.append({"k": "lift", "id": f"{name}_{tag}", "p": [cx, q(cy), cz], "rise": -q(h), "period": period, "pause": pause, "phase": ph, "hit": hit, "parts": parts})
    return {"blocks": blocks, "hazards": hazards, "doors": len(gs)}
