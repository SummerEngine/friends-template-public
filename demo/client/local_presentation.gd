extends Node
const _DevLap := preload("res://dev_env.gd")
## Local two-player delivery on one machine: the title (one Play), the round HUD and the one pause
## menu. Play picks the controls from the connected gamepads: two pads, a keyboard and a pad, or both
## couriers on one keyboard (then one shared view). The level game itself is client/local_level_flow.gd.
signal reload_requested
const MainMenu := preload("res://client/main_menu.gd")
const Hud := preload("res://client/hud.gd")
const Menus := preload("res://client/menus.gd")
const TitleCamera := preload("res://client/friends_title_camera.gd")
const Widgets := preload("res://client/friends_widgets.gd")
const CourseSection := preload("res://course_section.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
var simulation: Node
var menu_canvas: CanvasLayer
var main_menu
var hud
var menus
var level_flow # the level game (the client's, installed through tree meta): lobby circles, runs, results
var title_camera
var ready_for_play := false
var started := false
## Input mode 0 keyboard + pad, 1 two pads, 2 both couriers on one keyboard.
var input_mode_index := 0
var split_screen := true
var _owns_menu_pause := false
var _world_visible := true
var _reloading := false

func configure(owner_simulation: Node) -> void:
	simulation = owner_simulation
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_canvas = CanvasLayer.new()
	menu_canvas.layer = 30
	add_child(menu_canvas)
	main_menu = MainMenu.new()
	main_menu.actions = _main_actions()
	main_menu.live_world = true
	main_menu.play_note = "Two players · this screen"
	menu_canvas.add_child(main_menu)
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = Hud.new()
	hud.visible = false
	add_child(hud)
	menus = Menus.new()
	add_child(menus)
	menus.pause_changed.connect(_pause_changed)
	menus.back_to_main.connect(return_to_main)
	# The one pause menu (same as online): offline, so it stops the game.
	menus.pause_tree = true
	menus.restart_available = true
	menus.restart_requested.connect(_restart_delivery)
	menus.end_run_requested.connect(func() -> void:
		if level_flow != null: level_flow.finish_run())
	# Boot still needs two physics frames and its initial reset.
	_finish_boot.call_deferred()

func _finish_boot() -> void:
	while is_instance_valid(simulation) and not simulation.is_network_ready():
		await get_tree().physics_frame
	if not is_instance_valid(simulation): return
	ready_for_play = true
	show_local_job()
	menus.configure_camera_settings(simulation.apply_camera_settings, PackedStringArray(["XSensitivity","YSensitivity","InvertX","InvertY"]))
	# The lobby yard is the title backdrop: keep it visible behind the menu
	# and let the title camera frame the couriers while the tree is paused.
	_world_visible = simulation.world.visible
	simulation.set_local_input_enabled(false)
	if simulation.camera != null:
		title_camera = TitleCamera.new()
		add_child(title_camera)
		var spot_a: Vector3 = simulation.actors[0].global_position
		var spot_b: Vector3 = simulation.actors[1].global_position
		title_camera.configure(simulation.camera, spot_a, spot_b, WalkInLobby.ORIGIN + Vector3(0.0, 0.0, -6.0))
		title_camera.set_view(main_menu.page)
		main_menu.view_changed.connect(title_camera.set_view)
	main_menu.reveal()
	get_tree().paused = true
	_owns_menu_pause = true
	_focus_local_play()
	print("GW_LOCAL_MENU_READY reset=",simulation.reset_count)
	if simulation.local_players == 1: start_job() # one player: no title, straight into the lobby yard (client/solo_entry.gd)

func _main_actions() -> Dictionary:
	return {"Play":_play,"Settings":_show_settings,"Quit":_quit}

## The one Play: the job a press of Play starts, with the controls the connected pads allow.
func _play() -> void:
	show_local_job()
	start_job()

## Picks the job Play starts (no form): controls from the pads.
## Harnesses call this, override _input_mode_selected(), then start_job().
func show_local_job() -> void:
	if is_instance_valid(simulation) and simulation.local_players == 1:
		_input_mode_selected(1) # the keyboard and the first pad both drive the one courier
		split_screen = false
		return
	var pads: int = simulation.connected_pads().size() if is_instance_valid(simulation) else 0
	_input_mode_selected(1 if pads >= 2 else (0 if pads == 1 else 2))
	if pads > 0: split_screen = true

func _input_mode_selected(index: int) -> void:
	input_mode_index = index
	if index == 2: split_screen = false

func start_job() -> void:
	if not ready_for_play or started: return
	simulation.configure_local_input_mode(input_mode_index)
	simulation.configure_local_split_screen(split_screen)
	started = true
	# Fade the last menu frame out over the camera cut into gameplay.
	var start_button: Button = main_menu.action_button("Play")
	Widgets.burst(self, start_button.get_global_rect().get_center() if start_button != null else Vector2(640, 360))
	if title_camera != null:
		title_camera.stop()
	main_menu.hide()
	main_menu.set_process(false)
	simulation.world.visible = _world_visible
	if _owns_menu_pause:
		get_tree().paused = false
		_owns_menu_pause = false
	var flow_script: Variant = get_tree().get_meta("gw_level_flow", null)
	if flow_script != null and CourseSection.has_levels():
		# The level game: PLAY leads into the lobby yard, the circles pick TIME ATTACK or ENDLESS.
		level_flow = flow_script.new()
		level_flow.name = "LevelFlow"
		add_child(level_flow)
		level_flow.configure(self, simulation)
		level_flow.start()
	else:
		simulation.playing = true
		simulation.set_local_input_enabled(true)
		hud.visible = true
	print("GW_LOCAL_START reset=",simulation.reset_count," controls=",input_mode_index," keyboard_test=",input_mode_index==2," split_screen=",split_screen)

func _focus_local_play() -> void:
	var play: Button = main_menu.action_button("Play")
	if play != null: play.grab_focus()

func _show_settings() -> void:
	menus.show_pause(false)

func _pause_changed(open: bool) -> void:
	if not started: main_menu.set_dimmed(open)
	if not ready_for_play: return
	# The game is stopped while the menu is open (menus.pause_tree): Start/Esc pressed to close it
	# are still queued as device edges; drop them so closing never reopens the menu.
	if not open and started: simulation.prime_local_input()
	simulation.set_local_input_enabled(started and not open)

func handle_gameplay_input(_event: InputEvent) -> bool:
	# Returning here skips only gameplay; the GUI still receives its input.
	return not started or menus.pause_open

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		toggle_options()
		get_viewport().set_input_as_handled()

func toggle_options() -> void:
	if menus.pause_open: menus.hide_pause()
	elif started:
		menus.end_run_available = level_flow != null and level_flow.in_run()
		menus.restart_available = level_flow == null or level_flow.minigame_id == "" # a minigame round (the show) is never restarted from the pause menu
		menus.show_pause(true)

func _restart_delivery() -> void:
	if started and is_instance_valid(simulation): simulation.restart_delivery()

func _process(_delta: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(_delta)
	_DevLap.lap("local_presentation.p", _lap)

func _process_timed(_delta: float) -> void:
	if not ready_for_play or not started: return
	var state: Dictionary = simulation.hud_state()
	state["match"] = {"time_left": -1.0, "run": level_flow.run_state() if level_flow != null else {}}
	hud.simulation = simulation
	hud.update_from_state(state)

func return_to_main() -> void:
	if _reloading: return
	_reloading = true
	get_tree().paused = false
	_owns_menu_pause = false
	reload_requested.emit()
	var error := get_tree().reload_current_scene()
	if error != OK: push_error("Cannot leave local play: "+str(error))

func _quit() -> void:
	get_tree().paused = false
	get_tree().quit()

func _exit_tree() -> void:
	if _owns_menu_pause: get_tree().paused = false

func probe() -> Dictionary:
	return {"ready":ready_for_play,"started":started,"menu_page":main_menu.page,"menu_visible":main_menu.visible,"settings_open":menus.pause_open,"input_mode":input_mode_index,"split_screen":split_screen,"tree_paused":get_tree().paused,"hud":hud.probe()}
