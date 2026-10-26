extends SceneTree
## Crossing probe of the hurting spinners of the race levels (29-32): a cluster of fling spinners (spinner discs, windmills, wheels whose sweep reaches the course's route, merged
## when they lie within CLUSTER_GAP m of route progress of each other) must be passable on foot, and must still be an obstacle.
##
## A scripted courier (real courier physics, the real level world: bonk, fling, belts) walks the route from START_BEFORE m before the cluster to END_AFTER m behind it at the walking
## speed, steering to a point LOOKAHEAD m ahead on the route and jumping where the floor ahead ends or steps up. Two kinds of walker, each set off at every start of one full cycle of
## the cluster (the level clock at the start, CYCLE s):
##   steady    never waits and never dodges: walks straight through at a steady pace (every `--step` s of start time, 0.2 s by default),
##   careful   looks HORIZON s ahead at where the arms will be (the exact poses of the level clock) and walks on only when its next steps along the route are clear; otherwise it stands
##             and waits (when standing is clear for the next STAY_HORIZON s). Set off every CAREFUL_STEP s.
## A walk passes when the courier arrives on the far side without a bonk. The cluster is
##   passable    when the steady walk gets through from a run of start times at least MIN_WINDOW s wide (wait for the moment, then walk), or, where it does not, when the careful walker
##               (it only waits where it is safe to) arrives from at least CAREFUL_MIN of its starts, and
##   an obstacle when at least MIN_FLUNG of the steady walk's starts are flung (a careless run usually is).
## Prints SPIN_PASS lines (one per cluster: the starts as a string, P pass, . flung, f fell, t timed out) and `SPIN_PASS ok=<bool>`; exit code 1 on a failure. Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo -s $PWD/tools/spinner_pass_check.gd \
##     [-- --levels=29,30,31,32] [--only=disc_a,wind_a1] [--step=0.2] [--quick] [--start=<clock s>] [--trace]
const LevelWorld := preload("res://levels/level_world.gd")
const Hazards := preload("res://levels/hazards.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const CLUSTER_GAP := 8.0       ## m of route progress: spinners closer than this share a crossing
const START_BEFORE := 5.0      ## m of route before the first spinner's reach where the courier starts
const END_AFTER := 2.5         ## m behind the last one where it counts as across (the route may leave the floor soon after: a jump)
const LOOKAHEAD := 1.5         ## m
const REACH_GROW := 0.5        ## m: a courier's body and the arms' thickness round a sweep
const CAREFUL_STEP := 0.5      ## s between the starts of the careful walker (`--quick`: 1.0)
const CAREFUL_MIN := 0.9       ## fraction of the careful starts that must arrive
const HORIZON := 1.2           ## s the careful walker looks ahead along the route
const STAY_HORIZON := 0.4      ## s it needs standing still to be clear
const PLAN_SPEEDS := [4.0, 5.0]     ## m/s along the route it assumes while looking ahead (the walk is 5, the start, jumps and corners cost some): clear at all of them
const PLAN_MARGIN := 0.1       ## m added round the arms when looking ahead (the courier's radius and the bonk reach are in already)
const MIN_WINDOW := 0.6       ## s: the widest run of start times at which the steady walk gets through (a player who waits and then walks at a steady pace: +-0.3 s of slack)
const MIN_FLUNG := 0.3         ## fraction of the starts that must be flung for the cluster to count as an obstacle
const CYCLE := 24.0            ## s: one cycle of every rate in use (105 and 120 deg/s: 24 s; 60, 75, 90, 135 divide it as well)
const STOP_NEAR := 1.2         ## m from the cluster's end sample (horizontal) that counts as arrived
const LEVELS := [29, 30, 31, 32]

var levels: Array = LEVELS
var only: PackedStringArray = []
var step_s := 0.2
var careful_step := CAREFUL_STEP
var trace := false
var only_start := -1.0
var skip_careful := false
var skip_careless := false
var world: Node3D
var holder: Node3D
var fails := 0
var checked := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="):
			levels = []
			for part in argument.trim_prefix("--levels=").split(","): levels.append(int(part))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--step="): step_s = float(argument.trim_prefix("--step="))
		if argument.begins_with("--start="): only_start = float(argument.trim_prefix("--start="))
		if argument == "--quick":
			step_s = 0.4
			careful_step = 1.0
		if argument == "--careless-only": skip_careful = true
		if argument == "--careful-only": skip_careless = true
		if argument == "--trace": trace = true
	run.call_deferred()

func say(text: String) -> void:
	print("SPIN_PASS ", text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("authority")
	for number: int in levels:
		var k := number - 1
		if k >= world.level_count(): continue
		world.set_active_level(k)
		await physics_frame
		await check_level(number, k)
	if checked == 0:
		fails += 1
		say("FAIL no cluster was checked")
	say("ok=%s clusters=%d" % [fails == 0, checked])
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

## The radius of everything a spin hazard sweeps about its axis (m).
func reach_of(h: Dictionary) -> float:
	var axis := _axis(h)
	var best := 0.0
	for part: Dictionary in h.parts:
		var xf: Transform3D = part.xf
		var size: Vector3 = part.size
		if part.k == "cyl": size = Vector3(float(part.d), float(part.h), float(part.d))
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner: Vector3 = xf * (Vector3(sx, sy, sz) * size * 0.5)
					corner -= axis * corner.dot(axis)
					best = maxf(best, corner.length())
	return best

func _axis(h: Dictionary) -> Vector3:
	var local := Vector3.RIGHT if h.axis == "x" else (Vector3.BACK if h.axis == "z" else Vector3.UP)
	return ((h.base as Basis) * local).normalized()

## Does the courier standing at level-local `feet` stand in the sweep of the hazard (the disc of its reach in its plane, a slab as thick as the bars)?
func in_sweep(h: Dictionary, reach: float, feet: Vector3) -> bool:
	var axis := _axis(h)
	var d := feet + Vector3(0.0, LevelWorld.CENTRE_HEIGHT, 0.0) - (h.pivot as Vector3)
	var along := d.dot(axis)
	var across := (d - axis * along).length()
	var slab := 1.4 if h.axis == "y" else 1.2
	return across <= reach + REACH_GROW and absf(along) <= slab

func check_level(number: int, k: int) -> void:
	var data: Dictionary = world._levels[k].data
	var route: PackedVector3Array = data.route
	if route.size() < 2: return
	var lengths := LevelWorld._cumulative(route)
	# dense samples of the route, exactly every 0.5 m of route progress: [progress, point]
	var dense: Array = []
	var total: float = lengths[route.size() - 1]
	var segment := 1
	var progress := 0.0
	while progress <= total:
		while segment < route.size() - 1 and lengths[segment] < progress: segment += 1
		var span: float = lengths[segment] - lengths[segment - 1]
		var t := 0.0 if span <= 0.0 else clampf((progress - lengths[segment - 1]) / span, 0.0, 1.0)
		dense.append([progress, route[segment - 1].lerp(route[segment], t)])
		progress += 0.5
	# every hurting spinner's stretch of the route
	var spans: Array = []
	for h: Dictionary in data.hazards:
		if h.k != "spin" or not h.hit: continue
		var reach := reach_of(h)
		var lo := INF
		var hi := -INF
		for sample: Array in dense:
			if in_sweep(h, reach, sample[1]):
				lo = minf(lo, sample[0])
				hi = maxf(hi, sample[0])
		if hi < lo: continue
		spans.append({"id": str(h.id), "lo": lo, "hi": hi})
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.lo < b.lo)
	var clusters: Array = []
	for span: Dictionary in spans:
		if not clusters.is_empty() and span.lo - float(clusters[-1].hi) < CLUSTER_GAP:
			clusters[-1].hi = maxf(clusters[-1].hi, span.hi)
			clusters[-1].ids.append(span.id)
		else:
			clusters.append({"lo": span.lo, "hi": span.hi, "ids": [span.id]})
	for cluster: Dictionary in clusters:
		if not only.is_empty() and not (cluster.ids as Array).any(func(id: String) -> bool: return only.has(id)): continue
		var seg: Array = []
		for sample: Array in dense:
			if sample[0] >= float(cluster.lo) - START_BEFORE and sample[0] <= float(cluster.hi) + END_AFTER: seg.append(sample[1])
		# the walk starts on ground that stands still (not on a turning floor that would carry the courier off the route), at least RUN_UP m before the first arm
		var origin: Vector3 = world.level_origin(k)
		var first_ok := 0
		for i in seg.size():
			var ray := PhysicsRayQueryParameters3D.create(origin + seg[i] + Vector3(0.0, 0.6, 0.0), origin + seg[i] - Vector3(0.0, 0.8, 0.0), LevelWorld.LAYER_MOVER)
			if world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): break
			first_ok = i + 1
		if first_ok > 0 and first_ok < seg.size() - 4: seg = seg.slice(first_ok)
		if seg.size() < 3: continue
		await check_cluster(number, k, cluster, seg, data)

func check_cluster(number: int, k: int, cluster: Dictionary, seg: Array, data: Dictionary) -> void:
	var movers: Array = []
	for h: Dictionary in data.hazards:
		if h.k == "spin" and h.hit and (cluster.ids as Array).has(str(h.id)): movers.append(h)
	# the careless walker: every start of the cycle
	var starts := int(CYCLE / step_s)
	var line := ""
	var flung := 0
	var passed := 0
	for i in starts:
		if skip_careless or (only_start >= 0.0 and absf(float(i) * step_s - only_start) > 0.01): continue
		var outcome := await walk(k, seg, float(i) * step_s, [])
		line += outcome
		if outcome == "P": passed += 1
		elif outcome == ".": flung += 1
	var flung_frac := float(flung) / float(maxi(line.length(), 1))
	# the widest run of passing starts (the cycle wraps round)
	var window := 0
	var run_len := 0
	for c in (line + line):
		if c == "P":
			run_len += 1
			window = maxi(window, run_len)
		else:
			run_len = 0
	window = mini(window, line.length())
	var window_s := float(window) * step_s
	# the careful walker, when the steady walk has no wide enough window
	var careful_line := ""
	var careful_passed := 0
	var careful_frac := 0.0
	if window_s < MIN_WINDOW and not skip_careful and only_start < 0.0:
		var careful_starts := int(CYCLE / careful_step)
		for i in careful_starts:
			var outcome := await walk(k, seg, float(i) * careful_step, movers)
			careful_line += outcome
			if outcome == "P": careful_passed += 1
		careful_frac = float(careful_passed) / float(careful_starts)
	var passable := window_s >= MIN_WINDOW or careful_frac >= CAREFUL_MIN
	var ok := passable and flung_frac >= MIN_FLUNG
	checked += 1
	if not ok: fails += 1
	var ids: Array = cluster.ids
	say("%s L%d [%s] route %.0f..%.0f m: steady walk passes %d of %d starts, widest window %.1f s (need %.1f s), flung %.0f%% (need >= %.0f%%)%s" % [
		"ok  " if ok else "FAIL", number, ", ".join(PackedStringArray(ids)), float(cluster.lo), float(cluster.hi), passed, line.length(), window_s, MIN_WINDOW, 100.0 * flung_frac,
		100.0 * MIN_FLUNG, "" if careful_line == "" else "; careful (waits) arrives from %d of %d starts (need %.0f%%)" % [careful_passed, careful_line.length(), 100.0 * CAREFUL_MIN]])
	say("     steady  %s" % line)
	if careful_line != "": say("     careful %s" % careful_line)

## Is the courier at level-local `feet` (a capsule of the courier's size, grown by the bonk's reach and PLAN_MARGIN) inside an arm of one of `movers` at level clock `t`?
func struck(movers: Array, feet: Vector3, t: float) -> bool:
	var pose := Hazards.Pose.new()
	var grow := LevelWorld.COURIER_RADIUS + LevelWorld.BONK_REACH + PLAN_MARGIN
	for h: Dictionary in movers:
		Hazards.pose(h, t, pose)
		var inverse := Transform3D(pose.basis, pose.position).affine_inverse()
		for part: Dictionary in h.parts:
			if part.k != "box": continue
			var half: Vector3 = (part.size as Vector3) * 0.5 + Vector3.ONE * grow
			var to_part: Transform3D = (part.xf as Transform3D).affine_inverse() * inverse
			for step in 5:
				var point := feet + Vector3(0.0, 0.35 + 0.275 * float(step), 0.0)
				var local: Vector3 = to_part * point
				if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z: return true
	return false

## A point `distance` m further along `seg` than sample `index` (samples 0.5 m apart).
func ahead_on(seg: Array, index: int, distance: float) -> Vector3:
	var at := float(index) + distance / 0.5
	var low := mini(int(floor(at)), seg.size() - 1)
	var high := mini(low + 1, seg.size() - 1)
	return (seg[low] as Vector3).lerp(seg[high], at - floor(at))

## One walk of `seg` (level-local route samples) setting off at level clock `t0`. `movers` empty: the careless walker, else the careful one. Returns "P" (arrived), "." (bonked),
## "f" (fell), "t" (timed out).
func walk(k: int, seg: Array, t0: float, movers: Array) -> String:
	var origin: Vector3 = world.level_origin(k)
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	var first: Vector3 = seg[0]
	var yaw := atan2(-(seg[1].x - first.x), -(seg[1].z - first.z))
	motion.reset(body, origin + first + Vector3(0.0, 0.05, 0.0), yaw)
	world.set_clock(t0)
	world.reset_effects()
	for i in 8:
		await physics_frame
		motion.step(body, {}, DT)
	motion.reset(body, origin + first + Vector3(0.0, 0.05, 0.0), yaw)
	world.set_clock(t0)
	world.reset_effects()
	var length := 0.0
	for i in range(1, seg.size()): length += (seg[i] as Vector3).distance_to(seg[i - 1])
	var careful := not movers.is_empty()
	var ticks := int(((length / 3.0 + 8.0) + (30.0 if careful else 0.0)) / DT)
	var index := 0
	var low := INF
	for p: Vector3 in seg: low = minf(low, p.y)
	var result := "t"
	var last: Vector3 = seg[seg.size() - 1]
	for tick in ticks:
		world.advance(DT)
		var effect: Dictionary = world.apply_effects(k, 0, body, motion)
		if not effect.is_empty() and str(effect.get("kind", "")) == "bonk":
			result = "."
			if trace: print("  bonk at t=%.2f feet %s seg index %d of %d" % [world.clock, (body.global_position - origin).snapped(Vector3.ONE * 0.1), index, seg.size()])
			break
		var feet := body.global_position - origin
		if feet.y < low - 8.0:
			result = "f"
			break
		# the route sample the courier is nearest to, never back
		var near := index
		var near_d := INF
		for j in range(index, mini(index + 8, seg.size())):
			var d := Vector2(feet.x - seg[j].x, feet.z - seg[j].z).length()
			if d < near_d:
				near_d = d
				near = j
		index = near
		if index >= seg.size() - 2 and Vector2(feet.x - last.x, feet.z - last.z).length() < STOP_NEAR:
			result = "P"
			break
		var target: Vector3 = seg[mini(index + int(LOOKAHEAD / 0.5), seg.size() - 1)]
		var move := Vector2(target.x - feet.x, target.z - feet.z)
		var jump := false
		var wait := false
		if careful and motion.grounded:
			var blocked := false
			for speed: float in PLAN_SPEEDS:
				var dist := 0.0
				for s in int(HORIZON / 0.1) + 1:
					var tau := 0.1 * float(s)
					var spot := ahead_on(seg, index, dist)
					if struck(movers, spot, world.clock + tau):
						blocked = true
						if trace and tick % 30 == 0: print("  blocked: speed %.0f tau %.1f at %s (index %d of %d)" % [speed, tau, spot.snapped(Vector3.ONE * 0.1), index, seg.size()])
						break
					# a belt under the route changes the pace
					var heading := ahead_on(seg, index, dist + 0.5) - spot
					var belt: Vector2 = world.surface_at(k, origin + spot).get("belt", Vector2.ZERO)
					var along := Vector2(heading.x, heading.z).normalized().dot(belt) if Vector2(heading.x, heading.z).length() > 0.01 else 0.0
					dist += maxf(speed + along, 0.5) * 0.1
				if blocked: break
			if blocked:
				wait = true
				for s in int(STAY_HORIZON / 0.1) + 1:
					if struck(movers, feet, world.clock + 0.1 * float(s)):
						wait = false
						break
		if wait:
			# standing still on a belt means walking against it
			var carried: Vector2 = world.surface_at(k, body.global_position).get("belt", Vector2.ZERO)
			move = (-carried / Motion.WALK_SPEED).limit_length(1.0)
		elif move.length() > 0.15:
			move = move.normalized()
			if motion.grounded:
				var gap := true       # no floor 0.45 m ahead and none 0.95 m ahead either: a gap too wide to step over
				for reach: float in [0.45, 0.95]:
					var ahead: Vector3 = body.global_position + Vector3(move.x, 0.0, move.y) * reach + Vector3(0.0, 0.3, 0.0)
					var ray := PhysicsRayQueryParameters3D.create(ahead, ahead - Vector3(0.0, 0.9, 0.0), LevelWorld.LAYER_SOLID | LevelWorld.LAYER_MOVER)
					if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): gap = false
				var ahead_d := Vector2(target.x - feet.x, target.z - feet.z).length()
				var rises: bool = target.y > feet.y + 0.3 + 0.4 * ahead_d and ahead_d < 2.5     # a step up, not a ramp (the ramps of level 31 climb 0.35 m per m)
				jump = gap or rises
		else:
			move = Vector2.ZERO
		motion.step(body, {"move": move, "jump": jump}, DT)
		if trace and tick % 12 == 0: print("  t=%.2f feet %s %s" % [world.clock, feet.snapped(Vector3.ONE * 0.1), "wait" if wait else ""])
		await physics_frame
	body.queue_free()
	await physics_frame
	return result
