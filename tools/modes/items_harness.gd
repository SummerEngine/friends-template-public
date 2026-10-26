extends SceneTree
## The show's items through the real online flow, headless: an authority (the match controller and shell with scripted players, as tools/modes/show_check.gd has it) and two replica clients
## that follow its snapshots and draw the show's view and HUD (so the items' views run on the clients' side of the wire). A scenario script drives it:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/modes/items_harness.gd" -- --scenario=<id> [--shots=<dir>] [--show-level=31]
##   --pick=<circle id>  start the round of that lobby circle instead (e.g. r25, a tile round; the scenario checks of rounds without item boxes)
## (offscreen binary and `--shots`: the same, one scenario per run, frames of the replica that plays the VICTIM; one render at a time under the render lock, see docs/items.md "Checks").
## A scenario is `tools/modes/items/<id>_scenario.gd` (extends RefCounted, `func run(h) -> void`, awaits): it gets this harness as `h`:
##   h.sim, h.controller, h.rules()          the authority's shell, match controller and the show's rules (`h.rules().items` is modes/show/items/items.gd)
##   h.views[i], h.replicas[i], h.viewers[i]  replica i draws the view of slot viewers[i] (i = 0: slot 0, i = 1: slot 1); slot 2 is a third scripted racer
##   h.tick(n), h.wait_until(callable, ticks), h.check(ok, label), h.state()   the clock, and the show's state
##   h.hold(slot) / h.release(slot) / h.speed[slot]   the scripted racer stands still / runs again (m per tick along the route)
##   h.give(slot, id) -> true                 the authority hands `slot` the item (as if it had rolled it, roll over)
##   h.press_item(slot)                       the slot's player presses ITEM (the counter item_seq, as the client sends it)
##   h.press_grab(slot)                       the same for GRAB
##   h.progress(slot, metres)                 stands the scripted racer `metres` along the route
##   h.shoot(name)                            a frame of replica `h.shot_view` (only with --shots)
##   h.mark(label), h.focus()                 --measure=<csv>: the offscreen render loop stays on and every frame is written to the csv under the label set last (wall ms between two draws,
##                                            process / physics / harness ms, pipeline compiles of the frame, draw calls); h.focus() draws only the replica of --view
## Prints ITEMS_CHECK ok=<bool> last; exits 1 on a failure.
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const CourseSection := preload("res://course_section.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const SEATS := 3

class Controller extends "res://network/match_controller.gd":
	var inbox := {}
	var commands := {}
	var documents: Array = []
	func _apply_owner_poses() -> void:
		for seat: int in inbox.keys():
			var pose: Dictionary = inbox[seat]
			inbox.erase(seat)
			var slot := _slot(seat)
			fresh_at[seat] = elapsed
			owner_expired.erase(seat)
			var accepted := {}
			if slot >= 0 and simulation.queue_authority_owner_pose(slot, pose): accepted = pose
			var command: Dictionary = commands.get(seat, {"seq": 1, "move": [0.0, 0.0]})
			_note_owner_input(seat, command, accepted)
			if slot >= 0: simulation.set_player_input(slot, command)
	func _publish() -> void:
		if baseline_burst > 0: baseline_burst -= 1
		var state: Dictionary = simulation.capture_network_state(baseline_burst > 0)
		state = Game.with_match_mode(state, match_queue)
		state.baseline = baseline_burst > 0
		state.players_joined = joined.size()
		state.server_elapsed = elapsed
		state.input_sequences = input_sequences.duplicate()
		state.waiting_for_partner = waiting_for_partner
		state.settlement_state = settlement_state
		state.match = _match_state()
		var document := Game.pack_snapshot(state)
		if not document.is_empty(): documents.append(document)
		if documents.size() > 60: documents.pop_front()
	func _conclude_world(_success: bool, _reason: String) -> void: pass
	func _reset_owner_streams() -> void: pass

var failures := 0
var controller: Controller
var sim: Node
var replicas: Array = []
var views: Array = []
var huds: Array = []
var viewers: Array = []
var sequence: Array = []
var sequence_epoch: Array = []
var facing: Array = []
var targets: Array = []
var route_at: Array = [] ## per seat: index on the route
var warp := {} ## seat -> where it is being stood (progress): up to 10 m a tick
var held_still: Array = [] ## per seat: true while scripted to stand
var speed: Array = [0.13, 0.12, 0.11] ## m per tick along the route, per seat
var lobby_speed: Array = [0.08, 0.08, 0.08] ## m per tick a seat walks to its target in the lobby yard (0.08 = 4.8 m/s)
var shots := ""
var shot_view := 0
var cast_path := "" ## --cast=<file>: use that cast instead of the fixture
var scenario_id := ""
var pick_id := "" ## --pick=<circle id>: play that lobby circle's round (r25: a tile round) instead of THE SHOW's first round
var mirror_seq := 0
var replica_epoch := {}
var largest := 0
var events_seen: Array = [] ## [slot, banner words] every banner the viewers' item pills showed
var tandems: Array = [] ## per replica: the TANDEM view (modes/show/tandem/tandem_view.gd), fed `match.tandem` like the client does (tools/modes/items/tandem_scenario.gd)
var lobby_only := false ## `--scenario=<id>_lobby`: the run stays in the lobby yard (no race): the TANDEM's lobby scope
var film := false ## `--film`: a video take (the offscreen binary with --write-movie): every tick is shown, the remote couriers move with their velocity, `h.mark(label)` prints the frame it was called on (tools/modes/items/tandem_film_scenario.gd)
var stride := 3 ## physics ticks between two looks of the replicas at the authority's state (the 20 Hz of the snapshots; 1 in a film)
var step_dt := 0.05 ## the seconds of that look

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("ITEMS_CHECK ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	auto_accept_quit = false # another agent's "quit Summer" (a polite macOS quit request) would end this run mid-render with exit 0 and no frames; the harness quits on its own
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--scenario="): scenario_id = argument.trim_prefix("--scenario=")
		if argument.begins_with("--pick="): pick_id = argument.trim_prefix("--pick=")
		if argument.begins_with("--view="): shot_view = int(argument.trim_prefix("--view="))
		if argument.begins_with("--cast="): cast_path = argument.trim_prefix("--cast=")
		if argument.begins_with("--measure="): _start_measure(argument.trim_prefix("--measure="))
		if argument == "--film": film = true
	if shots != "": RenderingServer.render_loop_enabled = false
	lobby_only = scenario_id.ends_with("_lobby")
	if film:
		stride = 1
		step_dt = 1.0 / 60.0
	create_timer(280.0 if _csv == null and not film else 900.0).timeout.connect(func() -> void:
		print("ITEMS_CHECK FAIL timed out")
		print("ITEMS_CHECK ok=false")
		quit(1))
	main.call_deferred()

func rules():
	return controller.minigame

func state() -> Dictionary:
	return controller.minigame.state() if controller.minigame != null else {}

func pose(seat: int, position: Vector3, yaw := 0.0, velocity := Vector3.ZERO) -> Dictionary:
	var epoch: int = sim.reset_count
	if sequence_epoch[seat] != epoch:
		sequence_epoch[seat] = epoch
		sequence[seat] = 0
	sequence[seat] += 1
	return {"version": OwnerPoseWire.VERSION, "seq": sequence[seat], "reset_epoch": epoch, "local_tick": sequence[seat], "time": float(sequence[seat]) / 60.0,
		"transform": Transform3D(Basis(Vector3.UP, yaw), position), "velocity": velocity, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": yaw, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

func tick(count := 1) -> void:
	for i in count:
		for seat in SEATS:
			if not controller.joined.has(seat): continue
			var slot: int = controller._slot(seat)
			var here: Vector3 = sim.actors[slot].position if slot >= 0 else targets[seat]
			var next := drive(seat, slot, here)
			var step := Vector2(next.x - here.x, next.z - here.z)
			if step.length() > 0.01: facing[seat] = atan2(-step.x, -step.y)
			var velocity := Vector3(step.x, 0.0, step.y) * 60.0
			controller.inbox[seat] = pose(seat, next, float(facing[seat]), velocity)
		await physics_frame
		if controller.phase == "round" and controller.minigame != null:
			var began := Time.get_ticks_usec()
			observe()
			_observe_us += Time.get_ticks_usec() - began
		elif lobby_only and controller.phase == "lobby": observe_lobby()
		if shots != "": capture_pending()

func wait_until(predicate: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if predicate.call(): return true
		await tick()
	return predicate.call()

func latest_state() -> Dictionary:
	if controller.documents.is_empty(): return {}
	var document: Dictionary = controller.documents[-1]
	largest = maxi(largest, (document.b as PackedByteArray).size())
	return Game.unpack_snapshot(document)

func hold(slot: int) -> void:
	held_still[slot] = true

func release(slot: int) -> void:
	held_still[slot] = false

func progress(slot: int, metres: float) -> void:
	var route: PackedVector3Array = sim.level_world.route(int(state().level))
	var index := 0
	var run := 0.0
	while index < route.size() - 1 and run < metres:
		run += route[index].distance_to(route[index + 1])
		index += 1
	route_at[slot] = index
	var seat := -1
	for candidate in SEATS:
		if controller._slot(candidate) == slot: seat = candidate
	warp[seat] = route[index] + Vector3.UP * 0.05

## The racer the seat scripts: the route at its own speed, or standing.
func drive(seat: int, slot: int, here: Vector3) -> Vector3:
	var rules_now = controller.minigame
	if slot < 0 or controller.phase != "round" or rules_now == null:
		var toward: Vector3 = targets[seat] - here
		var pace: float = float(lobby_speed[seat])
		return targets[seat] if toward.length() <= pace else here + toward.normalized() * pace
	if warp.has(seat):
		var at: Vector3 = warp[seat]
		var gap := at - here
		if gap.length() <= 10.0: warp.erase(seat)
		return at if gap.length() <= 10.0 else here + gap.normalized() * 10.0 # the authority takes poses up to 12 m apart
	var st: Dictionary = rules_now.state()
	if str(st.phase) != "play" or bool(held_still[seat]): return here
	var route: PackedVector3Array = sim.level_world.route(int(st.level))
	if route.is_empty(): return here
	var idx: int = clampi(int(route_at[seat]), 0, route.size() - 1)
	var target: Vector3 = route[idx]
	var offset := target - here
	if offset.length() < 0.35 and idx < route.size() - 1:
		idx += 1
		route_at[seat] = idx
		target = route[idx]
		offset = target - here
	return here + offset.normalized() * minf(float(speed[seat]), offset.length()) if offset.length() > 0.001 else here

func give(slot: int, id: String) -> bool:
	var items = rules().items
	if items == null or not items.enabled: return false
	var kind: int = items.Catalog.index(id)
	if kind < 0: return false
	items.held[slot] = kind
	items.roll_left[slot] = 0.0
	return true

func press_item(slot: int) -> void:
	_press(slot, "item_seq")

## The slot's player presses the item lab key `number` (1-7): the counter test_seq (seq * 8 + number).
func press_lab(slot: int, number: int) -> void:
	for candidate in SEATS:
		if controller._slot(candidate) == slot:
			var command: Dictionary = controller.commands[candidate]
			command["test_seq"] = ((int(command.get("test_seq", 0)) >> 3) + 1) << 3 | number
			command["seq"] = int(command.seq) + 1
			return

func press_grab(slot: int) -> void:
	_press(slot, "grab_seq")

func _press(slot: int, key: String) -> void:
	var seat := -1
	for candidate in SEATS:
		if controller._slot(candidate) == slot: seat = candidate
	var command: Dictionary = controller.commands[seat]
	command[key] = int(command.get(key, 0)) + 1
	controller.commands[seat] = command

# ------------------------------------------------------------------ what the clients see

func observe() -> void:
	if Engine.get_physics_frames() % stride == 0: mirror()
	if Engine.get_physics_frames() % stride != 0: return
	var fresh := latest_state()
	var info: Dictionary = fresh.get("match", {})
	for index in replicas.size():
		var replica: Node = replicas[index]
		replica.apply_network_state(fresh, step_dt)
		if index < tandems.size(): (tandems[index] as Node).present(info.get("tandem", {}) if info.get("tandem", {}) is Dictionary else {}, step_dt)
		var minigame: Variant = info.get("minigame", {})
		if not minigame is Dictionary or (minigame as Dictionary).is_empty(): continue
		var view: Node3D = views[index]
		view.present(minigame, step_dt)
		var model: Dictionary = view.hud(minigame)
		(huds[index] as Node).show_model(model if shots == "" or index == shot_view else {})

## The replicas stand where the authority's couriers are (the client's relay does this online).
func mirror() -> void:
	var fresh := latest_state()
	if fresh.is_empty(): return
	for replica: Node in replicas:
		var key := replica.get_instance_id()
		if bool(fresh.get("baseline", false)) and int(fresh.get("resets", -1)) != int(replica_epoch.get(key, -2)):
			if replica.seed_baseline(fresh): replica_epoch[key] = int(fresh.resets)
		for slot in maxi(controller.round_roster.size(), controller.joined.size()):
			var body: CharacterBody3D = sim.actors[slot]
			mirror_seq += 1
			var remote := pose(0, body.position, body.rotation.y, body.velocity if film else Vector3.ZERO)
			remote.seq = mirror_seq
			remote.reset_epoch = int(replica.get("_baseline_epoch"))
			replica.apply_remote_pose(slot, remote)

var shoot_after := 0
var shoot_name := ""

func shoot(name: String) -> void:
	if shots == "" or shot_view >= replicas.size(): return
	focus()
	shoot_after = 4
	shoot_name = name

## Only the replica of `shot_view` is drawn: its HUD, item layers, world, sun and camera (every replica draws into this one window and stands in one physical space).
func focus() -> void:
	if shot_view >= replicas.size(): return
	for other in replicas.size():
		if huds[other] != null: (huds[other] as Node).visible = other == shot_view
	for other in replicas.size(): # the TANDEM's banner layer draws into this one window too
		if other < tandems.size(): ((tandems[other] as Node).get("_layer") as CanvasLayer).visible = other == shot_view
	for other in replicas.size(): # every replica's item layers (wobble, pills, banners) draw into this one window: only the played view's show
		var pigeons: Variant = views[other].get("_pigeons") if views[other] != null else null # GHOST PIGEON's own layers (the splat, the COO / DROP buttons)
		if pigeons != null: pigeons.show_layers(other == shot_view)
		var manager: Variant = views[other].get("_items") if views[other] != null else null
		if manager == null: continue
		for layer: CanvasLayer in [manager.post_layer, manager.over_layer, manager.top_layer]: layer.visible = other == shot_view
	for other in replicas.size(): # the replicas stand in one physical space: only the played one's world (rigs, effects, boxes) is drawn
		var other_world: Variant = replicas[other].get("world")
		if other_world is Node3D: (other_world as Node3D).visible = other == shot_view
	for child in root.get_children():
		var sun: Node = child.get_node_or_null("World/LevelSun")
		if sun is Light3D: (sun as Light3D).visible = child == replicas[shot_view]
	(replicas[shot_view].get("camera") as Camera3D).make_current()

# ------------------------------------------------------------------ frame times (--measure)

var _frame_last := 0
var _observe_us := 0
var _mark := ""
var _csv: FileAccess

## Tags the frames from now on with `label` (a row per frame in the csv).
func mark(label: String) -> void:
	_mark = label
	if film: print("FILM mark ", label, " frame ", Engine.get_process_frames(), " physics ", Engine.get_physics_frames())
	if _csv != null: _csv.flush()

func _start_measure(path: String) -> void:
	_csv = FileAccess.open(path, FileAccess.WRITE)
	_csv.store_line("label,frame_ms,process_ms,physics_ms,observe_ms,pipelines,draw_calls,video_mb")
	RenderingServer.frame_post_draw.connect(_frame_drawn)

func _pipelines() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))

func _frame_drawn() -> void:
	var now := Time.get_ticks_usec()
	if _frame_last > 0 and _mark != "":
		_csv.store_line("%s,%.2f,%.2f,%.2f,%.2f,%d,%d,%.1f" % [_mark, (now - _frame_last) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			_observe_us / 1000.0, _pipelines(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_frame_last = now
	_observe_us = 0

func capture_pending() -> void:
	if shoot_after <= 0: return
	shoot_after -= 1
	if shoot_after > 0: return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("ITEMS_CHECK shot ", shoot_name, " ", image.save_png("%s/%s.png" % [shots, shoot_name]) == OK)

# ------------------------------------------------------------------ the run

func main() -> void:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	controller = Controller.new()
	controller.match_queue = Game.DEFAULT_QUEUE
	controller.match_mode = mode
	controller.seat_count = int(mode.seat_count)
	controller.input_sequences.resize(controller.seat_count)
	controller.input_sequences.fill(0)
	sim = load("res://game/game_run.gd").new()
	sim.name = "Simulation"
	sim.network_role = "authority"
	sim.carrier_count = controller.seat_count
	controller.simulation = sim
	root.add_child(controller)
	controller.add_child(sim)
	load("res://client/presentation_entry.gd").install()
	fixture_cast()
	var shells := []
	for index in 2:
		var replica: Node = load("res://game/game_run.gd").new()
		replica.name = "Replica%d" % index
		replica.network_role = "replica"
		replica.carrier_count = controller.seat_count
		root.add_child(replica)
		shells.append(replica)
	var deadline := Time.get_ticks_msec() + 120000
	while not (sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready())) and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready()), "authority and two replica shells ready")
	controller.simulation_ready = true
	controller._enter_lobby()
	for seat in SEATS:
		sequence.append(0)
		sequence_epoch.append(-1)
		facing.append(0.0)
		route_at.append(0)
		held_still.append(false)
		controller.commands[seat] = {"seq": 1, "move": [0.0, 0.0], "jump_seq": 0, "grab_seq": 0, "item_seq": 0}
		targets.append(sim.actors[seat].position)
	var started := (await begin_lobby(shells)) if lobby_only else (await begin_race(shells))
	if started and scenario_id != "":
		var path := ProjectSettings.globalize_path("res://").path_join("../tools/modes/items/%s_scenario.gd" % scenario_id)
		var script: GDScript = null
		if FileAccess.file_exists(path):
			script = load(path) as GDScript # an absolute path outside res:// loads too
		check(script != null, "scenario %s found" % scenario_id)
		if script != null: await (script as GDScript).new().run(self)
	print("ITEMS_CHECK largest snapshot ", largest, " B")
	check(largest <= 32768, "every snapshot fits the 32 KB transport (largest %d B)" % largest)
	TeamCast.override({})
	print("ITEMS_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)

func fixture_cast() -> void:
	if cast_path != "": # --cast=<cast.json>: that team's cast (its items, words, brand; the three racers keep the fixture names), the way the shipped game reads demo/cast/
		var cast: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cast_path))
		cast["players"] = [{"name": "Maya", "color": "#ff5a36"}, {"name": "Theo", "color": "#2c4bff"}, {"name": "Ida", "color": "#2ec27e"}]
		TeamCast.override(cast)
		return
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Items Check"}, "mode": "show",
		"players": [{"name": "Maya", "color": "#ff5a36"}, {"name": "Theo", "color": "#2c4bff"}, {"name": "Ida", "color": "#2ec27e"}]})

func begin_race(shells: Array) -> bool:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	for seat in SEATS: check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)
	var wanted := pick_id if pick_id != "" else WalkInLobby.shown_course() # --pick=r25: a lobby circle of one round (a tile round, say) instead of THE SHOW's first, a race
	var centre := WalkInLobby.center(wanted)
	var offsets := [Vector3(-0.6, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, -0.6)]
	for seat in SEATS: targets[seat] = centre + offsets[seat] + Vector3(0.0, sim.actors[controller._slot(seat)].position.y - centre.y, 0.0)
	var expect_kind: String = str(RoundList.entry(pick_id).get("kind", "race")) if pick_id != "" else "race"
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready == wanted, 60 * 30)
	if not ready: return false
	controller.execute_command(0, {"c": "play"}, "")
	var started: bool = await wait_until(func() -> bool: return controller.phase == "round", 60 * 10)
	check(started and controller.minigame_id == "show" and sim.play_mode == "show", "the show starts")
	if not started: return false
	mark("card") # --measure: the frames of the round's card (the items' dress rehearsal runs here)
	await tick(8)
	var info: Dictionary = latest_state().get("match", {})
	var slots := []
	for seat: Variant in info.get("slots", []):
		if int(seat) < 0: break
		slots.append(int(seat))
	attach_view(shells[0], 0, slots)
	attach_view(shells[1], 1, slots)
	var st := state()
	check(str(st.kind) == expect_kind, "round 1 is a %s (level %d)" % [expect_kind, int(st.level) + 1])
	var racing: bool = await wait_until(func() -> bool: return str(state().phase) == "play", 60 * 12)
	check(racing, "the round is on")
	if expect_kind != "race": return racing # a tile round has no item boxes
	check(state().has("items"), "the race has item boxes (state.items)")
	var egg = rules().items.rules_of.get("eggplant") if state().has("items") else null
	if egg != null and scenario_id != "eggplant": egg._next_at = 1.0e9 # HOT EGGPLANT (the experiment) has a scenario of its own; the others test their item alone
	return racing and state().has("items")

func attach_view(replica: Node, slot: int, seats: Array) -> void:
	var view: Node3D = ModeViews.new_view("show")
	replica.world.add_child(view)
	view.setup(replica, seats, slot)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	replica.set_local_seat(slot)
	replicas.append(replica)
	views.append(view)
	huds.append(hud)
	viewers.append(slot)
	attach_tandem(replica, slot, seats)

## The TANDEM's look on a replica, as client/main.gd builds it (`match.tandem` is fed in observe()).
func attach_tandem(replica: Node, slot: int, seats: Array) -> void:
	var look = load("res://modes/show/tandem/tandem_view.gd").new()
	replica.world.add_child(look)
	look.setup(replica, slot, seats)
	tandems.append(look)

## The lobby yard only (`--scenario=<id>_lobby`): everybody joins, the replicas follow the authority and draw the TANDEM's look; no round starts.
func begin_lobby(shells: Array) -> bool:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	for seat in SEATS: check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)
	await tick(20)
	var seats := [0, 1, 2]
	for index in 2:
		var replica: Node = shells[index]
		replica.set_local_seat(index)
		replicas.append(replica)
		views.append(null)
		huds.append(null)
		viewers.append(index)
		attach_tandem(replica, index, seats)
	await tick(20)
	check(controller.phase == "lobby", "the run is in the lobby yard")
	return controller.phase == "lobby"

func observe_lobby() -> void:
	if Engine.get_physics_frames() % stride == 0: mirror()
	if Engine.get_physics_frames() % stride != 0: return
	var fresh := latest_state()
	var info: Dictionary = fresh.get("match", {})
	for index in replicas.size():
		(replicas[index] as Node).apply_network_state(fresh, step_dt)
		if index < tandems.size(): (tandems[index] as Node).present(info.get("tandem", {}) if info.get("tandem", {}) is Dictionary else {}, step_dt)
