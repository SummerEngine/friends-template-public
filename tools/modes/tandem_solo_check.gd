extends SceneTree
## EXPERIMENT TANDEM in a show for ONE player (docs/party-show.md "Tandem (experiment)"), on the real solo app with real courier physics (client/solo_entry.gd, as tools/modes/show_bot_check.gd --solo boots it).
## The player runs in a circle in the lobby yard: after 2 s a buddy comes running along its trail, runs beside it and takes its hand; the pair walks 1.6 times as fast with the averaged steering, the banner says
## TANDEM!, the buddy's rig is drawn and holds hands; 6 s later the player is thrown and the buddy spins away; it comes again after the cooldown. Then PLAY starts the show and the same happens in the race.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s $PWD/tools/modes/tandem_solo_check.gd
## Prints TANDEM_SOLO lines and TANDEM_SOLO ok=<bool> last.
class SoloLocal extends "res://client/solo_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")

var sim: Node
var flow: Node
var failures := 0
var t := 0.0
var turn := 0.0

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("TANDEM_SOLO ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	create_timer(280.0).timeout.connect(func() -> void:
		print("TANDEM_SOLO FAIL timed out")
		print("TANDEM_SOLO ok=false")
		quit(1))
	run.call_deferred()

## One physics tick of running in a circle (the stick turns once every `period` s).
func _circle(period := 6.3, radius_scale := 1.0) -> void:
	turn += (TAU / period) * (1.0 / 60.0)
	sim._local_commands[0] = {"move": Vector2(sin(turn), -cos(turn)) * radius_scale, "action": false}
	await physics_frame
	t += 1.0 / 60.0

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	sim = SoloLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("TANDEM_SOLO boot_timeout")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for key in ["move", "jump", "tilt", "lift"]: hud_script.taught[key] = true
	for i in 150: await physics_frame
	flow = sim.local_presentation.level_flow
	check(flow.phase == "lobby" and flow.tandem != null and flow._tandem_view != null, "the solo app is in the lobby with the tandem built (phase %s)" % flow.phase)
	check(sim.local_players == 1 and not sim.is_slot_active(1), "one player")
	sim.actors[0].position = WalkInLobby.ORIGIN + Vector3(0.0, 0.5, 2.0) # open yard
	for i in 30: await physics_frame
	# ------------------------------------------------------------ the lobby
	t = 0.0
	var came := -1.0
	var fused := -1.0
	var speeds_alone: Array = []
	var speeds_fused: Array = []
	var phases := {}
	var held_hands := false
	var banner := ""
	var rig_seen := false
	var ended := -1.0
	var peak_after := 0.0
	var pops := 0
	while t < 22.0:
		await _circle()
		var tandem = flow.tandem
		var v: Vector3 = sim.actors[0].velocity
		var planar := Vector2(v.x, v.z).length()
		if not tandem.buddy.is_empty():
			phases[int(tandem.buddy.phase)] = true
			if came < 0.0: came = t
		if not tandem.pairs.is_empty():
			if fused < 0.0: fused = t
			if t - fused > 1.0: speeds_fused.append(planar)
			held_hands = held_hands or (sim.rig_hold.has(0) and sim.tandem.has(0) and int((sim.tandem[0] as Dictionary).with) == Tandem.BUDDY)
			rig_seen = rig_seen or flow._tandem_view.buddy_rig() != null
			if str(flow._tandem_view._banner.get("words", "")) != "": banner = str(flow._tandem_view._banner.words)
		elif fused < 0.0 and planar > 3.0: speeds_alone.append(planar)
		if fused >= 0.0 and tandem.pairs.is_empty() and ended < 0.0:
			ended = t
		if ended >= 0.0 and t - ended < 1.2: peak_after = maxf(peak_after, planar)
		pops = flow._tandem_view.pops
	check(came > 1.8 and came < 3.0, "a buddy comes after about 2 s of running (%.2f s)" % came)
	check(phases.has(Tandem.Phase.CHASE) and phases.has(Tandem.Phase.BESIDE) and phases.has(Tandem.Phase.FUSED), "it chases along the trail, runs beside the player and holds its hand (%s)" % str(phases.keys()))
	check(fused > 5.0 and fused < 9.0, "the player and the buddy fuse about 6 s in (%.2f s)" % fused)
	check(held_hands and rig_seen, "the owner's machine has the pair and the hand point, the buddy's rig is drawn (hold %s, rig %s)" % [str(held_hands), str(rig_seen)])
	check(banner == "TANDEM!" and pops == 1, "the banner says TANDEM! and the pop went off once (%s, %d)" % [banner, pops])
	var alone := _mean(speeds_alone)
	var together := _mean(speeds_fused)
	check(alone > 3.0 and together > alone * 1.4 and together < alone * 1.75, "the pair walks 1.6 times as fast: %.2f m/s against %.2f m/s alone" % [together, alone])
	check(ended > fused + 5.5 and ended < fused + 6.6, "six seconds later it ends (%.2f s after the fuse)" % (ended - fused))
	check(peak_after > together * 0.8, "and the player is thrown (peak %.1f m/s in the second after)" % peak_after)
	check(sim.tandem.is_empty() and sim.rig_hold.is_empty(), "the machine is free again")
	var again := -1.0
	while t < 40.0 and again < 0.0:
		await _circle()
		if not flow.tandem.pairs.is_empty(): again = t
	check(again > ended + 9.0, "the pair's cooldown holds: the next tandem is %.1f s after the end (>= 10 s: the cooldown, then the buddy's 2 s and 1.5 s)" % (again - ended))
	# ------------------------------------------------------------ the race
	for i in 60: await physics_frame
	var centre := WalkInLobby.center(str((WalkInLobby.shown_pads()[0] as Dictionary).course))
	sim.actors[0].position = centre + Vector3(0.0, 0.3, 0.0)
	for i in 60 * 2: await physics_frame
	flow.press_play()
	var t0 := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - t0 < 20000: await physics_frame
	check(flow.phase == "round" and flow.minigame != null and flow.minigame_id == "show", "PLAY starts the show (%s)" % flow.phase)
	var racing := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not racing:
		await physics_frame
		racing = str(flow.minigame.state().phase) == "play"
	check(racing and str(flow.minigame.state().kind) == "race", "the first round is a race (%s)" % str(flow.minigame.state().get("kind")))
	await physics_frame
	await physics_frame
	check(flow.tandem.scope == "race" and flow.tandem.active, "the tandem runs in the race (scope %s)" % flow.tandem.scope)
	check(flow.minigame.tandem_solo() and flow.minigame.tandem_ok(0), "a show for one: solo, and its racer may fuse")
	print("TANDEM_SOLO ok=", failures == 0)
	quit(1 if failures > 0 else 0)

func _mean(values: Array) -> float:
	if values.is_empty(): return 0.0
	var sum := 0.0
	for value: float in values: sum += value
	return sum / values.size()
