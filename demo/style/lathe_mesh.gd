extends RefCounted
## Round machine parts for the race world's obstacles (style/spinner_look.gd, style/cannon_look.gd): surfaces of revolution with per-band vertex colours (in the candy look's
## course hues, the alpha of a tint choosing hard plastic, vinyl or striped vinyl: style/candy_prop.gdshader), merged
## into ONE ArrayMesh with ONE shared material per look, so a whole spinner (hub, base, collars, bars) or cannon is a single draw call. A profile is a list of
## [distance from the axis, height, colour] points walked from the bottom to the top over the outside of the part (the colour is that of the band ENDING at the
## point; the first point's is ignored); normals follow the bands and are smoothed over every joint flatter than SMOOTH_ANGLE, so chamfers and rounded rims
## shade round while a step stays a crisp edge. A part overlaps its neighbours volumetrically (bars run into the hub, collars round the bars): no coplanar faces.
const BlockMesh := preload("res://style/block_mesh.gd") ## only its triangle group
const SMOOTH_ANGLE := 70.0     ## degrees: joints between bands flatter than this share a normal
const CandyLook := preload("res://style/candy_look.gd")
const SHADER := preload("res://style/candy_prop.gdshader")
## The tint of a band carries its material family in the ALPHA (style/candy_prop.gdshader): 1.0 hard plastic, 0.5 vinyl, 0.0 vinyl with diagonal white stripes.
const PLASTIC := 1.0
const VINYL := 0.5
const STRIPED := 0.0
const PINK := Color(CandyLook.PROP_PINK, PLASTIC)              ## a hub, a collar
const PINK_DEEP := Color(CandyLook.PROP_PINK_DEEP, PLASTIC)
const PINK_BAR := Color(CandyLook.PROP_PINK, STRIPED)          ## an inflatable bar: pink with white stripes
const PINK_SOFT := Color(CandyLook.PROP_PINK, VINYL)           ## ... and its plain end
const WHITE := Color(CandyLook.PROP_WHITE, PLASTIC)
const AMBER := Color(CandyLook.PROP_AMBER, PLASTIC)
const AMBER_DEEP := Color(CandyLook.PROP_AMBER_DEEP, PLASTIC)
const AMBER_LIGHT := Color(CandyLook.PROP_AMBER_LIGHT, PLASTIC)
const PURPLE := Color(CandyLook.PROP_PURPLE, PLASTIC)
const PURPLE_DEEP := Color(CandyLook.PROP_PURPLE_DEEP, PLASTIC)
const PURPLE_LIGHT := Color(CandyLook.PROP_PURPLE_LIGHT, PLASTIC)
const BLUE := Color(CandyLook.PROP_BLUE, PLASTIC)

static var _material: ShaderMaterial

## The shared material of every lathe look: the candy prop surface (flat tint from the vertex colour, glossy, white stripes on the striped family).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("rough_plastic", CandyLook.ROUGH_PLASTIC)
		_material.set_shader_parameter("rough_vinyl", CandyLook.ROUGH_VINYL)
		_material.set_shader_parameter("rough_striped", CandyLook.ROUGH_VINYL_GLOSSY)
		_material.set_shader_parameter("stripe_color", CandyLook.PROP_WHITE)
	return _material

## Triangles under construction; `commit` leaves them as one mesh (null when empty).
class Build extends RefCounted:
	var group := BlockMesh.Group.new()

	## A profile spun about the y axis of `xf` (part space -> mesh space), `sides` steps round. The UV of a vertex is (the turn in whole stripe periods, the height in periods): what
	## the striped family of style/candy_prop.gdshader reads (`stripe_period` m: one stripe and its gap; the turn count is rounded so the stripes meet at the seam).
	func lathe(xf: Transform3D, profile: Array, sides := 16, stripe_period := CandyLook.STRIPE_PERIOD) -> void:
		var count := profile.size() - 1
		var widest := 0.0
		for point: Array in profile: widest = maxf(widest, float(point[0]))
		var turns := maxf(roundf(TAU * widest / stripe_period), 1.0)
		var normals: Array[Vector2] = []
		for k in count:
			var a: Array = profile[k]
			var b: Array = profile[k + 1]
			var dr := float(b[0]) - float(a[0])
			var dy := float(b[1]) - float(a[1])
			normals.append(Vector2(dy, -dr).normalized() if dr * dr + dy * dy > 1e-10 else Vector2.ZERO)
		var limit := cos(deg_to_rad(SMOOTH_ANGLE))
		for k in count:
			if normals[k] == Vector2.ZERO: continue
			var a: Array = profile[k]
			var b: Array = profile[k + 1]
			var color: Color = (b[2] as Color).srgb_to_linear()
			var ends := [a, b]
			var end_normals: Array[Vector2] = [normals[k], normals[k]]
			var before := _neighbour(normals, k, -1)
			var after := _neighbour(normals, k, 1)
			if before != Vector2.ZERO and before.dot(normals[k]) > limit: end_normals[0] = (before + normals[k]).normalized()
			if after != Vector2.ZERO and after.dot(normals[k]) > limit: end_normals[1] = (after + normals[k]).normalized()
			var base := group.v.size()
			for step in sides + 1:
				var angle := TAU * float(step) / sides
				var around := Vector3(cos(angle), 0.0, sin(angle))
				for e in 2:
					var p: Array = ends[e]
					var n2 := end_normals[e]
					group.add(xf * (around * float(p[0]) + Vector3(0.0, float(p[1]), 0.0)), (xf.basis * (around * n2.x + Vector3(0.0, n2.y, 0.0))).normalized(), Vector2(turns * float(step) / sides, float(p[1]) / stripe_period), color)
			for step in sides:
				var i0 := base + step * 2
				group.quad(i0, i0 + 2, i0 + 3, i0 + 1, group.n[i0] + group.n[i0 + 3])

	## The nearest band with a direction before (`step` -1) or after (+1) band `k`, when it touches it.
	static func _neighbour(normals: Array[Vector2], k: int, step: int) -> Vector2:
		var at := k + step
		return normals[at] if at >= 0 and at < normals.size() else Vector2.ZERO

	func commit(material: Material) -> ArrayMesh:
		if group.i.is_empty(): return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.v
		arrays[Mesh.ARRAY_NORMAL] = group.n
		arrays[Mesh.ARRAY_TEX_UV] = group.uv
		arrays[Mesh.ARRAY_COLOR] = group.c
		arrays[Mesh.ARRAY_INDEX] = group.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh

## Points of the arc of radius `rho` round the centre (`cr`, `cy`) from `from_deg` to `to_deg` (degrees counter-clockwise from the +r axis in the profile plane: -90 the
## bottom of the circle, 0 its outside, 90 its top), the start excluded, `steps` bands in `color`: a rounded rim, a dome (centre on the axis) or a ring's tube.
static func arc(cr: float, cy: float, rho: float, from_deg: float, to_deg: float, color: Color, steps := 3) -> Array:
	var points: Array = []
	for k in range(1, steps + 1):
		var angle := deg_to_rad(lerpf(from_deg, to_deg, float(k) / steps))
		points.append([cr + rho * cos(angle), cy + rho * sin(angle), color])
	return points

## `profile` reflected about the height `centre` and walked the other way round (bottom to top again); the band colours move with their bands.
static func mirror(profile: Array, centre: float) -> Array:
	var count := profile.size()
	var out: Array = []
	for k in count:
		var source: Array = profile[count - 1 - k]
		var band: Array = profile[count - k] if k > 0 else source
		out.append([source[0], 2.0 * centre - float(source[1]), band[2]])
	return out
