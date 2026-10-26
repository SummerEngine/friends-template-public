extends Node
## Dev builds only: `-- --shots=<dir>` walks the local game by itself and saves 1280x720 PNGs of each screen for review,
## then quits. A normal windowed run (the editor binary or a debug export; a release build ignores the switch):
##   Summer --path demo -- --shots=/abs/dir
## The walk: the title idle, PLAY lit (the pet happy), the pet petted, QUIT lit (sad); PLAY on one keyboard into the
## lobby yard; player 1 walks to the wardrobe booth and opens the customizer (E): every tab, a few sliders at their ends,
## RANDOMIZE ALL, CANCEL; both players walk onto the TIME ATTACK circle; the first seconds of the level. Pointer and keys
## are fed as input events (Input.parse_input_event / push_input), so the screens react as to a player. A step that cannot
## happen (no wardrobe, no pet model) is skipped with a line. Headless the walk runs the same and saves nothing.
## Files are numbered in walk order (01_title_idle.png, 02_title_play_hover.png, ...). Prints DEV_SHOTS lines; the last is
## `DEV_SHOTS done saved=<n> skipped=<list>`.
##   presentation_entry.gd: DevShots.attach(self)
const DevEnv := preload("res://dev_env.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Wardrobe := preload("res://character/wardrobe/wardrobe.gd")
const WardrobeUi := preload("res://character/wardrobe/wardrobe_ui.gd")
const FLAG := "--shots="
const SIZE := Vector2i(1280, 720)
## Seconds a walk may take before the player is put there (a pushed key can be lost when the window loses focus).
const WALK_TIME := 14.0
## Player keys on one keyboard: up, left, down, right.
const KEYS := [[KEY_W, KEY_A, KEY_S, KEY_D], [KEY_I, KEY_J, KEY_K, KEY_L]]

var game: Node ## game/game_run.gd (client/presentation_entry.gd)
var folder := ""
var saved := 0
var shots := 0
var skipped: Array[String] = []
var _held := {}

## Adds the walk to `host` when the switch is given (dev builds only); otherwise nothing.
static func attach(host: Node) -> void:
	for arg: String in DevEnv.user_args():
		if arg.begins_with(FLAG):
			var shots: Node = load("res://client/dev_shots.gd").new()
			shots.game = host
			shots.folder = arg.trim_prefix(FLAG)
			host.add_child.call_deferred(shots)
			return

func _init() -> void:
	name = "DevShots"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_run.call_deferred()

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

# ------------------------------------------------------------------ the walk

func _run() -> void:
	print("DEV_SHOTS start folder=", folder, " headless=", _headless())
	if not _headless():
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = SIZE
		DirAccess.make_dir_recursive_absolute(folder)
		# The window takes the system focus first: its focus-in and the cursor entering it come before the title steps.
		get_window().grab_focus()
		var focus_by := Time.get_ticks_msec() + 3000
		while not get_window().has_focus() and Time.get_ticks_msec() < focus_by: await get_tree().process_frame
		await _seconds(0.5)
		print("DEV_SHOTS window focus=", get_window().has_focus())
	var deadline := Time.get_ticks_msec() + 180000
	while not (game.is_network_ready() and game.local_presentation != null and game.local_presentation.ready_for_play):
		if Time.get_ticks_msec() > deadline:
			_finish("boot timeout")
			return
		await get_tree().process_frame
	var ui = game.local_presentation
	await _title(ui)
	await _lobby(ui)
	_finish("")

func _title(ui) -> void:
	var menu: Control = ui.main_menu
	var pet: Control = menu.get_node_or_null("MenuPet")
	var deadline := Time.get_ticks_msec() + 30000
	while pet != null and pet.has_model() and not pet.is_loaded() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var empty := menu.get_global_rect().position + menu.size * Vector2(0.5, 0.06)
	_point(empty)
	await _seconds(1.2)
	_pet_state(pet)
	await _shot("title_idle")
	var play: Button = menu.action_button("Play")
	if play != null:
		await _hover(play)
		_pet_state(pet)
		await _shot("title_play_hover")
	if pet != null and pet.is_loaded():
		var spot: Vector2 = pet.get_global_transform_with_canvas() * pet.hit_rect().get_center()
		_press(spot, true)
		for step in 50:
			_point(spot + Vector2(sin(step * 0.8), cos(step * 0.6) * 0.4) * pet.hit_rect().size.x * 0.22, true)
			await get_tree().process_frame
		_pet_state(pet)
		await _shot("title_petting")
		_press(spot, false)
	else: _skip("title_petting (no pet)")
	var quit_button: Button = menu.action_button("Quit")
	if quit_button != null:
		await _seconds(1.0) # the petting fades first
		await _hover(quit_button)
		_pet_state(pet)
		await _shot("title_quit_hover")
	else: _skip("title_quit_hover (no Quit on this screen)")
	_point(empty)
	await _seconds(0.3)

func _lobby(ui) -> void:
	# PLAY with both players on one keyboard, whatever pads are connected.
	ui.show_local_job()
	ui._input_mode_selected(2)
	ui.start_job()
	var deadline := Time.get_ticks_msec() + 20000
	while not (ui.level_flow != null and ui.level_flow.phase == "lobby") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if ui.level_flow == null or ui.level_flow.phase != "lobby":
		_skip("lobby, customizer, level (no lobby yard)")
		return
	await _seconds(1.5)
	await _shot("lobby")
	var wardrobe: Node = game.world.find_child("Wardrobe", true, false)
	if wardrobe != null:
		await _walk({0: WalkInLobby.ORIGIN + WalkInLobby.wardrobe_center()})
		await _seconds(0.5)
		await _shot("lobby_wardrobe_booth")
		await _customizer(wardrobe)
	else: _skip("wardrobe, customizer (no booth in the yard)")
	var pad := WalkInLobby.center(WalkInLobby.PADS[0].course)
	await _walk({0: pad + Vector3(-0.6, 0.0, 0.0), 1: pad + Vector3(0.6, 0.0, 0.0)})
	await _shot("lobby_on_pad")
	ui.level_flow.press_play()
	deadline = Time.get_ticks_msec() + 15000
	while ui.level_flow.phase != "round" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if ui.level_flow.phase != "round":
		_skip("level (it did not start)")
		return
	await _seconds(0.3)
	await _shot("level_start")
	await _seconds(1.2)
	await _shot("level_1s")
	await _seconds(2.0)
	await _shot("level_3s")

func _customizer(wardrobe: Node) -> void:
	_key(KEY_E, true)
	await get_tree().process_frame
	_key(KEY_E, false)
	await _seconds(0.2)
	if wardrobe.owner_slot < 0:
		print("DEV_SHOTS E did not open the wardrobe: opening it directly")
		wardrobe.open(0)
	if wardrobe.owner_slot < 0 or wardrobe.panel == null:
		_skip("customizer (player 1 cannot be dressed)")
		return
	await _seconds(0.9)
	await _shot("customizer_open")
	var panel: Control = wardrobe.panel
	for spec: Dictionary in WardrobeUi.TABS:
		var title := str(spec.title)
		_click(panel.find_child("Tab" + title, true, false) as Button)
		await _seconds(0.5)
		await _shot("customizer_" + title.to_lower())
	# On PARAMS (the last tab): the first sliders to their ends, alternating.
	var sliders := panel.find_children("*", "HSlider", true, false)
	for index in mini(sliders.size(), 6):
		var slider := sliders[index] as HSlider
		slider.value = slider.max_value if index % 2 == 0 else slider.min_value
	await _seconds(0.5)
	await _shot("customizer_sliders_extreme")
	_click(panel.find_child("RandomizeAll", true, false) as Button)
	await _seconds(0.5)
	await _shot("customizer_randomized")
	_click(panel.find_child("Cancel", true, false) as Button)
	await _seconds(0.8)
	await _shot("customizer_cancelled")

## Walks players (slot -> world point) there with their keys, steering by the camera they play with; after WALK_TIME the
## ones still on the way are put there.
func _walk(targets: Dictionary) -> void:
	var start := Time.get_ticks_msec()
	var left := targets.duplicate()
	while not left.is_empty() and Time.get_ticks_msec() - start < WALK_TIME * 1000.0:
		for slot: int in left.keys():
			var actor: Node3D = game.actors[slot]
			var to: Vector3 = left[slot] - actor.global_position
			to.y = 0.0
			if to.length() < 0.45:
				_steer(slot, Vector2.ZERO)
				left.erase(slot)
				continue
			var yaw: float = game.local_camera_yaws[slot] if game.local_split_screen else game.yaw
			# The inverse of GameInput.world_move: world XZ -> (x right, y forward) for this camera heading.
			var local := Basis(Vector3.UP, -yaw) * to.normalized()
			_steer(slot, Vector2(local.x, -local.z))
		await get_tree().physics_frame
	for slot: int in targets:
		_steer(slot, Vector2.ZERO)
		if left.has(slot):
			print("DEV_SHOTS walk slot=", slot, " put there after ", WALK_TIME, " s")
			game.motions[slot].teleport(game.actors[slot], targets[slot] + Vector3(0.0, 0.05, 0.0))
	await _seconds(0.4)

## Holds the slot's keys for a move direction (x right, y forward); zero lets go.
func _steer(slot: int, move: Vector2) -> void:
	var keys: Array = KEYS[slot]
	var want := [move.y > 0.38, move.x < -0.38, move.y < -0.38, move.x > 0.38]
	for index in 4:
		var key: int = keys[index]
		if want[index] != bool(_held.get(key, false)) or (want[index] and not Input.is_physical_key_pressed(key)):
			_key(key, want[index])

## Lights a title button as the pointer would. The hover and the key focus are one lit state on the title and the pet reads
## both; a pushed pointer hovers only while the system cursor is over the window, so this uses the focus (Shift taps keep
## the pet in key mode while the button holds the focus).
func _hover(button: Button) -> void:
	var until := Time.get_ticks_msec() + 900
	while Time.get_ticks_msec() < until:
		_key(KEY_SHIFT, true)
		_key(KEY_SHIFT, false)
		if not button.has_focus():
			button.grab_focus()
			button.queue_redraw() # the comic skin lights the lettering on a redraw
		await _seconds(0.15)
	if not button.has_focus(): button.grab_focus()
	button.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

func _key(key: int, down: bool) -> void:
	_held[key] = down
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = down
	Input.parse_input_event(event)

func _point(at: Vector2, held := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = Vector2(4.0, 0.0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)

func _press(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	get_viewport().push_input(event, true)

func _click(button: Button) -> void:
	if button == null or button.disabled: return
	button.pressed.emit()

func _seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await get_tree().process_frame

# ------------------------------------------------------------------ saving

func _shot(label: String) -> void:
	shots += 1
	var shot_name := "%02d_%s" % [shots, label]
	if _headless():
		print("DEV_SHOTS shot ", shot_name, " (headless: not saved)")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_skip(shot_name + " (no image)")
		return
	if image.get_size() != SIZE: image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var path := folder.path_join(shot_name + ".png")
	var ok := image.save_png(path) == OK
	if ok: saved += 1
	print("DEV_SHOTS shot ", shot_name, " ", path if ok else "SAVE FAILED")

func _pet_state(pet: Control) -> void:
	if pet == null or not pet.is_loaded(): return
	var focus := get_viewport().gui_get_focus_owner()
	print("DEV_SHOTS pet state=", pet.state, " pointer_mode=", pet.get("_pointer_mode"), " focus=", focus.name if focus != null else "none",
		" window_focus=", get_window().has_focus())

func _skip(what: String) -> void:
	skipped.append(what)
	print("DEV_SHOTS skip ", what)

func _finish(error: String) -> void:
	for key: int in _held:
		if _held[key]: _key(key, false)
	if error != "": print("DEV_SHOTS error ", error)
	print("DEV_SHOTS done saved=", saved, " skipped=", skipped)
	get_tree().paused = false
	get_tree().quit(0 if error == "" else 1)
