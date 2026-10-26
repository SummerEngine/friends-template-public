extends RefCounted
## Places the pieces of one backdrop (style/backdrop.gd) into per-body instance batches, from a spec and a seed. Pure geometry and random numbers:
## no nodes, no engine state, the same spec always gives the same instances.
## spec: {kind, time, seed, bbox (Rect2 of the course in x/z, level-local), y_low, y_high (lowest / highest walkable height), forward (Vector2, towards the
## goal), density (0.5..1)}. Local origin = the level's origin (the lobby: the yard's origin).
## Rules this file keeps: the far-below world tops out 30 m under the lowest walkable surface; every other piece stands more than
## KEEP_OUT metres from the course's bounding box (so never above or beside the route); drifting pieces fly in lanes outside that box too; nothing has collision.
const Themes := preload("res://style/backdrop_themes.gd")
const KEEP_OUT := 18.0         ## metres from the course box to the edge of any piece (the brief asks for more than 12)
const ISLAND_KEEP_OUT := 40.0  ## floating islands keep further away so they never read as a platform
const BELOW := 30.0            ## the roof tops of the world below end this far under the lowest walkable surface
const STREET_DEPTH := 16.0     ## streets and fields lie this much lower still
const WRAP := 1600.0           ## length of the lanes of drifting pieces
const ROCK_DEPTH := 1.3        ## an island's rock cone is this many radii deep

class Batch extends RefCounted:
	var data := PackedFloat32Array()
	var count := 0
	func add(xf: Transform3D, color: Color, custom: Color) -> void:
		var b := xf.basis
		var o := xf.origin
		data.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z,
			color.r, color.g, color.b, color.a, custom.r, custom.g, custom.b, custom.a]))
		count += 1

var spec: Dictionary
var rng := RandomNumberGenerator.new()
var batches := {"box": Batch.new(), "pyramid": Batch.new(), "cone": Batch.new(), "cylinder": Batch.new(), "sphere": Batch.new(), "bird": Batch.new()}
var kind := ""
var time := ""
var bbox: Rect2
var centre := Vector2.ZERO
var y_low := 0.0
var y_high := 0.0
var top_y := 0.0               ## roof tops of the near world
var ground_y := 0.0            ## streets, fields, cloud sea
var density := 1.0
var lanes_along_z := true      ## drift runs along z (the course is longer in z) or along x
var wind := 1.0                ## +1 / -1: which way along the lane everything drifts
var window_mode := 1.0

func _init(source: Dictionary) -> void:
	spec = source
	kind = str(spec.kind)
	time = str(spec.time)
	bbox = spec.bbox
	centre = bbox.get_center()
	y_low = float(spec.y_low)
	y_high = float(spec.y_high)
	density = float(spec.get("density", 1.0))
	top_y = y_low - BELOW
	ground_y = top_y - STREET_DEPTH
	rng.seed = int(spec.seed)
	lanes_along_z = bbox.size.y >= bbox.size.x
	wind = 1.0 if rng.randf() < 0.5 else -1.0
	window_mode = 1.0 if time == Themes.DAY else 2.0

## ---- helpers ----

func _c(color: Color, jitter := 0.0) -> Color:
	return Themes.tone(color, time, rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0)

func _pick(list: Array[Color], jitter := 0.04) -> Color:
	return _c(list[rng.randi() % list.size()], jitter)

func add(shape: String, pos: Vector3, size: Vector3, yaw: float, color: Color, mode := 0.0, seed_value := 0.0, smooth := 0.0, speed := 0.0, tilt := Basis.IDENTITY) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * tilt * Basis.from_scale(size), pos)
	(batches[shape] as Batch).add(xf, color, Color(mode, seed_value, smooth, speed))

## A body standing on `base_y`, `height` tall, centred on x/z.
func stand(shape: String, x: float, z: float, base_y: float, width: float, depth: float, height: float, yaw: float, color: Color, mode := 0.0) -> void:
	add(shape, Vector3(x, base_y + height * 0.5, z), Vector3(width, height, depth), yaw, color, mode, rng.randf())

## Whether a piece of radius `r` at (x, z) keeps `margin` metres from the course box.
func clear(x: float, z: float, r: float, margin := KEEP_OUT) -> bool:
	return not bbox.grow(margin + r).has_point(Vector2(x, z))

func _towards(point: Vector2) -> float:
	var d := centre - point
	return atan2(d.x, d.y)

## ---- the world below ----

func build() -> Dictionary:
	_near_world()
	_horizon()
	_islands()
	_sky()
	return batches

func _near_world() -> void:
	var radius := 330.0 * density
	match kind:
		Themes.CITY: _city_cells(44.0, radius, false)
		Themes.YARD: _city_cells(60.0, radius, true)
		Themes.PARK: _park_field(radius)
		_: _cloud_sea(radius)

func _city_cells(cell: float, radius: float, site: bool) -> void:
	var steps := int(ceil(radius / cell))
	var lot := cell - (14.0 if site else 10.0)
	var room := top_y - ground_y
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var x := centre.x + i * cell
			var z := centre.y + j * cell
			if Vector2(x - centre.x, z - centre.y).length() > radius: continue
			var roll := rng.randf()
			if site: _site_lot(x, z, lot, room, roll)
			elif roll < 0.1: _park_lot(x, z, lot)
			elif roll < 0.45: _tower(x, z, lot * rng.randf_range(0.5, 0.85), lot * rng.randf_range(0.5, 0.85), room)
			else:
				var half := lot * 0.25
				for sx in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						if rng.randf() < 0.15: continue
						_tower(x + sx * half, z + sz * half, lot * 0.36, lot * 0.36, room * 0.9)

func _tower(x: float, z: float, w: float, d: float, room: float) -> void:
	var cap := room - 4.0
	var h := 3.0 + pow(rng.randf(), 1.5) * (cap - 3.0)
	var color := _pick(Themes.CITY_BUILDING)
	var mode := window_mode if h > 7.0 else 0.0
	stand("box", x, z, ground_y, w, d, h, rng.randf_range(-0.05, 0.05), color, mode)
	var roll := rng.randf()
	if roll < 0.3 and w > 9.0:
		stand("cylinder", x + w * 0.2, z - d * 0.2, ground_y + h, 3.4, 3.4, 3.6, 0.0, _c(Themes.CITY_BUILDING[4]))
	elif roll < 0.55:
		stand("box", x - w * 0.2, z + d * 0.15, ground_y + h, w * 0.35, d * 0.3, 2.0, 0.0, _c(Themes.CITY_BUILDING[3]))
	elif roll < 0.65 and w < 12.0:
		stand("pyramid", x, z, ground_y + h, w + 1.0, d + 1.0, 3.5, 0.0, _c(Color("#a58a8c"), 0.05))

func _park_lot(x: float, z: float, lot: float) -> void:
	for n in rng.randi_range(4, 7):
		var size := rng.randf_range(4.0, 7.5)
		var at := Vector2(rng.randf_range(-lot, lot) * 0.4, rng.randf_range(-lot, lot) * 0.4)
		stand("sphere", x + at.x, z + at.y, ground_y, size, size, size * 1.1, 0.0, _pick(Themes.PARK_TREE))

func _site_lot(x: float, z: float, lot: float, room: float, roll: float) -> void:
	if roll < 0.5:
		var rows := rng.randi_range(2, 3)
		var length := rng.randf_range(10.0, 12.0)
		var turn := 0.0 if rng.randf() < 0.5 else PI * 0.5
		for row in rows:
			var offset := (row - (rows - 1) * 0.5) * 6.0
			var stack := rng.randi_range(1, 3)
			var color := _pick(Themes.YARD_BUILDING, 0.06)
			for level in stack:
				var at := Vector2(0.0, offset).rotated(-turn)
				stand("box", x + at.x, z + at.y, ground_y + level * 2.7, length, 2.5, 2.6, turn, color)
	elif roll < 0.66:
		var h := minf(rng.randf_range(5.0, 11.0), room - 3.0)
		stand("box", x, z, ground_y, lot * 0.6, lot * 0.5, h, 0.0, _pick(Themes.YARD_BUILDING), 0.0)
		stand("box", x, z, ground_y + h, lot * 0.52, lot * 0.42, 0.7, 0.0, _c(Themes.YARD_BUILDING[5]))
	elif roll < 0.8:
		var width := lot * rng.randf_range(0.5, 0.8)
		stand("pyramid", x, z, ground_y, width, width, rng.randf_range(5.0, 9.0), rng.randf(), _pick(Themes.YARD_GROUND))
	elif roll < 0.9:
		stand("cylinder", x, z, ground_y, 8.0, 8.0, minf(10.0, room - 3.0), 0.0, _c(Themes.YARD_BUILDING[4]))

func _river(p: Vector2) -> float:
	var s := float(spec.seed % 977) * 0.001 + 1.0
	return absf(p.y - 140.0 * sin(p.x * 0.005 + s) - 60.0 * sin(p.x * 0.013) - 40.0)

func _park_field(radius: float) -> void:
	var step := 27.0
	var steps := int(ceil(radius / step))
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var at := Vector2(centre.x + i * step + rng.randf_range(-10.0, 10.0), centre.y + j * step + rng.randf_range(-10.0, 10.0))
			if at.distance_to(centre) > radius or rng.randf() > 0.75 * density: continue
			if _river(at) < 24.0: continue
			var roll := rng.randf()
			if roll < 0.05:
				_house(at.x, at.y, ground_y, rng.randf_range(4.5, 7.0), rng.randf() * PI)
			elif roll < 0.55:
				var h := rng.randf_range(5.0, 11.0)
				stand("cone", at.x, at.y, ground_y, h * 0.55, h * 0.55, h, 0.0, _pick(Themes.PARK_TREE))
			else:
				var s := rng.randf_range(4.0, 8.0)
				stand("sphere", at.x, at.y, ground_y, s, s, s * rng.randf_range(0.9, 1.3), 0.0, _pick(Themes.PARK_TREE))

func _house(x: float, z: float, base_y: float, size: float, yaw: float) -> void:
	var h := size * rng.randf_range(0.6, 0.85)
	stand("box", x, z, base_y, size, size * rng.randf_range(0.8, 1.2), h, yaw, _pick(Themes.PARK_WALL), 0.0)
	stand("pyramid", x, z, base_y + h, size * 1.2, size * 1.1, size * 0.55, yaw, _pick(Themes.PARK_ROOF))

func _cloud_sea(radius: float) -> void:
	var step := 40.0
	var steps := int(ceil(radius / step))
	for i in range(-steps, steps + 1):
		for j in range(-steps, steps + 1):
			var at := Vector2(centre.x + i * step + rng.randf_range(-14.0, 14.0), centre.y + j * step + rng.randf_range(-14.0, 14.0))
			if at.distance_to(centre) > radius or rng.randf() > 0.7 * density: continue
			var w := rng.randf_range(34.0, 72.0)
			var h := rng.randf_range(8.0, 15.0)
			var lift := rng.randf_range(0.0, top_y - ground_y - h)
			add("sphere", Vector3(at.x, ground_y + h * 0.5 + lift, at.y), Vector3(w, h, w * rng.randf_range(0.7, 1.0)), rng.randf() * PI, _pick(Themes.CLOUD_PUFF, 0.02), 0.0, 0.0, 1.0)

## ---- horizon: three depth layers, each further, taller, hazier ----

const LAYERS := [[380.0, 620.0], [620.0, 900.0], [900.0, 1250.0]]

## 0..1 bump towards the goal and a few random bearings: where the skyline or the range rises.
func _skyline(angle: float, bumps: Array) -> float:
	var total := 0.0
	for bump: float in bumps:
		var delta := absf(wrapf(angle - bump, -PI, PI))
		total += exp(-pow(delta / 0.32, 2.0))
	return clampf(total, 0.0, 1.5)

func _bumps() -> Array:
	var forward := atan2(float((spec.forward as Vector2).x), -float((spec.forward as Vector2).y))
	var list: Array = [forward]
	for i in 3: list.append(rng.randf_range(-PI, PI))
	return list

func _horizon() -> void:
	var bumps := _bumps()
	for layer in LAYERS.size():
		var range_m: Array = LAYERS[layer]
		var count := int((float([150, 120, 90][layer])) * density)
		for n in count:
			var angle := rng.randf_range(-PI, PI)
			var r := rng.randf_range(range_m[0], range_m[1])
			var at := centre + Vector2(sin(angle), -cos(angle)) * r
			var rise := _skyline(angle, bumps)
			var spread := 1.0 + 0.5 * layer
			match kind:
				Themes.CITY: _skyline_tower(at, rise, spread, layer)
				Themes.YARD: _site_tower(at, rise, spread, layer)
				Themes.PARK: _hill(at, rise, spread, layer)
				_: _cumulus(at, rise, spread)
	var cranes := {Themes.CITY: 5, Themes.YARD: 12, Themes.PARK: 0, Themes.CLOUD: 0}[kind] as int
	for n in int(cranes * density):
		var angle := rng.randf_range(-PI, PI)
		var r := rng.randf_range(300.0, 900.0)
		var at := centre + Vector2(sin(angle), -cos(angle)) * r
		_crane(at, rng.randf_range(50.0, 95.0) * (1.0 + r / 1500.0), rng.randf() * TAU)

func _skyline_tower(at: Vector2, rise: float, spread: float, layer: int) -> void:
	var w := rng.randf_range(18.0, 40.0) * spread
	var d := rng.randf_range(18.0, 40.0) * spread
	var h := (rng.randf_range(22.0, 60.0) + rise * rng.randf_range(40.0, 110.0)) * (1.0 + 0.35 * layer)
	var color := _pick(Themes.CITY_BUILDING, 0.05)
	stand("box", at.x, at.y, ground_y - 4.0, w, d, h, rng.randf_range(-0.3, 0.3), color, window_mode)
	var roll := rng.randf()
	if roll < 0.2 and h > 60.0:
		stand("cone", at.x, at.y, ground_y - 4.0 + h, w * 0.06 + 1.0, w * 0.06 + 1.0, h * 0.28, 0.0, color)
	elif roll < 0.4:
		stand("box", at.x, at.y, ground_y - 4.0 + h, w * 0.6, d * 0.6, h * 0.12, 0.0, _c(Themes.CITY_BUILDING[3]), window_mode)
	elif roll < 0.5 and layer == 0 and h > 50.0:
		_billboard(at, ground_y - 4.0 + h)

func _site_tower(at: Vector2, rise: float, spread: float, layer: int) -> void:
	var w := rng.randf_range(14.0, 30.0) * spread
	var h := (rng.randf_range(15.0, 45.0) + rise * rng.randf_range(20.0, 70.0)) * (1.0 + 0.3 * layer)
	var roll := rng.randf()
	if roll < 0.55:
		var color := _pick(Themes.YARD_BUILDING, 0.05)
		stand("box", at.x, at.y, ground_y - 4.0, w, w * rng.randf_range(0.7, 1.2), h, rng.randf(), color, window_mode)
		if rng.randf() < 0.5: stand("box", at.x, at.y, ground_y - 4.0 + h, w * 0.7, w * 0.6, 1.2, 0.0, _c(Themes.YARD_BUILDING[5]))
	elif roll < 0.8:
		stand("cylinder", at.x, at.y, ground_y - 4.0, w * 0.6, w * 0.6, h * 0.8, 0.0, _c(Themes.YARD_BUILDING[4], 0.05))
	else:
		stand("pyramid", at.x, at.y, ground_y - 4.0, w * 2.4, w * 2.4, h * 0.45, rng.randf(), _pick(Themes.YARD_GROUND))

func _hill(at: Vector2, rise: float, spread: float, layer: int) -> void:
	var w := rng.randf_range(110.0, 230.0) * spread
	var h := w * rng.randf_range(0.3, 0.6) * (1.0 + 0.5 * rise)
	var color := _pick(Themes.MOUNTAIN, 0.05)
	stand("cone", at.x, at.y, ground_y - 6.0, w, w * rng.randf_range(0.8, 1.1), h, rng.randf() * TAU, color)
	if layer == 0 and rng.randf() < 0.5:
		var s := w * 0.5
		stand("sphere", at.x + rng.randf_range(-w, w) * 0.5, at.y + rng.randf_range(-w, w) * 0.5, ground_y - 6.0, s, s, h * 0.35, 0.0, _c(Themes.PARK_TREE[0], 0.05))

func _cumulus(at: Vector2, rise: float, spread: float) -> void:
	var w := rng.randf_range(110.0, 210.0) * spread
	var base := ground_y - 8.0
	var tiers := rng.randi_range(2, 4)
	for t in tiers:
		var s := w * (1.0 - 0.22 * t)
		var h := s * 0.62 * (1.0 + 0.4 * rise)
		var at_y := base + t * w * 0.33 * (1.0 + 0.3 * rise)
		add("sphere", Vector3(at.x + rng.randf_range(-w, w) * 0.12, at_y + h * 0.5, at.y + rng.randf_range(-w, w) * 0.12), Vector3(s, h, s * 0.85), rng.randf() * PI, _pick(Themes.CLOUD_PUFF, 0.03), 0.0, 0.0, 1.0)

func _billboard(at: Vector2, base_y: float) -> void:
	var yaw := _towards(at)
	var size := rng.randf_range(20.0, 30.0)
	var color := _pick(Themes.BILLBOARD, 0.04)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for side: float in [-0.32, 0.32]:
		var p := Vector3(at.x, 0.0, at.y) + right * size * side
		stand("box", p.x, p.z, base_y, 1.2, 1.2, 9.0, yaw, _c(Themes.CITY_BUILDING[4]))
	add("box", Vector3(at.x, base_y + 9.0 + size * 0.22, at.y), Vector3(size, size * 0.44, 1.0), yaw, color, 3.0, rng.randf())

func _crane(at: Vector2, h: float, yaw: float) -> void:
	var color := _c(Themes.YARD_CRANE, 0.03)
	var dark := _c(Themes.YARD_BUILDING[4])
	var base := ground_y - 4.0
	stand("box", at.x, at.y, base, 3.2, 3.2, h, yaw, color)
	var along := Vector3(cos(yaw), 0.0, -sin(yaw))
	var top := Vector3(at.x, base + h, at.y)
	var jib := h * 1.05
	var jib_centre := top + along * (jib * 0.5 - h * 0.18) + Vector3(0.0, 2.2, 0.0)
	add("box", jib_centre, Vector3(jib, 2.4, 2.4), yaw, color)
	var weight := top - along * (h * 0.14) + Vector3(0.0, 2.2, 0.0)
	add("box", weight, Vector3(7.0, 6.0, 6.0), yaw, dark)
	add("box", top + Vector3(0.0, 4.5, 0.0), Vector3(4.0, 4.0, 4.0), yaw, color)
	var hook := top + along * (jib * 0.78 - h * 0.18) + Vector3(0.0, -h * 0.1, 0.0)
	add("box", hook, Vector3(0.5, h * 0.2, 0.5), yaw, dark)

## ---- floating islands: a disc of grass on a cone of rock, with trees, a few houses or a tower, all far from the course ----

func _islands() -> void:
	var count := int((13 if kind == Themes.CLOUD else 9) * density)
	var placed: Array = []
	var attempts := 0
	while placed.size() < count and attempts < 400:
		attempts += 1
		var r := rng.randf_range(12.0, 26.0)
		var angle := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(70.0, 330.0)
		var at := centre + Vector2(sin(angle), -cos(angle)) * (maxf(bbox.size.x, bbox.size.y) * 0.5 + dist)
		if not clear(at.x, at.y, r, ISLAND_KEEP_OUT): continue
		var y := maxf(rng.randf_range(y_low - 6.0, y_high + 38.0), top_y + 2.4 + r * ROCK_DEPTH + 2.0)
		var overlap := false
		for other: Vector4 in placed:
			if Vector2(other.x - at.x, other.z - at.y).length() < other.w + r + 40.0: overlap = true
		if overlap: continue
		placed.append(Vector4(at.x, y, at.y, r))
		_island(Vector3(at.x, y, at.y), r)

func _island(p: Vector3, r: float) -> void:
	add("cylinder", p + Vector3(0.0, -1.2, 0.0), Vector3(r * 2.0, 2.4, r * 2.0), rng.randf() * PI, _pick(Themes.ISLAND_GRASS, 0.03))
	var rock := Basis.from_euler(Vector3(PI, 0.0, 0.0))
	add("cone", p + Vector3(0.0, -2.4 - r * ROCK_DEPTH * 0.5, 0.0), Vector3(r * 1.9, r * ROCK_DEPTH, r * 1.9), rng.randf() * PI, _pick(Themes.ISLAND_ROCK, 0.04), 0.0, 0.0, 0.0, 0.0, rock)
	match kind:
		Themes.CITY:
			for n in rng.randi_range(1, 3):
				var at := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.45
				var w := rng.randf_range(5.0, 9.0)
				var h := rng.randf_range(10.0, 26.0)
				stand("box", p.x + at.x, p.z + at.y, p.y, w, w, h, rng.randf() * PI, _pick(Themes.CITY_BUILDING), window_mode)
		Themes.YARD:
			for n in rng.randi_range(1, 3):
				var at := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.5
				stand("box", p.x + at.x, p.z + at.y, p.y, 8.0, 2.6, 2.6, rng.randf() * PI, _pick(Themes.YARD_BUILDING, 0.06))
			if r > 20.0: _crane(Vector2(p.x, p.z) + Vector2(r * 0.3, 0.0), 22.0, rng.randf() * TAU)
		_:
			for n in rng.randi_range(1, 2):
				var at := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.5
				_house(p.x + at.x, p.z + at.y, p.y, rng.randf_range(4.0, 6.0), rng.randf() * PI)
	for n in rng.randi_range(2, 6):
		var spot := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)) * 0.72
		var h := rng.randf_range(5.0, 9.0)
		if rng.randf() < 0.5: stand("cone", p.x + spot.x, p.z + spot.y, p.y, h * 0.55, h * 0.55, h, 0.0, _pick(Themes.PARK_TREE))
		else: stand("sphere", p.x + spot.x, p.z + spot.y, p.y, h * 0.7, h * 0.7, h * 0.8, 0.0, _pick(Themes.PARK_TREE))

## ---- sky: clouds, a blimp, a flock of birds; all drift in lanes beside the course, never across it ----

func lane_axis() -> Vector3:
	return Vector3(0.0, 0.0, 1.0) if lanes_along_z else Vector3(1.0, 0.0, 0.0)

## A point of a lane: `along` metres from the centre along the lane, `out` metres beyond the course box on side `side`.
func _lane(along: float, out: float, side: float, y: float) -> Vector3:
	var half := (bbox.size.x if lanes_along_z else bbox.size.y) * 0.5
	var perp := (centre.x if lanes_along_z else centre.y) + side * (half + out)
	return Vector3(perp, y, centre.y + along) if lanes_along_z else Vector3(centre.x + along, y, perp)

func _heading() -> Vector3:
	return lane_axis() * wind

func _sky() -> void:
	var cloud_count := int(30 * density)
	for n in cloud_count:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var y := rng.randf_range(y_low - 8.0, y_high + 70.0)
		var speed := wind * rng.randf_range(2.0, 5.0)
		var along := rng.randf_range(-WRAP * 0.5, WRAP * 0.5)
		var out := rng.randf_range(40.0, 520.0)
		var base := _lane(along, out, side, y)
		var size := rng.randf_range(18.0, 40.0)
		for puff in rng.randi_range(3, 5):
			var offset := lane_axis() * rng.randf_range(-size, size) * 0.7 + Vector3(0.0, rng.randf_range(-0.2, 0.3) * size, 0.0)
			var perp_shift := (Vector3(1.0, 0.0, 0.0) if lanes_along_z else Vector3(0.0, 0.0, 1.0)) * rng.randf_range(-0.2, 0.2) * size
			var s := size * rng.randf_range(0.55, 1.0)
			add("sphere", base + offset + perp_shift, Vector3(s, s * 0.5, s * 0.75), 0.0, _c(Themes.CLOUD_PUFF[rng.randi() % 3], 0.02), 0.0, 0.0, 1.0, speed)
	if time != Themes.NIGHT or rng.randf() < 0.5: _blimp()
	_birds()

func _heading_yaw_x() -> float:
	var h := _heading()
	return atan2(-h.z, h.x)

func _blimp() -> void:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var speed := wind * rng.randf_range(4.0, 7.0)
	var base := _lane(rng.randf_range(-300.0, 300.0), rng.randf_range(70.0, 130.0), side, y_high + rng.randf_range(22.0, 48.0))
	var yaw := _heading_yaw_x()
	var forward := _heading()
	var color := _c(Themes.BLIMP, 0.02)
	add("sphere", base, Vector3(26.0, 8.5, 8.5), yaw, color, 0.0, 0.0, 1.0, speed)
	add("box", base + Vector3(0.0, -5.6, 0.0) + forward * 1.5, Vector3(6.0, 1.8, 2.4), yaw, _c(Themes.CITY_BUILDING[4]), 0.0, 0.0, 0.0, speed)
	add("box", base - forward * 10.5 + Vector3(0.0, 3.4, 0.0), Vector3(4.5, 4.8, 0.5), yaw, _c(Themes.CITY_BUILDING[2]), 0.0, 0.0, 0.0, speed)
	add("box", base - forward * 10.5 - Vector3(0.0, 3.4, 0.0), Vector3(4.5, 4.8, 0.5), yaw, _c(Themes.CITY_BUILDING[2]), 0.0, 0.0, 0.0, speed)

func _birds() -> void:
	var flock := int(rng.randi_range(7, 11) * density)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var speed := wind * 9.0
	var base := _lane(rng.randf_range(-250.0, 250.0), rng.randf_range(45.0, 90.0), side, y_high + rng.randf_range(8.0, 26.0))
	var forward := _heading()
	var across := Vector3(forward.z, 0.0, -forward.x)
	var yaw := atan2(-forward.x, -forward.z)
	var color := _c(Color("#3f4572"))
	for n in flock:
		var rank := ceili(n / 2.0)
		var sign_value := 1.0 if n % 2 == 0 else -1.0
		var p := base - forward * rank * 3.2 + across * sign_value * rank * 2.6 + Vector3(0.0, rng.randf_range(-0.6, 0.6), 0.0)
		add("bird", p, Vector3(2.4, 1.0, 1.5), yaw, color, 4.0, rng.randf(), 0.0, speed)
