extends RefCounted
## GHOST PIGEON (docs/pigeon.md): our own low-poly pigeon, built in code from a few primitives (no model file, nothing AI-made): a grey-blue body with a pale belly, a round head with an orange
## eye and a little beak, a collar in the player's own colour (who it is), two wings that flap, a banded tail, tucked feet and a small gold halo (a ghost pigeon). About 0.9 m from beak to tail,
## 1.6 m across the wings, facing -Z like the couriers. Self-contained: its own small materials, nothing of the show's look.
##   PigeonMesh.build(color)                       -> Node3D (children named Body, WingL, WingR, Halo, Head)
##   PigeonMesh.pose(bird, phase, amp, bank, pitch)  flap (`phase` radians, `amp` the wing's swing), lean into a turn (`bank`) and tip nose up / down (`pitch`)
const BODY := Color("a7aebf")
const BELLY := Color("dfe4ee")
const WING := Color("8a93aa")
const WING_TIP := Color("3d4560")
const NECK := Color("5d9a96")
const BEAK := Color("e8a23a")
const EYE := Color("f08a24")
const PUPIL := Color("14161d")
const FOOT := Color("d9778f")
const HALO := Color("ffd45a")
const SIZE := 1.4 # the bird's scale: the show's cameras sit far back, a real pigeon would be a speck

static func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.0
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

static func _part(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, scale := Vector3.ONE, rotation_deg := Vector3.ZERO, glow := 0.0, label := "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color, glow)
	node.position = at
	node.scale = scale
	node.rotation_degrees = rotation_deg
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if label != "": node.name = label
	parent.add_child(node)
	return node

static func _sphere(segments := 12) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = maxi(segments / 2, 4)
	return mesh

static func build(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Pigeon"
	root.scale = Vector3.ONE * SIZE
	var body := Node3D.new() # everything that leans and tips together
	body.name = "Body"
	root.add_child(body)
	_part(body, _sphere(14), BODY, Vector3(0.0, 0.0, 0.0), Vector3(0.44, 0.40, 0.70))
	_part(body, _sphere(12), BELLY, Vector3(0.0, -0.05, -0.07), Vector3(0.36, 0.28, 0.5))
	_part(body, _sphere(10), BODY, Vector3(0.0, 0.14, -0.22), Vector3(0.24, 0.26, 0.26))
	var collar := TorusMesh.new()
	collar.inner_radius = 0.075
	collar.outer_radius = 0.135
	collar.rings = 14
	collar.ring_segments = 6
	_part(body, collar, color, Vector3(0.0, 0.17, -0.235), Vector3.ONE, Vector3(-28.0, 0.0, 0.0), 0.0, "Collar")
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.27, -0.31)
	body.add_child(head)
	_part(head, _sphere(12), BODY, Vector3.ZERO, Vector3(0.25, 0.24, 0.27))
	var beak := CylinderMesh.new()
	beak.top_radius = 0.0
	beak.bottom_radius = 0.042
	beak.height = 0.15
	beak.radial_segments = 8
	_part(head, beak, BEAK, Vector3(0.0, -0.015, -0.17), Vector3.ONE, Vector3(-90.0, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_part(head, _sphere(8), EYE, Vector3(side * 0.07, 0.03, -0.085), Vector3.ONE * 0.075)
		_part(head, _sphere(6), PUPIL, Vector3(side * 0.08, 0.032, -0.1), Vector3.ONE * 0.04)
	var halo := TorusMesh.new()
	halo.inner_radius = 0.1
	halo.outer_radius = 0.135
	halo.rings = 18
	halo.ring_segments = 5
	_part(head, halo, HALO, Vector3(0.0, 0.22, 0.0), Vector3.ONE, Vector3.ZERO, 1.6, "Halo")
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if side < 0.0 else "WingR"
		pivot.position = Vector3(side * 0.16, 0.07, -0.05)
		body.add_child(pivot)
		_part(pivot, _sphere(10), WING, Vector3(side * 0.36, 0.0, 0.05), Vector3(0.72, 0.05, 0.36))
		_part(pivot, _sphere(8), WING_TIP, Vector3(side * 0.68, 0.0, 0.1), Vector3(0.24, 0.05, 0.3))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.2, 0.025, 0.3)
	_part(body, tail, WING, Vector3(0.0, 0.0, 0.5), Vector3.ONE, Vector3(8.0, 0.0, 0.0))
	_part(body, _sphere(8), Color("f4f6fb"), Vector3(0.0, 0.1, 0.3), Vector3(0.22, 0.1, 0.2)) # the white rump
	var band := BoxMesh.new()
	band.size = Vector3(0.2, 0.028, 0.08)
	_part(body, band, WING_TIP, Vector3(0.0, -0.005, 0.62), Vector3.ONE, Vector3(8.0, 0.0, 0.0))
	var leg := CylinderMesh.new()
	leg.top_radius = 0.012
	leg.bottom_radius = 0.012
	leg.height = 0.14
	leg.radial_segments = 5
	for side in [-1.0, 1.0]: _part(body, leg, FOOT, Vector3(side * 0.07, -0.19, 0.12), Vector3.ONE, Vector3(70.0, 0.0, 0.0))
	return root

## Flap and lean. `phase`: radians of the flap; `amp`: how far the wings swing (0 = held out, 0.9 = a hard flap); `bank`: radians of roll into a turn; `pitch`: radians of nose up (+) or down (-).
static func pose(bird: Node3D, phase: float, amp: float, bank: float, pitch: float) -> void:
	var body: Node3D = bird.get_node_or_null("Body")
	if body == null: return
	var swing := sin(phase) * amp
	var droop := 0.12 + 0.1 * amp # the wings hang a little at rest, rise and fall with a flap
	var left: Node3D = body.get_node_or_null("WingL")
	var right: Node3D = body.get_node_or_null("WingR")
	if left != null: left.rotation = Vector3(0.0, 0.0, -(swing + 0.35 * amp - droop * 0.4))
	if right != null: right.rotation = Vector3(0.0, 0.0, swing + 0.35 * amp - droop * 0.4)
	body.rotation = Vector3(pitch, 0.0, bank)
	body.position.y = cos(phase) * 0.03 * amp # the body bobs against the wings
