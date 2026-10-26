extends SceneTree
## Camera clearance sweep: nothing of the look may sit between the follow camera and the player. For every sample pose of the game's own camera (race levels: the stage view of
## game/follow_camera.gd behind a courier running the level's route; the lobby: the shoulder view) this renders the real scene (real LevelWorld, real materials and shaders, so a piece that
## dissolves near the camera really is gone) against a flat magenta background (no sky, no fog, linear tonemap) with the camera's far plane pulled in, and counts the share of the screen that
## is not background: `cov4` = the share covered by geometry NOT dissolved within 4 m of the camera (the real distance to the eye: the screen is cut in RINGS of equal ray length, each ring is
## rendered with the far plane at 4 m / ring factor, so a piece at the corner of the screen counts only when it is nearer than 4 m to the eye, with at most 13 % slack on the far side of a ring);
## `cov8` = the same share for the depth along the view axis under 8 m (information: what the dither still leaves between the 4 m ring and the 7.5 m "whole" distance).
## Anything of the course counts: floors, walls, posts, beams, decor.
## Poses per route sample (every --step m of the route): lateral offset of the courier from the route (--lat, default -2.5,0,2.5 m), orbit yaw off the heading (--yaw, default 0,55,-55 degrees,
## the stage view is a free orbit) and the standing and running pitch (12.4 / 21 degrees). The lobby: a grid of standing spots every --step m over the yard, four yaws, the shoulder view.
## Pass = every frame has cov4 <= --limit (default 0.20); the tool also lists the frames above --note (default 0.01: any visible intrusion). Exit 1 when a frame is over the limit.
## Offscreen binary only, never windowed, ONE render at a time machine-wide (the render lock):
##   <ItemsLab offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 640x360 --path demo -s "$PWD/tools/camera_clear_check.gd" -- --levels=29,30,31,32 --step=6 --shots=<dir> [--worst=3] [--limit=0.2] [--note=0.01] [--lat=-2.5,0,2.5] [--yaw=0,55,-55]
##   same with `--lobby --dir=$PWD/tools/level_testdata --step=3` for the lobby yard (`--levels` is not given).
## --why: for every saved worst frame, lists the meshes within 4 m of the camera (node path, what material: shader file or StandardMaterial3D, and whether it dissolves).
## --filter=<text>: only the poses whose label contains the text (a spot to look at again).
## --shots=<dir>: writes the --worst worst frames per level as full-view pictures (`<level>_<n>_view.png`, the courier on its spot) and their cut at 4 m depth along the view axis (`..._cut.png`, magenta = clear: a superset of what `cov4` counts at the screen's corners).
## Prints CAMCLEAR lines: one per frame over --note, the per level summary (frames, worst cov4 / cov8, count over the limit / over the note) and `CAMCLEAR ok=<bool>`.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const RaceWorld := preload("res://style/race_world.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")

const VIEW_FOV := 65.0          ## the stage view's vertical FOV (follow_camera.gd STAGE_FOV)
const VIEW_ARM := 12.1          ## m, the 3D distance from the camera to the courier's feet (STAGE_ARM)
const FEET_Y := 0.704           ## where the feet stand in the frame's height (STAGE_FEET_Y)
const PITCHES := [12.4, 21.0]   ## degrees: standing (STAGE_PITCH_DEFAULT) and at the full run (+ STAGE_RUN_PITCH)
const SHOULDER_FOV := 60.0      ## follow_camera.gd VERTICAL_FOV (the lobby's shoulder view)
const SHOULDER_ARM := 5.4
const SHOULDER_PITCH := 13.0
const COUNT_W := 320            ## the picture is counted at this size (nearest)
const COUNT_H := 180
const NEAR := 4.0
const MID := 8.0
const RINGS := 5                ## the screen's rings of equal ray length for `cov4`
const BACKGROUND := Color(1.0, 0.0, 1.0)

var out := ""
var levels: Array = []
var lobby := false
var level_dir := ""
var step := 6.0
var worst_count := 3
var limit := 0.20
var note := 0.01
var laterals: Array = [-2.5, 0.0, 2.5]
var yaws: Array = [0.0, 55.0, -55.0]
var world: Node3D
var holder: Node3D
var camera: Camera3D
var env := Environment.new()
var clipped := false
var over_limit := 0
var filter := ""
var why := false
var ring_pixels: Array[PackedInt32Array] = []
var ring_low: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): out = argument.trim_prefix("--shots=")
		if argument.begins_with("--levels="):
			for item in argument.trim_prefix("--levels=").split(","): levels.append(int(item))
		if argument == "--lobby": lobby = true
		if argument == "--why": why = true
		if argument.begins_with("--filter="): filter = argument.trim_prefix("--filter=")
		if argument.begins_with("--dir="): level_dir = argument.trim_prefix("--dir=")
		if argument.begins_with("--step="): step = float(argument.trim_prefix("--step="))
		if argument.begins_with("--worst="): worst_count = int(argument.trim_prefix("--worst="))
		if argument.begins_with("--limit="): limit = float(argument.trim_prefix("--limit="))
		if argument.begins_with("--note="): note = float(argument.trim_prefix("--note="))
		if argument.begins_with("--lat="):
			laterals = []
			for item in argument.trim_prefix("--lat=").split(","): laterals.append(float(item))
		if argument.begins_with("--yaw="):
			yaws = []
			for item in argument.trim_prefix("--yaw=").split(","): yaws.append(float(item))
	create_timer(3300.0).timeout.connect(func() -> void:
		print("CAMCLEAR FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await process_frame

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

## The eye of the stage view for a view axis pitched `pitch` degrees down, VIEW_ARM m (3D) from `feet`, behind it along `heading` (tools/look_shots.gd chase()).
static func chase(feet: Vector3, heading: Vector3, pitch: float) -> Vector3:
	var below := atan((2.0 * FEET_Y - 1.0) * tan(deg_to_rad(VIEW_FOV) * 0.5))
	var angle := deg_to_rad(pitch) + below
	return feet + Vector3(0.0, VIEW_ARM * sin(angle), 0.0) - heading * VIEW_ARM * cos(angle)

## [eye, look-at, fov] of the stage view behind `feet` for the orbit direction `heading`.
static func stage_pose(feet: Vector3, heading: Vector3, pitch: float) -> Array:
	var eye := chase(feet, heading, pitch)
	var axis := heading * cos(deg_to_rad(pitch)) - Vector3.UP * sin(deg_to_rad(pitch))
	return [eye, eye + axis * 10.0, VIEW_FOV]

## The shoulder view's pose behind a courier at `feet`, orbit direction `heading` (tools/lobby_frames.gd shoulder_view()); the arm is pulled in until the eye is inside `room` (the follow camera's
## shape cast against the yard walls: it never puts the camera behind a wall; it never comes closer than CLEAR_MIN = 0.9 m).
static func shoulder_pose(feet: Vector3, heading: Vector3, room: Rect2) -> Array:
	var back := 5.3
	while back > 0.9 and not room.grow(-0.3).has_point(Vector2(feet.x - heading.x * back, feet.z - heading.z * back)): back -= 0.1
	var eye := feet + Vector3(0.0, 3.4 * back / 5.3, 0.0) - heading * back
	var axis := heading * cos(deg_to_rad(SHOULDER_PITCH)) - Vector3.UP * sin(deg_to_rad(SHOULDER_PITCH))
	return [eye, eye + axis * 8.0, SHOULDER_FOV]

## The route's points at every `metres` of its length: [[point, heading]].
static func along(path: PackedVector3Array, metres: float) -> Array:
	var list: Array = []
	var run := 0.0
	var next_at := 0.0
	for k in path.size() - 1:
		var a := path[k]
		var b := path[k + 1]
		var length := a.distance_to(b)
		var heading := flat(b - a)
		if heading.length() < 0.5: continue
		while next_at <= run + length:
			list.append([a.lerp(b, (next_at - run) / maxf(length, 0.001)), heading])
			next_at += metres
		run += length
	return list

## The share of the screen covered by anything nearer than NEAR m to the eye (the true distance): per ring of ray length, see the header.
func covered_near() -> float:
	if ring_pixels.is_empty(): make_rings()
	var hits := 0
	for ring in RINGS:
		camera.far = NEAR / ring_low[ring]
		await frames(1)
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		image.resize(COUNT_W, COUNT_H, Image.INTERPOLATE_NEAREST)
		var data := image.get_data()
		for i: int in ring_pixels[ring]:
			if not is_background(data, i * 3): hits += 1
	return float(hits) / float(COUNT_W * COUNT_H)

## The pixels (counted at COUNT_W x COUNT_H) of each ring of equal ray length: factor sqrt(1 + (u tx)^2 + (v ty)^2), u and v in -1 .. 1, from 1 (the middle) to the corner's.
func make_rings() -> void:
	var half_height := tan(deg_to_rad(camera.fov) * 0.5)
	var half_width := half_height * float(COUNT_W) / float(COUNT_H)
	var corner := sqrt(1.0 + half_width * half_width + half_height * half_height)
	var rings: Array[PackedInt32Array] = []
	for ring in RINGS:
		rings.append(PackedInt32Array())
		ring_low.append(1.0 + (corner - 1.0) * float(ring) / float(RINGS))
	for y in COUNT_H:
		var v := (2.0 * (float(y) + 0.5) / float(COUNT_H) - 1.0) * half_height
		for x in COUNT_W:
			var u := (2.0 * (float(x) + 0.5) / float(COUNT_W) - 1.0) * half_width
			var factor := sqrt(1.0 + u * u + v * v)
			rings[clampi(floori((factor - 1.0) / (corner - 1.0) * float(RINGS)), 0, RINGS - 1)].append(y * COUNT_W + x)
	ring_pixels = rings

## Whether the pixel at byte `i` is the magenta background (the sky facets, additive, only lighten its green).
static func is_background(data: PackedByteArray, i: int) -> bool:
	return data[i] >= 245 and data[i + 1] < 200 and data[i + 2] >= 245

## The share of the screen covered by anything rendered with the far plane at `far` (planar depth along the view axis).
func covered(far: float) -> float:
	camera.far = far
	await frames(1)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.resize(COUNT_W, COUNT_H, Image.INTERPOLATE_NEAREST)
	var data := image.get_data()
	var hit := 0
	for i in range(0, data.size(), 3):
		if not is_background(data, i): hit += 1
	return float(hit) / float(COUNT_W * COUNT_H)

func pose(spec: Array, origin: Vector3) -> void:
	camera.fov = float(spec[2])
	camera.global_position = origin + (spec[0] as Vector3)
	camera.look_at(origin + (spec[1] as Vector3), Vector3.UP)

## Measures every pose of `poses` ([{label, spec, feet}], level-local) of one place; prints the frames over the note, saves the worst ones; returns the number over the limit.
func sweep(tag: String, poses: Array, origin: Vector3) -> int:
	var rows: Array = []
	camera.environment = env
	for entry: Dictionary in poses:
		if filter != "" and not str(entry.label).contains(filter): continue
		pose(entry.spec, origin)
		var near_share: float = await covered_near()
		var mid_share: float = await covered(MID)
		rows.append({"label": entry.label, "spec": entry.spec, "feet": entry.feet, "near": near_share, "mid": mid_share})
	camera.environment = null
	camera.far = 4000.0
	var worst_near := 0.0
	var worst_mid := 0.0
	var over := 0
	var noted := 0
	for row: Dictionary in rows:
		worst_near = maxf(worst_near, row.near)
		worst_mid = maxf(worst_mid, row.mid)
		if row.near > limit: over += 1
		if row.near > note:
			noted += 1
			if noted <= 60: print("CAMCLEAR frame %s %s cov4=%.3f cov8=%.3f" % [tag, row.label, row.near, row.mid])
	print("CAMCLEAR level %s frames=%d worst_cov4=%.3f worst_cov8=%.3f over_limit=%d over_note=%d" % [tag, rows.size(), worst_near, worst_mid, over, noted])
	over_limit += over
	if out != "":
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.near > b.near or (a.near == b.near and a.mid > b.mid)) # the worst by cov4, then by what the dither still leaves (cov8)
		for n in mini(worst_count, rows.size()):
			await save_view(tag, n, rows[n], origin)
	return over

func save_view(tag: String, n: int, row: Dictionary, origin: Vector3) -> void:
	var rig: Node3D = CharRig.new()
	holder.add_child(rig)
	rig.setup(0, {})
	rig.global_position = origin + (row.feet as Vector3)
	var stand := {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": false}
	rig.snap(stand)
	for i in 3: rig.update(1.0 / 60.0, stand)
	pose(row.spec, origin)
	camera.far = 4000.0
	await frames(6)
	RenderingServer.force_draw(false)
	var file := "%s/%s_%d_view.png" % [out, tag, n]
	root.get_texture().get_image().save_png(file)
	camera.environment = env
	camera.far = NEAR
	await frames(2)
	RenderingServer.force_draw(false)
	var cut := "%s/%s_%d_cut.png" % [out, tag, n]
	root.get_texture().get_image().save_png(cut)
	camera.environment = null
	camera.far = 4000.0
	rig.queue_free()
	print("CAMCLEAR saved %s cov4=%.3f %s" % [file.get_file(), row.near, row.label])
	if why: explain(origin + (row.spec[0] as Vector3))

func run() -> void:
	if levels.is_empty() and not lobby:
		print("CAMCLEAR needs --levels=29,30,... or --lobby")
		quit(2)
		return
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	if level_dir != "": world.level_dir = level_dir
	holder.add_child(world)
	await world.build("local")
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 4000.0
	holder.add_child(camera)
	camera.current = true
	if lobby: await run_lobby()
	else:
		for number: int in levels: await run_level(number)
	print("CAMCLEAR ok=%s over_limit=%d" % [over_limit == 0, over_limit])
	holder.queue_free()
	await process_frame
	quit(0 if over_limit == 0 else 1)

func run_level(number: int) -> void:
	var level := number - 1
	if level < 0 or level >= world.level_count() or not RaceWorld.wanted(world._levels[level].data):
		print("CAMCLEAR FAIL level ", number, " is not a daylight race level")
		over_limit += 1
		return
	world.set_active_level(level)
	world.set_clock(1.0)
	await frames(4)
	await physics_frame
	await physics_frame
	var data: Dictionary = world._levels[level].data
	var poses: Array = []
	for sample: Array in along(data.path, step):
		var heading: Vector3 = sample[1]
		var right := Vector3(-heading.z, 0.0, heading.x)
		for lateral: float in laterals:
			var feet: Vector3 = (sample[0] as Vector3) + right * lateral + Vector3(0.0, 0.05, 0.0)
			var floor_height: float = world.floor_y(level, world.level_origin(level) + feet) # the route's points are not always on the floor: the courier stands on it
			if is_finite(floor_height): feet.y = floor_height - world.level_origin(level).y + 0.05
			else: continue # no floor there (a gap beside the route): nobody stands there
			for yaw: float in yaws:
				var direction := heading.rotated(Vector3.UP, deg_to_rad(yaw))
				for pitch: float in PITCHES:
					poses.append({"label": "at=(%.0f,%.1f,%.0f) lat=%.1f yaw=%.0f pitch=%.1f" % [feet.x, feet.y, feet.z, lateral, yaw, pitch], "spec": stage_pose(feet, direction, pitch), "feet": feet})
	await sweep(str(number), poses, world.level_origin(level))

func run_lobby() -> void:
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	LobbySpace.ensure(holder, "local")
	world.set_active_level(-1)
	LobbySpace.sync(holder, "local", true)
	await frames(6)
	var room := WalkInLobby.interior_rect()
	var floor_y := WalkInLobby.spawn(0).y
	var poses: Array = []
	var x := room.position.x + 1.0
	while x <= room.end.x - 1.0:
		var z := room.position.y + 1.0
		while z <= room.end.y - 1.0:
			var feet := Vector3(x, floor_y, z)
			for yaw in [0.0, 90.0, 180.0, 270.0]:
				var direction := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(yaw))
				poses.append({"label": "at=(%.1f,%.1f) yaw=%.0f" % [x, z, yaw], "spec": shoulder_pose(feet, direction, room), "feet": feet})
			z += step
		x += step
	await sweep("lobby", poses, Vector3.ZERO)

## Prints the meshes whose bounding box is within NEAR m of `eye`, with what they are made of (see --why).
func explain(eye: Vector3) -> void:
	for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree(): continue
		var box: AABB = instance.global_transform * instance.get_aabb()
		var closest := Vector3(clampf(eye.x, box.position.x, box.end.x), clampf(eye.y, box.position.y, box.end.y), clampf(eye.z, box.position.z, box.end.z))
		if closest.distance_to(eye) >= NEAR: continue
		var made: PackedStringArray = []
		for surface in instance.mesh.get_surface_count():
			var material: Material = instance.get_surface_override_material(surface)
			if material == null: material = instance.mesh.surface_get_material(surface)
			if instance.material_override != null: material = instance.material_override
			if material is ShaderMaterial: made.append("%s near=%s" % [(material as ShaderMaterial).shader.resource_path.get_file(), (material as ShaderMaterial).get_shader_parameter("near_whole")])
			elif material is StandardMaterial3D: made.append("Standard fade=%d" % (material as StandardMaterial3D).distance_fade_mode)
			else: made.append(str(material))
		print("CAMCLEAR   near %.1f m %s [%s]" % [closest.distance_to(eye), holder.get_path_to(instance), ", ".join(made)])
