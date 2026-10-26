extends RefCounted
## The show HUD's pieces, drawn with client/show_theme.gd into any CanvasItem (the generic mode HUD, the stage round's HUD, the round card and the face wall all draw
## the same pieces, so every round looks alike). All static; sizes are in screen pixels and scale with `k(ci)`; the right column keeps the phone's MENU corner free.
##   ShowHudKit.timer(ci, seconds, right, top, k)               a dark pill, chunky outlined digits, a plain stopwatch glyph at its end
##   ShowHudKit.counter(ci, words, right, top, k)               a dark pill with centred words (THROUGH 2/5, Current eliminations 1/6)
##   ShowHudKit.feed_row(ci, right, top, k, name, tail, mark)   a cream name pill with a red X or a gold rank badge (the finish and elimination feed)
##   ShowHudKit.board_row(ci, right, top, k, rank, name, points, color)  a scoreboard pill in the player's colour with a gold rank badge
##   ShowHudKit.line_pill(ci, words, centre, k)                    a dark pill with slanted words (a hint, an event, a catchphrase)
const ShowTheme := preload("res://client/show_theme.gd")

const MIN_K := 0.72 ## the smallest HUD scale (a phone: 844 x 390 is 0.54 of the 720 reference, pills would be too small to read)
const MARGIN := 30.0 ## px at k = 1: the space between the pills and the screen's edge
const TOP := 22.0
const PILL_H := 44.0
const ROW_H := 38.0
const GAP := 10.0
const OBJECTIVE_SPLIT := "  " ## the objective's two parts: the warning, then what to be
const INK := Color("1b1d24")
const FEED_FILL := Color("f7f3e6")
const FEED_EDGE := Color("00051e")
const TEAL_INK := Color("1f8f78")

## The HUD scale of this screen.
static func k(ci: CanvasItem) -> float:
	var unit := ShowTheme.unit(ci)
	return maxf(unit, MIN_K)

## The right column's right edge (the MENU button's corner stays free on a phone).
static func right_edge(ci: CanvasItem) -> float:
	return ci.get_viewport_rect().size.x - MARGIN * k(ci) - ShowTheme.menu_gap(ci)

## `words` broken into lines of at most `room` px at font size `size` (the part before a double space stays on a line of its own).
static func wrapped(words: String, size: float, room: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var parts := words.split(OBJECTIVE_SPLIT, false)
	for part in parts:
		var line := ""
		for word: String in part.split(" ", false):
			var next := word if line == "" else line + " " + word
			if line != "" and ShowTheme.width(next, size) * (1.0 + ShowTheme.SLANT * 0.1) > room:
				lines.append(line)
				line = word
			else: line = next
		if line != "": lines.append(line)
	return lines

# ------------------------------------------------------------------ pills

## "M:SS" for a number of seconds.
static func clock(seconds: float) -> String:
	var total := maxi(ceili(seconds), 0)
	return "%d:%02d" % [total / 60, total % 60]

## Chunky outlined digits centred on `centre` (every digit in a cell of the same width: the time does not shake).
static func digits(ci: CanvasItem, words: String, centre: Vector2, size: float, fill: Color, edge: Color, alpha := 1.0) -> void:
	var cells := PackedFloat32Array()
	var total := 0.0
	var zero := ShowTheme.width("0", size)
	for index in words.length():
		var cell := zero if words[index] != ":" else zero * 0.55
		cells.append(cell)
		total += cell
	var at := centre.x - total * 0.5
	for index in words.length():
		ShowTheme.text(ci, words[index], Vector2(at + cells[index] * 0.5, centre.y), size, fill, edge, maxf(size * 0.2, 3.0), Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
		at += cells[index]

## The timer pill (right edge at `right`): outlined digits and a plain stopwatch glyph at the right end; the last 10 s turn the digits yellow and the glyph red. Returns its rect.
static func timer(ci: CanvasItem, seconds: float, right: float, top: float, scale: float, alpha := 1.0) -> Rect2:
	var height := PILL_H * scale
	var words := clock(seconds)
	var size := ShowTheme.size_for_cap(height * 0.46)
	var glyph_r := height * 0.26
	var glyph_w := glyph_r * 1.9
	var digits_w := ShowTheme.width("0", size) * (words.length() - 1 + 0.55)
	var wide := height * 0.45 + digits_w + height * 0.3 + glyph_w + height * 0.4
	var rect := Rect2(right - wide, top, wide, height)
	var middle := top + height * 0.5
	ShowTheme.pill(ci, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, maxf(height * 0.04, 1.2), alpha)
	var hurry := seconds <= 10.0
	digits(ci, words, Vector2(rect.position.x + height * 0.45 + digits_w * 0.5, middle), size, ShowTheme.YELLOW if hurry else Color.WHITE, Color(ShowTheme.NAVY, 0.95), alpha)
	ShowTheme.stopwatch(ci, Vector2(rect.end.x - height * 0.4 - glyph_w * 0.5, middle), glyph_r, ShowTheme.RED if hurry else Color.WHITE, alpha)
	return rect

## A dark pill with slanted words centred in it (right edge `right`, its top at `top`). `swell` pops it. Returns its rect.
static func counter(ci: CanvasItem, words: String, right: float, top: float, scale: float, alpha := 1.0, swell := 1.0, min_wide := 0.0) -> Rect2:
	var height := PILL_H * scale
	return ShowTheme.pill_words(ci, words, right, top + height * 0.5, height, alpha, min_wide, swell)

## A dark pill with an icon's room at its left end and slanted words centred in the rest (right edge `right`, its top at `top`), `edge` its outline. The caller draws the icon at
## icon_centre(rect) within icon_radius(rect), with no disc behind it. Returns its rect.
static func icon_pill(ci: CanvasItem, words: String, right: float, top: float, scale: float, alpha := 1.0, swell := 1.0, min_wide := 0.0, edge := ShowTheme.PILL_EDGE) -> Rect2:
	var height := PILL_H * scale
	var size := height * 0.5
	var lead := height * 0.95
	var tail := height * 0.45
	var text_w := ShowTheme.width(words, size) * (1.0 + ShowTheme.SLANT * 0.1)
	var wide := maxf(min_wide, lead + text_w + tail)
	var rect := Rect2(right - wide, top, wide, height)
	ShowTheme.pill(ci, rect, ShowTheme.PILL, edge, maxf(height * 0.04, 1.2), alpha)
	ShowTheme.text(ci, words, Vector2(rect.position.x + lead + (wide - lead - tail) * 0.5, top + height * 0.5), size, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, swell, 0.0, ShowTheme.SLANT, alpha)
	return rect

## Where an icon of icon_pill()'s `rect` is centred.
static func icon_centre(rect: Rect2) -> Vector2:
	return Vector2(rect.position.x + rect.size.y * 0.5, rect.get_center().y)

## The radius of the icon in icon_pill()'s `rect`.
static func icon_radius(rect: Rect2) -> float:
	return rect.size.y * 0.36

## A dark pill with slanted words, centred on `centre` (a hint, an event, a catchphrase under a banner). Returns its rect.
static func line_pill(ci: CanvasItem, words: String, centre: Vector2, scale: float, alpha := 1.0, size_px := 0.0, max_wide := 0.0) -> Rect2:
	if words == "": return Rect2()
	var height := ROW_H * scale * 1.1
	var size := size_px if size_px > 0.0 else height * 0.5
	var wide := ShowTheme.width(words, size) * (1.0 + ShowTheme.SLANT * 0.1) + height * 1.1
	if max_wide > 0.0 and wide > max_wide:
		size *= max_wide / wide
		wide = max_wide
	var rect := Rect2(centre - Vector2(wide, height) * 0.5, Vector2(wide, height))
	ShowTheme.pill(ci, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, maxf(height * 0.04, 1.2), alpha)
	ShowTheme.text(ci, words, centre, size, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
	return rect

# ------------------------------------------------------------------ feed and board

## The round badge: a gold disc with a deep edge and a cream number (a rank), centred on `centre`.
static func rank_badge(ci: CanvasItem, centre: Vector2, radius: float, rank: int, alpha := 1.0) -> void:
	ci.draw_circle(centre + Vector2(0.0, radius * 0.08), radius, Color(ShowTheme.GOLD_DEEP, alpha))
	ci.draw_circle(centre, radius, Color(ShowTheme.GOLD, alpha))
	ci.draw_arc(centre, radius * 0.8, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.45 * alpha), radius * 0.1, true)
	ShowTheme.text(ci, str(rank), centre, radius * 1.25, ShowTheme.CREAM, ShowTheme.GOLD_DEEP, radius * 0.22, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)

## A round red badge with a white X (an elimination), centred on `centre`.
static func cross_badge(ci: CanvasItem, centre: Vector2, radius: float, alpha := 1.0) -> void:
	ci.draw_circle(centre, radius, Color(ShowTheme.RED, alpha))
	ci.draw_arc(centre, radius * 0.82, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.35 * alpha), radius * 0.1, true)
	var arm := radius * 0.4
	ci.draw_line(centre + Vector2(-arm, -arm), centre + Vector2(arm, arm), Color(1.0, 1.0, 1.0, alpha), radius * 0.26, true)
	ci.draw_line(centre + Vector2(-arm, arm), centre + Vector2(arm, -arm), Color(1.0, 1.0, 1.0, alpha), radius * 0.26, true)

## One row of the feed (right edge `right`, its top at `top`): a cream pill with a navy edge, the badge on the left (`mark`: a rank >= 1 gold badge, 0 the red X), the name in dark slanted words and,
## in teal after it, the `tail` word. `grow` scales the pill's width (a row coming in). Returns its rect.
static func feed_row(ci: CanvasItem, right: float, top: float, scale: float, who: String, tail := "", mark := 0, alpha := 1.0, grow := 1.0, min_wide := 0.0) -> Rect2:
	var height := ROW_H * scale
	var size := height * 0.5
	var name_wide := ShowTheme.width(who, size) * (1.0 + ShowTheme.SLANT * 0.1)
	var tail_size := size * 0.8
	var tail_wide := ShowTheme.width(tail, tail_size) * (1.0 + ShowTheme.SLANT * 0.1) + size * 0.5 if tail != "" else 0.0
	var wide := maxf(height * 1.6 + name_wide + tail_wide + height * 0.35, min_wide) * grow
	var rect := Rect2(right - wide, top, wide, height)
	ShowTheme.box(ci, rect, Color(FEED_FILL, FEED_FILL.a * alpha), Color(FEED_EDGE, alpha), maxf(height * 0.06, 1.5))
	var middle := top + height * 0.5
	var badge := Vector2(rect.position.x + height * 0.5, middle)
	if mark >= 1: rank_badge(ci, badge, height * 0.42 * grow, mark, alpha)
	else: cross_badge(ci, badge, height * 0.38 * grow, alpha)
	var at := rect.position.x + height * 1.05 * grow
	ShowTheme.text(ci, who, Vector2(at, middle), size, INK, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, grow, 0.0, ShowTheme.SLANT, alpha, HORIZONTAL_ALIGNMENT_LEFT)
	if tail != "": ShowTheme.text(ci, tail, Vector2(at + (name_wide + size * 0.5) * grow, middle), tail_size, TEAL_INK if mark >= 1 else ShowTheme.RED, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, grow, 0.0, ShowTheme.SLANT, alpha, HORIZONTAL_ALIGNMENT_LEFT)
	return rect

## One row of the points scoreboard (right edge `right`, its top at `top`): a pill in the player's colour (a dark pill when it is out: `dim`) with the gold rank badge, the name and the points.
static func board_row(ci: CanvasItem, right: float, top: float, scale: float, rank: int, who: String, points: int, color: Color, dim := false, alpha := 1.0, min_wide := 0.0) -> Rect2:
	var height := ROW_H * scale * 0.92
	var size := height * 0.5
	var shown := str(points)
	var wide := maxf(height * 2.9 + ShowTheme.width(who, size) * (1.0 + ShowTheme.SLANT * 0.1) + ShowTheme.width(shown, size), min_wide)
	var rect := Rect2(right - wide, top, wide, height)
	var fade := alpha * (0.5 if dim else 1.0)
	var ink: Color = INK if color.get_luminance() > 0.55 else Color.WHITE
	ShowTheme.pill(ci, rect, color.darkened(0.15) if dim else color, Color(1.0, 1.0, 1.0, 0.55), maxf(height * 0.05, 1.2), fade)
	var middle := top + height * 0.5
	rank_badge(ci, Vector2(rect.position.x + height * 0.5, middle), height * 0.4, rank, fade)
	ShowTheme.text(ci, who, Vector2(rect.position.x + height * 1.05, middle), size, ink, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, fade, HORIZONTAL_ALIGNMENT_LEFT)
	ShowTheme.text(ci, shown, Vector2(rect.end.x - height * 0.5, middle), size, ink, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, fade, HORIZONTAL_ALIGNMENT_RIGHT)
	return rect

# ------------------------------------------------------------------ the own marker

## The yellow triangle over the local courier's head (`head` is the head's screen point), the same size on the screen wherever the courier is.
static func marker(ci: CanvasItem, head: Vector2, unit: float) -> void:
	var tip := head - Vector2(0.0, 14.0 * unit)
	var half := 12.0 * unit
	var top := tip.y - 19.0 * unit
	var points := PackedVector2Array([Vector2(tip.x - half, top), Vector2(tip.x + half, top), tip])
	ci.draw_polygon(points, PackedColorArray([Color("f5e935"), Color("f5e935"), Color("f08c1a")]))
	var centre := (points[0] + points[1] + points[2]) / 3.0
	var ring := PackedVector2Array()
	for point: Vector2 in points: ring.append(centre + (point - centre) * 0.62)
	ring.append(ring[0])
	ci.draw_polyline(ring, ShowTheme.CREAM, 2.0 * unit, true)
	var outline := points.duplicate()
	outline.append(points[0])
	ci.draw_polyline(outline, Color.BLACK, 2.5 * unit, true)
