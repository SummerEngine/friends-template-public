extends RefCounted
## SOAR end to end.
## 1. The clock's own event (40-55 s into the race, to a racer, told by the clients) and the rule that the same event never comes twice running.
## 2. A forced SOAR on slot 0 (`happen`): the effect in the state with its tuning; the owner's machine gets the jump and the air jump (item_mods); the views counter on the owner's screen reads 10K,
##    then 100K, then 1M by the end (and holds it); the others' screens get the small VIEWS pill over the runner's head and the line instead; the ribbon trails the runner; the lens opens on a jump;
##    everything is gone when the seconds are up.
## 3. CourierMotion units on a private floor: the jump with the mod goes jump^2 times as high; a second press in the air gives a second jump with the mod (once, not a third time, not from a
##    held button) and none without it.
## Frames (`--shots`, view 0 = the soaring runner, `--view=1` = a bystander): toast, k100, jump, m1.
const CourierMotion := preload("res://courier/courier_motion.gd")

func _fx_of(h, id: int) -> Array:
	var rows: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == id: rows.append(row)
	return rows

func _stand(h, ahead: float, middle: float, behind: float) -> void:
	h.progress(0, ahead)
	h.progress(1, middle)
	h.progress(2, behind)

## The effect entry the client at `view` keeps for SOAR (the manager's own copy).
func _entry(h, view: int, id: int) -> Dictionary:
	for entry: Dictionary in h.views[view]._items._fx.values():
		if int(entry.kind) == id: return entry
	return {}

func run(h) -> void:
	for slot in 3: h.hold(slot)
	await h.tick(20)
	var items = h.rules().items
	var soar: int = items.Catalog.index("soar")
	var look = h.views[0]._items.look_of("soar")
	_stand(h, 5.0, 3.0, 1.0)
	await h.tick(10)
	# ------------------------------------------------------------ 1. the clock (not in a render: too long for frames)
	h.rules().manager._next_at = 1.0e9 # the manager would hold the event gate: its own check is manager_check.gd
	if h.shots == "":
		var came: bool = await h.wait_until(func() -> bool: return not h.state().items.fx.is_empty(), 60 * 60)
		var at: float = items.time
		h.check(came and at >= 40.0 and at <= 55.5, "the clock hands the first event out 40-55 s into the race (%.1f s)" % at)
		var first: Array = h.state().items.fx[0] if came else [0, -1, -1]
		var first_kind: String = items.Catalog.id_of(int(first[2]))
		h.check((first_kind == "boost" or first_kind == "soar") and items.racers().has(int(first[1])), "it is a BOOST or a SOAR (%s) and goes to racer %d" % [first_kind, int(first[1])])
		await h.tick(12)
		var victim := int(first[1])
		for view in 2:
			var shown = h.views[view]._items
			if view == victim: h.check(str(shown._banner.get("words", "")) != "", "the event's own screen shows a banner (%s)" % str(shown._banner.get("words", "")))
			else:
				var told := false
				for line: Dictionary in shown._lines: told = told or str(line.text).contains(shown.name_of(victim))
				h.check(told, "replica %d reads a line that names racer %d" % [view, victim])
		items.fx.clear()
		await h.tick(10)
		items._next_event_at = 0.0
		h.rules().gate.reset()
		items._events_clock(items.racers())
		h.check(not items.fx.is_empty() and items.Catalog.id_of(int(items.fx[0].kind)) != first_kind, "the next event is the other kind, never the same twice running (%s after %s)" % [items.Catalog.id_of(int(items.fx[0].kind)) if not items.fx.is_empty() else "none", first_kind])
		items.fx.clear()
		items._next_event_at = 1.0e9
	if h.shots != "": items._next_event_at = 1.0e9 # a render has no time for the clock
	# ------------------------------------------------------------ 2. a forced SOAR on slot 0
	await h.tick(10)
	_stand(h, 6.0, 4.0, 2.0)
	await h.tick(12)
	h.check(items.rules_of.has("soar"), "the round has the SOAR rule")
	for view in 2: # what the clock's events left on the screens
		h.views[view]._items._banner = {}
		h.views[view]._items._lines.clear()
	h.shoot("before")
	await h.tick(6)
	h.release(0)
	h.speed[0] = 0.13
	(items.rules_of["soar"] as RefCounted).happen(0)
	await h.tick(12)
	var rows := _fx_of(h, soar)
	h.check(rows.size() == 1 and int(rows[0][1]) == 0 and int(rows[0][7]) == -1, "SOAR is on slot 0 only, sent by nobody (%s)" % str(rows))
	var row: Array = rows[0]
	h.check(is_equal_approx(float(row[3]), items.tune("soar", "duration")) and is_equal_approx(float(row[5]), items.tune("soar", "jump")) and is_equal_approx(float(row[6]), items.tune("soar", "air_jumps")),
		"the effect carries duration %.1f, jump %.1f, air jumps %.0f" % [float(row[3]), float(row[5]), float(row[6])])
	var mods: Dictionary = h.replicas[0].item_mods.get(0, {})
	h.check(is_equal_approx(float(mods.get("jump", 0.0)), items.tune("soar", "jump")) and int(mods.get("air_jumps", 0)) == int(items.tune("soar", "air_jumps")) and not mods.has("dash") and not mods.has("no_flop"), "the owner's machine jumps %.1f times as fast and has %d jump in the air, and the dash is left alone (item_mods %s)" % [items.tune("soar", "jump"), int(items.tune("soar", "air_jumps")), str(mods)])
	var banner: Dictionary = h.views[0]._items._banner
	h.check(str(banner.get("kind", "")) == "boon" and str(banner.get("words", "")) == items.Catalog.text("soar", "banner"), "the owner's screen has the boon banner (%s)" % str(banner.get("words", "")))
	h.check(h.views[1]._items._banner.is_empty(), "the other player's screen has no banner")
	var told := false
	for line: Dictionary in h.views[1]._items._lines: told = told or str(line.text).contains(h.views[1]._items.name_of(0).to_upper())
	h.check(told, "the other player reads a line naming slot 0")
	var counter: Node = null
	for child in h.views[0]._items.over_layer.get_children(): if child.has_method("_sparks"): counter = child
	h.check(counter != null, "the owner's screen has the views counter")
	h.check(h.views[1]._items.over_layer.get_children().filter(func(n: Node) -> bool: return n.has_method("_sparks")).is_empty(), "the other screen has none")
	var mine: Node3D = h.replicas[0].rigs[0]
	var theirs: Node3D = h.replicas[1].rigs[0]
	h.check(mine.get_node_or_null("SoarAura") != null and mine.get_node_or_null("SoarAura/Views") == null, "the owner's rig has the aura and no pill over its own head")
	h.check(theirs.get_node_or_null("SoarAura") != null and theirs.get_node_or_null("SoarAura/Views") != null, "the other machine's rig has the aura and the VIEWS pill")
	h.check(h.views[0]._items.get_node_or_null("SoarRibbon") != null, "the ribbon is in the world")
	var entry := _entry(h, 0, soar)
	var seen: Array = []
	var last := 0.0
	var rising := true
	var pill_text := ""
	# the owner's counter over the whole effect, sampled every tenth of a second
	h.speed[0] = 0.13
	for step in 56:
		await h.tick(6)
		entry = _entry(h, 0, soar)
		if entry.is_empty(): break
		var count: float = look.views(float(entry.age), float(entry.dur))
		rising = rising and count >= last
		last = count
		var text: String = look.counter_text(entry)
		if seen.is_empty() or seen.back() != text: seen.append(text)
		if step == 4: h.shoot("toast")
		if step == 24: h.shoot("k100")
		if step == 33:
			# a jump: the harness drives the replica's courier by poses, so say how fast it climbs and let the look read it as the owner's machine would
			h.replicas[0].actors[0].velocity = Vector3(0.0, 9.0, 0.0)
			for blink in 3: look.update_fx(entry, 0.1)
			h.views[0]._items._apply_to_shell()
			h.check(float(entry.open) > 0.7, "the lens opens on a jump (open %.2f)" % float(entry.open))
			h.check(float(h.replicas[0].follow.fx.get("fov", 0.0)) > 9.0, "the camera's lens is +%.1f degrees" % float(h.replicas[0].follow.fx.get("fov", 0.0)))
			h.shoot("jump")
		if step == 45: h.shoot("m1")
		var pill := theirs.get_node_or_null("SoarAura/Views/Words") as Label3D
		if pill != null: pill_text = pill.text
	h.check(rising, "the count only climbs")
	h.check(seen.size() >= 12 and int(seen[0]) <= 15 and look.counter_text({"age": 0.0, "dur": 5.5}) == "10K" and seen.back() == "1M", "the counter ran 10K ... 1M (%d steps: %s ... %s)" % [seen.size(), str(seen.slice(0, 3)), str(seen.slice(seen.size() - 2))])
	h.check(seen.any(func(text: String) -> bool: return text.ends_with("K") and int(text) >= 100), "it passed 100K on the way")
	h.check(pill_text.ends_with("VIEWS") and pill_text != "10K VIEWS", "the bystander's pill climbs too (%s)" % pill_text)
	var trail: MeshInstance3D = h.views[0]._items.get_node_or_null("SoarRibbon") as MeshInstance3D
	h.check(trail != null and (trail.mesh as ImmediateMesh).get_surface_count() == 2, "the ribbon has its two strands")
	var gone: bool = await h.wait_until(func() -> bool: return _fx_of(h, soar).is_empty(), 60 * 3)
	h.check(gone, "the seconds run out")
	h.speed[0] = 0.13
	await h.tick(40)
	h.check(not h.replicas[0].item_mods.has(0) and h.replicas[0].follow.fx.is_empty(), "the owner's machine is free again (mods %s)" % str(h.replicas[0].item_mods))
	h.check(mine.get_node_or_null("SoarAura") == null and theirs.get_node_or_null("SoarAura") == null and h.views[0]._items.get_node_or_null("SoarRibbon") == null, "the aura, the pill and the ribbon are gone")
	h.check(counter == null or not is_instance_valid(counter), "the counter is gone")
	# ------------------------------------------------------------ 3. the units (the headless check)
	if h.shots != "": return
	var jump: float = items.tune("soar", "jump")
	var mod := {"jump": jump, "air_jumps": int(items.tune("soar", "air_jumps"))}
	var plain := await _probe(h, {}, [0])
	var high := await _probe(h, mod, [0])
	h.check(high.apex > plain.apex * jump * jump * 0.93 and high.apex < plain.apex * jump * jump * 1.07 and high.jumps == 1, "the first jump goes %.2f m with the mod against %.2f m (%.1f times the take-off, %.1f times the height)" % [high.apex, plain.apex, jump, jump * jump])
	var twice := await _probe(h, mod, [0, 36, 42])
	h.check(twice.jumps == 2 and twice.apex > high.apex * 1.2, "a second press in the air jumps again and only once, the third press does nothing (%d jumps, apex %.2f m against %.2f m)" % [twice.jumps, twice.apex, high.apex])
	var none := await _probe(h, {"jump": jump}, [0, 36, 42])
	h.check(none.jumps == 1 and is_equal_approx(none.apex, high.apex), "without the air jump the presses in the air do nothing (%d jump)" % none.jumps)
	var held := await _probe(h, mod, range(0, 40))
	h.check(held.jumps == 1, "a button held down through the air does not spend the air jump (%d jump)" % held.jumps)
	var again := await _probe(h, mod, [0, 36, 150, 186])
	h.check(again.jumps == 4, "standing on the floor again gives the air jump back (%d jumps)" % again.jumps)

## A courier on a private floor far from the round, `presses` the ticks the jump button is down (one tick each): {apex (m over the floor), jumps (the ticks that took off or jumped again)}.
func _probe(h, mods: Dictionary, presses: Array) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(5000.0, -0.5, 5000.0)
	h.root.add_child(floor_body)
	var body: CharacterBody3D = CourierMotion.make_body("Probe")
	h.root.add_child(body)
	body.global_position = Vector3(5000.0, 0.02, 5000.0)
	var motion := CourierMotion.new()
	motion.set_mods(mods)
	var dt := 1.0 / 60.0
	for tick in 12:
		motion.step(body, {"move": Vector2.ZERO, "jump": false, "dash": false}, dt)
		await h.root.get_tree().physics_frame
	var ground := body.global_position.y
	var apex := 0.0
	var jumps := 0
	for tick in 260:
		var events: Dictionary = motion.step(body, {"move": Vector2.ZERO, "jump": presses.has(tick), "dash": false}, dt)
		await h.root.get_tree().physics_frame
		if bool(events.get("jumped", false)): jumps += 1
		if tick < 140: apex = maxf(apex, body.global_position.y - ground) # the first jump's own height (a later press starts after it)
	body.queue_free()
	floor_body.queue_free()
	return {"apex": apex, "jumps": jumps}
