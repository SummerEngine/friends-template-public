extends SkeletonModifier3D
## What the menu pet does on top of its clips, applied after them every frame:
##  - the gaze toward `look_target` (a world point), within limits and smoothed, as `yaw` and `pitch`; menu_pet.gd turns
##    the whole pet by it (`body_turn`). It does not turn the head bone: in windowed shots a head turned here left the
##    team cap (on the head's BoneAttachment3D) floating beside the head;
##  - the collar tag swings on a damped spring, pushed by how the collar moves (and by `kick`);
##  - now and then one ear twitches.
## Bones are found by name; a model without one of them just skips that part.

const HEAD := ["head", "Head"]
## The point the gaze is measured from (between the eyes); the head bone itself when the model has no face bone.
const FACE := ["face", "Face"]
const TAG := ["tag", "Tag"]
const EARS := [["ear_l", "ear_L", "ear.L"], ["ear_r", "ear_R", "ear.R"]]
## Head turn limits (radians) and how fast it follows (1/s). The model faces +Z.
const MAX_YAW := 0.66
const MAX_UP := 0.4
const MAX_DOWN := 0.3
const FOLLOW := 7.0
## Tag spring: stiffness (1/s^2), damping (1/s), how much collar acceleration pushes it, and its swing limit (radians).
const TAG_STIFFNESS := 70.0
const TAG_DAMPING := 3.5
const TAG_PUSH := 0.45
const TAG_LIMIT := 0.75
## Ear twitch: length (s), angle (radians), pause between twitches (s).
const TWITCH_TIME := 0.32
const TWITCH_ANGLE := 0.4
const TWITCH_PAUSE := Vector2(2.5, 7.0)

## World point to look at, and how much of the turn to apply (0 = the clip alone).
var look_target := Vector3.ZERO
var look_weight := 1.0
## Current gaze (radians), smoothed; read by menu_pet.gd and checks.
var yaw := 0.0
var pitch := 0.0
## How far the pet's body is turned by the gaze now (radians, set by menu_pet.gd): the gaze is measured as if it were not.
var body_turn := 0.0

var _tag_angle := Vector2.ZERO
var _tag_speed := Vector2.ZERO
var _tag_last := Vector3.ZERO
var _tag_velocity := Vector3.ZERO
var _tag_ready := false
var _twitch_left := 0.0
var _twitch_ear := -1
var _twitch_wait := 2.0
var _random := RandomNumberGenerator.new()

func _init() -> void:
	name = "PetMotion"
	_random.randomize()

## A nudge to the tag (a state change, a pat): `strength` in radians per second.
func kick(strength: float) -> void:
	_tag_speed += Vector2(_random.randf_range(-1.0, 1.0), _random.randf_range(0.3, 1.0)) * strength

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or delta <= 0.0: return
	_look(skeleton, delta)
	_swing_tag(skeleton, delta)
	_twitch(skeleton, delta)

func _look(skeleton: Skeleton3D, delta: float) -> void:
	var head := _bone(skeleton, HEAD)
	if head < 0: return
	var face := _bone(skeleton, FACE)
	var pose := skeleton.get_bone_global_pose(head)
	var eyes := skeleton.get_bone_global_pose(face).origin if face >= 0 else pose.origin
	var to := Basis(Vector3.UP, body_turn) * (skeleton.global_transform.affine_inverse() * look_target - eyes)
	var want_yaw := clampf(atan2(to.x, to.z), -MAX_YAW, MAX_YAW) * look_weight
	var want_pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -MAX_DOWN, MAX_UP) * look_weight
	var follow := 1.0 - exp(-FOLLOW * delta)
	yaw = lerpf(yaw, want_yaw, follow)
	pitch = lerpf(pitch, want_pitch, follow)

## A pendulum: the tag lags behind the acceleration of the point it hangs from and swings back.
func _swing_tag(skeleton: Skeleton3D, delta: float) -> void:
	var tag := _bone(skeleton, TAG)
	if tag < 0: return
	var pose := skeleton.get_bone_global_pose(tag)
	if not _tag_ready:
		_tag_ready = true
		_tag_last = pose.origin
		return
	var velocity := (pose.origin - _tag_last) / delta
	var accel := ((velocity - _tag_velocity) / delta).limit_length(40.0)
	_tag_last = pose.origin
	_tag_velocity = velocity
	# Rotating about +X swings a hanging tag toward -Z, about +Z toward +X.
	var push := Vector2(accel.z, -accel.x) * TAG_PUSH
	_tag_speed += (push - _tag_angle * TAG_STIFFNESS - _tag_speed * TAG_DAMPING) * delta
	_tag_angle = (_tag_angle + _tag_speed * delta).clampf(-TAG_LIMIT, TAG_LIMIT)
	var swing := Basis(Vector3.RIGHT, _tag_angle.x) * Basis(Vector3.BACK, _tag_angle.y)
	_set_global_rotation(skeleton, tag, Transform3D(swing * pose.basis, pose.origin))

func _twitch(skeleton: Skeleton3D, delta: float) -> void:
	if _twitch_left <= 0.0:
		_twitch_wait -= delta
		if _twitch_wait > 0.0: return
		_twitch_wait = _random.randf_range(TWITCH_PAUSE.x, TWITCH_PAUSE.y)
		_twitch_ear = _bone(skeleton, EARS[_random.randi() % EARS.size()])
		_twitch_left = TWITCH_TIME if _twitch_ear >= 0 else 0.0
		return
	_twitch_left = maxf(_twitch_left - delta, 0.0)
	var angle := sin(PI * (1.0 - _twitch_left / TWITCH_TIME)) * TWITCH_ANGLE
	var rotation := skeleton.get_bone_pose_rotation(_twitch_ear) * Quaternion(Vector3.RIGHT, angle)
	skeleton.set_bone_pose_rotation(_twitch_ear, rotation)

## Sets `bone`'s pose so that its model-space transform is `target` (rotation only; it keeps its position and scale).
func _set_global_rotation(skeleton: Skeleton3D, bone: int, target: Transform3D) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_pose := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var local := parent_pose.affine_inverse() * target
	skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())

static func _bone(skeleton: Skeleton3D, names: Array) -> int:
	for bone_name: String in names:
		var index := skeleton.find_bone(bone_name)
		if index >= 0: return index
	return -1
