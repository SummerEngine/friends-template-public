extends Node
## Two left/right views over one simulation (local co-op on one screen). No input or physics here: the shell moves
## the two cameras. Each view is a SubViewport sharing the world; the host viewport stops drawing 3D while they are active.
const VIEW_OWN_BITS := (1 << 18) | (1 << 19) | (1 << 20) | (1 << 21) ## render layers of the first-person bodies and view arms
var cameras: Array[Camera3D] = []
var active := false
var host: Viewport
var world: World3D
var views: Array[SubViewport] = []
var displays: Array[TextureRect] = []
var canvas: CanvasLayer
var _saved_disable_3d := false

func configure(game_world: Node3D) -> void:
	host = game_world.get_viewport()
	world = game_world.get_world_3d()
	for seat in 2:
		var camera := Camera3D.new()
		camera.name = "SplitCamera%d" % seat
		add_child(camera)
		camera.current = false # the shell's own camera stays the ownership token while the views are off
		cameras.append(camera)
	host.size_changed.connect(_resize)

func set_active(enabled: bool) -> void:
	if active == enabled: return
	if not enabled:
		_clear()
		active = false
		return
	_saved_disable_3d = host.disable_3d
	host.disable_3d = true
	canvas = CanvasLayer.new()
	canvas.layer = -10 # the HUD and menu canvases stay global above both views
	add_child(canvas)
	for seat in 2:
		var view := SubViewport.new()
		view.name = "SplitViewport%d" % seat
		view.world_3d = world
		view.gui_disable_input = true
		view.audio_listener_enable_3d = false
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(view)
		cameras[seat].reparent(view)
		cameras[seat].make_current()
		views.append(view)
		var display := TextureRect.new()
		display.texture = view.get_texture()
		display.mouse_filter = Control.MOUSE_FILTER_IGNORE
		display.stretch_mode = TextureRect.STRETCH_SCALE
		canvas.add_child(display)
		displays.append(display)
	active = true
	_resize()

## The views copy what the host camera draws with (environment, attributes, culling) and the host's anti-aliasing. Each view keeps
## its own first-person layers (its courier's body hidden, its view arms drawn: game/follow_camera.gd, character/character_rig.gd).
func sync_camera_properties(source: Camera3D) -> void:
	for camera: Camera3D in cameras:
		camera.far = source.far
		camera.cull_mask = (source.cull_mask & ~VIEW_OWN_BITS) | (camera.cull_mask & VIEW_OWN_BITS)
		camera.environment = source.environment
		camera.attributes = source.attributes
	for view: SubViewport in views:
		view.msaa_3d = host.msaa_3d
		view.screen_space_aa = host.screen_space_aa
		view.use_taa = host.use_taa
		view.scaling_3d_mode = host.scaling_3d_mode
		view.scaling_3d_scale = host.scaling_3d_scale

func _resize() -> void:
	if views.size() != 2: return
	var size := Vector2i(host.get_visible_rect().size)
	var half_width := maxi(1, int(size.x * 0.5))
	for seat in 2:
		views[seat].size = Vector2i(half_width, maxi(1, size.y))
		displays[seat].position = Vector2(half_width * seat, 0)
		displays[seat].size = Vector2(half_width, maxi(1, size.y))

func _clear() -> void:
	if views.is_empty(): return
	for camera: Camera3D in cameras:
		camera.current = false
		camera.reparent(self)
		camera.current = false
	for view: SubViewport in views:
		remove_child(view)
		view.queue_free()
	views.clear()
	displays.clear()
	if is_instance_valid(canvas):
		remove_child(canvas)
		canvas.queue_free()
	canvas = null
	if is_instance_valid(host): host.disable_3d = _saved_disable_3d

func _exit_tree() -> void:
	# Do not reparent children while the tree is being torn down.
	if not views.is_empty() and is_instance_valid(host): host.disable_3d = _saved_disable_3d
	if is_instance_valid(host) and host.size_changed.is_connected(_resize): host.size_changed.disconnect(_resize)
