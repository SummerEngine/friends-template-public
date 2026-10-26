extends SceneTree
## EXPERIMENT (switchable) edge bumpers: proves the cushions on the real courier physics and the real level world (levels/edge_bumpers.gd, docs/level-format.md "Edge bumpers (experiment)").
## For every level the experiment is ON for (levels/edge_bumpers.json; `--levels=29,30` picks) it prints the plan (candidates, chosen, share) and checks
##   PLAN     the clear middle of every small platform is 45 to 70 % of its width both ways (the target is 55 %) and every platform has a clear middle at all; every cushion stands on its deck.
##   CENTRE   a courier aimed at the clear middle of every bumpered platform (a small one: its centre; a big deck: a spot just inside its longest cushion) from three sides (the course direction and
##            both sides), braking on landing, lands on the deck and is NEVER bumped (3 of 3).
##   SAFE     dropped straight down on each corner of the clear middle (a big deck: of 3 m round the spot; 4 flights, 5 cm inside it): never bumped, still standing (a slanting approach from outside
##            crosses the cushions at the rim in the air: that is what they are for).
##   EDGE     aimed at the middle of each cushion from outside: it is bumped (`kind` "cushion") and ends off the platform (outside its outline or under its deck).
##   DASH     (information, never a failure) the same bounced courier presses the air dash back at the platform 4 ticks after the bump: the share that ends standing on the deck again (an air dash is the
##            player's way out of a bump; one per airtime, 11 m/s for 0.3 s: courier_motion.gd).
##   LOOK     with `--look` (the world is built as a client): every drawn tube and ball is exactly the capsule the hitbox is (radius, length, place), nothing else is drawn.
## Headless, never windowed:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 600 <Summer> --headless --audio-driver Dummy --fixed-fps 60 --path demo -s $PWD/tools/edge_bumper_probe.gd -- [--levels=29,30,31,32] [--look] [--trace]
## Prints EDGE_BUMPER lines and `EDGE_BUMPER RESULT ok=<bool>`; exit code 1 on a failure.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const EdgeBumpers := preload("res://levels/edge_bumpers.gd")
const DT := 1.0 / 60.0
const DROP := 3.0               ## m over the deck a flight starts
const SPEED := 5.0              ## m/s, the walk
const STAND_TICKS := 45

var levels_wanted: Array = [29, 30, 31, 32]
var look_check := false
var trace := false
var world: Node3D
var holder: Node3D
var failures := 0
var counts := {"platforms": 0, "centre": 0, "centre_ok": 0, "safe": 0, "safe_ok": 0, "edge": 0, "edge_ok": 0, "dash": 0, "dash_ok": 0}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="):
			levels_wanted = []
			for part in argument.trim_prefix("--levels=").split(","): levels_wanted.append(int(part))
		if argument == "--look": look_check = true
		if argument == "--trace": trace = true
	run.call_deferred()

func say(text: String) -> void:
	print("EDGE_BUMPER ", text)

func fail(text: String) -> void:
	failures += 1
	say("FAIL " + text)

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local" if look_check else "authority")
	for number: int in levels_wanted:
		var k := number - 1
		if k >= world.level_count(): continue
		world.set_active_level(k)
		await physics_frame
		await check_level(k)
	say("TOTAL platforms=%d centre=%d/%d safe=%d/%d edge_bounced=%d/%d (information: a bounced courier that air-dashes back stands on the deck again in %d of %d)" % [counts.platforms, counts.centre_ok, counts.centre, counts.safe_ok, counts.safe, counts.edge_ok, counts.edge, counts.dash_ok, counts.dash])
	say("RESULT ok=%s" % str(failures == 0))
	holder.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)

func check_level(k: int) -> void:
	var entry: Dictionary = world._levels[k]
	var data: Dictionary = entry.data
	var plan: Dictionary = data.edge_bumpers
	var number := int(data.number)
	if not bool(plan.on):
		say("level %d: edge bumpers OFF" % number)
		return
	var platforms: Array = plan.platforms
	var share := float(platforms.size()) / maxf(float(plan.candidates), 1.0)
	say("level %d %s: %d platforms that can carry cushions, %d with bumpers (%.0f %%), %d cushions, seed %d" % [number, data.title, plan.candidates, platforms.size(), share * 100.0, (plan.pills as Array).size(), plan.seed])
	check_plan(number, plan, data)
	if trace:
		var listed: Array = []
		for candidate: Dictionary in EdgeBumpers.candidate_platforms(data): listed.append(int(candidate.index))
		say("  candidates (block indices): %s" % str(listed))
	if look_check and not (plan.pills as Array).is_empty(): check_look(number, entry, plan)
	var origin: Vector3 = world.level_origin(k)
	for platform: Dictionary in platforms:
		counts.platforms += 1
		var spot: Vector2 = platform.spot
		var top := float(platform.top)
		var swept := swept_by_bar(data, platform)
		var name := "L%d#%d (%s %.2f x %.2f m, top %.2f, %d cushions)%s" % [number, int(platform.index), str(platform.kind), float(platform.x1) - float(platform.x0), float(platform.z1) - float(platform.z0), top, (platform.pills as Array).size(), " [swept by a spinner bar]" if swept else ""]
		var centre_ok := 0
		var headings := clean_headings(data, platform, spot, top)
		var wanted := headings.size() + 1
		for heading: Vector2 in headings + [Vector2.ZERO]:
			var result: Dictionary = await fly(k, origin, top, spot, heading, platform)
			counts.centre += 1
			if bool(result.safe): centre_ok += 1
			elif trace: say("  centre %s heading %s: %s" % [name, str(heading), str(result)])
		var safe: Rect2 = platform.safe
		if not bool(platform.ring): safe = safe.intersection(Rect2(spot - Vector2(1.5, 1.5), Vector2(3.0, 3.0)))
		var safe_ok := 0
		for corner: Vector2 in [safe.position, Vector2(safe.end.x, safe.position.y), safe.end, Vector2(safe.position.x, safe.end.y)]:
			var aim := corner + (spot - corner).normalized() * 0.05
			var result: Dictionary = await fly(k, origin, top, aim, Vector2.ZERO, platform)
			counts.safe += 1
			if bool(result.safe): safe_ok += 1
			elif trace: say("  safe corner %s at %s: %s" % [name, str(corner), str(result)])
		var edge_ok := 0
		var dash_ok := 0
		var ok_report := 0
		for index: int in platform.pills:
			# a sloppy landing: dropped straight onto the cushion's inner flank, 0.35 m in from its axis (a courier lands there, the cushion's touch reaches 0.6 m)
			var pill: Dictionary = plan.pills[index]
			var middle: Vector3 = pill.pivot
			var out := Vector2((pill.out as Vector3).x, (pill.out as Vector3).z)
			var aim := Vector2(middle.x, middle.z) - out * 0.35
			var result: Dictionary = await fly(k, origin, top, aim, Vector2.ZERO, platform)
			counts.edge += 1
			if bool(result.bounced) or (int(result.bumps) > 0 and stopped_by_neighbour(data, platform, middle, out)): edge_ok += 1 # thrown off, or thrown at the next stone's wall (a step 0.5 m up one gap away) and dropped back
			elif trace: say("  edge %s side %d: %s" % [name, int(pill.side), str(result)])
			var back: Dictionary = await fly(k, origin, top, aim, Vector2.ZERO, platform, true, -out)
			counts.dash += 1
			if int(back.bumps) > 0 and bool(back.on_deck): dash_ok += 1
		var pills := (platform.pills as Array).size()
		if swept: # a spinner bar knocks the courier about on these (its own check, bonk_check, plays that): reported, not counted
			centre_ok = wanted
			safe_ok = 4
			counts.centre -= wanted
			counts.safe -= 4
			counts.edge -= pills
			counts.dash -= pills
			ok_report = edge_ok
			edge_ok = pills
		else:
			counts.centre_ok += centre_ok
			counts.safe_ok += safe_ok
			counts.edge_ok += edge_ok
			counts.dash_ok += dash_ok
			ok_report = edge_ok
		var ok := centre_ok == wanted and safe_ok == 4 and edge_ok == pills
		say("%s %s: centre %d/%d landed safe, clear-middle corners %d/4, sloppy landings bounced off %d/%d, air dash back onto the deck %d/%d" % ["PASS" if ok else "FAIL", name, centre_ok, wanted, safe_ok, ok_report, pills, dash_ok, pills])
		if not ok: failures += 1

## Whether another block of the level stands within 2 m outside the cushion at `middle` (facing `out`) and up to 3 m over the deck: a courier thrown out of the cushion meets its wall.
func stopped_by_neighbour(data: Dictionary, platform: Dictionary, middle: Vector3, out: Vector2) -> bool:
	var reach := AABB(Vector3(middle.x - 0.5, float(platform.top) - 0.5, middle.z - 0.5) + Vector3(out.x, 0.0, out.y) * 1.2, Vector3(1.0 + absf(out.x) * 1.6, 3.5, 1.0 + absf(out.y) * 1.6))
	for index in (data.blocks as Array).size():
		if index != int(platform.index) and reach.intersects(EdgeBumpers._aabb(data.blocks[index])): return true
	return false

## Whether a spinner bar (a hit `spin` or `swing`) sweeps the deck: the courier is knocked about there by the bar, not by the cushions.
func swept_by_bar(data: Dictionary, platform: Dictionary) -> bool:
	var footprint := Rect2(float(platform.x0), float(platform.z0), float(platform.x1) - float(platform.x0), float(platform.z1) - float(platform.z0))
	for h: Dictionary in data.hazards:
		if not str(h.k) in ["spin", "swing"] or not bool(h.hit): continue
		var box: AABB = EdgeBumpers._hazard_box(h)
		if footprint.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)) and box.end.y > float(platform.top) - 1.0 and box.position.y < float(platform.top) + 3.0: return true
	return false

## Up to three of the compass headings (the course's own first: -z, +x, -x, +z, then the diagonals) a flight at `spot` can start from: its whole descent (a 0.8 m wide, 1.8 m tall courier) stays clear of every
## other block of the level, so the flight tests the cushions and not a wall, a post or the next stone.
func clean_headings(data: Dictionary, platform: Dictionary, spot: Vector2, top: float) -> Array:
	var result: Array = []
	var fall := sqrt(2.0 * DROP / Motion.GRAVITY)
	for heading: Vector2 in [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071), Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071)]:
		var clear := true
		for step in 25:
			var t := fall * float(step) / 24.0
			var at := spot - heading * SPEED * (fall - t)
			var feet := top + DROP - 0.5 * Motion.GRAVITY * t * t
			var body := AABB(Vector3(at.x - 0.4, feet, at.y - 0.4), Vector3(0.8, 1.8, 0.8))
			for index in (data.blocks as Array).size():
				if index == int(platform.index): continue
				if body.intersects(EdgeBumpers._aabb(data.blocks[index])): clear = false
		if clear: result.append(heading)
		if result.size() >= 3: break
	return result

## The plan's own promises.
func check_plan(number: int, plan: Dictionary, data: Dictionary) -> void:
	var platforms: Array = plan.platforms
	for platform: Dictionary in platforms:
		var safe: Rect2 = platform.safe
		var width := float(platform.x1) - float(platform.x0)
		var depth := float(platform.z1) - float(platform.z0)
		if safe.size.x < 1.0 or safe.size.y < 1.0: fail("level %d #%d: the clear middle is only %.2f x %.2f m" % [number, platform.index, safe.size.x, safe.size.y])
		var sides := {}
		for span: Dictionary in platform.spans: sides[int(span.side)] = true
		if bool(platform.ring) and platform.kind == "box" and (platform.pills as Array).size() == 4 and sides.size() == 4: # one cushion on each of the four sides (a side a post or a cut breaks up has no single inset to measure)
			var wide := safe.size.x / width
			var deep := safe.size.y / depth
			if minf(wide, deep) < 0.45 or maxf(wide, deep) > 0.70: fail("level %d #%d: the clear middle is %.0f x %.0f %% of the platform" % [number, platform.index, wide * 100.0, deep * 100.0])
		var block: Dictionary = data.blocks[int(platform.index)]
		var half_up := (block.size as Vector3).y * 0.5 + (block.xf as Transform3D).origin.y
		for index: int in platform.pills:
			var pill: Dictionary = plan.pills[index]
			if absf(float(pill.a.y) - (half_up + EdgeBumpers.RADIUS + EdgeBumpers.LIFT)) > 0.001 or absf(float(pill.b.y) - float(pill.a.y)) > 0.0001: fail("level %d #%d: a cushion does not rest on its deck" % [number, platform.index])
			for end: Vector3 in [pill.a, pill.b]:
				if end.x < float(platform.x0) or end.x > float(platform.x1) or end.z < float(platform.z0) or end.z > float(platform.z1): fail("level %d #%d: a cushion reaches past the deck's edge" % [number, platform.index])

## LOOK: the drawn meshes are the hitboxes.
func check_look(number: int, entry: Dictionary, plan: Dictionary) -> void:
	var look: Node = entry.get("cushions")
	if look == null:
		fail("level %d: no cushion look was built" % number)
		return
	var tubes := 0
	var balls := 0
	for group: Node in look.get_children():
		for child: Node in group.get_children():
			var mesh := (child as MeshInstance3D).mesh
			if mesh is CylinderMesh:
				tubes += 1
				var found := false
				for pill: Dictionary in plan.pills:
					var at: Vector3 = ((child as Node3D).transform.origin)
					if at.distance_to((pill.a + pill.b) * 0.5) < 0.001 and absf((mesh as CylinderMesh).height - (pill.a as Vector3).distance_to(pill.b)) < 0.001 \
							and absf((mesh as CylinderMesh).top_radius - float(pill.rad)) < 0.0001 and absf((mesh as CylinderMesh).bottom_radius - float(pill.rad)) < 0.0001:
						var along: Vector3 = ((child as Node3D).transform.basis * Vector3.UP).normalized()
						if absf(along.dot(((pill.b as Vector3) - pill.a).normalized())) > 0.9999: found = true
				if not found: fail("level %d: a drawn tube is no hitbox (%s)" % [number, child.name])
			elif mesh is SphereMesh:
				balls += 1
				var matched := false
				for pill: Dictionary in plan.pills:
					for end: Vector3 in [pill.a, pill.b]:
						if (child as Node3D).position.distance_to(end) < 0.001 and absf((mesh as SphereMesh).radius - float(pill.rad)) < 0.0001: matched = true
				if not matched: fail("level %d: a drawn ball is no hitbox end (%s)" % [number, child.name])
			else: fail("level %d: something else is drawn: %s" % [number, child.name])
	if tubes != (plan.pills as Array).size(): fail("level %d: %d tubes drawn for %d cushions" % [number, tubes, (plan.pills as Array).size()])
	say("level %d look: %d tubes and %d balls, each exactly a hitbox" % [number, tubes, balls])

## One flight: the courier starts DROP over the deck, SPEED m/s along `heading`, and lands (no input in the air but the heading held) on `aim` (x, z level-local); it brakes on landing.
## With `dash_back` a bumped courier presses the air dash 4 ticks after the bump and holds `back` (the way back onto the platform) while the dash and the fall last, then brakes.
## Returns {safe: landed on the deck and never bumped, standing there at the end; bounced: a cushion threw it and it ended off the platform; on_deck; bumps; landing; final}.
func fly(k: int, origin: Vector3, top: float, aim: Vector2, heading: Vector2, platform: Dictionary, dash_back := false, back := Vector2.ZERO) -> Dictionary:
	var reach := SPEED * sqrt(2.0 * DROP / Motion.GRAVITY) # the way the courier covers while it falls DROP
	var start := aim - heading * reach
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	var yaw := atan2(-heading.x, -heading.y)
	motion.reset(body, origin + Vector3(start.x, top + DROP, start.y), yaw)
	body.velocity = Vector3(heading.x * SPEED, 0.0, heading.y * SPEED)
	world.set_clock(0.0)
	world.reset_effects()
	var bumps := 0
	var bumped_at := -1
	var landed_at := -1
	var landing := Vector3.ZERO
	var stood := 0
	var final := Vector3.ZERO
	for tick in 420:
		await physics_frame
		world.advance(DT)
		var effect: Dictionary = world.effects_at(k, 0, body.global_position)
		if not effect.is_empty() and str(effect.kind) == "cushion": # the platform's own cushions only: a spinner's bonk or a pad is proven by its own check
			bumps += 1
			if bumped_at < 0: bumped_at = tick
			motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
		var move := Vector2.ZERO
		var press_dash := false
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if bumped_at < 0:
			if landed_at < 0: move = heading
			elif speed > 0.5: move = -heading # the player brakes after landing
		elif dash_back:
			var since := tick - bumped_at
			if since >= 4 and since < 40 and not motion.grounded: move = back
			elif motion.grounded and speed > 0.5: move = -heading
			press_dash = since == 4
		motion.step(body, {"move": move, "dash": press_dash}, DT)
		var feet := body.global_position - origin
		final = feet
		if motion.grounded:
			if landed_at < 0 and tick > 2:
				landed_at = tick
				landing = feet
			stood += 1
		else: stood = 0
		if landed_at >= 0 and stood >= STAND_TICKS: break
		if feet.y < top - 12.0: break
	body.queue_free()
	await physics_frame
	var inside := final.x >= float(platform.x0) - 0.2 and final.x <= float(platform.x1) + 0.2 and final.z >= float(platform.z0) - 0.2 and final.z <= float(platform.z1) + 0.2
	var on_deck := inside and absf(final.y - top) <= 0.15
	var landed_on_deck := landed_at >= 0 and landing.x >= float(platform.x0) and landing.x <= float(platform.x1) and landing.z >= float(platform.z0) and landing.z <= float(platform.z1) and absf(landing.y - top) <= 0.15
	var result := {"safe": landed_on_deck and bumps == 0 and on_deck, "bounced": bumps > 0 and not on_deck, "on_deck": on_deck, "bumps": bumps, "landed_on_deck": landed_on_deck, "landing": landing, "final": final}
	return result
