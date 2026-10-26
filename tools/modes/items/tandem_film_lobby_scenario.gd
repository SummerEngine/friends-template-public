extends RefCounted
## EXPERIMENT TANDEM, the proof clip of the lobby yard (docs/party-show.md "Tandem (experiment)"): a take, not a check. Run with the offscreen binary under the render lock, one render at a time:
##   lockf -k ~/.local/state/friends-slots/render.lock timeout -k 10 900 <ItemsLab offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --write-movie /tmp/tandem/lobby.avi --path demo -s "$PWD/tools/modes/items_harness.gd" -- --scenario=tandem_film_lobby --film --cast=<cast.json>
## then the take is cut [start .. end] by the `FILM mark` lines of the log (ffmpeg, H.264; the precedent is the power-ups' video/tools/post.py). Two scripted players run side by side in a ring round the yard (the harness has no owner couriers: the script
## runs them 1.6 times as fast while the pair is fused and throws them apart when it ends, as the owners' machines would do from the replicated pair and the authority's kick); a third stands by.
## The camera is a free shot (`view_override`) ahead of the pair, looking back at them: hands, hearts, the banner of the first player's screen.
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")

const RING := 6.0 ## m: the ring the pair runs on
const WIDTH := 1.0 ## m between the two runners (radially)
const BASE := 0.085 ## m per tick alone
var _angle := 0.0
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _fling := 0.0

func _centre() -> Vector3:
	var local := WalkInLobby.interior_rect()
	return WalkInLobby.ORIGIN + Vector3(local.get_center().x, 0.0, local.get_center().y)

func _slot_of(h, seat: int) -> int:
	return h.controller._slot(seat)

func _pos(h, seat: int) -> Vector3:
	return h.sim.actors[_slot_of(h, seat)].position

## Where seat `seat` goes next on the ring (a little ahead of where it is), and the pace that keeps the two abreast.
func _steer(h, centre: Vector3, pace: float) -> void:
	var radii := [RING + WIDTH * 0.5, RING - WIDTH * 0.5]
	for seat in 2:
		var here := _pos(h, seat)
		var angle := atan2(here.z - centre.z, here.x - centre.x)
		var ahead := angle + 0.22
		h.targets[seat] = Vector3(centre.x + cos(ahead) * float(radii[seat]), here.y, centre.z + sin(ahead) * float(radii[seat]))
		h.lobby_speed[seat] = pace * float(radii[seat]) / RING

func _camera(h, centre: Vector3) -> void:
	var middle := (_pos(h, 0) + _pos(h, 1)) * 0.5
	var radial := Vector3(middle.x - centre.x, 0.0, middle.z - centre.z).normalized()
	var heading := Vector3(-radial.z, 0.0, radial.x) # counter-clockwise
	var wanted := middle + heading * 4.4 - radial * 2.2 + Vector3.UP * 1.9
	var aim := middle + Vector3.UP * 2.3 # the pair stands in the lower third: the banner sits above it
	_eye = wanted if _eye == Vector3.ZERO else _eye.lerp(wanted, 0.12)
	_look = aim if _look == Vector3.ZERO else _look.lerp(aim, 0.2)
	h.replicas[0].view_override = Transform3D(Basis.IDENTITY, _eye).looking_at(_look, Vector3.UP)

func run(h) -> void:
	var centre := _centre()
	var floor_y: float = _pos(h, 0).y
	h.targets[0] = Vector3(centre.x + RING + WIDTH * 0.5, floor_y, centre.z)
	h.targets[1] = Vector3(centre.x + RING - WIDTH * 0.5, floor_y, centre.z)
	h.targets[2] = Vector3(centre.x - RING - 2.0, floor_y, centre.z + 3.0)
	var lined: bool = await h.wait_until(func() -> bool: return _pos(h, 0).distance_to(h.targets[0]) < 0.3 and _pos(h, 1).distance_to(h.targets[1]) < 0.3 and _pos(h, 2).distance_to(h.targets[2]) < 0.3, 60 * 40)
	h.check(lined, "the three stand on their marks")
	await h.tick(30)
	h.focus()
	_camera(h, centre)
	await h.tick(20)
	h.mark("start")
	var tandem = h.controller.tandem
	var fused := false
	var ended := false
	var after := 0
	for tick in 60 * 14:
		var pace := BASE * (1.6 if not tandem.pairs.is_empty() else 1.0)
		_steer(h, centre, pace)
		if _fling > 0.0: # the owners' machines throw them: the kick the authority sent
			_fling -= 1.0 / 60.0
			for seat in 2:
				var here := _pos(h, seat)
				var out := (here - centre).normalized() * (1.0 if seat == 0 else -1.0)
				h.targets[seat] = here + out * 4.0
				h.lobby_speed[seat] = 0.16
		_camera(h, centre)
		await h.tick()
		if not tandem.pairs.is_empty(): fused = true
		if fused and tandem.pairs.is_empty() and not ended:
			ended = true
			_fling = 0.45
		if ended:
			after += 1
			if after > 60 * 2.2: break
	h.mark("end")
	h.check(fused and ended, "the pair fused and came apart on the take")
	await h.tick(10)
