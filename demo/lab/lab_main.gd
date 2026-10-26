extends Node
## The solo levels lab: one courier alone (no painting, no second player, no lobby) on every level in difficulty order.
## Stop N is the start pad of level N. Travelling to a stop starts that level: a new epoch, the level clock at zero, the hazards
## at their start, only that level drawn. Reaching the goal shows LEVEL CLEARED and, after the card, starts the next stop.
## The lab is a small simulation of its own (level world, one courier body, the follow camera, the game audio); it shares the
## modules of the game, not the two-courier shell. Doc: docs/solo-lab.md.
##
## Keys: WASD move, mouse look, Space jump, Esc pause sheet, R restart the level, [ ] or PgUp PgDn previous / next stop,
## a typed number (+ Enter) goes to that stop, N fly (Space up, C down, Shift fast), G no-death, H help.
const Motion = preload("res://courier/courier_motion.gd")
const LevelWorld = preload("res://levels/level_world.gd")
const LevelRun = preload("res://levels/level_run.gd")
const GameInput = preload("res://game/game_input.gd")
const LoadSlicer = preload("res://game/load_slicer.gd")
const OnlineScreens = preload("res://client/online_screens.gd")
const LevelHud = preload("res://client/level_hud.gd")
const Hud = preload("res://client/hud.gd")
const HudComic = preload("res://client/hud_comic.gd")
const ComicText = preload("res://client/comic_text.gd")
const LabSheets = preload("res://lab/lab_sheets.gd")
const MenuStyle = preload("res://client/menu_style.gd")
const FriendsStyle = preload("res://style/friends_style.gd")
const VisualTrack = preload("res://game/visual_track.gd")

const LABEL := "SOLO LEVELS"
const FLY_SPEED := 14.0
const FLY_FAST := 3.0
const CAMERA_FOCUS := Vector3(0.0, 1.0, 0.0) ## above the courier's feet
const FIRM_EVERY := 12 ## ticks between the "last place I stood" samples of the no-death mode
const DIGIT_WAIT_MSEC := 700

var level_world
var world: Node3D
var body: CharacterBody3D
var motion
var rig
var camera: Camera3D
var follow
var _visual := VisualTrack.new() ## where the courier is drawn between two physics ticks (game/visual_track.gd): the rig and the camera use it
var audio
var input := GameInput.new()
var screens: Control
var level_hud: CanvasLayer
var hint_hud: CanvasLayer ## client/hud.gd used for its key hints only
var sheets ## lab_sheets.gd: clock, help, stop list, pause sheet, toast

var stops: Array = [] ## {level, name, pad (feet, world), yaw}
var stop := 0
var epoch := 0
var lab_ready := false
var fatal := false
var elapsed := 0.0 ## seconds on the level's clock; runs from the first move
var started_moving := false
var cleared := false
var cleared_seconds := 0.0
var clear_wait := 0.0
var fly := false
var god := false
var help_mode := 1 ## 0 hidden, 1 keys, 2 keys and the stop list
var pause_open := false
var digits := ""
var digits_msec := 0
var yaw := 0.0
var pitch := deg_to_rad(-45.0) ## the game's top-down view (game/follow_camera.gd PITCH_DEFAULT)
var last_firm := Vector3.ZERO
var deaths := 0
var launches := 0

var _firm_tick := 0
var _slicer
var _last_events := {}

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 3
	_build_ui()
	screens.set_loading_kicker(LABEL)
	screens.show_loading("THE LEVELS", "Building the levels", false, 0.0)
	_boot.call_deferred()

func _boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	level_world = LevelWorld.new()
	level_world.name = "Levels"
	world.add_child(level_world)
	_slicer = LoadSlicer.new(get_tree(), func(part: float, label: String) -> void: _progress(lerpf(0.04, 0.85, part), label))
	await level_world.build("client", _slicer)
	var count: int = level_world.level_count()
	if count < 1:
		_fail("No level files were found (levels/level_01.json ...).")
		return
	_progress(0.88, "Courier")
	_build_courier()
	_build_stops(count)
	_progress(0.94, "Camera and sound")
	_build_view()
	_start_stop(0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_slicer.release()
	_progress(1.0, "Ready")
	await get_tree().process_frame
	screens.hide_all()
	lab_ready = true
	print("GW_LAB_READY stops=", stops.size(), " first=", stops[0].name)
	_run_tools()

func _progress(fraction: float, label: String) -> void:
	if screens != null and screens.current() == "loading": screens.update_loading_progress(fraction, label)

func _fail(detail: String) -> void:
	fatal = true
	print("GW_LAB_FATAL ", detail)
	screens.show_error("Lab failed", detail)

func _run_tools() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var tool: Node = null
		if arg == "--lab-levelscheck": tool = load("res://lab/lab_check.gd").new()
		elif arg.begins_with("--lab-shots="): tool = load("res://lab/lab_shots.gd").new()
		if tool == null: continue
		add_child(tool)
		if tool.has_method("run_shots"): tool.run_shots(self, arg.trim_prefix("--lab-shots="))
		else: tool.run(self)

# ------------------------------------------------------------------ build

func _build_courier() -> void:
	body = Motion.make_body("Courier")
	world.add_child(body)
	motion = Motion.new()
	motion.setup(body)
	rig = load("res://courier/courier_rig.gd").new()
	rig.name = "CourierRig"
	world.add_child(rig)
	rig.setup(0)

func _build_stops(count: int) -> void:
	stops.clear()
	for k in count:
		var pose: Dictionary = level_world.start_pose(k)
		var pad: Vector3 = ((pose.a as Vector3) + (pose.b as Vector3)) * 0.5
		stops.append({"level": k, "name": "%d %s" % [k + 1, level_world.title(k)], "pad": pad + Vector3.UP * 0.05, "yaw": float(pose.get("yaw", 0.0))})

func _build_view() -> void:
	var follow_script: GDScript = load("res://game/follow_camera.gd")
	var audio_script: GDScript = load("res://game/game_audio.gd")
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	world.add_child(camera)
	follow = follow_script.new()
	follow.configure(camera)
	follow.own_body(rig, 0)
	audio = audio_script.new()
	audio.name = "GameAudio"
	add_child(audio)
	audio.configure(camera)
	audio.bind_courier(0, rig, true)
	audio.playback_enabled = not _silent()
	if not _silent(): audio.install_music(get_tree())

func _silent() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--lab-levelscheck" or arg.begins_with("--lab-shots="): return true
	return DisplayServer.get_name() == "headless"

func _build_ui() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 70
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	MenuStyle.set_asset_reader(func(path: String) -> Resource: return ResourceLoader.load(path) if ResourceLoader.exists(path) else null) # the loading page's backdrop
	screens = OnlineScreens.new()
	overlay.add_child(screens)
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens.set_loading_steps(PackedStringArray(["Levels", "Courier", "Camera"]))
	screens.back_pressed.connect(func() -> void: get_tree().quit(1))
	level_hud = LevelHud.new()
	add_child(level_hud)
	hint_hud = Hud.new()
	add_child(hint_hud)
	hint_hud.visible = false
	hint_hud.clock_view.hide() # the lab has its own clock
	sheets = LabSheets.new()
	add_child(sheets)
	sheets.configure(self)

# ------------------------------------------------------------------ stops and epochs

## Starts level `index` as a new epoch: clock zero, hazards from their start, the courier on the pad.
func _start_stop(index: int) -> void:
	stop = posmod(index, stops.size())
	var entry: Dictionary = stops[stop]
	epoch += 1
	cleared = false
	clear_wait = 0.0
	elapsed = 0.0
	started_moving = false
	level_world.set_active_level(int(entry.level))
	level_world.set_clock(0.0)
	level_world.reset_effects()
	motion.reset(body, entry.pad, float(entry.yaw))
	body.set_meta(&"epoch", epoch)
	rig.global_position = entry.pad
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": float(entry.yaw), "carrying": false})
	yaw = float(entry.yaw)
	if follow != null:
		pitch = follow.default_pitch()
		follow.reset_lag()
	last_firm = entry.pad
	_firm_tick = 0
	input.clear()
	print("GW_LAB_STOP stop=", stop + 1, " level=", int(entry.level) + 1, " epoch=", epoch, " ", entry.name)

func travel(index: int) -> void:
	if not lab_ready or stops.is_empty(): return
	_start_stop(index)
	if fly: _set_fly(false)
	sheets.toast(str(stops[stop].name))

func travel_step(step: int) -> void:
	travel(posmod(stop + step, stops.size()))

## R and the pause sheet's Restart: the same level again from its start.
func restart() -> void:
	if not lab_ready: return
	_start_stop(stop)
	sheets.toast("Restart  " + str(stops[stop].name))

## Back on the pad (the level keeps running).
func respawn() -> void:
	if not lab_ready: return
	var entry: Dictionary = stops[stop]
	_place(entry.pad)
	yaw = float(entry.yaw)
	pitch = follow.default_pitch()
	follow.reset_lag()
	print("GW_LAB_RESPAWN at=", entry.pad)

func _place(at: Vector3) -> void:
	motion.teleport(body, at)
	rig.global_position = at
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": motion.yaw, "carrying": false})

func grounded_now() -> bool:
	return motion.grounded

func current_level() -> int:
	return int(stops[stop].level)

func blocked() -> bool:
	return not lab_ready or fatal or pause_open

# ------------------------------------------------------------------ tick

func _physics_process(delta: float) -> void:
	if not lab_ready: return
	if blocked():
		input.clear()
		return
	level_world.advance(delta)
	var action := _sample(delta)
	var frozen := cleared
	if fly: _fly_step(delta, action, frozen)
	else: _walk_step(delta, action, frozen)
	rig.global_position = body.global_position
	_visual.sample(0, body.global_position)
	if cleared:
		clear_wait += delta
		if clear_wait >= LevelRun.CLEARED_SECONDS: _start_stop(stop + 1)
		return
	if started_moving: elapsed += delta
	if fly: return
	_zones()

## One tick of the devices: keyboard and the first pad. Returns {move (world XZ), jumps}.
func _sample(delta: float) -> Dictionary:
	var move := Vector2.ZERO
	var jumps := 0
	var look := Vector2.ZERO
	var devices: Array = [GameInput.KEYBOARD]
	var pads := Input.get_connected_joypads()
	if not pads.is_empty(): devices.append(int(pads[0]))
	for device: int in devices:
		var action := input.sample(device, delta)
		if absf(action.move.x) >= absf(move.x): move.x = action.move.x
		if absf(action.move.y) >= absf(move.y): move.y = action.move.y
		jumps += int(action.jumps)
		look += action.look
	if look != Vector2.ZERO:
		var change := GameInput.look_delta(look)
		yaw = wrapf(yaw + change.x, -PI, PI)
		pitch = follow.clamp_pitch(pitch + change.y)
	return {"move": GameInput.world_move(move, yaw), "jumps": jumps}

func _walk_step(delta: float, action: Dictionary, frozen: bool) -> void:
	var move: Vector2 = Vector2.ZERO if frozen else action.move
	if move.length_squared() > 0.0: started_moving = true
	var level := current_level()
	var effects: Dictionary = level_world.apply_effects(level, 0, body, motion)
	if not effects.is_empty():
		launches += 1
		if audio != null:
			if str(effects.kind) == "bonk": audio.play_event("slap", effects.at)
			else: audio.play_push()
	_last_events = motion.step(body, {"move": move, "jump": not frozen and int(action.jumps) > 0}, delta)
	_firm_tick += 1
	if _firm_tick % FIRM_EVERY == 0 and motion.grounded and not cleared: last_firm = body.global_position

## Free flight: no collision, no gravity, Space up, C down, Shift fast.
func _fly_step(delta: float, action: Dictionary, frozen: bool) -> void:
	var move: Vector2 = Vector2.ZERO if frozen else action.move
	var wish := Vector3(move.x, 0.0, move.y)
	if not frozen:
		if Input.is_physical_key_pressed(KEY_SPACE): wish.y += 1.0
		if Input.is_physical_key_pressed(KEY_C): wish.y -= 1.0
	wish = wish.limit_length(1.0) * FLY_SPEED * (FLY_FAST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	if wish != Vector3.ZERO: started_moving = true
	body.global_position += wish * delta
	body.velocity = Vector3.ZERO
	if Vector2(wish.x, wish.z).length() > 0.1:
		motion.yaw = atan2(-wish.x, -wish.z)
		body.rotation.y = motion.yaw
	motion.grounded = false
	motion.floor_normal = Vector3.ZERO

## Kill volumes and the void put the courier back (the pad, or where it last stood with G); the goal clears the level.
func _zones() -> void:
	var zone: String = level_world.zone_at(current_level(), body.global_position)
	if zone == "kill":
		deaths += 1
		if audio != null: audio.play_death()
		if god and last_firm != Vector3.ZERO:
			_place(last_firm)
			print("GW_LAB_GOD_SAVE at=", last_firm)
		else:
			_place(stops[stop].pad)
			print("GW_LAB_DEATH deaths=", deaths)
	elif zone == "goal":
		cleared = true
		cleared_seconds = elapsed
		clear_wait = 0.0
		print("GW_LAB_CLEARED stop=", stop + 1, " seconds=", snappedf(elapsed, 0.01))

## What the level HUD shows: the lab's own run (label, stop number, the card with the next stop's title).
func run_state() -> Dictionary:
	var next_title := str(level_world.title(int(stops[posmod(stop + 1, stops.size())].level)))
	var state := {"mode": "lab", "label": LABEL, "level": current_level(), "number": stop + 1, "count": stops.size(), "cleared": 0, "base": elapsed,
		"times": [], "queue": [], "clearing": cleared, "next_title": next_title, "next_in": maxf(LevelRun.CLEARED_SECONDS - clear_wait, 0.0) if cleared else -1.0}
	if cleared:
		state["times"] = [cleared_seconds]
		state["queue"] = [current_level()]
	return state

# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	if not lab_ready:
		return
	_mouse_mode()
	if digits != "" and Time.get_ticks_msec() - digits_msec > DIGIT_WAIT_MSEC: _commit_digits()
	if not blocked():
		var look: Vector2 = follow.look(yaw, pitch)
		yaw = look.x
		pitch = look.y
	else: follow.discard_look()
	var state := {"velocity": body.velocity, "grounded": motion.grounded, "yaw": motion.yaw, "acceleration": motion.acceleration, "floor_normal": motion.floor_normal, "carrying": false, "paused": pause_open, "flop": motion.flop_left}
	var drawn := _visual.at(0, body.global_position)
	rig.global_position = drawn
	rig.update(delta, state, [])
	if follow.first_person: follow.update_first_person(delta, drawn, yaw, pitch)
	else: follow.update(delta, drawn + CAMERA_FOCUS, yaw, pitch, null)
	level_hud.update(run_state(), elapsed)
	hint_hud.visible = not blocked() and not cleared and not fly
	hint_hud.update_from_state({"playing": hint_hud.visible, "resets": epoch, "elapsed_seconds": elapsed}) # the game's key hints (move, jump); the lab has no painting to tilt or lift
	sheets.refresh(delta)

func _mouse_mode() -> void:
	if DisplayServer.get_name() == "headless": return
	var capture := not blocked() and DisplayServer.window_is_focused()
	var wanted := Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted: Input.mouse_mode = wanted

# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not lab_ready or blocked(): return
	input.push_event(event)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		follow.queue_look(event.screen_relative)

func _unhandled_input(event: InputEvent) -> void:
	if not lab_ready or fatal: return
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	if escape or start:
		set_pause(not pause_open)
		get_viewport().set_input_as_handled()
		return
	if pause_open or not (event is InputEventKey and event.pressed and not event.echo): return
	var digit := _digit_of(event.physical_keycode)
	if digit >= 0:
		_digit_key(digit)
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_R: restart()
		KEY_BRACKETLEFT, KEY_PAGEUP: travel_step(-1)
		KEY_BRACKETRIGHT, KEY_PAGEDOWN: travel_step(1)
		KEY_ENTER, KEY_KP_ENTER: _commit_digits()
		KEY_N: _set_fly(not fly)
		KEY_G: _set_god(not god)
		KEY_H: help_mode = (help_mode + 1) % 3

func set_pause(open: bool) -> void:
	if pause_open == open or not lab_ready: return
	pause_open = open
	input.clear()
	sheets.set_pause(open)

func _set_fly(on: bool) -> void:
	if fly == on: return
	fly = on
	if not on: motion.teleport(body, body.global_position) # back under gravity from where the flight ended
	sheets.toast("Fly: " + ("ON  (Space up, C down, Shift fast)" if on else "off"))
	print("GW_LAB_FLY ", on)

func _set_god(on: bool) -> void:
	god = on
	sheets.toast("No-death: " + ("ON  (a fall puts you back where you last stood)" if on else "off"))
	print("GW_LAB_GOD ", on)

static func _digit_of(code: Key) -> int:
	if code >= KEY_0 and code <= KEY_9: return code - KEY_0
	if code >= KEY_KP_0 and code <= KEY_KP_9: return code - KEY_KP_0
	return -1

func _digit_key(digit: int) -> void:
	digits += str(digit)
	digits_msec = Time.get_ticks_msec()
	if int(digits) == 0: digits = ""
	elif int(digits) * 10 > stops.size() or digits.length() >= 2: _commit_digits()

func _commit_digits() -> void:
	if digits == "": return
	var number := int(digits)
	digits = ""
	if number >= 1 and number <= stops.size(): travel(number - 1)
	else: sheets.toast("No stop %d (1 to %d)" % [number, stops.size()])
