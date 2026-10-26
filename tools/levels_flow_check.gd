extends SceneTree
## The level game's local flow without a window: PLAY -> lobby (two circles) -> both players on one circle -> countdown -> run ->
## every level "cleared" by forcing the ending -> results page. Prints LEVELS_FLOW lines; frames with --shots=<dir>.
## Run offscreen (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 400 <Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/levels_flow_check.gd -- [--shots=<dir>] [--mode=time_attack|endless] [--levels=N] [--balloon]
## --balloon (the dev switch of course_section.gd) plays the balloon mode with the two local players: the balloon is put into the goal.
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const TeamCast := preload("res://style/team_cast.gd")
var shots := ""
var mode := "time_attack"
var wanted := 0
var sim: Node

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
		if a.begins_with("--mode="): mode = a.trim_prefix("--mode=")
		if a.begins_with("--levels="): wanted = int(a.trim_prefix("--levels="))
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["run"] = mode # a game shows one circle, the cast's run (TeamCast.run)
	cast["mode"] = "carry" # the template's own cast plays the show; this check plays the carry rounds
	TeamCast.override(cast)
	run.call_deferred()

func capture(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("LEVELS_FLOW shot ", name, " ", image.save_png("%s/%s.png" % [shots, name]) == OK)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	sim = VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("LEVELS_FLOW boot_timeout")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for key in ["move", "jump", "tilt", "lift"]: hud_script.taught[key] = true
	var ui = sim.local_presentation
	print("LEVELS_FLOW levels=", CourseSection.level_count(), " titles=", range(CourseSection.level_count()).map(func(i): return CourseSection.level_title(i)))
	ui.show_local_job()
	ui._input_mode_selected(2)
	await process_frame
	ui.start_job()
	await frames(90)
	var flow = ui.level_flow
	print("LEVELS_FLOW phase=", flow.phase, " pads=", WalkInLobby.pads().map(func(p): return p.title))
	await frames(60)
	capture("lobby")
	# both players on one circle: ENDLESS or TIME ATTACK
	var course := CourseSection.CHALLENGE if mode == "endless" else CourseSection.ADVENTURE
	var centre := WalkInLobby.center(course)
	sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
	sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	await frames(60 * int(WalkInLobby.COUNTDOWN + 1.0))
	print("LEVELS_FLOW waiting_for_play=", flow.phase == "lobby" and flow.probe().ready != "" and flow.probe().pick == "", " hud=", flow.probe().hud)
	if flow.phase != "lobby": print("LEVELS_FLOW FAIL the run started without PLAY")
	flow.press_play()
	await frames(60)
	capture("lobby-countdown")
	var t0 := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - t0 < 20000: await frames(10)
	print("LEVELS_FLOW phase=", flow.phase, " run=", flow.run_state().get("mode", ""), " queue=", flow.run.queue if flow.run != null else [])
	var cleared := 0
	if wanted == 0: wanted = 5 if mode == "time_attack" else 3
	while cleared < wanted and flow.phase == "round":
		await frames(120 if cleared == 0 else 20)
		if cleared == 0:
			capture("level-1")
			await frames(120)
			capture("level-1b")
		print("LEVELS_FLOW level ", flow.run.number(), " ", CourseSection.level_title(flow.run.level()), " start=", sim.actors[0].global_position)
		sim.started_moving = true # the run clock only runs once somebody moved
		for i in (90 if cleared == 0 else 30): await physics_frame
		var goal: Dictionary = sim.level_world.goal_volume(flow.run.level()) # both couriers walk into the goal volume (no forced result)
		if sim.play_mode == "balloon": # balloon mode: the balloon has to get there
			print("LEVELS_FLOW balloon alive=", sim.team.balloon.alive, " hover=", sim.team.balloon.hover, " at=", sim.team.balloon.position, " look=", sim.team.look.visible)
			if cleared == 0: await _contact()
			sim.team.balloon.hover = false
			sim.team.balloon.position = goal.p
		else:
			for slot in 2: sim.actors[slot].global_position = goal.floor + Vector3(0.0, 0.05, 0.0) + Vector3(-0.6 if slot == 0 else 0.6, 0.0, 0.0)
		await frames(40)
		cleared += 1
		if flow.phase != "round": break
		if cleared == 1: capture("cleared")
		var t1 := Time.get_ticks_msec()
		var before: int = flow.run.number()
		while flow.phase == "round" and flow.run.number() == before and Time.get_ticks_msec() - t1 < 15000: await frames(10)
	if flow.phase == "round": flow.finish_run()
	await frames(150)
	print("LEVELS_FLOW cleared=", cleared, " phase=", flow.phase, " times=", flow.run.times, " total=", flow.run.total(), " finished=", flow.run.finished, " ", flow.run.headline(), " | ", flow.run.summary())
	capture("results")
	flow._screens.play_again_pressed.emit()
	await frames(30)
	print("LEVELS_FLOW back phase=", flow.phase)
	capture("lobby-again")
	quit(0)

## Players touching players on one machine (balloon mode): GRAB the partner in front, ride, throw; then a shove.
func _contact() -> void:
	var a: CharacterBody3D = sim.actors[0]
	var b: CharacterBody3D = sim.actors[1]
	b.global_position = a.global_position + Vector3(0.0, 0.0, -0.8)
	await frames(5)
	sim.team.note_presses(0, 0, 1)
	await frames(3)
	var held: bool = sim.team.held_by(1) == 0 and b.global_position.distance_to(a.global_position + Vector3.UP * 1.7) < 0.1
	sim.team.note_presses(0, 0, 1)
	await frames(2)
	print("LEVELS_FLOW contact held=", held, " thrown=", sim.team.held_by(1) < 0, " v=", b.velocity)
	await frames(90)
	b.global_position = a.global_position + Vector3(0.0, 0.0, -0.6)
	a.velocity = Vector3(0.0, 0.0, -5.0)
	await frames(1)
	print("LEVELS_FLOW contact shove v=", b.velocity, " gap=", snappedf(a.global_position.distance_to(b.global_position), 0.01))
	# A slap: courier A under the hanging balloon, a GRAB press there (split as the keyboard's would be).
	await frames(60)
	var balloon = sim.team.balloon
	a.global_position = balloon.position + Vector3(0.6, -2.6, 0.6)
	b.global_position = a.global_position + Vector3(4.0, 0.0, 0.0)
	await frames(3)
	var split: Array = sim.team.split_grabs(0, 1)
	sim.team.note_presses(0, 0, split[0], split[1])
	await frames(10)
	print("LEVELS_FLOW slap split=", split, " slaps=", balloon.slaps, " vy=", snappedf(balloon.velocity.y, 0.01), " swings=", sim.team.slaps_shown)
