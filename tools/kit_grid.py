"""Where the tiles of a platform are, for the generators that put launch pads on a platform: a mirror of demo/style/block_kit.gd `_fit` / `tile_grid` (square tiles of about 1.5 m in
a whole number each way, GROOVE m between them, a rim ring of RIM_MIN..RIM_MAX round the grid; a stone, a platform no longer than STONE_MAX, has round(side / TILE_UNIT) tiles
each way of about TILE_STONE m). A launch pad (style/pad_look.gd) covers exactly a 2 x 2 block of tiles, so its centre
is a groove crossing of the platform's grid: `snap` moves a wanted pad centre to the nearest crossing that leaves a whole tile ring round the cell where the platform is big enough,
`grow_for_cell` widens a platform that has no 2 x 2 cell. `tools/pad_cell_check.gd` reads the real BlockKit.tile_grid and fails when this mirror and the engine disagree.
"""
import math

GROOVE = 0.11
RIM_MIN = 0.18
RIM_MAX = 0.42
RIM_PREF = 0.24
TILE_TARGET = 1.5
TILE_UNIT = 1.5
TILE_STONE = 1.2
STONE_MAX = 9.0
TILE_MIN = 0.5

_fits = {}


def fit(width, depth):
    """{t, nx, nz, rx, rz} of block_kit.gd `_fit` for a platform width x depth (x, z), {} when no tile fits."""
    key = (round(width * 100.0), round(depth * 100.0))
    if key in _fits:
        return _fits[key]
    found = _search(width, depth, max(width, depth) <= STONE_MAX)
    if not found:
        found = _search(width, depth, False)   # a stone whose two sides ask for tiles of different sizes (5 x 5.5 m): the fallback
    _fits[key] = found
    return found


def _search(width, depth, stone):
    aim = TILE_STONE if stone else TILE_TARGET
    best = {}
    best_score = math.inf
    t = TILE_MIN
    while t <= TILE_TARGET * 1.3 + 0.0001:
        nx = max(round_half_away(width / TILE_UNIT), 1) if stone else math.floor((width - 2.0 * RIM_MIN - GROOVE) / (t + GROOVE))
        nz = max(round_half_away(depth / TILE_UNIT), 1) if stone else math.floor((depth - 2.0 * RIM_MIN - GROOVE) / (t + GROOVE))
        if nx >= 1 and nz >= 1:
            rx = (width - nx * t - (nx + 1) * GROOVE) * 0.5
            rz = (depth - nz * t - (nz + 1) * GROOVE) * 0.5
            if rx <= RIM_MAX and rz <= RIM_MAX and rx >= RIM_MIN - 1e-6 and rz >= RIM_MIN - 1e-6:
                odd = 0.0 if stone else (0.05 if nx % 2 == 1 else 0.0) + (0.05 if nz % 2 == 1 else 0.0)
                score = abs(rx - rz) * 2.0 + abs(t - aim) * (4.0 if stone else 1.0) + (abs(rx - RIM_PREF) + abs(rz - RIM_PREF)) * (0.1 if stone else 0.4) + odd
                if score < best_score:
                    best_score = score
                    best = {"t": t, "nx": nx, "nz": nz, "rx": rx, "rz": rz}
        t += 0.01
    return best


def round_half_away(v):
    """GDScript roundi: halves away from zero."""
    return int(math.floor(v + 0.5)) if v >= 0 else -int(math.floor(-v + 0.5))


def block_under(blocks, x, z, top):
    """The static box whose top (within 2 cm of `top`) lies under (x, z), the biggest one when several do; None for none."""
    best = None
    for b in blocks:
        if b.get("k") != "box" or b.get("r") or b.get("m") in ("belt", "ice"):
            continue
        px, py, pz = b["p"]
        sx, sy, sz = b["s"]
        if abs(py + sy / 2 - top) > 0.02 or abs(x - px) > sx / 2 + 1e-6 or abs(z - pz) > sz / 2 + 1e-6:
            continue
        if best is None or sx * sz > best["s"][0] * best["s"][2]:
            best = b
    return best


def cells(block):
    """The centres (x, z) of every 2 x 2 tile cell of the block's grid, with (i, j) and the grid size: [(x, z, i, j, nx, nz)]; [] when the block has no 2 x 2 cell."""
    px, _, pz = block["p"]
    sx, _, sz = block["s"]
    f = fit(sx, sz)
    if not f or f["nx"] < 2 or f["nz"] < 2:
        return []
    pitch = f["t"] + GROOVE
    ox = px - sx / 2 + f["rx"] + GROOVE + f["t"] / 2
    oz = pz - sz / 2 + f["rz"] + GROOVE + f["t"] / 2
    return [(ox + pitch * (i + 0.5), oz + pitch * (j + 0.5), i, j, f["nx"], f["nz"]) for i in range(f["nx"] - 1) for j in range(f["nz"] - 1)]


def full_cell(block):
    """(x, z, span) of the whole tile grid of a small stone (a block of n x n tiles, n >= 2): the middle of the block and the side of the n x n tiles with their grooves
    (n t + (n - 1) GROOVE); None when the block's grid is not square or has fewer than 2 tiles a side. A pad that covers the whole stone (style/pad_look.gd `cell_side`) is this big."""
    f = fit(block["s"][0], block["s"][2])
    if not f or f["nx"] != f["nz"] or f["nx"] < 2:
        return None
    return block["p"][0], block["p"][2], f["nx"] * f["t"] + (f["nx"] - 1) * GROOVE


def snap(blocks, x, z, top, taken=()):
    """The pad centre (x, z) moved to the nearest free 2 x 2 cell of the platform under it (a cell with a whole tile ring round it when there is one, never one
    of `taken`: [(x, z)] of the pads already on the platform); (x, z) itself when nothing is under it or the platform has no cell."""
    block = block_under(blocks, x, z, top)
    if block is None:
        return x, z
    options = cells(block)
    inner = [c for c in options if 1 <= c[2] <= c[4] - 3 and 1 <= c[3] <= c[5] - 3]
    pitch = fit(*[block["s"][0], block["s"][2]])["t"] + GROOVE
    free = [c for c in (inner or options) if all(math.hypot(c[0] - tx, c[1] - tz) > pitch * 1.9 for tx, tz in taken)]
    if not free:
        free = [c for c in options if all(math.hypot(c[0] - tx, c[1] - tz) > pitch * 1.9 for tx, tz in taken)]
    if not free:
        return x, z
    # pads of one platform stand in a row or a column of the grid: a cell lined up with a pad already there wins over a nearer one that is not
    lined = lambda c: 0.0 if not taken or any(abs(c[0] - tx) < 0.01 or abs(c[1] - tz) < 0.01 for tx, tz in taken) else 4.0
    c = min(free, key=lambda c: math.hypot(c[0] - x, c[1] - z) + lined(c))
    return c[0], c[1]


def grow_for_cell(block, x, z, side=4.5):
    """Widen `block` (a static box dict, in place) around the pad centre (x, z) to at least `side` m each way when its grid has no 2 x 2 cell; the pad then
    sits on the middle of an even grid, which is a groove crossing."""
    if cells(block):
        return
    px, py, pz = block["p"]
    sx, sy, sz = block["s"]
    x0, x1 = min(px - sx / 2, x - side / 2), max(px + sx / 2, x + side / 2)
    z0, z1 = min(pz - sz / 2, z - side / 2), max(pz + sz / 2, z + side / 2)
    block["p"] = [round((x0 + x1) / 2, 3), py, round((z0 + z1) / 2, 3)]
    block["s"] = [round(x1 - x0, 3), sy, round(z1 - z0, 3)]
