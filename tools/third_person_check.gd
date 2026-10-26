extends SceneTree
## Headless check of the show's shoulder camera (game/follow_camera.gd `set_shoulder_view`, modes.json `camera: third`) along every show level's
## route, with the real level collision: a courier at every metre of the route, looking along the route and 50 degrees to either side, the
## camera settled. At each spot the camera must not sit inside a solid (a sphere of CLEARANCE m at the eye finds no static block); looking along
## the route it also must keep at least MIN_ARM m from the courier's focus (closer and the own body is hidden), must see the courier (nothing solid between the eye
## and the courier's head), and its view centre must not be right up against a wall (a solid within NEAR_WALL m straight ahead of the eye).
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/third_person_check.gd" [-- --verbose --level=17]
## Prints THIRD_PERSON lines (the worst spots of each level) and THIRD_PERSON ok=<bool> last; exits 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const FollowCamera := preload("res://game/follow_camera.gd")
const SOLID := 1 | 256 ## the level's static blocks and the camera blockers (movers pass the camera: the start gate, sweepers and hammers are only there for a moment)
const STEP := 1.0 ## m along the route between two spots
const SIDE_YAWS := [0.0, 0.87, -0.87] ## rad: along the route, and 50 degrees to each side
const CLEARANCE := 0.22 ## m: the camera's near plane and a little more
const MIN_ARM := 1.9 ## m from the courier's focus (follow_camera.gd BODY_HIDE_DISTANCE is 0.9: the body is hidden, not clipped; below this the framing is too tight)
const NEAR_WALL := 1.0 ## m
const FOCUS := Vector3(0.0, 1.0, 0.0) ## game_run.gd CAMERA_FOCUS
var verbose := false
var only_level := 0
var failures := 0
var spots := 0
var world: Node3D
var camera := Camera3D.new()
var view := FollowCamera.new()

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--verbose": verbose = true
		if argument.begins_with("--level="): only_level = int(argument.trim_prefix("--level="))
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	world.add_child(camera)
	view.configure(camera)
	view.set_first_person(false)
	view.set_shoulder_view(true)
	var levels: Node3D = LevelWorld.new()
	world.add_child(levels)
	await levels.build("authority")
	for k in levels.level_count():
		if not ("show" in levels.modes(k)): continue
		if only_level > 0 and k + 1 != only_level: continue
		levels.set_active_level(k)
		await _frames(2)
		await _level(levels, k)
	print("THIRD_PERSON ok=", failures == 0, " spots=", spots, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _level(levels: Node3D, k: int) -> void:
	var route: PackedVector3Array = levels.route(k)
	var bad: Array = []
	var worst_arm := 99.0
	var count := 0
	for i in route.size() - 1:
		var from := route[i]
		var to := route[i + 1]
		var length := from.distance_to(to)
		if length < 0.01: continue
		var along := (to - from) / length
		var base_yaw := atan2(-along.x, -along.z)
		var at := 0.0
		while at < length:
			var feet := from + along * at
			for turn: float in SIDE_YAWS:
				var problem := _look(feet, base_yaw + turn, turn == 0.0)
				count += 1
				worst_arm = minf(worst_arm, problem.arm)
				if not (problem.what as String).is_empty(): bad.append("%s at %s yaw %.0f deg (route %+.0f) (arm %.1f m)" % [problem.what, _local(levels, k, feet), rad_to_deg(base_yaw + turn), rad_to_deg(turn), problem.arm])
			at += STEP
	spots += count
	failures += bad.size()
	print("THIRD_PERSON level %d %s: %d spots, %d problems, shortest arm %.1f m" % [k + 1, levels.title(k), count, bad.size(), worst_arm])
	for line in bad.slice(0, 40 if verbose else 8): print("THIRD_PERSON   ", line)

func _local(levels: Node3D, k: int, feet: Vector3) -> String:
	var local: Vector3 = feet - levels.level_origin(k)
	return "(%.1f, %.1f, %.1f)" % [local.x, local.y, local.z]

## One spot: the camera settled behind a courier at `feet` looking along `yaw`. {"what": "" or the problem, "arm": m}.
func _look(feet: Vector3, yaw: float, along: bool) -> Dictionary:
	view.reset_lag()
	var focus := feet + FOCUS
	var body := SphereShape3D.new()
	body.radius = 0.35
	var stand := PhysicsShapeQueryParameters3D.new()
	stand.shape = body
	stand.transform = Transform3D(Basis.IDENTITY, focus)
	stand.collision_mask = SOLID
	stand.collide_with_areas = false
	if not world.get_world_3d().direct_space_state.intersect_shape(stand, 1).is_empty(): return {"what": "", "arm": 99.0} # the route grazes a solid here: nobody stands there
	for i in 4: view.update(1.0 / 60.0, focus, yaw, view.default_pitch())
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var arm := eye.distance_to(focus)
	var space := world.get_world_3d().direct_space_state
	var what := ""
	var ball := SphereShape3D.new()
	ball.radius = CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis.IDENTITY, eye)
	query.collision_mask = SOLID
	query.collide_with_areas = false
	if not space.intersect_shape(query, 1).is_empty(): what = "camera inside a solid"
	elif not along: pass # a player who turns the view into a wall at his shoulder gets the arm pulled in (the clipped camera), that is no fault of the level
	elif not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, focus, SOLID)).is_empty(): what = "courier hidden behind a solid"
	elif arm < MIN_ARM: what = "camera too close"
	elif not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + forward * NEAR_WALL, SOLID)).is_empty(): what = "wall in the camera's face"
	return {"what": what, "arm": arm}
