extends RefCounted
## Mask-coded shared root fields of the snapshot. Values keep their exact Variant types; this is not quantization.
## Unknown fields stay in the outer snapshot.
const VERSION := 1
const FIELDS := ["tick","painting","roll","height","level","playing","broken","hit","won","resets","failure_kind","death_ui_visible","break_elapsed","break_event","elapsed_seconds","breaks","audio_events","hazard_t","players_joined","server_elapsed","input_sequences","waiting_for_partner","settlement_state"]
const BOOLS := ["playing","broken","won","death_ui_visible","waiting_for_partner"]
const INTS := ["tick","resets","break_event","breaks","players_joined"]
const NUMBERS := ["roll","height","break_elapsed","elapsed_seconds","hazard_t","server_elapsed"]

const MAX_SLOTS := 10 ## network/game.gd MAX_PLAYERS

static func _bools(value: Variant) -> bool:
	if not value is Array or value.size()<1 or value.size()>MAX_SLOTS: return false
	for entry: Variant in value:
		if not entry is bool: return false
	return true

static func _counts(value: Variant) -> bool:
	if not value is Array or value.size()<1 or value.size()>MAX_SLOTS: return false
	for entry: Variant in value:
		if not entry is int or entry<0: return false
	return true

static func _valid(key: String, value: Variant) -> bool:
	if key in BOOLS: return value is bool
	if key in INTS: return value is int and value>=0
	if key=="level": return value is int and value>=-1
	if key in NUMBERS: return (value is float or value is int) and is_finite(float(value))
	if key in ["hit","failure_kind","settlement_state"]: return value is String
	if key=="painting": return value is Transform3D and value.is_finite()
	if key=="input_sequences": return _counts(value)
	if key=="audio_events":
		if not value is Dictionary: return false
		for field: String in ["death"]:
			if not value.get(field) is int or value[field]<0: return false
		return true
	return false

static func encode(state: Dictionary) -> Array:
	var mask := 0
	var values := []
	for index in FIELDS.size():
		var key: String = FIELDS[index]
		if not state.has(key): continue
		if not _valid(key,state[key]): return []
		mask |= 1<<index
		values.append(state[key])
	return [VERSION,mask]+values

static func decode(frame: Variant) -> Dictionary:
	if not frame is Array or frame.size()<2 or not frame[0] is int or frame[0]!=VERSION or not frame[1] is int: return {}
	var mask: int = frame[1]
	if mask<0 or mask>>FIELDS.size()!=0: return {}
	var cursor := 2
	var state := {}
	for index in FIELDS.size():
		if not mask & (1<<index): continue
		if cursor>=frame.size() or not _valid(FIELDS[index],frame[cursor]): return {}
		state[FIELDS[index]]=frame[cursor]
		cursor+=1
	return {"value":state} if cursor==frame.size() else {}
