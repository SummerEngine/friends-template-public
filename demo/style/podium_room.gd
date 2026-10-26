extends Node3D
## The podium room of the show's ending (docs/party-show.md "The podium room"): an open stage on a starry NIGHT, built in code, far from every course. Glossy cylindrical pedestals of stacked discs (1st in the middle and
## highest, 2nd on its left, 3rd on its right), a purple cloth runner down the front of each with a pennant end and a big number, a big sunburst screen behind 1st and two small dark screens behind 2nd and 3rd with
## huge extruded numbers 2 / 1 / 3 and a caption, loudspeaker horns that pulse and fire confetti, an amber inflatable ring on a pink zig-zag truss round the back and the sides, a dark violet starry dome
## (style/podium_sky.gdshader) over a blue haze. It has its own light rig (the show's sun: style/candy_light.gd) and its own environment (`environment()`, which the camera takes while the room is up).
## Client only, pure look, plus collision for the characters on it: the floor, the three pedestals and a rail around them (layer 1, as every solid of the levels).
##
##   PodiumRoom.ORIGIN / spots()        where the room stands (world) and the feet of 1st, 2nd, 3rd (world)
##   room.update(t, landed, bursts, flashes)  the room at `t` seconds of the podium phase: `landed` = per rank (0 = 1st) the time that rank's winner landed (-1 not yet), `bursts` = [{at, horn, rain, seed}], `flashes` = per rank a white flash 0..1
##   room.set_captions(words, names)    the announcer's words: the champion word on the middle screen, the winners' names on their screens
##   room.horn_tip(index)               the world position of a horn's mouth (0, 1 left screen, 2, 3 middle, 4, 5 right)
## The room is a pure function of the time it is given (the replicas agree whenever the state does).
const CandyLight := preload("res://style/candy_light.gd")
const CandyLook := preload("res://style/candy_look.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const TeamCast := preload("res://style/team_cast.gd")
const HeroProp := preload("res://style/hero_prop.gd")
const CandyWorld := preload("res://style/candy_world.gd")
const CandyMesh := preload("res://style/candy_mesh.gd")
const CandyMaterial := preload("res://style/candy_material.gd")

## Far from every level (they stand along +x at 300 m a piece, from z 0 backwards): nothing else renders here.
const ORIGIN := Vector3(0.0, 0.0, 4000.0)
const HEIGHTS := [2.0, 1.5, 1.0] ## m: the top of 1st, 2nd and 3rd
const COURSE := 0.5 ## m: a course of blocks
const CENTRES := [0.0, -3.15, 3.15] ## x of the 1st, 2nd, 3rd pedestal
const WIDE := 3.0 ## m across a pedestal (x)
const DEEP := 2.4 ## m front to back (z)
const BLOCK_R := 0.08 ## the rounding of every block
const PEDESTAL_R := 0.14 ## the rounding of a pedestal disc's edges (a course is 0.5 m: a chunky glossy disc)
const PEDESTAL_ROUGH := 0.18 ## hard plastic (CandyLook.ROUGH_PLASTIC 0.11) with a little more spread: the light on a disc stays a soft sheen
const FRONT := 1.45 ## m: a pedestal's radius, and so its front face on the middle line (z); the pedestal is a stack of round discs
const CLOTH_CUTS := 6 ## segments across the runner (it follows the disc's round front)
const WALL_BACK := -5.6 ## m: the back wall
const WALL_SIDE := 9.6 ## m: the side walls
const FRONT_RAIL := 7.0 ## m: the rail along the front
const TUBE_RADIUS := 0.46 ## m: a rail tube of the stack that ringes the stage (back and sides, the front stays open)
const TUBE_STEP := 0.92 ## m between the tubes' axes: three tubes, 0.92 m apart, make a 2.3 m inflatable rim
const TUBE_CORNER := 1.6 ## m: the rounding of the corners
const YELLOW := Color("ffe033")        ## the candy palette (style/candy_look.gd): 1st's pedestal and the sunburst: the gold of the amber vinyl, a little lighter than the tile's yellow, because the grade pulls a yellow towards orange
const ORANGE := Color("ef860f")
const CREAM := Color("f3e9f4")         ## the softest light: numbers and the runner's hem (never a big surface: no white glare on the night)
const RED := Color("6130b0")           ## the cloth runner's colour: a purple vinyl
const NAVY := Color("32315d")          ## the dark accent: lettering and outlines
const TRIM := Color("5a58a0")          ## the grooves between the pedestal discs and the small screens' frames: navy lifted so that the lit frame has nothing under V 0.2
const INDIGO := Color("6a42a6")        ## the screens' frames, the horns' drums and cones: a saturated purple instead of black
const PEDESTAL := [Color("fbdc45"), Color("ea6aa6"), Color("66dcea")] ## 1st gold, 2nd pink, 3rd turquoise: three hues and the blue room (a little calmer than the course's: the night frame is not saturated)
const TRUSS_PINK := Color("f58cbf")    ## the truss under the amber ring and the front rail
const RING_AMBER := Color("ffdc66")    ## the ring's albedo: bright yellow-amber (#FFB52A..#FFC93C on screen) with its own light, so its shadow side stays bright
const NIGHT_ZENITH := Color("3e2f63")  ## the dome's screen colours (the picture: a dull violet-navy #412466 over the stage, a slate to teal blue under the horizon)
const NIGHT_MID := Color("473a72")
const NIGHT_HORIZON := Color("5a4886")
const NIGHT_BELOW := Color("3e5a92")
const NIGHT_DEEP := Color("2a80b8")
const DOME_RADIUS := 400.0             ## m: the dome's sphere (inside the camera's far plane, round the room's origin)
const TRUSS_HEIGHT := 1.25             ## m: the pink truss, floor to the ring
const TRUSS_PERIOD := 1.5              ## m: one zig and one zag
const SUN_AZIMUTH := 30.0 ## degrees, the room's sun: from the camera's side (+Z) and a little to the left
const SCREEN_X := [0.0, -5.6, 5.6] ## x of the 1st, 2nd, 3rd billboard
const SCREEN_SIZE := [Vector2(3.6, 2.7), Vector2(2.9, 2.2), Vector2(2.9, 2.2)] ## the glass: a big one behind 1st, two small ones
const SCREEN_Y := [4.7, 4.4, 4.4] ## the glass's centre height
const SCREEN_Z := -5.0
const NUMBER_DEPTH := 0.16 ## m: the thickness of a billboard number's fill (its dark back layer is 2.2 x that)
const NUMBER_STAND := 0.662 ## m: where the number sits in front of the billboard's middle, so that its back layer starts at the bezel's face (0.395)
const HORN_LIFE := 0.55 ## s a horn's pulse lasts
const HORN_SCALE := 0.8 ## the horns' size (1.0: a bell 1.0 m across, 1.65 m long)
const POP := 0.5 ## s a landing's pop (number, caption, runner) lasts
const CONFETTI_LIFE := 4.2
const CONFETTI_PER_HORN := 22 ## fewer pieces than the day room's: the night is the picture, the paper a sprinkle on it
const CONFETTI_PER_RAIN := 45
const CONFETTI_PER_POP := 16
const CONFETTI_MAX := 2200
const RAYS := preload("res://style/podium_rays.gdshader")
const STRIPES := preload("res://style/podium_runner.gdshader")
const SKY := preload("res://style/podium_sky.gdshader")

static var _materials := {}

var _horns: Array[Node3D] = []
var _horn_base: Array[Vector3] = []
var _bulb_materials: Array[StandardMaterial3D] = []
var _plates: Array[Node3D] = [] ## per rank: the name plate under the billboard
var _horn_tips: Array[Node3D] = []
var _rays: Array[ShaderMaterial] = []
var _numbers: Array[Node3D] = [] ## per rank: the extruded number
var _captions: Array[Label3D] = [] ## per rank
var _champion: Node3D ## the banner over the middle billboard
var _champion_label: Label3D
var _champion_name: Label3D
var _runners: Array[Node3D] = []
var _confetti: MultiMeshInstance3D
var _pieces: MultiMesh

## Feet of 1st, 2nd and 3rd (world).
static func spots() -> Array:
	var result: Array = []
	for rank in 3: result.append(ORIGIN + Vector3(float(CENTRES[rank]), float(HEIGHTS[rank]), 0.0))
	return result

## The room's own environment: the show's light (style/candy_light.gd: the violet and blue ambient, the grade) under a night sky of the dome's colours (what glossy things reflect; the dome itself is drawn by `_dome`).
## The camera takes it while the room is up.
static func environment() -> Environment:
	var env := CandyLight.environment(CandyLight.world_scale())
	var material := (env.sky as Sky).sky_material as ShaderMaterial
	for entry: Array in [["high_colour", NIGHT_ZENITH], ["mid_colour", NIGHT_MID], ["low_colour", NIGHT_HORIZON]]:
		var light := CandyLook.scene_linear(entry[1] as Color)
		material.set_shader_parameter(entry[0] as String, Vector3(light.r, light.g, light.b))
	return env

func _init() -> void:
	name = "PodiumRoom"

## Builds everything under this node (put the node at ORIGIN before or after).
func build() -> void:
	position = ORIGIN
	for index in 2:
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color("ffe9a8")
		bulb.emission_enabled = true
		bulb.emission = Color("ffd36a") if index == 0 else Color("ff9c5a")
		bulb.emission_energy_multiplier = 1.5
		_bulb_materials.append(bulb)
	_lights()
	_floor()
	_walls()
	_dome()
	for rank in 3: _pedestal(rank)
	for rank in 3: _screen(rank)
	_horn_pair()
	_banner()
	_railings()
	_props()
	_confetti_setup()
	_collision()
	update(-1.0, [-1.0, -1.0, -1.0], [])

# ------------------------------------------------------------------ materials and meshes

static func _paint(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [color.to_html(), rough, metal]
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = metal
	_materials[key] = material
	return material

static func _glow_paint(color: Color, energy := 1.0) -> StandardMaterial3D:
	var key := "glow:%s:%s" % [color.to_html(), energy]
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.4
	_materials[key] = material
	return material

## A box of `half` extents with its edges rounded by `radius` (smooth normals), `steps` segments per edge.
static func rounded_box(half: Vector3, radius: float, steps := 3) -> ArrayMesh:
	var key := "box:%s:%s:%s" % [half, radius, steps]
	if _materials.has(key): return _materials[key] # meshes and materials share one cache: the room is built once a show
	var r := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.99)
	var inner := half - Vector3.ONE * r
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for face: Array in axes:
		var normal: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var us := _samples(absf(u.dot(half)), r, steps)
		var vs := _samples(absf(v.dot(half)), r, steps)
		var grid: Array = []
		for a in us:
			var row: Array = []
			for b in vs:
				var p: Vector3 = normal * absf(normal.dot(half)) + u * float(a) + v * float(b)
				var clamped := p.clamp(-inner, inner)
				var d := p - clamped
				var n := normal
				if d.length() > 0.00001:
					n = d.normalized()
					p = clamped + n * r
				row.append([p, n])
			grid.append(row)
		for i in us.size() - 1:
			for j in vs.size() - 1:
				var q: Array = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
				var flip := ((q[1][0] - q[0][0]).cross(q[3][0] - q[0][0]) as Vector3).dot(normal) > 0.0 # Godot's front faces wind clockwise
				var order := [0, 2, 1, 0, 3, 2] if flip else [0, 1, 2, 0, 2, 3]
				for k in order:
					tool.set_normal(q[k][1])
					tool.add_vertex(q[k][0])
	var mesh := tool.commit()
	_materials[key] = mesh
	return mesh

static func _samples(half: float, radius: float, steps: int) -> Array:
	var list: Array = []
	for i in steps + 1: list.append(-half + radius * float(i) / float(steps))
	for i in range(steps, -1, -1): list.append(half - radius * float(i) / float(steps))
	return list

func _block(parent: Node3D, label: String, centre: Vector3, size: Vector3, color: Color, radius := 0.06, rough := 0.6) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = rounded_box(size * 0.5, radius)
	instance.material_override = _paint(color, rough)
	instance.position = centre
	parent.add_child(instance)
	return instance

func _ball(parent: Node3D, centre: Vector3, radius: float, color: Color, material: Material = null) -> void:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	instance.mesh = mesh
	instance.material_override = material if material != null else _paint(color, 0.35, 0.2)
	instance.position = centre
	parent.add_child(instance)

func _cylinder(parent: Node3D, centre: Vector3, radius: float, height: float, color: Color, axis := Vector3.UP) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = _paint(color, 0.5)
	instance.position = centre
	if axis != Vector3.UP: instance.basis = Basis(Quaternion(Vector3.UP, axis))
	parent.add_child(instance)
	return instance

# ------------------------------------------------------------------ the room

## The room's light rig: the show's sun and its cool fill (style/candy_light.gd), from the front left so the faces of the pedestals and screens are lit and the shadows fall back and right.
func _lights() -> void:
	var key := DirectionalLight3D.new()
	key.name = "RoomKey"
	add_child(key)
	CandyLight.apply_sun(key, SUN_AZIMUTH)
	if CandyLight.has_fill(CandyLight.world_scale()):
		var fill := CandyLight.make_fill()
		fill.name = "RoomFill"
		add_child(fill)
		fill.global_basis = Basis.looking_at(-CandyLook.towards(CandyLook.FILL_ELEVATION, CandyLook.FILL_AZIMUTH), Vector3.UP)

func _floor() -> void:
	var floor_node := Node3D.new()
	floor_node.name = "Floor"
	add_child(floor_node)
	var slab := MeshInstance3D.new()
	slab.mesh = rounded_box(Vector3(WALL_SIDE + 0.4, 0.5, (FRONT_RAIL - WALL_BACK) * 0.5 + 0.4), 0.12)
	slab.position = Vector3(0.0, -0.5, (FRONT_RAIL + WALL_BACK) * 0.5)
	var tiles := ShaderMaterial.new()
	tiles.shader = _tile_shader()
	slab.material_override = tiles
	floor_node.add_child(slab)
	# a navy skirt under the front edge, so the floor is a stage and not a plank
	_block(floor_node, "Skirt", Vector3(0.0, -2.2, FRONT_RAIL + 0.2), Vector3(WALL_SIDE * 2.0 + 1.4, 3.0, 0.6), NAVY, 0.1)

static func _tile_shader() -> Shader:
	if _materials.has("tile_shader"): return _materials.tile_shader
	var shader := Shader.new()
	shader.code = """shader_type spatial;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = wpos.xz / 0.42;
	vec2 id = floor(cell);
	vec2 f = fract(cell) - 0.5;
	float h = fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
	vec2 at = (vec2(fract(h * 7.31), fract(h * 13.7)) - 0.5) * 0.5;
	float star = step(0.9, h) * (1.0 - smoothstep(0.04, 0.09, length(f - at)));
	vec3 col = vec3(0.035, 0.09, 0.30);
	ALBEDO = col + vec3(1.0, 0.92, 0.7) * star * 0.8;
	EMISSION = col * 0.35 + vec3(1.0, 0.92, 0.7) * star * 0.6;
	ROUGHNESS = 0.12;
}
"""
	_materials["tile_shader"] = shader
	return shader

## The room is open to the night: the stage is ringed on the back and the two sides by a stack of three amber inflatable tubes (smooth, glossy vinyl with pillow pinches, rounded corners and ends, the
## tile rounds' rail in small) that stands on a pink zig-zag truss (two chords and a wave between them, `TRUSS_HEIGHT` m high, round the same path), on posts; the dome (`_dome`) shows behind and above,
## the front is open to the camera. One mesh, one material.
func _walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var x := WALL_SIDE + 0.4
	var z_back := WALL_BACK - 0.4
	var corner := TUBE_CORNER
	var path := PackedVector3Array()
	path.append_array(_tube_path(Vector2(-x, FRONT_RAIL), Vector2(-x, z_back), Vector2(x, z_back), Vector2(x, FRONT_RAIL), corner))
	var builder := CandyMesh.new()
	var colour := RING_AMBER
	for level in 3:
		var height := TRUSS_HEIGHT + TUBE_RADIUS + TUBE_STEP * float(level)
		var flat := PackedVector3Array()
		for point in path: flat.append(Vector3(point.x, height, point.z))
		builder.tube(flat, TUBE_RADIUS, 10, colour, 0.12, 2.6)
	var top := TRUSS_HEIGHT - 0.04
	var bottom := 0.08
	for chord: float in [top, bottom]:
		var flat := PackedVector3Array()
		for point in path: flat.append(Vector3(point.x, chord, point.z))
		builder.tube(flat, 0.11, 6, TRUSS_PINK)
	builder.tube(_zigzag(path, top - 0.06, bottom + 0.06), 0.07, 6, TRUSS_PINK)
	for post: Vector2 in [Vector2(-x, FRONT_RAIL), Vector2(x, FRONT_RAIL), Vector2(-x, z_back), Vector2(x, z_back), Vector2(-x, 0.0), Vector2(x, 0.0), Vector2(-x * 0.5, z_back), Vector2(x * 0.5, z_back), Vector2(0.0, z_back)]:
		builder.tube(PackedVector3Array([Vector3(post.x, 0.0, post.y), Vector3(post.x, TRUSS_HEIGHT + TUBE_RADIUS + TUBE_STEP * 2.0, post.y)]), TUBE_RADIUS * 1.12, 10, colour.lerp(Color("#ffb030"), 0.3))
	var rail := MeshInstance3D.new()
	rail.name = "TubeRail"
	rail.mesh = builder.to_mesh()
	rail.material_override = CandyMaterial.make({"albedo": Color.WHITE, "use_vertex_color": true, "roughness": CandyLook.ROUGH_VINYL_GLOSSY, "self_light": 0.55, "rim_color": Color("fff4c0"), "rim_power": 3.5})
	rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	walls.add_child(rail)

## The wave of the truss along `path` (x, z): a point about every 0.14 m of its length, y running between `low` and `high` once every TRUSS_PERIOD m, a rounded triangle wave (the peaks are bent wire, not corners).
static func _zigzag(path: PackedVector3Array, high: float, low: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	var run := 0.0
	var mid := (high + low) * 0.5
	var amp := (high - low) * 0.5
	var squash := 0.96
	for k in path.size():
		var here := path[k]
		var span := 0.0 if k == 0 else Vector2(here.x, here.z).distance_to(Vector2(path[k - 1].x, path[k - 1].z))
		var steps := 1 if k == 0 else maxi(1, ceili(span / 0.14))
		for step in steps:
			var f := 1.0 if k == 0 else float(step + 1) / float(steps)
			var at := here if k == 0 else path[k - 1].lerp(here, f)
			var wave := asin(squash * sin(TAU * (run + span * f) / TRUSS_PERIOD)) / asin(squash)
			result.append(Vector3(at.x, mid + amp * wave, at.z))
		run += span
	return result

## A path through the corners `a`, `b`, `c`, `d` (x, z) with the two inner corners cut and rounded over `corner` m, a point about every 0.8 m.
static func _tube_path(a: Vector2, b: Vector2, c: Vector2, d: Vector2, corner: float) -> Array[Vector3]:
	var knots: Array[Vector2] = [a]
	for k in 2:
		var p := b if k == 0 else c
		var before := a if k == 0 else b
		var after := c if k == 0 else d
		var p1 := p + (before - p).normalized() * corner
		var p2 := p + (after - p).normalized() * corner
		for step in 7:
			var u := float(step) / 6.0
			knots.append(p1.lerp(p, u).lerp(p.lerp(p2, u), u))
	knots.append(d)
	var result: Array[Vector3] = [Vector3(a.x, 0.0, a.y)]
	for k in range(1, knots.size()):
		var from := knots[k - 1]
		var count := maxi(1, int(from.distance_to(knots[k]) / 0.8))
		for step in count:
			var q := from.lerp(knots[k], float(step + 1) / float(count))
			result.append(Vector3(q.x, 0.0, q.y))
	return result

## The night: the inside of a sphere round the room (style/podium_sky.gdshader: a dark violet dome over blue haze, star specks), one draw call, no particles. Its colours are authored as the colours the picture
## shows (`CandyLook.scene_linear`, handed to `source_color` uniforms the way style/candy_world.gd does).
func _dome() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var material := ShaderMaterial.new()
	material.shader = SKY
	for entry: Array in [["zenith", NIGHT_ZENITH], ["mid", NIGHT_MID], ["horizon", NIGHT_HORIZON], ["below", NIGHT_BELOW], ["deep", NIGHT_DEEP],
			["star_a", Color("fff6d8")], ["star_b", Color("c4eeff")], ["star_c", Color("ffc6ec")], ["star_d", Color("ffe27a")]]:
		material.set_shader_parameter(entry[0] as String, CandyLook.scene_linear(entry[1] as Color).linear_to_srgb())
	var dome := MeshInstance3D.new()
	dome.name = "NightDome"
	dome.mesh = sphere
	dome.material_override = material
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)

# ------------------------------------------------------------------ pedestals and runners

func _pedestal(rank: int) -> void:
	var top: float = HEIGHTS[rank]
	var holder := Node3D.new()
	holder.name = "Pedestal%d" % (rank + 1)
	holder.position = Vector3(float(CENTRES[rank]), 0.0, 0.0)
	add_child(holder)
	var base: Color = PEDESTAL[rank]
	var courses := roundi(top / COURSE)
	var builder := CandyMesh.new()
	var groove := 0.06 # the dark core shows between the discs
	var core := PackedVector2Array([Vector2(0.0, 0.0), Vector2(FRONT - 0.1, 0.0), Vector2(FRONT - 0.1, top - 0.05), Vector2(0.0, top - 0.05)])
	builder.lathe(core, PackedColorArray([TRIM, TRIM, TRIM, TRIM]), 28)
	for course in courses:
		var shade := base.darkened(0.08 * float((course + rank) % 2)).lightened(0.2 if course == courses - 1 else 0.0)
		var low := COURSE * float(course) + (groove * 0.5 if course > 0 else 0.0)
		var high := COURSE * float(course + 1) - (groove * 0.5 if course < courses - 1 else 0.0)
		builder.push(Transform3D(Basis.IDENTITY, Vector3(0.0, low, 0.0)))
		builder.lathe(_disc(FRONT, high - low, PEDESTAL_R), _filled(shade, 12), 28)
		builder.pop()
	var stack := MeshInstance3D.new()
	stack.name = "Discs"
	stack.mesh = builder.to_mesh()
	stack.material_override = CandyMaterial.make({"albedo": Color.WHITE, "use_vertex_color": true, "roughness": 0.07 if rank == 0 else PEDESTAL_ROUGH}) # 1st is the shiniest cylinder
	holder.add_child(stack)
	_runner(holder, rank, top)

## The profile (radius, y) of a rounded disc of `radius` and `height`, its edges rounded by `bevel`: foot centre, a quarter circle up, the wall, a quarter circle in, the top centre.
static func _disc(radius: float, height: float, bevel: float) -> PackedVector2Array:
	var profile := PackedVector2Array([Vector2(0.0, 0.0)])
	for step in 5:
		var turn := -PI * 0.5 + PI * 0.5 * float(step) / 4.0
		profile.append(Vector2(radius - bevel + bevel * cos(turn), bevel + bevel * sin(turn)))
	for step in 5:
		var turn := PI * 0.5 * float(step) / 4.0
		profile.append(Vector2(radius - bevel + bevel * cos(turn), height - bevel + bevel * sin(turn)))
	profile.append(Vector2(0.0, height))
	return profile

static func _filled(colour: Color, count: int) -> PackedColorArray:
	var colours := PackedColorArray()
	for index in count: colours.append(colour)
	return colours

## The red cloth: ONE draped mesh. A mat on the top of the pedestal, over the front edge in a soft rounded fold, down the face as a wide pennant that narrows to a point (its width, not a second
## piece), on down as a runner, round another soft fold onto the floor and out along it. The cream hem, the stripes of the runner and the number are print on it (style/podium_runner.gdshader and a
## flat number, no stacked slabs): the cloth is one surface everywhere.
func _runner(holder: Node3D, rank: int, top: float) -> void:
	var cloth := Node3D.new()
	cloth.name = "Runner"
	holder.add_child(cloth)
	_runners.append(cloth)
	var red := ShaderMaterial.new()
	red.shader = STRIPES
	red.set_shader_parameter("red", RED)
	red.set_shader_parameter("stripe", RED.lightened(0.28))
	red.set_shader_parameter("edge", CREAM)
	var wide := 1.2
	var narrow := 0.62
	var skin := 0.02 # the cloth lies this far off the blocks
	var face := FRONT + skin
	var floor_y := skin
	var drop := minf(top * 0.62, 1.3)
	var p_top := top - 0.08
	var p_mid := p_top - drop * 0.58
	var p_tip := p_top - drop
	var fold := 0.16 # the radius of the folds over the edge and onto the floor
	var rows: Array = [] # [y, z, width, stripes 0|1, hug 0..1: how far the row follows the pedestal's round front]
	rows.append([top + skin, -0.1, wide, 0.0, 1.0])
	for step in range(0, 9): # over the edge: a quarter circle from the top to the face
		var turn := deg_to_rad(90.0 * float(step) / 8.0)
		rows.append([top + skin - fold + fold * cos(turn), face - fold + fold * sin(turn), wide, 0.0, 1.0])
	rows.append([p_mid, face, wide, 0.0, 1.0])
	rows.append([p_tip, face, narrow, 0.0, 1.0])
	rows.append([p_tip - 0.1, face, narrow, 1.0, 1.0])
	for step in range(0, 9): # onto the floor
		var turn := deg_to_rad(90.0 * float(step) / 8.0)
		rows.append([floor_y + fold - fold * sin(turn), face + fold - fold * cos(turn), narrow, 1.0, 1.0 - float(step) / 8.0])
	rows.append([floor_y, FRONT + 2.4, narrow, 1.0, 0.0])
	_drape(cloth, rows, red)
	var number := _flat_word("%d" % (rank + 1), 0.62 * minf(drop / 1.3 + 0.35, 1.0), CREAM, 0.012)
	number.position = Vector3(0.0, p_top - drop * 0.36, face + 0.007)
	number.name = "RunnerNumber"
	cloth.add_child(number)

## One sheet along `rows` ([y, z, width, stripes, hug]: a path in the y/z plane, centred on x = 0): smooth normals along the path, uv.x 0..1 across, uv.y metres along; COLOR.r is the stripe flag, COLOR.g
## half the width in metres (the hem is a distance from the edge). Across, the sheet is cut in `CLOTH_CUTS` and a row with `hug` follows the round front of the pedestal (FRONT m radius): its sides fall back as the disc does.
func _drape(parent: Node3D, rows: Array, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var made: Array = []
	for index in rows.size():
		var row: Array = rows[index]
		var here := Vector2(row[0], row[1])
		if index > 0: along += here.distance_to(Vector2((rows[index - 1] as Array)[0], (rows[index - 1] as Array)[1]))
		var before: Array = rows[maxi(index - 1, 0)]
		var after: Array = rows[mini(index + 1, rows.size() - 1)]
		var tangent := (Vector2(after[0], after[1]) - Vector2(before[0], before[1])).normalized()
		made.append({"at": Vector3(0.0, row[0], row[1]), "normal": Vector3(0.0, tangent.y, -tangent.x), "along": along, "width": float(row[2]), "stripes": float(row[3]), "hug": float(row[4])})
	for index in made.size() - 1:
		var a: Dictionary = made[index]
		var b: Dictionary = made[index + 1]
		for cut in CLOTH_CUTS:
			var corners: Array = []
			for pair: Array in [[a, float(cut)], [a, float(cut + 1)], [b, float(cut + 1)], [b, float(cut)]]:
				var row: Dictionary = pair[0]
				var across: float = float(pair[1]) / float(CLOTH_CUTS)
				var x := (across - 0.5) * float(row.width)
				var sag := float(row.hug) * (FRONT - sqrt(maxf(FRONT * FRONT - x * x, 0.0)))
				corners.append({"p": (row.at as Vector3) + Vector3(x, 0.0, -sag), "n": row.normal, "uv": Vector2(across, float(row.along)), "c": Color(float(row.stripes), float(row.width) * 0.5, 0.0)})
			for k in [0, 1, 2, 0, 2, 3]: # clockwise from the side the normal points to
				var corner: Dictionary = corners[k]
				tool.set_normal(corner.n)
				tool.set_uv(corner.uv)
				tool.set_color(corner.c)
				tool.add_vertex(corner.p)
	var mesh := tool.commit()
	var instance := MeshInstance3D.new()
	instance.name = "Cloth"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

## A word printed flat on a surface facing +z: `size` m tall capitals, `depth` m thick (a print, not a slab).
func _flat_word(words: String, size: float, fill: Color, depth: float) -> Node3D:
	var front := MeshInstance3D.new()
	front.mesh = _text_mesh(words, size, depth)
	front.material_override = _paint(fill, 0.6)
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return front

func _flat(parent: Node3D, corners: Array, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal: Vector3 = ((corners[1] as Vector3) - (corners[0] as Vector3)).cross((corners[2] as Vector3) - (corners[0] as Vector3)).normalized()
	if normal.y < 0.0 and absf(normal.y) > absf(normal.z): normal = -normal
	if normal.z < 0.0 and absf(normal.z) > absf(normal.y): normal = -normal
	var count: int = corners.size()
	var centre := Vector3.ZERO
	for corner: Vector3 in corners: centre += corner
	centre /= float(count)
	for index in count:
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % count]
		var order := [centre, a, b]
		if ((a - centre).cross(b - centre)).dot(normal) > 0.0: order = [centre, b, a] # clockwise from the front
		for point: Vector3 in order:
			tool.set_normal(normal)
			tool.add_vertex(point)
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

## An extruded word (Lilita One): a deep dark back layer a little bigger than the fill for the outline and the chunky side, the fill in front.
func _extruded(words: String, size: float, fill: Color, edge: Color, depth := 0.14) -> Node3D:
	var holder := Node3D.new()
	var back := MeshInstance3D.new()
	back.mesh = _text_mesh(words, size, depth * 2.2)
	back.material_override = _paint(edge, 0.55)
	back.scale = Vector3(1.09, 1.09, 1.0)
	back.position = Vector3(0.0, 0.0, -depth * 0.4)
	holder.add_child(back)
	var front := MeshInstance3D.new()
	front.mesh = _text_mesh(words, size, depth)
	front.material_override = _paint(fill, 0.45)
	front.position = Vector3(0.0, 0.0, depth * 0.55)
	holder.add_child(front)
	return holder

func _text_mesh(words: String, size: float, depth: float) -> TextMesh:
	var mesh := TextMesh.new()
	mesh.font = ShowTheme.font()
	mesh.text = words
	mesh.font_size = 128
	mesh.pixel_size = size / 128.0 / 0.69 # capitals `size` m tall (Lilita One's cap height is 0.69 em)
	mesh.depth = depth
	mesh.curve_step = 0.4
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return mesh

# ------------------------------------------------------------------ screens and horns

func _screen(rank: int) -> void:
	var holder := Node3D.new()
	holder.name = "Billboard%d" % (rank + 1)
	var glass: Vector2 = SCREEN_SIZE[rank]
	holder.position = Vector3(float(SCREEN_X[rank]), float(SCREEN_Y[rank]), SCREEN_Z)
	holder.rotation.y = 0.0 if rank == 0 else (0.12 if rank == 1 else -0.12)
	add_child(holder)
	var frame := glass + Vector2(0.8, 0.8)
	# a bold lightbox: a deep purple body (navy on the small ones), an amber bezel (pink on the small ones), the glass in front; marquee bulbs run round the edge
	_block(holder, "Frame", Vector3(0.0, 0.0, 0.0), Vector3(frame.x, frame.y, 0.6), INDIGO if rank == 0 else TRIM, 0.28, CandyLook.ROUGH_VINYL)
	_block(holder, "Bezel", Vector3(0.0, 0.0, 0.12), Vector3(glass.x + 0.28, glass.y + 0.28, 0.55), RING_AMBER if rank == 0 else TRUSS_PINK, 0.14, 0.5)
	var sheet := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = glass
	sheet.mesh = quad
	var rays := ShaderMaterial.new()
	rays.shader = RAYS
	rays.set_shader_parameter("aspect", glass.x / glass.y)
	# the sunburst is 1st's alone: amber and pink, almost pure; the two small screens are dark violet panels with a faint turning fan
	rays.set_shader_parameter("ray_a", Color("ffb347") if rank == 0 else Color("6a5ab8"))
	rays.set_shader_parameter("ray_b", Color("ff9cc8") if rank == 0 else Color("4a3a94"))
	rays.set_shader_parameter("wash", 0.16 if rank == 0 else 0.0)
	rays.set_shader_parameter("spin", 0.05 if rank == 0 else (-0.04 if rank == 1 else 0.045))
	sheet.material_override = rays
	sheet.position = Vector3(0.0, 0.0, 0.42)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(sheet)
	_rays.append(rays)
	var number := _extruded("%d" % (rank + 1), glass.y * (0.66 if rank == 0 else 0.62), Color("ffd814") if rank == 0 else Color("effcff"), NAVY, NUMBER_DEPTH)
	number.position = Vector3(0.0, -glass.y * 0.02, NUMBER_STAND) # the number stands on the glass: its back layer starts at the bezel's face, nothing of it sinks into the board
	number.name = "Number"
	holder.add_child(number)
	_numbers.append(number)
	# marquee bulbs round the frame's face, two colours alternating (their glow chases: update())
	var bulbs := 0
	var along := PackedVector2Array()
	var step := 1.0
	var count_x := roundi(frame.x / step)
	var count_y := roundi(frame.y / step)
	for index in count_x:
		var x := -frame.x * 0.5 + 0.2 + (frame.x - 0.4) * (float(index) + 0.5) / float(count_x)
		along.append(Vector2(x, frame.y * 0.5 - 0.17))
		along.append(Vector2(x, -frame.y * 0.5 + 0.17))
	for index in count_y:
		var y := -frame.y * 0.5 + 0.2 + (frame.y - 0.4) * (float(index) + 0.5) / float(count_y)
		along.append(Vector2(-frame.x * 0.5 + 0.17, y))
		along.append(Vector2(frame.x * 0.5 - 0.17, y))
	for spot: Vector2 in along:
		_ball(holder, Vector3(spot.x, spot.y, 0.32), 0.075, Color("ffe9a8"), _bulb_materials[bulbs % 2])
		bulbs += 1
	# the name plate stands on top of the frame on two rods: the winner's name comes up on it when the winner lands (the middle one is the champion banner's second line instead)
	var plate := Node3D.new()
	plate.name = "Plate"
	plate.position = Vector3(0.0, frame.y * 0.5 + 0.72, 0.1)
	holder.add_child(plate)
	for rod in [-1.0, 1.0]: _cylinder(plate, Vector3(float(rod) * glass.x * 0.3, -0.5, 0.0), 0.05, 0.5, NAVY.lightened(0.2))
	_block(plate, "Board", Vector3.ZERO, Vector3(glass.x * 0.86, 0.74, 0.2), CREAM, 0.14, 0.5)
	_block(plate, "BoardEdge", Vector3(0.0, 0.0, -0.02), Vector3(glass.x * 0.86 + 0.14, 0.88, 0.16), ORANGE, 0.17, 0.5)
	var caption := Label3D.new()
	caption.font = ShowTheme.font()
	caption.font_size = 96
	caption.pixel_size = 0.0075
	caption.outline_size = 0
	caption.modulate = NAVY
	caption.position = Vector3(0.0, 0.0, 0.12)
	caption.shaded = false
	caption.text = ""
	caption.set_meta("width", glass.x * 0.8)
	plate.add_child(caption)
	_captions.append(caption)
	_plates.append(plate)
	# two posts carry the billboard down behind the pedestals
	for post in [-1.0, 1.0]:
		var height := float(SCREEN_Y[rank]) - frame.y * 0.5 + 0.2
		_cylinder(holder, Vector3(float(post) * (frame.x * 0.5 - 0.5), -float(SCREEN_Y[rank]) * 0.5 - frame.y * 0.25 + 0.1, -0.1), 0.14, height, YELLOW.darkened(0.12))

## The champion banner above the middle billboard: a spiky yellow badge with the champion word and under it the winner's name, popped in when the winner has landed.
func _banner() -> void:
	_champion = Node3D.new()
	_champion.name = "Champion"
	_champion.position = Vector3(0.0, 8.7, WALL_BACK + 0.35)
	add_child(_champion)
	var points := PackedVector3Array()
	var spikes := 22
	for index in spikes * 2:
		var a := TAU * float(index) / float(spikes * 2)
		var reach := Vector2(3.6, 1.2) * (1.0 if index % 2 == 0 else 0.87)
		points.append(Vector3(cos(a) * reach.x, sin(a) * reach.y, 0.0))
	var back := PackedVector3Array()
	for point in points: back.append(point * 1.07 + Vector3(0.0, -0.07, -0.02))
	_flat(_champion, Array(back), _paint(ORANGE.darkened(0.2), 0.6))
	_flat(_champion, Array(points), _paint(YELLOW, 0.5))
	_champion_label = Label3D.new()
	_champion_label.font = ShowTheme.font()
	_champion_label.font_size = 130
	_champion_label.pixel_size = 0.008
	_champion_label.outline_size = 34
	_champion_label.modulate = Color("fff6d0")
	_champion_label.outline_modulate = Color("c8661a")
	_champion_label.position = Vector3(0.0, 0.34, 0.06)
	_champion_label.shaded = false
	_champion.add_child(_champion_label)
	_champion_name = Label3D.new()
	_champion_name.font = ShowTheme.font()
	_champion_name.font_size = 96
	_champion_name.pixel_size = 0.006
	_champion_name.outline_size = 22
	_champion_name.modulate = Color.WHITE
	_champion_name.outline_modulate = Color("8a4608")
	_champion_name.position = Vector3(0.0, -0.55, 0.06)
	_champion_name.shaded = false
	_champion.add_child(_champion_name)
	_champion.visible = false

## The two big loudspeaker horns, one on each side of the back wall on a yellow post, aimed in across the stage; each is a node (the pulse scales it) with a node at the mouth (the confetti leaves from there).
func _horn_pair() -> void:
	for side in [-1.0, 1.0]:
		var x := float(side) * (WALL_SIDE - 1.0)
		var post := _cylinder(self, Vector3(x, 2.65, WALL_BACK + 0.9), 0.2, 5.3, YELLOW.darkened(0.12)) # up to the horn's mount, not into it
		post.name = "HornPost"
		var horn := Node3D.new()
		horn.name = "Horn%d" % _horns.size()
		horn.position = Vector3(x, 6.0, WALL_BACK + 0.9)
		horn.basis = Basis.looking_at(-Vector3(-float(side) * 0.55, 0.38, 0.8).normalized(), Vector3.UP).scaled(Vector3.ONE * HORN_SCALE) # the bell is on +Z, looking_at points -Z
		add_child(horn)
		_horn_body(horn)
		var tip := Node3D.new()
		tip.position = Vector3(0.0, 0.0, 1.35)
		horn.add_child(tip)
		_horns.append(horn)
		_horn_tips.append(tip)
		_horn_base.append(Vector3.ONE * HORN_SCALE)

## A loudspeaker horn along +Z: a neck on a drum, the bell flaring to the mouth with a rim, a dark inside.
func _horn_body(horn: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile: Array = []
	for index in 13:
		var f := float(index) / 12.0
		profile.append(Vector2(0.17 + 0.75 * pow(f, 2.2), -0.3 + 1.65 * f)) # radius, z
	_lathe(tool, profile, 28, false)
	var mesh := tool.commit()
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _paint(YELLOW, 0.4, 0.15)
	horn.add_child(body)
	var inside := SurfaceTool.new()
	inside.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: Array = []
	for index in 13:
		var f := float(index) / 12.0
		inner.append(Vector2((0.17 + 0.75 * pow(f, 2.2)) * 0.9, -0.3 + 1.65 * f + 0.0))
	_lathe(inside, inner, 28, true)
	var dark := MeshInstance3D.new()
	dark.mesh = inside.commit()
	dark.material_override = _paint(CandyLook.COURSE_HUES.purple[2], CandyLook.ROUGH_VINYL)
	horn.add_child(dark)
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.84
	ring.outer_radius = 1.02
	ring.rings = 28
	ring.ring_segments = 8
	rim.mesh = ring
	rim.material_override = _paint(CREAM, 0.4)
	rim.rotation.x = PI * 0.5
	rim.position = Vector3(0.0, 0.0, 1.35)
	horn.add_child(rim)
	var drum := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.34
	cylinder.bottom_radius = 0.38
	cylinder.height = 0.5
	drum.mesh = cylinder
	drum.material_override = _paint(INDIGO, CandyLook.ROUGH_VINYL)
	drum.rotation.x = PI * 0.5
	drum.position = Vector3(0.0, 0.0, -0.5)
	horn.add_child(drum)
	_block(horn, "Mount", Vector3(0.0, -0.45, -0.3), Vector3(0.5, 0.6, 0.5), YELLOW.darkened(0.15), 0.1)

## A surface of revolution about +Z from (radius, z) points (outer faces out, or `inside` faces in).
func _lathe(tool: SurfaceTool, profile: Array, sides: int, inside: bool) -> void:
	for index in profile.size() - 1:
		var a: Vector2 = profile[index]
		var b: Vector2 = profile[index + 1]
		for side in sides:
			var t0 := TAU * float(side) / float(sides)
			var t1 := TAU * float(side + 1) / float(sides)
			var d0 := Vector3(cos(t0), sin(t0), 0.0)
			var d1 := Vector3(cos(t1), sin(t1), 0.0)
			var p := [d0 * a.x + Vector3(0, 0, a.y), d1 * a.x + Vector3(0, 0, a.y), d1 * b.x + Vector3(0, 0, b.y), d0 * b.x + Vector3(0, 0, b.y)]
			var slope := (b.x - a.x) / maxf(b.y - a.y, 0.001)
			var n0 := (d0 - Vector3(0, 0, slope)).normalized() * (-1.0 if inside else 1.0)
			var n1 := (d1 - Vector3(0, 0, slope)).normalized() * (-1.0 if inside else 1.0)
			var n := [n0, n1, n1, n0]
			var order := [0, 2, 1, 0, 3, 2] if not inside else [0, 1, 2, 0, 2, 3]
			for k in order:
				tool.set_normal(n[k])
				tool.add_vertex(p[k])

# ------------------------------------------------------------------ railings, props, collision

func _railings() -> void:
	var rails := Node3D.new()
	rails.name = "Railings"
	add_child(rails)
	var post_blue: Color = CandyLook.COURSE_HUES.blue[1]
	var posts: Array[Vector3] = []
	for index in 7: posts.append(Vector3(-WALL_SIDE + 1.0 + (WALL_SIDE * 2.0 - 2.0) * float(index) / 6.0, 0.0, FRONT_RAIL))
	for post: Vector3 in posts:
		_cylinder(rails, post + Vector3(0.0, 0.5, 0.0), 0.14, 1.0, post_blue)
		_cylinder(rails, post + Vector3(0.0, 1.06, 0.0), 0.2, 0.14, ORANGE)
		_ball(rails, post + Vector3(0.0, 1.2, 0.0), 0.12, YELLOW)
	for index in posts.size() - 1:
		var a: Vector3 = posts[index]
		var b: Vector3 = posts[index + 1]
		for height in [0.38, 0.8]:
			_block(rails, "Rail", Vector3((a.x + b.x) * 0.5, height, FRONT_RAIL), Vector3(absf(b.x - a.x) - 0.2, 0.1, 0.1), TRUSS_PINK, 0.04, CandyLook.ROUGH_VINYL)
	for side in [-1.0, 1.0]: # along the side walls, three posts a side
		for index in 3:
			var z := FRONT_RAIL - 2.8 - 3.4 * float(index)
			var x := float(side) * (WALL_SIDE - 0.5)
			_cylinder(rails, Vector3(x, 0.5, z), 0.13, 1.0, post_blue)
			_cylinder(rails, Vector3(x, 1.06, z), 0.19, 0.14, ORANGE)

func _props() -> void:
	# the hero prop in small copies at the room's two sides, if the cast has one (the built-in stand otherwise)
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	for side in [-1.0, 1.0]:
		var prop := HeroProp.build(Vector2(2.2, 2.4))
		if prop == null: continue
		prop.position = Vector3(float(side) * 8.2, 0.0, -1.0)
		prop.rotation.y = float(side) * -0.4
		props.add_child(prop)

func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "RoomSolids"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var boxes: Array = [[Vector3(0.0, -0.5, (FRONT_RAIL + WALL_BACK) * 0.5), Vector3(WALL_SIDE * 2.0, 1.0, FRONT_RAIL - WALL_BACK)]]
	for rank in 3: boxes.append([Vector3(float(CENTRES[rank]), float(HEIGHTS[rank]) * 0.5, 0.0), Vector3(WIDE, float(HEIGHTS[rank]), DEEP)])
	boxes.append([Vector3(0.0, 3.0, FRONT_RAIL), Vector3(WALL_SIDE * 2.0, 6.0, 0.3)])
	boxes.append([Vector3(0.0, 3.0, WALL_BACK - 0.2), Vector3(WALL_SIDE * 2.0, 6.0, 0.4)])
	for side in [-1.0, 1.0]: boxes.append([Vector3(float(side) * WALL_SIDE, 3.0, 0.0), Vector3(0.4, 6.0, FRONT_RAIL - WALL_BACK)])
	for entry: Array in boxes:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = entry[1]
		shape.shape = box
		shape.position = entry[0]
		body.add_child(shape)

# ------------------------------------------------------------------ confetti

func _confetti_setup() -> void:
	_pieces = MultiMesh.new()
	_pieces.transform_format = MultiMesh.TRANSFORM_3D
	_pieces.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.17, 0.1)
	_pieces.mesh = quad
	_pieces.instance_count = CONFETTI_MAX
	_pieces.visible_instance_count = 0
	_confetti = MultiMeshInstance3D.new()
	_confetti.name = "Confetti"
	_confetti.multimesh = _pieces
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.vertex_color_use_as_albedo = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	_confetti.material_override = paint
	_confetti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_confetti.extra_cull_margin = 200.0
	add_child(_confetti)

static func confetti_colors() -> Array[Color]:
	var colors: Array[Color] = [Color("f7c312"), Color("49c6ee"), Color("e6554f"), Color("ffd1ea"), Color("7bd957"), Color("c36cf0"), Color("ff8fb8")]
	for brand in TeamCast.brand_colors():
		if brand.s > 0.25: colors.append(brand)
	for index in colors.size(): colors[index] = colors[index].lerp(Color("f4eaff"), 0.3) # the paper is pastel: the saturated pixels of the night are the screens and the ring, not the confetti
	return colors

## The world position of a horn's mouth.
func horn_tip(index: int) -> Vector3:
	return _horn_tips[clampi(index, 0, _horn_tips.size() - 1)].global_position if is_inside_tree() else ORIGIN

func _pulse(age: float) -> float:
	if age < 0.0 or age > HORN_LIFE: return 0.0
	var f := age / HORN_LIFE
	return sin(f * PI * 3.0) * pow(1.0 - f, 1.4)

## One piece of one burst at `age` s: room-space position, spin, scale and colour index. Deterministic from (seed, index). A burst is a cannon from a horn (`horn`), a rain from the ceiling (`rain`) or a round pop at a point (`pop`, room space).
func _piece(burst: Dictionary, index: int, age: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(burst.seed) * 7919 + index * 104729 + 17
	var origin := Vector3.ZERO
	var velocity := Vector3.ZERO
	if burst.get("rain", false):
		origin = Vector3(rng.randf_range(-8.5, 8.5), rng.randf_range(9.0, 12.0), rng.randf_range(-4.5, 4.0))
		velocity = Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.0, 0.0), rng.randf_range(-0.5, 0.8))
	elif burst.has("pop"):
		origin = burst.pop
		var around := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0), rng.randf_range(-0.6, 1.0)).normalized()
		velocity = around * rng.randf_range(3.0, 8.5)
	else:
		var node := _horns[clampi(int(burst.horn), 0, _horns.size() - 1)]
		var forward := node.basis.z.normalized() # the bell looks along the horn's own +Z
		origin = node.position + forward * 1.35 * HORN_SCALE
		var spread := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.15, 0.6), rng.randf_range(-0.45, 0.45))
		velocity = (forward + spread + Vector3.UP * 0.5).normalized() * rng.randf_range(7.0, 15.0)
	var drag := rng.randf_range(1.2, 2.2)
	var fall := rng.randf_range(1.0, 1.8)
	var e := 1.0 - exp(-drag * age)
	var position := origin + Vector3(velocity.x, velocity.y + fall, velocity.z) * (e / drag) - Vector3(0.0, fall * age, 0.0)
	position.x += sin(age * rng.randf_range(3.0, 6.0) + rng.randf() * TAU) * 0.2
	position.z += cos(age * rng.randf_range(3.0, 6.0) + rng.randf() * TAU) * 0.2
	position.y = maxf(position.y, 0.04)
	var fade := clampf((CONFETTI_LIFE - age) / 0.7, 0.0, 1.0)
	var streamer := rng.randf() < 0.3 # a long thin ribbon among the paper
	return {"pos": position, "spin": Vector3(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0)) * age + Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0),
		"scale": Vector3(2.6 if streamer else 1.0, 0.35 if streamer else 1.0, 1.0) * fade * rng.randf_range(0.75, 1.35), "color": rng.randi()}

# ------------------------------------------------------------------ the show

## Words of the show: the champion word (the banner over the middle billboard) and the winners' names (best first); a rank without a name keeps its plate off.
func set_captions(champion: String, names: Array) -> void:
	_champion_label.text = champion
	_champion_label.pixel_size = minf(0.0085, 5.6 / maxf(ShowTheme.width(champion, 130.0), 1.0))
	_champion_name.text = str(names[0]) if not names.is_empty() else ""
	_champion_name.pixel_size = minf(0.0065, 4.6 / maxf(ShowTheme.width(_champion_name.text, 96.0), 1.0))
	for rank in 3:
		var caption := _captions[rank]
		caption.text = str(names[rank]) if rank < names.size() else ""
		caption.pixel_size = minf(0.0095, float(caption.get_meta("width")) / maxf(ShowTheme.width(caption.text, 96.0), 1.0))

## The room at `t` s of the podium phase.
func update(t: float, landed: Array, bursts: Array, flashes := [0.0, 0.0, 0.0], banner_at := -1.0) -> void:
	for index in 2: # the marquee bulbs chase: two colours trading
		var glow: float = 0.5 + 0.5 * sin(t * 7.0 + float(index) * PI)
		_bulb_materials[index].emission_energy_multiplier = 0.4 + 2.0 * glow
	for rank in 3:
		var rays: ShaderMaterial = _rays[rank]
		rays.set_shader_parameter("time_s", t)
		var since: float = t - float(landed[rank]) if float(landed[rank]) >= 0.0 else -1.0
		var live := since >= 0.0
		var pop := ShowTheme.pop_scale(since, POP, 0.3) if live else 1.0
		(_numbers[rank] as Node3D).scale = Vector3.ONE * (pop if live else 0.94)
		rays.set_shader_parameter("dim", 0.0 if live else 0.42)
		rays.set_shader_parameter("flash", maxf(maxf(0.0, 1.0 - since * 3.0) if live else 0.0, float(flashes[rank])))
		var plate: Node3D = _plates[rank]
		var named: bool = rank > 0 and live and (_captions[rank] as Label3D).text != ""
		plate.visible = named
		plate.scale = Vector3.ONE * (ShowTheme.pop_scale(since - 0.12, POP, 0.2) if named else 0.01)
	var shown := banner_at >= 0.0 and t >= banner_at and _champion_label.text != ""
	_champion.visible = shown
	_champion.scale = Vector3.ONE * (ShowTheme.pop_scale(t - banner_at, 0.5, 0.2) if shown else 0.01)
	for index in _horns.size(): _horns[index].scale = _horn_base[index]
	var count := 0
	var colors := confetti_colors()
	for burst: Dictionary in bursts:
		var age: float = t - float(burst.at)
		if age < 0.0: continue
		var cannon := burst.has("horn")
		if cannon and age < HORN_LIFE:
			var horn := clampi(int(burst.horn), 0, _horns.size() - 1)
			_horns[horn].scale = _horn_base[horn] * (1.0 + 0.2 * _pulse(age))
		if age > CONFETTI_LIFE: continue
		var pieces := CONFETTI_PER_RAIN if burst.get("rain", false) else (CONFETTI_PER_HORN if cannon else CONFETTI_PER_POP)
		for index in pieces:
			if count >= CONFETTI_MAX: break
			var piece := _piece(burst, index, age + (float(index % 6) * 0.012 if cannon else 0.0))
			var basis := Basis.from_euler(piece.spin as Vector3) * Basis.from_scale(piece.scale as Vector3)
			_pieces.set_instance_transform(count, Transform3D(basis, piece.pos))
			_pieces.set_instance_color(count, colors[int(piece.color) % colors.size()].srgb_to_linear())
			count += 1
	_pieces.visible_instance_count = count
