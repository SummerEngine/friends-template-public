extends RefCounted
## Where a body that the 60 Hz physics tick moves is DRAWN. The couriers (and the camera that follows them) are moved in `_physics_process` but drawn once per rendered frame:
## on a 120 Hz screen every other frame has no tick and the courier stands still while the camera (which eases towards it in the frame's own time step) keeps gliding, and at
## 60 fps one frame in a while takes two ticks or none: the courier steps ahead of and behind the camera by a tick of its speed (the sideways smear). The cure is the
## usual fixed-step one: the position of the last two ticks is kept, and a rendered frame draws the point `Engine.get_physics_interpolation_fraction()` of the way between
## them. The camera is placed from the same point, in the same `_process`, so courier and view never disagree.
## `sample(slot, position)` once per physics tick, after the tick moved the body; `at(slot, fallback)` in `_process`; `snap(slot, position)` where a body is put somewhere (a respawn).
const SNAP_DISTANCE := 2.0 ## m: a tick that moved a body further than this was a teleport (a respawn, a new level), drawn at once; the fastest throw is 0.4 m a tick
var _previous := PackedVector3Array()
var _current := PackedVector3Array()
var _stamp := PackedInt64Array() ## the physics frame each slot was sampled in
var _known := PackedByteArray()

func _grow(slot: int) -> void:
	if slot < _current.size(): return
	_previous.resize(slot + 1)
	_current.resize(slot + 1)
	_stamp.resize(slot + 1)
	_known.resize(slot + 1)

func sample(slot: int, position: Vector3) -> void:
	_grow(slot)
	if _known[slot] == 0 or _current[slot].distance_to(position) > SNAP_DISTANCE:
		_previous[slot] = position
	else:
		_previous[slot] = _current[slot]
	_current[slot] = position
	_stamp[slot] = Engine.get_physics_frames()
	_known[slot] = 1

func snap(slot: int, position: Vector3) -> void:
	_grow(slot)
	_previous[slot] = position
	_current[slot] = position
	_stamp[slot] = Engine.get_physics_frames()
	_known[slot] = 1

## The point drawn now for `slot`: between its last two ticks. `fallback` (the body's own position) while nothing was sampled, and the last tick's point (no interpolation) while ticks stopped (a paused
## tree runs no `_physics_process`, but the fraction keeps cycling: the body would swing back and forth over the last tick).
func at(slot: int, fallback: Vector3) -> Vector3:
	if slot >= _current.size() or _known[slot] == 0: return fallback
	if Engine.get_physics_frames() > _stamp[slot] + 1: return _current[slot]
	return _previous[slot].lerp(_current[slot], clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))
