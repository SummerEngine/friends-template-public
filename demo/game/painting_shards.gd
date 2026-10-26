extends Node3D
## The carried item's break. Its own pieces (the item data of style/carry_item.gd: the glass pane's angular shards, edge
## strip and rubber caps; a painting's frame bars and corners, torn canvas and glass) fly outward tumbling, bounce, settle flat
## and shrink away; glass splinters and glints (a painting: canvas scraps and paint flecks) fly with them.
## Every position and rotation is a pure function of (seed, age), so a replica replays the burst from `capture_state()` of
## the peer that owns the clock. One burst at a time; a new burst replaces the old one. API: docs/painting-api.md.
const CarryItem := preload("res://style/carry_item.gd")

const GRAVITY := 10.0
const RESTITUTION := 0.35
const AIR_DRAG := 1.4 ## horizontal slowing, 1/s
const TUMBLE_DECAY := 0.8 ## the spin fades out while flying, 1/s
const SETTLE_TIME := 0.35 ## after the first landing a piece turns flat in this time
const REST_LIFT := 0.02 ## resting pieces sit this high above the floor
const SHRINK_START := 18.0
const SHRINK_END := 27.0
const SYNC_TOLERANCE := 0.25 ## a replica re-syncs its clock when it differs from the state by more than this (s)
const HOLDER := Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT) ## item frame -> painting frame

static var _meshes := {} ## item name -> Array of ArrayMesh

var simulate := true ## draw the pieces on this peer
var authority := true ## this peer owns the clock
var auto_advance := true
var active := false
var age := 0.0

var _seed := 0
var _item := ""
var _floor_y := 0.0
var _pose := Transform3D.IDENTITY
var _lifetime := 30.0
var _pieces: Array[MeshInstance3D] = []
var _motion: Array[Dictionary] = []
var _flecks: Node3D

func configure(do_simulate: bool, is_authority: bool) -> void:
	simulate = do_simulate
	authority = is_authority
	top_level = true # pieces live in world space
	global_transform = Transform3D.IDENTITY

func reset() -> void:
	active = false
	age = 0.0
	_motion.clear()
	for piece in _pieces: piece.queue_free()
	_pieces.clear()
	if _flecks != null:
		_flecks.queue_free()
		_flecks = null

## Starts a burst at the painting's pose. `floor_y` NaN: look for the floor under the painting.
func burst(painting_transform: Transform3D, burst_seed: int, floor_y := NAN) -> void:
	var floor_level := floor_y if not is_nan(floor_y) else _find_floor(painting_transform.origin)
	var q := painting_transform.basis.get_rotation_quaternion()
	_start(burst_seed, CarryItem.active(), _quantized(painting_transform.origin, q), floor_level, 0.0)

func advance(dt: float) -> void:
	if not active: return
	age += dt
	if age >= _lifetime:
		reset()
		return
	if simulate: _apply()

func _process(delta: float) -> void:
	if auto_advance: advance(delta)

## [] or [seed, age, floor_y, qx, qy, qz, qw, px, py, pz, item_index]
func capture_state() -> Array:
	if not active: return []
	var q := _pose.basis.get_rotation_quaternion()
	return [_seed, snappedf(age, 0.01), _floor_y, q.x, q.y, q.z, q.w, _pose.origin.x, _pose.origin.y, _pose.origin.z, CarryItem.ITEMS.find(_item)]

func apply_state(state: Array, _weight: float) -> void:
	if authority: return # the clock owner is the source of the state
	if state.size() < 11:
		if active: reset()
		return
	var state_seed := int(state[0])
	var state_age := float(state[1])
	if active and state_seed == _seed:
		if absf(age - state_age) > SYNC_TOLERANCE: age = state_age
		return
	var item_index := int(state[10])
	if item_index < 0 or item_index >= CarryItem.ITEMS.size(): return
	var pose := _quantized(Vector3(state[7], state[8], state[9]), Quaternion(state[3], state[4], state[5], state[6]))
	_start(state_seed, CarryItem.ITEMS[item_index], pose, float(state[2]), state_age)

# The state is quantized so the peer that bursts and the peers that replay it compute the same motion.
static func _quantized(origin: Vector3, q: Quaternion) -> Transform3D:
	var rounded := Quaternion(snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)).normalized()
	return Transform3D(Basis(rounded), Vector3(snappedf(origin.x, 0.001), snappedf(origin.y, 0.001), snappedf(origin.z, 0.001)))

func _find_floor(from: Vector3) -> float:
	if is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.2, from + Vector3.DOWN * 40.0, 1 | 16)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): return (hit.position as Vector3).y
	return from.y - 0.9

func _start(burst_seed: int, item_name: String, pose: Transform3D, floor_level: float, start_age: float) -> void:
	reset()
	_seed = burst_seed
	_item = item_name
	_pose = pose
	_floor_y = floor_level
	age = start_age
	active = true
	var entry: Dictionary = CarryItem.data(item_name)
	_lifetime = float(entry.get("lifetime", 30.0))
	if not simulate: return
	_build(entry)
	_apply()

func _build(entry: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var burst_spec: Dictionary = entry.get("burst", {})
	var outward := float(burst_spec.get("outward", 1.0))
	var up := float(burst_spec.get("up", 1.7))
	var spin := float(burst_spec.get("spin", 5.5))
	var start_basis := _pose.basis * HOLDER
	var along := Vector3(_pose.basis.x.x, 0.0, _pose.basis.x.z)
	along = along.normalized() if along.length_squared() > 0.0001 else Vector3.RIGHT
	var level := Basis(along, Vector3.UP.cross(along), Vector3.UP) * HOLDER
	var meshes := _piece_meshes(_item, entry)
	var anchors: Array = []
	var centre := Vector3.ZERO
	for i in entry.pieces.size():
		var spec: Dictionary = entry.pieces[i]
		var c: Array = spec.centre
		var half: Array = spec.half
		var world_c := _pose * (HOLDER * Vector3(c[0], c[1], c[2]))
		var away := world_c - _pose.origin
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU)
		var velocity := away * outward * rng.randf_range(0.6, 1.3) + Vector3.UP * up * rng.randf_range(0.7, 1.15)
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		axis = axis.normalized() if axis.length_squared() > 0.01 else Vector3.RIGHT
		var rate := spin * rng.randf_range(0.6, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		var rest_y := _floor_y + float(half[1]) + REST_LIFT
		var y0 := maxf(world_c.y, rest_y)
		var impact := sqrt(velocity.y * velocity.y + 2.0 * GRAVITY * (y0 - rest_y))
		var rest_basis := Basis(Vector3.UP, rng.randf_range(-0.9, 0.9)) * level
		_motion.append({
			"p0": world_c, "v": velocity, "y0": y0, "rest_y": rest_y, "impact": impact,
			"t_land": (velocity.y + impact) / GRAVITY,
			"axis": axis, "rate": rate,
			"q0": start_basis.get_rotation_quaternion(), "q_rest": rest_basis.get_rotation_quaternion(),
		})
		var piece := MeshInstance3D.new()
		piece.mesh = meshes[i]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		_pieces.append(piece)
		anchors.append(world_c)
		centre += world_c
	if not anchors.is_empty():
		_flecks = CarryItem.build_flecks(_seed, anchors, centre / float(anchors.size()), _item)
		if _flecks != null: add_child(_flecks)

# One mesh per piece, centred on the piece, cached per item.
static func _piece_meshes(item_name: String, entry: Dictionary) -> Array:
	if _meshes.has(item_name): return _meshes[item_name]
	var list: Array = []
	for spec: Dictionary in entry.pieces:
		var c: Array = spec.centre
		var arrays := CarryItem.piece_arrays(entry, spec, Transform3D(Basis.IDENTITY, -Vector3(c[0], c[1], c[2])))
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, CarryItem.piece_material(spec))
		list.append(mesh)
	_meshes[item_name] = list
	return list

static func _height(m: Dictionary, t: float) -> float:
	if t < float(m.t_land): return float(m.y0) + float(m.v.y) * t - 0.5 * GRAVITY * t * t
	var tau := t - float(m.t_land)
	var speed := float(m.impact) * RESTITUTION
	for bounce in 3:
		var duration := 2.0 * speed / GRAVITY
		if tau < duration: return float(m.rest_y) + speed * tau - 0.5 * GRAVITY * tau * tau
		tau -= duration
		speed *= RESTITUTION
	return float(m.rest_y)

static func _rotation(m: Dictionary, t: float) -> Quaternion:
	var flying := minf(t, float(m.t_land))
	var angle := float(m.rate) * (1.0 - exp(-TUMBLE_DECAY * flying)) / TUMBLE_DECAY
	var tumbling := Quaternion(m.axis, angle) * (m.q0 as Quaternion)
	if t <= float(m.t_land): return tumbling
	return tumbling.slerp(m.q_rest, smoothstep(0.0, SETTLE_TIME, t - float(m.t_land)))

func _apply() -> void:
	var shrink := 1.0 - smoothstep(SHRINK_START, SHRINK_END, age)
	var drag := (1.0 - exp(-AIR_DRAG * age)) / AIR_DRAG
	for i in _pieces.size():
		var m: Dictionary = _motion[i]
		var at := Vector3(float(m.p0.x) + float(m.v.x) * drag, _height(m, age), float(m.p0.z) + float(m.v.z) * drag)
		var piece := _pieces[i]
		piece.visible = shrink > 0.001
		piece.global_transform = Transform3D(Basis(_rotation(m, age)).scaled(Vector3.ONE * shrink), at)
	if _flecks != null: CarryItem.animate_flecks(_flecks, age, _floor_y, _lifetime - 12.0, _lifetime - 3.0)
