extends SceneTree
## Frames of the candy world alone (style/candy_world.gd): a plain slab stands where the course would, the world around it, the daylight look's own sun, fill, grade and sky
## (style/candy_light.gd `rig`). Shots look like the gameplay cameras (a few metres up and behind, 60 degrees, the horizon in the frame) from a low and a high course.
## Offscreen binary only, never windowed (ONE render at a time machine-wide):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/candy_world_frames.gd" -- --shots=<dir> [--prefix=world_] [--sea=slime|none] [--scale=1.0] [--seed=1] [--only=low,high,side,far] [--stats]
## `low`: 6 m over a floor 12 m over the sea (a race), `high`: 60 m over the sea (a tile round), `side`: low and across the slab, `far`: long look from above. Prints WORLD_FRAMES lines.
const CandyWorld := preload("res://style/candy_world.gd")
const Look := preload("res://style/candy_look.gd")
const CandyLight := preload("res://style/candy_light.gd")

var shots := ""
var prefix := "world_"
var sea := "slime"
var world_scale := 1.0
var seed_value := 1
var only: PackedStringArray = []
var stats := false
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--sea="): sea = argument.trim_prefix("--sea=")
		if argument.begins_with("--scale="): world_scale = argument.trim_prefix("--scale=").to_float()
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument == "--stats": stats = true
	create_timer(90.0).timeout.connect(func() -> void:
		print("WORLD_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(shots)
	var root := Node3D.new()
	get_root().add_child(root)
	var scale_factor := world_scale
	CandyLight.rig(root, Look.SUN_AZIMUTH, scale_factor)
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.far = 5000.0
	root.add_child(camera)
	camera.current = true

	var slab := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40.0, 1.0, 60.0)
	slab.mesh = box
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#1aa8f4")
	paint.roughness = 0.4
	slab.material_override = paint
	slab.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(slab)
	var opts := {"centre": Vector3.ZERO, "floor_y": 0.0, "course_radius": 36.0, "world_scale": world_scale, "seed": seed_value, "sea": sea, "sea_y": -12.0, "view_y": 18.0, "quality": 2 if world_scale >= 1.0 else 0}
	var world := CandyWorld.build(opts)
	root.add_child(world)
	print("WORLD_FRAMES built in %.1f ms %s %s" % [float(world.get_meta("build_ms")), CandyWorld.stats(world), world.get_meta("build_parts")])
	var views := {
		"low": [Vector3(0.0, 6.0, 40.0), Vector3(0.0, 2.0, -60.0)],
		"side": [Vector3(30.0, 3.5, 10.0), Vector3(-200.0, 20.0, -150.0)],
		"far": [Vector3(0.0, 14.0, 60.0), Vector3(0.0, 0.0, -300.0)],
		"top": [Vector3(0.0, 330.0, 0.5), Vector3(0.0, 0.0, 0.0)],
		"around": [Vector3(0.0, 8.0, 0.0), Vector3(300.0, 30.0, 40.0)],
		"behind": [Vector3(0.0, 8.0, 0.0), Vector3(-300.0, 30.0, -60.0)],
	}
	for name: String in views:
		if not only.is_empty() and not only.has(name): continue
		await _shoot(name, views[name][0], views[name][1])
	if only.is_empty() or only.has("high"):
		slab.position.y = 47.5
		world.queue_free()
		var tall := CandyWorld.build({"centre": Vector3.ZERO, "floor_y": 47.0, "course_radius": 36.0, "world_scale": world_scale, "seed": seed_value, "sea": sea, "sea_y": -12.0, "view_y": 70.0, "quality": opts.quality})
		root.add_child(tall)
		await _shoot("high", Vector3(0.0, 62.0, 40.0), Vector3(0.0, 40.0, -50.0))
		await _shoot("high_far", Vector3(0.0, 62.0, 40.0), Vector3(0.0, 30.0, -400.0))
	quit(0)

func _shoot(label: String, eye: Vector3, target: Vector3) -> void:
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)
	for _i in 4: await process_frame
	var image := get_root().get_texture().get_image()
	var path := "%s/%s%s.png" % [shots, prefix, label]
	image.save_png(path)
	print("WORLD_FRAMES %s %s" % [label, path])
