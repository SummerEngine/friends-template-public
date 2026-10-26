extends Node3D
## The lobby wardrobe's runtime (client only). wardrobe_booth.gd draws the booth and adds this node at the ring's middle.
## A local player standing in the ring sees a prompt; E (the second keyboard player: P), a pad's X or a tap on the prompt
## opens the customizer for that player, who then owns it: the screen goes to a dark stage with their own character
## (wardrobe_camera.gd) and the customizer panel (wardrobe_ui.gd), which previews every change on the character at once.
## CONFIRM (or the pad's Start) saves the look (CharacterLook.save, one section per local seat); online it goes to the
## other players (demo/character/look_sync.gd). CANCEL, Escape or the pad's B put the look from before back. While it is
## open the owner holds still and is not counted on a pad: online the client sends menu=true (client/main.gd reads the
## world meta META), on one machine the shell's input pauses as under the pause menu. Every own character wears its saved
## look as soon as it exists.
const Layout = preload("res://network/walk_in_lobby.gd")
const GameInput = preload("res://game/game_input.gd")
const TouchControls = preload("res://client/touch_controls.gd")
const Look = preload("res://character/look.gd")
const PreviewCamera = preload("res://character/wardrobe/wardrobe_camera.gd")
const TeamCast = preload("res://style/team_cast.gd")
const WardrobeUi = preload("res://character/wardrobe/wardrobe_ui.gd")
const LookSync = preload("res://character/look_sync.gd")

signal opened(slot: int)
signal closed(slot: int)

const ENTER_RADIUS := 1.4 ## a player within this horizontal distance of the middle gets the prompt ...
const EXIT_RADIUS := 1.65 ## ... and keeps it up to this one
const BELOW := 0.6
const ABOVE := 2.2 ## a jump in the ring keeps the prompt
const META := "wardrobe_open" ## set on the simulation's world while a wardrobe is open (client/main.gd sends menu=true)
const LAYER := 36 ## canvas layer of the prompt and the panel: over the HUD, under the pause menu
const DRAG_TURN := 0.006 ## radians per design pixel of a mouse or finger drag
const STICK_TURN := 2.6 ## radians per second at full right stick
const PROMPT_SIZE := Vector2(400.0, 88.0)
const FADE_IN := 0.3 ## seconds of the dark veil lifting ...
const FADE_OUT := 0.18 ## ... and falling

var simulation: Node ## game/game_run.gd above this node; null in a bare yard (checks of the look): then nothing happens
var owner_slot := -1 ## the courier slot whose wardrobe is open, -1 while closed
var owner_seat := -1 ## the local seat that slot's look is saved under
var camera: Camera3D
var panel: Control
var in_ring := {} ## slot -> true while that local player stands in the ring
var _canvas: CanvasLayer
var _veil: ColorRect
var _fading: Tween
var _original ## the look before opening (CANCEL puts it back)
var _covered: Array[CanvasLayer] = [] ## the game's HUD layers hidden while the customizer is open
var _prompts := {} ## slot -> Button
var _worn := {} ## slot -> instance id of the rig that already wears its saved look
var _hold_input := false ## one machine: the shell's input was on when the wardrobe opened
var _leaving := false
var _drag := false
var _fingers := {} ## touch index -> position, fingers that went down on the free part of the screen
var _last_pad := false

func _ready() -> void:
	var node := get_parent()
	while node != null and not ("network_role" in node and "actors" in node and "rigs" in node): node = node.get_parent()
	simulation = node
	process_priority = 1000 # after the HUDs' own _process: the lobby banner sets itself visible every frame
	if simulation == null:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)

func _process(delta: float) -> void:
	if not _live(): return
	_wear_saved_looks()
	if owner_slot >= 0:
		_cover_hud()
		if not _lobby(): close(false, true)
		elif not _leaving:
			_hold()
			_turn_by_stick(delta)
			if panel.spin != 0.0: camera.turn(Vector2(panel.spin * WardrobeUi.TURN_SPEED * delta, 0.0))
		_show_prompts([])
		return
	_show_prompts(_slots_in_ring() if _lobby() and _input_allowed() else [])

func _live() -> bool:
	return is_instance_valid(simulation) and simulation.is_network_ready()

## The yard is up and played in (not the title backdrop, not a level).
func _lobby() -> bool:
	return is_visible_in_tree() and str(simulation.round_mode) == "lobby" and bool(simulation.playing)

## The slots played on this machine: both on one machine once Play was pressed, online the own courier.
func _local_slots() -> Array:
	if simulation.network_role == "local":
		var presentation: Node = simulation.local_presentation
		return [0, 1] if presentation != null and bool(presentation.started) else []
	var courier = simulation.owner_courier
	if courier != null and bool(courier.configured): return [int(courier.seat)]
	return []

func _seat_of(slot: int) -> int:
	return slot if simulation.network_role == "local" else 0

## The player may act: no pause menu, overlay or results page over the game.
func _input_allowed() -> bool:
	if simulation.network_role == "local": return bool(simulation.local_input_enabled) and not get_tree().paused
	return bool(simulation.camera_input_enabled)

func _slots_in_ring() -> Array:
	var middle := Layout.ORIGIN + Layout.wardrobe_center() # the ring's middle in the yard
	var result := []
	var slots := _local_slots()
	for slot: int in in_ring.keys():
		if not slot in slots: in_ring.erase(slot)
	for slot: int in slots:
		if slot >= simulation.actors.size() or not simulation.is_slot_active(slot) or not _dressable(slot): continue
		var at: Vector3 = simulation.actors[slot].global_position
		var reach := EXIT_RADIUS if in_ring.has(slot) else ENTER_RADIUS
		var height := at.y - middle.y
		if at.is_finite() and height >= -BELOW and height <= ABOVE and Vector2(at.x - middle.x, at.z - middle.z).length() <= reach:
			in_ring[slot] = true
			result.append(slot)
		else: in_ring.erase(slot)
	return result

# ------------------------------------------------------------------ looks

## The slot's character can wear looks (the character rig; the plain courier cannot).
func _dressable(slot: int) -> bool:
	var rig = simulation.rigs[slot] if slot >= 0 and slot < simulation.rigs.size() else null
	return rig != null and rig.has_method("set_look")

## Every own character wears its saved look once (again after its slot or its rig changes).
func _wear_saved_looks() -> void:
	var slots := _local_slots()
	for slot: int in _worn.keys():
		if not slot in slots: _worn.erase(slot)
	for slot: int in slots:
		if not _dressable(slot): continue
		var rig = simulation.rigs[slot]
		if int(_worn.get(slot, 0)) == rig.get_instance_id(): continue
		_worn[slot] = rig.get_instance_id()
		# Only a look the player saved: an unsaved player keeps the default of their seat. Once a rig wears a player's look,
		# the online seat tint (set_slot_tint) keeps its colours.
		if Look.has_saved(_seat_of(slot)): _wear(slot, Look.load_saved(_seat_of(slot)))

func _wear(slot: int, look) -> void:
	var rig = simulation.rigs[slot]
	if rig == null or not rig.has_method("set_look"): return
	rig.set_look(look)
	# A swapped mesh starts on the default render layers: the follow camera's own-body layer goes back on.
	if simulation.network_role == "local":
		if slot < simulation.split_follow.size(): simulation.split_follow[slot].own_body(rig, slot)
	elif simulation.follow != null and slot == int(simulation.selected): simulation.follow.own_body(rig, slot)

## A local player confirmed a look (CONFIRM or the pad's Start in the customizer). Online it goes to the other players; on
## one machine both characters are dressed here already.
func _on_look_committed(seat: int, look) -> void:
	if simulation.network_role != "local": LookSync.commit(look)
	print("WARDROBE saved seat=", seat, " bytes=", look.to_bytes().size())

# ------------------------------------------------------------------ open and close

func open(slot: int) -> void:
	if owner_slot >= 0 or not _live() or not _dressable(slot): return
	var rig = simulation.rigs[slot]
	owner_slot = slot
	owner_seat = _seat_of(slot)
	_leaving = false
	_original = rig.get_look() if rig.has_method("get_look") else null
	if _original == null: _original = Look.load_saved(owner_seat)
	simulation.world.set_meta(META, true)
	if simulation.network_role == "local":
		_hold_input = bool(simulation.local_input_enabled)
		simulation.set_local_input_enabled(false)
	_ensure_canvas()
	_veil.color.a = 1.0 # the stage comes up out of the dark
	camera = PreviewCamera.new()
	camera.name = "WardrobeCamera"
	add_child(camera)
	panel = WardrobeUi.new()
	panel.name = "WardrobePanel"
	_canvas.add_child(panel)
	panel.layout_changed.connect(camera.set_frame)
	panel.look_changed.connect(_preview)
	panel.confirm_pressed.connect(confirm)
	panel.cancel_pressed.connect(cancel)
	panel.zoom_step.connect(camera.zoom)
	panel.open(_original.duplicate_look(), _player_name(slot), _owner_pad(), owner_seat)
	_cover_hud(true)
	camera.begin(_home_camera(slot), rig, rig.global_rotation.y)
	_fade(0.0, FADE_IN)
	_show_prompts([])
	print("WARDROBE open slot=", slot, " seat=", owner_seat)
	opened.emit(slot)

## CONFIRM: the look is saved (and handed to sync) and stays on.
func confirm() -> void:
	close(true)

## CANCEL (Escape, B): the look from before opening comes back.
func cancel() -> void:
	close(false)

## Closes through the dark: `save` keeps the edited look, else the look from before opening is put back; `instant` skips
## the fade (the lobby is gone).
func close(save: bool, instant := false) -> void:
	if owner_slot < 0 or _leaving: return
	if save:
		var look = panel.look.duplicate_look()
		look.save(owner_seat)
		_wear(owner_slot, look)
		_on_look_committed(owner_seat, look)
	else: _wear(owner_slot, _original)
	_drag = false
	_fingers.clear()
	if instant:
		_finish_close()
		return
	_leaving = true
	_fade(1.0, FADE_OUT).tween_callback(func() -> void:
		_finish_close()
		_fade(0.0, FADE_IN))

func _finish_close() -> void:
	var slot := owner_slot
	if is_instance_valid(simulation):
		if simulation.camera != null and is_instance_valid(simulation.camera): simulation.camera.make_current()
		simulation.world.remove_meta(META)
		if simulation.network_role == "local" and _hold_input and not _pause_open():
			simulation.prime_local_input() # the key that closed the customizer must not reach the game
			simulation.set_local_input_enabled(true)
	_uncover_hud()
	if panel != null: panel.queue_free()
	panel = null
	if camera != null: camera.queue_free()
	camera = null
	owner_slot = -1
	owner_seat = -1
	_original = null
	_leaving = false
	print("WARDROBE closed slot=", slot)
	closed.emit(slot)

## While open the customizer has the screen: the game's HUD layers under it (the lobby banner, the HUD, the touch overlay)
## hide; menus above it (the pause menu, the online screens) stay.
func _cover_hud(scan := false) -> void:
	if scan or Engine.get_process_frames() % 30 == 0: # a look for new layers now and then, not every frame
		for layer: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if layer.layer >= 0 and layer.layer < LAYER and layer.visible and not is_ancestor_of(layer) and not layer in _covered: _covered.append(layer)
	for layer: CanvasLayer in _covered:
		if is_instance_valid(layer) and layer.visible: layer.visible = false

func _uncover_hud() -> void:
	for layer: CanvasLayer in _covered:
		if is_instance_valid(layer): layer.visible = true
	_covered.clear()

## The dark veil over everything: up to `alpha` in `seconds`.
func _fade(alpha: float, seconds: float) -> Tween:
	_ensure_canvas()
	if _fading != null and _fading.is_valid(): _fading.kill()
	_fading = create_tween()
	_fading.tween_property(_veil, "color:a", alpha, seconds)
	return _fading

## The name the header shows: the cast's name of a local seat; online the match's name for this client's seat.
func _player_name(slot: int) -> String:
	if simulation.network_role != "local":
		var client: Node = simulation.get_parent()
		if client != null and "match_info" in client and "my_seat" in client:
			var names: Array = client.match_info.get("names", [])
			var seat := int(client.my_seat)
			if seat >= 0 and seat < names.size() and str(names[seat]) != "": return str(names[seat])
	return TeamCast.player_name(slot)

func _preview(look) -> void:
	if owner_slot >= 0: _wear(owner_slot, look)

## While open the owner holds still: the shell's local input stays off even when the pause menu closes over the wardrobe.
func _hold() -> void:
	if simulation.network_role == "local" and bool(simulation.local_input_enabled): simulation.set_local_input_enabled(false)

func _pause_open() -> bool:
	var presentation: Node = simulation.get("local_presentation")
	return presentation != null and presentation.menus != null and bool(presentation.menus.pause_open)

## The camera that shows this player now (its half in split screen): the orbit camera eases in from it and back to it.
func _home_camera(slot: int) -> Camera3D:
	var views = simulation.local_views
	if views != null and bool(views.active) and slot < views.cameras.size(): return views.cameras[slot]
	return simulation.camera

# ------------------------------------------------------------------ input

## Devices of the owner: on one machine the seat's own (whoever opened it owns it), online every pad and the keyboard.
func _owner_devices() -> Array:
	if simulation.network_role != "local": return Array(Input.get_connected_joypads()) + [GameInput.KEYBOARD]
	var sources: Array = simulation.local_input.seat_sources(simulation.connected_pads())
	return sources[owner_slot] if owner_slot >= 0 and owner_slot < sources.size() else []

func _owner_pad() -> bool:
	return _last_pad and _owner_devices().any(func(device: int) -> bool: return device >= 0)

## The slot a press opens the wardrobe for (-1 for none): E for the keyboard's player, P for the second keyboard player,
## a pad's X for that pad's player.
func _opening_slot(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_E: return _slot_of_device(GameInput.KEYBOARD)
		if key == KEY_P and simulation.network_role == "local" and int(simulation.local_input.mode) == 2: return _slot_of_device(GameInput.KEYBOARD_TWO)
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X:
		return _slot_of_device(event.device)
	return -1

func _slot_of_device(device: int) -> int:
	if simulation.network_role != "local":
		var own := _local_slots()
		return int(own[0]) if not own.is_empty() else -1
	var sources: Array = simulation.local_input.seat_sources(simulation.connected_pads())
	for slot in sources.size():
		if device in sources[slot]: return slot
	return -1

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5): _last_pad = true
	elif event is InputEventKey or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION) or event is InputEventScreenTouch: _last_pad = false
	if owner_slot < 0 or _leaving or not _live(): return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if not event.device in _owner_devices():
			get_viewport().set_input_as_handled() # another player's pad: the wardrobe is not theirs
			return
		if event is InputEventJoypadButton and event.pressed and not _menu_over_panel():
			match event.button_index:
				JOY_BUTTON_B:
					get_viewport().set_input_as_handled()
					cancel()
				JOY_BUTTON_START:
					get_viewport().set_input_as_handled()
					confirm()
				JOY_BUTTON_LEFT_SHOULDER:
					panel.step_tab(-1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_RIGHT_SHOULDER:
					panel.step_tab(1)
					get_viewport().set_input_as_handled()
				JOY_BUTTON_Y:
					panel.randomize_all()
					get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and not _menu_over_panel():
		get_viewport().set_input_as_handled()
		cancel()
		return
	# Drags that started on the free part of the screen keep turning over the panel; releases end them anywhere.
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: _drag = false
	elif event is InputEventMouseMotion and _drag and event.device != InputEvent.DEVICE_ID_EMULATION: camera.turn(-event.relative * DRAG_TURN)
	elif event is InputEventScreenTouch and not event.pressed: _fingers.erase(event.index)
	elif event is InputEventScreenDrag and _fingers.has(event.index): _finger_drag(event)

func _unhandled_input(event: InputEvent) -> void:
	if not _live(): return
	if owner_slot >= 0:
		if _leaving: return
		if event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
			match event.button_index:
				MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT: _drag = true
				MOUSE_BUTTON_WHEEL_UP: camera.zoom(0.9)
				MOUSE_BUTTON_WHEEL_DOWN: camera.zoom(1.0 / 0.9)
		elif event is InputEventScreenTouch and event.pressed: _fingers[event.index] = event.position
		elif event is InputEventMagnifyGesture: camera.zoom(1.0 / maxf(event.factor, 0.01))
		elif event is InputEventPanGesture: camera.zoom(1.0 + event.delta.y * 0.04)
		return
	var slot := _opening_slot(event)
	if slot >= 0 and in_ring.has(slot) and _lobby() and _input_allowed():
		get_viewport().set_input_as_handled()
		open(slot)

## Another menu (the pause menu online) holds the focus over the panel: Escape and B are its own.
func _menu_over_panel() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and panel != null and not panel.is_ancestor_of(focus)

## One finger turns the camera, two pinch the zoom.
func _finger_drag(event: InputEventScreenDrag) -> void:
	if _fingers.size() >= 2:
		var others: Array = _fingers.keys().filter(func(index: int) -> bool: return index != event.index)
		var other: Vector2 = _fingers[others[0]]
		var before := other.distance_to(_fingers[event.index])
		var after := other.distance_to(event.position)
		if before > 1.0 and after > 1.0: camera.zoom(before / after)
	else: camera.turn(-event.relative * DRAG_TURN)
	_fingers[event.index] = event.position

func _turn_by_stick(delta: float) -> void:
	var turn := Vector2.ZERO
	var zoom := 0.0
	for device: int in _owner_devices():
		if device < 0: continue
		turn += GameInput.radial_deadzone(Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)))
		zoom += GameInput.trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)) - GameInput.trigger(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT))
	if turn != Vector2.ZERO:
		var settings: Dictionary = simulation.camera_settings
		var invert := Vector2(-1.0 if bool(settings.get("InvertX", false)) else 1.0, -1.0 if bool(settings.get("InvertY", false)) else 1.0)
		camera.turn(-turn * invert * STICK_TURN * delta)
	if zoom != 0.0: camera.zoom(1.0 + zoom * delta * 1.5)

# ------------------------------------------------------------------ prompt

func _ensure_canvas() -> void:
	if _canvas != null: return
	_canvas = CanvasLayer.new()
	_canvas.name = "WardrobeCanvas"
	_canvas.layer = LAYER
	add_child(_canvas)
	var veil_layer := CanvasLayer.new()
	veil_layer.name = "WardrobeVeil"
	veil_layer.layer = LAYER + 1
	add_child(veil_layer)
	_veil = ColorRect.new()
	_veil.color = Color(PreviewCamera.VEIL, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil_layer.add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## One prompt per player in the ring, over that player's half in split screen.
func _show_prompts(slots: Array) -> void:
	for slot: int in _prompts:
		if not slot in slots: (_prompts[slot] as Button).visible = false
	if slots.is_empty(): return
	_ensure_canvas()
	var view := get_viewport().get_visible_rect().size
	var factor := WardrobeUi.ui_scale(view)
	var views = simulation.local_views
	var split: bool = views != null and bool(views.active)
	for index in slots.size():
		var slot: int = slots[index]
		var button := _prompt(slot)
		WardrobeUi.set_prompt_key(button, _key_label(slot))
		button.scale = Vector2.ONE * factor
		var width := PROMPT_SIZE.x * factor
		var middle := view.x * (0.25 + 0.5 * slot) if split else view.x * 0.5 + (index - (slots.size() - 1) * 0.5) * (width + 24.0)
		button.position = Vector2(middle - width * 0.5, view.y - (PROMPT_SIZE.y + 168.0) * factor)
		button.visible = true

func _prompt(slot: int) -> Button:
	if _prompts.has(slot): return _prompts[slot]
	var button := WardrobeUi.prompt_button("Change your look", PROMPT_SIZE)
	button.name = "WardrobePrompt%d" % slot
	button.pressed.connect(func() -> void:
		if in_ring.has(slot) and _lobby() and _input_allowed(): open(slot))
	_canvas.add_child(button)
	_prompts[slot] = button
	return button

## The key shown on the prompt ("" on a touch screen: the prompt itself is the button).
func _key_label(slot: int) -> String:
	if TouchControls.touch_ui(): return ""
	if simulation.network_role != "local": return "X" if _last_pad and not Input.get_connected_joypads().is_empty() else "E"
	var devices: Array = simulation.local_input.seat_sources(simulation.connected_pads())[slot]
	if GameInput.KEYBOARD_TWO in devices: return "P"
	var pad := devices.any(func(device: int) -> bool: return device >= 0)
	if GameInput.KEYBOARD in devices and not (pad and _last_pad): return "E"
	return "X" if pad else "E"

func probe() -> Dictionary:
	return {"open": owner_slot >= 0, "slot": owner_slot, "seat": owner_seat, "leaving": _leaving, "in_ring": in_ring.keys(),
		"prompts": _prompts.keys().filter(func(slot: int) -> bool: return (_prompts[slot] as Button).visible)}
