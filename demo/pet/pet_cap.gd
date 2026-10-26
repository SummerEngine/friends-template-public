extends Node3D
## The menu pet's baseball cap with the team logo on the front panel, in the game's look (pet_look.gd). Crown,
## brim and button are built in code; the logo sits on a curved patch that follows the crown.
##   Colour: TeamCast.brand_accent() when the cast has it, else the first player colour.
##   Logo:   TeamCast.logo(), else TeamCast.picture(), else a round badge with the team's initial drawn at runtime (one big
##           letter reads at the cap's size; the whole name did not).
##
##   var cap := PetCap.wear(skeleton)   # sits it on the head bone; null when the model has no head bone
##
## Placement: a small cap perched on the crown of the head between the ears, a little forward and cocked to one side,
## clear of the ears in every clip. It is measured from a node named "CapSocket" under the head bone (our art
## marks the top of the skull there), else from the top of the vertices the head and face bones carry; its size from the
## skull's width. tools/menu_pet_check.gd checks that no part of the pet passes through it in any mood.
const TeamCast := preload("res://style/team_cast.gd")
const PetLook := preload("res://pet/pet_look.gd")
const Ui := preload("res://client/friends_ui.gd")

const SOCKET := "CapSocket"
const HEAD := ["head", "Head"]
## Bones whose vertices make the skull the cap sits on (ears, eyes and tongue are left out).
const SKULL := ["head", "Head", "face", "Face"]
## Crown radius as a share of the skull's half width: small enough to sit between the ears.
const CROWN_SHARE := 0.4614
## Where the crown's middle sits from the top of the skull, in crown radii (up, forward), and how far it is cocked to one
## side (radians, + lifts the pet's left). Found by searching seats against every clip (tools/menu_pet_check.gd checks
## it): sitting lower, the round skull comes through the crown's wall; further back or wider, the ears come through.
const SEAT := Vector2(0.21, 1.15)
const ROLL := 0.25
## Crown shape: a hemisphere, taller than round (room for the logo) and longer front to back.
const CROWN_SCALE := Vector3(1.0, 1.15, 1.08)
## The logo patch: its centre height on the crown (radians above the rim) and its width (radians around).
const PATCH_LIFT := 0.55
const PATCH_WIDE := 1.45
const BADGE_SIZE := 256
## The badge: white disc, dark ring, the team's initial in Inter 800 in the cap colour.
const DISC := Color("f6f6f4")
const RING := Color("1d2026")

var color := Color.WHITE
## The texture on the front panel (the logo, the picture or the runtime badge).
var logo: Texture2D
var panel: MeshInstance3D

## Builds the cap and puts it on `skeleton`'s head bone. Returns the cap, or null when there is no head bone.
static func wear(skeleton: Skeleton3D) -> Node3D:
	var head := -1
	for bone_name: String in HEAD:
		head = skeleton.find_bone(bone_name)
		if head >= 0: break
	if head < 0: return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "CapMount"
	attachment.bone_name = skeleton.get_bone_name(head)
	skeleton.add_child(attachment)
	var fit := _fit(skeleton)
	var size: float = fit.half_width * CROWN_SHARE
	# The top of the skull in model space: the socket our art placed there, else the fitted top, upright.
	var top := Transform3D(Basis(), fit.top)
	var socket := skeleton.find_child(SOCKET, true, false) as Node3D
	if socket != null: top = skeleton.global_transform.affine_inverse() * socket.global_transform
	var seat := top * Transform3D(Basis(Vector3.BACK, ROLL), Vector3(0.0, SEAT.x, SEAT.y) * size)
	var cap = load("res://pet/pet_cap.gd").new(size)
	attachment.add_child(cap)
	cap.transform = skeleton.get_bone_global_rest(head).affine_inverse() * seat
	return cap

## The skull in model space: {top (its highest point, middle of the head), half_width}. From the skull vertices of the
## skinned meshes; from the model's bounds when there are none.
static func _fit(skeleton: Skeleton3D) -> Dictionary:
	var points := PackedVector3Array()
	for mesh_instance: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null: continue
		var skull := {}
		var skin := mesh_instance.skin
		if skin != null:
			for bind in skin.get_bind_count():
				var bone_name := String(skin.get_bind_name(bind))
				if bone_name == "" and skin.get_bind_bone(bind) >= 0: bone_name = skeleton.get_bone_name(skin.get_bind_bone(bind))
				if bone_name in SKULL: skull[bind] = true
		else:
			for bone_name: String in SKULL:
				if skeleton.find_bone(bone_name) >= 0: skull[skeleton.find_bone(bone_name)] = true
		if skull.is_empty(): continue
		var to_model := skeleton.global_transform.affine_inverse() * mesh_instance.global_transform
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null: continue
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(vertices.size(), 1)
			for index in vertices.size():
				var best := 0
				for k in per:
					if weights[index * per + k] > weights[index * per + best]: best = k
				if skull.has(bones[index * per + best]): points.append(to_model * vertices[index])
	if points.size() < 8:
		var bounds := AABB()
		for mesh_instance: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
			var box := (skeleton.global_transform.affine_inverse() * mesh_instance.global_transform) * mesh_instance.get_aabb()
			bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
		return {"top": Vector3(bounds.get_center().x, bounds.end.y - bounds.size.y * 0.1, bounds.get_center().z), "half_width": bounds.size.x * 0.25}
	# The top: the 98th percentile height, so a few stray tuft vertices do not lift the cap.
	var heights: Array[float] = []
	for point in points: heights.append(point.y)
	heights.sort()
	var top := heights[int(heights.size() * 0.98)]
	var low := Vector3(INF, INF, INF)
	var high := -low
	for point in points:
		low = low.min(point)
		high = high.max(point)
	# Front to back: the middle of the skull's top band.
	var front := -INF
	var back := INF
	for point in points:
		if point.y >= top - (high.x - low.x) * 0.1:
			front = maxf(front, point.z)
			back = minf(back, point.z)
	var middle := (front + back) * 0.5 if front > back else (low.z + high.z) * 0.5
	return {"top": Vector3((low.x + high.x) * 0.5, top, middle), "half_width": (high.x - low.x) * 0.5}

## The cap colour from the cast.
static func team_color() -> Color:
	# brand_accent() is clear (alpha 0) when the cast names no brand colour.
	var accent = _cast_call("brand_accent")
	if accent is Color and (accent as Color).a > 0.0: return accent
	return TeamCast.player_color(0)

## The team logo from the cast, or null (then the cap gets the runtime badge).
static func team_logo() -> Texture2D:
	for method: String in ["logo", "picture"]:
		var found = _cast_call(method)
		if found is Texture2D: return found
	return null

## Calls a TeamCast function by name, null when the cast reader has no such function (e.g. a reader without logo() or
## brand_accent()).
static func _cast_call(method: String) -> Variant:
	var cast: Script = load("res://style/team_cast.gd")
	for entry: Dictionary in cast.get_script_method_list():
		if entry.name == method: return cast.call(method)
	return null

func _init(radius := 0.5) -> void:
	name = "PetCap"
	color = team_color()
	var shape := Node3D.new()
	shape.name = "Shape"
	shape.scale = CROWN_SCALE * radius
	add_child(shape)
	var cloth := PetLook.material(color)
	var trim := PetLook.material(color.darkened(0.14))
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 1.0
	crown.is_hemisphere = true
	crown.radial_segments = 40
	crown.rings = 12
	shape.add_child(_part("Crown", crown, cloth, Vector3.ZERO))
	var brim := CylinderMesh.new()
	brim.top_radius = 0.92
	brim.bottom_radius = 0.92
	brim.height = 0.07
	brim.radial_segments = 40
	var visor := _part("Brim", brim, trim, Vector3(0.0, 0.03, 0.42))
	visor.scale = Vector3(1.0, 1.0, 1.45)
	visor.rotation.x = 0.16
	shape.add_child(visor)
	var knob := SphereMesh.new()
	knob.radius = 0.1
	knob.height = 0.2
	shape.add_child(_part("Button", knob, trim, Vector3(0.0, 0.98, 0.0)))
	logo = team_logo()
	if logo == null: logo = _badge()
	panel = _part("Logo", _patch(float(logo.get_width()) / maxf(float(logo.get_height()), 1.0)), _logo_material(logo), Vector3.ZERO)
	shape.add_child(panel)

## The logo: the game look's "hat_logo", else printed flat and bright (no shading), so it reads under any light.
func _logo_material(texture: Texture2D) -> Material:
	var look := PetLook.styled("hat_logo", Color.WHITE, texture)
	if look != null: return look
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material

func _part(part_name: String, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.position = at
	return part

## A patch of the crown's sphere (radius just above it) facing +Z, as wide as PATCH_WIDE and as tall as the logo's aspect
## asks, UVs over the whole texture.
func _patch(aspect: float) -> ArrayMesh:
	var wide := PATCH_WIDE
	var tall := clampf(wide / maxf(aspect, 0.1), 0.45, 1.0)
	if aspect < 1.0: wide = tall * aspect
	var lift := maxf(PATCH_LIFT, tall * 0.5 + 0.06)
	var steps := 12
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in steps + 1:
		for column in steps + 1:
			var u := float(column) / steps
			var v := float(row) / steps
			var around := (u - 0.5) * wide
			var up := lift + (0.5 - v) * tall
			var normal := Vector3(sin(around) * cos(up), sin(up), cos(around) * cos(up))
			tool.set_normal(normal)
			tool.set_uv(Vector2(u, v))
			tool.add_vertex(normal * 1.015)
	for row in steps:
		for column in steps:
			var a := row * (steps + 1) + column
			var b := a + 1
			var c := a + steps + 1
			var d := c + 1
			for index in [a, b, c, b, d, c]: tool.add_index(index)
	return tool.commit()

## The fallback logo: the team's initial on a round white badge, drawn once into a small viewport.
func _badge() -> Texture2D:
	var viewport := SubViewport.new()
	viewport.name = "Badge"
	viewport.size = Vector2i(BADGE_SIZE, BADGE_SIZE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var label := Badge.new()
	label.text = initials(TeamCast.team_name())
	label.font = Ui.inter(800)
	label.fill = color
	label.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	viewport.add_child(label)
	add_child(viewport)
	return viewport.get_texture()

## The badge's letters: the first letter of the team name, or of its first two words ("Night Owls" -> "NO").
static func initials(team: String) -> String:
	var words := team.strip_edges().to_upper().split(" ", false)
	if words.is_empty(): return ""
	var letters := words[0].left(1)
	if words.size() > 1: letters += words[1].left(1)
	return letters

class Badge extends Control:
	const CAP := 0.727 ## Inter's capital height, a share of the font size
	var text := ""
	var font: Font
	var fill := Color.WHITE

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(center, radius, RING, true, -1.0, true)
		draw_circle(center, radius * 0.86, DISC, true, -1.0, true)
		if text == "": return
		# As big as fits the disc: one letter or two side by side.
		var room := radius * (1.05 if text.length() == 1 else 1.25)
		var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
		var font_size := int(minf(100.0 * room / maxf(wide, 1.0), room / CAP))
		var line := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2(center.x - line.x * 0.5, center.y + font_size * CAP * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill)
