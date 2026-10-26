extends RefCounted
## GHOST PIGEON (docs/pigeon.md): how a pigeon flies and where it may fly. Pure functions, no nodes and no random numbers: the authority (pigeon_rules.gd) steps every bird with them and the
## owner's own client steps ITS bird with the same ones (modes/show/pigeon/pigeon_view.gd, prediction: the owner sees no lag, the authority still decides where the bird is).
const CourseSection := preload("res://course_section.gd")

const ACCEL := 9.0 ## 1/s: the velocity eases to the wanted one this fast (a pigeon turns and stops softly)
const HOVER := 1.2 ## m a bird keeps over the floor under it
const CEILING := 12.0 ## m over the top floor (a tile round) the ceiling is
const ROUTE_PAD := 16.0 ## m the course's route may be strayed from sideways
const ROUTE_CEILING := 22.0 ## m over the highest point of a race's route
const WALL := 1.5 ## m kept from the arena's wall
const FLOOR_PROBE := 3.0

## One step: velocity eases towards `dir` (world x/z, length up to 1) at `speed` and `climb` (-1 down .. 1 up) at `climb_speed`, then the box `box` ({lo, hi}) and the floor under the
## bird (`floor_y`, NAN for none) keep it in. Returns {pos, vel}.
static func step(pos: Vector3, vel: Vector3, dir: Vector2, climb: float, dt: float, box: Dictionary, floor_y: float, speed: float, climb_speed: float) -> Dictionary:
	var want := Vector3(dir.x * speed, climb * climb_speed, dir.y * speed)
	vel = vel.lerp(want, 1.0 - exp(-ACCEL * dt))
	pos += vel * dt
	var lo: Vector3 = box.lo
	var hi: Vector3 = box.hi
	var bottom := lo.y if is_nan(floor_y) else maxf(lo.y, floor_y + HOVER)
	if pos.x < lo.x or pos.x > hi.x:
		pos.x = clampf(pos.x, lo.x, hi.x)
		vel.x = 0.0
	if pos.z < lo.z or pos.z > hi.z:
		pos.z = clampf(pos.z, lo.z, hi.z)
		vel.z = 0.0
	if pos.y < bottom or pos.y > hi.y:
		pos.y = clampf(pos.y, bottom, maxf(hi.y, bottom))
		vel.y = 0.0
	return {"pos": pos, "vel": vel}

## The way a bird faces (radians, 0 faces -Z, as the couriers do) when it flies at `vel`, else `yaw` as it was.
static func facing(vel: Vector3, yaw: float) -> float:
	return atan2(-vel.x, -vel.z) if Vector2(vel.x, vel.z).length() > 0.6 else yaw

## The flight box of level `level` ({lo, hi, ground, stage}, world): a tile stage round is the ground floor's rectangle (the arena's walls) from over the ground to a ceiling over the top floor;
## every other level is its route and goal with ROUTE_PAD m around, up to ROUTE_CEILING m over its highest point. `levels` is the level world (levels/level_world.gd), the same on every machine.
static func bounds(levels, level: int) -> Dictionary:
	var origin: Vector3 = levels.level_origin(level)
	var stage: Dictionary = CourseSection.level_stage(level)
	var ground: Variant = stage.get("ground")
	if ground is Dictionary and (ground as Dictionary).has("y"):
		var centre: Array = (ground as Dictionary).get("centre", [0.0, 0.0])
		var size: Array = (ground as Dictionary).get("size", [60.0, 60.0])
		var tops: PackedFloat32Array = levels.tile_floors(level)
		var top := float(tops[0]) if tops.size() > 0 else origin.y + 14.0
		var cx := origin.x + float(centre[0])
		var cz := origin.z + float(centre[1])
		var half_x := float(size[0]) * 0.5 - WALL
		var half_z := float(size[1]) * 0.5 - WALL
		var floor_y := float((ground as Dictionary).y) + origin.y
		return {"lo": Vector3(cx - half_x, floor_y + 2.5, cz - half_z), "hi": Vector3(cx + half_x, top + CEILING, cz + half_z), "ground": floor_y, "stage": true, "top": top}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var points: Array = Array(levels.route(level))
	var goal: Dictionary = levels.goal_volume(level)
	if not goal.is_empty(): points.append(goal.p)
	for point: Vector3 in points:
		lo = lo.min(point)
		hi = hi.max(point)
	if points.is_empty(): return {"lo": origin - Vector3(20.0, 0.0, 20.0), "hi": origin + Vector3(20.0, ROUTE_CEILING, 20.0), "ground": origin.y, "stage": false, "top": origin.y}
	return {"lo": Vector3(lo.x - ROUTE_PAD, lo.y - 2.0, lo.z - ROUTE_PAD), "hi": Vector3(hi.x + ROUTE_PAD, hi.y + ROUTE_CEILING, hi.z + ROUTE_PAD), "ground": lo.y - 2.0, "stage": false, "top": hi.y}

## Where a pigeon starts when its player went out at `at` (the courier's feet): over the spot in a race, over the arena's top floor in a tile round (the feet are on the ground floor, far below) and
## there kept STAGE_MARGIN metres off the arena's walls, so its camera has room behind it.
const STAGE_MARGIN := 12.0
static func start_point(box: Dictionary, at: Vector3) -> Vector3:
	var lo: Vector3 = box.lo
	var hi: Vector3 = box.hi
	var y := float(box.top) + 4.0 if bool(box.stage) else at.y + 2.5
	var margin := STAGE_MARGIN if bool(box.stage) and hi.x - lo.x > 3.0 * STAGE_MARGIN and hi.z - lo.z > 3.0 * STAGE_MARGIN else 0.0
	return Vector3(clampf(at.x, lo.x + margin, hi.x - margin), clampf(y, lo.y, hi.y), clampf(at.z, lo.z + margin, hi.z - margin))
