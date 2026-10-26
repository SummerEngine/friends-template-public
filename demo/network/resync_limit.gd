extends RefCounted
## Authority-side admission of client `phase_resync` requests: per admitted player a minimum interval and a
## rolling-minute cap, so a misbehaving or lossy client cannot turn keyframe bursts into a bandwidth amplifier.
## Pure policy (no engine state): authority/main.gd and the probes share it.
const MIN_INTERVAL := 2.0      # seconds between two accepted requests of one player
const MAX_PER_MINUTE := 10     # accepted requests of one player in any 60 s window

var _accepted: Dictionary = {} # seat -> Array[float] of acceptance times (authority wall seconds)
var accepted_total := 0
var refused_total := 0

## now = monotonically increasing authority seconds. Returns true when a burst should start.
func admit(seat: int, now: float) -> bool:
	var times: Array = _accepted.get(seat, [])
	while not times.is_empty() and now - float(times[0]) > 60.0: times.pop_front()
	if (not times.is_empty() and now - float(times[-1]) < MIN_INTERVAL) or times.size() >= MAX_PER_MINUTE:
		_accepted[seat] = times
		refused_total += 1
		return false
	times.append(now)
	_accepted[seat] = times
	accepted_total += 1
	return true

func forget(seat: int) -> void:
	_accepted.erase(seat)
