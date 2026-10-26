extends RefCounted
## Balloon mode (3+ players): keep one balloon in the air from the start to the goal. Players bump it by touching it
## (walk into it to nudge it, jump into it for a header); it drifts down slowly, bounces off walls and obstacles, and
## pops the moment it touches a floor. A surface that moves into it (a rising lift, a sliding wall) throws it off instead: it
## never ends up inside a body. A pop respawns it over `respawn_point` after RESPAWN_SECONDS.
##
## Pure simulation, no physics body: the authority steps it and replicates `snapshot()`; clients only draw it
## (balloon_look.gd). Players are passed in as plain capsules, the level is read through a PhysicsDirectSpaceState3D
## (shape casts against `world_mask`), so the same code runs in the lab, the local game and on the server.
##
##   var balloon := BalloonSim.new(spawn)
##   var events := balloon.step(delta, space, [{"position": capsule_centre, "velocity": v}, ...])
##   for event in events: match event.kind: "bump", "bounce", "pop", "respawn"

const RADIUS := 0.6
const GRAVITY := 3.0          ## m/s², floaty
const DRAG_SIDEWAYS := 1.1    ## 1/s, linear: a push carries it a couple of metres, not across the level
const DRAG_UPDOWN := 0.5      ## 1/s, linear
const MAX_SPEED := 9.0
const BUMP_UP := 3.2          ## upward speed every touch gives (m/s)
const HEADER_GAIN := 0.2      ## extra upward speed per m/s the player rises at the touch
const BUMP_OUT := 1.0         ## away-from-the-player speed (m/s)
const CARRY_GAIN := 0.35      ## share of the player's horizontal velocity passed on
const BUMP_COOLDOWN := 0.18   ## s, per player, so one long touch is one bump
const RESTITUTION := 0.65     ## walls, ceilings, obstacles
const FLOOR_NORMAL_Y := 0.6   ## a contact whose normal points this far up is a floor: pop
const MOVER_SPEED := 0.25     ## m/s: a surface that moves towards the balloon this fast shoves it instead (a rising lift does not pop it)
const SHOVE_SPEED := 1.5      ## m/s: the least speed a shove throws the balloon off with
const PUSH_DEPTH := 0.005     ## m: an overlap deeper than this is a body that moved into the balloon: it is pushed out
const PUSH_STEPS := 4
const RESPAWN_SECONDS := 1.6
const SLAP_UP := 6.0          ## upward speed a slap gives (m/s): well above a bump's BUMP_UP
const SLAP_FORWARD := 3.5     ## speed a slap adds along the slapper's facing (m/s)
const SLAP_REACH := 1.0       ## m from the balloon's skin to the slapper's capsule: in reach of a slap
const RESPAWN_HEIGHT := 2.6   ## above the respawn point
const KILL_Y := -30.0         ## below this (fell out of the level) also pops

const PLAYER_RADIUS := 0.35   ## the courier capsule (run.gd / core_character_origin.gd)
const PLAYER_HALF_SEGMENT := 0.55 ## half the capsule's inner segment: 1.8 m tall capsule, radius 0.35

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var alive := true
var respawn_point := Vector3.ZERO
var world_mask := 1
var pops := 0
var bumps := 0
var slaps := 0
## Hangs still over its spawn point until the first touch (the game sets it after every spawn: the team starts it).
var hover := false
var _respawn_in := 0.0
var _cooldowns: Dictionary = {} ## player index -> seconds left
var _shape := SphereShape3D.new()

func _init(spawn: Vector3 = Vector3.ZERO) -> void:
	_shape.radius = RADIUS
	respawn_point = spawn
	reset()

## Back over the respawn point, still, alive.
func reset() -> void:
	position = respawn_point + Vector3.UP * RESPAWN_HEIGHT
	velocity = Vector3.ZERO
	alive = true
	_respawn_in = 0.0
	_cooldowns.clear()

## One fixed step. `players`: Array of {position: Vector3 (capsule centre), velocity: Vector3}. Returns the events
## of this step as dictionaries {kind, position, player?, normal?}.
func step(delta: float, space: PhysicsDirectSpaceState3D, players: Array) -> Array:
	var events: Array = []
	if not alive:
		_respawn_in -= delta
		if _respawn_in <= 0.0:
			reset()
			events.append({"kind": "respawn", "position": position})
		return events
	for key in _cooldowns.keys():
		_cooldowns[key] = float(_cooldowns[key]) - delta
		if _cooldowns[key] <= 0.0: _cooldowns.erase(key)
	# A body that moved into the balloon (a rising lift, a sliding wall) throws it off: it never ends up inside one.
	var shoved := _push_out(space)
	if not shoved.is_empty():
		events.append(shoved)
		hover = false
	if hover:
		velocity = Vector3.ZERO
		for index in players.size():
			var touch := _touch(index, players[index])
			if not touch.is_empty(): events.append(touch)
		hover = events.is_empty()
		if hover:
			position = respawn_point + Vector3.UP * RESPAWN_HEIGHT
			return events
	velocity.y -= GRAVITY * delta
	velocity.x *= maxf(0.0, 1.0 - DRAG_SIDEWAYS * delta)
	velocity.z *= maxf(0.0, 1.0 - DRAG_SIDEWAYS * delta)
	velocity.y *= maxf(0.0, 1.0 - DRAG_UPDOWN * delta)
	for index in players.size():
		var bump := _touch(index, players[index])
		if not bump.is_empty(): events.append(bump)
	velocity = velocity.limit_length(MAX_SPEED)
	var hit := _move(delta, space)
	if not hit.is_empty(): events.append(hit)
	if alive and position.y < KILL_Y: events.append(_pop(Vector3.UP))
	return events

## Capsule-vs-sphere: push the balloon out of the player and give it the bump (once per cooldown).
func _touch(index: int, player: Dictionary) -> Dictionary:
	var centre: Vector3 = player.get("position", Vector3.INF)
	if not centre.is_finite(): return {}
	var closest := centre + Vector3.UP * clampf(position.y - centre.y, -PLAYER_HALF_SEGMENT, PLAYER_HALF_SEGMENT)
	var offset := position - closest
	var distance := offset.length()
	var reach := RADIUS + PLAYER_RADIUS
	if distance >= reach: return {}
	var normal := offset / distance if distance > 0.0001 else Vector3.UP
	position = closest + normal * reach
	if velocity.dot(normal) < 0.0: velocity -= normal * velocity.dot(normal)
	if _cooldowns.has(index): return {}
	_cooldowns[index] = BUMP_COOLDOWN
	var mover: Vector3 = player.get("velocity", Vector3.ZERO)
	var flat := Vector3(normal.x, 0.0, normal.z)
	velocity += flat.normalized() * BUMP_OUT if flat.length() > 0.05 else Vector3.ZERO
	velocity += Vector3(mover.x, 0.0, mover.z) * CARRY_GAIN
	velocity.y = maxf(velocity.y, BUMP_UP + maxf(0.0, mover.y) * HEADER_GAIN)
	bumps += 1
	return {"kind": "bump", "position": position, "player": index}

## Sweep the sphere along velocity·delta; a floor contact pops it, anything else bounces it.
func _move(delta: float, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var motion := velocity * delta
	if space == null or motion.length_squared() < 1e-10:
		position += motion
		return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.motion = motion
	query.collision_mask = world_mask
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[0] >= 1.0:
		position += motion
		return {}
	position += motion * fractions[0]
	query.transform = Transform3D(Basis.IDENTITY, position + motion * (fractions[1] - fractions[0]))
	query.motion = Vector3.ZERO
	var rest := space.get_rest_info(query)
	var normal: Vector3 = rest.get("normal", -motion.normalized())
	var surface: Vector3 = rest.get("linear_velocity", Vector3.ZERO)
	if surface.dot(normal) >= MOVER_SPEED: _shove(normal, surface) # a surface coming at the balloon throws it, floor or not
	elif normal.y >= FLOOR_NORMAL_Y: return _pop(normal)
	else: velocity = velocity.bounce(normal) * RESTITUTION
	return {"kind": "bounce", "position": position, "normal": normal}

## Out of every body it overlaps (deepest contact first, a few steps), then thrown off along the way out with the body's speed.
## {} when nothing overlaps deeper than PUSH_DEPTH.
func _push_out(space: PhysicsDirectSpaceState3D) -> Dictionary:
	if space == null: return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = world_mask
	var moved := Vector3.ZERO
	var surface := Vector3.ZERO
	for attempt in PUSH_STEPS:
		query.transform = Transform3D(Basis.IDENTITY, position)
		var pairs := space.collide_shape(query, 8)
		var push := Vector3.ZERO
		for index in range(0, pairs.size() - 1, 2):
			var out: Vector3 = pairs[index + 1] - pairs[index] # from the balloon's deepest point to the body's surface
			if out.length() > push.length(): push = out
		if push.length() <= PUSH_DEPTH: break
		if attempt == 0: surface = space.get_rest_info(query).get("linear_velocity", Vector3.ZERO)
		position += push + push.normalized() * PUSH_DEPTH
		moved += push
	if moved == Vector3.ZERO: return {}
	_shove(moved.normalized(), surface)
	return {"kind": "bounce", "position": position, "normal": moved.normalized()}

## Bounce off a surface moving at `surface` (m/s) with the restitution of the balloon, and leave it at SHOVE_SPEED at least.
func _shove(normal: Vector3, surface: Vector3) -> void:
	var closing := (velocity - surface).dot(normal)
	if closing < 0.0: velocity -= normal * closing * (1.0 + RESTITUTION)
	var away := velocity.dot(normal)
	if away < SHOVE_SPEED: velocity += normal * (SHOVE_SPEED - away)
	velocity = velocity.limit_length(MAX_SPEED)

## A slap (the game decides who, when and towards where): a strong lift up and along `facing` (flat). {} when popped.
func slap(facing: Vector3) -> Dictionary:
	if not alive: return {}
	hover = false
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() > 0.01: velocity += flat.normalized() * SLAP_FORWARD
	velocity.y = maxf(velocity.y, SLAP_UP)
	velocity = velocity.limit_length(MAX_SPEED)
	slaps += 1
	return {"kind": "slap", "position": position}

## Gap between the balloon's skin and a player capsule whose centre is `centre` (below zero: they touch).
func gap_to(centre: Vector3) -> float:
	var closest := centre + Vector3.UP * clampf(position.y - centre.y, -PLAYER_HALF_SEGMENT, PLAYER_HALF_SEGMENT)
	return position.distance_to(closest) - RADIUS - PLAYER_RADIUS

## Pops it now (a hit hazard, a kill volume: the game's own rules on top of the floor test). {} when already popped.
func pop(normal := Vector3.UP) -> Dictionary:
	return _pop(normal) if alive else {}

func _pop(normal: Vector3) -> Dictionary:
	alive = false
	pops += 1
	_respawn_in = RESPAWN_SECONDS
	return {"kind": "pop", "position": position, "normal": normal}

## True while the balloon is alive and inside `area` (the goal volume, world space).
func inside(area: AABB) -> bool:
	return alive and area.grow(-RADIUS * 0.5).has_point(position)

## Replicated state: authority -> clients, 8 floats.
func snapshot() -> PackedFloat32Array:
	return PackedFloat32Array([position.x, position.y, position.z, velocity.x, velocity.y, velocity.z, 1.0 if alive else 0.0, _respawn_in])

func apply_snapshot(state: PackedFloat32Array) -> void:
	if state.size() < 8: return
	position = Vector3(state[0], state[1], state[2])
	velocity = Vector3(state[3], state[4], state[5])
	alive = state[6] > 0.5
	_respawn_in = state[7]
