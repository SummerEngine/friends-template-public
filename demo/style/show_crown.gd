extends RefCounted
## The show's crown: a chunky cartoon crown built in code (a rounded gold ring rising in five rounded points with a gold ball on each, three bevel gems in gold bezels on the front, the brand accent
## on the gems), one ArrayMesh. Or the cast's own crown.glb (style/team_cast.gd crown_model) when there is one. Client only, pure look.
##
##   ShowCrown.build(height)      # the built-in crown: origin at its base centre, +Y up, `height` tall, 1.2 x `height` across, the front (a gem) at +Z
##   ShowCrown.crown(height)      # the cast's crown.glb scaled to `height` when it loads, else build(height)
##   ShowCrown.floating(height)   # crown(height) in a holder that turns slowly and bobs a little: the crown over the pedestal at the top of the climb
##   ShowCrown.plate(holder, logo, at, size)   # the logo on a bevel enamel plate facing +Z (the START gate, style/start_gate.gd)
## On the winner's head the view parents the crown to the character's head anchor (character_rig.gd `head_anchor`, modes/show/view.gd).
const TeamCast := preload("res://style/team_cast.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const PadLook := preload("res://style/pad_look.gd")
const POINTS := 5
const BAND := 0.38             ## the ring's height between the points, as a share of the crown's height
const BALL := 0.07             ## the tip balls' radius, as a share of the height
const CandyLook := preload("res://style/candy_look.gd")
const GOLD := CandyLook.PROP_AMBER   ## the crown: glossy amber plastic
const GEM := CandyLook.PROP_PINK
const SPIN := 0.9              ## turn speed of the floating crown (rad/s)
static var _materials := {}

## The built-in crown: a chunky cartoon crown, built in code. A rounded gold ring whose top edge rises in five rounded points, a gold ball on every point, three bevel gems in gold bezels on the
## front, 1.2 x `height` across. Smooth shaded, no flat shards: the ring is one swept section (a rounded rectangle) whose height follows the points.
static func build(height := 0.5) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Crown"
	var outer := height * 0.6
	var thick := outer * 0.17
	var band := height * BAND
	var ball := height * BALL
	var peak := height - ball * 1.55 # the ring's height at the top of a point
	var batch := BlockMesh.Batch.new()
	var gold := batch.group("gold")
	var gems := batch.group("gem")
	_ring(gold, outer, thick, band, peak)
	for point in POINTS:
		var angle := TAU * float(point) / POINTS
		var at := Vector3(sin(angle), 0.0, cos(angle)) * (outer - thick * 0.5) + Vector3(0.0, peak + ball * 0.55, 0.0)
		PadLook.revolve(gold, _sphere(ball), 16, at)
	var turn_to := func(angle: float) -> Basis:
		var radial := Vector3(sin(angle), 0.0, cos(angle))
		return Basis(radial.cross(Vector3.UP), radial, Vector3.UP)
	var seat := band * 0.5
	for gem in [-1, 0, 1]:
		var angle := TAU * float(gem) / POINTS
		var turn: Basis = turn_to.call(angle)
		var at := Vector3(sin(angle), 0.0, cos(angle)) * (outer - height * 0.03) + Vector3(0.0, seat, 0.0)
		var gem_r := band * 0.27
		PadLook.revolve(gold, _bezel(gem_r * 1.5, height * 0.06), 20, at, turn)
		PadLook.revolve(gems, _dome(gem_r, gem_r * 0.8, height * 0.04), 20, at, turn)
	var mesh := batch.commit({"gold": _gold(), "gem": _gem_paint()})
	var body := MeshInstance3D.new()
	body.name = "Band"
	body.mesh = mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(body)
	return holder

## The cast's crown.glb scaled to `height`, else the built-in crown. A model that does not load or has no size falls back silently.
static func crown(height := 0.5) -> Node3D:
	var model := TeamCast.crown_model()
	if model == null: return build(height)
	var box := bounds(model)
	if not box.has_volume() or box.size.y <= 0.0001:
		model.free()
		return build(height)
	var holder := Node3D.new()
	holder.name = "Crown"
	model.scale = Vector3.ONE * (height / box.size.y)
	holder.add_child(model)
	return holder

## crown(height) in a holder that turns slowly about +Y and bobs by `bob` metres: the origin of the holder is the crown's base centre.
static func floating(height := 0.5, bob := 0.04) -> Node3D:
	var spinner := Spinner.new()
	spinner.name = "FloatingCrown"
	spinner.bob = bob
	spinner.body = crown(height)
	spinner.add_child(spinner.body)
	return spinner

## Turns its body and bobs it; nothing else.
class Spinner extends Node3D:
	var body: Node3D
	var bob := 0.04
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		body.rotation.y += SPIN * delta
		body.position.y = sin(_time * 1.6) * bob

# ------------------------------------------------------------------ geometry

## The ring: a rounded-rectangle section (`thick` wide, its outer wall at radius `outer`) swept bevel the axis, its top at height `band` between the points and `peak` at the top of each one (a smooth hump
## per point, the first at +Z). Smooth normals from the grid itself; the quads wind themselves from the normal.
static func _ring(group: BlockMesh.Group, outer: float, thick: float, band: float, peak: float) -> void:
	var around := POINTS * 20
	var bevel := thick * 0.42
	var inner := outer - thick
	var corners: Array = [[outer - bevel, -90.0, 0.0, false], [outer - bevel, 0.0, 90.0, true], [inner + bevel, 90.0, 180.0, true], [inner + bevel, 180.0, 270.0, false]] # [centre radius, from, to (degrees), on the top edge]
	var grid: Array = [] # per step bevel the axis: the section's points
	var centres: Array[Vector3] = []
	for step in around:
		var angle := TAU * float(step) / around
		var radial := Vector3(sin(angle), 0.0, cos(angle))
		var share := fposmod(float(step) / 20.0, 1.0)
		var hump := 0.5 + 0.5 * cos(TAU * share) # 1 at the middle of a point (the first at +Z), 0 between two
		var top := lerpf(band, peak, pow(hump, 1.5))
		var row: Array[Vector3] = []
		for corner: Array in corners:
			for k in 4:
				var a := deg_to_rad(lerpf(float(corner[1]), float(corner[2]), float(k) / 3.0))
				var y := (top - bevel if bool(corner[3]) else bevel) + sin(a) * bevel
				row.append(radial * (float(corner[0]) + cos(a) * bevel) + Vector3(0.0, y, 0.0))
		grid.append(row)
		centres.append(radial * (outer - thick * 0.5) + Vector3(0.0, top * 0.5, 0.0))
	var width: int = (grid[0] as Array).size()
	var index: Array = []
	for step in around:
		var ring_row: Array = []
		for j in width:
			var before: Vector3 = grid[(step + around - 1) % around][j]
			var after: Vector3 = grid[(step + 1) % around][j]
			var down: Vector3 = grid[step][(j + width - 1) % width]
			var up: Vector3 = grid[step][(j + 1) % width]
			var normal := (after - before).cross(up - down).normalized()
			if normal.dot((grid[step][j] as Vector3) - centres[step]) < 0.0: normal = -normal
			ring_row.append(group.add(grid[step][j], normal, Vector2(float(step), float(j)), Color.WHITE))
		index.append(ring_row)
	for step in around:
		var next := (step + 1) % around
		for j in width:
			var after := (j + 1) % width
			group.quad(index[step][j], index[next][j], index[next][after], index[step][after], group.n[index[step][j]])

## A ball of radius `radius` as a revolve profile about its own centre.
static func _sphere(radius: float) -> Array:
	var profile: Array = []
	for k in 11:
		var phi := PI * float(k) / 10.0
		profile.append([sin(phi) * radius, -cos(phi) * radius, Vector2(sin(phi), -cos(phi)), Color.WHITE])
	return profile

## A flat rounded disc (a gem's bezel), its axis up: radius `radius`, from `sink` under the origin to `rise` over it.
static func _bezel(radius: float, total: float) -> Array:
	var bevel := total * 0.4
	var low := -total * 0.5
	var high := total * 0.5
	var profile: Array = [[0.0, low, Vector2(0.0, -1.0), Color.WHITE], [radius - bevel, low, Vector2(0.0, -1.0), Color.WHITE]]
	for k in range(0, 4):
		var a := -PI * 0.5 + PI * 0.5 * float(k) / 3.0
		profile.append([radius - bevel + cos(a) * bevel, low + bevel + sin(a) * bevel, Vector2(cos(a), sin(a)), Color.WHITE])
	for k in range(0, 4):
		var a := PI * 0.5 * float(k) / 3.0
		profile.append([radius - bevel + cos(a) * bevel, high - bevel + sin(a) * bevel, Vector2(cos(a), sin(a)), Color.WHITE])
	profile.append([0.0, high, Vector2(0.0, 1.0), Color.WHITE])
	return profile

## A gem: a dome of radius `radius` and height `rise` standing on a bezel of thickness `base` (its origin is the bezel's middle).
static func _dome(radius: float, rise: float, base: float) -> Array:
	var profile: Array = [[0.0, base * 0.4, Vector2(0.0, -1.0), Color.WHITE]]
	for k in range(0, 9):
		var a := PI * 0.5 * float(k) / 8.0
		profile.append([cos(a) * radius, base * 0.4 + sin(a) * rise, Vector2(cos(a) * rise, sin(a) * radius).normalized(), Color.WHITE])
	return profile

## The union of the meshes of a loaded model, in the model's own space (its root's transform left out). Also what style/hero_prop.gd fits by.
static func bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual.mesh == null: continue
		var xf := Transform3D.IDENTITY
		var up: Node = visual
		while up != null and up != model:
			xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var part := xf * visual.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box

## The logo on a small dark plate, lying flat on the front of `holder` (both quads face +Z).
static func plate(holder: Node3D, logo: Texture2D, at: Vector3, size: float) -> void:
	var backing := MeshInstance3D.new()
	backing.name = "Plate"
	var disc := CylinderMesh.new() # a bevel enamel plate, its axis along the crown's front
	disc.top_radius = size * 0.62
	disc.bottom_radius = size * 0.62
	disc.height = size * 0.01
	disc.radial_segments = 32
	disc.rings = 1
	backing.mesh = disc
	backing.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var enamel := TeamCast.logo_backing() # white behind a dark or colourful logo, ink behind a pale one
	backing.material_override = _flat("plate_" + enamel.to_html(), enamel)
	backing.position = at
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(backing)
	var face_node := MeshInstance3D.new()
	face_node.name = "Logo"
	var face := QuadMesh.new()
	face.size = Vector2.ONE * size
	face_node.mesh = face
	var material := StandardMaterial3D.new()
	material.albedo_texture = logo
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.6
	face_node.material_override = material
	face_node.position = at + Vector3(0.0, 0.0, size * 0.01)
	face_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(face_node)

# ------------------------------------------------------------------ materials

static func _gold() -> StandardMaterial3D:
	if not _materials.has("gold"):
		var material := StandardMaterial3D.new()
		material.albedo_color = GOLD
		material.roughness = CandyLook.ROUGH_PLASTIC
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["gold"] = material
	return _materials["gold"]

## The gems: the brand accent, else ruby red.
static func _gem_paint() -> StandardMaterial3D:
	var accent := TeamCast.brand_accent()
	var color := accent if accent.a > 0.0 else GEM
	var key := "gem" + color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = CandyLook.ROUGH_PLASTIC
		_materials[key] = material
	return _materials[key]

static func _flat(key: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = CandyLook.ROUGH_PLASTIC
		_materials[key] = material
	return _materials[key]
