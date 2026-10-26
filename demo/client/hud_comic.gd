extends RefCounted
## In-game words in the clean UI type: every HUD word is a ComicText (comic_text.gd: Inter ExtraBold, flat fill) on its
## own small flat plate, white on a near-black chip, so it reads over any part of the 3D scene without an outline.
## Celebrations sit on the team's accent, failures on red.
## Helpers here; the animated parts (clock, checkpoint word, stamp, key row) are in hud_comic_parts.gd.
##   HudComic.word("CHECKPOINT", 80.0)         a ComicText on a dark chip, sized for the HUD
##   HudComic.small("Long sentence ...", 22.0) a sentence (Inter SemiBold) on the same chip
const ComicText := preload("res://client/comic_text.gd")
const Ui := preload("res://client/friends_ui.gd")

## The chip behind a HUD word and a HUD sentence, and the type on it.
const INK := Color(0.075, 0.082, 0.105, 0.93) ## the show's pill colour (ShowTheme.PILL)
const PLATE := INK
const ON_PLATE := Ui.WHITE
## Not drawn: there is no outline or shadow.
const SHADOW := INK
const RIM := INK
const RIM_FAIL := INK
## Failure words (CRACK! / SPLASH!) and the last seconds of a timed run: the word on a red chip.
const TINT_FAIL := Ui.DANGER
## Sentence type colour (on the chip).
const SENTENCE_INK := Ui.WHITE
## Sentence chip padding in font sizes (x: each side, y: top and bottom).
const SENTENCE_PAD := Vector2(0.6, 0.32)

## HUD pixel scale from the viewport height (1.0 at 720).
static func unit_of(item: CanvasItem) -> float:
	return clampf(item.get_viewport_rect().size.y / 720.0, 0.72, 2.4)

## A HUD word: the kit's lettering (Lilita One, slanted, dark edge) on the show's dark pill with the thin light outline.
static func word(text: String, cap: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> ComicText:
	var node := ComicText.new()
	node.align = align
	node.cap_height = cap
	node.plate_color = PLATE
	node.kit = true
	node.fill_color = ON_PLATE
	node.kit_edge = Color("00051e")
	node.set_text(text)
	node.size = node.custom_minimum_size
	return node

## Re-set a word's cap height and text only when they changed (cheap to call every frame).
static func update(node: ComicText, text: String, cap: float) -> void:
	if absf(node.cap_height - cap) > 0.5: node.set_cap_height(cap)
	if node.text != text: node.set_text(text)
	node.size = node.custom_minimum_size

## A failure word: white on a red chip.
static func fail_style(node: ComicText) -> void:
	node.set_plate(TINT_FAIL, node.plate_pad)
	node.set_fill(Ui.WHITE)

## A celebration (LEVEL CLEARED, CHECKPOINT, the results stamp): the word on the show's gold.
static func accent_style(node: ComicText) -> void:
	node.set_plate(Color("fcd034"), node.plate_pad)
	node.set_kit(Color("fffaf0"), Color("a8570a"), Color("7c3d05"))

## Back to the plain dark chip.
static func plain_style(node: ComicText) -> void:
	node.set_plate(PLATE, node.plate_pad)
	node.set_fill(ON_PLATE)

## "65" seconds -> "01:05"; an hour or more -> "1:02:03".
static func clock_text(total: int) -> String:
	total = maxi(total, 0)
	if total >= 3600: return "%d:%02d:%02d" % [total / 3600, total / 60 % 60, total % 60]
	return "%02d:%02d" % [total / 60, total % 60]

## An Inter SemiBold Label for sentences that are too long for the display words: white on the HUD's dark chip.
## `width` > 0 wraps.
static func small(text: String, font_size: int, width := 0.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(label, font_size)
	if width > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = width
	return label

## Gives an existing Label the sentence treatment (Lilita One, white, on the show's dark pill with the thin light outline drawn behind its text); its size,
## text, wrapping and placement stay as they are. The chip hugs the text and hides with an empty label.
static func style_label(label: Label, font_size: int) -> void:
	ComicText.unclip(label)
	label.add_theme_font_override("font", ComicText.LILITA)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", SENTENCE_INK)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	if label.get_node_or_null("SentencePlate") == null:
		var plate := SentencePlate.new()
		plate.name = "SentencePlate"
		label.add_child(plate)

static var _bodies: Dictionary = {}
## Inter at a weight from 100 to 900 (a weight above 900 is drawn at 900).
static func body_font(weight := 600) -> Font:
	if not _bodies.has(weight):
		_bodies[weight] = Ui.inter(mini(weight, 900))
	return _bodies[weight]

## The dark chip behind a sentence Label: drawn behind the parent's text, hugging its lines, gone when the text is empty.
class SentencePlate extends Control:
	var _key := ""

	func _init() -> void:
		show_behind_parent = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		var label := get_parent() as Label
		if label == null: return
		var key := "%s|%s|%s|%s" % [label.text, label.size, label.get_theme_font_size("font_size"), label.get_meta("plate", PLATE)]
		if key != _key:
			_key = key
			queue_redraw()

	func _draw() -> void:
		var label := get_parent() as Label
		if label == null or label.text.strip_edges() == "": return
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var wraps := label.autowrap_mode != TextServer.AUTOWRAP_OFF
		var lines := maxi(label.get_visible_line_count(), 1)
		var line_height := font.get_height(font_size) + label.get_theme_constant("line_spacing")
		var text_size := font.get_multiline_string_size(label.text, label.horizontal_alignment, label.size.x if wraps else -1.0, font_size)
		var box := Vector2(minf(text_size.x, label.size.x) if wraps else text_size.x, line_height * lines)
		var x := 0.0
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER: x = (label.size.x - box.x) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT: x = label.size.x - box.x
		var y := (label.size.y - box.y) * 0.5
		match label.vertical_alignment:
			VERTICAL_ALIGNMENT_TOP: y = 0.0
			VERTICAL_ALIGNMENT_BOTTOM: y = label.size.y - box.y
		var pad := SENTENCE_PAD * float(font_size)
		var plate := StyleBoxFlat.new()
		plate.bg_color = label.get_meta("plate", PLATE) # a label may carry its own chip colour (the show's scoreboard: the player's colour)
		plate.set_corner_radius_all(int(round(minf(box.y * 0.5 + pad.y, font_size * 0.7))))
		plate.corner_detail = 10
		plate.anti_aliasing = true
		plate.border_color = Color(1.0, 1.0, 1.0, 0.55) # the show's pills carry a thin light outline
		plate.set_border_width_all(maxi(int(round(float(font_size) * 0.07)), 1))
		draw_style_box(plate, Rect2(Vector2(x, y) - pad, box + pad * 2.0))
