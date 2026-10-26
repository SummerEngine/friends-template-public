extends RefCounted
## The open-air world of a race level that asks for it with `"world": "daylight"` (levels/level_data.gd): the candy world (style/candy_world.gd: slime sea at the kill plane, lime meadow,
## trees, meringue mountains, puffs, cloud wall) under the stage rounds' bright daylight (style/candy_light.gd, switched in by levels/level_environment.gd `set_stage`), but NO rail ring: nothing
## stands around the course, the courier runs on open platforms and a fall is a short fall into the slime, which is where the rules kill (`sea_y`).
## It replaces the party / night backdrop of the level (levels/level_world.gd `_show_backdrop`). Decor only: no collision, no light. Client only.
## The world is centred on the middle of the rectangle around every block, every mover's travel and the path of the level (`footprint`); its lake is that rectangle plus CandyWorld.LAKE_MARGIN,
## so for a long, thin or L-shaped level nothing of the land is ever near the route. Docs: docs/backdrop.md "The race world".
const CandyWorld := preload("res://style/candy_world.gd")

const KEY := "daylight"
const CENTRE_HEIGHT := 0.9    ## m, a courier's centre over its feet (levels/level_world.gd CENTRE_HEIGHT; tools/race_world_check.gd checks they agree)
const MARGIN := 6.0           ## m between the course's bounding rectangle and its ring
const MIN_FLOOR := 2.0        ## m: a block narrower than this in x or z is a post or a wall, not a floor (it does not set the lowest floor)
const VIEW_UP := 8.0          ## m, about where the race camera hangs over the highest block: the mountains' and clouds' angles are set for it

## Whether level `data` (levels/level_data.gd) wants the daylight and this world.
static func wanted(data: Dictionary) -> bool:
	return str(data.get("world", "")) == KEY

## The height of the sea (level-local): where the rules kill, `void_y` (a courier's centre under it) less the centre's height, so a courier dies the moment its feet touch the slime, never
## before (tools/laser_plane.py puts `void_y` a little under the lowest block).
static func sea_y(data: Dictionary) -> float:
	return float(data.void_y) - CENTRE_HEIGHT

## The world of the level `data` standing at `origin`: a Node3D "RaceWorld<NN>" holding the candy world.
static func build(data: Dictionary, origin: Vector3) -> Node3D:
	var frame := footprint(data)
	var rect: Rect2 = frame.rect
	var root := Node3D.new()
	root.name = "RaceWorld%02d" % int(data.number)
	root.position = origin
	var plane := sea_y(data)
	root.add_child(CandyWorld.build({
		"centre": Vector3.ZERO, "course_rect": rect, "floor_y": float(frame.y_low), "world_scale": CandyWorld.default_scale(),
		"seed": int(data.number), "sea": "slime", "sea_y": plane, "view_y": float(frame.y_top) + VIEW_UP - plane}))
	return root

## What the world is built around: {rect (level-local x / z, MARGIN included), y_top (the highest block top), y_low (the lowest floor top, 0 at most)}.
static func footprint(data: Dictionary) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var y_top := -INF
	var y_low := INF
	for block: Dictionary in data.get("blocks", []):
		var xf: Transform3D = block.xf
		var size: Vector3 = block.size
		var top := -INF
		for corner in 8:
			var p := xf * (Vector3(size.x if corner & 1 else -size.x, size.y if corner & 2 else -size.y, size.z if corner & 4 else -size.z) * 0.5)
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
			top = maxf(top, p.y)
		y_top = maxf(y_top, top)
		if size.x >= MIN_FLOOR and size.z >= MIN_FLOOR and str(block.k) != "wedge": y_low = minf(y_low, top)
	for point: Vector3 in data.get("path", PackedVector3Array()):
		lo = lo.min(Vector2(point.x, point.z))
		hi = hi.max(Vector2(point.x, point.z))
		y_top = maxf(y_top, point.y)
	for hazard: Dictionary in data.get("hazards", []):
		var reach := _reach(hazard)
		for point: Vector3 in reach.points:
			lo = lo.min(Vector2(point.x - reach.radius, point.z - reach.radius))
			hi = hi.max(Vector2(point.x + reach.radius, point.z + reach.radius))
	var goal: Dictionary = data.get("goal", {})
	if goal.has("p"):
		var p: Vector3 = goal.p
		var half: Vector3 = goal.size * 0.5
		var spread := maxf(half.x, half.z)
		lo = lo.min(Vector2(p.x - spread, p.z - spread))
		hi = hi.max(Vector2(p.x + spread, p.z + spread))
	if lo.x > hi.x: # a level without a single block or point: a square round the start
		lo = Vector2(-4.0, -4.0)
		hi = Vector2(4.0, 4.0)
	if y_top == -INF: y_top = 0.0
	return {"rect": Rect2(lo, hi - lo).grow(MARGIN), "y_top": y_top, "y_low": minf(y_low if y_low != INF else 0.0, 0.0)}

## Where a hazard can be: {points (the pivot and the far ends of its travel), radius (the horizontal reach of its parts, or of the thing, around each point)}.
static func _reach(hazard: Dictionary) -> Dictionary:
	var pivot: Vector3 = hazard.pivot
	var points: Array[Vector3] = [pivot]
	var radius := 0.0
	for part: Dictionary in hazard.get("parts", []):
		var xf: Transform3D = part.xf
		var size: Vector3 = part.size
		radius = maxf(radius, (xf.origin.length() + size.length() * 0.5))
	match str(hazard.k):
		"slide", "lift": points.append(pivot + (hazard.to as Vector3))
		"laser":
			points.append(pivot + (hazard.to as Vector3))
			points.append(pivot + (hazard.move as Vector3))
		"push", "fire": radius = maxf(radius, (hazard.size as Vector3).length() * 0.5)
		"bumper": radius = maxf(radius, float(hazard.rad))
		"ball":
			for point: Vector3 in hazard.path: points.append(point)
			radius = maxf(radius, float(hazard.rad))
		"cannon":
			points.append(pivot + (hazard.v as Vector3) * float(hazard.life))
			radius = maxf(radius, float(hazard.rad))
	return {"points": points, "radius": radius}
