extends RefCounted
## GHOST PIGEON (EXPERIMENT, switchable, docs/pigeon.md): the switch, the texts and the tuning. Shared by the rules (authority, local game) and the view (clients): pure data, no nodes.
##   PigeonCatalog.on(kind)        true when the experiment is on for a round kind ("race" | "survival" | "final"): pigeon.json `on` and `rounds`, and the cast does not say show.pigeon.off
##   PigeonCatalog.text("banner")  the cast's show.pigeon text, else the template's neutral one (pigeon.json `texts`): banner, coo, splat, line, drop_line
##   PigeonCatalog.tune("speed")   the cast's show.pigeon.tuning number clamped to its range, else the default (pigeon.json `tuning`)
const TeamCast := preload("res://style/team_cast.gd")

const PATH := "res://modes/show/shared/pigeon/pigeon.json"
const FORMAT := "ghost-pigeon-1"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary and str(parsed.get("format", "")) == FORMAT else {"on": false}
	return _data

## True when the pigeons play in a round of `kind`.
static func on(kind: String) -> bool:
	var config := data()
	if not bool(config.get("on", false)) or bool(TeamCast.show_pigeon().get("off", false)): return false
	var rounds: Variant = config.get("rounds", {})
	return rounds is Dictionary and bool((rounds as Dictionary).get(kind, false))

## `key` of the texts (the cast's show.pigeon, else pigeon.json). The lines keep {user} and {victim}: `line` fills them.
static func text(key: String) -> String:
	var own: Dictionary = TeamCast.show_pigeon()
	if own.has(key): return str(own[key])
	return str((data().get("texts", {}) as Dictionary).get(key, ""))

## The line `key` ("line" | "drop_line") with the names filled in, upper case.
static func line(key: String, user: String, victim := "") -> String:
	return text(key).replace("{user}", user).replace("{victim}", victim).to_upper()

## The tuning number `key`: the cast's, clamped to the range in pigeon.json, else the default.
static func tune(key: String) -> float:
	var spec: Dictionary = ((data().get("tuning", {}) as Dictionary).get(key, {}) as Dictionary)
	if spec.is_empty(): return 0.0
	var own: Dictionary = (TeamCast.show_pigeon().get("tuning", {}) as Dictionary)
	return clampf(float(own.get(key, spec.default)), float(spec.min), float(spec.max))
