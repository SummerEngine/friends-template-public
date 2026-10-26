extends SceneTree
## Check of the stage tiles (levels/step_tiles.gd with `"style": "stage"`, levels 25-28), numbers only, headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --path demo -s $PWD/tools/stage_tiles_check.gd
## The layers (grid, counts, spacing, tones, one body per floor with a shape owner per tile), the colliders against the drawn tile (the same size within 1 cm, no gap between
## neighbours: a ray every centimetre across every seam lands on the top), the pads and the start spots, the ground under the last layer (its collider, its look, nothing kills
## before it), the step clock of a wrapped level (a stepped tile whitens and sinks at once, holds weight for its delay and is gone in ONE frame at the right level clock whatever the
## clock, a late joiner agrees, a settled tile stays gone when the byte's window comes round), the exit of a tile in the look (no fall, no shrink), the state pieces (the worst state
## keeps every byte field at 240 B), and the cost: the build time of the biggest level, set_steps and pose per tick with every tile stepped. Prints STAGE_TILES ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const StageLook := preload("res://style/stage_tile_look.gd")
const SquareGrid := preload("res://levels/square_grid.gd")
const HexGrid := preload("res://levels/hex_grid.gd")

const LEVELS := [24, 25, 26, 27] ## 0-based: level_25 .. level_28
## grid, FULL floors (the start layer of 12 groups, 3 x 3 square tiles or a flower of 7 hexagons, comes over them), tiles per full floor (min, max), pitch, floor gap, tones of the full floors from the top
const SHAPES := {
	24: ["square", 4, 484, 484, 3.5, 14.3, ["#1aa8f4", "#b02da2", "#1aa8f4", "#b02da2"]],
	25: ["hex", 8, 650, 720, 4.06, 14.3, ["#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00"]],
	26: ["square", 4, 484, 484, 3.5, 14.3, ["#1aa8f4", "#b02da2", "#1aa8f4", "#b02da2"]],
	27: ["hex", 8, 650, 720, 4.06, 14.3, ["#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00", "#1aa8f4", "#b02da2", "#ffad00"]],
}
const START_TILES := {"square": 108, "hex": 84} ## the start layer: 12 groups of 3 x 3 square tiles, or of 7 hexagons (a centre and its six neighbours), in the pad tone of the shape
const START_TONES := {"square": "#ffad00", "hex": "#59e4e4"}
const FULL := 1 ## the index of the first full floor (floor 0 is the start layer, one gap over it)
const ALL_TILES := 1 | 16 | StepTiles.TILE_LAYERS_ALL ## a ray that means "any tile or the ground"
const BUILD_LIMIT_MS := 2000.0 ## the largest stage level builds (collision and look) in about 2 s

var failures := 0
var holder: Node3D

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STAGE_TILES ", "ok   " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("STAGE_TILES FAIL timed out")
		print("STAGE_TILES ok=false")
		quit(1))
	run.call_deferred()

func make_world(role: String, level: int) -> Node3D:
	var world := LevelWorld.new()
	holder.add_child(world)
	await world.build(role)
	world.set_active_level(level)
	world.set_clock(0.0)
	return world

func ray_y(world: Node3D, level: int, local: Vector3, mask := ALL_TILES, top := 3.0) -> float:
	var origin: Vector3 = world.level_origin(level)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin + local + Vector3(0.0, top, 0.0), origin + local + Vector3(0.0, -200.0, 0.0), mask))
	return hit.position.y - origin.y if not hit.is_empty() else NAN

func tile_index(data: Dictionary, x: float, z: float, floor_index: int) -> int:
	for index in (data.tiles as Array).size():
		var tile: Dictionary = data.tiles[index]
		if int(tile.floor) == floor_index and absf((tile.p as Vector3).x - x) < 0.01 and absf((tile.p as Vector3).z - z) < 0.01: return index
	return -1

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	var authority: Node3D = await make_world("authority", 24)
	var client: Node3D = await make_world("local", 24)
	for level: int in LEVELS:
		await check_level(authority, client, level)
		check_ground(authority, client, level)
	await check_exit(client)
	check_state_pieces(authority)
	check_cost(authority)
	print("STAGE_TILES ok=", failures == 0)
	quit(0 if failures == 0 else 1)

func check_level(authority: Node3D, client: Node3D, level: int) -> void:
	var name := "level %d" % (level + 1)
	authority.set_active_level(level)
	client.set_active_level(level)
	authority.set_clock(0.0)
	var entry: Dictionary = authority._levels[level]
	var tiles: Dictionary = entry.data.tiles
	var stage: Dictionary = entry.data.stage
	var shape: Array = SHAPES[level]
	var square: bool = shape[0] == "square"
	var pitch := float(tiles.pitch)
	var thick := float(tiles.thick)
	var count: int = (tiles.tiles as Array).size()
	var stepper: StepTiles = entry.tiles
	check(str(tiles.grid) == shape[0] and str(tiles.style) == "stage" and bool(tiles.wrap) and bool(tiles.flat) == not square, "%s: a %s stage round, wrapped step bytes" % [name, shape[0]])
	check((tiles.floors as Array).size() == int(shape[1]) + 1, "%s: a start layer and %d full layers (%d floors)" % [name, shape[1], (tiles.floors as Array).size()])
	check(not stage.is_empty() and str(stage.enclosure) in ["a", "b"] and float(stage.cap) >= 75.0 and float(stage.cap) <= 150.0, "%s: stage section (enclosure %s, cap %s s)" % [name, str(stage.get("enclosure")), str(stage.get("cap"))])
	check(count <= StepTiles.MAX_PACKED_TILES, "%s: %d tiles, a state byte each (at most %d, packed on the wire)" % [name, count, StepTiles.MAX_PACKED_TILES])
	check(absf(pitch - float(shape[4])) < 0.001 and absf(thick - 0.5) < 0.001, "%s: pitch %.2f m, thickness %.2f m" % [name, pitch, thick])
	var gaps_ok := true
	var tones_ok := true
	var counts_ok := true
	var per_floor := []
	var previous := INF
	for floor_index in (tiles.floors as Array).size():
		var layout: Dictionary = tiles.floors[floor_index]
		var top := float(layout.y)
		if previous != INF and absf((previous - top) - float(shape[5])) > 0.011: gaps_ok = false
		previous = top
		tones_ok = tones_ok and str(layout.tone).to_lower() == (START_TONES[shape[0]] if floor_index == 0 else str((shape[6] as Array)[floor_index - 1]))
		var here := (tiles.tiles as Array).filter(func(tile: Dictionary) -> bool: return int(tile.floor) == floor_index).size()
		per_floor.append(here)
		counts_ok = counts_ok and ((here == int(START_TILES[shape[0]])) if floor_index == 0 else (here >= int(shape[2]) and here <= int(shape[3])))
	check(gaps_ok and absf(float(tiles.floors[FULL].y)) < 0.001 and absf(float(tiles.floors[0].y) - float(shape[5])) < 0.011, "%s: layers %.2f m apart, the first full one at y 0, the start layer one gap over it" % [name, shape[5]])
	check(tones_ok, "%s: one tone each, top to bottom" % name)
	check(counts_ok, "%s: tiles per layer %s (%d..%d)" % [name, str(per_floor), shape[2], shape[3]])
	# one body per floor, a shape owner per tile, on the floor's own collision layer
	var bodies_ok := stepper.tile_bodies.size() == (tiles.floors as Array).size()
	for floor_index in stepper.tile_bodies.size():
		var body: StaticBody3D = stepper.tile_bodies[floor_index]
		bodies_ok = bodies_ok and body.collision_layer == (StepTiles.TILE_LAYER_BASE << floor_index) and body.get_shape_owners().size() == int(per_floor[floor_index])
	check(bodies_ok, "%s: one static body per floor on layer TILE_LAYER_BASE << floor, a shape owner per tile (no node per tile)" % name)
	# neighbours touch: a plain tile of the top layer has 4 (square) / 6 (hex) neighbours one pitch away
	var probe := Vector2(0.0, -pitch * 6.0) if not square else Vector2(-pitch * 0.5, pitch * 4.5) # a plain tile of the top layer with plain neighbours
	var middle := tile_index(tiles, probe.x, probe.y, FULL)
	var around := []
	for other: Dictionary in tiles.tiles:
		if int(other.floor) == FULL and middle >= 0 and absf((other.p as Vector3).distance_to(tiles.tiles[middle].p) - pitch) < 0.01: around.append(other.p)
	check(middle >= 0 and around.size() == (4 if square else 6), "%s: a tile has %d neighbours one pitch away (%d)" % [name, 4 if square else 6, around.size()])
	# the drawn tile and the collider (a plain tile of the top layer)
	var mesh: ArrayMesh = StageLook._tile_mesh(square, pitch, thick, not square)
	var box := mesh.get_aabb()
	var body_size := collider_size(stepper, middle)
	check(absf(body_size.y - thick) < 0.001 and absf(box.size.y - thick) < 0.001 and absf(box.position.y + thick) < 0.001, "%s: collider and drawn tile are %.2f m thick, the top at the floor's y" % [name, thick])
	check(absf(body_size.x - box.size.x) <= 0.011 and absf(body_size.z - box.size.z) <= 0.011, "%s: the collider is the drawn tile within 1 cm (collider %.3f x %.3f, tile %.3f x %.3f)" % [name, body_size.x, body_size.z, box.size.x, box.size.z])
	# no gap between tiles: a ray every centimetre across the seam with every neighbour
	await frames(2)
	var middle_at: Vector3 = tiles.tiles[middle].p
	var seam_ok := true
	for neighbour: Vector3 in around:
		var way := Vector2(neighbour.x - middle_at.x, neighbour.z - middle_at.z).normalized()
		var seam_middle := Vector2(middle_at.x + neighbour.x, middle_at.z + neighbour.z) * 0.5
		for step in 60:
			var along := -0.3 + 0.6 * step / 59.0
			var at := seam_middle + way * along
			if not absf(ray_y(authority, level, Vector3(at.x, 0.0, at.y))) <= 0.001: seam_ok = false
	check(seam_ok, "%s: a ray every centimetre across each of %d seams lands on the top (no gap, no step)" % [name, around.size()])
	# the rim: nothing beside the arena down to the ground
	var rim := 0.0
	for tile: Dictionary in tiles.tiles: rim = maxf(rim, maxf(absf((tile.p as Vector3).x), absf((tile.p as Vector3).z)))
	var beyond := ray_y(authority, level, Vector3(rim + pitch, 0.0, 0.0), StepTiles.TILE_LAYERS_ALL)
	check(is_nan(beyond), "%s: no tile beside the rim (a ray %.1f m out)" % [name, rim + pitch])
	# the start layer: 12 start spots on the middle tile of 12 groups (3 x 3 squares, a hexagon and its six neighbours), the first in the middle of the block, every group a jump from the next
	var starts: Array = stage.starts
	var start_y := float(tiles.floors[0].y)
	var pads_ok := starts.size() == 12
	for start: Vector3 in starts:
		var found := tile_index(tiles, start.x, start.z, 0)
		pads_ok = pads_ok and found >= 0 and absf(float(tiles.tiles[found].p.y) - start.y) < 0.001 and absf(start.y - start_y) < 0.001
		for other: Vector3 in starts:
			if other != start and Vector2(other.x - start.x, other.z - start.z).length() < 3.0 * pitch: pads_ok = false
	check(pads_ok, "%s: 12 start spots on the start layer (y %.2f), %d tiles in it" % [name, start_y, per_floor[0]])
	var pad_hit := ray_y(authority, level, Vector3((starts[0] as Vector3).x, start_y, (starts[0] as Vector3).z))
	check(absf(pad_hit - start_y) < 0.001, "%s: the first start is a real tile top at %.3f" % [name, pad_hit])
	var under_ok := true # a player standing on a pad stands on a tile (the rules step it, and a courier that stands still there is not hanging)
	for start: Vector3 in starts:
		var found := tile_index(tiles, start.x, start.z, 0)
		var under: Array = authority.tiles_under(level, authority.level_origin(level) + start)
		under_ok = under_ok and under.has(found)
	check(under_ok, "%s: every start spot is a tile for tiles_under (a pad is stepped like any tile)" % name)
	# a tile's exit: step it at several clocks across the wrap window; it sinks at once, holds weight for its delay and is gone in one frame
	var delay := float((tiles.kinds as Dictionary)["n"].delay)
	var victim := tile_index(tiles, middle_at.x + (pitch if square else 0.0), middle_at.z + (0.0 if square else pitch), FULL)
	var victim_at: Vector3 = tiles.tiles[victim].p
	var timing_ok := true
	var sink_ok := true
	var late_ok := true
	var look: Object = (client._levels[level].tiles as StepTiles).look
	for stepped_clock: float in [4.0, 12.34, 49.99, 61.0, 100.0, 139.9]:
		authority.set_clock(stepped_clock)
		client.set_clock(stepped_clock)
		var bytes := PackedByteArray()
		bytes.resize(count)
		bytes[victim] = authority.tile_stamp(level)
		authority.set_tile_steps(level, bytes)
		client.set_tile_steps(level, bytes, true)
		var clocks := [0.03, delay * 0.5, delay - 0.06, delay + 0.04, delay + StepTiles.STAGE_FALL + 0.05, delay + 3.0, delay + 20.0]
		var expected_gone := [false, false, false, true, true, true, true]
		for at in clocks.size():
			authority.set_clock(stepped_clock + float(clocks[at]))
			client.set_clock(stepped_clock + float(clocks[at]))
			if at == 5 or at == 6: # the authority settles a fallen tile before its stamp comes round again
				if authority._levels[level].tiles.is_settled(victim, authority.clock) and bytes[victim] != StepTiles.SETTLED:
					bytes[victim] = StepTiles.SETTLED
					authority.set_tile_steps(level, bytes)
					client.set_tile_steps(level, bytes, true)
			await frames(1)
			var solid: bool = not authority.tile_gone(level, victim)
			var ray := ray_y(authority, level, Vector3(victim_at.x, 0.0, victim_at.z))
			var standing: bool = absf(ray - victim_at.y) <= 0.001 # a warned tile sinks in the look only: the collider keeps its height until the tile is gone
			if solid == expected_gone[at] or standing == expected_gone[at]:
				timing_ok = false
				print("STAGE_TILES   timing: stepped at %.2f, +%.2f s: solid %s ray %.3f standing %s (expected gone %s)" % [stepped_clock, clocks[at], solid, ray, standing, expected_gone[at]])
			if not expected_gone[at] and not standing: sink_ok = false
			if authority.tile_gone(level, victim) != client.tile_gone(level, victim): late_ok = false
			if look != null and not expected_gone[at] and look._last[victim] != 1: sink_ok = false
			if look != null and expected_gone[at] and look._last[victim] != 3: sink_ok = false
		bytes.fill(0)
		authority.set_tile_steps(level, bytes)
		client.set_tile_steps(level, bytes, true)
	check(timing_ok, "%s: a stepped tile holds weight for its delay (%.2f s), then collision is off in the same frame, whatever level clock it was stepped at (4 .. 139.9 s: the byte wraps)" % [name, delay])
	check(sink_ok, "%s: from the step on the tile is drawn lower (SINK_SHARE of a thickness) and pale while its collider keeps its height, until it is gone" % name)
	check(late_ok, "%s: the authority world and a client world agree on which tile is gone at every clock" % name)
	# a tile that is stepped on goes out of the physics world: a courier-sized shape cast against the top floor's layer finds nothing there
	authority.set_clock(0.0)
	client.set_clock(0.0)

## The size of tile `index`'s collider (one shape owner of its floor's body).
func collider_size(stepper: StepTiles, index: int) -> Vector3:
	var floor_body: StaticBody3D = stepper.tile_bodies[int((stepper.data.tiles[index] as Dictionary).floor)]
	var shape: Shape3D = floor_body.shape_owner_get_shape(stepper._owner[index], 0)
	if shape is BoxShape3D: return (shape as BoxShape3D).size
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point: Vector3 in (shape as ConvexPolygonShape3D).points:
		low = low.min(point)
		high = high.max(point)
	return high - low

## The ground of a stage round: a solid box one layer gap under the last layer (its top `stage.ground.y`), drawn as a flat slab; nothing kills before it.
func check_ground(world: Node3D, drawn: Node3D, level: int) -> void:
	var name := "level %d" % (level + 1)
	var entry: Dictionary = world._levels[level]
	var tiles: Dictionary = entry.data.tiles
	var ground: Dictionary = entry.data.stage.ground
	var last := float(tiles.floors[(tiles.floors as Array).size() - 1].y)
	var gap := float(SHAPES[level][5])
	check(not ground.is_empty() and absf((last - float(ground.y)) - gap) < 0.011, "%s: the ground's top (y %.2f) is one layer gap (%.2f m) under the last layer" % [name, float(ground.get("y", NAN)), gap])
	var stepper: StepTiles = entry.tiles
	check(stepper.ground != null and stepper.ground.collision_layer == StepTiles.LAYER, "%s: the ground is a solid body" % name)
	var size: Array = ground.size
	var reach_ok := true
	var top_ok := true
	for corner: Vector2 in [Vector2.ZERO, Vector2(-0.45, 0.45), Vector2(-0.45, -0.45), Vector2(0.0, 0.48), Vector2(0.0, -0.48), Vector2(-0.48, 0.0)]: # the -x half of the wall-wide slab (its +x edge is not probed)
		var at := Vector3(float(size[0]) * corner.x, 0.0, float(size[1]) * corner.y)
		var hit := ray_y(world, level, at, 1)
		top_ok = top_ok and absf(hit - float(ground.y)) < 0.001
		var origin: Vector3 = world.level_origin(level)
		reach_ok = reach_ok and world.zone_at(level, origin + Vector3(at.x, float(ground.y) + 0.02, at.z)) == "" and world.zone_at(level, origin + Vector3(at.x, float(ground.y) - 0.3, at.z)) == ""
	check(top_ok, "%s: a ray lands on the ground's top over the arena" % name)
	check(reach_ok, "%s: no kill volume and no void on or inside the ground (a faller is only out once it lands)" % name)
	var below: Vector3 = world.level_origin(level) + Vector3(0.0, float(ground.y) - float(ground.thick) - 1.5, 0.0)
	check(world.zone_at(level, below) == "kill" or world.zone_at(level, below + Vector3(0.0, -12.0, 0.0)) == "kill", "%s: under the ground the safety net kills" % name)
	var slab: Node = drawn._levels[level].root.get_node_or_null("StageGroundLook")
	var floor_tiles: Node = drawn._levels[level].root.get_node_or_null("StageGroundTiles")
	var floor_count: int = (floor_tiles as MultiMeshInstance3D).multimesh.instance_count if floor_tiles is MultiMeshInstance3D else 0
	var cell := float(tiles.pitch) * float(tiles.pitch) * (1.0 if str(tiles.grid) == "square" else 0.8660254)
	check(floor_count > 100 and floor_count * cell >= 0.6 * float(size[0]) * float(size[1]) and floor_count * cell <= float(size[0]) * float(size[1]), "%s: the ground is drawn as a solid floor of %d tiles that fill the slab (%.0f of %.0f m2)" % [name, floor_count, floor_count * cell, float(size[0]) * float(size[1])])

## The exit of a tile in the look: the stage tile has no fall (data.fall 0, no fall constants) and goes from standing to sunk and pale to gone, never through a drop or a shrink.
func check_exit(client: Node3D) -> void:
	check(StepTiles.STAGE_FALL == 0.0 and not (StageLook as GDScript).get_script_constant_map().has("FALL_TIME") and not (StageLook as GDScript).get_script_constant_map().has("FALL_GRAVITY"), "the stage exit has no fall time and no drop")
	var level := 24
	client.set_active_level(level)
	var stepper: StepTiles = client._levels[level].tiles
	check(float(stepper.data.fall) == 0.0, "a stage level's tiles take no time to go (data.fall %.2f)" % float(stepper.data.fall))
	var look: Object = stepper.look
	check(look != null, "the client world draws the stage look")
	if look == null: return
	var victim := 100
	while str(stepper.data.tiles[victim].kind) != "n" or int(stepper.data.tiles[victim].floor) != 0: victim += 1 # a plain tile of the top layer (not a pad: those are stretched)
	var at: Vector3 = stepper.data.tiles[victim].p
	var thick := float(stepper.data.thick)
	var modes_seen := {}
	var bytes := PackedByteArray()
	bytes.resize(stepper.tile_count())
	client.set_clock(20.0)
	bytes[victim] = client.tile_stamp(level)
	client.set_tile_steps(level, bytes, true)
	var stepped := stepper.stepped_at(victim, 20.0)
	var shape_ok := true
	for step in 81:
		var clock := stepped - 0.05 + 0.0125 * step # 12.5 ms steps from before the step to well after the exit
		client.set_clock(clock)
		await frames(1)
		var mode := int(look._last[victim])
		modes_seen[mode] = true
		var delay := 0.5
		var expected := 0 if clock < stepped - 0.001 else (1 if clock < stepped + delay - 0.001 else (3 if clock > stepped + delay + 0.001 else mode))
		if mode != expected:
			shape_ok = false
			print("STAGE_TILES   exit: at %+.4f s mode %d, expected %d" % [clock - stepped, mode, expected])
	# the poses the look gives them (a headless renderer does not hand a multimesh's instances back: the look's own functions)
	var standing: Transform3D = look._stand(victim)
	var sunk: Transform3D = look._stand(victim, look._sink)
	var gone: Transform3D = look._stand(victim, look._sink, StageLook.GONE_SCALE)
	var poses_ok: bool = standing.origin.is_equal_approx(at) and standing.basis.get_scale().is_equal_approx(Vector3.ONE) and absf(sunk.origin.y - (at.y - thick * StageLook.SINK_SHARE)) < 0.0001 and sunk.origin.x == at.x and sunk.origin.z == at.z and sunk.basis.get_scale().is_equal_approx(Vector3.ONE)
	poses_ok = poses_ok and gone.basis.get_scale().x < 0.001 and gone.origin.is_equal_approx(sunk.origin)
	check(poses_ok, "a stepped tile is drawn SINK_SHARE of a thickness lower at the same size, a gone one scaled to nothing where it sat (no drop)")
	check(shape_ok and not modes_seen.has(2), "stepped: sunk and pale at once, held for its delay, then gone in one frame (modes seen %s, none a fall)" % str(modes_seen.keys()))
	bytes.fill(0)
	client.set_tile_steps(level, bytes, true)
	client.set_clock(0.0)
	check_fade(client, level)

## The floors the view hides fade out and back over StageLook.FADE_TIME (a whole-frame pop otherwise): with a frame time they are in between for a few frames wearing their own
## dither material, then gone (not visible) or whole (the plain material); with no frame time (a fixed shot, a check) they change at once.
func check_fade(client: Node3D, level: int) -> void:
	var stepper: StepTiles = client._levels[level].tiles
	var look: Object = stepper.look
	var nodes: Array = look._nodes
	var dt := 1.0 / 60.0
	client.ghost_tiles(level, INF, 0.0, dt)
	var whole: bool = look.is_whole(0) and (nodes[0] as GeometryInstance3D).visible and (nodes[0] as GeometryInstance3D).material_override == null
	var top: float = float(stepper.data.floors[1].y) + (client.level_origin(level) as Vector3).y # standing on the second floor: the first is over the view
	var steps_out := 0
	var in_between := 0
	var dithered := false
	for i in 40:
		client.ghost_tiles(level, -INF, top, dt)
		var amount: float = look._fade[0]
		if amount > 0.0 and amount < 1.0:
			in_between += 1
			dithered = dithered or (nodes[0] as GeometryInstance3D).material_override == look._fade_materials[0]
		steps_out += 1
		if amount <= 0.0: break
	var gone: bool = not (nodes[0] as GeometryInstance3D).visible and look.is_ghosted(0)
	var frames_out := steps_out
	steps_out = 0
	for i in 40:
		client.ghost_tiles(level, INF, top, dt)
		steps_out += 1
		if look._fade[0] >= 1.0: break
	var back: bool = look.is_whole(0) and (nodes[0] as GeometryInstance3D).visible and (nodes[0] as GeometryInstance3D).material_override == null
	check(whole and in_between >= 8 and dithered and gone and absf(float(frames_out) * dt - StageLook.FADE_TIME) < 0.03 and back and absf(float(steps_out) * dt - StageLook.FADE_TIME) < 0.03, "level %d: a floor the view hides fades out in %d frames (%.2f s) on the dither material and is gone, and fades back in %d frames to the plain material (whole %s, in between %d frames, dithered %s)" % [level + 1, frames_out, float(frames_out) * dt, steps_out, str(whole), in_between, str(dithered)])
	client.ghost_tiles(level, -INF, top)
	var at_once: bool = not (nodes[0] as GeometryInstance3D).visible and look._fade[0] == 0.0
	client.ghost_tiles(level, INF, 0.0)
	check(at_once and look.is_whole(0) and (nodes[0] as GeometryInstance3D).visible, "level %d: with no frame time the floors are hidden and shown at once (a fixed shot)" % (level + 1))

## The state of the biggest stage level goes out in pieces of at most 240 B and joins back: the worst state has every tile gone for good (the bitmap) and the longest list of tiles
## with a clock still to read that a state holds.
func check_state_pieces(world: Node3D) -> void:
	var biggest := 0
	for level: int in LEVELS: biggest = maxi(biggest, world.tile_count(level))
	var live_most := StepTiles.LIVE_PIECE / 3 * StepTiles.MAX_PIECES
	var bytes := PackedByteArray()
	bytes.resize(biggest)
	bytes.fill(StepTiles.SETTLED)
	for index in live_most: bytes[(index * 37) % biggest] = index % 250 + 1 # 320 distinct tiles
	var live_count := 0
	for index in biggest: if bytes[index] != StepTiles.SETTLED: live_count += 1
	var fields := StepTiles.pack_state(bytes)
	var sizes_ok := true
	var largest := 0
	for key: String in fields:
		sizes_ok = sizes_ok and fields[key] is PackedByteArray and (fields[key] as PackedByteArray).size() <= StepTiles.CHUNK
		largest = maxi(largest, (fields[key] as PackedByteArray).size())
	var back := StepTiles.join_state(fields, biggest)
	check(sizes_ok and largest <= 240, "%d tiles, %d of them with a clock to read: %d byte fields, the largest %d B (at most 240)" % [biggest, live_count, fields.size(), largest])
	check(back == bytes, "the packed worst state round-trips (%d tiles)" % biggest)
	check(StepTiles.pack_state(PackedByteArray([0, 0, 0])).size() >= 2 and StepTiles.join_state(StepTiles.pack_state(bytes), biggest).size() == biggest, "an almost empty state packs too")
	# a state with all tiles untouched or settled needs no list
	var gone_all := PackedByteArray()
	gone_all.resize(biggest)
	gone_all.fill(StepTiles.SETTLED)
	check(StepTiles.join_state(StepTiles.pack_state(gone_all), biggest) == gone_all and (StepTiles.pack_state(gone_all)["ta"] as PackedByteArray).is_empty(), "every tile gone for good packs as the bitmap alone (%d B)" % (biggest / 8 + 1))
	var capacity := StepTiles.LIVE_PIECE / 3 * StepTiles.MAX_PIECES
	var in_flight := int(25.0 * (StepTiles.SETTLE_AFTER + 0.5)) # 12 runners eat up to 25 tiles a second; a tile is on the list from its step until it is settled
	check(capacity >= 4 * in_flight, "the list holds %d tiles with a clock to read (12 runners leave about %d on it: a quarter of the room)" % [capacity, in_flight])

## The cost of the biggest stage level: the time to build it (the collision bodies and the look), set_steps and pose per tick with every tile stepped.
func check_cost(world: Node3D) -> void:
	var level := 25
	for candidate: int in LEVELS:
		if world.tile_count(candidate) > world.tile_count(level): level = candidate
	var entry: Dictionary = world._levels[level]
	var data: Dictionary = entry.data.tiles
	var node := Node3D.new()
	holder.add_child(node)
	var started := Time.get_ticks_usec()
	var stepper := StepTiles.new()
	stepper.build(node, data, Vector3.ZERO, true, entry.data.stage.ground)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	var collision_only := Node3D.new()
	holder.add_child(collision_only)
	started = Time.get_ticks_usec()
	StepTiles.new().build(collision_only, data, Vector3.ZERO, false, entry.data.stage.ground)
	var collision_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("STAGE_TILES cost level %d: %d tiles, build with look %.0f ms, collision only %.0f ms" % [level + 1, stepper.tile_count(), build_ms, collision_ms])
	check(build_ms < BUILD_LIMIT_MS, "the biggest level builds in %.0f ms (limit %.0f)" % [build_ms, BUILD_LIMIT_MS])
	var count := stepper.tile_count()
	# every tile stepped at the same moment, all warning: the worst per-tick pose
	var bytes := PackedByteArray()
	bytes.resize(count)
	var clock := 30.0
	for index in count: bytes[index] = StepTiles.stamp_at(data, clock - 0.1 + (index % 4) * 0.01)
	started = Time.get_ticks_usec()
	stepper.set_steps(bytes, clock, true)
	var all_ms := (Time.get_ticks_usec() - started) / 1000.0
	var worst_tick := 0.0
	var total := 0.0
	for tick in 24: # 0.4 s of ticks, all of them warning
		var begin := Time.get_ticks_usec()
		stepper.pose(clock + tick / 60.0, true)
		var spent := (Time.get_ticks_usec() - begin) / 1000.0
		worst_tick = maxf(worst_tick, spent)
		total += spent
	print("STAGE_TILES cost: set_steps with all %d tiles stepped %.1f ms; pose per tick with all of them warning: worst %.2f ms, mean %.2f ms" % [count, all_ms, worst_tick, total / 24.0])
	check(all_ms < 800.0, "set_steps with every tile stepped takes %.1f ms (once, when the state arrives)" % all_ms)
	check(worst_tick < 12.0, "pose per tick with every tile warning takes at most %.2f ms" % worst_tick)
	# they all go in one tick, then sleep
	var gone_begin := Time.get_ticks_usec()
	stepper.pose(clock + 0.7, true)
	var gone_ms := (Time.get_ticks_usec() - gone_begin) / 1000.0
	var asleep_begin := Time.get_ticks_usec()
	for tick in 60: stepper.pose(clock + 0.8 + tick / 60.0, true)
	var asleep_ms := (Time.get_ticks_usec() - asleep_begin) / 1000.0 / 60.0
	var gone_all := true
	for index in count: gone_all = gone_all and stepper.is_gone(index)
	print("STAGE_TILES cost: every tile gone in one pose %.1f ms; pose per tick afterwards %.3f ms" % [gone_ms, asleep_ms])
	check(gone_all and gone_ms < 500.0 and asleep_ms < 0.5, "every tile gone in one pose (%.1f ms), then a pose costs %.3f ms (the gone tiles sleep)" % [gone_ms, asleep_ms])
	# one more tile stepped among the sleepers costs nothing like a rebuild
	var settled := bytes.duplicate()
	settled.fill(StepTiles.SETTLED)
	stepper.set_steps(settled, clock + 3.0, true)
	settled[7] = StepTiles.stamp_at(data, clock + 3.0)
	var one_begin := Time.get_ticks_usec()
	stepper.set_steps(settled, clock + 3.0, true)
	var one_ms := (Time.get_ticks_usec() - one_begin) / 1000.0
	print("STAGE_TILES cost: one new step among %d settled tiles: set_steps %.2f ms" % [count, one_ms])
	check(one_ms < 5.0, "one new step among settled tiles costs %.2f ms" % one_ms)
	node.queue_free()
	collision_only.queue_free()
