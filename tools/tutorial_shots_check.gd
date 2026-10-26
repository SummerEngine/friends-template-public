extends SceneTree
## Frames of the in-world key hints (move / jump / tilt / lift) without a window: they appear at the start of a level and fade once the action was used.
## Prints TUTORIAL_SHOTS lines. Run offscreen (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/tutorial_shots_check.gd -- --shots=<dir>
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []

var shots := ""
var sim: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
	run.call_deferred()

func capture(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("TUTORIAL_SHOTS shot ", name, " ", image.save_png("%s/%s.png" % [shots, name]) == OK)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	sim = VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("TUTORIAL_SHOTS boot_timeout")
			quit(2)
			return
	var ui = sim.local_presentation
	ui.show_local_job()
	ui._input_mode_selected(2)
	await process_frame
	ui.start_job()
	await frames(90)
	# walking about in the lobby (WASD held, a jump) must not use up the round's hints
	key(KEY_W, true)
	await frames(75)
	key(KEY_W, false)
	key(KEY_SPACE, true)
	await frames(6)
	key(KEY_SPACE, false)
	await frames(10)
	print("TUTORIAL_SHOTS taught after the lobby=", ui.hud.taught.keys())
	var centre: Vector3 = load("res://network/walk_in_lobby.gd").center(load("res://course_section.gd").ADVENTURE)
	sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
	sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	var flow = ui.level_flow
	var t0 := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - t0 < 20000: await frames(10)
	print("TUTORIAL_SHOTS phase=", flow.phase, " hud_visible=", ui.hud.visible)
	await frames(15)
	capture("0-start")
	await frames(60)
	print("TUTORIAL_SHOTS signs ", ui.hud.signs.keys().map(func(k): return [k, ui.hud.signs[k].wanted, snappedf(ui.hud.signs[k].amount, 0.01)]))
	capture("1-move-hint")
	for k in [KEY_W]: key(k, true)
	await frames(30)
	capture("2-move-used")
	await frames(30)
	for k in [KEY_W]: key(k, false)
	capture("3-move-fading")
	await frames(60)
	print("TUTORIAL_SHOTS signs ", ui.hud.signs.keys().map(func(k): return [k, ui.hud.signs[k].wanted, snappedf(ui.hud.signs[k].amount, 0.01)]))
	capture("4-jump-hint")
	key(KEY_SPACE, true)
	await frames(10)
	key(KEY_SPACE, false)
	await frames(60)
	capture("5-jump-done")
	print("TUTORIAL_SHOTS taught=", ui.hud.taught.keys())
	quit(0)
