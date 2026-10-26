class_name CharacterCatalog
extends RefCounted
## The character catalog: the body, the colour palettes and every wearable item, read from demo/character/catalog.json.
## Static, read once. Shared by the rig, the wardrobe and the saved looks; it never loads a model itself.
##
##   CharacterCatalog.data()            # the whole file (format character-catalog-v1)
##   CharacterCatalog.slots()           # item slots in display order: head, hat, hair, eyes, eyelids, brows, nose, mouth, ears, shirt, hand
##   CharacterCatalog.items("hat")      # the items of one slot that can be shown, in file order (see "Art lookup")
##   CharacterCatalog.items_for("nose", "head_frog")   # the items of a slot that fit a head (item field "heads", missing = all)
##   CharacterCatalog.params()          # the sliders: [{id, label, group, min, max, ...}] (see below); param_ids() their ids
##   CharacterCatalog.item("hat_cap")   # one item, {} when unknown
##   CharacterCatalog.palette("main")   # colours of a palette; the first 12 "main" colours are the website palette (index 0..11)
##   CharacterCatalog.color_slots()     # skin, shirt, pants, shoes
##   CharacterCatalog.resolve(file)     # the res:// path to load for a catalog file (see below), "" when there is none
##
## Item fields: id, slot, name, mode, file, default; `award` (an item that is won, not picked: see awards()); `bone` for attach items; optional `offset` [x, y, z] and `rotate`
## [x, y, z] (degrees; `yaw` alone also works) and `upright` (stays upright in the world: a balloon) for attach items; `print` ("team": the team shirt, white with the player's colour on the sleeve ends and collar, the team logo and motto on the chest, or the cast's shirt_print.png when there is one) for shirts; `heads` (ids of the heads the item fits, missing = all);
## `hides` (body mesh names hidden while the item is worn: outfits); `chest` [x, y, scale] on outfits: the team shirt's chest
## print (logo, motto or shirt_print.png) moved by x, y (shirt uv) and scaled around its centre, so the outfit's own parts (a
## hoodie's cords) never cover it; scale 0 = the outfit covers the chest (overalls' bib), no chest print; `skin` on heads (the skin palette index that suits it); `hair_place` [x, y, z, scale] on heads: hair items on that
## head moved (body units, in its HatSocket's space) and scaled so the fringe stays above the eyes.
## Hats and hair sit on the head's `HatSocket` node (a Node3D in the head model, usually under ORG_jaw_upper), else on
## ORG_jaw_upper, raised by `hat_fallback` (body units) to the crown of a head without a socket. A hat surface whose
## material is named "logo" shows the team logo.
## Colours: every surface whose material is named after a colour slot (skin, shirt, pants, shoes) takes that colour, on
## the body, the head and skinned items; `body_parts` names the body meshes of each slot (a list of candidate names, the
## first one the body has wins) for bodies whose materials are named otherwise. The character is scaled to 1.8 m with its
## head: a head mesh in the body is measured with it, else the default head's model on top of the body, else the body is
## taken as `body_height` units tall.
##
## Params (sliders, CharacterLook.params: id -> -1..1, 0 = as modelled). A value v scales by lerp(1, max, v) for v > 0 and
## lerp(1, min, -v) for v < 0. Kinds: `bones` + `axes` (x sideways, y up, z forward, in the body's rest space) scale those
## bones after the animation (`lift`: "body" raises the body over longer legs, "head" raises the head by `lift_by` per unit
## of scale); `parts` + `deform` ("scale" around each part's centre, `split` left/right; "spread": min/max are offsets
## outwards in body units) reshape face part meshes; `target` "hat" scales the hat (`special` "tilt": min/max in radians);
## `special` "wobble" | "bounce" | "swagger" scale small procedural motions. `bone_follow` [bone, anchor] pairs move the
## loose bones of the body (arms, hands, feet, head) with the bone they sit on when that one is scaled.
## Modes: "attach" (a model on the bone: hats and hair are authored upright with their origin at the head bone `ORG_jaw_upper`,
## hand items with the handle at their origin), "skinned" (a mesh skinned to the body skeleton in its rest pose; replaces the
## body part of the slot, hats and hair are added), "texture" (a picture on the body part: eyes, shirt print).
## An item `file` of "" is the body's own part (eyes, eyelids, brows, nose, mouth, ears) or no print (shirt).
## The empty item id "" in a look means nothing in that slot: no hat, no nose, ...; eyes and shirt fall back to the body's own.
##
## First person (`first_person`, the rig's set_first_person): where the view arms sit in front of the own camera. Points are
## [right, up, forward] metres from the camera: `shoulders` (between the view arms' shoulders), per pose and side
## (`idle`, `held` for the hand holding an item, `air` while jumping or falling, `carry` when the game gives no grips; each
## {"left": ..., "right": ...}) the palm `hand`, the point the `elbow` bends towards and an optional hand `turn` [x, y, z]
## (degrees about the camera's axes, at the wrist); `carry` also has `from` per side (where the arm comes from, below the
## view, so only the hands and forearms show over the painting), its own `scale` and `stretch` (the arm and forearm that
## many times longer, so a slim arm still reaches from below the view); `slap` sweeps the slapping palm `from` -> `to`
## (right hand; the left mirrors it) in `seconds`. `scale` sizes the view arms against the body, `hand_scale` the hands on
## top; `lag` (1/s) is how fast they follow camera turns, `bob` [side, down] metres per walking step, `sway` [metres, speed]
## the idle drift.
##
## Art lookup: `body` and item files are paths inside demo/character/models/ (our art, e.g. "items/hat_cap.glb"); always load
## them through resolve(). Nothing else is ever used in their place. An item whose file is not there is left out of items(),
## default_item() and random looks (left_out() lists them), so the customizer never shows an item that renders nothing. Looks and their bytes use every catalog item (all_items(); item() knows them all), so a client with the art
## and an authority without it agree.
## No people: the game shows animal and bean heads only. The catalog key `people_heads` lists head ids that read as a person
## (a skin-toned head on a person-shaped body, `head_human` which is not an item, `head_potato`); they are left out like
## items without art, and a look that names one (a cast, a saved look, another client) is dressed in the seat's animal
## instead (CharacterLook, seat_head()).
## Without a body model the game keeps the courier rig.
## models/ is a run-time payload of the client (named by a soft token below for tools/build_domain_graph.py).
const PATH := "res://character/catalog.json"
const TeamCast := preload("res://style/team_cast.gd")
const CAST_SHIRT := "shirt_print" ## demo/cast/shirt_print.png (.jpg, .webp): printed on the team shirt instead of logo and motto
const FORMAT := "character-catalog-v1"
const MODELS_DIR := "res" + "://character/models/"

static var _data: Dictionary = {}
static var _loaded := false
static var _by_id: Dictionary = {}
static var _by_slot: Dictionary = {}
static var _palettes: Dictionary = {}
static var _left_out: Array = []
static var _all_by_slot: Dictionary = {}
static var _awards_by_slot: Dictionary = {}

static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if parsed is Dictionary and str(parsed.get("format", "")) == FORMAT:
			_data = parsed
		else:
			push_error("Character catalog missing or not %s: %s" % [FORMAT, PATH])
			_data = {"format": FORMAT, "body": "", "palettes": {}, "color_slots": [], "slots": [], "items": []}
		_index()
	return _data

static func _index() -> void:
	_by_id.clear()
	_by_slot.clear()
	_palettes.clear()
	_left_out.clear()
	_all_by_slot.clear()
	_awards_by_slot.clear()
	for slot in _data.get("slots", []):
		var list: Array[Dictionary] = []
		_by_slot[str(slot)] = list
		var all: Array[Dictionary] = []
		_all_by_slot[str(slot)] = all
		var won: Array[Dictionary] = []
		_awards_by_slot[str(slot)] = won
	for entry in _data.get("items", []):
		if not (entry is Dictionary) or str(entry.get("id", "")) == "": continue
		var slot := str(entry.get("slot", ""))
		if not _by_slot.has(slot):
			push_warning("Character item %s has an unknown slot %s" % [entry["id"], slot])
			continue
		_by_id[str(entry["id"])] = entry
		(_all_by_slot[slot] as Array[Dictionary]).append(entry)
		var missing := str(entry.get("file", "")) != "" and resolve(str(entry["file"])) == ""
		if missing or is_people(str(entry["id"])):
			_left_out.append(str(entry["id"])) # its art is not there (yet), or it reads as a person: never offered
			continue
		if str(entry.get("award", "")) != "":
			(_awards_by_slot[slot] as Array[Dictionary]).append(entry) # won, not picked: the wardrobe offers it once its owner has it (awards())
			continue
		(_by_slot[slot] as Array[Dictionary]).append(entry)

static func slots() -> Array:
	return data().get("slots", [])

## Ids of catalog items left out because their file is missing or they are people heads.
static func left_out() -> Array:
	data()
	return _left_out

## Head ids the game never wears because they read as a person (catalog "people_heads").
static func people_heads() -> Array:
	return data().get("people_heads", [])

## True for a head id that reads as a person (an id of the people list, or any `head_human*`).
static func is_people(id: String) -> bool:
	return id.begins_with("head_human") or people_heads().has(id)

static func color_slots() -> Array:
	return data().get("color_slots", [])

static func items(slot: String) -> Array[Dictionary]:
	data()
	var none: Array[Dictionary] = []
	return _by_slot.get(slot, none)

## The award items of `slot` (item field `award`: the name of what won it, "crown"): wearable like any item and part of every look and its bytes, but never a
## default, never random and not in items(); the wardrobe lists one only for a player who has won it or wears it (CharacterLook.has_award()).
static func awards(slot: String) -> Array[Dictionary]:
	data()
	var none: Array[Dictionary] = []
	return _awards_by_slot.get(slot, none)

## The award item `id` is (its `award` name), "" for an ordinary item.
static func award_of(id: String) -> String:
	return str(item(id).get("award", ""))

## Every catalog item of `slot`, art or not (look bytes index into this list).
static func all_items(slot: String) -> Array[Dictionary]:
	data()
	var none: Array[Dictionary] = []
	return _all_by_slot.get(slot, none)

static func item(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})

## The default item of `slot` ("" when the slot has none). A head is never empty while any head model is there: without
## the default head's model the first head that has one.
static func default_item(slot: String) -> String:
	for entry in items(slot):
		if bool(entry.get("default", false)): return str(entry["id"])
	return str(items(slot)[0]["id"]) if slot == "head" and not items(slot).is_empty() else ""

## True when `entry` can be worn with the head `head_id` (its "heads" list, missing = every head).
static func fits(entry: Dictionary, head_id: String) -> bool:
	var heads = entry.get("heads")
	return not (heads is Array) or head_id == "" or head_id in heads

## The items of `slot` that fit the head `head_id`.
static func items_for(slot: String, head_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in items(slot):
		if fits(entry, head_id): result.append(entry)
	return result

## The slider definitions, in display order.
static func params() -> Array:
	return data().get("params", [])

static func param_ids() -> Array:
	return params().map(func(entry: Dictionary) -> String: return str(entry.get("id", "")))

static func param(id: String) -> Dictionary:
	for entry in params():
		if str(entry.get("id", "")) == id: return entry
	return {}

## The factor (or angle, for "tilt") a slider value gives: 1 at 0, `min` at -1, `max` at +1.
static func param_factor(entry: Dictionary, value: float) -> float:
	var base := 0.0 if str(entry.get("special", "")) == "tilt" or str(entry.get("deform", "")) == "spread" else 1.0
	var v := clampf(value, -1.0, 1.0)
	return lerpf(base, float(entry.get("max", base)), v) if v >= 0.0 else lerpf(base, float(entry.get("min", base)), -v)

static func palette(name: String) -> PackedColorArray:
	data()
	if not _palettes.has(name):
		var colors := PackedColorArray()
		for value in (_data.get("palettes", {}) as Dictionary).get(name, []):
			if value is String and Color.html_is_valid(value): colors.append(Color.html(value))
		_palettes[name] = colors
	return _palettes[name]

## The palette a colour slot picks from ("skin" -> "skin", everything else "main").
static func palette_for(color_slot: String) -> PackedColorArray:
	return palette(str((data().get("color_palettes", {}) as Dictionary).get(color_slot, "main")))

## The colour of `color_slot` at palette `index` (wraps; the first colour when the palette is empty or missing).
static func color(color_slot: String, index: int) -> Color:
	var colors := palette_for(color_slot)
	if colors.is_empty(): return Color.WHITE
	return colors[posmod(index, colors.size())]

## The palette index closest to `target` (perceived distance), for team colours that are not in the palette.
static func nearest(color_slot: String, target: Color) -> int:
	var colors := palette_for(color_slot)
	var best := 0
	var best_d := INF
	for i in colors.size():
		var c := colors[i]
		var mean_r := (c.r + target.r) * 0.5
		var d := (2.0 + mean_r) * pow(c.r - target.r, 2) + 4.0 * pow(c.g - target.g, 2) + (3.0 - mean_r) * pow(c.b - target.b, 2)
		if d < best_d:
			best_d = d
			best = i
	return best

static func body_path() -> String:
	return resolve(str(data().get("body", "")))

## The res:// path to load for a catalog file (our art under models/), "" when it is not there.
static func resolve(file: String) -> String:
	if file == "": return ""
	var path := file if file.begins_with("res:") else MODELS_DIR + file
	return path if ResourceLoader.exists(path) else ""

## The file name of the cast's team shirt picture in demo/cast/ (shirt_print.png, .jpg or .webp), "" without one.
static func cast_shirt() -> String:
	for ending in ["png", "jpg", "jpeg", "webp"]:
		var path: String = TeamCast.PICTURE_DIR + CAST_SHIRT + "." + ending
		if ResourceLoader.exists(path) or FileAccess.file_exists(path): return CAST_SHIRT + "." + ending
	return ""

## The cast's team shirt picture, null without one (loaded like every cast picture, also before the editor imports it).
static func cast_shirt_picture() -> Texture2D:
	var file := cast_shirt()
	return TeamCast._load(file) as Texture2D if file != "" else null

## The head a seat starts with (catalog "seat_heads", cycling; the first one whose model is there), "" for none.
static func seat_head(seat: int) -> String:
	var order: Array = data().get("seat_heads", [])
	for step in order.size():
		var id := str(order[(maxi(seat, 0) + step) % order.size()])
		if items("head").any(func(entry: Dictionary) -> bool: return str(entry["id"]) == id): return id
	return default_item("head")

## Body part names and clip names of the body model (catalog keys body_parts and clips).
static func body_parts() -> Dictionary:
	return data().get("body_parts", {})

## The mesh names a body_parts key may name (a name or a list of candidate names).
static func body_part_names(key: String) -> Array:
	var value = body_parts().get(key, [])
	if value is String: return [] if value == "" else [value]
	return value if value is Array else []

static func clip(role: String) -> String:
	return str((data().get("clips", {}) as Dictionary).get(role, ""))

## Emote names (dance, sit, yes, no, point, think, cry) -> {loop: bool, seconds: float (optional), mouth: [open, swing, hz]}.
static func emotes() -> Dictionary:
	return data().get("emotes", {})
