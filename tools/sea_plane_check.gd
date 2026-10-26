extends SceneTree
## Headless check that the slime kills exactly where it is drawn. For the race levels with `world: daylight` (29-32 and any other real one): the sea of the built world (style/candy_world.gd, the
## node `CandyWorld/Diorama` of the race world, whose y is the sea's height), the height the rules kill at (levels/level_world.gd `zone_at`, found by bisecting a courier's feet over
## the start, the goal and the far corners of the course) and the lowest floor and block of the level agree within 2 cm: a courier dies when its feet touch the slime, never before, and
## no `kill` volume reaches up to a floor or ahead of the sea. For the stage rounds (25-28): the sea lies a hair under the permanent ground slab (a solid floor that fills the rail ring; visual only, the elimination
## stays on the slab's top). Prints GW_SEA lines; exit 1 on a failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer 0.7.3> --headless --audio-driver Dummy --path demo -s $PWD/tools/sea_plane_check.gd
const LevelWorld := preload("res://levels/level_world.gd")
const RaceWorld := preload("res://style/race_world.gd")
const ArenaWorld := preload("res://style/arena_world.gd")

const TOLERANCE := 0.02       ## m
const MIN_DROP := 6.0         ## m the plane lies under the lowest walkable floor at least
const MAX_DROP := 14.0        ## ... and at most

var fails := 0
var checks := 0

func _initialize() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		print("GW_SEA FAILED timed out")
		quit(1))
	run.call_deferred()

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("GW_SEA   FAIL ", text)

## The feet height (world) at which `zone_at` turns to "kill" above (x, z): bisection between a point far under and far over the course.
func kill_height(world: Node3D, k: int, at: Vector3) -> float:
	var low := at.y - 200.0
	var high := at.y + 200.0
	if world.zone_at(k, Vector3(at.x, low, at.z)) != "kill": return NAN
	if world.zone_at(k, Vector3(at.x, high, at.z)) == "kill": return NAN
	for step in 40:
		var middle := (low + high) * 0.5
		if world.zone_at(k, Vector3(at.x, middle, at.z)) == "kill": low = middle
		else: high = middle
	return high

func run() -> void:
	var world: Node3D = LevelWorld.new()
	world.level_dir = "res://levels"
	root.add_child(world)
	await world.build("local")
	var races := 0
	var stages := 0
	for k in world.level_count():
		var data: Dictionary = world._levels[k].data
		var number := int(data.number)
		var origin: Vector3 = world.level_origin(k)
		world.set_active_level(k)
		var staged := not (data.stage as Dictionary).is_empty()
		if staged:
			stages += 1
			check_stage(world, data, origin)
			continue
		if not RaceWorld.wanted(data): continue
		races += 1
		var race: Node3D = world.get_node_or_null("RaceWorld%02d" % number)
		var plane := race.get_node_or_null("CandyWorld/Diorama") as Node3D if race != null else null
		expect(plane != null and plane.get_node_or_null("Sea") != null, "level %d: the race world has a sea" % number)
		if plane == null: continue
		var frame := RaceWorld.footprint(data)
		var plane_y := plane.global_position.y - origin.y # level-local
		var floor_top: float = frame.y_low
		var bottom := 0.0
		for block: Dictionary in data.blocks:
			var xf: Transform3D = block.xf
			var size: Vector3 = block.size
			for corner in 8:
				var p := xf * (Vector3(size.x if corner & 1 else -size.x, size.y if corner & 2 else -size.y, size.z if corner & 4 else -size.z) * 0.5)
				bottom = minf(bottom, p.y)
		# the kill height the rules use, from several columns of the course
		var rect: Rect2 = frame.rect
		var columns: Array[Vector3] = [data.start, data.goal.p, Vector3(rect.position.x, 0.0, rect.position.y), Vector3(rect.end.x, 0.0, rect.end.y), Vector3(rect.get_center().x, 0.0, rect.get_center().y)]
		var seen := {}
		for column in columns:
			var feet := origin + Vector3(column.x, 0.0, column.z)
			var killed := kill_height(world, k, feet)
			expect(not is_nan(killed), "level %d: a courier far under column %s dies, one far over does not" % [number, column])
			if is_nan(killed): continue
			seen[snappedf(killed, 0.001)] = true
			expect(absf(killed - plane.global_position.y) <= TOLERANCE, "level %d: the rules kill at feet y %.3f, the sea is at %.3f (column %s)" % [number, killed - origin.y, plane_y, column])
		print("GW_SEA level %d: sea y %.3f, kill heights %s, lowest floor top %.2f, lowest underside %.2f, drop %.2f m" % [number, plane_y, seen.keys(), floor_top, bottom, floor_top - plane_y])
		expect(data.kill.is_empty(), "level %d: no kill volume besides the plane (%d)" % [number, data.kill.size()])
		expect(floor_top - plane_y >= MIN_DROP and floor_top - plane_y <= MAX_DROP, "level %d: the sea lies %.2f m under the lowest floor (%s to %s wanted)" % [number, floor_top - plane_y, MIN_DROP, MAX_DROP])
		expect(bottom <= plane_y and bottom >= plane_y - 2.0, "level %d: the lowest block's underside (%.2f) reaches into the sea (%.2f) by at most 2 m, so no pillar floats over the slime" % [number, bottom, plane_y])
		expect(RaceWorld.CENTRE_HEIGHT == LevelWorld.CENTRE_HEIGHT, "the race world and the rules agree on the courier's centre height")
		# a courier standing on the start is not killed, one standing on the lowest floor neither
		expect(world.zone_at(k, origin + data.start) == "", "level %d: the start is not a kill zone" % number)
	expect(races >= 2, "the race levels 29 and 30 are there (%d)" % races)
	expect(stages >= 4, "the stage rounds 25-28 are there (%d)" % stages)
	world.queue_free()
	await process_frame
	print("GW_SEA %s: %d checks, %d failures (%d race levels, %d stage rounds)" % ["OK" if fails == 0 else "FAILED", checks, fails, races, stages])
	quit(1 if fails > 0 else 0)

## A stage round: the sea lies a hair under the ground slab's bottom (visual only: the slab, a solid floor, hides it inside the rail ring).
func check_stage(world: Node3D, data: Dictionary, origin: Vector3) -> void:
	var number := int(data.number)
	var arena: Node3D = world.get_node_or_null("ArenaWorld%02d" % number)
	var plane := arena.get_node_or_null("CandyWorld/Diorama") as Node3D if arena != null else null
	expect(plane != null and plane.get_node_or_null("Sea") != null, "level %d: the stage round has a sea" % number)
	if plane == null: return
	var ground: Dictionary = data.stage.ground
	var top := float(ground.y)
	var bottom := top - float(ground.thick)
	var plane_y := plane.global_position.y - origin.y
	expect(plane_y < bottom and plane_y > bottom - 0.2, "level %d: the sea (%.3f) lies a hair under the ground slab's bottom (%.2f)" % [number, plane_y, bottom])
	expect(absf(plane_y - ArenaWorld.sea_level(data, top)) <= TOLERANCE, "level %d: the sea follows the level's ground data" % number)
	print("GW_SEA level %d (stage): sea y %.3f, ground top %.2f" % [number, plane_y, top])
