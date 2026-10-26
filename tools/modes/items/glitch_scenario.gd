extends RefCounted
## GLITCH end to end. Slot 2 holds it with slots 0 and 1 ahead of it and presses ITEM: the authority puts the effect on 0 and 1 (not on the user), the clients draw their rigs once per period
## (rig_lag, on every replica), the victim's own screen gets the wobble layer (a shader that ramps), the camera sway and the PING pill, the rig really holds between jerks while the courier runs
## smoothly, and everything is gone when the seconds are up. Then a second use with slot 1 BEHIND the user (only slot 0 is hit: replica 1 draws no wobble), an early end, and a use with nobody ahead
## (it keeps its item).
## Frames (`--shots`, view 0 = the victim): before, use, peak_1 / peak / peak_3, stutter_a / stutter_b (0.25 s apart), end; with `--view=1` the user's screen is played instead (slot 1 holds it): pickup, use, seen.
const PERIOD := 0.5

func _fx_slots(h, id: int) -> Array:
	var slots: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == id: slots.append(int(row[1]))
	slots.sort()
	return slots

func _wobble(h, view: int) -> Node:
	return h.views[view]._items.post_layer.get_node_or_null("GlitchWobble")

func _ping(h, view: int) -> Node:
	return h.views[view]._items.over_layer.get_node_or_null("GlitchPing")

func _stand(h, ahead: float, middle: float, behind: float) -> void:
	h.progress(0, ahead)
	h.progress(1, middle)
	h.progress(2, behind)

func run(h) -> void:
	for slot in 3: h.hold(slot)
	await h.tick(20)
	await h.wait_until(func() -> bool: return float(h.state().get("t", 0.0)) > 1.4, 60 * 4) # the show's GO banner has cleared (item banners wait for it: one big banner at a time)
	var items = h.rules().items
	var glitch: int = items.Catalog.index("glitch")
	if h.shots != "" and h.shot_view == 1:
		await _user_screen(h, items, glitch)
		return
	_stand(h, 22.0, 14.0, 6.0)
	await h.tick(10)
	h.check(items.ahead_of(2) == [1, 0], "slots 1 and 0 are ahead of slot 2 (%s)" % str(items.ahead_of(2)))
	h.check(h.give(2, "glitch"), "slot 2 holds GLITCH")
	h.shoot("before")
	await h.tick(8)
	h.press_item(2)
	await h.tick(8)
	h.check(_fx_slots(h, glitch) == [0, 1], "GLITCH is on slots 0 and 1, not on the user (%s)" % str(_fx_slots(h, glitch)))
	h.check(int(h.state().items.held[2]) == -1, "the item is used up")
	var row: Array = []
	for candidate: Array in h.state().items.fx:
		if int(candidate[2]) == glitch: row = candidate
	h.check(is_equal_approx(float(row[3]), items.tune("glitch", "duration")) and is_equal_approx(float(row[5]), PERIOD) and is_equal_approx(float(row[6]), 1.0), "the effect carries duration %.1f, period %.2f and sway %.1f" % [float(row[3]), float(row[5]), float(row[6])])
	h.shoot("use")
	# what the clients do with it
	for view in 2:
		var lagged: Dictionary = h.replicas[view].rig_lag
		h.check(is_equal_approx(float(lagged.get(0, 0.0)), PERIOD) and is_equal_approx(float(lagged.get(1, 0.0)), PERIOD) and not lagged.has(2), "replica %d draws the rigs of slots 0 and 1 once per %.1f s, not the user's (%s)" % [view, PERIOD, str(lagged)])
		h.check(_wobble(h, view) != null and h.views[view]._items.post_layer.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("GlitchWobble")).size() == 1, "replica %d has one wobble layer (its own screen's)" % view)
		h.check(_wobble(h, view).get_parent() == h.views[view]._items.post_layer and _ping(h, view) != null, "replica %d: the wobble is in the post layer (under the HUD), the PING pill over the game" % view)
	h.check(str(h.views[0]._items._banner.get("kind", "")) == "alert" and str(h.views[0]._items._banner.get("words", "")) == items.Catalog.text("glitch", "banner"), "the victim's screen shows the alert banner (%s)" % str(h.views[0]._items._banner.get("words", "")))
	h.check(_wobble(h, 0).get("material") is ShaderMaterial and (_wobble(h, 0).material as ShaderMaterial).shader.resource_path.ends_with("glitch_wobble.gdshader"), "the wobble is the glitch_wobble shader")
	# the run: slots move again; sample the shader, the camera and the rigs over the whole effect
	for slot in 3: h.release(slot)
	var amounts: Array = []
	var rolls: Array = []
	var fovs: Array = []
	var rig_moves: Array = [] ## ticks (since the use) in which replica 0's rig of slot 0 moved
	var actor_moved := 0
	var sampled := 0
	var last_rig: Vector3 = h.replicas[0].rigs[0].global_position
	var last_actor: Vector3 = h.sim.actors[0].global_position
	var tick_no := 8
	var shots_at := {}
	var stutter_b_at := -1
	var gone := false
	while tick_no < 60 * 9:
		await h.tick()
		tick_no += 1
		var wobble: Node = _wobble(h, 0)
		if wobble != null:
			amounts.append(float((wobble.material as ShaderMaterial).get_shader_parameter("amount")))
		elif not amounts.is_empty() and not gone:
			gone = true
		var camera: Dictionary = h.replicas[0].follow.fx
		rolls.append(float(camera.get("roll", 0.0)))
		fovs.append(float(camera.get("fov", 0.0)))
		var rig: Vector3 = h.replicas[0].rigs[0].global_position
		var actor: Vector3 = h.sim.actors[0].global_position
		if tick_no > 60 and tick_no < 60 * 5:
			sampled += 1
			if rig.distance_to(last_rig) > 0.002: rig_moves.append(tick_no)
			if actor.distance_to(last_actor) > 0.01: actor_moved += 1
		var jerked := rig.distance_to(last_rig) > 0.05
		last_rig = rig
		last_actor = actor
		for at: Array in [[75, "peak_1"], [175, "peak"], [285, "peak_3"]]: # a strip of the trip: 1.25 s in (just risen), the swell's top (2.9 s), 4.75 s (the hue has drifted on)
			if tick_no >= int(at[0]) and not shots_at.has(at[1]):
				shots_at[at[1]] = true
				h.shoot(str(at[1]))
		if tick_no >= 200 and jerked and not shots_at.has("a"): # a jerk: the rig now holds for half a second
			shots_at["a"] = tick_no
			stutter_b_at = tick_no + 16
			h.shoot("stutter_a")
		if stutter_b_at > 0 and tick_no == stutter_b_at: h.shoot("stutter_b")
		if h.state().items.fx.is_empty(): break
	await h.tick(30)
	h.shoot("end")
	await h.tick(8)
	# the sampled numbers
	var peak := 0.0
	for value: float in amounts: peak = maxf(peak, value)
	var jump := 0.0
	for index in range(1, amounts.size()): jump = maxf(jump, absf(float(amounts[index]) - float(amounts[index - 1])))
	h.check(float(amounts[0]) < 0.5 and peak > 0.99 and peak < 1.01, "the wobble ramps in from %.2f to a peak of %.2f (sway 1)" % [float(amounts[0]), peak])
	h.check(jump < 0.25, "the wobble never jumps (largest step %.3f between two updates of the view, 3 ticks apart in this harness)" % jump)
	h.check(float(amounts[-1]) < 0.12, "the wobble has eased out when the effect ends (%.3f)" % float(amounts[-1]))
	var roll_max := 0.0
	var fov_max := 0.0
	for value: float in rolls: roll_max = maxf(roll_max, absf(value))
	for value: float in fovs: fov_max = maxf(fov_max, absf(value))
	h.check(roll_max > deg_to_rad(9.0) and roll_max <= deg_to_rad(10.001) and fov_max > 8.0 and fov_max <= 9.001, "the victim's camera sways: roll up to %.2f deg, lens up to %.2f deg" % [rad_to_deg(roll_max), fov_max])
	var intervals: Array = []
	for index in range(1, rig_moves.size()): intervals.append(int(rig_moves[index]) - int(rig_moves[index - 1]))
	var steady := not intervals.is_empty() and intervals.all(func(step: int) -> bool: return step >= 28 and step <= 32)
	h.check(steady and rig_moves.size() >= 6 and rig_moves.size() <= 9, "the rig on screen moves in jerks %.1f s apart (%d in %d ticks, steps %s)" % [PERIOD, rig_moves.size(), sampled, str(intervals)])
	h.check(float(actor_moved) / float(sampled) > 0.95, "while the courier itself moves smoothly (%d of %d ticks)" % [actor_moved, sampled])
	# the end
	h.check(h.state().items.fx.is_empty(), "the effect ran out")
	for view in 2:
		h.check(h.replicas[view].rig_lag.is_empty() and h.replicas[view].item_mods.is_empty(), "replica %d: nobody is drawn in jerks and nobody is held any more" % view)
		h.check(_wobble(h, view) == null and _ping(h, view) == null, "replica %d: the wobble layer and the PING pill are gone" % view)
	h.check(h.replicas[0].follow.fx.is_empty() and h.replicas[1].follow.fx.is_empty(), "the cameras are free")
	await h.tick(6) # a few frames for the rig to catch up with a courier that is still falling or settling
	h.check(h.replicas[0].rigs[0].global_position.distance_to(h.replicas[0].actors[0].global_position) < 0.8, "the rig is back on its courier (%.2f m, rig %s actor %s)" % [h.replicas[0].rigs[0].global_position.distance_to(h.replicas[0].actors[0].global_position), str(h.replicas[0].rigs[0].global_position), str(h.replicas[0].actors[0].global_position)])
	for slot in 3: h.hold(slot)
	# a second use: slot 1 stands behind the user, so only slot 0 is hit and replica 1 has no wobble
	_stand(h, 60.0, 4.0, 30.0)
	await h.tick(10)
	h.check(items.ahead_of(2) == [0], "only slot 0 is ahead of slot 2 now (%s)" % str(items.ahead_of(2)))
	h.give(2, "glitch")
	await h.tick(4)
	h.press_item(2)
	await h.tick(8)
	h.check(_fx_slots(h, glitch) == [0], "GLITCH is on slot 0 only (%s)" % str(_fx_slots(h, glitch)))
	h.check(_wobble(h, 0) != null and _wobble(h, 1) == null and _ping(h, 1) == null, "the wobble is on the victim's screen only (replica 0 yes, replica 1 no)")
	h.check(is_equal_approx(float(h.replicas[1].rig_lag.get(0, 0.0)), PERIOD) and not h.replicas[1].rig_lag.has(1), "replica 1 still sees slot 0 stutter, and slot 1 is drawn smoothly")
	# taken off early
	items.end_fx(items.fx_of(0, "glitch"), true)
	await h.tick(8)
	h.check(h.replicas[0].rig_lag.is_empty() and _wobble(h, 0) == null and _ping(h, 0) == null and h.replicas[0].follow.fx.is_empty(), "an effect taken off early frees the screen at once")
	# nobody ahead: the leader keeps its item
	_stand(h, 70.0, 20.0, 8.0)
	await h.tick(10)
	h.check(items.ahead_of(0).is_empty(), "slot 0 leads")
	h.give(0, "glitch")
	await h.tick(4)
	h.press_item(0)
	await h.tick(8)
	var pack: Array = _fx_slots(h, glitch)
	pack.sort()
	h.check(int(h.state().items.held[0]) == -1 and pack == [1, 2], "with nobody ahead the leader's GLITCH hits the pack behind (%s)" % str(pack))
	for entry: Dictionary in items.fx.duplicate(): items.end_fx(entry)
	items.held[0] = -1
	await h.tick(4)

## The user's screen (--view=1): slot 1 holds GLITCH, slot 0 runs ahead of it.
func _user_screen(h, items, glitch: int) -> void:
	_stand(h, 40.0, 26.0, 6.0)
	await h.tick(10)
	h.release(0)
	h.release(1)
	h.check(h.give(1, "glitch"), "slot 1 holds GLITCH")
	await h.tick(8)
	h.shoot("pickup")
	await h.tick(30)
	h.press_item(1)
	await h.tick(14)
	h.check(_fx_slots(h, glitch) == [0], "slot 0 (ahead of the user) is hit (%s)" % str(_fx_slots(h, glitch)))
	h.shoot("use")
	await h.tick(60)
	h.shoot("seen")
	await h.tick(8)
	h.check(_wobble(h, 1) == null and _ping(h, 1) == null, "the user's own screen does not wobble")
