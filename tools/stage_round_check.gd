extends SceneTree
## Whole survival rounds of the stage levels (25-28) with 2, 4, 8, 10 and 12 bots, headless, no shell: REAL courier physics (courier_motion.gd in the stage feel, the one-way
## floors), REAL contact between the couriers (players/player_contact.gd, the bump), the REAL level world (colliders follow the step bytes), the REAL ShowRules (card, play, done,
## the tiles stepped by whoever stands on them, the elimination when a player lands on the ground floor) on a host answering from that one world.
## The bots run like people do: a straight line over tiles nobody has stepped, a turn where the ground ends or the tile ahead is gone, a jump over a hole one tile wide, away
## from each other (and bumping when they do meet), a little wander now and then; `--pace=0.8` is the share of the full run they hold (below 0.56 a runner falls through the tile it just stepped: a tile is 2 per 0.5 s).
## Per level and player count it prints one line with the round's length (the play phase up to the deciding elimination and its END_GRACE), the eliminations over time
## (per 10 s), the layer counts, and asserts: the round ends by itself (before the cap), at most `need` players stand at the end and at least one,
## everybody who was eliminated stands on the ground floor (or fell off the slab), nobody is stuck (commanded to run and not moving for 2 s, or hanging in the air without
## moving: on a tile edge, under a layer, between couriers), every landing is clean (no bounce), the tile state always travels in pieces of at most 240 B. The lengths are
## REPORTED against the targets (about 103-116 s for 12 players on a square stack, about 137 s on a hex stack), they are not asserted: the arena is what it is.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 3000 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 \
##     --path demo -s $PWD/tools/stage_round_check.gd [-- --levels=25,26,27,28 --players=2,4,8,10,12 --pace=0.8 --hops=0.5 --seed=1 --trace]
## Prints STAGE_ROUND lines, a STAGE_ROUND table of the combinations, and `STAGE_ROUND ok=<bool>` last.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const PlayerContact := preload("res://players/player_contact.gd")
const DT := 1.0 / 60.0
const TARGETS := {"square": 110.0, "hex": 137.0} ## s, the round's length with 12 players
const MIN_LENGTH := 15.0 ## s a round must last at least
const STUCK_TIME := 2.0 ## s a bot may be commanded to run and make no headway
const STUCK_SPEED := 1.5 ## m/s: headway under this is none
const HOVER_TIME := 0.5 ## s a bot may hang in the air without moving up or down
const BOUNCE_SPEED := 0.5 ## m/s upward within BOUNCE_WINDOW s after a landing, with no jump asked for: the landing bounced
const BOUNCE_WINDOW := 0.3
const DROP_SPEED := 12.0 ## m/s of fall speed: a landing slower than this is a stepped tile sinking its 0.5 m under the courier (9 m/s); a jump lands at 23, a layer down at 17
const LOOK_STEPS := [1.0, 2.0, 3.0, 4.0] ## tiles ahead a bot looks at
const FAR_STEPS := [6.0, 8.0, 10.0, 12.0] ## and further, for whole ground
const TURN_STEP := 15.0 ## degrees between the headings a bot considers
const CROWD := 7.0 ## m: a bot looks at the others this near when it picks a heading

## ModeHost without a shell: positions are the bodies', every question about the level goes to the one LevelWorld.
class StageHost extends "modes/fake_host.gd":
	var world: Node3D
	var bodies: Array = []
	var motions: Array = []
	func zone(slot: int, level: int) -> String:
		return world.zone_at(level, position(slot))
	func scorch(_slot: int, _level: int) -> String:
		return ""
	func level_clock() -> float:
		return world.clock
	func begin_level(level: int, out := []) -> void:
		bench(out)
		world.set_active_level(level)
		world.set_clock(0.0)
		var start: Dictionary = world.team_start(level, count)
		for slot in count:
			place(slot, (start.pos[slot] if slot < start.pos.size() else start.spot) + Vector3.UP * 0.05, float(start.yaw))
	func place(slot: int, at: Vector3, yaw := 0.0) -> void:
		positions[slot] = at
		if slot < bodies.size(): (motions[slot] as Object).reset(bodies[slot], at, yaw)
	func respawn(slot: int, level: int, checkpoint: int) -> void:
		var spot: Dictionary = world.team_start(level, count, checkpoint)
		place(slot, (spot.pos[slot] if slot < spot.pos.size() else spot.spot) + Vector3.UP * 0.05, float(spot.yaw))
	func send_to(slot: int, at: Vector3, yaw := 0.0) -> void:
		super(slot, at, yaw)
		if slot < bodies.size(): (motions[slot] as Object).reset(bodies[slot], at, yaw)
	func tile_start(level: int, players: int) -> PackedByteArray:
		return world.tile_start(level, players)
	func tiles_under(slot: int, level: int) -> Array:
		return world.tiles_under(level, position(slot))
	func apply_tiles(level: int, steps: PackedByteArray) -> void:
		world.set_tile_steps(level, steps)
	func tile_stamp(level: int) -> int:
		return world.tile_stamp(level)
	func tile_settled(level: int, index: int) -> bool:
		return world.tile_settled(level, index)

## One bot's state: where it heads, how long it takes to look again, and the counters of what went wrong.
class Bot extends RefCounted:
	var slot := 0
	var heading := Vector2.DOWN
	var share := 0.9 ## of the full run
	var look_in := 0.0 ## s until it looks around again
	var wander_in := 0.0 ## s until it turns for no reason
	var jump_cool := 0.0
	var layer := 0
	var airborne := 0.0
	var still := 0.0 ## s commanded to run and not getting anywhere
	var hover := 0.0
	var stuck := 0
	var wedged := 0
	var bounced := 0
	var landings := 0
	var drops := 0 ## landings slower than DROP_SPEED: a stepped tile sinking under the courier
	var hop_in := 1.0 ## s until the next hop
	var jumps := 0
	var since_landing := 99.0
	var jumped_for := 0.0
	var last_up := false
	var rng := RandomNumberGenerator.new()

var failures := 0
var world: Node3D
var pace := 0.8
var hops := 0.5 ## jumps a second a bot makes on average while it runs
var seed_value := 1
var trace := false
var only_levels: Array = [24, 25, 26, 27]
var only_players: Array = [2, 4, 8, 10, 12]
var rows: Array = []

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_ROUND ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="): only_levels = Array(argument.trim_prefix("--levels=").split(",")).map(func(text: String) -> int: return int(text) - 1)
		if argument.begins_with("--players="): only_players = Array(argument.trim_prefix("--players=").split(",")).map(func(text: String) -> int: return int(text))
		if argument.begins_with("--pace="): pace = float(argument.trim_prefix("--pace="))
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--hops="): hops = float(argument.trim_prefix("--hops="))
		if argument == "--trace": trace = true
	create_timer(3300.0).timeout.connect(func() -> void:
		print("STAGE_ROUND FAIL timed out")
		print("STAGE_ROUND ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	for level: int in only_levels:
		for players: int in only_players:
			await play_round(level, players)
	print("STAGE_ROUND table  (pace %.2f, seed %d; length = play time to the deciding elimination + %.1f s grace, target %s)" % [pace, seed_value, ShowRules.END_GRACE, str(TARGETS)])
	print("STAGE_ROUND table | level | players | need | length s | first out s | out per 10 s | alive | stuck | wedged | bounces | landings | drops of a sinking tile | tiles used | max field B |")
	for row: String in rows: print("STAGE_ROUND table ", row)
	print("STAGE_ROUND ok=", failures == 0)
	quit(0 if failures == 0 else 1)

## The floor (index) a courier at `feet` stands over: the highest floor top at or under its feet (+ a step).
func floor_of(floors: Array, feet_y: float, origin_y: float) -> int:
	var best := -1
	for index in floors.size():
		if origin_y + float(floors[index].y) <= feet_y + 0.7 and (best < 0 or float(floors[index].y) > float(floors[best].y)): best = index
	return best

func play_round(level: int, players: int) -> void:
	var entry: Dictionary = world._levels[level]
	var grid := str(entry.data.tiles.grid)
	var label := "level %d (%s) with %d bots" % [level + 1, grid, players]
	var seats: Array = []
	for slot in players: seats.append(slot)
	var host := StageHost.new(seats, seed_value)
	host.world = world
	host.pick = "r%d" % (level + 1)
	var floors: Array = entry.data.tiles.floors
	var tops := PackedFloat32Array()
	for layout: Dictionary in floors: tops.append(float(layout.y) + (world.level_origin(level) as Vector3).y)
	var bots: Array = []
	for slot in players:
		var body := Motion.make_body("Courier")
		world.add_child(body)
		var motion := Motion.new()
		motion.setup(body)
		motion.set_stage(true)
		motion.set_floors(tops)
		host.bodies.append(body)
		host.motions.append(motion)
		var bot := Bot.new()
		bot.slot = slot
		bot.rng.seed = seed_value * 100003 + level * 1009 + players * 31 + slot
		bot.heading = Vector2.from_angle(bot.rng.randf() * TAU)
		bot.share = clampf(pace + bot.rng.randf_range(-0.08, 0.06), 0.4, 1.0)
		bot.look_in = bot.rng.randf_range(0.0, 0.3)
		bot.wander_in = bot.rng.randf_range(1.5, 4.0)
		bots.append(bot)
	var contact := PlayerContact.new(players)
	contact.stage = true
	var rules := ShowRules.new()
	rules.start(host)
	var origin: Vector3 = world.level_origin(level)
	var tiles: StepTiles = entry.tiles
	var pitch := float(entry.data.tiles.pitch)
	var ground_y := float(entry.data.stage.ground.y) + origin.y
	var seen_fell := 0
	var fell_times: Array = []
	var fell_heights: Array = []
	var layer_falls := {}
	var oversize := 0
	var largest := 0
	var clock := 0.0
	var ticks := 0
	while rules.phase != "done" and clock < 220.0:
		await physics_frame
		ticks += 1
		clock += DT
		world.advance(DT)
		var states: Array = []
		for slot in players:
			var body: CharacterBody3D = host.bodies[slot]
			states.append({"position": body.global_position + Vector3(0.0, 0.9, 0.0), "velocity": body.velocity})
		var results: Array = contact.step(DT, states).results
		for slot in players:
			var body: CharacterBody3D = host.bodies[slot]
			var motion: Object = host.motions[slot]
			var bot: Bot = bots[slot]
			var result: Dictionary = results[slot]
			if result.separate != Vector3.ZERO: body.move_and_collide(result.separate)
			if result.impulse != Vector3.ZERO: motion.launch(result.impulse, false, false)
			var input := {}
			var playing: bool = rules.status[slot] == ShowRules.PLAYING and rules.phase == "play"
			if playing: input = bot_input(bot, host, rules, level, floors, origin, pitch, tiles, body, motion, players)
			if float(result.stagger) > 0.0:
				motion.set_surface({"ice": true})
				if input.has("move"): input.move = (input.move as Vector2) * 0.35
			else: motion.set_surface({})
			var events: Dictionary = motion.step(body, input, DT)
			host.positions[slot] = body.global_position
			if playing: watch(bot, events, input, body, motion)
		rules.tick(DT)
		if ticks % 30 == 0:
			var state: Dictionary = rules.state()
			for key: String in state:
				if state[key] is PackedByteArray:
					largest = maxi(largest, (state[key] as PackedByteArray).size())
					if (state[key] as PackedByteArray).size() > StepTiles.CHUNK: oversize += 1
		while seen_fell < rules.fell.size():
			var slot: int = rules.fell[seen_fell]
			var at: Vector3 = (host.bodies[slot] as CharacterBody3D).global_position
			var last_layer: int = (bots[slot] as Bot).layer # the layer it last stood on
			fell_times.append(rules.phase_time)
			fell_heights.append(at.y - ground_y)
			layer_falls[last_layer] = int(layer_falls.get(last_layer, 0)) + 1
			if trace: print("STAGE_ROUND out t=%.1f bot %d last on layer %d, now at %s (level-local)" % [rules.phase_time, slot, last_layer, (at - origin).snapped(Vector3.ONE * 0.1)])
			seen_fell += 1
		if trace and ticks % 60 == 0 and rules.phase == "play": print("STAGE_ROUND layers t=%.0f %s" % [rules.phase_time, str(bots.map(func(bot: Bot) -> int: return bot.layer))])
		if trace and ticks % 600 == 0:
			var standing := 0
			for byte in rules.tiles: if byte == 0: standing += 1
			print("STAGE_ROUND trace t=%.0f alive=%d unstepped=%d/%d" % [rules.phase_time, rules._alive().size(), standing, rules.tiles.size()])
	var capped: bool = rules._end_at < 0.0 # the cap ended it: nobody was put out any more
	var length: float = rules._deadline if capped else rules._end_at
	var alive: int = rules._alive().size()
	var cap := float(entry.data.stage.cap)
	var safe := 0
	for slot in players: if rules.status[slot] == ShowRules.SAFE: safe += 1
	var stuck := 0
	var wedged := 0
	var bounces := 0
	var landings := 0
	var drops := 0
	var jumps := 0
	for bot: Bot in bots:
		stuck += bot.stuck
		wedged += bot.wedged
		bounces += bot.bounced
		landings += bot.landings
		drops += bot.drops
		jumps += bot.jumps
	var used := 0
	for byte in rules.tiles: if byte != 0 and byte != StepTiles.PRE_GONE: used += 1
	var buckets := []
	for bucket in ceili(maxf(length, 10.0) / 10.0): buckets.append(0)
	for time: float in fell_times: buckets[mini(int(time / 10.0), buckets.size() - 1)] += 1
	var first: float = fell_times[0] if not fell_times.is_empty() else -1.0
	var off_ground := 0
	for height: float in fell_heights: if height > ShowRules.STAGE_LAND + 0.05: off_ground += 1
	var target: float = TARGETS[grid] if players == 12 else -1.0
	print("STAGE_ROUND note %s: ended at play-time %.1f s%s (cap %.0f), first out %.1f s, %d out, need %d, alive at the end %d, outs per 10 s %s, outs by the layer last stood on %s, %d tiles used (%.1f a second), jumps %d, landings %d, drops of a sinking tile %d" % [
		label, length, "" if target < 0.0 else " (target about %.0f s: %+.0f %%)" % [target, (length / target - 1.0) * 100.0], cap, first, rules.fell.size(), rules.need, alive, str(buckets), str(layer_falls), used, float(used) / maxf(length, 1.0), jumps, landings, drops])
	check(rules.phase == "done", "%s: the round ends by itself at %.1f s (%s, cap %.0f)" % [label, length, "at the cap: nobody could be put out any more" if capped else "by the eliminations", cap])
	check(length >= MIN_LENGTH, "%s: lasts at least %.0f s (%.1f s)" % [label, MIN_LENGTH, length])
	check((rules.points_mode or (safe <= rules.need and safe >= 1)) and (capped or alive <= rules.need), "%s: %s, %d standing at the end (need %d)" % [label, "points mode: everybody scores" if rules.points_mode else "%d go through" % safe, alive, rules.need])
	check(capped or rules.fell.size() >= players - rules.need, "%s: %d out, at least %d unless the cap ended it" % [label, rules.fell.size(), players - rules.need])
	check(off_ground == 0, "%s: everybody out stood on the ground floor (or was over the slab's edge): %d did not" % [label, off_ground])
	check(stuck == 0 and wedged == 0, "%s: nobody stuck (%d runs without headway for %.0f s, %d hung in the air)" % [label, stuck, STUCK_TIME, wedged])
	check(bounces == 0, "%s: %d landings (and %d drops of a sinking tile), none bounced" % [label, landings, drops])
	check(oversize == 0, "%s: the tile state always goes out in pieces of at most %d B (largest %d B)" % [label, StepTiles.CHUNK, largest])
	rows.append("| %d (%s) | %d | %d | %.1f%s | %.1f | %s | %d | %d | %d | %d | %d | %d | %d | %d |" % [level + 1, grid, players, rules.need, length, " (cap)" if capped else "", first, "/".join(buckets.map(func(count: int) -> String: return str(count))), alive, stuck, wedged, bounces, landings, drops, used, largest])
	for body: CharacterBody3D in host.bodies: body.queue_free()
	await physics_frame
	world.set_clock(0.0)

## What went wrong with a bot this tick: no headway while running, hanging in the air, a bounce after a landing.
func watch(bot: Bot, events: Dictionary, input: Dictionary, body: CharacterBody3D, motion: Object) -> void:
	var planar := Vector2(body.velocity.x, body.velocity.z).length()
	var asked: bool = input.has("move") and (input.move as Vector2).length() > 0.3
	if motion.grounded and asked and planar < STUCK_SPEED: bot.still += DT
	else: bot.still = 0.0
	if bot.still >= STUCK_TIME:
		bot.stuck += 1
		bot.still = -STUCK_TIME # counted again after another STUCK_TIME of it
	if not motion.grounded and absf(body.velocity.y) < 0.1 and planar < STUCK_SPEED: bot.hover += DT
	else: bot.hover = 0.0
	if bot.hover >= HOVER_TIME:
		bot.wedged += 1
		bot.hover = -HOVER_TIME
	bot.since_landing += DT
	if events.landed:
		if float(events.land_speed) >= DROP_SPEED: bot.landings += 1
		else: bot.drops += 1
		bot.since_landing = 0.0
		bot.look_in = 0.0 # a new floor: look again
	if bool(input.get("jump", false)): bot.jumped_for = 0.5
	else: bot.jumped_for = maxf(bot.jumped_for - DT, 0.0)
	if bot.since_landing <= BOUNCE_WINDOW and not motion.grounded and body.velocity.y > BOUNCE_SPEED and bot.jumped_for <= 0.0: bot.bounced += 1
	if events.jumped: bot.jumps += 1

## The tile of `layer` that holds level-local (x, z) and is still there, -1 for none (a hole, or past the edge).
func ground_at(level: int, tiles: StepTiles, floors: Array, layer: int, at: Vector2) -> int:
	for index: int in tiles.tiles_at(Vector3(at.x, float((floors[layer] as Dictionary).y), at.y), 0.0):
		if not world.tile_gone(level, index): return index
	return -1

## The bot's input this tick: run in a straight line over tiles nobody has stepped, turn where the ground ends, jump a hole one tile wide.
func bot_input(bot: Bot, host: StageHost, rules: ShowRules, level: int, floors: Array, origin: Vector3, pitch: float, tiles: StepTiles, body: CharacterBody3D, motion: Object, players: int) -> Dictionary:
	var layer := floor_of(floors, body.global_position.y, origin.y)
	if layer < 0: return {} # on the ground floor or below: out
	if not motion.grounded: return {"move": bot.heading * bot.share} if body.velocity.y > 0.0 else {} # rising: keep the heading, falling: no steering
	var here := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	bot.look_in -= DT
	bot.wander_in -= DT
	bot.jump_cool -= DT
	if layer != bot.layer:
		bot.layer = layer
		bot.look_in = 0.0
	var ahead := ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 1.5)
	if bot.look_in <= 0.0 and (ahead < 0 or bot.wander_in <= 0.0):
		bot.look_in = bot.rng.randf_range(0.1, 0.3) # a person takes a moment to look again
		if bot.wander_in <= 0.0: bot.wander_in = bot.rng.randf_range(1.5, 4.0)
		bot.heading = choose_heading(bot, host, rules, level, floors, layer, origin, pitch, tiles, here, players)
	var jump := false
	if bot.jump_cool <= 0.0 and ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 0.9) < 0 and ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 2.0) >= 0:
		jump = true # a hole one tile wide ahead and ground behind it
		bot.jump_cool = 0.8
	bot.hop_in -= DT
	if bot.hop_in <= 0.0:
		bot.hop_in = -log(maxf(bot.rng.randf(), 0.001)) / maxf(hops, 0.001) # people hop now and then, `hops` times a second on average
		if bot.jump_cool <= 0.0:
			jump = true
			bot.jump_cool = 0.4
	return {"move": bot.heading * bot.share, "jump": jump}

## The heading (within 120 degrees of the old one) with the most ground and the most untouched tiles ahead, a small turn preferred, nobody in the way, a little chance.
func choose_heading(bot: Bot, host: StageHost, rules: ShowRules, level: int, floors: Array, layer: int, origin: Vector3, pitch: float, tiles: StepTiles, here: Vector2, players: int) -> Vector2:
	var best := bot.heading
	var best_score := -INF
	for step in range(-8, 9):
		var dir := bot.heading.rotated(deg_to_rad(float(step) * TURN_STEP))
		var score := bot.rng.randf() * 0.7 - absf(float(step)) * 0.1
		var open := 0
		for distance: float in LOOK_STEPS:
			var index := ground_at(level, tiles, floors, layer, here + dir * pitch * distance)
			if index < 0:
				if distance <= 2.0: score -= 40.0 / distance
				break
			open += 1
			if rules.tiles[index] == 0: score += 1.0
			else: score -= 0.3
		score += float(open) * 0.4
		for distance: float in FAR_STEPS: # people head for the part of the floor that is still whole
			var far := ground_at(level, tiles, floors, layer, here + dir * pitch * distance)
			if far >= 0 and rules.tiles[far] == 0: score += 0.5
		var spot := here + dir * pitch * 3.0
		for other in players:
			if other == bot.slot or rules.status[other] != ShowRules.PLAYING: continue
			var theirs := Vector2(host.positions[other].x - origin.x, host.positions[other].z - origin.z)
			if theirs.distance_to(here) > CROWD * 2.0: continue
			var gap := theirs.distance_to(spot)
			if gap < CROWD: score -= (CROWD - gap) * 0.25
		if score > best_score:
			best_score = score
			best = dir
	return best
