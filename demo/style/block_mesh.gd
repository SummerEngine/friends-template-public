extends RefCounted
## Meshes of the facility look, built from a level's collision shapes (style/collision_look.gd). Boxes get rounded edges (a radius
## and a number of segments per edge), cylinders and balls are lathed with rounded rims; any other polygon shape keeps its own flat faces.
## UVs are in metres along the face, laid out in the mesh's own space (the level for static blocks, the body for movers), so a
## texture runs on without a seam across blocks that line up; sides stand upright. Triangles are collected per material key and
## leave as one ArrayMesh with one surface per key (with tangents for the normal maps). Godot's front faces wind clockwise.
const PillarKit := preload("res://style/pillar_kit.gd")   ## the raised chevrons of a belt
const MIN_SHOULDER := 0.04    # pillow_slab: the smallest rounding of an edge (m)
const SEAM_ALPHA := 0.5       # pillow_slab: the vertex alpha of an edge that is a pinched seam
const DOME := 10.0             # pillow_slab: the ring that closes the flat top, after the shoulder's rings
const DOME_TILT := 0.14        # radians (8 degrees): how far the shoulder's last ring's normal leans outward
const DOME_WIDTH := 1.6        # m: the band of the flat top over which the normals lean from straight up to DOME_TILT
const TOP_Y := 0.65            # a face whose normal points this far up takes the top key
const LATHE_SIDES := 20
## A conveyor belt (a static box with the meta "belt", real_look.gd) takes the top key BELT_PREFIX + its velocity ("belt:3.0:0.0": level-local x and z m/s), one
## material per direction and speed (style/belt_look.gdshader). Its top is laid by Batch.belt.
const BELT_PREFIX := "belt:"
const BELT_RAIL := 0.2         # width of the rail strip along each side of a belt (m)
const BELT_LIFT := 0.005       # the belt's deck lies this far over the box's own top (m)

## The surface key of a belt that moves at `velocity` (level-local planar m/s).
static func belt_key(velocity: Vector2) -> String:
	return "%s%s:%s" % [BELT_PREFIX, velocity.x, velocity.y]

## The velocity a belt key stands for (ZERO for any other key).
static func belt_velocity(key: String) -> Vector2:
	if not key.begins_with(BELT_PREFIX): return Vector2.ZERO
	var parts := key.trim_prefix(BELT_PREFIX).split(":")
	return Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.ZERO

## The triangles of one material key.
class Group extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var uv2 := PackedVector2Array()   ## per vertex: how far it is from the box's edges (Batch.box `edge_data`); only sent to the mesh when `edged`
	var edged := false

	func add(position: Vector3, normal: Vector3, coords: Vector2, color: Color, edge := Vector2(8.0, 8.0)) -> int:
		v.append(position)
		n.append(normal)
		uv.append(coords)
		c.append(color)
		uv2.append(edge)
		return v.size() - 1

	## Triangle a b c, wound clockwise as seen from `outward`; degenerate ones are dropped.
	func triangle(a: int, b: int, c_index: int, outward: Vector3) -> void:
		var winding := (v[b] - v[a]).cross(v[c_index] - v[a])
		if winding.length_squared() < 1e-14: return
		if winding.dot(outward) > 0.0: i.append_array(PackedInt32Array([a, c_index, b]))
		else: i.append_array(PackedInt32Array([a, b, c_index]))

	func quad(p0: int, p1: int, p2: int, p3: int, outward: Vector3) -> void:
		triangle(p0, p1, p2, outward)
		triangle(p0, p2, p3, outward)

	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		out[Mesh.ARRAY_NORMAL] = n
		out[Mesh.ARRAY_TEX_UV] = uv
		if edged: out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_COLOR] = c
		out[Mesh.ARRAY_INDEX] = i
		return out

class Batch extends RefCounted:
	var groups := {}           # key -> Group

	func group(key: String) -> Group:
		if not groups.has(key): groups[key] = Group.new()
		return groups[key]

	func is_empty() -> bool:
		return groups.is_empty()

	## One ArrayMesh, one surface per key (sorted), each with materials[key]; null when nothing was added.
	func commit(materials: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var keys := groups.keys()
		keys.sort()
		for key: String in keys:
			var g: Group = groups[key]
			if g.i.is_empty(): continue
			var tool := SurfaceTool.new()
			tool.create_from_arrays(g.arrays())
			tool.generate_tangents()
			tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(key))
		return mesh if mesh.get_surface_count() > 0 else null

	## A box of `size` placed by `xf` (box space -> mesh space), edges rounded by `radius` in `segments` steps. Faces pointing up take
	## `top_key`, the others `side_key`. `lift` raises the whole box (mesh space y). `edge_data`: every vertex also tells how far it is from the box's edges
	## (the mesh's UV2, metres: on a top face the distances to its two pairs of edges, on a side face the depth under the top edge and the distance to its vertical edges), so
	## a shader can paint a rim, edge lines or a chevron that follows the face (style/candy_surface.gdshader pattern 2 and 7); `end_key` (with it) is the key of the two narrow side faces. `max_share`: the
	## radius is at most this share of half the shortest side (a pillow takes 1.0, an ordinary rounded box 0.45).
	func box(xf: Transform3D, size: Vector3, radius: float, segments: int, top_key: String, side_key: String, color := Color.WHITE, lift := 0.0, edge_data := false, end_key := "", max_share := 0.45) -> void:
		var half := size * 0.5
		var r := minf(radius, minf(half.x, minf(half.y, half.z)) * max_share)
		if r < 0.004: r = 0.0
		var inner := half - Vector3.ONE * r
		var lines: Array[PackedFloat32Array] = [BlockLines.of(half.x, r, segments, edge_data), BlockLines.of(half.y, r, segments, edge_data), BlockLines.of(half.z, r, segments, edge_data)]
		var shift := Vector3(0.0, lift, 0.0)
		var shape_x := xf.basis.x.normalized()
		for a in 3:
			var b := (a + 1) % 3
			var c := (a + 2) % 3
			for s: float in [-1.0, 1.0]:
				var face_normal := Vector3.ZERO
				face_normal[a] = s
				var out := (xf.basis * face_normal).normalized()
				var along := 2 if a == 0 else 0   # a side face's horizontal axis of the box
				var narrow := end_key != "" and a != 1 and half[along] < half[a]
				var g := group(top_key if out.y >= TOP_Y else (end_key if narrow else side_key))
				g.edged = g.edged or edge_data
				var frame := BlockLines.frame(out, shape_x)
				var lb: PackedFloat32Array = lines[b]
				var lc: PackedFloat32Array = lines[c]
				var base := g.v.size()
				for row in lb.size():
					for column in lc.size():
						var q := Vector3.ZERO
						q[a] = s * half[a]
						q[b] = lb[row]
						q[c] = lc[column]
						var core := q.clamp(-inner, inner)
						var dir := q - core
						dir = dir.normalized() if dir.length_squared() > 1e-12 else face_normal
						var mq := xf * q
						var edge := Vector2(8.0, 8.0)
						if edge_data:
							edge = Vector2(half[b] - absf(q[b]), half[c] - absf(q[c])) if a == 1 else Vector2(half.y - q.y, half[along] - absf(q[along]))
						g.add(xf * (core + dir * r) + shift, (xf.basis * dir).normalized(), Vector2(mq.dot(frame[0]), -mq.dot(frame[1])), color, edge)
				var columns := lc.size()
				for row in lb.size() - 1:
					for column in columns - 1:
						var p00 := base + row * columns + column
						g.quad(p00, p00 + columns, p00 + columns + 1, p00 + 1, out)

	## Flat triangles in shape space (a convex hull or trimesh: wedges and the like), each face with its own normal pointing away from the
	## centre (a trimesh: mostly horizontal faces up).
	func triangles(xf: Transform3D, corners: PackedVector3Array, concave: bool, top_key: String, side_key: String, color := Color.WHITE, lift := 0.0) -> void:
		var centre := Vector3.ZERO
		for corner in corners: centre += corner
		centre = xf * (centre / maxf(float(corners.size()), 1.0))
		var shift := Vector3(0.0, lift, 0.0)
		var shape_x := xf.basis.x.normalized()
		for k in range(0, corners.size() - 2, 3):
			var a := xf * corners[k]
			var b := xf * corners[k + 1]
			var c := xf * corners[k + 2]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-12: continue
			normal = normal.normalized()
			var away := normal.dot((a + b + c) / 3.0 - centre)
			if concave: away = normal.y if absf(normal.y) >= 0.5 else 1.0
			if away < 0.0: normal = -normal
			var g := group(top_key if normal.y >= TOP_Y else side_key)
			var frame := BlockLines.frame(normal, shape_x)
			var ia := g.add(a + shift, normal, Vector2(a.dot(frame[0]), -a.dot(frame[1])), color)
			var ib := g.add(b + shift, normal, Vector2(b.dot(frame[0]), -b.dot(frame[1])), color)
			var ic := g.add(c + shift, normal, Vector2(c.dot(frame[0]), -c.dot(frame[1])), color)
			g.triangle(ia, ib, ic, normal)

	## A lathe about the shape's y axis: an upright cylinder (radius, height) with rims rounded by `bevel` (flat caps take `cap_key`),
	## or a ball (height 0). `unit_caps`: the flat caps' UV is the unit disc (the cap's own plane, 1 at the radius) instead of world metres, for a face painted on a cap (style/race_surfaces.gd "eye").
	func lathe(xf: Transform3D, radius: float, height: float, bevel: float, key: String, cap_key: String, color := Color.WHITE, unit_caps := false) -> void:
		var profile: Array = []   # [distance from the axis, y, normal in the profile plane (out, up)]
		if height <= 0.0:
			for k in 13:
				var angle := -PI * 0.5 + PI * float(k) / 12.0
				profile.append([cos(angle) * radius, sin(angle) * radius, Vector2(cos(angle), sin(angle))])
		else:
			var h := height * 0.5
			var r := minf(bevel, minf(radius, h) * 0.45)
			profile.append([0.0, -h, Vector2(0.0, -1.0)])
			profile.append([radius - r, -h, Vector2(0.0, -1.0)])
			for k in range(1, 3):
				var angle := -PI * 0.5 + PI * 0.25 * float(k)
				profile.append([radius - r + cos(angle) * r, -h + r + sin(angle) * r, Vector2(cos(angle), sin(angle))])
			profile.append([radius, h - r, Vector2(1.0, 0.0)])
			for k in range(1, 3):
				var angle := PI * 0.25 * float(k)
				profile.append([radius - r + cos(angle) * r, h - r + sin(angle) * r, Vector2(cos(angle), sin(angle))])
			profile.append([radius - r, h, Vector2(0.0, 1.0)])
			profile.append([0.0, h, Vector2(0.0, 1.0)])
		for band in profile.size() - 1:
			var lo: Array = profile[band]
			var hi: Array = profile[band + 1]
			var flat_cap := height > 0.0 and (band == 0 or band == profile.size() - 2)
			var g := group(cap_key if flat_cap else key)
			var base := g.v.size()
			for k in LATHE_SIDES + 1:
				var angle := TAU * float(k) / LATHE_SIDES
				var around := Vector3(cos(angle), 0.0, sin(angle))
				for row: Array in [lo, hi]:
					var n2: Vector2 = row[2]
					var mp := xf * (around * float(row[0]) + Vector3(0.0, float(row[1]), 0.0))
					var coords := (Vector2(around.x, around.z) * float(row[0]) / maxf(radius, 1e-4) if unit_caps else Vector2(mp.x, mp.z)) if flat_cap else Vector2(angle * radius, -float(row[1]))
					g.add(mp, (xf.basis * (around * n2.x + Vector3(0.0, n2.y, 0.0))).normalized(), coords, color)
			for k in LATHE_SIDES:
				var i0 := base + k * 2
				g.quad(i0, i0 + 2, i0 + 3, i0 + 1, g.n[i0] + g.n[i0 + 3])

	## A conveyor belt: the box (all faces in `side_key`) with a deck laid over its top, inside its rounded rim: a lane between two rail strips parallel to the
	## flow (the box side the belt runs along). The deck's UVs are metres: x along the flow from the belt's trailing end, y across it from the lane's middle;
	## the vertex colour's red is 1 on the rails, 0 on the lane. On the lane stand raised, bevelled chevrons (style/pillar_kit.gd chevron_mesh), one column of them per 1.6 m of lane
	## width, one every PillarKit.BELT_PERIOD m along it: every chevron vertex has COLOR.g = 1 (COLOR.b = 1 on the face), UV = (the apex's place along the belt, the vertex's place behind the apex),
	## UV2 = (the belt's length, its height over the deck), and the shader (belt_look.gdshader) slides them along the belt.
	func belt(xf: Transform3D, size: Vector3, radius: float, segments: int, side_key: String, deck_key: String, flow: Vector2, lift := 0.0) -> void:
		box(xf, size, radius, segments, side_key, side_key, Color.WHITE, lift)
		var half := size * 0.5
		var r := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.45)
		if r < 0.004: r = 0.0
		var heading := flow.normalized()
		var x_axis := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z).normalized()
		var z_axis := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
		var along_x := absf(x_axis.x * heading.x + x_axis.z * heading.y) >= absf(z_axis.x * heading.x + z_axis.z * heading.y)
		var run_axis := x_axis if along_x else z_axis
		var side_axis := z_axis if along_x else x_axis
		var run_half := (half.x if along_x else half.z) - r
		var side_half := (half.z if along_x else half.x) - r
		if run_half <= 0.0 or side_half <= 0.0: return
		var rail := minf(BELT_RAIL, side_half * 0.5)
		var middle := xf * Vector3(0.0, half.y, 0.0) + Vector3(0.0, lift + BELT_LIFT, 0.0)
		var g := group(deck_key)
		g.edged = true
		var edges := [-side_half, -side_half + rail, side_half - rail, side_half]
		for strip in 3:
			var color := Color(1.0, 0.0, 0.0, 1.0) if strip != 1 else Color(0.0, 0.0, 0.0, 1.0)
			var base := g.v.size()
			for run_at: float in [-run_half, run_half]:
				for side_at: float in [edges[strip], edges[strip + 1]]:
					var offset: Vector3 = run_axis * run_at + side_axis * side_at
					var along := offset.x * heading.x + offset.z * heading.y
					var across := -offset.x * heading.y + offset.z * heading.x
					g.add(middle + offset, Vector3.UP, Vector2(along + run_half, across), color)
			g.quad(base, base + 1, base + 3, base + 2, Vector3.UP)
		_chevrons(g, middle, heading, run_half, side_half - rail)

	## The raised chevrons of a belt (see `belt`): `middle` the middle of its deck, `run_half` half its length, `lane` half the width between the rails.
	func _chevrons(g: Group, middle: Vector3, heading: Vector2, run_half: float, lane: float) -> void:
		var length := run_half * 2.0
		var columns := maxi(1, roundi(lane / PillarKit.BELT_REACH))
		var pitch := 2.0 * lane / float(columns)
		var reach := minf(PillarKit.BELT_REACH, pitch * 0.5 - 0.1)
		if reach < 0.15: return
		var mesh := PillarKit.chevron_mesh(reach)
		var pos: PackedVector3Array = mesh.pos
		var nrm: PackedVector3Array = mesh.nrm
		var role: PackedInt32Array = mesh.role
		var tri: PackedInt32Array = mesh.tri
		var flow3 := Vector3(heading.x, 0.0, heading.y)
		var side3 := Vector3(-heading.y, 0.0, heading.x)
		var start := middle - flow3 * run_half
		var count := ceili((length + PillarKit.BELT_SPAN) / PillarKit.BELT_PERIOD)
		for column in columns:
			var across := -lane + pitch * (float(column) + 0.5)
			for k in count:
				var apex := float(k) * PillarKit.BELT_PERIOD + PillarKit.BELT_STROKE
				var base := g.v.size()
				for i in pos.size():
					var p := pos[i]
					var at := start + flow3 * (apex + p.x) + side3 * (across + p.y) + Vector3(0.0, p.z - PillarKit.BELT_SINK, 0.0)
					var n := nrm[i]
					var normal := (flow3 * n.x + side3 * n.y + Vector3.UP * n.z).normalized()
					g.add(at, normal, Vector2(apex, p.x), Color(0.0, 1.0, 1.0 if role[i] == 2 else 0.0, 1.0), Vector2(length, p.z))
				for t in range(0, tri.size(), 3):
					g.triangle(base + tri[t], base + tri[t + 1], base + tri[t + 2], g.n[base + tri[t]])

	## A chamfered prism for the block kit (style/block_kit.gd): flat faces, each with its own normal, in the vertex colour `side_color` (upright faces and the underside bevel) or `top_color`
	## (the top bevel and the top). `rings` = [[inset, y], ...] bottom to top in the shape's space: every ring is the footprint (half extents `half` x/z around `centre` x/z) shrunk by `inset`,
	## with the four corners (+x+z, -x+z, -x-z, +x-z) cut off by `cuts[i]` m (0 = square); two rings of the same inset make an upright face, different insets a chamfer. `caps`: 1 closes the
	## bottom, 2 the top (a part buried in another one leaves its hidden faces out). UV is metres (sides upright, v down), like `box`.
	func prism(key: String, xf: Transform3D, centre: Vector3, half: Vector3, rings: Array, cuts: PackedFloat32Array, side_color: Color, top_color: Color, caps := 3) -> void:
		var g := group(key)
		var shape_x := xf.basis.x.normalized()
		var outlines: Array = []
		for ring: Array in rings: outlines.append(BlockLines.outline(centre.x, centre.z, maxf(half.x - float(ring[0]), 0.001), maxf(half.z - float(ring[0]), 0.001), cuts, float(ring[1])))
		for r in rings.size() - 1:
			var lo: Array = outlines[r]
			var hi: Array = outlines[r + 1]
			var color := top_color if float((rings[r + 1] as Array)[0]) > float((rings[r] as Array)[0]) + 1e-6 else side_color # a band that narrows going up (the underside's rounding) is a side, one that widens inwards on the top a top
			for j in lo.size():
				var k := (j + 1) % lo.size()
				_facet(g, xf, shape_x, [lo[j], lo[k], hi[k], hi[j]], Vector3(centre.x, 0.0, centre.z), color)
		if caps & 1 != 0: _facet(g, xf, shape_x, outlines[0], Vector3(centre.x, 0.0, centre.z), side_color, Vector3.DOWN)
		if caps & 2 != 0: _facet(g, xf, shape_x, outlines[outlines.size() - 1], Vector3(centre.x, 0.0, centre.z), top_color, Vector3.UP)

	## A slab with chamfered edges, the walkable block of the candy look (style/block_kit.gd): upright walls, a flat top, a 45 degree chamfer along every top edge that is open and a small one under
	## the bottom edge, flat facets (a crisp bevel highlight). `half`: half extents about the xf origin. `top_cut`: the chamfer width of the top edges (+x, -x, +z, -z; 0 = a square edge, where another
	## block joins), `bottom_cut` the underside's, `corner` the radius of the upright corners (two steps). The chamfer and the top take `top_color`, the walls and the underside `side_color`.
	## Nothing leaves the box: the chamfers cut into it, so the collision stays under the visual.
	func chamfered(key: String, xf: Transform3D, half: Vector3, top_cut: PackedFloat32Array, bottom_cut: float, corner: float, top_color: Color, side_color: Color) -> void:
		var g := group(key)
		var shape_x := xf.basis.x.normalized()
		var deepest := maxf(maxf(top_cut[0], top_cut[1]), maxf(top_cut[2], top_cut[3]))
		var rise := minf(deepest, half.y * 1.6)
		var bottom := minf(bottom_cut, half.y * 0.8 - 0.001)
		var rings: Array = [ # [y, insets +x, -x, +z, -z]
			[-half.y, bottom, bottom, bottom, bottom],
			[-half.y + bottom, 0.0, 0.0, 0.0, 0.0],
			[half.y - rise, 0.0, 0.0, 0.0, 0.0],
			[half.y, top_cut[0], top_cut[1], top_cut[2], top_cut[3]],
		]
		var outlines: Array = []
		for ring: Array in rings:
			var inset_x := (float(ring[1]) + float(ring[2])) * 0.5
			var inset_z := (float(ring[3]) + float(ring[4])) * 0.5
			var cut := maxf(corner - maxf(inset_x, inset_z), 0.006) if corner > 0.0 else 0.0
			outlines.append(BlockLines.outline((float(ring[2]) - float(ring[1])) * 0.5, (float(ring[4]) - float(ring[3])) * 0.5, maxf(half.x - inset_x, 0.001), maxf(half.z - inset_z, 0.001), PackedFloat32Array([cut, cut, cut, cut]), float(ring[0])))
		for r in rings.size() - 1:
			var lo: Array = outlines[r]
			var hi: Array = outlines[r + 1]
			var color := top_color if r == rings.size() - 2 else side_color
			for j in lo.size():
				var k := (j + 1) % lo.size()
				_facet(g, xf, shape_x, [lo[j], lo[k], hi[k], hi[j]], Vector3.ZERO, color)
		_facet(g, xf, shape_x, outlines[0], Vector3.ZERO, side_color, Vector3.DOWN)
		_facet(g, xf, shape_x, outlines[outlines.size() - 1], Vector3.ZERO, top_color, Vector3.UP)

	## A PILLOW slab, the walkable block of the race courses (style/block_kit.gd): upright walls, a flat top at the box's top and, along every top edge that is open, an inflated shoulder: a quarter
	## round of radius `top_round[i]` (+x, -x, +z, -z; at least MIN_SHOULDER: where another block joins the edge gets only a small one, a pinched seam), `steps` bands of smooth normals (`seams`: a bit mask of the edges, bit i = edge i, that are pinched seams, not shoulders: their vertices get alpha SEAM_ALPHA), so the edge catches light like a vinyl cushion; under the bottom
	## edge a small chamfer, upright corners rounded by `corner`. The top stays exactly in the box's top plane and the shoulder only goes DOWN and in: nothing leaves the box, the collision stays
	## under the visual. The shoulder's colour fades from `top_color` to `side_color` (a little darker where it turns away); the walls and the underside take `side_color`.
	func pillow_slab(key: String, xf: Transform3D, half: Vector3, top_round: PackedFloat32Array, bottom_cut: float, corner: float, top_color: Color, side_color: Color, seams := 0, steps := 3) -> void:
		var g := group(key)
		var bottom := minf(bottom_cut, half.y * 0.8 - 0.001)
		var limit := maxf(half.y * 2.0 - bottom - 0.02, 0.0)
		var radius: Array[float] = []
		for e in 4: radius.append(clampf(maxf(top_round[e], MIN_SHOULDER), 0.0, minf(limit, minf(half.x, half.z) * 0.9))) # never 0: an edge that joins another block still gets a small shoulder (the seam), so every edge's ring is consistent
		var corner_cut := maxf(corner, 0.01)
		var dome_width := clampf(minf(half.x, half.z) * 0.5 - maxf(maxf(radius[0], radius[1]), maxf(radius[2], radius[3])), 0.0, DOME_WIDTH)
		var rings: Array = [] # per ring: Array of vertex indices (12 each)
		var ring_defs: Array = [] # bottom to top: -2 the underside's edge, -1 the wall's foot, then the shoulder's angles 0 to 90 degrees
		ring_defs.append(-2.0)
		ring_defs.append(-1.0)
		for k in steps + 1: ring_defs.append(PI * 0.5 * float(k) / float(steps))
		ring_defs.append(DOME)
		for def: float in ring_defs:
			var inset := [0.0, 0.0, 0.0, 0.0]
			if def == DOME: for e in 4: inset[e] = radius[e] + (dome_width if radius[e] > 0.0 else 0.0)
			elif def >= 0.0: for e in 4: inset[e] = radius[e] * (1.0 - cos(def))
			elif def < -1.5: for e in 4: inset[e] = bottom
			var inset_x: float = (inset[0] + inset[1]) * 0.5
			var inset_z: float = (inset[2] + inset[3]) * 0.5
			var cut := maxf(corner_cut - maxf(inset_x, inset_z), 0.006)
			var flat_y := -half.y + (bottom if def > -1.5 else 0.0)
			var points := BlockLines.outline((float(inset[1]) - float(inset[0])) * 0.5, (float(inset[3]) - float(inset[2])) * 0.5, maxf(half.x - inset_x, 0.001), maxf(half.z - inset_z, 0.001), PackedFloat32Array([cut, cut, cut, cut]), 0.0)
			var ring: Array = []
			var signs := [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)]
			for j in points.size():
				var corner_index := j / 3
				var role := j % 3 # 0 first point of the corner's arc, 1 its middle, 2 the last
				var s: Vector2 = signs[corner_index]
				var on_x := (role == 0) == (corner_index % 2 == 0) # the point sits on a face standing across x (the +x / -x edge), else across z
				var e_x := 0 if s.x > 0.0 else 1
				var e_z := 2 if s.y > 0.0 else 3
				var out := Vector3(s.x, 0.0, 0.0) if on_x else Vector3(0.0, 0.0, s.y)
				var r := radius[e_x] if on_x else radius[e_z]
				if role == 1:
					out = Vector3(s.x, 0.0, s.y).normalized()
					r = (radius[e_x] + radius[e_z]) * 0.5
				var p: Vector3 = points[j]
				var normal := out
				if def == DOME: # the flat top's own ring: normal up (the top is flat)
					p.y = half.y
					normal = Vector3.UP
				elif def >= 0.0:
					p.y = half.y - r * (1.0 - sin(def))
					normal = out * cos(def) + Vector3.UP * sin(def)
					if def > PI * 0.5 - 0.001 and r > 0.0: normal = (out * sin(DOME_TILT) + Vector3.UP * cos(DOME_TILT)).normalized() # the shoulder's last ring leans outward, the ring inside it is straight up: the top shades like a gently domed cushion while its geometry stays in the plane
				elif def > -1.5:
					p.y = flat_y
				else:
					p.y = -half.y
					normal = (out * 0.94 + Vector3.DOWN * 0.34).normalized() # mostly outward: an underside facing straight down is black under the sky light
				var fade := 1.0 if def == DOME else (sin(def) if def >= 0.0 else 0.0)
				var color := side_color.lerp(top_color, clampf(0.35 + 0.65 * fade, 0.0, 1.0)) if def >= 0.0 else side_color
				var seam := (seams >> e_x) & 1 == 1 if role != 1 and on_x else ((seams >> e_z) & 1 == 1 if role != 1 else ((seams >> e_x) & 1 == 1 or (seams >> e_z) & 1 == 1))
				color.a = SEAM_ALPHA if seam else 1.0 # alpha 0.5 marks a pinched seam: style/candy_surface.gdshader darkens a steep surface there (`crease`), never on the shoulder of an open edge
				var mp := xf * p
				var coords := Vector2(mp.x, mp.z) if normal.y >= TOP_Y else Vector2(mp.x + mp.z, -mp.y)
				ring.append(g.add(mp, (xf.basis * normal).normalized(), coords, color))
			rings.append(ring)
		for r in rings.size() - 1:
			var lo: Array = rings[r]
			var hi: Array = rings[r + 1]
			for j in lo.size():
				var k := (j + 1) % lo.size()
				var outward: Vector3 = g.n[lo[j]] + g.n[lo[k]]
				g.quad(lo[j], lo[k], hi[k], hi[j], outward)
		var top: Array = rings[rings.size() - 1]
		for j in range(1, top.size() - 1): g.triangle(top[0], top[j], top[j + 1], xf.basis.y.normalized())
		var under: Array = rings[0]
		var first := -1
		var previous := -1
		for j in under.size():
			var index := g.add(g.v[under[j]], (xf.basis * Vector3.DOWN).normalized(), Vector2(g.v[under[j]].x, g.v[under[j]].z), side_color)
			if first < 0: first = index
			elif previous >= 0: g.triangle(first, previous, index, (xf.basis * Vector3.DOWN).normalized())
			previous = index

	## One flat convex polygon (shape space, any winding) into `g`: its normal points away from `inside` (a point in shape space), or along `facing` when given.
	func _facet(g: Group, xf: Transform3D, shape_x: Vector3, points: Array, inside: Vector3, color: Color, facing := Vector3.ZERO) -> void:
		var normal := ((points[1] as Vector3) - (points[0] as Vector3)).cross((points[2] as Vector3) - (points[0] as Vector3))
		if normal.length_squared() < 1e-14: return
		normal = normal.normalized()
		if facing != Vector3.ZERO:
			if normal.dot(facing) < 0.0: normal = -normal
		else:
			var middle := Vector3.ZERO
			for p: Vector3 in points: middle += p
			middle /= float(points.size())
			var away := middle - Vector3(inside.x, middle.y, inside.z)
			if normal.dot(away) < 0.0: normal = -normal
		var out := (xf.basis * normal).normalized()
		var frame := BlockLines.frame(out, shape_x)
		var first := -1
		var previous := -1
		for p: Vector3 in points:
			var mp := xf * p
			var index := g.add(mp, out, Vector2(mp.dot(frame[0]), -mp.dot(frame[1])), color)
			if first < 0: first = index
			elif previous >= 0: g.triangle(first, previous, index, out)
			previous = index

## Grid lines and face frames of the box builder.
class BlockLines:
	## The corners of a footprint (half extents `hx` x `hz` around cx, cz, y up) going around once; the corner i (+x+z, -x+z, -x-z, +x-z) is rounded with radius cuts[i] in two steps (three points on the arc), square when 0.
	static func outline(cx: float, cz: float, hx: float, hz: float, cuts: PackedFloat32Array, y: float) -> Array:
		var out: Array = []
		var signs := [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(-1.0, -1.0), Vector2(1.0, -1.0)]
		for i in 4:
			var s: Vector2 = signs[i]
			if cuts[i] < 0.004:
				out.append(Vector3(cx + s.x * hx, y, cz + s.y * hz))
				continue
			var cut := maxf(minf(cuts[i], minf(hx, hz) * 0.9), 0.002)
			var along_x := Vector3(cx + s.x * (hx - cut), y, cz + s.y * hz)
			var along_z := Vector3(cx + s.x * hx, y, cz + s.y * (hz - cut))
			var middle := Vector3(cx + s.x * (hx - cut * 0.2929), y, cz + s.y * (hz - cut * 0.2929)) # the arc's 45 degree point
			if i % 2 == 0:
				out.append_array([along_z, middle, along_x])
			else:
				out.append_array([along_x, middle, along_z])
		return out

	## Positions across a box side of half size `half`: the two edges and `segments` lines into each rounded edge; `centre` adds the middle (so a distance to the nearest edge
	## interpolates exactly, Batch.box `edge_data`).
	static func of(half: float, r: float, segments: int, centre := false) -> PackedFloat32Array:
		var out := PackedFloat32Array([-half])
		if r > 0.0:
			for k in range(1, segments + 1): out.append(-half + r * float(k) / segments)
		if centre: out.append(0.0)
		if r > 0.0:
			for k in range(segments, 0, -1): out.append(half - r * float(k) / segments)
		out.append(half)
		return out

	## [u axis, v axis] in a face: tops follow the shape's own x axis, sides stand upright (v = up).
	static func frame(normal: Vector3, shape_x: Vector3) -> Array:
		if absf(normal.y) >= TOP_Y:
			var u := shape_x - normal * shape_x.dot(normal)
			if u.length_squared() < 1e-6: u = Vector3.RIGHT
			u = u.normalized()
			return [u, normal.cross(u).normalized()]
		var v := (Vector3.UP - normal * normal.y).normalized()
		return [v.cross(normal).normalized(), v]
