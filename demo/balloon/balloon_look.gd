extends Node3D
## The balloon as drawn: a slightly egg-shaped balloon (glossy latex in the facility look, comic rubber with an ink outline in the comic
## look), a knot, and a string that trails behind its motion; a pop is a short burst of rubber flecks. Pure look: call
## `follow(sim, delta)` every frame with the BalloonSim being drawn (local or replicated).
## The team cast picks the shape (TeamCast.balloon_shape(): "balloon", a "blimp" that turns to where it drifts, or a "ball") and the
## print on its front (TeamCast.balloon_picture(): balloon.png, else the logo). Every shape stays inside the sim's sphere, so it still
## pops where it is seen to touch.
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const Style := preload("res://style/friends_style.gd")
const Ink := preload("res://style/style_ink.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Surfaces := preload("res://style/surfaces.gd")
const PRINT_SHADER := preload("res://balloon/balloon_print.gdshader")
const STRING_SEGMENTS := 6
const STRING_LENGTH := 1.1
const FLECKS := 10
const BLIMP_THICKNESS := 0.66 ## the blimp hull's radius as a share of the sim's radius
const PRINT_SIZE := {"balloon": 1.15, "ball": 1.2, "blimp": 0.95} ## the print's width as a share of the sim's radius

var color := Ink.TOMATO
var shape := "balloon"
var _body: MeshInstance3D
var _print: MeshInstance3D
var _heading := 0.0
var _knot: MeshInstance3D
var _string: Array[MeshInstance3D] = []
var _string_points: Array[Vector3] = []
var _flecks: Array[MeshInstance3D] = []
var _fleck_velocity: Array[Vector3] = []
var _pop_age := -1.0
var _was_alive := true
var _wobble := 0.0

func _ready() -> void:
	shape = TeamCast.balloon_shape()
	var rubber := _material(color)
	_body = MeshInstance3D.new()
	_body.name = "BalloonBody"
	if shape == "blimp":
		var hull := CapsuleMesh.new()
		hull.radius = BalloonSim.RADIUS * BLIMP_THICKNESS
		hull.height = BalloonSim.RADIUS * 2.0
		hull.radial_segments = 24
		hull.rings = 8
		_body.mesh = hull
		for fin in 3: _body.add_child(_fin(fin, rubber))
	else:
		var sphere := SphereMesh.new()
		sphere.radius = BalloonSim.RADIUS
		sphere.height = BalloonSim.RADIUS * 2.0
		sphere.radial_segments = 24
		sphere.rings = 14
		_body.mesh = sphere
	_body.material_override = rubber
	add_child(_body)
	_print = _print_sticker(TeamCast.balloon_picture())
	if _print != null: add_child(_print)
	_knot = MeshInstance3D.new()
	var knot := CylinderMesh.new()
	knot.top_radius = 0.02
	knot.bottom_radius = 0.09
	knot.height = 0.14
	_knot.mesh = knot
	_knot.material_override = rubber
	add_child(_knot)
	var cord := _material(Ink.INK) if Surfaces.ink() else _cord()
	for i in STRING_SEGMENTS:
		var segment := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.012
		mesh.bottom_radius = 0.012
		mesh.height = 1.0
		mesh.radial_segments = 4
		segment.mesh = mesh
		segment.material_override = cord
		add_child(segment)
		_string.append(segment)
	for i in STRING_SEGMENTS + 1: _string_points.append(Vector3.ZERO)
	for i in FLECKS:
		var fleck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.03, 0.09)
		fleck.mesh = box
		fleck.material_override = rubber
		fleck.visible = false
		add_child(fleck)
		_flecks.append(fleck)
		_fleck_velocity.append(Vector3.ZERO)

## Draw `sim` (alive balloon, its string, or the pop burst).
func follow(sim: RefCounted, delta: float) -> void:
	var alive: bool = sim.alive
	if _was_alive and not alive: _start_pop(sim.position)
	if not _was_alive and alive: _reset_string(sim.position)
	_was_alive = alive
	var tied := shape == "balloon" # only the balloon has a knot and a string
	_body.visible = alive
	_knot.visible = alive and tied
	for segment in _string: segment.visible = alive and tied
	if _print != null:
		_print.visible = alive
		_print.position = sim.position
	if alive:
		_wobble += delta * (2.0 + sim.velocity.length())
		_body.position = sim.position
		match shape:
			"blimp":
				var flat := Vector2(sim.velocity.x, sim.velocity.z)
				if flat.length() > 0.3: _heading = lerp_angle(_heading, atan2(flat.x, flat.y), clampf(delta * 3.0, 0.0, 1.0))
				_body.basis = Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, sin(_wobble) * 0.05)
			"ball":
				_body.rotate_y(delta * 0.6)
			_:
				var squash := clampf(sim.velocity.length() / BalloonSim.MAX_SPEED, 0.0, 1.0) * 0.08
				_body.scale = Vector3(1.0 - squash, 1.12 + squash + sin(_wobble) * 0.015, 1.0 - squash)
				var bottom: Vector3 = sim.position + Vector3.DOWN * (BalloonSim.RADIUS * 1.12)
				_knot.position = bottom + Vector3.DOWN * 0.05
				_follow_string(bottom + Vector3.DOWN * 0.1, sim.velocity, delta)
	_step_pop(delta)

## One tail fin of the blimp (0 on top, 1 and 2 at the sides), at the back end of the hull (the capsule's -Y before it is laid down).
func _fin(fin: int, rubber: Material) -> MeshInstance3D:
	var around: float = [0.0, PI * 0.5, -PI * 0.5][fin]
	var plate := BoxMesh.new()
	plate.size = Vector3(0.04, BalloonSim.RADIUS * 0.4, BalloonSim.RADIUS * 0.34)
	var node := MeshInstance3D.new()
	node.mesh = plate
	node.material_override = rubber
	node.basis = Basis(Vector3.UP, around)
	node.position = Vector3(0.0, -BalloonSim.RADIUS * 0.72, 0.0) + Basis(Vector3.UP, around) * Vector3(0.0, 0.0, BalloonSim.RADIUS * BLIMP_THICKNESS * 0.9)
	return node

## The print as a round sticker on paper in a ring (ink in the comic look) that faces each camera from in front of the body (balloon_print.gdshader);
## null without a picture.
func _print_sticker(picture: Texture2D) -> MeshInstance3D:
	var art := picture.get_image() if picture != null else null
	if art == null or art.is_empty(): return null
	var size := 256
	var ring := Ink.INK if Surfaces.ink() else Color("d9dadc") # the facility look: a printed sticker with a light edge, no ink
	var paper := Ink.PAPER if Surfaces.ink() else Color("f7f7f5")
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			image.set_pixel(x, y, Color(0, 0, 0, 0) if distance > 126.0 else (ring if distance > 114.0 else paper))
	var face := art.duplicate() as Image
	if face.is_compressed(): face.decompress()
	face.convert(Image.FORMAT_RGBA8)
	var fit := minf(160.0 / face.get_width(), 160.0 / face.get_height())
	face.resize(maxi(1, roundi(face.get_width() * fit)), maxi(1, roundi(face.get_height() * fit)), Image.INTERPOLATE_LANCZOS)
	image.blend_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), Vector2i((size - face.get_width()) / 2, (size - face.get_height()) / 2))
	image.generate_mipmaps()
	var material := ShaderMaterial.new()
	material.shader = PRINT_SHADER
	material.set_shader_parameter("print_texture", ImageTexture.create_from_image(image))
	material.set_shader_parameter("lift", BalloonSim.RADIUS * 1.15) # in front of every shape from every side (the egg is 1.12 tall)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * BalloonSim.RADIUS * float(PRINT_SIZE.get(shape, 1.0))
	var node := MeshInstance3D.new()
	node.name = "BalloonPrint"
	node.mesh = quad
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = BalloonSim.RADIUS * 2.0
	return node

func _follow_string(anchor: Vector3, velocity: Vector3, delta: float) -> void:
	var gap := STRING_LENGTH / STRING_SEGMENTS
	_string_points[0] = anchor
	for i in range(1, _string_points.size()):
		# Each point hangs below the one above it and lags behind the balloon's motion.
		var wanted := _string_points[i - 1] + (Vector3.DOWN - velocity * 0.08).normalized() * gap
		_string_points[i] = _string_points[i].lerp(wanted, clampf(delta * 14.0, 0.0, 1.0))
		_string_points[i] = _string_points[i - 1] + (_string_points[i] - _string_points[i - 1]).normalized() * gap
	for i in _string.size():
		var a := _string_points[i]
		var b := _string_points[i + 1]
		var dir := b - a
		if dir.length_squared() < 1e-8: continue
		var up := dir.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		_string[i].transform = Transform3D(Basis(side, up, side.cross(up)).scaled(Vector3(1.0, dir.length(), 1.0)), (a + b) * 0.5)

func _reset_string(at: Vector3) -> void:
	for i in _string_points.size(): _string_points[i] = at + Vector3.DOWN * (BalloonSim.RADIUS + STRING_LENGTH * i / STRING_SEGMENTS)

func _start_pop(at: Vector3) -> void:
	_pop_age = 0.0
	for i in _flecks.size():
		var angle := TAU * i / _flecks.size()
		_flecks[i].position = at
		_flecks[i].visible = true
		_fleck_velocity[i] = Vector3(cos(angle), 0.6 + 0.5 * sin(angle * 3.0), sin(angle)) * 4.5

func _step_pop(delta: float) -> void:
	if _pop_age < 0.0: return
	_pop_age += delta
	for i in _flecks.size():
		_fleck_velocity[i].y -= 12.0 * delta
		_flecks[i].position += _fleck_velocity[i] * delta
		_flecks[i].rotate_object_local(Vector3(1, 0.3, 0).normalized(), delta * 9.0)
	if _pop_age > 0.7:
		_pop_age = -1.0
		for fleck in _flecks: fleck.visible = false

## Glossy latex in the facility look (a soft sheen, a little light of its own so the colour reads in shade); comic ink rubber in the
## comic look when its shaders are in the project, a plain toon-ish material otherwise.
static func _material(tint: Color) -> Material:
	if not Surfaces.ink():
		var latex := StandardMaterial3D.new()
		latex.albedo_color = tint
		latex.roughness = 0.22
		latex.metallic_specular = 0.6
		latex.rim_enabled = true
		latex.rim = 0.35
		latex.rim_tint = 0.6
		latex.emission_enabled = true
		latex.emission = tint
		latex.emission_energy_multiplier = 0.12
		return latex
	if ResourceLoader.exists(Ink.SURFACE):
		var material: ShaderMaterial = Style.shader_material(Ink.SURFACE, {"mode": 3, "base_color": tint, "alt_color": tint.darkened(0.2), "ink_color": Ink.INK})
		return Style.outlined(material, Ink.INK, 0.03, false)
	var plain := StandardMaterial3D.new()
	plain.albedo_color = tint
	plain.roughness = 0.4
	return plain

## The string in the facility look: a thin grey cord.
static func _cord() -> Material:
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color("5a5e66")
	cord.roughness = 0.8
	return cord
