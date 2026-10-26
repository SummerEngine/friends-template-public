extends SceneTree
## Headless check of the daylight world of a race level (`"world": "daylight"`, style/race_world.gd, levels/level_world.gd, levels/level_environment.gd) and that the stage rounds
## (levels 25-28) keep their own. Builds the real level world as a client on tools/level_testdata/daylight (level 1 an ordinary level, level 2 a long L-shaped one and level 3 a long thin straight one, both with `world: daylight`)
## and on the real levels, switches back and forth and reads the light and the world back. Prints GW_RACEWORLD lines; exit 1 on a failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer 0.7.3> --headless --audio-driver Dummy --path demo -s $PWD/tools/race_world_check.gd
const LevelWorld := preload("res://levels/level_world.gd")
const Data := preload("res://levels/level_data.gd")
const RaceWorld := preload("res://style/race_world.gd")
const CandyLight := preload("res://style/candy_light.gd")
const CandyWorld := preload("res://style/candy_world.gd")
const RaceSurfaces := preload("res://style/race_surfaces.gd")
const ArenaWorld := preload("res://style/arena_world.gd")

var fails := 0
var checks := 0

func _initialize() -> void:
	create_timer(110.0).timeout.connect(func() -> void:
		print("GW_RACEWORLD FAILED timed out")
		quit(1))
	run.call_deferred()

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("GW_RACEWORLD   FAIL ", text)

func build_world(dir: String) -> Node3D:
	var world: Node3D = LevelWorld.new()
	world.level_dir = dir
	root.add_child(world)
	await world.build("local")
	return world

## The name of the world node in the tree of `world` (ArenaWorld.., RaceWorld.., Party.., Room.., Backdrop.., Night..), "" for none.
func backdrop_name(world: Node3D) -> String:
	for child in world.get_children():
		var named := str(child.name)
		if named.begins_with("ArenaWorld") or named.begins_with("RaceWorld") or named.begins_with("Party") or named.begins_with("Room") or named.begins_with("Backdrop") or named.begins_with("Night"): return named
	return ""

func sun_state(world: Node3D) -> Array:
	var sun: DirectionalLight3D = world._light.sun
	return [sun.light_energy, sun.light_color, sun.shadow_bias, sun.directional_shadow_max_distance, sun.light_angular_distance, sun.global_basis]

func is_daylight(world: Node3D) -> bool:
	var light: Dictionary = world._light
	return light.holder.environment == light.get("stage_environment") and light.holder.environment != light.environment

func has_collider(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D: return true
	for child in node.get_children():
		if has_collider(child): return true
	return false

func run() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../tools/level_testdata/daylight").simplify_path()
	# ---- the data: the key is read, only "daylight" ----
	var plain := Data.parse({"modes": ["show"], "show": "race"}, 1)
	expect(str(plain.world) == "" and not RaceWorld.wanted(plain), "a level without `world` has none")
	expect(Data.parse({"world": "daylight"}, 1).world == "daylight" and RaceWorld.wanted(Data.parse({"world": "daylight"}, 1)), "world daylight is read")
	expect(Data.parse({"world": "night"}, 1).world == "", "any other world is ignored")
	# ---- block tones: parsed (only the six), keys by tone and role ----
	expect(Data.parse({"blocks": [{"k": "box", "p": [0, 0, 0], "s": [1, 1, 1], "tone": "door"}, {"k": "box", "p": [0, 0, 0], "s": [1, 1, 1], "tone": "pink"}, {"k": "box", "p": [0, 0, 0], "s": [1, 1, 1]}]}, 1).blocks.map(func(b: Dictionary) -> String: return b.tone) == ["door", "", ""], "a block's tone is read, an unknown one is ignored")
	expect(RaceSurfaces.keys("", 0)[0] == "race:teal:top" and RaceSurfaces.keys("", 2)[1] == "race:teal:side", "no tone: a floor is teal")
	expect(RaceSurfaces.keys("", 1)[0] == "race:navy:top", "no tone: a wall is navy")
	expect(RaceSurfaces.keys("door", 0)[2] == "race:door:end" and RaceSurfaces.keys("crate", 1)[0] == "race:crate:top", "a tone beats the role")
	for tone in RaceSurfaces.TONES:
		for key: String in RaceSurfaces.keys(tone, 0): expect(RaceSurfaces.material(key).shader != null, "tone %s: material %s" % [tone, key])
	# ---- the footprint of the test level ----
	var level := Data.load_level(2, dir)
	expect(not level.is_empty() and level.world == "daylight", "test level 2 loads with world daylight (%s)" % dir)
	var frame := RaceWorld.footprint(level)
	var rect: Rect2 = frame.rect
	for point: Vector3 in level.path: expect(rect.has_point(Vector2(point.x, point.z)), "path point %s in the footprint" % point)
	for block: Dictionary in level.blocks:
		var p: Vector3 = (block.xf as Transform3D).origin
		expect(rect.has_point(Vector2(p.x, p.z)), "block at %s in the footprint" % p)
	expect(rect.has_point(Vector2(8.0 + 14.0, -10.0)), "the ferry's far end (x 22) is in the footprint")
	expect(rect.has_point(Vector2(-15.0 - 5.0, -45.0)) and rect.has_point(Vector2(-15.0 + 5.0, -45.0)), "the spinning bar's sweep is in the footprint")
	expect(is_equal_approx(frame.y_top, 6.0) and is_equal_approx(frame.y_low, 0.0), "y_top %s (6), y_low %s (0)" % [frame.y_top, frame.y_low])
	# ---- the daylight and the world of the test level, switching back and forth ----
	var world := await build_world(dir)
	expect(world.level_count() == 3, "three test levels built (%d)" % world.level_count())
	world.set_active_level(0)
	expect(not is_daylight(world), "level 1 (ordinary): the usual light")
	var plain_blocks := world.get_node("Level01/LevelLook") as MeshInstance3D
	var plain_used := {}
	for surface in plain_blocks.mesh.get_surface_count(): plain_used[(plain_blocks.mesh.surface_get_material(surface) as ShaderMaterial).shader.resource_path.get_file()] = true
	expect(not plain_used.has("candy_surface.gdshader"), "level 1 (ordinary): none of its blocks wears a race surface (%s)" % [plain_used.keys()])
	expect(not backdrop_name(world).begins_with("RaceWorld") and not backdrop_name(world).begins_with("ArenaWorld"), "level 1: no race world (%s)" % backdrop_name(world))
	var usual := sun_state(world)
	world.set_active_level(1)
	expect(is_daylight(world), "level 2 (world daylight): the daylight is on")
	var day := sun_state(world)
	expect(not is_equal_approx(float(day[0]), float(usual[0])) or day[1] != usual[1], "level 2: the sun changed (%s -> %s)" % [usual[0], day[0]])
	expect(is_equal_approx(float(day[0]), CandyLight.sun_energy()), "level 2: the stage rounds' sun energy")
	expect(backdrop_name(world) == "RaceWorld02", "level 2: the race world is in the tree (%s)" % backdrop_name(world))
	expect(world._void == null or not world._void.visible, "level 2: the flat void plane is hidden")
	var blocks := world.get_node("Level02/LevelLook") as MeshInstance3D # the merged mesh of the level's blocks: the tones of its blocks are surfaces of it
	var used := {}
	for surface in blocks.mesh.get_surface_count():
		var material := blocks.mesh.surface_get_material(surface) as ShaderMaterial
		used[material.shader.resource_path.get_file() if material != null else "none"] = true
	expect(used.has("candy_surface.gdshader") and not used.has("surface.gdshader"), "level 2: its blocks wear the race surfaces only (%s)" % [used.keys()])
	var vinyl := false
	var plastic := false
	var striped := false
	for surface in blocks.mesh.get_surface_count():
		var material := blocks.mesh.surface_get_material(surface) as ShaderMaterial
		if material == null: continue
		var rough: Variant = material.get_shader_parameter("roughness")
		if material.get_shader_parameter("use_vertex_color") == true and rough != null:
			vinyl = vinyl or is_equal_approx(float(rough), RaceSurfaces.VINYL_ROUGH)
		if rough != null: plastic = plastic or is_equal_approx(float(rough), 0.11)
		striped = striped or material.get_shader_parameter("pattern") == 2
	expect(vinyl and plastic and striped and blocks.mesh.get_surface_count() >= 6, "level 2: the candy kit's surfaces (vinyl slabs and pillows %s, hard plastic parts %s, striped doors %s; %d surfaces)" % [vinyl, plastic, striped, blocks.mesh.get_surface_count()])
	var race: Node3D = world.get_node_or_null("RaceWorld02")
	if race != null:
		expect(race.get_node_or_null("CandyWorld/Diorama/Sea") != null and race.get_node_or_null("CandyWorld/Diorama/Terrain") != null, "the race world is the candy world: a sea and a terrain")
		expect(race.find_child("Rail", true, false) == null and race.find_child("City", true, false) == null and race.find_child("SkyThings", true, false) == null, "the race world has no rail ring, no city, no balloons")
		expect(not has_collider(race), "the race world has no collider and no collision shape")
		check_world(race, level, world.level_origin(1))
	for round in 2:
		world.set_active_level(0)
		expect(not is_daylight(world), "back on level 1: the usual light (round %d)" % round)
		var again := sun_state(world)
		for k in usual.size(): expect(again[k] == usual[k], "back on level 1: sun property %d restored (%s, was %s)" % [k, again[k], usual[k]])
		world.set_active_level(1)
		expect(is_daylight(world), "on level 2 again: the daylight (round %d)" % round)
		var day_again := sun_state(world)
		for k in day.size(): expect(day_again[k] == day[k], "on level 2 again: sun property %d is the daylight's (%s, was %s)" % [k, day_again[k], day[k]])
		expect(backdrop_name(world) == "RaceWorld02", "level 2 again: the race world, not another (%s)" % backdrop_name(world))
	# the long thin corridor (level 3): the world's hole must be wider than it
	var corridor := Data.load_level(3, dir)
	world.set_active_level(2)
	expect(is_daylight(world) and backdrop_name(world) == "RaceWorld03", "level 3 (a long thin corridor): the daylight and its race world (%s)" % backdrop_name(world))
	var corridor_world: Node3D = world.get_node_or_null("RaceWorld03")
	if corridor_world != null: check_world(corridor_world, corridor, world.level_origin(2))
	world.set_active_level(0)
	expect(not is_daylight(world), "back on level 1 after the corridor: the usual light")
	world.queue_free()
	await process_frame
	# ---- the real levels: stage rounds keep their own world, 29 and 30 (if there) get the race world ----
	var real := await build_world("res://levels")
	var stages := 0
	var days := 0
	for k in real.level_count():
		var data: Dictionary = real._levels[k].data
		real.set_active_level(k)
		var staged := not (data.stage as Dictionary).is_empty()
		var named := backdrop_name(real)
		if staged:
			stages += 1
			expect(is_daylight(real), "level %d (stage round): the daylight" % data.number)
			expect(named == "ArenaWorld%02d" % int(data.number), "level %d (stage round): its arena world (%s)" % [data.number, named])
			check_arena(real.get_node_or_null(named), data)
		elif RaceWorld.wanted(data):
			days += 1
			expect(is_daylight(real), "level %d (world daylight): the daylight" % data.number)
			expect(named == "RaceWorld%02d" % int(data.number), "level %d (world daylight): its race world (%s)" % [data.number, named])
			var daylight_world := real.get_node_or_null(named)
			if daylight_world != null: check_world(daylight_world, data, real.level_origin(k))
		else:
			expect(not is_daylight(real), "level %d (ordinary): the usual light" % data.number)
			expect(not named.begins_with("ArenaWorld") and not named.begins_with("RaceWorld"), "level %d (ordinary): no arena or race world (%s)" % [data.number, named])
	expect(stages >= 4, "the stage rounds 25-28 are there (%d)" % stages)
	real.set_active_level(0)
	expect(not is_daylight(real), "level 1 after the real levels: the usual light")
	real.queue_free()
	await process_frame
	print("GW_RACEWORLD %s: %d checks, %d failures (%d stage rounds, %d daylight race levels among the real levels)" % ["OK" if fails == 0 else "FAILED", checks, fails, stages, days])
	quit(1 if fails > 0 else 0)

## The race world's sea lies where the level kills (`void_y` less a courier's centre height), is centred on the level, and the land comes no nearer than 14 m to the course's rectangle.
func check_world(race: Node3D, level: Dictionary, origin: Vector3) -> void:
	var frame := RaceWorld.footprint(level)
	var rect: Rect2 = frame.rect
	var candy := race.get_node("CandyWorld") as Node3D
	var diorama := candy.get_node("Diorama") as Node3D
	var scale_factor := diorama.scale.x
	expect(is_equal_approx(diorama.global_position.y, origin.y + RaceWorld.sea_y(level)) and RaceWorld.CENTRE_HEIGHT == LevelWorld.CENTRE_HEIGHT, "the sea lies at void_y less the courier's centre height (%s)" % diorama.global_position.y)
	expect(absf(diorama.global_position.x - (origin.x + rect.get_center().x)) < 0.01 and absf(diorama.global_position.z - (origin.z + rect.get_center().y)) < 0.01, "the world is centred on this level, not on the world")
	expect(absf(race.global_position.x - origin.x) < 0.01, "the race world stands at the level's origin")
	var lake := CandyWorld.lake_of({"course_rect": rect}, scale_factor)
	var gap := float(lake.margin) * (1.0 - CandyWorld.SHORE_WOBBLE * 1.4) * scale_factor # the nearest the land comes to the course's rectangle, real metres
	expect(gap >= 14.0, "level %d: the land stays %.0f m (14 wanted) off the course's rectangle (lake margin %.0f m)" % [int(level.get("number", 0)), gap, CandyWorld.LAKE_MARGIN])
	expect(absf(candy.global_position.x - (origin.x + rect.get_center().x)) < 0.01, "the candy world stands on the middle of the course's rectangle")
	var stats := CandyWorld.stats(candy)
	print("GW_RACEWORLD level %d footprint %s, shore %.0f m off, %d draw calls, %d triangles, built in %.1f ms" % [int(level.get("number", 0)), rect, gap, stats.draws, stats.triangles, float(candy.get_meta("build_ms"))])

## A stage round's world: the candy world and its sea, NO rail ring and NO walls (decor without collision is a fake barrier: you can fall off the tiles), decor only.
func check_arena(arena: Node3D, data: Dictionary) -> void:
	if arena == null: return
	expect(arena.find_child("Rail", true, false) == null and arena.find_child("StageWalls", true, false) == null, "level %d: no rail ring and no walls round the tiles" % int(data.number))
	expect(arena.get_node_or_null("CandyWorld/Diorama/Sea") != null, "level %d: the candy world's sea" % int(data.number))
	expect(not has_collider(arena), "level %d: the arena world has no collider" % int(data.number))
	var ring: Dictionary = ArenaWorld.ring_of(data.tiles)
	for k in (ring.offsets as PackedFloat32Array).size(): expect(float(ring.offsets[k]) - float(ring.apothems[k]) >= ArenaWorld.RIM_GAP - 0.001, "level %d: side %d of the lake ring stands RIM_GAP outside the tiles" % [int(data.number), k])
	var stats := CandyWorld.stats(arena)
	print("GW_RACEWORLD level %d (stage round): %d draw calls, %d triangles" % [int(data.number), stats.draws, stats.triangles])
