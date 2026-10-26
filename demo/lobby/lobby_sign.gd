extends RefCounted
## The signs of the lobby circles (client/walk_in_markers.gd), in the show's UI style (client/show_theme.gd: Lilita One, dark pills with a light edge) and the frame
## family of the GOAL sign (style/goal_sign.gd: a thick bevelled band round a dark recess). One sign per circle, standing behind it and facing the yard; every one stands on masonry:
##   round sign   a plate: a rounded band in the colour of its round's plate (lobby/pick_plate.gd KINDS: race mint, survival blue, final purple), a cream line, the dark pill with the title in white and
##                the rule line in cream under it. A front circle's plate stands on a corbel on a masonry pillar (the race pillars' two greys, whole courses of 0.5 m,
##                rounded blocks); the REAR row's plates stand side by side on ONE tan beam (`build_rear`) carried by a few masonry piers in the gaps between plates and by THE SHOW's pylon
##   THE SHOW     the GOAL sign's shield (V point down, yellow band, purple border with the marquee bulbs, brick recess, the huge mint word and the gold subtitle) scaled to the hero's width, on a
##                tall masonry pylon that rises behind it and touches its back
## Look only: no collision, but everything is connected: the pillar stands on the tiles (its lowest course 2 cm in them), the corbel sits on the pillar, the plate on the corbel.
## The plate's face is the sight line the lobby checks walk (`tools/party_look_check.gd`): the front face of the band is at z = FACE_Z of the circle, `lift` m up.
const BlockMesh := preload("res://style/block_mesh.gd")
const BlockKit := preload("res://style/block_kit.gd")
const RaceSurfaces := preload("res://style/race_surfaces.gd")
const PillarKit := preload("res://style/pillar_kit.gd")
const GoalSign := preload("res://style/goal_sign.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const FACE_Z := -1.85           ## m: the front of the sign plate behind the circle's middle (the ring is 1.55 m; network/walk_in_lobby.gd RING_RADIUS + 0.3)
const PILLAR_DEPTH := 0.8       ## m: the pillar stands from FACE_Z - 0.1 back
const PILLAR_FRONT := 1.0       ## m wide under a front plate
const PILLAR_REAR := 1.2        ## ... under a rear plate
const PLATE_DEPTH := 0.2
const CORBEL := 0.22            ## m: the corbel's height under the plate
const SINK := 0.02              ## m: the pillar's lowest course stands this far in the tiles
const OVERLAP := 0.03           ## m: how far a part stands in the part it stands on
const HERO_WIDTH := 5.0         ## m: THE SHOW's shield
const HERO_PYLON := Vector3(1.8, 6.0, 1.2)
const HERO_BIG := "THE SHOW"
const SLANT := ShowTheme.SLANT
const CREAM := Color("#f7edcf")
const TAN := Color("#cdb57f")
const CandyCourse := preload("res://style/candy_course.gd")
const KEY := BlockKit.KEY_TALL
const Layout := preload("res://network/walk_in_lobby.gd")
const PickPlate := preload("res://lobby/pick_plate.gd")

## The sign of `entry` (network/walk_in_lobby.gd shown_pads: title, subtitle, board, lift, kind) under `root` (the circle's middle on the floor): its meshes and texts. `seed` varies the masonry.
static func build(root: Node3D, entry: Dictionary, seed: int) -> void:
	var lift := float(entry.get("lift", 1.5))
	if str(entry.get("kind", "")) == "show":
		_hero(root, entry)
		return
	var board: Vector2 = entry.get("board", Vector2(3.0, 1.4))
	var batch := BlockMesh.Batch.new()
	var key: String = RaceSurfaces.keys(PillarKit.TONE, 1)[1]
	if not is_rear(entry): # a corbel on a pillar (a rear plate stands on the shared beam)
		var pillar_top := lift - CORBEL + OVERLAP
		var pillar_z := FACE_Z - 0.1 - PILLAR_DEPTH * 0.5
		var height := pillar_top + SINK
		PillarKit.support(batch, Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5 - SINK, pillar_z)), Vector3(PILLAR_FRONT, height, PILLAR_DEPTH), -height * 0.5 + 0.002)
		batch.box(Transform3D(Basis.IDENTITY, Vector3(0.0, lift - CORBEL * 0.5, pillar_z + 0.05)), Vector3(PILLAR_FRONT + 0.7, CORBEL, PILLAR_DEPTH + 0.1), 0.06, 2, KEY, KEY, TAN)
	var look: Dictionary = PickPlate.KINDS.get(str(entry.get("kind", "")), PickPlate.KINDS.race)
	_plate(batch, board, lift, look.band)
	var body := MeshInstance3D.new()
	body.name = "Sign"
	body.mesh = batch.commit({KEY: BlockKit.tall_material(), key: RaceSurfaces.material(key)})
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	_words(root, entry, board, lift)

## Whether the circle's sign is one of the rear row's (on the shared beam).
static func is_rear(entry: Dictionary) -> bool:
	return str(entry.get("kind", "")) != "show" and float(entry.get("lift", 1.5)) > 2.5

## The rear row's beam and piers under `parent` (world space, the node at the origin): one tan beam under the rear plates on each side of THE SHOW, from its pylon out to the last plate, and a masonry
## pier in every second gap between plates counted from the pylon (the beam hangs between the pylon and the first pier, and over the last plate's end by a plate width at most).
static func build_rear(parent: Node3D, entries: Array) -> void:
	var hero := {}
	var rear: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) == "show": hero = entry
		elif is_rear(entry): rear.append(entry)
	if hero.is_empty() or rear.is_empty(): return
	var batch := BlockMesh.Batch.new()
	var key: String = RaceSurfaces.keys(PillarKit.TONE, 1)[1]
	var middle: Vector3 = hero.center
	var lift := float(rear[0].lift)
	var depth := PILLAR_DEPTH + 0.2
	var piers := 0
	for side: float in [-1.0, 1.0]:
		var row: Array = rear.filter(func(entry: Dictionary) -> bool: return (entry.center.x - middle.x) * side > 0.0)
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a.center.x - middle.x) < absf(b.center.x - middle.x))
		if row.is_empty(): continue
		var last: Dictionary = row.back()
		var from := middle.x + side * (HERO_PYLON.x * 0.5 - 2.0 * OVERLAP)
		var to: float = last.center.x + side * ((last.board as Vector2).x * 0.5 + 0.2)
		var length := absf(to - from)
		var beam_z := middle.z + FACE_Z - depth * 0.5
		batch.box(Transform3D(Basis.IDENTITY, Vector3((from + to) * 0.5, middle.y + lift - CORBEL * 0.5, beam_z)), Vector3(length, CORBEL, depth), 0.06, 2, KEY, KEY, TAN)
		for index in range(0, row.size() - 1, 2): # a pier in the gap after the 1st, 3rd ... plate counted from THE SHOW
			var gap: float = (row[index].center.x + row[index + 1].center.x) * 0.5
			var height := lift - CORBEL + OVERLAP + SINK
			PillarKit.support(batch, Transform3D(Basis.IDENTITY, Vector3(gap, middle.y + height * 0.5 - SINK, beam_z)), Vector3(PILLAR_REAR, height, PILLAR_DEPTH), -height * 0.5 + 0.002)
			piers += 1
	var body := MeshInstance3D.new()
	body.name = "RearBeam"
	body.mesh = batch.commit({KEY: BlockKit.tall_material(), key: RaceSurfaces.material(key)})
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(body)

## What the lobby's sight-line check walks (tools/party_look_check.gd), circle-local: {size, bottom, rows, columns, solids}: the plate (THE SHOW: the shield's bounding rectangle) with the heights
## (shares of its height) of its two lines of words and the columns (shares of its width) they cover, and the masonry that can stand in a view: {z (its front face), width, bottom, top}.
static func sight(entry: Dictionary) -> Dictionary:
	var lift := float(entry.get("lift", 1.5))
	if str(entry.get("kind", "")) == "show":
		var half_thick := 0.64 * HERO_WIDTH / GoalSign.MIN_WIDTH
		return {"size": Layout.BOARD_BIG, "bottom": lift, "rows": [0.65, 0.4], "columns": [-0.25, 0.0, 0.25], "solids": [{"z": FACE_Z - 2.0 * half_thick, "width": HERO_PYLON.x, "bottom": 0.0, "top": HERO_PYLON.y}]}
	var board: Vector2 = entry.get("board", Vector2(3.0, 1.4))
	var solids: Array = []
	if is_rear(entry): solids.append({"z": FACE_Z, "width": board.x + 0.3, "bottom": lift - CORBEL, "top": lift}) # the shared beam under the plate (the piers stand in the gaps, behind the circles)
	else: solids.append_array([{"z": FACE_Z, "width": PILLAR_FRONT + 0.7, "bottom": lift - CORBEL, "top": lift}, {"z": FACE_Z - 0.1, "width": PILLAR_FRONT, "bottom": 0.0, "top": lift - CORBEL}])
	return {"size": board, "bottom": lift, "rows": [0.63, 0.27], "columns": [-0.4, -0.2, 0.0, 0.2, 0.4], "solids": solids}

## The plate: band, cream line and dark pill (front of the band at FACE_Z).
static func _plate(batch: BlockMesh.Batch, board: Vector2, lift: float, band: Color) -> void:
	var middle := lift + board.y * 0.5
	# the band stands OVERLAP in the corbel (or beam) it is on
	batch.box(Transform3D(Basis.IDENTITY, Vector3(0.0, middle - OVERLAP * 0.5, FACE_Z - PLATE_DEPTH * 0.5)), Vector3(board.x, board.y + OVERLAP, PLATE_DEPTH), 0.12, 2, KEY, KEY, band)
	batch.box(Transform3D(Basis.IDENTITY, Vector3(0.0, middle, FACE_Z + 0.02 - PLATE_DEPTH * 0.5)), Vector3(board.x - 0.16, board.y - 0.16, PLATE_DEPTH), 0.1, 2, KEY, KEY, CREAM)
	batch.box(Transform3D(Basis.IDENTITY, Vector3(0.0, middle, FACE_Z + 0.035 - PLATE_DEPTH * 0.5)), Vector3(board.x - 0.3, board.y - 0.3, PLATE_DEPTH), 0.14, 2, KEY, KEY, (CandyCourse.scheme().s as Dictionary).deep) # a saturated deep purple panel (white lettering), never black

## The title (one or two lines, white, slanted like the HUD's words) and the rule line (cream, up to two lines) on the pill.
static func _words(root: Node3D, entry: Dictionary, board: Vector2, lift: float) -> void:
	var front := FACE_Z + 0.035 + 0.012
	var title := _text(str(entry.title), Color.WHITE, board.x - 0.6, board.y * 0.43, 2, 0.46)
	title.name = "Title"
	title.transform = Transform3D(Basis(Vector3.RIGHT, Vector3(SLANT, 1.0, 0.0), Vector3.BACK), Vector3(0.0, lift + board.y * 0.63, front))
	root.add_child(title)
	var rule := _text(str(entry.subtitle), CREAM, board.x - 0.55, board.y * 0.27, 2, 0.2)
	rule.name = "Rule"
	rule.transform = Transform3D(Basis(Vector3.RIGHT, Vector3(SLANT, 1.0, 0.0), Vector3.BACK), Vector3(0.0, lift + board.y * 0.27, front))
	root.add_child(rule)

## Flat words in Lilita One that fit `width` m wide and `height` m tall in at most `lines` lines (split between words where the longest line is shortest; the largest size wins, fewer lines on a
## tie), capitals at most `cap` m high.
static func _text(value: String, color: Color, width: float, height: float, lines: int, cap: float) -> Label3D:
	var label := Label3D.new()
	var font := ShowTheme.font()
	label.font = font
	label.pixel_size = 0.0025
	var words := PackedStringArray()
	for word in value.to_upper().split(" ", false):
		if word == "·" and not words.is_empty(): words[words.size() - 1] += " ·" # a separator stays at the end of its line
		else: words.append(word)
	var limit := int(cap / ShowTheme.CAP / label.pixel_size)
	var best := 0
	var best_text := " ".join(words)
	for count in range(1, mini(lines, words.size()) + 1):
		var rows := _balanced(words, count, font)
		var fit := mini(limit, int(height / (count * 1.1 * label.pixel_size)))
		while fit > 24 and _widest(rows, font, fit) * label.pixel_size > width: fit -= 2
		if fit > best:
			best = fit
			best_text = "\n".join(rows)
	label.text = best_text
	label.font_size = best
	label.modulate = color
	label.outline_size = maxi(int(best * 0.09), 2)
	label.outline_modulate = Color(0.02, 0.03, 0.08, 0.95)
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.line_spacing = -0.1 * best
	label.render_priority = 2
	return label

static func _widest(rows: PackedStringArray, font: Font, size: int) -> float:
	var widest := 0.0
	for row in rows: widest = maxf(widest, font.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest

## `words` in `count` rows (1 or 2) with the shortest longest row.
static func _balanced(words: PackedStringArray, count: int, font: Font) -> PackedStringArray:
	if count <= 1 or words.size() < 2: return PackedStringArray([" ".join(words)])
	var best := PackedStringArray()
	var best_width := INF
	for cut in range(1, words.size()):
		var rows := PackedStringArray([" ".join(words.slice(0, cut)), " ".join(words.slice(cut))])
		var widest := _widest(rows, font, 64)
		if widest < best_width:
			best_width = widest
			best = rows
	return best

## THE SHOW: the GOAL family's shield, its V tip `lift` over the floor, on a tall masonry pylon touching its back.
static func _hero(root: Node3D, entry: Dictionary) -> void:
	var tip := float(entry.get("lift", 4.0))
	var shield := GoalSign.build_free(root, HERO_WIDTH, HERO_BIG, str(entry.subtitle))
	var half_thick := 0.64 * HERO_WIDTH / GoalSign.MIN_WIDTH # the frame's face stands this far off the shield's middle plane
	shield.name = "Slot_ShowSign" # one assembly for the mesh lint: the letters stand in the frame (`GoalSign`)
	shield.position = Vector3(0.0, tip, FACE_Z - half_thick)
	var back := FACE_Z - 2.0 * half_thick
	var batch := BlockMesh.Batch.new()
	var key: String = RaceSurfaces.keys(PillarKit.TONE, 1)[1]
	var centre := Vector3(0.0, HERO_PYLON.y * 0.5 - SINK, back + OVERLAP * 1.3 - HERO_PYLON.z * 0.5) # touches the shield's back, 4 cm into it
	PillarKit.support(batch, Transform3D(Basis.IDENTITY, centre), Vector3(HERO_PYLON.x, HERO_PYLON.y + SINK, HERO_PYLON.z), -(HERO_PYLON.y + SINK) * 0.5 + 0.002)
	var body := MeshInstance3D.new()
	body.name = "Pylon"
	body.mesh = batch.commit({key: RaceSurfaces.material(key)})
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
