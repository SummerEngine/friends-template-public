extends RefCounted
## The gameplay camera, one instance per view (two in local split screen). First person by default (update_first_person): the
## eye at EYE_HEIGHT, yaw and pitch from the look input. A rig with set_first_person (character/character_rig.gd) hides its body
## from this camera and draws view arms in front of it (idle hands, the glass grips, the slap); any other rig shows all but its
## head. Third person (update) is a dev / settings option and a mode's choice (modes.json `camera`: set_shoulder_view).
## Third person orbits the focus point from behind and above
## (about 45 degrees down: the view stays top-down, the look input tilts it between PITCH_LOW and PITCH_HIGH) on a spring arm:
## the focus is smoothed (LAG_SPEED_H along the floor, LAG_SPEED in height), the arm grows with the spread of the framed points, it is pulled in by a shape cast against camera
## blockers (and while static geometry hides a target), the orientation follows the look input without lag. The courier's own
## body is hidden while the camera is close. Client only; nothing here is authoritative. API: docs/painting-api.md.
## The shoulder view (set_shoulder_view, the show): the same arm, lower and closer (SHOULDER_ARM), the view centre raised over the courier's head
## and moved to its right (the body stands low on the left, the way ahead fills the screen), the look input tilting between SHOULDER_PITCH_LOW and
## SHOULDER_PITCH_HIGH; nobody but the own courier is kept in view, and a wall between the courier and that view centre pulls it in (the cast
## starts at the courier, so the camera is never put behind a wall).
## The stage view (set_stage_view, the tile stage rounds, docs/party-show.md "The stage camera and feel"): high and far over the arena, a free orbit (yaw
## over the full circle, pitch STAGE_PITCH_LOW .. STAGE_PITCH_HIGH), the courier a small figure (STAGE_ARM from its feet at STAGE_FOV: about an eighth of the frame's height)
## whose feet stand at STAGE_FEET_Y of the frame, whatever the pitch (the view centre is raised to fit). The focus follows level with STAGE_LAG_H and in height the
## floor under the courier, not its jumps: frozen in the air, a landing on another layer is caught up with tau 1 / STAGE_LAG_V (0.11 s), a fall trails by at most
## STAGE_AIR_TRAIL m. The race levels' stage view (`air_follow`) follows a pad's throw up and down instead (STAGE_AIR_*; a normal jump stays frozen). Blockers are ignored (the cage has no collision, the tiles are no camera blockers), the floors over the camera are hidden by the shell.
const ARM_LENGTH := 8.0 ## m, default distance from the focus
const ARM_MIN := 3.5 ## wheel zoom range
const ARM_MAX := 16.0 ## also the most a framed view pulls back
const ZOOM_STEP := 0.7 ## m per wheel step
const PITCH_DEFAULT := -45.0 ## degrees: the view looks down this much when a round or a seat starts
const PITCH_LOW := -75.0 ## degrees: the steepest the look input tilts it ...
const PITCH_HIGH := -15.0 ## ... and the flattest (never along the floor)
const LOOK_AHEAD := 2.0 ## m: the view centres this far ahead of the focus along the yaw (more of the way ahead, less wall behind)
const EYE_HEIGHT := 1.2 ## m over the feet: below the eyes of the big heads (never inside the own head); others' heads sit a bit above
const EYE_FORWARD := 0.18 ## m: the eye sits this far in front of the courier's centre, along the yaw
## Carrying the glass the eye sits higher and behind the hands (the shell passes it, game_run.gd _eye_feet): you look over the glass
## at the path ahead, both hands low in the view on its grips.
const CARRY_EYE_HEIGHT := 1.5
const CARRY_EYE_BACK := 0.45
const FP_FOV := 80.0 ## first person: vertical field of view by default (wide: the world reads big and a little goofy) ...
const FP_FOV_MIN := 45.0 ## ... settable in this range (settings "FieldOfView", set_fov)
const FP_FOV_MAX := 100.0
const FP_PITCH_DEFAULT := -12.0 ## degrees: a little down, the floor and the hazards ahead in view
const FP_PITCH_LOW := -85.0
const FP_PITCH_HIGH := 85.0
const FP_LAG_SPEED := 25.0 ## 1/s: the eye follows the head this fast (steps and landings stay smooth)
## Meshes of the own courier the first-person view never draws: the head and what is worn on it (names of the character's parts).
const HEAD_WORDS := ["head", "eye", "lid", "brow", "nose", "teeth", "mouth", "ear", "neck", "hair", "hat", "face", "beard", "glasses"]
const CAMERA_LAYER := 256 ## physics layer of camera blockers: the level world puts large static blocks (>= 1.5 m) on it
const CLEAR_GAP := 0.35 ## m a swung camera (fx.around) stays off a blocker in its way
const CLEAR_MIN := 0.9 ## m it never comes closer to its point than that
const SHOULDER_ARM := 5.4 ## the shoulder view's arm (m, zoomable)
const SHOULDER := {"shoulder": 0.8, "rise": 1.35, "ahead": 0.0} ## update() options of the shoulder view: view centre m to the right, m over the focus, m ahead
const SHOULDER_PITCH_LOW := -65.0 ## degrees
const SHOULDER_PITCH_HIGH := -3.0
const SHOULDER_PITCH_DEFAULT := -13.0 ## a little down: the floor and the obstacles ahead in view
const PROBE_RADII := [0.3, 0.2, 0.12] ## the widest probe that fits at the pivot wins
const LAG_SPEED := 10.0 ## 1/s, how fast the focus catches up in height (a step up or a landing does not pump the picture)
const LAG_SPEED_H := 30.0 ## 1/s, and along the floor: close to rigid like the stage view (STAGE_LAG_H). At 10 the courier ran 0.5 m (5 m/s) to 1.1 m (the dash) ahead of the view's centre and, turning back, the same behind it: a swing of 1 to 2 m across the screen as it strafed ("ahead, then behind"); at 30 it is 0.17 to 0.37 m
const RELEASE_SPEED := 4.0 ## 1/s: the arm snaps in at once and eases back out ...
const RELEASE_MAX_SPEED := 6.0 ## ... at most this many m/s
const VIEW_MIN_ARM := 2.5 ## pulling in for the partner never goes closer than this (m)
const VIEW_STEPS := [0.8, 0.6, 0.45, 0.3]
const FRAME_BASE := 3.0 ## shared view: arm = 3 m + 0.8 x the spread of the framed points
const FRAME_PER_METRE := 0.8
const MOUSE_DEGREES_PER_PIXEL := 0.15 ## at sensitivity 1
const TOUCH_DEGREES_PER_PIXEL := 0.2 ## per design pixel (1280 x 720) at sensitivity 1
const VERTICAL_FOV := 60.0
const STAGE_ARM := 12.1 ## m, the stage view's orbit radius: the 3D distance from the camera to the courier's feet (3.5 tiles of 3.5 m; the courier's silhouette is 12.2 % of the frame height, measured on a render: 11.9 % at 12.25 m); zoomable STAGE_ARM_MIN .. STAGE_ARM_MAX
const STAGE_ARM_MIN := 6.0
const STAGE_ARM_MAX := 24.0
const STAGE_FOV := 65.0 ## degrees (vertical): the start view's field of view
const STAGE_PITCH_LOW := -60.0 ## degrees (the view's axis; the courier's feet stand about 14.5 degrees lower in the frame): the steepest the look input tilts the stage view ...
const STAGE_PITCH_HIGH := -3.0 ## ... and the flattest
const STAGE_PITCH_DEFAULT := -12.4 ## the start view: the courier standing still
## The stage view's pitch table (the view axis, degrees down; the feet stand STAGE_FEET_Y of the frame, about 14.6 degrees under the axis, so the view ray to the feet is these plus 14.6:
## 27 idle, about 35.6 running). The targets: standing 12.4 | running 13.9, 16.0, 20.8 |
## one second after a landing on a lower floor 24.0 | a look-up recovery swing 28.3 (the player's own orbit input here: STAGE_PITCH_LOW .. HIGH reach it).
## Ours: 12.4 standing, 12.4 + STAGE_RUN_PITCH = 21 at the full run, 24 for a second after a landing a floor lower.
const STAGE_RUN_PITCH := 8.6 ## degrees the view tips further down at the full run (settles at 21)
const STAGE_RUN_TAU := 0.4 ## s, how fast the run tips the view ...
const STAGE_RUN_TAU_OUT := 0.6 ## ... and how fast it comes back when the courier stops
const STAGE_LAND_PITCH := 3.0 ## degrees further down while the courier has just landed a floor lower (24 against 21 running)
const STAGE_LAND_DROP := 0.8 ## m: a landing this far under the view's height counts as a landing a floor lower
const STAGE_LAND_HOLD := 1.0 ## s the landing swing is held ...
const STAGE_LAND_TAU := 0.15 ## ... it comes in with this time constant ...
const STAGE_LAND_TAU_OUT := 0.5 ## ... and goes out with this one
const STAGE_FEET_Y := 0.704 ## where the courier's feet stand in the frame's height (from the top; it stands in the middle of the width), whatever the pitch
const STAGE_FOCUS_HEIGHT := 1.0 ## m: the point the shell passes the camera is this far over the feet (game_run.gd CAMERA_FOCUS)
const STAGE_LAG_H := 30.0 ## 1/s, the level follow: close to rigid, the courier trails the picture by its speed / this (0.4 m at the run)
const STAGE_LAG_V := 9.0 ## 1/s, the height follow after a landing on another floor (a tau of 0.11 s)
const STAGE_AIR_TRAIL := 4.0 ## m: in a fall the view trails the courier by at most this (a jump never moves it: frozen in the air); 4 m is a quarter of the frame
const STAGE_AIR_RISE_DEAD := 2.0 ## m (air follow, the race levels): the courier may rise this far over the view centre before the picture goes up with it: a normal jump (apex 1.4 m) stays frozen, a pad's throw is followed
const STAGE_AIR_RISE_TAU := 0.15 ## s, how the picture follows a rise past the dead zone (an exponential approach: no overshoot; at a pad's 20 m/s the courier stays 2 + 3 m over the centre)
const STAGE_AIR_FALL_DEAD := 0.5 ## m (air follow): a fall may take the courier this far under the view centre ...
const STAGE_AIR_FALL_TAU := 0.08 ## s ... past it the picture follows the fall with this time constant (a pad's arc comes down at 14 m/s: the courier stays about 1.7 m under the centre, 0.11 of the frame)
const SMALL_SCREEN_HEIGHT := 480.0 ## px: a viewport lower than this (a phone held sideways) draws the stage view closer ...
const SMALL_SCREEN_ARM := 0.82 ## ... at this share of the arm: the courier stays readable
const BODY_HIDE_DISTANCE := 0.9 ## the own courier disappears closer than this ...
const BODY_RESTORE_DISTANCE := 1.2 ## ... and comes back beyond this
const BODY_HEIGHT := 1.0 ## measured to the courier's torso
const BODY_FIRST_BIT := 18 ## render layers 19 and 20 are reserved for the owned couriers' meshes (even and odd slots share them: up to ten slots)
const BODY_BITS := (1 << 18) | (1 << 19)

var first_person := true
var fp_fov := FP_FOV
var sensitivity := Vector2.ONE
var inverted := Vector2.ONE
var arm_length := ARM_LENGTH
var shoulder_view := false
var stage_view := false
var stage_air_follow := false ## the stage view of a race level (not of a tile stage round): the picture follows a throw's rise and fall (STAGE_AIR_*), where the tile rounds freeze it in the air
var third_low := PITCH_LOW ## degrees: the steepest the look input tilts the third-person view ...
var third_high := PITCH_HIGH ## ... and the flattest
var third_default := PITCH_DEFAULT
var control_yaw := 0.0 ## the yaw of the last update(): movement is relative to it

## The show's item effects on this view (modes/show/items/, set every frame by the items view; {} for none): "roll" (radians about the view axis), "fov" (degrees added to the lens),
## "zoom" (0..1: the share of the way the camera moves towards "point", a world position: the TIKTOK's close-up on the character) with "range" (m from the point); "around" (a yaw, radians, 0 faces -Z)
## makes the camera swing round the point to the side that yaw faces (a face from the front), ending "range" m away and "rise" m over the point (default 0.1), always looking at it, pulled in where a
## blocker (physics layers "mask", default CAMERA_LAYER) stands in its way. Applied after every update.
var fx := {}
var _camera: Camera3D
var _fx_fov := 0.0 ## the degrees `fx` added to the lens last time (taken off first: other code sets the lens)
var _fx_clear := 1.0 ## 0..1: how much of the way out to its place the camera of a swing (`fx.around`) is allowed, a blocker in the way shortens it
var _pending_mouse := Vector2.ZERO
var _pending_touch := Vector2.ZERO
var _lagged := Vector3.ZERO
var _stage_anchor := Vector3.ZERO
var _stage_run := 0.0 ## 0..1: how much of the full run the stage view has taken in (it tips the view down by STAGE_RUN_PITCH)
var _stage_swing := 0.0 ## 0..1: how much of the landing swing the view has taken in (STAGE_LAND_PITCH)
var _stage_hold := 0.0 ## s left of the landing swing's hold
var _stage_was_grounded := true
var _stage_ready := false
var _lag_ready := false
var _arm_fraction := 1.0
var _arm_ready := false
var _probe := SphereShape3D.new()
var _bodies := {} ## slot -> {"rig": WeakRef, "hidden": bool}
var _fp_eye := Vector3.ZERO
var _fp_ready := false
var _fp_frames := 0

static func configure_projection(camera: Camera3D) -> void:
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = VERTICAL_FOV
	camera.near = 0.1

func configure(camera: Camera3D) -> void:
	_camera = camera
	configure_projection(camera)
	camera.fov = fp_fov if first_person else _third_fov()

## First person or third (a dev / settings switch). Rebinds the own body's meshes for the new view.
func set_first_person(on: bool) -> void:
	first_person = on
	if _camera != null: _camera.fov = fp_fov if on else _third_fov()
	for slot: int in _bodies:
		var rig: Node3D = (_bodies[slot] as Dictionary).rig.get_ref()
		if rig != null: own_body(rig, slot)
	_fp_ready = false

## The shoulder view (a mode's `camera: third`, game_run.gd) in place of the top-down third person: closer, lower, over the shoulder.
func set_shoulder_view(on: bool) -> void:
	shoulder_view = on
	_apply_third()

## The stage view (a tile stage round, game_run.gd) in place of the shoulder view: high and far, a free orbit. Off again for every other round.
## `air_follow`: the race levels' variant that follows a pad's throw vertically (STAGE_AIR_*); the tile rounds (25-28) keep the picture frozen in the air.
func set_stage_view(on: bool, air_follow := false) -> void:
	air_follow = on and air_follow
	if stage_view == on and stage_air_follow == air_follow: return
	stage_air_follow = air_follow
	if stage_view == on:
		reset_lag()
		return
	stage_view = on
	_apply_third()
	reset_lag()

## The arm, the pitch limits and the field of view of the third-person view in force.
func _apply_third() -> void:
	if stage_view:
		arm_length = STAGE_ARM
		third_low = STAGE_PITCH_LOW
		third_high = STAGE_PITCH_HIGH
		third_default = STAGE_PITCH_DEFAULT
	else:
		arm_length = SHOULDER_ARM if shoulder_view else ARM_LENGTH
		third_low = SHOULDER_PITCH_LOW if shoulder_view else PITCH_LOW
		third_high = SHOULDER_PITCH_HIGH if shoulder_view else PITCH_HIGH
		third_default = SHOULDER_PITCH_DEFAULT if shoulder_view else PITCH_DEFAULT
	if _camera != null and not first_person: _camera.fov = _third_fov()

func _third_fov() -> float:
	return STAGE_FOV if stage_view else VERTICAL_FOV

## The first-person field of view (degrees, vertical), kept in FP_FOV_MIN .. FP_FOV_MAX.
func set_fov(degrees: float) -> void:
	fp_fov = clampf(degrees, FP_FOV_MIN, FP_FOV_MAX)
	if _camera != null and first_person: _camera.fov = fp_fov

# ------------------------------------------------------------------ look input
func apply_settings(values: Dictionary) -> void:
	if values.has("FieldOfView"): set_fov(float(values.FieldOfView))
	sensitivity = Vector2(clampf(float(values.get("XSensitivity", 1.0)), 0.1, 5.0), clampf(float(values.get("YSensitivity", 1.0)), 0.1, 5.0))
	inverted = Vector2(-1.0 if bool(values.get("InvertX", false)) else 1.0, -1.0 if bool(values.get("InvertY", false)) else 1.0)

func queue_look(screen_delta: Vector2) -> void:
	_pending_mouse += screen_delta

func queue_touch_look(design_delta: Vector2) -> void:
	_pending_touch += design_delta

func discard_look() -> void:
	_pending_mouse = Vector2.ZERO
	_pending_touch = Vector2.ZERO

## The queued mouse and touch input as a change of (yaw, pitch) in radians.
func consume_look() -> Vector2:
	var look := Vector2(-deg_to_rad(_pending_mouse.x * MOUSE_DEGREES_PER_PIXEL), -deg_to_rad(_pending_mouse.y * MOUSE_DEGREES_PER_PIXEL)) * sensitivity
	look += Vector2(-deg_to_rad(_pending_touch.x * TOUCH_DEGREES_PER_PIXEL), -deg_to_rad(_pending_touch.y * TOUCH_DEGREES_PER_PIXEL))
	discard_look()
	return look * inverted

## Applies the queued look input to a control rotation: the new (yaw, pitch), yaw wrapped, pitch clamped.
func look(yaw: float, pitch: float) -> Vector2:
	var change := consume_look()
	return Vector2(wrapf(yaw + change.x, -PI, PI), clamp_pitch(pitch + change.y))

## A pitch (radians, negative looks down) kept inside the view's limits: FP_PITCH_LOW .. FP_PITCH_HIGH in first person,
## PITCH_LOW .. PITCH_HIGH in third.
func clamp_pitch(pitch: float) -> float:
	if first_person: return clampf(pitch, deg_to_rad(FP_PITCH_LOW), deg_to_rad(FP_PITCH_HIGH))
	return clampf(pitch, deg_to_rad(third_low), deg_to_rad(third_high))

func default_pitch() -> float:
	return deg_to_rad(FP_PITCH_DEFAULT if first_person else third_default)

func zoom(steps: float) -> void:
	if stage_view: arm_length = clampf(arm_length + steps * ZOOM_STEP, STAGE_ARM_MIN, STAGE_ARM_MAX)
	else: arm_length = clampf(arm_length + steps * ZOOM_STEP, ARM_MIN, ARM_MAX)

func reset_lag() -> void:
	_lag_ready = false
	_arm_ready = false
	_fp_ready = false
	_stage_ready = false
	_stage_swing = 0.0
	_stage_hold = 0.0
	_stage_was_grounded = true

## First person: the eye at `feet` + EYE_HEIGHT (and EYE_FORWARD along the yaw), looking along yaw / pitch. `carry_back`: carrying,
## the flat way from the hands back to the eye (the eye goes to CARRY_EYE_HEIGHT, CARRY_EYE_BACK along it).
func update_first_person(dt: float, feet: Vector3, yaw: float, pitch: float, carry_back := Vector3.ZERO) -> void:
	if _camera == null or not _camera.is_inside_tree(): return
	control_yaw = yaw
	var heading := Basis(Vector3.UP, yaw)
	var eye := feet + Vector3.UP * EYE_HEIGHT + heading * Vector3(0.0, 0.0, -EYE_FORWARD)
	if carry_back != Vector3.ZERO: eye = feet + Vector3.UP * CARRY_EYE_HEIGHT + carry_back.normalized() * CARRY_EYE_BACK
	if not _fp_ready:
		_fp_ready = true
		_fp_eye = eye
	else: _fp_eye = _fp_eye.lerp(eye, 1.0 - exp(-dt * FP_LAG_SPEED))
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), _fp_eye)
	_fp_frames += 1
	if _fp_frames % 30 == 0: # a look change or a customizer rebuilds the rig's meshes: bind them again
		for slot: int in _bodies:
			var rig: Node3D = (_bodies[slot] as Dictionary).rig.get_ref()
			if rig != null: own_body(rig, slot)
	_update_bodies()

# ------------------------------------------------------------------ own body
## This view's courier: its meshes move to a private render layer so the camera can hide them when it gets close.
## Call again after the rig has built (or rebuilt) its meshes.
func own_body(rig: Node3D, slot: int) -> void:
	if rig == null: return
	var hook := rig.has_method("set_first_person") and _camera != null
	if hook:
		rig.set_first_person(first_person, _camera) # the rig hides its body from this camera and draws its view arms
		if first_person:
			_bodies[slot] = {"rig": weakref(rig), "hidden": false}
			return
	var meshes := rig.find_children("*", "MeshInstance3D", true, false)
	# First person hides only the head and what is on it; the body, the arms and the hands stay in view. A rig without named head
	# parts (the code-built courier) is hidden whole.
	var heads := meshes.filter(func(mesh: Node) -> bool: return _on_head(mesh, rig))
	for mesh: MeshInstance3D in meshes:
		var hidden := not first_person or heads.is_empty() or heads.has(mesh)
		mesh.layers = 1 << (BODY_FIRST_BIT + slot % 2) if hidden else 1
	var hidden := bool((_bodies.get(slot, {}) as Dictionary).get("hidden", false))
	_bodies[slot] = {"rig": weakref(rig), "hidden": hidden}

## Show every body again and forget them (the view stops following a courier).
func clear_bodies() -> void:
	_bodies.clear()
	if _camera != null and is_instance_valid(_camera): _camera.cull_mask |= BODY_BITS

## A mesh of the head: its name, or a holder above it (a hat or hair socket on the head), names a head part.
static func _on_head(mesh: Node, rig: Node) -> bool:
	var node := mesh
	while node != null and node != rig:
		var name := str(node.name).to_lower()
		for word: String in HEAD_WORDS:
			if name.contains(word): return true
		if node is BoneAttachment3D and str((node as BoneAttachment3D).bone_name).to_lower().contains("head"): return true
		node = node.get_parent()
	return false

func _update_bodies() -> void:
	var mask := _camera.cull_mask | BODY_BITS
	if first_person:
		for slot: int in _bodies: mask &= ~(1 << (BODY_FIRST_BIT + slot % 2)) # the own head is never drawn in its own view
		_camera.cull_mask = mask
		return
	for slot: int in _bodies:
		var row: Dictionary = _bodies[slot]
		var rig: Node3D = row.rig.get_ref()
		if rig == null or not rig.is_visible_in_tree():
			row.hidden = false
			continue
		var separation := _camera.global_position.distance_to(rig.global_position + Vector3.UP * BODY_HEIGHT)
		if separation < BODY_HIDE_DISTANCE: row.hidden = true
		elif separation > BODY_RESTORE_DISTANCE: row.hidden = false
		if row.hidden: mask &= ~(1 << (BODY_FIRST_BIT + slot % 2))
	_camera.cull_mask = mask

# ------------------------------------------------------------------ the arm
static func _points(targets) -> PackedVector3Array:
	if targets is PackedVector3Array: return targets
	var points := PackedVector3Array()
	if targets is Vector3: points.append(targets)
	elif targets is Array:
		for point in targets: points.append(point)
	return points

## Places the camera. `focus`: the point to orbit (the courier's chest); `yaw`, `pitch`: the control rotation;
## `targets`: a point or points that should stay visible (the partner, the painting, the balloon). options:
## {arm: float (distance), mask: int (blockers), frame: bool (the arm grows with the spread of the targets and of
## `frame_points`, up to ARM_MAX), frame_points: points that only widen the frame (teammates), ahead: float (look-ahead, m,
## default LOOK_AHEAD), shoulder: float (m, the view centre moves this far to the courier's right), rise: float (m, and this far up)}.
## The shoulder view fills in SHOULDER for what the options leave out and keeps no targets. The stage view takes only `focus` (the shell passes the courier's feet + STAGE_FOCUS_HEIGHT),
## the angles and {grounded: bool, the courier stands on a floor: its height is followed then, not a jump's; run: 0 to 1, the share of the full run}.
func update(dt: float, focus: Vector3, yaw: float, pitch: float, targets = null, options := {}) -> void:
	if _camera == null or not _camera.is_inside_tree(): return
	control_yaw = yaw
	if stage_view:
		_update_stage(dt, focus, yaw, pitch, bool(options.get("grounded", true)), float(options.get("run", 0.0)))
		return
	if shoulder_view:
		options = SHOULDER.merged(options, true)
		targets = null
	var mask := int(options.get("mask", CAMERA_LAYER))
	var courier := focus
	var side := float(options.get("shoulder", 0.0))
	var rise := float(options.get("rise", 0.0))
	focus += Basis(Vector3.UP, yaw) * Vector3(side, 0.0, -float(options.get("ahead", LOOK_AHEAD))) + Vector3.UP * rise
	if side != 0.0 or rise != 0.0: focus = _clip_pivot(courier, focus, mask)
	var points := _points(targets)
	var length := float(options.get("arm", arm_length))
	if bool(options.get("frame", false)):
		var spread := 0.0
		for point in points + _points(options.get("frame_points", PackedVector3Array())): spread = maxf(spread, Vector2(point.x - focus.x, point.z - focus.z).length())
		length = clampf(FRAME_BASE + FRAME_PER_METRE * spread, length, maxf(length, ARM_MAX))
	var anchor := _smooth_focus(focus, dt)
	var orientation := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var motion := anchor + orientation.z * length - focus
	var space := _camera.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = motion
	query.collision_mask = mask
	query.margin = 0.0
	query.collide_with_areas = false
	var fraction := 0.0
	var fits := false
	for radius: float in PROBE_RADII:
		_probe.radius = radius
		if not space.intersect_shape(query, 1).is_empty(): continue # touching at the pivot: try a thinner probe
		var swept := space.cast_motion(query)
		fraction = swept[0] if swept.size() == 2 else 1.0
		fits = true
		break
	if fits and not points.is_empty() and fraction > 0.0:
		fraction = _view_fraction(space, focus, motion, fraction, points, mask)
	# The arm snaps in at once (geometry must never cover the carriers) and eases back out, so a passing pole or a
	# sliding wall does not pump the picture. Only the arm is smoothed: the orientation is the control rotation.
	if not _arm_ready or fraction <= _arm_fraction:
		_arm_fraction = fraction
	else:
		var eased := (fraction - _arm_fraction) * (1.0 - exp(-dt * RELEASE_SPEED))
		_arm_fraction += minf(eased, RELEASE_MAX_SPEED * dt / maxf(motion.length(), 0.001))
	_arm_ready = true
	_camera.global_transform = Transform3D(orientation, focus + motion * _arm_fraction)
	_update_bodies()
	_apply_fx()

## The stage view: no arm cast (nothing in a stage round blocks the camera). The camera stands STAGE_ARM (the arm) from the courier's FEET, on the line that reaches them
## at STAGE_FEET_Y of the frame whatever the pitch (the feet are always the angle below the view axis that puts them there: the view centre is raised to fit), so the
## courier keeps its size and its spot while the look input tilts the view; the full run tips it STAGE_RUN_PITCH further down (to 21 degrees), a landing a floor lower STAGE_LAND_PITCH more for a second (`run`, 0 to 1). The picture follows
## level at STAGE_LAG_H. In height it is FROZEN while the courier is in the air (a jump moves the courier up the frame, not the picture), follows a landing with
## tau 1 / STAGE_LAG_V, and in a fall trails the courier by at most STAGE_AIR_TRAIL m. With `stage_air_follow` (the race levels) the air is not frozen: a rise past STAGE_AIR_RISE_DEAD
## over the view centre is followed with tau STAGE_AIR_RISE_TAU, a fall past STAGE_AIR_FALL_DEAD under it with STAGE_AIR_FALL_TAU, so a pad's throw stays in the frame, a small jump stays calm.
func _update_stage(dt: float, courier: Vector3, yaw: float, pitch: float, grounded: bool, run: float) -> void:
	var length := arm_length * (SMALL_SCREEN_ARM if _small_screen() else 1.0)
	if not _stage_ready:
		_stage_ready = true
		_stage_anchor = courier
		_stage_run = run
	else:
		var gap := courier - _stage_anchor
		_stage_anchor.x += gap.x * (1.0 - exp(-dt * STAGE_LAG_H))
		_stage_anchor.z += gap.z * (1.0 - exp(-dt * STAGE_LAG_H))
		if grounded and not _stage_was_grounded and _stage_anchor.y - courier.y > STAGE_LAND_DROP: _stage_hold = STAGE_LAND_HOLD # it landed a floor lower: the view tips further down for a second
		if grounded: _stage_anchor.y += gap.y * (1.0 - exp(-dt * STAGE_LAG_V))
		elif stage_air_follow:
			if gap.y > STAGE_AIR_RISE_DEAD: _stage_anchor.y += (courier.y - STAGE_AIR_RISE_DEAD - _stage_anchor.y) * (1.0 - exp(-dt / STAGE_AIR_RISE_TAU))
			elif gap.y < -STAGE_AIR_FALL_DEAD: _stage_anchor.y += (courier.y + STAGE_AIR_FALL_DEAD - _stage_anchor.y) * (1.0 - exp(-dt / STAGE_AIR_FALL_TAU))
		else: _stage_anchor.y = minf(_stage_anchor.y, courier.y + STAGE_AIR_TRAIL)
		var run_goal := clampf(run, 0.0, 1.0)
		_stage_run += (run_goal - _stage_run) * (1.0 - exp(-dt / (STAGE_RUN_TAU if run_goal > _stage_run else STAGE_RUN_TAU_OUT)))
		var swing_goal := 1.0 if _stage_hold > 0.0 else 0.0
		_stage_swing += (swing_goal - _stage_swing) * (1.0 - exp(-dt / (STAGE_LAND_TAU if swing_goal > _stage_swing else STAGE_LAND_TAU_OUT)))
		_stage_hold = maxf(_stage_hold - dt, 0.0)
	_stage_was_grounded = grounded
	control_yaw = yaw
	var tipped := pitch - deg_to_rad(STAGE_RUN_PITCH) * _stage_run - deg_to_rad(STAGE_LAND_PITCH) * _stage_swing
	var below := atan((2.0 * STAGE_FEET_Y - 1.0) * tan(deg_to_rad(STAGE_FOV) * 0.5)) # the feet's angle under the view axis
	var feet := _stage_anchor - Vector3.UP * STAGE_FOCUS_HEIGHT
	_camera.global_transform = Transform3D(Basis.from_euler(Vector3(tipped, yaw, 0.0)), feet + Basis.from_euler(Vector3(tipped - below, yaw, 0.0)).z * length)
	_update_bodies()
	_apply_fx()

## The item effects on the camera just placed (see `fx`).
func _apply_fx() -> void:
	if _camera == null: return
	var fov_now := float(fx.get("fov", 0.0))
	if not is_equal_approx(fov_now, _fx_fov):
		_camera.fov = clampf(_camera.fov - _fx_fov + fov_now, 20.0, 120.0)
		_fx_fov = fov_now
	if fx.is_empty():
		_fx_clear = 1.0
		return
	var xf := _camera.global_transform
	var zoom := clampf(float(fx.get("zoom", 0.0)), 0.0, 1.0)
	if zoom > 0.0 and fx.get("point") is Vector3:
		var point: Vector3 = fx.point
		if fx.has("around"):
			xf.origin = _swing(xf.origin, point, float(fx.around), float(fx.get("range", 2.4)), float(fx.get("rise", 0.1)), zoom)
			xf.origin = _clear_view(point, xf.origin, int(fx.get("mask", CAMERA_LAYER)))
			xf.basis = xf.basis.slerp(Basis.looking_at(point - xf.origin, Vector3.UP), clampf(zoom * 2.5, 0.0, 1.0))
		else:
			xf.origin = xf.origin.lerp(point - (xf.basis * Vector3(0.0, 0.0, -1.0)) * float(fx.get("range", 2.4)), zoom)
			xf.basis = xf.basis.slerp(Basis.looking_at(point - xf.origin, Vector3.UP), zoom)
	var roll := float(fx.get("roll", 0.0))
	if roll != 0.0: xf.basis = xf.basis * Basis(Vector3(0.0, 0.0, 1.0), roll)
	_camera.global_transform = xf

## `origin` pulled in towards `point` where a camera blocker (physics layers `mask`) stands in the way, never closer than CLEAR_MIN m: it shortens at once and lengthens again slowly.
func _clear_view(point: Vector3, origin: Vector3, mask: int) -> Vector3:
	var reach := point.distance_to(origin)
	if reach < 0.01: return origin
	var ratio := 1.0
	var hit := _camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point, origin, mask))
	if not hit.is_empty():
		var at: Vector3 = hit.position
		ratio = clampf((point.distance_to(at) - CLEAR_GAP) / reach, minf(CLEAR_MIN / reach, 1.0), 1.0)
	_fx_clear = ratio if ratio < _fx_clear else lerpf(_fx_clear, ratio, 0.1)
	return point + (origin - point) * _fx_clear

## Where the camera is `zoom` of the way on an arc round `point` from where it is to `range_m` away on the side `yaw` faces, radius and height eased to `range_m` and `rise` on the way. The arc turns the
## same way every frame (from behind the character that is half a turn), so it never flips.
static func _swing(from: Vector3, point: Vector3, yaw: float, range_m: float, rise: float, zoom: float) -> Vector3:
	var off := from - point
	var start := atan2(off.z, off.x)
	var goal := atan2(-cos(yaw), -sin(yaw))
	var turn := wrapf(goal - start + PI * 0.5, 0.0, TAU) - PI * 0.5 # in -90..270 degrees: from behind the character (180) it goes the same way each frame
	var angle := start + turn * zoom
	var radius := lerpf(Vector2(off.x, off.z).length(), range_m, zoom)
	return point + Vector3(cos(angle) * radius, lerpf(off.y, rise, zoom), sin(angle) * radius)

## A phone held sideways: the viewport is lower than SMALL_SCREEN_HEIGHT.
func _small_screen() -> bool:
	var viewport := _camera.get_viewport()
	return viewport != null and viewport.get_visible_rect().size.y < SMALL_SCREEN_HEIGHT

## The view centre `to`, cut short where a camera blocker stands between the courier `from` and it (a wall at the courier's shoulder).
func _clip_pivot(from: Vector3, to: Vector3, mask: int) -> Vector3:
	_probe.radius = PROBE_RADII[1]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = mask
	query.margin = 0.0
	query.collide_with_areas = false
	var space := _camera.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return from
	var swept := space.cast_motion(query)
	return from + (to - from) * (swept[0] if swept.size() == 2 else 1.0)

func _smooth_focus(focus: Vector3, dt: float) -> Vector3:
	if not _lag_ready:
		_lag_ready = true
		_lagged = focus
	else:
		var gap := focus - _lagged
		var level := 1.0 - exp(-dt * LAG_SPEED_H)
		_lagged += Vector3(gap.x * level, gap.y * (1.0 - exp(-dt * LAG_SPEED)), gap.z * level)
	return _lagged

## The arm is shortened (never below VIEW_MIN_ARM) while geometry covers one of the points.
func _view_fraction(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, fraction: float, points: PackedVector3Array, mask: int) -> float:
	var span := motion.length()
	if span < 0.001: return fraction
	for step: float in [1.0] + VIEW_STEPS:
		var candidate := fraction * step
		if step < 1.0 and candidate * span < VIEW_MIN_ARM: break
		var eye := from + motion * candidate
		var clear := true
		for point in points:
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point, mask)).is_empty():
				clear = false
				break
		if clear: return candidate
	return fraction
