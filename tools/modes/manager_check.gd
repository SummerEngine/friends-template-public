extends SceneTree
## EXPERIMENT (switchable): THE MANAGER (modes/show/manager/, docs/party-show.md "The manager (experiment)"): the rules and the client view on a host of the script's, no engine flow.
##   A. a race with three players: one random manager of the field, the first prompt 22-30 s into the play with three different rules, a manager who says nothing gets a random rule after
##      3 s (the strip at the bottom edge), the rule applies to the two others (not the manager) 0.9 s after it was issued for 10-15 s, the next prompt 60-75 s after the first, the prompt and the rule hold the event gate (15 s closed after the rule), never the rule that was issued last
##   B. the keys: a number key (test_seq, seq * 8 + n) picks that card, ITEM picks a random one of the three, a press from before the prompt counts for nothing, items.gd leaves the presses alone
##   C. a bot manager picks after 1.2 s
##   D. a show for one: the rule hits the player itself, 1.6 s after it was issued
##   E. a tile round (a stage round, circle r25): the same flow in a survival round
##   F. the switch: manager.json `on`, `rounds`, `levels`, the cast's `show.manager.off`; no manager state when it is off
##   G. nobody to rule over (everybody else is out) opens no prompt; a manager who leaves is replaced
##   H. the cast's words, lengths and `off` per rule (show.manager)
##   I. what a rule does to a courier: gravity (moon), no jump, no dash, ice, walking pace (CourierMotion mods) and the merge of items and rules (game_run.gd slot_mods)
##   J. the client view on a stub shell: banner, clipboard on the manager's head, prompt, the mods and scales of the targets, the camera's roll, all cleared when the rule ends (solo and tile round)
## Prints MANAGER_CHECK ok=<bool> last; exits 1 on a failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 280 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s "$PWD/tools/modes/manager_check.gd"
const TeamCast := preload("res://style/team_cast.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const Catalog := preload("res://modes/show/shared/manager/manager_catalog.gd")
const ManagerRules := preload("res://modes/show/shared/manager/manager_rules.gd")
const Motion := preload("res://courier/courier_motion.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const DT := 1.0 / 60.0

## A host without a shell for the show's rules: positions, the buttons' counters and who is a bot are the script's.
class FixtureHost extends "res://modes/mode_host.gd":
	var positions: Array = []
	var zones: Array = []
	var retired: Array = []
	var tests := {} ## slot -> test_seq
	var items := {} ## slot -> item_seq
	var bots: Array = []
	func _init(round_seats: Array, seed_value := 1) -> void:
		super(null, round_seats, seed_value)
		for slot in count:
			positions.append(Vector3(slot, 0.05, 0.0))
			zones.append("")
	func active(slot: int) -> bool: return slot >= 0 and slot < count
	func item_boxes(_level: int) -> PackedVector3Array: return PackedVector3Array()
	func presses(slot: int, key: String) -> int: return int((tests if key == "test" else items).get(slot, 0))
	func is_bot(slot: int) -> bool: return bots.has(slot)
	func position(slot: int) -> Vector3: return positions[slot]
	func held_by(_slot: int) -> int: return -1
	func send_to(slot: int, at: Vector3, _yaw := 0.0) -> void: positions[slot] = at
	func begin_level(_level: int, out := []) -> void: retired = out.duplicate()
	func begin_podium(out: Array) -> void: retired = out.duplicate()
	func tile_start(_level: int, _players: int) -> PackedByteArray: return PackedByteArray()
	func tiles_under(slot: int, _level: int) -> Array: return [slot]
	func apply_tiles(_level: int, _steps: PackedByteArray) -> void: pass
	func zone(slot: int, _level: int) -> String: return str(zones[slot])
	func scorch(_slot: int, _level: int) -> String: return ""
	func checkpoint_at(_slot: int, _level: int) -> int: return -1
	func note_scorch(_slot: int, _kind: String) -> void: pass
	func respawn(slot: int, _level: int, _checkpoint: int) -> void: positions[slot] = Vector3(slot, 0.05, 0.0)
	func progress(_slot: int, _level: int) -> float: return 0.0
	func route_length(_level: int) -> float: return 100.0
	func level_clock() -> float: return 0.0
	func retire(slot: int) -> void: if not retired.has(slot): retired.append(slot)
	func podium(_level: int) -> Array: return [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]
	func hold(_slot: int, _at: Vector3, _radius: float, _rise := INF) -> void: pass
	func strays(_slot: int) -> int: return 0
	func release_holds() -> void: pass

var failures := 0
var StubRun: GDScript

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("MANAGER_CHECK ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	auto_accept_quit = false
	create_timer(270.0).timeout.connect(func() -> void:
		print("MANAGER_CHECK FAIL timed out")
		print("MANAGER_CHECK ok=false")
		quit(1))
	run_all.call_deferred()

func fixture_cast(players: int, extra := {}) -> void:
	var list := []
	for index in players: list.append({"name": "Player%d" % (index + 1), "color": ["#ff5a36", "#2c4bff", "#2ec27e", "#f2c230", "#9a4dff", "#00b8d9"][index % 6]})
	var cast := {"format": "team-cast-v2", "team": {"name": "Manager Check"}, "players": list, "mode": "show"}
	if not extra.is_empty(): cast["show"] = extra
	TeamCast.override(cast)

## A show of one round on the circle `pick` with `players` players, in its play phase.
func begin(pick: String, players: int, seed_value := 3, cast_show := {}) -> Array:
	fixture_cast(players, cast_show)
	var host := FixtureHost.new(range(players), seed_value)
	host.pick = pick
	var rules := ShowRules.new()
	rules.start(host)
	var ticks := 0
	while str(rules.phase) != "play" and ticks < 60 * 12:
		rules.tick(DT)
		ticks += 1
	return [rules, host]

## The next prompt is due in `delay` s: the event gate is opened too (a rule that just ended keeps it closed for 15 s).
func due(rules, delay := 0.2) -> void:
	rules.manager._next_at = rules.manager.time + delay
	rules.gate.reset()

## Ticks until `until` holds (at most `seconds`); returns the seconds it took.
func run_until(rules, until: Callable, seconds: float) -> float:
	var ticks := 0
	while not until.call() and ticks < int(seconds * 60.0):
		rules.tick(DT)
		ticks += 1
	return float(ticks) / 60.0

func run_all() -> void:
	StubRun = load((get_script() as Script).resource_path.get_base_dir() + "/stub_run.gd")
	check(bool(Catalog.data().get("on", false)), "manager.json is on in the template (the experiment ships on)")
	check(Catalog.order().size() == 8 and Catalog.offered().size() == 8, "eight rules in the order of the file (%s)" % str(Catalog.order()))
	scenario_race()
	scenario_keys()
	scenario_bot()
	scenario_solo()
	scenario_tile()
	scenario_switch()
	scenario_nobody()
	scenario_cast()
	scenario_motion()
	await scenario_view()
	TeamCast.override({})
	print("MANAGER_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ A

func scenario_race() -> void:
	var made := begin("r31", 3)
	var rules: ShowRules = made[0]
	var m: ManagerRules = rules.manager
	check(m.enabled and rules.field.has(m.manager) and str(rules.kind) == "race", "A: a race round of three has a manager from the field (slot %d)" % m.manager)
	var st: Dictionary = rules.state()
	check(st.has("manager") and int(st.manager.mgr) == m.manager and int(st.manager.ph) == 0, "A: the show's state carries `manager` (mgr %d, idle)" % int(st.manager.mgr))
	var first := run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 40.0)
	check(first >= 22.0 - 4.5 and first <= 30.0, "A: the first prompt comes %.1f s into the play (22-30 s of play, the card's tail counted)" % first)
	var choices: Array = m.choices.duplicate()
	check(choices.size() == 3 and choices[0] != choices[1] and choices[1] != choices[2] and choices[0] != choices[2], "A: the prompt offers three different rules (%s)" % str(choices))
	check(m.takes_presses(m.manager) and not m.takes_presses((m.manager + 1) % 3), "A: only the manager's presses are taken while the prompt is open")
	st = rules.state()
	check(int(st.manager.ph) == 1 and (st.manager.ch as Array) == choices and float(st.manager.t) > 2.0, "A: the state says PROMPT with the choices and the seconds left (%.1f)" % float(st.manager.t))
	var opened := m.time
	var waited := run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.RULE, 12.0)
	check(waited >= 2.8 and waited <= 3.3 and choices.has(m.rule), "A: a manager who says nothing gets a random one of the three after 3 s (%.2f s, rule %s)" % [waited, Catalog.id_of(m.rule)])
	check(m.seq == 1 and is_equal_approx(m.age, -0.9), "A: it counts as rule 1, to start 0.9 s later (age %.2f)" % m.age)
	var expected: Array = [0, 1, 2]
	expected.erase(m.manager)
	var got: Array = m.targets.duplicate()
	got.sort()
	check(got == expected, "A: the rule applies to the two others, not the manager (%s)" % str(got))
	var id := Catalog.id_of(m.rule)
	var spec: Array = Catalog.spec(id).duration
	check(m.dur >= float(spec[0]) - 0.11 and m.dur <= float(spec[1]) + 0.11, "A: %s lasts %.1f s (the rule's own %.0f-%.0f s)" % [id, m.dur, float(spec[0]), float(spec[1])])
	check(m.dur >= 9.9 and m.dur <= 15.1, "A: every rule lasts 10-15 s")
	check(rules.gate.running == "manager", "A: the prompt and the rule hold the event gate (%s)" % rules.gate.running)
	var last := m.rule
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 20.0)
	check(rules.gate.running == "" and not rules.gate.open(), "A: the rule's end frees the gate, closed for 15 s after it")
	check(m.phase == ManagerRules.Phase.IDLE and int(rules.state().manager.rule) == -1, "A: the rule ends and the state is idle again")
	var second := run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 90.0)
	var spacing := m.time - opened
	check(spacing >= 60.0 and spacing <= 75.1, "A: the next prompt comes %.1f s after the first (60-75 s)" % spacing)
	check(not m.choices.has(last), "A: the rule issued last (%s) is not offered again (%s)" % [Catalog.id_of(last), str(m.choices)])
	var size := var_to_bytes(rules.state().manager).size()
	check(size < 400, "A: the manager's state is small (%d B)" % size)
	rules.manager.finish()
	check(m.phase == ManagerRules.Phase.IDLE and m.targets.is_empty(), "A: the round's end clears the prompt and the rule")
	_ignore(second)

func _ignore(_value: Variant) -> void:
	pass

# ------------------------------------------------------------------ B

func scenario_keys() -> void:
	var made := begin("r31", 3)
	var rules: ShowRules = made[0]
	var host: FixtureHost = made[1]
	var m: ManagerRules = rules.manager
	host.tests[m.manager] = (5 << 3) | 1 # a press from before the prompt
	host.items[m.manager] = 7
	due(rules)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 3.0)
	rules.tick(DT)
	check(m.phase == ManagerRules.Phase.PROMPT, "B: a press from before the prompt counts for nothing")
	var choices: Array = m.choices.duplicate()
	host.tests[m.manager] = (6 << 3) | 2
	rules.tick(DT)
	check(m.phase == ManagerRules.Phase.RULE and m.rule == int(choices[1]), "B: the number key 2 picks the second card (%s)" % Catalog.id_of(m.rule))
	check(m.takes_presses(m.manager), "B: the manager's presses are still its own right after the pick (the key's second event is not a lab item)")
	run_until(rules, func() -> bool: return false, ManagerRules.ECHO + 0.1)
	check(not m.takes_presses(m.manager), "B: and are free again after %.1f s" % ManagerRules.ECHO)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 20.0)
	due(rules)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 3.0)
	choices = m.choices.duplicate()
	host.tests[m.manager] = (7 << 3) | 6 # a number the prompt does not have
	rules.tick(DT)
	check(m.phase == ManagerRules.Phase.PROMPT, "B: a key the prompt has no card for (6) is no pick")
	host.items[m.manager] = 8
	rules.tick(DT)
	check(m.phase == ManagerRules.Phase.RULE and choices.has(m.rule), "B: ITEM picks a random one of the three (%s)" % Catalog.id_of(m.rule))
	# a key of somebody else is nobody's pick
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 20.0)
	due(rules)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 3.0)
	var other := (m.manager + 1) % 3
	host.tests[other] = (1 << 3) | 1
	host.items[other] = 1
	rules.tick(DT)
	check(m.phase == ManagerRules.Phase.PROMPT, "B: the others' keys pick nothing")

# ------------------------------------------------------------------ C

func scenario_bot() -> void:
	var made := begin("r31", 3, 5)
	var rules: ShowRules = made[0]
	var host: FixtureHost = made[1]
	var m: ManagerRules = rules.manager
	host.bots = [m.manager]
	due(rules)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 3.0)
	var waited := run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.RULE, 12.0)
	check(waited >= 1.1 and waited <= 1.4, "C: a bot manager picks at random after 1.2 s (%.2f s)" % waited)

# ------------------------------------------------------------------ D

func scenario_solo() -> void:
	var made := begin("r31", 1)
	var rules: ShowRules = made[0]
	var m: ManagerRules = rules.manager
	check(m.enabled and m.solo and m.manager == 0, "D: a show for one: you are the manager")
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 40.0)
	check(m.phase == ManagerRules.Phase.PROMPT and m.targets == [0], "D: the prompt opens and the only one to rule over is you")
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.RULE, 12.0)
	check(is_equal_approx(m.age, -1.6) and m.targets == [0], "D: the rule is to hit you, %.1f s after it was issued (age %.2f)" % [1.6, m.age])
	run_until(rules, func() -> bool: return m.age >= 0.0, 5.0)
	check(m.age >= 0.0 and int(rules.state().manager.tg[0]) == 0 and bool(rules.state().manager.solo), "D: then it is on: the state lists you as the target")

# ------------------------------------------------------------------ E

func scenario_tile() -> void:
	var made := begin("r25", 3, 9)
	var rules: ShowRules = made[0]
	var m: ManagerRules = rules.manager
	check(str(rules.kind) == "survival" and bool(rules.state().stage), "E: circle r25 is a tile round")
	check(m.enabled and rules.field.has(m.manager), "E: a tile round has a manager too (slot %d)" % m.manager)
	var first := run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 40.0)
	check(m.phase == ManagerRules.Phase.PROMPT and first >= 12.0 and first <= 30.0, "E: the first prompt comes %.1f s into the play" % first)
	rules.host.tests[m.manager] = (2 << 3) | 3
	rules.tick(DT)
	var expected: Array = [0, 1, 2]
	expected.erase(m.manager)
	var got: Array = m.targets.duplicate()
	got.sort()
	check(m.phase == ManagerRules.Phase.RULE and got == expected, "E: key 3 issues %s to the two others" % Catalog.id_of(m.rule))
	check(rules.state().has("manager"), "E: the state carries `manager` in the tile round")
	rules.manager.finish()

# ------------------------------------------------------------------ F

func scenario_switch() -> void:
	var saved: Dictionary = Catalog.data().duplicate(true)
	Catalog._data["on"] = false
	var rules: ShowRules = begin("r31", 3)[0]
	check(not rules.manager.enabled and not rules.state().has("manager"), "F: \"on\": false: no manager, no state key")
	Catalog._data = saved.duplicate(true)
	(Catalog._data.rounds as Dictionary)["race"] = {"on": false}
	check(not Catalog.on_for(30, "race") and Catalog.on_for(24, "survival"), "F: rounds.race off: races have none, tile rounds do")
	rules = begin("r31", 3)[0]
	check(not rules.manager.enabled, "F: a race round plays with no manager")
	(Catalog._data.levels as Dictionary)["31"] = {"on": true}
	check(Catalog.on_for(30, "race") and not Catalog.on_for(28, "race"), "F: levels.\"31\" on wins over rounds.race off")
	Catalog._data = saved.duplicate(true)
	(Catalog._data.levels as Dictionary)["25"] = {"on": false}
	check(not Catalog.on_for(24, "survival") and Catalog.on_for(25, "survival"), "F: levels.\"25\" off: that tile round has none, the next one does")
	Catalog._data = saved.duplicate(true)
	fixture_cast(3, {"manager": {"off": true}})
	check(not Catalog.on_for(30, "race"), "F: the cast's show.manager.off takes the experiment out of its show")
	fixture_cast(3)
	Catalog._data = saved
	check(Catalog.on_for(30, "race"), "F: and everything is back")

# ------------------------------------------------------------------ G

func scenario_nobody() -> void:
	var made := begin("r31", 2)
	var rules: ShowRules = made[0]
	var m: ManagerRules = rules.manager
	var other := 1 - m.manager
	rules.status[other] = ShowRules.OUT
	due(rules)
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 4.0)
	check(m.phase == ManagerRules.Phase.IDLE, "G: nobody left to rule over: no prompt")
	rules.status[other] = ShowRules.PLAYING
	run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 4.0)
	check(m.phase == ManagerRules.Phase.PROMPT and m.targets == [other], "G: the other is back in: the prompt opens, the rule is for them")
	var gone: int = m.manager
	rules.drop(gone)
	check(m.manager != gone and m.manager == other, "G: a manager who left is replaced by the other player (slot %d)" % m.manager)

# ------------------------------------------------------------------ H

func scenario_cast() -> void:
	fixture_cast(3, {"manager": {"title": "new manager", "line": "{manager} has opinions", "prompt": "give an order", "rules": [
		{"id": "nojump", "name": "no jumps in prod", "banner": "manager says: feature freeze", "line": "{manager} SAYS SO", "tuning": {"duration": 5}},
		{"id": "tiny", "off": true}]}})
	check(Catalog.text("title") == "NEW MANAGER" and Catalog.text("prompt") == "GIVE AN ORDER", "H: the cast's title and prompt (upper case)")
	check(Catalog.text("line", "Maya") == "MAYA HAS OPINIONS", "H: {manager} is filled in (%s)" % Catalog.text("line", "Maya"))
	check(Catalog.text("you") == "YOU MAKE THE RULES", "H: a text the cast leaves is the template's")
	check(Catalog.rule_text("nojump", "name") == "NO JUMPS IN PROD".left(16) and Catalog.rule_text("nojump", "banner") == "MANAGER SAYS: FEATURE FREEZE", "H: a rule's name (16 characters) and banner")
	check(Catalog.rule_text("flip", "banner") == "INVERTED!" and Catalog.rule_text("flip", "line", "Maya") == "MAYA'S RULE", "H: a rule the cast leaves has the template's neutral words")
	var rng := RandomNumberGenerator.new()
	check(is_equal_approx(Catalog.duration("nojump", rng), 5.0), "H: the cast's tuning.duration sets the length")
	check(not Catalog.offered().has("tiny") and Catalog.offered().size() == 7, "H: a rule the cast switches off is not offered")
	var made := begin("r31", 3, 11, {"manager": {"rules": [{"id": "tiny", "off": true}]}})
	var rules: ShowRules = made[0]
	var m: ManagerRules = rules.manager
	var tiny := Catalog.index("tiny")
	var seen_tiny := false
	for round_number in 30:
		due(rules, 0.1)
		run_until(rules, func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 3.0)
		seen_tiny = seen_tiny or m.choices.has(tiny)
		(made[1] as FixtureHost).items[m.manager] = int((made[1] as FixtureHost).items.get(m.manager, 0)) + 1
		rules.tick(DT)
		m.age = m.dur # end it at once
		rules.tick(DT)
	check(not seen_tiny, "H: thirty prompts never offered the rule that is off")
	fixture_cast(3)

# ------------------------------------------------------------------ I

func air_speed(mods: Dictionary) -> float:
	var body := Motion.make_body("Fall")
	root.add_child(body)
	body.global_position = Vector3(0.0, 5000.0, 0.0)
	var motion = Motion.new()
	motion.set_mods(mods)
	for step in 6: motion.step(body, {"move": Vector2.ZERO, "jump": false, "dash": false}, DT)
	var result := body.velocity.y
	body.queue_free()
	return result

func try_press(mods: Dictionary, key: String) -> bool:
	var body := Motion.make_body("Press")
	root.add_child(body)
	body.global_position = Vector3(0.0, 5000.0, 0.0)
	var motion = Motion.new()
	motion.set_mods(mods)
	motion.grounded = true
	var events: Dictionary = motion.step(body, {"move": Vector2.ZERO, "jump": key == "jump", "dash": key == "dash"}, DT)
	body.queue_free()
	return bool(events.get("jumped" if key == "jump" else "dashed", false))

func slide(mods: Dictionary) -> float:
	var body := Motion.make_body("Slide")
	root.add_child(body)
	body.global_position = Vector3(0.0, 5000.0, 0.0)
	var motion = Motion.new()
	motion.set_mods(mods)
	body.velocity = Vector3(8.0, 0.0, 0.0)
	motion.grounded = true
	motion.step(body, {"move": Vector2.ZERO, "jump": false, "dash": false}, 0.2)
	var result := absf(body.velocity.x)
	body.queue_free()
	return result

func walking(mods: Dictionary) -> float:
	var body := Motion.make_body("Walk")
	root.add_child(body)
	body.global_position = Vector3(0.0, 5000.0, 0.0)
	var motion = Motion.new()
	motion.set_mods(mods)
	for step in 90:
		motion.grounded = true
		motion.step(body, {"move": Vector2(0.0, -1.0), "jump": false, "dash": false}, DT)
	var result := Vector2(body.velocity.x, body.velocity.z).length()
	body.queue_free()
	return result

func scenario_motion() -> void:
	var normal := air_speed({})
	var moon := air_speed(Catalog.mods("moon"))
	check(normal < -1.0 and absf(moon / normal - 0.28) < 0.04, "I: the moon rule: falling at %.0f %% of the normal pull (%.2f vs %.2f m/s after 0.1 s)" % [moon / normal * 100.0, moon, normal])
	check(try_press({}, "jump") and not try_press(Catalog.mods("nojump"), "jump"), "I: no jumping: the jump press is ignored")
	check(try_press({}, "dash") and not try_press(Catalog.mods("walk"), "dash"), "I: walk only: the dash press is ignored")
	var plain := slide({})
	var icy := slide(Catalog.mods("ice"))
	check(icy > plain * 1.5 and icy > 6.0, "I: ice: a courier at 8 m/s keeps %.1f m/s after 0.2 s of ground, not %.1f" % [icy, plain])
	var pace := walking({})
	var slow := walking(Catalog.mods("walk"))
	check(pace > 3.0 and absf(slow / pace - 0.5) < 0.08, "I: walk only: top speed %.1f m/s instead of %.1f (half)" % [slow, pace])
	var shell: Node = load("res://game/game_run.gd").new()
	shell.item_mods = {0: {"invert": true, "speed": 1.45, "air_jumps": 1}}
	shell.rule_mods = {0: {"speed": 0.5, "no_jump": true, "gravity": 0.28}, 1: Catalog.mods("flip")}
	var merged: Dictionary = shell.slot_mods(0)
	check(bool(merged.invert) and bool(merged.no_jump) and absf(float(merged.speed) - 0.725) < 0.001 and absf(float(merged.gravity) - 0.28) < 0.001 and int(merged.air_jumps) == 1, "I: items and rules merge on one courier (flags either, speeds multiply): %s" % str(merged))
	var step := Vector2(0.6, -0.8)
	check(shell.item_move(1, step) == -step and shell.item_move(2, step) == step, "I: the inverted rule flips the steering of its slot only")
	shell.free()

# ------------------------------------------------------------------ J

func scenario_view() -> void:
	for variant: Array in [["r31", 1, "solo race"], ["r25", 2, "tile round"]]:
		var label := "J (%s)" % str(variant[2])
		var players := int(variant[1])
		var made := begin(str(variant[0]), players, 13)
		var rules: ShowRules = made[0]
		var host: FixtureHost = made[1]
		var m: ManagerRules = rules.manager
		var stub: Node = StubRun.new()
		root.add_child(stub)
		stub.call("make", players, true)
		var seats := range(players)
		var views: Array = []
		for slot in players:
			var view: Node3D = ModeViews.new_view("show")
			(stub.get("world") as Node3D).add_child(view)
			view.setup(stub, seats, slot)
			views.append(view)
		var saw := {"intro": "", "marker": false, "banner": "", "kind": "", "slots": [], "number_keys": false, "keys_elsewhere": false, "others_waiting": false, "ended": false}
		var rule_id := ""
		m._next_at = 6.0 if players == 1 else 5.0
		var pressed := false
		var frames := 0
		while frames < 60 * 40:
			rules.tick(DT)
			frames += 1
			var st: Dictionary = rules.state()
			if str(st.phase) == "play" and m.phase == ManagerRules.Phase.PROMPT and not pressed and m.left < float(Catalog.timing("prompt")) - 1.0:
				pressed = true
				host.tests[m.manager] = (9 << 3) | 3 # the number key 3 picks the third card
			if frames % 3 != 0: continue
			for index in views.size():
				var view: Node3D = views[index]
				view.present(st, 0.05)
				var manager_view: Node3D = view.get("_manager")
				var info: Dictionary = manager_view.get("info")
				var prompt_open := int(info.get("ph", 0)) == 1
				if prompt_open and index == m.manager: saw.number_keys = saw.number_keys or bool(stub.get("number_keys"))
				if prompt_open and index != m.manager:
					saw.others_waiting = true
					saw.keys_elsewhere = saw.keys_elsewhere or bool(stub.get("number_keys")) # a screen that is not the manager's never asks for the number keys
				if index != 0: continue
				var words: String = str(manager_view.banner.get("words", ""))
				if words == "THE MANAGER" and saw.intro == "": saw.intro = str(manager_view.banner.get("line", ""))
				if int(info.get("ph", 0)) == 2:
					rule_id = Catalog.id_of(int(info.rule))
					if words == Catalog.rule_text(rule_id, "banner"):
						saw.banner = words
						saw.kind = str(manager_view.banner.kind)
					if float(manager_view.get("_age")) > 0.7 and (saw.slots as Array).is_empty():
						var held: Array = (stub.get("rule_mods") as Dictionary).keys() + (stub.get("rule_scales") as Dictionary).keys()
						held.sort()
						saw.slots = held
			var head: Variant = (stub.get("rigs") as Array)[m.manager]
			if head != null and (head as Node).has_method("head_anchor"):
				var anchor: Node3D = head.call("head_anchor")
				if anchor != null and anchor.get_node_or_null("ManagerMarker") != null: saw.marker = true
			if m.seq >= 1 and m.phase == ManagerRules.Phase.IDLE and rule_id != "":
				saw.ended = true
				for view: Node3D in views: view.present(rules.state(), 0.05) # one more frame after the end: everything goes
				break
			await process_frame
		check(saw.marker, "%s: the clipboard hangs on the manager's head anchor (slot %d)" % [label, m.manager])
		var told := "YOU MAKE THE RULES" if m.manager == 0 else "PLAYER%d MAKES THE RULES" % (m.manager + 1)
		check(saw.intro == told, "%s: the round's first banner, THE MANAGER, says who (%s)" % [label, saw.intro])
		check(rule_id != "" and saw.banner == Catalog.rule_text(rule_id, "banner"), "%s: the rule's banner: %s" % [label, saw.banner])
		var hits_zero := players == 1 or m.manager != 0
		check(saw.kind == ("alert" if hits_zero else "item"), "%s: the banner is red where the rule hits and blue elsewhere (%s on the first player's screen)" % [label, saw.kind])
		var effect := not Catalog.mods(rule_id).is_empty() or Catalog.scale_of(rule_id) != Vector3.ONE
		var wanted: Array = [0] if players == 1 else range(players).filter(func(slot: int) -> bool: return slot != m.manager)
		check(not effect or (saw.slots as Array) == wanted, "%s: %s is on %s and on nobody else (%s)" % [label, rule_id, str(wanted), str(saw.slots)])
		check(saw.number_keys and not saw.keys_elsewhere, "%s: the number keys are asked for on the manager's screen only" % label)
		check(saw.ended and (stub.get("rule_mods") as Dictionary).is_empty() and (stub.get("rule_scales") as Dictionary).is_empty() and not bool(stub.get("number_keys")), "%s: when it ends nothing of it is left on the shell" % label)
		if players > 1: check(saw.others_waiting, "%s: the others read that the manager is picking" % label)
		stub.queue_free()
		await process_frame
