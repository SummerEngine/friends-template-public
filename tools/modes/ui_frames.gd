extends SceneTree
## Preview frames of the show's HUD (modes/mode_hud.gd, stage_hud.gd, plates.gd, face_wall.gd, client/name_tags.gd) over a level's world, with hand-made models and states: a race mid-play (feed, counters,
## timer, name tags), the survival counters, a stage round (eliminations, feed, objective), the round card, the countdown 3 / GO, the QUALIFIED / ELIMINATED / VICTORY banners, the points board
## and the face wall. Offscreen binary only, never windowed, about 15 s per run; one run per screen size (`--resolution`, a phone is 844x390 with `--touch`):
##   lockf -k ~/.local/state/friends-slots/render.lock <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 --resolution 1280x720 \
##     --path demo -s "$PWD/tools/modes/ui_frames.gd" -- --shots=<dir> [--prefix=ui_] [--only=name,name] [--touch]
## Prints UI_FRAMES lines.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const StageHud := preload("res://modes/show/stage_hud.gd")
const Plates := preload("res://modes/show/plates.gd")
const FaceWall := preload("res://modes/show/face_wall.gd")
const NameTags := preload("res://client/name_tags.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const ShowView := preload("res://modes/show/view.gd")

const RACE_LEVEL := 13 ## CIRCUIT BREAKER (0-based)
const STAGE_LEVEL := 24 ## SQUARE STACK A
const CATCH := "NO PROBLEM!" ## a catchphrase under the banner

## What NameTags.configure asks the simulation for: the actors (one body per slot) and the round's mode.
class Sim extends Node:
	var actors: Array = []
	var round_mode := "show"
	func stage_round() -> bool: return false

## A stand-in for the phone's overlay: only `is_active` is asked (TouchControls.showing).
class Overlay extends Node:
	func is_active() -> bool: return true

var shots := ""
var prefix := "ui_"
var only: PackedStringArray = []
var touch := false
var world: Node3D
var holder: Node3D
var camera: Camera3D
var hud: CanvasLayer
var stage: CanvasLayer
var plates: CanvasLayer
var wall: CanvasLayer
var sim: Sim
var tags: Node3D
var pegs: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument == "--touch": touch = true
	create_timer(100.0).timeout.connect(func() -> void:
		print("UI_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func save(name: String) -> void:
	await frames(3)
	RenderingServer.force_draw(false)
	var file := "%s/%s%s.png" % [shots, prefix, name]
	print("UI_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK)

func wanted(name: String) -> bool:
	return only.is_empty() or name in only

## Couriers (with name tags) at `spots` (level-local) of the level at `origin`.
func couriers(origin: Vector3, spots: Array) -> void:
	for peg: Node in pegs: peg.queue_free()
	pegs.clear()
	var entries: Array = []
	for slot in spots.size():
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(slot, {})
		rig.global_position = origin + (spots[slot] as Vector3)
		var motion := {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": false}
		rig.snap(motion)
		for i in 3: rig.update(1.0 / 60.0, motion)
		pegs.append(rig)
		(sim.actors[slot] as Node3D).global_position = rig.global_position
		entries.append({"name": str(TeamCast.player(slot).name).to_upper(), "color": TeamCast.player_color(slot), "visible": true, "rank": 0})
	while entries.size() < sim.actors.size(): entries.append({})
	tags.set_slots(entries)

## Where the yellow marker goes: over the head of the local courier (slot 0).
func head_point() -> Vector2:
	return camera.unproject_position((pegs[0] as Node3D).global_position + Vector3(0.0, ShowView.MARKER_HEAD, 0.0))

func look(origin: Vector3, level: int, eye: Vector3, target: Vector3, clock: float) -> void:
	world.set_active_level(level)
	world.set_clock(clock)
	if world.tile_count(level) > 0: world.set_tile_steps(level, PackedByteArray(), true)
	camera.global_position = origin + eye
	camera.look_at(origin + target, Vector3.UP)

func clear() -> void:
	hud.show_model({})
	stage.show_model({})
	plates.update({}, 0.0)
	wall.visible = false

func run() -> void:
	if shots == "":
		print("UI_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 4000.0 # as the game camera
	holder.add_child(camera)
	camera.current = true
	if touch:
		var overlay := Overlay.new()
		overlay.add_to_group(TouchControls.GROUP)
		root.add_child(overlay)
	sim = Sim.new()
	holder.add_child(sim)
	for slot in 6:
		var body := CharacterBody3D.new()
		body.name = "Courier%d" % slot
		sim.add_child(body)
		sim.actors.append(body)
	tags = NameTags.new()
	holder.add_child(tags)
	tags.configure(sim)
	tags.set_local_slot(0)
	hud = ModeHud.new()
	hud.seats = range(6)
	root.add_child(hud)
	stage = StageHud.new()
	root.add_child(stage)
	plates = Plates.new()
	root.add_child(plates)
	wall = FaceWall.new()
	root.add_child(wall)
	wall.setup(range(6))
	var names: Array = []
	for slot in 6: names.append(str(TeamCast.player(slot).name).to_upper())
	var done := 0

	# ---- a race, mid-play: objective, timer, counter, finish feed, name tags, a banner-free screen
	var origin: Vector3 = world.level_origin(RACE_LEVEL)
	if wanted("race"):
		look(origin, RACE_LEVEL, Vector3(0.0, 6.0, -38.0), Vector3(0.0, 2.5, -62.0), 3.0)
		couriers(origin, [Vector3(-2.0, 0.0, -49.0), Vector3(1.5, 0.0, -53.0), Vector3(3.0, 0.0, -57.0), Vector3(-3.0, 0.0, -45.0)])
		hud.show_model({"title": "ROUND 1  ·  RACE", "big": "", "big_kind": "", "big_age": 1.0, "line": "", "timer": 74.0, "scores": [], "out": [], "tint": true, "calm": true, "note": "",
			"counters": ["Through: 2/5"], "counter_age": 9.0, "feed": [
				{"name": names[0], "tail": TeamCast.show_word("qualified"), "rank": 1, "age": 2.0, "left": 1.0},
				{"name": names[1], "tail": TeamCast.show_word("qualified"), "rank": 2, "age": 0.5, "left": 2.4}], "marker": head_point()})
		await save("race")
		done += 1
	# ---- the same with the points board (a show for two or three) and a note
	if wanted("points"):
		hud.show_model({"title": "ROUND 2  ·  SURVIVAL", "big": "", "big_kind": "", "big_age": 1.0, "line": "", "timer": 41.0, "scores": [3, 5, 1, 2], "out": [2], "tint": true, "calm": true,
			"note": "SPECTATING  ·  %s" % names[1], "counters": ["Standing: 3", "2 go through"], "counter_age": 0.1,
			"feed": [{"name": names[2], "tail": TeamCast.show_word("eliminated"), "rank": 0, "age": 0.4, "left": 2.5}]})
		await save("points")
		done += 1
	# ---- the round card
	if wanted("card"):
		var card := {"phase": "card", "level": RACE_LEVEL, "count": 3.1, "kind": "race", "round": 1, "rounds": 3, "card": "FIRST 3 ACROSS QUALIFY"}
		clear()
		plates.update(card, 0.0)
		await save("card")
		plates.update({"phase": "card", "level": RACE_LEVEL, "count": 2.0, "kind": "race", "round": 1, "rounds": 3, "card": "FIRST 3 ACROSS QUALIFY"}, 0.0)
		await save("card_late")
		done += 1
	# ---- the countdown, GO and the banners (the generic HUD)
	look(origin, RACE_LEVEL, Vector3(0.0, 6.0, -38.0), Vector3(0.0, 2.5, -62.0), 3.0)
	couriers(origin, [Vector3(-2.0, 0.0, -49.0), Vector3(1.5, 0.0, -53.0), Vector3(3.0, 0.0, -57.0), Vector3(-3.0, 0.0, -45.0)])
	var base := {"title": "", "big": "", "big_kind": "", "big_age": 1.0, "line": "", "timer": -1.0, "scores": [], "out": [], "tint": true, "calm": true, "note": "",
		"counters": [], "counter_age": 9.0, "feed": [], "marker": head_point()}
	var big := {"countdown3": ["3", "digit", 0.16, ""], "countdown_go": [TeamCast.show_word("go"), "go", 0.2, ""],
		"qualified": [TeamCast.show_word("qualified"), "qualified", 0.5, CATCH],
		"eliminated": [TeamCast.show_word("eliminated"), "eliminated", 0.5, CATCH],
		"place": ["1ST", "victory", 0.5, CATCH],
		"timesup": ["TIME'S UP", "timesup", 0.5, ""]}
	for key: String in big:
		if not wanted(key): continue
		clear()
		var model := base.duplicate(true)
		var entry: Array = big[key]
		model.big = entry[0]
		model.big_kind = entry[1]
		model.big_age = entry[2]
		model.line = entry[3]
		hud.show_model(model)
		await save(key)
		done += 1
	# ---- a stage round: the objective, the eliminations pill and the red-X feed, the countdown, VICTORY, the failure banner
	var stage_origin: Vector3 = world.level_origin(STAGE_LEVEL)
	if wanted("stage") or wanted("stage_digit") or wanted("stage_victory") or wanted("stage_failure"):
		look(stage_origin, STAGE_LEVEL, Vector3(5.25, 22.0, 0.0), Vector3(5.25, 13.0, -14.0), 6.0)
		couriers(stage_origin, [Vector3(-1.75, 14.3, -8.75), Vector3(12.25, 14.3, -8.75), Vector3(5.25, 14.3, -22.75), Vector3(5.25, 14.3, -14.0)])
	var stage_model := {"pill": "", "pill_age": -1.0, "elim_n": 3, "elim_m": 4, "elim_pop": 0.1, "feed": [
		{"name": names[4], "age": 2.0, "left": 0.9}, {"name": names[5], "age": 0.4, "left": 2.5}], "digit": "", "digit_age": 0.0, "go": "", "go_age": 0.0, "go_len": 1.0,
		"victory_age": -1.0, "victory_len": 2.3, "failure": "", "failure_age": -1.0, "failure_len": 1.4, "marker": head_point()}
	if wanted("stage"):
		clear()
		stage.show_model(stage_model)
		await save("stage")
		done += 1
	if wanted("stage_digit"):
		clear()
		var digit := stage_model.duplicate(true)
		digit.elim_m = -1
		digit.digit = "2"
		digit.digit_age = 0.18
		digit.pill = StageHud.objective(2, 6)
		digit.pill_age = 1.3
		digit.feed = []
		stage.show_model(digit)
		await save("stage_digit")
		done += 1
	if wanted("stage_victory"):
		clear()
		var victory := stage_model.duplicate(true)
		victory.victory_age = 0.4
		stage.show_model(victory)
		await save("stage_victory")
		done += 1
	if wanted("stage_failure"):
		clear()
		var failed := stage_model.duplicate(true)
		failed.failure = TeamCast.show_word("eliminated")
		failed.failure_age = 0.5
		stage.show_model(failed)
		await save("stage_failure")
		done += 1
	# ---- the face wall after a round (two through, one out, the rest standing)
	if wanted("wall"):
		clear()
		look(origin, RACE_LEVEL, Vector3(0.0, 6.0, -38.0), Vector3(0.0, 2.5, -62.0), 3.0)
		wall.update({"phase": "done", "t": 3.0, "status": [1, 1, 2, 2, 1, 2], "field": [0, 1, 2, 3, 4, 5], "place": [0, 1, 4, 2, 3, 5], "kind": "race", "round": 1, "points_mode": false}, 0.0, 0)
		await save("wall")
		done += 1
	print("UI_FRAMES ok=", done > 0)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)
