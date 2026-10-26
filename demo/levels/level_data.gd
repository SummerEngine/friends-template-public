extends RefCounted
## Reads `level_NN.json` files (docs/level-format.md) into typed data. Pure: no nodes, shared by the authority, the clients and the tools.
const Hazards := preload("res://levels/hazards.gd")
const EdgeBumpers := preload("res://levels/edge_bumpers.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const DIR := "res" + "://levels"
const ROUTE_STEP := 2.0       ## metres between the points of the densified path the look measures distances to
const START_HALF_GAP := 1.75  ## the two couriers stand this far left and right of the start point
const DEFAULT_VOID_Y := -10.0
const MODES := ["carry", "balloon", "show"] ## the round modes a level may list (docs/level-format.md "modes")
const SHOW_KINDS := ["race", "survival", "final"] ## the show rounds a level may serve ("show")
const WORLDS := ["daylight"] ## the worlds a level may ask for ("world", docs/level-format.md); none = the cast's own world
const TONES := ["teal", "warm", "navy", "frame", "door", "crate", "eye", "court", "disc", "hub", "stone", "stone_plain", "arch", "slime", "finish"] ## the surfaces a block of a `world: daylight` level may ask for ("tone"); none = by its role: teal floors, navy walls
const PODIUM_SPOTS := 3

static func file_path(dir: String, number: int) -> String:
	return "%s/level_%02d.json" % [dir, number]

## Levels present: level_01.json, level_02.json, ... up to the first number that is missing (probing file names works in a packed build, a
## directory listing does not list every kind of file there).
static func count(dir := DIR) -> int:
	var number := 0
	while FileAccess.file_exists(file_path(dir, number + 1)): number += 1
	return number

## The level of file `number` (1-based) as typed data, {} when the file is missing or not valid JSON.
static func load_level(number: int, dir := DIR) -> Dictionary:
	var path := file_path(dir, number)
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("GW_LEVEL not valid JSON: " + path)
		return {}
	var level := parse(parsed, number)
	if not level.is_empty(): level.edge_bumpers = EdgeBumpers.plan(level, EdgeBumpers.config(dir, number)) # the experiment's cushions (levels/edge_bumpers.gd), NONE when it is off
	return level

static func parse(source: Dictionary, number: int) -> Dictionary:
	var start: Dictionary = source.get("start", {})
	var goal: Dictionary = source.get("goal", {})
	var level := {"number": number, "title": str(source.get("title", "LEVEL %d" % number)), "blurb": str(source.get("blurb", "")),
		"rule": str(source.get("rule", "")), "hint": str(source.get("hint", "")),
		"pool": bool(source.get("pool", true)),
		"start": Hazards.vec(start.get("p")), "start_yaw": deg_to_rad(float(start.get("yaw", 0.0))),
		"void_y": float(source.get("void_y", DEFAULT_VOID_Y))}
	var goal_size := Hazards.vec(goal.get("s"), Vector3(8.0, 4.0, 5.0))
	level.goal = {"p": Hazards.vec(goal.get("p")), "size": goal_size, "yaw": deg_to_rad(float(goal.get("yaw", 0.0)))}
	level.goal_volume = _volume(level.goal.p, goal_size, float(level.goal.yaw))
	var path := PackedVector3Array()
	for point: Variant in source.get("path", []): path.append(Hazards.vec(point))
	level.path = path
	level.route = densify(path)
	var kill: Array = []
	for entry: Variant in source.get("kill", []):
		if entry is Dictionary: kill.append(_volume(Hazards.vec(entry.get("p")), Hazards.vec(entry.get("s"), Vector3.ONE), deg_to_rad(float(entry.get("yaw", 0.0)))))
	level.kill = kill
	var modes: Array = []
	for mode: Variant in source.get("modes", ["carry"]):
		if mode is String and mode in MODES and not mode in modes: modes.append(mode)
	level.modes = modes if not modes.is_empty() else ["carry"]
	var show_kind := str(source.get("show", ""))
	level.show = show_kind if show_kind in SHOW_KINDS else ""
	level.arena = bool(source.get("arena", false)) # a survival level with a floor that stays (KEEP THE LOGO)
	level.play = str(source.get("play", "")) # how a survival show level is played besides its floor ("badge": KEEP THE LOGO)
	level.solo = bool(source.get("solo", true)) # false: the level needs other players (no show for one draws it)
	level.camera = str(source.get("camera", "")) # "stage": the round is played in the stage view (game/follow_camera.gd), as the tile stage rounds are
	level.cap = float(source.get("cap", 0.0)) # a show level's own time cap in s (0: the round kind's cap, modes/show/rules.gd CAPS)
	var podium: Array = []
	if source.get("podium") is Array:
		for point: Variant in source.podium:
			if podium.size() < PODIUM_SPOTS and point is Array and (point as Array).size() >= 3: podium.append(Hazards.vec(point))
	level.podium = podium
	var checkpoints: Array = []
	for entry: Variant in source.get("checkpoints", []):
		if entry is Dictionary: checkpoints.append(volume(Hazards.vec(entry.get("p")), Hazards.vec(entry.get("s"), Vector3(4.0, 4.0, 4.0)), deg_to_rad(float(entry.get("yaw", 0.0)))))
	level.checkpoints = checkpoints
	level.item_boxes = item_boxes(source.get("item_boxes")) # the show's item boxes of a race level (docs/items.md, docs/level-format.md "Item boxes")
	var blocks: Array = []
	var ice: Array = []
	var belts: Array = []
	var slimes: Array = []
	for entry: Variant in source.get("blocks", []):
		if not entry is Dictionary: continue
		var parsed := Hazards.block(entry)
		parsed["tone"] = str(entry.get("tone", "")) if str(entry.get("tone", "")) in TONES else "" # the surface a block of a `world: daylight` level wears (style/race_surfaces.gd)
		blocks.append(parsed)
		if parsed.m == "ice": ice.append(parsed)
		elif parsed.m == "slime" and parsed.k == "wedge": slimes.append(parsed)
		elif parsed.m == "belt" and not (parsed.belt as Vector2).is_zero_approx():
			parsed["carry"] = Hazards.belt_carry(parsed) # the box that carries a courier: the belt plus its downstream rim (Hazards.BELT_RIM)
			belts.append(parsed)
	level.blocks = blocks
	level.ice = ice
	level.slimes = slimes
	level.belts = belts
	var hazards: Array = []
	for entry: Variant in source.get("hazards", []):
		if not entry is Dictionary: continue
		var parsed := Hazards.normalize(entry)
		if parsed.is_empty():
			push_error("GW_LEVEL unknown hazard kind '%s' in level %d" % [str(entry.get("k", "")), number])
			continue
		hazards.append(parsed)
	level.hazards = hazards
	level.slots = slots(source.get("slots", []))
	level.tiles = StepTiles.parse(source.get("tiles")) # step tiles ({} for none, docs/level-format.md)
	level.stage = parse_stage(source.get("stage")) # a tile stage round ({} for none, docs/level-format.md "Stage rounds")
	level.draw = bool(source.get("draw", true)) # false: THE SHOW never draws this show level (its own lobby circle still plays it)
	level.world = str(source.get("world", "")) if str(source.get("world", "")) in WORLDS else "" # "daylight": the stage rounds' daylight and an open-air world without a cage (style/race_world.gd); "" = the cast's world
	level.edge_bumpers = EdgeBumpers.NONE # load_level fills it from levels/edge_bumpers.json (the experiment); a level parsed without that file has none
	return level

## A race level's `item_boxes` rows as the spots of the single boxes (level-local feet, each {p: Vector3, yaw: radians}): a row is {p [x, y, z] its middle on the floor,
## n 1-4 boxes, step m between them (default 1.8), yaw degrees: the row runs along the level's right axis turned by yaw (default 0, across a course that runs towards -Z)}.
const ITEM_ROW_MAX := 4
static func item_boxes(source: Variant) -> Array:
	var result: Array = []
	if not source is Array: return result
	for row: Variant in source:
		if not row is Dictionary: continue
		var middle := Hazards.vec(row.get("p"))
		var count := clampi(int(row.get("n", 1)), 1, ITEM_ROW_MAX)
		var step := float(row.get("step", 1.8))
		var yaw := deg_to_rad(float(row.get("yaw", 0.0)))
		var along := Vector3.RIGHT.rotated(Vector3.UP, yaw)
		for index in count: result.append({"p": middle + along * step * (float(index) - float(count - 1) * 0.5), "yaw": yaw})
	return result

## A tile stage round's `stage` section as typed data ({} for none): `enclosure` ("a" | "b": the sea under the arena, slime or cloud, style/arena_world.gd), `cap` (the round's time
## cap in seconds, 0 for the show's default), `starts` (level-local [x, y, z], the top of the pad each player starts on, in the order players are seated: the first is the middle
## of the pad block; fewer players use the first ones), `ground` (the permanent floor under the last layer: {y (level-local height of its top: what a player who lands on it
## is eliminated at), thick, centre [x, z], size [x, z], tone}; {} for none), `lines` (how many of the sign panels of the enclosure wear which words is the world's own business).
static func parse_stage(source: Variant) -> Dictionary:
	if not source is Dictionary: return {}
	var enclosure := str(source.get("enclosure", "a"))
	var starts: Array[Vector3] = []
	var listed: Variant = source.get("starts", [])
	if listed is Array:
		for entry: Variant in listed:
			if entry is Array and (entry as Array).size() >= 3: starts.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	var ground := {}
	var floor_data: Variant = source.get("ground")
	if floor_data is Dictionary and floor_data.get("size") is Array and (floor_data.size as Array).size() >= 2:
		var middle: Variant = floor_data.get("centre", [0.0, 0.0])
		ground = {"y": float(floor_data.get("y", 0.0)), "thick": maxf(float(floor_data.get("thick", 2.0)), 0.1), "tone": str(floor_data.get("tone", "#5b6ba6")),
			"size": [float(floor_data.size[0]), float(floor_data.size[1])],
			"centre": [float(middle[0]), float(middle[1])] if middle is Array and (middle as Array).size() >= 2 else [0.0, 0.0]}
	return {"enclosure": enclosure if enclosure in ["a", "b"] else "a", "cap": float(source.get("cap", 0.0)), "starts": starts, "ground": ground}

## The frames a team's cast fills (docs/slots.md), level-local: [{id, p (face centre), yaw (radians), size (Vector2 m)}].
static func slots(listed: Variant) -> Array:
	var result: Array = []
	if not listed is Array: return result
	for entry: Variant in listed:
		if not entry is Dictionary or not entry.get("id") is String: continue
		var size: Variant = entry.get("size")
		var face := Vector2(float(size[0]), float(size[1])) if size is Array and size.size() == 2 else Vector2(2.0, 1.0)
		var slot := {"id": str(entry.id), "p": Hazards.vec(entry.get("p")), "yaw": deg_to_rad(float(entry.get("yaw", 0.0))), "size": face.max(Vector2(0.25, 0.25))}
		if str(entry.get("door", "")) != "": slot["door"] = str(entry.door) # a poster door (levels/poster_doors.gd)
		if str(entry.get("ride", "")) != "": slot["ride"] = str(entry.ride) # ... that rides on the `slide` hazard of that id (it moves with it)
		result.append(slot)
	return result

## A box volume as {xf (centre, yaw), inverse, half}: contains() tests a level-local point.
static func _volume(centre: Vector3, size: Vector3, yaw: float) -> Dictionary:
	var xf := Transform3D(Basis(Vector3.UP, yaw), centre)
	return {"xf": xf, "inverse": xf.affine_inverse(), "half": size * 0.5}

static func volume(centre: Vector3, size: Vector3, yaw: float) -> Dictionary:
	return _volume(centre, size, yaw)

static func inside(volume: Dictionary, point: Vector3) -> bool:
	var local: Vector3 = (volume.inverse as Transform3D) * point
	var half: Vector3 = volume.half
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

## The path with a point at least every ROUTE_STEP metres (the look measures distances to it).
static func densify(path: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in path.size():
		if i == 0:
			result.append(path[0])
			continue
		var from := path[i - 1]
		var steps := maxi(ceili(from.distance_to(path[i]) / ROUTE_STEP), 1)
		for step in range(1, steps + 1): result.append(from.lerp(path[i], float(step) / float(steps)))
	return result
