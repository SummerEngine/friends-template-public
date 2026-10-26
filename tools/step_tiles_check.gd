extends SceneTree
## Check of the step tiles (levels/step_tiles.gd) of LAST TILE STANDING (level_15.json) on the level world, numbers only, headless:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --path demo -s $PWD/tools/step_tiles_check.gd
## The tiles are hexagons: they come with the level, the start steps follow the player count, a courier on a tile is found by tiles_under (the
## hexagon's own edges and corners, a courier on an edge stands on two tiles and on a corner on three), a stood-on tile shakes for its kind's delay
## and is then gone (collision off: a ray goes through it), a second world given the same bytes (a late joiner) agrees at once, the state is
## one byte per tile published in pieces (chunk_state: no byte field over 256 B) that join back to the same bytes, and ten players fit on the
## first floor. Prints STEP_TILES ok=<bool> last.
const LevelWorld := preload("res://levels/level_world.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const HexGrid := preload("res://levels/hex_grid.gd")

const LEVEL := 14 ## 0-based: level_15.json

var failures := 0
var holder: Node3D

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("STEP_TILES ", "ok   " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _initialize() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		print("STEP_TILES FAIL timed out")
		print("STEP_TILES ok=false")
		quit(1))
	run.call_deferred()

func make_world(role: String) -> Node3D:
	var world := LevelWorld.new()
	holder.add_child(world)
	await world.build(role)
	world.set_active_level(LEVEL)
	world.set_clock(0.0)
	return world

## The index of the tile whose top centre is at the level-local XZ point on the floor at `y` (0.01 m).
func tile_at(world: Node3D, x: float, z: float, y: float) -> int:
	var data: Dictionary = world._levels[LEVEL].data.tiles
	for index in (data.tiles as Array).size():
		var p: Vector3 = data.tiles[index].p
		if absf(p.x - x) < 0.01 and absf(p.z - z) < 0.01 and absf(p.y - y) < 0.01: return index
	return -1

## The first tile of `kind` on floor `floor_index`.
func first_of(data: Dictionary, kind: String, floor_index: int) -> int:
	for index in (data.tiles as Array).size():
		var tile: Dictionary = data.tiles[index]
		if tile.kind == kind and int(tile.floor) == floor_index: return index
	return -1

func ray_hits(world: Node3D, local: Vector3) -> float:
	var origin: Vector3 = world.level_origin(LEVEL)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin + local + Vector3(0, 1, 0), origin + local + Vector3(0, -30, 0), 1 | 16))
	return hit.position.y - origin.y if not hit.is_empty() else NAN

## True while tile `index` is drawn on a client world: not on a ghosted floor and not gone (the dummy renderer of a headless run keeps no instance transforms to read back).
func shown(world: Node3D, index: int) -> bool:
	var look = world._levels[LEVEL].tiles.look
	return not look.is_ghosted(index) and look._last[index] != StepTiles.MODE_GONE

func run() -> void:
	holder = Node3D.new()
	root.add_child(holder)
	var world: Node3D = await make_world("authority")
	var count: int = world.tile_count(LEVEL)
	var data: Dictionary = world._levels[LEVEL].data.tiles
	var per_floor := []
	for floor_index in (data.floors as Array).size():
		per_floor.append((data.tiles as Array).filter(func(tile: Dictionary) -> bool: return int(tile.floor) == floor_index).size())
	check(count > 300 and count <= StepTiles.MAX_TILES, "the level has %d step tiles (a byte each, at most %d; per floor %s)" % [count, StepTiles.MAX_TILES, str(per_floor)])
	check(count > StepTiles.CHUNK, "the level has more tiles than one state piece holds (%d > %d): the state is split" % [count, StepTiles.CHUNK])
	check((data.floors as Array).size() == 3 and int(per_floor[0]) >= 120 and int(per_floor[1]) >= 120, "three floors of hexagons, the first two 1.7x the old 73 or more")
	var pitch := float(data.pitch)
	var neighbours_ok := true
	var rings := []
	for tile: Dictionary in data.tiles:
		# every tile is a cell of the grid: its text position has an even column + row, and the cell found from its middle is itself
		var layout: Dictionary = data.floors[int(tile.floor)]
		var found := HexGrid.cell_of(pitch, layout, (tile.p as Vector3).x, (tile.p as Vector3).z)
		if found != tile.cell or (found.x + found.y) % 2 != 0: neighbours_ok = false
	for layout: Dictionary in data.floors:
		var radius := 0.0
		for cell: Vector2i in layout.cells:
			var at := HexGrid.cell_centre(pitch, layout, cell)
			radius = maxf(radius, (at - (layout.centre as Vector2)).length())
		rings.append(snappedf(radius, 0.1))
	check(neighbours_ok, "every tile is on the hexagon grid (cube rounding of its middle finds it again)")
	check(rings[0] > 8.0 and rings[2] < rings[0], "roughly circular floors, the last one smaller (radii %s m)" % str(rings))
	# a hexagon tile touches six neighbours at `pitch` (the first floor's middle has all six)
	var middle := tile_at(world, 0.0, 0.0, 0.0)
	var around := 0
	for other: Dictionary in data.tiles:
		if int(other.floor) == 0 and absf((other.p as Vector3).distance_to(data.tiles[middle].p) - pitch) < 0.01: around += 1
	check(middle >= 0 and around == 6, "the middle hexagon has six neighbours %.1f m away (%d)" % [pitch, around])
	check(world.tile_count(0) == 0 and world.tile_start(0, 2).is_empty(), "a level without tiles has none and no start steps")
	var start6: PackedByteArray = world.tile_start(LEVEL, 6)
	check(start6.size() == count and start6.count(0) == count, "start steps are one byte per tile, every tile standing")
	# `fit` (not used by level_15): a floor of seven hexagons loses its outer ring for up to 3 players
	var small := StepTiles.parse({"pitch": 2.5, "thick": 0.5, "kinds": {"n": {"delay": 0.75, "look": "plain"}}, "floors": [{"y": 0.0, "origin": [0.0, 0.0], "rows": ["  n n  ", " n n n ", "  n n  "]}], "fit": [{"players": 3, "radius": 1.5}]})
	var start2: PackedByteArray = StepTiles.start_steps(small, 2)
	check(start2.size() == 7 and start2.count(StepTiles.PRE_GONE) == 6 and StepTiles.start_steps(small, 6).count(0) == 7, "fit: two players lose the outer ring (%d of 7 gone), six keep all" % start2.count(StepTiles.PRE_GONE))
	# standing: the middle tile (a logo), the logo east of it, 4 clock seconds in
	world.set_clock(4.0)
	var origin: Vector3 = world.level_origin(LEVEL)
	var centre := middle
	var east := tile_at(world, pitch, 0.0, 0.0)
	var south_east := tile_at(world, pitch * 0.5, pitch * HexGrid.ROW, 0.0)
	check(centre >= 0 and east >= 0 and south_east >= 0, "the middle tile, its east and its south-east neighbour exist")
	check(world.tiles_under(LEVEL, origin + Vector3(pitch, 0.0, 0.0)) == [east], "a courier on a tile's middle stands on that tile only")
	check(world.tiles_under(LEVEL, origin + Vector3(1.1, 0.0, 0.0)) == [centre], "1.1 m east of the middle: still the middle tile (the edge is at 1.25 m)")
	check(world.tiles_under(LEVEL, origin + Vector3(1.3, 0.0, 0.0)).size() == 2, "0.05 m past the edge a courier stands on both tiles (on an edge: two)")
	check(world.tiles_under(LEVEL, origin + Vector3(1.4, 0.0, 0.0)) == [east], "0.15 m past the edge only on the tile it is over")
	var corner := Vector3(pitch * 0.5, 0.0, pitch / sqrt(3.0) * 0.5) # where the middle tile, its east and its south-east neighbour meet
	check(world.tiles_under(LEVEL, origin + corner).size() == 3, "on a corner of three hexagons a courier stands on all three (%d)" % world.tiles_under(LEVEL, origin + corner).size())
	check(world.tiles_under(LEVEL, origin + Vector3(1.4, 0.0, 1.2)) == [south_east], "past the slanted edge of the middle hexagon (1.4, 1.2) only the south-east tile holds a courier (a square would have held the middle one)")
	check(world.tiles_under(LEVEL, origin + Vector3(1.25, 0.8, 0.0)).is_empty(), "a courier jumping 0.8 m up stands on nothing")
	var below := tile_at(world, 1.25, 0.0, -4.0)
	check(below >= 0 and world.tiles_under(LEVEL, origin + Vector3(1.25, -4.0, 0.0)) == [below], "on the floor below (shifted half a tile east), the tile of that floor")
	check(world.tiles_under(LEVEL, origin + Vector3(30.0, 0.0, 0.0)).is_empty(), "off the floor nobody stands on a tile")
	var delay := 2.5 # the middle tile is a logo
	var plain := first_of(data, "n", 0)
	var rival := first_of(data, "1", 0)
	check(plain >= 0 and rival >= 0, "a plain and a rival tile on the first floor")
	var plain_at: Vector3 = data.tiles[plain].p
	var rival_at: Vector3 = data.tiles[rival].p
	await frames(2)
	check(absf(ray_hits(world, Vector3.ZERO)) < 0.01, "the ray lands on the standing tile's top (y 0)")
	check(absf(ray_hits(world, Vector3(1.2, 0.0, 0.0)) - 0.0) < 0.01 and absf(ray_hits(world, corner)) < 0.01, "and on its edge and its corner: the colliders leave no gap between hexagons")
	# stand on the logo tile, a plain one and a rival one at clock 4.0 (step byte 16)
	var steps := PackedByteArray()
	steps.resize(count)
	var stamp := roundi(4.0 / StepTiles.STEP_UNIT)
	steps[centre] = stamp
	steps[plain] = stamp
	steps[rival] = stamp
	world.set_tile_steps(LEVEL, steps)
	world.set_clock(4.5)
	await frames(2)
	check(not world.tile_gone(LEVEL, plain) and not world.tile_gone(LEVEL, centre), "0.5 s after the step both still stand (they shake)")
	check(world.tile_gone(LEVEL, rival), "the rival tile (0.25 s) is gone after 0.5 s")
	world.set_clock(4.0 + 0.75 + 0.05)
	await frames(2)
	check(world.tile_gone(LEVEL, plain), "the plain tile (0.75 s) is gone after 0.8 s")
	check(not world.tile_gone(LEVEL, centre), "the logo tile (2.5 s) still stands after 0.8 s")
	var through := ray_hits(world, plain_at)
	check(absf(through - -4.0) < 0.01 or absf(through - -8.0) < 0.01, "a ray through the vanished tile lands on a floor below (y %.2f)" % through)
	check(world.tiles_under(LEVEL, origin + plain_at).is_empty(), "nobody stands on a gone tile")
	world.set_clock(4.0 + delay + 0.05)
	await frames(2)
	check(world.tile_gone(LEVEL, centre) and ray_hits(world, Vector3.ZERO) < -3.9, "the logo tile is gone after its 2.5 s")
	# a late joiner: another world (a client with a look) given the same bytes at the same clock
	var late: Node3D = await make_world("local")
	late.set_clock(4.0 + delay + 0.05)
	late.set_tile_steps(LEVEL, steps, true)
	await frames(2)
	check(late.tile_gone(LEVEL, plain) and late.tile_gone(LEVEL, centre) and late.tile_gone(LEVEL, rival), "a late joiner's world has the same tiles gone")
	var untouched := tile_at(late, 5.0, 0.0, 0.0) if tile_at(late, 5.0, 0.0, 0.0) != plain else first_of(data, "n", 1)
	check(untouched >= 0 and not late.tile_gone(LEVEL, untouched), "and the untouched tiles stand")
	check(late._levels[LEVEL].tiles.look != null and world._levels[LEVEL].tiles.look == null, "only the client world builds the tile look")
	var seen_vanish := []
	var warned := []
	late.tile_warned.connect(func(index: int, _at: Vector3) -> void: warned.append(index))
	late.tile_vanished.connect(func(index: int, _at: Vector3) -> void: seen_vanish.append(index))
	var later := steps.duplicate()
	var fresh := untouched
	later[fresh] = roundi((4.0 + delay + 0.05) / StepTiles.STEP_UNIT) + 1
	late.set_tile_steps(LEVEL, later)
	for tick in 60: late.advance(0.1) # six seconds of level clock: the tile shakes (0.75 s), then goes
	check(warned == [fresh] and seen_vanish == [fresh], "the world signals a tile that shakes and then goes (%s, %s)" % [str(warned), str(seen_vanish)])
	# ghosted floors: the shoulder camera stands 3.565 m over the feet (focus 1.0 + rise 1.35 + 5.4 m arm at 13 degrees); a floor over the camera is not drawn
	var shoulder := 1.0 + 1.35 + 5.4 * sin(deg_to_rad(13.0))
	var tops: Array = (data.floors as Array).map(func(layout: Dictionary) -> float: return float(layout.y))
	check(tops == [0.0, -4.0, -8.0], "the floors' tops are 0, -4 and -8 m (%s)" % str(tops))
	check(StepTiles.ghost_floors(data, -4.0 + shoulder, 0.0).is_empty() and StepTiles.ghost_floors(data, -50.0, 0.0).is_empty(), "on the top floor nothing is ghosted, whatever the camera height (the floors below never are)")
	check(StepTiles.ghost_floors(data, -4.0 + shoulder, -4.0) == PackedInt32Array([0]), "on the middle floor the shoulder camera (%.2f m up) hides the top floor over it only" % (-4.0 + shoulder))
	check(StepTiles.ghost_floors(data, -8.0 + shoulder, -8.0) == PackedInt32Array([0, 1]), "on the lowest floor it hides both floors over it")
	check(StepTiles.ghost_floors(data, -1.0, -8.0) == PackedInt32Array([0]) and StepTiles.ghost_floors(data, -4.0 + StepTiles.GHOST_MARGIN - 0.01, -8.0) == PackedInt32Array([0, 1]) and StepTiles.ghost_floors(data, -4.0 + StepTiles.GHOST_MARGIN + 0.01, -8.0) == PackedInt32Array([0]), "a camera past a floor's top (+ %.1f m) sees that floor again, the one over it still hidden" % StepTiles.GHOST_MARGIN)
	check(StepTiles.ghost_floors(data, 0.29, -4.0) == PackedInt32Array([0]) and StepTiles.ghost_floors(data, 0.31, -4.0).is_empty() and StepTiles.ghost_floors(data, 6.0, -4.0).is_empty(), "a camera above the top floor (a steep look down) draws it: floors are only hidden from under")
	check(StepTiles.ghost_floors(data, INF, -8.0).is_empty() and StepTiles.ghost_floors({}, -9.0, -8.0).is_empty(), "a fixed shot (camera height INF) and a level without tiles hide nothing")
	check(StepTiles.ghost_floors(data, -3.0, -0.9).is_empty() and StepTiles.ghost_floors(data, -3.0, -StepTiles.REACH_BELOW).is_empty(), "a floor less than a metre over the feet (so the one a courier stands on: its top is at most REACH_BELOW over the feet) is never ghosted")
	world.ghost_tiles(LEVEL, origin.y - 4.0 + shoulder, origin.y - 4.0)
	check(world._levels[LEVEL].tiles.ghosted == PackedInt32Array([0]) and world._levels[LEVEL].tiles.look == null, "the authority world keeps the state (ghosted floors [0]) and draws nothing")
	world.ghost_tiles(LEVEL, INF, origin.y)
	check(world._levels[LEVEL].tiles.ghosted.is_empty(), "the camera above everything: no floor ghosted")
	var lowest_one := first_of(data, "n", 2)
	var middle_one := first_of(data, "n", 1)
	var standing := -1
	var standing2 := -1
	for index in count:
		if int(data.tiles[index].floor) == 0 and not late.tile_gone(LEVEL, index):
			if standing < 0: standing = index
			elif standing2 < 0: standing2 = index
	check(standing >= 0 and standing2 >= 0 and shown(late, standing) and shown(late, middle_one), "before ghosting the top and middle floors' tiles are drawn")
	late.ghost_tiles(LEVEL, origin.y - 4.0 + shoulder, origin.y - 4.0)
	check(late._levels[LEVEL].tiles.ghosted == PackedInt32Array([0]) and not shown(late, standing) and not shown(late, standing2) and shown(late, middle_one), "a player on the middle floor: the top floor's tiles are scaled away, the middle floor's drawn")
	var during := later.duplicate()
	during[standing] = 1 # stood on at 0.25 s: gone long ago at the clock now (a step that arrives while its floor is ghosted)
	late.set_tile_steps(LEVEL, during, true)
	check(late.tile_gone(LEVEL, standing) and not shown(late, standing) and not shown(late, standing2), "a step that arrives while the floor is ghosted changes the game (the tile is gone) and draws nothing")
	late.ghost_tiles(LEVEL, origin.y - 4.0 + shoulder, origin.y - 4.0)
	late.ghost_tiles(LEVEL, origin.y - 8.0 + shoulder, origin.y - 8.0)
	check(late._levels[LEVEL].tiles.ghosted == PackedInt32Array([0, 1]) and not shown(late, middle_one) and shown(late, lowest_one), "a player on the lowest floor: floors 0 and 1 away, its own floor drawn")
	late.ghost_tiles(LEVEL, origin.y + 8.0, origin.y - 8.0)
	check(late._levels[LEVEL].tiles.ghosted.is_empty() and shown(late, standing2) and shown(late, middle_one) and not shown(late, standing) and not shown(late, centre), "the camera above the floors: all drawn again, the tiles that went meanwhile (and before) stay gone")
	late.ghost_tiles(LEVEL, origin.y + 20.0, origin.y)
	check(late._levels[LEVEL].tiles.ghosted.is_empty() and late._levels[LEVEL].tiles.look.is_ghosted(standing2) == false, "a repeated call changes nothing")
	late.queue_free() # (both worlds share one physics space: the rays below are the authority world's alone)
	await frames(2)
	# a new round: all steps 0 again, everything stands
	world.set_clock(0.0)
	world.set_tile_steps(LEVEL, PackedByteArray(start6))
	await frames(2)
	check(not world.tile_gone(LEVEL, plain) and not world.tile_gone(LEVEL, centre) and absf(ray_hits(world, plain_at)) < 0.01, "a new round's steps put every tile back")
	# the state in pieces: every piece under 256 B, the pieces join back to the very bytes, also with the last piece stepped
	var full := PackedByteArray()
	full.resize(count)
	for index in count: full[index] = (index * 7) % 255 # every byte value 0..254 shows up in every piece
	full[count - 1] = StepTiles.PRE_GONE
	var fields := StepTiles.chunk_state(full)
	var biggest := 0
	var piece_total := 0
	for key: String in fields:
		biggest = maxi(biggest, (fields[key] as PackedByteArray).size())
		piece_total += (fields[key] as PackedByteArray).size()
	check(fields.has("tiles") and fields.has("tiles1") and fields.size() == ceili(count / float(StepTiles.CHUNK)), "%d tiles go out as %d pieces (%s)" % [count, fields.size(), str(fields.keys())])
	check(biggest <= StepTiles.CHUNK and biggest <= 256 and piece_total == count, "no piece over %d bytes (largest %d), %d bytes in all" % [StepTiles.CHUNK, biggest, piece_total])
	check(StepTiles.join_state(fields) == full and StepTiles.join_state(fields)[count - 1] == StepTiles.PRE_GONE, "join_state puts the pieces back together: the same bytes, the last piece's too")
	check(StepTiles.chunk_state(PackedByteArray()).size() == 1 and StepTiles.join_state(StepTiles.chunk_state(PackedByteArray())).is_empty() and StepTiles.join_state({}).is_empty(), "no tiles: one empty piece, and a state without pieces joins to nothing")
	var short := PackedByteArray([1, 2, 3])
	check(StepTiles.chunk_state(short).size() == 1 and StepTiles.join_state(StepTiles.chunk_state(short)) == short, "a short list is one piece")
	var exact := PackedByteArray()
	exact.resize(StepTiles.CHUNK)
	check(StepTiles.chunk_state(exact).size() == 1 and StepTiles.join_state(StepTiles.chunk_state(exact)).size() == StepTiles.CHUNK, "exactly one piece of bytes is one piece")
	exact.resize(StepTiles.CHUNK + 1)
	check(StepTiles.chunk_state(exact).size() == 2 and StepTiles.join_state(StepTiles.chunk_state(exact)).size() == StepTiles.CHUNK + 1, "one byte more is a second piece")
	# a world given the joined pieces of a state with a tile of the last piece stepped (a late joiner's path) has that tile gone
	var last_tile := count - 1
	var last_steps := PackedByteArray(start6)
	last_steps[last_tile] = roundi(1.0 / StepTiles.STEP_UNIT)
	var joined := StepTiles.join_state(StepTiles.chunk_state(last_steps))
	world.set_clock(4.0)
	world.set_tile_steps(LEVEL, joined)
	await frames(2)
	check(last_tile >= StepTiles.CHUNK and world.tile_gone(LEVEL, last_tile) and not world.tile_gone(LEVEL, plain), "a tile of the last piece (%d) stepped at 1 s is gone at 4 s, the others stand" % last_tile)
	# ten players fit on the first floor: every spot of the start ring for 2..10 players is on a tile at clock 0 and there is room to run
	world.set_clock(0.0)
	world.set_tile_steps(LEVEL, PackedByteArray(start6))
	var fits := true
	var worst := INF
	for players in range(2, 11):
		var spots: Array = world.team_start(LEVEL, players).pos
		for spot: Vector3 in spots:
			if world.tiles_under(LEVEL, spot).is_empty() or absf(spot.y - origin.y) > 0.05: fits = false
		for first in spots.size():
			for second in range(first + 1, spots.size()): worst = minf(worst, (spots[first] as Vector3).distance_to(spots[second]))
	check(fits, "the start ring of 2..10 players stands on tiles of the first floor (closest two: %.2f m)" % worst)
	var room := 0
	var start: Vector3 = world.team_start(LEVEL, 10).spot - origin
	for tile: Dictionary in data.tiles:
		if int(tile.floor) == 0 and Vector2((tile.p as Vector3).x - start.x, (tile.p as Vector3).z - start.z).length() > 3.0: room += 1
	check(room >= 100, "%d hexagons of the first floor lie more than 3 m from the start: room to run for ten players" % room)
	# a state of the wrong size is ignored
	world.set_tile_steps(LEVEL, PackedByteArray([1, 2, 3]))
	check(not world.tile_gone(LEVEL, plain), "a state of another size is ignored")
	holder.queue_free()
	await process_frame
	print("STEP_TILES ok=", failures == 0)
	quit(1 if failures > 0 else 0)
