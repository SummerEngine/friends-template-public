extends SceneTree
## The show's lobby yard as the shoulder camera and a free camera see it: spawn, overview, the hero circle, rows, close-ups. A small level directory
## keeps the world build short (the circles come from the real round list, not from the level world). The project's own demo/cast is what you see.
## Offscreen binary only, never windowed:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s "$PWD/tools/lobby_frames.gd" -- --shots=<dir> [--prefix=a_] [--only=name,name] [--count=2] [--dir=$PWD/tools/level_testdata] (a small level directory: the world build is short)
## `--resolution 844x390` is the phone. Prints LOBBY_FRAMES lines; the shot names are the first column of `views()`.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const WalkInMarkers := preload("res://client/walk_in_markers.gd")
const TeamCast := preload("res://style/team_cast.gd")

var shots := ""
var prefix := ""
var only: PackedStringArray = []
var players := 2
var level_dir := ""
var holder: Node3D
var camera: Camera3D

## What WalkInMarkers.build asks the game for: the floor under a point (the yard is flat).
class FloorAt extends RefCounted:
	func floor_at(point: Vector3) -> Vector3: return point

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--count="): players = int(argument.trim_prefix("--count="))
		if argument.begins_with("--dir="): level_dir = argument.trim_prefix("--dir=")
	create_timer(170.0).timeout.connect(func() -> void:
		print("LOBBY_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

## [eye, look-at] of the shoulder camera (game/follow_camera.gd: arm 5.4 m, pitch -13 degrees, the view centre 1.35 m over the focus) behind a player standing at `feet`, looking along `yaw` (0 = north, PI/2 = west).
func shoulder_view(feet: Vector3, yaw := 0.0) -> Array:
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := feet + Vector3(0.0, 3.4, 0.0) - ahead * 5.3
	return [eye, eye + (ahead * cos(deg_to_rad(13.0)) + Vector3.DOWN * sin(deg_to_rad(13.0))) * 8.0]

## [name, eye, look-at, couriers (yard-local... relative to THE SHOW's circle centre)]
func views() -> Array:
	var origin := WalkInLobby.ORIGIN
	var centre := WalkInLobby.center(WalkInLobby.shown_course())
	var spawn := WalkInLobby.spawn(0)
	var ring := origin + WalkInLobby.wardrobe_center()
	var room := WalkInLobby.interior_rect()
	var rows: Array = []
	for slot in players: rows.append(WalkInLobby.spawn(slot) - centre)
	var list: Array = [
		["spawn"] + shoulder_view(spawn) + [rows],
		["yard", origin + Vector3(0.0, 15.0, 12.5), origin + Vector3(0.0, 0.0, -4.0), []],
		["overhead", origin + Vector3(0.0, 34.0, 1.0), origin + Vector3(0.0, 0.0, -2.0), []],
		["show", centre + Vector3(0.0, 2.6, 5.4), centre + Vector3(0.0, 1.6, -2.0), [Vector3(-0.8, 0.0, 0.0), Vector3(0.8, 0.0, 0.2)]],
		["on_show"] + shoulder_view(centre) + [[Vector3.ZERO, Vector3(1.4, 0.0, 0.9)]],
		["west"] + shoulder_view(WalkInLobby.center("r29")) + [[WalkInLobby.center("r29") - centre]],
		["east"] + shoulder_view(WalkInLobby.center("r32")) + [[WalkInLobby.center("r32") - centre]],
		["rear_a"] + shoulder_view(WalkInLobby.center("r25")) + [[WalkInLobby.center("r25") - centre]],
		["pick", WalkInLobby.center("r30") + Vector3(0.0, 2.1, 4.2), WalkInLobby.center("r30") + Vector3(0.0, 1.3, -1.5), [WalkInLobby.center("r30") - centre + Vector3(-0.5, 0.0, 0.0)]],
		["pad_close", WalkInLobby.center("r29") + Vector3(2.4, 1.6, 3.2), WalkInLobby.center("r29") + Vector3(0.0, 0.6, 0.0), []],
		["corner_nw", origin + Vector3(room.position.x + 8.0, 4.0, -2.0), origin + Vector3(room.position.x + 0.5, 1.2, room.position.y + 1.0), []],
		["corner_se", origin + Vector3(room.end.x - 9.0, 5.0, -8.0), origin + Vector3(room.end.x - 0.5, 0.6, room.end.y - 0.5), []],
		["edge", origin + Vector3(room.position.x + 1.3, 3.0, 8.0), origin + Vector3(room.position.x + 1.3, 0.0, -10.0), []],
		["north", origin + Vector3(0.0, 2.4, -3.0), origin + Vector3(0.0, 2.2, room.position.y), []],
		["phone_spawn"] + shoulder_view(spawn) + [rows],
		["nook"] + shoulder_view(ring, PI * 0.5) + [[ring - centre]],
		["nook_walk"] + shoulder_view(origin + Vector3(room.position.x + 6.0, 0.0, 7.2), PI * 0.5) + [[origin + Vector3(room.position.x + 6.0, 0.0, 7.2) - centre]],
		["nook_wide", origin + Vector3(room.position.x + 8.5, 4.2, 4.6 + 7.5), ring + Vector3(-0.5, 1.0, -0.8), []],
	]
	return list

func run() -> void:
	if shots == "":
		print("LOBBY_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	var world := LevelWorld.new()
	if level_dir != "": world.level_dir = level_dir
	holder.add_child(world)
	await world.build("local")
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 4000.0 # as the game camera (Camera3D default); the candy world reaches 2600 m (the cloud wall)
	holder.add_child(camera)
	camera.current = true
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	LobbySpace.ensure(holder, "local")
	world.set_active_level(-1)
	LobbySpace.sync(holder, "local", true)
	var course := WalkInLobby.shown_course()
	var centre := WalkInLobby.center(course)
	var markers := WalkInMarkers.new()
	holder.add_child(markers)
	markers.build(FloorAt.new())
	markers.set_shown(true)
	var round_pads: Array = []
	for entry: Dictionary in WalkInLobby.shown_pads():
		var stood := [{"seat": 0, "color": TeamCast.player_color(0)}, {"seat": 1, "color": TeamCast.player_color(1)}] if str(entry.course) == course else []
		round_pads.append({"course": entry.course, "counting": false, "occupants": stood})
	markers.present({"pads": round_pads, "lamps": [{"seat": 0}, {"seat": 1}]}, centre)
	var made := 0
	for view: Array in views():
		if not only.is_empty() and not str(view[0]) in only: continue
		var pegs: Array = []
		var seat := 0
		for spot: Vector3 in view[3]:
			var rig: Node3D = CharRig.new()
			holder.add_child(rig)
			rig.setup(seat, {})
			rig.global_position = centre + spot
			var stand := {"velocity": Vector3.ZERO, "grounded": true, "yaw": PI * 0.5 if str(view[0]).begins_with("nook") else 0.0, "carrying": false}
			rig.snap(stand)
			for i in 3: rig.update(1.0 / 60.0, stand)
			pegs.append(rig)
			seat += 1
		camera.global_position = view[1]
		camera.look_at(view[2], Vector3.UP)
		await frames(4)
		RenderingServer.force_draw(false)
		var file := "%s/%s%s.png" % [shots, prefix, view[0]]
		print("LOBBY_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK)
		for rig: Node in pegs: rig.queue_free()
		made += 1
	markers.queue_free()
	LobbySpace.sync(holder, "local", false)
	print("LOBBY_FRAMES ok=", made > 0, " shots=", made)
	quit(0 if made > 0 else 1)
