extends RefCounted
## BOOST end to end, in three parts.
## 1. The clock's own event: every racer stands still with slot 2 behind; the authority hands the first event out 40-55 s into the race, to a racer, and the clients tell it (a banner on its
##    own screen, a line on the others'); then the back bias of the clock's choice is measured over many draws (slot 2 behind gets most, the leader almost none).
## 2. A forced BOOST on slot 0 (`happen`): the effect in the state with the tuning, the owner's machine gets speed and shove (item_mods, item_power, the contact's own `power`), the gold glow,
##    the "$" burst and the speed lines are there, the boon banner on the victim's screen and the line on the other's; it is all gone when the five seconds are up.
## 3. Units without the network: PlayerContact flings the one a boosted runner runs into harder (and the runner feels no kick back), CourierMotion walks 1.45 times as fast.
## Frames (`--shots`, view 0 = the boosted runner): toast, glow, lines, fade.
const PlayerContact := preload("res://players/player_contact.gd")
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

func run(h) -> void:
	for slot in 3: h.hold(slot)
	await h.tick(20)
	var items = h.rules().items
	var boost: int = items.Catalog.index("boost")
	var soar: int = items.Catalog.index("soar")
	_stand(h, 5.0, 3.0, 1.0)
	await h.tick(10)
	h.check(items.racers_in_order() == [0, 1, 2], "slot 2 is last (%s)" % str(items.racers_in_order()))
	# ------------------------------------------------------------ 1. the clock (not in a render: too long for frames)
	h.rules().manager._next_at = 1.0e9 # the manager would hold the event gate: its own check is manager_check.gd
	if h.shots == "":
		var came: bool = await h.wait_until(func() -> bool: return not h.state().items.fx.is_empty(), 60 * 60)
		var at: float = items.time
		h.check(came and at >= 40.0 and at <= 55.5, "the clock hands the first event out 40-55 s into the race (%.1f s)" % at)
		var first: Array = h.state().items.fx[0] if came else [0, -1, -1]
		var kind_id: String = items.Catalog.id_of(int(first[2]))
		h.check(kind_id == "boost" or kind_id == "soar", "it is a BOOST or a SOAR (%s) on racer %d" % [kind_id, int(first[1])])
		h.check(items.racers().has(int(first[1])), "it goes to a racer")
		await h.tick(12)
		var victim := int(first[1])
		for view in 2:
			var items_view = h.views[view]._items
			if view == victim:
				h.check(str(items_view._banner.get("words", "")) != "", "the event's own screen shows a banner (%s)" % str(items_view._banner.get("words", "")))
			else:
				var told := false
				for line: Dictionary in items_view._lines: told = told or str(line.text).contains(items_view.name_of(victim))
				h.check(told, "replica %d reads a line that names racer %d (%s)" % [view, victim, str(items_view._lines.map(func(l: Dictionary) -> String: return l.text))])
		items.fx.clear() # the event is over for this check
		await h.tick(10)
		# the clock's bias: draw the choice many times with the field standing as it is (slot 2 last); the effect it hands out is cleared each time
		var counts := [0, 0, 0]
		var live: Array = items.racers()
		for draw in 240:
			items._next_event_at = 0.0
			h.rules().gate.reset()
			items._events_clock(live)
			for row: Dictionary in items.fx: counts[int(row.slot)] += 1
			items.fx.clear()
		items._next_event_at = 1.0e9
		h.check(counts[2] >= 130 and counts[0] <= 30, "the clock favours the back: slot 2 (last) got %d of 240, slot 1 %d, the leader %d" % [counts[2], counts[1], counts[0]])
	if h.shots != "": items._next_event_at = 1.0e9 # a render has no time for the clock
	# ------------------------------------------------------------ 2. a forced BOOST on slot 0
	items.fx.clear()
	await h.tick(10)
	_stand(h, 6.0, 4.0, 2.0)
	await h.tick(12)
	h.check(items.rules_of.has("boost"), "the round has the BOOST rule")
	for view in 2: # what the clock's events left on the screens
		h.views[view]._items._banner = {}
		h.views[view]._items._lines.clear()
	h.shoot("before")
	await h.tick(6)
	h.release(0)
	h.speed[0] = 0.13
	(items.rules_of["boost"] as RefCounted).happen(0)
	await h.tick(12)
	var rows := _fx_of(h, boost)
	h.check(rows.size() == 1 and int(rows[0][1]) == 0 and int(rows[0][7]) == -1, "BOOST is on slot 0 only, sent by nobody (%s)" % str(rows))
	var row: Array = rows[0]
	h.check(is_equal_approx(float(row[3]), items.tune("boost", "duration")) and is_equal_approx(float(row[5]), items.tune("boost", "speed")) and is_equal_approx(float(row[6]), items.tune("boost", "shove")),
		"the effect carries duration %.1f, speed %.2f, shove %.1f" % [float(row[3]), float(row[5]), float(row[6])])
	var mods: Dictionary = h.replicas[0].item_mods.get(0, {})
	h.check(is_equal_approx(float(mods.get("speed", 0.0)), 1.45), "the owner's machine walks 1.45 times as fast (item_mods %s)" % str(mods))
	h.check(is_equal_approx(float(h.replicas[0].item_power.get(0, 0.0)), 2.2), "and flings 2.2 times as hard (item_power %s)" % str(h.replicas[0].item_power))
	var live_power: Dictionary = h.replicas[0].item_power.duplicate() # what the shell hands its contact every tick (game/team_play.gd owner_contact)
	var banner: Dictionary = h.views[0]._items._banner
	h.check(str(banner.get("kind", "")) == "boon" and str(banner.get("words", "")) == items.Catalog.text("boost", "banner"), "the owner's screen has the boon banner (%s)" % str(banner.get("words", "")))
	var others_banner: Dictionary = h.views[1]._items._banner
	h.check(others_banner.is_empty(), "the other player's screen has no banner")
	var told := false
	for line: Dictionary in h.views[1]._items._lines: told = told or str(line.text).contains(h.views[1]._items.name_of(0).to_upper())
	h.check(told, "the other player reads a line naming slot 0")
	var rig: Node3D = h.replicas[0].rigs[0]
	var glow: Node = rig.get_node_or_null("BoostGlow")
	h.check(glow != null and glow.get_node_or_null("Light") != null and glow.get_node_or_null("Aura") != null and glow.get_node_or_null("Ring") != null and glow.get_node_or_null("Sparks") != null, "the runner glows on its owner's machine: light, aura, ring, sparks")
	h.check(h.replicas[1].rigs[0].get_node_or_null("BoostGlow") != null, "and on the other machine")
	var lines: Node = null
	for child in h.views[0]._items.over_layer.get_children(): if child is ColorRect: lines = child
	h.check(lines != null, "the owner's screen has the speed lines")
	h.check(h.views[1]._items.over_layer.get_children().filter(func(n: Node) -> bool: return n is ColorRect).is_empty(), "the other screen has none")
	h.check(h.views[0]._items.get_node_or_null("BoostCoins") != null, "the $ burst is in the air")
	h.speed[0] = 0.13 * 1.45 # the scripted runner runs as the owner's machine would
	await h.tick(14)
	h.shoot("toast")
	await h.tick(40)
	h.shoot("glow")
	await h.tick(60)
	var amount := 0.0
	if lines != null: amount = float((lines.material as ShaderMaterial).get_shader_parameter("amount"))
	h.check(amount > 0.6, "the speed lines are up in the middle of the boost (%.2f)" % amount)
	h.shoot("lines")
	h.check(h.views[0]._items.get_node_or_null("BoostCoins") == null, "the $ are gone after their flight")
	await h.tick(60)
	h.check(not h.replicas[0].follow.fx.is_empty() and float(h.replicas[0].follow.fx.get("fov", 0.0)) > 6.0, "the lens is open (+%.1f degrees)" % float(h.replicas[0].follow.fx.get("fov", 0.0)))
	var gone: bool = await h.wait_until(func() -> bool: return _fx_of(h, boost).is_empty(), 60 * 3)
	h.check(gone, "the five seconds run out")
	h.speed[0] = 0.13
	await h.tick(6)
	h.shoot("fade")
	await h.tick(30)
	h.check(not h.replicas[0].item_mods.has(0) and not h.replicas[0].item_power.has(0) and h.replicas[0].follow.fx.is_empty(), "the owner's machine is free again (mods %s, power %s)" % [str(h.replicas[0].item_mods), str(h.replicas[0].item_power)])
	h.check(rig.get_node_or_null("BoostGlow") == null and h.replicas[1].rigs[0].get_node_or_null("BoostGlow") == null, "the glow is gone from both machines")
	h.check(lines == null or not is_instance_valid(lines), "the speed lines are gone")
	# ------------------------------------------------------------ 3. the units (the headless check)
	if h.shots != "": return
	var shove := PlayerContact.new(2)
	shove.grabs = false
	var heads := [{"position": Vector3(0.0, 0.9, 0.0), "velocity": Vector3(6.0, 0.0, 0.0), "grab": false, "jump": false}, {"position": Vector3(0.6, 0.9, 0.0), "velocity": Vector3.ZERO, "grab": false, "jump": false}]
	var plain: Dictionary = shove.step(1.0 / 60.0, heads)
	var shove_plain: Vector3 = plain.results[1].impulse
	var recoil_plain: Vector3 = plain.results[0].impulse
	var strong := PlayerContact.new(2)
	strong.grabs = false
	strong.power = live_power # the replicated power of slot 0, as the owner's machine hands it to its contact
	var boosted: Dictionary = strong.step(1.0 / 60.0, heads)
	var shove_boosted: Vector3 = boosted.results[1].impulse
	var recoil_boosted: Vector3 = boosted.results[0].impulse
	h.check(shove_plain.x > 3.0 and shove_boosted.x > shove_plain.x * 2.1, "a boosted runner flings the one it hits %.1f m/s against %.1f m/s" % [shove_boosted.x, shove_plain.x])
	h.check(recoil_plain.x < -0.5 and is_zero_approx(recoil_boosted.x), "and feels no kick back (%.2f against %.2f)" % [recoil_boosted.x, recoil_plain.x])
	var plain_speed := await _walk(h, {})
	var boosted_speed := await _walk(h, {"speed": 1.45})
	h.check(boosted_speed > plain_speed * 1.4 and boosted_speed < plain_speed * 1.5, "a courier with the mod walks %.2f m/s against %.2f m/s" % [boosted_speed, plain_speed])

## A courier on a private floor far from the round walks one second with `mods`; the planar speed it reaches (m/s).
func _walk(h, mods: Dictionary) -> float:
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
	for tick in 90:
		motion.step(body, {"move": Vector2(0.0, -1.0), "jump": false, "dash": false}, 1.0 / 60.0)
		await h.root.get_tree().physics_frame
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	body.queue_free()
	floor_body.queue_free()
	return speed
