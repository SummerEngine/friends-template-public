extends "res://modes/mode_view.gd"
## FRIEND SWAP view (docs/modes/friend_swap.md). Client only: it reads the rules' state() (modes/friend_swap/rules.gd) and draws
##  * every character in the look of the cast member it plays (state perm: CharacterLook.defaults_for_seat of that seat; a courier
##    rig takes that seat's tint), back in its own look once its player is revealed and when the view goes (_exit_tree). A rig the
##    game dresses again meanwhile (character/look_sync.gd after a seat move) is taken as that slot's own look and swapped again.
##    A swapped rig plays no idle emote: that is its real player's (character_rig.gd cast_emote) and would give them away;
##  * its own name tags (the game's hide while the view is up): the name of the character each one plays, its own once revealed.
##    Online the own tag stays hidden and the HUD says "YOU ARE <NAME>"; on one machine both tags show;
##  * the character's catchphrase in a speech bubble (client/cast_bubbles.gd look), one of its voice clips and its emote when the
##    slot's line counter goes up;
##  * during a vote: one pad per player where the rules put it (the lobby pad's paint, a name board on two posts at its far edge
##    facing the yard centre), lit while someone stands on it, and an accent ring under the character asked about; at the reveal
##    the right pad lights up and the others fade.
const Rules := preload("res://modes/friend_swap/rules.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Catalog := preload("res://character/catalog.gd")
const Look := preload("res://character/look.gd")
const Ui := preload("res://client/friends_ui.gd")
const WorldLabel := preload("res://client/world_label.gd")
const CastBubbles := preload("res://client/cast_bubbles.gd")
const WalkInLook := preload("res://style/walk_in_look.gd")
const TITLE := "FRIEND SWAP"
const TAG_HEIGHT := 2.3 ## over the feet, like the game's name tags (client/name_tags.gd)
const TAG_SCALE_DISTANCE := 6.0 ## up to here a tag keeps its own size, then it grows up to TAG_GROWTH
const TAG_GROWTH := 2.4
const ASKED_RADIUS := 0.75 ## the accent ring under the character asked about
const BOARD := Vector2(2.2, 0.8) ## a pad's name board, metres
const BOARD_MIDDLE := 1.9 ## its middle over the floor
const BOARD_BACK := 0.2 ## behind the pad's rim
const NOTE_ONLINE := "WASD move  ·  SPACE jump  ·  F grab  ·  Z / X say your line"
const NOTE_LOCAL := "Move, jump and grab as always  ·  say your line: Z / X (first player), H / Y (second player)"
const FALLBACK_LINE := "It's me, %s!" ## a cast member without a catchphrase

var _state: Dictionary = {}
var _perm: Array = [] ## slot -> the slot whose character it plays (state perm)
var _real := {} ## slot -> its rig's own look from before the swap (CharacterLook; a courier rig: its tint)
var _worn := {} ## slot -> what this view dressed it in
var _idle := {} ## slot -> its rig's idle_emotes before the swap (the idle emote is the real player's: it would give them away)
var _cast_looks := {} ## seat -> CharacterLook.defaults_for_seat(seat)
var _lines: Array = [] ## the line counters seen last
var _tags: Array[Label3D] = []
var _tag_asked: Array[bool] = []
var _bubbles: Array = [] ## {node, slot, age}
var _pads := {} ## pad slot -> {root, ring, fill, color}
var _pad_key := ""
var _asked: Node3D
var _asked_ring: StandardMaterial3D
var _asked_fill: StandardMaterial3D
var _voice: AudioStreamPlayer
var _clock := 0.0

func build() -> void:
	hide_name_tags = true
	for slot in seats.size():
		var tag := WorldLabel.make("", 60, 0.0042, Color.WHITE, WorldLabel.DARK, 4)
		tag.name = "SwapTag%d" % (slot + 1)
		tag.visible = false
		add_child(tag)
		_tags.append(tag)
		_tag_asked.append(false)
	_asked = Node3D.new()
	_asked.name = "Asked"
	add_child(_asked)
	var paint := WalkInLook.pad(_asked, Ui.ACCENT, ASKED_RADIUS)
	_asked_ring = paint.ring_material
	_asked_fill = paint.fill_material
	_asked.visible = false

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	_state = state
	var perm: Variant = state.get("perm")
	if perm is Array and (perm as Array).size() == seats.size(): _perm = (perm as Array).map(func(value: Variant) -> int: return int(value))
	if run == null or not is_instance_valid(run) or not is_inside_tree(): return
	if not _perm.is_empty():
		_dress()
		_listen(state.get("lines"))
	_show_tags()
	_show_pads()
	_show_asked()
	_age_bubbles(dt)

func hud(state: Dictionary) -> Dictionary:
	var model := {"title": TITLE, "big": "", "line": "", "timer": -1.0, "scores": [], "out": _ints(state.get("gone")), "note": ""}
	var perm := _ints(state.get("perm"))
	if perm.size() != seats.size() or perm.is_empty():
		model.line = "Everyone gets a friend's character"
		return model
	var local := _local()
	var me := my_slot if my_slot >= 0 and my_slot < perm.size() and not local else -1
	var left := float(state.get("left", 0.0))
	var actor := int(state.get("actor", -1))
	match str(state.get("phase", "")):
		"play":
			model.timer = left
			model.note = NOTE_LOCAL if local else NOTE_ONLINE
			var intro := Rules.PLAY_SECONDS - left < Rules.INTRO_SECONDS
			if local:
				var pairs := PackedStringArray()
				for slot in perm.size(): pairs.append("%s, PLAY AS %s" % [_name(_seat_of(slot)), _name(_seat_of(perm[slot]))])
				model.big = "SWAP!" if intro else ""
				model.line = "  ·  ".join(pairs)
			elif me >= 0:
				var character := _name(_seat_of(perm[me]))
				model.big = "YOU ARE %s" % character if intro else ""
				model.line = "Act like them. Nobody may guess it's you" if intro else "PLAY AS %s" % character
			else: model.line = "Everyone plays someone else"
		"vote":
			model.timer = left
			model.big = "WHO IS PLAYING %s?" % _name(_seat_of(int(state.get("target", -1))))
			if me >= 0 and me == actor: model.line = "That's you! Keep a straight face"
			elif local: model.line = "Everyone but the one playing it: run to a pad"
			else: model.line = "Run to the pad of who you think it is"
			model.note = "Vote %d of %d  ·  stand on a pad when the time runs out" % [int(state.get("vote", 0)), int(state.get("votes", 0))]
		"reveal":
			var right := int(state.get("right", 0))
			var wrong := int(state.get("wrong", 0))
			model.big = "IT WAS %s!" % _name(_seat_of(actor))
			var line := "Nobody guessed it" if right == 0 else ("1 guessed right" if right == 1 else "%d guessed right" % right)
			if wrong > 0: model.line = "%s  ·  %s fooled %d" % [line, _name(_seat_of(actor)), wrong]
			else: model.line = line
			var picks := _ints(state.get("picks"))
			if me >= 0 and me == actor: model.note = "You fooled %d: +%d" % [wrong, wrong] if wrong > 0 else "Nobody fell for it"
			elif me >= 0 and me < picks.size():
				var pick: int = picks[me]
				model.note = "You got it: +1" if pick == actor else ("No pad, no guess" if pick == -1 else "Wrong pad")
	if int(state.get("closed", 0)) > 0: model.scores = _ints(state.get("scores"))
	return model

## What the view shows now, for the checks: tag texts ("" hidden), pad slots, bubble slots, the asked ring, the seat each rig wears.
func probe() -> Dictionary:
	var tags := []
	for tag: Label3D in _tags: tags.append(tag.text if tag.visible else "")
	var bubbles := []
	for bubble: Dictionary in _bubbles: bubbles.append(int(bubble.slot))
	var shows := []
	for slot in seats.size(): shows.append(_shown_seat(slot) if not _perm.is_empty() else int(seats[slot]))
	return {"tags": tags, "pads": _pads.keys(), "bubbles": bubbles, "asked": _asked != null and _asked.visible, "shows": shows}

## The real looks go back on, whatever the round left.
func _exit_tree() -> void:
	if run == null or not is_instance_valid(run): return
	for slot: int in _real:
		var body := rig(slot)
		if body == null or body.is_queued_for_deletion(): continue
		if body.has_method("set_look"): body.set_look(_real[slot])
		else: body.set_slot_tint(int(_real[slot]))
		if _idle.has(slot): body.set("idle_emotes", _idle[slot])

# ------------------------------------------------------------------ the characters

## Every character wears the cast look of the one it plays, or its own once its player was revealed.
func _dress() -> void:
	for slot in seats.size():
		var body := rig(slot)
		if body == null: continue
		var seat := _shown_seat(slot)
		var own := seat == int(seats[slot])
		if body.has_method("set_look"):
			var now: CharacterLook = body.get_look()
			if not _real.has(slot) or (_worn.has(slot) and not now.equals(_worn[slot])): _real[slot] = now # first sight, or dressed again
			var wanted: CharacterLook = _real[slot] if own else _cast_look(seat)
			if not now.equals(wanted): body.set_look(wanted)
			_worn[slot] = wanted
			if not _idle.has(slot): _idle[slot] = bool(body.get("idle_emotes"))
			body.set("idle_emotes", own and bool(_idle[slot]))
		elif "tint_index" in body:
			var tint := int(body.get("tint_index"))
			if not _real.has(slot) or (_worn.has(slot) and tint != int(_worn[slot])): _real[slot] = tint
			var wanted_tint := int(_real[slot]) if own else seat
			if tint != wanted_tint: body.set_slot_tint(wanted_tint)
			_worn[slot] = wanted_tint

func _cast_look(seat: int) -> CharacterLook:
	if not _cast_looks.has(seat): _cast_looks[seat] = Look.defaults_for_seat(seat)
	return _cast_looks[seat]

## A line counter that went up: that character says its catchphrase.
func _listen(value: Variant) -> void:
	if not value is Array: return
	var counts: Array = value
	if _lines.size() == counts.size():
		for slot in mini(counts.size(), seats.size()):
			if int(counts[slot]) > int(_lines[slot]): _say(slot)
	_lines = counts.duplicate()

func _say(slot: int) -> void:
	var seat := _shown_seat(slot)
	var member := TeamCast.player(seat)
	var line := str(member.catchphrase)
	if line == "": line = FALLBACK_LINE % str(member.name).capitalize()
	for bubble: Dictionary in _bubbles:
		if int(bubble.slot) == slot and is_instance_valid(bubble.node): (bubble.node as Node).queue_free() # a new line replaces the last
	_bubbles = _bubbles.filter(func(bubble: Dictionary) -> bool: return int(bubble.slot) != slot)
	var node := CastBubbles._bubble(line)
	node.visible = false
	add_child(node)
	_bubbles.append({"node": node, "slot": slot, "age": 0.0})
	var body := rig(slot)
	if body != null and body.has_method("play_emote"):
		var emote := str(member.emote)
		body.play_emote(emote if Catalog.emotes().has(emote) else "yes")
	var clips := TeamCast.voices(seat)
	if not clips.is_empty(): _play(clips.pick_random())

func _play(stream: AudioStream) -> void:
	if stream == null: return
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		_voice.name = "SwapVoice"
		_voice.bus = &"GW_Voice" # the voice volume of the settings, like the game's catchphrases
		add_child(_voice)
	_voice.stream = stream
	_voice.play()

## The bubbles pop up over their speakers, stay and go, as the game's do.
func _age_bubbles(dt: float) -> void:
	if _bubbles.is_empty(): return
	var camera := get_viewport().get_camera_3d()
	for bubble: Dictionary in _bubbles:
		bubble.age = float(bubble.age) + dt
		var node: Variant = bubble.node
		if not is_instance_valid(node): continue
		var slot := int(bubble.slot)
		if float(bubble.age) >= CastBubbles.SHOWN or _gone(slot):
			(node as Node).queue_free()
			continue
		var shown: Node3D = node
		shown.global_position = feet(slot) + Vector3.UP * CastBubbles.HEIGHT
		shown.visible = true
		var growth := 1.0
		if camera != null: growth = clampf(camera.global_position.distance_to(shown.global_position) / CastBubbles.BASE_SCALE_DISTANCE, 1.0, CastBubbles.MAX_GROWTH)
		var pop := minf(float(bubble.age) / CastBubbles.POP, 1.0)
		pop = 1.0 + 2.2 * pow(pop - 1.0, 3.0) + 1.2 * pow(pop - 1.0, 2.0) # out-back
		var leave := clampf((CastBubbles.SHOWN - float(bubble.age)) / CastBubbles.POP, 0.0, 1.0)
		shown.scale = Vector3.ONE * maxf(growth * pop * leave, 0.01)
	_bubbles = _bubbles.filter(func(bubble: Dictionary) -> bool: return is_instance_valid(bubble.node) and not (bubble.node as Node).is_queued_for_deletion())

## Name tags: the character's name in its colour on the game's dark plate; the one asked about on the accent.
func _show_tags() -> void:
	var camera := get_viewport().get_camera_3d()
	var local := _local()
	var asked := int(_state.get("actor", -1)) if _phase() == "vote" or _phase() == "reveal" else -1
	for slot in _tags.size():
		var tag := _tags[slot]
		if _perm.is_empty() or slot >= run.actors.size() or _gone(slot) or (slot == my_slot and not local):
			tag.visible = false
			continue
		var member := TeamCast.player(_shown_seat(slot))
		var text := str(member.name)
		var is_asked := slot == asked
		if tag.text != text or is_asked != _tag_asked[slot]:
			tag.set_meta(&"plate_color", Ui.ACCENT if is_asked else WorldLabel.DARK)
			WorldLabel.set_text(tag, text)
			_tag_asked[slot] = is_asked
		tag.modulate = Ui.ON_ACCENT if is_asked else (member.color as Color).lerp(Color.WHITE, 0.55)
		var top := feet(slot) + Vector3.UP * TAG_HEIGHT
		tag.global_position = top
		tag.scale = Vector3.ONE * (clampf(camera.global_position.distance_to(top) / TAG_SCALE_DISTANCE, 1.0, TAG_GROWTH) if camera != null else 1.0)
		tag.visible = true

# ------------------------------------------------------------------ the vote

## The pads of the current vote, built when the rules put up a new set.
func _show_pads() -> void:
	var list := _list("pads").filter(func(pad: Variant) -> bool: return pad is Array and (pad as Array).size() >= 3)
	var key := str(list)
	if key != _pad_key:
		_pad_key = key
		for parts: Dictionary in _pads.values(): (parts.root as Node).queue_free()
		_pads.clear()
		var middle := Vector2.ZERO # pads stand evenly round the yard centre: their mean is that centre
		for pad: Array in list: middle += Vector2(float(pad[1]), float(pad[2])) / float(list.size())
		var height := float(_state.get("floor", 0.0))
		for pad: Array in list: _pads[int(pad[0])] = _build_pad(int(pad[0]), Vector3(float(pad[1]), height, float(pad[2])), middle)
	if _pads.is_empty(): return
	var stood := {}
	for value: Variant in _list("on"):
		if int(value) >= 0: stood[int(value)] = true
	var reveal := _phase() == "reveal"
	var answer := int(_state.get("actor", -1))
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 2.0)
	for slot: int in _pads:
		var parts: Dictionary = _pads[slot]
		var base: Color = parts.color
		var ring := base
		var fill := Color(base, 0.28)
		if reveal and slot == answer:
			ring = base.lerp(Ui.WHITE, 0.35 + 0.5 * pulse)
			fill = Color(base, 0.45 + 0.2 * pulse)
		elif reveal:
			ring = base.lerp(Ui.WALL, 0.6)
			fill = Color(base, 0.1)
		elif stood.has(slot):
			ring = base.lerp(Ui.WHITE, 0.45)
			fill = Color(base, 0.45)
		(parts.ring as StandardMaterial3D).albedo_color = ring
		(parts.fill as StandardMaterial3D).albedo_color = fill

## One pad: the lobby pad's paint in the player's colour, and a board with their real name at the far edge, facing the centre.
func _build_pad(slot: int, at: Vector3, middle: Vector2) -> Dictionary:
	var member := TeamCast.player(_seat_of(slot))
	var color: Color = member.color
	var root := Node3D.new()
	root.name = "Pad%d" % (slot + 1)
	add_child(root)
	root.global_position = at
	var inward := Vector2(middle.x - at.x, middle.y - at.z)
	if inward.length() > 0.01: root.rotation.y = atan2(inward.x, inward.y) # +Z to the yard centre
	var paint := WalkInLook.pad(root, color, Rules.PAD_RADIUS)
	var face := WalkInLook.board(root, BOARD, Vector3(0.0, BOARD_MIDDLE, -(Rules.PAD_RADIUS + WalkInLook.RIM + BOARD_BACK)))
	var banner := MeshInstance3D.new()
	banner.name = "Banner"
	var quad := QuadMesh.new()
	quad.size = BOARD - Vector2(0.12, 0.12)
	banner.mesh = quad
	var paper := StandardMaterial3D.new()
	paper.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper.albedo_color = color
	banner.material_override = paper
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	banner.position = Vector3(0.0, 0.0, 0.006)
	face.add_child(banner)
	var label := Label3D.new()
	label.name = "Name"
	label.text = str(member.name)
	label.font = Ui.HEAVY
	label.pixel_size = 0.004
	var size := 120
	while size > 24 and Ui.HEAVY.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * label.pixel_size > BOARD.x - 0.3: size -= 4
	label.font_size = size
	label.modulate = Ui.WHITE if color.get_luminance() < 0.6 else Ui.INK
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.render_priority = 2
	label.position = Vector3(0.0, 0.0, 0.012)
	face.add_child(label)
	return {"root": root, "ring": paint.ring_material, "fill": paint.fill_material, "color": color}

## The accent ring on the floor under the character asked about (vote and reveal).
func _show_asked() -> void:
	var asked := int(_state.get("actor", -1))
	var on: bool = (_phase() == "vote" or _phase() == "reveal") and asked >= 0 and asked < run.actors.size() and not _gone(asked)
	_asked.visible = on
	if not on: return
	var at := feet(asked)
	_asked.global_position = Vector3(at.x, float(_state.get("floor", at.y)), at.z)
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * 1.5)
	_asked_ring.albedo_color = Ui.ACCENT.lerp(Ui.WHITE, 0.4 * pulse)
	_asked_fill.albedo_color = Color(Ui.ACCENT, 0.2 + 0.15 * pulse)

# ------------------------------------------------------------------ helpers

## The cast seat the character at `slot` shows: the one it plays, its own once its player was revealed.
func _shown_seat(slot: int) -> int:
	if slot < 0 or slot >= seats.size(): return slot
	if _perm.is_empty() or _flag(_list("shown"), slot): return int(seats[slot])
	return _seat_of(int(_perm[slot]))

func _seat_of(slot: int) -> int:
	return int(seats[slot]) if slot >= 0 and slot < seats.size() else slot

func _name(seat: int) -> String:
	return str(TeamCast.player(seat).name)

func _phase() -> String:
	return str(_state.get("phase", ""))

func _list(key: String) -> Array:
	var value: Variant = _state.get(key)
	return value if value is Array else []

static func _ints(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for entry: Variant in value: result.append(int(entry))
	return result

static func _flag(list: Array, slot: int) -> bool:
	return slot >= 0 and slot < list.size() and bool(list[slot])

func _gone(slot: int) -> bool:
	return _ints(_state.get("gone")).has(slot)

func _local() -> bool:
	return run != null and is_instance_valid(run) and str(run.get("network_role")) == "local"
