extends SceneTree
## EXPERIMENT (switchable) edge bumpers: frames for the proof of the cushions (levels/edge_bumpers.gd, docs/level-format.md "Edge bumpers (experiment)"): the real LevelWorld with the
## cushions, the real courier physics and the real character rig. Shots, by name (`--only=`):
##   approach   a player's view behind a courier in mid-jump towards a bumpered platform (the first one with sides of 4 m or more, or `--pick=<block index>`)
##   close      a close view of the near cushions of that platform, a courier standing in the clear middle
##   overhead   straight down (orthographic), the whole level or the window `--focus=x,z --span=<m>` (level-local): the picture is accompanied by <name>.json with the screen box of every
##              candidate platform and whether it has bumpers (to draw a frame round each when the pictures are put on a sheet)
##   strip_centre / strip_edge   a courier dropped (5 m/s forward, 3 m up) on the middle of that platform / on the strip just inside its near cushion: a frame every STRIDE ticks
## Offscreen binary only, never windowed, ONE shot name per run (the offscreen binary ends a script after about 30 s):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/edge_bumper_frames.gd" -- --shots=<dir> --level=30 --only=approach [--pick=<block>] [--focus=x,z --span=60] [--prefix=eb_]
## Prints EDGE_FRAMES lines.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const Motion := preload("res://courier/courier_motion.gd")
const EdgeBumpers := preload("res://levels/edge_bumpers.gd")
const RaceWorld := preload("res://style/race_world.gd")
const DT := 1.0 / 60.0
const SPEED := 5.0
const DROP := 3.0
const STRIDE := 5       ## ticks between two frames of a strip
const STRIP_FRAMES := 24
const STRIP_FROM := 14  ## the tick of the first frame of a strip (the courier is 1 m over the deck)

var shots := ""
var prefix := "eb_"
var level_number := 30
var only := ""
var pick := -1
var focus := Vector2.ZERO
var span := 0.0
var world: Node3D
var holder: Node3D
var camera: Camera3D
var k := 0
var origin := Vector3.ZERO
var data: Dictionary = {}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if argument.begins_with("--pick="): pick = int(argument.trim_prefix("--pick="))
		if argument.begins_with("--focus="):
			var parts := argument.trim_prefix("--focus=").split(",")
			focus = Vector2(parts[0].to_float(), parts[1].to_float())
		if argument.begins_with("--span="): span = argument.trim_prefix("--span=").to_float()
	create_timer(200.0).timeout.connect(func() -> void:
		print("EDGE_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func run() -> void:
	if shots == "" or only == "":
		print("EDGE_FRAMES needs --shots=<dir> and --only=<shot>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	k = level_number - 1
	camera = Camera3D.new()
	camera.far = 4000.0 # as the game camera
	holder.add_child(camera)
	camera.current = true
	world.set_active_level(k)
	world.set_clock(0.0)
	data = world._levels[k].data
	origin = world.level_origin(k)
	var platforms: Array = data.edge_bumpers.platforms
	if platforms.is_empty():
		print("EDGE_FRAMES FAIL level ", level_number, " has no bumpered platform")
		quit(1)
		return
	var platform: Dictionary = chosen(platforms)
	var ok := false
	match only:
		"approach": ok = await approach(platform)
		"close": ok = await close(platform)
		"overhead": ok = await overhead()
		"strip_centre": ok = await strip(platform, false)
		"strip_edge": ok = await strip(platform, true)
		_: print("EDGE_FRAMES FAIL unknown shot ", only)
	print("EDGE_FRAMES ok=", ok, " level ", level_number, " platform block ", platform.index)
	holder.queue_free()
	await process_frame
	quit(0 if ok else 1)

## The platform the close shots are about.
func chosen(platforms: Array) -> Dictionary:
	for platform: Dictionary in platforms:
		if pick >= 0 and int(platform.index) == pick: return platform
	for platform: Dictionary in platforms:
		if pick < 0 and minf(float(platform.x1) - float(platform.x0), float(platform.z1) - float(platform.z0)) >= 4.0: return platform
	return platforms[0]

func middle_of(platform: Dictionary) -> Vector2:
	return Vector2((float(platform.x0) + float(platform.x1)) * 0.5, (float(platform.z0) + float(platform.z1)) * 0.5)

## The way the course runs at the platform (level-local x, z, a unit vector): the segment of the path nearest to it.
func course_heading(at: Vector2) -> Vector2:
	var path: PackedVector3Array = data.path
	var best := 0
	var best_distance := INF
	for index in path.size() - 1:
		var a := Vector2(path[index].x, path[index].z)
		var b := Vector2(path[index + 1].x, path[index + 1].z)
		var near := Geometry2D.get_closest_point_to_segment(at, a, b)
		if near.distance_to(at) < best_distance:
			best_distance = near.distance_to(at)
			best = index
	var way := Vector2(path[best + 1].x - path[best].x, path[best + 1].z - path[best].z).normalized()
	return Vector2(snappedf(way.x, 1.0), snappedf(way.y, 1.0)).normalized() if absf(absf(way.x) - absf(way.y)) > 0.2 else way

func make_rig(at: Vector3, state: Dictionary) -> Node3D:
	var rig: Node3D = CharRig.new()
	holder.add_child(rig)
	rig.setup(0, {})
	rig.global_position = origin + at
	rig.snap(state)
	for i in 3: rig.update(DT, state)
	return rig

func look(eye: Vector3, at: Vector3, fov: float) -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = fov
	camera.global_position = origin + eye
	camera.look_at(origin + at, Vector3.UP)

func grab(name: String) -> bool:
	await frames(3)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s%s.png" % [shots, prefix, name]
	var saved := image.save_png(file) == OK
	print("EDGE_FRAMES shot %s %s %dx%d" % [file.get_file(), saved, image.get_width(), image.get_height()])
	return saved

func state_of(heading: Vector2, velocity: Vector3, grounded: bool) -> Dictionary:
	return {"velocity": velocity, "grounded": grounded, "yaw": atan2(-heading.x, -heading.y), "carrying": false}

func approach(platform: Dictionary) -> bool:
	var centre := middle_of(platform)
	var top := float(platform.top)
	var heading := course_heading(centre)
	var from := centre - heading * 5.2
	var rig := make_rig(Vector3(from.x, top + 0.85, from.y), state_of(heading, Vector3(heading.x * 4.5, 3.0, heading.y * 4.5), false))
	var eye := from - heading * 6.0
	look(Vector3(eye.x, top + 3.4, eye.y), Vector3(centre.x, top - 0.3, centre.y), 60.0)
	var saved := await grab("approach")
	rig.queue_free()
	return saved

func close(platform: Dictionary) -> bool:
	var centre := middle_of(platform)
	var top := float(platform.top)
	var heading := course_heading(centre)
	var rig := make_rig(Vector3(centre.x, top, centre.y), state_of(heading, Vector3.ZERO, true))
	var near: Dictionary = near_pill(platform, heading)
	var pivot: Vector3 = near.pivot
	var right := Vector2(-heading.y, heading.x)
	var eye := Vector2(pivot.x, pivot.z) - heading * 3.3 + right * 1.8
	look(Vector3(eye.x, top + 1.8, eye.y), Vector3(centre.x, top + 0.25, centre.y) - Vector3(heading.x, 0.0, heading.y) * 0.6, 62.0)
	var saved := await grab("close")
	rig.queue_free()
	return saved

## The cushion on the side the course comes from.
func near_pill(platform: Dictionary, heading: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dot := -2.0
	for index: int in platform.pills:
		var pill: Dictionary = data.edge_bumpers.pills[index]
		var dot := Vector2((pill.out as Vector3).x, (pill.out as Vector3).z).dot(-heading)
		if dot > best_dot:
			best_dot = dot
			best = pill
	return best

func overhead() -> bool:
	var frame := RaceWorld.footprint(data)
	var rect: Rect2 = frame.rect
	var centre := rect.get_center() if span <= 0.0 else focus
	var size := maxf(rect.size.y, rect.size.x * 9.0 / 16.0) + 16.0 if span <= 0.0 else span
	var y_top: float = frame.y_top
	var y_low: float = frame.y_low
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.near = 1.0
	camera.global_position = origin + Vector3(centre.x, y_top + 60.0, centre.y)
	camera.look_at(origin + Vector3(centre.x, y_low, centre.y), Vector3(0.0, 0.0, -1.0))
	var saved := await grab("overhead_%d%s" % [level_number, "" if span <= 0.0 else "_section"])
	var list: Array = []
	var bumpered := {}
	for platform: Dictionary in data.edge_bumpers.platforms: bumpered[int(platform.index)] = true
	for candidate: Dictionary in EdgeBumpers.candidate_platforms(data):
		var low := camera.unproject_position(origin + Vector3(float(candidate.x0), float(candidate.top), float(candidate.z0)))
		var high := camera.unproject_position(origin + Vector3(float(candidate.x1), float(candidate.top), float(candidate.z1)))
		list.append({"index": int(candidate.index), "bumpers": bumpered.has(int(candidate.index)), "x0": minf(low.x, high.x), "y0": minf(low.y, high.y), "x1": maxf(low.x, high.x), "y1": maxf(low.y, high.y)})
	var pill_lines: Array = []
	for pill: Dictionary in data.edge_bumpers.pills:
		var from_a := camera.unproject_position(origin + (pill.a as Vector3))
		var to_b := camera.unproject_position(origin + (pill.b as Vector3))
		pill_lines.append({"ax": from_a.x, "ay": from_a.y, "bx": to_b.x, "by": to_b.y})
	var file := FileAccess.open("%s/%soverhead_%d%s.json" % [shots, prefix, level_number, "" if span <= 0.0 else "_section"], FileAccess.WRITE)
	file.store_string(JSON.stringify({"level": level_number, "candidates": list, "pills": pill_lines, "pixels_per_m": float(root.size.y) / size}))
	file.close()
	return saved

## A courier dropped DROP m over the deck at SPEED m/s along the course on the middle of the platform (or just inside its near cushion): a frame every STRIDE ticks.
func strip(platform: Dictionary, at_edge: bool) -> bool:
	var centre := middle_of(platform)
	var top := float(platform.top)
	var heading := course_heading(centre)
	var aim := centre
	if at_edge:
		var near: Dictionary = near_pill(platform, heading)
		var pivot: Vector3 = near.pivot
		var out: Vector3 = near.out
		aim = Vector2(pivot.x, pivot.z) - Vector2(out.x, out.z) * 0.3
	var reach := SPEED * sqrt(2.0 * DROP / Motion.GRAVITY)
	var start := aim - heading * reach
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	var yaw := atan2(-heading.x, -heading.y)
	motion.reset(body, origin + Vector3(start.x, top + DROP, start.y), yaw)
	body.velocity = Vector3(heading.x * SPEED, 0.0, heading.y * SPEED)
	var rig := make_rig(start_point(start, top + DROP), state_of(heading, body.velocity, false))
	var right := Vector2(-heading.y, heading.x)
	var spot := centre - heading * (1.0 if not at_edge else 2.0)
	var eye := spot + right * 7.0
	look(Vector3(eye.x, top + 2.6, eye.y), Vector3(spot.x, top + 1.0, spot.y), 54.0)
	world.set_clock(0.0)
	world.reset_effects()
	var bumped_at := -1
	var landed_at := -1
	var shot := 0
	var saved_all := true
	for tick in STRIP_FROM + STRIDE * STRIP_FRAMES:
		await physics_frame
		world.advance(DT)
		var effect: Dictionary = world.effects_at(k, 0, body.global_position)
		if not effect.is_empty():
			if str(effect.kind) == "cushion" and bumped_at < 0: bumped_at = tick
			motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
		var move := Vector2.ZERO
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if bumped_at < 0:
			if landed_at < 0: move = heading
			elif speed > 0.5: move = -heading # the player brakes after landing
		motion.step(body, {"move": move}, DT)
		if motion.grounded and landed_at < 0 and tick > 2: landed_at = tick
		rig.global_position = body.global_position
		rig.update(DT, state_of(heading, body.velocity, motion.grounded))
		if tick >= STRIP_FROM and (tick - STRIP_FROM) % STRIDE == 0:
			camera.look_at(origin + Vector3(spot.x, top + 0.9, spot.y), Vector3.UP)
			RenderingServer.force_draw(false)
			var image := root.get_texture().get_image()
			var file := "%s/%sstrip_%s_%02d.png" % [shots, prefix, "edge" if at_edge else "centre", shot]
			saved_all = (image.save_png(file) == OK) and saved_all
			print("EDGE_FRAMES strip %s tick %d y %.2f bumped %s landed %s" % [file.get_file(), tick, body.global_position.y - origin.y - top, str(bumped_at), str(landed_at)])
			shot += 1
	rig.queue_free()
	body.queue_free()
	return saved_all and (bumped_at >= 0) == at_edge

func start_point(start: Vector2, y: float) -> Vector3:
	return Vector3(start.x, y, start.y)
