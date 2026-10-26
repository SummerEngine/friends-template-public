extends CanvasLayer
## THE FACE WALL (docs/party-show.md): the board that follows every round of THE SHOW. A grid with every player's cell (the team's
## photo from `team_wall` when the cast has one, else the player's colour with their initial, always the name); after a beat the cells
## flip one by one: green with the cast's `qualified` word and a tick, pink with the `eliminated` word and a cross, gold for the
## champion, an ordinal (1ST, 2ND ...) in a points show and after the final; players who were out earlier stay dim. Client only, pure look:
## it reads only the show state, and its whole animation is a function of the state's phase time `t`, so every peer sees the same wall.
##   FaceWall.new() -> add_child -> setup(seats) -> update(state, start, mine)   # every frame; shows itself in the round's "done" phase only
## It is the round's one result moment: `start` is how many seconds into the phase it comes up (the local banner has the screen before it,
## never both at once; `INF` keeps it down, a show for one has no wall), `mine` the local slot: its cell is lifted out of the grid with a ring.
const TeamCast := preload("res://style/team_cast.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const Rules := preload("res://modes/show/rules.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const Kit := preload("res://style/show_hud_kit.gd")

const THROUGH := Color("#1fbf6b")
const OUT := Color("#e23d78")
const GOLD := Color("#ffc928")
const NEUTRAL := Color("#262a33")
const DIM := Color("#3a3d46")
const FLIP_FROM := 0.5 ## s after the wall comes up before the first cell flips
const FLIP_STEP := 0.14 ## s between two cells
const FLIP_TIME := 0.3
const FADE := 0.3
const SINGLE_ROW := 6 ## up to this many players stand in one row, more in two
const HEADER_CAP := 34.0 ## header cap height at 720 px
const BAND_TOP := 0.1 ## the wall lives between this share of the screen height and the bottom margin; it is centred in that band
const MINE_SCALE := 1.06 ## the local player's own cell is a little larger than the rest

## One player's cell: drawn by hand so the flip is a scale and a face swap.
class Cell extends Control:
	var photo: Texture2D
	var color := Color.WHITE
	var player_name := ""
	var result := "" ## the word of the result face ("" = still the neutral face)
	var result_color := Color.WHITE
	var mark := 0 ## 1 tick, 2 cross, 0 none
	var dim := false
	var mine := false ## the local player's own cell: a ring around it

	func _draw() -> void:
		var wide := size.x
		var tall := size.y
		var flipped := result != ""
		var face := result_color if flipped else (DIM if dim else NEUTRAL)
		ShowTheme.box(self, Rect2(Vector2.ZERO, size), face, Color(1.0, 1.0, 1.0, 0.55), maxf(wide * 0.012, 1.4), wide * 0.1)
		if mine:
			var ring := StyleBoxFlat.new()
			ring.draw_center = false
			ring.set_border_width_all(maxi(3, roundi(wide * 0.035)))
			ring.border_color = ShowTheme.GOLD
			ring.set_corner_radius_all(roundi(wide * 0.16))
			ring.set_expand_margin_all(ring.border_width_left * 0.5)
			ring.anti_aliasing = true
			draw_style_box(ring, Rect2(Vector2.ZERO, size))
		var pad := wide * 0.07
		var art := Rect2(pad, pad, wide - pad * 2.0, tall * 0.58)
		var alpha := 0.45 if dim else 1.0
		if photo != null:
			draw_texture_rect_region(photo, art, _cover(photo, art.size), Color(1, 1, 1, alpha))
		else:
			draw_rect(art, Color(color, alpha))
			var letter_size := art.size.y * 0.8
			var ink := Color("#16181d") if color.get_luminance() > 0.55 else Color.WHITE
			ShowTheme.text(self, player_name.left(1), art.get_center(), letter_size, ink, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
		draw_rect(art, Color(color, alpha), false, maxf(2.0, wide * 0.03))
		var line_top := art.end.y + pad * 0.6
		var line := Rect2(pad, line_top, wide - pad * 2.0, tall - line_top - pad)
		if flipped: # the result word below; the name stays on a strip over the bottom of the picture
			var strip := Rect2(art.position.x, art.end.y - art.size.y * 0.27, art.size.x, art.size.y * 0.27)
			draw_rect(strip, Color(0.04, 0.05, 0.08, 0.7 * alpha))
			_fit(player_name, strip.grow_individual(-pad * 0.4, 0.0, -pad * 0.4, -strip.size.y * 0.06), Color(1, 1, 1, alpha))
			_fit(result, line, Color("#16181d") if result_color.get_luminance() > 0.55 else Color.WHITE)
		else: _fit(player_name, line, Color(1, 1, 1, alpha))
		if mark != 0:
			var unit := art.size.y * 0.17
			var at := Vector2(art.end.x - unit * 1.1, art.position.y + unit * 1.1)
			var thick := maxf(3.0, unit * 0.45)
			draw_circle(at, unit * 1.35, Color(face, 0.95))
			if mark == 1:
				draw_polyline(PackedVector2Array([at + Vector2(-0.9, 0.0) * unit, at + Vector2(-0.2, 0.8) * unit, at + Vector2(1.0, -0.9) * unit]), Color.WHITE, thick)
			else:
				draw_line(at + Vector2(-0.8, -0.8) * unit, at + Vector2(0.8, 0.8) * unit, Color.WHITE, thick)
				draw_line(at + Vector2(0.8, -0.8) * unit, at + Vector2(-0.8, 0.8) * unit, Color.WHITE, thick)

	## `text` as large as fits `rect` (one line, slanted display type), centred.
	func _fit(text: String, rect: Rect2, ink: Color) -> void:
		var reference := 64.0
		var measured := ShowTheme.width(text, reference) * (1.0 + ShowTheme.SLANT * 0.1)
		var font_size := minf(reference * rect.size.x / maxf(measured, 1.0), rect.size.y / ShowTheme.CAP * 0.85)
		ShowTheme.text(self, text, rect.get_center(), maxf(font_size, 8.0), ink, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, ink.a)

	## The part of a picture that covers a box of this shape (centred).
	static func _cover(texture: Texture2D, box: Vector2) -> Rect2:
		var source := Vector2(texture.get_width(), texture.get_height())
		var shown := box / maxf(box.x / source.x, box.y / source.y)
		return Rect2((source - shown) * 0.5, shown)

## The wall's dark panel with the thin light outline.
class Backdrop extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		ShowTheme.box(self, Rect2(Vector2.ZERO, size), Color(ShowTheme.PILL, 0.9), ShowTheme.PILL_EDGE, 1.6, minf(size.y * 0.06, 26.0))

## The header: a dark pill with `words`.
class Head extends Control:
	var words := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if words != "": ShowTheme.pill_words(self, words, size.x, size.y * 0.5, size.y)

var seats: Array = []
var _dim: Backdrop
var _header: Control
var _cells: Array = [] ## per slot: Cell
var _unit := 1.0
var _size := Vector2.ZERO
var _head_at := 0.0
var _touch := false ## the phone's overlay is up: the wall stays between the stick and the buttons

func _init() -> void:
	layer = 24 # over the show's HUD (23)
	visible = false

## `round_seats`: slot -> cast index (the view's seats).
func setup(round_seats: Array) -> void:
	seats = round_seats.duplicate()
	_dim = Backdrop.new()
	add_child(_dim)
	_header = Head.new()
	add_child(_header)
	var wall := TeamCast.team_wall()
	for slot in seats.size():
		var seat := int(seats[slot])
		var cell := Cell.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.player_name = str(TeamCast.player(seat).name).to_upper()
		cell.color = TeamCast.player_color(seat)
		for entry: Dictionary in wall:
			if str(entry.name) == cell.player_name and entry.picture != null: cell.photo = entry.picture
		_cells.append(cell)
		add_child(cell)

## Every frame with the newest show state.
func update(state: Dictionary, start := 0.0, mine := -1) -> void:
	var phase_t := float(state.get("t", 0.0))
	var t := phase_t - start
	visible = str(state.get("phase", "")) == "done" and not _cells.is_empty() and t >= 0.0
	if not visible: return
	var view := get_viewport().get_visible_rect().size
	var touching := TouchControls.showing(get_tree())
	if view != _size or touching != _touch:
		_touch = touching
		_size = view
		_layout(view)
	var status := _list(state, "status")
	var field := _list(state, "field")
	var place := _list(state, "place")
	var final := str(state.get("kind", "")) == "final"
	var ordinals := bool(state.get("points_mode", false)) or final
	var fade := clampf(t / FADE, 0.0, 1.0) * clampf((Rules.DONE - phase_t) / FADE, 0.0, 1.0)
	_dim.modulate.a = fade
	_header.modulate.a = fade
	var order: Array = place.duplicate() # the round's best flip first, so the greens come before the pinks
	for slot in _cells.size():
		if not order.has(slot): order.append(slot)
	var through := 0
	var out := 0
	for slot in _cells.size():
		var cell: Cell = _cells[slot]
		var code := int(status[slot]) if slot < status.size() else 0
		var playing := field.has(slot)
		var flip := clampf((t - FLIP_FROM - order.find(slot) * FLIP_STEP) / FLIP_TIME, 0.0, 1.0) if playing else 1.0
		cell.dim = not playing
		cell.modulate.a = fade
		cell.scale = Vector2(absf(cos(flip * PI)) if flip < 1.0 else 1.0, 1.0) * (MINE_SCALE if slot == mine else 1.0)
		var word := ""
		var color := Color.WHITE
		var mark := 0
		if code == 1 and not ordinals: word = TeamCast.show_word("qualified"); color = THROUGH; mark = 1
		elif code == 2: word = TeamCast.show_word("eliminated"); color = OUT; mark = 2
		elif code == 3: word = TeamCast.show_word("eliminated"); color = DIM
		elif code == 4: word = TeamCast.show_word("champion"); color = GOLD; mark = 1
		elif ordinals and playing: word = ordinal(place.find(slot) + 1); color = GOLD if place.find(slot) == 0 else ShowTheme.BLUE
		through += 1 if code == 1 and not ordinals else 0
		out += 1 if code == 2 else 0
		if playing and flip < 0.5: word = "" # the neutral face until the card has turned
		if cell.result != word or cell.result_color != color or cell.mark != mark or cell.mine != (slot == mine):
			cell.mine = slot == mine
			cell.result = word
			cell.result_color = color
			cell.mark = mark if word != "" else 0
			cell.queue_redraw()
	var header := ("THE FINAL" if final else "ROUND %d" % int(state.get("round", 1))) if ordinals else "%d THROUGH  ·  %d OUT" % [through, out]
	var height := HEADER_CAP * _unit * 1.5
	var wide := ShowTheme.width(header, height * 0.5) * (1.0 + ShowTheme.SLANT * 0.1) + height * 1.14 + height * 0.7
	(_header as Head).words = header
	_header.size = Vector2(wide, height)
	_header.position = Vector2((view.x - wide) * 0.5, _head_at)
	_header.queue_redraw()

func _layout(view: Vector2) -> void:
	_unit = Kit.k(_dim)
	var count := _cells.size()
	var columns := count if count <= SINGLE_ROW else ceili(count / 2.0)
	var rows := ceili(float(count) / maxf(columns, 1.0))
	var band := Rect2(view.x * 0.03, view.y * BAND_TOP, view.x * 0.94, view.y * (0.97 - BAND_TOP)) # the wall has the screen to itself
	if _touch: band = Rect2(view.x * 0.17, view.y * BAND_TOP, view.x * 0.66, view.y * (0.74 - BAND_TOP)) # between the stick and the buttons of a phone
	var pad := band.size.y * 0.04
	var head := HEADER_CAP * _unit * 2.0
	var room := Vector2(band.size.x - pad * 2.0, band.size.y - head - pad * 2.5)
	var gap := room.x * 0.015
	var cell_wide := minf((room.x - gap * (columns - 1)) / columns, 190.0 * _unit)
	var cell_tall := minf((room.y - gap * (rows - 1)) / rows, cell_wide * 1.18)
	cell_wide = minf(cell_wide, cell_tall / 0.95) # the cell is a little taller than wide, never wider than tall
	var grid := Vector2(cell_wide * columns + gap * (columns - 1), cell_tall * rows + gap * (rows - 1))
	var panel := Rect2(Vector2((view.x - maxf(grid.x + pad * 2.0, view.x * 0.4)) * 0.5, band.position.y),
		Vector2(maxf(grid.x + pad * 2.0, view.x * 0.4), head + grid.y + pad * 2.5))
	panel.position.y = band.position.y + (band.size.y - panel.size.y) * 0.5
	_dim.position = panel.position
	_dim.size = panel.size
	_head_at = panel.position.y + pad
	var origin := Vector2((view.x - grid.x) * 0.5, panel.position.y + head + pad)
	for slot in count:
		var cell: Cell = _cells[slot]
		var row := slot / columns
		var in_row := mini(columns, count - row * columns) # a short last row is centred
		cell.size = Vector2(cell_wide, cell_tall)
		cell.pivot_offset = cell.size * 0.5
		cell.position = origin + Vector2((columns - in_row) * (cell_wide + gap) * 0.5 + (slot % columns) * (cell_wide + gap), row * (cell_tall + gap))

static func _list(state: Dictionary, key: String) -> Array:
	var value: Variant = state.get(key, [])
	var result: Array = []
	if value is Array:
		for entry: Variant in value: result.append(int(entry))
	return result

## 1 -> "1ST", 2 -> "2ND", 11 -> "11TH".
static func ordinal(place: int) -> String:
	var tail := place % 100
	if tail >= 11 and tail <= 13: return "%dTH" % place
	match place % 10:
		1: return "%dST" % place
		2: return "%dND" % place
		3: return "%dRD" % place
	return "%dTH" % place
