extends SceneTree
## A balloon round on the authority side of the shell without a transport (headless), four scripted players, and a replica that
## follows its snapshots. Poses and presses are scripted fixtures, not bots.
##   0. In the lobby yard a player grabs another one in front, the held one's client puts it above the holder, a second GRAB throws.
##      With nobody in reach GRAB picks up the loose box in front (in the snapshot, drawn in the holder's hands on the replica), GRAB
##      again throws it; a carrier who is grabbed drops what it carries.
##      Another player walks into the replica's own courier, which walks back into it, for 5 s: the own courier never leaps or leaves
##      the floor.
##   1. Four seats walk onto the TIME ATTACK pad: the round starts in balloon mode on a level that lists "balloon".
##   2. The team stands around the start pad; the balloon hangs over it until a player jumps into it.
##   3. Left alone it drifts down and pops: POP card, then a new epoch with the team and the balloon back at the start.
##   4. It passes a checkpoint (one is added to the level for this check): the next pop restarts the team there. At every
##      checkpoint of the real levels the team faces along the course (a step forward is progress along the level's path).
##   5. Contact: player 1 grabs player 2 and throws them (a kick for player 2), player 3 grabs player 4 who mashes JUMP free.
##   5b. GRAB next to the balloon with nobody in front slaps it: a stronger lift than a bump, a cooldown; with a free player in front it
##      still grabs; the replica swings the slapper's arm.
##   6. A player falls into the void: it alone respawns at the team's spot, the balloon is not popped.
##   7. Hazards that hurt (added to the level high over the checkpoint for this check): a laser zaps a player, who alone respawns
##      at the checkpoint ("ZAP!" on the replica), a fire jet burns one; a laser, a fire jet and the spike tips of a spike crusher pop
##      the balloon, while the same gap to a plain mover does not.
##   7b. A lift that rises into the hanging balloon throws it off: no pop, never inside the lift.
##   8. The balloon enters the goal: the level is cleared, the one-level run ends, the results show the time and the pops.
##   9. The replica draws the balloon where the authority has it, its owner courier (player 2) rides above its holder and
##      flies off with the throw.
## Run (never windowed):
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 600 -- <Summer> --headless \
##     --audio-driver Dummy --fixed-fps 60 --path demo -s "$PWD/tools/balloon_round_check.gd"
## Prints BALLOON_ROUND ok=<bool> and exits 0 only when all pass.
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const LevelData := preload("res://levels/level_data.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const PropSim := preload("res://players/prop_sim.gd")
const PLAYERS := 4
const OWNER := 1 ## the replica's own courier
const IDENTITY := {"world_id": "w", "session_id": "s", "entity_id": 2, "lifetime_revision": 1}

class Controller extends "res://network/match_controller.gd":
	var inbox := {} ## seat -> pose sent this tick
	var commands := {} ## seat -> the input this seat sends (move, press counters)
	var documents: Array = []
	## This check's poses and its added checkpoint fit ROOM 01 (plain floor at z -16): the run plays it alone, not the whole room run.
	func _new_level_run() -> RefCounted:
		return LevelRun.new(course, CourseSection.level_count(), -1, [CourseSection.rooms()[0]])
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
	func snapshot_state(full: bool) -> Dictionary:
		var state: Dictionary = simulation.capture_network_state(full or baseline_burst > 0)
		state = Game.with_match_mode(state, match_queue)
		state.baseline = full or baseline_burst > 0
		state.players_joined = joined.size()
		state.server_elapsed = elapsed
		state.input_sequences = input_sequences.duplicate()
		state.waiting_for_partner = waiting_for_partner
		state.settlement_state = settlement_state
		state.match = _match_state()
		return state
	func _publish() -> void:
		if baseline_burst > 0: baseline_burst -= 1
		var document := Game.pack_snapshot(snapshot_state(false))
		if not document.is_empty(): documents.append(document)
		if documents.size() > 200: documents.pop_front()
	func _conclude_world(_success: bool, _reason: String) -> void: pass
	func _reset_owner_streams() -> void: pass

var failures := 0
var controller: Controller
var sim: Node
var replica: Node
var owner_courier: RefCounted
var targets: Array = [] ## seat -> where its scripted pose walks to (feet)
var velocities: Array = [] ## seat -> the velocity its poses report
var sequence: Array = []
var sequence_epoch: Array = []
var largest := 0
var owner_move := Vector2.ZERO ## the replica's own courier walks this way (world x / z)
var bump_lift := 0.0 ## the balloon's upward speed right after the first bump (step 3)

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("BALLOON_ROUND ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	var cast: Dictionary = load("res://style/team_cast.gd").data().duplicate(true)
	cast["mode"] = "carry" # the template's own cast plays the show; this check plays the balloon rounds
	load("res://style/team_cast.gd").override(cast)
	run.call_deferred()

func pose(seat: int, position: Vector3, velocity := Vector3.ZERO) -> Dictionary:
	var epoch: int = sim.reset_count
	if sequence_epoch[seat] != epoch:
		sequence_epoch[seat] = epoch
		sequence[seat] = 0
	sequence[seat] += 1
	return {"version": OwnerPoseWire.VERSION, "seq": sequence[seat], "reset_epoch": epoch, "local_tick": sequence[seat], "time": float(sequence[seat]) / 60.0,
		"transform": Transform3D(Basis.IDENTITY, position), "velocity": velocity, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": 0.0, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

## One tick: every scripted seat sends a pose a step closer to its target (the replica's owner too: its pose comes from here,
## the replica's own courier is only checked), the replica follows the newest snapshot.
func tick(count := 1) -> void:
	for i in count:
		for seat in PLAYERS:
			var here: Vector3 = sim.actors[controller._slot(seat)].position if controller._slot(seat) >= 0 else targets[seat]
			var toward: Vector3 = targets[seat] - here
			var next: Vector3 = targets[seat] if toward.length() <= 8.0 else here + toward.normalized() * 8.0
			controller.inbox[seat] = pose(seat, next, velocities[seat])
		await physics_frame
		follow()

func wait_until(predicate: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if predicate.call(): return true
		await tick()
	return predicate.call()

func press(seat: int, key: String) -> void:
	var command: Dictionary = controller.commands[seat]
	command[key] = int(command.get(key, 0)) + 1
	command.seq = int(command.seq) + 1

func spot_of(slot: int) -> Vector3:
	var start: Dictionary = sim.level_world.team_start(sim.current_level(), PLAYERS, sim.team.checkpoint)
	return start.pos[slot]

func stand_on_ring() -> void:
	for seat in PLAYERS:
		targets[seat] = spot_of(controller._slot(seat)) + Vector3.UP * 0.05
		velocities[seat] = Vector3.ZERO

# ------------------------------------------------------------------ the replica (role "replica"), fed this run's snapshots
var carried := {}

func latest_state() -> Dictionary:
	if controller.documents.is_empty(): return {}
	var document: Dictionary = controller.documents[-1]
	largest = maxi(largest, (document.b as PackedByteArray).size())
	var state := Game.unpack_snapshot(document)
	if state.is_empty(): return {}
	if state.get("baseline", false):
		var movements := []
		for player: Dictionary in state.players: movements.append(player.get("movement", {}))
		carried = {"epoch": state.resets, "players": movements}
	if int(carried.get("epoch", -1)) == int(state.resets):
		for slot in state.players.size():
			if not state.players[slot].has("movement") and not state.players[slot].get("inactive", false) and (carried.players[slot] as Dictionary).has("yaw"):
				state.players[slot].movement = carried.players[slot]
	return state

func follow() -> void:
	if replica == null: return
	var state := latest_state()
	if state.is_empty(): return
	replica.apply_network_state(state, 1.0 / 60.0)
	var owner_slot := controller._slot(OWNER)
	if owner_slot >= 0 and replica.seed_baseline(state) and state.players[owner_slot].has("movement"):
		var baseline := {"position": state.players[owner_slot].position, "yaw": state.players[owner_slot].movement.yaw}
		if owner_courier == null:
			owner_courier = load("res://network/owner_courier.gd").new()
			if owner_courier.configure(replica, owner_slot, IDENTITY, state.resets, baseline): replica.owner_courier = owner_courier
			else: owner_courier = null
		elif int(state.resets) > owner_courier.reset_epoch: owner_courier.reset_from_authority(IDENTITY, state.resets, baseline)
		if owner_courier != null: owner_courier.observe_shared(IDENTITY, state)
	for seat in PLAYERS:
		var slot := controller._slot(seat)
		if seat != OWNER and slot >= 0: replica.apply_remote_pose(slot, pose_for_replica(slot, state))
	if owner_courier != null: replica.owner_step({"move": owner_move}, true, 1.0 / 60.0)

## The relayed pose of a remote slot: where the authority holds it.
func pose_for_replica(slot: int, state: Dictionary) -> Dictionary:
	var at: Vector3 = sim.actors[slot].position
	return {"version": OwnerPoseWire.VERSION, "seq": 1 + sim.frame, "reset_epoch": int(state.resets), "local_tick": sim.frame, "time": float(sim.frame) / 60.0,
		"transform": Transform3D(Basis.IDENTITY, at), "velocity": sim.actors[slot].velocity, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": 0.0, "acceleration": Vector3.ZERO, "anchor": at + Vector3(0.0, 1.0, 0.0), "flop": 0}

# ------------------------------------------------------------------ the run
func run() -> void:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	check(int(mode.get("seat_count", 0)) == Game.MAX_PLAYERS and Game.MAX_PLAYERS == 10, "one queue for up to ten players (%s)" % str(mode))
	check(CourseSection.play_mode_for(2) == CourseSection.CARRY and CourseSection.play_mode_for(3) == CourseSection.BALLOON and CourseSection.play_mode_for(10) == CourseSection.BALLOON, "2 players carry, 3 to 10 keep the balloon up")
	var balloon_pool := CourseSection.pool_levels(CourseSection.BALLOON)
	var carry_pool := CourseSection.pool_levels(CourseSection.CARRY)
	check(not balloon_pool.is_empty() and balloon_pool == CourseSection.rooms() and carry_pool.size() >= 2 and carry_pool.filter(func(k: int) -> bool: return k in balloon_pool).is_empty(), "balloon pool (the rooms) %s, carry pool %s" % [balloon_pool, carry_pool])
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
	load("res://client/presentation_entry.gd").install() # the client's own bootstrap (lobby drawing), as client/main.gd does
	replica = load("res://game/game_run.gd").new()
	replica.name = "Replica"
	replica.network_role = "replica"
	replica.carrier_count = controller.seat_count
	root.add_child(replica)
	var deadline := Time.get_ticks_msec() + 120000
	while not (sim.is_network_ready() and replica.is_network_ready()) and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready() and replica.is_network_ready(), "authority and replica shells ready (%d couriers each)" % sim.actors.size())
	check_checkpoint_facing()
	controller.simulation_ready = true
	controller._enter_lobby()
	for seat in PLAYERS:
		sequence.append(0)
		sequence_epoch.append(-1)
		velocities.append(Vector3.ZERO)
		controller.commands[seat] = {"seq": 1, "move": [0.0, 0.0], "jump_seq": 0, "grab_seq": 0}
		check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)
		targets.append(sim.actors[seat].position)
	var spots := {}
	for seat in PLAYERS: spots[WalkInLobby.spawn(seat).snapped(Vector3.ONE * 0.01)] = true
	check(spots.size() == PLAYERS, "every seat has its own yard spot")
	# ---- 0. the lobby yard is a playground: GRAB a player, lift, throw
	await check_lobby_grab()
	await check_lobby_props()
	await check_push()
	# ---- 1. walk-in
	var centre := WalkInLobby.center(CourseSection.ADVENTURE)
	var offsets := [Vector3(-0.6, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, -0.6), Vector3(0.0, 0.0, 0.6)]
	for seat in PLAYERS: targets[seat] = centre + offsets[seat] + Vector3(0.0, sim.actors[seat].position.y - centre.y, 0.0)
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready != "", 60 * 20)
	await tick(int(60 * (WalkInLobby.COUNTDOWN + 1.0)))
	check(ready and controller.phase == "lobby" and latest_state().get("match", {}).get("ready_pad", "") == CourseSection.ADVENTURE, "four players on one pad wait for PLAY (the snapshot names the pad)")
	check(bool(controller.execute_command(2, {"c": "play"}, "").ok), "a player on the pad presses PLAY")
	var started: bool = await wait_until(func() -> bool: return controller.phase == "round", 60 * 20)
	check(started, "four players on one pad started the round (phase=%s)" % controller.phase)
	if not started:
		finish()
		return
	check(controller.play_mode == CourseSection.BALLOON and sim.play_mode == CourseSection.BALLOON and controller.level_run.play_mode == CourseSection.BALLOON, "the round plays balloon mode")
	var room: int = CourseSection.rooms()[0]
	check(sim.current_level() == room and "balloon" in sim.level_world.modes(room), "the round plays ROOM 01 (level %d)" % (sim.current_level() + 1))
	check(not sim.painting.visible or not sim.holding_states.has(true), "no painting in a balloon round")
	# ---- 2. the team around the start pad, the balloon hanging over it
	stand_on_ring()
	await tick(30)
	var start: Dictionary = sim.level_world.team_start(room, PLAYERS)
	var balloon: BalloonSim = sim.team.balloon
	var ring := true
	for seat in PLAYERS: ring = ring and sim.actors[controller._slot(seat)].position.distance_to(start.pos[controller._slot(seat)]) < 0.3
	check(ring, "the team stands on a ring around the start pad")
	check(balloon.alive and balloon.hover and balloon.position.distance_to(start.spot + Vector3.UP * BalloonSim.RESPAWN_HEIGHT) < 0.05, "the balloon hangs over the start pad (%s)" % balloon.position)
	var snapshot := latest_state()
	check(snapshot.get("play_mode") == "balloon" and snapshot.get("balloon") is PackedFloat32Array and (snapshot.get("contact") as PackedFloat32Array).size() == controller.seat_count * Game.CONTACT_FLOATS, "snapshots carry play_mode, balloon and contact")
	await tick(10)
	check(replica.play_mode == "balloon" and replica.team.view.position.distance_to(balloon.position) < 0.5, "the replica draws the balloon where the authority has it")
	# ---- 3. a jump into it, then a pop on the floor and the restart at the start
	targets[0] = start.spot + Vector3(0.0, 0.5, 0.0)
	velocities[0] = Vector3(0.0, 5.0, 0.0)
	var bumped: bool = await wait_until(func() -> bool: return not balloon.hover, 30)
	check(bumped and balloon.bumps >= 1, "a jump into the balloon sets it going (bumps=%d)" % balloon.bumps)
	bump_lift = balloon.velocity.y
	stand_on_ring()
	var epoch: int = sim.reset_count
	var popped: bool = await wait_until(func() -> bool: return sim.failure_kind == "pop", 60 * 8)
	check(popped and sim.breaks == 1 and sim.death_ui_visible and not balloon.alive, "left alone it pops (pops=%d)" % sim.breaks)
	var shown: bool = await wait_until(func() -> bool: return replica.failure_kind == "pop" and not replica.team.view.alive, 30) # the next snapshot
	check(shown, "the replica shows the pop")
	var respawned: bool = await wait_until(func() -> bool: return sim.reset_count > epoch, 60 * 3)
	check(respawned and balloon.alive and balloon.hover, "a new epoch after the respawn time (epoch %d -> %d)" % [epoch, sim.reset_count])
	check(balloon.position.distance_to(start.spot + Vector3.UP * BalloonSim.RESPAWN_HEIGHT) < 0.05 and sim.actors[0].position.distance_to(start.pos[0]) < 0.3, "team and balloon back at the start")
	check(sim.breaks == 1 and sim.failure_kind == "", "the pop is counted once, the card is gone")
	# ---- 4. a checkpoint
	var level: int = sim.current_level()
	var origin: Vector3 = sim.level_world.level_origin(level)
	sim.level_world.checkpoints(level).append(LevelData.volume(Vector3(0.0, 2.0, -16.0), Vector3(12.0, 4.0, 3.0), 0.0))
	stand_on_ring()
	await tick(5)
	balloon.hover = false
	balloon.position = origin + Vector3(0.0, 2.6, -16.0)
	balloon.velocity = Vector3.ZERO
	var passed: bool = await wait_until(func() -> bool: return sim.team.checkpoint == 0, 10)
	check(passed, "the balloon passed the checkpoint")
	epoch = sim.reset_count
	var pop_again: bool = await wait_until(func() -> bool: return sim.reset_count > epoch, 60 * 8)
	var team_spot: Vector3 = sim.level_world.team_start(level, PLAYERS, 0).spot
	check(pop_again and sim.breaks == 2, "it popped again (pops=%d)" % sim.breaks)
	check(team_spot.distance_to(origin + Vector3(0.0, 0.0, -16.0)) < 0.3 and sim.actors[0].position.distance_to(spot_of(0)) < 0.3 and balloon.position.distance_to(team_spot + Vector3.UP * BalloonSim.RESPAWN_HEIGHT) < 0.05, "the team and the balloon restart at the checkpoint (%s)" % sim.actors[0].position)
	# ---- 5. contact: grab, throw, escape
	stand_on_ring()
	await tick(20)
	var here: Vector3 = sim.actors[controller._slot(0)].position
	targets[1] = here + Vector3(0.0, 0.0, -0.8) # in front of player 1 (facing -Z)
	var other: Vector3 = sim.actors[controller._slot(2)].position
	targets[3] = other + Vector3(0.0, 0.0, -0.8)
	await tick(10)
	press(0, "grab_seq")
	press(2, "grab_seq")
	var grabbed: bool = await wait_until(func() -> bool: return sim.team.held_by(controller._slot(1)) == controller._slot(0) and sim.team.held_by(controller._slot(3)) == controller._slot(2), 10)
	check(grabbed, "GRAB picks up the player in front (held_by %s)" % str(sim.team.contact.held_by))
	await tick(6)
	var touch: PackedFloat32Array = latest_state().get("contact", PackedFloat32Array())
	check(touch.size() > OWNER * Game.CONTACT_FLOATS and int(touch[controller._slot(OWNER) * Game.CONTACT_FLOATS]) == controller._slot(0), "the snapshot names the holder")
	var owner_slot := controller._slot(OWNER)
	check(owner_courier != null and replica.actors[owner_slot].position.distance_to(replica.actors[controller._slot(0)].position + Vector3.UP * 1.7) < 0.2, "the replica's owner courier rides above its holder")
	press(0, "grab_seq")
	var thrown: bool = await wait_until(func() -> bool: return sim.team.held_by(controller._slot(1)) < 0, 10)
	var kick: Vector3 = sim.team.kicks[controller._slot(1)]
	check(thrown and kick.y > 4.0 and Vector2(kick.x, kick.z).length() > 4.0, "GRAB again throws: a kick for the thrown player (%s)" % kick)
	var flew := false
	for i in 12:
		await tick()
		if replica.actors[owner_slot].velocity.y > 2.0 or replica.actors[owner_slot].position.y > replica.actors[controller._slot(0)].position.y + 2.2: flew = true
	check(flew, "the replica's owner courier flies off with the throw (v=%s)" % replica.actors[owner_slot].velocity)
	for i in 5:
		press(3, "jump_seq")
		await tick()
	await tick(2)
	check(sim.team.held_by(controller._slot(3)) < 0 and (sim.team.kicks[controller._slot(3)] as Vector3).y > 1.0, "five JUMP presses get the held player free")
	press(2, "grab_seq")
	await tick(2)
	check(sim.team.held_by(controller._slot(3)) < 0, "a player just freed cannot be grabbed again at once")
	# ---- 5b. the slap
	await check_slap()
	# ---- 6. a player falls out alone
	stand_on_ring()
	await tick(20)
	var pops_before: int = sim.breaks
	var faller := controller._slot(2)
	var fall: Vector3 = sim.actors[faller].position
	var respawned_alone := false
	for i in 10:
		fall += Vector3(0.0, -6.0, 0.0)
		targets[2] = fall
		await tick(2)
		if int(sim.team.respawns[faller]) > 0:
			respawned_alone = true
			break
	targets[2] = sim.team.respawn_points[faller]
	await tick(5)
	check(respawned_alone and sim.actors[faller].position.distance_to(sim.team.respawn_points[faller]) < 0.5, "a player in the void respawns alone at the team's spot")
	check(sim.breaks == pops_before and balloon.alive, "the balloon is not popped by a falling player")
	# ---- 7. hazards that hurt, high over the checkpoint where nothing else is
	await check_scorchers(level)
	await check_lift(level)
	# ---- 8. the goal
	var pops_total: int = sim.breaks
	var goal: Dictionary = sim.level_world.goal_volume(level)
	sim.started_moving = true
	await tick(30)
	balloon.hover = false
	balloon.position = goal.p
	balloon.velocity = Vector3.ZERO
	var cleared: bool = await wait_until(func() -> bool: return controller.phase == "results", 60 * 5)
	check(cleared and controller.level_run.cleared() == 1 and controller.round_success, "the balloon in the goal clears the level and ends the one-level run (phase=%s)" % controller.phase)
	check(controller.results_sub.contains("%d pops" % pops_total) and controller.results_sub.contains("total"), "the results show the time and the pops: %s | %s" % [controller.results_headline, controller.results_sub])
	check(controller.results_rows.size() == PLAYERS, "a results row per player")
	# ---- snapshots
	check(largest > 0 and largest < 8192, "largest snapshot %d bytes" % largest)
	var round_trip := Game.unpack_snapshot(Game.pack_snapshot(controller.snapshot_state(true)))
	check(not round_trip.is_empty() and round_trip.players.size() == controller.seat_count, "a full snapshot of %d slots packs and unpacks" % controller.seat_count)
	finish()

## A lift that rises into the hanging balloon throws it off upwards: no pop, and the balloon is never inside the lift.
func check_lift(level: int) -> void:
	var world = sim.level_world
	var balloon: BalloonSim = sim.team.balloon
	var index: int = world.add_hazard(level, {"k": "lift", "p": [10, 40, -20], "s": [3, 0.5, 3], "rise": 3, "period": 3, "pause": 0.25})
	var lift: Node3D = world.get_node_or_null("Level%02d/Hazard_lift_%d" % [level + 1, index])
	check(lift != null, "a lift added high over the level")
	if lift == null: return
	stand_on_ring()
	await tick(5)
	var spot: Vector3 = balloon.respawn_point
	var pops: int = sim.breaks
	var rest: Vector3 = world.level_origin(level) + Vector3(10.0, 40.0, -20.0) # the lift's pivot at rest
	balloon.respawn_point = rest + Vector3(0.0, 1.5 - BalloonSim.RESPAWN_HEIGHT, 0.0) # hanging 1.5 m over the lift at rest
	balloon.hover = true
	var swallowed := false
	var thrown := false
	for i in 60 * 4:
		await tick()
		var top: float = lift.global_position.y + 0.25
		var flat := Vector2(balloon.position.x - lift.global_position.x, balloon.position.z - lift.global_position.z)
		if absf(flat.x) < 1.5 and absf(flat.y) < 1.5 and balloon.position.y < top + BalloonSim.RADIUS * 0.5 and balloon.position.y > top - 0.5: swallowed = true
		if not balloon.hover:
			thrown = thrown or balloon.velocity.y > 0.5
			if i > 60 * 3 or (thrown and balloon.position.y > top + BalloonSim.RADIUS + 0.2): break
	check(thrown and not swallowed and sim.breaks == pops and balloon.alive, "a lift rising into the balloon throws it off, never swallows or pops it (thrown=%s swallowed=%s)" % [thrown, swallowed])
	balloon.respawn_point = spot
	balloon.hover = true # back over the checkpoint for the rest of the run
	await tick(5)

## In the lobby yard player 1 grabs player 2 in front of it (held above, in the snapshot, on the replica's owner courier), then throws.
func check_lobby_grab() -> void:
	await tick(30)
	var holder := controller._slot(0)
	var held := controller._slot(1)
	targets[1] = sim.actors[holder].position + Vector3(0.0, 0.0, -0.8)
	await tick(10)
	press(0, "grab_seq")
	var grabbed: bool = await wait_until(func() -> bool: return sim.team.held_by(held) == holder, 10)
	await tick(6)
	var touch: PackedFloat32Array = latest_state().get("contact", PackedFloat32Array())
	check(grabbed and sim.round_mode == "lobby" and touch.size() > held * Game.CONTACT_FLOATS and int(touch[held * Game.CONTACT_FLOATS]) == holder, "in the lobby GRAB picks up the player in front (in the snapshot)")
	var rides: bool = owner_courier != null and replica.actors[held].position.distance_to(replica.actors[holder].position + Vector3.UP * 1.7) < 0.2
	check(rides, "the held player's own client puts its courier above the holder in the lobby")
	press(0, "grab_seq")
	var thrown: bool = await wait_until(func() -> bool: return sim.team.held_by(held) < 0, 10)
	check(thrown and (sim.team.kicks[held] as Vector3).length() > 4.0, "GRAB again throws them in the lobby")
	targets[1] = sim.actors[held].position
	await tick(60)

func check_lobby_props() -> void:
	var props: PropSim = sim.team.props
	var holder := controller._slot(0)
	var victim := controller._slot(1)
	var feet: Vector3 = sim.actors[holder].position
	targets[1] = feet + Vector3(4.0, 0.0, 0.0) # out of reach: the GRAB is left for the props
	await tick(20)
	props.positions[0] = feet + Vector3(0.0, 0.25, -0.9)
	props.velocities[0] = Vector3.ZERO
	press(0, "grab_seq")
	var picked: bool = await wait_until(func() -> bool: return props.holding(holder) == 0, 10)
	await tick(6)
	var loose: PackedFloat32Array = latest_state().get("props", PackedFloat32Array())
	check(picked and sim.team.held_by(victim) < 0 and loose.size() == props.count * Game.PROP_FLOATS and int(loose[Game.PROP_FLOATS - 1]) == holder, "in the lobby GRAB with nobody in reach picks up the box in front (in the snapshot)")
	var drawn: Vector3 = (replica.team.prop_look.get_child(0) as Node3D).position
	var hand := PropSim.hold_point(replica.actors[holder].position, Vector3.FORWARD)
	check(replica.team.props.held_by[0] == holder and drawn.distance_to(hand) < 0.15, "the replica draws the box in the holder's hands (%.2f m off)" % drawn.distance_to(hand))
	press(0, "grab_seq")
	var thrown: bool = await wait_until(func() -> bool: return props.holding(holder) < 0, 10)
	await tick(60)
	var flew: float = feet.z - props.positions[0].z
	check(thrown and flew > 3.0 and props.positions[0].y < feet.y + 0.8, "GRAB again throws the box: it lands %.1f m ahead" % flew)
	props.positions[0] = sim.actors[victim].position + Vector3(0.0, 0.25, -0.9)
	props.velocities[0] = Vector3.ZERO
	press(1, "grab_seq")
	var victim_picked: bool = await wait_until(func() -> bool: return props.holding(victim) == 0, 10)
	targets[0] = sim.actors[victim].position + Vector3(0.0, 0.0, 0.8) # behind the carrier, facing it
	await tick(10)
	var knocks: int = sim.team.prop_counts.knock
	press(0, "grab_seq")
	var knocked: bool = await wait_until(func() -> bool: return sim.team.held_by(victim) == holder and props.holding(victim) < 0, 10)
	check(victim_picked and knocked and sim.team.prop_counts.knock > knocks, "a carrier who is grabbed drops the box")
	press(0, "grab_seq") # throw them off again
	await wait_until(func() -> bool: return sim.team.held_by(victim) < 0, 10)
	await tick(30)
	targets[1] = sim.actors[victim].position
	await tick(30)

## Seat 0 keeps walking into the replica's own courier, which walks back into it at full speed, for 5 s: shoves push it along the
## floor, never up.
func check_push() -> void:
	var own := controller._slot(OWNER)
	var body: CharacterBody3D = replica.actors[own]
	var floor_y := body.global_position.y
	targets[0] = body.global_position + Vector3(0.0, 0.0, -1.2)
	await tick(20)
	owner_move = Vector2(0.0, -1.0)
	velocities[0] = Vector3(0.0, 0.0, 5.0)
	var worst_speed := 0.0
	var worst_rise := 0.0
	var airborne := 0
	for step in 300:
		targets[0] = body.global_position + Vector3(0.0, 0.0, -0.55) # leaning into it
		await tick()
		worst_speed = maxf(worst_speed, absf(body.velocity.y))
		worst_rise = maxf(worst_rise, body.global_position.y - floor_y)
		if not owner_courier.motion.grounded: airborne += 1
	owner_move = Vector2.ZERO
	velocities[0] = Vector3.ZERO
	check(worst_speed <= 0.5 and worst_rise <= 0.1 and airborne == 0, "online, two players pushing into each other for 5 s stay on the floor (vertical speed %.2f m/s, rise %.2f m, airborne ticks %d)" % [worst_speed, worst_rise, airborne])
	targets[0] = sim.actors[controller._slot(0)].position
	await tick(30)

## GRAB near the balloon slaps it: told apart from a grab, a stronger lift than a bump, a cooldown, grabs still work.
func check_slap() -> void:
	var balloon: BalloonSim = sim.team.balloon
	var slapper := controller._slot(0)
	stand_on_ring()
	await tick(20)
	var spot: Vector3 = sim.level_world.team_start(sim.current_level(), PLAYERS, sim.team.checkpoint).spot
	targets[0] = spot + Vector3(0.6, 0.05, 0.6) # beside and under the hanging balloon, facing -Z
	await tick(4)
	check(balloon.alive and balloon.hover and sim.team.slap_side(slapper) != 0, "GRAB next to the balloon with nobody in front is a slap (hand %d)" % sim.team.slap_side(slapper))
	targets[1] = spot + Vector3(0.6, 0.05, -0.2) # a free player in front: GRAB grabs
	await tick(4)
	check(sim.team.slap_side(slapper) == 0, "with a free player in front GRAB stays a grab")
	press(0, "grab_seq")
	var grabbed: bool = await wait_until(func() -> bool: return sim.team.held_by(controller._slot(1)) == slapper, 10)
	check(grabbed and balloon.hover, "grabbing players still works next to the balloon")
	press(0, "grab_seq") # throw them off
	await tick(3)
	targets[1] = spot_of(controller._slot(1)) + Vector3.UP * 0.05
	await tick(10)
	var started: int = sim.team.slap_counts[slapper * 2]
	press(0, "slap_seq")
	var hit: bool = await wait_until(func() -> bool: return balloon.slaps >= 1, 15)
	check(hit and balloon.velocity.y > bump_lift + 1.0 and not balloon.hover, "a slap lifts the balloon more than a bump (%.2f m/s, bump %.2f)" % [balloon.velocity.y, bump_lift])
	check(sim.team.slap_counts[slapper * 2] == started + 1 and (latest_state().get("slaps", PackedInt32Array()) as PackedInt32Array).size() == controller.seat_count * 2, "the slap is counted in the snapshot")
	await tick(3)
	check(replica.team.slaps_shown >= 1, "the replica swings the slapper's arm (%d)" % replica.team.slaps_shown)
	press(0, "slap_seq") # within the cooldown: nothing
	await tick(10)
	check(sim.team.slap_counts[slapper * 2] == started + 1 and balloon.slaps == 1, "a second slap within the cooldown does nothing")
	await tick(int(sim.team.SLAP_COOLDOWN * 60.0))
	press(0, "slap_seq")
	await tick(3)
	check(sim.team.slap_counts[slapper * 2] == started + 2, "after the cooldown the next slap counts")
	# Back to a hanging balloon for the rest of the run.
	var epoch: int = sim.reset_count
	if balloon.alive: balloon.hover = true
	else: await wait_until(func() -> bool: return sim.reset_count > epoch, 60 * 3)
	stand_on_ring()
	await tick(10)

## Lasers, fire and spikes (levels/hazards.gd) on the authority, added to `level` 20 m and more over the checkpoint the team stands at.
func check_scorchers(level: int) -> void:
	var world = sim.level_world
	var origin: Vector3 = world.level_origin(level)
	var high := origin + Vector3(0.0, 20.0, 0.0)
	check(world.add_hazard(level, {"k": "laser", "p": [-6, 21, -20], "to": [12, 0, 0]}) >= 0, "a laser added to the level")
	world.add_hazard(level, {"k": "laser", "p": [-6, 30, -20], "to": [12, 0, 0]})
	world.add_hazard(level, {"k": "fire", "p": [0, 30, -26], "s": [2, 3, 2]})
	world.add_hazard(level, {"k": "spin", "p": [0, 30, -32], "rate": 20, "parts": [{"k": "cyl", "p": [0, 0, 0], "d": 1, "h": 1}], "look": "spikes"})
	world.add_hazard(level, {"k": "spin", "p": [6, 30, -32], "rate": 20, "parts": [{"k": "cyl", "p": [0, 0, 0], "d": 1, "h": 1}]})
	var balloon: BalloonSim = sim.team.balloon
	stand_on_ring()
	await tick(70) # past the respawn grace of the fall above
	# A laser across a player: that player alone respawns at the checkpoint, the others stay, the balloon flies on.
	var zapped := controller._slot(2)
	var pops_before: int = sim.breaks
	var respawns_before: int = sim.team.respawns[zapped]
	var others := []
	for seat in PLAYERS: others.append(sim.actors[controller._slot(seat)].position)
	targets[2] = high + Vector3(0.0, 0.0, -20.0)
	var hit: bool = await wait_until(func() -> bool: return int(sim.team.respawns[zapped]) > respawns_before, 20)
	targets[2] = spot_of(zapped) + Vector3.UP * 0.05
	await tick(4)
	var stayed := true
	for seat in PLAYERS:
		if seat != 2: stayed = stayed and sim.actors[controller._slot(seat)].position.distance_to(others[seat]) < 0.1
	check(hit and sim.actors[zapped].position.distance_to(spot_of(zapped)) < 0.3 and stayed, "a laser zaps a player: that player alone respawns at the checkpoint")
	check(sim.breaks == pops_before and balloon.alive, "a zap does not pop the balloon")
	check(sim.team.scorches[zapped * 2] == 1 and sim.team.scorches[zapped * 2 + 1] == 1, "the zap is counted for the clients (%s)" % sim.team.scorches)
	await tick(3)
	var words: Array = replica.world.find_children("HazardWord*", "Label3D", true, false)
	check(replica.team._scorches_seen.size() > zapped * 2 and replica.team._scorches_seen[zapped * 2] == 1 and words.size() >= 1 and words[0].text == "ZAP!", "the replica shows ZAP! over the player (%d words)" % words.size())
	# A fire jet burns a player the same way.
	var burned := controller._slot(3)
	targets[3] = high + Vector3(0.0, 8.5, -26.0)
	var burnt: bool = await wait_until(func() -> bool: return sim.team.scorches[burned * 2] == 1, 20)
	targets[3] = spot_of(burned) + Vector3.UP * 0.05
	await tick(4)
	check(burnt and sim.team.scorches[burned * 2 + 1] == 2 and sim.actors[burned].position.distance_to(spot_of(burned)) < 0.3, "a fire jet burns a player, who respawns at the checkpoint")
	# The balloon in a laser, in a fire jet, at the spike tips of a crusher: three pops. The same gap to a plain mover: none.
	for case: Array in [["a laser pops the balloon", Vector3(0.0, 10.0, -20.0)], ["a fire jet pops the balloon", Vector3(0.0, 10.0, -26.0)],
			["the spike tips of a spike crusher pop the balloon", Vector3(-1.2, 10.0, -32.0)]]:
		stand_on_ring()
		var epoch: int = sim.reset_count
		var before: int = sim.breaks
		balloon.hover = false
		balloon.position = high + case[1]
		balloon.velocity = Vector3.ZERO
		var popped: bool = await wait_until(func() -> bool: return sim.breaks > before, 6)
		check(popped and sim.failure_kind == "pop", case[0])
		await wait_until(func() -> bool: return sim.reset_count > epoch, 60 * 3)
		await tick(2)
	var plain_before: int = sim.breaks
	balloon.hover = false
	balloon.position = high + Vector3(6.0 - 1.2, 10.0, -32.0)
	balloon.velocity = Vector3.ZERO
	await tick(4)
	check(sim.breaks == plain_before and balloon.alive, "the same gap to a mover without spikes does not pop it")
	balloon.hover = true # back over the checkpoint for the rest of the run
	stand_on_ring()
	await tick(5)

## Every checkpoint of the real levels: the team restarts facing along the course, so two metres forward along its facing
## is further along the level's path, not into a wall beside it.
func check_checkpoint_facing() -> void:
	var tested := 0
	var wrong := []
	for k in sim.level_world.level_count():
		var route: PackedVector3Array = sim.level_world.route(k)
		for index in sim.level_world.checkpoints(k).size():
			var start: Dictionary = sim.level_world.team_start(k, PLAYERS, index)
			var facing := Vector3(-sin(float(start.yaw)), 0.0, -cos(float(start.yaw)))
			var gain := progress(route, start.spot + facing * 2.0) - progress(route, start.spot)
			tested += 1
			if gain < 1.0: wrong.append("level %d checkpoint %d (yaw %.0f deg, progress %+.2f m)" % [k + 1, index + 1, rad_to_deg(float(start.yaw)), gain])
	check(tested > 0 and wrong.is_empty(), "the team faces along the course at all %d checkpoints of the levels %s" % [tested, wrong])

## Arc length along `points` to the point of the polyline nearest to `at`.
func progress(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	var along := 0.0
	var walked := 0.0
	for index in range(1, points.size()):
		var nearest := Geometry3D.get_closest_point_to_segment(at, points[index - 1], points[index])
		if at.distance_to(nearest) < best:
			best = at.distance_to(nearest)
			along = walked + points[index - 1].distance_to(nearest)
		walked += points[index - 1].distance_to(points[index])
	return along

func finish() -> void:
	print("BALLOON_ROUND ok=", failures == 0, " failures=", failures)
	quit(1 if failures > 0 else 0)
