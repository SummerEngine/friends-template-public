extends RefCounted
## The party look: the look of the show mode (cast `mode` "show"): the lobby yard and every show level in a bright, playful world made
## from the cast's own colours instead of the facility's grey and blue. Pure data: `spec()` has the shape of `Surfaces.LOOK`
## (style/surfaces.gd hands it out instead while `on()`), `palette()` is what the open-air backdrop (style/party_backdrop.gd) and the
## sun and sky (levels/level_environment.gd) are painted with. Nothing here is a fixed colour except the fallback hues and the hazard red.
##
## The palette comes from `brand.colors` (up to 3, greys and near-blacks are skipped as "no colour"):
##   P  primary    the first colour with colour in it: the course (walls, track, curbs). Its own hue, saturation 0.55..0.92, value 0.8..1
##   S  secondary  the next colour at least 0.06 of hue away from P, else a sky blue (a peach when P itself is blue): sky, accent walls
##   A  accent     the third colour, else a burnt shade of P (its hue turned a little towards red, dark: `_burnt`): moving platforms, flags, confetti
##   X, Y          two neighbours of P on the colour wheel (a little towards yellow, a little towards red): hop blocks, confetti
## Every role comes in the same few tones (`main` candy, `deep`, `soft`, `pale`) so any palette gets the same contrast: a pale track,
## saturated curbs and walls, saturated hop blocks, hazards in a candy red that is never a floor colour. A cast without brand colours
## gets coral, sky blue and a burnt coral. `tools/party_look_check.gd` runs the rules over many palettes.
## The brand's first colour leads every surface that is not the sky: the hexagon tiles (`tiles`: three tones of P) and the lobby's signboards
## (`signs`: THE SHOW is P itself, the other kinds tones of it) never borrow another hue. A near-black brand colour is the `ink` (text, outlines)
## and a light grey one the `trim` (sign frames); neither is ever a floor, a wall or a tile.
##
## One switch makes it the night look: cast `world.style` "night" (TeamCast.world_style(), `night()` here) keeps every key of the palette and the spec but
## paints them dark: near-black glossy floors and walls with thin glowing lines in the accent (`_night`), dark obstacles with accent trim, the
## lettering light on dark (style/night_look.gd is the spec, style/night_backdrop.gd the world, style/night_sky.gdshader the sky).
const TeamCast := preload("res://style/team_cast.gd")
const DevEnv := preload("res://dev_env.gd")
const NightLook := preload("res://style/night_look.gd")

const MIN_SATURATION := 0.25     ## below this (or a value below MIN_VALUE) a brand colour counts as grey
const MIN_VALUE := 0.30
const DISTINCT := 0.06           ## hue distance (0..0.5) that makes two brand colours different roles
const FALLBACK_HUE := 0.99        ## a cast without brand colours: coral
const BURNT_SHIFTS := [-0.04, 0.04, -0.075, 0.075]  ## the accent of a brand without a third colour: P turned this far (towards red first) and darker
const WARM_SHIFTS := [0.05, 0.09, -0.1, 0.13, -0.13]   ## X: P turned this far towards yellow (the first that keeps clear of the roles taken)
const COOL_SHIFTS := [-0.085, 0.1, -0.12, 0.14, 0.17]  ## Y: P turned this far towards red
const NEIGHBOUR_GAP := 0.035
const SKY_BLUE := 0.57
const TILE_STEP := 1.15          ## contrast between the neighbouring tones of the hexagon tiles
const PEACH := 0.08
const CREAM := Color("#fff7ea")
const DANGER := Color("#f23a4e")
const SUN := Color("#fff1dc")
const NIGHT_FALLBACK_HUE := 0.52   ## a cast without brand colours gets a cyan accent in the night look
const NIGHT_SUN := Color("#ffe2b8")
const NIGHT_AMBIENT := Color("#34415a")

static var _on := -1
static var _key := ""
static var _palette := {}
static var _spec := {}

## The party look is the show mode's. Dev runs can look at the facility (`--look=facility`) or the comic look (`--look=comic`) instead, after the `--`.
static func on() -> bool:
	if _on < 0: _on = 0 if DevEnv.user_args().has("--look=facility") or DevEnv.user_args().has("--look=comic") else 1
	return _on == 1 and TeamCast.mode() == "show"

## The show's world is the night look (cast `world.style` "night", or "auto" with a near-black first brand colour) instead of the party look.
static func night() -> bool:
	return on() and TeamCast.world_style() == "night"

## Tools: the party look or the facility look, whatever the cast's mode (nothing built yet).
static func set_forced(party: bool) -> void:
	_on = 1 if party else 0

static func hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)

## The roles' hues in order P, S, A, X, Y (0..1).
static func hues() -> Array[float]:
	var found: Array[float] = []
	for color in TeamCast.brand_colors():
		if color.s < MIN_SATURATION or color.v < MIN_VALUE: continue
		var fresh := true
		for hue in found:
			if hue_gap(hue, color.h) < DISTINCT: fresh = false
		if fresh: found.append(color.h)
	var result: Array[float] = []
	result.append(found[0] if found.size() > 0 else FALLBACK_HUE)
	if found.size() > 1: result.append(found[1])
	else: result.append(PEACH if result[0] > 0.45 and result[0] < 0.72 else SKY_BLUE)
	if found.size() > 2: result.append(found[2])
	else: result.append(_neighbour(result, BURNT_SHIFTS))
	result.append(_neighbour(result, WARM_SHIFTS))
	result.append(_neighbour(result, COOL_SHIFTS))
	return result

## A hue next to P on the wheel (the first of `shifts` that keeps `NEIGHBOUR_GAP` from every role already taken).
static func _neighbour(taken: Array[float], shifts: Array) -> float:
	for shift: float in shifts:
		var candidate := fposmod(taken[0] + shift, 1.0)
		var clear := true
		for hue in taken:
			if hue_gap(hue, candidate) < NEIGHBOUR_GAP: clear = false
		if clear: return candidate
	return fposmod(taken[0] + float(shifts[0]), 1.0)

## A is the third brand colour; without one it is a burnt shade of P (`_burnt`), never another hue. X and Y (hop blocks, confetti) are always neighbours of P on the wheel.
static func _burnt(hue: float) -> Dictionary:
	return {"main": Color.from_hsv(hue, 0.88, 0.62), "deep": Color.from_hsv(hue, 0.92, 0.42), "soft": Color.from_hsv(hue, 0.42, 1.0), "pale": Color.from_hsv(hue, 0.17, 1.0)}

## How many different hues the brand colours have (greys and near-blacks do not count).
static func _brand_hue_count() -> int:
	var found: Array[float] = []
	for color in TeamCast.brand_colors():
		if color.s < MIN_SATURATION or color.v < MIN_VALUE: continue
		var fresh := true
		for hue in found:
			if hue_gap(hue, color.h) < DISTINCT: fresh = false
		if fresh: found.append(color.h)
	return found.size()

static func _brand_tone(hue: float) -> Color:
	for color in TeamCast.brand_colors():
		if color.s >= MIN_SATURATION and color.v >= MIN_VALUE and hue_gap(color.h, hue) < 0.001:
			return Color.from_hsv(hue, clampf(color.s, 0.55, 0.92), clampf(color.v, 0.8, 1.0))
	return Color.from_hsv(hue, 0.72, 1.0)

## A brand colour that is near black or dark grey: ink, never a floor or a wall.
static func _is_dark(color: Color) -> bool:
	return color.v < MIN_VALUE or (color.s < MIN_SATURATION and color.v < 0.5)

## A brand colour that is near white or light grey: trim, never a floor or a wall.
static func _is_light_grey(color: Color) -> bool:
	return color.s < MIN_SATURATION and color.v >= 0.6

## The ink (text, outlines, the dark of the signs): the brand's own near black when it has one, else a very dark tone of the primary.
static func _brand_ink(hue: float) -> Color:
	for color in TeamCast.brand_colors():
		if _is_dark(color): return Color.from_hsv(color.h, minf(color.s, 0.6), minf(color.v, 0.22))
	return Color.from_hsv(hue, 0.45, 0.22)

## The trim (sign frames, rims): the brand's own light grey when it has one, else a pale tone of the primary.
static func _brand_trim(primary: Dictionary) -> Color:
	for color in TeamCast.brand_colors():
		if _is_light_grey(color): return color
	return (primary.soft as Color).lerp(CREAM, 0.5)

## The three tones of the hexagon tiles (style/step_tile_look.gd): the primary at full strength (the daylight and the tone mapping wash a tile out, so
## its saturation is lifted), a deeper and warmer tone of it and a paler one, each at least TILE_STEP of contrast from the next so no two neighbours match.
## A primary too light for a paler tone gets two deeper ones.
static func _tiles(main: Color) -> Array[Color]:
	var vivid := Color.from_hsv(main.h, clampf(main.s * 1.6, 0.85, 1.0), 0.9)
	var deep := against(Color.from_hsv(fposmod(main.h - 0.02, 1.0), minf(vivid.s + 0.12, 1.0), vivid.v), vivid, TILE_STEP * 1.25)
	var pale := Color.from_hsv(fposmod(main.h + 0.015, 1.0), 0.5, 0.98)
	if contrast(pale, vivid) >= TILE_STEP: return [deep, vivid, pale]
	var deeper := against(Color.from_hsv(fposmod(main.h + 0.02, 1.0), minf(vivid.s + 0.1, 1.0), deep.v), deep, TILE_STEP)
	return [vivid, deep, deeper]

## The banners of the lobby's signboards by kind: THE SHOW wears the primary at full strength, the races a burnt tone of it, the survival rounds a tone a
## little towards red, the final one a little towards yellow: one family, never another brand's colours.
static func _signs(main: Color, hue: float) -> Dictionary:
	return {"show": Color.from_hsv(hue, maxf(main.s, 0.72), 1.0), "race": Color.from_hsv(hue, 0.85, 0.78), "survival": Color.from_hsv(fposmod(hue - 0.05, 1.0), 0.8, 0.85),
		"final": Color.from_hsv(fposmod(hue + 0.045, 1.0), 0.75, 0.95)}

## The text colour of a surface painted `color`: the ink or white, whichever reads better.
static func text_on(color: Color) -> Color:
	var ink: Color = palette().ink
	return ink if contrast(ink, color) >= contrast(Color.WHITE, color) else Color.WHITE

## Colour roles in tones: the palette, cached until the brand colours change. Keys: p, s, a, x, y (each {main, deep, soft, pale}), cream, ink,
## danger, sky_top, sky_horizon, sea, fog, floor_a / floor_b (the checker), wall, base (stripes that read on the cream), confetti and blocks
## (Arrays of Color; the blocks are darkened until they stand out of the track).
static func palette() -> Dictionary:
	var key := str(TeamCast.brand_colors()) + TeamCast.world_style()
	if key == _key and not _palette.is_empty(): return _palette
	_key = key
	var h := hues()
	var result := {}
	var names := ["p", "s", "a", "x", "y"]
	for i in names.size():
		var main := _brand_tone(h[i])
		result[names[i]] = {"main": main, "deep": Color.from_hsv(h[i], minf(main.s + 0.08, 0.95), 0.72), "soft": Color.from_hsv(h[i], 0.42, 1.0),
			"pale": Color.from_hsv(h[i], 0.17, 1.0)}
	if _brand_hue_count() < 3: result.a = _burnt(h[2])
	result.cream = CREAM
	result.ink = _brand_ink(h[0])
	result.trim = _brand_trim(result.p)
	result.danger = DANGER
	var tiles: Array[Color] = _tiles(result.p.main)
	result.tiles = tiles
	result.signs = _signs(result.p.main, h[0])
	var sky_hue: float = lerpf(h[1], SKY_BLUE, 0.35) if hue_gap(h[1], SKY_BLUE) < 0.12 else h[1] # a blue brand gets a sky-ier blue
	result.sky_top = Color.from_hsv(sky_hue, 0.6, 0.97)
	result.sky_horizon = Color.from_hsv(sky_hue, 0.24, 1.0)
	result.sea = Color.from_hsv(sky_hue, 0.36, 0.98) # a sea with colour in it, so the clouds and the course stand out of it (no white haze)
	result.fog = result.sky_horizon
	# Legibility for any palette: a light track with a visible checker, stripes that read on the cream, hop blocks that stand out of the track.
	var cp: Dictionary = result.p
	result.floor_b = lifted((cp.soft as Color).lerp(CREAM, 0.3), 0.68)
	result.floor_a = against(lifted(Color.from_hsv((cp.main as Color).h, 0.85, 0.95), 0.4), result.floor_b, 1.5) # a saturated track: it stands out of the pale sky
	result.wall = against(cp.main, CREAM, 1.7)
	result.base = against(cp.deep, CREAM, 1.8)
	var blocks: Array[Color] = []
	var confetti: Array[Color] = []
	for name: String in names:
		blocks.append(against_all((result[name] as Dictionary).main, [result.floor_a, result.floor_b], 1.5))
		confetti.append((result[name] as Dictionary).main)
		confetti.append((result[name] as Dictionary).soft)
	confetti.append(Color.WHITE)
	result.blocks = blocks
	result.confetti = confetti
	if TeamCast.world_style() == "night": _night(result)
	_palette = result
	_spec = {}
	return result

## The palette of the night look, in place: the keys of the party palette in dark tones. Roles: p the brand's first colour with colour in it (the lines
## and the trim: full strength, value 1), s the next colour of another hue else the brand's light grey or a silver, a the third colour else an ember tone
## of p, x silver, y a pale tint of p; each in the tones main (bright), deep (dim line), soft and pale. The rest: the void (the brand's near black, else a
## very dark tone of p) tints the sky, the sea, the floors, walls and tiles, which keep their contrast rules (`tiles` one step apart, `blocks` and the
## accent lines far lighter than any floor, the ink dark for the lettering on the accent, `lettering` light for the lettering on dark).
static func _night(result: Dictionary) -> void:
	var found: Array[Color] = []
	for color in TeamCast.brand_colors():
		if color.s < MIN_SATURATION or color.v < MIN_VALUE: continue
		var fresh := true
		for other in found:
			if hue_gap(other.h, color.h) < DISTINCT: fresh = false
		if fresh: found.append(color)
	var lead_hue: float = found[0].h if not found.is_empty() else NIGHT_FALLBACK_HUE
	var lead_sat: float = found[0].s if not found.is_empty() else 0.7
	var dark := Color.from_hsv(lead_hue, 0.45, 0.07)
	for color in TeamCast.brand_colors():
		if _is_dark(color):
			dark = color
			break
	var void_hue := dark.h
	var void_sat := minf(dark.s, 0.5)
	var trim := _brand_trim(result.p)
	if not _has_light_grey(): trim = Color.from_hsv(lead_hue, 0.08, 0.86)
	var silver := {"main": trim, "deep": Color.from_hsv(trim.h, trim.s, trim.v * 0.55), "soft": trim.lerp(Color.WHITE, 0.5), "pale": trim.lerp(Color.WHITE, 0.8)}
	var p := _glow_role(lead_hue, lead_sat)
	result.p = p
	result.s = _glow_role(found[1].h, found[1].s) if found.size() > 1 else silver
	result.a = _glow_role(found[2].h, found[2].s) if found.size() > 2 else _glow_role(fposmod(lead_hue - 0.045, 1.0), 0.8)
	result.x = silver
	result.y = _glow_role(lead_hue, 0.3)
	result.cream = Color.from_hsv(lead_hue, 0.06, 0.95)
	result.lettering = result.cream
	result.trim = trim
	result.sun = NIGHT_SUN.lerp(p.soft, 0.25)
	result.ambient = NIGHT_AMBIENT
	result.sky_top = Color.from_hsv(void_hue, void_sat, 0.035)
	result.sky_horizon = Color.from_hsv(lead_hue, 0.55, 0.16)
	result.sea = Color.from_hsv(void_hue, void_sat, 0.025)
	result.fog = Color.from_hsv(lead_hue, 0.5, 0.1)
	result.floor_a = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.32)
	result.floor_b = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.23)
	result.wall = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.2)
	result.wall2 = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.25)
	result.base = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.09)
	result.ice = Color.from_hsv(result.s.main.h if found.size() > 1 else lead_hue, 0.5, 0.2)
	result.steel_dark = Color.from_hsv(void_hue, minf(void_sat, 0.25), 0.2)
	result.steel = Color.from_hsv(void_hue, minf(void_sat, 0.2), 0.42)
	result.mat = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.1)
	result.support = Color.from_hsv(void_hue, minf(void_sat, 0.3), 0.1)
	var tiles: Array[Color] = [Color.from_hsv(lead_hue, 0.3, 0.11), Color.from_hsv(lead_hue, 0.3, 0.17), Color.from_hsv(lead_hue, 0.3, 0.24)]
	result.tiles = tiles
	result.signs = _signs(p.main, lead_hue)
	var blocks: Array[Color] = [p.main, result.s.main, result.a.main, p.soft, result.y.main, silver.main]
	var embers: Array[Color] = [p.main, p.soft, result.a.main, (result.y as Dictionary).pale, result.cream]
	result.blocks = blocks
	result.confetti = embers

## One role of the night palette from a hue and saturation: main (the accent at full value, lifted towards white where the hue is dark, like blue), deep (dim), soft and pale.
static func _glow_role(hue: float, sat: float) -> Dictionary:
	return {"main": lifted(Color.from_hsv(hue, clampf(sat, 0.45, 0.9), 1.0), 0.34), "deep": lifted(Color.from_hsv(hue, clampf(sat + 0.1, 0.5, 0.95), 0.62), 0.16),
		"soft": Color.from_hsv(hue, 0.32, 1.0), "pale": Color.from_hsv(hue, 0.12, 1.0)}

static func _has_light_grey() -> bool:
	for color in TeamCast.brand_colors():
		if _is_light_grey(color): return true
	return false

## Relative luminance (WCAG) and the contrast ratio of two colours (1 = the same, 21 = black on white).
static func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## `color` darkened (its hue and saturation kept) until it has at least `ratio` contrast to `other`.
static func against(color: Color, other: Color, ratio: float) -> Color:
	var result := color
	for step in 40:
		if contrast(result, other) >= ratio: break
		result = Color.from_hsv(result.h, result.s, result.v * 0.93)
	return result

## `color` darkened until it has at least `ratio` contrast to every colour of `others` at once.
static func against_all(color: Color, others: Array, ratio: float) -> Color:
	var result := color
	for step in 60:
		var ok := true
		for other: Color in others:
			if contrast(result, other) < ratio: ok = false
		if ok: break
		result = Color.from_hsv(result.h, result.s, result.v * 0.95)
	return result

## `color` lightened towards white until its luminance is at least `minimum`.
static func lifted(color: Color, minimum: float) -> Color:
	var result := color
	for step in 40:
		if luminance(result) >= minimum: break
		result = result.lerp(Color.WHITE, 0.1)
	return result

static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)

## The `Surfaces.LOOK` of the party look (same keys, party colours).
static func spec() -> Dictionary:
	var p := palette()
	if not _spec.is_empty(): return _spec
	if night():
		_spec = NightLook.spec(p)
		return _spec
	var cp: Dictionary = p.p
	var cs: Dictionary = p.s
	var ca: Dictionary = p.a
	var cream := _hex(p.cream)
	var blocks: Array = []
	for color: Color in p.blocks: blocks.append(_hex(color))
	var floor_top := {"set": "plastic", "tint": _hex(p.floor_a), "tint2": _hex(p.floor_b), "pattern": 1, "pattern_size": 2.0,
		"tile": 4.0, "detail": 0.1, "rough": 0.9, "rough_add": 0.1, "ao": 0.9}
	var wall := {"set": "plastic", "tint": _hex(p.wall), "tint2": cream, "pattern": 2, "pattern_size": 1.5, "tile": 4.0, "detail": 0.08,
		"rough": 0.9, "rough_add": 0.1, "ao": 0.9, "rim": 0.15}
	var accent_wall := wall.duplicate()
	accent_wall.tint = _hex(against(cs.main, CREAM, 1.7))
	_spec = {
		"surfaces": {
			"floor": floor_top,
			"base": {"set": "plastic", "tint": _hex(p.base), "tint2": cream, "pattern": 3, "pattern_size": 0.75, "tile": 4.0, "detail": 0.08,
				"rough": 0.8, "rough_add": 0.1, "ao": 0.7, "rim": 0.1},
			"wall": wall,
			"wall_brand": accent_wall,
			"block": {"set": "plastic", "tint": "#ffffff", "tile": 3.0, "detail": 0.08, "rough": 0.7, "rough_add": 0.05, "vtint": 1.0, "ao": 0.9, "rim": 0.3},
			"ice": {"set": "plastic", "tint": _hex(cs.pale), "tile": 3.0, "detail": 0.15, "rough": 0.25, "ao": 0.6, "spec": 0.8, "rim": 0.2},
			"mover": {"set": "plastic", "tint": _hex(ca.deep), "tint2": cream, "pattern": 3, "pattern_size": 0.25, "tile": 3.0, "detail": 0.08,
				"rough": 0.7, "ao": 0.0, "rim": 0.2},
			"mover_top": {"set": "plastic", "tint": _hex(against(ca.main, CREAM, 1.4)), "tint2": cream, "pattern": 1, "pattern_size": 0.5, "tile": 3.0, "detail": 0.08,
				"rough": 0.7, "ao": 0.0, "rim": 0.1},
			"danger": {"set": "plastic", "tint": _hex(p.danger), "tile": 3.0, "detail": 0.08, "rough": 0.55, "ao": 0.0, "rim": 0.3},
			"trim": {"set": "plastic", "tint": "#fff5e6", "tile": 2.0, "detail": 0.1, "rough": 0.6, "ao": 0.0, "rim": 0.1},
			"steel": {"set": "plastic", "tint": cream, "tile": 1.0, "detail": 0.08, "rough": 0.6, "ao": 0.0, "rim": 0.1},
			"room_wall": wall,
			"room_floor": floor_top,
			"ceiling": floor_top,
		},
		"block_colors": blocks,
		"radius": {"floor": 0.05, "base": 0.05, "wall": 0.12, "block": 0.3, "ice": 0.08, "mover": 0.12, "danger": 0.1, "trim": 0.0},
		"segments": {"block": 3, "mover": 2},
		"band": [1.0, 1.3],
		"signage": {"frame": _hex(cp.soft), "frame_metal": 0.0, "frame_rough": 0.5, "board": "#fffaf2", "post": _hex(cs.main), "post_metal": 0.0,
			"mat": "#fffdf8", "text": _hex(p.ink)},
		"room": {"number": _hex(p.ink)},
		"light": {"sun": _hex(SUN), "sun_energy": 1.3, "sun_dir": [-0.4, -0.78, -0.48], "shadow_blur": 2.0,
			"sky_top": _hex(p.sky_top), "sky_horizon": _hex(p.sky_horizon), "ground": _hex(p.sea), "ambient_energy": 0.45,
			"fog": _hex(p.fog), "fog_density": 0.0004, "background": 1.0, "sky_background": true, "lamp": "#ffffff", "lamp_energy": 1.0,
			"tonemap": "aces", "contrast": 1.0, "white": 6.0, "exposure": 0.72},
	}
	return _spec
