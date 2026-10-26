extends RefCounted
## Fixed-width input values; doubles retain the exact controller values.
## jump_seq / grab_seq / slap_seq count the owner's JUMP presses and GRAB presses that grab or slap (the owner tells them apart, the
## authority turns the change into press edges).
static var MAGIC := PackedByteArray([71, 87, 73, 78, 3]) # GWIN, version 3
const FIELDS := ["move", "seq", "jump_seq", "grab_seq", "slap_seq", "jump", "restart", "height", "roll", "facing"]

static func recognizes(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 4 and bytes.slice(0, 4) == MAGIC.slice(0, 4)

static func encode(input: Dictionary) -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	stream.put_data(MAGIC)
	stream.put_64(int(input.get("seq", 0)))
	stream.put_64(int(input.get("jump_seq", 0)))
	stream.put_64(int(input.get("grab_seq", 0)))
	stream.put_64(int(input.get("slap_seq", 0)))
	var flags := (1 if bool(input.get("jump", false)) else 0) | (2 if bool(input.get("restart", false)) else 0)
	stream.put_u8(flags)
	var move: Array = input.move
	stream.put_double(float(move[0]))
	stream.put_double(float(move[1]))
	for field: String in ["height", "roll", "facing"]:
		stream.put_double(float(input.get(field, 0.0)))
	var extra := input.duplicate()
	for field: String in FIELDS: extra.erase(field)
	if not extra.is_empty(): stream.put_data(var_to_bytes(extra))
	return stream.data_array

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 78 or bytes.size() > 1024 or not recognizes(bytes) or bytes[4] != MAGIC[4]: return {}
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	stream.seek(MAGIC.size())
	var output := {"seq": stream.get_64(), "jump_seq": stream.get_64(), "grab_seq": stream.get_64(), "slap_seq": stream.get_64()}
	var flags := stream.get_u8()
	if flags & ~3: return {}
	output.jump = bool(flags & 1)
	output.restart = bool(flags & 2)
	output.move = [stream.get_double(), stream.get_double()]
	for field: String in ["height", "roll", "facing"]: output[field] = stream.get_double()
	if stream.get_available_bytes() > 0:
		var extra: Variant = bytes_to_var(bytes.slice(stream.get_position()))
		if not extra is Dictionary: return {}
		for field: Variant in extra:
			if field in FIELDS: return {}
			output[field] = extra[field]
	return output
