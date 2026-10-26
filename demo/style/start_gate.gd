extends RefCounted
## The START gate over a race's start (the slot `arch_start`, style/slot_frames.gd draws it in every look but the comic one): ONE rounded gantry that spans the whole platform, the GOAL sign's design
## family (style/goal_sign.gd) at a fraction of its size. Look only: no collision.
##   legs     two rounded purple plastic posts at the two ends of the platform, an amber cap on top and a white collar at the foot. They stand INSIDE the platform's rim (0.3 m in from an open edge),
##            or against the inner face of a side wall; nothing stands in the walkway
##   band     the sign between the legs: a bevelled amber band with a white inner edge, a purple border with the marquee bulbs, a recess panel of saturated blue (the GOAL sign's section and shader,
##            scaled), its ends sunk into the legs. In the recess ONE brand plate on both faces: the logo on its round plate, the extruded START word and under it the team name
##   no floor under both legs (a survival level hangs in the air): `plan` is empty and SlotFrames falls back to style/goal_arch.gd
## Frame space (the slot's own): the band's underside BOTTOM over the floor, centred on x = plan.centre, the faces look along +Z and -Z.
const BlockMesh := preload("res://style/block_mesh.gd")
const GoalSign := preload("res://style/goal_sign.gd")
const Hazards := preload("res://levels/hazards.gd")
const ShowCrown := preload("res://style/show_crown.gd")
const TeamCast := preload("res://style/team_cast.gd")
const LEG := 0.7                 ## m: a leg's side
const RIM_GAP := 0.3             ## m: a leg's outer face stands this far inside an open platform edge (the rim is 0.25 m wide)
const WALL_SINK := 0.02          ## m: a leg's outer face goes this far into a side wall's inner face
const FOOT_SINK := 0.03          ## m: a leg's foot goes this far into the floor
const HEIGHT := 2.8              ## m: the band's height
const SCALE := 0.33              ## the GOAL sign's frame section, scaled
const CORNER := 0.55             ## m: radius of the band's outer corners
const ARC := 4                   ## segments of a rounded corner
const BULB_GAP := 0.6
const BULB := 0.11
const REACH := 14.0              ## m: the floor lies at most this far under the band's centre
const SEEK := 12.0               ## m: the legs stand at most this far from the middle
const MIN_HALF := 3.0
const TEXT_DEPTH := 0.3
const NAME_DEPTH := 0.18
const START_HEIGHT := 0.95
const NAME_HEIGHT := 0.38
const PLATE := 1.1               ## m: the logo on its plate (the plate is 1.24 m across)
const GAP := 0.3                 ## m between the plate and the words
const BOTTOM := 4.3              ## m: the band's underside over the floor (over the start gate's door, 4 m high, that rises behind it at GO)
const CAP := 0.28                ## m: the legs stand this far over the band's top edge

static var _meshes := {}

## Where the legs stand for `slot` among the level's `blocks`: {centre (x), half (x of each leg's axis, from the centre), left, right (y of each leg's foot in frame space)}, empty when it cannot stand.
static func plan(slot: Dictionary, blocks: Array) -> Dictionary:
	var at: Vector3 = slot.p
	var basis := Basis(Vector3.UP, float(slot.yaw))
	var under := _nearest(blocks, at, Vector3.DOWN)
	if under > REACH: return {}
	var top := at.y - under
	var legs: Array[float] = []
	var feet: Array[float] = []
	for side: float in [-1.0, 1.0]:
		var direction := basis.x * side
		var probe := at
		probe.y = top + 0.5
		var wall := _nearest(blocks, probe, direction)
		var reach := _edge(blocks, probe, direction, minf(wall, SEEK))
		var on_wall := wall <= reach + 0.01
		var axis := wall + WALL_SINK - LEG * 0.5 if on_wall else reach - RIM_GAP - LEG * 0.5 # the leg's axis, from the middle
		var spot := probe + direction * axis
		var drop := _nearest(blocks, spot, Vector3.DOWN)
		if drop > 0.9 or axis < MIN_HALF: return {}
		legs.append(axis * side)
		feet.append(spot.y - drop - at.y)
	var centre := (legs[0] + legs[1]) * 0.5
	return {"centre": centre, "half": (legs[1] - legs[0]) * 0.5, "left": feet[0], "right": feet[1]}

## The distance from `probe` along `direction` at which the floor under it ends (0.05 m resolution, at most `limit`).
static func _edge(blocks: Array, probe: Vector3, direction: Vector3, limit: float) -> float:
	var step := 0.5
	var last := 0.0
	var x := step
	while x <= limit + 0.001:
		if _nearest(blocks, probe + direction * x, Vector3.DOWN) > 0.9: break
		last = x
		x += step
	if x > limit + 0.001: return limit
	var low := last
	var high := x
	for round in 4:
		var middle := (low + high) * 0.5
		if _nearest(blocks, probe + direction * middle, Vector3.DOWN) > 0.9: high = middle
		else: low = middle
	return low

static func _nearest(blocks: Array, from: Vector3, direction: Vector3) -> float:
	var best := INF
	for block: Dictionary in blocks: best = minf(best, Hazards.ray_hit(block, from, direction))
	return best

## Adds the gate to `holder` (the slot's frame) for a `plan` (the slot's own size is not read: the gate spans the platform).
static func build(holder: Node3D, slot: Dictionary, plan: Dictionary) -> void:
	var size: Vector2 = slot.size
	var half: float = plan.half
	var centre: float = plan.centre
	var span := 2.0 * half # the band runs from leg axis to leg axis: its ends are inside the legs
	var bottom := (float(plan.left) + float(plan.right)) * 0.5 + BOTTOM # frame space: the floor's height under the middle of the legs + BOTTOM
	var key := "%.2f" % span
	if not _meshes.has(key): _meshes[key] = _band_mesh(span)
	var band := Node3D.new()
	band.name = "StartSign"
	band.position = Vector3(centre, bottom, 0.0)
	var body := MeshInstance3D.new()
	body.name = "Band"
	body.mesh = _meshes[key]
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	band.add_child(body)
	_brand(band, span)
	holder.add_child(band)
	var legs := MeshInstance3D.new()
	legs.name = "Legs"
	legs.mesh = _legs_mesh(centre, half, bottom, float(plan.left), float(plan.right))
	holder.add_child(legs)

# ------------------------------------------------------------------ the legs

static func _legs_mesh(centre: float, half: float, bottom: float, left: float, right: float) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var top := bottom + HEIGHT + CAP
	for index in 2:
		var x := centre + (-half if index == 0 else half)
		var foot := (left if index == 0 else right) - FOOT_SINK
		batch.box(Transform3D(Basis.IDENTITY, Vector3(x, (foot + top) * 0.5, 0.0)), Vector3(LEG, top - foot, LEG), 0.3, 3, "body", "body", GoalSign.PYLON_COLOUR)
		var inward := 1.0 if index == 0 else -1.0
		var shift := inward * 0.08 # a collar and a cap are 12 cm wider than the leg but 2 cm inside its outer face: against a side wall nothing of the gate enters the wall
		batch.box(Transform3D(Basis.IDENTITY, Vector3(x + shift, foot + FOOT_SINK + 0.15, 0.0)), Vector3(LEG + 0.12, 0.34, LEG + 0.12), 0.15, 3, "body", "body", GoalSign.WHITE)
		batch.box(Transform3D(Basis.IDENTITY, Vector3(x + shift, top + 0.12, 0.0)), Vector3(LEG + 0.12, 0.3, LEG + 0.12), 0.15, 3, "body", "body", GoalSign.AMBER)
	return batch.commit({"body": GoalSign._body_material()})

# ------------------------------------------------------------------ the band

## The band's section from the rim inwards, the GOAL sign's scaled: [d, z, colour].
static func _section() -> Array:
	var out: Array = []
	for point: Array in GoalSign.SECTION: out.append([float(point[0]) * SCALE, float(point[1]) * SCALE, point[2]])
	return out

static func _band_mesh(width: float) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var body := batch.group("body")
	var panel := batch.group("panel")
	var bulbs := batch.group("bulb")
	var section := _section()
	var loops := {}
	for point: Array in section:
		var inset := float(point[0])
		if not loops.has(inset): loops[inset] = _loop(width, HEIGHT, inset)
	for side: float in [1.0, -1.0]:
		for index in section.size() - 1:
			var from: Array = section[index]
			var to: Array = section[index + 1]
			GoalSign._strip(body, loops[float(from[0])], loops[float(to[0])], float(from[0]), float(to[0]), float(from[1]), float(to[1]), side, to[2])
	var brick_d: float = GoalSign.PANEL_D * SCALE
	var panel_z: float = GoalSign.PANEL_Z * SCALE
	var inner: PackedVector2Array = loops[brick_d]
	for side: float in [1.0, -1.0]:
		var centre := panel.add(Vector3(0.0, HEIGHT * 0.5, panel_z * side), Vector3(0.0, 0.0, side), Vector2(0.0, HEIGHT * 0.5), Color.WHITE)
		var first := -1
		var previous := -1
		for point: Vector2 in inner:
			var vertex := panel.add(Vector3(point.x, point.y, panel_z * side), Vector3(0.0, 0.0, side), point * Vector2(side, 1.0), Color.WHITE)
			if first < 0: first = vertex
			if previous >= 0: panel.triangle(centre, previous, vertex, Vector3(0.0, 0.0, side))
			previous = vertex
		panel.triangle(centre, previous, first, Vector3(0.0, 0.0, side))
	var band := _loop(width, HEIGHT, float(GoalSign.BAND_D) * SCALE)
	var spots := GoalSign._spaced(band, BULB_GAP)
	var band_z: float = GoalSign.BAND_Z * SCALE
	for side: float in [1.0, -1.0]:
		for spot: Dictionary in spots:
			var place := Vector3(spot.p.x, spot.p.y, (band_z + 0.04) * side)
			var tint := Color(float(int(spot.k) % 3) * 0.5, float(spot.f), float(int(spot.k) % 2), 1.0)
			GoalSign._ball(bulbs, place, BULB, tint, 8, 5)
			var next: Dictionary = spots[(int(spot.k) + 1) % spots.size()]
			var middle := ((spot.p as Vector2) + (next.p as Vector2)) * 0.5
			GoalSign._ball(body, Vector3(middle.x, middle.y, band_z * side), 0.05, GoalSign.WHITE, 6, 3, 0.55 * side)
	return batch.commit({"body": GoalSign._body_material(), "panel": GoalSign._shader("panel"), "bulb": GoalSign._shader("bulb")})

## The band's outline (a rounded rectangle, x across from the middle, y up from the underside) inset by `inset` (<= 0), counter-clockwise from the top left; always the same number of points.
static func _loop(width: float, height: float, inset: float) -> PackedVector2Array:
	var half := width * 0.5 + inset
	var sharp: Array[Vector2] = [Vector2(-half, height + inset), Vector2(-half, -inset), Vector2(half, -inset), Vector2(half, height + inset)]
	var out := PackedVector2Array()
	var radius := maxf(CORNER + inset, 0.1)
	for index in 4:
		var here := sharp[index]
		var before := sharp[(index + 3) % 4]
		var after := sharp[(index + 1) % 4]
		var to_before := (before - here).normalized()
		var to_after := (after - here).normalized()
		var a := here + to_before * radius
		var b := here + to_after * radius
		for step in ARC + 1:
			var s := float(step) / float(ARC)
			out.append(a * (1.0 - s) * (1.0 - s) + here * 2.0 * s * (1.0 - s) + b * s * s)
	return out

# ------------------------------------------------------------------ the brand plate

## The logo on its round plate, START in mint over the team name in gold, centred in the recess, on both faces.
static func _brand(band: Node3D, width: float) -> void:
	var recess_top := HEIGHT + float(GoalSign.PANEL_D) * SCALE
	var recess_low := -float(GoalSign.PANEL_D) * SCALE
	var middle := (recess_top + recess_low) * 0.5
	var recess_wide := width + 2.0 * float(GoalSign.PANEL_D) * SCALE
	var start := GoalSign._text("START", START_HEIGHT, recess_wide * 0.5, TEXT_DEPTH, "goal")
	var title := TeamCast.team_name()
	var name_word: Dictionary = {}
	if title != "": name_word = GoalSign._text(title, NAME_HEIGHT, maxf((start.size as Vector3).x * 1.5, 3.0), NAME_DEPTH, "sub")
	var block_wide := maxf((start.size as Vector3).x, (name_word.size as Vector3).x if not name_word.is_empty() else 0.0)
	var block_high := (start.size as Vector3).y + ((name_word.size as Vector3).y + 0.14 if not name_word.is_empty() else 0.0)
	var logo := TeamCast.logo()
	var plate_wide := PLATE * 1.24 if logo != null else 0.0
	var row := plate_wide + (GAP if logo != null else 0.0) + block_wide
	var left := -row * 0.5
	var z := float(GoalSign.PANEL_Z) * SCALE
	for face: float in [1.0, -1.0]:
		var mount := Node3D.new()
		mount.name = "Face" if face > 0.0 else "BackFace"
		mount.rotation.y = 0.0 if face > 0.0 else PI
		band.add_child(mount)
		var x := left
		if logo != null:
			ShowCrown.plate(mount, logo, Vector3(x + plate_wide * 0.5, middle, z + 0.03), PLATE)
			x += plate_wide + GAP
		var top := middle + block_high * 0.5
		GoalSign._place(mount, start, Vector3(x + block_wide * 0.5, top - (start.size as Vector3).y * 0.5, z + TEXT_DEPTH * 0.5 - 0.02), "Start")
		if not name_word.is_empty():
			var y := top - (start.size as Vector3).y - 0.14 - (name_word.size as Vector3).y * 0.5
			GoalSign._place(mount, name_word, Vector3(x + block_wide * 0.5, y, z + NAME_DEPTH * 0.5 - 0.02), "Name")
