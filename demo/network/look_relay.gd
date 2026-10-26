extends RefCounted
## Authority side of the players' looks (CharacterLook bytes, demo/character/look.gd). A client sends
## {"c": "look", "v": <hex of CharacterLook.to_bytes()>} after joining and when its wardrobe confirms a look. The authority
## checks size and ranges only, keeps one look per seat with a revision (unique over the match) and puts them into the match
## state: "look_revs" (per seat, 0 = no look) always, "looks" (per seat, the bytes or empty) for a short burst after a change
## and during the controller's baseline bursts (joins, resyncs). Clients dress the characters (demo/character/look_sync.gd).
const Look := preload("res://character/look.gd")
const BURST := 40 ## snapshots (2 s) that carry the bytes after a change

var looks := {} ## seat -> PackedByteArray
var revisions := {} ## seat -> revision of its look
var _revision := 0
var _burst := 0

## Stores the look of `seat`; false when `value` is not a valid look for this catalog.
func store(seat: int, value: Variant) -> bool:
	if not (value is String) or (value as String).length() != Look.byte_size() * 2 or not (value as String).is_valid_hex_number(false): return false
	var bytes := (value as String).hex_decode()
	if not Look.valid_bytes(bytes): return false
	if looks.get(seat) == bytes: return true
	looks[seat] = bytes
	_revision += 1
	revisions[seat] = _revision
	_burst = BURST
	return true

func forget(seat: int) -> void:
	looks.erase(seat)
	revisions.erase(seat)

## Adds "look_revs" and, during a burst or a baseline, "looks" to a match state.
func publish(state: Dictionary, seat_count: int, baseline: bool) -> void:
	var revs := []
	var list := []
	for seat in seat_count:
		revs.append(int(revisions.get(seat, 0)))
		list.append(looks.get(seat, PackedByteArray()))
	state["look_revs"] = revs
	if baseline or _burst > 0:
		state["looks"] = list
		_burst = maxi(_burst - 1, 0)
