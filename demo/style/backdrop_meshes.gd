extends RefCounted
## The few low-poly bodies every backdrop piece is built from (style/backdrop.gd): box, pyramid, cone, cylinder, sphere, bird. All are
## centred on the origin with a bounding size of 1 (cylinder, cone and sphere: diameter 1), so an instance's scale is its size in metres.
## Vertices are shared and there are no normals: the shaders flat-shade from screen derivatives, and the ink outline pass pushes every vertex
## outwards along its own direction from the centre (`normalize(VERTEX)`), which keeps the hull closed on every convex body.
static var _cache := {}

static func get_mesh(kind: String) -> ArrayMesh:
	if not _cache.has(kind):
		match kind:
			"box": _cache[kind] = _box()
			"pyramid": _cache[kind] = _cone(4, PI * 0.25, 0.70710678)
			"cone": _cache[kind] = _cone(7, 0.0, 0.5)
			"cylinder": _cache[kind] = _cylinder(8)
			"sphere": _cache[kind] = _sphere(8, 5)
			"bird": _cache[kind] = _bird()
			_: push_error("backdrop mesh kind '%s' unknown" % kind)
	return _cache[kind]

## Builds a mesh from convex-shape triangles; every triangle is turned to face away from the origin (front faces are clockwise in this engine).
static func _convex(vertices: PackedVector3Array, triangles: PackedInt32Array) -> ArrayMesh:
	var indices := PackedInt32Array()
	for i in range(0, triangles.size(), 3):
		var a := vertices[triangles[i]]
		var b := vertices[triangles[i + 1]]
		var c := vertices[triangles[i + 2]]
		var outward := (a + b + c) / 3.0
		if (b - a).cross(c - a).dot(outward) > 0.0:
			indices.append_array(PackedInt32Array([triangles[i], triangles[i + 2], triangles[i + 1]]))
		else:
			indices.append_array(PackedInt32Array([triangles[i], triangles[i + 1], triangles[i + 2]]))
	return _surface(vertices, indices)

static func _surface(vertices: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-0.8, -0.8, -0.8), Vector3(1.6, 1.6, 1.6))
	return mesh

static func _box() -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in 8: vertices.append(Vector3(0.5 if i & 1 else -0.5, 0.5 if i & 2 else -0.5, 0.5 if i & 4 else -0.5))
	var quads := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	var triangles := PackedInt32Array()
	for q: Array in quads: triangles.append_array(PackedInt32Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	return _convex(vertices, triangles)

## `sides`-gonal base at y = -0.5 (corner radius `radius`, first corner at `phase`), apex at y = 0.5.
static func _cone(sides: int, phase: float, radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0.0, 0.5, 0.0), Vector3(0.0, -0.5, 0.0)])
	for i in sides:
		var angle := phase + TAU * float(i) / float(sides)
		vertices.append(Vector3(cos(angle) * radius, -0.5, sin(angle) * radius))
	var triangles := PackedInt32Array()
	for i in sides:
		var a := 2 + i
		var b := 2 + (i + 1) % sides
		triangles.append_array(PackedInt32Array([0, a, b, 1, a, b]))
	return _convex(vertices, triangles)

static func _cylinder(sides: int) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0.0, 0.5, 0.0), Vector3(0.0, -0.5, 0.0)])
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		vertices.append(Vector3(cos(angle) * 0.5, 0.5, sin(angle) * 0.5))
		vertices.append(Vector3(cos(angle) * 0.5, -0.5, sin(angle) * 0.5))
	var triangles := PackedInt32Array()
	for i in sides:
		var top := 2 + i * 2
		var next := 2 + ((i + 1) % sides) * 2
		triangles.append_array(PackedInt32Array([0, top, next, 1, top + 1, next + 1, top, top + 1, next + 1, top, next + 1, next]))
	return _convex(vertices, triangles)

static func _sphere(sectors: int, stacks: int) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0.0, 0.5, 0.0), Vector3(0.0, -0.5, 0.0)])
	for s in range(1, stacks):
		var polar := PI * float(s) / float(stacks)
		for i in sectors:
			var angle := TAU * float(i) / float(sectors)
			vertices.append(Vector3(sin(polar) * cos(angle), cos(polar), sin(polar) * sin(angle)) * 0.5)
	var triangles := PackedInt32Array()
	for i in sectors:
		var j := (i + 1) % sectors
		triangles.append_array(PackedInt32Array([0, 2 + i, 2 + j, 1, 2 + (stacks - 2) * sectors + i, 2 + (stacks - 2) * sectors + j]))
		for s in range(0, stacks - 2):
			var a := 2 + s * sectors + i
			var b := 2 + s * sectors + j
			var c := 2 + (s + 1) * sectors + i
			var d := 2 + (s + 1) * sectors + j
			triangles.append_array(PackedInt32Array([a, c, d, a, d, b]))
	return _convex(vertices, triangles)

## A chevron seen from above (nose at -z, wing tips at +-x lifted by the shader), both sides, so it shows from below as well.
static func _bird() -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0.0, 0.0, -0.5), Vector3(-0.5, 0.0, 0.35), Vector3(0.0, 0.0, 0.12), Vector3(0.5, 0.0, 0.35)])
	var indices := PackedInt32Array([0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3])
	return _surface(vertices, indices)
