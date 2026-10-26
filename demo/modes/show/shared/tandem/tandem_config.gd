extends RefCounted
## EXPERIMENT (switchable): TANDEM, the switch and the numbers (docs/party-show.md "Tandem (experiment)"). Pure data for the rules (authority) and the view (clients):
## `modes/show/shared/tandem/tandem.json` says whether it is on at all (`on`), in which rounds (`rounds`: "race" and "lobby", the lobby yard), whether a lone player gets a buddy
## (`solo_buddy`) and the numbers (`tuning`). The cast may switch it off (`show.tandem.off`) and word it (`show.tandem.name`, `banner`, `line`: team jokes live in the cast; the
## template's own texts here are neutral). Deleting the file, `"on": false` or a round set to false turn it off completely.
const TeamCast := preload("res://style/team_cast.gd")
const PATH := "res://modes/show/shared/tandem/tandem.json"

static var _data: Dictionary = {}
static var _loaded := false

static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary and str(parsed.get("format", "")) == "tandem-1": _data = parsed
	return _data

## True when the experiment is on for `scope` ("race" or "lobby"): the file's `on`, the round's own switch, and the cast not having switched it off.
static func on(scope: String) -> bool:
	var config := data()
	if config.is_empty() or not bool(config.get("on", false)) or bool(TeamCast.show_tandem().get("off", false)): return false
	var rounds: Variant = config.get("rounds", {})
	return rounds is Dictionary and bool((rounds as Dictionary).get(scope, false))

## Alone, a buddy runs up to the player.
static func solo_buddy() -> bool:
	return bool(data().get("solo_buddy", false))

## A tuning number (tandem.json `tuning`).
static func tune(key: String) -> float:
	return float((data().get("tuning", {}) as Dictionary).get(key, 0.0))

## The cast's text, else the template's (`key`: "name", "banner" or "line").
static func text(key: String) -> String:
	var own: Dictionary = TeamCast.show_tandem()
	return str(own[key]) if own.has(key) else str(data().get(key, ""))

## What the others read when two fuse (`line` with {a} and {b} filled in).
static func line(a_name: String, b_name: String) -> String:
	return text("line").replace("{a}", a_name).replace("{b}", b_name).to_upper()

## For tests: forget the loaded file.
static func reset() -> void:
	_loaded = false
	_data = {}
