extends RefCounted
## The menu kit: what every non-gameplay screen of the show (title, Settings, pause, loading / error / notice pages, lobby chips, results, the customizer) is made of. The look is the candy
## menu look of the party world: a bright saturated full-screen backdrop (concentric rings, yellow by default), chunky rounded plates with a white rim and a thick bottom bevel
## (a big pink primary, cyan secondaries), a charcoal top bar with tabs, violet sheets, cyan chips, white heavy italic Lilita One lettering with a dark outline, slanted plates.
## The in-round HUD, banners, GOAL sign and podium keep the show's pills (client/show_theme.gd, show_hud_kit.gd, show_banner.gd): they are not part of the kit.
## Brand-swappable: the primary colour (PLAY, the chosen tab, the progress bar, the logo's extrusion) is the cast's first brand colour with colour in it (TeamCast.brand_accent()), the pink of the template when it has none.
## The page's backdrop stays yellow, and turns violet behind a brand colour that is itself a yellow or orange, so the primary never sinks into it. Everything else (cyan, violet, white, charcoal) is the kit's own.
## All static; every piece is vector drawing (StyleBox subclasses and `_draw`), no textures, so it is crisp at any scale.
##   Kit.style(role, state)                  a Chunk plate for a role ("primary", "chosen", "go", "danger", "blue", "plain", "tab") in a state ("normal", "hover", "pressed", "disabled")
##   Kit.dress(button, role)                 all states, the focus ring and the springy press of a Button / OptionButton / CheckBox (meta &"kit_slant" leans the plate)
##   Kit.panel(kind)                         a sheet: "sheet" (violet, white rim), "glass" (see-through violet over a 3D stage), "cream" (white card, violet rim)
##   Kit.button / label / heading / overline the same helpers as client/friends_ui.gd, in the kit's look (Ui's stay for the 3D world's boards)
##   Kit.theme()                             the Theme every menu root wears
##   Kit.draw_backdrop(ci, rect, clock, tone) the full-screen page: gradient, rings turning outward, soft glow ("sun", "sea", "berry", "grape")
##   Kit.rank_badge(ci, centre, r, rank)     the gold / silver / bronze medal (rank 1-3), a violet numbered disc after
##   Kit.bar_box() / Kit.corner_ribbons(...) the top bar's charcoal band; the tri-colour diagonal corner stripes of the results
##   Kit.LogoMark                            a Control that draws the show logo (the team's title in big outlined type) with its small line
const Ui := preload("res://client/friends_ui.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ShowHudKit := preload("res://style/show_hud_kit.gd")

const EDGE := Color("2a1062") ## the dark outline of lettering on the kit's colours (a deep violet)
const CREAM := Color("fff8e8")
const WHITE := Color("ffffff")
const MINT := Color("86f0c6")
const GOLD := ShowTheme.GOLD
const CHARCOAL := Color("2b2234") ## the top bar
const VIOLET := Color("5632cf") ## the sheet
const VIOLET_DEEP := Color("33188f")
const CYAN := Color("1fb8f2")
const PINK := Color("f23a96") ## the template's primary
const YELLOW := Color("ffc800")
const CHIP := Color("1a8fe3") ## the cyan-blue chip (tags, captions, counters)
## The sheet's text: white on the violet; muted lines on it.
const ON_DARK := Color("ffffff")
const MUTED_ON_DARK := Color("d9ccff")
## Ink on a cream card (the HUD's own ink).
const INK := ShowHudKit.INK
const INK_SOFT := Color("6c5aa6")
const BACKDROP_HUE := 0.137 ## the sun backdrop's yellow
const BACKDROP_CLASH := 0.1 ## a primary this close in hue to it (yellows, oranges) gets the violet backdrop

const DISABLED := {"top": Color("dcd6ec"), "face": Color("c6bfdc"), "low": Color("b2aacb"), "lip": Color("8d84aa"), "line": Color("f1eefa"), "ow": 0.8, "ink": Color("f4f1fb"), "edge": Color("7a7196"), "deep": Color(0, 0, 0, 0)}

static var _fonts_ready := false
static var _roles := {}
static var _roles_key := ""

## The display font (Lilita One, with the cast's fallback letters).
static func font() -> Font:
	return ShowTheme.font()

# ------------------------------------------------------------------ colours: the primary and what follows from it

## The primary colour: the brand's accent (a saturated, bright version of the first brand colour), the template's pink without one.
static func primary_color() -> Color:
	var brand := TeamCast.brand_accent()
	if brand.a <= 0.0: return PINK
	return Color.from_hsv(brand.h, clampf(brand.s, 0.62, 0.92), clampf(brand.v + 0.12, 0.86, 1.0))

## The secondary colour (the plain plates, the chips): cyan, a violet when the primary is itself a cyan.
static func secondary_color() -> Color:
	return Color("7a5cff") if absf(primary_color().h - CYAN.h) < 0.09 else CYAN

## The backdrop's base colour by `tone`: "sun" (yellow; the title, Settings, the customizer; violet behind a yellow or orange brand), "sea" (cyan, the loading page), "berry" (pink-red), "grape" (violet, the error page).
static func backdrop_base(tone := "sun") -> Color:
	match tone:
		"sea": return Color.from_hsv(0.54, 0.86, 1.0)
		"berry": return Color.from_hsv(0.96, 0.82, 1.0)
		"grape": return Color.from_hsv(0.74, 0.62, 0.92)
	if absf(primary_color().h - BACKDROP_HUE) < BACKDROP_CLASH: return backdrop_base("grape")
	return Color.from_hsv(BACKDROP_HUE, 0.98, 1.0)

## A colour's ramp as a plate spec: the face, the lighter top, the darker low band and the lip (the bevel), the lettering's edge and extrusion, shading drifting toward violet.
static func ramp(face: Color, rim := WHITE, rim_width := 1.0, ink := WHITE) -> Dictionary:
	var hue := face.h
	var sat := face.s
	var val := face.v
	return {
		"top": Color.from_hsv(hue, clampf(sat * 0.42, 0.0, 1.0), 1.0),
		"face": face,
		"low": Color.from_hsv(fposmod(hue + 0.012, 1.0), minf(sat * 1.04, 1.0), val * 0.86),
		"lip": Color.from_hsv(fposmod(hue + 0.025, 1.0), minf(sat * 1.1, 1.0), val * 0.58),
		"line": rim, "ow": rim_width, "ink": ink,
		"edge": Color.from_hsv(fposmod(hue + 0.03, 1.0), minf(sat * 1.15, 1.0), val * 0.42),
		"deep": Color.from_hsv(fposmod(hue + 0.035, 1.0), minf(sat * 1.15, 1.0), val * 0.3),
	}

## Per role: the plate (ramp of its colour). Roles are meta &"comic_role" of a Button (menu_skin.gd). `primary` and `chosen` are the brand's colour, `plain` the secondary, `tab` a light violet (an unchosen tab on the violet sheet),
## `go` green, `danger` red, `blue` a royal blue, `cream` the keycaps.
static func roles() -> Dictionary:
	var key := str(primary_color()) + str(secondary_color())
	if key != _roles_key:
		_roles_key = key
		var primary := ramp(primary_color())
		_roles = {
			"primary": primary,
			"chosen": primary,
			"go": ramp(Color("33d986")),
			"danger": ramp(Color("ff4c5f")),
			"blue": ramp(Color("3f6bff")),
			"plain": ramp(secondary_color()),
			"tab": ramp(Color("8e6df5")),
			"cream": {"top": Color("ffffff"), "face": Color("fff6e0"), "low": Color("f0dfb8"), "lip": Color("b79d62"), "line": Color("2a1062"), "ow": 0.7, "ink": INK, "edge": Color(0, 0, 0, 0), "deep": Color(0, 0, 0, 0)},
		}
	return _roles

static func role(name: String) -> Dictionary:
	return roles().get(name, roles()["plain"])

## The lettering colour of a role.
static func ink(name: String) -> Color:
	return (role(name).ink as Color)

# ------------------------------------------------------------------ the chunky plate

## A plate with a thick lip under it (the bevel), a white rim and a drop shadow: a StyleBox that draws its layers into whatever rect it is given (so one Chunk fits any button). `state`: "normal", "hover" (lighter),
## "pressed" (the face sinks onto the lip), "disabled" (grey). The lip, the rim and the shadow scale with the rect's height; the plate's body is the rect minus them at the bottom, so a Button
## keeps its size and the lettering is centred on `face_center` (the face's middle, in the rect's height share). `slant` (a shear, 0.2 = the title's PLAY) leans the whole plate like the italic type.
class Chunk extends StyleBox:
	var look: Dictionary
	var state := "normal"
	var slant := 0.0
	var _flat := StyleBoxFlat.new()

	func _init(spec: Dictionary, mode := "normal", lean := 0.0) -> void:
		look = spec
		state = mode
		slant = lean
		_flat.anti_aliasing = true
		_flat.corner_detail = 12

	## The lip (the bevel) under the face, px, for a rect `h` tall.
	static func lip(h: float) -> float:
		return clampf(h * 0.15, 4.0, 24.0)

	## The drop shadow's reach under the lip, px.
	static func drop(h: float) -> float:
		return clampf(h * 0.06, 2.0, 10.0)

	## The rim's width, px.
	static func outline(h: float, share := 1.0) -> float:
		return clampf(h * 0.032 * share, 1.5, 6.0)

	## Where the face's middle sits in a rect `h` tall (px from the top): above the lip and the shadow.
	static func face_middle(h: float) -> float:
		return (h - lip(h) - drop(h)) * 0.5

	func _fill(item: RID, rect: Rect2, color: Color, radius: float, cy := 0.0) -> void:
		if rect.size.x <= 0.5 or rect.size.y <= 0.5: return
		if is_zero_approx(slant):
			_flat.bg_color = color
			_flat.set_corner_radius_all(int(maxf(radius, 0.0)))
			_flat.draw(item, rect)
			return
		var points := rounded_polygon(rect, radius, slant, cy)
		RenderingServer.canvas_item_add_polygon(item, points, PackedColorArray([color]))
		var edge := points.duplicate()
		edge.append(points[0])
		RenderingServer.canvas_item_add_polyline(item, edge, PackedColorArray([color]), 1.4, true) # the antialiased edge

	## A rounded rectangle as a polygon, every point sheared about the height `cy` (top to the right for a positive `shear`).
	static func rounded_polygon(rect: Rect2, radius: float, shear: float, cy: float, steps := 8) -> PackedVector2Array:
		var points := PackedVector2Array()
		var r := maxf(minf(radius, minf(rect.size.x, rect.size.y) * 0.5), 0.0)
		var corners := [
			[rect.end.x - r, rect.position.y + r, -PI * 0.5],
			[rect.end.x - r, rect.end.y - r, 0.0],
			[rect.position.x + r, rect.end.y - r, PI * 0.5],
			[rect.position.x + r, rect.position.y + r, PI]]
		for corner: Array in corners:
			for step in steps + 1:
				var a: float = float(corner[2]) + PI * 0.5 * float(step) / float(steps)
				var point := Vector2(float(corner[0]) + cos(a) * r, float(corner[1]) + sin(a) * r)
				point.x += shear * (cy - point.y)
				points.append(point)
		return points

	func _draw(item: RID, rect: Rect2) -> void:
		var spec: Dictionary = DISABLED if state == "disabled" else look
		var top: Color = spec.top
		var face: Color = spec.face
		var low: Color = spec.low
		var lip_color: Color = spec.lip
		if state == "hover":
			top = top.lerp(Color.WHITE, 0.25)
			face = face.lerp(Color.WHITE, 0.16)
			low = low.lerp(Color.WHITE, 0.1)
		var h := rect.size.y
		var d := lip(h)
		var s := drop(h)
		var o := outline(h, float(spec.ow))
		var body := h - d - s
		var pad := absf(slant) * h * 0.5 # the lean needs room at the sides
		var w := rect.size.x - pad * 2.0
		var sink := d * 0.8 if state == "pressed" else 0.0
		var r := minf(body * 0.4, w * 0.5)
		var x := rect.position.x + pad
		var y := rect.position.y
		var cy := y + sink + (body + d - sink) * 0.5 # the silhouette's middle: every layer leans about it
		_fill(item, Rect2(x + s * 0.3, y + sink + s, w - s * 0.6, body + d - sink), Color(0.16, 0.04, 0.3, 0.38), r, cy) # the drop shadow
		_fill(item, Rect2(x, y + sink, w, body + d - sink), spec.line, r, cy) # the rim, silhouette of plate and lip
		var inner := Rect2(x + o, y + sink + o, w - o * 2.0, body + d - sink - o * 2.0)
		_fill(item, inner, lip_color, r - o, cy) # the lip, the thick bottom bevel
		var fr := Rect2(x + o, y + sink + o, w - o * 2.0, body - o * 2.0)
		_fill(item, fr, low, r - o, cy) # the face, three bands for the gradient
		_fill(item, Rect2(fr.position.x, fr.position.y, fr.size.x, fr.size.y * 0.74), face, r - o, cy)
		if state != "disabled":
			var hi := Rect2(fr.position.x + fr.size.y * 0.12, fr.position.y + fr.size.y * 0.07, fr.size.x - fr.size.y * 0.24, fr.size.y * 0.3)
			_fill(item, hi, Color(top.r, top.g, top.b, 0.55), minf(hi.size.y * 0.5, r - o), cy)

	func _get_draw_rect(rect: Rect2) -> Rect2:
		return rect

	func _get_minimum_size() -> Vector2:
		return Vector2.ZERO

## A Chunk plate of `role` in `state`.
static func style(role_name: String, state := "normal", lean := 0.0) -> Chunk:
	var plate := Chunk.new(role(role_name), state, lean)
	plate.content_margin_left = 22.0
	plate.content_margin_right = 22.0
	plate.content_margin_top = 6.0
	plate.content_margin_bottom = 6.0
	return plate

## The focus ring of a leaning plate: the same ring as `focus_ring`, drawn along the plate's slanted outline.
class Ring extends StyleBox:
	var slant := 0.0
	var gap := 5.0
	var width := 3.0

	func _init(lean := 0.0, space := 5.0, line := 3.0) -> void:
		slant = lean
		gap = space
		width = line

	func _draw(item: RID, rect: Rect2) -> void:
		var h := rect.size.y
		var d := Chunk.lip(h)
		var s := Chunk.drop(h)
		var body := h - d - s
		var pad := absf(slant) * h * 0.5
		var plate := Rect2(rect.position.x + pad, rect.position.y, rect.size.x - pad * 2.0, body + d).grow(gap)
		var r := minf(body * 0.4, (rect.size.x - pad * 2.0) * 0.5) + gap
		var points := Chunk.rounded_polygon(plate, r, slant, plate.get_center().y)
		points.append(points[0])
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([Color(EDGE, 0.85)]), width + 5.0, true)
		RenderingServer.canvas_item_add_polyline(item, points, PackedColorArray([WHITE]), width, true)

	func _get_draw_rect(rect: Rect2) -> Rect2:
		return rect.grow(gap + width + 6.0)

## The keyboard / pad focus ring: a white ring with a dark halo round the plate (it hugs a pill: a big radius is clamped to the rect), readable on yellow, violet and pink alike. A leaning plate takes a leaning ring.
static func focus_ring(gap := 5.0, width := 3, lean := 0.0) -> StyleBox:
	if not is_zero_approx(lean): return Ring.new(lean, gap, float(width))
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = WHITE
	ring.set_border_width_all(width)
	ring.set_corner_radius_all(64)
	ring.set_expand_margin_all(gap)
	ring.shadow_color = Color(EDGE, 0.85)
	ring.shadow_size = 3
	ring.anti_aliasing = true
	ring.corner_detail = 12
	return ring

## Gives `button` the plates of `role` in every state, the focus ring and a springy press (it dips on down and bounces back on up). The plate leans by the button's meta &"kit_slant". Idempotent per role.
static func dress(button: Control, role_name: String) -> void:
	var lean := float(button.get_meta(&"kit_slant", 0.0))
	if button is BaseButton:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, style(role_name, "pressed" if state == "hover_pressed" else state, lean))
	button.add_theme_stylebox_override("focus", focus_ring(5.0, 3, lean))
	button.set_meta(&"no_focus_ring", true)
	if button.has_meta(&"kit_press"): return
	button.set_meta(&"kit_press", true)
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	button.pivot_offset = button.size * 0.5
	if button is BaseButton:
		var base := button as BaseButton
		base.button_down.connect(func() -> void: _spring(base, 0.965, 0.07, false))
		base.button_up.connect(func() -> void: _spring(base, 1.0, 0.32, true))

static func _spring(control: Control, to: float, length: float, bounce: bool) -> void:
	if not control.is_inside_tree(): return
	var motion := Ui.tween(control)
	if control.has_meta(&"kit_tween"):
		var old: Tween = control.get_meta(&"kit_tween")
		if old != null and old.is_valid(): old.kill()
	control.set_meta(&"kit_tween", motion)
	motion.tween_property(control, "scale", Vector2.ONE * to, length).set_trans(Tween.TRANS_BACK if bounce else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ sheets and the theme

## A sheet: "sheet" (violet with a white rim and a soft drop shadow), "glass" (see-through violet, over a 3D stage), "cream" (a white card with a violet rim).
static func panel(kind := "sheet", radius := 26, pad := 26) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	match kind:
		"cream":
			box.bg_color = CREAM
			box.border_color = VIOLET
			box.set_border_width_all(4)
		"glass":
			box.bg_color = Color(VIOLET_DEEP, 0.78)
			box.border_color = Color(1, 1, 1, 0.85)
			box.set_border_width_all(3)
		_:
			box.bg_color = VIOLET
			box.border_color = WHITE
			box.set_border_width_all(4)
	box.set_corner_radius_all(radius)
	box.corner_detail = 12
	box.anti_aliasing = true
	box.shadow_color = Color(0.16, 0.04, 0.3, 0.42)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0.0, 9.0)
	box.set_content_margin_all(pad)
	return box

## A small tag / row plate: a cyan chip with a white rim, or a cream one with a violet rim.
static func pill_box(light := false, radius := 18, line := 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(CREAM, 0.98) if light else CHIP
	box.border_color = VIOLET if light else WHITE
	box.set_border_width_all(line)
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.anti_aliasing = true
	box.shadow_color = Color(0.16, 0.04, 0.3, 0.3)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0.0, 4.0)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

## The HUD's own pill (client/show_theme.gd: dark, a thin light outline), for what sits over the live world as HUD and not as a menu (the lobby's status line and name chips).
static func hud_pill_box(radius := 18, line := 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = ShowTheme.PILL
	box.border_color = ShowTheme.PILL_EDGE
	box.set_border_width_all(line)
	box.set_corner_radius_all(radius)
	box.corner_detail = 10
	box.anti_aliasing = true
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box

## A chip drawn into `ci`: `rect` filled with `fill`, a white rim round it and a soft drop shadow (the drawn twin of `pill_box`; the tags, counters and captions of the pages' graphics).
static func chip(ci: CanvasItem, rect: Rect2, alpha := 1.0, fill := CHIP) -> void:
	var rim := maxf(rect.size.y * 0.07, 2.0)
	ShowTheme.box(ci, Rect2(rect.position + Vector2(0.0, rim * 1.3), rect.size).grow(rim), Color(0.16, 0.04, 0.3, 0.3 * alpha))
	ShowTheme.box(ci, rect.grow(rim), Color(WHITE, alpha))
	ShowTheme.box(ci, rect, Color(fill, fill.a * alpha))

## A chip with slanted white words (dark edge) centred in it, right edge at `right`, centred on `middle`; `height` px tall, at least `min_wide` wide. Returns its rect.
static func chip_words(ci: CanvasItem, words: String, right: float, middle: float, height: float, alpha := 1.0, min_wide := 0.0, fill := CHIP) -> Rect2:
	var wide := maxf(min_wide, ShowTheme.pill_width(words, height))
	var rect := Rect2(right - wide, middle - height * 0.5, wide, height)
	chip(ci, rect, alpha, fill)
	ShowTheme.text(ci, words, rect.get_center(), height * 0.5, WHITE, EDGE, maxf(height * 0.09, 1.5), Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
	return rect

## The top bar's band: charcoal with a thin lighter line at its foot.
static func bar_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CHARCOAL
	box.border_color = Color(1, 1, 1, 0.14)
	box.border_width_bottom = 3
	box.shadow_color = Color(0.1, 0.03, 0.2, 0.35)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0.0, 4.0)
	return box

static func theme() -> Theme:
	var result := Theme.new()
	var display := font()
	result.default_font = display
	result.default_font_size = 22
	for kind: String in ["Button", "OptionButton", "CheckBox", "LineEdit", "Label"]:
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			result.set_color(key, kind, ON_DARK)
		result.set_color("font_disabled_color", kind, Color(ON_DARK, 0.6))
	result.set_font("font", "Button", display)
	result.set_font_size("font_size", "Button", 24)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		result.set_stylebox(state, "Button", style("plain", "pressed" if state == "hover_pressed" else state))
	result.set_stylebox("focus", "Button", focus_ring())
	result.set_stylebox("normal", "LineEdit", pill_box(false, 14, 3))
	result.set_stylebox("focus", "LineEdit", focus_ring(2.0, 2))
	result.set_stylebox("panel", "PopupMenu", panel("sheet", 14, 8))
	result.set_color("font_color", "PopupMenu", ON_DARK)
	result.set_color("font_hover_color", "PopupMenu", EDGE)
	var hover := pill_box(false, 10, 0)
	hover.bg_color = YELLOW
	result.set_stylebox("hover", "PopupMenu", hover)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(1, 1, 1, 0.85)
	grabber.set_corner_radius_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)
	track.set_corner_radius_all(6)
	track.content_margin_left = 8
	track.content_margin_right = 8
	for kind: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("grabber", kind, grabber)
		result.set_stylebox("grabber_highlight", kind, grabber)
		result.set_stylebox("grabber_pressed", kind, grabber)
		result.set_stylebox("scroll", kind, track)
		result.set_stylebox("scroll_focus", kind, track)
	return result

# ------------------------------------------------------------------ labels and buttons (the Ui helpers of the kit's look)

## A Label in the display font. `outline` > 0 gives it the dark violet edge (words straight over a page).
static func label(value: String, font_size := 22, color := ON_DARK, outline := 0) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_override("font", font())
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	if outline > 0:
		result.add_theme_constant_override("outline_size", outline)
		result.add_theme_color_override("font_outline_color", EDGE)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func heading(value: String, font_size := 56, color := WHITE) -> Label:
	return label(value, font_size, color, maxi(roundi(font_size * 0.12), 3))

## A small caption line (capitals, muted on a sheet).
static func overline(value: String, color := MUTED_ON_DARK, font_size := 16) -> Label:
	return label(value.to_upper(), font_size, color)

## An action button: a Chunk plate (the primary colour, else the cyan), the display font on it. menu_skin.gd letters over it.
static func button(value: String, primary := false, compact := false) -> Button:
	var result := Button.new()
	result.text = value
	result.theme = theme()
	result.custom_minimum_size.y = 50 if compact else 62
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_override("font", font())
	result.add_theme_font_size_override("font_size", (22 if compact else 26) if primary else (20 if compact else 22))
	result.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kind := "primary" if primary else "plain"
	result.set_meta(&"comic_role", kind)
	dress(result, kind)
	var ink_color := ink(kind)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		result.add_theme_color_override(key, ink_color)
	result.add_theme_color_override("font_disabled_color", Color(DISABLED.ink))
	result.mouse_entered.connect(func() -> void:
		if not result.disabled and result.focus_mode != Control.FOCUS_NONE: result.grab_focus())
	result.focus_entered.connect(func() -> void: Ui.play(result, &"hover"))
	result.pressed.connect(func() -> void: Ui.play(result, &"start" if primary else &"click"))
	return result

# ------------------------------------------------------------------ the full-screen backdrop

## The page behind the menus that have no 3D stage (the title, Settings from the title, the loading, error and notice pages, the customizer): a saturated radial gradient (bright in the middle, a deeper hue at the corners)
## with concentric rings turning outward from `at` (shares of the rect) and a soft glow. `tone`: "sun" (the default, follows the brand), "sea", "berry", "grape". `clock` is seconds.
static func draw_backdrop(ci: CanvasItem, rect: Rect2, clock: float, tone := "sun", at := Vector2(0.5, 0.52), rings := true) -> void:
	var base := backdrop_base(tone)
	var edge_color := Color.from_hsv(fposmod(base.h - 0.014, 1.0), minf(base.s + 0.02, 1.0), base.v * 0.95)
	var centre_color := Color.from_hsv(fposmod(base.h + 0.012, 1.0), base.s * 0.88, 1.0)
	var middle := rect.position + rect.size * at
	var reach := maxf(maxf(middle.distance_to(rect.position), middle.distance_to(rect.end)), maxf(middle.distance_to(Vector2(rect.end.x, rect.position.y)), middle.distance_to(Vector2(rect.position.x, rect.end.y))))
	ci.draw_rect(rect, edge_color)
	var steps := 14
	for step in steps:
		var share := 1.0 - float(step) / float(steps) # from the outside in
		ci.draw_circle(middle, reach * share * 0.92, edge_color.lerp(centre_color, pow(1.0 - share, 0.8)), true, -1.0, true)
	if rings:
		var spacing := rect.size.y * 0.21
		var phase := fposmod(clock * 0.045, 1.0)
		var count := int(ceilf(reach / spacing)) + 2
		for index in count:
			var r := (float(index) + phase) * spacing
			if r < spacing * 0.2: continue
			var fade := clampf(1.0 - r / (reach * 1.1), 0.25, 1.0)
			ci.draw_arc(middle, r, 0.0, TAU, 128, Color(1.0, 0.98, 0.78, 0.2 * fade), spacing * 0.42, true)
	ci.draw_circle(middle, rect.size.y * 0.42, Color(1, 1, 0.85, 0.07), true, -1.0, true)
	ci.draw_circle(middle, rect.size.y * 0.24, Color(1, 1, 0.85, 0.07), true, -1.0, true)

## A wash for the pause menu over the live world (a violet tint, lighter in the middle of a run so the world stays readable).
static func wash_color(in_game: bool) -> Color:
	return Color(0.22, 0.08, 0.5, 0.58 if in_game else 0.9)

## The results' corner stripes (the finish look of the podium): orange, yellow and cyan bands cutting the top left corner of `rect`. `unit` is the band's width, px.
static func corner_ribbons(ci: CanvasItem, rect: Rect2, unit: float, alpha := 1.0) -> void:
	var bands := [[Color("ff7a1a"), 1.0], [Color("ffc21a"), 2.0], [secondary_color(), 3.0]]
	var previous := 0.0
	for band: Array in bands:
		var reach: float = float(band[1]) * unit
		var o := rect.position
		var pts := PackedVector2Array([o + Vector2(previous, 0.0), o + Vector2(reach, 0.0), o + Vector2(0.0, reach), o + Vector2(0.0, previous)])
		ci.draw_colored_polygon(pts, Color(band[0], alpha))
		previous = reach

## A leaning slab (a parallelogram with round corners) of `rect`: `fill`, a `rim` px wide rim in `rim_color`, a soft drop shadow; `shear` leans the top to the right (0.12 is the results' rows).
static func slab(ci: CanvasItem, rect: Rect2, fill: Color, rim_color: Color, rim: float, shear := 0.12, radius := -1.0, alpha := 1.0) -> void:
	var r := rect.size.y * 0.32 if radius < 0.0 else radius
	var cy := rect.get_center().y
	var pad := absf(shear) * rect.size.y * 0.5
	var body := Rect2(rect.position.x + pad, rect.position.y, rect.size.x - pad * 2.0, rect.size.y)
	_slab_layer(ci, Rect2(body.position + Vector2(0.0, rect.size.y * 0.08), body.size), Color(0.16, 0.04, 0.3, 0.32 * alpha), r, shear, cy + rect.size.y * 0.08)
	if rim > 0.0:
		_slab_layer(ci, body, Color(rim_color, rim_color.a * alpha), r, shear, cy)
	_slab_layer(ci, body.grow(-rim), Color(fill, fill.a * alpha), maxf(r - rim, 0.0), shear, cy)

static func _slab_layer(ci: CanvasItem, rect: Rect2, color: Color, radius: float, shear: float, cy: float) -> void:
	var points := Chunk.rounded_polygon(rect, radius, shear, cy)
	ci.draw_colored_polygon(points, color)
	var edge := points.duplicate()
	edge.append(points[0])
	ci.draw_polyline(edge, color, 1.4, true)

# ------------------------------------------------------------------ medals

const SILVER := Color("cfd8e3")
const SILVER_DEEP := Color("7d8a9c")
const BRONZE := Color("e39a58")
const BRONZE_DEEP := Color("8c4b1c")

## The rank medal at `centre`: gold, silver and bronze for 1-3, a violet disc with a white rim after.
static func rank_badge(ci: CanvasItem, centre: Vector2, radius: float, rank: int, alpha := 1.0) -> void:
	var fill := ShowTheme.GOLD
	var deep := ShowTheme.GOLD_DEEP
	var number_fill := ShowTheme.CREAM
	if rank == 2:
		fill = SILVER
		deep = SILVER_DEEP
	elif rank == 3:
		fill = BRONZE
		deep = BRONZE_DEEP
	if rank >= 1 and rank <= 3:
		ci.draw_circle(centre + Vector2(0.0, radius * 0.1), radius * 1.1, Color(EDGE, 0.9 * alpha), true, -1.0, true)
		ci.draw_circle(centre + Vector2(0.0, radius * 0.08), radius * 1.04, Color(WHITE, alpha), true, -1.0, true)
		ci.draw_circle(centre + Vector2(0.0, radius * 0.08), radius, Color(deep, alpha), true, -1.0, true)
		ci.draw_circle(centre, radius, Color(fill, alpha), true, -1.0, true)
		ci.draw_arc(centre, radius * 0.8, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.5 * alpha), radius * 0.1, true)
		ShowTheme.text(ci, str(rank), centre, radius * 1.25, number_fill, deep.darkened(0.2), radius * 0.24, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
	else:
		ci.draw_circle(centre, radius * 1.08, Color(WHITE, alpha), true, -1.0, true)
		ci.draw_circle(centre, radius, Color(VIOLET_DEEP, alpha), true, -1.0, true)
		ShowTheme.text(ci, str(rank), centre, radius * 1.15, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)

# ------------------------------------------------------------------ the logo

## The show logo: the team's title in big white italic type with a dark violet outline and an extrusion in the primary's shade, and under it, on a cyan chip, the smaller line (the tagline's part of the title).
## It pops in and then bobs for ever. A Control: `fit(width)` sizes it.
class LogoMark extends Control:
	var words := ""
	var line := ""
	var kind := "title"
	var wide := 900.0
	var extrusion := PINK ## the type's extrusion (the primary's lip shade)
	var chip_color := CYAN ## the under-line's chip
	var _age := 0.0
	var _name_size := 100.0

	func _init(title_words := "", under := "", plate_kind := "title") -> void:
		words = title_words
		line = under
		kind = plate_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	## The type's size for `across` px: as big as fits, but never taller than a share of the width.
	func _fit_size(across: float) -> float:
		var unit := ShowTheme.width(words, 100.0) * (1.0 + ShowTheme.SLANT * 0.1) / 100.0
		return minf(across * 0.92 / maxf(unit, 0.01), across * 0.3)

	## The logo takes `width` px across and as much height as it needs.
	func fit(width: float) -> void:
		wide = width
		_name_size = _fit_size(width)
		var tall := _name_size * 0.95
		if line != "": tall += _name_size * 0.52
		custom_minimum_size = Vector2(width, tall * 1.12)
		size = custom_minimum_size
		queue_redraw()

	func _process(delta: float) -> void:
		_age += minf(delta, 0.05)
		if is_visible_in_tree(): queue_redraw()

	func _draw() -> void:
		var pop := ShowTheme.pop_scale(_age, 0.55, 0.3)
		var bob := sin(_age * 1.7) * 0.012
		var name_h := _name_size * 0.95
		var total := name_h + (_name_size * 0.52 if line != "" else 0.0)
		var top := (size.y - total) * 0.5
		var centre_x := size.x * 0.5
		var name_at := Vector2(centre_x, top + name_h * 0.5)
		var turn := -0.035 + bob
		ShowTheme.text(self, words, name_at + Vector2(0.0, _name_size * 0.1), _name_size, Color(0, 0, 0, 0), Color(0.16, 0.04, 0.3, 0.3), _name_size * 0.24, Color(0, 0, 0, 0), 0.0, pop, turn, ShowTheme.SLANT)
		ShowTheme.text(self, words, name_at, _name_size, WHITE, EDGE, _name_size * 0.2, extrusion, _name_size * 0.1, pop, turn, ShowTheme.SLANT)
		if line == "": return
		var small := _name_size * 0.3
		var chip_w := ShowTheme.width(line, small) * (1.0 + ShowTheme.SLANT * 0.1) + small * 1.8
		var chip := Rect2(Vector2(centre_x - chip_w * 0.5, top + name_h + _name_size * 0.04), Vector2(chip_w, small * 1.55))
		var centre := chip.get_center()
		draw_set_transform_matrix(Transform2D(turn, Vector2.ONE * pop, 0.0, centre) * Transform2D(0.0, -centre))
		ShowTheme.box(self, chip.grow(small * 0.1), WHITE, Color(0, 0, 0, 0), 0.0, chip.size.y * 0.5 + small * 0.1)
		ShowTheme.box(self, chip, chip_color, Color(0, 0, 0, 0), 0.0, chip.size.y * 0.5)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		ShowTheme.text(self, line, centre, small, WHITE, EDGE, small * 0.2, Color(0, 0, 0, 0), 0.0, pop, turn, ShowTheme.SLANT)

## The logo of `words` with the small `under` line, in the brand's colours.
static func logo_mark(words: String, under := "") -> LogoMark:
	var mark := LogoMark.new(words, under)
	mark.extrusion = role("primary").lip
	mark.chip_color = secondary_color()
	return mark

## The title as the logo's name and its under-line: a title with a colon, dash, dot or bar splits there ("SUMMER ENGINE: JUST SHIP IT" -> name, line), else the whole title is the name
## and the under-line is empty.
static func logo_words() -> Array:
	var full := TeamCast.title().strip_edges()
	for mark: String in [":", " - ", " · ", " | "]:
		var at := full.find(mark)
		if at > 2 and at < full.length() - 3:
			return [full.substr(0, at).strip_edges(), full.substr(at + mark.length()).strip_edges()]
	return [full, ""]
