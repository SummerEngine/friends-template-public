extends SceneTree
## Dev check of the bonk (levels/level_world.gd bonk_at, docs/level-format.md "The bonk"): a scripted courier with real courier physics is in the
## path of every kind of moving hazard (one lane each in tools/level_testdata/bonk) and the level clock runs the way a simulation ticks (advance, the
## level's effects, the courier's step). A courier that stands in the way of a hazard, or walks into it, must be thrown at least MIN_DISTANCE metres:
## from where it was at its first launch to the farthest it got within THROW_WINDOW seconds, and the way it was thrown. A courier riding a mover that
## hurts must not be thrown. Also the push pad and the bumper. Headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/bonk_check.gd [-- --legacy] [--trace=<lane>]
## `--legacy`: the level's launches only (push pads and bumpers), no bonk: for comparison, a hazard only shoves the courier aside.
## Prints BONK_CHECK lines and `BONK_CHECK ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Hazards := preload("res://levels/hazards.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const MIN_DISTANCE := 3.0     ## metres (a lane may ask for another: "need")
const MAX_INSIDE := 0.2       ## metres: a courier walking at a bumper (lane "ball": its centre, level-local) is thrown before its body is deeper than this in the drawn ball (band included)
const THROW_WINDOW := 1.0     ## seconds after the first launch
const RUN_SECONDS := 9.0
## id (lane), spot (level-local feet), move (a walker's raw input, world x / z; zero: it stands), kind (of the first launch)
const LANES := [
	{"id": "swing", "spot": Vector3(-62.0, 0.0, -6.0), "kind": "bonk"},
	{"id": "swing_walk", "spot": Vector3(-68.0, 0.0, -6.0), "move": Vector2(1.0, 0.0), "kind": "bonk"},
	{"id": "spin", "spot": Vector3(-43.2, 0.0, -4.2), "kind": "bonk"},
	{"id": "spin_walk", "spot": Vector3(-38.0, 0.0, -6.0), "move": Vector2(-1.0, 0.0), "kind": "bonk"},
	{"id": "slide", "spot": Vector3(-31.0, 0.0, -6.0), "kind": "bonk"},
	{"id": "slide_walk", "spot": Vector3(-24.0, 0.0, -6.0), "move": Vector2(-1.0, 0.0), "kind": "bonk"},
	{"id": "lift", "spot": Vector3(-14.0, 0.0, -6.0), "kind": "bonk"},
	{"id": "ball", "spot": Vector3(14.0, 0.0, -6.0), "kind": "bonk"},
	{"id": "ball_walk", "spot": Vector3(25.0, 0.0, -6.0), "move": Vector2(-1.0, 0.0), "kind": "bonk"},
	{"id": "cannon", "spot": Vector3(45.5, 0.0, -6.0), "kind": "bonk"},
	{"id": "push", "spot": Vector3(60.0, 0.0, -6.0), "kind": "push"},
	{"id": "bumper", "spot": Vector3(71.0, 0.0, -6.0), "kind": "bumper", "need": 1.5}, # a bumper's throw is mostly up (a bounce): kick 7.5 m/s, up 15
	{"id": "bumper_walk", "spot": Vector3(77.0, 0.0, -6.0), "move": Vector2(-1.0, 0.0), "kind": "bumper", "need": 0.0, "ball": Vector3(70.0, 1.0, -6.0), "rad": 1.25}, # keeps walking into the ball while it throws: only WHEN the bump fires is checked (the standing lane checks the throw)
	# ROLLING ROAD (level 23) as built: a big ball rolling down a lane at a courier who stands in it / walks into it, a hopping-size ball, a crossing ball, a cannon ball that lands on the road
	{"id": "lane_ball", "spot": Vector3(90.0, 0.0, -3.0), "kind": "bonk"},
	{"id": "lane_walk", "spot": Vector3(97.0, 0.0, 0.0), "move": Vector2(0.0, -1.0), "kind": "bonk"},
	{"id": "hop_ball", "spot": Vector3(104.0, 0.0, -3.0), "kind": "bonk"},
	{"id": "cross_ball", "spot": Vector3(122.0, 0.0, -6.0), "kind": "bonk"},
	{"id": "drop_cannon", "spot": Vector3(126.0, 0.0, 8.0), "kind": "bonk"},
]

var legacy := false
var trace := ""
var world: Node3D
var holder: Node3D
var fails := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--legacy": legacy = true
		if argument.begins_with("--trace="): trace = argument.trim_prefix("--trace=")
	run.call_deferred()

func say(text: String) -> void:
	print("BONK_CHECK ", text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	world.level_dir = ProjectSettings.globalize_path("res://").path_join("../tools/level_testdata/bonk").simplify_path()
	holder.add_child(world)
	await world.build("authority")
	world.set_active_level(0)
	await physics_frame
	for lane: Dictionary in LANES:
		await check_lane(lane)
	if not legacy:
		await check_rider()
		await check_race_flings()
	say("ok=%s" % (fails == 0))
	holder.queue_free()
	await process_frame
	quit(1 if fails > 0 else 0)

## One tick of a simulation: the clock, the level's effects on the courier, its step.
func tick(body: CharacterBody3D, motion: RefCounted, move: Vector2) -> Dictionary:
	world.advance(DT)
	var effect: Dictionary
	if legacy:
		effect = world.effects_at(0, 0, body.global_position)
		if not effect.is_empty(): motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
	else:
		effect = world.apply_effects(0, 0, body, motion)
	motion.step(body, {"move": move}, DT)
	await physics_frame
	return effect

func courier(spot: Vector3) -> Array:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.reset(body, world.level_origin(0) + spot, 0.0)
	return [body, motion]

func check_lane(lane: Dictionary) -> void:
	world.set_clock(0.0)
	await physics_frame
	var made := courier(lane.spot)
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var move: Vector2 = lane.get("move", Vector2.ZERO)
	var first := {}
	var first_at := -1.0
	var from := Vector3.ZERO     ## where the courier was at the first launch
	var thrown := 0.0            ## the farthest it got from there within THROW_WINDOW seconds
	var heading := Vector3.ZERO
	var inside_by := 0.0         ## a lane with a visible ball: how far the courier's capsule was inside it when the launch fired (m)
	for step in int(RUN_SECONDS / DT):
		var before := body.global_position
		var effect: Dictionary = await tick(body, motion, move)
		if not effect.is_empty() and first.is_empty():
			first = effect
			first_at = world.clock
			from = body.global_position
			if lane.has("ball"):
				# how far the capsule is inside the drawn ball (band included) at the tick it is thrown: what is drawn is what bumps
				var centre: Vector3 = world.level_origin(0) + (lane.ball as Vector3)
				var low := before + Vector3(0.0, LevelWorld.CENTRE_HEIGHT - LevelWorld.COURIER_HALF_SEGMENT, 0.0)
				var high := before + Vector3(0.0, LevelWorld.CENTRE_HEIGHT + LevelWorld.COURIER_HALF_SEGMENT, 0.0)
				var near := Geometry3D.get_closest_point_to_segment(centre, low, high)
				inside_by = float(lane.rad) + Hazards.BUMPER_BAND - (near.distance_to(centre) - LevelWorld.COURIER_RADIUS)
		if trace == lane.id and step % 6 == 0: say("  t=%.2f pos %s vel %s %s" % [world.clock, (body.global_position - world.level_origin(0)).snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.01), str(effect.get("kind", ""))])
		if not first.is_empty():
			if world.clock - first_at > THROW_WINDOW: break
			var gone := body.global_position - from
			gone.y = 0.0
			if gone.length() > thrown:
				thrown = gone.length()
				heading = gone
	var kind := str(first.get("kind", "none"))
	var direction := Vector3(first.v.x, 0.0, first.v.z).normalized() if not first.is_empty() else Vector3.ZERO
	var need: float = lane.get("need", MIN_DISTANCE)
	var ok: bool = thrown >= need and kind == str(lane.kind)
	if lane.has("ball") and inside_by > MAX_INSIDE: ok = false # thrown only once it stood well inside the ball it can see
	if kind == "bonk" and heading.normalized().dot(direction) < 0.5: ok = false # far enough, but not the way it was thrown
	if not ok: fails += 1
	say("%s %s: first launch '%s' at t=%.2f, thrown %.2f m in %.1f s (needs %.1f) towards %s, launch %s%s" % ["ok  " if ok else "FAIL", lane.id, kind, first_at, thrown, THROW_WINDOW, need,
		heading.normalized().snapped(Vector3.ONE * 0.01), direction.snapped(Vector3.ONE * 0.01), (", %.2f m inside the drawn ball (max %.2f)" % [inside_by, MAX_INSIDE]) if lane.has("ball") else ""])
	body.queue_free()
	await physics_frame

## RACE FLING (levels 29-32, `world: daylight`): a courier standing in the sweep of every hurting spinner, wheel and windmill of the real levels is bonked and thrown OFF the
## course: it is thrown at least FLING_MIN m/s, and within FALL_SECONDS it is under the level's `void_y` (the plane of the lasers), not stuck on the walkway. The real level
## world is built (authority, no look) and the courier is put on the floor under the hazard's pivot (a spinner: 2 m beside it); a hazard whose arms never come down to a
## courier's head is not asked.
const RACE_LEVELS := [29, 30, 31, 32]
const FALL_SECONDS := 9.0
const FLING_MIN := 11.0
## Hazards whose fling is stopped by the level's own solids (a hall wall beside the walkway, the next disc of a field or row (the 4-blade middle disc of level 30's row of three throws a courier onto the floor behind it), the hop pedestals beside the third gantry spinner of 29, a throw across a small disc that ends on the disc itself: the throw dies out within about 5 m): the throw is still checked, the fall is not.
const CAUGHT := ["29/disc_l", "29/disc_r1_1", "29/disc_r1_2", "29/spin_x3", "29/disc_r3_2", "29/disc_r4_c", "29/disc_r3_1", "29/disc_r4_l", "29/disc_r2_1", "30/disc_a1", "30/disc_a2", "30/disc_b2", "30/disc_b5"]

func check_race_flings() -> void:
	var real := LevelWorld.new()
	holder.add_child(real)
	await real.build("authority")
	var saved := world
	world = real
	var asked := 0
	for number: int in RACE_LEVELS:
		var k := number - 1
		if k >= real.level_count(): continue
		real.set_active_level(k)
		await physics_frame
		var data: Dictionary = real._levels[k].data
		for h: Dictionary in data.hazards:
			if h.k != "spin" or not h.hit: continue
			var reach := 0.0
			for part: Dictionary in h.parts: reach = maxf(reach, (part.size as Vector3).length() * 0.5)
			var origin: Vector3 = real.level_origin(k)
			var pivot: Vector3 = origin + (h.pivot as Vector3)
			var spot := pivot + (Vector3(2.0, 0.0, 0.0) if h.axis == "y" else Vector3.ZERO)
			var ray := PhysicsRayQueryParameters3D.create(spot + Vector3(0.0, 0.2, 0.0), spot - Vector3(0.0, 40.0, 0.0), LevelWorld.LAYER_SOLID)
			var hit: Dictionary = real.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty(): continue
			var floor_y: float = (hit.position as Vector3).y
			if h.axis != "y" and pivot.y - reach > floor_y + 1.6: continue
			asked += 1
			await check_fling(number, k, h, Vector3(spot.x, floor_y, spot.z) - origin, float(data.void_y))
	if asked == 0:
		fails += 1
		say("FAIL race fling: no spinner of levels 29-32 was asked")
	world = saved
	real.queue_free()
	await physics_frame

func check_fling(number: int, k: int, h: Dictionary, spot: Vector3, void_y: float) -> void:
	world.set_clock(0.0)
	world.reset_effects() # the previous fling's bonk cooldown (stamped at its own clock) must not swallow this one's first bonk
	await physics_frame
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.reset(body, world.level_origin(k) + spot + Vector3(0.0, 0.05, 0.0), 0.0)
	var first := {}
	var fell_at := -1.0
	for step in int(FALL_SECONDS / DT):
		world.advance(DT)
		var effect: Dictionary = world.apply_effects(k, 0, body, motion)
		if not effect.is_empty() and first.is_empty(): first = effect
		if trace == "fling:%s" % h.id and (step % 6 == 0 or not effect.is_empty()): say("  t=%.2f pos %s vel %s %s" % [world.clock, (body.global_position - world.level_origin(k)).snapped(Vector3.ONE * 0.01), body.velocity.snapped(Vector3.ONE * 0.01), str(effect.get("kind", ""))])
		motion.step(body, {"move": Vector2.ZERO}, DT)
		await physics_frame
		if body.global_position.y - world.level_origin(k).y < void_y:
			fell_at = world.clock
			break
	var speed := Vector3(first.v.x, 0.0, first.v.z).length() if not first.is_empty() else 0.0
	var caught := fell_at < 0.0 and ("%d/%s" % [number, h.id]) in CAUGHT
	var ok := not first.is_empty() and speed >= FLING_MIN and (fell_at >= 0.0 or caught)
	if not ok: fails += 1
	say("%s fling L%d %s%s: %s, launch %.1f m/s, under void_y %.0f at t=%s (spot %s, ends %s, launch dir %s)" % ["ok  " if ok else "FAIL", number, h.id, " (caught by level solids)" if caught else "", str(first.get("kind", "no bonk")), speed, void_y, ("%.1f" % fell_at) if fell_at >= 0.0 else "never", spot.snapped(Vector3.ONE * 0.1), (body.global_position - world.level_origin(k)).snapped(Vector3.ONE * 0.1), (Vector3(first.v.x, 0.0, first.v.z).normalized() if not first.is_empty() else Vector3.ZERO).snapped(Vector3.ONE * 0.01)])
	body.queue_free()
	await physics_frame

## A courier standing on a hurting slide platform's top (the platform's own side is a wall, its top only carries): not thrown, carried along.
func check_rider() -> void:
	var index: int = world.add_hazard(0, {"k": "slide", "id": "rider_deck", "p": [0, 0.5, 14], "to": [10, 0, 0], "period": 8, "pause": 0.5, "s": [6, 1, 6], "hit": true})
	if index < 0:
		fails += 1
		say("FAIL rider: the test hazard was not built")
		return
	world.set_clock(0.0)
	await physics_frame
	var made := courier(Vector3(1.0, 1.0, 14.0))
	var body: CharacterBody3D = made[0]
	var motion: RefCounted = made[1]
	var bonks := 0
	for step in int(4.0 / DT):
		var effect: Dictionary = await tick(body, motion, Vector2.ZERO)
		if str(effect.get("kind", "")) == "bonk": bonks += 1
	var carried: float = body.global_position.x - world.level_origin(0).x
	var ok: bool = bonks == 0 and carried > 3.0 and motion.platform != null
	if not ok: fails += 1
	say("%s rider: %d bonks while carried, travelled to x=%.2f (platform %s)" % ["ok  " if ok else "FAIL", bonks, carried, "yes" if motion.platform != null else "no"])
	body.queue_free()
	await physics_frame
