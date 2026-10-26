extends RefCounted
## EXPERIMENT (switchable): THE MANAGER. The rules' ids, defaults and the cast's overrides, shared by the authority (manager_rules.gd) and the clients (manager_view.gd): pure data, no nodes.
## The defaults and the switch are `manager.json` next to this file (`"on": false` there, or deleting it, turns it off for every round); a cast's `show.manager`
## (style/team_cast.gd show_manager) changes the words and the lengths, or takes the manager (`off`) or single rules out of its show. The order of `order` in the json is the wire's:
## the state carries a rule as an index into it.
const TeamCast := preload("res://style/team_cast.gd")

const PATH := "res://modes/show/shared/manager/manager.json"
const FORMAT := "manager-1"
const CHOICES := 3 ## rules offered at a time

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = parsed if parsed is Dictionary and str((parsed as Dictionary).get("format", "")) == FORMAT else {"on": false}
	return _data

## True when the manager plays in `level` (the level's index, file number - 1) of a round of `kind` ("race" | "final" | "survival"): the file's `on`, then its `rounds` by kind,
## then its `levels` by file number (a level entry wins), and the cast does not take it out.
static func on_for(level: int, kind: String) -> bool:
	var file := data()
	if not bool(file.get("on", false)) or bool(TeamCast.show_manager().get("off", false)): return false
	var by_kind: Variant = (file.get("rounds", {}) as Dictionary).get(kind)
	var on: bool = by_kind is Dictionary and bool((by_kind as Dictionary).get("on", false))
	var by_level: Variant = (file.get("levels", {}) as Dictionary).get(str(level + 1))
	if by_level is Dictionary and (by_level as Dictionary).has("on"): on = bool((by_level as Dictionary).get("on"))
	return on

## Every rule id in the wire's order.
static func order() -> Array:
	var value: Variant = data().get("order", [])
	return value if value is Array else []

## The rules this show offers: the order, minus the ones the cast switched off.
static func offered() -> Array:
	return order().filter(func(id: String) -> bool: return not off(id))

static func index(id: String) -> int:
	return order().find(id)

static func id_of(kind: int) -> String:
	var ids := order()
	return str(ids[kind]) if kind >= 0 and kind < ids.size() else ""

static func spec(id: String) -> Dictionary:
	var value: Variant = (data().get("rules", {}) as Dictionary).get(id, {})
	return value if value is Dictionary else {}

static func off(id: String) -> bool:
	return bool(((TeamCast.show_manager().get("rules", {}) as Dictionary).get(id, {}) as Dictionary).get("off", false))

## A timing number of the file (`first`, `every`: [min, max]; `prompt`, `bot`, `lead`, `solo_lead`, `intro`: seconds).
static func timing(key: String) -> Variant:
	return (data().get("timing", {}) as Dictionary).get(key, 0.0)

## One of the manager's words: the cast's, else the template's (`title`, `line`, `you`, `prompt`, `waiting`, `made`). `{manager}` stands for the manager's name.
static func text(key: String, manager_name := "") -> String:
	var own: Dictionary = TeamCast.show_manager()
	var words := str(own[key]) if own.has(key) else str((data().get("texts", {}) as Dictionary).get(key, ""))
	return words.replace("{manager}", manager_name).to_upper()

## A word of rule `id` (`name`, `banner`, `line`): the cast's entry, else the template's; the line falls back to the common `made` text.
static func rule_text(id: String, key: String, manager_name := "") -> String:
	var own: Dictionary = (TeamCast.show_manager().get("rules", {}) as Dictionary).get(id, {})
	var words := str(own[key]) if own.has(key) else str(spec(id).get(key, ""))
	if words == "" and key == "line": words = text("made", manager_name)
	return words.replace("{manager}", manager_name).to_upper()

## How long rule `id` lasts, s: the cast's `tuning.duration` clamped to 3..30, else a random draw of the rule's own range.
static func duration(id: String, rng: RandomNumberGenerator) -> float:
	var own: Dictionary = ((TeamCast.show_manager().get("rules", {}) as Dictionary).get(id, {}) as Dictionary).get("tuning", {})
	if own.has("duration"): return clampf(float(own.duration), 3.0, 30.0)
	var range_s: Variant = spec(id).get("duration", [12.0, 12.0])
	return rng.randf_range(float((range_s as Array)[0]), float((range_s as Array)[1])) if range_s is Array and (range_s as Array).size() == 2 else 12.0

## The courier mods of rule `id` (game/game_run.gd slot_mods): {invert, gravity, no_jump, no_dash, speed, ice}, {} for a rule that only scales or turns the camera.
static func mods(id: String) -> Dictionary:
	var value: Variant = spec(id).get("mods", {})
	return value if value is Dictionary else {}

## The rig scale of rule `id` (Vector3.ONE for none).
static func scale_of(id: String) -> Vector3:
	var value: Variant = spec(id).get("scale")
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and (value as Array).size() == 3 else Vector3.ONE

## The camera roll of rule `id` in radians (0 for none): the local camera of everybody under the rule is turned by it.
static func camera_roll(id: String) -> float:
	return float((spec(id).get("camera", {}) as Dictionary).get("roll", 0.0))
