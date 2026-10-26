extends RefCounted
## The lobby yard's playground (lobby_space.gd): a swing set, a trampoline, a slide, a ball pit, a seesaw and the furniture around them,
## built from boxes and upright cylinders on every role, so every peer collides with the same yard. Pure data plus bodies; the client
## dresses them (lobby/playground_look.gd).
##  * Movers (the swing, the seesaw) rock as pure functions of the wall clock (clock()), like the level hazards of the level clock: the
##    same instant gives the same pose on every peer. The courier rides them like any mover (courier_motion.gd, layer 16).
##  * The trampoline and the slide are geometric volumes, tested on the couriers this peer simulates (the local couriers, or the replica's
##    own one) and handed to their movement as a launch, like the level's bumpers and push pads.
## Positions are yard-local (walk_in_lobby.gd ORIGIN), metres, the floor at y = 0; `r` is a rotation in degrees (YXZ).
const Layout = preload("res://network/walk_in_lobby.gd")
const LAYER := 1 | 512
const MOVER_LAYER := 16 | 512
## Solids: `k` box (`s` its size) or cyl (`s.x` the diameter, `s.y` the height), `p` the centre, `look` how the client dresses it.
const SOLIDS := [
	# swing set: a top beam on two A-frames, the seat swings east-west between them
	{"name": "swing_beam", "k": "box", "p": Vector3(-7.6, 2.95, -10.7), "s": Vector3(0.16, 0.16, 4.5), "look": "frame"},
	{"name": "swing_leg_nw", "k": "box", "p": Vector3(-8.25, 1.45, -12.85), "s": Vector3(0.14, 3.2, 0.14), "r": Vector3(0, 0, -24), "look": "frame"},
	{"name": "swing_leg_ne", "k": "box", "p": Vector3(-6.95, 1.45, -12.85), "s": Vector3(0.14, 3.2, 0.14), "r": Vector3(0, 0, 24), "look": "frame"},
	{"name": "swing_leg_sw", "k": "box", "p": Vector3(-8.25, 1.45, -8.55), "s": Vector3(0.14, 3.2, 0.14), "r": Vector3(0, 0, -24), "look": "frame"},
	{"name": "swing_leg_se", "k": "box", "p": Vector3(-6.95, 1.45, -8.55), "s": Vector3(0.14, 3.2, 0.14), "r": Vector3(0, 0, 24), "look": "frame"},
	# trampoline: a round padded frame, the mat on top
	{"name": "trampoline", "k": "cyl", "p": Vector3(0.0, 0.2, -9.4), "s": Vector3(2.9, 0.4, 2.9), "look": "trampoline"},
	# slide: three steps up from the west, a tower, a chute down to the south between two rails
	{"name": "slide_step_1", "k": "box", "p": Vector3(6.775, 0.2, -12.6), "s": Vector3(0.45, 0.4, 1.4), "look": "step"},
	{"name": "slide_step_2", "k": "box", "p": Vector3(7.225, 0.4, -12.6), "s": Vector3(0.45, 0.8, 1.4), "look": "step"},
	{"name": "slide_step_3", "k": "box", "p": Vector3(7.675, 0.6, -12.6), "s": Vector3(0.45, 1.2, 1.4), "look": "step"},
	{"name": "slide_tower", "k": "box", "p": Vector3(8.7, 0.8, -12.6), "s": Vector3(1.6, 1.6, 1.4), "look": "tower"},
	{"name": "slide_chute", "k": "box", "p": Vector3(8.7, 0.727, -10.132), "s": Vector3(1.2, 0.16, 3.94), "r": Vector3(23.96, 0, 0), "look": "chute"},
	{"name": "slide_rail_w", "k": "box", "p": Vector3(8.04, 0.937, -10.039), "s": Vector3(0.1, 0.3, 3.94), "r": Vector3(23.96, 0, 0), "look": "rail"},
	{"name": "slide_rail_e", "k": "box", "p": Vector3(9.36, 0.937, -10.039), "s": Vector3(0.1, 0.3, 3.94), "r": Vector3(23.96, 0, 0), "look": "rail"},
	# ball pit against the west wall: a soft border you step over
	{"name": "pit_n", "k": "box", "p": Vector3(-15.35, 0.2, 4.575), "s": Vector3(3.9, 0.4, 0.25), "look": "cushion"},
	{"name": "pit_s", "k": "box", "p": Vector3(-15.35, 0.2, 8.025), "s": Vector3(3.9, 0.4, 0.25), "look": "cushion"},
	{"name": "pit_e", "k": "box", "p": Vector3(-13.525, 0.2, 6.3), "s": Vector3(0.25, 0.4, 3.2), "look": "cushion"},
	# seesaw fulcrum
	{"name": "seesaw_foot", "k": "box", "p": Vector3(7.6, 0.25, 6.8), "s": Vector3(0.5, 0.5, 0.5), "look": "frame"},
	# sofa corner on the south wall, two bean bags in front
	{"name": "sofa_seat", "k": "box", "p": Vector3(4.9, 0.22, 9.35), "s": Vector3(2.3, 0.44, 0.8), "look": "sofa"},
	{"name": "sofa_back", "k": "box", "p": Vector3(4.9, 0.55, 9.84), "s": Vector3(2.8, 1.1, 0.26), "look": "sofa"},
	{"name": "sofa_arm_w", "k": "box", "p": Vector3(3.625, 0.36, 9.4), "s": Vector3(0.25, 0.72, 0.9), "look": "sofa"},
	{"name": "sofa_arm_e", "k": "box", "p": Vector3(6.175, 0.36, 9.4), "s": Vector3(0.25, 0.72, 0.9), "look": "sofa"},
	{"name": "bean_a", "k": "cyl", "p": Vector3(4.1, 0.24, 7.9), "s": Vector3(0.9, 0.48, 0.9), "look": "bean"},
	{"name": "bean_b", "k": "cyl", "p": Vector3(5.8, 0.24, 7.75), "s": Vector3(0.9, 0.48, 0.9), "look": "bean"},
	# vending machine in the south-west corner, its front to the yard
	{"name": "vending", "k": "box", "p": Vector3(-16.65, 0.95, 9.5), "s": Vector3(1.1, 1.9, 0.8), "look": "vending"},
	# potted plants
	{"name": "plant_w", "k": "cyl", "p": Vector3(-16.7, 0.275, -3.0), "s": Vector3(0.6, 0.55, 0.6), "look": "plant"},
	{"name": "plant_e", "k": "cyl", "p": Vector3(16.7, 0.275, -2.5), "s": Vector3(0.6, 0.55, 0.6), "look": "plant"},
	{"name": "plant_sw", "k": "cyl", "p": Vector3(-2.95, 0.275, 9.45), "s": Vector3(0.6, 0.55, 0.6), "look": "plant"},
	{"name": "plant_se", "k": "cyl", "p": Vector3(2.95, 0.275, 9.45), "s": Vector3(0.6, 0.55, 0.6), "look": "plant"},
]
## Movers: rock by `amp` degrees about `axis` through `pivot`, one swing every `period` seconds. `parts` in the pivot's frame.
const MOVERS := [
	{"name": "swing", "pivot": Vector3(-7.6, 2.85, -10.7), "axis": Vector3.BACK, "amp": 30.0, "period": 3.4, "phase": 0.0,
		"parts": [{"p": Vector3(0.0, -2.5, 0.0), "s": Vector3(0.7, 0.1, 1.8)}], "rope": 2.45},
	{"name": "seesaw", "pivot": Vector3(7.6, 0.55, 6.8), "axis": Vector3.RIGHT, "amp": 12.0, "period": 3.0, "phase": 0.4,
		"parts": [{"p": Vector3(0.0, 0.06, 0.0), "s": Vector3(0.6, 0.12, 4.0)}]},
]
## The trampoline: feet landing within `rad` of its middle at about the mat's height bounce up at `up` m/s (apex under the wall tops).
const TRAMPOLINE := {"p": Vector3(0.0, 0.4, -9.4), "rad": 1.3, "below": 0.1, "above": 0.35, "up": 9.5}
## The slide: feet on the chute (its top face, `frame` at the middle of it) slide down it at `speed` m/s.
const SLIDE := {"p": Vector3(8.7, 0.8, -10.1), "r": Vector3(23.96, 0, 0), "half": Vector3(0.6, 0.6, 1.97), "speed": 7.5}
## Yard floor kept clear of furniture right behind the spawn rows: loose props can lie here.
const PROP_AREA := Rect2(-2.4, 7.3, 4.8, 2.3)

var movers: Array = []         ## {row, body}
var animated: Array = []       ## client look: {node, base, kind} posed with the clock: "bounce" hops, "spin" turns about its z axis
var _bounced := {}             ## slot -> true while its feet are in the trampoline volume
var _slide_frame := Transform3D()

static func euler(degrees: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)), EULER_ORDER_YXZ)

## The shared clock of the movers: seconds of the wall clock, the same on every peer.
static func clock() -> float:
	return Time.get_unix_time_from_system()

## A mover's rotation at time `t`.
static func swing_basis(row: Dictionary, t: float) -> Basis:
	var angle := deg_to_rad(float(row.amp)) * sin(TAU * t / float(row.period) + TAU * float(row.phase))
	return Basis(row.axis as Vector3, angle)

## Builds the bodies under `room` and returns them (each with meta "layer", the room switches them with the yard).
func build(room: Node3D) -> Array:
	var holder := Node3D.new()
	holder.name = "Playground"
	room.add_child(holder)
	var bodies: Array = []
	for row: Dictionary in SOLIDS:
		var body := StaticBody3D.new()
		body.name = str(row.name)
		holder.add_child(body)
		body.global_transform = Transform3D(euler(row.get("r", Vector3.ZERO)), Layout.ORIGIN + (row.p as Vector3))
		_shape(body, row.k, row.s, Transform3D.IDENTITY)
		body.collision_layer = LAYER
		body.collision_mask = 0
		body.set_meta("layer", LAYER)
		bodies.append(body)
	for row: Dictionary in MOVERS:
		var body := AnimatableBody3D.new()
		body.name = "Mover_" + str(row.name)
		body.sync_to_physics = true
		body.collision_layer = MOVER_LAYER
		body.collision_mask = 0
		body.set_meta("layer", MOVER_LAYER)
		for part: Dictionary in row.parts: _shape(body, "box", part.s, Transform3D(Basis(), part.p))
		holder.add_child(body)
		movers.append({"row": row, "body": body})
		bodies.append(body)
	_slide_frame = Transform3D(euler(SLIDE.r), Layout.ORIGIN + (SLIDE.p as Vector3))
	pose(clock())
	return bodies

static func _shape(body: CollisionObject3D, kind: String, size: Vector3, at: Transform3D) -> void:
	var node := CollisionShape3D.new()
	if kind == "cyl":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x * 0.5
		cylinder.height = size.y
		node.shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = size
		node.shape = box
	node.transform = at
	body.add_child(node)

## Poses the movers and the client's animated dressing at time `t`.
func pose(t: float) -> void:
	for mover: Dictionary in movers:
		(mover.body as Node3D).global_transform = Transform3D(swing_basis(mover.row, t), Layout.ORIGIN + (mover.row.pivot as Vector3))
	for entry: Dictionary in animated:
		var node: Node3D = entry.node
		if entry.kind == "bounce":
			node.position = (entry.base as Vector3) + Vector3(0.0, absf(sin(t * PI / 1.1)) * 1.1, 0.0)
			node.rotation = Vector3(fposmod(t * 1.3, TAU), fposmod(t * 0.7, TAU), 0.0)
		else:
			node.position = entry.base
			node.rotation = Vector3(0.0, 0.0, -fposmod(t * 3.0, TAU))

## One physics tick of the yard: the movers, then the trampoline and the slide on the couriers `run` simulates on this peer.
func tick(run: Node) -> void:
	pose(clock())
	if run == null or not "motions" in run: return
	for slot: int in _simulated(run):
		var body: CharacterBody3D = run.actors[slot]
		var motion = run.motions[slot]
		if motion == null: continue
		var feet := body.global_position - Layout.ORIGIN
		var flat := Vector2(feet.x - TRAMPOLINE.p.x, feet.z - TRAMPOLINE.p.z)
		var height: float = feet.y - TRAMPOLINE.p.y
		var on_mat: bool = flat.length() <= float(TRAMPOLINE.rad) and height >= -float(TRAMPOLINE.below) and height <= float(TRAMPOLINE.above)
		if on_mat and not _bounced.has(slot):
			motion.launch(Vector3(0.0, float(TRAMPOLINE.up), 0.0), false, true)
			if run.audio != null: run.audio.play_push()
		if on_mat: _bounced[slot] = true
		else: _bounced.erase(slot)
		var local := _slide_frame.affine_inverse() * body.global_position
		var half: Vector3 = SLIDE.half
		if absf(local.x) <= half.x and local.y >= -0.05 and local.y <= half.y and absf(local.z) <= half.z:
			var down := _slide_frame.basis.z
			motion.launch(Vector3(down.x, 0.0, down.z).normalized() * float(SLIDE.speed), true, false)

## The slots whose movement runs on this peer: every active one on a local run, the owner's own on a replica, none on the authority.
static func _simulated(run: Node) -> Array:
	var slots: Array = []
	if run.network_role == "local":
		for slot in run.carrier_count:
			if run.is_slot_active(slot): slots.append(slot)
	elif run.network_role == "replica" and run.owner_courier != null and run.owner_courier.configured:
		slots.append(int(run.owner_courier.seat))
	return slots
