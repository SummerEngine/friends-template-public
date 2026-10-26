#!/usr/bin/env python3
"""Validates level files (docs/level-format.md): `tools/level_lint.py [dir-or-files ...]` (default demo/levels).

Errors: format, fields, grid rounding (0.25 m, 5 deg, 0.25 s, 0.5 m/s), ranges, ids, start / goal support, a path that does not reach the goal, a swing whose
pivot hangs from nothing, a push pad or bumper that floats over the floor, a show level whose kill volume reaches a courier standing on (or jumping from) a floor or
a lift, a `show: survival` level with any static block (no permanent safe ground), on a show level a picture face (obstacle box, mover box at any
pose, decor board) that is coplanar with or cut by a floor, on a `daylight` race level a slide / lift that comes within 0.3 m of another mover, a spinner or a block
(tools/mover_clearance_check.py), two floors with coplanar overlapping tops, a conveyor block (`m: belt`) without a valid `belt`, and more than
MAX_BLOCKS blocks or MAX_HAZARDS hazards.
Warnings: path spacing, unsupported path stretches (a jump is about 4 m), steps above a jump, anything off-grid in a file whose `note` says why.
Exit status 1 when any error was found (or any warning with --strict)."""
import json
import math
import sys
from pathlib import Path

import blink_drop  # where a gone blink block hangs (it falls away, never vanishes)
import checkpoint_order_check  # a checkpoint's respawn is never behind an obstacle the racer has not passed
import mover_clearance_check  # a slide / lift never comes within 0.3 m of another mover, a spinner or a block (race levels of the daylight world)
import shot_plan  # the life of a ball / cannon ball (no pop in or out in view)

GRID = {"pos": 0.25, "angle": 5.0, "time": 0.25, "speed": 0.5}
KINDS = {"slide", "lift", "spin", "swing", "blink", "spikes", "push", "bumper", "ball", "cannon", "laser", "fire"}
BLOCK_KEYS = {"k", "p", "s", "d", "h", "r", "m", "belt", "hit", "slot", "tone"}
PART_KEYS = {"k", "p", "s", "d", "h", "r", "slot"}
PART_TONE_KINDS = ("slide", "lift")  # a part of these hazards (a sliding or sinking wall, a door) may wear a `tone` too
COMMON = {"k", "id", "p", "r", "phase", "hit", "parts", "s", "slot"}
SCHEDULE = {"on", "off", "warn"}
HAZARD_KEYS = {
    "slide": COMMON | {"to", "period", "pause", "ease", "look"},
    "lift": COMMON | {"rise", "period", "pause", "hold", "ease", "look"},
    "spin": COMMON | {"axis", "rate", "look", "kick", "up"},
    "swing": COMMON | {"axis", "a0", "a1", "period", "pause", "ease", "look"},
    "blink": COMMON | {"on", "off", "warn"},
    "spikes": COMMON | {"rise", "period", "up", "warn"},
    "push": COMMON | {"g", "d", "h", "v", "ride"},
    "bumper": COMMON | {"rad", "kick", "up", "ride"},
    "ball": COMMON | {"path", "speed", "rad", "period"},
    "cannon": COMMON | {"v", "rad", "period", "life"},
    "laser": {"k", "id", "p", "r", "phase", "to", "move", "period", "pause", "ease", "axis", "rate"} | SCHEDULE,
    "fire": {"k", "id", "p", "r", "phase", "g", "s", "d", "h"} | SCHEDULE,
}
TOP_KEYS = {"format", "number", "title", "blurb", "pool", "note", "start", "goal", "path", "void_y", "kill", "blocks", "hazards",
            "modes", "checkpoints", "slots", "show", "podium", "cues", "tiles", "rule", "hint", "arena", "play", "solo", "stage", "draw", "world", "cap", "camera", "item_boxes"}
DOOR_KINDS = ("open", "solid", "torn")  # poster doors: an obstacle slot with "door" (levels/poster_doors.gd)
TONES = ("teal", "warm", "navy", "frame", "door", "crate", "eye", "court", "disc", "hub", "stone", "stone_plain", "arch", "slime", "finish")  # `tone` of a block of a `world: daylight` level: the surface it wears (style/race_surfaces.gd)
WORLDS = ("daylight",)  # `world`: the stage rounds' daylight and an open-air world without a cage (style/race_world.gd); no key = the cast's own world
DOOR_BLOCK_GAP = 0.125  # a solid door's hidden block: its front face this far behind the board's plane, as wide as the board, 0.25 deep
DOOR_MIN_WIDTH = 1.75   # a logo poster (open / torn door) is at least this wide: a courier (0.7 m) runs through it without scraping
FIRST_ROW_PROBLEMS = 4  # the row nearest the start: one logo poster among at least this many problem posters
RIDE_PERIOD_MAX = 10.0  # a row that slides comes round (the logo poster is back where it was) within this many seconds
RIDE_STEPS = 8          # poses of a sliding row that are tested (the slide's travel in eighths)
SEAL_STEP = 0.05        # m between the sample points of the sealing test
SLIT_MAX = 0.6          # a slit between posters narrower than this stops a courier (the capsule is 0.7 m across)
TEXT_MAX = 48           # a card rule / objective hint: upper case, short enough for a phone
MODES = {"carry", "balloon", "show"}
SHOW_KINDS = ("race", "survival", "final")
PLAYS = ("badge",)      # `play` of a survival show level: how it is played besides the kind (badge = KEEP THE LOGO)
OBSTACLE_SLOTS = {f"obstacle_{i}" for i in range(1, 6)}
GATE_SLOT = "gate"  # the start gate hazard (id gate): its faces wear the brand
HERO_SLOT = "hero_prop"  # a hero prop (docs/hero-prop.md): the slot, and the three cylinder blocks of its stand
HERO_SHARES = (1.0, 2.0 / 3.0, 1.0 / 3.0)  # tier diameters as shares of the footprint; each tier is a third of the height
SLOT_IDS = OBSTACLE_SLOTS | {f"poster_{i}" for i in range(1, 4)} | {f"egg_{i}" for i in range(1, 6)} | {"logo_wall", "team_wall"} | \
    {"arch_start", "arch_finish", "banner_1", "banner_2", "billboard_1", "billboard_2", "floor_start", "floor_finish", "crown", HERO_SLOT}
PODIUM_SPOTS = 3
BLINK_ON_MAX = 120      # a blink block may stay solid for a whole show round ...
BLINK_OFF_MAX = 600     # ... and stay gone for the rest of it
BLINK_OFF_MIN = 1.0     # a gone block falls out of reach and climbs back (blink_drop.MIN_OFF, 0.9 s, on the 0.25 s grid): a shorter `off` would leave it half way
assert BLINK_OFF_MIN >= blink_drop.MIN_OFF
MAX_EXTENT = 150.0
TILE_LOOKS = ("plain", "logo", "obstacle")
TILE_GRIDS = ("hex", "square")
STAGE_ENCLOSURES = ("a", "b")
STAGE_CAP_MAX = 150.0  # a stage round's own time cap (`stage.cap`): the level clock of a wrapped step byte covers it (levels/step_tiles.gd WRAP_MAX)
MAX_TILES = 960         # step tiles of an ordinary level: one state byte each, published in pieces of 240 B (levels/step_tiles.gd CHUNK x MAX_CHUNKS: the platform refuses a byte field over 256 B)
MAX_STAGE_TILES = 7680  # step tiles of a stage level: its state is a bitmap and a short list (levels/step_tiles.gd pack_state), pieces of 240 B
MAX_TILE_FLOORS = 9  # the hex stack: a start layer and eight full ones (collision layer bits TILE_LAYER_BASE << k, levels/step_tiles.gd)
HEX_ROW = math.sqrt(3) / 2  # distance between two rows of hexagon tiles, in pitches
TILE_FLOOR_GAP = 3.0    # metres between the tops of two floors: a courier walks (and jumps) under the one above
TILE_STAGE_FLOOR_GAP = 1.0  # a stage round's floors are one-way (courier/courier_motion.gd set_floors) and may sit closer than that: at least a tile's thickness plus the courier's own clearance below the next floor
STAGE_DEPTH = -160.0    # a stage stack (8 floors 14.3 m apart and the ground under it, 116 m) reaches deeper than the other levels
MAX_STAGE_STARTS = 12   # `stage.starts`: one pad per player of the biggest round
STAGE_START_GAP = 3.0   # metres between two start spots
Y_RANGE = (-40.0, 80.0)
BOX_ROWS_MAX = 5       # `item_boxes`: rows per level ...
BOXES_MAX = 12         # ... and boxes per level
BOX_STEP = (1.2, 3.0)  # m between the boxes of a row (the box is 1 m wide)
BOX_FLOOR_MIDDLE = 0.05  # the floor under the middle of a row is within this of its `p.y` ...
BOX_FLOOR_END = 0.15     # ... under each box of it within this
BOX_FOOT_RADIUS = 0.74   # the pedestal's radius (demo/modes/show/items_ui/box_look.gd)
BOX_FOOT_MARGIN = 0.2    # the floor goes on this far past the pedestal's rim
BOX_FOOT_FLAT = 0.06     # the floor under the pedestal's whole foot is flat within this (a few degrees at most)
BOX_CUBE_MARGIN = 0.1    # no solid block within this of the 1 m cube or the pedestal
BOX_HAZARD_CLEAR = 2.5   # m between a box and every hazard's swept volume (hazard_shapes) and every kill volume
MAX_BLOCKS = 600
MAX_HAZARDS = 80
SPIN_RATE_MAX = 180    # deg/s: a `spin` hazard's rate (a big wheel turns ~150 deg/s); a courier's bonk is the same however fast it turns (BONK_MAX)
MAX_SLOTS = 64        # frames per level; only obstacle_1..5 may repeat (poster doors: POSTER RUSH 17 has fifty boards)
MAX_CUES = 12
JUMP_RISE = 1.5       # metres a jump reaches
JUMP_GAP = 4.0        # metres a running jump crosses
PATH_STEP_WARN = 6.5
PATH_STEP_MAX = 8.0
PIVOT_REACH = 0.25    # a swing's pivot must lie inside a solid block, or within this far of one (the gantry it hangs from)
LAUNCHER_REACH = 1.0  # a push pad's / bumper's underside is at most this far over a block top (levels/level_world.gd LAUNCHER_REACH)
CENTRE_HEIGHT = 0.9   # a courier's centre over its feet: the point the kill and goal volumes test (levels/level_world.gd CENTRE_HEIGHT)
FINISH_DECAL_REACH = 0.25  # the finish decal's centre is within this far (XZ) of the goal's centre: the logo lies centred on the GOAL pad (style/real_look.gd mark_level paints it there)
FLOOR_SPAN = 1.0       # a static box is a floor when it is at least this wide both ways ...
RAIL_SPAN = 0.5        # ... or at least this wide and no taller than RAIL_HEIGHT (a deck's rim: a hop block); a tall wall or a post is not a floor
RAIL_HEIGHT = 1.75
PICTURE_LIFT = 0.012   # obstacle faces stand this far off their box (style/slot_frames.gd BOX_LIFT)
PICTURE_SLACK = 0.02   # a picture face this near a floor's volume counts as inside it
COPLANAR_TOL = 0.05    # two faces of one direction this near one plane are coplanar
SAMPLES = 12           # sample grid of a tilted face / a turned board
SWING_STEPS = 8        # poses along a swing's arc
BOARD_DEPTH = 0.12     # a decor board is this thick (docs/level-format.md)
BOARD_FREE = {"floor_start", "floor_finish", "crown", HERO_SLOT}  # slots that lie on a floor or stand in it on purpose
PICTURE_FACE_HELP = {"coplanar": "lift or trim the box so its face is not in the floor's plane", "cut": "lift the box clear of the floor, or let the floor only touch its face"}


class Report:
    def __init__(self, name):
        self.name = name
        self.errors = []
        self.warnings = []
        self.off_grid_allowed = False
        self.daylight = False   # the level has `"world": "daylight"`: its blocks may carry a `tone`
        self.free_grid = False  # a generated level (a stage round) is not on the hand-authoring grid: nothing is said

    def error(self, text):
        self.errors.append(text)

    def warn(self, text):
        self.warnings.append(text)

    def grid(self, where, value, kind):
        step = GRID[kind]
        values = value if isinstance(value, list) else [value]
        for v in values:
            if not isinstance(v, (int, float)) or isinstance(v, bool):
                self.error(f"{where}: not a number ({v!r})")
                return
            if abs(v / step - round(v / step)) > 1e-6 and not self.free_grid:
                text = f"{where}: {v} is off the {step} grid ({kind})"
                (self.warn if self.off_grid_allowed else self.error)(text)


def vec(value, size=3):
    return isinstance(value, list) and len(value) == size and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value)


# ---- geometry (level-local), the same convention as hazards.gd ----
def euler_basis(r):
    """Godot YXZ Euler order: R = Ry * Rx * Rz (angles in degrees), columns are the basis vectors."""
    x, y, z = (math.radians(a) for a in r)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return mat_mul(ry, mat_mul(rx, rz))


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def planes(b):
    k = b["k"]
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


def ray_down_hit(b, origin, offset=(0, 0, 0)):
    """Height (level-local y) of the first surface a vertical ray hits going down from `origin`, or None. `offset` shifts the block."""
    rot = euler_basis(b.get("r", [0, 0, 0]))
    inv = transpose(rot)
    centre = [b.get("p", [0, 0, 0])[i] + offset[i] for i in range(3)]
    o = mat_vec(inv, [origin[i] - centre[i] for i in range(3)])
    d = mat_vec(inv, [0, -1, 0])
    t_in, t_out = -math.inf, math.inf
    for n, c in planes(b):
        denom = sum(n[i] * d[i] for i in range(3))
        num = c - sum(n[i] * o[i] for i in range(3))
        if abs(denom) < 1e-9:
            if num < 0:
                return None
            continue
        t = num / denom
        if denom > 0:
            t_out = min(t_out, t)
        else:
            t_in = max(t_in, t)
    if b["k"] == "cyl":
        r = b.get("d", 1.0) / 2
        a = d[0] ** 2 + d[2] ** 2
        c = o[0] ** 2 + o[2] ** 2 - r * r
        if a < 1e-9:
            if c > 0:
                return None
        else:
            bb = 2 * (o[0] * d[0] + o[2] * d[2])
            disc = bb * bb - 4 * a * c
            if disc < 0:
                return None
            root = math.sqrt(disc)
            t_in = max(t_in, (-bb - root) / (2 * a))
            t_out = min(t_out, (-bb + root) / (2 * a))
    if t_in > t_out or t_out < 0:
        return None
    return origin[1] - max(t_in, 0.0)


def floor_under(blocks, point, reach=3.0):
    """(y, block) of the highest static surface at or below point.y + 0.5 within `reach` metres under the point, or (None, None)."""
    best, found = None, None
    start = [point[0], point[1] + 0.5, point[2]]
    for b in blocks:
        p, s = b.get("p", [0, 0, 0]), b.get("s", [1, 1, 1])
        near = math.sqrt(sum(c * c for c in s)) / 2 if b.get("k") != "cyl" else math.hypot(b.get("d", 1.0) / 2, b.get("h", 1.0) / 2)
        if abs(point[0] - p[0]) > near or abs(point[2] - p[2]) > near:   # a block's bounding sphere is far off the ray: skip the slab test
            continue
        y = ray_down_hit(b, start)
        if y is not None and start[1] - y <= reach + 0.5 and (best is None or y > best):
            best, found = y, b
    return best, found


def floor_below(blocks, point, reach=3.0):
    """Highest static surface at or below point.y + 0.5 within `reach` metres under the point."""
    return floor_under(blocks, point, reach)[0]


def inside_block(b, point, margin):
    """True when `point` lies within `margin` of block b (a box, a cylinder, a wedge's bounding box)."""
    local = mat_vec(transpose(euler_basis(b.get("r", [0, 0, 0]))), [point[i] - b.get("p", [0, 0, 0])[i] for i in range(3)])
    if b.get("k") == "cyl":
        return abs(local[1]) <= b.get("h", 1.0) / 2 + margin and math.hypot(local[0], local[2]) <= b.get("d", 1.0) / 2 + margin
    half = [c / 2 + margin for c in b.get("s", [1, 1, 1])]
    return all(abs(local[i]) <= half[i] for i in range(3))


def lint_support(rep, hazards, blocks):
    """Nothing hangs in the air: a swing's pivot is held by a block (a gantry, a lintel, a wall), a push pad or bumper (not riding a hazard) stands on a block top."""
    for i, h in enumerate(hazards):
        if not isinstance(h, dict) or not vec(h.get("p")):
            continue
        where = f"hazards[{i}] ({h.get('k')}{' ' + h['id'] if h.get('id') else ''})"
        if h.get("k") == "swing" and not any(inside_block(b, h["p"], PIVOT_REACH) for b in blocks):
            rep.error(f"{where}: the pivot {h['p']} hangs from nothing (put a block through it: a gantry beam, a lintel or a wall)")
        if h.get("k") in ("push", "bumper") and not h.get("ride"):
            half = h.get("rad", 1.0) if h["k"] == "bumper" else (h.get("s", [1, 1, 1])[1] if h.get("g", "box") == "box" else h.get("h", 1.0)) / 2
            if floor_below(blocks, [h["p"][0], h["p"][1] - half, h["p"][2]], reach=LAUNCHER_REACH) is None:
                rep.error(f"{where}: floats more than {LAUNCHER_REACH} m over any block (a pad is drawn on the floor under its volume, so put the volume on a block)")


def lint_survival_ground(rep, blocks):
    """A survival round has no permanent safe ground: the floor is the step tiles / blink tiles and nothing else. A `show: survival` level has no static
    block at all (unless it is an `arena`): every one is a ledge to stand on forever."""
    for i, b in enumerate(blocks):
        p = b.get("p", [0, 0, 0])
        rep.error(f"blocks[{i}]: a survival level has no static ground (a block at {p} is permanent safe ground; the floor is tiles or blink hazards)")


def kill_contains(volume, point):
    """True when `point` (level-local) is inside the kill volume {p, s, yaw}."""
    yaw = math.radians(volume.get("yaw", 0.0))
    dx, dy, dz = (point[0] - volume["p"][0], point[1] - volume["p"][1], point[2] - volume["p"][2])
    lx = math.cos(yaw) * dx - math.sin(yaw) * dz
    lz = math.sin(yaw) * dx + math.cos(yaw) * dz
    return abs(lx) <= volume["s"][0] / 2 and abs(dy) <= volume["s"][1] / 2 and abs(lz) <= volume["s"][2] / 2


def standing_tops(blocks, hazards):
    """[(label, [x, y, z])] sample points of the floors a courier can stand on: the top of every upright box (corners inset, edge middles, centre) and cylinder
    (centre), and of every rider lift / slide at both ends of its travel. Spots buried in another block are left out."""
    spots = []

    def add(label, block, offset=(0, 0, 0)):
        if block.get("k") == "wedge" or block.get("hit") or (vec(block.get("r")) and any(block["r"])):   # a hit block breaks the painting at a touch: nobody stands on it
            return
        p = [block.get("p", [0, 0, 0])[i] + offset[i] for i in range(3)]
        if block.get("k", "box") == "cyl":
            top, half = p[1] + block.get("h", 1.0) / 2, [0.0, 0.0]
        else:
            s = block.get("s", [1, 1, 1])
            top, half = p[1] + s[1] / 2, [max(s[0] / 2 - 0.3, 0.0), max(s[2] / 2 - 0.3, 0.0)]
        for fx in (-1, 0, 1):
            for fz in (-1, 0, 1):
                spots.append((label, [p[0] + fx * half[0], top, p[2] + fz * half[1]]))

    for i, b in enumerate(blocks):
        add(f"blocks[{i}]", b)
    for i, h in enumerate(hazards):
        if not isinstance(h, dict) or h.get("k") not in ("lift", "slide") or h.get("hit") or not vec(h.get("p")):
            continue
        travel = [0, h.get("rise", 4.0), 0] if h["k"] == "lift" else (h.get("to") if vec(h.get("to")) else [0, 0, 0])
        if h["k"] == "lift" and h.get("rise", 4.0) < 0:
            continue
        parts = h.get("parts") if isinstance(h.get("parts"), list) else [{"k": "box", "s": h.get("s", [1, 1, 1])}]
        for part in parts:
            if not isinstance(part, dict) or part.get("k", "box") not in ("box", "cyl"):
                continue
            local = part.get("p") if vec(part.get("p")) else [0, 0, 0]
            moved = dict(part, p=[h["p"][j] + local[j] for j in range(3)])
            for end, scale in (("bottom", 0.0), ("top", 1.0)):
                add(f"hazards[{i}] ({h['k']} {h.get('id', '')}) {end}", moved, [travel[j] * scale for j in range(3)])
    return [(label, point) for label, point in spots if not any(inside_block(b, [point[0], point[1] + 0.45, point[2]], 0.0) for b in blocks)]


def lint_kill_reach(rep, kill, blocks, hazards):
    """A kill volume must not touch a courier standing on a floor (the centre CENTRE_HEIGHT over the feet) nor one jumping up from it (+ JUMP_RISE): a
    jump or a lift's ride that ends in a kill volume throws the player back to a checkpoint (CROWN CLIMB's lift)."""
    if not kill:
        return
    seen = set()
    for label, point in standing_tops(blocks, hazards):
        for j, volume in enumerate(kill):
            if not isinstance(volume, dict) or not vec(volume.get("p")) or not vec(volume.get("s")):
                continue
            for rise, what in ((CENTRE_HEIGHT, "stands"), (CENTRE_HEIGHT + JUMP_RISE, "jumps")):
                key = (label, j, what)
                if key not in seen and kill_contains(volume, [point[0], point[1] + rise, point[2]]):
                    seen.add(key)
                    rep.error(f"kill[{j}]: reaches a courier that {what} on {label} (feet at {[round(c, 2) for c in point]}): a kill volume stays clear of every floor by CENTRE_HEIGHT {CENTRE_HEIGHT} m + a jump {JUMP_RISE} m")


# ---- item boxes (docs/level-format.md "Item boxes") ----
def part_reach(part):
    """Metres from a hazard's pivot to the farthest point of one of its parts (a sphere round the part, whatever the hazard turns or swings)."""
    offset = math.sqrt(sum(c * c for c in part["p"])) if vec(part.get("p")) else 0.0
    if part.get("k") == "cyl":
        return offset + math.hypot(part.get("d", 1.0) / 2, part.get("h", 1.0) / 2)
    return offset + math.sqrt(sum(c * c for c in part.get("s", [1, 1, 1]))) / 2


def hazard_shapes(h, hazards):
    """The shapes that together hold everything hazard `h` ever sweeps, for the item boxes' clearance: a hazard that turns or swings (`spin`, `swing`) is a sphere about its pivot
    round its parts; one that only stands or slides (`blink`, `lift`, `slide`, `push`, `fire`, `bumper`) is its parts' boxes and cylinders (a wedge: its bounding box) at its rest pose and at
    every metre of its travel; a ball its path points, a laser its reach, a cannon its range. Shapes: ("s", centre, radius), ("b", centre, basis, half sizes), ("c", centre, basis, radius, half height)."""
    if not isinstance(h, dict) or not vec(h.get("p")):
        return []
    k = h.get("k")
    parts = [part for part in h["parts"] if isinstance(part, dict)] if isinstance(h.get("parts"), list) and h["parts"] else None
    if parts is None:
        if vec(h.get("s")):
            parts = [{"k": "box", "s": h["s"]}]
        elif (k in ("push", "fire") and h.get("g") == "cyl") or (k == "fire" and "d" in h and "s" not in h):
            parts = [{"k": "cyl", "d": h.get("d", 1.0), "h": h.get("h", 1.0)}]
        elif k == "bumper":
            return [("s", list(h["p"]), h.get("rad", 1.0) + 0.1)]
        else:
            parts = [{"k": "box", "s": [1, 1, 1]}]
    if k == "laser":
        return [("s", list(h["p"]), math.sqrt(sum(c * c for c in (h["to"] if vec(h.get("to")) else [0, 0, 0]))) + (math.sqrt(sum(c * c for c in h["move"])) if vec(h.get("move")) else 0.0))]
    if k == "cannon":
        reach = math.hypot(h["v"][0], h["v"][2]) * h.get("life", 3.0) + 2 * h.get("rad", 0.5) if vec(h.get("v")) else 0.0
        return [("s", list(h["p"]), max(reach, max(part_reach(part) for part in parts)))]
    if k == "ball" and isinstance(h.get("path"), list):
        return [("s", list(q), h.get("rad", 1.0)) for q in h["path"] if vec(q)]
    host = next((o for o in hazards if isinstance(o, dict) and h.get("ride") and o.get("id") == h["ride"]), None)
    if host is not None:   # a launcher riding a mover: the mover's shapes as spheres, grown by where the launcher sits on it
        grow = math.sqrt(sum(c * c for c in h["p"])) + max(part_reach(part) for part in parts)
        return [("s", shape[1], (shape[2] if shape[0] == "s" else math.sqrt(sum(c * c for c in shape[3])) if shape[0] == "b" else math.hypot(shape[3], shape[4])) + grow) for shape in hazard_shapes(host, hazards)]
    if k in ("spin", "swing"):
        return [("s", list(h["p"]), max(part_reach(part) for part in parts))]
    travel = [0.0, 0.0, 0.0]
    if k == "slide" and vec(h.get("to")):
        travel = h["to"]
    elif k == "lift":
        travel = [0.0, h.get("rise", 4.0), 0.0]
    steps = max(1, math.ceil(math.sqrt(sum(c * c for c in travel))))
    base = euler_basis(h["r"]) if vec(h.get("r")) else euler_basis([0, 0, 0])
    shapes = []
    for part in parts:
        local = part["p"] if vec(part.get("p")) else [0, 0, 0]
        basis = mat_mul(base, euler_basis(part["r"] if vec(part.get("r")) else [0, 0, 0]))
        offset = mat_vec(base, local)
        for n in range(steps + 1):
            centre = [h["p"][i] + offset[i] + travel[i] * n / steps for i in range(3)]
            if part.get("k") == "cyl":
                shapes.append(("c", centre, basis, part.get("d", 1.0) / 2, part.get("h", 1.0) / 2))
            else:
                shapes.append(("b", centre, basis, [c / 2 for c in part.get("s", [1, 1, 1])]))
    return shapes


def shape_distance(shape, point):
    """Metres from `point` to the surface of a hazard shape (negative inside a sphere; 0 inside a box or cylinder)."""
    if shape[0] == "s":
        return math.dist(point, shape[1]) - shape[2]
    local = mat_vec(transpose(shape[2]), [point[i] - shape[1][i] for i in range(3)])
    if shape[0] == "b":
        return math.sqrt(sum(max(abs(local[i]) - shape[3][i], 0.0) ** 2 for i in range(3)))
    return math.hypot(max(math.hypot(local[0], local[2]) - shape[3], 0.0), max(abs(local[1]) - shape[4], 0.0))


def hazard_shape_list(hazards):
    """[(hazard, shape)] of every hazard's shapes (hazard_shapes)."""
    return [(h, shape) for h in hazards for shape in hazard_shapes(h, hazards)]


def kill_distance(volume, point):
    """Metres from `point` to the kill volume {p, s, yaw} (0 inside it)."""
    yaw = math.radians(volume.get("yaw", 0.0))
    dx, dy, dz = (point[0] - volume["p"][0], point[1] - volume["p"][1], point[2] - volume["p"][2])
    local = [math.cos(yaw) * dx - math.sin(yaw) * dz, dy, math.sin(yaw) * dx + math.cos(yaw) * dz]
    return math.sqrt(sum(max(abs(local[i]) - volume["s"][i] / 2, 0.0) ** 2 for i in range(3)))


def item_box_spots(row):
    """The feet spots [x, y, z] of the boxes of an `item_boxes` row (the twin of demo/levels/level_data.gd item_boxes)."""
    count, step, yaw = max(1, min(int(row.get("n", 1)), 4)), float(row.get("step", 1.8)), math.radians(float(row.get("yaw", 0.0)))
    along = [math.cos(yaw), 0.0, -math.sin(yaw)]
    return [[row["p"][i] + along[i] * step * (n - (count - 1) / 2) for i in range(3)] for n in range(count)]


def blocks_near(blocks, x, z, reach):
    """The blocks whose bounding sphere comes within `reach` m (horizontally) of (x, z): a cheap first cut before the slab tests."""
    out = []
    for b in blocks:
        p, size = b.get("p", [0, 0, 0]), b.get("s", [1, 1, 1])
        half = math.sqrt(sum(c * c for c in size)) / 2 if b.get("k") != "cyl" else math.hypot(b.get("d", 1.0) / 2, b.get("h", 1.0) / 2)
        if abs(p[0] - x) <= half + reach and abs(p[2] - z) <= half + reach:
            out.append(b)
    return out


def box_spot_problems(spot, blocks, hazards, kill, middle=False, shapes=None):
    """Why a box of an item row may not stand at `spot` (feet, level-local): [] when it may. `blocks` are the level's static blocks, `middle` tightens the floor height."""
    problems = []
    x, y, z = spot
    blocks = blocks_near(blocks, x, z, 2.0)
    floor_y, floor_block = floor_under(blocks, spot, reach=0.6)
    if floor_y is None:
        return ["no static floor under it (a mover or the air)"]
    tolerance = BOX_FLOOR_MIDDLE if middle else BOX_FLOOR_END
    if abs(floor_y - y) > tolerance:
        problems.append(f"the floor top is {floor_y:.2f} m, the spot is at {y:.2f} m (within {tolerance})")
    foot = [(x, z)] + [(x + r * math.cos(math.radians(a)), z - r * math.sin(math.radians(a)))
                       for r in (BOX_FOOT_RADIUS / 2, BOX_FOOT_RADIUS + BOX_FOOT_MARGIN) for a in range(0, 360, 30)]
    for fx, fz in foot:
        foot_y, block = floor_under(blocks, [fx, y, fz], reach=0.6)
        if foot_y is None or abs(foot_y - floor_y) > BOX_FOOT_FLAT:
            problems.append(f"the pedestal's foot is not on one flat floor (at {[round(fx, 2), round(fz, 2)]}: {'none' if foot_y is None else round(foot_y, 2)} against {floor_y:.2f})")
            break
        if block.get("m", "ground") != "ground" or block.get("hit"):
            problems.append(f"it stands on a {'hit' if block.get('hit') else block.get('m')} block (a box stands on plain static floor)")
            break
    if floor_block is not None and (floor_block.get("m", "ground") != "ground" or floor_block.get("hit")):
        problems.append(f"it stands on a {'hit' if floor_block.get('hit') else floor_block.get('m')} block (a box stands on plain static floor)")
    air = [(x, z)] + [(x + 0.75 * math.cos(math.radians(a)), z - 0.75 * math.sin(math.radians(a))) for a in range(0, 360, 45)]
    for lift in (0.3, 0.75, 1.3):
        if any(inside_block(b, [ax, floor_y + lift, az], BOX_CUBE_MARGIN) for ax, az in air for b in blocks):
            problems.append(f"a solid block is within {BOX_CUBE_MARGIN} m of the cube (height {lift} m)")
            break
    centre = [x, floor_y + 0.6, z]
    for h, shape in (shapes if shapes is not None else hazard_shape_list(hazards)):
        gap = shape_distance(shape, centre)
        if gap < BOX_HAZARD_CLEAR:
            problems.append(f"{h.get('k')} {h.get('id', '')} is {gap:.1f} m away (at least {BOX_HAZARD_CLEAR}: its parts at rest and along its travel, a sphere where it turns)".replace("  ", " "))
            break
    for j, volume in enumerate(kill):
        if isinstance(volume, dict) and vec(volume.get("p")) and vec(volume.get("s")) and kill_distance(volume, centre) < BOX_HAZARD_CLEAR:
            problems.append(f"kill[{j}] is {kill_distance(volume, centre):.1f} m away (at least {BOX_HAZARD_CLEAR})")
    if abs(x) > MAX_EXTENT or abs(z) > MAX_EXTENT or not Y_RANGE[0] <= y <= Y_RANGE[1]:
        problems.append(f"outside +-{MAX_EXTENT} m / y {Y_RANGE}")
    return problems


def lint_item_boxes(rep, data, blocks, hazards, kill):
    """`item_boxes` (docs/level-format.md): rows of boxes on a race show level, each box on flat static floor, clear of every hazard and kill volume."""
    rows = data.get("item_boxes")
    if rows is None:
        return
    if data.get("show") != "race":
        rep.error("item_boxes: only a race show level has item boxes")
        return
    if not isinstance(rows, list) or len(rows) > BOX_ROWS_MAX:
        rep.error(f"item_boxes: a list of at most {BOX_ROWS_MAX} rows {{p, n, step, yaw}}")
        return
    total = 0
    shapes = hazard_shape_list(hazards)
    for i, row in enumerate(rows):
        where = f"item_boxes[{i}]"
        if not isinstance(row, dict) or set(row) - {"p", "n", "step", "yaw"} or not vec(row.get("p")):
            rep.error(f"{where}: {{p: [x,y,z] the middle of the row on the floor, n: 1-4, step: {BOX_STEP[0]}-{BOX_STEP[1]}, yaw: degrees}}")
            continue
        n, step, yaw = row.get("n"), row.get("step", 1.8), row.get("yaw", 0.0)
        if isinstance(n, bool) or not isinstance(n, int) or not 1 <= n <= 4:
            rep.error(f"{where}.n: a whole number 1-4")
            continue
        if isinstance(step, bool) or not isinstance(step, (int, float)) or not BOX_STEP[0] <= step <= BOX_STEP[1]:
            rep.error(f"{where}.step: {BOX_STEP[0]}-{BOX_STEP[1]} m")
            continue
        if isinstance(yaw, bool) or not isinstance(yaw, (int, float)):
            rep.error(f"{where}.yaw: degrees")
            continue
        total += n
        spots = item_box_spots(row)
        middle = floor_under(blocks, row["p"], reach=0.6)[0]
        if middle is None or abs(middle - row["p"][1]) > BOX_FLOOR_MIDDLE:
            rep.error(f"{where}: the floor under the middle of the row {row['p']} is {'missing' if middle is None else round(middle, 2) + 0.0} (the row's p.y must be within {BOX_FLOOR_MIDDLE} m of it)")
        for index, spot in enumerate(spots):
            for problem in box_spot_problems(spot, blocks, hazards, kill, shapes=shapes):
                rep.error(f"{where} box {index} at {[round(c, 2) for c in spot]}: {problem}")
    if total > BOXES_MAX:
        rep.error(f"item_boxes: {total} boxes (at most {BOXES_MAX})")


# ---- pictures against floors (docs/level-format.md "Pictures and floors") ----
def aligned_extent(basis, centre, size):
    """World (lo, hi) of a box whose basis only turns it by multiples of 90 degrees, else None."""
    if any(min(abs(c), abs(abs(c) - 1.0)) > 1e-6 for row in basis for c in row):
        return None
    half = [sum(abs(basis[i][k]) * size[k] for k in range(3)) / 2 for i in range(3)]
    return [centre[i] - half[i] for i in range(3)], [centre[i] + half[i] for i in range(3)]


def floor_extents(blocks):
    """[(index, lo, hi)] of the static boxes a courier walks on: upright (a turn of 90 degrees about y is fine), not `hit`, at least FLOOR_SPAN across both ways
    or RAIL_SPAN across and at most RAIL_HEIGHT tall (a tall wall or a post is not a floor). Cylinders, wedges and tilted boxes are left out."""
    out = []
    for i, b in enumerate(blocks):
        if b.get("k", "box") != "box" or b.get("hit") or not vec(b.get("p")) or not vec(b.get("s")) or not vec(b.get("r", [0, 0, 0])):
            continue
        extent = aligned_extent(euler_basis(b.get("r", [0, 0, 0])), b["p"], b["s"])
        if extent is None:
            continue
        span = min(extent[1][0] - extent[0][0], extent[1][2] - extent[0][2])
        if span < FLOOR_SPAN and not (span >= RAIL_SPAN and extent[1][1] - extent[0][1] <= RAIL_HEIGHT):
            continue
        out.append((i, extent[0], extent[1]))
    return out


def picture_face_hits(centre, basis, size, floors, skip=None):
    """[(floor index, 'coplanar' | 'cut', face)] for the faces an obstacle box wears (its four sides and its top, each PICTURE_LIFT off the box):
    `coplanar`: the face lies in one plane with a floor's face of the same direction (within COPLANAR_TOL) and overlaps it: the picture and the floor fight
    over the pixels; `cut`: a floor's volume covers part of the face and not all of it: the picture runs into the floor. A face buried whole (against
    the end of the neighbouring slab) is not seen and passes."""
    hits = []
    extent = aligned_extent(basis, centre, size)
    names = ("+x", "-x", "+y", "-y", "+z", "-z")
    down = [-basis[i][1] for i in range(3)]  # local bottom: no picture there
    if extent is not None:
        lo, hi = extent
        for axis in range(3):
            for sign in (1, -1):
                name = names[axis * 2 + (0 if sign > 0 else 1)]
                if abs(down[axis] - sign) < 1e-6:
                    continue
                plane = hi[axis] if sign > 0 else lo[axis]
                t1, t2 = [a for a in range(3) if a != axis]
                area = (hi[t1] - lo[t1]) * (hi[t2] - lo[t2])
                for index, flo, fhi in floors:
                    if index == skip:
                        continue
                    overlap = 1.0
                    for t in (t1, t2):
                        overlap *= max(0.0, min(hi[t], fhi[t]) - max(lo[t], flo[t]))
                    if overlap < 1e-6:
                        continue
                    fplane = fhi[axis] if sign > 0 else flo[axis]
                    if abs(fplane - plane) <= COPLANAR_TOL:
                        hits.append((index, "coplanar", name))
                    elif flo[axis] - PICTURE_SLACK <= plane + sign * PICTURE_LIFT <= fhi[axis] + PICTURE_SLACK and overlap < area - 1e-6:
                        hits.append((index, "cut", name))
        return hits
    # a tilted box (a swinging hammer head): sample every face
    reach = math.sqrt(sum(c * c for c in size)) / 2 + PICTURE_LIFT + PICTURE_SLACK  # only floors this near the box can touch it
    boxes = [(index, {"k": "box", "p": [(flo[t] + fhi[t]) / 2 for t in range(3)], "s": [fhi[t] - flo[t] for t in range(3)]}) for index, flo, fhi in floors
             if all(flo[t] - reach <= centre[t] <= fhi[t] + reach for t in range(3))]
    faces = (([1, 0, 0], [0, 0, -1], [0, 1, 0]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]), ([0, 1, 0], [1, 0, 0], [0, 0, -1]),
             ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [-1, 0, 0], [0, 1, 0]))
    for n, u, v in faces:
        width = abs(sum(u[k] * size[k] for k in range(3)))
        height = abs(sum(v[k] * size[k] for k in range(3)))
        inside = {}
        for gi in range(SAMPLES):
            for gj in range(SAMPLES):
                a, b = (gi + 0.5) / SAMPLES - 0.5, (gj + 0.5) / SAMPLES - 0.5
                local = [n[k] * (abs(n[k]) * size[k] / 2 + PICTURE_LIFT) + u[k] * a * width + v[k] * b * height for k in range(3)]
                world = mat_vec(basis, local)
                point = [centre[k] + world[k] for k in range(3)]
                for index, fb in boxes:
                    if index != skip and inside_block(fb, point, PICTURE_SLACK):
                        inside[index] = inside.get(index, 0) + 1
        for index, count in inside.items():
            if count < SAMPLES * SAMPLES:
                hits.append((index, "cut", "tilted " + str(n)))
    return hits


def hazard_picture_poses(h):
    """[(part, centre, basis)] of each obstacle-slot box of a hazard at the poses worth testing: rest, a slide's or lift's travel in quarters, a swing's
    whole arc, a spin's quarter turns. `spikes` hide under the floor on purpose and are not tested."""
    if h.get("k") == "spikes" or not vec(h.get("p")):
        return []
    base = euler_basis(h["r"]) if vec(h.get("r")) else euler_basis([0, 0, 0])
    parts = h["parts"] if isinstance(h.get("parts"), list) else ([{"k": "box", "s": h["s"], "slot": h.get("slot")}] if vec(h.get("s")) else [])
    moves = [([0.0, 0.0, 0.0], base)]
    if h["k"] in ("slide", "lift"):
        travel = [0.0, h.get("rise", 4.0), 0.0] if h["k"] == "lift" else (h["to"] if vec(h.get("to")) else [0.0, 0.0, 0.0])
        moves = [([travel[j] * f / 4 for j in range(3)], base) for f in range(5)]
    elif h["k"] in ("swing", "spin"):
        axis = {"x": 0, "y": 1, "z": 2}.get(h.get("axis", "y"), 1)
        if h["k"] == "swing":
            angles = [h.get("a0", -60.0) + (h.get("a1", 60.0) - h.get("a0", -60.0)) * f / SWING_STEPS for f in range(SWING_STEPS + 1)]
        else:
            angles = [a * 90.0 for a in range(4)]
        moves = []
        for angle in angles:
            turn = [0, 0, 0]
            turn[axis] = angle
            moves.append(([0.0, 0.0, 0.0], mat_mul(base, euler_basis(turn))))
    out = []
    for part in parts:
        if not isinstance(part, dict) or part.get("slot") not in OBSTACLE_SLOTS or part.get("k", "box") != "box" or not vec(part.get("s")):
            continue
        local = part["p"] if vec(part.get("p")) else [0.0, 0.0, 0.0]
        for move, basis in moves:
            offset = mat_vec(basis, local)
            out.append((part, [h["p"][j] + move[j] + offset[j] for j in range(3)], mat_mul(basis, euler_basis(part["r"] if vec(part.get("r")) else [0, 0, 0]))))
    return out


def lint_picture_floors(rep, slots, blocks, hazards):
    """Picture faces never merge with a floor: an obstacle box (a block, a hazard part, a mover's `s` box at every tested pose) may not wear a picture on a
    face that is coplanar with a floor's face or cut by a floor (`picture_face_hits`), and a board in `slots` may not be cut by one."""
    floors = floor_extents(blocks)
    for i, b in enumerate(blocks):
        if b.get("slot") in OBSTACLE_SLOTS and b.get("k", "box") == "box" and vec(b.get("p")) and vec(b.get("s")) and vec(b.get("r", [0, 0, 0])):
            for index, what, face in sorted(set(picture_face_hits(b["p"], euler_basis(b.get("r", [0, 0, 0])), b["s"], floors, skip=i))):
                rep.error(f"blocks[{i}]: the picture on its {face} face is {what} with the floor blocks[{index}] ({PICTURE_FACE_HELP[what]})")
    for i, h in enumerate(hazards):
        if not isinstance(h, dict):
            continue
        seen = set()
        for part, centre, basis in hazard_picture_poses(h):
            for index, what, face in picture_face_hits(centre, basis, part["s"], floors):
                if (id(part), index, what, face) not in seen:
                    seen.add((id(part), index, what, face))
                    rep.error(f"hazards[{i}] ({h.get('k')} {h.get('id', '')}): the picture on a box's {face} face is {what} with the floor blocks[{index}] "
                              f"({PICTURE_FACE_HELP[what]}) when it stands at {[round(c, 2) for c in centre]}")
    for i, slot in enumerate(slots):
        if not isinstance(slot, dict) or slot.get("id") in BOARD_FREE or not vec(slot.get("p")) or not vec(slot.get("size"), 2):
            continue
        basis = euler_basis([0, slot.get("yaw", 0), 0])
        size = [slot["size"][0], slot["size"][1], BOARD_DEPTH]
        extent = aligned_extent(basis, slot["p"], size)
        for index, flo, fhi in floors:
            if extent is not None:
                cut = all(min(extent[1][t], fhi[t]) - max(extent[0][t], flo[t]) > 1e-6 for t in range(3))
            else:
                floor_box = {"k": "box", "p": [(flo[t] + fhi[t]) / 2 for t in range(3)], "s": [fhi[t] - flo[t] for t in range(3)]}
                cut = False
                for gi in range(SAMPLES):
                    for gj in range(SAMPLES):
                        local = [(gi + 0.5) / SAMPLES * size[0] - size[0] / 2, (gj + 0.5) / SAMPLES * size[1] - size[1] / 2, 0.0]
                        world = mat_vec(basis, local)
                        cut = cut or inside_block(floor_box, [slot["p"][t] + world[t] for t in range(3)], 0.0)
            if cut:
                rep.error(f"slots[{i}] ({slot.get('id')}): the board at {slot['p']} is cut by the floor blocks[{index}] (a board stands on a floor, it does not sink into it)")


def lint_floor_tops(rep, blocks):
    """Two floor blocks whose tops are in one plane and overlap fight over the pixels (a dashed line along the overlap): trim one so the tops only touch."""
    floors = floor_extents(blocks)
    for a in range(len(floors)):
        for c in range(a + 1, len(floors)):
            (i, lo_a, hi_a), (j, lo_b, hi_b) = floors[a], floors[c]
            if abs(hi_a[1] - hi_b[1]) > COPLANAR_TOL:
                continue
            ox = min(hi_a[0], hi_b[0]) - max(lo_a[0], lo_b[0])
            oz = min(hi_a[2], hi_b[2]) - max(lo_a[2], lo_b[2])
            if ox > 1e-6 and oz > 1e-6:
                rep.error(f"blocks[{i}] and blocks[{j}]: floor tops at y {hi_a[1]} overlap by {round(ox, 3)} x {round(oz, 3)} m (coplanar tops z-fight: let the tops only touch)")


BELT_SPEED = (0.5, 8.0)  # m/s: the length of a belt's [vx, vz] (courier/courier_motion.gd carries a courier at it)


def lint_belt(rep, where, b):
    """`m: belt` (a conveyor, docs/level-format.md "Conveyor belts"): `belt` [vx, vz] level-local m/s on the 0.5 grid, its length BELT_SPEED, on an upright
    box (a turn about y of 0 / 90 / 180 / 270 degrees) that is not `hit`; `belt` belongs to `m: belt` blocks only."""
    if b.get("m", "ground") != "belt":
        if "belt" in b:
            rep.error(f"{where}: belt belongs to blocks with m belt")
        return
    if b.get("k", "box") != "box":
        rep.error(f"{where}: a belt is a box (k box)")
    if b.get("hit"):
        rep.error(f"{where}: a belt is a floor: it cannot be hit")
    turn = b.get("r", [0, 0, 0])
    if vec(turn) and (turn[0] % 360 != 0 or turn[2] % 360 != 0 or turn[1] % 90 != 0):
        rep.error(f"{where}: a belt is upright and turned about y by 0, 90, 180 or 270 degrees (r {turn})")
    belt = b.get("belt")
    if not vec(belt, 2):
        rep.error(f"{where}: m belt needs belt [vx, vz] (level-local m/s)")
        return
    rep.grid(f"{where}.belt", belt, "speed")
    speed = math.hypot(belt[0], belt[1])
    if not BELT_SPEED[0] <= speed <= BELT_SPEED[1]:
        rep.error(f"{where}: belt {belt} runs at {speed:.2f} m/s (from {BELT_SPEED[0]} to {BELT_SPEED[1]})")


SLIME_ANGLE_MAX = 20.0  # degrees: the steepest slope a slime wedge may have (the courier's floor limit is 55)


def lint_slime(rep, where, b):
    """`m: slime` (docs/level-format.md "Slime slopes"): a wedge (k wedge) that is not `hit`, turned about y by 0 / 90 / 180 / 270 degrees only, at most SLIME_ANGLE_MAX steep.
    Its downhill is the wedge's low edge; every courier on it is pushed that way (courier/courier_motion.gd SLIME)."""
    if b.get("m", "ground") != "slime":
        return
    if b.get("k", "box") != "wedge":
        rep.error(f"{where}: slime is a wedge (k wedge): the slope is the surface")
        return
    if b.get("hit"):
        rep.error(f"{where}: slime is a floor: it cannot be hit")
    turn = b.get("r", [0, 0, 0])
    if vec(turn) and (turn[0] % 360 != 0 or turn[2] % 360 != 0 or turn[1] % 90 != 0):
        rep.error(f"{where}: a slime wedge is turned about y by 0, 90, 180 or 270 degrees only (r {turn})")
    s = b.get("s")
    if vec(s) and s[1] > 0 and s[2] > 0:
        angle = math.degrees(math.atan2(s[1], s[2]))
        if angle > SLIME_ANGLE_MAX:
            rep.error(f"{where}: slime slope {angle:.1f} degrees is steeper than {SLIME_ANGLE_MAX}")


def lint_block(rep, where, b, part=False, hazard=None):
    if not isinstance(b, dict):
        rep.error(f"{where}: not an object")
        return False
    keys = (PART_KEYS | {"tone"} if hazard in PART_TONE_KINDS else PART_KEYS | {"bump"} if hazard == "spin" else PART_KEYS) if part else BLOCK_KEYS
    for key in b:
        if key not in keys:
            rep.error(f"{where}: unknown key '{key}'")
    k = b.get("k", "box")
    if k not in ("box", "cyl", "wedge"):
        rep.error(f"{where}: unknown block kind '{k}'")
        return False
    if not vec(b.get("p")):
        rep.error(f"{where}: needs p [x,y,z]")
        return False
    rep.grid(f"{where}.p", b["p"], "pos")
    if "r" in b:
        if not vec(b["r"]):
            rep.error(f"{where}: r must be [x,y,z] degrees")
        else:
            rep.grid(f"{where}.r", b["r"], "angle")
    if k == "cyl":
        for key in ("d", "h"):
            if not isinstance(b.get(key), (int, float)) or b[key] < 0.25:
                rep.error(f"{where}: cyl needs {key} >= 0.25")
            else:
                rep.grid(f"{where}.{key}", b[key], "pos")
    else:
        if not vec(b.get("s")) or min(b["s"]) < 0.25:
            rep.error(f"{where}: needs s [w,h,d] with every size >= 0.25")
            return False
        rep.grid(f"{where}.s", b["s"], "pos")
    if not part:
        if b.get("m", "ground") not in ("ground", "ice", "belt", "slime"):
            rep.error(f"{where}: m must be ground, ice, belt or slime")
        lint_belt(rep, where, b)
        lint_slime(rep, where, b)
        if "hit" in b and not isinstance(b["hit"], bool):
            rep.error(f"{where}: hit must be true/false")
    if "slot" in b:
        lint_slot(rep, where, b, part)
    if "tone" in b and (not part or hazard in PART_TONE_KINDS):
        if not rep.daylight:
            rep.error(f"{where}: tone only on a level with \"world\": \"daylight\"")
        elif b["tone"] not in TONES:
            rep.error(f"{where}: tone must be one of {', '.join(TONES)}")
    return True


def lint_slot(rep, where, b, part=False):
    """`slot` on a block or hazard part: an obstacle box (its faces show that cast slot), or hero_prop on a static cylinder (a stand tier)."""
    if not isinstance(b["slot"], str) or (b["slot"] not in OBSTACLE_SLOTS and b["slot"] not in (GATE_SLOT, HERO_SLOT)):
        rep.error(f"{where}: slot '{b['slot']}' must be one of obstacle_1..5 (or gate on the start gate, hero_prop on a stand's cylinders)")
    elif b["slot"] == HERO_SLOT:
        if part or b.get("k", "box") != "cyl":
            rep.error(f"{where}: slot hero_prop belongs to static cylinder blocks (k cyl), the tiers of a hero prop's stand")
    elif b.get("k", "box") != "box":
        rep.error(f"{where}: slot belongs to boxes (k box)")


def ridden_hazard(slot, hazards):
    """The hazard a door slot rides (its `ride` id), None when it stands still or the id names no hazard."""
    if not slot.get("ride"):
        return None
    return next((h for h in hazards if isinstance(h, dict) and h.get("id") == slot["ride"]), None)


def door_geometry(slot):
    """(turn, normal (nx, nz), right (rx, rz)) of a door slot: turn 0 faces +Z, 1 +X, 2 -Z, 3 -X."""
    turn = int(round(slot.get("yaw", 0) / 90.0)) % 4
    nx, nz = [(0, 1), (1, 0), (0, -1), (-1, 0)][turn]
    return turn, (nx, nz), (nz, -nx)


def lint_doors(rep, slots, blocks, hazards):
    """A poster door (an obstacle slot with `door`): `solid` (a problem poster, a wall) has a static box block exactly as wide as the board whose front face stands
    DOOR_BLOCK_GAP behind its plane and reaches from the floor to at least 2 m (the courier's push-back and the wobble are measured from that face);
    `open` and `torn` (the logo poster) have no block anywhere in their opening. A door with `ride` moves with that `slide` hazard (no `hit`, no turn, a travel along
    its row): the hazard's parts at the hazard's rest pose stand where the static blocks would, and the door's p is its place at that rest pose."""
    for i, slot in enumerate(slots):
        if not isinstance(slot, dict) or "door" not in slot or not vec(slot.get("p")) or not vec(slot.get("size"), 2):
            continue
        x, y, z = slot["p"]
        width, height = slot["size"]
        turn, (nx, nz), (rx, rz) = door_geometry(slot)
        around = blocks
        if slot.get("ride"):
            ride = ridden_hazard(slot, hazards)
            if ride is None or ride.get("k") != "slide":
                rep.error(f"slots[{i}]: ride '{slot['ride']}' is not the id of a slide hazard")
                continue
            if ride.get("hit") or vec(ride.get("r")) and any(ride["r"]) or not vec(ride.get("p")) or not vec(ride.get("to")) \
                    or abs(ride["to"][0] * nx + ride["to"][2] * nz) > 1e-6 or abs(ride["to"][1]) > 1e-6:
                rep.error(f"slots[{i}]: the slide '{slot['ride']}' a door rides has no hit, no turn and travels along its row (to across the board, level)")
                continue
            around = blocks + [dict(part, p=[ride["p"][t] + (part["p"][t] if vec(part.get("p")) else 0.0) for t in range(3)])
                               for part in ride.get("parts", []) if isinstance(part, dict) and part.get("k", "box") == "box" and vec(part.get("s"))]
        behind, wide = None, None
        for b in around:
            if b.get("k", "box") != "box" or not vec(b.get("p")) or not vec(b.get("s")):
                continue
            bx, by, bz = b["p"]
            sx, sy, sz = b["s"]
            along = (bx - x) * nx + (bz - z) * nz   # along the board's normal
            across = (bx - x) * rx + (bz - z) * rz  # across the board
            depth = abs(sx * nx) + abs(sz * nz)
            span = abs(sx * rx) + abs(sz * rz)
            if abs(along) - depth / 2 < 1.0 and abs(across) < width / 2 and by - sy / 2 < y + height / 2 and by + sy / 2 > y - height / 2 + 0.1:
                if slot["door"] == "solid" and abs(along + DOOR_BLOCK_GAP + depth / 2) < 0.01 and abs(across) < 0.01 and abs(span - width) < 0.01 \
                        and by - sy / 2 <= y - height / 2 + 0.01 and by + sy / 2 >= 2.0:
                    behind = b
                elif along < 0.0 and along + depth / 2 > -0.4 and slot["door"] != "solid":
                    wide = b
        if slot["door"] == "solid" and behind is None:
            rep.error(f"slots[{i}]: solid door at {slot['p']} has no hidden block {DOOR_BLOCK_GAP} m behind its board (as wide as the board, from the floor up)")
        if slot["door"] != "solid" and wide is not None:
            rep.error(f"slots[{i}]: {slot['door']} door at {slot['p']} has a block in its opening")
        if slot["door"] != "solid" and width < DOOR_MIN_WIDTH:
            rep.error(f"slots[{i}]: the {slot['door']} (logo) door at {slot['p']} is {width} m wide, at least {DOOR_MIN_WIDTH} m so that a courier fits through it")


def lint_door_rows(rep, slots, blocks, hazards):
    """The rows of a level's poster doors (doors on one plane): every row has a logo poster (an `open` or `torn` door), the row nearest the start has exactly one
    and at least four problem posters (the idea shown once) and the level's only `torn` door, and a row that rides a slide rides ONE slide of at most RIDE_PERIOD_MAX
    seconds. At every pose of the row (the slide's travel in eighths) the posters seal the hall between its walls apart from the logo poster's opening and slits
    narrower than SLIT_MAX (a courier is 0.7 m across), and the logo poster's opening stays inside the hall: a moving row is never closed for good and never
    leaves a way round."""
    rows = {}
    for i, slot in enumerate(slots):
        if isinstance(slot, dict) and "door" in slot and vec(slot.get("p")) and vec(slot.get("size"), 2) and slot.get("yaw", 0) % 90 == 0:
            turn, (nx, nz), (rx, rz) = door_geometry(slot)
            rows.setdefault((turn, round(slot["p"][0] * nx + slot["p"][2] * nz, 2)), []).append((i, slot))
    if not rows:
        return
    first = min(rows, key=lambda key: abs(key[1]))
    torn = [i for key, row in rows.items() for i, slot in row if slot["door"] == "torn"]
    for key, row in sorted(rows.items(), key=lambda item: abs(item[0][1])):
        turn, plane = key
        _, (nx, nz), (rx, rz) = door_geometry(row[0][1])
        where = f"door row at {plane} m"
        logos = [(i, s) for i, s in row if s["door"] != "solid"]
        if not logos:
            rep.error(f"{where}: no logo poster (an open or torn door): the row could not be passed")
        if key == first and (len(logos) != 1 or len(row) - len(logos) < FIRST_ROW_PROBLEMS):
            rep.error(f"{where}: the first row has exactly one logo poster among at least {FIRST_ROW_PROBLEMS} problem posters ({len(logos)} logo, {len(row) - len(logos)} problem)")
        if key != first and any(i in torn for i, _ in row):
            rep.error(f"{where}: only a door of the first row starts torn")
        rides = {s.get("ride") for _, s in row}
        if len(rides) > 1:
            rep.error(f"{where}: its doors ride {len(rides)} different slides (or some ride and some stand): a row is one thing")
            continue
        ride = ridden_hazard(row[0][1], hazards)
        if rides == {None} or ride is None:
            ride_to = None
        else:
            if float(ride.get("period", 0)) > RIDE_PERIOD_MAX:
                rep.error(f"{where}: the slide '{ride.get('id')}' takes {ride.get('period')} s a round trip, at most {RIDE_PERIOD_MAX} s (the opening must come round soon)")
            ride_to = ride.get("to") if vec(ride.get("to")) else None
        walls = door_walls(blocks, plane, (nx, nz), (rx, rz))
        if walls is None:
            rep.error(f"{where}: no tall wall block on each side of the row (the posters are sealed against the hall's walls)")
            continue
        low, high = walls
        left_hall, slit = False, False
        for step in range(RIDE_STEPS + 1):
            f = step / RIDE_STEPS if ride_to is not None else 0.0
            shift = (ride_to[0] * rx + ride_to[2] * rz) * f if ride_to is not None else 0.0
            solid, opening = [], []
            for _, s in row:
                centre = s["p"][0] * rx + s["p"][2] * rz + shift
                (solid if s["door"] == "solid" else opening).append((centre - s["size"][0] / 2, centre + s["size"][0] / 2))
            for lo, hi in opening:
                if (lo < low - 1e-6 or hi > high + 1e-6) and not left_hall:
                    left_hall = True
                    rep.error(f"{where}: the logo poster's opening ({lo:.2f} .. {hi:.2f}) leaves the hall ({low:.2f} .. {high:.2f}) at {f:.3f} of the slide's travel")
            run, worst, at = 0.0, 0.0, low
            x = low
            while x <= high + 1e-9:
                covered = any(lo - 1e-6 <= x <= hi + 1e-6 for lo, hi in solid + opening)
                run = 0.0 if covered else run + SEAL_STEP
                if run > worst:
                    worst, at = run, x
                x += SEAL_STEP
            if worst >= SLIT_MAX and not slit:
                slit = True
                rep.error(f"{where}: a {worst:.2f} m slit at {at:.2f} (across the hall) when the row is at {f:.3f} of the slide's travel: no poster covers it, a courier could walk round")


def door_walls(blocks, plane, normal, right):
    """(low, high): the inner faces of the tall wall blocks (at least 4 m tall) that stand on `plane` (of the normal's axis) either side of a row, as coordinates
    across the row; None when a side has none. The nearest wall to the middle of the hall on each side."""
    nx, nz = normal
    rx, rz = right
    low, high = -math.inf, math.inf
    for b in blocks:
        if b.get("k", "box") != "box" or not vec(b.get("p")) or not vec(b.get("s")) or b["s"][1] < 4.0:
            continue
        depth = abs(b["s"][0] * nx) + abs(b["s"][2] * nz)
        if abs(b["p"][0] * nx + b["p"][2] * nz - plane) > depth / 2:
            continue
        centre = b["p"][0] * rx + b["p"][2] * rz
        half = (abs(b["s"][0] * rx) + abs(b["s"][2] * rz)) / 2
        if centre < 0:
            low = max(low, centre + half)
        else:
            high = min(high, centre - half)
    return None if low == -math.inf or high == math.inf else (low, high)


def lint_goal_decals(rep, slots, goal):
    """The `floor_finish` decal lies on the GOAL pad, which is painted at the goal box's floor point: its centre is the goal's centre (XZ), else the logo
    sits off the pad's centre (the arch over the goal stands on the same line)."""
    for i, slot in enumerate(slots):
        if not isinstance(slot, dict) or slot.get("id") != "floor_finish" or not vec(slot.get("p")):
            continue
        off = math.dist([slot["p"][0], slot["p"][2]], [goal["p"][0], goal["p"][2]])
        if off > FINISH_DECAL_REACH:
            rep.error(f"slots[{i}]: floor_finish is {off:.2f} m off the goal pad's centre (goal x {goal['p'][0]}, z {goal['p'][2]}): put its p at the goal's x / z so the logo lies centred on the pad")


def lint_hero_stands(rep, slots, blocks):
    """A hero_prop slot (p = bottom centre, size = [footprint, height]) stands on three static cylinders tagged "slot": "hero_prop": tier i is
    footprint * HERO_SHARES[i] across and a third of the height tall, one on top of the other, centred under p. A tagged cylinder that is no
    tier of a hero_prop slot is an error (its look is not drawn)."""
    tagged = [b for b in blocks if b.get("slot") == HERO_SLOT and b.get("k") == "cyl"]
    used = set()
    for slot in slots:
        if not isinstance(slot, dict) or slot.get("id") != HERO_SLOT or not vec(slot.get("p")) or not vec(slot.get("size"), 2):
            continue
        (x, y, z), (width, height) = slot["p"], slot["size"]
        for tier, share in enumerate(HERO_SHARES):
            want = [x, y + height / 3 * (tier + 0.5), z, width * share, height / 3]
            found = next((i for i, b in enumerate(tagged) if all(math.isclose(a, c, abs_tol=0.01) for a, c in zip(b["p"] + [b["d"], b["h"]], want))), None)
            if found is None:
                rep.error(f"hero_prop at {slot['p']}: no cylinder block with slot hero_prop for tier {tier + 1} (p {[round(v, 3) for v in want[:3]]}, d {want[3]:g}, h {want[4]:g})")
            else:
                used.add(found)
    for i, b in enumerate(tagged):
        if i not in used:
            rep.error(f"block {b['p']}: a cylinder with slot hero_prop that is no tier of a hero_prop slot")


def number(rep, where, h, key, lo, hi, kind=None, default=None):
    value = h.get(key, default)
    if value is None:
        rep.error(f"{where}: missing '{key}'")
        return None
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        rep.error(f"{where}.{key}: not a number")
        return None
    if not lo <= value <= hi:
        rep.error(f"{where}.{key}: {value} outside {lo}..{hi}")
    if kind:
        rep.grid(f"{where}.{key}", value, kind)
    return value


def lint_hazard(rep, where, h, ids):
    k = h.get("k")
    if k not in KINDS:
        rep.error(f"{where}: unknown hazard kind '{k}'")
        return
    for key in h:
        if key not in HAZARD_KEYS[k]:
            rep.error(f"{where}: key '{key}' does not belong to '{k}'")
    if "id" in h:
        if not isinstance(h["id"], str) or not h["id"]:
            rep.error(f"{where}: id must be a non-empty string")
        elif h["id"] in ids:
            rep.error(f"{where}: duplicate id '{h['id']}'")
        ids.add(h["id"])
    if k not in ("ball",) and not vec(h.get("p")):
        rep.error(f"{where}: needs p [x,y,z]")
    elif "p" in h:
        rep.grid(f"{where}.p", h["p"], "pos")
    if "r" in h and vec(h["r"]):
        rep.grid(f"{where}.r", h["r"], "angle")
    if "phase" in h:
        number(rep, where, h, "phase", 0, 60, "time")
    if "hit" in h and not isinstance(h["hit"], bool):
        rep.error(f"{where}: hit must be true/false")
    movers = {"slide", "lift", "spin", "swing", "blink", "spikes"}
    if "slot" in h:
        if "parts" in h:
            rep.error(f"{where}: slot belongs on the parts (or on a hazard with s), not on a hazard with parts")
        elif k not in movers:
            rep.error(f"{where}: key 'slot' does not belong to '{k}'")
        else:
            lint_slot(rep, where, {"slot": h["slot"]})
    if k in movers:
        parts = h.get("parts")
        if parts is None:
            if not vec(h.get("s")):
                rep.error(f"{where}: needs parts [...] or s [w,h,d]")
            else:
                rep.grid(f"{where}.s", h["s"], "pos")
        elif not isinstance(parts, list) or not parts:
            rep.error(f"{where}: parts must be a non-empty list")
        else:
            for i, part in enumerate(parts):
                lint_block(rep, f"{where}.parts[{i}]", part, part=True, hazard=k)
    if "look" in h and h["look"] != "spikes":
        rep.error(f"{where}: look must be \"spikes\"")
    period_kinds = {"slide": (1, 30), "lift": (2, 30), "swing": (1, 20)}
    if k in ("slide", "lift", "swing"):
        lo, hi = period_kinds[k]
        period = number(rep, where, h, "period", lo, hi, "time")
        pause = number(rep, where, h, "pause", 0, 10, "time", default=0.0 if k != "lift" else 1.0)
        hold = pause
        if "hold" in h:
            if k != "lift":
                rep.error(f"{where}: hold belongs to lift")
            else:
                hold = number(rep, where, h, "hold", 0, 20, "time", default=pause)
        if period is not None and pause is not None and hold is not None and period <= pause + hold:
            rep.error(f"{where}: period {period} must be above pause + hold ({pause + hold})")
        if h.get("ease", "sine") not in ("sine", "linear"):
            rep.error(f"{where}: ease must be sine or linear")
    if k == "slide":
        if not vec(h.get("to")):
            rep.error(f"{where}: slide needs to [dx,dy,dz]")
        else:
            rep.grid(f"{where}.to", h["to"], "pos")
            if math.dist(h["to"], [0, 0, 0]) < 0.5:
                rep.error(f"{where}: slide offset is shorter than 0.5 m")
    if k == "lift":
        number(rep, where, h, "rise", -40, 40, "pos")
    if k == "spin":
        if h.get("axis", "y") not in ("x", "y", "z"):
            rep.error(f"{where}: axis must be x, y or z")
        rate = number(rep, where, h, "rate", -SPIN_RATE_MAX, SPIN_RATE_MAX, "angle")
        if rate == 0:
            rep.error(f"{where}: rate 0 is no spinner")
    if k == "swing":
        if h.get("axis", "x") not in ("x", "y", "z"):
            rep.error(f"{where}: axis must be x, y or z")
        a0 = number(rep, where, h, "a0", -180, 180, "angle")
        a1 = number(rep, where, h, "a1", -180, 180, "angle")
        if a0 is not None and a1 is not None and abs(a1 - a0) < 10:
            rep.error(f"{where}: a0 and a1 are less than 10 degrees apart")
    if k == "blink":
        on = number(rep, where, h, "on", 0.5, BLINK_ON_MAX, "time")
        number(rep, where, h, "off", BLINK_OFF_MIN, BLINK_OFF_MAX, "time")
        warn = number(rep, where, h, "warn", 0, 5, "time", default=1.0)
        if on is not None and warn is not None and warn > on:
            rep.error(f"{where}: warn {warn} is longer than on {on}")
    if k == "spikes":
        number(rep, where, h, "rise", 0.5, 6, "pos", default=2.5)
        period = number(rep, where, h, "period", 0, 20, "time", default=0.0)
        up = number(rep, where, h, "up", 0.25, 10, "time", default=1.0)
        warn = number(rep, where, h, "warn", 0, 3, "time", default=0.5)
        if period and up is not None and warn is not None and period < warn + up + 1.0:
            rep.error(f"{where}: period {period} is shorter than warn + up + 1 ({warn + up + 1.0})")
    if k in ("push", "bumper"):
        if h.get("ride") is not None and not isinstance(h["ride"], str):
            rep.error(f"{where}: ride must be an id")
    if k == "push":
        g = h.get("g", "box")
        if g == "box":
            if not vec(h.get("s")) or min(h["s"]) < 0.25:
                rep.error(f"{where}: box push needs s [w,h,d]")
            else:
                rep.grid(f"{where}.s", h["s"], "pos")
        elif g == "cyl":
            number(rep, where, h, "d", 0.5, 10, "pos")
            number(rep, where, h, "h", 0.25, 10, "pos")
        else:
            rep.error(f"{where}: g must be box or cyl")
        if not vec(h.get("v")):
            rep.error(f"{where}: push needs v [vx,vy,vz] in m/s")
        else:
            rep.grid(f"{where}.v", h["v"], "speed")
            if max(abs(c) for c in h["v"]) > 36:
                rep.error(f"{where}: launch component above 36 m/s")
    if k == "bumper":
        number(rep, where, h, "rad", 0.5, 4, "pos")
        number(rep, where, h, "kick", 0, 15, "speed", default=7.5)
        number(rep, where, h, "up", 0, 30, "speed", default=15.0)
    if k == "ball":
        path = h.get("path")
        if not isinstance(path, list) or len(path) < 2 or not all(vec(p) for p in path):
            rep.error(f"{where}: ball needs path [[x,y,z], ...] (2 or more)")
        else:
            for p in path:
                rep.grid(f"{where}.path", p, "pos")
            length = sum(math.dist(path[i], path[i + 1]) for i in range(len(path) - 1))
            speed = number(rep, where, h, "speed", 1, 15, "speed", default=4.0)
            period = number(rep, where, h, "period", 1, 30, "time", default=8.0)
            if speed and period and period < length / speed:
                rep.error(f"{where}: period {period} is shorter than the roll ({length / speed:.2f} s)")
        number(rep, where, h, "rad", 0.5, 3, "pos", default=1.0)
    if k == "laser":
        to = h.get("to")
        if not vec(to):
            rep.error(f"{where}: laser needs to [dx,dy,dz] (the beam from p)")
        else:
            rep.grid(f"{where}.to", to, "pos")
            if not 0.5 <= math.dist(to, [0, 0, 0]) <= 40:
                rep.error(f"{where}: the beam must be 0.5 to 40 m long")
        if "move" in h:
            if not vec(h["move"]):
                rep.error(f"{where}: move must be [dx,dy,dz]")
            else:
                rep.grid(f"{where}.move", h["move"], "pos")
                if math.dist(h["move"], [0, 0, 0]) < 0.5:
                    rep.error(f"{where}: move is shorter than 0.5 m")
            period = number(rep, where, h, "period", 1, 30, "time")
            pause = number(rep, where, h, "pause", 0, 10, "time", default=0.0)
            if period is not None and pause is not None and period <= 2 * pause:
                rep.error(f"{where}: period {period} must be above 2 * pause ({2 * pause})")
            if h.get("ease", "sine") not in ("sine", "linear"):
                rep.error(f"{where}: ease must be sine or linear")
        else:
            for key in ("period", "pause", "ease"):
                if key in h:
                    rep.error(f"{where}: '{key}' belongs to a laser that moves (move)")
        if "rate" in h:
            if h.get("axis", "y") not in ("x", "y", "z"):
                rep.error(f"{where}: axis must be x, y or z")
            if number(rep, where, h, "rate", -90, 90, "angle") == 0:
                rep.error(f"{where}: rate 0 is no spinning laser")
        elif "axis" in h:
            rep.error(f"{where}: 'axis' belongs to a laser that spins (rate)")
        lint_schedule(rep, where, h, 0.5)
    if k == "fire":
        g = h.get("g", "box")
        if g == "box":
            if not vec(h.get("s")) or min(h["s"]) < 0.25:
                rep.error(f"{where}: box fire needs s [w,h,d]")
            else:
                rep.grid(f"{where}.s", h["s"], "pos")
                if max(h["s"]) > 20:
                    rep.error(f"{where}: fire larger than 20 m")
        elif g == "cyl":
            number(rep, where, h, "d", 0.5, 10, "pos")
            number(rep, where, h, "h", 0.5, 20, "pos")
        else:
            rep.error(f"{where}: g must be box or cyl")
        lint_schedule(rep, where, h, 1.0)
    if k == "cannon":
        if not vec(h.get("v")):
            rep.error(f"{where}: cannon needs v [vx,vy,vz]")
        else:
            rep.grid(f"{where}.v", h["v"], "speed")
        number(rep, where, h, "rad", 0.25, 2, "pos", default=0.5)
        period = number(rep, where, h, "period", 1, 30, "time", default=4.0)
        life = number(rep, where, h, "life", 0.5, 10, "time", default=3.0)
        if period is not None and life is not None and life > period:
            rep.error(f"{where}: life {life} is longer than period {period}")


def lint_schedule(rep, where, h, default_warn):
    """on / off / warn of a laser or fire jet: both on and off, or neither (always on); warn is the end of off."""
    if ("on" in h) != ("off" in h):
        rep.error(f"{where}: give on and off together (or neither: always on)")
        return
    if "on" not in h:
        if "warn" in h:
            rep.error(f"{where}: warn needs on and off")
        return
    number(rep, where, h, "on", 0.5, 20, "time")
    off = number(rep, where, h, "off", 0.5, 20, "time")
    warn = number(rep, where, h, "warn", 0, 5, "time", default=default_warn)
    if off is not None and warn is not None and warn > off:
        rep.error(f"{where}: warn {warn} is longer than off {off}")


def box_points(volume):
    p, s = volume["p"], volume["s"]
    return [[p[0] + dx * s[0] / 2, p[1] + dy * s[1] / 2, p[2] + dz * s[2] / 2] for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]


def blink_blocks(hazards):
    """The boxes of unrotated blink hazards at their pivot (solid at level time 0): a survival round starts its players on falling tiles."""
    out = []
    for h in hazards:
        if not isinstance(h, dict) or h.get("k") != "blink" or not vec(h.get("p")) or (vec(h.get("r")) and any(h["r"])):
            continue
        parts = h.get("parts") if isinstance(h.get("parts"), list) else [{"k": "box", "s": h.get("s")}]
        for part in parts:
            if isinstance(part, dict) and part.get("k", "box") in ("box", "cyl", "wedge") and not (vec(part.get("r")) and any(part["r"])):
                local = part.get("p") if vec(part.get("p")) else [0, 0, 0]
                block = dict(part, k=part.get("k", "box"), p=[h["p"][i] + local[i] for i in range(3)])
                if block["k"] == "cyl" or vec(block.get("s")):
                    out.append(block)
    return out


def lint_tiles(rep, data):
    """`tiles`: floors of hexagonal step tiles (docs/level-format.md "Step tiles"). Returns the tiles as level-local boxes {k, p, s} (the walking
    surface is the top): the box is the widest rectangle inside the hexagon, so the start and path checks never count ground that is not there."""
    tiles = data.get("tiles")
    out = []
    if tiles is None:
        return out
    if not isinstance(tiles, dict) or set(tiles) - {"pitch", "thick", "kinds", "floors", "fit", "grid", "style", "wrap", "orient"}:
        rep.error("tiles: {pitch, thick, kinds, floors, fit, grid, style, wrap, orient}")
        return out
    grid = tiles.get("grid", "hex")
    if grid not in TILE_GRIDS:
        rep.error(f"tiles.grid: one of {', '.join(TILE_GRIDS)}")
        return out
    square = grid == "square"
    flat = tiles.get("orient", "pointy") == "flat"
    if tiles.get("orient", "pointy") not in ("pointy", "flat") or (square and "orient" in tiles):
        rep.error("tiles.orient: \"pointy\" or \"flat\", a hexagon grid only")
    if tiles.get("style", "") not in ("", "stage"):
        rep.error("tiles.style: \"stage\" or nothing")
    if not isinstance(tiles.get("wrap", False), bool):
        rep.error("tiles.wrap: true or false")
    pitch = number(rep, "tiles", tiles, "pitch", 1, 6 if tiles.get("style") == "stage" else 4, "pos", default=2.5)
    thick = number(rep, "tiles", tiles, "thick", 0.25, 2, "pos", default=0.5)
    kinds = tiles.get("kinds")
    if not isinstance(kinds, dict) or not kinds:
        rep.error("tiles.kinds: {<one character>: {delay, look, slot}}")
        return out
    for key, kind in kinds.items():
        where = f"tiles.kinds['{key}']"
        if len(key) != 1 or key in ". ":
            rep.error(f"{where}: a kind is one character (not '.' or a space)")
        if not isinstance(kind, dict) or set(kind) - {"delay", "look", "slot", "raise", "tone"}:
            rep.error(f"{where}: {{delay, look, slot, raise, tone}}")
            continue
        number(rep, where, kind, "delay", 0.25, 10, "time")
        number(rep, where, kind, "raise", 0, 2, "pos", default=0.0)
        if "tone" in kind and not (isinstance(kind["tone"], str) and len(kind["tone"]) == 7 and kind["tone"][0] == "#" and all(c in "0123456789abcdefABCDEF" for c in kind["tone"][1:])):
            rep.error(f"{where}.tone: a colour as #rrggbb")
        look = kind.get("look", "plain")
        if look not in TILE_LOOKS:
            rep.error(f"{where}: look must be one of {', '.join(TILE_LOOKS)}")
        if look == "obstacle" and kind.get("slot") not in OBSTACLE_SLOTS:
            rep.error(f"{where}: an obstacle tile names its slot (obstacle_1..5)")
        if look != "obstacle" and "slot" in kind:
            rep.error(f"{where}: slot belongs to the obstacle look")
    floors = tiles.get("floors")
    if not isinstance(floors, list) or not floors or len(floors) > MAX_TILE_FLOORS:
        rep.error(f"tiles.floors: 1..{MAX_TILE_FLOORS} floors {{y, origin, rows}}")
        return out
    tops = []
    for i, floor in enumerate(floors):
        where = f"tiles.floors[{i}]"
        if not isinstance(floor, dict) or set(floor) - {"y", "origin", "rows", "tone"} or not isinstance(floor.get("rows"), list) or not floor["rows"]:
            rep.error(f"{where}: {{y, origin: [x, z], rows: [text, ...]}}")
            continue
        y = number(rep, where, floor, "y", STAGE_DEPTH if tiles.get("style") == "stage" else -40, 80, "pos", default=0.0)
        origin = floor.get("origin", [0, 0])
        if not vec(origin, 2):
            rep.error(f"{where}.origin: [x, z]")
            continue
        rep.grid(f"{where}.origin", origin, "pos")
        if "tone" in floor and not (isinstance(floor["tone"], str) and len(floor["tone"]) == 7 and floor["tone"][0] == "#" and all(c in "0123456789abcdefABCDEF" for c in floor["tone"][1:])):
            rep.error(f"{where}.tone: a colour as #rrggbb")
        rows = floor["rows"]
        width = len(rows[0]) if isinstance(rows[0], str) else 0
        if width == 0 or any(not isinstance(r, str) or len(r) != width for r in rows):
            rep.error(f"{where}.rows: strings of one length ({'a character per tile' if square else 'a character per half tile width'}, a space or '.' for none)")
            continue
        if pitch is None or thick is None or y is None:
            continue
        tops.append(y)
        for ri, row in enumerate(rows):
            for ci, ch in enumerate(row):
                if ch in ". ":
                    continue
                if ch not in kinds:
                    rep.error(f"{where}.rows[{ri}]: '{ch}' is not a kind")
                    continue
                if not square and (ci + ri) % 2:
                    rep.error(f"{where}.rows[{ri}]: '{ch}' at column {ci} is off the hexagon grid (column + row must be even: a neighbour in the row is 2 columns on, in the next row 1)")
                    continue
                x = origin[0] + (ci - (width - 1) / 2) * (pitch if square else pitch / 2)
                z = origin[1] + (ri - (len(rows) - 1) / 2) * (pitch if square else pitch * HEX_ROW)
                if flat:
                    x, z = z, x
                if abs(x) > MAX_EXTENT or abs(z) > MAX_EXTENT:
                    rep.error(f"{where}: tile at [{x}, {z}] outside +-{MAX_EXTENT} m")
                    continue
                top = y + (kinds[ch].get("raise", 0.0) if isinstance(kinds[ch], dict) else 0.0)
                out.append({"k": "box", "p": [x, top - thick / 2, z], "s": [pitch / math.sqrt(3) if flat else pitch, thick, pitch if square or flat else pitch / math.sqrt(3)], "raised": top > y})
    limit = MAX_STAGE_TILES if tiles.get("style") == "stage" else MAX_TILES
    if len(out) > limit:
        rep.error(f"tiles: {len(out)} tiles (at most {limit}: one state byte each, in state pieces of 240 B)")
    tops.sort()
    gap_least = TILE_STAGE_FLOOR_GAP if tiles.get("style") == "stage" else TILE_FLOOR_GAP
    for a, b in zip(tops, tops[1:]):
        if b - a < gap_least or (thick is not None and b - a < thick * 2):
            rep.error(f"tiles.floors: floors at y {a} and {b} are less than {max(gap_least, (thick or 0) * 2)} m apart")
    fit = tiles.get("fit", [])
    last = 0
    if not isinstance(fit, list):
        rep.error("tiles.fit: a list of {players, radius}")
        fit = []
    for i, entry in enumerate(fit):
        where = f"tiles.fit[{i}]"
        if not isinstance(entry, dict) or set(entry) != {"players", "radius"}:
            rep.error(f"{where}: {{players, radius}}")
            continue
        players = entry["players"]
        if not isinstance(players, int) or isinstance(players, bool) or not last < players <= 10:
            rep.error(f"{where}.players: a whole number above the entry before it, at most 10")
        else:
            last = players
        number(rep, where, entry, "radius", 1, 40, "pos")
    return out


def lint_stage(rep, data, tile_boxes):
    """`stage` (docs/level-format.md "Stage rounds"): a survival round on stacked tile layers over a permanent ground, inside an enclosure. It needs `tiles` with `"style": "stage"` and
    `"wrap": true` (rounds of up to STAGE_CAP_MAX s of level clock), and is a `show: survival` level; `cap` is the round's own time cap; `starts` are the pads' middles (a
    tile top each: the players are seated on them in order); `ground` is the floor under the last layer, one layer gap under it, wider than the tiles, with every kill volume and `void_y` under it."""
    stage = data.get("stage")
    if stage is None:
        if isinstance(data.get("tiles"), dict) and data["tiles"].get("style") == "stage":
            rep.error("tiles.style \"stage\" belongs to a level with a `stage` section")
        return
    if not isinstance(stage, dict) or set(stage) - {"enclosure", "cap", "starts", "ground"}:
        rep.error("stage: {enclosure, cap, starts, ground}")
        return
    if stage.get("enclosure", "a") not in STAGE_ENCLOSURES:
        rep.error(f"stage.enclosure: one of {', '.join(STAGE_ENCLOSURES)}")
    number(rep, "stage", stage, "cap", 30, STAGE_CAP_MAX, "time", default=140.0)
    tiles = data.get("tiles")
    if not isinstance(tiles, dict) or tiles.get("style") != "stage" or tiles.get("wrap") is not True:
        rep.error("stage: the level's `tiles` need \"style\": \"stage\" and \"wrap\": true")
    if data.get("show") != "survival":
        rep.error("stage: a stage round is a `show: survival` level")
    starts = stage.get("starts")
    if not isinstance(starts, list) or not 1 <= len(starts) <= MAX_STAGE_STARTS or not all(vec(p) for p in starts):
        rep.error(f"stage.starts: 1..{MAX_STAGE_STARTS} spots [x, y, z] (the top of the tile each player starts on)")
    else:
        for i, p in enumerate(starts):
            top = floor_below(tile_boxes, p, reach=0.25)
            if top is None or abs(top - p[1]) > 0.05:
                rep.error(f"stage.starts[{i}]: no tile top at {p} (the spot is the top of the tile the player stands on)")
            for j in range(i):
                if math.dist([p[0], p[2]], [starts[j][0], starts[j][2]]) < STAGE_START_GAP:
                    rep.error(f"stage.starts[{i}]: less than {STAGE_START_GAP} m from stage.starts[{j}]")
    ground = stage.get("ground")
    if not isinstance(ground, dict) or set(ground) - {"y", "thick", "centre", "size", "tone"} or not vec(ground.get("size"), 2) or "y" not in ground:
        rep.error("stage.ground: {y, thick, centre: [x, z], size: [x, z], tone}")
        return
    y = number(rep, "stage.ground", ground, "y", STAGE_DEPTH, 0, "pos")
    thick = number(rep, "stage.ground", ground, "thick", 0.5, 10, "pos", default=2.0)
    centre = ground.get("centre", [0.0, 0.0])
    if not vec(centre, 2):
        rep.error("stage.ground.centre: [x, z]")
        return
    if "tone" in ground and not (isinstance(ground["tone"], str) and len(ground["tone"]) == 7 and ground["tone"][0] == "#" and all(c in "0123456789abcdefABCDEF" for c in ground["tone"][1:])):
        rep.error("stage.ground.tone: a colour as #rrggbb")
    if y is None or thick is None or not isinstance(tiles, dict) or not isinstance(tiles.get("floors"), list):
        return
    levels = sorted((f["y"] for f in tiles["floors"] if isinstance(f, dict) and isinstance(f.get("y"), (int, float))), reverse=True)
    if levels:
        if y > levels[-1] - TILE_STAGE_FLOOR_GAP:
            rep.error(f"stage.ground.y: {y} is not at least {TILE_STAGE_FLOOR_GAP} m under the last floor ({levels[-1]})")
        elif len(levels) > 1 and abs((levels[-1] - y) - (levels[-2] - levels[-1])) > 0.011:
            rep.error(f"stage.ground.y: {y} is not one layer gap ({levels[-2] - levels[-1]:.2f} m) under the last floor ({levels[-1]})")
    for box in tile_boxes:
        if abs(box["p"][0] - centre[0]) + box["s"][0] / 2 > ground["size"][0] / 2 + 1e-6 or abs(box["p"][2] - centre[1]) + box["s"][2] / 2 > ground["size"][1] / 2 + 1e-6:
            rep.error(f"stage.ground: the tile at {box['p']} lies over the ground's edge (a faller would miss it)")
            break
    bottom = y - thick
    void = data.get("void_y")
    if isinstance(void, (int, float)) and void > bottom - 1.0:
        rep.error(f"void_y: {void} is not at least 1 m under the ground's underside ({bottom}); nothing may kill before the ground")
    for i, volume in enumerate(data.get("kill", [])):
        if isinstance(volume, dict) and vec(volume.get("p")) and vec(volume.get("s")) and volume["p"][1] + volume["s"][1] / 2 > bottom + 1e-6:
            rep.error(f"kill[{i}]: reaches {volume['p'][1] + volume['s'][1] / 2}, over the ground's underside ({bottom}); nothing may kill before the ground")



def lint_level(path, expected_number):
    rep = Report(path.name)
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        rep.error(f"not valid JSON: {exc}")
        return rep
    if not isinstance(data, dict):
        rep.error("top level must be an object")
        return rep
    rep.off_grid_allowed = bool(str(data.get("note", "")).strip())
    rep.daylight = data.get("world") == "daylight"
    rep.free_grid = isinstance(data.get("stage"), dict)  # a stage round is generated (tools/stage_levels_gen.py): its numbers follow its own tile pitch, not the hand-authoring grid
    for key in data:
        if key not in TOP_KEYS:
            rep.error(f"unknown top-level key '{key}'")
    if data.get("format") != "level-1":
        rep.error("format must be 'level-1'")
    if data.get("number") != expected_number:
        rep.error(f"number {data.get('number')} does not match the file name ({expected_number})")
    title = data.get("title")
    if not isinstance(title, str) or not title or len(title) > 24 or title != title.upper():
        rep.error("title: upper case text, 1..24 characters")
    if "pool" in data and not isinstance(data["pool"], bool):
        rep.error("pool: true or false")
    if "blurb" in data and (not isinstance(data["blurb"], str) or len(data["blurb"]) > 80):
        rep.error("blurb: text up to 80 characters")
    for key in ("rule", "hint"):
        if key in data and (not isinstance(data[key], str) or not data[key] or len(data[key]) > TEXT_MAX or data[key] != data[key].upper()):
            rep.error(f"{key}: upper case text, 1..{TEXT_MAX} characters (the round card's goal line / the first seconds' objective hint)")
        elif key in data and "show" not in (data.get("modes") or []):
            rep.error(f"{key}: only a show level has one")
    start, goal = data.get("start"), data.get("goal")
    if not isinstance(start, dict) or start.get("p") != [0, 0, 0] or not isinstance(start.get("yaw", 0), (int, float)):
        rep.error("start: {p: [0,0,0], yaw}")
    else:
        rep.grid("start.yaw", start.get("yaw", 0), "angle")
    if not isinstance(goal, dict) or not vec(goal.get("p")) or not vec(goal.get("s")):
        rep.error("goal: {p: [x,y,z] centre, s: [w,h,d], yaw}")
        return rep
    rep.grid("goal.p", goal["p"], "pos")
    rep.grid("goal.s", goal["s"], "pos")
    rep.grid("goal.yaw", goal.get("yaw", 0), "angle")
    if min(goal["s"]) < 2.0:
        rep.error("goal.s: every size at least 2 m")
    if "void_y" in data:
        number(rep, "void_y", data, "void_y", STAGE_DEPTH if isinstance(data.get("stage"), dict) else -40, 0, "pos")
    path_points = data.get("path")
    if not isinstance(path_points, list) or len(path_points) < 3 or not all(vec(p) for p in path_points):
        rep.error("path: at least 3 waypoints [x,y,z]")
        path_points = []
    for p in path_points:
        rep.grid("path", p, "pos")
    kill = data.get("kill", [])
    if not isinstance(kill, list):
        rep.error("kill: a list")
        kill = []
    for i, volume in enumerate(kill):
        if not isinstance(volume, dict) or not vec(volume.get("p")) or not vec(volume.get("s")):
            rep.error(f"kill[{i}]: {{p, s, yaw}}")
            continue
        rep.grid(f"kill[{i}].p", volume["p"], "pos")
        rep.grid(f"kill[{i}].s", volume["s"], "pos")
        rep.grid(f"kill[{i}].yaw", volume.get("yaw", 0), "angle")
    if not kill and "void_y" not in data:
        rep.warn("no kill volumes: only the default void (-10 m) kills")
    modes = data.get("modes", ["carry"])
    if not isinstance(modes, list) or not modes or any(m not in MODES for m in modes) or len(set(modes)) != len(modes):
        rep.error(f"modes: a non-empty list from {sorted(MODES)}")
    is_show = isinstance(modes, list) and "show" in modes
    if "show" in data:
        if data["show"] not in SHOW_KINDS:
            rep.error(f"show: one of {', '.join(SHOW_KINDS)}")
        elif not is_show:
            rep.error("show: the level must list 'show' in modes")
    elif is_show:
        rep.error(f"show: a show level names its round ({', '.join(SHOW_KINDS)})")
    if is_show and data.get("pool") is not False:
        rep.error("pool: show levels carry \"pool\": false")
    for key in ("arena", "solo"):
        if key in data and not isinstance(data[key], bool):
            rep.error(f"{key}: true or false")
    if data.get("arena") and data.get("show") != "survival":
        rep.error("arena: only a survival show level may be an arena (static ground it stands on, the hazards and the shrinking decide)")
    if "play" in data and (data["play"] not in PLAYS or data.get("show") != "survival"):
        rep.error(f"play: one of {', '.join(PLAYS)}, on a survival show level")
    if "solo" in data and not is_show:
        rep.error("solo: only a show level has one")
    if "camera" in data and (data["camera"] != "stage" or not is_show):
        rep.error("camera: \"stage\", on a show level")
    if "cap" in data and (not is_show or data.get("show") != "race" or isinstance(data["cap"], bool)
                          or not isinstance(data["cap"], (int, float)) or not 60 <= data["cap"] <= 600):
        rep.error("cap: seconds (60-600), on a race show level")
    if "world" in data and (data["world"] not in WORLDS or not is_show):
        rep.error(f"world: one of {', '.join(WORLDS)}, on a show level")
    podium = data.get("podium")
    if podium is None:
        if data.get("show") == "final":
            rep.error(f"podium: {PODIUM_SPOTS} spots [[x,y,z], ...] are required on the final level")
    elif not isinstance(podium, list) or len(podium) != PODIUM_SPOTS or not all(vec(p) for p in podium):
        rep.error(f"podium: exactly {PODIUM_SPOTS} points [[x,y,z], ...] (1st, 2nd, 3rd)")
    else:
        for i, p in enumerate(podium):
            rep.grid(f"podium[{i}]", p, "pos")
            if abs(p[0]) > MAX_EXTENT or abs(p[2]) > MAX_EXTENT or not Y_RANGE[0] <= p[1] <= Y_RANGE[1]:
                rep.error(f"podium[{i}]: {p} outside +-{MAX_EXTENT} m / y {Y_RANGE}")
    checkpoints = data.get("checkpoints", [])
    if not isinstance(checkpoints, list):
        rep.error("checkpoints: a list")
        checkpoints = []
    for i, volume in enumerate(checkpoints):
        if not isinstance(volume, dict) or not vec(volume.get("p")) or not vec(volume.get("s")) or set(volume) - {"p", "s", "yaw"}:
            rep.error(f"checkpoints[{i}]: {{p, s, yaw}}")
            continue
        rep.grid(f"checkpoints[{i}].p", volume["p"], "pos")
        rep.grid(f"checkpoints[{i}].s", volume["s"], "pos")
        rep.grid(f"checkpoints[{i}].yaw", volume.get("yaw", 0), "angle")
        if min(volume["s"]) < 2.0:
            rep.error(f"checkpoints[{i}].s: every size at least 2 m")
    cues = data.get("cues", [])
    if "cues" in data and data.get("show") != "survival":
        rep.error("cues: only a survival show level has cues")
    if not isinstance(cues, list) or len(cues) > MAX_CUES:
        rep.error(f"cues: a list of at most {MAX_CUES} {{t, until, slot}}")
        cues = []
    last_until = 0.0
    for i, cue in enumerate(cues):
        if not isinstance(cue, dict) or set(cue) != {"t", "until", "slot"} or cue.get("slot") not in OBSTACLE_SLOTS \
                or not all(isinstance(cue.get(k), (int, float)) and not isinstance(cue.get(k), bool) for k in ("t", "until")):
            rep.error(f"cues[{i}]: {{t, until (level clock s), slot: obstacle_1..5}}")
            continue
        rep.grid(f"cues[{i}].t", cue["t"], "time")
        rep.grid(f"cues[{i}].until", cue["until"], "time")
        if not 0 <= cue["t"] < cue["until"] or cue["t"] < last_until:
            rep.error(f"cues[{i}]: 0 <= t < until, and after the cue before it")
        last_until = cue["until"]
    slots = data.get("slots", [])
    if not isinstance(slots, list):
        rep.error("slots: a list")
        slots = []
    slot_ids = set()
    for i, slot in enumerate(slots):
        if not isinstance(slot, dict) or set(slot) - {"id", "p", "yaw", "size", "door", "ride"} or not vec(slot.get("p")) or not vec(slot.get("size"), 2):
            rep.error(f"slots[{i}]: {{id, p: [x,y,z], yaw, size: [w,h]}}")
            continue
        if "door" in slot and (slot["door"] not in DOOR_KINDS or slot.get("id") not in OBSTACLE_SLOTS or slot.get("yaw", 0) % 90 != 0):
            rep.error(f"slots[{i}]: door is one of {', '.join(DOOR_KINDS)} on an obstacle slot facing along an axis")
        if "ride" in slot and ("door" not in slot or not isinstance(slot["ride"], str) or not slot["ride"]):
            rep.error(f"slots[{i}]: ride is the id of a slide hazard, on a poster door")
        if slot.get("id") not in SLOT_IDS:
            rep.error(f"slots[{i}]: id '{slot.get('id')}' is not a slot id (docs/level-format.md \"slots\")")
        elif slot["id"] in slot_ids and slot["id"] not in OBSTACLE_SLOTS and slot["id"] != HERO_SLOT:
            rep.error(f"slots[{i}]: id '{slot['id']}' used twice")
        slot_ids.add(slot.get("id"))
        rep.grid(f"slots[{i}].p", slot["p"], "pos")
        rep.grid(f"slots[{i}].size", slot["size"], "pos")
        rep.grid(f"slots[{i}].yaw", slot.get("yaw", 0), "angle")
        if min(slot["size"]) < 0.5:
            rep.error(f"slots[{i}].size: at least 0.5 m each way")
    if len(slots) > MAX_SLOTS:
        rep.error(f"{len(slots)} slots (at most {MAX_SLOTS}; only obstacle_1..5 and hero_prop may repeat)")
    blocks = data.get("blocks")
    hazards = data.get("hazards", [])
    if not isinstance(blocks, list) or (not blocks and data.get("show") != "survival"):  # a survival level's floor is its tiles: it may have no block
        rep.error("blocks: a non-empty list (a survival show level may have an empty one)")
        return rep
    if len(blocks) > MAX_BLOCKS:
        rep.error(f"{len(blocks)} blocks (at most {MAX_BLOCKS})")
    if not isinstance(hazards, list) or len(hazards) > MAX_HAZARDS:
        rep.error(f"hazards: a list of at most {MAX_HAZARDS}")
        hazards = []
    good = []
    for i, b in enumerate(blocks):
        if lint_block(rep, f"blocks[{i}]", b):
            good.append(b)
            b.setdefault("k", "box")
    lint_hero_stands(rep, slots, good)
    lint_goal_decals(rep, slots, goal)
    lint_doors(rep, slots, good, hazards)
    lint_door_rows(rep, slots, good, hazards)
    ids = set()
    for i, h in enumerate(hazards):
        if isinstance(h, dict):
            lint_hazard(rep, f"hazards[{i}] ({h.get('k')})", h, ids)
        else:
            rep.error(f"hazards[{i}]: not an object")
    lint_support(rep, hazards, good)
    shot_plan.lint_shots(rep, hazards, good)
    if is_show:
        lint_picture_floors(rep, slots, good, hazards)
        lint_floor_tops(rep, good)
        lint_kill_reach(rep, kill, good, hazards)
    lint_item_boxes(rep, data, good, hazards, kill)
    if data.get("show") == "survival" and not data.get("arena"):
        lint_survival_ground(rep, good)
    for i, h in enumerate(hazards):
        if isinstance(h, dict) and h.get("ride") and h["ride"] not in ids:
            rep.error(f"hazards[{i}]: ride '{h['ride']}' is not the id of a hazard")
    if data.get("show") in ("race", "final") and not any(
            isinstance(h, dict) and h.get("k") == "blink" and h.get("id") == "gate" and isinstance(h.get("on"), (int, float)) and h["on"] >= 3
            for h in hazards):
        rep.warn("show: a race or final level has no start gate (a blink hazard with id \"gate\" and on >= 3)")
    tile_boxes = lint_tiles(rep, data)
    lint_stage(rep, data, tile_boxes)
    # extent
    points = list(path_points) + box_points(goal) + [b["p"] for b in good] + [h["p"] for h in hazards if isinstance(h, dict) and vec(h.get("p"))]
    for p in points:
        if abs(p[0]) > MAX_EXTENT or abs(p[2]) > MAX_EXTENT or not Y_RANGE[0] <= p[1] <= Y_RANGE[1]:
            rep.error(f"point {p} outside +-{MAX_EXTENT} m / y {Y_RANGE}")
            break
    # support under start and goal
    start_blinks = blink_blocks(hazards) if data.get("show") == "survival" else []
    if data.get("arena"):   # a pedestal standing on the floor (bottom at y 0 or above, top over 0) is not the floor: the check looks under it
        start_blinks = [b for b in start_blinks if not (b["p"][1] - (b.get("h", 1.0) if b["k"] == "cyl" else b.get("s", [1, 1, 1])[1]) / 2 >= -0.05
                                                        and b["p"][1] + (b.get("h", 1.0) if b["k"] == "cyl" else b.get("s", [1, 1, 1])[1]) / 2 > 0.05)]
    start_support = good + [b for b in tile_boxes if not b.get("raised")] + start_blinks  # a raised tile (a spawn pad) is not the plain ground the start check looks for
    for x in ((0.0,) if isinstance(data.get("stage"), dict) else (-1.75, 0.0, 1.75)):  # a stage round's players start on pads (stage.starts): the origin must be plain top floor
        y = floor_below(start_support, [x, 0.0, 0.0], reach=0.5)
        if y is None or abs(y) > 0.05:
            rep.error(f"start: no ground top at y 0 under [{x}, 0, 0]")
            break
    goal_floor = [goal["p"][0], goal["p"][1] - goal["s"][1] / 2, goal["p"][2]]
    support = floor_below(good, goal_floor, reach=1.0)
    if data.get("show") == "survival":
        pass  # a survival round never reads the goal (the last tiles decide): it needs no floor
    elif support is None:
        movers = [h for h in hazards if isinstance(h, dict) and h.get("k") in ("lift", "slide") and vec(h.get("p"))]
        if not any(math.dist([m["p"][0], m["p"][2]], [goal_floor[0], goal_floor[2]]) < 6 for m in movers):
            rep.error(f"goal: no static floor within 1 m under the goal floor point {goal_floor}")
    elif abs(support - goal_floor[1]) > 1.0:
        rep.warn(f"goal: the floor under the goal box is {support}, the box floor is {goal_floor[1]}")
    # path
    if path_points:
        if math.dist(path_points[0], [0, 0, 0]) > 3.0:
            rep.error("path: the first waypoint must be within 3 m of the start [0,0,0]")
        last = path_points[-1]
        inside = all(abs(last[i] - goal["p"][i]) <= goal["s"][i] / 2 + 0.01 for i in range(3)) if goal.get("yaw", 0) in (0, 180, 360) else \
            math.dist(last, goal["p"]) <= max(goal["s"]) / 2 + 1.0
        if not inside:
            rep.error(f"path: the last waypoint {last} is not inside the goal box")
        for i in range(len(path_points) - 1):
            a, b = path_points[i], path_points[i + 1]
            flat = math.dist([a[0], a[2]], [b[0], b[2]])
            if flat > PATH_STEP_MAX:
                rep.error(f"path[{i}]->[{i + 1}]: {flat:.1f} m apart (at most {PATH_STEP_MAX})")
            elif flat > PATH_STEP_WARN:
                rep.warn(f"path[{i}]->[{i + 1}]: {flat:.1f} m apart (about every 4 to 6 m)")
            if b[1] - a[1] > JUMP_RISE and flat < 3.0:
                rep.warn(f"path[{i}]->[{i + 1}]: rises {b[1] - a[1]:.2f} m over {flat:.1f} m (a jump reaches {JUMP_RISE} m; a ramp is fine if drawn)")
            # unsupported stretch: no static floor within 1.5 m below the walking line for more than a running jump
            run = 0.0
            steps = max(int(flat / 0.5), 1)
            for s in range(steps + 1):
                u = s / steps
                p = [a[j] + (b[j] - a[j]) * u for j in range(3)]
                y = floor_below(good + tile_boxes, p, reach=1.5)
                if y is None:
                    run += flat / steps
                    if run > JUMP_GAP + 0.01:
                        movers_near = any(isinstance(h, dict) and h.get("k") in ("slide", "lift", "blink", "spin") and vec(h.get("p")) and math.dist(h["p"], p) < 8 for h in hazards)
                        if not movers_near:
                            rep.warn(f"path[{i}]->[{i + 1}]: more than {JUMP_GAP} m without ground near {[round(c, 2) for c in p]} and no mover close by")
                        break
                else:
                    run = 0.0
    return rep


EDGE_BUMPERS_FILE = "edge_bumpers.json"   # EXPERIMENT (switchable): the switch of the edge bumpers (demo/levels/edge_bumpers.gd), next to the level files
EDGE_BUMPERS_FORMAT = "edge-bumpers-1"
EDGE_BUMPERS_SHARE_MAX = 1.0            # edge_bumpers.gd SHARE_MAX: 1.0 puts cushions on every candidate platform


def lint_edge_bumpers(path, level_files):
    """The edge bumpers' switch (docs/level-format.md "Edge bumpers (experiment)"): format, `on`, and per level {on, share, seed}; only race show levels may be listed."""
    rep = Report(f"{path.parent.name}/{path.name}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        rep.error(f"not valid JSON ({error})")
        return rep
    if not isinstance(data, dict):
        rep.error("not an object")
        return rep
    for key in data:
        if key not in {"format", "experiment", "on", "levels"}:
            rep.error(f"unknown key '{key}'")
    if data.get("format") != EDGE_BUMPERS_FORMAT:
        rep.error(f"format must be '{EDGE_BUMPERS_FORMAT}'")
    if not isinstance(data.get("on"), bool):
        rep.error("on must be true or false (false turns the whole experiment off)")
    if not isinstance(data.get("experiment"), str) or not data.get("experiment"):
        rep.error("experiment: a label saying what this is (the switch must stay labelled as an experiment)")
    levels = data.get("levels")
    if not isinstance(levels, dict) or not levels:
        rep.error("levels must be an object {\"29\": {on, share, seed}, ...}")
        return rep
    race = {}
    for file in level_files:
        try:
            level = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(level, dict) and isinstance(level.get("number"), int):
            race[level["number"]] = level
    for key, entry in levels.items():
        where = f"levels.{key}"
        if not key.isdigit() or int(key) not in race:
            rep.error(f"{where}: no level file with that number")
            continue
        level = race[int(key)]
        if level.get("show") != "race" or level.get("world") != "daylight":
            rep.error(f"{where}: edge bumpers are for race show levels with the daylight world")
        if not isinstance(entry, dict):
            rep.error(f"{where}: not an object")
            continue
        for sub in entry:
            if sub not in {"on", "share", "seed"}:
                rep.error(f"{where}: unknown key '{sub}'")
        if not isinstance(entry.get("on"), bool):
            rep.error(f"{where}.on: must be true or false")
        share = entry.get("share", 0.5)
        if isinstance(share, bool) or not isinstance(share, (int, float)) or not 0.0 < share <= EDGE_BUMPERS_SHARE_MAX:
            rep.error(f"{where}.share: {share!r} is not a number in (0, {EDGE_BUMPERS_SHARE_MAX}]")
        seed = entry.get("seed", int(key))
        if isinstance(seed, bool) or not isinstance(seed, int):
            rep.error(f"{where}.seed: {seed!r} is not an integer")
    return rep


def collect(args):
    files = []
    for arg in args or ["demo/levels"]:
        p = Path(arg)
        if p.is_dir():
            files += sorted(p.glob("level_*.json"))
        else:
            files.append(p)
    return files


def main(argv):
    strict = "--strict" in argv
    files = collect([a for a in argv if not a.startswith("--")])
    if not files:
        print("level_lint: no level files found")
        return 1
    failed = 0
    warned = 0
    numbers = []
    for path in files:
        stem = path.stem.split("_")[-1]
        expected = int(stem) if stem.isdigit() else -1
        numbers.append(expected)
        rep = lint_level(path, expected)
        try:
            race = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            race = {}
        if isinstance(race, dict) and race.get("show") == "race" and not rep.errors:
            for text in checkpoint_order_check.check(race):   # a death must never skip an obstacle (tools/checkpoint_order_check.py)
                rep.error(text)
            if race.get("world") == "daylight":
                for text in mover_clearance_check.check(race):   # moving platforms never overlap anything (tools/mover_clearance_check.py)
                    rep.error(text)
        status = "FAIL" if rep.errors else ("warn" if rep.warnings else "ok")
        print(f"{rep.name}: {status} ({len(rep.errors)} errors, {len(rep.warnings)} warnings)")
        for text in rep.errors:
            print(f"  ERROR {text}")
        for text in rep.warnings:
            print(f"  warn  {text}")
        failed += 1 if rep.errors else 0
        warned += 1 if rep.warnings else 0
    if numbers != list(range(1, len(numbers) + 1)):
        print(f"ERROR level numbers are not 1..{len(numbers)} without gaps: {numbers}")
        failed += 1
    for folder in sorted({path.parent for path in files}):
        switch = folder / EDGE_BUMPERS_FILE
        if not switch.exists():
            continue
        rep = lint_edge_bumpers(switch, [path for path in files if path.parent == folder])
        print(f"{rep.name}: {'FAIL' if rep.errors else 'ok'} ({len(rep.errors)} errors)")
        for text in rep.errors:
            print(f"  ERROR {text}")
        failed += 1 if rep.errors else 0
    print(f"level_lint: {len(files)} files, {failed} failed, {warned} with warnings")
    return 1 if failed or (strict and warned) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
