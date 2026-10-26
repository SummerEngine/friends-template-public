extends RefCounted
## EXPERIMENT TANDEM, the proof clip of a race (docs/party-show.md "Tandem (experiment)"): a take, not a check. Use the flat race level (`--show-level=32`, the 144 m of level 31) and the offscreen binary under the render lock:
##   lockf -k ~/.local/state/friends-slots/render.lock timeout -k 10 900 <ItemsLab offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --write-movie /tmp/tandem/race.avi --path demo -s "$PWD/tools/modes/items_harness.gd" -- --scenario=tandem_film --show-level=32 --film --cast=<cast.json>
## then the take is cut [start .. end] by the `FILM mark` lines of the log. Slots 0 and 1 run side by side along the route; the script runs them 1.6 times as fast while the authority holds them fused (the owners'
## machines would, from the replicated pair) and, when it ends, one runs on and the other falls back (the authority's kick). Slot 2 stands behind. The camera is a free shot (`view_override`) over the course's gates, behind the pair.

const BASE := 0.09 ## m per tick along the route alone (5.4 m/s)
var _way := Vector3.ZERO
var _eye := Vector3.ZERO

func _pos(h, slot: int) -> Vector3:
	return h.sim.actors[slot].position

func _route_way(h, at: Vector3) -> Vector3:
	var route: PackedVector3Array = h.sim.level_world.route(int(h.state().level))
	var best := INF
	var index := 0
	for k in route.size():
		var gap := Vector2(route[k].x - at.x, route[k].z - at.z).length()
		if gap < best:
			best = gap
			index = k
	var way := route[mini(index + 3, route.size() - 1)] - route[maxi(index - 1, 0)]
	way.y = 0.0
	return way.normalized()

func _camera(h) -> void:
	var middle := (_pos(h, 0) + _pos(h, 1)) * 0.5
	var way := _route_way(h, middle)
	_way = way if _way == Vector3.ZERO else _way.lerp(way, 0.1).normalized()
	var wanted := middle - _way * 4.4 + Vector3.UP * 5.0 # over the gates, behind the pair
	_eye = wanted if _eye == Vector3.ZERO else _eye.lerp(wanted, 0.15)
	h.replicas[0].view_override = Transform3D(Basis.IDENTITY, _eye).looking_at(middle + Vector3.UP * 0.9 + _way * 1.0, Vector3.UP)

func run(h) -> void:
	for slot in 3: h.hold(slot)
	h.rules().items._next_event_at = 1.0e9
	await h.tick(10)
	h.progress(0, 6.0)
	h.progress(1, 6.0)
	h.progress(2, 1.0)
	await h.tick(40)
	h.focus()
	_camera(h)
	await h.tick(30)
	var tandem = h.controller.tandem
	h.check(tandem != null and tandem.active and tandem.scope == "race", "the tandem runs in the race (level %s)" % str(h.state().level))
	h.mark("start")
	h.speed[0] = BASE
	h.speed[1] = BASE
	h.speed[2] = 0.0
	h.release(0)
	h.release(1)
	var fused := false
	var ended := false
	var after := 0
	for tick in 60 * 14:
		var together: bool = not tandem.pairs.is_empty()
		if after == 0:
			h.speed[0] = BASE * (1.6 if together else 1.0)
			h.speed[1] = h.speed[0]
		_camera(h)
		await h.tick()
		if together: fused = true
		if fused and tandem.pairs.is_empty() and not ended:
			ended = true
			h.speed[0] = 0.3 # thrown apart: one on ahead, the other back
			h.speed[1] = 0.02
		if ended:
			after += 1
			if after == 18:
				h.speed[0] = BASE
				h.speed[1] = BASE
			if after > 60 * 2.2: break
	h.mark("end")
	h.check(fused and ended, "the pair fused and came apart on the take")
	await h.tick(10)
