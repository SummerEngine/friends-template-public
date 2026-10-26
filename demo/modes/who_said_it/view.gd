extends "res://modes/mode_view.gd"
## WHO SAID IT? view (docs/modes/who_said_it.md), client only. Where the rules' pads() put them: one pad per character of the round
## (the lobby circles' paint in the character's colour, the name painted on its inner edge) and on its outer edge a statue of that
## character on a pedestal (the character rig in the cast look at half size, a figurine frozen in its emote, never a life-size copy
## a player would take for a double of themselves), a name tag over it. While the race runs the line
## hangs in a speech bubble over the ring's middle; at the reveal the right pad lights up, its statue plays its emote, the line goes
## over it (with the character's voice clip) and +3 / +1 rise over the scorers. The own pad brightens while the local player stands on
## it. Reads only the rules' state(). The pedestals are solid (the couriers bump into them); the paint is not.
const Rules := preload("res://modes/who_said_it/rules.gd")
const WalkInLook := preload("res://style/walk_in_look.gd")
const WorldLabel := preload("res://client/world_label.gd")
const CastBubbles := preload("res://client/cast_bubbles.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const HudComic := preload("res://client/hud_comic.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const Ui := preload("res://client/friends_ui.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Rig := preload("res://character/character_rig.gd")
const Look := preload("res://character/look.gd")

const PAD_RADIUS := 1.35 ## the painted ring: between the rules' ENTER and EXIT
const PAD_LIFT := 0.008 ## m over the yard's own floor paint
const NAME_IN := 0.62 ## m from the pad's middle towards the ring's middle: the painted name
const NAME_WIDTH := 1.7 ## m the painted name may take
const STATUE_OUT := 0.95 ## m from the pad's middle outwards: the statue
const PLINTH_RADIUS := 0.32
const PLINTH_HEIGHT := 1.0 ## a pedestal: the figurine stands at chest height, not beside the player like a second body
const STATUE_SCALE := 0.5 ## the figurine's size against the real character
const PLINTH_COLOR := Color("f4f4f2")
const BAND := 0.05 ## the character's colour round the plinth's top
const SOLID_HEIGHT := 1.95 ## the statue's collision: a cylinder of PLINTH_RADIUS round pedestal and figurine
const SOLID_LAYER := 1 | 512 ## the yard's solid layer (lobby_space.gd LAYER): the couriers bump into the statues
const POSE_SECONDS := 0.8 ## a statue whose character has an emote is frozen this far into it
const POSE_STEP := 1.0 / 30.0
const REVEAL_EMOTE := "point" ## a statue whose character has no emote points at the reveal
const TAG_HEIGHT := 2.55 ## the name tag over the statue's foot
const BUBBLE_HEIGHT := 3.3 ## the line's bubble over the answer's statue
const MIDDLE_HEIGHT := 3.0 ## the line's bubble over the ring's middle
const SCORE_HEIGHT := 2.6 ## +3 / +1 over a scorer's feet
const POP := 0.2 ## s a bubble takes to pop up
const BASE_DISTANCE := 6.0 ## tags and bubbles keep their size up to this far from the camera, then grow ...
const MAX_GROWTH := 2.4 ## ... up to this much
const FIT := 0.9 ## the line goes big on the HUD when it takes at most this share of the screen's width, else under it
const NOTE := "Run onto the pad of whoever says it  ·  WASD move  ·  Space jump  ·  F grab"
const INTRO_LINE := "A line shows: run to the pad of whoever says it. First there scores 3, everybody else there 1."

var _points: Array = [] ## Rules.pads(): {at, out} per slot
var _pads: Array = [] ## per slot: {ring, fill, color, foot, yaw, rig, emote, tag, moving}
var _bubbles: Array = [] ## {node, age}: the line over the middle (race) or over the answer (reveal)
var _seen := "" ## "<round>:<phase>" presented last
var _own_pad := -1 ## the pad the local player stands on during the race
var _clock := 0.0
var _measure ## a HUD word (client/comic_text.gd), never shown: whether a line fits big
var _fits := {}
var _voice: AudioStreamPlayer

func build() -> void:
	_points = Rules.pads(seats.size())
	for slot in _points.size(): _pads.append(_pad(slot, _points[slot]))
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"GW_Voice" # [audio] Settings: Voice volume (game/game_audio.gd VOICE_BUS)
	add_child(_voice)

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	var phase := str(state.get("phase", ""))
	var key := "%d:%s" % [int(state.get("round", 0)), phase]
	if key != _seen:
		var late := _seen == "" # joined mid-phase: the look, without the sounds
		_seen = key
		_enter(phase, state, late)
	_track_own(phase)
	_paint_pads(phase, _ints(state.get("answer", [])))
	_animate(dt)

func hud(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {"title": "WHO SAID IT?", "note": NOTE}
	var rounds := maxi(int(state.get("rounds", Rules.ROUNDS)), 1)
	var number := clampi(int(state.get("round", 1)), 1, rounds)
	var model := {"title": "WHO SAID IT?  ·  ROUND %d / %d" % [number, rounds], "big": "", "line": "", "timer": -1.0,
		"scores": _ints(state.get("scores", [])), "out": _ints(state.get("out", [])), "note": NOTE}
	match str(state.get("phase", "")):
		"ready":
			model.big = "GET READY"
			if number == 1: model.line = INTRO_LINE
		"run":
			var shown := Rules.prompt(str(state.get("line", "")), bool(state.get("ask", false)))
			if _fits_big(shown): model.big = shown
			else: model.line = shown
			model.timer = float(state.get("left", 0.0))
		"reveal":
			model.big = _names(_ints(state.get("answer", [])))
			model.line = _scorers(state)
	return model

# ------------------------------------------------------------------ phases

## A new phase: the line's bubble over the ring's middle while the race runs; the answer's bubble, emote, scores and sounds at the reveal.
func _enter(phase: String, state: Dictionary, late: bool) -> void:
	for bubble: Dictionary in _bubbles:
		if is_instance_valid(bubble.node): (bubble.node as Node).queue_free()
	_bubbles.clear()
	if phase == "run":
		_add_bubble(Rules.prompt(str(state.get("line", "")), bool(state.get("ask", false))), Rules.middle() + Vector3.UP * MIDDLE_HEIGHT)
		if not late: _sound("go")
	elif phase == "reveal":
		_reveal(state, late)

func _reveal(state: Dictionary, late: bool) -> void:
	var answer := _ints(state.get("answer", []))
	for slot: int in answer:
		if slot < 0 or slot >= _pads.size(): continue
		var pad: Dictionary = _pads[slot]
		_add_bubble(str(state.get("line", "")), (pad.foot as Vector3) + Vector3.UP * BUBBLE_HEIGHT)
		if pad.rig != null and is_instance_valid(pad.rig):
			pad.rig.play_emote(str(pad.emote) if str(pad.emote) != "" else REVEAL_EMOTE)
			pad.moving = Rules.REVEAL + 0.5
	var first := int(state.get("first", -1))
	var right := _ints(state.get("right", []))
	if first >= 0: _score(first, "+%d" % Rules.FIRST_POINTS)
	for slot: int in right: _score(slot, "+%d" % Rules.ON_POINTS)
	if late: return
	_sound("goal" if my_slot >= 0 and (my_slot == first or right.has(my_slot)) else "ui_stamp")
	if bool(state.get("ask", false)) or answer.is_empty(): return
	var clips := TeamCast.voices(int(seats[answer[0]]) if answer[0] < seats.size() else answer[0])
	if not clips.is_empty():
		_voice.stream = clips.pick_random()
		_voice.play()

## The pad under the local player while the race runs (its own position, as the rules would see it): it brightens at once.
func _track_own(phase: String) -> void:
	var pad := -1
	if phase == "run" and run != null and my_slot >= 0 and my_slot < run.actors.size(): pad = Rules.pad_under(feet(my_slot), _points, _own_pad)
	if pad >= 0 and pad != _own_pad: _sound("pad_enter", feet(my_slot))
	_own_pad = pad

## Resting paint; the own pad bright; at the reveal the right pads pulse and the others fade.
func _paint_pads(phase: String, answer: Array) -> void:
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 2.0)
	for slot in _pads.size():
		var pad: Dictionary = _pads[slot]
		var base: Color = pad.color
		var ring := base
		var fill := Color(base, 0.28)
		if phase == "reveal" and answer.has(slot):
			ring = base.lerp(Ui.WHITE, 0.35 + 0.5 * pulse)
			fill = Color(base, 0.5 + 0.2 * pulse)
		elif phase == "reveal":
			fill = Color(base, 0.12)
		elif slot == _own_pad:
			ring = base.lerp(Ui.WHITE, 0.45)
			fill = Color(base, 0.45)
		(pad.ring as StandardMaterial3D).albedo_color = ring
		(pad.fill as StandardMaterial3D).albedo_color = fill

## Tags and bubbles keep a readable size from afar, bubbles pop in, a statue plays its emote while it has time left, then freezes.
func _animate(dt: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for pad: Dictionary in _pads:
		var tag: Label3D = pad.tag
		tag.scale = Vector3.ONE * _growth(camera, tag.global_position)
		if float(pad.moving) > 0.0 and pad.rig != null and is_instance_valid(pad.rig):
			pad.moving = float(pad.moving) - dt
			pad.rig.update(dt, {"yaw": pad.yaw, "grounded": true, "velocity": Vector3.ZERO})
	for bubble: Dictionary in _bubbles:
		var node: Node3D = bubble.node
		if not is_instance_valid(node): continue
		bubble.age = float(bubble.age) + dt
		var pop := minf(float(bubble.age) / POP, 1.0)
		pop = 1.0 + 2.2 * pow(pop - 1.0, 3.0) + 1.2 * pow(pop - 1.0, 2.0) # out-back, as the cast's bubbles
		node.scale = Vector3.ONE * maxf(_growth(camera, node.global_position) * pop, 0.01)

# ------------------------------------------------------------------ building

func _pad(slot: int, point: Dictionary) -> Dictionary:
	var member := cast_player(slot)
	var color: Color = member.color
	var at: Vector3 = point.at
	var out: Vector3 = point.out
	var root := Node3D.new()
	root.name = "Pad%d" % (slot + 1)
	add_child(root)
	root.global_position = at + Vector3.UP * PAD_LIFT
	var paint := WalkInLook.pad(root, color, PAD_RADIUS)
	root.add_child(_floor_name(str(member.name), out))
	var foot := at + out * STATUE_OUT
	var yaw := atan2(out.x, out.z) # the statue faces the ring's middle (a rig looks down -Z)
	var statue := _statue(slot, color, foot, yaw)
	var tag := WorldLabel.make(str(member.name), 60, 0.0042, Color.WHITE, WorldLabel.DARK, 4)
	tag.name = "NameTag%d" % (slot + 1)
	tag.modulate = color.lerp(Color.WHITE, 0.55) # as the game's own name tags
	add_child(tag)
	tag.global_position = foot + Vector3.UP * TAG_HEIGHT
	return {"ring": paint.ring_material, "fill": paint.fill_material, "color": color, "foot": foot, "yaw": yaw, "rig": statue.rig,
		"emote": statue.emote, "tag": tag, "moving": 0.0}

## The character's name painted flat on the pad's inner edge, upright for a player coming from the ring's middle.
func _floor_name(text: String, out: Vector3) -> Label3D:
	var label := Label3D.new()
	label.name = "Name"
	label.text = text
	label.font = Ui.inter(800)
	label.pixel_size = 0.004
	var size := 120
	while size > 40 and label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * label.pixel_size > NAME_WIDTH: size -= 4
	label.font_size = size
	label.modulate = Ui.INK
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = -out * NAME_IN + Vector3.UP * 0.012
	label.rotation = Vector3(-PI * 0.5, atan2(-out.x, -out.z), 0.0) # lying on the floor, its top away from the middle
	return label

## A pedestal with the character's colour round its top, the character on it as a half-size figurine frozen in its emote, a solid
## cylinder round both.
## Without the body model in the build, a figure in the character's colour stands in.
func _statue(slot: int, color: Color, foot: Vector3, yaw: float) -> Dictionary:
	var plinth := _mesh(_cylinder(PLINTH_RADIUS, PLINTH_HEIGHT), PLINTH_COLOR)
	plinth.name = "Plinth%d" % (slot + 1)
	add_child(plinth)
	plinth.global_position = foot + Vector3.UP * PLINTH_HEIGHT * 0.5
	var band := _mesh(_cylinder(PLINTH_RADIUS + 0.01, BAND), color)
	band.position = Vector3.UP * (PLINTH_HEIGHT - BAND) * 0.5
	plinth.add_child(band)
	var solid := StaticBody3D.new()
	solid.name = "Solid%d" % (slot + 1)
	solid.collision_layer = SOLID_LAYER
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = PLINTH_RADIUS
	cylinder.height = SOLID_HEIGHT
	shape.shape = cylinder
	solid.add_child(shape)
	add_child(solid)
	solid.global_position = foot + Vector3.UP * SOLID_HEIGHT * 0.5
	var top := foot + Vector3.UP * PLINTH_HEIGHT
	if not Rig.available():
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.7
		var figure := _mesh(capsule, color)
		figure.name = "Statue%d" % (slot + 1)
		add_child(figure)
		figure.scale = Vector3.ONE * STATUE_SCALE
		figure.global_position = top + Vector3.UP * 0.85 * STATUE_SCALE
		return {"rig": null, "emote": ""}
	var seat := int(seats[slot]) if slot < seats.size() else slot
	var rig: Node3D = Rig.new()
	rig.name = "Statue%d" % (slot + 1)
	add_child(rig)
	rig.setup(seat, {"look": Look.defaults_for_seat(seat)})
	rig.scale = Vector3.ONE * STATUE_SCALE
	rig.global_position = top
	var emote: String = rig.cast_emote()
	var still := {"yaw": yaw, "grounded": true, "velocity": Vector3.ZERO}
	rig.snap(still)
	if emote != "":
		rig.play_emote(emote)
		for step in roundi(POSE_SECONDS / POSE_STEP): rig.update(POSE_STEP, still)
	return {"rig": rig, "emote": emote}

func _cylinder(radius: float, height: float) -> CylinderMesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 32
	cylinder.rings = 1
	return cylinder

func _mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	return node

# ------------------------------------------------------------------ helpers

## The cast's speech bubble (client/cast_bubbles.gd) with `text` at `at`; it pops in from nothing.
func _add_bubble(text: String, at: Vector3) -> void:
	if text == "": return
	var node := CastBubbles._bubble(text)
	node.scale = Vector3.ONE * 0.01
	add_child(node)
	node.global_position = at
	_bubbles.append({"node": node, "age": 0.0})

## +3 / +1 rising over a scorer (the game's gameplay word).
func _score(slot: int, text: String) -> void:
	if run == null or slot < 0 or slot >= run.actors.size(): return
	HazardLooks.word(self, text, feet(slot) + Vector3.UP * SCORE_HEIGHT)

func _sound(id: String, at: Variant = null) -> void:
	var audio: Variant = run.get("audio") if run != null else null
	if audio is Node and is_instance_valid(audio) and audio.has_method("play_event"): audio.play_event(id, at)

func _growth(camera: Camera3D, at: Vector3) -> float:
	return clampf(camera.global_position.distance_to(at) / BASE_DISTANCE, 1.0, MAX_GROWTH) if camera != null else 1.0

func _names(slots: Array) -> String:
	var names := PackedStringArray()
	for slot: int in slots: names.append(str(cast_player(slot).name))
	return " & ".join(names)

func _scorers(state: Dictionary) -> String:
	var parts := PackedStringArray()
	var first := int(state.get("first", -1))
	if first >= 0: parts.append("%s +%d" % [cast_player(first).name, Rules.FIRST_POINTS])
	for slot: int in _ints(state.get("right", [])): parts.append("%s +%d" % [cast_player(slot).name, Rules.ON_POINTS])
	return "  ·  ".join(parts) if not parts.is_empty() else "Nobody got it"

## True when `text` set as the HUD's big word (modes/mode_hud.gd) fits FIT of the screen's width; else it goes on the line under it.
func _fits_big(text: String) -> bool:
	if text == "": return false
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	var room := screen.x * FIT / clampf(screen.y / 720.0, 0.72, 2.4) # in the HUD's units (HudComic.unit_of)
	var key := "%s|%d" % [text, roundi(room)]
	if not _fits.has(key):
		if _measure == null: _measure = HudComic.word(text, ModeHud.BIG_CAP)
		else: HudComic.update(_measure, text, ModeHud.BIG_CAP)
		_fits[key] = float(_measure.custom_minimum_size.x) <= room
	return bool(_fits[key])

static func _ints(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for entry: Variant in value: result.append(int(entry))
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_measure): _measure.free()
