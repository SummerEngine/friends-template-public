extends RefCounted
## Balloon mode and players touching players, for the simulation shell (game/game_run.gd) in its three roles.
##   balloon  a round of 3+ players (or the dev switch, course_section.gd): one BalloonSim kept in the air from the start pad to
##            the goal. Authority and local step it with the couriers' capsules. A pop (a floor, a "hit" block or hazard, a kill
##            volume, falling out) shows the POP! card; after BalloonSim.RESPAWN_SECONDS the shell starts a new epoch and the team
##            and the balloon restart at the last checkpoint the balloon passed (else the start). It hangs still over the spot
##            until somebody touches it. The goal is cleared when the balloon enters the goal volume. The replica draws the
##            authority's balloon and moves it on between snapshots with the same sim, without players and without pops.
##   contact  shoves everywhere: every owner runs them for its own courier against the others as it draws them (the local role
##            runs all couriers). Grabs, throws and escapes in the lobby yard and in balloon rounds (carriers hold the glass), decided by the authority from the owners'
##            GRAB / JUMP presses; it publishes held_by and a cumulative kick per slot, the owner applies the change.
##   props    the lobby yard's loose props (lobby_space.gd LOOSE_PROPS, players/prop_sim.gd): authority and local step them after the
##            contact; a prop holder's GRAB throws it, a press the contact did nothing with picks one up, a grabbed holder drops it.
##            Every lobby snapshot carries `props`; clients draw them (players/prop_look.gd), a carried one in its holder's hands.
##   slap     in balloon rounds a GRAB press near the balloon, with no free player in front to grab, is a slap: the owner tells it
##            apart (slap_seq on the input wire) and swings the arm at once; the authority checks the reach and a per-player cooldown and
##            lifts the balloon SLAP_HIT_TIME later, up and along the slapper's facing (BalloonSim.slap). Every client swings that
##            player's arm from the `slaps` counter of the snapshot (rig.slap(side), when the rig has it).
##   A courier in a kill volume during a balloon round respawns alone at the team's spot (a respawn count per slot, the owner
##   teleports when it goes up); so does one a laser zaps or a fire jet burns (in a carry round that breaks the painting instead,
##   game_run.gd). Every zap and burn counts per slot (`scorches`, in every snapshot): each client shows the comic word over that
##   player (TeamCast words "zap", "burnt"; style/hazard_looks.gd).
const BalloonSim = preload("res://balloon/balloon_sim.gd")
const PlayerContact = preload("res://players/player_contact.gd")
const PropSim = preload("res://players/prop_sim.gd")
const PropLook = preload("res://players/prop_look.gd")
const LobbySpace = preload("res://lobby_space.gd")
const TeamCast = preload("res://style/team_cast.gd")
const HazardLooks = preload("res://style/hazard_looks.gd")
const SCORCH_CODES := {"zap": 1, "burn": 2} ## the kind of a slot's last scorch on the wire
const SCORCH_WORDS := {1: "zap", 2: "burnt"}
const WORD_HEIGHT := 2.4 ## m above a courier's feet
const SLAP_HIT_TIME := 0.1 ## s from the press to the hit: CharacterRig.SLAP_HIT_TIME (the authority has no rig to ask)
const SLAP_COOLDOWN := 0.6 ## s per player between two slaps
const SLAP_SLACK := 0.75 ## m the authority adds to BalloonSim.SLAP_REACH: the owner chose on a balloon it draws a moment late
const SLAP_SIDES := {-1: 1, 1: 2} ## the hand of a slap on the wire: 1 left, 2 right
const CENTRE := Vector3(0.0, 0.9, 0.0) ## capsule centre above the courier's feet
const WORLD_MASK := 1 | 16 ## level blocks and movers: the balloon bounces off them and pops on their tops
const POP_MASK := 8 ## "hit" blocks and hazards: touching one pops the balloon
const POP_REACH := 0.05 ## the pop test reaches this far past the balloon's skin (the sweep stops at the contact)
const FAR := Vector3(0.0, -10000.0, 0.0) ## an inactive slot: out of everybody's reach
const RESPAWN_GRACE := 1.0 ## s after a personal respawn without a kill test (late poses of the fall)
const STAGGER_MOVE := 0.3 ## share of the move input a staggered courier keeps (it slides as on ice)
const SNAP_DISTANCE := 3.0 ## replica: the drawn balloon jumps instead of gliding to a state this far away
const FOLLOW_SPEED := 15.0 ## replica: 1/s, how fast the drawn balloon closes on the simulated one

var run ## the shell
var count := 0
var balloon: BalloonSim
var view: BalloonSim ## what is drawn: the balloon itself, on the replica a smoothed copy
var look: Node3D
var contact: PlayerContact
var props: PropSim ## the lobby yard's loose props (the replica's: the authority's, from the snapshot)
var prop_look: Node3D
var prop_counts := {"pick": 0, "throw": 0, "knock": 0} ## authority / local
var checkpoint := -1 ## index of the last checkpoint the balloon passed this level, -1 = the start
var results: Array = [] ## authority / local: the contact result of every slot this tick
var kicks: Array = [] ## authority: per slot, the sum of the contact impulses of this epoch
var respawns: Array = [] ## authority: per slot, personal respawns this epoch
var respawn_points: Array = []
var _grace: Array = []
var _counts := {} ## authority: slot -> [jump_seq, grab_seq] of the last input (presses are the change)
var _presses: Array = [] ## local: per slot [jumps, grabs] since the last tick
var _pop_shape := SphereShape3D.new()
var _epoch := -1 ## replica: the epoch of the kicks and respawns below
var _kick_seen := Vector3.ZERO
var _respawn_seen := 0
var _pending_kick := Vector3.ZERO
var _pending_teleport: Variant = null
var _heard := {} ## replica: counter -> last value heard (sounds of the authority's events)
var scorches := PackedInt32Array() ## authority / local: per slot [zaps and burns so far, kind of the last] (never reset: clients diff it)
var _scorches_seen := PackedInt32Array() ## replica: the counts its words were shown for (empty until the first snapshot)
var slap_counts := PackedInt32Array() ## authority / local: per slot [slaps so far, hand of the last] (never reset: clients diff it)
var _slaps_seen := PackedInt32Array() ## replica: the counts its arm swings were started for
var _slap_cooldown: Array = [] ## authority / local: per slot seconds until the next slap counts
var _slap_due: Array = [] ## authority / local: per slot seconds until a slap's hit, -1 none
var slaps_shown := 0 ## client roles: arm swings started (the checks read it)

func _init(shell) -> void:
	run = shell
	count = run.carrier_count
	balloon = BalloonSim.new()
	balloon.world_mask = WORLD_MASK
	props = PropSim.new(LobbySpace.loose_props())
	view = balloon
	_pop_shape.radius = BalloonSim.RADIUS + POP_REACH
	scorches.resize(count * 2)
	slap_counts.resize(count * 2)
	for slot in count:
		_slap_cooldown.append(0.0)
		_slap_due.append(-1.0)
	clear()

## Balloon rules apply: a level round in balloon mode.
func active() -> bool:
	return run.play_mode == "balloon" and run.round_mode != "lobby"

## Players grab, lift, throw and escape in the lobby yard, in balloon rounds (carriers hold the glass in a carry round) and in the show's rounds, except a tile stage round (no grab, no dash: they bump, docs/party-show.md).
func grabs_allowed() -> bool:
	return (active() or run.round_mode == "lobby" or run.play_mode == "show") and not run.stage_round()

## Client roles: the drawn balloon (hidden outside balloon rounds).
func build_look(world: Node3D) -> void:
	look = load("res://balloon/balloon_look.gd").new()
	look.name = "Balloon"
	world.add_child(look)
	look.visible = false
	if run.network_role == "replica": view = BalloonSim.new()
	prop_look = PropLook.new()
	prop_look.name = "LooseProps"
	world.add_child(prop_look)
	prop_look.build(props)
	prop_look.visible = false

## A new epoch: contact state, kicks and respawn counts start over.
func clear() -> void:
	contact = PlayerContact.new(count)
	contact.shoves = run.network_role != "authority"
	contact.grabs = run.network_role != "replica"
	results = []
	kicks = []
	respawns = []
	respawn_points = []
	_grace = []
	_presses = []
	for slot in count:
		results.append({})
		kicks.append(Vector3.ZERO)
		respawns.append(0)
		respawn_points.append(Vector3.ZERO)
		_grace.append(0.0)
		_presses.append([0, 0, 0])
	_counts.clear()
	for slot in _slap_due.size():
		_slap_due[slot] = -1.0
		_slap_cooldown[slot] = 0.0

## Authority / local, from the shell's _reset (the couriers stand on their spots): the balloon hangs over the team's spot.
func reset(spot: Vector3) -> void:
	clear()
	balloon.respawn_point = spot
	balloon.reset()
	balloon.hover = true
	props.reset()

func held_by(slot: int) -> int:
	return contact.held_by[slot] if slot >= 0 and slot < contact.count else -1

# ------------------------------------------------------------------ contact: authority and local

## Local: JUMP, GRAB and slap presses of a seat since the last tick (escape presses count while held).
func note_presses(slot: int, jumps: int, grabs: int, slaps := 0) -> void:
	if slot < 0 or slot >= count: return
	_presses[slot] = [mini(int(_presses[slot][0]) + jumps, 8), mini(int(_presses[slot][1]) + grabs, 8), mini(int(_presses[slot][2]) + slaps, 8)]

func _press_edges(slot: int) -> Array:
	if run.network_role == "authority":
		var command: Dictionary = run.player_input(slot)
		if int(command.get("seq", 0)) < 1 or not command.has("grab_seq"):
			_counts.erase(slot) # an epoch's neutral or fenced input: the next real one sets the counters again
			return [0, 0, 0]
		var now := [int(command.get("jump_seq", 0)), int(command.get("grab_seq", 0)), int(command.get("slap_seq", 0))]
		var before: Array = _counts.get(slot, now)
		_counts[slot] = now
		return [clampi(now[0] - int(before[0]), 0, 8), clampi(now[1] - int(before[1]), 0, 8), clampi(now[2] - int(before[2]), 0, 8)]
	var pressed: Array = _presses[slot]
	_presses[slot] = [0, 0, 0]
	return pressed

## Local and replica owner: `grabs` GRAB presses of `slot` split into [grabs, slaps]. In a balloon round a press is a slap when the
## balloon is in reach and no free player stands in front to grab. The replica owner swings its own arm at once; the local role
## swings it when the slap counts (step_contact).
func split_grabs(slot: int, grabs: int) -> Array:
	if grabs <= 0: return [0, 0]
	var side := slap_side(slot)
	if side == 0: return [grabs, 0]
	if run.network_role == "replica": _swing(slot, side)
	return [0, grabs]

## The hand (-1 left, +1 right) a GRAB press of `slot` would slap the balloon with now, 0 when it is a grab.
func slap_side(slot: int) -> int:
	if not active() or not balloon.alive or slot < 0 or slot >= count or held_by(slot) >= 0: return 0
	var body: CharacterBody3D = run.actors[slot]
	if balloon.gap_to(body.global_position + CENTRE) > BalloonSim.SLAP_REACH: return 0
	var facing := _facing(slot)
	for other in count:
		if other == slot or not run.is_slot_active(other) or held_by(other) >= 0 or contact.holding(other) >= 0: continue
		var offset: Vector3 = (run.actors[other].global_position - body.global_position) * Vector3(1, 0, 1)
		if absf(run.actors[other].global_position.y - body.global_position.y) > 1.0 or offset.length() >= PlayerContact.GRAB_RANGE: continue
		if offset.length() < 0.01 or facing.dot(offset.normalized()) >= PlayerContact.GRAB_FRONT: return 0 # a free player to grab
	var toward := (balloon.position - body.global_position) * Vector3(1, 0, 1)
	return 1 if toward.dot(Vector3(-facing.z, 0.0, facing.x)) >= 0.0 else -1

## Where a courier faces (flat, unit): yaw 0 faces -Z.
func _facing(slot: int) -> Vector3:
	var forward: Vector3 = -(run.actors[slot] as Node3D).global_basis.z * Vector3(1, 0, 1)
	return forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD

## Client roles: the slap's arm swing on `slot`'s rig (only rigs that have one).
func _swing(slot: int, side: int) -> void:
	var rig: Node3D = run.rigs[slot] if slot < run.rigs.size() else null
	if rig == null or not rig.has_method("slap"): return
	rig.slap(side)
	slaps_shown += 1

## Authority / local: a slap press of `slot`: it counts unless the player's cooldown runs; the hit follows SLAP_HIT_TIME later.
func _start_slap(slot: int) -> void:
	if not active() or float(_slap_cooldown[slot]) > 0.0: return
	_slap_cooldown[slot] = SLAP_COOLDOWN
	_slap_due[slot] = SLAP_HIT_TIME
	var side := slap_side(slot)
	if side == 0: side = 1
	slap_counts[slot * 2] += 1
	slap_counts[slot * 2 + 1] = SLAP_SIDES[side]
	if run.network_role == "local": _swing(slot, side)
	print("GW_SLAP_START slot=", slot, " side=", side)

## Authority / local, each tick of a balloon round: cooldowns, and the hits whose time has come (in reach: the lift).
func _tick_slaps(delta: float) -> void:
	for slot in count:
		_slap_cooldown[slot] = maxf(float(_slap_cooldown[slot]) - delta, 0.0)
		if float(_slap_due[slot]) < 0.0: continue
		_slap_due[slot] = float(_slap_due[slot]) - delta
		if float(_slap_due[slot]) > 0.0: continue
		_slap_due[slot] = -1.0
		var body: CharacterBody3D = run.actors[slot]
		var reach := BalloonSim.SLAP_REACH + (SLAP_SLACK if run.network_role == "authority" else 0.0)
		if not run.is_slot_active(slot) or not balloon.alive or balloon.gap_to(body.global_position + CENTRE) > reach:
			print("GW_SLAP_MISS slot=", slot)
			continue
		var facing := _facing(slot)
		var toward := (balloon.position - body.global_position) * Vector3(1, 0, 1)
		if toward.length() > 0.01 and facing.dot(toward.normalized()) < 0.0: facing = toward.normalized() # behind the slapper: away from it
		balloon.slap(facing)
		if run.audio != null: run.audio.play_bounce()
		print("GW_SLAP slot=", slot, " velocity=", balloon.velocity)

## Authority / local, once per tick before the couriers move (authority: after the owner poses were applied). Fills `results`.
func step_contact(delta: float) -> void:
	contact.stage = run.stage_round()
	contact.power = run.shove_power()
	contact.partners = run.tandem_partners()
	var grabbing := grabs_allowed()
	if grabbing != contact.grabs:
		contact.grabs = grabbing
		if not grabbing:
			for slot in count: contact.release(slot)
	var states := []
	var lobby: bool = run.round_mode == "lobby"
	var prop_grabs: Array[bool] = [] # a prop holder's GRAB throws the prop instead of reaching the contact
	for slot in count:
		var edges := _press_edges(slot)
		prop_grabs.append(false)
		if not run.is_slot_active(slot):
			contact.release(slot)
			states.append({"position": FAR + Vector3(slot * 10.0, 0.0, 0.0), "velocity": Vector3.ZERO})
			continue
		var body: CharacterBody3D = run.actors[slot]
		prop_grabs[slot] = lobby and int(edges[1]) > 0 and props.holding(slot) >= 0
		states.append({"position": body.global_position + CENTRE, "velocity": body.velocity, "jump": int(edges[0]) > 0, "grab": int(edges[1]) > 0 and not prop_grabs[slot]})
		if int(edges[2]) > 0: _start_slap(slot)
	if run.network_role == "authority" and not contact.grabs: return # the authority runs no shoves: only grabs need it
	var stepped: Dictionary = contact.step(delta, states)
	results = stepped.results
	for event: Dictionary in stepped.events:
		if event.kind != "shove": print("GW_CONTACT ", event.kind, " player=", event.player, " other=", event.other)
		if event.kind == "throw" and run.audio != null: run.audio.play_push()
	if run.network_role == "authority":
		for slot in count: kicks[slot] += results[slot].impulse
	if not lobby: return
	for slot in count:
		if bool(states[slot].get("grab", false)) and PropSim.leftover_grab(stepped.events, slot): prop_grabs[slot] = true
	_step_props(delta, prop_grabs)

## Authority / local, each lobby tick after the contact: the loose props with every courier's hands (a held courier drops its prop).
func _step_props(delta: float, grabs: Array[bool]) -> void:
	var hands := []
	for slot in count:
		var body: CharacterBody3D = run.actors[slot]
		hands.append({"position": body.global_position, "facing": _facing(slot), "velocity": body.velocity, "grab": grabs[slot],
			"active": run.is_slot_active(slot) and held_by(slot) < 0})
	for event: Dictionary in props.step(delta, run.world.get_world_3d().direct_space_state, hands):
		prop_counts[event.kind] = int(prop_counts.get(event.kind, 0)) + 1
		print("GW_PROP ", event.kind, " prop=", event.prop, " player=", event.player)
		if run.audio != null: run.audio.play_prop(event)

# ------------------------------------------------------------------ contact on a simulated courier (local, replica owner)

## A held courier rides above its holder this tick (no movement of its own). True when it was placed.
func place_held(slot: int, simulated := true) -> bool:
	var holder := held_by(slot)
	if holder < 0 or holder >= count or not run.is_slot_active(holder): return false
	var body: CharacterBody3D = run.actors[slot]
	var above: Vector3 = run.actors[holder].global_position + Vector3.UP * PlayerContact.HOLD_HEIGHT
	if simulated and run.motions[slot] != null: run.motions[slot].teleport(body, above)
	else: body.global_position = above
	body.velocity = run.actors[holder].velocity
	return true

## Separation and impulse of a contact result (before the level's own launches, which win).
func push(slot: int, result: Dictionary) -> void:
	var body: CharacterBody3D = run.actors[slot]
	var separate: Vector3 = result.get("separate", Vector3.ZERO)
	if separate != Vector3.ZERO: body.move_and_collide(separate)
	var impulse: Vector3 = result.get("impulse", Vector3.ZERO)
	if impulse != Vector3.ZERO: run.motions[slot].launch(impulse, false, false)

## The move input after a contact result: a staggered courier slides and barely steers, a holder walks slower.
func steer(slot: int, result: Dictionary, move: Vector2) -> Vector2:
	if float(result.get("stagger", 0.0)) > 0.0:
		run.motions[slot].set_surface({"ice": true})
		move *= STAGGER_MOVE
	return move * float(result.get("speed_scale", 1.0))

func result(slot: int) -> Dictionary:
	return results[slot] if slot >= 0 and slot < results.size() else {}

## Replica: the owner's own shove against the others as this client draws them (the authority runs no shoves).
func owner_contact(seat: int, delta: float) -> Dictionary:
	contact.stage = run.stage_round()
	contact.power = run.shove_power()
	contact.partners = run.tandem_partners()
	var states := []
	for slot in count:
		var shown: bool = run.is_slot_active(slot) and (slot == seat or not run.is_peer_hidden(slot))
		var body: CharacterBody3D = run.actors[slot]
		states.append({"position": body.global_position + CENTRE if shown else FAR + Vector3(slot * 10.0, 0.0, 0.0), "velocity": body.velocity if shown else Vector3.ZERO})
	return (contact.step(delta, states).results as Array)[seat]

## Replica: kicks and respawns the authority sent for the owner's courier, applied before its step.
func owner_pending(seat: int) -> void:
	var motion = run.motions[seat]
	var body: CharacterBody3D = run.actors[seat]
	if _pending_teleport is Vector3:
		var facing: float = run.level_world.facing_at(run.current_level(), _pending_teleport, motion.yaw) if run.level_world != null else motion.yaw
		motion.reset(body, _pending_teleport, facing)
		run.face_camera(seat, facing)
		print("GW_OWNER_RESPAWN seat=", seat, " at=", _pending_teleport)
	_pending_teleport = null
	if _pending_kick != Vector3.ZERO:
		motion.launch(_pending_kick, false, false)
		if run.audio != null: run.audio.play_push()
	_pending_kick = Vector3.ZERO

# ------------------------------------------------------------------ balloon: authority and local

## Once per tick of a balloon round, after the couriers moved: the balloon, its pops, checkpoints and goal, personal respawns.
func tick_balloon(delta: float) -> void:
	_tick_slaps(delta)
	var level: int = run.current_level()
	var levels = run.level_world
	if balloon.alive:
		var capsules := []
		for slot in count:
			var body: CharacterBody3D = run.actors[slot]
			capsules.append({"position": body.global_position + CENTRE if run.is_slot_active(slot) else Vector3.INF, "velocity": body.velocity})
		var space: PhysicsDirectSpaceState3D = run.world.get_world_3d().direct_space_state
		for event: Dictionary in balloon.step(delta, space, capsules): _balloon_event(event)
		if balloon.alive:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _pop_shape
			query.transform = Transform3D(Basis.IDENTITY, balloon.position)
			query.collision_mask = POP_MASK
			if not space.intersect_shape(query, 1).is_empty(): _balloon_event(balloon.pop())
			elif levels.point_zone(level, balloon.position) == "kill": _balloon_event(balloon.pop())
		if balloon.alive:
			var passed: int = levels.checkpoint_at(level, balloon.position)
			if passed > checkpoint:
				checkpoint = passed
				balloon.respawn_point = levels.team_start(level, 1, checkpoint).spot
				if run.audio != null: run.audio.play_checkpoint()
				print("GW_BALLOON_CHECKPOINT level=", level, " checkpoint=", checkpoint)
			if levels.point_zone(level, balloon.position) == "goal": run.balloon_goal()
	if run.won: return
	for slot in count:
		if not run.is_slot_active(slot): continue
		_grace[slot] = maxf(float(_grace[slot]) - delta, 0.0)
		if float(_grace[slot]) > 0.0 or held_by(slot) >= 0: continue
		var feet: Vector3 = run.actors[slot].global_position
		var scorch: String = levels.scorch_at(level, feet)
		if scorch != "":
			note_scorch(slot, scorch)
			_respawn_player(slot, scorch)
		elif levels.zone_at(level, feet) == "kill": _respawn_player(slot)

func _balloon_event(event: Dictionary) -> void:
	if event.is_empty(): return
	match str(event.kind):
		"bump":
			if run.audio != null: run.audio.play_bounce()
		"pop": run.begin_pop()

## Authority / local: a laser zapped or a fire jet burned `slot` ("zap" | "burn"): counted for the clients, the word shown here.
func note_scorch(slot: int, kind: String) -> void:
	scorches[slot * 2] += 1
	scorches[slot * 2 + 1] = int(SCORCH_CODES.get(kind, 1))
	_show_word(slot, scorches[slot * 2 + 1])
	print("GW_SCORCH slot=", slot, " kind=", kind, " count=", scorches[slot * 2])

## Client roles: the comic word over a scorched player, and its sound.
func _show_word(slot: int, code: int) -> void:
	if run.network_role == "authority" or run.world == null: return
	HazardLooks.word(run.world, TeamCast.word(SCORCH_WORDS.get(code, "zap")), run.actors[slot].global_position + Vector3.UP * WORD_HEIGHT)
	if run.audio != null: run.audio.play_death()

## A courier fell out, or was zapped or burned, during a balloon round: back to the team's spot alone (the balloon flies on).
func _respawn_player(slot: int, cause := "fall") -> void:
	var spots: Dictionary = run.level_world.team_start(run.current_level(), run.active_count(), checkpoint)
	var points: Array = spots.pos
	var at: Vector3 = (points[slot] if slot < points.size() else spots.spot) + Vector3.UP * 0.05
	contact.release(slot)
	_grace[slot] = RESPAWN_GRACE
	respawns[slot] += 1
	respawn_points[slot] = at
	run.respawn_courier(slot, at, float(spots.yaw))
	print("GW_PLAYER_RESPAWN slot=", slot, " cause=", cause, " count=", respawns[slot], " checkpoint=", checkpoint)

## A minigame moves a player (authority / local, modes/mode_host.gd send_to): released if held, a short grace, and its owner
## is told through the respawn count and point, as a personal respawn is.
func send_to(slot: int, at: Vector3, yaw := 0.0) -> void:
	if slot < 0 or slot >= count: return
	contact.release(slot)
	_grace[slot] = RESPAWN_GRACE
	respawns[slot] += 1
	respawn_points[slot] = at
	run.respawn_courier(slot, at, yaw)

# ------------------------------------------------------------------ snapshot

## Authority: the balloon round's shared fields (network/game.gd BALLOON_FLOATS, CONTACT_FLOATS).
func capture(state: Dictionary) -> void:
	state.play_mode = run.play_mode
	state.scorch = scorches.duplicate()
	if grabs_allowed() or run.stage_round(): # the lobby yard and balloon rounds: who holds whom, and the throws; a stage round: the personal respawns (the rules put a player back on its start spot, rules.gd)
		var touch := PackedFloat32Array()
		for slot in count:
			var kick: Vector3 = kicks[slot]
			var point: Vector3 = respawn_points[slot]
			touch.append_array(PackedFloat32Array([float(held_by(slot)), kick.x, kick.y, kick.z, float(respawns[slot]), point.x, point.y, point.z]))
		state.contact = touch
	if run.round_mode == "lobby": state.props = props.snapshot()
	if not active(): return
	state.slaps = slap_counts.duplicate()
	var data := balloon.snapshot()
	data.append_array(PackedFloat32Array([1.0 if balloon.hover else 0.0, float(checkpoint), float(balloon.bumps)]))
	state.balloon = data

## Replica: follow the authority's balloon and contact state (every rendered frame with the newest snapshot).
func apply(state: Dictionary, new_tick: bool) -> void:
	var data: Variant = state.get("balloon")
	if data is PackedFloat32Array and data.size() >= 11 and new_tick:
		balloon.apply_snapshot(data.slice(0, 8))
		balloon.hover = data[8] > 0.5
		checkpoint = int(data[9])
		_hear("checkpoint", checkpoint, run.audio.play_checkpoint if run.audio != null else Callable())
		_hear("bumps", int(data[10]), run.audio.play_bounce if run.audio != null else Callable())
	if run.failure_kind == "pop": _hear("pop", run.break_event, run.audio.play_death if run.audio != null else Callable())
	var loose: Variant = state.get("props")
	if loose is PackedFloat32Array and new_tick: props.apply_snapshot(loose)
	var scorched: Variant = state.get("scorch")
	if scorched is PackedInt32Array and scorched.size() == count * 2:
		for slot in count:
			if not _scorches_seen.is_empty() and scorched[slot * 2] > _scorches_seen[slot * 2] and run.is_slot_active(slot): _show_word(slot, scorched[slot * 2 + 1])
		_scorches_seen = scorched.duplicate()
	var slapped: Variant = state.get("slaps")
	if slapped is PackedInt32Array and slapped.size() == count * 2:
		var own: int = run.owner_courier.seat if run.owner_courier != null and run.owner_courier.configured else -1
		for slot in count:
			# The owner swung its own arm when it pressed; the others swing when the authority counted the slap.
			if not _slaps_seen.is_empty() and slapped[slot * 2] > _slaps_seen[slot * 2] and slot != own and run.is_slot_active(slot):
				_swing(slot, -1 if slapped[slot * 2 + 1] == 1 else 1)
		_slaps_seen = slapped.duplicate()
	var touch: Variant = state.get("contact")
	var epoch := int(state.get("resets", -1))
	if epoch != _epoch:
		_epoch = epoch
		_kick_seen = Vector3.ZERO
		_respawn_seen = 0
		_pending_kick = Vector3.ZERO
		_pending_teleport = null
	if not touch is PackedFloat32Array or touch.size() != count * 8:
		for slot in count: contact.held_by[slot] = -1
		return
	for slot in count: contact.held_by[slot] = int(touch[slot * 8])
	var own: int = run.owner_courier.seat if run.owner_courier != null and run.owner_courier.configured else -1
	if own < 0: return
	var at := own * 8
	var kick := Vector3(touch[at + 1], touch[at + 2], touch[at + 3])
	if kick != _kick_seen:
		_pending_kick += kick - _kick_seen
		_kick_seen = kick
	if int(touch[at + 4]) > _respawn_seen:
		_respawn_seen = int(touch[at + 4])
		_pending_teleport = Vector3(touch[at + 5], touch[at + 6], touch[at + 7])

## A counter went up since it was last heard: play its sound once (not for the first value seen).
func _hear(key: String, value: int, sound: Callable) -> void:
	var known := _heard.has(key)
	var before := int(_heard.get(key, 0))
	_heard[key] = value
	if known and value > before and sound.is_valid(): sound.call()

## Replica, once per physics tick: the balloon moves on between snapshots (no players, no pops: the authority decides those),
## held couriers are drawn above their holders.
func replica_tick(delta: float, own_seat: int) -> void:
	if active() and balloon.alive and not balloon.hover:
		var saved := balloon.snapshot()
		var popped := false
		for event: Dictionary in balloon.step(delta, run.world.get_world_3d().direct_space_state, []): popped = popped or event.kind == "pop"
		if popped:
			balloon.apply_snapshot(saved)
			balloon.velocity = Vector3.ZERO
	for slot in count:
		if slot != own_seat and run.is_slot_active(slot): place_held(slot, false)

# ------------------------------------------------------------------ drawing (client roles)

func draw(delta: float) -> void:
	if look == null: return
	prop_look.visible = run.round_mode == "lobby"
	if prop_look.visible: prop_look.follow(props, delta, _hands)
	look.visible = active()
	if not look.visible: return
	if view != balloon:
		var jump := view.alive != balloon.alive or view.position.distance_to(balloon.position) > SNAP_DISTANCE
		view.position = balloon.position if jump else view.position.lerp(balloon.position, 1.0 - exp(-delta * FOLLOW_SPEED))
		view.velocity = balloon.velocity
		view.alive = balloon.alive
	look.follow(view, delta)

## Where `slot` carries a prop as drawn this frame (Vector3.INF: not drawn).
func _hands(slot: int) -> Vector3:
	if slot < 0 or slot >= count or not run.is_slot_active(slot): return Vector3.INF
	var yaw: float = run.courier_yaw(slot)
	return PropSim.hold_point(run.actors[slot].global_position, Vector3(-sin(yaw), 0.0, -cos(yaw)))

## The point the camera keeps in view in a balloon round.
func focus_point() -> Vector3:
	return view.position if view.alive else balloon.respawn_point + Vector3.UP * BalloonSim.RESPAWN_HEIGHT
