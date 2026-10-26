extends SceneTree
## Render cost of the show's levels and lobby in the look in use (the party look in show mode; `--look=facility` after the `--` for the facility look):
## draw calls, objects, primitives and milliseconds per frame from the start spot and from a wide view. Offscreen binary only (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 [--rendering-method gl_compatibility --rendering-driver opengl3] --path demo -s $PWD/tools/party_perf.gd -- [--levels=14,16,19] [--lobby]
## Prints PARTY_PERF lines. The time is the whole pipeline per frame on this machine's GPU (CPU recording plus GPU, queued back to back, one read-back).
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const Rig := preload("res://courier/courier_rig.gd")
var level_list: Array = [14, 16, 19]
var with_lobby := false
var world: Node3D
var levels: Node3D
var camera: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--lobby": with_lobby = true
		if a.begins_with("--levels="):
			level_list = []
			for part in a.trim_prefix("--levels=").split(","): level_list.append(int(part))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func info() -> String:
	var get := func(what: int) -> int: return RenderingServer.get_rendering_info(what)
	return "draws=%d objects=%d primitives=%d" % [get.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), get.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), get.call(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]

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
	print("PARTY_PERF %s %.2f ms per frame (%.0f fps) at %s, %s" % [label, rounds[2], 1000.0 / rounds[2], str(root.get_visible_rect().size), info()])

func run() -> void:
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	world = Node3D.new()
	root.add_child(world)
	levels = LevelWorld.new()
	world.add_child(levels)
	var began := Time.get_ticks_msec()
	await levels.build("local")
	print("PARTY_PERF built %d levels in %d ms (%s, %s)" % [levels.level_count(), Time.get_ticks_msec() - began, RenderingServer.get_current_rendering_method(),
		"facility" if OS.get_cmdline_user_args().has("--look=facility") else "party"])
	camera = Camera3D.new()
	camera.fov = 62.0
	world.add_child(camera)
	camera.current = true
	for number: int in level_list:
		var k := number - 1
		var shown := Time.get_ticks_usec()
		levels.set_active_level(k)
		print("PARTY_PERF level %d shown in %.1f ms" % [number, float(Time.get_ticks_usec() - shown) / 1000.0])
		levels.set_clock(0.0)
		var start: Dictionary = levels.start_pose(k)
		var stage: Dictionary = levels._levels[k].data.stage
		var pads: Array = stage.get("starts", [])
		var origin: Vector3 = levels.level_origin(k)
		var spots: Array = [start.a, start.b]
		if not pads.is_empty(): # a stage round: the couriers stand on the pads
			for seat in 2:
				var pad: Vector3 = pads[seat % pads.size()]
				spots[seat] = origin + pad
		var middle: Vector3 = ((spots[0] as Vector3) + (spots[1] as Vector3)) * 0.5
		var pegs: Array = []
		for seat in 2:
			var rig := Rig.new()
			world.add_child(rig)
			rig.setup(seat, {})
			rig.global_position = spots[seat]
			rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": float(start.yaw), "carrying": false})
			pegs.append(rig)
		await frames(3)
		if pads.is_empty():
			camera.global_position = middle + Vector3(0.0, 2.4, 4.2)
			camera.look_at(middle + Vector3(0.0, 1.6, -12.0), Vector3.UP)
		else: # the stage view: behind the courier on its pad, looking over the field (arm 10.5 m, 12.4 degrees down)
			camera.global_position = (spots[0] as Vector3) + Vector3(0.0, 3.3, 10.2)
			camera.look_at((spots[0] as Vector3) + Vector3(0.0, 1.0, -10.0), Vector3.UP)
		await frames(2)
		await measure("level %d player view" % number)
		var reach: float = float(stage.ground.size[0]) if not pads.is_empty() else 0.0
		if pads.is_empty():
			camera.global_position = middle + Vector3(-6.0, 14.0, 13.0)
			camera.look_at(middle + Vector3(0.0, 1.5, -34.0), Vector3.UP)
		else: # the whole field from the side and above
			camera.global_position = origin + Vector3(0.0, reach * 0.55, reach * 0.95)
			camera.look_at(origin + Vector3(0.0, -reach * 0.1, 0.0), Vector3.UP)
		await frames(2)
		await measure("level %d wide view" % number)
		if not pads.is_empty(): # half of the tiles gone: the scattered holes of a round half way through
			var bytes := PackedByteArray()
			bytes.resize(levels.tile_count(k))
			for index in bytes.size():
				if index % 2 == 1: bytes[index] = StepTiles.PRE_GONE
			levels.set_tile_steps(k, bytes)
			await frames(3)
			await measure("level %d wide view, every second tile gone" % number)
			levels.set_tile_steps(k, PackedByteArray())
		for rig: Node in pegs: rig.queue_free()
	if with_lobby:
		levels.set_active_level(-1)
		LobbySpace.ensure(world, "local")
		LobbySpace.sync(world, "local", true)
		await frames(3)
		camera.global_position = Layout.ORIGIN + Vector3(0.0, 2.4, 6.5)
		camera.look_at(Layout.ORIGIN + Vector3(0.0, 1.5, -4.0), Vector3.UP)
		await frames(2)
		await measure("lobby player view")
	quit(0)
