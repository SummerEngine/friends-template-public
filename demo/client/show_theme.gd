extends RefCounted
## The show's one look (every HUD piece, banner and card of the show draws with this): dark rounded pills with a thin light outline, bold slanted
## white display type (Lilita One, OFL) with a dark outline, chunky extruded digits, spiky yellow-orange badges.
## All helpers are static and draw into the CanvasItem they are given (call them from its `_draw`), so a piece is one control with one draw routine.
##   ShowTheme.pill(self, rect)                                   a dark pill with the light outline
##   ShowTheme.pill_words(self, "Words", right, middle, height)   a pill with slanted words centred in it
##   ShowTheme.text(self, "WORDS", centre, size, fill, edge, ...) outlined, extruded, slanted display words
##   ShowTheme.badge(self, centre, half, ...)                     the spiky badge (VICTORY and family: style/show_banner.gd)
## Layout: `unit(item)` is the pixel scale of the screen (1.0 at 720 high, 0.54 at a phone's 390).
const Ui := preload("res://client/friends_ui.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const TeamCast := preload("res://style/team_cast.gd")

const FONT_FILE := preload("res://assets/fonts/LilitaOne-Regular.ttf")
## Lilita One: cap height over the em (OS/2 sCapHeight 1409 of 2048 is about 0.69; measured with the glyph "H").
const CAP := 0.69
const SLANT := 0.2 ## the shear of the italic words
const PILL := Color(0.075, 0.082, 0.105, 0.93) ## the dark pill
const PILL_EDGE := Color(1.0, 1.0, 1.0, 0.55) ## its thin light outline
const BLUE := Color("3d7bff") ## the show's blue (a lobby circle's band, an ordinal's colour; the menu kit's "blue" plate)
const GOLD := Color("f2b632")
const GOLD_DEEP := Color("c9731a")
const YELLOW := Color("f7c312")
const ORANGE := Color("e0870c")
const ORANGE_DEEP := Color("8a4a06")
const CREAM := Color("f6f0e0")
const MINT := Color("86f0c6") ## GOAL's letters, the countdown's digits
const MINT_DEEP := Color("2f9f86")
const PURPLE := Color("6c4cd6")
const NAVY := Color("00051e")
const RED := Color("e5484d")
const GREY := Color("a3a3a1")
const GREY_DEEP := Color("3d3d40")

static var _font: Font
## The display font (the cast's fallback fonts for letters Lilita One lacks are attached by TeamCast.use_fonts).
static func font() -> Font:
	if _font == null:
		TeamCast.use_fonts()
		_font = FONT_FILE
	return _font

## The screen's pixel scale: 1.0 at 720 px high, down to 0.5 on a phone (844 x 390 is 0.54), up to 2.4.
static func unit(item: CanvasItem) -> float:
	return clampf(item.get_viewport_rect().size.y / 720.0, 0.5, 2.4)

## True when the on-screen touch buttons are up (a phone): the top right corner belongs to the MENU button.
static func touch(item: Node) -> bool:
	return item.is_inside_tree() and TouchControls.showing(item.get_tree())

## The pixels a phone's MENU button takes from the top right corner (0 on a desktop).
static func menu_gap(item: CanvasItem) -> float:
	return 120.0 * unit(item) if touch(item) else 0.0

## Width of `text` at font size `size` px (before slant).
static func width(text: String, size: float) -> float:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(size)).x

## Font size whose capitals are `cap_px` high.
static func size_for_cap(cap_px: float) -> float:
	return cap_px / CAP

## Bounce with overshoot: 0 -> 1 over `length` s, rising past 1 (`over`) and settling; used by every pop-in.
static func bounce(age: float, length := 0.35, over := 1.7) -> float:
	return Ui.out_back(clampf(age / maxf(length, 0.001), 0.0, 1.0), over)

## Scale of a pop-in: starts at `from`, overshoots 1 and settles in `length` seconds (age < 0 is 0).
static func pop_scale(age: float, length := 0.4, from := 0.2) -> float:
	if age < 0.0: return 0.0
	return lerpf(from, 1.0, bounce(age, length))

# ------------------------------------------------------------------ text

## Words centred on `centre` (`align` left: `centre` is the left end, right: the right end): font size `size` px, `fill`, an outline `edge_px` wide in `edge`, and an extrusion `depth_px`
## deep under the letters in `deep` (the chunky 3D look); `scale`, `angle` (rad) and `slant` (shear, 0.2 = italic) move the whole word; alpha multiplies every colour.
static func text(ci: CanvasItem, words: String, centre: Vector2, size: float, fill := Color.WHITE, edge := Color(0, 0, 0, 0), edge_px := 0.0, deep := Color(0, 0, 0, 0), depth_px := 0.0,
		scale := 1.0, angle := 0.0, slant := 0.0, alpha := 1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := font()
	var s := roundi(size)
	var wide := f.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var shift := -wide * 0.5
	if align == HORIZONTAL_ALIGNMENT_LEFT: shift = 0.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: shift = -wide
	ci.draw_set_transform_matrix(Transform2D(angle, Vector2.ONE * scale, 0.0, centre) * Transform2D(Vector2(1.0, 0.0), Vector2(-slant, 1.0), Vector2.ZERO))
	var at := Vector2(shift, size * CAP * 0.5)
	if deep.a > 0.0 and depth_px > 0.0:
		var steps := maxi(roundi(depth_px), 1)
		for step in range(steps, 0, -1):
			var down := at + Vector2(0.0, depth_px * float(step) / float(steps))
			if edge_px > 0.0: ci.draw_string_outline(f, down, words, HORIZONTAL_ALIGNMENT_LEFT, -1, s, roundi(edge_px), Color(deep, deep.a * alpha))
			ci.draw_string(f, down, words, HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(deep, deep.a * alpha))
	if edge.a > 0.0 and edge_px > 0.0: ci.draw_string_outline(f, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, s, roundi(edge_px), Color(edge, edge.a * alpha))
	ci.draw_string(f, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(fill, fill.a * alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## White slanted words with a dark outline (HUD lines on the scene, no plate: the objective, the feed's names).
static func label(ci: CanvasItem, words: String, left: Vector2, size: float, fill := Color.WHITE, alpha := 1.0) -> void:
	text(ci, words, left, size, fill, Color(0.0, 0.0, 0.0, 0.92), maxf(size * 0.22, 3.0), Color(0, 0, 0, 0), 0.0, 1.0, 0.0, SLANT, alpha, HORIZONTAL_ALIGNMENT_LEFT)

# ------------------------------------------------------------------ shapes

## A flat rounded box.
static func box(ci: CanvasItem, rect: Rect2, fill: Color, edge := Color(0, 0, 0, 0), edge_px := 0.0, radius := -1.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(roundi(rect.size.y * 0.5 if radius < 0.0 else radius))
	style.corner_detail = 12
	style.anti_aliasing = true
	if edge.a > 0.0 and edge_px > 0.0:
		style.border_color = edge
		style.set_border_width_all(maxi(roundi(edge_px), 1))
	ci.draw_style_box(style, rect)

## The dark pill with the thin light outline.
static func pill(ci: CanvasItem, rect: Rect2, fill := PILL, edge := PILL_EDGE, edge_px := 1.6, alpha := 1.0) -> void:
	box(ci, rect, Color(fill, fill.a * alpha), Color(edge, edge.a * alpha), edge_px)

## The width of a `height` px tall words pill (`pill_words`): the slanted words and an even padding on both sides.
static func pill_width(words: String, height: float) -> float:
	return width(words, height * 0.5) * (1.0 + SLANT * 0.1) + height * 0.9

## A pill with slanted white words centred in it, right edge at `right`, centred vertically on `middle`; `height` px tall, at least `min_wide` wide. Returns its rect.
static func pill_words(ci: CanvasItem, words: String, right: float, middle: float, height: float, alpha := 1.0, min_wide := 0.0, swell := 1.0) -> Rect2:
	var wide := maxf(min_wide, pill_width(words, height))
	var rect := Rect2(right - wide, middle - height * 0.5, wide, height)
	pill(ci, rect, PILL, PILL_EDGE, maxf(height * 0.04, 1.2), alpha)
	text(ci, words, rect.get_center(), height * 0.5, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, swell, 0.0, SLANT, alpha)
	return rect

## A stopwatch (the timer's icon): a ring, a crown button, one hand.
static func stopwatch(ci: CanvasItem, centre: Vector2, radius: float, color := Color.WHITE, alpha := 1.0) -> void:
	var c := Color(color, color.a * alpha)
	ci.draw_arc(centre + Vector2(0.0, radius * 0.1), radius * 0.82, 0.0, TAU, 32, c, radius * 0.24, true)
	ci.draw_rect(Rect2(centre + Vector2(-radius * 0.22, -radius * 1.02), Vector2(radius * 0.44, radius * 0.24)), c)
	ci.draw_line(centre + Vector2(0.0, radius * 0.1), centre + Vector2(radius * 0.36, -radius * 0.28), c, radius * 0.2, true)

## A spiky badge: `spikes` points around an ellipse of half-size `half`, dented between them. The outer shape in `edge`, the body inset to 90 % in `fill`, a lighter band along the top in `shine`.
## Drawn about `centre`, popped by `scale`, turned by `angle`.
static func badge(ci: CanvasItem, centre: Vector2, half: Vector2, fill := YELLOW, edge := ORANGE, deep := ORANGE_DEEP, alpha := 1.0, scale := 1.0, angle := 0.0, spikes := 22, dent := 0.86) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for index in spikes * 2:
		var a := TAU * float(index) / float(spikes * 2)
		var v := Vector2(cos(a), sin(a)) * half * (1.0 if index % 2 == 0 else dent)
		outer.append(v)
		inner.append(v * 0.9)
	ci.draw_set_transform_matrix(Transform2D(angle, Vector2.ONE * scale, 0.0, centre))
	var shadow := PackedVector2Array()
	for v in outer: shadow.append(v + Vector2(0.0, half.y * 0.07))
	ci.draw_colored_polygon(shadow, Color(deep, alpha))
	ci.draw_colored_polygon(outer, Color(edge, alpha))
	ci.draw_colored_polygon(inner, Color(fill, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## A small crown (cream with a gold edge) of width `wide`, its base centre at `base`.
static func crown(ci: CanvasItem, base: Vector2, wide: float, fill := CREAM, edge := ORANGE, alpha := 1.0, angle := 0.0) -> void:
	var h := wide * 0.62
	var points := PackedVector2Array([Vector2(-0.5, 0.0), Vector2(-0.5, -0.55), Vector2(-0.25, -0.3), Vector2(0.0, -1.0), Vector2(0.25, -0.3), Vector2(0.5, -0.55), Vector2(0.5, 0.0)])
	var scaled := PackedVector2Array()
	for p in points: scaled.append(Vector2(p.x * wide, p.y * h))
	ci.draw_set_transform_matrix(Transform2D(angle, Vector2.ONE, 0.0, base))
	var rim := scaled.duplicate()
	rim.append(rim[0])
	ci.draw_colored_polygon(scaled, Color(edge, alpha))
	var inset := PackedVector2Array()
	for p in scaled: inset.append(p * 0.84 + Vector2(0.0, -h * 0.04))
	ci.draw_colored_polygon(inset, Color(fill, alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
