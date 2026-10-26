extends RefCounted
## The drawn pieces of the results page (client/online_screens.gd) in the candy menu look (menu_kit.gd, show_theme.gd): the head (the team's title on a cyan chip, the headline in big white outlined italic type
## over the podium, the line under it on a chip, the clear time of a show for one, the play-again countdown), the page's corner stripes, and a result row (a leaning violet slab with the rank medal, the round head of the
## cast character, the name on the player's colour, the cast title, the points counting up). Everything is drawn in the page's design space (1280 x 720) into its own Control; the page keeps the real Labels and Buttons.
const Ui := preload("res://client/friends_ui.gd")
const Kit := preload("res://style/menu_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const ShowHudKit := preload("res://style/show_hud_kit.gd")
const MenuPortraits := preload("res://client/menu_portraits.gd")

const DESIGN := Vector2(1280, 720)
const HEAD_CAP := 56.0 ## px, the capitals of a short headline
const HEAD_MAX := 880.0 ## the headline's widest, px (longer ones shrink)
const HEAD_Y := 128.0
const LINE_Y := 190.0 ## the line chip under the headline
## The headline's lettering by kind: fill, outline, extrusion. Wins are orange and gold (the podium's colours), a time's up is red, the rest the kit's violet and pink.
const HEAD_LOOKS := {
	"champion": {"edge": Color("e8590c"), "deep": Color("7c2d0a")},
	"victory": {"edge": Color("e8590c"), "deep": Color("7c2d0a")},
	"timesup": {"edge": Color("d3203f"), "deep": Color("6e0c2a")},
	"title": {"edge": Color("2a1062"), "deep": Color("f23a96")},
}

## The tri-colour corner stripes behind the page (full screen, over the 3D podium): they slide in from the corner.
class Corner extends Control:
	var age := 0.0

	func _init() -> void:
		name = "Corner"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func restart() -> void:
		age = 0.0

	func _process(delta: float) -> void:
		age += minf(delta, 0.05)
		if is_visible_in_tree(): queue_redraw()

	func _draw() -> void:
		var unit := size.y * 0.075
		var slide := 1.0 - Ui.out_expo(clampf(age / 0.5, 0.0, 1.0))
		draw_set_transform(Vector2(-unit * 3.0, -unit * 3.0) * slide, 0.0, Vector2.ONE)
		Kit.corner_ribbons(self, Rect2(Vector2.ZERO, size), unit)
		draw_set_transform_matrix(Transform2D.IDENTITY)

## The head of the page: nothing here takes the mouse.
class ResultsHead extends Control:
	var team := "" ## the team's title, a chip beside the corner stripes
	var kind := "victory" ## the headline's lettering (HEAD_LOOKS)
	var words := "" ## the headline
	var line := "" ## the line under it, on a chip
	var info := "" ## a chip under the headline (the level times, the personal best)
	var info_y := 226.0
	var big_time := "" ## a show for one: its time as a big slab
	var time_rect := Rect2(40, 232, 500, 96)
	var choose := "" ## "Play again within 12 s"
	var choose_at := Vector2(40.0, 702.0) ## left end, middle
	var age := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS
		size = DESIGN

	func restart() -> void:
		age = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		age += minf(delta, 0.05)
		if is_visible_in_tree(): queue_redraw()

	## A chip whose left end sits at `left`, centred on `mid`, `high` px tall.
	func _chip_at(text: String, left: float, mid: float, alpha: float, high := 32.0) -> void:
		Kit.chip_words(self, text, left + ShowTheme.pill_width(text, high), mid, high, alpha)

	func _draw() -> void:
		if team != "":
			var drop := 1.0 - Ui.out_back(clampf(age / 0.4, 0.0, 1.0))
			_chip_at(team, 160.0, 34.0 - 30.0 * drop, clampf(age / 0.2, 0.0, 1.0)) # the team's title beside the corner stripes (the champion's crown rises high in the middle)
		if words != "":
			_draw_headline()
		if info != "":
			var fade := clampf((age - 0.5) / 0.3, 0.0, 1.0)
			var wide := minf(ShowTheme.pill_width(info, 30.0), 1000.0)
			Kit.chip_words(self, info, 640.0 + wide * 0.5, info_y + 12.0 * (1.0 - fade), 30.0, fade, 0.0)
		if big_time != "": _draw_time(clampf((age - 0.3) / 0.4, 0.0, 1.0))
		if choose != "": _chip_at(choose, choose_at.x, choose_at.y, 1.0, 30.0)

	## The headline: big white slanted type with a thick outline and an extrusion in the kind's colours, popping in and bobbing; a crown over a champion; the line on a chip under it.
	func _draw_headline() -> void:
		var look: Dictionary = HEAD_LOOKS.get(kind, HEAD_LOOKS["title"])
		var pop := ShowTheme.pop_scale(age - 0.08, 0.5, 0.3)
		var size_px := ShowTheme.size_for_cap(HEAD_CAP)
		var text := words.to_upper()
		var wide := ShowTheme.width(text, size_px) * (1.0 + ShowTheme.SLANT * 0.1)
		if wide > HEAD_MAX: size_px *= HEAD_MAX / wide
		var bob := sin(age * 1.6) * 0.012
		var centre := Vector2(640.0, HEAD_Y)
		ShowTheme.text(self, text, centre + Vector2(0.0, size_px * 0.1), size_px, Color(0, 0, 0, 0), Color(0.16, 0.04, 0.3, 0.38), size_px * 0.24, Color(0, 0, 0, 0), 0.0, pop, -0.03 + bob, ShowTheme.SLANT)
		ShowTheme.text(self, text, centre, size_px, Color.WHITE, look.edge, size_px * 0.2, look.deep, size_px * 0.1, pop, -0.03 + bob, ShowTheme.SLANT)
		if kind == "champion":
			var rise := Ui.out_back(clampf((age - 0.25) / 0.45, 0.0, 1.0))
			ShowTheme.crown(self, Vector2(640.0, HEAD_Y - size_px * 0.5 - 4.0 * (1.0 - rise)), 96.0 * rise, ShowTheme.YELLOW, Color("7c2d0a"), clampf(rise, 0.0, 1.0), 0.12)
		if line != "":
			var fade := clampf((age - 0.35) / 0.3, 0.0, 1.0)
			var high := 34.0
			var chip_wide := minf(ShowTheme.pill_width(line, high), 960.0)
			Kit.chip_words(self, line, 640.0 + chip_wide * 0.5, LINE_Y + 10.0 * (1.0 - fade), high, fade, chip_wide)

	## The clear time: a violet slab with big outlined slanted digits and a plain stopwatch glyph at its end.
	func _draw_time(grow: float) -> void:
		var pop := ShowTheme.pop_scale(grow * 0.4, 0.4, 0.5)
		var rect := time_rect
		var centre := rect.get_center()
		var scaled := Rect2(centre - rect.size * 0.5 * pop, rect.size * pop)
		Kit.slab(self, scaled, Kit.VIOLET, Color.WHITE, maxf(scaled.size.y * 0.045, 2.0), 0.1, -1.0, grow)
		var h := scaled.size.y
		var glyph_r := h * 0.3
		var glyph := Vector2(scaled.end.x - h * 0.55, centre.y) ## the plain stopwatch at the right end
		var digits_end := glyph.x - glyph_r * 1.2 ## the digits are centred between the left end and the glyph
		var size := ShowTheme.size_for_cap(h * 0.42)
		var wide := ShowTheme.width(big_time, size) * (1.0 + ShowTheme.SLANT * 0.1)
		var room := digits_end - scaled.position.x - 48.0 * pop
		if wide > room: size *= room / wide
		ShowTheme.text(self, big_time, Vector2((scaled.position.x + digits_end) * 0.5, centre.y), size, Color.WHITE, Kit.EDGE, maxf(size * 0.2, 3.0), Kit.role("primary").lip, size * 0.06, 1.0, 0.0, ShowTheme.SLANT, grow)
		ShowTheme.stopwatch(self, glyph, glyph_r, Kit.YELLOW, grow)

## One row of the results table: a leaning violet slab with a white rim.
class ResultRow extends Control:
	const COUNT_LENGTH := 0.9 ## s the points take to count up
	const COUNT_LAG := 0.18 ## s between a row coming in and its points starting
	const SHEAR := 0.1 ## the slab's lean
	var seat := 0
	var rank := 0 ## 1-based, 0 = a page without ranks (a delivery, a level run)
	var points := 0
	var show_points := false
	var who := ""
	var title := ""
	var color := Color.WHITE
	var me := false
	var choice := "pending"
	var winner := false ## the first of a ranked page: gold outline and a crown
	var home := Vector2.ZERO ## rest position (the page sets it, the row slides in to it)
	var delay := 0.0 ## s after the page came up that the row comes in
	var age := 0.0
	var _from := 0
	var _start := 0.0 ## age the count-up starts at
	var _landed := -1.0 ## age the number reached its value
	var _shown := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	## The page just came up (or a row is new): slide in after `wait` s and count up.
	func restart(wait: float) -> void:
		delay = wait
		age = 0.0
		_from = 0
		_start = wait + COUNT_LAG
		_landed = -1.0
		_shown = 0.0
		modulate.a = 0.0
		position = home + Vector2(-90.0, 0.0)

	## The points changed while the page is up: count on from what is shown.
	func set_points(value: int) -> void:
		if value == points: return
		_from = roundi(_shown)
		points = value
		_start = age
		_landed = -1.0

	## The row at rest (no motion: the page was already up).
	func settle() -> void:
		age = 100.0
		_start = 0.0
		_landed = 0.0
		_shown = float(points)
		position = home
		modulate.a = 1.0

	func shown_points() -> int:
		return roundi(_shown)

	func _process(delta: float) -> void:
		if not is_visible_in_tree(): return
		age += minf(delta, 0.05)
		var enter := clampf((age - delay) / 0.4, 0.0, 1.0)
		position = home + Vector2(-90.0 * (1.0 - Ui.out_expo(enter)), 0.0)
		modulate.a = minf(enter * 3.0, 1.0) * (0.5 if choice == "gone" else 1.0)
		var count := clampf((age - _start) / COUNT_LENGTH, 0.0, 1.0)
		_shown = lerpf(float(_from), float(points), 1.0 - pow(1.0 - count, 3.0))
		if count >= 1.0 and _landed < 0.0: _landed = age
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var w := size.x
		if h < 4.0 or w < 4.0: return
		var mid := h * 0.5
		var gold := winner and rank == 1
		if gold: Kit.slab(self, Rect2(-4.0, -4.0, w + 8.0, h + 8.0), Color(ShowTheme.YELLOW, 0.25 + 0.15 * sin(age * 3.0)), Color(0, 0, 0, 0), 0.0, SHEAR, -1.0)
		Kit.slab(self, Rect2(0.0, 0.0, w, h), Kit.VIOLET, ShowTheme.YELLOW if gold else Color.WHITE, h * 0.07 if gold else maxf(h * 0.045, 2.0), SHEAR)
		var x := h * 0.62
		if rank > 0:
			Kit.rank_badge(self, Vector2(x, mid), h * 0.34, rank)
			if gold: ShowTheme.crown(self, Vector2(x - h * 0.06, mid - h * 0.26), h * 0.36, ShowTheme.CREAM, ShowTheme.ORANGE, 1.0, -0.35)
			x = h * 1.52
		var head := Vector2(x, mid)
		var r := h * 0.38
		draw_circle(head, r + h * 0.05, color, true, -1.0, true)
		draw_circle(head, r, color.darkened(0.5), true, -1.0, true)
		var picture := MenuPortraits.texture(seat)
		if picture != null:
			var points_ring := PackedVector2Array()
			var uvs := PackedVector2Array()
			for index in 40:
				var turn := Vector2.from_angle(TAU * float(index) / 40.0)
				points_ring.append(head + turn * r * 0.96)
				uvs.append(Vector2(0.5, 0.5) + turn * 0.5 * 0.96)
			draw_colored_polygon(points_ring, Color.WHITE, uvs, picture)
		else:
			ShowTheme.text(self, who.substr(0, 1).to_upper(), head, r * 1.2, Color.WHITE, Kit.EDGE, r * 0.2, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT)
		if choice == "again":
			var at := head + Vector2(r * 0.78, r * 0.78)
			draw_circle(at, h * 0.16, Kit.EDGE, true, -1.0, true)
			draw_circle(at, h * 0.13, Color("33d986"), true, -1.0, true)
			draw_polyline(PackedVector2Array([at + Vector2(-0.07, 0.0) * h, at + Vector2(-0.02, 0.05) * h, at + Vector2(0.07, -0.05) * h]), Kit.EDGE, h * 0.045, true)
		elif choice == "menu" or choice == "gone":
			ShowHudKit.cross_badge(self, head + Vector2(r * 0.78, r * 0.78), h * 0.15)
		var name_x := x + r + h * 0.16
		var count_text := str(shown_points()) if show_points else ""
		var points_size := h * 0.56
		var points_w := (ShowTheme.width(str(maxi(points, 0)), points_size) * (1.0 + ShowTheme.SLANT * 0.1) + h * 0.9) if show_points else h * 0.3
		var room := w - name_x - points_w
		var tall := h * (0.5 if title != "" else 0.62)
		var fs := tall * 0.66
		var tw := ShowTheme.width(who, fs) * (1.0 + ShowTheme.SLANT * 0.1)
		if tw + tall * 0.8 > room: fs *= maxf(room - tall * 0.8, 8.0) / tw
		tw = ShowTheme.width(who, fs) * (1.0 + ShowTheme.SLANT * 0.1)
		var top := h * 0.11 if title != "" else (h - tall) * 0.5
		var capsule := Rect2(name_x, top, tw + tall * 0.8, tall)
		ShowTheme.box(self, capsule, color, Color(Kit.MINT, 1.0) if me else Color(1, 1, 1, 0.55), 2.6 if me else 1.4)
		var ink := ShowHudKit.INK if color.get_luminance() > 0.55 else Color.WHITE
		var edge := Color(0, 0, 0, 0) if ink != Color.WHITE else Color(Kit.EDGE, 0.9)
		ShowTheme.text(self, who, Vector2(capsule.position.x + tall * 0.4, capsule.get_center().y), fs, ink, edge, fs * 0.16, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
		if title != "":
			var ts := h * 0.22
			var tl := ShowTheme.width(title, ts) * (1.0 + ShowTheme.SLANT * 0.1)
			if tl > room: ts *= room / tl
			ShowTheme.text(self, title, Vector2(name_x + tall * 0.3, h * 0.8), ts, Kit.MUTED_ON_DARK, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
		if show_points:
			var pop := 1.0
			if _landed >= 0.0: pop += 0.4 * sin(PI * clampf((age - _landed) / 0.35, 0.0, 1.0))
			ShowTheme.text(self, count_text, Vector2(w - h * 0.5, mid), points_size, ShowTheme.YELLOW if rank != 1 else Color.WHITE, Kit.EDGE, points_size * 0.2, Kit.role("primary").lip, points_size * 0.06, pop, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_RIGHT)
