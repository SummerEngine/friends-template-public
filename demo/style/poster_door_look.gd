extends Node3D
## The poster doors' look (levels/poster_doors.gd, docs/party-show.md): client only, pure look, nothing here is read by a rule or sent anywhere.
## * a courier through an OPEN poster (the brand's LOGO poster, the one that tears) tears it: the board rips down to a scrap hanging from one corner (the doorway
##   behind it shows), a burst of paper pieces flies the way the courier went, the scrap swings for FLAP seconds, rolls up into the top edge of the doorway, and a
##   new poster rolls down from there (the door was passable all along): nothing pops, the board is always either the whole poster, the scrap, or a roll between the two;
## * a courier that bumps a SOLID poster (a PROBLEM poster, a wall) makes it shudder (a short wobble about its bottom edge, the way a board rattles when something hits it);
## * a `torn` door starts out already torn: the idea of the round shown once, the scrap swings gently and a courier through it sets it swinging;
## * a door that rides a slide hazard moves with it (follow(), the level clock), board and bare doorway together, torn or not.
## The boards are the frames SlotFrames built (Slot_obstacle_N holders, tagged with their slot's place in the level's `slots`); the look poses them.
const TeamCast := preload("res://style/team_cast.gd")
const PosterDoors := preload("res://levels/poster_doors.gd")

const RIP := 0.12 ## s the board takes to rip down to its scrap
const FLAP := 1.4 ## s the scrap hangs and swings before it rolls up
const ROLL_UP := 0.3 ## s the scrap takes to roll up into the top edge of the doorway
const ROLL_DOWN := 0.5 ## s the new poster takes to roll down from the top edge
const ROLL_MIN := 0.02 ## share of its height the rolled-up paper keeps (a thin roll at the top edge)
const REST := 0.2 ## rad the scrap hangs crooked from its corner
const WOBBLE := 0.6 ## s a bumped board shudders
const SCRAP := Vector2(0.3, 0.8) ## the scrap's size as a share of the board
const FRAME_BAR := 0.22 ## m, the bare doorway frame that shows where a board was torn off (always there, behind the poster)
const FRAME_COLOR := Color("#22b35a") ## the logo poster's green: a torn doorway is the way through, from a long way off
const INK_BIT := Color("#2d3052") ## the dark scraps of paper
const FRAME_BEHIND := 0.1 ## m behind the board's plane, in front of a solid door's block (level_lint.py DOOR_BLOCK_GAP is 0.125)
const FRAME_INSET := 0.18 ## m the bars stand in from the board's edges: the whole poster hides them from any ordinary view
const PIECES := 44 ## paper pieces per burst
const POOL := 6 ## bursts that can fly at once
const PAPER := Color("#fbf3e0")
const LOGO_GREEN := Color("#22b35a") ## the logo poster's green (style/slot_frames.gd draws the same one on the board)

var _doors := {} ## slot index -> {door, holder, base, size, side, state, t, wobble, kick, shift, frame}
var _riders: Array[Dictionary] = [] ## the entries of the doors that ride a slide hazard
var _bursts: Array[CPUParticles3D] = []
var _next := 0
var _clock := 0.0
var _mesh: QuadMesh

## The look of a level's poster doors, added to `root`. `doors`: PosterDoors.list, `slots`: the level's slots (for the sizes).
static func build(root: Node3D, doors: Array, slots: Array) -> Node3D:
	var look: Node3D = new()
	look.name = "PosterDoorLook"
	root.add_child(look)
	var holders := {}
	for child: Node in root.get_children():
		if child.has_meta("slot_index"): holders[int(child.get_meta("slot_index"))] = child
	for door: Dictionary in doors:
		look.call("_add", door, holders.get(int(door.index)), (slots[int(door.index)] as Dictionary).size)
	look.set_process(look.call("_busy"))
	return look

func _add(door: Dictionary, holder: Variant, size: Vector2) -> void:
	var entry := {"door": door, "holder": holder, "base": (holder as Node3D).transform if holder != null else Transform3D.IDENTITY, "size": size,
		"side": 1.0 if int(door.index) % 2 == 0 else -1.0, "state": "whole", "t": 0.0, "wobble": -1.0, "kick": 0.0, "shift": Vector3.ZERO,
		"frame": _frame(door, size) if str(door.kind) != "solid" else null} # the bare doorway shows only where a logo poster was torn off
	if str(door.kind) == "torn": entry.state = "torn"
	_doors[int(door.index)] = entry
	if not (door.ride as Dictionary).is_empty(): _riders.append(entry)
	_pose(entry)

## The level clock `clock` (every tick): the doors that ride a slide hazard move with it, board and bare doorway together.
func follow(clock: float) -> void:
	for entry: Dictionary in _riders:
		var moved := PosterDoors.travel(entry.door, clock)
		if moved.is_equal_approx(entry.shift): continue
		entry.shift = moved
		var frame: Variant = entry.frame
		if frame != null: (frame as Node3D).position = (entry.door.p as Vector3) - (entry.door.normal as Vector3) * FRAME_BEHIND + moved
		_pose(entry)

## A courier went through the door at slot `index` (`centre`: where its centre crossed, level-local space = this node's, `heading`: the way it went).
func burst(index: int, centre: Vector3, heading: Vector3) -> void:
	var entry: Variant = _doors.get(index)
	if entry == null: return
	if str(entry.state) == "torn":
		entry.kick = 1.0 # the hanging scrap swings
		entry.t = 0.0
	else:
		entry.state = "flap"
		entry.t = 0.0
		_confetti(entry, heading)
	set_process(true)

## A courier bumped the solid door at slot `index`.
func bonk(index: int) -> void:
	var entry: Variant = _doors.get(index)
	if entry == null: return
	entry.wobble = 0.0
	set_process(true)

## Every door whole again (a round starts over).
func reset() -> void:
	for entry: Dictionary in _doors.values():
		entry.state = "torn" if str(entry.door.kind) == "torn" else "whole"
		entry.t = 0.0
		entry.wobble = -1.0
		entry.kick = 0.0
		_pose(entry)
	for burst_node: CPUParticles3D in _bursts:
		burst_node.restart() # clears the pieces still in the air
		burst_node.emitting = false
	set_process(_busy())

func _busy() -> bool:
	for entry: Dictionary in _doors.values():
		if entry.state != "whole" or float(entry.wobble) >= 0.0: return true
	return false

func _process(delta: float) -> void:
	_clock += delta
	for entry: Dictionary in _doors.values():
		if entry.state == "flap":
			entry.t = float(entry.t) + delta
			if float(entry.t) >= FLAP + ROLL_UP + ROLL_DOWN:
				entry.state = "whole"
				entry.t = 0.0
		elif entry.state == "torn":
			entry.t = float(entry.t) + delta
			entry.kick = maxf(float(entry.kick) - delta / 1.2, 0.0)
		if float(entry.wobble) >= 0.0:
			entry.wobble = float(entry.wobble) + delta
			if float(entry.wobble) > WOBBLE: entry.wobble = -1.0
		_pose(entry)
	set_process(_busy())

## The board's transform now: its place, with the scrap pose (rip, swing, roll up, roll down) and the wobble on top.
func _pose(entry: Dictionary) -> void:
	var holder: Variant = entry.holder
	var torn := 0.0 # 0 whole, 1 scrap
	var roll := 1.0 # the share of its height that hangs unrolled from the top edge
	var angle := 0.0
	var t := float(entry.t)
	var state := str(entry.state)
	if state == "flap":
		if t < RIP: torn = 1.0 - pow(1.0 - t / RIP, 2.0)
		elif t < FLAP: torn = 1.0
		elif t < FLAP + ROLL_UP: # the scrap rolls up into the top edge ...
			torn = 1.0
			roll = lerpf(1.0, ROLL_MIN, pow((t - FLAP) / ROLL_UP, 2.0))
		else: # ... and the new poster rolls down out of it (the scrap's width grows into the poster's while it is still a thin roll)
			var unrolled := clampf((t - FLAP - ROLL_UP) / ROLL_DOWN, 0.0, 1.0)
			torn = 1.0 - smoothstep(0.0, 0.3, unrolled)
			roll = lerpf(ROLL_MIN, 1.0, 1.0 - pow(1.0 - unrolled, 2.0))
		var swing := exp(-maxf(t - RIP, 0.0) * 1.1)
		angle = (REST * torn + (0.5 * sin((t - RIP) * 9.0) * swing if t > RIP else 0.0)) * float(entry.side) * torn
	elif state == "torn":
		torn = 1.0
		angle = (REST + 0.07 * sin(_clock * 1.6 + float(int(entry.door.index))) + 0.45 * float(entry.kick) * sin(t * 9.0) * exp(-t * 1.4)) * float(entry.side)
	if holder == null: return
	var board := holder as Node3D
	var size: Vector2 = entry.size
	var side := float(entry.side)
	var shape := Vector2.ONE.lerp(SCRAP, torn) * Vector2(1.0, roll)
	var turn := Basis(Vector3.BACK, angle)
	var corner := Vector3(side * size.x * 0.5, size.y * 0.5, 0.0)
	var centre := corner + turn * Vector3(-side * shape.x * size.x * 0.5, -shape.y * size.y * 0.5, 0.0)
	var local := Transform3D(turn * Basis.from_scale(Vector3(shape.x, shape.y, 1.0)), centre) if torn > 0.0 or roll < 1.0 else Transform3D.IDENTITY
	var wobble := float(entry.wobble)
	if wobble >= 0.0:
		var tilt := 0.12 * absf(sin(wobble * 18.0)) * exp(-wobble * 6.5) # the top rattles towards the courier only: leaning back would sink the board into the block behind it
		var foot := Vector3(0.0, -size.y * 0.5, 0.0)
		local = Transform3D(Basis(Vector3.RIGHT, tilt), foot - Basis(Vector3.RIGHT, tilt) * foot) * local
	board.transform = Transform3D(Basis.IDENTITY, entry.shift) * (entry.base as Transform3D) * local

## The bare doorway frame behind a board: three flat dark bars (top, left, right) on the wall plane, just behind the board and in from its edges so the whole poster
## hides them; drawn on their front side only (nobody sees them from behind a poster). They are always there: nothing appears when a board is torn.
func _frame(door: Dictionary, size: Vector2) -> Node3D:
	var frame := Node3D.new()
	frame.name = "Doorway%d" % int(door.index)
	frame.transform = Transform3D(Basis.looking_at(-(door.normal as Vector3), Vector3.UP), (door.p as Vector3) - (door.normal as Vector3) * FRAME_BEHIND)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FRAME_COLOR
	var side_x := size.x * 0.5 - FRAME_INSET
	var top_y := size.y * 0.5 - FRAME_INSET
	var side_height := size.y - FRAME_INSET + FRAME_BAR * 0.5
	for bar: Array in [[Vector2(side_x * 2.0 + FRAME_BAR, FRAME_BAR), Vector3(0.0, top_y, 0.0)],
			[Vector2(FRAME_BAR, side_height), Vector3(-side_x, top_y + FRAME_BAR * 0.5 - side_height * 0.5, 0.0)],
			[Vector2(FRAME_BAR, side_height), Vector3(side_x, top_y + FRAME_BAR * 0.5 - side_height * 0.5, 0.0)]]:
		var piece := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = bar[0]
		piece.mesh = quad
		piece.material_override = material
		piece.position = bar[1]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(piece)
	add_child(frame)
	return frame

## The paper: a one-shot burst at the door, in the poster's colour, the brand's, white and ink, flying the way the courier went.
func _confetti(entry: Dictionary, heading: Vector3) -> void:
	var door: Dictionary = entry.door
	var size: Vector2 = entry.size
	var flight := Vector3(heading.x, 0.0, heading.z)
	if flight.length_squared() < 0.0001: flight = -(door.normal as Vector3)
	flight = flight.normalized() + Vector3.UP * 0.35
	var burst_node := _take()
	var colors: Array[Color] = [PAPER, INK_BIT, LOGO_GREEN, Color.WHITE]
	var accent := TeamCast.brand_accent()
	if accent.a > 0.0: colors.append(accent)
	colors.append(LOGO_GREEN.lerp(Color.WHITE, 0.5))
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var shades := PackedColorArray()
	for index in colors.size():
		offsets.append(float(index) / colors.size())
		shades.append(colors[index])
	ramp.offsets = offsets
	ramp.colors = shades
	burst_node.color_initial_ramp = ramp
	burst_node.position = (door.p as Vector3) + (entry.shift as Vector3) + (door.normal as Vector3) * 0.05
	burst_node.emission_box_extents = Vector3(size.x * 0.4, size.y * 0.4, 0.05)
	burst_node.direction = flight
	burst_node.restart()
	burst_node.emitting = true

func _take() -> CPUParticles3D:
	if _bursts.size() < POOL:
		_bursts.append(_particles())
		add_child(_bursts.back())
		return _bursts.back()
	var node := _bursts[_next]
	_next = (_next + 1) % POOL
	return node

func _particles() -> CPUParticles3D:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(0.2, 0.13)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.particles_anim_h_frames = 1
		material.particles_anim_v_frames = 1
		_mesh.material = material
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.7, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.7))
	shrink.add_point(Vector2(0.15, 1.0))
	shrink.add_point(Vector2(1.0, 0.55))
	var node := CPUParticles3D.new()
	node.name = "PaperBurst"
	node.mesh = _mesh
	node.amount = PIECES
	node.lifetime = 1.3
	node.one_shot = true
	node.explosiveness = 0.95
	node.local_coords = false
	node.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	node.spread = 60.0
	node.initial_velocity_min = 2.5
	node.initial_velocity_max = 6.5
	node.gravity = Vector3(0.0, -6.0, 0.0)
	node.damping_min = 0.8
	node.damping_max = 1.8
	node.angle_min = 0.0
	node.angle_max = 360.0
	node.angular_velocity_min = -540.0
	node.angular_velocity_max = 540.0
	node.scale_amount_curve = shrink
	node.color_ramp = fade
	node.emitting = false
	return node
