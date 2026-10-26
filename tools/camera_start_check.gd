extends SceneTree
## Headless check of the gameplay camera where play starts: the start of every level (each carrier's spot and first facing in a
## carry level, the start pad in a balloon room) and every yard spot of the lobby, with the real follow camera
## (game/follow_camera.gd, first person: the default) and the level and lobby collision. At each start the eye must sit at
## EYE_HEIGHT over the floor (a carrier: CARRY_EYE_HEIGHT, behind its hands), look a little down (the default pitch), have nothing solid right in front of it, and the centre of
## the view must land on floor ahead, not on a wall.
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 600 -- <Summer> --headless \
##     --audio-driver Dummy --fixed-fps 60 --path demo -s "$PWD/tools/camera_start_check.gd"
## Prints CAMERA_START ok=<bool> and exits 0 only when every start passes.
const LevelWorld := preload("res://levels/level_world.gd")
const LobbySpace := preload("res://lobby_space.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const FollowCamera := preload("res://game/follow_camera.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const CARRY_LOOK := 0.5 ## game_run.gd CARRY_LOOK
const CLEAR_AHEAD := 1.5 ## m in front of the eye that must be free
const SOLID := 1 | 512 | StepTiles.TILE_LAYERS_ALL ## level blocks, the lobby yard and the floors of a stage round (one collision bit per floor: a ray that means "any tile")
const FLOORS := SOLID | 16 ## and the floors that are movers (level 18's floor of blinking tiles), tried only when the view centre finds nothing solid (a start gate is a mover too)
var failures := 0
var checked := 0
var world: Node3D
var camera := Camera3D.new()
var view := FollowCamera.new()

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	world.add_child(camera)
	view.configure(camera)
	var levels: Node3D = LevelWorld.new()
	world.add_child(levels)
	await levels.build("authority")
	for k in levels.level_count():
		levels.set_active_level(k)
		await _frames(2)
		var start: Dictionary = levels.team_start(k, 2)
		var yaw := float(start.yaw)
		if "carry" in levels.modes(k):
			var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
			for slot in 2:
				var feet: Vector3 = start.pos[slot]
				var partner: Vector3 = start.pos[1 - slot]
				await _look_from("level %d %s carrier %d" % [k + 1, levels.title(k), slot + 1], feet, yaw + (-CARRY_LOOK if (partner - feet).dot(right) > 0.0 else CARRY_LOOK), (feet - partner) * Vector3(1, 0, 1))
		else:
			await _look_from("level %d %s" % [k + 1, levels.title(k)], start.spot, yaw)
	levels.set_active_level(-1)
	var yard: Node3D = LobbySpace.ensure(world, "authority")
	yard.set_active(true)
	await _frames(2)
	for slot in 10:
		var spot := WalkInLobby.spawn(slot, 10)
		var floor_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 3.0, spot + Vector3.DOWN * 5.0, SOLID))
		var feet := Vector3(spot.x, (floor_hit.position as Vector3).y if not floor_hit.is_empty() else spot.y, spot.z)
		await _look_from("lobby spot %d" % slot, feet, WalkInLobby.CAMERA_YAW)
	print("CAMERA_START ok=", failures == 0, " starts=", checked, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _look_from(label: String, feet: Vector3, yaw: float, carry_back := Vector3.ZERO) -> void:
	view.reset_lag()
	view.update_first_person(1.0 / 60.0, feet, yaw, view.default_pitch(), carry_back)
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var down := rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0)))
	var space := world.get_world_3d().direct_space_state
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + forward * CLEAR_AHEAD, SOLID))
	var ahead := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + forward * 60.0, SOLID))
	if ahead.is_empty(): ahead = space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + forward * 60.0, FLOORS))
	var floor_ahead: bool = not ahead.is_empty() and (ahead.normal as Vector3).y > 0.7 and absf((ahead.position as Vector3).y - feet.y) < 1.5
	var height := eye.y - feet.y
	var eye_height := FollowCamera.CARRY_EYE_HEIGHT if carry_back != Vector3.ZERO else FollowCamera.EYE_HEIGHT
	var ok := absf(height - eye_height) < 0.05 and down > 5.0 and down < 20.0 and face.is_empty() and floor_ahead
	checked += 1
	if not ok: failures += 1
	print("CAMERA_START ", "ok   " if ok else "FAIL ", label, ": eye %.2f m up, looks down %.0f deg, %s in front, centre of view on %s" % [height, down,
		"nothing" if face.is_empty() else "something", ("floor %.1f m ahead" % eye.distance_to(ahead.position) if floor_ahead else "a wall at %s" % ahead.get("position")) if not ahead.is_empty() else "nothing"])
