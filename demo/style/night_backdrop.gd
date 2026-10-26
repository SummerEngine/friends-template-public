extends RefCounted
## The world of the night look (style/night_look.gd): under a dark sky (style/night_sky.gdshader) a black void with a faint grid far below the course,
## monoliths with light strips on the horizon, floating dark hexagon platforms with a glowing rim, pylons, stacks and monoliths of their own, a few big
## light rings standing in the sky, the course on dark supports, light blades hanging along the tops of its tall walls instead of pennants and embers
## rising around it instead of confetti. The same rules, helpers and budget as the party world (style/party_backdrop.gd, which this reuses: its `Batch`,
## shapes, ring points and supports): no collision, no shadows, no lights, no textures; dark lit pieces and unlit light pieces, one MultiMesh per shape,
## at most 11 draw calls and about 700 instances at quality High (55 % at Low, Android's default). Placement is seeded: a level always grows the same world.
## Emission only: nothing here is a light. Rules checked by tools/party_look_check.gd (the same as the party world's).
const Party := preload("res://style/party_look.gd")
const Style := preload("res://style/friends_style.gd")
const World := preload("res://style/party_backdrop.gd")
const BuntingRule := preload("res://style/bunting_rule.gd")
const MOTION := preload("res://style/party_motion.gdshader")
const VOID := preload("res://style/night_void.gdshader")
const MONOLITHS := 12
const MONOLITH_RING := Vector2(240.0, 430.0)
const BLADE_MAX := 700
const SHINE := 1.3              ## the unlit pieces are brighter than white, so they bloom (the environment's glow starts at 1.0)

## The backdrop of a course: `spec` as Backdrop.level_spec (bbox, y_low, y_high, forward), `data` the parsed level ({} for the lobby, which passes
## `supports` in the spec instead). Standing at `origin`, named `label`.
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
	lit.roughness = 0.5
	lit.metallic = 0.3
	lit.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER # decor fades out within 2 m of the camera: nothing fills the lens
	lit.distance_fade_min_distance = 0.8
	lit.distance_fade_max_distance = 2.0
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.vertex_color_use_as_albedo = true
	shine.vertex_color_is_srgb = true
	shine.albedo_color = Color(SHINE, SHINE, SHINE)
	shine.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	shine.distance_fade_min_distance = 0.8
	shine.distance_fade_max_distance = 2.0
	var boxes := World.Batch.new(BoxMesh.new(), lit)                   # monoliths, pylons, stacks
	var slabs := World.Batch.new(World._cylinder(1.0, 1.0, 6), lit)     # the hexagon platforms
	var cones := World.Batch.new(World._cylinder(0.0, 1.0, 6), lit)     # their undersides
	var edges := World.Batch.new(World._cylinder(1.0, 1.0, 6), shine)   # their glowing rims
	var strips := World.Batch.new(BoxMesh.new(), shine)                # light strips
	var orbs := World.Batch.new(World._sphere(8, 4), shine)            # beacons
	var rings := World.Batch.new(_torus(), shine)                      # the light rings in the sky
	var root := Node3D.new()
	root.name = label
	root.position = origin
	var sea_y := y_low - World.SEA_DEPTH
	_void(root, palette, sea_y)
	_monoliths(boxes, strips, orbs, rng, palette, box, sea_y)
	var forward: Vector2 = spec.forward
	_platforms(boxes, slabs, cones, edges, strips, orbs, rng, palette, box, forward, y_low, y_high, int(22.0 * density))
	_rings(rings, rng, palette, box, forward, y_high, int(5.0 * density + 0.5))
	for batch: Array in [["Boxes", boxes], ["Cylinders", slabs], ["Cones", cones], ["Edges", edges], ["Strips", strips], ["Orbs", orbs], ["Rings", rings]]:
		var made: World.Batch = batch[1]
		if not made.forms.is_empty(): root.add_child(made.node(batch[0]))
	var supports := World._supports(spec, data, palette, lit)
	if supports != null: root.add_child(supports)
	var blades := _blades(data, palette)
	if blades != null: root.add_child(blades)
	root.add_child(_embers(rng, palette, box, y_low, y_high, int(240.0 * density)))
	return root

# ------------------------------------------------------------------ the world below and far around

## The void: one plane in the palette's sea colour with a faint grid in the accent's dim tone that fades into the dark.
static func _void(root: Node3D, palette: Dictionary, sea_y: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(World.REACH, World.REACH)
	var material := ShaderMaterial.new()
	material.shader = VOID
	material.set_shader_parameter("base", palette.sea)
	material.set_shader_parameter("line_color", (palette.p as Dictionary).deep)
	var node := MeshInstance3D.new()
	node.name = "Void"
	node.mesh = plane
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, sea_y - 4.0, 0.0)
	node.extra_cull_margin = World.REACH
	root.add_child(node)

## A dark tone of the void, a little lighter or darker per piece.
static func _dark(palette: Dictionary, rng: RandomNumberGenerator, lift := 0.0) -> Color:
	var base: Color = palette.wall
	return Color.from_hsv(base.h, base.s, clampf(base.v * rng.randf_range(0.8, 1.5) + 0.07 + lift, 0.0, 1.0))

## The glow colour of a strip or a beacon: the accent mostly, its soft tone and the second role now and then.
static func _light(palette: Dictionary, rng: RandomNumberGenerator) -> Color:
	var roll := rng.randf()
	if roll < 0.55: return (palette.p as Dictionary).main
	if roll < 0.8: return (palette.p as Dictionary).soft
	if roll < 0.92: return (palette.s as Dictionary).main
	return (palette.a as Dictionary).main

## Monoliths on the horizon standing in the void, their front (+z) turned to the course, each with one to three light strips up its face; a few wear a beacon.
static func _monoliths(boxes: World.Batch, strips: World.Batch, orbs: World.Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, sea_y: float) -> void:
	var centre := box.get_center()
	for i in MONOLITHS:
		var angle := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / MONOLITHS
		var distance := rng.randf_range(MONOLITH_RING.x, MONOLITH_RING.y) + maxf(box.size.x, box.size.y) * 0.5
		var base := Vector3(centre.x + cos(angle) * distance, sea_y, centre.y + sin(angle) * distance)
		var height := rng.randf_range(70.0, 170.0)
		var wide := rng.randf_range(14.0, 34.0)
		var deep := rng.randf_range(10.0, 22.0)
		var towards := Vector3(centre.x - base.x, 0.0, centre.y - base.z)
		var yaw := atan2(towards.x, towards.z) + rng.randf_range(-0.35, 0.35)
		var turn := Basis(Vector3.UP, yaw)
		boxes.add(World._form(base + Vector3(0.0, height * 0.5 - 8.0, 0.0), Vector3(wide, height, deep), yaw), _dark(palette, rng), maxf(wide, height))
		for k in rng.randi_range(1, 3):
			var strip_height := height * rng.randf_range(0.35, 0.9)
			var local := Vector3(rng.randf_range(-0.38, 0.38) * wide, strip_height * 0.5 - 8.0 + rng.randf_range(0.0, height - strip_height), deep * 0.5 + 0.3)
			strips.add(Transform3D(turn.scaled_local(Vector3(rng.randf_range(0.7, 1.5), strip_height, 0.4)), base + turn * local), _light(palette, rng), strip_height)
		if i % 3 == 0:
			var beacon := rng.randf_range(1.2, 2.4)
			orbs.add(World._form(base + Vector3(0.0, height - 8.0 + beacon * 1.4, 0.0), Vector3(beacon, beacon, beacon)), (palette.p as Dictionary).main, beacon)

## Floating hexagon platforms around the course, mostly up in the sky beside and beyond it: a dark slab on a downward hexagon cone with a glowing rim, and a
## monolith with a light strip, a pylon with a beacon, or a stack of three plates with glowing seams on top.
static func _platforms(boxes: World.Batch, slabs: World.Batch, cones: World.Batch, edges: World.Batch, strips: World.Batch, orbs: World.Batch,
		rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, forward: Vector2, y_low: float, y_high: float, count: int) -> void:
	for i in count:
		var radius := rng.randf_range(5.0, 20.0)
		var spot := World._ring_point(rng, box, World.MIN_SIDE + radius + 4.0, World.PLACE_REACH)
		if i % 2 == 0: # half of them beyond the goal: the view along the course ends in a world
			var ahead := box.get_center() + forward * (maxf(box.size.x, box.size.y) * 0.5 + rng.randf_range(World.MIN_SIDE + radius + 10.0, 200.0)) \
				+ forward.orthogonal() * rng.randf_range(-90.0, 90.0)
			if not box.grow(World.MIN_SIDE + radius + 4.0).has_point(ahead): spot = ahead
		if spot == Vector2.INF: continue
		var low := rng.randf() < 0.3
		var top := rng.randf_range(y_low - 30.0, y_low + 4.0) if low else rng.randf_range(y_high - 6.0, y_high + 40.0)
		var thick := 2.4
		var tilt := rng.randf() * TAU
		slabs.add(World._form(Vector3(spot.x, top - thick * 0.5, spot.y), Vector3(radius, thick, radius), tilt), _dark(palette, rng, 0.02), radius)
		var depth := radius * rng.randf_range(0.7, 1.2)
		cones.add(World._form(Vector3(spot.x, top - thick - depth * 0.5, spot.y), Vector3(radius, depth, radius), tilt, true), _dark(palette, rng), radius)
		edges.add(World._form(Vector3(spot.x, top - thick * 0.5, spot.y), Vector3(radius * 1.012, 0.22, radius * 1.012), tilt), (palette.p as Dictionary).main, radius)
		for k in rng.randi_range(1, 3):
			var along := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, radius * 0.6)
			var base := Vector3(spot.x + along.x, top, spot.y + along.y)
			var yaw := rng.randf() * TAU
			var turn := Basis(Vector3.UP, yaw)
			match rng.randi() % 3:
				0: # monolith with a light strip
					var tall := rng.randf_range(3.0, 9.0)
					var wide := rng.randf_range(0.9, 2.2)
					boxes.add(World._form(base + Vector3(0.0, tall * 0.5, 0.0), Vector3(wide, tall, wide * 0.7), yaw), _dark(palette, rng, 0.02), tall)
					strips.add(Transform3D(turn.scaled_local(Vector3(0.14, tall * 0.7, 0.1)), base + turn * Vector3(0.0, tall * 0.5, wide * 0.35 + 0.05)), _light(palette, rng), tall)
				1: # pylon with a beacon
					var tall := rng.randf_range(5.0, 12.0)
					boxes.add(World._form(base + Vector3(0.0, tall * 0.5, 0.0), Vector3(0.35, tall, 0.35), yaw), _dark(palette, rng, 0.03), tall)
					var ball := rng.randf_range(0.35, 0.7)
					orbs.add(World._form(base + Vector3(0.0, tall + ball, 0.0), Vector3(ball, ball, ball)), _light(palette, rng), ball)
				_: # a stack of three plates with glowing seams
					var seam: Color = _light(palette, rng)
					var width := rng.randf_range(2.4, 3.4)
					for level in 3:
						var side := width * (1.0 - 0.25 * level)
						var y := 0.45 + level * 0.9
						boxes.add(World._form(base + Vector3(0.0, y, 0.0), Vector3(side, 0.9, side), yaw), _dark(palette, rng, 0.03), side)
						strips.add(Transform3D(turn.scaled_local(Vector3(side * 1.03, 0.07, side * 1.03)), base + Vector3(0.0, y + 0.45, 0.0)), seam, side)

## A few big light rings standing in the sky around the course, their axes turned to it, tilted a little: the landmarks of the night.
static func _rings(rings: World.Batch, rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, forward: Vector2, y_high: float, count: int) -> void:
	for i in count:
		var radius := rng.randf_range(14.0, 34.0)
		var spot := World._ring_point(rng, box, World.MIN_SIDE + radius + 40.0, 300.0)
		if i % 2 == 0: # half of them beyond the goal
			var ahead := box.get_center() + forward * (maxf(box.size.x, box.size.y) * 0.5 + rng.randf_range(radius + 70.0, 260.0)) + forward.orthogonal() * rng.randf_range(-120.0, 120.0)
			if not box.grow(World.MIN_SIDE + radius + 40.0).has_point(ahead): spot = ahead
		if spot == Vector2.INF: continue
		var towards := box.get_center() - spot
		var yaw := atan2(towards.x, towards.y)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5 + rng.randf_range(-0.35, 0.35)) * Basis(Vector3.UP, rng.randf() * TAU)
		var tone: Color = (palette.p as Dictionary).main if i % 2 == 0 else (palette.s as Dictionary).main
		rings.add(Transform3D(basis.scaled_local(Vector3(radius, radius, radius)), Vector3(spot.x, y_high + rng.randf_range(20.0, 90.0), spot.y)), tone, radius)

static func _torus() -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.outer_radius = 1.0
	mesh.inner_radius = 0.97
	mesh.rings = 48
	mesh.ring_segments = 6
	return mesh

# ------------------------------------------------------------------ the little things that move

## Light blades along the top of the tall walls, on both long faces, where the party world hangs pennants (style/bunting_rule.gd: the same places, so never
## on stair risers or low ledges): thin hanging strips, bright at the top and fading to the dark, swaying a little.
static func _blades(data: Dictionary, palette: Dictionary) -> MultiMeshInstance3D:
	if data.is_empty(): return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.045, 0.0, 0.0), Vector3(0.045, 0.0, 0.0), Vector3(0.045, -1.0, 0.0), Vector3(-0.045, -1.0, 0.0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = MOTION
	material.set_shader_parameter("sway", 0.08)
	material.set_shader_parameter("fade_down", 0.85)
	material.set_shader_parameter("boost", SHINE)
	var batch := World.Batch.new(mesh, material)
	var tones: Array[Color] = [(palette.p as Dictionary).main, (palette.p as Dictionary).main, (palette.p as Dictionary).soft, (palette.s as Dictionary).main]
	var lengths := [1.2, 0.8, 1.3, 0.9] # never longer than the party world's pennants (1.1 m): the same clearance rule holds
	var index := 0
	for pennant: Dictionary in BuntingRule.pennants(data):
		if batch.forms.size() >= BLADE_MAX: break
		var normal: Vector3 = pennant.normal
		var facing := Basis.looking_at(-normal, Vector3.UP)
		batch.add(Transform3D(facing.scaled_local(Vector3(1.0, float(lengths[index % lengths.size()]), 1.0)), pennant.at), tones[index % tones.size()], 2.0)
		index += 1
	return batch.node("Bunting") if not batch.forms.is_empty() else null

## Embers: small bright flat pieces climbing and turning slowly, everywhere around the course (not on the route): the column of one starts over the
## course's highest point plus 8 m when it begins inside its box, like the party world's confetti.
static func _embers(rng: RandomNumberGenerator, palette: Dictionary, box: Rect2, y_low: float, y_high: float, count: int) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var material := ShaderMaterial.new()
	material.shader = MOTION
	var fall := maxf(60.0, y_high - y_low + 50.0)
	material.set_shader_parameter("fall", fall)
	material.set_shader_parameter("rise", 1.0)
	material.set_shader_parameter("boost", SHINE)
	var batch := World.Batch.new(quad, material)
	var colors: Array = palette.confetti
	for i in count:
		var spot := World._ring_point(rng, box, 3.0, 55.0) if rng.randf() < 0.7 else Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if spot == Vector2.INF: continue
		var inside := box.has_point(spot)
		var bottom := rng.randf_range(y_high + 8.0, y_high + 8.0 + fall * 0.5) if inside else rng.randf_range(y_low - fall * 0.5, y_high)
		batch.add(Transform3D(Basis.IDENTITY, Vector3(spot.x, bottom, spot.y)), colors[rng.randi() % colors.size()], fall)
	return batch.node("Embers")
