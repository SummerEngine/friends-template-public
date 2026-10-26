extends SceneTree
## Dev check of levels/level_world.gd: builds the levels of a directory, prints the numbers of the zone / clock / launch / ice / floor queries,
## optionally renders frames. Headless (authority, numbers only):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer 0.7.2> --headless --audio-driver Dummy --path demo \
##     -s $PWD/tools/level_world_check.gd -- --role=authority --dir=$PWD/tools/level_testdata
## Offscreen (client look, frames; never windowed, offscreen binary only):
##   ... <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 --path demo \
##     -s $PWD/tools/level_world_check.gd -- --role=local --dir=$PWD/tools/level_testdata --shots=<dir> [--level=N] [--times=0,2,4] [--views=start,overview] [--hazards=N] [--expect=24]
const LevelWorld := preload("res://levels/level_world.gd")
const Hazards := preload("res://levels/hazards.gd")
const Rig := preload("res://courier/courier_rig.gd")
var shots := ""
var dir := "res://levels"
var role := "authority"
var only := 0
var max_hazards := 4
var expected := 0
var view_names: PackedStringArray = []
var times: Array = [0.0]
var world: Node3D
var holder: Node3D
var camera: Camera3D
var fails := 0
var checks := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
		if a.begins_with("--dir="): dir = a.trim_prefix("--dir=")
		if a.begins_with("--role="): role = a.trim_prefix("--role=")
		if a.begins_with("--level="): only = int(a.trim_prefix("--level="))
		if a.begins_with("--hazards="): max_hazards = int(a.trim_prefix("--hazards="))
		if a.begins_with("--expect="): expected = int(a.trim_prefix("--expect="))
		if a.begins_with("--views="): view_names = a.trim_prefix("--views=").split(",")
		if a.begins_with("--times="):
			times = []
			for part in a.trim_prefix("--times=").split(","): times.append(float(part))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		say("  FAIL " + text)

## The numbers every real level must satisfy: ground under both couriers at the start, a goal that answers "goal", no kill zone or goal on the start pad,
## a route that begins at the start and ends in the goal.
func assert_level(k: int, start: Dictionary, goal: Dictionary) -> void:
	var n := k + 1
	world.set_clock(0.0)
	var a: Vector3 = start.a
	var b: Vector3 = start.b
	var hot: bool = world.show_kind(k) == "survival" # its start stands on tiles that collapse: hazards, not static floor
	if not hot: expect(absf(world.floor_y(k, a)) < 0.05, "level %d: floor under courier A is %.2f, not 0" % [n, world.floor_y(k, a)])
	if not hot: expect(absf(world.floor_y(k, b)) < 0.05, "level %d: floor under courier B is %.2f, not 0" % [n, world.floor_y(k, b)])
	expect(world.zone_at(k, goal.p) == "goal", "level %d: goal centre is '%s'" % [n, world.zone_at(k, goal.p)])
	expect(world.zone_at(k, goal.floor) == "goal", "level %d: goal floor point is '%s'" % [n, world.zone_at(k, goal.floor)])
	var pad_clear := true
	var middle := (a + b) * 0.5
	for x in range(-3, 4):
		for z in range(-2, 3):
			for y in [0.0, 1.0, 2.0]:
				var point := middle + Vector3(x, y, z)
				if world.zone_at(k, point) != "": pad_clear = false
	expect(pad_clear, "level %d: a kill zone or the goal touches the start pad" % n)
	var route: PackedVector3Array = world.route(k)
	expect(route.size() >= 2, "level %d: route has %d points" % [n, route.size()])
	if route.size() >= 2:
		expect(Vector2(route[0].x - middle.x, route[0].z - middle.z).length() < 3.0, "level %d: route starts %s away from the start" % [n, route[0] - middle])
		expect(world.zone_at(k, route[route.size() - 1] - Vector3(0, 0.9, 0)) == "goal" or route[route.size() - 1].distance_to(goal.p) < 4.0, "level %d: route ends at %s, goal at %s" % [n, route[route.size() - 1], goal.p])
	expect(world.level_at(a.x) == k, "level %d: level_at(start) is %d" % [n, world.level_at(a.x)])

func say(text: String) -> void:
	print("GW_LEVELCHECK ", text)

func run() -> void:
	holder = Node3D.new()
	holder.name = "World"
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = dir
	holder.add_child(world)
	var t0 := Time.get_ticks_msec()
	await world.build(role)
	say("built role=%s levels=%d in %d ms" % [role, world.level_count(), Time.get_ticks_msec() - t0])
	if role != "authority":
		camera = Camera3D.new()
		camera.fov = 60.0
		camera.far = 800.0
		holder.add_child(camera)
		camera.current = true
	for k in world.level_count():
		if only > 0 and k + 1 != only: continue
		await check_level(k)
	if expected > 0: expect(world.level_count() == expected, "built %d levels, expected %d" % [world.level_count(), expected])
	await check_clock()
	say("ASSERTIONS %s: %d checks, %d failed" % ["OK" if fails == 0 else "FAILED", checks, fails])
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

func check_level(k: int) -> void:
	world.set_active_level(k)
	world.set_clock(0.0)
	await frames(3)
	var start: Dictionary = world.start_pose(k)
	var goal: Dictionary = world.goal_volume(k)
	say("level %d '%s' blurb='%s' origin=%s" % [k + 1, world.title(k), world.blurb(k), world.level_origin(k)])
	say("  start a=%s b=%s yaw=%.2f goal p=%s floor=%s route=%d" % [start.a, start.b, start.yaw, goal.p, goal.floor, world.route(k).size()])
	say("  zone start='%s' goalfloor='%s' goalcentre='%s' far_below='%s' floor_y(start)=%.2f" % [world.zone_at(k, start.a), world.zone_at(k, goal.floor), world.zone_at(k, goal.p), world.zone_at(k, start.a + Vector3(0, -30, 0)), world.floor_y(k, start.a)])
	var entry: Dictionary = world._levels[k]
	for volume: Dictionary in entry.data.kill:
		var centre: Vector3 = (volume.xf as Transform3D).origin + world.level_origin(k)
		say("  kill centre %s -> '%s' (feet at centre - 0.9)" % [centre, world.zone_at(k, centre - Vector3(0, 0.9, 0))])
	# bodies in the physics space: a ray down onto the start
	var space := world.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start.a + Vector3(0, 5, 0), start.a + Vector3(0, -5, 0), 1 | 16))
	say("  ray at start hits %s at y=%.2f" % [str(hit.collider.name) if not hit.is_empty() else "NOTHING", hit.position.y if not hit.is_empty() else 0.0])
	# hazards at three clock values
	for m in entry.movers.size():
		var mover: Dictionary = entry.movers[m]
		var h: Dictionary = mover.h
		var line := "  hazard %d %s id='%s' hit=%s:" % [m, h.k, h.id, h.hit]
		for t in [0.0, 1.0, 2.5, 4.0]:
			world.set_clock(t)
			var pose: Hazards.Pose = mover.pose
			line += " t=%.1f %s rot=%s%s" % [t, pose.position.snapped(Vector3.ONE * 0.01), (pose.basis.get_euler() * 180.0 / PI).snapped(Vector3.ONE * 0.1), "" if pose.active else "(gone)"]
		say(line)
		world.set_clock(0.0)
	# launch memory: outside, inside (fires once), inside again (silent), out, in again (fires)
	for index in entry.launchers.size():
		var launcher: Dictionary = entry.launchers[index]
		var h: Dictionary = launcher.h
		var frame := Transform3D(h.base, h.pivot)
		if launcher.host >= 0:
			var host_pose: Hazards.Pose = entry.movers[launcher.host].pose
			frame = Transform3D(host_pose.basis, host_pose.position) * frame
		var inside_feet: Vector3 = world.level_origin(k) + frame.origin - Vector3(0, 0.9, 0)
		var outside_feet: Vector3 = inside_feet + Vector3(0, 0, 30)
		world.effects_at(k, 0, outside_feet)
		var first: Dictionary = world.effects_at(k, 0, inside_feet)
		var again: Dictionary = world.effects_at(k, 0, inside_feet)
		world.effects_at(k, 0, outside_feet)
		var third: Dictionary = world.effects_at(k, 0, inside_feet + Vector3(0.2, 0, 0.1))
		var other_seat: Dictionary = world.effects_at(k, 1, inside_feet)
		expect(not first.is_empty() and again.is_empty() and not third.is_empty() and not other_seat.is_empty(), "level %d launcher %d %s: enter=%s again-empty=%s reenter=%s seat1=%s" % [k + 1, index, h.k, not first.is_empty(), again.is_empty(), not third.is_empty(), not other_seat.is_empty()])
		say("  launcher %d %s host=%d enter=%s again=%s reenter=%s seat1=%s" % [index, h.k, launcher.host, first, again.is_empty(), not third.is_empty(), not other_seat.is_empty()])
		if h.k == "bumper" and launcher.host < 0:
			# what is drawn bumps: a courier beside the ball at the height of its centre is thrown when its capsule touches the ball's band, not before
			# (a fresh seat each, so no launch memory is in the way; a neighbouring bumper may answer first in a tight cluster: any launch counts as "in")
			var reach: float = float(h.rad) + Hazards.BUMPER_BAND + LevelWorld.COURIER_RADIUS
			var beside: Vector3 = world.level_origin(k) + frame.origin - Vector3(0, LevelWorld.CENTRE_HEIGHT, 0)
			var far_hit: Dictionary = world.effects_at(k, 2, beside + Vector3(reach + 0.03, 0, 0))
			world.effects_at(k, 2, outside_feet)
			var near_hit: Dictionary = world.effects_at(k, 2, beside + Vector3(reach - 0.03, 0, 0))
			expect(int(far_hit.get("id", -1)) != index and not near_hit.is_empty(), "level %d bumper %d: reach %.2f m: %.2f m away not thrown=%s, %.2f m away thrown=%s" % [k + 1, index, reach, reach + 0.03, int(far_hit.get("id", -1)) != index, reach - 0.03, not near_hit.is_empty()])
	for block: Dictionary in entry.data.ice:
		var top: Vector3 = world.level_origin(k) + (block.xf as Transform3D).origin + Vector3(0, block.size.y * 0.5, 0)
		say("  ice surface on top=%s above=%s" % [world.surface_at(k, top), world.surface_at(k, top + Vector3(0, 2, 0))])
	assert_level(k, start, goal)
	if role != "authority" and shots != "": await shoot(k, start, goal)

func shoot(k: int, start: Dictionary, goal: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	var entry: Dictionary = world._levels[k]
	var route: PackedVector3Array = world.route(k)
	# a third-person view behind the start looking along the first stretch, then a high overview of the whole path
	var views: Array = []
	var origin: Vector3 = world.level_origin(k)
	var a: Vector3 = start.a
	var b: Vector3 = start.b
	var middle := (a + b) * 0.5
	var forward := Vector3(-sin(float(start.yaw)), 0.0, -cos(float(start.yaw)))
	var eye := middle - forward * 9.0 + Vector3(0, 4.5, 0)
	var from := middle + Vector3(0, 2.0, 0)
	var blocked := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, eye, 1 | 8 | 16))
	if not blocked.is_empty(): eye = from + (eye - from).normalized() * maxf(from.distance_to(blocked.position) - 0.4, 1.0)
	views.append(["start", eye, middle + forward * 6.0 + Vector3(0, 1.2, 0)])
	var centre := Vector3.ZERO
	for point in route: centre += point
	centre /= maxf(route.size(), 1.0)
	var span := 0.0
	for point in route: span = maxf(span, point.distance_to(centre))
	var along := Vector3(goal.p.x - middle.x, 0.0, goal.p.z - middle.z).normalized()
	var diag := maxf(span * 2.0, 12.0)
	views.append(["overview", centre - along * diag * 0.55 + Vector3(0, diag * 0.6, 0) + along.cross(Vector3.UP) * diag * 0.12, centre])
	# one close view on every hazard (up to 4)
	var count := 0
	for mover: Dictionary in entry.movers:
		var h: Dictionary = mover.h
		var at: Vector3 = origin + h.pivot
		views.append(["hazard_%d_%s" % [count, h.k], at + Vector3(6, 4, 9), at])
		count += 1
		if count >= max_hazards: break
	for launcher: Dictionary in entry.launchers:
		var at: Vector3 = origin + launcher.h.pivot
		views.append(["launcher_%s" % launcher.h.k, at + Vector3(6, 4, 9), at])
	var focus := middle + forward * 10.0
	for angle in 3:
		var spin: float = [0.0, 0.9, -1.6][angle]
		var lean: float = [1.45, 1.1, 0.85][angle]   # radians above the horizon: nearly straight down, steep, shallower
		var direction := (-forward).rotated(Vector3.UP, spin)
		views.append(["top%d" % (angle + 1), focus + direction * 30.0 * cos(lean) + Vector3(0, 30.0 * sin(lean), 0), focus])
	for view: Array in views:
		if not view_names.is_empty() and not view[0] in view_names: continue
		for t in times:
			world.set_clock(float(t))
			var peg_a := peg(a, 0, float(start.yaw))
			var peg_b := peg(b, 1, float(start.yaw))
			camera.global_position = view[1]
			camera.look_at(view[2], forward if str(view[0]).begins_with("top") else Vector3.UP)
			await frames(2)
			RenderingServer.force_draw(false)
			var image := root.get_texture().get_image()
			var file := "%s/level%02d_%s_t%s.png" % [shots, k + 1, view[0], str(t).replace(".", "_")]
			say("shot %s %s" % [file.get_file(), image.save_png(file) == OK])
			peg_a.queue_free()
			peg_b.queue_free()
	if "pan" in view_names:
		for step in 10:   # a slow pan: the camera drifts 1.2 m per frame over the first stretch
			var drift := focus + forward * (float(step) * 1.2 - 6.0)
			camera.global_position = drift - forward * 12.0 + Vector3(0, 22.0, 0)
			camera.look_at(drift, forward)
			await frames(2)
			RenderingServer.force_draw(false)
			var pan_file := "%s/level%02d_pan%02d.png" % [shots, k + 1, step]
			say("shot %s %s" % [pan_file.get_file(), root.get_texture().get_image().save_png(pan_file) == OK])

func peg(at: Vector3, seat: int, yaw: float) -> Node3D:
	var rig := Rig.new()
	holder.add_child(rig)
	rig.setup(seat, {})
	rig.global_position = at
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false})
	for i in 3: rig.update(1.0 / 60.0, {"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false})
	return rig

func check_clock() -> void:
	world.set_clock(10.0)
	world.correct_clock(10.3)
	var line := "clock 10.0 corrected to 10.3, after N ticks:"
	for n in 1 + 60:
		world.advance(1.0 / 60.0)
		if n in [0, 14, 29, 59]: line += " %d: %.4f" % [n + 1, world.clock]
	say(line + " (plain advance would read %.4f)" % [11.0])
	world.correct_clock(30.0)
	say("snap: clock=%.2f after a 18.9 s gap (expected 30.00)" % world.clock)
	world.sync_clock(30.2, 1.0 / 60.0)
	say("sync_clock(30.2, dt) -> %.4f" % world.clock)
