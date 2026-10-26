extends RefCounted
## Client-only picture of the lobby yard (lobby_space.gd) in the look of the levels, from primitives only:
##  * every collision box of the yard is drawn by style/collision_look.gd from its own shape (floor, walls, foam-block crates);
##  * the hall around the yard (style/backdrop.gd -> style/room_shell.gd), lit like the levels;
##  * the easel a framed picture (the team's print, else a painted landscape), the walls strings of flags in the team's colours,
##    the team name painted on the floor;
##  * the team cast's logo wall, posters and team wall hang on the walls (SLOTS, style/slot_frames.gd);
##  * the playground and its furniture (lobby/playground_look.gd), string lights, floor and wall paint (lobby/decor_look.gd).
## The comic look (dev runs) keeps its inked versions: crates with a painted X, ink edges, comic lettering.
## Nothing here collides: decals sit on the faces of the solid boxes, the bunting hangs on the wall faces out of reach.
const Layout = preload("res://network/walk_in_lobby.gd")
const Look = preload("res://style/collision_look.gd")
const Ink = preload("res://style/style_ink.gd")
const TeamCast = preload("res://style/team_cast.gd")
const Backdrop = preload("res://style/backdrop.gd")
const LobbyKit = preload("res://lobby/lobby_kit.gd")
const SlotFrames = preload("res://style/slot_frames.gd")
const CandyMaterial = preload("res://style/candy_material.gd")
const Surfaces = preload("res://style/surfaces.gd")
const Party = preload("res://style/party_look.gd")
const FriendsUi = preload("res://client/friends_ui.gd")
const Hazards = preload("res://levels/hazards.gd")
const WardrobeBooth = preload("res://character/wardrobe/wardrobe_booth.gd")
const PlaygroundLook = preload("res://lobby/playground_look.gd")
const DecorLook = preload("res://lobby/decor_look.gd")
const WATER = preload("res://style/collision_water.gdshader")
const GILT := Color("f2b630")
const SKY_PAINT := Color("a9d8ff")
const HILL_FAR := Color("43b57b")
const HILL_NEAR := Color("2c8a5c")
const FLAGS: Array[Color] = [Ink.TOMATO, Ink.YELLOW, Ink.COBALT, Ink.PAPER, Color("2ec27e")]
const CORD := Color("3a3d44")
const VOID_DEPTH := 8.0
## The yard walls brand.walls "accent" paints in the team's colour: the back wall behind the easel and the logo wall.
const BRAND_WALLS := ["wall_n"]
## The frames the team cast fills in the yard (docs/slots.md), yard-local like a level's `slots`: the logo wall and a poster on the
## north wall either side of the easel, a poster on each side wall, the team wall on the east wall. A poster slot has a `box` too: the
## largest room its frame may take when it shows a picture that is not a portrait (_wall_art).
const SLOTS := [
	{"id": "logo_wall", "p": Vector3(-4.0, 1.5, -13.85), "yaw": 0.0, "size": Vector2(3.0, 2.0)},
	{"id": "poster_1", "p": Vector3(3.9, 1.5, -13.85), "yaw": 0.0, "size": Vector2(1.5, 2.0), "box": Vector2(2.8, 2.0)},
	{"id": "poster_2", "p": Vector3(-17.15, 1.5, -5.0), "yaw": PI * 0.5, "size": Vector2(1.5, 2.0), "box": Vector2(4.2, 2.0)},
	{"id": "poster_3", "p": Vector3(17.15, 1.5, -5.0), "yaw": -PI * 0.5, "size": Vector2(1.5, 2.0), "box": Vector2(4.2, 2.0)},
	{"id": "team_wall", "p": Vector3(17.15, 1.4, 1.5), "yaw": -PI * 0.5, "size": Vector2(4.0, 2.25)},
]
## The show's yard (Layout.show_yard): the rear signs and their masonry stand along the north wall, so the logo wall moves to the east wall's back half and the first poster hangs on the wall between
## THE SHOW's pylon and the first rear pier (1.5 m wide, 0.9 m from the middle pylon); the others stay as they are. The side walls' frames hang on the wall faces of the yard's own width
## (Layout.yard_half_width()), the north wall's on its inner face (Layout.interior_rect()); the side walls are a low rim (lobby/lobby_kit.gd WALL_SIDE_TOP 2.4 m), so their frames hang with their tops at 2.3 m.
static func show_slots() -> Array:
	var rect := Layout.interior_rect()
	var east := rect.end.x - 0.15
	var west := rect.position.x + 0.15
	return [
		{"id": "logo_wall", "p": Vector3(east, 1.3, rect.position.y + 2.0), "yaw": -PI * 0.5, "size": Vector2(3.0, 2.0)},
		{"id": "poster_1", "p": Vector3(1.8, 1.5, rect.position.y + 0.15), "yaw": 0.0, "size": Vector2(1.5, 2.0), "box": Vector2(1.7, 2.0)},
		{"id": "poster_2", "p": Vector3(west, 1.3, -5.0), "yaw": PI * 0.5, "size": Vector2(1.5, 2.0), "box": Vector2(4.2, 2.0)},
		{"id": "poster_3", "p": Vector3(east, 1.3, -5.0), "yaw": -PI * 0.5, "size": Vector2(1.5, 2.0), "box": Vector2(4.2, 2.0)},
		{"id": "team_wall", "p": Vector3(east, 1.2, 1.5), "yaw": -PI * 0.5, "size": Vector2(4.0, 2.25)},
	]
## The frames hang with their tops at 2.6 m at most and the bunting runs above that: its lowest flag tip is BUNTING_HEIGHT - sag - a flag's length.
const BUNTING_HEIGHT := 3.3
const EASEL_MAT := 0.07 ## the paper edge around the picture on the easel (m)

static var _flat_materials: Dictionary = {}

## `props` is lobby_space.gd props(): crates and the easel are dressed, bodies are already built. The show's yard (Layout.show_yard) is the lobby kit (lobby/lobby_kit.gd: deck, cushion walls, supports and
## the open-air world), the wardrobe and the cast's wall frames; the furniture, bunting and paint below dress the single-circle minigames' yards.
static func dress(room: Node3D, props: Array) -> void:
	if Layout.show_yard():
		LobbyKit.dress(room)
		for row: Dictionary in props:
			if str(row.kind) == "wardrobe": WardrobeBooth.dress(room.get_node(str(row.name)), row.size) # the lobby wardrobe (character/wardrobe/)
		_slots(room)
		CandyMaterial.dissolve_tree(room) # nothing of the yard hides the courier from the shoulder camera: pieces near the eye dissolve (style/near_dissolve.gdshaderinc)
		return
	var shapes: Array = []
	for body: Node in room.get_children():
		if body is StaticBody3D:
			for child: Node in body.get_children():
				if child is CollisionShape3D: shapes.append(child)
	Look.draw_shapes(shapes, false, BRAND_WALLS)
	Look.edges(room)
	if Backdrop.enabled: room.add_child(Backdrop.for_lobby(Layout.ORIGIN))   # the world far below and around the yard
	else: _void(room)
	for row: Dictionary in props:
		var body: Node3D = room.get_node(str(row.name))
		match str(row.kind):
			"crate":
				if Surfaces.ink(): _crate(body, row.size) # the facility look's crates are plain foam blocks
			"easel": _easel(body, row.size, _wall_art().easel)
			"wardrobe": WardrobeBooth.dress(body, row.size) # the lobby wardrobe (character/wardrobe/)
	_bunting(room)
	_floor_word(room)
	_slots(room)
	PlaygroundLook.dress(room, room.get("playground"))
	DecorLook.dress(room)

## A flat colour: unshaded in the comic look, a painted surface lit like the room in the facility look.
static func _flat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _flat_materials.has(key):
		var material := StandardMaterial3D.new()
		if Surfaces.ink(): material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		else: material.roughness = 0.75
		material.albedo_color = color
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flat_materials[key] = material
	return _flat_materials[key]

static func _void(room: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	var holder := MeshInstance3D.new()
	holder.name = "LobbyVoid"
	holder.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = WATER
	holder.material_override = material
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.position = Layout.ORIGIN + Vector3(0.0, -VOID_DEPTH, 0.0)
	room.add_child(holder)

## A flat painted rectangle on a face: `at` is the middle in the face's own (x, y), `lift` metres off the surface.
static func _plate(parent: Node3D, size: Vector2, color: Color, at: Vector2, lift: float, angle := 0.0) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.material_override = _flat(color)
	node.position = Vector3(at.x, at.y, lift)
	node.rotation.z = angle
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## A filled polygon (points in the face's own x, y), triangulated.
static func _polygon(parent: Node3D, points: PackedVector2Array, color: Color, lift: float) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty(): return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in indices:
		vertices.append(Vector3(points[index].x, points[index].y, 0.0))
		normals.append(Vector3.BACK)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _flat(color)
	node.position.z = lift
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func _circle(center: Vector2, radius: float, segments := 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments: points.append(center + Vector2(cos(TAU * index / segments), sin(TAU * index / segments)) * radius)
	return points

## A hill: the wave `base + amplitude * sin(x * frequency + phase)` over [left, right] down to `floor_y`.
static func _hill(left: float, right: float, floor_y: float, base: float, amplitude: float, frequency: float, phase: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(left, floor_y)])
	var steps := 18
	for index in steps + 1:
		var x := lerpf(left, right, float(index) / steps)
		points.append(Vector2(x, base + amplitude * sin(x * frequency + phase)))
	points.append(Vector2(right, floor_y))
	return points

static func _word(text: String, size: int, pixel: float, fill: Color, outline: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = FriendsUi.inter(800)
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = fill
	label.outline_modulate = Ink.INK
	label.outline_size = outline
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## Faces of a box in its own frame: normal, yaw that turns a +Z quad onto it, width and height of the face.
static func _faces(size: Vector3) -> Array:
	return [
		{"at": Vector3(0, 0, size.z * 0.5), "yaw": 0.0, "face": Vector2(size.x, size.y)},
		{"at": Vector3(0, 0, -size.z * 0.5), "yaw": PI, "face": Vector2(size.x, size.y)},
		{"at": Vector3(size.x * 0.5, 0, 0), "yaw": PI * 0.5, "face": Vector2(size.z, size.y)},
		{"at": Vector3(-size.x * 0.5, 0, 0), "yaw": -PI * 0.5, "face": Vector2(size.z, size.y)},
	]

## A crate: a tomato X with an ink edge on each side face (the box itself is a hop block or a low slab of the look).
static func _crate(body: Node3D, size: Vector3) -> void:
	for side: Dictionary in _faces(size):
		var face: Vector2 = side.face
		var holder := Node3D.new()
		holder.position = side.at
		holder.rotation.y = side.yaw
		body.add_child(holder)
		var margin := minf(face.x, face.y) * 0.12
		var inner := face - Vector2.ONE * margin * 2.0
		var diagonal := inner.length()
		var angle := atan2(inner.y, inner.x)
		var strap := clampf(minf(face.x, face.y) * 0.16, 0.06, 0.2)
		_plate(holder, Vector2(diagonal, strap + 0.045), Ink.INK, Vector2.ZERO, 0.01, angle)
		_plate(holder, Vector2(diagonal, strap + 0.045), Ink.INK, Vector2.ZERO, 0.011, -angle)
		_plate(holder, Vector2(diagonal - 0.06, strap), Ink.TOMATO, Vector2.ZERO, 0.016, angle)
		_plate(holder, Vector2(diagonal - 0.06, strap), Ink.TOMATO, Vector2.ZERO, 0.017, -angle)

## The easel: a framed landscape on the board (the painting the couriers carry) and a plaque under it.
static func _easel(body: Node3D, size: Vector3, picture: Texture2D) -> void:
	var front := Node3D.new()
	front.position = Vector3(0.0, 0.0, size.z * 0.5)
	body.add_child(front)
	var middle := Vector2(0.0, 0.12)
	if not Surfaces.ink():
		_easel_print(front, middle, picture)
		return
	_plate(front, Vector2(1.84, 1.44), Ink.INK, middle, 0.01)
	_plate(front, Vector2(1.72, 1.32), GILT, middle, 0.014)
	_plate(front, Vector2(1.44, 1.04), Ink.INK, middle, 0.018)
	_plate(front, Vector2(1.38, 0.98), SKY_PAINT, middle, 0.022)
	var left := middle.x - 0.69
	var right := middle.x + 0.69
	var bottom := middle.y - 0.49
	_polygon(front, _circle(middle + Vector2(0.38, 0.27), 0.15), Ink.INK, 0.026)
	_polygon(front, _circle(middle + Vector2(0.38, 0.27), 0.115), Ink.YELLOW, 0.028)
	_polygon(front, _hill(left, right, bottom, middle.y - 0.06 + 0.03, 0.15, 3.1, 0.7), Ink.INK, 0.03)
	_polygon(front, _hill(left, right, bottom, middle.y - 0.06, 0.15, 3.1, 0.7), HILL_FAR, 0.032)
	_polygon(front, _hill(left, right, bottom, middle.y - 0.27 + 0.03, 0.1, 4.2, 2.1), Ink.INK, 0.034)
	_polygon(front, _hill(left, right, bottom, middle.y - 0.27, 0.1, 4.2, 2.1), HILL_NEAR, 0.036)
	_plate(front, Vector2(1.3, 0.3), Ink.INK, Vector2(0.0, -0.86), 0.01)
	_plate(front, Vector2(1.22, 0.22), Ink.PAPER, Vector2(0.0, -0.86), 0.014)
	var plaque := _word("HANDLE WITH CARE", 72, 0.0032, Ink.TOMATO, 10)
	plaque.position = Vector3(0.0, -0.86, 0.02)
	front.add_child(plaque)

## The facility easel: the picture (the team's print, else one of its scene pictures: _wall_art) in a thin frame behind glass, or (none) the
## painted landscape without ink, with a printed HANDLE WITH CARE plaque under it.
static func _easel_print(front: Node3D, middle: Vector2, picture: Texture2D) -> void:
	var at := Node3D.new()
	at.position = Vector3(middle.x, middle.y, 0.0)
	front.add_child(at)
	if picture != null:
		# the frame takes the print's own shape (a 2:1 print gets a 2:1 frame), and the print is fitted whole, never cropped; the board of
		# the easel is the frame (a second frame bar on top of it would be a double frame)
		var aspect := clampf(float(picture.get_width()) / maxf(float(picture.get_height()), 1.0), 0.6, 2.2)
		var room := Vector2(1.9, 1.4) - Vector2.ONE * EASEL_MAT * 2.0 # what the board has for the picture
		var size := (Vector2(room.x, room.x / aspect) if aspect >= room.x / room.y else Vector2(room.y * aspect, room.y)) + Vector2.ONE * EASEL_MAT * 2.0
		var inner := size
		SlotFrames._print(at, inner, Color("f6f6f4"), picture, Rect2(Vector2.ONE * EASEL_MAT, inner - Vector2.ONE * EASEL_MAT * 2.0), false, Color("f6f6f4"), 0.7)
		SlotFrames._glass(at, inner)
	else:
		_plate(front, Vector2(1.84, 1.44), GILT, middle, 0.014)
		_plate(front, Vector2(1.6, 1.2), SKY_PAINT, middle, 0.022)
		var left := middle.x - 0.8
		var right := middle.x + 0.8
		var bottom := middle.y - 0.6
		_polygon(front, _circle(middle + Vector2(0.42, 0.3), 0.14), Ink.YELLOW, 0.028)
		_polygon(front, _hill(left, right, bottom, middle.y - 0.06, 0.15, 3.1, 0.7), HILL_FAR, 0.032)
		_polygon(front, _hill(left, right, bottom, middle.y - 0.3, 0.1, 4.2, 2.1), HILL_NEAR, 0.036)
	var plaque := Node3D.new()
	plaque.position = Vector3(0.0, -0.86, 0.0)
	front.add_child(plaque)
	SlotFrames._print(plaque, Vector2(1.3, 0.3), Color(str(Surfaces.signage().frame)), null, Rect2(), false, Color.WHITE, 0.35, 0.9)
	SlotFrames._print_letters(plaque, Vector2(1.3, 0.3), Rect2(0.08, 0.06, 1.14, 0.18), "HANDLE WITH CARE", Color(str(Surfaces.signage().text)))

## The word on the floor between the spawn and the circles, lying flat, readable from the camera: painted in the team's colour in the
## facility look; tomato letters with an ink edge in the comic look.
static func _floor_word(room: Node3D) -> void:
	if not Surfaces.ink():
		var accent := TeamCast.brand_accent()
		var paint := _word(TeamCast.team_name(), 260, 0.0042, accent if accent.a > 0.0 else Color("f2f2f0"), 0)
		paint.name = "FloorWord"
		paint.shaded = true
		paint.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		paint.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		paint.position = Layout.ORIGIN + Vector3(0.0, 0.02, 3.4)
		room.add_child(paint)
		return
	var word := _word(TeamCast.team_name(), 260, 0.0042, Ink.TOMATO, 34)
	word.name = "FloorWord"
	word.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	word.position = Layout.ORIGIN + Vector3(0.0, 0.03, 3.4)
	word.double_sided = true
	room.add_child(word)

## The cast's frames on the yard walls (SLOTS); the walls and crates are the blocks they mount on.
static func _slots(room: Node3D) -> void:
	var yard := Node3D.new()
	yard.name = "CastSlots"
	yard.position = Layout.ORIGIN
	room.add_child(yard)
	var blocks: Array = []
	for row: Dictionary in room.get("placements"):
		var at: Vector3 = (row.origin as Vector3) - Layout.ORIGIN
		var size: Vector3 = row.size
		blocks.append(Hazards.block({"k": "box", "p": [at.x, at.y, at.z], "s": [size.x, size.y, size.z], "r": [0.0, float(row.yaw), 0.0]}))
	SlotFrames.build(yard, _wall_slots(), blocks)

## What hangs where: the logo is on the logo wall ONCE; the easel shows the team's print, else the first of the cast's scene pictures
## (billboards, banners, then the obstacle pictures: TeamCast.scene_art), and each poster its own picture (posters[i]) or the next scene
## picture; no poster where the cast has nothing left (never the logo again). {easel: Texture2D or null, posters: {1-based index: poster}}.
static func _wall_art() -> Dictionary:
	var pool := TeamCast.scene_art()
	var easel := TeamCast.print_picture()
	if easel == null and not pool.is_empty(): easel = (pool.pop_front() as Dictionary).picture
	var posters := {}
	for index in range(1, 4):
		var poster := TeamCast.poster_own(index)
		if poster.is_empty() and not pool.is_empty():
			poster = pool.pop_front()
			poster["fit"] = true # a scene picture: the frame takes its shape
		if not poster.is_empty(): posters[index] = poster
	return {"easel": easel, "posters": posters}

## SLOTS with the posters resolved by _wall_art: a poster slot without a picture is left out, one with a scene picture is sized to it.
static func _wall_slots() -> Array:
	var posters: Dictionary = _wall_art().posters
	var slots: Array = []
	for row: Dictionary in (show_slots() if Layout.show_yard() else SLOTS):
		var id := str(row.id)
		if not id.begins_with("poster_"):
			slots.append(row)
			continue
		var index := int(id.trim_prefix("poster_"))
		if not posters.has(index): continue
		var slot := row.duplicate()
		slot.poster = posters[index]
		if slot.poster.get("fit", false): slot.size = SlotFrames.poster_fit(slot.poster.picture, row.box)
		slots.append(slot)
	return slots

## Strings of bunting on the faces of the three walls the camera looks at: ribbons and flags merged into one mesh per colour.
static func _bunting(room: Node3D) -> void:
	var origin := Layout.ORIGIN
	var groups := {}
	# wall face point at, the way the face looks (towards the yard), end heights, sag
	_string(groups, origin + Vector3(-17.1, BUNTING_HEIGHT, -13.9), origin + Vector3(0.0, BUNTING_HEIGHT, -13.9), Vector3.BACK, 0.3, 21)
	_string(groups, origin + Vector3(0.0, BUNTING_HEIGHT, -13.9), origin + Vector3(17.1, BUNTING_HEIGHT, -13.9), Vector3.BACK, 0.3, 21)
	for side: float in [-1.0, 1.0]:
		var x := 17.2 * side
		var facing := Vector3.RIGHT * -side
		_string(groups, origin + Vector3(x, BUNTING_HEIGHT, -13.6), origin + Vector3(x, BUNTING_HEIGHT, -1.7), facing, 0.3, 14)
		_string(groups, origin + Vector3(x, BUNTING_HEIGHT, -1.7), origin + Vector3(x, BUNTING_HEIGHT, 9.6), facing, 0.3, 13)
	var mesh := ArrayMesh.new()
	for color_key: String in groups:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(groups[color_key].vertices)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(groups[color_key].normals)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := _flat(Color(color_key))
		if Party.night(): material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # the night look's flags are light, not painted cloth
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var holder := MeshInstance3D.new()
	holder.name = "Bunting"
	holder.mesh = mesh
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(holder)

static func _add_triangle(groups: Dictionary, color: Color, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var key := color.to_html()
	if not groups.has(key): groups[key] = {"vertices": [], "normals": []}
	var group: Dictionary = groups[key]
	for point: Vector3 in [a, b, c]:
		(group.vertices as Array).append(point)
		(group.normals as Array).append(normal)

## The flag colours: the team's brand colours and white in the facility look, the comic inks in the comic look.
static func _flag_colors() -> Array[Color]:
	if Surfaces.ink(): return FLAGS
	if Party.night(): # the night look: the accent in its tones and the brand's silver, like the light blades of the levels
		var palette := Party.palette()
		var tones: Array[Color] = [(palette.p as Dictionary).main, (palette.p as Dictionary).soft, (palette.x as Dictionary).main, (palette.p as Dictionary).pale]
		return tones
	var colors: Array[Color] = []
	for color: Color in TeamCast.brand_colors():
		if color.s > 0.18 and color.v > 0.2: colors.append(color)
	if colors.is_empty(): colors.assign([FLAGS[0], FLAGS[1], FLAGS[2]])
	colors.append(Color("f4f4f2"))
	return colors

## One scallop from `from` to `to` (both on a wall face, `normal` pointing into the yard): a ribbon (ink, or a dark cord in the
## facility look) sagging by `sag` and `count` flags.
static func _string(groups: Dictionary, from: Vector3, to: Vector3, normal: Vector3, sag: float, count: int) -> void:
	var ink := Surfaces.ink()
	var cord := Ink.INK if ink else CORD
	var flags := _flag_colors()
	var along := (to - from).normalized()
	var steps := count * 3
	var previous := from
	for step in range(1, steps + 1):
		var t := float(step) / steps
		var point := from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var lift := normal * 0.07
		var thick := Vector3.DOWN * (0.03 if ink else 0.015)
		_add_triangle(groups, cord, previous + lift, point + lift, point + lift + thick, normal)
		_add_triangle(groups, cord, previous + lift, point + lift + thick, previous + lift + thick, normal)
		previous = point
	for index in count:
		var t := (index + 0.5) / count
		var top := from.lerp(to, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t) + normal * 0.08
		var half := (to - from).length() / count * 0.36
		var tip := top + Vector3.DOWN * half * 1.5
		var color := flags[index % flags.size()]
		if ink: _add_triangle(groups, Ink.INK, top - along * (half + 0.07) + Vector3.UP * 0.03, top + along * (half + 0.07) + Vector3.UP * 0.03, tip + Vector3.DOWN * 0.1, normal)
		_add_triangle(groups, color, top - along * half + normal * 0.012, top + along * half + normal * 0.012, tip + normal * 0.012, normal)
