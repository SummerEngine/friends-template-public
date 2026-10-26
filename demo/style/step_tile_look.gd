extends RefCounted
## The look of the step tiles (levels/step_tiles.gd), client only: one MultiMesh per tile kind (a handful of draw calls for a whole
## arena), every tile one instance of a hexagonal prism with a flat rim and a small bevel. A tile follows its mode: standing, shaking and
## turning warning-red until it goes, falling away under the arena (nothing shrinks or pops out: it tumbles down and rests far below). Pure look: no collision, nothing here decides anything. The floors the camera sits under
## are hidden (set_ghosted: levels/step_tiles.gd ghost_floors): their instances are scaled to nothing, so no extra draw call and the slabs overhead never cover the view.
##   plain     in the show (the party look) three tones of the brand's first colour (style/party_look.gd `tiles`); else the brand colours in three tones (the first colour with colour in it, the second brand colour, else a paler tone of it, and the
##             paler tone of the first: three tones are what a hexagon grid needs so that no two neighbours match) in a darker rim
##             With labels in the cast (show.rounds.r15.label, TeamCast.round_labels) the plain tiles wear them in turn: a cream card with the word in ink on the tile, one MultiMesh per word
##   logo      the team logo on a cream plate in a rim of the brand colour (concentric hexagons when the cast has no logo)
##   obstacle  the cast's obstacle `slot` (picture covering the hexagon, cropped by it, else hazard stripes in its colour) in a red rim; with no
##             such obstacle in the cast, plain hazard stripes: the rival kind
const TeamCast := preload("res://style/team_cast.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const HexGrid := preload("res://levels/hex_grid.gd")
const Party := preload("res://style/party_look.gd")
const StageTileLook := preload("res://style/stage_tile_look.gd")
const CandyLook := preload("res://style/candy_look.gd")

const GAP := 0.07            ## m between two tiles' looks (the collision has none)
const RIM := 0.1             ## m (along a corner) of the flat rim around the plate that wears the picture
const BEVEL := CandyLook.CHAMFER_SLAB ## m the edge steps down and in: the candy slab's chamfer (the tile rounds' look, style/stage_tile_look.gd)
const TEX := 256
const WARN := Color(1.0, 0.28, 0.2)
const DEFAULT_ACCENT := Color("#2c4bff")
const CREAM := Color("#f4f0e6")
const DANGER := Color("#d7261e")
const INK := Color("#1b1d24")
const SIGN_YELLOW := Color("#ffd23f")
const SHAKE := 0.045         ## m of shaking at full warning
const FALL_GRAVITY := 17.0
const FALL_TIME := 2.4       ## s a vanished tile falls before it rests under the arena (levels/step_tiles.gd: the mode is MODE_FALL for that long)
const NIGHT_EDGE := 0.5      ## the night look: how strongly the rim of a tile shines
const LABEL_JOIN := "\t"      ## a group key of a labelled tile: its kind, this, the label number (a kind is one letter of a level's rows, never a tab)
const LABEL_ROUND := "r15"  ## the round whose plain tiles wear the cast's labels
const LABEL_SEED := 15       ## the labels are dealt in shuffled rounds (every word once, then again) from this seed: the same on every screen
const CARD_LIFT := 0.012     ## m the label card floats over the plate (more than the depth buffer can mix up), the letters on it
const LETTER_CURVE_STEP := 2.0 ## TextMesh curve detail: coarse is plenty at tile size and keeps a word to a few hundred triangles
const LETTER_FONT_SIZE := 64 ## TextMesh pixels: only the detail of the curves, the word is fitted to the card afterwards
const CARD_SPAN := Vector2(0.92, 0.46) ## half the card across the flat sides (share of the plate's apothem) and along the corners (share of its circumradius)
const WORD_SPAN := Vector2(0.86, 0.74) ## the word's room inside the card (shares of the card's width and height)
const WRAP_FROM := 9         ## a label this long with a space in it goes on two lines
static var _card_material: StandardMaterial3D
static var _letter_material: StandardMaterial3D
static var _letter_font: FontVariation

var _groups := {}            ## kind key -> {multi (MultiMesh), slots (tile index -> instance), base (Color per instance)}
var _slot_of := {}           ## tile index -> [kind key, instance]
var _last := PackedByteArray()
var _tiles: Array = []
var _by_floor: Array = []   ## floor index -> tile indices
var _hidden := PackedByteArray()        ## per tile: 1 while its floor is ghosted (the instance is scaled to nothing)
var _tau := PackedFloat32Array()        ## per tile: the last pose's tau and delay, to draw it again when its floor comes back
var _wait := PackedFloat32Array()

func build(level_root: Node3D, data: Dictionary) -> void:
	_tiles = data.tiles
	var pitch := float(data.pitch)
	var thick := float(data.thick)
	_last.resize(_tiles.size()) # all 0: standing, as built below
	_hidden.resize(_tiles.size())
	_tau.resize(_tiles.size())
	_wait.resize(_tiles.size())
	var kinds: Dictionary = data.kinds
	var labels := TeamCast.round_labels(LABEL_ROUND)
	var keys := _group_keys(kinds, labels)
	var counts := {}
	for key: String in keys: counts[key] = int(counts.get(key, 0)) + 1
	var colors := _plain_colors()
	var made := {} # kind -> its materials: the groups of one kind share them
	for key: String in counts:
		var kind := key.get_slice(LABEL_JOIN, 0)
		var spec: Dictionary = kinds[kind]
		if not made.has(kind): made[kind] = _materials(spec)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _tile_mesh((pitch - GAP) / sqrt(3.0), thick, made[kind], labels[int(key.get_slice(LABEL_JOIN, 1))] if key.contains(LABEL_JOIN) else "")
		multi.instance_count = int(counts[key])
		var node := MultiMeshInstance3D.new()
		node.name = "TileLook_" + key.replace(LABEL_JOIN, "_")
		node.multimesh = multi
		level_root.add_child(node)
		_groups[key] = {"multi": multi, "next": 0}
	for index in _tiles.size():
		var floor_index := int((_tiles[index] as Dictionary).floor)
		while _by_floor.size() <= floor_index: _by_floor.append([])
		(_by_floor[floor_index] as Array).append(index)
	for index in _tiles.size():
		var entry: Dictionary = _tiles[index]
		var group: Dictionary = _groups[keys[index]]
		var instance: int = group.next
		group.next = instance + 1
		var multi: MultiMesh = group.multi
		var base := Color.WHITE
		if str(kinds[entry.kind].look) == "plain":
			var cell: Vector2i = entry.cell
			base = colors[posmod(int((cell.x - cell.y) * 0.5) - cell.y + int(entry.floor), 3)]
		multi.set_instance_color(instance, base)
		multi.set_instance_transform(instance, Transform3D(Basis.IDENTITY, entry.p))
		_slot_of[index] = [keys[index], instance, base]

## The group of every tile: its kind, and for a plain tile of a round with labels "<kind><tab><label number>". The labels go round the plain tiles in shuffled
## rounds (every word once before any comes twice), so no word lines up with the three tones. No labels: every tile is its kind.
func _group_keys(kinds: Dictionary, labels: PackedStringArray) -> Array[String]:
	var keys: Array[String] = []
	var dealer := RandomNumberGenerator.new()
	dealer.seed = LABEL_SEED
	var bag: Array = []
	for entry: Dictionary in _tiles:
		var kind := str(entry.kind)
		if labels.is_empty() or str(kinds[kind].look) != "plain":
			keys.append(kind)
			continue
		if bag.is_empty():
			for number in labels.size(): bag.append(number)
			for at in range(bag.size() - 1, 0, -1): # a shuffle of the words
				var other := dealer.randi_range(0, at)
				var swap = bag[at]
				bag[at] = bag[other]
				bag[other] = swap
		keys.append("%s%s%d" % [kind, LABEL_JOIN, int(bag.pop_back())])
	return keys

## The three tones of the plain tiles: in the party look (the show) three tones of the brand's first colour (style/party_look.gd `tiles`), else the brand's own.
static func _plain_colors() -> Array:
	if Party.on(): return Party.palette().tiles
	var accent := TeamCast.brand_accent()
	var first := accent if accent.a > 0.0 else DEFAULT_ACCENT
	first = Color.from_hsv(first.h, minf(first.s * 1.12, 1.0), first.v * 0.86) # the room's light washes a colour out: a little deeper than the brand's
	var second := first.lerp(Color.WHITE, 0.62)
	for color in TeamCast.brand_colors():
		if absf(color.h - first.h) > 0.04 or absf(color.v - first.v) > 0.25 or absf(color.s - first.s) > 0.3:
			second = color
			break
	return [first, second, first.lerp(Color.WHITE, 0.4)]

## [top, rim and sides] materials of a kind. The rim's own colour is the material's albedo; the mesh darkens the bevel and the sides with vertex colours.
func _materials(spec: Dictionary) -> Array:
	var accent := TeamCast.brand_accent()
	var ring := accent if accent.a > 0.0 else DEFAULT_ACCENT
	if str(spec.look) == "plain" and not Party.night(): # a plain tile in daylight is the tile rounds' hexagon slab: glossy chamfer, own light, pink rim (the mesh's vertex shades darken the chamfer)
		return [StageTileLook.plain_material(false), StageTileLook.plain_material(false)]
	var top := StandardMaterial3D.new()
	top.vertex_color_use_as_albedo = true
	top.roughness = CandyLook.ROUGH_TILE
	var rim := StandardMaterial3D.new()
	rim.vertex_color_use_as_albedo = true
	rim.roughness = CandyLook.ROUGH_TILE
	rim.albedo_color = Color(0.82, 0.82, 0.84) # the tile's own tone, a little darker
	match str(spec.look):
		"logo":
			top.albedo_texture = _logo_texture(ring)
			rim.albedo_color = ring
		"obstacle":
			top.albedo_texture = _obstacle_texture(str(spec.slot))
			rim.albedo_color = DANGER
	if Party.night(): # the night look: dark tiles with a glowing edge in the accent (emission is not tinted by the tile's colour)
		top.roughness = 0.4
		top.metallic = 0.4
		rim.roughness = 0.4
		rim.metallic = 0.4
		rim.emission_enabled = true
		rim.emission = (Party.palette().p as Dictionary).main
		rim.emission_energy_multiplier = NIGHT_EDGE
	if top.albedo_texture != null: top.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return [top, rim]

## A tile as a mesh with its top at y = 0 (surface 0: the plate with the whole texture, surface 1: rim, bevel, sides and underside; with a `label` surface 2:
## the cream card on the plate and surface 3: the word on it, neither takes the tile's colour so the word reads on every tone),
## `outer` the circumradius of the hexagon at the foot of the bevel.
static func _tile_mesh(outer: float, thick: float, materials: Array, label := "") -> ArrayMesh:
	var edge := outer - BEVEL                  # where the flat rim ends and the bevel starts
	var plate := edge - RIM                    # the picture's hexagon
	var mesh := ArrayMesh.new()
	# plate: a fan, the texture laid over the plate's circumscribed square (the hexagon crops it left and right)
	var top := _Builder.new()
	var plate_corners := HexGrid.hex_corners(plate)
	for k in HexGrid.SIDES:
		var a := plate_corners[k]
		var b := plate_corners[(k + 1) % HexGrid.SIDES]
		top.triangle([Vector3.ZERO, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y)], Vector3.UP, [Color.WHITE], [_uv(Vector2.ZERO, plate), _uv(a, plate), _uv(b, plate)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top.arrays())
	mesh.surface_set_material(0, materials[0])
	var sides := _Builder.new()
	var rim_corners := HexGrid.hex_corners(edge)
	var foot_corners := HexGrid.hex_corners(outer)
	var step_down := Vector3(0.0, -BEVEL, 0.0)
	var low := Vector3(0.0, -thick, 0.0)
	for k in HexGrid.SIDES:
		var next := (k + 1) % HexGrid.SIDES
		var out := Vector2(sin(TAU * (k + 0.5) / HexGrid.SIDES), cos(TAU * (k + 0.5) / HexGrid.SIDES))
		var flat := Vector3(out.x, 0.0, out.y)
		var inner_a := Vector3(plate_corners[k].x, 0.0, plate_corners[k].y)
		var inner_b := Vector3(plate_corners[next].x, 0.0, plate_corners[next].y)
		var edge_a := Vector3(rim_corners[k].x, 0.0, rim_corners[k].y)
		var edge_b := Vector3(rim_corners[next].x, 0.0, rim_corners[next].y)
		var foot_a := Vector3(foot_corners[k].x, 0.0, foot_corners[k].y) + step_down
		var foot_b := Vector3(foot_corners[next].x, 0.0, foot_corners[next].y) + step_down
		sides.quad([inner_a, inner_b, edge_b, edge_a], Vector3.UP, 1.0)
		var slope := (flat * BEVEL + Vector3.UP * BEVEL * HexGrid.ROW).normalized() # the bevel drops BEVEL while it steps out BEVEL * ROW (across the flat)
		sides.quad([edge_a, edge_b, foot_b, foot_a], slope, 0.9)
		sides.quad([foot_a, foot_b, foot_b + low - step_down, foot_a + low - step_down], flat, 0.62)
		sides.triangle([Vector3(0.0, -thick, 0.0), foot_a + low - step_down, foot_b + low - step_down], Vector3.DOWN, [Color(0.45, 0.45, 0.45)], [])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sides.arrays())
	mesh.surface_set_material(1, materials[1])
	if label != "": _add_label(mesh, plate, label)
	return mesh

## The label as two more surfaces of `mesh` lying on the plate (2: the cream card, 3: the ink letters). The word is upright for a camera looking along -Z and
## reads along +X; it is fitted evenly into the card (never stretched): short words are big, long ones small, a long one with a space goes on two lines.
static func _add_label(mesh: ArrayMesh, plate: float, label: String) -> void:
	var half := Vector2(plate * HexGrid.ROW * CARD_SPAN.x, plate * CARD_SPAN.y)
	var cut := minf(half.x, half.y) * 0.25
	var corners: Array[Vector3] = [Vector3(-half.x + cut, CARD_LIFT, -half.y), Vector3(half.x - cut, CARD_LIFT, -half.y), Vector3(half.x, CARD_LIFT, -half.y + cut),
		Vector3(half.x, CARD_LIFT, half.y - cut), Vector3(half.x - cut, CARD_LIFT, half.y), Vector3(-half.x + cut, CARD_LIFT, half.y),
		Vector3(-half.x, CARD_LIFT, half.y - cut), Vector3(-half.x, CARD_LIFT, -half.y + cut)]
	var card := _Builder.new()
	for k in corners.size(): card.triangle([Vector3(0.0, CARD_LIFT, 0.0), corners[k], corners[(k + 1) % corners.size()]], Vector3.UP, [Color.WHITE], [])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, card.arrays())
	if _card_material == null:
		_card_material = StandardMaterial3D.new()
		_card_material.albedo_color = CREAM
		_card_material.roughness = 0.8
		_letter_material = StandardMaterial3D.new()
		_letter_material.albedo_color = INK
		_letter_material.roughness = 0.55
		_letter_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(mesh.get_surface_count() - 1, _card_material)
	var letters := _letters(label, half * 2.0 * WORD_SPAN)
	if letters.is_empty(): return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, letters)
	mesh.surface_set_material(mesh.get_surface_count() - 1, _letter_material)

## The arrays of `text` as flat letters lying on the card (+Y up, the top of the letters towards -Z), fitted evenly into `room` (x, z), centred on the origin;
## [] when the font gives no letters.
static func _letters(text: String, room: Vector2) -> Array:
	var shown := _two_lines(text) if text.length() >= WRAP_FROM else text
	var shaped := TextMesh.new()
	shaped.font = _font()
	shaped.font_size = LETTER_FONT_SIZE
	shaped.pixel_size = 0.01
	shaped.depth = 0.0 # flat letters: one face each (a few hundred triangles a word, shared by every tile that wears it)
	shaped.curve_step = LETTER_CURVE_STEP
	shaped.width = 2000.0
	shaped.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shaped.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shaped.text = shown
	var source: Array = shaped.get_mesh_arrays()
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX] if source.size() > Mesh.ARRAY_VERTEX and source[Mesh.ARRAY_VERTEX] is PackedVector3Array else PackedVector3Array()
	if vertices.is_empty(): return []
	var low := vertices[0]
	var high := vertices[0]
	for vertex: Vector3 in vertices:
		low = Vector3(minf(low.x, vertex.x), minf(low.y, vertex.y), minf(low.z, vertex.z))
		high = Vector3(maxf(high.x, vertex.x), maxf(high.y, vertex.y), maxf(high.z, vertex.z))
	var size := high - low
	if size.x <= 0.0001 or size.y <= 0.0001: return []
	var fit := minf(room.x / size.x, room.y / size.y)
	var centre := (low + high) * 0.5
	var placed := PackedVector3Array()
	for vertex: Vector3 in vertices: # the text plane (x right, y up, z towards the reader) laid down on the card: up -> -Z, towards the reader -> +Y
		placed.append(Vector3((vertex.x - centre.x) * fit, CARD_LIFT + 0.002, -(vertex.y - centre.y) * fit))
	var normals := PackedVector3Array()
	var given: Variant = source[Mesh.ARRAY_NORMAL] if source.size() > Mesh.ARRAY_NORMAL else null
	if given is PackedVector3Array and (given as PackedVector3Array).size() == vertices.size():
		for normal: Vector3 in (given as PackedVector3Array): normals.append(Vector3(normal.x, normal.z, -normal.y))
	else:
		normals.resize(vertices.size())
		normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = placed
	arrays[Mesh.ARRAY_NORMAL] = normals
	var indices: Variant = source[Mesh.ARRAY_INDEX] if source.size() > Mesh.ARRAY_INDEX else null
	if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty(): arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

## Archivo extra bold (as the printed signs): the game's Inter has overlapping contours that TextMesh cannot triangulate.
static func _font() -> Font:
	if _letter_font == null:
		_letter_font = FontVariation.new()
		_letter_font.base_font = SlotFrames.PRINT_FONT
		_letter_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _letter_font

## `label` on two lines, broken at the space nearest its middle (itself when it has none).
static func _two_lines(label: String) -> String:
	var best := -1
	for at in label.length():
		if label[at] == " " and (best < 0 or absi(at - label.length() / 2) < absi(best - label.length() / 2)): best = at
	return label.left(best) + "\n" + label.substr(best + 1) if best >= 0 else label

## The texture coordinate of the plate point `at` (x, z): the plate's circumscribed square (2 * circumradius) is the picture.
static func _uv(at: Vector2, plate: float) -> Vector2:
	return at / (2.0 * plate) + Vector2(0.5, 0.5)

## Triangles and quads with flat normals and vertex colours, wound clockwise as seen from the outside (Godot's front faces).
class _Builder extends RefCounted:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	## `paint`: [the vertex colour of the face]; `uv`: one texture coordinate per corner, or none.
	func triangle(corners: Array, outward: Vector3, paint: Array, uv: Array) -> void:
		var first := vertices.size()
		for index in 3:
			vertices.append(corners[index])
			normals.append(outward)
			colors.append(paint[0])
			uvs.append(uv[index] if not uv.is_empty() else Vector2.ZERO)
		var flip: bool = (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(outward) > 0.0
		if flip: indices.append_array(PackedInt32Array([first, first + 2, first + 1]))
		else: indices.append_array(PackedInt32Array([first, first + 1, first + 2]))

	## `shade`: the vertex colour (grey) of the whole face.
	func quad(corners: Array, outward: Vector3, shade: float) -> void:
		var paint := [Color(shade, shade, shade)]
		triangle([corners[0], corners[1], corners[2]], outward, paint, [])
		triangle([corners[0], corners[2], corners[3]], outward, paint, [])

	func arrays() -> Array:
		var result := []
		result.resize(Mesh.ARRAY_MAX)
		result[Mesh.ARRAY_VERTEX] = vertices
		result[Mesh.ARRAY_NORMAL] = normals
		result[Mesh.ARRAY_COLOR] = colors
		result[Mesh.ARRAY_INDEX] = indices
		if uvs.size() == vertices.size() and not uvs.is_empty(): result[Mesh.ARRAY_TEX_UV] = uvs
		return result

# ------------------------------------------------------------------ textures

## The logo on cream, inside the hexagon the plate crops (a square of 60 % of the picture's width fits it).
func _logo_texture(ring: Color) -> Texture2D:
	var image := Image.create_empty(TEX, TEX, false, Image.FORMAT_RGBA8)
	image.fill(CREAM if TeamCast.logo_backing().get_luminance() > 0.5 else TeamCast.logo_backing()) # cream behind a dark or colourful logo, ink behind a pale one
	var logo := TeamCast.logo()
	if logo != null: SlotFrames._fit_into(image, logo, Rect2i(52, 52, TEX - 104, TEX - 104), false)
	else: _hex_rings(image, ring)
	return _texture(image)

## Concentric hexagons (rings of `ring` on cream), for a cast without a logo.
static func _hex_rings(image: Image, ring: Color) -> void:
	for y in TEX:
		for x in TEX:
			var at := Vector2(x + 0.5 - TEX * 0.5, y + 0.5 - TEX * 0.5) / (TEX * 0.5) # -1..1 over the circumscribed square
			var reach := maxf(absf(at.x), absf(at.x) * 0.5 + absf(at.y) * HexGrid.ROW) / HexGrid.ROW # 1 at the plate's corners' circle: the hexagon of the plate
			if (reach > 0.42 and reach < 0.58) or reach < 0.2: image.set_pixel(x, y, ring)

func _obstacle_texture(slot: String) -> Texture2D:
	var sign := TeamCast.obstacle(int(slot.trim_prefix("obstacle_"))) if slot.begins_with("obstacle_") else {}
	var image := Image.create_empty(TEX, TEX, false, Image.FORMAT_RGBA8)
	var color: Color = DANGER
	if not sign.is_empty() and (sign.color as Color).a > 0.0: color = sign.color
	elif not sign.is_empty():
		var accent := TeamCast.brand_accent()
		color = accent if accent.a > 0.0 else SIGN_YELLOW
	if not sign.is_empty() and sign.picture != null:
		image.fill(Color.WHITE)
		SlotFrames._fit_into(image, sign.picture, Rect2i(0, 0, TEX, TEX), true)
	else: _stripes(image, color)
	return _texture(image)

## Diagonal hazard stripes of `color` and ink.
static func _stripes(image: Image, color: Color) -> void:
	var band := 32
	for y in TEX:
		for x in TEX:
			image.set_pixel(x, y, color if ((x + y) / band) % 2 == 0 else INK)

static func _texture(image: Image) -> Texture2D:
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

# ------------------------------------------------------------------ poses

## Tile `index` in `mode` (levels/step_tiles.gd MODE_*), `tau` seconds into it (warn: since the step, fall: since it went), `delay` its warning time.
## A tile of a ghosted floor only remembers its pose: it is drawn again when its floor comes back.
func pose(index: int, mode: int, tau: float, delay: float) -> void:
	_tau[index] = tau
	_wait[index] = delay
	if _hidden[index] == 1:
		_last[index] = mode
		return
	_draw(index, mode, tau, delay, false)

## The floors (indices into the level's floors, step_tiles.gd ghost_floors) whose tiles are not drawn; the others are drawn again. Only the tiles whose
## floor changed are touched.
func set_ghosted(floors: PackedInt32Array) -> void:
	for floor_index in _by_floor.size():
		var hide := floors.has(floor_index)
		for index: int in _by_floor[floor_index]:
			if (_hidden[index] == 1) == hide: continue
			_hidden[index] = 1 if hide else 0
			if hide:
				var slot: Array = _slot_of[index]
				((_groups[slot[0]] as Dictionary).multi as MultiMesh).set_instance_transform(slot[1], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), (_tiles[index] as Dictionary).p))
			else: _draw(index, _last[index], _tau[index], _wait[index], true)

## True while tile `index` is not drawn because its floor is ghosted.
func is_ghosted(index: int) -> bool:
	return index >= 0 and index < _hidden.size() and _hidden[index] == 1

func _draw(index: int, mode: int, tau: float, delay: float, force: bool) -> void:
	var slot: Array = _slot_of[index]
	var multi: MultiMesh = (_groups[slot[0]] as Dictionary).multi
	var instance: int = slot[1]
	var at: Vector3 = (_tiles[index] as Dictionary).p
	match mode:
		0:
			if _last[index] == 0 and not force: return
			multi.set_instance_transform(instance, Transform3D(Basis.IDENTITY, at))
			multi.set_instance_color(instance, slot[2])
		1:
			var strength := clampf(tau / maxf(delay, 0.1), 0.0, 1.0)
			var wave := tau * 55.0 + index * 1.7
			var shake := Vector3(sin(wave), sin(wave * 1.3) * 0.3, cos(wave * 0.9)) * SHAKE * (0.35 + 0.65 * strength)
			var tilt := Basis.from_euler(Vector3(sin(wave * 0.7), 0.0, cos(wave * 1.1)) * 0.025 * strength)
			multi.set_instance_transform(instance, Transform3D(tilt, at + shake))
			multi.set_instance_color(instance, (slot[2] as Color).lerp(WARN, 0.35 + 0.5 * strength))
		2:
			multi.set_instance_transform(instance, _fallen(at, tau))
			multi.set_instance_color(instance, WARN)
		_:
			if _last[index] == 3 and not force: return
			multi.set_instance_transform(instance, _fallen(at, FALL_TIME)) # gone: it rests where its fall ended, far under the arena, never hidden or scaled away
			multi.set_instance_color(instance, WARN)
	_last[index] = mode

## A tile `tau` seconds into its fall (gravity, a tumble that starts slowly so it never pokes above the floor it leaves): nothing shrinks or vanishes, it falls away
## under the arena; after FALL_TIME it rests at the depth it has reached (49 m), a tile that was never there is drawn there from the start.
static func _fallen(at: Vector3, tau: float) -> Transform3D:
	var fell := minf(tau, FALL_TIME)
	var turned := fell * minf(fell / 0.4, 1.0)
	return Transform3D(Basis.from_euler(Vector3(turned * 1.4, 0.0, turned * 0.9)), at - Vector3(0.0, 0.5 * FALL_GRAVITY * fell * fell, 0.0))
