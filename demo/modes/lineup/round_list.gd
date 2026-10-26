extends RefCounted
## The rounds of THE SHOW as the lobby lists them (docs/party-show.md "Pick a round"): one entry per round title among the listed show levels (modes/lineup/lineup.json), so a player can
## play any round on its own from a lobby circle next to THE SHOW's. The list comes from the level files (`show`, `title`, `rule`, `solo`) and the lineup: a new show level appears in the
## lobby once it is in the lineup's list, with no code (the yard grows with the rows, network/walk_in_lobby.gd). The cast may rename a round (show.rounds.<id>.title / .rule, docs/swappables.md): its title and rule show here, its id stays. Shared by the authority, the local game and the lobby's look (network/walk_in_lobby.gd).
##   RoundList.entries()      # [{id, title, kind, levels (0-based), rule, solo}] of the lineup's rounds: races, then the final, then the survival rounds, in file order; `entries(true)` lists the hidden ones too
##   RoundList.entry(id)      # the entry of a circle id ("r<first file number>") or {}: also a round the lobby hides (tools and the dev flags can still pick it)
const CourseSection := preload("res://course_section.gd")
const Lineup := preload("res://modes/lineup/lineup.gd")

const SHOW := "show" ## the pick of the circle that plays the whole show (the cast's own circle, CourseSection.ADVENTURE)
const PREFIX := "r"
const ORDER := ["race", "final", "survival"]

static func entries(with_hidden := false) -> Array:
	var result: Array = []
	for kind: String in ORDER:
		for level: int in (CourseSection.show_levels(kind) if with_hidden else Lineup.levels(kind)):
			var title := CourseSection.level_title(level) ## the cast's name for the round, if it renamed it
			var raw := CourseSection.level_raw_title(level) ## rounds are grouped by the level files' own title: a rename never merges or splits rounds
			var at := -1
			for index in result.size():
				if CourseSection.level_raw_title(int((result[index].levels as Array)[0])) == raw and str(result[index].kind) == kind: at = index
			if at >= 0:
				(result[at].levels as Array).append(level)
				result[at].solo = bool(result[at].solo) and CourseSection.level_solo(level)
				continue
			result.append({"id": "%s%d" % [PREFIX, level + 1], "title": title, "kind": kind, "levels": [level], "rule": CourseSection.level_rule(level),
				"solo": CourseSection.level_solo(level)})
	return result

static func entry(id: String) -> Dictionary:
	if not id.begins_with(PREFIX): return {}
	for row: Dictionary in entries(true):
		if str(row.id) == id: return row
	return {}
