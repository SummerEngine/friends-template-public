extends RefCounted
## The 3D parts of the lobby walk-in pads in the world look (client/walk_in_markers.gd builds the pads, places the text and runs the
## colours): a pad painted on the yard floor, a printed signboard on two steel posts, and the lamps over it. Lit like the room, no ink.
## Client only, no collision.
##
##   WalkInLook.pad(root, color, radius) -> {ring_material, fill_material}   # the caller sets albedo_color on both every frame
##   WalkInLook.board(root, size, at) -> Node3D                              # the board face's frame: +Z is the front, z = 0 its face
##   WalkInLook.posts(root, spread, top, z)                                  # two steel posts for a sign face the caller draws itself
##   WalkInLook.lamp(radius) -> MeshInstance3D                               # one lamp; the caller sets its albedo_color (off / a colour)
const Surfaces := preload("res://style/surfaces.gd")
const RING := 0.22          ## m, the coloured band of the pad
const RIM := 0.1            ## m, the white rim outside it (it reads on any floor)
const EDGE := 0.04          ## m, the metal edge of the board
const POST_RADIUS := 0.05
const SEGMENTS := 64

## The pad under `root`: a translucent painted fill, a white rim and the coloured ring, a few millimetres proud of the floor.
static func pad(root: Node3D, color: Color, radius: float) -> Dictionary:
	var fill_material := _paint(Color(color, 0.28), 0.6, 0.0, true)
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add(root, "Pad", _annulus(0.0, radius - RING, 0.012), fill_material)
	_add(root, "Rim", _annulus(radius - RING, radius + RIM, 0.014), _paint(Color("f4f4f2"), 0.55, 0.0, true))
	var ring_material := _paint(color, 0.5, 0.0, true)
	_add(root, "Ring", _annulus(radius - RING, radius, 0.016), ring_material)
	return {"ring_material": ring_material, "fill_material": fill_material}

## A printed signboard of `size` whose face centre is at `at` (in `root`), looking down +Z: a white face (one-sided, so a camera behind it
## sees through to its player), a thin metal edge and two steel posts down to the floor (y = 0). Returns the face's frame for the text.
static func board(root: Node3D, size: Vector2, at: Vector3) -> Node3D:
	var signage := Surfaces.signage()
	var metal := _paint(Color(str(signage.frame)), float(signage.frame_rough), float(signage.frame_metal))
	var steel := _paint(Color(str(signage.post)), 0.4, float(signage.post_metal))
	var face := Node3D.new()
	face.name = "Face"
	face.position = at
	root.add_child(face)
	var quad := QuadMesh.new()
	quad.size = size
	var white := _paint(Color(str(signage.board)), 0.5)
	white.cull_mode = BaseMaterial3D.CULL_BACK
	_add(face, "Board", quad, white)
	for bar: Array in [[Vector3(0.0, (size.y + EDGE) * 0.5, 0.0), Vector3(size.x + EDGE * 2.0, EDGE, EDGE)],
			[Vector3(0.0, -(size.y + EDGE) * 0.5, 0.0), Vector3(size.x + EDGE * 2.0, EDGE, EDGE)],
			[Vector3(-(size.x + EDGE) * 0.5, 0.0, 0.0), Vector3(EDGE, size.y, EDGE)],
			[Vector3((size.x + EDGE) * 0.5, 0.0, 0.0), Vector3(EDGE, size.y, EDGE)]]:
		var box := BoxMesh.new()
		box.size = bar[1]
		_add(face, "Edge", box, metal).position = bar[0]
	for side: float in [-1.0, 1.0]:
		var rod := CylinderMesh.new()
		rod.top_radius = POST_RADIUS
		rod.bottom_radius = POST_RADIUS
		rod.height = at.y + size.y * 0.5
		rod.radial_segments = 12
		rod.rings = 1
		var post := _add(root, "Post", rod, steel)
		post.position = Vector3(at.x + side * size.x * 0.36, rod.height * 0.5, at.z - POST_RADIUS - 0.02)
	return face

## Two brushed-steel posts from the floor (y = 0) up to `top`, `spread` apart, at depth `z`: for a sign whose face the caller draws.
static func posts(root: Node3D, spread: float, top: float, z: float) -> void:
	var signage := Surfaces.signage()
	var steel := _paint(Color(str(signage.post)), 0.4, float(signage.post_metal))
	for side: float in [-1.0, 1.0]:
		var rod := CylinderMesh.new()
		rod.top_radius = POST_RADIUS
		rod.bottom_radius = POST_RADIUS
		rod.height = top
		rod.radial_segments = 12
		rod.rings = 1
		_add(root, "Post", rod, steel).position = Vector3(side * spread * 0.5, top * 0.5, z)

## One lamp: a small glossy bulb that shows its colour in shade too.
static func lamp(radius: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var node := MeshInstance3D.new()
	node.name = "Lamp"
	node.mesh = sphere
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## A flat ring between radii `inner` and `outer` lying `lift` metres over the floor, facing up (a disc for inner 0). Its materials are
## two-sided, so the winding does not matter.
static func _annulus(inner: float, outer: float, lift: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for k in SEGMENTS + 1:
		var angle := TAU * float(k) / SEGMENTS
		var around := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(around * inner + Vector3.UP * lift)
		vertices.append(around * outer + Vector3.UP * lift)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for k in SEGMENTS:
		var i := k * 2
		indices.append_array(PackedInt32Array([i, i + 2, i + 1, i + 1, i + 2, i + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _paint(color: Color, rough: float, metal := 0.0, two_sided := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	if two_sided: material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func _add(parent: Node3D, label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
