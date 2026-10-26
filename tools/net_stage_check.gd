extends Node
## Dev probe of a whole stage round (levels 25-28) over the real network: the authority and two clients of the engine's Local Play, headless. It is not part of the game:
## `DevEnv.attach_probe` (demo/dev_env.gd) loads it by absolute path from `--net-probe=<path>` in the editor binary only, and the client's `_auto_pad` walks onto the round's
## circle for `--pick=<id>` (r25 .. r28); the clients' round input comes from `round_move` below. `tools/net_stage_check.py` starts everything and judges the logs.
## Every process prints, with its role prefix from Local Play:
##   NETSTAGE_S   once a second: wall s, phase, level clock, tiles gone, hash of the step bytes (StepTiles.join_state of the state's own pieces), hash and hex of the gone bitmap
##                (the level world's is_gone), players alive, eliminations, largest byte field of the state, tiles seen white
##   NETSTAGE_PLAY the play phase begins: the tiles the round starts without (bitmap)
##   NETSTAGE_EV  tile transitions as the level world poses them (white, gone, solid again = a pop-back, un-white), with the level clock and the unix time in ms (u)
##   NETSTAGE_H   a new step-bytes hash with the level clock it first showed (authority: when it published it; a client: when it received it)
##   NETSTAGE_END the round's summary: length of the play phase, tiles gone, white-to-gone interval (min/mean/max), tiles gone without being seen white, pop-backs
## The bots: slot 0 runs for the whole round, every other slot runs `--idle-after=<s>` (default 20) of play and then stands still, so the round ends by itself
## (a runner turns at an edge and at a hole). `--probe-seed=<n>` changes the headings.
const StepTiles := preload("res://levels/step_tiles.gd")
const TAG := "NETSTAGE"
const SAMPLE := 1.0 ## s between the NETSTAGE_S lines
const LOOK := 3.5 ## m a bot looks ahead for a tile under its feet
const TURN := [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4, PI]
const EDGE_OUTSIDE := 0.2

var role := ""
var host: Node
var rng := RandomNumberGenerator.new()
var idle_after := 20.0
var quit_at_end := true
var idle_edge := false ## --idle-edge: the idle bots stop with the middle of their feet EDGE_OUTSIDE m past the edge of a tile next to a hole (where a courier can rest)
var _edge_target := Vector2.INF

var world: Node3D
var tiles: Object ## the active level's StepTiles
var level := -1
var count := 0
var round_id := 0
var phase := "" ## the round state's phase ("" outside a round)
var play_time := 0.0
var started := false ## the play phase began: the baselines are taken
var ended := false
var prev_mode := PackedByteArray()
var white_at := PackedFloat64Array()
var gone_at := PackedFloat64Array()
var start_gone := 0
var gone_count := 0
var no_white := 0
var pops := 0
var unwhite := 0
var intervals: Array = []
var last_hash := 0
var _raw_hash := 0
var _last_state := {}
var hashes := 0
var max_field := 0
var max_snapshot_fields := 0
var sample_clock := 0.0
var sample_wall := 0.0
var seed_value := 1
var heading := -1000.0
var heading_until := 0.0
var wall := 0.0

func attach(parent: Node, which: String) -> void:
	role = which
	host = parent
	name = "NetStageProbe"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--idle-after="): idle_after = float(argument.trim_prefix("--idle-after="))
		if argument.begins_with("--probe-seed="): seed_value = int(argument.trim_prefix("--probe-seed="))
		if argument == "--probe-keep": quit_at_end = false
		if argument == "--idle-edge": idle_edge = true
	parent.add_child.call_deferred(self)
	print(TAG, " attached role=", role)

# ------------------------------------------------------------------ the clients' input

## The bot's world-space move for this physics tick (client/main.gd, in the round only): walks straight, bends at random, turns away from an edge or a hole.
func round_move(delta: float) -> Vector2:
	if phase != "play" or world == null or level < 0: return Vector2.ZERO
	var slot := int(host.get("my_slot"))
	var actors: Array = host.simulation.actors
	if slot < 0 or slot >= actors.size(): return Vector2.ZERO
	if slot > 0 and play_time >= idle_after: return _idle_move(actors[slot].position) if idle_edge else Vector2.ZERO
	if heading < -100.0:
		rng.seed = seed_value * 7919 + slot * 104729
		heading = rng.randf() * TAU
	var position: Vector3 = actors[slot].position
	heading_until -= delta
	var direction := Vector2(cos(heading), sin(heading))
	var blocked := (world.tiles_under(level, position + Vector3(direction.x, 0.0, direction.y) * LOOK) as Array).is_empty()
	if blocked or heading_until <= 0.0:
		if heading_until <= 0.0 and not blocked: heading += rng.randf_range(-0.7, 0.7)
		else:
			for turn: float in TURN:
				var trial := heading + turn
				var ahead := position + Vector3(cos(trial), 0.0, sin(trial)) * LOOK
				if not (world.tiles_under(level, ahead) as Array).is_empty():
					heading = trial
					break
			if (world.tiles_under(level, position + Vector3(cos(heading), 0.0, sin(heading)) * LOOK) as Array).is_empty(): heading += PI * 0.5
		heading_until = rng.randf_range(1.0, 2.5)
	return Vector2(cos(heading), sin(heading))

## --idle-edge: walk to the spot EDGE_OUTSIDE m past the edge of the tile under the feet, on a side with a hole beyond it, and stand there (the courier rests on the edge).
func _idle_move(position: Vector3) -> Vector2:
	if _edge_target == Vector2.INF:
		var origin: Vector3 = world.level_origin(level)
		var local := position - origin
		var here: Array = tiles.tiles_at(local, 0.0)
		if not here.is_empty():
			var centre: Vector3 = tiles.data.tiles[int(here[0])].p
			var corners: PackedVector2Array = StepTiles.tile_corners(tiles.data, 0.0)
			for step in 12:
				var direction := Vector2.from_angle(TAU * step / 12.0 + 0.1)
				var reach := -INF
				for corner in corners: reach = maxf(reach, corner.dot(direction))
				var spot := Vector2(centre.x, centre.z) + direction * (reach + EDGE_OUTSIDE)
				if (tiles.tiles_at(Vector3(spot.x, local.y, spot.y), 0.0) as Array).is_empty():
					_edge_target = spot + Vector2(origin.x, origin.z)
					print(TAG, "_EDGE role=", role, " target=", _edge_target, " tile=", int(here[0]))
					break
	if _edge_target == Vector2.INF: return Vector2.ZERO # no tile under the feet yet (falling): look again next tick
	var to := _edge_target - Vector2(position.x, position.z)
	return Vector2.ZERO if to.length() < 0.03 else to.normalized() * clampf(to.length() * 3.0, 0.08, 1.0)

# ------------------------------------------------------------------ the log

func _physics_process(delta: float) -> void:
	wall += delta
	var state := _state()
	if not state.is_empty(): _last_state = state
	var now_phase := str(state.get("phase", ""))
	if now_phase != phase:
		print(TAG, "_PHASE role=", role, " ", phase, " -> ", now_phase, " clock=", _clock())
		if now_phase == "card": _begin(state)
		if now_phase == "play" and not started: _baseline()
		if now_phase == "" and started and not ended: _end(_last_state)
		phase = now_phase
	if phase == "play": play_time += delta
	if world == null or level < 0 or not started or ended: return
	_fields(state)
	_transitions()
	_hash(state)
	if wall - sample_wall >= SAMPLE:
		sample_wall = wall
		_sample(state)

## Unix time in ms (one machine: the processes share it): the real delay of a state between the authority and a client.
func _unix() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _clock() -> float:
	return snappedf(float(world.get("clock")), 0.001) if world != null else -1.0

## The state of the round as this process holds it: the rules' own state() on the authority, what arrived in the snapshot on a client; {} outside a round.
func _state() -> Dictionary:
	if world == null and host.get("simulation") != null: world = host.simulation.get("level_world")
	if str(host.get("phase")) != "round": return {}
	if role == "authority":
		var rules: Variant = host.get("minigame")
		return _authority_state(rules) if rules != null else {}
	var info: Variant = host.get("match_info")
	var state: Variant = info.get("minigame", {}) if info is Dictionary else {}
	return state if state is Dictionary else {}

var _cached_state := {}
var _cached_at := -1.0

## state() builds the packed fields: once per 0.1 s of wall time here, not every tick (the phase is read from the rules directly).
func _authority_state(rules: Object) -> Dictionary:
	if wall - _cached_at >= 0.1 or str(rules.phase) != str(_cached_state.get("phase", "")):
		_cached_state = rules.state()
		_cached_at = wall
	return _cached_state

func _begin(state: Dictionary) -> void:
	round_id += 1
	level = int(state.get("level", -1))
	started = false
	ended = false
	play_time = 0.0
	intervals = []
	no_white = 0
	pops = 0
	unwhite = 0
	gone_count = 0
	hashes = 0
	last_hash = 0
	_raw_hash = 0
	var entry: Dictionary = world.call("_entry", level)
	tiles = entry.get("tiles")
	count = int(tiles.tile_count())
	white_at = PackedFloat64Array()
	white_at.resize(count)
	white_at.fill(-1.0)
	gone_at = white_at.duplicate()
	print(TAG, "_ROUND role=", role, " round=", round_id, " level=", level + 1, " tiles=", count, " players=", int(state.get("n", 0)), " need=", int(state.get("need", 0)))

## The play phase begins: the tiles the round starts without (fewer players, a smaller arena) are the baseline, every change from here on is an event.
func _baseline() -> void:
	if tiles == null: return
	started = true
	prev_mode = (tiles.get("_mode") as PackedByteArray).duplicate()
	start_gone = 0
	for index in count:
		if prev_mode[index] >= StepTiles.MODE_FALL: start_gone += 1
	print(TAG, "_PLAY role=", role, " round=", round_id, " clock=", _clock(), " start_gone=", start_gone, " bm=", _gone_bitmap().hex_encode())

func _transitions() -> void:
	var mode: PackedByteArray = tiles.get("_mode")
	if mode == prev_mode: return
	var clock := _clock()
	for index in count:
		var before := int(prev_mode[index])
		var after := int(mode[index])
		if before == after: continue
		var was_gone := before >= StepTiles.MODE_FALL
		var is_gone := after >= StepTiles.MODE_FALL
		if is_gone and not was_gone:
			gone_at[index] = clock
			gone_count += 1
			if white_at[index] < 0.0: no_white += 1
			else: intervals.append(clock - white_at[index])
			print(TAG, "_EV role=", role, " round=", round_id, " clock=", clock, " u=", _unix(), " kind=gone i=", index)
		elif was_gone and not is_gone:
			gone_count -= 1
			pops += 1
			print(TAG, "_EV role=", role, " round=", round_id, " clock=", clock, " u=", _unix(), " kind=solid i=", index)
		elif after == StepTiles.MODE_WARN:
			white_at[index] = clock
			print(TAG, "_EV role=", role, " round=", round_id, " clock=", clock, " u=", _unix(), " kind=white i=", index)
		elif before == StepTiles.MODE_WARN and after == StepTiles.MODE_SOLID:
			unwhite += 1
			print(TAG, "_EV role=", role, " round=", round_id, " clock=", clock, " u=", _unix(), " kind=unwhite i=", index)
	prev_mode = mode.duplicate()

## The step bytes as the wire carries them: a client's join of the received pieces, the authority's join of the pieces it publishes (pack_state of the rules' own bytes).
func _steps(state: Dictionary) -> PackedByteArray:
	if role == "authority":
		var rules: Variant = host.get("minigame")
		if rules != null: return StepTiles.join_state(StepTiles.pack_state(rules.tiles), count)
	return StepTiles.join_state(state, count)

func _hash(state: Dictionary) -> void:
	if role == "authority":
		var raw: int = hash(host.minigame.tiles) if host.get("minigame") != null else 0
		if raw == _raw_hash: return
		_raw_hash = raw
	var value := hash(_steps(state))
	if value == last_hash: return
	last_hash = value
	hashes += 1
	print(TAG, "_H role=", role, " round=", round_id, " clock=", _clock(), " u=", _unix(), " hash=", value)

func _fields(state: Dictionary) -> void:
	var biggest := 0
	for key: Variant in state:
		var value: Variant = state[key]
		if value is PackedByteArray: biggest = maxi(biggest, (value as PackedByteArray).size())
	max_field = maxi(max_field, biggest)

func _gone_bitmap() -> PackedByteArray:
	var mode: PackedByteArray = tiles.get("_mode")
	var bitmap := PackedByteArray()
	bitmap.resize((count + 7) / 8)
	for index in count:
		if mode[index] >= StepTiles.MODE_FALL: bitmap[index >> 3] = int(bitmap[index >> 3]) | (1 << (index & 7))
	return bitmap

## Where the couriers stand (x/y/z, rounded; the process's own view of every slot).
func _positions() -> String:
	var text := ""
	for actor: Variant in host.simulation.actors:
		var at: Vector3 = actor.position
		text += "%d/%d/%d;" % [roundi(at.x), roundi(at.y), roundi(at.z)]
	return text

## The authority's view of what each courier stands on: tile index, its step byte, its mode (0 solid, 1 white, 2/3 gone) per tile under the feet, per slot.
func _under() -> String:
	var text := ""
	var actors: Array = host.simulation.actors
	var steps: PackedByteArray = tiles.get("steps")
	var mode: PackedByteArray = tiles.get("_mode")
	for slot in mini(actors.size(), 2):
		text += "s%d[" % slot
		for index: int in world.tiles_under(level, actors[slot].position):
			text += "%d:%d:%d," % [index, steps[index], mode[index]]
		text += "];"
	return text

## What this process's own courier stands on, by a ray straight down from its feet (every collision layer): the body, and for a floor of tiles the tile whose shape it is and that tile's mode.
func _ray() -> String:
	var slot := int(host.get("my_slot")) if role != "authority" else 0
	var actors: Array = host.simulation.actors
	if slot < 0 or slot >= actors.size(): return "-"
	var at: Vector3 = actors[slot].position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 3.0, 0xFFFFFFFF)
	var hit: Dictionary = host.simulation.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return "none"
	var body: Object = hit.collider
	var text := str(body.name)
	if body is CollisionObject3D:
		var owner_id: int = (body as CollisionObject3D).shape_find_owner(int(hit.shape))
		var owners: PackedInt32Array = tiles.get("_owner")
		var mode: PackedByteArray = tiles.get("_mode")
		for index in count:
			if owners[index] == owner_id and (tiles.get("tile_bodies") as Array).has(body):
				text += ":tile%d:mode%d" % [index, mode[index]]
				break
	return "%s@%.2f" % [text, float(hit.position.y) - float(at.y)]

## The client's own courier driver: stepping only while active (the owner's epoch seen, the round playing, no partner missing); the authority has none.
func _owner() -> String:
	var owner_courier: Variant = host.get("owner_courier")
	if owner_courier == null: return "-"
	return "active=%s epoch=%d/%d playing=%s waiting=%s steps=%d" % [owner_courier.active, owner_courier.reset_epoch, owner_courier.observed_epoch, owner_courier.shared_playing, owner_courier.waiting_for_partner, int(owner_courier.metrics.get("steps", 0))]

func _alive(state: Dictionary) -> int:
	var total := 0
	for status: Variant in state.get("status", []):
		if int(status) == 0: total += 1
	return total

func _white() -> int:
	var mode: PackedByteArray = tiles.get("_mode")
	var total := 0
	for index in count:
		if mode[index] == StepTiles.MODE_WARN: total += 1
	return total

func _sample(state: Dictionary) -> void:
	var bitmap := _gone_bitmap()
	print(TAG, "_S role=", role, " round=", round_id, " wall=", snappedf(wall, 0.01), " phase=", phase, " t=", float(state.get("t", 0.0)), " clock=", _clock(), " gone=", gone_count,
		" tiles_hash=", hash(_steps(state)), " gone_hash=", hash(bitmap), " alive=", _alive(state), " elim=", (state.get("fell", []) as Array).size(),
		" max_field=", max_field, " white=", _white(), " pos=", _positions(), " under=", _under(), " ray=", _ray(), " owner=", _owner(), " bm=", bitmap.hex_encode())

func _end(state: Dictionary) -> void:
	ended = true
	var total := 0.0
	var low := INF
	var high := -INF
	for gap: float in intervals:
		total += gap
		low = minf(low, gap)
		high = maxf(high, gap)
	var mean := total / intervals.size() if not intervals.is_empty() else -1.0
	print(TAG, "_END role=", role, " round=", round_id, " level=", level + 1, " play_s=", snappedf(play_time, 0.01), " clock=", _clock(), " gone=", gone_count, " start_gone=", start_gone,
		" white_to_gone_n=", intervals.size(), " min=", snappedf(low if low != INF else -1.0, 0.001), " mean=", snappedf(mean, 0.001), " max=", snappedf(high if high != -INF else -1.0, 0.001),
		" no_white=", no_white, " pops=", pops, " unwhite=", unwhite, " hashes=", hashes, " max_field=", max_field, " elim=", (state.get("fell", []) as Array).size())
	if quit_at_end:
		await get_tree().create_timer(1.5 if role != "authority" else 4.0).timeout
		get_tree().quit(0)
