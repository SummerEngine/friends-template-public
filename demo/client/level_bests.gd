extends RefCounted
## The level game's personal bests, kept on this device (user://levels.cfg): the shortest total of a finished time attack and the
## most levels of an endless run, apart for carry and balloon runs. The authority replicates the run (match.run); each player's own
## client keeps its own bests.
const LevelRun = preload("res://levels/level_run.gd")
const SAVE := "user://levels.cfg"

static func best_total(play_mode := "carry") -> float:
	var saved := ConfigFile.new()
	return float(saved.get_value("best", _key(LevelRun.TIME_ATTACK, play_mode), -1.0)) if saved.load(SAVE) == OK else -1.0

static func best_endless(play_mode := "carry") -> int:
	var saved := ConfigFile.new()
	return int(saved.get_value("best", _key(LevelRun.ENDLESS, play_mode), 0)) if saved.load(SAVE) == OK else 0

## The save key of a run mode: carry runs use the plain keys, balloon runs their own.
static func _key(mode: String, play_mode: String) -> String:
	return mode if play_mode != "balloon" else mode + "_balloon"

## Saves the result of a run that has ended (a finished time attack, an endless run with at least one level) when it beats the
## stored best. Returns {"line": text for the results page ("NEW BEST" / "BEST 3:01.2"), "new": bool}; {} for a run that counts for nothing.
static func record(run: Dictionary) -> Dictionary:
	var saved := ConfigFile.new()
	saved.load(SAVE)
	var play_mode := str(run.get("play_mode", "carry"))
	if str(run.get("mode", "")) == LevelRun.TIME_ATTACK:
		if not bool(run.get("finished", false)): return {}
		var total := float(run.get("base", 0.0))
		if total <= 0.0: return {}
		var old := float(saved.get_value("best", _key(LevelRun.TIME_ATTACK, play_mode), -1.0))
		if old < 0.0 or total < old:
			saved.set_value("best", _key(LevelRun.TIME_ATTACK, play_mode), total)
			saved.save(SAVE)
			return {"line": "NEW BEST", "new": true}
		return {"line": "BEST %s" % LevelRun.format_time(old), "new": false}
	var cleared := int(run.get("cleared", 0))
	if cleared <= 0: return {}
	var best := int(saved.get_value("best", _key(LevelRun.ENDLESS, play_mode), 0))
	if cleared > best:
		saved.set_value("best", _key(LevelRun.ENDLESS, play_mode), cleared)
		saved.save(SAVE)
		return {"line": "NEW BEST", "new": true}
	return {"line": "BEST %d LEVEL%s" % [best, "" if best == 1 else "S"], "new": false}
