extends SceneTree
## Dev check of the poster doors (levels/poster_doors.gd, levels/level_world.gd door_push / observe_doors, docs/level-format.md "Poster doors") on the
## real POSTER RUSH levels (level_17.json, level_20.json), with real courier physics: a courier walking (or dashing) into a SOLID door (a problem poster, a wall)
## is stopped by its hidden block and given the small push-back (one `bonk` launch of kind "door" per touch, nowhere near a hazard's throw), a courier through an
## OPEN door (the logo poster) or the already TORN one is stopped by nothing and gets no push, and `observe_doors` (fed only the positions, the way a client sees
## another player) reports one burst per open door gone through and one bump per touch of a solid one. The rows whose logo poster SLIDES (a door with `ride`) are
## tested on the level clock too (check_moving): torn when the opening is there on arrival, a thud when it is not, never trapped by the sweeping edge. Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/poster_door_check.gd
## Prints POSTER_DOOR_CHECK lines and `POSTER_DOOR_CHECK ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const PosterDoors := preload("res://levels/poster_doors.gd")
const DT := 1.0 / 60.0
const PUSH_MAX_SPEED := 6.0 ## m/s: the push-back is small (a hazard's bonk is 8.5 to 15, horizontally)

var world: Node3D
var holder: Node3D
var fails := 0
var bursts := 0
var bumps := 0

func _initialize() -> void:
	run.call_deferred()

func say(text: String, ok := true) -> void:
	if not ok: fails += 1
	print("POSTER_DOOR_CHECK ", "ok   " if ok else "FAIL ", text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	world.door_burst.connect(func(_index: int, _at: Vector3, _heading: Vector3) -> void: bursts += 1)
	world.door_bonk.connect(func(_index: int, _at: Vector3, _who: int) -> void: bumps += 1)
	for number in [17, 20]: await check_level(number)
	say("ok=%s" % (fails == 0), fails == 0)
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

## One tick of a simulation: the level's effects on the courier, its step, and what a client would see of it (its position).
func tick(level: int, body: CharacterBody3D, motion: RefCounted, input: Dictionary) -> Dictionary:
	world.advance(DT)
	var effect: Dictionary = world.apply_effects(level, 0, body, motion)
	motion.step(body, input, DT)
	await physics_frame
	world.observe_doors(level, 0, body.global_position)
	return effect

## A courier at level-local `spot` facing the next row; `move` held for `seconds`. Returns {pushes, pushed (the biggest horizontal speed a push gave),
## min_z (the furthest it got along -z, level-local), bursts, bumps}.
func walk(level: int, spot: Vector3, seconds: float, dash_at := -1.0, clock := 10.0, wait := 0.0) -> Dictionary:
	world.set_clock(clock) # the start gate is long open (10 s by default)
	world.reset_effects()
	await physics_frame
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	var origin: Vector3 = world.level_origin(level)
	motion.reset(body, origin + spot, 0.0)
	await physics_frame
	bursts = 0
	bumps = 0
	var result := {"pushes": 0, "pushed": 0.0, "min_z": spot.z, "bursts": 0, "bumps": 0, "doors": 0}
	var time := 0.0
	while time < seconds:
		var effect: Dictionary = await tick(level, body, motion, {"move": Vector2(0.0, -1.0) if time >= wait else Vector2.ZERO, "dash": dash_at >= 0.0 and time >= dash_at and time < dash_at + 0.05})
		time += DT
		if str(effect.get("hazard", "")) == "door":
			result.pushes += 1
			result.pushed = maxf(float(result.pushed), Vector2(effect.v.x, effect.v.z).length())
		elif not effect.is_empty(): result.other = effect.get("kind", "")
		result.min_z = minf(float(result.min_z), body.global_position.z - origin.z)
	result.bursts = bursts
	result.bumps = bumps
	result.y = body.global_position.y - origin.y
	result.x = body.global_position.x - origin.x
	result.z = body.global_position.z - origin.z
	body.queue_free()
	await physics_frame
	return result

func check_level(number: int) -> void:
	var level := number - 1
	world.set_active_level(level)
	await physics_frame
	var doors: Array = PosterDoors.list(world.get("_levels")[level].data)
	var kinds := {}
	for door: Dictionary in doors: kinds[door.kind] = int(kinds.get(door.kind, 0)) + 1
	say("level %d: %d doors %s" % [number, doors.size(), kinds], kinds.get("torn", 0) == 1 and kinds.get("open", 0) >= 3 and kinds.get("solid", 0) >= 25)
	var first := _row(doors, 0) # the first row: one torn logo poster among problem posters; the second row: an open logo poster that stands still
	var rows := {"solid": first, "torn": first, "open": _row(doors, 1)}
	for kind: String in ["solid", "open", "torn"]:
		var row: Array = rows[kind]
		var plane: float = row[0].p.z
		var door: Dictionary = row.filter(func(entry: Dictionary) -> bool: return entry.kind == kind)[0]
		var spot := Vector3(float(door.p.x), 0.0, plane + 3.0)
		var walked := await walk(level, spot, 3.0)
		if kind == "solid":
			say("level %d solid door at x=%.2f: stopped at z=%.2f (plane %.2f), %d pushes of at most %.1f m/s, observer saw %d bumps, %d bursts" % [number, door.p.x, walked.min_z, plane,
				walked.pushes, walked.pushed, walked.bumps, walked.bursts],
				float(walked.min_z) > plane - 0.1 and int(walked.pushes) >= 2 and float(walked.pushed) <= PUSH_MAX_SPEED and int(walked.bumps) >= 2 and int(walked.bursts) == 0 and not walked.has("other"))
			var dashed := await walk(level, spot, 2.0, 0.3)
			say("level %d solid door, dashed at: stopped at z=%.2f, %d pushes" % [number, dashed.min_z, dashed.pushes], float(dashed.min_z) > plane - 0.1 and int(dashed.pushes) >= 1)
		else:
			say("level %d %s door at x=%.2f: through to z=%.2f, %d pushes, observer saw %d bursts and %d bumps" % [number, kind, door.p.x, walked.min_z, walked.pushes, walked.bursts, walked.bumps],
				float(walked.min_z) < plane - 1.5 and int(walked.pushes) == 0 and int(walked.bumps) == 0 and int(walked.bursts) == (1 if kind == "open" else 0))
	# a client's view of a courier it does not simulate: positions only, a jump (a respawn) is not a run
	world.reset_effects()
	bursts = 0
	bumps = 0
	var second: Array = rows["open"]
	var plane: float = second[0].p.z
	var open: Dictionary = second.filter(func(entry: Dictionary) -> bool: return entry.kind == "open")[0]
	var origin: Vector3 = world.level_origin(level)
	for step in 40: world.observe_doors(level, 3, origin + Vector3(float(open.p.x), 0.0, plane + 2.0 - step * 0.1))
	say("level %d observer: one burst through an open door from positions alone (%d)" % [number, bursts], bursts == 1)
	bursts = 0
	world.observe_doors(level, 3, origin + Vector3(float(open.p.x), 0.0, plane + 40.0))
	world.observe_doors(level, 3, origin + Vector3(float(open.p.x), 0.0, plane - 40.0))
	say("level %d observer: a jump across a door is a respawn, no burst (%d)" % [number, bursts], bursts == 0)
	await check_moving(number, level, doors)

## The logo posters that SLIDE (a door with `ride`: the logo poster with problem posters either side on a slide hazard, clock driven): with real courier physics
## a courier at the logo poster's resting x tears it when the opening is there on arrival (one burst, no push), stops at a thud when the opening is elsewhere (a
## problem poster is a wall: a push, a bump, no burst), is not trapped by the opening's edge sweeping into it (it walks on through the wall afterwards), and an
## observer fed only positions (and the clock) sees the burst exactly when the opening is there.
func check_moving(number: int, level: int, doors: Array) -> void:
	var logos: Array = doors.filter(func(door: Dictionary) -> bool: return door.kind == "open" and not (door.ride as Dictionary).is_empty())
	say("level %d: %d sliding logo posters" % [number, logos.size()], logos.size() >= 1)
	var origin: Vector3 = world.level_origin(level)
	for logo: Dictionary in logos:
		var label := "level %d slide '%s' (logo at x=%.2f, z=%.2f)" % [number, str(logo.ride.id), logo.p.x, logo.p.z]
		var plane: float = logo.p.z
		var rest := float(logo.p.x)
		var near := _when(logo, rest, 0.15, 1.0, true)
		var far := _when(logo, rest, 2.0, 2.0, false)
		say("%s: the opening is at rest from clock %.2f and far from it from clock %.2f" % [label, near, far], near >= 0.0 and far >= 0.0)
		if near < 0.0 or far < 0.0: continue
		var through := await walk(level, Vector3(rest, 0.0, plane + 2.5), 2.0, -1.0, near)
		say("%s: opening there on arrival: through to z=%.2f, %d bursts, %d pushes, %d bumps" % [label, through.min_z, through.bursts, through.pushes, through.bumps],
			float(through.min_z) < plane - 1.5 and int(through.bursts) == 1 and int(through.pushes) == 0 and int(through.bumps) == 0)
		var stopped := await walk(level, Vector3(rest, 0.0, plane + 2.5), 1.4, -1.0, far)
		say("%s: opening elsewhere on arrival: stopped at z=%.2f, %d bursts, %d pushes (at most %.1f m/s), %d bumps" % [label, stopped.min_z, stopped.bursts, stopped.pushes, stopped.pushed, stopped.bumps],
			float(stopped.min_z) > plane - 0.1 and int(stopped.bursts) == 0 and int(stopped.pushes) >= 1 and float(stopped.pushed) <= PUSH_MAX_SPEED and int(stopped.bumps) >= 1)
		# a courier standing in the opening when it sets off is met by the shutter's edge: that is a problem poster pressing on it, so it gets the door's push back (a
		# courier that walks on at once is through before the edge arrives). Never trapped: it ends on its feet in front of the row (not inside the shutter), free to go
		# again; the opening is back at rest within the period (the arrival check above)
		var sweep := _when_leaving(logo)
		var swept := await walk(level, Vector3(rest, 0.0, plane), 4.0, -1.0, sweep, 1.2)
		say("%s: standing in the opening as it sets off (clock %.2f): %d pushes, ends at z=%.2f (plane %.2f), y=%.2f" % [label, sweep, swept.pushes, swept.z, plane, swept.get("y", 0.0)],
			float(swept.get("y", 0.0)) > -0.5 and (float(swept.min_z) < plane - 1.5 or (int(swept.pushes) >= 1 and float(swept.z) > plane + 0.1)))
		# a client sees positions and the clock only
		world.reset_effects()
		bursts = 0
		world.set_clock(near)
		for step in 40: world.observe_doors(level, 4, origin + Vector3(rest, 0.0, plane + 2.0 - step * 0.1))
		say("%s: observer, opening there: %d bursts" % [label, bursts], bursts == 1)
		world.reset_effects()
		bursts = 0
		world.set_clock(far)
		for step in 40: world.observe_doors(level, 5, origin + Vector3(rest, 0.0, plane + 2.0 - step * 0.1))
		say("%s: observer, opening elsewhere: %d bursts" % [label, bursts], bursts == 0)

## The first level clock from 10 s (the start gate is long open) at which the logo poster's opening stays within (`within`) or further than (not) `tolerance` of
## across-position `x` for `window` seconds, -1 for none within two periods of its slide.
func _when(logo: Dictionary, x: float, tolerance: float, window: float, within: bool) -> float:
	var clock := 10.0
	while clock < 10.0 + 2.0 * float((logo.ride as Dictionary).period):
		var good := true
		var at := clock
		while at <= clock + window:
			var gap := absf(float(logo.p.x) + PosterDoors.travel(logo, at).x - x)
			if (gap > tolerance) == within:
				good = false
				break
			at += 0.05
		if good: return clock
		clock += 0.05
	return -1.0

## The first clock from 10 s at which the opening, resting at the start of its travel, has just set off (so a courier standing in it is met by its edge).
func _when_leaving(logo: Dictionary) -> float:
	var clock := 10.0
	var period := float((logo.ride as Dictionary).period)
	while clock < 10.0 + 2.0 * period:
		if PosterDoors.travel(logo, clock).x == 0.0 and absf(PosterDoors.travel(logo, clock + 0.25).x) > 0.01: return clock
		clock += 0.05
	return 10.0

## The doors of the row `index` (rows by their z, nearest the start first), left to right.
func _row(doors: Array, index: int) -> Array:
	var planes: Array = []
	for door: Dictionary in doors:
		if not planes.has(snappedf(door.p.z, 0.01)): planes.append(snappedf(door.p.z, 0.01))
	planes.sort()
	planes.reverse()
	var row: Array = doors.filter(func(door: Dictionary) -> bool: return is_equal_approx(snappedf(door.p.z, 0.01), float(planes[index])))
	row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.p.x < b.p.x)
	return row
