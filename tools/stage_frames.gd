extends SceneTree
## Frames of a stage round (levels 25-28: the falling-tile rounds) with a hand-placed camera: the real LevelWorld with the real character rig, tile steps (a white trail behind a
## runner, holes that show the layers below) and named framings (`make_shots`: start, phone, pads, trail, rim, layers, deep (hexagons), ground, over, rear, down, below, all derived from the arena size), so the world around the tiles (style/arena_world.gd: rail ring, candy world, sky) and its light can be checked
## in pictures. Offscreen binary only, never windowed, about 15 s per run (ONE render at a time machine-wide, see tools/modes/show_frames.gd):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1152x720 --path demo -s "$PWD/tools/stage_frames.gd" -- --level=25 --shots=<dir> [--prefix=a_] [--only=start,trail] [--orbit=12] [--startz=<m>] [--strip=<n>]
## --level=<file number> (default 25); --only=<names>; --orbit=<n>: n frames of a camera orbit around the arena (names orbit_00 ...; --arc=<degrees> of it, default 360) instead of the named shots, to look for flicker;
## --strip=<n>: n frames at 30 fps of the start courier's own tile going white (frame 2), sinking and going 15 frames later (motion strip). --startz=<m> moves the start/phone/pads framings to a start pad at that z (what-if for the pad block). --stats prints the draw calls and triangles of every shot; --hook only checks the light and backdrop switch (and times building the world) (level 1, then the stage level, then level 1 again). Positions are level-local (the arena is centred on x 0, z 0, the top layer's top is at y 0; +Z is the start
## view's forward). A shot: eye, look-at, vertical FOV, level clock, characters [[feet, yaw degrees (0 = towards -Z, 180 = towards +Z)]], tile steps: "trail" [[from, to, step clock at from, m/s]] (a runner's
## footsteps, 0.25 m apart), "clear" [[layer, box half-width m or -1 for all, step clock]] (a whole layer gone from a step clock on), "keep" [[layer, x, z, radius]] (tiles to leave in a "clear").
## Prints STAGE_FRAMES lines, and for every picture the mean luma (Rec.709 on the 8-bit values, 0-255) and mean HSV saturation.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const ArenaWorld := preload("res://style/arena_world.gd")
const CandyWorld := preload("res://style/candy_world.gd")

const REFERENCE_FOV := 65.0      ## the stage view's vertical FOV (follow_camera.gd STAGE_FOV)
const CHASE := 12.1              ## m, the stage camera's orbit radius: the 3D distance from the camera to the courier's feet (follow_camera.gd STAGE_ARM)
const FEET_Y := 0.704            ## where the courier's feet stand in the frame's height, whatever the pitch (follow_camera.gd STAGE_FEET_Y)
const STRIP_FPS := 30.0          ## the strip's frame rate
const STRIP_STEP := 2            ## the strip's frame at which the tile is stepped (white)
const STRIP_T0 := 5.0            ## the level clock of that step
const RUN_SPEED := 12.6          ## m/s, a courier's run (3.6 E/s)

## The framings of the level whose arena is `info` ({half: m from the middle to a tile's rim (the flat-to-flat half width for hexagons), starts: the pad centres, tops: the layers' tops,
## ground: the ground slab's top, corner: the ring's far left corner}) as name -> {eye, look or pitch (a chase camera looks towards +Z: the pads and the rail lie that way), fov,
## clock, who [[feet, yaw degrees]], trail, clear, keep, size (optional Vector2i), ghost (optional)}. Every framing is derived from the arena's own numbers so it lands the same way on
## a 77 m square and a 105 m hexagon.
static func make_shots(info: Dictionary) -> Dictionary:
	var half: float = info.half
	var starts: Array = info.starts
	var tops: PackedFloat32Array = info.tops
	var ground: float = info.ground
	var middle: Vector3 = starts[0]
	if info.has("start_z"): middle.z = float(info.start_z) # a what-if: the start camera for a pad block nearer the near rim
	var shots := {}
	var crowd: Array = []
	for at: Vector3 in starts: crowd.append([at, 180.0])
	# the start view: behind the courier on the middle pad, the pads and the rail ahead (chase camera, pitch 12.4 degrees)
	shots["start"] = {"eye": chase(middle, 12.4), "pitch": -12.4, "fov": REFERENCE_FOV, "clock": 1.0, "who": crowd}
	# the sky: the start camera tipped so the horizon is mid-frame (the meadow and mountains fading into the haze, clouds above) and tipped up 30 degrees (clouds and the zenith blue)
	shots["sky_horizon"] = {"eye": chase(middle, 12.4), "pitch": 2.0, "fov": REFERENCE_FOV, "clock": 1.0, "who": crowd}
	shots["sky_up"] = {"eye": chase(middle, 12.4), "pitch": 30.0, "fov": REFERENCE_FOV, "clock": 1.0, "who": crowd}
	# the start view as a phone shows it: 844 x 390
	shots["phone"] = {"eye": chase(middle, 12.4), "pitch": -12.4, "fov": 52.0, "clock": 1.0, "size": Vector2i(844, 390), "who": crowd}
	# the pads from above and behind: the flower of seven hexes / the nine-tile squares
	shots["pads"] = {"eye": middle + Vector3(0.0, 17.0, -22.0), "look": middle + Vector3(0.0, 0.0, 3.0), "fov": 55.0, "clock": 1.0, "who": crowd}
	# the start layer straight from above: the 12 groups (3 x 3 squares, flowers of 7 hexagons), evenly spaced
	var centre_xz := Vector3.ZERO
	for at: Vector3 in starts: centre_xz += at / starts.size()
	shots["pads_top"] = {"eye": Vector3(centre_xz.x, starts[0].y + 62.0, centre_xz.z - 0.01), "look": Vector3(centre_xz.x, starts[0].y, centre_xz.z), "fov": 55.0, "clock": 1.0, "who": crowd, "ghost": false}
	# mid round: a runner with a white trail behind it (the last half second of its steps), holes further back, the camera over its shoulder, pitch 18 degrees
	var lead := 22.0
	var runner := Vector3(4.0, 0.05, -half * 0.15)
	var raised: Array = info.get("raised", [])
	for column: float in [4.0, half * 0.62, -half * 0.62, half * 0.8, -half * 0.8]: # a column of plain tiles: the trail tiles are the ones at the floor, not the raised pads
		var plain := true
		for at: Vector2 in raised:
			if absf(at.x - column) < 4.5 and at.y > runner.z - lead - 2.0 and at.y < runner.z + 8.0: plain = false
		if plain:
			runner.x = column
			break
	shots["trail"] = {"eye": chase(runner, 18.0), "pitch": -18.0, "fov": REFERENCE_FOV, "clock": 9.0, "who": [[runner, 180.0], [runner + Vector3(-9.0, 0.0, 14.0), 180.0], [runner + Vector3(11.0, 0.0, 22.0), 180.0]],
		"trail": [[runner + Vector3(0.0, -0.05, -lead), runner + Vector3(0.0, -0.05, 0.0), 9.0 - lead / RUN_SPEED, RUN_SPEED]]}
	# running along the rim: the rail ring right beside the camera
	var rim_runner := Vector3(half - 5.0, 0.05, -half * 0.3)
	shots["rim"] = {"eye": chase(rim_runner, 16.0), "pitch": -16.0, "fov": REFERENCE_FOV, "clock": 17.0, "who": [[rim_runner, 180.0], [Vector3(half * 0.3, 0.05, half * 0.3), 180.0]],
		"trail": [[rim_runner + Vector3(0.0, -0.05, -lead), rim_runner + Vector3(0.0, -0.05, 0.0), 17.0 - lead / RUN_SPEED, RUN_SPEED]]}
	# the chevron wall panels (style/stage_wall_look.gd) against the follow camera: a courier on the far rim facing out (the wall ahead), on the near rim facing in (the camera behind and outside the
	# ring, looking over the wall), the same at the second layer and with the flattest standing pitch: the camera must not end up in a panel, see only its back or lose the tiles ahead
	for wall_shot: Array in [["wall_far", half - 1.7, 0.0, -12.4], ["wall_near", -(half - 1.7), 0.0, -12.4], ["wall_near_flat", -(half - 1.7), 0.0, -5.0], ["wall_far_low", half - 1.7, 1.0, -12.4], ["wall_near_low", -(half - 1.7), 1.0, -12.4]]:
		var wall_at := Vector3(0.0, 0.05 + (float(tops[int(wall_shot[2])]) - float(tops[0])), float(wall_shot[1]))
		shots[wall_shot[0]] = {"eye": chase(wall_at, float(wall_shot[3])), "pitch": float(wall_shot[3]), "fov": REFERENCE_FOV, "clock": 1.0, "who": [[wall_at, 180.0]]}
	# a three-layer view: the runner on an island of the second layer, the first and second layers gone round it except islands, the third layer below them (the follow camera at its running pitch, 20 degrees)
	shots["layers"] = islands_shot(1, half, tops, lead)
	# a deep stack (hexagons: 8 layers): the runner on the last tile layer but one, the rail rings of the lower layers around it
	if tops.size() > 4: shots["deep"] = layers_shot(tops.size() - 2, half, tops, lead)
	# the courier that fell to the ground slab: every layer gone, the rail ring and the world seen from the bottom
	var clear_all: Array = []
	for k in tops.size() + 1: clear_all.append([k, -1.0, 27.0]) # every floor, the start layer (index 0) and the last full one included
	var bottom := Vector3(0.0, ground + 0.05, -half * 0.2)
	shots["ground"] = {"eye": chase(bottom, 14.0), "pitch": -14.0, "fov": REFERENCE_FOV, "clock": 30.0, "who": [[bottom, 180.0], [bottom + Vector3(-10.0, 0.0, 16.0), 180.0]], "clear": clear_all, "keep": [], "ghost": false}
	# high over and behind the near rim, looking at the whole plate, the rail ring and the world beyond (a fly-over frame): everything at once
	shots["over"] = {"eye": Vector3(0.0, 66.0, -half * 1.35), "look": Vector3(0.0, -6.0, half * 0.1), "fov": 62.0, "clock": 1.0, "who": crowd}
	# from inside the far rim looking back at the near edge: the rail along it and the posts at its ends
	shots["rear"] = {"eye": Vector3(0.0, 40.0, half * 0.35), "look": Vector3(0.0, -2.0, -half), "fov": 60.0, "clock": 1.0, "who": []}
	# straight down on the top layer: the light calibration (a lit flat tile against its tone, a shadowed one)
	shots["down"] = {"eye": Vector3(0.0, 80.0 + half, -0.5), "look": Vector3(0.0, 0.0, 0.0), "fov": 38.0, "clock": 1.0, "who": []}
	# from under the stack between its rim and the rail posts, looking up and across: the ground slab, the layers' undersides, the posts, the sea
	shots["below"] = {"eye": Vector3(half * 0.5, ground - 11.0, -(half + 4.5)), "look": Vector3(-half * 0.1, ground * 0.4, half * 0.2), "fov": 70.0, "clock": 1.0, "who": [], "ghost": false}
	shots.merge(fall_shots(info))
	return shots

## A fall through one layer gap in three frames (`--only=fall_0,fall_1,fall_2`): the courier standing on an island of the top layer, half way down (the follow camera trails a fall
## by at most STAGE_AIR_TRAIL = 4 m: its anchor is that far above), and landed on an island of the second layer. The layers round the islands are gone.
static func fall_shots(info: Dictionary) -> Dictionary:
	var tops: PackedFloat32Array = info.tops
	if tops.size() < 2: return {}
	var half: float = info.half
	var x := -half * 0.1
	var z := -half * 0.1
	var clear: Array = [[0, -1.0, 27.0], [1, -1.0, 27.0]]
	var keep: Array = [[0, x - 8.0, z - 3.0, 3.5], [1, x, z, 6.0], [1, x + 14.0, z + 12.0, 5.0], [1, x - 16.0, z + 6.0, 4.0], [0, x + 16.0, z + 10.0, 4.0], [0, x - 14.0, z + 16.0, 4.0]]
	var gap := tops[0] - tops[1]
	var shots := {}
	var stages := [[Vector3(x - 8.0, tops[0] + 0.05, z - 3.0), Vector3(x - 8.0, tops[0] + 0.05, z - 3.0)], [Vector3(x, tops[0] - gap * 0.5, z), Vector3(x, tops[0] - gap * 0.5 + 4.0, z)], [Vector3(x, tops[1] + 0.05, z), Vector3(x, tops[1] + 0.05, z)]]
	for k in 3:
		var feet: Vector3 = stages[k][0]
		var anchor: Vector3 = stages[k][1]
		shots["fall_%d" % k] = {"eye": chase(anchor, 14.0), "pitch": -14.0, "fov": REFERENCE_FOV, "clock": 30.0, "who": [[feet, 180.0]], "clear": clear, "keep": keep, "ghost": false}
		if k == 1: shots["fall_1"] = {"eye": feet + Vector3(0.0, 4.0, -17.0), "look": feet + Vector3(0.0, -4.0, 0.0), "fov": REFERENCE_FOV, "clock": 30.0, "who": [[feet, 180.0]], "clear": clear, "keep": keep, "ghost": false}
	return shots

## The three-layer view with the runner on layer `on`: every layer above it cleared except islands left and right of the runner's path, ahead of it, a little different on every layer.
static func layers_shot(on: int, half: float, tops: PackedFloat32Array, lead: float) -> Dictionary:
	var low := Vector3(-half * 0.1, tops[on] + 0.05, -half * 0.1)
	var clear: Array = []
	var keep: Array = []
	for k in on:
		clear.append([k, -1.0, 27.0])
		for j in 6:
			keep.append([k, low.x + (1.0 if j % 2 == 1 else -1.0) * (11.0 + 6.0 * (j / 2) + 3.0 * (k % 4)), low.z + 12.0 + 7.0 * (j / 2) + 5.0 * (k % 4), 4.0 + 0.6 * j])
	return {"eye": chase(low, 20.0), "pitch": -20.0, "fov": REFERENCE_FOV, "clock": 30.0, "who": [[low, 180.0], [low + Vector3(12.0, 0.0, 18.0), 180.0], [low + Vector3(-13.0, 0.0, 26.0), 180.0]],
		"trail": [[low + Vector3(0.0, -0.05, -lead), low + Vector3(0.0, -0.05, 0.0), 30.0 - lead / RUN_SPEED, RUN_SPEED]], "clear": clear, "keep": keep}

## The three-layer view: the runner stands on an island of layer `on`; layers 0 to `on` are gone but for islands (a few tiles across, near the runner and ahead of it), so the layer
## below shows round them and through them: three layers in one frame, with the camera at the follow camera's running pitch.
static func islands_shot(on: int, half: float, tops: PackedFloat32Array, lead: float) -> Dictionary:
	var low := Vector3(-half * 0.1, tops[on] + 0.05, -half * 0.1)
	var clear: Array = []
	var keep: Array = [[on, low.x, low.z, 5.5], [on, low.x + 9.0, low.z + 5.0, 4.0], [on, low.x - 10.0, low.z + 12.0, 4.5]]
	for k in on + 1:
		clear.append([k, -1.0, 27.0])
		for j in 5:
			keep.append([k, low.x + (1.0 if j % 2 == 1 else -1.0) * (7.0 + 5.0 * (j / 2) + 3.0 * (k % 3)), low.z + 9.0 + 6.0 * (j / 2) + 4.0 * (k % 3), 3.5 + 0.5 * j])
	return {"eye": chase(low, 20.0), "pitch": -20.0, "fov": REFERENCE_FOV, "clock": 30.0, "who": [[low, 180.0], [low + Vector3(9.0, 0.0, 5.0), 180.0], [low + Vector3(-10.0, 0.0, 12.0), 180.0]],
		"trail": [[low + Vector3(0.0, -0.05, -lead), low + Vector3(0.0, -0.05, 0.0), 30.0 - lead / RUN_SPEED, RUN_SPEED]], "clear": clear, "keep": keep, "ghost": false}

## The eye of the stage camera for a view axis pitched `pitch` degrees down, CHASE m (3D) from a courier standing at `feet`, behind it (the start view looks towards +Z): the follow camera's
## geometry (follow_camera.gd, stage view): the feet stand FEET_Y of the frame's height, so they are `below` degrees under the view axis, and the eye is on the line from the feet at the
## angle pitch + below over the horizon. The look direction of the shot is the pitch alone (the shots give "pitch": -p).
static func chase(feet: Vector3, pitch: float) -> Vector3:
	var below := atan((2.0 * FEET_Y - 1.0) * tan(deg_to_rad(REFERENCE_FOV) * 0.5))
	var angle := deg_to_rad(pitch) + below
	return feet + Vector3(0.0, CHASE * sin(angle), -CHASE * cos(angle))

var shots := ""
var prefix := ""
var level_number := 25
var only: PackedStringArray = []
var orbit := 0
var arc := 360.0
var start_z := NAN
var strip := 0
var stats := false
var hook := false
var world: Node3D
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--orbit="): orbit = int(argument.trim_prefix("--orbit="))
		if argument.begins_with("--arc="): arc = float(argument.trim_prefix("--arc="))
		if argument.begins_with("--strip="): strip = int(argument.trim_prefix("--strip="))
		if argument.begins_with("--startz="): start_z = float(argument.trim_prefix("--startz="))
		if argument == "--stats": stats = true
		if argument == "--hook": hook = true
	create_timer(150.0).timeout.connect(func() -> void:
		print("STAGE_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

## Mean luma (Rec.709 weights, 8-bit values) and mean HSV saturation of an image.
static func measure(image: Image) -> Vector2:
	var small := image.duplicate() as Image
	small.convert(Image.FORMAT_RGB8)
	var data := small.get_data()
	var luma := 0.0
	var saturation := 0.0
	var count := data.size() / 3
	for k in count:
		var r := float(data[k * 3])
		var g := float(data[k * 3 + 1])
		var b := float(data[k * 3 + 2])
		luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
		var high := maxf(r, maxf(g, b))
		saturation += 0.0 if high <= 0.0 else (high - minf(r, minf(g, b))) / high
	return Vector2(luma / count, saturation / count)

func run() -> void:
	if shots == "":
		print("STAGE_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	var level := level_number - 1
	if level < 0 or level >= world.level_count() or (world._levels[level].data.get("stage", {}) as Dictionary).is_empty():
		print("STAGE_FRAMES FAIL level ", level_number, " is not a stage round")
		quit(1)
		return
	camera = Camera3D.new()
	camera.far = 4000.0 # as the game camera (Camera3D default); the candy world reaches 2600 m (the cloud wall)
	holder.add_child(camera)
	camera.current = true
	world.set_active_level(level)
	if hook:
		var started := Time.get_ticks_usec()
		var built := ArenaWorld.build(world._levels[level].data, Vector3.ZERO)
		print("STAGE_FRAMES hook build ", snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1), " ms, ", built.get_child_count(), " parts")
		built.free()
		for k in [0, level, 0, level]:
			world.set_active_level(k)
			var sun: DirectionalLight3D = world._light.sun
			var backdrop := ""
			for child in world.get_children():
				if child.name.begins_with("ArenaWorld") or child.name.begins_with("Party") or child.name.begins_with("Room") or child.name.begins_with("Backdrop") or child.name.begins_with("Night"): backdrop = str(child.name)
			print("STAGE_FRAMES hook level ", k + 1, " backdrop ", backdrop, " sun energy ", snappedf(sun.light_energy, 0.001), " shadow distance ", sun.directional_shadow_max_distance, " sky ", (world._light.holder.environment.sky.sky_material as Material).get_class() if world._light.holder.environment.sky != null else "none", " ambient ", world._light.holder.environment.ambient_light_source, " stage env ", world._light.holder.environment == world._light.get("stage_environment"))
		quit(0)
		return
	var data: Dictionary = world._levels[level].data
	var ring := ArenaWorld.ring_of(data.tiles)
	var half := INF
	for apothem: float in ring.apothems: half = minf(half, apothem)
	var all_tops := ArenaWorld.layer_tops(data.tiles)
	var tops := all_tops.slice(1) # the full layers: the start layer (12 groups of 3 x 3 tiles, one gap over the first full one) is not a layer to frame a trail or a hole on
	var starts: Array = []
	for at: Vector3 in (data.stage.get("starts", []) as Array): starts.append(at)
	if starts.is_empty(): # a level without pads: a staggered 3 x 4 block in the far part
		for row in 3:
			for column in 4: starts.append(Vector3((column - 1.5) * 14.0 + (row % 2) * 7.0, 0.0, half * 0.4 + row * 10.0))
	var corner := Vector2.ZERO
	for vertex: Vector2 in ring.vertices:
		if corner == Vector2.ZERO or vertex.x + vertex.y > corner.x + corner.y: corner = vertex
	var raised: Array = []
	for tile: Dictionary in data.tiles.tiles:
		if float((data.tiles.kinds[tile.kind] as Dictionary).raise) > 0.0: raised.append(Vector2(tile.p.x, tile.p.z))
	var info := {"raised": raised, "half": half, "starts": starts, "tops": tops, "ground": ArenaWorld.ground_top(data, all_tops), "corner": corner, "ring": ring}
	if not is_nan(start_z): info["start_z"] = start_z
	var made := make_shots(info)
	var done := 0
	if strip > 0:
		done += await take_strip(made["start"], level, strip)
	elif orbit > 0:
		for k in orbit:
			var angle := deg_to_rad(arc) * k / orbit
			var eye := Vector3(sin(angle) * half * 1.1, 14.0, cos(angle) * half * 1.1)
			done += await take("orbit_%02d" % k, {"eye": eye, "look": Vector3(0.0, -2.0, 0.0), "fov": 60.0, "clock": 1.0, "who": [[Vector3(0.0, 0.05, 0.0), 0.0]]}, level)
	else:
		for name: String in made:
			if not only.is_empty() and not name in only: continue
			done += await take(name, made[name], level)
	print("STAGE_FRAMES ok=", done > 0)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)

## The tile bytes of a shot's trails, cleared layers and kept tiles (the poses are a pure function of the bytes and the level clock).
func steps_for(level: int, spec: Dictionary) -> PackedByteArray:
	var data: Dictionary = world._levels[level].data.tiles
	var count: int = world.tile_count(level)
	var steps := PackedByteArray()
	steps.resize(count)
	var floors: Array = data.floors
	for entry: Array in spec.get("clear", []): # [layer index, half width (-1 all), step clock]
		var y := float((floors[int(entry[0])] as Dictionary).y)
		for index in count:
			var p: Vector3 = data.tiles[index].p
			if absf(p.y - y) > 0.7 or (float(entry[1]) > 0.0 and maxf(absf(p.x), absf(p.z)) > float(entry[1])): continue
			var kept := false
			for keep: Array in spec.get("keep", []):
				if int(keep[0]) == int(entry[0]) and Vector2(p.x - float(keep[1]), p.z - float(keep[2])).length() <= float(keep[3]): kept = true
			if not kept: steps[index] = StepTiles.stamp_at(data, float(entry[2]))
	var tiles = world._levels[level].tiles # levels/step_tiles.gd
	for run_spec: Array in spec.get("trail", []): # [from, to, step clock at from, m/s]
		var from: Vector3 = run_spec[0]
		var to: Vector3 = run_spec[1]
		var length := from.distance_to(to)
		var at := 0.0
		while at <= length:
			var feet: Vector3 = from.lerp(to, at / maxf(length, 0.01))
			var stamp := StepTiles.stamp_at(data, float(run_spec[2]) + at / float(run_spec[3]))
			for index: int in tiles.tiles_at(feet, 0.0):
				if steps[index] == 0: steps[index] = stamp
			at += 0.25
	return steps

## Triangles one draw of the nodes under `node` puts on the screen (a MultiMesh counts its instances), and the number of draw nodes: what the world around the tiles costs.
static func cost_of(node: Node) -> Vector2i:
	var total := Vector2i.ZERO
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		total += Vector2i(_triangles((node as MeshInstance3D).mesh), 1)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var multi := (node as MultiMeshInstance3D).multimesh
		total += Vector2i(_triangles(multi.mesh) * multi.instance_count, 1)
	for child in node.get_children(): total += cost_of(child)
	return total

static func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if indices != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return count

## Puts the characters and the camera of `spec` in place and returns the rigs (the clock and the tile steps are the caller's).
func place(spec: Dictionary, level: int) -> Array:
	var origin: Vector3 = world.level_origin(level)
	var pegs: Array = []
	var seat := 0
	for who: Array in spec.who:
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(seat, {})
		rig.global_position = origin + (who[0] as Vector3)
		var yaw := deg_to_rad(float(who[1]))
		var motion := {"velocity": Vector3.ZERO, "grounded": true, "yaw": yaw, "carrying": false}
		rig.snap(motion)
		for i in 3: rig.update(1.0 / 60.0, motion)
		pegs.append(rig)
		seat += 1
	camera.fov = float(spec.fov)
	camera.global_position = origin + (spec.eye as Vector3)
	if spec.has("look"): camera.look_at(origin + (spec.look as Vector3), Vector3.UP)
	else: camera.global_basis = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, deg_to_rad(float(spec.pitch))) # a chase view looks towards +Z
	if bool(spec.get("ghost", true)) and world.tile_count(level) > 0: world.ghost_tiles(level, camera.global_position.y - origin.y, (((spec.who as Array)[0] as Array)[0] as Vector3).y if not (spec.who as Array).is_empty() else 0.0)
	return pegs

## A tile going white, sinking and going: the courier of the `start` shot stands still on its pad, the tile under its feet is stepped at level clock T0 (frame STRIP_STEP of `count`),
## every frame is `1 / STRIP_FPS` s after the one before (30 fps), the same camera throughout. Frames `strip_<prefix>NN.png`.
func take_strip(spec: Dictionary, level: int, count: int) -> int:
	var data: Dictionary = world._levels[level].data.tiles
	var tiles = world._levels[level].tiles
	var feet: Vector3 = ((spec.who as Array)[0] as Array)[0]
	var stepped := PackedByteArray()
	stepped.resize(world.tile_count(level))
	for index: int in tiles.tiles_at(feet, 0.0): stepped[index] = StepTiles.stamp_at(data, STRIP_T0)
	var pegs := place(spec, level)
	var saved := 0
	for k in count:
		world.set_clock(STRIP_T0 + float(k - STRIP_STEP) / STRIP_FPS)
		world.set_tile_steps(level, stepped if k >= STRIP_STEP else PackedByteArray(), true)
		await frames(3)
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		var file := "%s/%sstrip_%02d.png" % [shots, prefix, k]
		if image.save_png(file) == OK: saved += 1
		var measured := measure(image)
		print("STAGE_FRAMES strip %s clock %.3f luma %.1f sat %.3f" % [file.get_file(), world.get("clock") if world.get("clock") != null else -1.0, measured.x, measured.y])
	for rig: Node in pegs: rig.queue_free()
	return 1 if saved == count else 0

func take(name: String, spec: Dictionary, level: int) -> int:
	var size: Vector2i = spec.get("size", Vector2i.ZERO)
	var base_size := root.size
	if size != Vector2i.ZERO: root.size = size
	world.set_clock(float(spec.clock))
	world.set_tile_steps(level, steps_for(level, spec), true)
	var pegs := place(spec, level)
	await frames(5)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s%s.png" % [shots, prefix, name]
	var saved := image.save_png(file) == OK
	var measured := measure(image)
	var line := "STAGE_FRAMES shot %s %s %dx%d luma %.1f sat %.3f" % [file.get_file(), saved, image.get_width(), image.get_height(), measured.x, measured.y]
	if stats:
		line += " draw_calls %d triangles %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
	if stats:
		for child in world.get_children():
			if str(child.name).begins_with("ArenaWorld"):
				var cost := cost_of(child)
				line += " | arena_world triangles %d nodes %d" % [cost.x, cost.y]
				var candy: Variant = child.get_node_or_null("CandyWorld")
				if candy != null: line += " candy_world %s" % [CandyWorld.stats(candy as Node)]
	print(line)
	for rig: Node in pegs: rig.queue_free()
	if size != Vector2i.ZERO: root.size = base_size
	return 1 if saved else 0
