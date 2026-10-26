extends CanvasLayer
## The HUD of a stage round (a tile stage level: docs/party-show.md "Stage rounds"), client only, pure look, no state of its own: it draws the model the
## show's view builds from the show state (modes/show/view.gd `_stage_flow`), the same way on every machine, in the show's one look (client/show_theme.gd, the pieces in style/show_hud_kit.gd):
##   * the OBJECTIVE: a dark pill with the words at the top centre only while the digits count and GO shows (no objective text stays on the screen after that);
##   * the ELIMINATIONS pill at the top right (dark, white slanted words "Current eliminations: n/M"), with a cream pill with a red X and the name under it,
##     right-aligned, for every player who fell (the oldest on top, a new one comes in under the others);
##   * the countdown digits 3, 2, 1 and GO as the round starts (style/show_banner.gd), the VICTORY banner at the round's end and the cast's elimination word on a failure banner for the player who fell;
##   * the own marker: a yellow triangle over the local courier's head.
## The words are ours (the objective is built by `objective()`), the pictures are drawn in code.
##   StageHud.new() -> add_child -> show_model(model)   # every frame; model keys: see `show_model`
const ShowTheme := preload("res://client/show_theme.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")

const OBJECTIVE_SPLIT := "  " ## the objective's two lines: the warning, then what to be
const CREAM := Color("f6f0e0")
const DIGIT_HEIGHT := 0.097 ## of the screen's height, a digit's cap height
const DIGIT_AT := 0.464 ## the digits' middle, of the screen's height
const BANNER_AT := 0.2 ## the banner's middle, of the screen's height
const BANNER_WIDE := 0.42 ## its width, of the screen's width (at most BANNER_MAX px at k = 1)
const BANNER_MAX := 760.0
const ELIM_POP := 0.3 ## s the eliminations pill swells when the number changes
const FAILURE_FADE := 0.2 ## s the failure banner fades in over
const FEED_FADE := 0.25 ## s a feed pill fades out over before it is cut

## The face: everything is drawn by this one control from `model`.
class Face extends Control:
	var model := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if model.is_empty(): return
		var view := get_viewport_rect().size
		var scale := Kit.k(self)
		_objective(view, scale)
		_eliminations(view, scale)
		_marker(ShowTheme.unit(self))
		_digit(view)
		_banner(view, scale)

	func _eased(age: float, length: float) -> float:
		var share := clampf(age / maxf(length, 0.001), 0.0, 1.0)
		return 1.0 - pow(1.0 - share, 3.0)

	# -------------------------------------------------------------- the objective

	## The pill at the top centre, only while the digits count and GO shows (`pill`, `pill_age` since it came up): the words in up to three lines, centred on a dark pill.
	## It comes in a little big and goes in one cut.
	func _objective(view: Vector2, scale: float) -> void:
		var text := str(model.get("pill", ""))
		var age := float(model.get("pill_age", -1.0))
		if text == "" or age < 0.0: return
		var pop := 1.0 + 0.1 * (1.0 - _eased(age, 0.1))
		var size := 19.0 * scale
		var wide := minf(maxf(view.x * 0.32, 300.0 * scale), view.x * 0.62 - ShowTheme.menu_gap(self))
		var lines := Kit.wrapped(text, size, wide - size * 2.4)
		var pitch := size * 1.25
		var height := (lines.size() * pitch + 20.0 * scale) * pop
		var centre := Vector2(view.x * 0.5, 0.046 * view.y + height * 0.5 + 4.0 * scale)
		var rect := Rect2(centre - Vector2(wide * pop, height) * 0.5, Vector2(wide * pop, height))
		ShowTheme.box(self, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, maxf(1.6 * scale, 1.2), minf(height * 0.4, 28.0 * scale))
		for index in lines.size():
			ShowTheme.text(self, lines[index], Vector2(rect.get_center().x, rect.position.y + 10.0 * scale * pop + (index + 0.5) * pitch * pop), size * pop, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT)

	# -------------------------------------------------------------- the eliminations

	## The dark pill at the top right with the count, and under it, right-aligned, the cream red-X pills of the players who fell
	## (the oldest on top: a new one comes in under the others, a pill that expires is cut out and the rest move up).
	func _eliminations(view: Vector2, scale: float) -> void:
		var total := int(model.get("elim_m", -1))
		if total < 0: return
		var words := "Current eliminations: %d/%d" % [int(model.get("elim_n", 0)), total]
		var swell := 1.0 + 0.12 * (1.0 - _eased(float(model.get("elim_pop", 9.0)), ELIM_POP))
		var right := Kit.right_edge(self)
		var top := Kit.counter(self, words, right, Kit.TOP * scale, scale, 1.0, swell, view.x * 0.2).end.y + Kit.GAP * scale
		var feed: Array = model.get("feed", [])
		for entry: Dictionary in feed:
			var age := float(entry.age)
			var grow := 0.64 if age < 0.03 else (1.05 if age < 0.08 else 1.0) # in one frame at two thirds of the width, a hair over, then settled: no slide
			var fade := clampf(float(entry.get("left", 9.0)) / FEED_FADE, 0.0, 1.0)
			top = Kit.feed_row(self, right, top, scale, str(entry.name), "", 0, fade, grow, view.x * 0.127).end.y + Kit.GAP * 0.6 * scale

	# -------------------------------------------------------------- the countdown

	## A digit (age = seconds into its second) or GO (age = seconds since it came up) in the middle of the screen, popping in (style/show_banner.gd); a digit is replaced by the next at once
	## and GO is cut out when its time is over (the view stops sending it).
	func _digit(view: Vector2) -> void:
		var digit := str(model.get("digit", ""))
		var go := str(model.get("go", ""))
		var word := go if go != "" else digit
		if word == "": return
		var age := float(model.get("go_age", 0.0)) if go != "" else float(model.get("digit_age", 0.0))
		ShowBanner.countdown(self, word, age, Vector2(view.x * 0.5, view.y * DIGIT_AT), DIGIT_HEIGHT * view.y, go != "")

	# -------------------------------------------------------------- VICTORY and the failure banner

	## A banner in the upper third of the screen: VICTORY for the survivors, the cast's elimination word on a failure banner for the player who is out (it fades in), cut out when its time is over.
	func _banner(view: Vector2, scale: float) -> void:
		var wide := minf(view.x * BANNER_WIDE, BANNER_MAX * scale)
		var centre := Vector2(view.x * 0.5, view.y * BANNER_AT)
		var age := float(model.get("victory_age", -1.0))
		if age >= 0.0:
			ShowBanner.draw(self, "victory", "VICTORY", age, centre, wide)
			return
		age = float(model.get("failure_age", -1.0))
		var length := float(model.get("failure_len", 1.4))
		if age >= 0.0 and age < length:
			ShowBanner.draw(self, "failure", str(model.get("failure", "")), age, centre, wide, minf(age / FAILURE_FADE, 1.0) * clampf((length - age) / FAILURE_FADE, 0.0, 1.0))

	# -------------------------------------------------------------- the own marker

	## A yellow triangle over the local courier's head, the same size on the screen wherever the courier is (the model's `marker` is the head's screen point).
	func _marker(unit: float) -> void:
		if model.has("marker"): Kit.marker(self, Vector2(model.marker), unit)

var _face: Face
var _last := {}

func _init() -> void:
	layer = 21 # under the show's HUD (23) and plates (22): the player's own banner and the round card stay on top

## The words of the objective: how many go through (`need`) and how many play (`players`); alone nobody is outlasted.
static func objective(need: int, players: int) -> String:
	if players <= 1: return "DON'T FALL!%sSTAY ON THE TILES AS LONG AS YOU CAN!" % OBJECTIVE_SPLIT
	if need <= 1: return "DON'T FALL!%sBE THE LAST ONE STANDING!" % OBJECTIVE_SPLIT
	return "DON'T FALL!%sBE ONE OF THE LAST %d STANDING!" % [OBJECTIVE_SPLIT, need]

## `model`: {pill (String, "": the top centre pill's words), pill_age (s since it came up, -1 none), elim_n, elim_m (-1 hides the pill), elim_pop (s since n changed),
## feed ([{name, age, left}], oldest first: the top pill first), digit ("" none, "3" ..), digit_age (0..1), go ("" none, the word), go_age (s), go_len (s), victory_age (s, -1 none),
## victory_len (s), failure ("" or the word of the failure banner), failure_age (s, -1 none), failure_len (s), marker (Vector2, the local courier's head on the screen; absent: no marker)}. {} hides everything.
func show_model(model: Dictionary) -> void:
	if _face == null:
		_face = Face.new()
		add_child(_face)
	_last = model
	_face.model = model
	_face.size = get_viewport().get_visible_rect().size
	_face.visible = not model.is_empty()
	_face.queue_redraw()

func probe() -> Dictionary:
	return _last.duplicate(true)
