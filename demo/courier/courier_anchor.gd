extends RefCounted
## Authority-side stand-in for a drawn courier: the authority builds no rig. It keeps the last accepted
## anchor of an owner pose (the point the painting hangs from), or falls back to body position + offset.
const ANCHOR_OFFSET := Vector3(0.0, 1.0, 0.0)

var _body: CharacterBody3D
var _anchor := Vector3.ZERO
var _has_anchor := false

func setup(body: CharacterBody3D) -> void:
	_body = body

func set_pose(position: Vector3) -> bool:
	if not position.is_finite(): return false
	return set_anchor(position + ANCHOR_OFFSET)

func set_anchor(anchor_point: Vector3) -> bool:
	if not anchor_point.is_finite(): return false
	_anchor = anchor_point
	_has_anchor = true
	return true

func anchor() -> Vector3:
	if _has_anchor: return _anchor
	return (_body.global_position if _body != null else Vector3.ZERO) + ANCHOR_OFFSET

func clear() -> void:
	_has_anchor = false
