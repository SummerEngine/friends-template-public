extends RefCounted
## Where the theme bunting (the triangular pennants of style/party_backdrop.gd) may hang: ONLY on high edges. The pennants run along the top
## of a tall wall; the run's line is `wall top - LINE_DROP`. A pennant hangs there only when the line is at least `MIN_CLEAR` m above the
## highest walkable top within `REACH` m in front of that stretch of the face (so its lowest tip is above a player's head), when no solid
## covers that stretch of the face, and when it does not hang in the podium shot (`near_podium`). Stair risers and ledges lower than that therefore never wear any: their line is a step or two above the
## tread a player stands on.
## A wall whose own top is a walkway (a thick ground slab, a plateau: the route or a podium stands on it) never wears any: its line
## would hang under the floor a player walks on.
## Pure functions of the level data (no nodes): `plan(data)` lists every candidate run with its clearance, the backdrop draws the kept ones
## (`pennants`), tools/party_look_check.gd audits all show levels with the same call. Level-local space, like the level data.
const MIN_CLEAR := 3.0      ## the line's height over the highest walkable top in front of it, at least (m)
const LINE_DROP := 0.35     ## the line hangs this far under the wall's top
const REACH := 4.0          ## walkable tops this far from the face (a jump away) count
const STEP := 1.4           ## spacing of the pennants along a wall (m)
const MIN_RUN := 3          ## fewer pennants in a row are dropped (a lone triangle looks like a mistake)
const MIN_HEIGHT := 3.0     ## walls lower than this (block height) never wear bunting
const MIN_LENGTH := 6.0
const WALK_MARGIN := 1.0    ## a route point this close (on x/z) to a block's footprint, and within WALK_RISE of its top, stands on it
const WALK_RISE := 1.2
const PODIUM_REACH := 10.0  ## around a podium spot (on x/z) no pennant hangs lower than PODIUM_CLEAR over the spot's feet: the podium camera sees
const PODIUM_CLEAR := 4.6   ## the winner's crown (3.3 m over the feet) with a pennant's length (1.1 m) to spare
const COVER_GAP := 0.4      ## a solid this close to the face, reaching the line, hides that stretch of the face

## The solids a player can stand on, as world AABBs: every block, the parts of movers (over their whole travel), step tiles. Index i < blocks.size()
## is block i (so `skip` can exclude the wall itself).
static func solids(data: Dictionary) -> Array[AABB]:
	var list: Array[AABB] = []
	for block: Dictionary in data.blocks: list.append(_box_bounds(block.xf, block.size))
	for h: Dictionary in data.hazards:
		if not str(h.k) in ["slide", "lift", "spin", "blink"]: continue
		var travel: Vector3 = h.get("to", Vector3.ZERO) if str(h.k) in ["slide", "lift"] else Vector3.ZERO
		for part: Dictionary in h.parts:
			var local: Transform3D = part.xf
			var xf := Transform3D(h.base * local.basis, h.pivot + (h.base as Basis) * local.origin)
			var bounds := _box_bounds(xf, part.size)
			if str(h.k) == "spin": bounds = bounds.grow(maxf(bounds.size.x, bounds.size.z) * 0.5)
			bounds = bounds.merge(AABB(bounds.position + travel, bounds.size))
			list.append(bounds)
	if not (data.tiles as Dictionary).is_empty():
		var pitch := float(data.tiles.pitch)
		for tile: Dictionary in data.tiles.tiles:
			var top: Vector3 = tile.p
			list.append(AABB(top - Vector3(pitch * 0.5, float(data.tiles.thick), pitch * 0.5), Vector3(pitch, float(data.tiles.thick), pitch)))
	return list

## Points a player stands on, level-local feet: the densified route and the podium spots.
static func walk_points(data: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array(data.route)
	for spot: Vector3 in data.podium: points.append(spot)
	return points

## True when somebody walks on the top of `bounds` (a block's world box).
static func is_walkway(walk: PackedVector3Array, bounds: AABB) -> bool:
	for point: Vector3 in walk:
		if absf(point.y - bounds.end.y) > WALK_RISE: continue
		if point.x < bounds.position.x - WALK_MARGIN or point.x > bounds.end.x + WALK_MARGIN: continue
		if point.z < bounds.position.z - WALK_MARGIN or point.z > bounds.end.z + WALK_MARGIN: continue
		return true
	return false

## True when the pennant at `at` would hang in the podium shot: within PODIUM_REACH of a spot, lower than PODIUM_CLEAR over its feet.
static func near_podium(spots: Array, at: Vector3) -> bool:
	for spot: Vector3 in spots:
		if Vector2(at.x - spot.x, at.z - spot.z).length() < PODIUM_REACH and at.y < spot.y + PODIUM_CLEAR: return true
	return false

static func _box_bounds(xf: Transform3D, size: Vector3) -> AABB:
	var half := size * 0.5
	var reach := Vector3(absf(xf.basis.x.x) * half.x + absf(xf.basis.y.x) * half.y + absf(xf.basis.z.x) * half.z,
		absf(xf.basis.x.y) * half.x + absf(xf.basis.y.y) * half.y + absf(xf.basis.z.y) * half.z,
		absf(xf.basis.x.z) * half.x + absf(xf.basis.y.z) * half.y + absf(xf.basis.z.z) * half.z)
	return AABB(xf.origin - reach, reach * 2.0)

## How far the line at height `line_y` over the stretch of a wall face is above the highest walkable top in front of it. `face` is the middle
## of the stretch on the face (level-local, xz used), `normal` the horizontal unit vector out of the face (a Vector3 on the xz plane), `along` the
## unit vector along it, `half_length` half the stretch. Looks `REACH` m out from the face; only tops at or under the line count. `skip` is the
## index of the wall's own solid (-1 for none). Returns INF when nothing walkable lies in front (a drop), and -1.0 when a solid hides the
## stretch (it touches the face and reaches the line): the stretch gets no bunting.
static func clearance(list: Array[AABB], line_y: float, face: Vector3, normal: Vector3, along: Vector3, half_length: float, skip := -1) -> float:
	var centre := Vector2(face.x, face.z) + Vector2(normal.x, normal.z) * (REACH * 0.5)
	var a := Vector2(along.x, along.z).normalized()
	var n := Vector2(normal.x, normal.z).normalized()
	var cover_centre := Vector2(face.x, face.z) + n * (COVER_GAP * 0.5)
	var best := -INF
	for i in list.size():
		if i == skip: continue
		var solid: AABB = list[i]
		if solid.end.y >= line_y and _overlap(solid, cover_centre, a, n, half_length, COVER_GAP * 0.5): return -1.0
		if solid.end.y > line_y: continue
		if _overlap(solid, centre, a, n, half_length, REACH * 0.5): best = maxf(best, solid.end.y)
	return INF if best == -INF else line_y - best

## Separating-axis test of a solid's footprint (an axis-aligned rectangle) against the oriented rectangle `centre`, axes `a` and `n`,
## half sizes `half_a` and `half_n`. Touching does not overlap.
static func _overlap(solid: AABB, centre: Vector2, a: Vector2, n: Vector2, half_a: float, half_n: float) -> bool:
	var middle := Vector2(solid.position.x + solid.size.x * 0.5, solid.position.z + solid.size.z * 0.5)
	var half := Vector2(solid.size.x * 0.5, solid.size.z * 0.5)
	var offset := middle - centre
	if absf(offset.x) >= half.x + half_a * absf(a.x) + half_n * absf(n.x) - 0.001: return false
	if absf(offset.y) >= half.y + half_a * absf(a.y) + half_n * absf(n.y) - 0.001: return false
	if absf(offset.dot(a)) >= half_a + half.x * absf(a.x) + half.y * absf(a.y) - 0.001: return false
	if absf(offset.dot(n)) >= half_n + half.x * absf(n.x) + half.y * absf(n.y) - 0.001: return false
	return true

## Every bunting run candidate of a level: the tall upright walls, both long faces, cut into stretches of `STEP` metres, the stretches grouped
## into runs. A run: {block, k, side (-1 or 1), line_y, from, to (level-local ends on the face line), normal (a Vector3), first, count (pennants),
## clear (the smallest clearance of its stretches, INF when nothing walkable lies in front), walkway (the wall's top is walked on), kept (bool: at least MIN_RUN pennants pass)}.
## Each `stretches` entry of a run: {at (Vector3 on the face, at the line), clear, ok}.
static func plan(data: Dictionary) -> Array:
	var list := solids(data)
	var walk := walk_points(data)
	var runs: Array = []
	for index in (data.blocks as Array).size():
		var block: Dictionary = data.blocks[index]
		var size: Vector3 = block.size
		var xf: Transform3D = block.xf
		if str(block.k) == "cyl" or size.y < MIN_HEIGHT or maxf(size.x, size.z) < MIN_LENGTH or absf(xf.basis.y.y) < 0.99: continue
		var along_x := size.x >= size.z
		var length := size.x if along_x else size.z
		var thick := size.z if along_x else size.x
		var axis := xf.basis.x.normalized() if along_x else xf.basis.z.normalized()
		var normal := xf.basis.z.normalized() if along_x else xf.basis.x.normalized()
		var line_y := xf.origin.y + size.y * 0.5 - LINE_DROP
		var walkway := is_walkway(walk, list[index])
		var count := int(length / STEP)
		if count < 1: continue
		for side: float in [-1.0, 1.0]:
			var out := normal * side
			var stretches: Array = []
			for i in count:
				var along := (float(i) + 0.5) / float(count) * length - length * 0.5
				var at := xf.origin + axis * along + out * (thick * 0.5 + 0.1)
				at.y = line_y
				var face := at - out * 0.1
				var clear := clearance(list, line_y, face, out, axis, length / float(count) * 0.5, index)
				stretches.append({"at": at, "clear": clear, "ok": clear >= MIN_CLEAR and not walkway and not near_podium(data.podium, at)})
			var i := 0
			while i < count:
				var j := i
				var low := INF
				while j < count and stretches[j].ok == (stretches[i].ok):
					low = minf(low, stretches[j].clear)
					j += 1
				var part := stretches.slice(i, j)
				runs.append({"block": index, "k": str(block.k), "side": side, "line_y": line_y, "from": part[0].at, "to": part[part.size() - 1].at, "normal": out,
					"first": i, "count": j - i, "clear": low, "walkway": walkway, "kept": bool(stretches[i].ok) and j - i >= MIN_RUN, "stretches": part})
				i = j
	return runs

## The pennants to draw: [{at (Vector3, the pennant's top middle), normal}] of the kept runs, in plan order (so colours stay stable).
static func pennants(data: Dictionary) -> Array:
	var result: Array = []
	for run: Dictionary in plan(data):
		if not run.kept: continue
		for stretch: Dictionary in run.stretches: result.append({"at": stretch.at, "normal": run.normal})
	return result
