extends RefCounted
## The game's modes (docs/modes.md). One game shows one mode (AGENTS.md "One game, one mode"): the cast's `mode` picks it.
## "carry" is the painting and balloon run (levels). Every other mode is a minigame played in the lobby yard, in its own
## folder demo/modes/<id>/: rules.gd (shared: the authority and the local game run it), view.gd (client: what players see),
## and its slots in docs/modes/<id>.md. The list, titles and player limits live in modes.json (tools/cast_check.py reads it too).
##
##   Modes.current()            # the cast's mode, "carry" when it names none or an unknown one
##   Modes.is_minigame(id)      # every mode but carry
##   Modes.info(id)             # {title, subtitle, min, max, camera: "first" | "third", dash: bool}
##   Modes.new_rules(id)        # the mode's rules (modes/mode_rules.gd), shared; the views are listed in modes/mode_views.gd (client)
##   Modes.camera()             # the view the current mode plays in: "first" (every mode but the show) or "third" (modes.json `camera`)
##   Modes.dash()               # true when the current mode lets the players dash (modes.json `dash`)
##   Modes.dash_flop()          # true when a dash costs a belly flop and a wall stun (modes.json `dash_flop`, off by default: only the cooldown)
## A new mode: its folder, an entry in modes.json, its rules in RULES here and its view in mode_views.gd.
const TeamCast := preload("res://style/team_cast.gd")
const PATH := "res://modes/modes.json"
const CARRY := "carry"
const RULES := {
	"who_said_it": preload("res://modes/who_said_it/rules.gd"),
	"friend_swap": preload("res://modes/friend_swap/rules.gd"),
	"hot_potato": preload("res://modes/hot_potato/rules.gd"),
	"shove_off": preload("res://modes/shove_off/rules.gd"),
	"show": preload("res://modes/show/rules.gd"),
}

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"modes": {CARRY: {}}}
	return _data

static func ids() -> Array:
	return (data().get("modes", {}) as Dictionary).keys()

static func info(id: String) -> Dictionary:
	var entry: Variant = (data().get("modes", {}) as Dictionary).get(id, {})
	return entry if entry is Dictionary else {}

static func current() -> String:
	var id := TeamCast.mode()
	return id if ids().has(id) else CARRY

## The camera the current mode plays in ("first" unless modes.json says "third": over the shoulder, the own body in view).
static func camera() -> String:
	return "third" if str(info(current()).get("camera", "first")) == "third" else "first"

static func dash() -> bool:
	return bool(info(current()).get("dash", false))

## The dash's belly flop and wall stun are on (modes.json `dash_flop`, default off): the show's dash costs only its cooldown and works in the air.
static func dash_flop() -> bool:
	return bool(info(current()).get("dash_flop", false))

static func is_minigame(id: String) -> bool:
	return id != CARRY and ids().has(id)

static func min_players(id: String) -> int:
	return int(info(id).get("min", 2))

static func new_rules(id: String) -> RefCounted:
	return (RULES[id] as GDScript).new() if RULES.has(id) else null

## The rank (1-based, best first) of each of `count` slots for a rules' results(): its own `order` (slots, best first) when it has one, else the scores (a tie shares its rank). Slots the
## order does not name come after it by score. Index = slot.
static func ranks(outcome: Dictionary, count: int) -> Array:
	var scores: Array = outcome.get("scores", [])
	var order: Array = []
	for slot: Variant in (outcome.get("order", []) as Array):
		if int(slot) >= 0 and int(slot) < count and not order.has(int(slot)): order.append(int(slot))
	var result: Array = []
	result.resize(count)
	for index in order.size(): result[order[index]] = index + 1
	var rest: Array = range(count).filter(func(slot: int) -> bool: return not order.has(slot))
	rest.sort_custom(func(a: int, b: int) -> bool:
		var score_a := int(scores[a]) if a < scores.size() else 0
		var score_b := int(scores[b]) if b < scores.size() else 0
		return score_a > score_b or (score_a == score_b and a < b))
	for index in rest.size():
		var slot: int = rest[index]
		var better := 0
		for other: int in rest:
			if (int(scores[other]) if other < scores.size() else 0) > (int(scores[slot]) if slot < scores.size() else 0): better += 1
		result[slot] = order.size() + (better + 1 if order.is_empty() else index + 1)
	return result
