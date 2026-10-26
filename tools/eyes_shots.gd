extends SceneTree
## Proof frames of the customizer's eye pictures: the FACE tab (the Eyes row) and a close-up of the character wearing each eye item.
## Offscreen only, never windowed:
##   lockf -k ~/.local/state/friends-slots/render.lock <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/eyes_shots.gd" -- --out=<dir> [--prefix=d_]
## Prints EYES_SHOTS lines.
const Rig := preload("res://character/character_rig.gd")
const Look := preload("res://character/look.gd")
const WardrobeUi := preload("res://character/wardrobe/wardrobe_ui.gd")
const CandyLight := preload("res://style/candy_light.gd")

const EYES := ["eyes_dot", "eyes_big", "eyes_heart", "eyes_spiral", "eyes_sleepy", "eyes_angry"]

var out := ""
var prefix := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--prefix="): prefix = a.trim_prefix("--prefix=")
	DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()

func frames(count: int) -> void:
	for _i in count: await process_frame

func capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s%s.png" % [out, prefix, name]
	image.save_png(path)
	print("EYES_SHOTS shot ", name, " ", path)

func run() -> void:
	root.size = Vector2i(1280, 720)
	await _tab()
	await _closeups()
	quit(0)

func _tab() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("6aa6dd")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(backdrop)
	var panel: Control = WardrobeUi.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var look := Look.defaults_for_seat(0)
	look.items["eyes"] = "eyes_big"
	panel.open(look, "VEL")
	await frames(6)
	panel.select_tab(1)
	await frames(240) # the thumbs render one item per frame
	capture("face_tab")
	layer.queue_free()
	await frames(2)

func _closeups() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = CandyLight.environment()
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	CandyLight.apply_sun(sun)
	sun.global_basis = Basis.looking_at(Vector3(-0.3, -0.5, -1.0), Vector3.UP)
	var camera := Camera3D.new()
	camera.fov = 22.0
	world.add_child(camera)
	camera.current = true
	for index in EYES.size():
		var rig: Node3D = Rig.new()
		world.add_child(rig)
		rig.setup(0, {"look": Look.defaults_for_seat(0)})
		var look := Look.defaults_for_seat(0)
		look.items["eyes"] = EYES[index]
		rig.set_look(look)
		rig.snap({"yaw": PI, "grounded": true, "velocity": Vector3.ZERO})
		await frames(8)
		var anchor: Node3D = rig.head_anchor()
		var head := anchor.global_position if anchor != null else Vector3(0.0, 1.6, 0.0)
		camera.global_position = head + Vector3(0.0, -0.12, 2.6)
		camera.look_at(head + Vector3(0.0, -0.3, 0.0), Vector3.UP)
		await frames(6)
		capture("eyes_%s" % EYES[index].trim_prefix("eyes_"))
		rig.queue_free()
		await frames(2)
