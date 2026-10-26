extends SceneTree
## Headless check of the stage rounds' camera, movement feel and couriers touching couriers, on the real stage levels (the square and the hex stack,
## level_25 and level_26) with the real tile colliders, the real courier motion (courier/courier_motion.gd, stage feel), the real contact
## (players/player_contact.gd) and the real follow camera (game/follow_camera.gd, stage view):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --path demo \
##     -s $PWD/tools/stage_feel_check.gd
## Per level: the run speed (12.6 m/s) and how fast it is reached and lost, the jump (apex 3.15 m, 0.54 s of air, no bounce on landing), a fall onto the next layer (a hole in the
## top layer), running along the tile seams and diagonally over them (no catching: always grounded, never slowed, never off the floor height; on the strip behind the raised
## pads), two couriers walking into each other (blocked, the one walked into shoved and staggered, nobody tunnels, a pile of five settles), the same against a replica body
## (placed by pose like the other players on an online client), a pressed dash ignored (the stage has no dash), a bump off the arena's edge, other rounds
## unchanged (the courier stays a ghost without the stage feel). Then the camera: the courier's share of the frame and its feet's screen spot (x 0.50, y 0.704) at the default view in
## 1280 x 720 and 844 x 390, over the whole pitch range and all around, after a fall to the next layer (back at its spot within a second, smoothly), frozen in a jump, the pitch
## 12.4 degrees standing and 16 to 24 at the run, and the camera never inside a tile slab that the view draws. Then the race levels' air follow (`camera_air_follow`: a goal-tower throw, a normal jump, a 6 m fall: the courier stays in the middle 70 % of the frame, no overshoot). Prints STAGE_FEEL lines and STAGE_FEEL ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const Motion := preload("res://courier/courier_motion.gd")
const TOP := 1 ## the "top layer" of these tests is the first full floor; floor 0 of the file is the start layer (12 groups of 3 x 3 tiles) one gap over it
const PlayerContact := preload("res://players/player_contact.gd")
const FollowCamera := preload("res://game/follow_camera.gd")

const LEVELS := [24, 25] ## 0-based: level_25.json (square stack) and level_26.json (hex stack)
const DT := 1.0 / 60.0
const SOLID := 1 | 16
const WALK := Motion.STAGE_FEEL.walk
const ACCEL_TIME_MAX := 0.35 ## s to 95 % of the run speed (target: at most about 0.4 s)
const STOP_TIME_MAX := 0.3 ## s from the run to a stop
const AIR_TIME := 0.54 ## s of a full jump (16 frames at 30 fps)
const SEAM_SPEED_SHARE := 0.97 ## the slowest tick of a run along the seams, share of the run speed
const FLOOR_TOLERANCE := 0.01 ## m: a courier on the floor stands this near the top of the tile
const SHARE_RANGE := Vector2(0.105, 0.135) ## the courier's share of the frame height at the default camera (target 12.2 % with the ears)
const FEET_Y_RANGE := Vector2(0.69, 0.72) ## the courier's feet in the frame's height (target 0.704)
const SCREEN_X_RANGE := Vector2(0.49, 0.51)
const PHONE_SHARE_RANGE := Vector2(0.12, 0.17)
const CAPSULE_HEIGHT := 1.8

var failures := 0
var holder: Node3D
var world: Node3D
var levels: Node3D
var level := 0
var shift := Vector3.ZERO ## added to the level's origin: where on the arena the section under test stands
const HEX_RUN := 12.0 ## m: a hex run goes this far either side of its middle

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_FEEL ", "ok   " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("STAGE_FEEL FAIL timed out")
		print("STAGE_FEEL ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	levels = LevelWorld.new()
	holder.add_child(levels)
	await levels.build("authority")
	for k: int in LEVELS:
		level = k
		levels.set_active_level(k)
		levels.set_clock(0.0)
		await frames(2)
		var data: Dictionary = levels._levels[k].data.tiles
		print("STAGE_FEEL --- level %d %s (%s tiles, pitch %.2f m)" % [k + 1, levels.title(k), data.grid, float(data.pitch)])
		shift = Vector3.ZERO
		await movement()
		await seams()
		var spot := find_spot(8.0)
		check(spot != Vector2.INF, "a plain disc of 8 m for the collisions exists on the top layer")
		shift = Vector3(spot.x, 0.0, spot.y) if spot != Vector2.INF else Vector3.ZERO
		await collisions()
		shift = Vector3.ZERO
		await camera_frames()
	feel_summary()
	print("STAGE_FEEL ok=", failures == 0)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------ helpers

func origin() -> Vector3:
	return levels.level_origin(level) + shift

## True when (x, z) (level-local) is on the top layer and every tile within `reach` of it is a plain top-layer tile: no raised pad, no hole in the outline.
func plain_at(p: Vector2, reach: float) -> bool:
	var steps: Object = levels._levels[level].tiles
	var floor_y := float(steps.data.floors[TOP].y)
	var feet := Vector3(p.x, floor_y + 0.02, p.y)
	if (steps.tiles_at(feet, 0.0) as Array).is_empty(): return false
	for index: int in steps.tiles_at(feet, reach):
		var tile: Dictionary = steps.data.tiles[index]
		if int(tile.floor) != TOP or float(tile.p.y) > floor_y + 0.001: return false
	return true

## The centres of the plain top-layer tiles, the nearest to the arena's middle first.
func plain_centres() -> Array:
	var steps: Object = levels._levels[level].tiles
	var floor_y := float(steps.data.floors[TOP].y)
	var list: Array = []
	for tile: Dictionary in steps.data.tiles:
		if int(tile.floor) == TOP and float(tile.p.y) <= floor_y + 0.001: list.append(Vector2(tile.p.x, tile.p.z))
	list.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	return list

## The middle of a straight stretch of plain top layer: `half` m either side of it along `direction` (from the plain tile centre plus `offset`, the one nearest the arena's middle that has one);
## Vector2.INF when the layout has none. A stretch is plain when a courier's width (1 m) either side of it stands on plain tiles only.
func find_run(offset: Vector2, direction: Vector2, half: float) -> Vector2:
	for centre: Vector2 in plain_centres():
		var middle := centre + offset
		var clear := true
		var steps := int(ceil(half * 2.0 / 0.75))
		for i in steps + 1:
			if not plain_at(middle + direction * (-half + half * 2.0 * float(i) / float(steps)), 1.0):
				clear = false
				break
		if clear: return middle
	return Vector2.INF

## The middle of a disc of plain top layer `radius` m across (its ring and its middle on plain tiles only).
func find_spot(radius: float) -> Vector2:
	for centre: Vector2 in plain_centres():
		var clear := plain_at(centre, 1.0)
		for i in 12:
			if not clear: break
			var turn := Vector2.RIGHT.rotated(TAU * float(i) / 12.0)
			clear = plain_at(centre + turn * radius, 1.0) and plain_at(centre + turn * radius * 0.5, 1.0)
		if clear: return centre
	return Vector2.INF

func top_y(floor_index := 0) -> float:
	return origin().y + float(levels._levels[level].data.tiles.floors[floor_index + TOP].y)

## A courier body with its motion in the stage feel, standing on the top layer at level-local (x, z) facing `yaw`.
func courier(x: float, z: float, stage := true, yaw := 0.0, solid := true) -> Dictionary:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.set_stage(stage)
	motion.set_floors(levels.tile_floors(level) if stage else PackedFloat32Array()) # the one-way floors under the feet (game_run.gd does this every tick)
	motion.reset(body, origin() + Vector3(x, top_y(0) - origin().y + 0.02, z), yaw)
	body.collision_layer = Motion.LAYER_COURIER if solid else 0
	await frames(1) # the physics server takes the body and its place at the next frame
	return {"body": body, "motion": motion}

func drop(courier_: Dictionary) -> void:
	var body := courier_.body as Node
	body.get_parent().remove_child(body)
	body.free()

func tick(c: Dictionary, move: Vector2, jump := false, dash := false) -> Dictionary:
	return (c.motion as RefCounted).step(c.body, {"move": move, "jump": jump, "dash": dash}, DT)

func planar_speed(c: Dictionary) -> float:
	var v: Vector3 = (c.body as CharacterBody3D).velocity
	return Vector2(v.x, v.z).length()

func settle(c: Dictionary, ticks := 20) -> void:
	for i in ticks: tick(c, Vector2.ZERO)

# ------------------------------------------------------------------ run, jump, fall

var summary := {}

func movement() -> void:
	var spot := find_run(Vector2.ZERO, Vector2(1.0, 0.0), 26.0) # a plain stretch of the top layer to run and jump on
	shift = Vector3(spot.x, 0.0, spot.y)
	var c := await courier(-20.0, 0.0)
	settle(c)
	var body: CharacterBody3D = c.body
	check(c.motion.grounded, "stands on the top layer (%.3f m, floor %.3f)" % [body.global_position.y, top_y()])
	# run
	var reached := -1.0
	var worst_height := 0.0
	var t := 0.0
	for i in 120:
		tick(c, Vector2(1.0, 0.0))
		t += DT
		if reached < 0.0 and planar_speed(c) >= WALK * 0.95: reached = t
		worst_height = maxf(worst_height, absf(body.global_position.y - top_y()))
	var speed := planar_speed(c)
	summary["walk"] = speed
	summary["accel_time"] = reached
	check(absf(speed - WALK) < 0.05, "run speed %.2f m/s (preset %.2f)" % [speed, WALK])
	check(reached > 0.0 and reached <= ACCEL_TIME_MAX, "95 %% of the run speed after %.2f s (at most %.2f)" % [reached, ACCEL_TIME_MAX])
	check(worst_height < FLOOR_TOLERANCE, "running keeps the floor height (worst %.4f m)" % worst_height)
	# stop
	var stopped := -1.0
	var distance := 0.0
	var at := body.global_position
	t = 0.0
	for i in 60:
		tick(c, Vector2.ZERO)
		t += DT
		if stopped < 0.0 and planar_speed(c) < 0.05:
			stopped = t
			distance = at.distance_to(body.global_position)
	summary["stop_time"] = stopped
	check(stopped > 0.0 and stopped <= STOP_TIME_MAX, "stops %.2f s and %.2f m after letting go (at most %.2f s)" % [stopped, distance, STOP_TIME_MAX])
	# jump
	settle(c)
	var floor_y := body.global_position.y
	var apex := 0.0
	var air := 0.0
	var jumped := false
	var landed_at := -1
	var after_landing_vy := 0.0
	var bounced := false
	for i in 120:
		var events := tick(c, Vector2.ZERO, i == 0)
		if events.jumped: jumped = true
		apex = maxf(apex, body.global_position.y - floor_y)
		if jumped and not c.motion.grounded and landed_at < 0: air += DT
		if events.landed and landed_at < 0:
			landed_at = i
			after_landing_vy = body.velocity.y
		elif landed_at >= 0 and (not c.motion.grounded or body.global_position.y - floor_y > 0.01): bounced = true
	summary["apex"] = apex
	summary["air"] = air
	var expected_apex: float = pow(float(Motion.STAGE_FEEL.jump), 2.0) / (2.0 * float(Motion.STAGE_FEEL.gravity))
	check(jumped and absf(apex - expected_apex) < expected_apex * 0.08 + 0.1, "jump apex %.2f m (ballistic %.2f), air time %.2f s" % [apex, expected_apex, air])
	check(absf(air - AIR_TIME) <= 0.04, "a full jump is %.2f s in the air (target %.2f s)" % [air, AIR_TIME])
	check(landed_at > 0 and not bounced and absf(after_landing_vy) < 0.001, "lands cleanly: no bounce, no hover after the landing")
	# air control: a jump with the stick held sideways turns the flight a little but not like on the ground
	drop(c)
	shift = Vector3.ZERO
	# fall onto the next layer: a hole in the top layer around (0, 8)
	var count: int = levels.tile_count(level)
	var steps := PackedByteArray()
	steps.resize(count)
	var data: Dictionary = levels._levels[level].data.tiles
	for index in count:
		var p: Vector3 = data.tiles[index].p
		if int(data.tiles[index].floor) == TOP and Vector2(p.x, p.z - 8.0).length() < 7.0: steps[index] = StepTiles.PRE_GONE
	levels.set_tile_steps(level, steps)
	await frames(3)
	var f := await courier(0.0, 8.0)
	var fb: CharacterBody3D = f.body
	var fall_time := 0.0
	var landed_layer := false
	var bounce_after := false
	var land_y := top_y(1)
	for i in 180:
		var events := tick(f, Vector2.ZERO)
		if not f.motion.grounded and not landed_layer: fall_time += DT
		if events.landed:
			landed_layer = true
			land_y = fb.global_position.y
		elif landed_layer and (not f.motion.grounded or absf(fb.global_position.y - land_y) > 0.01): bounce_after = true
	check(landed_layer and absf(land_y - top_y(1)) < FLOOR_TOLERANCE, "falls through the hole onto the next layer (%.3f m, floor %.3f) after %.2f s" % [land_y, top_y(1), fall_time])
	check(not bounce_after, "the landing on the lower layer is clean (no bounce, no sliding off)")
	summary["fall_time"] = fall_time
	drop(f)
	var whole := PackedByteArray()
	whole.resize(count)
	levels.set_tile_steps(level, whole)
	await frames(3)

# ------------------------------------------------------------------ the tile seams

## A run from `from` to `to` (level-local, on the top layer): grounded every tick after the first, never slower than the share of the run speed, never off the floor.
func run_line(label: String, from: Vector2, to: Vector2) -> void:
	var c := await courier(from.x, from.y, true)
	settle(c)
	var body: CharacterBody3D = c.body
	var direction := (to - from).normalized()
	var move := direction
	var ungrounded := 0
	var worst_height := 0.0
	var slowest := INF
	var ticks := int(from.distance_to(to) / (WALK * DT))
	for i in ticks:
		tick(c, move)
		if i > 20: slowest = minf(slowest, planar_speed(c))
		if not c.motion.grounded: ungrounded += 1
		worst_height = maxf(worst_height, absf(body.global_position.y - top_y()))
	var arrived := Vector2(body.global_position.x - origin().x, body.global_position.z - origin().z).distance_to(to)
	check(ungrounded == 0 and worst_height < FLOOR_TOLERANCE and slowest >= WALK * SEAM_SPEED_SHARE and arrived < WALK * 0.3,
		"%s: grounded every tick (%d off), slowest %.2f m/s, height off by %.4f m, %.2f m from the end" % [label, ungrounded, slowest, worst_height, arrived])
	drop(c)

func seams() -> void:
	var data: Dictionary = levels._levels[level].data.tiles
	var pitch := float(data.pitch)
	if str(data.grid) == "square":
		var half := pitch * 0.5 # the seams of the square grid lie half a pitch from the tile centres
		await run_found("along a seam (x = tile edge)", Vector2(half, 0.0), Vector2(0.0, 1.0), 8.0)
		await run_found("along a seam (z = tile edge)", Vector2(0.0, half), Vector2(1.0, 0.0), 16.0)
		await run_found("diagonal over the corners", Vector2(half, half), Vector2(1.0, 1.0).normalized(), 11.0)
		await run_found("diagonal the other way", Vector2(half, half), Vector2(1.0, -1.0).normalized(), 11.0)
		await run_found("a shallow angle over the seams", Vector2.ZERO, Vector2(40.0, 10.0).normalized(), 20.0)
	else:
		for degrees in [0, 30, 60, 90, 120, 150, 17, 73]:
			var a := deg_to_rad(float(degrees))
			await run_found("hex run at %d degrees" % degrees, Vector2.ZERO, Vector2(cos(a), sin(a)), HEX_RUN)
		# along a row of flats: the seam between two rows of hexagons (pointy-top rows are pitch * sqrt(3) / 2 apart)
		await run_found("along the seam between two hex rows", Vector2(0.0, pitch * sqrt(3.0) * 0.25), Vector2(1.0, 0.0), HEX_RUN)

## A run of `half` m either side of a plain stretch of the top layer found by find_run (no pad, no hole in the outline).
func run_found(label: String, offset: Vector2, direction: Vector2, half: float) -> void:
	var middle := find_run(offset, direction, half)
	if middle == Vector2.INF:
		check(false, "%s: no plain stretch of %.0f m + %.0f m on the top layer" % [label, half, half])
		return
	shift = Vector3.ZERO
	await run_line(label, middle - direction * half, middle + direction * half)

# ------------------------------------------------------------------ couriers touching couriers

## Runs the local-role contact loop for the given couriers one tick (team_play.gd step_contact / push / steer): contact first, then each courier's step.
func contact_tick(contact: PlayerContact, group: Array, moves: Array, simulate: Array, dash := false) -> Array:
	var events := []
	var states := []
	for c: Dictionary in group:
		var body: CharacterBody3D = c.body
		states.append({"position": body.global_position + Vector3(0.0, 0.9, 0.0), "velocity": body.velocity})
	var results: Array = contact.step(DT, states).results
	for index in group.size():
		var c: Dictionary = group[index]
		var body: CharacterBody3D = c.body
		var result: Dictionary = results[index]
		if not simulate[index]: continue # a replica body: placed by its owner's pose
		if result.separate != Vector3.ZERO: body.move_and_collide(result.separate)
		if result.impulse != Vector3.ZERO: c.motion.launch(result.impulse, false, false)
		var move: Vector2 = moves[index]
		if float(result.stagger) > 0.0:
			c.motion.set_surface({"ice": true})
			move *= 0.35
		else: c.motion.set_surface({})
		events.append(tick(c, move, false, dash and index == 0))
	return events

func gap(a: Dictionary, b: Dictionary) -> float:
	var d: Vector3 = (a.body as Node3D).global_position - (b.body as Node3D).global_position
	return Vector2(d.x, d.z).length()

func collisions() -> void:
	# 1. A runs into B who stands still: blocked, B shoved along and staggered, never inside each other.
	var contact := PlayerContact.new(2)
	contact.stage = true
	var a := await courier(-4.0, 0.0, true, -PI * 0.5)
	var b := await courier(0.0, 0.0, true, 0.0)
	var group := [a, b]
	var min_gap := 9.0
	var b_moved := 0.0
	var staggered := false
	var runner_staggered := false
	var passed := false
	for i in 150:
		contact_tick(contact, group, [Vector2(1.0, 0.0), Vector2.ZERO], [true, true])
		min_gap = minf(min_gap, gap(a, b))
		if (b.body as Node3D).global_position.x - origin().x - 0.0 > 0.0: b_moved = maxf(b_moved, (b.body as Node3D).global_position.x - origin().x)
		if (a.body as Node3D).global_position.x > (b.body as Node3D).global_position.x + 0.1: passed = true
		if contact.snapshot()[3] > 0.0: staggered = true
		if contact.snapshot()[1] > 0.0: runner_staggered = true
	check(min_gap > 0.65 and not passed, "walking into a standing courier is blocked (closest %.2f m, capsules 0.70 m; never passed)" % min_gap)
	check(b_moved > 1.0 and staggered, "the one walked into is shoved %.1f m along and staggered" % b_moved)
	check(not runner_staggered, "the one who ran into them keeps its feet (only the one walked into staggers)")
	drop(a)
	drop(b)
	# 2. head on, equal speed: neither tunnels, both are thrown back a little.
	contact = PlayerContact.new(2)
	contact.stage = true
	a = await courier(-3.0, 0.0, true, -PI * 0.5)
	b = await courier(3.0, 0.0, true, PI * 0.5)
	group = [a, b]
	min_gap = 9.0
	var crossed := false
	for i in 150:
		contact_tick(contact, group, [Vector2(1.0, 0.0), Vector2(-1.0, 0.0)], [true, true])
		min_gap = minf(min_gap, gap(a, b))
		if (a.body as Node3D).global_position.x > (b.body as Node3D).global_position.x + 0.1: crossed = true
	check(min_gap > 0.65 and not crossed, "head on, equal speed: nobody tunnels (closest %.2f m)" % min_gap)
	drop(a)
	drop(b)
	# 3. a replica body (placed by pose, not simulated): the local courier cannot walk through it, and is not hurt by pushing against it.
	contact = PlayerContact.new(2)
	contact.stage = true
	a = await courier(-4.0, 0.0, true, -PI * 0.5)
	b = await courier(0.0, 0.0, false, 0.0)
	(b.body as CharacterBody3D).collision_layer = Motion.LAYER_COURIER
	group = [a, b]
	min_gap = 9.0
	passed = false
	var jitter := 0.0
	var last := (a.body as Node3D).global_position
	for i in 180:
		contact_tick(contact, group, [Vector2(1.0, 0.0), Vector2.ZERO], [true, false])
		min_gap = minf(min_gap, gap(a, b))
		if (a.body as Node3D).global_position.x > (b.body as Node3D).global_position.x + 0.1: passed = true
		if i > 120: jitter = maxf(jitter, ((a.body as Node3D).global_position - last).length())
		last = (a.body as Node3D).global_position
	check(min_gap > 0.65 and not passed, "against a replica body: blocked (closest %.2f m)" % min_gap)
	check(jitter < 0.09, "pressing against it does not jitter (largest step %.3f m per tick, walking is %.3f)" % [jitter, WALK * DT])
	drop(a)
	drop(b)
	# 4. the stage has no dash: a pressed dash is ignored (no lunge, no belly flop, no bonk), the run stays at its speed.
	contact = PlayerContact.new(2)
	contact.stage = true
	a = await courier(-2.6, 0.0, true, -PI * 0.5)
	b = await courier(0.0, 0.0, true, 0.0)
	group = [a, b]
	var dashed := false
	var bonked := false
	var fastest := 0.0
	for i in 60:
		for events: Dictionary in contact_tick(contact, group, [Vector2(1.0, 0.0), Vector2.ZERO], [true, true], true):
			if events.dashed or events.flopped: dashed = true
			if events.wall_stun: bonked = true
		fastest = maxf(fastest, planar_speed(a))
	check(not dashed and not bonked and fastest <= WALK + 0.05 and a.motion.dash_left <= 0.0 and a.motion.flop_left <= 0.0, "a pressed dash is ignored in a stage round: no lunge, no flop, no bonk (fastest %.2f m/s, the run is %.2f)" % [fastest, WALK])
	drop(a)
	drop(b)
	# 5. a pile: four couriers run at a fifth from all sides; it settles (no overlap, no jitter).
	contact = PlayerContact.new(5)
	contact.stage = true
	group = [await courier(0.0, 0.0, true)]
	var moves := [Vector2.ZERO]
	for index in 4:
		var angle := TAU * index / 4.0
		group.append(await courier(cos(angle) * 3.0, sin(angle) * 3.0, true, angle))
		moves.append(Vector2(-cos(angle), -sin(angle)))
	var simulate := [true, true, true, true, true]
	var worst_overlap := 0.0
	var late_motion := 0.0
	var lasts := []
	for c: Dictionary in group: lasts.append((c.body as Node3D).global_position)
	for i in 240:
		contact_tick(contact, group, moves, simulate)
		for x in 5:
			for y in range(x + 1, 5): if i > 60: worst_overlap = maxf(worst_overlap, 0.7 - gap(group[x], group[y]))
		if i > 180:
			for x in 5:
				late_motion = maxf(late_motion, ((group[x].body as Node3D).global_position - lasts[x]).length())
		for x in 5: lasts[x] = (group[x].body as Node3D).global_position
	check(worst_overlap < 0.05, "a pile of five settles without overlapping (worst %.3f m)" % worst_overlap)
	check(late_motion < 0.09, "and without jitter once it has settled (largest step %.3f m per tick)" % late_motion)
	for c: Dictionary in group: drop(c)
	# 6. the edge: B stands near the arena's edge, A runs into B, B goes over.
	contact = PlayerContact.new(2)
	contact.stage = true
	shift = Vector3.ZERO # the rim is level-local
	var tile_data: Dictionary = levels._levels[level].data.tiles
	var rim := 0.0 # the top floor's edge along +x through the middle
	for tile: Dictionary in tile_data.tiles:
		if int(tile.floor) == TOP and absf((tile.p as Vector3).z) <= float(tile_data.pitch) * 0.5 + 0.01: rim = maxf(rim, (tile.p as Vector3).x + float(tile_data.pitch) * 0.5)
	a = await courier(0.0, 0.0, true)
	b = await courier(0.0, 0.0, true)
	(a.body as Node3D).global_position = origin() + Vector3(rim - 9.0, top_y() - origin().y + 0.02, 0.0)
	(b.body as Node3D).global_position = origin() + Vector3(rim - 1.2, top_y() - origin().y + 0.02, 0.0)
	(a.body as Node3D).rotation.y = -PI * 0.5
	a.motion.yaw = -PI * 0.5
	await frames(1)
	group = [a, b]
	var dropped := false
	for i in 300:
		contact_tick(contact, group, [Vector2(1.0, 0.0), Vector2.ZERO], [true, true])
		if (b.body as Node3D).global_position.y < top_y() - 1.0: dropped = true
	check(dropped, "a courier at the arena's edge can be bumped off it (it left the top layer, y %.1f)" % ((b.body as Node3D).global_position.y - origin().y))
	drop(a)
	drop(b)
	# 7. other rounds unchanged: without the stage feel the capsules are no obstacle for each other and the walk is the plain one.
	a = await courier(-3.0, 0.0, false, -PI * 0.5)
	b = await courier(0.0, 0.0, false, 0.0)
	var through := false
	for i in 120:
		tick(a, Vector2(1.0, 0.0))
		tick(b, Vector2.ZERO)
		if (a.body as Node3D).global_position.x > (b.body as Node3D).global_position.x + 0.5: through = true
	check(through and absf(planar_speed(a) - Motion.WALK_SPEED) < 0.05 and (a.body as CollisionObject3D).collision_mask & Motion.LAYER_COURIER == 0, "without the stage feel: the plain walk speed %.2f m/s and no collision between couriers" % planar_speed(a))
	drop(a)
	drop(b)

# ------------------------------------------------------------------ the camera

## The stage camera in a viewport of `size`, following feet at `feet` (world), yaw / pitch; settled. Returns {"share", "x", "y", "camera"}.
func frame(size: Vector2i, feet: Vector3, yaw: float, pitch: float, settle_ticks := 90) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	holder.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var view := FollowCamera.new()
	view.configure(camera)
	view.set_first_person(false)
	view.set_shoulder_view(true)
	view.set_stage_view(true)
	view.reset_lag()
	for i in settle_ticks: view.update(DT, feet + Vector3(0.0, 1.0, 0.0), yaw, pitch)
	var result := project(camera, feet)
	result["camera"] = camera.global_position
	result["fov"] = camera.fov
	holder.remove_child(viewport)
	viewport.free()
	return result

## The capsule's top, bottom and centre in the frame (0..1 from the top left of the viewport).
func project(camera: Camera3D, feet: Vector3) -> Dictionary:
	var size := camera.get_viewport().get_visible_rect().size
	var top := camera.unproject_position(feet + Vector3(0.0, CAPSULE_HEIGHT, 0.0)) / size
	var bottom := camera.unproject_position(feet) / size
	var centre := camera.unproject_position(feet + Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)) / size
	return {"share": bottom.y - top.y, "x": centre.x, "y": centre.y, "feet": bottom.y}

func camera_frames() -> void:
	var start: Dictionary = levels.team_start(level, 1)
	var feet: Vector3 = start.spot
	var yaw: float = start.yaw
	var pitch := deg_to_rad(FollowCamera.STAGE_PITCH_DEFAULT)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		var f := frame(size, feet, yaw, pitch)
		var range_share: Vector2 = SHARE_RANGE if size.y > 500 else PHONE_SHARE_RANGE
		summary["share_%d" % size.x] = f.share
		check(f.share >= range_share.x and f.share <= range_share.y, "%dx%d default view: the courier is %.1f %% of the frame height (%.0f px), at x %.3f, y %.3f, camera %.1f m up %.1f m back, fov %.0f" % [
			size.x, size.y, f.share * 100.0, f.share * size.y, f.x, f.y, f.camera.y - feet.y, Vector2(f.camera.x - feet.x, f.camera.z - feet.z).length(), f.fov])
		check(f.x >= SCREEN_X_RANGE.x and f.x <= SCREEN_X_RANGE.y and f.feet >= FEET_Y_RANGE.x and f.feet <= FEET_Y_RANGE.y, "%dx%d: the feet stand at x %.3f, y %.3f of the frame (target 0.49-0.50, 0.704)" % [size.x, size.y, f.x, f.feet])
	# the whole pitch range and all around (yaw is free over the full circle): the courier stays at its spot, about the same size
	var worst_y := 0.0
	var worst_x := 0.0
	var smallest := 1.0
	var largest := 0.0
	for pitch_degrees in [FollowCamera.STAGE_PITCH_LOW, -55.0, -40.0, FollowCamera.STAGE_PITCH_DEFAULT, FollowCamera.STAGE_PITCH_HIGH]:
		for turn in 8:
			var f := frame(Vector2i(1280, 720), feet, yaw + TAU * turn / 8.0, deg_to_rad(float(pitch_degrees)), 4)
			worst_y = maxf(worst_y, absf(f.feet - FollowCamera.STAGE_FEET_Y))
			worst_x = maxf(worst_x, absf(f.x - 0.5))
			if pitch_degrees >= -40.0: # looking more steeply down the vertical capsule is seen end on: it shrinks, whatever the camera
				smallest = minf(smallest, f.share)
				largest = maxf(largest, f.share)
	check(worst_y < 0.01 and worst_x < 0.01, "pitch %d..%d and yaw all around: the courier stays at its spot (off by %.4f / %.4f of the frame)" % [FollowCamera.STAGE_PITCH_LOW, FollowCamera.STAGE_PITCH_HIGH, worst_x, worst_y])
	check(smallest >= 0.07 and largest <= 0.15, "pitch -40..%d: it is %.1f..%.1f %% of the frame height" % [FollowCamera.STAGE_PITCH_HIGH, smallest * 100.0, largest * 100.0])
	await camera_fall(feet, yaw, pitch)
	await camera_slabs(feet, yaw)
	camera_air_follow(feet, yaw, pitch)

## A fall to the next layer, the courier's heights from real physics on the level: the courier's screen spot per tick; it must be back within 0.02 of its spot a second after landing,
## move one way only (no overshoot, no shake) and the height lag must not let it leave the frame.
func camera_fall(feet: Vector3, yaw: float, pitch: float) -> void:
	var count: int = levels.tile_count(level)
	var steps := PackedByteArray()
	steps.resize(count)
	var data: Dictionary = levels._levels[level].data.tiles
	for index in count:
		var p: Vector3 = data.tiles[index].p
		if int(data.tiles[index].floor) == TOP and Vector2(p.x, p.z).length() < 6.0: steps[index] = StepTiles.PRE_GONE
	levels.set_tile_steps(level, steps)
	await frames(3)
	var c := await courier(0.0, 0.0, true)
	var body: CharacterBody3D = c.body
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	holder.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var view := FollowCamera.new()
	view.configure(camera)
	view.set_first_person(false)
	view.set_stage_view(true)
	body.global_position = feet + Vector3(0.0, 0.0, 0.0)
	view.reset_lag()
	for i in 30: view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch)
	var path := []
	var pitch_path := []
	var landed_tick := -1
	for i in 210: # the fall is 0.57 s (a layer gap of 14.3 m), the landing swing holds a second and eases out in 0.5 s
		var events := tick(c, Vector2.ZERO)
		view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": c.motion.grounded})
		path.append(project(camera, body.global_position).y)
		pitch_path.append(-rad_to_deg(camera.global_rotation.x))
		if events.landed and landed_tick < 0: landed_tick = i
	var worst := 0.0
	for y: float in path: worst = maxf(worst, y - FollowCamera.STAGE_FEET_Y)
	var back := -1
	for i in range(landed_tick, path.size()):
		if absf(float(path[i]) - FollowCamera.STAGE_FEET_Y) < 0.02:
			back = i - landed_tick
			break
	var reversals := 0
	var direction := 0
	for i in range(landed_tick, path.size() - 1):
		var d: float = path[i + 1] - path[i]
		if absf(d) < 1.0e-5: continue
		var now := 1 if d > 0.0 else -1
		if direction != 0 and now != direction: reversals += 1
		direction = now
	var peak_pos := 0.0
	for y: float in path: peak_pos = maxf(peak_pos, y)
	var land_pitch_max := 0.0
	for pitch_after: float in pitch_path: land_pitch_max = maxf(land_pitch_max, pitch_after)
	var land_pitch_end: float = pitch_path[-1]
	summary["land_pitch"] = land_pitch_max
	check(absf(land_pitch_max - (12.4 + FollowCamera.STAGE_LAND_PITCH)) < 0.4 and absf(land_pitch_end - 12.4) < 0.3, "after a landing a floor lower the view tips to %.1f degrees (standing %.1f + %.1f) and is back at %.1f degrees within the clip (target: one second, 24 at the run)" % [land_pitch_max, 12.4, FollowCamera.STAGE_LAND_PITCH, land_pitch_end])
	summary["fall_back"] = back * DT
	check(landed_tick > 0 and worst < 0.3 and peak_pos < 0.95, "a fall to the next layer: the courier drops at most %.3f of the frame below its spot (the view lags)" % worst)
	check(back >= 0 and back * DT <= 1.0, "and is back at its screen spot %.2f s after landing (at most 1.0 s)" % (back * DT))
	check(reversals <= 1, "the follow is smooth: the courier's screen height changes direction %d time(s) after the landing (no overshoot, no shake)" % reversals)
	drop(c)
	holder.remove_child(viewport)
	viewport.free()
	var whole := PackedByteArray()
	whole.resize(count)
	levels.set_tile_steps(level, whole)
	await frames(3)
	await camera_motion(feet, yaw, pitch)

## The camera while the courier jumps and runs on the top layer (real motion): a jump moves the courier in the frame, not the picture; at the run speed the courier
## stays near the middle of the frame (the follow is close to rigid) and is never cut off.
func camera_motion(feet: Vector3, yaw: float, pitch: float) -> void:
	var spot := find_run(Vector2.ZERO, Vector2(0.0, 1.0), 14.0) # a plain stretch of the top layer with room to run away from the camera (it runs towards -z from its far end)
	var c := await courier(spot.x, spot.y + 13.0, true)
	var body: CharacterBody3D = c.body
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	holder.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var view := FollowCamera.new()
	view.configure(camera)
	view.set_first_person(false)
	view.set_stage_view(true)
	settle(c)
	view.reset_lag()
	var follow := func(grounded: bool) -> void: view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": grounded, "run": planar_speed(c) / WALK})
	for i in 10: follow.call(true)
	var rest_y := camera.global_position.y
	var idle_pitch := -rad_to_deg(camera.global_rotation.x)
	var highest := 1.0
	var camera_rise := 0.0
	for i in 80:
		tick(c, Vector2.ZERO, i == 0)
		follow.call(c.motion.grounded)
		highest = minf(highest, project(camera, body.global_position).y)
		camera_rise = maxf(camera_rise, absf(camera.global_position.y - rest_y))
	summary["jump_screen"] = FollowCamera.STAGE_FEET_Y - highest
	check(camera_rise < 0.02 and highest < 0.5 and highest > 0.15, "a jump moves the courier up the frame (to y %.2f) and the picture only %.3f m: the view is frozen in the air, it follows floors" % [highest, camera_rise])
	# the run: away from the camera, then across the view
	var off_x := 0.0
	var off_y := 0.0
	var run_pitch := 0.0
	for i in 60:
		tick(c, Vector2(0.0, -1.0))
		follow.call(c.motion.grounded)
		var p := project(camera, body.global_position)
		if i > 40:
			off_x = maxf(off_x, absf(p.x - 0.5))
			off_y = maxf(off_y, absf(p.feet - FollowCamera.STAGE_FEET_Y))
			run_pitch = -rad_to_deg(camera.global_rotation.x)
	summary["run_offset"] = off_y
	summary["run_pitch"] = run_pitch
	check(off_x < 0.03 and off_y < 0.06, "running at %.1f m/s away from the camera: the courier's feet stay within x %.3f, y %.3f of their spot (the follow trails by speed / %.0f)" % [planar_speed(c), off_x, off_y, FollowCamera.STAGE_LAG_H])
	check(absf(idle_pitch - 12.4) < 0.1 and run_pitch >= 16.0 and run_pitch <= 24.0, "the view's pitch: %.1f degrees standing, %.1f after a second of running (target 12.4 and 14 to 24)" % [idle_pitch, run_pitch])
	for i in 360: view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": true, "run": 0.0}) # stands: the view's own settling (the pitch depends on the `run` share only)
	var rested := -rad_to_deg(camera.global_rotation.x)
	for i in 360:
		view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": true, "run": 1.0})
		if i == 14: summary["run_pitch_quarter"] = -rad_to_deg(camera.global_rotation.x)
	var settled := -rad_to_deg(camera.global_rotation.x)
	for i in 360: view.update(DT, body.global_position + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": true, "run": 0.0})
	var rested_again := -rad_to_deg(camera.global_rotation.x)
	summary["run_pitch_settled"] = settled
	check(absf(settled - 21.0) < 0.5 and absf(rested - 12.4) < 0.2 and absf(rested_again - 12.4) < 0.2 and float(summary.run_pitch_quarter) < settled - 2.0 and float(summary.run_pitch_quarter) > rested + 1.0, "the pitch eases from %.1f to %.1f degrees at the full run (%.1f after a quarter second, not at once) and back to %.1f when it stops (target 12.4, about 21)" % [rested, settled, float(summary.run_pitch_quarter), rested_again])
	drop(c)
	holder.remove_child(viewport)
	viewport.free()

## Every spot of a courier on each layer, every pitch and four yaws: the camera is never inside a floor slab the view still draws (the shell leaves out every floor over
## the viewed courier: game_run.gd _ghost_tiles, StepTiles.ghost_floors with the camera height at -INF), and never under its own floor's top.
func camera_slabs(feet: Vector3, yaw: float) -> void:
	var data: Dictionary = levels._levels[level].data.tiles
	var thick := float(data.thick)
	var inside := 0
	var tested := 0
	for floor_index in (data.floors as Array).size():
		var floor_y: float = origin().y + float(data.floors[floor_index].y)
		for pitch_degrees in [FollowCamera.STAGE_PITCH_LOW, -40.0, FollowCamera.STAGE_PITCH_DEFAULT, FollowCamera.STAGE_PITCH_HIGH]:
			for turn in 4:
				var f := frame(Vector2i(1280, 720), Vector3(feet.x, floor_y, feet.z), yaw + TAU * turn / 4.0, deg_to_rad(float(pitch_degrees)), 4)
				var camera_y: float = (f.camera as Vector3).y - origin().y
				var ghosted := StepTiles.ghost_floors(data, -INF, floor_y - origin().y)
				for other in (data.floors as Array).size():
					var top := float(data.floors[other].y)
					if camera_y < top and camera_y > top - thick - 0.22 and not ghosted.has(other): inside += 1
				if camera_y < float(data.floors[floor_index].y) + 0.3: inside += 1 # under or in its own floor
				tested += 1
	check(inside == 0, "the camera is never inside a floor slab the view draws, never under the floor of the courier it follows (%d views over every layer, pitch and quarter turns)" % tested)

## The race levels' stage view (`set_stage_view(true, true)`, game_run.gd `_sync_stage_view`): the picture follows a pad's throw in the air. The courier's heights are a kinematic arc with the ordinary
## motion's gravity (courier_motion.gd GRAVITY 17, a throw of vy 20 m/s from the goal tower's pads: apex 11.8 m, landing 8.5 m up on the tower top, 12 m/s along the view's way), the real follow camera in
## a 1280 x 720 viewport. The courier (feet to head) stays inside the middle 70 % of the frame's height over the whole arc and the landing, the picture only ever goes up (no overshoot), it has caught
## the rise at the apex, is back on its spot a second after the landing; a normal jump (apex 1.4 m) still moves the picture by nothing; a fall of 6 m off a ledge stays in the middle 70 % too.
func camera_air_follow(feet: Vector3, yaw: float, pitch: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	holder.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var view := FollowCamera.new()
	view.configure(camera)
	view.set_first_person(false)
	view.set_stage_view(true, true)
	var way := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -1.0)
	var arc := func(vy: float, run: float, land_at: float, ticks: int) -> Dictionary:
		var pos := feet
		var velocity := Vector3(way.x * run, vy, way.z * run)
		view.reset_lag()
		for i in 30: view.update(DT, pos + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": true})
		var rest_y := camera.global_position.y
		var top_min := 1.0
		var feet_max := 0.0
		var x_off := 0.0
		var reversed := 0
		var apex_y := feet.y
		var apex_tick := -1
		var landed := -1
		var previous: float = view._stage_anchor.y
		var direction := 0
		var at_apex := 0.0
		var grounded := false
		var screen := []
		var back := -1
		for i in ticks:
			if not grounded:
				velocity.y -= Motion.GRAVITY * DT
				pos += velocity * DT
				if velocity.y < 0.0 and pos.y <= feet.y + land_at:
					pos.y = feet.y + land_at
					grounded = true
					velocity = Vector3.ZERO
					landed = i
				if pos.y > apex_y:
					apex_y = pos.y
					apex_tick = i
			view.update(DT, pos + Vector3(0.0, 1.0, 0.0), yaw, pitch, null, {"grounded": grounded, "run": 0.0})
			var p := project(camera, pos)
			screen.append(p.feet)
			top_min = minf(top_min, float(p.feet) - float(p.share))
			feet_max = maxf(feet_max, p.feet)
			x_off = maxf(x_off, absf(p.x - 0.5))
			var moved: float = view._stage_anchor.y - previous
			if absf(moved) > 1.0e-5:
				var now := 1 if moved > 0.0 else -1
				if direction != 0 and now != direction: reversed += 1
				direction = now
			previous = view._stage_anchor.y
			if i == apex_tick: at_apex = camera.global_position.y - rest_y
			if landed >= 0 and back < 0 and absf(float(p.feet) - FollowCamera.STAGE_FEET_Y) < 0.02: back = i - landed
		return {"rest_y": rest_y, "top": top_min, "feet": feet_max, "x": x_off, "reversed": reversed, "apex": apex_y - feet.y, "camera_rise": camera.global_position.y - rest_y, "at_apex": at_apex, "back": back, "screen": screen, "apex_tick": apex_tick, "landed": landed}
	var throw: Dictionary = arc.call(20.0, 12.0, 8.5, 150)
	var apex: float = throw.apex
	summary["air_throw_top"] = throw.top
	summary["air_throw_feet"] = throw.feet
	var strip := ""
	for i in range(0, 120, 10): strip += " %.2f" % float((throw.screen as Array)[i])
	print("STAGE_FEEL pad throw, the courier's feet in the frame every 10 ticks:", strip)
	check(apex > 10.0 and throw.landed > 0, "the throw (vy 20, gravity %.0f) rises %.1f m and lands 8.5 m up after %.2f s" % [Motion.GRAVITY, apex, throw.landed * DT])
	check(float(throw.top) >= 0.15 and float(throw.feet) <= 0.85, "air follow: through the whole throw the courier stays in the middle 70 %% of the frame (head at most %.2f from the top, feet at most %.2f)" % [throw.top, throw.feet])
	check(float(throw.x) < 0.03, "and at x 0.50 (off by at most %.3f)" % throw.x)
	check(int(throw.reversed) <= 1, "the view's height goes up with the rise and comes down once to the tower top (%d change(s) of direction: no overshoot, no shake)" % int(throw.reversed))
	check(float(throw.at_apex) > apex - 4.0 and float(throw.at_apex) < apex, "the picture has followed the rise: %.1f m up at the apex (the apex is %.1f m, it trails by under 4 m, never ahead)" % [throw.at_apex, apex])
	check(int(throw.back) >= 0 and int(throw.back) * DT <= 1.0, "and the courier is back at its screen spot %.2f s after landing (at most 1.0 s)" % (int(throw.back) * DT))
	var jump: Dictionary = arc.call(7.0, 0.0, 0.0, 60)
	summary["air_jump_rise"] = jump.camera_rise
	check(absf(float(jump.camera_rise)) < 0.02 and float(jump.apex) < 2.0, "a normal jump (apex %.2f m) still moves the picture by %.3f m: calm" % [jump.apex, jump.camera_rise])
	var fall: Dictionary = arc.call(0.0, 6.0, -6.0, 90)
	summary["air_fall_feet"] = fall.feet
	check(float(fall.feet) <= 0.85 and float(fall.top) >= 0.15, "a fall of 6 m off a ledge: the courier stays in the middle 70 %% of the frame (feet at most %.2f)" % fall.feet)
	var frozen := FollowCamera.new()
	frozen.configure(camera)
	frozen.set_first_person(false)
	frozen.set_stage_view(true)
	check(not frozen.stage_air_follow and view.stage_air_follow, "the tile rounds' stage view (set_stage_view(true)) keeps the frozen air; only the race levels' asks for the air follow")
	holder.remove_child(viewport)
	viewport.free()

func feel_summary() -> void:
	print("STAGE_FEEL numbers: ", summary)
