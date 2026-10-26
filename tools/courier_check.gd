extends SceneTree
## Dev check of the courier module (not shipped).
##   --mode=motion  numeric fixture: floor, ramps, step, wall, ledge, moving platform; prints COURIER_* lines (headless is fine)
##   --mode=rig     rig fixture: build time, foot slip, hand reach, signals (headless is fine)
##   --mode=frames  pictures of the poses from several angles into --out=<dir> (offscreen binary only)
## Example (from the worktree root):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --path demo -s $PWD/tools/courier_check.gd -- --mode=motion
const Motion := preload("res://courier/courier_motion.gd")
const Rig := preload("res://courier/courier_rig.gd")
const Anchor := preload("res://courier/courier_anchor.gd")
const DT := 1.0 / 60.0

var mode := "motion"
var out := "/tmp/courier-frames"
var world: Node3D
var failures := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="): mode = a.trim_prefix("--mode=")
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	run.call_deferred()

func run() -> void:
	match mode:
		"motion": await run_motion()
		"rig": await run_rig()
		"frames": await run_frames()
	print("COURIER_CHECK done mode=", mode, " failures=", failures)
	quit(1 if failures > 0 else 0)

func expect(name: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("COURIER_CHECK ", "ok  " if ok else "FAIL", " ", name, " ", detail)

# ------------------------------------------------------------------ fixtures
func block(parent: Node, pos: Vector3, size: Vector3, rot := Vector3.ZERO, layer := 1, mover := false) -> PhysicsBody3D:
	var body: PhysicsBody3D = AnimatableBody3D.new() if mover else StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = pos
	body.rotation_degrees = rot
	return body

func fresh_world() -> void:
	if world != null:
		root.remove_child(world)
		world.free()
	world = Node3D.new()
	root.add_child(world)

func spawn(pos: Vector3, yaw := 0.0) -> Array:
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, pos, yaw)
	return [body, motion]

func ticks(n: int) -> void:
	for i in n: await physics_frame

## Runs `count` ticks with a constant input; `each` (Callable(tick, events)) sees every tick.
func drive(body: CharacterBody3D, motion: RefCounted, input: Dictionary, count: int, each := Callable()) -> Dictionary:
	var last := {}
	for tick in count:
		await physics_frame
		var inp := input.duplicate()
		if inp.has("jump_at") and tick != int(inp["jump_at"]): inp["jump"] = false
		elif inp.has("jump_at"): inp["jump"] = true
		last = motion.step(body, inp, DT)
		if each.is_valid(): each.call(tick, last)
	return last

func settle(body: CharacterBody3D, motion: RefCounted, count := 20) -> void:
	await drive(body, motion, {}, count)

# ------------------------------------------------------------------ motion
func run_motion() -> void:
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40)) # main floor, edge at x = +-20, z = +-20
	var cm: Array
	var body: CharacterBody3D
	var motion: RefCounted
	# --- walk and stop
	cm = spawn(Vector3(0, 0.0, 15))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	expect("stand grounded", motion.grounded, "y=%.3f" % body.global_position.y)
	var speeds := {}
	await drive(body, motion, {"move": Vector2(0, -1)}, 90, func(t, _e): if t in [14, 29, 59, 89]: speeds[t] = Vector2(body.velocity.x, body.velocity.z).length())
	print("COURIER_NUM walk_speed_at 0.25s/0.5s/1s/1.5s = ", speeds)
	expect("walk reaches 5 m/s", absf(speeds[59] - 5.0) < 0.05)
	expect("accel about 15 (0.25 s -> ~3.75)", absf(speeds[14] - 3.75) < 0.4, str(speeds[14]))
	var start_z := body.global_position.z
	var stop_ticks := 0
	var stop_pos := body.global_position
	for i in 120:
		await physics_frame
		motion.step(body, {}, DT)
		stop_ticks += 1
		if Vector2(body.velocity.x, body.velocity.z).length() < 0.01: break
	var stop_dist := stop_pos.distance_to(body.global_position)
	print("COURIER_NUM stop ticks=", stop_ticks, " distance=", snappedf(stop_dist, 0.001), " (ideal 25/(2*20)=0.625)")
	expect("brake distance", absf(stop_dist - 0.625) < 0.15)
	# --- jump height and timing
	await settle(body, motion)
	var y0 := body.global_position.y
	var jump := {"peak": y0, "apex": 0}
	await drive(body, motion, {"jump_at": 0}, 80, func(t, _e):
		if body.global_position.y > jump["peak"]:
			jump["peak"] = body.global_position.y
			jump["apex"] = t)
	print("COURIER_NUM jump height=", snappedf(jump["peak"] - y0, 0.001), " apex_time=", snappedf(jump["apex"] * DT, 0.01), " (ideal 1.441 / 0.41)")
	expect("jump height v^2/2g", absf((jump["peak"] - y0) - 49.0 / 34.0) < 0.06)
	expect("landed again", motion.grounded)
	# --- air control: planar speed change in the air
	await settle(body, motion)
	await drive(body, motion, {"jump_at": 0, "move": Vector2(1, 0)}, 20)
	var air_vx := body.velocity.x
	print("COURIER_NUM air vx after 20 ticks of full input (accel 15*0.75) = ", snappedf(air_vx, 0.01))
	expect("air control slower than ground", air_vx < 15.0 * 0.34 and air_vx > 1.0)
	await ticks(1)
	await drive(body, motion, {}, 90)
	# --- coyote time and jump buffer on a ledge
	cm = spawn(Vector3(17, 0, 0), -PI * 0.5)
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var off := {"tick": -1}
	await drive(body, motion, {"move": Vector2(1, 0)}, 90, func(t, e): if off["tick"] < 0 and e["left_ground"]: off["tick"] = t)
	expect("walked off the ledge", off["tick"] >= 0, str(off["tick"]))
	cm = spawn(Vector3(17, 0, 3), -PI * 0.5)
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var left_at := -1
	var press_at := -1
	var res := {"jumped": false}
	for t in 120:
		await physics_frame
		var press := false
		if left_at >= 0 and t - left_at == 12 and press_at < 0:
			press = true
			press_at = t
		var e: Dictionary = motion.step(body, {"move": Vector2(1, 0), "jump": press}, DT)
		if left_at < 0 and e["left_ground"]: left_at = t
		if press_at >= 0 and e["jumped"]: res["jumped"] = true
	expect("coyote: jump 0.2 s after leaving the edge works", res["jumped"], "left_at=%d press_at=%d" % [left_at, press_at])
	cm = spawn(Vector3(17, 0, -3), -PI * 0.5)
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	left_at = -1
	press_at = -1
	res = {"jumped": false}
	for t in 120:
		await physics_frame
		var press := false
		if left_at >= 0 and t - left_at == 22 and press_at < 0:
			press = true
			press_at = t
		var e: Dictionary = motion.step(body, {"move": Vector2(1, 0), "jump": press}, DT)
		if left_at < 0 and e["left_ground"]: left_at = t
		if press_at >= 0 and e["jumped"]: res["jumped"] = true
	expect("coyote: jump 0.37 s after leaving the edge fails", not res["jumped"], "left_at=%d press_at=%d" % [left_at, press_at])
	# --- jump buffer: press while falling, 0.1 s and 0.25 s before touchdown
	for case in [[6, true], [15, false]]:
		cm = spawn(Vector3(-10, 4.0, 10))
		body = cm[0]; motion = cm[1]
		var land_tick := -1
		var press_tick := -1
		var jumped_after := false
		for t in 200:
			await physics_frame
			var press := false
			if land_tick < 0 and body.velocity.y < 0.0 and press_tick < 0:
				# distance to the floor with the current speed
				var ticks_left := int(ceil((body.global_position.y) / maxf(-body.velocity.y * DT, 0.0001)))
				if ticks_left <= case[0] + 4:
					press = true
					press_tick = t
			var e: Dictionary = motion.step(body, {"jump": press}, DT)
			if e["landed"] and land_tick < 0: land_tick = t
			if land_tick >= 0 and e["jumped"]: jumped_after = true
			if land_tick >= 0 and t > land_tick + 3: break
		print("COURIER_NUM buffer press_tick=", press_tick, " land_tick=", land_tick, " dt=", snappedf((land_tick - press_tick) * DT, 0.001), " jumped_after=", jumped_after)
	# buffered jump: pressed 4 ticks before touchdown must fire on landing; pressed 14 ticks before must not
	for case in [[4, true], [14, false]]:
		cm = spawn(Vector3(-10, 3.0, 10))
		body = cm[0]; motion = cm[1]
		var fired := false
		var pressed := false
		var landed_tick := -1
		for t in 200:
			await physics_frame
			var press := false
			if not pressed and body.velocity.y < 0.0:
				var speed := -body.velocity.y
				var h := body.global_position.y
				# ticks until touchdown, simulated exactly the way the motion integrates
				var vy := body.velocity.y
				var y := h
				var n := 0
				while y > 0.0 and n < 100:
					vy = maxf(vy - Motion.GRAVITY * DT, -Motion.MAX_FALL)
					y += vy * DT
					n += 1
				if n <= case[0]:
					press = true
					pressed = true
			var e: Dictionary = motion.step(body, {"jump": press}, DT)
			if e["landed"]: landed_tick = t
			if landed_tick >= 0 and e["jumped"]: fired = true
			if landed_tick >= 0 and t > landed_tick + 4: break
		expect("buffer: jump pressed %d ticks before touchdown %s" % [case[0], "fires" if case[1] else "is dropped"], fired == case[1], "landed=%d fired=%s" % [landed_tick, fired])
	# --- step up and walls
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	block(world, Vector3(0, 0.125, -9), Vector3(4, 0.25, 9))   # 0.25 m step, front edge at z = -4.5
	block(world, Vector3(6, 0.2, -9), Vector3(4, 0.4, 9))      # 0.4 m step
	block(world, Vector3(12, 0.5, -9), Vector3(4, 1.0, 9))     # 1.0 m wall (no step)
	var stair_y := {}
	for i in 3:
		var x: float = [0.0, 6.0, 12.0][i]
		cm = spawn(Vector3(x, 0, 2))
		body = cm[0]; motion = cm[1]
		await settle(body, motion)
		var stepped_flag := {"v": false}
		await drive(body, motion, {"move": Vector2(0, -1)}, 140, func(_t, e): if e["stepped"]: stepped_flag["v"] = true)
		stair_y[i] = [body.global_position.y, body.global_position.z, stepped_flag["v"]]
	print("COURIER_NUM step results (y, z, stepped) 0.25 / 0.4 / 1.0 m: ", stair_y)
	expect("0.25 m step is climbed", stair_y[0][0] > 0.24 and stair_y[0][1] < -5.0 and stair_y[0][2])
	expect("0.4 m step is climbed", stair_y[1][0] > 0.39 and stair_y[1][1] < -5.0)
	expect("1.0 m wall blocks", stair_y[2][0] < 0.05 and stair_y[2][1] > -4.4)
	# stairs: 4 steps of 0.25
	for i in 4:
		# each tread is a solid block from the floor up to its top, 0.8 m deep
		var top := 0.25 * (i + 1)
		block(world, Vector3(-8, top * 0.5, -4 - 0.8 * i), Vector3(3, top, 0.8))
	block(world, Vector3(-8, 0.5, -10.2), Vector3(3, 1.0, 6.0))
	cm = spawn(Vector3(-8, 0, 2))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	await drive(body, motion, {"move": Vector2(0, -1)}, 160)
	print("COURIER_NUM stairs: y=", snappedf(body.global_position.y, 0.001), " z=", snappedf(body.global_position.z, 0.01))
	# steps carry only boxes that exist; the staircase boxes have no vertical overlap, so check we climbed at least 0.75
	expect("stairs of 0.25 m climbed", body.global_position.y > 0.95)
	# --- ramps
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var ramp30 := block(world, Vector3(-6, 1.0, -8), Vector3(4, 0.4, 14), Vector3(30, 0, 0))
	var ramp60 := block(world, Vector3(6, 2.0, -8), Vector3(4, 0.4, 8), Vector3(60, 0, 0))
	cm = spawn(Vector3(-6, 0, 2))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var ramp_speed := {"v": 0.0}
	await drive(body, motion, {"move": Vector2(0, -1)}, 150, func(t, _e): if t == 140: ramp_speed["v"] = body.velocity.length())
	print("COURIER_NUM 30deg ramp: y=", snappedf(body.global_position.y, 0.01), " speed=", snappedf(ramp_speed["v"], 0.01), " grounded=", motion.grounded, " normal=", motion.floor_normal)
	expect("30 degree ramp is climbed at full speed", body.global_position.y > 1.0 and ramp_speed["v"] > 4.8)
	cm = spawn(Vector3(6, 0, 2))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	await drive(body, motion, {"move": Vector2(0, -1)}, 150)
	print("COURIER_NUM 60deg ramp: y=", snappedf(body.global_position.y, 0.01), " z=", snappedf(body.global_position.z, 0.01))
	expect("60 degree slope is not climbed", body.global_position.y < 1.0)
	# --- downhill: stays glued to the ramp
	cm = spawn(Vector3(-6, 5.5, -13.5))
	body = cm[0]; motion = cm[1]
	var airborne_ticks := {"n": 0}
	await settle(body, motion, 30)
	await drive(body, motion, {"move": Vector2(0, 1)}, 80, func(_t, _e): if not motion.grounded: airborne_ticks["n"] += 1)
	print("COURIER_NUM downhill airborne ticks=", airborne_ticks["n"], " y=", snappedf(body.global_position.y, 0.01))
	expect("downhill stays grounded", airborne_ticks["n"] <= 2)
	# --- moving platform (layer 16)
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	var mover := block(world, Vector3(0, 0.5, -10), Vector3(4, 0.2, 4), Vector3.ZERO, 16, true) as AnimatableBody3D
	mover.sync_to_physics = true
	cm = spawn(Vector3(0, 0.6, -10))
	body = cm[0]; motion = cm[1]
	var drift := {"max": 0.0, "n": 0}
	var t_clock := {"t": 0.0}
	for tick in 240:
		await physics_frame
		t_clock["t"] += DT
		mover.global_position = Vector3(3.0 * sin(t_clock["t"] * 1.2), 0.5 + 0.4 * (0.5 + 0.5 * sin(t_clock["t"] * 0.7)), -10)
		motion.step(body, {}, DT)
		if tick > 30:
			drift["max"] = maxf(drift["max"], absf(body.global_position.x - mover.global_position.x))
			drift["n"] += 1
	print("COURIER_NUM platform carry: max horizontal drift from mover centre=", snappedf(drift["max"], 0.001), " on_platform=", motion.platform == mover, " y=", snappedf(body.global_position.y, 0.02))
	expect("platform carries the courier (sine mover, rising and falling)", drift["max"] < 0.08 and motion.platform == mover and motion.grounded)
	# jump off at the moment of full speed: keeps the platform velocity
	var before_vx := {"v": 0.0}
	for tick in 4000:
		await physics_frame
		t_clock["t"] += DT
		mover.global_position = Vector3(3.0 * sin(t_clock["t"] * 1.2), 0.5, -10)
		if absf(cos(t_clock["t"] * 1.2)) > 0.995:
			var e: Dictionary = motion.step(body, {"jump": true}, DT)
			if e["jumped"]:
				before_vx["v"] = body.velocity.x
				break
		else:
			motion.step(body, {}, DT)
	print("COURIER_NUM jump off the mover: vx=", snappedf(before_vx["v"], 0.01), " (mover speed up to 3.6)")
	expect("jumping off keeps the mover velocity", absf(before_vx["v"]) > 2.5)
	# --- pull towards the partner
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	cm = spawn(Vector3(0, 0, 0))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var partner := Vector3(12, 0, 0)
	await drive(body, motion, {"toward": partner, "partner_velocity": Vector3(0, 0, -6)}, 60)
	var pulled_speed := body.velocity.length()
	print("COURIER_NUM pull speed=", snappedf(pulled_speed, 0.01), " x=", snappedf(body.global_position.x, 0.01), " (0.8 of 5 = 4)")
	expect("pull moves a far idle courier at about 4 m/s", absf(pulled_speed - 4.0) < 0.2)
	cm = spawn(Vector3(0, 0, 0))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	await drive(body, motion, {"toward": Vector3(3, 0, 0), "partner_velocity": Vector3.ZERO}, 30)
	expect("no pull inside 5 m", body.velocity.length() < 0.01)
	await drive(body, motion, {"move": Vector2(1, 0)}, 30)
	var own_speed := body.velocity.length()
	await drive(body, motion, {"toward": Vector3(-12, 0, 0), "partner_velocity": Vector3.ZERO}, 12)
	expect("no pull for the faster courier (keeps braking)", body.velocity.length() < own_speed - 3.0, "%.2f -> %.2f" % [own_speed, body.velocity.length()])
	# --- dash: a lunge along the input or the facing, a cooldown, one per airtime
	cm = spawn(Vector3(0, 0, 15))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var dash_from := body.global_position
	var dash_peak := [0.0]
	var dashed_events := [0]
	var dash_probe := func(_t, e) -> void:
		dash_peak[0] = maxf(dash_peak[0], Vector2(body.velocity.x, body.velocity.z).length())
		if e.dashed: dashed_events[0] += 1
	await drive(body, motion, {"dash": true}, 1, dash_probe)
	await drive(body, motion, {}, 17, dash_probe)
	var dash_travel := dash_from.distance_to(body.global_position)
	print("COURIER_NUM dash from standing: travel=", snappedf(dash_travel, 0.01), " m in 0.3 s, peak speed=", snappedf(dash_peak[0], 0.01), " m/s, z=", snappedf(body.global_position.z - dash_from.z, 0.01))
	expect("an idle dash goes along the facing (-Z) about 2.2 x the walk for 0.3 s", dash_peak[0] >= Motion.DASH_SPEED - 0.01 and body.global_position.z < dash_from.z - 2.8 and absf(body.global_position.x - dash_from.x) < 0.01 and dashed_events[0] == 1, str(body.global_position - dash_from))
	expect("a dash takes off from the ground a little (the arc)", not motion.grounded or body.global_position.y < 0.5, "y=%.3f" % body.global_position.y)
	await drive(body, motion, {"dash": true}, 1, dash_probe)
	await drive(body, motion, {}, 20, dash_probe)
	expect("a dash pressed inside the cooldown (about 0.65 s after the first) is refused", dashed_events[0] == 1 and motion.dash_cooldown > 0.3, "events=%d cooldown=%.2f" % [dashed_events[0], motion.dash_cooldown])
	await drive(body, motion, {}, 70) # the cooldown (DASH_COOLDOWN) must be over too
	var from_x := body.global_position.x
	await drive(body, motion, {"dash": true, "move": Vector2(1, 0)}, 1, dash_probe)
	await drive(body, motion, {"move": Vector2(1, 0)}, 17, dash_probe)
	expect("after the cooldown a dash along the move input (+X) works", dashed_events[0] == 2 and body.global_position.x > from_x + 2.8, "events=%d dx=%.2f" % [dashed_events[0], body.global_position.x - from_x])
	await drive(body, motion, {}, 90) # lands, settles, the cooldown is over
	motion.launch(Vector3(0, 20, 0), true, true) # a long airtime: ~2.4 s
	await drive(body, motion, {}, 8)
	var air_events := [0]
	var air_probe := func(_t, e) -> void: if e.dashed: air_events[0] += 1
	await drive(body, motion, {"dash": true, "move": Vector2(0, -1)}, 1, air_probe)
	var air_vy := body.velocity.y
	await drive(body, motion, {"move": Vector2(0, -1)}, 16, air_probe)
	expect("a dash in the air works and keeps the courier up (a slight arc)", air_events[0] == 1 and air_vy > 1.0, "events=%d vy=%.2f" % [air_events[0], air_vy])
	await drive(body, motion, {}, 90, air_probe) # past the cooldown (DASH_COOLDOWN), still in the air
	await drive(body, motion, {"dash": true}, 1, air_probe)
	expect("one dash per airtime: a second one in the air is refused", air_events[0] == 1 and not motion.grounded, "events=%d grounded=%s" % [air_events[0], str(motion.grounded)])
	await drive(body, motion, {}, 120, air_probe)
	await drive(body, motion, {}, 20, air_probe) # no belly flop after the landing: the dash is back at once
	await drive(body, motion, {"dash": true}, 1, air_probe)
	expect("landing gives the dash back", air_events[0] == 2, "events=%d" % air_events[0])
	await drive(body, motion, {}, 120)
	# --- launch and ice
	await settle(body, motion)
	motion.launch(Vector3(2, 9, 0), true, true)
	await drive(body, motion, {}, 1)
	expect("launch sets velocity", absf(body.velocity.y - (9.0 - Motion.GRAVITY * DT)) < 0.01 and absf(body.velocity.x - 2.0) < 0.2, str(body.velocity))
	await drive(body, motion, {}, 150)
	cm = spawn(Vector3(0, 0, 15))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	await drive(body, motion, {"move": Vector2(0, -1)}, 60)
	motion.set_surface({"ice": true})
	var ice_start := body.global_position
	for i in 400:
		await physics_frame
		motion.step(body, {}, DT)
		if Vector2(body.velocity.x, body.velocity.z).length() < 0.01: break
	var ice_dist := ice_start.distance_to(body.global_position)
	print("COURIER_NUM ice stop distance=", snappedf(ice_dist, 0.01), " (ground 0.63)")
	expect("ice stop distance is several times longer", ice_dist > 2.5)
	motion.set_surface({})
	# --- determinism: capture / restore / replay
	fresh_world()
	block(world, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	cm = spawn(Vector3(0, 0, 0))
	body = cm[0]; motion = cm[1]
	await settle(body, motion)
	var script_inputs: Array = []
	for i in 120:
		script_inputs.append({"move": Vector2(sin(i * 0.1), -cos(i * 0.07)).limit_length(1.0), "jump": i % 37 == 5})
	for i in 40:
		await physics_frame
		motion.step(body, script_inputs[i], DT)
	var snapshot: Dictionary = motion.capture(body)
	var first_run: Array = []
	for i in range(40, 120):
		await physics_frame
		motion.step(body, script_inputs[i], DT)
		first_run.append(body.global_position)
	motion.restore(snapshot, body)
	var second_run: Array = []
	for i in range(40, 120):
		await physics_frame
		motion.step(body, script_inputs[i], DT)
		second_run.append(body.global_position)
	var worst := 0.0
	for i in first_run.size(): worst = maxf(worst, first_run[i].distance_to(second_run[i]))
	print("COURIER_NUM replay divergence max=", worst)
	expect("capture/restore replay is deterministic", worst < 0.0005)
	# --- authority anchor
	var anchor := Anchor.new()
	anchor.setup(body)
	expect("anchor fallback", anchor.anchor().is_equal_approx(body.global_position + Anchor.ANCHOR_OFFSET))
	anchor.set_pose(Vector3(1, 2, 3))
	expect("anchor from pose", anchor.anchor().is_equal_approx(Vector3(1, 3, 3)))
	expect("anchor rejects NaN", not anchor.set_pose(Vector3(NAN, 0, 0)))

# ------------------------------------------------------------------ rig
func run_rig() -> void:
	fresh_world()
	var times: Array = []
	for i in 6:
		var rig := Rig.new()
		var t0 := Time.get_ticks_usec()
		world.add_child(rig)
		rig.setup(i % 2, {})
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("COURIER_NUM rig build ms (first includes shared mesh generation): ", times)
	expect("rig build under 10 ms after the first", times.slice(1).all(func(t): return t < 10.0))
	var rig: Node3D = world.get_child(0)
	var skel: Skeleton3D = rig.skeleton()
	expect("19 bones", skel.get_bone_count() == 19, str(skel.get_bone_count()))
	var vertices := 0
	var mesh: ArrayMesh = (skel.get_child(0) as MeshInstance3D).mesh
	for s in mesh.get_surface_count(): vertices += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	print("COURIER_NUM vertices=", vertices, " surfaces=", mesh.get_surface_count())
	# animation cost
	var stats := {"steps": [0, 0], "jumped": 0, "landed": []}
	rig.footstep.connect(func(side): stats["steps"][side] += 1)
	rig.jumped.connect(func(): stats["jumped"] += 1)
	rig.landed.connect(func(speed): stats["landed"].append(snappedf(speed, 0.1)))
	rig.global_position = Vector3.ZERO
	var t1 := Time.get_ticks_usec()
	var speed := 5.0
	var slip_worst := 0.0
	var stance_samples := 0
	var prev_foot: Array = [Vector3.ZERO, Vector3.ZERO]
	var prev_stance: Array = [false, false]
	rig.snap({"velocity": Vector3(0, 0, -speed), "grounded": true, "yaw": 0.0})
	for tick in 300:
		rig.global_position += Vector3(0, 0, -speed * DT)
		rig.update(DT, {"velocity": Vector3(0, 0, -speed), "grounded": true, "yaw": 0.0, "carrying": false})
		if tick > 60:
			for i in 2:
				var foot := foot_world(rig, i)
				var stance := foot.y < Rig.ANKLE_H + 0.012
				if stance and prev_stance[i]:
					stance_samples += 1
					slip_worst = maxf(slip_worst, Vector2(foot.x - prev_foot[i].x, foot.z - prev_foot[i].z).length())
				prev_foot[i] = foot
				prev_stance[i] = stance
	var per_update := (Time.get_ticks_usec() - t1) / 300.0
	print("COURIER_NUM update cost us/frame=", snappedf(per_update, 0.1), " steps L/R=", stats["steps"], " worst stance foot slip per tick (m)=", snappedf(slip_worst, 0.0001), " stance samples=", stance_samples)
	expect("footsteps alternate at running cadence", stats["steps"][0] > 6 and absi(stats["steps"][0] - stats["steps"][1]) <= 1)
	expect("no foot sliding in stance (< 4 mm per tick)", slip_worst < 0.004)
	# jump events
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	for i in 30: rig.update(DT, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	var vy := 7.0
	for tick in 60:
		vy -= 17.0 * DT
		rig.global_position.y = maxf(rig.global_position.y + vy * DT, 0.0)
		var grounded := rig.global_position.y <= 0.0 and vy < 0.0
		rig.update(DT, {"velocity": Vector3(0, vy, 0), "grounded": grounded, "yaw": 0.0})
		if grounded: vy = 0.0
	expect("jumped / landed signals", stats["jumped"] == 1 and stats["landed"].size() == 1 and stats["landed"][0] > 5.0, str(stats))
	# carry reach
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": true})
	var grips := [Vector3(-0.25, 1.1, -0.45), Vector3(0.25, 1.1, -0.45)]
	for i in 90: rig.update(DT, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": true}, grips)
	var miss0: float = rig.hand_world(0).distance_to(grips[0])
	var miss1: float = rig.hand_world(1).distance_to(grips[1])
	print("COURIER_NUM carry reach error (m) L/R=", snappedf(miss0, 0.0001), "/", snappedf(miss1, 0.0001), " hands_center=", rig.hands_center(), " anchor=", rig.anchor())
	expect("hands reach the grips", miss0 < 0.02 and miss1 < 0.02)
	expect("anchor = position + offset", rig.anchor().is_equal_approx(rig.global_position + Rig.ANCHOR_OFFSET))
	# slope: ankles stay one ankle height above the ramp plane
	var slope_n := Vector3(0.0, cos(deg_to_rad(25.0)), sin(deg_to_rad(25.0))) # rises towards -Z
	rig.global_position = Vector3.ZERO
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
	for i in 60: rig.update(DT, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "floor_normal": slope_n})
	var slope_err := 0.0
	for i in 2:
		var f := foot_world(rig, i)
		var plane_y := -(slope_n.x * f.x + slope_n.z * f.z) / slope_n.y
		slope_err = maxf(slope_err, absf(f.y - plane_y - Rig.ANKLE_H))
	print("COURIER_NUM slope ankle error (m)=", snappedf(slope_err, 0.0001))
	expect("feet settle on a 25 degree slope", slope_err < 0.01)
	# replica: velocity derived from movement
	var replica := Rig.new()
	world.add_child(replica)
	replica.setup(1, {})
	replica.set_replica(true)
	replica.global_position = Vector3(5, 0, 0)
	var replica_steps := {"n": 0}
	replica.footstep.connect(func(_s): replica_steps["n"] += 1)
	for tick in 120:
		replica.global_position += Vector3(0, 0, -3.0 * DT)
		replica.update(DT, {"grounded": true, "yaw": 0.0})
	expect("replica animates from movement alone", replica_steps["n"] >= 3, str(replica_steps["n"]))

func shoot(cam: Camera3D, rig: Node3D, a: Dictionary) -> Image:
	var focus := rig.global_position + Vector3(0, 0.95, 0)
	var yaw := deg_to_rad(float(a["yaw"]))
	var pitch := deg_to_rad(float(a["pitch"]))
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * float(a["dist"])
	cam.global_position = focus + offset
	cam.look_at(focus + Vector3(0, float(a["height"]) - 0.95, 0), Vector3.UP)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var w := image.get_width()
	var h := image.get_height()
	return image.get_region(Rect2i(w / 2 - 230, h / 2 - 300, 460, 600))

func foot_world(rig: Node3D, i: int) -> Vector3:
	var sk: Skeleton3D = rig.skeleton()
	return rig.to_global(sk.get_bone_global_pose(Rig.B_FOOT[i]).origin)

# ------------------------------------------------------------------ frames
func run_frames() -> void:
	root.mode = Window.MODE_WINDOWED
	DirAccess.make_dir_recursive_absolute(out)
	fresh_world()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#f6ecd2")
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var checker := StandardMaterial3D.new()
	checker.albedo_color = Color("#f0d9a6")
	ground.material_override = checker
	world.add_child(ground)
	for k in range(-6, 7):
		var line := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = Vector3(0.04, 0.005, 40)
		line.mesh = quad
		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color("#8a7a55")
		line.material_override = line_mat
		line.position = Vector3(k * 0.5, 0.003, 0)
		world.add_child(line)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.make_current()
	var rigs: Array = []
	var poses := [
		{"name": "idle", "speed": 0.0, "air": 0, "carry": false, "ticks": 90},
		{"name": "walk", "speed": 2.2, "air": 0, "carry": false, "ticks": 70},
		{"name": "run", "speed": 5.0, "air": 0, "carry": false, "ticks": 80},
		{"name": "jump-rise", "speed": 3.0, "air": 1, "carry": false, "ticks": 80},
		{"name": "fall", "speed": 3.0, "air": 2, "carry": false, "ticks": 80},
		{"name": "land", "speed": 0.0, "air": 3, "carry": false, "ticks": 80},
		{"name": "carry-idle", "speed": 0.0, "air": 0, "carry": true, "ticks": 90},
		{"name": "carry-run", "speed": 5.0, "air": 0, "carry": true, "ticks": 80},
		{"name": "dive", "speed": 10.0, "air": 4, "carry": false, "ticks": 40},
		{"name": "flop", "speed": 0.0, "air": 0, "carry": false, "ticks": 40, "flop": 0.8},
		{"name": "getup", "speed": 0.0, "air": 0, "carry": false, "ticks": 40, "flop": 0.14},
	]
	var angles := [
		{"name": "front34", "yaw": 145.0, "pitch": -10.0, "dist": 5.2, "height": 1.0},
		{"name": "side", "yaw": -90.0, "pitch": -5.0, "dist": 5.2, "height": 0.95},
		{"name": "back", "yaw": 0.0, "pitch": -22.0, "dist": 6.2, "height": 1.2},
		{"name": "front", "yaw": 180.0, "pitch": -8.0, "dist": 5.2, "height": 1.0},
	]
	var sheet_rows: Array = []
	for pose in poses:
		var rig := Rig.new()
		world.add_child(rig)
		rig.setup(0, {})
		var grips := [Vector3(-0.25, 1.1, -0.45), Vector3(0.25, 1.1, -0.45)]
		rig.global_position = Vector3.ZERO
		var speed: float = pose["speed"]
		var vel := Vector3(0, 0, -speed)
		var y := 0.0
		var vy := 0.0
		rig.snap({"velocity": vel, "grounded": true, "yaw": 0.0, "carrying": pose["carry"]})
		var air: int = pose["air"]
		var landed_ticks := 0
		for tick in int(pose["ticks"]):
			var grounded := air != 4
			if air == 4: y = 1.0
			if air == 1:
				if tick == 40: vy = 7.0
			elif air == 2:
				if tick == 20: vy = 7.0
			elif air == 3:
				if tick == 20: vy = 7.0
			if vy != 0.0 or y > 0.0:
				vy -= 17.0 * DT
				y = maxf(y + vy * DT, 0.0)
				grounded = y <= 0.0 and vy < 0.0
				if grounded: vy = 0.0
			rig.global_position += Vector3(0, 0, -speed * DT)
			rig.global_position.y = y
			rig.update(DT, {"velocity": Vector3(vel.x, vy, vel.z), "grounded": grounded, "yaw": 0.0, "carrying": pose["carry"], "flop": pose.get("flop", 0.0)}, grips if pose["carry"] else [])
			# stop the sequence at the pose's moment
			if air == 1 and tick == 40 + 12: break
			if air == 2 and tick == 20 + 40: break
			if air == 3:
				if grounded and tick > 30: landed_ticks += 1
				if landed_ticks == 6: break
		await process_frame
		var row: Array = []
		for a in angles: row.append(await shoot(cam, rig, a))
		sheet_rows.append(row)
		var tag: String = pose["name"]
		# individual images for the closer look
		for i in row.size():
			(row[i] as Image).save_png("%s/%s-%s.png" % [out, tag, angles[i]["name"]])
		rig.queue_free()
		await process_frame
	# seats and hats, idle
	var variants := [[0, "cap"], [1, "cap"], [0, "hardhat"], [1, "beanie"]]
	var variant_row: Array = []
	for v in variants:
		var rig := Rig.new()
		world.add_child(rig)
		rig.setup(v[0], {"hat": v[1]})
		rig.global_position = Vector3.ZERO
		rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
		for i in 20: rig.update(DT, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0})
		await process_frame
		var shot := await shoot(cam, rig, {"name": "variant", "yaw": 160.0, "pitch": -8.0, "dist": 3.6, "height": 1.35})
		variant_row.append(shot)
		shot.save_png("%s/variant-%d-%s.png" % [out, v[0], v[1]])
		rig.queue_free()
		await process_frame
	sheet_rows.append(variant_row)
	# contact sheet
	var cols := angles.size()
	var cell_w := 460
	var cell_h := 600
	var sheet := Image.create_empty(cell_w * cols, cell_h * sheet_rows.size(), false, Image.FORMAT_RGBA8)
	for r in sheet_rows.size():
		for c in cols:
			var cell: Image = sheet_rows[r][c]
			cell.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(c * cell_w, r * cell_h))
	var half := Image.create_empty(cell_w * cols / 2, cell_h * sheet_rows.size() / 2, false, Image.FORMAT_RGBA8)
	half.copy_from(sheet)
	half.resize(cell_w * cols / 2, cell_h * sheet_rows.size() / 2, Image.INTERPOLATE_LANCZOS)
	print("COURIER_FRAMES sheet ", sheet.save_png(out + "/sheet-" + "ink.png") == OK, " half ", half.save_png(out + "/sheet-" + "ink-half.png") == OK)
