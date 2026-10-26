extends SceneTree
## Headless check of balloon mode in the balloon lab (no course data needed):
##
##   "$SUMMER" --headless --fixed-fps 60 --path demo -s "$PWD/tools/balloon_check.gd"
##
## 1. Alone, the balloon drifts down and pops on the floor, then respawns.
## 2. One bot under it keeps it in the air for 30 s without a pop.
## 3. Three bots carry it 22 m to the goal, past a low beam, within 90 s.
## 4. Pushed into a wall it bounces off; a wall is not a floor, so it does not pop.
## 5. snapshot() / apply_snapshot() carry the whole replicated state.
## Prints BALLOON_CHECK ok=<bool> and exits 0 only when all pass.
const Lab := preload("res://balloon/balloon_lab.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
var failures: Array[String] = []
var completed := 0 ## scenarios that ran to their end: a scenario that crashes must not pass silently

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _alone()
	await _keep_up()
	await _carry()
	await _wall()
	_snapshot()
	if completed != 5: failures.append("only %d of 5 scenarios ran to the end (script error above)" % completed)
	for failure in failures: printerr("BALLOON_CHECK_FAIL ", failure)
	print("BALLOON_CHECK ok=", failures.is_empty(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _lab(count: int, mode := "carry") -> Node3D:
	var lab: Node3D = Lab.new()
	lab.player_count = count
	lab.human = false
	lab.bot_mode = mode
	root.add_child(lab)
	return lab

func _seconds(seconds: float) -> void:
	for i in roundi(seconds * 60.0): await physics_frame

func _done(lab: Node3D) -> void:
	lab.queue_free()
	await process_frame

func _alone() -> void:
	var lab := _lab(0)
	await _seconds(4.0)
	var popped: int = lab.event_counts.pop
	var respawned: int = lab.event_counts.respawn
	print("BALLOON_ALONE pops=%d respawns=%d y=%.2f" % [popped, respawned, lab.sim.position.y])
	if popped < 1: failures.append("alone: the balloon never touched the floor in 4 s")
	if respawned < 1: failures.append("alone: no respawn after the pop")
	await _done(lab)
	completed += 1

func _keep_up() -> void:
	var lab := _lab(1, "keep")
	await _seconds(30.0)
	print("BALLOON_KEEP pops=%d bumps=%d" % [lab.sim.pops, lab.sim.bumps])
	if lab.sim.pops > 0: failures.append("keep: one bot let it touch the floor %d times in 30 s" % lab.sim.pops)
	if lab.sim.bumps < 5: failures.append("keep: only %d bumps in 30 s" % lab.sim.bumps)
	await _done(lab)
	completed += 1

func _carry() -> void:
	var lab := _lab(3)
	for i in 90 * 60:
		await physics_frame
		if lab.reached_goal: break
	print("BALLOON_CARRY goal=%s seconds=%.1f pops=%d bumps=%d bounces=%d" % [lab.reached_goal, lab.goal_seconds, lab.sim.pops, lab.sim.bumps, lab.event_counts.bounce])
	if not lab.reached_goal: failures.append("carry: three bots did not reach the goal in 90 s (balloon at %s)" % lab.sim.position)
	await _done(lab)
	completed += 1

func _wall() -> void:
	var lab := _lab(0)
	await physics_frame
	lab.sim.position = Vector3(-4.0, 2.0, -10.0)
	lab.sim.velocity = Vector3(-6.0, 1.0, 0.0)
	await _seconds(0.6)
	print("BALLOON_WALL bounces=%d pops=%d vx=%.2f" % [lab.event_counts.bounce, lab.sim.pops, lab.sim.velocity.x])
	if lab.event_counts.bounce < 1: failures.append("wall: no bounce")
	if lab.sim.pops > 0: failures.append("wall: the wall popped it")
	if lab.sim.velocity.x <= 0.0: failures.append("wall: still moving into the wall")
	await _done(lab)
	completed += 1

func _snapshot() -> void:
	var a := BalloonSim.new(Vector3(1.0, 0.0, 2.0))
	a.position = Vector3(3.0, 4.0, 5.0)
	a.velocity = Vector3(-1.0, 2.0, 0.5)
	var b := BalloonSim.new()
	b.apply_snapshot(a.snapshot())
	if not (b.position.is_equal_approx(a.position) and b.velocity.is_equal_approx(a.velocity) and b.alive == a.alive):
		failures.append("snapshot: state did not round-trip")
	completed += 1
