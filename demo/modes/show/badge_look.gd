extends RefCounted
## The logo of KEEP THE LOGO (modes/show/view.gd): a round enamel plate wearing the team's logo (else the brand accent's own mark), rimmed in the brand
## accent. One on the wearer's back, and a bigger one that turns over the wearer's head so everybody sees who has it from any side. Client only,
## pure look: nothing here is replicated or decides anything.
##
##   BadgeLook.plate(radius)     # the plate, +Z facing, origin at its middle (hangs on a back: the character faces -Z)
##   BadgeLook.floating(radius)  # a double-sided plate that turns about +Y (over the head)
const TeamCast := preload("res://style/team_cast.gd")
const THICK := 0.035
const SEGMENTS := 36

static var _materials := {}

static func plate(radius := 0.2) -> Node3D:
	var holder := Node3D.new()
	holder.name = "LogoPlate"
	_disc(holder, "Rim", radius, THICK, 0.0, _flat("rim_" + TeamCast.brand_accent().to_html(), TeamCast.brand_accent()))
	_disc(holder, "Enamel", radius * 0.86, THICK * 1.4, 0.0, _flat("enamel_" + TeamCast.logo_backing().to_html(), TeamCast.logo_backing()))
	var logo := TeamCast.logo()
	var face := MeshInstance3D.new()
	face.name = "Logo"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * radius * 1.45
	face.mesh = quad
	face.material_override = _logo_material(logo)
	face.position = Vector3(0.0, 0.0, THICK * 0.7 + 0.002)
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(face)
	return holder

## Two plates back to back inside a holder you turn (about +Y) and bob.
static func floating(radius := 0.3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "LogoFloat"
	var front := plate(radius)
	front.position.z = THICK * 0.5
	holder.add_child(front)
	var back := plate(radius)
	back.rotation.y = PI
	back.position.z = -THICK * 0.5
	holder.add_child(back)
	return holder

static func _disc(parent: Node3D, label: String, radius: float, depth: float, z: float, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var cylinder := CylinderMesh.new() # axis along Z once turned
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = depth
	cylinder.radial_segments = SEGMENTS
	cylinder.rings = 1
	node.mesh = cylinder
	node.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	node.position = Vector3(0.0, 0.0, z)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func _logo_material(logo: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if logo != null:
		material.albedo_texture = logo
	else:
		material.albedo_color = Color(0, 0, 0, 0) # no logo: the enamel and the rim are the mark
	return material

static func _flat(key: String, color: Color) -> StandardMaterial3D:
	if _materials.has(key) and is_instance_valid(_materials[key]): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.45
	material.metallic = 0.1
	_materials[key] = material
	return material
