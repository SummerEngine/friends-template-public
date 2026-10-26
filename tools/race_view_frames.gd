extends SceneTree
## Frames of a race level from a list of views (written by `tools/gen_level_31.py --emit-views`), one picture per view:
## the real LevelWorld (blocks, hazards posed at the view's clock, belts, daylight world) and one character on the feet of the view. A view is
## {name, feet [x, y, z] level-local, dir [dx, dz], clock, back, up, ahead}: the camera stands `back` m behind the feet along -dir and `up` m over them, looks at `ahead` m in
## front of the feet (0.8 m up, plus the optional `look_up` m: a tipped-up view of the sky), vertical FOV 65. Offscreen binary only, never windowed, ONE render at a time machine-wide (lockf render.lock):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 960x540 \
##     --path demo -s "$PWD/tools/race_view_frames.gd" -- --views=/tmp/v29.json --shots=<dir> [--only=sec01,sec07] [--stagecam]
## `--stagecam` puts the camera where the stage view (game/follow_camera.gd `_update_stage`, the view a race level with `"camera": "stage"` plays in) stands for a courier
## running along `dir`: the arm STAGE_ARM from the feet, tipped to the running pitch; a view whose name contains `flyover` keeps its own pose.
## Prints RACE_VIEW lines (file, luma) and `RACE_VIEW ok=<n>`.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const FollowCamera := preload("res://game/follow_camera.gd")

var shots := ""
var views_file := ""
var only: PackedStringArray = []
var stagecam := false
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--views="): views_file = argument.trim_prefix("--views=")
		if argument == "--stagecam": stagecam = true
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
	create_timer(600.0).timeout.connect(func() -> void:
		print("RACE_VIEW FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(views_file))
	if shots == "" or not parsed is Dictionary:
		print("RACE_VIEW needs --shots=<dir> --views=<json>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	var level := int(parsed.level) - 1
	camera = Camera3D.new()
	camera.far = 4000.0 # as the game camera
	holder.add_child(camera)
	camera.current = true
	world.set_active_level(level)
	var done := 0
	for view: Dictionary in parsed.views:
		var wanted := only.is_empty()
		for prefix in only:
			if str(view.name).begins_with(prefix): wanted = true
		if wanted: done += await take(level, view)
	print("RACE_VIEW ok=", done)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)

func take(level: int, view: Dictionary) -> int:
	var origin: Vector3 = world.level_origin(level)
	world.set_clock(float(view.get("clock", 0.0)))
	var feet := Vector3(float(view.feet[0]), float(view.feet[1]), float(view.feet[2]))
	var dir := Vector3(float(view.dir[0]), 0.0, float(view.dir[1])).normalized()
	var rig: Node3D = CharRig.new()
	holder.add_child(rig)
	rig.setup(0, {})
	rig.global_position = origin + feet + Vector3(0.0, 0.05, 0.0)
	var motion := {"velocity": dir * 5.0, "grounded": true, "yaw": atan2(-dir.x, -dir.z), "carrying": false}
	rig.snap(motion)
	for i in 3: rig.update(1.0 / 60.0, motion)
	camera.fov = 65.0
	if stagecam and not str(view.name).contains("flyover"):
		var yaw := atan2(-dir.x, -dir.z)
		var tipped := deg_to_rad(FollowCamera.STAGE_PITCH_DEFAULT - FollowCamera.STAGE_RUN_PITCH)
		var below := atan((2.0 * FollowCamera.STAGE_FEET_Y - 1.0) * tan(deg_to_rad(FollowCamera.STAGE_FOV) * 0.5))
		camera.fov = FollowCamera.STAGE_FOV
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(tipped, yaw, 0.0)), origin + feet + Basis.from_euler(Vector3(tipped - below, yaw, 0.0)).z * FollowCamera.STAGE_ARM)
	else:
		camera.global_position = origin + feet - dir * float(view.get("back", 6.5)) + Vector3(0.0, float(view.get("up", 3.0)), 0.0)
		camera.look_at(origin + feet + dir * float(view.get("ahead", 4.0)) + Vector3(0.0, 0.8 + float(view.get("look_up", 0.0)), 0.0), Vector3.UP)
	await frames(5)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s.png" % [shots, str(view.name)]
	var saved := image.save_png(file) == OK
	print("RACE_VIEW shot %s %s %dx%d" % [file.get_file(), saved, image.get_width(), image.get_height()])
	rig.queue_free()
	return 1 if saved else 0
