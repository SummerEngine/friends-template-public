extends Node3D
## EXPERIMENT (switchable): TANDEM, the client side (docs/party-show.md "Tandem (experiment)"). Built once per client by client/main.gd (online) and client/local_level_flow.gd (one machine),
## fed the match state's `tandem` (modes/show/shared/tandem/tandem.gd `state()`, {} when it is off) every frame by `present`. Nothing it draws decides anything; what it does to how couriers move is what
## the authority replicated, applied by each owner's machine (game/game_run.gd `tandem`: the pair's walking speed, the averaged steering, the shove, the pull together):
##   * a fused pair: both characters reach for each other's hand (`rig_hold`: the carry pose with one grip at the joined hands), a heart rises from the hands now and then, the pair walks
##     `speed` times as fast, whoever it runs into is flung (`shove`);
##   * the fuse: a pop of hearts and sparks, a TANDEM! banner (the show's banner, `boon`) on the screens of the two, a line for the others (cast `show.tandem`, else tandem.json);
##   * the end: the two spin apart (`rig_spin`), sparks; early ends (a fall, a gap) are quiet;
##   * a lone player's BUDDY (state.buddy): an ordinary character (a rig of its own) that comes running along the player's trail, runs beside it, and takes its hand.
const Config := preload("res://modes/show/shared/tandem/tandem_config.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")
const Fx := preload("res://modes/show/tandem/tandem_fx.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")

const HAND_HEIGHT := 0.95 ## m over the feet: where two hands meet
const HEART_EVERY := 0.55 ## s between the hearts that rise from joined hands
const LINE_SHOW := 3.0 ## s a line about another pair stays
const SPIN_TIME := 0.7 ## s the two spin apart (the tuning's `spin`)
const BUDDY_SEAT := 6 ## the seat look of the buddy's rig (an animal head per seat)
const BANNER_AT := 0.3

class Hud extends Control:
	var model := {}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if model.is_empty(): return
		var view := get_viewport_rect().size
		var k := Kit.k(self)
		var top := (Kit.TOP + 76.0) * k
		var lines: Array = model.get("lines", [])
		for index in range(lines.size() - 1, -1, -1):
			var line: Dictionary = lines[index]
			var rect := Kit.line_pill(self, str(line.text), Vector2(view.x * 0.5, top + Kit.ROW_H * k * 0.6), k * 0.9, clampf(float(line.left) / 0.3, 0.0, 1.0), 0.0, view.x * 0.7)
			top = rect.end.y + 6.0 * k
		var banner: Dictionary = model.get("banner", {})
		if not banner.is_empty():
			ShowBanner.draw(self, "boon", str(banner.words), float(banner.age), Vector2(view.x * 0.5, view.y * BANNER_AT), ShowBanner.small_wide(view.x, k), 1.0, str(banner.get("line", "")))

var run ## the shell (game/game_run.gd)
var my_slot := -1
var seats: Array = [] ## slot -> cast index
var _fx: Node3D
var _layer: CanvasLayer
var _hud: Hud
var _seq := -1
var _clock := 0.0
var _banner := {}
var _lines: Array = []
var _applied: Dictionary = {} ## slots whose run.tandem / run.rig_hold this view set
var _spins: Dictionary = {} ## slot (-1 the buddy) -> {t, sign}
var _heart_at := {} ## pair id -> clock of its last heart
var _buddy_rig: Node3D
var _buddy_pos := Vector3.ZERO
var _buddy_yaw := 0.0
var _buddy_vel := Vector3.ZERO
var _buddy_phase := -1
var _buddy_spin := 0.0
var _feet_cache := {}
var last_state := {}
var banners_shown := 0 ## the checks read these
var pops := 0

func setup(shell, slot: int, round_seats: Array) -> void:
	run = shell
	my_slot = slot
	seats = round_seats
	name = "TandemView"
	_fx = Fx.new()
	add_child(_fx)
	_layer = CanvasLayer.new()
	_layer.layer = 23
	add_child(_layer)
	_hud = Hud.new()
	_layer.add_child(_hud)

func set_viewer(slot: int, round_seats: Array) -> void:
	my_slot = slot
	seats = round_seats

func _exit_tree() -> void:
	_release()

func name_of(slot: int) -> String:
	if slot == Tandem.BUDDY: return "BUDDY"
	var seat := int(seats[slot]) if slot >= 0 and slot < seats.size() and int(seats[slot]) >= 0 else slot
	return str(TeamCast.player(seat).name)

func _feet(slot: int) -> Vector3:
	if slot == Tandem.BUDDY: return _buddy_pos
	if run == null or slot < 0 or slot >= run.actors.size(): return Vector3.ZERO
	return run.actors[slot].global_position

func _seen(slot: int) -> Vector3:
	if slot == Tandem.BUDDY: return _buddy_pos
	if run == null or slot < 0 or slot >= run.actors.size(): return Vector3.ZERO
	return run.visual_position(slot)

# ------------------------------------------------------------------ every frame

## `state`: the match state's `tandem` ({} / absent when it is off or nothing may fuse: everything this view put on the shell is let go).
func present(state: Dictionary, dt: float) -> void:
	if run == null or not is_instance_valid(run): return
	_clock += dt
	last_state = state
	_buddy_state(state.get("buddy", []), dt)
	var now := {}
	var holds := {}
	for row: Array in state.get("pairs", []):
		var a := int(row[1])
		var b := int(row[2])
		var mid := (_seen(a) + _seen(b)) * 0.5 + Vector3.UP * HAND_HEIGHT
		var moves := [Vector2(float(row[7]), float(row[8])), Vector2(float(row[5]), float(row[6]))] # a steers by b's input and the other way round
		for side in 2:
			var slot: int = a if side == 0 else b
			var other: int = b if side == 0 else a
			holds[slot] = mid
			if slot < 0: continue
			now[slot] = {"with": other, "move": moves[side], "at": _feet(other), "speed": Config.tune("speed"), "power": Config.tune("shove")}
		var id := int(row[0])
		if _clock - float(_heart_at.get(id, -9.0)) >= HEART_EVERY:
			_heart_at[id] = _clock
			_fx.heart(mid + Vector3.UP * 0.25, Vector3(randf_range(-0.3, 0.3), 1.3, randf_range(-0.3, 0.3)), 0.24, 1.1)
	for row: Array in state.get("warm", []): # two that are nearly holding hands: a spark at the middle
		if float(row[2]) >= 0.5 and Engine.get_frames_drawn() % 7 == 0:
			_fx.spark((_seen(int(row[0])) + _seen(int(row[1]))) * 0.5 + Vector3.UP * HAND_HEIGHT, Vector3(randf_range(-0.4, 0.4), 0.8, randf_range(-0.4, 0.4)), 0.16, 0.5)
	_apply(now, holds)
	_events(state)
	_spin_step(dt)
	_fx.step(dt)
	_banner_clock(dt)
	_hud.model = {"banner": _banner, "lines": _lines} if (not _banner.is_empty() or not _lines.is_empty()) else {}
	_hud.queue_redraw()
	_buddy_draw(dt, holds.get(Tandem.BUDDY))

func _apply(now: Dictionary, holds: Dictionary) -> void:
	for slot: int in _applied.keys():
		if now.has(slot): continue
		run.tandem.erase(slot)
		run.rig_hold.erase(slot)
		_applied.erase(slot)
	for slot: int in now:
		run.tandem[slot] = now[slot]
		run.rig_hold[slot] = holds[slot]
		_applied[slot] = true

## Everything this view put on the shell is let go (a new round, the view leaves).
func _release() -> void:
	if run != null and is_instance_valid(run):
		for slot: int in _applied.keys():
			run.tandem.erase(slot)
			run.rig_hold.erase(slot)
		for slot: int in _spins.keys():
			if slot >= 0: run.rig_spin.erase(slot)
	_applied.clear()
	_spins.clear()

func _banner_clock(dt: float) -> void:
	if not _banner.is_empty():
		_banner.age = float(_banner.age) + dt
		if float(_banner.age) > ShowBanner.total("boon"): _banner = {}
	for line: Dictionary in _lines: line.left = float(line.left) - dt
	_lines = _lines.filter(func(line: Dictionary) -> bool: return float(line.left) > 0.0)

# ------------------------------------------------------------------ events

func _events(state: Dictionary) -> void:
	var list: Array = state.get("ev", [])
	if _seq < 0:
		_seq = int(state.get("seq", 1)) - 1 if state.has("seq") else (0 if list.is_empty() else int((list.back() as Array)[0]))
		return
	for row: Array in list:
		if int(row[0]) <= _seq: continue
		_seq = int(row[0])
		var a := int(row[2])
		var b := int(row[3])
		match int(row[1]):
			Tandem.Event.FUSE: _fused(a, b)
			Tandem.Event.END: _ended(a, b)
			Tandem.Event.SLIP:
				_fx.poof(_seen(a) + Vector3.UP * 0.9)
			Tandem.Event.BUDDY_IN, Tandem.Event.BUDDY_OUT:
				_fx.poof(_buddy_pos + Vector3.UP * 0.9)

func _fused(a: int, b: int) -> void:
	var mid := (_seen(a) + _seen(b)) * 0.5 + Vector3.UP * HAND_HEIGHT
	_fx.burst(mid)
	pops += 1
	_sfx("res://audio/items/box_get.ogg", mid, -3.0)
	if a == my_slot or b == my_slot:
		var other := b if a == my_slot else a
		_banner = {"words": Config.text("banner"), "line": "WITH %s" % name_of(other), "age": 0.0}
		banners_shown += 1
	else: _lines.append({"text": Config.line(name_of(a), name_of(b)), "left": LINE_SHOW})
	while _lines.size() > 3: _lines.pop_front()

func _ended(a: int, b: int) -> void:
	_spins[a] = {"t": 0.0, "sign": 1.0}
	_spins[b] = {"t": 0.0, "sign": -1.0}
	_fx.poof(_seen(a) + Vector3.UP * 0.9)
	_fx.poof(_seen(b) + Vector3.UP * 0.9)
	_sfx("res://audio/items/boost_hit.ogg", (_seen(a) + _seen(b)) * 0.5, -6.0)

func _spin_step(dt: float) -> void:
	var span := maxf(Config.tune("spin"), 0.1)
	for slot: int in _spins.keys():
		var spin: Dictionary = _spins[slot]
		spin.t = float(spin.t) + dt
		var u := clampf(float(spin.t) / span, 0.0, 1.0)
		var angle := float(spin.sign) * TAU * (1.0 - pow(1.0 - u, 2.0)) * 1.5
		if slot == Tandem.BUDDY: _buddy_spin = angle
		else: run.rig_spin[slot] = angle
		if u >= 1.0:
			if slot >= 0: run.rig_spin.erase(slot)
			else: _buddy_spin = 0.0
			_spins.erase(slot)

func _sfx(path: String, at: Vector3, gain_db: float) -> void:
	if not is_inside_tree() or not ResourceLoader.exists(path): return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.volume_db = gain_db
	player.max_distance = 70.0
	player.unit_size = 8.0
	add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()

# ------------------------------------------------------------------ the buddy

func _buddy_state(row: Array, dt: float) -> void:
	if row.size() < 7:
		_buddy_phase = -1
		if _buddy_rig != null: _buddy_rig.visible = false
		return
	var at := Vector3(float(row[0]), float(row[1]), float(row[2]))
	_buddy_vel = Vector3(float(row[4]), 0.0, float(row[5]))
	_buddy_yaw = float(row[3])
	if _buddy_rig == null or _buddy_phase < 0 or _buddy_pos.distance_to(at) > 6.0: _buddy_pos = at
	else:
		var ahead := _buddy_pos + _buddy_vel * dt
		_buddy_pos = ahead.lerp(at, 0.35)
	_buddy_phase = int(row[6])

func _buddy_draw(dt: float, hold: Variant) -> void:
	if _buddy_phase < 0: return
	if _buddy_rig == null:
		var script: GDScript = load("res://character/character_rig.gd")
		if not script.call("available"): script = load("res://courier/courier_rig.gd")
		_buddy_rig = script.new()
		_buddy_rig.name = "TandemBuddy"
		run.world.add_child(_buddy_rig)
		_buddy_rig.setup(BUDDY_SEAT)
	var rig := _buddy_rig
	rig.visible = true
	rig.global_position = _buddy_pos
	var state := {"velocity": _buddy_vel, "carrying": false, "paused": false, "grounded": true, "yaw": _buddy_yaw, "acceleration": Vector3.ZERO, "floor_normal": Vector3.UP, "flop": 0.0,
		"look_at": _seen(my_slot) if my_slot >= 0 else _buddy_pos}
	var grips := []
	if hold is Vector3:
		var towards: bool = rig.to_local(hold as Vector3).x > 0.0
		var loose: Vector3 = rig.to_global(Vector3(-0.42 if towards else 0.42, 0.8, -0.15))
		grips = [loose, hold] if towards else [hold, loose]
		state.carrying = true
	rig.update(dt, state, grips)
	if _buddy_spin != 0.0: rig.global_basis = Basis(Vector3.UP, _buddy_spin) * rig.global_basis

## The buddy's rig node (the checks and the frames read it).
func buddy_rig() -> Node3D:
	return _buddy_rig if _buddy_rig != null and is_instance_valid(_buddy_rig) and _buddy_rig.visible else null
