extends RefCounted
## Light props in the lobby yard (boxes, balls, cones) that players pick up, carry in front of them, drop or throw, and knock out
## of each other's hands. Pure simulation, like the balloon (balloon/balloon_sim.gd): the authority (and the local game) steps it with
## the couriers and replicates `snapshot()`; clients only draw it (players/prop_look.gd).
##
##   var props := PropSim.new([{"kind": "box", "position": p}, ...])
##   var events := props.step(delta, space, players)   # players: [{position (feet), facing (flat unit), velocity, grab, active}]
##   for event in events: match event.kind: "pick", "throw", "knock"
##
## Rules: GRAB with empty hands picks up the nearest free prop in front within REACH; GRAB again throws it forward; a holder who is
## grabbed or leaves (`active` false) or is hit by a flying prop drops it (`knock`). A free prop falls, bounces off the world and
## slides to rest; a player walking into one on the floor kicks it along. GRAB presses are shared with players/player_contact.gd:
## a prop holder's press throws the prop, the others go to the contact first and pick up a prop only when it did nothing with them.
const KINDS := {"box": 0.25, "ball": 0.25, "cone": 0.22} ## kind -> radius of its collision sphere (m)
const GRAVITY := 17.0
const REACH := 1.5            ## m from the holder's chest to a prop it can pick up
const FRONT := -0.2           ## dot(facing, to prop) at least this: in front or beside
const HOLD_FORWARD := 0.75    ## where a carried prop sits: in front of the holder ...
const HOLD_UP := 0.95         ## ... at belly height (in first person it fills only the bottom of the view)
const THROW_FORWARD := 8.0    ## m/s
const THROW_UP := 4.5
const DROP_UP := 1.5
const BOUNCE := 0.45
const FRICTION := 4.0         ## 1/s of sliding speed lost on the floor
const KICK := 1.3             ## a walked-into prop takes this share of the walker's speed
const KNOCK_SPEED := 4.0      ## m/s: a flying prop this fast knocks what the player it hits carries out of their hands
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.8
const FLOOR_NORMAL_Y := 0.6
const KILL_Y := -30.0         ## below its home: back home

var count := 0
var kinds: PackedStringArray = []
var positions: PackedVector3Array = []
var velocities: PackedVector3Array = []
var held_by: PackedInt32Array = [] ## per prop: the holding slot, -1 free
var homes: PackedVector3Array = [] ## where each prop starts, and goes back to when it falls out of the world
var world_mask := 1 | 16 | 512
var _shapes := {}

func _init(layout: Array) -> void:
	for entry: Dictionary in layout:
		var kind := str(entry.get("kind", "box"))
		kinds.append(kind if KINDS.has(kind) else "box")
		var at: Vector3 = entry.get("position", Vector3.ZERO)
		positions.append(at)
		homes.append(at)
		velocities.append(Vector3.ZERO)
		held_by.append(-1)
	count = kinds.size()

## The prop `slot` holds, -1 for none.
func holding(slot: int) -> int:
	return held_by.find(slot)

## True when a GRAB press of `slot` is left for the props: players/player_contact.gd stepped it without a grab or a throw by
## `slot` (no player in reach, nobody held).
static func leftover_grab(contact_events: Array, slot: int) -> bool:
	for event: Dictionary in contact_events:
		if int(event.get("player", -1)) == slot and str(event.get("kind", "")) in ["grab", "throw"]: return false
	return true

## Where a carried prop sits for a holder standing at `feet` facing `facing`.
static func hold_point(feet: Vector3, facing: Vector3) -> Vector3:
	return feet + facing * HOLD_FORWARD + Vector3.UP * HOLD_UP

## Back home, still, nobody holding.
func reset() -> void:
	for index in count:
		positions[index] = homes[index]
		velocities[index] = Vector3.ZERO
		held_by[index] = -1

## `slot` lets go of its prop (grabbed, hit, gone): it drops where it is with `velocity` and a little hop. {} when it held none.
func knock(slot: int, velocity := Vector3.ZERO) -> Dictionary:
	var index := holding(slot)
	if index < 0: return {}
	held_by[index] = -1
	velocities[index] = velocity + Vector3.UP * DROP_UP
	return {"kind": "knock", "prop": index, "player": slot, "position": positions[index]}

## One fixed step. `players`: per slot {position (feet), facing (flat unit), velocity, grab (a press this step), active}.
func step(delta: float, space: PhysicsDirectSpaceState3D, players: Array) -> Array:
	var events: Array = []
	for slot in players.size():
		var player: Dictionary = players[slot]
		if not bool(player.get("active", true)):
			var gone := knock(slot, player.get("velocity", Vector3.ZERO))
			if not gone.is_empty(): events.append(gone)
			continue
		if not bool(player.get("grab", false)): continue
		var carried := holding(slot)
		if carried >= 0:
			held_by[carried] = -1
			var facing: Vector3 = player.get("facing", Vector3.FORWARD)
			velocities[carried] = (player.get("velocity", Vector3.ZERO) as Vector3) * Vector3(1, 0, 1) + facing * THROW_FORWARD + Vector3.UP * THROW_UP
			events.append({"kind": "throw", "prop": carried, "player": slot, "position": positions[carried]})
			continue
		var best := _nearest_free(player)
		if best >= 0:
			held_by[best] = slot
			events.append({"kind": "pick", "prop": best, "player": slot, "position": positions[best]})
	for index in count:
		var holder := held_by[index]
		if holder >= 0 and holder < players.size():
			var player: Dictionary = players[holder]
			positions[index] = hold_point(player.position, player.get("facing", Vector3.FORWARD))
			velocities[index] = player.get("velocity", Vector3.ZERO)
			continue
		_kick(index, players)
		_fly(index, delta, space)
		var hit := _hit_player(index, players)
		if hit >= 0 and holding(hit) >= 0: events.append(knock(hit, velocities[index] * 0.3))
	return events

func _nearest_free(player: Dictionary) -> int:
	var chest: Vector3 = (player.position as Vector3) + Vector3.UP * HOLD_UP
	var facing: Vector3 = player.get("facing", Vector3.FORWARD)
	var best := -1
	var best_distance := REACH
	for index in count:
		if held_by[index] >= 0: continue
		var offset := positions[index] - chest
		var distance := offset.length()
		if distance >= best_distance: continue
		var flat := offset * Vector3(1, 0, 1)
		if flat.length() > 0.05 and facing.dot(flat.normalized()) < FRONT: continue
		best = index
		best_distance = distance
	return best

## A player walking into a free prop near the floor pushes it out of the capsule and along at KICK times its speed.
func _kick(index: int, players: Array) -> void:
	var radius := float(KINDS[kinds[index]])
	for player: Dictionary in players:
		if not bool(player.get("active", true)): continue
		var feet: Vector3 = player.position
		if positions[index].y < feet.y - radius or positions[index].y > feet.y + PLAYER_HEIGHT: continue
		var flat := (positions[index] - feet) * Vector3(1, 0, 1)
		var overlap := PLAYER_RADIUS + radius - flat.length()
		if overlap <= 0.0: continue
		var away := flat.normalized() if flat.length() > 0.01 else (player.get("facing", Vector3.FORWARD) as Vector3)
		positions[index] += away * overlap
		var walk: Vector3 = (player.get("velocity", Vector3.ZERO) as Vector3) * Vector3(1, 0, 1)
		var push := maxf(walk.dot(away), 0.0) * KICK
		var along := velocities[index].dot(away)
		if push > along: velocities[index] += away * (push - along) + Vector3.UP * push * 0.25

## A free prop: out of the world where it sank in, gravity, a sweep against the world (the rest of a blocked move slides along
## the surface), a bounce off walls and floors, sliding to rest.
func _fly(index: int, delta: float, space: PhysicsDirectSpaceState3D) -> void:
	var velocity := velocities[index]
	var position := positions[index]
	var on_floor := false
	var out := _push_out(index, position, space)
	if out != Vector3.ZERO:
		position += out
		var away := out.normalized()
		if velocity.dot(away) < 0.0: velocity -= away * velocity.dot(away)
		on_floor = away.y >= FLOOR_NORMAL_Y
	velocity.y -= GRAVITY * delta
	var motion := velocity * delta
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape(kinds[index])
	query.collision_mask = world_mask
	for attempt in 3:
		if motion.length_squared() < 1e-10: break
		if space == null:
			position += motion
			break
		query.transform = Transform3D(Basis.IDENTITY, position)
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions.is_empty() or fractions[0] >= 1.0:
			position += motion
			break
		position += motion * fractions[0]
		query.transform = Transform3D(Basis.IDENTITY, position + motion * (fractions[1] - fractions[0]))
		query.motion = Vector3.ZERO
		var normal: Vector3 = space.get_rest_info(query).get("normal", Vector3.UP)
		var into := velocity.dot(normal)
		if into < 0.0: velocity -= normal * into * (1.0 + (BOUNCE if into < -1.5 else 0.0)) # slow contacts settle instead of jittering
		on_floor = on_floor or normal.y >= FLOOR_NORMAL_Y
		motion = (motion * (1.0 - fractions[0])).slide(normal)
	if on_floor: velocity -= Vector3(velocity.x, 0.0, velocity.z) * minf(FRICTION * delta, 1.0)
	if position.y < homes[index].y + KILL_Y:
		position = homes[index]
		velocity = Vector3.ZERO
	positions[index] = position
	velocities[index] = velocity

## The way out of the world bodies a prop at `position` overlaps (the sweep does not see a shape that starts inside), ZERO for none.
func _push_out(index: int, position: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	if space == null: return Vector3.ZERO
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape(kinds[index])
	query.collision_mask = world_mask
	var moved := Vector3.ZERO
	for attempt in 3:
		query.transform = Transform3D(Basis.IDENTITY, position + moved)
		var pairs := space.collide_shape(query, 8)
		var push := Vector3.ZERO
		for at in range(0, pairs.size() - 1, 2):
			var way: Vector3 = pairs[at + 1] - pairs[at] # from the prop's deepest point to the body's surface
			if way.length() > push.length(): push = way
		if push.length() < 0.002: break
		moved += push + push.normalized() * 0.001
	return moved

## The slot a flying prop runs into fast enough to knock what it carries, -1 for none.
func _hit_player(index: int, players: Array) -> int:
	if velocities[index].length() < KNOCK_SPEED: return -1
	for slot in players.size():
		var player: Dictionary = players[slot]
		if not bool(player.get("active", true)) or holding(slot) == index: continue
		var feet: Vector3 = player.position
		var closest := feet + Vector3.UP * clampf(positions[index].y - feet.y, PLAYER_RADIUS, PLAYER_HEIGHT - PLAYER_RADIUS)
		if positions[index].distance_to(closest) < PLAYER_RADIUS + float(KINDS[kinds[index]]): return slot
	return -1

func _shape(kind: String) -> SphereShape3D:
	if not _shapes.has(kind):
		var sphere := SphereShape3D.new()
		sphere.radius = float(KINDS.get(kind, 0.3))
		_shapes[kind] = sphere
	return _shapes[kind]

## Replicated state: per prop [x, y, z, vx, vy, vz, held_by] (network/game.gd PROP_FLOATS).
func snapshot() -> PackedFloat32Array:
	var state := PackedFloat32Array()
	for index in count:
		var at := positions[index]
		var v := velocities[index]
		state.append_array(PackedFloat32Array([at.x, at.y, at.z, v.x, v.y, v.z, float(held_by[index])]))
	return state

func apply_snapshot(state: PackedFloat32Array) -> void:
	if state.size() != count * 7: return
	for index in count:
		var at := index * 7
		positions[index] = Vector3(state[at], state[at + 1], state[at + 2])
		velocities[index] = Vector3(state[at + 3], state[at + 4], state[at + 5])
		held_by[index] = int(state[at + 6])
