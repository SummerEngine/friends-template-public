extends SceneTree
## Proves that the REQUIRED jumps of the race levels can be made with the real courier (courier_motion.gd, normal feel) on the real collision of the level world.
## `tools/gen_level_29.py --emit-jumps /tmp/j29.json` (and 30) list the jumps: a run-up start on the take-off platform, the unit direction, the brink where the jump is pressed,
## the heights of the two surfaces and the target's outline. Every jump is played tick by tick with the move input held along `u` and the jump pressed when the courier's centre is
## `--before` metres short of the brink (negative = past the brink: a late press uses the coyote time). A jump passes when the courier stands again
## on the target (feet within 0.15 m of `top`, inside the outline +- 0.2 m), or on a surface at least that high after the courier crossed the gap (an overshoot), or the courier meets a launch pad on the target. A jump from or onto a platform with edge cushions (levels/edge_bumpers.gd, the experiment) that no run lands may use the air dash (pressed 6 to 30 ticks after the jump): it passes and is counted in `dash=`. Spinner bonks are not played (belts and pads are). Prints RACE_JUMP lines and `RACE_JUMP RESULT jumps=<n> pass=<n> fail=<n> dash=<n>`; exit 1 when a jump fails.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo -s $PWD/tools/race_jump_probe.gd -- --jobs=/tmp/j29.json[,/tmp/j30.json] [--before=0.8,0.4,0,-0.25]
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const MAX_TICKS := 300
const SLACK := 0.2
const TOP_TOLERANCE := 0.15
const CUSHION_OFFSETS := [1.0, 1.25, 1.5, 1.75, 2.0] ## metres before the brink a jump from a deck with edge cushions may be pressed (the clear middle ends 0.75 to 1.5 m in from the edge)
const DASH_DELAYS := [6, 10, 14, 18, 24, 30] ## ticks after the jump the air dash is pressed when a bumpered jump needs it

var jobs_files: PackedStringArray = []
var offsets: Array = [0.8, 0.4, 0.0, -0.25]
var world: Node3D
var holder: Node3D
var passed := 0
var failed := 0
var count := 0
var dashed := 0
var only := ""

var trace := OS.get_cmdline_user_args().has("--trace")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--jobs="): jobs_files = a.trim_prefix("--jobs=").split(",")
		if a.begins_with("--only="): only = a.trim_prefix("--only=")
		if a.begins_with("--before="):
			offsets = []
			for part in a.trim_prefix("--before=").split(","): offsets.append(float(part))
	run.call_deferred()

func say(text: String) -> void:
	print("RACE_JUMP ", text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	for file in jobs_files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not parsed is Dictionary or not (parsed as Dictionary).has("jumps"):
			say("no jumps in %s" % file)
			failed += 1
			continue
		for job: Dictionary in parsed.jumps:
			if only != "" and not str(job.name).contains(only): continue
			var k := int(job.level) - 1
			world.set_active_level(k)
			await physics_frame
			await play_job(k, job)
		for pad: Dictionary in parsed.get("pads", []):
			var k := int(parsed.jumps[0].level if not (parsed.jumps as Array).is_empty() else 1) - 1
			world.set_active_level(k)
			await physics_frame
			await play_pad(k, pad)
	say("RESULT jumps=%d pass=%d fail=%d dash=%d (passes that need the air dash)" % [count, passed, failed, dashed])
	holder.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)

func inside(poly: Array, x: float, z: float) -> bool:
	var n := poly.size()
	var hit := false
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		if (float(a[1]) > z) != (float(b[1]) > z) and x < (float(b[0]) - float(a[0])) * (z - float(a[1])) / (float(b[1]) - float(a[1])) + float(a[0]): hit = not hit
	if hit: return true
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		var seg := Geometry2D.get_closest_point_to_segment(Vector2(x, z), Vector2(float(a[0]), float(a[1])), Vector2(float(b[0]), float(b[1])))
		if seg.distance_to(Vector2(x, z)) <= SLACK: return true
	return false

func play_job(k: int, planned: Dictionary) -> void:
	var origin: Vector3 = world.level_origin(k)
	var ok_offsets: Array = []
	var best_margin := -99.0
	var tries: Array = offsets.duplicate()
	var start := Vector2(float(planned.start[0]), float(planned.start[1]))
	var platform := bumpered(k, start, float(planned.from_top))
	var target := poly_bounds(planned)
	var target_bumpered := not bumpered(k, target.get_center(), float(planned.top)).is_empty()
	var lanes: Array = [["generator's lane", planned]]
	if not platform.is_empty() or target_bumpered:
		# The experiment's edge cushions (levels/edge_bumpers.gd): a bumpered deck is left from its clear middle by a jump pressed well before the brink (the generator's run-up may start
		# inside the cushions) and a bumpered target is landed on in its clear middle (the generator's lane may run along its rim). A jump is makeable when some line works: the
		# generator's own (a deck without cushions only), the same direction shifted to run through the middle of the target, or the line from the middle of the deck to the middle of the target.
		var deck := deck_under(k, start, float(planned.from_top))
		if deck.has_area():
			var from: Rect2 = Rect2(platform.safe) if not platform.is_empty() else deck
			lanes = [["shifted lane", shifted(planned, deck, from)], ["middle to middle", aimed(planned, deck, from)]]
			if platform.is_empty(): lanes.push_front(["generator's lane", planned])
		if target_bumpered: # a courier steers in the air towards the middle of a bumpered target too
			var steered := planned.duplicate()
			steered.steer = [target.get_center().x, target.get_center().y]
			lanes.append(["air steering to the middle", steered])
		tries.append_array(CUSHION_OFFSETS)
	var job: Dictionary = lanes[0][1]
	for choice: Array in lanes:
		for off in tries:
			var r: Dictionary = await play(k, origin, choice[1], float(off))
			if bool(r.landed): ok_offsets.append("%s %s" % [str(off), choice[0]] if lanes.size() > 1 else off)
			best_margin = maxf(best_margin, float(r.cross) - float((choice[1] as Dictionary).gap))
		if not ok_offsets.is_empty():
			job = choice[1]
			break
	var dash_note := ""
	if ok_offsets.is_empty() and (not platform.is_empty() or target_bumpered):
		# A landing that needs the air dash is acceptable: the jump is flown again with the dash pressed DASH_DELAYS ticks after the jump, forward or braking (the move input turned
		# against the run for the dash and the rest of the flight); the first that lands is reported.
		for choice: Array in lanes:
			for off in tries:
				for delay in DASH_DELAYS:
					for sign in [-1.0, 1.0]:
						var r: Dictionary = await play(k, origin, choice[1], float(off), int(delay), float(sign))
						best_margin = maxf(best_margin, float(r.cross) - float((choice[1] as Dictionary).gap))
						if bool(r.landed):
							ok_offsets.append("%s %s with the %s air dash %d ticks after the jump" % [str(off), choice[0], "braking" if sign < 0.0 else "forward", int(delay)])
							job = choice[1]
							dash_note = " (NEEDS THE AIR DASH)"
							dashed += 1
							break
					if dash_note != "": break
				if dash_note != "": break
			if dash_note != "": break
	count += 1
	var good := not ok_offsets.is_empty()
	if good: passed += 1
	else: failed += 1
	say("%s %s gap %.2f m (%s -> %s): landed with jump %s m before the brink, tried %s, farthest at target height %.2f m past the brink, margin %+.2f m%s" % [
		"PASS" if good else "FAIL", job.name, float(job.gap), float(job.from_top), float(job.top), str(ok_offsets), str(tries), float(job.gap) + best_margin, best_margin, dash_note])

## The platform of level `k` with edge cushions (levels/edge_bumpers.gd, the experiment) that the point `at` (level-local x, z) stands on at height `top`; {} for none.
func bumpered(k: int, at: Vector2, top: float) -> Dictionary:
	for platform: Dictionary in world._levels[k].data.edge_bumpers.platforms:
		if at.x >= float(platform.x0) and at.x <= float(platform.x1) and at.y >= float(platform.z0) and at.y <= float(platform.z1) and absf(float(platform.top) - top) < 0.3: return platform
	return {}

## The outline of the job's target (x, z).
func poly_bounds(job: Dictionary) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Array in job.poly:
		low = low.min(Vector2(float(corner[0]), float(corner[1])))
		high = high.max(Vector2(float(corner[0]), float(corner[1])))
	return Rect2(low, high - low)

## The footprint of the static floor box under the point `at` (level-local x, z) whose top is at `top`: the smallest box that holds it; {} when there is none (a mover's top) or it is a belt (the generator's lane stays).
func deck_under(k: int, at: Vector2, top: float) -> Rect2:
	var best := Rect2()
	var best_area := INF
	for block: Dictionary in world._levels[k].data.blocks:
		if str(block.k) != "box" or str(block.m) == "belt": continue
		var xf: Transform3D = block.xf
		var half: Vector3 = (block.size as Vector3) * 0.5
		if absf(xf.basis.x.z) > 0.999: half = Vector3(half.z, half.y, half.x)
		var rect := Rect2(xf.origin.x - half.x, xf.origin.z - half.z, half.x * 2.0, half.z * 2.0)
		if absf(xf.origin.y + half.y - top) < 0.05 and rect.grow(0.01).has_point(at) and rect.get_area() < best_area:
			best = rect
			best_area = rect.get_area()
	return best

## `job` flown from `start` along `u`: the brink (where the line leaves the deck `deck`) and the gap (to where it enters the target's outline) are worked out again.
func lane(job: Dictionary, deck: Rect2, start: Vector2, u: Vector2) -> Dictionary:
	var target := poly_bounds(job)
	var leave := 1e9
	for axis in 2:
		if absf(u[axis]) < 1e-6: continue
		var deck_edge: float = deck.end[axis] if u[axis] > 0.0 else deck.position[axis]
		leave = minf(leave, (deck_edge - start[axis]) / u[axis])
	var near: float = -1e9
	var far: float = 1e9
	for axis in 2:
		if absf(u[axis]) < 1e-6: continue
		var t1: float = (target.position[axis] - start[axis]) / u[axis]
		var t2: float = (target.end[axis] - start[axis]) / u[axis]
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
	var enter: float = near if near < far else leave
	var result := job.duplicate()
	result.start = [start.x, start.y]
	result.u = [u.x, u.y]
	var brink := start + u * leave
	result.edge = [brink.x, brink.y]
	result.gap = maxf(enter - leave, 0.0)
	result.run_up = leave
	return result

## The line from the middle of `from` (a deck's clear middle, or its whole footprint) straight at the middle of the target.
func aimed(job: Dictionary, deck: Rect2, from: Rect2) -> Dictionary:
	var start := from.get_center()
	return lane(job, deck, start, (poly_bounds(job).get_center() - start).normalized())

## The generator's direction, shifted sideways so that it runs through the middle of the target: it starts as far back in `from` as that line allows (the point of `from` nearest to the line when it misses).
func shifted(job: Dictionary, deck: Rect2, from: Rect2) -> Dictionary:
	var u := Vector2(float(job.u[0]), float(job.u[1]))
	var middle := poly_bounds(job).get_center()
	var best := from.get_center()
	var best_miss := INF
	var best_back := -1.0
	for step in 57:
		var back := float(step) * 0.25
		var point := middle - u * back
		var clamped := Vector2(clampf(point.x, from.position.x, from.end.x), clampf(point.y, from.position.y, from.end.y))
		var miss := point.distance_to(clamped)
		if miss < best_miss - 1e-6 or (absf(miss - best_miss) <= 1e-6 and back > best_back):
			best_miss = miss
			best_back = back
			best = clamped
	return lane(job, deck, best, u)

## One flight: the courier starts `start`, runs along u, presses jump when its centre reaches `edge` (+ offset s), lands (or not). With `dash_delay` >= 0 it also presses the air dash that many ticks
## after the jump (one per airtime: courier_motion.gd, DASH_SPEED 11 m/s for 0.3 s along the move input, the show leaves the belly flop off); from then on the move input is u * `dash_sign`.
func play(k: int, origin: Vector3, job: Dictionary, offset: float, dash_delay := -1, dash_sign := 1.0) -> Dictionary:
	var u := Vector2(float(job.u[0]), float(job.u[1]))
	var start := Vector2(float(job.start[0]), float(job.start[1]))
	var edge := Vector2(float(job.edge[0]), float(job.edge[1]))
	var from_top := float(job.from_top)
	var top := float(job.top)
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	var yaw := atan2(-u.x, -u.y)
	motion.reset(body, origin + Vector3(start.x, from_top + 0.02, start.y), yaw)
	world.set_clock(0.0)
	world.reset_effects()
	for i in 8:
		await physics_frame
		motion.step(body, {}, DT)
	motion.reset(body, origin + Vector3(start.x, from_top + 0.02, start.y), yaw)
	var airborne := false
	var landed := false
	var cross := -1.0
	var t := 0.0
	var jumped := false
	var jump_tick := -1
	for tick in MAX_TICKS:
		await physics_frame
		world.advance(DT)
		# belts and launch pads only: a spinner's bonk is timing, not reach (the hazards are proven by their own checks)
		var surface: Dictionary = world.surface_at(k, body.global_position)
		motion.set_surface({"ice": true} if bool(surface.get("ice", false)) else {})
		motion.set_belt(surface.get("belt", Vector2.ZERO))
		var effect: Dictionary = world.effects_at(k, 0, body.global_position)
		if not effect.is_empty():
			if trace and str(effect.kind) == "cushion": say("  %s offset %.2f: bumped at %s tick %d (jumped %s)" % [str(job.name), offset, str(body.global_position - origin), tick, str(jumped)])
			var at := body.global_position - origin
			if str(effect.kind) != "cushion" and inside(job.poly, at.x, at.z) and at.y >= top - 0.5 and at.y <= top + 2.5: # an edge cushion (levels/edge_bumpers.gd, the experiment) is no pad: its bounce is played, the jump has not arrived
				landed = true # a launch pad on the target: the jump arrived
				break
			motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
		var feet := body.global_position - origin
		var along := (Vector2(feet.x, feet.z) - edge).dot(u)
		var jump := false
		if not jumped and along >= -offset:
			jump = true
			jumped = true
			jump_tick = tick
		var heading := u
		if job.has("steer") and jumped: # air steering: the input turns to the middle of the target once the jump is pressed
			var to_middle := Vector2(float(job.steer[0]) - feet.x, float(job.steer[1]) - feet.z)
			if to_middle.length() > 0.3: heading = to_middle.normalized()
		var dashing := dash_delay >= 0 and jumped and tick >= jump_tick + dash_delay
		motion.step(body, {"move": heading * dash_sign if dashing else heading, "jump": jump, "dash": dash_delay >= 0 and jumped and tick == jump_tick + dash_delay}, DT)
		t += DT
		feet = body.global_position - origin
		if not motion.grounded: airborne = true
		if airborne and cross < 0.0 and feet.y <= top + 0.02 and body.velocity.y <= 0.0:
			cross = (Vector2(feet.x, feet.z) - edge).dot(u)
		if airborne and motion.grounded:
			# arrived: standing on the target, or on the same level / higher past the gap (overshoot, the next row of a stair)
			if cross < 0.0: cross = (Vector2(feet.x, feet.z) - edge).dot(u) # never fell to the target's height: it landed on a higher row past it
			landed = (inside(job.poly, feet.x, feet.z) and absf(feet.y - top) <= TOP_TOLERANCE) or (feet.y >= top - TOP_TOLERANCE and cross >= float(job.gap))
			if trace and dash_delay >= 0: say("  %s offset %.2f dash %d sign %+.0f: grounded at %s (cross %.2f, landed %s)" % [str(job.name), offset, dash_delay, dash_sign, str(feet), cross, str(landed)])
			break
		if feet.y < minf(from_top, top) - 20.0: break
	body.queue_free()
	await physics_frame
	return {"landed": landed, "cross": cross}

## A launch pad of the level (`pads` of the generator: {id, from [x, z], from_top, v, target_top, target [x0, x1, z0, z1]}): the courier stands on the pad's spot, is launched, and
## flies with no input, with the input along the launch's own heading and against it, towards the middle of the target and sideways towards its middle line (the air control). Passes when one lands
## standing on the target (inside the rectangle, 0.15 m of its top). A pad that none of those lands is flown again with the air dash (DASH_DELAYS ticks after the launch, the same inputs, the
## rest of the flight too): such a pass is reported `NEEDS THE AIR DASH` (an edge cushion of the target threw the plain flights back).
func play_pad(k: int, pad: Dictionary) -> void:
	var origin: Vector3 = world.level_origin(k)
	var heading := Vector2(float(pad.v[0]), float(pad.v[2]))
	var ahead := heading.normalized() if heading.length() > 0.1 else Vector2.ZERO
	var rect: Array = pad.target
	var middle := Vector2((float(rect[0]) + float(rect[1])) * 0.5, (float(rect[2]) + float(rect[3])) * 0.5)
	var spot := Vector2(float(pad.from[0]), float(pad.from[1]))
	var inputs: Array = [Vector2.ZERO, ahead, -ahead, (middle - spot).normalized()]
	var across := Vector2(-ahead.y, ahead.x)
	inputs.append(across * signf((middle - spot).dot(across)))
	var landed_with: Array = []
	for variant: Vector2 in inputs:
		if await fly_pad(k, origin, pad, variant, -1): landed_with.append(variant)
	var dash_note := ""
	if landed_with.is_empty():
		for delay in DASH_DELAYS:
			for variant: Vector2 in inputs.slice(1):
				if await fly_pad(k, origin, pad, variant, int(delay)):
					landed_with.append(variant)
					dash_note = " (NEEDS THE AIR DASH: input %s, %d ticks after the launch)" % [str(variant), int(delay)]
					dashed += 1
					break
			if dash_note != "": break
	count += 1
	var good := not landed_with.is_empty()
	if good: passed += 1
	else: failed += 1
	say("%s pad %s: %d of %d flights (no input, along, against, to the middle, sideways to the middle line) land on the target%s" % ["PASS" if good else "FAIL", pad.id, landed_with.size(), inputs.size(), dash_note])

## One pad flight: launched from the pad's spot, the move input `variant` after the launch (and the air dash `dash_delay` ticks after it when >= 0). True when it lands standing on the target.
func fly_pad(k: int, origin: Vector3, pad: Dictionary, variant: Vector2, dash_delay: int) -> bool:
	var rect: Array = pad.target
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	var from := Vector3(float(pad.from[0]), float(pad.from_top) + 0.02, float(pad.from[1]))
	motion.reset(body, origin + from, 0.0)
	world.set_clock(0.0)
	world.reset_effects()
	for i in 8:
		await physics_frame
		motion.step(body, {}, DT)
	motion.reset(body, origin + from, 0.0)
	world.reset_effects()
	var launched := false
	var launch_tick := -1
	var ok := false
	for tick in 600:
		await physics_frame
		world.advance(DT)
		var surface: Dictionary = world.surface_at(k, body.global_position)
		motion.set_surface({"ice": true} if bool(surface.get("ice", false)) else {})
		motion.set_belt(surface.get("belt", Vector2.ZERO))
		var effect: Dictionary = world.effects_at(k, 0, body.global_position)
		if not effect.is_empty():
			if OS.get_cmdline_user_args().has("--trace") and str(effect.kind) == "cushion": say("  pad %s variant %s dash %d: bumped at %s tick %d" % [pad.id, str(variant), dash_delay, str(body.global_position - origin), tick])
			motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
			if not launched: launch_tick = tick
			launched = true
		motion.step(body, {"move": variant if launched else Vector2.ZERO, "dash": dash_delay >= 0 and launched and tick == launch_tick + dash_delay}, DT)
		var feet := body.global_position - origin
		if launched and motion.grounded and tick > 10:
			if OS.get_cmdline_user_args().has("--trace"): say("  pad %s variant %s dash %d landed at %s (target %s top %s)" % [pad.id, str(variant), dash_delay, str(feet), str(rect), str(pad.target_top)])
			ok = feet.x >= float(rect[0]) - SLACK and feet.x <= float(rect[1]) + SLACK and feet.z >= float(rect[2]) - SLACK and feet.z <= float(rect[3]) + SLACK and absf(feet.y - float(pad.target_top)) <= TOP_TOLERANCE
			break
		if feet.y < float(pad.target_top) - 25.0: break
	body.queue_free()
	await physics_frame
	return ok
