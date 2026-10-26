extends SceneTree
## Check of the rule "nothing in the game vanishes into nowhere" on the real levels, numbers only, headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --fixed-fps 60 --path demo -s $PWD/tools/vanish_check.gd
## * every `blink` hazard of every level (levels/hazards.gd pose, levels/level_world.gd _pose_all): while it is solid it stands at its place, the collision window is
##   exactly the schedule (collision layer on <=> m < on), the body is never hidden, and while it is not solid it hangs under its place: at least its own thickness plus
##   BLINK_CLEAR once it has fallen (or as deep as it is allowed to), never shows a jump from one frame to the next, and is back at its place when it is solid again;
## * the step tiles' fall (style/step_tile_look.gd): nothing scales, the tile falls from where it stood to a far rest and keeps it, `StepTiles.FALL_TIME` is the look's;
## * the poster door look (style/poster_door_look.gd): a torn poster hangs from its corner, rolls up into the top edge and rolls down again; the corner never moves,
##   the board never hides or shrinks to nothing, and it is whole again at the end;
## * every rolling `ball` of every level (ROLLING ROAD has 27) over a whole period, 60 ticks a second: it never jumps a metre it cannot have rolled (position) or turns
##   faster than it rolls (the look's basis, also across a bounce), it is drawn exactly while it is on its path or in a housing lead, and wherever it goes from drawn to hidden
##   (or back) it is fully inside its housing: under the floor's top for a floor hole, a radius beyond the wall face for a wall slot.
## Prints VANISH_CHECK lines and `VANISH_CHECK ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Hazards := preload("res://levels/hazards.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const TileLook := preload("res://style/step_tile_look.gd")
const PosterDoorLook := preload("res://style/poster_door_look.gd")
const DT := 1.0 / 60.0
const EPS := 1e-3

var failures := 0
var checks := 0
var hung: Array[float] = [] ## per blink that passed: how deep it hangs (m)
var ball_failures := 0

func say(text: String, ok := true) -> void:
	checks += 1
	if not ok: failures += 1
	print("VANISH_CHECK ", "ok   " if ok else "FAIL ", text)

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("VANISH_CHECK FAIL timed out")
		print("VANISH_CHECK ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var world := LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	var blinks := 0
	for k in world.level_count():
		blinks += check_level(world, k)
	say("%d blink hazards in %d levels: each stands at its place while solid, collides exactly while solid, is never hidden, hangs %.1f to %.1f m under its place while gone (its thickness + %.0f m at least) and is back when solid again, with no jump from frame to frame" % [blinks, world.level_count(), hung.min() if not hung.is_empty() else 0.0, hung.max() if not hung.is_empty() else 0.0, Hazards.BLINK_CLEAR], blinks >= 40 and hung.size() == blinks)
	var balls := 0
	for k in world.level_count():
		balls += check_level_balls(world, k)
	say("%d rolling balls: no jump in position or turn between two ticks, drawn exactly while on the path or in a lead, hidden only fully inside a floor hole or a wall slot" % balls, balls >= 30 and ball_failures == 0)
	check_tiles()
	check_poster()
	say("ok=%s (%d checks)" % [failures == 0, checks], failures == 0)
	print("VANISH_CHECK ok=%s" % (failures == 0))
	holder.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

## The thickness of a blink's parts (m), from the level file's own numbers (the blinks of the levels are not rotated).
func thickness(h: Dictionary) -> float:
	var low := INF
	var high := -INF
	for part: Dictionary in h.parts:
		var centre: float = (part.xf as Transform3D).origin.y
		var half: float = (part.size as Vector3).y * 0.5
		low = minf(low, centre - half)
		high = maxf(high, centre + half)
	return high - low

func check_level(world: Node3D, k: int) -> int:
	var count := 0
	world.set_active_level(k)
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		var h: Dictionary = mover.h
		if h.k != "blink": continue
		count += 1
		check_blink(world, k, index, mover)
	return count

## Every ball of level `k` over one period of its own cycle (the number of balls): see the header.
func check_level_balls(world: Node3D, k: int) -> int:
	var count := 0
	world.set_active_level(k)
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		if mover.h.k != "ball" or not (mover.h as Dictionary).has("ports"): continue
		count += 1
		check_ball(world, k, index, mover)
	return count

## True when a ball at `pose` is fully inside the housing `port` (a wall slot: its centre a radius beyond the wall face; a floor hole: its top under the floor's top),
## give or take `slack` m (one tick of travel: the last drawn tick may be that short of the end of the lead, which is a radius and 0.1 m beyond the face).
func housed(port: Dictionary, pose: Hazards.Pose, rad: float, slack: float) -> bool:
	if port.kind == "wall": return (pose.position - (port.point as Vector3)).dot(port.normal as Vector3) <= -rad + slack
	if port.kind == "floor": return pose.position.y + rad <= (port.point as Vector3).y + slack
	return false

func check_ball(world: Node3D, k: int, index: int, mover: Dictionary) -> void:
	var h: Dictionary = mover.h
	var body: AnimatableBody3D = mover.body
	var label := "level %d %s" % [k + 1, h.id if h.id != "" else "ball %d" % index]
	var ports: Dictionary = h.ports
	var rad := float(h.rad)
	var speed := float(h.speed)
	var period := float(h.period)
	var step_max := (speed + 2.0 * (2.0 * rad + Hazards.SWALLOW) / Hazards.PORT_TIME) * DT * 1.1 + 1e-3 # position per tick: the path's speed, or a sink / rise out of a floor hole
	var turn_max := speed / maxf(rad, 0.1) * DT * 1.1 + 1e-3 # radians per tick
	var bad: PackedStringArray = []
	var previous: Hazards.Pose = null
	var previous_shown := false
	var shown_count := 0
	var hidden_count := 0
	var ticks := int(ceil(period / DT)) + 1
	for i in ticks:
		var m := minf(float(i) * DT, period - 0.0001)
		world.set_clock(m - float(h.phase))
		var pose: Hazards.Pose = mover.pose
		var shown := pose.active or pose.lead
		if body.visible != shown: bad.append("body.visible %s but pose says %s at m %.2f" % [body.visible, shown, m])
		if shown: shown_count += 1
		else: hidden_count += 1
		if previous != null:
			if shown and previous_shown:
				if pose.position.distance_to(previous.position) > step_max: bad.append("jumps %.3f m in one tick at m %.2f" % [pose.position.distance_to(previous.position), m])
				var turned := (previous.basis.inverse() * pose.basis).get_rotation_quaternion().get_angle()
				if turned > turn_max: bad.append("turns %.3f rad in one tick at m %.2f (at most %.3f)" % [turned, m, turn_max])
			elif shown != previous_shown:
				var seen: Hazards.Pose = pose if shown else previous # the last / first tick it is drawn
				if not housed(ports.enter, seen, rad, step_max) and not housed(ports.leave, seen, rad, step_max): bad.append("%s out of view at m %.2f while not inside a hole or a slot (centre %s)" % ["goes" if previous_shown else "comes", m, seen.position])
		if previous == null: previous = Hazards.Pose.new()
		previous.position = pose.position
		previous.basis = pose.basis
		previous_shown = shown
	if shown_count == 0 or hidden_count == 0: bad.append("never %s over a period" % ("drawn" if shown_count == 0 else "hidden"))
	if not bad.is_empty():
		ball_failures += 1
		say("%s: %d problems, first: %s" % [label, bad.size(), "; ".join(bad.slice(0, 3))], false)
	else: checks += 1

func check_blink(world: Node3D, k: int, index: int, mover: Dictionary) -> void:
	var h: Dictionary = mover.h
	var body: AnimatableBody3D = mover.body
	var label := "level %d %s" % [k + 1, h.id if h.id != "" else "blink %d" % index]
	var on_time := float(h.on_time)
	var total := on_time + float(h.off_time)
	var rest: Vector3 = h.pivot
	var need := thickness(h) + Hazards.BLINK_CLEAR
	var sink := float(h.sink)
	var slope := maxf(sqrt(2.0 * float(h.fall_accel) * sink), 2.0 * sink / float(h.rise_time))
	var up := str(h.get("slot", "")) == Hazards.GATE_SLOT # the start gate (a door) goes UP when it is gone; "under its place" below reads "over" for it
	var bad: PackedStringArray = []
	if float(h.off_time) < Hazards.BLINK_MIN_OFF: bad.append("off %.2f is shorter than BLINK_MIN_OFF" % float(h.off_time))
	if h.base != Basis.IDENTITY: bad.append("rotated blink: the thickness is not measured")
	# the moments to look at (m = seconds into the cycle): around the end of `on`, the fall, the hang, the climb, the wrap
	var moments: Array[float] = []
	for i in 61: moments.append(minf(total * float(i) / 60.0, total - 0.0001))
	for i in range(-20, 241): moments.append(clampf(on_time + float(i) * 0.01, 0.0, total - 0.0001))
	for i in range(-40, 1): moments.append(clampf(total + float(i) * DT, 0.0, total - 0.0001))
	moments.sort()
	var deepest := 0.0
	var previous := -1.0
	var previous_m := -1.0
	for m in moments:
		world.set_clock(m - float(h.phase))
		var pose: Hazards.Pose = mover.pose
		var depth := (pose.position.y - rest.y if up else rest.y - pose.position.y) # what level_world.gd sets as the body's transform (the node itself follows the physics frame)
		var solid := m < on_time
		if (body.collision_layer != 0) != solid: bad.append("collision %s at m %.2f" % ["on" if body.collision_layer != 0 else "off", m])
		if pose.active != solid: bad.append("pose.active %s at m %.2f" % [pose.active, m])
		if not body.visible and not (up and depth > LevelWorld.GATE_GONE): bad.append("body hidden at m %.2f" % m)
		if solid:
			if absf(depth) > EPS: bad.append("solid but %.3f m under its place at m %.2f" % [depth, m])
		else:
			if not pose.lead: bad.append("gone but not drawn (lead) at m %.2f" % m)
			if depth < -EPS: bad.append("gone and ABOVE its place at m %.2f" % m)
			deepest = maxf(deepest, depth)
			if m >= on_time + Hazards.BLINK_FALL_TIME and m <= total - float(h.rise_time) and depth < minf(need, sink) - EPS:
				bad.append("hangs only %.2f m under its place at m %.2f (needs %.2f)" % [depth, m, minf(need, sink)])
		if previous >= 0.0 and m - previous_m < DT * 1.01 and absf(depth - previous) > slope * (m - previous_m) * 1.1 + 1e-4:
			bad.append("jumps %.3f m in %.3f s at m %.2f" % [depth - previous, m - previous_m, m])
		previous = depth
		previous_m = m
	if deepest < need - EPS: bad.append("never falls its own thickness + clearance (%.2f of %.2f)" % [deepest, need])
	world.set_clock(total - float(h.phase) - 0.0001)
	if absf(rest.y - (mover.pose as Hazards.Pose).position.y) > 0.01: bad.append("not back at its place when it is solid again (%.3f m off)" % (rest.y - (mover.pose as Hazards.Pose).position.y))
	var told := "ok" if bad.is_empty() else "%d problems, first: %s" % [bad.size(), "; ".join(bad.slice(0, 3))]
	if bad.is_empty():
		checks += 1
		hung.append(deepest)
	else: say("%s: on %.2f off %.2f, hangs %.2f m under its place (thickness %.2f), %s" % [label, on_time, float(h.off_time), deepest, thickness(h), told], false)

## The step tiles' look: a pure function of the time since the tile went.
func check_tiles() -> void:
	var at := Vector3(3.0, -4.0, 1.5)
	say("a tile's fall is the look's FALL_TIME (%.1f s) in the world's states" % TileLook.FALL_TIME, StepTiles.FALL_TIME == TileLook.FALL_TIME and TileLook.FALL_TIME >= 2.0)
	var start: Transform3D = TileLook._fallen(at, 0.0)
	say("a tile that has just gone is where it stood, not turned and not scaled", start.origin.is_equal_approx(at) and start.basis.is_equal_approx(Basis.IDENTITY))
	var previous := at.y
	var steady := true
	var unscaled := true
	var tau := 0.0
	while tau <= TileLook.FALL_TIME + 1.0:
		var pose: Transform3D = TileLook._fallen(at, tau)
		if pose.origin.y > previous + 1e-6: steady = false
		if not pose.basis.get_scale().is_equal_approx(Vector3.ONE): unscaled = false
		previous = pose.origin.y
		tau += DT
	say("it only ever goes down, and nothing scales (no shrinking away)", steady and unscaled)
	var rest: Transform3D = TileLook._fallen(at, TileLook.FALL_TIME)
	say("it comes to rest %.1f m under its place (far below any floor) and keeps that pose (the gone mode)" % (at.y - rest.origin.y), at.y - rest.origin.y >= 40.0 and rest.is_equal_approx(TileLook._fallen(at, TileLook.FALL_TIME + 5.0)))
	var early: Transform3D = TileLook._fallen(at, 0.15)
	var tilt := absf(early.basis.get_euler().x)
	say("it tumbles slowly at first: after 0.15 s it has dropped %.2f m and turned %.2f rad" % [at.y - early.origin.y, tilt], at.y - early.origin.y > 0.15 and tilt < 0.1)

## The poster look under the clock: a flap from the tear to the new poster.
func check_poster() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var size := Vector2(2.75, 3.5)
	var plane := Vector3(0.0, 1.75, -8.0)
	var board := Node3D.new()
	board.set_meta("slot_index", 0)
	board.transform = Transform3D(Basis.IDENTITY, plane)
	scene_root.add_child(board)
	var doors: Array = [{"index": 0, "id": "obstacle_1", "kind": "open", "p": plane, "normal": Vector3.BACK, "right": Vector3.RIGHT, "half": size.x * 0.5, "bottom": 0.0, "top": size.y, "ride": {}}]
	var look: Node3D = PosterDoorLook.build(scene_root, doors, [{"size": size}])
	var entry: Dictionary = look._doors[0]
	var side := float(entry.side)
	var corner := Vector3(side * size.x * 0.5, size.y * 0.5, 0.0)
	var base: Transform3D = entry.base
	look.burst(0, plane, Vector3.FORWARD)
	var seen_roll := 1.0
	var anchored := true
	var visible_always := true
	var steps := 0
	var biggest := 0.0
	var last := PackedVector3Array()
	while str(entry.state) != "whole" and steps < 600:
		look._process(DT)
		steps += 1
		var local: Transform3D = base.affine_inverse() * board.transform
		if (local * corner).distance_to(corner) > 0.002: anchored = false
		if not board.visible: visible_always = false
		seen_roll = minf(seen_roll, local.basis.get_scale().y)
		var corners := PackedVector3Array()
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]: corners.append(local * Vector3(size.x * sx, size.y * sy, 0.0))
		if not last.is_empty():
			for i in 4: biggest = maxf(biggest, corners[i].distance_to(last[i]))
		last = corners
	var seconds := float(steps) * DT
	say("the torn poster is whole again after %.2f s (rip, %.1f s hang, %.1f s roll up, %.1f s roll down)" % [seconds, PosterDoorLook.FLAP, PosterDoorLook.ROLL_UP, PosterDoorLook.ROLL_DOWN], absf(seconds - (PosterDoorLook.FLAP + PosterDoorLook.ROLL_UP + PosterDoorLook.ROLL_DOWN)) < 0.1)
	say("its top corner never moves while it tears, hangs, rolls up and rolls down", anchored)
	say("the board is never hidden, and rolled up it keeps %.3f of its height (a thin roll, not nothing)" % seen_roll, visible_always and seen_roll > 0.01 and seen_roll < 0.05)
	say("no corner of the board moves more than %.2f m between two frames (no pop)" % biggest, biggest < 0.6)
	say("it ends as the whole poster, exactly where it hung", (base.affine_inverse() * board.transform).is_equal_approx(Transform3D.IDENTITY))
	var bars := 0
	for child: Node in look.get_children():
		if child.name.begins_with("Doorway"):
			var frame := child as Node3D
			bars += frame.get_child_count() if frame.visible else 1000
	say("the doorway bars are always there behind the poster (%d, never toggled)" % bars, bars == 3)
	scene_root.queue_free()
