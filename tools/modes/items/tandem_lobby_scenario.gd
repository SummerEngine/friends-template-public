extends RefCounted
## EXPERIMENT TANDEM in the lobby yard, end to end (docs/party-show.md "Tandem (experiment)"): run with `--scenario=tandem_lobby` (the harness stays in the lobby: three joined players, two replicas
## drawing the TANDEM's look). Seats 0 and 1 run up and down the yard side by side, seat 2 stands in a corner.
## Checks: they fuse after 1.5 s alongside, the replicas hold the pair, the banner words, the third player is untouched; at the end both are thrown apart (the authority's kicks), the pair cools down.
## Frames (`--shots`, view 0 = seat 0): run, pop, hands, spin.
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")

var _dir := 1.0

func _yard() -> Rect2:
	var local := WalkInLobby.interior_rect()
	return Rect2(local.position + Vector2(WalkInLobby.ORIGIN.x, WalkInLobby.ORIGIN.z), local.size)

func _at(h, seat: int) -> Vector3:
	return h.sim.actors[h.controller._slot(seat)].position

## The two runners' targets this tick: ahead along x, turning round at the yard's ends, `gap` m apart in z.
func _steer(h, rect: Rect2, gap: float) -> void:
	var here: Vector3 = _at(h, 0)
	if here.x > rect.end.x - 3.0: _dir = -1.0
	elif here.x < rect.position.x + 3.0: _dir = 1.0
	var z := rect.position.y + rect.size.y * 0.3
	h.targets[0] = Vector3(here.x + _dir * 2.0, here.y, z)
	h.targets[1] = Vector3(_at(h, 1).x + _dir * 2.0, here.y, z + gap)

func run(h) -> void:
	var rect := _yard()
	var floor_y: float = _at(h, 0).y
	# the line-up: seat 0 and 1 side by side near one end, seat 2 in the far corner
	h.targets[0] = Vector3(rect.position.x + 4.0, floor_y, rect.position.y + rect.size.y * 0.3)
	h.targets[1] = Vector3(rect.position.x + 4.0, floor_y, rect.position.y + rect.size.y * 0.3 + 1.0)
	h.targets[2] = Vector3(rect.end.x - 2.0, floor_y, rect.end.y - 2.0)
	var lined: bool = await h.wait_until(func() -> bool: return _at(h, 0).distance_to(h.targets[0]) < 0.3 and _at(h, 1).distance_to(h.targets[1]) < 0.3 and _at(h, 2).distance_to(h.targets[2]) < 0.3, 60 * 40)
	h.check(lined, "three players stand where the script put them (%s)" % str([_at(h, 0), _at(h, 1), _at(h, 2)]))
	var tandem = h.controller.tandem
	h.check(tandem != null and tandem.active and tandem.scope == "lobby", "the authority runs the tandem in the lobby (scope %s)" % str(tandem.scope if tandem != null else "none"))
	await h.tick(20)
	h.check(tandem.pairs.is_empty() and tandem.warm.is_empty(), "standing side by side: nothing")
	h.shoot("run")
	var began: float = tandem.time
	var fused := false
	for tick in 60 * 8:
		_steer(h, rect, 1.0)
		await h.tick()
		if not tandem.pairs.is_empty():
			fused = true
			break
	var after: float = tandem.time - began
	h.check(fused and after >= 1.4 and after <= 3.0, "running side by side fuses them within a couple of seconds (%.2f s)" % after)
	var pair: Dictionary = tandem.pairs[0] if fused else {}
	h.check(int(pair.get("a", -9)) == 0 and int(pair.get("b", -9)) == 1, "seats 0 and 1 are the pair")
	for tick in 14:
		_steer(h, rect, 1.0)
		await h.tick()
	h.shoot("pop")
	for index in 2:
		var shell: Node = h.replicas[index]
		h.check(int((shell.tandem.get(index, {}) as Dictionary).get("with", -9)) == 1 - index and is_equal_approx(float((shell.tandem.get(index, {}) as Dictionary).get("speed", 0.0)), 1.6), "replica %d is fused with %d at 1.6 x" % [index, 1 - index])
		h.check(not shell.tandem.has(2), "replica %d: the third player is not" % index)
	h.check(h.tandems[0].banners_shown == 1 and str(h.tandems[0]._banner.get("words", "")) == "TANDEM!" and h.tandems[1].banners_shown == 1, "both screens say TANDEM!")
	var info: Dictionary = h.latest_state().get("match", {})
	h.check((info.get("tandem", {}) as Dictionary).get("scope", "") == "lobby", "match.tandem is published in the lobby")
	for tick in 24:
		_steer(h, rect, 1.0)
		await h.tick()
	h.shoot("hold")
	var before: Vector3 = h.sim.team.kicks[0]
	var ended := false
	for tick in 60 * 8:
		_steer(h, rect, 1.0)
		await h.tick()
		if tandem.pairs.is_empty():
			ended = true
			break
	h.check(ended and (tandem.events as Array).any(func(row: Array) -> bool: return int(row[1]) == Tandem.Event.END), "six seconds later they spin apart (END)")
	var kick: Vector3 = h.sim.team.kicks[0] - before
	h.check(Vector2(kick.x, kick.z).length() > 4.5 and kick.y > 2.0, "the authority threw seat 0 (kick %s)" % str(kick))
	for tick in 9: await h.tick()
	h.shoot("spin")
	for tick in 60:
		_steer(h, rect, 1.0)
		await h.tick()
	h.check(h.replicas[0].tandem.is_empty() and h.replicas[0].rig_hold.is_empty() and h.replicas[0].rig_spin.is_empty(), "the owners' machines are free again")
	h.check(tandem.cooling.has(Tandem.key_of(0, 1)), "the pair is cooling down")
