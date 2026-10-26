extends Node3D
## EXPERIMENT (switchable): TANDEM, the pops (docs/party-show.md "Tandem (experiment)"): flat hearts and four-point sparks drawn as camera-facing unshaded shapes made in code (own meshes and
## materials, nothing of the world's look is touched). `heart(at, velocity, size, life)` and `spark(at, velocity, size, life)` add one; `burst(at)` is the fuse's pop (a ring of hearts, a ring of
## sparks), `poof(at)` the buddy's coming and going, `step(dt)` moves them. Every piece pops in, rides on its velocity (slowly lifting, slowing down) and shrinks away.
const HEART_POINTS := 28
const COLORS := [Color("ff5c8a"), Color("ff8fb1"), Color("ffd0dc"), Color("ff3d6e")]
const SPARK_COLOR := Color("fff2a8")

static var _heart_mesh: ArrayMesh
static var _spark_mesh: ArrayMesh
static var _materials := {}

var _bits: Array = [] ## {node, v, age, life, size, spin}
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	name = "TandemFx"
	_rng.seed = 77

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		_materials[key] = material
	return _materials[key]

## A flat heart of unit height (a parametric heart outline fanned from its middle), standing in the XY plane.
static func heart_mesh() -> ArrayMesh:
	if _heart_mesh != null: return _heart_mesh
	var ring := PackedVector3Array()
	for index in HEART_POINTS:
		var t := TAU * float(index) / HEART_POINTS
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		ring.append(Vector3(x, y + 1.5, 0.0) / 30.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, 0.0, 0.0)
	for index in HEART_POINTS:
		tool.set_normal(Vector3.BACK)
		tool.add_vertex(centre)
		tool.set_normal(Vector3.BACK)
		tool.add_vertex(ring[index])
		tool.set_normal(Vector3.BACK)
		tool.add_vertex(ring[(index + 1) % HEART_POINTS])
	_heart_mesh = tool.commit()
	return _heart_mesh

## A four-point star of unit height.
static func spark_mesh() -> ArrayMesh:
	if _spark_mesh != null: return _spark_mesh
	var ring := PackedVector3Array()
	for index in 8:
		var radius := 0.5 if index % 2 == 0 else 0.13
		var angle := TAU * float(index) / 8.0
		ring.append(Vector3(cos(angle), sin(angle), 0.0) * radius)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 8:
		for point: Vector3 in [Vector3.ZERO, ring[index], ring[(index + 1) % 8]]:
			tool.set_normal(Vector3.BACK)
			tool.add_vertex(point)
	_spark_mesh = tool.commit()
	return _spark_mesh

func _add(mesh: ArrayMesh, color: Color, at: Vector3, velocity: Vector3, size: float, life: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = at
	node.scale = Vector3.ZERO
	_bits.append({"node": node, "v": velocity, "age": 0.0, "life": life, "size": size})

func heart(at: Vector3, velocity: Vector3, size := 0.32, life := 1.3) -> void:
	_add(heart_mesh(), COLORS[_rng.randi() % COLORS.size()], at, velocity, size, life)

func spark(at: Vector3, velocity: Vector3, size := 0.22, life := 0.7) -> void:
	_add(spark_mesh(), SPARK_COLOR, at, velocity, size, life)

## The fuse's pop at `at` (over the joined hands): hearts fly up and out, sparks go round.
func burst(at: Vector3) -> void:
	for index in 12:
		var angle := TAU * float(index) / 12.0 + _rng.randf() * 0.3
		var out := Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(1.1, 2.2)
		heart(at, out + Vector3.UP * _rng.randf_range(1.8, 3.4), _rng.randf_range(0.26, 0.5), _rng.randf_range(1.1, 1.7))
	for index in 16:
		var angle := TAU * float(index) / 16.0
		spark(at, Vector3(cos(angle), _rng.randf_range(-0.2, 0.9), sin(angle)) * _rng.randf_range(2.6, 4.4), _rng.randf_range(0.18, 0.3), _rng.randf_range(0.5, 0.8))

## A small puff of sparks (the buddy comes, leaves; two come apart).
func poof(at: Vector3) -> void:
	for index in 8:
		var angle := TAU * float(index) / 8.0
		spark(at, Vector3(cos(angle), 0.4, sin(angle)) * _rng.randf_range(1.2, 2.4), _rng.randf_range(0.14, 0.24), _rng.randf_range(0.4, 0.6))

func step(dt: float) -> void:
	for bit: Dictionary in _bits.duplicate():
		bit.age = float(bit.age) + dt
		var node: Node3D = bit.node
		var life := float(bit.life)
		var age := float(bit.age)
		if age >= life or not is_instance_valid(node):
			if is_instance_valid(node): node.queue_free()
			_bits.erase(bit)
			continue
		var v: Vector3 = bit.v
		node.global_position += v * dt
		bit.v = Vector3(v.x * maxf(1.0 - 1.6 * dt, 0.0), v.y * maxf(1.0 - 1.1 * dt, 0.0) + 0.5 * dt, v.z * maxf(1.0 - 1.6 * dt, 0.0))
		var grow := minf(age / 0.12, 1.0) * (1.0 + 0.25 * sin(minf(age / 0.12, 1.0) * PI)) # pops in with a little overshoot
		var shrink := clampf((life - age) / (life * 0.35), 0.0, 1.0)
		node.scale = Vector3.ONE * float(bit.size) * grow * shrink

func count() -> int:
	return _bits.size()

func clear() -> void:
	for bit: Dictionary in _bits:
		if is_instance_valid(bit.node): (bit.node as Node).queue_free()
	_bits.clear()
