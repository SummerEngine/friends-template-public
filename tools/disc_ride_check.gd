extends SceneTree
## Dev check of the turning floors (a `spin` with `hit: false` and a cylinder part, level 31: docs/level-format.md "spin"): a real courier (courier_motion.gd, the physics of a game) rides each one.
##   "stand"  put on the disc 60 % of the way to the rim and left alone for 3 s: it stays grounded on the disc (feet within 0.15 m of the top), keeps its distance from the axis
##            (within 0.25 m) and goes round the axis with the disc (the angle it covers is the disc's, within 12 degrees), and the real course rules never send it back.
##   "walk"   (disc_b and disc_big) walks on from the static floor in front of it (the route), walks to 60 % of the radius, stops and rides 2 s: it is carried (it covered at least 70 % of the
##            disc's turn in those 2 s) and is never sent back.
##   "field"  (level 31) the disc field after the last ramp: from the static landing ring no jump reaches the big disc, not even with the dash (the ground dash into a jump with the air
##            dash on top, every timing of a grid of strategies), while each hop of the way over the small discs (ring > disc_l1 > l2 > l3 > disc_big, and the same on the right) is made by
##            a walking jump from enough of the starts of one cycle of the discs, and the big disc to the thin ramp walks on. A disc's pointer bar bounces (`bump`): a courier that
##            walks into the big disc's bar is thrown 8..10 m/s away from it with a pop, with the bumper sound's effect (`kind` "bumper").
## Prints DISC_RIDE lines and `DISC_RIDE ok=<bool>` last; exit code 1 on any failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s $PWD/tools/disc_ride_check.gd [-- --level=31]
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const Hazards := preload("res://levels/hazards.gd")
const DT := 1.0 / 60.0
const STAND_SECONDS := 3.0
const RIDE_SECONDS := 2.0
const SETTLE_TICKS := 15
const ANGLE_SLACK := 12.0 ## degrees
const HOP_STARTS := 24        ## starts of a hop test: spread over one cycle (24 s: every rate of the level divides it) of the discs
const HOP_MIN := 0.2          ## fraction of the starts a hop must be made from (a player waits for the moment)
const BRINK_BACK := 0.3       ## m before the brink a walking jump is pressed (the jump of the hop tests: where a player jumps at the edge, give or take)
const DIRECT_MARGIN := 1.0    ## m: the farthest a dash jump gets from the ring's brink must stay this far short of the big disc's rim

var only := 31
var world: Node3D
var failures := 0
var checks := 0
var discs := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): only = int(argument.trim_prefix("--level="))
	run.call_deferred()

func say(text: String) -> void:
	print("DISC_RIDE ", text)

func expect(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		say("FAIL " + text)

func run() -> void:
	world = LevelWorld.new()
	root.add_child(world)
	await world.build("authority")
	var k := only - 1
	world.set_active_level(k)
	await physics_frame
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var h: Dictionary = entry.movers[index].h
		if h.k != "spin" or bool(h.hit) or str(h.axis) != "y": continue
		var radius := 0.0
		for part: Dictionary in h.parts:
			if part.k == "cyl": radius = maxf(radius, float(part.size.x) * 0.5)
		if radius <= 0.0: continue
		discs += 1
		await stand(k, index, radius)
		if str(h.id) == "disc_b": await walk_on(k, index, radius)
	if only == 31: await check_field(k)
	say("%d discs ridden" % discs)
	expect(discs > 0, "level %d has turning discs" % only)
	say("ok=%s" % str(failures == 0))
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

## The disc's axis (world) and its top height.
func axis_of(k: int, index: int) -> Vector3:
	return world.level_origin(k) + (world._levels[k].movers[index].h.pivot as Vector3)

func angle_of(at: Vector3, axis: Vector3) -> float:
	return rad_to_deg(atan2(-(at.z - axis.z), at.x - axis.x))

func fresh_courier(spot: Vector3) -> Array:
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, spot + Vector3(0.0, 0.02, 0.0), 0.0)
	return [body, motion]

func stand(k: int, index: int, radius: float) -> void:
	var h: Dictionary = world._levels[k].movers[index].h
	var label := "level %d disc '%s' (d %.2f, %d deg/s) stand" % [only, h.id, radius * 2.0, int(h.rate)]
	world.set_clock(0.0)
	await physics_frame
	var axis := axis_of(k, index)
	var made := fresh_courier(axis + Vector3(0.0, 0.0, radius * 0.6)) # off the pointer bar (it lies along +X)
	var body: CharacterBody3D = made[0]
	var motion = made[1]
	for settle in SETTLE_TICKS:
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
	var start_angle := angle_of(body.global_position, axis)
	var t0: float = world.clock
	var worst_height := 0.0
	var worst_radius := 0.0
	var lost := false
	for tick in int(STAND_SECONDS / DT):
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
		var at := body.global_position
		worst_height = maxf(worst_height, absf(at.y - axis.y))
		worst_radius = maxf(worst_radius, absf(Vector2(at.x - axis.x, at.z - axis.z).length() - radius * 0.6))
		if not motion.grounded: lost = true
	var elapsed: float = float(world.clock) - t0
	var covered := wrapf(angle_of(body.global_position, axis) - start_angle, -180.0, 180.0)
	var wanted := wrapf(float(h.rate) * elapsed, -180.0, 180.0)
	expect(not lost, "%s: the courier left the floor" % label)
	expect(worst_height <= 0.15, "%s: feet %.2f m off the top" % [label, worst_height])
	expect(worst_radius <= 0.25, "%s: slid %.2f m off its ring" % [label, worst_radius])
	expect(absf(wrapf(covered - wanted, -180.0, 180.0)) <= ANGLE_SLACK, "%s: covered %.1f deg, the disc turned %.1f deg" % [label, covered, wanted])
	say("ok   %s: %.1f of %.1f deg, ring drift %.2f m, feet %.2f m" % [label, covered, wanted, worst_radius, worst_height])
	body.queue_free()
	await physics_frame

## Walks on from the static floor before the disc (the route: straight at the axis along -Z, one hop when the gap before the disc is wider than a courier), stops at 60 % of the radius and rides.
func walk_on(k: int, index: int, radius: float) -> void:
	var h: Dictionary = world._levels[k].movers[index].h
	var label := "level %d disc '%s' walk-on" % [only, h.id]
	world.set_clock(0.0)
	await physics_frame
	var axis := axis_of(k, index)
	var from := Vector3(axis.x, 0.0, axis.z + radius + 2.0)
	var floor_y := NAN
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 2.0, from + Vector3.DOWN * 6.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		expect(false, "%s: no static floor %.1f m before the disc" % [label, radius + 2.0])
		return
	floor_y = (hit["position"] as Vector3).y
	var made := fresh_courier(Vector3(from.x, floor_y, from.z))
	var body: CharacterBody3D = made[0]
	var motion = made[1]
	for settle in SETTLE_TICKS:
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
	var stopped := false
	var t_stop := 0.0
	var angle_stop := 0.0
	var jumped := false
	for tick in int(12.0 / DT):
		await physics_frame
		world.advance(DT)
		var at := body.global_position
		var rel := Vector2(at.x - axis.x, at.z - axis.z)
		var input := {}
		if not stopped:
			if rel.length() > radius * 0.6:
				var to := Vector2(axis.x - at.x, axis.z - at.z).normalized()
				input["move"] = to
				if not jumped and motion.grounded and rel.length() < radius + 1.6 and rel.length() > radius + 0.8: # the gap before the disc (the landing's rim): a hop
					input["jump"] = true
					jumped = true
			else:
				stopped = true
				t_stop = world.clock
				angle_stop = angle_of(at, axis)
		motion.step(body, input, DT)
		if stopped and world.clock - t_stop >= RIDE_SECONDS: break
	expect(stopped, "%s: the courier never came to the disc's 60 %% ring" % label)
	if stopped:
		var covered := wrapf(angle_of(body.global_position, axis) - angle_stop, -180.0, 180.0)
		var wanted: float = float(h.rate) * (float(world.clock) - t_stop)
		var ratio: float = covered / wanted if absf(wanted) > 1.0 else 0.0
		expect(ratio >= 0.7, "%s: carried only %.1f of %.1f deg" % [label, covered, wanted])
		expect(absf(body.global_position.y - axis.y) < 0.2 and motion.grounded, "%s: not standing on the disc at the end" % label)
		say("ok   %s: carried %.1f of %.1f deg in %.1f s" % [label, covered, wanted, world.clock - t_stop])
	body.queue_free()
	await physics_frame

## ---- the disc field of level 31 -------------------------------------------------------------------------------------------------------------------------------------------
## A surface of the field: a static ring / ramp start (`axis` its centre, `radius`, `top`) or a turning disc (`index` of its mover).
func surface(k: int, id: String) -> Dictionary:
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var h: Dictionary = entry.movers[index].h
		if str(h.id) != id: continue
		var radius := 0.0
		for part: Dictionary in h.parts:
			if part.k == "cyl": radius = maxf(radius, float(part.size.x) * 0.5)
		return {"id": id, "index": index, "radius": radius, "top": float((h.pivot as Vector3).y), "body": entry.movers[index].body}
	return {}

func static_surface(k: int, id: String, at: Vector3, radius: float, top: float) -> Dictionary:
	return {"id": id, "index": -1, "radius": radius, "top": top, "axis": world.level_origin(k) + at, "body": null}

## Where a surface's centre is now (a disc moves only about its axis: the hub does not move).
func centre_of(k: int, surf: Dictionary) -> Vector3:
	if int(surf.index) < 0: return surf.axis
	return axis_of(k, int(surf.index))

## One attempt to get from `from` to `to`. The courier stands on `from` at 60 % of its radius on the line to `to` (at the clock now), runs at the target's centre and presses jump when
## its distance from the brink along the line is `jump_at` (negative: before it), a ground dash when it is `ground_at` m before the brink (null: none) and an air dash `air_after` s
## after the jump (null: none). Returns {landed: it stands on `to` (a disc: on its body; a static surface: on no mover within 2 m of its centre), reach: the farthest it got from the
## brink along the line, at the height of `to`'s top or above, bonks: launches it got, kinds}.
func hop(k: int, from: Dictionary, to: Dictionary, jump_at: float, ground_at: Variant, air_after: Variant) -> Dictionary:
	var a := centre_of(k, from)
	var b := centre_of(k, to)
	var line := Vector2(b.x - a.x, b.z - a.z).normalized()
	var start := Vector2(a.x, a.z) + line * float(from.radius) * 0.6
	var made := fresh_courier(Vector3(start.x, float(from.top) + world.level_origin(k).y, start.y))
	var body: CharacterBody3D = made[0]
	var motion = made[1]
	body.rotation.y = atan2(-line.x, -line.y)
	for settle in 6:
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
	var jumped_at := -1.0
	var landed := false
	var reach := -99.0
	var launches := 0
	var kinds := ""
	var airborne := false
	var t0: float = world.clock
	var dashed_ground := false
	for tick in int(4.0 / DT):
		await physics_frame
		world.advance(DT)
		var at := body.global_position
		var rel := Vector2(at.x - a.x, at.z - a.z)
		var along := rel.dot(line) - float(from.radius)     # m past the brink of `from` along the line
		var to_b := Vector2(b.x - at.x, b.z - at.z)
		var move := to_b.normalized() if to_b.length() > 0.2 else Vector2.ZERO
		var input := {"move": move}
		if jumped_at < 0.0 and motion.grounded and along >= jump_at: # the jump
			input["jump"] = true
			jumped_at = world.clock
		if ground_at != null and not dashed_ground and motion.grounded and jumped_at < 0.0 and along >= -float(ground_at):
			input["dash"] = true
			dashed_ground = true
		if air_after != null and jumped_at >= 0.0 and world.clock - jumped_at >= float(air_after) - 0.5 * DT and not motion.grounded and world.clock - jumped_at < float(air_after) + 0.1:
			input["dash"] = true
		var effect: Dictionary = world.apply_effects(k, 0, body, motion)
		if not effect.is_empty():
			launches += 1
			kinds += str(effect.kind) + " "
		motion.step(body, input, DT)
		if not motion.grounded: airborne = true
		var feet := body.global_position
		if feet.y >= float(to.top) + world.level_origin(k).y - 0.3: reach = maxf(reach, (Vector2(feet.x, feet.z) - Vector2(a.x, a.z)).dot(line) - float(from.radius))
		if airborne and motion.grounded:
			if to.body != null: landed = motion.platform == to.body and absf(feet.y - (float(to.top) + world.level_origin(k).y)) < 0.2
			else: landed = motion.platform == null and Vector2(feet.x - b.x, feet.z - b.z).length() < float(to.radius) + 0.2 and (bool(to.get("slope", false)) or absf(feet.y - (float(to.top) + world.level_origin(k).y)) < 0.2)
			if landed or jumped_at >= 0.0: break
		if feet.y < float(to.top) + world.level_origin(k).y - 8.0: break
	body.queue_free()
	await physics_frame
	return {"landed": landed, "reach": reach, "launches": launches, "kinds": kinds}

func check_field(k: int) -> void:
	var entry: Dictionary = world._levels[k]
	var ring_at := Vector3.ZERO
	var ring_top := 0.0
	var ring_d := 0.0
	for block: Dictionary in entry.data.blocks:
		if block.k == "cyl" and str(block.tone) == "court":
			ring_at = (block.xf as Transform3D).origin
			ring_top = ring_at.y + float(block.size.y) * 0.5
			ring_d = float(block.size.x)
	var ring := static_surface(k, "ring", Vector3(ring_at.x, 0.0, ring_at.z), ring_d * 0.5, ring_top)
	var big := surface(k, "disc_big")
	expect(ring_d > 0.0 and not big.is_empty(), "the field: the landing ring and the big disc are there")
	# 1. the direct jump: the grid of strategies of a walking jump, a ground dash into a jump, an air dash, from the ring's brink at the big disc
	var tried := 0
	var made_it := 0
	var farthest := -99.0
	var gap: float = (centre_of(k, big) - centre_of(k, ring)).length() - float(ring.radius) - float(big.radius)
	for jump_at in [-0.3, 0.0, 0.2]:
		for ground_at in [null, 3.0, 2.0, 1.2, 0.6]:
			for air_after in [null, 0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8]:
				for clock0 in [0.0, 6.0]:
					world.set_clock(clock0)
					await physics_frame
					var r: Dictionary = await hop(k, ring, big, jump_at, ground_at, air_after)
					tried += 1
					if bool(r.landed): made_it += 1
					farthest = maxf(farthest, float(r.reach))
	expect(made_it == 0, "field: %d of %d strategies (jump, ground dash, air dash) reach the big disc from the ring" % [made_it, tried])
	expect(farthest < gap - DIRECT_MARGIN, "field: the farthest dash jump gets %.2f m past the ring's brink, the big disc is %.2f m away" % [farthest, gap])
	say("ok   field direct: %d strategies, none lands on the big disc; farthest %.2f m past the brink at disc height, gap %.2f m" % [tried, farthest, gap])
	# 2. the way over: walking hops along each side
	for side in ["l", "r"]:
		var chain: Array = [ring, surface(k, "disc_%s1" % side), surface(k, "disc_%s2" % side), surface(k, "disc_%s3" % side), big]
		for i in chain.size() - 1:
			var good := 0
			for start in HOP_STARTS:
				world.set_clock(24.0 * float(start) / HOP_STARTS)
				await physics_frame
				var r: Dictionary = await hop(k, chain[i], chain[i + 1], -BRINK_BACK, null, null)
				if bool(r.landed): good += 1
			var label := "field hop %s > %s" % [chain[i].id, chain[i + 1].id]
			expect(float(good) / HOP_STARTS >= HOP_MIN, "%s: made from %d of %d starts (need %.0f %%)" % [label, good, HOP_STARTS, HOP_MIN * 100.0])
			say("ok   %s: made from %d of %d starts" % [label, good, HOP_STARTS])
	# 2b. off the big disc onto the walkway behind it: a floor within a step of its far rim (the courier walks off; the wheel behind sweeps that floor, it is not a jump to make)
	var rim := centre_of(k, big) + Vector3(0.0, 0.0, -(float(big.radius) + 0.45))
	var query := PhysicsRayQueryParameters3D.create(rim + Vector3.UP * 4.0, rim + Vector3.DOWN * 8.0, 1)
	var found := world.get_world_3d().direct_space_state.intersect_ray(query)
	expect(not found.is_empty() and absf((found["position"] as Vector3).y - (float(big.top) + world.level_origin(k).y)) < 0.8, "field: a static floor within 0.45 m past the big disc's far rim, no higher than a step over it")
	say("ok   field big disc > walkway: static floor %.2f m up/down at 0.45 m past the far rim" % ((found["position"] as Vector3).y - (float(big.top) + world.level_origin(k).y) if not found.is_empty() else 99.0))
	# 3. the big disc's pointer bar bounces
	await check_bump(k, big)

## A courier on the big disc walking into the pointer bar from the side: bounced 8..10 m/s away from the bar's plane with a pop; `kind` "bumper".
func check_bump(k: int, big: Dictionary) -> void:
	var index := int(big.index)
	var h: Dictionary = entry_h(k, index)
	var bar := -1
	for part_index in h.parts.size():
		if bool(h.parts[part_index].bump): bar = part_index
	expect(bar >= 0, "bump: the big disc has a bumper bar")
	if bar < 0: return
	world.set_clock(0.0)
	await physics_frame
	var axis := axis_of(k, index)
	var radius := float(big.radius)
	var made := fresh_courier(axis + Vector3(radius * 0.55, 0.0, radius * 0.25)) # beside the bar (it lies along +X at the start), 0.6 m off its plane
	var body: CharacterBody3D = made[0]
	var motion = made[1]
	var launched: Dictionary = {}
	for tick in int(6.0 / DT):
		await physics_frame
		world.advance(DT)
		var effect: Dictionary = world.apply_effects(k, 0, body, motion)
		if not effect.is_empty() and launched.is_empty():
			launched = effect
			break
		var pose := Hazards.Pose.new()
		Hazards.pose(h, world.clock, pose)
		var frame := Transform3D(pose.basis, pose.position) * (h.parts[bar].xf as Transform3D)
		var feet_local: Vector3 = body.global_position - world.level_origin(k)
		var inside_bar: Vector3 = frame.affine_inverse() * feet_local
		var aim: Vector3 = frame * Vector3(clampf(inside_bar.x, -float(h.parts[bar].size.x) * 0.5, float(h.parts[bar].size.x) * 0.5), 0.0, 0.0) # the nearest point of the bar's centre line
		var toward := Vector2(aim.x - feet_local.x, aim.z - feet_local.z)
		motion.step(body, {"move": toward.normalized() if toward.length() > 0.05 else Vector2.ZERO}, DT)
	expect(not launched.is_empty(), "bump: the turning bar was never felt by a courier standing beside it")
	if launched.is_empty():
		body.queue_free()
		return
	var v: Vector3 = launched.v
	var flat := Vector2(v.x, v.z).length()
	expect(str(launched.kind) == "bumper", "bump: the effect is a bumper's (kind %s)" % launched.kind)
	expect(flat >= 8.0 and flat <= 10.0 and v.y >= 2.0 and v.y <= 6.0, "bump: thrown %.1f m/s sideways and %.1f up (want 8..10 and a small pop)" % [flat, v.y])
	say("ok   bump: kind %s, %.1f m/s away from the bar and %.1f up" % [launched.kind, flat, v.y])
	body.queue_free()
	await physics_frame

func entry_h(k: int, index: int) -> Dictionary:
	return world._levels[k].movers[index].h
