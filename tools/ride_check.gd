extends SceneTree
## Dev check of the moving platforms of a level directory (not shipped). Two parts, both headless, no input and no bot:
##  1. STATIC: every platform (slide / lift / spin / swing without `hit`) is sampled over its whole cycle (a clock step of 0.25 s). A courier standing on
##     a sampled point of its top must never be inside a kill zone (zone_at) and the platform must never leave the level's void line.
##  2. PHYSICS: a courier (courier_motion.gd, no input) is put on top of each such platform and the level clock runs a full cycle in physics ticks,
##     exactly like the simulation does (advance(dt) first, then the courier steps). The courier must stay on the platform (grounded, platform under
##     the feet, still on its top) and never be in a kill zone.
## Prints GW_RIDE lines and `GW_RIDE RESULT`; exit code 1 on any failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer 0.7.2> --headless --audio-driver Dummy --path demo \
##     -s $PWD/tools/ride_check.gd -- --dir=$PWD/demo/levels [--level=10] [--static-only] [--cycles=1]
const LevelWorld := preload("res://levels/level_world.gd")
const Hazards := preload("res://levels/hazards.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const SAMPLE_STEP := 0.25
const OFF_PLATFORM_TICKS := 20     ## a courier not carried for this many ticks in a row has been left behind
const HOLD_DISTANCE := 0.45        ## the feet may be this far from the platform top
const RIDER_KINDS := ["slide", "lift", "spin", "swing"]

var dir := "res://levels"
var only := 0
var static_only := false
var cycles := 1
var trace := false
var only_platform := -1
var world: Node3D
var holder: Node3D
var fails := 0
var checks := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="): dir = a.trim_prefix("--dir=")
		if a.begins_with("--level="): only = int(a.trim_prefix("--level="))
		if a.begins_with("--cycles="): cycles = maxi(int(a.trim_prefix("--cycles=")), 1)
		if a == "--static-only": static_only = true
		if a == "--trace": trace = true
		if a.begins_with("--platform="): only_platform = int(a.trim_prefix("--platform="))
	run.call_deferred()

func say(text: String) -> void:
	print("GW_RIDE ", text)

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		say("FAIL " + text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = dir
	holder.add_child(world)
	await world.build("authority")
	var riders := 0
	for k in world.level_count():
		if only > 0 and k + 1 != only: continue
		world.set_active_level(k)
		await physics_frame
		riders += await check_level(k)
	say("RESULT %s: %d checks, %d failed, %d platforms" % ["OK" if fails == 0 else "FAILED", checks, fails, riders])
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

## Platforms of a level: movers of a rider kind that do not hurt (`hit` false) and have a flat top.
func platforms(k: int) -> Array:
	var result: Array = []
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		var h: Dictionary = mover.h
		if not h.k in RIDER_KINDS or h.hit: continue
		result.append(index)
	return result

func cycle_length(h: Dictionary) -> float:
	if h.k == "spin": return 360.0 / maxf(absf(float(h.rate)), 1.0)
	return maxf(float(h.period), 1.0)

## Top faces of a mover body: [{xf, top, half (Vector2 of the face), area}] for the box and cylinder shapes that face up. `from_pose` = where the clock
## puts the body (a body that syncs to physics only moves at the next physics step), else where the body really is.
func tops(k: int, mover: Dictionary, from_pose: bool) -> Array:
	var result: Array = []
	var frame: Transform3D = (mover.body as Node3D).global_transform
	if from_pose:
		var pose: Hazards.Pose = mover.pose
		frame = Transform3D(pose.basis, pose.position + world.level_origin(k))
	for child in (mover.body as Node).get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null: continue
		var xf := frame * shape_node.transform
		if xf.basis.y.normalized().y < 0.9: continue
		if shape_node.shape is BoxShape3D:
			var size: Vector3 = (shape_node.shape as BoxShape3D).size
			result.append({"xf": xf, "top": Vector3(0, size.y * 0.5, 0), "half": Vector2(size.x, size.z) * 0.5, "area": size.x * size.z, "pivot": frame.origin})
		elif shape_node.shape is CylinderShape3D:
			var cylinder := shape_node.shape as CylinderShape3D
			result.append({"xf": xf, "top": Vector3(0, cylinder.height * 0.5, 0), "half": Vector2(cylinder.radius, cylinder.radius) * 0.7, "area": PI * cylinder.radius * cylinder.radius, "pivot": frame.origin})
	return result

func check_level(k: int) -> int:
	var found := platforms(k)
	if found.is_empty(): return 0
	var entry: Dictionary = world._levels[k]
	var number := k + 1
	for index in found:
		if only_platform >= 0 and index != only_platform: continue
		var mover: Dictionary = entry.movers[index]
		var h: Dictionary = mover.h
		var length := cycle_length(h)
		var label := "level %d '%s' platform %d %s id='%s' (cycle %.1f s)" % [number, world.title(k), index, h.k, h.id, length]
		# 1. static
		var worst := ""
		var intrusions: Array[String] = []
		var zones_hit: Dictionary = {}
		var steps := int(ceil(length / SAMPLE_STEP))
		for step in steps:
			var t := float(step) * SAMPLE_STEP
			world.set_clock(t)
			for face: Dictionary in tops(k, mover, true):
				for fx in [-1.0, 0.0, 1.0]:
					for fz in [-1.0, 0.0, 1.0]:
						var local: Vector3 = face.top + Vector3(fx * face.half.x, 0.0, fz * face.half.y)
						var feet: Vector3 = (face.xf as Transform3D) * local
						var zone: String = world.zone_at(k, feet + Vector3(0, 0.05, 0))
						if zone == "kill":
							if worst == "": worst = "t=%.2f feet at %s (level-local %s) are in a kill zone:%s" % [t, feet, feet - world.level_origin(k), kill_zones(k, feet + Vector3(0, 0.05, 0))]
							intrusions.append("t=%.2f %s" % [t, (feet - world.level_origin(k)).snapped(Vector3.ONE * 0.01)])
							for zone_index in entry.data.kill.size():
								if LevelWorld.Data.inside(entry.data.kill[zone_index], feet - world.level_origin(k) + Vector3(0, 0.95, 0)): zones_hit[zone_index] = int(zones_hit.get(zone_index, 0)) + 1
		if worst != "":
			var shown := intrusions.slice(0, 6)
			worst += " | %d sampled points inside kill zones, first: %s ... last: %s; kill zones involved (index: points): %s" % [intrusions.size(), "; ".join(shown), intrusions[intrusions.size() - 1], str(zones_hit)]
		expect(worst == "", "%s: %s" % [label, worst])
		if worst == "": say("static ok: " + label)
		# 2. physics
		if not static_only:
			var spots := ["nearest the pivot", "centre of the top", "half way to the corner"]
			var failures: Array[String] = []
			var passed := false
			for variant in spots.size():
				if await ride(k, index, label, length, variant):
					passed = true
					break
				failures.append("[%s] %s" % [spots[variant], last_failure])
				if last_failure == "":
					passed = true   # skipped (nothing to ride)
					break
			if not passed:
				var blocked := true
				for text in failures:
					if not ("NEIGHBOUR" in text or "OBSTRUCTED" in text): blocked = false
				if blocked: say("WARN the ride is stopped by a neighbouring mover or by static geometry in the route (the ride up to that moment is proven): %s: %s" % [label, " | ".join(failures)])
				else: expect(false, "%s: %s" % [label, " | ".join(failures)])
			elif failures.size() > 0: say("ride ok on a later spot (%d spots failed first: %s): %s" % [failures.size(), " | ".join(failures), label])
	world.set_clock(0.0)
	return found.size()

var last_failure := ""

## One ride with the courier on spot `variant`; true when it stayed on (or nothing could be ridden), else last_failure says why.
func ride(k: int, index: int, label: String, length: float, variant := 0) -> bool:
	last_failure = ""
	var entry: Dictionary = world._levels[k]
	var mover: Dictionary = entry.movers[index]
	var h: Dictionary = mover.h
	var body_node := mover.body as AnimatableBody3D
	# start clock: where nothing static is under the platform's centre (so the courier really rides), else the start
	var start_t := 0.0
	var spot := Vector3.ZERO
	var found := false
	for step in int(ceil(length / 0.5)):
		var t := float(step) * 0.5
		world.set_clock(t)
		var faces := tops(k, mover, true)
		if faces.is_empty(): continue
		faces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)
		var face: Dictionary = faces[0]
		# the rider stands on the point of the biggest top that is closest to the body's origin (the pivot of a spinner), 0.6 m inside its edge
		var pivot_local: Vector3 = (face.xf as Transform3D).affine_inverse() * (face.pivot as Vector3)
		if variant == 1: pivot_local = Vector3.ZERO
		elif variant == 2: pivot_local = Vector3(face.half.x * 0.5, 0.0, face.half.y * 0.5)
		var spot_local := Vector3(clampf(pivot_local.x, -maxf(face.half.x - 0.6, 0.0), maxf(face.half.x - 0.6, 0.0)), 0.0, clampf(pivot_local.z, -maxf(face.half.y - 0.6, 0.0), maxf(face.half.y - 0.6, 0.0)))
		var on_top: Vector3 = (face.xf as Transform3D) * (face.top + spot_local)
		var support: float = world.floor_y(k, on_top)
		if is_nan(support) or support < on_top.y - 1.0:
			start_t = t
			spot = on_top
			found = true
			break
	if not found:
		say("skip (a static floor is under the platform all the time): " + label)
		return true
	world.set_clock(start_t)
	await physics_frame
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, spot + Vector3(0, 0.02, 0), 0.0)
	for i in 10:
		await physics_frame
		motion.step(body, {}, DT)
	var ticks := int(ceil(length * float(cycles) / DT))
	var off := 0
	var worst_off := 0
	var failure := ""
	var travelled := 0.0
	var last := body.global_position
	var obstruction := ""
	for tick in ticks:
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
		var position := body.global_position
		travelled += position.distance_to(last)
		last = position
		if world.zone_at(k, position) == "kill":
			failure = "killed at tick %d (t=%.2f) at %s (level-local %s), platform at %s, in:%s" % [tick, world.clock, position, position - world.level_origin(k), body_node.global_position, kill_zones(k, position)]
			break
		var faces := tops(k, mover, false)
		var over := false
		var top_distance := INF
		for face: Dictionary in faces:
			var local: Vector3 = (face.xf as Transform3D).affine_inverse() * position
			if absf(local.x) <= face.half.x + 0.35 and absf(local.z) <= face.half.y + 0.35:
				over = true
				top_distance = minf(top_distance, absf(position.y - ((face.xf as Transform3D) * face.top).y))
		if trace and tick % 30 == 0: say("trace t=%.2f courier-local %s vel %s %s %s grounded %s on_platform %s platform_pos %s slides %s" % [world.clock, ((body_node.global_transform).affine_inverse() * position).snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.01), "pv", motion._platform_velocity.snapped(Vector3.ONE * 0.01), motion.grounded, motion.platform == body_node, body_node.global_position, slide_report(body, motion)])
		if obstruction == "" and motion.platform == body_node and motion._platform_velocity.length() > 0.1:
			var heading: Vector3 = motion._platform_velocity.normalized()
			for rise in [0.3, 1.5]:
				var from := position + Vector3(0, rise, 0)
				var ray := body.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + heading * 0.8, 1, [body.get_rid(), body_node.get_rid()]))
				if not ray.is_empty():
					obstruction = "static '%s' at t=%.2f, %.2f m ahead of the courier at level-local %s" % [(ray.collider as Node).name, world.clock, from.distance_to(ray.position), position - world.level_origin(k)]
					break
		var carried := over and motion.grounded and top_distance <= HOLD_DISTANCE
		if carried: off = 0
		else: off += 1
		worst_off = maxi(worst_off, off)
		if off >= OFF_PLATFORM_TICKS:
			var support: float = world.floor_y(k, position)
			if motion.grounded and not is_nan(support) and absf(support - position.y) < 0.15:
				say("ride ended on static ground at t=%.2f (the platform moved out from under the courier onto a flush floor): %s" % [world.clock, label])
				break
			var neighbour := ""
			for index2 in body.get_slide_collision_count():
				var other := body.get_slide_collision(index2).get_collider() as CollisionObject3D
				if other != null and other != body_node and (other.collision_layer & 16) != 0: neighbour = other.name
			if neighbour != "":
				failure = "NEIGHBOUR blocked by the neighbouring mover '%s' at t=%.2f (courier at level-local %s)" % [neighbour, world.clock, position - world.level_origin(k)]
				break
			var blocked := "" if obstruction == "" else " (the platform's route is obstructed: " + obstruction + ")"
			failure = "left behind at tick %d (t=%.2f): courier at %s, platform at %s, grounded=%s, over=%s, top distance %.2f" % [tick, world.clock, position, body_node.global_position, motion.grounded, over, top_distance if top_distance != INF else -1.0] + blocked
			if obstruction != "": failure = "OBSTRUCTED " + failure
			break
	if failure == "": say("ride ok: %s, %d ticks from t=%.1f, courier moved %.1f m, longest off-platform streak %d ticks" % [label, ticks, start_t, travelled, worst_off])
	last_failure = failure
	body.queue_free()
	await physics_frame
	world.set_clock(0.0)
	return failure == ""

## Which kill volumes of the level hold this world point (the centre of a courier standing with its feet there).
func kill_zones(k: int, feet: Vector3) -> String:
	var entry: Dictionary = world._levels[k]
	var local: Vector3 = feet - world.level_origin(k) + Vector3(0, LevelWorld.CENTRE_HEIGHT, 0)
	var text := ""
	if local.y < float(entry.data.void_y): text += " below void_y %.1f" % float(entry.data.void_y)
	for index in entry.data.kill.size():
		var volume: Dictionary = entry.data.kill[index]
		if LevelWorld.Data.inside(volume, local):
			var origin: Vector3 = (volume.xf as Transform3D).origin
			text += " kill[%d] centre %s size %s" % [index, origin.snapped(Vector3.ONE * 0.01), (volume.half as Vector3) * 2.0]
	return text

func slide_report(body: CharacterBody3D, motion: RefCounted) -> String:
	var text := ""
	for index in body.get_slide_collision_count():
		var hit := body.get_slide_collision(index)
		text += "[%s n=%s]" % [(hit.get_collider() as Node).name, hit.get_normal().snapped(Vector3.ONE * 0.01)]
	var heading: Vector3 = motion._platform_velocity
	if heading.length() > 0.1:
		var from := body.global_position + Vector3(0, 0.5, 0)
		var query := PhysicsRayQueryParameters3D.create(from, from + heading.normalized() * 1.5, 0xFFFFFFFF, [body.get_rid()])
		var ray := body.get_world_3d().direct_space_state.intersect_ray(query)
		if not ray.is_empty(): text += " AHEAD %s layer %d at %.2f m" % [(ray.collider as Node).name, (ray.collider as CollisionObject3D).collision_layer, from.distance_to(ray.position)]
	return text
