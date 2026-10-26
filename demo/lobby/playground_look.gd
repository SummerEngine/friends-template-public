extends RefCounted
## Client-only picture of the lobby playground (lobby/playground.gd) in the facility look: each solid dressed as what it is (a painted
## swing frame, a padded trampoline, foam steps, a glossy chute, cushions, a sofa, bean bags, a vending machine, potted plants), the
## swing seat and the seesaw plank on their movers, a pit of balls, a bouncing beach ball and a pinwheel posed with the yard's clock.
## Brand-coloured parts take the team's colours (style/team_cast.gd). All static parts are one mesh (one surface per material);
## nothing here collides.
const Layout = preload("res://network/walk_in_lobby.gd")
const Playground = preload("res://lobby/playground.gd")
const Surfaces = preload("res://style/surfaces.gd")
const BlockMesh = preload("res://style/block_mesh.gd")
const TeamCast = preload("res://style/team_cast.gd")
const Party = preload("res://style/party_look.gd")
const FALLBACK: Array[Color] = [Color("2c4bff"), Color("2fb7a5"), Color("ff5a36")]
const SUNNY := Color("f2c230")
const SOFT_WHITE := Color("f4f4f2")
const MAT := Color("2a2d34")
const LEAVES: Array[Color] = [Color("3fa45b"), Color("2f8a4c"), Color("5cbf6a")]
const POT := Color("e9e4dc")
const BALL_COLORS: Array[Color] = [Color("ff5a36"), Color("2c4bff"), Color("2ec27e"), Color("ffd23f"), Color("9b5de5"), Color("18b5b5"), Color("ff7eb6")]
const PIT := Rect2(-17.2, 4.75, 3.5, 3.1)
const BALLS := 420

## The team's chromatic brand colours (up to 3), else a cheerful default set.
static func brand(index: int) -> Color:
	var colors: Array[Color] = []
	for color: Color in TeamCast.brand_colors():
		if color.s >= 0.18 and color.v >= 0.2: colors.append(color)
	if colors.is_empty(): colors.assign(FALLBACK)
	return colors[posmod(index, colors.size())]

static func dress(room: Node3D, playground: Playground) -> void:
	var batch := BlockMesh.Batch.new()
	var foam := 0
	for row: Dictionary in Playground.SOLIDS:
		var xf := Transform3D(Playground.euler(row.get("r", Vector3.ZERO)), Layout.ORIGIN + (row.p as Vector3))
		var size: Vector3 = row.s
		match str(row.look):
			"frame": batch.box(xf, size, 0.05, 2, paint(0.45), paint(0.45), brand(0))
			"step", "tower":
				batch.box(xf, size, 0.1, 3, "block", "block", Surfaces.block_color(foam))
				foam += 1
			"chute": batch.box(xf, size, 0.06, 2, paint(0.2), paint(0.2), SUNNY)
			"rail": batch.box(xf, size, 0.04, 2, paint(0.25), paint(0.25), SOFT_WHITE)
			"cushion": batch.box(xf, size, 0.12, 3, "block", "block", (Party.palette().s as Dictionary).deep if Party.night() else Color("f7c9d6"))
			"sofa": batch.box(xf, size, 0.14, 3, "block", "block", brand(0).lightened(0.25))
			"bean": _bean(batch, xf, size, BALL_COLORS[(foam * 3) % BALL_COLORS.size()]); foam += 1
			"trampoline": _trampoline(batch, xf)
			"vending": _vending(batch, xf, size)
			"plant": _plant(batch, xf, size)
	_add(room, "PlaygroundLook", batch)
	for mover: Dictionary in playground.movers: _mover(mover)
	_ball_pit(room)
	_beach_ball(room, playground)
	_pinwheel(room, playground)

## A painted-surface key of the batch, "paint/<rough>": the colour rides on the vertices, so every colour of one finish is one surface.
static func paint(rough := 0.5) -> String:
	return "paint/%.2f" % (0.3 if rough < 0.4 else (0.5 if rough < 0.65 else 0.75))

## Materials for every key of a batch: painted keys, glow, and the facility's own surfaces.
static func materials(batch: BlockMesh.Batch) -> Dictionary:
	var result := {}
	for key: String in batch.groups:
		if key.begins_with("paint/"):
			var material := Surfaces.paint(Color.WHITE, float(key.get_slice("/", 1)))
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = true
			result[key] = material
		elif key == "glow": result[key] = Surfaces.lamp_material(0.45)
		else: result[key] = Surfaces.material(key)
	return result

static func _add(parent: Node3D, label: String, batch: BlockMesh.Batch, shadows := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = batch.commit(materials(batch))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## A squashed ball sitting on the floor.
static func _bean(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3, color: Color) -> void:
	var squash := Transform3D(Basis().scaled(Vector3(1.0, size.y / size.x * 1.15, 1.0)), xf.origin + Vector3(0.0, 0.02, 0.0))
	batch.lathe(squash, size.x * 0.5, 0.0, 0.0, "block", "block", color)

## The trampoline: a white skirt, a padded rim in the team's colour and a dark mat with a target ring.
static func _trampoline(batch: BlockMesh.Batch, xf: Transform3D) -> void:
	batch.lathe(xf * Transform3D(Basis(), Vector3(0.0, -0.04, 0.0)), 1.42, 0.32, 0.04, paint(0.4), paint(0.4), SOFT_WHITE)
	batch.lathe(xf * Transform3D(Basis(), Vector3(0.0, 0.14, 0.0)), 1.47, 0.12, 0.06, "block", "block", brand(0))
	batch.lathe(xf * Transform3D(Basis(), Vector3(0.0, 0.185, 0.0)), 1.3, 0.05, 0.0, paint(0.8), paint(0.8), MAT)
	batch.lathe(xf * Transform3D(Basis(), Vector3(0.0, 0.19, 0.0)), 0.55, 0.05, 0.0, paint(0.7), paint(0.7), SUNNY)
	batch.lathe(xf * Transform3D(Basis(), Vector3(0.0, 0.195, 0.0)), 0.35, 0.05, 0.0, paint(0.8), paint(0.8), MAT)

## The vending machine: a painted cabinet, a glowing window with shelves of cans, a slot and a tray.
static func _vending(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3) -> void:
	batch.box(xf, size, 0.05, 2, paint(0.35), paint(0.35), brand(1))
	var front := -size.z * 0.5 - 0.01
	batch.box(xf * Transform3D(Basis(), Vector3(-0.12, 0.2, front)), Vector3(0.7, 1.25, 0.02), 0.0, 1, "glow", "glow")
	for shelf in 4:
		for can in 4:
			var color := BALL_COLORS[(shelf * 2 + can) % BALL_COLORS.size()]
			batch.box(xf * Transform3D(Basis(), Vector3(-0.38 + can * 0.17, -0.25 + shelf * 0.3, front - 0.05)), Vector3(0.1, 0.2, 0.08), 0.03, 1, paint(0.3), paint(0.3), color)
	batch.box(xf * Transform3D(Basis(), Vector3(0.38, 0.35, front)), Vector3(0.16, 0.5, 0.03), 0.0, 1, paint(0.5), paint(0.5), MAT)
	batch.box(xf * Transform3D(Basis(), Vector3(-0.12, -0.7, front)), Vector3(0.7, 0.22, 0.04), 0.02, 1, paint(0.5), paint(0.5), MAT)

## A potted plant: a round pot and a bush of leafy balls.
static func _plant(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3) -> void:
	batch.lathe(xf, size.x * 0.5, size.y, 0.05, paint(0.7), paint(0.7), POT)
	var top := size.y * 0.5
	for leaf: Array in [[Vector3(0.0, top + 0.45, 0.0), 0.42], [Vector3(0.22, top + 0.85, 0.08), 0.32], [Vector3(-0.2, top + 0.8, -0.1), 0.3],
			[Vector3(0.05, top + 1.15, -0.05), 0.24]]:
		batch.lathe(xf * Transform3D(Basis(), leaf[0]), float(leaf[1]), 0.0, 0.0, paint(0.8), paint(0.8), LEAVES[int(leaf[1] * 10.0) % LEAVES.size()])

## A mover's picture as its own child mesh: the swing seat on two ropes, the seesaw plank with handles and seats.
static func _mover(mover: Dictionary) -> void:
	var row: Dictionary = mover.row
	var batch := BlockMesh.Batch.new()
	var part: Dictionary = row.parts[0]
	var seat := Transform3D(Basis(), part.p)
	if row.name == "swing":
		batch.box(seat, part.s, 0.05, 2, paint(0.4), paint(0.4), SUNNY)
		for side: float in [-1.0, 1.0]:
			var z: float = (part.s as Vector3).z * 0.5 * side * 0.85
			batch.box(Transform3D(Basis(), Vector3(0.0, -float(row.rope) * 0.5, z)), Vector3(0.035, float(row.rope), 0.035), 0.0, 1, "steel", "steel")
	else:
		batch.box(seat, part.s, 0.05, 2, paint(0.4), paint(0.4), SUNNY)
		for side: float in [-1.0, 1.0]:
			var end: float = (part.s as Vector3).z * 0.5 * side
			batch.box(Transform3D(Basis(), Vector3(0.0, 0.25, end - side * 0.55)), Vector3(0.06, 0.4, 0.06), 0.02, 1, "steel", "steel")
			batch.box(Transform3D(Basis(), Vector3(0.0, 0.45, end - side * 0.55)), Vector3(0.4, 0.06, 0.06), 0.03, 2, paint(0.4), paint(0.4), brand(0))
			batch.box(Transform3D(Basis(), Vector3(0.0, 0.16, end - side * 0.25)), Vector3(0.55, 0.08, 0.4), 0.04, 2, "block", "block", brand(1))
	_add(mover.body, "MoverLook", batch)

## The ball pit: a few hundred glossy balls in one multimesh, heaped to about knee height (they do not collide).
static func _ball_pit(room: Node3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.radial_segments = 10
	sphere.rings = 5
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.3
	sphere.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = sphere
	multi.instance_count = BALLS
	var random := RandomNumberGenerator.new()
	random.seed = 7
	for index in BALLS:
		var x := random.randf_range(PIT.position.x + 0.12, PIT.end.x - 0.12)
		var z := random.randf_range(PIT.position.y + 0.12, PIT.end.y - 0.12)
		var y := 0.12 + random.randf() * 0.32
		multi.set_instance_transform(index, Transform3D(Basis(), Layout.ORIGIN + Vector3(x, y, z)))
		multi.set_instance_color(index, BALL_COLORS[random.randi() % BALL_COLORS.size()])
	var node := MultiMeshInstance3D.new()
	node.name = "BallPit"
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(node)

## A striped beach ball bouncing in the pit.
static func _beach_ball(room: Node3D, playground: Playground) -> void:
	var ball := MeshInstance3D.new()
	ball.name = "BeachBall"
	ball.mesh = _striped_ball(0.34)
	room.add_child(ball)
	playground.animated.append({"node": ball, "base": Layout.ORIGIN + Vector3(-15.3, 0.34, 6.3), "kind": "bounce"})

## A ball of six coloured segments (one mesh, vertex colours).
static func _striped_ball(radius: float) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	var stripes: Array[Color] = [brand(0), SOFT_WHITE, SUNNY, SOFT_WHITE, brand(1), SOFT_WHITE]
	for vertex: Vector3 in vertices:
		colors.append(stripes[int(floor((atan2(vertex.z, vertex.x) + PI) / TAU * 6.0)) % 6])
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.35
	mesh.surface_set_material(0, material)
	return mesh

## A pinwheel on a pole on the slide tower, turning.
static func _pinwheel(room: Node3D, playground: Playground) -> void:
	var pole := BlockMesh.Batch.new()
	var top := Layout.ORIGIN + Vector3(9.3, 1.6, -13.15)
	pole.box(Transform3D(Basis(), top + Vector3(0.0, 0.6, 0.0)), Vector3(0.05, 1.2, 0.05), 0.0, 1, "steel", "steel")
	_add(room, "PinwheelPole", pole)
	var blades := BlockMesh.Batch.new()
	for k in 4:
		var color: Color = [brand(0), SUNNY, brand(1), SOFT_WHITE][k]
		var along := Basis(Vector3.BACK, k * PI * 0.5)
		blades.triangles(Transform3D(along, Vector3.ZERO), PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.36, 0.0, 0.0), Vector3(0.36, 0.36, 0.0)]),
			false, paint(0.5), paint(0.5), color)
	var wheel := _add(room, "Pinwheel", blades, false)
	for surface in wheel.mesh.get_surface_count(): (wheel.mesh.surface_get_material(surface) as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	playground.animated.append({"node": wheel, "base": top + Vector3(0.0, 1.2, 0.08), "kind": "spin"})
