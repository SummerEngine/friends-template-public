extends RefCounted
## Local device sampling for the local role (one machine, one or two humans). The caller owns devices, cameras and gameplay.
## Modes: 0 keyboard + gamepad, 1 two gamepads, 2 both couriers on one keyboard (each its own first-person view):
##   player 1 WASD move, Q/E turn, Space jump, F grab, C/V tilt, Z/X lower/lift;
##   player 2 IJKL move, U/O turn, M (or Shift+Space) jump, N grab, comma/period tilt, H/Y lower/lift.
## sample() returns, per device and call: move (x right, y forward, |v| <= 1), look (right stick), turn (-1..1, keys, plus turns
## right), jumps (press edges since the last sample), options, restart (edges), roll (-1..1, plus = right button / E / right trigger),
## height (-1..1, up = wheel up / X / shoulder), grabs (GRAB press edges: F, the second keyboard player's N, pad X; the touch GRAB
## button taps F), dashes (DASH press edges: Shift, pad B or the right bumper, the touch DASH button taps Shift; on one keyboard
## C and comma, Shift being player 2's jump there) and items (ITEM press edges, the show's item slot: E, the pad's Y or left bumper, the touch ITEM button taps E; on one keyboard
## G and B). A game that has no dash ignores them (game_run.gd dash_enabled), a game without items ignores items (modes/show/items/).
const KEYBOARD := -1
const MISSING := -2
const KEYBOARD_TWO := -3
## The keyboard keys per action, as the HUD's hints show them (client/hud.gd): "one" is the keyboard player of modes 0 and 1,
## "first" and "second" are the two players of mode 2. Captions as printed on the keys. Keep in step with push_event() and
## sample() below.
const KEY_HINTS := {
	"one": {"move": ["W", "A", "S", "D"], "jump": ["SPACE"], "tilt": ["Q", "E"], "lift": ["Z", "X"], "grab": ["F"], "dash": ["SHIFT"], "item": ["E"]},
	"first": {"move": ["W", "A", "S", "D"], "turn": ["Q", "E"], "jump": ["SPACE"], "tilt": ["C", "V"], "lift": ["Z", "X"], "grab": ["F"], "dash": ["C"], "item": ["G"]},
	"second": {"move": ["I", "J", "K", "L"], "turn": ["U", "O"], "jump": ["M"], "tilt": [",", "."], "lift": ["H", "Y"], "grab": ["N"], "dash": [","], "item": ["B"]},
}
const DEAD_ZONE := 0.2
const LOOK_DEGREES := 2.5 ## degrees per rendered frame at full stick and sensitivity 1
const SHOULDER_HOLD := 0.05

var mode := 0
var _previous := {}
var _pending := {}
var _held := {}

func configure(input_mode: int) -> void:
	mode = clampi(input_mode, 0, 2)
	clear()

func clear() -> void:
	_previous.clear()
	_pending.clear()
	_held.clear()

## Devices that drive each seat (a seat may take several: keyboard and pad share seat 0 in the two-pad mode).
func seat_sources(connected: Array) -> Array:
	if mode == 2: return [[KEYBOARD], [KEYBOARD_TWO]]
	var pads := connected.duplicate()
	pads.sort()
	var first := int(pads[0]) if pads.size() > 0 else MISSING
	var second := int(pads[1]) if pads.size() > 1 else MISSING
	if mode == 0: return [[KEYBOARD], [first]]
	return [[KEYBOARD, first], [second]]

static func radial_deadzone(value: Vector2) -> Vector2:
	var length := value.length()
	return value / length * clampf((length - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0) if length > DEAD_ZONE else Vector2.ZERO

static func trigger(value: float) -> float:
	return clampf((value - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)

## Stick/key move in view space -> world XZ for a camera heading `yaw`.
static func world_move(move: Vector2, yaw: float) -> Vector2:
	var direction := Basis(Vector3.UP, yaw) * Vector3(move.x, 0.0, -move.y)
	return Vector2(direction.x, direction.z).limit_length(1.0)

## Right stick -> (yaw, pitch) change in radians for one rendered frame. `settings`: XSensitivity, YSensitivity, InvertX, InvertY.
static func look_delta(action: Vector2, settings := {}) -> Vector2:
	var x := -deg_to_rad(action.x * LOOK_DEGREES * float(settings.get("XSensitivity", 1.0))) * (-1.0 if bool(settings.get("InvertX", false)) else 1.0)
	var y := -deg_to_rad(action.y * LOOK_DEGREES * float(settings.get("YSensitivity", 1.0))) * (-1.0 if bool(settings.get("InvertY", false)) else 1.0)
	return Vector2(x, y)

## Key, pad and wheel edges between two samples.
func push_event(event: InputEvent) -> void:
	var device := MISSING
	var action := ""
	var pressed := false
	if event is InputEventKey and not event.echo:
		var keycode: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		pressed = event.pressed
		if mode == 2:
			if keycode == KEY_SPACE and not Input.is_physical_key_pressed(KEY_SHIFT):
				device = KEYBOARD
				action = "jump"
			elif keycode == KEY_M or (keycode == KEY_SPACE and Input.is_physical_key_pressed(KEY_SHIFT)):
				device = KEYBOARD_TWO
				action = "jump"
			elif keycode == KEY_C:
				device = KEYBOARD
				action = "dash"
			elif keycode == KEY_COMMA:
				device = KEYBOARD_TWO
				action = "dash"
			elif keycode == KEY_F:
				device = KEYBOARD
				action = "grab"
			elif keycode == KEY_N:
				device = KEYBOARD_TWO
				action = "grab"
			elif keycode == KEY_G:
				device = KEYBOARD
				action = "item"
			elif keycode == KEY_B:
				device = KEYBOARD_TWO
				action = "item"
			elif keycode == KEY_ESCAPE:
				device = KEYBOARD
				action = "options"
			elif keycode == KEY_R:
				device = KEYBOARD
				action = "restart"
			elif keycode >= KEY_1 and keycode <= KEY_7:
				var lab_two: Dictionary = _pending.get(KEYBOARD, {}) # the item lab on one keyboard for two: the number keys hand the first player an item or event
				lab_two["tests"] = keycode - KEY_0
				_pending[KEYBOARD] = lab_two
				return
		else:
			device = KEYBOARD
			if keycode == KEY_SPACE: action = "jump"
			elif keycode == KEY_SHIFT: action = "dash"
			elif keycode == KEY_F: action = "grab"
			elif keycode == KEY_E: action = "item"
			elif keycode == KEY_ESCAPE: action = "options"
			elif keycode == KEY_R: action = "restart"
			elif keycode >= KEY_1 and keycode <= KEY_7:
				var lab: Dictionary = _pending.get(KEYBOARD, {}) # the item lab (docs/items.md): 1-7 name an item or event; the game ignores it unless the lab is on
				lab["tests"] = keycode - KEY_0
				_pending[KEYBOARD] = lab
				return
	elif event is InputEventJoypadButton:
		device = event.device
		pressed = event.pressed
		if event.button_index == JOY_BUTTON_A: action = "jump"
		elif event.button_index == JOY_BUTTON_X: action = "grab"
		elif event.button_index == JOY_BUTTON_B or event.button_index == JOY_BUTTON_RIGHT_SHOULDER: action = "dash"
		elif event.button_index == JOY_BUTTON_Y: action = "restart"
		elif event.button_index == JOY_BUTTON_LEFT_SHOULDER: action = "item"
		elif event.button_index == JOY_BUTTON_START: action = "options"
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var pending: Dictionary = _pending.get(KEYBOARD, {})
			pending["wheel"] = float(pending.get("wheel", 0.0)) + (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			_pending[KEYBOARD] = pending
		return
	if action == "" or not pressed: return
	var key: Dictionary = _pending.get(device, {})
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y: key["items"] = int(key.get("items", 0)) + 1 # Y is RESTART and PLAY too: a round of the show only reads ITEM, the lobby only PLAY
	if action == "jump": key["jumps"] = int(key.get("jumps", 0)) + 1
	elif action == "grab": key["grabs"] = int(key.get("grabs", 0)) + 1
	elif action == "dash": key["dashes"] = int(key.get("dashes", 0)) + 1
	elif action == "item": key["items"] = int(key.get("items", 0)) + 1
	else: key[action] = true
	_pending[device] = key

func sample(device: int, delta: float) -> Dictionary:
	var result := {"move": Vector2.ZERO, "look": Vector2.ZERO, "turn": 0.0, "jumps": 0, "grabs": 0, "dashes": 0, "items": 0, "tests": 0, "options": false, "restart": false, "roll": 0.0, "height": 0.0, "jump_held": false, "dash_held": false}
	if device == MISSING: return result
	var pending: Dictionary = _pending.get(device, {})
	_pending.erase(device)
	if device == KEYBOARD or device == KEYBOARD_TWO:
		var second := device == KEYBOARD_TWO
		var key := func(code: int) -> bool: return Input.is_physical_key_pressed(code)
		var move := Vector2.ZERO
		if mode == 2 and second:
			move = Vector2(float(key.call(KEY_L)) - float(key.call(KEY_J)), float(key.call(KEY_I)) - float(key.call(KEY_K)))
			result.turn = float(key.call(KEY_O)) - float(key.call(KEY_U))
			result.roll = float(key.call(KEY_PERIOD)) - float(key.call(KEY_COMMA))
			result.height = float(key.call(KEY_Y)) - float(key.call(KEY_H))
		elif mode == 2:
			move = Vector2(float(key.call(KEY_D)) - float(key.call(KEY_A)), float(key.call(KEY_W)) - float(key.call(KEY_S)))
			result.turn = float(key.call(KEY_E)) - float(key.call(KEY_Q))
			result.roll = float(key.call(KEY_V)) - float(key.call(KEY_C))
			result.height = clampf(float(key.call(KEY_X)) - float(key.call(KEY_Z)), -1.0, 1.0)
		else:
			move = Vector2(float(key.call(KEY_D)) - float(key.call(KEY_A)), float(key.call(KEY_W)) - float(key.call(KEY_S)))
			result.roll = float(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or key.call(KEY_E)) - float(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or key.call(KEY_Q))
			result.height = clampf(float(pending.get("wheel", 0.0)) + float(key.call(KEY_X)) - float(key.call(KEY_Z)), -1.0, 1.0)
		result.move = move.limit_length(1.0)
		if mode == 2 and second: # the keys held (GHOST PIGEON: JUMP climbs, DASH dives)
			result.jump_held = bool(key.call(KEY_M)) or (bool(key.call(KEY_SPACE)) and bool(key.call(KEY_SHIFT)))
			result.dash_held = bool(key.call(KEY_COMMA))
		elif mode == 2:
			result.jump_held = bool(key.call(KEY_SPACE)) and not bool(key.call(KEY_SHIFT))
			result.dash_held = bool(key.call(KEY_C))
		else:
			result.jump_held = bool(key.call(KEY_SPACE))
			result.dash_held = bool(key.call(KEY_SHIFT)) or bool(key.call(KEY_C)) or bool(key.call(KEY_CTRL)) # SHIFT (dash), or C / CTRL (crouch)
	else:
		result.move = radial_deadzone(Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), -Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)))
		result.look = radial_deadzone(Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)))
		var plus := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) or trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)) > 0.0
		var minus := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) or trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)) > 0.0
		result.roll = float(plus) - float(minus)
		var held: Dictionary = _held.get(device, {"up": 0.0, "down": 0.0})
		held.up = float(held.up) + maxf(delta, 0.0) if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER) else 0.0
		held.down = float(held.down) + maxf(delta, 0.0) if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) else 0.0
		_held[device] = held
		var up := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP) or float(held.up) >= SHOULDER_HOLD
		var down := Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN) or float(held.down) >= SHOULDER_HOLD
		result.height = float(up) - float(down)
		result.jump_held = Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		result.dash_held = Input.is_joy_button_pressed(device, JOY_BUTTON_B) or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	result.jumps = int(pending.get("jumps", 0))
	result.grabs = int(pending.get("grabs", 0))
	result.dashes = int(pending.get("dashes", 0))
	result.items = int(pending.get("items", 0))
	result.tests = int(pending.get("tests", 0))
	result.options = bool(pending.get("options", false))
	result.restart = bool(pending.get("restart", false))
	return result
