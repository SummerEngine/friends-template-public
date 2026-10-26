extends Node
## Drives the gameplay camera through slow framings of the start area while the
## local title menu is up (the tree is paused, so the game's own camera update
## is idle). Each menu page has a framing; changes ease over about a second.
## The game's camera code takes over again on stop(); nothing else is touched.
const VIEWS := {
	# yaw (deg, around the pair from behind the start), distance, height,
	# look height, screen shift (deg, + puts the pair right of centre), sway (deg)
	"main": [34.0, 6.4, 1.15, 0.95, 17.0, 14.0],
}
var camera: Camera3D
var centre := Vector3.ZERO
var behind := Vector3.BACK
var active := false
var clock := 0.0
var _current: Array = VIEWS["main"].duplicate()
var _target: Array = VIEWS["main"].duplicate()

func _init() -> void:
	name = "FriendsTitleCamera"
	process_mode = Node.PROCESS_MODE_ALWAYS

## `a`, `b`: the two couriers' positions, `ahead`: a point further along the level (LevelWorld.route(k)[1]); "behind" is the side away from it.
func configure(game_camera: Camera3D, a: Vector3, b: Vector3, ahead: Vector3) -> void:
	camera = game_camera
	centre = (a + b) * 0.5
	# The couriers face each other across the painting; the level runs along the horizontal perpendicular.
	var across := (b - a)
	across.y = 0.0
	behind = across.normalized().cross(Vector3.UP)
	if (ahead - centre).dot(behind) > 0.0: behind = -behind
	active = camera != null
	_apply(0.0)

func set_view(page: String) -> void:
	_target = VIEWS.get(page, VIEWS["main"]).duplicate()

func stop() -> void:
	active = false

func _process(delta: float) -> void:
	if not active or not is_instance_valid(camera): return
	var d := minf(delta, 0.05)
	clock += d
	var blend := 1.0 - exp(-2.2 * d)
	for index in _current.size():
		_current[index] = lerpf(float(_current[index]), float(_target[index]), blend)
	_apply(d)

func _apply(_delta: float) -> void:
	if camera == null: return
	var sway := sin(clock * TAU / 34.0) * float(_current[5])
	var yaw := deg_to_rad(float(_current[0]) + sway)
	var direction := behind.rotated(Vector3.UP, yaw)
	var breathe := sin(clock * TAU / 21.0) * 0.18
	var eye := centre + direction * (float(_current[1]) + breathe) + Vector3.UP * (float(_current[2]) + 0.06 * sin(clock * 0.9))
	var look := centre + Vector3.UP * float(_current[3])
	camera.global_position = eye
	camera.look_at(look, Vector3.UP)
	camera.rotate_object_local(Vector3.UP, deg_to_rad(float(_current[4])))
