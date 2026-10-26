extends Node3D
## The carried painting. No rig and no physics body: the pose is derived from the two couriers' anchors, a roll and a
## height offset; the break rule is a shape query against layer 8 (hit blocks and hazards) after a grace period.
##
## Frame (painting local space): x = along the carry axis (from anchor A towards anchor B), y = across, z = the face
## normal (up at roll 0). Roll turns the painting around the axis through the two anchors.
## The visual (style/carry_item.gd) exists on the client roles only; the authority keeps the same pose and break logic
## without drawing anything. API: docs/painting-api.md.
const CarryItem := preload("res://style/carry_item.gd")

const SIZE := Vector3(3.25, 1.25, 0.05) ## along, across, thickness (m)
const BREAK_SIZE := Vector3(3.25, 1.25, 0.1) ## the break box: the same outline, a little deeper
const BREAK_GRACE := 2.0 ## seconds after a reset in which nothing breaks the painting
const BREAK_LAYER := 8 ## physics layer of hit blocks and hazards
const BLOCKER_LAYER := 1024 ## solid stand-in for the carriers' own capsules (see make_blocker)
const BLOCKER_END_INSET := 0.7 ## the blocker is shorter by a capsule diameter so the carriers can stand at the ends
## The blocker stands upright through the glass (yaw only, never rolled or pitched with it), this tall and this wide: a capsule
## that runs into it is stopped sideways. A thin rolled slab let the capsules stand on it and threw them up when it tilted.
const BLOCKER_HEIGHT := 4.0
const BLOCKER_WIDTH := 0.6
const GRIP_ALONG := 1.5 ## the hands hold the short end bars, a little inside the edge (carriers stand 3.5 m apart: 0.25 m in front of each anchor) ...
const GRIP_ACROSS := 0.25 ## ... 0.5 m apart, matching the courier shoulders ...
const GRIP_LIFT := 0.1 ## ... slightly above the plane
const ROLL_SPEED := 2.0943951 ## rad/s (120 degrees)
const ROLL_LIMIT := 1.3962634 ## rad (80 degrees)
const HEIGHT_SPEED := 2.25 ## m/s
const HEIGHT_LIMIT := 0.5 ## m, up and down

var role := "local" ## "authority" (no visuals), "local" or "replica"
var anchor_a := Vector3(-1.75, 0.0, 0.0)
var anchor_b := Vector3(1.75, 0.0, 0.0)
var roll := 0.0
var height := 0.0
var broken := false
var hit_name := ""
var age := 0.0 ## seconds since the last reset, advanced by step()

var _holder: Node3D
var _item_node: Node3D
var _blocker: AnimatableBody3D
var _break_shape := BoxShape3D.new()

## Builds the visual on the client roles. Call once, after add_child.
func configure(new_role: String) -> void:
	role = new_role
	_break_shape.size = BREAK_SIZE
	if role == "authority" or _holder != null: return
	_holder = Node3D.new()
	_holder.name = "Item"
	# item frame (x across, y up, z along) -> painting frame (x along, y across, z up)
	_holder.basis = Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT)
	add_child(_holder)
	_make_item()

func _make_item() -> void:
	_item_node = CarryItem.build_intact()
	_holder.add_child(_item_node)

## Order handover (landscape -> portrait): swap the intact item for the active one with a small pop.
## Only the look changes. No-op on the authority.
func set_carry_item() -> void:
	if _holder == null: return
	_holder.remove_child(_item_node)
	_item_node.queue_free()
	_make_item()
	if not is_inside_tree(): return
	_item_node.scale = Vector3.ONE * 0.45
	create_tween().tween_property(_item_node, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_intact_visible(value: bool) -> void:
	if _holder != null: _holder.visible = value

## Where the painting hangs for the given anchors, roll and height offset.
static func pose_for(a: Vector3, b: Vector3, roll_angle: float, height_offset: float) -> Transform3D:
	var axis := b - a
	if axis.length_squared() < 0.0001: axis = Vector3.RIGHT
	axis = axis.normalized()
	var across := Vector3.UP.cross(axis)
	if across.length_squared() < 0.001: across = Vector3.FORWARD
	across = across.normalized().rotated(axis, roll_angle)
	return Transform3D(Basis(axis, across, axis.cross(across)).orthonormalized(), (a + b) * 0.5 + Vector3.UP * height_offset)

func desired_transform() -> Transform3D:
	return pose_for(anchor_a, anchor_b, roll, height)

## The hands' targets of a carrier for a painting pose: [left_world, right_world]. Slot 0 stands at the A end, slot 1 at
## the B end; both face the painting, so the left hand sits on opposite sides of the axis for the two slots.
static func grips_for(pose: Transform3D, slot: int) -> Array:
	var along := -GRIP_ALONG if slot == 0 else GRIP_ALONG
	var left := GRIP_ACROSS if slot == 0 else -GRIP_ACROSS
	return [pose * Vector3(along, left, GRIP_LIFT), pose * Vector3(along, -left, GRIP_LIFT)]

func grip_points(slot: int) -> Array:
	return grips_for(global_transform if is_inside_tree() else transform, slot)

## Roll input, axis -1..1 (positive turns towards +roll), applied for dt seconds.
func roll_input(axis: float, dt: float) -> void:
	roll = clampf(roll + axis * dt * ROLL_SPEED, -ROLL_LIMIT, ROLL_LIMIT)

## Height input, axis -1..1, applied for dt seconds.
func height_input(axis: float, dt: float) -> void:
	height = clampf(height + axis * dt * HEIGHT_SPEED, -HEIGHT_LIMIT, HEIGHT_LIMIT)

## A fresh painting at the given anchors: roll and height cleared, intact, age 0, no hit.
func reset(a: Vector3, b: Vector3) -> void:
	anchor_a = a
	anchor_b = b
	roll = 0.0
	height = 0.0
	age = 0.0
	broken = false
	hit_name = ""
	_place(desired_transform())
	set_intact_visible(true)

## One tick: follow the anchors, then test the break box. Replicas call this only to place the painting; a broken
## painting stays where it broke.
func step(dt: float) -> void:
	age += dt
	if broken: return
	var pose := desired_transform()
	_place(pose)
	if age < BREAK_GRACE or not is_inside_tree(): return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _break_shape
	query.transform = pose
	query.collision_mask = BREAK_LAYER
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 4)
	if hits.is_empty():
		hit_name = ""
		return
	var collider = hits[0].get("collider")
	break_with(str(collider.name) if collider != null else "world", 0.0)

## Break for a reason the shell knows (kill volume, grip loss). `min_age` is the grace for this rule: -1 uses
## BREAK_GRACE, 0 breaks at once.
func break_with(tag: String, min_age := -1.0) -> void:
	var grace := BREAK_GRACE if min_age < 0.0 else min_age
	if broken or age < grace: return
	broken = true
	hit_name = tag

func _place(pose: Transform3D) -> void:
	if is_inside_tree(): global_transform = pose
	else: transform = pose
	_place_blocker(pose)

## The blocker upright at the painting's centre, along the flat carry axis.
func _place_blocker(pose: Transform3D) -> void:
	if _blocker == null: return
	var along := pose.basis.x * Vector3(1, 0, 1)
	along = along.normalized() if along.length() > 0.001 else Vector3.RIGHT
	_blocker.transform = pose.affine_inverse() * Transform3D(Basis(along, Vector3.UP, along.cross(Vector3.UP)), pose.origin)

## The solid stand-in against the owner's own capsule (layer 1024): an upright box along the carry axis, as long as the painting
## shortened by a capsule diameter. A child of the painting placed with every pose (upright: _place_blocker); the shell adds
## BLOCKER_LAYER to the capsule's mask. Idempotent.
func make_blocker() -> AnimatableBody3D:
	if _blocker != null: return _blocker
	_blocker = AnimatableBody3D.new()
	_blocker.name = "Blocker"
	_blocker.sync_to_physics = false
	_blocker.collision_layer = BLOCKER_LAYER
	_blocker.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(SIZE.x - BLOCKER_END_INSET, 0.1), BLOCKER_HEIGHT, BLOCKER_WIDTH)
	shape.shape = box
	_blocker.add_child(shape)
	add_child(_blocker)
	_place_blocker(global_transform if is_inside_tree() else transform)
	return _blocker

func set_blocker_enabled(on: bool) -> void:
	if _blocker == null: make_blocker()
	_blocker.collision_layer = BLOCKER_LAYER if on else 0
