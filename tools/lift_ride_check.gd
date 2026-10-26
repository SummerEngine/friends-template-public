extends SceneTree
## Dev check of the lifts of the show levels (files level_14 .. level_31, docs/party-show.md; not shipped). For EVERY `lift` that carries riders (`hit`
## false, rising) a real courier (courier_motion.gd, the physics of a game) is put on its top at its bottom position and the level clock runs
## exactly like the simulation's (advance(dt) first, then the courier steps). The REAL ShowRules `_tick_course` (modes/show/rules.gd) runs every
## tick on a host that answers from the same LevelWorld (zone, scorch, checkpoint_at), so "the rules throw the courier back" is the rules' own
## decision, not a copy of it. Variants of the ride (each starts on a fresh clock at the bottom):
##   "walk"  stands still while the lift rises, then walks onto the landing the route goes to after the lift
##   "dash"  the same, with a dash off the top
##   "jump"  the same, with a jump off the lift's edge (a player who hops across the gap; the jump's apex reaches 1.5+ m over the top)
##   "late"  walks off while the lift is still rising (at 90 % of the rise) and jumps for the landing
## Asserts per variant: the courier is carried up with the lift (feet on the top, inside its footprint), the rules never respawn it (no kill volume, no
## scorch, no goal), and it ends standing on the landing (grounded, within LANDING_RADIUS of the route point, feet at that height).
## A second part checks every checkpoint of the show levels: the respawn spot (host.respawn -> LevelWorld.team_start, what the rules use) of EVERY
## player slot of a 2 to 8 player round stands on a static floor, is in no kill volume, and no moving platform (lift, slide) ever passes through
## the courier there (a respawn on a moving lift is impossible).
## Respawn depends on the courier's POSITION only: the rules read host.position(slot) (zone, scorch, checkpoint_at take that point); the follow
## camera, its yaw and the courier's facing never enter (this tool has no camera, and rules.gd has none).
## Prints LIFT_RIDE lines and `LIFT_RIDE ok=<bool>` last; exit code 1 on any failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh lockf -k /tmp/fs-v086.lock timeout -k 10 300 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --fixed-fps 60 --path demo -s $PWD/tools/lift_ride_check.gd [-- --level=16] [--variant=jump] [--trace]
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const Hazards := preload("res://levels/hazards.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const DT := 1.0 / 60.0
const FIRST := 14 ## the show levels: files level_14 .. level_24 (a level file that does not exist yet is skipped)
const LAST_SHOW_LEVEL := 32
const LANDING_RADIUS := 1.2 ## m: the courier must end this close (XZ) to the landing's route point
const LANDING_HEIGHT := 0.35 ## m: ... with its feet this close to that point's height
const CARRY_SLACK := 0.3 ## m: feet may be this far off the lift's top while riding
const CROSS_SECONDS := 6.0 ## s the courier gets to reach the landing once the lift is up
const SETTLE_TICKS := 12
const VARIANTS := ["walk", "dash", "jump", "late"]

## ModeHost without a shell: positions are set by the check, every question about the level goes to the one LevelWorld.
class LiftHost extends "modes/fake_host.gd":
	var world: Node3D
	var respawned: Array = [] ## [checkpoint, spot, ring positions] of every host.respawn the rules asked for
	func zone(slot: int, level: int) -> String:
		return world.zone_at(level, position(slot))
	func scorch(slot: int, level: int) -> String:
		return world.scorch_at(level, position(slot))
	func checkpoint_at(slot: int, level: int) -> int:
		return world.checkpoint_at(level, position(slot))
	func level_clock() -> float:
		return world.clock
	func respawn(slot: int, level: int, checkpoint: int) -> void:
		var spot: Dictionary = world.team_start(level, count, checkpoint)
		respawned.append({"slot": slot, "checkpoint": checkpoint, "at": spot.pos[slot] if slot < spot.pos.size() else spot.spot})
	func note_scorch(_slot: int, _kind: String) -> void:
		pass

var dir := "res://levels"
var only := 0
var only_variant := ""
var trace := false
var world: Node3D
var failures := 0
var checks := 0
var lifts := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="): only = int(argument.trim_prefix("--level="))
		if argument.begins_with("--variant="): only_variant = argument.trim_prefix("--variant=")
		if argument == "--trace": trace = true
	run.call_deferred()

func say(text: String) -> void:
	print("LIFT_RIDE ", text)

func expect(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		say("FAIL " + text)

func run() -> void:
	world = LevelWorld.new()
	world.level_dir = dir
	root.add_child(world)
	await world.build("authority")
	for number in range(FIRST, LAST_SHOW_LEVEL + 1):
		if only > 0 and number != only: continue
		var k := number - 1
		if k >= world.level_count():
			say("skip level %d: no such level file (the check covers files level_%d .. level_%d)" % [number, FIRST, LAST_SHOW_LEVEL])
			continue
		world.set_active_level(k)
		await physics_frame
		await check_checkpoints(k)
		await check_lifts(k)
		await check_survival(k)
	say("%d lifts ridden" % lifts)
	expect(lifts > 0 or only > 0, "the show levels have lifts to ride")
	say("ok=%s" % str(failures == 0))
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ the survival floor

## Level-local spots with no floor under them (where the ground ring of level 15, the start deck, the goal pad and the arch and billboard feet of level 18 would be):
## a courier put there must fall into the kill volume.
const FORMER_GROUND := {
	15: [[0.0, 0.0, -22.0], [0.0, 0.0, 22.0], [-22.0, 0.0, 0.0], [22.0, 0.0, 0.0], [0.0, 0.0, -17.5], [-16.75, 0.0, 0.0], [16.75, 0.0, 0.0], [-10.5, 0.0, -16.75], [10.5, 0.0, -16.75], [26.0, 0.0, 26.0], [0.0, 0.0, -26.0]],
	18: [[0.0, 0.0, -17.0], [9.0, 0.0, -17.0], [-9.0, 0.0, -17.0], [0.0, 0.0, -14.5], [-8.0, 0.0, -16.5], [8.0, 0.0, -16.5], [0.0, 0.0, 17.0], [2.5, 0.0, 19.0], [0.0, 0.0, 22.0]],
}
const FALL_SECONDS := 3.0 ## s a courier on a FORMER_GROUND spot gets to be in the kill volume
const SPAWN_DROP := 0.45 ## m: a start spot may be this far over / under the tile it lands on (a drop or a step the courier takes in stride)
const GROUND_TIMES := [15.0, 40.0] ## level clocks after which no permanent ground may be left
const GROUND_GRID := 1.0 ## m between the rays of the ground scan
const GROUND_EXTENT := 40.0 ## m: the scan covers +-this around the level's origin
const SPAWN_COUNTS := [1, 2, 3, 4, 6, 8, 10]

## A survival level (docs/party-show.md "Survival"): there is NO permanent safe ground. After GROUND_TIMES seconds of the level clock a vertical ray over a
## grid of the whole play area finds only step tiles or blink tiles (moving bodies), never a static block. The round's
## start ring (team_start, every roster size) stands on tiles at clock 0. A courier put on each FORMER_GROUND spot falls (never grounded) and the REAL
## rules (`_tick_survival`) put it in `fell` within FALL_SECONDS.
func check_survival(k: int) -> void:
	var entry: Dictionary = world._levels[k]
	var data: Dictionary = entry.data
	if str(data.show) != "survival": return
	var origin: Vector3 = world.level_origin(k)
	var label := "level %d '%s' survival" % [k + 1, world.title(k)]
	var tile_bodies: Array = (entry.tiles.tile_bodies as Array) if entry.has("tiles") else []
	var arena := bool(data.arena) # an arena (`"arena": true`, KEEP THE LOGO) has a floor that stays: only its start ring is checked
	# 1. no permanent ground
	world.set_tile_steps(k, world.tile_start(k, 8))
	var space := world.get_world_3d().direct_space_state
	for at_clock: float in ([] if arena else GROUND_TIMES):
		world.set_clock(at_clock)
		await physics_frame
		await physics_frame
		var permanent: Array[String] = []
		var tiles_standing := 0
		var movers_standing := 0
		var x := -GROUND_EXTENT
		while x <= GROUND_EXTENT:
			var z := -GROUND_EXTENT
			while z <= GROUND_EXTENT:
				var skip: Array[RID] = []
				for guard in 12:
					var query := PhysicsRayQueryParameters3D.create(origin + Vector3(x, 60.0, z), origin + Vector3(x, -60.0, z), 0xFFFFFFFF, skip)
					var hit := space.intersect_ray(query)
					if hit.is_empty(): break
					var collider := hit.collider as CollisionObject3D
					skip.append(collider.get_rid())
					if collider is AnimatableBody3D: movers_standing += 1
					elif tile_bodies.has(collider): tiles_standing += 1
					elif entry.has("tiles") and collider == entry.tiles.ground: pass # a stage round's ground under its last layer: whoever lands on it is out (stage.ground)
					else: permanent.append("%s at level-local %s" % [collider.name, ((hit.position as Vector3) - origin).snapped(Vector3.ONE * 0.01)])
				z += GROUND_GRID
			x += GROUND_GRID
		var shown := permanent.slice(0, 5)
		expect(permanent.is_empty(), "%s: at level clock %.0f s %d ray hits are PERMANENT ground (not a tile): %s" % [label, at_clock, permanent.size(), "; ".join(shown)])
		if permanent.is_empty(): say("ok   %s: clock %.0f s: nothing static left to stand on (%d tile hits, %d mover hits over %.0f m x %.0f m)" % [label, at_clock, tiles_standing, movers_standing, GROUND_EXTENT * 2.0, GROUND_EXTENT * 2.0])
	# 2. the start ring stands on tiles
	var before := failures
	for count: int in SPAWN_COUNTS:
		world.set_tile_steps(k, world.tile_start(k, count))
		world.set_clock(0.0)
		await physics_frame
		await physics_frame
		var ring: Dictionary = world.team_start(k, maxi(count, 2)) # the shell's start ring (game_run.gd _spawn_points): at least two places
		var off := ""
		for at: Vector3 in ring.pos:
			var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.5, 0.0), at - Vector3(0.0, 0.6, 0.0), 0xFFFFFFFF)
			var hit := space.intersect_ray(query)
			var collider := hit.collider as CollisionObject3D if not hit.is_empty() else null
			if collider == null or not (arena or collider is AnimatableBody3D or tile_bodies.has(collider)) or absf((hit.position as Vector3).y - at.y) > SPAWN_DROP:
				off += " %s" % [(at - origin).snapped(Vector3.ONE * 0.01)]
		expect(off == "", "%s: with %d players the start spots are not on a standing tile at clock 0:%s" % [label, count, off])
	if failures == before: say("ok   %s: the start ring of %s players stands on tiles at clock 0" % [label, SPAWN_COUNTS])
	world.set_tile_steps(k, world.tile_start(k, 2))
	world.set_clock(0.0)
	# 3. no ground at the FORMER_GROUND spots: a courier there falls, and the rules put it out
	for spot: Array in FORMER_GROUND.get(k + 1, []):
		await fall_from(k, label, Vector3(spot[0], spot[1], spot[2]))

func fall_from(k: int, label: String, spot: Vector3) -> void:
	var origin: Vector3 = world.level_origin(k)
	var host := LiftHost.new([0], 1)
	host.world = world
	var rules := ShowRules.new()
	rules.host = host
	rules.kind = "survival"
	rules.level = k
	rules.phase = "play"
	rules.field = [0]
	rules.status = [0]
	rules._send_at = [-1.0]
	rules._grace = [0.0]
	rules._deadline = 1000.0
	rules.need = 1
	world.set_clock(20.0)
	await physics_frame
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, origin + spot + Vector3(0.0, 0.05, 0.0), 0.0)
	var grounded_ticks := 0
	var fell_at := -1.0
	var lowest := 0.0
	for tick in int(FALL_SECONDS / DT):
		await physics_frame
		world.advance(DT)
		motion.step(body, {}, DT)
		if motion.grounded: grounded_ticks += 1
		host.positions[0] = body.global_position
		lowest = minf(lowest, body.global_position.y - origin.y)
		rules._tick_survival()
		if rules.fell.has(0):
			fell_at = float(tick) * DT
			break
	var where := "level-local %s" % [spot]
	expect(grounded_ticks == 0, "%s: a courier at the former ground spot %s stood on something (%d grounded ticks)" % [label, where, grounded_ticks])
	expect(fell_at >= 0.0, "%s: a courier at the former ground spot %s was not put out within %.0f s (lowest feet y %.1f, kill: %s)" % [label, where, FALL_SECONDS, lowest, kill_zones(k, body.global_position)])
	if grounded_ticks == 0 and fell_at >= 0.0: say("ok   %s: a courier at former ground %s falls and is out after %.2f s" % [label, where, fell_at])
	body.queue_free()
	await physics_frame
	world.set_clock(0.0)

# ------------------------------------------------------------------ the lifts

## Movers of kind lift that carry riders: no `hit`, rising.
func rider_lifts(k: int) -> Array:
	var result: Array = []
	var entry: Dictionary = world._levels[k]
	for index in entry.movers.size():
		var h: Dictionary = entry.movers[index].h
		if h.k == "lift" and not bool(h.hit) and float((h.to as Vector3).y) > 0.0: result.append(index)
	return result

## The top face of the lift (its biggest box part), in the lift's own frame: {top (local point), half (Vector2), size_y}.
func top_face(mover: Dictionary) -> Dictionary:
	var best := {}
	for block: Dictionary in mover.h.parts:
		if block.k != "box": continue
		var size: Vector3 = block.size
		var area := size.x * size.z
		if best.is_empty() or area > float(best.area):
			best = {"top": (block.xf as Transform3D).origin + Vector3(0.0, size.y * 0.5, 0.0), "half": Vector2(size.x, size.z) * 0.5, "area": area}
	return best

## The landing the route serves after the lift: the first route point after the one nearest the lift's bottom that lies outside the lift's footprint
## and at the height of its top (level-local). Vector3.INF when the route has none.
func landing(k: int, mover: Dictionary, face: Dictionary) -> Vector3:
	var h: Dictionary = mover.h
	var path: PackedVector3Array = world._levels[k].data.path
	var bottom: Vector3 = (h.pivot as Vector3) + (face.top as Vector3)
	var top: Vector3 = bottom + (h.to as Vector3)
	var from := 0
	var gap := INF
	for index in path.size():
		var d := Vector2(path[index].x - bottom.x, path[index].z - bottom.z).length()
		if absf(path[index].y - bottom.y) < 1.5 and d < gap:
			gap = d
			from = index
	for index in range(from + 1, path.size()):
		var point: Vector3 = path[index]
		var outside := absf(point.x - top.x) > (face.half as Vector2).x + 0.3 or absf(point.z - top.z) > (face.half as Vector2).y + 0.3
		if outside and absf(point.y - top.y) < 0.75: return point
	return Vector3.INF

func check_lifts(k: int) -> void:
	for index in rider_lifts(k):
		for variant: String in VARIANTS:
			if only_variant != "" and variant != only_variant: continue
			await ride(k, index, variant)
		lifts += 1

## One ride of one variant; prints a LIFT_RIDE line.
func ride(k: int, index: int, variant: String) -> void:
	var entry: Dictionary = world._levels[k]
	var mover: Dictionary = entry.movers[index]
	var h: Dictionary = mover.h
	var origin: Vector3 = world.level_origin(k)
	var label := "level %d '%s' %s '%s' %s" % [k + 1, world.title(k), h.k, h.id, variant]
	var face := top_face(mover)
	var target := landing(k, mover, face)
	if face.is_empty() or target == Vector3.INF:
		expect(false, "%s: no top face or no landing on the route after the lift" % label)
		return
	var half: Vector2 = face.half
	var host := LiftHost.new([0], 1)
	host.world = world
	var rules := ShowRules.new()
	rules.host = host
	rules.kind = "race"
	rules.level = k
	rules.phase = "play"
	rules.field = [0]
	rules.status = [0]
	rules.pts = [0]
	rules._progress = [0.0]
	rules._checkpoint = [-1]
	rules._grace = [0.0]
	rules._send_at = [-1.0]
	rules._deadline = 1000.0
	rules.need = 1
	# the lift at its bottom (cycle phase 0): the clock that gives tau = 0
	var start_t := fposmod(-float(h.phase), float(h.period))
	world.set_clock(start_t)
	await physics_frame
	var pose: Hazards.Pose = mover.pose
	var spot: Vector3 = origin + pose.position + (face.top as Vector3)
	var body := Motion.make_body("Courier")
	world.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.reset(body, spot + Vector3(0.0, 0.02, 0.0), 0.0)
	var failure := ""
	for settle in SETTLE_TICKS:
		await physics_frame
		motion.step(body, {}, DT)
	var tau0: float = world.clock + float(h.phase)
	var cross_started := -1.0
	var jumped := false
	var dashed := false
	var arrived := false
	var top_y := spot.y + float((h.to as Vector3).y)
	var highest := body.global_position.y
	var worst_carry := 0.0
	var ticks := int(ceil((float(h.period) + CROSS_SECONDS) / DT))
	for tick in ticks:
		await physics_frame
		world.advance(DT)
		var tau: float = world.clock + float(h.phase)
		var f: float = Hazards.cycle(tau, h.period, h.pause, h.ease, float(h.get("hold", -1.0)))
		var lift_top: Vector3 = origin + pose.position + (face.top as Vector3)
		var at := body.global_position
		var input := {}
		var rise_done: bool = f >= 0.999 and tau - tau0 < float(h.period) * 0.5 + 1.0
		var leave: bool = cross_started >= 0.0 or rise_done or (variant == "late" and f >= 0.9 and tau - tau0 < float(h.period) * 0.5)
		if leave:
			if cross_started < 0.0: cross_started = world.clock
			var to := Vector2(origin.x + target.x - at.x, origin.z + target.z - at.z)
			input["move"] = to.normalized() if to.length() > 0.25 else Vector2.ZERO
			var edge := maxf(absf(at.x - lift_top.x) - half.x, absf(at.z - lift_top.z) - half.y) # < 0 inside the footprint
			if variant == "dash" and not dashed:
				input["dash"] = true
				dashed = true
			if (variant == "jump" or variant == "late") and not jumped and motion.grounded and edge > -0.7:
				input["jump"] = true
				jumped = true
		elif variant == "late" or variant == "walk" or variant == "dash" or variant == "jump":
			# riding: nothing pressed; the lift must carry the courier
			var inside := absf(at.x - lift_top.x) <= half.x + 0.1 and absf(at.z - lift_top.z) <= half.y + 0.1
			var off := absf(at.y - lift_top.y)
			worst_carry = maxf(worst_carry, off)
			if f > 0.02 and (not inside or off > CARRY_SLACK):
				failure = "not carried at t=%.2f: courier %s, lift top %s (inside=%s, off by %.2f m)" % [world.clock, (at - origin).snapped(Vector3.ONE * 0.01), (lift_top - origin).snapped(Vector3.ONE * 0.01), str(inside), off]
				break
		motion.step(body, input, DT)
		at = body.global_position
		highest = maxf(highest, at.y)
		host.positions[0] = at
		var before := host.respawned.size()
		rules._tick_course()
		if trace and tick % 20 == 0: say("trace t=%.2f f=%.2f courier %s zone '%s' checkpoint %d grounded %s" % [world.clock, f, (at - origin).snapped(Vector3.ONE * 0.01), world.zone_at(k, at), world.checkpoint_at(k, at), str(motion.grounded)])
		if host.respawned.size() > before or rules.across.size() > 0 or rules.phase != "play":
			var zones := kill_zones(k, at)
			failure = "the rules sent the courier back at t=%.2f (lift f=%.2f, %s): courier at level-local %s, respawn at checkpoint %d%s%s" % [world.clock, f, "airborne" if not motion.grounded else "grounded",
				(at - origin).snapped(Vector3.ONE * 0.01), int(host.respawned[before].checkpoint) if host.respawned.size() > before else -2, zones, " scorch '%s'" % world.scorch_at(k, at) if world.scorch_at(k, at) != "" else ""]
			break
		if cross_started >= 0.0 and motion.grounded:
			var flat := Vector2(at.x - (origin.x + target.x), at.z - (origin.z + target.z)).length()
			var support: float = world.floor_y(k, at) # the landing is STATIC ground: still on the lift's edge does not count
			if flat <= LANDING_RADIUS and absf(at.y - (origin.y + target.y)) <= LANDING_HEIGHT and not is_nan(support) and absf(support - at.y) < 0.1:
				arrived = true
				break
		if cross_started >= 0.0 and world.clock - cross_started > CROSS_SECONDS: break
	if failure == "" and highest < top_y - CARRY_SLACK: failure = "the lift did not carry the courier up (highest feet %.2f, top %.2f)" % [highest - origin.y, top_y - origin.y]
	if failure == "" and not arrived:
		var at := body.global_position
		failure = "did not reach the landing %s (level-local) within %.0f s: courier at %s grounded=%s" % [target.snapped(Vector3.ONE * 0.01), CROSS_SECONDS, (at - origin).snapped(Vector3.ONE * 0.01), str(motion.grounded)]
	expect(failure == "", "%s: %s" % [label, failure])
	if failure == "": say("ok   %s: carried %.1f m (worst %.2f m off the top), landed at level-local %s, never sent back" % [label, float((h.to as Vector3).y), worst_carry, (body.global_position - origin).snapped(Vector3.ONE * 0.01)])
	body.queue_free()
	await physics_frame
	world.set_clock(0.0)

## Which kill volumes of the level hold a courier standing with its feet at this world point.
func kill_zones(k: int, feet: Vector3) -> String:
	var entry: Dictionary = world._levels[k]
	var local: Vector3 = feet - world.level_origin(k) + Vector3(0.0, LevelWorld.CENTRE_HEIGHT, 0.0)
	var text := ""
	if local.y < float(entry.data.void_y): text += " below void_y %.1f" % float(entry.data.void_y)
	for index in entry.data.kill.size():
		var volume: Dictionary = entry.data.kill[index]
		if LevelWorld.Data.inside(volume, local):
			text += " in kill[%d] (centre %s size %s)" % [index, ((volume.xf as Transform3D).origin).snapped(Vector3.ONE * 0.01), (volume.half as Vector3) * 2.0]
	return text

# ------------------------------------------------------------------ the checkpoints

## Every checkpoint of a show level: where each slot of a 1 to 8 player round restarts (LevelWorld.team_start, what ModeHost.respawn uses) is on a static
## floor, in no kill volume, outside every scorcher and never inside the path of a moving platform.
func check_checkpoints(k: int) -> void:
	var entry: Dictionary = world._levels[k]
	var origin: Vector3 = world.level_origin(k)
	var list: Array = entry.data.checkpoints
	var label := "level %d '%s'" % [k + 1, world.title(k)]
	if str(entry.data.show) == "survival":
		say("note %s is a survival level: nobody respawns (a fall is out), the start ring is checked with the survival floor" % label)
		return
	var notes := {} ## hit hazards (sweepers, hammers) that pass over a respawn spot: they knock the player, never kill: reported, not failed
	for checkpoint in range(-1, list.size()):
		for count in [1, 2, 4, 8]:
			var spot: Dictionary = world.team_start(k, count, checkpoint)
			var bad := ""
			for at: Vector3 in spot.pos:
				var floor_at: float = world.floor_y(k, at)
				if is_nan(floor_at) or absf(floor_at - at.y) > 0.1: bad += " no static floor under %s (floor %s)" % [(at - origin).snapped(Vector3.ONE * 0.01), str(floor_at)]
				if world.zone_at(k, at + Vector3(0.0, 0.05, 0.0)) == "kill": bad += " %s is in a kill volume:%s" % [(at - origin).snapped(Vector3.ONE * 0.01), kill_zones(k, at + Vector3(0.0, 0.05, 0.0))]
				if world.scorch_at(k, at) != "": bad += " %s is in a scorcher" % (at - origin).snapped(Vector3.ONE * 0.01)
				bad += mover_through(k, at, false)
				var bonk := mover_through(k, at, true)
				if bonk != "": notes[bonk] = true
			expect(bad == "", "%s checkpoint %d for %d players: respawn spots are not safe:%s" % [label, checkpoint, count, bad])
	if list.is_empty(): say("note %s has no checkpoints (a fall restarts at the start)" % label)
	else: say("ok   %s: %d checkpoints, respawn spots on static floor, outside kill volumes and moving platforms" % [label, list.size()])
	for text: String in notes: say("note %s: a respawn spot is on the path of a hazard that knocks back:%s" % [label, text])

## "" or text: a moving platform (lift, slide, spin, swing) of the level that passes through the volume of a courier standing at `feet` (world) at any
## sampled clock of its cycle; `harmful` false looks at the platforms that carry riders (no `hit`), true at the ones that knock (`hit`).
func mover_through(k: int, feet: Vector3, harmful: bool) -> String:
	var entry: Dictionary = world._levels[k]
	var origin: Vector3 = world.level_origin(k)
	var text := ""
	for mover: Dictionary in entry.movers:
		var h: Dictionary = mover.h
		if not h.k in ["lift", "slide", "spin", "swing"] or bool(h.hit) != harmful: continue
		var length := maxf(float(h.period), 1.0) if h.k in ["lift", "slide", "swing"] else 360.0 / maxf(absf(float(h.rate)), 1.0)
		for step in int(ceil(length / 0.25)):
			var tau := float(step) * 0.25 - float(h.phase)
			var pose := Hazards.Pose.new()
			Hazards.pose(h, tau, pose)
			var frame := Transform3D(pose.basis, pose.position + origin).affine_inverse()
			var hit := false
			for part: Dictionary in h.parts:
				if part.k != "box": continue
				var half: Vector3 = (part.size as Vector3) * 0.5 + Vector3(0.4, 0.0, 0.4)
				var xf: Transform3D = part.xf
				for lift in [0.0, 0.9, 1.7]:
					var local: Vector3 = (xf.affine_inverse() * (frame * (feet + Vector3(0.0, lift, 0.0))))
					if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z: hit = true
			if hit:
				text += " the %s '%s' passes through it (clock %.2f)" % [h.k, h.id, float(step) * 0.25]
				break
	return text
