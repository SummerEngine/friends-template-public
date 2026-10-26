extends Node
## Transport-neutral match rules shared by hosted SDK authority and the offline lab.
## Identity, streams and settlement live in authority/main.gd.
## Authority of one match-scoped World: the lobby, the rounds and the results (docs/online-lobby.md).
## It validates owner poses and derives the painting from them; it runs no courier rigs.
##
## Phases: lobby (players walk in the yard; standing together on one pad starts a short
## countdown, docs/walk-in-lobby.md) -> round (a run of levels: 2 players carry the painting, 3 to 10
## keep the balloon up, course_section.gd play_mode_for) -> results
## (Play Again / Main Menu) -> lobby again (with the players who chose Play Again, back on their
## yard spots) ... -> the World completes when fewer than 2 players remain.
##
## Seat = a player's network identity (group keys p0..p7). Slot = position in the round (actors,
## anchors). In the lobby slot == seat; at a round start the roster is compacted in
## join order and published as `match.slots`.
const Game = preload("res://network/game.gd")
const ResyncLimit = preload("res://network/resync_limit.gd")
const CourseSection = preload("res://course_section.gd")
const WalkInLobby = preload("res://network/walk_in_lobby.gd")
const LevelRun = preload("res://levels/level_run.gd")
const LookRelay = preload("res://network/look_relay.gd")
const Modes = preload("res://modes/modes.gd")
const ModeHost = preload("res://modes/mode_host.gd")
const Tandem = preload("res://modes/show/shared/tandem/tandem.gd")
const JOIN_SETTLE := 8.0 ## the formed roster size is unknown: wait this long after the last join before a walk-in start
const RESULTS_SECONDS := 25.0 ## time to choose Play Again / Main Menu
const BASELINE_BURST := 40 ## snapshots (2 s) that carry the full owner baselines after an epoch/join
const LOBBY_IDLE_SECONDS := 900.0
const SNAPSHOT_PERIOD := 0.05
var simulation
var seat_count := 2
var groups := {} # seat -> input group
var worker_groups := {} # seat -> pose relay group
var relay_skip := {} # seat -> poses since the last relay
var owner_epoch := -1
var owner_expired := {}
var revisions := {}
var fresh_at := {}
var joined := {} # seat -> true after the join command
## seat -> true once its owner's first pose was accepted: that client is in the world (level built, owner simulation
## running). A joined seat that is not present yet is still loading: it counts for no pad, no roster and no start, and
## the other clients draw it as loading (match.ready). Nothing here ever removes a loading seat.
var present := {}
var joined_at := {} # seat -> elapsed at its join command
var names := {} # seat -> display name
var join_order: Array = [] # seats, in the order their join command was accepted
var disconnected := {}
var simulation_ready := false
var elapsed := 0.0
var send_time := 0.0
var stats_time := 0.0
var input_sequences: Array = []
var restart_requested := false
var resync_admission := ResyncLimit.new()
var match_queue: StringName = &""
var match_mode := {}
var looks := LookRelay.new() ## the players' looks, published in the match state (network/look_relay.gd)
# --- phase machine ---
var phase := "boot" # boot | lobby | round | results | ended
var round_number := 0
var round_mode := "" # level
var play_mode := "" ## carry | balloon of the current round, decided by the roster size at its start
var slots: Array = [] # slot -> seat (-1 empty)
var slot_of := {} # seat -> slot
var start_at := -1.0 ## walk-in countdown end (elapsed), -1 = no countdown
var round_roster: Array = [] # seats in slot order for the current round
var round_success := false
var round_reason := ""
var results_rows: Array = []
var results_headline := ""
var results_sub := ""
var results_deadline := 0.0
var choices := {} # seat -> "again" | "menu" | "gone"
var excluded := {} # seats that must leave (did not choose in time)
var waiting_for_partner := false
var resume_after_partner := false
var baseline_burst := 0
var lobby_since := 0.0
var concluding := false
var settlement_state := "playing"
var ever_joined := false
var round_started_elapsed := 0.0
var last_join_elapsed := -100.0
# --- course (docs/walk-in-lobby.md) ---
var course := CourseSection.default_course() ## course of the last walk-in pick, frozen into round_plan at the start
var round_pick := "" ## the circle of the last walk-in pick (WalkInLobby pad id: the show has one per round); its `pick` goes to a minigame's rules (ModeHost.pick)
var round_plan: Dictionary = {} ## frozen at the round start
var round_time := 0.0 ## seconds played this round, partner pause excluded
var level_run: RefCounted ## the level run of this round (levels/level_run.gd), null without levels / in the lobby
var level_clearing := false ## a level was just cleared: its card is up until `level_next_at` (elapsed)
var level_next_at := -1.0
# --- minigames (modes/modes.gd: the cast's mode; docs/modes.md) ---
var minigame: RefCounted ## the round's rules (modes/<id>/rules.gd), null in a carry round and in the lobby
var minigame_id := "" ## its mode id
var tandem: RefCounted ## the TANDEM experiment (modes/show/shared/tandem/tandem.gd): the lobby yard and a show's races; null until the first tick, its state is `tandem` in the match state
# --- walk-in lobby: occupancy comes from accepted owner positions, never from a client vote ---
var owner_positions := {} ## seat -> {epoch, position} of the last accepted owner pose
var owner_away := {} ## seat -> true while that owner's input says a menu/overlay covers the game
var lobby_zones := {} ## seat -> pad course id the seat stands on this tick (eligible seats only)
var lobby_pick := "" ## pad whose countdown runs ("" = none)
var lobby_ready := "" ## pad every joined player stands on, waiting for a PLAY press ("" = none)
var play_settled := false ## a player pressed PLAY with everybody on one pad: the roster counts as settled (JOIN_SETTLE does not apply) until the shared pad is gone
var play_course := "" ## pad a player on it pressed PLAY for; cleared when the shared pad changes

func _slot(seat: int) -> int:
	return int(slot_of.get(seat, -1))

func _sync_owner_epoch() -> void:
	if owner_epoch == simulation.reset_count: return
	owner_epoch = simulation.reset_count
	owner_expired.clear()
	owner_positions.clear() # positions of an older epoch say nothing about the reset world
	baseline_burst = BASELINE_BURST
	_reset_owner_streams()

func execute_command(seat: int, command: Dictionary, display_name: String) -> Dictionary:
	match str(command.get("c", "")):
		"join":
			if not simulation_ready or not Game.valid_match_mode(command.get("match_mode"),match_queue):
				return _refused(&"match_mode_mismatch")
			if phase != "lobby" and not joined.has(seat):
				return _refused(&"match_in_progress")
			_join_seat(seat, display_name)
			print("GW_PLAYER_JOINED seat=", seat, " name=", names.get(seat, ""), " players=", joined.size(), "/", seat_count)
			return _accepted({"seat": seat,"match_mode":match_mode,"seat_count":seat_count})
		"baseline_resync":
			if not simulation_ready or not joined.has(seat) or not resync_admission.admit(seat,elapsed):
				return _refused(&"baseline_resync_limited")
			baseline_burst = BASELINE_BURST
			return _accepted()
		"choose":
			var choice := str(command.get("v", ""))
			if phase != "results" or not joined.has(seat) or choice not in ["again", "menu"] or not seat in round_roster:
				return _refused(&"not_in_results")
			choices[seat] = choice
			print("GW_RESULTS_CHOICE seat=", seat, " choice=", choice)
			return _accepted()
		"end_run":
			# The pause menu's "End run": a level run stops after the level it is on (results, then the lobby again).
			if phase != "round" or not joined.has(seat) or not seat in round_roster or (level_run == null and minigame == null) or waiting_for_partner:
				return _refused(&"not_in_run")
			if minigame != null:
				print("GW_RUN_ENDED seat=", seat, " mode=", minigame_id)
				_end_round(false, "run_ended")
				return _accepted()
			print("GW_RUN_ENDED seat=", seat, " cleared=", level_run.cleared())
			_end_round(level_run.cleared() > 0, "run_ended")
			return _accepted()
		"restart":
			if not simulation_ready or phase != "round" or waiting_for_partner or minigame != null:
				return _refused(&"partner_required")
			restart_requested = true
			return _accepted()
		"play":
			# The walk-in start: a player standing on the pad everybody shares starts the countdown.
			var shared := WalkInLobby.shared_pick(join_order.filter(func(other: int) -> bool: return joined.has(other)).map(func(other: int) -> String: return str(lobby_zones.get(other, ""))))
			if phase != "lobby" or not joined.has(seat) or shared == "" or str(lobby_zones.get(seat, "")) != shared:
				return _refused(&"not_on_shared_pad")
			play_settled = true # the press is the consent: friends who are all on the pad start at once, no JOIN_SETTLE wait
			lobby_ready = shared
			play_course = lobby_ready
			print("GW_LOBBY_PLAY seat=", seat, " course=", play_course)
			return _accepted()
		"look":
			if not joined.has(seat) or not looks.store(seat, command.get("v")): return _refused(&"bad_look")
			return _accepted()
		"leave":
			# A closing client says so before its transport drops; Summer.client.leave() alone reaches
			# this authority only as a disconnect, which pauses the round for the reconnect grace.
			print("GW_PLAYER_QUIT seat=", seat)
			_request_leave(seat)
			return _accepted()
	return _refused(&"unknown_command")

static func _accepted(result: Dictionary = {}) -> Dictionary:
	return {"ok": true, "result": result, "reason": &""}

static func _refused(reason: StringName) -> Dictionary:
	return {"ok": false, "result": {}, "reason": reason}

## A seat's join command was accepted (shared by every transport).
func _join_seat(seat: int, display_name: String) -> void:
	var was_new := not joined.has(seat)
	joined[seat] = true
	names[seat] = display_name
	if was_new:
		ever_joined = true
		join_order.append(seat)
		joined_at[seat] = elapsed
		last_join_elapsed = elapsed
		baseline_burst = BASELINE_BURST
		if phase == "lobby" and simulation_ready:
			simulation.set_slot_active(seat, true) # lobby: slot == seat

func _leave_seat(seat: int, _reason: String) -> void:
	var slot := _slot(seat)
	if simulation_ready and slot >= 0:
		simulation.set_player_input(slot, Game.neutral_input())
		simulation.clear_authority_owner_pose(slot)
		resync_admission.forget(seat)
	var was_roster := seat in round_roster
	looks.forget(seat)
	joined.erase(seat)
	present.erase(seat)
	joined_at.erase(seat)
	owner_positions.erase(seat)
	owner_away.erase(seat)
	lobby_zones.erase(seat)
	disconnected.erase(seat)
	join_order.erase(seat)
	groups.erase(seat)
	worker_groups.erase(seat)
	owner_expired.erase(seat)
	revisions.erase(seat)
	fresh_at.erase(seat)
	relay_skip.erase(seat)
	input_sequences[seat] = 0
	print("GW_PLAYER_LEFT seat=", seat, " phase=", phase, " players=", joined.size())
	if phase == "lobby" and simulation_ready: simulation.set_slot_active(seat, false)
	elif phase == "round" and was_roster and not concluding:
		# A balloon team plays on without the player who left while two or more remain; a carry round needs both carriers.
		var remaining := round_roster.filter(func(member: int) -> bool: return joined.has(member)).size()
		if minigame != null and remaining >= maxi(Modes.min_players(minigame_id), 2) and slot >= 0:
			simulation.drop_slot(slot)
			minigame.drop(slot)
		elif minigame != null: _end_round.call_deferred(false, "player_left")
		elif play_mode == CourseSection.BALLOON and remaining >= 2 and slot >= 0: simulation.drop_slot(slot)
		else: _end_round.call_deferred(false, "player_left")
	if ever_joined and joined.is_empty() and phase != "ended": _conclude_world.call_deferred(false, "all_players_left")

func _disconnect_seat(seat: int) -> void:
	if seat >= 0:
		disconnected[seat] = true
		owner_positions.erase(seat) # a returning owner is placed again by its next accepted pose
		owner_away.erase(seat)
		var slot := _slot(seat)
		if simulation_ready and slot >= 0:
			simulation.set_player_input(slot, Game.neutral_input())
			simulation.freeze_authority_owner_pose(slot)

func _reconnect_seat(seat: int) -> void:
	disconnected.erase(seat)
	baseline_burst = BASELINE_BURST

func _expire_stale_input(seat: int) -> bool:
	if elapsed - float(fresh_at.get(seat,-1.0)) <= .35: return false
	var slot := _slot(seat)
	if slot >= 0: simulation.set_player_input(slot,Game.neutral_input())
	if not owner_expired.has(seat):
		owner_expired[seat] = true
		if slot >= 0: simulation.freeze_authority_owner_pose(slot)
	return true

## Both transports call this for every fresh owner input they admit. `menu` marks a seat whose
## player has a menu or overlay over the game: no walk-in countdown runs under it. `pose` is the
## owner pose accepted with that input ({} when none was): its position is the seat's place in
## the lobby yard. An input without an admitted pose clears the place: occupancy always comes
## from the newest admitted pose, never from an older one kept alive by later inputs.
func _note_owner_input(seat: int, command: Dictionary, pose: Dictionary) -> void:
	if bool(command.get("menu", false)): owner_away[seat] = true
	else: owner_away.erase(seat)
	if pose.is_empty(): owner_positions.erase(seat)
	else:
		owner_positions[seat] = {"epoch": int(pose.reset_epoch), "position": (pose.transform as Transform3D).origin}
		if not present.has(seat):
			present[seat] = true
			print("GW_PLAYER_PRESENT seat=", seat, " after_ms=", roundi((elapsed - float(joined_at.get(seat, elapsed))) * 1000.0))

## The pad a joined seat stands on for the walk-in rule ("" for none). Only a live owner counts:
## connected, input fresh, no menu open, latest input carried an admitted pose of this epoch.
func _seat_zone(seat: int) -> String:
	if not joined.has(seat) or disconnected.has(seat) or excluded.has(seat) or owner_expired.has(seat) or owner_away.has(seat): return ""
	# Enforce the existing owner-input TTL even if a transport group retired before
	# its expiry callback. Newer input without an admitted pose erases the note.
	if elapsed - float(fresh_at.get(seat, -1.0)) > .35: return ""
	var note: Dictionary = owner_positions.get(seat, {})
	if note.is_empty() or int(note.epoch) != simulation.reset_count: return ""
	return WalkInLobby.zone_at(note.position, str(lobby_zones.get(seat, "")))

# ------------------------------------------------------------------ phases

func _identity_slots() -> Array:
	var list := []
	for seat in simulation.carrier_count: list.append(seat if joined.has(seat) else -1)
	return list

func _set_slots(list: Array) -> void:
	slots = list
	slot_of.clear()
	for slot in slots.size():
		if int(slots[slot]) >= 0: slot_of[int(slots[slot])] = slot

## Players who chose Play Again come back on their yard spots (a new epoch): nobody stands on a
## pad, so the next round needs another walk-in.
func _enter_lobby() -> void:
	phase = "lobby"
	lobby_since = elapsed
	start_at = -1.0
	lobby_pick = ""
	lobby_ready = ""
	play_course = ""
	lobby_zones.clear()
	level_run = null
	level_clearing = false
	minigame = null
	minigame_id = ""
	round_roster = []
	excluded = excluded.duplicate()
	waiting_for_partner = false
	_set_slots(_identity_slots())
	var active := []
	for slot in simulation.carrier_count: active.append(int(slots[slot]) >= 0)
	simulation.configure_phase("lobby", active)
	print("GW_LOBBY_OPEN players=", joined.size())

func _begin_round() -> void:
	var roster: Array = []
	for seat: int in join_order:
		if joined.has(seat) and present.has(seat) and not disconnected.has(seat) and not excluded.has(seat): roster.append(seat)
	if roster.size() < 2: return
	var mode := Modes.current()
	if Modes.is_minigame(mode) and roster.size() < Modes.min_players(mode):
		print("GW_MODE_TOO_FEW mode=", mode, " players=", roster.size(), " min=", Modes.min_players(mode))
		start_at = -1.0
		lobby_pick = ""
		play_course = ""
		return
	round_roster = roster
	round_mode = "minigame" if Modes.is_minigame(mode) else "level"
	play_mode = CourseSection.play_mode_for(roster.size())
	var list := []
	for slot in simulation.carrier_count: list.append(int(roster[slot]) if slot < roster.size() else -1)
	_set_slots(list)
	var active := []
	for slot in simulation.carrier_count: active.append(slot < roster.size())
	round_number += 1
	round_success = false
	round_reason = ""
	results_rows = []
	choices.clear()
	start_at = -1.0
	lobby_pick = ""
	lobby_ready = ""
	play_course = ""
	lobby_zones.clear()
	level_run = null
	level_clearing = false
	level_next_at = -1.0
	round_time = 0.0
	if round_mode == "minigame":
		_begin_minigame(mode, roster, active)
		return
	level_run = _new_level_run()
	level_run.play_mode = play_mode
	round_plan = CourseSection.plan(course, level_run.level(), play_mode)
	simulation.set_course_plan(round_plan)
	simulation.configure_phase(round_mode, active)
	phase = "round"
	round_started_elapsed = elapsed
	print("GW_ROUND_START round=", round_number, " mode=", round_mode, " play=", play_mode, " players=", roster.size(), " roster=", roster, " course=", round_plan.course, " level=", round_plan.level)
	print("GW_MATCH_STARTED players=", roster.size(), " authority_owned=true")

## A minigame round: the shell stays in its yard ("lobby" phase: contact and props run; a new epoch puts everybody on their
## spots), the mode's rules (modes/<id>/rules.gd) run every tick and their state rides in match.minigame.
func _begin_minigame(mode: String, roster: Array, active: Array) -> void:
	minigame_id = mode
	round_plan = {"course": course, "level": -1, "play_mode": play_mode, "time_limit": -1.0}
	simulation.configure_phase("lobby", active)
	minigame = Modes.new_rules(mode)
	var host := ModeHost.new(simulation, roster, int(round_number * 7919 + roster.size() * 131 + int(elapsed * 1000.0)))
	host.pick = str(WalkInLobby.pad(round_pick).get("pick", ""))
	minigame.start(host)
	phase = "round"
	round_started_elapsed = elapsed
	print("GW_ROUND_START round=", round_number, " mode=minigame id=", mode, " players=", roster.size(), " roster=", roster)
	print("GW_MATCH_STARTED players=", roster.size(), " authority_owned=true")

## Walk-in start: every joined player stands on the same pad (and nobody joined in the last
## JOIN_SETTLE seconds, or the lobby is full, or a player's PLAY press settles it) -> a player on it presses PLAY -> COUNTDOWN (none) -> round on that pad's course. Any
## change of the shared pad (someone steps off, crosses to the other pad, leaves, disconnects,
## opens a menu) cancels the countdown; a new shared pad starts a fresh one.
func _tick_lobby() -> void:
	var identity := _identity_slots() # lobby: slot == seat for everyone who joined
	if identity != slots: _set_slots(identity)
	var zones := []
	var now := {}
	for seat: int in join_order:
		if not joined.has(seat): continue
		var zone := _seat_zone(seat)
		if zone != str(lobby_zones.get(seat, "")): print("GW_LOBBY_ZONE seat=", seat, " zone=", zone if zone != "" else "none", " t=", snappedf(elapsed, 0.01))
		if zone != "": now[seat] = zone
		zones.append(zone)
	lobby_zones = now
	if WalkInLobby.shared_pick(zones) == "": play_settled = false
	var settled := joined.size() >= seat_count or elapsed - last_join_elapsed >= JOIN_SETTLE or play_settled
	var ready := WalkInLobby.shared_pick(zones) if settled else ""
	if ready != lobby_ready:
		lobby_ready = ready
		play_course = "" # a new shared pad (or none) needs its own PLAY
	var pick := ready if play_course == ready else ""
	if pick != lobby_pick:
		if lobby_pick != "": print("GW_LOBBY_COUNTDOWN_CANCEL course=", lobby_pick, " left=", snappedf(maxf(start_at - elapsed, 0.0), 0.01))
		lobby_pick = pick
		start_at = elapsed + WalkInLobby.COUNTDOWN if pick != "" else -1.0
		if pick != "":
			round_pick = pick
			if CourseSection.valid(pick): course = pick
			print("GW_LOBBY_COUNTDOWN course=", pick, " seconds=", WalkInLobby.COUNTDOWN, " players=", zones.size())
	if start_at >= 0.0 and elapsed >= start_at:
		_begin_round()
	elif elapsed - lobby_since > LOBBY_IDLE_SECONDS:
		_conclude_world.call_deferred(false, "lobby_timeout")

## The TANDEM experiment (docs/party-show.md "Tandem (experiment)"): the lobby yard (everybody who joined) and a show's races (the racers on course) may fuse; nothing else does.
func _tick_tandem(dt: float) -> void:
	if Modes.current() != "show": return
	if tandem == null: tandem = Tandem.new(simulation)
	var scope := ""
	var eligible: Array = []
	var solo := false
	if phase == "lobby":
		scope = "lobby"
		for seat: int in joined: eligible.append(seat) # lobby: slot == seat
		solo = joined.size() <= 1
	elif phase == "round" and minigame != null and minigame.has_method("tandem_ok") and not waiting_for_partner:
		scope = "race"
		for slot in minigame.host.count:
			if minigame.tandem_ok(slot): eligible.append(slot)
		solo = minigame.tandem_solo()
	tandem.tick(dt, scope, eligible, solo)

func _tick_round() -> void:
	if minigame != null:
		# A minigame plays on without a disconnected player (its courier stands still until it returns).
		round_time += get_physics_process_delta_time()
		minigame.tick(get_physics_process_delta_time())
		if minigame.finished(): _end_round(true, "mode_done")
		return
	# A carry round waits for a disconnected carrier; a balloon team plays on (that courier stands still until it returns).
	var missing := not disconnected.is_empty() and play_mode != CourseSection.BALLOON
	if missing and not waiting_for_partner:
		resume_after_partner = simulation.playing
		simulation.playing = false # the shell advances neither the round clock nor the hazards while it is not playing
		waiting_for_partner = true
		print("GW_PARTNER_PAUSE")
	elif not missing and waiting_for_partner:
		waiting_for_partner = false
		simulation.playing = resume_after_partner
		print("GW_PARTNER_RESUME")
	if restart_requested:
		restart_requested = false
		if not waiting_for_partner: simulation.restart_delivery()
	if not waiting_for_partner: round_time += get_physics_process_delta_time()
	_tick_levels()

## A level run: a cleared level (the goal reached with the intact painting) shows its card for LevelRun.CLEARED_SECONDS, then the
## next level of the run starts (a new epoch: the couriers stand on that level's start). The last level of a time attack ends the run.
func _tick_levels() -> void:
	if waiting_for_partner: return
	if level_clearing:
		if elapsed >= level_next_at: _start_level()
	elif simulation.won:
		var breaks: int = simulation.breaks # the level's breaks (carry) or pops (balloon)
		var seconds: float = simulation.elapsed_seconds
		var finished_level := CourseSection.level_title(level_run.level())
		var more: bool = level_run.level_cleared(seconds, breaks)
		print("GW_LEVEL_CLEARED run=", level_run.mode, " level=", finished_level, " seconds=", snappedf(seconds, 0.01), " cleared=", level_run.cleared(), " more=", more)
		if more:
			level_clearing = true
			level_next_at = elapsed + LevelRun.CLEARED_SECONDS
		else: _end_round(true, "run_completed")

## Starts the level the run is on: its plan, a new epoch, the level clock at zero.
func _start_level() -> void:
	level_clearing = false
	level_next_at = -1.0
	round_plan = CourseSection.plan(course, level_run.level(), play_mode)
	var active := []
	for slot in simulation.carrier_count: active.append(slot < round_roster.size())
	simulation.set_course_plan(round_plan)
	simulation.configure_phase(round_mode, active)
	print("GW_LEVEL_START run=", level_run.mode, " number=", level_run.number(), " level=", level_run.level() + 1, " title=", CourseSection.level_title(level_run.level()))

func _end_round(success: bool, reason: String) -> void:
	if phase != "round": return
	phase = "results"
	round_success = success
	round_reason = reason
	waiting_for_partner = false
	simulation.playing = false
	if minigame != null: _build_mode_results(reason)
	else: _build_level_results(success, reason)
	choices.clear()
	for seat: int in round_roster:
		if not joined.has(seat): choices[seat] = "gone"
	results_deadline = elapsed + RESULTS_SECONDS
	print("GW_ROUND_END round=", round_number, " mode=", round_mode, " success=", success, " reason=", reason, " sub=", results_sub)
	for row: Dictionary in results_rows:
		print("GW_RESULT_ROW seat=", row.seat, " name=", row.name, " time=", snappedf(float(row.time), 0.01), " breaks=", row.breaks, " arrived=", row.arrived)

## The results of a level run (levels/level_run.gd): every player's row carries the run's total time; the headline and the
## sub line name the run, the level list rides in match.run.
func _build_level_results(success: bool, reason: String) -> void:
	results_rows = []
	var done: int = level_run.cleared()
	for slot in round_roster.size():
		var seat := int(round_roster[slot])
		results_rows.append({"seat": seat, "name": str(names.get(seat, "Player %d" % (seat + 1))), "time": level_run.total() if done > 0 else -1.0, "panes_intact": -1,
			"breaks": level_run.breaks, "arrived": success and done > 0})
	results_headline = level_run.headline()
	results_sub = level_run.summary(reason == "player_left")

## The results of a minigame: its headline and score line; no row arrives (the page shows the headline, not the delivered word).
func _build_mode_results(reason: String) -> void:
	var outcome: Dictionary = minigame.results()
	var scores: Array = outcome.get("scores", [])
	results_rows = []
	var ranks: Array = Modes.ranks(outcome, round_roster.size())
	for slot in round_roster.size():
		var seat := int(round_roster[slot])
		var score := int(scores[slot]) if slot < scores.size() else 0
		results_rows.append({"seat": seat, "name": str(names.get(seat, "Player %d" % (seat + 1))), "time": -1.0, "panes_intact": -1,
			"breaks": score, "arrived": false, "rank": int(ranks[slot]), "points": score})
	results_headline = str(outcome.get("headline", "")) if str(outcome.get("headline", "")) != "" else str(Modes.info(minigame_id).get("title", "")).to_upper()
	results_sub = str(outcome.get("sub", ""))
	if reason == "player_left": results_sub = "A player left  ·  " + results_sub

func _tick_results() -> void:
	var undecided := 0
	for seat: int in round_roster:
		if joined.has(seat) and not choices.has(seat): undecided += 1
	if undecided > 0 and elapsed < results_deadline: return
	var again: Array = []
	excluded.clear()
	for seat: int in round_roster:
		if not joined.has(seat): continue
		if choices.get(seat, "") == "again": again.append(seat)
		else:
			choices[seat] = "gone"
			excluded[seat] = true # told to leave through the snapshot; skipped by the next round
	if again.size() < 2:
		print("GW_RESULTS_DONE again=", again.size(), " -> world completes")
		_conclude_world.call_deferred(round_success, "players_left")
		return
	print("GW_RESULTS_DONE again=", again.size(), " -> lobby")
	_enter_lobby()

# ------------------------------------------------------------------ world end

func _physics_process(dt: float) -> void:
	if not simulation_ready: return
	if phase == "ended": return
	elapsed += dt
	_sync_owner_epoch()
	match phase:
		"round": _tick_round()
		"results": _tick_results()
	_apply_owner_poses()
	_tick_tandem(dt)
	# The walk-in decision uses the positions admitted in this very tick: a player who stepped off
	# (or opened a menu) at the countdown deadline is seen before the round can start.
	if phase == "lobby": _tick_lobby()
	_sync_owner_epoch() # A restart or round start may have advanced the epoch during this tick.
	send_time += dt
	stats_time += dt
	if send_time >= SNAPSHOT_PERIOD:
		send_time = 0.0
		_publish()

func _match_state() -> Dictionary:
	var joined_mask := 0
	var ready_mask := 0
	var name_list := []
	var zone_list := [] ## per seat: the pad course it stands on ("" = none)
	for seat in seat_count:
		if joined.has(seat): joined_mask |= 1 << seat
		if present.has(seat): ready_mask |= 1 << seat
		name_list.append(str(names.get(seat, "")) if joined.has(seat) else "")
		zone_list.append(str(lobby_zones.get(seat, "")) if phase == "lobby" else "")
	var start_in := -1.0
	if start_at >= 0.0: start_in = maxf(start_at - elapsed, 0.0)
	var result := {"phase": phase, "round": round_number, "mode": round_mode, "play_mode": play_mode, "seats": seat_count, "slots": slots, "names": name_list,
		"joined": joined_mask, "ready": ready_mask, "zones": zone_list, "pick": lobby_pick, "ready_pad": lobby_ready if phase == "lobby" else "", "start_in": start_in,
		"course": course, "round_course": str(round_plan.get("course", "")), "level": int(round_plan.get("level", -1)),
		"time_limit": float(round_plan.get("time_limit", -1.0)), "round_time": round_time,
		"time_left": maxf(float(round_plan.get("time_limit", -1.0)) - round_time, 0.0) if float(round_plan.get("time_limit", -1.0)) > 0.0 else -1.0}
	if level_run != null: result["run"] = level_run.state(level_clearing, maxf(level_next_at - elapsed, 0.0) if level_clearing else -1.0)
	if minigame != null:
		result["minigame_id"] = minigame_id
		result["minigame"] = minigame.state()
	if tandem != null and tandem.active: result["tandem"] = tandem.state()
	looks.publish(result, seat_count, baseline_burst > 0)
	if phase == "results" or phase == "ended":
		var choice_list := []
		for seat in seat_count: choice_list.append(str(choices.get(seat, "")))
		result["choices"] = choice_list
		result["choose_in"] = maxf(results_deadline - elapsed, 0.0)
		result["rows"] = results_rows
		result["headline"] = results_headline
		result["sub"] = results_sub
		result["success"] = round_success
		result["excluded"] = excluded.keys()
		result["reason"] = round_reason
	return result


# Transport hooks. Each concrete adapter supplies its own external effects.
func _reset_owner_streams() -> void: pass
func _request_leave(_seat: int) -> void: pass
func _apply_owner_poses() -> void: pass
func _publish() -> void: pass
func _conclude_world(_success: bool, _reason: String) -> void: pass

## The run a round on `course` plays, from the levels that suit the round's play mode. The offline lab overrides it with an
## ordered run it can travel in.
func _new_level_run() -> RefCounted:
	var pool := CourseSection.pool_levels(play_mode)
	if pool.is_empty(): push_warning("GW_NO_LEVELS_FOR_MODE " + play_mode + ": the run draws from every level")
	return LevelRun.new(course, CourseSection.level_count(), -1, pool)
