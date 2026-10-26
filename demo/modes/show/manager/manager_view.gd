extends Node3D
## EXPERIMENT (switchable): THE MANAGER, client side. Added by modes/show/view.gd as a child; it reads only `manager` of the show's state (manager_rules.gd state()) and draws everything:
##   * the round's first banner (THE MANAGER, and who) and the clipboard over the manager's head (manager_marker.gd, a child of the rig's head anchor),
##   * the prompt of the manager: a compact translucent strip at the BOTTOM EDGE with the three choices as small chips (1 2 3; a click or a tap picks too) and a thin bar that runs out
##     with the 3 s it stays open (no panel in the middle of the screen); the others read "<name> IS PICKING A RULE" in a small pill,
##   * the rule's banner (red for the ones it hits, blue for the rest) and the pill that counts it down (the rule's icon at its left end, a red outline when it is on you),
##   * what a rule does on this machine: the mods of the targets' couriers (game/game_run.gd rule_mods: inverted, moon gravity, no jump, ice, walk only), their rig's scale (rule_scales: giant,
##     tiny) and the local camera's roll (the upside-down camera). A courier moves on its own machine, so each owner's machine applies it from the replicated state; nothing here decides anything.
## It also tells the shell while its prompt is open for this player (`run.number_keys`): the number keys 1-3 then travel to the authority as test_seq, as in the item lab.
const Catalog := preload("res://modes/show/shared/manager/manager_catalog.gd")
const Icons := preload("res://modes/show/manager/manager_icons.gd")
const Marker := preload("res://modes/show/manager/manager_marker.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const TouchControls := preload("res://client/touch_controls.gd")

const BANNER_AT := 0.3 ## the banner's middle, of the screen's height (the items' banners sit there too)
const BANNER_WAIT := 2.5 ## s a banner waits for the show's own banner before it comes up anyway
const FADE := 0.45 ## s a rule's scale eases in and out over
const ROLL_RATE := 5.0 ## rad/s the camera turns over at (the upside-down camera takes 0.6 s)
const BELL := "res://audio/items/box_get.ogg"
const GONG := "res://audio/items/flip_hit.ogg"

var run ## the shell
var my_slot := -1
var seats: Array = []
var items_view: Node ## modes/show/items_ui/items_view.gd: an item banner makes room for ours and we wait for the show's (its `busy`)
var busy := false ## the show's own big banner is up (set by modes/show/view.gd every frame)
var layer: CanvasLayer
var hud: Control
var info: Dictionary = {} ## the last state's `manager`
var banner := {} ## {kind, words, line, age} on screen
var _queued := {}
var _queued_wait := 0.0
var _round := -1
var _seq := -1 ## the newest rule issued that this client has told (-1 until the round's first state)
var _intro := false ## the round's THE MANAGER banner is still to come
var _age := 0.0 ## s into the rule in force (negative: still to start), advanced by the frame
var _roll := 0.0 ## the roll of the main camera applied now
var _split_rolls := [0.0, 0.0] ## the roll of each split-screen camera (local play, a view each), by slot
var _clock := 0.0
var _marker: Node3D
var _marker_head: Node3D
var _prompt_age := 0.0
var _prompt_open := false

func setup(shell, slot: int, round_seats: Array, items: Node) -> void:
	run = shell
	my_slot = slot
	seats = round_seats
	items_view = items
	name = "Manager"
	layer = CanvasLayer.new()
	layer.layer = 23
	add_child(layer)
	hud = Hud.new()
	hud.view = self
	layer.add_child(hud)

func _exit_tree() -> void:
	_clear_shell()
	_drop_marker()

# ------------------------------------------------------------------ helpers

func name_of(slot: int) -> String:
	return str(preload("res://style/team_cast.gd").player(int(seats[slot]) if slot >= 0 and slot < seats.size() else slot).name).to_upper()

func manager_slot() -> int:
	return int(info.get("mgr", -1))

## The prompt is the local player's to answer: it is the manager's own screen (the first local player of a one-machine show; the second one has the B key).
func prompt_is_mine() -> bool:
	var mgr := manager_slot()
	if mgr < 0 or my_slot < 0: return false
	if run != null and str(run.get("network_role")) == "local": return mgr == 0
	return mgr == my_slot

func touching() -> bool:
	return run != null and run.get("touch") != null and is_instance_valid(run.touch) and run.touch.is_active()

## The hint over the strip, only where the chips' own numbers do not say it: a second local player has no number keys (B picks one at random).
func hint_words() -> String:
	if run != null and str(run.get("network_role")) == "local" and manager_slot() != 0: return "B  PICKS ONE AT RANDOM"
	return ""

## A card was clicked or tapped: the number key travels like a typed one.
func tap(index: int) -> void:
	if not prompt_is_mine(): return
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = (KEY_1 + index) as Key
		event.physical_keycode = (KEY_1 + index) as Key
		event.pressed = down
		event.device = InputEvent.DEVICE_ID_EMULATION
		Input.parse_input_event(event)

func _play(path: String, gain_db := 0.0) -> void:
	if not is_inside_tree() or not ResourceLoader.exists(path): return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = gain_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

# ------------------------------------------------------------------ every frame

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	var fresh: Variant = state.get("manager")
	if not fresh is Dictionary:
		if not info.is_empty(): _reset()
		hud.model = {}
		hud.queue_redraw()
		return
	info = fresh
	var round_number := int(state.get("round", 0))
	if round_number != _round:
		_reset()
		info = fresh
		_round = round_number
		_seq = int(info.get("seq", 0))
		_intro = true
	_intro_banner(state)
	_prompt(dt)
	_rule(dt)
	_marker_state()
	_banner_clock(dt)
	hud.model = {"info": info, "age": _age, "banner": banner, "clock": _clock, "prompt_age": _prompt_age, "mine": prompt_is_mine()}
	hud.queue_redraw()

## The round's first words: who the manager is.
func _intro_banner(state: Dictionary) -> void:
	if not _intro or str(state.get("phase", "")) != "play" or float(state.get("t", 0.0)) < float(Catalog.timing("intro")): return
	_intro = false
	var mgr := manager_slot()
	if mgr < 0: return
	var mine := mgr == my_slot
	_say("title", Catalog.text("title"), Catalog.text("you") if mine else Catalog.text("line", name_of(mgr)))
	_play(BELL)

func _prompt(dt: float) -> void:
	var open := int(info.get("ph", 0)) == 1
	if open and not _prompt_open: _prompt_age = 0.0
	_prompt_open = open
	_prompt_age += dt
	if run != null and is_instance_valid(run): run.number_keys = open and prompt_is_mine()

func _rule(dt: float) -> void:
	var seq := int(info.get("seq", 0))
	var ruled := int(info.get("ph", 0)) == 2 and int(info.get("rule", -1)) >= 0
	if seq > _seq:
		_seq = seq
		if ruled: _announce()
	elif seq < _seq: _seq = seq
	if not ruled:
		_age = 0.0
		_apply({}, 0.0, dt)
		return
	_age += dt
	var told := float(info.get("age", 0.0))
	if absf(_age - told) > 0.5 or (_age < 0.0 and told >= 0.0 and told < 0.3): _age = told # a state that knows better (a late joiner, a stall)
	var id := Catalog.id_of(int(info.rule))
	_apply({"id": id, "left": float(info.get("dur", 0.0)) - _age}, _age, dt)

## The rule's banner: red where it hits (the targets), blue for the rest.
func _announce() -> void:
	var id := Catalog.id_of(int(info.rule))
	var targets: Array = info.get("tg", [])
	var hits := targets.has(my_slot)
	_say("alert" if hits else "item", Catalog.rule_text(id, "banner"), Catalog.rule_text(id, "line", name_of(manager_slot())))
	_play(GONG)
	_age = float(info.get("age", -1.0))

func _say(kind: String, words: String, line := "") -> void:
	var next := {"kind": kind, "words": words, "line": line, "age": 0.0}
	if _blocked():
		_queued = next
		_queued_wait = 0.0
	else: _show(next)

func _show(next: Dictionary) -> void:
	banner = next
	_queued = {}
	if items_view != null and items_view.has_method("cut_banner"): items_view.cut_banner() # one big banner at a time: an item banner makes room

func _blocked() -> bool:
	if busy: return true
	var theirs: Variant = items_view.get("_banner") if items_view != null else null
	return theirs is Dictionary and not (theirs as Dictionary).is_empty()

func _banner_clock(dt: float) -> void:
	if not _queued.is_empty():
		_queued_wait += dt
		if not _blocked() or _queued_wait > BANNER_WAIT: _show(_queued)
	if banner.is_empty(): return
	banner.age = float(banner.age) + dt
	if float(banner.age) > ShowBanner.total(str(banner.kind)): banner = {}

## Puts the rule on the targets' couriers and rigs and on the cameras of the targets (`rule` {id, left} or {} for none): never on the manager's.
func _apply(rule: Dictionary, age: float, dt: float) -> void:
	if run == null or not is_instance_valid(run): return
	var per_mods := {}
	var per_scale := {}
	var wanted := 0.0
	var targets: Array = []
	if not rule.is_empty() and age >= 0.0:
		var id := str(rule.id)
		var mods := Catalog.mods(id)
		var grown := Catalog.scale_of(id)
		var ease_in := clampf(minf(age, float(rule.left)) / FADE, 0.0, 1.0)
		targets = info.get("tg", [])
		for slot: Variant in targets:
			if not mods.is_empty(): per_mods[int(slot)] = mods
			if grown != Vector3.ONE: per_scale[int(slot)] = Vector3.ONE.lerp(grown, ease(ease_in, -2.0))
		if float(rule.left) > 0.0: wanted = Catalog.camera_roll(id)
	run.rule_mods = per_mods
	run.rule_scales = per_scale
	var split := _split_views()
	var main_hit := false # the main camera: the one view of this machine, or one shared by the players on it; a victim among them turns it over
	if not split:
		for slot in _screen_slots(): main_hit = main_hit or targets.has(slot)
	_roll = move_toward(_roll, wanted if main_hit else 0.0, ROLL_RATE * dt)
	for slot in 2: # split screen (two players on one machine, a view each): the view of a victim turns over, the manager's does not
		_split_rolls[slot] = move_toward(float(_split_rolls[slot]), wanted if split and targets.has(slot) else 0.0, ROLL_RATE * dt)
	_camera()

## The slots whose courier this machine's main camera shows: the players on it (local play), else the one of this client.
func _screen_slots() -> Array:
	if str(run.get("network_role")) == "local": return range(int(run.get("local_players")))
	return [my_slot]

## Local play with a view each (the shell's split screen): its two cameras are `run.split_follow`.
func _split_views() -> bool:
	if run == null or str(run.get("network_role")) != "local" or not run.has_method("_split_views"): return false
	return bool(run.call("_split_views")) and (run.get("split_follow") as Array).size() >= 2

## The roll goes on each camera's `fx` next to what the items put there (their dict is a new one each frame while the race has items): our share is kept in `manager_roll`.
func _camera() -> void:
	if run == null: return
	var follow: Variant = run.get("follow")
	if follow != null: _roll_on(follow, _roll)
	var splits: Variant = run.get("split_follow")
	if splits is Array:
		for slot in mini((splits as Array).size(), 2): _roll_on((splits as Array)[slot], float(_split_rolls[slot]))

func _roll_on(follow: Object, roll: float) -> void:
	var fx: Dictionary = follow.fx
	var mine := float(fx.get("manager_roll", 0.0))
	if is_zero_approx(roll) and is_zero_approx(mine):
		fx.erase("manager_roll")
		return
	var base := float(fx.get("roll", 0.0)) - mine
	if is_zero_approx(roll):
		fx.erase("manager_roll")
		if is_zero_approx(base): fx.erase("roll")
		else: fx["roll"] = base
		return
	fx["roll"] = base + roll
	fx["manager_roll"] = roll

# ------------------------------------------------------------------ the clipboard

func _marker_state() -> void:
	var mgr := manager_slot()
	var rig: Variant = null
	if mgr >= 0 and run != null and mgr < run.rigs.size(): rig = run.rigs[mgr]
	var head: Node3D = null
	if rig != null and is_instance_valid(rig) and (rig as Node).has_method("head_anchor"): head = (rig as Node).call("head_anchor")
	if head == null:
		_drop_marker()
		return
	if _marker == null: _marker = Marker.build()
	if _marker.get_parent() != head:
		if _marker.get_parent() != null: _marker.get_parent().remove_child(_marker)
		head.add_child(_marker)
		_marker_head = head
	Marker.animate(_marker, _clock)

func _drop_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		if _marker.get_parent() != null: _marker.get_parent().remove_child(_marker)
		_marker.queue_free()
	_marker = null
	_marker_head = null

# ------------------------------------------------------------------ clean up

func _reset() -> void:
	info = {}
	banner = {}
	_queued = {}
	_seq = -1
	_age = 0.0
	_intro = false
	_prompt_open = false
	_clear_shell()
	_drop_marker()

func _clear_shell() -> void:
	if run == null or not is_instance_valid(run): return
	run.rule_mods = {}
	run.rule_scales = {}
	run.number_keys = false
	_roll = 0.0
	_split_rolls = [0.0, 0.0]
	_camera()

# ------------------------------------------------------------------ the HUD

## The rule cards, the banner and the pill, one control drawing in the show's one look (client/show_theme.gd, style/show_hud_kit.gd).
class Hud extends Control:
	var view
	var model := {}
	var _cards: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		for index in 3:
			var card := Card.new()
			card.index = index
			card.visible = false
			card.pressed.connect(func() -> void: view.tap(index))
			add_child(card)
			_cards.append(card)

	func _draw() -> void:
		if model.is_empty(): return
		var info: Dictionary = model.info
		var view_size := get_viewport_rect().size
		var k := Kit.k(self)
		_prompt(info, view_size, k)
		_pill(info, view_size, k)
		var words: Dictionary = model.get("banner", {})
		if not words.is_empty():
			ShowBanner.draw(self, str(words.kind), str(words.words), float(words.age), Vector2(view_size.x * 0.5, view_size.y * BANNER_AT), ShowBanner.small_wide(view_size.x, k), 1.0, str(words.get("line", "")))

	func _prompt(info: Dictionary, view_size: Vector2, k: float) -> void:
		var open := int(info.get("ph", 0)) == 1
		var mgr := int(info.get("mgr", -1))
		for card: Card in _cards: card.visible = false
		if not open: return
		var left := float(info.get("t", 0.0))
		if not bool(model.get("mine", false)) and not view.prompt_is_mine():
			Kit.line_pill(self, Catalog.text("waiting", view.name_of(mgr)), Vector2(view_size.x * 0.5, (Kit.TOP + 80.0) * k), k * 0.7, 1.0, 0.0, view_size.x * 0.7)
			return
		var choices: Array = info.get("ch", [])
		var gap := 6.0 * k
		var high := 44.0 * k
		var wide := minf(214.0 * k, (view_size.x * 0.62 - gap * 2.0) / 3.0)
		var total := wide * choices.size() + gap * maxf(choices.size() - 1.0, 0.0)
		var top := view_size.y - high - 20.0 * k # the strip hugs the bottom edge
		var fade := clampf(float(model.get("prompt_age", 0.0)) / 0.18, 0.0, 1.0)
		var left_x := view_size.x * 0.5 - total * 0.5
		for index in choices.size():
			var card: Card = _cards[index]
			card.visible = true
			card.rule_id = Catalog.id_of(int(choices[index]))
			card.words = Catalog.rule_text(card.rule_id, "name")
			card.size = Vector2(wide, high)
			card.position = Vector2(left_x + (wide + gap) * index, top + (1.0 - fade) * 10.0 * k)
			card.modulate = Color(1, 1, 1, 0.8 * fade)
			card.queue_redraw()
		var share := clampf(left / maxf(float(Catalog.timing("prompt")), 0.1), 0.0, 1.0) # the bar runs out with the prompt's seconds
		var bar := Rect2(left_x, top + high + 5.0 * k, total, 4.0 * k)
		draw_rect(bar, Color(0, 0, 0, 0.4 * fade))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(ShowTheme.CREAM, 0.85 * fade))
		var hint: String = view.hint_words()
		if hint != "": Kit.line_pill(self, hint, Vector2(view_size.x * 0.5, top - 20.0 * k), k * 0.6, fade, 0.0, view_size.x * 0.9)

	func _pill(info: Dictionary, view_size: Vector2, k: float) -> void:
		if int(info.get("ph", 0)) != 2 or int(info.get("rule", -1)) < 0: return
		var age := float(model.get("age", 0.0))
		if age < 0.0: return
		var id := Catalog.id_of(int(info.rule))
		var left := maxf(float(info.get("dur", 0.0)) - age, 0.0)
		var hits: bool = (info.get("tg", []) as Array).has(view.my_slot)
		var pop := ShowTheme.pop_scale(age, 0.35, 0.3)
		var alpha := clampf(left / 0.3, 0.0, 1.0)
		var rect := Kit.icon_pill(self, "%s  %d" % [Catalog.rule_text(id, "name"), ceili(left)], view_size.x * 0.5 + 170.0 * k * pop, view_size.y - 205.0 * k, k * pop, alpha, 1.0, 340.0 * k, ShowTheme.RED if hits else ShowTheme.PILL_EDGE)
		Icons.draw(self, id, Kit.icon_centre(rect), Kit.icon_radius(rect), alpha)

## One of the strip's three rule chips: a small dark rounded chip with its number (the key), the rule's icon and its name; a click or a tap picks it.
class Card extends Button:
	var index := 0
	var rule_id := ""
	var words := ""

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var lit := is_hovered() or button_pressed
		var rect := Rect2(Vector2.ZERO, size)
		var high := size.y
		ShowTheme.box(self, rect, ShowTheme.PILL, ShowTheme.CREAM if lit else ShowTheme.PILL_EDGE, maxf(high * 0.04, 1.2) * (1.6 if lit else 1.0), high * 0.3)
		var badge := Vector2(high * 0.5, high * 0.5)
		draw_circle(badge, high * 0.26, ShowTheme.CREAM)
		ShowTheme.text(self, str(index + 1), badge, high * 0.34, ShowTheme.NAVY)
		Icons.draw(self, rule_id, Vector2(high * 1.22, high * 0.5), high * 0.3)
		var fit := high * 0.36
		var room := size.x - high * 1.7 - high * 0.2
		var wide := ShowTheme.width(words, fit) * (1.0 + ShowTheme.SLANT * 0.1)
		if wide > room: fit *= room / wide
		ShowTheme.text(self, words, Vector2(high * 1.7, high * 0.5), fit, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
