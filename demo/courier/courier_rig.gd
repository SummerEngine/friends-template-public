extends Node3D
## The drawn courier: a skeleton of 19 bones built in code, one skinned mesh of primitive shapes
## and procedural animation (idle, walk, run, jump, fall, land, carry with two-bone arm reach).
## Rig space: origin at the feet, +Y up, forward is -Z, the courier's left side is -X.
## The node turns itself to the smoothed `state.yaw`; the caller only places its global position.

signal footstep(side: int)
signal jumped
signal landed(speed: float)
signal slap_hit(side: int, hand_world: Vector3) ## never fires: the courier does not slap (same API as character/character_rig.gd)

const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)
const SLAP_HIT_TIME := 0.0
const TeamCast := preload("res://style/team_cast.gd") ## seat colours, skin and hair come from the team cast (demo/cast/cast.json)

# ---------------------------------------------------------------- proportions (metres)
const THIGH := 0.45
const SHIN := 0.44
const ARM_UP := 0.30
const ARM_FORE := 0.27
const ANKLE_H := 0.07
const HIP_X := 0.10
const SHOULDER_X := 0.26
const SHOULDER_Y := 1.38
const GLOVE_REACH := 0.06 ## wrist to glove centre
const HEAD_R := 0.15
const HEAD_Y := 1.64
const HOLD_FORWARD := 0.40
const HOLD_SIDE := 0.25
const REACH_FACTOR := 0.97
const GETUP := 0.3 ## s at the end of `state.flop` spent getting up (courier_motion.gd FLOP_GETUP)
const LIE_IN := 0.1 ## s to go down on the belly
const LIE_HEIGHT := 0.2 ## m: the body axis over the floor when lying
const LIE_CENTER := 0.08 ## m: hips ahead of the capsule centre while lying (the legs reach further back than the head forward)
const DIVE_SPEED := 7.0 ## m/s of planar speed in the air that pitches the courier forward
const DIVE_PITCH := 1.1 ## rad (63 degrees)

const B_ROOT := 0
const B_PELVIS := 1
const B_SPINE := 2
const B_CHEST := 3
const B_NECK := 4
const B_HEAD := 5
const B_PACK := 6
const B_UA := [7, 10]
const B_FA := [8, 11]
const B_HAND := [9, 12]
const B_TH := [13, 16]
const B_SH := [14, 17]
const B_FOOT := [15, 18]
const BONES := ["root", "pelvis", "spine", "chest", "neck", "head", "pack", "upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const PARENTS := [-1, 0, 1, 2, 3, 4, 3, 3, 7, 8, 3, 10, 11, 1, 13, 14, 1, 16, 17]
## Rest origins in rig space (all bones have an identity rest rotation).
const REST: Array[Vector3] = [
	Vector3(0, 0, 0), Vector3(0, 0.98, 0), Vector3(0, 1.08, 0), Vector3(0, 1.24, 0), Vector3(0, 1.47, 0), Vector3(0, 1.52, 0), Vector3(0, 1.30, 0.20),
	Vector3(-0.26, 1.38, 0), Vector3(-0.26, 1.08, 0), Vector3(-0.26, 0.81, 0),
	Vector3(0.26, 1.38, 0), Vector3(0.26, 1.08, 0), Vector3(0.26, 0.81, 0),
	Vector3(-0.10, 0.96, 0), Vector3(-0.10, 0.51, 0), Vector3(-0.10, 0.07, 0),
	Vector3(0.10, 0.96, 0), Vector3(0.10, 0.51, 0), Vector3(0.10, 0.07, 0),
]

const KINDS := ["skin", "hair", "main", "accent", "pants", "dark", "shoe", "cream", "glove", "eye"]
const INK := Color("#1b1d3a")
const CREAM := Color("#fff1d6")

static var _mesh_cache: Dictionary = {}
static var _skin: Skin = null
static var _materials: Dictionary = {}

var seat := 0
var tint_index := 0
var hat_kind := "cap"
var _material_hook := Callable()
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _replica := false
var _built := false
var _fresh := true

# animation state
var _yaw := 0.0
var _phase := 0.0
var _clock := 0.0
var _air := 0.0
var _carry := 0.0
var _grounded := true
var _lean := 0.0
var _roll := 0.0
var _acc_fwd := 0.0
var _acc_side := 0.0
var _speed := 0.0
var _crouch := 0.0
var _crouch_v := 0.0
var _kick := 0.0
var _pack := 0.0
var _pack_v := 0.0
var _vy_prev := 0.0
var _fall_peak := 0.0
var _last_pos := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _lead := 0
var _reach_lean := 0.0
var _floor_n := Vector3.UP
var _hand_pos: Array = [Vector3.ZERO, Vector3.ZERO]
var _lie := 0.0 ## 0..1: how far the courier is down on its belly (eases in over LIE_IN s, then follows `state.flop` out)
var _getup := 0.0 ## 1 while the flop still lies flat, falling to 0 over the last GETUP s of `state.flop`
var _dive := 0.0 ## 0..1: the superman pitch of a fast airborne courier

# ---------------------------------------------------------------- setup
func setup(seat_index: int, style_cfg: Dictionary = {}) -> void:
	seat = seat_index
	tint_index = seat_index
	hat_kind = str(style_cfg.get("hat", "cap"))
	var hook: Variant = style_cfg.get("mat")
	_material_hook = hook if hook is Callable else Callable()
	if _skeleton != null:
		_skeleton.queue_free()
	_build()

func set_replica(on: bool) -> void:
	_replica = on

## No slap on the courier (callers of the character rig's slap need no checks).
func slap(_side: int) -> void:
	pass

func slap_length() -> float:
	return 0.0

func set_slot_tint(palette_index: int) -> void:
	tint_index = palette_index
	if _mesh != null: _apply_materials()

static func warm_up() -> void:
	_cached_mesh("cap")

func skeleton() -> Skeleton3D:
	return _skeleton

func anchor() -> Vector3:
	return global_position + ANCHOR_OFFSET

func hand_world(side: int) -> Vector3:
	if _skeleton == null: return anchor()
	return to_global(_hand_pos[side])

func hands_center() -> Vector3:
	return (hand_world(0) + hand_world(1)) * 0.5

func _build() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	for i in BONES.size():
		_skeleton.add_bone(BONES[i])
	for i in BONES.size():
		if PARENTS[i] >= 0: _skeleton.set_bone_parent(i, PARENTS[i])
		var parent_origin: Vector3 = REST[PARENTS[i]] if PARENTS[i] >= 0 else Vector3.ZERO
		_skeleton.set_bone_rest(i, Transform3D(Basis(), REST[i] - parent_origin))
	_skeleton.reset_bone_poses()
	add_child(_skeleton)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = _cached_mesh(hat_kind)
	_mesh.skin = _shared_skin()
	_mesh.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.6, 2.4))
	_skeleton.add_child(_mesh)
	_mesh.skeleton = NodePath("..")
	_apply_materials()
	_built = true
	_fresh = true
	_pose_rest_stand()

# ---------------------------------------------------------------- materials
func _apply_materials() -> void:
	var tint: Color = TeamCast.player_color(tint_index)
	var mesh := _mesh.mesh as ArrayMesh
	for surface in mesh.get_surface_count():
		var kind: String = mesh.surface_get_name(surface)
		_mesh.set_surface_override_material(surface, _material_for(kind, tint))

func _kind_color(kind: String, tint: Color) -> Color:
	match kind:
		"skin": return TeamCast.player(tint_index)["skin"]
		"hair": return TeamCast.player(tint_index)["hair"]
		"main": return tint
		"accent": return tint.darkened(0.3)
		"pants": return Color("#3b3f6e")
		"dark": return INK
		"shoe": return INK
		"cream": return CREAM
		"glove": return Color("#ffd23f")
		"eye": return INK
	return Color.WHITE

func _material_for(kind: String, tint: Color) -> Material:
	if _material_hook.is_valid():
		return _material_hook.call(kind, seat, tint)
	var color := _kind_color(kind, tint)
	var key := "%s|%s" % [kind, color.to_html()]
	if _materials.has(key): return _materials[key]
	var style := preload("res://style/friends_style.gd")
	var shader := style.shader_material("res://style/ink_surface.gdshader", {"mode": 3, "base_color": color, "alt_color": color.darkened(0.2), "ink_color": INK})
	var material: Material = shader if kind == "eye" else style.outlined(shader, INK, 0.028, false)
	_materials[key] = material
	return material

# ---------------------------------------------------------------- mesh
static func _shared_skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for i in BONES.size():
			_skin.add_bind(i, Transform3D(Basis(), -REST[i]))
	return _skin

class Builder extends RefCounted:
	static var _unit: Dictionary = {}
	var surfaces := {}

	static func _unit_arrays(shape: String) -> Array:
		if _unit.has(shape): return _unit[shape]
		var mesh: Mesh
		match shape:
			"sphere":
				var sphere := SphereMesh.new()
				sphere.radius = 1.0
				sphere.height = 2.0
				sphere.radial_segments = 14
				sphere.rings = 7
				mesh = sphere
			"capsule":
				var capsule := CapsuleMesh.new()
				capsule.radius = 1.0
				capsule.height = 2.0
				capsule.radial_segments = 12
				capsule.rings = 4
				mesh = capsule
			"box":
				var box := BoxMesh.new()
				mesh = box
			"cylinder":
				var cylinder := CylinderMesh.new()
				cylinder.top_radius = 1.0
				cylinder.bottom_radius = 1.0
				cylinder.height = 1.0
				cylinder.radial_segments = 16
				cylinder.rings = 1
				mesh = cylinder
			"torus":
				var torus := TorusMesh.new()
				torus.inner_radius = 0.7
				torus.outer_radius = 1.0
				torus.rings = 16
				torus.ring_segments = 8
				mesh = torus
			_:
				var prism := PrismMesh.new()
				mesh = prism
		var arrays: Array = mesh.get_mesh_arrays()
		_unit[shape] = arrays
		return arrays

	static func _frame(y: Vector3) -> Basis:
		var x := Vector3.RIGHT - y * Vector3.RIGHT.dot(y) if absf(y.x) < 0.9 else Vector3.UP - y * Vector3.UP.dot(y)
		x = x.normalized()
		return Basis(x, y, x.cross(y))

	func add(bone: int, shape: String, xf: Transform3D, kind: String, half := 0.0) -> void:
		if not surfaces.has(kind):
			surfaces[kind] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "i": PackedInt32Array(), "b": PackedInt32Array(), "w": PackedFloat32Array()}
		var s: Dictionary = surfaces[kind]
		var unit: Array = _unit_arrays(shape)
		var src: PackedVector3Array = unit[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = unit[Mesh.ARRAY_NORMAL]
		var src_i: PackedInt32Array = unit[Mesh.ARRAY_INDEX]
		if half > 0.0:
			src = src.duplicate()
			for k in src.size():
				var p := src[k]
				p.y += half if p.y > 0.0 else -half
				src[k] = p
		var normal_basis := xf.basis.inverse().transposed()
		var verts: PackedVector3Array = xf * src
		var norms: PackedVector3Array = Transform3D(normal_basis, Vector3.ZERO) * src_n
		var all_v: PackedVector3Array = s["v"]
		var base := all_v.size()
		for k in norms.size(): norms[k] = norms[k].normalized()
		all_v.append_array(verts)
		s["v"] = all_v
		var all_n: PackedVector3Array = s["n"]
		all_n.append_array(norms)
		s["n"] = all_n
		var indices := PackedInt32Array()
		indices.resize(src_i.size())
		for k in src_i.size(): indices[k] = src_i[k] + base
		var all_i: PackedInt32Array = s["i"]
		all_i.append_array(indices)
		s["i"] = all_i
		var bones := PackedInt32Array()
		bones.resize(verts.size() * 4)
		var weights := PackedFloat32Array()
		weights.resize(verts.size() * 4)
		for k in verts.size():
			bones[k * 4] = bone
			weights[k * 4] = 1.0
		var all_b: PackedInt32Array = s["b"]
		all_b.append_array(bones)
		s["b"] = all_b
		var all_w: PackedFloat32Array = s["w"]
		all_w.append_array(weights)
		s["w"] = all_w

	func capsule(bone: int, a: Vector3, b: Vector3, radius: float, kind: String, squash := Vector3.ONE) -> void:
		var length := (b - a).length()
		var half := maxf(length - 2.0 * radius, 0.0) * 0.5 / radius
		var basis: Basis = _frame((b - a) / maxf(length, 1e-6)) * Basis.from_scale(Vector3(radius * squash.x, radius, radius * squash.z))
		add(bone, "capsule", Transform3D(basis, (a + b) * 0.5), kind, half)

	func sphere(bone: int, centre: Vector3, radii: Vector3, kind: String) -> void:
		add(bone, "sphere", Transform3D(Basis.from_scale(radii), centre), kind)

	func box(bone: int, centre: Vector3, size: Vector3, kind: String) -> void:
		add(bone, "box", Transform3D(Basis.from_scale(size), centre), kind)

	func drum(bone: int, centre: Vector3, size: Vector3, kind: String) -> void:
		add(bone, "cylinder", Transform3D(Basis.from_scale(size), centre), kind)

	## Flat disc facing -Z (the front), or +Z with `back`.
	func disc(bone: int, centre: Vector3, radius: float, thickness: float, kind: String, back := false) -> void:
		var face := Basis(Vector3.RIGHT, PI * 0.5)
		add(bone, "cylinder", Transform3D(face * Basis.from_scale(Vector3(radius, thickness, radius)), centre), kind)

	func ring(bone: int, centre: Vector3, major: float, tube_y: float, kind: String) -> void:
		add(bone, "torus", Transform3D(Basis.from_scale(Vector3(major / 0.85, tube_y / 0.3, major / 0.85)), centre), kind)

	## Triangle mark, tip down, facing -Z (or +Z with `back`).
	func slice(bone: int, centre: Vector3, size: float, kind: String, back := false) -> void:
		var basis := Basis(Vector3(0, 0, 1), PI)
		if back: basis = Basis(Vector3.UP, PI) * basis
		add(bone, "prism", Transform3D(basis * Basis.from_scale(Vector3(size, size * 0.9, 0.012)), centre), kind)

static func _cached_mesh(hat: String) -> ArrayMesh:
	if _mesh_cache.has(hat): return _mesh_cache[hat]
	var b := Builder.new()
	var f := Vector3(0, 0, -1) # forward
	# legs: trousers, trainers
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var hip := REST[B_TH[i]]
		var knee := REST[B_SH[i]]
		var ankle := REST[B_FOOT[i]]
		b.capsule(B_TH[i], hip + Vector3(0, 0.02, 0), knee, 0.105, "pants")
		b.capsule(B_SH[i], knee, ankle + Vector3(0, 0.03, 0), 0.09, "pants")
		b.capsule(B_FOOT[i], ankle + Vector3(0, -0.005, 0.06), ankle + Vector3(0, 0.0, -0.17), 0.078, "shoe", Vector3(1.0, 1.0, 0.9))
		b.drum(B_FOOT[i], ankle + Vector3(0, -0.045, -0.055), Vector3(0.07, 0.03, 0.135), "dark")
		b.box(B_FOOT[i], ankle + Vector3(0, 0.055, -0.15), Vector3(0.09, 0.02, 0.03), "main")
	# torso: hips, belt, shirt, badge, collar
	b.capsule(B_PELVIS, REST[B_PELVIS] + Vector3(0, -0.07, 0), REST[B_SPINE] + Vector3(0, 0.02, 0), 0.185, "pants", Vector3(1.0, 1.0, 0.82))
	b.drum(B_SPINE, REST[B_SPINE] + Vector3(0, 0.0, 0.0), Vector3(0.185, 0.045, 0.152), "dark")
	b.capsule(B_CHEST, REST[B_SPINE] + Vector3(0, 0.07, 0), REST[B_NECK] + Vector3(0, -0.03, 0), 0.205, "main", Vector3(1.02, 1.0, 0.78))
	b.disc(B_CHEST, Vector3(0.085, 1.32, -0.163), 0.05, 0.012, "cream")
	b.slice(B_CHEST, Vector3(0.085, 1.32, -0.171), 0.046, "accent")
	b.ring(B_NECK, REST[B_NECK] + Vector3(0, 0.005, 0.0), 0.075, 0.03, "cream")
	# neck, head, face, hair, hat
	var r := HEAD_R
	var hc := Vector3(0, HEAD_Y, 0)
	b.capsule(B_NECK, REST[B_NECK] + Vector3(0, -0.03, 0), hc + Vector3(0, -0.05, 0), 0.05, "skin")
	b.sphere(B_HEAD, hc, Vector3(r, r * 1.05, r * 0.98), "skin")
	for sx: float in [-1.0, 1.0]:
		b.sphere(B_HEAD, hc + Vector3(sx * r * 0.36, -r * 0.04, -r * 0.88), Vector3(r * 0.25, r * 0.3, r * 0.14), "cream")
		b.sphere(B_HEAD, hc + Vector3(sx * r * 0.33, -r * 0.06, -r * 0.98), Vector3(r * 0.12, r * 0.17, r * 0.08), "eye")
		b.sphere(B_HEAD, hc + Vector3(sx * r * 1.0, -r * 0.05, 0), Vector3(r * 0.15, r * 0.25, r * 0.2), "skin")
	b.sphere(B_HEAD, hc + Vector3(0, -r * 0.1, -r * 0.99), Vector3(r * 0.13, r * 0.13, r * 0.12), "skin")
	b.sphere(B_HEAD, hc + Vector3(0, -r * 0.4, -r * 0.93), Vector3(r * 0.22, r * 0.045, r * 0.05), "eye")
	b.sphere(B_HEAD, hc + Vector3(0, r * 0.02, r * 0.14), Vector3(r * 1.03, r * 0.98, r * 0.98), "hair")
	if hat == "cap":
		b.sphere(B_HEAD, hc + Vector3(0, r * 0.3, 0), Vector3(r * 1.08, r * 0.88, r * 1.08), "main")
		b.sphere(B_HEAD, hc + Vector3(0, r * 0.42, -r * 0.95), Vector3(r * 0.92, r * 0.07, r * 0.7), "accent")
		b.disc(B_HEAD, hc + Vector3(0, r * 0.72, -r * 0.99), 0.034, 0.01, "cream")
	elif hat == "hardhat":
		b.sphere(B_HEAD, hc + Vector3(0, r * 0.36, 0), Vector3(r * 1.1, r * 0.9, r * 1.1), "main")
		b.drum(B_HEAD, hc + Vector3(0, r * 0.4, 0), Vector3(r * 1.3, r * 0.08, r * 1.3), "main")
		b.capsule(B_HEAD, hc + Vector3(0, r * 1.18, r * 0.95), hc + Vector3(0, r * 1.18, -r * 0.95), r * 0.12, "accent")
	elif hat == "beanie":
		b.sphere(B_HEAD, hc + Vector3(0, r * 0.34, 0), Vector3(r * 1.1, r * 0.9, r * 1.1), "main")
		b.sphere(B_HEAD, hc + Vector3(0, r * 1.35, 0), Vector3.ONE * r * 0.3, "accent")
	# arms: sleeves, forearms, gloves
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var shoulder := REST[B_UA[i]]
		var elbow := REST[B_FA[i]]
		var wrist := REST[B_HAND[i]]
		var sleeve := shoulder.lerp(elbow, 0.62)
		b.sphere(B_UA[i], shoulder, Vector3.ONE * 0.085, "main")
		b.capsule(B_UA[i], shoulder, sleeve, 0.078, "main")
		b.capsule(B_UA[i], sleeve, elbow, 0.058, "skin")
		b.capsule(B_FA[i], elbow, wrist, 0.055, "skin")
		b.capsule(B_FA[i], wrist + Vector3(0, 0.065, 0), wrist + Vector3(0, -0.01, 0), 0.062, "cream")
		b.sphere(B_HAND[i], wrist + Vector3(0, -0.055, 0), Vector3(0.082, 0.09, 0.082), "glove")
	# delivery backpack
	var bag := REST[B_PACK]
	b.box(B_PACK, bag, Vector3(0.36, 0.40, 0.22), "dark")
	b.box(B_PACK, bag + Vector3(0, 0.215, 0), Vector3(0.38, 0.05, 0.24), "main")
	b.box(B_PACK, bag + Vector3(0, 0.1, 0.112), Vector3(0.38, 0.05, 0.005), "cream")
	b.disc(B_PACK, bag + Vector3(0, -0.05, 0.12), 0.08, 0.012, "cream", true)
	b.slice(B_PACK, bag + Vector3(0, -0.05, 0.128), 0.07, "accent", true)
	for sx: float in [-1.0, 1.0]:
		b.box(B_CHEST, Vector3(sx * 0.12, 1.30, -0.158), Vector3(0.045, 0.3, 0.02), "dark")
	# one skinned mesh, one surface per material kind
	var mesh := ArrayMesh.new()
	for kind: String in KINDS:
		if not b.surfaces.has(kind): continue
		var s: Dictionary = b.surfaces[kind]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_INDEX] = s["i"]
		arrays[Mesh.ARRAY_BONES] = s["b"]
		arrays[Mesh.ARRAY_WEIGHTS] = s["w"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, kind)
	_mesh_cache[hat] = mesh
	return mesh

# ---------------------------------------------------------------- animation
func snap(state: Dictionary) -> void:
	_fresh = true
	_last_pos = global_position
	update(0.0, state, [])

func _pose_rest_stand() -> void:
	_pose({})

func update(dt: float, state: Dictionary, grips: Array = []) -> void:
	if not _built: return
	dt = clampf(dt, 0.0, 0.1)
	var paused := bool(state.get("paused", false))
	var pos := global_position
	var vel: Vector3
	if state.has("velocity") and state["velocity"] is Vector3:
		vel = state["velocity"]
	elif dt > 0.0 and not _fresh:
		vel = (pos - _last_pos) / dt
	else:
		vel = Vector3.ZERO
	_last_pos = pos
	var grounded := bool(state.get("grounded", true))
	var flop := maxf(float(state.get("flop", 0.0)), 0.0) ## seconds of dash flop left (courier_motion.gd flop_left, the pose's `flop`)
	var target_yaw := float(state.get("yaw", _yaw))
	if _fresh:
		_yaw = target_yaw
		_grounded = grounded
		_vy_prev = vel.y
		_last_vel = vel
		_air = 0.0 if grounded else 1.0
		_carry = 1.0 if bool(state.get("carrying", false)) else 0.0
		_speed = Vector2(vel.x, vel.z).length()
		_lie = 1.0 if flop > 0.0 else 0.0
		_getup = clampf(flop / GETUP, 0.0, 1.0)
		_dive = 0.0
		_fresh = false
	var turn := angle_difference(_yaw, target_yaw)
	if not paused:
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-16.0 * dt))
	global_basis = Basis(Vector3.UP, _yaw)
	if paused:
		_pose_current(grips, {"state": state})
		return
	var inv := Basis(Vector3.UP, _yaw).inverse()
	var local_vel := inv * vel
	var speed := Vector2(vel.x, vel.z).length()
	_speed = lerpf(_speed, speed, 1.0 - exp(-20.0 * dt))
	_clock += dt
	# airborne transitions and events
	if _grounded and not grounded and vel.y > 1.5:
		_kick = 1.0
		_crouch_v -= 1.2
		_lead = 1 - _lead
		jumped.emit()
	if not _grounded and grounded:
		var impact := maxf(_fall_peak, -_vy_prev)
		_fall_peak = 0.0
		_crouch_v += clampf(impact, 0.0, 14.0) * 1.3
		landed.emit(impact)
	if not grounded: _fall_peak = maxf(_fall_peak, -vel.y)
	_grounded = grounded
	_vy_prev = vel.y
	_air = move_toward(_air, 0.0 if grounded else 1.0, dt * (12.0 if grounded else 9.0))
	_carry = move_toward(_carry, 1.0 if bool(state.get("carrying", false)) else 0.0, dt * 6.0)
	_kick = move_toward(_kick, 0.0, dt * 2.5)
	# the belly flop (lies down fast, rises over the last GETUP s) and the dive (fast and airborne: pitched forward, arms ahead)
	_lie = move_toward(_lie, 1.0 if flop > 0.0 else 0.0, dt / LIE_IN)
	_getup = clampf(flop / GETUP, 0.0, 1.0)
	var diving := not grounded and flop <= 0.0 and _carry < 0.5 and Vector2(vel.x, vel.z).length() > DIVE_SPEED
	_dive = move_toward(_dive, 1.0 if diving else 0.0, dt * (9.0 if diving else 6.0))
	# acceleration in the courier frame (lean)
	var accel: Vector3
	if state.has("acceleration") and state["acceleration"] is Vector3:
		accel = state["acceleration"]
	elif dt > 0.0:
		accel = (vel - _last_vel) / dt
	else:
		accel = Vector3.ZERO
	_last_vel = vel
	if accel.length() < 0.5 and speed > 0.3 and grounded:
		accel = -vel.normalized() * 12.0 * minf(speed / 2.0, 1.0)
	var local_acc := inv * accel
	_acc_fwd = lerpf(_acc_fwd, clampf(-local_acc.z, -20.0, 20.0), 1.0 - exp(-10.0 * dt))
	_acc_side = lerpf(_acc_side, clampf(local_acc.x, -20.0, 20.0), 1.0 - exp(-10.0 * dt))
	var floor_target := Vector3.UP
	if state.has("floor_normal") and state["floor_normal"] is Vector3 and (state["floor_normal"] as Vector3).y > 0.3:
		floor_target = inv * (state["floor_normal"] as Vector3)
	_floor_n = _floor_n.lerp(floor_target, 1.0 - exp(-12.0 * dt)).normalized()
	var turn_rate := clampf(turn / maxf(dt, 0.001), -6.0, 6.0) if dt > 0.0 else 0.0
	var speed01 := clampf(_speed / 5.0, 0.0, 1.2)
	var lean_target := (0.03 + speed01 * 0.16 + _acc_fwd * 0.004) * (1.0 - 0.45 * _carry)
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-9.0 * dt))
	var roll_target := clampf(_acc_side * 0.004 - turn_rate * speed01 * 0.03, -0.25, 0.25)
	_roll = lerpf(_roll, roll_target, 1.0 - exp(-9.0 * dt))
	# landing / take-off spring (dip in metres, positive = lower)
	_crouch_v += (-380.0 * _crouch - 17.0 * _crouch_v) * dt
	_crouch += _crouch_v * dt
	_crouch = clampf(_crouch, -0.1, 0.26)
	# gait
	var run := smoothstep(2.0, 4.6, _speed) * (1.0 - _lie)
	var gait := smoothstep(0.2, 1.2, _speed) * (1.0 - _air) * (1.0 - _lie)
	var duty := lerpf(0.62, 0.4, run)
	var cycle_hz := maxf(0.8 + 0.14 * _speed, _speed * duty / 1.1)
	var previous_phase := _phase
	if grounded and speed > 0.15 and _lie < 0.5:
		_phase = fposmod(_phase + cycle_hz * dt, 1.0)
		if gait > 0.35:
			for i in 2:
				if fposmod(previous_phase + 0.5 * i, 1.0) > fposmod(_phase + 0.5 * i, 1.0):
					footstep.emit(i)
	var stance_len := _speed * duty / maxf(cycle_hz, 0.01)
	_pose_current(grips, {"run": run, "gait": gait, "duty": duty, "stance_len": stance_len, "state": state, "local_vel": local_vel, "dt": dt})

func _pose_current(grips: Array, extra: Dictionary) -> void:
	_pose(extra, grips)

# The full pose. `ctx` carries the per-frame gait numbers (empty keys = standing).
func _pose(ctx: Dictionary, grips: Array = []) -> void:
	var run: float = ctx.get("run", 0.0)
	var gait: float = ctx.get("gait", 0.0)
	var duty: float = ctx.get("duty", 0.6)
	var stance_len: float = ctx.get("stance_len", 0.0)
	var phase := _phase
	var look_yaw := 0.0
	var state: Dictionary = ctx.get("state", {})
	var lie := _lie * smoothstep(0.0, 1.0, _getup) ## lying amount: 1 flat, easing to 0 as the courier gets up
	var strait := maxf(lie, _dive) ## body held straight (arms ahead, legs trailing): lying or diving
	var tilt := maxf(_dive * DIVE_PITCH, lie * PI * 0.5)
	var skeleton_xf := _tilt_skeleton(tilt, lie)
	if state.has("look_at") and state["look_at"] is Vector3 and is_inside_tree():
		var to_target: Vector3 = to_local(state["look_at"])
		if Vector2(to_target.x, to_target.z).length_squared() > 0.01:
			look_yaw = clampf(atan2(-to_target.x, -to_target.z), -1.0, 1.0)
	var cos_mid := cos(TAU * (phase - duty * 0.5))
	var tw := lerpf(0.08, 0.2, run) * gait
	# pelvis
	var reach := REACH_FACTOR * (THIGH + SHIN)
	var vertical := sqrt(maxf(reach * reach - 0.25 * stance_len * stance_len, 0.04))
	var hip_joint := ANKLE_H + vertical
	var dip := lerpf(0.03, 0.07, run) * gait * (0.5 + 0.5 * cos(2.0 * TAU * (phase - duty * 0.5)))
	var breath := sin(_clock * 1.7)
	var pelvis_y := hip_joint + 0.02 - dip - _crouch * (1.0 - lie) - _carry * 0.0
	pelvis_y = lerpf(pelvis_y, 0.98 - _crouch * 0.5 + _kick * 0.03, _air)
	var sway := -0.02 * gait * cos_mid + 0.012 * sin(_clock * 0.45) * (1.0 - gait) * (1.0 - _air)
	var lean := (_lean + _crouch * 1.1 + maxf(_reach_lean, 0.0) * _carry) * (1.0 - strait)
	var pelvis_q := Quaternion(Vector3.UP, -tw * cos(TAU * phase)) * Quaternion(Vector3.BACK, 0.03 * gait * cos_mid - _roll * 0.3) * Quaternion(Vector3.RIGHT, -lean * 0.2)
	var spine_q := Quaternion(Vector3.UP, tw * cos(TAU * phase) + look_yaw * 0.25) * Quaternion(Vector3.BACK, -_roll * 0.35) * Quaternion(Vector3.RIGHT, -lean * 0.35 + 0.015 * breath * (1.0 - gait))
	var chest_q := Quaternion(Vector3.UP, tw * 0.7 * cos(TAU * phase) + look_yaw * 0.25) * Quaternion(Vector3.BACK, -_roll * 0.35) * Quaternion(Vector3.RIGHT, -lean * 0.45 + 0.02 * breath * (1.0 - gait))
	var pelvis_pos := Vector3(sway, pelvis_y, 0.0)
	var pelvis_g := Transform3D(Basis(pelvis_q), pelvis_pos)
	var spine_g := pelvis_g * Transform3D(Basis(spine_q), REST[B_SPINE] - REST[B_PELVIS])
	var chest_g := spine_g * Transform3D(Basis(chest_q), REST[B_CHEST] - REST[B_SPINE])
	var chest_world_q := chest_g.basis.get_rotation_quaternion()
	var pelvis_world_q := pelvis_q
	var spine_world_q := pelvis_q * spine_q
	var sk := _skeleton
	sk.set_bone_pose_position(B_PELVIS, pelvis_pos)
	sk.set_bone_pose_rotation(B_PELVIS, pelvis_q)
	sk.set_bone_pose_rotation(B_SPINE, spine_q)
	sk.set_bone_pose_rotation(B_CHEST, chest_q)
	# neck and head keep looking ahead while the torso leans
	var neck_q := Quaternion(Vector3.RIGHT, lean * 0.35 - 0.02 * breath * (1.0 - gait) + tilt * 0.42) * Quaternion(Vector3.UP, look_yaw * 0.4)
	var head_q := Quaternion(Vector3.RIGHT, lean * 0.3 - 0.1 * _air * (1.0 if _vy_prev < 0.0 else -1.0) * 0.0 + tilt * 0.3) * Quaternion(Vector3.UP, look_yaw * 0.6) * Quaternion(Vector3.BACK, _roll * 0.4)
	sk.set_bone_pose_rotation(B_NECK, neck_q)
	sk.set_bone_pose_rotation(B_HEAD, head_q)
	# backpack sways against the vertical motion of the pelvis
	_pack_v += (-260.0 * _pack - 18.0 * _pack_v - _crouch_v * 6.0) * 0.016
	_pack += _pack_v * 0.016
	_pack = clampf(_pack, -0.3, 0.3)
	sk.set_bone_pose_rotation(B_PACK, Quaternion(Vector3.RIGHT, _pack))
	# legs
	var chest_inv := chest_world_q.inverse()
	var thigh_world: Array = []
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var hip_pos := pelvis_g * (REST[B_TH[i]] - REST[B_PELVIS])
		var foot_idle := Vector3(sx * (HIP_X + 0.012), ANKLE_H, 0.0)
		var foot_gait := foot_idle
		var pitch_gait := 0.0
		var p := fposmod(phase + 0.5 * i, 1.0)
		var forward := 0.0
		if p < duty:
			var u := p / duty
			forward = stance_len * (0.5 - u)
			foot_gait.y += 0.05 * smoothstep(0.72, 1.0, u) * (0.4 + run)
			pitch_gait = lerpf(0.18, -0.35, smoothstep(0.55, 1.0, u)) * (1.0 - smoothstep(0.0, 0.2, u) * 0.0)
		else:
			var q := (p - duty) / (1.0 - duty)
			var e := q * q * (3.0 - 2.0 * q)
			forward = stance_len * (-0.5 + e)
			foot_gait.y += lerpf(0.12, 0.26, run) * pow(sin(PI * q), 0.9)
			pitch_gait = lerpf(-0.5, 0.3, q)
		foot_gait.z = -forward
		var foot_target := foot_idle.lerp(foot_gait, gait)
		var foot_pitch := pitch_gait * gait
		# stand on the slope under the courier: plane through the feet origin
		var slope_up := -(_floor_n.x * foot_target.x + _floor_n.z * foot_target.z) / maxf(_floor_n.y, 0.3)
		foot_target.y += clampf(slope_up, -0.5, 0.5) * (1.0 - _air)
		foot_pitch += atan2(_floor_n.z, _floor_n.y) * (1.0 - _air) * (1.0 - clampf((foot_gait.y - ANKLE_H) * 6.0, 0.0, 1.0))
		var ground := _two_bone(hip_pos, foot_target, THIGH, SHIN, Vector3(0, 0, -1))
		var thigh_dir: Vector3 = ground["upper"]
		var shin_dir: Vector3 = ground["lower"]
		# air pose: leading leg tucks forward, the other trails
		if _air > 0.001:
			var rising := clampf((_vy_prev + 3.0) / 8.0, 0.0, 1.0)
			var leader := i == _lead
			var thigh_a := lerpf(0.4, 1.0, rising) if leader else lerpf(-0.2, -0.3, rising)
			var knee_a := lerpf(0.3, 1.3, rising) if leader else lerpf(0.5, 1.1, rising)
			var up_a := _flex_dir(thigh_a, 0.0)
			var low_a := _flex_dir(thigh_a - knee_a, 0.0)
			thigh_dir = thigh_dir.slerp(up_a, _air)
			shin_dir = shin_dir.slerp(low_a, _air)
			foot_pitch = lerpf(foot_pitch, -0.35, _air)
		if strait > 0.001: # legs trail straight behind, the knees a little bent
			thigh_dir = thigh_dir.slerp(_flex_dir(-0.1, 0.0), strait)
			shin_dir = shin_dir.slerp(_flex_dir(-0.1 - 0.35, 0.0), strait)
			foot_pitch = lerpf(foot_pitch, -0.5, strait)
		var thigh_q_world := Quaternion(Vector3.DOWN, thigh_dir)
		var shin_q_world := Quaternion(Vector3.DOWN, shin_dir)
		sk.set_bone_pose_rotation(B_TH[i], pelvis_world_q.inverse() * thigh_q_world)
		sk.set_bone_pose_rotation(B_SH[i], thigh_q_world.inverse() * shin_q_world)
		var foot_q_world := Quaternion(Vector3.UP, sx * -0.12) * Quaternion(Vector3.RIGHT, foot_pitch)
		sk.set_bone_pose_rotation(B_FOOT[i], shin_q_world.inverse() * foot_q_world)
		thigh_world.append(thigh_q_world)
	# arms
	var avg_reach := 0.0
	var run_flex := lerpf(0.35, 1.35, run)
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var shoulder := chest_g * (REST[B_UA[i]] - REST[B_CHEST])
		var swing := lerpf(0.0, lerpf(0.5, 0.95, run), gait) * cos(TAU * fposmod(phase + 0.5 * (1 - i), 1.0))
		var idle_pitch := 0.05 + 0.03 * sin(_clock * 1.3 + sx)
		var abd := lerpf(0.13, lerpf(0.2, 0.3, run), gait)
		var pitch := idle_pitch + swing
		var flex := lerpf(0.15, run_flex, gait) + 0.35 * maxf(swing, 0.0) * gait
		# air: arms rise on take-off and spread while falling
		if _air > 0.001:
			var rising := clampf((_vy_prev + 3.0) / 8.0, 0.0, 1.0)
			pitch = lerpf(pitch, lerpf(0.7, 1.7, rising) + _kick * 0.5, _air)
			abd = lerpf(abd, lerpf(1.0, 0.4, rising), _air)
			flex = lerpf(flex, 0.3, _air)
		if strait > 0.001: # arms stretched ahead of the head; a little hop of the hands while getting up
			var hop := sin(PI * smoothstep(0.0, 1.0, _getup)) * 0.6 * _lie
			pitch = lerpf(pitch, 2.9 - hop, strait)
			abd = lerpf(abd, 0.28, strait)
			flex = lerpf(flex, 0.08 + hop * 0.5, strait)
		var upper_local := _arm_dir(pitch, abd * sx)
		var fore_local := _arm_dir(pitch + flex, abd * sx * 0.8)
		var upper_dir := chest_g.basis * upper_local
		var fore_dir := chest_g.basis * fore_local
		if _carry > 0.001:
			var target_local: Vector3
			if grips.size() == 2:
				target_local = skeleton_xf.affine_inverse() * to_local(grips[i])
			else:
				target_local = Vector3(sx * HOLD_SIDE, ANCHOR_OFFSET.y, -HOLD_FORWARD)
			avg_reach += shoulder.distance_to(target_local) * 0.5
			var wrist_target := target_local - (target_local - shoulder).normalized() * GLOVE_REACH
			var arm := _two_bone(shoulder, wrist_target, ARM_UP, ARM_FORE, Vector3(sx * 0.7, -1.0, 0.35))
			for refine in 2:
				wrist_target = target_local - (arm["lower"] as Vector3) * GLOVE_REACH
				arm = _two_bone(shoulder, wrist_target, ARM_UP, ARM_FORE, Vector3(sx * 0.7, -1.0, 0.35))
			upper_dir = upper_dir.slerp(arm["upper"], _carry * (1.0 - strait))
			fore_dir = fore_dir.slerp(arm["lower"], _carry * (1.0 - strait))
		var upper_q := Quaternion(Vector3.DOWN, upper_dir)
		var fore_q := Quaternion(Vector3.DOWN, fore_dir)
		sk.set_bone_pose_rotation(B_UA[i], chest_world_q.inverse() * upper_q)
		sk.set_bone_pose_rotation(B_FA[i], upper_q.inverse() * fore_q)
		sk.set_bone_pose_rotation(B_HAND[i], Quaternion.IDENTITY)
		var wrist := shoulder + upper_dir * ARM_UP + fore_dir * ARM_FORE
		_hand_pos[i] = skeleton_xf * (wrist + fore_dir * GLOVE_REACH)
	_reach_lean = lerpf(_reach_lean, clampf((avg_reach - 0.5) * 1.0, 0.0, 0.3), 0.15)

## The whole skeleton tilted forward by `tilt` rad about the hips (a dive in the air, 90 degrees flat for the belly flop). Flat on the floor
## (`lie` 1) the body axis is 0.2 m over the ground and centred on the capsule; while rising the toes stay on the floor.
func _tilt_skeleton(tilt: float, lie: float) -> Transform3D:
	var hips := REST[B_PELVIS]
	var rotation_about_hips := Basis(Vector3.RIGHT, -tilt)
	var down := clampf(lie * 4.0, 0.0, 1.0)
	var pivot := Vector3(0.0, lerpf(hips.y, hips.y * cos(tilt) + LIE_HEIGHT * sin(tilt), down), -LIE_CENTER * sin(tilt) * down)
	var xf := Transform3D(rotation_about_hips, pivot - rotation_about_hips * hips)
	if _skeleton != null: _skeleton.transform = xf
	return xf

## Direction of a limb that hangs down and is swung forward by `pitch` (rad) and out by `side` (rad, + = towards +X).
static func _arm_dir(pitch: float, side: float) -> Vector3:
	return Basis(Vector3.RIGHT, pitch) * (Basis(Vector3.BACK, side) * Vector3.DOWN)

static func _flex_dir(pitch: float, side: float) -> Vector3:
	return _arm_dir(pitch, side)

## Two-bone chain from `root` to `target`; the middle joint bends towards `pole`.
## Returns the directions of the two bones (unit vectors, root -> mid, mid -> end).
static func _two_bone(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Dictionary:
	var d := target - root
	var dist := clampf(d.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var side := pole - dir * pole.dot(dir)
	side = side.normalized() if side.length() > 0.0001 else Vector3.BACK
	var mid := root + dir * x + side * h
	var end := root + dir * dist
	return {"upper": (mid - root).normalized(), "lower": (end - mid).normalized()}
