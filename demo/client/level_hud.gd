extends CanvasLayer
## The level game's words over a round, each on a small flat chip (hud_comic.gd): top centre the run ("TIME ATTACK · LEVEL 2 / 5",
## "ENDLESS · LEVEL 7") with the level's title under it, and a LEVEL CLEARED card on the team's accent in the middle while
## the next level is on its way.
## Reads the run the authority replicates (match.run, levels/level_run.gd state()); the local flow feeds the same dictionary.
## The run clock itself is the HUD's (client/hud.gd adds match.run.base to the level's clock).
const Ui = preload("res://client/friends_ui.gd")
const HudComic = preload("res://client/hud_comic.gd")
const CourseSection = preload("res://course_section.gd")
const LevelRun = preload("res://levels/level_run.gd")
const TOP_CAP := 20.0
const CARD_CAP := 64.0
const NOTE_CAP := 24.0

var _top: Control
var _title: Label
var _card: Control
var _card_line: Label
var _card_next: Label
var _note: Control ## the lobby line, comic lettering like the level title
var _top_text := ""
var _card_text := ""
var _unit := 1.0
var _run_shown := false

func _init() -> void:
	layer = 22
	visible = false

func _ensure() -> void:
	if _top != null: return
	_top = HudComic.word("TIME ATTACK", TOP_CAP)
	add_child(_top)
	_title = HudComic.small("", 20)
	add_child(_title)
	_card = HudComic.word("LEVEL CLEARED", CARD_CAP)
	HudComic.accent_style(_card)
	add_child(_card)
	_card_line = HudComic.small("", 26)
	add_child(_card_line)
	_card_next = HudComic.small("", 20)
	add_child(_card_next)
	_card.visible = false
	_card_line.visible = false
	_card_next.visible = false
	_note = HudComic.word("", NOTE_CAP)
	add_child(_note)
	_note.visible = false

## One line top centre without a run (the local lobby: the countdown, what to do); "" hides it.
func note(text: String) -> void:
	_ensure()
	if text == "":
		if _note.visible and not _run_shown: visible = false
		_note.visible = false
		return
	visible = true
	_unit = _scale()
	HudComic.update(_note, text, NOTE_CAP * _unit)
	_note.visible = true
	_note.position = Vector2((get_viewport().get_visible_rect().size.x - _note.size.x) * 0.5, 22.0 * _unit)

## `run` is match.run ({} hides everything), `level_seconds` the seconds of the level being played.
func update(run: Dictionary, level_seconds: float) -> void:
	_ensure()
	_run_shown = not run.is_empty()
	if run.is_empty():
		visible = _note.visible
		_top.visible = false
		_title.visible = false
		_card.visible = false
		_card_line.visible = false
		_card_next.visible = false
		return
	visible = true
	_top.visible = true
	_title.visible = true
	_note.visible = false
	_unit = _scale()
	var endless := str(run.get("mode", "")) == LevelRun.ENDLESS
	var level := int(run.get("level", 0))
	var top := ("ENDLESS  ·  LEVEL %d" % int(run.get("number", 1))) if endless else ("TIME ATTACK  ·  LEVEL %d / %d" % [int(run.get("number", 1)), int(run.get("count", 1))])
	var room := int(run.get("room", 0)) # a balloon run plays rooms (levels/level_run.gd)
	if room > 0: top = "ROOM %02d / %02d" % [room, int(run.get("rooms", room))]
	if run.has("label"): top = "%s  ·  LEVEL %d / %d" % [str(run.label), int(run.get("number", 1)), int(run.get("count", 1))] # the solo lab's own run (lab/lab_main.gd run_state)
	_top_text = top
	HudComic.update(_top, top, TOP_CAP * _unit)
	var title := CourseSection.level_title(level)
	if endless and int(run.get("cleared", 0)) > 0: title += "   ·   %d CLEARED" % int(run.get("cleared", 0))
	_title.text = title
	_title.add_theme_font_size_override("font_size", int(round(20.0 * _unit)))
	var clearing := bool(run.get("clearing", false))
	_card.visible = clearing
	_card_line.visible = clearing
	_card_next.visible = clearing
	if clearing:
		var times: Array = run.get("times", [])
		var last := float(times[times.size() - 1]) if not times.is_empty() else level_seconds
		var queue: Array = run.get("queue", [])
		HudComic.update(_card, "ROOM CLEARED" if room > 0 else "LEVEL CLEARED", CARD_CAP * _unit)
		_card_line.text = "%s  ·  %s" % [CourseSection.level_title(int(queue[times.size() - 1]) if times.size() - 1 < queue.size() and not times.is_empty() else level), LevelRun.format_time(last)]
		_card_line.add_theme_font_size_override("font_size", int(round(26.0 * _unit)))
		_card_next.text = ("Next: %s" % str(run.next_title)) if run.has("next_title") else ("Total %s" % LevelRun.format_time(float(run.get("base", 0.0))))
		_card_next.add_theme_font_size_override("font_size", int(round(20.0 * _unit)))
	_place()

## HUD pixel scale from the viewport height (1.0 at 720), as HudComic.unit_of does for a CanvasItem.
func _scale() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / 720.0, 0.72, 2.4)

func _process(_delta: float) -> void:
	if visible and _top != null: _place()

func _place() -> void:
	var size := get_viewport().get_visible_rect().size
	_top.position = Vector2((size.x - _top.size.x) * 0.5, 22.0 * _unit)
	_title.size = Vector2.ZERO
	_title.position = Vector2((size.x - _title.get_minimum_size().x) * 0.5, 22.0 * _unit + _top.size.y + 14.0 * _unit)
	if _card.visible:
		_card.position = Vector2((size.x - _card.size.x) * 0.5, size.y * 0.30)
		_card_line.size = Vector2.ZERO
		_card_line.position = Vector2((size.x - _card_line.get_minimum_size().x) * 0.5, _card.position.y + _card.size.y + 24.0 * _unit)
		_card_next.size = Vector2.ZERO
		_card_next.position = Vector2((size.x - _card_next.get_minimum_size().x) * 0.5, _card_line.position.y + _card_line.get_minimum_size().y + 20.0 * _unit)

func probe() -> Dictionary:
	return {"visible": visible, "top": _top_text, "title": _title.text if _title != null else "", "clearing": _card != null and _card.visible,
		"card_line": _card_line.text if _card_line != null else "", "card_next": _card_next.text if _card_next != null else ""}
