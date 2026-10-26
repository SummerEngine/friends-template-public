extends RefCounted
## The block kit: how the static blocks of a `world: daylight` level (and of the stage rounds' side blocks, the lobby yard's deck) are built, in the candy look (style/real_look.gd `draw_level` asks
## `dress`). Everything is simple glossy primitives in flat authored colours (style/race_surfaces.gd, style/candy_surface.gdshader); no brick courses, no grooves, no trim, no outline:
##  * a FLOOR block (the P tone `teal`, the A tone `warm`, `court`, every ground and hop block): a PILLOW slab, flat colour, its open top edges inflated into a rounded shoulder (EDGE_ROUND, smooth normals,
##    BlockMesh.Batch.pillow_slab) and a small chamfer under the bottom edge, rounded upright corners; a big floor is a quilt of mats whose seams are soft pinched creases (SEAM_ROUND); an edge where another
##    walkable block joins at the same height, or a wall or rail stands on it, stays square, so a joint reads as one floor (`Index.closed_edges`). The shoulders cut INTO the collision box and the top
##    stays exactly in the collision plane: the visual never stands proud of it.
##  * a wall (tone `navy`, or a wall without a tone): a PILLOW piece, a box rounded with a radius up to half its thickness (an inflatable's bulging section, smooth normals), vinyl;
##  * everything else (door frames, crates, small decorative blocks): the tone's own surface on a box with a chamfer-sized rounding (door-sized pieces 0.09 m).
## Tall slim columns are the pillar kit's (style/pillar_kit.gd). Nothing here moves a collision shape.
## The kit's own parts share two materials of style/candy_surface.gdshader, the colour being the vertex colour (sRGB): KEY (vinyl, roughness 0.45) and KEY_PLASTIC (hard plastic, 0.11), and KEY_TALL (the vinyl again, for the tall parts: it dissolves near the camera, style/near_dissolve.gdshaderinc).
## `tile_grid` is only the LAYOUT the bounce pads and the movers' arrows are placed on (a cell of 2 x 2 tiles), nothing is drawn on it.
const BlockMesh := preload("res://style/block_mesh.gd")
const RaceSurfaces := preload("res://style/race_surfaces.gd")
const CandyMaterial := preload("res://style/candy_material.gd")
const CandyLook := preload("res://style/candy_look.gd")
const CandyCourse := preload("res://style/candy_course.gd")
const LIGHT_SHARE := 0.4                  ## the share of a platform's slabs that wear the light tone of their family (`floor_block`), picked by a hash of the slab's place
const KEY := "kit:flat"                   ## the surface key of the kit's own vinyl parts
const KEY_PLASTIC := "kit:plastic"        ## ... and of its hard plastic parts
const KEY_TALL := "kit:tall"              ## the vinyl of the kit's TALL parts (gate frames, the lobby's sign boards and pylons): dissolves near the camera (CandyMaterial.NEAR_TALL), where KEY (floors, platforms) does not
const PILLAR_KIT := "res://style/pillar_kit.gd"
const BRICK := 1.0                        ## vertex alpha of a side colour (always 1), as the movers' fallback slab writes it

# The tile grid LAYOUT of a platform (metres): square tiles with a groove between, a rim ring round them; only the cells are used (style/pad_look.gd, style/mover_look.gd), nothing is drawn.
const TILE_TOP := 0.0
const GROOVE := 0.11
const RIM_MIN := 0.18
const RIM_MAX := 0.42
const RIM_PREF := 0.24
const TILE_TARGET := 1.5
const TILE_UNIT := 1.5
const TILE_STONE := 1.2
const STONE_MAX := 9.0
const TILE_MIN := 0.5

const WALK_MIN_SIDE := 1.4    ## a walkable platform: its short side, its top area (m^2) and its thickness (m) at least this (only the stage rounds' kit asks)
const WALK_MIN_AREA := 4.0
const WALK_MIN_THICK := 0.5
const PLANT := 0.03           ## a block standing on a platform is drawn from this far under the platform's top
const FLAT_TOPS := ["finish", "stone"] ## tones (besides the floor tones) whose box top is a walkable surface: a platform's edge meeting one at the same height stays square
const FLOOR_TONES := ["teal", "warm", "court"]
const BOTTOM_SHARE := 0.4     ## the underside's chamfer as a share of the top's
const CORNER := 0.15          ## radius of the upright corners (at most a fifth of the short side)
const CRATE_PINK := Color("#ee7fe6")   ## the crate tone's cushions
const MAT := 5.0              ## m: about the side of one mat of a big floor
const MAT_MIX := 0.45         ## the alternate mat's mix of the light tone into the floor tone
const SEAM_ROUND := 0.1       ## m: the rounding of the two edges of a mat that meet the next mat: together a soft pinched crease
const SHOULDER_SHADE := 0.04  ## share of the floor colour the shoulder's lower edge and the seams darken by
const EDGE_ROUND := 0.45      ## m: the shoulder of an open floor edge (a pillow's rounded rim)
const PILLOW_SHARE := 0.95    ## a wall's rounding reaches this share of half its thickness: a full pillow section
const PILLOW_MAX := 0.34
const PILLOW_SEGMENTS := 4
const FRAME_MAX := 0.4        ## m: the rounding of a beam or post
const BEAM_SECTION := 2.6     ## m: about the length of one section of a long beam
const PILLOW_LENGTH := 12.0   ## m: the longest section of a pillow piece in x or z
const PILLOW_GROW := 0.12     ## m of rounding per metre of thickness over 0.7 m
const PILLOW_BIG := 1.3       ## m: the rounding of the biggest blocks
const PILLOW_TALL := 4.5      ## m: a pillow at least this high is stacked in tiers ...
const PILLOW_FAT := 3.0       ## ... and so is one this thick (and over 3 m high)
const PILLOW_TIER := 6.0      ## m: about as high as a tier is

## The palette of a floor tone as `floor_block` colours: {a: the top, side}. "mover" is no level tone: the movers' platform (style/mover_look.gd), amber with a white rim and arrows, so it reads
## against the blue floors; `b` and `groove` are its second tile tone and its dark.
const FLOORS := {
	"mover": {"a": "#efaa2b", "b": "#f5b94a", "rim": "#f8f4f3", "groove": "#c27a0c", "side": "#e06418", "sub": "#e06418", "leg": "#e06418", "arrow": "#f8f4f3"},
}

static var _pillar: Variant = false ## the pillar kit script once looked for (null when the file does not exist)

static func is_key(key: String) -> bool:
	return key == KEY or key == KEY_PLASTIC or key == KEY_TALL

## The material of the kit's vinyl parts: the vertex colour is the albedo (made once, shared by every level).
static func material(near := CandyMaterial.NEAR_FLOOR) -> ShaderMaterial:
	return CandyMaterial.make(_kit_spec(RaceSurfaces.VINYL_ROUGH, near)) # a faint cyan lift at grazing angles: the vinyl read of the far floor

## ... the same vinyl for the kit's tall parts, which dissolve near the camera (KEY_TALL).
static func tall_material() -> ShaderMaterial:
	return CandyMaterial.make(_kit_spec(RaceSurfaces.VINYL_ROUGH, CandyMaterial.NEAR_TALL))

static func _kit_spec(roughness: float, near: Dictionary) -> Dictionary:
	var spec := {"albedo": Color.WHITE, "use_vertex_color": true, "roughness": roughness, "crease": 1.0, "rim_color": RaceSurfaces.GRAZE_COLOR, "rim_power": RaceSurfaces.GRAZE_POWER}
	if roughness <= CandyLook.ROUGH_PLASTIC + 0.001: spec.erase("crease")
	spec.merge(near, true)
	return spec

## ... and of its hard plastic parts.
static func plastic_material() -> ShaderMaterial:
	return CandyMaterial.make(_kit_spec(CandyLook.ROUGH_PLASTIC, CandyMaterial.NEAR_TALL))

## The material of kit key `key` (KEY, KEY_PLASTIC or KEY_TALL); `near`: the dissolve distances of the floor key (CandyMaterial.NEAR_FLOOR, the lobby's deck NEAR_FLOOR_LOW).
static func material_of(key: String, near := CandyMaterial.NEAR_FLOOR) -> ShaderMaterial:
	if key == KEY_TALL: return tall_material()
	return plastic_material() if key == KEY_PLASTIC else material(near)

## The colours of a floor tone: {a: top, side, light (only teal and warm: the light tone of the family, worn by some slabs)}.
static func palette(name: String) -> Dictionary:
	if FLOORS.has(name): return FLOORS[name]
	var found := {"a": RaceSurfaces.colour(name, "top"), "side": RaceSurfaces.colour(name, "side")}
	if name == "teal": found.light = (CandyCourse.scheme().p as Dictionary).light
	elif name == "warm": found.light = (CandyCourse.scheme().a as Dictionary).light
	return found

## The blocks of a level that others can stand on, for `dress`: every static box of `jobs` (real_look.gd: {shape_node, hazard}) as its bounds in level space (`to_level`: world -> level). `role_of` (a Callable
## taking a CollisionShape3D, returning its role 0 ground, 1 wall, 2 hop block) tells which boxes are floor: a floor-role box of a floor tone (any size: a thin connecting strip counts) or of a flat top tone
## (FLAT_TOPS: the finish strip, stepping stones) is a walkable top. The index answers which edges of a platform meet another walkable top at the same height (a joint) or have a rail or wall standing on them
## (`Index.closed_edges`), which stay square.
static func index(jobs: Array, to_level: Transform3D, role_of: Callable) -> Index:
	var found := Index.new()
	for job: Dictionary in jobs:
		var shape_node: CollisionShape3D = job.shape_node
		if job.hazard or not shape_node.shape is BoxShape3D: continue
		var size := (shape_node.shape as BoxShape3D).size
		var role: int = role_of.call(shape_node)
		var tone := str(shape_node.get_meta("tone", ""))
		var name := tone if tone in RaceSurfaces.TONES else ("navy" if role == 1 else "teal")
		found.add(shape_node.get_instance_id(), to_level * shape_node.global_transform, size, role != 1 and (name in FLOOR_TONES or name in FLAT_TOPS))
	return found

## Whether a static box (tone `tone`, role `role`: 0 ground, 1 wall, 2 hop block; placed by `xf` in level space; `lift` the look's few-millimetre lift, real_look.gd `_lifts`) is drawn by the kit into `batch`.
## False for boxes it leaves to the plain look (tilted, scaled) and for the ones the pillar kit takes.
static func dress(batch: BlockMesh.Batch, shape_node: CollisionShape3D, xf: Transform3D, tone: String, role: int, lift: float, solids: Index) -> bool:
	var shape := shape_node.shape as BoxShape3D
	if shape == null or xf.basis.y.normalized().y < 0.999 or absf(xf.basis.x.length() - 1.0) > 0.01 or absf(xf.basis.y.length() - 1.0) > 0.01: return false
	var base := solids.floor_top(shape_node.get_instance_id(), xf, shape.size * 0.5) if solids != null else NAN # the top of the platform the block stands inside (NAN: none)
	var pillars: Variant = _pillar_kit()
	if pillars != null and pillars.dress(batch, shape_node, xf, tone, lift, base + lift): return true
	var name := tone if tone in RaceSurfaces.TONES else ("navy" if role == 1 else "teal")
	var lifted := xf
	lifted.origin.y += lift
	var closed: Array = solids.closed_edges(shape_node.get_instance_id(), xf, shape.size * 0.5) if solids != null else [[], [], [], []]
	var size := shape.size
	if not is_nan(base): # a block standing on or inside a platform (its footprint within the platform's): its drawn part starts 3 cm under the platform's top (planted, never a lift-sized gap, nothing of it in the slab)
		var top_y := xf.origin.y + size.y * 0.5
		var bottom_y := base - PLANT
		lifted.origin.y = (top_y + bottom_y) * 0.5 + lift
		size = Vector3(size.x, top_y - bottom_y, size.z)
		closed = [[], [], [], []]
	if name in FLOOR_TONES and role != 1:
		floor_block(batch, lifted, size, name, solids, closed)
	else:
		plain_block(batch, lifted, size, name, role)
	return true

## Whether a static box of `size` and role `role` (0 ground, 1 wall, 2 hop block) is a walkable platform (a stage round's kit asks).
static func walkable(size: Vector3, role: int) -> bool:
	return role != 1 and minf(size.x, size.z) >= WALK_MIN_SIDE and size.x * size.z >= WALK_MIN_AREA and size.y >= WALK_MIN_THICK

static func _pillar_kit() -> Variant:
	if typeof(_pillar) == TYPE_BOOL:
		_pillar = load(PILLAR_KIT) if ResourceLoader.exists(PILLAR_KIT) else null
	return _pillar

## ---- floors ----

## The rounding of the open top edges of a floor slab of `size`: a pillow's shoulder, EDGE_ROUND m on a thick slab (never more than 0.55 of its thickness and a quarter of its short side).
static func chamfer(size: Vector3) -> float:
	return minf(EDGE_ROUND, minf(size.y * 0.55, minf(size.x, size.z) * 0.25))

## A floor block of `size` placed by `xf` (its centre; the top face at +size.y / 2) wearing palette `name` (a floor tone or "mover"): one PILLOW slab, its open top edges inflated into a rounded shoulder with smooth
## normals (BlockMesh.Batch.pillow_slab; the mover's platform keeps its flat chamfer). `closed`: for each edge (+x, -x, +z, -z) the stretches [from, to] (metres along the edge from the block's middle) where another
## platform joins or a rail or wall stands: an edge mostly closed stays square. A big floor is a quilt of mats whose seams are soft pinched creases (SEAM_ROUND). The top stays exactly in the collision plane. Returns true.
static func floor_block(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3, name: String, _solids: Index, closed: Array, varied := true) -> bool:
	var colours := palette(name)
	var top := _color(colours.a)
	var side := _color(colours.side)
	if name != "mover": side = side.darkened(SHOULDER_SHADE) # the shoulder fades into a slightly deeper tone where it turns away: the crease of a mat reads as a soft shadow line
	if varied and colours.has("light") and size.x < MAT * 1.4 and size.z < MAT * 1.4 and _lighter(xf.origin) < LIGHT_SHARE: top = _color(colours.light) # a share of the small slabs wear the family's light tone
	var half := size * 0.5
	var c := chamfer(size)
	var cuts := PackedFloat32Array([c, c, c, c])
	var seams := 0 # bit i: edge i is a pinched seam (the crease shading of the surface shader applies there)
	for edge in 4:
		var length := size.z if edge < 2 else size.x
		if edge < closed.size() and _covered(closed[edge], length) > 0.5:
			cuts[edge] = minf(SEAM_ROUND, c) # a joint or a wall's foot: a pinched seam, not a shoulder
			seams |= 1 << edge
	var mats_x := maxi(1, roundi(size.x / MAT)) if varied and colours.has("light") else 1
	var mats_z := maxi(1, roundi(size.z / MAT)) if varied and colours.has("light") else 1
	var corner := minf(CORNER, minf(size.x, size.z) * 0.2)
	var pillow := name != "mover"
	if mats_x * mats_z == 1:
		if pillow: batch.pillow_slab(KEY, xf, half, cuts, c * BOTTOM_SHARE, corner, top, side, seams)
		else: batch.chamfered(KEY, xf, half, cuts, c * BOTTOM_SHARE, corner, top, side)
		return true
	# a big floor is a quilt of mats (about MAT m a side) that alternate the family's tone and a mix with its light tone; the seam between two mats is a soft pinched crease
	var alt := _color(colours.a).lerp(_color(colours.light), MAT_MIX)
	var mat := Vector3(size.x / float(mats_x), size.y, size.z / float(mats_z))
	var seam := minf(SEAM_ROUND, c)
	for i in mats_x:
		for k in mats_z:
			var edges := PackedFloat32Array([cuts[0] if i == mats_x - 1 else seam, cuts[1] if i == 0 else seam, cuts[2] if k == mats_z - 1 else seam, cuts[3] if k == 0 else seam])
			var at := Vector3(-half.x + mat.x * (float(i) + 0.5), 0.0, -half.z + mat.z * (float(k) + 0.5))
			var mat_seams := (0 if i == mats_x - 1 and cuts[0] > seam else 1) | (0 if i == 0 and cuts[1] > seam else 2) | (0 if k == mats_z - 1 and cuts[2] > seam else 4) | (0 if k == 0 and cuts[3] > seam else 8)
			batch.pillow_slab(KEY, Transform3D(xf.basis, xf * at), mat * 0.5, edges, c * BOTTOM_SHARE, 0.05, _color(colours.a) if (i + k) % 2 == 0 else alt, side, mat_seams)
	return true

## The share of an edge `length` long that the stretches `spans` ([from, to] pairs) cover.
static func _covered(spans: Array, length: float) -> float:
	var total := 0.0
	for span: Array in spans: total += float(span[1]) - float(span[0])
	return total / maxf(length, 0.001)

## 0 to 1 from a slab's place (to the 1/4 m): the same on every machine and in every copy of the level.
static func _lighter(origin: Vector3) -> float:
	var x := ((roundi(origin.x * 4.0) * 73856093) ^ (roundi(origin.y * 4.0) * 19349663) ^ (roundi(origin.z * 4.0) * 83492791)) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return float((x ^ (x >> 16)) & 0xFFFF) / 65536.0

static func _color(value: Variant) -> Color:
	return value as Color if value is Color else Color(str(value))

## Where the tile grid of the platform of `size` placed by `xf` (level space, upright, no lift) lies, for what sits on it (a bounce pad takes a 2 x 2 block of tiles): {t: tile side, pitch: t + the groove, nx, nz:
## tiles along the block's x and z axes, origin: the middle of tile (0, 0) on the top face (level space), axis_x, axis_z: the unit steps along the grid (the block's own x and z), top: the top's height}. The tile of
## index (i, j) is at origin + axis_x * pitch * i + axis_z * pitch * j. Empty for a block without a grid. The grid does not depend on neighbours; it is a layout only, nothing is drawn on it.
static func tile_grid(xf: Transform3D, size: Vector3) -> Dictionary:
	var fit := _fit(size.x, size.z)
	if fit.is_empty(): return {}
	var half := size * 0.5
	var t := float(fit.t)
	var axis_x := xf.basis.x.normalized()
	var axis_z := xf.basis.z.normalized()
	var origin := xf * Vector3(-half.x + float(fit.rx) + GROOVE + t * 0.5, half.y + TILE_TOP, -half.z + float(fit.rz) + GROOVE + t * 0.5)
	return {"t": t, "pitch": t + GROOVE, "nx": int(fit.nx), "nz": int(fit.nz), "origin": origin, "axis_x": axis_x, "axis_z": axis_z, "top": xf.origin.y + half.y + TILE_TOP}

static var _fits := {}

## How square tiles fill a platform `width` x `depth` m (x, z): {t: tile side, nx, nz: how many each way, rx, rz: the rim ring's width along the z-running and the x-running edges}. A STONE (no side over
## STONE_MAX) has round(side / TILE_UNIT) tiles each way (1 at least), all of about TILE_STONE m (the rim ring absorbs what is left, RIM_MIN to RIM_MAX); a larger platform's count is the most tiles of about
## TILE_TARGET m that fit. The tile side moves within TILE_MIN to 1.3 x TILE_TARGET so that a whole number fits both ways with the rim ring; equal rims, a rim near RIM_PREF and (large platforms) an even
## number of tiles each way win. Empty when nothing fits.
static func _fit(width: float, depth: float) -> Dictionary:
	var key := Vector2i(roundi(width * 100.0), roundi(depth * 100.0))
	if _fits.has(key): return _fits[key]
	var found := _search(width, depth, maxf(width, depth) <= STONE_MAX)
	if found.is_empty(): found = _search(width, depth, false) # a stone whose two sides ask for tiles of different sizes (5 x 5.5 m): the fallback, the most tiles of about TILE_TARGET
	_fits[key] = found
	return found

static func _search(width: float, depth: float, stone: bool) -> Dictionary:
	var aim := TILE_STONE if stone else TILE_TARGET
	var best := {}
	var best_score := INF
	var t := TILE_MIN
	while t <= TILE_TARGET * 1.3 + 0.0001:
		var nx := maxi(roundi(width / TILE_UNIT), 1) if stone else floori((width - 2.0 * RIM_MIN - GROOVE) / (t + GROOVE))
		var nz := maxi(roundi(depth / TILE_UNIT), 1) if stone else floori((depth - 2.0 * RIM_MIN - GROOVE) / (t + GROOVE))
		if nx >= 1 and nz >= 1:
			var rx := (width - float(nx) * t - float(nx + 1) * GROOVE) * 0.5
			var rz := (depth - float(nz) * t - float(nz + 1) * GROOVE) * 0.5
			if rx <= RIM_MAX and rz <= RIM_MAX and rx >= RIM_MIN - 1e-6 and rz >= RIM_MIN - 1e-6:
				var odd := 0.0 if stone else (0.05 if nx % 2 == 1 else 0.0) + (0.05 if nz % 2 == 1 else 0.0)
				var score := absf(rx - rz) * 2.0 + absf(t - aim) * (4.0 if stone else 1.0) + (absf(rx - RIM_PREF) + absf(rz - RIM_PREF)) * (0.1 if stone else 0.4) + odd
				if score < best_score:
					best_score = score
					best = {"t": t, "nx": nx, "nz": nz, "rx": rx, "rz": rz}
		t += 0.01
	return best

## ---- everything else ----

## Any block that is no floor slab: a wall is a PILLOW (a box rounded by up to half its thickness, vinyl), any other tone's own flat surface on a box with the tone's rounding (door-sized pieces
## 0.09 m, RaceSurfaces.RADIUS). A floor tone's block that is not drawn as a slab (never: `dress` sends floors to `floor_block`) wears its flat side surface on every face.
static func plain_block(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3, name: String, role: int) -> void:
	var keys := RaceSurfaces.keys(name, role)
	if name in FLOOR_TONES: keys = [keys[1], keys[1], keys[1]]
	if role == 1 or name == "navy":
		pillow(batch, xf, size, keys)
		return
	if name == "crate":
		var c := CandyCourse.scheme()
		pillow(batch, xf, size, keys, [CRATE_PINK, (c.p as Dictionary).light]) # a clean pink cushion (a white one in the violet shadow reads dusty lavender), light-blue bands when it is tall
		return
	if name == "frame": # a beam or post: an inflated tube, the rounding nearly the half of its thinnest side; a long beam is a string of sections that touch, the rounded ends pinching it like an inflatable's seams
		var thin := minf(size.x, minf(size.y, size.z))
		var axis := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
		var sections := clampi(roundi(size[axis] / BEAM_SECTION), 1, 6) if size[axis] >= BEAM_SECTION * 1.4 and size[axis] >= thin * 3.0 else 1
		var piece := size
		piece[axis] = size[axis] / float(sections)
		for index in sections:
			var at := Vector3.ZERO
			at[axis] = -size[axis] * 0.5 + piece[axis] * (float(index) + 0.5)
			batch.box(Transform3D(xf.basis, xf * at), piece, minf(thin * 0.48, FRAME_MAX), 3, keys[0], keys[1], Color.WHITE, 0.0, true, keys[2], 1.0)
		return
	batch.box(xf, size, RaceSurfaces.radius(keys[1]), 2, keys[0], keys[1], Color.WHITE, 0.0, true, keys[2])

## A pillow: a box rounded by up to PILLOW_SHARE of half its thickness, PILLOW_SEGMENTS steps a corner, so the surface bulges the way an inflatable section does and every normal leans smoothly off
## the face's. The rounding is PILLOW_MAX on a thin wall and grows with the thickness of a fat block (PILLOW_GROW per metre over 0.7 m, PILLOW_BIG at most). A piece longer than PILLOW_LENGTH
## in x or z is cut into equal sections of at most that length that touch (the rounded ends make the pinch between two inflatable pieces, walls come in lengths of 2.5 to 12 m);
## a tall piece (at least PILLOW_TALL m, or a fat block, PILLOW_FAT m thick, over 3 m high) is stacked in tiers of about PILLOW_TIER m that alternate the S tone and its light tone, so a tower
## is a stack of cushions, not one flat blob. `keys`: [top, side, end] surface keys of the plain pillow; `tiers_pair`: the two colours of the tiers (default the S tone and its light tone).
static func pillow(batch: BlockMesh.Batch, xf: Transform3D, size: Vector3, keys: Array, tiers_pair := []) -> void:
	var thick := minf(size.x, size.z)
	var banded := size.y >= PILLOW_TALL or (thick >= PILLOW_FAT and size.y >= 3.0)
	var tiers := maxi(1, roundi(size.y / PILLOW_TIER)) if banded else 1
	var tier := size.y / float(tiers)
	var round := minf(minf(PILLOW_MAX + maxf(thick - 0.7, 0.0) * PILLOW_GROW, PILLOW_BIG), minf(minf(thick, tier) * 0.5 * PILLOW_SHARE, size.y * 0.45))
	var count_x := maxi(1, ceili(size.x / PILLOW_LENGTH - 0.001))
	var count_z := maxi(1, ceili(size.z / PILLOW_LENGTH - 0.001))
	var piece := Vector3(size.x / float(count_x), tier, size.z / float(count_z))
	var stone := RaceSurfaces.keys("stone", 1)
	var scheme := {"main": tiers_pair[0], "light": tiers_pair[1]} if not tiers_pair.is_empty() else {"main": (CandyCourse.scheme().s as Dictionary).main, "light": (CandyCourse.scheme().s as Dictionary).deep}
	for level in tiers:
		for i in count_x:
			for k in count_z:
				var at := Vector3(-size.x * 0.5 + piece.x * (float(i) + 0.5), -size.y * 0.5 + tier * (float(level) + 0.5), -size.z * 0.5 + piece.z * (float(k) + 0.5))
				var section := Transform3D(xf.basis, xf * at)
				if not banded: batch.box(section, piece, round, PILLOW_SEGMENTS, keys[0], keys[1], Color.WHITE, 0.0, true, keys[2], 1.0)
				else: batch.box(section, piece, round, PILLOW_SEGMENTS, stone[0], stone[1], scheme.main if level % 2 == 0 else scheme.light, 0.0, true, stone[2], 1.0)

## The bounds of a level's static boxes in a coarse grid: which edges of a platform meet another platform or have a rail or wall on them, and which platform a block stands inside.
class Index extends RefCounted:
	const CELL := 8.0
	const COPLANAR := 0.06    ## a platform whose top is this close to another's joins it into one surface
	const RISE := 0.25        ## a block that stands this far over a platform's top (and reaches down to it) is a rail or wall on it
	var cells := {}           # Vector2i -> Array of [x0, z0, x1, z1, y0, y1, id, walkable]

	func add(id: int, xf: Transform3D, size: Vector3, walk: bool) -> void:
		var half := size * 0.5
		var basis := xf.basis
		var extent := Vector3(
			absf(basis.x.x) * half.x + absf(basis.y.x) * half.y + absf(basis.z.x) * half.z,
			absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z,
			absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z)
		var box := [xf.origin.x - extent.x, xf.origin.z - extent.z, xf.origin.x + extent.x, xf.origin.z + extent.z, xf.origin.y - extent.y, xf.origin.y + extent.y, id, walk]
		for cx in range(floori(box[0] / CELL), floori(box[2] / CELL) + 1):
			for cz in range(floori(box[1] / CELL), floori(box[3] / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key): cells[key] = []
				(cells[key] as Array).append(box)

	## The top of the block (not `id`) that the upright block `id` (`xf`, `half`, level space) stands inside: its footprint lies within the platform's and the platform's top is between the block's bottom and
	## top (up to 0.04 m under the bottom to 0.1 under the top). NAN when there is none.
	func floor_top(id: int, xf: Transform3D, half: Vector3) -> float:
		if xf.basis.x.x < 0.999: return NAN
		var c := xf.origin
		var found: Variant = cells.get(Vector2i(floori(c.x / CELL), floori(c.z / CELL)))
		if found == null: return NAN
		var best := NAN
		for box: Array in found:
			if int(box[6]) == id: continue
			if c.x - half.x < float(box[0]) - 0.05 or c.x + half.x > float(box[2]) + 0.05 or c.z - half.z < float(box[1]) - 0.05 or c.z + half.z > float(box[3]) + 0.05: continue
			var top := float(box[5])
			if top > c.y - half.y - 0.04 and top < c.y + half.y - 0.1 and (is_nan(best) or top > best): best = top
		return best

	## The stretches of the four edges (+x, -x, +z, -z; metres from the block's middle along the edge) of the upright, unturned platform `id` (`xf`, half size `half`, level space) where another platform joins it at
	## the same height or another block stands on its edge or against it, rising at least RISE over it. Empty lists for a turned block.
	func closed_edges(id: int, xf: Transform3D, half: Vector3) -> Array:
		var out: Array = [[], [], [], []]
		if xf.basis.x.x < 0.999: return out
		var c := xf.origin
		var top := c.y + half.y
		var seen := {}
		for cx in range(floori((c.x - half.x - 0.5) / CELL), floori((c.x + half.x + 0.5) / CELL) + 1):
			for cz in range(floori((c.z - half.z - 0.5) / CELL), floori((c.z + half.z + 0.5) / CELL) + 1):
				var found: Variant = cells.get(Vector2i(cx, cz))
				if found == null: continue
				for box: Array in found:
					if int(box[6]) == id or seen.has(box[6]): continue
					seen[box[6]] = true
					var inward := 0.0
					var outward := 0.0
					if bool(box[7]) and absf(float(box[5]) - top) <= COPLANAR:
						inward = 0.3
						outward = 0.12
					elif float(box[5]) >= top + RISE and float(box[4]) <= top + 0.1:
						inward = RIM_MAX + 0.1
						outward = 0.06
					else:
						continue
					# edge +x / -x: a strip across x, running along z; edge +z / -z: across z, running along x
					for edge in 4:
						var along_z := edge < 2
						var way := 1.0 if edge % 2 == 0 else -1.0
						var line := (c.x if along_z else c.z) + way * (half.x if along_z else half.z)
						var near := line - way * inward
						var far := line + way * outward
						var low_across := minf(near, far)
						var high_across := maxf(near, far)
						var b_low := float(box[0] if along_z else box[1])
						var b_high := float(box[2] if along_z else box[3])
						if b_high <= low_across or b_low >= high_across: continue
						var centre_along := c.z if along_z else c.x
						var reach := half.z if along_z else half.x
						var from := maxf(float(box[1] if along_z else box[0]), centre_along - reach) - centre_along
						var to := minf(float(box[3] if along_z else box[2]), centre_along + reach) - centre_along
						if to > from: (out[edge] as Array).append([from, to])
		return out
