extends SceneTree
## Frame strips of the movement rules, played with the REAL CourierMotion on the real level world (collision, launch pads) and drawn with the character rig. Offscreen binary only,
## never windowed, ONE render at a time machine-wide (lockf render.lock):
##   <ItemsLab offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 960x540 --path demo -s "$PWD/tools/move_strips.gd" -- --shots=<dir> --mode=pads [--level=29] [--pads=hop_start_l,hop_start_r] [--every=12]
##   --mode=pads      every pad in --pads is stepped on by its own courier at the same moment (a walk of 0.4 s onto the pad, then the launch fires through `effects_at` as game_run.gd
##                    feeds it, the stick held along the throw), one frame every --every ticks from just before the launch until all have landed; a fixed wide camera beside the flights
##   --mode=airdash   a courier jumps off the start deck and presses the dash in the air with a sideways stick (a correction): the camera follows from the side, frames every --every ticks
## Prints MOVE_STRIP lines (per frame: tick, each courier's feet, flop) and `MOVE_STRIP ok` (the couriers landed on solid ground; for airdash: no flop after the landing).
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
var CAM_SIDE := 3.0
var CAM_UP := 4.5
var CAM_BACK := 13.0

var shots := ""
var mode := "pads"
var level_number := 29
var pad_ids := PackedStringArray(["hop_start_l", "hop_start_r"])
var every := 15
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--pads="): pad_ids = argument.trim_prefix("--pads=").split(",")
		if argument.begins_with("--every="): every = int(argument.trim_prefix("--every="))
		if argument.begins_with("--cam-side="): CAM_SIDE = float(argument.trim_prefix("--cam-side="))
		if argument.begins_with("--cam-up="): CAM_UP = float(argument.trim_prefix("--cam-up="))
		if argument.begins_with("--cam-back="): CAM_BACK = float(argument.trim_prefix("--cam-back="))
	create_timer(300.0).timeout.connect(func() -> void:
		print("MOVE_STRIP FAIL timed out")
		quit(1))
	run.call_deferred()

func run() -> void:
	if shots == "":
		print("MOVE_STRIP needs --shots=<dir>")
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
	camera = Camera3D.new()
	camera.far = 900.0
	camera.fov = 60.0
	holder.add_child(camera)
	camera.current = true
	var ok := false
	if mode == "pads": ok = await pads(level)
	else: ok = await airdash(level)
	print("MOVE_STRIP ", "ok" if ok else "FAIL")
	holder.queue_free()
	await process_frame
	quit(0 if ok else 1)

func make_courier(at: Vector3, yaw: float) -> Dictionary:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.set_dash_flop(false)
	motion.reset(body, at, yaw)
	var rig: Node3D = CharRig.new()
	holder.add_child(rig)
	rig.setup(0, {})
	return {"body": body, "motion": motion, "rig": rig}

func draw(courier: Dictionary, accel := Vector3.ZERO) -> void:
	var body: CharacterBody3D = courier.body
	var motion: RefCounted = courier.motion
	var rig: Node3D = courier.rig
	rig.global_position = body.global_position
	rig.update(DT, {"velocity": body.velocity, "grounded": motion.grounded, "yaw": motion.yaw, "acceleration": motion.acceleration, "floor_normal": motion.floor_normal, "carrying": false, "flop": motion.flop_left})

func shoot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("%s/%s.png" % [shots, name])

# ------------------------------------------------------------------ pads
func pads(level: int) -> bool:
	var origin: Vector3 = world.level_origin(level)
	var runners := []
	var midpoint := Vector3.ZERO
	var lows := 1e9
	for id in pad_ids:
		var launcher: Dictionary = {}
		for candidate: Dictionary in world._levels[level].launchers:
			if str(candidate.h.id) == id: launcher = candidate
		if launcher.is_empty():
			print("MOVE_STRIP FAIL no pad ", id)
			return false
		var h: Dictionary = launcher.h
		var pivot: Vector3 = origin + (h.pivot as Vector3)
		var throw: Vector3 = h.v
		var heading := Vector3(throw.x, 0.0, throw.z).normalized() if Vector2(throw.x, throw.z).length() > 0.5 else Vector3(0.0, 0.0, -1.0) # a pad that only hops: the courier walks on along the course
		var feet := Vector3(pivot.x, pivot.y - 1.0, pivot.z) - heading * 1.1
		var made := make_courier(feet + Vector3(0.0, 0.02, 0.0), atan2(-heading.x, -heading.z))
		made.heading = heading
		made.id = id
		made.launched = -1
		made.landed = -1
		made.landing = Vector3.ZERO
		runners.append(made)
		midpoint += feet + heading * 17.0
		lows = minf(lows, feet.y)
	midpoint /= float(runners.size())
	var side := Vector3.RIGHT if (runners[0].heading as Vector3).z < 0.0 else Vector3.LEFT
	world.set_clock(5.0)
	world.reset_effects()
	for i in 6:
		await physics_frame
	var tick := 0
	var shot := 0
	var done := false
	var landed_ok := true
	while not done and tick < 60 * 12:
		await physics_frame
		world.advance(DT)
		done = true
		for r: Dictionary in runners:
			var body: CharacterBody3D = r.body
			var motion: RefCounted = r.motion
			var effect: Dictionary = world.effects_at(level, runners.find(r), body.global_position)
			if not effect.is_empty() and r.launched < 0:
				motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
				r.launched = tick
			var stick := Vector2(r.heading.x, r.heading.z) if (r.launched >= 0 and r.landed < 0) else Vector2(r.heading.x, r.heading.z) * (1.0 if r.launched < 0 else 0.0)
			motion.step(body, {"move": stick}, DT)
			draw(r)
			if r.launched >= 0 and r.landed < 0 and motion.grounded and tick > r.launched + 10:
				r.landed = tick
				r.landing = body.global_position - origin
			if r.landed < 0: done = false
		# a chase camera over the pads' couriers (behind them along the throw, a little to the side and high): both stay in frame through the whole arc
		var centre := Vector3.ZERO
		for r: Dictionary in runners: centre += (r.body as Node3D).global_position
		centre /= float(runners.size())
		var way: Vector3 = runners[0].heading
		camera.global_position = centre - way * CAM_BACK + side * CAM_SIDE + Vector3(0.0, CAM_UP, 0.0)
		camera.look_at(centre + way * 5.0 + Vector3(0.0, 0.5, 0.0), Vector3.UP)
		if tick % every == 0 and tick >= 6:
			shoot("pads_%02d" % shot)
			shot += 1
			var line := "MOVE_STRIP tick %d" % tick
			for r: Dictionary in runners: line += " | %s feet %s launched %d" % [r.id, str(((r.body as Node3D).global_position - origin).snapped(Vector3(0.1, 0.1, 0.1))), r.launched]
			print(line)
		tick += 1
	for r: Dictionary in runners:
		print("MOVE_STRIP %s launched at tick %d landed at tick %d on %s (air time %.2f s)" % [r.id, r.launched, r.landed, str((r.landing as Vector3).snapped(Vector3(0.01, 0.01, 0.01))), float(r.landed - r.launched) * DT])
		if r.launched < 0 or r.landed < 0: landed_ok = false
	shoot("pads_%02d" % shot)
	return landed_ok

# ------------------------------------------------------------------ air dash
func airdash(level: int) -> bool:
	var origin: Vector3 = world.level_origin(level)
	var start := origin + Vector3(0.0, 0.05, -8.0)
	var made := make_courier(start, 0.0)
	var body: CharacterBody3D = made.body
	var motion: RefCounted = made.motion
	world.set_clock(5.0)
	world.reset_effects()
	for i in 12:
		await physics_frame
		motion.step(body, {}, DT)
	motion.reset(body, start, 0.0)
	# a fixed camera ahead of the runner, a little to the right: it runs towards it and the sideways burst crosses the frame
	camera.global_position = start + Vector3(2.5, 2.3, -6.0)
	camera.look_at(start + Vector3(-3.0, 1.5, -0.5), Vector3.UP)
	camera.fov = 70.0
	var tick := 0
	var shot := 0
	var jumped := -1
	var dashed := -1
	var landed := -1
	var flop_max := 0.0
	var dx_before := 0.0
	var dx_after := 0.0
	var x_dash := 0.0
	var events_dash := 0
	while tick < 60 * 6 and not (landed >= 0 and tick > landed + 40):
		await physics_frame
		world.advance(DT)
		var input := {"move": Vector2(0.0, -1.0)} # running forward (-Z)
		if tick == 6: input["jump"] = true
		if tick == 24: # near the apex the course is off to the left of the jump: a sideways burst corrects it
			input = {"move": Vector2(-1.0, 0.0), "dash": true}
			x_dash = body.global_position.x
		elif tick > 24 and tick < 60 and dashed >= 0:
			input = {"move": Vector2(-1.0, 0.0)}
		var e: Dictionary = motion.step(body, input, DT)
		if e.jumped: jumped = tick
		if e.dashed:
			dashed = tick
			events_dash += 1
		if landed < 0 and jumped >= 0 and tick > jumped + 5 and motion.grounded: landed = tick
		flop_max = maxf(flop_max, motion.flop_left)
		draw(made)
		var at: Vector3 = body.global_position
		if tick % every == 0 and tick >= 4 and tick < 96:
			shoot("airdash_%02d" % shot)
			shot += 1
			print("MOVE_STRIP tick %d feet %s vel %s flop %.2f dash_left %.2f cooldown %.2f grounded %s" % [tick, str((at - origin).snapped(Vector3(0.01, 0.01, 0.01))), str(body.velocity.snapped(Vector3(0.1, 0.1, 0.1))), motion.flop_left, motion.dash_left, motion.dash_cooldown, str(motion.grounded)])
		tick += 1
	dx_after = body.global_position.x - x_dash
	print("MOVE_STRIP air dash at tick %d (jump at %d, landed %d): sideways %.2f m after the dash (to the landing), flop_left max %.2f, dashes %d" % [dashed, jumped, landed, dx_after, flop_max, events_dash])
	return dashed > jumped and landed > dashed and flop_max == 0.0 and dx_after < -2.0 and events_dash == 1
