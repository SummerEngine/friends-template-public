class_name CharacterLook
extends RefCounted
## One character's look: a palette index per colour slot, an item id per item slot and a value per slider (ids from
## CharacterCatalog; params are -1..1, 0 = as modelled, kept at int8 steps so bytes and saves round-trip exactly).
## Plain data; the rig applies it (character_rig.gd set_look), the wardrobe edits it, saves keep it in user://look.cfg.
##
##   var look := CharacterLook.load_saved(seat)      # the saved look of a local seat, else the seat's default look
##   look.colors["shirt"] = 3; look.items["hat"] = "hat_beanie"; look.save(seat)
##   var bytes := look.to_bytes()                     # compact form for the network (same catalog on both ends)
##
## "" as an item id means nothing in that slot. Unknown slots, unknown ids and ids of the wrong slot are dropped when a look is
## read (from_dict, from_bytes, load_saved), and missing slots get their catalog default. fitted() swaps face items that do
## not fit the chosen head for ones that do.
const Catalog := preload("res://character/catalog.gd")
const TeamCast := preload("res://style/team_cast.gd")
const SAVE_PATH := "user://look.cfg"
const BYTES_VERSION := 2
## Slots that may stay empty when randomizing (a face always gets its parts).
const OPTIONAL_SLOTS := ["hat", "hair", "hand", "shirt"]
const RANDOM_PARAM_SPREAD := 0.45 ## randomized params: normal spread around 0 (most stay moderate, a few go far)

var colors := {} ## color slot -> palette index
var items := {} ## slot -> item id or ""
var params := {} ## param id -> -1..1 (missing = 0)

## A slider value as stored: clamped to -1..1, on int8 steps.
static func step(value: float) -> float:
	return roundf(clampf(value, -1.0, 1.0) * 127.0) / 127.0

func param(id: String) -> float:
	return float(params.get(id, 0.0))

func set_param(id: String, value: float) -> void:
	if Catalog.param(id).is_empty(): return
	var v := step(value)
	if v == 0.0: params.erase(id)
	else: params[id] = v

## The look a seat starts with: the cast's pick for the seat (players[i].look: catalog slot -> item id, "" = nothing in that
## slot; ids of another slot, unknown ids and items whose art is not here are skipped), else an animal head by seat (catalog
## "seat_heads": frog, bear, bird, cat, fish, bean, cycling) and catalog defaults for the rest. The head brings its own
## skin colour; the cast's colour for this seat goes on the shirt (nearest palette entry). A cast that names a people head
## (Catalog.people_heads(), `head_human*`) gets the seat's animal: always the same one for the same seat.
static func defaults_for_seat(seat: int) -> CharacterLook:
	var look := CharacterLook.new()
	var defaults: Dictionary = Catalog.data().get("color_defaults", {})
	for slot in Catalog.color_slots():
		look.colors[slot] = int(defaults.get(slot, 0))
	var member: Dictionary = TeamCast.player(seat)
	look.colors["shirt"] = Catalog.nearest("shirt", member["color"])
	look.colors["skin"] = Catalog.nearest("skin", member["skin"])
	var chosen: Dictionary = member["look"]
	for slot in Catalog.slots():
		var id := str(chosen.get(slot, "-"))
		look.items[slot] = id if _shown(slot, id) or (id == "" and slot != "head") else Catalog.default_item(slot)
	var head := str(look.items["head"]) if _shown("head", str(chosen.get("head", ""))) else Catalog.seat_head(seat)
	if head != "":
		look.items["head"] = head
		var skin = Catalog.item(head).get("skin")
		if skin is int or skin is float: look.colors["skin"] = int(skin)
	return look.fitted()

## True when `id` is an item of `slot` whose art is here (one Catalog.items(slot) shows).
static func _shown(slot: String, id: String) -> bool:
	return id != "" and str(Catalog.item(id).get("slot", "")) == slot and not Catalog.left_out().has(id)

func randomized(rng: RandomNumberGenerator) -> CharacterLook:
	var look := CharacterLook.new()
	for slot in Catalog.color_slots():
		look.colors[slot] = rng.randi_range(0, maxi(Catalog.palette_for(slot).size() - 1, 0))
	for slot in Catalog.slots():
		var choices: Array = Catalog.items(slot).map(func(entry: Dictionary) -> String: return str(entry["id"]))
		if slot in OPTIONAL_SLOTS: choices.append("")
		look.items[slot] = choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else ""
	look.params = _random_params(rng)
	return look.fitted()

## This look with new random slider values (colours and items kept).
func randomized_params(rng: RandomNumberGenerator) -> CharacterLook:
	var look := duplicate_look()
	look.params = _random_params(rng)
	return look

static func _random_params(rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for id in Catalog.param_ids():
		var v := step(rng.randfn(0.0, RANDOM_PARAM_SPREAD))
		if v != 0.0: result[id] = v
	return result

## This look with every face item that does not fit its head swapped for the slot's first fitting item (the default if it
## fits), or nothing when no item of the slot fits.
func fitted() -> CharacterLook:
	var look := duplicate_look()
	var head := str(items.get("head", ""))
	for slot in Catalog.slots():
		var id := str(look.items.get(slot, ""))
		if id == "" or Catalog.fits(Catalog.item(id), head): continue
		var choices := Catalog.items_for(slot, head)
		var fallback := Catalog.default_item(slot)
		look.items[slot] = fallback if fallback != "" and Catalog.fits(Catalog.item(fallback), head) else (str(choices[0]["id"]) if not choices.is_empty() else "")
	return look

## This look with a people head (Catalog.people_heads()) swapped for `seat`'s animal and its skin colour; any other look as it is.
func animal_only(seat: int) -> CharacterLook:
	var head := str(items.get("head", ""))
	if not Catalog.is_people(head): return self
	var look := duplicate_look()
	var animal := Catalog.seat_head(seat)
	look.items["head"] = animal
	var skin = Catalog.item(animal).get("skin")
	if skin is int or skin is float: look.colors["skin"] = int(skin)
	return look.fitted()

func duplicate_look() -> CharacterLook:
	var look := CharacterLook.new()
	look.colors = colors.duplicate()
	look.items = items.duplicate()
	look.params = params.duplicate()
	return look

func equals(other: CharacterLook) -> bool:
	return other != null and colors == other.colors and items == other.items and params == other.params

func to_dict() -> Dictionary:
	return {"colors": colors.duplicate(), "items": items.duplicate(), "params": params.duplicate()}

## `seat` is the player's seat: a people head in `d` (another client, a saved look) becomes that seat's animal.
static func from_dict(d: Dictionary, seat: int = 0) -> CharacterLook:
	var look := CharacterLook.new()
	var defaults: Dictionary = Catalog.data().get("color_defaults", {})
	var in_colors = d.get("colors", {})
	var in_items = d.get("items", {})
	if not (in_colors is Dictionary): in_colors = {}
	if not (in_items is Dictionary): in_items = {}
	for slot in Catalog.color_slots():
		var size := Catalog.palette_for(slot).size()
		var value = in_colors.get(slot, defaults.get(slot, 0))
		look.colors[slot] = clampi(int(value), 0, maxi(size - 1, 0)) if (value is int or value is float) else int(defaults.get(slot, 0))
	for slot in Catalog.slots():
		var id = in_items.get(slot, null)
		if slot == "head" and id is String and Catalog.is_people(id): look.items[slot] = id # animal_only() below dresses the seat's animal
		else: look.items[slot] = _checked_item(slot, id) if id is String else Catalog.default_item(slot)
	var in_params = d.get("params", {})
	if in_params is Dictionary:
		for id in in_params:
			var value = in_params[id]
			if value is int or value is float: look.set_param(str(id), float(value))
	return look.animal_only(seat)

static func _checked_item(slot: String, id: String) -> String:
	if id == "": return ""
	var entry := Catalog.item(id)
	return id if not entry.is_empty() and str(entry.get("slot", "")) == slot else Catalog.default_item(slot)

## [version, colour count, colour indices..., slot count, per slot: item index in its slot + 1 (0 = nothing), param count,
## per param (catalog order): int8 round(value * 127)]. Both ends must run the same catalog (same build); a look that is not
## valid_bytes() gives the defaults of its seat (from_bytes' `seat`, 0 without one).
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray([BYTES_VERSION])
	var color_slots := Catalog.color_slots()
	out.append(color_slots.size())
	for slot in color_slots: out.append(clampi(int(colors.get(slot, 0)), 0, 255))
	var slots := Catalog.slots()
	out.append(slots.size())
	for slot in slots:
		var id := str(items.get(slot, ""))
		var index := 0
		if id != "":
			var list := Catalog.all_items(slot)
			for i in list.size():
				if str(list[i]["id"]) == id:
					index = i + 1
					break
		out.append(clampi(index, 0, 255))
	var ids := Catalog.param_ids()
	out.append(ids.size())
	for id in ids:
		out.append(roundi(param(id) * 127.0) & 0xFF)
	return out

## The exact byte length of a look for this catalog.
static func byte_size() -> int:
	return 4 + Catalog.color_slots().size() + Catalog.slots().size() + Catalog.param_ids().size()

## Size and ranges only (what the authority checks before it stores and relays a look).
static func valid_bytes(b: PackedByteArray) -> bool:
	var color_slots := Catalog.color_slots()
	var slots := Catalog.slots()
	if b.size() != byte_size() or b[0] != BYTES_VERSION or b[1] != color_slots.size(): return false
	for i in color_slots.size():
		if b[2 + i] >= Catalog.palette_for(color_slots[i]).size(): return false
	var at := 2 + color_slots.size()
	if b[at] != slots.size(): return false
	for i in slots.size():
		if b[at + 1 + i] > Catalog.all_items(slots[i]).size(): return false
	at += 1 + slots.size()
	return b[at] == Catalog.param_ids().size() and not b.slice(at + 1).has(0x80) # -128 is outside -127..127

static func from_bytes(b: PackedByteArray, seat: int = 0) -> CharacterLook:
	if not valid_bytes(b): return defaults_for_seat(seat)
	var color_slots := Catalog.color_slots()
	var slots := Catalog.slots()
	var d := {"colors": {}, "items": {}, "params": {}}
	for i in color_slots.size(): d["colors"][color_slots[i]] = int(b[2 + i])
	var at := 3 + color_slots.size()
	for i in slots.size():
		var index := int(b[at + i])
		var list := Catalog.all_items(slots[i])
		d["items"][slots[i]] = str(list[index - 1]["id"]) if index > 0 and index <= list.size() else ""
	at += slots.size() + 1
	var ids := Catalog.param_ids()
	for i in ids.size():
		var raw := int(b[at + i])
		if raw >= 128: raw -= 256
		if raw != 0: d["params"][ids[i]] = raw / 127.0
	return from_dict(d, seat)

# ------------------------------------------------------------------ saves (user://look.cfg: one section per local seat, presets)
## True when this local seat has a saved look (load_saved() falls back to the seat's defaults otherwise).
static func has_saved(seat: int) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and cfg.has_section_key(_section(seat), "look")

static func load_saved(seat: int) -> CharacterLook:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section_key(_section(seat), "look"):
		var d = cfg.get_value(_section(seat), "look", {})
		if d is Dictionary: return from_dict(d, seat)
	return defaults_for_seat(seat)

func save(seat: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # a missing file starts empty
	cfg.set_value(_section(seat), "look", to_dict())
	cfg.save(SAVE_PATH)

## Saved presets, oldest first.
static func presets() -> Array:
	var cfg := ConfigFile.new()
	var result: Array = []
	if cfg.load(SAVE_PATH) != OK: return result
	var list = cfg.get_value("presets", "looks", [])
	if list is Array:
		for d in list:
			if d is Dictionary: result.append(from_dict(d))
	return result

## Replaces the saved presets (CharacterLook or look dictionaries).
static func save_presets(list: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var out: Array = []
	for entry in list:
		if entry is CharacterLook: out.append(entry.to_dict())
		elif entry is Dictionary: out.append(from_dict(entry).to_dict())
	cfg.set_value("presets", "looks", out)
	cfg.save(SAVE_PATH)

## Awards (user://look.cfg, section "awards", key "<award>:<seat>"): what a local seat has won and may wear again after taking it off (Catalog.awards()).
static func has_award(seat: int, award: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and bool(cfg.get_value("awards", "%s:%d" % [award, seat], false))

## `base` for `seat` with the award item `id` worn, saved, and the award kept for the wardrobe. The look to wear and send on.
static func award(seat: int, id: String, base: CharacterLook) -> CharacterLook:
	var entry := Catalog.item(id)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("awards", "%s:%d" % [str(entry.get("award", "")), seat], true)
	cfg.save(SAVE_PATH)
	var look := base.duplicate_look()
	look.items[str(entry.get("slot", ""))] = id
	look = look.fitted()
	look.save(seat)
	return look

static func _section(seat: int) -> String:
	return "seat_%d" % seat
