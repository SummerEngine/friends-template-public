extends RefCounted
## The look of the lobby wardrobe booth (client only), in the soft toy style of the characters, not the comic ink of the yard:
##  * a round rug with a pink band and little warm bulbs on the floor of the yard's west side (the ring you stand in),
##  * an oval mirror in a honey frame on the west wall, with a WARDROBE plaque on its crest, two shirts on pegs beside it,
##  * a warm lamp over the booth.
## lobby_visuals.gd calls dress() for the "wardrobe" prop of lobby_space.gd: that prop is the mirror board's collision box,
## everything else stays within reach of no one (on the floor or flat on the wall). dress() also adds the booth's runtime
## (wardrobe.gd: prompt, open and close, orbit camera, panel, save).
const Layout = preload("res://network/walk_in_lobby.gd")
const Wardrobe = preload("res://character/wardrobe/wardrobe.gd")
const FONT = preload("res://assets/fonts/Nunito.ttf")
const Party = preload("res://style/party_look.gd")
const PickPlate = preload("res://lobby/pick_plate.gd")
const LobbySign = preload("res://lobby/lobby_sign.gd")
const ShowTheme = preload("res://client/show_theme.gd")

const RUG := Color("f8dbe4")
const BAND := Color("f28ca8")
const BULB := Color("ffe39a")
const FRAME := Color("f2b66d")
const GLASS := Color("cfe7f6")
const PLAQUE := Color("ff8f6b")
const PEG := Color("c98a52")
const SHIRTS: Array[Color] = [Color("7cc4f2"), Color("8fd694")]
const BULBS := 10
const KIT_FRAME := Color("#cdb57f") ## the show's yard (Layout.show_yard): the lobby kit's tan frame and the UI's dark pill for the plaque
const KIT_PLAQUE := Color(0.075, 0.082, 0.105)
const PLUSH_PINK := Color("f28ca8") ## the nook's border and foot (the cushion wings' pink: lobby/lobby_kit.gd WING_PINK)
const CREAM := Color("fbe9d6")

## `body` is the board's StaticBody3D (lobby_space.gd built it, collision_look.gd dressed its box), `size` its box.
static func dress(body: Node3D, size: Vector3) -> Node3D:
	# The board's comic box is replaced by the mirror drawn here.
	for shape: Node in body.get_children():
		for drawn: Node in shape.get_children():
			if drawn is GeometryInstance3D: drawn.visible = false
	var room := body.get_parent() as Node3D
	var booth: Node3D = Wardrobe.new()
	booth.name = "Wardrobe"
	room.add_child(booth)
	booth.global_position = Layout.ORIGIN + Layout.wardrobe_center()
	_rug(booth)
	if Layout.show_yard(): # the ring's own sign, like the circles' (a pink plate, no pick)
		LobbySign.build(booth, {"title": "WARDROBE", "subtitle": "Change your look", "board": Layout.BOARD_FRONT, "lift": Layout.FRONT_LIFT, "kind": "wardrobe"}, 5)
	_mirror(room, body, size)
	_lamp(booth)
	return booth

static func _soft(color: Color, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	material.rim_enabled = true
	material.rim = 0.3
	material.rim_tint = 0.6
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

static func _mesh(parent: Node3D, mesh: Mesh, material: Material, at: Transform3D, shadow := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

## A flat oval in a face's own (x, y), `depth` thick along z: a unit cylinder turned to face +z and scaled.
static func _oval(parent: Node3D, width: float, height: float, depth: float, material: Material, at: Vector3) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 48
	cylinder.rings = 1
	var basis := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(width, depth, height))
	return _mesh(parent, cylinder, material, Transform3D(basis, at), true)

## The rug: a soft disc, a raised band at the ring's edge and a circle of warm bulbs. The show's yard has a press plate of the lobby circles' family (blue and mint rings) instead.
static func _rug(booth: Node3D) -> void:
	var radius: float = Wardrobe.ENTER_RADIUS
	if Layout.show_yard():
		PickPlate.build(booth, radius + 0.15, "wardrobe")
		return
	var disc := CylinderMesh.new()
	disc.top_radius = radius + 0.12
	disc.bottom_radius = radius + 0.16
	disc.height = 0.03
	disc.radial_segments = 64
	disc.rings = 1
	_mesh(booth, disc, _soft(Party.palette().mat if Party.night() else RUG), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.015, 0.0)))
	var band := TorusMesh.new()
	band.inner_radius = radius - 0.1
	band.outer_radius = radius + 0.08
	band.rings = 64
	band.ring_segments = 12
	_mesh(booth, band, _soft((Party.palette().p as Dictionary).main if Party.night() else BAND, 0.6 if Party.night() else 0.0), Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 1.0)), Vector3(0.0, 0.035, 0.0)))
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.08
	bulb.radial_segments = 16
	bulb.rings = 8
	var glow := _soft(BULB, 1.2)
	for index in BULBS:
		var angle := TAU * index / BULBS
		_mesh(booth, bulb, glow, Transform3D(Basis.IDENTITY, Vector3(cos(angle), 0.0, sin(angle)) * (radius - 0.01) + Vector3.UP * 0.07))

## The mirror on the board's front face (+X, towards the yard), the plaque on its crest, shirts on pegs left and right.
static func _mirror(room: Node3D, body: Node3D, size: Vector3) -> void:
	var face := Node3D.new()
	face.name = "WardrobeMirror"
	room.add_child(face)
	# Face space: x along the wall (towards -Z of the yard), y up, z out of the wall into the yard.
	face.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), body.global_position + Vector3(size.x * 0.5, 0.0, 0.0))
	var width := minf(size.z - 0.2, 1.3)
	var height := minf(size.y - 0.3, 2.0)
	if Layout.show_yard(): # the show's yard: the mirror stands on the floor with its back against the wall (2 cm in each), no hanging in air
		face.global_position = Vector3(body.global_position.x - size.x * 0.5 + 0.01, Layout.ORIGIN.y + height * 0.5 - 0.02, body.global_position.z)
	var kit := Layout.show_yard()
	if kit: _alcove(face, height)
	_oval(face, width, height, 0.12, _soft(KIT_FRAME if kit else FRAME), Vector3(0.0, 0.0, 0.03))
	var glass := _soft(GLASS)
	glass.metallic = 0.5
	glass.roughness = 0.12
	_oval(face, width - 0.2, height - 0.2, 0.04, glass, Vector3(0.0, 0.0, 0.08))
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var layer := 0.0
	for streak: Vector3 in [Vector3(-0.18, 0.42, 0.5), Vector3(-0.05, 0.5, 0.3)]: # x, y, length
		var quad := QuadMesh.new()
		quad.size = Vector2(streak.z, 0.06)
		_mesh(face, quad, shine, Transform3D(Basis(Vector3.BACK, deg_to_rad(52.0)), Vector3(streak.x, streak.y, 0.105 + layer)))
		layer += 0.004 # no two streaks in one plane
	# The plaque: a pink pill over the frame's crest with the word in rounded letters.
	var plaque := CapsuleMesh.new()
	plaque.radius = 0.17
	plaque.height = 1.1
	plaque.radial_segments = 24
	plaque.rings = 4
	var crest := height * 0.5 - 0.02
	_mesh(face, plaque, _soft(KIT_PLAQUE if kit else PLAQUE), Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 0.45)), Vector3(0.0, crest, 0.14)), true)
	var bold := FontVariation.new()
	bold.base_font = FONT
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 900}
	var word := Label3D.new()
	word.text = "WARDROBE"
	word.font = ShowTheme.font() if kit else bold
	word.font_size = 56
	word.pixel_size = 0.0034
	word.modulate = Color.WHITE
	word.outline_size = 0
	word.shaded = false
	word.double_sided = false
	word.position = Vector3(0.0, crest, 0.225)
	face.add_child(word)
	if kit: return # the show's yard hangs nothing else on the wall
	# Shirts on pegs on the bare wall left and right of the board (the wall face is size.x behind the board's face).
	for side: int in 2:
		var x := (width * 0.5 + 0.55) * (1.0 if side == 0 else -1.0)
		var peg := CylinderMesh.new()
		peg.top_radius = 0.035
		peg.bottom_radius = 0.045
		peg.height = 0.14
		_mesh(face, peg, _soft(PEG), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.45, 0.07 - size.x)))
		_shirt(face, SHIRTS[side], Vector3(x, 0.12, 0.03 - size.x))

## The nook's back (the show's yard): the wall behind the mirror wears a cream arch in a pink border, flat on the wall face (like the north wall's yellow panel), and the mirror stands on a pink foot,
## so the wardrobe reads as a booth between its two cushion wings (Layout.nook_wings), not as an oval stuck to a wall. `face` is the mirror's frame (z out of the wall, the wall 1 cm behind z = 0).
static func _alcove(face: Node3D, height: float) -> void:
	var floor_y := -(height * 0.5 - 0.02)
	var half := Layout.NOOK_SIDE - Layout.NOOK_THICK * 0.5 - 0.15 ## the arch's half width: clear of the wings' inner faces
	var straight := 1.65 ## the arch's sides rise this far over the floor, then the top is half an ellipse to the arch's crest (under the low wall's rim, lobby/lobby_kit.gd WALL_SIDE_TOP)
	var crest := 2.15
	var border := 0.16
	for layer: Dictionary in [{"half": half, "inset": 0.0, "lift": 0.0, "color": PLUSH_PINK}, {"half": half - border, "inset": border, "lift": 0.006, "color": CREAM}]:
		var reach: float = layer.half
		var points := PackedVector2Array()
		points.append(Vector2(reach, floor_y))
		points.append(Vector2(reach, floor_y + straight))
		var rise := crest - float(layer.inset) - straight
		for step in range(1, 16):
			var angle := PI * float(step) / 16.0
			points.append(Vector2(cos(angle) * reach, floor_y + straight + sin(angle) * rise))
		points.append(Vector2(-reach, floor_y + straight))
		points.append(Vector2(-reach, floor_y))
		var indices := Geometry2D.triangulate_polygon(points)
		if indices.is_empty(): continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in indices:
			tool.set_normal(Vector3.BACK)
			tool.add_vertex(Vector3(points[index].x, points[index].y, 0.0))
		var material := _soft(layer.color as Color)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh(face, tool.commit(), material, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.004 + float(layer.lift))))
	var foot := CylinderMesh.new()
	foot.top_radius = 0.42
	foot.bottom_radius = 0.48
	foot.height = 0.16
	foot.radial_segments = 32
	foot.rings = 1
	_mesh(face, foot, _soft(PLUSH_PINK), Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y + 0.08 - 0.01, 0.2)), true)

## A little T-shirt hanging flat on the wall: a soft rounded slab in the outline of a shirt.
static func _shirt(face: Node3D, color: Color, at: Vector3) -> void:
	var outline := PackedVector2Array([Vector2(-0.07, 0.24), Vector2(-0.28, 0.14), Vector2(-0.22, 0.01), Vector2(-0.15, 0.05), Vector2(-0.15, -0.26),
		Vector2(0.15, -0.26), Vector2(0.15, 0.05), Vector2(0.22, 0.01), Vector2(0.28, 0.14), Vector2(0.07, 0.24), Vector2(0.0, 0.18)])
	var indices := Geometry2D.triangulate_polygon(outline)
	if indices.is_empty(): return
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		tool.set_normal(Vector3.BACK)
		tool.add_vertex(Vector3(outline[index].x, outline[index].y, 0.02))
	for corner in outline.size(): # the slab's rim
		var a := outline[corner]
		var b := outline[(corner + 1) % outline.size()]
		var normal := Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
		for point: Vector3 in [Vector3(a.x, a.y, 0.02), Vector3(b.x, b.y, 0.0), Vector3(b.x, b.y, 0.02), Vector3(a.x, a.y, 0.02), Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0)]:
			tool.set_normal(normal)
			tool.add_vertex(point)
	_mesh(face, tool.commit(), _soft(color), Transform3D(Basis.IDENTITY, at))

## A warm lamp over the booth: the rug and the character in it glow a little warmer than the yard.
static func _lamp(booth: Node3D) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "WardrobeLamp"
	lamp.light_color = Color("ffe2b8")
	lamp.light_energy = 0.7
	lamp.omni_range = 4.5
	lamp.shadow_enabled = false
	lamp.position = Vector3(-0.9, 2.5, 0.0)
	booth.add_child(lamp)
