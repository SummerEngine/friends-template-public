extends SceneTree
## Check of the hang: a courier that rests on the edge or the corner of a stage tile with the middle of its round feet up to 0.29 m past it (radius 0.35 m, the steepest
## floor 55 degrees, nothing slides it off) must be "on" that tile for the rules (a reach past the edge of only 0.1 m is too short): otherwise the tile is never stepped, never vanishes, the
## courier hangs there for good and the round cannot end (e.g. an idle player on layer 2 of the hex stack). Headless, the real courier motion on the real stage levels:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s $PWD/tools/stage_hang_check.gd
## 1. Where a courier can rest (an isolated tile, every other tile gone, the courier idle for 1.5 s with nothing stepped, from 0 to 0.4 m past the tile's edge or corner, along
##    the sides and the diagonals): wherever it is still on the tile, the tile counts as under it (StepTiles.tiles_under), on the square and the hex stack.
## 2. The same spots with the rules' stepping (whoever stands on a tile steps it): the courier falls through, 3 m or more within 4 s, never hangs.
## Prints STAGE_HANG lines and STAGE_HANG ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const Motion := preload("res://courier/courier_motion.gd")
const DT := 1.0 / 60.0
const LEVELS := [24, 25] ## 0-based: the square and the hex stack
const OFFSETS := [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.28, 0.3, 0.35, 0.4] ## m past the tile's extent in the direction
const REST_TICKS := 90
const FALL_TICKS := 240

var failures := 0
var holder: Node3D
var levels: Node3D
var data: Dictionary = {}
var level := 0
var tile_index := -1
var tile_p := Vector3.ZERO

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_HANG ", "ok   " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	create_timer(280.0).timeout.connect(func() -> void:
		print("STAGE_HANG FAIL timed out")
		print("STAGE_HANG ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	levels = LevelWorld.new()
	holder.add_child(levels)
	await levels.build("authority")
	for k: int in LEVELS:
		level = k
		levels.set_active_level(k)
		data = levels._levels[k].data.tiles
		print("STAGE_HANG --- level %d %s (%s)" % [k + 1, levels.title(k), data.grid])
		await rest_spots()
		await falls_through()
	print("STAGE_HANG ok=", failures == 0)
	quit(0 if failures == 0 else 1)

# ------------------------------------------------------------------ helpers

func isolate() -> void:
	levels.set_clock(0.0)
	var count: int = levels.tile_count(level)
	tile_index = -1
	for index in count:
		var tile: Dictionary = data.tiles[index]
		if int(tile.floor) == 0 and (tile_index < 0 or (tile.p as Vector3).length() < (data.tiles[tile_index].p as Vector3).length()): tile_index = index
	tile_p = data.tiles[tile_index].p
	var bytes := PackedByteArray()
	bytes.resize(count)
	bytes.fill(StepTiles.PRE_GONE)
	bytes[tile_index] = 0
	levels.set_tile_steps(level, bytes)

func extent(direction: Vector2) -> float:
	var best := -INF
	for corner in StepTiles.tile_corners(data, 0.0): best = maxf(best, corner.dot(direction))
	return best

## The directions to test: both axes and the diagonals (towards the corners of a square, between a hexagon's corners and edges).
func directions() -> Array:
	return [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]

func courier(spot: Vector3) -> Dictionary:
	var body := Motion.make_body("Courier")
	holder.add_child(body)
	var motion := Motion.new()
	motion.setup(body)
	motion.set_stage(true)
	motion.set_floors(levels.tile_floors(level))
	motion.reset(body, spot, 0.0)
	await frames(1)
	return {"body": body, "motion": motion}

func spot_for(direction: Vector2, offset: float) -> Vector3:
	var origin: Vector3 = levels.level_origin(level)
	var reach := extent(direction) + offset
	return origin + Vector3(tile_p.x + direction.x * reach, float(data.floors[0].y) + 0.02, tile_p.z + direction.y * reach)

func top_y() -> float:
	return (levels.level_origin(level) as Vector3).y + float(data.floors[0].y)

func remove(c: Dictionary) -> void:
	var body := c.body as Node
	body.get_parent().remove_child(body)
	body.free()

# ------------------------------------------------------------------ 1. wherever it can rest, the tile is under it

func rest_spots() -> void:
	var worst_rest := 0.0
	var rests := 0
	var uncovered: Array = []
	for direction: Vector2 in directions():
		for offset: float in OFFSETS:
			isolate()
			var c := await courier(spot_for(direction, offset))
			for i in REST_TICKS: (c.motion as RefCounted).step(c.body, {"move": Vector2.ZERO, "jump": false, "dash": false}, DT)
			var body := c.body as CharacterBody3D
			var resting: bool = (c.motion as RefCounted).grounded and body.global_position.y > top_y() - 0.5
			if resting:
				rests += 1
				worst_rest = maxf(worst_rest, offset)
				if (levels.tiles_under(level, body.global_position) as Array).is_empty(): uncovered.append("%.2f m towards %s" % [offset, str(direction)])
			remove(c)
	check(rests > 0, "level %d: couriers rest idle on the edge or corner of a tile up to %.2f m past it (%d resting spots tried)" % [level + 1, worst_rest, rests])
	check(uncovered.is_empty(), "level %d: wherever a courier rests, the tile counts as under it (%d spots outside the reach %.2f m%s)" % [level + 1, uncovered.size(), StepTiles.STAGE_REACH_XZ, (": " + str(uncovered.slice(0, 3))) if not uncovered.is_empty() else ""])
	check(worst_rest <= StepTiles.STAGE_REACH_XZ - 0.005, "level %d: the reach (%.2f m) is past the farthest resting spot (%.2f m)" % [level + 1, StepTiles.STAGE_REACH_XZ, worst_rest])

# ------------------------------------------------------------------ 2. with the rules' stepping it falls through

func falls_through() -> void:
	var stuck: Array = []
	var cases := 0
	for direction: Vector2 in directions():
		for offset: float in OFFSETS:
			isolate()
			var c := await courier(spot_for(direction, offset))
			var body := c.body as CharacterBody3D
			var bytes: PackedByteArray = levels._levels[level].tiles.steps.duplicate()
			var fell_at := -1
			for i in FALL_TICKS:
				levels.advance(DT)
				await frames(1)
				(c.motion as RefCounted).step(body, {"move": Vector2.ZERO, "jump": false, "dash": false}, DT)
				var changed := false
				for index: int in levels.tiles_under(level, body.global_position):
					if bytes[index] == 0:
						bytes[index] = levels.tile_stamp(level)
						changed = true
				if changed: levels.set_tile_steps(level, bytes)
				if fell_at < 0 and body.global_position.y < top_y() - 3.0:
					fell_at = i
					break
			cases += 1
			if fell_at < 0: stuck.append("%.2f m towards %s (y %.2f)" % [offset, str(direction), body.global_position.y - top_y()])
			remove(c)
	check(stuck.is_empty(), "level %d: a courier idle %.2f m past a tile's edge, with the tile stepped as the rules do, falls 3 m within %.0f s (%d of %d hang%s)" % [level + 1, OFFSETS.back(), FALL_TICKS * DT, stuck.size(), cases, (": " + str(stuck.slice(0, 3))) if not stuck.is_empty() else ""])
	levels.set_clock(0.0)
