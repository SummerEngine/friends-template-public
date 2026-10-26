extends Node3D
## The show's items and events on a client (docs/items.md): the manager. Added by modes/show/view.gd as a child; it reads only `items` of the show's state (modes/show/items/items.gd state())
## and draws everything: the item boxes (box_look.gd), the local player's item pill (the HUD slot), the projectiles in the air, the effects, the banners and lines, and it hands the
## effects that change how the local courier moves to the shell (game/game_run.gd item_mods, rig_lag, rig_scales, item_power; the camera's `fx`). Each item has its own look
## (`<id>_view.gd`, extends item_look.gd) that builds what its effect and projectile look like; this file knows nothing of any single item. It decides nothing that counts.
const LOOKS := { ## the look script of every item and event
	"smash": preload("res://modes/show/items_ui/smash_view.gd"),
	"call": preload("res://modes/show/items_ui/call_view.gd"),
	"flip": preload("res://modes/show/items_ui/flip_view.gd"),
	"glitch": preload("res://modes/show/items_ui/glitch_view.gd"),
	"dance": preload("res://modes/show/items_ui/dance_view.gd"),
	"boost": preload("res://modes/show/items_ui/boost_view.gd"),
	"soar": preload("res://modes/show/items_ui/soar_view.gd"),
	"eggplant": preload("res://modes/show/items_ui/eggplant_view.gd")}

const Catalog := preload("res://modes/show/items/catalog.gd")
const BoxLook := preload("res://modes/show/items_ui/box_look.gd")
const ItemLook := preload("res://modes/show/items_ui/item_look.gd")
const ItemIcons := preload("res://modes/show/items/item_icons.gd")
const SlotHud := preload("res://modes/show/items_ui/slot_hud.gd")
const ShowRulesItems := preload("res://modes/show/items/items.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Rehearsal := preload("res://modes/show/items_ui/items_rehearsal.gd")

const POP := 0.5 ## s a box's pop (the cube bursts into shards) and its growing back take
const LINE_SHOW := 3.2 ## s a line about another player's item stays
const LINE_KEEP := 3
const BANNER_AT := 0.3 ## the banner's middle, of the screen's height

var run ## the shell
var my_slot := -1
var seats: Array = []
var post_layer: CanvasLayer ## under the HUD and the touch buttons: screen distortions
var over_layer: CanvasLayer ## over the game, under the round's HUD: letterbox bars, windows
var top_layer: CanvasLayer ## the item pill, the banners and lines
var hud: SlotHud
var _looks := {} ## id -> ItemLook
var _boxes: Array = [] ## {node, there, age, spot}
var _level := -2
var _fx := {} ## effect id -> its entry (what the look keeps in it stays)
var _shots := {} ## projectile id -> its entry
var _seq := -1 ## the newest event seq told (-1 until the first state: what happened before this client came is not told)
var _held := -1 ## the local player's item
var _spin := 0.0
var _tick := -1 ## the roulette icon the last tick sounded for
var _clock := 0.0
var _banner := {} ## {kind, words, line, age}
var _lab := false ## the item lab is on (cast show.item_lab): 1-7 hand out items, the HUD says so, the touch ITEM button long-presses through them
var busy := false ## the show's own big banner (the 2-1, GO, a result) is up: item banners wait (set by modes/show/view.gd every frame)
var _queued := {} ## an item banner waiting for the show's banner to clear
var _queued_wait := 0.0
const QUEUE_WAIT := 1.5 ## s an item banner waits for the show's banner before it is dropped
var _lines: Array = [] ## {text, left}
var _mods_slots: Array = [] ## the slots item_mods / rig_lag / item_power / rig_scales hold entries of from this manager
var _boxed_ever := false
var leaving := false ## the manager is leaving the tree: looks add nothing to it any more (a pop of confetti cannot be added while the tree is being torn down)
var rehearsal := false ## the scratch manager of the dress rehearsal (items_rehearsal.gd): its own viewport, its own scratch rig, nothing of it reaches the shell
var scratch_rig: Node3D ## the rehearsal's one rig, every slot's

func setup(show_view, shell, slot: int, round_seats: Array) -> void:
	run = shell
	my_slot = slot
	seats = round_seats
	name = "Items"
	post_layer = _layer(7)
	over_layer = _layer(19)
	top_layer = _layer(24)
	hud = SlotHud.new()
	hud.manager = self
	top_layer.add_child(hud)
	for id: String in Catalog.KINDS:
		if not LOOKS.has(id): continue
		var look: ItemLook = (LOOKS[id] as GDScript).new()
		look.setup(self, id)
		_looks[id] = look

func _layer(order: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = order
	add_child(layer)
	return layer

func _exit_tree() -> void:
	leaving = true
	_clear_all()

# ------------------------------------------------------------------ helpers for the looks

func rig(slot: int) -> Node3D:
	if rehearsal: return scratch_rig
	if run == null or slot < 0 or slot >= run.rigs.size(): return null
	var found: Variant = run.rigs[slot]
	return found if found != null and is_instance_valid(found) else null

func feet(slot: int) -> Vector3:
	if rehearsal: return Rehearsal.FEET
	return run.actors[slot].global_position if run != null and slot >= 0 and slot < run.actors.size() else Vector3.ZERO

func name_of(slot: int) -> String:
	return str(TeamCast.player(int(seats[slot]) if slot >= 0 and slot < seats.size() else slot).name)

func look_of(id: String) -> ItemLook:
	return _looks.get(id)

## A banner with the item's big words (kind: client/show_banner.gd), replacing the one on screen.
func say(kind: String, words: String, line := "") -> void:
	var next := {"kind": kind, "words": words, "line": line, "age": 0.0}
	if busy: # one big banner at a time: while the show's own banner (GO, QUALIFIED ...) is up this waits, for at most QUEUE_WAIT s
		_queued = next
		_queued_wait = 0.0
	else: _banner = next

## A line the others read (a look's own sentence: the eggplant's "passed it to").
func tell(text: String) -> void:
	_lines.append({"text": text, "left": LINE_SHOW})
	while _lines.size() > LINE_KEEP: _lines.pop_front()

## The show's own big banner has come up: an item banner on screen or waiting makes room (the show's words win).
func cut_banner() -> void:
	_banner = {}
	_queued = {}

## The template's own sound `key` of item `id` (audio/items/<id>_<key>.ogg), or the cast's `sfx` for the key "hit"; at a world point (positional) or on the player's own ears (`at` null).
func sfx(id: String, key: String, at: Variant = null, gain_db := 0.0) -> void:
	var stream: AudioStream = Catalog.sfx(id) if key == "hit" else null
	if stream == null:
		var path := "res" + "://audio/items/%s_%s.ogg" % [id, key]
		if ResourceLoader.exists(path): stream = load(path)
	if stream != null: _play(stream, at, gain_db)

## The cast's voice clip of the item, when it has one (the voice slot: docs/items.md); the banner is the item's announcement either way.
func voice(id: String) -> void:
	var clip := Catalog.voice(id)
	if clip != null: _play(clip, null, 0.0)

func _play(stream: AudioStream, at: Variant, gain_db: float) -> void:
	if not is_inside_tree(): return
	if rehearsal: gain_db = Rehearsal.QUIET_DB
	var player: Node
	if at is Vector3:
		var player3 := AudioStreamPlayer3D.new()
		player3.stream = stream
		player3.volume_db = gain_db
		player3.max_distance = 70.0
		player3.unit_size = 8.0
		player = player3
		add_child(player)
		player3.global_position = at
		player3.finished.connect(player.queue_free)
		player3.play()
	else:
		var player2 := AudioStreamPlayer.new()
		player2.stream = stream
		player2.volume_db = gain_db
		player = player2
		add_child(player)
		player2.finished.connect(player.queue_free)
		player2.play()

## The icon of catalog item `kind` (the pill and the touch button).
func draw_icon(ci: CanvasItem, kind: int, c: Vector2, r: float, alpha := 1.0) -> void:
	ItemIcons.draw(ci, kind, c, r, alpha)

# ------------------------------------------------------------------ every frame

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	if not _queued.is_empty():
		_queued_wait += dt
		if not busy:
			_banner = _queued
			_queued = {}
		elif _queued_wait > QUEUE_WAIT: _queued = {}
	var items: Variant = state.get("items")
	if not items is Dictionary:
		if _boxed_ever or not _fx.is_empty() or not _boxes.is_empty(): _clear_all()
		_banner = {}
		_lines.clear()
		hud.model = {}
		hud.queue_redraw()
		return
	_boxed_ever = true
	if not rehearsal: Rehearsal.begin(self) # the first race round of a run: every item's look plays once, hidden, while the round's card is up
	_lab = TeamCast.show_item_lab()
	var level := int(state.get("level", -1))
	if level != _level:
		_clear_all()
		_level = level
		_build_boxes(level)
	_boxes_state(int(items.get("boxes", 0)), dt)
	_held_state(items, dt)
	_effects(items, dt)
	_shots_state(items, dt)
	_events(items)
	_apply_to_shell()
	_banner_line_clock(dt)
	hud.model = {"held": _held, "spin": _spin, "age": _clock, "banner": _banner, "lines": _lines, "pool": _pool_kinds(), "lab": _lab}
	hud.queue_redraw()

func _pool_kinds() -> Array:
	var result: Array = []
	for id: String in Catalog.HELD:
		if _looks.has(id) and not Catalog.off(id): result.append(Catalog.index(id))
	return result

func _banner_line_clock(dt: float) -> void:
	if not _banner.is_empty():
		_banner.age = float(_banner.age) + dt
		if float(_banner.age) > 6.0: _banner = {}
	for line: Dictionary in _lines: line.left = float(line.left) - dt
	_lines = _lines.filter(func(line: Dictionary) -> bool: return float(line.left) > 0.0)

# ------------------------------------------------------------------ boxes

func _build_boxes(level: int) -> void:
	var levels: Variant = run.get("level_world") if run != null else null
	if levels == null or level < 0: return
	for spot: Vector3 in levels.item_boxes(level):
		var node := BoxLook.build()
		add_child(node)
		node.global_position = spot
		_boxes.append({"node": node, "there": true, "age": POP, "spot": spot, "turn": randf() * TAU})

func _boxes_state(mask: int, dt: float) -> void:
	for index in _boxes.size():
		var box: Dictionary = _boxes[index]
		var there := index < 62 and (mask >> index) & 1 == 1
		if there != bool(box.there):
			box.there = there
			box.age = 0.0
			if not there: _burst(box)
		box.age = float(box.age) + dt
		var node: Node3D = box.node
		var cube := BoxLook.cube(node)
		var glow := BoxLook.glow(node)
		var grown := clampf(float(box.age) / POP, 0.0, 1.0)
		var visible_now := bool(box.there)
		cube.visible = visible_now
		glow.visible = visible_now
		if visible_now:
			var s := lerpf(0.1, 1.0, ease(clampf(grown * 1.6, 0.0, 1.0), 0.45)) * (1.0 + 0.12 * sin(grown * PI)) if grown < 1.0 else 1.0 # grows back with a little overshoot
			var bob := 1.0 + 0.025 * sin(_clock * 3.1 + float(box.turn)) # a slow squash and stretch: it stands on its pedestal, it does not float
			cube.scale = Vector3(s * (2.0 - bob), s * bob, s * (2.0 - bob))
			cube.rotation.y = float(box.turn) + _clock * 0.9
			cube.rotation.x = 0.06 * sin(_clock * 1.7 + float(box.turn))
			cube.rotation.z = 0.06 * cos(_clock * 1.3 + float(box.turn))
			glow.scale = Vector3.ONE * (0.92 + 0.08 * sin(_clock * 2.3 + float(box.turn)))
		if box.has("shards"): _step_shards(box, dt)

## The cube bursts into shards (they fly and fall, then are freed) and the pickup sounds.
func _burst(box: Dictionary) -> void:
	var node: Node3D = box.node
	var shards := Node3D.new()
	node.add_child(shards)
	shards.name = "Shards"
	var accent := BoxLook.accent()
	var pieces: Array = []
	for index in 14:
		var piece := MeshInstance3D.new()
		var cube := BoxMesh.new()
		var edge := randf_range(0.1, 0.2)
		cube.size = Vector3(edge, edge, edge)
		piece.mesh = cube
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("3a5cd6") if index % 3 != 0 else (Color("fff3d1") if index % 2 == 0 else accent)
		material.roughness = 0.35
		piece.material_override = material
		shards.add_child(piece)
		piece.position = Vector3(0.0, BoxLook.PEDESTAL + 0.55, 0.0) + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		var away := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.6), randf_range(-1.0, 1.0)).normalized() * randf_range(2.0, 4.5)
		pieces.append({"node": piece, "v": away, "spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))})
	box["shards"] = {"root": shards, "pieces": pieces, "t": 0.0}
	sfx("box", "pop", box.spot, 0.0)

func _step_shards(box: Dictionary, dt: float) -> void:
	var shards: Dictionary = box.shards
	shards.t = float(shards.t) + dt
	for piece: Dictionary in shards.pieces:
		var node: Node3D = piece.node
		piece.v = (piece.v as Vector3) + Vector3(0.0, -14.0, 0.0) * dt
		node.position += (piece.v as Vector3) * dt
		node.rotation += (piece.spin as Vector3) * dt
		node.scale = Vector3.ONE * clampf(1.0 - (float(shards.t) - 0.35) / 0.3, 0.0, 1.0)
	if float(shards.t) > 0.7:
		(shards.root as Node).queue_free()
		box.erase("shards")

# ------------------------------------------------------------------ the local player's item

func _held_state(items: Dictionary, dt: float) -> void:
	var held: Array = items.get("held", [])
	var spin: Array = items.get("spin", [])
	var mine := int(held[my_slot]) if my_slot >= 0 and my_slot < held.size() else -1
	var spinning := float(spin[my_slot]) if my_slot >= 0 and my_slot < spin.size() else 0.0
	if mine != _held:
		_held = mine
	if mine >= 0 and spinning > 0.0: # the roll: one tick per icon flip (slot_hud.gd FLIP), then the bell when it lands
		var flip := int(_clock / SlotHud.FLIP)
		if flip != _tick: sfx("box", "tick")
		_tick = flip
	elif mine >= 0 and _spin > 0.0: sfx("box", "get")
	_spin = spinning
	if run != null and not rehearsal: run.item_slot = {"kind": _held if _spin <= 0.0 else -1, "roll": _spin, "lab": _lab}

# ------------------------------------------------------------------ effects and projectiles

func _effects(items: Dictionary, dt: float) -> void:
	var seen := {}
	for row: Variant in items.get("fx", []):
		var entry := {"id": int(row[0]), "slot": int(row[1]), "kind": int(row[2]), "dur": float(row[3]), "age": float(row[4]), "a": float(row[5]), "b": float(row[6]), "src": int(row[7])}
		seen[entry.id] = entry
		var look: ItemLook = _looks.get(Catalog.id_of(entry.kind))
		if not _fx.has(entry.id):
			entry["mine"] = entry.slot == my_slot
			_fx[entry.id] = entry
			if look != null: look.begin_fx(entry)
		var kept: Dictionary = _fx[entry.id]
		kept.age = float(kept.age) + dt
		if absf(float(kept.age) - entry.age) > 0.6: kept.age = entry.age # a state that knows better (a late joiner, a stall)
		kept.a = entry.a
		kept.b = entry.b
		if look != null: look.update_fx(kept, dt)
	for key: int in _fx.keys():
		if seen.has(key): continue
		var gone: Dictionary = _fx[key]
		var look: ItemLook = _looks.get(Catalog.id_of(int(gone.kind)))
		if look != null: look.end_fx(gone)
		_fx.erase(key)

func _shots_state(items: Dictionary, dt: float) -> void:
	var seen := {}
	for row: Variant in items.get("proj", []):
		var id := int(row[0])
		seen[id] = true
		var p := Vector3(float(row[2]), float(row[3]), float(row[4]))
		var v := Vector3(float(row[5]), float(row[6]), float(row[7]))
		var look: ItemLook = _looks.get(Catalog.id_of(int(row[1])))
		if not _shots.has(id):
			var shot := {"id": id, "kind": int(row[1]), "p": p, "v": v, "tgt": int(row[8]), "age": float(row[9])}
			_shots[id] = shot
			if look != null: look.begin_shot(shot)
		var kept: Dictionary = _shots[id]
		kept.v = v
		kept.tgt = int(row[8])
		kept.age = float(kept.age) + dt
		# between states the shot flies on its velocity; a new state pulls it to where the authority has it
		var ahead: Vector3 = (kept.p as Vector3) + v * dt
		kept.p = ahead.lerp(p, 0.35) if ahead.distance_to(p) < 6.0 else p
		if look != null: look.update_shot(kept, dt)
	for key: int in _shots.keys():
		if seen.has(key): continue
		var gone: Dictionary = _shots[key]
		var look: ItemLook = _looks.get(Catalog.id_of(int(gone.kind)))
		if look != null: look.end_shot(gone)
		_shots.erase(key)

## What is in the state is put on the shell: how each courier moves (the owner's machine acts on its own), how a rig is drawn, how hard a player shoves, the local camera.
func _apply_to_shell() -> void:
	if run == null or rehearsal: return
	var per_slot := {}
	var camera := {}
	for entry: Dictionary in _fx.values():
		var look: ItemLook = _looks.get(Catalog.id_of(int(entry.kind)))
		if look == null: continue
		var slot := int(entry.slot)
		var merged: Dictionary = per_slot.get(slot, {})
		var add: Dictionary = look.mods(entry)
		for key: String in add:
			match key:
				"speed", "jump", "dash": merged[key] = float(merged.get(key, 1.0)) * float(add[key])
				"freeze", "invert": merged[key] = bool(merged.get(key, false)) or bool(add[key])
				"lag", "power", "air_jumps": merged[key] = maxf(float(merged.get(key, 0.0)), float(add[key]))
				"scale": merged[key] = (merged[key] as Vector3).min(add[key] as Vector3) if merged.has(key) else add[key] as Vector3 # (a swell above 1 on x and z must survive: only a second effect on the slot takes the smaller)
		per_slot[slot] = merged
		if slot == my_slot: look.camera(entry, camera)
	var active: Array = per_slot.keys()
	for slot: int in _mods_slots:
		if not per_slot.has(slot):
			run.item_mods.erase(slot)
			run.item_power.erase(slot)
			run.rig_lag.erase(slot)
			if run.rig_scales.get(slot) is Vector3 and (run.rig_scales[slot] as Vector3).x >= 0.01: run.rig_scales.erase(slot)
	for slot: int in active:
		var merged: Dictionary = per_slot[slot]
		var mods := merged.duplicate()
		for key in ["lag", "power", "scale"]: mods.erase(key)
		run.item_mods[slot] = mods
		if merged.has("power"): run.item_power[slot] = float(merged.power)
		else: run.item_power.erase(slot)
		if merged.has("lag"): run.rig_lag[slot] = float(merged.lag)
		else: run.rig_lag.erase(slot)
		if merged.has("scale"): run.rig_scales[slot] = merged.scale
		elif run.rig_scales.get(slot) is Vector3: run.rig_scales.erase(slot)
	_mods_slots = active
	if run.get("follow") != null: run.follow.fx = camera

# ------------------------------------------------------------------ events

func _events(items: Dictionary) -> void:
	var list: Array = items.get("ev", [])
	if _seq < 0:
		_seq = 0 if list.is_empty() else int((list.back() as Array)[0])
		return
	var fresh: Array = list.filter(func(row: Array) -> bool: return int(row[0]) > _seq)
	if fresh.is_empty(): return
	_seq = int((fresh.back() as Array)[0])
	for row: Array in fresh:
		var type := int(row[1])
		var id := Catalog.id_of(int(row[2]))
		var a := int(row[3])
		var b := int(row[4])
		var look: ItemLook = _looks.get(id)
		match type:
			ShowRulesItems.Event.PICK:
				if a != my_slot and a >= 0: sfx("box", "get", feet(a), -8.0)
			ShowRulesItems.Event.USE:
				var victim := name_of(b) if b >= 0 else "" # an item that flies at somebody names them in its USE event
				for other: Array in fresh:
					if int(other[1]) == ShowRulesItems.Event.HIT and int(other[2]) == int(row[2]) and int(other[3]) == a:
						victim = name_of(int(other[4]))
						break
				if look == null or not look.tells_on_hit(): _lines.append({"text": Catalog.line(id, name_of(a), victim if victim != "" else "NOBODY"), "left": LINE_SHOW})
				if look != null and look.announces_itself(): pass
				elif a == my_slot: sfx(id, "use")
				else: sfx(id, "use", feet(a), -4.0)
			ShowRulesItems.Event.HIT:
				if look != null and look.announces_itself(): pass
				elif b == my_slot:
					say(look.banner_kind() if look != null else "item", Catalog.text(id, "banner"))
					voice(id)
					sfx(id, "hit")
				else: sfx(id, "hit", feet(b), -2.0)
				if b != my_slot and (a < 0 or (look != null and look.tells_on_hit())): _lines.append({"text": Catalog.line(id, name_of(a) if a >= 0 else "", name_of(b)), "left": LINE_SHOW}) # an event of the clock (a = -1) and a thrown item that hit are told to the others
		if look != null: look.on_event(type, a, b)
	while _lines.size() > LINE_KEEP: _lines.pop_front()

# ------------------------------------------------------------------ the dress rehearsal (items_rehearsal.gd)

## One box on the rehearsal's stage (it pops and grows back as the made-up state says).
func add_rehearsal_box() -> void:
	var node := BoxLook.build()
	add_child(node)
	_boxes.append({"node": node, "there": true, "age": POP, "spot": Rehearsal.FEET, "turn": 0.0})

## The rehearsal is over: everything the looks still hold is let go.
func finish_rehearsal() -> void:
	_clear_all()

# ------------------------------------------------------------------ clean up

func _clear_all() -> void:
	for entry: Dictionary in _fx.values():
		var look: ItemLook = _looks.get(Catalog.id_of(int(entry.kind)))
		if look != null: look.end_fx(entry)
	_fx.clear()
	for shot: Dictionary in _shots.values():
		var look: ItemLook = _looks.get(Catalog.id_of(int(shot.kind)))
		if look != null: look.end_shot(shot)
	_shots.clear()
	for box: Dictionary in _boxes:
		if is_instance_valid(box.node): (box.node as Node).queue_free()
	_boxes.clear()
	if run != null and is_instance_valid(run) and not rehearsal:
		for slot: int in _mods_slots:
			run.item_mods.erase(slot)
			run.item_power.erase(slot)
			run.rig_lag.erase(slot)
			if run.rig_scales.get(slot) is Vector3 and (run.rig_scales[slot] as Vector3).x >= 0.01: run.rig_scales.erase(slot)
		run.item_slot = {"kind": -1, "roll": 0.0, "lab": false}
		if run.get("follow") != null: run.follow.fx = {}
	_mods_slots.clear()
	_held = -1
	_seq = -1
	_level = -2
