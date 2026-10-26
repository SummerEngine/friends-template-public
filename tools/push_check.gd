extends SceneTree
## Two players on one keyboard walk into each other at full speed for 5 s in the lobby yard (local role, the real couriers and
## contact): nobody leaps or climbs. Every tick after landing: vertical speed at most 0.5 m/s, both on the floor.
##
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 600 -- <Summer> --headless \
##     --audio-driver Dummy --fixed-fps 60 --path demo -s "$PWD/tools/push_check.gd"
##
## Prints PUSH_CHECK ok=<bool> and exits 0 only when it passes.
class VirtualLocal extends "res://client/presentation_entry.gd":
	var scripted := [Vector2.ZERO, Vector2.ZERO] ## per slot: the raw move (x right, y back) instead of the keyboard
	var tilt := 0.0 ## both carriers' roll and height input (-1..1)
	func connected_pads() -> Array: return []
	func _sample_local_inputs(_delta: float) -> void:
		for slot in 2:
			local_camera_yaws[slot] = 0.0 # raw moves are world x / z
			_local_commands[slot] = {"move": scripted[slot]}
			_local_roll[slot] = tilt * (1.0 if slot == 0 else -1.0) if round_mode != "lobby" else 0.0
			_local_height[slot] = tilt if round_mode != "lobby" else 0.0

const CourseSection := preload("res://course_section.gd")
const MAX_RISE := 0.5
var sim: Node

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	sim = VirtualLocal.new()
	root.add_child(sim)
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("PUSH_CHECK boot_timeout")
			quit(2)
			return
	sim.local_presentation.show_local_job()
	sim.local_presentation._input_mode_selected(2)
	await process_frame
	sim.local_presentation.start_job()
	await _frames(60)
	var failures := 0
	var a: CharacterBody3D = sim.actors[0]
	var b: CharacterBody3D = sim.actors[1]
	b.global_position = a.global_position + Vector3(1.2, 0.0, 0.0)
	await _frames(20)
	if not await _push("lobby"): failures += 1
	b.global_position = a.global_position + Vector3(1.2, 0.0, 0.0)
	await _frames(20)
	if not await _push("lobby, one stands", false): failures += 1
	sim.set_course_plan(CourseSection.plan(CourseSection.ADVENTURE, 2, CourseSection.CARRY))
	sim.configure_phase("level", [true, true])
	await _frames(90)
	if not await _push("carry"): failures += 1
	print("PUSH_CHECK ok=", failures == 0)
	quit(0 if failures == 0 else 1)

## The two couriers walk straight into each other for 5 s.
func _push(label: String, both := true) -> bool:
	var a: CharacterBody3D = sim.actors[0]
	var b: CharacterBody3D = sim.actors[1]
	var floor_y := minf(a.global_position.y, b.global_position.y)
	var toward := ((b.global_position - a.global_position) * Vector3(1, 0, 1)).normalized()
	sim.scripted = [Vector2(toward.x, toward.z), Vector2(-toward.x, -toward.z) if both else Vector2.ZERO]
	var worst_speed := 0.0
	var worst_rise := 0.0
	var fastest := 0.0
	var airborne := 0
	for tick in 300:
		if sim.round_mode != "lobby": sim.tilt = sin(tick * 0.08) # the carriers tilt and lift the glass while they push
		if not both: sim.scripted[0] = Vector2((b.global_position - a.global_position).x, (b.global_position - a.global_position).z).normalized() # chase
		await physics_frame
		for body: CharacterBody3D in [a, b]:
			worst_speed = maxf(worst_speed, absf(body.velocity.y))
			worst_rise = maxf(worst_rise, body.global_position.y - floor_y)
			fastest = maxf(fastest, Vector2(body.velocity.x, body.velocity.z).length())
		for slot in 2:
			if not sim.motions[slot].grounded: airborne += 1
	sim.scripted = [Vector2.ZERO, Vector2.ZERO]
	sim.tilt = 0.0
	var gap := ((b.global_position - a.global_position) * Vector3(1, 0, 1)).length()
	var ok := worst_speed <= MAX_RISE and worst_rise <= 0.1 and airborne == 0
	print("PUSH_CHECK ", "ok   " if ok else "FAIL ", label, ": vertical speed %.2f m/s, rise %.2f m, airborne ticks %d, gap %.2f m, top ground speed %.1f m/s" % [worst_speed, worst_rise, airborne, gap, fastest])
	await _frames(30)
	return ok
