extends SceneTree
## Frames of a level with `"world": "daylight"` (style/race_world.gd) with hand-placed cameras: the real LevelWorld (the level's own party-look blocks and hazards, the daylight, the race
## world) and the real character rig on the start. Shots (level-local framings, computed from the level's footprint): `behind` (behind the start, looking along the course), `over` (above
## and beside the whole course, at an angle), `side` (low, beside the course, looking across it at the skyline), `below` (under the lowest floor, looking down at the neon floor), `far`
## (a long look along the course from high behind the start), `hazard_<kind>` (a close look at the first spin, slide / lift and push hazard of the level). Offscreen binary only, never windowed (ONE render at a time machine-wide, see tools/modes/show_frames.gd):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1152x720 \
##     --path demo -s "$PWD/tools/race_world_frames.gd" -- --shots=<dir> [--dir=res://levels] [--level=30] [--prefix=daylight_] [--only=behind,over] [--cam=<ex,ey,ez,lx,ly,lz[,fov]>]
##   `--cam` adds the shot `cam` (an eye and a look point in the level's own coordinates, optional field of view; the shot name is `--cam-name`, default `cam`), e.g. the court-edge view of the
##   double-rim report: `--level=30 --cam=14,9,-116,18,0,-132,60 --cam-name=court1_edge --only=court1_edge`.
## Prints RACE_FRAMES lines with the mean luma and mean HSV saturation of every picture.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const RaceWorld := preload("res://style/race_world.gd")

var shots := ""
var prefix := "daylight_"
var dir := "res://levels"
var level_number := 30
var only: PackedStringArray = []
var cam: PackedFloat64Array = []
var cam_name := "cam"
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--dir="): dir = argument.trim_prefix("--dir=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--cam="): cam = PackedFloat64Array(Array(argument.trim_prefix("--cam=").split(",")).map(func(v: String) -> float: return v.to_float()))
		if argument.begins_with("--cam-name="): cam_name = argument.trim_prefix("--cam-name=")
	create_timer(150.0).timeout.connect(func() -> void:
		print("RACE_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

## Mean luma (Rec.709 weights, 8-bit values) and mean HSV saturation of an image.
static func measure(image: Image) -> Vector2:
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	var data := small.get_data()
	var luma := 0.0
	var saturation := 0.0
	var count := data.size() / 3
	for k in count:
		var r := float(data[k * 3])
		var g := float(data[k * 3 + 1])
		var b := float(data[k * 3 + 2])
		luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
		var high := maxf(r, maxf(g, b))
		saturation += 0.0 if high <= 0.0 else (high - minf(r, minf(g, b))) / high
	return Vector2(luma / count, saturation / count)

func run() -> void:
	if shots == "":
		print("RACE_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = dir
	holder.add_child(world)
	await world.build("local")
	var level := level_number - 1
	if level < 0 or level >= world.level_count() or not RaceWorld.wanted(world._levels[level].data):
		print("RACE_FRAMES FAIL level ", level_number, " has no world daylight (", dir, ")")
		quit(1)
		return
	camera = Camera3D.new()
	camera.far = 4000.0 # as the game camera (Camera3D default); the candy world reaches 2600 m (the cloud wall)
	holder.add_child(camera)
	camera.current = true
	world.set_active_level(level)
	var data: Dictionary = world._levels[level].data
	var frame := RaceWorld.footprint(data)
	var rect: Rect2 = frame.rect
	var middle := rect.get_center()
	var big := maxf(rect.size.x, rect.size.y)
	var y_top: float = frame.y_top
	var y_low: float = frame.y_low
	var path: PackedVector3Array = data.path
	var ahead: Vector3 = path[mini(3, path.size() - 1)] if path.size() > 1 else Vector3(0.0, 0.0, -10.0)
	var heading := Vector3(ahead.x, 0.0, ahead.z).normalized()
	var start: Vector3 = data.start
	var specs := {
		"behind": {"eye": start - heading * 8.0 + Vector3(0.0, 4.2, 0.0), "look": start + heading * 30.0 + Vector3(0.0, 1.0, 0.0), "fov": 64.6},
		"over": {"eye": Vector3(middle.x + big * 0.35, y_top + big * 0.38 + 10.0, middle.y + rect.size.y * 0.5 + 20.0), "look": Vector3(middle.x, y_low, middle.y), "fov": 60.0},
		"side": {"eye": Vector3(rect.position.x + 2.0, y_low + 3.0, middle.y + rect.size.y * 0.25), "look": Vector3(rect.end.x, y_top + 12.0, middle.y - rect.size.y * 0.25), "fov": 70.0},
		"below": {"eye": Vector3(start.x, y_low - 6.0, start.z + 12.0), "look": Vector3(middle.x, y_low - 30.0, middle.y), "fov": 70.0},
		"far": {"eye": start - heading * 12.0 + Vector3(0.0, y_top + 30.0, 0.0), "look": start + heading * 90.0, "fov": 60.0},
	}
	var seen := {}
	for hazard: Dictionary in data.hazards: # a close view of the first hazard of each kind (spin bars, a ride platform, a push pad): their daylight look
		var kind := str(hazard.k)
		if kind in ["spin", "slide", "lift", "push"] and not seen.has(kind) and not (kind == "slide" and bool(hazard.hit)):
			seen[kind] = true
			var at: Vector3 = hazard.pivot
			specs["hazard_" + kind] = {"eye": at + Vector3(4.5, 4.0, 7.0), "look": at, "fov": 60.0}
	if cam.size() >= 6:
		specs[cam_name] = {"eye": Vector3(cam[0], cam[1], cam[2]), "look": Vector3(cam[3], cam[4], cam[5]), "fov": cam[6] if cam.size() > 6 else 60.0}
	var done := 0
	for name: String in specs:
		if only.is_empty() or name in only: done += await take(name, specs[name], level)
	print("RACE_FRAMES ok=", done > 0, " footprint ", rect, " y_top ", y_top, " y_low ", y_low)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)

func take(name: String, spec: Dictionary, level: int) -> int:
	var origin: Vector3 = world.level_origin(level)
	world.set_clock(1.0)
	var data: Dictionary = world._levels[level].data
	var start: Vector3 = data.start
	var pegs: Array = []
	var seat := 0
	for offset: Vector3 in [Vector3(0.0, 0.05, 0.0), Vector3(-1.75, 0.05, 0.0), Vector3(1.75, 0.05, 0.0)]:
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(seat, {})
		rig.global_position = origin + start + offset
		var motion := {"velocity": Vector3.ZERO, "grounded": true, "yaw": float(data.start_yaw), "carrying": false}
		rig.snap(motion)
		for i in 3: rig.update(1.0 / 60.0, motion)
		pegs.append(rig)
		seat += 1
	camera.fov = float(spec.fov)
	camera.global_position = origin + (spec.eye as Vector3)
	camera.look_at(origin + (spec.look as Vector3), Vector3.UP)
	await frames(5)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s%s.png" % [shots, prefix, name]
	var saved := image.save_png(file) == OK
	var measured := measure(image)
	print("RACE_FRAMES shot %s %s %dx%d luma %.1f sat %.3f" % [file.get_file(), saved, image.get_width(), image.get_height(), measured.x, measured.y])
	for rig: Node in pegs: rig.queue_free()
	return 1 if saved else 0
