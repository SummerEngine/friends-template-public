extends SceneTree
## Dev check of the backdrop (style/backdrop.gd): frames of levels and the lobby (gameplay camera and a wide shot), render cost, build time.
## Offscreen binary only (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/backdrop_shots.gd -- --shots=<dir> [--levels=1,2,7,12,18,24] [--lobby] [--backdrop=off] [--perf=<level>] [--t=<seconds>]
## Names: level<NN>_play.png, level<NN>_wide.png, lobby_play.png, lobby_wide.png; prints GW_BACKDROP lines (draw calls, objects, primitives, ms per frame).
const LevelWorld := preload("res://levels/level_world.gd")
const LobbySpace := preload("res://lobby_space.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const Backdrop := preload("res://style/backdrop.gd")
const Rig := preload("res://courier/courier_rig.gd")
var shots := ""
var level_list: Array = [1, 2, 7, 12, 18, 24]
var with_lobby := false
var perf_level := 0
var clock_t := 0.0
var world: Node3D
var levels: Node3D
var camera: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
		if a == "--lobby": with_lobby = true
		if a == "--backdrop=off": Backdrop.enabled = false
		if a.begins_with("--perf="): perf_level = int(a.trim_prefix("--perf="))
		if a.begins_with("--t="): clock_t = float(a.trim_prefix("--t="))
		if a.begins_with("--levels="):
			level_list = []
			for part in a.trim_prefix("--levels=").split(","): level_list.append(int(part))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func shot(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	await frames(2)
	RenderingServer.force_draw(false)
	print("GW_BACKDROP shot ", name, " ", root.get_texture().get_image().save_png("%s/%s.png" % [shots, name]) == OK)

func peg(at: Vector3, seat: int, yaw: float) -> Node3D:
	var rig := Rig.new()
	world.add_child(rig)
	rig.setup(seat, {})
	rig.global_position = at
	rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false})
	for i in 3: rig.update(1.0 / 60.0, {"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false})
	return rig

func info() -> String:
	return "draws=%d objects=%d primitives=%d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]

## Cost of the current camera: `count` forced draws queued back to back, then one read-back of the frame (it waits for the GPU), so the time is the
## whole pipeline per frame (CPU recording plus GPU), not the display's refresh. Median of five rounds.
func measure(label: String, count := 120) -> void:
	for i in 20: RenderingServer.force_draw(false)
	root.get_texture().get_image()
	var rounds: Array = []
	for round_index in 5:
		var begin := Time.get_ticks_usec()
		for i in count: RenderingServer.force_draw(false)
		root.get_texture().get_image()
		rounds.append(float(Time.get_ticks_usec() - begin) / 1000.0 / count)
	rounds.sort()
	var ms: float = rounds[2]
	print("GW_BACKDROP perf %s %.2f ms per frame (%.0f fps) at %s, rounds %s, %s" % [label, ms, 1000.0 / ms, str(root.get_visible_rect().size), str(rounds.map(func(v): return snappedf(v, 0.01))), info()])

func gameplay_view(k: int) -> void:
	var start: Dictionary = levels.start_pose(k)
	var middle: Vector3 = (start.a + start.b) * 0.5
	var forward := Vector3(-sin(float(start.yaw)), 0.0, -cos(float(start.yaw)))
	camera.global_position = middle - forward * 7.0 + Vector3(0.0, 3.6, 0.0)
	camera.look_at(middle + forward * 14.0 + Vector3(0.0, 0.5, 0.0), Vector3.UP)

func wide_view(k: int) -> void:
	var start: Dictionary = levels.start_pose(k)
	var goal: Dictionary = levels.goal_volume(k)
	var middle: Vector3 = (start.a + start.b) * 0.5
	var mid: Vector3 = (middle + (goal.p as Vector3)) * 0.5
	var forward := Vector3((goal.p as Vector3).x - middle.x, 0.0, (goal.p as Vector3).z - middle.z).normalized()
	var span := middle.distance_to(goal.p)
	camera.global_position = middle - forward * (span * 0.35 + 25.0) + Vector3(0.0, 22.0 + span * 0.2, 0.0)
	camera.look_at(mid + forward * 30.0 + Vector3(0.0, -10.0, 0.0), Vector3.UP)

func run() -> void:
	preload("res://style/surfaces.gd").set_ink(true) # frames of the comic backdrop (the facility look builds a plain room instead)
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	levels = LevelWorld.new()
	world.add_child(levels)
	var t0 := Time.get_ticks_msec()
	await levels.build("local")
	print("GW_BACKDROP built %d levels in %d ms, backdrop %s" % [levels.level_count(), Time.get_ticks_msec() - t0, "on" if Backdrop.enabled else "off"])
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.1
	world.add_child(camera)
	camera.current = true
	for number: int in level_list:
		var k := number - 1
		var t1 := Time.get_ticks_usec()
		levels.set_active_level(k)
		print("GW_BACKDROP level %d shown in %.1f ms" % [number, float(Time.get_ticks_usec() - t1) / 1000.0])
		levels.set_clock(clock_t)
		var start: Dictionary = levels.start_pose(k)
		var pegs := [peg(start.a, 0, float(start.yaw)), peg(start.b, 1, float(start.yaw))]
		await frames(3)
		gameplay_view(k)
		await shot("level%02d_play" % number)
		if number == perf_level: await measure("level%02d play" % number)
		wide_view(k)
		await shot("level%02d_wide" % number)
		if number == perf_level: await measure("level%02d wide" % number)
		for p: Node in pegs: p.queue_free()
	if with_lobby:
		levels.set_active_level(-1)
		var room := LobbySpace.ensure(world, "local")
		LobbySpace.sync(world, "local", true)
		await frames(3)
		camera.global_position = Layout.ORIGIN + Vector3(0.0, 5.0, 9.5)
		camera.look_at(Layout.ORIGIN + Vector3(0.0, 1.2, -2.0), Vector3.UP)
		await shot("lobby_play")
		camera.global_position = Layout.ORIGIN + Vector3(0.0, 40.0, 70.0)
		camera.look_at(Layout.ORIGIN + Vector3(0.0, -20.0, -10.0), Vector3.UP)
		await shot("lobby_wide")
		if perf_level == -1: await measure("lobby")
		room = null
	quit(0)
