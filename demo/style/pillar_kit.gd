extends RefCounted
## Pillars and columns of the blocks of a `world: daylight` level (levels 29 and 30, style/race_surfaces.gd) and the lobby yard, in the candy look: a stack of PILLOW segments (rounded boxes, glossy
## vinyl in flat colours, a bulge at every joint, like a stack of inflatable rings), a pachinko-pillar silhouette. Plain geometry in the level's one merged mesh
## (style/real_look.gd `draw_level`) with the vertex colours of the surface tone "stone" (style/candy_surface.gdshader, use_vertex_color); nothing here touches collision.
##   pillar    a tall box (footprint 1.5 to 6 m, at least twice as high as wide, no tone or "stone"): amber (A) and white segments, alternating
##   plain     tone "stone_plain": any tall box up to 14 m long (the gate rows of level 32): purple (S) and white segments
##   post      a slim (up to 1 m) tall frame-tone box (a gantry post): one S-coloured column of segments
## `column` is the entry for anything else that wants a column (the lobby yard's supports and sign pylons).
## Entry for the platform kit (style/block_kit.gd): `dress(batch, shape_node, xf, tone, lift, floor_y) -> bool`: true when the shape was drawn here, false for any other shape.
## `chevron_mesh` is the one shared mesh of a raised belt chevron (style/block_mesh.gd Batch.belt lays them, style/belt_look.gdshader scrolls them).
const RaceSurfaces := preload("res://style/race_surfaces.gd")
const CandyCourse := preload("res://style/candy_course.gd")
const TONE := "stone"
const PLAIN := "stone_plain"   ## a tall box (at least 1.5 times as high as its short side, up to 14 m long) in a column of segments (the gate rows of level 32)
const MIN_FOOT := 1.5          ## m: a pillar is at least this wide ...
const MAX_FOOT := 6.0          ## ... and at most this wide,
const SLENDER := 2.0           ## ... and this many times higher than its longer side
const POST_FOOT := 1.0         ## m: a frame-tone post is this wide at most ...
const POST_HEIGHT := 5.0       ## ... and this tall at least
const POST_TOP_CUT := 0.15    ## m: a frame post is drawn this much shorter than its collision (its top hides under the beam it carries)
const SEGMENT := 1.6           ## m: about as high as one pillow segment is (a whole number of them fits the column)
const SEGMENT_ROUND := 0.32    ## m: the rounding of a segment's edges (at most 0.45 of its short side or height)
const SEGMENT_STEPS := 4
const INSET := 0.02            ## m: a segment's face stands this far inside the collision box
## Belt chevrons
const BELT_PROUD := 0.07       ## m: a belt chevron stands this far over the deck
const BELT_SINK := 0.01        ## m: its foot starts this far under the deck, so no bevel edge lies in the deck's plane
const BELT_SLOPE := 0.9        ## m back per m out from the middle (the arms trail)
const BELT_STROKE := 0.5       ## m: the thickness of a chevron along the flow
const BELT_REACH := 0.8        ## m out from the middle that the arms reach (at most)
const BELT_SPAN := 1.4         ## m: the longest a chevron stands along the flow (arms trailing plus stroke), the shader's wrap margin
const BELT_PERIOD := 2.0       ## m from one chevron to the next along the flow (the shader's PERIOD)

static var _cache := {}

## Whether a box of `size` and surface `tone` is a pillar or a post (see the header).
static func is_pillar(size: Vector3, tone: String) -> bool:
	var long_side := maxf(size.x, size.z)
	var short_side := minf(size.x, size.z)
	if tone == "" or tone == TONE: return short_side >= MIN_FOOT and long_side <= MAX_FOOT and size.y >= SLENDER * long_side
	if tone == PLAIN: return long_side <= 14.0 and size.y >= 1.5 * short_side
	if tone == "frame": return long_side <= POST_FOOT and size.y >= POST_HEIGHT
	return false

## Draws the shape as a column of pillow segments into `batch` (style/block_mesh.gd Batch; `xf` places the box in the batch's space, `lift` raises it) when it is a pillar or a post. True when it did.
## `floor_y` (batch space, NAN = none): the top of the platform the pillar stands in (BlockKit solids.floor_top): the column stops there (sunk 2 cm into the floor).
static func dress(batch: Variant, shape_node: CollisionShape3D, xf: Transform3D, tone: String, lift: float, floor_y := NAN) -> bool:
	var box := shape_node.shape as BoxShape3D
	if box == null or not is_pillar(box.size, tone): return false
	var placed := xf
	placed.origin.y += lift
	var c := CandyCourse.scheme()
	var first: Color = (c.s as Dictionary).main if tone == "frame" or tone == PLAIN else (c.a as Dictionary).main
	var second: Color = first if tone == "frame" else (c.white as Color)
	var bottom := -box.size.y * 0.5
	if not is_nan(floor_y): bottom = clampf(floor_y - placed.origin.y - 0.02, bottom, box.size.y * 0.5 - SEGMENT * 0.5)
	var size := box.size
	if tone == "frame": # a gantry post carries a beam: it stops under the beam's top (the beam is a little lower than the post's collision), so its top never stands over the beam like an ear
		size.y -= POST_TOP_CUT
		placed.origin.y -= POST_TOP_CUT * 0.5
		bottom = maxf(bottom + POST_TOP_CUT * 0.5, -size.y * 0.5)
	column(batch, placed, size, bottom, first, second)
	return true

## A column of pillow segments in `batch`: the box `size` placed by `xf`, from `bottom` (box space, -size.y / 2 for the whole box) up to its top, `first` and `second` (sRGB) alternating from the top
## down. The segments are about SEGMENT m high, a whole number of them; each is a rounded box with a bulge, the joints between them are the pinches of an inflatable stack.
static func column(batch: Variant, xf: Transform3D, size: Vector3, bottom: float, first: Color, second: Color) -> void:
	var half := size * 0.5
	var span := half.y - bottom
	var count := maxi(1, roundi(span / SEGMENT))
	var height := span / float(count)
	var keys := RaceSurfaces.keys(TONE, 1)
	var wide := Vector3(maxf(size.x - 2.0 * INSET, 0.1), height, maxf(size.z - 2.0 * INSET, 0.1))
	var round := minf(SEGMENT_ROUND, minf(minf(wide.x, wide.z) * 0.45, height * 0.45))
	for k in count:
		var top := half.y - float(k) * height
		var segment := Transform3D(xf.basis, xf * Vector3(0.0, top - height * 0.5, 0.0))
		batch.box(segment, wide, round, SEGMENT_STEPS, keys[0], keys[1], first if k % 2 == 0 else second)

## A support column of the lobby yard (deck pillars, the sign pylons and piers): `column` in the S tone and white.
static func support(batch: Variant, xf: Transform3D, size: Vector3, bottom: float) -> void:
	var c := CandyCourse.scheme()
	column(batch, xf, size, bottom, (c.s as Dictionary).main, c.white as Color)

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Belt chevrons
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## The shared mesh of one raised belt chevron whose arms reach `reach` m out from its middle: {pos: Vector3 (x along the flow, behind the apex negative; y across; z height), role, tri: indices}.
## Roles: 0 the bevel, 2 the top face (cached by reach).
static func chevron_mesh(reach: float) -> Dictionary:
	var key := "chevron:%.3f" % reach
	if _cache.has(key): return _cache[key]
	var back := reach * BELT_SLOPE
	var outline := PackedVector2Array([Vector2(-back, -reach), Vector2(0.0, 0.0), Vector2(-back, reach), Vector2(-back - BELT_STROKE, reach), Vector2(-BELT_STROKE, 0.0), Vector2(-back - BELT_STROKE, -reach)])
	var made := extrude(_rounded(outline, 0.09, 3), 0.0, BELT_PROUD, 0.03, 0.0)
	_cache[key] = made
	return made

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# Relief geometry
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## A raised, bevelled shape in a plane: `outline` (metres in x, y) stands on z = `base` and rises `height` to a flat top, its sides sloped inward by `bevel`; with `outline` > 0 the top
## carries a flat ring of that width around the face (role 1: a cream outline), else the whole top is the face. Returns {pos, nrm: Vector3 (flat per facet), role (0 slope, 1 ring, 2 face), tri:
## PackedInt32Array} with vertices of their own per facet, triangles wound counter-clockwise seen from +z.
static func extrude(shape: PackedVector2Array, base: float, height: float, bevel: float, ring: float) -> Dictionary:
	var p0 := shape
	if Geometry2D.is_polygon_clockwise(p0):
		p0 = PackedVector2Array()
		for k in range(shape.size() - 1, -1, -1): p0.append(shape[k])
	var top := base + height
	var r := minf(bevel * 1.5, height * 0.55)
	# the rounded edge in two steps: a vertical wall up to top - r, then two facets of a quarter circle (insets 0.29 r and r)
	var profile: Array = [[0.0, base], [0.0, top - r], [r * (1.0 - cos(PI * 0.25)), top - r + r * sin(PI * 0.25)], [r, top]]
	var rings: Array[PackedVector2Array] = []
	for step: Array in profile: rings.append(p0 if float(step[0]) == 0.0 else _shrink(p0, float(step[0])))
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var role := PackedInt32Array()
	var tri := PackedInt32Array()
	var count := p0.size()
	for level in profile.size() - 1:
		var lower: PackedVector2Array = rings[level]
		var upper: PackedVector2Array = rings[level + 1]
		var z0: float = profile[level][1]
		var z1: float = profile[level + 1][1]
		for i in count:
			var j := (i + 1) % count
			var a := Vector3(lower[i].x, lower[i].y, z0)
			var b := Vector3(lower[j].x, lower[j].y, z0)
			var c := Vector3(upper[j].x, upper[j].y, z1)
			var d := Vector3(upper[i].x, upper[i].y, z1)
			var n := (b - a).cross(d - a).normalized()
			_facet(pos, nrm, role, tri, [a, b, c, d], n, 0)
	var p1: PackedVector2Array = rings[rings.size() - 1]
	var face := p1
	if ring > 0.0:
		var p2 := _shrink(p1, ring)
		for i in count:
			var j := (i + 1) % count
			var a := Vector3(p1[i].x, p1[i].y, top)
			var b := Vector3(p1[j].x, p1[j].y, top)
			var c := Vector3(p2[j].x, p2[j].y, top)
			var d := Vector3(p2[i].x, p2[i].y, top)
			_facet(pos, nrm, role, tri, [a, b, c, d], Vector3.BACK, 1)
		face = p2
	var cap := Geometry2D.triangulate_polygon(face)
	var first := pos.size()
	for p in face:
		pos.append(Vector3(p.x, p.y, top))
		nrm.append(Vector3.BACK)
		role.append(2)
	for k in range(0, cap.size(), 3):
		var ia := first + cap[k]
		var ib := first + cap[k + 1]
		var ic := first + cap[k + 2]
		if (pos[ib] - pos[ia]).cross(pos[ic] - pos[ia]).z < 0.0: tri.append_array(PackedInt32Array([ia, ic, ib]))
		else: tri.append_array(PackedInt32Array([ia, ib, ic]))
	return {"pos": pos, "nrm": nrm, "role": role, "tri": tri}

static func _facet(pos: PackedVector3Array, nrm: PackedVector3Array, role: PackedInt32Array, tri: PackedInt32Array, quad: Array, normal: Vector3, kind: int) -> void:
	var first := pos.size()
	for p: Vector3 in quad:
		pos.append(p)
		nrm.append(normal)
		role.append(kind)
	for t: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = pos[first + int(t[0])]
		var b: Vector3 = pos[first + int(t[1])]
		var c: Vector3 = pos[first + int(t[2])]
		var winding := (b - a).cross(c - a)
		if winding.length_squared() < 1e-14: continue
		if winding.dot(normal) < 0.0: tri.append_array(PackedInt32Array([first + int(t[0]), first + int(t[2]), first + int(t[1])]))
		else: tri.append_array(PackedInt32Array([first + int(t[0]), first + int(t[1]), first + int(t[2])]))

## A relief mesh (`extrude`) placed by `xf` into group `g` with `colors[role]` (sRGB); `shade` multiplies them.

## `shape` (CCW) moved inward by `distance` (the largest of 1, 0.6, 0.36 or 0.22 of it that leaves a polygon that can be triangulated: a corner rounded tighter than the inset would fold over).
static func _shrink(shape: PackedVector2Array, distance: float) -> PackedVector2Array:
	var d := distance
	for attempt in 4:
		var out := _shrink_once(shape, d)
		if not Geometry2D.triangulate_polygon(out).is_empty(): return out
		d *= 0.6
	return shape

## `shape` (CCW) moved inward by `distance` at every corner (mitred, never more than 2.2 times `distance` out of line).
static func _shrink_once(shape: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := shape.size()
	for i in count:
		var prev := shape[(i + count - 1) % count]
		var here := shape[i]
		var next := shape[(i + 1) % count]
		var d1 := (here - prev).normalized()
		var d2 := (next - here).normalized()
		var n1 := Vector2(-d1.y, d1.x)
		var n2 := Vector2(-d2.y, d2.x)
		var miter := (n1 + n2) / maxf(1.0 + n1.dot(n2), 0.2)
		if miter.length() > 2.2: miter = miter.normalized() * 2.2
		out.append(here + miter * distance)
	return out

## `shape` (CCW) with every corner rounded by a curve of `steps` segments that starts `radius` (at most 45% of the edge) before the corner.
static func _rounded(shape: PackedVector2Array, radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := shape.size()
	for i in count:
		var prev := shape[(i + count - 1) % count]
		var here := shape[i]
		var next := shape[(i + 1) % count]
		var a := here + (prev - here).normalized() * minf(radius, here.distance_to(prev) * 0.45)
		var b := here + (next - here).normalized() * minf(radius, here.distance_to(next) * 0.45)
		for s in steps + 1:
			var t := float(s) / float(steps)
			out.append(a * ((1.0 - t) * (1.0 - t)) + here * (2.0 * t * (1.0 - t)) + b * (t * t))
	return out
