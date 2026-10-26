extends CanvasLayer
const _DevLap := preload("res://dev_env.gd")
## In-round HUD in the clean display type, each word on a small flat chip: the run time top left (digits only), the
## CRACK!/WHOOPS! word on red with the retry key when the delivery fails (POP! in a balloon round, with the pops under the
## clock), and key hints that teach move / jump / tilt / lift (grab in a balloon round; turn when two players share one keyboard)
## at the moment they matter. The keys come from game/game_input.gd (KEY_HINTS). The hints sit in the lower outer corner of
## each player's view, clear of the hands and the carried painting: one view = bottom left; two views side by side = the left
## player's bottom left, the right player's bottom right, each with that player's own keys and fading once that player has
## used them. On one shared view with two keyboard players each hint shows both players' keys, the first player's left.
## Reads replicated state; changes nothing.
const Ui = preload("res://client/friends_ui.gd")
const HudComic = preload("res://client/hud_comic.gd")
const Parts = preload("res://client/hud_comic_parts.gd")
const ComicText = preload("res://client/comic_text.gd")
const TeamCast = preload("res://style/team_cast.gd")
const TouchControls = preload("res://client/touch_controls.gd")
const PaintingScript = preload("res://game/painting.gd")
const CastBubbles = preload("res://client/cast_bubbles.gd")
const CastAnnouncer = preload("res://client/cast_announcer.gd")
const GameInput = preload("res://game/game_input.gd")
const TOUCH_KEYS := {"move": ["WALK"], "turn": [], "jump": ["JUMP"], "tilt": ["TILT"], "lift": ["LIFT", "LOWER"], "grab": ["GRAB"]}
## Pad names per hint (the pad's own buttons; the keyboard keys come from GameInput.KEY_HINTS).
const PAD_KEYS := {"move": ["STICK"], "turn": ["STICK"], "jump": ["A"], "tilt": ["LT", "RT"], "lift": ["LB", "RB"], "grab": ["X"]}
## The hints in the order they are taught.
const KINDS := ["move", "turn", "jump", "tilt", "lift", "grab"]
const TILT_DEGREES := 80.0
const LIFT_METERS := 0.45
const PROBE_PERIOD := 0.12
const NEED_HOLD := 1.4
const KEYCODES := {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D, "Q": KEY_Q, "E": KEY_E, "Z": KEY_Z, "X": KEY_X, "R": KEY_R, "F": KEY_F, "SPACE": KEY_SPACE,
	"C": KEY_C, "V": KEY_V, "I": KEY_I, "J": KEY_J, "K": KEY_K, "L": KEY_L, "U": KEY_U, "O": KEY_O, "M": KEY_M, "N": KEY_N, "H": KEY_H, "Y": KEY_Y,
	",": KEY_COMMA, ".": KEY_PERIOD}
## What a person has already learned this session; a sign never returns once used. The second view's player learns under
## "<kind>@2" (taught_key).
static var taught: Dictionary = {}
## How long a player moves before the move hint fades (its first move).
const MOVE_TAUGHT := 0.2

## The running game shell; the tilt/lift hints probe its painting against the world.
var simulation: Node
var clock_view: Parts.Clock
var retry: RetryPlate
var bubbles: CastBubbles ## the cast's catchphrases over the couriers on a break, a fall and the goal
var announcer: CastAnnouncer ## the cast's announcer lines on the moments of a round
var signs: Dictionary = {} ## the first (or only) view's hints, by kind
var seat_signs: Array = [] ## [signs, the second view's hints]
var previous_second := 0
var previous_resets := -1
var timer_text := "00:00"
var breaks := 0
var round_seconds := 0.0
var playing := false
var failed := false
var balloon_mode := false ## a balloon round: no painting hints, GRAB taught, pops under the clock
var roll := 0.0
var lift := 0.0
var held: Array = [{}, {}] ## per view: seconds each hint's keys were held this session
var probe_clock := 0.0
var need := {"tilt": 0.0, "lift": 0.0}
var last_need := {"tilt": false, "lift": false}
var clock := 0.0
var forced: Dictionary = {}
var blocked_ahead := false
var probe_speed := 0.0

# ================================================================== widgets

## Centre word shown while the delivery is broken: the verdict on a red chip and the retry key under it.
class RetryPlate extends Control:
	const WORD_CAP := 92.0
	const KEY_CAP := 54.0
	const KEY_CAP_TOUCH := 84.0 ## a thumb-sized key (the overlay's MIN_BUTTON_HEIGHT is 76): it is a real button on touch
	var word := TeamCast.word("break")
	var clock := 0.0
	var age := 0.0
	var shown := false
	var pad := false
	var touch := false ## the RETRY button instead of the R key
	var _word: ComicText
	var _keys: Parts.Keys
	var _sig := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		_word = HudComic.word(word, WORD_CAP)
		HudComic.fail_style(_word)
		add_child(_word)
		_keys = Parts.Keys.new()
		add_child(_keys)

	func show_for(kind: String) -> void:
		word = TeamCast.word("pop") if kind == "pop" else (TeamCast.word("fall") if kind == "death" else TeamCast.word("break"))
		if not shown:
			age = 0.0
		shown = true
		visible = true

	func hide_plate() -> void:
		shown = false
		visible = false
		_publish_target(Rect2())

	func _exit_tree() -> void:
		_publish_target(Rect2())

	## On touch the key under CRACK! / SPLASH! is tappable: tell the overlay where it is (it sends the same R as its RETRY button).
	func _publish_target(rect: Rect2) -> void:
		if not is_inside_tree(): return
		for overlay in get_tree().get_nodes_in_group(TouchControls.GROUP): overlay.set_retry_target(rect)

	func _process(delta: float) -> void:
		if not shown: return
		clock += delta
		age += delta
		pad = Ui.using_gamepad
		modulate.a = minf(age / 0.18, 1.0)
		_place()

	func _input(event: InputEvent) -> void:
		Ui.note_input(event)

	func _place() -> void:
		var unit := HudComic.unit_of(self)
		var retry_key := "Y" if pad else ("RETRY" if touch else "R")
		var key_cap := (KEY_CAP_TOUCH if touch and not pad else KEY_CAP) * unit
		var sig := "%s|%s|%.2f" % [word, retry_key, unit]
		if sig != _sig:
			_sig = sig
			HudComic.update(_word, word, WORD_CAP * unit)
			_keys.set_keys([retry_key], key_cap, key_cap)
			_keys.light_all(true)
		var width := maxf(_word.size.x, _keys.size.x)
		var gap := 22.0 * unit
		var total := Vector2(width, _word.size.y + gap + _keys.size.y)
		var t := Ui.out_back(minf(age / 0.35, 1.0))
		var bob := sin(clock * 4.0) * 1.5 * unit
		var centre := Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.27)
		size = total
		pivot_offset = total * 0.5
		scale = Vector2.ONE * lerpf(1.2, 1.0, t)
		rotation = 0.0
		position = centre - total * 0.5
		_word.position = Vector2((width - _word.size.x) * 0.5, 0.0)
		_keys.position = Vector2((width - _keys.size.x) * 0.5, _word.size.y + gap + bob)
		var hot := Rect2()
		if touch and not pad and age > 0.18 and is_visible_in_tree(): hot = (_keys.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _keys.size)).grow(14.0 * unit)
		_publish_target(hot)

## One key hint: a pictogram (tilt / lift) on a dark chip and the keys as flat keycaps (or gamepad / touch names). The
## key being held turns the accent.
class SignView extends Control:
	var kind := ""
	var keys: Array = []
	var pad_keys: Array = []
	var touch_keys: Array = []
	var pad := false
	var touch := false
	var clock := 0.0
	var amount := 0.0 # 0..1 visibility
	var wanted := false
	var phase := 0.0
	var _top: Parts.Keys
	var _bottom: Parts.Keys
	var _top_y := 0.0
	var _bottom_y := 0.0
	var _sig := ""
	var _extent := Vector2(200, 80)
	var _glyph := 0.0
	var _glyph_centre := Vector2.ZERO
	var _unit := 1.0
	var _bob := 0.0
	## The second view's player on a pad (keyboard and pad, or two pads): pad names only.
	var pad_only := false

	func _init(sign_kind: String, key_list: Array, pad_list: Array) -> void:
		kind = sign_kind
		keys = key_list
		pad_keys = pad_list
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.0
		visible = false
		_top = Parts.Keys.new()
		_bottom = Parts.Keys.new()
		add_child(_top)
		add_child(_bottom)

	func _input(event: InputEvent) -> void:
		Ui.note_input(event)

	func _process(delta: float) -> void:
		clock += delta
		amount = move_toward(amount, 1.0 if wanted else 0.0, delta / (0.35 if wanted else 0.5))
		modulate.a = clampf(amount * 1.4, 0.0, 1.0)
		visible = amount > 0.01
		pad = pad_only or Ui.using_gamepad
		if not visible: return
		var pop := Ui.out_back(amount)
		_bob = sin(clock * 3.2 + phase) * 2.2 * _unit + (1.0 - pop) * 26.0 * _unit
		pivot_offset = size * 0.5
		scale = Vector2.ONE * lerpf(0.85, 1.0, pop)
		_top.position.y = _top_y + _bob
		_bottom.position.y = _bottom_y + _bob
		if not pad and not touch:
			for key: String in _list():
				_top.light(key, _down(key))
				_bottom.light(key, _down(key))
		queue_redraw()

	func _list() -> Array:
		return pad_keys if pad else (touch_keys if touch else keys)

	## Size of the sign at this pixel scale; also (re)builds its keycaps when the input family changes.
	func plate_size(unit: float) -> Vector2:
		_unit = unit
		var list: Array = _list()
		var sig := "%s|%s|%.2f|%s" % [pad, touch, unit, ",".join(PackedStringArray(list))]
		if sig == _sig: return _extent
		_sig = sig
		var cap := (40.0 if kind == "move" else 48.0) * unit
		var cell := cap * 0.96
		_glyph = 84.0 * unit if kind in ["tilt", "lift"] else 0.0
		var height := cap
		var width := 0.0
		_top.set_keys([], cap)
		if kind == "move" and not pad and not touch:
			# Each player's four keys as on the keyboard: the first over the middle of the other three.
			var top: Array = []
			var bottom: Array = []
			for cluster in _clusters(list):
				if not bottom.is_empty():
					top.append("")
					bottom.append("")
				top.append_array(["", cluster[0], ""])
				bottom.append_array(cluster.slice(1))
			_top.set_keys(top, cap, cell)
			_bottom.set_keys(bottom, cap, cell)
			height = cap * 2.1
			width = _bottom.size.x
			_top.position.x = _glyph
			_top_y = 0.0
			_bottom_y = cap * 1.1
		else:
			_bottom.set_keys(list, cap, cell if list.size() > 1 and not touch else 0.0)
			width = _bottom.size.x
			_bottom_y = 0.0
		_bottom.position.x = _glyph
		var inner := maxf(height, 66.0 * unit if _glyph > 0.0 else 0.0)
		var drop := (inner - height) * 0.5
		_top_y += drop
		_bottom_y += drop
		_glyph_centre = Vector2(_glyph * 0.5, inner * 0.5)
		_extent = Vector2(_glyph + width, inner)
		return _extent

	func _down(key: String) -> bool:
		return KEYCODES.has(key) and Input.is_physical_key_pressed(KEYCODES[key])

	## The players' runs of keys in a list ("" between two players).
	static func _clusters(list: Array) -> Array:
		var result: Array = [[]]
		for key: Variant in list:
			if str(key) == "": result.append([])
			else: (result[-1] as Array).append(str(key))
		return result.filter(func(cluster: Array) -> bool: return cluster.size() == 4)

	func _draw() -> void:
		if _glyph <= 0.0: return
		var at := _glyph_centre + Vector2(0.0, _bob)
		var unit := _unit
		var sway := sin(clock * 2.6 + phase)
		var chip := StyleBoxFlat.new()
		chip.bg_color = HudComic.PLATE
		chip.set_corner_radius_all(int(20.0 * unit))
		chip.corner_detail = 10
		chip.anti_aliasing = true
		var reach := Vector2(_glyph, _glyph) * 0.46
		draw_style_box(chip, Rect2(at - reach, reach * 2.0))
		if kind == "tilt":
			draw_set_transform(at, deg_to_rad(-24.0 * sway), Vector2.ONE)
			_painting(unit)
			draw_set_transform(at, 0.0, Vector2.ONE)
			for side in [-1.0, 1.0]:
				_arc_arrow(PI * 0.5 + 0.55 if side < 0.0 else -PI * 0.5 + 0.55, unit)
		else:
			draw_set_transform(at + Vector2(0, sway * 7.0 * unit), 0.0, Vector2.ONE)
			_painting(unit)
			draw_set_transform(at, 0.0, Vector2.ONE)
			_triangle(Vector2(0, -34.0) * unit, Vector2(8, -22.0) * unit, Vector2(-8, -22.0) * unit)
			_triangle(Vector2(0, 34.0) * unit, Vector2(8, 22.0) * unit, Vector2(-8, 22.0) * unit)
		draw_set_transform(Vector2.ZERO)

	## A little framed painting (the carried item): white frame, accent canvas, flat.
	func _painting(unit: float) -> void:
		var rect := Rect2(Vector2(-22.0, -12.0) * unit, Vector2(44.0, 24.0) * unit)
		draw_rect(rect, Ui.WHITE)
		draw_rect(rect.grow(-4.0 * unit), Ui.ACCENT)

	func _arc_arrow(arc_from: float, unit: float) -> void:
		var radius := 29.0 * unit
		draw_arc(Vector2.ZERO, radius, arc_from, arc_from + 1.0, 10, Ui.WHITE, 3.4 * unit, true)
		var tip := Vector2.from_angle(arc_from + 1.0) * radius
		var side := Vector2.from_angle(arc_from + 1.0 + PI * 0.5) * 6.0 * unit
		draw_colored_polygon(PackedVector2Array([tip + side, tip - side, tip + Vector2.from_angle(arc_from + 1.0) * 9.0 * unit]), Ui.WHITE)

	func _triangle(a: Vector2, b: Vector2, c: Vector2) -> void:
		draw_colored_polygon(PackedVector2Array([a, b, c]), Ui.WHITE)

# ================================================================== lifecycle

func _ready() -> void:
	layer = 20
	clock_view = Parts.Clock.new()
	clock_view.name = "RunClock"
	retry = RetryPlate.new()
	retry.name = "RetryPlate"
	add_child(clock_view)
	retry.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(retry)
	bubbles = CastBubbles.new()
	bubbles.name = "CastBubbles"
	add_child(bubbles)
	announcer = CastAnnouncer.new()
	announcer.name = "CastAnnouncer"
	add_child(announcer)
	visibility_changed.connect(func() -> void: if not visible: announcer.forget_level())
	visibility_changed.connect(func() -> void:
		if visible: clock_view.shown = 0.0 # the clock slides in each time the round HUD appears
	)
	for seat in 2:
		var hints := {}
		var index := 0
		for kind: String in KINDS:
			var view := SignView.new(kind, hint_keys(kind, seat), PAD_KEYS[kind])
			view.name = "Sign" + kind.capitalize() + ("" if seat == 0 else "2")
			view.phase = float(index + seat * 3) * 1.7
			view.touch_keys = TOUCH_KEYS[kind]
			view.size = Vector2(10, 10)
			add_child(view)
			hints[kind] = view
			index += 1
		seat_signs.append(hints)
	signs = seat_signs[0]

## The keyboard input mode of the running shell (game/game_input.gd: 2 = two players on one keyboard), 0 without one.
func input_mode() -> int:
	if simulation == null or not is_instance_valid(simulation): return 0
	var source = simulation.get("local_input")
	return int(source.mode) if source != null else 0

## Two views side by side (game/split_views.gd), one per local player.
func split_active() -> bool:
	if simulation == null or not is_instance_valid(simulation): return false
	var views = simulation.get("local_views")
	return views != null and bool(views.active)

## The keyboard keys a view's hint shows. Two views: each player's own (in modes 0 and 1 the second view's player is on a
## pad: no keys). One view: the keyboard player's, or with two keyboard players the first's, a gap, then the second's.
func hint_keys(kind: String, seat := 0) -> Array:
	var hints: Dictionary = GameInput.KEY_HINTS
	if input_mode() != 2: return (hints.one as Dictionary).get(kind, []) if seat == 0 else []
	if split_active(): return (hints[["first", "second"][seat]] as Dictionary).get(kind, [])
	if seat == 1: return []
	return ((hints.first as Dictionary).get(kind, []) as Array) + [""] + ((hints.second as Dictionary).get(kind, []) as Array)

## The name `kind` is learned under for a view's player.
static func taught_key(kind: String, seat: int) -> String:
	return kind if seat == 0 else kind + "@2"

## The devices that drive a view's player: with two views the shell's seat sources (game/game_input.gd seat_sources), with
## one view the keyboard and every pad.
func _seat_devices(seat: int) -> Array:
	if not split_active(): return [GameInput.KEYBOARD] + Array(Input.get_connected_joypads()) if seat == 0 else []
	var sources: Array = simulation.local_input.seat_sources(simulation.connected_pads())
	return sources[seat] if seat < sources.size() else []

## Is a key (or the pad's stick or button) of this hint down for this view's player?
func _hint_down(kind: String, seat := 0) -> bool:
	for key: Variant in hint_keys(kind, seat):
		if KEYCODES.has(str(key)) and Input.is_physical_key_pressed(KEYCODES[str(key)]): return true
	for device: Variant in _seat_devices(seat):
		var pad := int(device)
		if pad < 0: continue
		if kind == "move" and Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)).length() > 0.5: return true
		if kind == "jump" and Input.is_joy_button_pressed(pad, JOY_BUTTON_A): return true
		if kind == "grab" and Input.is_joy_button_pressed(pad, JOY_BUTTON_X): return true
	return false

var _keys_sig := ""
## Re-reads every hint's keys when the input mode or the views change (the shell configures them when a job starts).
func _sync_keys() -> void:
	var sig := "%d|%s" % [input_mode(), split_active()]
	if sig == _keys_sig: return
	_keys_sig = sig
	for seat in seat_signs.size():
		for kind: String in seat_signs[seat]:
			var view: SignView = seat_signs[seat][kind]
			view.keys = hint_keys(kind, seat)
			view.pad_only = seat == 1 and input_mode() != 2

static func time_text(seconds: float) -> String:
	return HudComic.clock_text(maxi(int(seconds), 0))

func update_from_state(state: Dictionary) -> void:
	var second := maxi(int(float(state.get("elapsed_seconds", 0))), 0)
	# A level run counts its total: the cleared levels (match.run.base) plus the level being played (not again while its card is up).
	var match_state: Variant = state.get("match")
	if match_state is Dictionary and match_state.get("run") is Dictionary:
		var run: Dictionary = match_state.run
		second = maxi(int(float(run.get("base", 0.0)) + (0.0 if bool(run.get("clearing", false)) else float(state.get("elapsed_seconds", 0)))), 0)
	if second != previous_second:
		previous_second = second
		timer_text = HudComic.clock_text(second)
	clock_view.seconds = second
	clock_view.urgent = match_state is Dictionary and float(match_state.get("time_left", -1.0)) >= 0.0
	breaks = int(state.get("breaks", 0))
	balloon_mode = str(state.get("play_mode", "carry")) == "balloon"
	clock_view.sub = ("%d POP%s" % [breaks, "" if breaks == 1 else "S"]) if balloon_mode and breaks > 0 else ""
	var resets := int(state.get("resets", 0))
	if resets != previous_resets:
		previous_resets = resets
		round_seconds = 0.0
		need = {"tilt": 0.0, "lift": 0.0}
	failed = bool(state.get("death_ui_visible", false)) or bool(state.get("broken", false))
	playing = bool(state.get("playing", true)) and not bool(state.get("won", false)) and not failed
	roll = float(state.get("roll", 0.0))
	lift = float(state.get("height", 0.0))
	if bool(state.get("death_ui_visible", false)): retry.show_for(str(state.get("failure_kind", "")))
	else: retry.hide_plate()
	bubbles.simulation = simulation
	bubbles.observe(state)
	announcer.simulation = simulation
	announcer.observe(state)
	_layout()

# ================================================================== signs

func _process(dt: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(dt)
	_DevLap.lap("hud.p", _lap)

func _process_timed(dt: float) -> void:
	clock += dt
	var touch_on := TouchControls.touch_hints(get_tree())
	retry.touch = touch_on
	for hints: Dictionary in seat_signs:
		for view: SignView in hints.values(): view.touch = touch_on
	if playing and visible: round_seconds += dt
	_sync_keys()
	_poll_input(dt)
	_update_signs(dt)
	probe_clock += dt
	if probe_clock >= PROBE_PERIOD:
		probe_clock = 0.0
		_probe_painting()
	_layout()

func _poll_input(dt: float) -> void:
	if not playing or not visible: return # walking about in the lobby must not use up the round's hints
	var touch_pad = _touch_pad()
	for seat in (2 if split_active() else 1):
		var times: Dictionary = held[seat]
		for kind: String in ["move", "turn", "jump", "grab"]:
			var down := _hint_down(kind, seat)
			if seat == 0 and kind == "move" and touch_pad != null and touch_pad.stick.length() > 0.5: down = true
			if down: times[kind] = float(times.get(kind, 0.0)) + dt
		if float(times.get("move", 0.0)) >= MOVE_TAUGHT: taught[taught_key("move", seat)] = true
		if float(times.get("turn", 0.0)) >= 0.35: taught[taught_key("turn", seat)] = true
		if float(times.get("jump", 0.0)) > 0.0: taught[taught_key("jump", seat)] = true
		if balloon_mode and float(times.get("grab", 0.0)) > 0.0: taught[taught_key("grab", seat)] = true # the touch GRAB taps F too

func _update_signs(dt: float) -> void:
	for kind: String in ["tilt", "lift"]:
		need[kind] = NEED_HOLD if playing and visible and last_need[kind] and not balloon_mode else maxf(float(need[kind]) - dt, 0.0)
	var seats := 2 if split_active() else 1
	for seat in seat_signs.size():
		_update_seat(seat, dt, seat < seats)

## One view's hints: at most one at a time (the first wanted in KINDS order), each until that view's player used it.
func _update_seat(seat: int, dt: float, shown: bool) -> void:
	var views: Dictionary = seat_signs[seat]
	var base_roll: float = float(views.tilt.get_meta("base", 0.0))
	var base_lift: float = float(views.lift.get_meta("base", 0.0))
	var learned := func(kind: String) -> bool: return taught.has(taught_key(kind, seat))
	var want := {"move": false, "turn": false, "jump": false, "tilt": false, "lift": false, "grab": false}
	if playing and visible and shown:
		want.move = not learned.call("move") and round_seconds > 0.5
		# Turning exists only with two players on one keyboard (each looks with its own keys), after walking.
		want.turn = input_mode() == 2 and not learned.call("turn") and learned.call("move") and round_seconds > 1.5
		# Jump comes after walking has been learned (or after a long wait).
		want.jump = not learned.call("jump") and (learned.call("move") or round_seconds > 14.0) and round_seconds > 2.5
		want.grab = balloon_mode and not learned.call("grab") and learned.call("jump") and round_seconds > 6.0
		for kind: String in ["tilt", "lift"]:
			want[kind] = not learned.call(kind) and float(need[kind]) > 0.0
		# Using the controls teaches them: a held key, or a clear change of roll / height.
		var touch_pad = _touch_pad() if seat == 0 else null
		if want.tilt and touch_pad != null and (touch_pad.tilt_left or touch_pad.tilt_right): views.tilt.set_meta("used", float(views.tilt.get_meta("used", 0.0)) + dt)
		elif want.tilt and (absf(roll - base_roll) > deg_to_rad(15.0) or _hint_down("tilt", seat) or (seat == 0 and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)))):
			views.tilt.set_meta("used", float(views.tilt.get_meta("used", 0.0)) + dt)
		if want.lift and touch_pad != null and (touch_pad.lift_up or touch_pad.lift_down): views.lift.set_meta("used", float(views.lift.get_meta("used", 0.0)) + dt)
		elif want.lift and (absf(lift - base_lift) > 0.12 or _hint_down("lift", seat)):
			views.lift.set_meta("used", float(views.lift.get_meta("used", 0.0)) + dt)
		for kind: String in ["tilt", "lift"]:
			if float(views[kind].get_meta("used", 0.0)) > 0.35:
				taught[taught_key(kind, seat)] = true
				want[kind] = false
	if shown:
		for kind: String in forced:
			if forced[kind]: want[kind] = true
	var priority := ""
	for kind: String in KINDS:
		if want[kind] and priority == "": priority = kind
	for kind: String in views:
		if not (shown and forced.get(kind, false)): want[kind] = kind == priority and not TouchControls.touch_hints(get_tree())
		var view: SignView = views[kind]
		if want[kind] and not view.wanted:
			view.set_meta("base", roll if kind == "tilt" else lift)
		view.wanted = want[kind]

## The running touch overlay (the shell's `touch`) while it is shown, else null.
func _touch_pad() -> Node:
	if simulation == null or not is_instance_valid(simulation): return null
	var pad = simulation.get("touch")
	return pad if pad != null and is_instance_valid(pad) and pad.is_active() else null

## Would the painting break within a step or two at the pose it has now, and would a tilted or lifted one clear it?
func _probe_painting() -> void:
	last_need = {"tilt": false, "lift": false}
	blocked_ahead = false
	probe_speed = 0.0
	if not playing or not visible or balloon_mode or simulation == null or not is_instance_valid(simulation): return
	var painting = simulation.get("painting")
	if painting == null or not is_instance_valid(painting) or painting.broken or not painting.is_inside_tree(): return
	var actors: Array = simulation.get("actors") if simulation.get("actors") is Array else []
	if actors.size() < 2: return
	var first := Vector3(actors[0].velocity.x, 0.0, actors[0].velocity.z)
	var second := Vector3(actors[1].velocity.x, 0.0, actors[1].velocity.z)
	var velocity := first if first.length() >= second.length() else second
	probe_speed = velocity.length()
	if velocity.length() < 0.5: return
	var result := probe_pose(painting, painting.global_transform, velocity.normalized(), float(painting.height))
	blocked_ahead = result.blocked
	last_need = {"tilt": result.tilt, "lift": result.lift}

## Would a painting at `here`, moving along `heading`, break within a step or two, and would a tilted (+-80 deg) or
## lifted/lowered (+-0.45 m) one clear that spot?
func probe_pose(painting: Node, here: Transform3D, heading: Vector3, current_offset: float) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = painting.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = PaintingScript.BREAK_SIZE + Vector3.ONE * 0.2
	var axis := here.basis.x.normalized()
	var base_up := Vector3.UP.cross(axis)
	if base_up.length_squared() < 0.001: base_up = Vector3.FORWARD
	base_up = base_up.normalized()
	var result := {"blocked": false, "tilt": false, "lift": false}
	for distance: float in [0.6, 1.5]:
		var step := heading * distance
		if _blocked(space, shape, Transform3D(here.basis, here.origin + step)):
			result.blocked = true
			for angle: float in [TILT_DEGREES, -TILT_DEGREES]:
				var up := base_up.rotated(axis, deg_to_rad(angle))
				result.tilt = result.tilt or not _blocked(space, shape, Transform3D(Basis(axis, up, axis.cross(up)).orthonormalized(), here.origin + step))
			for target: float in [LIFT_METERS, -LIFT_METERS]:
				result.lift = result.lift or not _blocked(space, shape, Transform3D(here.basis, here.origin + step + Vector3.UP * (target - current_offset)))
			break
	return result

func _blocked(space: PhysicsDirectSpaceState3D, shape: BoxShape3D, at: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at
	query.collision_mask = PaintingScript.BREAK_LAYER
	return not space.intersect_shape(query, 1).is_empty()

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var unit := clampf(viewport.y / 720.0, 0.72, 2.4)
	clock_view.fit(unit)
	# Each view's visible hints sit in a row in its lower outer corner (bottom left; the right view's bottom right), clear of
	# the first-person hands and the painting in the lower middle. Hidden ones take no room.
	var split := split_active()
	var margin := 28.0 * unit
	var gap := 18.0 * unit
	for seat in seat_signs.size():
		var visible_signs: Array = []
		for kind: String in seat_signs[seat]:
			if seat_signs[seat][kind].visible: visible_signs.append(seat_signs[seat][kind])
		if visible_signs.is_empty(): continue
		var total := -gap
		for view: SignView in visible_signs: total += view.plate_size(unit).x + gap
		var right := split and seat == 1
		var x := viewport.x - margin - total if right else margin
		for view: SignView in visible_signs:
			var plate := view.plate_size(unit)
			view.position = Vector2(x, viewport.y - margin - plate.y)
			view.size = plate
			x += plate.x + gap

func force_sign(kind: String, on := true) -> void:
	## Dev/proof hook: show a sign regardless of the world.
	forced[kind] = on

func probe() -> Dictionary:
	return {"timer": timer_text, "timer_visible": visible and clock_view.visible,
		"dead_visible": visible and retry.shown, "broken": breaks,
		"signs": signs.keys().filter(func(kind: String) -> bool: return signs[kind].visible),
		"signs_second": (seat_signs[1] as Dictionary).keys().filter(func(kind: String) -> bool: return seat_signs[1][kind].visible) if seat_signs.size() > 1 else [],
		"need": last_need.duplicate(), "taught": taught.keys(), "blocked_ahead": blocked_ahead, "speed": probe_speed,
		"touch_hints": retry.touch}
