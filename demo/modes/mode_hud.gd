extends CanvasLayer
## The minigame HUD (docs/modes.md) in the show's one look (client/show_theme.gd, the pieces in style/show_hud_kit.gd): the words of the mode's view (modes/mode_view.gd hud()) as dark pills with the thin
## light outline and slanted Lilita One words. Top centre the title pill, the right column (clear of a phone's MENU corner):
## the timer (chunky digits, a stopwatch glyph), the counters (words pills), the feed (cream name pills with a red X or a gold rank badge) and the scoreboard (best first, a pill in the player's colour with a gold rank
## badge, players out dimmed); in the middle the big word (a banner `big_kind`: victory / champion / qualified / eliminated / failure / timesup / title; `digit` and `go`: the countdown; none: a big pill)
## with a line under it, a note at the bottom. Client only, pure look: one control draws it all from the model.
## `calm`: the small layout for a mode with a lot of play to see: the banner smaller and high up, off the centre.
const ShowTheme := preload("res://client/show_theme.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const TeamCast := preload("res://style/team_cast.gd")
const TITLE_CAP := 20.0 ## (read by the views that measure the big word: modes/who_said_it/view.gd)
const BIG_CAP := 54.0
const CALM_BIG := 0.8 ## calm: the scale of the banner
const BIG_AT := 0.24 ## the banner's middle, as a share of the screen height
const CALM_BIG_AT := 0.18
const DIGIT_AT := 0.46 ## the countdown's middle
const DIGIT_CAP := 0.097 ## the countdown digit's cap height, of the screen's height
const BANNER_WIDE := 0.42 ## the banner's width, of the screen's width (at most BANNER_MAX px at 720 high)
const BANNER_MAX := 760.0

## The face: everything is drawn by this one control from `model`.
class Face extends Control:
	var model := {}
	var seats: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if model.is_empty(): return
		var view := get_viewport_rect().size
		var scale := Kit.k(self)
		var calm := bool(model.get("calm", false))
		var small := 0.9 if calm else 1.0
		_title(view, scale * small)
		_column(view, scale * small)
		_big(view, scale, calm)
		_note(view, scale)
		if model.has("marker"): Kit.marker(self, Vector2(model.marker), ShowTheme.unit(self))

	func _title(view: Vector2, scale: float) -> void:
		var words := str(model.get("title", ""))
		if words == "": return
		Kit.line_pill(self, words, Vector2(view.x * 0.5, (Kit.TOP + Kit.PILL_H * 0.5) * scale), scale * 0.85, 1.0, 0.0, view.x * 0.4)

	## The right column, top down: the timer, the counters, the feed, the board.
	func _column(view: Vector2, scale: float) -> void:
		var right := Kit.right_edge(self)
		var top := Kit.TOP * scale
		var timer := float(model.get("timer", -1.0))
		if timer >= 0.0: top = Kit.timer(self, timer, right, top, scale).end.y + Kit.GAP * scale
		var counters: Array = model.get("counters", [])
		var swell := 1.0 + 0.12 * (1.0 - clampf(float(model.get("counter_age", 9.0)) / 0.3, 0.0, 1.0))
		for index in counters.size():
			top = Kit.counter(self, str(counters[index]), right, top, scale, 1.0, swell if index == 0 else 1.0, 240.0 * scale).end.y + Kit.GAP * scale
		var feed: Array = model.get("feed", [])
		for entry: Dictionary in feed:
			var age := float(entry.get("age", 1.0))
			var grow := 0.64 if age < 0.03 else (1.05 if age < 0.08 else 1.0)
			var left := float(entry.get("left", 9.0))
			var fade := clampf(left / 0.25, 0.0, 1.0)
			top = Kit.feed_row(self, right, top, scale, str(entry.get("name", "")), str(entry.get("tail", "")), int(entry.get("rank", 0)), fade, grow, 150.0 * scale).end.y + Kit.GAP * 0.6 * scale
		_board(right, top + Kit.GAP * 0.4 * scale, scale)

	func _board(right: float, top: float, scale: float) -> void:
		var list: Variant = model.get("scores", [])
		if not list is Array or (list as Array).is_empty(): return
		var scores: Array = list
		var gone: Array = model.get("out", [])
		var order: Array = range(scores.size())
		order.sort_custom(func(a: int, b: int) -> bool: return int(scores[a]) > int(scores[b]) or (int(scores[a]) == int(scores[b]) and a < b))
		var tint := bool(model.get("tint", false))
		for place in order.size():
			var slot: int = order[place]
			var seat := int(seats[slot]) if slot < seats.size() else slot
			var color := TeamCast.player_color(seat) if tint else Color("3a3d46")
			top = Kit.board_row(self, right, top, scale, place + 1, str(TeamCast.player(seat).name).to_upper(), int(scores[slot]), color, gone.has(slot), 1.0, 210.0 * scale).end.y + Kit.GAP * 0.6 * scale

	## The middle: the banner / countdown / big pill, and the line under it.
	func _big(view: Vector2, scale: float, calm: bool) -> void:
		var words := str(model.get("big", ""))
		var kind := str(model.get("big_kind", ""))
		var age := float(model.get("big_age", 1.0))
		var alpha := float(model.get("big_alpha", 1.0))
		var bottom := view.y * (CALM_BIG_AT if calm else BIG_AT)
		if words != "":
			if kind == "digit" or kind == "go":
				ShowBanner.countdown(self, words, age, Vector2(view.x * 0.5, view.y * DIGIT_AT), view.y * DIGIT_CAP, kind == "go", alpha)
				bottom = 0.0
			elif ShowBanner.KINDS.has(kind):
				var wide := minf(view.x * BANNER_WIDE, BANNER_MAX * scale) * (CALM_BIG if calm else 1.0)
				ShowBanner.draw(self, kind, words, age, Vector2(view.x * 0.5, bottom), wide, alpha)
				bottom += ShowBanner.height_of(kind, wide) * 0.5 + 12.0 * scale
			else: # a big pill: the mode's own words (a question, a verdict)
				var rect := Kit.line_pill(self, words, Vector2(view.x * 0.5, bottom), scale * 1.5, alpha, 0.0, view.x * 0.92)
				bottom = rect.end.y + 12.0 * scale
		var line := str(model.get("line", ""))
		if line != "" and bottom > 0.0:
			Kit.line_pill(self, line, Vector2(view.x * 0.5, bottom + Kit.ROW_H * scale * 0.55), scale, alpha * clampf((age - 0.25) / 0.2, 0.0, 1.0), 0.0, view.x * 0.92)

	func _note(view: Vector2, scale: float) -> void:
		var words := str(model.get("note", ""))
		if words == "": return
		Kit.line_pill(self, words, Vector2(view.x * 0.5, view.y - (36.0 + Kit.ROW_H * 0.5) * scale), scale * 0.85, 1.0, 0.0, view.x * 0.92)

var seats: Array = [] ## slot -> cast index, for the names on the board
var _face: Face
var _last := {}

func _init() -> void:
	layer = 23
	visible = false

## `model` is the view's hud() ({} hides everything).
func show_model(model: Dictionary) -> void:
	if _face == null:
		_face = Face.new()
		add_child(_face)
	visible = not model.is_empty()
	_last = model
	if not visible: return
	_face.model = model
	_face.seats = seats
	_face.size = get_viewport().get_visible_rect().size
	_face.queue_redraw()

func probe() -> Dictionary:
	return _last.duplicate()
