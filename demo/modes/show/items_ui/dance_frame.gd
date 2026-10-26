extends Control
## The victim's vertical frame of the DANCE (modes/show/items_ui/dance_view.gd), one per effect on the local screen: dark bars that close in to a centred 9:16 frame (and open again over the last
## BARS s), the filter shader over what shows between them (dance_filter.gdshader), and over that the frame's own drawing (`Ui`: floating hearts and sparkles, a LIVE badge with a climbing
## view counter, a blinking REC, a column of heart / comment / share buttons, the name, a caption and a few comments, viewfinder corners, the shutter flash). Shapes and the show's font only.
const Filter := preload("res://modes/show/items_ui/dance_filter.gdshader")

const BARS := 0.25 ## s the bars take to close and to open
const DARK := Color(0.03, 0.03, 0.05, 0.97)

var fx: Dictionary = {} ## the effect (age, dur, id): the manager advances it
var who := "" ## the victim's name, upper case
var _filter: ColorRect
var _ui: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_filter = ColorRect.new()
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = Filter
	_filter.material = material
	add_child(_filter)
	_ui = Ui.new()
	(_ui as Ui).frame = self
	add_child(_ui)

## Every frame: where the bars and the filter are, then a redraw.
func refresh() -> void:
	if fx.is_empty(): return
	var view := get_viewport_rect().size
	var closed := _closed()
	var gap := (view.x - Ui.frame_rect(view).size.x) * 0.5 * closed
	_filter.position = Vector2(gap, 0.0)
	_filter.size = Vector2(view.x - gap * 2.0, view.y)
	var material := _filter.material as ShaderMaterial
	material.set_shader_parameter("amount", closed)
	material.set_shader_parameter("clock", float(fx.age))
	queue_redraw()
	_ui.queue_redraw()

func _closed() -> float:
	return Ui.ease_out(Ui.shut(float(fx.age), float(fx.dur)))

func _draw() -> void:
	if fx.is_empty(): return
	var view := get_viewport_rect().size
	var gap := (view.x - Ui.frame_rect(view).size.x) * 0.5 * _closed()
	if gap <= 0.0: return
	draw_rect(Rect2(0.0, 0.0, gap, view.y), DARK)
	draw_rect(Rect2(view.x - gap, 0.0, gap, view.y), DARK)

class Ui extends Control:
	const ShowTheme := preload("res://client/show_theme.gd")
	const PINK := Color("ff4f86")
	const LIVE_RED := Color("ff2d55")
	const COMMENTS := ["NO WAY", "AGAIN!!", "THE MOVES", "10 OUT OF 10", "PLAY IT BACK", "KEEP GOING"]
	const AVATARS := [Color("ff8fb8"), Color("8fd3ff"), Color("ffd36b"), Color("b79bff")]
	var frame ## the Frame this draws for (its fx and who)
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	## The vertical 9:16 frame of a screen: 9/16 of the height wide (the whole width on a screen already narrower), centred.
	static func frame_rect(view: Vector2) -> Rect2:
		var wide := minf(view.x, view.y * 9.0 / 16.0)
		return Rect2((view.x - wide) * 0.5, 0.0, wide, view.y)
	## 0..1: how far the bars are in (closing over BARS s, opening again over the last BARS s of the effect).
	static func shut(age: float, dur: float) -> float:
		return clampf(minf(age / 0.25, (dur - age) / 0.25), 0.0, 1.0)
	static func ease_out(x: float) -> float:
		return 1.0 - pow(1.0 - x, 3.0)
	static func hash01(index: int, salt: float) -> float:
		return fposmod(sin(float(index) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)
	static func counted(count: int) -> String:
		if count < 1000: return str(count)
		return "%.1fK" % (float(count) / 1000.0) if count < 1000000 else "%.1fM" % (float(count) / 1000000.0)
	static func heart(c: Vector2, size: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for step in 30:
			var a := TAU * float(step) / 30.0
			points.append(c + Vector2(16.0 * pow(sin(a), 3.0), -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))) * (size / 17.0))
		return points
	static func star(c: Vector2, size: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for step in 8:
			var a := TAU * float(step) / 8.0 - PI * 0.5
			points.append(c + Vector2(cos(a), sin(a)) * size * (1.0 if step % 2 == 0 else 0.24))
		return points
	func _text(words: String, at: Vector2, size: float, fill: Color, edge := Color(0, 0, 0, 0), edge_px := 0.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
		ShowTheme.text(self, words, at, size, fill, edge, edge_px, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, 0.0, 1.0, align)
	func _draw() -> void:
		var fx: Dictionary = frame.fx
		if fx.is_empty(): return
		var view := get_viewport_rect().size
		var age := float(fx.age)
		var dur := float(fx.dur)
		var closed := ease_out(shut(age, dur))
		if closed <= 0.0: return
		var f := frame_rect(view)
		var u := view.y / 720.0
		var a := clampf((closed - 0.35) / 0.65, 0.0, 1.0)
		var seed := int(fx.id)
		var left := f.position.x
		var right := f.end.x
		var spent := clampf(age / dur, 0.0, 1.0)
		var white := Color(1, 1, 1, a)
		var shade := Color(0, 0, 0, 0.6 * a)
		# hearts rise from the button column, sparkles twinkle all over
		for index in 14:
			var rate := 0.28 + 0.3 * hash01(index, 1.0 + float(seed))
			var phase := fposmod(age * rate + hash01(index, 2.0), 1.0)
			var x := right - (28.0 + 62.0 * hash01(index, 3.0)) * u + sin(phase * 7.0 + float(index)) * 14.0 * u
			var y := f.end.y - 250.0 * u - phase * view.y * 0.55
			var fade := pow(sin(phase * PI), 0.7) * a
			var tone: Color = [PINK, Color("ff6b6b"), Color("ffb347"), Color.WHITE, Color("ff7bc0")][index % 5]
			var points := heart(Vector2(x, y), (8.0 + 9.0 * hash01(index, 4.0)) * u)
			draw_colored_polygon(points, Color(tone, 0.92 * fade))
			points.append(points[0])
			draw_polyline(points, Color(1, 1, 1, 0.7 * fade), 1.5 * u, true)
		for index in 16:
			var glint := pow(maxf(sin(age * (2.0 + 3.0 * hash01(index, 5.0)) + hash01(index, 6.0) * TAU), 0.0), 6.0) * a
			if glint <= 0.02: continue
			var at := Vector2(left + (0.08 + 0.84 * hash01(index, 7.0)) * f.size.x, (0.1 + 0.7 * hash01(index, 8.0)) * view.y)
			draw_colored_polygon(star(at, (7.0 + 10.0 * hash01(index, 9.0)) * u * (0.6 + 0.4 * glint)), Color(1.0, 0.97, 0.85, glint))
		# the viewfinder: corner brackets
		var inset := 12.0 * u
		var arm := 30.0 * u
		for corner in 4:
			var cx := left + inset if corner % 2 == 0 else right - inset
			var cy := inset if corner < 2 else view.y - inset
			var sx := 1.0 if corner % 2 == 0 else -1.0
			var sy := 1.0 if corner < 2 else -1.0
			draw_polyline(PackedVector2Array([Vector2(cx, cy + sy * arm), Vector2(cx, cy), Vector2(cx + sx * arm, cy)]), Color(1, 1, 1, 0.85 * a), 3.5 * u, true)
		# LIVE badge and the view counter, top left
		var top := 66.0 * u # under the round's pill, which stays over the bars
		var badge := Rect2(left + 22.0 * u, top, 78.0 * u, 30.0 * u)
		ShowTheme.box(self, badge, Color(LIVE_RED, a), Color(1, 1, 1, 0.9 * a), 1.5 * u, 6.0 * u)
		_text("LIVE", badge.get_center(), 20.0 * u, white)
		var eyes := Rect2(badge.end.x + 6.0 * u, top, 86.0 * u, 30.0 * u)
		ShowTheme.box(self, eyes, Color(0, 0, 0, 0.5 * a), Color(0, 0, 0, 0), 0.0, 6.0 * u)
		var eye := Vector2(eyes.position.x + 15.0 * u, eyes.get_center().y)
		draw_colored_polygon(PackedVector2Array([eye + Vector2(-9, 0) * u, eye + Vector2(0, -6) * u, eye + Vector2(9, 0) * u, eye + Vector2(0, 6) * u]), white)
		draw_circle(eye, 3.4 * u, Color(0.1, 0.1, 0.14, a))
		_text(counted(int(lerpf(140.0, 61000.0, pow(spent, 1.7)))), Vector2(eye.x + 14.0 * u, eye.y), 17.0 * u, white, Color(0, 0, 0, 0), 0.0, HORIZONTAL_ALIGNMENT_LEFT)
		# REC, top right, blinking
		var rec := Vector2(right - 80.0 * u, top + 15.0 * u)
		if fposmod(age, 0.8) < 0.5:
			draw_circle(rec, 11.0 * u, Color(1.0, 0.15, 0.2, 0.3 * a))
			draw_circle(rec, 7.5 * u, Color(1.0, 0.15, 0.2, a))
		else:
			draw_circle(rec, 6.0 * u, Color(0.5, 0.1, 0.13, a))
		_text("REC", rec + Vector2(14.0 * u, 0.0), 18.0 * u, white, shade, 3.0 * u, HORIZONTAL_ALIGNMENT_LEFT)
		# the button column on the right edge
		var column := right - 40.0 * u
		var base := view.y * 0.5
		var heart_at := Vector2(column, base)
		var points := heart(heart_at, 19.0 * u * (1.0 + 0.3 * exp(-fposmod(age, 0.7) * 7.0)))
		draw_colored_polygon(points, Color(1.0, 0.24, 0.38, a))
		points.append(points[0])
		draw_polyline(points, white, 2.2 * u, true)
		_text(counted(int(300.0 + 21000.0 * pow(spent, 1.3))), heart_at + Vector2(0.0, 36.0 * u), 15.0 * u, white, shade, 3.0 * u)
		var bubble_at := Vector2(column, base + 88.0 * u)
		ShowTheme.box(self, Rect2(bubble_at - Vector2(19, 16) * u, Vector2(38, 30) * u), white, Color(0, 0, 0, 0), 0.0, 10.0 * u)
		draw_colored_polygon(PackedVector2Array([bubble_at + Vector2(-8, 12) * u, bubble_at + Vector2(-12, 22) * u, bubble_at + Vector2(2, 12) * u]), white)
		for dot in 3: draw_circle(bubble_at + Vector2(float(dot - 1) * 9.0, -1.0) * u, 2.6 * u, Color(0.15, 0.15, 0.2, a))
		_text(counted(int(40.0 + 900.0 * pow(spent, 1.1))), bubble_at + Vector2(0.0, 40.0 * u), 15.0 * u, white, shade, 3.0 * u)
		var share_at := Vector2(column, base + 176.0 * u)
		draw_colored_polygon(PackedVector2Array([share_at + Vector2(20, -2) * u, share_at + Vector2(-2, -18) * u, share_at + Vector2(-2, -9) * u, share_at + Vector2(-20, -9) * u, share_at + Vector2(-20, 14) * u, share_at + Vector2(-2, 14) * u, share_at + Vector2(-2, 20) * u, share_at + Vector2(20, 4) * u]), white)
		_text("SHARE", share_at + Vector2(0.0, 40.0 * u), 13.0 * u, white, shade, 3.0 * u)
		var disc := Vector2(column, base + 266.0 * u)
		draw_circle(disc, 22.0 * u, Color(0.06, 0.06, 0.09, a))
		draw_circle(disc, 10.0 * u, Color(PINK, a))
		draw_circle(disc, 3.0 * u, Color(0.06, 0.06, 0.09, a))
		draw_arc(disc, 16.0 * u, age * 3.0, age * 3.0 + 1.3, 12, Color(1, 1, 1, 0.55 * a), 2.0 * u, true)
		# the name and the caption, bottom left, and the comments above them
		var text_left := left + 22.0 * u
		_text("@" + str(frame.who), Vector2(text_left, view.y - 86.0 * u), 26.0 * u, white, Color(0, 0, 0, 0.7 * a), 4.0 * u, HORIZONTAL_ALIGNMENT_LEFT)
		_text("NEW DANCE, NOT BY CHOICE", Vector2(text_left, view.y - 52.0 * u), 16.0 * u, Color(1, 1, 1, 0.92 * a), Color(0, 0, 0, 0.7 * a), 3.0 * u, HORIZONTAL_ALIGNMENT_LEFT)
		var shown := clampi(int((age - 0.6) / 0.5) + 1, 0, 3)
		for row in shown:
			var arrive := clampf((age - 0.6 - 0.5 * float(row)) / 0.25, 0.0, 1.0)
			var words: String = COMMENTS[(seed + row * 2) % COMMENTS.size()]
			var y := view.y - 140.0 * u - float(shown - 1 - row) * 40.0 * u
			var pill := Rect2(text_left - 4.0 * u - (1.0 - ease_out(arrive)) * 24.0 * u, y - 15.0 * u, ShowTheme.width(words, 16.0 * u) + 56.0 * u, 30.0 * u)
			ShowTheme.box(self, pill, Color(0, 0, 0, 0.45 * a * arrive), Color(0, 0, 0, 0), 0.0, 15.0 * u)
			draw_circle(Vector2(pill.position.x + 15.0 * u, y), 10.0 * u, Color(AVATARS[(seed + row) % AVATARS.size()], a * arrive))
			_text(words, Vector2(pill.position.x + 34.0 * u, y), 16.0 * u, Color(1, 1, 1, a * arrive), Color(0, 0, 0, 0), 0.0, HORIZONTAL_ALIGNMENT_LEFT)
		# the shutter: a white flash over everything as the bars come in
		var flash := clampf(1.0 - age / 0.22, 0.0, 1.0)
		if flash > 0.0: draw_rect(Rect2(Vector2.ZERO, view), Color(1, 1, 1, 0.75 * flash * flash))
