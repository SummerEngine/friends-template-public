extends "res://modes/mode_rules.gd"
## HOT POTATO rules (docs/modes/hot_potato.md). One of the yard's loose props (players/prop_sim.gd) is the potato: players pick it
## up and throw it with the game's own GRAB like any prop. Everybody has LIVES lives. A hidden fuse (FUSE seconds from host.rng,
## a little shorter after every pop, never under MIN_FUSE) runs; when it pops, whoever holds the potato loses a life, or the player
## nearest to it when nobody does. Then a short POP beat, the potato lands on a random open spot of the yard, "3, 2, 1" and the next
## fuse. A player without lives is out: sent to a side of the yard, and a potato they grab drops at once. Last one with lives wins.
##
## Phases: "live" (the fuse runs) -> "pop" (POP_SECONDS) -> "count" (COUNT_SECONDS, the potato waits on its new spot) -> "live" ...
## and "over" (END_SECONDS, the winner) once one player is left; finished() after it.
const PropSim := preload("res://players/prop_sim.gd")
const LIVES := 3
const FUSE := Vector2(10.0, 20.0) ## s: the first fuse is drawn from this range
const SHRINK := 0.92 ## every pop so far multiplies the range by this ...
const MIN_FUSE := 8.0 ## ... and no fuse is shorter than this
const POP_SECONDS := 1.6
const COUNT_SECONDS := 3.0
const END_SECONDS := 3.0
const GO_SECONDS := 1.0 ## the first second of a fuse shows GO!
## Where the potato lands: yard-local XZ (walk_in_lobby.gd ORIGIN), the open middle clear of the playground and the furniture.
const OPEN := Rect2(-5.5, -7.0, 11.0, 12.0)
const CLEAR := 2.5 ## m: a landing spot keeps this far from every player still in when it can
const SPOT_TRIES := 12
const STRAY := 0.5 ## m outside the yard's walls (or this far under its floor): the potato lands again
## The players who are out stand along the side walls, facing the middle: yard-local x, then rows along z.
const OUT_X := 8.4
const OUT_Z := -5.5
const OUT_STEP := 1.6

var lives: Array = [] ## per slot
var out_order: Array = [] ## slots in the order they went out
var potato := -1 ## the prop index of the potato
var phase := "live"
var phase_time := 0.0 ## s in the current phase
var fuse := 0.0 ## s: the current fuse (hidden: never in state())
var fuses: Array = [] ## every fuse drawn (the check reads it)
var pops := 0
var zapped := -1 ## the slot the last pop zapped, -1 none
var zapped_out := false ## that pop took its last life
var pop_at := Vector3.ZERO ## where the potato was when it popped
var spot := Vector3.ZERO ## where it waits during the pop and the count
var rest := Vector3.ZERO ## where it last lay free: a grab by a player who is out puts it back here
var winner := -1
var _sent := 0 ## players sent to the side so far (their place along the wall)
var _done := false

func start(round_host) -> void:
	super.start(round_host)
	lives = []
	for slot in host.count: lives.append(LIVES)
	var props = host.props()
	potato = host.rng.randi_range(0, props.count - 1) if props != null and props.count > 0 else -1
	spot = _open_spot()
	_place(spot)
	fuse = _new_fuse()
	_enter("live")
	if _alive().size() <= 1: _end()

func tick(dt: float) -> void:
	super.tick(dt)
	if _done: return
	phase_time += dt
	match phase:
		"live":
			_keep_legal()
			if phase_time >= fuse: _pop()
		"pop":
			_place(spot)
			if phase_time >= POP_SECONDS:
				if zapped_out: _bench(zapped)
				if _alive().size() <= 1: _end()
				else: _enter("count")
		"count":
			_place(spot)
			if phase_time >= COUNT_SECONDS:
				fuse = _new_fuse()
				_enter("live")
		"over":
			_place(spot)
			if phase_time >= END_SECONDS: _done = true

func state() -> Dictionary:
	var at: Vector3 = host.props().positions[potato] if potato >= 0 else spot
	return {
		"phase": phase,
		"potato": potato,
		"kind": str(host.props().kinds[potato]) if potato >= 0 else "",
		"holder": holder(),
		"heat": snappedf(clampf(phase_time / fuse, 0.0, 1.0), 0.01) if phase == "live" and fuse > 0.0 else 0.0,
		"go": phase == "live" and phase_time < GO_SECONDS,
		"count": ceili(COUNT_SECONDS - phase_time) if phase == "count" else 0,
		"lives": lives.duplicate(),
		"out": out_order.duplicate(),
		"pops": pops,
		"zapped": zapped,
		"zapped_out": zapped_out,
		"pop_at": [snappedf(pop_at.x, 0.01), snappedf(pop_at.y, 0.01), snappedf(pop_at.z, 0.01)],
		"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"winner": winner,
	}

func finished() -> bool:
	return _done

## Headline "<WINNER> WINS"; the sub names everybody else by place, the last one out first.
func results() -> Dictionary:
	var winners: Array = [winner] if winner >= 0 else _leaders()
	var names := PackedStringArray()
	for slot: int in winners: names.append(host.name(slot))
	var who := ", ".join(names.slice(0, names.size() - 1)) + " & " + names[names.size() - 1] if names.size() > 1 else "".join(names)
	var headline := (who + (" WINS" if winners.size() == 1 else " WIN")) if not winners.is_empty() else ""
	var others: Array = _alive().filter(func(slot: int) -> bool: return not winners.has(slot))
	others.sort_custom(func(a: int, b: int) -> bool: return int(lives[a]) > int(lives[b]) or (int(lives[a]) == int(lives[b]) and a < b))
	for index in range(out_order.size() - 1, -1, -1):
		if not winners.has(out_order[index]): others.append(out_order[index])
	var places := PackedStringArray()
	for index in others.size(): places.append("%s %s" % [_ordinal(winners.size() + index + 1), host.name(others[index])])
	return {"headline": headline, "sub": "  ·  ".join(places), "scores": lives.duplicate(), "winners": winners}

## A player left: out at once; a potato in their hands drops where it is.
func drop(slot: int) -> void:
	if slot < 0 or slot >= lives.size() or phase == "over" or _done: return
	if int(lives[slot]) > 0:
		lives[slot] = 0
		out_order.append(slot)
	var props = host.props()
	if potato >= 0 and props.held_by[potato] == slot:
		props.held_by[potato] = -1
		props.velocities[potato] = Vector3.ZERO
	if _alive().size() <= 1: _end()

## The slot holding the potato, -1 when nobody (still in) does.
func holder() -> int:
	if potato < 0: return -1
	var slot: int = host.props().held_by[potato]
	return slot if _in(slot) else -1

# ------------------------------------------------------------------ the round

func _enter(next: String) -> void:
	phase = next
	phase_time = 0.0

## The fuse pops: the holder (else the nearest player still in) loses a life; the potato goes to its next spot.
func _pop() -> void:
	var at: Vector3 = host.props().positions[potato] if potato >= 0 else spot
	var victim := holder()
	if victim < 0: victim = _nearest(at)
	pops += 1
	pop_at = at
	zapped = victim
	zapped_out = false
	if victim >= 0:
		lives[victim] = int(lives[victim]) - 1
		if int(lives[victim]) <= 0:
			zapped_out = true
			out_order.append(victim)
	spot = _open_spot()
	_place(spot)
	_enter("pop")

func _end() -> void:
	var left := _alive()
	winner = int(left[0]) if left.size() == 1 else -1
	_enter("over")

## During the fuse: a potato in the hands of a player who is out goes back where it lay; one that left the yard lands again.
func _keep_legal() -> void:
	if potato < 0: return
	var props = host.props()
	var slot: int = props.held_by[potato]
	if slot >= 0 and not _in(slot):
		props.held_by[potato] = -1
		props.positions[potato] = rest
		props.velocities[potato] = Vector3.ZERO
		return
	if slot >= 0: return
	var at: Vector3 = props.positions[potato]
	var yard: Rect2 = host.yard_rect().grow(STRAY)
	if not yard.has_point(Vector2(at.x, at.z)) or at.y < host.floor_y() - STRAY:
		spot = _open_spot()
		_place(spot)
	else:
		rest = at

## The potato lies still at `at`, nobody holding it.
func _place(at: Vector3) -> void:
	if potato < 0: return
	var props = host.props()
	props.positions[potato] = at
	props.velocities[potato] = Vector3.ZERO
	props.held_by[potato] = -1
	rest = at

## A player who went out plays on from a side wall, facing in (west and east by turns, rows along the wall).
func _bench(slot: int) -> void:
	if slot < 0 or not host.active(slot): return
	var side := -1.0 if _sent % 2 == 0 else 1.0
	var centre: Vector3 = host.yard_center()
	var at := Vector3(centre.x + OUT_X * side, host.floor_y() + 0.05, centre.z + OUT_Z + floorf(_sent * 0.5) * OUT_STEP)
	host.send_to(slot, at, PI * 0.5 * side)
	_sent += 1

func _new_fuse() -> float:
	var drawn := maxf(MIN_FUSE, host.rng.randf_range(FUSE.x, FUSE.y) * pow(SHRINK, pops))
	fuses.append(drawn)
	return drawn

## A random open spot of the yard on the floor, CLEAR from every player still in when one of SPOT_TRIES tries is (else the
## try farthest from them).
func _open_spot() -> Vector3:
	var radius := float(PropSim.KINDS.get(str(host.props().kinds[potato]), 0.25)) if potato >= 0 else 0.25
	var centre: Vector3 = host.yard_center()
	var best := centre + Vector3(0.0, radius, 0.0)
	var best_gap := -1.0
	for attempt in SPOT_TRIES:
		var x: float = host.rng.randf_range(OPEN.position.x, OPEN.end.x)
		var z: float = host.rng.randf_range(OPEN.position.y, OPEN.end.y)
		var at := Vector3(centre.x + x, host.floor_y() + radius, centre.z + z)
		var gap := INF
		for slot: int in _alive(): gap = minf(gap, _flat(host.position(slot), at))
		if gap >= CLEAR: return at
		if gap > best_gap:
			best = at
			best_gap = gap
	return best

# ------------------------------------------------------------------ players

## Still in: lives left and in the round.
func _in(slot: int) -> bool:
	return slot >= 0 and slot < lives.size() and int(lives[slot]) > 0 and host.active(slot)

func _alive() -> Array:
	var result: Array = []
	for slot in lives.size():
		if _in(slot): result.append(slot)
	return result

## The player still in nearest to `at` (flat distance; the lower slot on a tie), -1 for none.
func _nearest(at: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for slot: int in _alive():
		var distance := _flat(host.position(slot), at)
		if distance < best_distance:
			best = slot
			best_distance = distance
	return best

## The players still in with the most lives (a round that ended early).
func _leaders() -> Array:
	var left := _alive()
	if left.is_empty(): return [out_order.back()] if not out_order.is_empty() else []
	var top := 0
	for slot: int in left: top = maxi(top, int(lives[slot]))
	return left.filter(func(slot: int) -> bool: return int(lives[slot]) == top)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

static func _ordinal(place: int) -> String:
	var tail := "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1: tail = "st"
			2: tail = "nd"
			3: tail = "rd"
	return "%d%s" % [place, tail]
