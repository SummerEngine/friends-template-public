extends SceneTree
## The authority side of the simulation shell without a transport (headless): the shell built rigless, owner poses accepted
## and refused, a scripted round (lobby walk-in -> two levels cleared by walking poses into the goal -> End run -> results ->
## lobby), a kill and its respawn, the players' looks (the look command, the match state, the snapshot size with 10 seats) and
## every published snapshot packed and unpacked. Poses are scripted fixtures, not bots.
## Run (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/core_shell_check.gd
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Look := preload("res://character/look.gd")
const LookRelay := preload("res://network/look_relay.gd")

class Controller extends "res://network/match_controller.gd":
	var inbox := {} ## seat -> pose sent this tick
	var documents: Array = []
	var concluded := ""
	func _apply_owner_poses() -> void:
		for seat: int in inbox.keys():
			var pose: Dictionary = inbox[seat]
			inbox.erase(seat)
			var slot := _slot(seat)
			fresh_at[seat] = elapsed
			owner_expired.erase(seat)
			var accepted := {}
			if slot >= 0 and simulation.queue_authority_owner_pose(slot, pose): accepted = pose
			_note_owner_input(seat, {"seq": 1}, accepted)
	func snapshot_state(full: bool) -> Dictionary:
		var state: Dictionary = simulation.capture_network_state(full or baseline_burst > 0)
		state = Game.with_match_mode(state, match_queue)
		state.baseline = full or baseline_burst > 0
		state.players_joined = joined.size()
		state.server_elapsed = elapsed
		state.owner_grants = [1, 1]
		state.input_sequences = input_sequences.duplicate()
		state.waiting_for_partner = waiting_for_partner
		state.settlement_state = settlement_state
		state.match = _match_state()
		return state
	func _publish() -> void:
		if baseline_burst > 0: baseline_burst -= 1
		var document := Game.pack_snapshot(snapshot_state(false))
		if not document.is_empty(): documents.append(document)
		if documents.size() > 400: documents.pop_front()
	func _conclude_world(_success: bool, reason: String) -> void: concluded = reason
	func _reset_owner_streams() -> void: pass

var failures := 0
var controller: Controller
var sim: Node
var sequence := [0, 0]
var sequence_epoch := [0, 0]

## The look command as the clients send it (through the command wire), what the match state publishes and what it costs.
func check_looks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bytes: PackedByteArray = Look.new().randomized(rng).to_bytes()
	var hex := bytes.hex_encode()
	var sent := func(seat: int, value: Variant) -> bool: return bool(controller.execute_command(seat, Game.unpack(Game.pack({"c": "look", "v": value})), "").ok)
	check(sent.call(0, hex), "a joined seat's look is accepted (%d bytes)" % bytes.size())
	var wrong_colour := bytes.duplicate()
	wrong_colour[2] = 250
	var refused := [hex.substr(2), "zz" + hex.substr(2), 7, wrong_colour.hex_encode(), (bytes + PackedByteArray([0])).hex_encode()].filter(func(v) -> bool: return not sent.call(1, v))
	check(refused.size() == 5 and not sent.call(5, hex), "bad looks and looks of seats that did not join are refused")
	var state := controller._match_state()
	check(state.look_revs[0] > 0 and int(state.look_revs[1]) == 0 and state.looks[0] == bytes and (state.looks[1] as PackedByteArray).is_empty(), "the match state publishes the look and its revision")
	var trip := Game.unpack_snapshot(Game.pack_snapshot(controller.snapshot_state(true)))
	check(not trip.is_empty() and trip.match.looks[0] == bytes and trip.match.look_revs == state.look_revs, "looks survive the snapshot wire")
	var first_rev := int(state.look_revs[0])
	check(sent.call(0, hex) and int(controller._match_state().look_revs[0]) == first_rev, "the same look again keeps its revision")
	# ten seats, every one with a look, in a baseline snapshot: still far under the cap
	var relay := LookRelay.new()
	for seat in 10: relay.store(seat, Look.new().randomized(rng).to_bytes().hex_encode())
	var full := controller.snapshot_state(true)
	var without: int = Game.pack_snapshot(full).b.size()
	full.match = (full.match as Dictionary).duplicate()
	relay.publish(full.match, 10, true)
	var with_looks: int = Game.pack_snapshot(full).b.size()
	check(with_looks < 32768 and with_looks - without < 1500, "snapshot with 10 seats' looks: %d bytes (%d without)" % [with_looks, without])
	# the bytes ride only for a burst after a change; the revisions always
	for i in LookRelay.BURST + 1: controller._match_state()
	var quiet := controller._match_state()
	check(quiet.has("look_revs") and (not quiet.has("looks") or controller.baseline_burst > 0), "looks leave the snapshot after the burst")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("CORE_CHECK FAIL ", label)
	else: print("CORE_CHECK ok   ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func pose(slot: int, position: Vector3, yaw := 0.0, epoch := -1, forced_seq := -1) -> Dictionary:
	var number: int = sim.reset_count if epoch < 0 else epoch
	if sequence_epoch[slot] != number:
		sequence_epoch[slot] = number
		sequence[slot] = 0
	sequence[slot] += 1
	var seq: int = sequence[slot] if forced_seq < 0 else forced_seq
	return {"version": OwnerPoseWire.VERSION, "seq": seq, "reset_epoch": number, "local_tick": seq, "time": float(seq) / 60.0,
		"transform": Transform3D(Basis(Vector3.UP, yaw), position), "velocity": Vector3.ZERO, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": yaw, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

## Both owners send one pose per tick, stepping toward `targets` by at most `step` metres.
func walk_to(targets: Array, step := 8.0) -> void:
	for i in 400:
		var done := true
		for slot in 2:
			var here: Vector3 = sim.actors[slot].position
			var toward: Vector3 = targets[slot] - here
			if toward.length() > 0.01: done = false
			var next: Vector3 = targets[slot] if toward.length() <= step else here + toward.normalized() * step
			controller.inbox[slot] = pose(slot, next)
		await physics_frame
		await physics_frame # the pose is applied by the shell one tick after the controller queued it
		if done: return

## The replica side of the same loop, in one process: a second shell with role "replica" is fed the unpacked snapshots, its owner
## courier is stepped by CourierMotion and its pose goes through encode/decode into the authority's inbox, as client/main.gd does.
var replica: Node
var owner_courier: RefCounted
var owner_sequence := 0
var carried_baseline := {}
const IDENTITY := {"world_id": "w", "session_id": "s", "entity_id": 1, "lifetime_revision": 1}

func latest_state() -> Dictionary:
	if controller.documents.is_empty(): return {}
	var state := Game.unpack_snapshot(controller.documents[-1])
	if state.is_empty(): return {}
	if int(carried_baseline.get("epoch", -1)) != int(state.resets): # the burst may have been published before this tick
		for index in range(controller.documents.size() - 1, -1, -1):
			var earlier := Game.unpack_snapshot(controller.documents[index])
			if earlier.is_empty() or not earlier.get("baseline", false) or int(earlier.resets) != int(state.resets): continue
			var movements := []
			for player: Dictionary in earlier.players: movements.append(player.get("movement", {}))
			carried_baseline = {"epoch": earlier.resets, "players": movements}
			break
	if int(carried_baseline.get("epoch", -1)) == int(state.resets):
		for slot in state.players.size():
			if not state.players[slot].has("movement") and not state.players[slot].get("inactive", false) and (carried_baseline.players[slot] as Dictionary).has("yaw"):
				state.players[slot].movement = carried_baseline.players[slot]
	return state

## One physics tick of the loopback: the replica follows the newest snapshot, steps its owner and answers with a pose.
func replica_tick(command: Dictionary, partner_position: Vector3) -> void:
	var state := latest_state()
	if state.is_empty(): return
	replica.apply_network_state(state, 1.0 / 60.0)
	if replica.seed_baseline(state) and state.players[0].has("movement"):
		var epoch: int = state.resets
		var baseline := {"position": state.players[0].position, "yaw": state.players[0].movement.yaw}
		if owner_courier == null:
			owner_courier = load("res://network/owner_courier.gd").new()
			if not owner_courier.configure(replica, 0, IDENTITY, epoch, baseline): owner_courier = null
			else: replica.owner_courier = owner_courier
		elif epoch > owner_courier.reset_epoch: owner_courier.reset_from_authority(IDENTITY, epoch, baseline)
		if owner_courier != null: owner_courier.observe_shared(IDENTITY, state)
	if owner_courier != null:
		replica.owner_step(command, true, 1.0 / 60.0)
		if owner_courier.active:
			var own: Dictionary = owner_courier.capture_pose()
			owner_sequence += 1
			own["version"] = OwnerPoseWire.VERSION
			own["seq"] = owner_sequence
			own["time"] = float(Time.get_ticks_usec()) * .000001
			own["floor_normal"] = owner_courier.motion.floor_normal
			var decoded := OwnerPoseWire.decode(OwnerPoseWire.encode(own))
			if not decoded.is_empty(): controller.inbox[0] = decoded
	var partner := pose(1, partner_position)
	controller.inbox[1] = partner
	if owner_courier != null and owner_courier.configured: replica.apply_remote_pose(1, partner)

func loopback(mode: Dictionary) -> void:
	load("res://client/presentation_entry.gd").install() # the client's own bootstrap (lobby drawing), as client/main.gd does
	replica = load("res://game/game_run.gd").new()
	replica.name = "Replica"
	replica.network_role = "replica"
	replica.carrier_count = controller.seat_count
	root.add_child(replica)
	var deadline := Time.get_ticks_msec() + 60000
	while not replica.is_network_ready() and Time.get_ticks_msec() < deadline: await process_frame
	check(replica.is_network_ready(), "replica shell ready")
	check(replica.rigs.all(func(rig): return rig != null) and replica.camera != null and replica.audio != null, "replica has rigs, camera and audio")
	# lobby: the owner walks onto the ENDLESS pad with real movement, the partner (scripted) stands there
	var centre := WalkInLobby.center(CourseSection.CHALLENGE)
	var partner_spot := centre + Vector3(0.6, 0.02, 0.0)
	partner_spot.y = sim.actors[1].position.y
	var epoch_lobby: int = sim.reset_count
	for i in 600:
		var own_position: Vector3 = replica.actors[0].position
		var toward := Vector3(centre.x - 0.6 - own_position.x, 0.0, centre.z - own_position.z)
		var command := {"move": Vector2(toward.x, toward.z).normalized() if toward.length() > 0.25 else Vector2.ZERO}
		replica_tick(command, partner_spot)
		await physics_frame
		if controller.lobby_ready != "" and controller.play_course == "": controller.execute_command(0, {"c": "play"}, "") # PLAY on the shared pad
		if controller.phase == "round": break
	check(controller.phase == "round", "owner walked onto the pad, pressed PLAY and the round started (phase=%s)" % controller.phase)
	check(owner_courier != null and owner_courier.configured, "owner courier configured from the snapshot baseline")
	# round: the owner walks forward with real movement
	await frames(3)
	var start_level: int = sim.course_plan.level
	var begin: Dictionary = sim.level_world.start_pose(start_level)
	for i in 8:
		replica_tick({"move": Vector2.ZERO}, begin.b)
		await physics_frame
	check(replica.round_mode == "level" and replica.reset_count == sim.reset_count, "replica follows the round (epoch %d)" % replica.reset_count)
	check(replica.actors[0].position.distance_to(begin.a) < 0.5, "owner courier seeded at the level start (%s)" % str(replica.actors[0].position))
	var before: Vector3 = replica.actors[0].position
	for i in 45:
		replica_tick({"move": Vector2(0.0, -1.0)}, begin.b)
		await physics_frame
	var moved: float = replica.actors[0].position.distance_to(before)
	check(moved > 1.0, "owner courier moved %.2f m under its own physics" % moved)
	await frames(4)
	var accepted: Vector3 = sim.actors[0].position
	check(accepted.distance_to(replica.actors[0].position) < 1.0, "authority holds the owner's pose (%.2f m apart)" % accepted.distance_to(replica.actors[0].position))
	var painting_gap: float = (sim.painting.global_position as Vector3).distance_to(replica.painting.global_position)
	check(painting_gap < 1.0 and not replica.painting.broken, "replica painting follows the authority's (%.2f m apart)" % painting_gap)
	# a dash is the owner's own physics: the authority takes it like a walk (pose by pose) and every other replica reads it from the snapshot
	for i in 60: # standing still: the walk's momentum is gone
		replica_tick({"move": Vector2.ZERO}, begin.b)
		await physics_frame
	var dash_from: Vector3 = replica.actors[0].position
	var dash_seen: Vector3 = sim.actors[0].position
	var dash_peak := 0.0
	var authority_peak := 0.0
	owner_courier.dash_flop = true
	replica.dash_flop = true # the option's pose path (the show leaves it off: tools/dash_penalty_check.gd checks the default); the dash itself is the same
	owner_courier.dash_edge()
	for i in 24:
		replica_tick({"move": Vector2(0.0, -1.0)}, begin.b)
		await physics_frame
		dash_peak = maxf(dash_peak, Vector2(replica.actors[0].velocity.x, replica.actors[0].velocity.z).length())
		authority_peak = maxf(authority_peak, Vector2(sim.actors[0].velocity.x, sim.actors[0].velocity.z).length())
	await frames(4)
	var dashed: float = replica.actors[0].position.distance_to(dash_from)
	check(dash_peak >= 10.5 and dashed > 3.2, "the owner dashed under its own physics (peak %.1f m/s, %.2f m in 0.4 s)" % [dash_peak, dashed])
	check(authority_peak >= 10.5 and (sim.actors[0].position as Vector3).distance_to(dash_seen) > 3.0, "the authority accepted the dash like a walk (peak %.1f m/s, %.2f m)" % [authority_peak, (sim.actors[0].position as Vector3).distance_to(dash_seen)])
	var seen_state := latest_state()
	check(not seen_state.is_empty() and (seen_state.players[0].position as Vector3).distance_to(dash_seen) > 3.0, "the snapshot every other replica follows carries the dashed position (%.2f m from before)" % (seen_state.players[0].position as Vector3).distance_to(dash_seen))
	check(controller.level_run != null and replica.playing, "replica plays")
	# the landing flop is the option `dash_flop` (courier_motion.gd; off for the show): switched on above (the game run and the owner path read the same mode value), the owner pose carries
	# the time left (1/100 s, `flop`) and the authority keeps it for the others
	var flop_own := 0
	var flop_authority := 0
	for i in 70:
		replica_tick({"move": Vector2(1.0, 0.0)}, begin.b)
		await physics_frame
		flop_own = maxi(flop_own, int(owner_courier.capture_pose().flop))
		flop_authority = maxi(flop_authority, int((sim._owner_accepted.get(0, {}) as Dictionary).get("flop", 0)))
	await frames(4)
	check(flop_own >= 100 and flop_authority >= 90, "with dash_flop on the belly flop travels in the owner pose (own %d, authority %d, in 1/100 s)" % [flop_own, flop_authority])
	owner_courier.dash_flop = false
	replica.dash_flop = false
	# the show's podium: with hold_yaw set the owner's courier stands still facing that way (a walk and a dash do nothing, a jump stays in place);
	# (this carry round's partner pulls a courier that is far from it a little, 0.15 m here; a walk would be 8 m)
	replica.hold_yaw = PI
	for i in 120: # the dash's belly flop (courier_motion.gd FLOP_TIME) has to be over before a jump counts
		replica_tick({"move": Vector2.ZERO}, begin.b)
		await physics_frame
	var held_from: Vector3 = replica.actors[0].position
	var held_peak := held_from.y
	owner_courier.dash_edge()
	owner_courier.jump_edge()
	for i in 90:
		replica_tick({"move": Vector2(0.0, -1.0)}, begin.b)
		await physics_frame
		held_peak = maxf(held_peak, replica.actors[0].position.y)
	var held_to: Vector3 = replica.actors[0].position
	var held_gap := Vector2(held_to.x - held_from.x, held_to.z - held_from.z).length()
	var held_turn := absf(wrapf(float(replica.actors[0].rotation.y) - PI, -PI, PI))
	check(held_gap < 0.5 and held_turn < 0.01, "the held owner stays on its spot facing the camera (%.3f m off, %.3f rad turned)" % [held_gap, held_turn])
	check(held_peak > held_from.y + 0.3, "the held owner still jumps in place (%.2f m up)" % (held_peak - held_from.y))
	replica.hold_yaw = null
	# the partner falls out of the level: death, shards, then a new epoch
	var epoch_round: int = sim.reset_count
	var fall: Vector3 = begin.b
	for i in 12:
		fall += Vector3(0.0, -9.0, 0.0)
		replica_tick({"move": Vector2.ZERO}, fall)
		await physics_frame
		await physics_frame
		if sim.painting.broken: break
	for i in 6:
		replica_tick({"move": Vector2.ZERO}, fall)
		await physics_frame
	check(replica.painting.broken and replica.failure_kind == "death" and replica.death_ui_visible, "replica shows the death (kind=%s)" % replica.failure_kind)
	check(replica.shards.active, "replica plays the shards")
	var again := false
	for i in 600:
		replica_tick({"move": Vector2.ZERO}, begin.b)
		await physics_frame
		if replica.reset_count > epoch_round and not replica.painting.broken:
			again = true
			break
	check(again, "replica follows the respawn epoch (%d)" % replica.reset_count)
	for i in 10:
		replica_tick({"move": Vector2.ZERO}, begin.b)
		await physics_frame
	check(replica.actors[0].position.distance_to(begin.a) < 0.6, "owner courier back on the start after the respawn")

func wait_for(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call(): return true
		await physics_frame
	return predicate.call()

func _initialize() -> void:
	# the walk-in parts use the ENDLESS circle: a game shows one circle, the cast's run (TeamCast.run)
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["run"] = "endless"
	cast["mode"] = "carry" # the template's own cast plays the show; this check plays the carry rounds (the show: tools/modes/show_check.gd)
	TeamCast.override(cast)
	run.call_deferred()

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
	var deadline := Time.get_ticks_msec() + 60000
	while not sim.is_network_ready() and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready(), "authority shell ready")
	controller.simulation_ready = true
	controller._enter_lobby()
	await frames(5)
	# ---- rigless
	var visuals := 0
	var cameras := 0
	var stack: Array = [sim]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is VisualInstance3D: visuals += 1
		if node is Camera3D: cameras += 1
		stack.append_array(node.get_children())
	check(visuals == 0 and cameras == 0, "authority builds no visuals and no camera (visual nodes=%d cameras=%d)" % [visuals, cameras])
	check(sim.rigs.all(func(rig): return rig == null) and sim.camera == null and sim.audio == null, "no rigs, camera or audio on the authority")
	check(sim.level_world.level_count() >= 2, "levels loaded: %d" % sim.level_world.level_count())
	# ---- seats
	for seat in 2:
		var answer: Dictionary = controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1))
		check(bool(answer.ok), "seat %d joined" % seat)
	check_looks()
	# ---- pose validation in the lobby
	var base: Vector3 = sim.actors[0].position
	var lobby_epoch: int = sim.reset_count
	check(not sim.queue_authority_owner_pose(0, pose(0, base, 0.0, lobby_epoch + 1)), "pose of another epoch refused")
	check(sim.queue_authority_owner_pose(0, pose(0, base + Vector3(0.5, 0.0, 0.0), 0.0, lobby_epoch)), "fresh pose accepted")
	check(not sim.queue_authority_owner_pose(0, pose(0, base, 0.0, lobby_epoch, 1)), "stale sequence refused")
	check(not sim.queue_authority_owner_pose(0, pose(0, base + Vector3(40.0, 0.0, 0.0), 0.0, lobby_epoch)), "a 40 m jump refused")
	var detached := pose(0, base + Vector3(1.0, 0.0, 0.0), 0.0, lobby_epoch)
	detached.anchor = detached.anchor + Vector3(3.0, 0.0, 0.0)
	check(not sim.queue_authority_owner_pose(0, detached), "an anchor 3 m from its courier refused")
	await frames(3)
	check(sim.actors[0].position.distance_to(base + Vector3(0.5, 0.0, 0.0)) < 0.01, "accepted pose moved the carrier")
	# ---- walk-in: both on the ENDLESS pad -> countdown -> round
	var centre := WalkInLobby.center(CourseSection.CHALLENGE)
	var pad_at := [centre + Vector3(-0.6, 0.02, 0.0), centre + Vector3(0.6, 0.02, 0.0)]
	var started := false
	var waited := 0.0 ## seconds both stood on the pad without PLAY
	for i in 900:
		for slot in 2:
			var here: Vector3 = sim.actors[slot].position
			var toward: Vector3 = pad_at[slot] - here
			controller.inbox[slot] = pose(slot, pad_at[slot] if toward.length() < 8.0 else here + toward.normalized() * 8.0)
		await physics_frame
		if controller.lobby_ready != "": waited += 1.0 / 60.0
		if waited > WalkInLobby.COUNTDOWN + 1.0 and controller.play_course == "" and controller.phase == "lobby":
			check(controller.phase == "lobby" and controller.start_at < 0.0, "standing on the pad together does not start the round without PLAY")
			check(bool(controller.execute_command(1, {"c": "play"}, "").ok), "a player on the shared pad presses PLAY")
		if controller.phase == "round":
			started = true
			break
	check(started, "PLAY on the shared pad started the countdown and the round (phase=%s)" % controller.phase)
	check(sim.round_mode == "level" and sim.playing, "shell is in a level round")
	# ---- level 1: a kill, then the respawn
	var first_level: int = sim.course_plan.level
	var start: Dictionary = sim.level_world.start_pose(first_level)
	await walk_to([start.a, start.b])
	check(sim.actors[0].position.distance_to(start.a) < 0.3 and sim.actors[1].position.distance_to(start.b) < 0.3, "couriers stand on the level start")
	var epoch_before: int = sim.reset_count
	var fall: Vector3 = start.a
	for i in 8:
		fall += Vector3(0.0, -9.0, 0.0)
		controller.inbox[0] = pose(0, fall)
		controller.inbox[1] = pose(1, sim.actors[1].position)
		await frames(2)
		if sim.painting.broken: break
	check(sim.painting.broken and sim.failure_kind == "death" and sim.death_ui_visible, "falling out of the level breaks the painting (kind=%s)" % sim.failure_kind)
	check(sim.breaks == 1 and sim.breaks_by_slot.reduce(func(a, b): return a + b) == 1, "one break counted")
	var broke_ok: bool = await wait_for(func(): return sim.reset_count > epoch_before and not sim.painting.broken, 600)
	check(broke_ok, "everybody respawns after the break (epoch %d -> %d)" % [epoch_before, sim.reset_count])
	await frames(3)
	check(sim.actors[0].position.distance_to(start.a + Vector3.UP * 0.05) < 0.6, "respawn placed the carrier on the start")
	check(sim.level_world.clock < 0.5, "hazard clock restarted with the epoch (%.2f)" % sim.level_world.clock)
	# ---- a laser on a carrier (added beside the start, off every later walk): the painting breaks, like a fall
	var local_a: Vector3 = start.a - sim.level_world.level_origin(first_level)
	sim.level_world.add_hazard(first_level, {"k": "laser", "p": [local_a.x - 1.25, 0.0, local_a.z], "to": [0, 3, 0]})
	var epoch_zap: int = sim.reset_count
	await walk_to([start.a + Vector3(-1.25, 0.05, 0.0), sim.actors[1].position], 0.5)
	check(sim.failure_kind == "death" and sim.painting.hit_name == "zap" and sim.team.scorches[1] == 1, "a laser zaps a carrier: the painting breaks (hit=%s)" % sim.painting.hit_name)
	var zap_ok: bool = await wait_for(func(): return sim.reset_count > epoch_zap and not sim.painting.broken, 600)
	check(zap_ok, "everybody respawns after the zap")
	# ---- clear the level by walking into the goal, then the next level
	var cleared_levels := 0
	for round_index in 2:
		var level: int = sim.course_plan.level
		var goal: Dictionary = sim.level_world.goal_volume(level)
		var begin: Dictionary = sim.level_world.start_pose(level)
		var level_epoch: int = sim.reset_count
		var cleared_before: int = controller.level_run.cleared()
		await walk_to([begin.a, begin.b])
		sim.painting.age = -30.0 # keep the break grace: the straight walk ignores hazards, this checks the round flow
		await walk_to([goal.floor + Vector3(-0.5, 0.05, 0.0), goal.floor + Vector3(0.5, 0.05, 0.0)])
		var won: bool = await wait_for(func(): return controller.level_run.cleared() > cleared_before or controller.level_clearing or controller.phase == "results", 120)
		check(won, "level %d cleared (won=%s)" % [level + 1, sim.won])
		if not won: break
		cleared_levels += 1
		var advanced: bool = await wait_for(func(): return sim.reset_count > level_epoch and not sim.won, 400)
		check(advanced, "next level started (level index %d, epoch %d)" % [sim.course_plan.level, sim.reset_count])
	check(cleared_levels == 2, "two levels cleared in a row")
	check(controller.level_run.cleared() == 2, "the run counted two cleared levels (%d)" % controller.level_run.cleared())
	# ---- End run -> results -> lobby
	var ended: Dictionary = controller.execute_command(0, {"c": "end_run"}, "")
	check(bool(ended.ok) and controller.phase == "results", "End run leads to the results (phase=%s)" % controller.phase)
	check(controller.results_rows.size() == 2 and str(controller.results_headline) != "", "results rows: %s | %s" % [controller.results_headline, controller.results_sub])
	for seat in 2: controller.execute_command(seat, {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_for(func(): return controller.phase == "lobby", 30)
	check(back and sim.round_mode == "lobby", "both chose Play Again: back in the lobby")
	await loopback(mode)
	# ---- snapshot round trip over what was published
	var unpacked := 0
	var largest := 0
	var holding_seen := false
	var baseline_seen := false
	for document: Dictionary in controller.documents:
		var state := Game.unpack_snapshot(document)
		if state.is_empty(): continue
		unpacked += 1
		largest = maxi(largest, (document.b as PackedByteArray).size())
		if state.get("baseline", false): baseline_seen = true
		if state.holding is Array and state.holding.has(true): holding_seen = true
	check(unpacked == controller.documents.size() and unpacked > 50, "every published snapshot unpacked (%d)" % unpacked)
	check(largest < 2048, "largest snapshot %d bytes" % largest)
	check(holding_seen and baseline_seen, "holding flags rebuilt and a baseline seen")
	# a fresh capture in a level round compared field by field
	controller.restart_requested = false
	sim.set_course_plan(CourseSection.plan(CourseSection.ADVENTURE, 0))
	sim.configure_phase("level", [true, true])
	await frames(2)
	await walk_to([sim.level_world.start_pose(0).a, sim.level_world.start_pose(0).b])
	sim.level_world.advance(0.4)
	var state: Dictionary = controller.snapshot_state(true)
	var document := Game.pack_snapshot(state)
	var round_trip := Game.unpack_snapshot(document)
	check(not round_trip.is_empty(), "snapshot packs and unpacks")
	if not round_trip.is_empty():
		check(round_trip.resets == state.resets and round_trip.level == state.level and round_trip.playing == state.playing and round_trip.broken == state.broken, "scalar fields survive")
		check(absf(float(round_trip.hazard_t) - float(state.hazard_t)) < 0.01, "hazard clock survives (%.3f vs %.3f)" % [round_trip.hazard_t, state.hazard_t])
		check((round_trip.players[0].position as Vector3).distance_to(state.players[0].position) < 0.05, "player positions survive")
		check(absf(float(round_trip.players[1].movement.yaw) - float(state.players[1].yaw)) < 0.01, "baseline yaw survives")
		check((round_trip.painting as Transform3D).origin.distance_to((state.painting as Transform3D).origin) < 0.05, "painting transform survives")
		check(round_trip.holding.slice(0, 2) == [true, true] and not round_trip.holding.slice(2).has(true), "holding flags rebuilt: %s" % str(round_trip.holding))
		check(round_trip.match.phase == "lobby" or round_trip.match.phase == "round", "match block survives")
	print("CORE_CHECK failures=", failures)
	quit(1 if failures > 0 else 0)
