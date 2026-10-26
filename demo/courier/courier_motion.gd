extends RefCounted
## Movement of one courier: a capsule CharacterBody3D (origin at the feet) driven at a fixed tick.
## The caller owns the body, the inputs and the clock; this object keeps only the small state that
## makes movement feel right (coyote time, jump buffer, surface, pending launch, the mover under the
## feet). Everything is plain data, deterministic for equal inputs and equal physics worlds.
## Facing: forward is -Z at yaw 0.

const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.8
const WALK_SPEED := 5.0
const MIN_ANALOG_SPEED := 0.2
const ACCEL := 15.0
const BRAKE := 20.0
const FRICTION := 8.0
const FALL_BRAKE := 15.0
const AIR_CONTROL := 0.75
const GRAVITY := 17.0
const MAX_FALL := 40.0
const JUMP_SPEED := 7.0
const COYOTE := 0.25
const JUMP_BUFFER := 0.15
const FLOOR_MAX_ANGLE_DEG := 55.0
const FLOOR_SNAP := 0.35
const MAX_STEP := 0.45
const PULL_DISTANCE := 5.0
const PULL_STRENGTH := 0.8
const MOVER_LAYER := 16
const LAYER_COURIER := 2
const MASK_WORLD := 1 | 16
## One-way floors (a tile stage round, set_floors): floor k of the stack is a collision layer of its own (levels/step_tiles.gd TILE_LAYER_BASE << k) and the body's mask holds
## the layers of the floors whose top is at or under its feet (FLOOR_REACH over them), so it stands on its floor and every floor below it, jumps up through the floor above
## and lands on it, and is never wedged under a floor. A floor already in the mask stays in it until the feet are FLOOR_HOLD under its top (a warned tile sinks by its
## thickness; a fall through a hole passes the floor's own edge).
const FLOOR_BASE := 2048 ## levels/step_tiles.gd TILE_LAYER_BASE
const FLOOR_BITS := FLOOR_BASE * 511
const FLOOR_REACH := 0.02
const FLOOR_HOLD := 0.6
## Stage rounds' movement feel (set_stage, a tile stage round: docs/party-show.md "The stage camera and feel"), in our metres (a tile of 3.5 m, a
## 1.8 m courier): the run 3.6 tiles/s = 12.6 m/s, 95 % of it in 0.22 s, a stop in 0.15 s; the jump's apex 3.15 m (0.9 tile) and 0.54 s of air (23.3 m/s up, gravity 86.4, the
## same falling), which carries about two tiles at the run; no dash (the input's dash is ignored). Every other round keeps the constants above. Ice (set_surface)
## still overrides friction, braking and air control.
const STAGE_FEEL := {"walk": 12.6, "accel": 55.0, "brake": 84.0, "friction": 18.0, "air_control": 0.5, "fall_brake": 20.0, "gravity": 86.4, "jump": 23.3, "max_step": 0.6}
## Slippery ground preset (set_surface({"ice": true})).
const ICE := {"friction": 1.0, "braking": 3.0, "air_control": 0.25}
## Slime slope (set_surface({"slime": downhill})): low friction like ice, and a constant push of SLIME_PUSH m/s^2 along the slope's downhill (a unit planar vector, level-local x / z)
## on the ground (up to SLIME_MAX m/s) and in the air after it (no air brake, so a jump keeps its speed, up to SLIME_AIR_MAX); a jump off the slime adds SLIME_HOP m/s along the slope.
const SLIME := {"friction": 0.6, "braking": 1.0, "air_control": 0.35}
const SLIME_PUSH := 6.0
const SLIME_MAX := 11.0       ## the ground slide's top speed (m/s)
const SLIME_AIR_MAX := 15.0   ## the top speed of a slide that hops (m/s): jumps add speed, the ground does not
const SLIME_HOP := 2.0
# Conveyor belt (set_belt): the ground under the feet moves at this level-local planar velocity (world x, z; levels are not rotated). A grounded courier's velocity is
# taken relative to it for the ground rules (turn, accelerate, brake, friction) and the belt velocity is added back: standing still is carried at the belt's speed,
# walking against it nets the difference, and what it carries stays in the air after a jump (the air rules take over from there).

## Dash (the input's `dash`): a quick lunge along the move input (the facing when idle) at DASH_SPEED for DASH_TIME, with a slight lift that
## sails over the gravity (the arc), DASH_COOLDOWN from its start, and one per airtime (landing gives it back). Plain motion: the owner's own
## physics like walking, so it travels as the same owner pose (docs/courier-api.md).
const DASH_SPEED := 11.0 ## m/s: about 2.2 x the walk
const DASH_TIME := 0.3
const DASH_COOLDOWN := 1.5 ## s from the start of a dash to the next one (shared by the ground dash and the air dash)
const DASH_LIFT := 3.2 ## m/s upward at the start of an air dash (a ground dash gets DASH_HOP)
const DASH_HOP := 1.8
const DASH_GRAVITY := 0.25 ## the share of gravity while dashing
const DASH_BUFFER := 0.12 ## s a press waits for the cooldown or the landing
## The dash's penalty (an option, `dash_flop`, off unless the mode asks: modes.json `dash_flop`, set_dash_flop; the show leaves it off, its dash costs only the
## cooldown and works in the air as a burst of control): the first time the courier is grounded again after a dash it flops on its belly: FLOP_TIME s (FLOP_GETUP of it
## getting up) with no steering, no jump, no new dash, facing locked; the carried speed is cut to FLOP_SPEED and braked at FLOP_BRAKE (about
## a metre of belly slide). A dash that runs into a wall or an obstacle ends at once and stuns WALL_STUN s with a small push back (with the option off the dash just ends
## there, no stun and no push). A launch (pad, bumper, bonk) ends the flop: the throw is the move then. The owner pose carries the time left (`flop`, owner_pose_wire.gd).
const FLOP_TIME := 1.15
const FLOP_GETUP := 0.3 ## s: the rig's getting-up at the end (courier_rig.gd GETUP)
const FLOP_SPEED := 4.0 ## m/s: the most planar speed a flop starts with
const FLOP_BRAKE := 10.0 ## m/s^2
const WALL_STUN := 1.8
const WALL_PUSH := 2.5 ## m/s back from the wall
const WALL_HEAD_ON := 0.7 ## -(wall normal . dash direction) at least: a head-on hit (a glancing wall just slides)

var grounded := false
var acceleration := Vector3.ZERO
var yaw := 0.0
var floor_normal := Vector3.ZERO
var platform: Node3D = null
var dash_left := 0.0 ## s of dash still to go (a view may lean the body into it)
var stage := false ## the stage feel is on (set_stage)
var dash_flop := false ## the dash's penalty is on (set_dash_flop): the belly flop after it and the stun of a dash into a wall
var dash_cooldown := 0.0 ## s until the next dash may start
var flop_left := 0.0 ## s of flop / wall stun still to go (a view lies the body down while it is above 0)
## The show's item effects on this courier (modes/show/items/, game_run.gd item_mods): "freeze" (no steering, jump or dash: a hand holds it, a call, a dance), "speed" (walk and
## acceleration multiplier: BOOST), "jump" (jump speed multiplier: SUPER JUMP), "air_jumps" (int: that many more jumps in the air, one per press, each 0.92 of a jump's speed:
## SUPER JUMP) and "dash" (dash speed multiplier). The manager's rules (modes/show/manager/) add "no_jump" (the jump press is ignored), "no_dash" (the dash press is ignored), "gravity" (gravity
## multiplier: the moon jump) and "ice" (the ice's friction under the feet unless the surface already has its own). Empty for none; set every tick by the shell (set_mods).
var mods := {}

var _coyote := 0.0
var _air_jumps_used := 0 ## the air jumps (mods "air_jumps") spent since the courier last stood on something
var _jump_was_down := false ## input.jump last tick (an air jump wants a fresh press, not a held button)
var _buffer := 0.0
var _surface := {}
var _belt := Vector2.ZERO
var _slime_air := Vector2.ZERO ## the downhill of the slime slope the courier last stood on, kept in the air until the next landing (zero when it last stood on anything else)
var _launch := {}
var _platform_frame := Transform3D.IDENTITY
var _platform_velocity := Vector3.ZERO
var _fall_speed := 0.0
var _dash_dir := Vector2.ZERO
var _dash_buffer := 0.0
var _dash_air_used := false
var _flop_pending := false ## a dash was started and the landing flop has not happened yet
var _configured := false
var _kc := KinematicCollision3D.new()
var _floor_cos := cos(deg_to_rad(FLOOR_MAX_ANGLE_DEG))
var _feel := {} ## the constants in force: STAGE_FEEL in a stage round, empty otherwise (every lookup falls back to the constant above)
var _solid := false ## the body's mask has LAYER_COURIER (stage rounds)
var _floor_tops := PackedFloat32Array() ## world heights of the tops of the tile floors of a stage round, top floor first (set_floors); none outside
var _floor_mask := 0 ## the floor bits in the body's mask now

static func make_body(body_name: String) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = body_name
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	shape.position.y = CAPSULE_HEIGHT * 0.5
	body.add_child(shape)
	body.collision_layer = LAYER_COURIER
	body.collision_mask = MASK_WORLD
	return body

func setup(body: CharacterBody3D) -> void:
	body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	body.floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE_DEG)
	body.floor_snap_length = FLOOR_SNAP
	body.floor_stop_on_slope = true
	body.floor_constant_speed = true
	body.floor_block_on_wall = true
	body.max_slides = 6
	body.platform_floor_layers = 0
	body.platform_wall_layers = 0
	body.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	body.up_direction = Vector3.UP
	yaw = body.rotation.y
	_configured = true

## The stage feel on or off (a tile stage round, game_run.gd sets it every tick from the level): STAGE_FEEL in place of the walk, jump and air constants,
## and the couriers solid for each other (step() sets the body's mask).
func set_mods(values: Dictionary) -> void:
	mods = values

func set_stage(on: bool) -> void:
	stage = on
	_feel = STAGE_FEEL if on else {}

## The dash's penalty on or off (game_run.gd and the owner path set it from modes.json `dash_flop`). Off: a dash costs the cooldown only.
func set_dash_flop(on: bool) -> void:
	dash_flop = on
	if not on:
		flop_left = 0.0
		_flop_pending = false

## The tile floors of the round played, as the world heights of their tops (levels/level_world.gd tile_floors; an empty list outside a stage round): step() keeps the body's
## mask to the floors under its feet. Floors are numbered from the top: floor k is the layer FLOOR_BASE << k.
func set_floors(tops: PackedFloat32Array) -> void:
	_floor_tops = tops

## The floor bits for a body at `feet` height (a pure function of the floors, the height and the bits held now).
func floor_mask(feet: float) -> int:
	var bits := 0
	for k in _floor_tops.size():
		var bit := FLOOR_BASE << k
		var top := _floor_tops[k]
		if feet >= top - FLOOR_REACH or ((_floor_mask & bit) != 0 and feet >= top - FLOOR_HOLD): bits |= bit
	return bits

## Ground feel under the feet: {} = normal ground (and no belt), {"ice": true} = ICE, or any of friction / braking / air_control. A belt is separate (set_belt):
## a surface that is not empty (the stagger's ice) leaves it alone, {} puts it away too.
func set_surface(d: Dictionary) -> void:
	if bool(d.get("ice", false)): _surface = ICE.duplicate()
	elif d.has("slime"): _surface = SLIME.duplicate()
	else: _surface = {}
	if d.has("slime"): _surface["slime"] = d["slime"]
	for key: String in ["friction", "braking", "air_control"]:
		if d.has(key): _surface[key] = float(d[key])
	if d.is_empty(): _belt = Vector2.ZERO

## The belt under the courier's feet (planar, m/s; ZERO for none), set every tick before step() (levels/level_world.gd apply_effects).
func set_belt(v: Vector2) -> void:
	_belt = v

func launch(v: Vector3, override_xy: bool, override_z: bool) -> void:
	_launch = {"v": v, "xy": override_xy, "z": override_z}

func reset_clock() -> void:
	_coyote = 0.0
	_buffer = 0.0

func teleport(body: CharacterBody3D, pos: Vector3) -> void:
	body.global_position = pos
	body.velocity = Vector3.ZERO
	grounded = false
	floor_normal = Vector3.ZERO
	acceleration = Vector3.ZERO
	platform = null
	_platform_velocity = Vector3.ZERO
	_launch = {}
	_belt = Vector2.ZERO
	_slime_air = Vector2.ZERO
	_fall_speed = 0.0
	_floor_mask = 0
	dash_left = 0.0
	dash_cooldown = 0.0
	_dash_air_used = false
	_dash_buffer = 0.0
	flop_left = 0.0
	_flop_pending = false
	reset_clock()

## Spawn / epoch reset: position, facing and every piece of motion state.
func reset(body: CharacterBody3D, pos: Vector3, facing_yaw: float) -> void:
	teleport(body, pos)
	_surface = {}
	_belt = Vector2.ZERO
	_slime_air = Vector2.ZERO
	yaw = facing_yaw
	body.rotation = Vector3(0.0, facing_yaw, 0.0)

func capture(body: CharacterBody3D = null) -> Dictionary:
	var d := {"coyote": _coyote, "buffer": _buffer, "surface": _surface.duplicate(), "belt": _belt, "launch": _launch.duplicate(), "yaw": yaw,
		"grounded": grounded, "floor_normal": floor_normal, "acceleration": acceleration, "fall_speed": _fall_speed,
		"platform": String(platform.get_path()) if is_instance_valid(platform) and platform.is_inside_tree() else "",
		"platform_frame": _platform_frame, "platform_velocity": _platform_velocity,
		"dash_left": dash_left, "dash_cooldown": dash_cooldown, "dash_dir": _dash_dir, "dash_air_used": _dash_air_used, "flop_left": flop_left, "flop_pending": _flop_pending, "slime_air": _slime_air}
	if body != null:
		d["transform"] = body.transform
		d["velocity"] = body.velocity
	return d

func restore(d: Dictionary, body: CharacterBody3D) -> void:
	if d.has("transform"): body.transform = d["transform"]
	if d.has("velocity"): body.velocity = d["velocity"]
	_coyote = float(d.get("coyote", 0.0))
	_buffer = float(d.get("buffer", 0.0))
	_surface = (d.get("surface", {}) as Dictionary).duplicate()
	_slime_air = d.get("slime_air", Vector2.ZERO)
	_belt = d.get("belt", Vector2.ZERO)
	_launch = (d.get("launch", {}) as Dictionary).duplicate()
	yaw = float(d.get("yaw", body.rotation.y))
	grounded = bool(d.get("grounded", false))
	floor_normal = d.get("floor_normal", Vector3.ZERO)
	acceleration = d.get("acceleration", Vector3.ZERO)
	_fall_speed = float(d.get("fall_speed", 0.0))
	_platform_frame = d.get("platform_frame", Transform3D.IDENTITY)
	_platform_velocity = d.get("platform_velocity", Vector3.ZERO)
	dash_left = float(d.get("dash_left", 0.0))
	dash_cooldown = float(d.get("dash_cooldown", 0.0))
	_dash_dir = d.get("dash_dir", Vector2.ZERO)
	_dash_air_used = bool(d.get("dash_air_used", false))
	flop_left = float(d.get("flop_left", 0.0))
	_flop_pending = bool(d.get("flop_pending", false))
	var path := str(d.get("platform", ""))
	platform = body.get_node_or_null(NodePath(path)) as Node3D if path != "" and body.is_inside_tree() else null

## Planar velocity on the ground: turns towards the input, accelerates up to `top`, brakes when idle or too fast.
static func ground_velocity(v: Vector2, dir: Vector2, friction: float, braking: float, dt: float, accel_scale := 1.0, walk := WALK_SPEED, accel := ACCEL) -> Vector2:
	var top := maxf(walk * minf(dir.length(), 1.0), MIN_ANALOG_SPEED)
	var speed := v.length()
	var has_input := dir.length_squared() > 0.000001
	if not has_input or speed > top:
		var floor_speed := top if has_input else 0.0
		var new_speed := maxf(speed - braking * dt, floor_speed)
		v = v.normalized() * new_speed if speed > 0.0001 else Vector2.ZERO
		if not has_input and v.length_squared() <= 0.01: v = Vector2.ZERO
	else:
		v -= (v - dir.normalized() * speed) * minf(dt * friction, 1.0)
	if has_input:
		var limit := maxf(v.length(), top)
		v = (v + dir * accel * accel_scale * dt).limit_length(limit)
	return v

static func air_velocity(v: Vector2, dir: Vector2, control: float, dt: float, walk := WALK_SPEED, accel := ACCEL, fall_brake := FALL_BRAKE) -> Vector2:
	if v.length_squared() < 0.0625: control = minf(1.0, control * 2.0)
	return ground_velocity(v, dir, 0.0, fall_brake, dt, control, walk, accel)

func step(body: CharacterBody3D, input: Dictionary, dt: float) -> Dictionary:
	if not _configured: setup(body)
	var events := {"jumped": false, "landed": false, "land_speed": 0.0, "left_ground": false, "stepped": false, "started_moving": false, "dashed": false, "flopped": false, "wall_stun": false}
	if stage: # the couriers are solid for each other (game_run.gd _sync_courier_bodies gives the bodies it meets the layer)
		body.collision_mask |= LAYER_COURIER
		_solid = true
	elif _solid:
		body.collision_mask &= ~LAYER_COURIER
		_solid = false
	if not _floor_tops.is_empty() or _floor_mask != 0: # the floors under the feet, before anything moves
		_floor_mask = floor_mask(body.global_position.y) if not _floor_tops.is_empty() else 0
		body.collision_mask = (body.collision_mask & ~FLOOR_BITS) | _floor_mask
	if bool(mods.get("freeze", false)): # an item holds the courier: it stands, whatever its player presses
		input = input.duplicate()
		input.move = Vector2.ZERO
		input.jump = false
		input.dash = false
	if bool(mods.get("no_jump", false)) or bool(mods.get("no_dash", false)): # a rule of the manager: the press is ignored (a held button is no press either)
		input = input.duplicate()
		if bool(mods.get("no_jump", false)): input.jump = false
		if bool(mods.get("no_dash", false)): input.dash = false
	var surface: Dictionary = ICE if bool(mods.get("ice", false)) and _surface.is_empty() else _surface # the ice rule: icy ground wherever the ground has no feel of its own (slime, level ice)
	var pace := float(mods.get("speed", 1.0))
	var walk := float(_feel.get("walk", WALK_SPEED)) * pace
	var accel := float(_feel.get("accel", ACCEL)) * pace
	var gravity := float(_feel.get("gravity", GRAVITY)) * float(mods.get("gravity", 1.0))
	var was_grounded := grounded
	dash_cooldown = maxf(dash_cooldown - dt, 0.0)
	if was_grounded: _dash_air_used = false # landing gives the air dash back
	_follow_platform(body, dt, was_grounded)
	# input direction and the pull towards a far partner
	var move: Vector2 = input.get("move", Vector2.ZERO)
	var dir := Vector3(move.x, 0.0, move.y).limit_length(1.0)
	# dash: a press (kept DASH_BUFFER s) starts it when it is off cooldown (and, in the air, not yet used this airtime): along the move
	# input, else the facing. A flop (see FLOP_TIME) refuses it, takes the steering and the jump, and clears the press.
	var flopping := flop_left > 0.0
	if flopping: dir = Vector3.ZERO
	var dash_lift := 0.0
	_dash_buffer = 0.0 if flopping or stage else (DASH_BUFFER if bool(input.get("dash", false)) else maxf(_dash_buffer - dt, 0.0))
	if _dash_buffer > 0.0 and dash_left <= 0.0 and dash_cooldown <= 0.0 and (was_grounded or not _dash_air_used):
		_dash_dir = move.normalized() if move.length_squared() > 0.01 else Vector2(-sin(yaw), -cos(yaw))
		_dash_buffer = 0.0
		dash_left = DASH_TIME
		dash_cooldown = DASH_COOLDOWN
		_flop_pending = dash_flop
		if not was_grounded: _dash_air_used = true
		dash_lift = DASH_HOP if was_grounded else DASH_LIFT
		events["dashed"] = true
	events["started_moving"] = dir.length_squared() > 0.0
	var toward: Variant = input.get("toward")
	var partner_gap := Vector3.ZERO
	if toward is Vector3:
		partner_gap = toward - body.global_position
		var partner_speed := Vector2((input.get("partner_velocity", Vector3.ZERO) as Vector3).x, (input.get("partner_velocity", Vector3.ZERO) as Vector3).z).length() if input.has("partner_velocity") else INF
		var own_speed := Vector2(body.velocity.x, body.velocity.z).length()
		if partner_gap.length() > PULL_DISTANCE and own_speed <= partner_speed and not flopping:
			dir += Vector3(partner_gap.x, 0.0, partner_gap.z).normalized() * PULL_STRENGTH
			dir = dir.limit_length(1.0)
	acceleration = dir * accel
	# launch
	var launched := false
	if not _launch.is_empty():
		var lv: Vector3 = _launch["v"]
		body.velocity.x = lv.x if _launch["xy"] else body.velocity.x + lv.x
		body.velocity.z = lv.z if _launch["xy"] else body.velocity.z + lv.z
		body.velocity.y = lv.y if _launch["z"] else body.velocity.y + lv.y
		_launch = {}
		launched = true
		dash_left = 0.0 # a pad or a bumper throws the courier: that is the move now
		flop_left = 0.0
		flopping = false
		_flop_pending = false
	# planar velocity
	var slime_dir: Vector2 = _surface.get("slime", Vector2.ZERO) # the downhill of the slime slope under the feet (set_surface), ZERO elsewhere
	if was_grounded: _slime_air = slime_dir # a jump or a fall off the slope keeps the slide's rules until the next landing
	if not launched:
		var planar := Vector2(body.velocity.x, body.velocity.z)
		var d2 := Vector2(dir.x, dir.z)
		var slide := _slime_air != Vector2.ZERO
		if dash_left > 0.0:
			planar = _dash_dir * DASH_SPEED * float(mods.get("dash", 1.0))
		elif flopping:
			var carry := _belt if was_grounded else Vector2.ZERO # a belly slide on a belt is still carried by it
			planar = (planar - carry).move_toward(Vector2.ZERO, FLOP_BRAKE * dt) + carry
		elif was_grounded:
			var floor_friction := float(surface.get("friction", _feel.get("friction", FRICTION)))
			var floor_braking := float(surface.get("braking", _feel.get("brake", BRAKE)))
			if slide and d2.length_squared() < 0.000001:
				planar = (planar - _belt).move_toward(Vector2.ZERO, floor_braking * dt) + _belt # no dead zone at rest: the slime's push has to be able to start a courier that stands still
			else:
				planar = ground_velocity(planar - _belt, d2, floor_friction, floor_braking, dt, 1.0, walk, accel) + _belt
		else:
			planar = air_velocity(planar, d2, float(surface.get("air_control", SLIME["air_control"] if slide else _feel.get("air_control", AIR_CONTROL))), dt, walk, accel, 0.0 if slide else float(_feel.get("fall_brake", FALL_BRAKE)))
		if slide and dash_left <= 0.0:
			# the slime pushes downhill on the ground (up to SLIME_MAX) and in the air after a jump (no air brake, up to SLIME_AIR_MAX); a courier already faster is not pushed further
			var before := Vector2(body.velocity.x, body.velocity.z).length()
			planar = (planar + _slime_air * SLIME_PUSH * dt).limit_length(maxf(SLIME_MAX if was_grounded else SLIME_AIR_MAX, minf(before, planar.length())))
		body.velocity.x = planar.x
		body.velocity.z = planar.y
	# vertical, coyote, jump
	if was_grounded and not launched and body.velocity.y <= 0.0: body.velocity.y = 0.0
	else: body.velocity.y = maxf(body.velocity.y - gravity * (DASH_GRAVITY if dash_left > 0.0 else 1.0) * dt, -MAX_FALL)
	if dash_lift > 0.0: body.velocity.y = maxf(body.velocity.y, dash_lift)
	_coyote = COYOTE if was_grounded else maxf(_coyote - dt, 0.0)
	_buffer = maxf(_buffer - dt, 0.0)
	if bool(input.get("jump", false)) and not flopping: _buffer = JUMP_BUFFER
	if flopping: _buffer = 0.0
	var jump_down := bool(input.get("jump", false)) and not flopping
	if was_grounded: _air_jumps_used = 0
	if jump_down and not _jump_was_down and not was_grounded and _coyote <= 0.0 and _air_jumps_used < int(mods.get("air_jumps", 0)):
		body.velocity.y = float(_feel.get("jump", JUMP_SPEED)) * float(mods.get("jump", 1.0)) * 0.92 # a second jump in the air: a touch weaker than the first
		_air_jumps_used += 1
		_buffer = 0.0
		events["jumped"] = true
	_jump_was_down = jump_down
	if _buffer > 0.0 and _coyote > 0.0:
		body.velocity.y = float(_feel.get("jump", JUMP_SPEED)) * float(mods.get("jump", 1.0))
		_buffer = 0.0
		_coyote = 0.0
		events["jumped"] = true
		if slime_dir != Vector2.ZERO: # a jump off the slime kicks along the slope: bunny hops on it add speed (up to SLIME_AIR_MAX, which the ground slide never reaches)
			var flat := Vector2(body.velocity.x, body.velocity.z)
			var kicked := (flat + slime_dir * SLIME_HOP).limit_length(maxf(SLIME_AIR_MAX, flat.length()))
			body.velocity.x = kicked.x
			body.velocity.z = kicked.y
	var pre_move_vy := body.velocity.y
	# move
	var stepped := false
	if was_grounded and not events["jumped"] and not launched:
		stepped = _try_step(body, Vector3(body.velocity.x, 0.0, body.velocity.z) * dt)
	if stepped:
		body.velocity.y = 0.0
		grounded = true
		floor_normal = _kc.get_normal()
		events["stepped"] = true
	else:
		body.move_and_slide()
		grounded = body.is_on_floor()
		floor_normal = body.get_floor_normal() if grounded else Vector3.ZERO
	# mover under the feet
	_update_platform(body, dt, events)
	var wall_hit := dash_left > 0.0 and not launched and not stepped and _hit_wall(body)
	# facing
	var face := Vector3.ZERO
	if bool(input.get("holding", false)) and toward is Vector3 and Vector2(partner_gap.x, partner_gap.z).length_squared() > 0.0001:
		face = Vector3(partner_gap.x, 0.0, partner_gap.z)
	elif dir.length_squared() > 0.001:
		face = dir
	if dash_left > 0.0 and not _dash_dir.is_zero_approx(): face = Vector3(_dash_dir.x, 0.0, _dash_dir.y)
	if face != Vector3.ZERO and not flopping:
		yaw = atan2(-face.x, -face.z)
		body.rotation.y = yaw
	dash_left = maxf(dash_left - dt, 0.0)
	flop_left = maxf(flop_left - dt, 0.0)
	if wall_hit and not dash_flop:
		dash_left = 0.0 # a dash that meets a wall just ends there, the courier keeps its control
	elif wall_hit:
		dash_left = 0.0
		flop_left = WALL_STUN
		_flop_pending = false
		body.velocity.x = -_dash_dir.x * WALL_PUSH
		body.velocity.z = -_dash_dir.y * WALL_PUSH
		events["wall_stun"] = true
	elif _flop_pending and grounded and dash_left <= 0.0:
		var carried := Vector2(body.velocity.x, body.velocity.z).limit_length(FLOP_SPEED)
		body.velocity.x = carried.x
		body.velocity.z = carried.y
		flop_left = FLOP_TIME
		_flop_pending = false
		events["flopped"] = true
	body.transform = body.transform.orthonormalized()
	# events
	if grounded and not was_grounded:
		events["landed"] = true
		events["land_speed"] = _fall_speed
	if grounded: _fall_speed = 0.0
	elif pre_move_vy < 0.0: _fall_speed = maxf(_fall_speed, -pre_move_vy)
	events["left_ground"] = was_grounded and not grounded and not events["jumped"]
	return events

func _is_courier(collider: Object) -> bool:
	var body := collider as CollisionObject3D
	return body != null and (body.collision_layer & LAYER_COURIER) != 0

## True when this tick's slide ran head-on into a wall or an obstacle (a vertical face, its normal opposing the dash) and the dash lost most of its speed.
## Another courier is no wall: a dash into one is a tackle, the shove (players/player_contact.gd) handles it and nobody bonks.
func _hit_wall(body: CharacterBody3D) -> bool:
	for index in body.get_slide_collision_count():
		var hit := body.get_slide_collision(index)
		if _is_courier(hit.get_collider()): continue
		var normal := hit.get_normal()
		if absf(normal.y) > 0.5: continue
		var flat := Vector2(normal.x, normal.z)
		if flat.length_squared() < 0.01: continue
		if -flat.normalized().dot(_dash_dir) >= WALL_HEAD_ON and Vector2(body.velocity.x, body.velocity.z).dot(_dash_dir) < DASH_SPEED * 0.5: return true
	return false

## Carries the courier by the transform delta of the mover under its feet (before the courier moves).
func _follow_platform(body: CharacterBody3D, dt: float, was_grounded: bool) -> void:
	_platform_velocity = Vector3.ZERO
	if platform == null: return
	if not is_instance_valid(platform) or not platform.is_inside_tree() or not was_grounded:
		platform = null
		return
	var current := Transform3D(platform.global_basis.orthonormalized(), platform.global_position)
	var target := current * _platform_frame.affine_inverse() * body.global_position
	var requested := target - body.global_position
	_platform_frame = current
	_platform_velocity = requested / maxf(dt, 0.0001)
	if requested.length_squared() > 1e-10:
		var mover := platform as CollisionObject3D
		if mover != null: body.add_collision_exception_with(mover)
		body.move_and_collide(requested)
		if mover != null: body.remove_collision_exception_with(mover)

func _update_platform(body: CharacterBody3D, _dt: float, events: Dictionary) -> void:
	var found: Node3D = null
	if grounded:
		for index in body.get_slide_collision_count():
			var hit := body.get_slide_collision(index)
			var collider := hit.get_collider() as CollisionObject3D
			if collider != null and (collider.collision_layer & MOVER_LAYER) != 0 and hit.get_normal().y >= _floor_cos:
				found = collider
				break
		if found == null:
			var query := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.1, body.global_position - Vector3.UP * 0.15, MOVER_LAYER, [body.get_rid()])
			var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and (hit["normal"] as Vector3).y >= _floor_cos: found = hit["collider"] as Node3D
	if found != null:
		if found != platform:
			platform = found
			_platform_frame = Transform3D(found.global_basis.orthonormalized(), found.global_position)
	elif platform != null:
		# left the mover: keep its velocity
		if not grounded: body.velocity += _platform_velocity
		platform = null

## Step up onto a low ledge in the way. The capsule is lifted, carried forward far enough that its axis ends up
## over the ledge (a capsule blocked by a vertical edge still has its axis one radius away from it) and put back
## down. Returns true (and moves the body) when it worked.
func _try_step(body: CharacterBody3D, want: Vector3) -> bool:
	if want.length_squared() < 1e-8: return false
	var max_step := float(_feel.get("max_step", MAX_STEP))
	var start := body.global_transform
	if not body.test_move(start, want, _kc): return false
	if _kc.get_normal().y >= _floor_cos or _is_courier(_kc.get_collider()): return false # another courier is no ledge
	var rise := max_step
	if body.test_move(start, Vector3.UP * max_step, _kc): rise = maxf(_kc.get_travel().y, 0.0)
	if rise < 0.02: return false
	var t := start
	t.origin.y += rise
	var ahead := want.normalized() * (want.length() + CAPSULE_RADIUS)
	var forward := ahead
	if body.test_move(t, ahead, _kc): forward = _kc.get_travel()
	if forward.length() < want.length() * 0.99: return false
	t.origin += forward
	if not body.test_move(t, Vector3.DOWN * (rise + 0.05), _kc): return false
	if _kc.get_normal().y < _floor_cos: return false
	t.origin += _kc.get_travel()
	var gain := t.origin.y - start.origin.y
	if gain < 0.03 or gain > max_step + 0.01: return false
	body.global_transform = t
	return true
