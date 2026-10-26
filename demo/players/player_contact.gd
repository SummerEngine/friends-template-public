extends RefCounted
## Players touching players: shoving and picking each other up (the friendslop part).
##
## Shove: walking into someone pushes them away along the contact; a hard hit staggers them for a moment, so the
## shove carries instead of being undone by their own movement on the next frame.
## In a tile stage round (`stage`) the couriers are also solid bodies for each other (courier_motion.gd), and the shove is a two-way bump of the closing
## speed that does not depend on who has the lower slot (STAGE_BUMP, _stage_bump).
## Pick up: GRAB next to a free player lifts them over your head; GRAB again throws them forward. The held player
## gets free by pressing JUMP ESCAPE_PRESSES times, and is dropped after MAX_HOLD seconds anyway. Nobody who is
## holding or being held can be grabbed, and a released player can't be grabbed again for REGRAB_COOLDOWN.
##
## Pure simulation over plain capsules, like the balloon (balloon_sim.gd): the authority steps it and replicates
## `snapshot()`; the movement code applies its results. Per player in:
##   {position: Vector3 (capsule centre), velocity: Vector3, grab: bool (pressed this step), jump: bool (pressed this step)}
## Per player out (step() return, `results`):
##   {impulse: Vector3 (add to velocity), separate: Vector3 (move by this, out of other players), stagger: float
##    (s of reduced control), speed_scale: float,
##    held_by: int (-1 = free), hold_position: Vector3 (where a held player is, valid when held_by >= 0)}
## step() also returns `events`: {kind: "shove"|"grab"|"throw"|"drop"|"escape", player, other, position}.

const RADIUS := 0.35            ## courier capsule
const HALF_SEGMENT := 0.55      ## 1.8 m capsule: centre ± this is the inner segment
const SHOVE_SHARE := 0.85       ## share of the approach speed handed to the one being walked into
const SHOVE_MIN := 1.2          ## m/s: even a slow walk-in moves them
const STAGGER_SPEED := 2.4      ## a shove at least this fast staggers
const STAGGER_SECONDS := 0.35
const SEPARATE_RATE := 0.5      ## share of an overlap resolved per step
const GRAB_RANGE := 1.25        ## m between capsule centres, horizontally
const GRAB_FRONT := -0.3        ## dot(facing, to other) at least this: in front or beside, not right behind
const HOLD_HEIGHT := 1.7        ## held player's centre above the holder's
const HOLD_SPEED := 0.75        ## holder walks at this share of full speed
const THROW_FORWARD := 6.5
const THROW_UP := 5.5
const ESCAPE_PRESSES := 5
const MAX_HOLD := 5.0
const REGRAB_COOLDOWN := 0.8
## Stage rounds (`stage`, a tile stage round: the couriers are solid for each other, courier_motion.gd). A solid body never overlaps and a blocked one's velocity
## is cut by the slide, so contact counts on the way in: within STAGE_SKIN of the capsules or STAGE_LEAD ticks of the closing speed (a dash covers 0.4 m a tick),
## and exchanges the closing speed like two equal masses (STAGE_BUMP): each gets an impulse of (1 + restitution) / 2 of it, at most `max` m/s, whoever is slot 0;
## the one that did not bring most of the speed (the one run into) staggers `stagger` s, a hit softer
## than `min_approach` m/s is only blocked.
const STAGE_SKIN := 0.25 ## m
const STAGE_LEAD := 1.3 ## the reach also covers this many ticks of the closing speed (a run is 0.25 m a tick, a dash 0.4, a head-on 0.5)
const STAGE_BUMP := {"restitution": 0.5, "min_approach": 0.3, "max": 14.0, "stagger_speed": 2.0, "stagger": 0.4}

var stage := false ## the stage skin and bump are in force (game/team_play.gd sets it from the round)
var count := 0
## The game runs the two halves where they belong: shoves on every owner's own machine (shoves only), grabs on the
## authority (grabs only, it decides who holds whom); one machine with every player (local play, the lab) runs both.
var shoves := true
var grabs := true
var partners: Dictionary = {} ## slot -> the slot it holds hands with (the TANDEM, modes/show/tandem/): two fused partners do not shove each other; set on every machine from the replicated pair
var power: Dictionary = {} ## slot -> multiplier of the shove that player gives (the show's BOOST: modes/show/items_ui/boost_view.gd sets it on every machine from the replicated effect); absent = 1
var held_by: PackedInt32Array = []     ## per player: the holder's index, -1 = free
var _stagger: PackedFloat32Array = []
var _hold_time: PackedFloat32Array = []
var _escape: PackedInt32Array = []
var _cooldown: PackedFloat32Array = []
var _facing: Array[Vector3] = []

func _init(players: int) -> void:
	count = players
	held_by.resize(players)
	held_by.fill(-1)
	for array in [_stagger, _hold_time, _cooldown]:
		array.resize(players)
		array.fill(0.0)
	_escape.resize(players)
	_escape.fill(0)
	for i in players: _facing.append(Vector3.FORWARD)

## Index of the player `holder` is holding, -1 for none.
func holding(holder: int) -> int:
	return held_by.find(holder)

## Where `player` faces (flat, unit): the way it last moved.
func facing(player: int) -> Vector3:
	return _facing[player]

func step(delta: float, players: Array) -> Dictionary:
	var events: Array = []
	var results: Array = []
	for i in count:
		results.append({"impulse": Vector3.ZERO, "separate": Vector3.ZERO, "stagger": 0.0, "speed_scale": 1.0, "held_by": -1, "hold_position": Vector3.ZERO})
		_stagger[i] = maxf(0.0, _stagger[i] - delta)
		_cooldown[i] = maxf(0.0, _cooldown[i] - delta)
		var flat: Vector3 = players[i].velocity * Vector3(1, 0, 1)
		if flat.length() > 0.5: _facing[i] = flat.normalized()
	if grabs:
		_holds(delta, players, events)
		_grabs(players, events)
	if shoves: _shoves(delta, players, results, events)
	for i in count:
		results[i].stagger = _stagger[i]
		results[i].held_by = held_by[i]
		if held_by[i] >= 0: results[i].hold_position = players[held_by[i]].position + Vector3.UP * HOLD_HEIGHT
		if holding(i) >= 0: results[i].speed_scale = HOLD_SPEED
	for event in events:
		if event.kind == "throw":
			results[event.other].impulse += _facing[event.player] * THROW_FORWARD + Vector3.UP * THROW_UP
		elif event.kind in ["drop", "escape"]:
			results[event.other if event.kind == "drop" else event.player].impulse += Vector3.UP * 2.0
	return {"results": results, "events": events}

## Held players: count the hold, the escape presses; release when either runs out.
func _holds(delta: float, players: Array, events: Array) -> void:
	for i in count:
		var holder := held_by[i]
		if holder < 0: continue
		_hold_time[i] += delta
		if bool(players[i].get("jump", false)): _escape[i] += 1
		if _escape[i] >= ESCAPE_PRESSES:
			_release(i)
			events.append({"kind": "escape", "player": i, "other": holder, "position": players[i].position})
		elif _hold_time[i] >= MAX_HOLD:
			_release(i)
			events.append({"kind": "drop", "player": holder, "other": i, "position": players[i].position})

## GRAB presses: a holder throws; a free player picks up the nearest grabbable player in front of them.
func _grabs(players: Array, events: Array) -> void:
	for i in count:
		if not bool(players[i].get("grab", false)) or held_by[i] >= 0: continue
		var held := holding(i)
		if held >= 0:
			_release(held)
			events.append({"kind": "throw", "player": i, "other": held, "position": players[held].position})
			continue
		var best := -1
		var best_distance := GRAB_RANGE
		for j in count:
			if j == i or held_by[j] >= 0 or holding(j) >= 0 or _cooldown[j] > 0.0: continue
			var offset: Vector3 = (players[j].position - players[i].position) * Vector3(1, 0, 1)
			var distance := offset.length()
			if absf(players[j].position.y - players[i].position.y) > 1.0: continue
			if distance >= best_distance or (distance > 0.01 and _facing[i].dot(offset / distance) < GRAB_FRONT): continue
			best = j
			best_distance = distance
		if best >= 0:
			held_by[best] = i
			_hold_time[best] = 0.0
			_escape[best] = 0
			events.append({"kind": "grab", "player": i, "other": best, "position": players[best].position})

## Frees `player` and whoever it holds (a respawn, a player who left, grabs switched off).
func release(player: int) -> void:
	if player < 0 or player >= count: return
	if held_by[player] >= 0: _release(player)
	var held := holding(player)
	if held >= 0: _release(held)

func _release(held: int) -> void:
	held_by[held] = -1
	_hold_time[held] = 0.0
	_escape[held] = 0
	_cooldown[held] = REGRAB_COOLDOWN

## Capsule against capsule for every free pair: separate them and hand the approach speed to the one walked into.
func _shoves(delta: float, players: Array, results: Array, events: Array) -> void:
	for a in count:
		for b in range(a + 1, count):
			if held_by[a] >= 0 or held_by[b] >= 0 or holding(a) == b or holding(b) == a or int(partners.get(a, -2)) == b: continue
			var pa: Vector3 = players[a].position
			var pb: Vector3 = players[b].position
			if absf(pa.y - pb.y) > HALF_SEGMENT * 2.0 + RADIUS: continue
			var offset := (pb - pa) * Vector3(1, 0, 1)
			var distance := offset.length()
			var normal := offset / distance if distance > 0.0001 else Vector3.RIGHT
			var va: Vector3 = players[a].velocity
			var vb: Vector3 = players[b].velocity
			var approach := (va - vb).dot(normal) ## > 0: closing
			var reach := RADIUS * 2.0
			if stage: reach += maxf(STAGE_SKIN, approach * delta * STAGE_LEAD)
			if distance >= reach: continue
			var overlap := maxf(RADIUS * 2.0 - distance, 0.0)
			# Separation as a position correction: a share of the overlap per step, half each, so a crowd settles without jitter.
			var separate := normal * overlap * 0.5 * SEPARATE_RATE
			results[a].separate -= separate
			results[b].separate += separate
			if approach <= 0.0: continue
			if stage:
				_stage_bump(a, b, normal, va.dot(normal), vb.dot(normal), approach, players, results, events)
				continue
			# The faster one shoves; the slower one is shoved (equal mass: both feel it, the target more).
			var speed := maxf(approach * SHOVE_SHARE, SHOVE_MIN)
			var shover := a if va.dot(normal) >= -vb.dot(normal) else b
			var target := b if shover == a else a
			var push := normal if target == b else -normal
			var strong := float(power.get(shover, 1.0))
			if strong > 1.0 and float(power.get(target, 1.0)) <= 1.0: speed *= strong # a boosted player flings whoever it runs into (and feels no kick back)
			results[target].impulse += push * speed
			results[shover].impulse -= push * speed * (0.3 if strong <= 1.0 else 0.0)
			if speed >= STAGGER_SPEED:
				_stagger[target] = STAGGER_SECONDS
				events.append({"kind": "shove", "player": shover, "other": target, "position": players[target].position})

## A stage round's bump of the pair a < b: `ua`, `ub` their speeds along the normal a -> b. Equal masses exchange the closing speed (restitution): b gets pushed on,
## a back, by the same amount, so the result does not depend on who has the lower slot.
func _stage_bump(a: int, b: int, normal: Vector3, ua: float, ub: float, approach: float, players: Array, results: Array, events: Array) -> void:
	if approach < float(STAGE_BUMP.min_approach): return
	var throw := minf(approach * (1.0 + float(STAGE_BUMP.restitution)) * 0.5, float(STAGE_BUMP.max))
	results[b].impulse += normal * throw
	results[a].impulse -= normal * throw
	if throw < float(STAGE_BUMP.stagger_speed): return
	var brought_by_a := clampf(ua / approach, 0.0, 1.0) # a's share of the closing speed: 1 = a ran into b, 0 = b ran into a
	for pair: Array in [[a, b, brought_by_a], [b, a, 1.0 - brought_by_a]]:
		if float(pair[2]) <= 0.5:
			_stagger[int(pair[0])] = float(STAGE_BUMP.stagger)
			events.append({"kind": "shove", "player": pair[1], "other": pair[0], "position": players[int(pair[0])].position})

## Replicated state: per player held_by and stagger.
func snapshot() -> PackedFloat32Array:
	var state := PackedFloat32Array()
	for i in count:
		state.append(float(held_by[i]))
		state.append(_stagger[i])
	return state

func apply_snapshot(state: PackedFloat32Array) -> void:
	for i in mini(count, state.size() / 2):
		held_by[i] = int(state[i * 2])
		_stagger[i] = state[i * 2 + 1]
