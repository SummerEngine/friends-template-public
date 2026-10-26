extends Node3D
## The lobby props as drawn (players/prop_sim.gd): a cardboard box, a striped ball, a traffic cone. Plain meshes, one material per
## colour, no lights. build(props) once, then follow(props, delta, hands) every frame with the PropSim being drawn.
const PropSim := preload("res://players/prop_sim.gd")
const FOLLOW_SPEED := 18.0 ## 1/s: drawn props ease towards the simulated ones (replica snapshots arrive at 20 Hz)
const SNAP := 3.0          ## m: a jump this far is not eased

var _nodes: Array[Node3D] = []
static var _materials := {}

static func _material(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), roughness]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = roughness
		_materials[key] = material
	return _materials[key]

func build(props: PropSim) -> void:
	for index in props.count:
		var node := Node3D.new()
		node.name = "Prop_%s_%d" % [props.kinds[index], index]
		add_child(node)
		var radius := float(PropSim.KINDS[props.kinds[index]])
		match props.kinds[index]:
			"box":
				var box := BoxMesh.new()
				box.size = Vector3.ONE * radius * 2.0
				_part(node, box, _material(Color("#b98a55")))
				var tape := BoxMesh.new()
				tape.size = Vector3(box.size.x * 1.02, box.size.y * 0.16, box.size.z * 1.02)
				_part(node, tape, _material(Color("#d9c49a"), 0.5))
			"ball":
				var sphere := SphereMesh.new()
				sphere.radius = radius
				sphere.height = radius * 2.0
				_part(node, sphere, _material(Color("#e8463c"), 0.45))
				var band := CylinderMesh.new()
				band.top_radius = radius * 1.01
				band.bottom_radius = band.top_radius
				band.height = radius * 0.35
				_part(node, band, _material(Color("#f4f1ea"), 0.45))
			_: # a traffic cone standing on its foot at the bottom of the collision sphere
				var height := radius * 2.8
				var cone := CylinderMesh.new()
				cone.top_radius = 0.03
				cone.bottom_radius = radius * 0.9
				cone.height = height
				var body := _part(node, cone, _material(Color("#ff7a1f"), 0.6))
				body.position.y = height * 0.5 - radius
				var stripe := CylinderMesh.new()
				stripe.top_radius = cone.bottom_radius * 0.5
				stripe.bottom_radius = cone.bottom_radius * 0.66
				stripe.height = height * 0.16
				var ring := _part(node, stripe, _material(Color("#f4f1ea"), 0.6))
				ring.position.y = body.position.y + height * 0.08
				var foot := BoxMesh.new()
				foot.size = Vector3(radius * 2.2, 0.05, radius * 2.2)
				var base := _part(node, foot, _material(Color("#2b2b30"), 0.9))
				base.position.y = 0.025 - radius
		node.position = props.positions[index]
		_nodes.append(node)

func _part(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	parent.add_child(part)
	return part

## Draw `props`: free props ease to the simulated ones (the ball rolls, the others turn while they fly); a carried prop sits at
## `hands.call(slot)` (the holder as drawn this frame; Vector3.INF or no callable: the simulated spot).
func follow(props: PropSim, delta: float, hands := Callable()) -> void:
	for index in mini(_nodes.size(), props.count):
		var node := _nodes[index]
		var target: Vector3 = props.positions[index]
		var holder := props.held_by[index]
		if holder >= 0:
			var hand: Vector3 = hands.call(holder) if hands.is_valid() else Vector3.INF
			node.position = hand if hand.is_finite() else target
			continue
		node.position = target if node.position.distance_to(target) > SNAP else node.position.lerp(target, 1.0 - exp(-delta * FOLLOW_SPEED))
		var velocity: Vector3 = props.velocities[index]
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		if props.kinds[index] == "ball":
			if flat.length() > 0.2: node.global_rotate(Vector3.UP.cross(flat.normalized()), flat.length() * delta / float(PropSim.KINDS.ball))
		elif absf(velocity.y) > 0.5: node.rotate_y(flat.length() * delta * 0.8)
