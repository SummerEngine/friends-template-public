extends RefCounted
## GHOST PIGEON (EXPERIMENT, switchable, docs/pigeon.md). A player who is out of a tile round (landed on the ground floor), or through a race (crossed the goal), or who went out in an
## earlier round, is a PIGEON: a small bird that flies over the arena and annoys the living players with two things, both only a look on the living player's screen:
##   COO   a loud coo and a small screen-shake ping for every living player within `coo_range` m (cooldown `coo_cooldown`).
##   DROP  a white blob falls from the bird; where it meets a living player it splats on that player's screen for `splat_time` s, half covering the view (cooldown `drop_cooldown`; a player who
##         wears a splat, or wore one `victim_rest` s ago, cannot be splatted: one at a time, never a pile-up).
## A pigeon never pushes, grabs, blocks or kills anybody and nothing it does changes the round's rules: it is a look and a sound. The authority decides everything (where each bird is, who hears the
## coo, where the blob lands, who wears the splat); the clients only draw (modes/show/pigeon/pigeon_view.gd). Owned by modes/show/rules.gd (`pigeons`), shared by the authority and the local game.
## Controls come from the owner's input: move = the world direction of the stick (the camera's), climb = JUMP held minus DASH held (`height` on the wire), COO = the GRAB button, DROP = the ITEM
## button (their press counters, `host.presses`). A bird whose player does not touch anything for `wander_after` s (a bot, an idle player) wanders and coos now and then, until it is touched.
const Catalog := preload("res://modes/show/shared/pigeon/pigeon_catalog.gd")
const Sim := preload("res://modes/show/shared/pigeon/pigeon_sim.gd")
const EventGate := preload("res://modes/show/shared/event_gate.gd")
const GATE := "splat" ## the kind a DROP asks the event gate under

const GRAVITY := 16.0 ## m/s^2 of the falling blob
const HIT_RADIUS := 0.8 ## m (x/z) a blob counts as on a living player
const HIT_BELOW := 0.2 ## m under the feet ...
const HIT_ABOVE := 2.2 ## ... and over them: the blob is on the player
const EVENT_KEEP := 1.5 ## s a landing stays in the state (the clients tell it once, by its number)
const START_COOLDOWN := 1.0 ## s before a new pigeon may coo or drop
const CAP_BIRDS := 10

var host
var gate: EventGate ## the show's event gate (rules.gd): a DROP is let go only when it grants a splat (one interrupting event at a time, 15 s apart); null: ungated (a check's own rules)
var enabled := false ## the experiment is on in this round (pigeon.json, the cast, the round's kind)
var birds: Dictionary = {} ## slot -> {pos, vel, yaw, coo_n, drop_n, coo_cd, drop_cd, hits, idle, auto, seen_coo, seen_drop, goal, next_goal, next_coo, floor, born}
var blobs: Array = [] ## the falling drops: {id, pos, vel, from}
var splats: Dictionary = {} ## victim slot -> {left, from}: the splats on living players' screens now
var landed: Array = [] ## the blobs that landed: {seq, pos, victim (slot, -1 none), age}
var box: Dictionary = {}
var level := -1
var capable := false ## the host can run pigeons (a real host: positions, inputs, presses, the level world)
var _rest: Dictionary = {} ## victim slot -> s until it may be splatted again
var _rng := RandomNumberGenerator.new()
var _seq := 0
var _frame := 0
var _armed := false
var _gated := false ## the gate has granted the splat of the drop in the air (or on a screen); given back when the last blob has landed and no splat is left

func setup(round_host) -> void:
	host = round_host
	capable = host != null and host.has_method("pigeon_input") and host.has_method("levels") and host.has_method("presses") and host.has_method("floor_at")
	_rng.seed = 24102026

## A round begins on `level` (kind "race" | "survival" | "final"): every bird is gone, and the players who are out of the show (`watchers`) are pigeons over the start.
func begin_round(kind: String, round_level: int, watchers: Array) -> void:
	clear()
	enabled = capable and round_level >= 0 and Catalog.on(kind) and host.get("simulation") != null and host.levels() != null # (a check's fake host has no simulation, no level world)
	level = round_level
	if not enabled: return
	box = Sim.bounds(host.levels(), level)
	var start: Dictionary = host.levels().start_pose(level)
	var from_a: Vector3 = start.get("a", Vector3.ZERO)
	var from_b: Vector3 = start.get("b", Vector3.ZERO)
	var base: Vector3 = (from_a + from_b) * 0.5
	if bool(box.stage): base = Vector3((box.lo.x + box.hi.x) * 0.5, float(box.top), (box.lo.z + box.hi.z) * 0.5)
	for index in watchers.size():
		var angle := TAU * float(index) / float(maxi(watchers.size(), 1))
		spawn(int(watchers[index]), base + Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0))

## Everything is put away (a new round, the podium, the experiment off).
func clear() -> void:
	birds.clear()
	blobs.clear()
	splats.clear()
	landed.clear()
	_rest.clear()
	_give_back()
	enabled = false

## A player is a pigeon from now on; `at` is where its courier stood (the feet).
func spawn(slot: int, at: Vector3) -> void:
	if not enabled or birds.has(slot) or birds.size() >= CAP_BIRDS: return
	var start := Sim.start_point(box, at)
	birds[slot] = {"pos": start, "vel": Vector3.ZERO, "yaw": 0.0, "coo_n": 0, "drop_n": 0, "coo_cd": START_COOLDOWN, "drop_cd": START_COOLDOWN, "hits": 0, "idle": 0.0, "auto": false,
		"seen_coo": host.presses(slot, "grab"), "seen_drop": host.presses(slot, "item"), "goal": start, "next_goal": 0.0, "next_coo": _rng.randf_range(2.0, 6.0), "floor": NAN, "born": 0.0}

func has(slot: int) -> bool:
	return birds.has(slot)

## A player left the game.
func drop(slot: int) -> void:
	birds.erase(slot)
	splats.erase(slot)

## `armed`: coos and drops count (the round is on); false during a card (the birds fly but keep quiet).
func tick(dt: float, armed: bool) -> void:
	if not enabled: return
	_armed = armed
	_frame += 1
	for slot: int in birds.keys(): _tick_bird(slot, dt)
	_tick_blobs(dt)
	for victim: int in splats.keys():
		splats[victim].left = float(splats[victim].left) - dt
		if float(splats[victim].left) <= 0.0: splats.erase(victim)
	for victim: int in _rest.keys():
		_rest[victim] = float(_rest[victim]) - dt
		if float(_rest[victim]) <= 0.0: _rest.erase(victim)
	if _gated and blobs.is_empty() and splats.is_empty(): _give_back()
	for event: Dictionary in landed: event.age = float(event.age) + dt
	landed = landed.filter(func(event: Dictionary) -> bool: return float(event.age) < EVENT_KEEP)

func _tick_bird(slot: int, dt: float) -> void:
	var bird: Dictionary = birds[slot]
	bird.born = float(bird.born) + dt
	var input: Dictionary = host.pigeon_input(slot)
	var dir: Vector2 = input.get("move", Vector2.ZERO)
	var climb := float(input.get("climb", 0.0))
	var coos: int = host.presses(slot, "grab")
	var drops: int = host.presses(slot, "item")
	var coo_pressed := coos > int(bird.seen_coo)
	var drop_pressed := drops > int(bird.seen_drop)
	bird.seen_coo = coos
	bird.seen_drop = drops
	if dir.length() > 0.1 or absf(climb) > 0.1 or coo_pressed or drop_pressed:
		bird.idle = 0.0
		bird.auto = false
	else:
		bird.idle = float(bird.idle) + dt
		if float(bird.idle) >= Catalog.tune("wander_after"): bird.auto = true
	if bool(bird.auto): # nobody is flying it: wander, and coo now and then
		var here: Vector3 = bird.pos
		if float(bird.born) >= float(bird.next_goal) or here.distance_to(bird.goal) < 1.5:
			bird.goal = _wander_goal(here)
			bird.next_goal = float(bird.born) + _rng.randf_range(4.0, 8.0)
		var to_goal: Vector3 = (bird.goal as Vector3) - here
		dir = Vector2(to_goal.x, to_goal.z).limit_length(1.0) * 0.6
		climb = clampf(to_goal.y * 0.4, -0.6, 0.6)
		if float(bird.born) >= float(bird.next_coo):
			bird.next_coo = float(bird.born) + _rng.randf_range(5.0, 10.0)
			coo_pressed = true
	if (_frame + slot) % 3 == 0: bird.floor = host.floor_at(level, bird.pos) if not bool(box.stage) else NAN
	var moved := Sim.step(bird.pos, bird.vel, dir, climb, dt, box, float(bird.floor), Catalog.tune("speed"), Catalog.tune("climb"))
	bird.pos = moved.pos
	bird.vel = moved.vel
	bird.yaw = Sim.facing(bird.vel, float(bird.yaw))
	bird.coo_cd = maxf(float(bird.coo_cd) - dt, 0.0)
	bird.drop_cd = maxf(float(bird.drop_cd) - dt, 0.0)
	if not _armed: return
	if gate != null and not _gated: bird.drop_cd = maxf(float(bird.drop_cd), gate.wait_left()) # the DROP pill's bar shows the wait for the gate
	if coo_pressed and float(bird.coo_cd) <= 0.0: _coo(slot, bird)
	if drop_pressed and float(bird.drop_cd) <= 0.0: _try_drop(slot, bird)

func _wander_goal(here: Vector3) -> Vector3:
	var lo: Vector3 = box.lo
	var hi: Vector3 = box.hi
	var y_low := minf(lo.y + 3.0, hi.y)
	var y_high := maxf(minf(hi.y - 1.0, here.y + 4.0), y_low)
	return Vector3(clampf(here.x + _rng.randf_range(-14.0, 14.0), lo.x, hi.x), clampf(here.y + _rng.randf_range(-3.0, 3.0), y_low, y_high), clampf(here.z + _rng.randf_range(-14.0, 14.0), lo.z, hi.z))

## The living players: in the round, not pigeons.
func _living(slot: int) -> bool:
	return slot >= 0 and host.active(slot) and not birds.has(slot)

func _coo(slot: int, bird: Dictionary) -> void:
	bird.coo_n = int(bird.coo_n) + 1
	bird.coo_cd = Catalog.tune("coo_cooldown")
	var range_m := Catalog.tune("coo_range")
	var mask := 0
	for victim in host.count:
		if victim == slot or not _living(victim): continue
		if (host.position(victim) + Vector3.UP).distance_to(bird.pos) <= range_m: mask |= 1 << victim
	bird.hits = mask

## A DROP is let go when the show's event gate grants it (never queued: a pigeon that cannot drop now simply waits, its bar says so).
func _try_drop(slot: int, bird: Dictionary) -> void:
	if gate != null:
		if _gated or gate.request(GATE, Catalog.tune("splat_time") + 3.0, false) != EventGate.Verdict.GRANTED: return
		_gated = true
	_drop(slot, bird)

func _give_back() -> void:
	if gate != null and _gated: gate.end(GATE)
	_gated = false

func _drop(slot: int, bird: Dictionary) -> void:
	bird.drop_n = int(bird.drop_n) + 1
	bird.drop_cd = Catalog.tune("drop_cooldown")
	_seq += 1
	blobs.append({"id": _seq, "pos": (bird.pos as Vector3) + Vector3(0.0, -0.3, 0.0), "vel": Vector3((bird.vel as Vector3).x * 0.7, -1.0, (bird.vel as Vector3).z * 0.7), "from": slot})

func _tick_blobs(dt: float) -> void:
	for index in range(blobs.size() - 1, -1, -1):
		var blob: Dictionary = blobs[index]
		var before: Vector3 = blob.pos
		blob.vel = (blob.vel as Vector3) + Vector3(0.0, -GRAVITY * dt, 0.0)
		blob.pos = before + (blob.vel as Vector3) * dt
		var now: Vector3 = blob.pos
		var victim := _under(before, now, int(blob.from))
		if victim >= 0:
			splats[victim] = {"left": Catalog.tune("splat_time"), "from": int(blob.from)}
			_rest[victim] = Catalog.tune("splat_time") + Catalog.tune("victim_rest")
			_land(now, victim)
			blobs.remove_at(index)
			continue
		var surface := _surface(before, now)
		if not is_nan(surface):
			_land(Vector3(now.x, surface, now.z), -1)
			blobs.remove_at(index)
		elif now.y < float(box.ground) - 5.0:
			blobs.remove_at(index)

func _land(at: Vector3, victim: int) -> void:
	_seq += 1
	landed.append({"seq": _seq, "pos": at, "victim": victim, "age": 0.0})

## The living player (that may be splatted now) whose body the blob went through between `before` and `now`, -1 for none.
func _under(before: Vector3, now: Vector3, from: int) -> int:
	for victim in host.count:
		if victim == from or not _living(victim) or splats.has(victim) or _rest.has(victim): continue
		var feet: Vector3 = host.position(victim)
		if Vector2(now.x - feet.x, now.z - feet.z).length() > HIT_RADIUS: continue
		if maxf(before.y, now.y) >= feet.y - HIT_BELOW and minf(before.y, now.y) <= feet.y + HIT_ABOVE: return victim
	return -1

## The height of the first floor the blob crossed between `before` and `now`, NAN for none: the tile floors of a stage round (where a tile is standing), the level's blocks, the arena's ground.
func _surface(before: Vector3, now: Vector3) -> float:
	var levels = host.levels()
	if bool(box.stage):
		for top: float in levels.tile_floors(level):
			if before.y > top and now.y <= top and not (levels.tiles_under(level, Vector3(now.x, top, now.z)) as Array).is_empty(): return top
		return float(box.ground) if now.y <= float(box.ground) else NAN
	var floor_y: float = host.floor_at(level, Vector3(now.x, before.y, now.z))
	if not is_nan(floor_y) and now.y <= floor_y: return floor_y
	return float(box.ground) if now.y <= float(box.ground) else NAN

## What goes into the show's state as `pigeon` ({} when the experiment is off in this round): the birds as rows
## [slot, x, y, z, yaw, vx, vy, vz, coo_n, drop_n, coo_cd, drop_cd, auto, hits], the falling blobs [id, x, y, z, vx, vy, vz, from], the splats on screens [victim, left, from], the landings [seq, x, y, z, victim].
func state() -> Dictionary:
	if not enabled: return {}
	var rows := []
	for slot: int in birds:
		var b: Dictionary = birds[slot]
		var p: Vector3 = b.pos
		var v: Vector3 = b.vel
		rows.append([slot, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(float(b.yaw), 0.01), snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1),
			int(b.coo_n), int(b.drop_n), snappedf(float(b.coo_cd), 0.1), snappedf(float(b.drop_cd), 0.1), 1 if bool(b.auto) else 0, int(b.hits)])
	var falling := []
	for blob: Dictionary in blobs:
		var p: Vector3 = blob.pos
		var v: Vector3 = blob.vel
		falling.append([int(blob.id), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1), int(blob.from)])
	var wearing := []
	for victim: int in splats: wearing.append([victim, snappedf(float(splats[victim].left), 0.05), int(splats[victim].from)])
	var told := []
	for event: Dictionary in landed:
		var p: Vector3 = event.pos
		told.append([int(event.seq), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), int(event.victim)])
	return {"b": rows, "d": falling, "s": wearing, "l": told}
