extends RefCounted
## Which rounds the show offers (docs/party-show.md "The lineup"): one reversible list, `modes/lineup/lineup.json`, that hides rounds without touching their levels or modes.
##   "lobby"     level file numbers (1-based) whose rounds get a lobby circle (modes/lineup/round_list.gd) and may be drawn by THE SHOW; a missing or empty list offers every show level
##   "playlist"  the rounds of THE SHOW in order: `rules` is the kind the round is played by (modes/show/rules.gd: race, survival, final), `levels` the kind of show level it draws from.
##               The last round ends in the victory banner and the podium. A "final" round may be played on a race level: the first across the goal wins the crown. A missing playlist
##               is race, survival, final on their own levels.
## `--all-rounds` (dev tools only) ignores the file: every show level is offered, the playlist is the default one (tools/modes/show_check.gd uses it for KEEP THE LOGO).
## The levels and the circle ids stay what they are ("r<file number>"): adding a number to "lobby" brings a round back, both in the lobby and in THE SHOW's draw.
##   Lineup.levels(kind)        # the 0-based show levels of `kind` that are in the lobby, in file order
##   Lineup.playlist()          # [{rules, levels}] the rounds of THE SHOW
##   Lineup.draw(index)         # the 0-based levels round `index` of the playlist may draw: its kind's draw levels (CourseSection.draw_levels) that are in the lobby
const CourseSection := preload("res://course_section.gd")
const DevEnv := preload("res://dev_env.gd")

const PATH := "res://modes/lineup/lineup.json"
const KINDS := ["race", "survival", "final"]
const ALL_FLAG := "--all-rounds" ## dev tools only (DevEnv.user_args(), like --show-level=): ignore the file, offer every show level and play race, survival, final on their own levels

static var _loaded := false
static var _lobby: Array = [] ## 0-based levels; empty: every show level
static var _playlist: Array = []

static func _read() -> void:
	if _loaded: return
	_loaded = true
	_lobby = []
	_playlist = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) and not DevEnv.has_arg(ALL_FLAG) else null
	if data is Dictionary:
		for number in data.get("lobby", []): _lobby.append(int(number) - 1)
		for row in data.get("playlist", []):
			if row is Dictionary and str(row.get("rules", "")) in KINDS and str(row.get("levels", "")) in KINDS: _playlist.append({"rules": str(row.rules), "levels": str(row.levels)})
	if _playlist.is_empty():
		for kind: String in KINDS: _playlist.append({"rules": kind, "levels": kind})

static func listed(level: int) -> bool:
	_read()
	return _lobby.is_empty() or _lobby.has(level)

static func levels(kind: String) -> Array:
	return CourseSection.show_levels(kind).filter(func(level: int) -> bool: return listed(level))

static func playlist() -> Array:
	_read()
	return _playlist.duplicate(true)

static func draw(index: int) -> Array:
	var rows := playlist()
	if index < 0 or index >= rows.size(): return []
	return CourseSection.draw_levels(str(rows[index].levels)).filter(func(level: int) -> bool: return listed(level))
