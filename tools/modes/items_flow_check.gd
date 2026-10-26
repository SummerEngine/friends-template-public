extends SceneTree
## The show's items through the REAL local flow (not the harness of tools/modes/items_harness.gd): the app's own entry (client/solo_entry.gd for one player, client/presentation_entry.gd
## for two), the lobby, the lobby circle of a round (or THE SHOW's), PLAY, the card, the play phase with the show's real view and HUD. Asserts what a player sees:
##   * the round has item boxes (the authority's `items.enabled`, the boxes' mask in the state), the view builds them (a '?' cube on a pedestal in the tree, visible),
##   * the item pill is drawn (the HUD slot has a rect: the pill is on the screen) and, with the item lab on, the hint pill `1-7: TEST ITEMS`,
##   * no objective text: the show's HUD model has no `quest` and nothing is drawn top left but the pills,
##   * a runner who walks into a box takes an item (alone: a boost or soar), ITEM (E) uses it, and the lab key 7 makes an event happen (soar) through the real key path.
## `--players=1` (default: the solo app) or `--players=2`; `--pick=r30` (default: race 30, FERRY CROSSING) or `--show` (THE SHOW: its first round, a race; asserts the boxes of whatever level it drew);
## `--lab=0` the cast without the lab (default: the lab on, as the Summer cast has it); `--frames=<dir>` frames of the play phase (the offscreen binary, one render at a time under the render lock).
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/modes/items_flow_check.gd" -- [--players=2] [--pick=r31 | --show] [--lab=0] [--frames=<dir>]
## Prints ITEMS_FLOW lines and ITEMS_FLOW ok=<bool>; exits 1 on a failure.
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []
class SoloLocal extends "res://client/solo_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const TeamCast := preload("res://style/team_cast.gd")

var players := 1
var pick := "r30"
var show_run := false
var lab := true
var route_shots := false ## --route: only frames of the runner's own view along the route (the sky decor must never hang in the course or the camera's play space)
var goal_shot := false ## --goal: only frames of the finish pad (the floor decal) from several camera angles
var shots := ""
var failures := 0
var sim: Node
var flow: Node

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("ITEMS_FLOW ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--players="): players = clampi(int(argument.trim_prefix("--players=")), 1, 2)
		if argument.begins_with("--pick="): pick = argument.trim_prefix("--pick=")
		if argument == "--show": show_run = true
		if argument == "--goal": goal_shot = true
		if argument == "--route": route_shots = true
		if argument.begins_with("--lab="): lab = argument.trim_prefix("--lab=") != "0"
		if argument.begins_with("--frames="): shots = argument.trim_prefix("--frames=")
	if shots != "": RenderingServer.render_loop_enabled = false
	create_timer(280.0).timeout.connect(func() -> void:
		print("ITEMS_FLOW FAIL timed out")
		print("ITEMS_FLOW ok=false")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func capture(label: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("ITEMS_FLOW shot ", label, " ", image.save_png("%s/%s.png" % [shots, label]) == OK)

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)

func state() -> Dictionary:
	return flow.minigame.state() if flow.minigame != null else {}

func items():
	return flow.minigame.items

## Frames of the runner's own view at points along the route (the runner stood there, looking the way the route goes).
func route_frames(level: int) -> void:
	var route: PackedVector3Array = sim.level_world.route(level)
	var length := 0.0
	for index in route.size() - 1: length += route[index].distance_to(route[index + 1])
	var shot := 0
	for share in [0.12, 0.28, 0.42, 0.55, 0.7, 0.86]:
		var walked := 0.0
		var at := 0
		while at < route.size() - 2 and walked + route[at].distance_to(route[at + 1]) < length * share:
			walked += route[at].distance_to(route[at + 1])
			at += 1
		var ahead: Vector3 = route[mini(at + 3, route.size() - 1)] - route[at]
		sim.actors[0].global_position = route[at] + Vector3(0.0, 0.3, 0.0)
		sim.yaw = atan2(-ahead.x, -ahead.z)
		sim.pitch = deg_to_rad(-12.0)
		await frames(30)
		capture("route_L%d_%d" % [level + 1, shot])
		shot += 1

## Frames of the finish pad's floor decal (`floor_finish`) from a free camera of the script's (current while it shoots) at several angles and heights; the runner stays at the start.
func goal_frames(level: int) -> void:
	var entry: Dictionary = sim.level_world._levels[level]
	var spot := Vector3.ZERO
	for slot: Dictionary in entry.data.slots:
		if str(slot.id) == "floor_finish": spot = (slot.p as Vector3) + (entry.origin as Vector3)
	print("ITEMS_FLOW finish decal of level %d at %s" % [level + 1, str(spot)])
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.05
	sim.add_child(camera)
	var angle := 0
	for view in [[0.0, 85.0, 6.0], [0.0, 40.0, 7.0], [90.0, 25.0, 7.0], [180.0, 45.0, 7.0], [270.0, 15.0, 7.0], [200.0, 60.0, 6.0]]: # [compass degrees, elevation degrees, metres away]
		var around := deg_to_rad(float(view[0]))
		var up := deg_to_rad(float(view[1]))
		var eye := spot + Vector3(sin(around) * cos(up), sin(up), cos(around) * cos(up)) * float(view[2])
		camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(spot + Vector3(0.0, 0.1, 0.0), Vector3.UP if view[1] < 80.0 else Vector3(0.0, 0.0, -1.0))
		camera.make_current()
		await frames(12)
		camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(spot + Vector3(0.0, 0.1, 0.0), Vector3.UP if view[1] < 80.0 else Vector3(0.0, 0.0, -1.0))
		camera.make_current()
		capture("goal_L%d_%d" % [level + 1, angle])
		angle += 1
	camera.queue_free()

func run() -> void:
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["mode"] = "show"
	var section: Dictionary = (cast.get("show", {}) as Dictionary).duplicate(true) if cast.get("show") is Dictionary else {}
	section["item_lab"] = lab # the Summer cast has it on; the template's cast says nothing
	cast["show"] = section
	TeamCast.override(cast)
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	sim = SoloLocal.new() if players == 1 else VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("ITEMS_FLOW boot_timeout")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for taught in ["move", "jump", "tilt", "lift"]: hud_script.taught[taught] = true
	var ui = sim.local_presentation
	if players == 1: check(ui.started and sim.local_players == 1, "the solo app starts by itself: one player, no title page")
	else:
		ui.show_local_job()
		ui._input_mode_selected(2)
		await process_frame
		ui.start_job()
	await frames(150)
	flow = ui.level_flow
	var shown: Array = WalkInLobby.shown_pads()
	var circle := str(shown[0].course) if show_run else pick
	check(show_run or not RoundList.entry(pick).is_empty(), "the lobby has the circle %s" % circle)
	var centre := WalkInLobby.center(circle)
	if players == 1: sim.actors[0].position = centre + Vector3(0.0, 0.3, 0.0)
	else:
		sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
		sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	await frames(30)
	flow.press_play()
	var started := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - started < 20000: await frames(5)
	check(flow.phase == "round" and flow.minigame != null and flow.minigame_id == "show", "PLAY starts the show (%s)" % flow.phase)
	if flow.minigame == null:
		quit(1)
		return
	var guard := 0
	while (str(state().get("phase", "")) != "play" or float(state().get("t", 0.0)) < 1.5) and guard < 60 * 40:
		await physics_frame
		guard += 1
	var st := state()
	var level := int(st.get("level", -1))
	var rules = flow.minigame
	var boxes: PackedVector3Array = rules.host.item_boxes(level)
	print("ITEMS_FLOW round %s level %d (%d players, lab %s): %d item boxes" % [str(st.get("kind", "")), level + 1, players, str(lab), boxes.size()])
	if route_shots:
		await route_frames(level)
		print("ITEMS_FLOW ok=true")
		quit(0)
		return
	if goal_shot:
		await goal_frames(level)
		print("ITEMS_FLOW ok=true")
		quit(0)
		return
	check(str(st.get("kind", "")) == "race", "the round is a race")
	check(boxes.size() >= 2, "level %d lists item boxes (%d)" % [level + 1, boxes.size()])
	check(items().enabled == (boxes.size() > 0), "the authority's items are on when the level has boxes (enabled %s)" % str(items().enabled))
	check(st.has("items") and int((st.items as Dictionary).get("boxes", 0)) != 0, "the show's state carries the items and their boxes")
	var mode_view = flow._mode_view
	var manager = mode_view._items
	await frames(5)
	var drawn := 0
	for box: Dictionary in manager._boxes:
		if is_instance_valid(box.node) and (box.node as Node).is_inside_tree() and bool(box.there): drawn += 1
	check(drawn == boxes.size() and drawn >= 2, "the view draws every box: a '?' cube on a pedestal in the scene (%d of %d)" % [drawn, boxes.size()])
	var pill: Rect2 = manager.hud._pill_rect
	check(pill.size.x > 0.0 and pill.position.x < 120.0 and pill.position.y < 120.0, "the item pill is on the screen top left (%s)" % str(pill))
	check(bool(manager.hud.model.get("lab", false)) == lab, "the lab hint %s" % ("shows" if lab else "is off"))
	var hud: Dictionary = mode_view.hud(state())
	check(not hud.has("quest") and not manager.hud.model.has("quest"), "no objective text in the show's HUD model (no quest)")
	# the lap to a box: stand the runner in front of the first box, looking at it
	var route: PackedVector3Array = sim.level_world.route(level)
	var first := boxes[0]
	var near := Vector3.ZERO
	var best := INF
	for point in route: # the route point nearest the first box that is still 2.5 m clear of every box (a runner standing in another box would take its item first)
		var gap := Vector2(point.x - first.x, point.z - first.z).length()
		var clear := true
		for spot: Vector3 in boxes:
			if Vector2(point.x - spot.x, point.z - spot.z).length() < 2.5: clear = false
		if gap < best and clear:
			best = gap
			near = point
	var look := first - near
	sim.actors[0].global_position = Vector3(near.x, near.y + 0.3, near.z)
	sim.yaw = atan2(-look.x, -look.z)
	sim.pitch = deg_to_rad(-14.0)
	await frames(40)
	capture("race_box_pill_hint")
	# walk into the box: the authority gives the item
	sim.actors[0].global_position = first + Vector3(0.0, 0.1, 0.0)
	await frames(8)
	check(int(items().held[0]) >= 0, "the runner who stands in a box takes an item (held %s)" % str(items().held[0]))
	check(int(state().items.boxes) & 1 == 0 and manager.hud.model.held >= 0, "the box is gone from the mask and the pill holds it (mask %d, pill %s, runner at %s)" % [int(state().items.boxes), str(manager.hud.model.held), str(sim.actors[0].global_position.snapped(Vector3.ONE * 0.1))])
	capture("item_taken")
	await frames(70)
	var held_id := str(items().Catalog.id_of(int(items().held[0]))) if int(items().held[0]) >= 0 else ""
	if players == 1: check(held_id == "boost" or held_id == "soar", "alone a box hands out a boost or a soar (%s)" % held_id)
	await key(KEY_G if players == 2 else KEY_E) # one keyboard for two: G is the first player's ITEM
	await frames(10)
	if players == 1: check(int(items().held[0]) == -1 and not items().fx.is_empty(), "ITEM (E) uses it on the runner: %d effect(s) now" % items().fx.size())
	else: check(int(items().held[0]) == -1, "ITEM used the item (held %s)" % str(items().held[0]))
	capture("item_used")
	if lab:
		items().fx.clear()
		await key(KEY_7)
		await frames(10)
		check(not items().fx_of(0, "soar").is_empty(), "the lab key 7 (soar) happens to the runner through the real key path")
		await key(KEY_3)
		await frames(10)
		check(int(items().held[0]) == items().Catalog.index("flip"), "the lab key 3 puts a FLIP in the slot")
		capture("lab_flip")
	print("ITEMS_FLOW ok=", failures == 0)
	quit(1 if failures > 0 else 0)
