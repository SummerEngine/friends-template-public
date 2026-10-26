extends SceneTree
## A clip of a bot round of a stage level (25-28), drawn: the REAL level world and character rig, the REAL stage camera (follow_camera.gd, the stage view) following one runner, the
## bots and the show rules of tools/stage_round_check.gd (this script's bots are that script's: same classes, same choices, a copy so the check stays whole). The sim runs from the start
## of the play phase at the headless speed; from `--from` s of play time it draws a frame every 1/30 s for `--len` s and writes them as PNGs. The offscreen binary stops a script after
## about 30 s of wall time: a longer clip is written in parts (`--from` / `--len`; the sim is deterministic, so each part re-plays the round up to its start).
##   lockf -k <render.lock> <offscreen Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 960x540 --path demo -s $PWD/tools/stage_clip.gd -- \
##     --shots=<dir> [--level=25] [--players=10] [--follow=0] [--from=0] [--len=6] [--index=0] [--seed=1] [--pace=0.8] [--hops=0.5]
## Prints STAGE_CLIP lines (one per frame: play time, the followed runner's state, luma and saturation of the frame) and `STAGE_CLIP ok=<bool>` last.
const LevelWorld := preload("res://levels/level_world.gd")
const Motion := preload("res://courier/courier_motion.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const PlayerContact := preload("res://players/player_contact.gd")
const CharRig := preload("res://character/character_rig.gd")
const FollowCamera := preload("res://game/follow_camera.gd")
const DT := 1.0 / 60.0
const CLIP_FPS := 30.0
const LOOK_STEPS := [1.0, 2.0, 3.0, 4.0] ## tiles ahead a bot looks at
const FAR_STEPS := [6.0, 8.0, 10.0, 12.0] ## and further, for whole ground
const TURN_STEP := 15.0 ## degrees between the headings a bot considers
const CROWD := 7.0 ## m: a bot looks at the others this near when it picks a heading

## ModeHost without a shell: positions are the bodies', every question about the level goes to the one LevelWorld.
class StageHost extends "modes/fake_host.gd":
	var world: Node3D
	var bodies: Array = []
	var motions: Array = []
	func zone(slot: int, level: int) -> String:
		return world.zone_at(level, position(slot))
	func scorch(_slot: int, _level: int) -> String:
		return ""
	func level_clock() -> float:
		return world.clock
	func begin_level(level: int, out := []) -> void:
		bench(out)
		world.set_active_level(level)
		world.set_clock(0.0)
		var start: Dictionary = world.team_start(level, count)
		for slot in count:
			place(slot, (start.pos[slot] if slot < start.pos.size() else start.spot) + Vector3.UP * 0.05, float(start.yaw))
	func place(slot: int, at: Vector3, yaw := 0.0) -> void:
		positions[slot] = at
		if slot < bodies.size(): (motions[slot] as Object).reset(bodies[slot], at, yaw)
	func respawn(slot: int, level: int, checkpoint: int) -> void:
		var spot: Dictionary = world.team_start(level, count, checkpoint)
		place(slot, (spot.pos[slot] if slot < spot.pos.size() else spot.spot) + Vector3.UP * 0.05, float(spot.yaw))
	func send_to(slot: int, at: Vector3, yaw := 0.0) -> void:
		super(slot, at, yaw)
		if slot < bodies.size(): (motions[slot] as Object).reset(bodies[slot], at, yaw)
	func tile_start(level: int, players: int) -> PackedByteArray:
		return world.tile_start(level, players)
	func tiles_under(slot: int, level: int) -> Array:
		return world.tiles_under(level, position(slot))
	func apply_tiles(level: int, steps: PackedByteArray) -> void:
		world.set_tile_steps(level, steps)
	func tile_stamp(level: int) -> int:
		return world.tile_stamp(level)
	func tile_settled(level: int, index: int) -> bool:
		return world.tile_settled(level, index)

## One bot's state: where it heads, how long it takes to look again, and the counters of what went wrong.
class Bot extends RefCounted:
	var slot := 0
	var heading := Vector2.DOWN
	var share := 0.9 ## of the full run
	var look_in := 0.0 ## s until it looks around again
	var wander_in := 0.0 ## s until it turns for no reason
	var jump_cool := 0.0
	var layer := 0
	var airborne := 0.0
	var still := 0.0 ## s commanded to run and not getting anywhere
	var hover := 0.0
	var stuck := 0
	var wedged := 0
	var bounced := 0
	var landings := 0
	var drops := 0 ## landings slower than DROP_SPEED: a stepped tile sinking under the courier
	var hop_in := 1.0 ## s until the next hop
	var jumps := 0
	var since_landing := 99.0
	var jumped_for := 0.0
	var last_up := false
	var rng := RandomNumberGenerator.new()
var world: Node3D
var pace := 0.8
var hops := 0.5 ## jumps a second a bot makes on average while it runs
var seed_value := 1
var shots := ""
var level_number := 25
var players := 10
var follow_slot := 0
var from_time := 0.0 ## s of play time the frames start at
var length := 6.0 ## s of frames
var first_index := 0 ## the number of the first frame (the next part of a clip continues the numbering)
var failures := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--level="): level_number = int(argument.trim_prefix("--level="))
		if argument.begins_with("--players="): players = int(argument.trim_prefix("--players="))
		if argument.begins_with("--follow="): follow_slot = int(argument.trim_prefix("--follow="))
		if argument.begins_with("--from="): from_time = float(argument.trim_prefix("--from="))
		if argument.begins_with("--len="): length = float(argument.trim_prefix("--len="))
		if argument.begins_with("--index="): first_index = int(argument.trim_prefix("--index="))
		if argument.begins_with("--pace="): pace = float(argument.trim_prefix("--pace="))
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--hops="): hops = float(argument.trim_prefix("--hops="))
	if shots == "":
		print("STAGE_CLIP needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.render_loop_enabled = false # frames are drawn on demand (the part of the round before the clip runs at headless speed)
	create_timer(600.0).timeout.connect(func() -> void:
		print("STAGE_CLIP FAIL timed out")
		print("STAGE_CLIP ok=false")
		quit(1))
	run.call_deferred()

func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	await play_round(level_number - 1)
	print("STAGE_CLIP ok=", failures == 0)
	quit(0 if failures == 0 else 1)

## The yaw (radians) of a courier facing the planar direction `heading` (x, z): yaw 0 faces -Z.
static func yaw_of(heading: Vector2) -> float:
	return atan2(-heading.x, -heading.y)

func play_round(level: int) -> void:
	var entry: Dictionary = world._levels[level]
	world.set_active_level(level)
	var seats: Array = []
	for slot in players: seats.append(slot)
	var host := StageHost.new(seats, seed_value)
	host.world = world
	host.pick = "r%d" % (level + 1)
	var floors: Array = entry.data.tiles.floors
	var tops := PackedFloat32Array()
	for layout: Dictionary in floors: tops.append(float(layout.y) + (world.level_origin(level) as Vector3).y)
	var bots: Array = []
	var rigs: Array = []
	var yaws: Array = []
	for slot in players:
		var body := Motion.make_body("Courier")
		world.add_child(body)
		var motion := Motion.new()
		motion.setup(body)
		motion.set_stage(true)
		motion.set_floors(tops)
		host.bodies.append(body)
		host.motions.append(motion)
		var bot := Bot.new()
		bot.slot = slot
		bot.rng.seed = seed_value * 100003 + level * 1009 + players * 31 + slot
		bot.heading = Vector2.from_angle(bot.rng.randf() * TAU)
		bot.share = clampf(pace + bot.rng.randf_range(-0.08, 0.06), 0.4, 1.0)
		bot.look_in = bot.rng.randf_range(0.0, 0.3)
		bot.wander_in = bot.rng.randf_range(1.5, 4.0)
		bots.append(bot)
		var rig: Node3D = CharRig.new()
		world.add_child(rig)
		rig.setup(slot, {})
		rigs.append(rig)
		yaws.append(PI)
	var camera := Camera3D.new()
	camera.far = 4000.0 # as the game camera
	world.add_child(camera)
	camera.current = true
	var follow := FollowCamera.new()
	follow.configure(camera)
	follow.set_stage_view(true)
	var contact := PlayerContact.new(players)
	contact.stage = true
	var rules := ShowRules.new()
	rules.start(host)
	var origin: Vector3 = world.level_origin(level)
	var tiles: StepTiles = entry.tiles
	var pitch := float(entry.data.tiles.pitch)
	var clock := 0.0
	var drawn := 0
	var next_frame := 0.0
	var frames_wanted := int(length * CLIP_FPS)
	while rules.phase != "done" and clock < 220.0 and drawn < frames_wanted:
		await physics_frame
		clock += DT
		world.advance(DT)
		var states: Array = []
		for slot in players:
			var body: CharacterBody3D = host.bodies[slot]
			states.append({"position": body.global_position + Vector3(0.0, 0.9, 0.0), "velocity": body.velocity})
		var results: Array = contact.step(DT, states).results
		for slot in players:
			var body: CharacterBody3D = host.bodies[slot]
			var motion: Object = host.motions[slot]
			var bot: Bot = bots[slot]
			var result: Dictionary = results[slot]
			if result.separate != Vector3.ZERO: body.move_and_collide(result.separate)
			if result.impulse != Vector3.ZERO: motion.launch(result.impulse, false, false)
			var input := {}
			var playing: bool = rules.status[slot] == ShowRules.PLAYING and rules.phase == "play"
			if playing: input = bot_input(bot, host, rules, level, floors, origin, pitch, tiles, body, motion, players)
			if float(result.stagger) > 0.0:
				motion.set_surface({"ice": true})
				if input.has("move"): input.move = (input.move as Vector2) * 0.35
			else: motion.set_surface({})
			var events: Dictionary = motion.step(body, input, DT)
			host.positions[slot] = body.global_position
			if events.landed: bot.look_in = 0.0 # a new floor: look again
			if playing and (body.velocity.x != 0.0 or body.velocity.z != 0.0): yaws[slot] = lerp_angle(float(yaws[slot]), yaw_of(Vector2(body.velocity.x, body.velocity.z)), 0.3)
			(rigs[slot] as Node3D).global_position = body.global_position
			(rigs[slot] as Node3D).update(DT, {"velocity": body.velocity, "grounded": motion.grounded, "yaw": float(yaws[slot]), "carrying": false})
		rules.tick(DT)
		var followed: CharacterBody3D = host.bodies[follow_slot]
		var planar := Vector2(followed.velocity.x, followed.velocity.z).length()
		follow.update(DT, followed.global_position + Vector3(0.0, FollowCamera.STAGE_FOCUS_HEIGHT, 0.0), PI, deg_to_rad(FollowCamera.STAGE_PITCH_DEFAULT), null, {"grounded": host.motions[follow_slot].grounded, "run": planar / float(Motion.STAGE_FEEL.walk)})
		world.ghost_tiles(level, -INF, followed.global_position.y, DT) # the stage view hides every floor over the followed courier (game_run.gd _ghost_tiles)
		if rules.phase != "play" or rules.phase_time < from_time or rules.phase_time < next_frame: continue
		next_frame = maxf(next_frame, rules.phase_time) + 1.0 / CLIP_FPS - 0.5 * DT
		await process_frame
		RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		var file := "%s/f_%04d.png" % [shots, first_index + drawn]
		if image.save_png(file) != OK: failures += 1
		var measured := measure(image)
		print("STAGE_CLIP frame %04d play %.2f runner %s y %.2f speed %.1f %s alive %d luma %.1f sat %.3f" % [first_index + drawn, rules.phase_time, (followed.global_position - origin).snapped(Vector3.ONE * 0.1), followed.global_position.y - origin.y, planar, "out" if rules.status[follow_slot] != ShowRules.PLAYING else "in", rules._alive().size(), measured.x, measured.y])
		drawn += 1
	if drawn < frames_wanted:
		failures += 1
		print("STAGE_CLIP FAIL only %d of %d frames (the round ended at %.1f s of play)" % [drawn, frames_wanted, rules.phase_time])
	for body: CharacterBody3D in host.bodies: body.queue_free()

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

## The floor (index) a courier at `feet` stands over: the highest floor top at or under its feet (+ a step).
func floor_of(floors: Array, feet_y: float, origin_y: float) -> int:
	var best := -1
	for index in floors.size():
		if origin_y + float(floors[index].y) <= feet_y + 0.7 and (best < 0 or float(floors[index].y) > float(floors[best].y)): best = index
	return best

## The tile of `layer` that holds level-local (x, z) and is still there, -1 for none (a hole, or past the edge).
func ground_at(level: int, tiles: StepTiles, floors: Array, layer: int, at: Vector2) -> int:
	for index: int in tiles.tiles_at(Vector3(at.x, float((floors[layer] as Dictionary).y), at.y), 0.0):
		if not world.tile_gone(level, index): return index
	return -1

## The bot's input this tick: run in a straight line over tiles nobody has stepped, turn where the ground ends, jump a hole one tile wide.
func bot_input(bot: Bot, host: StageHost, rules: ShowRules, level: int, floors: Array, origin: Vector3, pitch: float, tiles: StepTiles, body: CharacterBody3D, motion: Object, players: int) -> Dictionary:
	var layer := floor_of(floors, body.global_position.y, origin.y)
	if layer < 0: return {} # on the ground floor or below: out
	if not motion.grounded: return {"move": bot.heading * bot.share} if body.velocity.y > 0.0 else {} # rising: keep the heading, falling: no steering
	var here := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	bot.look_in -= DT
	bot.wander_in -= DT
	bot.jump_cool -= DT
	if layer != bot.layer:
		bot.layer = layer
		bot.look_in = 0.0
	var ahead := ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 1.5)
	if bot.look_in <= 0.0 and (ahead < 0 or bot.wander_in <= 0.0):
		bot.look_in = bot.rng.randf_range(0.1, 0.3) # a person takes a moment to look again
		if bot.wander_in <= 0.0: bot.wander_in = bot.rng.randf_range(1.5, 4.0)
		bot.heading = choose_heading(bot, host, rules, level, floors, layer, origin, pitch, tiles, here, players)
	var jump := false
	if bot.jump_cool <= 0.0 and ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 0.9) < 0 and ground_at(level, tiles, floors, layer, here + bot.heading * pitch * 2.0) >= 0:
		jump = true # a hole one tile wide ahead and ground behind it
		bot.jump_cool = 0.8
	bot.hop_in -= DT
	if bot.hop_in <= 0.0:
		bot.hop_in = -log(maxf(bot.rng.randf(), 0.001)) / maxf(hops, 0.001) # people hop now and then, `hops` times a second on average
		if bot.jump_cool <= 0.0:
			jump = true
			bot.jump_cool = 0.4
	return {"move": bot.heading * bot.share, "jump": jump}

## The heading (within 120 degrees of the old one) with the most ground and the most untouched tiles ahead, a small turn preferred, nobody in the way, a little chance.
func choose_heading(bot: Bot, host: StageHost, rules: ShowRules, level: int, floors: Array, layer: int, origin: Vector3, pitch: float, tiles: StepTiles, here: Vector2, players: int) -> Vector2:
	var best := bot.heading
	var best_score := -INF
	for step in range(-8, 9):
		var dir := bot.heading.rotated(deg_to_rad(float(step) * TURN_STEP))
		var score := bot.rng.randf() * 0.7 - absf(float(step)) * 0.1
		var open := 0
		for distance: float in LOOK_STEPS:
			var index := ground_at(level, tiles, floors, layer, here + dir * pitch * distance)
			if index < 0:
				if distance <= 2.0: score -= 40.0 / distance
				break
			open += 1
			if rules.tiles[index] == 0: score += 1.0
			else: score -= 0.3
		score += float(open) * 0.4
		for distance: float in FAR_STEPS: # people head for the part of the floor that is still whole
			var far := ground_at(level, tiles, floors, layer, here + dir * pitch * distance)
			if far >= 0 and rules.tiles[far] == 0: score += 0.5
		var spot := here + dir * pitch * 3.0
		for other in players:
			if other == bot.slot or rules.status[other] != ShowRules.PLAYING: continue
			var theirs := Vector2(host.positions[other].x - origin.x, host.positions[other].z - origin.z)
			if theirs.distance_to(here) > CROWD * 2.0: continue
			var gap := theirs.distance_to(spot)
			if gap < CROWD: score -= (CROWD - gap) * 0.25
		if score > best_score:
			best_score = score
			best = dir
	return best
