extends RefCounted
## GHOST PIGEON end to end (docs/pigeon.md), through the items harness (tools/modes/items_harness.gd: the authority, its match controller and three scripted players, and two replica clients that draw the show's
## real view), on the race (level 31) and then on a tile stage round (level 25): `--scenario=pigeon --show-level=31 --show-level=25`.
##  The race: slot 0 crosses the goal and is a pigeon 1.2 s later (its courier retired, a bird in the state, both replicas draw it, its own replica follows it and shows the banner), it flies on its player's input
##  (WASD world direction and JUMP / DASH held, as the wire carries them) inside the arena's bounds and ceiling, a COO plays for everybody, shakes the screen of the living player within 5 m and not the one further
##  away, goes on cooldown; a DROP falls and splats on the living player under it (overlay on that replica's screen, a white blob on its head for the others), nobody is pushed or hurt, the drop's cooldown holds, a
##  second bird cannot put a second splat on a player who wears one, a bird nobody flies wanders and coos.
##  The tile round: slot 0 lands on the ground floor and is out, a bird flies over the top floor from the spot where it fell, its drop splats on a player standing on the tiles.
var h

func row(slot: int) -> Array:
	var state: Dictionary = h.state()
	for entry: Array in (state.get("pigeon", {}) as Dictionary).get("b", []):
		if int(entry[0]) == slot: return entry
	return []

func steer(slot: int, move: Vector2, climb: float) -> void:
	for seat in 3:
		if h.controller._slot(seat) != slot: continue
		var command: Dictionary = h.controller.commands[seat]
		command["move"] = [move.x, move.y]
		command["height"] = climb
		command["seq"] = int(command.seq) + 1
		h.controller.commands[seat] = command

func bird(slot: int) -> Dictionary:
	return h.rules().pigeons.birds.get(slot, {})

func run(harness) -> void:
	h = harness
	for slot in 3: h.hold(slot)
	await h.tick(20)
	await h.wait_until(func() -> bool: return float(h.state().get("t", 0.0)) > 1.4, 60 * 4)
	var rules = h.rules()
	var level: int = int(h.state().level)
	h.check(rules.pigeons.enabled, "the experiment is on in the race (pigeon.json: on, rounds.race)")
	h.check(h.state().has("pigeon") and (h.state().pigeon.b as Array).is_empty(), "the state carries `pigeon` with no birds while everybody runs")
	var length: float = h.sim.level_world.route_length(level)
	h.progress(1, length - 8.0) # the living player stands 8 m before the goal
	await h.tick(20)
	h.progress(0, 99999.0) # slot 0 crosses the goal
	await h.wait_until(func() -> bool: return int(h.state().status[0]) == 1, 60 * 5)
	h.check(int(h.state().status[0]) == 1, "slot 0 qualified (status 1)")
	rules._deadline = 1.0e9 # the scenario takes longer than the 30 s window a points race gives the others
	rules.manager._next_at = 1.0e9 # the manager, the eggplant and the clock would hold the event gate a DROP asks (shared/event_gate.gd): the gate has its own check
	rules.items._next_event_at = 1.0e9
	if rules.items.rules_of.has("eggplant"): rules.items.rules_of["eggplant"]._next_at = 1.0e9
	h.check(h.sim.is_slot_active(0) and h.replicas[0].is_slot_active(0), "its courier is still on the course right after the finish")
	await h.wait_until(func() -> bool: return not row(0).is_empty(), 60 * 3)
	h.check(not row(0).is_empty() and not h.sim.is_slot_active(0), "1.2 s after the finish the courier is retired and slot 0 is a pigeon in the state")
	await h.tick(12)
	h.check(not h.replicas[0].is_slot_active(0) and not h.replicas[1].is_slot_active(0), "both replicas know the courier is gone")
	h.check(h.views[0]._pigeons.birds_shown() == [0] and h.views[1]._pigeons.birds_shown() == [0], "both replicas see the pigeon (%s, %s)" % [str(h.views[0]._pigeons.birds_shown()), str(h.views[1]._pigeons.birds_shown())])
	h.check(h.views[0]._pigeons.mine() and h.replicas[0].pigeon_focus is Vector3, "the pigeon's own replica follows the bird (pigeon_focus) and does not spectate (spectate_slot %d)" % int(h.replicas[0].spectate_slot))
	h.check(h.replicas[0].spectate_slot == -1 and h.replicas[1].pigeon_focus == null, "the other replica is not a bird")
	h.check(str(h.views[0]._banner) == "YOU ARE A PIGEON", "the new pigeon reads the banner (%s)" % str(h.views[0]._banner))
	h.check(str(h.views[0].hud(h.state()).note).contains("coo"), "its note names the keys (%s)" % str(h.views[0].hud(h.state()).note))
	var box: Dictionary = rules.pigeons.box
	h.check(not bool(box.stage) and float(bird(0).pos.y) > float(box.lo.y), "the race's flight box is the route and its ceiling (ceiling %.1f m)" % float(box.hi.y))
	h.shoot("pigeon_start")

	# flight: WASD (the world direction) and JUMP held
	var start: Vector3 = bird(0).pos
	steer(0, Vector2(1.0, 0.0), 1.0)
	await h.tick(60)
	var moved: Vector3 = bird(0).pos - start
	h.check(moved.x > 3.0 and moved.y > 2.0 and absf(moved.z) < 0.5, "the bird flies on its player's input: right and up (%.1f, %.1f, %.1f m in 1 s)" % [moved.x, moved.y, moved.z])
	var shown: Vector3 = h.views[1]._pigeons.bird_position(0)
	h.check(shown.distance_to(bird(0).pos) < 2.5, "the other replica draws the bird where the authority has it (%.2f m apart)" % shown.distance_to(bird(0).pos))
	h.shoot("pigeon_fly")
	await h.tick(300) # 5 s more: the bounds and the ceiling hold it
	var bound: Vector3 = bird(0).pos
	h.check(bound.y <= float(box.hi.y) + 0.001 and bound.x <= float(box.hi.x) + 0.001, "a ceiling and the bounds keep it in the arena (y %.2f of %.2f, x %.2f of %.2f)" % [bound.y, float(box.hi.y), bound.x, float(box.hi.x)])
	h.check(bound.y > float(box.hi.y) - 0.5 and bound.x > float(box.hi.x) - 0.5, "it reached them")
	steer(0, Vector2(-1.0, 0.0), -1.0) # and down: DASH held
	await h.tick(420)
	var low: Vector3 = bird(0).pos
	h.check(low.y >= float(box.lo.y) - 0.001 and low.y < bound.y - 5.0, "DASH held takes it down, never under the floor (y %.2f)" % low.y)
	steer(0, Vector2.ZERO, 0.0)

	# the second bird
	h.progress(2, 99999.0)
	await h.wait_until(func() -> bool: return not row(2).is_empty(), 60 * 5)
	h.check(not row(2).is_empty(), "slot 2 finishes too and is a pigeon")

	# COO: first from far away, then from within 5 m
	var living: Vector3 = h.sim.actors[1].position
	bird(0).pos = living + Vector3(9.0, 3.0, 0.0)
	bird(0).vel = Vector3.ZERO
	await h.tick(30)
	var before_far: int = int(h.views[1]._pigeons.coos_heard)
	h.press_grab(0)
	await h.tick(6)
	h.check(int(row(0)[8]) == 1 and int(row(0)[13]) == 0, "COO #1 from 9 m: counted, nobody in range (hits %d)" % int(row(0)[13]))
	h.check(int(h.views[1]._pigeons.coos_heard) == before_far + 1 and int(h.views[0]._pigeons.coos_heard) >= 1, "every replica plays the coo")
	h.check(h.views[1]._pigeons.shakes == 0, "no screen shake at 9 m")
	h.press_grab(0)
	await h.tick(6)
	h.check(int(row(0)[8]) == 1 and float(row(0)[10]) > 2.0, "a second press during the cooldown is ignored (cooldown %.1f s)" % float(row(0)[10]))
	bird(0).pos = living + Vector3(2.0, 2.0, 0.0)
	await h.tick(190)
	h.check(float(row(0)[10]) == 0.0, "the cooldown is over after 3 s")
	h.press_grab(0)
	await h.tick(6)
	h.check(int(row(0)[8]) == 2 and (int(row(0)[13]) & 2) != 0 and (int(row(0)[13]) & 1) == 0, "COO #2 at 2.8 m reaches the living player (slot 1) and nobody else (hits %d)" % int(row(0)[13]))
	h.check(h.views[1]._pigeons.shakes == 1 and h.views[0]._pigeons.shakes == 0, "its screen shakes (%d), the pigeon's does not (%d)" % [h.views[1]._pigeons.shakes, h.views[0]._pigeons.shakes])
	h.check(h.sim.actors[1].position.distance_to(living) < 0.05 and int(h.state().status[1]) == 0, "the coo pushed and hurt nobody")
	h.shoot("pigeon_coo")

	# DROP: above the living player; a second bird adds no second splat
	bird(0).pos = living + Vector3(0.0, 4.0, 0.0)
	bird(0).vel = Vector3.ZERO
	bird(2).pos = living + Vector3(0.0, 5.0, 0.2)
	bird(2).vel = Vector3.ZERO
	steer(2, Vector2.ZERO, 0.0)
	await h.tick(30)
	var shots_before: int = int(h.views[0]._pigeons.splats_heard)
	h.press_item(0)
	await h.tick(2)
	h.check(not rules.pigeons.blobs.is_empty() and (h.state().pigeon.d as Array).size() == 1, "a drop is falling (state.pigeon.d)")
	h.check(float(row(0)[11]) > 5.0, "the drop is on its 6 s cooldown (%.1f s)" % float(row(0)[11]))
	await h.tick(14)
	h.shoot("pigeon_drop")
	await h.wait_until(func() -> bool: return not (h.state().pigeon.s as Array).is_empty(), 60 * 2)
	var splat_rows: Array = h.state().pigeon.s
	h.check(splat_rows.size() == 1 and int(splat_rows[0][0]) == 1 and int(splat_rows[0][2]) == 0, "the drop splatted on the living player under it, from slot 0 (%s)" % str(splat_rows))
	await h.tick(6)
	h.check(h.views[1]._pigeons.splat_up() and not (h.views[1]._pigeons._splat.model as Dictionary).is_empty(), "the splat is on that replica's screen")
	h.check(not h.views[0]._pigeons.splat_up(), "and not on the pigeon's")
	h.check(h.views[0]._pigeons._worn.has(1) or h.views[0]._pigeons.splats_heard > shots_before, "the others see it land (a white blob on the head)")
	var landing_told: bool = not (h.state().pigeon.l as Array).is_empty() # the landing is in the state for 1.5 s: read it while the splat is up
	h.shoot("pigeon_splat")
	var left_first := float(splat_rows[0][1])
	h.press_item(2) # the second bird drops on the same player, who wears a splat: the event gate lets no second drop go while a splat is on a screen (one interrupting event at a time)
	await h.tick(2)
	h.check(rules.pigeons.blobs.is_empty() and rules.gate.running == "splat", "the second bird's drop is not let go: the gate holds the one splat (%s)" % rules.gate.running)
	await h.tick(28)
	var wearing: Array = h.state().pigeon.s
	h.check(wearing.size() == 1 and float(wearing[0][1]) < left_first, "a player who wears a splat gets no second one: still one, still running down (%.2f -> %.2f s)" % [left_first, float(wearing[0][1]) if not wearing.is_empty() else -1.0])
	h.check(h.sim.actors[1].position.distance_to(living) < 0.05 and int(h.state().status[1]) == 0, "the drop pushed and hurt nobody")
	await h.tick(80)
	h.check((h.state().pigeon.s as Array).is_empty() and not h.views[1]._pigeons.splat_up(), "the splat is gone after 1.5 s (state and screen)")
	h.check(rules.gate.running == "" and not rules.gate.open() and float(row(0)[11]) > 5.0, "the gate is free again but closed for 15 s: the DROP pill's bar waits for it (%.1f s)" % float(row(0)[11]))
	h.check(landing_told and int(h.views[0]._pigeons.splats_heard) > shots_before, "the landings were told to the clients once each")

	# nobody flies bird 2 (and bird 0 now): they wander and coo
	await h.tick(60 * 6)
	h.check(int(row(2)[12]) == 1 and int(row(0)[12]) == 1, "a bird nobody flies wanders (auto)")
	var wander_from: Vector3 = bird(2).pos
	var coos: int = int(row(2)[8]) + int(row(0)[8])
	await h.tick(180)
	h.check(bird(2).pos.distance_to(wander_from) > 4.0, "and it moves (%.1f m in 3 s)" % bird(2).pos.distance_to(wander_from))
	await h.wait_until(func() -> bool: return int(row(2)[8]) + int(row(0)[8]) > coos, 60 * 14)
	h.check(int(row(2)[8]) + int(row(0)[8]) > coos, "a wandering bird coos now and then")

	# the tile round
	h.progress(1, 99999.0)
	await h.wait_until(func() -> bool: return str(h.state().phase) == "done", 60 * 6)
	await h.wait_until(func() -> bool: return str(h.state().phase) == "card" and str(h.state().kind) == "survival", 60 * 12)
	h.check(str(h.state().kind) == "survival" and bool(h.state().stage), "round 2 is a tile stage round (level %d)" % (int(h.state().level) + 1))
	h.check(rules.pigeons.enabled and (h.state().pigeon.b as Array).is_empty(), "the experiment is on in it, with no pigeon yet (a 3-player show is a points show: nobody is out of the show)")
	await h.wait_until(func() -> bool: return str(h.state().phase) == "play", 60 * 8)
	await h.tick(20)
	var tile_level: int = int(h.state().level)
	var ground: float = float(rules._ground_y)
	var top: float = float(h.sim.level_world.tile_floors(tile_level)[0])
	var from: Vector3 = h.sim.actors[0].position
	var seat0 := 0
	h.warp[seat0] = Vector3(from.x, ground + 0.1, from.z)
	await h.wait_until(func() -> bool: return int(h.state().status[0]) == 2, 60 * 4)
	h.check(int(h.state().status[0]) == 2, "slot 0 landed on the ground floor: out (status 2)")
	await h.wait_until(func() -> bool: return not row(0).is_empty(), 60 * 4)
	var tile_bird: Array = row(0)
	h.check(not tile_bird.is_empty() and not h.sim.is_slot_active(0), "its courier is retired 1.2 s later and it is a pigeon")
	var arena: Dictionary = rules.pigeons.box
	h.check(bool(arena.stage) and float(tile_bird[2]) >= top and float(tile_bird[2]) <= float(arena.hi.y), "it flies over the arena's top floor, not down on the ground (y %.1f, top floor %.1f, ceiling %.1f)" % [float(tile_bird[2]), top, float(arena.hi.y)])
	var inside := Vector2(float(tile_bird[1]), float(tile_bird[3]))
	h.check(inside.x >= float(arena.lo.x) + 11.9 and inside.x <= float(arena.hi.x) - 11.9 and inside.y >= float(arena.lo.z) + 11.9 and inside.y <= float(arena.hi.z) - 11.9
		and Vector2(from.x, from.z).distance_to(inside) < 14.0 * 1.5, "over the spot it fell from, kept 12 m off the walls (%.1f, %.1f)" % [inside.x, inside.y])
	await h.tick(12)
	h.check(h.views[0]._pigeons.mine() and h.replicas[0].pigeon_focus is Vector3 and h.views[1]._pigeons.birds_shown() == [0], "its replica follows it, the other draws it")
	h.shoot("pigeon_tiles")
	var target: Vector3 = h.sim.actors[1].position
	bird(0).pos = target + Vector3(0.0, 4.0, 0.0)
	bird(0).vel = Vector3.ZERO
	bird(0).coo_cd = 0.0
	bird(0).drop_cd = 0.0
	rules.gate.reset() # the first splat closed the event gate for 15 s (the DROP bar waits for it)
	await h.tick(30)
	h.press_item(0)
	await h.wait_until(func() -> bool: return not (h.state().pigeon.s as Array).is_empty(), 60 * 2)
	h.check(not (h.state().pigeon.s as Array).is_empty() and int(h.state().pigeon.s[0][0]) == 1, "its drop splats on the player standing on the tiles (%s)" % str(h.state().pigeon.s))
	await h.tick(8)
	h.check(h.views[1]._pigeons.splat_up(), "on that player's screen")
	h.shoot("pigeon_tiles_splat")
	h.check(h.sim.actors[1].position.distance_to(target) < 0.05 and int(h.state().status[1]) == 0, "nobody pushed, nobody hurt")
	h.press_grab(0)
	await h.tick(6)
	h.check(int(row(0)[8]) == 1 and (int(row(0)[13]) & 2) != 0, "its coo reaches the player below (hits %d)" % int(row(0)[13]))
