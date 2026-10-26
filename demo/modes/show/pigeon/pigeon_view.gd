extends Node3D
## GHOST PIGEON on a client (docs/pigeon.md): the manager. Added by modes/show/view.gd as a child; it reads only `pigeon` of the show's state (modes/show/shared/pigeon/pigeon_rules.gd state()) and draws
## everything: the birds (pigeon_mesh.gd, flapping, a collar in the owner's colour, a name over the others'), the coo (a loud sound in the world, "COO!" over the bird, two rings of sound, a small screen
## shake for the living players the authority says are within range), the falling drops, the splats on the floor, on the head of a player who was hit and, for the player who was hit, on its own screen
## (splat_overlay.gd). For the player whose bird it is, it follows the bird with the shoulder camera (game_run.gd `pigeon_focus`), predicts the bird from the player's own input so the controls feel
## immediate (the same pigeon_sim.gd step as the authority; the authority's position wins when they drift apart) and draws the COO / DROP buttons (pigeon_hud.gd). It decides nothing that counts.
const Catalog := preload("res://modes/show/shared/pigeon/pigeon_catalog.gd")
const Sim := preload("res://modes/show/shared/pigeon/pigeon_sim.gd")
const PigeonMesh := preload("res://modes/show/pigeon/pigeon_mesh.gd")
const PigeonAudio := preload("res://modes/show/pigeon/pigeon_audio.gd")
const SplatOverlay := preload("res://modes/show/pigeon/splat_overlay.gd")
const PigeonHud := preload("res://modes/show/pigeon/pigeon_hud.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const TouchControls := preload("res://client/touch_controls.gd")

const NOTE_KEYS := "WASD fly  ·  Space up  ·  Shift down  ·  F coo  ·  E drop"
const NOTE_PAD := "stick fly  ·  A up  ·  B down  ·  X coo  ·  LB drop"
const SMOOTH := 14.0 ## 1/s: another player's bird is drawn this closely behind the newest state
const MAX_AGE := 0.25 ## s the newest state's velocity is carried on
const SNAP := 4.0 ## m: the own bird further than this from the authority's is put there
const DRIFT := 3.0 ## m the own bird may run ahead of the authority's (the wire's lag) before it is pulled back
const RING_LIFE := 0.55 ## s a coo's ring of sound takes to spread
const BUBBLE_LIFE := 1.0 ## s the "COO!" stays over a bird
const DECAL_LIFE := 5.0 ## s a splat stays on the floor (it fades over the last second)
const SHAKE_AMP := 0.2 ## m of the camera's frustum offset at the start of a coo's ping
const SHAKE_DECAY := 2.6 ## 1/s

var show_view ## modes/show/view.gd
var run ## the shell
var my_slot := -1
var seats: Array = []
var coos_heard := 0 ## coos this client played (checks)
var splats_heard := 0 ## landings this client played (checks)
var shakes := 0 ## screen shakes this client took (checks)

var _birds: Dictionary = {} ## slot -> {node, label, pos, vel, yaw, row_pos, age, coo_n, drop_n, phase, bank, mpos, mvel, mready, fresh}
var _blobs: Dictionary = {} ## id -> {node, pos, vel, age, row_pos}
var _fx: Array = [] ## rings, bubbles and floor splats: {node, kind, age, life, ...}
var _worn: Dictionary = {} ## victim slot -> the white blob on its head {node, left}
var _clock := 0.0
var _box: Dictionary = {}
var _box_level := -2
var _seen_seq := -2 ## the newest landing told (-2 until the first state: what happened before this client came is not told)
var _mine_on := false
var _shake := 0.0
var _shaking := false
var _splat_up := false
var _splat_age := 0.0
var _splat_total := 1.5
var _splat_count := 0
var _splat_victims: Dictionary = {} ## victim slot -> true while its splat is in the state (the line about it is told once)
var _floor := NAN
var _frame := 0
var _warm_left := 2
var _splat_layer: CanvasLayer
var _splat: SplatOverlay
var _hud_layer: CanvasLayer
var _hud: PigeonHud

func setup(view, shell, slot: int, round_seats: Array) -> void:
	show_view = view
	run = shell
	my_slot = slot
	seats = round_seats
	name = "Pigeons"
	_splat_layer = CanvasLayer.new()
	_splat_layer.layer = 8 # over the game, under the round's HUD and the items' layers
	add_child(_splat_layer)
	_splat = SplatOverlay.new()
	_splat_layer.add_child(_splat)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 23
	add_child(_hud_layer)
	_hud = PigeonHud.new()
	_hud_layer.add_child(_hud)
	_splat.show_model({})
	_hud.show_model({})

func _exit_tree() -> void:
	_release_camera()

## The splat layer and the buttons' layer drawn or not. A client has one view; the test harnesses (tools/modes/items_harness.gd, items_film.gd) draw several replicas into one window and show one at a time.
func show_layers(on: bool) -> void:
	_splat_layer.visible = on
	_hud_layer.visible = on

# ------------------------------------------------------------------ the frame

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	_frame += 1
	_tick_fx(dt)
	_warm()
	var data: Variant = state.get("pigeon")
	if not data is Dictionary or (data as Dictionary).is_empty():
		_reset()
		return
	var level := int(state.get("level", -1))
	if level != _box_level:
		_box_level = level
		_clear_nodes() # a new round: the birds are put over its start, not flown there
		_box = Sim.bounds(run.level_world, level) if run != null and run.get("level_world") != null and level >= 0 else {}
	var rows := {}
	for row: Variant in (data as Dictionary).get("b", []):
		if row is Array and (row as Array).size() >= 14: rows[int((row as Array)[0])] = row
	_sync_birds(rows)
	for slot: int in _birds.keys(): _update_bird(slot, rows[slot], dt)
	_blobs_update((data as Dictionary).get("d", []), dt)
	_landings((data as Dictionary).get("l", []))
	_splats((data as Dictionary).get("s", []), dt)
	_mine(rows)
	_shake_camera(dt)

## True while the local player is a bird (modes/show/view.gd: no spectating, the note and the buttons are the bird's).
func mine() -> bool:
	return _mine_on

## The bottom note while the local player is a bird.
func note() -> String:
	if not _mine_on or (show_view != null and show_view.has_method("touching") and bool(show_view.call("touching"))): return ""
	return NOTE_PAD if TouchControls.last_device == "pad" else NOTE_KEYS

func birds_shown() -> Array:
	return _birds.keys()

func bird_position(slot: int) -> Vector3:
	return (_birds[slot] as Dictionary).pos if _birds.has(slot) else Vector3.ZERO

func splat_up() -> bool:
	return _splat_up

# ------------------------------------------------------------------ birds

func _sync_birds(rows: Dictionary) -> void:
	for slot: int in _birds.keys():
		if not rows.has(slot): _drop_bird(slot)
	for slot: int in rows:
		if _birds.has(slot): continue
		var row: Array = rows[slot]
		var made := _make_bird(slot, row)
		_birds[slot] = made
		if slot != my_slot and show_view != null and _seen_seq != -2:
			var events: Variant = show_view.get("_events")
			if events is Array: (events as Array).append({"text": Catalog.line("line", _name_of(slot)), "left": 2.0})

func _name_of(slot: int) -> String:
	return str(show_view.call("cast_player", slot).get("name", "")) if show_view != null else ""

func _make_bird(slot: int, row: Array) -> Dictionary:
	var colour: Color = show_view.call("cast_player", slot).get("color", Color.WHITE) if show_view != null else Color.WHITE
	var node: Node3D = PigeonMesh.build(colour)
	node.name = "Pigeon%d" % slot
	var at := Vector3(float(row[1]), float(row[2]), float(row[3]))
	node.position = at
	add_child(node)
	var label := Label3D.new()
	label.text = _name_of(slot)
	label.font = ShowTheme.font()
	label.font_size = 56
	label.pixel_size = 0.0065
	label.outline_size = 14
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0.05, 0.06, 0.1, 0.95)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at + Vector3(0.0, 0.95, 0.0)
	label.visible = slot != my_slot
	add_child(label)
	return {"node": node, "label": label, "pos": at, "vel": Vector3.ZERO, "yaw": float(row[4]), "row_pos": at, "age": 0.0, "coo_n": int(row[8]), "drop_n": int(row[9]), "phase": float(slot) * 1.7, "bank": 0.0,
		"mpos": at, "mvel": Vector3.ZERO, "mready": false}

func _drop_bird(slot: int) -> void:
	var bird: Dictionary = _birds[slot]
	(bird.node as Node).queue_free()
	(bird.label as Node).queue_free()
	_birds.erase(slot)

func _update_bird(slot: int, row: Array, dt: float) -> void:
	var bird: Dictionary = _birds[slot]
	var auth := Vector3(float(row[1]), float(row[2]), float(row[3]))
	var vel := Vector3(float(row[5]), float(row[6]), float(row[7]))
	if (bird.row_pos as Vector3) != auth:
		bird.row_pos = auth
		bird.age = 0.0
	bird.age = minf(float(bird.age) + dt, MAX_AGE)
	var target: Vector3 = auth + vel * float(bird.age)
	if slot == my_slot and str(run.get("network_role")) == "replica": _predict(bird, row, target, vel, dt)
	else:
		bird.pos = (bird.pos as Vector3).lerp(target, 1.0 - exp(-SMOOTH * dt))
		bird.vel = (bird.vel as Vector3).lerp(vel, 1.0 - exp(-SMOOTH * dt))
	# the look: face the way it flies, lean into a turn, tip with the climb, flap harder when climbing
	var node: Node3D = bird.node
	var shown_vel: Vector3 = bird.vel
	var yaw := Sim.facing(shown_vel, float(bird.yaw))
	var turn := wrapf(yaw - float(bird.yaw), -PI, PI) / maxf(dt, 0.001)
	bird.yaw = yaw
	node.position = bird.pos
	node.rotation.y = lerp_angle(node.rotation.y, yaw, 1.0 - exp(-10.0 * dt))
	bird.bank = lerpf(float(bird.bank), clampf(turn * 0.12, -0.55, 0.55), 1.0 - exp(-6.0 * dt))
	var speed := Vector2(shown_vel.x, shown_vel.z).length()
	var rising := clampf(shown_vel.y / 4.0, -1.0, 1.0)
	var amp := clampf(0.5 + 0.2 * rising + speed * 0.03, 0.35, 0.95)
	bird.phase = float(bird.phase) + dt * (11.0 + 3.0 * maxf(rising, 0.0) + speed * 0.4)
	PigeonMesh.pose(node, float(bird.phase), amp, float(bird.bank), clampf(-rising * 0.35 + speed * 0.015, -0.5, 0.5))
	(bird.label as Label3D).position = (bird.pos as Vector3) + Vector3(0.0, 0.95, 0.0)
	if int(row[8]) != int(bird.coo_n):
		bird.coo_n = int(row[8])
		_coo(slot, bird, int(row[13]))
	bird.drop_n = int(row[9])

## The own bird: stepped from the player's own input with the authority's rules, so the controls answer at once; the authority's bird is the truth: far away it is taken, while the player is
## still it is eased to, while it flies it may run ahead by the wire's lag.
func _predict(bird: Dictionary, row: Array, target: Vector3, vel: Vector3, dt: float) -> void:
	if int(row[12]) == 1 or not bool(bird.mready) or _box.is_empty(): # nobody is flying it (it wanders), or the first state
		bird.mpos = target
		bird.mvel = vel
		bird.mready = not _box.is_empty()
	else:
		var input: Dictionary = run.owner_command if run.get("owner_command") is Dictionary else {}
		var wire: Variant = input.get("move", Vector2.ZERO)
		var move := Vector2.ZERO
		if wire is Vector2: move = wire
		elif wire is Array and (wire as Array).size() == 2: move = Vector2(float(wire[0]), float(wire[1]))
		var climb := clampf(float(input.get("height", 0.0)), -1.0, 1.0)
		if _frame % 3 == 0 and not bool(_box.stage): _floor = run.level_world.floor_y(_box_level, bird.mpos)
		var step := Sim.step(bird.mpos, bird.mvel, move.limit_length(1.0), climb, dt, _box, _floor if not bool(_box.stage) else NAN, Catalog.tune("speed"), Catalog.tune("climb"))
		bird.mpos = step.pos
		bird.mvel = step.vel
		var gap: Vector3 = target - (bird.mpos as Vector3)
		var steering := move.length() > 0.1 or absf(climb) > 0.1
		if gap.length() > SNAP: bird.mpos = target
		elif not steering: bird.mpos = (bird.mpos as Vector3) + gap * (1.0 - exp(-3.0 * dt))
		elif gap.length() > DRIFT: bird.mpos = (bird.mpos as Vector3) + gap * (1.0 - exp(-0.4 * dt))
	bird.pos = bird.mpos
	bird.vel = bird.mvel

# ------------------------------------------------------------------ the coo

func _coo(slot: int, bird: Dictionary, hits: int) -> void:
	coos_heard += 1
	var at: Vector3 = bird.pos
	_sound(PigeonAudio.coo(), at, 6.0, 1.0 + 0.04 * float(slot % 3))
	var words := Label3D.new()
	words.text = Catalog.text("coo").to_upper()
	words.font = ShowTheme.font()
	words.font_size = 72
	words.pixel_size = 0.009
	words.outline_size = 18
	words.modulate = Color(1.0, 1.0, 0.92)
	words.outline_modulate = Color(0.1, 0.12, 0.2, 0.95)
	words.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	words.no_depth_test = true
	words.position = at + Vector3(0.0, 1.2, 0.0)
	add_child(words)
	_fx.append({"node": words, "kind": "bubble", "age": 0.0, "life": BUBBLE_LIFE, "from": words.position, "slot": slot})
	for index in 2:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.46
		torus.outer_radius = 0.5
		torus.rings = 28
		torus.ring_segments = 4
		ring.mesh = torus
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
		ring.material_override = material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = at
		add_child(ring)
		_fx.append({"node": ring, "kind": "ring", "age": -0.12 * float(index), "life": RING_LIFE, "slot": slot, "reach": Catalog.tune("coo_range")})
	if my_slot >= 0 and ((hits >> my_slot) & 1) == 1 and not _birds.has(my_slot):
		_shake = 1.0 # the ping: a living player within range feels it
		shakes += 1

func _shake_camera(dt: float) -> void:
	var camera: Variant = run.get("camera") if run != null else null
	if not camera is Camera3D: return
	if _shake > 0.0:
		_shaking = true
		_shake = maxf(_shake - SHAKE_DECAY * dt, 0.0)
		var amount := _shake * _shake * SHAKE_AMP
		(camera as Camera3D).h_offset = sin(_clock * 63.0) * amount
		(camera as Camera3D).v_offset = cos(_clock * 51.0) * amount * 0.8
	elif _shaking:
		_shaking = false
		(camera as Camera3D).h_offset = 0.0
		(camera as Camera3D).v_offset = 0.0

func _release_camera() -> void:
	var camera: Variant = run.get("camera") if run != null and is_instance_valid(run) else null
	if camera is Camera3D and _shaking:
		(camera as Camera3D).h_offset = 0.0
		(camera as Camera3D).v_offset = 0.0
	_shaking = false
	if run != null and is_instance_valid(run): run.set("pigeon_focus", null)

# ------------------------------------------------------------------ drops, landings, splats

func _blobs_update(rows: Array, dt: float) -> void:
	var seen := {}
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 8: continue
		var id := int((row as Array)[0])
		seen[id] = true
		var at := Vector3(float(row[1]), float(row[2]), float(row[3]))
		var vel := Vector3(float(row[4]), float(row[5]), float(row[6]))
		if not _blobs.has(id):
			var node := MeshInstance3D.new()
			var drop := SphereMesh.new()
			drop.radius = 0.5
			drop.height = 1.0
			drop.radial_segments = 10
			drop.rings = 6
			node.mesh = drop
			node.scale = Vector3(0.24, 0.34, 0.24)
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.98, 0.98, 0.95)
			material.emission_enabled = true
			material.emission = Color(0.9, 0.92, 1.0)
			material.emission_energy_multiplier = 0.5
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = at
			add_child(node)
			_blobs[id] = {"node": node, "pos": at, "vel": vel, "age": 0.0, "row_pos": at}
		var blob: Dictionary = _blobs[id]
		if (blob.row_pos as Vector3) != at:
			blob.row_pos = at
			blob.age = 0.0
		blob.age = minf(float(blob.age) + dt, MAX_AGE)
		blob.pos = (blob.pos as Vector3).lerp(at + vel * float(blob.age), 1.0 - exp(-SMOOTH * dt))
		(blob.node as Node3D).position = blob.pos
	for id: int in _blobs.keys():
		if seen.has(id): continue
		((_blobs[id] as Dictionary).node as Node).queue_free()
		_blobs.erase(id)

func _landings(rows: Array) -> void:
	var newest := _seen_seq
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 5: continue
		var seq := int((row as Array)[0])
		newest = maxi(newest, seq)
		if _seen_seq == -2 or seq <= _seen_seq: continue
		var at := Vector3(float(row[1]), float(row[2]), float(row[3]))
		splats_heard += 1
		_sound(PigeonAudio.splat(), at, 4.0, 1.0)
		if int(row[4]) < 0: _floor_splat(at)
		else: _head_splat(int(row[4]))
	_seen_seq = maxi(newest, -1) if _seen_seq == -2 else newest

func _floor_splat(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = at + Vector3(0.0, 0.03, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 100.0) * 31 + int(at.z * 100.0)
	for index in 5:
		var disc := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 0.02
		cylinder.radial_segments = 14
		disc.mesh = cylinder
		var size := 0.7 if index == 0 else rng.randf_range(0.14, 0.3)
		var offset := Vector3.ZERO if index == 0 else Vector3(rng.randf_range(-0.55, 0.55), 0.0, rng.randf_range(-0.55, 0.55))
		disc.scale = Vector3(size, 1.0, size * rng.randf_range(0.8, 1.2))
		disc.position = offset + Vector3(0.0, 0.002 * float(index), 0.0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.97, 0.98, 0.96, 1.0)
		disc.material_override = material
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(disc)
	add_child(holder)
	_fx.append({"node": holder, "kind": "decal", "age": 0.0, "life": DECAL_LIFE})

## The white blob on the head of a player who was hit (the others see it; the player itself sees the overlay).
func _head_splat(victim: int) -> void:
	var body: Variant = show_view.call("rig", victim) if show_view != null else null
	if body == null or not (body as Node).has_method("head_anchor"): return
	var head: Variant = (body as Node).call("head_anchor")
	if not head is Node3D: return
	if _worn.has(victim): ((_worn[victim] as Dictionary).node as Node).queue_free()
	var blob := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6
	blob.mesh = mesh
	blob.scale = Vector3(0.5, 0.26, 0.46)
	blob.position = Vector3(0.0, 0.08, 0.02)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.98, 0.98, 0.95)
	blob.material_override = material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(head as Node3D).add_child(blob)
	_worn[victim] = {"node": blob, "left": Catalog.tune("splat_time")}

func _splats(rows: Array, dt: float) -> void:
	var mine_left := -1.0
	var mine_from := -1
	var present := {}
	for row: Variant in rows:
		if not row is Array or (row as Array).size() < 3: continue
		var victim := int((row as Array)[0])
		present[victim] = true
		if victim == my_slot:
			mine_left = float(row[1])
			mine_from = int(row[2])
		elif not _splat_victims.has(victim) and _seen_seq != -2 and show_view != null:
			var events: Variant = show_view.get("_events")
			if events is Array: (events as Array).append({"text": Catalog.line("drop_line", _name_of(int(row[2])), _name_of(victim)), "left": 2.0})
		_splat_victims[victim] = true
	for victim: int in _splat_victims.keys():
		if not present.has(victim): _splat_victims.erase(victim)
	if mine_left >= 0.0:
		if not _splat_up:
			_splat_up = true
			_splat_age = 0.0
			_splat_total = maxf(mine_left, 0.1)
			_splat_count += 1
			if show_view != null:
				var events: Variant = show_view.get("_events")
				if events is Array: (events as Array).append({"text": "%s  ·  %s" % [Catalog.text("splat").to_upper(), _name_of(mine_from)], "left": 2.0})
		_splat_age += dt
		_splat.show_model({"age": _splat_age, "left": minf(maxf(_splat_total - _splat_age, 0.0), mine_left + 0.06), "seed": _splat_count * 31 + mine_from})
	elif _splat_up:
		_splat_up = false
		_splat.show_model({})
	for victim: int in _worn.keys():
		var entry: Dictionary = _worn[victim]
		entry.left = float(entry.left) - dt
		if float(entry.left) <= 0.0 or not is_instance_valid(entry.node):
			if is_instance_valid(entry.node): (entry.node as Node).queue_free()
			_worn.erase(victim)

# ------------------------------------------------------------------ the own bird: camera, buttons

func _mine(rows: Dictionary) -> void:
	var flying := my_slot >= 0 and rows.has(my_slot) and _birds.has(my_slot)
	var can_follow := run != null and (str(run.get("network_role")) != "local" or int(run.get("local_players")) == 1)
	if flying and can_follow:
		if not _mine_on and show_view != null: show_view.call("_say", Catalog.text("banner").to_upper(), "", 1.4, "boon")
		_mine_on = true
		run.set("pigeon_focus", (_birds[my_slot] as Dictionary).pos)
		var row: Array = rows[my_slot]
		var keys := {"coo": "X" if TouchControls.last_device == "pad" else "F", "drop": "LB" if TouchControls.last_device == "pad" else "E"}
		_hud.show_model({"coo": float(row[10]), "coo_total": Catalog.tune("coo_cooldown"), "drop": float(row[11]), "drop_total": Catalog.tune("drop_cooldown"), "keys": keys,
			"touch": show_view != null and show_view.has_method("touching") and bool(show_view.call("touching"))})
	else:
		_end_flight()

func _end_flight() -> void:
	if _mine_on and run != null: run.set("pigeon_focus", null)
	_mine_on = false
	_hud.show_model({})

# ------------------------------------------------------------------ effects, sounds

func _tick_fx(dt: float) -> void:
	for index in range(_fx.size() - 1, -1, -1):
		var fx: Dictionary = _fx[index]
		fx.age = float(fx.age) + dt
		var age := float(fx.age)
		var life := float(fx.life)
		var node: Node3D = fx.node
		if not is_instance_valid(node):
			_fx.remove_at(index)
			continue
		if age >= life:
			node.queue_free()
			_fx.remove_at(index)
			continue
		if age < 0.0:
			node.visible = false
			continue
		node.visible = true
		var t := age / life
		match str(fx.kind):
			"bubble":
				var bird: Variant = _birds.get(int(fx.slot))
				var base: Vector3 = ((bird as Dictionary).pos as Vector3) + Vector3(0.0, 1.2, 0.0) if bird != null else (fx.from as Vector3)
				node.position = base + Vector3(0.0, t * 0.9, 0.0)
				var pop := ShowTheme.pop_scale(age, 0.25, 0.3)
				node.scale = Vector3.ONE * pop
				(node as Label3D).modulate.a = clampf((1.0 - t) * 3.0, 0.0, 1.0)
				(node as Label3D).outline_modulate.a = (node as Label3D).modulate.a * 0.95
			"ring":
				var scale := lerpf(0.4, float(fx.reach) * 2.0, 1.0 - pow(1.0 - t, 2.0))
				node.scale = Vector3(scale, 1.0, scale)
				var material := (node as MeshInstance3D).material_override as StandardMaterial3D
				material.albedo_color.a = 0.7 * (1.0 - t)
				var bird: Variant = _birds.get(int(fx.slot))
				if bird != null: node.position = (bird as Dictionary).pos
			"decal":
				var alpha := clampf((life - age) / 1.0, 0.0, 1.0)
				for child in node.get_children():
					((child as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = alpha

## A sound in the world at `at` (loud: `db` over the base level): a 3D player on the effects bus that frees itself.
func _sound(stream: AudioStream, at: Vector3, db: float, pitch: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = pitch
	player.unit_size = 14.0
	player.max_distance = 140.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.bus = "GW_Effects" if AudioServer.get_bus_index("GW_Effects") >= 0 else "Master"
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()

## The first frames draw every look once, tiny, in front of the camera, so the renderer builds their materials before anybody coos (the same reason as the items' rehearsal, docs/items.md).
func _warm() -> void:
	if _warm_left <= 0 or run == null or not run.get("camera") is Camera3D: return
	_warm_left -= 1
	var camera: Camera3D = run.camera
	var holder := Node3D.new()
	holder.name = "Warm"
	add_child(holder)
	holder.global_position = camera.global_position - camera.global_transform.basis.z * 2.0
	holder.scale = Vector3.ONE * 0.002
	var bird: Node3D = PigeonMesh.build(Color.WHITE)
	holder.add_child(bird)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material
	holder.add_child(ring)
	var disc := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	disc.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	disc.material_override = glow
	holder.add_child(disc)
	get_tree().create_timer(0.1).timeout.connect(holder.queue_free)

# ------------------------------------------------------------------ clearing

func _clear_nodes() -> void:
	for slot: int in _birds.keys(): _drop_bird(slot)
	for id: int in _blobs.keys():
		((_blobs[id] as Dictionary).node as Node).queue_free()
	_blobs.clear()
	for fx: Dictionary in _fx:
		if is_instance_valid(fx.node): (fx.node as Node).queue_free()
	_fx.clear()
	for victim: int in _worn.keys():
		if is_instance_valid((_worn[victim] as Dictionary).node): ((_worn[victim] as Dictionary).node as Node).queue_free()
	_worn.clear()

## No pigeons in this round (or the state has none): everything is put away.
func _reset() -> void:
	_clear_nodes()
	_end_flight()
	_splat_up = false
	_splat.show_model({})
	_splat_victims.clear()
	_seen_seq = -2
	_box_level = -2
	_box = {}
	_shake = 0.0
	_shake_camera(0.0)
