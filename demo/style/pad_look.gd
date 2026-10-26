extends RefCounted
## A launch pad of a `world: daylight` level as a real BUTTON (levels/hazards.gd `push`, drawn by style/hazard_looks.gd as a flat plate and re-dressed here by
## style/race_hazard_looks.gd): a white collar round a well, and in the well a round pink-ringed button with a rounded rim that PRESSES DOWN
## when a courier steps on it and springs back. Look only: the launch volume, the launch and every number stay with levels/level_world.gd; the node here only
## plays the press when that file tells it a courier set the pad off (`Press.press`: from `effects_at` for a courier this machine simulates, from `observe_pads` for every
## courier it only sees, both for the same launch, the second one ignored while the press is still on).
##   LaunchPad (Press)   origin on the floor under the volume, y up
##     Base              collar + well, one shared mesh per pad size (vertex colours), never moves
##     Button            one shared mesh per pad size (rings in its shader, by distance from the axis), sinks TRAVEL m
## Cost: about 1000 triangles and 2 draw calls per pad; the meshes and the shader are shared, a pad owns only its button's material (the glow of a press).
const BlockMesh := preload("res://style/block_mesh.gd")
const BlockKit := preload("res://style/block_kit.gd")
const CandyLook := preload("res://style/candy_look.gd")
const CREAM := CandyLook.PROP_WHITE          ## the collar and the button's rim: white hard plastic
const ORANGE := CandyLook.PROP_PINK          ## the button's rings: hot pink and a light pink
const YELLOW := CandyLook.PROP_PINK_LIGHT
const COLLAR_WIDTH := 0.2       ## m: the white ring round the well
const GAP := 0.045              ## m: the dark gap between the button and the collar
const COLLAR_TOP := 0.1         ## m: the collar's top over the floor (its foot is ON the tile top: nothing of the pad goes into the tiles)
const BUTTON_TOP := 0.21        ## m: the button's top over the floor at rest (0.11 over the collar: it stands out of the well)
const BUTTON_FOOT := 0.15       ## m: the button's underside at rest; a press (TRAVEL) ends 0.02 m over the well's floor, so the button never reaches into the floor
const DOME := 0.07              ## m: how much higher the button's middle stands than its rim
const DOME_ROWS := 4
const BEVEL := 0.05             ## m: the rounded rim of the button
const SIDES := 36
const TRAVEL := 0.13            ## m: how far a press sinks the button (its top ends 0.02 m over the floor, under the collar)
const T_DOWN := 0.09            ## s: the button goes down ...
const T_HOLD := 0.14            ## s: ... stays ...
const T_UP := 0.3               ## s: ... and springs back (a little past rest)
const CELL_MARGIN := 0.4        ## m: the pad's outer diameter is the 2 x 2 tile cell's side minus this (2.7 m of a 3.1 m cell)
const FULL_SLACK := 0.5         ## m: a launch volume at least the tile grid's side less this is a pad over the whole stone
const FULL_CENTRE := 0.1        ## m: ... and its middle is this near the stone's middle
const STRIP_MAX := 0.85         ## m: the guide strips in the corners of the cell, along the diagonal towards the pad: at most this long ...
const STRIP_WIDTH := 0.26
const STRIP_COLOR := CandyLook.PROP_WHITE
const STRIP_RISE := 0.045       ## m: how far a strip stands over the floor
const IGNORE := 0.2             ## s: a second press of the same launch (the local courier is told twice: by the simulation and by the look's own watch) is ignored this long

## The rings of the button by distance from the axis (1 = the rim of the flat top): pink centre, light pink, pink, light pink, pink, the white rim. `glow` brightens it while it is pressed.
const BUTTON_SHADER := "shader_type spatial;\nuniform vec4 cream : source_color;\nuniform vec4 orange : source_color;\nuniform vec4 yellow : source_color;\nuniform float radius = 0.75;\nuniform float glow = 0.0;\nvarying vec3 lp;\nvarying float up;\n" + """
void vertex() { lp = VERTEX; up = NORMAL.y; }
void fragment() {
	float r = length(lp.xz) / radius;
	float w = 0.012;
	vec3 c = orange.rgb;
	c = mix(c, yellow.rgb, smoothstep(0.2 - w, 0.2 + w, r));
	c = mix(c, orange.rgb, smoothstep(0.42 - w, 0.42 + w, r));
	c = mix(c, yellow.rgb, smoothstep(0.6 - w, 0.6 + w, r));
	c = mix(c, orange.rgb, smoothstep(0.78 - w, 0.78 + w, r));
	c = mix(c, cream.rgb, smoothstep(0.88 - w, 0.88 + w, r));
	if (up < 0.5) c = orange.rgb * 0.8;
	ALBEDO = c;
	EMISSION = c * glow * 0.5;
	ROUGHNESS = 0.11;
}
"""

static var _shader: Shader
static var _meshes := {}
static var _base_material: StandardMaterial3D

## Replaces `plate` (the flat plate style/hazard_looks.gd drew: a cylinder or a box mesh, in the area's frame, thick as HazardLooks.PAD_HEIGHT) with a button pad
## of the same footprint standing on the same floor; returns it.
static func dress(plate: MeshInstance3D, plate_height: float, cell := 0.0) -> Press:
	var radius := 1.0
	if plate.mesh is CylinderMesh: radius = (plate.mesh as CylinderMesh).top_radius
	elif plate.mesh is BoxMesh: radius = minf((plate.mesh as BoxMesh).size.x, (plate.mesh as BoxMesh).size.z) * 0.5
	var pad := Press.new()
	pad.name = "LaunchPad"
	pad.transform = plate.transform
	pad.position += plate.transform.basis * Vector3(0.0, -plate_height * 0.5, 0.0) # the plate's origin is its middle: the pad's is the floor
	var parent := plate.get_parent()
	var index := plate.get_index()
	parent.remove_child(plate)
	plate.free()
	parent.add_child(pad)
	parent.move_child(pad, index)
	if cell > 0.0: radius = (cell - CELL_MARGIN) * 0.5 # on a 2 x 2 tile cell: the round pad sits in it with a margin, a guide strip in each corner
	var meshes := _pad_meshes(radius, cell)
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = meshes.base
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.add_child(base)
	var button := MeshInstance3D.new()
	button.name = "Button"
	button.mesh = meshes.button
	var material := ShaderMaterial.new()
	material.shader = _button_shader()
	material.set_shader_parameter("cream", CREAM)
	material.set_shader_parameter("orange", ORANGE)
	material.set_shader_parameter("yellow", YELLOW)
	material.set_shader_parameter("radius", _button_radius(radius) - BEVEL)
	button.material_override = material
	pad.add_child(button)
	pad.button = button
	pad.material = material
	return pad

static func _button_radius(radius: float) -> float:
	return maxf(radius - COLLAR_WIDTH - GAP, 0.3)

static func _button_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BUTTON_SHADER
	return _shader

## {base, button}: the meshes of a pad whose footprint has this `radius`, made once per radius.
static func _pad_meshes(radius: float, cell: float) -> Dictionary:
	var key := roundi(radius * 100.0) * 1000 + roundi(cell * 100.0)
	if _meshes.has(key): return _meshes[key]
	var well := _button_radius(radius) + GAP
	var collar := BlockMesh.Batch.new()
	var group := collar.group("base")
	var profile: Array = [[radius, 0.0, Vector2(1.0, 0.0), CREAM], [radius, COLLAR_TOP - 0.04, Vector2(1.0, 0.0), CREAM]]
	for k in range(1, 4): # the collar's outer rim, rounded
		var angle := PI * 0.5 * float(k) / 3.0
		profile.append([radius - 0.04 + cos(angle) * 0.04, COLLAR_TOP - 0.04 + sin(angle) * 0.04, Vector2(cos(angle), sin(angle)), CREAM])
	profile.append([well + 0.02, COLLAR_TOP, Vector2(0.0, 1.0), CREAM])
	for k in range(1, 3): # ... and its inner rim
		var angle := PI * 0.5 + PI * 0.5 * float(k) / 2.0
		profile.append([well + 0.02 + cos(angle) * 0.02, COLLAR_TOP - 0.02 + sin(angle) * 0.02, Vector2(cos(angle), sin(angle)), CREAM])
	profile.append([well, 0.0, Vector2(-1.0, 0.0), CREAM])
	revolve(group, profile)
	if cell > 0.0:
		var corner_at := cell * 0.5 * sqrt(2.0)     # the cell's corner, from the pad's middle
		var length := clampf(corner_at - radius - 0.2, 0.4, STRIP_MAX)
		var middle := radius + (corner_at - radius - length) * 0.5 + length * 0.5
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var heading := corner.normalized()
			strip(group, heading * middle, heading, length, STRIP_WIDTH)
	var top := _button_radius(radius)
	var rim_top := BUTTON_TOP - DOME # the rim stands DOME lower than the middle: the button is a domed cushion (its middle keeps BUTTON_TOP, so a courier on it stands at BUTTON_TOP)
	var shape: Array = [[0.0, BUTTON_FOOT, Vector2(0.0, -1.0), Color.WHITE], [top - 0.01, BUTTON_FOOT, Vector2(0.0, -1.0), Color.WHITE], [top, BUTTON_FOOT + 0.01, Vector2(1.0, 0.0), Color.WHITE], [top, rim_top - BEVEL, Vector2(1.0, 0.0), Color.WHITE]]
	for k in range(1, 4):
		var angle := PI * 0.5 * float(k) / 3.0
		shape.append([top - BEVEL + cos(angle) * BEVEL, rim_top - BEVEL + sin(angle) * BEVEL, Vector2(cos(angle), sin(angle)), Color.WHITE])
	var reach := top - BEVEL
	for k in range(1, DOME_ROWS + 1): # the dome: a parabola from the rim's flat to the middle, smooth normals
		var r := reach * (1.0 - float(k) / DOME_ROWS)
		var slope := 2.0 * DOME * r / (reach * reach)
		shape.append([r, rim_top + DOME * (1.0 - (r * r) / (reach * reach)), Vector2(slope, 1.0).normalized(), Color.WHITE])
	var plunger := BlockMesh.Batch.new()
	revolve(plunger.group("button"), shape)
	var made := {"base": collar.commit({"base": _collar_material()}), "button": plunger.commit({"button": null})}
	_meshes[key] = made
	return made

static func _collar_material() -> StandardMaterial3D:
	if _base_material == null:
		_base_material = StandardMaterial3D.new()
		_base_material.vertex_color_use_as_albedo = true
		_base_material.roughness = CandyLook.ROUGH_PLASTIC
	return _base_material

## A surface of revolution about the vertical axis (turned by `turn`) through `at`: `profile` rows [distance from the axis, y, normal (out, up), colour], first to last.
static func revolve(group: BlockMesh.Group, profile: Array, sides := SIDES, at := Vector3.ZERO, turn := Basis.IDENTITY) -> void:
	for band in profile.size() - 1:
		var lo: Array = profile[band]
		var hi: Array = profile[band + 1]
		var first := group.v.size()
		for k in sides + 1:
			var angle := TAU * float(k) / sides
			var around := Vector3(cos(angle), 0.0, sin(angle))
			for row: Array in [lo, hi]:
				var n2: Vector2 = row[2]
				group.add(at + turn * (around * float(row[0]) + Vector3(0.0, float(row[1]), 0.0)), (turn * (around * n2.x + Vector3(0.0, n2.y, 0.0))).normalized(), Vector2(angle, float(row[1])), row[3])
		for k in sides:
			var i0 := first + k * 2
			group.quad(i0, i0 + 2, i0 + 3, i0 + 1, group.n[i0] + group.n[i0 + 3])

## A raised white guide strip (a capsule: two round ends) lying along `heading` (xz unit) centred at `at` (xz), `length` by `width`, its top STRIP_RISE over the floor, bevelled.
static func strip(group: BlockMesh.Group, at: Vector2, heading: Vector2, length: float, width: float) -> void:
	var across := Vector2(-heading.y, heading.x)
	var half_core := (length - width) * 0.5
	var outline: Array = [] # [point xz, outward normal xz]
	for end: float in [1.0, -1.0]:
		for k in 9:
			var angle := -PI * 0.5 + PI * float(k) / 8.0
			var normal := heading * (cos(angle) * end) + across * (sin(angle) * end)
			outline.append([at + heading * (half_core * end) + normal * (width * 0.5), normal])
	var rows: Array = [[0.0, 0.0, 1.0, 0.0], [0.0, STRIP_RISE - 0.018, 1.0, 0.0], [0.018, STRIP_RISE, 0.7, 0.7]] # inset, y, share of the outward normal, share of up
	var rings: Array = []
	for row: Array in rows:
		var ring: Array = []
		for item: Array in outline:
			var normal: Vector2 = item[1]
			var shaded := Vector3(normal.x * float(row[2]), float(row[3]), normal.y * float(row[2])).normalized()
			var point: Vector2 = (item[0] as Vector2) - normal * float(row[0])
			ring.append(group.add(Vector3(point.x, float(row[1]), point.y), shaded, point, STRIP_COLOR))
		rings.append(ring)
	for r in rings.size() - 1:
		var lo: Array = rings[r]
		var hi: Array = rings[r + 1]
		for k in lo.size():
			var n := (k + 1) % lo.size()
			group.quad(lo[k], lo[n], hi[n], hi[k], group.n[lo[k]] + group.n[lo[n]])
	var top := group.add(Vector3(at.x, STRIP_RISE, at.y), Vector3.UP, Vector2(at.x, at.y), STRIP_COLOR)
	var last: Array = rings[rings.size() - 1]
	var tops: Array = []
	for k in last.size(): tops.append(group.add(group.v[last[k]], Vector3.UP, Vector2(group.v[last[k]].x, group.v[last[k]].z), STRIP_COLOR))
	for k in tops.size(): group.triangle(top, tops[k], tops[(k + 1) % tops.size()], Vector3.UP)

## The side (m) of the 2 x 2 tile cell a pad stands on: the platform box under `pad` (a static collision box of `level_root` whose top is the pad's floor, level space) asked for
## BlockKit.tile_grid; 0 when no platform with such a cell is under it. A cell is 2 tiles and a groove. A pad that covers the whole of a small stone (the stone's grid is n x n tiles, the pad
## stands in its middle and its launch volume is about as wide as the grid, within FULL_SLACK) takes the whole grid: n tiles and n - 1 grooves (3 x 3 tiles on a 4.5 m stone).
static func cell_side(level_root: Node3D, pad: Node3D) -> float:
	var volume := 0.0 # the launch volume's diameter (the plate's)
	var plate := pad as MeshInstance3D
	if plate != null and plate.mesh is CylinderMesh: volume = (plate.mesh as CylinderMesh).top_radius * 2.0
	var to_level := level_root.global_transform.affine_inverse()
	var at := to_level * pad.global_position
	var best := 0.0
	for node: Node in level_root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null or not shape_node.shape is BoxShape3D or shape_node.get_parent() is AnimatableBody3D: continue
		var size := (shape_node.shape as BoxShape3D).size
		var xf := to_level * shape_node.global_transform
		var local := xf.affine_inverse() * at
		if absf(local.x) > size.x * 0.5 or absf(local.z) > size.z * 0.5 or absf(local.y - size.y * 0.5) > 0.15: continue
		var grid := BlockKit.tile_grid(xf, size)
		if grid.is_empty() or int(grid.nx) < 2 or int(grid.nz) < 2: continue
		best = 2.0 * float(grid.t) + BlockKit.GROOVE
		var n := int(grid.nx)
		var span := float(n) * float(grid.t) + float(n - 1) * BlockKit.GROOVE
		if n == int(grid.nz) and volume >= span - FULL_SLACK and Vector2(local.x, local.z).length() < FULL_CENTRE: best = span # the pad covers the whole stone
	return best

## The pad node: plays the press of its button.
class Press extends Node3D:
	var button: MeshInstance3D
	var material: ShaderMaterial
	var _time := -1.0   ## seconds since the press began, -1 at rest
	var _from := 0.0    ## how far down the button was when it began

	func _ready() -> void:
		set_process(false)

	## A courier set the pad off: the button goes down, stays, springs back. Told again within IGNORE seconds (the same launch seen twice): nothing.
	func press() -> void:
		if _time >= 0.0 and _time < IGNORE: return
		_from = _depth()
		_time = 0.0
		set_process(true)

	## How far down the button is now (m, negative a little over rest while it springs back).
	func _depth() -> float:
		if _time < 0.0: return 0.0
		if _time < T_DOWN:
			var u := _time / T_DOWN
			return lerpf(_from, TRAVEL, 1.0 - (1.0 - u) * (1.0 - u))
		if _time < T_DOWN + T_HOLD: return TRAVEL
		var v := clampf((_time - T_DOWN - T_HOLD) / T_UP, 0.0, 1.0)
		var s := v - 1.0
		var back := 1.0 + 2.2 * s * s * s + 1.2 * s * s # ease out back: past rest by a few millimetres, then rest
		return TRAVEL * (1.0 - back)

	func _process(delta: float) -> void:
		_time += delta
		var depth := _depth()
		if _time >= T_DOWN + T_HOLD + T_UP:
			_time = -1.0
			depth = 0.0
			set_process(false)
		button.position.y = -depth
		material.set_shader_parameter("glow", clampf(depth / TRAVEL, 0.0, 1.0))
