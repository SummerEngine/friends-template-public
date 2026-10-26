extends SceneTree
## Headless check of WHO SAID IT? (docs/modes/who_said_it.md). Plays whole games of the rules through FakeHost with scripted players
## (2, 4 and 10; each runs to a pad by script: fast, slow, to a wrong pad, stands still, or already stands on the right pad before the
## line shows) and checks the scores, a player who leaves, the end and the results; the lines with and without catchphrases; the pad
## ring for every player count against the yard's furniture. Then presents every captured state in the view under StubRun (with the
## real rigs, so the statues are characters) and the mode HUD.
## Run (never windowed):
##   /opt/homebrew/bin/python3 ~/.claude/skills/engine-runs-summer/engine_run.py --timeout 600 -- <Summer> --headless \
##     --audio-driver Dummy --rendering-driver dummy --path demo -s "$PWD/tools/modes/who_said_it_check.gd"
## Prints MODE_CHECK who_said_it ok=<bool> last; exits 1 on a failure.
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const TeamCast := preload("res://style/team_cast.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Rig := preload("res://character/character_rig.gd")
const Rules := preload("res://modes/who_said_it/rules.gd")
const ID := "who_said_it"
const DT := 1.0 / 60.0
const FAST := 6.0 ## m/s of a fast scripted player ...
const SLOW := 3.5 ## ... and of a slow one
const FAST_DELAY := 0.3 ## s after the line shows before a fast (or wrong) scripted player sets off ...
const SLOW_DELAY := 2.0 ## ... and a slow one: a fast one is always first
## Nine catchphrases (Kai's too long for the HUD's big word), emotes, and Vera without a line.
const CAST := {"format": "team-cast-v2", "team": {"name": "Who Check"}, "mode": "who_said_it",
	"players": [{"name": "Maya", "catchphrase": "Ship it!", "emote": "dance"}, {"name": "Theo", "catchphrase": "On my way!", "emote": "yes"},
		{"name": "Ida", "catchphrase": "Coffee first"}, {"name": "Noor", "catchphrase": "Quick one?", "emote": "think"},
		{"name": "Leo", "catchphrase": "Let me check the logs"}, {"name": "Sana", "catchphrase": "Looks good to me", "emote": "point"},
		{"name": "Omar", "catchphrase": "Who moved my chair?"}, {"name": "Juno", "catchphrase": "Back in five", "emote": "sit"},
		{"name": "Kai", "catchphrase": "Has anyone tried turning it off and on again this week?"}, {"name": "Vera", "emote": "cry"}],
	"eggs": ["Someone always brings snacks"]}
## Furniture of the yard (lobby_space.gd, lobby/playground.gd, lobby_visuals.gd floor word), yard-local x, z: boxes [x0, z0, x1, z1]
## and circles [x, z, radius]. Pads and statues keep clear of all of them.
const BOXES := [[-8.4, -13.0, -6.8, -8.4], [6.5, -13.3, 9.5, -8.0], [-10.0, 4.4, -6.1, 8.2], [7.3, 4.8, 7.9, 8.8], [3.5, 7.3, 6.3, 10.0],
	[-10.0, -0.25, -9.7, 1.25], [-9.9, 9.1, -8.8, 9.9], [-3.2, 2.85, 3.2, 3.95], [-1.0, -14.0, 1.0, -13.5]]
const CIRCLES := [[0.0, -9.4, 1.45], [-9.4, -3.0, 0.3], [9.4, -2.5, 0.3], [-2.95, 9.45, 0.3], [2.95, 9.45, 0.3]]
const PAD_PAINT := 1.35 ## the view's painted ring
const STATUE_REACH := 1.37 ## the view's statue: 0.95 out from the pad's middle, plinth radius 0.42

var FakeHost: GDScript
var StubRun: GDScript
var failures := 0

func expect(label: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("MODE_CHECK who_said_it ", "ok  " if ok else "FAIL", " ", label, " ", detail)

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: # a script error stops _run: never hang the guard
		print("MODE_CHECK who_said_it FAIL timed out")
		print("MODE_CHECK who_said_it ok=false")
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	FakeHost = load(here + "/fake_host.gd")
	StubRun = load(here + "/stub_run.gd")
	check_ring()
	TeamCast.override(CAST)
	check_lines()
	# Two players: the fast one is always first.
	var two := play([0, 1], ["fast", "slow"])
	expect_game("2 players", two, [30, 10], "MAYA WINS", [0])
	expect("2 players: the line alternates (two catchphrases, never twice in a row)", two.lines.size() == 2 and two.repeats == 0, str(two.lines))
	expect("2 players: everybody back on the start ring every round", (two.host.sent as Array).size() == 20 and two.on_ring, "%d sends" % (two.host.sent as Array).size())
	# Four: a wrong runner, one who stands on the right pad before the line shows (1, never 3), a slow one who leaves after round 5.
	var four := play([0, 1, 2, 3], ["fast", "wrong", "early", "slow"], {6: [3]})
	expect_game("4 players", four, [30, 0, 10, 5], "MAYA WINS", [0])
	var sent: Array = four.host.sent
	var cut := int(four.dropped_at)
	var sent_before := sent.slice(0, cut).filter(func(entry: Array) -> bool: return int(entry[0]) == 3).size()
	var sent_after := sent.slice(cut).filter(func(entry: Array) -> bool: return int(entry[0]) == 3).size()
	expect("4 players: the one who left is sent nowhere after it left", cut > 0 and sent_before == 6 and sent_after == 0, "%d sends before, %d after" % [sent_before, sent_after])
	expect("4 players: out lists the one who left", four.last.get("out", []) == [3], str(four.last.get("out", [])))
	expect("4 players: its pad's lines still come up", four.answers.has(3), str(four.answers))
	# Ten: Maya fast on odd rounds, Theo on even ones (a tie at 20), slow, wrong, still and early runners; Vera has no line.
	var ten := play(range(10), ["fast_odd", "fast_even", "slow", "wrong", "still", "early", "slow", "wrong", "slow", "still"])
	expect_game("10 players", ten, [20, 20, 10, 0, 0, 10, 10, 0, 10, 0], "TIE: MAYA & THEO", [0, 1])
	expect("10 players: nine lines (Vera has none), never twice in a row", ten.lines.size() == 9 and ten.repeats == 0 and not ten.answers.has(9), str(ten.answers))
	# Nobody scores.
	var none := play([2, 4], ["still", "still"])
	expect_game("nobody scores", none, [0, 0], "NO WINNER", [])
	# One catchphrase in the round: the words and the egg fill in.
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Who Check"}, "words": {"pop": "BOOM!"}, "eggs": ["Someone always brings snacks"],
		"players": [{"name": "Ada", "catchphrase": "Hello there"}, {"name": "Bo"}, {"name": "Cy"}]})
	var filler := play([0, 1, 2], ["fast", "wrong", "wrong"], {}, 11)
	expect_game("one catchphrase, words and eggs fill in", filler, [30, 0, 0], "ADA WINS", [0])
	var asked: Array = filler.rules.lines.filter(func(line: Dictionary) -> bool: return bool(line.ask))
	var texts: Array = asked.map(func(line: Dictionary) -> String: return str(line.text))
	expect("filler: six words (BOOM! for pop) and the egg, asked", asked.size() == 7 and texts.has("BOOM!") and texts.has("DELIVERED") and texts.has("Someone always brings snacks"), str(texts))
	var robin := true
	for k in range(1, asked.size()): robin = robin and int(asked[k].slots[0]) == (int(asked[k - 1].slots[0]) + 1) % 3
	expect("filler: given to the characters round-robin", robin, str(asked.map(func(line: Dictionary) -> int: return int(line.slots[0]))))
	expect("filler: \"Who would say: <line>?\"", Rules.prompt("Someone always brings snacks", true) == "Who would say: Someone always brings snacks?" and Rules.prompt("BOOM!", true) == "Who would say: BOOM!" and Rules.prompt("Hello there", false) == "Hello there")
	expect("filler: never twice in a row", filler.repeats == 0)
	await present_game(filler, [0, 1, 2])
	# Two characters with the same catchphrase: both pads are right.
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Who Check"}, "players": [{"name": "Ada", "catchphrase": "Same!"}, {"name": "Bo", "catchphrase": "same!"}, {"name": "Cy", "catchphrase": "Other"}]})
	var twins = Modes.new_rules(ID)
	twins.start(FakeHost.new([0, 1, 2], 3))
	expect("the same catchphrase twice: one line, both pads right", twins.lines.size() == 2 and (twins.lines[0].slots as Array) == [0, 1], str(twins.lines))
	TeamCast.override(CAST)
	await present_game(two, [0, 1])
	await present_game(four, [0, 1, 2, 3])
	await present_game(ten, range(10))
	TeamCast.override({})
	print("MODE_CHECK who_said_it ok=", failures == 0)
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ rules

## A whole game: `plan` per slot (fast, slow, fast_odd, fast_even, wrong, still, early), `drops` round -> slots that leave as it starts.
func play(seats: Array, plan: Array, drops := {}, seed_value := 7) -> Dictionary:
	var host = FakeHost.new(seats, seed_value)
	var rules = Modes.new_rules(ID)
	rules.start(host)
	var pads: Array = Rules.pads(seats.size())
	var result := {"host": host, "rules": rules, "states": [], "repeats": 0, "answers": [], "lines": [], "on_ring": true, "biggest": 0,
		"leaked": false, "plain": true, "last": {}, "dropped_at": -1}
	var started := 0.0
	var before := ""
	var line_before := ""
	var ticks := 0
	while not rules.finished() and ticks < 60 * 200:
		if drops.has(rules.number) and rules.phase == "ready":
			for slot: int in drops[rules.number]:
				if host.actives[slot]:
					host.actives[slot] = false
					rules.drop(slot)
					result.dropped_at = (host.sent as Array).size()
		drive(host, rules, plan, pads, started)
		var sent_before: int = (host.sent as Array).size()
		rules.tick(DT)
		ticks += 1
		for entry: Array in (host.sent as Array).slice(sent_before):
			var flat := Vector2((entry[1] as Vector3).x - Rules.middle().x, (entry[1] as Vector3).z - Rules.middle().z).length()
			if absf(flat - Rules.START_RADIUS) > 0.01: result.on_ring = false
		var changed: bool = rules.phase != before
		if changed:
			before = rules.phase
			if rules.phase == "run":
				started = rules.time
				var line := str(rules.state().line)
				if line == line_before: result["repeats"] = int(result["repeats"]) + 1
				line_before = line
				if not (result.lines as Array).has(line): result.lines.append(line)
				result.answers.append_array(rules.answer_slots())
		if changed or ticks % 6 == 0:
			var state: Dictionary = rules.state()
			result.biggest = maxi(result.biggest, var_to_bytes(state).size())
			if str(state.phase) == "run" and not (state.answer as Array).is_empty(): result.leaked = true
			if not plain(state): result.plain = false
			result.states.append(state)
			result.last = state
	result.ticks = ticks
	result.results = rules.results()
	return result

## The scripted players this tick (FakeHost: no physics; walk() moves them, the early one is put straight on the right pad).
func drive(host, rules, plan: Array, pads: Array, started: float) -> void:
	var answer: Array = rules.answer_slots()
	if answer.is_empty(): return
	var count: int = host.count
	for slot in count:
		if not host.active(slot): continue
		var how := str(plan[slot])
		if how == "fast_odd": how = "fast" if rules.number % 2 == 1 else "slow"
		elif how == "fast_even": how = "fast" if rules.number % 2 == 0 else "slow"
		var target: Vector3 = (pads[int(answer[0])].at as Vector3) + Vector3.UP * Rules.START_LIFT
		if how == "early":
			if rules.phase == "ready": host.positions[slot] = target
			continue
		if rules.phase != "run" or how == "still": continue
		if how == "wrong": target = (pads[(int(answer[0]) + 1) % count].at as Vector3) + Vector3.UP * Rules.START_LIFT
		if rules.time - started < (SLOW_DELAY if how == "slow" else FAST_DELAY): continue
		host.walk(slot, target, (SLOW if how == "slow" else FAST) * DT)

func expect_game(label: String, game: Dictionary, scores: Array, headline: String, winners: Array) -> void:
	var results: Dictionary = game.results
	var rules = game.rules
	expect("%s: ten rounds, then the end" % label, rules.finished() and rules.number == Rules.ROUNDS, "round %d after %.1f s" % [rules.number, game.ticks * DT])
	var expected := Rules.INTRO + Rules.ROUNDS * (Rules.RUN + Rules.REVEAL) + (Rules.ROUNDS - 1) * Rules.READY
	expect("%s: about %.0f s long" % [label, expected], absf(game.ticks * DT - expected) < 0.2, "%.2f s" % (game.ticks * DT))
	expect("%s: scores" % label, results.scores == scores, "%s, expected %s" % [results.scores, scores])
	expect("%s: results headline" % label, str(results.headline) == headline, str(results.headline))
	expect("%s: results sub is the score line" % label, str(results.sub) == rules.score_line(scores) and str(results.sub) != "", str(results.sub))
	expect("%s: winners" % label, results.winners == winners, str(results.winners))
	expect("%s: state small and plain" % label, game.biggest < 8192 and game.plain, "largest %d B" % game.biggest)
	expect("%s: the answer stays hidden while the race runs" % label, not game.leaked)

func check_lines() -> void:
	var host = FakeHost.new(range(10), 5)
	var rules = Modes.new_rules(ID)
	rules.start(host)
	var phrases: Array = []
	for slot in 9: phrases.append(str(CAST.players[slot].catchphrase))
	var all_theirs: bool = rules.lines.all(func(line: Dictionary) -> bool: return phrases.has(str(line.text)) and not bool(line.ask))
	expect("lines: the round's catchphrases, a character without one has none", rules.lines.size() == 9 and all_theirs)
	var repeat := false
	for k in range(1, rules.order.size()): repeat = repeat or int(rules.order[k]) == int(rules.order[k - 1])
	expect("lines: ten rounds, never the same line twice in a row", rules.order.size() == Rules.ROUNDS and not repeat, str(rules.order))
	var four = Modes.new_rules(ID)
	four.start(FakeHost.new([0, 1, 2, 3], 5))
	expect("lines: only the round's characters' catchphrases", four.lines.size() == 4, str(four.lines.map(func(line: Dictionary) -> String: return str(line.text))))

## The ring for 1..10 players: pads apart, inside the walls, clear of the furniture and the floor word, the start ring clear of the pads.
func check_ring() -> void:
	var problems: Array = []
	for count in range(1, 11):
		var pads: Array = Rules.pads(count)
		if pads.size() != count: problems.append("%d: %d pads" % [count, pads.size()])
		for k in pads.size():
			var at: Vector3 = (pads[k].at as Vector3) - WalkInLobby.ORIGIN
			var out: Vector3 = pads[k].out
			var foot := at + out * (STATUE_REACH - 0.42)
			for other in range(k + 1, pads.size()):
				var gap := Vector2(at.x, at.z).distance_to(Vector2((pads[other].at as Vector3).x - WalkInLobby.ORIGIN.x, (pads[other].at as Vector3).z - WalkInLobby.ORIGIN.z))
				if gap < Rules.EXIT * 2.0 + 0.2: problems.append("%d: pads %d and %d %.2f m apart" % [count, k, other, gap])
			for spot in count:
				var start := Rules.start_point(spot, count) - WalkInLobby.ORIGIN
				if Vector2(start.x, start.z).distance_to(Vector2(at.x, at.z)) < Rules.EXIT + 0.4: problems.append("%d: start spot %d on pad %d" % [count, spot, k])
			for shape: Array in [[Vector2(at.x, at.z), PAD_PAINT], [Vector2(foot.x, foot.z), 0.42]]:
				var centre: Vector2 = shape[0]
				var radius: float = shape[1]
				var inside := WalkInLobby.interior_rect().grow(-0.4)
				if centre.x - radius < inside.position.x or centre.x + radius > inside.end.x or centre.y - radius < inside.position.y or centre.y + radius > inside.end.y:
					problems.append("%d: pad %d past the walls" % [count, k])
				for box: Array in BOXES:
					var nearest := Vector2(clampf(centre.x, box[0], box[2]), clampf(centre.y, box[1], box[3]))
					if nearest.distance_to(centre) < radius: problems.append("%d: pad %d on furniture %s" % [count, k, box])
				for circle: Array in CIRCLES:
					if centre.distance_to(Vector2(circle[0], circle[1])) < radius + float(circle[2]): problems.append("%d: pad %d on %s" % [count, k, circle])
	expect("ring: 1-10 pads apart, inside the walls, clear of the playground, the decor and the floor word", problems.is_empty(), str(problems.slice(0, 6)))
	var ten: Array = Rules.pads(10)
	var under := Rules.pad_under((ten[4].at as Vector3) + Vector3(0.0, 0.25, 0.0), ten)
	var edge := Rules.pad_under((ten[4].at as Vector3) + (ten[4].out as Vector3) * 1.3, ten, 4)
	var off := Rules.pad_under((ten[4].at as Vector3) + (ten[4].out as Vector3) * 1.3, ten)
	var high := Rules.pad_under((ten[4].at as Vector3) + Vector3(0.0, 3.0, 0.0), ten)
	expect("pad_under: on, kept on the edge, not entered from the edge, not from high above", under == 4 and edge == 4 and off == -1 and high == -1, "%d %d %d %d" % [under, edge, off, high])

## Only ints, floats, bools, strings, arrays and dictionaries.
func plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING: return true
		TYPE_ARRAY: return (value as Array).all(func(entry: Variant) -> bool: return plain(entry))
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not (key is String and plain(value[key])): return false
			return true
	return false

# ------------------------------------------------------------------ view

## The view under a stub shell with the real rigs and the mode HUD: every captured state, checking what the HUD says.
func present_game(game: Dictionary, seats: Array) -> void:
	var count := seats.size()
	var label := "view %d players" % count
	var stub = StubRun.new()
	root.add_child(stub)
	stub.make(count, true)
	var view: Node3D = ModeViews.new_view(ID)
	stub.world.add_child(view)
	view.setup(stub, seats, 0)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	var statues: int = view._pads.filter(func(pad: Dictionary) -> bool: return pad.rig != null).size()
	var solids := view.get_children().filter(func(node: Node) -> bool: return node is StaticBody3D).size()
	expect("%s: a pad, a solid statue and a name tag per character" % label, view._pads.size() == count and solids == count and (statues == count or not Rig.available()), "%d pads, %d rigs, %d solids" % [view._pads.size(), statues, solids])
	var empty: Dictionary = view.hud({})
	view.present({}, 0.1)
	expect("%s: no state yet: the title" % label, str(empty.get("title", "")) == "WHO SAID IT?")
	var wrong := PackedStringArray()
	var saw := {"big": false, "line": false, "reveal": false, "emote": false, "out": false}
	var kept := ""
	for index in (game.states as Array).size():
		var state: Dictionary = game.states[index]
		view.present(state, 0.1)
		var model: Dictionary = view.hud(state)
		hud.show_model(model)
		var phase := str(state.phase)
		var number := int(state.round)
		if str(model.title) != "WHO SAID IT?  ·  ROUND %d / %d" % [number, Rules.ROUNDS]: wrong.append("title %s" % model.title)
		if (model.scores as Array) != (state.scores as Array): wrong.append("scores")
		if not (model.out as Array).is_empty(): saw.out = true
		var key := "%d:%s" % [number, phase]
		var fresh := key != kept
		kept = key
		match phase:
			"ready":
				if str(model.big) != "GET READY": wrong.append("ready big %s" % model.big)
			"run":
				var shown := Rules.prompt(str(state.line), bool(state.ask))
				if str(model.big) == shown: saw.big = true
				elif str(model.line) == shown and str(model.big) == "": saw.line = true
				else: wrong.append("run %s / %s" % [model.big, model.line])
				if float(model.timer) < 0.0 or view._bubbles.size() != 1: wrong.append("run timer or bubble")
			"reveal":
				saw.reveal = true
				var answer: Array = state.answer
				if answer.is_empty() or str(model.big) != str(TeamCast.player(int(seats[int(answer[0])])).name): wrong.append("reveal big %s" % model.big)
				if view._bubbles.size() != answer.size(): wrong.append("reveal bubbles %d" % view._bubbles.size())
				if fresh and view._pads[int(answer[0])].rig != null:
					saw.emote = saw.emote or float(view._pads[int(answer[0])].moving) > 0.0
		if index % 20 == 0: await process_frame
	expect("%s: every state presented, the HUD as the phase says" % label, wrong.is_empty(), str(wrong.slice(0, 6)))
	expect("%s: a reveal lit a pad, its statue played its emote" % label, saw.reveal and (saw.emote or not Rig.available()))
	expect("%s: short lines go big, long ones on the line under it" % label, saw.big and (saw.line or count != 10), str(saw))
	if count == 4: expect("%s: the one who left is greyed on the board" % label, saw.out)
	expect("%s: HUD shows the model" % label, not hud.probe().is_empty())
	# A late joiner whose first state is a reveal.
	var late: Node3D = ModeViews.new_view(ID)
	stub.world.add_child(late)
	late.setup(stub, seats, 1)
	for state: Dictionary in game.states:
		if str(state.phase) == "reveal":
			late.present(state, 0.1)
			break
	expect("%s: joining in a reveal shows it" % label, late._bubbles.size() >= 1)
	await process_frame
	hud.queue_free()
	stub.queue_free()
	await process_frame
