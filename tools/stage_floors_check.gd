extends SceneTree
## Headless check of the one-way floors of the stage rounds (courier/courier_motion.gd set_floors, levels/step_tiles.gd TILE_LAYER_BASE << floor), on the real stage levels
## (the square and the hex stack, level_25 and level_26), the real tile colliders (one static body per floor) and the real courier motion in the stage feel:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/stage_floors_check.gd
## A courier collides with the floors whose top is at or under its feet (and holds a floor until its feet are 0.6 m under it): it stands on its floor, walks freely on a
## lower floor under an intact one (it is never pushed, slowed or wedged), jumps UP through the floor over it and lands on it (when its jump reaches), falls through a hole
## onto the floor below (two holes: the next one, no tile: the ground), keeps standing on the tile it stepped on while it sinks, and runs off a sunk tile onto an intact one.
## Prints STAGE_FLOORS lines and STAGE_FLOORS ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const Motion := preload("res://courier/courier_motion.gd")

const START := 1 ## the start layer (12 groups of 3 x 3 tiles) is floor 0 of the file; the floors tested here are the full ones under it, numbered from 0
const LEVELS := [24, 25] ## 0-based: level_25.json (square stack) and level_26.json (hex stack)
const DT := 1.0 / 60.0
const STAND := 0.012 ## m: a courier on a floor stands this near its top

var failures := 0
var holder: Node3D
var levels: Node3D
var level := 0
var data: Dictionary = {}

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_FLOORS ", "ok   " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("STAGE_FLOORS FAIL timed out")
		print("STAGE_FLOORS ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	levels = LevelWorld.new()
	holder.add_child(levels)
	await levels.build("authority")
	check_mask()
	for k: int in LEVELS:
		level = k
		levels.set_active_level(k)
		levels.set_clock(0.0)
		levels.set_tile_steps(k, PackedByteArray())
		await frames(2)
		data = levels._levels[k].data.tiles
		print("STAGE_FLOORS --- level %d %s (%s tiles, %d floors, gap %.2f m)" % [k + 1, levels.title(k), data.grid, (data.floors as Array).size(), float(data.floors[1].y) - float(data.floors[2].y)])
		await standing_and_walking()
		await jumping_up()
		await holes()
		await sinking()
		await running_off_a_sunk_tile()
	print("STAGE_FLOORS ok=", failures == 0)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------ helpers

func origin() -> Vector3:
	return levels.level_origin(level)

func top_y(floor_index: int) -> float:
	return origin().y + float(data.floors[floor_index + START].y)

## The level-local spot of a plain tile of the top layer with plain tiles round it (28 m on the near side for the hex stack; a square stack has its pads in the near half, up to z 7 m).
func probe() -> Vector2:
	var pitch := float(data.pitch)
	return Vector2(0.0, -float(data.pitch) * 7.0) if str(data.grid) == "hex" else Vector2(-pitch * 0.5, pitch * 4.5)

func tile_at(floor_index: int, at: Vector2) -> int:
	for index in (data.tiles as Array).size():
		var tile: Dictionary = data.tiles[index]
		if int(tile.floor) == floor_index + START and absf((tile.p as Vector3).x - at.x) < 0.01 and absf((tile.p as Vector3).z - at.y) < 0.01: return index
	return -1

## A courier with its motion in the stage feel and the one-way floors of the round, standing on `floor_index` at level-local `at`.
func courier(floor_index: int, at: Vector2, rise := 0.02) -> Dictionary:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.set_stage(true)
	motion.set_floors(levels.tile_floors(level))
	motion.reset(body, origin() + Vector3(at.x, float(data.floors[floor_index + START].y) + rise, at.y), 0.0)
	body.collision_layer = Motion.LAYER_COURIER
	await frames(1)
	return {"body": body, "motion": motion}

func drop(c: Dictionary) -> void:
	var body := c.body as Node
	body.get_parent().remove_child(body)
	body.free()

func tick(c: Dictionary, move := Vector2.ZERO, jump := false) -> void:
	(c.motion as RefCounted).step(c.body, {"move": move, "jump": jump, "dash": false}, DT)

func feet(c: Dictionary) -> float:
	return (c.body as Node3D).global_position.y

func planar(c: Dictionary) -> Vector2:
	var v: Vector3 = (c.body as CharacterBody3D).velocity
	return Vector2(v.x, v.z)

func gone(index: int) -> void:
	var bytes: PackedByteArray = levels._levels[level].tiles.steps.duplicate()
	bytes.resize(levels.tile_count(level))
	bytes[index] = StepTiles.PRE_GONE
	levels.set_tile_steps(level, bytes)

func all_back() -> void:
	levels.set_clock(0.0)
	levels.set_tile_steps(level, PackedByteArray())
	var bytes := PackedByteArray()
	bytes.resize(levels.tile_count(level))
	levels.set_tile_steps(level, bytes)

# ------------------------------------------------------------------ the mask is a pure function of the floors and the height

func check_mask() -> void:
	var motion := Motion.new()
	motion.set_floors(PackedFloat32Array([0.0, -1.6, -3.2, -4.8]))
	var all := Motion.FLOOR_BASE | (Motion.FLOOR_BASE << 1) | (Motion.FLOOR_BASE << 2) | (Motion.FLOOR_BASE << 3)
	check(Motion.FLOOR_BASE == StepTiles.TILE_LAYER_BASE and Motion.FLOOR_BITS == StepTiles.TILE_LAYERS_ALL, "the motion's floor bits are the tiles' (TILE_LAYER_BASE %d)" % StepTiles.TILE_LAYER_BASE)
	check(motion.floor_mask(0.0) == all and motion.floor_mask(5.0) == all, "on the top floor, or over it: every floor")
	check(motion.floor_mask(-1.6) == (all & ~Motion.FLOOR_BASE) and motion.floor_mask(-1.58) == (all & ~Motion.FLOOR_BASE), "on the second floor: not the one over it, itself and every one under it")
	check(motion.floor_mask(-1.7) == ((Motion.FLOOR_BASE << 2) | (Motion.FLOOR_BASE << 3)) and motion.floor_mask(-6.0) == 0, "under a floor's top: that floor is not in the mask, only the ones under it; under every floor: none")
	check(motion.floor_mask(-1.6 - Motion.FLOOR_REACH * 0.5) == (all & ~Motion.FLOOR_BASE) and motion.floor_mask(-1.6 - Motion.FLOOR_REACH * 2.0) == (all & ~Motion.FLOOR_BASE & ~(Motion.FLOOR_BASE << 1)), "a floor comes in the mask when the feet reach its top (%.0f cm of reach)" % (Motion.FLOOR_REACH * 100.0))
	# the mask a body gets keeps the bits that are not floors (the painting's blocker, the other couriers)
	var body := Motion.make_body("Mask")
	body.collision_mask |= 1024
	holder.add_child(body)
	motion.setup(body)
	motion.set_stage(true)
	body.global_position = Vector3(0.0, -1.58, 0.0)
	motion.step(body, {}, DT)
	check((body.collision_mask & 1024) != 0 and (body.collision_mask & Motion.LAYER_COURIER) != 0 and (body.collision_mask & Motion.FLOOR_BITS) == (all & ~Motion.FLOOR_BASE) and (body.collision_mask & Motion.MASK_WORLD) == Motion.MASK_WORLD, "step() sets only the floor bits of the mask (the blocker, the couriers and the world stay)")
	motion.set_floors(PackedFloat32Array())
	motion.step(body, {}, DT)
	check((body.collision_mask & Motion.FLOOR_BITS) == 0, "outside a stage round no floor bit is left in the mask")
	body.free()

# ------------------------------------------------------------------ standing and walking under an intact floor

func standing_and_walking() -> void:
	var name := "level %d" % (level + 1)
	var at := probe()
	var floors: int = (data.floors as Array).size() - START
	var run_speed: float = Motion.STAGE_FEEL.walk
	for floor_index in mini(floors, 3):
		var c := await courier(floor_index, at)
		for i in 30: tick(c)
		check(c.motion.grounded and absf(feet(c) - top_y(floor_index)) < STAND, "%s: stands on floor %d (feet %.3f, top %.3f)" % [name, floor_index, feet(c) - origin().y, top_y(floor_index) - origin().y])
		# walks in four directions for a second, under every floor above it, intact
		var worst_height := 0.0
		var ungrounded := 0
		var slowest := INF
		var travelled := 0.0
		for way: Vector2 in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(0.0, -1.0)]: # a loop of 6 m legs: it stays clear of the pads
			var from: Vector3 = (c.body as Node3D).global_position
			for i in 30:
				tick(c, way)
				worst_height = maxf(worst_height, absf(feet(c) - top_y(floor_index)))
				if not c.motion.grounded: ungrounded += 1
				if i >= 14 and i < 26: slowest = minf(slowest, planar(c).length())
			travelled += ((c.body as Node3D).global_position - from).length()
		check(worst_height < STAND and ungrounded == 0, "%s: walks on floor %d under %d intact floors: height off by at most %.4f m, grounded every tick (%d off)" % [name, floor_index, floor_index, worst_height, ungrounded])
		check(slowest >= run_speed * 0.97 and travelled > run_speed * 2.0 * 0.8, "%s: never pushed or slowed there (slowest %.2f of %.2f m/s, %.1f m in 2 s)" % [name, slowest, run_speed, travelled])
		drop(c)

# ------------------------------------------------------------------ jumping up through the floor over it

func jumping_up() -> void:
	var name := "level %d" % (level + 1)
	var at := probe()
	var feel: Dictionary = Motion.STAGE_FEEL
	var apex := pow(float(feel.jump), 2.0) / (2.0 * float(feel.gravity))
	var gap := float(data.floors[START].y) - float(data.floors[START + 1].y)
	var c := await courier(1, at)
	for i in 20: tick(c)
	var highest := -INF
	var lowest_after := INF
	var started := feet(c)
	for i in 120:
		tick(c, Vector2.ZERO, i == 0)
		highest = maxf(highest, feet(c))
	var landed := feet(c)
	var reaches := apex > gap + 0.1
	if reaches:
		check(c.motion.grounded and absf(landed - top_y(0)) < STAND, "%s: jumps up through the floor over it (apex %.2f m over a gap of %.2f m) and lands on it (feet %.3f, top %.3f)" % [name, apex, gap, landed - origin().y, top_y(0) - origin().y])
	else:
		check(c.motion.grounded and absf(landed - top_y(1)) < STAND and highest > started + apex * 0.9, "%s: a jump of %.2f m does not reach the floor %.2f m over it: it comes down on its own floor (feet %.3f, highest %.2f over it)" % [name, apex, gap, landed - origin().y, highest - started])
	drop(c)
	# a jump under a hole's edge and under the middle of a tile alike, and several in a row: never stuck in the slab
	var stuck := false
	var tiles: Array = (data.tiles as Array).filter(func(tile: Dictionary) -> bool: return int(tile.floor) == START and absf((tile.p as Vector3).y) < 0.001)
	var spots := 0
	for index in range(0, tiles.size(), maxi(tiles.size() / 9, 1)):
		var p: Vector3 = (tiles[index] as Dictionary).p
		var j := await courier(1, Vector2(p.x, p.z))
		for i in 20: tick(j)
		var wedged := false
		for hop in 3:
			for i in 70:
				tick(j, Vector2.ZERO, i == 0)
			if not j.motion.grounded: wedged = true
		var ground := absf(feet(j) - top_y(1)) < STAND or absf(feet(j) - top_y(0)) < STAND
		stuck = stuck or wedged or not ground
		spots += 1
		drop(j)
	check(not stuck, "%s: hops under %d spots of the floor over it never end wedged in it (always back on a floor, grounded)" % [name, spots])

# ------------------------------------------------------------------ holes

func holes() -> void:
	var name := "level %d" % (level + 1)
	var at := probe()
	var floors: int = (data.floors as Array).size() - START
	# a hole in the top floor under the courier: it lands on the second
	all_back()
	var c := await courier(0, at)
	for i in 20: tick(c)
	gone(tile_at(0, at))
	await frames(1)
	var fell := 0
	var landed := false
	for i in 120:
		tick(c)
		if not c.motion.grounded: fell += 1
		if c.motion.grounded and not landed and fell > 0: landed = true
	check(landed and c.motion.grounded and absf(feet(c) - top_y(1)) < STAND, "%s: falls through a hole in the top floor onto the next (feet %.3f, top %.3f, %d ticks of fall)" % [name, feet(c) - origin().y, top_y(1) - origin().y, fell])
	drop(c)
	# holes in two floors: the third
	all_back()
	c = await courier(0, at)
	for i in 20: tick(c)
	gone(tile_at(0, at))
	var bytes: PackedByteArray = levels._levels[level].tiles.steps.duplicate()
	bytes[tile_at(1, at)] = StepTiles.PRE_GONE
	levels.set_tile_steps(level, bytes)
	await frames(1)
	for i in 160: tick(c)
	check(c.motion.grounded and absf(feet(c) - top_y(2)) < STAND, "%s: through two holes: the third floor (feet %.3f, top %.3f)" % [name, feet(c) - origin().y, top_y(2) - origin().y])
	drop(c)
	# no tile anywhere under it: the ground
	all_back()
	c = await courier(0, at)
	for i in 20: tick(c)
	bytes = levels._levels[level].tiles.steps.duplicate()
	for floor_index in floors: bytes[tile_at(floor_index, at)] = StepTiles.PRE_GONE
	levels.set_tile_steps(level, bytes)
	await frames(1)
	for i in 400: tick(c)
	var ground_y: float = origin().y + float(levels._levels[level].data.stage.ground.y)
	check(c.motion.grounded and absf(feet(c) - ground_y) < STAND, "%s: through every floor onto the ground (feet %.3f, ground top %.3f)" % [name, feet(c) - origin().y, ground_y - origin().y])
	check(levels.zone_at(level, (c.body as Node3D).global_position) == "", "%s: the ground is not a kill zone: the rules decide there" % name)
	drop(c)
	all_back()

# ------------------------------------------------------------------ the tile under it sinks

func sinking() -> void:
	var name := "level %d" % (level + 1)
	var at := probe()
	var delay := float(data.kinds["n"].delay)
	all_back()
	levels.set_clock(10.0)
	var c := await courier(0, at)
	for i in 20: tick(c)
	var index := tile_at(0, at)
	var bytes := PackedByteArray()
	bytes.resize(levels.tile_count(level))
	bytes[index] = levels.tile_stamp(level)
	levels.set_tile_steps(level, bytes)
	var low := INF
	var stood := true
	var went_at := -1.0
	var t := 0.0
	var solid_ticks := 0
	for i in 80:
		levels.set_clock(10.0 + t)
		await frames(1) # the world poses the tiles in its own step
		tick(c)
		t += DT
		if t < delay - 0.08:
			low = minf(low, feet(c))
			if absf(feet(c) - top_y(0)) > STAND or not c.motion.grounded: stood = false # the tile sinks in the look only: the courier stays level on it
			solid_ticks += 1
		if went_at < 0.0 and feet(c) < top_y(0) - 0.06: went_at = t
	check(stood and solid_ticks > 20 and absf(low - top_y(0)) < STAND, "%s: the courier stays level on the tile it stepped on while it holds weight (%.2f s): it sinks in the look only (lowest %.3f)" % [name, delay, low - origin().y])
	check(went_at > delay - 0.05 and went_at < delay + 0.2, "%s: it falls when the tile is gone, at %.2f s (delay %.2f s)" % [name, went_at, delay])
	for i in 200:
		levels.set_clock(10.0 + t)
		tick(c)
		t += DT
	check(c.motion.grounded and absf(feet(c) - top_y(1)) < STAND, "%s: and lands on the floor below (feet %.3f)" % [name, feet(c) - origin().y])
	drop(c)
	all_back()

# ------------------------------------------------------------------ off a sunk tile onto an intact one

func running_off_a_sunk_tile() -> void:
	var name := "level %d" % (level + 1)
	var pitch := float(data.pitch)
	var at := probe()
	var square: bool = str(data.grid) == "square"
	var along := Vector2(1.0, 0.0) if square else Vector2(0.0, 1.0) # the neighbour across a flat edge
	var next := at + along * pitch
	all_back()
	levels.set_clock(10.0)
	var c := await courier(0, at - along * (pitch * 0.5 + 5.0))
	for i in 20: tick(c)
	var bytes := PackedByteArray()
	bytes.resize(levels.tile_count(level))
	var worst_speed := INF
	var reached := false
	var stamped := false
	var bob := 0.0
	var t := 0.0
	for i in 70: # the courier runs up to the tile, the tile is stepped on as it arrives (it sinks), and it runs along it onto the next, intact one
		var local := (c.body as Node3D).global_position - origin()
		var edge := Vector2(local.x, local.z).dot(along) - (at.dot(along) - pitch * 0.5)
		if not stamped and edge > -0.1:
			stamped = true
			bytes[tile_at(0, at)] = levels.tile_stamp(level)
			levels.set_tile_steps(level, bytes)
			await frames(1)
		levels.set_clock(10.0 + t)
		tick(c, along)
		t += DT
		if stamped and Vector2(local.x, local.z).dot(along) > at.dot(along) - pitch * 0.5 and not reached: worst_speed = minf(worst_speed, planar(c).length())
		if stamped and not reached: bob = maxf(bob, absf(feet(c) - top_y(0)))
		if stamped and Vector2(local.x, local.z).distance_to(next) < 0.4 and absf(feet(c) - top_y(0)) < STAND: reached = true
		if OS.get_cmdline_user_args().has("--trace"): print("  tick %2d edge %.2f y %.3f grounded %s speed %.2f" % [i, edge, feet(c) - origin().y, c.motion.grounded, planar(c).length()])
	var run_speed: float = Motion.STAGE_FEEL.walk
	check(reached and worst_speed > run_speed * 0.9 and bob < STAND, "%s: runs onto a tile that sinks in the look and off it onto the next without stopping or bobbing (slowest %.2f of %.2f m/s, height off by at most %.3f m)" % [name, worst_speed, run_speed, bob])
	drop(c)
	all_back()
