extends RefCounted
## A sliding block that hurts (a `slide` hazard with `hit` whose parts are boxes, levels 30: the crates that shuttle across a deck) in the candy look: a pillow cube, the shape of an inflatable
## (every corner and edge rolled over by a fifth of the box's shortest side, smooth normals), hot pink with 45 degree white stripes (style/candy_prop.gdshader, striped vinyl): the same pink-and-white
## stripes as the spinner bars, so everything that hurts reads as one family. One mesh per box size, one shared material (style/lathe_mesh.gd). Look only: the collision is the box, untouched (the pillow
## sits inside it); a child of the collision shape, so it moves with the body. Client only.
const Lathe := preload("res://style/lathe_mesh.gd")
const CandyLook := preload("res://style/candy_look.gd")
const ROUND_SHARE := 0.2       ## the rounding radius over the box's shortest side (at most MAX_ROUND)
const MAX_ROUND := 0.4         ## m
const STEPS := 6               ## grid steps over a face's flat part (per axis); the rolled rim takes RIM_STEPS more
const RIM_STEPS := 3
const STRIPE := 0.75           ## m: one stripe and its gap

static var _meshes := {}

## The look of the box `shape_node` (a CollisionShape3D child of the hazard's body): a MeshInstance3D, or null for a shape that is not a box.
static func build(shape_node: CollisionShape3D) -> MeshInstance3D:
	var box := shape_node.shape as BoxShape3D
	if box == null: return null
	if not _meshes.has(box.size): _meshes[box.size] = _mesh(box.size)
	var visual := MeshInstance3D.new()
	visual.name = "RaceLook"
	visual.mesh = _meshes[box.size]
	return visual

## Grid coordinates along one axis of half length `half` with the corner radius `radius`: the rim steps either side, `STEPS` over the flat part.
static func _axis(half: float, radius: float) -> PackedFloat32Array:
	var inner := half - radius
	var out := PackedFloat32Array()
	for k in RIM_STEPS: out.append(-half + radius * float(k) / RIM_STEPS)
	for k in STEPS + 1: out.append(lerpf(-inner, inner, float(k) / STEPS))
	for k in range(1, RIM_STEPS + 1): out.append(inner + radius * float(k) / RIM_STEPS)
	return out

static func _mesh(size: Vector3) -> ArrayMesh:
	var half := size * 0.5
	var radius := minf(minf(size.x, minf(size.y, size.z)) * ROUND_SHARE, MAX_ROUND)
	var inner := half - Vector3.ONE * radius
	var tint := Color(CandyLook.PROP_PINK.srgb_to_linear(), Lathe.STRIPED)
	var group := Lathe.BlockMesh.Group.new()
	for axis in 3:
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		var grid_a := _axis(half[a], radius)
		var grid_b := _axis(half[b], radius)
		for side in [-1.0, 1.0]:
			var base := group.v.size()
			for i in grid_a.size():
				for j in grid_b.size():
					var q := Vector3.ZERO
					q[axis] = side * half[axis]
					q[a] = grid_a[i]
					q[b] = grid_b[j]
					var clamped := q.clamp(-inner, inner)
					var away := (q - clamped).normalized()
					var uv := Vector2(grid_a[i] + grid_b[j], 0.0) / STRIPE + Vector2(float(axis) * 0.37, 0.0)
					group.add(clamped + away * radius, away, uv, tint)
			for i in grid_a.size() - 1:
				for j in grid_b.size() - 1:
					var p0 := base + i * grid_b.size() + j
					var p1 := p0 + 1
					var p2 := p0 + grid_b.size() + 1
					var p3 := p0 + grid_b.size()
					group.quad(p0, p1, p2, p3, group.n[p0] + group.n[p2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = group.v
	arrays[Mesh.ARRAY_NORMAL] = group.n
	arrays[Mesh.ARRAY_TEX_UV] = group.uv
	arrays[Mesh.ARRAY_COLOR] = group.c
	arrays[Mesh.ARRAY_INDEX] = group.i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Lathe.material())
	return mesh
