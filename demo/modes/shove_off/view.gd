extends "res://modes/mode_view.gd"
## SHOVE-OFF view (docs/modes/shove_off.md). Builds the raised floor of tiles (modes/shove_off/rules.gd: GRID x GRID tiles of TILE
## metres, the top TOP_ABOVE over the yard floor) as real collision on the yard's floor layer, so every player's own courier stands
## on it, walks off its edges and falls through the tiles that drop. Each tile is a facility block: a two-tone top (white and the
## team's wall colour) on yellow safety-striped sides; the first tiles to fall carry the cast's obstacle labels in Archivo
## lettering on a sign-yellow top (or the obstacle's own colour). A tile about to drop turns red and shakes with the crack of the
## level's vanishing blocks, then falls to the yard floor and is gone; between rounds the tiles come back. A player who falls off
## gets the cast's fall word, the round's winner dances (or plays the cast's own emote). The view only follows the rules' state.
const Rules := preload("res://modes/shove_off/rules.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Surfaces := preload("res://style/surfaces.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const LobbySpace := preload("res://lobby_space.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const SIGN_FONT := preload("res://assets/fonts/Archivo.ttf")

const NOTE := "Walk into players to shove them. F grabs and throws  ·  WASD move · Space jumps"
const PLAIN := Color("f2f2f2")
const TEAL := Color("2fb7a5") ## the second top colour when the cast has no wall colour
const SIGN := Color("f2c230") ## the top of a labelled tile without a colour of its own
const WARN := Color("e8584f") ## a shaking tile's top
const INK := Color("1d2026")
const GAP := 0.06 ## m between two tiles' looks (the collision has none)
const EDGE := 0.05 ## m of edge rounding
const FALL_GRAVITY := 17.0
const RISE := 0.5 ## s a tile that rests on the yard floor takes to rise back to its place (nothing shrinks or vanishes: a dropped tile lies there until it comes back)
const SOUND_ID := 7300 ## the tiles' ids for game/game_audio.gd blink_warn / blink_gone: SOUND_ID + index
const LABEL_WIDTH := 1.05 ## m of lettering across a tile
const LABEL_SIZE := 96

## Per tile: {body, look, label, color, state (the rules' UP / SHAKING / GONE as shown), shake (s), speed (m/s of its fall),
## sink (s on the floor), rise (s back)}.
var _tiles: Array[Dictionary] = []
var _meshes := {} ## colour -> the tile mesh in it
var _materials := {}
var _labels: Array = [] ## [text, top colour] of the cast's obstacles that have a label, in order
var _marked: Array = []
var _seen_out: Array = []
var _phase := ""
var _round := -1
var _winner := -1
var _count_shown := -1
var _clock := 0.0
var _first := true
var _font: FontVariation

func build() -> void:
	_materials = {"block": Surfaces.material("block"), "mover": Surfaces.material("mover")}
	for index in range(1, TeamCast.OBSTACLES + 1):
		var board := TeamCast.obstacle(index)
		if board.is_empty(): continue
		var color: Color = board.get("color", Color(0, 0, 0, 0))
		_labels.append([str(board.label), color if color.a > 0.0 else SIGN])
	var hue := TeamCast.wall_hue()
	var second := Color.from_hsv(hue, 0.5, 0.85) if hue >= 0.0 else TEAL
	for index in Rules.GRID * Rules.GRID:
		var body := StaticBody3D.new()
		body.name = "Tile%02d" % index
		body.collision_layer = LobbySpace.LAYER
		body.collision_mask = 0
		add_child(body)
		_place(body, Rules.tile_center(index) - Vector3(0.0, Rules.THICK * 0.5, 0.0))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(Rules.TILE, Rules.THICK, Rules.TILE)
		shape.shape = box
		body.add_child(shape)
		var color := PLAIN if (index % Rules.GRID + floori(index / float(Rules.GRID))) % 2 == 0 else second
		var look := MeshInstance3D.new()
		look.name = "Look"
		look.mesh = _mesh(color)
		body.add_child(look)
		_tiles.append({"body": body, "look": look, "label": null, "color": color, "plain": color, "state": Rules.UP, "shake": 0.0, "speed": 0.0,
			"sink": -1.0, "rise": -1.0})

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	var round_number := int(state.get("round", 0))
	if round_number != _round:
		_round = round_number
		_seen_out = []
		_winner = -1
		_count_shown = -1
	var marked := _ints(state, "marked")
	if marked != _marked: _mark(marked)
	var shown := _ints(state, "tiles")
	for index in _tiles.size():
		_show_tile(index, int(shown[index]) if index < shown.size() else Rules.UP)
		_animate(index, dt)
	_cues(state)
	_first = false

func hud(state: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", ""))
	var round_number := int(state.get("round", 0))
	var t := float(state.get("t", 0.0))
	var wins := _ints(state, "wins")
	var out := _ints(state, "out")
	for slot: int in _ints(state, "gone"):
		if not out.has(slot): out.append(slot)
	var model := {"title": "SHOVE-OFF  ·  ROUND %d" % round_number if round_number > 0 else "SHOVE-OFF", "big": "", "line": "", "timer": -1.0,
		"scores": wins, "out": out, "note": NOTE}
	match phase:
		"count":
			model.big = str(clampi(ceili(Rules.COUNT - t), 1, 3))
			model.line = "Last one standing wins the round  ·  first to %d round wins" % Rules.WINS_NEEDED
		"play":
			if t < Rules.SHOVE_SHOW: model.big = "SHOVE!"
			elif not _local() and out.has(my_slot): model.line = "You fell. Watch the rest of the round"
		"card":
			var winner := int(state.get("winner", -1))
			model.big = "%s WINS THE ROUND" % _name(winner) if winner >= 0 else "NOBODY WINS THE ROUND"
			var decided := round_number >= Rules.MAX_ROUNDS or (winner >= 0 and winner < wins.size() and int(wins[winner]) >= Rules.WINS_NEEDED)
			if decided: model.line = "That's the game"
			elif winner < 0: model.line = "They fell together  ·  next round in %d" % ceili(maxf(Rules.CARD - t, 0.0))
			else: model.line = "Next round in %d" % ceili(maxf(Rules.CARD - t, 0.0))
		"over":
			var champion := int(state.get("champion", -1))
			model.big = "%s WINS" % _name(champion) if champion >= 0 else "GAME OVER"
	return model

func _exit_tree() -> void:
	var audio = _audio()
	if audio == null: return
	for index in _tiles.size():
		if int(_tiles[index].state) == Rules.SHAKING: audio.stop_hazard(SOUND_ID + index)

# ------------------------------------------------------------------ tiles

## A tile follows the rules' state: SHAKING turns it red and shakes it, GONE drops it (its collision goes at once), UP after GONE
## brings it back. The first state a client sees is shown as it is, without the falls that led to it.
func _show_tile(index: int, want: int) -> void:
	var tile := _tiles[index]
	var was := int(tile.state)
	if want == was: return
	tile.state = want
	var body: StaticBody3D = tile.body
	var look: MeshInstance3D = tile.look
	var audio = _audio()
	var at := Rules.tile_center(index)
	if want == Rules.SHAKING:
		look.mesh = _mesh(WARN)
		tile.shake = 0.0
		if audio != null and not _first: audio.blink_warn(SOUND_ID + index, at)
	elif want == Rules.GONE:
		body.collision_layer = 0
		tile.speed = 0.0
		tile.sink = -1.0
		if _first: look.position.y = -(Rules.TOP_ABOVE - Rules.THICK) # a tile that was already gone lies on the yard floor from the start
		elif audio != null: audio.blink_gone(SOUND_ID + index, at)
	else:
		body.collision_layer = LobbySpace.LAYER
		look.mesh = _mesh(tile.color)
		look.visible = true
		look.position = Vector3.ZERO
		look.rotation = Vector3.ZERO
		look.scale = Vector3.ONE
		tile.rise = 0.0 if was == Rules.GONE and not _first else -1.0
		if was == Rules.SHAKING and audio != null: audio.stop_hazard(SOUND_ID + index)

func _animate(index: int, dt: float) -> void:
	var tile := _tiles[index]
	var look: MeshInstance3D = tile.look
	var state := int(tile.state)
	if state == Rules.SHAKING:
		tile.shake = float(tile.shake) + dt
		var strength := clampf(float(tile.shake) / Rules.SHAKE, 0.25, 1.0)
		var wave := _clock * 40.0 + index * 1.7
		look.position = Vector3(sin(wave) * 0.035, sin(wave * 1.3) * 0.015, cos(wave * 0.9) * 0.035) * strength
		look.rotation = Vector3(sin(wave * 0.7) * 0.03, 0.0, cos(wave * 1.1) * 0.03) * strength
	elif state == Rules.GONE:
		if float(tile.sink) < 0.0 and look.position.y > -(Rules.TOP_ABOVE - Rules.THICK): # falling to the yard floor, where it lies
			tile.speed = float(tile.speed) + FALL_GRAVITY * dt
			look.position.y -= float(tile.speed) * dt
			look.rotation = look.rotation.lerp(Vector3.ZERO, minf(dt * 6.0, 1.0))
			if look.position.y <= -(Rules.TOP_ABOVE - Rules.THICK):
				look.position.y = -(Rules.TOP_ABOVE - Rules.THICK)
				tile.sink = 0.0
	elif float(tile.rise) >= 0.0: # coming back up from the floor
		tile.rise = float(tile.rise) + dt
		var grown := clampf(float(tile.rise) / RISE, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - grown, 3.0)
		look.position.y = -(Rules.TOP_ABOVE - Rules.THICK) * (1.0 - eased)
		if grown >= 1.0:
			tile.rise = -1.0
			look.position = Vector3.ZERO

## The cast's obstacle labels on the tiles that drop first (the rules' `marked`, in order); the others keep their checker top.
func _mark(marked: Array) -> void:
	for index: int in _marked:
		if index < 0 or index >= _tiles.size(): continue
		var tile := _tiles[index]
		if tile.label != null:
			(tile.look as Node).remove_child(tile.label)
			(tile.label as Node).queue_free()
		tile.label = null
		tile.color = tile.plain
		if int(tile.state) == Rules.UP: (tile.look as MeshInstance3D).mesh = _mesh(tile.color)
	_marked = marked
	for k in mini(marked.size(), _labels.size()):
		var index: int = marked[k]
		if index < 0 or index >= _tiles.size(): continue
		var tile := _tiles[index]
		var top: Color = _labels[k][1]
		tile.color = top
		if int(tile.state) == Rules.UP: (tile.look as MeshInstance3D).mesh = _mesh(top)
		tile.label = _lettering(str(_labels[k][0]), INK if top.get_luminance() > 0.5 else Color.WHITE)
		(tile.look as Node).add_child(tile.label)

## Flat Archivo lettering on a tile's top, sized to fit across it (a long label breaks at the space nearest its middle).
func _lettering(text: String, ink: Color) -> Label3D:
	var shown := text
	var space := -1
	var middle := text.length() * 0.5
	if text.length() > 10:
		for k in text.length():
			if text[k] == " " and (space < 0 or absf(k - middle) < absf(space - middle)): space = k
	if space > 0: shown = text.substr(0, space) + "\n" + text.substr(space + 1)
	var label := Label3D.new()
	label.name = "Lettering"
	label.text = shown
	label.font = _sign_font()
	label.font_size = LABEL_SIZE
	var size := _sign_font().get_multiline_string_size(shown, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_SIZE)
	label.pixel_size = minf(0.004, LABEL_WIDTH / maxf(maxf(size.x, size.y), 1.0))
	label.modulate = ink
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = Vector3(0.0, Rules.THICK * 0.5 + 0.012, 0.0)
	return label

## The sign face of the levels: Archivo, extra bold.
func _sign_font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = SIGN_FONT
		_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _font

## One tile's block: `top` on the walkable face, the facility's safety-striped mover material on the sides.
func _mesh(top: Color) -> ArrayMesh:
	var key := top.to_html(false)
	if not _meshes.has(key):
		var batch := BlockMesh.Batch.new()
		batch.box(Transform3D.IDENTITY, Vector3(Rules.TILE - GAP, Rules.THICK, Rules.TILE - GAP), EDGE, 2, "block", "mover", top)
		_meshes[key] = batch.commit(_materials)
	return _meshes[key]

# ------------------------------------------------------------------ moments

## Sounds, words and emotes of the moments the state passes: 3, 2, 1, SHOVE!, a fall, a round won.
func _cues(state: Dictionary) -> void:
	var phase := str(state.get("phase", ""))
	var t := float(state.get("t", 0.0))
	var audio = _audio()
	if phase == "count":
		var number := clampi(ceili(Rules.COUNT - t), 1, 3)
		if number != _count_shown and not _first and audio != null: audio.play_event("countdown")
		_count_shown = number
	elif phase == "play" and _phase == "count" and audio != null: audio.play_event("go")
	for slot: int in _ints(state, "out"):
		if _seen_out.has(slot): continue
		_seen_out.append(slot)
		if _first or slot < 0 or slot >= seats.size(): continue
		var at := feet(slot)
		HazardLooks.word(self, TeamCast.word("fall"), at + Vector3.UP * 2.1)
		if audio != null: audio.play_event("fall", at)
	var winner := int(state.get("winner", -1)) if phase == "card" else -1
	if winner != _winner:
		_winner = winner
		if winner >= 0 and not _first:
			var body := rig(winner)
			if body != null and body.has_method("play_emote"):
				var emote := str(body.call("cast_emote")) if body.has_method("cast_emote") else ""
				body.call("play_emote", emote if emote != "" else "dance")
			if audio != null: audio.play_event("goal")
	_phase = phase

# ------------------------------------------------------------------ helpers

func _place(node: Node3D, at: Vector3) -> void:
	if node.is_inside_tree(): node.global_position = at
	else: node.position = at

func _audio():
	return run.get("audio") if run != null else null

func _local() -> bool:
	return run != null and str(run.get("network_role")) == "local"

func _name(slot: int) -> String:
	return str(cast_player(slot).name)

## A list of ints from the state ([] when it is missing or not a list).
static func _ints(state: Dictionary, key: String) -> Array:
	var value: Variant = state.get(key, [])
	var result: Array = []
	if value is Array:
		for entry: Variant in value: result.append(int(entry))
	return result
