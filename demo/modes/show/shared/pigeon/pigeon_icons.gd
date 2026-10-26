extends RefCounted
## GHOST PIGEON (docs/pigeon.md): the little pictures of the pigeon's HUD, drawn into any CanvasItem in the show's look (client/show_theme.gd): the DROP glyph (a falling drop), the COO glyph
## (a beak with two sound arcs), and the round DROP button of the phone's overlay (client/touch_controls.gd calls touch_drop; the keyboard's key for it is ITEM).
const ShowTheme := preload("res://client/show_theme.gd")

## A drop: a teardrop of radius `r` with its round belly centred at `centre`, white with a pale rim.
static func drop_glyph(ci: CanvasItem, centre: Vector2, r: float, fill := Color.WHITE, alpha := 1.0) -> void:
	var points := PackedVector2Array()
	points.append(centre + Vector2(0.0, -r * 1.75))
	for step in 17:
		var angle := lerpf(-0.42 * PI, 1.42 * PI, float(step) / 16.0) # the belly from the right round the bottom to the left, the tip above
		points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	var rim := PackedVector2Array(points)
	rim.append(points[0])
	ci.draw_colored_polygon(points, Color(fill.r, fill.g, fill.b, alpha))
	ci.draw_polyline(rim, Color(0.62, 0.7, 0.85, alpha), maxf(r * 0.1, 1.5), true)
	ci.draw_circle(centre + Vector2(-r * 0.35, r * 0.1), r * 0.2, Color(0.62, 0.7, 0.85, alpha * 0.6)) # a glint

## A coo: a beak pointing right and two arcs of sound in front of it.
static func coo_glyph(ci: CanvasItem, centre: Vector2, r: float, fill := Color.WHITE, alpha := 1.0) -> void:
	var colour := Color(fill.r, fill.g, fill.b, alpha)
	ci.draw_colored_polygon(PackedVector2Array([centre + Vector2(-r, -r * 0.7), centre + Vector2(r * 0.15, -r * 0.2), centre + Vector2(r * 0.15, r * 0.2), centre + Vector2(-r, r * 0.7)]), colour)
	for arc in 2:
		var radius := r * (0.65 + 0.5 * float(arc))
		ci.draw_arc(centre + Vector2(r * 0.15, 0.0), radius, -0.6, 0.6, 12, colour, maxf(r * 0.16, 1.6), true)

## The round DROP key of the phone's overlay over `rect`: a dark disc with a white ring, the glyph and the word, as the ITEM key of the items looks (modes/show/items/item_icons.gd touch_button).
static func touch_drop(ci: CanvasItem, rect: Rect2, held: bool) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5 * 0.9
	ci.draw_circle(c, r, Color(ShowTheme.PILL.r, ShowTheme.PILL.g, ShowTheme.PILL.b, 0.82 if held else 0.66))
	ci.draw_arc(c, r - 1.5, 0.0, TAU, 56, ShowTheme.CREAM if held else Color(1.0, 1.0, 1.0, 0.55), 3.5, true)
	drop_glyph(ci, c + Vector2(0.0, -r * 0.02), r * 0.24)
	ShowTheme.text(ci, "DROP", c + Vector2(0.0, r * 0.74), r * 0.36, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 0.95)
