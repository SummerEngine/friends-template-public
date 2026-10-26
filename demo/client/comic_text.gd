extends Control
## Display words in the clean UI type (Inter ExtraBold, OFL): flat fill, no outline, no shadow. A word may sit on its
## own flat plate (set_plate: a soft rounded rect, the HUD's chips), which is part of the control's size.
##
##   var title := ComicText.make("SETTINGS", 72.0)          # cap height 72 px, centred in whatever width it gets
##   title.set_text("PAUSED")                               # re-use
##   title.set_tint(Color(0.8, 0.9, 1.0))                   # multiply (e.g. dim a disabled button)
##   title.set_plate(Color("15161a"))                       # a dark chip behind the word (alpha 0 = none)
##
## The control's minimum size is the word at that cap height (plus the plate's padding): width = advances, height = the
## cap height. Lower-case is drawn as capitals: display words are set in caps.
##   word.set_tabular(true)                # digits share one advance cell (clocks)
##   word.set_focus(true)                  # a few percent larger (animated); the fill turns focus_fill when one is set
##   word.set_press(true)                  # the word shrinks a little
## set_edge / set_shadow store their values only: the clean look draws neither. The menus' lettering is the kit's (`kit` true, set_kit): Lilita One, slanted, a dark outline and an extrusion
## under the letters (style/menu_kit.gd), in the fill / edge / deep colours of the plate it sits on.
const Ui := preload("res://client/friends_ui.gd")
const LILITA := preload("res://assets/fonts/LilitaOne-Regular.ttf") ## the show's display font (ShowTheme.font(); not preloaded from there: ShowTheme reaches this file through the touch controls)
static var DISPLAY: Font = Ui.DISPLAY
## Inter: OS/2 sCapHeight 1490 of 2048 units.
const CAP_RATIO := 0.7275
const SPACE_ADVANCE := 0.26   # in cap heights
## Colours: resting fill (near-black ink), the lit fill (the accent).
const INK := Ui.INK
const FILL := Ui.INK
static var FOCUS_FILL: Color = Ui.ACCENT
const FOCUS_SCALE := 0.04   # grows by this share when focused
const PRESS_SCALE := 0.03   # shrinks by this share while pressed
## Default letter spacing in cap heights (caps in Inter want a little air).
const TRACKING := 0.04
## Plate padding around the word, in cap heights (x: each side, y: top and bottom).
const PLATE_PAD := Vector2(0.62, 0.5)
var text := ""
var cap_height := 48.0
var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
## Extra spacing between letters in cap heights.
var tracking := 0.0
var tint := Color.WHITE
## Resting fill colour (set_fill).
var fill_color := FILL
## Fill of a focused word; alpha 0 keeps the resting fill.
var focus_fill := Color(0, 0, 0, 0)
## Set by set_edge (never drawn).
var edge_color := Color(0, 0, 0, 0)
var edge_width := 0.0
var shadow_color := Color(0, 0, 0, 0)
var shadow_offset := 0.0
## The kit's lettering (menus): Lilita One, a dark outline and an extrusion, slanted. Off for the HUD's own chips.
var kit := false
var kit_edge := Color("2a1062")
var kit_deep := Color(0, 0, 0, 0)
var kit_slant := 0.2
## How far a pressed word drops, px (the plate's lip: style/menu_kit.gd).
var press_drop := 0.0
const KIT_CAP := 0.69 ## Lilita One's cap height over its em (ShowTheme.CAP)
const KIT_EDGE := 0.17 ## outline width in cap heights
const KIT_DEPTH := 0.11 ## extrusion depth in cap heights
## The word's own plate: colour (alpha 0 = none) and padding in cap heights.
var plate_color := Color(0, 0, 0, 0)
var plate_pad := PLATE_PAD
## 0..1: how much the word is "lit" (set_focus / set_press animate it).
var focus_amount := 0.0
var press_amount := 0.0
## 0..1 underline bar under the word (tabs: the chosen one).
var underline_amount := 0.0
## Digits share one advance cell (the widest digit) so a ticking clock never jitters.
var tabular := false
var _runs: Array[Dictionary] = []   # {s, x}
var _width := 0.0
var _focus_tween: Tween

## A key: a flat white cap with a hairline, `label` in the display type on it. One character gives the square 1u key,
## longer labels (ESC, SPACE, TAB, SHIFT, LB) the wide key. `height_px` is the whole key's height; the control's size is
## the key's box. Call set_held(true) while the key is down (it turns the accent); set_lit(true) tints it pale accent.
##   var key := ComicText.keycap("Q", 40.0)   # or Script.call("keycap", "Q", 40.0) from another script
static func keycap(label: String, height_px: float) -> Control:
	return KeyCap.new(label, height_px)

static func make(word: String, height_px: float, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, lettering := false) -> Control:
	var node := (load("res://client/comic_text.gd") as GDScript).new() as Control
	node.set("align", alignment)
	node.set("cap_height", height_px)
	node.set("kit", lettering)
	node.call("set_text", word)
	return node

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_text(value: String) -> void:
	text = value
	_relayout()

func set_cap_height(value: float) -> void:
	cap_height = value
	_relayout()

func set_fill(value: Color) -> void:
	fill_color = value
	queue_redraw()

func set_tint(value: Color) -> void:
	tint = value
	queue_redraw()

## Stores the outline values only: the clean look draws no outline.
func set_edge(color: Color, width := -1.0) -> void:
	edge_color = color
	if width >= 0.0: edge_width = width

## Stores the shadow values only: the clean look draws no shadow.
func set_shadow(color: Color, offset := 0.0) -> void:
	shadow_color = color
	shadow_offset = offset

## The kit's lettering: Lilita One in `fill`, a dark outline in `edge`, an extrusion in `deep` (alpha 0 = none), slanted by `slant` (0.2 = the HUD's italic). Re-flows the word (another font, other widths).
func set_kit(fill: Color, edge: Color, deep := Color(0, 0, 0, 0), slant := 0.2) -> void:
	var was := kit
	kit = true
	fill_color = fill
	kit_edge = edge
	kit_deep = deep
	kit_slant = slant
	if not was: _relayout()
	else: queue_redraw()

## A flat rounded plate behind the word (alpha 0 = none); `pad` in cap heights. The plate is part of the control's size.
func set_plate(color: Color, pad := PLATE_PAD) -> void:
	var had := plate_color.a > 0.0
	plate_color = color
	plate_pad = pad
	if had != (color.a > 0.0): _relayout()
	else: queue_redraw()

## Lit word for keyboard/gamepad focus and mouse hover: a few percent larger (and focus_fill when set). Animated over
## 0.14 s. Drawn without changing the control's size, so layouts do not move.
func set_focus(on: bool, animate := true) -> void:
	_animate("focus_amount", 1.0 if on else 0.0, animate)

## Pressed (touch down / mouse down): the word shrinks a little.
func set_press(on: bool, animate := true) -> void:
	_animate("press_amount", 1.0 if on else 0.0, animate)

## Underline bar under the word, 0..1 (the chosen tab).
func set_underline(amount: float) -> void:
	underline_amount = amount
	queue_redraw()

func _animate(property: String, target: float, animate: bool) -> void:
	if absf(float(get(property)) - target) < 0.001: return
	if _focus_tween != null and _focus_tween.is_valid() and property == "focus_amount": _focus_tween.kill()
	if not animate or not is_inside_tree():
		set(property, target)
		queue_redraw()
		return
	var step := create_tween()
	step.tween_method(func(value: float) -> void:
		set(property, value)
		queue_redraw(), float(get(property)), target, 0.14)
	if property == "focus_amount": _focus_tween = step

func set_tabular(on: bool) -> void:
	tabular = on
	_relayout()

func set_tracking(value: float) -> void:
	tracking = value
	_relayout()

## Width the word takes at this cap height.
func text_width() -> float:
	return _width

## Pixels the word reaches past its box (the focus growth, and the kit's outline and extrusion).
func bleed_px() -> float:
	var bleed := cap_height * (FOCUS_SCALE if focus_amount > 0.01 else 0.0)
	if kit: bleed += cap_height * (KIT_EDGE * 0.5 + (KIT_DEPTH if kit_deep.a > 0.0 else 0.0) + kit_slant * 0.5)
	return bleed

## Width of `text` in px per px of cap height (layout is linear in the cap height), cached. Lets a group of words pick
## one common cap height from its widest word without building the nodes.
static var _unit_widths: Dictionary = {}
static func unit_width(word: String, letter_tracking := 0.0, lettering := false) -> float:
	var key := "%s|%.3f|%s" % [word, letter_tracking, lettering]
	if _unit_widths.has(key): return _unit_widths[key]
	var probe := make(word, 100.0, HORIZONTAL_ALIGNMENT_LEFT, lettering)
	if letter_tracking != 0.0: probe.call("set_tracking", letter_tracking)
	var result := maxf(float(probe.call("text_width")) / 100.0, 0.001)
	probe.free()
	_unit_widths[key] = result
	return result

## The lettering is drawn as a child of the control whose text it replaces, so that control (and any ancestor) must not
## clip: a Label with clip_text or an overrun mode, or any clip_contents, cuts the focused word at the control's own rect. A clipped Label also has no minimum width; the same layout is kept with one wrapped line (autowrap,
## max_lines_visible 1), which hides nothing it did not hide before.
static func unclip(control: Control) -> void:
	if control.clip_contents: control.clip_contents = false
	if control is Label:
		var label := control as Label
		if label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			label.clip_text = false
			label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.max_lines_visible = 1
	elif control is Button:
		var button := control as Button
		if button.clip_text or button.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
			button.clip_text = false
			button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

## Debug guard: the first time the word is drawn, warn (once) when an ancestor that clips cuts into the word.
var _clip_checked := false
func _check_clipping() -> void:
	if not OS.is_debug_build() or size.x < 1.0 or not is_inside_tree(): return
	var bleed := bleed_px()
	var mine := get_global_transform() * Rect2(Vector2.ZERO, size).grow(bleed)
	var node := get_parent()
	while node is Control:
		var ancestor := node as Control
		var clips := ancestor.clip_contents
		if ancestor is Label: clips = clips or (ancestor as Label).clip_text or (ancestor as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
		if clips:
			var box := ancestor.get_global_transform() * Rect2(Vector2.ZERO, ancestor.size)
			if not box.grow(0.5).encloses(mine):
				push_warning("ComicText '%s' (cap %.0f) is cut: %s clips %.1f px inside the word's reach" % [text, cap_height, ancestor.get_path(), bleed])
				return
		node = node.get_parent()

# ------------------------------------------------------------------ layout

func _font() -> Font:
	return LILITA if kit else DISPLAY

func _font_size() -> int:
	return maxi(int(round(cap_height / (KIT_CAP if kit else CAP_RATIO))), 1)

func _advance(piece: String) -> float:
	return _font().get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size()).x

func _digit_advance() -> float:
	var widest := 0.0
	for digit in "0123456789": widest = maxf(widest, _advance(digit))
	return widest

func _relayout() -> void:
	_runs.clear()
	var shown := text.to_upper()
	var gap := (TRACKING + tracking) * cap_height
	if tabular or tracking != 0.0:
		# One run per character: tabular digits take the widest digit's cell, the rest advance by their own width.
		var pen := 0.0
		var cell := _digit_advance() if tabular else 0.0
		for index in shown.length():
			var ch := shown[index]
			if ch == " ":
				pen += SPACE_ADVANCE * cap_height + gap
				continue
			var advance := _advance(ch)
			var inset := 0.0
			if tabular and ch >= "0" and ch <= "9":
				inset = (cell - advance) * 0.5
				advance = cell
			_runs.append({"s": ch, "x": pen + inset})
			pen += advance + gap
		_width = maxf(pen - gap, 0.0)
	else:
		# Whole words keep the font's own kerning; only the word space is ours.
		var pen := 0.0
		var words := shown.split(" ")
		for index in words.size():
			if words[index] != "":
				_runs.append({"s": words[index], "x": pen})
				pen += _advance(words[index]) + words[index].length() * gap
			if index < words.size() - 1: pen += SPACE_ADVANCE * cap_height + gap
		_width = maxf(pen - (gap if shown != "" else 0.0), 0.0)
	custom_minimum_size = Vector2(ceilf(_width), ceilf(cap_height)) + _plate_margin() * 2.0
	update_minimum_size()
	queue_redraw()

## Padding the plate adds on each side, in px (zero without a plate).
func _plate_margin() -> Vector2:
	return Vector2(ceilf(plate_pad.x * cap_height), ceilf(plate_pad.y * cap_height)) if plate_color.a > 0.0 else Vector2.ZERO

func _draw() -> void:
	if _runs.is_empty(): return
	if not _clip_checked:
		_clip_checked = true
		_check_clipping.call_deferred()
	var margin := _plate_margin()
	var inner := Rect2(margin, size - margin * 2.0)
	var origin_x := inner.position.x
	match align:
		HORIZONTAL_ALIGNMENT_LEFT: origin_x = inner.position.x
		HORIZONTAL_ALIGNMENT_RIGHT: origin_x = inner.end.x - _width
		_: origin_x = inner.position.x + (inner.size.x - _width) * 0.5
	var font_size := _font_size()
	# The cap band sits between the baseline and CAP_RATIO of the em above it: centre it on the control.
	var baseline := (size.y + cap_height) * 0.5 - press_amount * press_drop
	var lit := focus_amount
	var grow := 1.0 + FOCUS_SCALE * lit - PRESS_SCALE * press_amount
	var shear := kit_slant if kit else 0.0
	# Scale about the control's centre: the layout never moves (the kit's words also lean: a shear about the baseline).
	var centre := size * 0.5
	var lean := Transform2D(Vector2(1.0, 0.0), Vector2(-shear, 1.0), Vector2(shear * baseline, 0.0))
	var grow_transform := Transform2D(0.0, Vector2(grow, grow), 0.0, centre * (1.0 - grow))
	if grow != 1.0: draw_set_transform_matrix(grow_transform)
	if plate_color.a > 0.0:
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(plate_color.r, plate_color.g, plate_color.b, plate_color.a * tint.a)
		plate.set_corner_radius_all(int(round(minf(size.y * 0.5, cap_height * 0.55))))
		plate.corner_detail = 10
		plate.anti_aliasing = true
		if kit: # the show's pills carry a thin light outline
			plate.border_color = Color(1.0, 1.0, 1.0, 0.55 * tint.a)
			plate.set_border_width_all(maxi(roundi(cap_height * 0.09), 1))
		draw_style_box(plate, Rect2(Vector2.ZERO, size))
	if shear != 0.0: draw_set_transform_matrix(grow_transform * lean)
	var fill := fill_color.lerp(focus_fill, lit) if lit > 0.0 and focus_fill.a > 0.0 else fill_color
	if tint != Color.WHITE: fill = Color(fill.r * tint.r, fill.g * tint.g, fill.b * tint.b, fill.a * tint.a)
	var font := _font()
	var deep := Color(kit_deep.r, kit_deep.g, kit_deep.b, kit_deep.a * tint.a)
	var edge := Color(kit_edge.r * tint.r, kit_edge.g * tint.g, kit_edge.b * tint.b, kit_edge.a * tint.a)
	for run in _runs:
		var at := Vector2(origin_x + float(run.x), baseline)
		if kit:
			var edge_px := maxi(roundi(cap_height * KIT_EDGE), 1)
			if deep.a > 0.0:
				var steps := maxi(roundi(cap_height * KIT_DEPTH), 1)
				for step in range(steps, 0, -1):
					var down := at + Vector2(0.0, float(step))
					draw_string_outline(font, down, String(run.s), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, edge_px, deep)
					draw_string(font, down, String(run.s), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, deep)
			if edge.a > 0.0: draw_string_outline(font, at, String(run.s), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, edge_px, edge)
		draw_string(font, at, String(run.s), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill)
	if underline_amount > 0.01:
		var thick := maxf(cap_height * 0.09, 2.0)
		var line_y := baseline + cap_height * 0.32
		var bar := StyleBoxFlat.new()
		bar.bg_color = Color(FOCUS_FILL, underline_amount * tint.a)
		bar.set_corner_radius_all(int(ceilf(thick * 0.5)))
		draw_style_box(bar, Rect2(origin_x, line_y, _width, thick))
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()


# ------------------------------------------------------------------ keycap

class KeyCap extends Control:
	const WIDE_MIN := 1.2
	## Where the label's cap band is centred, as a share of the key height.
	const FACE_CENTRE := 0.5
	const LABEL_CAP := 0.36
	var key_height := 40.0
	var held := 0.0
	var lit := 0.0
	## Extra dark rim around the key in key heights (0 = none): touch buttons over a bright 3D frame (see fit()).
	var rim := 0.0
	var label_centre := FACE_CENTRE
	var _label: Control
	var _is_wide := false
	var _key_width := 0.0

	func _init(text: String, height_px: float) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_height = height_px
		_label = (load("res://client/comic_text.gd") as GDScript).call("make", text, height_px * LABEL_CAP, HORIZONTAL_ALIGNMENT_CENTER)
		_label.set_fill(Ui.INK)
		add_child(_label)
		_is_wide = text.length() > 1
		var word_width: float = _label.text_width()
		_key_width = maxf(height_px * WIDE_MIN, word_width + height_px * 0.7) if _is_wide else height_px
		custom_minimum_size = Vector2(ceilf(_key_width), ceilf(height_px))
		size = custom_minimum_size
		_place()

	func set_label(text: String) -> void:
		if _label.text == text: return
		_label.set_text(text)
		_place()

	## Touch buttons: the key is exactly `box`, the label is `cap_share` of the box height tall (shrunk until it fits
	## the face) and centred `centre` of the way down.
	func fit(box: Vector2, cap_share: float, centre: float) -> void:
		key_height = box.y
		_key_width = box.x
		_is_wide = box.x > box.y * WIDE_MIN
		custom_minimum_size = box
		size = box
		label_centre = centre
		var cap := box.y * cap_share
		_label.set_cap_height(cap)
		var room := box.x * 0.72
		if _label.text_width() > room: _label.set_cap_height(cap * room / _label.text_width())
		_place()
		queue_redraw()

	## Key down: turns the accent.
	func set_held(on: bool) -> void:
		_animate("held", 1.0 if on else 0.0)

	## Pale accent only.
	func set_lit(on: bool) -> void:
		_animate("lit", 1.0 if on else 0.0)

	func _animate(property: String, target: float) -> void:
		if absf(float(get(property)) - target) < 0.001: return
		if not is_inside_tree():
			set(property, target)
			_place()
			queue_redraw()
			return
		var step := create_tween()
		step.tween_method(func(value: float) -> void:
			set(property, value)
			_place()
			queue_redraw(), float(get(property)), target, 0.1)

	func _place() -> void:
		_label.size = _label.custom_minimum_size
		_label.position = Vector2((_key_width - _label.size.x) * 0.5, key_height * label_centre - _label.size.y * 0.5)
		_label.set_fill(Ui.INK.lerp(Ui.ON_ACCENT, held))

	func _draw() -> void:
		var radius := int(key_height * 0.2)
		if rim > 0.0:
			var halo := StyleBoxFlat.new()
			halo.bg_color = Color(Ui.INK, 0.55)
			halo.set_corner_radius_all(radius + int(key_height * rim))
			halo.anti_aliasing = true
			draw_style_box(halo, Rect2(Vector2(-key_height * rim, -key_height * rim), Vector2(_key_width, key_height) + Vector2.ONE * key_height * rim * 2.0))
		var cap := StyleBoxFlat.new()
		cap.bg_color = Ui.WHITE.lerp(Ui.YELLOW, lit).lerp(Ui.ACCENT, held)
		cap.border_color = Color(Ui.INK, 0.14)
		cap.set_border_width_all(maxi(int(round(key_height * 0.03)), 1))
		cap.set_corner_radius_all(radius)
		cap.corner_detail = 10
		cap.anti_aliasing = true
		draw_style_box(cap, Rect2(Vector2.ZERO, Vector2(_key_width, key_height)))
