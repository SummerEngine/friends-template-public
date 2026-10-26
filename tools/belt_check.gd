extends SceneTree
## Dev check of the conveyor belt (`"m": "belt"`, docs/level-format.md "Conveyor belts"): a scripted courier with real courier physics on the real collision of
## tools/level_testdata/belt/level_01.json (belts of 3 m/s, level-local), the level clock and the level's effects ticking the way a simulation does (advance,
## apply_effects, step). Checks: a courier standing still is carried at the belt's speed (in x and in z); one walking with it goes at walk + belt, one walking
## against it at walk - belt; stepping off the end or jumping keeps the velocity into the air (and the plain ground takes it away again); two belts of opposite
## directions side by side carry opposite ways and a courier crossing from one to the other is turned round; a belt over ice carries slowly (ice friction and
## belt); surface_at answers a belt only within reach of its top; capture / restore carry the belt (the replay is the same). Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 "/Applications/Summer Engine.app/Contents/MacOS/Summer" --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/belt_check.gd [-- --trace=<case>]
## Prints BELT_CHECK lines and `BELT_CHECK ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const BELT := 3.0             ## m/s: every belt of the test level but the opposite one
const TOLERANCE := 0.15       ## m/s a steady speed may be off

var trace := ""
var world: Node3D
var holder: Node3D
var fails := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace="): trace = argument.trim_prefix("--trace=")
	run.call_deferred()

func say(text: String) -> void:
	print("BELT_CHECK ", text)

func verdict(ok: bool, id: String, text: String) -> void:
	if not ok: fails += 1
	say("%s %s: %s" % ["ok  " if ok else "FAIL", id, text])

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = ProjectSettings.globalize_path("res://").path_join("../tools/level_testdata/belt").simplify_path()
	holder.add_child(world)
	await world.build("authority")
	world.set_active_level(0)
	await physics_frame
	check_surface()
	await check_stand()
	await check_stand_z()
	await check_with()
	await check_against()
	await check_step_off()
	await check_jump()
	await check_opposite()
	await check_cross()
	await check_ice()
	await check_replay()
	say("ok=%s" % (fails == 0))
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

## One tick of a simulation: the clock, the level's effects on the courier, its step.
func tick(body: CharacterBody3D, motion: RefCounted, move: Vector2, jump := false) -> void:
	world.advance(DT)
	world.apply_effects(0, 0, body, motion)
	motion.step(body, {"move": move, "jump": jump}, DT)
	await physics_frame

func courier(spot: Vector3) -> Array:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.reset(body, world.level_origin(0) + spot, 0.0)
	return [body, motion]

func local(body: CharacterBody3D) -> Vector3:
	return body.global_position - world.level_origin(0)

## Runs a courier from `spot` (level-local feet) for `seconds` with a constant move input (and one jump press at tick `jump_tick`); per tick it
## records velocity x / z, position, grounded. Returns {vx, vz, pos, grounded, jumped_at}.
func trace_run(id: String, spot: Vector3, move: Vector2, seconds: float, jump_tick := -1) -> Dictionary:
	world.set_clock(0.0)
	await physics_frame
	var made := courier(spot)
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var result := {"vx": [], "vz": [], "pos": [], "grounded": []}
	for step in int(seconds / DT):
		await tick(body, motion, move, step == jump_tick)
		result.vx.append(body.velocity.x)
		result.vz.append(body.velocity.z)
		result.pos.append(local(body))
		result.grounded.append(motion.grounded)
		if trace == id and step % 6 == 0: say("  %s t=%.2f pos %s vel %s grounded %s" % [id, step * DT, local(body).snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.01), motion.grounded])
	body.queue_free()
	await physics_frame
	return result

func at_second(samples: Array, seconds: float) -> float:
	return float(samples[mini(int(seconds / DT), samples.size() - 1)])

## surface_at: a belt's velocity within reach of its top (0.4 m), plain ground and the air above give none.
func check_surface() -> void:
	var origin: Vector3 = world.level_origin(0)
	var on: Dictionary = world.surface_at(0, origin + Vector3(20, 0, -6))
	var near: Dictionary = world.surface_at(0, origin + Vector3(20, 0.3, -6))
	var high: Dictionary = world.surface_at(0, origin + Vector3(20, 1.0, -6))
	var pad: Dictionary = world.surface_at(0, origin + Vector3(0, 0, 0))
	var back: Dictionary = world.surface_at(0, origin + Vector3(20, 0, -34))
	var ice: Dictionary = world.surface_at(0, origin + Vector3(20, 0, -42))
	var ok: bool = on.get("belt", Vector2.ZERO) == Vector2(BELT, 0.0) and not on.has("ice") and near.has("belt") and high.is_empty() and pad.is_empty() \
		and back.get("belt", Vector2.ZERO) == Vector2(-BELT, 0.0) and ice.get("belt", Vector2.ZERO) == Vector2(BELT, 0.0) and bool(ice.get("ice", false))
	verdict(ok, "surface_at", "belt %s, 0.3 m up %s, 1 m up %s, pad %s, opposite %s, over ice %s" % [on, near, high, pad, back, ice])

## Standing still on a 3 m/s belt (+x): carried at 3 m/s after a short take-up.
func check_stand() -> void:
	var r: Dictionary = await trace_run("stand", Vector3(1, 0, -6), Vector2.ZERO, 3.0)
	var speed := at_second(r.vx, 2.5)
	var took := -1.0
	for i in r.vx.size():
		if float(r.vx[i]) >= BELT - TOLERANCE:
			took = i * DT
			break
	var moved: float = (r.pos[r.pos.size() - 1] as Vector3).x - 1.0
	var ok: bool = absf(speed - BELT) <= TOLERANCE and took >= 0.0 and took <= 0.5 and moved > 7.8 and moved < 9.2 and absf(at_second(r.vz, 2.5)) < 0.05
	verdict(ok, "stand", "standing still: vx %.2f m/s after 2.5 s (belt %.1f), up to speed after %.2f s, carried %.2f m in 3 s (about 8.8), vz %.2f" % [speed, BELT, took, moved, at_second(r.vz, 2.5)])

## A belt that runs along z carries along z.
func check_stand_z() -> void:
	var r: Dictionary = await trace_run("stand_z", Vector3(50, 0, -35), Vector2.ZERO, 2.5)
	var vz := at_second(r.vz, 2.0)
	var vx := at_second(r.vx, 2.0)
	var moved: float = (r.pos[r.pos.size() - 1] as Vector3).z + 35.0
	verdict(absf(vz - BELT) <= TOLERANCE and absf(vx) < 0.05 and moved > 5.5, "stand_z", "belt [0, 3]: vz %.2f vx %.2f after 2 s, carried %.2f m towards +z" % [vz, vx, moved])

## Walking with the belt: walk (5) + belt (3).
func check_with() -> void:
	var r: Dictionary = await trace_run("with", Vector3(1, 0, -12), Vector2(1, 0), 2.0)
	var speed := at_second(r.vx, 1.8)
	verdict(absf(speed - (Motion.WALK_SPEED + BELT)) <= 0.3, "with", "walking with the belt: vx %.2f m/s after 1.8 s (walk %.1f + belt %.1f)" % [speed, Motion.WALK_SPEED, BELT])

## Walking against it at 5 m/s on a 3 m/s belt nets 2 m/s the walker's way.
func check_against() -> void:
	var r: Dictionary = await trace_run("against", Vector3(39, 0, -18), Vector2(-1, 0), 2.0)
	var speed := at_second(r.vx, 1.8)
	verdict(absf(speed - (BELT - Motion.WALK_SPEED)) <= 0.3, "against", "walking against the belt: vx %.2f m/s after 1.8 s (belt %.1f - walk %.1f = %.1f)" % [speed, BELT, Motion.WALK_SPEED, BELT - Motion.WALK_SPEED])

## Standing still at the belt's end: carried over the edge; the velocity at the first airborne tick is the belt's, the air takes it from there (a metre or so
## of drift at most), and the plain ground it lands on (a lower deck) takes it away again.
func check_step_off() -> void:
	var r: Dictionary = await trace_run("off", Vector3(2, 0, -24), Vector2.ZERO, 6.0)
	var left := -1
	for i in r.grounded.size():
		if not bool(r.grounded[i]) and i > 10:
			left = i
			break
	var leave_vx := float(r.vx[left]) if left >= 0 else 0.0
	var drift := 0.0
	var landed := -1
	for i in range(maxi(left, 0), r.pos.size()):
		drift = maxf(drift, (r.pos[i] as Vector3).x - (r.pos[maxi(left, 0)] as Vector3).x)
		if (r.pos[i] as Vector3).y <= -1.99 and bool(r.grounded[i]):
			landed = i
			break
	var final_vx := float(r.vx[r.vx.size() - 1])
	var ok: bool = left >= 0 and leave_vx >= BELT - 0.3 and drift >= 0.2 and landed > left and absf(final_vx) < 0.2
	verdict(ok, "step_off", "left the belt at t=%.2f with vx %.2f (belt %.1f), drifted %.2f m in the air, landed on the plain deck at t=%.2f, vx there %.2f" % [left * DT, leave_vx, BELT, drift, landed * DT, final_vx])

## A jump from a belt keeps the velocity: standing, the first air tick still has the belt's speed; running with the belt, the jump carries far.
func check_jump() -> void:
	var stand: Dictionary = await trace_run("jump", Vector3(1, 0, -6), Vector2.ZERO, 2.5, 90)
	var vx_jump := float(stand.vx[91])
	var travelled := (stand.pos[130] as Vector3).x - (stand.pos[90] as Vector3).x
	var run: Dictionary = await trace_run("jump_run", Vector3(1, 0, -12), Vector2(1, 0), 2.5, 90)
	var in_air := 0
	for i in range(91, run.grounded.size()):
		if bool(run.grounded[i]): break
		in_air += 1
	var run_distance := (run.pos[91 + in_air] as Vector3).x - (run.pos[90] as Vector3).x if 91 + in_air < run.pos.size() else 0.0
	var ok: bool = vx_jump >= BELT - 0.3 and travelled >= 0.2 and in_air >= 30 and run_distance >= 4.0
	verdict(ok, "jump", "jump while standing: vx %.2f on the first air tick, %.2f m gone 0.67 s later; jump while walking with the belt: %.2f m in %.2f s of air" % [vx_jump, travelled, run_distance, in_air * DT])

## Two belts side by side, opposite directions: each carries its own way.
func check_opposite() -> void:
	var a: Dictionary = await trace_run("opposite_a", Vector3(20, 0, -30), Vector2.ZERO, 2.5)
	var b: Dictionary = await trace_run("opposite_b", Vector3(20, 0, -34), Vector2.ZERO, 2.5)
	var va := at_second(a.vx, 2.0)
	var vb := at_second(b.vx, 2.0)
	verdict(absf(va - BELT) <= TOLERANCE and absf(vb + BELT) <= TOLERANCE, "opposite", "lane +x: vx %.2f, the lane beside it (-x): vx %.2f" % [va, vb])

## Walking from the +x belt across the line to the -x one: the courier is carried +x, then turned round and carried -x.
func check_cross() -> void:
	var r: Dictionary = await trace_run("cross", Vector3(10, 0, -31), Vector2(0, -1), 1.2)
	var most := -INF
	var least := INF
	for i in r.vx.size():
		most = maxf(most, float(r.vx[i]))
		least = minf(least, float(r.vx[i]))
	verdict(most >= BELT - 0.3 and least <= -BELT + 0.5, "cross", "walking across the line between the lanes: vx ran from %.2f to %.2f m/s" % [most, least])

## A belt over an ice block: ice friction and the carry both apply, the carry takes its time.
func check_ice() -> void:
	var r: Dictionary = await trace_run("ice", Vector3(1, 0, -42), Vector2.ZERO, 4.0)
	var early := at_second(r.vx, 0.5)
	var late := at_second(r.vx, 3.5)
	verdict(early >= 1.0 and early <= 2.0 and late >= BELT - TOLERANCE, "ice", "belt over ice: vx %.2f after 0.5 s (an iceless belt: 3.0 after 0.2 s), %.2f after 3.5 s" % [early, late])

## capture / restore carry the belt: the same courier restored to the state of tick 90 replays the next 60 ticks exactly.
func check_replay() -> void:
	world.set_clock(0.0)
	await physics_frame
	var made := courier(Vector3(1, 0, -6))
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	for step in 90: await tick(body, motion, Vector2.ZERO)
	var state: Dictionary = motion.capture(body)
	var clock: float = world.clock
	var first := []
	for step in 60:
		await tick(body, motion, Vector2(0, -0.2))
		first.append(body.global_position)
	motion.restore(state, body)
	world.set_clock(clock)
	await physics_frame
	var worst := 0.0
	for step in 60:
		await tick(body, motion, Vector2(0, -0.2))
		worst = maxf(worst, body.global_position.distance_to(first[step]))
	var ok: bool = state.get("belt", Vector2.ZERO) == Vector2(BELT, 0.0) and worst < 0.001
	verdict(ok, "replay", "captured belt %s; the restored courier replays 60 ticks %.5f m from the first run" % [state.get("belt"), worst])
	body.queue_free()
	await physics_frame
