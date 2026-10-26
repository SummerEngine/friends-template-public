extends RefCounted
## The facility collision look (style/collision_look.gd hands calls here): what you see is what you collide with, drawn as real
## surfaces (style/surfaces.gd).
## A client-only pass after a level is built (draw_level). Every collision shape of every static or moving body becomes a mesh with rounded
## edges and textures in world-aligned metres (style/block_mesh.gd); a shape's surface comes from its ROLE, its top's height above the
## level's path beside it:
##  * ground and low slabs: the floor on top, the base material on the sides;
##  * hop blocks (knee to head high): soft blocks in a few colours, one picked per block;
##  * walls and tall blocks you bump into: the wall material; ice: its own glossy surface;
##  * a conveyor belt (a shape with the meta "belt"): a dark rubber lane between yellow rails with green chevrons running the way it carries (style/belt_look.gdshader);
##  * moving bodies: platforms in the mover material (sides) and mover_top (tops), things that hurt in danger, spike posts in steel;
##  * the team's brand colour (TeamCast.brand_walls()): a painted stripe along the walls; "accent" also paints the end walls, pillars
##    and door frames whole; "full" every wall.
## All static shapes of a level merge into ONE mesh with one surface per material (ceilings into a second one that casts no sun shadow,
## so roofed rooms read as lit through skylights); each moving body gets one mesh as its child, so it moves
## exactly as the body does. Contact shadows come from the level's height field (style/height_field.gd). START and GOAL get painted floor
## pads and a GOAL word (no flags); the team cast puts its logo over the GOAL word.
## Nothing here touches collision, hazards or the network; the authority never runs it.
const Surfaces := preload("res://style/surfaces.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const HeightField := preload("res://style/height_field.gd")
const TeamCast := preload("res://style/team_cast.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const Party := preload("res://style/party_look.gd")
const WalkInLook := preload("res://style/walk_in_look.gd") ## the 3D parts of the lobby walk-in pads (client/walk_in_markers.gd builds them)
const SIGN_FONT := preload("res://assets/fonts/Archivo.ttf")
const BELT_SHADER := preload("res://style/belt_look.gdshader")
const Hazards := preload("res://levels/hazards.gd")
const RaceSurfaces := preload("res://style/race_surfaces.gd") ## the blocks of a `world: daylight` level
const BlockKit := preload("res://style/block_kit.gd") ## the platform / wall kit of a `world: daylight` level's static boxes (chamfered floor slabs, pillow walls, the pillar kit's columns)
const WATER_Y := -8.0
const GATE_LIFT := 0.03        # the start gate (a `blink` box with the slot gate) is drawn this far higher than its collision (never a plane shared with a tile top; under the rim pieces' 4.5 cm)
const DOOR_FOOT := 0.015       # a door slab (tone door, or a cycling door) is drawn this far lower at its foot than its collision: a shut door sits 1.5 cm in the floor, not on a shared plane
const LIFT_STEP := 0.003       # visual lift between shapes whose tops stand at the same height
const LIFT_CLASSES := 9
const HAZARD_LIFT := 0.015
const TOP_Y := 0.65            # a face whose normal points this far up is walkable (a top)
const SLAB := 0.7              # shapes whose top is lower than this (metres) above the route beside them are ground; up to WALL hop blocks, above walls
const WALL := 1.7
const ROUTE_CELL := 40.0       # grid of the route points
const OVERHEAD := 2.6          # a shape whose underside is this far over the route is a ceiling (no sun shadow)
const SHORT_WALL := 4.0        # brand.walls "accent": wall pieces this long or shorter across the floor are painted (pillars, door frames)
const END_WALL_HEIGHTS: Array[float] = [1.5, 3.0, 5.0, 7.0] # brand.walls "accent": heights the end walls are looked for at
const LAYER_HIT := 8
const PAD_RADIUS := 2.7
const PAD_BORDER := 0.18
const START_COLOR := Color("#2fae5c")
const GOAL_COLOR := Color("#f2c230")
const SIGN_INK := Color("#1d2026")
## The START and GOAL words (and the logo over GOAL) are only drawn from this far from the camera on (fading in over SIGN_FADE more metres).
const SIGN_NEAR := 9.0
const SIGN_FADE := 3.0
const GOAL_LOGO_SIZE := SlotFrames.GOAL_CARD_SIZE ## the team logo over the GOAL word (m)
const GOAL_WORD_HALF := 0.3     ## half the height of the GOAL word (64 px at 8 mm, and its outline)

class Cache extends RefCounted:
	var triangles: Dictionary = {}      # Shape3D instance id -> local triangle corners
	var route_cells: Dictionary = {}     # Vector2i grid cell -> PackedVector3Array of route points

## Where the spinners of `level_root` that style/race_hazard_looks.gd dresses stand (level coordinates, x z): a spin hazard whose parts are all plain boxes.
static func _spin_hubs(level_root: Node3D, to_level: Transform3D) -> Array:
	var spots: Array = []
	for body: Node in level_root.get_children():
		if not (body is AnimatableBody3D and str(body.name).begins_with("Hazard_spin_")): continue
		var boxes_only := true
		for child: Node in body.get_children():
			var part := child as CollisionShape3D
			if part != null and (not part.shape is BoxShape3D or part.has_meta("slot") or part.has_meta("tone")): boxes_only = false
		if boxes_only:
			var at := to_level * (body as Node3D).global_transform.origin
			spots.append(Vector2(at.x, at.z))
	return spots

static func _at_spot(spots: Array, at: Vector3) -> bool:
	for spot: Vector2 in spots:
		if spot.distance_to(Vector2(at.x, at.z)) < 0.05: return true
	return false

## Draws one level of the level world (every collision shape under `level_root`, which must be in the tree). `route` = the level's path in world
## coordinates. Bodies with the meta "hazard" (movers, launch volumes) are drawn as movers; a shape with the meta "ice" in the ice surface.
## Bodies with the meta "fx" draw themselves.
static func draw_level(level_root: Node3D, route: PackedVector3Array, slicer = null) -> int:
	var cache := Cache.new()
	_index_route(cache, route)
	var jobs: Array = [] # {shape_node, hazard}
	for body: CollisionObject3D in level_root.find_children("*", "CollisionObject3D", true, false):
		if body.get_meta("fx", false): continue
		var hazard := bool(body.get_meta("hazard", false))
		for child: Node in body.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null or shape_node.disabled: continue
			jobs.append({"shape_node": shape_node, "hazard": hazard})
	var lifts := _lifts(jobs, cache)
	var statics := BlockMesh.Batch.new()
	var overhead := BlockMesh.Batch.new()  # ceilings and beams over the route: they let the light through (skylights)
	var movers := {}  # body -> Batch
	var tops: Array = []
	var to_level := level_root.global_transform.affine_inverse()
	var drawn := 0
	var block_index := 0
	var walls := _paint_mode()
	var ends := _end_walls(cache, route, jobs) if walls == "accent" else {}
	var daylight := RaceSurfaces.wanted(level_root) # a `world: daylight` level (levels/level_world.gd marks it)
	var kit_level := daylight or bool(level_root.get_meta("stage_round", false)) # the kit and the daylight palette also dress the static blocks of a stage round (levels/level_world.gd marks it)
	var solids: Variant = BlockKit.index(jobs, to_level, func(shape_node: CollisionShape3D) -> int: return _role(cache, shape_node)) if kit_level else null # what stands under what and where platforms join (a joint keeps its edge square)
	var hub_spots := _spin_hubs(level_root, to_level) if daylight else []
	for job: Dictionary in jobs:
		if slicer != null and slicer.due(): await slicer.next()
		var shape_node: CollisionShape3D = job.shape_node
		if job.hazard:
			var body := shape_node.get_parent() as Node3D
			if not movers.has(body): movers[body] = BlockMesh.Batch.new()
			var hazard_keys := _hazard_keys(body, shape_node)
			var gate := str(shape_node.get_meta("slot", "")) == Hazards.GATE_SLOT # the start gate is a chevron door in every look
			var door_look := (daylight or gate) and RaceSurfaces.is_door(body, shape_node)
			if door_look: hazard_keys = RaceSurfaces.keys("door", 1) # a cycling door of a `world: daylight` level: a navy slab with chevrons
			elif daylight and shape_node.has_meta("tone"): hazard_keys = RaceSurfaces.keys(str(shape_node.get_meta("tone")), 1) # a part of a sliding / sinking wall or door that names its surface
			if (daylight or door_look) and shape_node.shape is BoxShape3D and (RaceSurfaces.is_door(body, shape_node) or str(shape_node.get_meta("tone", "")) == "door"):
				var slab := shape_node.transform
				slab.origin -= slab.basis.y.normalized() * (DOOR_FOOT * 0.5)
				var slab_size := (shape_node.shape as BoxShape3D).size + Vector3(0.0, DOOR_FOOT, 0.0)
				var door_round := RaceSurfaces.radius(hazard_keys[1])
				if gate and slab_size.y > RaceSurfaces.GATE_SHOWN: # the start gate is drawn as a low cushion barrier (the collision stays the full door): the course behind it stays in view
					slab.origin -= slab.basis.y.normalized() * ((slab_size.y - RaceSurfaces.GATE_SHOWN) * 0.5)
					slab_size.y = RaceSurfaces.GATE_SHOWN
					door_round = RaceSurfaces.GATE_ROUND
				var sections := clampi(roundi(maxf(slab_size.x, slab_size.z) / RaceSurfaces.GATE_SECTION), 1, 8) if gate else 1 # the barrier is a row of cushions: the rounded ends of neighbours pinch like an inflatable's seams
				var along := 0 if slab_size.x >= slab_size.z else 2
				var piece := slab_size
				piece[along] = slab_size[along] / float(sections)
				for index in sections:
					var offset := Vector3.ZERO
					offset[along] = -slab_size[along] * 0.5 + piece[along] * (float(index) + 0.5)
					movers[body].box(Transform3D(slab.basis, slab * offset), piece, door_round, 3 if gate else 1, hazard_keys[0], hazard_keys[1], Color.WHITE, 0.0, true, hazard_keys[2], 0.95 if gate else 0.45)
				drawn += 1
			elif _add_shape(movers[body], shape_node, shape_node.transform, hazard_keys, GATE_LIFT if str(shape_node.get_meta("slot", "")) == "gate" else 0.0, Color.WHITE): drawn += 1   # the start gate stands GATE_LIFT over the floor
		else:
			var role := _role(cache, shape_node)
			if not hub_spots.is_empty() and str(shape_node.get_meta("tone", "")) == "hub" and _at_spot(hub_spots, to_level * shape_node.global_transform.origin): continue # the spinner's own look (style/spinner_look.gd) draws the hub drum: the block's drawing would run through its bars
			if daylight and str(shape_node.get_meta("tone", "")) == "arch":   # the collision of a gate frame: style/gate_look.gd draws the one frame
				if not _overhead(cache, shape_node): _collect_tops(cache, shape_node, tops)
				continue
			var keys := _static_keys(role)
			var above := _overhead(cache, shape_node)
			if role == 1 and not above and (walls == "full" or (walls == "accent" and (ends.has(shape_node.get_instance_id()) or _short(shape_node)))):
				keys = ["wall_brand", "wall_brand"] # the team's paint: walls, never ceilings
			if shape_node.has_meta("belt") and shape_node.shape is BoxShape3D: keys = [BlockMesh.belt_key(shape_node.get_meta("belt")), "base"] # a conveyor lane (BlockMesh.Batch.belt)
			if kit_level and role != 3: # a level with `world: daylight`: teal floors and navy walls, or the block's own `tone` (style/race_surfaces.gd)
				var lane: Variant = keys[0] if shape_node.has_meta("belt") and shape_node.shape is BoxShape3D else null
				keys = RaceSurfaces.keys(str(shape_node.get_meta("tone", "")), role)
				if lane != null: keys[0] = lane
			var color := Color.WHITE
			if role == 2:
				color = Surfaces.block_color(block_index)
				block_index += 1
			var target := overhead if above else statics
			var at_level := to_level * shape_node.global_transform
			if kit_level and not above and not shape_node.has_meta("belt") and role != 3 and BlockKit.dress(target, shape_node, at_level, str(shape_node.get_meta("tone", "")), role, lifts.get(shape_node.get_instance_id(), 0.0), solids): drawn += 1 # BlockKit.dress hands tall columns to style/pillar_kit.gd
			elif kit_level and above and str(shape_node.get_meta("tone", "")) == "frame" and shape_node.shape is BoxShape3D and at_level.basis.y.normalized().y > 0.999: # a beam over the route: an inflated tube (the kit's frame look), no collision change
				var beam := at_level
				beam.origin.y += lifts.get(shape_node.get_instance_id(), 0.0)
				BlockKit.plain_block(target, beam, (shape_node.shape as BoxShape3D).size, "frame", role)
				drawn += 1
			elif _add_shape(target, shape_node, at_level, keys, lifts.get(shape_node.get_instance_id(), 0.0), color): drawn += 1
			if not above: _collect_tops(cache, shape_node, tops) # a ceiling does not shade the floor under it
	var field := HeightField.build(tops)
	var materials := {}
	for batch: BlockMesh.Batch in [statics, overhead]:
		for key: String in batch.groups:
			if materials.has(key): continue
			materials[key] = _level_material(key, field)
	_add_level_mesh(level_root, "LevelLook", statics.commit(materials), true)
	_add_level_mesh(level_root, "LevelCeilings", overhead.commit(materials), false)
	var shared := {}
	for body: Node3D in movers:
		var batch: BlockMesh.Batch = movers[body]
		for key: String in batch.groups:
			if not shared.has(key): shared[key] = RaceSurfaces.material(key) if RaceSurfaces.is_key(key) else (_trim_material() if key == "trim" else Surfaces.material(key))
		var moving := batch.commit(shared)
		if moving == null: continue
		var visual := MeshInstance3D.new()
		visual.name = "CollisionLook"
		visual.mesh = moving
		body.add_child(visual)
	return drawn

static func _add_level_mesh(level_root: Node3D, label: String, mesh: Mesh, shadows: bool) -> void:
	if mesh == null: return
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	if not shadows: visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level_root.add_child(visual)

## A static shape whose underside is OVERHEAD metres or more above the route beside it (a ceiling, a beam over the path): it casts no
## sun shadow, so a roofed room reads as lit through skylights, and stays out of the height field.
static func _overhead(cache: Cache, shape_node: CollisionShape3D) -> bool:
	var corners := _corners(shape_node.shape, cache)
	if corners.is_empty(): return false
	var xf := shape_node.global_transform
	var low := INF
	var foot_low := Vector2(INF, INF)
	var foot_high := Vector2(-INF, -INF)
	for corner in corners:
		var w := xf * corner
		low = minf(low, w.y)
		foot_low = Vector2(minf(foot_low.x, w.x), minf(foot_low.y, w.z))
		foot_high = Vector2(maxf(foot_high.x, w.x), maxf(foot_high.y, w.z))
	var walked := _route_height(cache, foot_low, foot_high)
	return not is_nan(walked) and low - walked >= OVERHEAD

## Shapes of bodies outside a course (the lobby yard, lobby_visuals.gd), drawn like a level's: the same surfaces, a shape's role by its own
## height (no route to compare with): 1.7 m and more a wall, 0.7 to 1.7 a hop block, lower ground. `hazard`: as a mover (a hazard added
## to a level after its build). `painted`: names of the bodies brand.walls "accent" paints (the yard's back wall). Each shape gets its
## own mesh as a child.
static func draw_shapes(shapes: Array, hazard := false, painted: Array = []) -> int:
	var cache := Cache.new()
	var materials := {}
	var drawn := 0
	var tops: Array = []
	if not hazard:
		for shape_node: CollisionShape3D in shapes: _collect_tops(cache, shape_node, tops)
	var field := HeightField.build(tops) # contact shadows and the team's band along the yard walls
	var walls := _paint_mode()
	for shape_node: CollisionShape3D in shapes:
		var batch := BlockMesh.Batch.new()
		var role := _role(cache, shape_node)
		var keys := _hazard_keys(shape_node.get_parent(), shape_node) if hazard else _static_keys(role)
		if not hazard and role == 1 and (walls == "full" or (walls == "accent" and str(shape_node.get_parent().name) in painted)):
			keys = ["wall_brand", "wall_brand"]
		if not _add_shape(batch, shape_node, Transform3D.IDENTITY, keys, 0.0, Surfaces.block_color(drawn)): continue
		for key: String in batch.groups:
			if not materials.has(key): materials[key] = _level_material(key, field)
		var visual := MeshInstance3D.new()
		visual.name = "CollisionLook"
		visual.mesh = batch.commit(materials)
		shape_node.add_child(visual)
		drawn += 1
	return drawn

## A level surface's material with the level's height field: the walls get the team's stripe, the painted walls the team's paint.
static func _level_material(key: String, field: RefCounted) -> ShaderMaterial:
	if key.begins_with(BlockMesh.BELT_PREFIX): return _belt_material(key)
	if RaceSurfaces.is_key(key): return RaceSurfaces.material(key)
	if BlockKit.is_key(key): return BlockKit.material_of(key)
	var material := Surfaces.material(key)
	field.apply(material)
	if key == "trim" and TeamCast.brand_accent().a > 0.0: material.set_shader_parameter("tint", TeamCast.brand_accent())
	if Party.on(): return material # the party look paints the brand colours into every surface itself (style/party_look.gd)
	if key == "wall": _brand_band(material)
	if key == "wall_brand": material.set_shader_parameter("tint", TeamCast.brand_paint())
	return material

## The material of a conveyor lane's deck (style/belt_look.gdshader) for the belt key `key` (BlockMesh.belt_key): its speed scrolls the chevrons; the direction
## is laid into the mesh's UVs.
static func _belt_material(key: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BELT_SHADER
	material.set_shader_parameter("speed", BlockMesh.belt_velocity(key).length())
	material.set_shader_parameter("flow", BlockMesh.belt_velocity(key).normalized()) # the raised chevrons slide along it (style/belt_look.gdshader)
	return material

## How much the team's colour paints (TeamCast.brand_walls()); "stripe" when the cast has no colour to paint.
static func _paint_mode() -> String:
	return TeamCast.brand_walls() if TeamCast.brand_paint().a > 0.0 else "stripe"

## A pillar, a door frame or a short piece of wall: an upright cylinder, or a box whose longer side across the floor is SHORT_WALL or less.
static func _short(shape_node: CollisionShape3D) -> bool:
	var shape := shape_node.shape
	if shape is CylinderShape3D: return true
	if not shape is BoxShape3D: return false
	var size: Vector3 = (shape as BoxShape3D).size
	var basis := shape_node.global_transform.basis
	var across := maxf(Vector2(basis.x.x, basis.x.z).length() * size.x, Vector2(basis.z.x, basis.z.z).length() * size.z)
	return across <= SHORT_WALL

## The end walls of a level: the nearest wall straight ahead of the start and the nearest one behind it (along the route's first stretch,
## at a few heights, ceilings left out). Shape instance ids.
static func _end_walls(cache: Cache, route: PackedVector3Array, jobs: Array) -> Dictionary:
	var ends := {}
	if route.size() < 2: return ends
	var start := route[0]
	var ahead := Vector3.ZERO
	for point in route:
		var step := Vector3(point.x - start.x, 0.0, point.z - start.z)
		if step.length() > 2.0:
			ahead = step.normalized()
			break
	if ahead == Vector3.ZERO: return ends
	var walls: Array = []
	for job: Dictionary in jobs:
		var shape_node: CollisionShape3D = job.shape_node
		if not job.hazard and shape_node.shape is BoxShape3D and _role(cache, shape_node) == 1 and not _overhead(cache, shape_node): walls.append(shape_node)
	for direction: Vector3 in [ahead, -ahead]:
		var best := INF
		var hit := 0
		for height: float in END_WALL_HEIGHTS:
			var from := start + Vector3.UP * height
			for shape_node: CollisionShape3D in walls:
				var distance := _ray_box(shape_node.global_transform, (shape_node.shape as BoxShape3D).size * 0.5, from, direction)
				if distance < best:
					best = distance
					hit = shape_node.get_instance_id()
		if hit != 0: ends[hit] = true
	return ends

## Distance along `direction` (unit) from `from` to a box (half size `half`, placed by `xf`), INF when the ray misses it.
static func _ray_box(xf: Transform3D, half: Vector3, from: Vector3, direction: Vector3) -> float:
	var inverse := xf.affine_inverse()
	var origin := inverse * from
	var along := inverse.basis * direction
	var near := -INF
	var far := INF
	for axis in 3:
		if absf(along[axis]) < 1e-6:
			if absf(origin[axis]) > half[axis]: return INF
			continue
		var t1 := (-half[axis] - origin[axis]) / along[axis]
		var t2 := (half[axis] - origin[axis]) / along[axis]
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
	return near if near <= far and far >= 0.0 and near >= 0.0 else INF

## The team's brand colour painted along the walls at the look's band height over the floor (nothing without a brand colour).
static func _brand_band(material: ShaderMaterial) -> void:
	var accent := TeamCast.brand_accent()
	if accent.a <= 0.0: return
	var band: Array = Surfaces.spec().band
	material.set_shader_parameter("band_color", accent)
	material.set_shader_parameter("band", Vector2(float(band[0]), float(band[1])))

## No ink pass in this look: real surfaces carry their own edges (the call does nothing).
static func edges(_world: Node3D) -> void:
	pass

## [top key, side key] of a static shape by role (0 ground, 1 wall, 2 hop block, 3 ice).
static func _static_keys(role: int) -> Array:
	match role:
		1: return ["wall", "wall"]
		2: return ["block", "block"]
		3: return ["ice", "base"]
	return ["floor", "base"]

## [top key, side key] of a moving body: spike posts in steel, bodies that break the painting in danger, platforms in mover. A box that wears
## the cast's picture (an obstacle slot with a cast sign, the start gate) has square edges in the team's trim, so the picture ends in a clean
## border instead of the hazard's red showing at its corners.
static func _hazard_keys(body: Node, shape_node: CollisionShape3D = null) -> Array:
	if body != null and str(body.name).begins_with("Hazard_spikes"): return ["steel", "steel"]
	if shape_node != null and _worn(shape_node): return ["trim", "trim"]
	var hurts := body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & LAYER_HIT) != 0
	return ["danger", "danger"] if hurts or body is Area3D else ["mover_top", "mover"]

## True when the cast puts a face on this box shape (SlotFrames.box_faces: an obstacle slot the cast has a sign for, or the start gate).
static func _worn(shape_node: CollisionShape3D) -> bool:
	if not shape_node.shape is BoxShape3D: return false
	var slot := str(shape_node.get_meta("slot", ""))
	if slot == "gate": return true
	return slot.begins_with("obstacle_") and not TeamCast.obstacle(int(slot.trim_prefix("obstacle_"))).is_empty()

## The trim around a cast picture: the brand accent, plain light grey without one.
static func _trim_material() -> ShaderMaterial:
	var material := Surfaces.material("trim")
	var accent := TeamCast.brand_accent()
	if accent.a > 0.0: material.set_shader_parameter("tint", accent)
	return material

## One collision shape into `batch` (placed by `xf` in the batch's space). Returns false for shapes it cannot draw.
static func _add_shape(batch: BlockMesh.Batch, shape_node: CollisionShape3D, xf: Transform3D, keys: Array, lift: float, color: Color) -> bool:
	var shape := shape_node.shape
	var top: String = keys[0]
	var side: String = keys[1]
	var raced := RaceSurfaces.is_key(side)
	var edge := RaceSurfaces.radius(side) if raced else Surfaces.radius(side)
	var steps := 1 if raced else Surfaces.segments(side)
	var lifted := xf
	lifted.origin.y += lift
	if shape is BoxShape3D and top.begins_with(BlockMesh.BELT_PREFIX):
		batch.belt(xf, (shape as BoxShape3D).size, edge, steps, side, top, BlockMesh.belt_velocity(top), lift)
	elif shape is BoxShape3D:
		batch.box(xf, (shape as BoxShape3D).size, edge, steps, top, side, color, lift, raced, str(keys[2]) if raced and keys.size() > 2 else "")
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		batch.lathe(lifted, cylinder.radius, cylinder.height, edge * 2.0, side, top, color, raced and RaceSurfaces.unit_caps(top))
	elif shape is SphereShape3D:
		batch.lathe(lifted, (shape as SphereShape3D).radius, 0.0, 0.0, side, top, color)
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		batch.lathe(lifted, capsule.radius, capsule.height, capsule.radius, side, top, color)
	elif shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
		var corners := _corners(shape, Cache.new())
		if corners.size() < 3: return false
		batch.triangles(xf, corners, shape is ConcavePolygonShape3D, top, side, color, lift)
	else:
		return false
	return true

## The upward faces of a static shape, in world space, for the height field.
static func _collect_tops(cache: Cache, shape_node: CollisionShape3D, tops: Array) -> void:
	var corners := _corners(shape_node.shape, cache)
	var xf := shape_node.global_transform
	for i in range(0, corners.size() - 2, 3):
		var a := xf * corners[i]
		var b := xf * corners[i + 1]
		var c := xf * corners[i + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-12: continue
		if absf(normal.normalized().y) >= TOP_Y: tops.append([a, b, c])

## Tops that stand at the same height would z-fight (flicker in stripes) where two shapes overlap. The drawn mesh of every polygon shape is
## raised by a few millimetres: among the static shapes with the same top height the biggest footprint stays lowest; every mover body gets its
## own lift on top of a constant 1.5 cm (a platform at rest is level with the ground beside it, and two movers can overlap). Collision is
## untouched; the largest lift is below 4 cm.
static func _lifts(jobs: Array, cache: Cache) -> Dictionary:
	var groups: Dictionary = {} # quantised top height -> Array of [footprint area, job index]
	var result: Dictionary = {}
	var bodies: Dictionary = {} # hazard body instance id -> ordinal
	for index in jobs.size():
		var job: Dictionary = jobs[index]
		var shape_node: CollisionShape3D = job.shape_node
		var shape := shape_node.shape
		if shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D: continue
		if job.hazard:
			var body_id := shape_node.get_parent().get_instance_id()
			if not bodies.has(body_id): bodies[body_id] = bodies.size()
			result[shape_node.get_instance_id()] = HAZARD_LIFT + LIFT_STEP * float(int(bodies[body_id]) % LIFT_CLASSES)
			continue
		var xf := shape_node.global_transform
		var high := -INF
		var low := Vector2(INF, INF)
		var top := Vector2(-INF, -INF)
		for corner in _corners(shape, cache):
			var w := xf * corner
			high = maxf(high, w.y)
			low = Vector2(minf(low.x, w.x), minf(low.y, w.z))
			top = Vector2(maxf(top.x, w.x), maxf(top.y, w.z))
		var key := roundi(high * 100.0)
		if not groups.has(key): groups[key] = []
		(groups[key] as Array).append([(top.x - low.x) * (top.y - low.y), index])
	for key: int in groups:
		var members: Array = groups[key]
		members.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
		for rank in members.size():
			var shape_node: CollisionShape3D = jobs[members[rank][1]].shape_node
			result[shape_node.get_instance_id()] = LIFT_STEP * float(rank % LIFT_CLASSES)
	return result

## The route of a level (world points, about 2 m apart) in a coarse grid: a shape's top above the route beside it says wall, hop block or ground.
static func _index_route(cache: Cache, route: PackedVector3Array) -> void:
	for p: Vector3 in route:
		var cell := Vector2i(floori(p.x / ROUTE_CELL), floori(p.z / ROUTE_CELL))
		var points: PackedVector3Array = cache.route_cells.get(cell, PackedVector3Array())
		points.append(p)
		cache.route_cells[cell] = points

## Distance on the ground plane from a route point to a shape's footprint (x/z box), 0 inside it.
static func _box_distance(low: Vector2, high: Vector2, p: Vector3) -> float:
	return Vector2(maxf(maxf(low.x - p.x, 0.0), p.x - high.x), maxf(maxf(low.y - p.z, 0.0), p.z - high.y)).length()

## Height of the route beside a shape's footprint: the highest point of the route among those nearest to the box (a shape the route
## runs through or along). NAN when no route point is within 20 m (a shape out in the background).
static func _route_height(cache: Cache, low: Vector2, high: Vector2) -> float:
	if cache.route_cells.is_empty(): return NAN
	var distances := PackedFloat32Array()
	var heights := PackedFloat32Array()
	for cx in range(floori((low.x - 20.0) / ROUTE_CELL), floori((high.x + 20.0) / ROUTE_CELL) + 1):
		for cz in range(floori((low.y - 20.0) / ROUTE_CELL), floori((high.y + 20.0) / ROUTE_CELL) + 1):
			var points: Variant = cache.route_cells.get(Vector2i(cx, cz))
			if points == null: continue
			for p: Vector3 in points:
				distances.append(_box_distance(low, high, p))
				heights.append(p.y)
	if distances.is_empty(): return NAN
	var nearest := 20.0
	for d in distances: nearest = minf(nearest, d)
	if nearest >= 20.0: return NAN
	var top := -INF
	for i in distances.size():
		if distances[i] <= nearest + 1.5: top = maxf(top, heights[i])
	return top

## Role of a static shape (0 ground, 1 wall, 2 hop block, 3 ice) by how far its top stands above the path beside it: walls (>= WALL),
## hop blocks (>= SLAB), else ground. Without a path nearby, by its own height. Ice (meta "ice") is role 3.
static func _role(cache: Cache, shape_node: CollisionShape3D) -> int:
	if shape_node.has_meta("ice"): return 3
	if shape_node.has_meta("belt"): return 0 # a conveyor lane is floor wherever it stands
	var xf := shape_node.global_transform
	var low := INF
	var high := -INF
	var foot_low := Vector2(INF, INF)
	var foot_high := Vector2(-INF, -INF)
	var shape := shape_node.shape
	if shape is CylinderShape3D or shape is SphereShape3D or shape is CapsuleShape3D:
		var radius := 0.5
		var height := 1.0
		if shape is CylinderShape3D:
			radius = (shape as CylinderShape3D).radius
			height = (shape as CylinderShape3D).height
		elif shape is SphereShape3D:
			radius = (shape as SphereShape3D).radius
			height = radius * 2.0
		else:
			radius = (shape as CapsuleShape3D).radius
			height = (shape as CapsuleShape3D).height
		var centre := xf.origin
		low = centre.y - height * 0.5
		high = centre.y + height * 0.5
		foot_low = Vector2(centre.x - radius, centre.z - radius)
		foot_high = Vector2(centre.x + radius, centre.z + radius)
	else:
		for corner in _corners(shape, cache):
			var w := xf * corner
			low = minf(low, w.y)
			high = maxf(high, w.y)
			foot_low = Vector2(minf(foot_low.x, w.x), minf(foot_low.y, w.z))
			foot_high = Vector2(maxf(foot_high.x, w.x), maxf(foot_high.y, w.z))
	if low == INF: return 0
	var walked := _route_height(cache, foot_low, foot_high)
	var above := high - (low if is_nan(walked) else walked)
	return 1 if above >= WALL else (2 if above >= SLAB else 0)

## The faces of a polygon shape (its own debug mesh: the exact hull / box / trimesh faces) as local triangle corners.
static func _corners(shape: Shape3D, cache: Cache) -> PackedVector3Array:
	var id := shape.get_instance_id()
	if cache.triangles.has(id): return cache.triangles[id]
	var corners := PackedVector3Array()
	var debug := shape.get_debug_mesh()
	for surface in debug.get_surface_count():
		if debug.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := debug.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
			for i: int in index_data: corners.append(points[i])
		else:
			corners = points
		break
	cache.triangles[id] = corners
	return corners

## The plane under a level: the level world hides it while the room is shown.
static func void_plane(parent: Node3D) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	var floor_plane := MeshInstance3D.new()
	floor_plane.name = "CollisionLookVoid"
	floor_plane.mesh = plane
	floor_plane.material_override = Surfaces.paint(Color("#3b4048"), 0.9)
	floor_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_plane.position = Vector3(0.0, WATER_Y, 0.0)
	parent.add_child(floor_plane)
	return floor_plane

## START and GOAL of a level: a painted pad on the floor, and over the GOAL pad a word (no flag poles: no checkpoint is a visible object; the START gate says START). The team logo hangs over the GOAL word. All nodes are children of `level_root` (world positions given),
## so hiding the root hides them. `arch_under`: the height of the underside of the arch over the goal over the goal floor (SlotFrames.goal_arch_under,
## INF for none): the GOAL word and the card keep under it, and the card is dropped when the arch wears the same logo (SlotFrames.goal_marks). `goal_word` false: the level's
## GOAL sign (style/goal_sign.gd) says GOAL, so no word and no logo card hang over the pad (the pad stays).
static func mark_level(level_root: Node3D, start: Vector3, goal_floor: Vector3, _lateral: Vector3, goal := true, arch_under := INF, goal_word := true) -> void:
	var marks := SlotFrames.goal_marks(GOAL_WORD_HALF, arch_under) # where the GOAL word and its card hang, clear of the arch over the goal
	var spots: Array = [["START", start]]
	if goal: spots.append(["GOAL", goal_floor])
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		var accent := START_COLOR if spot[0] == "START" else GOAL_COLOR
		var pad := _pad(accent)
		level_root.add_child(pad)
		pad.global_position = at + Vector3(0.0, 0.012, 0.0)
		if spot[0] == "START": continue # the START gate says START (style/start_gate.gd): the pad is the mark on the floor, no word floats over it
		var label := Label3D.new()
		label.text = str(spot[0])
		label.font = _sign_font()
		label.font_size = 64
		label.pixel_size = 0.008
		label.outline_size = 10
		label.modulate = Color.WHITE
		label.outline_modulate = SIGN_INK
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		# Seen from close by (the carriers on the pad, a courier walking past, a lift arriving) the billboard grows past the screen edge
		# or sits behind the HUD lettering: it fades out inside SIGN_NEAR metres.
		label.visibility_range_begin = SIGN_NEAR
		label.visibility_range_begin_margin = SIGN_FADE
		label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if spot[0] == "GOAL" and not goal_word: continue # the pad is down; the sign over the deck is the word
		if spot[0] == "GOAL" and float(marks.card) >= 0.0: _goal_logo(level_root, at + Vector3(0.0, float(marks.card), 0.0))
		level_root.add_child(label)
		label.global_position = at + Vector3(0.0, float(marks.word) if spot[0] == "GOAL" else SlotFrames.GOAL_WORD_Y, 0.0)

static var _font: FontVariation

## The sign face: Archivo, extra bold.
static func _sign_font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = SIGN_FONT
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _font

## The goal sign's picture (goal_sign.png, else the team logo) on a card over the GOAL word (nothing without either); fades out
## close by like the word.
static func _goal_logo(level_root: Node3D, at: Vector3) -> void:
	var card := SlotFrames.card(TeamCast.goal_sign())
	if card == null: return
	var sign := Sprite3D.new()
	sign.name = "GoalLogo"
	sign.texture = card
	sign.pixel_size = GOAL_LOGO_SIZE / float(card.get_width())
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.shaded = false
	sign.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.visibility_range_begin = SIGN_NEAR
	sign.visibility_range_begin_margin = SIGN_FADE
	sign.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	level_root.add_child(sign)
	sign.global_position = at

## The painted pad under a checkpoint: a white ring around a disc in the pad's colour, both a few millimetres proud of the floor.
static func _pad(color: Color) -> Node3D:
	var holder := Node3D.new()
	holder.name = "CollisionLookPad"
	for ring: Array in [[PAD_RADIUS, Color("#f4f4f2"), 0.0], [PAD_RADIUS - PAD_BORDER, color, 0.003]]:
		var disc := CylinderMesh.new()
		disc.top_radius = ring[0]
		disc.bottom_radius = ring[0]
		disc.height = 0.01
		disc.radial_segments = 64
		disc.rings = 1
		var part := MeshInstance3D.new()
		part.mesh = disc
		part.material_override = Surfaces.paint(ring[1], 0.55)
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.position.y = ring[2]
		holder.add_child(part)
	return holder
