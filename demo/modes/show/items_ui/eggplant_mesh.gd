extends RefCounted
## HOT EGGPLANT's model (EXPERIMENT, docs/items.md): a 3 m cartoon eggplant built in code, no assets: a glossy purple body (a lathe round a bent spine: a round bulb, a long tapering neck), a green
## calyx with five drooping sepals, a curled stem, a worried face (eyes, brows, an open mouth, a sweat drop) and two orange straps round it; and the harness that ties it to a runner (a belt and
## two shoulder straps in the runner's own rig space). Our own geometry and materials, nothing shared with the course's look. `build()` returns the root: origin at the bottom of the bulb, +Y along
## the eggplant, +Z the face; `mount()` is where it sits on a runner's back (rig space: origin at the feet, -Z forward, +Z back).
const LENGTH := 3.0 ## m, bottom of the bulb to the tip of the stem
const BULB := 0.62 ## m, the bulb's radius
const BODY_TOP := 2.42 ## m, where the body ends under the calyx
const NECK := 0.2 ## m, the body's radius there
const BEND := 0.3 ## m the spine leans (towards +X) by the top of the body
const SIDES := 40
const PURPLE := Color(0.43, 0.13, 0.58)
const PURPLE_DARK := Color(0.2, 0.05, 0.3)
const GREEN := Color(0.26, 0.62, 0.24)
const STRAP := Color(0.93, 0.52, 0.12)
const CREAM := Color(0.98, 0.95, 0.86)
const INK := Color(0.1, 0.06, 0.14)

static var _meshes := {}
static var _materials := {}

## Where the eggplant stands on a runner's back (rig space): behind the hips, leaning back and to the runner's left.
static func mount() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(16.0), 0.0, deg_to_rad(28.0)), EULER_ORDER_YXZ), Vector3(0.08, 0.22, 0.62))

# ------------------------------------------------------------------ the body

static func spine(y: float) -> Vector3:
	return Vector3(BEND * pow(clampf(y / BODY_TOP, 0.0, 1.4), 2.2), y, 0.0)

static func radius(y: float) -> float:
	if y <= BULB: return sqrt(maxf(BULB * BULB - (y - BULB) * (y - BULB), 0.0))
	var u := clampf((y - BULB) / (BODY_TOP - BULB), 0.0, 1.0)
	return NECK + (BULB - NECK) * pow(cos(u * PI * 0.5), 1.1)

static func _rings() -> PackedFloat32Array:
	var ys := PackedFloat32Array()
	for index in 13: ys.append(BULB * (1.0 - cos(float(index) / 12.0 * PI * 0.5))) # the bulb: evenly round
	for index in range(1, 33): ys.append(BULB + (BODY_TOP - BULB) * float(index) / 32.0)
	return ys

## A lathe round the spine: vertex normals from the surface's own derivatives, triangles wound clockwise seen from outside.
static func body_mesh() -> ArrayMesh:
	if _meshes.has("body"): return _meshes.body
	var ys := _rings()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for y: float in ys:
		var row: Array = []
		for side in SIDES + 1:
			var angle := TAU * float(side) / float(SIDES)
			var ring := Vector3(cos(angle), 0.0, sin(angle))
			var point := spine(y) + ring * radius(y)
			var dy := (spine(y + 0.01) - spine(y - 0.01)) / 0.02 + ring * ((radius(y + 0.01) - radius(y - 0.01)) / 0.02)
			var dt := Vector3(-sin(angle), 0.0, cos(angle))
			var normal := dt.cross(dy).normalized()
			if normal.dot(ring) < 0.0: normal = -normal
			if y < 0.001: normal = Vector3.DOWN
			var shade := lerpf(0.72, 1.0, smoothstep(0.0, 1.0, y / 1.1)) * lerpf(1.0, 0.8, smoothstep(1.7, BODY_TOP, y)) # darker under the bulb and up the neck
			row.append([point, normal, Color(PURPLE.r * shade, PURPLE.g * shade, PURPLE.b * shade)])
		grid.append(row)
	for ring in ys.size() - 1:
		for side in SIDES:
			_quad(tool, grid[ring][side], grid[ring][side + 1], grid[ring + 1][side + 1], grid[ring + 1][side])
	_meshes["body"] = tool.commit()
	return _meshes.body

## Adds the quad a b c d (rows of [point, normal, colour]) as two triangles, clockwise seen from where the normals point.
static func _quad(tool: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	for tri: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = tri[0][0]
		var p1: Vector3 = tri[1][0]
		var p2: Vector3 = tri[2][0]
		if (p1 - p0).cross(p2 - p0).length_squared() < 1.0e-12: continue
		var wanted: Vector3 = (tri[0][1] as Vector3) + (tri[1][1] as Vector3) + (tri[2][1] as Vector3)
		var order: Array = tri if (p1 - p0).cross(p2 - p0).dot(wanted) < 0.0 else [tri[0], tri[2], tri[1]]
		for corner: Array in order:
			tool.set_normal(corner[1])
			tool.set_color(corner[2])
			tool.add_vertex(corner[0])

# ------------------------------------------------------------------ the calyx and the stem

## Five sepals: a shell a hand's width over the body's top, its rim scalloped into five points that droop down the body, closing in a lid at the top.
static func calyx_mesh() -> ArrayMesh:
	if _meshes.has("calyx"): return _meshes.calyx
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	var top := BODY_TOP + 0.2
	var grid: Array = []
	for step in steps + 1:
		var w := float(step) / float(steps)
		var row: Array = []
		for side in SIDES + 1:
			var angle := TAU * float(side) / float(SIDES)
			var rim := 2.06 - 0.34 * pow(0.5 + 0.5 * cos(5.0 * angle), 2.2)
			var y := lerpf(rim, top, pow(w, 0.85))
			var flare := 0.075 + 0.07 * (1.0 - w) * (1.0 - w)
			var r := (radius(minf(y, BODY_TOP)) + flare) * (1.0 - 0.75 * smoothstep(0.78, 1.0, w))
			var ring := Vector3(cos(angle), 0.0, sin(angle))
			var point := spine(minf(y, BODY_TOP)) + Vector3(0.0, maxf(y - BODY_TOP, 0.0), 0.0) + ring * r
			var normal := (ring + Vector3(0.0, 0.35 + 1.6 * smoothstep(0.78, 1.0, w), 0.0)).normalized()
			var shade := lerpf(0.85, 1.12, w)
			row.append([point, normal, Color(GREEN.r * shade, GREEN.g * shade, GREEN.b * shade)])
		grid.append(row)
	for step in steps:
		for side in SIDES:
			_quad(tool, grid[step][side], grid[step][side + 1], grid[step + 1][side + 1], grid[step + 1][side])
	_meshes["calyx"] = tool.commit()
	return _meshes.calyx

## A curled stem: a tube along a bent path, round at the tip.
static func stem_mesh() -> ArrayMesh:
	if _meshes.has("stem"): return _meshes.stem
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := spine(BODY_TOP) + Vector3(0.0, 0.16, 0.0)
	var steps := 10
	var sides := 12
	var grid: Array = []
	for step in steps + 1:
		var t := float(step) / float(steps)
		var centre := base + Vector3(0.26 * t * t, 0.48 * t - 0.05 * t * t, 0.0)
		var tangent := (Vector3(0.52 * t, 0.48 - 0.1 * t, 0.0)).normalized()
		var side_axis := Vector3.BACK
		var up_axis := tangent.cross(side_axis).normalized()
		var r := 0.095 * (1.0 - 0.3 * t) * (1.0 if step < steps else 0.0)
		var row: Array = []
		for side in sides + 1:
			var angle := TAU * float(side) / float(sides)
			var out := side_axis * cos(angle) + up_axis * sin(angle)
			row.append([centre + out * r, out, Color(GREEN.r * 0.8, GREEN.g * 0.8, GREEN.b * 0.8)])
		grid.append(row)
	for step in steps:
		for side in sides:
			_quad(tool, grid[step][side], grid[step][side + 1], grid[step + 1][side + 1], grid[step + 1][side])
	_meshes["stem"] = tool.commit()
	return _meshes.stem

# ------------------------------------------------------------------ straps

## A flat strap along `points` (`width` across, `thick` deep), `across` the axis its width lies on. A closed box all the way round.
static func _ribbon(points: Array, width: float, thick: float, across: Vector3, color: Color) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for index in points.size():
		var before: Vector3 = points[maxi(index - 1, 0)]
		var after: Vector3 = points[mini(index + 1, points.size() - 1)]
		var tangent := (after - before).normalized()
		var deep := tangent.cross(across).normalized()
		var centre: Vector3 = points[index]
		var half_w := across * width * 0.5
		var half_t := deep * thick * 0.5
		rows.append([centre - half_w - half_t, centre + half_w - half_t, centre + half_w + half_t, centre - half_w + half_t, [-deep - across, -deep + across, deep + across, deep - across]])
	for index in rows.size() - 1:
		for corner in 4:
			var next := (corner + 1) % 4
			var normal := ((rows[index][4][corner] as Vector3) + (rows[index][4][next] as Vector3)).normalized()
			_quad(tool, [rows[index][corner], normal, color], [rows[index][next], normal, color], [rows[index + 1][next], normal, color], [rows[index + 1][corner], normal, color])
	for end in [0, rows.size() - 1]:
		var sign_value := -1.0 if end == 0 else 1.0
		var tail: Vector3 = ((points[mini(end + 1, points.size() - 1)] as Vector3) - (points[maxi(end - 1, 0)] as Vector3)).normalized() * sign_value
		_quad(tool, [rows[end][0], tail, color], [rows[end][1], tail, color], [rows[end][2], tail, color], [rows[end][3], tail, color])
	return tool.commit()

# ------------------------------------------------------------------ materials

static func material(kind: String) -> Material:
	if _materials.has(kind): return _materials[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"body":
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.26
			m.metallic_specular = 0.7
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.2
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.6
		"green":
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.55
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"strap":
			m.albedo_color = STRAP
			m.roughness = 0.7
			m.vertex_color_use_as_albedo = true
		"cream":
			m.albedo_color = CREAM
			m.roughness = 0.35
		"ink":
			m.albedo_color = INK
			m.roughness = 0.4
		"drop":
			m.albedo_color = Color(0.55, 0.85, 1.0)
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(0.25, 0.55, 0.8)
			m.emission_energy_multiplier = 0.6
	_materials[kind] = m
	return m

# ------------------------------------------------------------------ the assembled model

static func _part(parent: Node3D, mesh: Mesh, kind: String, name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material(kind)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

static func _blob(parent: Node3D, kind: String, at: Vector3, size: Vector3, name: String) -> MeshInstance3D:
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 20
	ball.rings = 10
	var instance := _part(parent, ball, kind, name)
	instance.position = at
	instance.scale = size
	return instance

static func _band(parent: Node3D, y: float, name: String) -> MeshInstance3D:
	var torus := TorusMesh.new()
	var r := radius(y + 0.05) + 0.03
	torus.inner_radius = r - 0.045
	torus.outer_radius = r + 0.045
	torus.rings = 40
	torus.ring_segments = 8
	var instance := _part(parent, torus, "strap", name)
	instance.position = spine(y)
	instance.scale = Vector3(1.0, 1.9, 1.0)
	return instance

## The model (own materials: the body's is its own copy, so a look may flash it). `harness` adds the belt and the shoulder straps (a runner wears it).
static func build(harness := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Eggplant"
	var body := _part(root, body_mesh(), "body", "Body")
	body.material_override = (material("body") as StandardMaterial3D).duplicate()
	_part(root, calyx_mesh(), "green", "Calyx")
	_part(root, stem_mesh(), "green", "Stem")
	_band(root, 0.75, "BandLow")
	_band(root, 1.7, "BandHigh")
	var face := Node3D.new()
	face.name = "Face"
	root.add_child(face)
	var eye_y := 1.44
	var eye_x := spine(eye_y).x
	var face_r := radius(eye_y)
	for side: float in [-1.0, 1.0]:
		var ex := eye_x + side * 0.2
		var ez := sqrt(maxf(face_r * face_r - 0.2 * 0.2, 0.01)) - 0.03
		_blob(face, "cream", Vector3(ex, eye_y, ez), Vector3(0.3, 0.36, 0.2), "Eye")
		_blob(face, "ink", Vector3(ex - side * 0.02, eye_y - 0.02, ez + 0.07), Vector3(0.13, 0.15, 0.07), "Pupil")
		_blob(face, "cream", Vector3(ex - side * 0.04, eye_y + 0.03, ez + 0.1), Vector3(0.04, 0.05, 0.03), "Glint")
		var brow := _blob(face, "ink", Vector3(ex, eye_y + 0.27, ez - 0.02), Vector3(0.26, 0.055, 0.06), "Brow")
		brow.rotation.z = side * 0.42 # worried: the inner ends up
	_blob(face, "ink", Vector3(spine(1.02).x, 1.02, radius(1.02) - 0.02), Vector3(0.22, 0.26, 0.09), "Mouth")
	_blob(face, "drop", Vector3(eye_x + 0.37, 1.72, sqrt(maxf(radius(1.72) * radius(1.72) - 0.37 * 0.37, 0.01)) - 0.01), Vector3(0.09, 0.14, 0.07), "Sweat")
	if harness: _harness(root)
	return root

## The belt round the runner's middle and the two shoulder straps (over the shoulders, down the chest to the belt), in the eggplant's own frame.
static func _harness(root: Node3D) -> void:
	var to_rig := mount()
	var from_rig := to_rig.affine_inverse()
	var harness := Node3D.new()
	harness.name = "Harness"
	root.add_child(harness)
	for side: float in [-1.0, 1.0]:
		var path: Array = []
		for point: Vector3 in [Vector3(0.0, 0.98, 0.5), Vector3(0.0, 1.12, 0.3), Vector3(0.0, 1.34, 0.23), Vector3(0.0, 1.52, 0.08), Vector3(0.0, 1.56, -0.06), Vector3(0.0, 1.44, -0.2), Vector3(0.0, 1.22, -0.25), Vector3(0.0, 1.04, -0.23)]:
			path.append(from_rig * Vector3(side * 0.2, point.y, point.z))
		var strap := MeshInstance3D.new()
		strap.name = "Shoulder"
		strap.mesh = _ribbon(path, 0.09, 0.035, from_rig.basis * Vector3.RIGHT, Color.WHITE)
		strap.material_override = material("strap")
		strap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		harness.add_child(strap)
	var belt := TorusMesh.new()
	belt.inner_radius = 0.265
	belt.outer_radius = 0.345
	belt.rings = 32
	belt.ring_segments = 8
	var instance := MeshInstance3D.new()
	instance.name = "Belt"
	instance.mesh = belt
	instance.material_override = material("strap")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transform = from_rig * Transform3D(Basis.from_scale(Vector3(1.0, 1.5, 0.8)), Vector3(0.0, 1.0, 0.04))
	harness.add_child(instance)
