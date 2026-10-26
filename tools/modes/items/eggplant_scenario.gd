extends RefCounted
## HOT EGGPLANT (the experiment, docs/items.md) end to end: the authority and two replica clients with the show's real view.
## 1. The clock hands the first eggplant out 40-44 s into the race to a racer, a front runner more often than the last (measured over many draws), and the switch file says on for 29-32 only.
## 2. A forced eggplant on slot 0: one effect in the state with the tuning (25 % slower: 0.75, lower jumps: 0.8), the owner's machine gets the mods, the model hangs on the carrier's rig on both
##    machines (a face, a harness), the "EGGPLANT!" banner on its own screen, the line on the other's, the pill on the owner's screen only.
## 3. A bump passes it: slot 1 stands on slot 0, the effect moves (src = 0, the time left carried over, not restarted), the same eggplant flies over (it is the one node, reparented), the banner is slot 1's,
##    both read "<name> PASSED IT TO <name>"; slot 0 cannot take it back for the 2 s of immunity and gets it back after them (the bump goes on); a carrier must hold it 0.6 s before it may pass it.
## 4. A GRAB passes it too: slot 0 carries it, stands 1.15 m from slot 2 (out of bump reach, inside grab reach), presses GRAB: slot 2 wears it.
## 5. It pops when its time is up (an END event, the carrier's screen reads "DELIVERED!", confetti and chunks, the mods are gone) and at the finish line.
## 6. Nobody is a carrier when the carrier is the only racer who is left in a field of more (no handout), and a round that ends takes it off everybody.
## Frames (`--shots`, view 0 = slot 0): carrying, the pass in the air, the new carrier, the pop.
const REACH := 1.05 ## items.json eggplant reach

func _seat(h, slot: int) -> int:
	for seat in 3:
		if h.controller._slot(seat) == slot: return seat
	return -1

func _rows(h, kind: int) -> Array:
	var rows: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == kind: rows.append(row)
	return rows

func _has_model(h, replica: int, slot: int) -> bool:
	var rig: Node3D = h.replicas[replica].rigs[slot]
	return rig != null and rig.get_node_or_null("Eggplant") != null

func _lines(h, view: int) -> Array:
	return h.views[view]._items._lines.map(func(l: Dictionary) -> String: return str(l.text))

func _clear_screens(h) -> void:
	for view in 2:
		h.views[view]._items._banner = {}
		h.views[view]._items._lines.clear()

func run(h) -> void:
	for slot in 3: h.hold(slot)
	h.progress(0, 60.0)
	h.progress(1, 40.0)
	h.progress(2, 20.0)
	await h.tick(30)
	var items = h.rules().items
	var rule = items.rules_of.get("eggplant")
	var kind: int = items.Catalog.index("eggplant")
	h.check(kind == 7 and rule != null and rule.active, "the race has the HOT EGGPLANT rule, switched on (kind %d)" % kind)
	h.check(items.Catalog.EVENTS.find("eggplant") < 0 and items.Catalog.HELD.find("eggplant") < 0, "no box rolls it and the clock's events do not draw it")
	for number in [29, 30, 31, 32]: h.check(rule.on(number), "the switch file is on for race %d" % number)
	h.check(not rule.on(1) and not rule.on(25) and not rule.on(33), "and off for the levels it does not list (1, 25, 33)")
	h.check(h.state().items.fx.is_empty(), "nothing is on anybody before the first handout")
	# ------------------------------------------------------------ 1. the clock (not in a render: too long for frames)
	items._next_event_at = 1.0e9 # the boost and soar clock stays out of it
	h.rules().manager._next_at = 1.0e9 # and so does the manager's (its own check is manager_check.gd; the gate's own is event_gate_check.gd)
	if h.shots == "":
		var came: bool = await h.wait_until(func() -> bool: return not _rows(h, kind).is_empty(), 60 * 60)
		var at: float = items.time
		h.check(came and at >= 39.5 and at <= 44.6, "the clock straps the first eggplant on 40-44 s into the race (%.1f s)" % at)
		h.check(h.rules().gate.running == "eggplant", "the handout holds the event gate (%s)" % h.rules().gate.running)
		var first: Array = _rows(h, kind)[0] if came else [0, -1, -1, 0, 0, 0, 0, -1]
		h.check(items.racers().has(int(first[1])) and int(first[7]) == -1, "to a racer, sent by nobody (slot %d, src %d)" % [int(first[1]), int(first[7])])
		h.check(is_equal_approx(float(first[3]), 20.0) and is_equal_approx(float(first[5]), 0.75) and is_equal_approx(float(first[6]), 0.8), "for 20 s with speed 0.75 and jump 0.8 (%s)" % str(first))
		h.check(_rows(h, kind).size() == 1, "one eggplant at a time")
		var next_at: float = rule._next_at
		h.check(next_at - at >= 80.9 and next_at - at <= 99.1, "the next one is 81-99 s on (%.1f s later)" % (next_at - at))
		items.end_fx(items.fx_of(int(first[1]), "eggplant"))
		rule.holder = -1
		await h.tick(10)
		# the bias: draw the pick many times with the field standing as it is (slot 0 ahead, slot 2 last)
		var counts := [0, 0, 0]
		var live: Array = items.racers()
		for draw in 300:
			rule._hand_out(live, items.time)
			for row: Dictionary in items.fx: counts[int(row.slot)] += 1
			items.fx.clear()
			rule.holder = -1
		h.check(counts[0] >= 120 and counts[0] > counts[1] and counts[1] > counts[2] and counts[2] >= 25, "a front runner is likelier than the back: leader %d, middle %d, last %d of 300" % [counts[0], counts[1], counts[2]])
		rule._next_at = 1.0e9
		await h.tick(10)
	rule._next_at = 1.0e9 # a render has no time for the clock
	items.fx.clear()
	rule.holder = -1
	await h.tick(10)
	_clear_screens(h)
	# ------------------------------------------------------------ 2. a forced eggplant on slot 0
	h.shoot("before")
	await h.tick(4)
	rule.happen(0)
	await h.tick(12)
	var rows := _rows(h, kind)
	h.check(rows.size() == 1 and int(rows[0][1]) == 0 and int(rows[0][7]) == -1, "the eggplant is on slot 0 only (%s)" % str(rows))
	var mods: Dictionary = h.replicas[0].item_mods.get(0, {})
	h.check(is_equal_approx(float(mods.get("speed", 0.0)), 0.75) and is_equal_approx(float(mods.get("jump", 0.0)), 0.8) and is_equal_approx(float(mods.get("dash", 0.0)), 0.75), "its owner's machine is 25 %% slower with lower jumps (item_mods %s)" % str(mods))
	var banner: Dictionary = h.views[0]._items._banner
	h.check(str(banner.get("words", "")) == "EGGPLANT!" and str(banner.get("kind", "")) == "alert", "the carrier's screen has the banner (%s)" % str(banner))
	var told := false
	for line: String in _lines(h, 1): told = told or (line.contains("MAYA") and line.contains("EGGPLANT"))
	h.check(told, "the other screen reads who got it (%s)" % str(_lines(h, 1)))
	h.check(_has_model(h, 0, 0) and _has_model(h, 1, 0), "the eggplant hangs on the carrier's back on both machines")
	h.check(not _has_model(h, 0, 1) and not _has_model(h, 0, 2), "and on nobody else's")
	var model: Node3D = h.replicas[1].rigs[0].get_node("Eggplant")
	var parts := ["Body", "Calyx", "Stem", "BandLow", "BandHigh", "Face", "Harness"].filter(func(n: String) -> bool: return model.get_node_or_null(n) == null)
	h.check(parts.is_empty(), "it has a body, a calyx, a stem, two bands, a face and a harness (missing %s)" % str(parts))
	var box: AABB = (model.get_node("Body") as MeshInstance3D).get_aabb()
	var whole := AABB(box.position, box.size).merge((model.get_node("Stem") as MeshInstance3D).get_aabb())
	h.check(whole.size.y >= 2.9 and whole.size.y <= 3.3, "about 3 m long (%.2f m)" % whole.size.y)
	var pill: Array = h.views[0]._items.over_layer.get_children().filter(func(n: Node) -> bool: return n.name == "EggplantPill")
	h.check(pill.size() == 1 and h.views[1]._items.over_layer.get_children().filter(func(n: Node) -> bool: return n.name == "EggplantPill").is_empty(), "the seconds pill is on the carrier's screen only")
	await h.tick(40)
	for view in 2: for node in h.views[view]._items.get_children(): if node.name.begins_with("EggplantPop"): node.queue_free() # what the made-up clear of the draws above left
	h.shoot("carry")
	# ------------------------------------------------------------ 3. a bump passes it
	h.progress(1, 60.0) # slot 1 onto slot 0
	await h.tick(14)
	var passed: bool = await h.wait_until(func() -> bool: return not _rows(h, kind).is_empty() and int(_rows(h, kind)[0][1]) == 1, 60 * 2)
	h.check(passed, "a bump hands it to slot 1")
	rows = _rows(h, kind)
	h.check(rows.size() == 1 and int(rows[0][1]) == 1 and int(rows[0][7]) == 0, "one effect, on slot 1, sent by slot 0 (%s)" % str(rows))
	h.check(float(rows[0][3]) > 15.0 and float(rows[0][3]) < 20.0, "with the time that was left (%.1f s of 20 s), not a new 20 s" % float(rows[0][3]))
	h.check(rule.passes == 1 and rule.holder == 1, "the rule counts one pass (holder %d)" % rule.holder)
	await h.tick(8)
	h.shoot("pass")
	await h.tick(12)
	h.check(not h.replicas[0].item_mods.has(0) and is_equal_approx(float(h.replicas[1].item_mods.get(1, {}).get("speed", 0.0)), 0.75), "slot 0 is free again and slot 1's machine is slower (%s / %s)" % [str(h.replicas[0].item_mods), str(h.replicas[1].item_mods)])
	await h.tick(40) # the pass flies for 0.55 s, then the eggplant hangs on the new carrier's rig
	h.check(_has_model(h, 0, 1) and _has_model(h, 1, 1) and not _has_model(h, 0, 0) and not _has_model(h, 1, 0), "the eggplant is on slot 1's back now, on both machines, and gone from slot 0's")
	var pop_nodes := 0
	for view in 2: pop_nodes += h.views[view]._items.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("EggplantPop") and n.get_node("Flash").scale.x > 0.0).size()
	h.check(pop_nodes == 0, "a pass is no pop (%d)" % pop_nodes)
	banner = h.views[1]._items._banner
	h.check(str(banner.get("words", "")) == "EGGPLANT!", "slot 1's screen has the banner (%s)" % str(banner.get("words", "")))
	var line_ok := false
	for line: String in _lines(h, 0): line_ok = line_ok or line == "MAYA PASSED IT TO THEO"
	h.check(line_ok, "the others read who passed it (%s)" % str(_lines(h, 0)))
	# the immunity: slot 0 stands on slot 1 and may not have it back for 2 s after the pass
	var passed_at: float = rule._since
	var back_early := false
	while items.time < passed_at + 1.9:
		await h.tick(1)
		if rule.holder == 0: back_early = true
	h.check(not back_early and rule.passes == 1, "slot 0 cannot take it back inside its 2 s of immunity (%.2f s after the pass)" % (items.time - passed_at))
	var back: bool = await h.wait_until(func() -> bool: return rule.holder == 0, 60 * 3)
	await h.tick(8)
	h.check(back and rule.passes == 2 and int(_rows(h, kind)[0][7]) == 1, "and the bump hands it back after them (passes %d)" % rule.passes)
	h.progress(1, 80.0) # slot 1 off to the front, nobody is near slot 0 any more
	await h.tick(30)
	# ------------------------------------------------------------ 4. a GRAB passes it
	_clear_screens(h)
	h.check(rule.holder == 0, "slot 0 carries it again")
	var route: PackedVector3Array = h.sim.level_world.route(int(h.state().level))
	var dir := Vector3(route[3].x - route[0].x, 0.0, route[3].z - route[0].z).normalized()
	var start: Vector3 = route[0] + dir * 1.0 + Vector3.UP * 0.05 # on the start deck, whatever the level
	rule.active = false # the racers fly across the course to their spots (10 m a tick): they must not bump on the way
	h.hold(1)
	h.progress(1, 90.0)
	h.warp[_seat(h, 0)] = start - dir * 2.5 # slot 0 stands 2.5 m behind its spot, slot 2 1.15 m past it: 3.65 m apart
	h.warp[_seat(h, 2)] = start + dir * 1.15
	await h.tick(30)
	h.warp[_seat(h, 0)] = start # a step of 2.5 m along `dir`: it faces slot 2, which stands 1.15 m ahead
	await h.tick(4)
	rule._since = items.time - 1.0
	var gap: float = items.host.position(0).distance_to(items.host.position(2))
	var before_pass: int = rule.passes
	h.check(gap > REACH + 0.02 and gap < 1.3, "slot 2 stands %.2f m from slot 0: out of bump reach, inside the grab's" % gap)
	rule.active = true
	await h.tick(50)
	h.check(rule.passes == before_pass and rule.holder == 0, "standing there is not a bump")
	h.press_grab(0)
	var grabbed: bool = await h.wait_until(func() -> bool: return rule.holder == 2, 60)
	h.check(grabbed and rule.passes == before_pass + 1, "a GRAB hands it to slot 2 (holder %d, passes %d, held by %s)" % [rule.holder, rule.passes, str(items.host.held_by(2))])
	await h.tick(50) # the pass flies for 0.55 s
	# ------------------------------------------------------------ 5. the pop: time, and the finish line
	_clear_screens(h)
	var wearer: int = rule.holder
	h.shoot("before_pop")
	var entry: Dictionary = items.fx_of(wearer, "eggplant")
	entry.age = float(entry.dur) - 0.15
	await h.tick(24)
	var viewer := wearer if wearer < 2 else -1
	h.check(_rows(h, kind).is_empty() and rule.holder == -1, "the eggplant is gone when its time is up")
	var ended := false
	var pop_ev: Array = h.state().items.ev.filter(func(e: Array) -> bool: return int(e[1]) == items.Event.END and int(e[2]) == kind)
	ended = pop_ev.size() == 1 and int(pop_ev[0][4]) == wearer
	h.check(ended, "an END event names the carrier (%s)" % str(pop_ev))
	if viewer >= 0:
		h.check(str(h.views[viewer]._items._banner.get("words", "")) == "DELIVERED!" and str(h.views[viewer]._items._banner.get("kind", "")) == "boon", "the carrier's screen says DELIVERED! (%s)" % str(h.views[viewer]._items._banner))
	var pops := 0
	for view in 2: pops += 1 if h.views[view]._items.get_node_or_null("EggplantPop") != null else 0
	h.check(pops == 2, "the confetti burst is in the air on both machines (%d)" % pops)
	h.shoot("pop")
	h.check(not _has_model(h, 0, wearer) and not _has_model(h, 1, wearer), "the model is gone from the carrier's rig on both machines")
	h.check(h.replicas[0].item_mods.is_empty() and h.replicas[1].item_mods.is_empty() and h.replicas[0].follow.fx.is_empty(), "every owner's machine is free again (%s / %s / %s)" % [str(h.replicas[0].item_mods), str(h.replicas[1].item_mods), str(h.replicas[0].follow.fx)])
	await h.tick(60 * 3)
	for view in 2: h.check(h.views[view]._items.get_node_or_null("EggplantPop") == null, "the confetti is cleaned up on view %d" % view)
	# the finish line: slot 2 wears it and crosses the goal
	h.progress(1, 80.0)
	h.progress(0, 70.0)
	await h.tick(20)
	rule.happen(2)
	await h.tick(10)
	h.check(rule.holder == 2 and not _rows(h, kind).is_empty(), "slot 2 wears a new one")
	h.release(2)
	h.speed[2] = 0.13
	h.progress(2, 1.0e6) # the end of the route: the goal
	var crossed: bool = await h.wait_until(func() -> bool: return (h.rules().across as Array).has(2), 60 * 8)
	await h.tick(12)
	h.check(crossed and _rows(h, kind).is_empty() and rule.holder == -1, "it pops at the finish line (across %s)" % str(h.rules().across))
	var pop_goal: Array = h.state().items.ev.filter(func(e: Array) -> bool: return int(e[1]) == items.Event.END and int(e[4]) == 2)
	h.check(pop_goal.size() >= 1, "with an END event for slot 2")
	h.check(not _has_model(h, 0, 2) and not _has_model(h, 1, 2), "and the model is gone")
	# ------------------------------------------------------------ 6. a lone racer in a field gets none; the round's end takes it off everybody
	for slot in 2: h.hold(slot)
	rule._next_at = 0.0
	var alone: Array = items.racers()
	await h.tick(30)
	h.check(alone.size() >= 2 or _rows(h, kind).is_empty(), "with one racer left in a field of more the clock hands out nothing")
	rule.happen(0)
	await h.tick(6)
	h.check(not _rows(h, kind).is_empty(), "(a forced one on slot 0 to end the round with)")
	items.finish()
	await h.tick(8)
	h.check(not h.state().has("items") or _rows(h, kind).is_empty(), "the round's end clears it")
