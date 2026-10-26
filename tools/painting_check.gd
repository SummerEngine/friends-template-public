extends SceneTree
## Dev check (not shipped) of demo/game/: painting pose and break rules, shards replay, follow camera, game audio data.
## Headless it asserts; offscreen it also renders frames of the carried and the broken painting:
##   headless:  FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <0.7.2 Summer> --headless --audio-driver Dummy --path demo -s $PWD/tools/painting_check.gd
##   offscreen: FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <offscreen Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/painting_check.gd -- --shots=<dir>
## Prints PAINTING_CHECK lines and `PAINTING_CHECK done failures=N`.
const Painting := preload("res://game/painting.gd")
const PaintingShards := preload("res://game/painting_shards.gd")
const FollowCamera := preload("res://game/follow_camera.gd")
const NO_LEAD := {"ahead": 0.0} ## the arm tests measure from the focus itself (no look-ahead)
const GameAudio := preload("res://game/game_audio.gd")
const CarryItem := preload("res://style/carry_item.gd")
const LevelEnvironment := preload("res://levels/level_environment.gd")

func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

class FakeRig extends Node3D:
	signal footstep(side)
	signal jumped
	signal landed(speed)

var shots := ""
var failures := 0
var world: Node3D
var hit_box: StaticBody3D
var camera: Camera3D
var courier_rigs: Array[Node3D] = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
	run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok: failures += 1
	print("PAINTING_CHECK ", "ok   " if ok else "FAIL ", what)

func near(a: Vector3, b: Vector3, eps := 0.002) -> bool:
	return a.distance_to(b) < eps

func physics_frames(count: int) -> void:
	for i in count: await physics_frame

func build_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80, 1, 80)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position = Vector3(0, -0.5, 0)
	world.add_child(ground)
	if shots != "":
		var mesh := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(80, 1, 80)
		mesh.mesh = plane
		mesh.material_override = _flat(Color("#f0d9a6"))
		mesh.position = ground.position
		world.add_child(mesh)
		LevelEnvironment.build(world)
	hit_box = StaticBody3D.new()
	hit_box.name = "HitBlock"
	hit_box.collision_layer = 8
	var hit_shape := CollisionShape3D.new()
	var hit_size := BoxShape3D.new()
	hit_size.size = Vector3(1.0, 3.0, 1.0)
	hit_shape.shape = hit_size
	hit_box.add_child(hit_shape)
	hit_box.position = Vector3(30, 1.5, 0)
	world.add_child(hit_box)
	camera = Camera3D.new()
	camera.current = true
	world.add_child(camera)

func stand_in(slot: int, feet: Vector3) -> Node3D:
	var rig := Node3D.new()
	rig.name = "StandIn%d" % slot
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	body.mesh = capsule
	body.position = Vector3(0, 0.9, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#e8603c") if slot == 0 else Color("#3c58d8")
	body.material_override = material
	rig.add_child(body)
	world.add_child(rig)
	rig.global_position = feet
	return rig

func hands(painting: Node3D) -> Array:
	var spheres: Array = []
	for slot in 2:
		for index in 2:
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.1
			sphere.height = 0.2
			ball.mesh = sphere
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#f4c20d")
			ball.material_override = material
			world.add_child(ball)
			spheres.append(ball)
	return spheres

func capture(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	for i in 3: await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("PAINTING_CHECK shot ", name, " ", image.save_png("%s/%s.png" % [shots, name]) == OK)

func run() -> void:
	build_world()
	await physics_frames(3)
	await check_painting()
	await check_shards()
	await check_camera()
	await check_audio()
	if shots != "": await render_frames()
	print("PAINTING_CHECK done failures=", failures)
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ painting
func check_painting() -> void:
	var painting := Painting.new()
	world.add_child(painting)
	painting.configure("authority")
	var a := Vector3(-1.75, 1.0, 0.0)
	var b := Vector3(1.75, 1.0, 0.0)
	painting.reset(a, b)
	check(near(painting.global_position, Vector3(0, 1, 0)), "reset places the painting at the anchor midpoint")
	check(near(painting.global_transform.basis.x, Vector3.RIGHT, 0.001) and near(painting.global_transform.basis.z, Vector3.UP, 0.001), "level pose: x along the axis, face up")
	var left0: Vector3 = painting.grip_points(0)[0]
	var left1: Vector3 = painting.grip_points(1)[0]
	check(near(left0, Vector3(-1.5, 1.1, -0.25)), "slot 0 left hand on its (-Z) left side, 0.25 m in front of the anchor (%s)" % left0)
	check(near(left1, Vector3(1.5, 1.1, 0.25)), "slot 1 left hand on the +Z side (%s)" % left1)
	check(painting.grip_points(0)[0].distance_to(painting.grip_points(0)[1]) > 0.49 and painting.grip_points(0)[0].distance_to(painting.grip_points(0)[1]) < 0.51, "hands 0.5 m apart")
	# follows moving anchors
	for i in 120:
		a += Vector3(0.0, 0.0, -0.05)
		b += Vector3(0.0, 0.0, -0.05)
		painting.anchor_a = a
		painting.anchor_b = b
		painting.step(1.0 / 60.0)
	check(near(painting.global_position, Vector3(0, 1, -6.0), 0.01), "follows the anchors while they move")
	check(not painting.broken, "moving through empty space does not break it")
	# roll and height
	for i in 600: painting.roll_input(1.0, 1.0 / 60.0)
	check(is_equal_approx(painting.roll, Painting.ROLL_LIMIT), "roll clamps at 80 degrees")
	for i in 600: painting.height_input(-1.0, 1.0 / 60.0)
	check(is_equal_approx(painting.height, -Painting.HEIGHT_LIMIT), "height clamps at -0.5 m")
	painting.step(1.0 / 60.0)
	check(absf(painting.global_position.y - 0.5) < 0.001, "height offset moves the painting (%s)" % painting.global_position.y)
	var rolled: Vector3 = painting.grip_points(0)[0]
	check(absf(rolled.y - painting.global_position.y) > 0.2, "roll turns the grips with the painting")
	# break rules with a hit block on layer 8
	painting.reset(Vector3(30 - 1.75, 1.0, 0.0), Vector3(30 + 1.75, 1.0, 0.0))
	var before_grace := 0.0
	while before_grace < 1.9:
		painting.step(1.0 / 60.0)
		before_grace += 1.0 / 60.0
	check(not painting.broken, "touching a hit block inside the 2 s grace does not break it (age %.2f)" % painting.age)
	for i in 20: painting.step(1.0 / 60.0)
	check(painting.broken and painting.hit_name == "HitBlock", "after the grace the hit block breaks it (%s, hit=%s)" % [painting.broken, painting.hit_name])
	var broken_at := painting.global_position
	painting.anchor_a += Vector3(5, 0, 0)
	painting.step(1.0 / 60.0)
	check(near(painting.global_position, broken_at), "a broken painting stays where it broke")
	painting.reset(a, b)
	check(not painting.broken and painting.age == 0.0 and painting.hit_name == "", "reset: intact, age 0, no hit")
	painting.break_with("kill")
	check(not painting.broken, "break_with inside the grace is ignored")
	painting.break_with("kill", 0.0)
	check(painting.broken and painting.hit_name == "kill", "break_with(tag, 0) breaks at once")
	painting.reset(a, b)
	for i in 70: painting.step(1.0 / 60.0)
	painting.break_with("grip", 1.0)
	check(painting.broken and painting.hit_name == "grip", "break_with(tag, 1.0) breaks after one second")
	painting.reset(a, b)
	for i in 130: painting.step(1.0 / 60.0)
	painting.anchor_a = Vector3(0, 1, 0)
	painting.anchor_b = Vector3(5, 1, 0)
	painting.step(1.0 / 60.0)
	check(not painting.broken, "no hit away from the block")
	var blocker := painting.make_blocker()
	check(blocker == painting.make_blocker() and blocker.collision_layer == 1024, "blocker on layer 1024, idempotent")
	painting.queue_free()

# ------------------------------------------------------------------ shards
func check_shards() -> void:
	var pose := Painting.pose_for(Vector3(-1.75, 1.0, 0), Vector3(1.75, 1.0, 0), 0.5, 0.0)
	pose.origin += Vector3(2, 0, 3)
	var owner_node := PaintingShards.new()
	var replica := PaintingShards.new()
	var server := PaintingShards.new()
	world.add_child(owner_node)
	world.add_child(replica)
	world.add_child(server)
	owner_node.configure(true, true)
	replica.configure(true, false)
	server.configure(false, true)
	for node in [owner_node, replica, server]: node.auto_advance = false
	check(owner_node.capture_state() == [], "no burst: empty state")
	owner_node.burst(pose, 4711)
	server.burst(pose, 4711, owner_node._floor_y)
	check(absf(owner_node._floor_y) < 0.001, "floor found under the painting (%s)" % owner_node._floor_y)
	for i in 30:
		owner_node.advance(1.0 / 60.0)
		server.advance(1.0 / 60.0)
	var state: Array = owner_node.capture_state()
	check(state.size() == 11 and int(state[0]) == 4711 and absf(float(state[1]) - 0.5) < 0.011, "state is [seed, age, floor, quat, pos, item]: %s" % [state.slice(0, 3)])
	check(server.capture_state() == state, "the no-visual server holds the same state")
	replica.apply_state(state, 1.0)
	var piece_count: int = CarryItem.item().pieces.size()
	check(replica.active and replica._pieces.size() == piece_count, "replica starts the burst from the state, %d pieces (%s)" % [piece_count, CarryItem.active()])
	owner_node.advance(0.0)
	var same := true
	for i in owner_node._pieces.size():
		if not owner_node._pieces[i].global_transform.is_equal_approx(replica._pieces[i].global_transform): same = false
	check(same, "replica draws exactly what the clock owner draws at the same age")
	check(CarryItem.ITEMS.find(CarryItem.active()) == int(state[10]), "state carries the item index")
	var floor_y: float = owner_node._floor_y
	var lowest := INF
	var farthest := 0.0
	for step in 600:
		owner_node.advance(0.05)
		for piece in owner_node._pieces:
			if piece.visible:
				lowest = minf(lowest, piece.global_position.y)
				farthest = maxf(farthest, Vector2(piece.global_position.x - pose.origin.x, piece.global_position.z - pose.origin.z).length())
		if step == 40:
			check(owner_node._flecks != null, "flecks present")
	check(lowest >= floor_y - 0.001, "no piece sinks below the floor (lowest %.3f)" % lowest)
	check(farthest > 0.8 and farthest < 6.0, "pieces scatter %.2f m from the painting" % farthest)
	check(not owner_node.active and owner_node.capture_state() == [], "the burst ends after its lifetime")
	replica.apply_state([], 1.0)
	check(not replica.active, "empty state clears the replica")
	# every other item replays the same way from the state (glass: its own shards)
	var default_item := CarryItem.active()
	for item_name in CarryItem.ITEMS:
		if item_name == default_item: continue
		CarryItem.set_active(item_name)
		owner_node.burst(pose, 977)
		owner_node.advance(0.4)
		replica.apply_state(owner_node.capture_state(), 1.0)
		var alike: bool = replica._pieces.size() == CarryItem.item().pieces.size() and replica._pieces.size() == owner_node._pieces.size()
		for i in mini(owner_node._pieces.size(), replica._pieces.size()):
			if not owner_node._pieces[i].global_transform.is_equal_approx(replica._pieces[i].global_transform): alike = false
		check(alike and replica._item == item_name, "%s: the replica replays %d pieces exactly" % [item_name, replica._pieces.size()])
		owner_node.reset()
		replica.apply_state([], 1.0)
	CarryItem.set_active(default_item)
	for node in [owner_node, replica, server]: node.queue_free()

# ------------------------------------------------------------------ camera
func check_camera() -> void:
	var view := FollowCamera.new()
	view.first_person = false # the orbit (the third-person option) and its arm
	view.configure(camera)
	var rig := stand_in(0, Vector3(0, 0, 8))
	view.own_body(rig, 0)
	var focus := Vector3(0, 1.4, 8)
	view.reset_lag()
	view.update(1.0 / 60.0, focus, 0.0, -0.2, Vector3(0, 1, 5), NO_LEAD)
	var open_distance := camera.global_position.distance_to(focus)
	check(absf(open_distance - FollowCamera.ARM_LENGTH) < 0.05, "open field: camera sits one arm behind the focus (%.2f m)" % open_distance)
	check(camera.global_position.z > focus.z and camera.global_position.y > focus.y, "behind and above at negative pitch")
	check(absf(view.control_yaw) < 0.0001, "control_yaw mirrors the yaw")
	var wall := StaticBody3D.new()
	wall.collision_layer = FollowCamera.CAMERA_LAYER
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20, 10, 1)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = Vector3(0, 5, 12)
	world.add_child(wall)
	await physics_frames(2)
	view.reset_lag()
	view.update(1.0 / 60.0, focus, 0.0, 0.0, null, NO_LEAD)
	var pulled := camera.global_position.distance_to(focus)
	check(pulled < 3.8 and camera.global_position.z < 12.0, "a wall behind pulls the arm in (%.2f m, z=%.2f)" % [pulled, camera.global_position.z])
	var released := false
	wall.position = Vector3(0, 5, 100)
	await physics_frames(2)
	for i in 6: view.update(1.0 / 60.0, focus, 0.0, 0.0, null, NO_LEAD)
	check(camera.global_position.distance_to(focus) < FollowCamera.ARM_LENGTH - 0.5, "after the wall leaves the arm eases back out, not at once")
	for i in 300: view.update(1.0 / 60.0, focus, 0.0, 0.0, null, NO_LEAD)
	check(absf(camera.global_position.distance_to(focus) - FollowCamera.ARM_LENGTH) < 0.05, "and reaches the full arm again")
	wall.queue_free()
	# zoom, look
	view.zoom(-100.0)
	check(is_equal_approx(view.arm_length, FollowCamera.ARM_MIN), "zoom clamps at the near limit")
	view.zoom(100.0)
	check(is_equal_approx(view.arm_length, FollowCamera.ARM_MAX), "zoom clamps at the far limit")
	view.arm_length = FollowCamera.ARM_LENGTH
	view.queue_look(Vector2(100, -100000))
	var rotated := view.look(3.0, 0.0)
	check(absf(rotated.y - deg_to_rad(FollowCamera.PITCH_HIGH)) < 0.0001, "pitch is clamped to the flattest top-down view (%.3f)" % rotated.y)
	view.queue_look(Vector2(0, 100000))
	check(absf(view.look(3.0, 0.0).y - deg_to_rad(FollowCamera.PITCH_LOW)) < 0.0001, "and to the steepest one")
	check(rotated.x >= -PI and rotated.x <= PI and absf(rotated.x - (3.0 - deg_to_rad(15.0))) < 0.0001, "mouse turns 15 degrees per 100 px, yaw wrapped (%.3f)" % rotated.x)
	view.queue_look(Vector2(50, 50))
	view.discard_look()
	check(view.consume_look() == Vector2.ZERO, "discard_look drops queued input")
	# own body: hidden when the camera is close, back when away
	view.reset_lag()
	view.update(1.0 / 60.0, focus, 0.0, 0.0, null, {"arm": 0.5, "ahead": 0.0})
	check((camera.cull_mask & (1 << FollowCamera.BODY_FIRST_BIT)) == 0, "own body hidden at 0.5 m")
	view.update(1.0 / 60.0, focus, 0.0, 0.0, null, {"arm": 1.1, "ahead": 0.0})
	check((camera.cull_mask & (1 << FollowCamera.BODY_FIRST_BIT)) == 0, "own body stays hidden at 1.1 m (hysteresis)")
	view.update(1.0 / 60.0, focus, 0.0, 0.0, null, {"arm": 2.0, "ahead": 0.0})
	for i in 200: view.update(1.0 / 60.0, focus, 0.0, 0.0, null, {"arm": 2.0, "ahead": 0.0})
	check((camera.cull_mask & (1 << FollowCamera.BODY_FIRST_BIT)) != 0, "own body back at 2 m")
	view.clear_bodies()
	rig.queue_free()
	await check_shoulder_camera()

## The show's over-the-shoulder view (FollowCamera.set_shoulder_view): behind, a little above, the body low on the left; walls never block it.
func check_shoulder_camera() -> void:
	var view := FollowCamera.new()
	view.first_person = false
	view.set_shoulder_view(true)
	view.configure(camera)
	var rig := stand_in(0, Vector3(0, 0, 8))
	view.own_body(rig, 0)
	var courier := Vector3(0, 1.0, 8) # the chest the shell passes (feet + CAMERA_FOCUS)
	view.reset_lag()
	view.update(1.0 / 60.0, courier, 0.0, view.default_pitch(), Vector3(0, 1, 5))
	var behind := camera.global_position - courier
	check(absf(view.arm_length - FollowCamera.SHOULDER_ARM) < 0.001 and absf(view.default_pitch() - deg_to_rad(FollowCamera.SHOULDER_PITCH_DEFAULT)) < 0.0001, "shoulder view: its own arm and pitch")
	check(behind.z > 4.0 and behind.z < FollowCamera.SHOULDER_ARM + 0.1 and behind.y > 0.5 and behind.y < 3.5, "shoulder view: behind the courier and a little above (%s)" % str(behind))
	check(behind.x > 0.3 and behind.x < 1.2, "shoulder view: over the right shoulder, the body stands left of the view centre (x=%.2f)" % behind.x)
	check(is_equal_approx(view.control_yaw, 0.0), "shoulder view: movement stays relative to the yaw")
	check((camera.cull_mask & (1 << FollowCamera.BODY_FIRST_BIT)) != 0, "shoulder view: the own body is drawn")
	var walls := []
	for spec in [[Vector3(0, 5, 12), Vector3(20, 10, 1)], [Vector3(1.4, 5, 8), Vector3(1, 10, 20)]]: # behind the courier; right at its shoulder
		var wall := StaticBody3D.new()
		wall.collision_layer = FollowCamera.CAMERA_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		wall.add_child(shape)
		wall.position = spec[0]
		world.add_child(wall)
		walls.append(wall)
	await physics_frames(2)
	view.reset_lag()
	view.update(1.0 / 60.0, courier, 0.0, view.default_pitch(), null)
	check(camera.global_position.z < 12.0 and camera.global_position.x < 1.4, "shoulder view: walls behind and at the shoulder never put the camera behind them (x=%.2f z=%.2f)" % [camera.global_position.x, camera.global_position.z])
	for wall: Node in walls: wall.queue_free()
	view.queue_look(Vector2(100, -100000))
	check(absf(view.look(3.0, 0.0).y - deg_to_rad(FollowCamera.SHOULDER_PITCH_HIGH)) < 0.0001, "shoulder view: the look input stops at the flattest pitch")
	view.queue_look(Vector2(0, 100000))
	check(absf(view.look(3.0, 0.0).y - deg_to_rad(FollowCamera.SHOULDER_PITCH_LOW)) < 0.0001, "shoulder view: and at the steepest")
	view.clear_bodies()
	rig.queue_free()

# ------------------------------------------------------------------ audio
func check_audio() -> void:
	var mix := GameAudio.load_mix()
	check(not mix.is_empty() and mix.has("footsteps") and mix.has("breaks"), "sound mix loads")
	var entry := GameAudio.break_entry("break_painting")
	var stream := GameAudio.load_wave(str(entry.resource))
	check(stream != null and absf(stream.get_length() - float(entry.duration_s)) < 0.02, "break sound atlas region cut to its length")
	for item_name in CarryItem.ITEMS:
		var item_sound := str(CarryItem.data(item_name).get("sound_id", ""))
		check(GameAudio.break_entry(item_sound).get("id", "") == item_sound, "%s breaks with its own sound (%s)" % [item_name, item_sound])
	check(GameAudio.load_wave(str(mix.jump.resource)) != null, "whole-file sound loads")
	check(is_equal_approx(GameAudio.attenuation(0.2), 1.0) and is_equal_approx(GameAudio.break_gain(10.0), 1.0) and GameAudio.break_gain(60.0) == 0.0, "distance gain curves")
	var audio := GameAudio.new()
	audio.playback_enabled = false
	world.add_child(audio)
	audio.configure(camera)
	var events: Array = []
	audio.played.connect(func(event: Dictionary): events.append(event))
	var rig := FakeRig.new()
	world.add_child(rig)
	audio.bind_courier(0, rig, true)
	rig.footstep.emit(0)
	rig.jumped.emit()
	rig.landed.emit(2.0)
	rig.landed.emit(10.0)
	var kinds := events.map(func(event): return event.kind)
	check(kinds == ["step", "jump", "step"], "rig signals: footstep, own jump, loud landing only (%s)" % [kinds])
	events.clear()
	audio.play_break(Vector3.ZERO)
	audio.play_break(Vector3.ZERO, 5.0)
	check(events.size() == 1 and events[0].kind == "break", "break plays once, a finished crash is not replayed")
	events.clear()
	audio.observe({"death": 3, "push": 0, "bounce": 0, "easter": 1}, 0)
	check(events.is_empty(), "first observation is a baseline")
	audio.observe({"death": 4, "push": 1, "bounce": 0, "easter": 1}, 0)
	check(events.map(func(event): return event.kind) == ["death", "push"], "counter increases play their sounds")
	events.clear()
	audio.observe({"death": 4, "push": 1, "bounce": 0, "easter": 1}, 1)
	check(events.is_empty(), "a new epoch is a baseline again")
	audio.blink_warn(7, Vector3(1, 2, 3))
	audio.blink_gone(7, Vector3(1, 2, 3))
	check(events.map(func(event): return event.kind) == ["blink_crack", "blink_broken"], "blinking block cues")
	audio.queue_free()
	rig.queue_free()

# ------------------------------------------------------------------ frames
func render_frames() -> void:
	for item_name in CarryItem.ITEMS:
		CarryItem.set_active(item_name)
		var a := Vector3(-1.75, 1.0, 0.0)
		var b := Vector3(1.75, 1.0, 0.0)
		var painting := Painting.new()
		world.add_child(painting)
		painting.configure("local")
		painting.reset(a, b)
		var couriers := [stand_in(0, a + Vector3(0, -1, 0)), stand_in(1, b + Vector3(0, -1, 0))]
		var balls := hands(painting)
		var index := 0
		for slot in 2:
			for point in painting.grip_points(slot):
				balls[index].global_position = point
				index += 1
		camera.global_position = Vector3(-0.8, 3.6, 4.8)
		camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)
		await capture("%s-carried-flat" % item_name)
		# behind slot 0 looking along the walking direction (-Z), the partner on the right, as the game camera sees it
		var behind := FollowCamera.new()
		behind.configure(camera)
		behind.update(1.0 / 60.0, Vector3(-1.75, 1.4, 0.0), 0.0, -0.3, Vector3(1.75, 1.0, 0.0))
		print("PAINTING_CHECK follow camera at ", camera.global_position, " looks ", -camera.global_transform.basis.z)
		await capture("%s-carried-follow" % item_name)
		painting.roll = deg_to_rad(40)
		painting.step(1.0 / 60.0)
		index = 0
		for slot in 2:
			for point in painting.grip_points(slot):
				balls[index].global_position = point
				index += 1
		camera.global_position = Vector3(0.6, 3.2, 4.2)
		camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
		await capture("%s-carried-rolled" % item_name)
		painting.reset(a, b)
		camera.global_position = Vector3(0.0, 3.4, 4.6)
		camera.look_at(Vector3(0, 0.8, 0.0), Vector3.UP)
		var pieces := PaintingShards.new()
		world.add_child(pieces)
		pieces.configure(true, true)
		pieces.auto_advance = false
		painting.set_intact_visible(false)
		for ball in balls: ball.visible = false
		pieces.burst(painting.global_transform, 2026)
		for stage in [[0.25, "0p25"], [0.6, "0p60"], [1.4, "1p40"], [3.0, "settled"]]:
			pieces.advance(float(stage[0]) - pieces.age)
			await capture("%s-broken-%s" % [item_name, stage[1]])
		pieces.queue_free()
		painting.queue_free()
		for node in couriers: node.queue_free()
		for ball in balls: ball.queue_free()
