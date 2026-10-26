extends "res://modes/mode_rules.gd"
## SHOVE-OFF rules (docs/modes/shove_off.md): everybody stands on a raised floor of tiles in the yard and shoves the others off
## with the game's own contact (walking into someone, GRAB and throw) while the tiles fall away, outer ring first and faster and
## faster. Off = out for the round; the last one standing wins it. The first to WINS_NEEDED round wins wins the game (at most
## MAX_ROUNDS rounds; then the most round wins).
##
## The floor is GRID x GRID tiles of TILE metres, its top TOP_ABOVE over the yard floor around CENTER (yard space). The view
## (modes/shove_off/view.gd) builds it as real collision on every client; these rules never use that geometry: a player whose
## feet are more than OFF_DEPTH below the top is off, and so is one who hangs over no tile for HANG seconds (a frozen courier).
##
## A round: "count" (everybody sent onto a ring of tiles, 3, 2, 1), "play" (SHOVE!, then the tiles shake SHAKE s and drop),
## "card" (who won the round; the tiles come back after it); "over" once the game is decided.
const WalkInLobby := preload("res://network/walk_in_lobby.gd")

const GRID := 6
const TILE := 1.25 ## m, one tile's side
const TOP_ABOVE := 1.5 ## m from the yard floor to the tiles' top: too high to jump back on or to shove from below
const THICK := 0.35 ## m, a tile's thickness (the view)
const CENTER := Vector2(0.0, 0.4) ## yard space (x, z): the open floor between two light strands, clear of the playground
const RING_RADIUS := 2.0 ## m from the centre: where a round puts everybody
const WATCH_BACK := 3.0 ## m north of the floor's edge: the row out players watch from
const WATCH_GAP := 0.95 ## m between two watchers

const COUNT := 3.0 ## s of 3, 2, 1
const SHOVE_SHOW := 1.0 ## s the big SHOVE! stays after the count (the view)
const FIRST_DROP := 2.0 ## s of shoving before the first tile shakes
const SHAKE := 1.0 ## s a tile shakes before it drops
const GAP_START := 1.4 ## s between the first two tiles that start to shake ...
const GAP_DECAY := 0.93 ## ... each gap this much shorter than the one before ...
const GAP_MIN := 0.35 ## ... down to this
const CARD := 3.5 ## s of the round's card
const OFF_DEPTH := 0.8 ## m below the top: off
const HANG := 1.5 ## s over no tile without falling: off (a courier that stopped moving)
const SUPPORT := 0.35 ## m past a tile's edge that still stands on it (the capsule's radius)
const GRACE := 1.0 ## s after a send_to without a test (late poses from before the move)
const FALL_SHOW := 1.0 ## s an out player falls before the rules send them to the watch row
const KEEP_OUT := 0.6 ## m around the floor that out players are kept from
const LABELS := 5 ## tiles that carry the cast's obstacle labels: the first ones to drop
const WINS_NEEDED := 2
const MAX_ROUNDS := 5

const UP := 0
const SHAKING := 1
const GONE := 2

var phase := "count"
var round_number := 0
var phase_time := 0.0 ## s since the phase started
var tiles: Array = [] ## per tile (row * GRID + column): UP, SHAKING or GONE
var order: Array = [] ## the round's drop order (tile indices)
var shake_at: Array = [] ## per tile: s into "play" when it starts to shake
var marked: Array = [] ## the tiles with labels, in label order
var wins: Array = [] ## per slot
var out: Array = [] ## slots out this round, in the order they fell
var gone: Array = [] ## slots that left the game
var winner := -1 ## the round's winner during its card, -1 for none
var champion := -1 ## the game's winner once it is over, -1 for none (a tie or nobody)
var _spots: Array = [] ## per slot: [at, yaw] on the ring this round
var _grace: Array = [] ## per slot: s left without a test
var _hang: Array = [] ## per slot: s over no tile
var _send_at: Array = [] ## per slot: when an out player goes to the watch row, -1 for not pending
var _last_drop := 0.0 ## s into "play" when the last tile drops

func start(round_host) -> void:
	super(round_host)
	for slot in host.count:
		wins.append(0)
		_spots.append([center(), 0.0])
		_grace.append(0.0)
		_hang.append(0.0)
		_send_at.append(-1.0)
	_begin_round()

func tick(dt: float) -> void:
	super(dt)
	phase_time += dt
	for slot in host.count: _grace[slot] = maxf(float(_grace[slot]) - dt, 0.0)
	match phase:
		"count":
			_keep_on()
			if phase_time >= COUNT: _set_phase("play")
		"play":
			_drop_tiles()
			_check_falls(dt)
			_watchers()
		"card":
			_watchers()
			if phase_time >= CARD:
				if _decided(): _end_game()
				else: _begin_round()

func state() -> Dictionary:
	return {"phase": phase, "round": round_number, "t": snappedf(phase_time, 0.01), "tiles": tiles.duplicate(), "marked": marked.duplicate(),
		"wins": wins.duplicate(), "out": out.duplicate(), "gone": gone.duplicate(), "winner": winner, "champion": champion}

func finished() -> bool:
	return phase == "over"

func results() -> Dictionary:
	var slot := champion if phase == "over" else _leader()
	if slot >= 0: return {"headline": "%s WINS" % host.name(slot), "sub": score_line(wins), "scores": wins.duplicate(), "winners": [slot]}
	var top := _top_wins()
	var tied := _in_game().filter(func(each: int) -> bool: return top > 0 and int(wins[each]) == top)
	return {"headline": "IT'S A TIE" if top > 0 else "NOBODY WINS", "sub": score_line(wins), "scores": wins.duplicate(), "winners": tied}

## A player left: out for the rest of the game. The round plays on while two or more are left in it.
func drop(slot: int) -> void:
	if slot < 0 or slot >= host.count or gone.has(slot): return
	gone.append(slot)
	if phase == "play": _round_over_check()
	elif phase == "count" and _in_game().size() < 2: _end_round()

# ------------------------------------------------------------------ the floor (the view builds it from the same numbers)

## The tiles' top, world y.
static func top_y() -> float:
	return WalkInLobby.FLOOR_Y + TOP_ABOVE

## The floor's centre on its top, world space.
static func center() -> Vector3:
	return WalkInLobby.ORIGIN + Vector3(CENTER.x, TOP_ABOVE, CENTER.y)

## The middle of tile `index` (row * GRID + column) on its top, world space.
static func tile_center(index: int) -> Vector3:
	var middle := (GRID - 1) * 0.5
	return center() + Vector3((index % GRID - middle) * TILE, 0.0, (floori(index / float(GRID)) - middle) * TILE)

## 0 for the outer ring, 1 for the one inside it, ...
static func ring(index: int) -> int:
	var column := index % GRID
	var row := floori(index / float(GRID))
	return mini(mini(column, row), mini(GRID - 1 - column, GRID - 1 - row))

## The floor from above (x, z), grown by `margin` metres on every side.
static func area(margin := 0.0) -> Rect2:
	var middle := center()
	var half := GRID * TILE * 0.5 + margin
	return Rect2(middle.x - half, middle.z - half, half * 2.0, half * 2.0)

## Where an out player watches from: a row of `count` spots on the yard floor north of the tiles, facing them (yaw PI).
static func watch_spot(slot: int, count: int) -> Vector3:
	var middle := center()
	return Vector3(middle.x + (slot - (count - 1) * 0.5) * WATCH_GAP, WalkInLobby.FLOOR_Y + 0.25, middle.z - GRID * TILE * 0.5 - WATCH_BACK)

## The tile a player at `at` stands on (SUPPORT past its edges counts), -1 for none.
func tile_under(at: Vector3) -> int:
	for index in tiles.size():
		if int(tiles[index]) == GONE: continue
		var middle := tile_center(index)
		if absf(at.x - middle.x) <= TILE * 0.5 + SUPPORT and absf(at.z - middle.z) <= TILE * 0.5 + SUPPORT: return index
	return -1

# ------------------------------------------------------------------ the round

func _begin_round() -> void:
	round_number += 1
	winner = -1
	out = []
	tiles = []
	for index in GRID * GRID: tiles.append(UP)
	order = []
	for ring_index in ceili(GRID * 0.5): # outer ring first, each ring shuffled with the round's random numbers
		var band: Array = range(GRID * GRID).filter(func(index: int) -> bool: return ring(index) == ring_index)
		for k in range(band.size() - 1, 0, -1):
			var pick: int = host.rng.randi_range(0, k)
			var swap: Variant = band[k]
			band[k] = band[pick]
			band[pick] = swap
		order.append_array(band)
	shake_at = []
	shake_at.resize(GRID * GRID)
	var at := FIRST_DROP
	for k in order.size():
		shake_at[order[k]] = at
		at += maxf(GAP_MIN, GAP_START * pow(GAP_DECAY, k))
	_last_drop = float(shake_at[order[order.size() - 1]]) + SHAKE
	marked = order.slice(0, LABELS)
	var turn: float = host.rng.randf() * TAU
	var playing := _in_game()
	for k in playing.size():
		var slot: int = playing[k]
		var angle := wrapf(turn + TAU * k / playing.size(), -PI, PI)
		_spots[slot] = [center() + Vector3(sin(angle) * RING_RADIUS, 0.25, cos(angle) * RING_RADIUS), angle] # facing the centre
		_send(slot, _spots[slot][0], _spots[slot][1])
		_hang[slot] = 0.0
		_send_at[slot] = -1.0
	_set_phase("count")

## "count": somebody shoved off before SHOVE! goes back to their spot.
func _keep_on() -> void:
	for slot: int in _in_game():
		if float(_grace[slot]) > 0.0 or host.held_by(slot) >= 0: continue
		var feet: Vector3 = host.position(slot)
		if feet.y < top_y() - OFF_DEPTH: _send(slot, _spots[slot][0], _spots[slot][1])

func _drop_tiles() -> void:
	for index in tiles.size():
		var started := float(shake_at[index])
		var want := UP if phase_time < started else (SHAKING if phase_time < started + SHAKE else GONE)
		if want > int(tiles[index]): tiles[index] = want

func _check_falls(dt: float) -> void:
	if _alive().size() <= 1: # a player stopped being active without a drop
		_round_over_check()
		return
	var fell: Array = []
	for slot: int in _alive():
		if float(_grace[slot]) > 0.0: continue
		var feet: Vector3 = host.position(slot)
		if feet.y < top_y() - OFF_DEPTH:
			fell.append(slot)
			continue
		if host.held_by(slot) >= 0 or tile_under(feet) >= 0: _hang[slot] = 0.0
		else:
			_hang[slot] = float(_hang[slot]) + dt
			if float(_hang[slot]) >= HANG: fell.append(slot)
	if fell.is_empty() and phase_time >= _last_drop + HANG + 2.0: fell = _alive() # no floor left: whoever is still up fell together
	if fell.is_empty(): return
	for slot: int in fell:
		out.append(slot)
		_send_at[slot] = time + FALL_SHOW
	_round_over_check()

## One player left standing wins the round; when the last ones fell in the same tick, nobody does.
func _round_over_check() -> void:
	var standing := _alive()
	if standing.size() > 1: return
	winner = int(standing[0]) if standing.size() == 1 else -1
	if winner >= 0: wins[winner] = int(wins[winner]) + 1
	_end_round()

func _end_round() -> void:
	for index in tiles.size():
		if int(tiles[index]) == SHAKING: tiles[index] = UP # the floor stops falling for the card
	_set_phase("card")

## Out players: sent to the watch row once their fall has shown, and back to it whenever they come near the floor again.
func _watchers() -> void:
	for slot: int in out:
		if gone.has(slot) or float(_grace[slot]) > 0.0: continue
		if float(_send_at[slot]) >= 0.0:
			if time >= float(_send_at[slot]):
				_send_at[slot] = -1.0
				_send(slot, watch_spot(slot, host.count), PI)
			continue
		var feet: Vector3 = host.position(slot)
		if area(KEEP_OUT).has_point(Vector2(feet.x, feet.z)): _send(slot, watch_spot(slot, host.count), PI)

func _decided() -> bool:
	return _top_wins() >= WINS_NEEDED or round_number >= MAX_ROUNDS or _in_game().size() < 2

func _end_game() -> void:
	champion = _leader()
	_set_phase("over")

## The one player ahead on round wins (the only one left in the game wins too), -1 for a tie or nobody.
func _leader() -> int:
	var playing := _in_game()
	if playing.size() == 1: return int(playing[0])
	var top := _top_wins()
	if top <= 0: return -1
	var leaders := playing.filter(func(slot: int) -> bool: return int(wins[slot]) == top)
	return int(leaders[0]) if leaders.size() == 1 else -1

func _top_wins() -> int:
	var top := 0
	for slot: int in _in_game(): top = maxi(top, int(wins[slot]))
	return top

func _set_phase(next: String) -> void:
	phase = next
	phase_time = 0.0

func _send(slot: int, at: Vector3, yaw: float) -> void:
	host.send_to(slot, at, yaw)
	_grace[slot] = GRACE

## Slots still in the game (not left).
func _in_game() -> Array:
	return range(host.count).filter(func(slot: int) -> bool: return not gone.has(slot) and host.active(slot))

## Slots still standing this round.
func _alive() -> Array:
	return _in_game().filter(func(slot: int) -> bool: return not out.has(slot))
