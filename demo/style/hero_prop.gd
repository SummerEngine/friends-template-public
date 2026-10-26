extends RefCounted
## The hero prop (docs/hero-prop.md): the stand the crown floats over at the top of CROWN CLIMB, and its small copies on the podium. The
## cast's own hero_prop.glb (TeamCast.hero_prop_model) fitted into the slot's size box, or a stepped stand in the brand colours. Client only,
## pure look: its collision is the level's (cylinder blocks with "slot": "hero_prop", the same three tiers as `tiers()`), the model only skins it.
##
##   HeroProp.build(size)   # size = the `hero_prop` slot's [footprint, height]: the cast's model fitted into the box, else stand(size)
##   HeroProp.stand(size)   # the built-in stand: three tiers in the brand colours, a cream rim on each, the logo on a plaque at the front
##   HeroProp.tiers(size)   # [{d, h, y}]: the stepped stack of cylinders (diameter, height, bottom) the level's blocks must be
##   HeroProp.fit_into(model, box)  # a round's model (TeamCast.round_model) fitted evenly inside `box` (full extents) and centred on the origin, null when it has no size
##
## Frame: the origin is the bottom centre of the footprint, +Y up, the front is +Z. A model of any size and origin is fitted: scaled evenly
## so that it fits the box (footprint = the longer side of its bounds across the floor), its footprint centred on the origin, its bottom on y 0.
const TeamCast := preload("res://style/team_cast.gd")
const ShowCrown := preload("res://style/show_crown.gd")
const TIERS := 3
const SHARES := [1.0, 2.0 / 3.0, 1.0 / 3.0] ## diameter of tier i as a share of the footprint; every tier is height / 3 tall
const REFERENCE_WIDTH := 4.5 ## the footprint the details below are drawn for (metres); smaller boxes scale them
const CandyLook := preload("res://style/candy_look.gd")
const CREAM := CandyLook.PROP_WHITE
const DEFAULTS: Array[Color] = [CandyLook.PROP_BLUE, CandyLook.PROP_PURPLE_DEEP, CandyLook.PROP_AMBER] ## the stand without brand colours
static var _materials := {}

## The built-in stand or the cast's model, `size` = [footprint diameter, height] in metres.
static func build(size: Vector2) -> Node3D:
	var model := _fitted(size)
	return model if model != null else stand(size)

## The stepped stack the collision is: tier i is `h` = height / 3 tall from `y`, `d` = footprint * SHARES[i] across.
static func tiers(size: Vector2) -> Array:
	var result: Array = []
	for tier in TIERS:
		result.append({"d": size.x * float(SHARES[tier]), "h": size.y / TIERS, "y": size.y / TIERS * tier})
	return result

## The cast's hero_prop.glb in a holder, fitted into the box; null when there is none, it does not load or it has no size.
static func _fitted(size: Vector2) -> Node3D:
	var model := TeamCast.hero_prop_model()
	if model == null: return null
	var box := ShowCrown.bounds(model)
	var footprint := maxf(box.size.x, box.size.z)
	if not box.has_volume() or box.size.y <= 0.0001 or footprint <= 0.0001:
		model.free()
		return null
	var fit := minf(size.x / footprint, size.y / box.size.y)
	model.scale = Vector3.ONE * fit
	model.position = -Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5) * fit
	var holder := Node3D.new()
	holder.name = "HeroProp"
	holder.add_child(model)
	return holder

## The model of a round (docs/swappables.md "Rounds as metaphors": the spin bars, the balls) in a holder, scaled evenly (never stretched) by the
## axis it fills most of `box` along, so that it lies inside the box on every axis, and centred on the holder's origin: the centre of its bounds on
## (0, 0, 0). `box` is the hazard's collision box, full extents in metres (x the long axis). Takes the model over; null (the model freed) when it
## has no size.
static func fit_into(model: Node3D, box: Vector3) -> Node3D:
	if model == null: return null
	var bounds := ShowCrown.bounds(model)
	var fit := INF
	for axis in 3:
		if bounds.size[axis] > 0.0001: fit = minf(fit, box[axis] / bounds.size[axis])
	if fit == INF or fit <= 0.0:
		model.free()
		return null
	model.scale = Vector3.ONE * fit
	model.position = -(bounds.position + bounds.size * 0.5) * fit
	var holder := Node3D.new()
	holder.name = "RoundModel"
	holder.add_child(model)
	return holder

## The built-in stand: each tier a drum in one brand colour (bottom to top, from `_colors`) with a darker foot and a cream rim whose flat
## top is the tier's walkable top, and the logo (when the cast has one) on a plaque at the front of the bottom tier.
static func stand(size: Vector2) -> Node3D:
	var holder := Node3D.new()
	holder.name = "HeroStand"
	var unit := size.x / REFERENCE_WIDTH
	var colors := _colors()
	for tier: Dictionary in tiers(size):
		var index := int(round(float(tier.y) / float(tier.h)))
		var radius := float(tier.d) * 0.5
		var color := colors[index]
		var body := float(tier.h) - 0.1 * unit   # the drum runs 0.05 m into the foot and into the rim: no two faces share a plane
		_drum(holder, "Tier%d" % index, radius - 0.04 * unit, body, float(tier.y) + float(tier.h) * 0.5, _paint(color))
		_drum(holder, "Foot%d" % index, radius, 0.12 * unit, float(tier.y) + 0.06 * unit, _paint(color.darkened(0.3)))
		_drum(holder, "Rim%d" % index, radius, 0.12 * unit, float(tier.y) + float(tier.h) - 0.06 * unit, _paint(color.lerp(CREAM, 0.72)))
	var logo := TeamCast.logo()
	if logo != null: _plaque(holder, logo, Vector3(0.0, size.y / TIERS * 0.5, size.x * 0.5 - 0.04 * unit), 0.62 * unit)
	return holder

## The three tier colours: the brand colours, filled up with a darker and a paler shade of the first, else the template's.
static func _colors() -> Array[Color]:
	var listed := TeamCast.brand_colors()
	if listed.is_empty(): return DEFAULTS.duplicate()
	var result: Array[Color] = listed.duplicate()
	if result.size() < 2: result.append(result[0].darkened(0.4))
	if result.size() < 3: result.append(result[0].lerp(CREAM, 0.55))
	return result

static func _drum(holder: Node3D, label: String, radius: float, height: float, centre_y: float, material: Material) -> void:
	var drum := MeshInstance3D.new()
	drum.name = label
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius
	tube.height = height
	tube.radial_segments = 48
	tube.rings = 1
	drum.mesh = tube
	drum.material_override = material
	drum.position = Vector3(0.0, centre_y, 0.0)
	holder.add_child(drum)

## The logo on a cream plate standing proud of the front of a drum, `side` metres square.
static func _plaque(holder: Node3D, logo: Texture2D, at: Vector3, side: float) -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plaque"
	var slab := BoxMesh.new()
	slab.size = Vector3(side * 1.12, side * 1.12, 0.06)
	plate.mesh = slab
	plate.material_override = _paint(CREAM)
	plate.position = at
	holder.add_child(plate)
	var picture := MeshInstance3D.new()
	picture.name = "Logo"
	var face := QuadMesh.new()
	face.size = Vector2.ONE * side
	picture.mesh = face
	var material := StandardMaterial3D.new()
	material.albedo_texture = logo
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.6
	picture.material_override = material
	picture.position = at + Vector3(0.0, 0.0, 0.032)
	picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(picture)

static func _paint(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = CandyLook.ROUGH_PLASTIC
		_materials[key] = material
	return _materials[key]
