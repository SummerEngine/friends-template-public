extends RefCounted
## EXPERIMENT (switchable): THE MANAGER. The marker over the manager's head: a little clipboard (a navy board, a cream sheet with four lines of "orders" and a mint tick, a gold clip) tipped
## a little and turning slowly as it bobs, so every player sees who makes the rules from any side. Built in code from boxes with its own flat materials, client only, pure look.
##   ManagerMarker.build()        # a Node3D with the clipboard standing on its origin (+Y up, the sheet facing +Z); ManagerMarker.animate(node, seconds) bobs and turns it
const HEIGHT := 0.44 ## m, the board's height
const RISE := 0.5 ## m over the head anchor its middle floats
static var _materials := {}

static func _material(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.55
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _materials[key]

static func _box(parent: Node3D, key: String, color: Color, size: Vector3, at: Vector3, turn := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(key, color)
	node.position = at
	node.rotation.z = turn
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ManagerMarker"
	var holder := Node3D.new()
	holder.name = "Board"
	root.add_child(holder)
	var wide := HEIGHT * 0.78
	_box(holder, "board", Color("22357a"), Vector3(wide, HEIGHT, 0.045), Vector3(0.0, 0.0, 0.0))
	_box(holder, "sheet", Color("f6f0e0"), Vector3(wide * 0.82, HEIGHT * 0.8, 0.012), Vector3(0.0, -HEIGHT * 0.04, 0.03))
	_box(holder, "sheet", Color("f6f0e0"), Vector3(wide * 0.82, HEIGHT * 0.8, 0.012), Vector3(0.0, -HEIGHT * 0.04, -0.03))
	for line in 4:
		var y := HEIGHT * (0.22 - 0.15 * float(line))
		var length := wide * (0.62 if line < 3 else 0.38)
		_box(holder, "ink", Color("2b3350"), Vector3(length, 0.018, 0.006), Vector3(-(wide * 0.62 - length) * 0.5 - wide * 0.02, y, 0.04))
	# the tick that approves the orders: two bars of a check mark, mint on the top line's end
	_box(holder, "tick", Color("2f9f86"), Vector3(0.05, 0.016, 0.008), Vector3(wide * 0.3, HEIGHT * 0.185, 0.042), deg_to_rad(-40.0))
	_box(holder, "tick", Color("2f9f86"), Vector3(0.095, 0.016, 0.008), Vector3(wide * 0.36, HEIGHT * 0.225, 0.042), deg_to_rad(50.0))
	# the clip: a gold plate over the top edge with a round-cornered grip
	_box(holder, "gold", Color("f2b632"), Vector3(wide * 0.46, HEIGHT * 0.1, 0.07), Vector3(0.0, HEIGHT * 0.5, 0.0))
	_box(holder, "gold", Color("c9731a"), Vector3(wide * 0.26, HEIGHT * 0.05, 0.085), Vector3(0.0, HEIGHT * 0.5, 0.0))
	holder.position = Vector3(0.0, RISE, 0.0)
	holder.rotation.x = deg_to_rad(-8.0)
	return root

## Bob and turn the marker: `seconds` is any running clock.
static func animate(root: Node3D, seconds: float) -> void:
	var holder := root.get_node_or_null("Board") as Node3D
	if holder == null: return
	holder.position.y = RISE + 0.035 * sin(seconds * 2.6)
	holder.rotation.y = seconds * 1.4
	holder.rotation.z = 0.08 * sin(seconds * 1.7)
