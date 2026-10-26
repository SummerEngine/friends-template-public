extends RefCounted
## EXPERIMENT (switchable): THE MANAGER, rules side. Built by modes/show/rules.gd, begun with every race and tile round, ticked with its play phase, on the authority and in the local
## game; it only reads positions and presses through the host and keeps everything that counts. It never touches a node.
##   At the round's start one random player of the field is named THE MANAGER. `first` s into the play (then every `every` s, counted from one prompt to the next; about every 60-75 s)
##   the manager is asked for a RULE, when the show's event gate lets it (shared/event_gate.gd: one interrupting event at a time, 15 s apart; the prompt waits for it, the rule holds
##   it until it ends): 3 random choices of the offered ones (never the one issued last). The manager picks with the number keys 1 2 3 (`test_seq`: seq * 8 + the number, as the item lab), a
##   press of ITEM (E, Y, the phone's ITEM button) picks a random one of the three, a phone taps the cards (the view sends the same number keys); a bot picks at random after `bot` s,
##   and a manager that says nothing for `prompt` s (3 s: a strip at the bottom edge, not a panel) gets a random one. The rule then applies to everybody else still racing (or standing) for 10-15 s, `lead` s after it was issued
##   (so the banner lands first). A show for one player has no one else: the rule hits the player itself, `solo_lead` s after (the item lab's way of making a rule visible).
## What a rule does is on the owners' machines (a courier moves on its own machine and the authority only checks poses): the clients read `rule`, `age`, `dur` and `tg` of the state
## and put the rule's mods on the targets' couriers (manager_view.gd, game/game_run.gd rule_mods). Docs: docs/party-show.md "The manager (experiment)".
const Catalog := preload("res://modes/show/shared/manager/manager_catalog.gd")
const Gate := preload("res://modes/show/shared/event_gate.gd")

enum Phase { IDLE, PROMPT, RULE } ## the `ph` of the state
const GATE := "manager" ## the kind this asks the event gate under
const RULE_SPAN := 30.0 ## s: the longest rule a cast can set (Catalog.duration clamps to it): what the gate is told to expect
const ECHO := 0.6 ## s after a pick that the manager's presses are still taken (the key's second event)

var rules ## modes/show/rules.gd
var host
var enabled := false ## the round has a manager
var manager := -1 ## the slot of THE MANAGER
var phase := Phase.IDLE
var time := 0.0 ## s of play
var left := 0.0 ## s the prompt stays open
var choices: Array = [] ## the 3 offered rules (indexes into Catalog.order())
var rule := -1 ## the rule in force (Phase.RULE), its index
var dur := 0.0
var age := 0.0 ## s since the rule was issued, -lead while it is still to start
var seq := 0 ## rules issued this round (a view tells each one once)
var prompts := 0 ## prompts opened this round
var targets: Array = [] ## the slots the rule applies to now
var solo := false ## a show for one: the rule applies to the manager itself
var rng := RandomNumberGenerator.new()
var _next_at := 0.0
var _last := -1
var _lead := 0.0
var _seen_item := 0
var _seen_test := 0
var _grace_until := 0.0 ## play time until which the manager's presses are still its own: a typed key is two events (down and up), the second must not hand out a lab item

func _init(show_rules) -> void:
	rules = show_rules
	host = show_rules.host

## A round starts on `level` (index) of `round_kind`: a manager is named among `field` when the switch (manager.json) is on for it.
func begin(round_level: int, round_kind: String, field: Array) -> void:
	finish()
	enabled = false
	manager = -1
	time = 0.0
	seq = 0
	prompts = 0
	rule = -1
	_last = -1
	solo = field.size() == 1
	if field.is_empty() or round_level < 0 or not Catalog.on_for(round_level, round_kind) or Catalog.offered().is_empty(): return
	rng.seed = int(host.rng.seed) + round_level * 6151 + int(rules.round_index) * 7727 + 13
	manager = int(field[rng.randi_range(0, field.size() - 1)])
	enabled = true
	_next_at = _schedule("first")

## The round is over: no prompt, no rule. (The state keeps the manager's name until the next round begins.)
func finish() -> void:
	rules.gate.end(GATE)
	rules.gate.cancel(GATE)
	phase = Phase.IDLE
	rule = -1
	targets = []
	choices = []

## A player left: a manager who left is replaced by another player of the field.
func drop(slot: int) -> void:
	if not enabled or slot != manager: return
	var live: Array = rules.field.filter(func(candidate: int) -> bool: return candidate != slot and not rules.gone.has(candidate) and host.active(candidate))
	if live.is_empty():
		manager = -1
		finish()
		return
	manager = int(live[rng.randi_range(0, live.size() - 1)])
	if phase == Phase.PROMPT: _open_seen()

## True while the prompt is open for `slot` (and for ECHO s after a pick): its ITEM and number presses pick a rule and do nothing else (items.gd leaves them alone).
func takes_presses(slot: int) -> bool:
	return enabled and slot == manager and (phase == Phase.PROMPT or time < _grace_until)

func tick(dt: float) -> void:
	if not enabled: return
	time += dt
	targets = _targets()
	match phase:
		Phase.IDLE:
			if time >= _next_at and not targets.is_empty(): _ask()
		Phase.PROMPT:
			left -= dt
			var pick := _pressed()
			if pick < 0 and _is_bot(manager) and float(Catalog.timing("prompt")) - left >= float(Catalog.timing("bot")): pick = rng.randi_range(0, choices.size() - 1)
			if pick < 0 and left <= 0.0: pick = rng.randi_range(0, choices.size() - 1) # a manager who says nothing gets a random rule
			if pick >= 0 and targets.is_empty(): pick = -1 # everybody else has crossed the line or fallen: nobody to rule over
			if pick >= 0: _issue(int(choices[pick]))
			elif left <= -2.0: _close() # a prompt nobody could use for a while
		Phase.RULE:
			age += dt
			if age >= dur: _end_rule()

## The slots the rule applies to: everybody else still racing or standing; alone, the player itself.
func _targets() -> Array:
	var live: Array = rules.field.filter(func(slot: int) -> bool: return not rules.gone.has(slot) and host.active(slot) and int(rules.status[slot]) == rules.PLAYING)
	if solo: return live
	return live.filter(func(slot: int) -> bool: return slot != manager)

func _schedule(key: String) -> float:
	var range_s: Variant = Catalog.timing(key)
	return time + (rng.randf_range(float((range_s as Array)[0]), float((range_s as Array)[1])) if range_s is Array and (range_s as Array).size() == 2 else 30.0)

## The prompt is due: the gate says when. WAIT keeps asking each tick (the prompt can wait); SKIP (another event already queued ahead) tries again after Gate.RETRY s.
func _ask() -> void:
	match rules.gate.request(GATE, float(Catalog.timing("prompt")) + float(Catalog.timing("solo_lead")) + RULE_SPAN):
		Gate.Verdict.GRANTED: _open()
		Gate.Verdict.SKIP: _next_at = time + Gate.RETRY

func _open() -> void:
	var pool: Array = Catalog.offered().map(func(id: String) -> int: return Catalog.index(id))
	if pool.size() > 1 and pool.has(_last): pool.erase(_last) # never the same rule twice running
	choices = []
	while choices.size() < Catalog.CHOICES and not pool.is_empty():
		var at := rng.randi_range(0, pool.size() - 1)
		choices.append(pool[at])
		pool.remove_at(at)
	if choices.is_empty():
		rules.gate.end(GATE)
		return
	phase = Phase.PROMPT
	left = float(Catalog.timing("prompt"))
	prompts += 1
	_next_at = _schedule("every")
	_open_seen()

## What the manager pressed before the prompt does not count.
func _open_seen() -> void:
	_seen_item = host.presses(manager, "item") if host.has_method("presses") else 0
	_seen_test = host.presses(manager, "test") if host.has_method("presses") else 0

## The choice (0..2) the manager's input says now, -1 for none: a number key 1-3, or ITEM for a random one of the three.
func _pressed() -> int:
	if not host.has_method("presses"): return -1
	var test: int = host.presses(manager, "test")
	var item: int = host.presses(manager, "item")
	var number := (test & 7) if test != _seen_test else 0
	var surprised := item != _seen_item
	_seen_test = test
	_seen_item = item
	if number >= 1 and number <= choices.size(): return number - 1
	if surprised: return rng.randi_range(0, choices.size() - 1)
	return -1

func _is_bot(slot: int) -> bool:
	return host.has_method("is_bot") and bool(host.call("is_bot", slot))

func _issue(kind: int) -> void:
	_grace_until = time + ECHO
	rule = kind
	_last = kind
	var id := Catalog.id_of(kind)
	dur = Catalog.duration(id, rng)
	_lead = float(Catalog.timing("solo_lead" if solo else "lead"))
	age = -_lead
	seq += 1
	phase = Phase.RULE
	choices = []

func _end_rule() -> void:
	phase = Phase.IDLE
	rule = -1
	rules.gate.end(GATE)

func _close() -> void:
	phase = Phase.IDLE
	choices = []
	rules.gate.end(GATE)

# ------------------------------------------------------------------ the state the views get

func state() -> Dictionary:
	return {"mgr": manager, "ph": int(phase), "t": snappedf(maxf(left, 0.0), 0.1), "ch": choices.duplicate(), "rule": rule, "dur": snappedf(dur, 0.1), "age": snappedf(age, 0.05),
		"seq": seq, "tg": targets.duplicate(), "solo": solo, "round": int(rules.round_index)}
