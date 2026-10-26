extends SceneTree
## Dev check: the level world and the lobby yard side by side in one world (client look). Prints the zone/placement numbers and, with --shots=<dir>,
## renders the lobby (yard on, level hidden) and a level (yard off). Offscreen binary only:
##   ... <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 --path demo \
##     -s $PWD/tools/level_lobby_check.gd -- --dir=$PWD/tools/level_testdata --shots=<dir>
const LevelWorld := preload("res://levels/level_world.gd")
const LobbySpace := preload("res://lobby_space.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const TitleCamera := preload("res://client/friends_title_camera.gd")
var shots := ""
var dir := "res://levels"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
		if a.begins_with("--dir="): dir = a.trim_prefix("--dir=")
	run.call_deferred()

func shot(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	print("GW_LOBBYCHECK shot ", name, " ", root.get_texture().get_image().save_png("%s/%s.png" % [shots, name]) == OK)

func run() -> void:
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var levels := LevelWorld.new()
	levels.level_dir = dir
	world.add_child(levels)
	await levels.build("local")
	print("GW_LOBBYCHECK levels=", levels.level_count(), " course_section count=", CourseSection.level_count(dir), " plan=", CourseSection.plan(CourseSection.CHALLENGE, 1), " orders=", CourseSection.orders().keys())
	var room := LobbySpace.ensure(world, "local")
	print("GW_LOBBYCHECK yard bodies=", room.placements.size(), " pads=", Layout.pads().map(func(p): return p.title))
	var faces := {} # the walls' inner faces and the slab's width (yard-local), against Layout.interior_rect(): the yard is cut to the show's circles
	for placement: Dictionary in room.placements:
		var at: Vector3 = (placement.origin as Vector3) - Layout.ORIGIN
		var size: Vector3 = placement.size
		match str(placement.name):
			"wall_w": faces.west = at.x + size.x * 0.5
			"wall_e": faces.east = at.x - size.x * 0.5
			"wall_n": faces.north = at.z + size.z * 0.5
			"wall_s": faces.south = at.z - size.z * 0.5
			"yard_slab": faces.slab = size.x
	var rect := Layout.interior_rect()
	var fits := is_equal_approx(float(faces.get("west", INF)), rect.position.x) and is_equal_approx(float(faces.get("east", INF)), rect.end.x) \
		and is_equal_approx(float(faces.get("north", INF)), rect.position.y) and is_equal_approx(float(faces.get("south", INF)), rect.end.y) and is_equal_approx(float(faces.get("slab", 0.0)), rect.size.x)
	print("GW_LOBBYCHECK yard walls ", faces, " interior ", rect, " fit=", fits)
	if not fits:
		quit(1)
		return
	var camera := Camera3D.new()
	camera.far = 600.0
	world.add_child(camera)
	camera.current = true
	levels.set_active_level(-1)
	LobbySpace.sync(world, "local", true)
	camera.global_position = Layout.ORIGIN + Vector3(0, 15, 12.5) # over the south wall, the whole 35 m yard in the frame
	camera.look_at(Layout.ORIGIN + Vector3(0, 0, -4), Vector3.UP)
	await shot("lobby")
	LobbySpace.sync(world, "local", false)
	levels.set_active_level(1)
	levels.set_clock(2.0)
	var start: Dictionary = levels.start_pose(1)
	var title := TitleCamera.new()
	world.add_child(title)
	title.configure(camera, start.a, start.b, levels.route(1)[1])
	title.set_process(false)
	print("GW_LOBBYCHECK title camera at ", camera.global_position, " looking from behind ", title.behind)
	await shot("level_title_view")
	title.stop()
	camera.global_position = (start.a + start.b) * 0.5 + Vector3(0, 4.5, 9)
	camera.look_at((start.a + start.b) * 0.5 + Vector3(0, 1.2, -6), Vector3.UP)
	await shot("level_start")
	quit(0)
