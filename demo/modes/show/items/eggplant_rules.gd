extends "res://modes/show/items/item_rule.gd"
## HOT EGGPLANT (EXPERIMENT, switchable; switch and per-race overrides: hot_eggplant.json): a cursed parcel. Now and then (`first` s into the race, then about every `every` s from the
## last handout) the clock straps a giant eggplant to one runner's back, a front runner more likely (`bias`). It is an effect (`eggplant`, kind 7) on that slot: its owner's machine walks
## `a` times as fast and jumps `b` times as high (eggplant_view.gd `mods`), nobody can drop it. It is only passed on: a bump (a runner within `reach` m of the carrier) or a GRAB between
## the carrier and another racer hands it over, and whoever passed it cannot take it back for `immune` s. It pops after `duration` s, or when its carrier crosses the goal (or leaves the
## race): an END event the views tell, confetti and the cast's "pop" banner. Alone (a show for one player) the same clock puts it on the player: nobody to pass it to, it pops in time.
## The authority decides everything here: positions come from the owners' poses (`host.position`), grabs from the contact simulation (`host.held_by`); the views only draw.
## One effect entry at a time. A pass ends the carrier's entry and starts one on the receiver (`src` = the passer, the rest of the time left), so a client sees "new effect with a source"
## and flies the same eggplant across; the HIT event of it is what the receiver's banner and the others' line are.
const Gate := preload("res://modes/show/shared/event_gate.gd")
const CONFIG := "res://modes/show/items/hot_eggplant.json"
const FORMAT := "hot-eggplant-1"
const HOLD_MIN := 0.6 ## s a new carrier keeps it before it may pass it on (one bump in a crowd does not carry it through the pack)
const REACH_Y := 1.5 ## m: a runner this far above or below the carrier's feet is not a bump
const FIRST_SPREAD := 4.0 ## s: the first handout lies in `first` .. `first` + this
const EVERY_SPREAD := 0.1 ## the gap between handouts varies by this share

static var _parsed: Dictionary = {}
static var _read := false

var active := false ## the experiment is on for this race
var holder := -1 ## the slot wearing it now, -1 for nobody
var passes := 0 ## passes this race (the checks read it)
var given := 0 ## handouts this race
var popped := 0 ## eggplants that popped this race (time, the goal)
var _rng := RandomNumberGenerator.new()
var _next_at := 0.0 ## s of play of the next handout
var _since := 0.0 ## s of play the carrier got it
var _immune := {} ## slot -> s of play until it cannot be handed the eggplant (it just passed it)
var _held_before := {} ## slot -> who held it a tick ago (the grab's rising edge)

## The experiment's switch for race `number` (the level file's number, 29-32): true when the file says `on` for it. No file, a wrong format, `"on": false` or an unlisted race: false.
static func on(number: int) -> bool:
	if not _read:
		_read = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG)) if FileAccess.file_exists(CONFIG) else null
		_parsed = parsed if parsed is Dictionary else {}
	if str(_parsed.get("format", "")) != FORMAT or not bool(_parsed.get("on", false)): return false
	var levels: Variant = _parsed.get("levels")
	if not levels is Dictionary: return false
	var entry: Variant = (levels as Dictionary).get(str(number))
	return entry is Dictionary and bool(entry.get("on", false))

func begin() -> void:
	active = on(items.level + 1)
	holder = -1
	passes = 0
	given = 0
	popped = 0
	_immune.clear()
	_held_before.clear()
	_rng.seed = int(items.rng.seed) + 31337 # its own stream: the clock's and the boxes' draws are the ones they were
	_next_at = _rng.randf_range(items.tune(id, "first"), items.tune(id, "first") + FIRST_SPREAD)

func tick(_dt: float) -> void:
	if not active: return
	var now: float = items.time
	var live: Array = items.racers()
	if holder >= 0 and items.fx_of(holder, id).is_empty(): # the carrier crossed the goal or left: the eggplant pops there
		_pop(holder)
	if holder >= 0: _pass_on(live, now)
	elif now >= _next_at and (live.size() >= 2 or items.solo) and not live.is_empty(): _ask(live, now)
	for slot: int in live: _held_before[slot] = items.host.held_by(slot)

## An effect of this kind ran out: the eggplant pops on its carrier.
func ended(entry: Dictionary) -> void:
	if int(entry.slot) == holder: _pop(holder)

## The eggplant is put on `slot` now (a tool, the lab): whoever wore it loses it quietly.
func happen(slot: int) -> void:
	if holder >= 0: items.end_fx(items.fx_of(holder, id))
	_strap(slot, items.tune(id, "duration"), -1)
	given += 1

## A handout is due: the show's event gate (one interrupting event at a time, 15 s apart) says when. WAIT: asked again next tick; SKIP (another event is queued ahead): asks again after Gate.RETRY s.
func _ask(live: Array, now: float) -> void:
	match items.rules.gate.request(id, items.tune(id, "duration")):
		Gate.Verdict.GRANTED: _hand_out(live, now)
		Gate.Verdict.SKIP: _next_at = now + Gate.RETRY

## The clock's pick: a racer, a front runner `bias` times as likely as the last one.
func _hand_out(live: Array, now: float) -> void:
	var order: Array = items.racers_in_order()
	var weights: Array = []
	var total := 0.0
	var bias: float = items.tune(id, "bias")
	for place in order.size():
		var f := float(place) / float(maxi(order.size() - 1, 1))
		var weight := lerpf(bias, 1.0, clampf(f * 1.5, 0.0, 1.0)) # the front third has the full bias, the back third none
		weights.append(weight)
		total += weight
	var pick := _rng.randf() * total
	var chosen: int = order[order.size() - 1]
	for place in order.size():
		pick -= float(weights[place])
		if pick <= 0.0:
			chosen = order[place]
			break
	_strap(chosen, items.tune(id, "duration"), -1)
	given += 1
	_next_at = now + items.tune(id, "every") * _rng.randf_range(1.0 - EVERY_SPREAD, 1.0 + EVERY_SPREAD)

## Puts the eggplant on `slot` for `left` s; `from` is the slot that passed it (-1: the clock).
func _strap(slot: int, left: float, from: int) -> void:
	items.add_fx(slot, id, left, items.tune(id, "speed"), items.tune(id, "jump"), from)
	holder = slot
	_since = items.time

## The carrier bumps into somebody, or one grabbed the other (the rising edge of the grab): the nearest racer that may take it gets it.
func _pass_on(live: Array, now: float) -> void:
	if now - _since < HOLD_MIN: return
	var me := holder
	var here: Vector3 = items.host.position(me)
	var reach: float = items.tune(id, "reach")
	var best := -1
	var best_gap := INF
	for slot: int in live:
		if slot == me or now < float(_immune.get(slot, 0.0)): continue
		var there: Vector3 = items.host.position(slot)
		var gap := Vector2(there.x - here.x, there.z - here.z).length()
		var bumped: bool = gap <= reach and absf(there.y - here.y) <= REACH_Y and items.host.held_by(slot) < 0
		var grabbed: bool = (items.host.held_by(slot) == me and int(_held_before.get(slot, -1)) != me) or (items.host.held_by(me) == slot and int(_held_before.get(me, -1)) != slot)
		if not bumped and not grabbed: continue
		if grabbed: gap = 0.0
		if gap < best_gap:
			best_gap = gap
			best = slot
	if best < 0: return
	var entry: Dictionary = items.fx_of(me, id)
	var left := maxf(float(entry.dur) - float(entry.age), 0.5)
	items.end_fx(entry)
	_strap(best, left, me)
	_immune[me] = now + items.tune(id, "immune")
	passes += 1

## It is over on `slot` (time, the goal, or the player left): the views pop it.
func _pop(slot: int) -> void:
	holder = -1
	items.rules.gate.end(id)
	popped += 1
	items.announce(items.Event.END, id, -1, slot)
