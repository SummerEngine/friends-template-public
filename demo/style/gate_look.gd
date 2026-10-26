extends RefCounted
## The doorway frames of the gate walls of a `world: daylight` level (tools/gate_piece.py, docs/level-format.md "Gate walls"), drawn on top of what style/real_look.gd made of the blocks. The
## frame's collision is blocks of tone `arch` (two piers, a beam, and a thin CORE over the opening that marks the frame: the only `arch` box with a 0.25 m side; real_look.gd draws none of
## them). The cores of one row whose openings are one pier pair (1.0 m) apart belong to the same frame: this builds ONE rounded-arch frame for every such run of cores as one mesh: a teal
## slab with a rounded outer outline (only the ends of the run and its top corners have edges; the joints between two openings are one flat mullion, no seam, no slit), a window per core
## that is twice the opening's height (the door slides up into its top half, in front of the core), a chamfer on the outer edge, an amber lip round every window on both faces and along its
## reveals, and the core's dark field on both sides. One surface for the level (the kit's vertex-colour material, style/block_kit.gd), made once the level is drawn. Look only: no collision, no
## gameplay; `dress(level_root)` is called after the collision look (style/race_hazard_looks.gd `dress`). The eyes on top are plain `eye` cylinders (style/race_surfaces.gd).
const BlockMesh := preload("res://style/block_mesh.gd")
const BlockKit := preload("res://style/block_kit.gd")
const OUTLINE := 0.5         ## m: width of the ring (piers and beam)
const HALF_DEPTH := 0.76     ## m: half the frame's depth (the wall is 1 m deep, the collision of the frame 1.5 m: the look stands 1 cm deeper, so no face shares a plane with a block edge on the 0.25 m grid)
const CORNER := 0.5          ## m: radius of the outer top corners
const CandyLook := preload("res://style/candy_look.gd")
const CHAMFER := 0.24         ## m: a fat padded edge (door frames are rounded by about this much; one bevel, smooth normals)
const LIP := 0.12            ## m: width of the amber lip round the window
const STEPS := 8
const CORE_THICK := 0.25
const SLOT := 0.02           ## m: the window is this much narrower and lower than the opening (the door's edges slide 2 cm into the frame: never a shared plane), and the frame's outside this much wider than its piers (it sinks into the wall at its ends)
const JOIN := 2.0 * OUTLINE + 0.01   ## m: two openings in a row at most this far apart share one frame (their piers touch: tools/gate_piece.py keeps them 2 * OUTLINE apart at the least)
const FRAME := CandyLook.PROP_PURPLE
const FRAME_EDGE := CandyLook.PROP_PURPLE_LIGHT
const LIP_COLOUR := CandyLook.PROP_AMBER_LIGHT
const FIELD := CandyLook.PROP_PURPLE_LIGHT

## Dresses the frames of the drawn level under `level_root`.
static func dress(level_root: Node3D) -> void:
	var to_level := level_root.global_transform.affine_inverse()
	var cores: Array[Dictionary] = []
	for node: Node in level_root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null or not shape_node.shape is BoxShape3D or str(shape_node.get_meta("tone", "")) != "arch": continue
		var size := (shape_node.shape as BoxShape3D).size
		var across_x := absf(size.z - CORE_THICK) < 0.01 and size.x > CORE_THICK + 0.01
		var across_z := absf(size.x - CORE_THICK) < 0.01 and size.z > CORE_THICK + 0.01
		if not (across_x or across_z): continue
		var at := (to_level * shape_node.global_transform).origin
		cores.append({"x": across_x, "at": Vector3(at.x, at.y - 1.5 * size.y, at.z), "c": at.x if across_x else at.z, "row": at.z if across_x else at.x, "width": size.x if across_x else size.z, "high": size.y})
	if cores.is_empty(): return
	cores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:   # by row (axis, depth, floor, height), then along the row
		if a.x != b.x: return bool(a.x)
		if absf(a.row - b.row) > 0.01: return a.row < b.row
		if absf(a.at.y - b.at.y) > 0.01: return a.at.y < b.at.y
		if absf(a.high - b.high) > 0.01: return a.high < b.high
		return a.c < b.c)
	var batch := BlockMesh.Batch.new()
	var group := batch.group(BlockKit.KEY_TALL)
	var run: Array[Dictionary] = []
	for core: Dictionary in cores:
		if not run.is_empty() and not _joins(run[run.size() - 1], core):
			_run_frame(group, run)
			run.clear()
		run.append(core)
	_run_frame(group, run)
	var mesh := batch.commit({BlockKit.KEY_TALL: BlockKit.tall_material()})
	if mesh == null: return
	var visual := MeshInstance3D.new()
	visual.name = "GateFrames"
	visual.mesh = mesh
	level_root.add_child(visual)

## Whether core `b` (the next one along the sorted row) stands in the row of core `a` with its opening touching a's pier pair.
static func _joins(a: Dictionary, b: Dictionary) -> bool:
	if a.x != b.x or absf(a.row - b.row) > 0.01 or absf(a.at.y - b.at.y) > 0.01 or absf(a.high - b.high) > 0.01: return false
	return (b.c - b.width * 0.5) - (a.c + a.width * 0.5) <= JOIN

## One frame for a run of cores (sorted along their row, openings one pier pair apart).
static func _run_frame(g: BlockMesh.Group, run: Array[Dictionary]) -> void:
	var first := run[0]
	var last := run[run.size() - 1]
	var left: float = first.c - first.width * 0.5
	var right: float = last.c + last.width * 0.5
	var middle_c := (left + right) * 0.5
	var across := Vector3.RIGHT if first.x else Vector3.BACK
	var depth := Vector3.BACK if first.x else Vector3.RIGHT
	var windows: Array[Vector2] = []   # (centre across the frame from its middle, width) of every opening
	for core: Dictionary in run:
		windows.append(Vector2(core.c - middle_c, core.width))
	_frame(g, (first.at as Vector3) + across * (middle_c - first.c), across, depth, windows, first.high)

## One frame: `base` the floor point under the middle of the whole frame, `across` / `depth` the unit axes, `windows` (x of the opening's middle from `base`, width) of its openings, `high`
## their height.
static func _frame(g: BlockMesh.Group, base: Vector3, across: Vector3, depth: Vector3, windows: Array[Vector2], high: float) -> void:
	var half := (windows[windows.size() - 1].x + windows[windows.size() - 1].y * 0.5) - (windows[0].x - windows[0].y * 0.5)
	half *= 0.5
	var window_top := 2.0 * high
	var top := window_top + OUTLINE
	var middle := base + Vector3.UP * high
	var outer := _round(half + OUTLINE + SLOT, top, CORNER)
	var inset := _round(half + OUTLINE + SLOT - CHAMFER, top - CHAMFER, CORNER - CHAMFER)
	var hull := _round(half + LIP, window_top + LIP, 0.0)   # the lips of all the openings together: the ring is the strip from the inset outline to it
	var lips: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for w: Vector2 in windows:
		lips.append(_shift(_round(w.y * 0.5 + LIP, window_top + LIP, 0.0), w.x))
		holes.append(_shift(_round(w.y * 0.5 - SLOT, window_top - SLOT, 0.0), w.x))
	for side: float in [-1.0, 1.0]:
		var z_face := side * HALF_DEPTH
		var normal := depth * side
		_band(g, base, across, depth, middle, outer, side * (HALF_DEPTH - CHAMFER), inset, z_face, FRAME_EDGE, normal, 0)
		_band(g, base, across, depth, middle, inset, z_face, hull, z_face, FRAME, normal, 0)
		for i in windows.size():
			_band(g, base, across, depth, middle, lips[i], z_face, holes[i], z_face, LIP_COLOUR, normal, 0)
			if i + 1 < windows.size():   # the mullion between this opening and the next: one flat purple face from the floor to the top of the lips
				var u0 := windows[i].x + windows[i].y * 0.5 + LIP
				var u1 := windows[i + 1].x - windows[i + 1].y * 0.5 - LIP
				var quad: Array[Vector3] = []
				for c: Vector2 in [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, window_top + LIP), Vector2(u0, window_top + LIP)]:
					quad.append(base + across * c.x + Vector3.UP * c.y + depth * z_face)
				_triangle(g, quad[0], quad[1], quad[2], normal, FRAME)
				_triangle(g, quad[0], quad[2], quad[3], normal, FRAME)
	_band(g, base, across, depth, middle, outer, -(HALF_DEPTH - CHAMFER), outer, HALF_DEPTH - CHAMFER, FRAME, Vector3.ZERO, 1)
	for i in windows.size():
		var window_middle := middle + across * windows[i].x
		_band(g, base, across, depth, window_middle, holes[i], -HALF_DEPTH, holes[i], HALF_DEPTH, LIP_COLOUR, Vector3.ZERO, -1)
		for side: float in [-1.0, 1.0]:   # the core's field, both faces
			var z := side * CORE_THICK * 0.5
			var corners: Array[Vector3] = []
			for c: Vector2 in [Vector2(windows[i].x - windows[i].y * 0.5, high), Vector2(windows[i].x + windows[i].y * 0.5, high), Vector2(windows[i].x + windows[i].y * 0.5, window_top), Vector2(windows[i].x - windows[i].y * 0.5, window_top)]:
				corners.append(base + across * c.x + Vector3.UP * c.y + depth * z)
			_triangle(g, corners[0], corners[1], corners[2], depth * side, FIELD)
			_triangle(g, corners[0], corners[2], corners[3], depth * side, FIELD)

static func _shift(line: PackedVector2Array, dx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in line:
		out.append(Vector2(p.x + dx, p.y))
	return out

## The polyline of a rounded-top rectangle from the left foot (-half, 0) over the top to the right foot (half, 0): always 2 + 2 * (STEPS + 1) points (a radius of 0 makes the corner points coincide).
static func _round(half: float, top: float, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(-half, 0.0))
	var r := maxf(radius, 0.0)
	for k in STEPS + 1:
		var a := PI - (PI * 0.5) * float(k) / float(STEPS)
		out.append(Vector2(-half + r + r * cos(a), top - r + r * sin(a)))
	for k in STEPS + 1:
		var a := (PI * 0.5) - (PI * 0.5) * float(k) / float(STEPS)
		out.append(Vector2(half - r + r * cos(a), top - r + r * sin(a)))
	out.append(Vector2(half, 0.0))
	return out

## The strip between polyline `a` at depth `za` and polyline `b` at depth `zb`. `face` is the outward normal of a flat face (ring / lip); `mode` 1: a wall facing away from the
## frame's middle (the outer rim), -1: facing in (the window's reveals), 0: the face's own side.
static func _band(g: BlockMesh.Group, base: Vector3, across: Vector3, depth: Vector3, middle: Vector3, a: PackedVector2Array, za: float, b: PackedVector2Array, zb: float, color: Color, face: Vector3, mode: int) -> void:
	for i in a.size() - 1:
		var p0 := base + across * a[i].x + Vector3.UP * a[i].y + depth * za
		var p1 := base + across * a[i + 1].x + Vector3.UP * a[i + 1].y + depth * za
		var p2 := base + across * b[i + 1].x + Vector3.UP * b[i + 1].y + depth * zb
		var p3 := base + across * b[i].x + Vector3.UP * b[i].y + depth * zb
		var centre := (p0 + p1 + p2 + p3) * 0.25
		var hint := face
		if mode != 0: hint = (centre - middle) * float(mode)
		_triangle(g, p0, p1, p2, hint, color)
		_triangle(g, p0, p2, p3, hint, color)

static func _triangle(g: BlockMesh.Group, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12: return
	n = n.normalized()
	if n.dot(outward) < 0.0: n = -n
	var ia := g.add(a, n, Vector2.ZERO, color)
	var ib := g.add(b, n, Vector2.ZERO, color)
	var ic := g.add(c, n, Vector2.ZERO, color)
	g.triangle(ia, ib, ic, n)
