extends CanvasLayer
const _DevLap := preload("res://dev_env.gd")
const DevEnv := preload("res://dev_env.gd")
## Touchscreen controls for FRIENDS (phones, tablets, `--touch` on a desktop).
##
## The overlay is only a different way to produce the keyboard/mouse inputs: it never changes
## gameplay. Jump (Space), Retry (R) and Menu (Esc) are synthetic key events that travel the same
## `Viewport` input path as the keyboard. Walking, tilting the glass, lifting it and looking
## around are read by run.gd from this node's state at the places where it reads WASD, the mouse
## buttons, the wheel and the mouse motion, so the local game, the online client and the
## authority protocol see exactly the same commands as for a keyboard player.
##
## Look (clean, like the HUD): every button is a flat white keycap with a hairline (the accent while held) and its caption
## in the display type, the walk stick is a translucent dark disc with a white knob, the hint sits on the HUD's dark chip.
## Pictograms are flat shapes, never Unicode arrows.
##
## Layout (design canvas 1280x720, safe-area aware): floating left stick = walk; any other
## touch on the free part of the screen drags the camera; bottom right: JUMP, TILT left/right
## (the two mouse buttons) and LIFT/LOWER (the wheel); top right: MAP, RETRY and MENU.
##
## Hosts: run.gd (online client and local game) and solo/solo_main.gd (singleplayer, which renames
## the buttons: the hands GRAB, the ARMS rise and lower, HOLD locks both hands like F). MAP (M) and
## HOLD (F) are optional buttons a host switches on with set_optional(). GRAB (F, the same key as HOLD) is the balloon
## round's: pick up a player, throw them; it sits where TILT is in a carry round.
const ComicText = preload("res://client/comic_text.gd")
const HudComic = preload("res://client/hud_comic.gd")
const Ui = preload("res://client/friends_ui.gd")
const DESIGN := Vector2(1280, 720)
const KEY_HOLD_SECONDS := 0.08
const STICK_RADIUS := 104.0
const STICK_DEADZONE := 0.14
const MODES := ["Auto", "On", "Off"]
const ITEM_ROLES := ["tilt_left", "tilt_right", "lift", "lower", "retry", "hold"]
const OPTIONAL_ROLES := ["map", "hold", "grab", "play", "dash", "item"]
const GROUP := &"friends_touch_controls"
## Settings > Display "Touch controls" (Auto: phones and tablets always, a desktop touchscreen
## once it is actually touched) and Settings "Touch look speed". Saved by settings.gd.
static var mode := "Auto"
static var look_sensitivity := 1.0
## The device the player used last: "keyboard" (keys and mouse) or "pad". The lobby's prompt names the key of that one (match_presenter.gd input_kind).
static var last_device := "keyboard"

## True while a touch overlay should be offered to this process at all.
var _touch_seen := false
var _context := false
var _surface: Control
var _fingers := {} # pointer index -> {"role": String, "origin": Vector2, "pos": Vector2}
var _rects := {}
var _jump := {"c": Vector2.ZERO, "r": 70.0}
var _stick_zone := Rect2()
var _stick_ghost := Vector2.ZERO
var _insets := Vector4.ZERO
var _look := Vector2.ZERO
var _held_keys := {} # keycode -> true while this overlay holds the synthetic key down
var _key_releases := {} # keycode -> remaining seconds of a tapped key
var _hint_until := 0
var _first_active := true
var _glass := true ## Glass controls (tilt, lift, retry) only exist in a round; the lobby has no glass.
var _focused := true
var stick := Vector2.ZERO ## Screen-space walk vector (x right, y down), dead zone removed, length <= 1.
var tilt_left := false ## Same as holding the left mouse button.
var tilt_right := false ## Same as holding the right mouse button.
var lift_up := false ## Same as scrolling the wheel up while held.
var lift_down := false
## Button captions. A host may rename them (singleplayer: GRAB, ARMS, HOLD).
var labels := {"tilt_left": "TILT", "tilt_right": "TILT", "lift": "LIFT", "lower": "LOWER", "retry": "RETRY", "menu": "MENU", "map": "MAP", "hold": "HOLD", "grab": "GRAB", "play": "PLAY", "dash": "DASH"}
## Draw the tipping-painting pictogram on the TILT buttons (off when they mean something else).
var tilt_glyphs := true
var _optional := {"map": false, "hold": false, "grab": false, "play": false, "dash": false, "item": false}
var item_lab := false ## the item lab is on: the ITEM button is always there, a long press hands out the next item or event (keys 1-7, docs/items.md)
var _item_down_at := 0
var _item_cycle := 0
var item_kind := -1 ## the item the ITEM button shows (modes/show/items/catalog.gd KINDS index), set by the shell with set_optional("item")
var _round_buttons := false ## a stage round: the jump button is a dark round disc and there is no hint text
var _pigeon := false ## GHOST PIGEON: the player is a bird: JUMP (UP) climbs, DASH (DOWN) held dives, GRAB (COO) coos, the round ITEM button (DROP) drops (modes/show/pigeon/)
var _labels_before := {} ## the captions the pigeon's buttons replaced
const ROUND_DISC := Color("1b1f26") ## the stage round's button: a flat disc with a grey ring
const ROUND_RING := Color("8f929a")
var _lit := {} # role -> true: a toggle that is on (singleplayer HOLD)
var _paused := false
var _pads := {} # role -> Pad (a keycap with its pictogram), a child of _surface
var _walk_word: Control
var _hint: Label
## A RETRY key the HUD draws itself (the CRACK! / SPLASH! plate) is a real button on touch: its screen rectangle, empty when none.
var _retry_target := Rect2()

static func forced() -> int:
	# --touch: always; --no-touch: never; otherwise the saved setting decides.
	var args := DevEnv.user_args()
	if "--touch" in args: return 1
	if "--no-touch" in args: return -1
	return 0

static func is_phone() -> bool:
	return OS.has_feature("mobile")

## True while any overlay in this tree is shown (a round is being played by touch).
static func showing(tree: SceneTree) -> bool:
	if tree == null: return false
	for node in tree.get_nodes_in_group(GROUP):
		if node.is_active(): return true
	return false

## Keyboard hint caps (Enter / R Ready, M Close map, W A S D signs...) mean nothing on a phone:
## true when they should show touch wording or be hidden.
static func touch_hints(tree: SceneTree) -> bool:
	return touch_ui() or showing(tree)

## Menus follow the same switch: on a phone, `--touch` or Touch controls "On" every button grows
## to a thumb-sized target (see fit_ui). A desktop never changes.
static func touch_ui() -> bool:
	var force := forced()
	if force != 0: return force > 0
	return is_phone() or mode == "On"

const MIN_BUTTON_HEIGHT := 76.0 ## design units: 7 mm on a 6.1" 1080x2400 phone, 7.4 mm on a 6.8" 1344x2992 one
const MIN_SLIDER_HEIGHT := 64.0
static var _fit_connected := false

## Grows every tappable control the menus create to a thumb-sized target. Idempotent, no-op on a desktop.
static func fit_ui(tree: SceneTree) -> void:
	if _fit_connected or not touch_ui(): return
	_fit_connected = true
	tree.node_added.connect(func(node: Node) -> void:
		if node is BaseButton or node is Range: _fit_control.call_deferred(node))

static func _fit_control(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or control.mouse_filter == Control.MOUSE_FILTER_IGNORE: return
	var minimum := MIN_SLIDER_HEIGHT if control is Range else MIN_BUTTON_HEIGHT
	if control.size.y >= minimum - 0.5 and control.custom_minimum_size.y >= minimum - 0.5: return
	if control.get_parent() is Container:
		control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, minimum)
	else:
		var extra := minimum - control.size.y
		if extra <= 0.0: return
		control.position.y -= extra * 0.5
		control.size.y = minimum

## Whether the platform / settings allow the overlay (the host adds "a round is running").
func allowed() -> bool:
	var force := forced()
	if force != 0: return force > 0
	match mode:
		"On": return true
		"Off": return false
	return is_phone() or _touch_seen

func _ready() -> void:
	layer = 8
	add_to_group(GROUP)
	# Releases of tapped keys and the pause gate must keep running while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_paused = get_tree().paused
	_surface = Control.new()
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(func() -> void: _draw_controls(_surface))
	add_child(_surface)
	_build_art()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_surface.hide()

## A paused tree (pause menu, local route map) never plays: the overlay hides until it resumes.
func is_active() -> bool:
	return _context and _focused and not _paused and allowed()

## The host (run.gd) says whether a round/lobby is being played with the camera under input.
func set_context(on: bool) -> void:
	if on == _context: return
	_context = on
	_refresh()

func _refresh() -> void:
	var active := is_active()
	if not active: release_all()
	elif _first_active:
		_first_active = false
		_hint_until = Time.get_ticks_msec() + 7000
	if _surface != null:
		_surface.visible = active
		_surface.queue_redraw()

## The lobby is free walking without glass: only walk, look, jump and MENU stay.
func set_glass_controls(on: bool) -> void:
	if on == _glass: return
	_glass = on
	if not on:
		for index in _fingers.keys():
			if _fingers[index].role in ITEM_ROLES: _release_finger(index)
	if _surface != null: _surface.queue_redraw()

## MAP (M), HOLD (F), GRAB (F), PLAY (Enter) and DASH (Shift) exist only where the host has them (the route map, singleplayer's hands, grabbing rounds, a ready lobby circle, a mode with a dash).
func set_optional(role: String, on: bool) -> void:
	if not role in OPTIONAL_ROLES or bool(_optional[role]) == on: return
	_optional[role] = on
	if role == "play": _lit[role] = on # the ready circle's key glows in the accent
	if not on:
		for index in _fingers.keys():
			if _fingers[index].role == role: _release_finger(index)
	if _surface != null: _surface.queue_redraw()

## GHOST PIGEON: the buttons are the bird's while `on` (set by the shell every frame): UP, DOWN, COO and the round DROP button over COO.
func set_pigeon(on: bool) -> void:
	if on == _pigeon: return
	_pigeon = on
	if on:
		_labels_before = labels.duplicate()
		labels["jump"] = "UP"
		labels["dash"] = "DOWN"
		labels["grab"] = "COO"
		set_optional("item", true)
	else:
		labels = _labels_before.duplicate()
		set_optional("item", item_kind >= 0 or item_lab)
		_set_key(KEY_SHIFT, false)
	_sync_art()
	if _surface != null: _surface.queue_redraw()

## The show's ITEM button: shown while the player holds an item (`kind`: modes/show/items/catalog.gd KINDS index, -1 none), wearing its icon.
func set_item(kind: int, lab := false) -> void:
	if _pigeon: return # the round ITEM button is the DROP button
	var changed := kind != item_kind or lab != item_lab
	item_lab = lab
	item_kind = kind
	set_optional("item", kind >= 0 or item_lab)
	if changed and _surface != null: _surface.queue_redraw()

func has_optional(role: String) -> bool:
	return bool(_optional.get(role, false))

## A stage round (tile stage levels): the jump key is a flat dark round disc (no caption, no keycap) and the hint "Drag here to look around" stays away; the phone shows the stick and that one round button.
func set_round_buttons(on: bool) -> void:
	if on == _round_buttons: return
	_round_buttons = on
	if _surface != null: _surface.queue_redraw()
	_sync_art()

## Show a toggle as on (HOLD while both hands are locked).
func set_lit(role: String, on: bool) -> void:
	if bool(_lit.get(role, false)) == on: return
	_lit[role] = on
	if _surface != null: _surface.queue_redraw()

func take_look() -> Vector2:
	var value := _look
	_look = Vector2.ZERO
	return value

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		_refresh()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true
		_refresh()

func _exit_tree() -> void:
	release_all()

# ------------------------------------------------------------------ layout

func _safe_insets() -> Vector4:
	var fake := PackedStringArray()
	for arg in DevEnv.user_args():
		if arg.begins_with("--touch-safe="): fake = arg.trim_prefix("--touch-safe=").split(",") # left,top,right,bottom design px
	if fake.size() == 4: return Vector4(float(fake[0]), float(fake[1]), float(fake[2]), float(fake[3]))
	if DisplayServer.get_name() == "headless": return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0 or win.distance_to(screen) > 4.0: return Vector4.ZERO
	# Stretch aspect is expand: no bars, the canvas grows past 1280x720 on the long axis and every pixel scales by k.
	var k := minf(win.x / DESIGN.x, win.y / DESIGN.y)
	return Vector4(maxf(safe.position.x, 0.0), maxf(safe.position.y, 0.0), maxf(screen.x - safe.end.x, 0.0), maxf(screen.y - safe.end.y, 0.0)) / k

## Live canvas size in design units (>= DESIGN under expand).
func _canvas() -> Vector2:
	var v := get_viewport()
	if v == null: return DESIGN
	var s := v.get_visible_rect().size
	return Vector2(maxf(s.x, DESIGN.x), maxf(s.y, DESIGN.y))

func _layout() -> void:
	release_all() # A rotation or resize must never leave a finger holding an action.
	_insets = _safe_insets()
	var margin := 30.0
	var left := _insets.x + margin
	var canvas := _canvas()
	var right := canvas.x - _insets.z - margin
	var top := _insets.y + 18.0
	var bottom := canvas.y - _insets.w - margin
	var radius := 74.0
	_jump = {"c": Vector2(right - radius, bottom - radius), "r": radius}
	var bw := 108.0
	var bh := 86.0
	var gap := 12.0
	var jump_centre: Vector2 = _jump.c
	var grid_x: float = _jump.c.x - radius - 20.0 - (2.0 * bw + gap)
	var big_button := Rect2(grid_x, bottom - bh - gap - 112.0, 2.0 * bw + gap, 112.0)
	_rects = {
		"lift": Rect2(grid_x, bottom - 2.0 * bh - gap, bw, bh),
		"lower": Rect2(grid_x + bw + gap, bottom - 2.0 * bh - gap, bw, bh),
		"tilt_left": Rect2(grid_x, bottom - bh, bw, bh),
		"tilt_right": Rect2(grid_x + bw + gap, bottom - bh, bw, bh),
		"menu": Rect2(right - 96.0, top, 96.0, 66.0),
		"retry": Rect2(right - 96.0 * 2.0 - 12.0, top, 96.0, 66.0),
		"map": Rect2(right - 96.0 * 3.0 - 24.0, top, 96.0, 66.0),
		"hold": Rect2(grid_x, bottom - 3.0 * bh - 2.0 * gap, 2.0 * bw + gap, bh),
		"grab": Rect2(grid_x + bw + gap, bottom - bh, bw, bh),
		"play": big_button, # the lobby's PLAY: a big key over GRAB, left of JUMP (the glass grid is not there in the lobby)
		"dash": Rect2(jump_centre.x - bw * 0.6, jump_centre.y - radius - gap - bh, bw * 1.2, bh), # a game with a dash (the show): over JUMP, under the right thumb
		"item": Rect2(grid_x + bw * 0.5 + gap - 4.0, bottom - bh - gap - 100.0, 100.0, 100.0), # the show's item slot: a round key over GRAB (it is drawn, not a keycap: _draw_controls)
	}
	_stick_ghost = Vector2(left + STICK_RADIUS + 14.0, bottom - STICK_RADIUS - 190.0)
	_stick_zone = Rect2(0.0, canvas.y * 0.34, canvas.x * 0.42, canvas.y * 0.66)
	_place_art()
	if _surface != null: _surface.queue_redraw()

## The HUD's RETRY key (shown after the glass breaks) taps like the top-right RETRY button; an empty rect takes it away.
func set_retry_target(rect: Rect2) -> void:
	_retry_target = rect

func retry_target() -> Rect2:
	return _retry_target

func region_rect(id: String) -> Rect2:
	return _rects.get(id, Rect2())

func region_ids() -> Array:
	return _rects.keys() + ["jump", "stick"]

func jump_circle() -> Dictionary:
	return _jump

func stick_zone() -> Rect2:
	return _stick_zone

# ------------------------------------------------------------------ pointers

func _process(delta: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(delta)
	_DevLap.lap("touch_controls.p", _lap)

func _process_timed(delta: float) -> void:
	var paused := get_tree().paused
	if paused != _paused:
		_paused = paused
		_refresh()
	if _surface != null and _surface.visible:
		_sync_art()
		if Time.get_ticks_msec() < _hint_until + 200: _surface.queue_redraw()
	for code in _key_releases.keys():
		_key_releases[code] = float(_key_releases[code]) - delta
		if float(_key_releases[code]) <= 0.0:
			_key_releases.erase(code)
			_set_key(code, false)

func _watch_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5): last_device = "pad"
	elif (event is InputEventKey or event is InputEventMouseButton) and event.device != InputEvent.DEVICE_ID_EMULATION: last_device = "keyboard"
	# Auto mode on a desktop touchscreen: the overlay follows the last device used.
	if is_phone() or mode != "Auto" or forced() != 0: return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not _touch_seen:
			_touch_seen = true
			_refresh()
	elif (event is InputEventKey or event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventJoypadButton) and event.device != InputEvent.DEVICE_ID_EMULATION:
		if _touch_seen:
			_touch_seen = false
			_refresh()

func _input(event: InputEvent) -> void:
	_watch_device(event)
	if not is_active(): return
	var phase := ""
	var index := 0
	var position := Vector2.ZERO
	var relative := Vector2.ZERO
	if event is InputEventScreenTouch:
		phase = "down" if event.pressed and not event.canceled else "up"
		index = event.index
		position = event.position
	elif event is InputEventScreenDrag:
		phase = "move"
		index = event.index
		position = event.position
		relative = event.relative
	elif forced() > 0 and not is_phone() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		# `--touch` on a desktop: the real mouse stands in for one finger so the layout can be tried.
		phase = "down" if event.pressed else "up"
		index = 1000
		position = event.position
	elif forced() > 0 and not is_phone() and event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _fingers.has(1000):
		phase = "move"
		index = 1000
		position = event.position
		relative = event.relative
	if phase.is_empty(): return
	match phase:
		"down":
			if _fingers.has(index): _release_finger(index)
			var role := _role_at(position)
			if role.is_empty(): return
			_fingers[index] = {"role": role, "origin": position, "pos": position}
			_apply_role(role, true, index)
			get_viewport().set_input_as_handled()
		"move":
			if not _fingers.has(index): return
			var finger: Dictionary = _fingers[index]
			finger.pos = position
			if finger.role == "look": _look += relative
			elif finger.role == "stick": _update_stick(finger)
			get_viewport().set_input_as_handled()
		"up":
			if not _fingers.has(index): return
			_release_finger(index)
			get_viewport().set_input_as_handled()
	_surface.queue_redraw()

## A touch that lands on a menu, the READY button, Leave... belongs to that control, never to the game.
func _ui_blocked(point: Vector2) -> bool:
	for layer: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if layer == self or layer.layer <= self.layer or not layer.visible: continue
		for control: Control in layer.find_children("*", "Control", true, false):
			if not (control is BaseButton or control is Range or control is LineEdit) or control.mouse_filter == Control.MOUSE_FILTER_IGNORE or not control.is_visible_in_tree(): continue
			if (control.get_global_transform() * Rect2(Vector2.ZERO, control.size)).grow(4.0).has_point(point): return true
	return false

func _role_at(point: Vector2) -> String:
	if _ui_blocked(point): return ""
	if (point - Vector2(_jump.c)).length() <= float(_jump.r) + 10.0: return "jump"
	if _glass and _retry_target.size != Vector2.ZERO and _retry_target.has_point(point): return "retry"
	for id: String in _rects:
		if not _offered(id): continue
		if _rects[id].grow(8.0).has_point(point): return id
	if _stick_zone.has_point(point) and not _roles().has("stick"): return "stick"
	return "look"

## Whether a button is on screen now: glass buttons only in a round, MAP / HOLD only where the host has them.
func _offered(id: String) -> bool:
	if id in ITEM_ROLES and not _glass: return false
	if id in OPTIONAL_ROLES and not has_optional(id): return false
	return true

func _roles() -> Array:
	var roles := []
	for finger: Dictionary in _fingers.values(): roles.append(finger.role)
	return roles

func _apply_role(role: String, down: bool, _index: int) -> void:
	match role:
		"jump": _set_key(KEY_SPACE, down)
		"tilt_left": tilt_left = down
		"tilt_right": tilt_right = down
		"lift": lift_up = down
		"lower": lift_down = down
		"retry": if down: _tap_key(KEY_R)
		"menu": if down: _tap_key(KEY_ESCAPE)
		"map": if down: _tap_key(KEY_M)
		"hold", "grab": if down: _tap_key(KEY_F)
		"dash":
			if _pigeon: _set_key(KEY_SHIFT, down) # DOWN is held, as the keyboard's SHIFT is (game/game_input.gd dash_held)
			elif down: _tap_key(KEY_SHIFT) # the keyboard's dash key (game/game_input.gd)
		"item": # the keyboard's ITEM key (game/game_input.gd); with the item lab on a long press (0.5 s) cycles through the items and events instead (the keys 1-7)
			if _pigeon:
				if down: _tap_key(KEY_E) # DROP: the keyboard's ITEM key
			elif not item_lab:
				if down: _tap_key(KEY_E)
			elif down: _item_down_at = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _item_down_at >= 500:
				_item_cycle = _item_cycle % 7 + 1
				_tap_key((KEY_0 + _item_cycle) as Key)
			else: _tap_key(KEY_E)
		"play": if down: _tap_key(KEY_ENTER) # the same key as the keyboard's PLAY: client/main.gd and client/local_level_flow.gd read it
		"stick":
			if not down: stick = Vector2.ZERO
			else: _update_stick(_fingers[_index])

func _update_stick(finger: Dictionary) -> void:
	var raw: Vector2 = (finger.pos - finger.origin) / STICK_RADIUS
	var length := raw.length()
	if length > 1.0:
		finger.origin = finger.pos - raw / length * STICK_RADIUS # the base follows a thumb that overshoots
		length = 1.0
		raw = raw.normalized()
	stick = Vector2.ZERO if length < STICK_DEADZONE else raw / length * ((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))

func _release_finger(index: int) -> void:
	if not _fingers.has(index): return
	var role: String = _fingers[index].role
	_fingers.erase(index)
	_apply_role(role, false, index)
	if _surface != null: _surface.queue_redraw()

func release_all() -> void:
	for index in _fingers.keys(): _release_finger(index)
	_fingers.clear()
	stick = Vector2.ZERO
	tilt_left = false
	tilt_right = false
	lift_up = false
	lift_down = false
	_look = Vector2.ZERO
	for code in _held_keys.keys(): _set_key(code, false)
	for code in _key_releases.keys():
		_key_releases.erase(code)
		_set_key(code, false)
	if _surface != null: _surface.queue_redraw()

# ------------------------------------------------------------------ synthetic keys

func _set_key(code: Key, down: bool) -> void:
	if down == _held_keys.has(code): return
	if down: _held_keys[code] = true
	else: _held_keys.erase(code)
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.device = InputEvent.DEVICE_ID_EMULATION # not a person at a keyboard: never switches the overlay off
	Input.parse_input_event(event)

func _tap_key(code: Key) -> void:
	_set_key(code, true)
	_key_releases[code] = KEY_HOLD_SECONDS

# ------------------------------------------------------------------ drawing

## Pictogram on a keycap, drawn after the key so it lies on the key's top face: flat red shapes with an ink outline.
class Glyph extends Control:
	var kind := ""
	var key: Control # the ComicText.KeyCap under it (its press dip moves the glyph too)
	var _dip := 0.0

	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		var dip: float = float(key.get("key_height")) * 0.09 * float(key.get("held"))
		if absf(dip - _dip) > 0.01:
			_dip = dip
			queue_redraw()

	## Flat ink pictogram (the keycap's face is white and turns the accent while held).
	const FILL := Color("15161a")

	func _shape(points: PackedVector2Array, _halo: float) -> void:
		draw_colored_polygon(points, FILL)

	func _arrow(center: Vector2, direction: Vector2, extent: float, halo: float) -> void:
		var side := Vector2(-direction.y, direction.x)
		_shape(PackedVector2Array([center + direction * extent, center - direction * extent * 0.7 + side * extent * 0.85, center - direction * extent * 0.7 - side * extent * 0.85]), halo)

	func _draw() -> void:
		if kind == "": return
		var unit := size.y / 86.0 # shapes are tuned on the 108x86 button
		var halo := 2.0 * unit
		var middle := Vector2(size.x * 0.5, size.y * 0.27 + _dip)
		match kind:
			"up": _arrow(middle, Vector2.UP, 13.0 * unit, halo)
			"down": _arrow(middle, Vector2.DOWN, 13.0 * unit, halo)
			"tilt_left", "tilt_right":
				var sign_value := -1.0 if kind == "tilt_left" else 1.0
				# A painting tipping towards the side the arrow points at.
				var tip := Vector2(sign_value * 20.0, -sign_value * 6.0) * unit
				var a := middle + Vector2(0, 1.0 * unit) - tip
				var b := middle + Vector2(0, 1.0 * unit) + tip
				draw_line(a, b, FILL, 4.0 * unit, true)
				_arrow(middle + Vector2(sign_value * 2.0, 12.0) * unit, Vector2(sign_value, 0.0), 8.5 * unit, halo)

## One touch button: a flat keycap with its caption in the display type (and a pictogram above it).
class Pad extends Control:
	var key: Control
	var glyph: Glyph
	var _box := Vector2(10, 10)
	var _kind := ""
	var _held := false
	var _lit := false

	func _init(caption: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		key = ComicText.keycap(caption, 60.0)
		key.set("rim", 0.022) # a soft dark rim: the white key must stand out of a bright frame
		add_child(key)
		glyph = Glyph.new()
		glyph.key = key
		add_child(glyph)

	func set_caption(text: String) -> void:
		if key.get("_label").text == text: return
		key.call("set_label", text)
		fit(_box, _kind)

	func fit(box: Vector2, kind: String) -> void:
		_box = box
		_kind = kind
		size = box
		glyph.kind = kind
		glyph.size = box
		# Caption under the pictogram, or centred on the face when there is none.
		key.call("fit", box, 0.18 if kind != "" else 0.3, 0.64 if kind != "" else 0.43)
		glyph.queue_redraw()

	func set_state(held: bool, lit: bool) -> void:
		if held != _held:
			_held = held
			key.call("set_held", held)
		if lit != _lit:
			_lit = lit
			key.call("set_lit", lit)

func _build_art() -> void:
	for role in ["lift", "lower", "tilt_left", "tilt_right", "retry", "menu", "map", "hold", "grab", "play", "dash", "jump"]:
		var pad := Pad.new(str(labels.get(role, "JUMP")))
		pad.name = "Pad_" + role
		_surface.add_child(pad)
		_pads[role] = pad
	_walk_word = HudComic.word("WALK", 24.0)
	_surface.add_child(_walk_word)
	_hint = HudComic.small("Drag here to look around", 22)
	_hint.modulate.a = 0.0
	_surface.add_child(_hint)

## The pictogram a button wears now ("" = caption only).
func _glyph_of(role: String) -> String:
	match role:
		"lift", "jump": return "up"
		"lower": return "down"
		"tilt_left", "tilt_right": return role if tilt_glyphs else ""
	return ""

func _pad_box(role: String) -> Rect2:
	if role == "jump":
		var r: float = _jump.r
		var box := Vector2(2.0 * r * 0.957, 2.0 * r) # the 1u key art's aspect
		return Rect2(Vector2(_jump.c) - box * 0.5, box)
	return _rects.get(role, Rect2())

func _place_art() -> void:
	if _pads.is_empty(): return
	for role: String in _pads:
		var box := _pad_box(role)
		var pad: Control = _pads[role]
		pad.position = box.position
		pad.call("fit", box.size, _glyph_of(role))
	_sync_art()

## Per-frame state of the child art: which buttons exist, their captions and pictograms, held / lit, the hint.
func _sync_art() -> void:
	if _pads.is_empty(): return
	for role: String in _pads:
		var pad: Control = _pads[role]
		var offered := (role == "jump" and not _round_buttons) or (role != "jump" and _offered(role))
		pad.visible = offered
		if not offered: continue
		pad.call("set_caption", str(labels.get(role, "JUMP")))
		var kind := _glyph_of(role)
		if pad.get("_kind") != kind: pad.call("fit", _pad_box(role).size, kind)
		pad.call("set_state", _holding(role), bool(_lit.get(role, false)))
	var stick_down := _roles().has("stick")
	_walk_word.visible = not stick_down
	_walk_word.modulate.a = 0.78
	_walk_word.size = _walk_word.custom_minimum_size
	_walk_word.position = _stick_ghost - _walk_word.size * 0.5
	var left := float(_hint_until - Time.get_ticks_msec())
	_hint.visible = left > -200.0 and _retry_target.size == Vector2.ZERO and not _round_buttons # CRACK! takes the middle of the screen; a stage round has no hint
	_hint.modulate.a = clampf((left + 200.0) / 400.0, 0.0, 1.0) if left < 200.0 else 1.0
	var cv := _canvas()
	_hint.position = Vector2(cv.x * 0.62, cv.y * 0.46) - _hint.get_combined_minimum_size() * 0.5 # below the round card and the GO lines, which take the top fifth

func _holding(role: String) -> bool:
	return _roles().has(role)

## Stick base: a flat translucent dark disc.
func _ring(c: Control, center: Vector2, radius: float, alpha: float) -> void:
	c.draw_circle(center, radius, Color(HudComic.PLATE, minf(alpha * 0.9, 0.6)), true, -1.0, true)

func _draw_controls(c: Control) -> void:
	# Stick: a ghost at its default place until a thumb lands; then the base sits under the thumb.
	var stick_finger := {}
	for finger: Dictionary in _fingers.values():
		if finger.role == "stick": stick_finger = finger
	var idle := stick_finger.is_empty()
	var base := _stick_ghost if idle else Vector2(stick_finger.origin)
	_ring(c, base, STICK_RADIUS, 0.36 if idle else 0.58)
	c.draw_arc(base, STICK_RADIUS * 0.62, 0.0, TAU, 56, Color(Ui.WHITE, 0.25 if idle else 0.4), 2.0, true)
	var knob := base + (Vector2.ZERO if idle else (Vector2(stick_finger.pos) - base).limit_length(STICK_RADIUS))
	# Knob: a flat white disc (the accent ring while a thumb holds it).
	var radius := 40.0
	var fade := 0.85 if idle else 1.0
	c.draw_circle(knob, radius, Color(Ui.WHITE, fade), true, -1.0, true)
	if not idle: c.draw_arc(knob, radius - 2.0, 0.0, TAU, 56, Ui.ACCENT, 4.0, true)
	if _pigeon: (load("res://modes/show/shared/pigeon/pigeon_icons.gd") as GDScript).call("touch_drop", c, _rects["item"], _holding("item")) # loaded here, not preloaded: it uses client/show_theme.gd, which preloads this file
	elif has_optional("item"): (load("res://modes/show/items/item_icons.gd") as GDScript).call("touch_button", c, _rects["item"], item_kind, _holding("item")) # loaded here, not preloaded: it uses client/show_theme.gd, which preloads this file
	if _round_buttons: # a stage round: the one button is a flat dark round disc with a white up arrow
		var held := _holding("jump")
		var disc: float = float(_jump.r) * 0.9
		c.draw_circle(_jump.c, disc, Color(ROUND_DISC, 0.72 if held else 0.55), true, -1.0, true)
		c.draw_arc(_jump.c, disc - 1.5, 0.0, TAU, 56, Ui.ACCENT if held else ROUND_RING, 3.0, true)
		var tip := Vector2(_jump.c) + Vector2(0.0, -disc * 0.34)
		c.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(disc * 0.34, disc * 0.5), tip + Vector2(-disc * 0.34, disc * 0.5)]), Color.WHITE)
