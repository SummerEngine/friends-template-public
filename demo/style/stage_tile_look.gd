extends RefCounted
## The look of the stage tiles (levels/step_tiles.gd with `"style": "stage"`), client only: glossy chamfered candy slabs, one MultiMesh (one draw call, one surface) per floor.
## A floor wears ONE colour family (blue, yellow-orange or purple of `CandyLook.TILE_FAMILIES`, picked from its `tone` in the level file), each tile one of the family's three shades
## (a pure function of floor and cell), flat and saturated, lit by the engine's PBR (roughness `ROUGH_TILE`) with two extras for a hexagon: 30 % of its colour as its
## own light and a pink additive rim (`style/stage_tile.gdshaderinc`; a square tile has the cool dark rim and no own light). A slab is 0.5 m thick with a 0.25 m chamfer (half its thickness)
## all round its top, a faint near-white sheen band on the flat top and a bright chamfer slope; where two tiles meet the chamfers make a V groove, darkened a little at its foot. No outline, no toon ramp.
## A tile that is stepped on turns to a pale tone of its own colour (the warning: a colour swap, the shape never changes) and sinks by SINK_SHARE of its thickness at once, holds there
## for its delay, and is gone in one frame: no drop, no shrink, no fade (a gone tile is scaled to nothing where it stood). A kind with a `raise` (a spawn pad) stands that much higher
## and its side reaches down to the floor's level; a kind with a `tone` wears that colour whole (no patches). Pure look: no collision, nothing here decides anything.
## The permanent ground of the round (`stage.ground`) is a tray of the same family: tiles of the layers' own lattice and shape, lower chamfered frustums (one more MultiMesh) laid on a
## chamfered near-white slab (the collider's picture) that fills the edges. The floors the camera sits under are hidden whole (set_ghosted: levels/step_tiles.gd ghost_floors): a floor
## is one node, so this is a visibility flip.
const SquareGrid := preload("res://levels/square_grid.gd")
const HexGrid := preload("res://levels/hex_grid.gd")
const CandyLook := preload("res://style/candy_look.gd")
const CandyCourse := preload("res://style/candy_course.gd")

const GONE_SCALE := 0.0001   ## the scale of a gone tile: a MultiMesh instance is taken away by shrinking it
const SINK_SHARE := 0.4       ## of its thickness a warned tile sits lower than its neighbours (thin walls round a white tile: a full-thickness pit reads as a dark hole)
const CHAMFER_SHARE := CandyLook.CHAMFER_SLAB / 0.5 ## of a slab's thickness the chamfer cuts from the top edge (0.25 m on 0.5 m)
const CHAMFER_ROUND := 0.25   ## how far the chamfer's vertex normals lean off the 45 degree slope (0: flat slope, 1: a quarter circle): the slope shades as a gradient, like a rounded edge
const FOOT_SHADE := 0.97      ## vertex shade at the foot of a chamfer and on the side: a little occlusion in the groove between two tiles
const DEFAULT_TONE := Color("#058ee0")
const SHADER := preload("res://style/stage_tile.gdshader")
const FADE_SHADER := preload("res://style/stage_tile_fade.gdshader")
const FADE_TIME := 0.2        ## s a floor takes to fade out or in when the view hides or brings it back
const SEED := 7
const GLARE_DIR := Vector3(-0.29, 0.5, 0.82) ## world direction towards the glare the tops mirror (a bright sky 30 degrees up, ahead and a little left of the stage camera): only tiles whose bowled top turns that way to the eye catch it
const HEX_ROW := 0.8660254   ## sqrt(3) / 2: the spacing of hexagon rows or columns in pitches
const FLOOR_CHAMFER_HEX := 0.2   ## m: the chamfer of the plain floors under the start layer (the start layer keeps the 0.25 m slab): a dark seam between two hexagons
const FLOOR_CHAMFER_SQUARE := 0.0 ## ... square cells: almost no edge: the cells' own borders are hairlines, the floor is one big padded mat (quilted by the shader: MAT_*)
const FLOOR_SEAM_HEX := 0.38     ## the seam's shade (the chamfer slope's albedo times this) on a hexagon floor: a clearly darker line on the violet floor
const FLOOR_SEAM_SQUARE := 1.0  ## ... on a square floor: none (the quilted seams are the shader's)
const MAT_SIZE := 9.0            ## m: a padded mat of a plain square floor (about 4 couriers wide), on a lattice that ignores the 3.5 m cells
const HEX_BEVEL_LIFT := 0.4      ## how far a hexagon's chamfer is lifted towards white: the bevel reads lighter than the top (icy)
const HEX_BEVEL_FRESNEL := 0.3   ## the white fresnel on a hexagon's chamfer
const HEX_GLINT := 0.55          ## the soft sun lobe on a hexagon's top (view dependent: a few tiles catch it)
const HEX_SHEEN := 0.18          ## the pale cyan fresnel on the top
const HEX_SIDE_DARK := 0.1       ## the vertical side of a slab: this share of its own albedo, the rest the navy trim, no own light (the dark accent under every tile)
const SQUARE_BEVEL_LIFT := 0.08  ## the same for a square slab
const SQUARE_GLINT := 0.45
const SQUARE_SHEEN := 0.08
const SQUARE_CENTRE_LIFT := 0.0  ## a square slab's top: the soft highlight at its middle, towards white (the lit top clips)
const SQUARE_MAT_LIFT := 0.0     ## a mat's middle: this far towards white (a pillow's sheen)
const HEX_TOP_SELF_LIGHT := 0.2  ## a hexagon pad's own light (the standard 0.3 turns a cyan top near white under the grade): the top stays a saturated cyan, the chamfers go white by the bevel terms
const MAT_SPECULAR := 0.04       ## the engine's specular amount of a mat: the sky's cyan glare at a grazing view must not turn the deep blue to cyan
const MAT_ROUGH := 0.38          ## a padded mat: glossy vinyl (0.3 .. 0.4)
const GROUND_RAISE := 0.03    ## m the ground's tiles stand over the collider's top: no face shares a plane with it, a courier's soles sink 3 cm into the tile
const GROUND_CHAMFER := 0.2   ## m: the ground's tiles are frustums of this height (a chamfer all the way down), their feet on the tray
const TRAY_CHAMFER := CandyLook.CHAMFER_SLAB ## m of chamfer on the ground tray's top edge
const TRAY_TONE := Color("#f0e1f7") ## the ground tray under and round the tiles: near white with a lavender cast
const GROUND_SOFT := 0.4     ## share of the self light and the rim a ground tile keeps
const GROUND_FLOOR := 99      ## the floor index the ground's tile shades are hashed with (a floor of its own)
const HEX_RIM_STRENGTH := 0.6 ## the pink rim's amplitude on a hexagon (a faint rim: a thin pink cast on the chamfers, not an outline)
const SQUARE_SELF_LIGHT := 0.2  ## own light on a square tile: its top clips in the sun and its shaded sides and far rows keep their colour instead of going brown
const HEX_FLOOR_SELF_LIGHT := 0.16 ## a hexagon floor under the start layer: less own light than the pads, so it reads deep and its dark seams stay dark
const SQUARE_ROUGH := 0.24    ## a square tile is glossier than a hexagon (nearly a mirror), without the self light
const FAMILY_HUE_GAP := 0.06 ## a floor tone further than this in hue from every family keeps its own colour (the ground's lime)
## The brand: a tile family is the colour of a ROLE of the course scheme (`CandyCourse.scheme()`: p, s, a), `family_of` keeps the family's saturation and value and swaps its hue for the role's
## (the default scheme is the family's own hue, nothing changes). Blue and cyan are P (the floor), yellow-orange is A (the accent), purple is S. `ROLE_HUE_SHIFT`: how far a family sits from its role's
## hue (cyan is a greener P).
const FAMILY_ROLE := {"blue": "p", "cyan": "p", "yellow": "a", "purple": "s", "sky": "p", "mats": "p"}
const ROLE_HUE_SHIFT := {"blue": 0.0, "cyan": -0.05, "yellow": 0.0, "purple": 0.0, "sky": 0.0, "mats": 0.0}

var _tiles: Array = []
var _multis: Array = []       ## per floor: MultiMesh
var _nodes: Array = []        ## per floor: MultiMeshInstance3D
var _base := PackedColorArray() ## per tile: its standing colour
var _warn := PackedColorArray() ## per tile: its colour while it is warned (a pale tone of its own)
var _last := PackedByteArray() ## per tile: the mode of the last pose (tools read it)
var _sink := 0.0              ## m a warned tile sits lower than its neighbours: SINK_SHARE of its thickness
var _slot := PackedInt32Array() ## per tile: its instance in its floor's multimesh
var _scale_y := PackedFloat32Array() ## per tile: how much taller than the plain slab its mesh is stretched (a raised tile reaches down to the floor's level)
var _hidden := PackedByteArray() ## per floor: 1 while ghosted (its target: gone)
var _fade := PackedFloat32Array() ## per floor: 1 whole .. 0 gone
var _fade_materials: Array = [] ## per floor: the dither material it wears while it fades

func build(level_root: Node3D, data: Dictionary, ground_data := {}) -> void:
	_tiles = data.tiles
	var floors: Array = data.floors
	var square := str(data.grid) == "square"
	var pitch := float(data.pitch)
	_sink = float(data.thick) * SINK_SHARE
	var mesh := _tile_mesh(square, pitch, float(data.thick), bool(data.get("flat", false)))
	mesh.surface_set_material(0, _material(SHADER, square))
	var plain := floors.size() > 1 # the layers under the start layer are the plain floor: a thin chamfer, a light line between two cells, flat colour
	var flat_mesh := _tile_mesh(square, pitch, float(data.thick), bool(data.get("flat", false)), false, FLOOR_CHAMFER_SQUARE if square else FLOOR_CHAMFER_HEX) if plain else mesh
	if plain: flat_mesh.surface_set_material(0, _material(SHADER, square, false, FLOOR_SEAM_SQUARE if square else FLOOR_SEAM_HEX))
	_last.resize(_tiles.size())
	_base.resize(_tiles.size())
	_warn.resize(_tiles.size())
	_slot.resize(_tiles.size())
	_scale_y.resize(_tiles.size())
	_hidden.resize(floors.size())
	_fade.resize(floors.size())
	_fade.fill(1.0)
	var counts: Array = []
	for _f in floors.size(): counts.append(0)
	for index in _tiles.size(): counts[int((_tiles[index] as Dictionary).floor)] += 1
	var families: Array = []
	for floor_index in floors.size():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = mesh if floor_index == 0 else flat_mesh
		multi.instance_count = int(counts[floor_index])
		var node := MultiMeshInstance3D.new()
		node.name = "StageFloor%d" % floor_index
		node.multimesh = multi
		level_root.add_child(node)
		_multis.append(multi)
		_nodes.append(node)
		_fade_materials.append(_material(FADE_SHADER, square, false, -1.0 if floor_index == 0 else (FLOOR_SEAM_SQUARE if square else FLOOR_SEAM_HEX)))
		counts[floor_index] = 0
		var layer_tone: String = str((floors[floor_index] as Dictionary).tone)
		families.append(layer_family(Color(layer_tone) if layer_tone != "" else DEFAULT_TONE, square, floor_index == 0))
	for index in _tiles.size():
		var entry: Dictionary = _tiles[index]
		var floor_index := int(entry.floor)
		var instance := int(counts[floor_index])
		counts[floor_index] = instance + 1
		_slot[index] = instance
		var kind: Dictionary = (data.kinds as Dictionary)[entry.kind]
		var fixed := str(kind.get("tone", "")) != ""
		var family: Array = family_of(Color(str(kind.tone))) if fixed else families[floor_index]
		_base[index] = tint(family, floor_index, entry.cell, not fixed and floor_index == 0, not (square and plain and floor_index > 0 and not fixed)) # only the pads wear three shades, a plain floor one colour (a square one without the brightness jitter: its mats are the shader's)
		_warn[index] = warned(_base[index])
		_scale_y[index] = 1.0 + float(kind.get("raise", 0.0)) / float(data.thick)
		var multi: MultiMesh = _multis[floor_index]
		multi.set_instance_color(instance, _base[index])
		multi.set_instance_transform(instance, _stand(index))
	if not ground_data.is_empty(): _build_ground(level_root, data, ground_data)

## The plain surface of a stage tile for a look outside the tile rounds (the title's deck, style/menu_stage.gd).
static func plain_material(square: bool) -> ShaderMaterial:
	return _material(SHADER, square)

## The surface of a stage tile (`shader` is the plain one or the dither one): PBR roughness and, for a hexagon, the self light and the pink rim, for a square tile the cool dark rim. Both wear a lighter, whiter
## bevel (an icy chamfer), a short white glint on the top and a navy trim on the side. `seam` >= 0 makes it a plain floor of the layers under the start layer: the chamfer slope is darker, not lighter, the
## middle of a cell is not lifted, and a square floor is quilted mats (stage_tile.gdshaderinc, MAT_SIZE).
static func _material(shader: Shader, square: bool, soft := false, seam := -1.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("colors_linear", _compat())
	material.set_shader_parameter("glyph", CandyLook.TILE_GLYPH)
	material.set_shader_parameter("side_dark", HEX_SIDE_DARK)
	material.set_shader_parameter("sun_dir", GLARE_DIR)
	if square:
		material.set_shader_parameter("roughness", SQUARE_ROUGH)
		material.set_shader_parameter("self_light", SQUARE_SELF_LIGHT)
		material.set_shader_parameter("rim_color", CandyLook.TILE_SQUARE_RIM_COLOR)
		material.set_shader_parameter("rim_power", CandyLook.TILE_SQUARE_RIM_POWER)
		material.set_shader_parameter("rim_strength", 1.0)
		material.set_shader_parameter("bevel_lift", SQUARE_BEVEL_LIFT)
		material.set_shader_parameter("centre_lift", SQUARE_CENTRE_LIFT)
		material.set_shader_parameter("glint", SQUARE_GLINT)
		material.set_shader_parameter("sheen", SQUARE_SHEEN)
	else:
		material.set_shader_parameter("roughness", CandyLook.ROUGH_TILE)
		material.set_shader_parameter("self_light", HEX_TOP_SELF_LIGHT)
		material.set_shader_parameter("rim_color", CandyLook.HEX_RIM_COLOR)
		material.set_shader_parameter("rim_power", CandyLook.HEX_RIM_POWER)
		material.set_shader_parameter("rim_strength", HEX_RIM_STRENGTH)
		material.set_shader_parameter("bevel_lift", HEX_BEVEL_LIFT)
		material.set_shader_parameter("bevel_fresnel", HEX_BEVEL_FRESNEL)
		material.set_shader_parameter("glint", HEX_GLINT)
		material.set_shader_parameter("sheen", HEX_SHEEN)
	if seam >= 0.0: # a plain floor
		material.set_shader_parameter("bevel_lift", 0.0)
		material.set_shader_parameter("bevel_fresnel", 0.0)
		material.set_shader_parameter("bevel_dark", seam)
		material.set_shader_parameter("centre_lift", 0.0)
		material.set_shader_parameter("glyph", 0.0)
		material.set_shader_parameter("glint", 0.0)
		material.set_shader_parameter("sheen", 0.0)
		if square:
			material.set_shader_parameter("side_dark", 1.0) # a mat floor has no trim: a cell border is no line
			material.set_shader_parameter("mat_size", MAT_SIZE)
			material.set_shader_parameter("mat_lift", SQUARE_MAT_LIFT)
			material.set_shader_parameter("roughness", MAT_ROUGH)
			material.set_shader_parameter("tile_specular", MAT_SPECULAR)
			material.set_shader_parameter("self_light", 0.0)
		else:
			material.set_shader_parameter("self_light", HEX_FLOOR_SELF_LIGHT)
	if soft: # the ground's tiles: less of the self light and rim, so the big bright floor does not clip
		material.set_shader_parameter("self_light", float(material.get_shader_parameter("self_light")) * GROUND_SOFT)
		material.set_shader_parameter("rim_strength", float(material.get_shader_parameter("rim_strength")) * GROUND_SOFT)
		material.set_shader_parameter("glint", 0.0)
		material.set_shader_parameter("sheen", 0.0)
		material.set_shader_parameter("bevel_fresnel", 0.0)
	return material

## The ground of the round: a near-white chamfered tray (`StageGroundLook`, the collider's size, its top GROUND_CHAMFER under the tiles' feet) and on it the tiles of the layers' own
## lattice and shape (`StageGroundTiles`, one MultiMesh of chamfered frustums) that lie wholly inside the tray, each in the ground's tone with a slight jitter: a solid floor with the
## grooves of the tiles above.
func _build_ground(level_root: Node3D, data: Dictionary, ground_data: Dictionary) -> void:
	var size: Array = ground_data.size
	var middle: Array = ground_data.centre
	var height := float(ground_data.thick)
	var tone := Color(str(ground_data.get("tone", "#cffa65")))
	var ground_y := float(ground_data.y)
	var tile_top := ground_y + GROUND_RAISE
	var tray_top := tile_top - GROUND_CHAMFER
	var tray := ShaderMaterial.new()
	tray.shader = SHADER
	tray.set_shader_parameter("colors_linear", _compat())
	tray.set_shader_parameter("tint", TRAY_TONE)
	tray.set_shader_parameter("roughness", CandyLook.ROUGH_TILE)
	tray.set_shader_parameter("self_light", 0.2)
	tray.set_shader_parameter("rim_strength", 0.0)
	tray.set_shader_parameter("glyph", 0.0)
	var tray_mesh := _tray_mesh(Vector2(float(size[0]), float(size[1])), height - (ground_y - tray_top), TRAY_CHAMFER)
	tray_mesh.surface_set_material(0, tray)
	var node := MeshInstance3D.new()
	node.name = "StageGroundLook"
	node.mesh = tray_mesh
	node.position = Vector3(float(middle[0]), tray_top, float(middle[1]))
	level_root.add_child(node)
	var square := str(data.grid) == "square"
	var pitch := float(data.pitch)
	var flat := bool(data.get("flat", false))
	var step_a := Vector2(pitch, 0.0)
	var step_b := Vector2(0.0, pitch)
	if not square:
		step_a = Vector2(pitch * 0.5, pitch * HEX_ROW) if not flat else Vector2(pitch * HEX_ROW, pitch * 0.5)
		step_b = Vector2(pitch, 0.0) if not flat else Vector2(0.0, pitch)
	var anchor := Vector2(((_tiles[0] as Dictionary).p as Vector3).x, ((_tiles[0] as Dictionary).p as Vector3).z)
	var reach := pitch * (0.5 if square else 0.58) # the tile's farthest corner from its middle (hexagon: the circumradius)
	var half_x := float(size[0]) * 0.5 - reach
	var half_z := float(size[1]) * 0.5 - reach
	var count := ceili(maxf(float(size[0]), float(size[1])) / pitch) + 4
	var spots: Array[Transform3D] = []
	var colours := PackedColorArray()
	var family: Array = family_of(tone)
	for i in range(-count, count + 1):
		for j in range(-count, count + 1):
			var at := anchor + step_a * i + step_b * j
			if absf(at.x - float(middle[0])) > half_x or absf(at.y - float(middle[1])) > half_z: continue
			spots.append(Transform3D(Basis.IDENTITY, Vector3(at.x, tile_top, at.y)))
			colours.append(tint(family, GROUND_FLOOR, Vector2i(i, j), false))
	if spots.is_empty(): return
	var tiles_mesh := _tile_mesh(square, pitch, GROUND_CHAMFER, flat, true, GROUND_CHAMFER)
	tiles_mesh.surface_set_material(0, _material(SHADER, square, true))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = tiles_mesh
	multi.instance_count = spots.size()
	for k in spots.size():
		multi.set_instance_transform(k, spots[k])
		multi.set_instance_color(k, colours[k])
	var tiles_node := MultiMeshInstance3D.new()
	tiles_node.name = "StageGroundTiles"
	tiles_node.multimesh = multi
	level_root.add_child(tiles_node)

## The transform of tile `index` standing, `down` metres lower (a warned tile sinks by SINK_SHARE of its thickness), at `size` times its size (GONE_SCALE for a gone one).
func _stand(index: int, down := 0.0, size := 1.0) -> Transform3D:
	var at: Vector3 = (_tiles[index] as Dictionary).p - Vector3(0.0, down, 0.0)
	return Transform3D(Basis.IDENTITY.scaled(Vector3(size, size * _scale_y[index], size)), at)

## True under the Compatibility renderer, which hands the vertex and instance colours to a shader already linear (the tile shaders convert from sRGB otherwise).
static func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

## The three shades of the colour family a floor of colour `tone` wears: the family of `CandyLook.TILE_FAMILIES` nearest in hue (within FAMILY_HUE_GAP), else the tone alone. Under a cast with brand colours
## the family's hue is its role's (FAMILY_ROLE: P, S or A of `CandyCourse.scheme()`): the same saturation and value, the hue of the brand's colour; the default scheme gives the family as it is.
## The family of a layer: `family_of`, but in a square round the start layer (`pads`) is the blue pad family where the level says yellow-orange (the arena is blue and the orange is the rail's) and the blue floors under it are the deeper mat family.
static func layer_family(tone: Color, square := false, pads := false) -> Array:
	if square and pads and _is_hue(tone, "yellow"): return _branded(CandyLook.TILE_PADS_SQUARE, "sky")
	if square and not pads and _is_hue(tone, "blue"): return _branded(CandyLook.TILE_MATS_SQUARE, "mats") # the blue floors under the pads: deep mats
	return family_of(tone)

static func _is_hue(tone: Color, family: String) -> bool:
	return absf(fposmod(tone.h - ((CandyLook.TILE_FAMILIES[family] as Array)[1] as Color).h + 0.5, 1.0) - 0.5) < FAMILY_HUE_GAP

static func family_of(tone: Color) -> Array:
	var best: Array = [tone]
	var best_name := ""
	var gap := FAMILY_HUE_GAP
	for name: String in CandyLook.TILE_FAMILIES:
		var shades: Array = CandyLook.TILE_FAMILIES[name]
		var apart := absf(fposmod(tone.h - (shades[1] as Color).h + 0.5, 1.0) - 0.5)
		if apart < gap:
			gap = apart
			best = shades
			best_name = name
	return _branded(best, best_name) if best_name != "" else best

## `shades` of family `name` with the hue of the family's role in the current cast's scheme (unchanged for the default scheme).
static func _branded(shades: Array, name: String) -> Array:
	var scheme := CandyCourse.scheme()
	var role: Dictionary = scheme[FAMILY_ROLE[name]]
	var default_role: Dictionary = {"p": CandyCourse.DEFAULT_P, "s": CandyCourse.DEFAULT_S, "a": CandyCourse.DEFAULT_A}[FAMILY_ROLE[name]]
	if (role.main as Color).is_equal_approx(default_role.main): return shades
	var hue: float = (role.main as Color).h + float(ROLE_HUE_SHIFT[name])
	var mid: float = (shades[1] as Color).h
	var result: Array = []
	for shade: Color in shades: # each shade keeps its small hue offset from the family's middle shade
		result.append(Color.from_hsv(fposmod(hue + fposmod(shade.h - mid + 0.5, 1.0) - 0.5, 1.0), shade.s, shade.v))
	return result

## The standing colour of the tile at `cell` of a floor wearing `family` (family_of): one of its shades by hash (the three equally often), with a slight fixed jitter in brightness;
## the first shade with the jitter alone when `patches` is off (a one-colour kind, the ground). A pure function of (floor, cell): every machine draws the same floor.
static func tint(family: Array, floor_index: int, cell: Vector2i, patches := true, jitter := true) -> Color:
	var a := _hash(floor_index * 977 + cell.x * 131 + cell.y * 17 + SEED)
	var c := _hash(floor_index * 59 + cell.x * 257 + cell.y * 43 + SEED * 5)
	var shade: Color = family[mini(int(a * family.size()), family.size() - 1)] if patches else family[mini(1, family.size() - 1)]
	var color := Color.from_hsv(shade.h, shade.s, minf(shade.v * (0.97 + 0.06 * c), 1.0) if jitter else shade.v)
	color.a = 1.0
	return color

## The warning colour of a tile standing in `color`: its own colour lifted towards white.
static func warned(color: Color) -> Color:
	return color.lerp(Color.WHITE, CandyLook.TILE_WARN_LIFT)

static func _hash(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	return float((x ^ (x >> 16)) & 0xffff) / 65535.0

## The mesh of one tile with its top at y = 0: a flat top, a `chamfer` all round it (a 45 degree slope, default CHAMFER_SHARE of `thick`), a vertical side down to -thick and an underside
## (`top_only`: the top and the chamfer alone, a frustum that lies on a tray), one surface; the vertex colour is a shade (1 on the top, FOOT_SHADE at the foot of the chamfer and below).
static func _tile_mesh(square: bool, pitch: float, thick: float, flat := false, top_only := false, chamfer := -1.0) -> ArrayMesh:
	var cut := minf(thick * CHAMFER_SHARE if chamfer < 0.0 else chamfer, thick)
	var outer: PackedVector2Array
	var apothem := pitch * 0.5
	if square: outer = SquareGrid.corners(pitch * 0.5)
	else: outer = HexGrid.hex_corners(pitch / sqrt(3.0))
	if flat: # a flat-top hexagon: the pointy one turned a quarter
		for index in outer.size(): outer[index] = Vector2(outer[index].y, outer[index].x)
	var inner := PackedVector2Array()
	for corner in outer: inner.append(corner * (1.0 - cut / apothem))
	var builder := _Builder.new()
	var count := outer.size()
	for k in count: # top: a fan around the middle
		var a := inner[k]
		var b := inner[(k + 1) % count]
		builder.triangle(Vector3.ZERO, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3.UP, 1.0, 1.0, 1.0)
	for k in count:
		var next := (k + 1) % count
		var middle := (outer[k] + outer[next]) * 0.5
		var out := Vector3(middle.x, 0.0, middle.y).normalized()
		var rim_a := Vector3(inner[k].x, 0.0, inner[k].y)
		var rim_b := Vector3(inner[next].x, 0.0, inner[next].y)
		var foot_a := Vector3(outer[k].x, -cut, outer[k].y)
		var foot_b := Vector3(outer[next].x, -cut, outer[next].y)
		builder.chamfer(rim_a, rim_b, foot_b, foot_a, out, 1.0, FOOT_SHADE)
		if top_only or thick - cut < 0.0005: continue
		var low_a := Vector3(outer[k].x, -thick, outer[k].y)
		var low_b := Vector3(outer[next].x, -thick, outer[next].y)
		builder.quad(foot_a, foot_b, low_b, low_a, out, FOOT_SHADE, FOOT_SHADE, FOOT_SHADE, FOOT_SHADE)
		builder.triangle(Vector3(0.0, -thick, 0.0), low_b, low_a, Vector3.DOWN, 1.0, FOOT_SHADE, FOOT_SHADE)
	return builder.mesh()

## The ground tray: a slab `size` (x, z) wide and `thick` deep with its top at y = 0, a `chamfer` all round the top edge, vertical sides and no underside (nothing sees it); vertex shades as the tiles'.
static func _tray_mesh(size: Vector2, thick: float, chamfer: float) -> ArrayMesh:
	var half := size * 0.5
	var inset := half - Vector2(chamfer, chamfer)
	var builder := _Builder.new()
	var outer: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var inner: Array[Vector2] = [Vector2(-inset.x, -inset.y), Vector2(inset.x, -inset.y), Vector2(inset.x, inset.y), Vector2(-inset.x, inset.y)]
	var top: Array[Vector3] = []
	for corner in inner: top.append(Vector3(corner.x, 0.0, corner.y))
	builder.quad(top[0], top[1], top[2], top[3], Vector3.UP, 1.0, 1.0, 1.0, 1.0)
	for k in 4:
		var next := (k + 1) % 4
		var out := Vector3((outer[k] + outer[next]).x, 0.0, (outer[k] + outer[next]).y).normalized()
		var foot_a := Vector3(outer[k].x, -chamfer, outer[k].y)
		var foot_b := Vector3(outer[next].x, -chamfer, outer[next].y)
		builder.chamfer(top[k], top[next], foot_b, foot_a, out, 1.0, FOOT_SHADE)
		builder.quad(foot_a, foot_b, Vector3(foot_b.x, -thick, foot_b.z), Vector3(foot_a.x, -thick, foot_a.z), out, FOOT_SHADE, FOOT_SHADE, FOOT_SHADE, FOOT_SHADE)
	return builder.mesh()

## Triangles and quads with flat normals and a grey vertex shade per corner (the foot of a chamfer darker), wound so their front faces `outward` (Godot's front faces are clockwise).
class _Builder extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func triangle(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, shade_a: float, shade_b: float, shade_c: float) -> void:
		var first := vertices.size()
		var corners: Array[Vector3] = [a, b, c]
		var shades: Array[float] = [shade_a, shade_b, shade_c]
		for k in 3:
			vertices.append(corners[k])
			normals.append(outward)
			colors.append(Color(shades[k], shades[k], shades[k]))
		if (b - a).cross(c - a).dot(outward) > 0.0: indices.append_array(PackedInt32Array([first, first + 2, first + 1]))
		else: indices.append_array(PackedInt32Array([first, first + 1, first + 2]))

	## The chamfer between a top edge (a, b) and a foot edge (c, d): the slope's own winding, but smoothed vertex normals (tilted up at the top edge, out at the foot) so the slope shades as a gradient: a rounded edge.
	func chamfer(a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, shade_top: float, shade_foot: float) -> void:
		var up := (Vector3.UP + out * CHAMFER_ROUND).normalized()
		var down := (out + Vector3.UP * CHAMFER_ROUND).normalized()
		var outward := (out + Vector3.UP).normalized()
		var corners: Array[Vector3] = [a, b, c, d]
		var normal_of: Array[Vector3] = [up, up, down, down]
		var shades: Array[float] = [shade_top, shade_top, shade_foot, shade_foot]
		var first := vertices.size()
		for k in 4:
			vertices.append(corners[k])
			normals.append(normal_of[k])
			colors.append(Color(shades[k], shades[k], shades[k]))
		for order in [[0, 1, 2], [0, 2, 3]]:
			if (b - a).cross(c - a).dot(outward) > 0.0: indices.append_array(PackedInt32Array([first + order[0], first + order[2], first + order[1]]))
			else: indices.append_array(PackedInt32Array([first + order[0], first + order[1], first + order[2]]))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, shade_a: float, shade_b: float, shade_c: float, shade_d: float) -> void:
		triangle(a, b, c, outward, shade_a, shade_b, shade_c)
		triangle(a, c, d, outward, shade_a, shade_c, shade_d)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var result := ArrayMesh.new()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result

## Tile `index` in `mode` (levels/step_tiles.gd MODE_*): standing, warning (a pale tone of its own colour and sunk by SINK_SHARE of its thickness at once) or gone (a fall mode does not exist here: the exit is one frame).
## `tau` and `delay` are the other look's (the signature is shared).
func pose(index: int, mode: int, _tau: float, _delay: float) -> void:
	var multi: MultiMesh = _multis[int((_tiles[index] as Dictionary).floor)]
	var instance := _slot[index]
	match mode:
		0:
			if _last[index] == 0: return
			multi.set_instance_transform(instance, _stand(index))
			multi.set_instance_color(instance, _base[index])
		1:
			if _last[index] == 1: return
			multi.set_instance_transform(instance, _stand(index, _sink))
			multi.set_instance_color(instance, _warn[index])
		_:
			if _last[index] == 3: return
			multi.set_instance_transform(instance, _stand(index, _sink, GONE_SCALE))
			multi.set_instance_color(instance, _warn[index])
			mode = 3
	_last[index] = mode

## The floors (indices into the level's floors, step_tiles.gd ghost_floors) whose tiles are not drawn; the others are drawn again. `instant`: every floor is whole or gone
## at once (a fixed shot, a check); else they fade over FADE_TIME s, driven by advance_fade (the view calls it every frame).
func set_ghosted(floors: PackedInt32Array, instant := true) -> void:
	for floor_index in _nodes.size():
		var hide := floors.has(floor_index)
		_hidden[floor_index] = 1 if hide else 0
		if instant:
			_fade[floor_index] = 0.0 if hide else 1.0
			_show_fade(floor_index)

## Moves the floors' fade `dt` seconds towards their target (gone for a ghosted floor, whole for the others). A floor that is whole is drawn by the plain opaque shader, a
## floor that is gone is not visible (no draw call); only a floor in between wears its own dither material.
func advance_fade(dt: float) -> void:
	for floor_index in _nodes.size():
		var target := 0.0 if _hidden[floor_index] == 1 else 1.0
		var now: float = _fade[floor_index]
		if now == target: continue
		var next := move_toward(now, target, dt / FADE_TIME)
		_fade[floor_index] = target if absf(next - target) < 0.0001 else next # the last step lands exactly (a float sum of 12 twelfths is not 1)
		_show_fade(floor_index)

## Puts floor `floor_index` into the state its fade says: whole (plain material), gone (not visible) or in between (the dither material at that fade).
func _show_fade(floor_index: int) -> void:
	var node: GeometryInstance3D = _nodes[floor_index]
	var amount: float = _fade[floor_index]
	node.visible = amount > 0.0
	if amount > 0.0 and amount < 1.0:
		var material: ShaderMaterial = _fade_materials[floor_index]
		material.set_shader_parameter("fade", amount)
		node.material_override = material
	else:
		node.material_override = null

## True while tile `index` is not drawn because its floor is ghosted (it is on its way out or gone).
func is_ghosted(index: int) -> bool:
	return _hidden[int((_tiles[index] as Dictionary).floor)] == 1

## True while floor `floor_index` is drawn whole by the plain shader.
func is_whole(floor_index: int) -> bool:
	return _fade[floor_index] >= 1.0
