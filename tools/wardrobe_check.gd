extends SceneTree
## Headless check of the lobby wardrobe and its customizer (demo/character/wardrobe/). Builds the yard with its booth under a
## stand-in shell (the local role: two players, the parts of game/game_run.gd the wardrobe reads), then:
##   the board's collision and the booth are where they belong; the prompt shows only in the ring;
##   player 1 opens it with E: the shell's input pauses, the world says wardrobe_open, the dark stage camera takes over, the
##   header names the player; landscape and phone-portrait layouts (thumb-sized tiles and sliders);
##   drags on the preview turn it (not on the sheet), the wheel and the zoom buttons zoom, a held turn button turns;
##   every tab: every tile is clicked and every slider is set to both ends: the look and the character follow each one,
##   the value shows with one decimal, face rows only show what fits the head;
##   RANDOMIZE ALL, RANDOMIZE PARAMS, RESET PARAMS; CANCEL (a real click) and Escape put the look back; CONFIRM (a real
##   click) saves it; the look round-trips (rig, save file, bytes); the champion's crown is a hat (offered once won, off with None, back on, saved, in the bytes);
##   player 2 opens it with a pad's X; the other pad's B is ignored, the owner's B cancels, Start confirms (seat 2);
##   the lobby ending cancels at once; a new character wears the saved look, a seat tint does not undo it.
## Then the real local game (game/game_run.gd booted through client/presentation_entry.gd, two pads, split screen): E
## opens it, the stage shows only the own character, the courier holds still, Escape brings back the split views and walking.
## Without a body model (no art, no local stand-ins) the character rig cannot build: the stand-in rig is used and the real
## game pass is skipped (the game keeps the courier, which has no looks).
## The player's own user://look.cfg is put back afterwards. Prints WARDROBE_CHECK ok=true|false and exits 0 / 1.
##   Summer --headless --path demo -s $PWD/tools/wardrobe_check.gd [-- --quick (stand-in shell only)]
const LobbySpace := preload("res://lobby_space.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const LobbyDraw := preload("res://lobby_visuals.gd")
const LobbyEnvironment := preload("res://lobby_environment.gd")
const GameInput := preload("res://game/game_input.gd")
const Catalog := preload("res://character/catalog.gd")
const Look := preload("res://character/look.gd")
const Wardrobe := preload("res://character/wardrobe/wardrobe.gd")
const WardrobeUi := preload("res://character/wardrobe/wardrobe_ui.gd")
const PreviewCamera := preload("res://character/wardrobe/wardrobe_camera.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Thumbs := preload("res://character/wardrobe/wardrobe_thumbs.gd")
const RIG := "res://character/character_rig.gd"
const SAVE := "user://look.cfg"

## The parts of game/game_run.gd the wardrobe reads, for the local role.
class StandInShell extends Node:
	var network_role := "local"
	var actors: Array = []
	var rigs: Array = []
	var world: Node3D
	var camera: Camera3D
	var local_views = null
	var split_follow: Array = []
	var follow = null
	var selected := 0
	var round_mode := "lobby"
	var playing := true
	var local_input_enabled := true
	var camera_input_enabled := true
	var camera_settings := {}
	var local_presentation: Node
	var local_input := GameInput.new()
	var owner_courier = null
	var pads: Array = []
	var primed := 0
	func is_network_ready() -> bool: return true
	func is_slot_active(slot: int) -> bool: return slot >= 0 and slot < actors.size()
	func set_local_input_enabled(on: bool) -> void:
		local_input_enabled = on
		camera_input_enabled = on
	func prime_local_input() -> void: primed += 1
	func connected_pads() -> Array: return pads

## The real local game with pads the check chooses.
class VirtualLocal extends "res://client/presentation_entry.gd":
	var pads: Array = []
	func connected_pads() -> Array: return pads

class StandInPresentation extends Node:
	var started := true
	var menus := {"pause_open": false}

## Used when the character rig cannot build (no body model): wears the look it is given and, like the rig, reports its
## seat's default look before it was given one.
class StandInRig extends Node3D:
	var worn = null
	var seat := 0
	func setup(seat_index: int) -> void:
		seat = seat_index
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.8
		body.mesh = capsule
		body.position.y = 0.9
		add_child(body)
	func set_look(look) -> void: worn = look.duplicate_look()
	func get_look(): return worn.duplicate_look() if worn != null else Look.defaults_for_seat(seat)

var failures: Array[String] = []
var shell: StandInShell
var booth: Node3D
var saved_bytes := PackedByteArray()
var had_save := false

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("WARDROBE_CHECK fail ", what)

func frames(count := 2) -> void:
	for _i in count: await process_frame

func seconds(value: float) -> void:
	await create_timer(value).timeout

## Until the customizer has closed (it fades out first), at most 5 s: a loaded machine can run long frames, in which a
## fixed timer and the fade end in the same frame.
func closed(target: Node3D) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while target.probe().open and Time.get_ticks_msec() < deadline: await process_frame
	await frames(1)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func _hold_key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func pad_button(device: int, button: JoyButton) -> void:
	for down: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = down
		root.push_input(event, true)

func click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = at
		event.global_position = at
		event.pressed = down
		root.push_input(event, true)

func rig_look(slot: int):
	return shell.rigs[slot].get_look()

func run() -> void:
	_keep_save()
	_build()
	await frames(3)
	_check_booth()
	await _check_prompt()
	await _open_with_key()
	await _check_layout()
	await _check_view_input()
	await _click_everything()
	await _check_bar()
	await _cancel_reverts()
	await _confirm_saves()
	await _crown_hat()
	await _second_player_with_pad()
	await _lobby_ends()
	await _new_character_wears_saved()
	_check_picture_colors()
	LobbySpace.client_draw_factory = Callable()
	shell.queue_free()
	await frames(2)
	if "--quick" in OS.get_cmdline_user_args() or not _real_rig(): print("WARDROBE_CHECK real game skipped (--quick or no body model)")
	else: await _real_game()
	_restore_save()
	var ok := failures.is_empty()
	print("WARDROBE_CHECK ok=", ok, " failures=", failures.size(), " params=", Catalog.params().size(), " rig=", "character_rig.gd" if _real_rig() else "stand-in")
	quit(0 if ok else 1)

## Same colours, items and params (params sit on int8 steps, so saves and bytes match exactly).
func same(a, b) -> bool:
	return a != null and b != null and a.equals(b)

func tiles_of(panel: Control) -> Array:
	return panel.find_children("*", "Button", true, false).filter(func(node: Node) -> bool: return node.has_meta("row") and not node.is_queued_for_deletion())

func tile(panel: Control, row: String, value: Variant) -> Button:
	for button: Button in tiles_of(panel):
		if button.get_meta("row") == row and button.get_meta("value") == value: return button
	return null

func sliders_of(panel: Control) -> Array:
	return panel.find_children("*", "HSlider", true, false).filter(func(node: Node) -> bool: return node.has_meta("param") and not node.is_queued_for_deletion())

func center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func _keep_save() -> void:
	had_save = FileAccess.file_exists(SAVE)
	if had_save: saved_bytes = FileAccess.get_file_as_bytes(SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

func _restore_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if had_save:
		var file := FileAccess.open(SAVE, FileAccess.WRITE)
		file.store_buffer(saved_bytes)
		file.close()

## The character rig when it can build (a body model in models/ or the local stand-ins), else the stand-in.
func _real_rig() -> bool:
	return ResourceLoader.exists(RIG) and bool(load(RIG).available())

func _make_rig(slot: int) -> Node3D:
	var rig: Node3D = load(RIG).new() if _real_rig() else StandInRig.new()
	rig.name = "Rig%d" % (slot + 1)
	shell.world.add_child(rig)
	rig.setup(slot)
	rig.global_position = shell.actors[slot].global_position
	return rig

func _build() -> void:
	root.size = Vector2i(1280, 720)
	LobbySpace.client_draw_factory = func() -> Dictionary: return {"visuals": LobbyDraw, "environment": LobbyEnvironment.new()}
	shell = StandInShell.new()
	shell.name = "Shell"
	root.add_child(shell)
	shell.local_presentation = StandInPresentation.new()
	shell.add_child(shell.local_presentation)
	shell.local_input.configure(2) # both players on one keyboard: E and P
	shell.world = Node3D.new()
	shell.world.name = "World"
	shell.add_child(shell.world)
	for slot in 2:
		var body := CharacterBody3D.new()
		body.name = "Courier%d" % (slot + 1)
		shell.world.add_child(body)
		body.global_position = Layout.spawn(slot)
		shell.actors.append(body)
	for slot in 2: shell.rigs.append(_make_rig(slot))
	shell.camera = Camera3D.new()
	shell.camera.name = "FollowCamera"
	shell.world.add_child(shell.camera)
	shell.camera.global_position = Layout.ORIGIN + Vector3(0.0, 4.0, 8.0)
	shell.camera.current = true
	LobbySpace.sync(shell.world, "local", true)

func _check_booth() -> void:
	var room: Node3D = shell.world.get_node(LobbySpace.NAME)
	var board: StaticBody3D = room.get_node_or_null("wardrobe_mirror")
	expect(board != null, "the mirror board has collision")
	if board != null:
		var at := Vector3(-Layout.yard_half_width() + 0.15, 1.6, Layout.wardrobe_center().z) # the mirror board stands behind the ring
		expect(board.global_position.distance_to(Layout.ORIGIN + at) < 0.01, "the board stands on the west wall at %s: %s" % [at, board.global_position - Layout.ORIGIN])
		expect(board.collision_layer == LobbySpace.LAYER, "the board collides like the yard")
		for shape: Node in board.get_children():
			for drawn: Node in shape.get_children():
				if drawn is GeometryInstance3D: expect(not drawn.visible, "the board's comic box is hidden behind the mirror")
	booth = room.get_node_or_null("Wardrobe")
	expect(booth != null and booth.simulation == shell, "the booth runs under the shell")
	if booth != null: expect(booth.global_position.distance_to(Layout.ORIGIN + Layout.wardrobe_center()) < 0.01, "the booth sits at the ring's middle")
	expect(room.get_node_or_null("WardrobeMirror") != null, "the mirror is drawn")

func _check_prompt() -> void:
	await frames(2)
	expect(booth.probe().prompts.is_empty(), "no prompt at the spawn")
	shell.actors[0].global_position = Layout.ORIGIN + Layout.wardrobe_center() + Vector3(0.6, 0.0, 0.3)
	await frames(2)
	expect(booth.probe().prompts == [0], "player 1 in the ring gets the prompt: %s" % [booth.probe()])
	var prompt: Button = booth._prompts.get(0)
	expect(prompt != null and prompt.visible and prompt.get_node("Key").text == "E", "the prompt shows E for the first keyboard player")
	shell.local_input_enabled = false
	await frames(2)
	expect(booth.probe().prompts.is_empty(), "no prompt while the game's input is off (a menu is open)")
	shell.local_input_enabled = true
	await frames(1)

func _open_with_key() -> void:
	key(KEY_E)
	await frames(2)
	var state: Dictionary = booth.probe()
	expect(state.open and state.slot == 0 and state.seat == 0, "E opens the customizer for player 1: %s" % [state])
	expect(bool(shell.world.get_meta(Wardrobe.META, false)), "the world says wardrobe_open (online: menu=true)")
	expect(not shell.local_input_enabled, "the shell's input pauses while it is open")
	expect(booth.camera != null and root.get_camera_3d() == booth.camera, "the stage camera is the current camera")
	expect(booth.camera.environment != null and booth.camera.environment.background_mode == Environment.BG_COLOR, "the stage clears to a plain colour (the painted sky is a quad in front of it)")
	var header: Label = booth.panel.find_child("Player", true, false)
	expect(header != null and header.text == "PLAYER: " + TeamCast.player_name(0).to_upper(), "the header names the player: %s" % (header.text if header != null else "none"))
	var deadline := Time.get_ticks_msec() + 5000
	while booth._veil.color.a >= 0.05 and Time.get_ticks_msec() < deadline: await process_frame
	expect(booth._veil.color.a < 0.05, "the dark veil lifted")

## Landscape: preview left, sheet right, one bar row. An upright phone: preview on top, sheet below, two bar rows, thumb sizes.
func _check_layout() -> void:
	var panel: Control = booth.panel
	var sheet: Control = panel.get_node("Sheet")
	var tools: Control = panel.get_node("ViewTools")
	var view := root.get_visible_rect().size
	var rect := sheet.get_global_rect()
	expect(not panel.portrait and Rect2(Vector2.ZERO, view).grow(1.0).encloses(rect) and rect.position.x > view.x * 0.4, "landscape: the sheet on the right (%s in %s)" % [rect, view])
	expect(tools.get_global_rect().end.x < rect.position.x and booth.camera.frame.x < -0.2, "landscape: the character and its buttons on the left (%s)" % booth.camera.frame)
	var bar: Dictionary = {}
	for name: String in ["RandomizeAll", "RandomizeParams", "ResetParams", "Cancel", "Confirm"]: bar[name] = panel.find_child(name, true, false)
	expect(bar.values().all(func(button) -> bool: return button != null and button.is_visible_in_tree()), "the bottom bar has its five buttons")
	expect(is_equal_approx(center(bar.Cancel).y, center(bar.RandomizeAll).y) and center(bar.Confirm).y > rect.end.y, "landscape: one bar row under the sheet")
	var window_size := root.size
	root.size = Vector2i(390, 844)
	await frames(3)
	view = root.get_visible_rect().size
	rect = sheet.get_global_rect()
	expect(panel.portrait, "a phone held upright gets the stacked layout (%s)" % view)
	expect(Rect2(Vector2.ZERO, view).grow(1.0).encloses(rect) and rect.position.y > view.y * 0.3, "portrait: the sheet sits low and fits (%s in %s)" % [rect, view])
	expect(booth.camera.frame.y > 0.2 and tools.get_global_rect().end.y <= rect.position.y + 1.0, "portrait: the character and its buttons above the sheet (%s)" % booth.camera.frame)
	expect(center(bar.Confirm).y > center(bar.RandomizeAll).y + 10.0, "portrait: CANCEL and CONFIRM get their own row")
	var thumb := minf(view.x, view.y) / 720.0 * 56.0 # 56 px of a phone held sideways
	for node: Control in tiles_of(panel) + sliders_of(panel): expect(node.get_global_rect().size.y >= thumb - 0.5, "portrait: thumb-sized %s (%s)" % [node.get_class(), node.get_global_rect().size])
	root.size = window_size
	await frames(3)
	expect(not panel.portrait, "back to landscape")
	print("WARDROBE_CHECK layout portrait ", view, " sheet ", rect)

func _drag(from: Vector2, by: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = from + by
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await frames(1)

func _check_view_input() -> void:
	var panel: Control = booth.panel
	var view := root.get_visible_rect().size
	var before: Dictionary = booth.camera.probe()
	await _drag(Vector2(view.x * 0.25, view.y * 0.4), Vector2(120.0, 30.0))
	var after: Dictionary = booth.camera.probe()
	expect(absf(after.yaw - before.yaw) > 0.3, "a drag on the preview turns the character: %s -> %s" % [before.yaw, after.yaw])
	expect(after.pitch >= deg_to_rad(-45.01) and after.pitch <= deg_to_rad(30.01), "the pitch stays within -45..30 degrees")
	var yaw: float = after.yaw
	await _drag(center(panel.get_node("Sheet")), Vector2(60.0, 0.0))
	expect(is_equal_approx(booth.camera.probe().yaw, yaw), "a drag on the sheet does not turn it")
	click(Vector2(view.x * 0.25, view.y * 0.4), MOUSE_BUTTON_WHEEL_UP)
	await frames(1)
	var zoom: float = booth.camera.probe().zoom
	expect(zoom < before.zoom, "the wheel zooms in")
	(panel.find_child("ZoomIn", true, false) as Button).pressed.emit()
	expect(booth.camera.probe().zoom < zoom, "the zoom-in button zooms in")
	(panel.find_child("ZoomOut", true, false) as Button).pressed.emit()
	(panel.find_child("ZoomOut", true, false) as Button).pressed.emit()
	expect(booth.camera.probe().zoom > zoom, "the zoom-out button zooms out")
	var turn: Button = panel.find_child("TurnLeft", true, false)
	yaw = booth.camera.probe().yaw
	turn.button_down.emit()
	await seconds(0.2)
	turn.button_up.emit()
	await frames(1)
	var turned: float = booth.camera.probe().yaw
	expect(absf(angle_difference(yaw, turned)) > 0.1, "a held turn button turns the character")
	await frames(5)
	expect(is_equal_approx(booth.camera.probe().yaw, turned), "letting go stops the turn")

## Every tab: every tile, every slider to both ends. The look follows, the character wears it.
func _click_everything() -> void:
	var panel: Control = booth.panel
	var counts := {}
	for index in WardrobeUi.TABS.size():
		var title := str(WardrobeUi.TABS[index].title)
		if index == 1: click(center(panel._tab_buttons[index])) # one real click on a tab
		else: panel.select_tab(index)
		await frames(1)
		expect(panel.tab == index, "tab %s opens" % title)
		var head := str(panel.look.items.get("head", ""))
		var want := 0
		for row: String in WardrobeUi.tab_rows(index):
			if row.begins_with("color:"): want += Catalog.palette_for(row.trim_prefix("color:")).size()
			else:
				var slot := row.trim_prefix("item:")
				want += 1 + Catalog.items(slot).filter(func(item: Dictionary) -> bool: return slot == "head" or Catalog.fits(item, head)).size()
		var pairs := tiles_of(panel).map(func(button: Button) -> Array: return [button.get_meta("row"), button.get_meta("value")])
		expect(pairs.size() == want, "%s shows every picker tile: %d of %d" % [title, pairs.size(), want])
		for pair: Array in pairs:
			var button := tile(panel, pair[0], pair[1])
			if button == null: continue # a face item the newly picked head does not take
			button.pressed.emit()
			await frames(0)
			var row: String = pair[0]
			var picked: Variant = int(panel.look.colors.get(row.trim_prefix("color:"), -1)) if row.begins_with("color:") else str(panel.look.items.get(row.trim_prefix("item:"), ""))
			expect(picked == pair[1], "tile %s=%s is picked" % pair)
			if row == "item:head" and Catalog.item(str(pair[1])).has("skin"):
				expect(int(panel.look.colors.get("skin", -1)) == int(Catalog.item(str(pair[1])).skin), "the head %s brings its skin colour" % pair[1])
			var shown := tile(panel, pair[0], pair[1])
			expect(shown != null and shown.button_pressed, "tile %s=%s shows as picked" % pair)
			expect(rig_look(0) != null and same(rig_look(0), panel.look), "the character wears %s=%s" % pair)
		head = str(panel.look.items.get("head", ""))
		for button: Button in tiles_of(panel):
			var row: String = button.get_meta("row")
			if row.begins_with("item:") and row != "item:head" and str(button.get_meta("value")) != "":
				expect(Catalog.fits(Catalog.item(str(button.get_meta("value"))), head), "%s only shows items for the head %s" % [row, head])
		var sliders := sliders_of(panel)
		expect(sliders.size() == WardrobeUi.tab_params(index).size(), "%s shows its sliders: %d of %d" % [title, sliders.size(), WardrobeUi.tab_params(index).size()])
		for slider: HSlider in sliders:
			var id := str(slider.get_meta("param"))
			for end: float in [-1.0, 1.0]:
				slider.value = end
				expect(is_equal_approx(panel.look.param(id), end), "slider %s at %s" % [id, end])
				var value: Button = slider.get_parent().get_node("Value")
				expect(value.text == "%.1f" % end, "slider %s shows %s (%s)" % [id, "%.1f" % end, value.text])
				expect(same(rig_look(0), panel.look), "the character wears %s=%s" % [id, end])
			(slider.get_parent().get_node("Value") as Button).pressed.emit()
			expect(is_zero_approx(panel.look.param(id)), "tapping the value of %s sets it back to 0" % id)
		counts[title] = [pairs.size(), sliders.size()]
	expect(int(counts.get("PARAMS", [0, 0])[1]) == Catalog.params().size(), "PARAMS shows every slider")
	print("WARDROBE_CHECK tabs [tiles, sliders] ", counts)

func _check_bar() -> void:
	var panel: Control = booth.panel
	var ids := Catalog.params().map(func(entry: Dictionary) -> String: return str(entry.id))
	(panel.find_child("RandomizeAll", true, false) as Button).pressed.emit()
	await frames(1)
	var values: Array = ids.map(func(id: String) -> float: return panel.look.param(id))
	expect(values.all(func(v: float) -> bool: return v >= -1.0 and v <= 1.0) and (ids.is_empty() or values.any(func(v: float) -> bool: return v != 0.0)), "RANDOMIZE ALL sets params in -1..1")
	expect(same(rig_look(0), panel.look), "RANDOMIZE ALL is worn at once")
	var head := str(panel.look.items.get("head", ""))
	for slot: String in Catalog.slots():
		var id := str(panel.look.items.get(slot, ""))
		if slot != "head" and id != "": expect(Catalog.fits(Catalog.item(id), head), "RANDOMIZE ALL keeps %s on the head" % slot)
	var colors: Dictionary = panel.look.colors.duplicate()
	var items: Dictionary = panel.look.items.duplicate()
	var params: Dictionary = panel.look.params.duplicate()
	(panel.find_child("RandomizeParams", true, false) as Button).pressed.emit()
	expect(panel.look.colors == colors and panel.look.items == items, "RANDOMIZE PARAMS keeps colours and items")
	expect(ids.is_empty() or panel.look.params != params, "RANDOMIZE PARAMS changes the params")
	expect(same(rig_look(0), panel.look), "RANDOMIZE PARAMS is worn at once")
	(panel.find_child("ResetParams", true, false) as Button).pressed.emit()
	expect(ids.all(func(id: String) -> bool: return is_zero_approx(panel.look.param(id))), "RESET PARAMS sets every param to 0")
	expect(sliders_of(panel).all(func(slider: HSlider) -> bool: return is_zero_approx(slider.value)), "RESET PARAMS moves the sliders to 0")
	expect(same(rig_look(0), panel.look), "RESET PARAMS is worn at once")

func _edit_something(panel: Control) -> void:
	panel.select_tab(0)
	await frames(1)
	var skin := int(panel.look.colors.get("skin", 0))
	for swatch: Button in tiles_of(panel):
		if swatch.get_meta("row") == "color:skin" and int(swatch.get_meta("value")) != skin:
			swatch.pressed.emit() # another skin colour
			break
	var sliders := sliders_of(panel)
	if not sliders.is_empty(): (sliders[0] as HSlider).value = 0.5

func _cancel_reverts() -> void:
	var original = booth._original.duplicate_look()
	expect(not same(rig_look(0), original), "the character wears the edited look before CANCEL")
	var cancel: Button = booth.panel.find_child("Cancel", true, false)
	click(center(cancel))
	await frames(1)
	expect(booth.probe().leaving, "a click on CANCEL closes it")
	expect(same(rig_look(0), original), "CANCEL puts the look from before back at once")
	await closed(booth)
	var state: Dictionary = booth.probe()
	expect(not state.open and not shell.world.has_meta(Wardrobe.META), "closed, wardrobe_open cleared: %s" % [state])
	expect(shell.local_input_enabled and root.get_camera_3d() == shell.camera, "the input and the follow camera are back")
	expect(not Look.has_saved(0), "CANCEL saves nothing")
	key(KEY_E)
	await frames(2)
	await _edit_something(booth.panel)
	expect(not same(rig_look(0), original), "edited again")
	key(KEY_ESCAPE)
	await closed(booth)
	expect(not booth.probe().open and same(rig_look(0), original) and not Look.has_saved(0), "Escape cancels too")

func _confirm_saves() -> void:
	key(KEY_E)
	await frames(2)
	expect(booth.probe().open, "E opens it again")
	await seconds(0.4)
	await _edit_something(booth.panel)
	var final = booth.panel.look.duplicate_look()
	var primed := shell.primed
	click(center(booth.panel.find_child("Confirm", true, false)))
	await frames(1)
	expect(Look.has_saved(0) and same(Look.load_saved(0), final), "a click on CONFIRM saves the look for seat 1")
	await closed(booth)
	expect(not booth.probe().open and shell.local_input_enabled and shell.primed == primed + 1, "closed, the input is back (the closing key is drained)")
	expect(same(rig_look(0), final), "the character keeps the confirmed look")
	var reloaded = Look.load_saved(0)
	expect(same(reloaded, final) and same(Look.from_dict(reloaded.to_dict()), final) and same(Look.from_bytes(reloaded.to_bytes()), final), "the saved look round-trips (file, dict, bytes)")

## The champion's crown is a hat: not offered before it is won, then in the Hat tab, worn, taken off by None or another hat and put back, saved, and in the bytes the other players get.
func _crown_hat() -> void:
	var crown := "hat_crown"
	var hat_tab := -1
	for index in WardrobeUi.TABS.size():
		if "item:hat" in WardrobeUi.tab_rows(index): hat_tab = index
	expect(hat_tab >= 0 and Catalog.item(crown).get("slot") == "hat" and Catalog.award_of(crown) == "crown", "the crown is a hat item of the catalog, an award")
	expect(not Catalog.items("hat").any(func(item: Dictionary) -> bool: return item.id == crown) and Catalog.awards("hat").size() == 1 and Catalog.default_item("hat") != crown, "it is not an ordinary, default or random item")
	var seen := {}
	for seed in 20: seen[Look.new().randomized(_rng_seeded(seed)).items["hat"]] = true
	expect(not seen.has(crown), "RANDOMIZE never picks it")
	key(KEY_E)
	await frames(2)
	await seconds(0.4)
	var panel: Control = booth.panel
	panel.select_tab(hat_tab)
	await frames(2)
	expect(tile(panel, "item:hat", crown) == null, "a player who has not won it is not offered the crown")
	var base = rig_look(0)
	key(KEY_ESCAPE)
	await closed(booth)
	var worn = Look.award(0, crown, base)
	expect(Look.has_award(0, "crown") and not Look.has_award(1, "crown") and worn.items["hat"] == crown and same(Look.load_saved(0), worn), "the award is saved for the seat, with the crown on")
	shell.rigs[0].set_look(worn)
	expect(shell.rigs[0].get_look().items["hat"] == crown and _hat_shown(shell.rigs[0]), "the crown is on the character's head as a hat")
	var bytes: PackedByteArray = worn.to_bytes()
	var other = Look.from_bytes(bytes)
	expect(Look.valid_bytes(bytes) and other.items["hat"] == crown and same(other, worn), "the look the others get names the crown (bytes round trip)")
	key(KEY_E)
	await frames(2)
	await seconds(0.4)
	panel = booth.panel
	panel.select_tab(hat_tab)
	await frames(2)
	var on_tile := tile(panel, "item:hat", crown)
	expect(on_tile != null and on_tile.button_pressed, "the Hat tab offers the crown, picked")
	await _shot("crown_worn")
	var none_tile := tile(panel, "item:hat", "")
	none_tile.pressed.emit()
	await frames(2)
	expect(rig_look(0).items["hat"] == "" and not _hat_shown(shell.rigs[0]), "None takes the crown off the head")
	await _shot("crown_off")
	var cap_tile := tile(panel, "item:hat", "hat_cap")
	cap_tile.pressed.emit()
	await frames(2)
	expect(rig_look(0).items["hat"] == "hat_cap", "another hat replaces it")
	expect(tile(panel, "item:hat", crown) != null, "the crown stays on offer after it came off (it was won)")
	tile(panel, "item:hat", crown).pressed.emit()
	await frames(2)
	expect(rig_look(0).items["hat"] == crown and _hat_shown(shell.rigs[0]), "picking the crown puts it back on")
	tile(panel, "item:hat", "").pressed.emit()
	await frames(2)
	click(center(panel.find_child("Confirm", true, false)))
	await closed(booth)
	expect(Look.load_saved(0).items["hat"] == "" and Look.has_award(0, "crown") and Look.from_bytes(Look.load_saved(0).to_bytes()).items["hat"] == "", "confirmed without it: saved without the crown, still won, and the others get a look without it")
	Look.award(0, crown, rig_look(0)) # leave it won and worn for the next checks
	shell.rigs[0].set_look(Look.load_saved(0))

## `--shots=<dir>` (offscreen renderer only): the window as a picture.
func _shot(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			await seconds(0.8) # the thumbnails come in
			DirAccess.make_dir_recursive_absolute(arg.trim_prefix("--shots="))
			var image := root.get_texture().get_image()
			if image != null: image.save_png("%s/%s.png" % [arg.trim_prefix("--shots="), name])
			print("WARDROBE_CHECK shot ", name)

func _rng_seeded(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng

## The rig has a crown model among its head attachments.
func _hat_shown(rig: Node) -> bool:
	if not _real_rig(): return true
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) != null and (mesh.surface_get_material(0) as Material).resource_name == "crown_gold": return true
	return false

func _second_player_with_pad() -> void:
	shell.local_input.configure(1) # two pads: player 1 keyboard and pad 7, player 2 pad 8
	shell.pads = [7, 8]
	shell.actors[0].global_position = Layout.spawn(0)
	shell.actors[1].global_position = Layout.ORIGIN + Layout.wardrobe_center()
	await frames(2)
	expect(booth.probe().prompts == [1], "player 2 in the ring gets the prompt")
	pad_button(7, JOY_BUTTON_X)
	await frames(1)
	expect(not booth.probe().open, "player 1's pad cannot open it for player 2 (player 1 is not in the ring)")
	pad_button(8, JOY_BUTTON_X)
	await frames(1)
	expect(booth.probe().open and booth.probe().slot == 1 and booth.probe().seat == 1, "player 2's pad opens it for player 2")
	var before = rig_look(1)
	await _edit_something(booth.panel)
	pad_button(8, JOY_BUTTON_RIGHT_SHOULDER)
	await frames(1)
	expect(booth.panel.tab == 1, "the owner's RB moves to the next tab")
	pad_button(7, JOY_BUTTON_B)
	await frames(1)
	expect(booth.probe().open and not booth.probe().leaving, "the other player's B does nothing")
	pad_button(8, JOY_BUTTON_B)
	await closed(booth)
	expect(not booth.probe().open and same(rig_look(1), before) and not Look.has_saved(1), "the owner's B cancels")
	pad_button(8, JOY_BUTTON_X)
	await frames(2)
	await _edit_something(booth.panel)
	var final = booth.panel.look.duplicate_look()
	pad_button(8, JOY_BUTTON_START)
	await closed(booth)
	expect(not booth.probe().open and Look.has_saved(1) and same(Look.load_saved(1), final) and same(rig_look(1), final), "the owner's Start confirms: saved under seat 2")
	shell.actors[1].global_position = Layout.spawn(1)
	shell.local_input.configure(2)
	shell.pads = []

func _lobby_ends() -> void:
	shell.actors[0].global_position = Layout.ORIGIN + Layout.wardrobe_center()
	await frames(2)
	key(KEY_E)
	await frames(2)
	expect(booth.probe().open, "open once more")
	await _edit_something(booth.panel)
	shell.round_mode = "level"
	await frames(2)
	expect(not booth.probe().open and not shell.world.has_meta(Wardrobe.META), "the lobby ending closes it at once")
	expect(same(rig_look(0), Look.load_saved(0)), "the lobby ending puts the saved look back (nothing confirmed)")
	expect(root.get_camera_3d() == shell.camera, "the follow camera is back")
	shell.round_mode = "lobby"
	await frames(1)

func _new_character_wears_saved() -> void:
	var old: Node3D = shell.rigs[0]
	shell.rigs[0] = _make_rig(0)
	old.queue_free()
	await frames(2)
	expect(rig_look(0) != null and same(rig_look(0), Look.load_saved(0)), "a new character of player 1 wears the saved look")
	if shell.rigs[0].has_signal("look_applied"):
		shell.rigs[0].set_slot_tint(5) # online, every seat refresh tints the shirt with the seat colour
		await frames(2)
		expect(same(rig_look(0), Look.load_saved(0)), "a seat tint does not undo the saved shirt")

## Item pictures show the player's colours: the outfits' white cloth takes the shirt and pants colours.
func _check_picture_colors() -> void:
	var colors := {"shirt": Color("e5484d"), "pants": Color("3e63dd"), "shoes": Color("2b2b2b"), "skin": Color("dca07a")}
	var item := Catalog.item("outfit_hoodie")
	expect(Thumbs.key(item, colors) != Thumbs.key(item, {"shirt": Color.WHITE}), "a picture is kept per colours")
	for id: String in ["outfit_hoodie", "outfit_overalls"]:
		var file := Catalog.resolve(str(Catalog.item(id).get("file", "")))
		if file == "": continue
		var model: Node = (load(file) as PackedScene).instantiate()
		var count := Thumbs.tint(model, colors)
		var shown := []
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.get_surface_override_material_count():
				var material := mesh.get_surface_override_material(surface)
				if material is BaseMaterial3D: shown.append((material as BaseMaterial3D).albedo_color)
		expect(count > 0 and shown.any(func(color: Color) -> bool: return color in colors.values()), "%s's picture takes the player's colours (%d surfaces)" % [id, count])
		print("WARDROBE_CHECK picture colours ", id, " surfaces=", count)
		model.free()

## The real shell: boots the local game, Play with two pads (split screen), then the customizer in the lobby.
func _real_game() -> void:
	var game := VirtualLocal.new()
	game.pads = [7, 8]
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 180000
	while not game.is_network_ready() or game.local_presentation == null or not game.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			expect(false, "the local game boots")
			return
	var ui = game.local_presentation
	ui.show_local_job()
	ui.start_job()
	for _i in 60: await physics_frame
	var room: Node3D = game.world.get_node(LobbySpace.NAME)
	var real_booth: Node3D = room.get_node_or_null("Wardrobe")
	expect(real_booth != null and real_booth.simulation == game, "the real yard has the booth under the shell")
	if real_booth == null: return
	expect(game.local_views != null and game.local_views.active, "two pads: split screen")
	game.motions[0].teleport(game.actors[0], Layout.ORIGIN + Layout.wardrobe_center() + Vector3(0.0, 0.05, 0.0))
	for _i in 10: await physics_frame
	expect(real_booth.probe().prompts == [0], "the real game: player 1 in the ring gets the prompt (%s)" % [real_booth.probe()])
	key(KEY_E)
	await frames(2)
	expect(real_booth.probe().open, "the real game: E opens the customizer")
	expect(not game.local_input_enabled and game.world.has_meta(Wardrobe.META), "the real game: input pauses, wardrobe_open is set")
	expect(root.get_camera_3d() == real_booth.camera and not game.local_views.active, "the real game: the stage camera replaces the split views")
	expect(real_booth.camera.cull_mask == 1 << 18, "the real game: the stage shows only player 1's character (mask %d)" % real_booth.camera.cull_mask)
	var banner: CanvasLayer = ui.level_flow._level_hud
	await frames(3)
	expect(not banner.visible, "the real game: the lobby banner hides while the customizer is open")
	var lights: Array = real_booth.camera.find_children("Preview*", "DirectionalLight3D", false, false)
	expect(lights.size() == 3 and lights.all(func(light: DirectionalLight3D) -> bool: return light.light_cull_mask == 1 << 18 and not light.shadow_enabled), "the real game: key, fill and rim light only the character, no shadows")
	var key_light: DirectionalLight3D = real_booth.camera.get_node("PreviewKey")
	var toward_viewer := -key_light.global_basis.z.dot(real_booth.camera.global_basis.z)
	expect(toward_viewer < 0.0, "the real game: the key light shines from the camera's side onto the character")
	var held: Vector3 = game.actors[0].global_position
	_hold_key(KEY_W, true) # walking keys do not move the courier while it is open
	for _i in 30: await physics_frame
	_hold_key(KEY_W, false)
	expect(game.actors[0].global_position.distance_to(held) < 0.05, "the real game: the courier holds still")
	var original = game.rigs[0].get_look()
	await _edit_something(real_booth.panel)
	expect(same(game.rigs[0].get_look(), real_booth.panel.look), "the real game: the character wears the edit")
	key(KEY_ESCAPE)
	await closed(real_booth)
	await frames(2)
	expect(not real_booth.probe().open and game.local_input_enabled and not game.world.has_meta(Wardrobe.META), "the real game: Escape closes, input is back")
	expect(game.local_views.active, "the real game: the split views are back")
	expect(banner.visible, "the real game: the lobby banner is back")
	expect(same(game.rigs[0].get_look(), original), "the real game: Escape put the look back")
	var before: Vector3 = game.actors[0].global_position
	_hold_key(KEY_W, true)
	for _i in 30: await physics_frame
	_hold_key(KEY_W, false)
	expect(game.actors[0].global_position.distance_to(before) > 0.3, "the real game: the same key walks again once it is closed")
	print("WARDROBE_CHECK real game done")
	game.queue_free()
	await frames(2)
