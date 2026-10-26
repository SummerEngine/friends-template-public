extends RefCounted
## What a round plays: the two lobby circles and the levels they draw from (levels/level_world.gd, docs/level-format.md).
## The circle ids stay the wire keys: "adventure" = TIME ATTACK (5 random levels, total time), "challenge" = ENDLESS (random levels until the
## players leave). A plan is a plain Dictionary so the authority can publish it and clients can rebuild it:
## {course, level (0-based), time_limit (-1 = none), hazards, play_mode}. Shared by the authority, the local game and the clients.
## The play mode follows the number of players when the round starts: 2 carry the painting, 3 or more keep the balloon up. The show
## (SHOW) is never picked by player count: the show rules start its rounds on the levels that serve it (show_levels()).
const DevEnv := preload("res://dev_env.gd")
const LevelData := preload("res://levels/level_data.gd")
const TeamCast := preload("res://style/team_cast.gd")

const ADVENTURE := "adventure"
const CHALLENGE := "challenge"
const COURSES := [ADVENTURE, CHALLENGE]
## Diagnostics/local: --course=challenge makes the endless circle the default.
const COURSE_FLAG := "--course="
const CARRY := "carry"
const BALLOON := "balloon"
const SHOW := "show"
const PLAY_MODES := [CARRY, BALLOON, SHOW]
## Dev switch (editor binary / debug builds only): balloon mode with two players too. User arg or FRIENDS_BALLOON=1.
const BALLOON_FLAG := "--balloon"

## The two circles: title and subtitle for the lobby boards, headline and sub line of the results page ({time} = the run time).
const ORDERS := {
	ADVENTURE: {"id": ADVENTURE, "title": "TIME ATTACK", "subtitle": "5 random levels · total time", "time_limit": -1.0,
		"clear_headline": "TIME ATTACK", "clear_sub": "{time}"},
	CHALLENGE: {"id": CHALLENGE, "title": "ENDLESS", "subtitle": "Random levels until you leave", "time_limit": -1.0,
		"clear_headline": "ENDLESS", "clear_sub": "{time}"},
}

static var _titles: Array = []
static var _pool: Array = []
static var _modes: Array = [] ## per level: the play modes its file lists
static var _shows: Array = [] ## per level: the show round it serves ("race" | "survival" | "final", "" none)
static var _dir := ""
static var _rules: Array = [] ## per level: the round card's goal line (`rule`, "" none)
static var _hints: Array = [] ## per level: the hint under the goal on the round card (`hint`, "" none)
static var _plays: Array = [] ## per level: how a survival show level is played (`play`: "" the floor falls away / hazards, "badge" keep the logo)
static var _solos: Array = [] ## per level: false when a show for one player never draws or offers it (`solo: false`)
static var _cameras: Array = [] ## per level: "stage" for a level played in the stage view (`camera`), else ""
static var _caps: Array = [] ## per level: its own round cap in s (`cap`, 0 for the round kind's)
static var _stages: Array = [] ## per level: its `stage` section ({} for none: a tile stage round, docs/level-format.md "Stage rounds")
static var _draws: Array = [] ## per level: false when THE SHOW never draws it (`draw: false`; its own lobby circle still plays it)

static func valid(course: Variant) -> bool:
	return course is String and course in COURSES

static func default_course() -> String:
	for argument in DevEnv.user_args():
		if argument.begins_with(COURSE_FLAG) and valid(argument.trim_prefix(COURSE_FLAG)): return argument.trim_prefix(COURSE_FLAG)
	return ADVENTURE

static func orders() -> Dictionary:
	return ORDERS

## The level titles, read once from the level files (the files are the only list of levels).
static func _read(dir: String) -> void:
	if dir == _dir and not _titles.is_empty(): return
	_dir = dir
	_titles = []
	_pool = []
	_modes = []
	_shows = []
	_rules = []
	_hints = []
	_plays = []
	_solos = []
	_cameras = []
	_caps = []
	_stages = []
	_draws = []
	for number in range(1, LevelData.count(dir) + 1):
		var level := LevelData.load_level(number, dir)
		_titles.append(str(level.get("title", "LEVEL %d" % number)))
		_modes.append(level.get("modes", [CARRY]))
		_shows.append(str(level.get("show", "")))
		_rules.append(str(level.get("rule", "")))
		_hints.append(str(level.get("hint", "")))
		_plays.append(str(level.get("play", "")))
		_solos.append(bool(level.get("solo", true)))
		_cameras.append(str(level.get("camera", "")))
		_caps.append(float(level.get("cap", 0.0)))
		_stages.append(level.get("stage", {}))
		_draws.append(bool(level.get("draw", true)))
		if bool(level.get("pool", true)): _pool.append(number - 1)

static func level_count(dir := LevelData.DIR) -> int:
	_read(dir)
	return _titles.size()

## 0-based indices of the levels that Time Attack and Endless may draw in `play_mode` (`"pool": false` in a level file holds a level
## back; a level lists the modes it suits in `"modes"`; the solo lab keeps all).
static func pool_levels(play_mode := CARRY) -> Array:
	_read(LevelData.DIR)
	return _pool.filter(func(level: int) -> bool: return play_mode in (_modes[level] as Array))

## The 0-based levels that serve the show round `kind` ("race" | "survival" | "final"), in file order. Show levels carry `"pool": false`,
## so pool_levels() never offers them to Time Attack, Endless or a balloon run.
static func show_levels(kind: String) -> Array:
	_read(LevelData.DIR)
	var result: Array = []
	for level in _shows.size():
		if kind != "" and _shows[level] == kind and SHOW in (_modes[level] as Array): result.append(level)
	return result

## The 0-based levels THE SHOW may draw for the round `kind`: show_levels() without the ones that carry `"draw": false` (they stay on their own lobby circle).
static func draw_levels(kind: String) -> Array:
	return show_levels(kind).filter(func(level: int) -> bool: return bool(_draws[level]))

## The rooms of a balloon run: the 0-based levels that list "balloon" (and are in the pool), in file order. ROOM 01 is the first.
static func rooms(dir := LevelData.DIR) -> Array:
	_read(dir)
	return _pool.filter(func(level: int) -> bool: return BALLOON in (_modes[level] as Array))

## The room number (1-based) of level `level` (0-based), 0 when it is not a room.
static func room_of(level: int, dir := LevelData.DIR) -> int:
	return rooms(dir).find(level) + 1

## The play mode of a round that starts with `players` players: 2 carry, 3 or more balloon (the dev switch forces balloon).
static func play_mode_for(players: int) -> String:
	if players >= 3 or DevEnv.has_arg(BALLOON_FLAG) or DevEnv.read("FRIENDS_BALLOON") == "1": return BALLOON
	return CARRY

static func has_levels() -> bool:
	return level_count() > 0

## The level's title as shown: the cast's own title of its round (show.rounds.<id>.title) when it names one, else the level file's.
static func level_title(level: int) -> String:
	_read(LevelData.DIR)
	if level < 0 or level >= _titles.size(): return ""
	var own := TeamCast.round_text(round_id(level), "title")
	return own if own != "" else str(_titles[level])

## The level file's own title, whatever the cast calls the round (the key rounds are grouped by).
static func level_raw_title(level: int) -> String:
	_read(LevelData.DIR)
	return str(_titles[level]) if level >= 0 and level < _titles.size() else ""

## The id of the show round level `level` (0-based) belongs to: "r<file number of the first show level with the same title and kind>", so the two
## POSTER RUSH levels are one round (r17); "" for a level that is no show level. Computed from the level files' own titles, never the cast's.
static func round_id(level: int) -> String:
	_read(LevelData.DIR)
	if level < 0 or level >= _titles.size() or _shows[level] == "" or not SHOW in (_modes[level] as Array): return ""
	for first in level + 1:
		if _titles[first] == _titles[level] and _shows[first] == _shows[level] and SHOW in (_modes[first] as Array): return "r%d" % (first + 1)
	return ""

## The level's rule line for the round card (the cast's show.rounds.<id>.rule, else its file's own; "" when its file has none: the round kind's default is used, modes/show/rules.gd).
static func level_rule(level: int) -> String:
	_read(LevelData.DIR)
	if level < 0 or level >= _rules.size(): return ""
	var own := TeamCast.round_text(round_id(level), "rule")
	return own if own != "" else str(_rules[level])

## The level's hint, one more sentence under the goal on the round card (the cast's show.rounds.<id>.hint, else its file's own; "" for none).
static func level_hint(level: int) -> String:
	_read(LevelData.DIR)
	if level < 0 or level >= _hints.size(): return ""
	var own := TeamCast.round_text(round_id(level), "hint")
	return own if own != "" else str(_hints[level])

## How a show level is played besides its kind (`play` in its file): "" the kind's own rules, "badge" KEEP THE LOGO (modes/show/rules.gd).
static func level_play(level: int) -> String:
	_read(LevelData.DIR)
	return str(_plays[level]) if level >= 0 and level < _plays.size() else ""

## The level's `stage` section ({enclosure, cap}; {} for a level that is no tile stage round, docs/level-format.md "Stage rounds").
static func level_stage(level: int) -> Dictionary:
	_read(LevelData.DIR)
	return (_stages[level] as Dictionary) if level >= 0 and level < _stages.size() else {}

## "stage" when the level asks for the stage view (`camera` in the level file, docs/level-format.md), else "".
static func level_camera(level: int) -> String:
	_read(LevelData.DIR)
	return str(_cameras[level]) if level >= 0 and level < _cameras.size() else ""

## The level's own round cap in seconds (`cap` in the level file), 0 when it has none and the round kind's cap stands.
static func level_cap(level: int) -> float:
	_read(LevelData.DIR)
	return float(_caps[level]) if level >= 0 and level < _caps.size() else 0.0

## False when the level needs other players (a show for one never draws it and its lobby circle says so).
static func level_solo(level: int) -> bool:
	_read(LevelData.DIR)
	return bool(_solos[level]) if level >= 0 and level < _solos.size() else true

## `level` (0-based): the plan of that level.
static func plan(course: String, level := 0, play_mode := CARRY) -> Dictionary:
	return {"course": course if valid(course) else ADVENTURE, "level": clampi(level, 0, maxi(level_count() - 1, 0)), "time_limit": -1.0, "hazards": false,
		"play_mode": play_mode if play_mode in PLAY_MODES else CARRY}

static func default_plan() -> Dictionary:
	return plan(default_course())
