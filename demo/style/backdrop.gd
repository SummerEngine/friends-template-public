extends RefCounted
## The comic backdrop around a level or the lobby yard: far below the course a world seen from above (a city, a building site, a park, a sea of
## clouds), on the horizon three hazy layers of skyline, range or cloud towers, floating islands, cranes, billboards, and slow ambient motion
## (drifting clouds, a blimp, a flock of birds). Decor only: no collision, no shadows, no lights; the course stays the only warm, saturated thing.
## Client only. Everything is one ground quad plus a handful of MultiMeshes (box, pyramid, cone, cylinder, sphere, birds), each with an ink
## outline as next_pass; drifting is done in the vertex shader. A few draw calls and under 3000 instances, whatever the level.
## Rules for placement are in backdrop_scatter.gd, the colours and the theme per level in backdrop_themes.gd. Docs: docs/backdrop.md.
## The team cast picks the world (office / outdoor, TeamCast.world_theme()); a stage round (`stage` in the level file) has the fixed arena world of style/arena_world.gd instead.
const Style := preload("res://style/friends_style.gd")
const Themes := preload("res://style/backdrop_themes.gd")
const Meshes := preload("res://style/backdrop_meshes.gd")
const Scatter := preload("res://style/backdrop_scatter.gd")
const TeamCast := preload("res://style/team_cast.gd")
const RoomShell := preload("res://style/room_shell.gd")
const Party := preload("res://style/party_look.gd")
const PartyBackdrop := preload("res://style/party_backdrop.gd")
const NightBackdrop := preload("res://style/night_backdrop.gd")
const Surfaces := preload("res://style/surfaces.gd")
const ArenaWorld := preload("res://style/arena_world.gd")
const FILL := "res://style/backdrop.gdshader"
const OUTLINE := "res://style/backdrop_outline.gdshader"
const GROUND := "res://style/backdrop_ground.gdshader"
const GROUND_KIND := {Themes.CITY: 0, Themes.YARD: 0, Themes.PARK: 1, Themes.CLOUD: 3}
const SUN_TOWARDS := Vector3(0.5, 0.75, 0.35)
const REACH := 6000.0
## The lobby yard's box (network/walk_in_lobby.gd: 34.6 m wide, 24 m deep, with a metre of margin) the decor around it keeps clear of.
const LOBBY_BOX := Rect2(-18.3, -15.0, 36.6, 26.5)
## Switch for the tools that compare before and after (tools/backdrop_shots.gd); the game always has it on.
static var enabled := true

## The backdrop of level `number` (1-based) from its parsed data (levels/level_data.gd), standing at `origin` (the level's world origin).
static func for_level(number: int, data: Dictionary, origin: Vector3) -> Node3D:
	if not (data.get("stage", {}) as Dictionary).is_empty(): return ArenaWorld.build(data, origin) # a stage round: its own world and light, whatever the cast's world style is
	if Party.on() and not Surfaces.ink(): # the show: open air in the cast's colours, or the night world (cast world.style)
		return (NightBackdrop if Party.night() else PartyBackdrop).build(level_spec(data), origin, "Party%02d" % number, data)
	if not Surfaces.ink(): return RoomShell.build(level_spec(data), origin, "Room%02d" % number)
	var plan := Themes.plan(number, TeamCast.world_theme())
	var spec := level_spec(data)
	spec.kind = plan.kind
	spec.time = plan.time
	spec.seed = Themes.seed_of(number, plan.kind)
	return _assemble(spec, origin, "Backdrop%02d" % number)

## The backdrop of the lobby yard, standing at `origin` (the yard's origin).
static func for_lobby(origin: Vector3) -> Node3D:
	if Party.on() and not Surfaces.ink():
		return (NightBackdrop if Party.night() else PartyBackdrop).build({"bbox": LOBBY_BOX, "y_low": -0.65, "y_high": 3.4, "forward": Vector2(0.0, -1.0),
			"supports": [{"p": Vector3(0.0, -0.65, -1.75), "size": LOBBY_BOX.size}]}, origin, "PartyLobby")
	if not Surfaces.ink(): return RoomShell.build({"bbox": LOBBY_BOX, "y_low": -0.65, "y_high": 3.4, "depth": 0.0, "forward": Vector2(0.0, -1.0)}, origin, "LobbyRoom")
	var kind := Themes.themed(Themes.CITY, TeamCast.world_theme())
	var spec := {"kind": kind, "time": Themes.DAY, "seed": Themes.seed_of(0, kind), "bbox": LOBBY_BOX,
		"y_low": -0.65, "y_high": 3.4, "forward": Vector2(0.0, -1.0)}
	return _assemble(spec, origin, "LobbyBackdrop")

## The sky and fog of the level's hour (day, dusk, night); `environment` is the level world's Environment.
static func apply_sky(environment: Environment, number: int) -> void:
	if not Surfaces.ink(): return
	if environment == null or environment.sky == null: return
	var look: Dictionary = Themes.TIMES[Themes.plan(number).time]
	var sky_material := environment.sky.sky_material as ShaderMaterial
	if sky_material != null:
		sky_material.set_shader_parameter("paper", look.paper)
		sky_material.set_shader_parameter("tint", look.tint)
		sky_material.set_shader_parameter("ink", look.ink)
		sky_material.set_shader_parameter("sun_color", look.sun)
	environment.fog_light_color = look.paper
	environment.fog_density = look.fog

## What the backdrop needs to know of a level: the box its course covers on x/z (blocks, movers and their reach, shots, start, goal), the lowest
## and highest walkable heights, and the bearing from the start to the goal.
static func level_spec(data: Dictionary) -> Dictionary:
	var box := {"lo": Vector2(INF, INF), "hi": Vector2(-INF, -INF), "low": 0.0, "high": 0.0}
	for block: Dictionary in data.blocks:
		var xf: Transform3D = block.xf
		var half: Vector3 = (block.size as Vector3) * 0.5
		for corner in 8:
			_extend(box, xf * Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y, half.z if corner & 4 else -half.z), 0.0)
	for h: Dictionary in data.hazards:
		var reach := 1.0
		for part: Dictionary in h.parts: reach = maxf(reach, (part.xf as Transform3D).origin.length() + (part.size as Vector3).length() * 0.5)
		var pivot: Vector3 = h.pivot
		_extend(box, pivot, reach)
		if h.has("to"): _extend(box, pivot + (h.to as Vector3), reach)
		if h.k == "ball":
			for point: Vector3 in h.path: _extend(box, point, float(h.rad))
		if h.k == "cannon":
			var v: Vector3 = h.v
			_extend(box, pivot + Vector3(v.x, 0.0, v.z) * float(h.life), float(h.rad))
	for point: Vector3 in data.path: _extend(box, point, 0.0)
	if not (data.tiles as Dictionary).is_empty(): # step tiles: their faces and the underside of the lowest floor
		var reach := float(data.tiles.pitch) / sqrt(3.0) # the hexagon's circumradius
		for tile: Dictionary in data.tiles.tiles:
			_extend(box, tile.p - Vector3(0.0, float(data.tiles.thick), 0.0), reach)
			_extend(box, tile.p, reach)
	_extend(box, data.start, 2.0)
	_extend(box, data.goal.p, (data.goal.size as Vector3).length() * 0.5)
	var from := Vector2((data.start as Vector3).x, (data.start as Vector3).z)
	var to := Vector2((data.goal.p as Vector3).x, (data.goal.p as Vector3).z)
	var forward := (to - from).normalized() if from.distance_to(to) > 1.0 else Vector2(0.0, -1.0)
	var lo: Vector2 = box.lo
	var hi: Vector2 = box.hi
	return {"bbox": Rect2(lo, hi - lo), "y_low": box.low, "y_high": box.high, "forward": forward}

static func _extend(box: Dictionary, point: Vector3, reach: float) -> void:
	var lo: Vector2 = box.lo
	var hi: Vector2 = box.hi
	box.lo = Vector2(minf(lo.x, point.x - reach), minf(lo.y, point.z - reach))
	box.hi = Vector2(maxf(hi.x, point.x + reach), maxf(hi.y, point.z + reach))
	box.low = minf(float(box.low), point.y - reach)
	box.high = maxf(float(box.high), point.y + reach)

static func _assemble(spec: Dictionary, origin: Vector3, label: String) -> Node3D:
	spec.density = [0.55, 0.8, 1.0][clampi(Style.quality(), 0, 2)]
	var look: Dictionary = Themes.TIMES[spec.time]
	var scatter := Scatter.new(spec)
	var batches := scatter.build()
	var root := Node3D.new()
	root.name = label
	root.position = origin
	var shared := {"haze": look.paper, "centre": origin, "drift_axis": scatter.lane_axis(), "wrap_length": Scatter.WRAP}
	var ink: Color = look.ink if spec.time != Themes.NIGHT else Color("#0f1030")
	var fill := Style.shader_material(FILL, shared)
	fill.set_shader_parameter("light_dir", SUN_TOWARDS)
	fill.set_shader_parameter("lit_share", float(look.lit))
	fill.set_shader_parameter("ink", ink)
	var line := Style.shader_material(OUTLINE, shared)
	line.set_shader_parameter("ink_color", ink)
	fill.next_pass = line
	var birds := Style.shader_material(FILL, shared)
	birds.set_shader_parameter("light_dir", SUN_TOWARDS)
	for shape: String in batches:
		var batch: Scatter.Batch = batches[shape]
		if batch.count == 0: continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = Meshes.get_mesh(shape)
		multi.instance_count = batch.count
		multi.buffer = batch.data
		multi.custom_aabb = AABB(Vector3(-REACH * 0.5, -REACH * 0.25, -REACH * 0.5), Vector3(REACH, REACH * 0.5, REACH))
		var node := MultiMeshInstance3D.new()
		node.name = shape.capitalize()
		node.multimesh = multi
		node.material_override = birds if shape == "bird" else fill
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	root.add_child(_ground(spec, scatter, look, shared, origin))
	return root

static func _ground(spec: Dictionary, scatter: Scatter, look: Dictionary, shared: Dictionary, origin: Vector3) -> MeshInstance3D:
	var kind: String = spec.kind
	var plane := PlaneMesh.new()
	plane.size = Vector2(REACH, REACH)
	var material := Style.shader_material(GROUND, shared)
	material.set_shader_parameter("kind", int(GROUND_KIND[kind]))
	material.set_shader_parameter("origin", Vector2(origin.x, origin.z))
	material.set_shader_parameter("seed", float(int(spec.seed) % 977) * 0.001 + 1.0)
	material.set_shader_parameter("cell", 60.0 if kind == Themes.YARD else 44.0)
	material.set_shader_parameter("road", 14.0 if kind == Themes.YARD else 10.0)
	var colors: Array[Color] = _ground_colors(kind)
	for i in 6:
		material.set_shader_parameter("c%d" % i, _toned_srgb(colors[i], look))
	material.set_shader_parameter("line_color", Color("#1b1d3a") if spec.time != Themes.NIGHT else Color("#0f1030"))
	var node := MeshInstance3D.new()
	node.name = "Ground"
	node.mesh = plane
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = Vector3(0.0, scatter.ground_y, 0.0)
	node.extra_cull_margin = REACH
	return node

static func _ground_colors(kind: String) -> Array[Color]:
	match kind:
		Themes.CITY: return Themes.CITY_GROUND
		Themes.YARD: return Themes.YARD_GROUND
		Themes.PARK: return Themes.PARK_GROUND
		_: return Themes.CLOUD_GROUND

## A ground colour at the hour, as sRGB (the shader's `source_color` uniforms convert it).
static func _toned_srgb(color: Color, look: Dictionary) -> Color:
	var result := color.lerp(look.warm as Color, float(look.warm_amount)) * float(look.shade)
	result.a = 1.0
	return result
