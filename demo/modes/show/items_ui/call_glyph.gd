extends RefCounted
## The call item's drawing kit (call_view.gd, call_window.gd): the handset glyph (an arched bar with a cup at each end), drawn on a canvas (the item pill's icon, the window's buttons) and
## built as flat camera-facing meshes (the shot and the phone over a ringing runner's head). Static helpers only; every shape is plain geometry made in code.
const BLUE := Color("3d7bff")
const CORE := Color("031141")
const LIGHT := Color("e9f5fe")
const RED := Color("e5484d")
const RED_DEEP := Color("a9232c")

static var _parts: Array = []
static var _halo: Texture2D

## The handset as polygons around the origin, within radius 1, y down: an arched bar with a rounded cup hanging from each end (the glyph of a phone call).
static func handset_parts() -> Array:
	if not _parts.is_empty(): return _parts
	var centre := Vector2(0.0, 1.0) # of the circle the bar's arc is part of
	var radius := 1.35
	var reach := 0.66 # rad of the arc each side of the top
	var bar_half := 0.15
	var steps := 16
	var bar := PackedVector2Array()
	for index in steps + 1:
		var a := -reach + 2.0 * reach * float(index) / float(steps)
		bar.append(centre + Vector2(sin(a), -cos(a)) * (radius + bar_half))
	for index in range(steps, -1, -1):
		var a2 := -reach + 2.0 * reach * float(index) / float(steps)
		bar.append(centre + Vector2(sin(a2), -cos(a2)) * (radius - bar_half))
	var parts: Array = [bar]
	for side in [-1.0, 1.0]:
		var end := centre + Vector2(sin(reach * side), -cos(reach * side)) * radius
		var inward := (centre - end).normalized()
		parts.append(_rounded_rect(end + inward * 0.17, Vector2(0.54, 0.7), 0.18, inward.angle() - PI * 0.5))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for part: PackedVector2Array in parts:
		for p in part:
			low = low.min(p)
			high = high.max(p)
	var middle := (low + high) * 0.5
	var extent := maxf(high.x - low.x, high.y - low.y) * 0.5
	var scaled_parts: Array = []
	for part: PackedVector2Array in parts:
		var scaled := PackedVector2Array()
		for p in part: scaled.append((p - middle) / extent)
		scaled_parts.append(scaled)
	_parts = scaled_parts
	return _parts

## A rounded rectangle of `size` (x across, y along its axis) about `centre`, its y axis turned by `angle`.
static func _rounded_rect(centre: Vector2, size: Vector2, corner: float, angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var inner := size * 0.5 - Vector2(corner, corner)
	for index in 4:
		var around := Vector2(1.0 if index in [0, 3] else -1.0, 1.0 if index < 2 else -1.0)
		var turn: float = float(index) * PI * 0.5
		for step in 6:
			var a: float = turn + (PI * 0.5) * float(step) / 5.0
			points.append(centre + (inner * around + Vector2(cos(a), sin(a)) * corner).rotated(angle))
	return points

## The handset drawn on `ci` centred on `c`, radius `r`, turned by `angle` rad.
static func draw_handset(ci: CanvasItem, c: Vector2, r: float, color: Color, angle := 0.0) -> void:
	for part: PackedVector2Array in handset_parts():
		var points := PackedVector2Array()
		for p in part: points.append(c + p.rotated(angle) * r)
		ci.draw_colored_polygon(points, color)
		var rim := points.duplicate()
		rim.append(points[0])
		ci.draw_polyline(rim, color, maxf(r * 0.03, 1.0), true)

## Ring waves over the handset: `count` arcs fanned upward from `c`, the first at radius `r0`, each `step` further out; with `lit` >= 0 only the first `lit` + 1 are bright.
static func draw_waves(ci: CanvasItem, c: Vector2, r0: float, step: float, width: float, color: Color, count := 2, lit := -1) -> void:
	for index in count:
		var alpha := 1.0 if lit < 0 else (1.0 if index <= lit else 0.25)
		ci.draw_arc(c, r0 + step * float(index), deg_to_rad(-140.0), deg_to_rad(-40.0), 18, Color(color, color.a * alpha), width, true)

# ------------------------------------------------------------------ flat meshes that face the camera

## A disc, or a ring when `r_in` > 0, from angle `a0` to `a1` (a full turn by default), flat in the XY plane at depth `z`.
static func ring_mesh(r_in: float, r_out: float, z := 0.0, a0 := 0.0, a1 := TAU, segments := 36) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in segments + 1:
		var a := lerpf(a0, a1, float(index) / float(segments))
		var dir := Vector2(cos(a), sin(a))
		vertices.append(Vector3(dir.x * r_out, dir.y * r_out, z))
		vertices.append(Vector3(dir.x * r_in, dir.y * r_in, z))
		if index > 0:
			var at := (index - 1) * 2
			indices.append_array(PackedInt32Array([at, at + 1, at + 2, at + 1, at + 3, at + 2]))
	return _mesh(vertices, indices)

## The handset polygons scaled to radius `r`, at depth `z`, as one mesh.
static func handset_mesh(r: float, z := 0.0) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for part: PackedVector2Array in handset_parts():
		var winding := PackedVector2Array()
		for p in part: winding.append(Vector2(p.x, -p.y)) # the canvas has y down, the world y up
		var base := vertices.size()
		for p in winding: vertices.append(Vector3(p.x * r, p.y * r, z))
		for index in Geometry2D.triangulate_polygon(winding): indices.append(base + index)
	return _mesh(vertices, indices)

static func _mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3(0.0, 0.0, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## A flat unlit material that faces the camera (`additive` for glows).
static func material(color: Color, additive := false, texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = false
		mat.disable_receive_shadows = true
	if texture != null: mat.albedo_texture = texture
	return mat

## A soft round glow texture (white in the middle, clear at the rim).
static func halo() -> Texture2D:
	if _halo != null: return _halo
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_halo = texture
	return _halo

## A mesh instance with `mesh` and `material`, in the node `parent`.
static func piece(parent: Node3D, mesh: Mesh, mat: Material, priority := 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	mat.render_priority = priority
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
