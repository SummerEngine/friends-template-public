extends RefCounted
## The show's items and events, rules side (docs/items.md). Built by modes/show/rules.gd, ticked with the race's play phase, on the authority and in the local game; it only reads
## positions and presses through the host and keeps everything that counts. It never touches a node. Clients get `state()` (`items` in the show's state) and draw the rest: the boxes,
## the held item in the HUD, the projectiles, the effects (modes/show/items_ui/items_view.gd); the effects that change how a courier moves are applied by its owner's machine from the
## replicated effect (game/game_run.gd item_mods), because couriers move on their own machines and the authority only checks their poses.
##
## The pieces:
##   boxes     the level's `item_boxes` (docs/level-format.md): a racer standing in one without an item takes a roll, the box is gone for BOX_RESPAWN s (state `boxes`: a bit per box, set = there)
##   held      per slot the catalog index of the item it holds (-1 none); an item is usable `roll` s after the pick (the HUD spins for that long); one press of ITEM uses it
##   effects   `fx`: what is on a slot now, {id, slot, kind, dur, age, a, b, src}; a client runs one from the moment it is listed to the moment it is gone
##   projects  `proj`: what flies (the call, the filmed video), moved by its item's rule
##   events    `ev`: the last few things told to the views, [seq, type, kind, a, b] (a client tells each seq once: banners, lines and sounds)
## Every item or event is one script per side under modes/show/items/: `<id>_rules.gd` here (extends item_rule.gd) and `<id>_view.gd` on the clients (extends item_look.gd).
const RULES := { ## the rules script of every item and event (one per side, docs/items.md)
	"smash": preload("res://modes/show/items/smash_rules.gd"),
	"call": preload("res://modes/show/items/call_rules.gd"),
	"flip": preload("res://modes/show/items/flip_rules.gd"),
	"glitch": preload("res://modes/show/items/glitch_rules.gd"),
	"dance": preload("res://modes/show/items/dance_rules.gd"),
	"boost": preload("res://modes/show/items/boost_rules.gd"),
	"soar": preload("res://modes/show/items/soar_rules.gd"),
	"eggplant": preload("res://modes/show/items/eggplant_rules.gd")} ## (the experiment HOT EGGPLANT: its own clock and switch, hot_eggplant.json)

const TeamCast := preload("res://style/team_cast.gd")
const Catalog := preload("res://modes/show/items/catalog.gd")
const ItemRule := preload("res://modes/show/items/item_rule.gd")
const Gate := preload("res://modes/show/shared/event_gate.gd")
const EVENT_GATE := "clock" ## the kind the clock's BOOST / SOAR ask the event gate under
const EVENT_SPAN := 8.0 ## s: the longest boost or soar the gate is told to expect (its tuning maxes at 8)

enum Event { PICK, USE, HIT, END } ## the `ev` types: a racer took an item (a = slot), used it (a = user, b = the first it hit or -1), an effect began on a slot (b = slot, a = who sent it or -1), an effect ended early (b = slot)
const EVENT_KEEP := 8 ## events remembered in the state
const BOX_REACH_Y := Vector2(-0.6, 2.0) ## m over the box's feet spot a racer's feet must be within
const STATE_EFFECTS := 24 ## most effects listed

var rules ## modes/show/rules.gd
var host
var enabled := false ## this round has boxes
var solo := false ## one racer only (a show for one player): the boxes hand out the events' effects (boost, soar) as items, the clock hands out nothing, the lab's attack items hit the racer itself
var time := 0.0 ## s of play
var level := -1
var rng := RandomNumberGenerator.new()
var boxes := PackedVector3Array()
var box_back := PackedFloat32Array() ## per box: s until it is there again (0 = there)
var held: Array = [] ## per slot: catalog index, -1 none
var roll_left: Array = [] ## per slot: s until the held item may be used
var fx: Array = [] ## effects, see above
var projectiles: Array = [] ## {id, kind (catalog index), p, v, tgt, age, a (the rule's number)}
var events: Array = []
var rules_of := {} ## kind id -> ItemRule
var _seen_presses: Array = []
var _seen_tests: Array = [] ## per slot: the last item-lab press (seq * 8 + the id's number 1-7) the authority acted on
var lab := false ## the item lab (cast show.item_lab): a lab press hands a racer an item or event
var _next_id := 1
var _next_seq := 1
var _next_event_at := 0.0
var _last_event_kind := ""

func _init(show_rules) -> void:
	rules = show_rules
	host = show_rules.host

## A race round starts on `level`: the boxes the level lists, nothing held, nothing on anybody.
func begin(round_level: int, kind: String, racers: int) -> void:
	finish()
	enabled = false
	solo = racers < 2
	level = round_level
	boxes = PackedVector3Array()
	events.clear()
	projectiles.clear()
	fx.clear()
	held = []
	roll_left = []
	_seen_presses = []
	_seen_tests = []
	lab = TeamCast.show_item_lab()
	for slot in host.count:
		held.append(-1)
		roll_left.append(0.0)
		_seen_presses.append(host.presses(slot, "item") if host.has_method("presses") else 0)
		_seen_tests.append(host.presses(slot, "test") if host.has_method("presses") else 0)
	if kind != "race" or level < 0 or racers < 1 or not host.has_method("item_boxes"): return
	boxes = host.item_boxes(level)
	if boxes.is_empty(): return
	rules_of.clear()
	for id: String in Catalog.KINDS:
		var script: Variant = RULES.get(id)
		if script == null or Catalog.off(id): continue
		var rule: ItemRule = (script as GDScript).new()
		rule.setup(self, id)
		rules_of[id] = rule
	enabled = not _held_pool().is_empty()
	box_back = PackedFloat32Array()
	box_back.resize(boxes.size())
	time = 0.0
	rng.seed = int(host.rng.seed) + level * 7919 + rules.round_index * 104729
	var first: Array = Catalog.event("first")
	_next_event_at = rng.randf_range(float(first[0]), float(first[1])) if first.size() == 2 else 18.0
	_last_event_kind = ""
	for rule: ItemRule in rules_of.values(): rule.begin()

## The round is over (or a new one starts): nothing is on anybody any more, so every owner is free.
func finish() -> void:
	if fx.is_empty() and projectiles.is_empty() and not enabled: return
	for slot in held.size():
		held[slot] = -1
	fx.clear()
	projectiles.clear()
	enabled = false

# ------------------------------------------------------------------ services for the item rules

## The slots racing now: in the field, in the game, not across the goal.
func racers() -> Array:
	return rules.field.filter(func(slot: int) -> bool: return not rules.gone.has(slot) and host.active(slot) and not rules.across.has(slot) and int(rules.status[slot]) == rules.PLAYING)

## The racers an attack item of the lab may hit when nobody else is racing: the user itself (a show for one player has no other racer; the lab shows what each item does).
## Empty outside the lab and in a race with company.
func self_test(user: int) -> Array:
	return [user] if lab and solo and racers().has(user) else []

## Race position of `slot` among the racers (0 leads); the field's size when it is not racing.
func rank(slot: int) -> int:
	var order: Array = racers_in_order()
	var at := order.find(slot)
	return at if at >= 0 else order.size()

## The racers best first (by how far along the route they are).
func racers_in_order() -> Array:
	var live: Array = racers()
	live.sort_custom(func(a: int, b: int) -> bool: return float(rules._progress[a]) > float(rules._progress[b]) or (float(rules._progress[a]) == float(rules._progress[b]) and a < b))
	return live

## The racers in front of `slot`, nearest first.
func ahead_of(slot: int) -> Array:
	var order: Array = racers_in_order()
	var at := order.find(slot)
	if at < 0: return []
	var result: Array = order.slice(0, at)
	result.reverse()
	return result

## The racers behind `slot`, nearest first.
func behind_of(slot: int) -> Array:
	var order: Array = racers_in_order()
	var at := order.find(slot)
	return order.slice(at + 1) if at >= 0 else []

## The racer in the lead, not counting `except` (-1 for the plain leader).
func leader(except := -1) -> int:
	for slot: int in racers_in_order():
		if slot != except: return slot
	return -1

func position_of(slot: int) -> Vector3:
	return host.position(slot)

func tune(id: String, key: String) -> float:
	return Catalog.tuning(id, key)

## Puts effect `kind_id` on `slot` for `duration` s (`a` and `b` are the item's own numbers, `src` the slot that sent it); one of the same kind on the slot starts over. Returns the effect.
func add_fx(slot: int, kind_id: String, duration: float, a := 0.0, b := 0.0, src := -1) -> Dictionary:
	for old: Dictionary in fx:
		if int(old.slot) == slot and int(old.kind) == Catalog.index(kind_id):
			fx.erase(old)
			break
	var entry := {"id": _next_id, "slot": slot, "kind": Catalog.index(kind_id), "dur": duration, "age": 0.0, "a": a, "b": b, "src": src}
	_next_id += 1
	fx.append(entry)
	if fx.size() > STATE_EFFECTS: fx.pop_front()
	announce(Event.HIT, kind_id, src, slot)
	return entry

func fx_of(slot: int, kind_id: String) -> Dictionary:
	for entry: Dictionary in fx:
		if int(entry.slot) == slot and int(entry.kind) == Catalog.index(kind_id): return entry
	return {}

## Takes an effect off early (its slot knows from the entry going away; `told` adds an END event for the views).
func end_fx(entry: Dictionary, told := false) -> void:
	if not fx.has(entry): return
	fx.erase(entry)
	if told: announce(Event.END, Catalog.id_of(int(entry.kind)), -1, int(entry.slot))

## Puts a projectile in the air: `from` the world position, `velocity` m/s, `target` the slot it goes for (-1 none), `a` the rule's number. Returns it (the rule moves it and removes it).
func spawn(kind_id: String, from: Vector3, velocity: Vector3, target := -1, a := 0.0) -> Dictionary:
	var shot := {"id": _next_id, "kind": Catalog.index(kind_id), "p": from, "v": velocity, "tgt": target, "age": 0.0, "a": a}
	_next_id += 1
	projectiles.append(shot)
	return shot

func remove_projectile(shot: Dictionary) -> void:
	projectiles.erase(shot)

## Something the views should tell once: a banner, a line, a sound.
func announce(type: int, kind_id: String, a: int, b: int) -> void:
	events.append([_next_seq, type, Catalog.index(kind_id), a, b])
	_next_seq += 1
	while events.size() > EVENT_KEEP: events.pop_front()

# ------------------------------------------------------------------ the tick

func tick(dt: float) -> void:
	if not enabled: return
	time += dt
	for index in boxes.size(): box_back[index] = maxf(box_back[index] - dt, 0.0)
	for slot in held.size():
		roll_left[slot] = maxf(float(roll_left[slot]) - dt, 0.0)
	for entry: Dictionary in fx.duplicate():
		entry.age = float(entry.age) + dt
	var live: Array = racers()
	# a slot that crossed the goal, fell out or left drops what it held and what is on it
	for slot in held.size():
		if live.has(slot): continue
		held[slot] = -1
		for entry: Dictionary in fx.duplicate():
			if int(entry.slot) == slot: fx.erase(entry)
	_pickups(live)
	_presses_of(live)
	for rule: ItemRule in rules_of.values(): rule.tick(dt)
	for entry: Dictionary in fx.duplicate():
		if float(entry.age) >= float(entry.dur):
			fx.erase(entry)
			var rule: ItemRule = rules_of.get(Catalog.id_of(int(entry.kind)))
			if rule != null: rule.ended(entry)
	_events_clock(live)

## A racer without an item that stands in a box that is there takes a roll; the box is gone for a while.
func _pickups(live: Array) -> void:
	if live.size() < (1 if solo else 2): return
	var reach := Catalog.box("radius")
	for slot: int in live:
		if int(held[slot]) >= 0: continue
		var feet: Vector3 = host.position(slot)
		for index in boxes.size():
			if box_back[index] > 0.0: continue
			var spot := boxes[index]
			if Vector2(feet.x - spot.x, feet.z - spot.z).length() > reach: continue
			if feet.y - spot.y < BOX_REACH_Y.x or feet.y - spot.y > BOX_REACH_Y.y: continue
			var kind := _roll(slot, live)
			if kind < 0: break
			box_back[index] = Catalog.box("respawn")
			held[slot] = kind
			roll_left[slot] = Catalog.box("roll")
			announce(Event.PICK, Catalog.id_of(kind), slot, index)
			break

## The kind a racer at its position rolls: the weights of the catalog by race position; a kind nobody could be hit by is not on the table.
func _roll(slot: int, live: Array) -> int:
	var place := rank(slot)
	var table: Array = []
	var total := 0.0
	for id: String in _held_pool():
		var weight := 1.0 if solo else Catalog.weight_at(id, place, live.size()) # alone every kind is as likely
		if weight <= 0.0: continue
		table.append([id, weight])
		total += weight
	if table.is_empty(): return Catalog.index("flip") if rules_of.has("flip") else -1
	var pick := rng.randf() * total
	for entry: Array in table:
		pick -= float(entry[1])
		if pick <= 0.0: return Catalog.index(str(entry[0]))
	return Catalog.index(str((table.back() as Array)[0]))

## The items this round can roll: the held kinds that have a rules script and are not switched off by the cast; alone nobody could be hit, so a box hands out the events' effects
## (boost, soar: a held one is used on its owner by one press of ITEM).
func _held_pool() -> Array:
	return (Catalog.EVENTS if solo else Catalog.HELD).filter(func(id: String) -> bool: return rules_of.has(id))

## One press of ITEM uses the held item when its roll is over; a press with nothing held, or while it spins, is spent.
func _presses_of(live: Array) -> void:
	if lab: _lab_presses(live)
	for slot in held.size():
		var count: int = host.presses(slot, "item")
		var fresh := count > int(_seen_presses[slot])
		_seen_presses[slot] = count
		if not fresh or not live.has(slot) or int(held[slot]) < 0 or float(roll_left[slot]) > 0.0 or _manager_asks(slot): continue
		var id := Catalog.id_of(int(held[slot]))
		var rule: ItemRule = rules_of.get(id)
		if rule == null: continue
		rule.aimed = -1
		if Catalog.EVENTS.has(id): # a boost or soar from a box (alone): it happens to its owner, its banner is the effect's
			rule.happen(slot)
			held[slot] = -1
			continue
		if not rule.use(slot): continue # a rule that has nobody to hit keeps the item with its player
		held[slot] = -1
		announce(Event.USE, id, slot, rule.aimed)

## True while the manager's prompt (modes/show/manager/) is open for `slot`: its ITEM and number presses pick a rule, they use nothing and hand out nothing.
func _manager_asks(slot: int) -> bool:
	return rules.manager != null and rules.manager.takes_presses(slot)

## The item lab: a press of 1-7 (the order of Catalog.KINDS) puts that item in the racer's slot at once, replacing what it holds, or (6, 7) makes the event happen to it now.
func _lab_presses(live: Array) -> void:
	for slot in held.size():
		var code: int = host.presses(slot, "test")
		var fresh: bool = code != int(_seen_tests[slot])
		_seen_tests[slot] = code
		if not fresh or not live.has(slot) or _manager_asks(slot): continue
		var number := code & 7
		if number < 1 or number > Catalog.KINDS.size(): continue
		var id: String = Catalog.KINDS[number - 1]
		if Catalog.off(id): continue
		if Catalog.EVENTS.has(id):
			var rule: ItemRule = rules_of.get(id)
			if rule != null: rule.happen(slot)
		else:
			held[slot] = number - 1
			roll_left[slot] = 0.0
			announce(Event.PICK, id, slot, 0)

## The clock hands a runner at the back a BOOST or SOAR now and then (`event.first` s into the race, then `event.every`), when the show's event gate lets it (one interrupting event at a time,
## 15 s apart: it waits for its turn, and one that finds another already waiting asks again after Gate.RETRY s). The gate is told when the effect is gone.
func _events_clock(live: Array) -> void:
	if rules.gate.running == EVENT_GATE and none_on_anybody(Catalog.EVENTS): rules.gate.end(EVENT_GATE)
	if time < _next_event_at or live.size() < 2: return # alone the boxes hand them out
	var every: Array = Catalog.event("every")
	var wait_s: float = rng.randf_range(float(every[0]), float(every[1])) if every.size() == 2 else 25.0
	match rules.gate.request(EVENT_GATE, EVENT_SPAN):
		Gate.Verdict.WAIT: return
		Gate.Verdict.SKIP:
			_next_event_at = time + Gate.RETRY
			return
	_next_event_at = time + wait_s
	var pool: Array = Catalog.EVENTS.filter(func(id: String) -> bool: return rules_of.has(id) and id != _last_event_kind)
	if pool.is_empty(): pool = Catalog.EVENTS.filter(func(id: String) -> bool: return rules_of.has(id))
	if pool.is_empty():
		rules.gate.end(EVENT_GATE)
		return
	var order: Array = racers_in_order()
	var weights: Array = []
	var total := 0.0
	var bias := float((Catalog.data().get("event", {}) as Dictionary).get("back_bias", 2.0))
	for place in order.size():
		var slot: int = order[place]
		var taken := not fx_of(slot, "boost").is_empty() or not fx_of(slot, "soar").is_empty()
		var f := float(place) / float(maxi(order.size() - 1, 1))
		var weight := 0.0 if taken else pow(0.15 + f, bias)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		rules.gate.end(EVENT_GATE)
		return
	var pick := rng.randf() * total
	var chosen: int = order[order.size() - 1]
	for place in order.size():
		pick -= float(weights[place])
		if pick <= 0.0:
			chosen = order[place]
			break
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	_last_event_kind = id
	(rules_of[id] as ItemRule).happen(chosen)

## True when none of the event kinds `ids` is on anybody.
func none_on_anybody(ids: Array) -> bool:
	for entry: Dictionary in fx:
		if ids.has(Catalog.id_of(int(entry.kind))): return false
	return true

## A player left or crossed: its item and effects go.
func drop(slot: int) -> void:
	if slot >= 0 and slot < held.size(): held[slot] = -1
	for entry: Dictionary in fx.duplicate():
		if int(entry.slot) == slot: fx.erase(entry)

# ------------------------------------------------------------------ the state the views get

func state() -> Dictionary:
	var mask := 0
	for index in boxes.size():
		if box_back[index] <= 0.0 and index < 62: mask |= 1 << index
	var list: Array = []
	for entry: Dictionary in fx:
		list.append([int(entry.id), int(entry.slot), int(entry.kind), snappedf(float(entry.dur), 0.01), snappedf(float(entry.age), 0.05), snappedf(float(entry.a), 0.01), snappedf(float(entry.b), 0.01), int(entry.src)])
	var flying: Array = []
	for shot: Dictionary in projectiles:
		var p: Vector3 = shot.p
		var v: Vector3 = shot.v
		flying.append([int(shot.id), int(shot.kind), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1), int(shot.tgt), snappedf(float(shot.age), 0.05)])
	var spin: Array = []
	for slot in roll_left.size(): spin.append(snappedf(float(roll_left[slot]), 0.1))
	return {"held": held.duplicate(), "spin": spin, "boxes": mask, "fx": list, "proj": flying, "ev": events.duplicate(true)}
