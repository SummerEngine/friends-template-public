extends RefCounted
## EXPERIMENT (switchable): EDGE BUMPERS. The jump-target platforms of the race levels carry rounded bumper cushions along their open edges, so a landing in the middle is fine and
## a sloppy one near the rim bounces the courier off. Toggleable and reversible: nothing is written into a level file; the plan below is derived at load time from
## `levels/edge_bumpers.json` (docs/level-format.md "Edge bumpers (experiment)"), `"on": false` there (or deleting the file) leaves every level exactly as its file says.
## Pure functions of the level's blocks and hazards (no nodes, no random numbers: a seeded hash per platform), so the authority, every client and every tool build the same plan.
##
## The plan (`plan()`): {on, share, seed, candidates, platforms: [{id, index, kind, x0, x1, z0, z1, top, ring, inset, margins, safe, spot, spans, pills}], pills: [cushion hazard dictionaries]}.
##   A platform is a candidate when it is a floor to land on: a plain upright box (or round floor) at least MIN_SIDE across, not the start deck, the finish, a belt, a gate's deck, a mover,
##   a hit or slot block, or a pillar, frame or wall tone. Its open edges get cushions: every side of a platform up to ISLAND_MAX across (a stepping stone, a landing deck, a pad stone),
##   and on a bigger deck only the stretch of an open edge that faces a jump (a platform within REACH of it across a gap). An edge a block touches, or that a checkpoint zone, an item box
##   or a pad / bumper / fire jet / spike field stands on, stays bare there. A platform keeps no more than `share` of the candidates (the lowest seeded hashes first; 1.0 is all of them).
##   A cushion is a PILL: a capsule of RADIUS lying on the deck along the edge, its axis INSET from the edge so the bare middle is about SAFE_SHARE of the width.
## The hitbox IS the drawn pill (style/edge_bumper_look.gd draws exactly these capsules): a courier is bumped the moment its capsule touches a pill's surface, from deck height to
## 2 x RADIUS (about knee height) and not an inch more; the middle of the deck is clear. The throw: KICK m/s outward along the edge's normal and UP_SPEED m/s up.
const Hazards := preload("res://levels/hazards.gd")
const RADIUS := 0.25            ## m: a cushion's radius (it is 0.5 m thick: knee height)
const LIFT := 0.04              ## m: the cushions rest this far over the deck: just clear of the 0.045 to 0.07 m rim strips the floor look lays along an open edge (MeshLint: no overlap) and never z-fighting with the tiles
const COURIER_RADIUS := 0.35    ## the courier capsule (levels/level_world.gd COURIER_RADIUS)
const COURIER_HALF_SEGMENT := 0.55
const KICK := 8.0               ## m/s horizontal, outward (7 to 9)
const UP_SPEED := 3.5           ## m/s up (3 to 4)
const SAFE_SHARE := 0.55        ## the share of a platform's width that stays clear of every cushion (50 to 60 %), as far as INSET_MIN / INSET_MAX allow
const INSET_MIN := 0.15         ## m: a cushion's axis is at least this far in from the deck's edge (most of it stands on the deck) ...
const INSET_MAX := 0.9          ## ... and at most this far (a big deck keeps a bumper band, not a moat)
const MIN_SIDE := 3.0           ## m: a platform narrower than this has no room for a safe middle
const ISLAND_MAX := 12.0        ## m: up to this size every open side is cushioned; a bigger deck only where an edge faces a jump
const MIN_RUN := 1.0            ## m: a stretch of edge shorter than this gets no cushion
const REACH := 8.0              ## m: a platform this near across an open edge is a jump that edge faces
const FACE_MARGIN := 1.5        ## m: the stretch facing a jump reaches this far past the target's sides
const ATTACHED := 0.3           ## m: a block this near a platform's side joins it (a walkway, a step): no cushion there
const CUT_GROW := 0.9           ## m: a checkpoint zone, item box or compact hazard keeps its surroundings this far free of cushions
const GATE_HEIGHT := 2.0        ## m: a mover with a part this tall is a gate (or a wall): the deck under it is no landing
const GATE_AREA := 0.5          ## m2 of a deck a gate's sweep may cover before the deck is left out
const TARGET_BELOW := 6.0       ## m: a platform this far under, or ...
const TARGET_ABOVE := 3.5       ## ... this far over, is still a jump away
const SEGMENTS := 16            ## the pills of a round floor's ring
const SHARE_MAX := 1.0
const CONFIG_FILE := "edge_bumpers.json"
const FORMAT := "edge-bumpers-1"
## Tones that are not a plain floor: walls, frames, gates, doors, eyes, hubs and discs of the spinners, pillars, crates, slime, the finish line. (A gate's deck is left out by _under_gate.)
const NOT_FLOORS := ["arch", "navy", "crate", "frame", "door", "eye", "hub", "disc", "stone", "stone_plain", "slime", "finish"]
const NONE := {"on": false, "share": 0.0, "seed": 0, "candidates": 0, "platforms": [], "pills": []}
const OUTWARD := [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0)]

## The experiment's switch for level `number`: {share, seed} when it is ON for that level, {} when it is off (no file, `"on": false`, the level not listed).
static func config(dir: String, number: int) -> Dictionary:
	var path := "%s/%s" % [dir, CONFIG_FILE]
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or str(parsed.get("format", "")) != FORMAT or not bool(parsed.get("on", false)): return {}
	var levels: Variant = parsed.get("levels")
	if not levels is Dictionary: return {}
	var entry: Variant = (levels as Dictionary).get(str(number))
	if not entry is Dictionary or not bool(entry.get("on", false)): return {}
	return {"share": clampf(float(entry.get("share", 1.0)), 0.0, SHARE_MAX), "seed": int(entry.get("seed", number))}

## The plan of a parsed level (levels/level_data.gd parse) under `cfg` (config()); NONE when `cfg` is empty or the level has nothing to dress.
static func plan(level: Dictionary, cfg: Dictionary) -> Dictionary:
	if cfg.is_empty(): return NONE
	var candidates := candidate_platforms(level)
	var picked := choose(candidates, float(cfg.share), int(cfg.seed), int(level.number))
	var platforms: Array = []
	var pills: Array = []
	for candidate: Dictionary in candidates:
		if not int(candidate.index) in picked: continue
		var platform: Dictionary = candidate.duplicate()
		platform.id = platforms.size()
		platform.pills = []
		for pill: Dictionary in _pills(platform):
			pill.platform = platforms.size()
			(platform.pills as Array).append(pills.size())
			pills.append(pill)
		platforms.append(platform)
	return {"on": true, "share": float(cfg.share), "seed": int(cfg.seed), "candidates": candidates.size(), "platforms": platforms, "pills": pills}

# ------------------------------------------------------------------ which platforms

## Every platform of the level that can carry cushions, in block order: [{index (of the block), kind ("box" | "cyl"), x0, x1, z0, z1, top, ring (every open side is cushioned), inset: Vector2 (the
## cushion axis' distance from the edge along x / z; a round floor: x), margins (per side: the distance from its edge to where the bare middle begins), safe: Rect2 (x, z, w, d: where a courier's
## feet are clear of every cushion), spot: Vector2 (a point in it), spans: [{side, a, b, out}] (the cushions' axes)}].
static func candidate_platforms(level: Dictionary) -> Array:
	var blocks: Array = level.blocks
	var boxes: Array = []
	for block: Dictionary in blocks: boxes.append(_aabb(block))
	var context := {"blocks": blocks, "boxes": boxes, "cuts": _cuts(level), "gates": _gates(level)}
	context.targets = _targets(level, blocks, boxes)
	var result: Array = []
	for index in blocks.size():
		var block: Dictionary = blocks[index]
		var box: AABB = boxes[index]
		var shape := _floor_shape(block, box)
		if shape == "" or _covered(index, box, boxes): continue
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if _special_zone(level, footprint, box.end.y) or _under_gate(footprint, context.gates): continue
		var platform := _box_platform(index, box, context) if shape == "box" else _round_platform(index, box, context)
		if not (platform.get("spans", []) as Array).is_empty(): result.append(platform)
	return result

## The distance from a deck's edge to its cushions' axis for a side of `width` metres: the one that leaves SAFE_SHARE of the width clear, within INSET_MIN .. INSET_MAX.
static func _inset(width: float) -> float:
	return clampf(width * (1.0 - SAFE_SHARE) * 0.5 - (RADIUS + COURIER_RADIUS), INSET_MIN, INSET_MAX)

## The axis-aligned box of a block (turned about y by a multiple of 90 degrees), level-local.
static func _aabb(block: Dictionary) -> AABB:
	var xf: Transform3D = block.xf
	var size: Vector3 = block.size
	var half := size * 0.5
	if absf(xf.basis.x.z) > 0.999: half = Vector3(half.z, half.y, half.x)
	return AABB(xf.origin - half, half * 2.0)

static func _rect(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

## "box" for a plain upright box, "cyl" for a plain upright round floor, a floor to walk on, of a size a jump lands on; "" for everything else.
static func _floor_shape(block: Dictionary, box: AABB) -> String:
	var shape := str(block.k)
	if not shape in ["box", "cyl"] or bool(block.hit) or str(block.m) != "ground" or str(block.slot) != "": return ""
	if str(block.tone) in NOT_FLOORS: return ""
	var basis: Basis = (block.xf as Transform3D).basis
	if absf(basis.y.y) < 0.999: return ""
	var small := minf(box.size.x, box.size.z)
	if small < MIN_SIDE: return ""
	if shape == "cyl": return "cyl" if absf(box.size.x - box.size.z) < 0.01 and box.size.x <= ISLAND_MAX else ""
	return "box" if absf(basis.x.x) > 0.999 or absf(basis.x.z) > 0.999 else ""

## Something covers most of the deck (a pillar's top under a stone, a slab on a slab): not a platform. A post or a beam over a corner is the cushions' business (_blocked), not the deck's.
static func _covered(index: int, box: AABB, boxes: Array) -> bool:
	for other in boxes.size():
		if other == index: continue
		var above: AABB = boxes[other]
		if above.position.y <= box.end.y + 0.01 and above.end.y > box.end.y + 0.01:
			if _rect(box).intersection(_rect(above)).get_area() > 0.5 * box.size.x * box.size.z: return true
	return false

## The start deck and the finish stay as they are.
static func _special_zone(level: Dictionary, footprint: Rect2, top: float) -> bool:
	var start: Vector3 = level.start
	if footprint.grow(0.5).has_point(Vector2(start.x, start.z)) and absf(start.y - top) < 1.0: return true
	var volume: Dictionary = level.goal_volume
	for point: Vector3 in [Vector3(footprint.get_center().x, top + 0.1, footprint.get_center().y), Vector3(footprint.get_center().x, top + 1.6, footprint.get_center().y)]:
		if _inside(volume, point): return true
	var inside_corners := 0
	for corner: Vector2 in [footprint.position, Vector2(footprint.end.x, footprint.position.y), footprint.end, Vector2(footprint.position.x, footprint.end.y)]:
		if _inside(volume, Vector3(corner.x, top + 0.1, corner.y)): inside_corners += 1
	return inside_corners >= 2

static func _inside(volume: Dictionary, point: Vector3) -> bool:
	var local: Vector3 = (volume.inverse as Transform3D) * point
	var half: Vector3 = volume.half
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z

## The deck of a gate: a mover with a tall part (a door that slides up into its frame, a wall that sweeps) over it.
static func _under_gate(footprint: Rect2, gates: Array) -> bool:
	for gate: Rect2 in gates:
		if footprint.intersection(gate).get_area() > GATE_AREA: return true
	return false

static func _gates(level: Dictionary) -> Array:
	var result: Array = []
	for h: Dictionary in level.hazards:
		if not str(h.k) in ["lift", "slide", "blink", "swing"]: continue
		var tall := false
		for part: Dictionary in h.parts:
			if (part.size as Vector3).y >= GATE_HEIGHT: tall = true
		if tall: result.append(_rect(_hazard_box(h)))
	return result

## The places cushions keep clear: [{rect (x, z), y0, y1, circle?, radius?}]: the respawn ring of every checkpoint (level_world.gd team_start: a ring of START_HALF_GAP round the zone's middle, so nobody
## is ever put back inside a bumper), the item boxes, the compact hazards (pads, bumpers, fire jets, spikes, lasers) and the turn of a disc or a bar turning flat over the deck (a circle: no cushion
## runs through the disc's sweep; `rect` is its bounding square).
static func _cuts(level: Dictionary) -> Array:
	var result: Array = []
	for volume: Dictionary in level.checkpoints:
		var middle: Vector3 = (volume.xf as Transform3D).origin
		var floor_y: float = middle.y - (volume.half as Vector3).y
		var reach := 1.75 + COURIER_RADIUS + RADIUS + CUT_GROW * 0.5 # the ring's radius (Data.START_HALF_GAP), a courier's reach and a cushion's thickness
		result.append({"rect": Rect2(middle.x - reach, middle.z - reach, reach * 2.0, reach * 2.0), "y0": floor_y - 1.0, "y1": floor_y + 3.0})
	for item: Dictionary in level.item_boxes:
		var at: Vector3 = item.p
		result.append({"rect": Rect2(at.x - 0.5, at.z - 0.5, 1.0, 1.0).grow(0.65), "y0": at.y - 0.5, "y1": at.y + 2.0})
	for h: Dictionary in level.hazards:
		if str(h.k) == "spin" and bool(h.hit) and str(h.axis) != "y": # a bar turning on a rod over the deck: the courier it knocks is not also thrown by a cushion under the rod
			var pivot: Vector3 = h.pivot
			result.append({"rect": Rect2(pivot.x - CUT_GROW - 0.5, pivot.z - CUT_GROW - 0.5, (CUT_GROW + 0.5) * 2.0, (CUT_GROW + 0.5) * 2.0), "y0": pivot.y - 8.0, "y1": pivot.y + 2.0})
		if str(h.k) == "spin" and str(h.axis) == "y": # a disc or a bar turning flat: no cushion runs through its sweep
			var pivot: Vector3 = h.pivot
			var sweep := 0.0
			var bottom := INF
			var peak := -INF
			for part: Dictionary in h.parts:
				var middle: Vector3 = (h.base as Basis) * (part.xf as Transform3D).origin
				var half: Vector3 = (part.size as Vector3) * 0.5
				var extent := half.x if str(part.k) == "cyl" else Vector2(half.x, half.z).length()
				sweep = maxf(sweep, Vector2(middle.x, middle.z).length() + extent)
				bottom = minf(bottom, pivot.y + middle.y - half.y)
				peak = maxf(peak, pivot.y + middle.y + half.y)
			sweep += RADIUS + 0.1
			result.append({"rect": Rect2(pivot.x - sweep, pivot.z - sweep, sweep * 2.0, sweep * 2.0), "circle": Vector2(pivot.x, pivot.z), "radius": sweep, "top_from": bottom - 2.0 * RADIUS - LIFT - 0.1, "top_to": peak + 0.05})
		if not str(h.k) in ["push", "bumper", "fire", "spikes", "laser"]: continue
		var box := _hazard_box(h)
		result.append({"rect": _rect(box).grow(CUT_GROW), "y0": box.position.y - 1.0, "y1": box.end.y + 1.0})
	return result

## The platforms a jump can aim at: [{rect, top, index}] (the floors of the level and the carriers of the movers).
static func _targets(level: Dictionary, blocks: Array, boxes: Array) -> Array:
	var result: Array = []
	for index in blocks.size():
		var block: Dictionary = blocks[index]
		var box: AABB = boxes[index]
		if bool(block.hit) or str(block.tone) in NOT_FLOORS or not str(block.k) in ["box", "wedge", "cyl"]: continue
		if minf(box.size.x, box.size.z) < 0.9: continue
		result.append({"rect": _rect(box), "top": box.end.y, "index": index})
	for h: Dictionary in level.hazards:
		var kind := str(h.k)
		if not (kind in ["slide", "lift", "blink"] or (kind == "spin" and not bool(h.hit))): continue
		var low := true
		for part: Dictionary in h.parts:
			if (part.size as Vector3).y >= GATE_HEIGHT: low = false
		if not low: continue
		var box := _hazard_box(h)
		result.append({"rect": _rect(box), "top": box.end.y, "index": -1})
	return result

# ------------------------------------------------------------------ the spans of a platform

## A box: the cushions along each open side (see the header for which), clipped where a block, a checkpoint zone, an item box or a compact hazard is in the way.
static func _box_platform(index: int, box: AABB, context: Dictionary) -> Dictionary:
	var top := box.end.y
	var x0 := box.position.x
	var x1 := box.end.x
	var z0 := box.position.z
	var z1 := box.end.z
	var size := Vector2(box.size.x, box.size.z)
	var ring := maxf(size.x, size.y) <= ISLAND_MAX
	var inset := Vector2(_inset(size.x), _inset(size.y))
	var y := top + RADIUS + LIFT
	var spans: Array = []
	var margins: Array = [0.6, 0.6, 0.6, 0.6]
	for side in 4:
		var along_x := side == 0 or side == 2
		var gap_in := inset.y if along_x else inset.x
		var corner := inset.x if along_x else inset.y
		var low := x0 if along_x else z0
		var high := x1 if along_x else z1
		var axis: float = [z0 + gap_in, x1 - gap_in, z1 - gap_in, x0 + gap_in][side]
		var reach := gap_in + RADIUS + COURIER_RADIUS
		var band: Rect2 = [Rect2(x0 - ATTACHED, z0 - ATTACHED, size.x + ATTACHED * 2.0, ATTACHED + reach), Rect2(x1 - reach, z0 - ATTACHED, reach + ATTACHED, size.y + ATTACHED * 2.0),
			Rect2(x0 - ATTACHED, z1 - reach, size.x + ATTACHED * 2.0, reach + ATTACHED), Rect2(x0 - ATTACHED, z0 - ATTACHED, ATTACHED + reach, size.y + ATTACHED * 2.0)][side]
		var blocked := _blocked(band, along_x, axis, top, index, context)
		var runs := _subtract(Vector2(low + corner, high - corner), blocked)
		if not ring:
			var outward: Rect2 = [Rect2(x0, z0 - REACH, size.x, REACH - ATTACHED), Rect2(x1 + ATTACHED, z0, REACH - ATTACHED, size.y),
				Rect2(x0, z1 + ATTACHED, size.x, REACH - ATTACHED), Rect2(x0 - REACH, z0, REACH - ATTACHED, size.y)][side]
			runs = _meet(runs, _facing(outward, along_x, top, index, context))
		var any := false
		for run: Vector2 in runs:
			if run.y - run.x < MIN_RUN: continue
			var a := Vector3(run.x, y, axis) if along_x else Vector3(axis, y, run.x)
			var b := Vector3(run.y, y, axis) if along_x else Vector3(axis, y, run.y)
			spans.append({"side": side, "a": a, "b": b, "out": OUTWARD[side]})
			any = true
		if any: margins[side] = reach
	var safe := Rect2(x0 + margins[3], z0 + margins[0], size.x - margins[3] - margins[1], size.y - margins[0] - margins[2])
	var result := {"index": index, "kind": "box", "x0": x0, "x1": x1, "z0": z0, "z1": z1, "top": top, "ring": ring, "inset": inset, "margins": margins, "safe": safe, "spans": spans}
	result.spot = _spot(result)
	return result

## A round floor: a ring of SEGMENTS pills, left out where something is in the way; nothing when a block touches it.
static func _round_platform(index: int, box: AABB, context: Dictionary) -> Dictionary:
	var top := box.end.y
	var centre := Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5)
	var radius := box.size.x * 0.5
	var reach := _rect(box).grow(ATTACHED)
	for other in (context.boxes as Array).size():
		var around: AABB = context.boxes[other]
		if other != index and around.end.y > top - 0.5 and around.position.y < top + 1.8 and reach.intersects(_rect(around)): return {}
	var inset := _inset(box.size.x)
	var axis_radius := radius - inset
	var y := top + RADIUS + LIFT
	var spans: Array = []
	for k in SEGMENTS:
		var angle_a := TAU * float(k) / float(SEGMENTS)
		var angle_b := TAU * float(k + 1) / float(SEGMENTS)
		var a := Vector3(centre.x + cos(angle_a) * axis_radius, y, centre.y + sin(angle_a) * axis_radius)
		var b := Vector3(centre.x + cos(angle_b) * axis_radius, y, centre.y + sin(angle_b) * axis_radius)
		var mid := (angle_a + angle_b) * 0.5
		if _cut_at(Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5), top, context) or _cut_at(Vector2(a.x, a.z), top, context): continue
		spans.append({"side": k, "a": a, "b": b, "out": Vector3(cos(mid), 0.0, sin(mid))})
	var clear := radius - inset - RADIUS - COURIER_RADIUS
	var half := clear / sqrt(2.0)
	var safe := Rect2(centre.x - half, centre.y - half, half * 2.0, half * 2.0)
	var result := {"index": index, "kind": "cyl", "x0": centre.x - radius, "x1": centre.x + radius, "z0": centre.y - radius, "z1": centre.y + radius, "top": top, "ring": true,
		"inset": Vector2(inset, inset), "margins": [], "safe": safe, "radius": radius, "centre": centre, "spans": spans}
	result.spot = centre
	if clear < 0.7: result.spans = []
	return result

## Whether a cut keeps cushions off a deck whose top is `top`: a circle (a flat spinner) where a cushion's top reaches the spinner's underside and the deck is not above its top; the others by height band.
static func _cut_applies(cut: Dictionary, top: float) -> bool:
	if cut.has("circle"): return top >= float(cut.top_from) and top <= float(cut.top_to)
	return float(cut.y1) >= top - 0.5 and float(cut.y0) <= top + 2.0

static func _cut_at(at: Vector2, top: float, context: Dictionary) -> bool:
	for cut: Dictionary in context.cuts:
		if not _cut_applies(cut, top): continue
		if cut.has("circle"):
			if at.distance_to(cut.circle) <= float(cut.radius): return true
		elif (cut.rect as Rect2).has_point(at): return true
	return false

## The stretches along a side (x for the sides along x, z for the others) where something stands in the cushion band `band` (level-local x, z; `axis` is where the cushion's axis runs): a block in the deck's height band (one touching the band's end counts: ATTACHED), a cut zone.
static func _blocked(band: Rect2, along_x: bool, axis: float, top: float, index: int, context: Dictionary) -> Array:
	var result: Array = []
	var boxes: Array = context.boxes
	for other in boxes.size():
		if other == index: continue
		var around: AABB = boxes[other]
		if around.end.y <= top - 0.5 or around.position.y >= top + 1.8: continue
		var rect := _rect(around)
		if band.intersects(rect): result.append(Vector2(rect.position.x - 0.3, rect.end.x + 0.3) if along_x else Vector2(rect.position.y - 0.3, rect.end.y + 0.3))
	for cut: Dictionary in context.cuts:
		if not _cut_applies(cut, top): continue
		var rect: Rect2 = cut.rect
		if not band.intersects(rect): continue
		if cut.has("circle"): # a disc's sweep: the chord of the circle along the cushion's axis
			var centre: Vector2 = cut.circle
			var across := absf(axis - centre.y) if along_x else absf(axis - centre.x)
			var radius := float(cut.radius)
			if across >= radius: continue
			var half := sqrt(radius * radius - across * across)
			var along := centre.x if along_x else centre.y
			result.append(Vector2(along - half, along + half))
		else:
			result.append(Vector2(rect.position.x, rect.end.x) if along_x else Vector2(rect.position.y, rect.end.y))
	return result

## The stretches of a side that face a jump: where a target platform stands in the `outward` rectangle, widened by FACE_MARGIN.
static func _facing(outward: Rect2, along_x: bool, top: float, index: int, context: Dictionary) -> Array:
	var result: Array = []
	for target: Dictionary in context.targets:
		if int(target.index) == index and index >= 0: continue
		var target_top := float(target.top)
		if target_top < top - TARGET_BELOW or target_top > top + TARGET_ABOVE: continue
		var rect: Rect2 = target.rect
		if outward.intersects(rect): result.append(Vector2(rect.position.x - FACE_MARGIN, rect.end.x + FACE_MARGIN) if along_x else Vector2(rect.position.y - FACE_MARGIN, rect.end.y + FACE_MARGIN))
	return _merge(result)

static func _merge(intervals: Array) -> Array:
	var sorted := intervals.duplicate()
	sorted.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var result: Array = []
	for item: Vector2 in sorted:
		if not result.is_empty() and item.x <= (result[-1] as Vector2).y: result[-1] = Vector2((result[-1] as Vector2).x, maxf((result[-1] as Vector2).y, item.y))
		else: result.append(item)
	return result

## `range` without the `blocked` intervals.
static func _subtract(range_: Vector2, blocked: Array) -> Array:
	var result: Array = []
	var cursor := range_.x
	for item: Vector2 in _merge(blocked):
		if item.y <= cursor: continue
		if item.x >= range_.y: break
		if item.x > cursor: result.append(Vector2(cursor, item.x))
		cursor = maxf(cursor, item.y)
	if cursor < range_.y: result.append(Vector2(cursor, range_.y))
	return result

## The parts of `runs` inside `keep` (both lists of intervals).
static func _meet(runs: Array, keep: Array) -> Array:
	var result: Array = []
	for run: Vector2 in runs:
		for item: Vector2 in keep:
			var low := maxf(run.x, item.x)
			var high := minf(run.y, item.y)
			if high > low: result.append(Vector2(low, high))
	return result

## A point in the clear middle to stand on: the middle of a small platform, and on a big deck the point just inside the longest cushion.
static func _spot(platform: Dictionary) -> Vector2:
	var safe: Rect2 = platform.safe
	if bool(platform.ring) or (platform.spans as Array).is_empty(): return safe.get_center()
	var best: Dictionary = (platform.spans as Array)[0]
	for span: Dictionary in platform.spans:
		if (span.a as Vector3).distance_to(span.b) > (best.a as Vector3).distance_to(best.b): best = span
	var middle: Vector3 = ((best.a as Vector3) + (best.b as Vector3)) * 0.5
	var out: Vector3 = best.out
	var inward := Vector2(middle.x - out.x * 2.6, middle.z - out.z * 2.6)
	return Vector2(clampf(inward.x, safe.position.x + 0.3, safe.end.x - 0.3), clampf(inward.y, safe.position.y + 0.3, safe.end.y - 0.3))

## A generous box round everything a hazard can reach (its parts at every pose of its travel or turn, a pad's volume, a ball's path ...), level-local.
static func _hazard_box(h: Dictionary) -> AABB:
	var kind := str(h.k)
	var pivot: Vector3 = h.pivot
	var base: Basis = h.base
	var box := AABB(pivot, Vector3.ZERO)
	var corners: Array = []
	for part: Dictionary in h.parts:
		var half: Vector3 = (part.size as Vector3) * 0.5
		for corner in 8:
			var local := Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y, half.z if corner & 4 else -half.z)
			corners.append(pivot + base * ((part.xf as Transform3D) * local))
	match kind:
		"spin", "swing":
			var reach := 0.0
			for point: Vector3 in corners: reach = maxf(reach, point.distance_to(pivot))
			return AABB(pivot - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		"slide", "lift":
			for point: Vector3 in corners:
				box = box.expand(point)
				box = box.expand(point + (h.to as Vector3))
		"push", "fire":
			var size: Vector3 = h.size
			var reach := size.length() * 0.5
			return AABB(pivot - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		"bumper":
			var radius := float(h.rad)
			return AABB(pivot - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
		"ball":
			for point: Vector3 in h.path: box = box.expand(point)
			box = box.grow(float(h.rad))
		"cannon":
			box = box.expand(pivot + (h.v as Vector3) * float(h.life)).grow(float(h.rad) + 1.0)
			for point: Vector3 in corners: box = box.expand(point)
			box = box.expand(pivot + Vector3(0.0, -0.5 * Hazards.GRAVITY * float(h.life) * float(h.life), 0.0))
		"laser":
			box = box.expand(pivot + (h.to as Vector3)).expand(pivot + (h.to as Vector3) + (h.move as Vector3)).expand(pivot + (h.move as Vector3))
			var reach := (h.to as Vector3).length()
			if float(h.rate) != 0.0: return AABB(pivot - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
		_: # blink, spikes
			for point: Vector3 in corners: box = box.expand(point)
			if kind == "spikes": box = box.expand(pivot - base.y * float(h.rise))
	return box


# ------------------------------------------------------------------ which of them

## The seeded hash of a platform: in [0, 1), a pure function of (seed, level, the block's place on a 0.25 m grid), so every machine ranks the platforms alike.
static func hash_of(seed_value: int, number: int, at: Vector3) -> float:
	var h := (seed_value * 374761393 + number * 668265263 + 1013904223) & 0xFFFFFFFF
	for part: int in [roundi(at.x * 4.0), roundi(at.y * 4.0), roundi(at.z * 4.0)]:
		h = (((h ^ (part & 0xFFFFFFFF)) * 2654435761) & 0xFFFFFFFF)
		h = (h ^ (h >> 15)) & 0xFFFFFFFF
	return float(h & 0xFFFFFF) / 16777216.0


## The block indices chosen: round(`share` x n) of the n `candidates`, the lowest hashes first (share 1.0: all of them).
static func choose(candidates: Array, share: float, seed_value: int, number: int) -> Array:
	var order: Array = []
	for position in candidates.size():
		var c: Dictionary = candidates[position]
		var at := Vector3((float(c.x0) + float(c.x1)) * 0.5, float(c.top), (float(c.z0) + float(c.z1)) * 0.5)
		order.append([hash_of(seed_value, number, at), position])
	order.sort()
	var result: Array = []
	for entry: Array in order.slice(0, roundi(share * float(candidates.size()))): result.append(int((candidates[entry[1]] as Dictionary).index))
	result.sort()
	return result

# ------------------------------------------------------------------ the cushions

## The pills of a platform, one per span, each a hazard-shaped dictionary the level world treats as a launcher: {k "cushion", id, pivot (the middle of the axis), base, ride, a, b (the axis'
## ends, level-local), rad, out (the unit horizontal normal it throws along), kick, up_speed, side}.
static func _pills(platform: Dictionary) -> Array:
	var result: Array = []
	for span: Dictionary in platform.spans:
		var a: Vector3 = span.a
		var b: Vector3 = span.b
		result.append({"k": "cushion", "id": "", "pivot": (a + b) * 0.5, "base": Basis.IDENTITY, "ride": "", "a": a, "b": b, "rad": RADIUS, "out": span.out,
			"kick": KICK, "up_speed": UP_SPEED, "side": int(span.side)})
	return result

## Whether a courier whose capsule centre is at `local` (level-local) touches the cushion `h`: its capsule (COURIER_HALF_SEGMENT up and down the vertical, COURIER_RADIUS round it)
## reaches the cushion's surface, the capsule round the axis a-b of radius `rad`. The drawn cushion is exactly that shape: no part of a courier is ever inside what is seen.
static func touched(h: Dictionary, local: Vector3) -> bool:
	var reach := Vector3(0.0, COURIER_HALF_SEGMENT, 0.0)
	return segment_distance(h.a, h.b, local - reach, local + reach) <= float(h.rad) + COURIER_RADIUS

## The throw of a cushion: outward along the edge's normal, KICK m/s, and UP_SPEED up, overriding the courier's own motion: {v, override_xy, override_z}.
static func launch(h: Dictionary) -> Dictionary:
	var out: Vector3 = h.out
	return {"v": out * float(h.kick) + Vector3.UP * float(h.up_speed), "override_xy": true, "override_z": true}

## The least distance between the segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9).
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9: return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-9: s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
