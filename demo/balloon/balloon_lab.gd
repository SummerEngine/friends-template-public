extends Node3D
## Balloon lab: balloon mode, player contact (shove, pick up, throw) and loose props (a box, a ball, a cone to pick up, carry,
## throw and knock out of hands: players/prop_sim.gd) on a flat test yard, with no course data.
## A start pad, a wall, a low beam, a goal zone, and capsule players with the courier's size and movement numbers
## (core_capsule_motion.gd defaults).
##
##   "$SUMMER" --path demo res://balloon/balloon_lab.tscn                         # you (WASD, Space, E grab/throw) + 2 bots
##   "$SUMMER" --path demo res://balloon/balloon_lab.tscn -- --balloon-players=5   # you + 4 bots
##
## tools/balloon_check.gd and tools/contact_check.gd drive the same scene headless. A test scene: the game never loads it.
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const BalloonLook := preload("res://balloon/balloon_look.gd")
const PlayerContact := preload("res://players/player_contact.gd")
const TeamCast := preload("res://style/team_cast.gd")
const PropSim := preload("res://players/prop_sim.gd")
const PropLook := preload("res://players/prop_look.gd")

const WALK_SPEED := 5.0
const ACCELERATION := 30.0
const GRAVITY := 17.15
const JUMP_SPEED := 7.0
const AIR_CONTROL := 0.2 ## share of the ground acceleration in the air: a throw or a shove in the air carries
const START := Vector3(0.0, 0.0, 0.0)
const GOAL := AABB(Vector3(-3.0, 0.0, -24.0), Vector3(6.0, 6.0, 4.0))
## Checkpoint lines (z): once the balloon crosses one alive, a pop respawns it there, like the course checkpoints.
const CHECKPOINTS := [-8.0, -16.0]
const PROPS := [{"kind": "box", "position": Vector3(3.5, 0.25, 1.5)}, {"kind": "ball", "position": Vector3(-3.5, 0.25, 1.5)},
	{"kind": "cone", "position": Vector3(3.5, 0.22, 3.5)}]

## Set before the node enters the tree (tests), or from the command line. A human plays seat 0 (keyboard).
var player_count := 3
var human := true
var bot_mode := "carry" ## carry: bots take it to the goal | keep: bots only keep it up where it is | idle: bots stand still
var with_balloon := true
var prop_layout: Array = PROPS ## the loose props (tests set their own; [] for none)
## Tests: seat -> {wish: Vector3, jump: bool, grab: bool} held this frame; overrides the human/bot for that seat.
var scripted := {}
var sim: BalloonSim
var contact: PlayerContact
var contact_counts := {"shove": 0, "grab": 0, "throw": 0, "drop": 0, "escape": 0}
var props: PropSim
var prop_counts := {"pick": 0, "throw": 0, "knock": 0}
var _held_keys := {} ## seat -> {jump, grab} last frame, for press edges
var players: Array[CharacterBody3D] = []
var reached_goal := false
var goal_seconds := -1.0
var elapsed := 0.0
var event_counts := {"bump": 0, "bounce": 0, "pop": 0, "respawn": 0}
var _look: Node3D
var _prop_look: Node3D
var _camera: Camera3D

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--balloon-players="): player_count = clampi(int(arg.trim_prefix("--balloon-players=")), 1, 8)
		if arg == "--balloon-bots": human = false
	_build_yard()
	for i in player_count: players.append(_build_player(i))
	contact = PlayerContact.new(player_count)
	props = PropSim.new(prop_layout)
	props.world_mask = 1
	_prop_look = PropLook.new()
	add_child(_prop_look)
	_prop_look.build(props)
	sim = BalloonSim.new(START + Vector3(0.0, 0.0, -1.0))
	_look = BalloonLook.new()
	_look.visible = with_balloon
	add_child(_look)
	if not DisplayServer.get_name() == "headless":
		_camera = Camera3D.new()
		_camera.fov = 60.0
		add_child(_camera)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
		add_child(sun)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("#f6ecd2")
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.6
		add_child(env)

func _physics_process(delta: float) -> void:
	elapsed += delta
	var inputs: Array = []
	var states: Array = []
	for i in players.size():
		var input := _seat_input(i)
		var last: Dictionary = _held_keys.get(i, {"jump": false, "grab": false})
		_held_keys[i] = {"jump": input.jump, "grab": input.grab}
		inputs.append(input)
		states.append({"position": players[i].global_position, "velocity": players[i].velocity,
			"jump": input.jump and not last.jump, "grab": input.grab and not last.grab})
	# GRAB presses: a prop holder's throws its prop; the others go to the contact, and pick up a prop when it did nothing with them.
	var prop_grabs: Array[bool] = []
	for i in players.size():
		prop_grabs.append(bool(states[i].grab) and props.holding(i) >= 0)
		if prop_grabs[i]: states[i].grab = false
	var touched := contact.step(delta, states)
	for event in touched.events: contact_counts[event.kind] = int(contact_counts.get(event.kind, 0)) + 1
	for i in players.size():
		if bool(states[i].grab) and PropSim.leftover_grab(touched.events, i): prop_grabs[i] = true
	for i in players.size(): _move_player(i, delta, inputs[i], touched.results[i])
	# Held players last, on top of where their holders are after this step's move.
	for i in players.size():
		var holder := int(touched.results[i].held_by)
		if holder >= 0:
			players[i].global_position = players[holder].global_position + Vector3.UP * PlayerContact.HOLD_HEIGHT
			players[i].velocity = players[holder].velocity
	var hands: Array = []
	for i in players.size():
		hands.append({"position": players[i].global_position + Vector3.DOWN * 0.9, "facing": contact.facing(i), "velocity": players[i].velocity,
			"grab": prop_grabs[i], "active": contact.held_by[i] < 0})
	for event in props.step(delta, get_world_3d().direct_space_state, hands): prop_counts[event.kind] = int(prop_counts.get(event.kind, 0)) + 1
	if not with_balloon: return
	var capsules: Array = []
	for body in players: capsules.append({"position": body.global_position, "velocity": body.velocity})
	for event in sim.step(delta, get_world_3d().direct_space_state, capsules):
		event_counts[event.kind] = int(event_counts.get(event.kind, 0)) + 1
	for line: float in CHECKPOINTS:
		if sim.alive and sim.position.z < line and sim.respawn_point.z > line: sim.respawn_point = Vector3(0.0, 0.0, line)
	if not reached_goal and sim.inside(GOAL):
		reached_goal = true
		goal_seconds = elapsed
		print("BALLOON_LAB goal seconds=%.1f pops=%d bumps=%d" % [elapsed, sim.pops, sim.bumps])

func _process(delta: float) -> void:
	_look.follow(sim, delta)
	_prop_look.follow(props, delta)
	if _camera != null:
		var focus := sim.position if sim.alive else sim.respawn_point
		_camera.global_position = _camera.global_position.lerp(focus + Vector3(0.0, 7.0, 11.0), clampf(delta * 3.0, 0.0, 1.0))
		_camera.look_at(focus + Vector3.DOWN * 0.5)

# ------------------------------------------------------------------ players
func _build_player(seat: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Player%d" % (seat + 1)
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BalloonSim.PLAYER_RADIUS
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = BalloonSim.PLAYER_RADIUS
	capsule_mesh.height = 1.8
	mesh.mesh = capsule_mesh
	mesh.material_override = BalloonLook._material(TeamCast.player_color(seat))
	body.add_child(mesh)
	add_child(body)
	var angle := TAU * seat / maxf(1.0, player_count)
	body.global_position = START + Vector3(cos(angle) * 1.6, 0.9, sin(angle) * 1.6 + 1.0)
	return body

## What seat `seat` wants this frame: {wish, jump, grab} (held, not edges).
func _seat_input(seat: int) -> Dictionary:
	if scripted.has(seat):
		var given: Dictionary = scripted[seat]
		return {"wish": given.get("wish", Vector3.ZERO), "jump": bool(given.get("jump", false)), "grab": bool(given.get("grab", false))}
	if seat == 0 and human:
		var wish := Vector3(Input.get_axis("ui_left", "ui_right"), 0.0, Input.get_axis("ui_up", "ui_down"))
		for pair in [[KEY_A, Vector3.LEFT], [KEY_D, Vector3.RIGHT], [KEY_W, Vector3.FORWARD], [KEY_S, Vector3.BACK]]:
			if Input.is_physical_key_pressed(pair[0]): wish += pair[1]
		return {"wish": wish, "jump": Input.is_physical_key_pressed(KEY_SPACE), "grab": Input.is_physical_key_pressed(KEY_E)}
	if bot_mode == "idle" or not with_balloon: return {"wish": Vector3.ZERO, "jump": false, "grab": false}
	var plan := _bot(seat)
	return {"wish": plan.wish, "jump": plan.jump, "grab": false}

## Movement with the contact results: a held player rides above its holder; a staggered one barely steers;
## shoves and throws arrive as an impulse on top of the walk.
func _move_player(seat: int, delta: float, input: Dictionary, touch: Dictionary) -> void:
	var body := players[seat]
	if int(touch.held_by) >= 0: return # placed after the holders have moved (_physics_process)
	var wish: Vector3 = input.wish.limit_length(1.0) * WALK_SPEED * float(touch.speed_scale)
	var control := ACCELERATION * (0.15 if float(touch.stagger) > 0.0 else 1.0) * (1.0 if body.is_on_floor() else AIR_CONTROL)
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(wish, control * delta)
	if touch.separate != Vector3.ZERO: body.move_and_collide(touch.separate)
	body.velocity = Vector3(flat.x, body.velocity.y - GRAVITY * delta, flat.z) + touch.impulse
	if input.jump and body.is_on_floor() and touch.impulse.y <= 0.0: body.velocity.y = JUMP_SPEED
	body.move_and_slide()

## A simple bot: stand under the balloon's landing spot (on the far side from the goal in carry mode, so every
## header sends it goalwards) and jump when it comes down into reach.
func _bot(seat: int) -> Dictionary:
	var body := players[seat]
	# carry: head it to the goal | keep: head it back over its spawn point
	var aim := GOAL.get_center() if bot_mode == "carry" else sim.respawn_point
	if not sim.alive:
		var wait := sim.respawn_point - ((aim - sim.respawn_point) * Vector3(1, 0, 1)).normalized() * 0.6
		return {"wish": ((wait - body.global_position) * Vector3(1, 0, 1)).limit_length(1.0), "jump": false}
	var landing := sim.position + Vector3(sim.velocity.x, 0.0, sim.velocity.z) * 0.6
	var to_goal := (aim - sim.position) * Vector3(1, 0, 1)
	var behind := -to_goal.normalized() * 0.45 if to_goal.length() > 0.5 else Vector3.ZERO
	# Seats fan out a little so the bots don't stand inside each other.
	var fan := Vector3(cos(seat * 2.4), 0.0, sin(seat * 2.4)) * 0.5 * float(seat > 0)
	var target := Vector3(landing.x, body.global_position.y, landing.z) + behind + fan
	var offset := (target - body.global_position) * Vector3(1, 0, 1)
	var wish := offset.normalized() if offset.length() > 0.15 else Vector3.ZERO
	var height := sim.position.y - (body.global_position.y + 0.9)
	var near := Vector2(sim.position.x - body.global_position.x, sim.position.z - body.global_position.z).length() < 1.0
	var jump := near and sim.velocity.y < 0.0 and height + sim.velocity.y * 0.3 < 1.0 ## where it will be when the jump meets it
	# Carry: run goalwards into the header so the balloon takes the bot's speed towards the goal.
	if near and (jump or not body.is_on_floor()) and to_goal.length() > 0.5: wish = to_goal.normalized() * (1.0 if bot_mode == "carry" else 0.4)
	return {"wish": wish, "jump": jump}

# ------------------------------------------------------------------ yard
func _build_yard() -> void:
	_box("Floor", Vector3(0.0, -0.5, -10.0), Vector3(24.0, 1.0, 40.0), Color("#f0d9a6"))
	_box("Wall", Vector3(-6.0, 1.5, -10.0), Vector3(0.6, 3.0, 8.0), Color("#2c4bff"))
	_box("Beam", Vector3(2.0, 3.6, -14.0), Vector3(5.0, 0.5, 0.5), Color("#ffd23f"))
	var goal := MeshInstance3D.new()
	goal.name = "GoalPad"
	var pad := BoxMesh.new()
	pad.size = Vector3(GOAL.size.x, 0.04, GOAL.size.z)
	goal.mesh = pad
	goal.material_override = BalloonLook._material(Color("#2ec27e"))
	goal.position = Vector3(GOAL.get_center().x, 0.02, GOAL.get_center().z)
	add_child(goal)

func _box(name_: String, centre: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = name_
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = BalloonLook._material(color)
	body.add_child(mesh)
	body.position = centre
	add_child(body)
