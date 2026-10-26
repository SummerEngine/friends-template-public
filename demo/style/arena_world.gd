extends RefCounted
## The world around a stage round (levels 25-28: falling-tile rounds on a stack of layers, `stage` in the level file): the candy world (style/candy_world.gd: a slime lake at the plane under the ground slab (`stage.enclosure` "b" only picks another layout of the
## same world, a different seed), the lime meadow round it, trees, meringue mountains, puffs and the cloud wall) (NO rail ring, NO walls: the course has no fake barriers, you can fall off the tiles). It replaces the party / night backdrop for these levels whatever the cast's world style is; the matching bright daylight is
## style/candy_light.gd's (levels/level_environment.gd applies it). Decor only: no collision, nothing the physics sees, no lights. Client only. `ring_of` is the footprint of the tiles pushed RIM_GAP out (a square for square tiles, a hexagon for hex tiles): the world's lake is sized by it. Docs: docs/backdrop.md "The stage look".
const CandyWorld := preload("res://style/candy_world.gd")
const HexGrid := preload("res://levels/hex_grid.gd")
const SquareGrid := preload("res://levels/square_grid.gd")

const E := 3.5                ## m, the big square tile's edge: the unit the ring's proportions are measured in
const RIM_GAP := 1.75 * E     ## m between the rim of the tiles and the lake ring (ring_of)
const SEA_UNDER := 0.05       ## m the sea lies under the permanent ground slab's bottom (no face shares its plane)
const DEFAULT_THICK := 2.0    ## m, the ground slab's thickness when the level gives none
const DEFAULT_GAP := 0.45 * E ## m between two layers' tops when a level has one layer only
const LAKE_PER_HEIGHT := 7.2    ## m of slime beyond the lake ring per metre the camera hangs over the sea: the far shore stands about 7 degrees under the horizon, so the slime fills the band between the arena and the meadow (CandyWorld option lake_margin)
const LAKE_MIN := 95.0          ## m, a low stack's least lake margin
const LAKE_MAX := 1100.0         ## m, a tower's greatest (the shore field's window and the terrain mesh grow with it)
const VIEW_UP := 12.0         ## m, about where the stage camera hangs over the top layer: the mountains' and clouds' angles are set for it

## The world of the level `data` (levels/level_data.gd load_level: `tiles` and `stage` are read) standing at `origin`.
static func build(data: Dictionary, origin: Vector3) -> Node3D:
	var tiles: Dictionary = data.tiles
	var root := Node3D.new()
	root.name = "ArenaWorld%02d" % int(data.number)
	root.position = origin
	var tops := layer_tops(tiles)
	var ring := ring_of(tiles)
	var ground_y := ground_top(data, tops)
	var sea_y := sea_level(data, ground_y)
	var vertices: PackedVector2Array = ring.vertices
	var reach := 0.0
	for p in vertices: reach = maxf(reach, p.length())
	root.add_child(CandyWorld.build({
		"centre": Vector3.ZERO, "floor_y": ground_y, "course_radius": reach, "world_scale": CandyWorld.default_scale(), "seed": int(data.number) + (1 if str(data.stage.get("enclosure", "a")) == "b" else 0), "sea": "slime", "sea_y": sea_y, "lake_margin": clampf(LAKE_PER_HEIGHT * (tops[0] + VIEW_UP - sea_y), LAKE_MIN, LAKE_MAX),
		"view_y": tops[0] + VIEW_UP - sea_y}))
	return root

## The top of the permanent ground slab under the last layer (level-local y): the level's own `stage.ground.y` when it gives one, else one layer gap under the last layer's top.
static func ground_top(data: Dictionary, tops: PackedFloat32Array) -> float:
	var ground: Variant = (data.stage as Dictionary).get("ground")
	if ground is Dictionary and (ground as Dictionary).has("y"): return float((ground as Dictionary).y)
	var gap := tops[tops.size() - 2] - tops[tops.size() - 1] if tops.size() > 1 else DEFAULT_GAP
	return tops[tops.size() - 1] - gap

## The height of the sea of the stage round (visual only: nothing kills at it, the rules eliminate on the ground slab's top): SEA_UNDER under the slab's bottom, so the slab, a solid floor
## that fills the ring (style/stage_tile_look.gd), hides it and it shows only round the outside of the arena. Follows the level's own ground data.
static func sea_level(data: Dictionary, ground_y: float) -> float:
	var ground: Variant = (data.stage as Dictionary).get("ground")
	var thick := float((ground as Dictionary).get("thick", DEFAULT_THICK)) if ground is Dictionary else DEFAULT_THICK
	return ground_y - thick - SEA_UNDER

## The tops of the layers, highest first (level-local y).
static func layer_tops(tiles: Dictionary) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for entry: Dictionary in tiles.floors: result.append(float(entry.y))
	result.sort()
	result.reverse()
	return result

## The ring of the rail around the tiles: {vertices (x, z, in order), normals (outward, unit), offsets (n . p of each side), apothems (of the tiles' own outline)}. The tiles' outline
## is the polygon of the grid's own shape (4 sides for square tiles, 6 for hex tiles) pulled tight around every tile corner of every layer; the ring is that outline pushed out RIM_GAP.
static func ring_of(tiles: Dictionary) -> Dictionary:
	var square := str(tiles.grid) == "square"
	var pitch := float(tiles.pitch)
	var corners := SquareGrid.corners(pitch * 0.5) if square else HexGrid.hex_corners(pitch / sqrt(3.0))
	var sides := 4 if square else 6
	var normals := PackedVector2Array()
	for k in sides:
		var angle := TAU * k / sides + (0.0 if square else PI / 6.0)
		normals.append(Vector2(cos(angle), sin(angle)))
	var support := PackedFloat32Array()
	support.resize(sides)
	support.fill(-INF)
	for entry: Dictionary in tiles.tiles:
		var p: Vector3 = entry.p
		var at := Vector2(p.x, p.z)
		for corner in corners:
			for k in sides: support[k] = maxf(support[k], normals[k].dot(at + corner))
	var offsets := PackedFloat32Array()
	var apothems := PackedFloat32Array()
	for k in sides:
		apothems.append(support[k])
		offsets.append(support[k] + RIM_GAP)
	return {"vertices": polygon(normals, offsets), "normals": normals, "offsets": offsets, "apothems": apothems}

## The corners of the convex polygon whose sides have the outward unit `normals` and offsets `offsets` (n . p), in order: corner k is where side k meets side k + 1.
static func polygon(normals: PackedVector2Array, offsets: PackedFloat32Array) -> PackedVector2Array:
	var sides := normals.size()
	var vertices := PackedVector2Array()
	for k in sides:
		var a := normals[k]
		var b := normals[(k + 1) % sides]
		var det := a.x * b.y - a.y * b.x
		var da := offsets[k]
		var db := offsets[(k + 1) % sides]
		vertices.append(Vector2((da * b.y - db * a.y) / det, (a.x * db - b.x * da) / det))
	return vertices
