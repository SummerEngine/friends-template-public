extends Control
## The call window on the victim's screen (call_view.gd builds one per call effect on the local courier, in the manager's over_layer). An INCOMING CALL toast rings for TOAST s, then a
## dark video-call window pops in over `cover` of the screen (by area), centred, so a strip of the game stays visible around it. The window's content (the shared screen, the tiles, the toolbar) stays inside FREE, the part of the screen the HUD leaves clear, so the HUD's pills (objectives and item pill, scoreboard, timer, hints) land on the window's dark frame gutters, never on the content. In the window: the shared screen (the cast's footage in a
## VideoStreamPlayer, or a spreadsheet drawn in code), the other callers as letter tiles in their colours, and a toolbar with a muted mic, a switched-off camera and a big red DECLINE button.
## Every GRAB tap of the victim shakes DECLINE hard and squishes it; a small ring beside it shows the seconds left and how many taps have landed. The window closes with a quick shrink.
## Pure drawing: when the call ends is the authority's (the effect leaves the state); the window only plays the end.
const ShowTheme := preload("res://client/show_theme.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Glyph := preload("res://modes/show/items_ui/call_glyph.gd")
const Catalog := preload("res://modes/show/items/catalog.gd")
const INTER := preload("res://assets/fonts/Inter.ttf")

const TOAST := 0.35 ## s of the INCOMING CALL toast before the window opens
const POP := 0.5 ## s the window takes to pop in (it overshoots)
const CLOSE := 0.2 ## s of the closing shrink
const FREE := Rect2(0.17, 0.085, 0.66, 0.84) ## the share of the screen the HUD leaves clear: the window's content is laid out inside it
const FRAME := Color(0.082, 0.09, 0.118)
const TITLE := Color(0.118, 0.128, 0.165)
const TILE := Color(0.135, 0.145, 0.19)
const INK := Color(0.82, 0.85, 0.92)
const SOFT := Color(0.55, 0.59, 0.68)
const GREEN := Color(0.33, 0.82, 0.5)
const WGHT := 2003265652 ## the OpenType tag "wght"

static var _bold: FontVariation

var look ## call_view.gd
var fx: Dictionary
var cover := 0.72
var caller_slot := -1
var age := 0.0
var closing := -1.0 ## s since the close began, -1 while open
var taps := 0
var shake := 0.0 ## 0..1.6: how hard DECLINE shakes now
var squish := 0.0
var squish_speed := 0.0
var pinged := 0.0 ## s since the last tap (the ring flashes)
var _grab_seen := -1
var _panel: Control
var _toast: Control
var _screen: Control ## the footage or the sheet
var _video: VideoStreamPlayer
var _over: Control
var _started := false
var _laid := Vector2.ZERO

class Face extends Control:
	var win
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		win.paint_panel(self)

class Over extends Control:
	var win
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		win.paint_over(self)

class Toast extends Control:
	var win
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		win.paint_toast(self)

## The spreadsheet that stands in for the footage: a white sheet slowly scrolling, a formula bar, a cell cursor that hops about.
class Sheet extends Control:
	var clock := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _draw() -> void:
		var u := size.y / 320.0
		var bar := 24.0 * u
		var head := 18.0 * u
		var side := 30.0 * u
		var cell := Vector2(74.0 * u, 20.0 * u)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.975, 0.977, 0.982))
		var scroll := clock * 7.0 * u
		var first := int(floor(scroll / cell.y))
		var shift := fmod(scroll, cell.y)
		var cols := int(ceil((size.x - side) / cell.x)) + 1
		var rows := int(ceil((size.y - bar - head) / cell.y)) + 2
		var grid := Color(0.84, 0.86, 0.9)
		for row in rows:
			var y := bar + head + float(row) * cell.y - shift
			var number := first + row + 1
			draw_line(Vector2(0.0, y + cell.y), Vector2(size.x, y + cell.y), grid, 1.0)
			for col in cols:
				var x := side + float(col) * cell.x
				if row == 0: draw_line(Vector2(x, bar + head), Vector2(x, size.y), grid, 1.0)
				var mix := (number * 73856093) ^ (col * 19349663)
				var value := absi(mix) % 9000 + 500
				var words := "%d,%03d" % [value / 1000, value % 1000] if col % 3 != 0 else ("%d.%d%%" % [absi(mix >> 3) % 90 + 4, absi(mix >> 7) % 10])
				if col == 0: words = ["MRR", "USERS", "CAC", "CHURN", "COMPUTE", "ARPU"][absi(number) % 6]
				draw_string(INTER, Vector2(x + 6.0 * u, y + cell.y - 6.0 * u), words, HORIZONTAL_ALIGNMENT_LEFT, cell.x - 8.0 * u, roundi(10.0 * u), Color(0.22, 0.25, 0.32) if col != 0 else Color(0.1, 0.12, 0.18))
			draw_rect(Rect2(0.0, y, side, cell.y), Color(0.93, 0.94, 0.96))
			draw_string(INTER, Vector2(4.0 * u, y + cell.y - 6.0 * u), str(number), HORIZONTAL_ALIGNMENT_LEFT, side - 4.0 * u, roundi(9.0 * u), Color(0.45, 0.48, 0.56))
		draw_rect(Rect2(0.0, bar, size.x, head), Color(0.93, 0.94, 0.96))
		for col in cols:
			draw_string(INTER, Vector2(side + float(col) * cell.x + cell.x * 0.5 - 3.0 * u, bar + head - 5.0 * u), char(65 + col % 26), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(9.0 * u), Color(0.4, 0.43, 0.5))
		draw_rect(Rect2(0.0, 0.0, size.x, bar), Color(1, 1, 1))
		draw_line(Vector2(0.0, bar), Vector2(size.x, bar), grid, 1.0)
		draw_string(INTER, Vector2(8.0 * u, bar - 8.0 * u), "fx", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * u), Color(0.45, 0.48, 0.56))
		draw_string(INTER, Vector2(34.0 * u, bar - 8.0 * u), ["=B2*C2", "=SUM(B2:B13)", "=D7/E7", "=AVERAGE(C2:C13)"][int(clock / 1.6) % 4], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(11.0 * u), Color(0.15, 0.17, 0.24))
		var hop := int(clock / 1.6)
		var eased := ease(clampf(fmod(clock, 1.6) / 0.25, 0.0, 1.0), 0.4)
		var at := _spot(hop - 1, cols, rows, side, bar + head, cell, shift).lerp(_spot(hop, cols, rows, side, bar + head, cell, shift), eased)
		draw_rect(Rect2(at, cell), Color(0.24, 0.48, 1.0, 0.12))
		draw_rect(Rect2(at, cell), Color(0.24, 0.48, 1.0), false, 2.0 * u)

## Where the cursor stands on its `hop`-th stop.
	func _spot(hop: int, cols: int, rows: int, side: float, top: float, cell: Vector2, shift: float) -> Vector2:
		return Vector2(side + float(posmod(hop * 5, maxi(cols - 1, 1))) * cell.x, top + float(2 + posmod(hop * 3, maxi(rows - 4, 1))) * cell.y - shift)

static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = INTER
		_bold.variation_opentype = {WGHT: 700}
	return _bold

## Builds the window for the effect `entry` (`mine` on the local courier), shown through `owner_look`; `media` is the footage's path or "".
func setup(owner_look, entry: Dictionary, media: String) -> void:
	look = owner_look
	fx = entry
	cover = clampf(float(entry.get("a", 0.72)), 0.3, 0.95)
	caller_slot = int(entry.get("src", -1))
	name = "CallWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Face.new()
	_panel.win = self
	_panel.name = "Panel"
	add_child(_panel)
	var video := media != "" and DisplayServer.get_name() != "headless" and ClassDB.class_exists("VideoStreamTheora")
	if video:
		var stream: VideoStream = load(media) as VideoStream if ResourceLoader.exists(media) else null
		if stream == null:
			stream = ClassDB.instantiate("VideoStreamTheora") as VideoStream
			if stream != null: stream.file = media
		if stream != null:
			_video = VideoStreamPlayer.new()
			_video.name = "Footage"
			_video.stream = stream
			_video.expand = true
			_video.volume_db = -80.0
			_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if "loop" in _video: _video.set("loop", true)
			else: _video.finished.connect(_video.play)
			_screen = _video
	if _screen == null:
		_screen = Sheet.new()
		_screen.name = "Sheet"
	_panel.add_child(_screen)
	_over = Over.new()
	_over.win = self
	_panel.add_child(_over)
	_toast = Toast.new()
	_toast.win = self
	_toast.name = "Toast"
	add_child(_toast)
	_panel.visible = false

## Where the window is on the screen now (position and size before the pop's scale).
func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if _panel != null else Rect2()

## The share of the screen's area the window covers (before the pop's scale).
func cover_ratio() -> float:
	var view := get_viewport_rect().size
	return _panel.size.x * _panel.size.y / maxf(view.x * view.y, 1.0)

func has_footage() -> bool:
	return _video != null

func close() -> void:
	if closing < 0.0: closing = 0.0

func _process(delta: float) -> void:
	if closing >= 0.0:
		closing += delta
		if closing >= CLOSE:
			queue_free()
			return
	else:
		age = float(fx.get("age", age))
		_read_taps()
	shake = maxf(shake - (shake * 7.0 + 0.4) * delta, 0.0)
	squish_speed -= (squish * 420.0 + squish_speed * 22.0) * delta
	squish += squish_speed * delta
	pinged += delta
	_place(delta)
	_panel.queue_redraw()
	_over.queue_redraw()
	_toast.queue_redraw()

## The local player's own GRAB taps (game_run.gd grab_taps), counted on this machine as they happen; the authority's count (fx.b) only ever raises the number.
func _read_taps() -> void:
	var run: Variant = look.m.run if look != null and look.m != null else null
	var now := int(run.get("grab_taps")) if run != null and run.get("grab_taps") != null else 0
	if _grab_seen < 0: _grab_seen = now
	if now > _grab_seen:
		var fresh := now - _grab_seen
		_grab_seen = now
		taps += fresh
		shake = minf(shake + 1.0, 1.6)
		squish_speed += 4.5 * minf(float(fresh), 2.0)
		pinged = 0.0
		look.m.sfx("call", "tap", null, -4.0)
	taps = maxi(taps, int(float(fx.get("b", 0.0))))

func _place(delta: float) -> void:
	var view := get_viewport_rect().size
	var panel := (view * sqrt(cover)).floor()
	var open := age - TOAST
	var pop := 0.0
	if open > 0.0: pop = ShowTheme.pop_scale(open, POP, 0.12)
	var scale_now := pop
	if closing >= 0.0: scale_now = pop * (1.0 - ease(clampf(closing / CLOSE, 0.0, 1.0), 2.2))
	_panel.visible = scale_now > 0.01
	_panel.size = panel
	_panel.position = ((view - panel) * 0.5).floor()
	_panel.pivot_offset = panel * 0.5
	_panel.scale = Vector2.ONE * maxf(scale_now, 0.001)
	_panel.modulate.a = clampf(open / 0.08, 0.0, 1.0) * (1.0 - clampf((closing - CLOSE * 0.5) / (CLOSE * 0.5), 0.0, 1.0) if closing >= 0.0 else 1.0)
	if _laid != panel:
		_laid = panel
		var rects := layout(panel)
		var video: Rect2 = rects.video
		_screen.position = video.position
		_screen.size = video.size
		_over.position = Vector2.ZERO
		_over.size = panel
	if _screen is Sheet: (_screen as Sheet).clock = age
	_screen.queue_redraw()
	if _video != null and open >= 0.0 and not _started:
		_started = true
		_video.play()

## The window's parts as rects in its own coordinates.
func layout(size: Vector2) -> Dictionary:
	var u := size.y / 600.0
	var pad := 12.0 * u
	var title_h := 44.0 * u
	var bar_h := 96.0 * u
	var gap := 10.0 * u
	var view := get_viewport_rect().size
	var origin := ((view - size) * 0.5).floor()
	var free := Rect2(view * FREE.position - origin, view * FREE.size).intersection(Rect2(Vector2.ZERO, size)) # FREE in the window's own coordinates
	var left := maxf(free.position.x, pad)
	var content := Rect2(left, title_h, minf(free.end.x, size.x - pad) - left, minf(free.end.y, size.y) - title_h - bar_h)
	var video_w := minf(content.size.y * 16.0 / 9.0, content.size.x - 170.0 * u - gap)
	var video_h := video_w * 9.0 / 16.0
	var video := Rect2(content.position.x, content.position.y + (content.size.y - video_h) * 0.5, video_w, video_h)
	var column := Rect2(video.end.x + gap, content.position.y, content.end.x - video.end.x - gap, content.size.y)
	var tile_h := (column.size.y - gap * 2.0) / 3.0
	var tiles: Array = []
	for index in 3: tiles.append(Rect2(column.position.x, column.position.y + float(index) * (tile_h + gap), column.size.x, tile_h))
	return {"u": u, "title_h": title_h, "bar": Rect2(content.position.x, content.end.y, content.size.x, bar_h), "video": video, "tiles": tiles, "pad": pad}

# ------------------------------------------------------------------ drawing

func _text(ci: CanvasItem, words: String, at: Vector2, size: float, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font: Font = INTER) -> float:
	var s := maxi(roundi(size), 6)
	var wide := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER: x -= wide * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT: x -= wide
	ci.draw_string(font, Vector2(x, at.y + (font.get_ascent(s) - font.get_descent(s)) * 0.5), words, HORIZONTAL_ALIGNMENT_LEFT, -1, s, color)
	return wide

func paint_panel(ci: Control) -> void:
	var size := ci.size
	var parts := layout(size)
	var u: float = parts.u
	var title_h: float = parts.title_h
	for index in 6: # a soft shadow
		var shade := Rect2(Vector2(0.0, 8.0 * u), size).grow(float(index + 1) * 5.0 * u)
		ShowTheme.box(ci, shade, Color(0, 0, 0, 0.075), Color(0, 0, 0, 0), 0.0, 22.0 * u + float(index) * 5.0 * u)
	ShowTheme.box(ci, Rect2(Vector2.ZERO, size), FRAME, Color(1, 1, 1, 0.22), 1.6 * u, 22.0 * u)
	ShowTheme.box(ci, Rect2(0.0, 0.0, size.x, title_h), TITLE, Color(0, 0, 0, 0), 0.0, 22.0 * u)
	ci.draw_rect(Rect2(0.0, title_h * 0.55, size.x, title_h * 0.45), TITLE)
	ci.draw_line(Vector2(0.0, title_h), Vector2(size.x, title_h), Color(0, 0, 0, 0.35), 1.2 * u)
	for index in 3:
		ci.draw_circle(Vector2((22.0 + 20.0 * float(index)) * u, title_h * 0.5), 6.0 * u, [Color(0.92, 0.38, 0.34), Color(0.95, 0.76, 0.3), Color(0.36, 0.78, 0.42)][index])
	var clock := maxi(int(age - TOAST), 0)
	_text(ci, "SCREEN SHARE", Vector2(size.x * 0.5, title_h * 0.5), 15.0 * u, INK, HORIZONTAL_ALIGNMENT_CENTER, bold())
	_text(ci, "%02d:%02d" % [clock / 60, clock % 60], Vector2(size.x - 22.0 * u, title_h * 0.5), 14.0 * u, SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
	var video: Rect2 = parts.video
	ShowTheme.box(ci, video.grow(2.0 * u), Color(0.02, 0.025, 0.04), Color(1, 1, 1, 0.1), 1.2 * u, 6.0 * u)
	_tiles(ci, parts.tiles, u)
	_toolbar(ci, parts.bar, u)

func _tiles(ci: CanvasItem, tiles: Array, u: float) -> void:
	var me: int = look.m.my_slot
	var others: Array = []
	for slot in look.m.seats.size():
		if slot != me and slot != caller_slot: others.append(slot)
	var cast: Array = [[caller_slot, true, false], [me, false, true], [int(others[0]) if not others.is_empty() else -1, false, false]]
	for index in 3:
		var rect: Rect2 = tiles[index]
		var slot := int((cast[index] as Array)[0])
		var speaking := bool((cast[index] as Array)[1])
		var muted := bool((cast[index] as Array)[2])
		ShowTheme.box(ci, rect, TILE, Color(GREEN, 0.55 + 0.45 * sin(age * 7.0)) if speaking else Color(1, 1, 1, 0.08), 2.4 * u if speaking else 1.2 * u, 10.0 * u)
		var colour := TeamCast.player_color(int(look.m.seats[slot])) if slot >= 0 and slot < look.m.seats.size() else Color(0.35, 0.38, 0.46)
		var words: String = look.m.name_of(slot) if slot >= 0 else "GUEST"
		var centre := rect.get_center() + Vector2(0.0, -rect.size.y * 0.08)
		var radius := minf(rect.size.y * 0.3, rect.size.x * 0.22)
		if speaking: ci.draw_arc(centre, radius * (1.18 + 0.08 * sin(age * 9.0)), 0.0, TAU, 36, Color(GREEN, 0.5), 2.2 * u, true)
		ci.draw_circle(centre, radius, colour)
		_text(ci, words.left(1), centre, radius * 1.05, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, bold())
		var label := ("YOU" if muted else words) if slot >= 0 else words
		_text(ci, label, Vector2(rect.position.x + 9.0 * u, rect.end.y - 12.0 * u), 11.0 * u, INK, HORIZONTAL_ALIGNMENT_LEFT, bold())
		_mic(ci, Vector2(rect.end.x - 14.0 * u, rect.end.y - 12.0 * u), 7.0 * u, muted or index == 2)

func _toolbar(ci: CanvasItem, bar: Rect2, u: float) -> void:
	ShowTheme.box(ci, bar, TITLE, Color(0, 0, 0, 0), 0.0, 22.0 * u)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x, bar.size.y * 0.5)), TITLE)
	ci.draw_line(bar.position, bar.position + Vector2(bar.size.x, 0.0), Color(0, 0, 0, 0.35), 1.2 * u)
	var middle := bar.get_center().y
	var wide := 252.0 * u
	var left := bar.get_center().x - (54.0 * u * 2.0 + 18.0 * u * 2.0 + wide) * 0.5
	var round := 27.0 * u
	var mic := Vector2(left + round, middle)
	var cam := Vector2(left + round * 3.0 + 18.0 * u, middle)
	for centre in [mic, cam]:
		ci.draw_circle(centre, round, Color(0.2, 0.215, 0.27))
		ci.draw_arc(centre, round - 0.8 * u, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 1.4 * u, true)
	_mic(ci, mic, round * 0.5, true, true)
	_camera(ci, cam, round * 0.5)
	_decline(ci, Vector2(left + round * 4.0 + 36.0 * u + wide * 0.5, middle), Vector2(wide, 62.0 * u), u)
	_taps_ring(ci, Vector2(left + round * 4.0 + 36.0 * u + wide + 40.0 * u, middle), 24.0 * u, u)

## A microphone (a capsule on a stem); `slashed` crosses it out in red; `big` draws it as the toolbar's button.
func _mic(ci: CanvasItem, c: Vector2, r: float, slashed := false, big := false) -> void:
	var colour := Color(0.93, 0.95, 0.98) if big else Color(0.78, 0.81, 0.88)
	ShowTheme.box(ci, Rect2(c + Vector2(-r * 0.36, -r * 0.95), Vector2(r * 0.72, r * 1.3)), colour, Color(0, 0, 0, 0), 0.0, r * 0.36)
	ci.draw_arc(c + Vector2(0.0, -r * 0.1), r * 0.7, 0.0, PI, 14, colour, maxf(r * 0.16, 1.2), true)
	ci.draw_line(c + Vector2(0.0, r * 0.6), c + Vector2(0.0, r * 0.98), colour, maxf(r * 0.16, 1.2), true)
	ci.draw_line(c + Vector2(-r * 0.32, r * 0.98), c + Vector2(r * 0.32, r * 0.98), colour, maxf(r * 0.16, 1.2), true)
	if slashed:
		ci.draw_line(c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(r * 0.95, r * 1.05), Color(FRAME, 0.9) if big else FRAME, maxf(r * 0.42, 3.0), true)
		ci.draw_line(c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(r * 0.95, r * 1.05), Glyph.RED, maxf(r * 0.2, 1.6), true)

func _camera(ci: CanvasItem, c: Vector2, r: float) -> void:
	var colour := Color(0.93, 0.95, 0.98)
	ShowTheme.box(ci, Rect2(c + Vector2(-r * 1.0, -r * 0.62), Vector2(r * 1.4, r * 1.24)), colour, Color(0, 0, 0, 0), 0.0, r * 0.22)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.52, -r * 0.18), c + Vector2(r * 1.1, -r * 0.55), c + Vector2(r * 1.1, r * 0.55), c + Vector2(r * 0.52, r * 0.18)]), colour)
	ci.draw_line(c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(r * 0.95, r * 1.05), Color(0.2, 0.215, 0.27), maxf(r * 0.42, 3.0), true)
	ci.draw_line(c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(r * 0.95, r * 1.05), Glyph.RED, maxf(r * 0.2, 1.6), true)

## The big red DECLINE button: it jitters (decaying) on every tap and squishes under it.
func _decline(ci: CanvasItem, c: Vector2, size: Vector2, u: float) -> void:
	var jitter := Vector2(sin(age * 83.0) + 0.6 * sin(age * 51.0 + 1.0), cos(age * 71.0) + 0.5 * cos(age * 47.0)) * 13.0 * u * shake
	var tilt := sin(age * 61.0) * 0.07 * shake
	ci.draw_set_transform_matrix(Transform2D(tilt, Vector2(1.0 + squish * 0.6, 1.0 - squish), 0.0, c + jitter))
	var rect := Rect2(-size * 0.5, size)
	var flash := clampf(1.0 - pinged / 0.18, 0.0, 1.0)
	var body := Glyph.RED.lerp(Color(1.0, 0.55, 0.52), flash * 0.7)
	ShowTheme.box(ci, Rect2(rect.position + Vector2(0.0, 5.0 * u), rect.size), Glyph.RED_DEEP, Color(0, 0, 0, 0), 0.0, size.y * 0.5)
	ShowTheme.box(ci, rect, body, Color(1, 1, 1, 0.5), 1.6 * u, size.y * 0.5)
	Glyph.draw_handset(ci, Vector2(-size.x * 0.5 + size.y * 0.66, size.y * 0.02), size.y * 0.3, Color.WHITE, PI)
	_text(ci, "DECLINE", Vector2(size.y * 0.2, -size.y * 0.07), size.y * 0.4, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold())
	_text(ci, "TAP GRAB", Vector2(size.y * 0.2, size.y * 0.28), size.y * 0.15, Color(1, 1, 1, 0.78), HORIZONTAL_ALIGNMENT_CENTER, bold())
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## Beside DECLINE: a ring with the seconds left (it jumps down on a tap), the taps landed in the middle.
func _taps_ring(ci: CanvasItem, c: Vector2, r: float, u: float) -> void:
	var goal := maxf(float(fx.get("dur", 6.0)) - Catalog.tuning("call", "tap") * float(taps), Catalog.tuning("call", "least")) # the effect's own `dur` is the window as it opened: each tap takes `tap` off, never below `least`
	var left := clampf(1.0 - age / maxf(goal, 0.1), 0.0, 1.0)
	var lit := clampf(1.0 - pinged / 0.25, 0.0, 1.0)
	ci.draw_circle(c, r + 3.0 * u, Color(0, 0, 0, 0.3))
	ci.draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.14), 4.0 * u, true)
	ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * left, 40, Glyph.RED.lerp(Color.WHITE, lit * 0.6) if left > 0.0 else Color(0, 0, 0, 0), 4.0 * u, true)
	_text(ci, str(taps), c + Vector2(0.0, -r * 0.12), r * 0.95 * (1.0 + 0.3 * lit), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bold())
	_text(ci, "TAPS" if taps != 1 else "TAP", c + Vector2(0.0, r * 0.56), r * 0.34, SOFT, HORIZONTAL_ALIGNMENT_CENTER, bold())

## Over the footage: the caller's name chip and a live dot.
func paint_over(ci: Control) -> void:
	var parts := layout(ci.size)
	var u: float = parts.u
	var video: Rect2 = parts.video
	var caller: String = look.m.name_of(caller_slot) if caller_slot >= 0 else "SOMEONE"
	var words := "%s IS PRESENTING" % caller
	var font := bold()
	var h := 26.0 * u
	var wide := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12.0 * u)).x + 48.0 * u
	var rect := Rect2(video.position + Vector2(10.0 * u, video.size.y - h - 10.0 * u), Vector2(wide, h))
	ShowTheme.box(ci, rect, Color(0.05, 0.055, 0.08, 0.82), Color(1, 1, 1, 0.12), 1.0, h * 0.5)
	ci.draw_circle(rect.position + Vector2(h * 0.55, h * 0.5), 4.5 * u * (1.0 + 0.2 * sin(age * 8.0)), Glyph.RED)
	_text(ci, words, rect.position + Vector2(h * 0.95, h * 0.5), 12.0 * u, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, font)

func paint_toast(ci: Control) -> void:
	if age > TOAST + 0.16 or closing >= 0.0: return
	var view := ci.get_viewport_rect().size
	var k := ShowTheme.unit(ci)
	var pop := ShowTheme.pop_scale(age, 0.22, 0.35)
	var fade := 1.0 - clampf((age - TOAST) / 0.16, 0.0, 1.0)
	var height := 84.0 * k
	var wide := 378.0 * k
	var c := view * 0.5
	var pulse := 1.0 + 0.05 * sin(age * 34.0)
	var s := pop * pulse
	var rect := Rect2(c - Vector2(wide, height) * 0.5 * s, Vector2(wide, height) * s)
	ShowTheme.pill(ci, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, 2.0 * k, fade)
	var icon := Vector2(rect.position.x + height * 0.5 * s + 6.0 * k * s, c.y)
	var r := height * 0.38 * s
	var light := Color(Glyph.LIGHT, fade)
	Glyph.draw_handset(ci, icon + Vector2(0.0, r * 0.2), r * 0.72, light, sin(age * 44.0) * 0.32)
	Glyph.draw_waves(ci, icon + Vector2(0.0, r * 0.1), r * 0.9, r * 0.3, 3.0 * k, light, 3, int(age * 5.0) % 3)
	ShowTheme.text(ci, "INCOMING CALL", Vector2(rect.position.x + rect.size.x * 0.58, c.y), 34.0 * k * s, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, fade)
