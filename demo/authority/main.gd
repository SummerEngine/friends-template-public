extends "res://network/match_controller.gd"
const DevEnv := preload("res://dev_env.gd")
## SDK transport around the shared match controller.
## Identity, stream grants, command replies and hosted settlement stay here.
const OwnerPoseWire = preload("res://network/owner_pose_wire.gd")
var spawner: SummerNetworkSpawner
var net: SummerNetworkWorld
var state_group: SummerNetworkStateGroup
var seats := {} # session id -> seat
var published_reset := -1
var probe: Object ## dev probe (DevEnv.attach_probe), null in a release build
var publish_failures := 0
var admitted_sessions := {}
var departed_sessions := {}

func _ready() -> void:
	var boot_started_msec := Time.get_ticks_msec()
	# Resolve trusted placement before the world is built, while no World node
	# exists. Initialization prepares identity without opening a transport.
	var initialized: SummerResult = await Summer.initialize().get_result_or_completed_signal()
	if not initialized.ok or Summer.authority == null or Summer.authority.context.world == null:
		push_error("GW_AUTHORITY_INIT_FAILED " + str(initialized.code))
		return
	match_queue = StringName(Summer.authority.context.world.queue)
	match_mode = Game.match_mode_for_queue(match_queue)
	if match_mode.is_empty():
		push_error("GW_AUTHORITY_MODE_UNKNOWN_QUEUE")
		return
	seat_count = int(match_mode.seat_count)
	input_sequences.resize(seat_count)
	input_sequences.fill(0)
	# World readiness permits clients to start their bounded transport.
	# Finish the synchronous level build before registering that World;
	# otherwise this main thread cannot poll ENet during the clients' handoff.
	simulation = load("res://game/game_run.gd").new()
	simulation.name = "Simulation"
	simulation.network_role = "authority"
	simulation.carrier_count = seat_count
	add_child(simulation)
	while not simulation.is_network_ready(): await get_tree().process_frame
	print("GW_AUTHORITY_SIMULATION_READY elapsed_ms=", Time.get_ticks_msec()-boot_started_msec, " network_created=false")
	spawner = Game.build_network(self)
	print("GW_AUTHORITY_NETWORK_CREATED elapsed_ms=", Time.get_ticks_msec()-boot_started_msec)
	net = $World
	net.session_joined.connect(_admitted)
	spawner.entity_spawned.connect(_spawned)
	spawner.command_received.connect(_command)
	net.session_left.connect(_left)
	net.session_disconnected.connect(_disconnected)
	net.session_reconnected.connect(_reconnected)
	if not net.is_ready(): await net.binding_ready
	if not spawner.is_network_ready(): await spawner.network_ready
	state_group = spawner.create_state_group(Game.SNAPSHOT, &"world", Game.pack_snapshot(Game.with_match_mode({},match_queue)))
	if state_group == null:
		push_error("GW_AUTHORITY_STREAM_FAILED")
		return
	_enter_lobby()
	simulation_ready = true
	probe = DevEnv.attach_probe(self, "authority")
	print("GW_AUTHORITY_READY couriers=", simulation.actors.size(), " authority_owned=true queue=", match_queue, " seats=", seat_count)

# ------------------------------------------------------------------ seats and commands

func _seat(session: SummerSession) -> int:
	admitted_sessions[session.session_id] = session
	if seats.has(session.session_id): return int(seats[session.session_id])
	for seat in seat_count:
		if seat not in seats.values():
			seats[session.session_id] = seat
			return seat
	return -1

func _spawned(entity: SummerNetworkEntity) -> void:
	var seat := _seat(entity.session)
	if seat < 0: return
	var group := spawner.create_state_group(Game.INPUT, Game.input_key(seat), Game.pack({"seq": 0, "move": [0, 0]}), entity.session, entity)
	group.set_acceptance_policy(_validate_state.bind(seat))
	groups[seat] = group
	var relay := spawner.create_state_group(Game.WORKER,Game.input_key(seat),{"b":PackedByteArray()},null,entity)
	if relay == null:
		push_error("GW_WORKER_STREAM_FAILED")
		return
	worker_groups[seat] = relay
	revisions[seat] = -1
	print("GW_SESSION_SPAWNED seat=", seat, " entity=", entity.entity_id)

func _validate_state(candidate: Dictionary, current: Dictionary, seat_number: int) -> bool:
	# SDK verifies the bound writer Session/entity/grant before this policy.
	var data := Game.unpack(candidate)
	var previous := Game.unpack(current)
	if not Game.valid_input(data) or int(data.seq) <= int(previous.get("seq", -1)): return false
	if not data.has("owner_pose"): return true # Waiting for the first trusted baseline.
	if not simulation_ready or not joined.has(seat_number) or _slot(seat_number) < 0: return false
	var pose := OwnerPoseWire.decode(data.owner_pose)
	if pose.is_empty() or int(pose.reset_epoch) != simulation.reset_count: return false
	var before := OwnerPoseWire.decode(previous.get("owner_pose",PackedByteArray()))
	return before.is_empty() or before.reset_epoch != pose.reset_epoch or int(pose.seq)>int(before.seq)

func _reset_owner_streams() -> void:
	# Shared respawn fences in-flight owner submissions at the SDK grant boundary.
	# No input-group reset is treated as permission to reseed a client root.
	for seat: int in groups:
		simulation.clear_authority_owner_pose(_slot(seat))
		var result: SummerResult = groups[seat].reset(Game.pack({"seq":0,"move":[0,0]}))
		if not result.ok: push_error("GW_OWNER_EPOCH_FENCE_FAILED " + str(result.code))
	for seat: int in worker_groups:
		var result: SummerResult = worker_groups[seat].reset({"b":PackedByteArray()})
		if not result.ok: push_error("GW_WORKER_EPOCH_FENCE_FAILED " + str(result.code))

## Relay rate per owner from the players in the World (Game.relay_every: 60/30/20 Hz, bytes grow with players x
## players). Observers widen their back time to match (client/main.gd).
func _relay_every() -> int:
	return Game.relay_every(joined.size())

func _relay_owner_pose(seat: int, bytes: PackedByteArray) -> void:
	# Validated (structure, epoch, sequence) on receipt and relayed in the same tick:
	# the partner's smoothing needs the pose, not the authority's application of it.
	var group: SummerNetworkStateGroup = worker_groups.get(seat)
	if group == null or not group.is_active(): return
	var skipped := int(relay_skip.get(seat, 0)) + 1
	if skipped < _relay_every():
		relay_skip[seat] = skipped
		return
	relay_skip[seat] = 0
	group.submit({"b":bytes})

func _command(request: SummerNetworkCommandRequest) -> void:
	var session := request.get_session()
	var seat := _seat(session)
	if seat < 0:
		request.refuse(&"match_full")
		return
	var outcome := execute_command(seat, Game.unpack(request.payload), _display_name(session, seat))
	if bool(outcome.ok): request.accept({}, Game.pack(outcome.result))
	else: request.refuse(StringName(outcome.reason))

## The match rules of every shared command, for an already admitted seat. The SDK wrapper
## (_command) and the offline test lab (test_lab/lab_authority.gd) both call this; transport
## identity stays with the caller. Returns {ok, result, reason}.
func _request_leave(seat: int) -> void:
	for id: String in seats:
		if int(seats[id]) == seat:
			_left.call_deferred(admitted_sessions[id], "quit")
			return

func _display_name(session: SummerSession, seat: int) -> String:
	var player: SummerPlayer = session.player
	var text := str(player.display_name).strip_edges() if player != null else ""
	return text.substr(0, 16) if not text.is_empty() else "Player %d" % (seat + 1)

# ------------------------------------------------------------------ leaving and reconnecting

func _left(session: SummerSession, reason: String) -> void:
	departed_sessions[session.session_id] = true
	var seat := int(seats.get(session.session_id, -1))
	if seat < 0: return
	seats.erase(session.session_id)
	_leave_seat(seat, reason)

## A joined seat is gone for good (shared by every transport): its round ends, an empty World concludes.
func _admitted(session: SummerSession) -> void:
	# Keep the exact admitted objects even when a player leaves: settlement
	# requires the whole eligible roster, rather than only connected clients.
	admitted_sessions[session.session_id] = session

func _disconnected(session: SummerSession) -> void:
	_disconnect_seat(int(seats.get(session.session_id, -1)))

## Transport dropped without a leave: neutral input, frozen pose; _tick_round pauses for the partner.
func _reconnected(session: SummerSession) -> void:
	_reconnect_seat(int(seats.get(session.session_id, -1)))

func _conclude_world(success: bool, reason: String) -> void:
	if concluding: return
	concluding = true
	phase = "ended"
	settlement_state = "settling"
	# Concluding revokes ordinary match writes. Install the final gameplay state first.
	var final_state: Dictionary = _snapshot_state(true)
	final_state.settlement_state = settlement_state
	var installed := state_group.reset(Game.pack_snapshot(final_state))
	if not installed.ok: push_error("GW_FINAL_STATE_FAILED " + str(installed.code))
	await get_tree().create_timer(1.0).timeout
	var outcomes: Dictionary[SummerSession, SummerAuthorityMatch.MatchOutcome] = {}
	for id: String in admitted_sessions:
		var session: SummerSession = admitted_sessions[id]
		var participant := Summer.authority.match.get_participant(session)
		if participant == null or not participant.outcome_eligible: continue
		outcomes[session] = SummerAuthorityMatch.MATCH_OUTCOME_ABANDON if departed_sessions.has(id) else (SummerAuthorityMatch.MATCH_OUTCOME_WIN if success else SummerAuthorityMatch.MATCH_OUTCOME_LOSS)
	var settled := false
	for attempt in 3:
		var operation := Summer.authority.match.conclude(outcomes, reason)
		var result: SummerResult = await operation.get_result_or_completed_signal()
		if result.ok:
			settled = true
			settlement_state = "settled"
			print("GW_MATCH_SETTLED players=", outcomes.size(), " success=", success, " replayed=", operation.replayed)
			break
		print("GW_MATCH_SETTLEMENT_FAILED code=", result.code, " retryable=", result.retryable)
		if not result.retryable: break
		await get_tree().create_timer(1.0 + attempt).timeout
	if not settled:
		settlement_state = "failed"
		push_error("GW_MATCH_SETTLEMENT_FAILED exhausted_or_refused")
		return
	await get_tree().create_timer(3.0).timeout
	var completed: SummerResult = await Summer.authority.world.complete(reason).get_result_or_completed_signal()
	settlement_state = "completed" if completed.ok else "completion_failed"
	print("GW_WORLD_COMPLETED ok=", completed.ok, " code=", completed.code)

# ------------------------------------------------------------------ tick

func _apply_owner_poses() -> void:
	for seat in seat_count:
		var group: SummerNetworkStateGroup = groups.get(seat)
		if group == null or not group.is_active(): continue
		var slot := _slot(seat)
		if int(revisions.get(seat, -1)) != group.get_revision():
			revisions[seat] = group.get_revision()
			var command := Game.unpack(group.get_state())
			if Game.valid_input(command):
				command.erase("restart") # Restart is a separately admitted shared command.
				fresh_at[seat] = elapsed
				owner_expired.erase(seat)
				input_sequences[seat] = int(command.seq)
				if slot < 0: continue
				var accepted_pose := {}
				if command.has("owner_pose"):
					var pose := OwnerPoseWire.decode(command.owner_pose)
					if not pose.is_empty() and simulation.queue_authority_owner_pose(slot, pose):
						_relay_owner_pose(seat, command.owner_pose)
						accepted_pose = pose
				_note_owner_input(seat, command, accepted_pose) # walk-in lobby: accepted position, menu flag
				simulation.set_player_input(slot, command)
		else: _expire_stale_input(seat)

# ------------------------------------------------------------------ snapshot

func _snapshot_state(full: bool) -> Dictionary:
	var state: Dictionary = simulation.capture_network_state(full or baseline_burst > 0)
	state = Game.with_match_mode(state,match_queue)
	state.baseline = full or baseline_burst > 0
	state.players_joined = joined.size()
	state.server_elapsed = elapsed
	var grants := []
	grants.resize(seat_count)
	grants.fill(0)
	for seat: int in groups:
		if groups[seat].is_active(): grants[seat] = int(groups[seat].get_timing().grant_revision)
	state.owner_grants = grants
	state.input_sequences = input_sequences.duplicate() # input receipt sequence, by seat
	state.waiting_for_partner = waiting_for_partner
	state.settlement_state = settlement_state
	state.match = _match_state()
	return state

func _publish() -> void:
	var state := _snapshot_state(false)
	var document := Game.pack_snapshot(state)
	if document.is_empty():
		push_error("GW_SNAPSHOT_PACK_FAILED")
		return
	if baseline_burst > 0: baseline_burst -= 1
	if document.b.size() > 32768:
		push_error("GW_SNAPSHOT_TOO_LARGE " + str(document.b.size()))
		return
	# Ordinary replaceable state uses the writer's submit path. Reset is an
	# explicit protocol discontinuity, reserved for shared respawns.
	var reset_number := int(state.get("resets", 0))
	if reset_number != published_reset:
		var result := state_group.reset(document)
		if result.ok: published_reset = reset_number
		else: push_error("GW_STATE_RESET_FAILED " + str(result.code))
	else:
		var submission := state_group.submit(document)
		if submission.outcome in [SummerNetworkStateSubmission.OUTCOME_REJECTED, SummerNetworkStateSubmission.OUTCOME_INVALIDATED, SummerNetworkStateSubmission.OUTCOME_EXPIRED]:
			publish_failures += 1
			push_error("GW_STATE_SUBMIT_FAILED " + str(submission.reason))
	if stats_time >= 5.0:
		stats_time = 0.0
		if DevEnv.is_dev(): print("GW_AUTHORITY_STATE tick=", state.get("tick", 0), " phase=", phase, " players=", joined.size(), " bytes=", document.b.size(), " baseline=", state.baseline, " physics_ms=", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0, " fps=", Engine.get_frames_per_second(), " submit_failures=", publish_failures)
