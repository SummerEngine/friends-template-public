extends Node
## Small pictures of the wardrobe's items, each rendered once per session in an own-world SubViewport (one item per frame)
## and kept in a static cache: the item's model alone, seen from the front and a little from the side, in soft light on a
## transparent background. A texture item ("mode": "texture") shows its texture, the team print the team logo. Files come
## through Catalog.resolve() (our art, else local stand-ins). An item without a file yet or a run without a renderer
## (headless checks) gets no picture: its tile keeps the item's name. Surfaces named after a colour slot (the rig's rule:
## "shirt", "pants", "shoes", "skin"; "ears" is skin) show the player's colours, so a white hoodie shows their shirt colour;
## a picture is kept per item and colours (key()).
signal thumb_ready(key: String, texture: Texture2D)

const Catalog = preload("res://character/catalog.gd")
const TeamCast = preload("res://style/team_cast.gd")
const SIZE := 192
const VIEW_FOV := 30.0
const VIEW_FROM := Vector3(0.45, 0.3, 1.0) ## the camera's side of the model (models face +Z)

const SURFACE_SLOTS := {"ears": "skin"}

static var _cache := {} ## key() -> Texture2D, or null when the item has no picture
var _queue: Array[Array] = [] ## [key, item, colours]
var _busy := false
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D

## The picture's name: the item and the colours it is shown in (`colors`: colour slot -> Color).
static func key(item: Dictionary, colors: Dictionary) -> String:
	var parts := [str(item.get("id", ""))]
	var slots := colors.keys()
	slots.sort()
	for slot: String in slots: parts.append("%s=%s" % [slot, (colors[slot] as Color).to_html(false)])
	return "|".join(parts)

## The item's picture in `colors` when it exists; else it is queued (thumb_ready follows) and null comes back.
func request(item: Dictionary, colors := {}) -> Texture2D:
	var name := key(item, colors)
	if str(item.get("id", "")) == "" or _cache.has(name): return _cache.get(name)
	for queued: Array in _queue:
		if queued[0] == name: return null
	_queue.append([name, item, colors])
	return null

## Every surface of `model` named after a colour slot takes that slot's colour from `colors`; returns how many did.
static func tint(model: Node, colors: Dictionary) -> int:
	var count := 0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D: meshes.append(model)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface)
			if not material is BaseMaterial3D: continue
			var slot := material.resource_name.get_slice(".", 0)
			slot = SURFACE_SLOTS.get(slot, slot)
			if not colors.has(slot): continue
			var tinted := material.duplicate() as BaseMaterial3D
			tinted.albedo_color = colors[slot]
			mesh.set_surface_override_material(surface, tinted)
			count += 1
	return count

static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"

func _process(_delta: float) -> void:
	if _busy or _queue.is_empty(): return
	var next: Array = _queue.pop_front()
	_render(next[0], next[1], next[2])

func _render(name: String, item: Dictionary, colors: Dictionary) -> void:
	var file := Catalog.resolve(str(item.get("file", "")))
	var model: Variant = load(file) if file != "" else null
	if model == null and str(item.get("print", "")) == "team": model = TeamCast.logo()
	if model is Texture2D:
		_finish(name, eyeball(model) if str(item.get("slot", "")) == "eyes" else model)
		return
	if not model is PackedScene or not can_render():
		_cache[name] = null
		return
	_busy = true
	_ensure_stage()
	var instance: Node = (model as PackedScene).instantiate()
	for player: Node in instance.find_children("*", "AnimationPlayer", true, false): # skinned items carry the body's clips
		player.get_parent().remove_child(player)
		player.free()
	tint(instance, colors)
	_stage.add_child(instance)
	var box := _bounds(instance)
	if box.size == Vector3.ZERO:
		instance.queue_free()
		_cache[name] = null
		_busy = false
		return
	var radius := maxf(box.size.length() * 0.5, 0.05)
	var middle := box.get_center()
	_camera.global_position = middle + VIEW_FROM.normalized() * radius / sin(deg_to_rad(VIEW_FOV) * 0.5) * 1.05
	_camera.look_at(middle, Vector3.UP)
	_camera.near = maxf(radius * 0.05, 0.01)
	_camera.far = radius * 8.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree(): return
	var image := _viewport.get_texture().get_image()
	instance.queue_free()
	_busy = false
	if image == null or image.is_empty():
		_cache[name] = null
		return
	_finish(name, ImageTexture.create_from_image(image))

func _finish(id: String, texture: Texture2D) -> void:
	_cache[id] = texture
	thumb_ready.emit(id, texture)

const EYE_DISC := 0.8 ## the eyeball's diameter in a tile picture, as a share of SIZE
const EYE_ZOOM := 0.92 ## the eye picture's side across that diameter (its white corners fall outside the disc)

## An eye picture (a square texture mapped on the eyeball, white all round) as the eyeball itself: a round disc, centred, padded, with a transparent
## surround, so a tile shows an eye and not a white square. A texture that cannot be read keeps its square.
static func eyeball(texture: Texture2D) -> Texture2D:
	var source := texture.get_image()
	if source == null or source.is_empty(): return texture
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var side := int(round(float(SIZE) * EYE_DISC * EYE_ZOOM))
	source.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var middle := Vector2(SIZE, SIZE) * 0.5
	var radius := float(SIZE) * EYE_DISC * 0.5
	var origin := Vector2i((SIZE - side) / 2, (SIZE - side) / 2)
	for y in SIZE:
		for x in SIZE:
			var edge := radius - (Vector2(x + 0.5, y + 0.5) - middle).length() # px inside the rim
			if edge <= -0.5: continue
			var local := Vector2i(x, y) - origin
			var color := Color.WHITE
			if local.x >= 0 and local.y >= 0 and local.x < side and local.y < side: color = source.get_pixelv(local)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(edge + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)

func _ensure_stage() -> void:
	if _viewport != null: return
	_viewport = SubViewport.new()
	_viewport.name = "ThumbStage"
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff4e6")
	environment.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff1dc")
	key.light_energy = 1.1
	_viewport.add_child(key)
	key.global_basis = Basis.looking_at(Vector3(-0.4, -0.6, -1.0).normalized(), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("dfe9ff")
	fill.light_energy = 0.4
	_viewport.add_child(fill)
	fill.global_basis = Basis.looking_at(Vector3(0.7, -0.2, 0.4).normalized(), Vector3.UP)
	_camera = Camera3D.new()
	_camera.fov = VIEW_FOV
	_viewport.add_child(_camera)
	_camera.current = true

static func _bounds(root: Node) -> AABB:
	var box := AABB()
	var found := false
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var part := mesh.global_transform * mesh.get_aabb()
		box = part if not found else box.merge(part)
		found = true
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		var own := (root as MeshInstance3D).global_transform * (root as MeshInstance3D).get_aabb()
		box = own if not found else box.merge(own)
	return box
