extends RefCounted
## The world around the course in the candy look (docs/backdrop.md "CandyWorld"): a static, bright, saturated pastel meadow diorama seen from a floating course, built from our own code-made
## meshes in a handful of draw calls. Near to far: a pink slime sea at the kill plane, a lime terrain with white contour lines and swirl tracks around a lake that hugs
## the course, round broccoli trees and bushes (all natural green), meringue mountains with pink bands and white caps, cumulus puffs, and a pale cloud wall on the horizon, all hand-lit
## (hemisphere ambient + the sun) and fogged by the exp2 fog of the daylight look inside their own shaders (style/candy_fog.gdshaderinc, no `Environment` fog). The sky itself is
## style/candy_light.gd's (`sky_node()`, added here when it gives one). Decor only: no collision, no light, no shadow, no outline, no motion (the slime's pattern drifts slowly, that is all).
## Every number is from style/candy_look.gd. The sea is a LAKE hugging the course (the rectangle or circle of the course plus LAKE_MARGIN, a wobbly shore), the lime land rises from its shore
## in rolling hills; nothing of the land stands within LAKE_MARGIN * (1 - SHORE_WOBBLE) of the course, so nothing is ever above or beside the route. `CandyWorld.build(options)`:
##   centre        Vector3  where the world stands: its x / z are the middle of the course, the world node is placed here (the parent's space)
##   course_rect   Rect2    (optional) the course's rectangle in x / z (parent's space): the world is centred on it (`centre`'s x / z are then ignored) and its lake is that rectangle plus LAKE_MARGIN
##   lake_margin   float    m the lake's shore stands off the course (default LAKE_MARGIN 30): a stage round asks for a wide one, so the lime islands lie in the slime round the arena
##   course_radius float    horizontal radius of the course round `centre` (m) when there is no `course_rect`: the lake is a round one of that radius plus LAKE_MARGIN
##   floor_y       float    the course's lowest walkable surface (parent's space) - the terrain stands under it when there is no sea
##   world_scale   float    1.0 desktop, 0.25 phones: every distance and size x S, fog density / S, fewer pieces on a phone
##   seed          int      the layout of hills, trees, mountains and clouds
##   sea           String   "slime" | "none"
##   sea_y         float    height of the sea (parent's space): the kill plane of the race rounds
##   foliage_from  float    the nearest a tree stands to the middle of the lake (default FOLIAGE_NEAREST 150 m): a walled yard asks for far ones so no treetop shows over its walls
##   view_y        float    the usual camera height over the sea (m), the mountains' tops and the clouds are lifted to stand 3-13 degrees over the horizon from there (default floor_y - sea + 15)
##   quality       int      0 phone, 1, 2 desktop (pieces and detail); default Style.quality()-like: 2
##   sun_azimuth   float    degrees, default CandyLook.SUN_AZIMUTH
## Height is metres over the sea in the full-size world; the node `Diorama` is scaled by `world_scale`, so a scaled world is the same picture closer. Meshes are cached per size.
const Look := preload("res://style/candy_look.gd")
const CandyMesh := preload("res://style/candy_mesh.gd")
const CandyLight := preload("res://style/candy_light.gd")
const SURFACE := preload("res://style/candy_surface.gdshader")
const BACKDROP := preload("res://style/candy_backdrop.gdshader")
const TERRAIN := preload("res://style/candy_terrain.gdshader")
const SEA := preload("res://style/candy_sea.gdshader")

const LAKE_MARGIN := 30.0            ## m the lake's shore stands off the course's rectangle or circle (before the wobble)
const TERRACE := 22.0               ## m between the ledges of the meadow's plateaus (the contour lines sit on them)
const SHORE_FOAM := 1.1               ## m: the white foam line stands this far on each side of the waterline (the height 0 of `_height`), in both the terrain's and the sea's shader
const SDF_SIDE := 384                ## texels along the longest side of the shore field (256 on a phone)
const ISLAND_LIFT := 18.0            ## m an island rises from the lake bed (-12 m): its top stands 6 m over the slime
const SHORE_WOBBLE := 0.3            ## the shore's margin varies by +- this share of itself
const SEA_DROP := 16.0               ## m the terrain level stands under the floor when there is no sea
const TERRAIN_OUTER := 1450.0
const WALL_BOTTOM := -700.0
const WALL_TOP := 260.0              ## m over the camera height `view_y`: the haze band's ridge, about 4 degrees over the horizon at its 2600 m
const WALL_JITTER := 40.0
const WALL_SKY := Color("#5edcf2")    ## screen colour the haze band's top ring fades to: the sky's own colour a few degrees over the horizon (lightened by the facets)
const WALL_HAZE := Color("#c4effb")    ## screen colour of the haze band below its fade and of the mountains' foot haze: a pale cyan that does not clip to white
const WALL_FOG := 0.3                ## the haze band takes half the exp2 fog: a pale cyan-white band, not the fog's own colour
const WALL_SEGMENTS := 192            ## scalloped: a cumulus edge
const TERRAIN_VARIANTS := 3
const MOUNTAIN_COUNT := 14
const MOUNTAIN_BROAD := [Color("#a8d84a"), Color("#f98cb4"), Color("#ffc8dc"), Color("#e04f8f"), Color("#ffffff")] ## screen colours of the bands, bottom to top: green foot, salmon-pink body, pale stripe, deep pink under the cap, snow
const MOUNTAIN_SKINNY := [Color("#b4dc6e"), Color("#f786ae"), Color("#ffc0d6"), Color("#d8468a"), Color("#ffffff")]
const MOUNTAIN_BROAD_WHITE := [Color("#f5b9cf"), Color("#fdf6f9"), Color("#f4d2e3"), Color("#f2d0e3")] ## the white meringue ramp (the race worlds, 2/3 of the stage rounds'): pink foot band, white body, a faint pink band, the pale pink-lavender under the cap (SPEC 5.1: #E9D3D2 -> #FAD4DB -> #FAF5F5 -> #FAF7F7)
const MOUNTAIN_SKINNY_WHITE := [Color("#f4b0c8"), Color("#fcf3f8"), Color("#f3cde0"), Color("#f0cbe0")]
const WHITE_SHARE_STAGE := 0.3       ## the share of white mountains in a stage round's world (the rest pink, alternating); a race world (a `course_rect`) takes WHITE_SHARE_RACE
const WHITE_SHARE_RACE := 1.0
const MOUNTAIN_HORIZON_AT := 0.72         ## the height of a mountain's tip over the camera's horizon is this share of the dome's own height: the horizon cuts the dome at t = 0.28, so the pink body, the deeper pink and the snow show
const MOUNTAIN_FOG := 0.5                ## the far mountains fade into the haze (pale pink-cyan: 6 % at 1000 m, 20 % at 1900 m); their feet are hazed more (candy_backdrop.gdshader `haze`)
const CAP_AT := 0.82                 ## the snow cap starts at this share of a mountain's dome height (candy_backdrop.gdshader `cap_at`, its lobes droop under it): the cap is the top 25-35 % of what shows
const MOUNTAIN_DEPTH := 420.0        ## m under the sea the mountains' feet go: they never end in view
const SEA_BASE := Color("#f59bcb")        ## screen colours of the slime (a median of #FD9CC7: its red clips)
const SEA_DEEP := Color("#e06aa8")        ## the troughs: a deeper rose pink
const SEA_EDGE := Color("#f9a0cf")        ## the shallows near the shore and the ripple crests
const SEA_SKY := Color("#ffe4f1")      ## what the slime mirrors at a grazing angle: a pale pink white
const PUFF_LIFT := 0.12
const MOUNTAIN_LIFT := 0.0
const PUFF_COUNT := 22
const FOLIAGE_SHADE := 0.3           ## foliage is nearly flat lit (high ambient, weak N.L)
const FOLIAGE_COUNT := 240
const FOLIAGE_NEAREST := 150.0       ## m: no tree stands nearer to the lake's centre than this, and the nearer ones are made smaller
const FOLIAGE_PHONE_REACH := 900.0   ## foliage beyond this is dropped on a phone

static var _cache := {}
static var _noises := {}

## The world scale of this device (style/candy_light.gd): 0.25 on a phone (Android or Quality Low), else 1.
static func default_scale() -> float:
	return CandyLight.world_scale()

# ------------------------------------------------------------------ build

## The lake of a world for `options` at `world_scale`: {rect (centre-relative, the course's own rectangle, REAL metres), hx, hz (half sizes in the diorama's units), margin (in the diorama's
## units)}: a circle of the course radius is a rectangle of no size with the radius as margin.
static func lake_of(options: Dictionary, world_scale: float) -> Dictionary:
	var half := Vector2.ZERO
	var extra := 0.0
	if options.has("course_rect"):
		half = (options.course_rect as Rect2).size * 0.5
	else:
		extra = float(options.get("course_radius", 40.0))
	return {"hx": half.x / world_scale, "hz": half.y / world_scale, "radius": extra / world_scale, "margin": (extra + float(options.get("lake_margin", LAKE_MARGIN))) / world_scale, "seed": int(options.get("seed", 1)) % TERRAIN_VARIANTS}

static func build(options: Dictionary) -> Node3D:
	var started := Time.get_ticks_usec()
	var s := clampf(float(options.get("world_scale", 1.0)), 0.1, 1.0)
	var centre: Vector3 = options.get("centre", Vector3.ZERO)
	var sea_kind := str(options.get("sea", "slime"))
	var floor_y := float(options.get("floor_y", centre.y))
	var sea_y := float(options.get("sea_y", floor_y - SEA_DROP)) if sea_kind != "none" else floor_y - SEA_DROP
	var seed_value := int(options.get("seed", 1))
	var quality := int(options.get("quality", 2 if s >= 1.0 else 0))
	var azimuth := float(options.get("sun_azimuth", Look.SUN_AZIMUTH))
	var lake := lake_of(options, s)
	var ground := seed_value % TERRAIN_VARIANTS # the terrain's layout: a few shared ones, so its mesh is built once and cached
	var view := float(options.get("view_y", floor_y - sea_y + 15.0)) / s
	var root := Node3D.new()
	root.name = "CandyWorld"
	if options.has("course_rect"): centre = Vector3((options.course_rect as Rect2).get_center().x, centre.y, (options.course_rect as Rect2).get_center().y)
	root.position = centre
	var diorama := Node3D.new()
	diorama.name = "Diorama"
	diorama.position = Vector3(0.0, sea_y - centre.y, 0.0)
	diorama.scale = Vector3.ONE * s
	root.add_child(diorama)

	var parts := {}
	var tick := Time.get_ticks_usec()
	var look := _look(azimuth, s)
	diorama.add_child(_instance("CloudWall", _wall_mesh(quality, view), _backdrop(look, {"kind": 0, "albedo": Color.WHITE, "use_vertex_color": true, "shade": 0.0, "fog_amount": WALL_FOG})))
	var field := _shore_field(lake, quality)
	diorama.add_child(_instance("Terrain", _terrain_mesh(lake, ground, quality), _terrain(look, s, sea_y, field)))
	parts["terrain"] = _lap(tick)
	tick = Time.get_ticks_usec()
	_foliage(diorama, look, lake, seed_value, ground, quality, float(options.get("foliage_from", FOLIAGE_NEAREST)))
	parts["foliage"] = _lap(tick)
	tick = Time.get_ticks_usec()
	_mountains(diorama, look, ground, quality, view, float(options.get("white_share", WHITE_SHARE_RACE if options.has("course_rect") else WHITE_SHARE_STAGE)))
	parts["mountains"] = _lap(tick)
	tick = Time.get_ticks_usec()
	diorama.add_child(_instance("Puffs", _puff_mesh(ground, quality, view), _backdrop(look, {"kind": 0, "albedo": Color.WHITE, "use_vertex_color": true, "shade": 0.4, "lift": PUFF_LIFT})))
	parts["puffs"] = _lap(tick)
	tick = Time.get_ticks_usec()
	if sea_kind != "none": diorama.add_child(_sea(look, s, field, lake))
	parts["sea"] = _lap(tick)
	var sky := CandyLight.sky_node()
	if sky != null: root.add_child(sky)
	root.set_meta("build_ms", float(Time.get_ticks_usec() - started) / 1000.0)
	root.set_meta("build_parts", parts)
	return root

static func _lap(since: int) -> String:
	return "%.1f ms" % (float(Time.get_ticks_usec() - since) / 1000.0)

## Draw calls and triangles of a built world: {draws, triangles} (counted from what `build` put in the tree, MultiMesh instances included).
static func stats(world: Node) -> Dictionary:
	var draws := 0
	var triangles := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		if not node.has_meta("triangles"): continue
		draws += 1
		triangles += int(node.get_meta("triangles")) * int(node.get_meta("instances", 1))
	return {"draws": draws, "triangles": triangles}

## What the `shaders` of the backdrop share: the look's sun, ambient and fog numbers, scale covariant fog.
static func _look(azimuth: float, s: float) -> Dictionary:
	return {
		"sun_dir": Look.towards(Look.SUN_ELEVATION, azimuth), "sun_col": Look.SUN_COLOR, "sun_energy": Look.SUN_ENERGY,
		"amb_up": _vec(Look.AMBIENT_B_UP), "amb_side": _vec(Look.AMBIENT_B_SIDE), "amb_down": _vec(Look.AMBIENT_B_DOWN),
		"fog_color": _uniform(Look.FOG_COLOR), "fog_density": Look.fog_density(s)}

## The scene-linear light that makes the picture show the SCREEN colour `screen` (CandyLook.scene_linear: the tone mapper and the grade are inverted). The backdrop is authored in screen colours.
static func _screen(screen: Color) -> Color:
	return Look.scene_linear(screen)

## The same for a `source_color` shader uniform (Godot converts those from sRGB on upload).
static func _uniform(screen: Color) -> Color:
	return Look.scene_linear(screen).linear_to_srgb()

static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

static func _material(shader: Shader, shared: Dictionary, own: Dictionary, keys: Array) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in keys:
		if shared.has(key): material.set_shader_parameter(key, shared[key])
	for key: String in own: material.set_shader_parameter(key, own[key])
	return material

static func _backdrop(look: Dictionary, own: Dictionary) -> ShaderMaterial:
	return _material(BACKDROP, look, own, ["sun_dir", "sun_col", "sun_energy", "amb_up", "amb_side", "amb_down", "fog_color", "fog_density"])

static func _terrain(look: Dictionary, s: float, sea_y: float, field: Dictionary) -> ShaderMaterial:
	var own := {"world_scale": s, "sea_y": sea_y, "line_color": _uniform(Color("#fbfbdc")), "foam_color": _uniform(Color.WHITE), "swirl_color": _uniform(Color("#e6f4a8")), "slope_color": _uniform(Color("#b4d283"))}
	own.merge(_shore_uniforms(field))
	return _material(TERRAIN, look, own, ["sun_dir", "sun_col", "sun_energy", "amb_up", "amb_side", "amb_down", "fog_color", "fog_density"])

## A decor instance: no shadow, no GI, counted by `stats`.
static func _instance(label: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.set_meta("triangles", _triangles(mesh))
	return node

static func _triangles(mesh: Mesh) -> int:
	return int(mesh.get_meta("triangles", 0)) if mesh.has_meta("triangles") else 0

static func _counted(mesh: ArrayMesh, triangles: int) -> ArrayMesh:
	mesh.set_meta("triangles", triangles)
	return mesh

const NOISE_FREQUENCIES := [0.0, 0.0042, 0.016, 0.005, 0.02, 0.0021, 0.011, 0.009] ## by salt: 1 hills, 2 fine hills, 3 and 4 colour patches, 5 big hills, 6 shore, 7 islands

## The noises of terrain layout `seed_value`, indexed by salt (NOISE_FREQUENCIES), made once.
static func _noise_set(seed_value: int) -> Array:
	if not _noises.has(seed_value):
		var set: Array = []
		for salt in NOISE_FREQUENCIES.size():
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.seed = seed_value * 7 + salt
			noise.frequency = NOISE_FREQUENCIES[salt]
			set.append(noise)
		_noises[seed_value] = set
	return _noises[seed_value]

# ------------------------------------------------------------------ cloud wall

## Open cylinder R 2600, inward facing, down to WALL_BOTTOM (nothing under the mountains is ever sky) and up to a soft top ring (WALL_TOP +- WALL_JITTER) in three rings: the pale haze colour
## up to a quarter of the way over the horizon, then fading to the sky's own horizon colour at the top, so there is no hard line between the haze and the sky.
static func _wall_mesh(quality: int, view: float) -> ArrayMesh:
	var key := "wall:%d:%d" % [quality, roundi(view / 10.0)]
	if _cache.has(key): return _cache[key]
	var segments := WALL_SEGMENTS if quality > 0 else 48
	var rng := RandomNumberGenerator.new()
	rng.seed = 2600
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var haze := _screen(WALL_HAZE)
	var sky := _screen(WALL_SKY)
	for k in segments:
		var a := TAU * float(k) / float(segments)
		var top := maxf(view, 0.0) + WALL_TOP + sin(a * 7.0) * WALL_JITTER * 0.5 + absf(sin(a * 31.0 + 1.0)) * WALL_JITTER * 0.9 - WALL_JITTER * 0.4 + rng.randf_range(-1.0, 1.0) * WALL_JITTER * 0.2
		var dir := Vector3(cos(a), 0.0, sin(a))
		var mid := maxf(view, 0.0) + (top - maxf(view, 0.0)) * 0.25
		for ring in [[WALL_BOTTOM, haze], [mid, haze], [top, sky]]:
			v.append(dir * Look.CLOUD_WALL_RADIUS + Vector3(0.0, float(ring[0]), 0.0))
			c.append(ring[1])
			n.append(-dir)
	for k in segments:
		var next := (k + 1) % segments
		for ring in 2:
			var b0 := k * 3 + ring
			var t0 := b0 + 1
			var b1 := next * 3 + ring
			var t1 := b1 + 1
			i.append_array(PackedInt32Array([b0, t0, t1, b0, t1, b1])) # seen from inside, clockwise
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = _counted(mesh, i.size() / 3)
	return _cache[key]

# ------------------------------------------------------------------ terrain

## Distance (diorama units) from (x, z) to the course's rectangle (0 inside it): a circle for a rectangle of no size.
static func _course_distance(x: float, z: float, lake: Dictionary) -> float:
	return Vector2(maxf(absf(x) - float(lake.hx), 0.0), maxf(absf(z) - float(lake.hz), 0.0)).length()

## The terrain's height over the sea at (x, z) in the full-size world, `lake` from `lake_of`, `seed_value` one of TERRAIN_VARIANTS: a lake hugging the course with a wobbly shore (the ground
## dips under the sea, a few islands), land that rises from the shore in rolling hills (bigger the farther out, 10-80 m), a rim that keeps the sea inside, then the skirt that falls away to
## nothing under the mountains.
static func height(x: float, z: float, lake: Dictionary, seed_value: int) -> float:
	return _height(x, z, lake, _noise_set(seed_value))

## Metres from the shore at (x, z) (negative on the lake): the distance to the course's rectangle less the lake's wobbling margin.
static func _shore(x: float, z: float, lake: Dictionary, n: Array) -> float:
	var margin: float = lake.margin + minf(lake.margin * SHORE_WOBBLE * 1.4, 12.6) * (n[6] as FastNoiseLite).get_noise_2d(x, z) + _wide_wobble(lake.margin) * (n[5] as FastNoiseLite).get_noise_2d(x, z)
	return _course_distance(x, z, lake) - margin

## How far (m) the shore of a lake of `margin` m can stand from it, either way: a narrow lake wobbles by the share SHORE_WOBBLE of itself (12.6 m at the most, in the 90 m waves of noise 6), a wide
## one (a tower's) also by up to 45 m in the broad waves of noise 5: more would fold the shore into ponds (the wobble's slope across the shore stays under 1.1).
static func _wobble_bound(margin: float) -> float:
	return minf(margin * SHORE_WOBBLE * 1.4, 12.6) + _wide_wobble(margin)

static func _wide_wobble(margin: float) -> float:
	return clampf((margin - 60.0) * 0.1, 0.0, 45.0)

static func _height(x: float, z: float, lake: Dictionary, n: Array) -> float:
	var d := _course_distance(x, z, lake)
	var s := _shore(x, z, lake, n)
	var h := lerpf(-12.0, 2.4, smoothstep(-14.0, 6.0, s)) # a lip: the meadow drops to the lake within 20 m (the waterline is at s = SHORE_WATERLINE)
	var wobble := (n[1] as FastNoiseLite).get_noise_2d(x, z) * 0.75 + (n[2] as FastNoiseLite).get_noise_2d(x, z) * 0.25
	h += wobble * lerpf(2.0, 10.0, smoothstep(0.0, 500.0, s)) * smoothstep(-6.0, 30.0, s)
	var hills := (n[5] as FastNoiseLite).get_noise_2d(x, z) * 0.5 + 0.5 # big rolling hills: they lift the horizon of the meadow
	var raised := hills * hills * 105.0 * smoothstep(30.0, 300.0, s)
	var stair := floorf(raised / TERRACE) * TERRACE + TERRACE * smoothstep(0.3, 0.7, fposmod(raised / TERRACE, 1.0)) # plateaus with ledges
	h += lerpf(raised, stair, 0.8)
	var ring := (n[5] as FastNoiseLite).get_noise_2d(x * 1.7 + 300.0, z * 1.7) * 0.5 + 0.5 # a ring of rolling hills out where the mountains stand: they lift the meadow's horizon and hide the mountains' feet
	var ringed := d - clampf(float(lake.margin) - 160.0, 0.0, 700.0) # a tower's wide lake pushes the ring of hills out with its shore: it never raises land inside the slime
	h += (10.0 + 34.0 * ring) * smoothstep(380.0, 700.0, ringed) * (1.0 - smoothstep(1100.0, 1400.0, ringed))
	h += _island_bump(x, z, lake, n) # a few lime islands in the lake
	if s > 0.0: h = maxf(h, 1.6 * smoothstep(0.0, 6.0, s)) # no ponds on the land: the hills never dip back under the slime, so the shore is one clean line
	d = maxf(d - 1150.0, 0.0)
	return h - 125.0 * smoothstep(0.0, 400.0, d) - maxf(d - 400.0, 0.0) * 0.3

static func _terrain_mesh(lake: Dictionary, seed_value: int, quality: int) -> ArrayMesh:
	var hx := ceilf(float(lake.hx) / 25.0) * 25.0 # the cache key: lakes of nearly one size share a mesh
	var hz := ceilf(float(lake.hz) / 25.0) * 25.0
	var margin := ceilf(float(lake.margin) / 5.0) * 5.0
	var key := "terrain:%d:%d:%d:%d:%d" % [int(hx), int(hz), int(margin), seed_value, quality]
	if _cache.has(key): return _cache[key]
	var lake_q := {"hx": hx, "hz": hz, "margin": margin, "seed": lake.seed}
	var sectors := 120 if quality > 0 else 80
	var shore_far := Vector2(hx, hz).length() + margin + _wobble_bound(margin) + 60.0
	var shore_near := minf(hx, hz) + margin - _wobble_bound(margin)
	var inner := maxf(8.0, shore_near - 50.0)
	for island: Vector3 in _islands(lake_q): inner = minf(inner, Vector2(island.x, island.y).length() - island.z - 30.0) # the rings start inside the islands' feet: an island is land, never a hole
	var radii := PackedFloat32Array()
	var step := maxf(10.0 if quality > 0 else 14.0, (shore_far - inner) / 44.0) # a wide lake: its bed is cut away by the shader, a coarser mesh does
	var r := inner
	while r < shore_far:
		radii.append(r)
		r += step
	var outer := TERRAIN_OUTER + Vector2(hx, hz).length()
	var far_rows := 24 if quality > 0 else 16
	for row in far_rows + 1: radii.append(shore_far + (outer - shore_far) * pow(float(row) / float(far_rows), 1.5))
	var rows := radii.size() - 1
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var green := _screen(Color("#cde396")) # screen colours of a lit upward face: a pale lime (the range #A1C14F to #B1EE7F, #B2DF6A to #DAEF8D), in scene-linear light and mixed there
	var pale := _screen(Color("#d9ecab"))
	var deep := _screen(Color("#bad87c"))
	var warm := _screen(Look.TERRAIN_TINTS[0] as Color)
	var rose := _screen(Look.TERRAIN_TINTS[1] as Color)
	var noises := _noise_set(seed_value)
	var patch: FastNoiseLite = noises[3]
	var fine: FastNoiseLite = noises[4]
	for row in rows + 1:
		for sector in sectors:
			var a := TAU * float(sector) / float(sectors)
			var x := cos(a) * radii[row]
			var z := sin(a) * radii[row]
			var h := _height(x, z, lake_q, noises)
			v.append(Vector3(x, h, z))
			var m := patch.get_noise_2d(x, z) * 0.5 + 0.5 + fine.get_noise_2d(x, z) * 0.1
			var colour := green.lerp(pale, smoothstep(0.45, 0.85, m)).lerp(deep, smoothstep(0.4, 0.1, m))
			colour = colour.lerp(warm, smoothstep(0.86, 0.99, m) * 0.2).lerp(rose, smoothstep(0.08, 0.0, m) * 0.1)
			c.append(colour)
	var idx := PackedInt32Array()
	for row in rows:
		for sector in sectors:
			var a := row * sectors + sector
			var b := row * sectors + (sector + 1) % sectors
			var cc := a + sectors
			var d := b + sectors
			idx.append_array(PackedInt32Array([a, cc, d, a, d, b]))
	if (v[idx[2]] - v[idx[0]]).cross(v[idx[1]] - v[idx[0]]).y < 0.0: # the faces must look up
		for k in range(0, idx.size(), 3):
			var swap := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = swap
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = CandyMesh.normals_of(v, idx)
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = _counted(mesh, idx.size() / 3)
	return _cache[key]

# ------------------------------------------------------------------ foliage

const GREENS := ["#90bd5e", "#88b85e", "#9cc668", "#7fae56", "#a8ce70", "#92bf62"] ## screen colours of the crowns' lit tops: light to mid leaf green only, never a brand or cast colour (bright lit tops)

## A broccoli tree: a short trunk and a crown of five overlapping round balls (one big, three round it, one over it), smooth normals, no lumps; `quality` 0 (a phone) uses fewer segments.
static func _tree_mesh(quality: int) -> ArrayMesh:
	var key := "tree:%d" % quality
	if _cache.has(key): return _cache[key]
	var builder := CandyMesh.new()
	var rings := 9 if quality > 0 else 6
	var sectors := 14 if quality > 0 else 9
	var white := Color.WHITE
	var shade := Color(0.7, 0.82, 0.55) # the crown's belly is a little deeper green: lit nearly flat, a little shade underneath and between the balls
	var flag := Color(1.0, 1.0, 1.0, 0.5)
	var trunk := PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.055, 0.34)])
	builder.raw = true
	builder.lathe(trunk, PackedColorArray([flag, flag]), 8)
	builder.raw = false
	builder.blob(Vector3(0.0, 0.5, 0.0), Vector3(0.3, 0.3, 0.3), white, shade, rings, sectors)
	for lobe in 3:
		var angle := float(lobe) / 3.0 * TAU + 0.5
		builder.blob(Vector3(cos(angle) * 0.26, 0.44 + 0.04 * float(lobe), sin(angle) * 0.26), Vector3(0.21, 0.21, 0.21), white, shade, rings, sectors)
	builder.blob(Vector3(0.03, 0.74, -0.02), Vector3(0.2, 0.2, 0.2), white, shade, rings, sectors)
	_cache[key] = _counted(builder.to_mesh(), builder.triangle_count())
	return _cache[key]

## A bush: three round balls, smooth.
static func _bush_mesh(quality: int) -> ArrayMesh:
	var key := "bush:%d" % quality
	if _cache.has(key): return _cache[key]
	var builder := CandyMesh.new()
	var rings := 7 if quality > 0 else 5
	var sectors := 12 if quality > 0 else 8
	var white := Color.WHITE
	var shade := Color(0.72, 0.83, 0.58)
	builder.blob(Vector3(0.0, 0.34, 0.0), Vector3(0.42, 0.34, 0.42), white, shade, rings, sectors, 0.0, 2, -0.3)
	builder.blob(Vector3(0.3, 0.24, 0.08), Vector3(0.26, 0.24, 0.26), white, shade, rings, sectors, 0.0, 9, -0.3)
	builder.blob(Vector3(-0.3, 0.22, -0.06), Vector3(0.24, 0.22, 0.26), white, shade, rings, sectors, 0.0, 14, -0.3)
	_cache[key] = _counted(builder.to_mesh(), builder.triangle_count())
	return _cache[key]

static func _pick_colour(rng: RandomNumberGenerator) -> Color:
	return _screen(Color(GREENS[rng.randi() % GREENS.size()]))

## 90 trees and bushes on the dry terrain between r 140 and 1250 (a phone drops what is beyond 900 and keeps a third of the rest), two MultiMeshes, all green.
static func _foliage(parent: Node3D, look: Dictionary, lake: Dictionary, seed_value: int, ground: int, quality: int, nearest: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	var count := FOLIAGE_COUNT if quality > 0 else 30
	var kinds := [[], []] # trees, bushes: {t: Transform3D, c: Color}
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 12:
		guard += 1
		var r := (nearest + (700.0 - nearest) * rng.randf()) if rng.randf() < 0.55 else (maxf(nearest, 600.0) + (1200.0 - maxf(nearest, 600.0)) * rng.randf()) # most of them along the ring of the horizon, 550-1150 m
		if quality == 0 and r > FOLIAGE_PHONE_REACH: continue
		var a := rng.randf() * TAU
		var x := cos(a) * r
		var z := sin(a) * r
		var h := height(x, z, lake, ground)
		if h < 1.2 or _course_distance(x, z, lake) < float(lake.margin) * 0.8 + 30.0: continue # on dry land only
		var kind := 0 if rng.randf() < 0.5 else 1
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var size := Vector3.ONE
		if kind == 0:
			var tall := rng.randf_range(9.0, 30.0)
			var wide := tall * rng.randf_range(0.9, 1.0) * 1.2 # round crowns: nearly as wide as tall (no stretching)
			size = Vector3(wide, tall * 1.2, wide)
		else:
			var tall := rng.randf_range(5.0, 12.0)
			size = Vector3(tall * 1.4, tall, tall * 1.4)
		size *= lerpf(0.6, 1.0, smoothstep(nearest, nearest + 250.0, r)) # the nearer ones are smaller
		kinds[kind].append({"t": Transform3D(basis.scaled(size), Vector3(x, h - size.y * 0.04, z)), "c": _pick_colour(rng)})
		placed += 1
	var names := ["Trees", "Bushes"]
	var material := _backdrop(look, {"kind": 1, "shade": FOLIAGE_SHADE, "fog_mul": 1.3, "trunk_color": _uniform(Color("#d49a6c"))})
	for kind in 2:
		var list: Array = kinds[kind]
		if list.is_empty(): continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _bush_mesh(quality) if kind == 1 else _tree_mesh(quality)
		multi.instance_count = list.size()
		for k in list.size():
			multi.set_instance_transform(k, list[k].t)
			multi.set_instance_color(k, list[k].c)
		var node := MultiMeshInstance3D.new()
		node.name = names[kind]
		node.multimesh = multi
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.set_meta("triangles", _triangles(multi.mesh))
		node.set_meta("instances", list.size())
		parent.add_child(node)

# ------------------------------------------------------------------ mountains

const DOME_Q := [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.42, 0.35, 0.29, 0.24, 0.2, 0.16, 0.125, 0.09, 0.062, 0.04, 0.022, 0.008, 0.0] ## the rows of a dome from its foot to its tip, as shares of its visible height under the tip (dense under the snow cap and at the rounded summit)

## One lobe of a meringue mountain, standing on y = 0 at `at` (x, z), `vis` metres of broad rounded dome (radius `radius` at its foot, `pow(q, bulge)` round to a sphere-cap summit, lumpy in section) under its tip
## and `extra` more metres of broadening foot down to the diorama's depth (never seen: it only keeps the foot of a mountain under the terrain and the haze whatever the camera's height). The colour data
## (r: how high inside the visible dome, 0 below it; g: 1 for the white meringue ramp, 0 for the pink one) is what candy_backdrop.gdshader bands into green foot, body, deeper tone and the snow cap.
static func _lobe(builder: CandyMesh, at: Vector2, radius: float, vis: float, extra: float, phase: float, sectors: int, bulge: float, white: float) -> void:
	var profile := PackedVector2Array()
	var colors := PackedColorArray()
	var tall := vis + extra
	var foot_q := tall / vis
	var qs: Array = [foot_q, 1.0 + (foot_q - 1.0) * 0.4]
	qs.append_array(DOME_Q)
	for q: float in qs:
		var f := 1.0 - q # how high inside the visible dome
		var r := radius * (pow(q, bulge) if q <= 1.0 else 1.0 + (q - 1.0) * 0.7)
		r *= 1.0 + 0.05 * exp(-pow((f - CAP_AT) / 0.05, 2.0)) # the snow cap's puffy lip
		profile.append(Vector2(r, tall - q * vis))
		colors.append(Color(clampf(f, 0.0, 1.0), white, 0.0, 1.0))
	builder.push(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y)))
	builder.lathe(profile, colors, sectors, 0.05, 5, phase)
	builder.pop()

## Where the mountains stand, one entry each {a: azimuth, r: distance, half: half angle the foot radius takes (rad), elevation: angle of the tip over the horizon seen from `view`, top: its height, skinny,
## white: 1 for the white meringue ramp}: r 1100-1900 round the diorama, tops 6-16 degrees over the horizon (median about 10; flat frames show 4-13, the gameplay cameras stand higher than `view`), broad domes with a
## half width 1.3-1.8 x their height (skinny ones 0.9-1.2), with gaps of meadow and sky between them; `white_share` of them (WHITE_SHARE_RACE / WHITE_SHARE_STAGE) take the white ramp, the rest the pink one.
static func _mountain_plan(seed_value: int, quality: int, view: float, white_share := 0.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 3
	var count := MOUNTAIN_COUNT if quality > 0 else 8
	var plan := []
	for k in count:
		var skinny := k % 4 == 3
		var a := TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / float(count)
		var r := 1250.0 + 650.0 * pow(rng.randf(), 1.3)
		var elevation_deg := clampf((13.0 if skinny else 10.0) + rng.randfn(0.0, 2.5), 6.0, 14.0)
		var elevation := deg_to_rad(elevation_deg)
		var half := minf(atan(tan(elevation) * (rng.randf_range(0.9, 1.2) if skinny else rng.randf_range(1.2, 1.6))), deg_to_rad(15.0)) # the dome's foot radius over the horizon follows its height, never wider than 30 degrees across
		var white := 1.0 if rng.randf() < white_share else 0.0
		plan.append({"a": a, "r": r, "half": half, "elevation": elevation, "top": view + r * tan(elevation), "skinny": skinny, "white": white})
	return plan

## The mountains as two merged meshes (broad and skinny kind; two draws), each a cluster of one to three lobes of its own.
static func _mountain_meshes(seed_value: int, quality: int, view: float, white_share: float) -> Array[ArrayMesh]:
	var key := "mountains:%d:%d:%d:%d" % [seed_value, quality, roundi(view / 10.0), roundi(white_share * 100.0)]
	if _cache.has(key): return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 23 + 7
	var sectors := 28 if quality > 0 else 14
	var builders: Array[CandyMesh] = [CandyMesh.new(), CandyMesh.new()]
	for builder in builders: builder.raw = true
	for m: Dictionary in _mountain_plan(seed_value, quality, view, white_share):
		var builder: CandyMesh = builders[1 if m.skinny else 0]
		var a: float = m.a
		var tall := (float(m.top) - view) / MOUNTAIN_HORIZON_AT # the dome's height: the camera's horizon cuts it at this share, so the body and the snow are what shows
		var radius := float(m.r) * tan(float(m.half))
		var foot := -MOUNTAIN_DEPTH
		var bulge := 0.6 if m.skinny else 0.5 # 0.5: a parabola, the tip is a rounded cap
		builder.push(Transform3D(Basis(Vector3.UP, -a + rng.randf_range(-0.35, 0.35)), Vector3(cos(a) * float(m.r), foot, sin(a) * float(m.r))))
		var lobes := 1 + rng.randi() % 3
		var side_sign := -1.0 if rng.randf() < 0.5 else 1.0
		for lobe in lobes:
			var share := 1.0 if lobe == 0 else rng.randf_range(0.45, 0.78)
			var small := 1.0 if lobe == 0 else rng.randf_range(0.5, 0.75)
			var side := 0.0 if lobe == 0 else (side_sign if lobe == 1 else -side_sign) * rng.randf_range(1.0, 1.3) # along the view (local z): the neighbour lobes stand beside the big one
			_lobe(builder, Vector2(rng.randf_range(-0.3, 0.3) * radius, side * radius), radius * small, tall * share, float(m.top) - foot - tall, rng.randf() * 6.0, sectors, bulge, float(m.white))
		builder.pop()
	var meshes: Array[ArrayMesh] = []
	for builder in builders: meshes.append(_counted(builder.to_mesh(), builder.triangle_count()))
	_cache[key] = meshes
	return meshes

## The mountains of the diorama, two merged meshes with the band ramps of the broad and the skinny kind (pink ramp `MOUNTAIN_*`, white ramp `MOUNTAIN_*_WHITE`, picked per lobe by the vertex colour's g).
static func _mountains(parent: Node3D, look: Dictionary, seed_value: int, quality: int, view: float, white_share: float) -> void:
	var meshes := _mountain_meshes(seed_value, quality, view, white_share)
	var ramps := [MOUNTAIN_BROAD, MOUNTAIN_SKINNY]
	var whites := [MOUNTAIN_BROAD_WHITE, MOUNTAIN_SKINNY_WHITE]
	for kind in 2:
		var ramp: Array = ramps[kind]
		var white: Array = whites[kind]
		var own := {"kind": 2, "shade": 1.0, "lift": MOUNTAIN_LIFT, "fog_mul": MOUNTAIN_FOG, "use_vertex_color": true, "cap_at": CAP_AT, "haze_color": _uniform(WALL_HAZE), "ramp0": _uniform(ramp[0]), "ramp1": _uniform(ramp[1]), "ramp2": _uniform(ramp[2]), "ramp3": _uniform(ramp[3]), "ramp4": _uniform(ramp[4]), "wramp1": _uniform(white[0]), "wramp2": _uniform(white[1]), "wramp3": _uniform(white[2]), "wramp4": _uniform(white[3])}
		parent.add_child(_instance("MountainsSkinny" if kind == 1 else "Mountains", meshes[kind], _backdrop(look, own)))

# ------------------------------------------------------------------ clouds

## The cumulus puffs merged into one mesh: PUFF_COUNT separate heaps of a few big round lobes with a flat bottom, 10-15 percent of their distance wide, r 1000-2000, 12-34 degrees over the horizon from `view`, each
## lifted to stand at least 6 degrees over any peak at its azimuth (the peaks stand 4-13 degrees; the puffs 12-34, evenly spread round the horizon so every 60 degrees of view holds three). Almost white, with only slightly cooler bellies.
static func _puff_mesh(seed_value: int, quality: int, view: float) -> ArrayMesh:
	var key := "puffs:%d:%d:%d" % [seed_value, quality, roundi(view / 10.0)]
	if _cache.has(key): return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 1
	var plan := _mountain_plan(seed_value, quality, view)
	var builder := CandyMesh.new()
	builder.raw = true # vertex colours in scene-linear light
	var count := PUFF_COUNT if quality > 0 else 10
	var rings := 7 if quality > 0 else 5
	var sectors := 12 if quality > 0 else 8
	var top := _screen(Color("#fcfeff"))
	var under := _screen(Color("#e2edf6"))
	for k in count:
		var r := rng.randf_range(1000.0, 2000.0)
		var width := r * rng.randf_range(0.1, 0.15) * 2.0
		var elevation := 9.0 + 17.0 * pow(rng.randf(), 1.1)
		var a := TAU * (float(k) + rng.randf_range(-0.25, 0.25)) / float(count)
		var forward := k < 3 # three puffs in front of the stage camera (+Z, within 25 degrees of it), behind the domes (1900-2200 m) at 14-20 degrees: they float in the open sky between and above the peaks
		if forward:
			a = PI * 0.5 + float(k - 1) * 0.43 + rng.randf_range(-0.05, 0.05)
			r = rng.randf_range(1900.0, 2200.0)
			width = r * rng.randf_range(0.1, 0.14) * 2.0
			elevation = 14.0 + 6.0 * rng.randf()
			var a0 := a
			for step in 25: # sideways (alternating) into the first gap whose peaks are 4 degrees under the puff
				a = a0 + ceilf(float(step) * 0.5) * 0.04 * (1.0 if step % 2 == 0 else -1.0)
				var clear := true
				for m: Dictionary in plan:
					if absf(wrapf(a - float(m.a), -PI, PI)) < float(m.half) + width / r * 0.5 and rad_to_deg(float(m.elevation)) + 4.0 > elevation: clear = false
				if clear: break
		for m: Dictionary in plan: # clear of the mountain peaks at this azimuth (never above 22 degrees)
			if absf(wrapf(a - float(m.a), -PI, PI)) < float(m.half) + width / r * 0.5: elevation = minf(maxf(elevation, rad_to_deg(float(m.elevation)) + (4.0 if forward else 6.0)), 22.0)
		var y := view + r * tan(deg_to_rad(elevation))
		builder.push(Transform3D(Basis(Vector3.UP, a + PI * 0.5 + rng.randf_range(-0.4, 0.4)), Vector3(cos(a) * r, y, sin(a) * r))) # its length across the view
		var lumps := 4 + rng.randi() % 3
		for lump in lumps:
			var along := float(lump) / float(lumps - 1) * 2.0 - 1.0
			var main := 1.0 - absf(along) * 0.5
			var rx := width * 0.25 * main * rng.randf_range(0.85, 1.1)
			builder.blob(Vector3(along * width * 0.3, rx * 0.7, rng.randf_range(-0.08, 0.08) * width), Vector3(rx, rx * 0.85, rx * 0.95), top, under, rings, sectors, 0.02, lump * 3 + k, -0.4)
		builder.blob(Vector3(width * rng.randf_range(-0.08, 0.08), width * 0.26, 0.0), Vector3(width * 0.22, width * 0.2, width * 0.21), top, under, rings, sectors, 0.02, k * 5 + 1, -0.4) # the crown
		builder.pop()
	_cache[key] = _counted(builder.to_mesh(), builder.triangle_count())
	return _cache[key]

# ------------------------------------------------------------------ sea

## The lake's islands as Vector3(x, z, radius) of the foot of each (its shore stands at 0.64 of it): two in front of a stage round (a wide lake round a circle; toward +Z, where the stage camera looks,
## and a little to its sides), none in a narrow lake of a race course. Laid out by the layout `lake.seed`, from the lake's rounded size, so the terrain, the shore field and the trees agree.
static func _islands(lake: Dictionary) -> Array:
	var margin := ceilf(float(lake.margin) / 5.0) * 5.0
	var round_lake := float(lake.hx) + float(lake.hz) < 1.0
	if not round_lake or margin < 120.0: return []
	var key := "islands:%d:%d" % [int(margin), int(lake.get("seed", 0))]
	if _cache.has(key): return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lake.get("seed", 0)) * 977 + int(margin)
	var list := []
	var angles := [-0.62, 0.58]           # radians off the +Z axis: none on the stage camera's axis (an island there fills the whole band between the rail and the horizon)
	var reaches := [0.93, 0.9]            # share of the margin from the middle (the stage camera hangs high: the slime it sees over the rail and the layers is 70-95 % of the way out)
	for k in angles.size():
		var a := PI * 0.5 + float(angles[k]) + rng.randf_range(-0.1, 0.1)
		var r := margin * float(reaches[k]) * rng.randf_range(0.92, 1.0)
		list.append(Vector3(cos(a) * r, sin(a) * r, margin * rng.randf_range(0.07, 0.085)))
	_cache[key] = list
	return list

## How much the islands raise the lake bed at (x, z) (m): a wobbling round hill per island.
static func _island_bump(x: float, z: float, lake: Dictionary, n: Array) -> float:
	var islands := _islands(lake)
	if islands.is_empty(): return 0.0
	var wobble := 1.0 + (n[4] as FastNoiseLite).get_noise_2d(x, z) * 0.35
	var best := 0.0
	for island: Vector3 in islands:
		var dist := Vector2(x - island.x, z - island.y).length() * wobble
		best = maxf(best, smoothstep(island.z, island.z * 0.45, dist))
	return best * ISLAND_LIFT

## The shore field of the lake: the height over the slime (the waterline is its contour 0; negative on the slime) and its slope, baked at 384 texels along its longest side (256 on a phone) over the lake's
## window (the lake plus the wobble plus 60 m) as a half float texture, so the foam line, the rings and the lime / pink edge are exact whatever the meshes' resolution (a coarse mesh would
## step the shore). {texture, origin: Vector2, size: Vector2} in the diorama's units. Outside the window it reads as land (clamped to the edge texels, which are dry).
static func _shore_field(lake: Dictionary, quality: int) -> Dictionary:
	var hx := ceilf(float(lake.hx) / 25.0) * 25.0
	var hz := ceilf(float(lake.hz) / 25.0) * 25.0
	var margin := ceilf(float(lake.margin) / 5.0) * 5.0
	var key := "shore:%d:%d:%d:%d:%d" % [int(hx), int(hz), int(margin), int(lake.get("seed", 0)), quality]
	if _cache.has(key): return _cache[key]
	var lake_q := {"hx": hx, "hz": hz, "margin": margin, "seed": int(lake.get("seed", 0))}
	var noises := _noise_set(int(lake_q.seed))
	var reach := margin + _wobble_bound(margin) + 60.0
	var half := Vector2(hx + reach, hz + reach)
	var side := SDF_SIDE if quality > 0 else SDF_SIDE * 2 / 3
	var texel := maxf(half.x, half.y) * 2.0 / float(side)
	var w := ceili(half.x * 2.0 / texel)
	var h := ceili(half.y * 2.0 / texel)
	var origin := -half
	var bound := _wobble_bound(margin)
	var heights := PackedFloat32Array()
	heights.resize(w * h)
	for j in h:
		for i in w:
			var x := origin.x + (float(i) + 0.5) * texel
			var z := origin.y + (float(j) + 0.5) * texel
			var away := _course_distance(x, z, lake_q) - margin # the shore field's own value is within the wobble's bound of this: far from the shore no noise is needed
			var height: float
			if away > bound + 40.0: height = 3.0 # dry land: the lake's own shore is always inside the window
			elif away < -bound - 16.0: height = -12.0 + _island_bump(x, z, lake_q, noises)
			else: height = _height(x, z, lake_q, noises)
			heights[j * w + i] = height
	var packed := PackedFloat32Array() # R: the height over the slime (clamped to +-16 m), G: how steep it is (m/m): the shader makes the distance as height / slope AFTER the bilinear filter, so the waterline is the exact contour of a smooth height field (a stored distance would step it)
	packed.resize(w * h * 2)
	for j in h:
		for i in w:
			var here := clampf(heights[j * w + i], -16.0, 16.0)
			var slope := 0.02
			if i > 0 and j > 0 and i < w - 1 and j < h - 1:
				slope = maxf(Vector2(heights[j * w + i + 1] - heights[j * w + i - 1], heights[(j + 1) * w + i] - heights[(j - 1) * w + i]).length() / (2.0 * texel), 0.02)
			else: here = 16.0 # the border is always dry (the window is wider than the lake)
			packed[(j * w + i) * 2] = here
			packed[(j * w + i) * 2 + 1] = slope
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGF, packed.to_byte_array())
	image.convert(Image.FORMAT_RGH)
	var result := {"texture": ImageTexture.create_from_image(image), "origin": origin, "size": Vector2(float(w), float(h)) * texel}
	_cache[key] = result
	return result

## The sea: one flat quad over the lake's window (the shore field says where the slime ends: the fragment shader cuts the quad at the shore), not a disc of rows of vertices.
static func _sea_mesh(field: Dictionary) -> ArrayMesh:
	var origin: Vector2 = field.origin
	var size: Vector2 = field.size
	var key := "sea:%d:%d:%d:%d" % [int(origin.x), int(origin.y), int(size.x), int(size.y)]
	if _cache.has(key): return _cache[key]
	var v := PackedVector3Array([Vector3(origin.x, 0.0, origin.y), Vector3(origin.x + size.x, 0.0, origin.y), Vector3(origin.x + size.x, 0.0, origin.y + size.y), Vector3(origin.x, 0.0, origin.y + size.y)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2]) # facing up
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = _counted(mesh, 2)
	return _cache[key]

## The shader inputs of the shore field (shared by the sea's and the terrain's shaders).
static func _shore_uniforms(field: Dictionary) -> Dictionary:
	return {"shore_tex": field.texture, "shore_origin": field.origin, "shore_size": field.size, "foam_width": SHORE_FOAM}

static func _sea(look: Dictionary, s: float, field: Dictionary, lake: Dictionary) -> MeshInstance3D:
	var own := {"course_half": Vector2(float(lake.hx), float(lake.hz)), "course_r": float(lake.get("radius", 0.0)), "base": _uniform(SEA_BASE), "light": _uniform(SEA_EDGE), "deep": _uniform(SEA_DEEP), "sky_tint": _uniform(SEA_SKY), "foam": _uniform(Color.WHITE), "crest_col": _uniform(Color("#ffd3e8")), "world_scale": s}
	own.merge(_shore_uniforms(field))
	var material := _material(SEA, look, own, ["sun_dir", "fog_color", "fog_density"])
	return _instance("Sea", _sea_mesh(field), material)
