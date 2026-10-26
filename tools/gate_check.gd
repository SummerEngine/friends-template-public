extends SceneTree
## Dev check of level 32 (GATE RUSH): the gate-row doors (`lift` hazards with a `hold`, a part of tone "door") and the slime slope (`m: slime`), with real courier physics on the real
## collision of demo/levels/level_32.json and the level's effects ticking the way a simulation does (advance, apply_effects, step). Checks:
##   * the door schedule: Hazards.cycle with a `hold` (dwell open, rise, dwell shut, fall), a door is flush with the floor when open and 2 m up when shut, and the
##     six rows' patterns (which doors are open at which clock) are the ones the generator promised;
##   * a courier standing on a flush door that rises is lifted or thrown, never left inside the door or under the floor (centre, edge, half on the floor);
##   * gate doors are solid and never throw anybody (`hit` false): a courier running through an open door passes, one that runs into a shut door (even jumping) is stopped,
##     one that runs into a rising or closing door is stopped or passes, and none of them gets a launch or a bonk event; a courier standing under a closing door (or half in it) is moved
##     out of its volume by LevelWorld.door_nudge (a depenetration: at most NUDGE_MAX m in all (0.62 standing in the middle of the door), never pushed under the floor, no upward or backward velocity);
##   * the slime slope: surface_at answers it, a courier standing on it slides downhill from rest and speeds up (never above SLIME_MAX), steering still works, a
##     courier that jumps along it ends up faster than one that does not, and the foot of the slope leaves it on the plain floor.
## Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 "/Applications/Summer Engine.app/Contents/MacOS/Summer" --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/gate_check.gd [-- --trace=<case>]
## Prints GATE_CHECK lines and `GATE_CHECK ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const Hazards := preload("res://levels/hazards.gd")
const DT := 1.0 / 60.0
const LEVEL := 32
const K := LEVEL - 1
const DOOR_H := 3.5
const ROW1 := 26.25     ## f of row 1's frame
const DOOR_F := 25.75   ## f of the doors' plane (the front face of the gate wall, tools/gate_piece.py)
const STANDING_SINK := 0.05  ## m a courier caught standing under a coming-down door may be pressed under the floor (the nudge moves it sideways before the door arrives)
const NUDGE_MAX := 0.7       ## m: the farthest a courier is moved by a closing door: its half depth 0.25 + the courier radius 0.35 (standing in the middle of its plane) + the 2 cm margin of the nudge and a little slack
const NO_LAUNCH := 1.0       ## m/s: no vertical speed above this and no horizontal speed away from the door above this on a courier that stands or walks into a door
const SLOPE_F0 := 98.0
const SLOPE_F1 := 128.0
const DROP := 5.0

var trace := ""
var world: Node3D
var holder: Node3D
var fails := 0
var data: Dictionary

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace="): trace = argument.trim_prefix("--trace=")
	run.call_deferred()

func say(text: String) -> void:
	print("GATE_CHECK ", text)

func verdict(ok: bool, id: String, text: String) -> void:
	if not ok: fails += 1
	say("%s %s: %s" % ["ok  " if ok else "FAIL", id, text])

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	if world.level_count() < LEVEL:
		verdict(false, "level", "level %d is not there (%d levels)" % [LEVEL, world.level_count()])
		quit(1)
		return
	world.set_active_level(K)
	data = world._levels[K].data
	await physics_frame
	check_schedule()
	check_no_hit_doors()
	check_patterns()
	await check_stand_centre()
	await check_stand_edge()
	await check_run_through()
	await check_shut_door()
	await check_rising_door()
	check_surface()
	await check_slide()
	await check_jump_speed()
	await check_steer()
	say("ok=%s" % (fails == 0))
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

func tick(body: CharacterBody3D, motion: RefCounted, move: Vector2, jump := false) -> void:
	world.advance(DT)
	world.apply_effects(K, 0, body, motion)
	motion.step(body, {"move": move, "jump": jump}, DT)
	await physics_frame

func courier(spot: Vector3) -> Array:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.reset(body, world.level_origin(K) + spot, 0.0)
	return [body, motion]

func local(body: CharacterBody3D) -> Vector3:
	return body.global_position - world.level_origin(K)

func hazard(id: String) -> Dictionary:
	for h: Dictionary in data.hazards:
		if h.id == id: return h
	return {}

## Door height over its shut pose (0 = shut, on the floor .. DOOR_H = lifted into the frame) at level clock t.
func door_rise(id: String, t: float) -> float:
	var pose := Hazards.Pose.new()
	var h := hazard(id)
	Hazards.pose(h, t, pose)
	return pose.position.y - (h.pivot as Vector3).y + DOOR_H     # the door's rest pose is OPEN (the piece's `rise` is -DOOR_H)

func is_open(id: String, t: float) -> bool:
	return door_rise(id, t) > DOOR_H - 0.02

func is_shut(id: String, t: float) -> bool:
	return door_rise(id, t) < 0.02

## Every gate door (a `lift` with a part of tone "door") of the race levels 29-32 is solid and not `hit`: it never bonks (levels/level_world.gd door_nudge does the only pushing), and the
## world marks it as a gate door; the start gates (blink, slot gate) are not `hit` either.
func check_no_hit_doors() -> void:
	var doors := 0
	var bad: Array = []
	for number in [29, 30, 31, 32]:
		var level: Dictionary = world._levels[number - 1].data
		for h: Dictionary in level.hazards:
			var is_door := false
			if h.k == "lift":
				for part: Dictionary in h.parts:
					if str(part.tone) == "door": is_door = true
			if is_door:
				doors += 1
			if (is_door or str(h.get("slot", "")) == "gate") and h.hit: bad.append("%d %s" % [number, h.id])
	verdict(bad.is_empty() and doors > 0, "doors_not_hit", "%d gate doors in levels 29-32, hit ones: %s" % [doors, str(bad)])

## The schedule: a lift with a `hold` dwells `pause` at the bottom, `hold` at the top, and moves for (period - pause - hold) / 2 each way.
func check_schedule() -> void:
	var p := 6.0
	var pause := 1.5
	var hold := 3.5
	var ok := true
	var why := ""
	for t in [0.0, 0.7, 1.5, 1.75, 2.0, 5.0, 5.4, 5.75, 6.0, 6.0 + 0.7, 12.0 + 1.5]:
		var f := Hazards.cycle(t, p, pause, "sine", hold)
		var m := fposmod(t, p)
		var want := 0.0
		if m < pause: want = 0.0
		elif m < pause + 0.5: want = 0.5 - 0.5 * cos((m - pause) / 0.5 * PI)
		elif m < pause + 0.5 + hold: want = 1.0
		else: want = 0.5 - 0.5 * cos((1.0 - (m - pause - 0.5 - hold) / 0.5) * PI)
		if absf(f - want) > 1e-6:
			ok = false
			why += " t=%.2f got %.3f want %.3f;" % [t, f, want]
	verdict(ok, "cycle", "pause 1.5 / hold 3.5 / move 0.5 (period 6)%s" % why)
	# a lift without `hold` gets the plain curve (hold = pause)
	var old := Hazards.cycle(1.0, 8.0, 1.0, "sine")
	var same := Hazards.cycle(1.0, 8.0, 1.0, "sine", 1.0)
	verdict(absf(old - same) < 1e-9 and absf(Hazards.cycle(4.0, 8.0, 1.0, "sine") - Hazards.cycle(4.0, 8.0, 1.0, "sine", -1.0)) < 1e-9, "cycle_default", "hold missing = pause: old %.3f same %.3f" % [old, same])
	var open := door_rise("g1_2", 3.3)
	var shut := door_rise("g1_2", 1.0)
	verdict(absf(shut) < 0.01 and absf(open - DOOR_H) < 0.01, "lifted", "g1_2 shut at 1.0 s (%.2f up), lifted at 3.3 s (%.2f up)" % [shut, open])

## The patterns of the rows, read off the clock: which doors of a row are open (lifted all the way) and how they follow each other.
func check_patterns() -> void:
	var rows := {"g1": 3, "g2": 4, "g3": 4, "g4": 8, "g5": 5, "g6": 3}
	var periods := {"g1": 3.75, "g2": 3.5, "g3": 3.5, "g4": 3.5, "g5": 3.75, "g6": 3.0}
	var order := {}
	for name: String in rows:
		var seq: Array = []     # [clock, door] of every door's first fully open moment in one period
		var sets: Array = []
		var t := 0.0
		var last := ""
		while t < float(periods[name]) * 2.0:
			var open_now: Array = []
			for i in int(rows[name]):
				if is_open("%s_%d" % [name, i + 1], t): open_now.append(i + 1)
			var key := str(open_now)
			if key != last and not open_now.is_empty():
				sets.append(open_now)
			last = key
			t += 0.05
		order[name] = sets
	say("patterns: g1 %s" % str(order.g1))
	say("patterns: g2 %s" % str(order.g2))
	say("patterns: g3 %s" % str(order.g3))
	say("patterns: g4 %s" % str(order.g4))
	say("patterns: g5 %s" % str(order.g5))
	say("patterns: g6 %s" % str(order.g6))
	# first appearance of each door in the open sets, in order, over the first period
	var firsts := {}
	for name: String in rows:
		var seen: Array = []
		for set: Array in order[name]:
			for door: int in set:
				if not door in seen: seen.append(door)
		firsts[name] = seen
	verdict(firsts.g1 == [1, 3, 2] or firsts.g1 == [3, 2, 1] or firsts.g1 == [2, 1, 3], "row1", "doors open one after the other in a cycle 1 > 3 > 2 (seen %s)" % str(firsts.g1))
	var alt_ok := true
	for set: Array in order.g2:
		if not (set in [[1, 4], [2, 3], [1], [4], [2], [3], [1, 2, 3, 4]]) and not (set.size() <= 2): alt_ok = false
	verdict(alt_ok and ([1, 4] in order.g2) and ([2, 3] in order.g2), "row2", "1+4 then 2+3 (sets %s)" % str(order.g2))
	verdict(is_rotation(firsts.g3, [1, 2, 3, 4]), "row3", "a wave across 4 doors 1 2 3 4 (seen %s)" % str(firsts.g3))
	var left: Array = []
	var right: Array = []
	for door: int in firsts.g4:
		if door <= 4: left.append(door)
		else: right.append(door)
	verdict(is_rotation(left, [1, 2, 3, 4]) and is_rotation(right, [8, 7, 6, 5]) and ([1, 8] in order.g4), "row4", "left four 1 2 3 4, right four 8 7 6 5, mirrored (seen %s | %s)" % [str(left), str(right)])
	verdict([3] in order.g5 and [2, 4] in order.g5 and [1, 5] in order.g5, "row5", "3, then 2+4, then 1+5 (sets %s)" % str(order.g5))
	verdict(firsts.g6 == [1, 2, 3] or firsts.g6 == [2, 3, 1] or firsts.g6 == [3, 1, 2], "row6", "1 > 2 > 3 (seen %s)" % str(firsts.g6))

## A courier stands under the open door g1_2 (x 0, door plane f 25.0-25.5, open from clock 3.5 to 4.5, down by 5.0) while it comes down: it ends beside it or on the floor, never inside.
func stand_test(id: String, spot: Vector3, from: float, seconds: float) -> Dictionary:
	world.set_clock(from)
	await physics_frame
	var made := courier(spot)
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var worst_inside := 0.0
	var end_inside := 0.0
	var lowest := 100.0
	var highest := -100.0
	var h := hazard(id)
	var bonks := 0
	var max_speed := 0.0
	for step in int(seconds / DT):
		world.advance(DT)
		var effect: Dictionary = world.apply_effects(K, 0, body, motion)
		if str(effect.get("kind", "")) == "bonk": bonks += 1
		motion.step(body, {"move": Vector2.ZERO}, DT)
		await physics_frame
		max_speed = maxf(max_speed, Vector3(body.velocity.x, maxf(body.velocity.y, 0.0), body.velocity.z).length())
		var l := local(body)
		lowest = minf(lowest, l.y)
		highest = maxf(highest, l.y)
		# inside the door's box (its pose at the physics clock): the capsule's axis (centre line) inside it with 0.15 m of margin
		var pose := Hazards.Pose.new()
		Hazards.pose(h, world.clock, pose)
		var half: Vector3 = (h.parts[0].size as Vector3) * 0.5
		var centre: Vector3 = pose.position + (h.parts[0].xf as Transform3D).origin
		var dx := absf(l.x - centre.x) - half.x
		var dz := absf(l.z - centre.z) - half.z
		end_inside = 0.0
		if dx < 0.0 and dz < 0.0 and l.y < centre.y + half.y - 0.15 and l.y + 1.8 > centre.y - half.y + 0.15:
			worst_inside = maxf(worst_inside, -maxf(dx, dz))
			end_inside = -maxf(dx, dz)
		if trace == id and step % 6 == 0: say("  %s t=%.2f courier %s rise %.2f grounded %s" % [id, world.clock, l.snapped(Vector3.ONE * 0.01), door_rise(id, world.clock), motion.grounded])
	var moved := Vector2(local(body).x - spot.x, local(body).z - spot.z).length()
	var result := {"pos": local(body), "moved": moved, "speed": max_speed, "lowest": lowest, "highest": highest, "inside": end_inside, "worst": worst_inside, "bonks": bonks, "grounded": motion.grounded, "clock": world.clock}
	body.queue_free()
	await physics_frame
	return result

func check_stand_centre() -> void:
	var r: Dictionary = await stand_test("g1_2", Vector3(0.0, 0.0, -DOOR_F), 3.1, 3.0)
	var ok: bool = float(r.inside) < 0.05 and float(r.lowest) > -STANDING_SINK and bool(r.grounded) and int(r.bonks) == 0 and float(r.moved) <= NUDGE_MAX and float(r.speed) <= NO_LAUNCH
	verdict(ok, "stand_centre", "under the open door at 3.1 s, it comes down at 3.75: highest %.2f, lowest %.2f, inside at the end by %.2f (%.2f at worst), moved %.2f m, top speed %.2f m/s, bonks %d, ends at %s" % [r.highest, r.lowest, r.inside, r.worst, r.moved, r.speed, r.bonks, (r.pos as Vector3).snapped(Vector3.ONE * 0.01)])

func check_stand_edge() -> void:
	var cases := {"side": Vector3(3.9, 0.0, -DOOR_F), "half out, front": Vector3(0.0, 0.0, -DOOR_F + 0.45), "half out, back": Vector3(0.0, 0.0, -DOOR_F - 0.45), "corner": Vector3(4.1, 0.0, -DOOR_F + 0.4)}
	for name: String in cases:
		var r: Dictionary = await stand_test("g1_2", cases[name], 3.1, 3.0)
		var ok: bool = float(r.inside) < 0.05 and float(r.lowest) > -STANDING_SINK and bool(r.grounded) and int(r.bonks) == 0 and float(r.moved) <= NUDGE_MAX and float(r.speed) <= NO_LAUNCH
		verdict(ok, "stand_edge", "%s: highest %.2f, lowest %.2f, inside at the end by %.2f (%.2f at worst), moved %.2f m, top speed %.2f m/s, bonks %d, ends at %s" % [name, r.highest, r.lowest, r.inside, r.worst, r.moved, r.speed, r.bonks, (r.pos as Vector3).snapped(Vector3.ONE * 0.01)])

## Runs at 5 m/s down the hall from f = 20 through door g1_2 starting at clock `from`; returns {z (level-local, final), bonks, clock at the door}.
func run_test(id: String, x: float, from: float, jump_at_f := -1.0, seconds := 3.0) -> Dictionary:
	world.set_clock(from)
	await physics_frame
	var made := courier(Vector3(x, 0.0, -20.0))
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var bonks := 0
	var at_door := -1.0
	var jumped := false
	var back := 0.0     # the fastest the runner moved back from the door (towards +z) and the highest it rose in the air without a jump
	var rose := 0.0
	for step in int(seconds / DT):
		var f := -local(body).z
		var press := false
		if jump_at_f > 0.0 and not jumped and f >= jump_at_f and motion.grounded:
			press = true
			jumped = true
		world.advance(DT)
		var effect: Dictionary = world.apply_effects(K, 0, body, motion)
		if str(effect.get("kind", "")) == "bonk": bonks += 1
		motion.step(body, {"move": Vector2(0.0, -1.0), "jump": press}, DT)
		await physics_frame
		if at_door < 0.0 and -local(body).z >= DOOR_F: at_door = world.clock
		back = maxf(back, body.velocity.z)
		if jump_at_f < 0.0: rose = maxf(rose, local(body).y)
	var result := {"z": local(body).z, "bonks": bonks, "at_door": at_door, "y": local(body).y, "back": back, "rose": rose}
	body.queue_free()
	await physics_frame
	return result

func check_run_through() -> void:
	# the runner is at the door's face after ~1.1 s: start at clock 2.2 so the door is fully open (3.0 to 3.75) when it passes
	var r: Dictionary = await run_test("g1_2", 0.0, 2.2)
	verdict(-float(r.z) > ROW1 + 3.0 and int(r.bonks) == 0, "run_through", "ran through the open door g1_2: reached f %.1f, bonks %d, at the door at clock %.2f" % [-float(r.z), r.bonks, r.at_door])
	var j: Dictionary = await run_test("g1_2", 0.0, 2.2, DOOR_F - 2.0)
	verdict(-float(j.z) > ROW1 + 3.0 and int(j.bonks) == 0, "jump_through", "jumped into the open door g1_2 from 2 m: the head clears the lintel and the lifted door, reached f %.1f, bonks %d" % [-float(j.z), j.bonks])

func check_shut_door() -> void:
	# door g1_2 is shut from clock 0.5 to 2.5: a runner reaches its face (f 25.0) at ~1.1 s after the start
	var r: Dictionary = await run_test("g1_2", 0.0, 0.0, -1.0, 2.0)
	verdict(-float(r.z) < DOOR_F - 0.15 and float(r.y) < 0.2 and int(r.bonks) == 0 and float(r.back) <= NO_LAUNCH and float(r.rose) < 0.2, "shut_stops", "ran into the shut door g1_2: stopped at f %.2f (door face at %.2f), bonks %d, fastest backwards %.2f m/s, highest %.2f" % [-float(r.z), DOOR_F - 0.25, r.bonks, r.back, r.rose])
	var j: Dictionary = await run_test("g1_2", 0.0, 0.0, DOOR_F - 1.75, 2.0)
	verdict(-float(j.z) < DOOR_F - 0.15, "shut_jump", "jumping at the shut door (3.5 m high, a jump reaches 1.44): still in front at f %.2f" % -float(j.z))

## A runner that meets a door that is rising (g1_2 opens 2.5-3.0) or coming down (closes 3.75-4.25): it is stopped or passes (never a bonk, a launch or a throw back), never left inside the door.
func check_rising_door() -> void:
	var all_ok := true
	var text := ""
	for arrive in [2.5, 2.7, 2.9, 3.8, 4.0, 4.2]:
		var r: Dictionary = await run_test("g1_2", 0.0, float(arrive) - 1.1, -1.0, 2.0)
		var z := -float(r.z)
		var inside := absf(z - DOOR_F) < 0.25 and float(r.y) > -0.1
		text += " [%.1f: f %.2f y %.2f bonks %d back %.2f up %.2f]" % [arrive, z, r.y, r.bonks, r.back, r.rose]
		if inside or int(r.bonks) > 0 or float(r.back) > NO_LAUNCH or float(r.rose) > 0.2: all_ok = false
	verdict(all_ok, "rising", "running into a moving door:%s" % text)

func check_surface() -> void:
	var origin: Vector3 = world.level_origin(K)
	var on: Dictionary = world.surface_at(K, origin + Vector3(0.0, -DROP * 0.5 / 30.0 * 2.0, -(SLOPE_F0 + 2.0)))
	var plain: Dictionary = world.surface_at(K, origin + Vector3(0.0, 0.0, -60.0))
	var foot: Dictionary = world.surface_at(K, origin + Vector3(0.0, -DROP, -(SLOPE_F1 + 3.0)))
	var high: Dictionary = world.surface_at(K, origin + Vector3(0.0, 2.0, -(SLOPE_F0 + 2.0)))
	var ok: bool = on.get("slime", Vector2.ZERO) == Vector2(0.0, -1.0) and plain.is_empty() and foot.is_empty() and high.is_empty()
	verdict(ok, "surface_at", "slope %s, plain floor %s, foot %s, 2 m over the slope %s" % [on, plain, foot, high])

func slope_y(f: float) -> float:
	return -DROP * clampf((f - SLOPE_F0) / (SLOPE_F1 - SLOPE_F0), 0.0, 1.0)

## From rest at the top of the slope with no input.
func slide_run(seconds: float, jump := false, move := Vector2.ZERO) -> Dictionary:
	world.set_clock(0.0)
	await physics_frame
	var made := courier(Vector3(0.0, 0.05, -(SLOPE_F0 + 1.0)))
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var speeds: Array = []
	var peak := 0.0
	var x_end := 0.0
	var grounded_ticks := 0
	var t124 := -1.0     # when it passed f 124 (the foot of the slope is at 128, the row 6 doors stand just behind it)
	for step in int(seconds / DT):
		await tick(body, motion, move, jump and motion.grounded)
		if t124 < 0.0 and -local(body).z >= 124.0: t124 = (step + 1) * DT
		var planar := Vector2(body.velocity.x, body.velocity.z).length()
		speeds.append(planar)
		peak = maxf(peak, planar)
		if motion.grounded: grounded_ticks += 1
		if trace == "slide" and step % 12 == 0: say("  slide t=%.2f at %s vel %s grounded %s" % [step * DT, local(body).snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.01), motion.grounded])
	var result := {"pos": local(body), "speeds": speeds, "peak": peak, "grounded": grounded_ticks, "vel": body.velocity, "t124": t124}
	body.queue_free()
	await physics_frame
	return result

func check_slide() -> void:
	var r: Dictionary = await slide_run(4.0)
	var f := -(r.pos as Vector3).z
	var at1 := float(r.speeds[59])
	var at2 := float(r.speeds[119])
	var ok: bool = f > SLOPE_F0 + 12.0 and at2 > at1 + 1.0 and at2 > 5.5 and float(r.peak) <= Motion.SLIME_MAX + 0.25 and absf((r.pos as Vector3).x) < 0.5
	verdict(ok, "slide", "from rest at f %.0f with no input: after 1 s %.1f m/s, 2 s %.1f m/s, peak %.1f (cap %.0f), at f %.1f after 4 s, x %.2f" % [SLOPE_F0 + 1.0, at1, at2, r.peak, Motion.SLIME_MAX, f, (r.pos as Vector3).x])

func check_jump_speed() -> void:
	var plain: Dictionary = await slide_run(4.5, false, Vector2(0.0, -1.0))
	var hops: Dictionary = await slide_run(4.5, true, Vector2(0.0, -1.0))
	var ok: bool = float(hops.t124) > 0.0 and float(hops.t124) < float(plain.t124) - 0.15 and float(hops.peak) > float(plain.peak) + 0.3 and float(hops.peak) <= Motion.SLIME_AIR_MAX + 0.5 and float(plain.peak) <= Motion.SLIME_MAX + 0.25
	verdict(ok, "jump_speed", "running down the slope: sliding is at f 124 after %.2f s (peak %.1f m/s), hopping after %.2f s (peak %.1f m/s)" % [plain.t124, plain.peak, hops.t124, hops.peak])

## Steering on the slime: holding left moves the courier across the slope.
func check_steer() -> void:
	var r: Dictionary = await slide_run(2.0, false, Vector2(-1.0, 0.0))
	var x: float = (r.pos as Vector3).x
	verdict(x < -3.0, "steer", "holding left for 2 s on the slope: x %.2f (still pushed downhill: f %.1f)" % [x, -(r.pos as Vector3).z])

## True when `seen` is `want` started at any of its elements (the clock started in the middle of a cycle).
func is_rotation(seen: Array, want: Array) -> bool:
	if seen.size() != want.size(): return false
	for shift in want.size():
		var rotated: Array = want.slice(shift) + want.slice(0, shift)
		if rotated == seen: return true
	return false
