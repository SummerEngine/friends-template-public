extends "res://modes/mode_rules.gd"
## WHO SAID IT? rules (docs/modes/who_said_it.md). Every character of the round has a pad on the open yard floor, in a ring
## (pads(): the view draws them, a statue of that character on each). Ten rounds: a short get-ready beat on the start ring, then one
## line shows (a catchphrase of the round's cast) and everybody runs to the pad of whoever says it. When the round closes, the first
## player who stepped onto a right pad after the line showed gets FIRST_POINTS and everybody else on a right pad ON_POINTS. The
## reveal follows, then everybody is sent back to the start ring so the next race is fair.
## Who stands where comes from the host's positions only (pad_under()); the pads the view draws never decide anything.
const TeamCast := preload("res://style/team_cast.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")

const ROUNDS := 10
const INTRO := 3.0 ## s: round 1's get-ready beat (time to look at the pads and statues)
const READY := 1.0 ## s: the get-ready beat of every later round
const RUN := 4.5 ## s: the line shows and everybody runs; the round closes when it runs out
const REVEAL := 2.5 ## s: the right pad lights up and its statue plays its emote
const FIRST_POINTS := 3
const ON_POINTS := 1
## The ring: an ellipse around CENTER (yard-local x, z) ASPECT times wider than deep, big enough that neighbouring pads stand PAD_GAP
## apart along it (and never shallower than MIN_DEPTH). With ten pads it stays clear of the trampoline (north), the team's floor word
## (south) and the walls; the pads' statues stand on their outer edge.
const CENTER := Vector2(0.0, -2.7)
const ASPECT := 1.75
const MIN_DEPTH := 3.3
const PAD_GAP := 3.5
const RING_STEPS := 720 ## samples along the ellipse when the pads are spread by length
## A player is on a pad within ENTER of its middle and stays on it up to EXIT (no flicker on its edge). EXIT * 2 < PAD_GAP: never on
## two pads. The height window is the lobby circles': a jump on a pad keeps the player on it.
const ENTER := 1.2
const EXIT := 1.45
const BELOW := WalkInLobby.BELOW
const ABOVE := WalkInLobby.ABOVE
## The start ring: before every race everybody stands START_RADIUS around the ring's middle, facing north (yaw 0).
const START_RADIUS := 1.3
const START_LIFT := 0.25 ## m over the floor, as the yard spots
## The cast's words (TeamCast.word: the template's words when unset) that fill the rounds, with the eggs, when fewer than two
## characters of the round have a catchphrase.
const WORD_KEYS := ["delivered", "break", "fall", "pop", "zap", "burnt"]

var phase := "ready" ## ready | run | reveal | done
var number := 1 ## the round, 1..ROUNDS
var left := INTRO ## s left in this phase
var scores: Array = [] ## per slot
var lines: Array = [] ## {text, slots (the right pads), ask (not a catchphrase: "Who would say: ...?")}
var order: Array = [] ## the line of every round (index into lines)
var first := -1 ## reveal: the slot that got FIRST_POINTS, -1 for none
var right: Array = [] ## reveal: the other slots on a right pad (ON_POINTS each)
var on: Array = [] ## slot -> the pad it stands on, -1
var since: Array = [] ## slot -> time it stepped onto that pad
var early: Array = [] ## slot -> it already stood on that pad when the line showed (no FIRST_POINTS for that stay)
var gone: Array = [] ## slot -> left the round (drop)
var _pads: Array = []

func start(round_host) -> void:
	super(round_host)
	var count: int = host.count
	for list: Array in [scores, on, since, early, gone]: list.clear()
	for slot in count:
		scores.append(0)
		on.append(-1)
		since.append(0.0)
		early.append(false)
		gone.append(false)
	_pads = pads(count)
	lines = _lines()
	order = _schedule(lines.size())
	phase = "ready"
	number = 1
	left = INTRO
	first = -1
	right = []
	_send_all()

func tick(dt: float) -> void:
	super(dt)
	if phase == "done": return
	left -= dt
	if phase == "run": _track()
	if left > 0.0: return
	match phase:
		"ready": _open()
		"run": _close()
		"reveal": _next()

func state() -> Dictionary:
	var shown := phase == "run" or phase == "reveal"
	var current := _current()
	return {"phase": phase, "round": number, "rounds": ROUNDS, "left": maxf(left, 0.0),
		"line": str(current.get("text", "")) if shown else "", "ask": bool(current.get("ask", false)) if shown else false,
		"answer": answer_slots() if phase == "reveal" else [], "first": first if phase == "reveal" else -1,
		"right": right.duplicate() if phase == "reveal" else [], "scores": scores.duplicate(), "out": out()}

func finished() -> bool:
	return phase == "done"

## "<WINNER> WINS", "TIE: A & B" (up to three), "<n>-WAY TIE", or "NO WINNER" when nobody scored. A player who left cannot win.
func results() -> Dictionary:
	var standing: Array = range(host.count).filter(func(slot: int) -> bool: return not bool(gone[slot]))
	if standing.is_empty(): standing = range(host.count)
	var top := 0
	for slot: int in standing: top = maxi(top, int(scores[slot]))
	var winners: Array = standing.filter(func(slot: int) -> bool: return int(scores[slot]) == top) if top > 0 else []
	var names := PackedStringArray()
	for slot: int in winners: names.append(host.name(slot))
	var headline := "NO WINNER"
	if winners.size() == 1: headline = "%s WINS" % names[0]
	elif winners.size() > 3: headline = "%d-WAY TIE" % winners.size()
	elif winners.size() > 1: headline = "TIE: %s & %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
	return {"headline": headline, "sub": score_line(scores), "scores": scores.duplicate(), "winners": winners}

## The player's pad stays and its lines still come up (the answer is that pad); nobody is sent there and it scores no more.
func drop(slot: int) -> void:
	if slot >= 0 and slot < gone.size():
		gone[slot] = true
		on[slot] = -1

## The slots whose pad is right this round (two characters with the same catchphrase: both).
func answer_slots() -> Array:
	return (_current().get("slots", []) as Array).duplicate()

## The slots that left.
func out() -> Array:
	return range(gone.size()).filter(func(slot: int) -> bool: return bool(gone[slot]))

# ------------------------------------------------------------------ the round

func _current() -> Dictionary:
	if number < 1 or number > order.size(): return {}
	var index := int(order[number - 1])
	return lines[index] if index >= 0 and index < lines.size() else {}

func _playing(slot: int) -> bool:
	return not bool(gone[slot]) and host.active(slot)

## The line shows: who already stands on a pad stays on it, but that stay cannot win FIRST_POINTS.
func _open() -> void:
	phase = "run"
	left += RUN # what the last tick ran over counts: every phase as long as it says
	for slot in host.count:
		on[slot] = pad_under(host.position(slot), _pads) if _playing(slot) else -1
		since[slot] = time
		early[slot] = int(on[slot]) >= 0

func _track() -> void:
	for slot in host.count:
		var pad := pad_under(host.position(slot), _pads, int(on[slot])) if _playing(slot) else -1
		if pad == int(on[slot]): continue
		on[slot] = pad
		since[slot] = time
		early[slot] = false

## The round closes: the earliest arrival on a right pad (not an early one) gets FIRST_POINTS, everybody else on one ON_POINTS.
func _close() -> void:
	var answer := answer_slots()
	first = -1
	right = []
	var earliest := INF
	for slot in host.count:
		if not _playing(slot) or not answer.has(int(on[slot])): continue
		right.append(slot)
		if not bool(early[slot]) and float(since[slot]) < earliest:
			earliest = float(since[slot])
			first = slot
	right.erase(first)
	if first >= 0: scores[first] += FIRST_POINTS
	for slot: int in right: scores[slot] += ON_POINTS
	phase = "reveal"
	left += REVEAL

func _next() -> void:
	if number >= ROUNDS:
		phase = "done"
		left = 0.0
		return
	number += 1
	phase = "ready"
	left += READY
	first = -1
	right = []
	_send_all()

## Everybody still playing back to the start ring; the spots turn one place every round, so nobody keeps the nearest one.
func _send_all() -> void:
	var count: int = host.count
	for slot in count:
		if _playing(slot): host.send_to(slot, start_point(posmod(slot + number - 1, count), count), 0.0)

# ------------------------------------------------------------------ the lines

## The catchphrases of the round's characters (a character without one has no line). Fewer than two: the cast's words and eggs fill
## in, each given to a character round-robin (from a random one) and asked as "Who would say: <line>?".
func _lines() -> Array:
	var result: Array = []
	var seen := {} ## lower-case text -> index in result
	for slot in host.count:
		var text := str(host.player(slot).get("catchphrase", "")).strip_edges()
		if text == "": continue
		var key := text.to_lower()
		if seen.has(key): (result[seen[key]].slots as Array).append(slot)
		else:
			seen[key] = result.size()
			result.append({"text": text, "slots": [slot], "ask": false})
	if result.size() >= 2 or host.count < 1: return result
	var extra: Array = []
	for key: String in WORD_KEYS: extra.append(TeamCast.word(key))
	for index in range(1, TeamCast.EGGS + 1): extra.append(TeamCast.egg(index))
	var turn: int = host.rng.randi_range(0, host.count - 1)
	for entry: String in extra:
		var text := entry.strip_edges()
		if text == "" or seen.has(text.to_lower()): continue
		seen[text.to_lower()] = result.size()
		result.append({"text": text, "slots": [turn % host.count], "ask": true})
		turn += 1
	return result

## ROUNDS line indices: the lines shuffled (host.rng), dealt again as often as needed, never the same line twice in a row.
func _schedule(size: int) -> Array:
	var result: Array = []
	if size <= 0: return result
	while result.size() < ROUNDS:
		var deck: Array = range(size)
		for i in range(size - 1, 0, -1):
			var j: int = host.rng.randi_range(0, i)
			var swap: int = deck[i]
			deck[i] = deck[j]
			deck[j] = swap
		if not result.is_empty() and size > 1 and int(deck[0]) == int(result.back()):
			var j: int = host.rng.randi_range(1, size - 1)
			deck[0] = deck[j]
			deck[j] = result.back()
		result.append_array(deck)
	result.resize(ROUNDS)
	return result

## What the players read: the line itself, or "Who would say: <line>?" for a word or an egg (no "?" after one that ends a sentence).
static func prompt(line: String, ask: bool) -> String:
	if not ask or line == "": return line
	return "Who would say: %s%s" % [line, "" if line.right(1) in ["?", "!", "."] else "?"]

# ------------------------------------------------------------------ the yard (shared: the rules decide with it, the view draws it)

static var _ring_cache := {}

## The pads of a round of `count` characters, slot k's pad k: {at (its middle on the yard floor, world), out (flat unit vector away
## from the ring's middle)}. Spread evenly along the ring by length, the first half a step clockwise from north.
static func pads(count: int) -> Array:
	if count <= 0: return []
	if not _ring_cache.has(count):
		var depth := maxf(MIN_DEPTH, count * PAD_GAP / _perimeter(1.0))
		var width := depth * ASPECT
		var lengths := PackedFloat32Array([0.0])
		for step in RING_STEPS: lengths.append(lengths[step] + _ring(width, depth, step).distance_to(_ring(width, depth, step + 1)))
		var total := lengths[RING_STEPS]
		var result: Array = []
		var step := 0
		for k in count:
			var goal := total * (k + 0.5) / count
			while step < RING_STEPS - 1 and lengths[step + 1] < goal: step += 1
			var t := (goal - lengths[step]) / maxf(lengths[step + 1] - lengths[step], 0.0001)
			var point := _ring(width, depth, step).lerp(_ring(width, depth, step + 1), t)
			var normal := Vector2((point.x - CENTER.x) / (width * width), (point.y - CENTER.y) / (depth * depth)).normalized()
			result.append({"at": WalkInLobby.ORIGIN + Vector3(point.x, 0.0, point.y), "out": Vector3(normal.x, 0.0, normal.y)})
		_ring_cache[count] = result
	return (_ring_cache[count] as Array).duplicate(true)

## The ring's middle on the yard floor, world.
static func middle() -> Vector3:
	return WalkInLobby.ORIGIN + Vector3(CENTER.x, 0.0, CENTER.y)

## Spot `index` of `count` on the start ring (world, at the yard spots' height); spot 0 is north of the middle.
static func start_point(index: int, count: int) -> Vector3:
	var at := middle() + Vector3(0.0, START_LIFT, 0.0)
	if count <= 1: return at
	var angle := TAU * index / count
	return at + Vector3(sin(angle), 0.0, -cos(angle)) * START_RADIUS

## The pad (index into `list`, from pads()) feet at `at` stand on, -1 for none. `previous` is kept up to EXIT, any other pad needs ENTER.
static func pad_under(at: Vector3, list: Array, previous := -1) -> int:
	if not at.is_finite(): return -1
	var height := at.y - WalkInLobby.FLOOR_Y
	if height < -BELOW or height > ABOVE: return -1
	if previous >= 0 and previous < list.size() and _flat(at, list[previous].at) <= EXIT: return previous
	for k in list.size():
		if _flat(at, list[k].at) <= ENTER: return k
	return -1

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Sample `step` of RING_STEPS along the ellipse, yard-local (x, z), clockwise from north.
static func _ring(width: float, depth: float, step: int) -> Vector2:
	var angle := TAU * step / RING_STEPS
	return CENTER + Vector2(width * sin(angle), -depth * cos(angle))

static func _perimeter(depth: float) -> float:
	var total := 0.0
	for step in RING_STEPS: total += _ring(depth * ASPECT, depth, step).distance_to(_ring(depth * ASPECT, depth, step + 1))
	return total
