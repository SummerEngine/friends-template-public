extends Node
## Catchphrases (docs/slots.md): when the painting breaks, a courier falls or the team reaches the goal, the cast member's catchphrase
## (TeamCast.player(seat).catchphrase) pops up in a clean speech bubble over that courier for a moment, with one of their voice
## clips at random (TeamCast.voices(seat): demo/cast/voice/member_<n>.ogg and the variants member_<n>_<k>.ogg) when the cast has
## any. At the goal every courier with a catchphrase says it, one after the other. Client only and pure look: it reads the round state the HUD gets (breaks, failure_kind, won, resets) and the
## simulation's couriers; it changes nothing.
const TeamCast := preload("res://style/team_cast.gd")
const Ui := preload("res://client/friends_ui.gd")
const WorldLabel := preload("res://client/world_label.gd")
const SHOWN := 2.6              ## seconds a bubble stays
const POP := 0.2                ## seconds it takes to pop up (and to go)
const HEIGHT := 3.0             ## bubble centre over a courier's feet (the name tag is at 2.3)
const GOAL_STAGGER := 0.55      ## seconds between the bubbles at the goal
const FONT_SIZE := 52
const PIXEL := 0.0056           ## metres per font pixel (a little bigger than the name tags)
const WRAP_PX := 620.0          ## a long catchphrase wraps at this width
const PAD := Vector2(0.16, 0.1)
const BASE_SCALE_DISTANCE := 6.0
const MAX_GROWTH := 2.2

var simulation: Node
var _breaks := -1
var _resets := -1
var _won := false
var _by_slot: Array = []
var _holder: Node3D
var _bubbles: Array = []        ## {node, slot, age, delay, voice}
var _voice: AudioStreamPlayer

## One round state (the local hud_state() or a snapshot): a new break, fall or goal pops the bubbles.
func observe(state: Dictionary) -> void:
	if simulation == null or not is_instance_valid(simulation): return
	var breaks := int(state.get("breaks", 0))
	var resets := int(state.get("resets", 0))
	var won := bool(state.get("won", false))
	var fresh := _breaks < 0 or breaks < _breaks or resets < _resets # first state or a new run: a baseline, not an event
	if not fresh and breaks > _breaks:
		_say(_culprit("fall" if str(state.get("failure_kind", "")) == "death" else "break"), 0.0)
	if not fresh and won and not _won:
		var delay := 0.0
		for slot in _actors().size():
			if _say(slot, delay): delay += GOAL_STAGGER
			_cheer(slot)
	_breaks = breaks
	_resets = resets
	_won = won
	var by_slot: Variant = simulation.get("breaks_by_slot")
	_by_slot = (by_slot as Array).duplicate() if by_slot is Array else []

## The cast's emote for the courier at `slot` (players[i].emote) at the goal; a rig that is still carrying or has none skips it.
func _cheer(slot: int) -> void:
	var rigs: Variant = simulation.get("rigs")
	if rigs is Array and slot < (rigs as Array).size() and rigs[slot] != null and is_instance_valid(rigs[slot]) and rigs[slot].has_method("play_cast_emote"):
		rigs[slot].play_cast_emote()

func _actors() -> Array:
	var actors: Variant = simulation.get("actors")
	return actors if actors is Array else []

## The cast seat a courier slot shows (online the seat behind a slot is the rig's tint), the slot itself without a rig.
func _seat(slot: int) -> int:
	var rigs: Variant = simulation.get("rigs")
	if rigs is Array and slot < (rigs as Array).size() and rigs[slot] != null and is_instance_valid(rigs[slot]):
		var tint: Variant = rigs[slot].get("tint_index")
		if tint is int: return tint
	return slot

## Who broke it: the slot whose break count went up (local play keeps one), else the lowest courier for a fall and the faster one for
## a break (the authority's own rule, game/game_run.gd).
func _culprit(kind: String) -> int:
	var by_slot: Variant = simulation.get("breaks_by_slot")
	if by_slot is Array and (by_slot as Array).size() == _by_slot.size():
		for slot in _by_slot.size():
			if int(by_slot[slot]) > int(_by_slot[slot]): return slot
	var actors := _actors()
	var best := 0
	for slot in actors.size():
		var actor: Node3D = actors[slot]
		var leader: Node3D = actors[best]
		if kind == "fall" and actor.global_position.y < leader.global_position.y: best = slot
		elif kind == "break" and actor is CharacterBody3D and leader is CharacterBody3D and (actor as CharacterBody3D).velocity.length() > (leader as CharacterBody3D).velocity.length(): best = slot
	return best

## Queues the bubble of `slot` after `delay` seconds; false when its cast member has no catchphrase.
func _say(slot: int, delay: float) -> bool:
	if slot < 0 or slot >= _actors().size(): return false
	var seat := _seat(slot)
	var line := str(TeamCast.player(seat).catchphrase)
	if line == "": return false
	for bubble: Dictionary in _bubbles:
		if bubble.slot == slot: _drop(bubble) # a new line replaces that courier's last one
	_bubbles = _bubbles.filter(func(bubble: Dictionary) -> bool: return bubble.slot != slot)
	var node := _bubble(line)
	node.visible = false
	_world_holder().add_child(node)
	var clips := TeamCast.voices(seat)
	_bubbles.append({"node": node, "slot": slot, "age": -delay, "voice": clips.pick_random() if not clips.is_empty() else null})
	return true

func _drop(bubble: Dictionary) -> void:
	if is_instance_valid(bubble.node): bubble.node.queue_free()

func _world_holder() -> Node3D:
	var world: Variant = simulation.get("world")
	var parent: Node = world if world is Node3D else simulation
	if _holder == null or not is_instance_valid(_holder) or _holder.get_parent() != parent:
		_holder = Node3D.new()
		_holder.name = "CastBubbles"
		parent.add_child(_holder)
	return _holder

func _process(delta: float) -> void:
	if _bubbles.is_empty(): return
	var camera := get_viewport().get_camera_3d()
	var actors: Array = _actors() if simulation != null and is_instance_valid(simulation) else []
	for bubble: Dictionary in _bubbles:
		var node: Node3D = bubble.node
		if not is_instance_valid(node) or int(bubble.slot) >= actors.size():
			_drop(bubble)
			bubble.age = SHOWN
			continue
		var was := float(bubble.age)
		bubble.age = was + delta
		if was < 0.0 and bubble.age >= 0.0: _play(bubble.voice)
		if bubble.age < 0.0: continue
		if bubble.age >= SHOWN:
			_drop(bubble)
			continue
		var feet: Vector3 = (actors[bubble.slot] as Node3D).global_position
		node.global_position = feet + Vector3(0.0, HEIGHT, 0.0)
		node.visible = true
		var growth := 1.0
		if camera != null: growth = clampf(camera.global_position.distance_to(node.global_position) / BASE_SCALE_DISTANCE, 1.0, MAX_GROWTH)
		var pop := minf(float(bubble.age) / POP, 1.0)
		pop = 1.0 + 2.2 * pow(pop - 1.0, 3.0) + 1.2 * pow(pop - 1.0, 2.0) # out-back
		var leave := clampf((SHOWN - float(bubble.age)) / POP, 0.0, 1.0)
		node.scale = Vector3.ONE * maxf(growth * pop * leave, 0.01)
	_bubbles = _bubbles.filter(func(bubble: Dictionary) -> bool: return float(bubble.age) < SHOWN)

func _play(stream: AudioStream) -> void:
	if stream == null: return
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		_voice.name = "CastVoice"
		_voice.bus = &"GW_Voice" # [audio] Settings: Voice volume (game/game_audio.gd VOICE_BUS)
		add_child(_voice)
	_voice.stream = stream
	_voice.play()

func _exit_tree() -> void:
	if _holder != null and is_instance_valid(_holder): _holder.queue_free()

# ------------------------------------------------------------------ the bubble

## A white rounded bubble with a small tail down to the courier, the line in ink Inter; flat, no edge; always on top.
static func _bubble(line: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Bubble"
	var font := Ui.inter(700)
	var text_size := font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, WRAP_PX, FONT_SIZE)
	var size := (text_size * PIXEL + PAD * 2.0).max(Vector2(0.9, 0.4))
	root.add_child(WorldLabel.mesh(WorldLabel.bubble_shape(size, minf(0.14, size.y * 0.5)), WorldLabel.LIGHT, 6, true))
	var label := Label3D.new()
	label.text = line
	label.font = font
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL
	label.modulate = Ui.INK
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.shaded = false
	label.render_priority = 7
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = WRAP_PX
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(label)
	return root
