extends RefCounted
## Backdrop themes (style/backdrop.gd): which world surrounds which level, and the colours of it. Pure data and small helpers, no nodes.
## A level's theme is a (kind, time of day) pair read from PLAN by its number, so the 24 levels do not look alike and every run of a level
## gets the same one. KINDS describe the world far below the course and on the horizon; TIMES the sky and the light colour of that world.
## Background colours are desaturated and cooler than the course: the course stays the only warm, saturated, high-contrast thing.
const CITY := "city"      ## rooftops and streets seen from above, a skyline with towers, cranes and billboards
const YARD := "yard"      ## a building site: container stacks, pits, tower cranes
const PARK := "park"      ## fields, hedges, a river, tiny houses and trees, ranges of hills
const CLOUD := "cloud"    ## a sea of clouds with halftone shading
const DAY := "day"
const DUSK := "dusk"
const NIGHT := "night"

## 1-based level number - 1 -> [kind, time]. Day for the first half, dusk then night towards the hard levels.
const PLAN := [
	[PARK, DAY], [CITY, DAY], [YARD, DAY], [PARK, DAY], [YARD, DAY], [CLOUD, DAY],
	[CITY, DAY], [PARK, DAY], [YARD, DUSK], [CLOUD, DAY], [CITY, DUSK], [PARK, DUSK],
	[YARD, DUSK], [CITY, DUSK], [CLOUD, DUSK], [PARK, DUSK], [CITY, DUSK], [YARD, DUSK],
	[CLOUD, NIGHT], [CITY, NIGHT], [PARK, NIGHT], [YARD, NIGHT], [CITY, NIGHT], [CLOUD, NIGHT],
]

## Sky and fog per time of day: `paper` is the sky colour at the horizon (the far haze of every backdrop piece), `tint` the halftone colour
## towards the zenith (style/ink_sky.gdshader), `ink` the cloud line, `fog` the density of the level fog, `shade` darkens the backdrop pieces,
## `warm` pulls their colours towards the light of that hour, `lit` is how many windows are lit, `sun` the sky's glow of the light.
const TIMES := {
	DAY: {"paper": Color("#f6ecd2"), "tint": Color("#99bdff"), "ink": Color("#1b1d3a"), "fog": 0.0045, "shade": 1.0, "warm": Color("#ffffff"), "warm_amount": 0.0, "lit": 0.0, "sun": Color("#ffd23f")},
	DUSK: {"paper": Color("#f1cdb0"), "tint": Color("#b58abf"), "ink": Color("#3a2450"), "fog": 0.003, "shade": 0.95, "warm": Color("#a8789f"), "warm_amount": 0.12, "lit": 0.35, "sun": Color("#ff9a6b")},
	NIGHT: {"paper": Color("#2d3268"), "tint": Color("#6a56b4"), "ink": Color("#9aa0ee"), "fog": 0.002, "shade": 0.74, "warm": Color("#2f3a7c"), "warm_amount": 0.42, "lit": 0.85, "sun": Color("#a99cff")},
}

## Palettes (daylight colours; `tone` brings them to the hour).
const CITY_BUILDING: Array[Color] = [Color("#8196b4"), Color("#93a6c0"), Color("#7388a8"), Color("#a3b3c8"), Color("#6f7f9c"), Color("#9aa7bd")]
const CITY_GROUND: Array[Color] = [Color("#c3cac4"), Color("#b6c3b6"), Color("#d0cfc0"), Color("#a7b9a4"), Color("#76839b"), Color("#dcd9cb")]
const YARD_BUILDING: Array[Color] = [Color("#7f9cae"), Color("#a7a28c"), Color("#9d8680"), Color("#8aa08f"), Color("#a6adb5"), Color("#8f98a3")]
const YARD_GROUND: Array[Color] = [Color("#cdbf9f"), Color("#bfb391"), Color("#b3a785"), Color("#a09478"), Color("#968c78"), Color("#d6cfba")]
const YARD_CRANE := Color("#c5b57a")
const PARK_GROUND: Array[Color] = [Color("#a9c394"), Color("#98b98b"), Color("#bacb9a"), Color("#90b196"), Color("#8fb7cc"), Color("#6f9a79")]
const PARK_TREE: Array[Color] = [Color("#6f9b7c"), Color("#5f8c74"), Color("#7ba583"), Color("#8aae78")]
const PARK_ROOF: Array[Color] = [Color("#b98f86"), Color("#a38aa3"), Color("#c3a77f"), Color("#8e9fc0")]
const PARK_WALL: Array[Color] = [Color("#e3dccb"), Color("#d6d3c4"), Color("#dcd0c0")]
const MOUNTAIN: Array[Color] = [Color("#8aa3bb"), Color("#7d96b0"), Color("#98aec3")]
const CLOUD_GROUND: Array[Color] = [Color("#dde3f0"), Color("#c9d1e6"), Color("#b3bedb"), Color("#9ba7cc"), Color("#dde3f0"), Color("#9ba7cc")]
const CLOUD_PUFF: Array[Color] = [Color("#e6eaf5"), Color("#d8dff0"), Color("#c9d2e8")]
const ISLAND_GRASS: Array[Color] = [Color("#a2c294"), Color("#92b98a"), Color("#b0c997")]
const ISLAND_ROCK: Array[Color] = [Color("#8b8ca6"), Color("#7d7f9c"), Color("#9a9bb3")]
const BILLBOARD: Array[Color] = [Color("#c9b98a"), Color("#a9b8d0"), Color("#c3a1a1"), Color("#a5bfae")]
const BLIMP := Color("#c6cde0")

## 1-based level number -> {kind, time}. Numbers outside 1..24 repeat the plan. `theme` is the team's world (TeamCast.world_theme()):
## "office" keeps the built world (city, building site, clouds) and turns parks into city; "outdoor" turns city and building site into park.
static func plan(number: int, theme := "") -> Dictionary:
	var row: Array = PLAN[posmod(number - 1, PLAN.size())]
	return {"kind": themed(row[0], theme), "time": row[1]}

static func themed(kind: String, theme: String) -> String:
	match theme:
		"office": return CITY if kind == PARK else kind
		"outdoor": return PARK if kind == CITY or kind == YARD else kind
	return kind

## A fixed seed per level and kind: the same level always grows the same backdrop (no clock, no global random).
static func seed_of(number: int, kind: String) -> int:
	return (number * 7919 + kind.hash() % 100003) & 0x7fffffff

## A daylight colour at the given hour, as the linear colour the instance data carries. `jitter` is a brightness spread (0.04 = +-4 %).
static func tone(color: Color, time: String, jitter := 0.0) -> Color:
	var look: Dictionary = TIMES[time]
	var result := color.lerp(look.warm as Color, float(look.warm_amount)) * float(look.shade)
	result = result * (1.0 + jitter)
	result.a = 1.0
	return result.srgb_to_linear()
