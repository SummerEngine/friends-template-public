extends RefCounted
## The finish deck of a race (the floor under the GOAL pad) and its railings: square hot pink posts with white globe lamps on top and two round white rails along the deck's open edges.
## The deck comes from the level's own blocks (no level file key): the static boxes whose top is the goal floor and that lie under the goal volume, with the wide floors of the
## same top that touch them (a deck laid in several boxes is one deck); its rectangle and top are what the GOAL sign (style/goal_sign.gd) is sized by and what these rails follow.
## Two kinds of railing, one look. The level's own low RIM WALLS on and next to the deck (thin static boxes that stand on the deck's floor, 0.4 to 1.75 m tall) keep their collision
## but are not drawn (level_world.gd gives them an `fx` body): the railings are drawn along them instead, so a runner is stopped by exactly what it sees. An OPEN edge of the deck (no wall,
## no floor that meets it, not where the route crosses it: 1.6 m either side) gets the same railings as a look only: no collision, a runner is never stopped by it.
## A chequered line crosses the deck at the way in (where the route enters it).
##   FinishRails.deck(blocks, goal)                   # {rect: Rect2 (x, z of the level), top: y, found: bool}
##   FinishRails.rims(blocks, deck)                   # the rim walls (block dictionaries) that are drawn as railings
##   FinishRails.build(parent, deck, blocks, route)   # the railings and the line, level space
const BlockMesh := preload("res://style/block_mesh.gd")
const CandyLook := preload("res://style/candy_look.gd")
const POST := 0.26              ## m: a post's side ...
const POST_HEIGHT := 1.05       ## ... its height over the deck
const GLOBE := 0.3             ## m: the radius of the white globe lamp on a post
const INSET := 0.75             ## m: the posts of an open edge stand this far inside the deck's edge (clear of the 0.26 m rim strip the floor look lays along it)
const FOOT_LIFT := 0.036        ## m: the foot of a post on a rim wall's middle line over the deck's top: it may stand on a rim piece of the floor look (0.045 to 0.05 m high), 2 cm sunk into it
const FOOT_TILE := 0.0          ## m: the foot of a post of an open edge: INSET keeps it clear of the rim, so it stands in the tiles (or the joint strip, as high as the tiles) and is planted in them
const SPACING := 2.2            ## m: the longest gap between two posts
const RAIL_LOW := 0.42
const RAIL_HIGH := 0.84
const RAIL_RADIUS := 0.06
const MIN_RUN := 1.0            ## m: a stretch of open edge shorter than this gets no rails
const WALL_HEIGHT := 0.4
const WALL_TALL := 1.75
const WALL_THIN := 1.0          ## m: a rim wall is at most this wide
const RIM_NEAR := 16.0          ## m: the rim walls this near the deck (gap between their footprints) are railings
const LINE_ROWS := 2
const LINE_SQUARE := 0.6
const LINE_LIGHT := CandyLook.PROP_WHITE
const LINE_DARK := CandyLook.PROP_PURPLE_DEEP
const ROUTE_GAP := 1.6
const NEAR := 6.0               ## m: a floor farther than this from the goal volume is not part of the deck
const WIDE := 2.0               ## m: a floor must be this wide both ways to join the deck
const POST_COLOR := CandyLook.PROP_PINK
const CAP_COLOR := CandyLook.PROP_WHITE
const RAIL_COLOR := CandyLook.PROP_WHITE
const SIDES := 8

static var _material: StandardMaterial3D

## The deck under `goal` ({p, size, yaw}, level space) among `blocks`.
static func deck(blocks: Array, goal: Dictionary) -> Dictionary:
	var size: Vector3 = goal.size
	var top: float = (goal.p as Vector3).y - size.y * 0.5
	var turned := Basis(Vector3.UP, float(goal.yaw))
	var half := Vector2(absf(turned.x.x) * size.x + absf(turned.z.x) * size.z, absf(turned.x.z) * size.x + absf(turned.z.z) * size.z) * 0.5
	var volume := Rect2(Vector2((goal.p as Vector3).x, (goal.p as Vector3).z) - half, half * 2.0)
	var pool: Array[Rect2] = []
	var seeds: Array[Rect2] = []
	for block: Dictionary in blocks:
		if block.k != "box" or block.hit: continue
		var box := bounds(block)
		if absf(box.end.y - top) > 0.06: continue
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if minf(footprint.size.x, footprint.size.y) < 1.0: continue
		if volume.grow(0.5).intersection(footprint).get_area() > 0.01: seeds.append(footprint)
		elif minf(footprint.size.x, footprint.size.y) >= WIDE: pool.append(footprint)
	if seeds.is_empty(): return {"rect": volume.grow(1.0), "top": top, "found": false}
	var rect := seeds[0]
	for seed in seeds: rect = rect.merge(seed)
	var grown := true
	while grown:
		grown = false
		for index in range(pool.size() - 1, -1, -1):
			var piece := pool[index]
			var touch := rect.grow(0.06).intersection(piece)
			if touch.size.x < 0.0 or touch.size.y < 0.0: continue
			# only a floor as wide as the deck along the shared edge is more deck: a narrower one is the way in
			var shared := maxf(touch.size.x, touch.size.y)
			if shared < 0.9 * (rect.size.x if touch.size.x > touch.size.y else rect.size.y): continue
			if volume.grow(NEAR).intersection(piece).get_area() <= 0.0: continue
			rect = rect.merge(piece)
			pool.remove_at(index)
			grown = true
	return {"rect": rect, "top": top, "found": true}

## The axis-aligned box round a block (its size turned by its transform).
static func bounds(block: Dictionary) -> AABB:
	var xf: Transform3D = block.xf
	var size: Vector3 = block.size
	var b := xf.basis
	var half := Vector3(
		absf(b.x.x) * size.x + absf(b.y.x) * size.y + absf(b.z.x) * size.z,
		absf(b.x.y) * size.x + absf(b.y.y) * size.y + absf(b.z.y) * size.z,
		absf(b.x.z) * size.x + absf(b.y.z) * size.y + absf(b.z.z) * size.z) * 0.5
	return AABB(xf.origin - half, half * 2.0)

## The rim walls of the deck: static boxes (no picture, not `hit`) at most WALL_THIN wide, WALL_HEIGHT to WALL_TALL tall and long enough for a post (1 m), standing on the deck's
## top level, within RIM_NEAR of the deck.
static func rims(blocks: Array, deck: Dictionary) -> Array:
	var found: Array = []
	var rect: Rect2 = deck.rect
	for block: Dictionary in blocks:
		if block.k != "box" or block.hit or block.slot != "": continue
		var box := bounds(block)
		if absf(box.position.y - float(deck.top)) > 0.1 or box.size.y < WALL_HEIGHT or box.size.y > WALL_TALL: continue
		if minf(box.size.x, box.size.z) > WALL_THIN or maxf(box.size.x, box.size.z) < 1.0: continue
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		var gap := Vector2(maxf(maxf(rect.position.x - footprint.end.x, footprint.position.x - rect.end.x), 0.0), maxf(maxf(rect.position.y - footprint.end.y, footprint.position.y - rect.end.y), 0.0))
		if gap.length() <= RIM_NEAR: found.append(block)
	return found

## Builds the railings of `deck` into `parent` (level space).
static func build(parent: Node3D, deck: Dictionary, blocks: Array, route: PackedVector3Array) -> void:
	var rect: Rect2 = deck.rect
	var top: float = deck.top
	var batch := BlockMesh.Batch.new()
	var rails := batch.group("rail")
	var placed := []
	# the four edges: [axis along it (0 x, 1 z), the fixed coordinate, outward sign]
	var edges: Array = [[0, rect.position.y, -1.0], [0, rect.end.y, 1.0], [1, rect.position.x, -1.0], [1, rect.end.x, 1.0]]
	for edge: Array in edges:
		var axis: int = edge[0]
		var fixed: float = edge[1]
		var outward: float = edge[2]
		var low: float = rect.position[axis]
		var high: float = rect.end[axis]
		var shut := _shut(blocks, deck, axis, fixed, outward, route)
		for run: Vector2 in _open(low, high, shut):
			if run.y - run.x < MIN_RUN: continue
			var from := run.x + (INSET if run.x <= low + 0.01 else 0.0)
			var to := run.y - (INSET if run.y >= high - 0.01 else 0.0)
			if to - from < 0.3: continue
			var count := int(ceil((to - from) / SPACING))
			var line := fixed - outward * INSET
			for step in count + 1:
				var at := from + (to - from) * float(step) / float(count)
				var spot := Vector2(at, line) if axis == 0 else Vector2(line, at)
				_post(batch, Vector3(at if axis == 0 else line, top, line if axis == 0 else at), placed, FOOT_TILE)
			for height: float in [RAIL_LOW, RAIL_HIGH]:
				var a := Vector3(from if axis == 0 else line, top + FOOT_TILE + height, line if axis == 0 else from)
				var b := Vector3(to if axis == 0 else line, top + FOOT_TILE + height, line if axis == 0 else to)
				_tube(rails, a, b, RAIL_RADIUS, RAIL_COLOR)
	for wall: Dictionary in rims(blocks, deck): _wall_rails(batch, rails, bounds(wall), top, placed)
	_line(batch, deck, blocks, route)
	var mesh := batch.commit({"post": _paint(), "rail": _paint(), "light": _paint(), "dark": _paint()})
	if mesh == null: return
	var holder := MeshInstance3D.new()
	holder.name = "FinishRails"
	holder.mesh = mesh
	parent.add_child(holder)

## Railings along a rim wall's long axis, on its middle line.
static func _wall_rails(batch: BlockMesh.Batch, rails: BlockMesh.Group, box: AABB, top: float, placed: Array) -> void:
	var along_x := box.size.x >= box.size.z
	var length := box.size.x if along_x else box.size.z
	var middle := box.get_center()
	var from := -length * 0.5 + POST * 0.5
	var to := length * 0.5 - POST * 0.5
	var count := maxi(int(ceil((to - from) / SPACING)), 1)
	for step in count + 1:
		var at := from + (to - from) * float(step) / float(count)
		var foot := Vector3(middle.x + (at if along_x else 0.0), top, middle.z + (0.0 if along_x else at))
		_post(batch, foot, placed)
	for height: float in [RAIL_LOW, RAIL_HIGH]:
		var a := Vector3(middle.x + (from if along_x else 0.0), top + FOOT_LIFT + height, middle.z + (0.0 if along_x else from))
		var b := Vector3(middle.x + (to if along_x else 0.0), top + FOOT_LIFT + height, middle.z + (0.0 if along_x else to))
		_tube(rails, a, b, RAIL_RADIUS, RAIL_COLOR)

## One post (a square shaft with an orange cap) standing at `foot`; a spot already taken (within 0.3 m) gets none.
static func _post(batch: BlockMesh.Batch, foot: Vector3, placed: Array, lift := FOOT_LIFT) -> void:
	for other: Vector3 in placed:
		if Vector2(other.x - foot.x, other.z - foot.z).length() < 0.6: return
	placed.append(foot)
	foot.y += lift
	batch.box(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, POST_HEIGHT * 0.5 - 0.01, 0.0)), Vector3(POST, POST_HEIGHT + 0.02, POST), 0.04, 2, "post", "post", POST_COLOR)
	batch.lathe(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, POST_HEIGHT + GLOBE * 0.6, 0.0)), GLOBE, 0.0, 0.0, "post", "post", CAP_COLOR)

## The chequered line across the deck at the way in: where the route first crosses one of its edges, as wide as the floor that meets the edge there (else 8 m), two rows of squares
## laid flat just inside the edge.
static func _line(batch: BlockMesh.Batch, deck: Dictionary, blocks: Array, route: PackedVector3Array) -> void:
	var rect: Rect2 = deck.rect
	var top: float = deck.top
	var edges: Array = [[0, rect.position.y, -1.0], [0, rect.end.y, 1.0], [1, rect.position.x, -1.0], [1, rect.end.x, 1.0]]
	for index in route.size() - 1:
		for edge: Array in edges:
			var axis: int = edge[0]
			var fixed: float = edge[1]
			var across := 1 - axis
			var p := route[index]
			var q := route[index + 1]
			var pa := p.x if across == 0 else p.z
			var qa := q.x if across == 0 else q.z
			# a crossing from outside to inside
			if (pa - fixed) * float(edge[2]) < 0.0 or (qa - fixed) * float(edge[2]) > 0.0 or absf(pa - qa) < 1e-6: continue
			var s := (fixed - pa) / (qa - pa)
			if s < 0.0 or s > 1.0 or absf(lerpf(p.y, q.y, s) - top) > 1.0: continue
			var along := lerpf(p.x if axis == 0 else p.z, q.x if axis == 0 else q.z, s)
			if along < rect.position[axis] or along > rect.end[axis]: continue
			var span := Vector2(along - 4.0, along + 4.0)
			for block: Dictionary in blocks:
				if block.hit: continue
				var box := bounds(block)
				var near := (box.position.z if across == 1 else box.position.x)
				var far := (box.end.z if across == 1 else box.end.x)
				var low := box.position.x if axis == 0 else box.position.z
				var high := box.end.x if axis == 0 else box.end.z
				if absf((near if float(edge[2]) > 0.0 else far) - fixed) <= 0.12 and low <= along and high >= along and box.end.y >= top - 0.3 and box.position.y <= top + 0.3:
					span = Vector2(low, high)
			span = Vector2(maxf(span.x, rect.position[axis]), minf(span.y, rect.end[axis]))
			var count := maxi(int(round((span.y - span.x) / LINE_SQUARE)), 1)
			var size := (span.y - span.x) / float(count)
			var inward := -float(edge[2])
			for column in count:
				for row in LINE_ROWS:
					var along_low := span.x + size * float(column)
					var depth_low := fixed + inward * (0.35 + LINE_SQUARE * float(row))
					var depth_high := depth_low + inward * LINE_SQUARE
					var key := "light" if (column + row) % 2 == 0 else "dark"
					var group := batch.group(key)
					var color := LINE_LIGHT if key == "light" else LINE_DARK
					var corners: Array[Vector3] = []
					for corner: Vector2 in [Vector2(along_low, depth_low), Vector2(along_low + size, depth_low), Vector2(along_low + size, depth_high), Vector2(along_low, depth_high)]:
						corners.append(Vector3(corner.x if axis == 0 else corner.y, top + 0.014, corner.y if axis == 0 else corner.x))
					var ids := PackedInt32Array()
					for corner in corners: ids.append(group.add(corner, Vector3.UP, Vector2.ZERO, color))
					group.quad(ids[0], ids[1], ids[2], ids[3], Vector3.UP)
			return

## The stretches of one edge that are shut (as [low, high] along the edge): a wall on the deck at the edge, a floor that meets the edge, the route crossing it.
static func _shut(blocks: Array, deck: Dictionary, axis: int, fixed: float, outward: float, route: PackedVector3Array) -> Array[Vector2]:
	var rect: Rect2 = deck.rect
	var top: float = deck.top
	var shut: Array[Vector2] = []
	var across := 1 - axis
	for block: Dictionary in blocks:
		if block.hit: continue
		var box := bounds(block)
		var near := box.position.z if across == 1 else box.position.x
		var far := box.end.z if across == 1 else box.end.x
		var length_low := box.position.x if axis == 0 else box.position.z
		var length_high := box.end.x if axis == 0 else box.end.z
		var inside_deck := Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersection(rect.grow(-0.05)).get_area() > 0.01
		if length_high < (rect.position[axis]) or length_low > rect.end[axis]: continue
		var thin := far - near <= 1.0
		if block.k == "box" and inside_deck and thin and box.position.y >= top - 0.1 and box.position.y <= top + 0.35 and box.size.y >= WALL_HEIGHT:
			# a wall on the deck whose outer face is the edge
			if (absf(far - fixed) <= 0.12) if outward > 0.0 else (absf(near - fixed) <= 0.12): shut.append(Vector2(length_low - 0.1, length_high + 0.1))
		elif not inside_deck and box.end.y >= top - 0.3 and box.position.y <= top + 0.3:
			# a floor or ramp that meets the edge from outside
			if (absf(near - fixed) <= 0.12) if outward > 0.0 else (absf(far - fixed) <= 0.12): shut.append(Vector2(length_low, length_high))
	for index in route.size() - 1:
		var p := route[index]
		var q := route[index + 1]
		var pa := p.x if across == 0 else p.z
		var qa := q.x if across == 0 else q.z
		if (pa - fixed) * (qa - fixed) > 0.0 or absf(pa - qa) < 1e-6: continue
		var s := (fixed - pa) / (qa - pa)
		var along := lerpf(p.x if axis == 0 else p.z, q.x if axis == 0 else q.z, s)
		if absf(lerpf(p.y, q.y, s) - top) <= 2.0: shut.append(Vector2(along - ROUTE_GAP, along + ROUTE_GAP))
	return shut

## [low, high] minus the shut stretches: what remains open, in order.
static func _open(low: float, high: float, shut: Array[Vector2]) -> Array[Vector2]:
	shut.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var open: Array[Vector2] = []
	var at := low
	for gap in shut:
		if gap.x > at: open.append(Vector2(at, minf(gap.x, high)))
		at = maxf(at, gap.y)
		if at >= high: break
	if at < high: open.append(Vector2(at, high))
	return open

## A closed round bar from `a` to `b` (sealed by a cap at each end), in the group's own colour.
static func _tube(group: BlockMesh.Group, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var along := (b - a).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var up := side.cross(along).normalized()
	var rings: Array[PackedInt32Array] = []
	for end: Vector3 in [a, b]:
		var ring := PackedInt32Array()
		for step in SIDES:
			var angle := TAU * float(step) / float(SIDES)
			var out := side * cos(angle) + up * sin(angle)
			ring.append(group.add(end + out * radius, out, Vector2.ZERO, color))
		rings.append(ring)
	for step in SIDES:
		var next := (step + 1) % SIDES
		group.quad(rings[0][step], rings[0][next], rings[1][next], rings[1][step], group.n[rings[0][step]])
	for index in 2:
		var direction := -along if index == 0 else along
		var centre := group.add(a if index == 0 else b, direction, Vector2.ZERO, color)
		var cap := PackedInt32Array()
		for step in SIDES:
			cap.append(group.add(group.v[rings[index][step]], direction, Vector2.ZERO, color))
		for step in SIDES: group.triangle(centre, cap[step], cap[(step + 1) % SIDES], direction)

static func _paint() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = CandyLook.ROUGH_PLASTIC
		_material.metallic = 0.0
	return _material
