extends SceneTree
## Every minigame through the real online flow (docs/modes.md), headless, without a transport: the authority's match controller
## and shell with four scripted players, and a replica that follows its snapshots and draws the mode's view and HUD as
## client/main.gd does. For each mode: the lobby circle shows the mode, the four walk onto it, PLAY, the round starts as a minigame
## (the shell stays in its yard phase), match.minigame rides in the snapshots and the view presents it, the scripted players walk
## about for a while, the pause menu's End run ends it, the results come from the mode's rules, Play Again brings everybody back to
## the lobby. Then friend_swap with two players: the round does not start (it needs three).
## Run (never windowed):
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 900 -- <Summer> --headless \
##     --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s "$PWD/tools/modes/mode_round_check.gd"
## Prints MODE_ROUND ok=<bool> last; exits 1 on a failure.
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const PLAYERS := 4
const PLAY_SECONDS := 20.0

class Controller extends "res://network/match_controller.gd":
	var inbox := {} ## seat -> pose sent this tick
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
var replica: Node
var targets: Array = []
var sequence: Array = []
var sequence_epoch: Array = []
var largest := 0

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("MODE_ROUND ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		print("MODE_ROUND FAIL timed out")
		print("MODE_ROUND ok=false")
		quit(1))
	run.call_deferred()

func pose(seat: int, position: Vector3) -> Dictionary:
	var epoch: int = sim.reset_count
	if sequence_epoch[seat] != epoch:
		sequence_epoch[seat] = epoch
		sequence[seat] = 0
	sequence[seat] += 1
	return {"version": OwnerPoseWire.VERSION, "seq": sequence[seat], "reset_epoch": epoch, "local_tick": sequence[seat], "time": float(sequence[seat]) / 60.0,
		"transform": Transform3D(Basis.IDENTITY, position), "velocity": Vector3.ZERO, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": 0.0, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

func tick(count := 1) -> void:
	for i in count:
		for seat in PLAYERS:
			if not controller.joined.has(seat): continue
			var slot := controller._slot(seat)
			var here: Vector3 = sim.actors[slot].position if slot >= 0 else targets[seat]
			var toward: Vector3 = targets[seat] - here
			var next: Vector3 = targets[seat] if toward.length() <= 0.08 else here + toward.normalized() * 0.08
			controller.inbox[seat] = pose(seat, next)
		await physics_frame

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

func run() -> void:
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
	replica = load("res://game/game_run.gd").new()
	replica.name = "Replica"
	replica.network_role = "replica"
	replica.carrier_count = controller.seat_count
	root.add_child(replica)
	var deadline := Time.get_ticks_msec() + 120000
	while not (sim.is_network_ready() and replica.is_network_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready() and replica.is_network_ready(), "authority and replica shells ready")
	controller.simulation_ready = true
	controller._enter_lobby()
	for seat in PLAYERS:
		sequence.append(0)
		sequence_epoch.append(-1)
		controller.commands[seat] = {"seq": 1, "move": [0.0, 0.0], "jump_seq": 0, "grab_seq": 0}
		check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)
		targets.append(sim.actors[seat].position)
	for id: String in Modes.ids().filter(func(m: String) -> bool: return Modes.is_minigame(m) and m != "show"): # the show has its own check (show_check.gd)
		await play_mode_round(id, PLAYERS)
	await too_few_for_friend_swap()
	TeamCast.override({})
	print("MODE_ROUND largest snapshot ", largest, " B")
	check(largest <= 32768, "every snapshot fits the 32 KB transport (largest %d B)" % largest)
	print("MODE_ROUND ok=", failures == 0)
	quit(1 if failures > 0 else 0)

func use_cast(id: String) -> void:
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Round Check"}, "mode": id,
		"players": [{"name": "Maya", "catchphrase": "Ship it!", "emote": "dance"}, {"name": "Theo", "catchphrase": "On my way!"},
			{"name": "Ida", "catchphrase": "Coffee first"}, {"name": "Noor", "catchphrase": "Quick one?"}],
		"obstacles": [{"label": "FLAKY CI"}, {"label": "CHAT PINGS"}], "eggs": ["Someone always says it's a quick one"]})

## The four walk onto the one circle and one presses PLAY; true once the round runs.
func walk_in(seats: Array) -> bool:
	var centre := WalkInLobby.center(WalkInLobby.shown_course())
	var offsets := [Vector3(-0.6, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, -0.6), Vector3(0.0, 0.0, 0.6)]
	for seat: int in seats: targets[seat] = centre + offsets[seat] + Vector3(0.0, sim.actors[controller._slot(seat)].position.y - centre.y, 0.0)
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready != "", 60 * 20)
	if not ready: return false
	controller.execute_command(int(seats[0]), {"c": "play"}, "")
	return await wait_until(func() -> bool: return controller.phase == "round", 60 * 10)

func play_mode_round(id: String, count: int) -> void:
	use_cast(id)
	var pads := WalkInLobby.shown_pads()
	check(pads.size() == 1 and str(pads[0].title) == str(Modes.info(id).title), "%s: the lobby circle shows the mode" % id)
	var started := await walk_in(range(count))
	check(started and controller.round_mode == "minigame" and controller.minigame_id == id and sim.round_mode == "lobby", "%s: the round starts as a minigame in the yard" % id)
	if not started: return
	await tick(6) # a snapshot or two of the round
	var state := latest_state()
	var info: Dictionary = state.get("match", {})
	check(str(info.get("minigame_id", "")) == id and info.get("minigame") is Dictionary, "%s: match.minigame rides in the snapshot" % id)
	var seats := []
	for seat: Variant in info.get("slots", []):
		if int(seat) < 0: break
		seats.append(int(seat))
	var view: Node3D = ModeViews.new_view(id)
	replica.world.add_child(view)
	view.setup(replica, seats, 1)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	var hud_models := 0
	for step in int(PLAY_SECONDS * 60.0):
		if step % 90 == 0:
			for seat in count: targets[seat] = WalkInLobby.ORIGIN + Vector3(randf_range(-5.0, 5.0), sim.actors[controller._slot(seat)].position.y - WalkInLobby.ORIGIN.y, randf_range(-4.0, 6.0))
		await tick()
		if step % 6 == 0:
			var fresh := latest_state()
			replica.apply_network_state(fresh, 0.1)
			var minigame: Variant = (fresh.get("match", {}) as Dictionary).get("minigame", {})
			if minigame is Dictionary:
				view.present(minigame, 0.1)
				var model: Dictionary = view.hud(minigame)
				hud.show_model(model)
				if not model.is_empty(): hud_models += 1
		if controller.phase != "round": break
	print("MODE_ROUND ", id, " hud models ", hud_models, " phase ", controller.phase)
	check(is_instance_valid(view), "%s: the view presented %d s of snapshots" % [id, int(PLAY_SECONDS)])
	if controller.phase == "round": check(bool(controller.execute_command(0, {"c": "end_run"}, "").ok), "%s: End run ends the round" % id)
	await tick(3)
	var results: Dictionary = latest_state().get("match", {})
	check(controller.phase == "results" and str(results.get("headline", "")) != "" and (results.get("rows", []) as Array).size() == count, "%s: results from the mode: %s / %s" % [id, results.get("headline", ""), results.get("sub", "")])
	view.queue_free()
	hud.queue_free()
	for seat in count: controller.execute_command(seat, {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_until(func() -> bool: return controller.phase == "lobby", 60 * 5)
	check(back and controller.minigame == null, "%s: Play Again: the lobby again" % id)

## Two players on friend_swap (min 3): the countdown runs out and no round starts.
func too_few_for_friend_swap() -> void:
	use_cast("friend_swap")
	for seat in [2, 3]: controller._leave_seat(seat, "check")
	await tick(5)
	var centre := WalkInLobby.center(WalkInLobby.shown_course())
	targets[0] = centre + Vector3(-0.6, sim.actors[controller._slot(0)].position.y - centre.y, 0.0)
	targets[1] = centre + Vector3(0.6, sim.actors[controller._slot(1)].position.y - centre.y, 0.0)
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready != "", 60 * 20)
	controller.execute_command(0, {"c": "play"}, "")
	await tick(int(60 * (WalkInLobby.COUNTDOWN + 1.5)))
	check(ready and controller.phase == "lobby", "friend_swap with two players does not start (needs %d)" % Modes.min_players("friend_swap"))
