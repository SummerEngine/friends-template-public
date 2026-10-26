extends RefCounted
## The item box (docs/items.md): a crafted rounded cube with a "?" on every side, standing on a small tapered pedestal with an accent ring, never floating. Pure code, no assets: the cube is a
## rounded box built from a cube's grid pushed onto the rounded-box surface (smooth normals), the "?" is Lilita One (the show's display type) as extruded text, the pedestal a tapered
## cylinder with a torus on its rim. The accent is the cast's brand accent. `build` returns the root (origin on the floor under the box); the cube is `cube(root)`, its glow `glow(root)`.
const ShowTheme := preload("res://client/show_theme.gd")
const TeamCast := preload("res://style/team_cast.gd")

const SIZE := 1.0 ## m, the cube's edge
const RADIUS := 0.2 ## m, the rounding of its edges
const PEDESTAL := 0.24 ## m, the pedestal's height
const SIT := 0.02 ## m, the cube's gap over the pedestal (it stands on it: the cube's lowest point is a flat face, the gap hides nothing)
const GRID := 8 ## cells per cube edge

static var _mesh: ArrayMesh
static var _glyph: TextMesh

## The cube's mesh: SIZE wide, rounded by RADIUS, smooth normals, one surface.
static func rounded_cube() -> ArrayMesh:
	if _mesh != null: return _mesh
	var half := SIZE * 0.5
	var inner := half - RADIUS
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in 6:
		var axis := face / 2 # 0 x, 1 y, 2 z
		var sign_value := 1.0 if face % 2 == 0 else -1.0
		var u_axis := (axis + 1) % 3
		var v_axis := (axis + 2) % 3
		var grid: Array = []
		for j in GRID + 1:
			var row: Array = []
			for i in GRID + 1:
				var p := Vector3.ZERO
				p[axis] = sign_value * half
				p[u_axis] = lerpf(-half, half, float(i) / GRID)
				p[v_axis] = lerpf(-half, half, float(j) / GRID)
				var core := Vector3(clampf(p.x, -inner, inner), clampf(p.y, -inner, inner), clampf(p.z, -inner, inner))
				var n := (p - core).normalized()
				row.append([core + n * RADIUS, n, Vector2(float(i) / GRID, float(j) / GRID)])
			grid.append(row)
		for j in GRID:
			for i in GRID:
				var a: Array = grid[j][i]
				var b: Array = grid[j][i + 1]
				var c: Array = grid[j + 1][i + 1]
				var d: Array = grid[j + 1][i]
				var order := [a, b, c, a, c, d] if (sign_value > 0.0) == (axis != 1) else [a, c, b, a, d, c]
				for corner: Array in order:
					tool.set_normal(corner[1])
					tool.set_uv(corner[2])
					tool.add_vertex(corner[0])
	_mesh = tool.commit()
	return _mesh

static func _glyph_mesh() -> TextMesh:
	if _glyph != null: return _glyph
	_glyph = TextMesh.new()
	_glyph.text = "?"
	_glyph.font = ShowTheme.font()
	_glyph.font_size = 160
	_glyph.pixel_size = 0.0042
	_glyph.depth = 0.07
	_glyph.curve_step = 0.3
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return _glyph

static func _paint(color: Color, rough: float, metal: float, glow := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

## The accent of the box's pedestal ring: the cast's brand accent, else the show's gold.
static func accent() -> Color:
	var brand := TeamCast.brand_accent()
	return brand if brand.a > 0.0 else ShowTheme.GOLD

## A box standing on its pedestal, origin on the floor under it.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ItemBox"
	var ring_color := accent()
	# pedestal: a tapered kit stand with a dark body, a pale cap and the accent ring on its rim
	var stand := MeshInstance3D.new()
	var taper := CylinderMesh.new()
	taper.bottom_radius = 0.74
	taper.top_radius = 0.62
	taper.height = PEDESTAL
	taper.radial_segments = 40
	taper.rings = 1
	stand.mesh = taper
	stand.material_override = _paint(Color("1d2236"), 0.55, 0.15)
	stand.position.y = PEDESTAL * 0.5
	root.add_child(stand)
	var cap := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.bottom_radius = 0.6
	disc.top_radius = 0.6
	disc.height = 0.03
	disc.radial_segments = 40
	cap.mesh = disc
	cap.material_override = _paint(Color("e9eaf2"), 0.35, 0.05)
	cap.position.y = PEDESTAL + 0.012
	root.add_child(cap)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.595
	torus.outer_radius = 0.665
	torus.rings = 40
	torus.ring_segments = 10
	rim.mesh = torus
	rim.material_override = _paint(ring_color, 0.3, 0.3, 0.6)
	rim.position.y = PEDESTAL - 0.01
	root.add_child(rim)
	# the cube on it, turning about its own vertical axis
	var turner := Node3D.new()
	turner.name = "Cube"
	turner.position.y = PEDESTAL + SIT + SIZE * 0.5
	root.add_child(turner)
	var body := MeshInstance3D.new()
	body.mesh = rounded_cube()
	body.material_override = _paint(Color("3a5cd6"), 0.28, 0.1)
	turner.add_child(body)
	var inlay := MeshInstance3D.new() # a slightly smaller, glowing core seen through nothing: the soft inner light under the "?" faces
	inlay.mesh = rounded_cube()
	inlay.scale = Vector3.ONE * 0.97
	inlay.material_override = _paint(Color("3a5cd6").lightened(0.15), 0.2, 0.0, 0.25)
	turner.add_child(inlay)
	var face_color := Color("fff3d1")
	for face in 5: # four sides and the top
		var glyph := MeshInstance3D.new()
		glyph.mesh = _glyph_mesh()
		glyph.material_override = _paint(face_color, 0.3, 0.0, 0.5)
		glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var offset := SIZE * 0.5 + 0.005
		match face:
			0: glyph.position = Vector3(0.0, 0.0, offset)
			1:
				glyph.position = Vector3(offset, 0.0, 0.0)
				glyph.rotation.y = PI * 0.5
			2:
				glyph.position = Vector3(0.0, 0.0, -offset)
				glyph.rotation.y = PI
			3:
				glyph.position = Vector3(-offset, 0.0, 0.0)
				glyph.rotation.y = -PI * 0.5
			4:
				glyph.position = Vector3(0.0, offset, 0.0)
				glyph.rotation.x = -PI * 0.5
		turner.add_child(glyph)
	# a soft glow on the floor round the pedestal, so the box reads from far
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	glow.mesh = quad
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.28)
	glow_material.albedo_texture = _glow_texture()
	glow_material.no_depth_test = false
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = glow_material
	glow.rotation.x = -PI * 0.5
	glow.position.y = 0.02
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	return root

static var _glow_tex: GradientTexture2D

static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = gradient
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex

static func cube(root: Node3D) -> Node3D:
	return root.get_node("Cube") as Node3D

static func glow(root: Node3D) -> MeshInstance3D:
	return root.get_node("Glow") as MeshInstance3D
