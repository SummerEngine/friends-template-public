extends Node
## --lab-levelscheck: the stops are named in order, travelling to each lands the courier on a floor at its pad with the clock at zero
## and only that level in the tree, the goal of stop 1 gives the cleared card and then stop 2, a fall returns to the pad and G returns
## to where the courier last stood, the number keys travel. Prints GW_LEVELSCHECK lines and quits 0 (all ok) or 1.
var lab
var failures := 0

func run(owner_lab) -> void:
	lab = owner_lab
	_run.call_deferred()

func _expect(ok: bool, what: String) -> void:
	if not ok: failures += 1
	print("GW_LEVELSCHECK ", "ok   " if ok else "FAIL ", what)

func _ticks(count: int) -> void:
	for index in count: await lab.get_tree().physics_frame

func _run() -> void:
	await _ticks(2)
	var count: int = lab.stops.size()
	_expect(count >= 1 and count == lab.level_world.level_count(), "%d stops for %d levels" % [count, lab.level_world.level_count()])
	var named := true
	for index in count:
		var title: String = lab.level_world.title(index)
		named = named and lab.stops[index].name == "%d %s" % [index + 1, title] and int(lab.stops[index].level) == index
	_expect(named, "stops are named '<N> <TITLE>' in level order")
	_expect(lab.stop == 0 and lab.epoch >= 1, "the lab opens on stop 1")
	for index in count:
		lab.travel(index)
		await _ticks(40)
		var entry: Dictionary = lab.stops[index]
		var pad: Vector3 = entry.pad
		var at: Vector3 = lab.body.global_position
		var floor_y: float = lab.level_world.floor_y(index, pad)
		var gap := absf(at.y - floor_y) if not is_nan(floor_y) else INF
		var flat := Vector2(at.x - pad.x, at.z - pad.z).length()
		var only: bool = lab.level_world.active_level == index
		var in_goal: String = lab.level_world.zone_at(index, at)
		_expect(lab.stop == index and only and lab.grounded_now() and gap < 0.6 and flat < 0.75 and in_goal == "" and lab.elapsed == 0.0 and not lab.cleared,
			"stop %d (%s): grounded on a floor at its pad (gap %.2f, off %.2f), clock %.2f, level %d drawn" % [index + 1, entry.name, gap, flat, lab.level_world.clock, lab.level_world.active_level + 1])
	# the goal of stop 1: card, then stop 2
	lab.travel(0)
	await _ticks(10)
	var epoch_before: int = lab.epoch
	var goal: Dictionary = lab.level_world.goal_volume(0)
	lab.motion.teleport(lab.body, (goal.p as Vector3) - Vector3(0.0, 0.8, 0.0))
	await _ticks(3)
	_expect(lab.cleared and lab.stop == 0, "the goal of stop 1 clears the level")
	await lab.get_tree().process_frame
	var probe: Dictionary = lab.level_hud.probe()
	var title_1: String = lab.level_world.title(0)
	var expected_next: String = lab.level_world.title(1 % count)
	_expect(str(probe.get("card_line", "")).begins_with(title_1) and str(probe.get("card_next", "")) == "Next: " + expected_next and bool(probe.get("clearing", false)),
		"cleared card names '%s' and 'Next: %s' (probe %s)" % [title_1, expected_next, probe])
	await _ticks(int(2.6 * 60.0) + 20)
	var pad_next: Vector3 = lab.stops[1 % count].pad
	_expect(not lab.cleared and lab.stop == 1 % count and lab.epoch > epoch_before and Vector2(lab.body.global_position.x - pad_next.x, lab.body.global_position.z - pad_next.z).length() < 0.75,
		"after the card stop %d starts at its pad (epoch %d)" % [1 % count + 1, lab.epoch])
	# wrap after the last stop
	lab.travel(count - 1)
	await _ticks(10)
	lab.motion.teleport(lab.body, (lab.level_world.goal_volume(count - 1).p as Vector3) - Vector3(0.0, 0.8, 0.0))
	await _ticks(int(2.6 * 60.0) + 20)
	_expect(lab.stop == 0 and not lab.cleared, "after the last stop the first starts again")
	# a fall: back on the pad
	lab.travel(0)
	await _ticks(10)
	var void_y: float = lab.level_world.floor_y(0, lab.stops[0].pad) - 60.0
	lab.motion.teleport(lab.body, Vector3(lab.body.global_position.x, void_y, lab.body.global_position.z))
	await _ticks(60)
	var back: Vector3 = lab.body.global_position
	_expect(lab.deaths >= 1 and Vector2(back.x - lab.stops[0].pad.x, back.z - lab.stops[0].pad.z).length() < 0.75 and back.y > void_y + 30.0, "a fall into the void puts the courier back on the pad")
	# the number keys: a typed number travels, a typed zero does nothing
	lab.travel(0)
	await _ticks(5)
	lab._digit_key(int(min(2, count)))
	lab._commit_digits()
	await _ticks(5)
	_expect(lab.stop == int(min(2, count)) - 1, "typing 2 and Enter goes to stop 2")
	lab.travel_step(-1)
	await _ticks(5)
	_expect(lab.stop == posmod(int(min(2, count)) - 2, count), "the previous-stop key steps back, wrapping")
	# G: where the courier last stood
	lab.travel(0)
	await _ticks(60)
	lab._set_god(true)
	var stood: Vector3 = lab.last_firm
	lab.motion.teleport(lab.body, Vector3(stood.x, void_y, stood.z))
	await _ticks(60)
	_expect(lab.god and lab.body.global_position.distance_to(stood) < 0.9, "with G a fall puts the courier back where it last stood")
	lab._set_god(false)
	print("GW_LEVELSCHECK done failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
