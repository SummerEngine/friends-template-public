extends SceneTree
## THE SHOW through the real online flow (docs/party-show.md), headless, without a transport: the authority's match controller and
## shell with scripted players and replicas that follow its snapshots and draw the show's view and HUD as client/main.gd does.
##   A. two players (POINTS: nobody is eliminated): the lobby circle "THE SHOW", PLAY, race -> survival -> final in that order, every
##      round awards placement points (the final scores like any round), the crown goes to the highest total, the podium, results, Play Again.
##   B. then four more players join, six in all (ELIMINATION): 4 qualify from the race (one racer falls into a kill volume on the way and
##      is put back at its checkpoint), 2 survive the survival, the final is between those two, the first to the crown wins; the
##      four who are out spectate (the view sets spectate_slot, the leader is followed); the podium camera; results; the lobby again.
## Poses are scripted fixtures: each racer follows the level's route at its own speed. Run (never windowed):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer> --headless --audio-driver Dummy --rendering-driver dummy \
##     --fixed-fps 60 --path demo -s "$PWD/tools/modes/show_check.gd"
## Frames (offscreen binary only, never windowed; --touch adds the phone overlay, --resolution 844x390 is a phone):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 900 <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s "$PWD/tools/modes/show_check.gd" -- --shots=<dir> --only=A|B [--touch]
## (the offscreen binary ends a script after about 30 s: one scenario per run)
## LAST TILE STANDING (level 15, step tiles: `--show-level=15`): in the survival a player who stands still stops a tile under them, which is gone for
## the authority, both replicas and a replica that joins after it went, while the walkers' trail of tiles is gone too (tile_asserts).
##   C. (between A and B, the two players are still alone in the lobby) a lobby circle of ONE round: the first race circle (and the KEEP THE LOGO circle when the lineup lists it: `-- --all-rounds`),
##      each played through the real flow: one round, then the podium room for the winner, the results name the winner, Play Again.
##   D. (after B, the six are in the lobby; only with `-- --all-rounds`: KEEP THE LOGO is hidden from the lobby by modes/lineup/lineup.json) KEEP THE LOGO from its circle with six players: one who wears none walks up to one who does and GRABs it (the real
##      contact), the logo changes hands, both views draw the plates on the right couriers and tell it in the event line; the round ends at its cap with the
##      logo wearers through, the others out.
##   E. (after C, the two are in the lobby; four players in all) a STAGE round (a tile stage level, `RoundList` circle of the first stage level) through the real flow: the card is a
##      title and the digits 3, 2, 1 (a second apart) and GO, the objective pill (no objective text top left), CURRENT ELIMINATIONS n/M with a red-X pill for each who fell, the two who fall
##      spectate (note `SPECTATING`), the survivors' VICTORY banner, then the results of the one round. Then, without the engine flow, the same stage rules and views for
##      TWELVE players (4 go through: M = 8) and three (points: need 1) on a host of the script's: the countdown and VICTORY timings, the pills' data, the feed (at most 4,
##      each gone after 3.5 s), the eliminations count and that a race round's card is still 4 s.
## Prints SHOW_CHECK ok=<bool> last; exits 1 on a failure.
const Game := preload("res://network/game.gd")
const OwnerPoseWire := preload("res://network/owner_pose_wire.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const CourseSection := preload("res://course_section.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const Plates := preload("res://modes/show/plates.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const SEATS := 6

class Controller extends "res://network/match_controller.gd":
	var inbox := {} ## seat -> pose sent this tick
	var commands := {}
	var documents: Array = []
	func _apply_owner_poses() -> void:
		for seat: int in inbox.keys():
			var pose: Dictionary = inbox[seat]
			inbox.erase(seat)
			var slot := _slot(seat)
			fresh_at[seat] = elapsed
			owner_expired.erase(seat)
			var accepted := {}
			if slot >= 0 and simulation.queue_authority_owner_pose(slot, pose): accepted = pose
			var command: Dictionary = commands.get(seat, {"seq": 1, "move": [0.0, 0.0]})
			_note_owner_input(seat, command, accepted)
			if slot >= 0: simulation.set_player_input(slot, command)
	func _publish() -> void:
		if baseline_burst > 0: baseline_burst -= 1
		var state: Dictionary = simulation.capture_network_state(baseline_burst > 0)
		state = Game.with_match_mode(state, match_queue)
		state.baseline = baseline_burst > 0
		state.players_joined = joined.size()
		state.server_elapsed = elapsed
		state.input_sequences = input_sequences.duplicate()
		state.waiting_for_partner = waiting_for_partner
		state.settlement_state = settlement_state
		state.match = _match_state()
		var document := Game.pack_snapshot(state)
		if not document.is_empty(): documents.append(document)
		if documents.size() > 60: documents.pop_front()
	func _conclude_world(_success: bool, _reason: String) -> void: pass
	func _reset_owner_streams() -> void: pass

var failures := 0
var controller: Controller
var sim: Node
var replicas: Array = []
var views: Array = [] ## per replica
var huds: Array = []
var viewers: Array = [] ## per replica: the slot it plays
var targets: Array = []
var sequence: Array = []
var sequence_epoch: Array = []
var pilots: Array = []
var race_falls := {} ## seat -> s into the race when it falls into a kill volume
var survival_falls := {} ## index in the field -> s into the survival when it falls
var largest := 0
var seen := {} ## label -> true
var rounds_seen: Array = [] ## "round:kind" in the order they came
var banners := {} ## slot -> Array of big words the HUD showed
var respawned := false
var spectated := false
var podium_camera := false
var podium_worst := 0.0 ## the largest x/z distance any held player got from its spot during the podium phase (the scripted pose walks away)
var podium_samples := 0
var crown_slot := -1 ## the champion, read in the podium phase
var podium_respawns: Array = [] ## per slot: the shell's respawn counter at the last podium tick
var podium_sent := 0 ## times the authority put a walker back on its spot during the podium
var podium_shot_ok := false ## the podium camera of every viewer frames the spots, the winner in the middle, the crown over it
var out_at := {} ## slot -> where the authority's courier stood when its slot went inactive (retired, or out of the round): it must never move
var out_drift := 0.0 ## the largest distance any such courier got from that spot
var follow_ok := 0 ## ticks an out viewer's camera followed the state's `lead` (somebody else, in the round)
var follow_bad := 0 ## ticks it followed somebody inactive, itself, or not the lead
var own_hidden := 0 ## ticks an out viewer's replica had its own slot inactive while it spectated
var last_state: Dictionary = {}
var shots := ""
var real_cast := false ## --cast=real: the project's own demo/cast (a brand sample copied there), not the fixture cast
var stage_nth := 0 ## --stage=<n>: scenario E (and the frames) play the n-th (0-based) stage round circle instead of the first (levels 25-28: 0 square A, 1 hex A, 2 square B, 3 hex B)
var only := "" ## "A", "B" or "C": one scenario (the offscreen binary ends a run after about 30 s)
var scenario := ""
var active_view := 0 ## shots: the replica whose camera and HUD are drawn
var shot_done := {}
var replica_epoch := {}
var mirror_seq := 0
var facing: Array = []
var round_seats: Array = [] ## the show's seats in slot order (a replica that joins late is given them)
var tile_walk := {} ## seat -> radians along its circle (tile level: the walkers of the survival)
const STAGE_RUN := 8.0 ## m/s a scripted runner of a stage round runs at (scenario E: the ones who do not fall)
const TILE_LEVEL := 14 ## 0-based: level_15.json, LAST TILE STANDING
const WALK_SPEED := 3.4 ## m/s of a scripted walker on the tile level
var stage_seen := {} ## scenario E: slot -> what that viewer's stage HUD showed: digits, go, pill, quest, victory, feed names, elim_n / elim_m
var notes := {} ## slot -> every HUD note the viewer saw
var StubRun: GDScript

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("SHOW_CHECK ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
		if argument.begins_with("--stage="): stage_nth = int(argument.trim_prefix("--stage="))
		if argument == "--cast=real": real_cast = true
	if shots != "": RenderingServer.render_loop_enabled = false # frames are drawn on demand (capture_pending): the rest runs at headless speed
	create_timer(850.0).timeout.connect(func() -> void:
		print("SHOW_CHECK FAIL timed out")
		print("SHOW_CHECK ok=false")
		quit(1))
	run.call_deferred()

func pose(seat: int, position: Vector3, yaw := 0.0, velocity := Vector3.ZERO) -> Dictionary:
	var epoch: int = sim.reset_count
	if sequence_epoch[seat] != epoch:
		sequence_epoch[seat] = epoch
		sequence[seat] = 0
	sequence[seat] += 1
	return {"version": OwnerPoseWire.VERSION, "seq": sequence[seat], "reset_epoch": epoch, "local_tick": sequence[seat], "time": float(sequence[seat]) / 60.0,
		"transform": Transform3D(Basis(Vector3.UP, yaw), position), "velocity": velocity, "grounded": true, "floor_normal": Vector3.UP,
		"yaw": yaw, "acceleration": Vector3.ZERO, "anchor": position + Vector3(0.0, 1.0, 0.0), "flop": 0}

func tick(count := 1) -> void:
	for i in count:
		for seat in SEATS:
			if not controller.joined.has(seat): continue
			var slot := controller._slot(seat)
			var here: Vector3 = sim.actors[slot].position if slot >= 0 else targets[seat]
			var next := drive(seat, slot, here)
			var step := Vector2(next.x - here.x, next.z - here.z)
			if step.length() > 0.01: facing[seat] = atan2(-step.x, -step.y)
			if controller.phase == "round" and controller.minigame != null and str(controller.minigame.phase) == "podium": facing[seat] = PI # a held owner faces the camera whatever its pose does (the shell's hold_yaw)
			var walking := Vector3(step.x, 0.0, step.y) * 60.0 if scenario == "D" else Vector3.ZERO # contact faces a player the way it last moved (its velocity): the thief's grab needs the victim in front
			controller.inbox[seat] = pose(seat, next, float(facing[seat]), walking)
		await physics_frame
		if controller.phase == "round" and controller.minigame != null: observe()
		if shots != "": capture_pending()

func wait_until(predicate: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if predicate.call(): return true
		await tick()
	return predicate.call()

func latest_state() -> Dictionary:
	if controller.documents.is_empty(): return {}
	var document: Dictionary = controller.documents[-1]
	largest = maxi(largest, (document.b as PackedByteArray).size())
	return Game.unpack_snapshot(document)

# ------------------------------------------------------------------ the scripted racers

## The pose a seat sends this tick: the lobby targets, then in a show round the route at the seat's own speed.
func drive(seat: int, slot: int, here: Vector3) -> Vector3:
	var rules = controller.minigame
	if slot < 0 or controller.phase != "round" or rules == null:
		var toward: Vector3 = targets[seat] - here
		return targets[seat] if toward.length() <= 0.08 else here + toward.normalized() * 0.08
	var st: Dictionary = rules.state()
	var pilot: Dictionary = pilots[seat]
	if int(st.round) != int(pilot.round):
		pilot.round = int(st.round)
		pilot.idx = 0
		pilot.falling = false
		pilot.fell = false
	if str(st.phase) == "podium": return here + Vector3(0.05, 0.0, 0.03) # the scripted pose does not hold still: it walks away from the podium
	if str(st.phase) != "play": return here
	var index: int = (st.field as Array).find(slot)
	if index < 0: return here # a spectator stays where it is
	var falls: Dictionary = survival_falls if str(st.kind) == "survival" else race_falls
	var key: int = index if str(st.kind) == "survival" else seat
	if str(st.kind) != "final" and falls.has(key) and rules.phase_time >= float(falls[key]) and not pilot.fell:
		pilot.falling = true
		if here.y < fall_depth(int(st.level)):
			pilot.fell = true
		else: return here + Vector3(0.0, -10.0, 0.0)
	if pilot.falling and here.y > -5.0:
		pilot.falling = false
		if str(st.kind) == "race": respawned = true
	if scenario == "D" and str(st.play) == "badge": return steal_step(seat, slot, here, st)
	if str(st.kind) == "survival":
		if int(st.level) == TILE_LEVEL and not survival_falls.has(index): return walk_circle(seat, here, index) # a walker leaves a trail of tiles
		if bool(st.stage) and not survival_falls.has(index): return here + Vector3(0.0, 0.0, STAGE_RUN / 60.0) # a stage round's runner runs straight ahead (+Z), a trail of cream tiles behind it
		return here # the others stand on the floor
	var route: PackedVector3Array = sim.level_world.route(int(st.level))
	if route.is_empty(): return here
	if pilot.idx == 0 or pilot.idx >= route.size(): pilot.idx = clampi(pilot.idx, 0, route.size() - 1)
	var speed := 0.13 - 0.012 * seat
	var target: Vector3 = route[pilot.idx]
	var offset := target - here
	if offset.length() < 0.35 and pilot.idx < route.size() - 1:
		pilot.idx += 1
		target = route[pilot.idx]
		offset = target - here
	if pilot.falling and here.y < -5.0: return here + Vector3(0.0, -1.0, 0.0)
	return here + offset.normalized() * minf(speed, offset.length()) if offset.length() > 0.001 else here

## How deep a scripted fall goes: into the kill volume of an ordinary level (10.5 m down); a tile stage round is out only on its ground floor (`stage.ground.y`), which can be 40 m down.
func fall_depth(level: int) -> float:
	var stage: Dictionary = CourseSection.level_stage(level)
	return -10.5 if stage.is_empty() else minf(-10.5, float(stage.ground.y) - 1.0)

## KEEP THE LOGO, scenario D: once the round has run 2 s the lowest slot that wears no logo walks up to the first logo wearer and GRABs (a press every third of a second
## until the logo is its own); everybody else stands.
func steal_step(seat: int, slot: int, here: Vector3, st: Dictionary) -> Vector3:
	if float(st.t) < 2.0: return here
	var wearers: Array = st.badge
	if int(steal.thief) < 0 and not wearers.is_empty():
		steal.victim = wearers[0]
		for candidate: int in (st.field as Array):
			if not wearers.has(candidate):
				steal.thief = candidate
				break
	if slot != int(steal.thief) or wearers.has(slot): return here
	if int(steal.grabbed_at) >= 0 and Engine.get_physics_frames() - int(steal.grabbed_at) > 300 and wearers.size() > 1: # no luck in 5 s (somebody stood in the way of the grab): go for the other wearer
		steal.victim = wearers[1] if int(steal.victim) == int(wearers[0]) else wearers[0]
		steal.outside = false
		steal.grabbed_at = -1
	var target: Vector3 = sim.actors[int(steal.victim)].position
	var middle: Vector3 = sim.level_world.level_origin(int(st.level))
	var outward := Vector3(target.x - middle.x, 0.0, target.z - middle.z).normalized()
	if not bool(steal.get("outside", false)): # out to an orbit clear of the start ring, round it to the far side of the victim, so the victim is the first courier in front when the thief walks in (a straight lap ran into the others standing on the ring)
		var orbit := 4.25
		var from := Vector2(here.x - middle.x, here.z - middle.z)
		var aim := Vector2(outward.x, outward.z)
		if from.length() < orbit - 0.3:
			var out := from.normalized() if from.length() > 0.01 else aim
			return here + Vector3(out.x, 0.0, out.y) * 0.1
		var turn := wrapf(aim.angle() - from.angle(), -PI, PI)
		if absf(turn) > 0.08:
			var next := from.normalized().rotated(signf(turn) * 0.1 / orbit) * orbit
			return Vector3(middle.x + next.x, here.y, middle.z + next.y)
		steal.outside = true
	var gap := Vector3(target.x - here.x, 0.0, target.z - here.z)
	if gap.length() > 0.9: return here + gap.normalized() * 0.1
	if Engine.get_physics_frames() % 20 == 0:
		var command: Dictionary = controller.commands[seat]
		command.grab_seq = int(command.get("grab_seq", 0)) + 1
		controller.commands[seat] = command
		if int(steal.grabbed_at) < 0: steal.grabbed_at = Engine.get_physics_frames()
	return here

## One step of a scripted walker on the tile level: a circle of radius 2.5 + 1.5 * index around the level's middle at WALK_SPEED, so it is
## always on a tile that has not been stood on yet (tiles go 0.75 s after the step, a tile of the logo kind 2.5 s).
func walk_circle(seat: int, here: Vector3, index: int) -> Vector3:
	var radius := 2.5 + 1.5 * index
	var middle: Vector3 = sim.level_world.level_origin(TILE_LEVEL)
	if not tile_walk.has(seat): tile_walk[seat] = atan2(here.z - middle.z, here.x - middle.x)
	tile_walk[seat] = float(tile_walk[seat]) + WALK_SPEED / 60.0 / radius
	var angle: float = tile_walk[seat]
	return Vector3(middle.x + cos(angle) * radius, here.y, middle.z + sin(angle) * radius)

# ------------------------------------------------------------------ what the clients see

func observe() -> void:
	var st: Dictionary = controller.minigame.state()
	last_state = st
	podium_watch(st)
	spectate_watch()
	var tag := "%d:%s" % [int(st.round), str(st.kind)]
	if str(st.phase) == "podium": tag = "podium"
	if rounds_seen.is_empty() or rounds_seen[-1] != tag:
		rounds_seen.append(tag)
		if shots != "": print("SHOW_CHECK round ", tag)
	if shots != "": mirror()
	if Engine.get_physics_frames() % 6 != 0: return
	var fresh := latest_state()
	var info: Dictionary = fresh.get("match", {})
	for index in replicas.size():
		var replica: Node = replicas[index]
		replica.apply_network_state(fresh, 0.1)
		var minigame: Variant = info.get("minigame", {})
		if not minigame is Dictionary or (minigame as Dictionary).is_empty(): continue
		var view: Node3D = views[index]
		view.present(minigame, 0.1)
		var model: Dictionary = view.hud(minigame)
		(huds[index] as Node).show_model(model if shots == "" or index == active_view else {})
		if shots != "" and index != active_view: (view.get("_wall") as CanvasLayer).visible = false # one window shows one player's wall
		var slot: int = viewers[index]
		if not banners.has(slot): banners[slot] = []
		var line := str(model.get("line", ""))
		if line != "" and not hud_lines.has(line): hud_lines.append(line)
		var big := str(model.get("big", ""))
		if big != "" and not (banners[slot] as Array).has(big): (banners[slot] as Array).append(big)
		var note := str(model.get("note", ""))
		if note != "":
			if not notes.has(slot): notes[slot] = []
			if not (notes[slot] as Array).has(note): (notes[slot] as Array).append(note)
		if scenario == "E": stage_record(slot, (view.get("_stage") as CanvasLayer).call("probe"))
		if int(replica.get("spectate_slot")) >= 0: spectated = true
		spectate_follow(replica, slot, minigame as Dictionary)
		if replica.get("view_override") is Transform3D: podium_camera = true

## Shots: the replicas stand where the authority's couriers are (the client's relay does this online).
func mirror() -> void:
	var fresh := latest_state()
	if fresh.is_empty(): return
	for replica: Node in replicas:
		var key := replica.get_instance_id()
		if bool(fresh.get("baseline", false)) and int(fresh.get("resets", -1)) != int(replica_epoch.get(key, -2)):
			if replica.seed_baseline(fresh): replica_epoch[key] = int(fresh.resets)
		for slot in controller.round_roster.size():
			var body: CharacterBody3D = sim.actors[slot]
			mirror_seq += 1
			var remote := pose(0, body.position, body.rotation.y)
			remote.seq = mirror_seq
			remote.reset_epoch = int(replica.get("_baseline_epoch"))
			replica.apply_remote_pose(slot, remote)
	for wanted: Dictionary in shot_list():
		if shot_done.has(wanted.name) or str(wanted.scenario) != scenario: continue
		if not bool(wanted.when.call(last_state)): continue
		shot_done[wanted.name] = true
		var index: int = int(wanted.view)
		if index >= replicas.size(): continue
		active_view = index
		for other in replicas.size():
			(huds[other] as Node).visible = other == index
			var plates: Variant = views[other].get("_plates") # the round card is a layer of its own: only the shown replica's
			if plates is CanvasLayer: (plates as CanvasLayer).visible = other == index
			var stage_layer: Variant = views[other].get("_stage") # ... and so is the stage round's HUD
			if stage_layer is CanvasLayer: (stage_layer as CanvasLayer).visible = other == index
		for child in root.get_children(): # ... and so is the sun: every replica's world (the lobby's too) lights the one window, a second sun doubles the light
			var sun: Node = child.get_node_or_null("World/LevelSun")
			if sun is Light3D: (sun as Light3D).visible = child == replicas[index]
		(replicas[index].get("camera") as Camera3D).make_current()
		shoot_after = 9 # a few frames for the camera and the HUD to settle
		shoot_name = "%s_%s" % [scenario, wanted.name]

var shoot_after := 0
var shoot_name := ""

func capture_pending() -> void:
	if shoot_after <= 0: return
	shoot_after -= 1
	if shoot_after > 0: return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("SHOW_CHECK shot ", shoot_name, " ", image.save_png("%s/%s.png" % [shots, shoot_name]) == OK)

func shot_list() -> Array:
	var in_play := func(kind: String, at: float) -> Callable:
		return func(st: Dictionary) -> bool: return str(st.kind) == kind and str(st.phase) == "play" and float(st.t) >= at
	var in_phase := func(kind: String, phase: String, at: float) -> Callable:
		return func(st: Dictionary) -> bool: return (kind == "" or str(st.kind) == kind) and str(st.phase) == phase and float(st.t) >= at
	if scenario == "A":
		return [
			{"name": "1_card_race", "scenario": "A", "view": 0, "when": in_phase.call("race", "card", 1.0)},
			{"name": "1b_card_survival", "scenario": "A", "view": 0, "when": in_phase.call("survival", "card", 1.0)},
			{"name": "1c_card_final", "scenario": "A", "view": 0, "when": in_phase.call("final", "card", 1.0)},
			{"name": "2_count", "scenario": "A", "view": 0, "when": in_phase.call("race", "card", 3.2)},
			{"name": "2b_go", "scenario": "A", "view": 0, "when": in_play.call("race", 0.3)},
			{"name": "2c_hint", "scenario": "A", "view": 0, "when": in_play.call("race", 3.0)},
			{"name": "3_race", "scenario": "A", "view": 0, "when": in_play.call("race", 9.0)},
			{"name": "4_race_done", "scenario": "A", "view": 0, "when": in_phase.call("race", "done", 0.7)},
			{"name": "4b_wall_points", "scenario": "A", "view": 0, "when": in_phase.call("race", "done", 3.8)},
			{"name": "5b_wall_survival", "scenario": "A", "view": 0, "when": in_phase.call("survival", "done", 3.8)},
			{"name": "5_survival", "scenario": "A", "view": 0, "when": in_play.call("survival", 12.0)},
			{"name": "6_final", "scenario": "A", "view": 0, "when": in_play.call("final", 14.0)},
			{"name": "7_podium", "scenario": "A", "view": 0, "when": in_phase.call("", "podium", 3.0)},
		]
	if scenario == "D":
		var thief_wears := func(st: Dictionary) -> bool: return str(st.play) == "badge" and str(st.phase) == "play" and int(steal.thief) >= 0 and (st.badge as Array).has(int(steal.thief)) and not (st.badge as Array).has(int(steal.victim)) and float(st.t) > 3.0
		return [
			{"name": "1_card", "scenario": "D", "view": 0, "when": in_phase.call("survival", "card", 1.0)},
			{"name": "2_play", "scenario": "D", "view": 0, "when": in_play.call("survival", 1.5)},
			{"name": "3_steal", "scenario": "D", "view": 0, "when": thief_wears},
			{"name": "4_done", "scenario": "D", "view": 0, "when": in_phase.call("survival", "done", 0.8)},
		]
	if scenario == "E":
		return [
			{"name": "1_title", "scenario": "E", "view": 0, "when": in_phase.call("survival", "card", 0.5)},
			{"name": "2_digit_3", "scenario": "E", "view": 0, "when": in_phase.call("survival", "card", 1.7)},
			{"name": "3_digit_1", "scenario": "E", "view": 0, "when": in_phase.call("survival", "card", 3.4)},
			{"name": "4_go", "scenario": "E", "view": 0, "when": in_play.call("survival", 0.3)},
			{"name": "5_play_pill", "scenario": "E", "view": 0, "when": in_play.call("survival", 2.0)},
			{"name": "9_run", "scenario": "E", "view": 0, "when": in_play.call("survival", 3.2)},
			{"name": "6_feed", "scenario": "E", "view": 0, "when": func(st: Dictionary) -> bool: return str(st.phase) == "play" and (st.fell as Array).size() == 1 and float(st.t) >= 7.0},
			{"name": "7_spectate", "scenario": "E", "view": 1, "when": func(st: Dictionary) -> bool: return str(st.phase) == "play" and (st.fell as Array).size() == 2 and float(st.t) >= 10.5},
			{"name": "8_victory", "scenario": "E", "view": 0, "when": in_phase.call("survival", "done", 0.8)},
		]
	return [
		{"name": "1_race", "scenario": "B", "view": 0, "when": in_play.call("race", 10.0)},
		{"name": "2_qualified", "scenario": "B", "view": 0, "when": func(st: Dictionary) -> bool: return str(st.kind) == "race" and int(st.status[0]) == 1},
		{"name": "3_eliminated", "scenario": "B", "view": 1, "when": in_phase.call("race", "done", 0.4)},
		{"name": "3b_wall_race", "scenario": "B", "view": 0, "when": in_phase.call("race", "done", 3.8)},
		{"name": "3c_wall_race_out", "scenario": "B", "view": 1, "when": in_phase.call("race", "done", 3.8)},
		{"name": "4_spectate", "scenario": "B", "view": 1, "when": in_play.call("survival", 7.0)},
		{"name": "5_survival", "scenario": "B", "view": 0, "when": in_play.call("survival", 3.0)},
		{"name": "5b_wall_survival", "scenario": "B", "view": 0, "when": in_phase.call("survival", "done", 3.8)},
		{"name": "6b_wall_final", "scenario": "B", "view": 0, "when": in_phase.call("final", "done", 3.8)},
		{"name": "6_final", "scenario": "B", "view": 0, "when": in_play.call("final", 14.0)},
		{"name": "7_podium_crown", "scenario": "B", "view": 0, "when": in_phase.call("", "podium", 4.5)},
	]

func attach_view(replica: Node, slot: int, seats: Array) -> void:
	var view: Node3D = ModeViews.new_view("show")
	replica.world.add_child(view)
	view.setup(replica, seats, slot)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	replica.set_local_seat(slot)
	replicas.append(replica)
	views.append(view)
	huds.append(hud)
	viewers.append(slot)

func drop_views() -> void:
	for view: Node in views:
		if is_instance_valid(view): view.queue_free()
	for hud: Node in huds:
		if is_instance_valid(hud): hud.queue_free()
	views = []
	huds = []
	viewers = []
	for replica: Node in replicas:
		replica.set("spectate_slot", -1)
		replica.set("view_override", null)
	replicas = []

# ------------------------------------------------------------------ the run

func run() -> void:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	controller = Controller.new()
	controller.match_queue = Game.DEFAULT_QUEUE
	controller.match_mode = mode
	controller.seat_count = int(mode.seat_count)
	controller.input_sequences.resize(controller.seat_count)
	controller.input_sequences.fill(0)
	sim = load("res://game/game_run.gd").new()
	sim.name = "Simulation"
	sim.network_role = "authority"
	sim.carrier_count = controller.seat_count
	controller.simulation = sim
	root.add_child(controller)
	controller.add_child(sim)
	load("res://client/presentation_entry.gd").install()
	if not real_cast: show_cast()
	var shells := []
	for index in 3: # the third one is the late joiner of tile_asserts: ready from the start, shown the show only when it "joins"
		var replica: Node = load("res://game/game_run.gd").new()
		replica.name = "Replica%d" % index
		replica.network_role = "replica"
		replica.carrier_count = controller.seat_count
		root.add_child(replica)
		shells.append(replica)
	var deadline := Time.get_ticks_msec() + 180000
	while not (sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready())) and Time.get_ticks_msec() < deadline: await process_frame
	check(sim.is_network_ready() and shells.all(func(shell: Node) -> bool: return shell.is_network_ready()), "authority and three replica shells ready")
	controller.simulation_ready = true
	controller._enter_lobby()
	for seat in SEATS:
		sequence.append(0)
		sequence_epoch.append(-1)
		pilots.append({"round": 0, "idx": 0, "falling": false, "fell": false})
		facing.append(0.0)
		controller.commands[seat] = {"seq": 1, "move": [0.0, 0.0], "jump_seq": 0, "grab_seq": 0}
		targets.append(sim.actors[seat].position)
	check(Modes.current() == "show" and Modes.is_minigame("show"), "the cast's mode is the show, a minigame")
	check(CourseSection.show_levels("race").size() >= 1 and CourseSection.show_levels("survival").size() >= 1 and CourseSection.show_levels("final").size() >= 1, "a show level for every round")
	if only == "" or only == "A": await scenario_points(shells)
	if only == "" or only == "C": await scenario_picks(shells)
	if (only == "" or only == "E") and not real_cast: await scenario_stage(shells) # (its names are the fixture cast's)
	if only == "" or only == "B": await scenario_elimination(shells)
	if only == "" or only == "D": await scenario_steal(shells)
	if not real_cast: TeamCast.override({})
	print("SHOW_CHECK largest snapshot ", largest, " B")
	check(largest <= 32768, "every snapshot fits the 32 KB transport (largest %d B)" % largest)
	print("SHOW_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)

func join(seats: Array) -> void:
	var mode := Game.match_mode_for_queue(Game.DEFAULT_QUEUE)
	for seat: int in seats:
		check(bool(controller.execute_command(seat, {"c": "join", "match_mode": mode}, "Player %d" % (seat + 1)).ok), "seat %d joined" % seat)

## Everybody walks onto the one circle and one presses PLAY; true once the round runs.
func walk_in(seats: Array, course := "") -> bool:
	var centre := WalkInLobby.center(course if course != "" else WalkInLobby.shown_course())
	var offsets := [Vector3(-0.6, 0.0, 0.0), Vector3(0.6, 0.0, 0.0), Vector3(0.0, 0.0, -0.6), Vector3(0.0, 0.0, 0.6), Vector3(-0.9, 0.0, 0.9), Vector3(0.9, 0.0, 0.9)]
	for seat: int in seats: targets[seat] = centre + offsets[seat] + Vector3(0.0, sim.actors[controller._slot(seat)].position.y - centre.y, 0.0)
	var wanted := course if course != "" else WalkInLobby.shown_course()
	var ready: bool = await wait_until(func() -> bool: return controller.lobby_ready == wanted, 60 * 30) # (walking over another circle on the way is no start)
	if not ready: return false
	controller.execute_command(int(seats[0]), {"c": "play"}, "")
	return await wait_until(func() -> bool: return controller.phase == "round", 60 * 10)

func begin_show(seats: Array, course := "") -> bool:
	rounds_seen = []
	banners = {}
	respawned = false
	spectated = false
	podium_camera = false
	podium_worst = 0.0
	podium_samples = 0
	podium_respawns = []
	podium_sent = 0
	podium_shot_ok = false
	out_at = {}
	out_drift = 0.0
	follow_ok = 0
	follow_bad = 0
	own_hidden = 0
	for seat in SEATS:
		pilots[seat].round = 0
	var started := await walk_in(seats, course)
	check(started and controller.round_mode == "minigame" and controller.minigame_id == "show" and sim.round_mode == "level" and sim.play_mode == "show", "the show starts: a level-phase round in show mode")
	if not started: return false
	await tick(8)
	var info: Dictionary = latest_state().get("match", {})
	check(str(info.get("minigame_id", "")) == "show" and info.get("minigame") is Dictionary, "match.minigame rides in the snapshot")
	var slots := []
	for seat: Variant in info.get("slots", []):
		if int(seat) < 0: break
		slots.append(int(seat))
	round_seats = slots
	tile_walk = {}
	attach_view(shells_ref[0], 0, slots) # the first replica plays seat 0; the second plays seat 1 of two, or seat 5 of six (out after the race)
	attach_view(shells_ref[1], 1 if slots.size() == 2 else slots.size() - 1, slots) # the second replica plays seat 1 of two, or the last seat (out first in the scripted rounds)
	return true

var shells_ref: Array = []
var steal := {"thief": -1, "victim": -1, "grabbed_at": -1} ## scenario D: who walks up to whom, and the tick of the first GRAB
var hud_lines: Array = [] ## scenario D: every `line` any viewer's HUD showed

## After a respawn the camera looks along the course: at the start and at every checkpoint of the level the facing a team is put back with is within 15 degrees
## of the route's direction there, and a replica's camera takes it at once (game_run.face_camera; online the owner's step does it when the authority's respawn arrives).
func check_respawn_camera(level: int) -> void:
	var route: PackedVector3Array = sim.level_world.route(level)
	var spots: Array = [sim.level_world.team_start(level, 1, -1).spot]
	for index in (sim.level_world.checkpoints(level) as Array).size(): spots.append(sim.level_world.checkpoint_spot(level, index))
	var worst := 0.0
	var turned := 0.0
	for at: Vector3 in spots:
		var yaw: float = sim.level_world.facing_at(level, at + Vector3(0.4, 0.05, 0.3), 3.0)
		var best := INF
		var ahead := Vector3.ZERO
		for index in range(1, route.size()):
			var near := Geometry3D.get_closest_point_to_segment(at, route[index - 1], route[index])
			if at.distance_to(near) < best:
				best = at.distance_to(near)
				ahead = route[mini(index + 2, route.size() - 1)] - at
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var along := Vector3(ahead.x, 0.0, ahead.z).normalized()
		worst = maxf(worst, rad_to_deg(forward.angle_to(along)))
		var replica: Node = replicas[0]
		var seat: int = viewers[0]
		replica.set("yaw", 3.0)
		replica.face_camera(seat, yaw)
		turned = maxf(turned, rad_to_deg(absf(angle_difference(float(replica.get("yaw")), yaw))))
	check(worst <= 15.0 and turned < 0.01, "B: after a respawn the camera looks along the course (%d spots of level %d, worst %.1f degrees off the route, a replica's camera %.2f off the facing)" % [spots.size(), level, worst, turned])

## The podium phase, every tick: how far each held player (the top three on their spots) is from its spot.
func podium_watch(st: Dictionary) -> void:
	if str(st.phase) != "podium": return
	var rules = controller.minigame
	crown_slot = int(rules.crown)
	var counters: Array = (sim.team.respawns as Array).duplicate()
	if not podium_respawns.is_empty():
		for slot in counters.size(): podium_sent += maxi(int(counters[slot]) - int(podium_respawns[slot]), 0)
	podium_respawns = counters
	for slot: int in rules._hold:
		var at: Vector3 = rules._hold[slot].at
		var here: Vector3 = sim.actors[slot].position
		podium_worst = maxf(podium_worst, Vector2(here.x - at.x, here.z - at.z).length())
	podium_samples += 1
	if podium_samples % 30 == 0 and not podium_shot_ok and float(st.t) >= 2.6: podium_shot_ok = podium_camera_frames(st) # the room's wide shot (modes/show/shared/victory_flow.gd) has settled

## The podium room's wide shot every viewer has: the three spots (feet) and the crown over the winner are inside the picture, the winner in the middle.
func podium_camera_frames(st: Dictionary) -> bool:
	if replicas.is_empty() or views.is_empty(): return false
	var spots: Array = st.podium
	if spots.is_empty(): return false
	for index in replicas.size():
		var replica: Node = replicas[index]
		var shot: Variant = replica.get("view_override")
		if not shot is Transform3D: return false
		var camera: Camera3D = replica.get("camera")
		var size: Vector2 = camera.get_viewport().get_visible_rect().size
		var aspect := size.x / size.y
		var view: Node = views[index]
		var winner := Vector3(float(spots[0][0]), float(spots[0][1]), float(spots[0][2]))
		var middle: Vector3 = (shot as Transform3D).affine_inverse() * winner
		if absf(middle.x) > 0.05: return false
		var points: Array = [winner + Vector3(0.0, 3.4, 0.0)]
		for spot: Variant in spots: points.append(Vector3(float(spot[0]), float(spot[1]), float(spot[2])))
		for point: Vector3 in points:
			if not view.in_picture(shot, camera.fov, aspect, point): return false
		if not replica.get("hold_yaw") is float: return false
	return true

## After the podium: nobody got further than 0.5 m from its spot in all those ticks although the scripted poses kept walking, the authority put
## the walkers back, the camera framed the podium, everybody was held.
func podium_asserts(label: String) -> void:
	check(podium_samples > 60, "%s: the podium phase ran %d ticks" % [label, podium_samples])
	check(podium_worst <= 0.5, "%s: every player stayed within 0.5 m of its spot for the whole podium (worst %.2f m, walking away every tick)" % [label, podium_worst])
	check(podium_sent > 0, "%s: the authority put the walking players back %d times" % [label, podium_sent])
	var wears := -1 # the champion's own client: the crown it was handed on the podium is its HAT now (saved, sent on, removable in the wardrobe)
	for index in replicas.size():
		if int(viewers[index]) == crown_slot and crown_slot >= 0: wears = 1 if str(replicas[index].rigs[crown_slot].get_look().items.get("hat", "")) == "hat_crown" else 0
	check(wears != 0, "%s: the champion's client wears the crown as a hat after the podium (%s)" % [label, "no client plays the champion" if wears < 0 else "yes"])
	check(podium_shot_ok, "%s: the podium camera frames the three spots and the crown, the winner in the middle, everybody held (hold_yaw)" % label)

## Every tick of a level round: a courier whose slot is inactive (an eliminated player) stays exactly where it was when it went inactive, also through the next rounds.
func spectate_watch() -> void:
	if controller.phase != "round" or sim.round_mode == "lobby": return
	for slot in controller.round_roster.size():
		if sim.is_slot_active(slot): continue
		var here: Vector3 = sim.actors[slot].position
		if not out_at.has(slot): out_at[slot] = here
		out_drift = maxf(out_drift, here.distance_to(out_at[slot]))

## An out viewer (status OUT or SPECTATOR) follows the leader: spectate_slot is the state's `lead`, another player who is in the round.
func spectate_follow(replica: Node, viewer: int, minigame: Dictionary) -> void:
	var follow: int = int(replica.get("spectate_slot"))
	if follow < 0: return
	if follow != viewer and follow == int(minigame.get("lead", -1)) and replica.is_slot_active(follow): follow_ok += 1
	else: follow_bad += 1
	if not replica.is_slot_active(viewer): own_hidden += 1

func spectate_asserts(label: String) -> void:
	check(out_at.size() >= 4, "%s: the four who are out left the round where they stood (%d couriers inactive)" % [label, out_at.size()])
	check(out_drift <= 0.01, "%s: an out courier never moved after it left the round, through the next rounds (worst drift %.3f m)" % [label, out_drift])
	check(follow_ok > 100 and follow_bad == 0, "%s: an out viewer's camera follows the leader (%d ticks on the lead, %d on somebody else)" % [label, follow_ok, follow_bad])
	check(own_hidden > 100, "%s: an out viewer's own courier is hidden (slot inactive) while it spectates (%d ticks)" % [label, own_hidden])

func finish_show(label: String) -> void:
	var done: bool = await wait_until(func() -> bool: return controller.phase != "round", 60 * 400)
	podium_asserts(label)
	check(done and controller.phase == "results", "%s: the show ends in the results (phase %s)" % [label, controller.phase])
	await tick(3)
	var results: Dictionary = latest_state().get("match", {})
	check(str(results.get("headline", "")).contains("CROWN") and str(results.get("sub", "")) != "", "%s: results: %s / %s" % [label, results.get("headline", ""), results.get("sub", "")])
	drop_views()
	for seat in controller.joined.keys(): controller.execute_command(int(seat), {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_until(func() -> bool: return controller.phase == "lobby", 60 * 5)
	check(back and controller.minigame == null and sim.round_mode == "lobby", "%s: Play Again: the lobby again" % label)

## Step tiles in the survival (only when the round is on level 15; `--show-level=15` forces it): a standing player's tiles are stepped, then gone
## for the authority's world, every replica and a replica that joins after it (its first state is already the final one); tiles nobody stood on
## still stand; the state is one byte per tile in pieces (`tiles`, `tiles1`, ...) of at most 240 B: no byte field of the whole published state
## is over 256 B, and a tile stepped in the LAST piece is gone for the replicas and the late joiner too.
func tile_asserts(label: String) -> void:
	var st: Dictionary = controller.minigame.state()
	if int(st.level) != TILE_LEVEL:
		print("SHOW_CHECK note %s: the survival is on level %d, not the tile level (--show-level=15)" % [label, int(st.level) + 1])
		return
	var level := TILE_LEVEL
	var field: Array = st.field
	var standing_slot := -1
	for index in field.size():
		if survival_falls.has(index): standing_slot = int(field[index])
	check(standing_slot >= 0, "%s: a scripted player stands still on the tile level" % label)
	if standing_slot < 0: return
	var rules = controller.minigame
	var world: Node = sim.level_world
	var count: int = world.tile_count(level)
	var joined := StepTiles.join_state(st)
	check(joined.size() == count and count > StepTiles.CHUNK and st.has("tiles1"), "%s: the state carries one byte per tile (%d) in pieces (%s)" % [label, joined.size(), str((st.keys() as Array).filter(func(key: String) -> bool: return key.begins_with("tiles")))])
	var biggest := biggest_byte_field(st)
	var biggest_wire := biggest_byte_field(latest_state())
	check(biggest > 0 and biggest <= 256 and biggest_wire <= 256, "%s: no byte field of the show state (%d B) nor of the published snapshot (%d B) is over 256 B" % [label, biggest, biggest_wire])
	await wait_until(func() -> bool: return float(controller.minigame.state().t) >= 0.3, 60 * 3)
	var under: Array = world.tiles_under(level, sim.actors[standing_slot].position)
	check(not under.is_empty(), "%s: the standing player is on %d tile(s)" % [label, under.size()])
	await tick(6)
	st = rules.state()
	var joined_now := StepTiles.join_state(st)
	check(under.all(func(index: int) -> bool: return int(joined_now[index]) != 0), "%s: the tile(s) under the standing player are stepped (%s)" % [label, str(under.map(func(i: int) -> int: return joined_now[i]))])
	var untouched := -1
	for index in joined_now.size():
		if int(joined_now[index]) == 0 and not under.has(index):
			untouched = index
			break
	var gone_at := 0.0
	for index: int in under: gone_at = maxf(gone_at, float(world._levels[level].tiles.gone_at(index)))
	check(not under.any(func(index: int) -> bool: return world.tile_gone(level, index)), "%s: the tile under the standing player is still there during its warning" % label)
	await wait_until(func() -> bool: return float(world.clock) >= gone_at + 0.15, 60 * 6)
	await tick(24)
	check(under.all(func(index: int) -> bool: return world.tile_gone(level, index)), "%s: the authority's world: the tile under the standing player is gone (collision off)" % label)
	for index in replicas.size():
		var replica: Node = replicas[index]
		check(under.all(func(tile: int) -> bool: return replica.level_world.tile_gone(level, tile)), "%s: replica %d: that tile is gone for them too" % [label, index])
	check(untouched >= 0 and not world.tile_gone(level, untouched) and replicas.all(func(replica: Node) -> bool: return not replica.level_world.tile_gone(level, untouched)), "%s: a tile nobody stood on still stands everywhere" % label)
	# the steps travel in pieces: a tile of the LAST piece stepped long ago (nobody stands there; written into the authority's steps) is gone for
	# the authority, the replicas (through the published state) and, below, the late joiner
	var last_tile := count - 1
	var long_ago := maxi(1, ceili((float(world.clock) - 4.0) / StepTiles.STEP_UNIT))
	check(last_tile >= StepTiles.CHUNK and int(rules.tiles[last_tile]) == 0, "%s: the last tile (%d) is in the last piece and untouched" % [label, last_tile])
	rules.tiles[last_tile] = long_ago
	rules.host.apply_tiles(level, rules.tiles)
	await tick(12)
	var wire: Dictionary = latest_state().get("match", {}).get("minigame", {})
	check(StepTiles.join_state(wire).size() == count and int(StepTiles.join_state(wire)[last_tile]) == long_ago, "%s: the published state's last piece carries the stepped tile" % label)
	check(world.tile_gone(level, last_tile) and replicas.all(func(replica: Node) -> bool: return replica.level_world.tile_gone(level, last_tile)), "%s: the tile of the last piece is gone for the authority and both replicas" % label)
	# a late joiner: a third replica shell appears now; its first snapshot already has the tile gone
	var late: Node = shells_ref[2]
	attach_view(late, 0, round_seats)
	await tick(30)
	var made: int = replicas.size() - 1
	check(under.all(func(tile: int) -> bool: return late.level_world.tile_gone(level, tile)), "%s: the late joiner sees the stood-on tile gone at once" % label)
	check(untouched >= 0 and not late.level_world.tile_gone(level, untouched), "%s: and the untouched tile standing" % label)
	check(late.level_world.tile_gone(level, last_tile), "%s: and the tile of the last piece gone (the late joiner joins a split state)" % label)
	check(absf(float(late.level_world.clock) - float(world.clock)) < 0.5, "%s: the late joiner's level clock follows the authority's (%.2f vs %.2f)" % [label, float(late.level_world.clock), float(world.clock)])
	# the late shell leaves again
	var view: Node = views.pop_back()
	var hud: Node = huds.pop_back()
	replicas.pop_back()
	viewers.pop_back()
	view.queue_free()
	hud.queue_free()
	check(made >= 2, "%s: the late shell was the third viewer" % label)

## The largest byte array in `value` (a published state, walked through dictionaries and arrays): the platform refuses a byte field over 256 B.
func biggest_byte_field(value: Variant) -> int:
	if value is PackedByteArray: return (value as PackedByteArray).size()
	var most := 0
	if value is Dictionary:
		for key: Variant in value: most = maxi(most, biggest_byte_field(value[key]))
	elif value is Array:
		for item: Variant in value: most = maxi(most, biggest_byte_field(item))
	return most

func scenario_points(shells: Array) -> void:
	shells_ref = shells
	scenario = "A"
	race_falls = {}
	survival_falls = {1: 16.0}
	join([0, 1])
	if not await begin_show([0, 1]): return
	var st: Dictionary = controller.minigame.state()
	check(bool(st.points_mode) and int(st.n) == 2, "A: two players play for points")
	check(sim.level_world.active_level == int(st.level) and str(sim.level_world.show_kind(int(st.level))) == "race", "A: round 1 is on a race level")
	check(str(st.card) == "EVERYBODY RACES  ·  PLACES SCORE POINTS" and CourseSection.level_rule(int(st.level)) != "", "A: the round card says what to do (%s) and how it scores (%s)" % [CourseSection.level_rule(int(st.level)), str(st.card)])
	await tick(30)
	var wants_stage := CourseSection.level_camera(int(st.level)) == "stage" # a race level with `"camera": "stage"` (levels 29 and 30) plays in the stage view, in a game as in the show's replicas
	for replica: Node in replicas: # (a headless run draws nothing and has no camera: the offscreen run with --shots checks it)
		var follow: Variant = replica.get("follow")
		if follow == null: continue
		check(bool(replica.get("_stage_view")) == wants_stage and bool(follow.stage_view) == wants_stage, "A: the replica's camera is %s for level %d" % ["the stage view" if wants_stage else "the chase view", int(st.level) + 1])
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done" and int(controller.minigame.state().round) == 1, 60 * 140)
	st = controller.minigame.state()
	check(int(st.round) == 1 and (st.status as Array).count(2) == 0 and (st.status as Array).count(3) == 0, "A: the race eliminates nobody")
	check(int(st.pts[0]) == 2 and int(st.pts[1]) == 1, "A: race points 2 / 1 (%s)" % str(st.pts))
	await wait_until(func() -> bool: return int(controller.minigame.state().round) == 2 and str(controller.minigame.state().phase) == "play", 60 * 20)
	await tile_asserts("A")
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done" and int(controller.minigame.state().round) == 2, 60 * 100)
	st = controller.minigame.state()
	var logo_round := str(st.play) == "badge" # KEEP THE LOGO: the scripted couriers stand still, so who wears the logo longest (2 points) is the deal's
	if logo_round: check(int(st.pts[0]) + int(st.pts[1]) == 6 and int(st.pts[0]) >= 3, "A: the logo round adds 2 / 1 (%s)" % str(st.pts))
	else: check(int(st.pts[0]) == 4 and int(st.pts[1]) == 2, "A: survival points add 2 / 1 (%s)" % str(st.pts))
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "podium", 60 * 160)
	st = controller.minigame.state()
	if logo_round: check(int(st.pts[0]) + int(st.pts[1]) == 9 and int(st.pts[0]) >= 5, "A: the final scores like any round, nothing doubles: 9 points in all (%s)" % str(st.pts))
	else: check(int(st.pts[0]) == 6 and int(st.pts[1]) == 3, "A: the final scores like any round: totals 6 / 3 (%s)" % str(st.pts))
	check(int(st.crown) == 0 and (st.podium as Array).size() == 3, "A: the crown goes to the highest total, the podium has three spots")
	check(rounds_seen == ["1:race", "2:survival", "3:final", "podium"], "A: round order %s" % str(rounds_seen))
	await tick(90)
	check(podium_camera, "A: the view takes the podium camera")
	await finish_show("A")

## Two players stand on the circle of one round (`row`: a RoundList entry) and PLAY: just that round runs, then the results (then the winner's podium), then the lobby.
func play_pick(row: Dictionary, label: String) -> void:
	rounds_seen = []
	for seat in SEATS: pilots[seat].round = 0
	var started := await walk_in([0, 1], str(row.id))
	check(started and controller.round_mode == "minigame" and controller.minigame_id == "show" and sim.round_mode == "level", "%s: PLAY on the %s circle starts the round" % [label, row.title])
	if not started: return
	await tick(8)
	var st: Dictionary = controller.minigame.state()
	check(int(st.rounds) == 1 and str(st.kind) == str(row.kind) and (row.levels as Array).has(int(st.level)), "%s: one %s round on level %d (rounds %d)" % [label, st.kind, int(st.level) + 1, int(st.rounds)])
	var info: Dictionary = latest_state().get("match", {})
	check(info.get("minigame") is Dictionary and int((info.minigame as Dictionary).get("rounds", 0)) == 1, "%s: the published state says it is one round" % label)
	var done: bool = await wait_until(func() -> bool: return controller.phase != "round", 60 * 200)
	check(done and controller.phase == "results" and rounds_seen.size() == 2 and str(rounds_seen[-1]) == "podium", "%s: the results come after the one round and the podium room for its winner (phase %s, %s)" % [label, controller.phase, str(rounds_seen)])
	await tick(3)
	var results: Dictionary = latest_state().get("match", {})
	check(str(results.get("headline", "")).ends_with(" WINS") and str(results.get("sub", "")).contains(str(row.title)), "%s: results: %s / %s" % [label, results.get("headline", ""), results.get("sub", "")])
	for seat in controller.joined.keys(): controller.execute_command(int(seat), {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_until(func() -> bool: return controller.phase == "lobby", 60 * 5)
	check(back and controller.minigame == null and sim.round_mode == "lobby", "%s: Play Again: the lobby again" % label)
	for seat in [0, 1]: targets[seat] = WalkInLobby.spawn(seat)

func scenario_picks(shells: Array) -> void:
	scenario = "C"
	shells_ref = shells
	race_falls = {}
	survival_falls = {}
	if only == "C": join([0, 1])
	var rows: Array = RoundList.entries()
	await play_pick(rows[0], "C1")
	for row: Dictionary in rows:
		if CourseSection.level_play(int(row.levels[0])) == "badge": await play_pick(row, "C2")

func scenario_steal(shells: Array) -> void:
	scenario = "D"
	shells_ref = shells
	race_falls = {}
	survival_falls = {}
	steal = {"thief": -1, "victim": -1, "grabbed_at": -1, "outside": false}
	hud_lines = []
	if only == "D": join([0, 1, 2, 3, 4, 5])
	var row: Dictionary = {}
	for entry: Dictionary in RoundList.entries():
		if CourseSection.level_play(int(entry.levels[0])) == "badge": row = entry
	if row.is_empty():
		print("SHOW_CHECK note D: KEEP THE LOGO is not in the lineup (modes/lineup/lineup.json): skipped; `--all-rounds` brings every round back")
		return
	if not await begin_show([0, 1, 2, 3, 4, 5], str(row.id)):
		check(false, "D: the KEEP THE LOGO circle starts a round")
		return
	var st: Dictionary = controller.minigame.state()
	check(str(st.play) == "badge" and int(st.rounds) == 1 and (st.badge as Array).size() == int(st.need) and int(st.need) == 2, "D: six players, two logos dealt on the card (%s)" % str(st.badge))
	check(str(st.card).contains("LOGO") and CourseSection.level_rule(int(st.level)) != "", "D: the card says what to do (%s) and how it ends (%s)" % [CourseSection.level_rule(int(st.level)), str(st.card)])
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "play" and float(controller.minigame.state().t) > 1.0, 60 * 20)
	var worn_ok := true
	for view in views:
		var worn: Array = (view.get("_worn") as Dictionary).keys()
		var wearers: Array = (controller.minigame.state().badge as Array).duplicate()
		worn.sort()
		wearers.sort()
		worn_ok = worn_ok and worn == wearers
	check(worn_ok, "D: every viewer's view draws a logo plate on each wearer (and on nobody else)")
	var first_wearers: Array = (controller.minigame.state().badge as Array).duplicate()
	var stolen: bool = await wait_until(func() -> bool: return int(steal.thief) >= 0 and (controller.minigame.state().badge as Array).has(int(steal.thief)), 60 * 25)
	st = controller.minigame.state()
	var where := ""
	if not stolen and int(steal.thief) >= 0:
		var thief_at: Vector3 = sim.actors[int(steal.thief)].position
		var victim_at: Vector3 = sim.actors[int(steal.victim)].position
		where = " (thief %s, victim %s, gap %.2f m, outside %s, grabbed at %d, held_by %s)" % [str(thief_at.snapped(Vector3.ONE * 0.01)), str(victim_at.snapped(Vector3.ONE * 0.01)), Vector2(thief_at.x - victim_at.x, thief_at.z - victim_at.z).length(), str(steal.outside), int(steal.grabbed_at), str((st.badge as Array))]
	check(stolen and not (st.badge as Array).has(int(steal.victim)) and (st.badge as Array).size() == 2, "D: a real GRAB took the logo: slot %d took it from slot %d (%s -> %s)%s" % [int(steal.thief), int(steal.victim), str(first_wearers), str(st.badge), where])
	await tick(30)
	var worn_after := true
	for view in views:
		var worn: Array = (view.get("_worn") as Dictionary).keys()
		var wearers: Array = (controller.minigame.state().badge as Array).duplicate()
		worn.sort()
		wearers.sort()
		worn_after = worn_after and worn == wearers
	check(worn_after, "D: the plates followed the logo")
	check(hud_lines.any(func(line: String) -> bool: return line.contains("LOGO")), "D: the HUD line talks about the logo (%s)" % str(hud_lines))
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done", 60 * 60)
	st = controller.minigame.state()
	var through: Array = []
	for slot: int in st.field:
		if (st.status as Array)[slot] == 1: through.append(slot)
	check(through.size() == 2 and through.all(func(slot: int) -> bool: return (st.badge as Array).has(slot)), "D: the two who wear a logo at the cap go through (%s, status %s)" % [str(st.badge), str(st.status)])
	var done: bool = await wait_until(func() -> bool: return controller.phase != "round", 60 * 20)
	check(done and controller.phase == "results", "D: the results follow, no podium (phase %s)" % controller.phase)
	drop_views()
	for seat in controller.joined.keys(): controller.execute_command(int(seat), {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_until(func() -> bool: return controller.phase == "lobby", 60 * 5)
	check(back, "D: Play Again: the lobby again")

func scenario_elimination(shells: Array) -> void:
	scenario = "B"
	show_cast(false) # B is the spectators' scenario (the out viewers follow the leader): the GHOST PIGEON experiment (docs/pigeon.md) turns the out player into a bird instead; A and E run with it on, tools/modes/items/pigeon_scenario.gd covers it
	shells_ref = shells
	race_falls = {3: 9.0}
	survival_falls = {2: 5.0, 3: 8.0}
	var newcomers: Array = [0, 1, 2, 3, 4, 5].filter(func(seat: int) -> bool: return not controller.joined.has(seat)) # (A and C seated two, E two more)
	join(newcomers)
	for seat: int in newcomers: targets[seat] = sim.actors[seat].position
	if not await begin_show([0, 1, 2, 3, 4, 5]): return
	var st: Dictionary = controller.minigame.state()
	check(not bool(st.points_mode) and int(st.n) == 6, "B: six players: elimination")
	check(int(st.need) == 4 and (st.field as Array).size() == 6, "B: 4 of 6 qualify from the race (need %d)" % int(st.need))
	check(str(st.card) == "FIRST 4 ACROSS QUALIFY" and CourseSection.level_rule(int(st.level)) != "", "B: the round card says what to do (%s) and who qualifies (%s)" % [CourseSection.level_rule(int(st.level)), str(st.card)])
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done" and int(controller.minigame.state().round) == 1, 60 * 160)
	st = controller.minigame.state()
	check(respawned, "B: a racer that fell into a kill volume was put back on the course")
	check_respawn_camera(int(st.level))
	check((st.status as Array).count(1) == 4 and (st.status as Array).count(2) == 2, "B: 4 qualified, 2 eliminated (%s)" % str(st.status))
	var race_field: Array = (st.place as Array).slice(0, 4)
	await wait_until(func() -> bool: return int(controller.minigame.state().round) == 2 and str(controller.minigame.state().phase) == "play", 60 * 20)
	st = controller.minigame.state()
	var qualifiers := race_field.duplicate()
	qualifiers.sort()
	var survivors_field: Array = (st.field as Array).duplicate()
	survivors_field.sort()
	check(survivors_field == qualifiers, "B: the survival is played by the 4 qualifiers (%s)" % str(survivors_field))
	check(int(st.need) == 2 and (st.status as Array).count(3) == 2, "B: 2 survive; the 2 out are spectators (status %s)" % str(st.status))
	check(int(st.lead) >= 0, "B: spectators have somebody to follow")
	var field: Array = (st.field as Array).duplicate()
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done" and int(controller.minigame.state().round) == 2, 60 * 100)
	st = controller.minigame.state()
	var logo_round := str(st.play) == "badge" # KEEP THE LOGO: the two who wear a logo at the cap go through
	var through: Array = field.filter(func(slot: int) -> bool: return (st.status as Array)[slot] == 1)
	if logo_round: check(through.size() == 2 and field.filter(func(slot: int) -> bool: return (st.status as Array)[slot] == 2).size() == 2 and through.all(func(slot: int) -> bool: return (st.badge as Array).has(slot)), "B: the two who wear a logo survive (%s, logos %s)" % [str(st.status), str(st.badge)])
	else: check((st.status as Array)[field[0]] == 1 and (st.status as Array)[field[1]] == 1 and (st.status as Array)[field[2]] == 2 and (st.status as Array)[field[3]] == 2, "B: the last two standing survive (%s)" % str(st.status))
	if logo_round: field = through + field.filter(func(slot: int) -> bool: return not through.has(slot))
	await wait_until(func() -> bool: return int(controller.minigame.state().round) == 3 and str(controller.minigame.state().phase) == "play", 60 * 20)
	st = controller.minigame.state()
	check((st.field as Array).size() == 2 and (st.status as Array).count(3) == 4, "B: the final is between the two survivors, four watch")
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "podium", 60 * 160)
	st = controller.minigame.state()
	var crowned := int(st.crown)
	check(crowned == field[0] or crowned == field[1], "B: the crown goes to a finalist (slot %d)" % crowned)
	check((st.status as Array)[crowned] == 4 and (st.podium as Array).size() == 3, "B: crown winner marked, podium spots set")
	check(rounds_seen == ["1:race", "2:survival", "3:final", "podium"], "B: round order %s" % str(rounds_seen))
	await tick(90)
	check(spectated and podium_camera, "B: the eliminated viewer followed the leader and the podium camera came")
	spectate_asserts("B")
	check((banners.get(5, []) as Array).has(TeamCast.show_word("eliminated")), "B: the ELIMINATED banner shows the cast's word (%s)" % str(banners))
	check(banners.values().any(func(list: Array) -> bool: return list.has(TeamCast.show_word("qualified"))), "B: the QUALIFIED banner shows the cast's word")
	check(banners.values().any(func(list: Array) -> bool: return list.has(TeamCast.show_word("go"))), "B: GO shows the cast's word")
	await finish_show("B")

# ------------------------------------------------------------------ E: stage rounds

## The fixture cast of the checks (six players; `fixture_cast` makes more). `pigeons` false: the cast turns the GHOST PIGEON experiment off (show.pigeon.off).
func show_cast(pigeons := true) -> void:
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Show Check"}, "mode": "show",
		"players": [{"name": "Maya", "catchphrase": "Ship it!"}, {"name": "Theo", "catchphrase": "On my way!"}, {"name": "Ida", "catchphrase": "Coffee first"},
			{"name": "Noor", "catchphrase": "Quick one?"}, {"name": "Lars", "catchphrase": "Hold my coffee"}, {"name": "Eva", "catchphrase": "Too easy"}],
		"obstacles": [{"label": "FLAKY CI"}, {"label": "CHAT PINGS"}], "show": {"words": {"qualified": "IN!", "eliminated": "OUT!", "champion": "CROWNED", "go": "RUN!"}, "pigeon": {"off": not pigeons}}})

func fixture_cast(players: int) -> void:
	var list := []
	for index in players: list.append({"name": "Player%d" % (index + 1), "color": ["#ff5a36", "#2c4bff", "#2ec27e", "#f2c230", "#9a4dff", "#00b8d9"][index % 6]})
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Stage Check"}, "players": list, "mode": "show"})

## The first round circle of a stage level (a level with a `stage` section); `--stage=<n>` takes the n-th.
func stage_row() -> Dictionary:
	var skip := stage_nth
	for row: Dictionary in RoundList.entries():
		if CourseSection.level_stage(int(row.levels[0])).is_empty(): continue
		if skip <= 0: return row
		skip -= 1
	return {}

## What a viewer's stage HUD (stage_hud.gd probe) showed, over the whole round.
func stage_record(slot: int, model: Dictionary) -> void:
	if model.is_empty(): return
	if not stage_seen.has(slot): stage_seen[slot] = {"digits": [], "go": false, "pill": "", "quest": "", "victory": false, "failure": "", "names": [], "elim_n": 0, "elim_m": -1, "max_feed": 0, "go_word": ""}
	var seen: Dictionary = stage_seen[slot]
	var digit := str(model.get("digit", ""))
	if digit != "" and (seen.digits.is_empty() or str(seen.digits[-1]) != digit): (seen.digits as Array).append(digit)
	if str(model.get("go", "")) != "":
		seen.go = true
		seen.go_word = str(model.go)
	if float(model.get("pill_age", -1.0)) >= 0.0: seen.pill = str(model.pill)
	if str(model.get("quest", "")) != "": seen.quest = str(model.quest)
	if float(model.get("victory_age", -1.0)) >= 0.0: seen.victory = true
	if str(model.get("failure", "")) != "": seen.failure = str(model.failure)
	for entry: Dictionary in model.get("feed", []):
		if not (seen.names as Array).has(str(entry.name)): (seen.names as Array).append(str(entry.name))
	seen.max_feed = maxi(int(seen.max_feed), (model.get("feed", []) as Array).size())
	if int(model.get("elim_m", -1)) >= 0:
		seen.elim_n = int(model.elim_n)
		seen.elim_m = int(model.elim_m)

## A stage round with the players seated in the lobby, through the real flow (see the header): two fall (the scripted falls), the rest stand.
func scenario_stage(shells: Array) -> void:
	scenario = "E"
	shells_ref = shells
	race_falls = {}
	survival_falls = {2: 6.0, 3: 9.0}
	stage_seen = {}
	notes = {}
	var seats := [0, 1, 2, 3]
	var newcomers: Array = seats.filter(func(seat: int) -> bool: return not controller.joined.has(seat))
	join(newcomers)
	for seat: int in newcomers: targets[seat] = sim.actors[seat].position
	var row := stage_row()
	if row.is_empty() or not await begin_show(seats, str(row.id)):
		check(false, "E: the stage round circle starts a round")
		return
	var st: Dictionary = controller.minigame.state()
	check(bool(st.stage) and int(st.rounds) == 1 and int(st.n) == 4 and int(st.need) == 2 and (st.field as Array).size() == 4, "E: four players, a stage round of one, 2 go through (need %d)" % int(st.need))
	check(float(st.count) <= ShowRules.STAGE_CARD and float(st.count) > ShowRules.STAGE_CARD - 0.5 and str(st.phase) == "card", "E: the stage card counts down from %.1f s (count %.2f)" % [ShowRules.STAGE_CARD, float(st.count)])
	var played: bool = await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "play", 60 * 10)
	check(played, "E: the card ends and play begins")
	await wait_until(func() -> bool: return str(controller.minigame.state().phase) == "done", 60 * 80)
	st = controller.minigame.state()
	check((st.fell as Array) == [2, 3], "E: the state names who fell, in order (%s)" % str(st.fell))
	var through: Array = (st.field as Array).filter(func(slot: int) -> bool: return (st.status as Array)[slot] == 1)
	check(through == [0, 1] and (st.status as Array)[2] == 2 and (st.status as Array)[3] == 2, "E: the two who stood go through (status %s)" % str(st.status))
	await tick(40)
	var mine: Dictionary = stage_seen.get(0, {})
	var lost: Dictionary = stage_seen.get(3, {})
	check(mine.get("digits", []) == ["3", "2", "1"], "E: the survivor's HUD counted 3, 2, 1 (%s)" % str(mine.get("digits")))
	check(bool(mine.get("go", false)) and str(mine.get("go_word", "")) == TeamCast.show_word("go"), "E: GO showed the cast's word (%s)" % str(mine.get("go_word")))
	check(str(mine.get("pill", "")) == "DON'T FALL!  BE ONE OF THE LAST 2 STANDING!" and str(mine.get("quest", "")) == "", "E: the objective pill names the 2 who go through and no objective text (quest) is ever on the HUD (%s)" % str(mine.get("pill")))
	check(int(mine.get("elim_m", -1)) == 2 and int(mine.get("elim_n", 0)) == 2, "E: CURRENT ELIMINATIONS %s/%s (4 players, 2 go through: M 2)" % [str(mine.get("elim_n")), str(mine.get("elim_m"))])
	check((mine.get("names", []) as Array) == ["IDA", "NOOR"], "E: the kill feed told who fell, in order (%s)" % str(mine.get("names")))
	check(bool(mine.get("victory", false)) and not bool(lost.get("victory", false)), "E: the survivor got the VICTORY banner, the one who fell did not")
	check(spectated and (notes.get(3, []) as Array).any(func(note: String) -> bool: return note.begins_with("SPECTATING")), "E: the one who fell spectated (%s)" % str(notes.get(3)))
	check(str(lost.get("failure", "")) == TeamCast.show_word("eliminated") and not (banners.get(3, []) as Array).has(TeamCast.show_word("eliminated")) and str(mine.get("failure", "")) == "", "E: the fallen player's grey plate carries the cast's word (no banner), the survivor has none and gets VICTORY, not QUALIFIED (%s)" % str(lost.get("failure")))
	var finished: bool = await wait_until(func() -> bool: return controller.phase != "round", 60 * 20)
	check(finished and controller.phase == "results" and rounds_seen.size() == 2 and str(rounds_seen[-1]) == "podium", "E: the results follow the one round and the podium room (phase %s)" % controller.phase)
	await tick(3)
	var results: Dictionary = latest_state().get("match", {})
	check(str(results.get("headline", "")).ends_with(" WINS") and str(results.get("sub", "")).contains(str(row.title)), "E: results: %s / %s" % [results.get("headline", ""), results.get("sub", "")])
	drop_views()
	for seat in controller.joined.keys(): controller.execute_command(int(seat), {"c": "choose", "v": "again"}, "")
	var back: bool = await wait_until(func() -> bool: return controller.phase == "lobby", 60 * 5)
	check(back and controller.minigame == null and sim.round_mode == "lobby", "E: Play Again: the lobby again")
	for seat: int in seats: targets[seat] = WalkInLobby.spawn(seat)
	for players in [12, 10, 8, 4, 3]: await stage_fixture(players)
	await card_fixture()

## A host without a shell for the stage rules: positions and zones are the script's, the level is only its number (the pattern of round_pick_check.gd).
class FixtureHost extends "res://modes/mode_host.gd":
	var positions: Array = []
	var zones: Array = []
	var respawns := 0
	var retired: Array = []
	func _init(round_seats: Array, seed_value := 1) -> void:
		super(null, round_seats, seed_value)
		for slot in count:
			positions.append(Vector3(slot, 0.05, 0.0))
			zones.append("")
	func active(slot: int) -> bool: return slot >= 0 and slot < count
	func item_boxes(_level: int) -> PackedVector3Array: return PackedVector3Array() # no level world in the fixture: no item boxes
	func presses(_slot: int, _key: String) -> int: return 0 # the fixture has no run shell (no button counters): the items read 0 presses (mode_host.gd presses asks the run's press_count)
	func position(slot: int) -> Vector3: return positions[slot]
	func held_by(_slot: int) -> int: return -1
	func send_to(slot: int, at: Vector3, _yaw := 0.0) -> void: positions[slot] = at
	func begin_level(_level: int, out := []) -> void: retired = out.duplicate()
	func begin_podium(out: Array) -> void: retired = out.duplicate()
	func tile_start(_level: int, _players: int) -> PackedByteArray: return PackedByteArray()
	func tiles_under(slot: int, _level: int) -> Array: return [slot] # the fixture's players always stand on a tile (the rules' hang check, rules.gd `_hanging`, only fires on nothing)
	func apply_tiles(_level: int, _steps: PackedByteArray) -> void: pass
	func zone(slot: int, _level: int) -> String: return str(zones[slot])
	func scorch(_slot: int, _level: int) -> String: return ""
	func checkpoint_at(_slot: int, _level: int) -> int: return -1
	func note_scorch(_slot: int, _kind: String) -> void: pass
	func respawn(slot: int, _level: int, _checkpoint: int) -> void:
		respawns += 1
		zones[slot] = ""
		positions[slot] = Vector3(slot, 0.05, 0.0)
	func progress(_slot: int, _level: int) -> float: return 0.0
	func route_length(_level: int) -> float: return 100.0
	func level_clock() -> float: return 0.0
	func retire(slot: int) -> void: if not retired.has(slot): retired.append(slot)
	func podium(_level: int) -> Array: return [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]
	func hold(_slot: int, _at: Vector3, _radius: float, _rise := INF) -> void: pass
	func strays(_slot: int) -> int: return 0
	func release_holds() -> void: pass

## The stage rules of `players` players and two views on them (the survivor, slot 0, and the first to fall), on a host of the script's: one slot falls every half
## second from play second 2, the last `players - need` of them. Every sixth tick both views present the state, the way the replicas do.
func stage_fixture(players: int) -> void:
	var label := "E%d" % players
	StubRun = load((get_script() as Script).resource_path.get_base_dir() + "/stub_run.gd")
	fixture_cast(players)
	var seats := range(players)
	var host := FixtureHost.new(seats, 3)
	host.pick = str(stage_row().id)
	var rules := ShowRules.new()
	rules.start(host)
	var st: Dictionary = rules.state()
	var need := int(st.need)
	var fallers := players - need
	var expected_need := 1 if players <= 3 else clampi(ceili(maxi(3, roundi(players * ShowRules.RACE_SHARE)) / 2.0), 1, players - 1) # the show's own deal: 12 -> 4, 10 -> 4, 8 -> 3, 4 -> 2
	check(bool(st.stage) and int(st.n) == players and (st.field as Array).size() == players and need == expected_need and bool(st.points_mode) == (players <= 3), "%s: %d players: a stage round, need %d (points %s)" % [label, players, need, str(st.points_mode)])
	var stub: Node = StubRun.new()
	root.add_child(stub)
	stub.call("make", players, false)
	var watchers: Array = []
	for slot: int in [0, players - 1]: # the survivor and the first who falls
		var view: Node3D = ModeViews.new_view("show")
		(stub.get("world") as Node3D).add_child(view)
		view.setup(stub, seats, slot)
		watchers.append(view)
	var falls := {}
	for index in fallers: falls[players - 1 - index] = 2.0 + 0.5 * index
	var seen := {"play_at": -1.0, "digit_at": {}, "title_ok": true, "digit_plates_ok": true, "go_ok": true, "pill_late": false, "quest_ok": true, "feed_max": 0, "feed_old": false,
		"first_late": false, "elim": [], "victory": [false, false], "lead_ok": true, "spectating": false, "need_words": ""}
	var first_name := str(TeamCast.player(players - 1).name).to_upper()
	var done_at := -1.0
	var finished_at := -1.0
	for frame in 60 * 40:
		st = rules.state()
		if str(st.phase) == "play":
			for slot: int in falls:
				if float(st.t) >= float(falls[slot]) and host.zones[slot] == "": host.zones[slot] = "kill"
		rules.tick(1.0 / 60.0)
		if done_at >= 0.0 and rules.finished():
			finished_at = float(frame) / 60.0
			break
		if frame % 6 != 0: continue
		st = rules.state()
		var phase := str(st.phase)
		var t := float(st.t)
		if phase == "done" and done_at < 0.0: done_at = float(frame) / 60.0
		for index in watchers.size():
			var view: Node3D = watchers[index]
			view.present(st, 0.1)
			var model: Dictionary = (view.get("_stage") as CanvasLayer).call("probe")
			var hud: Dictionary = view.hud(st)
			if index == 1:
				if phase == "done": seen.victory[1] = seen.victory[1] or float(model.get("victory_age", -1.0)) >= 0.0
				if phase == "play" and (st.fell as Array).has(players - 1) and str(hud.note).begins_with("SPECTATING"): seen.spectating = true
				continue
			if phase == "card":
				var digit := str(model.get("digit", ""))
				if digit != "" and not (seen.digit_at as Dictionary).has(digit): (seen.digit_at as Dictionary)[digit] = t
				if float(st.count) > ShowRules.STAGE_COUNT and (not Plates.title_up(st) or digit != "" or str(hud.big) != ""): seen.title_ok = false
				if float(st.count) <= ShowRules.STAGE_COUNT and (Plates.title_up(st) or digit == "" or str(hud.big) != ""): seen.digit_plates_ok = false
			if phase == "play":
				if seen.play_at < 0.0: seen.play_at = float(rules.phase_time)
				if t < 0.8 and (str(model.get("go", "")) == "" or str(hud.big) != ""): seen.go_ok = false
				if t > 3.4 and float(model.get("pill_age", -1.0)) >= 0.0: seen.pill_late = true
				if str(model.get("quest", "")) != "" or str(hud.title) != "" or float(hud.timer) >= 0.0 or not (hud.scores as Array).is_empty() or str(hud.line) != "": seen.quest_ok = false
				if str(model.get("pill", "")) != "": seen.need_words = str(model.pill)
				var feed: Array = model.get("feed", [])
				seen.feed_max = maxi(int(seen.feed_max), feed.size())
				for entry: Dictionary in feed:
					if float(entry.age) >= 3.5 or float(entry.left) <= 0.0: seen.feed_old = true
					if str(entry.name) == first_name and t >= 2.0 + 3.7: seen.first_late = true
				if int(model.get("elim_m", -1)) >= 0: (seen.elim as Array).append([int(model.elim_n), int(model.elim_m)])
				if int(st.lead) >= 0 and (st.fell as Array).has(int(st.lead)): seen.lead_ok = false
			if phase == "done": seen.victory[0] = seen.victory[0] or float(model.get("victory_age", -1.0)) >= 0.0
	check(float(seen.play_at) >= 0.0 and float(seen.play_at) < 0.2, "%s: play begins as the card ends (first play state at %.2f s)" % [label, float(seen.play_at)])
	var digits: Dictionary = seen.digit_at
	check(digits.keys().size() == 3 and digits.has("3") and digits.has("2") and digits.has("1"), "%s: the digits 3, 2, 1 came (%s)" % [label, str(digits)])
	if digits.keys().size() == 3:
		check(absf(float(digits["3"]) - ShowRules.STAGE_TITLE) < 0.25 and absf(float(digits["2"]) - float(digits["3"]) - 1.0) < 0.2 and absf(float(digits["1"]) - float(digits["2"]) - 1.0) < 0.2, "%s: the digits come a second apart after the %.1f s title (3 at %.2f, 2 at %.2f, 1 at %.2f)" % [label, ShowRules.STAGE_TITLE, float(digits["3"]), float(digits["2"]), float(digits["1"])])
	check(seen.title_ok and seen.digit_plates_ok, "%s: the title card is up for its %.1f s, the digits after it (the HUD's own big word and chip stay out of the way)" % [label, ShowRules.STAGE_TITLE])
	check(seen.go_ok and not seen.pill_late and seen.quest_ok, "%s: GO shows at the start, the speech bubble is gone after GO, no objective text (quest) top left, no timer / board / hint line" % label)
	var expected_words := "DON'T FALL!  BE THE LAST ONE STANDING!" if need == 1 else "DON'T FALL!  BE ONE OF THE LAST %d STANDING!" % need
	check(str(seen.need_words) == expected_words, "%s: the objective reads %s (%s)" % [label, expected_words, str(seen.need_words)])
	var elim: Array = seen.elim
	check(not elim.is_empty() and elim[0] == [0, fallers] and elim[-1] == [fallers, fallers], "%s: CURRENT ELIMINATIONS ran from 0/%d to %d/%d" % [label, fallers, fallers, fallers])
	check(int(seen.feed_max) == mini(fallers, 4) and not seen.feed_old, "%s: the kill feed shows at most 4 pills (max %d), none older than 3.5 s" % [label, int(seen.feed_max)])
	if players == 12: check(not seen.first_late, "%s: the first pill is gone 3.7 s after the fall" % label)
	check(seen.victory[0] and not seen.victory[1], "%s: VICTORY for the survivor, not for the one who fell" % label)
	check(seen.lead_ok and seen.spectating, "%s: spectators follow somebody still standing, the one who fell reads SPECTATING" % label)
	var state_end: Dictionary = rules.state()
	check((state_end.fell as Array).size() == fallers and (state_end.status as Array).count(2) + (state_end.status as Array).count(3) == fallers and (state_end.status as Array).count(1) + (state_end.status as Array).count(4) == (need if players > 3 else 1), "%s: %d fell, status %s" % [label, fallers, str(state_end.status)])
	check(finished_at > 0.0 and absf(finished_at - done_at - (ShowRules.STAGE_DONE + ShowRules.PODIUM)) < 0.25, "%s: the round's result lasts the VICTORY banner %.1f s and the podium room %.1f s (%.2f s)" % [label, ShowRules.STAGE_DONE, ShowRules.PODIUM, finished_at - done_at])
	stub.queue_free()
	show_cast()

## The rest of the show is unaffected by the stage rounds: a race round's card is CARD (4 s) with its start gate shut, a state without the stage flag.
func card_fixture() -> void:
	var host := FixtureHost.new([0, 1, 2, 3], 3)
	for row: Dictionary in RoundList.entries():
		if str(row.kind) == "race":
			host.pick = str(row.id)
			break
	var rules := ShowRules.new()
	rules.start(host)
	var first: Dictionary = rules.state()
	var ticks := 0
	while str(rules.phase) == "card" and ticks < 60 * 10:
		rules.tick(1.0 / 60.0)
		ticks += 1
	check(not bool(first.stage) and absf(float(first.count) - ShowRules.CARD) < 0.02 and absf(float(ticks) / 60.0 - ShowRules.CARD) < 0.05, "E: a race round's card is still %.1f s (count %.2f, play after %.2f s), not a stage round" % [ShowRules.CARD, float(first.count), float(ticks) / 60.0])
