extends RefCounted
## Round heads of the cast's characters for the menu pages (the results rows): each seat's rig, dressed in its default look, is rendered once from the chest up into a small picture through
## a tiny SubViewport of its own, copied into an ImageTexture and kept for the session; the viewport and the rig are gone again afterwards. One seat at a time, so a page of ten players never
## stalls a frame. Nothing is built where there is no renderer (a headless run) or no rig; the page then draws the player's initial in a ring of the player's colour.
##   MenuPortraits.request(host, [seat, ...])   starts baking what is not there yet (host: any Node in the tree, it owns the baker)
##   MenuPortraits.texture(seat)                the picture, or null while it is not there (or when it cannot be made)
const Rig := preload("res://character/character_rig.gd")
const Look := preload("res://character/look.gd")
const CandyLight := preload("res://style/candy_light.gd")

const SIZE := 192 ## px, the picture's side
const EYE_Y := 1.6 ## m, where the camera looks (the head's middle on a 1.8 m character)
const DISTANCE := 1.35 ## m from the character
const FOV := 26.0
const WARM_FRAMES := 3 ## frames the viewport renders before its picture is taken

static var _pictures := {} ## seat -> ImageTexture (or null when it failed)
static var _queued := {} ## seat -> true while it is waiting or being drawn

static func texture(seat: int) -> Texture2D:
	return _pictures.get(seat)

## True when there is a renderer and a rig to draw the heads with.
static func possible() -> bool:
	return DisplayServer.get_name() != "headless" and Rig.available()

static func request(host: Node, seats: Array) -> void:
	if host == null or not host.is_inside_tree() or not possible(): return
	var baker: Baker = host.get_node_or_null("PortraitBaker") as Baker
	for seat: Variant in seats:
		var number := int(seat)
		if _pictures.has(number) or _queued.has(number): continue
		if baker == null:
			baker = Baker.new()
			baker.name = "PortraitBaker"
			# Lambdas made here may reach the statics (an inner class may not).
			baker.done = func(seat: int, picture: Texture2D) -> void:
				_pictures[seat] = picture
				_queued.erase(seat)
			baker.dropped = func(seat: int) -> void: _queued.erase(seat)
			host.add_child(baker)
		_queued[number] = true
		baker.line.append(number)

class Baker extends Node:
	var line: Array[int] = []
	var done: Callable ## (seat, picture or null) when a head is baked (null: it could not be)
	var dropped: Callable ## (seat) when the baker leaves the tree with the head still waiting
	var _viewport: SubViewport
	var _seat := -1
	var _frames := 0

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _exit_tree() -> void:
		if not dropped.is_valid(): return
		if _seat >= 0: dropped.call(_seat)
		for seat in line: dropped.call(seat)

	func _process(_delta: float) -> void:
		if _viewport == null:
			if line.is_empty(): return
			_seat = line.pop_front()
			_begin(_seat)
			return
		_frames += 1
		if _frames < WARM_FRAMES: return
		var image := _viewport.get_texture().get_image()
		done.call(_seat, ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null)
		_viewport.queue_free()
		_viewport = null
		_seat = -1

	func _begin(seat: int) -> void:
		_frames = 0
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(SIZE, SIZE)
		_viewport.own_world_3d = true
		_viewport.transparent_bg = true
		_viewport.msaa_3d = Viewport.MSAA_4X
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.handle_input_locally = false
		add_child(_viewport)
		var world := Node3D.new()
		_viewport.add_child(world)
		var environment := Environment.new()
		environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.86, 0.88, 0.95)
		environment.ambient_light_energy = 0.9
		var holder := WorldEnvironment.new()
		holder.environment = environment
		world.add_child(holder)
		var sun := DirectionalLight3D.new()
		world.add_child(sun)
		CandyLight.apply_sun(sun)
		sun.global_basis = Basis.looking_at(Vector3(-0.35, -0.55, -0.75), Vector3.UP)
		var camera := Camera3D.new()
		camera.fov = FOV
		camera.current = true
		world.add_child(camera)
		camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, EYE_Y + 0.04, DISTANCE)).looking_at(Vector3(0.0, EYE_Y, 0.0), Vector3.UP)
		var rig: Node3D = Rig.new()
		rig.name = "Seat%d" % seat
		world.add_child(rig)
		rig.setup(seat, {"look": Look.defaults_for_seat(seat)})
		var still := {"yaw": PI, "grounded": true, "velocity": Vector3.ZERO}
		rig.snap(still)
		rig.update(0.016, still)
