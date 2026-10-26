extends SceneTree
## Frames of the menu pages without a window: title, each Settings page, the in-game pause menu, the loading page.
## Prints MENU_SHOTS lines. Run offscreen (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/menu_shots_check.gd -- --shots=<dir>
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
	print("MENU_SHOTS shot ", name, " ", image.save_png("%s/%s.png" % [shots, name]) == OK)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

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
			print("MENU_SHOTS boot_timeout")
			quit(2)
			return
	var ui = sim.local_presentation
	await frames(90)
	capture("title")
	# Settings from the title: each page
	ui.menus.show_pause(false)
	for tab in ui.menus.TABS.size():
		ui.menus._select_tab(tab)
		await frames(40)
		capture("settings-" + str(ui.menus.TABS[tab]).to_lower())
		print("MENU_SHOTS probe ", JSON.stringify(ui.menus.probe()))
	ui.menus.hide_pause()
	await frames(10)
	# The in-game pause menu inside a level
	ui.show_local_job()
	ui._input_mode_selected(2)
	await process_frame
	ui.start_job()
	await frames(90)
	var centre: Vector3 = load("res://network/walk_in_lobby.gd").center(load("res://course_section.gd").ADVENTURE)
	sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
	sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	var flow = ui.level_flow
	var t0 := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - t0 < 20000: await frames(10)
	ui.menus.end_run_available = true
	await frames(60)
	capture("level")
	ui.menus.show_pause(true)
	await frames(40)
	capture("pause")
	ui.menus.hide_pause()
	# The loading page
	var screens = load("res://client/online_screens.gd").new()
	root.add_child(screens)
	screens.show_loading("Finding a partner", "Waiting for a second courier", true, 0.4, 1)
	await frames(60)
	capture("loading")
	quit(0)
