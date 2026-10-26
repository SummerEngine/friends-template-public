extends RefCounted
## The show's banners and the countdown digits, drawn into any CanvasItem (the API every HUD piece calls; the look is in here only). Pure drawing: polygons (vertex colours for the
## gradients) and Lilita One letters, no textures; every call is cheap enough for every frame (the spiky outlines are built once per size and cached).
##   ShowBanner.draw(ci, "victory", "VICTORY", age, centre, wide)             a banner `age` s after it came up (pops in, idles, leaves by itself)
##   ShowBanner.draw(ci, "title", "CIRCUIT BREAKER", age, centre, wide, 1.0, "Round 2")   the round's wide ribbon banner with a smaller line under the name
##   ShowBanner.countdown(ci, "3", age, centre, cap_px)                         a chunky digit (or the GO word with `go` true) popping in
## kinds: victory (yellow-orange, small crown), champion (gold, big crown and sparkles), qualified (mint, tick), eliminated (grey, cross, cracked, tilted), failure (grey, sagging pop),
## timesup (orange-red, stopwatch), title (the wide ribbon), and the show's items (modes/show/items/): item (blue), alert (red-pink, an item that hits you), boon (lime, something good happens to you). Words are drawn in capitals and always fit: the lettering shrinks until the banner is `wide` px across at most (the pop
## overshoots to 1.25 x `wide` for a moment), and the plate hugs the words (it is never wider than `wide`, nor taller than `height_of`).
## Timeline (age = seconds since the banner came up): pop-in 0 -> 1.25 x at 0.10 s -> 0.92 x at 0.19 s -> 1.0 at 0.28 s with a rotation wobble and the letters wobbling one after the other;
## then a soft bob and a shine sweeping across the plate every 2.4 s; it holds for `life(kind)` seconds and then LEAVES BY ITSELF over LEAVE s (grows 20 % and fades out; draws nothing
## once `age` passes `total(kind)`). So the caller just keeps counting `age` and may stop drawing at `total(kind)`; `alpha` is the caller's own extra fade and multiplies in.
const ShowTheme := preload("res://client/show_theme.gd")

const KINDS := ["victory", "champion", "qualified", "eliminated", "failure", "timesup", "title", "item", "alert", "boon"]
const LEAVE := 0.35 ## s, the leave animation after the hold
const GO_TILT := -0.12 ## rad, the GO word's tilt
const TRACKING := 0.05 ## extra space between letters, in em
const PAD := 0.6 ## the plate's room beyond the letters at each end, in capital heights

## Per kind: gradient (top, body, low), rim, deep (the drop shadow), the letters' face / shade / edge / extrusion colours, the hold in seconds, the plate's tilt (rad), the arch of the word
## (negative: the middle rides up; positive: it sags), the squash and droop of a sagging plate, the icon over the plate, the outline's superellipse exponent and spike pitch (x the plate's half
## height), the seed of its irregular spikes, the pop-in (age, scale) keys, and whether it is cracked.
const LOOK := {
	"victory": {"top": Color("ffec8c"), "body": Color("fcd034"), "low": Color("f7b21e"), "rim": Color("ee9210"), "deep": Color("7c3d05"),
		"face": Color("fffaf0"), "shade": Color("e6d1a0"), "edge": Color("c4650a"), "ext": Color("9b4f08"), "life": 2.4, "tilt": -0.035, "arch": -0.06, "sag": 0.0, "squash": 0.0,
		"icon": "crown", "n": 3.4, "pitch": 0.5, "seed": 3, "pop": [0.0, 0.0, 0.11, 1.28, 0.22, 0.9, 0.35, 1.0], "crack": false},
	"champion": {"top": Color("fff0a8"), "body": Color("f6c22a"), "low": Color("e39a14"), "rim": Color("c9731a"), "deep": Color("6e3606"),
		"face": Color("fffbe8"), "shade": Color("efd9a2"), "edge": Color("b5640f"), "ext": Color("8a4608"), "life": 4.0, "tilt": 0.0, "arch": -0.09, "sag": 0.0, "squash": 0.0,
		"icon": "royal", "n": 2.5, "pitch": 0.46, "seed": 11, "pop": [0.0, 0.0, 0.12, 1.3, 0.24, 0.88, 0.38, 1.0], "crack": false},
	"qualified": {"top": Color("d6ffe9"), "body": Color("7ee8b6"), "low": Color("49cfa0"), "rim": Color("2f9f86"), "deep": Color("124f45"),
		"face": Color("fbfffb"), "shade": Color("cdeedd"), "edge": Color("1f8571"), "ext": Color("17695a"), "life": 2.2, "tilt": -0.03, "arch": -0.05, "sag": 0.0, "squash": 0.0,
		"icon": "tick", "n": 2.7, "pitch": 0.5, "seed": 7, "pop": [0.0, 0.0, 0.11, 1.26, 0.22, 0.91, 0.35, 1.0], "crack": false},
	"eliminated": {"top": Color("dcdcd8"), "body": Color("b4b4b1"), "low": Color("9a9a98"), "rim": Color("6a6a6e"), "deep": Color("27272b"),
		"face": Color("f1f0ea"), "shade": Color("cfcec8"), "edge": Color("56565a"), "ext": Color("3b3b40"), "life": 2.4, "tilt": 0.05, "arch": 0.04, "sag": 0.0, "squash": 0.0,
		"icon": "cross", "n": 2.7, "pitch": 0.5, "seed": 5, "pop": [0.0, 0.2, 0.12, 1.1, 0.24, 0.97, 0.34, 1.0], "crack": true},
	"failure": {"top": Color("c7cad4"), "body": Color("9fa4b1"), "low": Color("858a99"), "rim": Color("5c6070"), "deep": Color("22242c"),
		"face": Color("eceef2"), "shade": Color("c3c7d2"), "edge": Color("4a4e5c"), "ext": Color("353844"), "life": 2.6, "tilt": -0.06, "arch": 0.16, "sag": 0.1, "squash": 0.07,
		"icon": "none", "n": 2.7, "pitch": 0.5, "seed": 9, "pop": [0.0, 0.0, 0.16, 1.1, 0.34, 0.9, 0.55, 0.96], "crack": true},
	"timesup": {"top": Color("ffc08a"), "body": Color("ff8a3d"), "low": Color("e5484d"), "rim": Color("b32a22"), "deep": Color("5c130d"),
		"face": Color("fff6ea"), "shade": Color("f0cdb2"), "edge": Color("9c2a1a"), "ext": Color("7a1d14"), "life": 2.2, "tilt": 0.03, "arch": -0.04, "sag": 0.0, "squash": 0.0,
		"icon": "watch", "n": 2.7, "pitch": 0.5, "seed": 13, "pop": [0.0, 0.0, 0.11, 1.28, 0.22, 0.9, 0.35, 1.0], "crack": false},
	"item": {"top": Color("c4dbff"), "body": Color("5a8cff"), "low": Color("3563e6"), "rim": Color("1f45b0"), "deep": Color("0a1a52"),
		"face": Color("f6f9ff"), "shade": Color("cddfff"), "edge": Color("1b3a9c"), "ext": Color("132a78"), "life": 1.3, "tilt": -0.03, "arch": -0.05, "sag": 0.0, "squash": 0.0,
		"icon": "none", "n": 2.7, "pitch": 0.5, "seed": 21, "pop": [0.0, 0.0, 0.11, 1.28, 0.22, 0.9, 0.35, 1.0], "crack": false},
	"alert": {"top": Color("ffb8c8"), "body": Color("ff5580"), "low": Color("df2f62"), "rim": Color("a31a48"), "deep": Color("4a0a22"),
		"face": Color("fff6f8"), "shade": Color("f7c9d5"), "edge": Color("931642"), "ext": Color("6a0f30"), "life": 1.4, "tilt": 0.04, "arch": -0.04, "sag": 0.0, "squash": 0.0,
		"icon": "none", "n": 2.4, "pitch": 0.44, "seed": 23, "pop": [0.0, 0.0, 0.1, 1.34, 0.21, 0.88, 0.34, 1.0], "crack": false},
	"boon": {"top": Color("ecffb4"), "body": Color("b4f23c"), "low": Color("72cc20"), "rim": Color("3f8f12"), "deep": Color("1d4a07"),
		"face": Color("fffff2"), "shade": Color("e8f2c6"), "edge": Color("3a7d10"), "ext": Color("2b6209"), "life": 1.3, "tilt": -0.04, "arch": -0.07, "sag": 0.0, "squash": 0.0,
		"icon": "none", "n": 3.0, "pitch": 0.5, "seed": 27, "pop": [0.0, 0.0, 0.11, 1.3, 0.22, 0.9, 0.35, 1.0], "crack": false},
	"title": {"top": Color("ffec8c"), "body": Color("fcd034"), "low": Color("f7b21e"), "rim": Color("ee9210"), "deep": Color("6f3706"),
		"face": Color("fffaf0"), "shade": Color("e6d1a0"), "edge": Color("c4650a"), "ext": Color("9b4f08"), "life": 2.6, "tilt": 0.0, "arch": -0.03, "sag": 0.0, "squash": 0.0,
		"icon": "none", "n": 4.2, "pitch": 0.5, "seed": 17, "pop": [0.0, 0.0, 0.11, 1.22, 0.22, 0.93, 0.35, 1.0], "crack": false},
}

## The countdown's lettering: cream with a mint-teal edge and a dark teal rim, extruded down.
const DIGIT := {"face": Color("fbf6ea"), "shade": Color("d3ecdf"), "edge": Color("3fc7ab"), "ext": Color("1b6c60"), "outer": Color("17564c")}

static var _shapes := {}

# ------------------------------------------------------------------ timeline

## The width of the SMALL banners of the show's experiments (item and event banners, the manager's rules, the tandem): about half the show's own big ones.
static func small_wide(view_w: float, k: float) -> float:
	return minf(view_w * 0.27, 440.0 * k)

## Seconds a banner of `kind` holds before it starts to leave.
static func life(kind: String) -> float:
	return float(LOOK.get(kind, LOOK["victory"]).life)

## Seconds after which a banner of `kind` has left (nothing is drawn any more).
static func total(kind: String) -> float:
	return life(kind) + LEAVE

## The vertical room a banner of `kind` takes at most for `wide` px (plate and the icon on it, a title with its extra line).
static func height_of(kind: String, wide: float, has_line := false) -> float:
	var cap := wide * 0.135
	var plate := cap * 1.84 + (cap * 0.63 if has_line else 0.0)
	return plate + (cap * 0.6 if str(LOOK.get(kind, LOOK["victory"]).icon) != "none" else 0.0)

## Piecewise smooth interpolation through `keys` [t0, v0, t1, v1, ...] (each leg eased).
static func _keys(age: float, keys: Array) -> float:
	if age <= float(keys[0]): return float(keys[1])
	for i in range(2, keys.size(), 2):
		if age < float(keys[i]):
			var t := (age - float(keys[i - 2])) / (float(keys[i]) - float(keys[i - 2]))
			return lerpf(float(keys[i - 1]), float(keys[i + 1]), t * t * (3.0 - 2.0 * t))
	return float(keys[keys.size() - 1])

static func _hash(index: int, seed_value: int) -> float:
	return fposmod(sin(float(index) * 12.9898 + float(seed_value) * 78.233) * 43758.5453, 1.0)

## The digit's pop (the stage HUD's timing): 1.3 x for 0.10 s, down to 0.67 x at 0.13 s, 1.08 x at 0.20 s, settled at 0.27 s.
static func _digit_pop(age: float) -> float:
	if age < 0.10: return 1.3
	if age < 0.13: return lerpf(1.3, 0.67, (age - 0.10) / 0.03)
	if age < 0.20: return lerpf(0.67, 1.08, (age - 0.13) / 0.07)
	return lerpf(1.08, 1.0, clampf((age - 0.20) / 0.07, 0.0, 1.0))

## GO's pop: 0.63 x for the first frames, 1.15 x from 0.03 s, settled at 0.23 s.
static func _go_pop(age: float) -> float:
	if age < 0.03: return 0.63
	if age < 0.12: return 1.15
	return lerpf(1.15, 1.0, clampf((age - 0.12) / 0.11, 0.0, 1.0))

# ------------------------------------------------------------------ the banner

## Draws banner `kind` with `words` (and an optional smaller `line` under it) centred on `centre`, at most `wide` px across, `age` s after it popped in; `alpha` fades it. `hold` keeps it on screen for ever
## (the menus' logo: it pops in, then bobs and shines; it never leaves).
static func draw(ci: CanvasItem, kind: String, words: String, age: float, centre: Vector2, wide: float, alpha := 1.0, line := "", hold := false) -> void:
	if age < 0.0 or alpha <= 0.0 or wide < 8.0 or words == "": return
	var look: Dictionary = LOOK.get(kind, LOOK["victory"])
	var out := 0.0 if hold else clampf((age - float(look.life)) / LEAVE, 0.0, 1.0)
	if out >= 1.0: return
	var a := alpha * (1.0 - out * out)
	var s := _keys(age, look.pop) * (1.0 + 0.2 * (1.0 - (1.0 - out) * (1.0 - out)))
	if s < 0.03: return
	words = words.to_upper()
	line = line.to_upper()
	var lay := _layout(kind, words, line, wide)
	var hx: float = lay.hx
	var hy: float = lay.hy
	var cap: float = lay.cap
	var settled := clampf((age - 0.3) / 0.3, 0.0, 1.0)
	s *= 1.0 + 0.012 * sin(age * 4.0) * settled
	var angle := float(look.tilt) + sin(age * 26.0) * 0.07 * exp(-age * 7.0) + sin(age * 1.7) * 0.008 * settled
	var bob := sin(age * 3.0) * hy * 0.025 * settled
	var grow := clampf(age / 0.6, 0.0, 1.0)
	var droop := float(look.sag) * hy * grow
	var squash := 1.0 - float(look.squash) * grow
	var xf := Transform2D(angle, Vector2(s, s * squash), 0.0, centre + Vector2(0.0, bob + droop))
	var shape := _shape(hx, hy, float(look.n), float(look.pitch), int(look.seed))
	var outer: PackedVector2Array = shape.outer
	var body: PackedVector2Array = shape.body
	var tips: int = shape.tips
	var top: Color = look.top
	var mid: Color = look.body
	var low: Color = look.low
	var rim: Color = look.rim
	var deep: Color = look.deep
	ci.draw_set_transform_matrix(xf)
	if kind == "title": _tails(ci, hx, hy, rim, deep, a)
	ci.draw_colored_polygon(shape.shadow, Color(deep, 0.42 * a))
	ci.draw_polygon(outer, _vertical(outer, hy, rim.lightened(0.18), rim.darkened(0.25), rim, a))
	ci.draw_polygon(body, _vertical(body, hy, top, low, mid, a))
	var upper := PackedVector2Array()
	for k in range(tips + 1, tips * 2): upper.append(body[k] + Vector2(0.0, hy * 0.07))
	ci.draw_polyline(upper, Color(top.lightened(0.55), 0.7 * a), maxf(hy * 0.05, 1.5), true)
	var lower := PackedVector2Array()
	for k in range(1, tips): lower.append(body[k] + Vector2(0.0, -hy * 0.05))
	ci.draw_polyline(lower, Color(low.darkened(0.3), 0.4 * a), maxf(hy * 0.05, 1.5), true)
	_shine(ci, body, hx, hy, age, a)
	if bool(look.crack): _crack(ci, hx, hy, deep, age, a)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	_icon(ci, str(look.icon), xf, angle, hx, hy, age, a, look)
	# the letters, one by one (each with its own wobble and a little jitter), laid out along the word's arch
	var size: float = lay.size
	var fs := maxi(8, roundi(size * s / 8.0) * 8)
	var ratio := size / float(fs)
	var font := ShowTheme.font()
	var track := size * TRACKING
	var total_w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * ratio + track * float(words.length() - 1)
	var seed_value := int(look.seed)
	var style := {"face": look.face, "shade": look.shade, "edge": look.edge, "ext": look.ext, "slant": 0.03, "e": 0.15, "depth": 0.09}
	for i in words.length():
		var ch := words[i]
		if ch == " ": continue
		var before := font.get_string_size(words.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var wide_ch := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var local_x := -total_w * 0.5 + (before + wide_ch * 0.5) * ratio + track * float(i)
		var u := local_x / maxf(total_w * 0.5, 1.0)
		var jitter := _hash(i, seed_value)
		var la := age - 0.018 * float(i)
		var y: float = lay.main_y + cap * (float(look.arch) * (1.0 - u * u) + (jitter - 0.5) * 0.07)
		var rot := (jitter - 0.5) * 0.09 + u * float(look.sag) * 0.6
		if la > 0.0: rot += sin(la * 26.0) * 0.12 * exp(-la * 7.0)
		_glyph(ci, ch, xf * Vector2(local_x, y), angle + rot, s * ratio, fs, style, a)
	if line != "":
		var lsize: float = lay.line_size
		var lfs := maxi(8, roundi(lsize * s / 8.0) * 8)
		var lstyle := {"face": look.face, "shade": look.shade, "edge": look.edge, "ext": look.ext, "slant": 0.03, "e": 0.17, "depth": 0.07}
		_glyph(ci, line, xf * Vector2(0.0, lay.line_y), angle, s * lsize / float(lfs), lfs, lstyle, a)

## Where everything sits for these words at `wide` px: letter size, half sizes of the plate, the rows of the main words and of the line.
static func _layout(kind: String, words: String, line: String, wide: float) -> Dictionary:
	var unit_w := ShowTheme.width(words, 100.0) / 100.0 + TRACKING * float(words.length() - 1)
	var room := wide * (0.86 if kind == "title" else 1.0) * 0.5
	var cap_max := wide * 0.135
	var size := minf(cap_max / ShowTheme.CAP, room / (unit_w * 0.5 + ShowTheme.CAP * PAD))
	var cap := size * ShowTheme.CAP
	var text_w := unit_w * size
	var line_size := 0.0
	var line_w := 0.0
	if line != "":
		var unit_l := ShowTheme.width(line, 100.0) / 100.0
		line_size = minf(size * 0.5, (room - cap * PAD) * 2.0 / maxf(unit_l, 0.01))
		line_w = unit_l * line_size
	var base := cap * 1.0
	var extra := line_size * ShowTheme.CAP * 1.5 if line != "" else 0.0
	var hy := base + extra * 0.5
	var hx := minf(maxf(maxf(text_w, line_w) * 0.5 + cap * PAD, hy * 1.5), room)
	var main_y := -hy + base
	var line_y := hy - extra * 0.5 - hy * 0.1
	return {"size": size, "cap": cap, "hx": hx, "hy": hy, "main_y": main_y, "line_size": line_size, "line_y": line_y}

## Vertex colours for `points` from `top` (the plate's top) through `mid` to `low` (its bottom).
static func _vertical(points: PackedVector2Array, hy: float, top: Color, low: Color, mid: Color, alpha: float) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(points.size())
	for k in points.size():
		var t := clampf((points[k].y / hy + 1.0) * 0.5, 0.0, 1.0)
		var c := top.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(low, (t - 0.5) * 2.0)
		colors[k] = Color(c, c.a * alpha)
	return colors

## The spiky outline (a squarish ellipse of half sizes hx, hy with irregular spikes: tips on the curve, dents inside it, a pointed tip at each end), its inset body, its shadow; cached.
static func _shape(hx: float, hy: float, n: float, pitch: float, seed_value: int) -> Dictionary:
	var key := Vector4i(roundi(hx), roundi(hy), roundi(n * 10.0), seed_value * 100 + roundi(pitch * 100.0))
	if _shapes.has(key): return _shapes[key]
	if _shapes.size() > 48: _shapes.clear()
	var count := 240
	var curve := PackedVector2Array()
	var run := PackedFloat32Array()
	var length := 0.0
	for i in count + 1:
		var t := TAU * float(i) / float(count)
		var c := cos(t)
		var s := sin(t)
		curve.append(Vector2(hx * signf(c) * pow(absf(c), 2.0 / n), hy * signf(s) * pow(absf(s), 2.0 / n)))
		if i > 0: length += curve[i].distance_to(curve[i - 1])
		run.append(length)
	var tips := clampi(roundi(length / (hy * pitch * 2.5) / 2.0) * 2, 8, 36)
	var made := _spikes(curve, run, length, count, tips, hy, seed_value, true)
	if not _drawable(made): made = _spikes(curve, run, length, count, tips, hy, seed_value, false) # a rim or plate that crosses itself at some widths: the even spikes
	if not _drawable(made):
		var inset := PackedVector2Array()
		for p in made.outer: inset.append(p * 0.94)
		made.body = inset # the plate is the rim shrunk about the centre (as many points as the rim)
	_shapes[key] = made
	return made

static func _drawable(made: Dictionary) -> bool:
	return not Geometry2D.triangulate_polygon(made.outer).is_empty() and not Geometry2D.triangulate_polygon(made.body).is_empty()

## The spiky rim (`outer`), the plate (`body`) and the drop shadow along the curve; `jitter` varies the spikes' depth per spike.
static func _spikes(curve: PackedVector2Array, run: PackedFloat32Array, length: float, count: int, tips: int, hy: float, seed_value: int, jitter: bool) -> Dictionary:
	var outer := PackedVector2Array()
	var body := PackedVector2Array()
	var at := 0
	for k in tips * 2:
		var want := length * float(k) / float(tips * 2)
		while at < count - 1 and run[at + 1] < want: at += 1
		var span := maxf(run[at + 1] - run[at], 0.0001)
		var p := curve[at].lerp(curve[at + 1], clampf((want - run[at]) / span, 0.0, 1.0))
		var tangent := curve[at + 1] - curve[at]
		var normal := Vector2(tangent.y, -tangent.x).normalized()
		var noise := _hash(k, seed_value) if jitter else 0.5
		if k % 2 == 0:
			outer.append(p + normal * hy * 0.2 * noise)
			body.append(p - normal * hy * 0.15)
		else:
			var depth := hy * (0.2 + 0.22 * noise)
			outer.append(p - normal * depth)
			body.append(p - normal * (depth + hy * 0.05))
	var shadow := PackedVector2Array()
	for p in outer: shadow.append(p + Vector2(0.0, hy * 0.14))
	return {"outer": outer, "body": body, "shadow": shadow, "tips": tips}

## A shine sweeping over the plate (clipped to the plate's body), once every 2.4 s from 0.3 s on.
static func _shine(ci: CanvasItem, body: PackedVector2Array, hx: float, hy: float, age: float, alpha: float) -> void:
	var phase := fposmod(age - 0.3, 2.4)
	if age < 0.3 or phase > 0.55: return
	var x := lerpf(-hx * 1.15, hx * 1.15, phase / 0.55)
	var band := PackedVector2Array([Vector2(x - hx * 0.05 + hy * 0.4, -hy * 1.2), Vector2(x + hx * 0.07 + hy * 0.4, -hy * 1.2), Vector2(x + hx * 0.07 - hy * 0.4, hy * 1.2), Vector2(x - hx * 0.05 - hy * 0.4, hy * 1.2)])
	for piece in Geometry2D.intersect_polygons(body, band):
		if piece.size() >= 3: ci.draw_colored_polygon(piece, Color(1.0, 1.0, 1.0, 0.36 * alpha))

## A crack zig-zagging down through the plate (grey kinds), appearing 0.1 s in.
static func _crack(ci: CanvasItem, hx: float, hy: float, deep: Color, age: float, alpha: float) -> void:
	var show := clampf((age - 0.1) / 0.15, 0.0, 1.0)
	if show <= 0.0: return
	var spots := [Vector2(-0.06, -0.95), Vector2(-0.14, -0.55), Vector2(0.0, -0.3), Vector2(-0.1, 0.02), Vector2(0.09, 0.32), Vector2(0.0, 0.62), Vector2(0.07, 0.95)]
	var line := PackedVector2Array()
	var glint := PackedVector2Array()
	for spot: Vector2 in spots:
		var at := Vector2(spot.x * hy * 1.4 + hx * 0.18, spot.y * hy * 0.92)
		line.append(at)
		glint.append(at + Vector2(hy * 0.035, 0.0))
	ci.draw_polyline(line, Color(deep, 0.75 * alpha * show), maxf(hy * 0.05, 1.5), true)
	ci.draw_polyline(glint, Color(1.0, 1.0, 1.0, 0.3 * alpha * show), maxf(hy * 0.02, 1.0), true)

## The ribbon's swallow tails behind the title plate (drawn in the plate's local frame, before it).
static func _tails(ci: CanvasItem, hx: float, hy: float, rim: Color, deep: Color, alpha: float) -> void:
	for side in [-1.0, 1.0]:
		var tail := PackedVector2Array([Vector2(side * (hx - hy * 0.6), hy * 0.05), Vector2(side * (hx + hy * 0.75), hy * 0.14), Vector2(side * (hx + hy * 0.5), hy * 0.58),
			Vector2(side * (hx + hy * 0.75), hy * 1.02), Vector2(side * (hx - hy * 0.6), hy * 0.92)])
		var back := PackedVector2Array()
		for p in tail: back.append(p + Vector2(0.0, hy * 0.1))
		ci.draw_colored_polygon(back, Color(deep, 0.5 * alpha))
		ci.draw_colored_polygon(tail, Color(rim.darkened(0.12), alpha))
		var fold := PackedVector2Array([Vector2(side * (hx - hy * 0.6), hy * 0.05), Vector2(side * (hx + hy * 0.75), hy * 0.14), Vector2(side * (hx + hy * 0.7), hy * 0.28), Vector2(side * (hx - hy * 0.6), hy * 0.2)])
		ci.draw_colored_polygon(fold, Color(rim.lightened(0.2), alpha))

# ------------------------------------------------------------------ icons

## The icon over the plate (in world space: `xf` is the plate's transform), popping in a moment after the plate.
static func _icon(ci: CanvasItem, icon: String, xf: Transform2D, angle: float, hx: float, hy: float, age: float, alpha: float, look: Dictionary) -> void:
	if icon == "none": return
	var pop := _keys(age - 0.1, [0.0, 0.0, 0.1, 1.3, 0.2, 0.9, 0.3, 1.0])
	if pop < 0.03: return
	var scale := xf.get_scale().x
	var rim: Color = look.rim
	var deep: Color = look.deep
	var at := xf * Vector2(hx * 0.04 if icon == "crown" else 0.0, -hy * (0.74 if icon == "crown" else 0.94 if icon == "royal" else 1.0 if icon == "watch" else 0.9))
	var r := hy * scale * pop
	match icon:
		"crown":
			ShowTheme.crown(ci, at, r * 1.15, ShowTheme.CREAM, rim, alpha, angle - 0.12)
		"royal":
			_royal(ci, at, r * 1.5, angle, alpha)
			for k in 3:
				var star_at := xf * Vector2([-0.86, 0.9, 0.5][k] * hx, [-0.7, -0.45, 0.95][k] * hy)
				var pulse := 0.65 + 0.35 * sin(age * 5.0 + float(k) * 2.1)
				_star(ci, star_at, hy * scale * 0.2 * pulse * pop, Color("fff6c8"), alpha * (0.6 + 0.4 * pulse))
		"tick", "cross":
			var disc: Color = look.body
			ci.draw_circle(at + Vector2(0.0, r * 0.08), r * 0.4, Color(deep, 0.5 * alpha))
			ci.draw_circle(at, r * 0.4, Color(rim, alpha))
			ci.draw_circle(at, r * 0.32, Color(ShowTheme.CREAM, alpha))
			var ink := Color(rim.darkened(0.15), alpha)
			var w := r * 0.11
			if icon == "tick":
				ci.draw_polyline(PackedVector2Array([at + Vector2(-r * 0.17, r * 0.0), at + Vector2(-r * 0.04, r * 0.13), at + Vector2(r * 0.19, -r * 0.14)]), Color(disc.darkened(0.3), alpha), w, true)
			else:
				ci.draw_line(at + Vector2(-r * 0.13, -r * 0.13), at + Vector2(r * 0.13, r * 0.13), ink, w, true)
				ci.draw_line(at + Vector2(-r * 0.13, r * 0.13), at + Vector2(r * 0.13, -r * 0.13), ink, w, true)
		"watch":
			var shake := sin(age * 38.0) * 0.18 * exp(-age * 5.0) * (1.0 if age > 0.25 else 0.0) + sin(age * 2.0) * 0.03
			ci.draw_set_transform_matrix(Transform2D(angle + shake, Vector2.ONE, 0.0, at))
			ShowTheme.stopwatch(ci, Vector2(0.0, r * 0.06), r * 0.7, deep, alpha)
			ShowTheme.stopwatch(ci, Vector2.ZERO, r * 0.6, ShowTheme.CREAM, alpha)
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## A gold crown with jewels (the champion's), base centre at `base`, `wide` px across.
static func _royal(ci: CanvasItem, base: Vector2, wide: float, angle: float, alpha: float) -> void:
	var h := wide * 0.72
	var shape := PackedVector2Array([Vector2(-0.5, 0.0), Vector2(-0.52, -0.62), Vector2(-0.26, -0.36), Vector2(0.0, -1.0), Vector2(0.26, -0.36), Vector2(0.52, -0.62), Vector2(0.5, 0.0)])
	var big := PackedVector2Array()
	var face := PackedVector2Array()
	for p in shape:
		big.append(Vector2(p.x * wide, p.y * h) * 1.0)
		face.append(Vector2(p.x * wide * 0.86, p.y * h * 0.88 - h * 0.04))
	ci.draw_set_transform_matrix(Transform2D(angle - 0.06, Vector2.ONE, 0.0, base))
	ci.draw_colored_polygon(big, Color("a85a0c", alpha))
	ci.draw_polygon(face, _vertical(face, h, Color("fff1a0", alpha), Color("e8a014", alpha), Color("f8cc32", alpha), 1.0))
	ci.draw_rect(Rect2(Vector2(-wide * 0.5, -h * 0.2), Vector2(wide, h * 0.2)), Color("c97a10", alpha))
	ci.draw_rect(Rect2(Vector2(-wide * 0.5, -h * 0.2), Vector2(wide, h * 0.05)), Color("f8d460", alpha))
	var jewels := [Color("e5484d"), Color("3d7bff"), Color("e5484d")]
	for k in 3: ci.draw_circle(Vector2((float(k) - 1.0) * wide * 0.3, -h * 0.1), wide * 0.055, Color(jewels[k], alpha))
	for p in [shape[1], shape[3], shape[5]]: ci.draw_circle(Vector2(p.x * wide, p.y * h), wide * 0.06, Color("fffbe8", alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## A four-pointed sparkle.
static func _star(ci: CanvasItem, at: Vector2, radius: float, color: Color, alpha: float) -> void:
	if radius < 1.0: return
	var points := PackedVector2Array()
	for k in 8:
		var t := TAU * float(k) / 8.0 - PI * 0.5
		points.append(at + Vector2(cos(t), sin(t)) * radius * (1.0 if k % 2 == 0 else 0.28))
	ci.draw_colored_polygon(points, Color(color, alpha))

# ------------------------------------------------------------------ letters

## One chunky letter or word: an extrusion below it (`ext`), the edge outline (`edge`), a `shade` face with the light `face` face offset up and left over it (the bevel: a darker rim at
## the bottom right), centred on `at` (world), turned by `angle`, scaled by `res` (the small remainder between the quantised font size `fs` and the wanted size). Style: slant, e (the
## outline in em), depth (the extrusion in em), optional outer (a dark rim round the edge, the countdown's).
static func _glyph(ci: CanvasItem, words: String, at: Vector2, angle: float, res: float, fs: int, style: Dictionary, alpha: float) -> void:
	var font := ShowTheme.font()
	var m := Transform2D(angle, Vector2.ONE * res, 0.0, at) * Transform2D(Vector2(1.0, 0.0), Vector2(-float(style.slant), 1.0), Vector2.ZERO)
	ci.draw_set_transform_matrix(m)
	var w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(-w * 0.5, float(fs) * ShowTheme.CAP * 0.5)
	var edge_px := roundi(float(fs) * float(style.e))
	var outer: Color = style.get("outer", Color(0, 0, 0, 0))
	var ext: Color = style.ext
	var ext_edge := edge_px
	if outer.a > 0.0: ext_edge = roundi(float(edge_px) * 1.5)
	var depth := float(fs) * float(style.depth)
	for step in [0.5, 1.0]:
		var down: Vector2 = base + Vector2(0.0, depth * step)
		ci.draw_string_outline(font, down, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ext_edge, Color(ext, ext.a * alpha))
		ci.draw_string(font, down, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ext, ext.a * alpha))
	if outer.a > 0.0: ci.draw_string_outline(font, base, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ext_edge, Color(outer, outer.a * alpha))
	var edge: Color = style.edge
	ci.draw_string_outline(font, base, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, edge_px, Color(edge, edge.a * alpha))
	var shade: Color = style.shade
	var face: Color = style.face
	ci.draw_string(font, base, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(shade, shade.a * alpha))
	var k := float(fs) * 0.026
	ci.draw_string(font, base + Vector2(-k, -k), words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(face, face.a * alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# ------------------------------------------------------------------ countdown

## Draws a countdown digit or the GO word centred on `centre` with capitals `cap_px` high, `age` s after it popped in.
static func countdown(ci: CanvasItem, word: String, age: float, centre: Vector2, cap_px: float, go := false, alpha := 1.0) -> void:
	if word == "" or age < 0.0 or alpha <= 0.0: return
	var size := ShowTheme.size_for_cap(cap_px) * (_go_pop(age) if go else _digit_pop(age))
	var fs := maxi(8, roundi(size / 8.0) * 8)
	var style := {"face": DIGIT.face, "shade": DIGIT.shade, "edge": DIGIT.edge, "ext": DIGIT.ext, "outer": DIGIT.outer, "slant": 0.0, "e": 0.16, "depth": 0.07}
	_glyph(ci, word.to_upper(), centre, GO_TILT if go else 0.0, size / float(fs), fs, style, alpha)
