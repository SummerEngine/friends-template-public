extends Control
## Online flow screens, in the candy menu look (style/menu_kit.gd, docs/comic-ui.md "Menu kit"): the loading / error / notice pages (a rings page in its own tone, big outlined lettering, cyan chips, a chunky progress
## bar), the lobby HUD (the players' colours on the HUD's pills) and the results page (the 3D stage with the podium behind a ribbon banner and a table of rows).
## One full-rect overlay owned by the client. It never blocks the mouse except over its own buttons and over the opaque pages (loading, error, notice, results). The lobby is a transparent
## HUD over the live yard with no buttons: players pick a course by walking onto its pad (docs/walk-in-lobby.md), so the HUD shows only one status line (partner / countdown) and the player chips.
## Every Button carries meta `bot_id`; `press()` emits the same `pressed` signal a mouse click does.
signal cancel_pressed
signal back_pressed
signal play_again_pressed
signal main_menu_pressed

const Ui := preload("res://client/friends_ui.gd")
const Kit := preload("res://style/menu_kit.gd")
const Lettering := preload("res://client/menu_skin.gd")
const HudComic := preload("res://client/hud_comic.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const ShowHudKit := preload("res://style/show_hud_kit.gd")
const Parts := preload("res://client/results_parts.gd")
const MenuPortraits := preload("res://client/menu_portraits.gd")
const LevelRun := preload("res://levels/level_run.gd")
const TeamCast := preload("res://style/team_cast.gd")
const LevelBests := preload("res://client/level_bests.gd")
const CastVideo := preload("res://client/cast_video.gd")
const MenuBackdrop := preload("res://client/menu_backdrop.gd")
const DESIGN := Vector2(1280, 720)
const STATUS_DESIGN := Vector2(960, 540)
const STATUS_FOOT := 516.0 ## bottom edge of the loading page's action row: 24 design px above the page edge
const DEFAULT_STEPS := ["Search", "Match", "Server", "Connect", "Level", "Lobby"]
const STALL_TITLE_SEC := 20.0
const STALL_PROGRESS_SEC := 8.0
const STALL_HINT := "Still working... this can take a while"

var _current := ""
var _buttons: Dictionary = {}
var _paper: Control ## the rings page behind the loading / error / notice pages
var _paper_title: Control ## the 3D stage behind the results: built when they show and gone when they leave (a stage renders every frame, shown or not)
var _corner: Parts.Corner ## the results' tri-colour corner stripes, over the stage
var _stage: Control
# status (loading / error)
var _status: Control
var _status_kind := ""
var _status_over: Label ## the page's words live in these (invisible) Labels; StatusGraphic draws them
var _kicker := "TWO PLAYERS" ## small line above the title of the loading page
var _status_title: Label
var _status_detail: Label
var _status_elapsed: Label
var _status_caption: Label
var _status_percent: Label
var _status_hint: Label
var _status_graphic: StatusGraphic
var _clock_pill: ClockPill
var _seq_start_ms := 0
var _seq_active := false
var _title_raw := ""
var _title_since_ms := 0
var _progress_target := -1.0
var _progress_shown := 0.0
var _progress_changed_ms := 0
var _caption_override := ""
var _steps := PackedStringArray(DEFAULT_STEPS)
var _default_steps := true
var _ticker: StatusTicker
var _intro_tweens: Array[Tween] = []
var _status_rest: Dictionary = {}
var _status_error_page := false
var _foot_tweens: Dictionary = {} ## Button -> its intro Tween
var _step := 0
var _error_elapsed := -1.0
var _gap := {"frames": 0, "max": 0.0, "sum": 0.0, "over50": 0, "over100": 0} ## frame times while the loading page shows
var _gap_last_ms := 0 ## wall time of the last page tick (the final frame of a long block is never ticked)
var _cancel_button: Button
var minigame := true ## the loading page's ComicHop (class at the end of this file); false = a bare loading page
var _load_game: Control
var _back_button: Button
# lobby
var _lobby: Control
var _timer_pill: PanelContainer
var _timer_label: Label
var _list_panel: HFlowContainer ## the lobby's player chips: one line, two with many players
var _member_rows: Array[Dictionary] = []
# results
var _results: Control
var _head: Parts.ResultsHead ## the drawn head: the team's title, the banner, the lines under it, the clear time, the play-again countdown
var _results_headline: Label ## the headline's words (an invisible Label; the banner draws them)
var _results_title: Label ## the team's title (TeamCast.title()) over the headline, when the cast has one
var _results_sub: Label
var _results_levels: Label ## a level run: the times of the levels cleared
var _credit: Button ## the team's one credit line (TeamCast.credit_link), a watermark on the results
var _credit_invite: Label ## "Make one for your team", the watermark's second line
var _credit_box: VBoxContainer
var _credit_layer: Control ## full screen, holds the watermark in the corner
var _best_line := "" ## a level run: this device's personal best for the results page
var _table_rows: Control
var _result_rows: Array = [] ## Parts.ResultRow, best first on a ranked page
var _ranking_key := ""
var _again_button: Button
var _menu_button: Button
var _choose_label: Label
var _results_round := -1
var _again_sent := false
# ------------------------------------------------------------------ drawing helpers

## The loading / error / notice page's art, drawn in STATUS_DESIGN over the rings page: the kicker chip, the title in big lettering (a badge before it on the error and notice pages, a spinner after
## it on the loading page), the detail on a violet card and, on the loading page, the caption and percent chips, the chunky progress bar and the step badges. The page's words live in the
## (invisible) Labels it is given; `clock` (the bar's motion) comes from the page's ticker, `age` (the intro) from this control.
class StatusGraphic extends Control:
	const BAR := Rect2(64, 358, 840, 28) ## the track
	const STEP_Y := 410.0
	const MIN_FILL := 28.0
	const STRIPE_PERIOD := 22.0
	const STRIPE_WIDTH := 9.0
	const TONES := {
		"loading": {"fill": Color("ffffff"), "edge": Kit.EDGE, "deep": Color("1a8fe3"), "accent": Kit.CHIP},
		"error": {"fill": Color("ffffff"), "edge": Color("6e0c2a"), "deep": Color("c4183c"), "accent": Color("e5365a")},
		"notice": {"fill": Color("ffffff"), "edge": Kit.EDGE, "deep": Color("f23a96"), "accent": Color("27b872")},
	}
	var clock := 0.0
	var steps := PackedStringArray()
	var step := 0
	var progress := -1.0
	var tone := "loading"
	var page := false ## error / notice: the badge and the detail, no progress
	var over: Label
	var heading: Label
	var body: Label
	var note: Label ## the progress caption
	var percent: Label
	var hint: Label ## the stall line (shown while visible)
	var age := 0.0
	var _card := Kit.panel("sheet", 22, 0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = STATUS_DESIGN

	func restart() -> void:
		age = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		age += minf(delta, 0.05)
		if is_visible_in_tree(): queue_redraw()

	## 0..1: how far a piece that came in `delay` s after the intro is.
	func _in(delay: float, length := 0.45) -> float:
		return clampf((age - delay) / length, 0.0, 1.0)

	func _draw() -> void:
		var look: Dictionary = TONES.get(tone, TONES["loading"])
		var accent: Color = look.accent
		var kick := _in(0.0)
		if over != null and over.text != "": _pill(over.text, 64.0 - 40.0 * (1.0 - Ui.out_expo(kick)), 96.0, 38.0, kick, accent)
		if hint != null and hint.visible and hint.text != "":
			var wide := ShowTheme.pill_width(hint.text, 38.0)
			_pill(hint.text, 904.0 - wide, 96.0, 38.0, 1.0, TONES["error"].accent)
		_title(look)
		_card_of(look)
		if not page: _progress(look)

	func _title(look: Dictionary) -> void:
		var shown := _in(0.05, 0.55)
		var words := heading.text if heading != null else ""
		var left := 64.0 + (106.0 if page else 0.0)
		var room := 840.0 - (106.0 if page else 76.0)
		var size_px := 76.0
		var wide := ShowTheme.width(words, size_px) * (1.0 + ShowTheme.SLANT * 0.1)
		if wide > room: size_px *= room / maxf(wide, 1.0)
		var fill: Color = look.fill
		var edge: Color = look.edge
		var deep: Color = look.deep
		if words != "":
			ShowTheme.text(self, words, Vector2(left - 50.0 * (1.0 - Ui.out_expo(shown)), 160.0), size_px, fill, edge, maxf(size_px * 0.14, 4.0), deep, size_px * 0.07, 1.0, 0.0, ShowTheme.SLANT, shown, HORIZONTAL_ALIGNMENT_LEFT)
		if page:
			var pop := ShowTheme.pop_scale(age - 0.1, 0.45, 0.2)
			var centre := Vector2(104.0, 160.0)
			var bad := tone == "error"
			ShowTheme.badge(self, centre, Vector2(48.0, 48.0), Color("ff4c5f") if bad else Color("33d986"), Color("ffffff"), Color("6e0c2a") if bad else Color("0b5c36"), 1.0, pop, -0.12, 18, 0.84)
			if pop > 0.3:
				if bad:
					ShowTheme.text(self, "!", centre + Vector2(0.0, 2.0), 66.0 * pop, Color.WHITE, Color("6e0c2a"), 6.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT)
				else:
					var tick := PackedVector2Array([centre + Vector2(-17.0, 2.0) * pop, centre + Vector2(-6.0, 13.0) * pop, centre + Vector2(18.0, -13.0) * pop])
					draw_polyline(tick, Color("0b5c36"), 14.0 * pop, true)
					draw_polyline(tick, Color.WHITE, 8.0 * pop, true)
		else:
			var spin := Vector2(878.0, 160.0)
			var turn := fposmod(clock * 1.4, 1.0) * TAU
			draw_arc(spin, 22.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5 * shown), 8.0, true) # the track
			draw_arc(spin, 22.0, turn, turn + TAU * 0.3, 24, Color(Kit.primary_color(), shown), 8.0, true)

	func _card_of(_look: Dictionary) -> void:
		if body == null or body.text == "": return
		var shown := _in(0.12, 0.5)
		var size_px := 24.0
		var pitch := 31.0
		var lines := ShowHudKit.wrapped(body.text, size_px, 840.0 - 56.0)
		var count := mini(lines.size(), 5 if page else 2)
		var widest := 0.0
		for index in count: widest = maxf(widest, ShowTheme.width(lines[index], size_px) * (1.0 + ShowTheme.SLANT * 0.1))
		var rect := Rect2(64.0, 206.0 + 16.0 * (1.0 - Ui.out_expo(shown)), clampf(widest + 56.0, 300.0, 840.0), float(count) * pitch + 30.0)
		_card.bg_color.a = shown
		_card.border_color.a = shown
		_card.shadow_color.a = 0.42 * shown
		draw_style_box(_card, rect)
		for index in count:
			ShowTheme.text(self, lines[index], Vector2(rect.position.x + 28.0, rect.position.y + 15.0 + pitch * (float(index) + 0.5)), size_px, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, shown, HORIZONTAL_ALIGNMENT_LEFT)

	## The loading page's lower half: caption and percent pills, the bar, the step badges.
	func _progress(look: Dictionary) -> void:
		var shown := _in(0.2, 0.5)
		if note != null and note.visible and note.text != "": _pill(note.text, 64.0, 336.0, 32.0, shown, look.accent)
		if percent != null and percent.visible and percent.text != "": Kit.chip_words(self, percent.text, 904.0, 336.0, 36.0, shown)
		ShowTheme.box(self, BAR.grow(5.0), Color(1, 1, 1, shown))
		ShowTheme.box(self, BAR, Color(Kit.VIOLET_DEEP, shown))
		var inner := BAR.grow(-4.0)
		if progress < 0.0:
			var seg := inner.size.x * 0.26
			var t := fposmod(clock * 0.5, 2.0)
			var u := t if t < 1.0 else 2.0 - t
			_fill(inner, smoothstep(0.0, 1.0, u) * (inner.size.x - seg), seg, shown)
		else:
			# Never empty: at 0 % the first stretch already sits on the track, and it still reaches the end at 100 %.
			_fill(inner, 0.0, MIN_FILL + (inner.size.x - MIN_FILL) * clampf(progress, 0.0, 1.0), shown)
		_markers(shown)

	## The bar's fill: the primary with a lighter top, a shine and moving diagonal stripes (so a long step still reads as alive), a white knob at its head.
	func _fill(inner: Rect2, x0: float, width: float, alpha: float) -> void:
		var area := Rect2(inner.position.x + x0, inner.position.y, width, inner.size.y)
		var height := area.size.y
		var plate: Dictionary = Kit.role("primary")
		ShowTheme.box(self, area, Color(plate.lip, alpha), Color(0, 0, 0, 0), 0.0, height * 0.5)
		ShowTheme.box(self, Rect2(area.position, Vector2(area.size.x, height * 0.74)), Color(plate.face, alpha), Color(0, 0, 0, 0), 0.0, height * 0.5)
		var x := area.position.x - height - STRIPE_PERIOD + fposmod(clock * 28.0, STRIPE_PERIOD)
		var inside := Rect2(area.position.x + height * 0.5, area.position.y, maxf(area.size.x - height, 0.0), height)
		while x < area.end.x:
			var stripe := PackedVector2Array([Vector2(x, area.end.y), Vector2(x + STRIPE_WIDTH, area.end.y), Vector2(x + STRIPE_WIDTH + height, area.position.y), Vector2(x + height, area.position.y)])
			if x >= inside.position.x and x + STRIPE_WIDTH + height <= inside.end.x:
				draw_colored_polygon(stripe, Color(1, 1, 1, 0.2 * alpha))
			else:
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(stripe, Ui.rect_points(inside)):
					if piece.size() >= 3 and absf(_area(piece)) > 1.0: draw_colored_polygon(piece, Color(1, 1, 1, 0.2 * alpha))
			x += STRIPE_PERIOD
		ShowTheme.box(self, Rect2(area.position + Vector2(height * 0.4, height * 0.1), Vector2(maxf(area.size.x - height * 0.8, 0.0), height * 0.2)), Color(1, 1, 1, 0.5 * alpha), Color(0, 0, 0, 0), 0.0, height * 0.1)
		var knob := Vector2(area.end.x - height * 0.5, area.position.y + height * 0.5)
		draw_circle(knob, height * 0.66, Color(Kit.EDGE, alpha), true, -1.0, true)
		draw_circle(knob, height * 0.52, Color(1, 1, 1, alpha), true, -1.0, true)
		draw_circle(knob + Vector2(-height * 0.12, -height * 0.14), height * 0.18, Color(1, 1, 1, 0.55 * alpha), true, -1.0, true)

	static func _area(points: PackedVector2Array) -> float:
		var sum := 0.0
		for index in points.size(): sum += points[index].cross(points[(index + 1) % points.size()])
		return sum * 0.5

	## The steps as round badges on a thin line under the bar: done (green, a check), the current one (the primary, pulsing), the next ones (violet).
	func _markers(alpha: float) -> void:
		var count := steps.size()
		if count < 2: return
		var x0 := BAR.position.x + 12.0
		var x1 := BAR.end.x - 12.0
		var r := 10.0
		var current := clampi(step, 0, count - 1)
		draw_line(Vector2(x0, STEP_Y), Vector2(x1, STEP_Y), Color(1, 1, 1, 0.6 * alpha), 5.0, true)
		draw_line(Vector2(x0, STEP_Y), Vector2(lerpf(x0, x1, float(current) / float(count - 1)), STEP_Y), Color(Color("33d986"), alpha), 5.0, true)
		for index in count:
			var c := Vector2(lerpf(x0, x1, float(index) / float(count - 1)), STEP_Y)
			if index < current:
				draw_circle(c, r + 2.0, Color(Kit.EDGE, alpha), true, -1.0, true)
				draw_circle(c, r, Color(Color("33d986"), alpha), true, -1.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-4.5, 0.5), c + Vector2(-1.2, 3.8), c + Vector2(5.0, -3.5)]), Color(Kit.EDGE, alpha), 2.6, true)
			elif index == current:
				var pulse := 1.0 + 0.14 * sin(clock * 5.0)
				draw_circle(c, r * 1.9 * pulse, Color(Kit.primary_color(), 0.3 * alpha), true, -1.0, true)
				draw_circle(c, r * pulse + 2.0, Color(Kit.EDGE, alpha), true, -1.0, true)
				draw_circle(c, r * pulse, Color(Kit.primary_color(), alpha), true, -1.0, true)
				draw_circle(c + Vector2(-2.0, -2.5), r * 0.3, Color(1, 1, 1, 0.6 * alpha), true, -1.0, true)
			else:
				draw_circle(c, r + 2.0, Color(1, 1, 1, alpha), true, -1.0, true)
				draw_circle(c, r, Color(Kit.VIOLET_DEEP, alpha), true, -1.0, true)

	## A chip in the page's tone (`accent`) with slanted white words centred in it, from `left`, centred on `mid`.
	func _pill(words: String, left: float, mid: float, height: float, alpha: float, accent: Color) -> void:
		Kit.chip_words(self, words, left + ShowTheme.pill_width(words, height), mid, height, alpha, 0.0, accent)

## The elapsed clock: a cyan chip in the screen's corner.
class ClockPill extends Control:
	var words := "":
		set(value):
			if value == words: return
			words = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if words == "" or size.y < 8.0: return
		var height := size.y
		Kit.chip_words(self, words, ShowTheme.pill_width(words, height), height * 0.5, height)

## Calls back every frame while enabled; lives under a node that ignores pause.
class StatusTicker extends Node:
	var callback: Callable
	func _process(delta: float) -> void:
		if callback.is_valid(): callback.call(delta)

## Drawn check or dash (the fonts have no check glyph): a mint disc with a check when this player stands on a pad, a thin ring with a dash when not.
class ReadyMark extends Control:
	var compact := false ## only the check / dash, no READY word
	var is_ready := false:
		set(value):
			is_ready = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(108, 30)

	func _draw() -> void:
		var c := Vector2(15, size.y * 0.5)
		if is_ready:
			draw_circle(c, 13.0, Kit.EDGE, true, -1, true)
			draw_circle(c, 11.0, Color("33d986"), true, -1, true)
			var check := PackedVector2Array([c + Vector2(-5.5, 0.5), c + Vector2(-1.5, 4.5), c + Vector2(6, -4.5)])
			draw_polyline(check, Kit.EDGE, 3.0, true)
			if compact: return
			ShowTheme.text(self, "READY", Vector2(34, size.y * 0.5), 18.0, Color.WHITE, Kit.EDGE, 3.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
		else:
			draw_arc(c, 11.0, 0.0, TAU, 28, Color(Kit.MUTED_ON_DARK, 0.85), 2.4, true)
			draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), Color(Kit.MUTED_ON_DARK, 0.85), 2.8, true)

# ------------------------------------------------------------------ setup

func _init() -> void:
	name = "OnlineScreens"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Kit.theme()
	_paper = _backdrop("loading", "Paper")
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = DESIGN
	add_child(_stage)
	_build_status()
	_build_lobby()
	_build_results()
	for screen: Control in [_status, _lobby, _results]: screen.visible = false
	resized.connect(_layout)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout()

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0: return
	_place_credit()
	var factor := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (size - DESIGN * factor) * 0.5
	var status_factor := minf(size.x / STATUS_DESIGN.x, size.y / STATUS_DESIGN.y)
	_status.scale = Vector2.ONE * status_factor
	_status.position = (size - STATUS_DESIGN * status_factor) * 0.5
	var unit := HudComic.unit_of(self) if is_inside_tree() else size.y / 720.0
	_status_elapsed.position = Vector2(34.0, 26.0) * unit
	_status_elapsed.size = Vector2(560.0, 50.0) * unit
	_clock_pill.position = Vector2(34.0, 26.0) * unit
	_clock_pill.size = Vector2(560.0, 40.0) * unit

func _screen_root(screen_name: String) -> Control:
	var root := Control.new()
	root.name = screen_name
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = DESIGN
	_stage.add_child(root)
	return root

func _place(parent: Control, control: Control, rect: Rect2) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size

## One full-rect backdrop node; `kind` is MenuBackdrop's art ("loading": the sky page, "results": the 3D stage with the podium). Hidden until its page shows.
func _backdrop(kind: String, node_name: String) -> Control:
	var backdrop := MenuBackdrop.new(kind)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.name = node_name
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.visible = false
	add_child(backdrop)
	return backdrop

## A Label that only holds words (a probe or the page's drawing reads its text): nothing of its own is drawn.
func _holder(value := "") -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key: String in ["font_color", "font_outline_color", "font_shadow_color"]: label.add_theme_color_override(key, Color(0, 0, 0, 0))
	return label

## Buttons register under their bot id; everything else lets the mouse through.
func _register(button: Button, bot_id: String) -> void:
	button.set_meta("bot_id", bot_id)
	_buttons[bot_id] = button

func _ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control and not (child is Button): (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)

## The player's colour as a round dot with a light ring.
func _chip_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(1, 1, 1, 0.9)
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.anti_aliasing = true
	return box

func _chip(color: Color) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(26, 26)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", _chip_style(color))
	return chip

func _ceil_seconds(value: float) -> int:
	return maxi(ceili(value), 0)

# ------------------------------------------------------------------ queries and bot hooks

func find_button(bot_id: String) -> Button:
	var button: Button = _buttons.get(bot_id)
	if button == null or not is_instance_valid(button): return null
	if button.disabled or not button.is_visible_in_tree(): return null
	return button

## Same code path as a mouse click: the button's own `pressed` signal.
func press(bot_id: String) -> bool:
	var button := find_button(bot_id)
	if button == null: return false
	button.pressed.emit()
	return true

func is_open() -> bool:
	return _current != ""

func current() -> String:
	return _current

func _set_current(kind: String) -> void:
	_current = kind
	if kind != "loading":
		_seq_active = false
		_title_raw = ""
		_progress_target = -1.0
		_caption_override = ""
		_step = 0
	if kind != "loading": _report_frame_gaps("left loading")
	if _ticker != null: _ticker.set_process(kind in ["loading", "error"])
	if kind == "loading": _start_load_game()
	else: _stop_load_game()
	_paper.visible = kind in ["loading", "error", "notice"]
	(_paper as MenuBackdrop).tone = {"loading": "sea", "error": "grape"}.get(kind, "sun")
	if kind == "results": _show_stage()
	else: _drop_stage()
	_status.visible = kind in ["loading", "error", "notice"]
	_status_elapsed.visible = _status.visible
	_clock_pill.visible = _status.visible
	_lobby.visible = kind == "lobby"
	_results.visible = kind == "results"
	_credit_layer.visible = kind == "results"
	if kind in ["loading", "error", "notice", "results"] and is_inside_tree(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## The results' stage is built when they show and freed when they leave: a 3D stage renders every frame, shown or not.
func _show_stage() -> void:
	if _paper_title != null and is_instance_valid(_paper_title):
		_paper_title.visible = true
		return
	_ranking_key = ""
	_paper_title = _backdrop("results", "PaperTitle")
	_paper_title.visible = true
	move_child(_paper_title, _paper.get_index() + 1)
	_corner = Parts.Corner.new()
	add_child(_corner)
	move_child(_corner, _paper_title.get_index() + 1)

func _drop_stage() -> void:
	if _paper_title == null or not is_instance_valid(_paper_title): return
	remove_child(_paper_title)
	_paper_title.queue_free()
	_paper_title = null
	if _corner != null and is_instance_valid(_corner):
		remove_child(_corner)
		_corner.queue_free()
	_corner = null
	_ranking_key = ""

func hide_all() -> void:
	_set_current("")

func hide_lobby() -> void:
	if _current == "lobby": _set_current("")

func hide_results() -> void:
	if _current == "results": _set_current("")

# ------------------------------------------------------------------ loading and error
# The page has its own design space (STATUS_DESIGN) and scale, so type stays
# readable in a small window: at 800x450 body text is ~23 px and the title ~57 px.

func _build_status() -> void:
	_status = Control.new()
	_status.name = "Status"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.size = STATUS_DESIGN
	add_child(_status)
	_status_graphic = StatusGraphic.new()
	_status_graphic.name = "Art"
	_status.add_child(_status_graphic)
	_status_over = _holder("Play online")
	_status_over.name = "Kicker"
	_status.add_child(_status_over)
	# The clock sits at the screen corner where the in-game clock will be, so it is parented to the page root and
	# placed in _layout with the HUD's pixel unit instead of the page's design scale.
	_status_elapsed = _holder("")
	_status_elapsed.name = "Elapsed"
	_status_elapsed.visible = false
	add_child(_status_elapsed)
	_clock_pill = ClockPill.new()
	_clock_pill.name = "ElapsedPill"
	_clock_pill.visible = false
	add_child(_clock_pill)
	_status_title = _holder("")
	_status_title.name = "Title"
	_status.add_child(_status_title)
	_status_detail = _holder("")
	_status_detail.name = "Detail"
	_status.add_child(_status_detail)
	_status_caption = _holder("")
	_status_caption.name = "Caption"
	_status.add_child(_status_caption)
	_status_percent = _holder("")
	_status_percent.name = "Percent"
	_status.add_child(_status_percent)
	_status_hint = _holder(STALL_HINT)
	_status_hint.name = "Hint"
	_status_hint.visible = false
	_status.add_child(_status_hint)
	_status_graphic.over = _status_over
	_status_graphic.heading = _status_title
	_status_graphic.body = _status_detail
	_status_graphic.note = _status_caption
	_status_graphic.percent = _status_percent
	_status_graphic.hint = _status_hint
	_cancel_button = _status_button("Cancel", false)
	_cancel_button.pressed.connect(func() -> void: cancel_pressed.emit())
	_cancel_button.focus_mode = Control.FOCUS_NONE ## Space / Enter / pad A must never cancel the search: Esc / pad B and a tap do
	_place(_status, _cancel_button, Rect2(64, STATUS_FOOT - 54, 240, 54))
	_register(_cancel_button, "loading_cancel")
	_back_button = _status_button("Back", true)
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	_place(_status, _back_button, Rect2(64, STATUS_FOOT - 54, 240, 54))
	_register(_back_button, "error_back")
	_ignore_mouse(_status)
	# Touch fit (touch_controls.gd) grows buttons to a thumb height after they are
	# placed; re-seat the row by its bottom edge whenever a button's height changes.
	for button: Button in [_cancel_button, _back_button]: button.resized.connect(_seat_status_foot)
	_seat_status_foot()
	# Runs even while the tree is paused, so the page never looks frozen.
	_status.process_mode = Node.PROCESS_MODE_ALWAYS
	_ticker = StatusTicker.new()
	_ticker.name = "Ticker"
	_ticker.callback = _tick_status
	_status.add_child(_ticker)

## A chunky plate (the gold primary or the dark pill) with the kit's lettering on it.
func _status_button(text: String, primary: bool) -> Button:
	var button := Kit.button(text, primary, true)
	button.custom_minimum_size.y = 54
	Lettering.comicify(button, 0.56, HORIZONTAL_ALIGNMENT_CENTER)
	return button

func _now_ms() -> int:
	return Time.get_ticks_msec()

func _show_status(kind: String, title: String, detail: String) -> void:
	var fresh := _status_kind != kind or _current != kind
	_status_kind = kind
	_status_title.text = title.to_upper()
	_status_detail.text = detail
	if fresh:
		var failed := kind == "error"
		var page := kind != "loading" ## error or notice: text plus BACK, no progress
		_status_over.text = "SOMETHING WENT WRONG" if failed else _kicker
		_status_graphic.tone = kind
		_status_graphic.page = page
		_status_caption.visible = not page
		_status_percent.visible = not page
		_status_hint.visible = false
		if kind == "notice": _set_elapsed("")
		_back_button.visible = page
		_status_error_page = page
		_seat_status_foot()
		_set_current(kind)
		_status_intro()
		if page: _focus_button.call_deferred(_back_button)
		else: _release_focus.call_deferred()
		_tick_status(0.0)

## `progress` < 0 shows a moving indeterminate bar; 0..1 a determinate bar with
## percent text. A repeated call with the same title and no progress keeps the
## determinate bar fed by update_loading_progress(). `step` is the 0-based
## index into the step list; -1 infers it from the title (default steps) or
## keeps the current one.
func show_loading(title: String, detail: String, cancelable := true, progress := -1.0, step := -1) -> void:
	var now := _now_ms()
	if not _seq_active:
		_seq_active = true
		_seq_start_ms = now
	var changed_title := title != _title_raw
	if changed_title:
		_title_raw = title
		_title_since_ms = now
		_caption_override = ""
	if progress >= 0.0: _set_progress(progress, now)
	elif changed_title or _current != "loading": _progress_target = -1.0
	if step >= 0: _step = clampi(step, 0, _steps.size() - 1)
	elif _default_steps: _step = _infer_step(title, _step)
	_show_status("loading", title, detail)
	_cancel_button.visible = cancelable
	_tick_status(0.0)

## Offline modes reuse the loading page: set before show_loading ("LOCAL CO-OP", "SINGLEPLAYER").
func set_loading_kicker(text: String) -> void:
	_kicker = text.to_upper()

## Replaces the step list (e.g. PackedStringArray(["Search", "Match", ...])); empty restores the defaults.
func set_loading_steps(labels: PackedStringArray) -> void:
	_default_steps = labels.is_empty()
	_steps = PackedStringArray(DEFAULT_STEPS) if _default_steps else labels.duplicate()
	_step = clampi(_step, 0, _steps.size() - 1)
	_status_graphic.steps = _steps
	_status_graphic.queue_redraw()

## Determinate progress 0..1 with an optional caption ("Loading level geometry"); a negative fraction shows the
## moving indeterminate bar under the caption.
func update_loading_progress(fraction: float, label := "") -> void:
	if fraction < 0.0: _progress_target = -1.0
	else: _set_progress(fraction, _now_ms())
	_caption_override = label
	if fraction >= 0.999: _report_frame_gaps("progress 100%")

func _exit_tree() -> void:
	_report_frame_gaps("page removed")

## One line per loading sequence: the longest frame while the level built (the spinner stands still that long).
func _report_frame_gaps(why: String) -> void:
	if int(_gap.frames) == 0: return
	var tail := float(_now_ms() - _gap_last_ms) / 1000.0
	if tail > float(_gap.max): _gap.max = tail
	if tail > 0.1: _gap.over100 += 1
	_gap_last_ms = 0
	print("GW_LOAD_FRAMES ", why, " frames=", _gap.frames, " max_ms=", snappedf(float(_gap.max) * 1000.0, 0.1), " mean_ms=", snappedf(float(_gap.sum) * 1000.0 / int(_gap.frames), 0.1), " over50=", _gap.over50, " over100=", _gap.over100)
	_gap = {"frames": 0, "max": 0.0, "sum": 0.0, "over50": 0, "over100": 0}

func _set_progress(fraction: float, now: int) -> void:
	var value := clampf(fraction, 0.0, 1.0)
	if _progress_target < 0.0:
		_progress_shown = 0.0
		_progress_changed_ms = now
	elif absf(value - _progress_target) > 0.0005:
		_progress_changed_ms = now
	_progress_target = value

func _infer_step(title: String, fallback: int) -> int:
	var text := title.to_lower()
	for entry: Array in [["lobby", 5], ["joining", 5], ["level", 4], ["connect", 3], ["server", 2], ["start", 2], ["match", 1], ["found", 1], ["search", 0]]:
		if text.contains(String(entry[0])): return mini(int(entry[1]), _steps.size() - 1)
	return fallback

func show_error(title: String, detail: String) -> void:
	if _seq_active: _error_elapsed = float(_now_ms() - _seq_start_ms) / 1000.0
	elif _current != "error": _error_elapsed = -1.0
	_cancel_button.visible = false
	_show_status("error", title, detail)

## An ordinary stop that is not a failure (e.g. "you left"): the error page's layout and BACK,
## with a plain overline and no red headline or FAILED AFTER clock.
func show_notice(overline: String, title: String, detail: String) -> void:
	_cancel_button.visible = false
	_show_status("notice", title, detail)
	_status_over.text = overline.to_upper()

## Seconds the current loading sequence has been running (-1 outside one).
func loading_elapsed() -> float:
	return float(_now_ms() - _seq_start_ms) / 1000.0 if _seq_active else -1.0

func _clock_text(seconds: float) -> String:
	var whole := maxi(int(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]

func _tick_status(delta: float) -> void:
	var graphic := _status_graphic
	var now := _now_ms()
	graphic.clock += minf(delta, 0.1)
	if _current == "loading" and delta > 0.0:
		# Wall time between ticks: the engine clamps `delta` after a long block, so it hides the freeze.
		var wall := float(now - _gap_last_ms) / 1000.0 if _gap_last_ms > 0 else delta
		_gap_last_ms = now
		_gap.frames += 1
		_gap.sum += wall
		_gap.max = maxf(float(_gap.max), wall)
		if wall > 0.05: _gap.over50 += 1
		if wall > 0.1:
			_gap.over100 += 1
			print("GW_LOAD_GAP ms=", roundi(wall * 1000.0), " at '", _caption_override, "' ", snappedf(_progress_target, 0.001))
	if _current == "error":
		_set_elapsed("FAILED AFTER %s" % _clock_text(_error_elapsed) if _error_elapsed >= 0.0 else "")
		return
	if _current != "loading": return
	_set_elapsed("ELAPSED %s" % _clock_text(loading_elapsed()))
	var determinate := _progress_target >= 0.0
	if determinate:
		_progress_shown = clampf(_progress_shown + (_progress_target - _progress_shown) * (1.0 - exp(-7.0 * delta)), 0.0, 1.0)
	var stalled := float(now - _progress_changed_ms) / 1000.0 > STALL_PROGRESS_SEC if determinate else float(now - _title_since_ms) / 1000.0 > STALL_TITLE_SEC
	_status_hint.visible = stalled
	graphic.steps = _steps
	graphic.step = _step
	graphic.progress = _progress_shown if determinate else -1.0
	_status_percent.text = "%d%%" % roundi(_progress_shown * 100.0) if determinate else ""
	_status_caption.text = _caption_override

## The clock's words: the Label holds them, the dark pill in the corner draws them.
func _set_elapsed(words: String) -> void:
	_status_elapsed.text = words
	_clock_pill.words = words

func _status_intro() -> void:
	if not is_inside_tree(): return
	var running: Array = _foot_tweens.values()
	running.append_array(_intro_tweens)
	for tween: Tween in running:
		if tween != null and tween.is_valid(): tween.kill()
	_intro_tweens.clear()
	_foot_tweens.clear()
	# Back to rest first: a page replaced mid-intro must not take the shifted position as home.
	var rest: Dictionary = _status_rest
	for control: Control in rest:
		control.position = rest[control]
	_status_graphic.restart() # the kicker, the title and the card come in by themselves
	for button: Button in [_cancel_button, _back_button]: _foot_tweens[button] = Ui.enter(button, 0.2, Vector2(0, 16), 0.4)

## The loading page's action row sits on STATUS_FOOT by its bottom edge, so a button
## grown for touch rises instead of running off the page. The error page's Back sits
## under the five-line detail (top 426; even a 76-high Back ends at 502).
func _seat_status_foot() -> void:
	var tall := maxf(_cancel_button.size.y, 54.0)
	_status_rest[_cancel_button] = Vector2(64, STATUS_FOOT - tall)
	_status_rest[_back_button] = Vector2(64, 426.0 if _status_error_page else STATUS_FOOT - maxf(_back_button.size.y, 54.0))
	for button: Button in [_cancel_button, _back_button]:
		button.position = _status_rest[button]
		var running: Tween = _foot_tweens.get(button)
		if running != null and running.is_valid() and running.is_running():
			# The intro tween would carry the button back to its old home: restart it toward the new one.
			running.kill()
			_foot_tweens[button] = Ui.enter(button, 0.0, Vector2(0, 16), 0.3)

func _focus_button(button: Button) -> void:
	if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled: button.grab_focus()

## The loading page has nothing to confirm: whatever held focus (the menu button that started the search) lets go.
func _release_focus() -> void:
	if not is_inside_tree(): return
	var holder := get_viewport().gui_get_focus_owner()
	if holder != null: holder.release_focus()

func _start_load_game() -> void:
	if not minigame or _load_game != null: return
	_load_game = ComicHop.new()
	_status.add_child(_load_game)

func _stop_load_game() -> void:
	if _load_game == null: return
	_status.remove_child(_load_game) ## out of the tree at once: no input or frame after the page left loading
	_load_game.queue_free()
	_load_game = null

# ------------------------------------------------------------------ lobby

## The lobby HUD: one status line (partner / countdown) and the player chips, nothing to press.
## The course choice lives in the world: the pads in client/walk_in_markers.gd.
func _build_lobby() -> void:
	_lobby = _screen_root("Lobby")
	var top := VBoxContainer.new()
	top.name = "Top"
	top.add_theme_constant_override("separation", 10)
	_place(_lobby, top, Rect2(0, 26, DESIGN.x, 120))
	_timer_pill = PanelContainer.new()
	_timer_pill.name = "Status"
	_timer_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pill_look := Kit.hud_pill_box(30, 2)
	pill_look.content_margin_left = 22
	pill_look.content_margin_right = 22
	pill_look.content_margin_top = 4
	pill_look.content_margin_bottom = 4
	_timer_pill.add_theme_stylebox_override("panel", pill_look)
	_timer_label = Kit.label("", 30, Kit.ON_DARK)
	_timer_label.custom_minimum_size = Vector2(480, 52)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_pill.add_child(_timer_label)
	Lettering.comicify(_timer_label, 0.62)
	top.add_child(_timer_pill)
	_list_panel = HFlowContainer.new()
	_list_panel.name = "Members"
	_list_panel.alignment = FlowContainer.ALIGNMENT_CENTER
	_list_panel.add_theme_constant_override("h_separation", 14)
	_list_panel.add_theme_constant_override("v_separation", 8)
	top.add_child(_list_panel)
	_ignore_mouse(_lobby)

func show_lobby(model: Dictionary) -> void:
	var fresh := _current != "lobby"
	_set_current("lobby")
	_apply_lobby(model)
	if fresh and is_inside_tree(): _lobby_intro()

func update_lobby(model: Dictionary) -> void:
	if _current != "lobby": _set_current("lobby")
	_apply_lobby(model)

func _lobby_intro() -> void:
	Ui.enter(_lobby.find_child("Top", false, false), 0.0, Vector2(0, -30), 0.5)

## The text of the lobby status line ("" hides it): the countdown, else the model's hint.
func lobby_status() -> String:
	return _timer_label.text if _timer_pill.visible else ""

## One line on top: the countdown ("Adventure in 3"), else who we wait for. No rules text.
func _apply_lobby(model: Dictionary) -> void:
	var members: Array = model.get("members", []).duplicate()
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	_sync_member_rows(members)
	var start_in := float(model.get("start_in", -1.0))
	if start_in >= 0.0:
		_timer_label.text = "%s in %d" % [str(model.get("pick_title", "")).capitalize(), _ceil_seconds(start_in)]
	else:
		_timer_label.text = str(model.get("hint", ""))
	_timer_pill.visible = _timer_label.text != ""

func _sync_member_rows(members: Array) -> void:
	while _member_rows.size() > members.size():
		var old: Dictionary = _member_rows.pop_back()
		_list_panel.remove_child(old.panel)
		(old.panel as Control).queue_free()
	while _member_rows.size() < members.size():
		var row := _make_member_row()
		_list_panel.add_child(row.panel)
		_ignore_mouse(row.panel)
		(row.panel as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_member_rows.append(row)
		if is_inside_tree(): Ui.enter(row.panel, 0.0, Vector2.ZERO, 0.35)
	for index in members.size():
		var member: Dictionary = members[index]
		var row: Dictionary = _member_rows[index]
		var mine := bool(member.get("me", false))
		(row.chip as Panel).add_theme_stylebox_override("panel", _chip_style(member.get("color", Kit.MUTED_ON_DARK)))
		(row.name as Label).text = "You" if mine else str(member.get("name", "Partner"))
		(row.mark as ReadyMark).is_ready = bool(member.get("on_pad", false))

## A name chip: the HUD's dark pill with the player's colour as a ring dot, the name ("You" for this player) and the on-a-pad mark.
func _make_member_row() -> Dictionary:
	var panel := PanelContainer.new()
	var plate := Kit.hud_pill_box(22, 2)
	plate.content_margin_left = 10
	plate.content_margin_right = 14
	plate.content_margin_top = 5
	plate.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", plate)
	panel.custom_minimum_size.y = 44
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	panel.add_child(line)
	var chip := _chip(Kit.MUTED_ON_DARK)
	line.add_child(chip)
	var label := Kit.label("", 28, Kit.ON_DARK)
	label.custom_minimum_size.y = 40
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	Lettering.comicify(label, 0.6, HORIZONTAL_ALIGNMENT_LEFT)
	var mark := ReadyMark.new()
	mark.custom_minimum_size = Vector2(34, 30)
	mark.compact = true
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(mark)
	return {"panel": panel, "chip": chip, "name": label, "mark": mark}

# ------------------------------------------------------------------ results
# The 3D stage with the podium behind (the table sits on its left, or on both sides from five players), the headline as a ribbon banner, a table of pills, two chunky buttons.
# Everything is laid out in DESIGN (1280 x 720) and drawn by client/results_parts.gd; the page keeps the real Labels and Buttons.

const RESULT_TOP := 226.0 ## where the table starts (lower under a pill line or the clear time)
const RESULT_BOTTOM := 594.0
const RESULT_BUTTONS_Y := 606.0
const RESULT_BUTTON_H := 76.0
const RESULT_COLUMN := 500.0 ## the table's width in one column (up to 4 players), RESULT_PAIR each in two
const RESULT_PAIR := 370.0
const RESULT_ONE_COLUMN := 4
const RESULT_STAGE_SHIFT := 0.42 ## the stage's picture sits right of the middle while the table is on the left
const RESULT_STAGE_NEAR := 1.24 ## the camera's distance factor with one table column (the winners big), ...
const RESULT_STAGE_FAR := 1.8 ## ... and with a table on both sides (the middle is narrow)

func _build_results() -> void:
	_results = _screen_root("Results")
	_head = Parts.ResultsHead.new()
	_head.name = "Head"
	_results.add_child(_head)
	var title_words := TeamCast.title() if TeamCast.has_title() else ""
	_head.team = title_words
	_results_title = _holder(title_words)
	_results_title.name = "TeamTitle"
	_results_title.visible = TeamCast.has_title()
	_results.add_child(_results_title)
	_results_headline = _holder("")
	_results_headline.name = "Headline"
	_results.add_child(_results_headline)
	_results_sub = _holder("")
	_results_sub.name = "Sub"
	_results.add_child(_results_sub)
	_results_levels = _holder("")
	_results_levels.name = "Levels"
	_results.add_child(_results_levels)
	_choose_label = _holder("")
	_choose_label.name = "Choose"
	_results.add_child(_choose_label)
	_table_rows = Control.new()
	_table_rows.name = "Players"
	_table_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_rows.size = DESIGN
	_results.add_child(_table_rows)
	_again_button = Kit.button("Play again", true)
	_again_button.pressed.connect(_on_again_pressed)
	_place(_results, _again_button, Rect2(40, RESULT_BUTTONS_Y, 290, RESULT_BUTTON_H))
	_register(_again_button, "results_again")
	_menu_button = Kit.button("Main menu", false)
	_menu_button.pressed.connect(func() -> void: main_menu_pressed.emit())
	_place(_results, _menu_button, Rect2(346, RESULT_BUTTONS_Y, 220, RESULT_BUTTON_H))
	_register(_menu_button, "results_menu")
	_ignore_mouse(_results)
	_letter_results()
	_build_credit()

## The one line a team may put in its game (docs/slots.md, team.credit_link): "Made by the <team> team" with its link, and "Make one for your team". Only here, on the results; nothing else in the game links
## anywhere. It is a watermark: small, light, half see-through white type with a faint outline in the bottom right corner of the screen, no frame and no hover box (the words brighten and the cursor turns to a hand
## over it). A click opens the team's link; nothing opens by itself.
func _build_credit() -> void:
	var link := TeamCast.credit_link()
	_credit_layer = Control.new()
	_credit_layer.name = "CreditLayer"
	_credit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credit_layer.visible = false
	add_child(_credit_layer)
	_credit_box = VBoxContainer.new()
	_credit_box.name = "CreditBox"
	_credit_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credit_box.add_theme_constant_override("separation", 0)
	_credit_layer.add_child(_credit_box)
	_credit_invite = Kit.label("Make one for your team", 14, Color(1, 1, 1, WATERMARK_ALPHA))
	_credit_invite.name = "CreditInvite"
	_credit_invite.visible = link != ""
	_credit_invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credit_box.add_child(_credit_invite)
	_credit = Button.new()
	_credit.name = "Credit"
	_credit.flat = true
	_credit.focus_mode = Control.FOCUS_NONE
	_credit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_credit.text = "Made by the %s team  ·  %s" % [TeamCast.team_name(), link.trim_prefix("https://").trim_suffix("/")]
	_credit.visible = link != ""
	_credit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credit.add_theme_font_override("font", Kit.font())
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		_credit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for key: String in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_credit.add_theme_color_override(key, Color(1, 1, 1, WATERMARK_ALPHA))
	_credit.add_theme_color_override("font_hover_color", Color(1, 1, 1, WATERMARK_HOVER_ALPHA))
	_credit.add_theme_color_override("font_outline_color", Color(Kit.EDGE, 0.3))
	_credit.add_theme_constant_override("outline_size", 3)
	_credit.pressed.connect(func() -> void: OS.shell_open(link))
	_credit_box.add_child(_credit)
	_place_credit()

const WATERMARK_ALPHA := 0.45 ## the watermark's white, of full
const WATERMARK_HOVER_ALPHA := 0.8

## The watermark sits in the screen's bottom right corner at a size that follows the screen's height.
func _place_credit() -> void:
	if _credit_box == null or size.y <= 0.0: return
	var unit := clampf(size.y / 720.0, 0.75, 2.4)
	_credit.add_theme_font_size_override("font_size", roundi(15.0 * unit))
	_credit_invite.add_theme_font_size_override("font_size", roundi(13.0 * unit))
	_credit_box.size = Vector2.ZERO
	var wide := _credit_box.get_combined_minimum_size()
	_credit_box.size = wide
	_credit_box.position = size - wide - Vector2(18.0, 14.0) * unit

## The two buttons of the results page in the kit's lettering (the gold PLAY AGAIN, the dark MAIN MENU), one cap height between them.
func _letter_results() -> void:
	Lettering.set_scope(_results)
	Lettering.comicify(_again_button, 0.55, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true, &"buttons")
	Lettering.comicify(_menu_button, 0.55, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true, &"buttons")

func _on_again_pressed() -> void:
	if _again_sent: return
	_again_sent = true
	_refresh_again_button()
	play_again_pressed.emit()

func _refresh_again_button() -> void:
	_again_button.disabled = _again_sent
	_again_button.text = "Waiting for partner..." if _again_sent else "Play again"

func show_results(model: Dictionary) -> void:
	var fresh := _current != "results"
	_set_current("results")
	# A new results screen is a new choice, even when a new world restarts round numbers at 1:
	# the server's row still re-marks a choice it already holds.
	if fresh: _again_sent = false
	_apply_results(model, fresh)
	if fresh and is_inside_tree(): _results_intro()
	# The team's win video (demo/cast/video/win.ogv) over the results of a delivered run.
	if fresh and (model.get("rows", []) as Array).any(func(row: Variant) -> bool: return row is Dictionary and bool(row.get("arrived", false))):
		CastVideo.play(self, "win", false)

func update_results(model: Dictionary) -> void:
	if _current != "results": _set_current("results")
	_apply_results(model)

## Everything pops in: the head (headline, chips), the rows last rank first (each row's points count up as it lands), the buttons and the credit watermark.
func _results_intro() -> void:
	_head.restart()
	var count := _result_rows.size()
	for index in count: (_result_rows[index] as Parts.ResultRow).restart(0.5 + 0.16 * float(count - 1 - index))
	Ui.enter(_again_button, 0.45, Vector2(0, 20), 0.4)
	Ui.enter(_menu_button, 0.5, Vector2(0, 20), 0.4)
	if _corner != null: _corner.restart()
	if _credit.visible:
		_credit_box.modulate.a = 0.0
		Ui.tween(_credit_box).tween_property(_credit_box, "modulate:a", 1.0, 0.6).set_delay(0.9)
	_focus_button.call_deferred(_again_button)

static func time_text(seconds: float) -> String:
	if seconds < 0.0: return "--"
	var whole_minutes := int(seconds / 60.0)
	return "%02d:%04.1f" % [whole_minutes, seconds - whole_minutes * 60.0]

## The pair delivered or not; one shared time and pane; who wants another go. A scored round (rows with a rank) names its order and points in the table.
func _apply_results(model: Dictionary, fresh := false) -> void:
	if fresh and not (model.get("run", {}) as Dictionary).is_empty(): _best_line = str(LevelBests.record(model.run).get("line", ""))
	var round_number := int(model.get("round", 0))
	if round_number != _results_round:
		_results_round = round_number
		_again_sent = false
	var rows: Array = model.get("rows", [])
	var run: Dictionary = model.get("run", {})
	var ranked := false
	var arrived := false
	var time := -1.0
	var breaks := 0
	var intact := true
	for row_model: Dictionary in rows:
		if bool(row_model.get("me", false)) and str(row_model.get("choice", "pending")) == "again": _again_sent = true
		arrived = arrived or bool(row_model.get("arrived", false))
		time = maxf(time, float(row_model.get("time", -1.0)))
		breaks += int(row_model.get("breaks", 0))
		ranked = ranked or int(row_model.get("rank", 0)) > 0
		if int(row_model.get("panes_intact", 1)) == 0: intact = false
	ranked = ranked and run.is_empty() # a level run is not ranked
	if ranked: arrived = false # a scored round has its own headline: no delivered word
	_refresh_again_button()
	var headline := ""
	var line := ""
	var kind := "title"
	var info := ""
	if not run.is_empty():
		# A level run (levels/level_run.gd): the authority names the run; this device adds its personal best.
		var revealed := bool(run.get("finished", false)) and TeamCast.reveal() != ""
		headline = TeamCast.reveal() if revealed else str(model.get("headline", "RUN ENDED")).to_upper()
		line = (str(model.get("headline", "")).to_upper() + "  ·  " if revealed else "") + str(model.get("sub", ""))
		var times: Array = run.get("times", [])
		var shown := times.slice(maxi(times.size() - 8, 0))
		var parts := PackedStringArray()
		for seconds: float in shown: parts.append(LevelRun.format_time(seconds))
		_results_levels.text = ("LEVELS  " + ("... · " if times.size() > shown.size() else "") + " · ".join(parts)) if not parts.is_empty() else ""
		info = _results_levels.text + ("  ·  " + _best_line if _best_line != "" and _results_levels.text != "" else _best_line)
		kind = "champion" if bool(run.get("finished", false)) else "title"
	else:
		_best_line = ""
		_results_levels.text = ""
		var delivered := TeamCast.reveal() if TeamCast.reveal() != "" else TeamCast.word("delivered")
		headline = delivered if arrived else str(model.get("headline", "ROUND ENDED")).to_upper()
		if arrived:
			var pane := "pane intact" if intact and breaks == 0 else ("%d break%s" % [breaks, "" if breaks == 1 else "s"])
			line = "%s  ·  %s" % [time_text(time), pane]
			kind = "victory"
		else:
			line = _unscored_line(str(model.get("sub", "")), rows) if ranked else str(model.get("sub", ""))
			kind = _banner_kind(headline, line, ranked, rows.size())
	_results_headline.text = headline
	_results_sub.text = line
	var solo := ranked and rows.size() == 1
	_head.words = headline
	_head.kind = kind
	_head.line = "" if solo else line
	_head.big_time = line if solo else ""
	_head.info = info
	_sync_result_rows(rows, fresh, ranked, solo, info != "")
	var choose_in := float(model.get("choose_in", -1.0))
	_choose_label.text = "Play again within %d s" % _ceil_seconds(choose_in) if choose_in >= 0.0 and not _again_sent else ""
	_head.choose = _choose_label.text

## The banner for a headline: the crown of the show's champion, a win, a cleared round, the neutral ribbon for a tie or nobody.
func _banner_kind(headline: String, sub: String, ranked: bool, count: int) -> String:
	var words := headline.to_upper()
	if words.ends_with("CROWN"): return "champion"
	if ranked and count == 1: return "timesup" if sub.to_upper().begins_with("TIME") else "victory"
	if words.begins_with("NO ") or words.begins_with("NOBODY") or words.contains("TIE"): return "title"
	if words.contains(" WIN") or words.ends_with("CLEARED"): return "victory"
	return "title"

## A scored round's sub line without what the table shows: the parts that name a player ("MARCUS 7  TIM 3", "2ND TIM") are dropped, "SHIP IT" stays.
func _unscored_line(sub: String, rows: Array) -> String:
	var kept := PackedStringArray()
	for part: String in sub.split("  ·  ", false):
		var names := false
		for row_model: Dictionary in rows:
			var who := str(row_model.get("name", "")).to_upper()
			if who != "" and part.to_upper().contains(who): names = true
		if not names: kept.append(part)
	return "  ·  ".join(kept)

## The table: one row per player, best first on a ranked page (by seat otherwise), one column up to four players and two from five (the stage between them); the buttons under it; the stage's
## characters in the table's order (the podium); the heads of the cast characters baked for the rows.
func _sync_result_rows(rows: Array, fresh: bool, ranked: bool, solo: bool, has_info: bool) -> void:
	var sorted_rows := rows.duplicate()
	sorted_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := int(a.get("rank", 0)) if ranked else 0
		var rank_b := int(b.get("rank", 0)) if ranked else 0
		if rank_a != rank_b: return rank_a < rank_b
		return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	var count := sorted_rows.size()
	var seats := []
	for data: Dictionary in sorted_rows: seats.append(int(data.get("seat", 0)))
	var two := count > RESULT_ONE_COLUMN
	_apply_stage(seats, RESULT_STAGE_SHIFT if not two else 0.0, RESULT_STAGE_FAR if two else RESULT_STAGE_NEAR)
	MenuPortraits.request(self, seats)
	while _result_rows.size() > count:
		var old: Control = _result_rows.pop_back()
		_table_rows.remove_child(old)
		old.queue_free()
	var made := _result_rows.size()
	while _result_rows.size() < count:
		var row := Parts.ResultRow.new()
		_table_rows.add_child(row)
		_result_rows.append(row)
	var per_column := ceili(float(count) / 2.0) if two else maxi(count, 1)
	var top := RESULT_TOP
	if solo: top = _head.time_rect.end.y + 16.0
	elif has_info: top = RESULT_TOP + 38.0
	var pitch := clampf((RESULT_BOTTOM - top) / float(per_column), 46.0, 88.0)
	var height := minf(pitch - 10.0, 78.0)
	var width := RESULT_PAIR if two else RESULT_COLUMN
	var scored := ranked and count > 0 and (count > 1 or int(sorted_rows[0].get("points", 0)) > 0)
	for index in count:
		var data: Dictionary = sorted_rows[index]
		var row: Parts.ResultRow = _result_rows[index]
		var column := 1 if two and index >= per_column else 0
		var left := 40.0 if not two else (36.0 if column == 0 else DESIGN.x - 36.0 - width)
		row.size = Vector2(width, height)
		row.home = Vector2(left, top + pitch * float(index - per_column * column))
		row.seat = int(data.get("seat", index))
		row.rank = int(data.get("rank", 0)) if ranked else 0
		row.winner = ranked and row.rank == 1
		row.show_points = scored
		row.who = str(data.get("name", "Partner")) if str(data.get("name", "")) != "" else "Partner"
		row.title = str(TeamCast.player(row.seat).title)
		row.color = data.get("color", Kit.MUTED_ON_DARK)
		row.me = bool(data.get("me", false))
		row.choice = str(data.get("choice", "pending"))
		if index >= made and not fresh:
			row.points = int(data.get("points", 0))
			row.settle()
		else: row.set_points(int(data.get("points", 0)))
	# The buttons: under the table (one column), or in the middle (two).
	var again_wide := 290.0 if not two else 300.0
	var menu_wide := 220.0 if not two else 230.0
	var first := 40.0 if not two else (DESIGN.x - again_wide - menu_wide - 16.0) * 0.5 - 90.0 # (the credit sits at the right)
	_again_button.position = Vector2(first, RESULT_BUTTONS_Y)
	_again_button.size = Vector2(again_wide, RESULT_BUTTON_H)
	_menu_button.position = Vector2(first + again_wide + 16.0, RESULT_BUTTONS_Y)
	_menu_button.size = Vector2(menu_wide, RESULT_BUTTON_H)

## The stage's winners follow the table's order (best first: the top three stand on the podium room's pedestals) when it changed; `shift` puts the picture right of the middle.
func _apply_stage(seats: Array, shift: float, zoom: float) -> void:
	if _paper_title == null or not is_instance_valid(_paper_title): return
	var stage: Control = _paper_title.call("stage")
	if stage == null or not stage.is_node_ready(): return
	stage.set("shift", shift)
	stage.set("zoom", zoom)
	var key := str(seats)
	if key == _ranking_key: return
	_ranking_key = key
	stage.call("set_ranking", seats)

## The loading page's minigame: a small courier in a yellow hardhat hops along drifting paper platforms, one button
## (Space / Enter / pad A / tap or click anywhere on the band). Pure sky: no text beyond one comic-lettered hint, the
## score and the best in comic digits (best kept in user://). It lives under the page only while the page shows
## "loading" (_start_load_game / _stop_load_game) and never touches the loading itself: no level, network or progress
## state is read or written, the page's own ticker keeps feeding the bar. Cost: the platforms, the courier and the
## landing dust are painted ONCE into a small sprite sheet (a SubViewport that renders one frame, then rests), so a
## frame is a handful of textured quads and the course lives in preallocated arrays; the digits are re-set only when
## the score changes. (Redrawing ~200 circles per frame measurably slowed the real level build behind the page, see
## docs/comic-ui.md.) Space and Enter are always taken here while the page shows, so they can never reach a focused
## Cancel (Esc / pad B and a tap on CANCEL stay).
class ComicHop extends Control:
	const BAND := Rect2(332, 428, 572, 88) ## in STATUS_DESIGN: right of CANCEL, under the progress line, ending where it ends
	const LANE := 26.0 ## top strip for the hint / score
	const GROUND := 70.0 ## platform surface (band space)
	const HERO_X := 70.0
	const GRAVITY := 1150.0
	const JUMP_V := 290.0
	const FLIGHT := 0.504 ## seconds in the air: 2 * JUMP_V / GRAVITY
	const COYOTE := 0.09
	const BUFFER := 0.12
	const SPEED_START := 118.0
	const SPEED_STEP := 6.0
	const SPEED_MAX := 226.0
	const SLOTS := 8
	const SAVE := "user://comic_hop.cfg"
	## Platform widths on the sheet (the last is the long starting platform); a jump's reach decides which are used.
	const WIDTHS := [64.0, 76.0, 90.0, 104.0, 120.0, 136.0, 152.0, 300.0]
	const START_BLOCK := 7
	const CELL_H := 36.0 ## sheet row height; a platform's surface sits CELL_TOP below the cell top
	const CELL_TOP := 11.0
	const CELL_PAD := 8.0 ## ink border and hard shadow reach past the platform's ends
	const HERO_CELL := Vector2(20, 26) ## courier sprite; its boots are HERO_FOOT below the cell top
	const HERO_FOOT := 23.0
	const DUST_CELL := 16.0
	const SKIN := Color("ffd9a8")
	enum { IDLE, RUN, FALLEN, GHOST }
	static var _shader: Shader
	var state := IDLE
	var score := 0
	var best := 0
	var clock := 0.0
	var speed := SPEED_START
	var feet := GROUND
	var vy := 0.0
	var grounded := true
	var coyote := 0.0
	var buffer := 0.0
	var squash := 0.0 ## > 0 squashed (landing), < 0 stretched (take-off)
	var alpha := 1.0
	var ghost_t := 0.0
	var standing_id := 0
	var dust_t := 9.0
	var _x := PackedFloat32Array() ## per platform slot: left edge, width, surface offset, id, sheet cell
	var _w := PackedFloat32Array()
	var _dy := PackedFloat32Array()
	var _id := PackedInt32Array()
	var _v := PackedInt32Array()
	var _cell_x := PackedFloat32Array() ## sheet x (design units) of every platform cell, then the courier cell and the dust cell
	var _sheet_w := 0.0
	var _sheet_k := 3.0 ## sheet pixels per design unit
	var _sheet: SubViewport
	var _tex: Texture2D
	var _frames := 0
	var _last := 0
	var _next_id := 1
	var _rng := RandomNumberGenerator.new()
	var _tap_frame := -1
	var _best_dirty := false
	var _score_word ## HudComic.ComicText (a const script: untyped here)
	var _best_word
	var _hint_word
	var _hint_key: Control
	var _hud_dirty := true

	func _init() -> void:
		name = "ComicHop"
		position = BAND.position
		size = BAND.size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if _shader == null:
			_shader = Shader.new()
			_shader.code = "shader_type canvas_item;\nuniform float width = 572.0;\nuniform float edge = 34.0;\nvarying float lx;\nvoid vertex() { lx = VERTEX.x; }\nvoid fragment() { COLOR.a *= smoothstep(0.0, edge, lx) * smoothstep(width, width - edge, lx); }\n"
		var fade := ShaderMaterial.new() ## platforms fade in and out at the band's ends instead of popping
		fade.shader = _shader
		fade.set_shader_parameter("width", size.x)
		material = fade
		_rng.randomize()
		best = _load_best()
		_x.resize(SLOTS)
		_w.resize(SLOTS)
		_dy.resize(SLOTS)
		_id.resize(SLOTS)
		_v.resize(SLOTS)
		_place_block(0, -60.0, START_BLOCK, 0.0, 0)
		_last = 0
		for slot in range(1, SLOTS): _spawn(slot)
		var touch := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		var pad := not Input.get_connected_joypads().is_empty()
		_hint_word = Lettering.word("TAP TO JUMP" if touch else "OR TAP TO JUMP", 13.0)
		_score_word = Lettering.word("0", 20.0)
		_best_word = Lettering.word("BEST 0", 12.0)
		for word: Control in [_hint_word, _score_word, _best_word]:
			word.mouse_filter = Control.MOUSE_FILTER_IGNORE
			word.size = word.custom_minimum_size
			add_child(word)
		if not touch:
			_hint_key = HudComic.ComicText.keycap("A" if pad else "SPACE", 26.0)
			add_child(_hint_key)
		_layout_hud()

	func _ready() -> void:
		_build_sheet()

	func _exit_tree() -> void:
		_save_best()

	# ---------------------------------------------------------------- input

	func press() -> void:
		match state:
			IDLE:
				state = RUN
				speed = SPEED_START
				buffer = BUFFER
				_hud_dirty = true
			RUN:
				buffer = BUFFER

	## Space / Enter (and Up / W, pad A) are taken whether they jump or not: the page has nothing to confirm.
	func _input(event: InputEvent) -> void:
		if not is_visible_in_tree(): return
		if event is InputEventKey:
			match (event as InputEventKey).physical_keycode:
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_W:
					if event.pressed and not event.echo: press()
					get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			if event.pressed: press()
			get_viewport().set_input_as_handled()

	## A tap or click on the band (a touch and its emulated click arrive in one frame: one jump).
	func _gui_input(event: InputEvent) -> void:
		if not ((event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)): return
		accept_event()
		var frame := Engine.get_process_frames()
		if frame == _tap_frame: return
		_tap_frame = frame
		press()

	# ---------------------------------------------------------------- course

	func _speed_plan() -> float:
		return minf(SPEED_MAX, SPEED_START + SPEED_STEP * score)

	## Re-lays platform `slot` after the last one: gap and width scale with how far a jump carries at the current speed,
	## so every gap stays jumpable (window = flight distance minus gap, over the speed).
	func _spawn(slot: int) -> void:
		var reach := _speed_plan() * FLIGHT
		var low := 0
		var high := 0
		for index in START_BLOCK:
			if WIDTHS[index] < 0.6 * reach + 26.0: low = mini(index + 1, START_BLOCK - 1)
			if WIDTHS[index] <= 1.1 * reach + 26.0: high = index
		var dy := clampf(_dy[_last] + _rng.randf_range(-6.0, 6.0), -6.0, 6.0)
		_place_block(slot, _x[_last] + _w[_last] + _rng.randf_range(0.3, 0.6) * reach, _rng.randi_range(low, maxi(low, high)), dy, _next_id)
		_next_id += 1
		_last = slot

	func _place_block(slot: int, x0: float, variant: int, dy: float, id: int) -> void:
		_x[slot] = x0
		_w[slot] = WIDTHS[variant]
		_dy[slot] = dy
		_id[slot] = id
		_v[slot] = variant

	## Platform under the courier (x within the platform, a little forgiving for the courier's half width), or -1.
	func _block_at(px: float) -> int:
		for slot in SLOTS:
			if px >= _x[slot] - 4.0 and px <= _x[slot] + _w[slot] + 4.0: return slot
		return -1

	# ---------------------------------------------------------------- step

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.05)
		clock += dt
		_frames += 1
		_step(dt)
		if _hud_dirty: _layout_hud()
		queue_redraw()

	func _step(dt: float) -> void:
		var shift := speed * dt
		if state == IDLE: shift = minf(16.0 * dt, maxf(_x[0] + _w[0] - (HERO_X + 110.0), 0.0))
		for slot in SLOTS: _x[slot] -= shift
		for slot in SLOTS:
			if _x[slot] + _w[slot] < -30.0: _spawn(slot)
		buffer = maxf(buffer - dt, 0.0)
		coyote = maxf(coyote - dt, 0.0)
		squash = move_toward(squash, 0.0, dt * 4.5)
		dust_t += dt
		match state:
			IDLE:
				feet = GROUND
			RUN:
				_run(dt)
			FALLEN:
				vy += GRAVITY * dt
				feet += vy * dt
				alpha = clampf(1.0 - (feet - GROUND - 18.0) / 26.0, 0.0, 1.0)
				if feet > GROUND + 44.0: _begin_ghost()
			GHOST:
				ghost_t -= dt
				feet = GROUND - 26.0 + sin(clock * 5.0) * 2.0
				if ghost_t <= 0.0: _try_drop()

	func _run(dt: float) -> void:
		var slot := _block_at(HERO_X)
		if grounded:
			if slot < 0:
				grounded = false
				vy = 0.0
			else:
				feet = GROUND + _dy[slot]
			coyote = COYOTE
		if buffer > 0.0 and (grounded or coyote > 0.0):
			vy = -JUMP_V
			grounded = false
			coyote = 0.0
			buffer = 0.0
			squash = -0.7
			Ui.play(self, &"toggle")
		if grounded: return
		var before := feet
		vy += GRAVITY * dt
		feet += vy * dt
		if vy > 0.0 and slot >= 0:
			var surface := GROUND + _dy[slot]
			if before <= surface + 4.0 and feet >= surface:
				feet = surface
				vy = 0.0
				grounded = true
				squash = 0.6
				dust_t = 0.0
				if _id[slot] != standing_id:
					standing_id = _id[slot]
					score += 1
					speed = _speed_plan()
					if score > best:
						best = score
						_best_dirty = true
					_hud_dirty = true
				return
		if feet > GROUND + 26.0:
			state = FALLEN
			Ui.play(self, &"back")
			_save_best()

	func _begin_ghost() -> void:
		state = GHOST
		ghost_t = 0.35
		score = 0
		speed = SPEED_START
		alpha = 0.5
		vy = 0.0
		_hud_dirty = true

	## Back in play once a platform will still be under the courier for the short drop.
	func _try_drop() -> void:
		var slot := _block_at(HERO_X)
		if slot < 0 or _x[slot] > HERO_X - 12.0 or _x[slot] + _w[slot] < HERO_X + 16.0 + speed * 0.45: return
		state = RUN
		standing_id = _id[slot]
		grounded = false
		coyote = 0.0
		buffer = 0.0
		vy = 0.0
		alpha = 1.0

	# ---------------------------------------------------------------- score words

	func _layout_hud() -> void:
		_hud_dirty = false
		var right := size.x - 10.0
		var idle := state == IDLE
		HudComic.update(_score_word, str(score), 20.0)
		HudComic.update(_best_word, "BEST %d" % best, 12.0)
		_score_word.visible = not idle
		_hint_word.visible = idle
		if _hint_key != null: _hint_key.visible = idle
		_best_word.visible = best > 0
		var edge := right
		if idle:
			_hint_word.position = Vector2(edge - _hint_word.size.x, (LANE - _hint_word.size.y) * 0.5)
			edge = _hint_word.position.x
			if _hint_key != null:
				edge -= 10.0 + _hint_key.size.x
				_hint_key.position = Vector2(edge, (LANE - _hint_key.size.y) * 0.5 - 1.0)
		else:
			_score_word.position = Vector2(edge - _score_word.size.x, (LANE - _score_word.size.y) * 0.5)
			edge = _score_word.position.x
		_best_word.position = Vector2(edge - 18.0 - _best_word.size.x, (LANE - _best_word.size.y) * 0.5)

	static func _load_best() -> int:
		var config := ConfigFile.new()
		if config.load(SAVE) != OK: return 0
		return maxi(int(config.get_value("comic_hop", "best", 0)), 0)

	func _save_best() -> void:
		if not _best_dirty: return
		_best_dirty = false
		var config := ConfigFile.new()
		config.set_value("comic_hop", "best", best)
		config.save(SAVE)

	# ---------------------------------------------------------------- sprite sheet and drawing

	## One row of platforms (every width), the courier and a dust disc, painted once by SheetPainter into a SubViewport
	## that renders a single frame. Sheet pixels per design unit follow the page's real scale (2..4), so the ink stays crisp.
	func _build_sheet() -> void:
		var scale := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().x
		_sheet_k = clampf(ceilf(scale), 2.0, 4.0)
		_cell_x.resize(WIDTHS.size() + 2)
		var at := 0.0
		for index in WIDTHS.size():
			_cell_x[index] = at
			at += float(WIDTHS[index]) + 2.0 * CELL_PAD
		_cell_x[WIDTHS.size()] = at
		at += HERO_CELL.x
		_cell_x[WIDTHS.size() + 1] = at
		_sheet_w = at + DUST_CELL
		_sheet = SubViewport.new()
		_sheet.name = "Sheet"
		_sheet.transparent_bg = true
		_sheet.disable_3d = true
		_sheet.size = Vector2i(ceili(_sheet_w * _sheet_k), ceili(CELL_H * _sheet_k))
		_sheet.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := SheetPainter.new()
		painter.k = _sheet_k
		painter.cell_x = _cell_x
		_sheet.add_child(painter)
		add_child(_sheet)
		_tex = _sheet.get_texture()

	func _draw() -> void:
		if _tex == null or _frames < 3: return ## the sheet renders on its first frame
		var k := _sheet_k
		for slot in SLOTS:
			var x0 := _x[slot]
			var width := _w[slot]
			if x0 > size.x + 4.0 or x0 + width < -4.0: continue
			var cell := _v[slot]
			var cell_w := width + 2.0 * CELL_PAD
			draw_texture_rect_region(_tex, Rect2(x0 - CELL_PAD, GROUND + _dy[slot] + 2.0 - CELL_TOP, cell_w, CELL_H), Rect2(_cell_x[cell] * k, 0.0, cell_w * k, CELL_H * k))
		if dust_t < 0.3:
			var u := dust_t / 0.3
			var half := 8.0 * (0.4 + 0.9 * u)
			var tone := Color(1, 1, 1, 1.0 - u)
			var src := Rect2(_cell_x[WIDTHS.size() + 1] * k, 0.0, DUST_CELL * k, DUST_CELL * k)
			draw_texture_rect_region(_tex, Rect2(HERO_X - 6.0 - 10.0 * u - half, feet - 4.0 - half, half * 2.0, half * 2.0), src, tone)
			draw_texture_rect_region(_tex, Rect2(HERO_X + 6.0 + 10.0 * u - half, feet - 4.0 - half, half * 2.0, half * 2.0), src, tone)
		# The courier squashes on landing and stretches on take-off; the ghost after a fall pulses.
		var sx := 1.0 + 0.28 * squash
		var sy := 1.0 - 0.28 * squash
		var fade := alpha if state != GHOST else 0.38 + 0.14 * sin(clock * 8.0)
		draw_texture_rect_region(_tex, Rect2(HERO_X - HERO_CELL.x * sx * 0.5, feet - HERO_FOOT * sy, HERO_CELL.x * sx, HERO_CELL.y * sy), Rect2(_cell_x[WIDTHS.size()] * k, 0.0, HERO_CELL.x * k, HERO_CELL.y * k), Color(1, 1, 1, fade))

	## Paints the sheet once, in design units scaled by `k`.
	class SheetPainter extends Control:
		var k := 3.0
		var cell_x := PackedFloat32Array()

		func _init() -> void:
			mouse_filter = Control.MOUSE_FILTER_IGNORE

		func _draw() -> void:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
			for index in WIDTHS.size(): _block(Vector2(cell_x[index] + CELL_PAD, CELL_TOP), WIDTHS[index])
			_courier(Vector2(cell_x[WIDTHS.size()], 0.0))
			# Dust: a small soft white disc.
			var dust := Vector2(cell_x[WIDTHS.size() + 1] + DUST_CELL * 0.5, DUST_CELL * 0.5)
			draw_circle(dust, DUST_CELL * 0.5 - 2.0, Color(1, 1, 1, 0.9), true, -1.0, true)

		## A floating block in the show's colours: a mint top on a deep teal side, a navy outline round it. `at.y` is the surface line the
		## courier stands on.
		func _block(at: Vector2, width: float) -> void:
			var top := at.y - 1.0
			var height := 17.0
			var line := StyleBoxFlat.new()
			line.bg_color = ShowTheme.NAVY
			line.set_corner_radius_all(5)
			line.anti_aliasing = true
			draw_style_box(line, Rect2(at.x - 1.5, top - 1.5, width + 3.0, height + 3.0))
			var side := StyleBoxFlat.new()
			side.bg_color = ShowTheme.MINT_DEEP
			side.set_corner_radius_all(4)
			side.anti_aliasing = true
			draw_style_box(side, Rect2(at.x, top, width, height))
			var face := StyleBoxFlat.new()
			face.bg_color = ShowTheme.MINT
			face.set_corner_radius_all(4)
			face.anti_aliasing = true
			draw_style_box(face, Rect2(at.x, top, width, 7.0))

		## The hopping courier: a gold jacket, round head, a red hardhat, all flat. Its boots touch the cell's HERO_FOOT line.
		func _courier(cell: Vector2) -> void:
			var cx := cell.x + HERO_CELL.x * 0.5
			var foot := cell.y + HERO_FOOT
			var body := StyleBoxFlat.new()
			body.bg_color = ShowTheme.GOLD
			body.set_corner_radius_all(3)
			draw_style_box(body, Rect2(cx - 6.0, foot - 9.0, 12.0, 9.0))
			var head := Vector2(cx, foot - 13.5)
			draw_circle(head, 5.6, SKIN, true, -1.0, true)
			draw_circle(head + Vector2(2.2, 0.8), 0.9, ShowTheme.NAVY, true, -1.0, true)
			var dome_centre := head + Vector2(0.0, -1.5)
			draw_colored_polygon(_dome(dome_centre, 6.0), ShowTheme.RED)
			draw_rect(Rect2(cx - 7.0, head.y - 2.4, 14.0, 2.2), ShowTheme.RED)

		func _dome(centre: Vector2, radius: float) -> PackedVector2Array:
			var points := PackedVector2Array()
			for index in 13: points.append(centre + Vector2.from_angle(PI + PI * index / 12.0) * radius)
			return points
