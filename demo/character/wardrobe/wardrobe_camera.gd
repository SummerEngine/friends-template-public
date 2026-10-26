extends Camera3D
## The customizer's preview camera: the player's own character alone on a painted sky. It sees only the character's own render
## layers (follow_camera.gd own_body() puts an owned character on them) against the menu kit's painted sky, on a round pedestal (cream plate, gold ring, mint drum) under
## the feet, lit like a product shot by its own lights that turn with the camera: a warm key from the front-left above, a
## soft fill from the front-right, a rim from behind, and a bright ambient. They light only the character's layers and cast
## no shadows. (The yard's sun reaches the booth, but from one fixed side of the world: a face turned away from it would be dark.) Drags (mouse, touch, right stick) and the turn buttons orbit it, the wheel, a pinch, the triggers and the zoom
## buttons zoom within limits, the pitch stays between -45 and 30 degrees (negative: from above). `frame` is the character's
## spot in normalized screen coordinates (x right, y up, -1..1), `free_height` the share of the screen height the preview has:
## the distance fits the whole character into it.
const PITCH_MIN := -45.0
const PITCH_MAX := 30.0
const PITCH_START := -10.0
const FOV := 40.0
const ZOOM_MIN := 0.35 ## share of the fitting distance: close-up on the face ...
const ZOOM_MAX := 1.4 ## ... to a step back
const FIT_MARGIN := 1.35 ## the character's height times this fills the free height (head room above, the pedestal under the feet)
const DISTANCE_MIN := 0.6
const DISTANCE_MAX := 16.0 ## m: an upright phone has a short preview, the character is fitted far back
const FALLBACK_HEIGHT := 1.8 ## m, when the character's size cannot be measured
const SETTLE := 10.0 ## 1/s: zoom and layout changes glide
const Kit := preload("res://style/menu_kit.gd")
const STAGE := Color("3a7fd4") ## the sky blue behind the painted sky (shows only where the sky page does not reach)
const SKY_DISTANCE := 40.0 ## m behind the character: the painted sky is a big quad this far in front of the camera, turning with it
const VEIL := Color("0b1b3d") ## the colour the screen fades through when the customizer opens and closes
## The round pedestal the character stands on, top down: [name, top radius, bottom radius, height, centre y under the top, colour]. A cream plate on a gold ring on a mint drum.
const PEDESTAL := [
	["Plate", 0.55, 0.57, 0.05, -0.025, Color("f6f0e0")],
	["Ring", 0.63, 0.63, 0.045, -0.0725, Color("f2b632")],
	["Drum", 0.56, 0.64, 0.2, -0.195, Color("49cfa0")],
]
## Preview lights in camera space: [name, where the light comes from (x right, y up, z towards the viewer), colour, energy].
const LIGHTS := [
	["Key", Vector3(-1.0, 1.1, 1.3), Color("fff0dc"), 0.95],
	["Fill", Vector3(1.2, 0.2, 1.0), Color("e6eeff"), 0.45],
	["Rim", Vector3(0.3, 0.9, -1.2), Color("fff6ea"), 0.75],
]

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(PITCH_START)
var zoom_scale := 1.0
var frame := Vector2.ZERO
var free_height := 1.0
var character_height := FALLBACK_HEIGHT
var _shown_zoom := 1.0
var _shown_frame := Vector2.ZERO
var _shown_free := 1.0
var _pedestal: Node3D
var _sky: MeshInstance3D

## `home` showed the player until now (its far plane and attributes carry over); `facing` is the character's yaw (it looks
## along -Z at 0): the camera starts in front.
func begin(home: Camera3D, character: Node3D, facing: float) -> void:
	target = character
	attributes = home.attributes
	far = maxf(home.far, SKY_DISTANCE * 2.0)
	near = 0.05
	fov = FOV
	keep_aspect = Camera3D.KEEP_HEIGHT
	var stage := Environment.new()
	stage.background_mode = Environment.BG_COLOR
	stage.background_color = STAGE
	stage.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	stage.ambient_light_color = Color("fff6ee")
	stage.ambient_light_energy = 0.5
	stage.tonemap_mode = Environment.TONE_MAPPER_REINHARDT # light shirts keep their colour where the lights add up
	stage.tonemap_white = 1.5
	environment = stage
	var layers := _character_layers()
	# The character alone when it has its own layers; else everything (the dark background is still behind it).
	var own := (layers & ~1) != 0
	if own: layers &= ~1
	cull_mask = layers if own else home.cull_mask
	yaw = wrapf(facing + PI, -PI, PI)
	character_height = _measure()
	_shown_zoom = zoom_scale
	_shown_frame = frame
	_shown_free = free_height
	_pedestal = _build_pedestal(layers if own else 1)
	add_child(_pedestal)
	_sky = _build_sky(layers if own else 1)
	add_child(_sky)
	for spec: Array in LIGHTS:
		var light := DirectionalLight3D.new()
		light.name = "Preview" + str(spec[0])
		light.light_color = spec[2]
		light.light_energy = spec[3]
		light.shadow_enabled = false
		light.light_cull_mask = layers if own else 0xFFFFF
		light.transform.basis = Basis.looking_at(-(spec[1] as Vector3).normalized(), Vector3.UP)
		add_child(light)
	_place()
	make_current()

## The round pedestal: stacked cylinders (PEDESTAL), on the character's render layers, its top face at the origin.
func _build_pedestal(layers: int) -> Node3D:
	var root := Node3D.new()
	root.name = "StagePedestal"
	root.top_level = true
	for part: Array in PEDESTAL:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = float(part[1])
		cylinder.bottom_radius = float(part[2])
		cylinder.height = float(part[3])
		cylinder.radial_segments = 64
		cylinder.rings = 1
		var material := StandardMaterial3D.new()
		material.albedo_color = part[5]
		material.roughness = 0.55
		material.emission_enabled = true # the Reinhard tone mapping of the stage dulls what the lights alone give: the colours glow a little
		material.emission = part[5]
		material.emission_energy_multiplier = 0.6
		var piece := MeshInstance3D.new()
		piece.name = str(part[0])
		piece.mesh = cylinder
		piece.material_override = material
		piece.layers = layers
		piece.position = Vector3(0.0, float(part[4]), 0.0)
		root.add_child(piece)
	return root

## The painted sky (the menu kit's: gradient, haze, sunburst, clouds) drawn into a viewport and shown on a quad that fills the picture behind the character.
func _build_sky(layers: int) -> MeshInstance3D:
	var view := SubViewport.new()
	view.name = "SkyView"
	view.size = Vector2i(1024, 1024)
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var page := SkyPage.new()
	page.size = Vector2(view.size)
	view.add_child(page)
	var material := StandardMaterial3D.new()
	# Lit by nothing: the sky is only emission (the tone mapping of the stage would dim an unshaded picture, so it is lifted a little).
	material.albedo_color = Color.BLACK
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.emission_enabled = true
	material.emission_texture = view.get_texture()
	material.emission_energy_multiplier = 1.25
	material.disable_fog = true
	var quad := MeshInstance3D.new()
	quad.name = "StageSky"
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	quad.layers = layers
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0.0, 0.0, -SKY_DISTANCE)
	return quad

## The sky page: the kit's painted sky, its sunburst in the middle (behind the character).
class SkyPage extends Control:
	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		Kit.draw_backdrop(self, Rect2(Vector2.ZERO, size), float(Time.get_ticks_msec()) * 0.001, "sun", Vector2(0.5, 0.5))

func set_frame(spot: Vector2, free_share: float) -> void:
	frame = spot
	free_height = clampf(free_share, 0.2, 1.0)

func turn(change: Vector2) -> void:
	yaw = wrapf(yaw + change.x, -PI, PI)
	pitch = clampf(pitch + change.y, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))

func zoom(factor: float) -> void:
	zoom_scale = clampf(zoom_scale * factor, ZOOM_MIN, ZOOM_MAX)

## The render layers of the character's meshes.
func _character_layers() -> int:
	var layers := 0
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false): layers |= mesh.layers
	return layers

## Height of the character's drawn meshes above its feet.
func _measure() -> float:
	var top := -INF
	for mesh: MeshInstance3D in target.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var box := mesh.global_transform * mesh.get_aabb()
		top = maxf(top, box.end.y)
	var height := top - target.global_position.y
	return height if is_finite(height) and height > 0.3 and height < 4.0 else FALLBACK_HEIGHT

func _process(delta: float) -> void:
	var settle := 1.0 - exp(-delta * SETTLE)
	_shown_zoom = lerpf(_shown_zoom, zoom_scale, settle)
	_shown_frame = _shown_frame.lerp(frame, settle)
	_shown_free = lerpf(_shown_free, free_height, settle)
	if is_instance_valid(target): _place()

func _place() -> void:
	var focus := target.global_position + Vector3.UP * character_height * 0.5
	var direction := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var half := tan(deg_to_rad(FOV) * 0.5)
	var reach := clampf(character_height * FIT_MARGIN / (2.0 * half * _shown_free) * _shown_zoom, DISTANCE_MIN, DISTANCE_MAX)
	global_transform = Transform3D(Basis.looking_at(-direction, Vector3.UP), focus + direction * reach)
	# Shift the picture so the focus lands on `frame`: half the visible height (and width) at the focus distance.
	var view := get_viewport().get_visible_rect().size
	var half_height := reach * half
	h_offset = -_shown_frame.x * half_height * (view.x / maxf(view.y, 1.0))
	v_offset = -_shown_frame.y * half_height
	if _pedestal != null: _pedestal.global_position = target.global_position + Vector3.UP * 0.02
	if _sky != null:
		var reach_sky := tan(deg_to_rad(fov) * 0.5) * SKY_DISTANCE * 2.0 * maxf(view.x / maxf(view.y, 1.0), 1.0) * 1.35 # fills the picture, whatever the frame offset
		_sky.scale = Vector3(reach_sky, reach_sky, 1.0)

func probe() -> Dictionary:
	return {"yaw": yaw, "pitch": pitch, "zoom": zoom_scale, "height": character_height, "frame": frame, "cull_mask": cull_mask}
