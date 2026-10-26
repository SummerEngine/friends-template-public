extends RefCounted
## Which spawn pads a stage round of `count` players stands on (level_world.gd team_start; `stage.starts` of the level file, docs/level-format.md "Stage rounds").
## Everybody has a pad of their own while there are pads (12 players on 12 pads, as listed). Fewer players take pads spread over the whole block: the first is the
## pad furthest from the block's middle and every next one the pad furthest from all taken so far (ties go to the first listed), so two players stand at opposite
## corners, four at the four corners, and so on; one player alone gets the first listed, the middle of the block. A pure function of the pad list and the
## count, the same on every machine. More players than pads wrap round the list.

## The feet spots (level-local) of `count` players, in seat order.
static func pick(pads: Array, count: int) -> Array:
	var spots := []
	if pads.is_empty() or count <= 0: return spots
	if count == 1: return [pads[0]]
	if count >= pads.size():
		for index in count: spots.append(pads[index % pads.size()])
		return spots
	var order := _spread(pads)
	for index in count: spots.append(pads[order[index]])
	return spots

## The pads' indices in the order they are taken when few play: furthest from the middle first, then always the one furthest from the taken ones.
static func _spread(pads: Array) -> Array:
	var middle := Vector2.ZERO
	for pad: Vector3 in pads: middle += Vector2(pad.x, pad.z)
	middle /= pads.size()
	var first := 0
	var far := -1.0
	for index in pads.size():
		var gap := Vector2((pads[index] as Vector3).x, (pads[index] as Vector3).z).distance_to(middle)
		if gap > far + 0.001:
			far = gap
			first = index
	var order := [first]
	var nearest := []
	for index in pads.size(): nearest.append(_gap(pads[index], pads[first]))
	while order.size() < pads.size():
		var best := -1
		for index in pads.size():
			if order.has(index): continue
			if best < 0 or float(nearest[index]) > float(nearest[best]) + 0.001: best = index
		order.append(best)
		for index in pads.size(): nearest[index] = minf(float(nearest[index]), _gap(pads[index], pads[best]))
	return order

static func _gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
