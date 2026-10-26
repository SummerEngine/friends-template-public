extends "res://modes/mode_rules.gd"
## FRIEND SWAP rules (docs/modes/friend_swap.md): everyone plays as someone else, then everyone guesses who is who.
##  * The start: every slot gets another slot's character (perm[slot]: that cast member's look, name tag and catchphrase), a
##    derangement drawn from host.rng, so nobody keeps their own (with two players they simply swap).
##  * PLAY_SECONDS of free play in the yard. The action button (either lift key, press edge) makes the character say its
##    catchphrase, at most once every LINE_GAP seconds; lines[slot] counts them so every view pops the bubble.
##  * Then one vote per character, in a shuffled order. Everyone is sent to a ring round the yard centre and one pad per player
##    appears on a wider ring (labelled with that player's real name, in a shuffled order). Everyone but the character's player
##    runs to the pad of who they think plays it. At the close a voter on the right pad scores 1, and the character's player
##    scores 1 for every voter on a wrong pad (good acting); a voter on no pad did not guess. A short reveal shows the player.
##  * The end: after the last reveal. A player who leaves (drop) votes no more; the character they played is skipped.
## Decided from host time, the players' feet and the action button only; the view draws the pads where state() puts them.

const PLAY_SECONDS := 60.0
const INTRO_SECONDS := 5.0 ## the first seconds of the free play: the view shows "YOU ARE <NAME>" big
const VOTE_SECONDS := 8.0
const REVEAL_SECONDS := 3.5
const LINE_GAP := 2.0 ## seconds between two lines of one player
const PAD_RING := 5.6 ## m from the yard centre to the middle of every vote pad: pads and boards clear of the playground and furniture
const PAD_RADIUS := 1.1 ## feet within this (horizontally) of a pad's middle stand on it
const PAD_BELOW := 0.7 ## the vertical window over the floor that counts as on the pad (a jump on it still counts)
const PAD_ABOVE := 2.6
const START_RING := 1.2 ## m: the ring the players are sent to before a vote, wider by RING_PER_PLAYER for each player
const RING_PER_PLAYER := 0.08
const FEET_LIFT := 0.25 ## send_to puts the feet this far over the floor, like the yard spots

var phase := "play" ## play | vote | reveal | done
var phase_end := PLAY_SECONDS ## host time the phase ends
var perm: Array = [] ## slot -> the slot whose character it plays
var lines: Array = [] ## slot -> catchphrases said
var scores: Array = [] ## slot -> points
var shown: Array = [] ## slot -> true once its own player was revealed (its character's vote closed)
var gone: Array = [] ## slots that left
var order: Array = [] ## the characters (slots) to vote on, in voting order; a character whose player left is taken out
var index := 0 ## order index of the next or current vote
var closed := 0 ## votes closed so far
var pads: Array = [] ## [slot, x, z] per pad of the current vote
var on: Array = [] ## slot -> the pad (its slot) the player stands on during a vote, -1 none
var picks: Array = [] ## slot -> its vote at the last close: a pad slot, -1 no pad, -2 not voting
var right := 0 ## voters on the right pad at the last close
var wrong := 0 ## voters on a wrong pad at the last close
var _held: Array = []
var _said_at: Array = []

func start(round_host) -> void:
	super(round_host)
	var count: int = host.count
	perm = _derangement(count)
	for slot in count:
		lines.append(0)
		scores.append(0)
		shown.append(false)
		on.append(-1)
		picks.append(-1)
		_held.append(false)
		_said_at.append(-LINE_GAP)
	order = range(count)
	_shuffle(order)
	phase = "play"
	phase_end = PLAY_SECONDS

func tick(dt: float) -> void:
	super(dt)
	if phase == "done": return
	if _players().size() < 2:
		_finish()
		return
	_listen()
	if phase == "vote": _watch_pads()
	if time < phase_end: return
	match phase:
		"play": _next_vote()
		"vote": _close_vote()
		"reveal":
			index += 1
			_next_vote()

func state() -> Dictionary:
	var target := _target()
	return {"phase": phase, "left": maxf(phase_end - time, 0.0), "perm": perm.duplicate(), "lines": lines.duplicate(),
		"scores": scores.duplicate(), "shown": shown.duplicate(), "gone": gone.duplicate(), "target": target,
		"actor": perm.find(target) if target >= 0 else -1, "vote": index + 1 if target >= 0 else 0, "votes": order.size(),
		"closed": closed, "pads": pads.duplicate(true) if target >= 0 else [], "floor": host.floor_y(),
		"on": on.duplicate() if phase == "vote" else [], "picks": picks.duplicate() if phase == "reveal" else [],
		"right": right, "wrong": wrong}

func finished() -> bool:
	return phase == "done"

## Winners: the best score among the players still there. "<NAME> WINS"; a tie names everyone in it.
func results() -> Dictionary:
	var pool := _players()
	if pool.is_empty(): pool = range(scores.size())
	var top := -1
	for slot: int in pool: top = maxi(top, int(scores[slot]))
	var winners := pool.filter(func(slot: int) -> bool: return int(scores[slot]) == top)
	var names := PackedStringArray()
	for slot: int in winners: names.append(str(host.name(slot)).to_upper())
	var headline := ""
	if names.size() == 1: headline = "%s WINS" % names[0]
	elif names.size() <= 4: headline = "%s AND %s WIN" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]
	elif not names.is_empty(): headline = "A %d-WAY TIE" % names.size()
	return {"headline": headline, "sub": score_line(scores), "scores": scores.duplicate(), "winners": winners}

## The slot left: it votes no more, and the character it played is skipped (its vote stops if it is on now).
func drop(slot: int) -> void:
	if slot < 0 or slot >= perm.size() or gone.has(slot): return
	gone.append(slot)
	on[slot] = -1
	var at := order.find(int(perm[slot]))
	if at < 0 or phase == "done": return
	if phase == "vote" and at == index:
		order.remove_at(at)
		_next_vote()
	elif at > index or (at == index and phase == "play"):
		order.remove_at(at)

# ------------------------------------------------------------------ the round

## Starts the vote on order[index]; the end when there is none left.
func _next_vote() -> void:
	while index < order.size() and not _in(perm.find(int(order[index]))): order.remove_at(index)
	var players := _players()
	if index >= order.size() or players.size() < 2:
		_finish()
		return
	phase = "vote"
	phase_end = time + VOTE_SECONDS
	right = 0
	wrong = 0
	for slot in on.size():
		on[slot] = -1
		picks[slot] = -1
	# One pad per player, in a shuffled order round a wider ring, turned at random: where a name stands says nothing.
	var labels := players.duplicate()
	_shuffle(labels)
	var turn: float = host.rng.randf() * TAU
	pads = []
	for k in labels.size():
		var at := _around(turn + TAU * k / labels.size(), PAD_RING)
		pads.append([int(labels[k]), at.x, at.z])
	# Everybody back to a ring round the centre, in a shuffled order, facing it: the race to the pads starts even.
	var ring := players.duplicate()
	_shuffle(ring)
	var radius := START_RING + RING_PER_PLAYER * ring.size()
	var middle: Vector3 = host.yard_center()
	for k in ring.size():
		var at := _around(TAU * k / ring.size(), radius) + Vector3.UP * FEET_LIFT
		host.send_to(int(ring[k]), at, atan2(at.x - middle.x, at.z - middle.z))

## The close: the voters' feet decide, then the reveal.
func _close_vote() -> void:
	_watch_pads()
	var actor := perm.find(int(order[index]))
	right = 0
	wrong = 0
	for slot in perm.size():
		picks[slot] = -2
		if slot == actor or not _in(slot): continue
		var pick := int(on[slot])
		picks[slot] = pick
		if pick < 0: continue
		if pick == actor:
			scores[slot] = int(scores[slot]) + 1
			right += 1
		else: wrong += 1
	if actor >= 0:
		scores[actor] = int(scores[actor]) + wrong
		shown[actor] = true
	closed += 1
	phase = "reveal"
	phase_end = time + REVEAL_SECONDS

func _finish() -> void:
	phase = "done"
	pads = []

## The action button's press edge says the line, LINE_GAP seconds apart at most (not while a reveal shows).
func _listen() -> void:
	for slot in perm.size():
		var down: bool = _in(slot) and host.action(slot)
		if down and not bool(_held[slot]) and phase != "reveal" and time - float(_said_at[slot]) >= LINE_GAP:
			lines[slot] = int(lines[slot]) + 1
			_said_at[slot] = time
		_held[slot] = down

func _watch_pads() -> void:
	for slot in on.size(): on[slot] = _pad_at(host.position(slot)) if _in(slot) else -1

## The pad (its slot) under these feet, -1 for none.
func _pad_at(feet: Vector3) -> int:
	if not feet.is_finite(): return -1
	var height: float = feet.y - host.floor_y()
	if height < -PAD_BELOW or height > PAD_ABOVE: return -1
	for pad: Array in pads:
		if Vector2(feet.x - float(pad[1]), feet.z - float(pad[2])).length() <= PAD_RADIUS: return int(pad[0])
	return -1

func _target() -> int:
	return int(order[index]) if (phase == "vote" or phase == "reveal") and index < order.size() else -1

func _in(slot: int) -> bool:
	return slot >= 0 and slot < perm.size() and not gone.has(slot) and host.active(slot)

## The slots still playing.
func _players() -> Array:
	var result: Array = []
	for slot in perm.size():
		if _in(slot): result.append(slot)
	return result

## A point on the yard floor `radius` from its centre, `angle` round from +Z.
func _around(angle: float, radius: float) -> Vector3:
	var middle: Vector3 = host.yard_center()
	return Vector3(middle.x + sin(angle) * radius, host.floor_y(), middle.z + cos(angle) * radius)

## A random order with nobody in their own place (redrawn until it is one; a shift by one if that ever runs long).
func _derangement(count: int) -> Array:
	var result: Array = range(count)
	if count < 2: return result
	for attempt in 64:
		_shuffle(result)
		if not _fixed(result): return result
	result = []
	for slot in count: result.append((slot + 1) % count)
	return result

static func _fixed(list: Array) -> bool:
	for slot in list.size():
		if int(list[slot]) == slot: return true
	return false

func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j: int = host.rng.randi_range(0, i)
		var keep: Variant = list[i]
		list[i] = list[j]
		list[j] = keep
