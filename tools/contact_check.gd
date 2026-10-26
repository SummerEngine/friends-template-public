extends SceneTree
## Headless check of shoving and picking up in the balloon lab (no course data needed):
##
##   "$SUMMER" --headless --fixed-fps 60 --path demo -s "$PWD/tools/contact_check.gd"
##
## 1. Shove: A runs into B standing still; B is pushed on in A's direction, staggers, and they end up apart.
## 2. Crowd: four players start inside each other; they settle apart.
## 3. Pick up: A grabs B next to it; B rides above A while A walks, and B's own input does nothing.
## 4. Throw: A presses grab again; B flies forward and lands well ahead of A.
## 5. Escape: B mashes jump and gets free; then can't be grabbed again straight away.
## 6. Reach: A too far away grabs nothing; a held player and a holder can't be grabbed.
## 7. Props: A picks up the box in front, carries it at its chest and throws it; the box knocks the cone out of C's hands; walking
##    into the ball kicks it; a holder's GRAB throws the prop, not the player in front; grabbing a holder knocks its prop out.
## 8. Push: A and B walk into each other at full speed for 5 s: nobody rises faster than 0.5 m/s or leaves the floor.
## Prints CONTACT_CHECK ok=<bool> and exits 0 only when all pass.
const Lab := preload("res://balloon/balloon_lab.gd")
const PlayerContact := preload("res://players/player_contact.gd")
const PropSim := preload("res://players/prop_sim.gd")
var failures: Array[String] = []
var completed := 0 ## scenarios that ran to their end: a scenario that crashes must not pass silently

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _shove()
	await _crowd()
	await _pick_throw()
	await _escape()
	await _reach()
	await _props()
	await _push()
	if completed != 7: failures.append("only %d of 7 scenarios ran to the end (script error above)" % completed)
	for failure in failures: printerr("CONTACT_CHECK_FAIL ", failure)
	print("CONTACT_CHECK ok=", failures.is_empty(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _lab(count: int, props := []) -> Node3D:
	var lab: Node3D = Lab.new()
	lab.player_count = count
	lab.prop_layout = props
	lab.human = false
	lab.with_balloon = false
	lab.bot_mode = "idle"
	root.add_child(lab)
	return lab

func _place(lab: Node3D, seat: int, at: Vector3) -> void:
	lab.players[seat].global_position = at + Vector3.UP * 0.9
	lab.players[seat].velocity = Vector3.ZERO

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _settle(lab: Node3D) -> void:
	await _frames(20) # land on the floor

func _done(lab: Node3D) -> void:
	lab.queue_free()
	await process_frame

func _shove() -> void:
	var lab := _lab(2)
	await physics_frame
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -3))
	await _settle(lab)
	var b_start: Vector3 = lab.players[1].global_position
	lab.scripted = {0: {"wish": Vector3.FORWARD}}
	await _frames(45)
	lab.scripted = {}
	await _frames(30)
	var moved: Vector3 = lab.players[1].global_position - b_start
	var gap: Vector3 = (lab.players[1].global_position - lab.players[0].global_position) * Vector3(1, 0, 1)
	print("CONTACT_SHOVE b_moved=%.2f along=%.2f shoves=%d gap=%.2f" % [moved.length(), -moved.z, lab.contact_counts.shove, gap.length()])
	if -moved.z < 0.8: failures.append("shove: B only moved %.2f m in A's direction" % -moved.z)
	if lab.contact_counts.shove < 1: failures.append("shove: no stagger at running speed")
	if gap.length() < PlayerContact.RADIUS * 2.0 - 0.05: failures.append("shove: still inside each other (%.2f m)" % gap.length())
	await _done(lab)
	completed += 1

func _crowd() -> void:
	var lab := _lab(4)
	await physics_frame
	for i in 4: _place(lab, i, Vector3(0.05 * i, 0, 0.03 * i))
	await _frames(90)
	var closest := 99.0
	for a in 4:
		for b in range(a + 1, 4):
			closest = minf(closest, ((lab.players[a].global_position - lab.players[b].global_position) * Vector3(1, 0, 1)).length())
	print("CONTACT_CROWD closest=%.2f" % closest)
	if closest < PlayerContact.RADIUS * 2.0 - 0.08: failures.append("crowd: players still overlap (%.2f m apart)" % closest)
	await _done(lab)
	completed += 1

func _pick_throw() -> void:
	var lab := _lab(2)
	await physics_frame
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -0.9))
	await _settle(lab)
	# Face B (facing follows movement), then grab.
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	lab.scripted = {0: {"wish": Vector3.RIGHT}, 1: {"wish": Vector3.LEFT}}
	await _frames(60)
	var a: Vector3 = lab.players[0].global_position
	var b: Vector3 = lab.players[1].global_position
	var held: int = lab.contact.held_by[1]
	print("CONTACT_PICK held_by=%d grabs=%d b_above=%.2f b_off=%.2f a_x=%.2f" % [held, lab.contact_counts.grab, b.y - a.y, ((b - a) * Vector3(1, 0, 1)).length(), a.x])
	if held != 0: failures.append("pick up: B is not held by A")
	if absf(b.y - a.y - PlayerContact.HOLD_HEIGHT) > 0.05: failures.append("pick up: B is not above A's head")
	if ((b - a) * Vector3(1, 0, 1)).length() > 0.05: failures.append("pick up: B does not ride with A")
	if a.x < 2.0: failures.append("pick up: A did not walk while holding (x %.2f)" % a.x)
	# Throw: grab again while walking right.
	lab.scripted = {0: {"wish": Vector3.RIGHT, "grab": true}}
	await _frames(2)
	lab.scripted = {}
	await _frames(90)
	a = lab.players[0].global_position
	b = lab.players[1].global_position
	print("CONTACT_THROW throws=%d free=%s ahead=%.2f b_y=%.2f" % [lab.contact_counts.throw, lab.contact.held_by[1] == -1, b.x - a.x, b.y])
	if lab.contact_counts.throw < 1 or lab.contact.held_by[1] != -1: failures.append("throw: B was not thrown")
	if b.x - a.x < 2.5: failures.append("throw: B landed only %.2f m ahead" % (b.x - a.x))
	if b.y > 1.0: failures.append("throw: B did not land (y %.2f)" % b.y)
	await _done(lab)
	completed += 1

func _escape() -> void:
	var lab := _lab(2)
	await physics_frame
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -0.9))
	await _settle(lab)
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	for press in PlayerContact.ESCAPE_PRESSES:
		lab.scripted = {1: {"jump": true}}
		await _frames(3)
		lab.scripted = {}
		await _frames(3)
	var free: bool = lab.contact.held_by[1] == -1
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	var regrabbed: bool = lab.contact.held_by[1] == 0
	print("CONTACT_ESCAPE escapes=%d free=%s regrabbed=%s" % [lab.contact_counts.escape, free, regrabbed])
	if not free: failures.append("escape: B is still held after %d jumps" % PlayerContact.ESCAPE_PRESSES)
	if regrabbed: failures.append("escape: B was grabbed again at once")
	await _done(lab)
	completed += 1

func _reach() -> void:
	var lab := _lab(3)
	await physics_frame
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -2.0))
	_place(lab, 2, Vector3(3, 0, 0))
	await _settle(lab)
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(4)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	var far_grab: bool = lab.contact.held_by[1] != -1
	# C picks up A; then B can't take A off C's head, and A can't grab anyone while held.
	lab.scripted = {}
	_place(lab, 2, lab.players[0].global_position - Vector3(0.9, 0.9, 0))
	await _frames(2)
	lab.scripted = {2: {"wish": Vector3.RIGHT * 0.2}}
	await _frames(6)
	lab.scripted = {2: {"grab": true}}
	await _frames(2)
	var c_holds_a: bool = lab.contact.held_by[0] == 2
	_place(lab, 1, lab.players[2].global_position + Vector3(0.0, -0.9, -0.8))
	lab.scripted = {1: {"grab": true}, 0: {"grab": true}}
	await _frames(2)
	print("CONTACT_REACH far_grab=%s c_holds_a=%s held=%s" % [far_grab, c_holds_a, lab.contact.held_by])
	if far_grab: failures.append("reach: grabbed someone 2 m away")
	if not c_holds_a: failures.append("reach: setup failed, C did not pick up A")
	if lab.contact.held_by[0] != 2: failures.append("reach: A was taken off C's head")
	if lab.contact.held_by[2] != -1 or lab.contact.held_by[1] != -1: failures.append("reach: a holder or a held player grabbed someone")
	await _done(lab)
	completed += 1

## 7. Props: A picks up the box in front and it rides in front of A's chest; GRAB again throws it well ahead; a player walking
## into the ball kicks it along; a thrown box knocks the cone out of C's hands; grabbing a holder knocks its prop out too; a
## holder's GRAB throws its prop even with a player in front.
func _props() -> void:
	var lab := _lab(3, [{"kind": "box", "position": Vector3(0, 0.25, -0.9)}, {"kind": "ball", "position": Vector3(4, 0.25, 0)}, {"kind": "cone", "position": Vector3(-4, 0.22, -6)}])
	await physics_frame
	var props: PropSim = lab.props
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(8, 0, 6))
	_place(lab, 2, Vector3(-4, 0, -5.2))
	await _settle(lab)
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}, 2: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	lab.scripted = {0: {"grab": true}, 2: {"grab": true}}
	await _frames(2)
	lab.scripted = {0: {"wish": Vector3.LEFT}}
	await _frames(30)
	var a: Vector3 = lab.players[0].global_position
	var hand := PropSim.hold_point(a + Vector3.DOWN * 0.9, lab.contact.facing(0))
	print("CONTACT_PROP_PICK box_held_by=%d cone_held_by=%d off=%.2f picks=%d" % [props.held_by[0], props.held_by[2], props.positions[0].distance_to(hand), lab.prop_counts.pick])
	if props.held_by[0] != 0: failures.append("props: A did not pick up the box in front")
	if props.held_by[2] != 2: failures.append("props: C did not pick up the cone in front")
	if props.positions[0].distance_to(hand) > 0.1: failures.append("props: the box is not in front of A's chest (%.2f m off)" % props.positions[0].distance_to(hand))
	# Throw at C (A faces -Z towards C first): the box knocks the cone out of C's hands.
	_place(lab, 0, Vector3(-4, 0, -3.0))
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	var from: Vector3 = lab.players[0].global_position
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	lab.scripted = {}
	await _frames(70)
	print("CONTACT_PROP_THROW throws=%d box_free=%s knocks=%d cone_held_by=%d box_flew=%.2f box_y=%.2f" % [lab.prop_counts.throw, props.held_by[0] == -1, lab.prop_counts.knock, props.held_by[2], from.z - props.positions[0].z, props.positions[0].y])
	if lab.prop_counts.throw < 1 or props.held_by[0] != -1: failures.append("props: GRAB again did not throw the box")
	if lab.prop_counts.knock < 1 or props.held_by[2] != -1: failures.append("props: the thrown box did not knock the cone out of C's hands")
	if props.positions[0].y > 0.5: failures.append("props: the box did not come to rest on the floor (y %.2f)" % props.positions[0].y)
	# Kick: B runs into the ball on the floor.
	_place(lab, 1, Vector3(1.5, 0, 0))
	await _frames(4)
	var ball: Vector3 = props.positions[1]
	lab.scripted = {1: {"wish": Vector3.RIGHT}}
	await _frames(40)
	lab.scripted = {}
	await _frames(30)
	print("CONTACT_PROP_KICK ball_moved=%.2f" % (props.positions[1].x - ball.x))
	if props.positions[1].x - ball.x < 1.5: failures.append("props: walking into the ball moved it only %.2f m" % (props.positions[1].x - ball.x))
	# Grabbing a holder knocks its prop out; a holder's GRAB throws the prop, not the player in front.
	props.positions[1] = Vector3(0, 0.25, -0.9)
	props.velocities[1] = Vector3.ZERO
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -2.0))
	await _frames(10)
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	var picked: bool = props.held_by[1] == 0
	_place(lab, 1, Vector3(0, 0, -0.9))
	lab.scripted = {}
	await _frames(4)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	lab.scripted = {}
	var threw_prop: bool = props.held_by[1] == -1 and lab.contact.held_by[1] == -1
	await _frames(40)
	_place(lab, 0, Vector3(0, 0, 0))
	_place(lab, 1, Vector3(0, 0, -0.9))
	props.positions[1] = Vector3(0, 0.25, -1.9)
	props.velocities[1] = Vector3.ZERO
	await _frames(10)
	lab.scripted = {1: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(6)
	lab.scripted = {1: {"grab": true}}
	await _frames(2)
	var b_holds: bool = props.held_by[1] == 1
	lab.scripted = {0: {"wish": Vector3.FORWARD * 0.2}}
	await _frames(4)
	lab.scripted = {0: {"grab": true}}
	await _frames(2)
	lab.scripted = {}
	print("CONTACT_PROP_GRAB picked=%s threw_prop=%s b_holds=%s b_held_by=%d ball_held_by=%d" % [picked, threw_prop, b_holds, lab.contact.held_by[1], props.held_by[1]])
	if not picked or not threw_prop: failures.append("props: a holder's GRAB did not throw its prop (picked %s, threw %s)" % [picked, threw_prop])
	if not b_holds or lab.contact.held_by[1] != 0 or props.held_by[1] != -1: failures.append("props: grabbing a holder did not knock its prop out")
	await _done(lab)
	completed += 1

func _push() -> void:
	var lab := _lab(2)
	await physics_frame
	_place(lab, 0, Vector3(0, 0, 8)) # along the yard's long side: the one who wins the shove drives the other 25 m
	_place(lab, 1, Vector3(0, 0, 6.8))
	await _settle(lab)
	lab.scripted = {0: {"wish": Vector3.FORWARD}, 1: {"wish": Vector3.BACK}}
	var worst := 0.0
	var airborne := 0
	for tick in 300:
		await physics_frame
		for body: CharacterBody3D in lab.players:
			worst = maxf(worst, absf(body.velocity.y))
			if not body.is_on_floor(): airborne += 1
	lab.scripted = {}
	print("CONTACT_PUSH vertical_speed=%.2f airborne_ticks=%d" % [worst, airborne])
	if worst > 0.5 or airborne > 0: failures.append("push: walking into each other lifted a player (%.2f m/s up, %d ticks off the floor)" % [worst, airborne])
	await _done(lab)
	completed += 1
