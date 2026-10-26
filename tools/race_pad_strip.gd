extends SceneTree
## A motion strip of a launch pad being stepped on: one scripted courier walks onto a push pad of a race level (level 29's `pad_a1` by default), the level world's
## `effects_at` (the authority path, what game_run.gd feeds every physics tick) launches it and presses the button, the courier then flies on its launch for a moment; a
## picture every STEP frames. `--observe` drives the press from `observe_pads` instead (what a machine that only SEES the courier does). Offscreen binary only, never windowed,
## ONE render at a time machine-wide (lockf render.lock):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 640x360 \
##     --path demo -s "$PWD/tools/race_pad_strip.gd" -- --shots=<dir> [--level=29] [--pad=pad_a1] [--observe] [--frames=24] [--step=2]
## `--followcam[=air|frozen] [--land=<level-local floor y>]` shoots from the PLAYER's camera instead (game/follow_camera.gd, the stage view of the race levels, the one game_run.gd runs: yaw behind the throw,
## default pitch) with the ordinary motion's gravity (17); `air` (the default) is the race levels' air follow, `frozen` the tile rounds' frozen air (the picture before the air follow). The courier lands on the floor `--land`
## (default: the pad's own floor) and stands. Prints RACE_PAD_CAM lines: the frame, the camera's height, the courier's feet's screen y (0 top .. 1 bottom) and its head's.
## Prints RACE_PAD lines: the frame, the courier's feet, whether a launch fired, the button's depth; `RACE_PAD ok` when the button went down by more than 0.1 m within 0.2 s of the
## launch and was back at rest at the end, `RACE_PAD FAIL ...` otherwise (exit 1).
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const GRAVITY := 28.0
const Motion := preload("res://courier/courier_motion.gd")
const FollowCamera := preload("res://game/follow_camera.gd")

var shots := ""
var level_number := 29
var pad_id := "pad_a1"
var observe := false
var followcam := ""
var land_y := INF
var frames_total := 24
var step := 2
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--pad="): pad_id = argument.trim_prefix("--pad=")
		if argument.begins_with("--frames="): frames_total = int(argument.trim_prefix("--frames="))
		if argument.begins_with("--step="): step = int(argument.trim_prefix("--step="))
		if argument == "--observe": observe = true
		if argument == "--followcam": followcam = "air"
		if argument.begins_with("--followcam="): followcam = argument.trim_prefix("--followcam=")
		if argument.begins_with("--land="): land_y = float(argument.trim_prefix("--land="))
	create_timer(300.0).timeout.connect(func() -> void:
		print("RACE_PAD FAIL timed out")
		quit(1))
	run.call_deferred()

func run() -> void:
	if shots == "":
		print("RACE_PAD needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	var level := level_number - 1
	world.set_active_level(level)
	world.set_clock(5.0)
	var launcher: Dictionary = {}
	for candidate: Dictionary in world._levels[level].launchers:
		if str(candidate.h.id) == pad_id: launcher = candidate
	if launcher.is_empty():
		print("RACE_PAD FAIL no pad ", pad_id)
		quit(1)
		return
	var h: Dictionary = launcher.h
	var origin: Vector3 = world.level_origin(level)
	var pivot: Vector3 = origin + (h.pivot as Vector3)
	var floor_y := pivot.y - 1.0
	var throw: Vector3 = h.v
	var flat := Vector3(throw.x, 0.0, throw.z)
	var heading: Vector3 = flat.normalized() if flat.length() > 0.5 else Vector3.FORWARD
	var pad: Node = (launcher.area as Node).get_node_or_null("LaunchPad")
	if pad == null or not pad.has_method("press"):
		print("RACE_PAD FAIL pad of ", pad_id, " has no button")
		quit(1)
		return
	camera = Camera3D.new()
	camera.far = 600.0
	camera.fov = 55.0
	holder.add_child(camera)
	camera.current = true
	var side := heading.cross(Vector3.UP).normalized()
	var follow: RefCounted = null
	var gravity := GRAVITY
	var landing := -INF
	if followcam != "":
		follow = FollowCamera.new()
		follow.configure(camera)
		follow.set_first_person(false)
		follow.set_stage_view(true, followcam == "air")
		camera.fov = FollowCamera.STAGE_FOV
		gravity = Motion.GRAVITY
		landing = origin.y + (land_y if land_y != INF else floor_y - origin.y)
	else:
		camera.global_position = Vector3(pivot.x, floor_y, pivot.z) + side * 4.0 - heading * 0.5 + Vector3(0.0, 1.9, 0.0)
		camera.look_at(Vector3(pivot.x, floor_y, pivot.z) + heading * 1.0 + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var yaw := atan2(-heading.x, -heading.z)
	var rig: Node3D = CharRig.new()
	holder.add_child(rig)
	rig.setup(0, {})
	var feet := Vector3(pivot.x, floor_y, pivot.z) - heading * 2.6 # 0.4 s of walking before the courier reaches the volume at 5 m/s
	var velocity := heading * 5.0
	var delta := 1.0 / 60.0
	var launched_at := -1
	var depth_at_launch := 0.0
	var peak := 0.0
	var depth := 0.0
	var button := pad.get("button") as Node3D
	var images: Array[String] = []
	await physics_frame
	for frame in frames_total * step:
		feet += velocity * delta
		if launched_at >= 0 and (landing == -INF or velocity != Vector3.ZERO):
			velocity.y -= gravity * delta
			if landing > -INF and velocity.y < 0.0 and feet.y <= landing:
				feet.y = landing
				velocity = Vector3.ZERO
		var effect := {}
		if observe: # a machine that only sees the courier: the press comes from its position alone; the flight is scripted here (the owner's machine would simulate it)
			world.observe_pads(level, 0, feet)
			if launched_at < 0 and Vector2(feet.x - pivot.x, feet.z - pivot.z).length() < 1.0: effect = {"v": throw}
		else:
			effect = world.effects_at(level, 0, feet)
		if not effect.is_empty() and launched_at < 0:
			launched_at = frame
			velocity = effect.v
			print("RACE_PAD launch at frame ", frame, " v ", effect.v)
		var grounded := launched_at < 0 or (landing > -INF and velocity == Vector3.ZERO)
		var motion := {"velocity": velocity, "grounded": grounded, "yaw": atan2(-heading.x, -heading.z), "carrying": false}
		rig.global_position = feet
		if frame == 0: rig.snap(motion)
		rig.update(delta, motion)
		if follow != null:
			follow.update(delta, feet + Vector3(0.0, 1.0, 0.0), yaw, deg_to_rad(FollowCamera.STAGE_PITCH_DEFAULT), null, {"grounded": grounded, "run": Vector2(velocity.x, velocity.z).length() / float(Motion.STAGE_FEEL.walk)})
		await process_frame
		depth = -button.position.y
		peak = maxf(peak, depth)
		if launched_at >= 0 and frame - launched_at == 12: depth_at_launch = depth
		if frame % step == 0:
			RenderingServer.force_draw(false)
			var image := root.get_texture().get_image()
			var file := "%s/pad_%02d.png" % [shots, frame / step]
			image.save_png(file)
			images.append(file)
			if follow != null:
				var size := root.get_visible_rect().size
				print("RACE_PAD_CAM frame %d camera_y %.2f feet_y %.2f screen_feet %.3f screen_head %.3f" % [frame, camera.global_position.y, feet.y, camera.unproject_position(feet).y / size.y, camera.unproject_position(feet + Vector3(0.0, 1.8, 0.0)).y / size.y])
			print("RACE_PAD frame %d feet %s launched %s depth %.3f" % [frame, str(feet), str(launched_at >= 0), depth])
	var ok := launched_at >= 0 and depth_at_launch > 0.1 and peak > 0.1 and absf(depth) < 0.002
	print("RACE_PAD ", "ok" if ok else "FAIL", " launched_at=", launched_at, " depth_12_frames_after=%.3f peak=%.3f end=%.3f" % [depth_at_launch, peak, depth])
	holder.queue_free()
	await process_frame
	quit(0 if ok else 1)
