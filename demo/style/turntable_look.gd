extends RefCounted
## A rideable floor disc of the race world (a `spin` hazard without `hit` whose part is a cylinder, levels 31) as a turntable in the candy look: a purple top of inset
## polar tiles (two tones) with grooves between them, a raised white rim ring of pieces of different lengths, a chamfered deep-purple substructure, a pink hub with a white axle cap,
## and a pink striped bumper bar from hub to rim (the hazard's own low box part, so the rotation reads). ONE mesh per layout (style/lathe_mesh.gd, shared material), a child of the body so it turns with it.
## A bar of a part with `bump` (a real bumper: levels/level_world.gd bump_at) is a mesh of its own, `Bar<part index>`, a child of the look at the part's centre, so `pulse` can squash it on a hit.
## Look only: the collision is the body's shapes, untouched (the rim and the tiles stand at most 0.08 m over the disc's top). Client only.
const Lathe := preload("res://style/lathe_mesh.gd")
const SpinnerLook := preload("res://style/spinner_look.gd")
const CandyLook := preload("res://style/candy_look.gd")
const TILE_A := CandyLook.PROP_PURPLE
const TILE_B := CandyLook.PROP_PURPLE_LIGHT
const GROOVE_FLOOR := CandyLook.PROP_PURPLE_DEEP
const RIM_A := CandyLook.PROP_WHITE
const RIM_B := Color("#e1d6f2")
const TILE := 0.85             ## m: the tiles' pitch (radial and along the arc)
const GROOVE := 0.05           ## m: half the groove between two tiles
const BEVEL := 0.035           ## m: a tile's chamfer
const RIM := 0.34              ## m: the rim ring's width
const RIM_LIFT := 0.045        ## m: how far the rim stands over the top
const TILE_LIFT := 0.02
const BASE := -0.04            ## the groove floor under the tiles
const HUB_RADIUS := 0.62
const HUB_TOP := 0.34
const SIDES := 36

static var _meshes := {}

## The look of `shapes` (CollisionShape3D children of the body: one upright cylinder and boxes) or null when there is none.
static func build(shapes: Array[CollisionShape3D]) -> MeshInstance3D:
	var key := ""
	var disc: CollisionShape3D = null
	for shape_node in shapes:
		if shape_node.shape is CylinderShape3D and disc == null: disc = shape_node
		key += "|%s|%s" % [(shape_node.shape as Shape3D).get_class() + (str((shape_node.shape as BoxShape3D).size) if shape_node.shape is BoxShape3D else str((shape_node.shape as CylinderShape3D).radius)) + ("|bump" if shape_node.has_meta("bump") else ""), shape_node.transform]
	if disc == null: return null
	if not _meshes.has(key): _meshes[key] = _mesh(shapes, disc)
	var visual := MeshInstance3D.new()
	visual.name = "RaceLook"
	visual.mesh = _meshes[key]
	for index in shapes.size():
		var shape_node := shapes[index]
		if not shape_node.has_meta("bump") or not shape_node.shape is BoxShape3D: continue
		var bar := MeshInstance3D.new()
		bar.name = "Bar%d" % index
		bar.position = shape_node.position
		var bar_key := "bar|%s|%s" % [(shape_node.shape as BoxShape3D).size, shape_node.transform]
		if not _meshes.has(bar_key): _meshes[bar_key] = _bar_mesh(shape_node)
		bar.mesh = _meshes[bar_key]
		visual.add_child(bar)
	return visual

## The squash of a bumper bar that was hit: flat and wide at once, springing back past its size once and settling (a tween on the bar's own scale, look only).
static func pulse(bar: Node3D) -> void:
	var tween := bar.create_tween()
	tween.tween_property(bar, "scale", Vector3(1.0, 0.45, 1.7), 0.06)
	tween.tween_property(bar, "scale", Vector3(1.0, 1.35, 0.8), 0.12).set_trans(Tween.TRANS_SINE)
	tween.tween_property(bar, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_SINE)

## One striped bar built round its own centre (the bar is a node at the part's position; the hub lies `offset` along it from the middle, as in the disc's own mesh).
static func _bar_mesh(shape_node: CollisionShape3D) -> ArrayMesh:
	var build := Lathe.Build.new()
	var size := (shape_node.shape as BoxShape3D).size
	var longest := 0
	for k in 3: if size[k] > size[longest]: longest = k
	var cross := minf(size[(longest + 1) % 3], size[(longest + 2) % 3])
	var direction := shape_node.transform.basis[longest].normalized()
	SpinnerLook.bar(build, {"dir": direction, "centre": Vector3.ZERO, "half": size[longest] * 0.5, "radius": cross * 0.5, "offset": -shape_node.position.dot(direction)}, HUB_RADIUS)
	return build.commit(Lathe.material())

static func _mesh(shapes: Array[CollisionShape3D], disc: CollisionShape3D) -> ArrayMesh:
	var cylinder := disc.shape as CylinderShape3D
	var radius := cylinder.radius
	var top := disc.position.y + cylinder.height * 0.5
	var low := top - cylinder.height
	var build := Lathe.Build.new()
	var at := Transform3D(Basis.IDENTITY, Vector3(0.0, top, 0.0))   # the disc's top is the part's y = top; the profile below is relative to it
	build.lathe(at, _body(radius, cylinder.height), SIDES)
	build.lathe(at, _hub(), 20)
	var seed_value := int(radius * 100.0)
	# tiles: rings between the hub and the rim, each cut into sectors
	var inner := HUB_RADIUS + 0.1
	var outer := radius - RIM
	var rings := maxi(int(round((outer - inner) / TILE)), 1)
	for ring in rings:
		var r0 := inner + (outer - inner) * float(ring) / rings
		var r1 := inner + (outer - inner) * float(ring + 1) / rings
		var count := maxi(int(round(TAU * (r0 + r1) * 0.5 / TILE)), 4)
		var turn := 0.5 * (ring % 2) * TAU / count
		for k in count:
			var a0 := turn + TAU * float(k) / count
			var a1 := turn + TAU * float(k + 1) / count
			var color := TILE_A if (k + ring) % 2 == 0 else TILE_B
			_sector(build, at, r0, r1, a0, a1, GROOVE, GROOVE, BASE, TILE_LIFT, BEVEL, color)
	# rim: pieces of different lengths
	var angle := 0.0
	var piece := 0
	while angle < TAU - 0.01:
		var length := TILE * (0.45 + 0.55 * fposmod(sin(float(seed_value + piece) * 12.9898) * 43758.5453, 1.0)) / radius
		var a1 := minf(angle + length, TAU)
		if TAU - a1 < 0.45 * TILE / radius: a1 = TAU
		_sector(build, at, radius - RIM, radius, angle, a1, GROOVE, 0.0, BASE, RIM_LIFT, BEVEL, RIM_A if piece % 2 == 0 else RIM_A.lerp(RIM_B, 0.25))
		angle = a1
		piece += 1
	# the pointer: the hazard's own low boxes as striped bumper bars from the hub to the rim
	for shape_node in shapes:
		if not shape_node.shape is BoxShape3D or shape_node.has_meta("bump"): continue
		var size := (shape_node.shape as BoxShape3D).size
		var longest := 0
		for k in 3: if size[k] > size[longest]: longest = k
		var cross := minf(size[(longest + 1) % 3], size[(longest + 2) % 3])
		var direction := shape_node.transform.basis[longest].normalized()
		var arm := {"dir": direction, "centre": shape_node.position, "half": size[longest] * 0.5, "radius": cross * 0.5, "offset": -shape_node.position.dot(direction)}
		SpinnerLook.bar(build, arm, HUB_RADIUS)
	return build.commit(Lathe.material())

## The substructure from the underside of the cylinder (`height` under the top) to the groove floor: a chamfered purple drum, a light purple band under the rim, the groove floor deep purple.
static func _body(radius: float, height: float) -> Array:
	var bottom := -height
	var chamfer := minf(0.22, height * 0.4)
	var profile: Array = [[0.0, bottom, Lathe.PURPLE_DEEP], [radius - chamfer, bottom, Lathe.PURPLE_DEEP]]
	profile.append([radius - 0.03, bottom + chamfer, Lathe.PURPLE])
	profile.append([radius, bottom + chamfer + 0.06, Lathe.PURPLE])
	profile.append([radius, BASE - 0.12, Lathe.PURPLE_LIGHT])
	profile.append([radius, BASE, Lathe.PURPLE_LIGHT])
	profile.append([radius * 0.98, BASE, GROOVE_FLOOR])
	profile.append([0.0, BASE, GROOVE_FLOOR])
	return profile

## A pink drum on the middle with a rolled top and a white axle cap under an amber dome.
static func _hub() -> Array:
	var cap := HUB_RADIUS * 0.55
	var profile: Array = [[HUB_RADIUS + 0.06, BASE - 0.02, Lathe.PURPLE_DEEP], [HUB_RADIUS + 0.06, 0.03, Lathe.PURPLE_DEEP], [HUB_RADIUS, 0.09, Lathe.PINK]]
	profile.append([HUB_RADIUS, HUB_TOP - 0.1, Lathe.PINK])
	profile.append_array(Lathe.arc(HUB_RADIUS - 0.1, HUB_TOP - 0.1, 0.1, 0.0, 90.0, Lathe.PINK, 2))
	profile.append([cap, HUB_TOP, Lathe.PINK])
	profile.append([cap, HUB_TOP + 0.04, Lathe.WHITE])
	profile.append([cap * 0.8, HUB_TOP + 0.04, Lathe.WHITE])
	profile.append_array(Lathe.arc(0.0, HUB_TOP + 0.04, cap * 0.8, 0.0, 90.0, Lathe.AMBER, 3))
	return profile

## One chamfered tile on a polar grid cell (`r0`..`r1`, angles `a0`..`a1`, y axis up, relative to `at`): outline at `base`, top face at `lift` inset by `bevel` more; `gap_in` shrinks
## the inner/side edges, `gap_out` the outer edge (0 on a rim piece's outer edge, which stands flush with the substructure).
static func _sector(build: Lathe.Build, at: Transform3D, r0: float, r1: float, a0: float, a1: float, gap: float, gap_out: float, base: float, lift: float, bevel: float, color: Color) -> void:
	var g := build.group
	var linear := color.srgb_to_linear()
	var side := linear.darkened(0.25)
	var low: Array[Vector3] = []
	var high: Array[Vector3] = []
	var inset := gap + bevel
	var corners := [[r0 + gap, a0, 1.0], [r1 - gap_out, a0, -1.0], [r1 - gap_out, a1, -1.0], [r0 + gap, a1, 1.0]]
	for k in 4:
		var c: Array = corners[k]
		var forward := 1.0 if (k == 0 or k == 1) else -1.0   # the angular shrink points into the tile: + at a0, - at a1
		var r: float = c[0]
		var angle_low: float = float(c[1]) + forward * gap / maxf(r, 0.1)
		low.append(at * Vector3(cos(angle_low) * r, base, sin(angle_low) * r))
		var r_high: float = r + float(c[2]) * bevel
		var angle_high: float = float(c[1]) + forward * inset / maxf(r_high, 0.1)
		high.append(at * Vector3(cos(angle_high) * r_high, lift, sin(angle_high) * r_high))
	var centre := (high[0] + high[1] + high[2] + high[3]) * 0.25
	var top_base := g.v.size()
	for p in high: g.add(p, at.basis.y, Vector2.ZERO, linear)
	g.quad(top_base, top_base + 1, top_base + 2, top_base + 3, at.basis.y)
	for k in 4:
		var n := (k + 1) % 4
		var mid := (low[k] + low[n] + high[k] + high[n]) * 0.25
		var outward := mid - centre
		outward.y = 0.0
		var face := (low[n] - low[k]).cross(high[k] - low[k])
		if face.dot(outward) < 0.0: face = -face
		face = face.normalized() if face.length_squared() > 1e-12 else at.basis.y
		var base_index := g.v.size()
		for p in [low[k], low[n], high[n], high[k]]: g.add(p, face, Vector2.ZERO, side)
		g.quad(base_index, base_index + 1, base_index + 2, base_index + 3, face)
