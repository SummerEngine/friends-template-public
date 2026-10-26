extends RefCounted
## The colours of a course in the candy look (levels 29-32, the lobby yard): THREE hues, each in three tones, plus near white and a dark accent
## (docs/party-show.md "The candy palette"; hue families in style/candy_look.gd COURSE_HUES). Roles, the same as the brand palette's (style/party_look.gd hues P, S, A):
##   p  the floor and its main feature hue: the flat tone `main`, the lighter `light` (second floor tone, stripes, lines), the deeper `deep` (shadow side of a feature)
##   s  walls, door frames, pillars, the big pillow pieces
##   a  accents: amber rails, hop blocks, spinner discs, stepping stones
## A cast with brand colours gives its first three hues to P, S, A (flat, bright: saturation 0.88, value 0.96 for `main`); a cast without any gets the default: royal blue floor,
## purple walls, amber accents. Characters stay the most colourful thing on screen because the course never has more than these three hues; the world around it (sky, meadow, sea) and the
## hazard colour are NOT brand coloured (style/candy_world.gd, the props' own colours).
const Party := preload("res://style/party_look.gd")
const TeamCast := preload("res://style/team_cast.gd")
const CandyLook := preload("res://style/candy_look.gd")

const MAIN_SATURATION := 0.97
const MAIN_VALUE := 0.96
const LIGHT_SATURATION := 0.55
const DEEP_SATURATION := 0.9
const DEEP_VALUE := 0.78
const WHITE := Color("#f8f4f3")
const DARK := Color("#473255")
const DARK_INK := Color("#1e1828")             ## the chequered flag's dark squares
const DEFAULT_P := {"main": Color("#0aa4ff"), "light": Color("#3dd1f4"), "deep": Color("#0566c8")}   ## authored with R near 0: under the rig a lit floor lands near #0095FF
const DEFAULT_S := {"main": Color("#b254f8"), "light": Color("#c868fa"), "deep": Color("#5a16c0")}
const DEFAULT_A := {"main": Color("#ff8000"), "light": Color("#ffb21c"), "deep": Color("#e84a00")}

static var _key := ""
static var _scheme := {}

## The scheme of the current cast: {p, s, a: {main, light, deep}, white, dark, ink}, cached until the brand colours change.
static func scheme() -> Dictionary:
	var key := str(TeamCast.brand_colors())
	if key == _key and not _scheme.is_empty(): return _scheme
	_key = key
	var branded := not TeamCast.brand_colors().is_empty() and _has_colour()
	var result := {"white": WHITE, "dark": DARK, "ink": DARK_INK}
	if branded:
		var hues := Party.hues()
		result.p = _tones(hues[0])
		result.s = _tones(hues[1])
		result.a = _tones(hues[2])
	else:
		result.p = DEFAULT_P
		result.s = DEFAULT_S
		result.a = DEFAULT_A
	_scheme = result
	return result

## Whether any brand colour has colour in it (the roles then follow the brand).
static func _has_colour() -> bool:
	for color in TeamCast.brand_colors():
		if color.s >= Party.MIN_SATURATION and color.v >= Party.MIN_VALUE: return true
	return false

## One hue in the three tones of the course: flat, saturated, bright.
static func _tones(hue: float) -> Dictionary:
	return {"main": Color.from_hsv(hue, MAIN_SATURATION, MAIN_VALUE), "light": Color.from_hsv(hue, LIGHT_SATURATION, 1.0), "deep": Color.from_hsv(hue, DEEP_SATURATION, DEEP_VALUE)}
