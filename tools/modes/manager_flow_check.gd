extends SceneTree
## EXPERIMENT (switchable): THE MANAGER (modes/show/manager/, docs/party-show.md "The manager (experiment)") through the REAL local flow, as tools/modes/items_flow_check.gd plays
## the items: the app's own entry (client/solo_entry.gd for one player, client/presentation_entry.gd for two), the lobby circle, PLAY, the card, the play phase with the show's real
## view and HUD, and the REAL key path (InputEventKey into GameInput, the way a player types). Asserts what a player gets:
##   * the round has a manager (state.manager, a slot of the field), the intro banner THE MANAGER and the clipboard on that player's rig,
##   * the prompt: three cards on the manager's screen, the number keys asked for (`number_keys`), the key 2 picks the second card and uses nothing (the lab on: no lab item either, not even
##     from the key's second event), E (one player) / B (the second player of one keyboard) picks at random,
##   * the rule's banner and the effect on the player it is for (alone: the manager itself), and the effect is gone when the rule ends.
## `--players=1` (default: the solo app) or `--players=2`; `--pick=r31` (default: race 31) or `r25` (a tile round); `--split=1` (two players) a view each, the upside-down camera is then the victim's view only; `--lab=0` the cast without the lab (default on, as the Summer cast has it).
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/modes/manager_flow_check.gd" -- [--players=2 [--split=1]] [--pick=r25] [--lab=0]
## Prints MANAGER_FLOW lines and MANAGER_FLOW ok=<bool>; exits 1 on a failure.
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []
class SoloLocal extends "res://client/solo_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Catalog := preload("res://modes/show/shared/manager/manager_catalog.gd")
const ManagerRules := preload("res://modes/show/shared/manager/manager_rules.gd")

var players := 1
var pick := "r31"
var lab := true
var split_screen := false ## --split=1: two players get a view each (the shell's local_split_screen)
var failures := 0
var sim: Node
var flow: Node

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("MANAGER_FLOW ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--players="): players = clampi(int(argument.trim_prefix("--players=")), 1, 2)
		if argument.begins_with("--pick="): pick = argument.trim_prefix("--pick=")
		if argument.begins_with("--split="): split_screen = argument.trim_prefix("--split=") != "0"
		if argument.begins_with("--lab="): lab = argument.trim_prefix("--lab=") != "0"
	create_timer(280.0).timeout.connect(func() -> void:
		print("MANAGER_FLOW FAIL timed out")
		print("MANAGER_FLOW ok=false")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)

func state() -> Dictionary:
	return flow.minigame.state() if flow.minigame != null else {}

func manager():
	return flow.minigame.manager

func view():
	return flow._mode_view._manager

## Opens the next prompt now for `slot` (the clock's own first prompt is 22-30 s into the round).
func prompt_for(slot: int) -> bool:
	var m = manager()
	m.manager = slot
	m._next_at = m.time
	flow.minigame.gate.reset() # a rule that just ended keeps the event gate closed for 15 s: open it for the next prompt
	m.rule = -1
	var guard := 0
	while m.phase != ManagerRules.Phase.PROMPT and guard < 60 * 6:
		await physics_frame
		guard += 1
	await frames(6)
	if m.phase != ManagerRules.Phase.PROMPT: print("MANAGER_FLOW prompt did not open: phase %d, round phase %s, time %.1f, next %.1f, status %s, gone %s, targets %s, fell %s, t %.1f, left %.1f" % [m.phase, str(state().get("phase")), m.time, m._next_at, str(flow.minigame.status), str(flow.minigame.gone), str(m.targets), str(state().get("fell")), float(state().get("t", 0.0)), float(state().get("left", 0.0))])
	return m.phase == ManagerRules.Phase.PROMPT

## The effect of the rule on slot `slot` as the local machine applies it now.
func effect_on(slot: int) -> bool:
	var roll := absf(float(sim.follow.fx.get("roll", 0.0))) if slot == 0 else 0.0
	return not (sim.rule_mods.get(slot, {}) as Dictionary).is_empty() or sim.rule_scales.has(slot) or roll > 0.1

func run() -> void:
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["mode"] = "show"
	var section: Dictionary = (cast.get("show", {}) as Dictionary).duplicate(true) if cast.get("show") is Dictionary else {}
	section["item_lab"] = lab
	cast["show"] = section
	TeamCast.override(cast)
	root.mode = Window.MODE_WINDOWED
	root.always_on_top = false
	sim = SoloLocal.new() if players == 1 else VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("MANAGER_FLOW boot_timeout")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for taught in ["move", "jump", "tilt", "lift"]: hud_script.taught[taught] = true
	var ui = sim.local_presentation
	if players == 1: check(ui.started and sim.local_players == 1, "the solo app starts by itself: one player, no title page")
	else:
		ui.show_local_job()
		ui._input_mode_selected(2)
		await process_frame
		ui.start_job()
	if players == 2 and split_screen: sim.configure_local_split_screen(true)
	await frames(150)
	flow = ui.level_flow
	check(not RoundList.entry(pick).is_empty(), "the lobby has the circle %s" % pick)
	var centre := WalkInLobby.center(pick)
	if players == 1: sim.actors[0].position = centre + Vector3(0.0, 0.3, 0.0)
	else:
		sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
		sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	await frames(30)
	flow.press_play()
	var started := Time.get_ticks_msec()
	while flow.phase != "round" and Time.get_ticks_msec() - started < 20000: await frames(5)
	check(flow.phase == "round" and flow.minigame != null and flow.minigame_id == "show", "PLAY starts the show (%s)" % flow.phase)
	if flow.minigame == null:
		quit(1)
		return
	var guard := 0
	while (str(state().get("phase", "")) != "play" or float(state().get("t", 0.0)) < 1.6) and guard < 60 * 40:
		await physics_frame
		guard += 1
	var st := state()
	print("MANAGER_FLOW round %s level %d (%d players, lab %s)" % [str(st.get("kind", "")), int(st.get("level", -1)) + 1, players, str(lab)])
	var m = manager()
	flow.minigame.items._next_event_at = 1.0e9 # no boost or soar from the clock in the middle of the check
	check(m.enabled and st.has("manager") and (st.field as Array).has(int(st.manager.mgr)), "the round has a manager from the field (slot %d)" % m.manager)
	var anchor: Node = sim.rigs[m.manager].head_anchor() if sim.get("rigs") != null and sim.rigs.size() > m.manager and sim.rigs[m.manager] != null else null
	check(anchor != null and anchor.get_node_or_null("ManagerMarker") != null, "the clipboard is on the manager's head")
	var held_before: int = int(flow.minigame.items.held[0]) if flow.minigame.items.enabled else -1
	# 1. the first player (slot 0) is the manager: key 2
	check(await prompt_for(0), "the prompt opens for slot 0")
	var choices: Array = (m.choices as Array).duplicate()
	check(sim.number_keys, "the number keys are asked for while the prompt is open")
	check((view().hud._cards as Array).size() == 3 and (view().hud._cards as Array).all(func(card: Control) -> bool: return card.visible), "three cards on the manager's screen")
	await key(KEY_2)
	await frames(6)
	check(m.phase == ManagerRules.Phase.RULE and m.rule == int(choices[1]), "the key 2 picked the second card (%s)" % Catalog.id_of(m.rule))
	await frames(40) # the key's second event (the release) and the lab: still nothing
	if flow.minigame.items.enabled: check(int(flow.minigame.items.held[0]) == held_before, "no item was used or handed out by the pick (held %s)" % str(flow.minigame.items.held[0]))
	check(not sim.number_keys, "the number keys are free again once the rule is in")
	var victim := 0 if players == 1 else 1
	var told := false
	for step in 150: # the lead (0.9 s, alone 1.6 s) and then the rule is on
		await physics_frame
		if str(view().banner.get("words", "")) == Catalog.rule_text(Catalog.id_of(m.rule), "banner"): told = true
	await process_frame
	check((state().manager.tg as Array).has(victim) and not (players == 2 and (state().manager.tg as Array).has(0)), "the rule is for slot %d (%s)" % [victim, str(state().manager.tg)])
	check(told, "the rule's banner was shown: %s" % Catalog.rule_text(Catalog.id_of(m.rule), "banner"))
	check(effect_on(victim) or (Catalog.id_of(m.rule) == "upside" and victim != 0), "the rule is on slot %d in this machine (%s)" % [victim, Catalog.id_of(m.rule)])
	m._end_rule()
	await frames(80)
	check(sim.rule_mods.is_empty() and sim.rule_scales.is_empty() and absf(float(sim.follow.fx.get("roll", 0.0))) < 0.05, "the rule is gone when it ends")
	# 1b. the upside-down camera is the victims' (alone: the player's own), never the manager's
	check(await prompt_for(0), "the prompt opens for slot 0 again")
	m._issue(Catalog.index("upside"))
	await frames(150)
	var split: bool = sim.has_method("_split_views") and bool(sim.call("_split_views")) and (sim.split_follow as Array).size() >= 2
	var rolls: Array = [absf(float(sim.split_follow[0].fx.get("roll", 0.0))), absf(float(sim.split_follow[1].fx.get("roll", 0.0)))] if split else []
	var main_roll := absf(float(sim.follow.fx.get("roll", 0.0)))
	if players == 1: check(main_roll > 0.5, "alone the rule turns the player's own camera over (roll %.2f)" % main_roll)
	elif split: check(rolls[0] < 0.01 and rolls[1] > 0.5, "split screen: the victim's view (slot 1) is upside down (%.2f), the manager's (slot 0) is not (%.2f)" % [rolls[1], rolls[0]])
	else: check(main_roll > 0.5, "one shared view: a victim is on it, so it turns over (roll %.2f)" % main_roll)
	print("MANAGER_FLOW split screen %s" % str(split))
	if players == 2 and split_screen: check(split, "the two players have a view each")
	m._end_rule()
	await frames(80)
	check(absf(float(sim.follow.fx.get("roll", 0.0))) < 0.05 and (not split or (absf(float(sim.split_follow[0].fx.get("roll", 0.0))) < 0.05 and absf(float(sim.split_follow[1].fx.get("roll", 0.0))) < 0.05)), "every camera is upright again")
	# 2. the random pick: E alone, B for the second player of one keyboard
	if str(st.get("kind", "")) != "race": # the check's runners stand still: in a tile round they fall within seconds and the round (a show for one: alone; two: both out) is over, and the manager's state with it
		await frames(240)
		var over := str(state().get("phase", "")) != "play"
		check(not over or not state().has("manager"), "a tile round that ends takes the manager's state with it (phase %s)" % str(state().get("phase", "")))
		print("MANAGER_FLOW ok=", failures == 0)
		quit(1 if failures > 0 else 0)
		return
	var second := 0 if players == 1 else 1
	check(await prompt_for(second), "the prompt opens for slot %d" % second)
	var offered: Array = (m.choices as Array).duplicate()
	await key(KEY_E if players == 1 else KEY_B)
	await frames(6)
	check(m.phase == ManagerRules.Phase.RULE and offered.has(m.rule), "%s picked a random one of the three (%s)" % ["E" if players == 1 else "B", Catalog.id_of(m.rule)])
	m._end_rule()
	await frames(30)
	print("MANAGER_FLOW ok=", failures == 0)
	quit(1 if failures > 0 else 0)
