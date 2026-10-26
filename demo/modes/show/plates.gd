extends CanvasLayer
## The show's two screen plates (docs/party-show.md), client only, pure look, no state of their own, in the show's one look (client/show_theme.gd, style/show_banner.gd, style/show_hud_kit.gd):
## * the ROUND CARD: the level's own title (`CourseSection.level_title`) as a title banner popping in, under it the level's goal in plain words (its `rule`, else the
##   round kind's) on a dark pill and under that the round's qualify / scoring line on a smaller one, up top for the card's first 3 s (until the last digit takes over), and nowhere once play starts;
## * the TARGET CUE: a level may list `"cues": [{"t", "until", "slot"}]` (docs/level-format.md): from level clock `t` to `until` this plate
##   shows that obstacle's picture and label big at the top of the screen with the seconds left. The clock is the level world's own
##   (`run.level_world.clock`, the same on every peer), so nothing is replicated and nothing is decided here.
##   Plates.new() -> add_child -> update(state, level_clock)   # every frame
const TeamCast := preload("res://style/team_cast.gd")
const CourseSection := preload("res://course_section.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const ShowRules := preload("res://modes/show/rules.gd") ## the card's timings

const COUNT_FROM := 1.0 ## s before GO: the card gives way to the digit (the HUD's big word) and these plates leave: the card reads for 3 of its 4 s
const KIND_GOALS := {"race": "RACE TO THE GOAL", "survival": "STAY ON THE FLOOR TO THE END", "final": "CLIMB TO THE CROWN"} ## a level without its own `rule`
const TITLE_AT := 0.17 ## the title banner's middle, of the screen's height
const TITLE_WIDE := 0.46 ## its width, of the screen's width (at most TITLE_MAX px at k = 1)
const TITLE_MAX := 820.0
const CUE_SHARE := 0.26 ## the cue plate's width as a share of the screen width
const CUE_HURRY := 1.0 ## s left: the countdown turns red
const CUE_POP := 0.3 ## s the plate takes to pop in

## The round card: the title banner and the goal and rule pills, drawn from the model {title, goal, hint, rule, age} (age: s since the card came up).
class Card extends Control:
	var model := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if model.is_empty(): return
		var view := get_viewport_rect().size
		var k := Kit.k(self)
		var age := float(model.get("age", 1.0))
		var wide := minf(view.x * TITLE_WIDE, TITLE_MAX * k)
		var centre := Vector2(view.x * 0.5, view.y * TITLE_AT)
		var line := str(model.get("line", ""))
		ShowBanner.draw(self, "title", str(model.get("title", "")), age, centre, wide, 1.0, line)
		var y := centre.y + ShowBanner.height_of("title", wide, line != "") * 0.5 + 18.0 * k
		var room := view.x * 0.92
		var pop := ShowTheme.bounce(age - 0.15, 0.3, 1.4)
		if str(model.get("goal", "")) != "":
			var rect := Kit.line_pill(self, str(model.goal), Vector2(view.x * 0.5, y + Kit.ROW_H * k * 0.65), k * 1.3, pop, 0.0, room)
			y = rect.end.y + 8.0 * k
		if str(model.get("hint", "")) != "":
			var hint_rect := Kit.line_pill(self, str(model.hint), Vector2(view.x * 0.5, y + Kit.ROW_H * k * 0.55), k * 0.9, pop, 0.0, room)
			y = hint_rect.end.y + 8.0 * k
		if str(model.get("rule", "")) != "":
			Kit.line_pill(self, str(model.rule), Vector2(view.x * 0.5, y + Kit.ROW_H * k * 0.55), k * 0.9, pop, 0.0, room)

## The target cue: the obstacle's picture (or its colour plate) with its label under it and the seconds left in a disc.
class Cue extends Control:
	var picture: Texture2D
	var color := Color.WHITE
	var label := ""
	var left := 0.0
	var hurry := false
	var tint := Color.WHITE

	func _draw() -> void:
		var wide := size.x
		var pad := wide * 0.04
		ShowTheme.box(self, Rect2(Vector2.ZERO, size), ShowTheme.PILL, ShowTheme.PILL_EDGE, maxf(wide * 0.008, 1.5), wide * 0.07)
		var art := Rect2(pad, pad, wide - pad * 2.0, (wide - pad * 2.0) * 0.5)
		if picture != null:
			draw_texture_rect(picture, art, false, tint)
		else:
			draw_rect(art, color)
		var line := Rect2(pad, art.end.y + pad * 0.5, wide - pad * 2.0, size.y - art.end.y - pad * 1.5)
		_fit(label, line, Color.WHITE)
		var disc := wide * 0.11 ## the seconds left sit in the top right corner as plain outlined digits (yellow in the last seconds)
		var at := Vector2(wide - pad - disc * 0.2, pad + disc * 0.2)
		_fit(str(ceili(left)), Rect2(at.x - disc * 0.7, at.y - disc * 0.7, disc * 1.4, disc * 1.4), ShowTheme.YELLOW if hurry else Color.WHITE)

	## `text` as large as fits `rect` (one line, slanted display type), centred.
	func _fit(text: String, rect: Rect2, ink: Color) -> void:
		var reference := 64.0
		var measured := ShowTheme.width(text, reference) * (1.0 + ShowTheme.SLANT * 0.1)
		var size := minf(reference * rect.size.x / maxf(measured, 1.0), rect.size.y / ShowTheme.CAP * 0.8)
		ShowTheme.text(self, text, rect.get_center(), maxf(size, 8.0), ink, Color(0, 0, 0, 0.9), maxf(size * 0.12, 1.0), Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT)

var _card: Card
var _cue: Cue
var _level := -999
var _cues: Array = [] ## the current level's cues: {t, until, slot}

func _init() -> void:
	layer = 22 # under the show's HUD (23)

## `state`: the show state; `clock`: the level world's clock (seconds).
func update(state: Dictionary, clock: float) -> void:
	var level := int(state.get("level", -1))
	if level != _level:
		_level = level
		_cues = _read_cues(level)
	_show_title(state, level)
	_show_cue(state, clock)

## True while the round card is up (the card's first seconds): the HUD's own title chip steps aside for it. A stage round's card is only its first STAGE_TITLE
## seconds: the digits take over for the last STAGE_COUNT.
static func title_up(state: Dictionary) -> bool:
	var from := ShowRules.STAGE_COUNT if bool(state.get("stage", false)) else COUNT_FROM
	return int(state.get("level", -1)) >= 0 and str(state.get("phase", "")) == "card" and float(state.get("count", 0.0)) > from

func _show_title(state: Dictionary, level: int) -> void:
	var shown := title_up(state)
	if _card == null:
		_card = Card.new()
		add_child(_card)
	_card.visible = shown
	if not shown:
		_card.model = {}
		return
	# the goal in plain words (the level's own rule, else its round kind's), then who qualifies
	var own := CourseSection.level_rule(level)
	var of_show := "Round %d  ·  " % int(state.get("round", 1)) if int(state.get("rounds", 3)) > 1 else "" # one round picked in the lobby: no round number
	var length := ShowRules.STAGE_CARD if bool(state.get("stage", false)) else ShowRules.CARD
	_card.model = {"title": CourseSection.level_title(level), "goal": own if own != "" else str(KIND_GOALS.get(str(state.get("kind", "")), "")), "hint": CourseSection.level_hint(level),
		"line": "%s%s" % [of_show, str(state.get("kind", "")).capitalize()], "rule": str(state.get("card", "")), "age": length - float(state.get("count", 0.0))}
	_card.size = get_viewport().get_visible_rect().size
	_card.queue_redraw()

func _show_cue(state: Dictionary, clock: float) -> void:
	var active := {}
	if str(state.get("phase", "")) == "play":
		for cue: Dictionary in _cues:
			if clock >= float(cue.t) and clock < float(cue.until): active = cue
	if _cue == null:
		_cue = Cue.new()
		_cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_cue)
	_cue.visible = not active.is_empty()
	if active.is_empty(): return
	var sign := TeamCast.obstacle(int(str(active.slot).trim_prefix("obstacle_")))
	var view := get_viewport().get_visible_rect().size
	_cue.picture = sign.get("picture") as Texture2D
	var named: Color = sign.get("color", Color(0, 0, 0, 0))
	_cue.color = named if named.a > 0.0 else ShowTheme.PURPLE
	_cue.tint = Color.WHITE.lerp(named, SlotFrames.PICTURE_TINT) if named.a > 0.0 else Color.WHITE # the same tint the obstacle's tiles wear
	_cue.label = str(sign.get("label", ""))
	_cue.left = float(active.until) - clock
	_cue.hurry = _cue.left <= CUE_HURRY
	var wide := view.x * CUE_SHARE
	_cue.size = Vector2(wide, wide * 0.5 + wide * 0.04 * 2.0 + wide * 0.17)
	_cue.pivot_offset = Vector2(_cue.size.x * 0.5, 0.0)
	_cue.scale = Vector2.ONE * (0.6 + 0.4 * ShowTheme.bounce(clock - float(active.t), CUE_POP))
	_cue.position = Vector2((view.x - wide) * 0.5, Kit.k(_cue) * 66.0)
	_cue.queue_redraw()

## The level file's `cues` ([] for none): {t, until, slot} in level clock seconds, in order.
static func _read_cues(level: int) -> Array:
	var result: Array = []
	if level < 0: return result
	var path := "%s/level_%02d.json" % ["res" + "://levels", level + 1]
	if not FileAccess.file_exists(path): return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("cues") is Array:
		for entry: Variant in (parsed as Dictionary).cues:
			if entry is Dictionary and entry.has("t") and entry.has("until") and str(entry.get("slot", "")).begins_with("obstacle_"): result.append(entry)
	return result
