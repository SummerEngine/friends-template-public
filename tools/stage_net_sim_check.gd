extends SceneTree
## Whole stage rounds (levels 25-28) through a simulated network, in one process, headless, no shell: the authority is the REAL ShowRules on a REAL LevelWorld, walkers
## stand and run on its tiles (kinematic: they stand on the tile under their feet, fall through a hole onto the next floor, and are out on the ground); a replica LevelWorld is fed ONLY
## through the state dictionaries the rules publish (ShowRules.state(), deep-copied) as client/main.gd feeds the client: `StepTiles.join_state` of the pieces into `set_tile_steps`
## and the authority's level clock into `correct_clock`, once per snapshot. The link has latency, jitter and dropped snapshots (default: 20 snapshots a second like the real
## stream, 100 ms, +-30 ms uniform, 5 % dropped; a snapshot older than the newest one applied is discarded, as the stream's latest-state rule does). A second replica joins late (its first
## state, mid-round, is applied quietly) and the round is played twice in a row (the replica's clock goes back to 0 for the new round).
## Per level it prints the round's length, the tiles gone, and for each replica: the delay of a tile's exit against the authority's (in level clock and in real time), the white-to-gone
## interval, the bitmaps once a second against the authority's at the same level clock, the pop-backs (gone -> solid) and white tiles that went solid again, the state's largest byte field.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 \
##     --path demo -s $PWD/tools/stage_net_sim_check.gd [-- --levels=25,26,27,28 --players=2,6 --rounds=2 --latency=0.1 --jitter=0.03 --drop=0.05 --hz=20 --idle-after=20 --seed=1 --spike]
## `--spike` adds one 0.4 s stall of the link in the middle of every round (nothing is delivered, then everything at once). Prints STAGE_NET_SIM lines and `STAGE_NET_SIM ok=<bool>` last.
const LevelWorld := preload("res://levels/level_world.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const DT := 1.0 / 60.0
const RUN := 12.6 ## m/s (STAGE_FEEL: 3.6 E/s)
const GRAVITY := 86.4 ## m/s^2
const LOOK := 3.5 ## m a walker looks ahead
const TURN := [0.0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4, PI]
const STALL := 0.4 ## s of the --spike stall
const WHITE_MAX := 0.62 ## 0.5 s of weight + the step byte's 0.05 s unit + a tick
const TILE_LAG := 0.1 ## s: a tile goes at a replica within this of the authority's level clock
const BITMAP_WINDOW := 0.1 ## s: a replica's gone set equals the authority's at a level clock within this of its own

## ModeHost without a shell: the walkers' positions, every question about the level goes to the authority's LevelWorld.
class SimHost extends "modes/fake_host.gd":
	var world: Node3D
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
		for slot in count: positions[slot] = (start.pos[slot] if slot < start.pos.size() else start.spot) + Vector3.UP * 0.05
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

## A runner: straight lines over the tiles, a bend now and then, a turn away from a hole or the edge; falls with gravity when the tile under it is gone.
class Walker extends RefCounted:
	var slot := 0
	var position := Vector3.ZERO
	var vy := 0.0
	var standing := true
	var heading := 0.0
	var turn_in := 1.0
	var idle_after := INF
	var rng := RandomNumberGenerator.new()

## What one world did to its tiles during a round: when each went white and gone (level clock and real time), and every step back.
class Tracker extends RefCounted:
	var tiles: Object
	var count := 0
	var prev := PackedByteArray()
	var white_clock := PackedFloat64Array()
	var white_time := PackedFloat64Array()
	var gone_clock := PackedFloat64Array()
	var gone_time := PackedFloat64Array()
	var start_gone := PackedByteArray()
	var intervals: Array = []
	var pops := 0
	var pop_log: Array = [] ## [tile, level clock, real time] of the first pop-backs
	var unwhite := 0
	var no_white := 0
	var samples: Array = [] ## [level clock, gone bitmap bytes]
	func begin(world: Node3D, level: int) -> void:
		tiles = (world.call("_entry", level) as Dictionary).tiles
		count = int(tiles.tile_count())
		white_clock = PackedFloat64Array()
		white_clock.resize(count)
		white_clock.fill(-1.0)
		white_time = white_clock.duplicate()
		gone_clock = white_clock.duplicate()
		gone_time = white_clock.duplicate()
		intervals = []
		samples = []
		pops = 0
		pop_log = []
		unwhite = 0
		no_white = 0
		prev = (tiles.get("_mode") as PackedByteArray).duplicate()
		start_gone = bitmap()
	func bitmap() -> PackedByteArray:
		var mode: PackedByteArray = tiles.get("_mode")
		var bits := PackedByteArray()
		bits.resize((count + 7) / 8)
		for index in count:
			if mode[index] >= StepTiles.MODE_FALL: bits[index >> 3] = int(bits[index >> 3]) | (1 << (index & 7))
		return bits
	func poll(clock: float, time: float) -> void:
		var mode: PackedByteArray = tiles.get("_mode")
		if mode == prev: return
		for index in count:
			var before := int(prev[index])
			var after := int(mode[index])
			if before == after: continue
			var was_gone := before >= StepTiles.MODE_FALL
			var is_gone := after >= StepTiles.MODE_FALL
			if is_gone and not was_gone:
				gone_clock[index] = clock
				gone_time[index] = time
				if white_clock[index] < 0.0: no_white += 1
				else: intervals.append(clock - white_clock[index])
			elif was_gone and not is_gone:
				pops += 1
				if pop_log.size() < 4: pop_log.append([index, snappedf(clock, 0.001), snappedf(time, 0.001), snappedf(gone_clock[index], 0.001)])
			elif after == StepTiles.MODE_WARN:
				white_clock[index] = clock
				white_time[index] = time
			elif before == StepTiles.MODE_WARN and after == StepTiles.MODE_SOLID: unwhite += 1
		prev = mode.duplicate()
	func gone_set(bits: PackedByteArray) -> Dictionary:
		var result := {}
		for index in count:
			if int(bits[index >> 3]) & (1 << (index & 7)) != 0: result[index] = true
		return result

## One replica: its world, its tracker, and the state it was last fed.
class Replica extends RefCounted:
	var name := ""
	var world: Node3D
	var tracker := Tracker.new()
	var joined_at := 0.0 ## s of the round's play after which the replica starts to receive
	var live := false
	var last_seq := -1
	var last_phase := ""
	var applied := 0
	var mismatched_bytes := 0
	var back_steps := 0 ## ticks the replica's level clock ran backwards (or jumped back) between two polls
	var back_max := 0.0 ## s: the largest step back
	var clock_before := 0.0
	var level := -1

var failures := 0
var holder: Node3D
var authority_world: Node3D
var replica_worlds: Array = []
var rng := RandomNumberGenerator.new()
var only_levels: Array = [24, 25, 26, 27]
var only_players: Array = [2]
var rounds := 2
var latency := 0.1
var jitter := 0.03
var drop := 0.05
var hz := 20.0
var idle_after := 20.0
var pace := 0.9
var seed_value := 1
var spike := false
var rows: Array = []

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_NET_SIM ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="): only_levels = Array(argument.trim_prefix("--levels=").split(",")).map(func(text: String) -> int: return int(text) - 1)
		if argument.begins_with("--players="): only_players = Array(argument.trim_prefix("--players=").split(",")).map(func(text: String) -> int: return int(text))
		if argument.begins_with("--rounds="): rounds = int(argument.trim_prefix("--rounds="))
		if argument.begins_with("--latency="): latency = float(argument.trim_prefix("--latency="))
		if argument.begins_with("--jitter="): jitter = float(argument.trim_prefix("--jitter="))
		if argument.begins_with("--drop="): drop = float(argument.trim_prefix("--drop="))
		if argument.begins_with("--hz="): hz = float(argument.trim_prefix("--hz="))
		if argument.begins_with("--idle-after="): idle_after = float(argument.trim_prefix("--idle-after="))
		if argument.begins_with("--pace="): pace = float(argument.trim_prefix("--pace="))
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument == "--spike": spike = true
	create_timer(3300.0).timeout.connect(func() -> void:
		print("STAGE_NET_SIM FAIL timed out")
		print("STAGE_NET_SIM ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	authority_world = LevelWorld.new()
	holder.add_child(authority_world)
	await authority_world.build("authority")
	for index in 2:
		var replica_world := LevelWorld.new()
		holder.add_child(replica_world)
		await replica_world.build("client")
		replica_worlds.append(replica_world)
	print("STAGE_NET_SIM link: %.0f snapshots/s, latency %.0f ms, jitter +-%.0f ms, %.1f %% dropped%s; %d round(s) a level" % [hz, latency * 1000.0, jitter * 1000.0, drop * 100.0, ", one 0.4 s stall a round" if spike else "", rounds])
	for level: int in only_levels:
		for players: int in only_players:
			await play_level(level, players)
	print("STAGE_NET_SIM table | level | players | round | length s | tiles gone | replica | tile exit delay vs authority: level clock s min/max, real ms min/mean/max | white to gone s min/mean/max | bitmaps differing/compared | snapshots applied/sent | pop-backs | max field B |")
	for row: String in rows: print("STAGE_NET_SIM table ", row)
	print("STAGE_NET_SIM ok=", failures == 0)
	quit(0 if failures == 0 else 1)

func floor_top(tops: Array, feet_y: float) -> float:
	var best := -INF
	for top: float in tops:
		if top <= feet_y + 0.7 and top > best: best = top
	return best

## One physics tick of a walker on the authority's world.
func step_walker(walker: Walker, rules: Object, world: Node3D, level: int, tops: Array, ground_y: float, play_time: float) -> void:
	var slot := walker.slot
	if rules.phase != "play" or int(rules.status[slot]) != ShowRules.PLAYING: return
	if walker.standing:
		if (world.tiles_under(level, walker.position) as Array).is_empty():
			walker.standing = false
			walker.vy = 0.0
		elif play_time < walker.idle_after:
			walker.turn_in -= DT
			var ahead := walker.position + Vector3(cos(walker.heading), 0.0, sin(walker.heading)) * LOOK
			var blocked := (world.tiles_under(level, ahead) as Array).is_empty()
			if blocked or walker.turn_in <= 0.0:
				if walker.turn_in <= 0.0 and not blocked: walker.heading += walker.rng.randf_range(-0.7, 0.7)
				else:
					for turn: float in TURN:
						var trial: float = walker.heading + turn
						if not (world.tiles_under(level, walker.position + Vector3(cos(trial), 0.0, sin(trial)) * LOOK) as Array).is_empty():
							walker.heading = trial
							break
				walker.turn_in = walker.rng.randf_range(1.0, 2.5)
			walker.position += Vector3(cos(walker.heading), 0.0, sin(walker.heading)) * RUN * pace * DT
	if not walker.standing:
		walker.vy -= GRAVITY * DT
		walker.position.y += walker.vy * DT
		walker.position += Vector3(cos(walker.heading), 0.0, sin(walker.heading)) * RUN * pace * DT * 0.5
		if walker.position.y <= ground_y:
			walker.position.y = ground_y
		elif walker.vy < 0.0 and not (world.tiles_under(level, walker.position) as Array).is_empty():
			walker.position.y = floor_top(tops, walker.position.y)
			walker.standing = true
			walker.vy = 0.0

## The state as the stream would carry it: a deep copy (the replica never shares a byte array with the authority), with the authority's level clock.
func snapshot(rules: Object, world: Node3D, seq: int, time: float) -> Dictionary:
	return {"seq": seq, "sent": time, "clock": world.clock, "state": (rules.state() as Dictionary).duplicate(true)}

## client/main.gd's feed of one received snapshot into the replica's world (modes/show/view.gd _tiles and game_run.gd's clock correction).
func feed(replica: Replica, snap: Dictionary, time: float, round_number: int) -> void:
	var state: Dictionary = snap.state
	var level_now := int(state.get("level", -1))
	var phase := str(state.get("phase", ""))
	var fresh := not replica.live or (phase == "card" and replica.last_phase != "card")
	replica.last_phase = phase
	if fresh:
		replica.live = true
		replica.level = level_now
		replica.world.set_active_level(level_now)
		replica.world.set_clock(float(snap.clock))
		replica.world.set_tile_steps(level_now, StepTiles.join_state(state, int(replica.world.tile_count(level_now))), true)
		replica.tracker.begin(replica.world, level_now)
		replica.last_seq = int(snap.seq)
		replica.applied += 1
		return
	replica.world.correct_clock(float(snap.clock))
	var steps := StepTiles.join_state(state, int(replica.world.tile_count(level_now)))
	replica.world.set_tile_steps(level_now, steps, false)
	if not steps.is_empty() and (replica.tracker.tiles.get("steps") as PackedByteArray) != steps: replica.mismatched_bytes += 1
	replica.applied += 1
	replica.last_seq = int(snap.seq)

func play_level(level: int, players: int) -> void:
	var entry: Dictionary = authority_world._levels[level]
	var origin: Vector3 = authority_world.level_origin(level)
	var tops: Array = []
	for layout: Dictionary in entry.data.tiles.floors: tops.append(float(layout.y) + origin.y)
	var ground_y := float(entry.data.stage.ground.y) + origin.y
	var host := SimHost.new(range(players), seed_value)
	host.world = authority_world
	host.pick = "r%d" % (level + 1)
	var replicas: Array = []
	for index in replica_worlds.size():
		var replica := Replica.new()
		replica.name = "replica%d" % (index + 1)
		replica.world = replica_worlds[index]
		replica.world.set_active_level(-1)
		replicas.append(replica)
	var seq := 0
	for round_number in range(1, rounds + 1):
		var sent := 0
		for replica: Replica in replicas:
			replica.live = false
			replica.last_phase = ""
			replica.applied = 0
			replica.mismatched_bytes = 0
			replica.back_steps = 0
			replica.back_max = 0.0
		(replicas[1] as Replica).joined_at = 12.0 if round_number == 1 else 0.0 # the second replica joins late in the first round
		host.bench([]) # a new show: everybody is in the round again (the shell's lobby does this for a real host)
		var rules := ShowRules.new()
		rules.start(host)
		var walkers: Array = []
		for slot in players:
			var walker := Walker.new()
			walker.slot = slot
			walker.position = host.position(slot)
			walker.rng.seed = seed_value * 100003 + level * 1009 + players * 31 + slot + round_number * 7
			walker.heading = walker.rng.randf() * TAU
			walker.idle_after = INF if slot == 0 else idle_after
			walkers.append(walker)
		var auth := Tracker.new()
		var queue: Array = [] ## snapshots on the way: {arrive, snap, replica}
		var time := 0.0
		var play_time := 0.0
		var tick := 0
		var every := maxi(roundi(60.0 / hz), 1)
		var spiked := false
		var stall_until := -1.0
		var largest := 0
		var oversize := 0
		var tracking := false
		var sample_at := 1.0
		var unix_hash := {}
		while time < 400.0:
			await physics_frame
			time += DT
			tick += 1
			authority_world.advance(DT)
			for walker: Walker in walkers:
				step_walker(walker, rules, authority_world, level, tops, ground_y, play_time)
				host.positions[walker.slot] = walker.position
			rules.tick(DT)
			if rules.phase == "play": play_time += DT
			if not tracking:
				auth.begin(authority_world, level)
				tracking = true
			auth.poll(authority_world.clock, time)
			if tick % every == 0:
				seq += 1
				var snap := snapshot(rules, authority_world, seq, time)
				sent += 1
				for key: Variant in snap.state:
					if snap.state[key] is PackedByteArray:
						largest = maxi(largest, (snap.state[key] as PackedByteArray).size())
						if (snap.state[key] as PackedByteArray).size() > StepTiles.CHUNK: oversize += 1
				for replica: Replica in replicas:
					if replica.joined_at > 0.0 and play_time < replica.joined_at: continue
					if rng.randf() < drop: continue
					var arrive := time + latency + rng.randf_range(-jitter, jitter)
					queue.append({"arrive": arrive, "snap": snap, "replica": replica})
			if spike and not spiked and play_time >= 20.0:
				spiked = true
				stall_until = time + 0.4
			queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.arrive < b.arrive)
			while not queue.is_empty() and float(queue[0].arrive) <= time and (stall_until < 0.0 or time >= stall_until):
				var item: Dictionary = queue.pop_front()
				var target: Replica = item.replica
				if int(item.snap.seq) <= target.last_seq:
					continue # older than what the replica already has
				var before: float = target.world.clock
				var was_live: bool = target.live
				feed(target, item.snap, time, round_number)
				if was_live and target.world.clock < before - 0.0001 and target.last_phase != "card":
					target.back_steps += 1
					target.back_max = maxf(target.back_max, before - target.world.clock)
			for replica: Replica in replicas:
				if not replica.live: continue
				replica.clock_before = replica.world.clock
				replica.world.advance(DT)
				if replica.world.clock < replica.clock_before - 0.0001 and replica.live:
					replica.back_steps += 1
					replica.back_max = maxf(replica.back_max, replica.clock_before - replica.world.clock)
				replica.tracker.poll(replica.world.clock, time)
				if time >= sample_at: replica.tracker.samples.append([replica.world.clock, replica.tracker.bitmap()])
			if time >= sample_at: sample_at += 1.0
			if rules.phase == "done" and rules.phase_time >= 1.5: break
		var length: float = rules._end_at if rules._end_at >= 0.0 else rules.phase_time
		report(level, players, round_number, rules, auth, replicas, length, sent, largest, oversize)

func report(level: int, players: int, round_number: int, rules: Object, auth: Tracker, replicas: Array, length: float, sent: int, largest: int, oversize: int) -> void:
	var tag := "level %d, %d players, round %d" % [level + 1, players, round_number]
	var gone := 0
	for index in auth.count:
		if auth.gone_clock[index] >= 0.0: gone += 1
	check(rules.phase == "done", "%s: the round finished by itself after %.1f s of play (eliminations %d, %d tiles gone)" % [tag, length, rules.fell.size(), gone])
	check(rules.fell.size() >= 1, "%s: somebody fell" % tag)
	check(oversize == 0, "%s: every byte field of the state is at most %d B (largest %d B)" % [tag, StepTiles.CHUNK, largest])
	check(auth.pops == 0, "%s: authority: no tile came back (%d)" % [tag, auth.pops])
	for replica: Replica in replicas:
		var tracker: Tracker = replica.tracker
		var name := "%s %s" % [tag, replica.name]
		var late: bool = replica.joined_at > 0.0 and round_number == 1
		check(tracker.pops == 0 and tracker.unwhite == 0, "%s: no tile came back from gone (%d) and no white tile went solid (%d)%s" % [name, tracker.pops, tracker.unwhite, (", first back [tile, replica clock, time, its gone clock] " + str(tracker.pop_log)) if tracker.pops > 0 else ""])
		if replica.back_steps > 0: print("STAGE_NET_SIM note %s: the replica's level clock went back %d times, by %.0f ms at most (a gone tile with a later gone time than the clock comes back)" % [name, replica.back_steps, replica.back_max * 1000.0])
		check(replica.mismatched_bytes == 0, "%s: the world's step bytes are the state's every time (%d differ)" % [name, replica.mismatched_bytes])
		var low_clock := INF
		var high_clock := -INF
		var delays: Array = []
		var missing := 0
		var first_missing := -1
		var extra := 0
		for index in auth.count:
			var a_clock := float(auth.gone_clock[index])
			var r_clock := float(tracker.gone_clock[index])
			var r_start := (int(tracker.start_gone[index >> 3]) >> (index & 7)) & 1 == 1 ## gone when the replica joined (a late joiner): no event of its own
			if a_clock >= 0.0 and r_clock < 0.0 and not r_start:
				if a_clock < float(replica.world.clock) - 1.0:
					missing += 1
					if first_missing < 0: first_missing = index
			elif a_clock < 0.0 and r_clock >= 0.0: extra += 1
			elif a_clock >= 0.0 and r_clock >= 0.0:
				low_clock = minf(low_clock, r_clock - a_clock)
				high_clock = maxf(high_clock, r_clock - a_clock)
				delays.append((float(tracker.gone_time[index]) - float(auth.gone_time[index])) * 1000.0)
		check(missing == 0 and extra == 0, "%s: the replica lost exactly the tiles the authority lost (missing %d%s, extra %d)" % [name, missing, (": tile %d at authority clock %.2f" % [first_missing, auth.gone_clock[first_missing]]) if missing > 0 else "", extra])
		check(delays.is_empty() or (low_clock >= -TILE_LAG and high_clock <= TILE_LAG), "%s: a tile goes within %.0f ms of the authority's level clock (%.0f..%.0f ms)" % [name, TILE_LAG * 1000.0, low_clock * 1000.0, high_clock * 1000.0])
		delays.sort()
		var lo_delay := float(delays[0]) if not delays.is_empty() else 0.0
		var hi_delay := float(delays[-1]) if not delays.is_empty() else 0.0
		var mean_delay := 0.0
		for value: float in delays: mean_delay += value
		mean_delay = mean_delay / delays.size() if not delays.is_empty() else 0.0
		var low := INF
		var high := -INF
		var total := 0.0
		for gap: float in tracker.intervals:
			low = minf(low, gap)
			high = maxf(high, gap)
			total += gap
		var mean := total / tracker.intervals.size() if not tracker.intervals.is_empty() else 0.0
		# a replica's clock is the authority's: a state that arrives late shows its tile white late and it goes at its time. The earliest a seen-white tile may go: 0.5 s less the
		# link's latency and jitter, three snapshots lost in a row and (with --spike) the stall; any seen-white time is fine after a stall, which may skip the white altogether
		var white_min := maxf(0.5 - latency - jitter - 3.0 / hz - 0.05 - (STALL if spike else 0.0), 0.0)
		check(tracker.intervals.is_empty() or (low >= white_min and high <= WHITE_MAX), "%s: a tile seen white goes %.3f..%.3f s later (bounds %.2f..%.2f, mean %.3f)" % [name, low, high, white_min, WHITE_MAX, mean])
		check(tracker.no_white == 0 or late or spike, "%s: no tile went without being seen white (%d%s)" % [name, tracker.no_white, ", a late joiner's tiles already white when it joined" if late else ""])
		var differing := 0
		var compared := 0
		var first_diff := ""
		for sample: Array in tracker.samples:
			var clock := float(sample[0])
			var seen: Dictionary = tracker.gone_set(sample[1])
			compared += 1
			var best := -1
			for offset in [0.0, -BITMAP_WINDOW * 0.5, BITMAP_WINDOW * 0.5, -BITMAP_WINDOW, BITMAP_WINDOW]:
				var expected := {}
				for index in auth.count:
					if (int(auth.start_gone[index >> 3]) >> (index & 7)) & 1 == 1 or (float(auth.gone_clock[index]) >= 0.0 and float(auth.gone_clock[index]) <= clock + float(offset)): expected[index] = true
				var wrong := 0
				var first_wrong := -1
				for index in seen:
					if not expected.has(index):
						wrong += 1
						if first_wrong < 0: first_wrong = index
				for index in expected:
					if not seen.has(index):
						wrong += 1
						if first_wrong < 0: first_wrong = index
				if best < 0 or wrong < best: best = wrong
				if wrong == 0: break
				if offset == BITMAP_WINDOW and first_diff == "" and first_wrong >= 0: first_diff = "replica clock %.2f tile %d (authority gone at %.2f, replica at %.2f)" % [clock, first_wrong, auth.gone_clock[first_wrong], tracker.gone_clock[first_wrong]]
			if best != 0: differing += 1
		check(compared > 0 and differing == 0, "%s: %d gone bitmaps (once a second) equal the authority's at the same level clock +-%.0f ms (%d differ%s)" % [name, compared, BITMAP_WINDOW * 500.0, differing, (": first " + first_diff) if differing > 0 else ""])
		rows.append("| %d | %d | %d | %.1f | %d | %s%s | %.0f..%.0f ms, real %.0f/%.0f/%.0f | %.3f/%.3f/%.3f | %d/%d | %d/%d | %d | %d |" % [level + 1, players, round_number, length, gone, replica.name, " (late)" if late else "",
			low_clock * 1000.0, high_clock * 1000.0, lo_delay, mean_delay, hi_delay, low if low != INF else 0.0, mean, high if high != -INF else 0.0, differing, compared, replica.applied, sent, tracker.pops + tracker.unwhite, largest])
