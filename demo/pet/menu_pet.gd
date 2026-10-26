extends Control
## The menu pet: a small dog standing on a platform of the title drawing, right of the menu, that reacts to the menu.
##  - Happy while PLAY, INVITE or SETTINGS is hovered (pointer) or focused (keys, pad); sad on QUIT; idle otherwise.
##  - Petted while a pointer or finger presses and rubs it: hand cursor, hearts float up.
##  - A short happy jump when PLAY is pressed. It turns toward the pointer (or the focused button), looks around when
##    nothing moves; the collar tag swings, the ears twitch (pet_motion.gd). It wears the team cap (pet_cap.gd).
## It is drawn in the game's look (pet_look.gd: the characters' soft toy material, or the look's own character material)
## with a soft contact shadow, in its own SubViewport and World3D (camera, a warm key and a cool fill light like the
## facility's, transparent background), so the title's live world is never touched.
## It stands on GROUND, a point of the title art (client/menu_backdrop.gd art_point), and follows the art's sway. It is a
## child of the title, so it hides with it.
##
##   add_child(MenuPet.new(menu))   # menu: client/main_menu.gd (buttons are read through menu.action_button(key))
##
## The model is demo/pet/models/pet.glb (our art). Until that exists a local stand-in in demo/pet/_ref/ (gitignored) is
## used; with neither, the pet stays hidden.
const PetRig := preload("res://pet/pet_rig.gd")
const PetHearts := preload("res://pet/pet_hearts.gd")
const TeamCast := preload("res://style/team_cast.gd")
const SHADOW := preload("res://pet/pet_shadow.gdshader")
const GameAudio := preload("res://game/game_audio.gd") ## the pet's sounds: mix.json events pet_<cue>, a random take each

const MODELS := ["res" + "://pet/models/pet.glb", "res" + "://pet/_ref/dog.glb"]
## Sound hooks (GameAudio.pet_stream: happy, sad, pet, idle, poke, curious; provenance: demo/audio/sfx/provenance.md), one-shots
## by state and on idle, hover and a tap. A missing one is silence; headless runs are always silent.
## Seconds before the same sound may play again.
const SOUND_GAP := {"happy": 1.0, "sad": 1.5, "pet": 1.6, "idle": 5.0, "poke": 0.4, "curious": 4.0}
## Mean seconds between two idle sounds (a sniff, a small yawn) while nobody moves.
const IDLE_SOUND_EVERY := 6.0
const SOUND_DB := -6.0
const HAPPY_KEYS := ["Play", "Invite", "Settings"]
const SAD_KEYS := ["Quit"]
## Where the pet stands: the middle of its feet on GROUND, a point of the title art (0..1 across the picture: the front of
## the platform at the lower right, before the spikes, clear of the drawn couriers). A cast with its own title art says
## where on it in title.pet_ground ([x, y], the same shares; docs/slots.md). Its height (feet to cap) as a share of
## the title, landscape and portrait; it stays right of FREE_FROM (the menu column covers x 6%..46%) and EDGE (share of the
## height) inside the screen, smaller when it would not fit.
const GROUND := Vector2(0.885, 0.848)
const HEIGHT_WIDE := 0.5
const HEIGHT_TALL := 0.27
const FREE_FROM := 0.5
const EDGE := 0.015
## Camera: field of view (degrees), how far it looks down (radians, about the drawing's own view), room around the pet in
## its view (width, height: head turns and the tag swing stay inside), and the pet's turn toward the menu (+ faces right).
const FOV := 28.0
const ELEVATION := 0.12
const ROOM := Vector2(1.3, 1.12)
const TURN := -0.32
## Share of the gaze (pet_motion.gd yaw) the whole pet turns by.
const LOOK_TURN := 0.6
## Petting: rub energy (title heights of pointer travel) decays at RUB_DECAY per second; the pet state starts above
## RUB_START and lasts while above RUB_STOP. A tap alone adds RUB_TAP.
const RUB_DECAY := 2.5
const RUB_START := 0.04
const RUB_STOP := 0.015
const RUB_TAP := 0.05
const HEART_GAP := 0.22
## The device of the engine's synthetic cursor-refresh motion (InputEvent DEVICE_ID_INTERNAL, not bound to scripts).
const ENGINE_MOTION := -2
## Happy reaction to PLAY (seconds); look-around after the pointer rests this long (seconds).
const CHEER_TIME := 1.1
const LOOK_AROUND_AFTER := 3.5

signal state_changed(state: String)

var menu: Control
var state := "idle"
var rig: PetRig
var hearts: PetHearts

var _view: SubViewportContainer
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _shadow: MeshInstance3D
var _model_path := ""
var _box := Rect2()
var _scale := 1.0
var _hit := Rect2()
## The pet's size in title px (feet to cap; width), its feet in the box (px), and its hit area relative to the box.
var _size := Vector2.ZERO
var _feet := Vector2.ZERO
var _hit_in_box := Rect2()
## The pet's width / height from its bounds, once its cap sits (until then: a guess).
var _aspect := 0.7
var _ground := Vector2.INF
var _ground_share := GROUND
var _fit_frames := -1
var _pointer := Vector2.ZERO
var _pointer_mode := true
var _pointer_known := false
var _still := 0.0
var _wander := Vector2.ZERO
var _wander_time := 0.0
var _rubbing := false
var _rub := 0.0
var _heart_time := 0.0
var _cheer := 0.0
var _play_button: Button
var _voice: AudioStreamPlayer
var _sound_at := {}
var _random := RandomNumberGenerator.new()

func _init(title: Control = null) -> void:
	menu = title
	name = "MenuPet"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_random.randomize()
	_view = SubViewportContainer.new()
	_view.name = "View"
	_view.stretch = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_viewport = SubViewport.new()
	_viewport.name = "PetViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.gui_disable_input = true
	_view.add_child(_viewport)
	_stage = Node3D.new()
	_stage.name = "Stage"
	_viewport.add_child(_stage)
	_build_stage()
	hearts = PetHearts.new()
	add_child(hearts)
	_voice = AudioStreamPlayer.new()
	_voice.name = "PetVoice"
	_voice.volume_db = SOUND_DB
	_voice.bus = GameAudio.SFX_BUS
	add_child(_voice)
	mouse_entered.connect(_on_hover)

func _ready() -> void:
	resized.connect(_layout)
	visibility_changed.connect(_on_visibility)
	for path: String in MODELS:
		if ResourceLoader.exists(path):
			_model_path = path
			break
	if _model_path == "":
		# No art yet (a clean checkout): no pet, quietly.
		_retire()
		return
	ResourceLoader.load_threaded_request(_model_path, "PackedScene")
	_layout()

## True once the model is in and the camera is fitted.
func is_loaded() -> bool:
	return rig != null and _fit_frames < 0

## False when there is no pet model (then the pet is hidden and does nothing).
func has_model() -> bool:
	return _model_path != ""

func _retire() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	set_process_input(false)

## Screen rect (local px) where the pet can be petted.
func hit_rect() -> Rect2:
	return _hit

## Where the pet stands (local px): its feet in the middle of the bottom edge, as tall as it is drawn (feet to cap).
func stand_rect() -> Rect2:
	return Rect2(_ground - Vector2(_size.x * 0.5, _size.y), _size)

func _has_point(point: Vector2) -> bool:
	return rig != null and _hit.has_point(point)

func _build_stage() -> void:
	# The facility's light: a soft sky ambient, a warm key from the upper left and in front, a cool fill from the right.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("eaeef2")
	environment.ambient_light_energy = 0.5
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_color = Color("fff4e6")
	key.light_energy = 1.0
	key.rotation = Vector3(-0.75, -0.55, 0.0)
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("dbe5f0")
	fill.light_energy = 0.4
	fill.rotation = Vector3(-0.25, 0.7, 0.0)
	_stage.add_child(fill)
	# A soft contact shadow under the feet, sized to the model when it is in.
	var floor_material := ShaderMaterial.new()
	floor_material.shader = SHADOW
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	_shadow.mesh = QuadMesh.new()
	_shadow.material_override = floor_material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.rotation.x = -PI * 0.5
	_shadow.visible = false
	_stage.add_child(_shadow)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = FOV
	_camera.current = true
	_stage.add_child(_camera)

func _process(delta: float) -> void:
	if rig == null:
		_poll_load()
		return
	if not is_visible_in_tree(): return
	delta = minf(delta, 0.1)
	if _fit_frames > 0:
		_fit_frames -= 1
		if _fit_frames == 0:
			_fit_frames = -1
			_layout()
	_follow_ground()
	_bind_buttons()
	_rub *= exp(-RUB_DECAY * delta)
	_cheer = maxf(_cheer - delta, 0.0)
	_still += delta
	_set_state(_wanted_state())
	if state == "idle" and _still > LOOK_AROUND_AFTER and _random.randf() < delta / IDLE_SOUND_EVERY: _sound("idle")
	_aim(delta)
	# The gaze turns the whole pet (pet_motion.gd), so the cap stays on its head.
	rig.motion.body_turn = rig.motion.yaw * LOOK_TURN
	rig.rotation.y = TURN + rig.motion.body_turn
	if state == "pet":
		_heart_time -= delta
		if _heart_time <= 0.0:
			_heart_time = HEART_GAP
			hearts.emit(_head_point())
		_sound("pet")
	mouse_default_cursor_shape = Control.CURSOR_DRAG if _rubbing else Control.CURSOR_POINTING_HAND

func _poll_load() -> void:
	if _model_path == "": return
	var status := ResourceLoader.load_threaded_get_status(_model_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	var scene: PackedScene = null
	if status == ResourceLoader.THREAD_LOAD_LOADED: scene = ResourceLoader.load_threaded_get(_model_path) as PackedScene
	var body := PetRig.new()
	body.rotation.y = TURN
	_stage.add_child(body)
	if scene == null or not body.setup(scene):
		push_warning("Menu pet: cannot use " + _model_path)
		body.queue_free()
		_model_path = ""
		_retire()
		return
	rig = body
	# The cap follows its bone from the first skeleton update; fit once it sits there.
	_fit_frames = 2

# ------------------------------------------------------------------ state

func _wanted_state() -> String:
	if _rub > RUB_START or (state == "pet" and _rub > RUB_STOP): return "pet"
	if _cheer > 0.0: return "happy"
	var key := _menu_key()
	if key in HAPPY_KEYS: return "happy"
	if key in SAD_KEYS: return "sad"
	return "idle"

## The menu button the player is on: hovered with a pointer, focused with keys or a pad.
func _menu_key() -> String:
	for key: String in HAPPY_KEYS + SAD_KEYS:
		var button := _button(key)
		if button == null or button.disabled or not button.is_visible_in_tree(): continue
		if button.is_hovered() if _pointer_mode else button.has_focus(): return key
	return ""

func _set_state(next: String) -> void:
	if next == state: return
	state = next
	rig.play(next)
	rig.motion.kick(2.5)
	if next != "idle": _sound(next)
	state_changed.emit(next)

func _button(key: String) -> Button:
	if menu == null or not is_instance_valid(menu) or not menu.has_method("action_button"): return null
	return menu.call("action_button", key) as Button

## The title rebuilds its buttons on every page swap: follow PLAY to cheer when it is pressed.
func _bind_buttons() -> void:
	var play := _button("Play")
	if play == _play_button: return
	_play_button = play
	if play != null: play.button_down.connect(_on_play_down)

func _on_play_down() -> void:
	_cheer = CHEER_TIME
	if rig != null: rig.motion.kick(5.0)
	_sound("happy", true)

func _on_visibility() -> void:
	if is_visible_in_tree(): return
	_voice.stop()
	_rub = 0.0
	_rubbing = false

## The pointer comes onto the pet: a curious little whine while it idles.
func _on_hover() -> void:
	if state == "idle": _sound("curious")

func _sound(cue: String, force := false) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - float(_sound_at.get(cue, -100.0)) < float(SOUND_GAP.get(cue, 1.0)): return
	var stream := GameAudio.pet_stream(cue)
	if stream == null: return
	_sound_at[cue] = now
	_voice.stream = stream
	_voice.play()

# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	# The engine's own cursor refresh (a motion at the resting cursor when a cursor shape or the tree changes) and a motion
	# that does not move (the window opening under a resting cursor) are not the player moving the pointer: a key or pad
	# player who focused QUIT stays in key mode. Real moves (and every press and touch) still switch to the pointer.
	if event is InputEventMouseMotion and (event.device == ENGINE_MOTION or (event as InputEventMouseMotion).relative == Vector2.ZERO): return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		var moved := not _pointer_known or not event is InputEventMouseMotion or (event as InputEventMouseMotion).relative != Vector2.ZERO
		_pointer = get_global_transform_with_canvas().affine_inverse() * (event.get("position") as Vector2)
		_pointer_mode = true
		_pointer_known = true
		if moved: _still = 0.0
	elif (event is InputEventKey and event.is_pressed()) or (event is InputEventJoypadButton and event.is_pressed()) \
			or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_pointer_mode = false
		_still = 0.0

func _gui_input(event: InputEvent) -> void:
	var pressed := -1
	var travel := Vector2.ZERO
	var at := Vector2.ZERO
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = 1 if event.is_pressed() else 0
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).index == 0:
		pressed = 1 if event.is_pressed() else 0
	elif event is InputEventMouseMotion and _rubbing:
		travel = (event as InputEventMouseMotion).relative
		at = (event as InputEventMouseMotion).position
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == 0 and _rubbing:
		travel = (event as InputEventScreenDrag).relative
		at = (event as InputEventScreenDrag).position
	if pressed == 1:
		_rubbing = true
		_rub += RUB_TAP
		_sound("poke", true)
		_sound_at["pet"] = Time.get_ticks_msec() / 1000.0 # the petted sigh follows only if the rub goes on
		if rig != null: rig.motion.kick(1.5)
		accept_event()
	elif pressed == 0:
		_rubbing = false
		accept_event()
	elif travel != Vector2.ZERO:
		# Only rubbing on the pet counts; the drag keeps its press when it slides off.
		if _hit.has_point(at): _rub = minf(_rub + travel.length() / maxf(size.y, 1.0), 0.6)
		accept_event()

# ------------------------------------------------------------------ gaze

func _aim(delta: float) -> void:
	var motion := rig.motion
	if _pointer_mode and _pointer_known and _still < LOOK_AROUND_AFTER:
		motion.look_target = _screen_point(_pointer)
		return
	var focused: Variant = _focused_center()
	if not _pointer_mode and focused != null and _still < LOOK_AROUND_AFTER:
		motion.look_target = _screen_point(focused)
		return
	# Nothing moves: look around now and then, and back at the player.
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = _random.randf_range(1.6, 3.2)
		_wander = Vector2.INF if _random.randf() < 0.35 else _box.get_center() + Vector2(_random.randf_range(-0.7, 0.6), _random.randf_range(-0.5, 0.2)) * _box.size
	motion.look_target = _camera.global_position if _wander == Vector2.INF else _screen_point(_wander)

func _focused_center() -> Variant:
	for key: String in HAPPY_KEYS + SAD_KEYS:
		var button := _button(key)
		if button != null and button.has_focus():
			return get_global_transform_with_canvas().affine_inverse() * button.get_global_transform_with_canvas() * (button.size * 0.5)
	return null

## The world point under a title point, about halfway between the camera and the pet.
func _screen_point(at: Vector2) -> Vector3:
	var depth := _camera.global_position.distance_to(rig.global_position) * 0.55
	return _camera.project_position((at - _box.position) * _scale, depth)

## Where hearts rise from: just above the cap (or the head), in title px.
func _head_point() -> Vector2:
	var top: Vector3
	if rig.cap != null: top = rig.cap.global_position
	else: top = rig.global_transform * rig.bounds().get_center()
	return _box.position + _camera.unproject_position(top) / _scale

# ------------------------------------------------------------------ layout

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0: return
	# Render at screen resolution (the title is stretched from design px), at most 2x.
	var screen := get_viewport().get_final_transform().get_scale().x * get_global_transform_with_canvas().get_scale().x
	_scale = clampf(screen, 1.0, 2.0)
	if rig != null and _fit_frames < 0: _aspect = _width(rig.bounds()) / maxf(rig.bounds().size.y, 0.01)
	var tall := (HEIGHT_WIDE if size.x / size.y >= 1.1 else HEIGHT_TALL) * size.y
	var free := size.x * (1.0 - FREE_FROM) - size.y * EDGE
	tall = minf(tall, free / maxf(_aspect, 0.1))
	_size = Vector2(tall * _aspect, tall)
	_box.size = _size * ROOM
	_view.scale = Vector2.ONE / _scale
	_view.size = _box.size * _scale
	# Until the camera is fitted: the feet low in the middle of the box.
	_feet = Vector2(_box.size.x * 0.5, _box.size.y * (0.5 + 0.5 / ROOM.y))
	if rig != null and _fit_frames < 0: _fit_camera()
	_ground_share = ground_share()
	_ground = Vector2.INF
	_follow_ground()

## Where the feet go on the title: GROUND on the art (it sways a few px), kept right of the menu and inside the screen.
func _ground_point() -> Vector2:
	var backdrop: CanvasItem = null
	if menu != null and is_instance_valid(menu): backdrop = menu.get_node_or_null("MenuBackdrop") as CanvasItem
	var at := _ground_share * size
	if backdrop != null and backdrop.has_method("art_point"):
		at = get_global_transform_with_canvas().affine_inverse() * backdrop.get_global_transform_with_canvas() * (backdrop.call("art_point", _ground_share) as Vector2)
	var edge := size.y * EDGE
	var half := _size.x * 0.5
	at.x = clampf(at.x, size.x * FREE_FROM + half, size.x - edge - half)
	at.y = clampf(at.y, _size.y + edge, size.y - edge)
	return at

## Moves the pet's box so its feet stand on the ground point (every frame: the art sways).
func _follow_ground() -> void:
	var at := _ground_point()
	if at.is_equal_approx(_ground): return
	_ground = at
	_box.position = at - _feet
	_view.position = _box.position
	_hit = Rect2(_box.position + _hit_in_box.position, _hit_in_box.size).intersection(Rect2(Vector2.ZERO, size))

## Frames the pet in its box (looking down a little, like the drawing), puts the contact shadow under it and works out
## where its feet are and where it can be petted.
func _fit_camera() -> void:
	var bounds := rig.transform * rig.bounds()
	var view := Vector2(_viewport.size)
	var aspect := view.x / maxf(view.y, 1.0)
	var half := tan(deg_to_rad(FOV) * 0.5)
	var tall := bounds.size.y * 0.5 * ROOM.y
	var wide := _width(rig.bounds()) * 0.5 * ROOM.x
	var distance := maxf(tall / half, wide / (half * aspect)) + bounds.size.z * 0.5
	var center := bounds.get_center()
	_camera.position = center + Vector3(0.0, sin(ELEVATION), cos(ELEVATION)) * distance
	_camera.look_at(center, Vector3.UP)
	var floor_at := Vector3(center.x, bounds.position.y + 0.01, center.z)
	_shadow.position = floor_at
	_shadow.scale = Vector3(bounds.size.x * 1.05, bounds.size.z * 0.75, 1.0)
	_shadow.visible = true
	_feet = _camera.unproject_position(floor_at) / _scale
	# Petted anywhere on its body: from the top of its bounds down to the feet, as wide as it looks.
	var top := INF
	for corner in 8: top = minf(top, _camera.unproject_position(bounds.get_endpoint(corner)).y / _scale)
	var drawn := _feet.y - top
	_hit_in_box = Rect2(_feet.x - _size.x * 0.45, top + drawn * 0.04, _size.x * 0.9, drawn * 0.98)
	_ground = Vector2.INF

## The point of the title art the pet stands on: the cast's title.pet_ground when it is two numbers from 0 to 1, else GROUND.
static func ground_share() -> Vector2:
	var title = TeamCast.data().get("title", {})
	var spot = title.get("pet_ground") if title is Dictionary else null
	if spot is Array and spot.size() == 2 and (spot[0] is float or spot[0] is int) and (spot[1] is float or spot[1] is int):
		var share := Vector2(float(spot[0]), float(spot[1]))
		if share.x >= 0.0 and share.x <= 1.0 and share.y >= 0.0 and share.y <= 1.0: return share
	return GROUND

## How wide the pet looks from the front once turned by TURN: its own bounds as an ellipse (it is round, not a box).
static func _width(own: AABB) -> float:
	return Vector2(own.size.x * cos(TURN), own.size.z * sin(TURN)).length()
