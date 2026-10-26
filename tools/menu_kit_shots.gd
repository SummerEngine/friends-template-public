extends SceneTree
## Frames of every non-gameplay screen of the show build, one boot, no window: the title, Settings (every tab), the pause menu in the lobby yard, the customizer (wardrobe), the loading, error and notice
## pages, the lobby HUD and the results pages (a points show of three, a show of six, a clear time in a show for one, a level run). Used for the menu kit's before / after sheets (docs/comic-ui.md "Menu kit").
## Prints MENU_KIT_SHOTS lines. Offscreen binary only, never windowed; the phone is `--resolution 844x390` with `--touch`:
##   lockf -k ~/.local/state/friends-slots/render.lock <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/menu_kit_shots.gd" -- --out=<dir> [--prefix=d_] [--only=title,pause,results_show] [--touch] [--credit] [--brand=#rrggbb]
## `--credit` gives the cast a credit link (the results' watermark shows only with one); `--brand=` gives it that first brand colour (the primary, the backdrop and the logo follow).
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []

const LobbySpace := preload("res://lobby_space.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const Wardrobe := preload("res://character/wardrobe/wardrobe.gd")
const TeamCast := preload("res://style/team_cast.gd")
const OnlineScreens := preload("res://client/online_screens.gd")

var out := ""
var prefix := ""
var only: PackedStringArray = []
var credit := false
var brand := ""
var game: Node
var ui: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--prefix="): prefix = a.trim_prefix("--prefix=")
		elif a.begins_with("--only="): only = a.trim_prefix("--only=").split(",", false)
		elif a == "--credit": credit = true
		elif a.begins_with("--brand="): brand = a.trim_prefix("--brand=")
	run.call_deferred()

func wants(name: String) -> bool:
	return only.is_empty() or only.has(name)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func capture(name: String) -> void:
	if out == "": return
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("MENU_KIT_SHOTS shot ", name, " ", image.save_png("%s/%s%s.png" % [out, prefix, name]) == OK)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

## The cast with a credit link and / or a brand colour on top of the template's own.
func _dress_cast() -> void:
	if not credit and brand == "": return
	var cast: Dictionary = TeamCast.data().duplicate(true)
	var team: Dictionary = (cast.get("team", {}) as Dictionary).duplicate()
	if credit: team["credit_link"] = "https://www.summerengine.com"
	if team.get("name", "") == "": team["name"] = "SUMMER ENGINE"
	cast["team"] = team
	if brand != "": cast["brand"] = {"colors": [brand]}
	TeamCast.override(cast)

func run() -> void:
	_dress_cast()
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	game = VirtualLocal.new()
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 240000
	while not game.is_network_ready() or game.local_presentation == null or not game.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("MENU_KIT_SHOTS boot_timeout")
			quit(2)
			return
	ui = game.local_presentation
	await frames(120)
	if wants("title"): capture("title")
	if wants("settings"):
		ui.menus.show_pause(false)
		for tab in ui.menus.TABS.size():
			ui.menus._select_tab(tab)
			await frames(40)
			capture("settings_" + str(ui.menus.TABS[tab]).to_lower())
		ui.menus.hide_pause()
		await frames(10)
	# The lobby yard: pause, the customizer
	ui.show_local_job()
	ui._input_mode_selected(2)
	await process_frame
	ui.start_job()
	await frames(120)
	if wants("pause"):
		ui.menus.end_run_available = false
		ui.menus.show_pause(true)
		await frames(40)
		capture("pause")
		ui.menus.hide_pause()
		await frames(10)
	if wants("wardrobe"): await _wardrobe()
	# The pages of the online screens, over their own backdrops
	var screens: Control = OnlineScreens.new()
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	layer.add_child(screens)
	if wants("loading"):
		screens.show_loading("Finding a game", "Waiting for the others", true, 0.45, 1)
		await frames(90)
		capture("loading")
	if wants("error"):
		screens.show_error("Connection lost", "The server stopped answering. Check your network and try again.")
		await frames(60)
		capture("error")
	if wants("notice"):
		screens.show_notice("YOU LEFT", "Back to the lobby", "Nothing went wrong: you left the match.")
		await frames(60)
		capture("notice")
	if wants("lobby_hud"):
		screens.show_lobby(_lobby_model())
		await frames(60)
		capture("lobby_hud")
	if wants("results_show"):
		screens.show_results(_results(3, "MARCUS TAKES THE CROWN", "SHIP IT  ·  VEL 5  MARCUS 7  TIM 3", [5, 7, 3], false))
		await frames(260)
		capture("results_show")
	if wants("results_six"):
		screens.hide_all()
		screens.show_results(_results(6, "MIKO TAKES THE CROWN", "SHIP IT", [0, 1, 2, 9, 4, 6], false))
		await frames(260)
		capture("results_six")
	if wants("results_solo"):
		screens.hide_all()
		screens.show_results(_results(1, "SHIP IT CLEARED", "42.3 S", [0], true))
		await frames(260)
		capture("results_solo")
	if wants("results_run"):
		screens.hide_all()
		var model := _results(2, "RUN COMPLETE", "5 LEVELS  ·  4:12.8", [0, 0], true)
		model["run"] = {"finished": true, "times": [51.2, 48.7, 60.1, 44.0, 49.0]}
		screens.show_results(model)
		await frames(260)
		capture("results_run")
	quit(0)

func _lobby_model() -> Dictionary:
	var members := []
	for seat in 3:
		members.append({"seat": seat, "name": TeamCast.player_name(seat), "zone": "", "on_pad": seat == 1, "me": seat == 0, "color": TeamCast.player_color(seat)})
	return {"seat_count": 6, "joined": 3, "solo": false, "hint": "Waiting for MARCUS", "start_in": -1.0, "pick": "", "pick_title": "", "ready_pad": "", "can_play": false, "input": "keyboard",
		"members": members, "lamps": members, "pads": []}

## A results model: `count` players, their points as `breaks` (the match controller's row for a scored mode), `rank` best first by points (1-based).
func _results(count: int, headline: String, sub: String, points: Array, arrived: bool) -> Dictionary:
	var order := range(count)
	order.sort_custom(func(a: int, b: int) -> bool: return int(points[a]) > int(points[b]) or (int(points[a]) == int(points[b]) and a < b))
	var rows := []
	for seat in count:
		rows.append({"seat": seat, "name": TeamCast.player_name(seat), "color": TeamCast.player_color(seat), "me": seat == 0, "time": 42.3 if arrived else -1.0, "panes_intact": -1,
			"breaks": int(points[seat]), "arrived": arrived, "choice": "pending", "rank": order.find(seat) + 1, "points": int(points[seat])})
	return {"round": 1, "headline": headline, "sub": sub, "choose_in": 12.0, "remaining": count, "rows": rows, "course": "", "reason": "", "time_limit": -1.0, "run": {}}

func _wardrobe() -> void:
	var room: Node3D = game.world.get_node_or_null(LobbySpace.NAME)
	var booth: Node3D = room.get_node_or_null("Wardrobe") if room != null else null
	if booth == null:
		print("MENU_KIT_SHOTS skipped wardrobe (no booth)")
		return
	game.motions[0].teleport(game.actors[0], Layout.ORIGIN + Layout.wardrobe_center() + Vector3(0.0, 0.05, 0.0))
	await frames(12)
	key(KEY_E)
	await frames(60)
	capture("wardrobe")
	key(KEY_ESCAPE)
	await frames(30)
