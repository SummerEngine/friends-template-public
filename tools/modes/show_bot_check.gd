extends SceneTree
## The show played on one machine with REAL courier physics: two bots run the race and the final along the level's route (a greedy
## path follower that jumps at gaps and ledges), so a course nobody can finish shows up here. The local flow ticks the rules, the
## respawns and the points exactly as in a game for two. Prints SHOW_BOT lines; ok=true when the show reaches its results and
## both bots finished the race and the final. `--solo` plays it as the standalone `FRIENDS Show` app does (client/solo_entry.gd: ONE
## player, no title, a points show): one bot, the whole show to the results page, then Play Again back to the lobby, `--shows=<n>` times.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --fixed-fps 60 --path demo -s $PWD/tools/modes/show_bot_check.gd [-- --solo --shows=2 --frames=<dir> [--size=844x390 --touch]] [--pace=0.7] [--trace] [--stop=<s>]   (frames: the offscreen binary instead)
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []
class SoloLocal extends "res://client/solo_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const GameInput := preload("res://game/game_input.gd")
const Hazards := preload("res://levels/hazards.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const PosterDoors := preload("res://levels/poster_doors.gd")
const DOOR_LOOK := 9.0 ## m: a bot heads for the logo poster from this far
const DOOR_HOLD := 2.2 ## m: ... and waits this far from the wall while the opening would be elsewhere when it got there
const DOOR_GO := 0.6 ## m: ... but never waits closer than this (it is through the wall in a tenth of a second)
const DOOR_ALIGN := 0.45 ## m across: the opening would be this close to the bot on arrival: go
const DOOR_PAST := 0.9 ## m past the wall a bot still follows the opening (the board and the blocks are 0.4 m thick, the courier 0.35 m wide)
const WALK_SPEED := 5.0 ## m/s the courier walks at pace 1
var door_normals := {} ## level index -> the way its poster doors face
var sim: Node
var flow: Node
var failures := 0
var shots := ""
var size_wanted := Vector2i.ZERO
var pace := 1.0 ## --pace=<0.4..1>: the share of full speed the bots walk at (an average player is about 0.7 of a perfect route follower)
var solo := false ## --solo: the one-player app (client/solo_entry.gd)
var shows := 1 ## --shows=<n> (solo): shows played one after the other, each started from the lobby with Play Again
var bird_rows := 0 ## GHOST PIGEON: birds the rules have seen this round (printed once each)
var players := 2
var route_index := [0, 0]
var stuck := [0.0, 0.0]
var last_progress := [0.0, 0.0]
var jumped_at := [-9.0, -9.0]
var finished_at := {} ## "kind:slot" -> seconds into the round
var round_log: Array = []
var clock := 0.0
var podium_worst := 0.0 ## the podium: the bots press move and dash every tick; the largest x/z distance from the spot they got
var podium_ticks := 0
var podium_facing := true ## the shell held every courier (hold_yaw) during the podium
var held := [0.0, 0.0]
var prior := [Vector3.ZERO, Vector3.ZERO]
var dodge_until := [0.0, 0.0]
var dodge := [Vector2.ZERO, Vector2.ZERO]
var stop_at := -1.0 ## --stop=<s>: frames only: leave after this many seconds of the race (the offscreen binary ends a script after about 30 s)
var stopped := false
var dash_at := -1.0 ## --dash-at=<s>: frames only: bot 0 jumps (--dash-air) or just runs and dashes at this many seconds into the race, a frame 0.12 s later
var dash_air := false
var flop_shots := false ## --flop-shots (with --dash-at): instead of the dash frame, the belly flop (shoulder view and a free side view) and the get-up
var flop_stage := 0
var bonk_shot := false ## --bonk-shot: frames only: the first hazard bonk of bot 0 in the race is shot 0.15 s after it, in the air, from the player's own view
var bonk_wait := -1
var bonk_z := 1000.0 ## --bonk-z=<z>: only a bonk beyond this level-local z counts (the hammers of level 14 stand past -60, its sweepers at -20)
var bonk_prev_speed := 0.0
var bot_dash := false ## --bot-dash: the bots also dash on flat, clear ground (a player who knows the move: how much shorter a run gets)
var dashed_at := [-9.0, -9.0]
var egg_log := {} ## "round:kind" -> {given, passes, popped}: what the HOT EGGPLANT rule did in that round (the experiment, docs/items.md)
var dash_phase := 0 ## 0 waiting, 1 jump pressed, 2 dash pressed
var dash_ticks := 0
var _dash_sent := false
var fell_seen := 0
var trace := false ## --trace: a position line every 4 s
var phase_seen := ""
var play_at := 0.0
var pick := "" ## --pick=<circle id, e.g. r21>: stand on that round's circle (not THE SHOW's) and play just that round
var dumb := false ## --dumb: on a level with cues bot 1 ignores the cues (and stays where it stands), to see that tiles really drop
var match_level := {} ## the picture-match level in play: {cues, tiles: [{p (level-local), slot, h (normalized hazard)}]}

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("SHOW_BOT ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): shots = argument.trim_prefix("--frames=")
		if argument == "--trace": trace = true
		if argument.begins_with("--pick="): pick = argument.trim_prefix("--pick=")
		if argument == "--dumb": dumb = true
		if argument == "--dash-air": dash_air = true
		if argument == "--bonk-shot": bonk_shot = true
		if argument.begins_with("--bonk-z="): bonk_z = float(argument.trim_prefix("--bonk-z="))
		if argument == "--bot-dash": bot_dash = true
		if argument == "--flop-shots": flop_shots = true
		if argument.begins_with("--dash-at="): dash_at = float(argument.trim_prefix("--dash-at="))
		if argument.begins_with("--stop="): stop_at = float(argument.trim_prefix("--stop="))
		if argument.begins_with("--pace="): pace = clampf(float(argument.trim_prefix("--pace=")), 0.3, 1.0)
		if argument == "--solo":
			solo = true
			players = 1
		if argument.begins_with("--shows="): shows = maxi(1, int(argument.trim_prefix("--shows=")))
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2: size_wanted = Vector2i(int(parts[0]), int(parts[1]))
	create_timer(840.0).timeout.connect(func() -> void:
		print("SHOW_BOT FAIL timed out")
		print("SHOW_BOT ok=false")
		quit(1))
	run.call_deferred()

func capture(label: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("SHOW_BOT shot ", label, " ", image.save_png("%s/%s.png" % [shots, label]) == OK)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func run() -> void:
	if shots != "": RenderingServer.render_loop_enabled = false
	root.mode = Window.MODE_WINDOWED
	if size_wanted != Vector2i.ZERO: root.size = size_wanted # a phone is 844x390
	root.always_on_top = false
	sim = SoloLocal.new() if solo else VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("SHOW_BOT boot_timeout")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for key in ["move", "jump", "tilt", "lift"]: hud_script.taught[key] = true
	var ui = sim.local_presentation
	if solo:
		check(ui.started and sim.local_players == 1 and ui.input_mode_index == 1 and not ui.split_screen, "the solo app starts by itself: one player, keyboard and pad on one courier, one view (started %s, mode %d)" % [str(ui.started), ui.input_mode_index])
		check(not sim.is_slot_active(1), "the second courier is not in the game")
		check(not ui.main_menu.visible, "no title page")
	else:
		ui.show_local_job()
		ui._input_mode_selected(2)
		await process_frame
		ui.start_job()
	await frames(90)
	flow = ui.level_flow
	await frames(60)
	var shown: Array = WalkInLobby.shown_pads()
	check(shown.size() > 1 and str(shown[0].title).to_upper().contains("SHOW") and str(shown[0].pick) == "show", "the lobby shows THE SHOW first and a circle per round: %s" % str(shown.map(func(p): return p.title)))
	var picked: Dictionary = RoundList.entry(pick) if pick != "" else {}
	check(pick == "" or not picked.is_empty(), "the picked circle %s is one of the rounds" % pick)
	var centre := WalkInLobby.center(pick if pick != "" else str(shown[0].course))
	for show_index in shows:
		if show_index > 0: # Play Again (the results page's button): back in the lobby, nothing left of the last show
			flow._screens.play_again_pressed.emit()
			await frames(60)
			check(flow.phase == "lobby" and flow.minigame == null, "Play Again returns to the lobby (%s)" % flow.phase)
			round_log = []
			finished_at = {}
			match_level = {}
			phase_seen = ""
		print("SHOW_BOT show ", show_index + 1, " of ", shows)
		if solo: sim.actors[0].position = centre + Vector3(0.0, 0.3, 0.0)
		else:
			sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
			sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
		await frames(60 * int(WalkInLobby.COUNTDOWN + 1.0))
		check(flow.phase == "lobby", "standing on the circle does not start the show without PLAY")
		if shots != "" and show_index == 0: # frames: one fixed shot over the players' shoulders (a player's own view stares at a wall sign)
			var shoulders := centre + Vector3(0.0, 2.6, 4.6)
			var views_before: Array = [sim.first_person, sim.local_split_screen]
			sim.first_person = false
			sim.local_split_screen = false
			sim.view_override = Transform3D(Basis.IDENTITY, shoulders).looking_at(centre + Vector3(0.0, 0.9, -1.0), Vector3.UP)
			await frames(20)
			capture("lobby_wide")
			sim.view_override = null
			sim.first_person = views_before[0]
			sim.local_split_screen = views_before[1]
			await frames(20)
		if show_index == 0: capture("lobby_ready")
		if pick != "" and solo and not bool(picked.solo): # a round that needs other players: a show for one cannot start it
			check(str(WalkInLobby.pad(pick).subtitle) == WalkInLobby.SOLO_NOTE, "the circle's board says it needs 2+ players (%s)" % str(WalkInLobby.pad(pick).subtitle))
			flow.press_play()
			await frames(60)
			check(flow.phase == "lobby" and flow.minigame == null, "PLAY on a round for 2+ players does nothing in a show for one (%s)" % flow.phase)
			print("SHOW_BOT ok=", failures == 0)
			quit(1 if failures > 0 else 0)
			return
		flow.press_play()
		var t0 := Time.get_ticks_msec()
		while flow.phase != "round" and Time.get_ticks_msec() - t0 < 20000: await frames(5)
		check(flow.phase == "round" and flow.minigame != null and flow.minigame_id == "show", "PLAY starts the show (%s, %s)" % [flow.phase, flow.minigame_id])
		if flow.minigame == null:
			quit(1)
			return
		check(int(flow.minigame.host.count) == players, "the show has %d player(s)" % players)
		await play_the_show()
		if stopped:
			quit(0)
			return
		var log_lines := round_log.map(func(line: Dictionary) -> String: return "%s %s" % [line.kind, line.text])
		print("SHOW_BOT rounds: ", log_lines)
		var kinds := round_log.map(func(line: Dictionary) -> String: return str(line.kind))
		_egg_checks()
		if pick != "":
			check(kinds == [str(picked.kind)] and (picked.levels as Array).has(int(flow.minigame.level)) and flow.minigame.single, "the circle played one %s round and nothing else (%s)" % [picked.kind, str(kinds)])
			check(flow.phase == "results", "the round ends on the results page, after the winner's podium room (phase %s)" % flow.phase)
			capture("results_pick")
			continue
		check(kinds == ["race", "survival", "final"], "the show played race, survival, final (%s)" % str(kinds))
		for slot in players: check(finished_at.has("race:%d" % slot), "bot %d finished the race on real physics (%s)" % [slot, str(finished_at.get("race:%d" % slot, "never"))])
		check(finished_at.has("final:0") or finished_at.has("final:1"), "a bot reached the crown in the final on real physics (%s)" % str([finished_at.get("final:0", "never"), finished_at.get("final:1", "never")]))
		check(flow.phase == "results", "the show ends on the results page (phase %s)" % flow.phase)
		check(podium_ticks > 60 and podium_worst <= 0.5 and podium_facing, "the podium holds the bots on their spots although they press move and dash (%d ticks, worst %.2f m off, held %s)" % [podium_ticks, podium_worst, str(podium_facing)])
		if solo: check(int(flow.minigame.crown) == 0 and int(flow.minigame.pts[0]) > 0, "the one player wears the crown with %s points" % str(flow.minigame.pts))
		capture("results" if show_index == 0 else "results_%d" % (show_index + 1))
	print("SHOW_BOT ok=", failures == 0)
	quit(1 if failures > 0 else 0)

## Both bots play until the show ends (or 12 minutes of game time pass).
func play_the_show() -> void:
	var seen := ""
	var round_start := 0.0
	var stuck_report := 0.0
	var shots_taken := {}
	for tick in 60 * 700:
		await physics_frame
		clock += 1.0 / 60.0
		if flow.phase != "round" or flow.minigame == null: break
		var st: Dictionary = flow.minigame.state()
		var kind := str(st.kind)
		var tag := "%d:%s" % [int(st.round), kind]
		if tag != seen and str(st.phase) != "podium":
			seen = tag
			round_start = clock
			route_index = [0, 0]
			stuck = [0.0, 0.0]
			last_progress = [0.0, 0.0]
			round_log.append({"kind": kind, "text": ""})
			print("SHOW_BOT round ", tag, " level ", int(st.level), " ", CourseSection.level_title(int(st.level)), " t=", snappedf(clock, 0.1))
		if str(st.phase) != phase_seen:
			if str(st.phase) == "play": play_at = clock
			elif phase_seen == "play" and not round_log.is_empty():
				round_log[-1].text += "[play %.1fs] " % (clock - play_at)
				print("SHOW_BOT   ", kind, " play phase lasted ", snappedf(clock - play_at, 0.1), " s")
				if kind == "survival": print("SHOW_BOT   survival: fell ", flow.minigame.fell, " status ", st.status, " (level clock now ", snappedf(float(sim.level_world.clock), 0.1), ")")
			phase_seen = str(st.phase)
		if str(st.phase) == "card" and float(st.t) > 1.5 and not shots_taken.has("card" + kind):
			shots_taken["card" + kind] = true
			capture("card_" + kind)
		if str(st.phase) == "done" and float(st.t) > 0.8 and not shots_taken.has("done" + kind): # the banner (a show for one: its whole result)
			shots_taken["done" + kind] = true
			capture("done_" + kind)
		if str(st.phase) == "done" and float(st.t) > 3.8 and not shots_taken.has("wall" + kind): # the face wall, flipped
			shots_taken["wall" + kind] = true
			capture("wall_" + kind)
		if str(st.phase) == "podium" and float(st.t) > 4.0 and not shots_taken.has("podium_shot"):
			shots_taken["podium_shot"] = true
			capture("podium")
		if str(st.phase) == "podium" and not shots_taken.has("podium"):
			shots_taken["podium"] = true
			print("SHOW_BOT podium crown=", st.crown, " pts=", st.pts)
		if str(st.phase) == "podium":
			for slot in players: # the bots try to walk away and dash every tick
				sim._local_commands[slot] = {"move": Vector2(1.0, -1.0), "action": false}
				sim._local_dashes[slot] = 1
				var kept: Dictionary = flow.minigame._hold
				if kept.has(slot):
					var spot: Vector3 = kept[slot].at
					var here: Vector3 = sim.actors[slot].position
					podium_worst = maxf(podium_worst, Vector2(here.x - spot.x, here.z - spot.z).length())
			podium_ticks += 1
			if not sim.hold_yaw is float: podium_facing = false
		if str(st.phase) == "play" and kind == "survival" and (flow.minigame.fell as Array).size() != fell_seen:
			fell_seen = (flow.minigame.fell as Array).size()
			print("SHOW_BOT   survival: ", fell_seen, " fallen at ", snappedf(float(st.t), 0.1), " s (fell ", flow.minigame.fell, ")")
		if str(st.phase) != "play" and kind == "survival": fell_seen = 0
		if kind == "survival" and str(st.phase) in ["play", "done"] and flow.minigame.pigeons.enabled and (flow.minigame.pigeons.birds as Dictionary).size() > bird_rows: # GHOST PIGEON (docs/pigeon.md): a fallen player is a bird (the app's local role flies it)
			bird_rows = (flow.minigame.pigeons.birds as Dictionary).size()
			print("SHOW_BOT   pigeon: ", bird_rows, " bird(s) at ", snappedf(float(st.t), 0.1), " s: ", (st.get("pigeon", {}) as Dictionary).get("b", []))
		if str(st.phase) == "card": bird_rows = 0
		if str(st.phase) == "play":
			if stop_at >= 0.0 and kind == "race" and float(st.t) >= stop_at:
				capture("race_%d" % int(stop_at))
				print("SHOW_BOT stopped at the race, frames only")
				stopped = true
				return
			for slot in players: drive(slot, st, kind, clock - round_start)
			var egg = flow.minigame.items.rules_of.get("eggplant") if flow.minigame.items != null else null
			if egg != null and egg.active: egg_log[tag] = {"given": egg.given, "passes": egg.passes, "popped": egg.popped}
			if dash_at >= 0.0 and kind == "race" and float(st.t) >= dash_at: _dash_shot()
			if bonk_shot and kind == "race": _bonk_shot()
			if stopped: return
			var key := "%s:%s" % [kind, int(st.t) / 20]
			if shots != "" and not shots_taken.has(key) and int(st.t) % 20 == 4:
				shots_taken[key] = true
				capture("%s_%d" % [kind, int(st.t)])
			var across: Array = flow.minigame.across
			for slot in players:
				if across.has(slot) and not finished_at.has("%s:%d" % [kind, slot]):
					finished_at["%s:%d" % [kind, slot]] = snappedf(clock - round_start, 0.1)
					round_log[-1].text += "bot%d %.1fs " % [slot, clock - round_start]
		elif str(st.phase) == "done" and not round_log.is_empty() and round_log[-1].text == "": round_log[-1].text = "nobody across"
		if clock - stuck_report > (4.0 if trace else 15.0) and str(st.phase) == "play":
			stuck_report = clock
			var at: Vector3 = sim.actors[0].global_position
			print("SHOW_BOT   ", kind, " t=", snappedf(float(st.t), 0.1), " bot0 idx=", route_index[0], " at=", at.snapped(Vector3.ONE * 0.1), " bot1 idx=", route_index[1], " fell=", st.get("fell", []))
	await frames(30)

## Frames of the first bonk (--bonk-shot): a throw is a horizontal speed over 8 m/s in the air with the upward kick, which walking (6 m/s) and a jump never make.
func _bonk_shot() -> void:
	var body: CharacterBody3D = sim.actors[0]
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if bonk_wait < 0:
		if not body.is_on_floor() and speed > 8.0 and body.velocity.y > 3.0 and bonk_prev_speed < 8.0 and body.global_position.z < bonk_z:
			bonk_wait = 9
			print("SHOW_BOT bonk thrown at ", body.global_position.snapped(Vector3.ONE * 0.1), " speed ", snappedf(speed, 0.1), " m/s up ", snappedf(body.velocity.y, 0.1))
	else:
		bonk_wait -= 1
		if bonk_wait == 0:
			capture("race_bonk")
			stopped = true
	bonk_prev_speed = speed

## Frames of the dash (--dash-at): bot 0 presses DASH (after a jump with --dash-air) the way a player would, and the dash is shot 0.12 s into it.
func _dash_shot() -> void:
	dash_ticks += 1
	if dash_phase == 0:
		dash_phase = 1
		dash_ticks = 0
		if dash_air: sim._local_jumps[0] = 1
		else: dash_phase = 2
	if dash_phase == 1 and dash_ticks >= 14: dash_phase = 2
	if dash_phase == 2 and sim._local_dashes[0] == 0 and not _dash_sent:
		_dash_sent = true
		dash_ticks = 0
		sim._local_dashes[0] = 1
		print("SHOW_BOT dash pressed at ", sim.actors[0].global_position.snapped(Vector3.ONE * 0.1), " grounded=", sim.actors[0].is_on_floor())
	if _dash_sent and flop_shots:
		_flop_shot()
		return
	if _dash_sent and dash_ticks == 7:
		var speed := Vector2(sim.actors[0].velocity.x, sim.actors[0].velocity.z).length()
		print("SHOW_BOT dash frame: speed ", snappedf(speed, 0.1), " m/s, height ", snappedf(sim.actors[0].global_position.y, 0.01), " grounded=", sim.actors[0].is_on_floor())
		capture("race_dash")
		stopped = true

## --flop-shots: after the dash the courier lands on its belly (shoulder view, then a free camera from its side), later it gets up (the same two views).
func _flop_shot() -> void:
	var motion = sim.motions[0]
	var left: float = motion.flop_left
	var body: Node3D = sim.actors[0]
	var side := Transform3D(Basis.IDENTITY, body.global_position + Vector3.LEFT.rotated(Vector3.UP, motion.yaw) * 3.0 + Vector3(0.0, 0.7, 0.0)).looking_at(body.global_position + Vector3(0.0, 0.3, 0.0), Vector3.UP)
	match flop_stage:
		0:
			if left > 0.0 and left <= motion.FLOP_TIME - 0.35:
				print("SHOW_BOT belly flop: flop_left ", snappedf(left, 0.01), " speed ", snappedf(Vector2(body.velocity.x, body.velocity.z).length(), 0.1), " m/s")
				capture("race_flop")
				flop_stage = 1
				_side_shot("race_flop_side", side, false)
		1:
			if left > 0.0 and left <= 0.15:
				print("SHOW_BOT get-up: flop_left ", snappedf(left, 0.01))
				capture("race_getup")
				flop_stage = 2
				_side_shot("race_getup_side", side, true)

## A free camera for one frame: the show's view resets `view_override` every physics tick, so it is set here (after the tick) and drawn by the
## very next process frame, which is when the camera follows it.
func _side_shot(label: String, view: Transform3D, finish: bool) -> void:
	for i in 3: # the view's tick may clear it in between: set and apply it again each time, then draw twice
		sim.view_override = view
		sim._update_camera(0.0)
		await process_frame
	sim.view_override = view
	sim._update_camera(0.0)
	RenderingServer.force_draw(false)
	capture(label)
	sim.view_override = null
	if finish: stopped = true

## One bot's input for this physics frame: walk the route, jump at gaps and ledges, never twice within 0.35 s.
func drive(slot: int, st: Dictionary, kind: String, since: float) -> void:
	var across: Array = flow.minigame.across
	var status: Array = st.status if st.has("status") else []
	if across.has(slot) or (status.size() > slot and int(status[slot]) >= 2): return
	var level := int(st.level)
	var world: Node3D = sim.level_world
	var body: CharacterBody3D = sim.actors[slot]
	if kind == "survival":
		_survive(slot, level)
		return
	var route: PackedVector3Array = world.route(level)
	if route.is_empty(): return
	var origin := Vector3.ZERO # route() is in world coordinates already
	var here := body.global_position
	var index: int = route_index[slot]
	while index < route.size() - 1:
		var waypoint: Vector3 = route[index] + origin
		var flat := Vector2(waypoint.x - here.x, waypoint.z - here.z)
		if flat.length() < 1.1 and absf(waypoint.y - here.y) < 2.6: index += 1
		else: break
	var back := _door_back(level) # a level of poster doors: the waypoints a bot has run past (it went through the logo poster, not by the waypoint) are done
	while back != Vector3.ZERO and index < route.size() - 1 and (route[index] + origin - here).dot(back) > 0.6: index += 1
	# a respawn put the bot back along the route: follow the nearest earlier point again
	var progress: float = world.route_progress(level, here)
	if progress + 6.0 < float(last_progress[slot]):
		print("SHOW_BOT   ", kind, " bot", slot, " set back from route ", snappedf(float(last_progress[slot]), 0.1), " m (index ", index, ") to ", snappedf(progress, 0.1), " m, last seen ", (prior[slot] as Vector3).snapped(Vector3.ONE * 0.1), " t=", snappedf(since, 0.1))
		index = maxi(0, mini(index, _nearest(route, origin, here) + 1))
		last_progress[slot] = progress
	else: last_progress[slot] = maxf(float(last_progress[slot]), progress)
	route_index[slot] = index
	prior[slot] = here
	var target: Vector3 = route[mini(index, route.size() - 1)] + origin
	var gate := _door_row(level, here)
	if not gate.is_empty(): target = gate.aim
	var wanted := Vector2(target.x - here.x, target.z - here.z)
	if wanted.length() < 0.05: return
	var heading := wanted.normalized()
	var prey := _egg_prey(slot, here) # carrying the HOT EGGPLANT: run at the nearest racer to bump it on
	if prey != Vector3.ZERO:
		wanted = Vector2(prey.x - here.x, prey.z - here.z)
		heading = wanted.normalized()
	var on_floor := body.is_on_floor()
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	# an edge 0.7 m ahead: jump when something to land on is in reach now (moving platforms come and go), else wait for it
	var waiting := false
	var edge := false
	var landing := false
	var flat_ahead := Vector3(heading.x, 0.0, heading.y)
	if on_floor:
		var floor_ahead := _floor(here + flat_ahead * 0.7)
		edge = is_nan(floor_ahead) or floor_ahead < here.y - 0.7
		if edge:
			for distance in [1.4, 2.0, 2.7, 3.4]:
				var y := _floor(here + flat_ahead * distance)
				if not is_nan(y) and y > here.y - 1.6 and y < here.y + 1.2: landing = true # a bonk can leave a bot on a rail 1.1 m over the floor: stepping down is a landing too
			waiting = not landing
	# held up (a sweeper, a crate): sidestep to one side for a second
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if on_floor and speed < 0.5 and wanted.length() > 1.5 and not waiting: held[slot] += 1.0 / 60.0
	else: held[slot] = 0.0
	if float(held[slot]) > 0.4 and clock > float(dodge_until[slot]):
		var blocker := _blocker(here, heading)
		var perp := heading.orthogonal()
		if perp.dot(Vector2(here.x - blocker.x, here.z - blocker.z)) < 0.0: perp = -perp
		dodge[slot] = perp
		dodge_until[slot] = clock + 1.0
	var move := heading
	if clock < float(dodge_until[slot]) and not edge: move = (heading * 0.35 + (dodge[slot] as Vector2)).normalized()
	if waiting: move = Vector2.ZERO
	if not gate.is_empty() and bool(gate.hold): # a poster that slides is not where the bot would meet it: wait here, sidestepping towards it
		move = gate.sidestep
		held[slot] = 0.0
	var can_jump := on_floor and clock - float(jumped_at[slot]) > 0.35
	if can_jump and ((edge and landing) or (not edge and (target.y - here.y > 0.55 and wanted.length() < 3.0 or float(held[slot]) > 0.4))):
		sim._local_jumps[slot] = 1
		jumped_at[slot] = clock
	if bot_dash and on_floor and not edge and not waiting and move != Vector2.ZERO and float(held[slot]) < 0.1 and clock - float(dashed_at[slot]) > 1.05 and clock - float(jumped_at[slot]) > 0.5 and wanted.length() > 4.5:
		var ahead := Vector3(move.x, 0.0, move.y)
		var floor_far := _floor(here + ahead * 4.0)
		var floor_near := _floor(here + ahead * 2.0)
		var space: PhysicsDirectSpaceState3D = (sim.level_world as Node3D).get_world_3d().direct_space_state
		var from := here + Vector3(0.0, 0.8, 0.0)
		var clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + ahead * 4.2, 1 | 16)).is_empty()
		if clear and not is_nan(floor_far) and not is_nan(floor_near) and absf(floor_far - here.y) < 0.3 and absf(floor_near - here.y) < 0.3:
			sim._local_dashes[slot] = 1
			dashed_at[slot] = clock
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands

## The HOT EGGPLANT (the experiment, docs/items.md) in the race the bots ran: the clock strapped it on a bot at least once (the first at 12-16 s, a bot race takes 29-35 s or more) and, with one bot alone,
## it popped (time or the goal: nobody to pass it to). Passes between two bots are only reported: a slowed carrier is chased, not always caught. A race level the switch leaves out has no entry.
func _egg_checks() -> void:
	print("SHOW_BOT eggplant ", egg_log)
	for tag: String in egg_log.keys():
		var row: Dictionary = egg_log[tag]
		check(int(row.given) >= 1, "the clock strapped the HOT EGGPLANT on a bot in round %s (given %d, passed %d, popped %d)" % [tag, int(row.given), int(row.passes), int(row.popped)])
		if players == 1 or solo: check(int(row.popped) >= 1 and int(row.passes) == 0, "alone it pops on the player and is never passed (popped %d, passed %d)" % [int(row.popped), int(row.passes)])

## The HOT EGGPLANT (the experiment): a bot that carries it heads for the nearest other racer within EGG_CHASE metres (on about the same level) until it has passed it on; Vector3.ZERO for none.
const EGG_CHASE := 9.0
func _egg_prey(slot: int, here: Vector3) -> Vector3:
	var items = flow.minigame.items
	if items == null or not items.enabled or items.fx_of(slot, "eggplant").is_empty(): return Vector3.ZERO
	var best := Vector3.ZERO
	var best_gap := EGG_CHASE
	for other: int in items.racers():
		if other == slot: continue
		var there: Vector3 = sim.actors[other].global_position
		var gap := Vector2(there.x - here.x, there.z - here.z).length()
		if gap < best_gap and absf(there.y - here.y) < 1.5:
			best_gap = gap
			best = there
	return best

## POSTER RUSH: the wall of poster doors ahead (levels/poster_doors.gd; a level without doors has none). The bot runs at the logo poster (an open or torn door),
## from DOOR_LOOK metres out, at the place the poster WILL be when the bot gets there: a poster that slides is read on the level clock, as a player times it on
## the screen. DOOR_HOLD metres from the wall the bot waits, sidestepping towards the opening, while the opening would be too far from it when it arrived.
## {aim (world, a point just past the wall), hold (wait and sidestep), sidestep (unit, across)} for the nearest wall within reach, {} for none.
func _door_row(level: int, here: Vector3) -> Dictionary:
	var world: Node3D = sim.level_world
	var doors: Array = world._levels[level].doors
	if doors.is_empty(): return {}
	var origin: Vector3 = world.level_origin(level)
	var local := here - origin
	var now: float = world.clock
	var plane := INF
	for door: Dictionary in doors:
		if str(door.kind) == PosterDoors.SOLID: continue
		var ahead := PosterDoors.frame(door, local, PosterDoors.travel(door, now)).z # metres in front of the wall, negative once through
		if ahead > -DOOR_PAST and ahead <= DOOR_LOOK: plane = minf(plane, ahead)
	if plane == INF: return {}
	var best := {}
	var best_gap := INF
	for door: Dictionary in doors:
		if str(door.kind) == PosterDoors.SOLID: continue
		var ahead := PosterDoors.frame(door, local, PosterDoors.travel(door, now)).z
		if absf(ahead - plane) > 0.05: continue
		var arrive := now + maxf(ahead, 0.0) / (WALK_SPEED * pace)
		var centre: Vector3 = (door.p as Vector3) + PosterDoors.travel(door, arrive)
		var right: Vector3 = door.right
		var normal: Vector3 = door.normal
		var across := (local - centre).dot(right)
		if absf(across) >= best_gap: continue
		best_gap = absf(across)
		best = {"aim": Vector3(origin.x + centre.x - normal.x * 1.6, here.y, origin.z + centre.z - normal.z * 1.6),
			"hold": ahead > DOOR_GO and ahead <= DOOR_HOLD and absf(across) > DOOR_ALIGN, "sidestep": -Vector2(right.x, right.z) * signf(across)}
	return best

## The way a level's poster doors face (the course runs the other way), ZERO for a level without doors.
func _door_back(level: int) -> Vector3:
	if not door_normals.has(level):
		var doors: Array = (sim.level_world as Node3D).get("_levels")[level].doors
		door_normals[level] = (doors[0].normal as Vector3) if not doors.is_empty() else Vector3.ZERO
	return door_normals[level]

## Survival: a level with `cues` (PICTURE MATCH) is played by _match, a level with step tiles (LAST TILE STANDING) by _walk_tiles.
func _survive(slot: int, level: int) -> void:
	if flow.minigame.play == "badge":
		_logo(slot)
		return
	if FileAccess.get_file_as_string("res://levels/level_%02d.json" % (level + 1)).contains("\"cues\""):
		_match(slot, level)
		return
	if not _bar_list(level).is_empty():
		_bars(slot, level)
		return
	if not _ring_list(level).is_empty():
		_ring(slot, level)
		return
	if sim.level_world.tile_count(level) > 0: _walk_tiles(slot, level)

## KEEP THE LOGO: a bot without a logo walks at the nearest wearer and GRABs it when in reach; one with a logo walks away from the nearest courier without one.
func _logo(slot: int) -> void:
	var st: Dictionary = flow.minigame.state()
	var body: CharacterBody3D = sim.actors[slot]
	var wearing: bool = (st.badge as Array).has(slot)
	var near := Vector3.ZERO
	var best := INF
	for other: int in (st.field as Array):
		if other == slot or (st.badge as Array).has(other) != (not wearing): continue
		var gap := ((sim.actors[other] as Node3D).global_position - body.global_position) * Vector3(1, 0, 1)
		if gap.length() < best:
			best = gap.length()
			near = gap
	var toward := Vector2(near.x, near.z) * (1.0 if not wearing else -1.0)
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	var move := toward.normalized() if best < INF and toward.length() > 0.3 else Vector2.ZERO
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands
	if not wearing and best < 1.1 and Engine.get_physics_frames() % 20 == 0: sim.team.note_presses(slot, 0, 1)

var ring_cache := {} ## level -> [{middle: Vector2, r: radius, t: level clock the floor drops}] of the cylinder floors of the level file (SHOVE RING), read once
const RING_HOME := 1.0 ## m from the middle of the standing floor where a bot waits (the two bots on opposite sides)
const RING_SAFE := 2.5 ## s: a floor counts as gone this long before it drops (it shakes over its warning)

func _ring_list(level: int) -> Array:
	if not ring_cache.has(level):
		var list := []
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://levels/level_%02d.json" % (level + 1)))
		if data is Dictionary and not bool(data.get("arena", false)):
			for source: Dictionary in data.get("hazards", []):
				var h: Dictionary = Hazards.normalize(source)
				if h.is_empty() or str(h.k) != "blink": continue
				for part: Dictionary in h.parts:
					if str(part.k) != "cyl": continue
					var at: Vector3 = (h.pivot as Vector3) + (part.xf as Transform3D).origin
					list.append({"middle": Vector2(at.x, at.z), "r": float(part.d) * 0.5, "t": float(h.on_time) - float(h.phase)})
		ring_cache[level] = list
	return ring_cache[level]

## SHOVE RING: the bots shove nobody. Each stands near the middle of the biggest floor that will still be there in RING_SAFE seconds (it reads the
## drops off the level file, as a player reads the shaking rings), the two on opposite sides, so the shrinking floor never takes them before the
## last disc goes. A bonk or a shove from outside sends it back.
func _ring(slot: int, level: int) -> void:
	var body: CharacterBody3D = sim.actors[slot]
	var origin: Vector3 = sim.level_world.level_origin(level)
	var here := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	var clock_now: float = sim.level_world.clock
	var best := {}
	for ring: Dictionary in _ring_list(level):
		if float(ring.t) - RING_SAFE <= clock_now: continue
		if best.is_empty() or float(ring.r) > float(best.r): best = ring
	var move := Vector2.ZERO
	if not best.is_empty():
		var home: Vector2 = (best.middle as Vector2) + Vector2.from_angle(PI * slot) * minf(RING_HOME, float(best.r) * 0.3)
		var wanted := home - here
		if wanted.length() > 0.3: move = wanted.normalized()
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands

var bars_cache := {} ## level -> the normalized `spin` hazards of the level file (SPIN BARS), read once
const BAR_REACH := 0.5    ## m: a bar this close to the bot's middle touches it (the bar is 0.25 m to the side of its axis, the body 0.4 m across)
const BAR_LOOK := 0.95    ## s the bot looks ahead; a jump is above a 0.75 m bar from 0.14 to 0.69 s: it jumps when the bar's pass is centred there (0.42 s from now)
const BAR_HOME := [[0.0, 2.0], [8.0, 4.5], [36.0, 3.4]] ## [from level clock, m from the middle]: the pedestal first, then where the slow bar passes fast enough to jump, then the core

func _bar_list(level: int) -> Array:
	if not bars_cache.has(level):
		var list := []
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://levels/level_%02d.json" % (level + 1)))
		if data is Dictionary and bool(data.get("arena", false)):
			for source: Dictionary in data.get("hazards", []):
				if str(source.get("k", "")) == "spin": list.append(Hazards.normalize(source))
		bars_cache[level] = list
	return bars_cache[level]

## The nearest bar part to the point (level-local x/z) at level clock `t`: {gap (m, 0 inside), top (height of the part's top), away (unit, from the part to the point)}.
func _bar_gap(level: int, t: float, point: Vector2) -> Dictionary:
	var best := {"gap": INF, "top": 0.0, "away": Vector2.ZERO}
	var pose := Hazards.Pose.new()
	for h: Dictionary in _bar_list(level):
		Hazards.pose(h, t, pose)
		var frame := Transform3D(pose.basis, pose.position)
		for part: Dictionary in h.parts:
			var box: Transform3D = frame * (part.xf as Transform3D)
			var size: Vector3 = part.size
			var along := Vector2(box.basis.x.x, box.basis.x.z).normalized()
			var across := Vector2(-along.y, along.x)
			var off := point - Vector2(box.origin.x, box.origin.z)
			var out := Vector2(off.dot(along) - clampf(off.dot(along), -size.x * 0.5, size.x * 0.5), off.dot(across) - clampf(off.dot(across), -size.z * 0.5, size.z * 0.5))
			if out.length() < float(best.gap):
				var side := across * (1.0 if off.dot(across) >= 0.0 else -1.0)
				best = {"gap": out.length(), "top": box.origin.y + size.y * 0.5, "away": (along * out.x + across * out.y).normalized() if out.length() > 0.01 else side}
	return best

## SPIN BARS: the bot waits at BAR_HOME[clock] from the middle (the two bots on opposite sides). It looks BAR_LOOK seconds ahead at the bars on the
## level clock (as a player looks at them on screen; its own walking velocity included): a bar that passes quickly is jumped, timed so the pass is
## in the middle of the jump (never twice within 0.5 s); a bar that is slow where the bot stands (near the middle: no jump is long enough) is
## sidestepped. It walks back home after a bonk. The floor shrinks under it: the core goes last, so a bot that dodges every bar still falls with it.
func _bars(slot: int, level: int) -> void:
	var body: CharacterBody3D = sim.actors[slot]
	var origin: Vector3 = sim.level_world.level_origin(level)
	var here := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	var clock_now: float = sim.level_world.clock
	var radius := 2.0
	for step: Array in BAR_HOME:
		if clock_now >= float(step[0]): radius = float(step[1])
	var home := Vector2.from_angle(PI * slot + 0.5) * radius
	var wanted := home - here
	var move := wanted.normalized() if wanted.length() > 0.3 else Vector2.ZERO
	var feet: float = body.global_position.y - origin.y
	var drift := Vector2(body.velocity.x, body.velocity.z)
	if body.is_on_floor():
		var first := -1.0
		var last := -1.0
		var away := Vector2.ZERO
		var tau := 0.0
		while tau <= BAR_LOOK:
			var near := _bar_gap(level, clock_now + tau, here + drift * tau)
			if float(near.gap) < BAR_REACH and float(near.top) > feet + 0.05:
				if first < 0.0:
					first = tau
					away = near.away
				last = tau
			elif first >= 0.0: break
			tau += 1.0 / 60.0
		if first >= 0.0:
			if last - first > 0.55 or last >= BAR_LOOK - 0.02:
				if first < 0.5: move = away # too slow to jump over from here: step out of its way
			elif (first + last) * 0.5 <= 0.42 and clock - float(jumped_at[slot]) > 0.5:
				sim._local_jumps[slot] = 1
				jumped_at[slot] = clock
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands

## LAST TILE STANDING and the stage rounds (levels 25-28: square or hexagon tiles, 4 m or 3.5 m across): the bot walks to the nearest tile that nobody has stood on
## yet (a step byte of 0: stepped, settled and never-there tiles are all non-zero, wrapped levels included) on the floor it is on, leaning away from the nearest other
## courier, so a trail of falling tiles follows it. It never jumps, so when the tiles around it are gone it walks off the edge: down to the next floor, in
## the end into the kill volume. A bot that has the floor to itself lasts as long as its trail allows.
func _walk_tiles(slot: int, level: int) -> void:
	var world: Node3D = sim.level_world
	var origin: Vector3 = world.level_origin(level)
	var data: Dictionary = world._levels[level].data.tiles
	var steps: PackedByteArray = flow.minigame.tiles
	var body: CharacterBody3D = sim.actors[slot]
	var here := body.global_position - origin
	var other := Vector3(INF, 0.0, INF) # nobody to lean away from when alone
	for rival in players:
		if rival == slot or not sim.is_slot_active(rival): continue
		var rival_at := (sim.actors[rival] as Node3D).global_position - origin
		if other.x == INF or Vector2(rival_at.x - here.x, rival_at.z - here.z).length() < Vector2(other.x - here.x, other.z - here.z).length(): other = rival_at
	var best := INF
	var goal := Vector3(here.x, here.y, here.z) + Vector3(1.0, 0.0, 0.0) * (1.0 if slot == 0 else -1.0) * 20.0 # nothing left on this floor: off the edge
	for index in steps.size():
		if steps[index] != 0: continue
		var at: Vector3 = data.tiles[index].p
		if absf(at.y - here.y) > 1.0: continue
		var gap := Vector2(at.x - here.x, at.z - here.z).length()
		if gap < 0.6: continue
		var score := gap + 0.03 * Vector2(at.x, at.z).length() - (0.25 * Vector2(at.x - other.x, at.z - other.z).length() if other.x != INF else 0.0) # the hexagons around it tie on distance: the one nearer the middle wins, so the trail curls inwards instead of running off the edge
		if score < best:
			best = score
			goal = at
	var wanted := Vector2(goal.x - here.x, goal.z - here.z)
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	var move := wanted.normalized() if wanted.length() > 0.2 else Vector2.ZERO
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands

## PICTURE MATCH: while a cue shows, the bot walks to the nearest tile that shows the cue's picture and still stands after the drop (what a
## player who reads the screen does); between cues it stays put. With --dumb bot 1 never moves.
func _match(slot: int, level: int) -> void:
	if match_level.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://levels/level_%02d.json" % (level + 1)))
		match_level = {"cues": data.cues, "tiles": []}
		for source in data.hazards:
			var h: Dictionary = Hazards.normalize(source)
			for part: Dictionary in h.parts:
				if str(part.slot) != "": match_level.tiles.append({"p": (h.pivot as Vector3) + (part.xf as Transform3D).origin, "slot": str(part.slot), "h": h})
	var clock_now: float = sim.level_world.clock
	var body: CharacterBody3D = sim.actors[slot]
	var origin: Vector3 = sim.level_world.level_origin(level)
	var move := Vector2.ZERO
	for cue: Dictionary in match_level.cues:
		if clock_now < float(cue.t) or clock_now >= float(cue.until) or (dumb and slot == 1): continue
		var best := INF
		var goal := Vector3.ZERO
		for tile: Dictionary in match_level.tiles:
			if str(tile.slot) != str(cue.slot): continue
			var pose := Hazards.Pose.new()
			Hazards.pose(tile.h, float(cue.until) + 1.0, pose)
			if not pose.active: continue
			var gap := (origin + (tile.p as Vector3)).distance_to(body.global_position)
			if gap < best:
				best = gap
				goal = origin + (tile.p as Vector3)
		var wanted := Vector2(goal.x - body.global_position.x, goal.z - body.global_position.z)
		if best < INF and wanted.length() > 0.35: move = wanted.normalized()
	var yaw: float = sim.local_camera_yaws[slot] if sim._split_views() else sim.yaw
	var local := Basis(Vector3.UP, -yaw) * Vector3(move.x, 0.0, move.y)
	var commands: Dictionary = sim._local_commands[slot]
	commands["move"] = Vector2(local.x, -local.z) * pace
	sim._local_commands[slot] = commands

## Where the thing in front of a held bot is (its position), a point straight ahead when nothing answers.
func _blocker(here: Vector3, heading: Vector2) -> Vector3:
	var space: PhysicsDirectSpaceState3D = (sim.level_world as Node3D).get_world_3d().direct_space_state
	var from := here + Vector3(0.0, 0.8, 0.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(heading.x, 0.0, heading.y) * 1.2, 1 | 16))
	if hit.is_empty() or not hit.collider is Node3D: return here + Vector3(heading.x, 0.0, heading.y)
	return (hit.collider as Node3D).global_position

## The floor under `point` in the physics world now (moving platforms included), NAN for none.
func _floor(point: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = (sim.level_world as Node3D).get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3(0.0, 1.6, 0.0), point + Vector3(0.0, -7.0, 0.0), 1 | 16))
	return NAN if hit.is_empty() else float(hit.position.y)

func _nearest(route: PackedVector3Array, origin: Vector3, here: Vector3) -> int:
	var best := 0
	var best_distance := INF
	for index in route.size():
		var distance := (route[index] + origin).distance_to(here)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best
