extends RefCounted
## The menus' controls, in the candy menu look (style/menu_kit.gd): chunky plates with a white rim, a thick bevel and a drop shadow, Lilita One lettering with a dark outline, the primary's pink and green accents on deep violet tracks.
## Pickers, toggles and sliders subclass the stock OptionButton/CheckBox/HSlider so every existing caller and probe keeps the same widget API (select/item_selected, button_pressed/toggled, value),
## while the engine's own drawing is emptied and replaced by vector drawing.
##   Picker       a deep violet segmented track with a primary-coloured pill that slides to the chosen word (a carousel with chunky cyan arrows for a long list)
##   Toggle       a chunky switch: green with a big round knob when ON, light violet when OFF, ON / OFF in lettering
##   ComicSlider  a thick deep violet track with a primary-coloured fill and a round white knob that swells when focused
##   KeyHints     the bottom row of cream keycaps and their captions
const Ui := preload("res://client/friends_ui.gd")
const Kit := preload("res://style/menu_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const ComicText := preload("res://client/comic_text.gd")
const Lettering := preload("res://client/menu_skin.gd")

## What the controls share: cached plates, the dark track, lettering and the dimming of a disabled control.
class Looks:
	static var _plates := {}
	static var _tracks := {}
	static var _ring: StyleBox
	const MUTED_WORD := Color("d9ccff")
	const SHADOW := Color(0.16, 0.04, 0.3, 0.42)

	## A Chunk plate of a kit role.
	static func plate(role_name: String, state := "normal") -> StyleBox:
		var key := role_name + "|" + state
		if not _plates.has(key): _plates[key] = Kit.style(role_name, state)
		return _plates[key]

	## The cream keycap plate.
	static func cap_plate() -> StyleBox:
		if not _plates.has("cap"): _plates["cap"] = Kit.Chunk.new(Kit.role("cream"))
		return _plates["cap"]

	## The deep violet channel a switch / slider / picker runs in, the thin light outline.
	static func track(radius: float) -> StyleBoxFlat:
		var key := int(radius)
		if not _tracks.has(key):
			var box := StyleBoxFlat.new()
			box.bg_color = Color(Kit.VIOLET_DEEP, 0.96)
			box.border_color = Color(1, 1, 1, 0.6)
			box.set_border_width_all(2)
			box.set_corner_radius_all(key)
			box.corner_detail = 12
			box.anti_aliasing = true
			_tracks[key] = box
		return _tracks[key]

	## The keyboard / pad focus ring that hugs a control.
	static func ring() -> StyleBox:
		if _ring == null: _ring = Kit.focus_ring(3.0, 3)
		return _ring

	## Lettering at cap height `cap`, centred on `centre`: fill, dark outline, an extrusion when `deep` has alpha, the show's lean.
	static func word(ci: CanvasItem, words: String, centre: Vector2, cap: float, fill: Color, edge := Kit.EDGE, deep := Color(0, 0, 0, 0), alpha := 1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
		ShowTheme.text(ci, words, centre, cap / ShowTheme.CAP, fill, edge, maxf(cap * 0.17, 1.5), deep, cap * 0.11, 1.0, 0.0, ShowTheme.SLANT, alpha, align)

	## Width of the word at cap height `cap`.
	static func width(words: String, cap: float) -> float:
		return ShowTheme.width(words, cap / ShowTheme.CAP) * (1.0 + ShowTheme.SLANT * 0.1)

	## A disabled control is drawn dim.
	static func dim(control: CanvasItem, off: bool) -> void:
		var want := 0.45 if off else 1.0
		if not is_equal_approx(control.self_modulate.a, want): control.self_modulate = Color(1, 1, 1, want)

	## A chunky round knob (shadow, white rim, a white face with a shine) of radius `r` at `at`.
	static func knob(ci: CanvasItem, at: Vector2, r: float, face := Color("ffffff"), low := Color("d9ccff"), line := Color("2a1062")) -> void:
		ci.draw_circle(at + Vector2(0.0, r * 0.32), r * 1.02, SHADOW, true, -1.0, true)
		ci.draw_circle(at + Vector2(0.0, r * 0.16), r, line, true, -1.0, true)
		ci.draw_circle(at + Vector2(0.0, r * 0.08), r * 0.8, low, true, -1.0, true)
		ci.draw_circle(at, r * 0.8, face, true, -1.0, true)
		ci.draw_circle(at + Vector2(-r * 0.16, -r * 0.24), r * 0.42, Color(1, 1, 1, 0.55), true, -1.0, true)

# ====================================================================== Picker
## One focus stop. Left/right step, click or tap picks. Up to four short options draw
## as a segmented track with a sliding pill; longer lists as a carousel.
## It stays an OptionButton for the item API (add_item/select/item_selected) that
## settings code and probes use, but the built-in popup is unreachable: _gui_input runs
## before the engine's BaseButton.gui_input and consumes every event that would press
## it. Summer's BaseButton presses on InputEventScreenTouch itself (not only on the
## mouse emulated from it), which is how a phone tap opened the list.
class Picker extends OptionButton:
	var _pill_x := 0.0
	var _pill_w := 0.0
	var _velocity := 0.0
	var _placed := false
	var _hover := -1
	var _shown := -2
	var _segments: Array[Rect2] = []

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		fit_to_longest_item = false
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(320, 42)
		Ui.hide_engine_drawing(self, "OptionButton")
		mouse_entered.connect(func() -> void: if not disabled: grab_focus())
		mouse_exited.connect(func() -> void: _hover = -1; queue_redraw())
		focus_entered.connect(func() -> void:
			z_index = 2 # the ring draws over the neighbours
			Ui.play(self, &"hover"))
		focus_exited.connect(func() -> void: z_index = 0)
		resized.connect(_measure)

	## Cap height of the words: a share of the plate's face.
	func _cap() -> float:
		return clampf(Kit.Chunk.face_middle(size.y - 6.0) * 2.0 * 0.47, 11.0, 22.0)

	func _pad() -> float:
		return _cap() * 2.2

	func carousel() -> bool:
		if item_count > 4: return true
		var need := 0.0
		for index in item_count:
			need += Looks.width(get_item_text(index).to_upper(), _cap()) + _pad()
		return need > size.x - 8.0

	func _measure() -> void:
		_segments.clear()
		if item_count == 0 or carousel(): return
		var widths: Array[float] = []
		var total := 0.0
		for index in item_count:
			var w := Looks.width(get_item_text(index).to_upper(), _cap()) + _pad()
			widths.append(w)
			total += w
		var spare := maxf(0.0, size.x - 8.0 - total) / item_count
		var x := 4.0
		for w in widths:
			_segments.append(Rect2(x, 3, w + spare, size.y - 6.0))
			x += w + spare
		_placed = false
		queue_redraw()

	func choose(index: int) -> void:
		if disabled or item_count == 0: return
		index = wrapi(index, 0, item_count) if carousel() else clampi(index, 0, item_count - 1)
		if index == selected: return
		select(index)
		item_selected.emit(index)
		Ui.play(self, &"toggle")
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if disabled: return
		if event.is_action_pressed("ui_left", true):
			choose(selected - 1); accept_event()
		elif event.is_action_pressed("ui_right", true):
			choose(selected + 1); accept_event()
		elif event.is_action_pressed("ui_accept"):
			choose(selected + 1 if carousel() else (selected + 1) % maxi(item_count, 1)); accept_event()
		elif event is InputEventMouseMotion:
			var at := _index_at(event.position)
			if at != _hover: _hover = at; queue_redraw()
			accept_event()
		elif event is InputEventScreenTouch:
			if event.pressed: _pick_at(event.position)
			accept_event()
		elif event is InputEventScreenDrag:
			accept_event()
		elif event is InputEventMouseButton:
			# The left click a finger emulates arrives after its ScreenTouch, which already picked.
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
				_pick_at(event.position)
			accept_event()

	func _pick_at(at: Vector2) -> void:
		if carousel(): choose(selected + (-1 if at.x < size.x * 0.5 else 1))
		else:
			var index := _index_at(at)
			if index >= 0: choose(index)

	func _index_at(at: Vector2) -> int:
		if carousel(): return 0 if at.x < size.x * 0.5 else 1
		for index in _segments.size():
			if _segments[index].has_point(Vector2(at.x, size.y * 0.5)): return index
		return -1

	func _process(delta: float) -> void:
		Looks.dim(self, disabled)
		if _segments.size() != item_count and not carousel(): _measure()
		if selected != _shown:
			_shown = selected
			queue_redraw()
		if _segments.is_empty() or selected < 0 or selected >= _segments.size(): return
		var target := _segments[selected]
		if not _placed:
			_pill_x = target.position.x; _pill_w = target.size.x; _placed = true
		var d := minf(delta, 0.05)
		_velocity += ((target.position.x - _pill_x) * 420.0 - _velocity * 32.0) * d
		_pill_x += _velocity * d
		_pill_w = lerpf(_pill_w, target.size.x, Ui.damp(18.0, d))
		if absf(target.position.x - _pill_x) > 0.2 or absf(_velocity) > 0.2: queue_redraw()

	func _draw() -> void:
		var h := size.y
		var track := Rect2(0.0, 0.0, size.x, h - 2.0)
		draw_style_box(Looks.track(track.size.y * 0.5), track)
		if has_focus() and not disabled: draw_style_box(Looks.ring(), track)
		var cap := _cap()
		var face_y := 3.0 + Kit.Chunk.face_middle(h - 6.0)
		if carousel():
			var value := get_item_text(selected).to_upper() if selected >= 0 else ""
			var arrow := h - 6.0
			var room := size.x - arrow * 2.0 - 16.0
			var word_cap := cap
			if Looks.width(value, word_cap) > room: word_cap = maxf(word_cap * room / Looks.width(value, word_cap), 8.0)
			Looks.word(self, value, Vector2(size.x * 0.5, face_y), word_cap, Color.WHITE)
			for side in [-1, 1]:
				var hot := (_hover == (0 if side < 0 else 1)) or has_focus()
				var plate := Rect2((3.0 if side < 0 else size.x - 3.0 - arrow), 3.0, arrow, arrow)
				draw_style_box(Looks.plate("plain", "hover" if hot else "normal"), plate)
				var c := Vector2(plate.get_center().x, 3.0 + Kit.Chunk.face_middle(arrow))
				var r := arrow * 0.2
				var s := float(side)
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * r * 0.9, 0.0), c + Vector2(-s * r * 0.7, -r), c + Vector2(-s * r * 0.7, r)]), Kit.EDGE)
			return
		if selected >= 0 and selected < _segments.size():
			draw_style_box(Looks.plate("chosen"), Rect2(_pill_x, 3.0, _pill_w, h - 6.0))
		var chosen_ink: Color = Kit.role("chosen").ink
		for index in _segments.size():
			var segment := _segments[index]
			var cover := clampf(1.0 - absf(segment.get_center().x - (_pill_x + _pill_w * 0.5)) / maxf(segment.size.x * 0.6, 1.0), 0.0, 1.0)
			if index == _hover and cover < 0.5:
				var lit := StyleBoxFlat.new()
				lit.bg_color = Color(1, 1, 1, 0.14)
				lit.set_corner_radius_all(int(segment.size.y * 0.5))
				lit.anti_aliasing = true
				draw_style_box(lit, Rect2(segment.position.x, segment.position.y, segment.size.x, segment.size.y - 3.0))
			var idle := Looks.MUTED_WORD.lerp(Color.WHITE, 0.6 if index == _hover else 0.0)
			Looks.word(self, get_item_text(index).to_upper(), Vector2(segment.get_center().x, face_y), cap, idle.lerp(chosen_ink, cover), Kit.EDGE.lerp(Kit.role("chosen").edge, cover), Color(Kit.role("chosen").deep, cover))

# ====================================================================== Toggle
## A chunky switch with ON/OFF in lettering on the free end; the CheckBox text sits beside it.
class Toggle extends CheckBox:
	var _knob := 0.0

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(130, 42)
		Ui.hide_engine_drawing(self, "CheckBox")
		mouse_entered.connect(func() -> void: if not disabled: grab_focus())
		focus_entered.connect(func() -> void:
			z_index = 2
			Ui.play(self, &"hover"))
		focus_exited.connect(func() -> void: z_index = 0)
		toggled.connect(func(_on: bool) -> void: Ui.play(self, &"toggle"))

	func _ready() -> void:
		_knob = 1.0 if button_pressed else 0.0

	func _gui_input(event: InputEvent) -> void:
		if disabled: return
		if event.is_action_pressed("ui_left", true) and button_pressed:
			button_pressed = false; accept_event()
		elif event.is_action_pressed("ui_right", true) and not button_pressed:
			button_pressed = true; accept_event()

	func _process(delta: float) -> void:
		Looks.dim(self, disabled)
		var target := 1.0 if button_pressed else 0.0
		if absf(_knob - target) > 0.002:
			_knob = lerpf(_knob, target, Ui.damp(18.0, minf(delta, 0.05)))
			queue_redraw()
		elif _knob != target:
			_knob = target; queue_redraw()

	func _draw() -> void:
		var h := size.y
		var wide := minf(size.x, maxf(h * 3.1, 96.0))
		var role_name := "go" if button_pressed else "tab"
		var face := Kit.Chunk.face_middle(h)
		var body := face * 2.0
		draw_style_box(Looks.plate(role_name), Rect2(0.0, 0.0, wide, h))
		if has_focus() and not disabled: draw_style_box(Looks.ring(), Rect2(0.0, 0.0, wide, h - Kit.Chunk.drop(h)))
		var r := body * 0.5 * 0.86
		var edge_pad := body * 0.5 - r + 3.0
		var left := edge_pad + r
		var right := wide - edge_pad - r
		var x := lerpf(left, right, _knob)
		# ON / OFF in the free half: it moves to the other end as the knob crosses.
		var free_left := (wide - r * 2.0) * 0.5
		var free_right := (wide + r * 2.0) * 0.5
		var word_x := lerpf(free_right, free_left, _knob)
		var spec: Dictionary = Kit.role(role_name)
		var cap := body * 0.36
		Looks.word(self, "ON" if button_pressed else "OFF", Vector2(word_x, face + 1.0), cap, spec.ink if button_pressed else Looks.MUTED_WORD, spec.edge, spec.deep)
		Looks.knob(self, Vector2(x, face), r)
		if text != "":
			Looks.word(self, text.to_upper(), Vector2(wide + 16.0, face), body * 0.4, Color.WHITE, Kit.EDGE, Color(0, 0, 0, 0), 1.0, HORIZONTAL_ALIGNMENT_LEFT)

# ====================================================================== Slider
## A thick deep violet track with a primary-coloured fill and a round chunky knob that swells when focused. `ticks`: how many marks under the track (0 = none).
class ComicSlider extends HSlider:
	var ticks := 0
	var _swell := 0.0
	var _grab := Vector2i.ZERO

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(240, 40)
		for state: String in ["slider", "grabber_area", "grabber_area_highlight", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var blank := Ui.blank_texture(Vector2i(2, 2))
		for icon: String in ["grabber", "grabber_highlight", "grabber_disabled", "tick"]:
			add_theme_icon_override(icon, blank)
		mouse_entered.connect(func() -> void: if editable: grab_focus())
		focus_entered.connect(func() -> void:
			z_index = 2
			Ui.play(self, &"hover"))
		focus_exited.connect(func() -> void: z_index = 0)
		value_changed.connect(func(_v: float) -> void: queue_redraw())
		resized.connect(_fit_grabber)

	## The radius of the knob at rest.
	func _radius() -> float:
		return clampf(size.y * 0.4, 12.0, 26.0)

	## The engine maps the mouse onto the range by the grabber's width: it is made as wide as the drawn knob.
	func _fit_grabber() -> void:
		var wide := maxi(roundi(_radius() * 2.0 * 1.15), 2)
		if _grab.x == wide: return
		_grab = Vector2i(wide, wide)
		var blank := Ui.blank_texture(_grab)
		for icon: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
			add_theme_icon_override(icon, blank)

	func _process(delta: float) -> void:
		Looks.dim(self, not editable)
		var target := 1.0 if has_focus() and editable else 0.0
		if absf(_swell - target) > 0.005:
			_swell = lerpf(_swell, target, Ui.damp(20.0, minf(delta, 0.05)))
			queue_redraw()
		elif _swell != target:
			_swell = target
			queue_redraw()

	func _draw() -> void:
		var ratio := clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)
		var y := size.y * 0.5
		var base := _radius()
		var r := base * (1.0 + 0.16 * _swell)
		var left := _grab.x * 0.5 if _grab.x > 0 else base
		var right := size.x - left
		var x := lerpf(left, right, ratio)
		var thick := clampf(size.y * 0.38, 12.0, 26.0)
		var track := Rect2(left - thick * 0.5, y - thick * 0.5, right - left + thick, thick)
		draw_style_box(Looks.track(thick * 0.5), track)
		var fill_wide := x - track.position.x + thick * 0.1
		if ratio > 0.0 and fill_wide > thick * 0.6:
			var fill := StyleBoxFlat.new()
			fill.bg_color = Kit.role("primary").face
			fill.set_corner_radius_all(int(thick * 0.5))
			fill.corner_detail = 10
			fill.anti_aliasing = true
			var inset := 2.5
			draw_style_box(fill, Rect2(track.position.x + inset, track.position.y + inset, fill_wide - inset, thick - inset * 2.0))
			var shine := StyleBoxFlat.new()
			shine.bg_color = Color(Kit.role("primary").top, 0.8)
			shine.set_corner_radius_all(int(thick * 0.25))
			shine.anti_aliasing = true
			draw_style_box(shine, Rect2(track.position.x + inset + thick * 0.3, track.position.y + inset + thick * 0.12, maxf(fill_wide - inset - thick * 0.6, 0.0), thick * 0.24))
		for tick in ticks:
			var tx := lerpf(left, right, float(tick) / float(maxi(ticks - 1, 1)))
			draw_rect(Rect2(tx - 1.5, y + thick * 0.5 + 4.0, 3.0, 5.0), Color(1, 1, 1, 0.35))
		if has_focus() and editable: draw_arc(Vector2(x, y + r * 0.1), r * 1.18 + 3.0, 0.0, TAU, 36, Kit.WHITE, 3.0, true)
		Looks.knob(self, Vector2(x, y - r * 0.1), r)

# ==================================================================== KeyHints
## Bottom row of keys and captions; switches to gamepad face buttons after pad input. No bar behind it.
## Rebuilt only when the entries, the pad/touch state or the size change.
class KeyHints extends Control:
	var entries: Array = []
	var _pad := false
	## Phones / the touch overlay: keyboard caps mean nothing there; every hinted action has an
	## on-screen button (READY, RESUME, Back, CLOSE MAP, the overlay), so the row is hidden.
	var _touch := false

	func _init(rows: Array = []) -> void:
		entries = rows
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_entries(rows: Array) -> void:
		entries = rows

	func _input(event: InputEvent) -> void:
		Ui.note_input(event)

	func _process(_delta: float) -> void:
		if _pad != Ui.using_gamepad:
			_pad = Ui.using_gamepad
		var touch := TouchControls.touch_hints(get_tree())
		if touch != _touch:
			_touch = touch
		_sync_row()

	func hidden_for_touch() -> bool:
		return _touch and not _pad

	## A cream keycap: a chunky plate, the key's name in ink lettering on its face.
	class Cap extends Control:
		var _word: Control

		func _init(label: String, height: float) -> void:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			var face := Kit.Chunk.face_middle(height)
			_word = ComicText.make(label, face * 2.0 * 0.4, HORIZONTAL_ALIGNMENT_CENTER, true)
			_word.call("set_kit", Kit.INK, Color(0, 0, 0, 0))
			var wide := height if label.length() <= 1 else maxf(height * 1.25, float(_word.call("text_width")) + height * 0.8)
			custom_minimum_size = Vector2(ceilf(wide), ceilf(height))
			size = custom_minimum_size
			_word.size = _word.custom_minimum_size
			_word.position = Vector2((wide - _word.size.x) * 0.5, face - _word.size.y * 0.5)
			add_child(_word)

		func _draw() -> void:
			draw_style_box(Looks.cap_plate(), Rect2(Vector2.ZERO, size))

	func _sync_row() -> void:
		var row := get_node_or_null("ComicHints") as Control
		if hidden_for_touch():
			if row != null:
				row.queue_free()
				remove_child(row)
			return
		var signature := "%s|%s|%d|%d" % [entries, _pad, roundi(size.x), roundi(size.y)]
		if row != null and row.get_meta(&"signature", "") == signature: return
		if row != null:
			row.queue_free()
			remove_child(row)
		row = Control.new()
		row.name = "ComicHints"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta(&"signature", signature)
		add_child(row)
		var key_height := size.y * 0.92
		var label_cap := size.y * 0.36
		var cells: Array[Array] = []   # [word, cap, gap after]
		for entry: Dictionary in entries:
			var keys: Array = entry.get("pad", []) if _pad else entry.get("keys", [])
			for index in keys.size():
				cells.append([String(keys[index]).to_upper(), -key_height, 8.0 if index < keys.size() - 1 else 14.0])
			cells.append([str(entry.label).to_upper(), label_cap, 30.0])
		var total := -30.0
		var made: Array[Control] = []
		for cell in cells:
			# A negative height marks a key: a keycap of that height; otherwise a caption.
			var item: Control
			if float(cell[1]) < 0.0: item = Cap.new(cell[0], -float(cell[1]))
			else:
				item = Lettering.word(cell[0], cell[1], 0.05)
				item.call("set_kit", Looks.MUTED_WORD, Kit.EDGE)
			made.append(item)
			total += item.custom_minimum_size.x + float(cell[2])
		var x := size.x - total - 6.0
		for index in made.size():
			var item := made[index]
			item.size = item.custom_minimum_size
			item.position = Vector2(x, (size.y - item.size.y) * 0.5)
			row.add_child(item)
			x += item.size.x + float(cells[index][2])

# ================================================================ PanelBurst
## The last menu frame leaves cleanly: it is captured, then fades out while it scales up a little, over whatever is
## behind. Purely presentational: callers change state first, then cover the cut.
class PanelBurst extends Control:
	var texture: Texture2D
	var origin := Vector2(640, 360)
	var clock := 0.0
	var duration := 0.45

	func _init(frame: Texture2D = null, from := Vector2(640, 360)) -> void:
		texture = frame
		origin = from
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		clock += minf(delta, 0.05)
		if clock >= duration: queue_free()
		queue_redraw()

	func _draw() -> void:
		if texture == null: return
		var t := clampf(clock / duration, 0.0, 1.0)
		var area := get_viewport_rect().size
		var grow := 1.0 + 0.04 * Ui.out_expo(t)
		var rect := Rect2(origin - origin * grow, area * grow)
		draw_texture_rect(texture, rect, false, Color(1, 1, 1, 1.0 - Ui.in_out(t)))

## Capture the current frame, then fade it out from `from` (canvas coordinates).
static func burst(context: Node, from: Vector2) -> void:
	if DisplayServer.get_name() == "headless": return
	var image := context.get_viewport().get_texture().get_image()
	if image == null or image.is_empty(): return
	var layer := CanvasLayer.new()
	layer.layer = 130
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	context.get_tree().root.add_child(layer)
	var effect := PanelBurst.new(ImageTexture.create_from_image(image), from)
	layer.add_child(effect)
	effect.tree_exited.connect(layer.queue_free)
	Ui.play(effect, &"start")
