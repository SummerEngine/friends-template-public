"""The kill plane of a race level (`"world": "daylight"`: the slime sea of demo/style/candy_world.gd) and the kill height that belongs to it, shared by tools/gen_level_29.py and gen_level_30.py.

The slime lies in one horizontal plane under the whole course: a courier dies exactly when its feet reach it. The rules test the courier's CENTRE (feet + CENTRE_HEIGHT, levels/level_world.gd
`zone_at`) against `void_y`, so `void_y` = plane height + CENTRE_HEIGHT; the world draws the plane at `void_y - CENTRE_HEIGHT` (style/race_world.gd), so there is one number and no
`kill` volume. The plane is LIFT m over the lowest block's underside, so every pillar that reaches down ends inside the plane (the glow ring of its foot meets it) and nothing
walkable is under it.
"""
CENTRE_HEIGHT = 0.9   # a courier's centre over its feet (levels/level_world.gd CENTRE_HEIGHT)
LIFT = 0.75           # m the lowest block's underside lies under the plane
MIN_DROP = 6.0        # m the plane lies under the lowest walkable floor at least
MAX_DROP = 14.0       # ... and at most (the slime lies 8 to 12 m under the platforms)
MIN_FLOOR = 2.0       # style/race_world.gd MIN_FLOOR: a block narrower than this in x or z is a post or a wall, not a floor


def _extent(block):
    """(lowest y, highest y, width x, width z) of a block dict of the level file; a turned block counts as its bounding sphere."""
    p = block["p"]
    if block["k"] == "cyl":
        size = [block["d"], block["h"], block["d"]]
    else:
        size = block["s"]
    if "r" in block and any(abs(a) > 1e-9 for a in block["r"]):
        reach = 0.5 * (size[0] ** 2 + size[1] ** 2 + size[2] ** 2) ** 0.5
        return p[1] - reach, p[1] + reach, size[0], size[2]
    return p[1] - size[1] * 0.5, p[1] + size[1] * 0.5, size[0], size[2]


def lowest(blocks):
    """(top of the lowest walkable floor, underside of the lowest block), level-local."""
    floor_top = 0.0
    bottom = 0.0
    for block in blocks:
        low, high, wx, wz = _extent(block)
        bottom = min(bottom, low)
        if block["k"] != "wedge" and wx >= MIN_FLOOR and wz >= MIN_FLOOR:
            floor_top = min(floor_top, high)
    return floor_top, bottom


def void_y(blocks):
    """The level's `void_y` (on the 0.25 m grid): the sea's height plus CENTRE_HEIGHT. Asserts the sea's drop under the lowest walkable floor."""
    floor_top, bottom = lowest(blocks)
    plane = bottom + LIFT
    value = round((plane + CENTRE_HEIGHT) * 4.0) / 4.0
    drop = floor_top - (value - CENTRE_HEIGHT)
    assert MIN_DROP <= drop <= MAX_DROP, f"the sea lies {drop:.2f} m under the lowest floor (top {floor_top}, lowest underside {bottom}), wanted {MIN_DROP} to {MAX_DROP}"
    return value
