extends RefCounted
## The comic ink collision look (dev runs only; style/collision_look.gd hands calls here): what you see is what you collide with.
## A client-only pass after a level is built (draw_level). Every collision shape of every static or moving body is drawn, in flat toon
## colours that tell the parts of a level apart (collision_surface.gdshader):
##  * ground and low slabs: cream tops, warm tan sides, a darker ochre band along the free border of every top (so a drop-off reads);
##  * walls and tall blocks you bump into: teal with light hatching; hop blocks: teal sides, cream top with the ochre band; ice: pale blue;
##  * everything far from the level's path fades into a dark, cool, low-contrast slate;
##  * moving hazards and the volumes that launch a courier (bumpers, push pads) from their own shapes in red/orange warning stripes. The meshes are
##    children of the shape nodes, so they move exactly as the bodies do;
##  * one dark plane for the void/water, a green START pad and a gold GOAL pad with their signs on the checkpoint rings;
##  * the team cast (style/team_cast.gd) tints the walls with its brand hue, colours the GOAL flag and puts its logo over the GOAL word;
##  * ONE full-screen ink pass (collision_edges.gdshader) draws a line on every silhouette and crease of everything, so no shape needs lines of its own.
## Nothing here touches collision, hazards or the network; the authority never runs it.
const Ink := preload("res://style/style_ink.gd")
const Style := preload("res://style/friends_style.gd")
const TeamCast := preload("res://style/team_cast.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const WATER_Y := -8.0
const LIFT_STEP := 0.003       # visual lift between shapes whose tops stand at the same height
const LIFT_CLASSES := 9
const HAZARD_LIFT := 0.015
const FLAT_Y := 0.995           # a face this level is a flat top (the cover test)
const COVER_HEIGHT := 0.06      # a top within this height of another's counts as the same plane
const COVER_REACH := 0.12       # how far outside an edge the cover test looks (hairline gaps between boxes count as seams)
const COVER_CELL := 4.0
const SEAM_GROW := 0.08         # drawn ground boxes grow by up to this on each side (see _poly)
const COVER_SAMPLES: Array[float] = [0.1, 0.3, 0.5, 0.7, 0.9]   # along an edge; all but one must stand on another top
const TOP_Y := 0.65            # a face whose normal points this far up is walkable (a top)
const BIG := 1000.0            # "no border here" distance of a vertex
const SLAB := 0.7              # shapes whose top is lower than this (metres) above the route beside them are ground; up to WALL hop blocks, above walls
const WALL := 1.7
const ROUTE_CELL := 40.0       # grid of the route points
const NEAR_ROUTE := 12.0       # metres from the route up to which a vertex is in the foreground
const FAR_ROUTE := 32.0        # ... and from which it is background
const FLOOR_TOP := Color("#fff6db")
const GROUND_SIDE: Array[Color] = [Color("#d3bc8a"), Color("#bca172"), Color("#9b8359")]
const RIM := Color("#b57a45")
const WALL_TOP := Color("#9ccdd0")
const WALL_SIDE: Array[Color] = [Color("#5b9ea9"), Color("#477f8e"), Color("#33616f")]
const HATCH := Color("#b4dde0")
const SLATE := Color("#5b5a82")
const PAD_RADIUS := 2.7
const START_COLOR := Color("#22b25f")
const GOAL_COLOR := Color("#ffc21a")
## The GOAL word is only drawn from this far from the camera on (fading in over GOAL_SIGN_FADE more metres).
const GOAL_SIGN_NEAR := 6.0
const GOAL_SIGN_FADE := 3.0
const GOAL_LOGO_SIZE := SlotFrames.GOAL_CARD_SIZE ## the team logo over the GOAL word (m)
const GOAL_WORD_HALF := 0.55    ## half the height of the GOAL word (118 px at 8 mm, and its outline)

static var _surface_shader: Shader
static var _edge_shader: Shader
static var _pad_shader: Shader

class Cache extends RefCounted:
	var poly: Dictionary = {}    # Shape3D instance id (concave) or id * 4 + background bucket (convex) -> {fill: ArrayMesh}
	var round_meshes: Dictionary = {}   # Shape3D instance id -> Mesh
	var triangles: Dictionary = {}      # Shape3D instance id -> local triangle corners
	var terrain_tops: Dictionary = {}    # world-space edge key -> how many upward faces meet there
	var flat_tops: Array = []            # horizontal top triangles of the static shapes: [a, b, c (world), corner ids a, b, c]
	var terrain_ids: Dictionary = {}     # quantised world position -> id
	var route_cells: Dictionary = {}     # Vector2i grid cell -> PackedVector2Array of route points
	var background: Dictionary = {}      # quantised world position -> background factor
	var materials: Dictionary = {}
	var shared_edges := false            # static convex shapes count their edges level-wide too (a level's ground boxes)

static func _colors(material: ShaderMaterial, prefix: String, list: Array[Color]) -> void:
	for i in list.size(): material.set_shader_parameter("%s_%d" % [prefix, i], list[i])

## One material per (hazard, round shape, role, background bucket); meshes of polygon shapes carry role and background per vertex.
static func _material(cache: Cache, hazard: bool, round_shape: bool, background := 0.0, role := 1) -> Material:
	var bucket := roundi(background * 3.0)
	var key := "%s%s%d%d" % [hazard, round_shape, bucket if round_shape else 0, role if round_shape else 0]
	if cache.materials.has(key): return cache.materials[key]
	if _surface_shader == null: _surface_shader = preload("res://style/collision_surface.gdshader")
	var material := ShaderMaterial.new()
	material.shader = _surface_shader
	material.set_shader_parameter("floor_top", FLOOR_TOP)
	_colors(material, "ground_side", GROUND_SIDE)
	material.set_shader_parameter("rim_color", RIM)
	material.set_shader_parameter("wall_top", _branded(WALL_TOP))
	var sides: Array[Color] = []
	for color in WALL_SIDE: sides.append(_branded(color))
	_colors(material, "wall_side", sides)
	material.set_shader_parameter("hatch_color", _branded(HATCH))
	material.set_shader_parameter("background_tone", SLATE)
	material.set_shader_parameter("stripe_a", Ink.TOMATO)
	material.set_shader_parameter("stripe_b", Color("#ffa51f"))
	material.set_shader_parameter("hazard", hazard)
	material.set_shader_parameter("vertex_data", not round_shape)
	material.set_shader_parameter("role_uniform", float(role))
	material.set_shader_parameter("background_uniform", float(bucket) / 3.0)
	if round_shape: Style.outlined(material, Ink.INK, 0.045, false, true)
	cache.materials[key] = material
	return material

## A wall colour in the team's brand hue (TeamCast.wall_hue()): only the hue changes, so walls keep their contrast with the cream
## ground and stay apart from the hazard stripes; the template's teal when the cast has no brand colour for walls.
static func _branded(color: Color) -> Color:
	var hue := TeamCast.wall_hue()
	return color if hue < 0.0 else Color.from_hsv(hue, color.s, color.v)

## Draws one level of the level world (every collision shape under `level_root`, which must be in the tree). `route` = the level's path in world
## coordinates. Bodies with the meta "hazard" (movers, launch volumes) are drawn as hazards; a shape with the meta "ice" in the ice tone.
## Static shapes share their top edges level-wide, so two ground boxes that meet draw no rim line between them.
static func draw_level(level_root: Node3D, route: PackedVector3Array, slicer = null) -> int:
	var cache := Cache.new()
	_index_route(cache, route)
	cache.shared_edges = true
	var drawn := 0
	var jobs: Array = [] # {shape_node, hazard}
	for body: CollisionObject3D in level_root.find_children("*", "CollisionObject3D", true, false):
		if body.get_meta("fx", false): continue # lasers, fire jets and spike shells draw themselves (hazard_looks.gd)
		var hazard := bool(body.get_meta("hazard", false))
		for child: Node in body.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null or shape_node.disabled: continue
			jobs.append({"shape_node": shape_node, "hazard": hazard})
			if not hazard and not (shape_node.shape is SphereShape3D or shape_node.shape is CapsuleShape3D or shape_node.shape is CylinderShape3D):
				_collect_terrain(cache, shape_node) # every static shape's faces first: a seam between two shapes is no border
	_cover_edges(cache)
	var lifts := _lifts(jobs, cache)
	for job: Dictionary in jobs:
		if slicer != null and slicer.due(): await slicer.next()
		if _draw(job.shape_node, job.hazard, cache, lifts.get(job.shape_node.get_instance_id(), 0.0)): drawn += 1
	return drawn

## Tops that stand at the same height would z-fight (flicker in stripes) where two shapes overlap. The drawn mesh of every polygon shape is
## raised by a few millimetres: among the static shapes with the same top height the biggest footprint stays lowest, so a small block on a
## big one keeps its rim visible; every mover body gets its own lift on top of a constant 1.5 cm (a platform at rest is level with the ground
## beside it, and two movers can overlap). Collision is untouched; the largest lift is below 4 cm.
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


## Shapes of bodies outside a course (the lobby yard, lobby_visuals.gd), drawn like a level's: the same materials, a shape's role by
## its own height (no route to compare with): 1.7 m and more a teal wall, 0.7 to 1.7 a hop block, lower ground. `hazard`: in the
## hazard stripes (a hazard added to a level after its build).
static func draw_shapes(shapes: Array, hazard := false) -> int:
	var cache := Cache.new()
	var drawn := 0
	for shape_node: CollisionShape3D in shapes:
		if _draw(shape_node, hazard, cache): drawn += 1
	return drawn

## The full-screen ink pass: one quad that covers the camera's view, drawn after everything opaque (it reads the depth buffer).
static func edges(world: Node3D) -> void:
	if _edge_shader == null: _edge_shader = preload("res://style/collision_edges.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))
	var material := ShaderMaterial.new()
	material.shader = _edge_shader
	material.set_shader_parameter("ink_color", Ink.INK)
	material.render_priority = 100
	var holder := MeshInstance3D.new()
	holder.name = "CollisionLookEdges"
	holder.mesh = quad
	holder.material_override = material
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.extra_cull_margin = 16384.0
	holder.ignore_occlusion_culling = true
	world.add_child(holder)

## The route of a level (world points, about 2 m apart) in a coarse grid: what is far from every route point is background, and a
## shape's top above the route beside it says wall, hop block or ground.
static func _index_route(cache: Cache, route: PackedVector3Array) -> void:
	for p: Vector3 in route:
		var cell := Vector2i(floori(p.x / ROUTE_CELL), floori(p.z / ROUTE_CELL))
		var points: PackedVector3Array = cache.route_cells.get(cell, PackedVector3Array())
		points.append(p)
		cache.route_cells[cell] = points

## 0 near the route .. 1 far from it (0 everywhere for a course without routes).
static func _background(cache: Cache, world: Vector3) -> float:
	if cache.route_cells.is_empty(): return 0.0
	var key := Vector3i((world * 2.0).round()) # half-metre cells: the factor changes over 20 m
	if cache.background.has(key): return cache.background[key]
	var cell := Vector2i(floori(world.x / ROUTE_CELL), floori(world.z / ROUTE_CELL))
	var best := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var points: Variant = cache.route_cells.get(Vector2i(cell.x + dx, cell.y + dz))
			if points == null: continue
			for p: Vector3 in points: best = minf(best, (p.x - world.x) * (p.x - world.x) + (p.z - world.z) * (p.z - world.z))
	var value := 1.0 if best == INF else smoothstep(NEAR_ROUTE, FAR_ROUTE, sqrt(best))
	cache.background[key] = value
	return value

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

## Role (0 ground, 1 wall, 2 hop block) of a round static shape (upright cylinder): the same heights as polygon shapes, over the path beside it.
static func _round_role(cache: Cache, shape: Shape3D, shape_node: CollisionShape3D) -> int:
	var radius := 0.5
	var height := 1.0
	if shape is CylinderShape3D:
		radius = (shape as CylinderShape3D).radius
		height = (shape as CylinderShape3D).height
	elif shape is SphereShape3D:
		radius = (shape as SphereShape3D).radius
		height = radius * 2.0
	elif shape is CapsuleShape3D:
		radius = (shape as CapsuleShape3D).radius
		height = (shape as CapsuleShape3D).height
	var centre := shape_node.global_position
	var walked := _route_height(cache, Vector2(centre.x - radius, centre.z - radius), Vector2(centre.x + radius, centre.z + radius))
	var above := height if is_nan(walked) else centre.y + height * 0.5 - walked
	return 1 if above >= WALL else (2 if above >= SLAB else 0)

## One shape of one body: a MeshInstance3D child of the shape node (same transform chain as the collision).
static func _draw(shape_node: CollisionShape3D, hazard: bool, cache: Cache, lift := 0.0) -> bool:
	var shape := shape_node.shape
	var id := shape.get_instance_id()
	var visual := MeshInstance3D.new()
	visual.name = "CollisionLook"
	if shape is SphereShape3D or shape is CapsuleShape3D or shape is CylinderShape3D:
		if not cache.round_meshes.has(id):
			if shape is SphereShape3D:
				var sphere := SphereMesh.new()
				sphere.radius = (shape as SphereShape3D).radius
				sphere.height = sphere.radius * 2.0
				cache.round_meshes[id] = sphere
			elif shape is CapsuleShape3D:
				var capsule := CapsuleMesh.new()
				capsule.radius = (shape as CapsuleShape3D).radius
				capsule.height = (shape as CapsuleShape3D).height
				cache.round_meshes[id] = capsule
			else:
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = (shape as CylinderShape3D).radius
				cylinder.bottom_radius = cylinder.top_radius
				cylinder.height = (shape as CylinderShape3D).height
				cache.round_meshes[id] = cylinder
		visual.mesh = cache.round_meshes[id]
		visual.material_override = _material(cache, hazard, true, 0.0 if hazard else _background(cache, shape_node.global_position), 1 if hazard else _round_role(cache, shape, shape_node))
		shape_node.add_child(visual)
		return true
	if not (shape is BoxShape3D or shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D):
		visual.free()
		return false
	var bucket := 0
	if not (shape is ConcavePolygonShape3D) and not hazard: bucket = roundi(_background(cache, shape_node.global_position) * 3.0)
	var key := id if shape is ConcavePolygonShape3D else id * 4 + bucket
	if not cache.poly.has(key): cache.poly[key] = _poly(shape, shape_node, hazard, cache)
	var entry: Dictionary = cache.poly[key]
	if entry.is_empty():
		visual.free()
		return false
	visual.mesh = entry.fill
	visual.material_override = _material(cache, hazard, false)
	shape_node.add_child(visual)
	if lift != 0.0: visual.position = shape_node.global_transform.basis.inverse() * Vector3(0.0, lift, 0.0)
	return true

static func _quantise(p: Vector3) -> Vector3i:
	return Vector3i((p * 100.0).round())

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

## A trimesh's triangle, wound so a mostly horizontal one faces up.
static func _upward(a: Vector3, b: Vector3, c: Vector3) -> PackedVector3Array:
	var normal := (b - a).cross(c - a)
	if absf(normal.y) > 0.5 * normal.length() and normal.y < 0.0: return PackedVector3Array([a, c, b])
	return PackedVector3Array([a, b, c])

static func _edge_key(from: int, to: int) -> int:
	return (mini(from, to) << 32) | maxi(from, to)

## Level-wide, how many upward faces meet at every edge of the static shapes (world-space quantised keys). The free border of
## the ground is an edge with a single upward face; the seam between two shapes that share it has two.
static func _collect_terrain(cache: Cache, shape_node: CollisionShape3D) -> void:
	var corners := _corners(shape_node.shape, cache)
	var xf := shape_node.global_transform
	var convex := not shape_node.shape is ConcavePolygonShape3D
	var centre := Vector3.ZERO
	if convex:
		for corner in corners: centre += corner
		centre /= maxf(float(corners.size()), 1.0)
	for i in range(0, corners.size() - 2, 3):
		var tri := _upward(corners[i], corners[i + 1], corners[i + 2])
		if convex:
			var outward := (corners[i + 1] - corners[i]).cross(corners[i + 2] - corners[i])
			tri = PackedVector3Array([corners[i], corners[i + 1], corners[i + 2]]) if outward.dot((corners[i] + corners[i + 1] + corners[i + 2]) / 3.0 - centre) >= 0.0 else PackedVector3Array([corners[i], corners[i + 2], corners[i + 1]])
		var world: Array[Vector3] = [xf * tri[0], xf * tri[1], xf * tri[2]]
		var normal := (world[1] - world[0]).cross(world[2] - world[0])
		if normal.length_squared() < 1e-12: continue
		var up := normal.normalized().y >= TOP_Y
		var corner: Array[int] = []
		for p in world:
			var q := _quantise(p)
			if not cache.terrain_ids.has(q): cache.terrain_ids[q] = cache.terrain_ids.size()
			corner.append(cache.terrain_ids[q])
		for k in 3:
			var key := _edge_key(corner[k], corner[(k + 1) % 3])
			cache.terrain_tops[key] = int(cache.terrain_tops.get(key, 0)) + (1 if up else 0)
		if normal.normalized().y >= FLAT_Y:
			cache.flat_tops.append([world[0], world[1], world[2], corner[0], corner[1], corner[2]])

## An edge of a flat top that lies on another flat top at the same height (within COVER_HEIGHT) is not a free border: two floor boxes that overlap
## or meet at a slight angle (after rounding) would otherwise draw a rim band across the floor, and the two bands z-fight. Points just
## outside the edge (all but one) must stand on another top; the edge then counts as covered like a shared seam.
static func _cover_edges(cache: Cache) -> void:
	var grid: Dictionary = {}   # Vector2i cell -> Array of indices into flat_tops
	for index in cache.flat_tops.size():
		var tri: Array = cache.flat_tops[index]
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for k in 3:
			var p: Vector3 = tri[k]
			low = Vector2(minf(low.x, p.x), minf(low.y, p.z))
			high = Vector2(maxf(high.x, p.x), maxf(high.y, p.z))
		for cx in range(floori(low.x / COVER_CELL), floori(high.x / COVER_CELL) + 1):
			for cz in range(floori(low.y / COVER_CELL), floori(high.y / COVER_CELL) + 1):
				var cell := Vector2i(cx, cz)
				if not grid.has(cell): grid[cell] = []
				(grid[cell] as Array).append(index)
	var covered: Array[int] = []
	for index in cache.flat_tops.size():
		var tri: Array = cache.flat_tops[index]
		var centre: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		for k in 3:
			var key := _edge_key(tri[3 + k], tri[3 + (k + 1) % 3])
			if int(cache.terrain_tops.get(key, 0)) > 1: continue
			var a: Vector3 = tri[k]
			var b: Vector3 = tri[(k + 1) % 3]
			var along := Vector2(b.x - a.x, b.z - a.z)
			if along.length() < 1e-4: continue
			var outward := Vector2(-along.y, along.x).normalized()
			if outward.dot(Vector2(centre.x - a.x, centre.z - a.z)) > 0.0: outward = -outward
			var hits := 0
			for t in COVER_SAMPLES:
				var at := a.lerp(b, t)
				if _on_top(cache, grid, Vector2(at.x, at.z) + outward * COVER_REACH, at.y, index): hits += 1
			if hits >= COVER_SAMPLES.size() - 1: covered.append(key)
	for key: int in covered: cache.terrain_tops[key] = int(cache.terrain_tops.get(key, 0)) + 1

static func _on_top(cache: Cache, grid: Dictionary, probe: Vector2, height: float, skip: int) -> bool:
	var cell := Vector2i(floori(probe.x / COVER_CELL), floori(probe.y / COVER_CELL))
	for index: int in grid.get(cell, []):
		if index == skip: continue
		var tri: Array = cache.flat_tops[index]
		var a: Vector3 = tri[0]
		if absf(a.y - height) > COVER_HEIGHT: continue
		if _in_triangle(probe, Vector2(a.x, a.z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)): return true
	return false

static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var negative := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var positive := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (negative and positive)

## Flat-shaded triangles of a polygon shape with outward normals. Per vertex: CUSTOM0 = the distance (in the mesh's own units) to
## each of the triangle's edges that is a free border of an upward face (BIG for the others), COLOR = background (r) and role / 2 (g).
static func _poly(shape: Shape3D, shape_node: CollisionShape3D, hazard: bool, cache: Cache) -> Dictionary:
	var corners := _corners(shape, cache)
	if corners.size() < 3: return {}
	var concave := shape is ConcavePolygonShape3D
	var xf := shape_node.global_transform
	var centre := Vector3.ZERO
	if not concave:
		for corner in corners: centre += corner
		centre /= float(corners.size())
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var tops: Array[bool] = []
	var low := INF
	var high := -INF
	var foot_low := Vector2(INF, INF)
	var foot_high := Vector2(-INF, -INF)
	for i in range(0, corners.size() - 2, 3):
		var a := corners[i]
		var b := corners[i + 1]
		var c := corners[i + 2]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-12: continue
		normal = normal.normalized()
		if concave:
			if absf(normal.y) > 0.5 and normal.y < 0.0:
				var swap := b
				b = c
				c = swap
				normal = -normal
		elif normal.dot((a + b + c) / 3.0 - centre) < 0.0:
			var swap := b
			b = c
			c = swap
			normal = -normal
		positions.append(a)
		positions.append(b)
		positions.append(c)
		for k in 3: normals.append(normal)
		tops.append((xf.basis * normal).normalized().y >= TOP_Y)
		for p: Vector3 in [a, b, c]:
			var w := xf * p
			low = minf(low, w.y)
			high = maxf(high, w.y)
			foot_low = Vector2(minf(foot_low.x, w.x), minf(foot_low.y, w.z))
			foot_high = Vector2(maxf(foot_high.x, w.x), maxf(foot_high.y, w.z))
	if positions.is_empty(): return {}
	# edges: how many upward faces meet at each of them. A concave shape's, and those of every static shape of a level (shared_edges), are
	# level-wide (collected by _collect_terrain); a moving shape counts its own.
	var shared := concave or (cache.shared_edges and not hazard)
	var local_tops: Dictionary = {}
	var ids: Dictionary = {}
	var corner_ids := PackedInt32Array()
	for index in positions.size():
		var p := positions[index]
		var q := _quantise(xf * p) if shared else _quantise(p)
		var table: Dictionary = cache.terrain_ids if shared else ids
		if not table.has(q): table[q] = table.size()
		corner_ids.append(table[q])
	if not shared:
		for tri in positions.size() / 3:
			if not tops[tri]: continue
			for k in 3:
				var key := _edge_key(corner_ids[tri * 3 + k], corner_ids[tri * 3 + (k + 1) % 3])
				local_tops[key] = int(local_tops.get(key, 0)) + 1
	var edge_tops: Dictionary = cache.terrain_tops if shared else local_tops
	# ROLE. By how far the shape's top stands above the path beside it: walls (>= WALL) role 1, hop blocks (>= SLAB) role 2, else ground (0).
	# Without a path nearby, by its own height. Ice (meta "ice") is role 3.
	var shape_role := 0.0
	if not hazard:
		var walked := _route_height(cache, foot_low, foot_high)
		var above := high - (low if is_nan(walked) else walked)
		shape_role = 1.0 if above >= WALL else (2.0 if above >= SLAB else 0.0)
		if shape_node.has_meta("ice"): shape_role = 3.0
	# Ground boxes lying flat are drawn a little wider than they collide (at most SEAM_GROW per side, less for thin ones): rounded neighbours leave
	# hairline cracks, and a crack shimmers when the camera moves.
	if shape is BoxShape3D and not hazard and shape_role == 0.0 and xf.basis.y.normalized().y > FLAT_Y:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		var grow := Vector3(clampf(half.x * 0.12, 0.0, SEAM_GROW), 0.0, clampf(half.z * 0.12, 0.0, SEAM_GROW))
		for index in positions.size():
			var corner := positions[index]
			positions[index] = corner + Vector3(signf(corner.x) * grow.x, 0.0, signf(corner.z) * grow.z)
	var custom := PackedFloat32Array()
	var colors := PackedColorArray()
	for tri in positions.size() / 3:
		var a := positions[tri * 3]
		var b := positions[tri * 3 + 1]
		var c := positions[tri * 3 + 2]
		var area2 := (b - a).cross(c - a).length()
		var height_a := area2 / maxf((c - b).length(), 1e-6)   # distance of a to edge bc
		var height_b := area2 / maxf((a - c).length(), 1e-6)   # b to edge ca
		var height_c := area2 / maxf((b - a).length(), 1e-6)   # c to edge ab
		var role := shape_role
		var border: Array[bool] = [false, false, false]
		if tops[tri]:
			for k in 3:
				border[k] = int(edge_tops.get(_edge_key(corner_ids[tri * 3 + k], corner_ids[tri * 3 + (k + 1) % 3]), 0)) <= 1
		# edge 0 = ab, 1 = bc, 2 = ca; per vertex (d to ab, d to bc, d to ca)
		custom.append_array(PackedFloat32Array([0.0 if border[0] else BIG, height_a if border[1] else BIG, 0.0 if border[2] else BIG]))
		custom.append_array(PackedFloat32Array([0.0 if border[0] else BIG, 0.0 if border[1] else BIG, height_b if border[2] else BIG]))
		custom.append_array(PackedFloat32Array([height_c if border[0] else BIG, 0.0 if border[1] else BIG, 0.0 if border[2] else BIG]))
		for k in 3:
			var background := 0.0 if hazard else _background(cache, xf * positions[tri * 3 + k])
			colors.append(Color(background, role / 3.0, 0.0, 1.0))
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = positions
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_CUSTOM0] = custom
	var fill := ArrayMesh.new()
	fill.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface, [], {}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return {"fill": fill}

## The dark void under a level: one plane, 6000 m wide, that the world moves under the level being played.
static func void_plane(parent: Node3D) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	var water := MeshInstance3D.new()
	water.name = "CollisionLookVoid"
	water.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = preload("res://style/collision_water.gdshader")
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0.0, WATER_Y, 0.0)
	parent.add_child(water)
	return water

## START and GOAL of a level: the ring and flag of the ink look, the coloured disc under it and a word on a sign above. `lateral` is the
## side the flag stands on. The GOAL flag takes the team's brand accent and the team logo hangs over the GOAL word.
## All nodes are children of `level_root` (world positions given), so hiding the root hides them. `arch_under`: the height of the underside of the
## arch over the goal over the goal floor (SlotFrames.goal_arch_under, INF for none): the GOAL word and the card keep under it, and the card is
## dropped when the arch wears the same logo (SlotFrames.goal_marks).
static func mark_level(level_root: Node3D, start: Vector3, goal_floor: Vector3, lateral: Vector3, goal := true, arch_under := INF) -> void:
	var marks := SlotFrames.goal_marks(GOAL_WORD_HALF, arch_under)
	var font: Font = preload("res://assets/fonts/Bangers-Regular.ttf") # Bangers runs small for its em: sized up below
	var markers := Markers.new()
	markers.name = "CollisionLookMarkers"
	level_root.add_child(markers)
	var spots: Array = [["START", start]]
	if goal: spots.append(["GOAL", goal_floor])
	for spot: Array in spots:
		var at: Vector3 = spot[1]
		var brand := TeamCast.brand_accent()
		markers.add(at, lateral, brand if spot[0] == "GOAL" and brand.a > 0.0 else Ink.TOMATO)
		var accent := START_COLOR if spot[0] == "START" else GOAL_COLOR
		var pad := _pad(accent)
		level_root.add_child(pad)
		pad.global_position = at + Vector3(0.0, 0.02, 0.0)
		var label := Label3D.new()
		label.text = str(spot[0])
		if font != null: label.font = font
		label.font_size = 118
		label.pixel_size = 0.008
		label.outline_size = 26
		label.modulate = accent
		label.outline_modulate = Ink.INK
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		if spot[0] == "GOAL":
			# Seen from close by (a courier walking past, a lift arriving) the billboard grows past the screen edge or sits half
			# behind the HUD lettering, which reads as a stray yellow letter: it fades out inside GOAL_SIGN_NEAR metres.
			label.visibility_range_begin = GOAL_SIGN_NEAR
			label.visibility_range_begin_margin = GOAL_SIGN_FADE
			label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if float(marks.card) >= 0.0: _goal_logo(level_root, at + Vector3(0.0, float(marks.card), 0.0))
		level_root.add_child(label)
		label.global_position = at + Vector3(0.0, float(marks.word) if spot[0] == "GOAL" else SlotFrames.GOAL_WORD_Y, 0.0)

## The goal sign's picture (goal_sign.png, else the team logo) on a paper card over the GOAL word (nothing without either);
## fades out close by like the word.
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
	sign.visibility_range_begin = GOAL_SIGN_NEAR
	sign.visibility_range_begin_margin = GOAL_SIGN_FADE
	sign.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	level_root.add_child(sign)
	sign.global_position = at

## Ring, pole and flag on a checkpoint spot (ink look).
class Markers extends Node3D:
	const RING_SIZE := 5.2
	const POLE_SIDE := 3.1
	const POLE_HEIGHT := 2.6

	func add(base: Vector3, lateral: Vector3, cloth_color := Ink.TOMATO) -> void:
		var ring := MeshInstance3D.new()
		ring.name = "CheckpointRing"
		var quad := QuadMesh.new()
		quad.size = Vector2(RING_SIZE, RING_SIZE)
		quad.orientation = PlaneMesh.FACE_Y
		ring.mesh = quad
		ring.material_override = Ink.checkpoint_ring()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = base + Vector3(0.0, 0.03, 0.0)
		var foot := base + lateral * POLE_SIDE
		var pole := MeshInstance3D.new()
		pole.name = "CheckpointPole"
		var rod := CylinderMesh.new()
		rod.top_radius = 0.035
		rod.bottom_radius = 0.045
		rod.height = POLE_HEIGHT
		rod.radial_segments = 8
		rod.rings = 1
		pole.mesh = rod
		pole.material_override = Ink.checkpoint_flag(false)
		add_child(pole)
		pole.global_position = foot + Vector3.UP * (POLE_HEIGHT * 0.5)
		var cloth := MeshInstance3D.new()
		cloth.name = "CheckpointFlag"
		var sheet := BoxMesh.new()
		sheet.size = Vector3(1.0, 0.6, 0.05)
		cloth.mesh = sheet
		cloth.material_override = Ink.checkpoint_flag(true, cloth_color)
		add_child(cloth)
		cloth.global_position = foot + Vector3.UP * (POLE_HEIGHT - 0.4) - lateral * 0.5
		cloth.global_basis = Basis(lateral, Vector3.UP, lateral.cross(Vector3.UP))
## The flat disc under a checkpoint ring: green at a START, gold at a GOAL, with a darker rim and a pale inner ring.
static func _pad(color: Color) -> MeshInstance3D:
	if _pad_shader == null: _pad_shader = preload("res://style/collision_pad.gdshader")
	var disc := CylinderMesh.new()
	disc.top_radius = PAD_RADIUS
	disc.bottom_radius = PAD_RADIUS
	disc.height = 0.04
	disc.radial_segments = 48
	disc.rings = 1
	var material := ShaderMaterial.new()
	material.shader = _pad_shader
	material.set_shader_parameter("pad_color", color)
	material.set_shader_parameter("radius", PAD_RADIUS)
	var holder := MeshInstance3D.new()
	holder.name = "CollisionLookPad"
	holder.mesh = disc
	holder.material_override = material
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder
