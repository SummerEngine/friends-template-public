extends RefCounted
## The GOAL sign over a race's finish deck (the slot `arch_finish`, style/slot_frames.gd draws it in every look but the comic one): a big shield with a V point that
## hangs from a gantry over the deck and points down at the GOAL pad. Look only: no collision, the goal volume is untouched.
##   frame      a thick amber glossy bevelled band with a white inner edge, then a purple border on which the marquee bulbs sit (chasing, blinking, breathing: style/goal_sign.gdshader)
##              with small white rivets between them, then a recess panel of saturated blue with a faint dot pattern (a shader), all hard plastic (roughness 0.11), no light of its own
##   GOAL       the huge white extruded word (Lilita One, a TextMesh) with amber sides, and under it the sign's SUBTITLE in light amber: the level's own title
##              (`CourseSection.level_title`: the cast's title of the round, else the level file's), on two lines when it is long
##   gantry     two pylons beside the sign (on the deck when it is wide, else on columns from far below), a beam over them under a rainbow arch (style/rainbow_arch.gd) and four rods down to the sign's top edge: nothing but the rods touches it
## The sign stands BEHIND the deck: beyond the deck's far edge on the course's way in (`deck.ahead`, slot_frames.gd), BEHIND_EDGE past it, the V's tip MIN_CLEARANCE over the deck's top, drawn at SIGN_SCALE, on two columns beside it
## (the slot's own position and height are not read: only its yaw, the width of the deck and the way in). So it hangs on the horizon of the approach, fully in the stage view, pointing down at the deck.
## Both faces are built (the sign is a slab: the runner reads GOAL from either side). Sign space: x across, y up from the V's tip, +z the face; the sign's mesh is
## made once per width. The slot gives the sign's position and facing (its `p` y less half its height is the V's tip, its yaw the facing); the width comes from the
## deck (`FinishRails.deck`): 14 m, on a deck 19.2 m or wider (across the sign) the deck's width less 5.2 m up to 18 m; centred on the deck. Pylons stand clear of the sign's sides.
const BlockMesh := preload("res://style/block_mesh.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const SHADER := preload("res://style/goal_sign.gdshader")
const RainbowArch := preload("res://style/rainbow_arch.gd")
const HEIGHT_OVER_WIDTH := 0.7  ## the sign's height (top edge to the V's tip) over its width
const SHOULDER := 0.5           ## where the vertical sides end and the V begins, as a share of the height over the tip
const MIN_WIDTH := 14.0
const MAX_WIDTH := 18.0
const SIGN_SCALE := 0.5         ## the sign as built (14 to 18 m wide) is drawn at this scale: it fits the stage view from the way in (the whole shield, V tip to top edge, in frame from 10 m and still readable from 30 m)
const MIN_CLEARANCE := 2.0      ## m: the V's tip hangs this high over the deck's top
const BEHIND_EDGE := 1.0        ## m: the sign stands this far beyond the deck's far edge (clear of the rails along it)
const SLAB := 0.46              ## m: half the sign's thickness at its rim (the face of the frame stands 0.64 off the middle)
const PYLON := 0.8              ## m: a pylon's side
const PYLON_GAP := 1.3          ## m: the pylons stand this far clear of the sign's side edges (nothing touches the sign but its rods)
const ARCH_RISE := 0.42        ## the rainbow arch over the beam rises this share of the half span (at least 3.2 m)
const ROD_LENGTH := 2.0         ## m: the beam hangs this far over the sign's top edge
const DECK_CLEAR := 5.2         ## m: on a wide deck the sign is this much narrower than the deck: the pylons stand clear of the rails along its edges
const WIDE_DECK := MIN_WIDTH + DECK_CLEAR ## m: a deck at least this wide (across the sign) carries the pylons on its own floor, a narrower one has them beside it on columns
const COLUMN_DROP := 12.0       ## m: such a column reaches this far under the deck's top
const LOOP_ARC := 4             ## segments of a rounded corner
const BULB_GAP := 0.75          ## m: between two bulbs
const MARGIN := 0.5             ## m: the letters keep this far from the purple border
const GAP_ABOVE_GOAL := 0.55    ## m: between the border and the word, and between the word and the subtitle
const GOAL_HEIGHT := 0.23       ## GOAL's height over the sign's
const GOAL_WIDTH_MAX := 0.64    ## ... and its width over the sign's
const LETTER_DEPTH := 0.8       ## m: how far the letters stand off the panel
const PANEL_Z := 0.12           ## the recess panel's distance from the middle plane

const CandyLook := preload("res://style/candy_look.gd")
const AMBER := CandyLook.PROP_AMBER
const AMBER_LIGHT := CandyLook.PROP_AMBER_LIGHT
const AMBER_DEEP := CandyLook.PROP_AMBER_DEEP
const WHITE := CandyLook.PROP_WHITE
const WHITE_DEEP := Color("#f0e1f7")
const PURPLE := CandyLook.PROP_PURPLE
const PURPLE_DEEP := CandyLook.PROP_PURPLE_DEEP
const PYLON_COLOUR := CandyLook.PROP_PURPLE
const PYLON_LIGHT := CandyLook.PROP_PURPLE_LIGHT
const ROD := CandyLook.PROP_PURPLE_DEEP
const SUBTITLE_FRONT := CandyLook.PROP_AMBER_LIGHT
const SUBTITLE_SIDE := CandyLook.PROP_AMBER_DEEP

## The frame's section from the rim inwards: [d (m inwards, <= 0), z (off the middle plane), colour of the strip that leads to this point]. The first point is the rim at the middle plane.
const SECTION: Array = [
	[0.0, 0.0, Color.BLACK], [0.0, 0.46, AMBER_DEEP], [-0.2, 0.64, AMBER_LIGHT], [-0.85, 0.64, AMBER], [-1.08, 0.48, WHITE],
	[-1.08, 0.32, WHITE_DEEP], [-1.2, 0.32, WHITE], [-1.2, 0.24, PURPLE_DEEP], [-1.75, 0.24, PURPLE], [-1.75, PANEL_Z, PURPLE_DEEP]]
const BAND_D := -1.475          ## the middle of the purple border
const BAND_Z := 0.24
const PANEL_D := -1.75          ## the recess panel begins here
## The corners' radii at the rim (the top corners, the shoulders, the tip): they shrink with the inset
const CORNER := [1.6, 2.4, 1.2, 2.4, 1.6]

static var _meshes := {}
static var _materials := {}

## Adds the sign and its gantry to `holder` (the slot's frame: the slot's `p` at the origin, +z its facing). `deck` is FinishRails.deck(), `words` the subtitle,
## `slot` the slot ({id, p, yaw, size} in the level's space).
static func build(holder: Node3D, slot: Dictionary, deck: Dictionary, words: String) -> void:
	var basis := Basis(Vector3.UP, float(slot.yaw))
	var at: Vector3 = slot.p
	var low := INF
	var high := -INF
	for corner: Vector2 in _corners(deck.rect as Rect2):
		var across := (Vector3(corner.x - at.x, 0.0, corner.y - at.z)).dot(basis.x)
		low = minf(low, across)
		high = maxf(high, across)
	var centre := (low + high) * 0.5
	var deck_width := high - low
	var ahead: Vector2 = deck.get("ahead", Vector2.ZERO)
	var behind := Vector3.ZERO # frame space: the sign stands BEHIND the deck's far edge (beyond the finish, on the horizon of the approach), not over the pad
	if ahead != Vector2.ZERO:
		var far := -INF
		for corner: Vector2 in _corners(deck.rect as Rect2): far = maxf(far, Vector2(corner.x - at.x, corner.y - at.z).dot(ahead))
		behind = basis.inverse() * Vector3(ahead.x, 0.0, ahead.y) * (far + BEHIND_EDGE)
	var wide := false # beyond the deck the pylons stand beside it on columns from far below (a wide deck's own floor is in front of them)
	var width := clampf(deck_width - DECK_CLEAR, MIN_WIDTH, MAX_WIDTH) if deck_width >= WIDE_DECK else MIN_WIDTH
	var floor_y := float(deck.top) - at.y
	var tip := floor_y + MIN_CLEARANCE # low: the V's tip hangs MIN_CLEARANCE over the deck's top (the slot's own height is not read)
	var height := width * HEIGHT_OVER_WIDTH
	var key := "%.2f" % width
	var drawn_width := width * SIGN_SCALE
	var drawn_height := height * SIGN_SCALE
	if not _meshes.has(key): _meshes[key] = _sign_mesh(width, height)
	var board := Node3D.new()
	board.name = "GoalSign"
	board.position = Vector3(centre, tip, 0.0) + behind
	board.scale = Vector3.ONE * SIGN_SCALE
	var body := MeshInstance3D.new()
	body.name = "Board"
	body.mesh = _meshes[key]
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(body)
	_letters(board, width, height, words)
	holder.add_child(board)
	var gantry := MeshInstance3D.new()
	gantry.name = "Gantry"
	gantry.mesh = _gantry_mesh(drawn_width, centre, floor_y if wide else floor_y - COLUMN_DROP, tip, drawn_height, wide)
	gantry.position = behind
	holder.add_child(gantry)

## A free-standing shield of the same family for the lobby's hero circle (lobby/lobby_sign.gd): the sign alone (no gantry, no deck), `width` m across (MIN_WIDTH's shield scaled down: frame, marquee
## bulbs, brick recess and extruded letters all scale together), the V's tip at the origin of the returned node, +z the face; `big` is the huge white word (GOAL's place), `words` the subtitle.
## The letters are on the front face only (the frame's mesh has both faces: the sign is a slab); the node's mesh is made once.
static func build_free(holder: Node3D, width: float, big: String, words: String) -> Node3D:
	var scale := width / MIN_WIDTH
	var height := MIN_WIDTH * HEIGHT_OVER_WIDTH
	var key := "%.2f" % MIN_WIDTH
	if not _meshes.has(key): _meshes[key] = _sign_mesh(MIN_WIDTH, height)
	var board := Node3D.new()
	board.name = "ShowSign"
	board.scale = Vector3.ONE * scale
	var body := MeshInstance3D.new()
	body.name = "Board"
	body.mesh = _meshes[key]
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(body)
	_letters(board, MIN_WIDTH, height, words, big, false)
	holder.add_child(board)
	return board

static func _corners(rect: Rect2) -> Array[Vector2]:
	return [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]

# ------------------------------------------------------------------ the sign's mesh

static func _sign_mesh(width: float, height: float) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var body := batch.group("body")
	var panel := batch.group("panel")
	var bulbs := batch.group("bulb")
	var loops := {}
	for point: Array in SECTION:
		var inset := float(point[0])
		if not loops.has(inset): loops[inset] = _loop(width, height, inset)
	for side: float in [1.0, -1.0]:
		for index in SECTION.size() - 1:
			var from: Array = SECTION[index]
			var to: Array = SECTION[index + 1]
			_strip(body, loops[float(from[0])], loops[float(to[0])], float(from[0]), float(to[0]), float(from[1]), float(to[1]), side, to[2])
	var inner: PackedVector2Array = loops[PANEL_D]
	for side: float in [1.0, -1.0]:
		var centre := panel.add(Vector3(0.0, height * 0.45, PANEL_Z * side), Vector3(0.0, 0.0, side), Vector2(0.0, height * 0.45), Color.WHITE)
		var first := -1
		var previous := -1
		for point: Vector2 in inner:
			var vertex := panel.add(Vector3(point.x, point.y, PANEL_Z * side), Vector3(0.0, 0.0, side), point * Vector2(side, 1.0), Color.WHITE)
			if first < 0: first = vertex
			if previous >= 0: panel.triangle(centre, previous, vertex, Vector3(0.0, 0.0, side))
			previous = vertex
		panel.triangle(centre, previous, first, Vector3(0.0, 0.0, side))
	# the marquee: bulbs on the purple border with a rivet between each two
	var band := _loop(width, height, BAND_D)
	var spots := _spaced(band, BULB_GAP)
	for side: float in [1.0, -1.0]:
		for spot: Dictionary in spots:
			var place := Vector3(spot.p.x, spot.p.y, (BAND_Z + 0.05) * side)
			var tint := Color(float(int(spot.k) % 3) * 0.5, float(spot.f), float(int(spot.k) % 2), 1.0)
			_ball(bulbs, place, 0.15, tint, 8, 5)
			var next: Dictionary = spots[(int(spot.k) + 1) % spots.size()]
			var middle := ((spot.p as Vector2) + (next.p as Vector2)) * 0.5
			_ball(body, Vector3(middle.x, middle.y, BAND_Z * side), 0.065, WHITE, 6, 3, 0.55 * side)
	return batch.commit({"body": _body_material(), "panel": _shader("panel"), "bulb": _shader("bulb")})

## The pentagon of the sign (a V point at the bottom, tip at the origin) inset by `inset` (<= 0) from the rim, its corners rounded; always the same number of points.
static func _loop(width: float, height: float, inset: float) -> PackedVector2Array:
	var shoulder := height * SHOULDER
	var half := width * 0.5
	var sharp: Array[Vector2] = [Vector2(-half, height), Vector2(-half, shoulder), Vector2(0.0, 0.0), Vector2(half, shoulder), Vector2(half, height)]
	# a sharp corner pushed along the miter of its two edges
	var count := sharp.size()
	var moved: Array[Vector2] = []
	for index in count:
		var before := sharp[(index + count - 1) % count]
		var here := sharp[index]
		var after := sharp[(index + 1) % count]
		var n0 := _outward(here - before)
		var n1 := _outward(after - here)
		moved.append(here + (n0 + n1) / (1.0 + n0.dot(n1)) * inset)
	var out := PackedVector2Array()
	for index in count:
		var before := moved[(index + count - 1) % count]
		var here := moved[index]
		var after := moved[(index + 1) % count]
		var radius := maxf(float(CORNER[index]) + inset, 0.12)
		var to_before := (before - here).normalized()
		var to_after := (after - here).normalized()
		var turn := acos(clampf(to_before.dot(to_after), -1.0, 1.0))
		var reach := minf(radius / tan(turn * 0.5), 0.45 * minf(before.distance_to(here), after.distance_to(here)))
		var a := here + to_before * reach
		var b := here + to_after * reach
		for step in LOOP_ARC + 1:
			var s := float(step) / float(LOOP_ARC)
			out.append(a * (1.0 - s) * (1.0 - s) + here * 2.0 * s * (1.0 - s) + b * s * s)
	return out

static func _outward(edge: Vector2) -> Vector2:
	return Vector2(edge.y, -edge.x).normalized()

## One strip of the section between two loops (`from` at the inset d0 and height z0, `to` at d1 and z1; z off the middle plane of the face `side`): the quads round the
## loop, smooth along it, a crease at each end.
static func _strip(group: BlockMesh.Group, from: PackedVector2Array, to: PackedVector2Array, d0: float, d1: float, z0: float, z1: float, side: float, color: Color) -> void:
	var normal := Vector2(z1 - z0, -(d1 - d0)).normalized()
	if normal.length_squared() < 0.5: return
	var count := from.size()
	var first_ring := PackedInt32Array()
	var second_ring := PackedInt32Array()
	for index in count:
		var out := _outward(from[(index + 1) % count] - from[(index + count - 1) % count])
		var direction := Vector3(out.x * normal.x, out.y * normal.x, normal.y * side)
		first_ring.append(group.add(Vector3(from[index].x, from[index].y, z0 * side), direction, from[index], color))
		second_ring.append(group.add(Vector3(to[index].x, to[index].y, z1 * side), direction, to[index], color))
	for index in count:
		var next := (index + 1) % count
		group.quad(first_ring[index], first_ring[next], second_ring[next], second_ring[index], group.n[first_ring[index]])

## Evenly spaced places along a closed loop: [{p, f (0..1 along it), k}].
static func _spaced(loop: PackedVector2Array, gap: float) -> Array[Dictionary]:
	var count := loop.size()
	var total := 0.0
	for index in count: total += loop[index].distance_to(loop[(index + 1) % count])
	var places := int(round(total / gap))
	var out: Array[Dictionary] = []
	var run := 0.0
	var index := 0
	var edge := loop[0].distance_to(loop[1])
	for k in places:
		var target := total * (float(k) + 0.5) / float(places)
		while run + edge < target and index < count - 1:
			run += edge
			index += 1
			edge = loop[index].distance_to(loop[(index + 1) % count])
		var amount := clampf((target - run) / maxf(edge, 1e-6), 0.0, 1.0)
		out.append({"p": loop[index].lerp(loop[(index + 1) % count], amount), "f": target / total, "k": k})
	return out

## A small ball: a whole sphere (`dome` 0) or the half of one that stands on a surface facing `dome`'s sign in z (its height `abs(dome)` of the radius, open below).
static func _ball(group: BlockMesh.Group, centre: Vector3, radius: float, color: Color, around: int, rings: int, dome := 0.0) -> void:
	var lift := 1.0 if dome == 0.0 else signf(dome)
	var reach := radius if dome == 0.0 else radius * absf(dome)
	var grid: Array[PackedInt32Array] = []
	for ring in range(0, rings + 1):
		var polar := (PI if dome == 0.0 else PI * 0.5) * float(ring) / float(rings) # 0 at the +z pole
		var row := PackedInt32Array()
		for step in around:
			var angle := TAU * float(step) / float(around)
			var direction := Vector3(sin(polar) * cos(angle), sin(polar) * sin(angle), cos(polar) * lift)
			row.append(group.add(centre + direction * Vector3(radius, radius, reach), direction, Vector2.ZERO, color))
		grid.append(row)
	for ring in range(0, rings):
		for step in around:
			var next := (step + 1) % around
			var a := grid[ring][step]
			group.quad(a, grid[ring][next], grid[ring + 1][next], grid[ring + 1][step], group.n[a])

# ------------------------------------------------------------------ the letters

static func _letters(board: Node3D, width: float, height: float, words: String, big := "GOAL", both := true) -> void:
	var inner := _loop(width, height, PANEL_D)
	var inner_top := height + PANEL_D - MARGIN
	var goal := _fitted(big, height * GOAL_HEIGHT, width * GOAL_WIDTH_MAX, LETTER_DEPTH, "goal", inner, inner_top)
	var goal_y: float = float(goal.top) - (goal.size as Vector3).y * 0.5
	var title := _fit_title(words)
	var base: float = float(goal.top) - (goal.size as Vector3).y - GAP_ABOVE_GOAL
	var lines := title.count("\n") + 1
	var sub: Dictionary = {}
	var sub_y := 0.0
	if title != "":
		sub = _fitted(title, height * 0.075 * float(lines) + 0.2 * float(lines - 1), width * 0.5, LETTER_DEPTH * 0.6, "sub", inner, base)
		sub_y = float(sub.top) - (sub.size as Vector3).y * 0.5
	for face: float in ([1.0, -1.0] if both else [1.0]):
		var mount := Node3D.new()
		mount.name = "Face" if face > 0.0 else "BackFace"
		mount.rotation.y = 0.0 if face > 0.0 else PI
		board.add_child(mount)
		_place(mount, goal, Vector3(0.0, goal_y, PANEL_Z - 0.03 + LETTER_DEPTH * 0.5), "Goal")
		if not sub.is_empty(): _place(mount, sub, Vector3(0.0, sub_y, PANEL_Z - 0.03 + LETTER_DEPTH * 0.3), "Subtitle")

## A word whose top edge is at `top` and whose box lies fully inside the recess panel `inner` with MARGIN to spare (its width shrinks until it does): {mesh, centre, size, material, top}.
static func _fitted(words: String, height: float, max_width: float, depth: float, kind: String, inner: PackedVector2Array, top: float) -> Dictionary:
	var word := _text(words, height, max_width, depth, kind)
	for attempt in 24:
		var box: Vector3 = word.size
		var half := minf(_half_width_at(inner, top - box.y), _half_width_at(inner, top)) - MARGIN
		if half >= box.x * 0.5: break
		word = _text(words, height * 0.96, minf(max_width, box.x) * 0.96, depth, kind)
		height *= 0.96
	word["top"] = top
	return word

static func _place(parent: Node3D, word: Dictionary, at: Vector3, label: String) -> void:
	var item := MeshInstance3D.new()
	item.name = label
	item.mesh = word.mesh
	item.material_override = word.material
	item.position = at - (word.centre as Vector3)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)

## One word as an extruded TextMesh scaled to `height` (m) tall, or `max_width` when that is narrower: {mesh, centre (of its bounds), material}.
static func _text(words: String, height: float, max_width: float, depth: float, kind: String) -> Dictionary:
	var mesh := TextMesh.new()
	mesh.font = ShowTheme.font()
	mesh.text = words
	mesh.font_size = 96
	mesh.pixel_size = 0.01
	mesh.depth = depth
	mesh.curve_step = 0.4
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box := mesh.get_aabb()
	var scale := minf(height / maxf(box.size.y, 1e-4), max_width / maxf(box.size.x, 1e-4))
	mesh.pixel_size = 0.01 * scale
	box = mesh.get_aabb() # the extrusion is not scaled with the pixel size: the depth stays in metres
	var material := _shader("goal" if kind == "goal" else "sub").duplicate() as ShaderMaterial
	material.set_shader_parameter("y_span", Vector2(box.position.y, box.end.y))
	return {"mesh": mesh, "centre": box.get_center(), "size": box.size, "material": material}

## The subtitle as lines: upper case, split in two at the space nearest the middle when it is long.
static func _fit_title(words: String) -> String:
	var title := words.strip_edges().to_upper()
	if title.length() <= 11 or not " " in title: return title
	var best := -1
	for index in title.length():
		if title[index] == " " and (best < 0 or absi(index - title.length() / 2) < absi(best - title.length() / 2)): best = index
	return title.substr(0, best) + "\n" + title.substr(best + 1)

## Half the width of the convex `loop` at height `y` (0 when `y` is outside it).
static func _half_width_at(loop: PackedVector2Array, y: float) -> float:
	var best := 0.0
	for index in loop.size():
		var a := loop[index]
		var b := loop[(index + 1) % loop.size()]
		if (a.y - y) * (b.y - y) <= 0.0 and absf(a.y - b.y) > 1e-6:
			best = maxf(best, absf(a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)))
	return best

# ------------------------------------------------------------------ the gantry

## Two pylons beside the sign (PYLON_GAP clear of its edges, on the deck or on columns down to `foot`), the beam over them and four rods from the beam down to the sign's top edge.
static func _gantry_mesh(width: float, centre: float, foot: float, tip: float, height: float, plinth: bool) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var reach := width * 0.5 + PYLON_GAP
	var rim := tip + height
	var top := rim + ROD_LENGTH
	for side: float in [-1.0, 1.0]:
		var x := centre + side * reach
		var length := top - foot
		var start := foot + (0.5 if plinth else 0.0) # the shaft starts inside the plinth: no two faces share a plane
		batch.box(Transform3D(Basis.IDENTITY, Vector3(x, (start + top) * 0.5, 0.0)), Vector3(PYLON, top - start, PYLON), 0.3, 3, "body", "body", PYLON_COLOUR)
		if plinth: batch.box(Transform3D(Basis.IDENTITY, Vector3(x, foot + 0.27, 0.0)), Vector3(PYLON + 0.5, 0.6, PYLON + 0.5), 0.1, 2, "body", "body", PYLON_LIGHT) # sunk 3 cm into the deck
		var bands := int(length / 4.0)
		for k in bands:
			batch.box(Transform3D(Basis.IDENTITY, Vector3(x, foot + length * float(k + 1) / float(bands + 1), 0.0)), Vector3(PYLON + 0.18, 0.3, PYLON + 0.18), 0.07, 2, "body", "body", WHITE)
		batch.box(Transform3D(Basis.IDENTITY, Vector3(x, top + 0.15, 0.0)), Vector3(RainbowArch.ribbon() + 0.3, 0.5, RainbowArch.ribbon() + 0.3), 0.1, 2, "body", "body", AMBER)
	batch.box(Transform3D(Basis.IDENTITY, Vector3(centre, top - 0.1, 0.0)), Vector3(reach * 2.0, 0.6, 0.6), 0.28, 3, "body", "body", PYLON_LIGHT)
	RainbowArch.add(batch.group("body"), centre, top + 0.35, reach, maxf(3.2, reach * ARCH_RISE))
	for side: float in [-1.0, 1.0]:
		for inset: float in [1.4, 4.2]:
			var x := centre + side * (width * 0.5 - inset)
			var length := top - 0.3 - rim + 0.04 # from 4 cm into the sign's top edge to 10 cm into the beam
			batch.box(Transform3D(Basis.IDENTITY, Vector3(x, rim - 0.04 + length * 0.5, 0.0)), Vector3(0.1, length, 0.1), 0.0, 1, "body", "body", ROD)
			batch.box(Transform3D(Basis.IDENTITY, Vector3(x, top - 0.45, 0.0)), Vector3(0.4, 0.22, 0.4), 0.06, 2, "body", "body", AMBER)
	return batch.commit({"body": _body_material()})

# ------------------------------------------------------------------ materials

## The painted parts (vertex colours, a glow of their own so the yellow stays yellow on the shaded side).
static func _body_material() -> ShaderMaterial:
	return _shader("body")

## The shader's materials by name: body, panel, bulb, goal (white letters), sub (the subtitle's amber).
static func _shader(name: String) -> ShaderMaterial:
	if not _materials.has(name):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		match name:
			"body": material.set_shader_parameter("kind", 3)
			"panel": material.set_shader_parameter("kind", 0)
			"bulb": material.set_shader_parameter("kind", 2)
			"goal":
				material.set_shader_parameter("kind", 1)
				material.set_shader_parameter("front", CandyLook.PROP_WHITE)
				material.set_shader_parameter("side", CandyLook.PROP_AMBER)
			"sub":
				material.set_shader_parameter("kind", 1)
				material.set_shader_parameter("front", SUBTITLE_FRONT)
				material.set_shader_parameter("side", SUBTITLE_SIDE)
		_materials[name] = material
	return _materials[name]
