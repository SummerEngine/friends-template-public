extends SceneTree
## Proves that the conveyor belts of the race levels (29-32) can be crossed, and how hard they are, with the real courier (courier_motion.gd, normal feel: walk 5 m/s, dash 11 m/s for
## 0.3 s that ignores the belt) on the real collision and the real belt effects of the level world (no spinner bonks, no pads: those have their own probes).
## `python3 tools/belt_jobs.py /tmp/belts.json` lists the jobs from the level files (the belt's `belt` [vx, vz] is the one source of both what carries the courier and the speed the chevrons
## of style/belt_look.gdshader scroll at: the probe also checks that the look's material speed IS that vector's length). Every job is played tick by tick:
##   cross  the courier STANDS at the group's entry edge, at lateral offsets 1 m apart over the first strip's width, runs straight across the course (jumping 0.5 m short of every
##          step up) and has crossed when it stands on the last strip's far end. Printed: which start offsets cross (counted from the belt's upstream end; a start counts when
##          the crossing works at every jump timing of JUMP_SHORT) and the crossing time. Passes with WINDOW_NEEDED neighbouring starts.
##   lane   a belt that runs back along the course: the courier stands at its start, in the lane's middle, and runs the length. Printed: the time, or "carried back".
##   stand  a courier that stands still at the lateral middle of every belt (and 1 m from its upstream end): the seconds until the belt has carried it off.
## Prints BELT_CROSS lines and `BELT_CROSS RESULT cross=<n> ok=<n> fail=<n>`; exit 1 when a job that has to pass fails. `--no-require` plays and prints only.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo -s $PWD/tools/belt_cross_probe.gd -- --jobs=/tmp/belts.json
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const DT := 1.0 / 60.0
const MAX_CROSS := 40.0       ## s a crossing may take
const MAX_STAND := 12.0       ## s a standing courier is watched
const STAND_CROSS_MAX := 2.0  ## s: a courier standing still in the middle of a belt ACROSS the course is carried off within this
const LANE_BUDGET := 15.0     ## s: running the length of a belt that runs back along the course takes at most this
const WINDOW_NEEDED := 4      ## a crossing must succeed from at least this many neighbouring start offsets (1 m apart) at every jump timing of JUMP_SHORT
const JUMP_SHORT := [0.3, 0.5, 0.8] ## m short of a step's edge where the run presses jump (a late and an early press as well as the middle)

var jobs_file := ""
var require := true
var world: Node3D
var holder: Node3D
var ok_count := 0
var fail_count := 0
var count := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--jobs="): jobs_file = a.trim_prefix("--jobs=")
		if a == "--no-require": require = false
	run.call_deferred()

func say(text: String) -> void:
	print("BELT_CROSS ", text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(jobs_file))
	if not parsed is Dictionary or not (parsed as Dictionary).has("jobs"):
		say("no jobs in %s" % jobs_file)
		quit(1)
		return
	var last_level := -1
	for job: Dictionary in parsed.jobs:
		var k := int(job.level) - 1
		if k != last_level:
			world.set_active_level(k)
			await physics_frame
			last_level = k
		check_look(job)
		if str(job.kind) == "cross": await play_cross(k, job)
		else: await play_lane(k, job)
		await play_stand(k, job)
	say("RESULT cross=%d ok=%d fail=%d" % [count, ok_count, fail_count])
	holder.queue_free()
	await process_frame
	quit(1 if fail_count > 0 and require else 0)

func verdict(good: bool, text: String) -> void:
	count += 1
	if good: ok_count += 1
	else: fail_count += 1
	say("%s %s" % ["PASS" if good else "FAIL", text])

## The chevrons scroll at the belt's own speed: the look's material speed (real_look.gd _belt_material) is the length of the key's velocity, the key is the block's `belt`.
func check_look(job: Dictionary) -> void:
	for strip: Dictionary in job.strips:
		var flow := Vector2(float(strip.flow[0]), float(strip.flow[1]))
		var seen := BlockMesh.belt_velocity(BlockMesh.belt_key(flow))
		if not seen.is_equal_approx(flow): verdict(false, "%s: look speed %s differs from the belt %s" % [job.name, str(seen), str(flow)])

func new_courier(origin: Vector3, at: Vector2, top: float, yaw: float) -> Array:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, origin + Vector3(at.x, top + 0.02, at.y), yaw)
	world.set_clock(0.0)
	world.reset_effects()
	return [body, motion]

func settle(body: CharacterBody3D, motion: RefCounted, origin: Vector3, at: Vector2, top: float, yaw: float) -> void:
	for i in 8:
		await physics_frame
		motion.step(body, {}, DT)
	motion.reset(body, origin + Vector3(at.x, top + 0.02, at.y), yaw)

func tick(k: int, body: CharacterBody3D, motion: RefCounted, input: Dictionary) -> void:
	await physics_frame
	world.advance(DT)
	var surface: Dictionary = world.surface_at(k, body.global_position)
	motion.set_surface({"ice": true} if bool(surface.get("ice", false)) else {})
	motion.set_belt(surface.get("belt", Vector2.ZERO))
	motion.step(body, input, DT)

## One run along u from `at`: {"done": reached the end, "time": s, "off": carried back / fell}.
func run_along(k: int, job: Dictionary, at: Vector2, with_jumps: bool, short := 0.5) -> Dictionary:
	var origin: Vector3 = world.level_origin(k)
	var u := Vector2(float(job.u[0]), float(job.u[1]))
	var top: float = float((job.strips[0] as Dictionary).top)
	var yaw := atan2(-u.x, -u.y)
	var made := new_courier(origin, at, top, yaw)
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	await settle(body, motion, origin, at, top, yaw)
	var jumps: Array = job.jumps if with_jumps else []
	var next_jump := 0
	var result := {"done": false, "time": 0.0, "off": false}
	var floor_y := top - 3.0
	for s in job.strips: floor_y = minf(floor_y, float(s.top) - 3.0)
	for t in int(MAX_CROSS / DT):
		var feet := body.global_position - origin
		var along := Vector2(feet.x, feet.z).dot(u)
		var jump := false
		if next_jump < jumps.size() and along >= float(jumps[next_jump]) - short:
			jump = true
			next_jump += 1
		await tick(k, body, motion, {"move": u, "jump": jump})
		feet = body.global_position - origin
		along = Vector2(feet.x, feet.z).dot(u)
		result.time = (t + 1) * DT
		if along >= float(job.end_along) and motion.grounded and feet.y >= float(job.end_top) - 0.2:
			result.done = true
			break
		if feet.y < floor_y or along < float(job.along_min) - 1.0:
			result.off = true
			break
	body.queue_free()
	await physics_frame
	return result

func play_cross(k: int, job: Dictionary) -> void:
	var passes: Array = []
	var times: Array = []
	var starts: Array = job.starts
	for s: Array in starts:
		var all := true
		var middle := 0.0
		for short: float in JUMP_SHORT:
			var r: Dictionary = await run_along(k, job, Vector2(float(s[0]), float(s[1])), true, short)
			if not bool(r.done): all = false
			elif is_equal_approx(short, 0.5) or (job.jumps as Array).is_empty(): middle = float(r.time)
			if (job.jumps as Array).is_empty(): break # no step: the timing does not matter
		passes.append(all)
		if all: times.append(middle)
	# starts run across the first strip from lateral min to max: put the upstream end first
	var u := Vector2(float(job.u[0]), float(job.u[1]))
	var flow := Vector2(float(job.flow[0]), float(job.flow[1]))
	var lateral := Vector2(-u.y, u.x)
	if flow.dot(lateral) < 0.0: passes.reverse()
	var window := 0
	var run_len := 0
	var text := ""
	for p in passes:
		text += "o" if p else "x"
		run_len = run_len + 1 if p else 0
		window = maxi(window, run_len)
	var best := "-" if times.is_empty() else "%.1fs" % (times.reduce(func(a, b): return minf(a, b)))
	verdict(window >= WINDOW_NEEDED, "%s: straight run crosses from %d neighbouring starts of %d (upstream end -> downstream end) [%s], %s; belt %.1f m/s over %.1f m deep x %.1f m wide" % [
		job.name, window, passes.size(), text, "fastest " + best, float(job.speed), float(job.get("depth", 0.0)), float(job.get("width", 0.0))])

func play_lane(k: int, job: Dictionary) -> void:
	var s: Array = job.starts[0]
	var r: Dictionary = await run_along(k, job, Vector2(float(s[0]), float(s[1])), false)
	verdict(bool(r.done) and float(r.time) <= LANE_BUDGET, "%s: running its length from the start %s (%.1f s, budget %.0f s)" % [job.name, "arrives" if bool(r.done) else ("carried back / off" if bool(r.off) else "does not arrive"), float(r.time), LANE_BUDGET])

## A courier standing still: the seconds until the belt has carried it off (its feet leave the belt, or it falls). `strips` of a group each; only the first strip counts for a chain.
func play_stand(k: int, job: Dictionary) -> void:
	var origin: Vector3 = world.level_origin(k)
	var report := ""
	var carried_off := true
	for strip: Dictionary in job.strips:
		var rect: Array = strip.rect
		var flow := Vector2(float(strip.flow[0]), float(strip.flow[1]))
		var dir := flow.normalized()
		var mid := Vector2((float(rect[0]) + float(rect[1])) / 2.0, (float(rect[2]) + float(rect[3])) / 2.0)
		var half := Vector2((float(rect[1]) - float(rect[0])) / 2.0, (float(rect[3]) - float(rect[2])) / 2.0)
		var extent := absf(dir.x) * half.x + absf(dir.y) * half.y   # half the belt's length along the flow
		var spots := [mid, mid - dir * (extent - 1.0)]
		var labels := ["middle", "1 m from upstream end"]
		var seconds: Array = []
		for i in spots.size():
			var at: Vector2 = spots[i]
			var yaw := 0.0
			var made := new_courier(origin, at, float(strip.top), yaw)
			var body: CharacterBody3D = made[0]
			var motion: RefCounted = made[1]
			await settle(body, motion, origin, at, float(strip.top), yaw)
			var left := MAX_STAND
			for t in int(MAX_STAND / DT):
				await tick(k, body, motion, {})
				var feet := body.global_position - origin
				var surface: Dictionary = world.surface_at(k, body.global_position)
				if not surface.has("belt") or feet.y < float(strip.top) - 0.5:
					left = (t + 1) * DT
					break
			seconds.append(left)
			body.queue_free()
			await physics_frame
		if str(job.kind) == "cross" and float(seconds[0]) > STAND_CROSS_MAX: carried_off = false
		report += " | strip %s: %s %.1f s, %s %.1f s" % [str(strip.rect.map(func(v): return snappedf(v, 0.1))), labels[0], seconds[0], labels[1], seconds[1]]
		if str(job.kind) == "cross" and (job.strips as Array).size() > 1: break
	verdict(carried_off, "%s: standing still is carried off after%s" % [job.name, report])
