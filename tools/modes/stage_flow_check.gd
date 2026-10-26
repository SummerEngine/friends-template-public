extends SceneTree
## A tile stage round (levels 25-28) through the real online flow with REAL owner couriers: the authority (match controller and shell, scripted lobby walk-in) and three replica
## shells whose own couriers run the real courier physics (courier_motion.gd in the stage feel) on their own copy of the level and send their poses to the authority, as client/main.gd does.
## Seat 3 is a scripted pose that stands. Two things are checked:
##   FREEZE  from the spawn to GO every player stands on its own start tiles. Seats 0 and 1 are honest clients (the show's view freezes their couriers) and hold FORWARD (and press jump and
##           dash) all through the card; seat 2 is a cheat: its client does not freeze (hold_start is forced off), holds forward and presses jump and dash, so its poses leave the spot and the
##           authority must drop them (host.hold) and put it back (rules.gd). Nobody may leave its spot by more than STAGE_HOLD on x/z or STAGE_RISE in height, on the authority or on its own
##           screen (the cheat's own courier is allowed to try); at GO seat 1 runs at once (input unlocks), the camera was free all along.
##   FALL    seat 0 stands still after GO: its start tile goes, it falls layer by layer onto the ground floor, is eliminated on landing (the authority decides: state.fell, status OUT), watches
##           the others (spectate), the ground under it is the solid floor (ray) and the authority retires it. With --shots frames of that (the victim's own view) are written.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/modes/stage_flow_check.gd" -- [--stage=0..3]            (0 square A, 1 hex A, 2 square B, 3 hex B)
##   frames (offscreen binary, under the render lock, one run per level): ... --summer-offscreen --resolution 1152x720 ... -- --stage=1 --shots=<dir> [--prefix=hex_]
## Prints STAGE_FLOW lines and `STAGE_FLOW ok=<bool>` last.
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const CourseSection := preload("res://course_section.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const RoundList := preload("res://modes/show/round_list.gd")
const SEATS := 4
const DT := 1.0 / 60.0
const IDENTITY := {"world_id": "w", "session_id": "s", "entity_id": 1, "lifetime_revision": 1}
const HONEST := 0 ## seat whose replica is the victim of the fall (it also holds forward in the card)
const RUNNER := 1
const CHEAT := 2

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
		if documents.size() > 120: documents.pop_front()
	func _conclude_world(_success: bool, _reason: String) -> void: pass
	func _reset_owner_streams() -> void: pass

var failures := 0
var controller: Controller
var sim: Node
var shells: Array = []
var views: Array = []
var huds: Array = []
var owners: Array = [null, null, null]
var owner_seq := [0, 0, 0]
var sequence := [0, 0, 0, 0]
var sequence_epoch := [-1, -1, -1, -1]
var targets: Array = []
var facing := [0.0, 0.0, 0.0, 0.0]
var carried := {}
var shots := ""
var trace := false
var prefix := ""
var stage_nth := 0
var tick_count := 0
var round_tick0 := 0
var in_round := false
var round_slots: Array = []
var start_at := {}      ## slot -> the authority's start spot
var worst_auth := {}    ## slot -> the largest x/z distance from its start spot the authority's courier got during the card
var worst_rise := {}    ## ... and in height
var worst_own := {}     ## the same for the replica's own courier
var strays_seen := 0
var go_tick := -1
var run_gain := 0.0
var fell_at_tick := -1
var land_y := NAN
var shoot_after := 0
var shoot_name := ""
var strip_done := {}

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_FLOW ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument == "--trace": trace = true
		if argument.begins_with("--stage="): stage_nth = int(argument.trim_prefix("--stage="))
	if shots != "": RenderingServer.render_loop_enabled = false
	create_timer(560.0).timeout.connect(func() -> void:
		print("STAGE_FLOW FAIL timed out")
		print("STAGE_FLOW ok=false")
		quit(1))
	run.call_deferred()

func pose(seat: int, position: Vector3, yaw := 0.0) -> Dictionary:
	var epoch: int = sim.reset_count
	if sequence_epoch[seat] != epoch:
		sequence_epoch[seat] = epoch
		sequence[seat] = 0
	sequence[seat] += 1
	return {"version": OwnerPoseWire.VERSION, "seq": sequence[seat], "reset_epoch": epoch, "local_tick": sequence[seat], "time": float(sequence[seat]) / 60.0,
		"transform": Transform3D(Basis(Vector3.UP, yaw), position), "velocity": Vector3.ZERO, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": yaw, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

func latest_state() -> Dictionary:
	if controller.documents.is_empty(): return {}
	var state := Game.unpack_snapshot(controller.documents[-1])
	if state.is_empty(): return {}
	if int(carried.get("epoch", -1)) != int(state.resets): # the burst may have been published before this tick: take the movements from it
		for index in range(controller.documents.size() - 1, -1, -1):
			var earlier := Game.unpack_snapshot(controller.documents[index])
			if earlier.is_empty() or not earlier.get("baseline", false) or int(earlier.resets) != int(state.resets): continue
			var movements := []
			for player: Dictionary in earlier.players: movements.append(player.get("movement", {}))
			carried = {"epoch": earlier.resets, "players": movements}
			break
	if int(carried.get("epoch", -1)) == int(state.resets):
		for slot in state.players.size():
			if not state.players[slot].has("movement") and not state.players[slot].get("inactive", false) and (carried.players[slot] as Dictionary).has("yaw"):
				state.players[slot].movement = carried.players[slot]
	return state

func rules_state() -> Dictionary:
	return controller.minigame.state() if controller.minigame != null else {}

## What the seat does this tick: honest and cheating seats hold forward (+Z on the arena) through the card; after GO the victim stands and the runner runs on.
func command_for(seat: int, st: Dictionary) -> Vector2:
	var phase := str(st.get("phase", ""))
	if phase == "card": return Vector2(0.0, 1.0)
	if seat == HONEST: return Vector2.ZERO
	return Vector2(0.0, 1.0) if seat == RUNNER else Vector2.ZERO

func replica_tick(seat: int, st: Dictionary) -> void:
	var slot: int = controller._slot(seat)
	var replica: Node = shells[seat]
	var state := latest_state()
	if state.is_empty() or slot < 0: return
	replica.apply_network_state(state, DT)
	if seat < views.size() and str(st.get("phase", "")) == "card": # the client applies a state to the view in the same frame
		var minigame: Variant = (state.get("match", {}) as Dictionary).get("minigame", {})
		if minigame is Dictionary and not (minigame as Dictionary).is_empty(): views[seat].present(minigame, DT)
	if replica.seed_baseline(state) and state.players[slot].has("movement"):
		var epoch := int(state.resets)
		var baseline := {"position": state.players[slot].position, "yaw": state.players[slot].movement.yaw}
		if owners[seat] == null:
			owners[seat] = load("res://network/owner_courier.gd").new()
			if not owners[seat].configure(replica, slot, IDENTITY, epoch, baseline): owners[seat] = null
			else: replica.owner_courier = owners[seat]
		elif epoch > owners[seat].reset_epoch: owners[seat].reset_from_authority(IDENTITY, epoch, baseline)
		if owners[seat] != null: owners[seat].observe_shared(IDENTITY, state)
	var own = owners[seat]
	if own == null or not own.configured: return
	var command := {"move": command_for(seat, st)}
	if str(st.get("phase", "")) == "card" and tick_count % 20 == 0: # the player mashes jump and dash
		own.jump_edge()
		own.dash_edge()
	if seat == CHEAT: replica.set("hold_start", false) # a client that does not freeze its courier
	replica.owner_step(command, true, DT)
	if own.active:
		var captured: Dictionary = own.capture_pose()
		owner_seq[seat] += 1
		captured["version"] = OwnerPoseWire.VERSION
		captured["seq"] = owner_seq[seat]
		captured["time"] = float(Time.get_ticks_usec()) * .000001
		captured["floor_normal"] = own.motion.floor_normal
		var decoded := OwnerPoseWire.decode(OwnerPoseWire.encode(captured))
		if not decoded.is_empty(): controller.inbox[seat] = decoded
	for other: int in round_slots: # the others as the client's relay draws them: where the authority has them
		if other == slot: continue
		var body: CharacterBody3D = sim.actors[other]
		var remote := pose(0, body.position, body.rotation.y)
		remote.seq = Engine.get_physics_frames() + other
		remote.reset_epoch = int(replica.get("_baseline_epoch"))
		replica.apply_remote_pose(other, remote)

## The authority and the three replicas share ONE physics space here (a real game has one per machine), so their copies of a courier would shove each other: every body but a replica's
## own courier is taken off the courier layer.
func separate_bodies() -> void:
	for slot in sim.actors.size(): (sim.actors[slot] as CharacterBody3D).collision_layer = 0
	for seat in 3:
		var own_slot: int = controller._slot(seat)
		for slot in shells[seat].actors.size():
			if slot != own_slot: (shells[seat].actors[slot] as CharacterBody3D).collision_layer = 0

func tick(count := 1) -> void:
	for i in count:
		tick_count += 1
		if in_round: separate_bodies()
		var st := rules_state()
		var round_on := controller.phase == "round" and controller.minigame != null and in_round
		for seat in SEATS:
			if not controller.joined.has(seat): continue
			var slot: int = controller._slot(seat)
			if round_on and seat < 3 and slot >= 0:
				replica_tick(seat, st)
				continue
			var here: Vector3 = sim.actors[slot].position if slot >= 0 else targets[seat]
			var next := here
			if not round_on:
				var toward: Vector3 = targets[seat] - here
				next = targets[seat] if toward.length() <= 0.08 else here + toward.normalized() * 0.08
			var step := Vector2(next.x - here.x, next.z - here.z)
			if step.length() > 0.01: facing[seat] = atan2(-step.x, -step.y)
			controller.inbox[seat] = pose(seat, next, float(facing[seat]))
		await physics_frame
		if round_on: observe()
		if shots != "": capture_pending()

func wait_until(predicate: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if predicate.call(): return true
		await tick()
	return predicate.call()

## The views' present() and HUD every third tick, the freeze measurements every tick.
func observe() -> void:
	var st := rules_state()
	if str(st.get("phase", "")) == "card": measure_card(st)
	if tick_count % 3 == 0:
		var fresh := latest_state()
		var info: Dictionary = fresh.get("match", {})
		var minigame: Variant = info.get("minigame", {})
		if minigame is Dictionary and not (minigame as Dictionary).is_empty():
			for seat in views.size():
				views[seat].present(minigame, 0.05)
				(huds[seat] as Node).show_model(views[seat].hud(minigame) if shots == "" or seat == HONEST else {})
	if shots != "": strip_frames(st)

func measure_card(st: Dictionary) -> void:
	if trace and (tick_count - round_tick0 < 40 or tick_count % 30 == 0):
		var s0: int = controller._slot(HONEST)
		print("STAGE_FLOW trace t %.2f auth %s own %s hold %s hs %s resp %d" % [float(st.t), sim.actors[s0].position, shells[HONEST].actors[s0].position, (controller.minigame._start_hold.get(s0, {}) as Dictionary).get("at"), str(shells[HONEST].hold_start), sim.team.respawns[s0]])
	for seat in 3:
		var slot: int = controller._slot(seat)
		if slot < 0 or not start_at.has(slot) or owners[seat] == null or not owners[seat].active or tick_count - round_tick0 < 12: continue # (until the owner's courier runs, the scripted lobby pose of the harness is still the authority's)
		var at: Vector3 = start_at[slot]
		var here: Vector3 = sim.actors[slot].position
		worst_auth[slot] = maxf(float(worst_auth.get(slot, 0.0)), Vector2(here.x - at.x, here.z - at.z).length())
		worst_rise[slot] = maxf(float(worst_rise.get(slot, 0.0)), absf(here.y - at.y))
		var mine: Vector3 = shells[seat].actors[slot].position
		worst_own[slot] = maxf(float(worst_own.get(slot, 0.0)), Vector2(mine.x - at.x, mine.z - at.z).length())

# ------------------------------------------------------------------ frames

## The strip: the victim's own view at the moments of its fall (heights over the ground, landing, the plate, the spectator view).
func strip_frames(st: Dictionary) -> void:
	var since := float(tick_count - fell_tick) / 60.0 if fell_tick >= 0 else 0.0
	if trace and strip_done.has("e_eliminated") and tick_count % 30 == 0: print("STAGE_FLOW trace strip phase ", st.get("phase"), " spectate ", shells[HONEST].get("spectate_slot"), " since ", since)
	if shoot_after > 0 or not str(st.get("phase", "")) in ["play", "done"]: return
	var slot: int = controller._slot(HONEST)
	var feet: float = shells[HONEST].actors[slot].position.y
	var ground := float(CourseSection.level_stage(int(st.level)).ground.y)
	var fell := (st.fell as Array).has(slot)
	var gap := 14.3
	var wanted := ""
	if strip_done.has("e_eliminated"):
		if not strip_done.has("f_spectating") and int(shells[HONEST].get("spectate_slot")) >= 0 and since >= 1.6: wanted = "f_spectating"
	elif not fell:
		if feet < ground + gap * 1.95 and feet > ground + gap * 1.3 and not strip_done.has("a_over_last_layer"): wanted = "a_over_last_layer"
		elif feet < ground + gap * 0.82 and not strip_done.has("b_falling_through"): wanted = "b_falling_through"
		elif feet < ground + gap * 0.38 and not strip_done.has("c_above_the_floor"): wanted = "c_above_the_floor"
	else:
		if not strip_done.has("d_landed") and since >= 0.0: wanted = "d_landed"
		elif not strip_done.has("e_eliminated") and since >= 0.3: wanted = "e_eliminated"
	if wanted == "": return
	strip_done[wanted] = true
	for other in views.size():
		(huds[other] as Node).visible = other == HONEST
		for layer_name: String in ["_plates", "_stage", "_wall"]:
			var layer: Variant = views[other].get(layer_name)
			if layer is CanvasLayer: (layer as CanvasLayer).visible = other == HONEST
	for other in shells.size():
		var other_world: Variant = shells[other].get("world")
		if other_world is Node3D: (other_world as Node3D).visible = other == HONEST
	for child in root.get_children():
		var sun: Node = child.get_node_or_null("World/LevelSun")
		if sun is Light3D: (sun as Light3D).visible = child == shells[HONEST]
	(shells[HONEST].get("camera") as Camera3D).make_current()
	shoot_after = 6
	shoot_name = wanted

var fell_tick := -1 ## the tick the authority put the victim out

func capture_pending() -> void:
	if shoot_after <= 0: return
	shoot_after -= 1
	if shoot_after > 0: return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("STAGE_FLOW shot ", shoot_name, " y ", snappedf(shells[HONEST].actors[controller._slot(HONEST)].position.y, 0.1), " ", image.save_png("%s/%s%s.png" % [shots, prefix, shoot_name]) == OK)

# ------------------------------------------------------------------ the run

func stage_row() -> Dictionary:
	var skip := stage_nth
	for row: Dictionary in RoundList.entries():
		if CourseSection.level_stage(int(row.levels[0])).is_empty(): continue
		if skip <= 0: return row
		skip -= 1
	return {}

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
	var list := []
	for index in SEATS: list.append({"name": "Player%d" % (index + 1), "color": ["#ff5a36", "#2c4bff", "#2ec27e", "#f2c230"][index]})
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Stage Flow"}, "players": list, "mode": "show"})
	for index in 3:
		var replica: Node = load("res://game/game_run.gd").new()
		replica.name = "Replica%d" % index
		replica.network_role = "replica"
		replica.carrier_count = controller.seat_count
		root.add_child(replica)
		shells.append(replica)
	var deadline := Time.get_ticks_msec() + 180000
	while not (sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready())) and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready()), "authority and three replica shells ready")
	controller.simulation_ready = true
	controller._enter_lobby()
	for seat in SEATS:
		controller.commands[seat] = {"seq": 1, "move": [0.0, 0.0], "jump_seq": 0, "grab_seq": 0}
		targets.append(sim.actors[seat].position)
	for seat in SEATS: check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)
	var row := stage_row()
	var course := str(row.id)
	var centre := WalkInLobby.center(course)
	var offsets := [Vector3(-0.6, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, -0.6), Vector3(0.0, 0.0, 0.6)]
	for seat in SEATS: targets[seat] = centre + offsets[seat] + Vector3(0.0, sim.actors[controller._slot(seat)].position.y - centre.y, 0.0)
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready == course, 60 * 30)
	check(ready, "the four stand on the circle of %s" % str(row.title))
	controller.execute_command(0, {"c": "play"}, "")
	var started: bool = await wait_until(func() -> bool: return controller.phase == "round", 60 * 10)
	check(started and sim.play_mode == "show" and sim.stage_round(), "a stage round starts")
	if not started:
		print("STAGE_FLOW ok=false")
		quit(1)
		return
	await tick(2)
	var info: Dictionary = latest_state().get("match", {})
	for seat: Variant in info.get("slots", []):
		if int(seat) < 0: break
		round_slots.append(int(seat))
	for seat in 3:
		var view: Node3D = ModeViews.new_view("show")
		shells[seat].world.add_child(view)
		view.setup(shells[seat], round_slots, controller._slot(seat))
		var hud = ModeHud.new()
		root.add_child(hud)
		hud.seats = round_slots
		shells[seat].set_local_seat(controller._slot(seat))
		views.append(view)
		huds.append(hud)
	in_round = true
	round_tick0 = tick_count
	var st := rules_state()
	check(str(st.phase) == "card" and bool(st.stage), "the round opens with its card")
	for slot: int in round_slots: start_at[slot] = (controller.minigame._start_hold[slot] as Dictionary).at if controller.minigame._start_hold.has(slot) else sim.actors[slot].position
	var level := int(st.level)
	var ground := float(CourseSection.level_stage(level).ground.y)
	# --- freeze: the whole card, everybody holding forward
	await wait_until(func() -> bool: return str(rules_state().phase) == "play", 60 * 8)
	for seat in 3:
		var slot: int = controller._slot(seat)
		var label := "seat %d (%s)" % [seat, "honest, victim" if seat == HONEST else ("honest, runs after GO" if seat == RUNNER else "cheat: no client freeze")]
		check(float(worst_auth.get(slot, 99.0)) <= ShowRules.STAGE_HOLD and float(worst_rise.get(slot, 99.0)) <= ShowRules.STAGE_RISE, "FREEZE %s: on the authority it never left its start tiles in the card (%.2f m on x/z, %.2f m in height; limits %.2f / %.2f)" % [label, float(worst_auth.get(slot, -1.0)), float(worst_rise.get(slot, -1.0)), ShowRules.STAGE_HOLD, ShowRules.STAGE_RISE])
		if seat == CHEAT:
			check(float(worst_own.get(slot, 0.0)) > 0.3, "FREEZE %s: its own courier did try to run (%.2f m from its spot at most), the authority put it back" % [label, float(worst_own.get(slot, 0.0))])
		else:
			check(float(worst_own.get(slot, 99.0)) < 0.1, "FREEZE %s: its own courier stood still on every screen (%.3f m)" % [label, float(worst_own.get(slot, -1.0))])
	check(float(worst_auth.get(controller._slot(HONEST), 99.0)) < 0.05 and float(worst_auth.get(controller._slot(RUNNER), 99.0)) < 0.05, "FREEZE the honest clients' poses never stray at all on the authority (%.3f / %.3f m)" % [float(worst_auth.get(controller._slot(HONEST), -1.0)), float(worst_auth.get(controller._slot(RUNNER), -1.0))])
	go_tick = tick_count
	# --- unlock: the runner (still holding forward) leaves its tiles at once
	var from: Vector3 = sim.actors[controller._slot(RUNNER)].position
	await tick(45)
	var gain: float = Vector2(sim.actors[controller._slot(RUNNER)].position.x - from.x, sim.actors[controller._slot(RUNNER)].position.z - from.z).length()
	check(gain > 4.0, "UNLOCK at GO the honest runner moves (%.1f m in 0.75 s)" % gain)
	var spot: Vector3 = sim.actors[controller._slot(HONEST)].position
	var origin_y := float(sim.level_world.level_origin(level).y)
	var probe := PhysicsRayQueryParameters3D.create(Vector3(spot.x, origin_y + ground + 1.0, spot.z), Vector3(spot.x, origin_y + ground - 1.0, spot.z), 1)
	var probed: Dictionary = root.world_3d.direct_space_state.intersect_ray(probe)
	check(not probed.is_empty() and absf(float((probed.position as Vector3).y) - origin_y - ground) < 0.01, "GROUND under the start pad a ray on the courier's world layer lands on the ground's top (%s)" % str(probed.get("position")))
	var motion_mask: int = shells[HONEST].actors[controller._slot(HONEST)].collision_mask
	print("STAGE_FLOW courier mask ", motion_mask, " ground bit ", motion_mask & 1)
	# --- the victim: stands, falls layer by layer to the ground, is out on landing, spectates
	var slot0: int = controller._slot(HONEST)
	var floor_hit := await wait_until(func() -> bool:
		if trace and shells[HONEST].actors[slot0].position.y < ground + 3.0: print("STAGE_FLOW trace fall y auth %.2f own %.2f vy %.1f" % [sim.actors[slot0].position.y, shells[HONEST].actors[slot0].position.y, shells[HONEST].actors[slot0].velocity.y])
		return (rules_state().fell as Array).has(slot0), 60 * 30)
	check(floor_hit, "FALL the standing player falls through every layer and the authority puts it out on the ground")
	st = rules_state()
	fell_tick = tick_count
	if trace:
		for k in 24:
			await tick()
			print("STAGE_FLOW trace after y own %.2f vy %.1f auth %.2f grounded %s" % [shells[HONEST].actors[slot0].position.y, shells[HONEST].actors[slot0].velocity.y, sim.actors[slot0].position.y, str(shells[HONEST].actors[slot0].is_on_floor())])
	var out_at: Vector3 = sim.actors[slot0].position
	land_y = out_at.y
	check(land_y <= ground + ShowRules.STAGE_LAND and land_y >= ground - 0.05, "FALL it is out standing on the ground slab (feet y %.2f, the ground's top %.2f)" % [land_y, ground])
	check(int((st.status as Array)[slot0]) == ShowRules.OUT, "FALL the status of the fallen is OUT")
	await tick(45 + 120)
	check(int(shells[HONEST].get("spectate_slot")) >= 0 and int(shells[HONEST].get("spectate_slot")) != slot0, "FALL after its fall shows the victim spectates somebody else (slot %d)" % int(shells[HONEST].get("spectate_slot")))
	check(not sim.is_slot_active(slot0), "FALL the authority retired the fallen courier")
	TeamCast.override({})
	print("STAGE_FLOW ok=", failures == 0)
	quit(1 if failures > 0 else 0)
