extends SceneTree
## Race-level frames from the show's own view camera (the "stage" view of follow_camera.gd: 12.1 m behind the courier's feet on a line
## that puts the feet at 70.4 % of the frame height, 65 degrees vertical FOV, pitch 12.4 degrees standing / 21 running) behind a courier on a daylight race level (`"world": "daylight"`),
## with the real character rig (character_rig.gd, the project's own demo/cast) and the real LevelWorld (the level's blocks, hazards, daylight, race world). Several levels in ONE run.
## Offscreen binary only, never windowed, ONE render at a time machine-wide (the render lock):
##   <ItemsLab offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/look_shots.gd" -- --shots=<dir> --plan=29:start:04_race_start,31:mid:05_race_mid,30:finish:06_race_finish [--dir=res://levels]
## --plan=<level file number>:<kind>:<file name without .png>,... ; kinds:
##   start   the start: eight couriers on the start line, the camera behind the middle one (standing pitch)
##   mid     the middle spin hazard of the level (else the middle hazard): three running couriers ~12 m before it, the camera behind (running pitch)
##   finish  the last stretch: three running couriers a few metres before the goal, the camera behind them
##   wide    the backdrop band: 16 m over the start, looking out over the course's side (31 degrees off the course, 7 degrees down, FOV 70), nobody on the course
## Prints LOOK_SHOTS lines (file, saved, size); exits non-zero when a picture was not saved.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const RaceWorld := preload("res://style/race_world.gd")

const VIEW_FOV := 65.0          ## the stage view's vertical FOV (follow_camera.gd STAGE_FOV)
const VIEW_ARM := 12.1          ## m, the 3D distance from the camera to the courier's feet (STAGE_ARM)
const FEET_Y := 0.704           ## where the feet stand in the frame's height (STAGE_FEET_Y)
const PITCH_STAND := 12.4       ## degrees, the view axis' downward pitch with the courier standing (STAGE_PITCH_DEFAULT)
const PITCH_RUN := 21.0         ## ... at the full run (STAGE_PITCH_DEFAULT + STAGE_RUN_PITCH)
const WIDE_PITCH := 7.0         ## degrees down, the `wide` view
const WIDE_FOV := 70.0
const RUN_SPEED := 12.6         ## m/s, a courier's run (the animation's pace)

var shots := ""
var dir := "res://levels"
var plan: Array = []
var world: Node3D
var holder: Node3D
var camera: Camera3D
var failed := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--dir="): dir = argument.trim_prefix("--dir=")
		if argument.begins_with("--plan="):
			for item in argument.trim_prefix("--plan=").split(","):
				var parts := item.split(":")
				if parts.size() == 3: plan.append({"level": int(parts[0]), "kind": parts[1], "name": parts[2]})
	create_timer(200.0).timeout.connect(func() -> void:
		print("LOOK_SHOTS FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

## The eye of the stage view for a view axis pitched `pitch` degrees down, VIEW_ARM m (3D) from `feet`, behind it along `heading`: the feet stand FEET_Y of the frame's height, so they
## are `below` degrees under the view axis and the eye is on the line from the feet at the angle pitch + below over the horizon (stage_frames.gd chase()).
static func chase(feet: Vector3, heading: Vector3, pitch: float) -> Vector3:
	var below := atan((2.0 * FEET_Y - 1.0) * tan(deg_to_rad(VIEW_FOV) * 0.5))
	var angle := deg_to_rad(pitch) + below
	return feet + Vector3(0.0, VIEW_ARM * sin(angle), 0.0) - heading * VIEW_ARM * cos(angle)

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

## The index of the path point nearest to `at` (horizontally).
static func nearest(path: PackedVector3Array, at: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in path.size():
		var d := Vector2(path[k].x - at.x, path[k].z - at.z).length()
		if d < best_d:
			best_d = d
			best = k
	return best

## The path point `metres` of path length before index `k` (k itself when the path is shorter) and the heading of the course there.
static func before(path: PackedVector3Array, k: int, metres: float) -> Array:
	var j := k
	var run := 0.0
	while j > 0 and run < metres:
		run += path[j].distance_to(path[j - 1])
		j -= 1
	var ahead := path[mini(j + 1, path.size() - 1)]
	var heading := flat(ahead - path[j])
	if heading.length() < 0.5: heading = Vector3(0.0, 0.0, -1.0)
	return [path[j], heading]

## [eye, look-at, fov, [[feet, heading, running]]] of one shot kind of the level `data`.
func make(kind: String, data: Dictionary) -> Array:
	var path: PackedVector3Array = data.path
	var start: Vector3 = data.start
	var yaw: float = data.start_yaw
	var start_heading := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(-start_heading.z, 0.0, start_heading.x)
	var who: Array = []
	match kind:
		"start":
			for k in 8:
				var column := (k % 5) - 2 if k < 5 else (k - 5) * 2 - 1
				var row := 0.0 if k < 5 else 1.9
				who.append([start + right * float(column) * 1.75 - start_heading * row + Vector3(0.0, 0.05, 0.0), start_heading, false])
			var feet: Vector3 = who[2][0]
			var eye := chase(feet, start_heading, PITCH_STAND)
			var axis := start_heading * cos(deg_to_rad(PITCH_STAND)) - Vector3.UP * sin(deg_to_rad(PITCH_STAND))
			return [eye, eye + axis * 10.0, VIEW_FOV, who]
		"wide":
			# high over the start, looking out over the course's side at the horizon band (the course in the lower part of the frame, nobody on it)
			var eye := start + Vector3(0.0, 16.0, 0.0) - start_heading * 6.0
			var level_axis := (start_heading * 0.8 + right * 0.6).normalized()
			var axis := level_axis * cos(deg_to_rad(WIDE_PITCH)) - Vector3.UP * sin(deg_to_rad(WIDE_PITCH))
			return [eye, eye + axis * 10.0, WIDE_FOV, who]
		"mid":
			var spins: Array = []
			var hazards: Array = data.hazards
			for k in hazards.size():
				if str(hazards[k].k) == "spin": spins.append(k)
			var at: int = spins[spins.size() / 2] if not spins.is_empty() else (hazards.size() / 2 if not hazards.is_empty() else -1)
			var target: Vector3 = path[path.size() / 2]
			if at >= 0 and hazards[at].has("pivot"): target = hazards[at].pivot
			var stop := nearest(path, target)
			var spot := before(path, stop, 12.0)
			return runners(spot[0], spot[1])
		"finish":
			var stop := path.size() - 1
			var spot := before(path, stop, 14.0)
			return runners(spot[0], spot[1])
	return []

## Three running couriers on the course at `feet`, heading `heading`, the stage view behind the middle one (running pitch).
func runners(feet: Vector3, heading: Vector3) -> Array:
	var right := Vector3(-heading.z, 0.0, heading.x)
	var who: Array = [
		[feet + Vector3(0.0, 0.05, 0.0), heading, true],
		[feet + right * -2.4 + heading * 5.5 + Vector3(0.0, 0.05, 0.0), heading, true],
		[feet + right * 2.6 + heading * 9.0 + Vector3(0.0, 0.05, 0.0), heading, true],
	]
	var eye := chase(feet + Vector3(0.0, 0.05, 0.0), heading, PITCH_RUN)
	var axis := heading * cos(deg_to_rad(PITCH_RUN)) - Vector3.UP * sin(deg_to_rad(PITCH_RUN))
	return [eye, eye + axis * 10.0, VIEW_FOV, who]

func run() -> void:
	if shots == "" or plan.is_empty():
		print("LOOK_SHOTS needs --shots=<dir> --plan=<level>:<kind>:<name>,...")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = dir
	holder.add_child(world)
	await world.build("local")
	camera = Camera3D.new()
	camera.far = 4000.0 # as the game camera (Camera3D default); the candy world reaches 2600 m (the cloud wall)
	camera.fov = VIEW_FOV
	holder.add_child(camera)
	camera.current = true
	for item: Dictionary in plan:
		var level: int = int(item.level) - 1
		if level < 0 or level >= world.level_count() or not RaceWorld.wanted(world._levels[level].data):
			print("LOOK_SHOTS FAIL level ", item.level, " is not a daylight race level")
			failed += 1
			continue
		world.set_active_level(level)
		world.set_clock(1.0)
		var data: Dictionary = world._levels[level].data
		var spec: Array = make(str(item.kind), data)
		if spec.is_empty():
			print("LOOK_SHOTS FAIL unknown kind ", item.kind)
			failed += 1
			continue
		await take(str(item.name), spec, level)
	holder.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)

func take(shot: String, spec: Array, level: int) -> void:
	var origin: Vector3 = world.level_origin(level)
	var pegs: Array = []
	var seat := 0
	for entry: Array in spec[3]:
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(seat, {})
		rig.global_position = origin + (entry[0] as Vector3)
		var heading: Vector3 = entry[1]
		var motion := {"velocity": heading * RUN_SPEED if bool(entry[2]) else Vector3.ZERO, "grounded": true, "yaw": atan2(-heading.x, -heading.z), "carrying": false}
		rig.snap(motion)
		for i in 24 if bool(entry[2]) else 3: rig.update(1.0 / 60.0, motion)
		pegs.append(rig)
		seat += 1
	camera.fov = float(spec[2])
	camera.global_position = origin + (spec[0] as Vector3)
	camera.look_at(origin + (spec[1] as Vector3), Vector3.UP)
	await frames(6)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s.png" % [shots, shot]
	var saved := image.save_png(file) == OK
	print("LOOK_SHOTS shot %s %s %dx%d" % [file.get_file(), saved, image.get_width(), image.get_height()])
	if not saved: failed += 1
	for rig: Node in pegs: rig.queue_free()
