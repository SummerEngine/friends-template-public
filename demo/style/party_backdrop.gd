extends RefCounted
## The open-air world of the party look (style/party_look.gd): a bright sky, a sea of soft clouds far below, candy islands, hills and
## balloons around the course, the course itself standing on candy supports like a floating island, bunting along the tops of its walls
## and confetti drifting down. Everything is decor in the cast's colours (the palette of style/party_look.gd): no collision, no shadows,
## no lights, no textures. Built from primitives in code, one MultiMesh per mesh shape (sphere, cylinder, cone, box), a few quad
## batches, a cloud-sea plane: 9 draw calls and about 600 instances whatever the level (density follows the graphics quality).
## Placement is seeded: a level always grows the same world. Replaces style/room_shell.gd in the show mode (style/backdrop.gd).
##
## Rules (checked by tools/backdrop_check.gd): every piece of the lit batches, the clouds and the sea is entirely `MIN_BELOW` m under the
## course's lowest walkable surface or `MIN_SIDE` m from the course's box on x/z (never above or beside the route); `Supports` hang
## directly under the course's own ground; `Confetti` and `Bunting` are the only things near the route (small, flat, unlit, harmless).
const Party := preload("res://style/party_look.gd")
const Style := preload("res://style/friends_style.gd")
const BuntingRule := preload("res://style/bunting_rule.gd")
const MOTION := preload("res://style/party_motion.gdshader")
const MIN_SIDE := 14.0
const MIN_BELOW := 25.0
const SEA_DEPTH := 60.0         ## the cloud sea's top under the lowest walkable surface
const REACH := 4000.0
const PLACE_REACH := 360.0      ## islands and balloons stand this far from the course at most
const HILL_RING := Vector2(260.0, 420.0)
const BUNTING_MAX := 700

## A batch of instances of one mesh: transform and colour each.
class Batch extends RefCounted:
	var mesh: Mesh
	var material: Material
	var forms: Array[Transform3D] = []
	var colors := PackedColorArray()
	var reach := 0.0

	func _init(shape: Mesh, shared: Material) -> void:
		mesh = shape
		material = shared

	func add(at: Transform3D, color: Color, size := 1.0) -> void:
		forms.append(at)
		colors.append(color)
		reach = maxf(reach, size)

	func node(label: String) -> MultiMeshInstance3D:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh
		multi.instance_count = forms.size()
		var data := PackedFloat32Array() # a transform's three rows then the colour, per instance
		data.resize(forms.size() * 16)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in forms.size():
			var xf := forms[i]
			var b := i * 16
			var c := colors[i]
			data[b] = xf.basis.x.x; data[b + 1] = xf.basis.y.x; data[b + 2] = xf.basis.z.x; data[b + 3] = xf.origin.x
			data[b + 4] = xf.basis.x.y; data[b + 5] = xf.basis.y.y; data[b + 6] = xf.basis.z.y; data[b + 7] = xf.origin.y
			data[b + 8] = xf.basis.x.z; data[b + 9] = xf.basis.y.z; data[b + 10] = xf.basis.z.z; data[b + 11] = xf.origin.z
			data[b + 12] = c.r; data[b + 13] = c.g; data[b + 14] = c.b; data[b + 15] = c.a
			lo = lo.min(xf.origin)
			hi = hi.max(xf.origin)
		multi.buffer = data
		multi.custom_aabb = AABB(lo, hi - lo).grow(reach + 4.0)
		var instance := MultiMeshInstance3D.new()
		instance.name = label
		instance.multimesh = multi
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return instance

## The backdrop of a course: `spec` as Backdrop.level_spec (bbox, y_low, y_high, forward), `data` the parsed level (its blocks give the
## supports and the bunting; {} for the lobby, which passes `supports` in the spec instead). Standing at `origin`, named `label`.
static func build(spec: Dictionary, origin: Vector3, label: String, data := {}) -> Node3D:
	var palette := Party.palette()
	var density: float = [0.55, 0.8, 1.0][clampi(Style.quality(), 0, 2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label) & 0x7fffffff
	var box: Rect2 = spec.bbox
	var y_low := float(spec.y_low)
	var y_high := float(spec.y_high)
	var lit := StandardMaterial3D.new()
	lit.vertex_color_use_as_albedo = true
	lit.vertex_color_is_srgb = true
	lit.roughness = 0.7
	lit.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER # decor fades out within 2 m of the camera: nothing fills the lens
	lit.distance_fade_min_distance = 0.8
	lit.distance_fade_max_distance = 2.0
	var spheres := Batch.new(_sphere(10, 5), lit)   # clouds and hills: big, few
	var balls := Batch.new(_sphere(8, 4), lit)      # balloons, pom-poms, lollipops: small, many
	var cylinders := Batch.new(_cylinder(1.0, 1.0, 14), lit)
	var cones := Batch.new(_cylinder(0.0, 1.0, 14), lit)
	var boxes := Batch.new(BoxMesh.new(), lit)
	var root := Node3D.new()
	root.name = label
	root.position = origin
	var sea_y := y_low - SEA_DEPTH
	_sea(root, palette, sea_y)
	_clouds(spheres, rng, palette, box, sea_y, int(46.0 * density))
	_hills(cones, spheres, balls, rng, palette, box, sea_y)
	var forward: Vector2 = spec.forward
	_islands(cylinders, cones, balls, boxes, rng, palette, box, forward, y_low, y_high, int(22.0 * density))
	_balloons(balls, cylinders, rng, palette, box, forward, y_high, int(26.0 * density))
	for batch: Array in [["Spheres", spheres], ["Balls", balls], ["Cylinders", cylinders], ["Cones", cones], ["Boxes", boxes]]:
		var made: Batch = batch[1]
		if not made.forms.is_empty(): root.add_child(made.node(batch[0]))
	var supports := _supports(spec, data, palette, lit)
	if supports != null: root.add_child(supports)
	var bunting := _bunting(data, palette, spec)
	if bunting != null: root.add_child(bunting)
	root.add_child(_confetti(rng, palette, box, y_low, y_high, int(260.0 * density)))
	return root

# ------------------------------------------------------------------ shapes

static func _sphere(sides: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = sides
	mesh.rings = rings
	return mesh

## A unit cylinder along y (height 1, centred), radius `top` and `bottom` at its ends: 0 on top is a cone pointing up.
static func _cylinder(top: float, bottom: float, sides: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh

static func _form(at: Vector3, scale: Vector3, yaw := 0.0, flip := false) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw)
	if flip: basis = basis * Basis(Vector3.RIGHT, PI)
	return Transform3D(basis.scaled_local(scale), at)

static func _tone(role: Dictionary, rng: RandomNumberGenerator, names: Array) -> Color:
	return role[names[rng.randi() % names.size()]]

static func _role(palette: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	return palette[["p", "s", "a", "x", "y"][rng.randi() % 5]]

## A point on x/z at least `clear` m from the box and at most `far` m from it, uniformly over the ring, or Vector2.INF after a few tries.
static func _ring_point(rng: RandomNumberGenerator, box: Rect2, clear: float, far: float) -> Vector2:
	var outer := box.grow(far)
	var inner := box.grow(clear)
	for attempt in 24:
		var at := Vector2(rng.randf_range(outer.position.x, outer.end.x), rng.randf_range(outer.position.y, outer.end.y))
		if not inner.has_point(at): return at
	return Vector2.INF

# ------------------------------------------------------------------ the world below and far around

## The sea: one big plane in the palette's sea colour (a saturated tone of the sky, deeper than its horizon, so the clouds stand out of it).
static func _sea(root: Node3D, palette: Dictionary, sea_y: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(REACH, REACH)
	var material := StandardMaterial3D.new()
	material.albedo_color = palette.sea
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.name = "Sea"
	node.mesh = plane
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, sea_y - 4.0, 0.0)
	node.extra_cull_margin = REACH
	root.add_child(node)

## Soft clouds on the sea: puffs of three flattened balls in white and the palettes' palest tones.
static func _clouds(spheres: Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, sea_y: float, count: int) -> void:
	var centre := box.get_center()
	for i in count:
		var radius := rng.randf_range(10.0, 30.0)
		var at := Vector3(centre.x + rng.randf_range(-480.0, 480.0), sea_y + rng.randf_range(-2.0, 4.0), centre.y + rng.randf_range(-480.0, 480.0))
		var tone: Color = Color.WHITE if rng.randf() < 0.6 else (_role(palette, rng) as Dictionary).pale
		for k in 3:
			var part := radius * (1.0 if k == 0 else rng.randf_range(0.6, 0.8))
			var shift := Vector3(0.0, 0.0, 0.0) if k == 0 else Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * radius * 0.95
			spheres.add(_form(at + shift, Vector3(part, part * 0.6, part)), tone, radius * 2.0)

## Landmarks on the horizon, standing in the sea: round candy domes and a few tall party hats with a pom-pom, all melting into the haze.
static func _hills(cones: Batch, spheres: Batch, balls: Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, sea_y: float) -> void:
	var centre := box.get_center()
	var count := 11
	for i in count:
		var angle := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
		var distance := rng.randf_range(HILL_RING.x, HILL_RING.y) + maxf(box.size.x, box.size.y) * 0.5
		var at := Vector3(centre.x + cos(angle) * distance, sea_y, centre.y + sin(angle) * distance)
		var role := _role(palette, rng)
		if i % 3 == 0:
			var height := rng.randf_range(70.0, 130.0)
			var radius := height * 0.32
			cones.add(_form(at + Vector3(0.0, height * 0.5 - 8.0, 0.0), Vector3(radius, height, radius)), role.main, radius)
			balls.add(_form(at + Vector3(0.0, height - 8.0 + radius * 0.12, 0.0), Vector3(radius * 0.22, radius * 0.22, radius * 0.22)), palette.cream, radius)
		else:
			var radius := rng.randf_range(45.0, 90.0)
			spheres.add(_form(at + Vector3(0.0, radius * 0.1, 0.0), Vector3(radius, radius * 0.7, radius)), role.main, radius)

## Islands around the course, mostly up in the sky beside and beyond it where a player looking over the walls sees them: a disc on a
## downward cone, with a lollipop, a party hat, a gift box or a balloon or two on top.
static func _islands(cylinders: Batch, cones: Batch, balls: Batch, boxes: Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2,
		forward: Vector2, y_low: float, y_high: float, count: int) -> void:
	for i in count:
		var radius := rng.randf_range(5.0, 20.0)
		var spot := _ring_point(rng, box, MIN_SIDE + radius + 4.0, PLACE_REACH)
		if i % 2 == 0: # half of them beyond the goal: the view along the course ends in a world
			var ahead := box.get_center() + forward * (maxf(box.size.x, box.size.y) * 0.5 + rng.randf_range(MIN_SIDE + radius + 10.0, 200.0)) \
				+ forward.orthogonal() * rng.randf_range(-90.0, 90.0)
			if not box.grow(MIN_SIDE + radius + 4.0).has_point(ahead): spot = ahead
		if spot == Vector2.INF: continue
		var low := rng.randf() < 0.3
		var top := rng.randf_range(y_low - 30.0, y_low + 4.0) if low else rng.randf_range(y_high - 6.0, y_high + 40.0)
		var role := _role(palette, rng)
		var thick := 2.4
		cylinders.add(_form(Vector3(spot.x, top - thick * 0.5, spot.y), Vector3(radius, thick, radius)), role.soft, radius)
		var depth := radius * rng.randf_range(0.8, 1.3)
		cones.add(_form(Vector3(spot.x, top - thick - depth * 0.5, spot.y), Vector3(radius, depth, radius), 0.0, true), role.deep, radius)
		for k in rng.randi_range(1, 4):
			var along := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, radius * 0.7)
			var base := Vector3(spot.x + along.x, top, spot.y + along.y)
			var prop := _role(palette, rng)
			match rng.randi() % 4:
				0: # lollipop
					var stalk := rng.randf_range(2.5, 5.0)
					cylinders.add(_form(base + Vector3(0.0, stalk * 0.5, 0.0), Vector3(0.14, stalk, 0.14)), palette.cream, 0.2)
					var head := rng.randf_range(0.9, 1.9)
					balls.add(_form(base + Vector3(0.0, stalk + head * 0.6, 0.0), Vector3(head, head, head * 0.35), rng.randf() * TAU), prop.main, head)
				1: # party hat
					var tall := rng.randf_range(2.2, 4.5)
					var wide := tall * 0.38
					cones.add(_form(base + Vector3(0.0, tall * 0.5, 0.0), Vector3(wide, tall, wide)), prop.main, wide)
					balls.add(_form(base + Vector3(0.0, tall + 0.15, 0.0), Vector3(0.35, 0.35, 0.35)), palette.cream, 0.35)
				2: # gift box
					var side := rng.randf_range(1.4, 3.2)
					boxes.add(_form(base + Vector3(0.0, side * 0.5, 0.0), Vector3(side, side, side), rng.randf() * TAU), prop.main, side)
					boxes.add(_form(base + Vector3(0.0, side * 0.5, 0.0), Vector3(side * 1.04, side * 1.04, side * 0.22), rng.randf() * TAU), prop.pale, side)
				_: # balloon on a string
					var string := rng.randf_range(3.0, 6.0)
					var ball := rng.randf_range(1.0, 2.0)
					cylinders.add(_form(base + Vector3(0.0, string * 0.5, 0.0), Vector3(0.04, string, 0.04)), palette.cream, 0.1)
					balls.add(_form(base + Vector3(0.0, string + ball, 0.0), Vector3(ball * 0.85, ball, ball * 0.85)), prop.main, ball)

## Balloons loose in the sky above and beyond the course, in the palette's colours: the first thing a player looking over the walls sees.
static func _balloons(balls: Batch, cylinders: Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, forward: Vector2, y_high: float, count: int) -> void:
	for i in count:
		var radius := rng.randf_range(1.6, 4.0)
		var spot := box.get_center() + forward * (maxf(box.size.x, box.size.y) * 0.5 + rng.randf_range(10.0, 160.0)) + forward.orthogonal() * rng.randf_range(-70.0, 70.0)
		if i % 3 == 0: spot = _ring_point(rng, box, MIN_SIDE + radius, 120.0)
		if spot == Vector2.INF or box.grow(MIN_SIDE + radius).has_point(spot): continue
		var at := Vector3(spot.x, y_high + rng.randf_range(8.0, 55.0), spot.y)
		var role := _role(palette, rng)
		balls.add(_form(at, Vector3(radius * 0.85, radius, radius * 0.85)), role.main, radius)
		cylinders.add(_form(at - Vector3(0.0, radius * 1.0 + 3.0, 0.0), Vector3(0.05, 6.0, 0.05)), palette.cream, 0.1)

# ------------------------------------------------------------------ what the course stands on

## Candy cones under the course's ground slabs (and under the lobby yard): the course reads as a floating island. Hung straight under the
## slab's underside, along its long side every few metres.
static func _supports(spec: Dictionary, data: Dictionary, palette: Dictionary, shared: Material) -> MultiMeshInstance3D:
	var cones := Batch.new(_cylinder(0.0, 1.0, 12), shared)
	var slabs: Array = []
	var solids: Array[AABB] = []
	if not data.is_empty():
		for block: Dictionary in data.blocks:
			var xf: Transform3D = block.xf
			var half := (block.size as Vector3) * 0.5
			var reach := Vector3(absf(xf.basis.x.x) * half.x + absf(xf.basis.y.x) * half.y + absf(xf.basis.z.x) * half.z,
				absf(xf.basis.x.y) * half.x + absf(xf.basis.y.y) * half.y + absf(xf.basis.z.y) * half.z,
				absf(xf.basis.x.z) * half.x + absf(xf.basis.y.z) * half.y + absf(xf.basis.z.z) * half.z)
			solids.append(AABB(xf.origin - reach, reach * 2.0))
		for block: Dictionary in data.blocks:
			var size: Vector3 = block.size
			var xf: Transform3D = block.xf
			if str(block.k) != "box": continue
			if size.y > 2.0 or minf(size.x, size.z) < 3.0: continue
			if absf(xf.basis.y.y) < 0.99: continue # tilted: a ramp
			var yaw := xf.basis.get_euler().y
			var under := xf.origin - Vector3(0.0, size.y * 0.5, 0.0)
			if _has_ground_below(solids, under, Vector2(size.x, size.z)): continue # a beam or roof over the course: a cone would hang in the play space
			slabs.append({"p": under, "size": Vector2(size.x, size.z), "yaw": yaw})
	for extra: Dictionary in spec.get("supports", []): slabs.append(extra)
	var tone: Color = palette.get("support", (palette.p as Dictionary).deep) # the night look hangs dark metal cones
	for slab: Dictionary in slabs:
		var size: Vector2 = slab.size
		var yaw: float = slab.yaw if slab.has("yaw") else 0.0
		var short := minf(size.x, size.y)
		var long_axis := Vector3(1.0, 0.0, 0.0) if size.x >= size.y else Vector3(0.0, 0.0, 1.0)
		var length := maxf(size.x, size.y)
		var radius := minf(short * 0.42, 9.0)
		var count := clampi(roundi((length - short) / (radius * 2.2)) + 1, 1, 6)
		for i in count:
			var offset := 0.0 if count == 1 else lerpf(-(length - short) * 0.5, (length - short) * 0.5, float(i) / float(count - 1))
			var at: Vector3 = slab.p + Basis(Vector3.UP, yaw) * (long_axis * offset)
			var depth := clampf(radius * 1.6, 3.0, 14.0)
			cones.add(_form(at - Vector3(0.0, depth * 0.5, 0.0), Vector3(radius, depth, radius), 0.0, true), tone, radius)
	return cones.node("Supports") if not cones.forms.is_empty() else null

## True when a solid lies under the slab (its top below the slab's underside, overlapping the footprint by more than a metre each way).
static func _has_ground_below(solids: Array[AABB], under: Vector3, footprint: Vector2) -> bool:
	var low := Vector2(under.x - footprint.x * 0.5, under.z - footprint.y * 0.5)
	var high := Vector2(under.x + footprint.x * 0.5, under.z + footprint.y * 0.5)
	for solid: AABB in solids:
		if solid.end.y > under.y - 0.05: continue
		var overlap_x := minf(high.x, solid.end.x) - maxf(low.x, solid.position.x)
		var overlap_z := minf(high.y, solid.end.z) - maxf(low.y, solid.position.z)
		if overlap_x > 1.0 and overlap_z > 1.0: return true
	return false

# ------------------------------------------------------------------ the little things that move

## Pennants along the top of the tall walls, on both long faces, in the palette's colours: only where the line is high above everything a player can
## stand on (style/bunting_rule.gd): never on stair risers or low ledges.
static func _bunting(data: Dictionary, palette: Dictionary, spec: Dictionary) -> MultiMeshInstance3D:
	if data.is_empty(): return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.0, -1.0, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = MOTION
	material.set_shader_parameter("sway", 0.12)
	var batch := Batch.new(mesh, material)
	var tones: Array[Color] = []
	for name: String in ["p", "s", "a", "x", "y"]: tones.append((palette[name] as Dictionary).main)
	tones.append(palette.cream)
	var index := 0
	for pennant: Dictionary in BuntingRule.pennants(data):
		if batch.forms.size() >= BUNTING_MAX: break
		var normal: Vector3 = pennant.normal
		var facing := Basis.looking_at(-normal, Vector3.UP)
		batch.add(Transform3D(facing.scaled_local(Vector3(0.9, 1.1, 1.0)), pennant.at), tones[index % tones.size()], 1.5)
		index += 1
	return batch.node("Bunting") if not batch.forms.is_empty() else null

## Confetti: small flat pieces in the palette's colours falling and turning slowly, everywhere around the course (not on the route).
static func _confetti(rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, y_low: float, y_high: float, count: int) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.45)
	var material := ShaderMaterial.new()
	material.shader = MOTION
	var fall := maxf(60.0, y_high - y_low + 50.0)
	material.set_shader_parameter("fall", fall)
	var batch := Batch.new(quad, material)
	var colors: Array = palette.confetti
	for i in count:
		var spot := _ring_point(rng, box, 3.0, 55.0) if rng.randf() < 0.7 else Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if spot == Vector2.INF: continue
		var inside := box.has_point(spot)
		var top := rng.randf_range(y_high + 8.0, y_high + 8.0 + fall * 0.5) if inside else rng.randf_range(y_low, y_high + fall * 0.5)
		batch.add(Transform3D(Basis.IDENTITY, Vector3(spot.x, top, spot.y)), colors[rng.randi() % colors.size()], fall)
	return batch.node("Confetti")
