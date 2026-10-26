#!/usr/bin/env python3
"""Writes the four stage rounds (docs/level-format.md "Stage rounds"): `demo/levels/level_25.json` .. `level_28.json`.

    python3 tools/stage_levels_gen.py            # write the files
    python3 tools/stage_levels_gen.py --check    # fail when a file is not what this script would write

A stage round is a stack of flat tile layers over a permanent ground, ringed by an enclosure (the world's own business: `stage.enclosure` "a" or "b"), played
as a survival round: a tile somebody stands on turns white, holds for half a second and is gone; whoever lands on the ground is out. The numbers of a layer stack
live here (one table per round shape) so that the four files stay alike; everything the rules, the look and the checks read is in the files. A and B differ only
in `stage.enclosure` and the title letter.

Units: a square round is 22 x 22 tiles of 3.5 m in four layers, a hex round is flat-top hexagons of 4.06 m flat to flat in eight layers, a rounded hexagon of about
690 tiles a layer; the layers are GAP = 14.3 m apart in both (the floors are one-way, courier/courier_motion.gd). GAP is the gap a fall of 0.59 s needs with our gravity
(86.4 m/s2, a body leaves a vanished tile at rest, speed cap 40 m/s): a fall between two layers should last 0.5-0.65 s (15-19 frames at 30 fps), the cage (style/arena_cage.gd) stacks one tier per layer, a tier being one gap tall: a beam, a panel and the air over and under the panel. Level-local y 0
is the top of the first layer; the ground's top (`stage.ground.y`) is one layer gap under the last layer; the ground slab reaches under the whole enclosure (the cage's ring
plus GROUND_OVER) so that the walls stand on it.
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ROOT / "demo" / "levels"
HEX_ROW = math.sqrt(3.0) / 2.0

GAP = 14.3   # m between the tops of two layers (and of the last layer and the ground): a fall of 0.59 s, see the header
RIM_GAP = 6.125   # m between the tiles' rim and the cage's ring, style/arena_world.gd RIM_GAP (1.75 E)
GROUND_OVER = 1.5   # m the ground slab reaches past the ring (the walls' plane) on every side

# One table per round shape. `tones`: the colour of each layer from the top down: the middle shade of its colour family (style/candy_look.gd TILE_FAMILIES, the middle shade: blue #1aa8f4, cyan #59e4e4, amber #ffad00,
# magenta-violet #b02da2; style/stage_tile_look.gd draws each tile in one of the family's three shades);
# `gap`: metres between the tops of two layers.
SHAPES = {
    "square": {
        "title": "SQUARE STACK", "blurb": "Square tiles in four layers. A tile you stand on goes white, then it is gone.",
        "grid": "square", "pitch": 3.5, "thick": 0.5, "size": 22, "gap": GAP,
        "tones": ["#1aa8f4", "#b02da2", "#1aa8f4", "#b02da2"],
        "pad": "#ffad00", "delay": 0.5, "cap": 140.0,
        "ground": "#a1e531",
    },
    "hex": {
        "title": "HEX STACK", "blurb": "Hexagon tiles in eight layers. A tile you stand on goes white, then it is gone.",
        "grid": "hex", "pitch": 4.06, "thick": 0.5, "gap": GAP,
        "columns": 14,   # columns either side of the middle one: 29 columns
        "reach_hex": 16, "reach": 14.0,  # the outline: within 16 hexagon steps of the middle and 14 pitches of it (a rounded hexagon, 691 tiles)
        "tones": ["#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00"],
        "pad": "#59e4e4", "delay": 0.5, "cap": 150.0,
        "ground": "#a1e531",
    },
}
LEVELS_OUT = [(25, "square", "a"), (26, "hex", "a"), (27, "square", "b"), (28, "hex", "b")]
GROUND_THICK = 2.0
PLAYERS = 12


def square_layout(s):
    """The square round's rows (one character per tile) of the start layer and of a full layer, and the group centres: 12 groups of 3 x 3 tiles in a staggered block of 3 rows x 4,
    four tiles apart, in the near (-Z) half of the arena: the middle start pad at z -8.75 so the start view (camera behind it, looking +Z) shows the pillar line's hubs and beams over the far rows. Returns (rows of the start layer, rows of a full layer, group centres as (column, row))."""
    size = s["size"]
    plain = [["n"] * size for _ in range(size)]
    top = [[" "] * size for _ in range(size)]   # the start layer: only the 12 groups of 3 x 3 tiles
    centres = []
    for band, first_row in enumerate((3, 7, 11)):
        for k in range(4):
            first_col = 3 + 4 * k + (2 if band == 1 else 0)
            for dr in range(3):
                for dc in range(3):
                    top[first_row + dr][first_col + dc] = "n"
            centres.append((first_col + 1, first_row + 1))
    middle = (sum(c for c, _ in centres) / len(centres), sum(r for _, r in centres) / len(centres))
    centres.sort(key=lambda cell: math.hypot(cell[0] - middle[0], cell[1] - middle[1]))  # the first start is the pad in the middle of the block
    return ["".join(row) for row in top], ["".join(row) for row in plain], centres


def square_point(s, cell):
    size = s["size"]
    return [round((cell[0] - (size - 1) / 2) * s["pitch"], 3), round((cell[1] - (size - 1) / 2) * s["pitch"], 3)]


def hex_cells(s):
    """The cells (column c, half-step v) of the hex round's layer: a flat-top hexagon at column c is x = c * 0.866 pitches, at half-step v is z = v / 2 pitches,
    (c + v) even; the outline is a rounded hexagon (within `reach_hex` hexagon steps and `reach` pitches of the middle, `columns` columns either side)."""
    cells = set()
    for c in range(-s["columns"], s["columns"] + 1):
        for v in range(-2 * s["columns"] - 6, 2 * s["columns"] + 7):
            if (c + v) % 2:
                continue
            steps = max(abs(c), (abs(c) + abs(v)) / 2)
            if steps <= s["reach_hex"] and math.hypot(c * HEX_ROW, v / 2) <= s["reach"] + 1e-9:
                cells.add((c, v))
    return cells


def hex_rows(s, cells):
    """Rows of the flat-top grid text (levels/step_tiles.gd: a flat-top grid is the pointy one turned a quarter, so a text row is a COLUMN of the layer, a text column a half
    step along Z): a cell is `n`."""
    columns = s["columns"]
    vmax = 2 * columns  # the text is symmetric about the middle cell: column + row even
    rows = []
    for c in range(-columns, columns + 1):
        text = ""
        for v in range(-vmax, vmax + 1):
            if (c, v) in cells:
                text += "n"
            else:
                text += " "
        rows.append(text)
    return rows


def hex_flowers():
    """The 12 start groups of the hex round (`flower`): a staggered block of 3 rows x 4 on a hexagonal lattice, so every group has its neighbours the same distance away: four columns (3.46 pitches)
    along a row, and the middle row's groups two columns over and three pitches down from the rows beside it (the same 3.46 pitches), the middle band 4.06 m past the middle (z +4): the pad
    cluster stands near the middle of its arena and the start view sees the pillar line (the corner pillars, 45 m away). A group is one hexagon's gap from the next.
    Returns the centres (c, v), the first the one in the middle of the block."""
    centres = []
    for band, v in enumerate((-4, 2, 8)):
        for k in range(4):
            centres.append(((-4 if band != 1 else -6) + 4 * k, v))
    middle = (sum(c * HEX_ROW for c, _ in centres) / len(centres), sum(v / 2 for _, v in centres) / len(centres))
    centres.sort(key=lambda cell: math.hypot(cell[0] * HEX_ROW - middle[0], cell[1] / 2 - middle[1]))
    return centres


def flower(centre):
    """The seven cells of a start group: a hexagon and its six neighbours, a flower of hexagons (in the flat-top grid: the centre, the cells above and below it on its own column, and the
    two above and below on each neighbouring column); the centre hexagon is the start spot."""
    c, v = centre
    return {(c, v), (c, v - 2), (c, v + 2), (c - 1, v - 1), (c - 1, v + 1), (c + 1, v - 1), (c + 1, v + 1)}


def ring_half(points, corners, sides, turn):
    """The half extents (x, z) of the cage's ring around tiles at `points` with the tile outline `corners`: style/arena_world.gd ring_of (a convex polygon of `sides` sides
    whose side normals start at angle `turn`, pulled tight around every tile corner, pushed out RIM_GAP) and its corners."""
    normals = [(math.cos(2 * math.pi * k / sides + turn), math.sin(2 * math.pi * k / sides + turn)) for k in range(sides)]
    offsets = [max(n[0] * (px + cx) + n[1] * (pz + cz) for px, pz in points for cx, cz in corners) + RIM_GAP for n in normals]
    xs, zs = [], []
    for k in range(sides):
        a, b = normals[k], normals[(k + 1) % sides]
        det = a[0] * b[1] - a[1] * b[0]
        da, db = offsets[k], offsets[(k + 1) % sides]
        xs.append(abs((da * b[1] - db * a[1]) / det))
        zs.append(abs((a[0] * db - b[0] * da) / det))
    return max(xs), max(zs)


def level(number, shape, enclosure):
    s = SHAPES[shape]
    square = s["grid"] == "square"
    layers = len(s["tones"])
    if square:
        top_rows, plain_rows, centres = square_layout(s)
        starts_xz = [square_point(s, cell) for cell in centres]
        floors_rows = [top_rows] + [plain_rows] * layers
        extent = s["size"] * s["pitch"]
        half = ring_half([(0.0, 0.0)], [(-extent / 2, -extent / 2), (extent / 2, -extent / 2), (extent / 2, extent / 2), (-extent / 2, extent / 2)], 4, 0.0)
        kinds = {"n": {"delay": s["delay"], "look": "plain"}}
    else:
        cells = hex_cells(s)
        centres = hex_flowers()
        pads = set()
        for centre in centres:
            assert not (flower(centre) & pads), "two start groups touch"
            pads |= flower(centre)
        assert pads <= cells, "a pad reaches out of the outline"
        assert 650 <= len(cells) <= 720, f"{len(cells)} hexagons"
        plain_rows = hex_rows(s, cells)
        floors_rows = [hex_rows(s, pads)] + [plain_rows] * layers
        starts_xz = [[round(c * HEX_ROW * s["pitch"], 3), round(v / 2 * s["pitch"], 3)] for c, v in centres]
        radius = s["pitch"] / math.sqrt(3.0)
        points = [(c * HEX_ROW * s["pitch"], v / 2 * s["pitch"]) for c, v in cells]
        half = ring_half(points, [(math.sin(math.tau * k / 6) * radius, math.cos(math.tau * k / 6) * radius) for k in range(6)], 6, math.pi / 6)
        kinds = {"n": {"delay": s["delay"], "look": "plain"}}
    # the start layer (the groups) one gap over the first full layer, whose top is level-local y 0
    floors = [{"y": round(s["gap"], 2), "origin": [0.0, 0.0], "tone": s["pad"], "rows": floors_rows[0]}]
    for index, tone in enumerate(s["tones"]):
        floors.append({"y": round(-s["gap"] * index, 2) + 0.0, "origin": [0.0, 0.0], "tone": tone, "rows": floors_rows[index + 1]})
    low = floors[-1]["y"]
    ground_y = round(low - s["gap"], 2)
    ground_size = [round(2 * (half[0] + GROUND_OVER), 1), round(2 * (half[1] + GROUND_OVER), 1)]
    ground_bottom = ground_y - GROUND_THICK
    starts = [[x, floors[0]["y"], z] for x, z in starts_xz]
    title = f"{s['title']} {enclosure.upper()}"
    data = {
        "format": "level-1",
        "number": number,
        "title": title,
        "blurb": s["blurb"],
        "rule": "DON'T FALL  ·  BE ONE OF THE LAST STANDING",
        "hint": "A TILE YOU STAND ON GOES WHITE, THEN IT IS GONE",
        "modes": ["show"],
        "pool": False,
        "show": "survival",
        "start": {"p": [0, 0, 0], "yaw": 180},
        "goal": {"p": [0.0, 1.0, -9.0], "s": [4.0, 2.0, 4.0], "yaw": 0.0},
        "path": [[0.0, 0.0, 0.0], [0.0, 0.0, -4.5], [0.0, 0.0, -9.0]],
        "void_y": round(ground_bottom - 12.0, 2),
        "kill": [{"p": [0.0, round(ground_bottom - 4.0, 2), 0.0], "s": [200.0, 6.0, 200.0], "yaw": 0.0}],
        "blocks": [],
        "stage": {
            "enclosure": enclosure, "cap": s["cap"], "starts": starts[:PLAYERS],
            "ground": {"y": ground_y, "thick": GROUND_THICK, "centre": [0.0, 0.0], "size": ground_size, "tone": s["ground"]},
        },
        "tiles": {
            "grid": s["grid"], "style": "stage", "wrap": True,
            "pitch": s["pitch"], "thick": s["thick"],
            "kinds": kinds,
            "floors": floors,
        },
    }
    if not square:
        data["tiles"]["orient"] = "flat"
        data["tiles"] = {k: data["tiles"][k] for k in ("grid", "orient", "style", "wrap", "pitch", "thick", "kinds", "floors")}
    return data


def render(data):
    """Compact JSON: one line per top-level key, the floor rows on one line each."""
    lines = ["{"]
    keys = list(data)
    for i, key in enumerate(keys):
        value = data[key]
        if key == "tiles":
            tiles = dict(value)
            floors = tiles.pop("floors")
            head = json.dumps(tiles, ensure_ascii=False)[:-1]
            body = ",\n    ".join(
                json.dumps({k: v for k, v in f.items() if k != "rows"}, ensure_ascii=False)[:-1] + ', "rows": [\n      ' + ",\n      ".join(json.dumps(r) for r in f["rows"]) + "\n    ]}"
                for f in floors)
            text = f'  "tiles": {head}, "floors": [\n    {body}\n  ]}}'
        else:
            text = f'  "{key}": {json.dumps(value, ensure_ascii=False)}'
        lines.append(text + ("," if i < len(keys) - 1 else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    check = "--check" in sys.argv
    bad = 0
    for number, shape, enclosure in LEVELS_OUT:
        text = render(level(number, shape, enclosure))
        path = LEVELS / f"level_{number:02d}.json"
        if check:
            if not path.exists() or path.read_text() != text:
                print(f"{path.name}: not what stage_levels_gen.py writes")
                bad += 1
        else:
            path.write_text(text)
            print("wrote", path.name)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
