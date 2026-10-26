extends SceneTree
## The balloon room run, headless (authority role: bodies only, no drawing):
## 1. A balloon run plays every room (course_section.gd rooms) in file order: ROOM 01 first, the time attack ends after the last room,
##    the endless run starts over at ROOM 01; the run state numbers the rooms (levels/level_run.gd).
## 2. Every room can be cleared: a scripted team carries the balloon along the room's path with the real BalloonSim, level physics,
##    hazards and the pop rules of game/team_play.gd (floors, "hit" hazards, kill volumes). The team is idealised: a player stands
##    wherever there is floor under the balloon (or jumps over a gap from the floor behind it) and touches it, pushing it towards the
##    next path point. The path splits at the points no "hit" hazard reaches (sampled over SAMPLE_SECONDS of the level clock): the team
##    can hold the balloon there as long as it likes. For every stretch between two such points the check searches the departure
##    (wait 0, 0.5, 1, ... s, four ways of playing) that gets the balloon through, the way a team learns when to go. A room passes
##    when every stretch has one; the waits and the time are printed.
## Run (never windowed):
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 900 -- <Summer> --headless \
##     --audio-driver Dummy --fixed-fps 60 --path demo -s "$PWD/tools/room_run_check.gd" [-- --room=N]
## Prints ROOM_RUN lines and ROOM_RUN_CHECK ok=<bool>; exits 0 only when every room can be cleared.
const LevelWorld := preload("res://levels/level_world.gd")
const LevelData := preload("res://levels/level_data.gd")
const LevelRun := preload("res://levels/level_run.gd")
const CourseSection := preload("res://course_section.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const DT := 1.0 / 60.0
const WORLD_MASK := 1 | 16 ## game/team_play.gd
const POP_MASK := 8
const REACH := 2.4         ## the highest balloon centre above a floor a standing player touches
const NEAR := 1.5          ## m: the balloon is at a path point
const SAMPLE_SECONDS := 24.0
const WAIT_STEP := 0.5     ## s between the departures tried
const LONGEST_WAIT := 24.0 ## s: the longest wait tried at a point
const STRETCH_SECONDS := 30.0
## How a team may play: how high players hop to reach it, how fast they run into it, whether they also touch it on its way up.
const STYLES := [{"hop": 0.5, "speed": 4.0, "eager": true}, {"hop": 0.0, "speed": 3.0, "eager": false}, {"hop": 0.8, "speed": 5.0, "eager": true},
	{"hop": 0.0, "speed": 1.5, "eager": false}]

var failures: Array[String] = []
var world: Node3D
var levels
var space: PhysicsDirectSpaceState3D
var only := 0
var debug_lines := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room="): only = int(argument.trim_prefix("--room="))
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
	print("ROOM_RUN ", "ok   " if ok else "FAIL ", text)

func _run() -> void:
	_run_order()
	world = Node3D.new()
	root.add_child(world)
	levels = LevelWorld.new()
	world.add_child(levels)
	await levels.build("authority")
	space = world.get_world_3d().direct_space_state
	var rooms := CourseSection.rooms()
	for index in rooms.size():
		if only > 0 and index + 1 != only: continue
		await _clear_room(index + 1, int(rooms[index]))
	print("ROOM_RUN_CHECK ok=", failures.is_empty(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ------------------------------------------------------------------ 1. the run
func _run_order() -> void:
	var rooms := CourseSection.rooms()
	check(rooms.size() >= 1 and CourseSection.pool_levels(CourseSection.BALLOON) == rooms, "the balloon pool is the rooms %s" % str(rooms))
	var run := LevelRun.new(CourseSection.ADVENTURE, CourseSection.level_count(), 3, CourseSection.pool_levels(CourseSection.BALLOON))
	run.play_mode = CourseSection.BALLOON
	var numbers := []
	var order := []
	for index in rooms.size():
		numbers.append(int(run.state().room))
		order.append(run.level())
		run.level_cleared(10.0, 1)
	check(order == rooms and numbers == range(1, rooms.size() + 1) and run.finished, "the time attack plays every room in file order, then ends (%s)" % str(order))
	check(run.headline() == "ALL ROOMS CLEARED" and run.summary().contains("%d rooms" % rooms.size()) and run.summary().contains("%d pops" % rooms.size()), "results: %s | %s" % [run.headline(), run.summary()])
	var endless := LevelRun.new(CourseSection.CHALLENGE, CourseSection.level_count(), 3, CourseSection.pool_levels(CourseSection.BALLOON))
	endless.play_mode = CourseSection.BALLOON
	for index in rooms.size(): endless.level_cleared(5.0)
	check(endless.level() == rooms[0] and int(endless.state().room) == 1 and not endless.finished, "the endless run starts over at ROOM 01 after the last room")
	var carry := LevelRun.new(CourseSection.ADVENTURE, CourseSection.level_count(), 3, CourseSection.pool_levels(CourseSection.CARRY))
	carry.play_mode = CourseSection.CARRY
	check(not carry.rooms and int(carry.state().room) == 0 and carry.queue.filter(func(k: int) -> bool: return k in rooms).is_empty(), "a carry run draws no rooms and numbers none")

# ------------------------------------------------------------------ 2. every room
func _clear_room(number: int, k: int) -> void:
	levels.set_active_level(k)
	var origin: Vector3 = levels.level_origin(k)
	var route := PackedVector3Array()
	for point: Vector3 in LevelData.load_level(k + 1).path: route.append(point + origin)
	var safe: Array = await _safe_points(route)
	var holds := [0]
	for index in range(1, route.size()):
		if safe[index] or index == route.size() - 1: holds.append(index)
	var clock := 0.0
	var waits := []
	for step in range(holds.size() - 1):
		var from: int = holds[step]
		var to: int = holds[step + 1]
		var passed := {}
		var wait := 0.0
		while passed.is_empty() and wait <= LONGEST_WAIT:
			for style: Dictionary in STYLES:
				var result: Dictionary = await _stretch(k, route, from, to, clock + wait, style)
				if result.ok:
					passed = result
					break
			if passed.is_empty(): wait += WAIT_STEP
		if passed.is_empty():
			check(false, "ROOM %02d %s: no departure gets the balloon from path point %d to %d (%s to %s)" % [number, levels.title(k), from, to,
				route[from] - origin, route[to] - origin])
			return
		clock += wait + float(passed.seconds)
		waits.append(wait)
	check(true, "ROOM %02d %s can be cleared: %.0f s, waits %s at the safe points" % [number, levels.title(k), clock, str(waits)])

## The balloon held over path point `from` sets off at level clock `start` and is carried to point `to` (the goal for the last point):
## {ok, seconds}.
func _stretch(k: int, route: PackedVector3Array, from: int, to: int, start: float, style: Dictionary) -> Dictionary:
	levels.set_clock(start)
	await physics_frame
	var balloon := BalloonSim.new(route[from])
	balloon.world_mask = WORLD_MASK
	var last := to == route.size() - 1
	var aim := from + 1
	var cooldown := 0.0
	var t := 0.0
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BalloonSim.RADIUS + 0.05
	query.shape = shape
	query.collision_mask = POP_MASK
	while t < STRETCH_SECONDS:
		await physics_frame
		t += DT
		levels.advance(DT)
		if aim < to and Vector2(balloon.position.x - route[aim].x, balloon.position.z - route[aim].z).length() < NEAR: aim += 1
		cooldown = maxf(cooldown - DT, 0.0)
		var players := []
		var player := _player(balloon, route[aim], false, style)
		if not player.is_empty() and cooldown <= 0.0: players.append(player)
		for event: Dictionary in balloon.step(DT, space, players):
			if event.kind == "bump": cooldown = 0.5
		if not balloon.alive:
			if only > 0 and debug_lines < 12: debug_lines += 1; print("ROOM_RUN   %s: popped on a floor at %s after %.2f s" % [str(style), balloon.position - levels.level_origin(k), t])
			return {"ok": false}
		query.transform = Transform3D(Basis.IDENTITY, balloon.position)
		var hits := space.intersect_shape(query, 1)
		if not hits.is_empty() or levels.point_zone(k, balloon.position) == "kill":
			if only > 0 and debug_lines < 12: debug_lines += 1; print("ROOM_RUN   %s: popped at %s by %s after %.2f s" % [str(style), balloon.position - levels.level_origin(k), str(hits[0].collider.name) if not hits.is_empty() else "a kill zone", t])
			return {"ok": false}
		if last and levels.point_zone(k, balloon.position) == "goal": return {"ok": true, "seconds": t}
		if not last and aim == to and Vector2(balloon.position.x - route[to].x, balloon.position.z - route[to].z).length() < NEAR:
			return {"ok": true, "seconds": t}
	return {"ok": false}

## Per path point: true when no "hit" hazard comes within reach of a balloon held there (2.4 to 4 m over the point).
func _safe_points(route: PackedVector3Array) -> Array:
	var safe := []
	safe.resize(route.size())
	safe.fill(true)
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.6 # the balloon (0.6) and about a metre of wobble while the team holds it there
	query.shape = shape
	query.collision_mask = POP_MASK
	var t := 0.0
	while t < SAMPLE_SECONDS:
		levels.set_clock(t)
		await physics_frame
		for index in route.size():
			query.transform = Transform3D(Basis.IDENTITY, route[index] + Vector3.UP * 3.2)
			if not space.intersect_shape(query, 1).is_empty(): safe[index] = false
		t += 0.25
	return safe

## The idealised player who touches the balloon this tick: {position (capsule centre), velocity}, or {} when nobody can reach it
## (no floor under it, too high even with this try's hop, or rising while the team only meets it on its way down). `style` is how this
## try's team plays: {hop (m a player jumps to reach it), speed (m/s running into it), eager (also touch it on its way up)}.
func _player(balloon: BalloonSim, target: Vector3, waiting: bool, style: Dictionary) -> Dictionary:
	var rising := balloon.velocity.y > 0.0 and not balloon.hover
	if rising and (waiting or not bool(style.eager)): return {}
	var push := Vector3(target.x - balloon.position.x, 0.0, target.z - balloon.position.z)
	push = push.normalized() if push.length() > 0.3 and not waiting else Vector3.ZERO
	var floor := _floor_under(balloon.position)
	if is_nan(floor):
		floor = _floor_under(balloon.position - push * 2.0) # jumping over a gap from the floor behind it
		if is_nan(floor): return {}
	var above: float = balloon.position.y - floor
	if above > REACH + float(style.hop) + 0.05: return {}
	var hop := clampf(above - REACH, 0.0, float(style.hop))
	var feet := Vector3(balloon.position.x, floor + hop, balloon.position.z) - push * 0.3
	return {"position": feet + Vector3(0.0, 0.9, 0.0), "velocity": push * float(style.speed) + Vector3.UP * (3.0 if hop > 0.0 else 0.0)}

## Height of the highest floor (block or mover top) under `at` that a player can stand on (not inside a kill volume, like the bottom
## of a pit), NAN if none within 15 m.
func _floor_under(at: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.DOWN * 0.7, at + Vector3.DOWN * 15.0, WORLD_MASK))
	if hit.is_empty() or (hit.normal as Vector3).y <= 0.6: return NAN
	if levels.point_zone(levels.active_level, (hit.position as Vector3) + Vector3.UP * 0.9) == "kill": return NAN
	return float((hit.position as Vector3).y)
