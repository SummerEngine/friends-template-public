extends RefCounted
## The show's items and events: ids, defaults and the cast's overrides (docs/items.md). Shared by the rules (authority) and the view (clients): pure data, no nodes.
## The ids and their order are the wire's: the state carries an item or an effect as an index into KINDS.
##   Catalog.KINDS       smash, call, flip, glitch, dance (items a player picks up and uses), boost, soar (events that happen to a player), eggplant (the experiment's cursed parcel:
##                       its own clock, hot_eggplant.json; never rolled by a box and never an event of the clock, so it is in neither HELD nor EVENTS)
##   Catalog.text(id, "banner")      the cast's show.items[] text, else the template's (items.json)
##   Catalog.tuning(id, "duration")  the cast's number clamped to its range, else the default
##   Catalog.weights(id)             the roll weights by race position: [leader, middle, last]
const TeamCast := preload("res://style/team_cast.gd")

const KINDS := ["smash", "call", "flip", "glitch", "dance", "boost", "soar", "eggplant"]
const HELD := ["smash", "call", "flip", "glitch", "dance"] ## what a box rolls
const EVENTS := ["boost", "soar"] ## what the clock hands out to a runner at the back
const PATH := "res://modes/show/items/items.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"items": {}, "box": {}, "event": {}}
	return _data

static func index(id: String) -> int:
	return KINDS.find(id)

static func id_of(kind: int) -> String:
	return str(KINDS[kind]) if kind >= 0 and kind < KINDS.size() else ""

static func box(key: String) -> float:
	return float((data().get("box", {}) as Dictionary).get(key, 0.0))

static func event(key: String) -> Array:
	var value: Variant = (data().get("event", {}) as Dictionary).get(key, [])
	return value if value is Array else []

static func _item(id: String) -> Dictionary:
	var value: Variant = (data().get("items", {}) as Dictionary).get(id, {})
	return value if value is Dictionary else {}

## True when the cast takes this id out of the show (show.items[] with "off": true).
static func off(id: String) -> bool:
	return bool(TeamCast.show_item(id).get("off", false))

## `key` of `id`: "name", "banner", "line" (the line keeps {user} and {victim}: `line` fills them) or, for the eggplant, "pass" and "pop".
static func text(id: String, key: String) -> String:
	var own: Dictionary = TeamCast.show_item(id)
	if own.has(key): return str(own[key])
	return str(_item(id).get(key, ""))

## The line `id` tells the others ("{user} ..." with the names filled in, upper case); `key` is another sentence of the item that names players (the eggplant's "pass").
static func line(id: String, user: String, victim: String, key := "line") -> String:
	return text(id, key).replace("{user}", user).replace("{victim}", victim).to_upper()

## The tuning number `key` of `id`: the cast's, clamped to the range in items.json, else the default.
static func tuning(id: String, key: String) -> float:
	var spec: Dictionary = ((_item(id).get("tuning", {}) as Dictionary).get(key, {}) as Dictionary)
	if spec.is_empty(): return 0.0
	var own: Dictionary = (TeamCast.show_item(id).get("tuning", {}) as Dictionary)
	var value := float(own.get(key, spec.default))
	return clampf(value, float(spec.min), float(spec.max))

## The roll weights of `id` at the leader, mid-field and last place (an item with no weights is never rolled).
static func weights(id: String) -> Array:
	var value: Variant = _item(id).get("weights", [])
	return value if value is Array and (value as Array).size() == 3 else [0.0, 0.0, 0.0]

## The roll weight of `id` for the racer at `rank` (0 = leading) of `racers`: the three weights, blended along the field.
static func weight_at(id: String, rank: int, racers: int) -> float:
	var w := weights(id)
	var f := 0.0 if racers <= 1 else clampf(float(rank) / float(racers - 1), 0.0, 1.0)
	return lerpf(float(w[0]), float(w[1]), f * 2.0) if f < 0.5 else lerpf(float(w[1]), float(w[2]), (f - 0.5) * 2.0)

## The cast's voice clip of `id` (show.items[].voice under demo/cast/items/), null for none (voices are optional: the banner is the item's announcement).
static func voice(id: String) -> AudioStream:
	var file := str(TeamCast.show_item(id).get("voice", ""))
	return TeamCast.item_file(file) as AudioStream if file != "" else null

## The cast's own sound of `id` (show.items[].sfx), null for none: the template's own sound then plays.
static func sfx(id: String) -> AudioStream:
	var file := str(TeamCast.show_item(id).get("sfx", ""))
	return TeamCast.item_file(file) as AudioStream if file != "" else null

## The cast's media of `id` as a res:// path (show.items[].media, an .ogv), "" for none.
static func media(id: String) -> String:
	var file := str(TeamCast.show_item(id).get("media", ""))
	return str(TeamCast.item_file(file)) if file != "" else ""
