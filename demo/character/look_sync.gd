extends Node
## Client side of the players' looks online. Sends this player's look ({"c": "look", "v": hex}, network/look_relay.gd)
## right after joining (when one is saved) and whenever the wardrobe confirms one (LookSync.commit), and dresses every other
## player's character from the match state ("look_revs", "looks"), again when the round moves players to other slots.
## Our own character is the wardrobe's (it wears the saved look and every preview); without one it gets our seat's default
## look like everybody else. client/main.gd attaches this once;
## local play never joins, so nothing happens there (the wardrobe dresses both local characters itself).
const Look := preload("res://character/look.gd")
const SAVE_SEAT := 0 ## online, this device's look is saved under local seat 0

static var _pending := PackedByteArray() ## a confirmed look waiting to be sent

var main: Node ## client/main.gd: joined, my_seat, slot_seats, match_info, simulation
var _sent_after_join := false
var _known := {} ## seat -> [revision, bytes] from the match state
var _shown := {} ## slot -> "seat:revision:rig" that slot's rig wears

static func attach(client: Node) -> Node:
	var sync: Node = load("res://character/look_sync.gd").new()
	sync.name = "LookSync"
	sync.main = client
	client.add_child(sync)
	return sync

## The wardrobe confirmed `look` for this player: it is sent with the next frame (online only).
static func commit(look: CharacterLook) -> void:
	_pending = look.to_bytes()

func _process(_delta: float) -> void:
	if not bool(main.get("joined")):
		_sent_after_join = false
		_known.clear()
		_shown.clear()
		_pending = PackedByteArray()
		return
	if not _sent_after_join:
		_sent_after_join = true
		if _pending.is_empty() and Look.has_saved(SAVE_SEAT): _pending = Look.load_saved(SAVE_SEAT).to_bytes()
	if not _pending.is_empty():
		main.call("_command", {"c": "look", "v": _pending.hex_encode()})
		_pending = PackedByteArray()
	dress(main.get("match_info"))

## Dresses the other players' characters from a match state.
func dress(info: Variant) -> void:
	if not (info is Dictionary): return
	var revs: Variant = info.get("look_revs")
	var looks: Variant = info.get("looks")
	if not (revs is Array): return
	for seat in (revs as Array).size():
		var revision := int(revs[seat])
		if revision == int((_known.get(seat, [0]) as Array)[0]): continue
		if revision == 0: _known[seat] = [0, PackedByteArray()]
		elif looks is Array and seat < (looks as Array).size() and looks[seat] is PackedByteArray: _known[seat] = [revision, looks[seat]]
	var simulation: Variant = main.get("simulation")
	if simulation == null: return
	var rigs: Array = simulation.get("rigs")
	var slot_seats: Array = main.get("slot_seats")
	var own := int(main.get("my_seat"))
	for slot in rigs.size():
		var seat := int(slot_seats[slot]) if slot < slot_seats.size() else (slot if slot_seats.is_empty() else -1)
		if seat < 0: continue
		var known: Array = _known.get(seat, [0, PackedByteArray()])
		if seat == own and (Look.has_saved(SAVE_SEAT) or int(known[0]) != 0): continue # our own look is the wardrobe's
		var rig: Node = rigs[slot]
		if rig == null or not rig.has_method("set_look"): continue
		var tag := "%d:%d:%d" % [seat, known[0], rig.get_instance_id()]
		if _shown.get(slot, "") == tag: continue
		var bytes: PackedByteArray = known[1] # no look sent (revision 0): the seat's own default, not the slot's
		rig.set_look(Look.from_bytes(bytes, seat) if Look.valid_bytes(bytes) else Look.defaults_for_seat(seat))
		_shown[slot] = tag
