extends RefCounted
## EXPERIMENT TANDEM in a race, end to end (docs/party-show.md "Tandem (experiment)"): the authority (match controller, shell, the show's rules with three scripted racers) and two replicas that draw the
## show's view and the TANDEM's look. Slots 0 and 1 run side by side along the route, slot 2 stands behind them.
## 1. Alongside for 1.5 s: the authority fuses them (`match.tandem.pairs`, one FUSE event); both owners' machines get the pair (`tandem`: 1.6 x speed, 2.2 x shove, the partner's steering and feet,
##    `rig_hold`: the arms reach), the contact is told who holds hands, each screen shows the TANDEM! banner naming the partner, the third racer is untouched.
## 2. The steering of a fused courier is the average of its own and its partner's (`item_move`); both must agree to turn.
## 3. Units without the network: the shove (the pair flings a third player, never each other), the motion walks 1.6 times as fast.
## 4. Six seconds later: END, both are flung (the authority's kicks), the machines are free, the rigs spin, the pair's cooldown runs.
## Frames (`--shots`, view 0 = slot 0): approach, pop, holding hands, spin.
const PlayerContact := preload("res://players/player_contact.gd")
const CourierMotion := preload("res://courier/courier_motion.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")

func _tandem_state(h) -> Dictionary:
	var info: Dictionary = h.latest_state().get("match", {})
	return info.get("tandem", {}) if info.get("tandem", {}) is Dictionary else {}

func run(h) -> void:
	for slot in 3: h.hold(slot)
	h.rules().items._next_event_at = 1.0e9 # the clock's events (a BOOST) would change the speeds
	await h.tick(10)
	h.progress(0, 30.0)
	h.progress(1, 30.0)
	h.progress(2, 24.0)
	await h.tick(30)
	var tandem = h.controller.tandem
	h.check(tandem != null and tandem.active and tandem.scope == "race", "the authority runs the tandem in the race's play phase (scope %s)" % str(tandem.scope if tandem != null else "none"))
	h.check(_tandem_state(h).get("pairs", [1]).is_empty() and h.replicas[0].tandem.is_empty(), "standing still: no pair")
	h.shoot("approach")
	h.speed[0] = 0.13
	h.speed[1] = 0.13
	h.release(0)
	h.release(1)
	var began: float = tandem.time
	var fused: bool = await h.wait_until(func() -> bool: return not tandem.pairs.is_empty(), 60 * 6)
	var after: float = tandem.time - began
	h.check(fused and after >= 1.4 and after <= 2.6, "running alongside for 1.5 s fuses them (%.2f s after the start)" % after)
	var pair: Dictionary = tandem.pairs[0] if fused else {}
	h.check(int(pair.get("a", -9)) == 0 and int(pair.get("b", -9)) == 1 and float(pair.get("dur", 0.0)) == 6.0, "the pair is slots 0 and 1 for 6 s")
	await h.tick(14)
	h.shoot("pop")
	var state := _tandem_state(h)
	var rows: Array = state.get("pairs", [])
	h.check(rows.size() == 1 and int(rows[0][1]) == 0 and int(rows[0][2]) == 1, "match.tandem lists the pair (%s)" % str(rows))
	var events: Array = (state.get("ev", []) as Array).filter(func(row: Array) -> bool: return int(row[1]) == Tandem.Event.FUSE)
	h.check(events.size() == 1 and int(events[0][2]) == 0 and int(events[0][3]) == 1, "one FUSE event naming 0 and 1")
	for index in 2:
		var shell: Node = h.replicas[index]
		var mine: Dictionary = shell.tandem.get(index, {})
		var other: Dictionary = shell.tandem.get(1 - index, {})
		h.check(int(mine.get("with", -9)) == 1 - index and is_equal_approx(float(mine.get("speed", 0.0)), 1.6) and is_equal_approx(float(mine.get("power", 0.0)), 2.2), "replica %d: its courier is fused with %d at 1.6 x speed, 2.2 x shove (%s)" % [index, 1 - index, str(mine)])
		h.check(int(other.get("with", -9)) == index, "replica %d knows the other half too" % index)
		h.check(not shell.tandem.has(2) and not shell.rig_hold.has(2), "replica %d: the third racer is untouched" % index)
		h.check(shell.rig_hold.has(0) and shell.rig_hold.has(1), "replica %d: both characters reach for the joined hands (rig_hold)" % index)
		h.check(is_equal_approx(float(shell.courier_mods(index).get("speed", 0.0)), 1.6), "replica %d: the owner's motion mods carry the speed (%s)" % [index, str(shell.courier_mods(index))])
		var hands: Vector3 = shell.rig_hold.get(0, Vector3.ZERO)
		var between: Vector3 = (shell.actors[0].global_position + shell.actors[1].global_position) * 0.5
		h.check(absf(hands.y - between.y - 0.95) < 0.3, "replica %d: the hands meet about a metre over the feet" % index)
	var contact = h.replicas[0].team.contact
	h.replicas[0].team.owner_contact(0, 1.0 / 60.0) # what the owner's machine does each tick before it steps its courier: the contact is handed the pair's shove and who holds whom
	h.check(float(contact.power.get(0, 0.0)) >= 2.2 and int(contact.partners.get(0, -9)) == 1, "the contact knows the pair's shove and who holds whom (power %s, partners %s)" % [str(contact.power), str(contact.partners)])
	h.check(h.tandems[0].banners_shown == 1 and str(h.tandems[0]._banner.get("words", "")) == "TANDEM!" and str(h.tandems[0]._banner.get("line", "")).contains(h.tandems[0].name_of(1)), "slot 0's screen: TANDEM! with %s" % str(h.tandems[0]._banner.get("line", "")))
	h.check(h.tandems[1].banners_shown == 1 and str(h.tandems[1]._banner.get("line", "")).contains(h.tandems[1].name_of(0)), "slot 1's screen: TANDEM! with %s" % str(h.tandems[1]._banner.get("line", "")))
	h.check(h.tandems[0].pops == 1 and h.tandems[0]._fx.count() > 10, "the heart and spark pop is in the air (%d pieces)" % h.tandems[0]._fx.count())
	# ------------------------------------------------------------ 2. the steering
	var shell0: Node = h.replicas[0]
	var partner_move := Vector2(0.0, -1.0)
	(shell0.tandem[0] as Dictionary).move = partner_move
	(shell0.tandem[0] as Dictionary).at = shell0.actors[0].global_position # no pull
	var steered: Vector2 = shell0.item_move(0, Vector2(1.0, 0.0))
	h.check(steered.is_equal_approx(Vector2(0.5, -0.5)), "steering is the average of both inputs: right + forward = %s" % str(steered))
	(shell0.tandem[0] as Dictionary).move = Vector2(-1.0, 0.0)
	h.check(shell0.item_move(0, Vector2(1.0, 0.0)).length() < 0.01, "opposite inputs cancel: the pair stands still")
	(shell0.tandem[0] as Dictionary).move = Vector2.ZERO
	h.check(shell0.item_move(0, Vector2(1.0, 0.0)).is_equal_approx(Vector2(0.5, 0.0)), "a partner who does not steer halves the steering")
	(shell0.tandem[0] as Dictionary).at = shell0.actors[0].global_position + Vector3(3.0, 0.0, 0.0)
	h.check(shell0.item_move(0, Vector2.ZERO).x > 0.3, "a partner left behind pulls the other towards it")
	h.check(shell0.item_move(2, Vector2(1.0, 0.0)) == Vector2(1.0, 0.0), "an unfused courier steers by itself")
	await h.tick(6)
	h.shoot("hold")
	# ------------------------------------------------------------ the pair wins the race to the end of its time
	var floor_kicks: Vector3 = h.sim.team.kicks[0]
	var spun := false
	var ended: bool = await h.wait_until(func() -> bool:
		spun = spun or shell0.rig_spin.has(0)
		return tandem.pairs.is_empty(), 60 * 8)
	h.check(ended, "the tandem ends by itself (age %.2f s)" % float(tandem.time - began))
	var end_events: Array = (tandem.events as Array).filter(func(row: Array) -> bool: return int(row[1]) == Tandem.Event.END)
	h.check(end_events.size() == 1, "one END event (they spin apart)")
	var kick_a: Vector3 = h.sim.team.kicks[0] - floor_kicks
	var kick_b: Vector3 = h.sim.team.kicks[1]
	h.check(Vector2(kick_a.x, kick_a.z).length() > 4.5 and kick_a.y > 2.0, "the authority threw slot 0 (kick %s)" % str(kick_a))
	h.check(kick_a.x * h.sim.team.kicks[1].x + kick_a.z * h.sim.team.kicks[1].z < 0.0 or kick_b.length() > 4.5, "and slot 1 the other way (kick %s)" % str(kick_b))
	await h.tick(9)
	h.shoot("spin")
	await h.tick(9)
	h.check(spun or shell0.rig_spin.has(0) or h.tandems[0]._spins.has(0), "the rigs spin apart")
	await h.tick(60)
	h.check(h.replicas[0].tandem.is_empty() and h.replicas[1].tandem.is_empty() and h.replicas[0].rig_hold.is_empty() and h.replicas[0].rig_spin.is_empty(), "the owners' machines are free again")
	var key: int = Tandem.key_of(0, 1)
	h.check(tandem.cooling.has(key) and float(tandem.cooling[key]) > 7.0, "the pair is cooling for 10 s (%.1f s left)" % float(tandem.cooling.get(key, 0.0)))
	await h.tick(60 * 3)
	h.check(tandem.pairs.is_empty(), "still running side by side, they do not fuse again in the cooldown")
	# ------------------------------------------------------------ 3. units
	if h.shots != "": return
	var heads := [{"position": Vector3(0.0, 0.9, -0.5), "velocity": Vector3(8.0, 0.0, 0.0), "grab": false, "jump": false}, {"position": Vector3(0.0, 0.9, 0.5), "velocity": Vector3(8.0, 0.0, 0.0), "grab": false, "jump": false},
		{"position": Vector3(0.55, 0.9, -0.5), "velocity": Vector3.ZERO, "grab": false, "jump": false}]
	var plain := PlayerContact.new(3)
	plain.grabs = false
	var plain_step: Dictionary = plain.step(1.0 / 60.0, heads)
	var strong := PlayerContact.new(3)
	strong.grabs = false
	strong.power = {0: 2.2, 1: 2.2}
	strong.partners = {0: 1, 1: 0}
	var strong_step: Dictionary = strong.step(1.0 / 60.0, heads)
	var thrown_plain: float = (plain_step.results[2].impulse as Vector3).length()
	var thrown: float = (strong_step.results[2].impulse as Vector3).length()
	h.check(thrown > thrown_plain * 2.0, "a pair that runs into a third player flings it %.1f m/s against %.1f m/s" % [thrown, thrown_plain])
	var close := [{"position": Vector3(0.0, 0.9, 0.0), "velocity": Vector3(4.0, 0.0, 0.0), "grab": false, "jump": false}, {"position": Vector3(0.5, 0.9, 0.0), "velocity": Vector3.ZERO, "grab": false, "jump": false}]
	var holders := PlayerContact.new(2)
	holders.grabs = false
	holders.power = {0: 2.2, 1: 2.2}
	holders.partners = {0: 1, 1: 0}
	var between_step: Dictionary = holders.step(1.0 / 60.0, close)
	h.check((between_step.results[1].impulse as Vector3).length() < 0.001 and (between_step.results[0].impulse as Vector3).length() < 0.001, "two fused partners never shove each other")
	var slow := await _walk(h, {})
	var quick := await _walk(h, {"speed": 1.6})
	h.check(quick > slow * 1.55 and quick < slow * 1.65, "a courier with the pair's mod walks %.2f m/s against %.2f m/s" % [quick, slow])

## A courier on a private floor far from the round walks 1.5 s with `mods`; the planar speed it reaches (m/s).
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
