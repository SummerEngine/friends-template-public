extends SceneTree
## The dash (courier_motion.gd): in the show it costs only a cooldown and works in the air; the flop penalty (a belly flop after it, a long stun for a dash into a wall,
## FLOP_*) is the option `dash_flop` (modes.json, `set_dash_flop`), off by default. The real CourierMotion on a flat static floor, headless.
## Default rules (dash_flop off, parts F-J):
##   (F) a dash never flops: `flop_left` stays 0, move input and jump work on the landing tick, the dash is back after DASH_COOLDOWN, never earlier;
##   (G) a dash into a wall just ends there: no stun, no push, the courier steers at once;
##   (H) the air dash: one per airtime, refused after it however long the airtime, back on landing; it bends a jump sideways (a correction) and keeps the courier up;
##   (I) the dash is a boost, not a road: spamming it on flat ground is faster than walking by a bounded amount;
##   (J) the option off clears a flop; the setter and the modes.json value (the show: off).
## The rules with the option on (dash_flop true, parts a-e): after a dash the courier lands on its belly and slides / gets up with no steering and no jump,
## a dash into a wall stuns longer, and spamming the dash is slower than walking.
## (a) a flat 30 m course: a walker, a bot that presses dash every tick and a bot that dashes once then walks;
## (b) a dash into a wall stuns longer than a normal flop, a glancing wall only slides;
## (c) move input, jump and a new dash change nothing during the flop, the jump works again after it;
## (d) the pose wire round-trips `flop` and refuses noncanonical encodings;
## (e) `flop` is 0 for walking.
## Run (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/dash_penalty_check.gd
## Last line: DASH_PENALTY ok=<bool>.
const Motion := preload("res://courier/courier_motion.gd")
const Wire := preload("res://network/owner_pose_wire.gd")
const Modes := preload("res://modes/modes.gd")
const DT := 1.0 / 60.0
const COURSE := 30.0
const MIN_ADVANTAGE := 1.10 ## the walker beats the spammer by at least 10 % over the course

var world: Node3D
var failures := 0
var flop_option := true ## the dash_flop option the motions of the option-on checks (a-e) are made with

func _initialize() -> void:
	run.call_deferred()

func expect(name: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("DASH_PENALTY ", "ok  " if ok else "FAIL", " ", name, " ", detail)

func block(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = pos

func fresh_world(with_wall := false, wall_angle := 0.0) -> void:
	if world != null:
		root.remove_child(world)
		world.free()
	world = Node3D.new()
	root.add_child(world)
	block(Vector3(0.0, -0.5, 0.0), Vector3(400.0, 1.0, 400.0))
	if with_wall:
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20.0, 3.0, 1.0)
		shape.shape = box
		wall.add_child(shape)
		world.add_child(wall)
		wall.global_position = Vector3(0.0, 1.5, -5.5) # its near face at z = -5
		wall.rotation.y = deg_to_rad(wall_angle)

func spawn(pos := Vector3.ZERO) -> Array:
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.set_dash_flop(flop_option)
	motion.reset(body, pos, 0.0)
	return [body, motion]

## A grounded courier at rest (a few ticks on the floor).
func settle(body: CharacterBody3D, motion: RefCounted) -> void:
	for i in 12:
		await physics_frame
		motion.step(body, {}, DT)

## Walks (or dashes) along -Z until `COURSE` metres; returns {"time", "trace": [[t, metres] ...], "dashes", "flops", "min_window"}.
func run_course(strategy: String) -> Dictionary:
	fresh_world()
	var made := spawn()
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion)
	var start := body.global_position.z
	var trace := []
	var dashes := 0
	var flops := 0
	var tick := 0
	while -(body.global_position.z - start) < COURSE and tick < 60 * 60:
		await physics_frame
		var dash := strategy == "spam" or (strategy == "once" and tick == 0)
		var events: Dictionary = motion.step(body, {"move": Vector2(0, -1), "dash": dash}, DT)
		if events.dashed: dashes += 1
		if events.flopped: flops += 1
		tick += 1
		trace.append([tick * DT, -(body.global_position.z - start)])
	return {"time": tick * DT, "trace": trace, "dashes": dashes, "flops": flops}

## The shortest time over which the bot covered any 10 m of the course.
func fastest_window(trace: Array, metres := 10.0) -> float:
	var best := INF
	var j := 0
	for i in trace.size():
		var from: float = trace[i][1]
		if from + metres > float(trace[-1][1]): break
		while j < trace.size() and float(trace[j][1]) < from + metres: j += 1
		if j >= trace.size(): break
		best = minf(best, float(trace[j][0]) - float(trace[i][0]))
	return best

# ------------------------------------------------------------------ (a)
func check_course() -> void:
	var walker: Dictionary = await run_course("walk")
	var spammer: Dictionary = await run_course("spam")
	var once: Dictionary = await run_course("once")
	var walk_window := fastest_window(walker.trace)
	var spam_window := fastest_window(spammer.trace)
	print("DASH_PENALTY course %.0f m: walk %.2f s | spam %.2f s (%d dashes, %d flops) | one dash then walk %.2f s | fastest 10 m: walk %.2f s, spam %.2f s" % [
		COURSE, walker.time, spammer.time, spammer.dashes, spammer.flops, once.time, walk_window, spam_window])
	print("DASH_PENALTY one dash costs %.2f s over %.0f m (a spammer %.2f s, %.0f %% slower than walking)" % [float(once.time) - float(walker.time), COURSE, float(spammer.time) - float(walker.time), (float(spammer.time) / float(walker.time) - 1.0) * 100.0])
	expect("the walker beats the dash spammer by at least 10 %", float(spammer.time) >= float(walker.time) * MIN_ADVANTAGE, "walk=%.2f spam=%.2f ratio=%.3f" % [walker.time, spammer.time, float(spammer.time) / float(walker.time)])
	expect("the spammer is slower than the walker over any 10 m", spam_window > walk_window, "spam=%.2f walk=%.2f" % [spam_window, walk_window])
	expect("the spammer really dashed (and flopped) many times", int(spammer.dashes) >= 4 and int(spammer.flops) >= 4, "dashes=%d flops=%d" % [spammer.dashes, spammer.flops])
	expect("one dash then walking is not faster than walking over the course by more than a little", float(once.time) >= float(walker.time) - 0.05, "once=%.2f walk=%.2f" % [once.time, walker.time])

# ------------------------------------------------------------------ (b)
func check_wall() -> void:
	# a dash from 2.5 m before a wall (head on)
	fresh_world(true)
	var made := spawn(Vector3(0, 0, -2.5))
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion)
	var wall_events := 0
	var wall_stun := 0.0
	var push_vz := 0.0
	var ticks := 0
	var peak := 0.0
	await physics_frame
	var events: Dictionary = motion.step(body, {"dash": true, "move": Vector2(0, -1)}, DT)
	while ticks < 120 and wall_events == 0:
		if ticks > 0:
			await physics_frame
			events = motion.step(body, {}, DT)
		ticks += 1
		if events.wall_stun:
			wall_events += 1
			wall_stun = motion.flop_left
			push_vz = body.velocity.z
	var stuck_at := body.global_position.z
	var wall_ticks := 0
	var jumped_in_stun := false
	while motion.flop_left > 0.0 and wall_ticks < 400:
		await physics_frame
		var e: Dictionary = motion.step(body, {"jump": true, "move": Vector2(0, -1), "dash": true}, DT)
		jumped_in_stun = jumped_in_stun or e.jumped or e.dashed
		wall_ticks += 1
		peak = maxf(peak, body.velocity.length())
	var stun_seconds := wall_stun
	var pushed_back := body.global_position.z - stuck_at
	# the normal flop: the same dash in the open
	fresh_world()
	var open := spawn()
	var open_body: CharacterBody3D = open[0]
	var open_motion: RefCounted = open[1]
	await settle(open_body, open_motion)
	var flop_seconds := 0.0
	var landed_at := -1
	for tick in 120:
		await physics_frame
		var e: Dictionary = open_motion.step(open_body, {"dash": tick == 0, "move": Vector2(0, -1)}, DT)
		if e.flopped:
			flop_seconds = open_motion.flop_left
			landed_at = tick
			break
	print("DASH_PENALTY wall stun %.2f s (push back %.2f m, vz %.2f) vs belly flop %.2f s (after %.2f s in the air)" % [stun_seconds, pushed_back, push_vz, flop_seconds, float(landed_at) * DT])
	expect("a dash into a wall stuns (wall_stun event) for WALL_STUN seconds", wall_events == 1 and absf(stun_seconds - Motion.WALL_STUN) < 0.03, "events=%d stun=%.2f" % [wall_events, stun_seconds])
	expect("the wall stun is longer than the normal flop", stun_seconds > flop_seconds + 0.3, "stun=%.2f flop=%.2f" % [stun_seconds, flop_seconds])
	expect("a bonked courier is pushed back a little and cannot jump or dash while stunned", push_vz > 1.0 and pushed_back > 0.0 and pushed_back < 1.5 and not jumped_in_stun, "push=%.2f vz=%.2f jumped=%s" % [pushed_back, push_vz, str(jumped_in_stun)])
	# a glancing dash (60 degrees off the wall's normal) slides along it: no stun
	fresh_world(true)
	var slid := spawn(Vector3(-2.0, 0, -2.5))
	var slid_body: CharacterBody3D = slid[0]
	var slid_motion: RefCounted = slid[1]
	await settle(slid_body, slid_motion)
	var glancing_stun := false
	for tick in 40:
		await physics_frame
		var e: Dictionary = slid_motion.step(slid_body, {"dash": tick == 0, "move": Vector2(0.9, -0.3)}, DT)
		glancing_stun = glancing_stun or e.wall_stun
	expect("a dash that only grazes a wall does not stun", not glancing_stun)

# ------------------------------------------------------------------ (c)
## Dash from standing, then a trace of positions / velocities while the flop runs, with or without inputs thrown at it.
func flop_trace(throw_inputs: bool) -> Dictionary:
	fresh_world()
	var made := spawn()
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion)
	var trace := []
	var jumped := false
	var dashed := 0
	var in_flop := false
	var after := {"jumped": false}
	var tick := 0
	var flop_ticks := 0
	var yaw_at_flop := 0.0
	var yaw_changed := false
	while tick < 240:
		await physics_frame
		var input := {"dash": tick == 0, "move": Vector2(0, -1) if tick < 5 else Vector2.ZERO}
		if in_flop and throw_inputs:
			input = {"move": Vector2(1, 0.3), "jump": true, "dash": true}
		elif not in_flop and tick >= 5:
			input = {"dash": false}
		var events: Dictionary = motion.step(body, input, DT)
		if events.dashed and tick > 0: dashed += 1
		if events.flopped:
			in_flop = true
			yaw_at_flop = motion.yaw
		if in_flop and motion.flop_left > 0.0:
			trace.append([body.global_position, body.velocity, motion.acceleration, motion.yaw])
			flop_ticks += 1
			yaw_changed = yaw_changed or absf(motion.yaw - yaw_at_flop) > 0.0001
			jumped = jumped or events.jumped
		elif in_flop:
			break # the flop is over
		tick += 1
	# the first tick without a flop: a jump press works again
	await physics_frame
	await physics_frame
	var post: Dictionary = motion.step(body, {"jump": true}, DT)
	after.jumped = post.jumped
	return {"trace": trace, "jumped": jumped, "dashes": dashed, "after_jump": after.jumped, "ticks": flop_ticks, "yaw_changed": yaw_changed}

func check_flop_locked() -> void:
	var plain: Dictionary = await flop_trace(false)
	var thrown: Dictionary = await flop_trace(true)
	var same: bool = plain.trace.size() == thrown.trace.size() and plain.trace.size() > 0
	if same:
		for i in plain.trace.size():
			for k in 4:
				var a: Variant = plain.trace[i][k]
				var b: Variant = thrown.trace[i][k]
				if typeof(a) == TYPE_FLOAT: same = same and is_equal_approx(a, b)
				else: same = same and a.is_equal_approx(b)
	print("DASH_PENALTY flop lasted %d ticks (%.2f s), distance of the slide %.2f m" % [plain.ticks, float(plain.ticks) * DT, absf(float((plain.trace[-1][0] as Vector3).z) - float((plain.trace[0][0] as Vector3).z))])
	expect("during the flop move input, jump and dash change nothing (position, velocity, facing)", same and not thrown.jumped and int(thrown.dashes) == 0 and not thrown.yaw_changed, "ticks=%d/%d jumped=%s dashes=%d" % [plain.trace.size(), thrown.trace.size(), str(thrown.jumped), thrown.dashes])
	expect("the flop lasts about FLOP_TIME", absf(float(plain.ticks) * DT - Motion.FLOP_TIME) < 0.05, "ticks=%d" % plain.ticks)
	expect("after the flop a jump works again", bool(thrown.after_jump) and bool(plain.after_jump))
	var slide := absf(float((plain.trace[-1][0] as Vector3).z) - float((plain.trace[0][0] as Vector3).z))
	expect("the belly slide is short (under 1.5 m)", slide < 1.5, "slide=%.2f" % slide)

# ------------------------------------------------------------------ (d) (e)
func check_wire_and_walk() -> void:
	var base := {"version": Wire.VERSION, "seq": 7, "reset_epoch": 2, "local_tick": 5, "time": 1.5, "transform": Transform3D(Basis.IDENTITY, Vector3(1, 0, 2)), "velocity": Vector3(0, 0, -3),
		"grounded": true, "floor_normal": Vector3.UP, "yaw": 0.5, "acceleration": Vector3.ZERO, "anchor": Vector3(1, 1, 2), "flop": 0}
	var ok := true
	for value in [0, 1, 85, 140, 255]:
		var pose := base.duplicate()
		pose.flop = value
		var back := Wire.decode(Wire.encode(pose))
		ok = ok and not back.is_empty() and int(back.flop) == value and back.size() == Wire.KEYS.size()
	expect("the pose wire round-trips flop (0, 1, 85, 140, 255) as version 2", ok and Wire.VERSION == 2 and Wire.BYTES == 248)
	for bad in [-1, 256, 1000]:
		var pose := base.duplicate()
		pose.flop = bad
		expect("a flop of %d is not a valid pose" % bad, not Wire.valid(pose) and Wire.encode(pose).is_empty())
	var missing := base.duplicate()
	missing.erase("flop")
	expect("a pose without flop is invalid", not Wire.valid(missing))
	var floaty := base.duplicate()
	floaty.flop = 1.0
	expect("a float flop is invalid", not Wire.valid(floaty))
	var data := Wire.encode(base)
	var reserved := data.duplicate()
	reserved[162] = 1
	expect("a set reserved byte (162) is refused on decode", Wire.decode(reserved).is_empty())
	var old := data.duplicate()
	old.encode_u32(4, 1)
	expect("the old version 1 is refused on decode", Wire.decode(old).is_empty())
	# (e) walking never flops, and the capture rounds the time up to 1/100 s
	fresh_world()
	var made := spawn()
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion)
	var flopped := false
	for tick in 180:
		await physics_frame
		var e: Dictionary = motion.step(body, {"move": Vector2(0, -1), "jump": tick % 50 == 20}, DT)
		flopped = flopped or e.flopped or e.wall_stun or motion.flop_left > 0.0
	expect("flop is 0 while walking (and jumping)", not flopped and clampi(ceili(motion.flop_left * 100.0), 0, 255) == 0)
	# a dash makes the pose's flop go 1..85 and back to 0
	var peak := 0
	for tick in 150:
		await physics_frame
		motion.step(body, {"dash": tick == 0, "move": Vector2(0, -1)}, DT)
		peak = maxi(peak, clampi(ceili(motion.flop_left * 100.0), 0, 255))
	expect("after a dash the pose's flop reaches FLOP_TIME in 1/100 s", peak == int(ceil(Motion.FLOP_TIME * 100.0)) or peak == int(ceil(Motion.FLOP_TIME * 100.0)) - 1, "peak=%d" % peak)

# ------------------------------------------------------------------ default rules (dash_flop off)
func step_n(body: CharacterBody3D, motion: RefCounted, input: Dictionary, count: int) -> Dictionary:
	var seen := {"dashed": 0, "flopped": 0, "wall_stun": 0, "jumped": 0, "max_flop": 0.0}
	for i in count:
		await physics_frame
		var e: Dictionary = motion.step(body, input, DT)
		seen.dashed += int(e.dashed)
		seen.flopped += int(e.flopped)
		seen.wall_stun += int(e.wall_stun)
		seen.jumped += int(e.jumped)
		seen.max_flop = maxf(seen.max_flop, motion.flop_left)
	return seen

func check_free_dash() -> void:
	flop_option = false
	# (F) a ground dash, landing, immediate control
	fresh_world()
	var made := spawn()
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion)
	var dashed: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(0, -1)}, 1)
	var air_ticks := 0
	var flop_max := 0.0
	var flopped := 0
	while not motion.grounded and air_ticks < 120:
		var e: Dictionary = await step_n(body, motion, {"move": Vector2(0, -1)}, 1)
		flop_max = maxf(flop_max, e.max_flop)
		flopped += int(e.flopped)
		air_ticks += 1
	var side: Dictionary = await step_n(body, motion, {"move": Vector2(1, 0)}, 6)
	expect("a dash is never followed by a flop: no flopped event, flop_left stays 0", dashed.dashed == 1 and flopped == 0 and flop_max == 0.0 and side.flopped == 0 and side.max_flop == 0.0, "air=%d flop=%.2f" % [air_ticks, flop_max])
	expect("after the landing the courier steers at once (its speed turns towards +X)", body.velocity.x > 1.0, "vx=%.2f" % body.velocity.x)
	var jump: Dictionary = await step_n(body, motion, {"jump": true}, 3)
	expect("the jump works at once after a dash", jump.jumped == 1)
	# the cooldown: refused inside it, one dash after it
	fresh_world()
	made = spawn()
	body = made[0]
	motion = made[1]
	await settle(body, motion)
	await step_n(body, motion, {"dash": true}, 1)
	expect("a dash starts a cooldown of DASH_COOLDOWN (1.0 to 1.5 s)", absf(motion.dash_cooldown - Motion.DASH_COOLDOWN) < 0.03 and Motion.DASH_COOLDOWN >= 1.0 and Motion.DASH_COOLDOWN <= 1.5, "cooldown=%.2f" % motion.dash_cooldown)
	var inside: Dictionary = await step_n(body, motion, {"dash": true}, 60) # a spammer inside the first second
	expect("pressing again inside the cooldown does nothing (no dash, no flop)", inside.dashed == 0 and inside.max_flop == 0.0, "dashed=%d" % inside.dashed)
	var held: Dictionary = await step_n(body, motion, {"dash": true}, int(ceil(Motion.DASH_COOLDOWN / DT)) - 61 + 6) # held until just past the end
	expect("the dash starts as soon as the cooldown is over (one dash)", held.dashed == 1, "dashed=%d" % held.dashed)
	# (G) a dash into a wall: it ends, no stun, no push, control at once
	fresh_world(true)
	made = spawn(Vector3(0, 0, -2.5))
	body = made[0]
	motion = made[1]
	await settle(body, motion)
	var into: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(0, -1)}, 40)
	var away: Dictionary = await step_n(body, motion, {"move": Vector2(0, 1)}, 20)
	expect("a dash into a wall: no wall stun, no flop, no flop time", into.wall_stun == 0 and into.flopped == 0 and into.max_flop == 0.0 and away.max_flop == 0.0, "stun=%d" % into.wall_stun)
	expect("after hitting the wall the courier walks straight back (control at once)", body.velocity.z > 3.0 and motion.dash_left <= 0.0, "vz=%.2f" % body.velocity.z)
	# (H) the air dash
	fresh_world()
	made = spawn()
	body = made[0]
	motion = made[1]
	await settle(body, motion)
	await step_n(body, motion, {"jump": true, "move": Vector2(0, -1)}, 1)
	await step_n(body, motion, {"move": Vector2(0, -1)}, 10) # up, still going -Z
	var x0 := body.global_position.x
	var air: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(1, 0)}, 1)
	var vy_dash: float = body.velocity.y
	await step_n(body, motion, {"move": Vector2(1, 0)}, 14)
	var bend := body.global_position.x - x0
	expect("an air dash bends a jump sideways by about 3 m (+X after going -Z)", air.dashed == 1 and bend > 2.5, "dx=%.2f" % bend)
	expect("an air dash lifts the courier a little (a slight arc)", vy_dash > 1.0, "vy=%.2f" % vy_dash)
	var landed := false
	var land_flop := 0.0
	for i in 150:
		var e: Dictionary = await step_n(body, motion, {"move": Vector2(0, 1)}, 1)
		land_flop = maxf(land_flop, e.max_flop)
		if motion.grounded:
			landed = true
			break
	expect("the air dash landing has no belly flop", landed and land_flop == 0.0 and motion.flop_left == 0.0)
	# one per airtime: a long fall, one dash at the start, a second long after the cooldown refused; landing gives it back
	fresh_world()
	made = spawn(Vector3(0, 60, 0))
	body = made[0]
	motion = made[1]
	var first: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(1, 0)}, 1)
	await step_n(body, motion, {}, 96) # past the cooldown, still falling (60 m take 2.7 s)
	var cooled: bool = not motion.grounded and motion.dash_cooldown <= 0.0
	var second: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(-1, 0)}, 1)
	expect("one air dash per airtime: a second one in the same fall is refused even after the cooldown", first.dashed == 1 and second.dashed == 0 and cooled, "first=%d second=%d cd=%.2f grounded=%s y=%.1f" % [first.dashed, second.dashed, motion.dash_cooldown, str(motion.grounded), body.global_position.y])
	await step_n(body, motion, {}, 260)
	var back: Dictionary = await step_n(body, motion, {"dash": true}, 1)
	expect("landing gives the dash back at once (no flop to wait out)", motion.grounded or back.dashed == 1)
	await step_n(body, motion, {}, 90)
	await step_n(body, motion, {"jump": true}, 1)
	await step_n(body, motion, {}, 8)
	var again: Dictionary = await step_n(body, motion, {"dash": true, "move": Vector2(1, 0)}, 1)
	expect("the next jump has its air dash again", again.dashed == 1)
	# (I) the dash is a boost, not a road
	var walker: Dictionary = await run_course("walk")
	var spammer: Dictionary = await run_course("spam")
	var ratio := float(spammer.time) / float(walker.time)
	print("DASH_PENALTY (no flop) %.0f m: walk %.2f s, spam %.2f s (%d dashes, %d flops), spam/walk %.3f" % [COURSE, walker.time, spammer.time, spammer.dashes, spammer.flops, ratio])
	expect("spamming the dash (only the cooldown) is faster than walking but by less than 40 %", int(spammer.flops) == 0 and ratio < 1.0 and ratio > 0.6, "ratio=%.3f" % ratio)
	# (J) the option
	fresh_world()
	flop_option = true
	made = spawn()
	body = made[0]
	motion = made[1]
	await settle(body, motion)
	await step_n(body, motion, {"dash": true}, 40)
	var had: bool = float(motion.flop_left) > 0.0
	motion.set_dash_flop(false)
	expect("turning the option off clears a flop in progress", had and motion.flop_left == 0.0 and not motion.dash_flop)
	var info: Dictionary = Modes.info("show")
	expect("modes.json: the show dashes and has dash_flop off", bool(info.get("dash", false)) and info.has("dash_flop") and not bool(info.get("dash_flop")))
	flop_option = true

func run() -> void:
	await check_free_dash()
	await check_course()
	await check_wall()
	await check_flop_locked()
	await check_wire_and_walk()
	print("DASH_PENALTY ok=", failures == 0)
	quit(1 if failures > 0 else 0)
