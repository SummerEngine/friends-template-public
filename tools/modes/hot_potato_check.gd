extends SceneTree
## Headless check of HOT POTATO (docs/modes/hot_potato.md). Whole games with 2, 4 and 10 scripted players through FakeHost: they
## wander the yard, walk up to the potato, pick it up, carry it and throw it next to somebody else (the script moves the prop as the
## yard's prop simulation would). Every pop must zap the holder, or the nearest player still in when nobody holds it; every fuse
## stays in its range; a POP beat and "3, 2, 1" follow every pop; players without lives go out to the side; the last one wins and
## the results name the winner and the rest by place. The 4-player game also has a player who is out grab the potato (it drops
## back) and a holder leave (drop). Then every captured state is presented in the view under StubRun with rigs and the yard's drawn
## props, and the mode HUD shows its model. Prints MODE_CHECK hot_potato ok=<bool> last; exits 1 on a failure.
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const TeamCast := preload("res://style/team_cast.gd")
const PropSim := preload("res://players/prop_sim.gd")
const PropLook := preload("res://players/prop_look.gd")
const LobbySpace := preload("res://lobby_space.gd")
const Rules := preload("res://modes/hot_potato/rules.gd")
const ID := "hot_potato"
const TICK := 1.0 / 60.0
const MAX_SECONDS := 1200.0
const NAMES := ["Maya", "Theo", "Ida", "Noor", "Sami", "Lena", "Omar", "Kai", "Vera", "Jonas"]
## The helpers next to this script (tools/ is outside the project: loaded by file path).
var FakeHost: GDScript
var StubRun: GDScript

var failures := 0
var held_pops := 0 ## pops that zapped a holder, over all games
var loose_pops := 0 ## pops that zapped the nearest player, over all games

func expect(label: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("MODE_CHECK ", ID, " ", "ok  " if ok else "FAIL", " ", label, " ", detail)

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: # a script error stops _run: never hang the guard
		print("MODE_CHECK ", ID, " FAIL timed out")
		print("MODE_CHECK ", ID, " ok=false")
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	FakeHost = load(here + "/fake_host.gd")
	StubRun = load(here + "/stub_run.gd")
	var players: Array = []
	for name: String in NAMES: players.append({"name": name})
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Potato"}, "players": players, "mode": ID})
	expect("the cast picks the mode", Modes.current() == ID, Modes.current())
	var early = Modes.new_rules(ID)
	early.start(FakeHost.new([0, 1, 2], 5))
	var tied: Dictionary = early.results()
	expect("a round ended early: the players still in with the most lives win", str(tied.headline) == "MAYA, THEO & IDA WIN" and tied.winners == [0, 1, 2], str(tied.headline))
	for n: int in [2, 4, 10]:
		var game := play(n, 11 + n)
		await show(n, game)
	expect("pops zapped holders and loose ones", held_pops > 0 and loose_pops > 0, "held %d loose %d" % [held_pops, loose_pops])
	TeamCast.override({})
	print("MODE_CHECK ", ID, " ok=", failures == 0)
	quit(1 if failures > 0 else 0)

## One whole game of `n` scripted players; returns what the view part needs.
func play(n: int, seed_value: int) -> Dictionary:
	var label := "%dp:" % n
	var host = FakeHost.new(range(n), seed_value)
	var rules = Modes.new_rules(ID)
	rules.start(host)
	var props = host.props()
	var potato: int = rules.potato
	expect("%s a yard prop is the potato" % label, potato >= 0 and potato < props.count, str(potato))
	var script := RandomNumberGenerator.new()
	script.seed = seed_value * 31 + n
	var targets: Array = []
	for slot in n: targets.append(_wander(host, script))
	var hold_left := 0.0
	var seek_in := 2.0
	var states: Array = []
	var biggest := 0
	var mismatches := PackedStringArray()
	var zaps: Array = []
	for slot in n: zaps.append(0)
	var entries := {"pop": 0, "count": 0, "live": 0, "over": 0}
	var counts := {}
	var phase: String = rules.phase
	var out_grab := ""
	var dropped := -1
	var ticks := 0
	while not rules.finished() and ticks < int(MAX_SECONDS * 60.0):
		# The players still in wander; now and then one walks up to the potato.
		seek_in -= TICK
		var alive: Array = rules._alive()
		if seek_in <= 0.0 and not alive.is_empty():
			seek_in = script.randf_range(2.0, 5.0)
			targets[alive[script.randi() % alive.size()]] = props.positions[potato]
		for slot: int in alive:
			if _flat(host.positions[slot], targets[slot]) < 0.3: targets[slot] = _wander(host, script)
			host.walk(slot, targets[slot], 3.5 * TICK)
		# The potato: carried, thrown next to somebody else, picked up by whoever stands at it.
		if rules.phase == "live":
			var holder: int = props.held_by[potato]
			if holder >= 0:
				props.positions[potato] = PropSim.hold_point(host.positions[holder], Vector3.FORWARD)
				hold_left -= TICK
				var catchers: Array = alive.filter(func(slot: int) -> bool: return slot != holder)
				if hold_left <= 0.0 and not catchers.is_empty():
					var at: Vector3 = host.positions[catchers[script.randi() % catchers.size()]]
					var angle := script.randf() * TAU
					props.held_by[potato] = -1
					props.positions[potato] = Vector3(at.x + cos(angle) * 0.8, host.floor_y() + 0.25, at.z + sin(angle) * 0.8)
			else:
				var near: int = rules._nearest(props.positions[potato])
				if near >= 0 and _flat(host.positions[near], props.positions[potato]) < 1.5 and script.randf() < 0.03:
					props.held_by[potato] = near
					hold_left = script.randf_range(0.5, 3.0)
		# A player who went out (and is still here) grabs it (4 players, once): it goes back where it lay.
		var benched: Array = rules.out_order.filter(func(slot: int) -> bool: return host.active(slot))
		var grab_test: bool = n == 4 and out_grab == "" and rules.phase == "live" and not benched.is_empty() and rules.phase_time + 1.0 < rules.fuse
		var rest_before: Vector3 = rules.rest
		if grab_test:
			var outsider: int = benched[0]
			props.held_by[potato] = outsider
			props.positions[potato] = PropSim.hold_point(host.positions[outsider], Vector3.FORWARD)
			out_grab = str(outsider)
		# A holder leaves (4 players, after the second pop): out at once, the potato drops.
		if n == 4 and dropped < 0 and rules.pops >= 2 and rules.phase == "live" and rules.phase_time + 1.0 < rules.fuse and alive.size() >= 3 and not grab_test:
			dropped = alive[script.randi() % alive.size()]
			props.held_by[potato] = dropped
			host.actives[dropped] = false
			rules.drop(dropped)
			expect("%s a player who leaves is out at once and drops the potato" % label, int(rules.lives[dropped]) == 0 and rules.out_order.back() == dropped and props.held_by[potato] == -1,
				"slot %d lives %d holder %d" % [dropped, int(rules.lives[dropped]), props.held_by[potato]])
		var expected: int = rules.holder()
		var held := expected >= 0
		if not held: expected = rules._nearest(props.positions[potato])
		var pops_before: int = rules.pops
		rules.tick(TICK)
		ticks += 1
		if grab_test:
			expect("%s a player who is out cannot hold the potato" % label, props.held_by[potato] == -1 and props.positions[potato].is_equal_approx(rest_before),
				"holder %d at %s rest %s" % [props.held_by[potato], props.positions[potato], rest_before])
		if rules.pops > pops_before:
			if rules.zapped != expected: mismatches.append("pop %d zapped %d expected %d" % [rules.pops, rules.zapped, expected])
			if rules.zapped >= 0: zaps[rules.zapped] += 1
			if held: held_pops += 1
			else: loose_pops += 1
		if rules.phase != phase:
			phase = rules.phase
			entries[phase] = int(entries.get(phase, 0)) + 1
		if ticks % 6 == 0 or rules.finished():
			var state: Dictionary = rules.state()
			biggest = maxi(biggest, var_to_bytes(state).size())
			if rules.phase == "count": counts[int(state.count)] = true
			states.append(state)
	var seconds := ticks * TICK
	expect("%s the game ends" % label, rules.finished(), "after %.0f s, %d pops" % [seconds, rules.pops])
	var winner: int = rules.winner
	var others: Array = range(n).filter(func(slot: int) -> bool: return slot != winner)
	expect("%s one winner with lives, everybody else out" % label, winner >= 0 and int(rules.lives[winner]) > 0 and others.all(func(slot: int) -> bool: return int(rules.lives[slot]) == 0),
		"winner %d lives %s" % [winner, str(rules.lives)])
	var order: Array = rules.out_order
	var unique := {}
	for slot: int in order: unique[slot] = true
	expect("%s everybody else went out once" % label, order.size() == n - 1 and unique.size() == n - 1 and not unique.has(winner), str(order))
	expect("%s every pop zapped the holder, else the nearest player still in" % label, mismatches.is_empty(), "; ".join(mismatches))
	var lost := 0
	var lives_ok := true
	for slot in n:
		lost += int(zaps[slot])
		if slot != dropped and int(rules.lives[slot]) != Rules.LIVES - int(zaps[slot]): lives_ok = false
	expect("%s a pop costs one life" % label, lost == rules.pops and lives_ok, "pops %d lives lost %d" % [rules.pops, lost])
	var least := (n - 1) * Rules.LIVES - (Rules.LIVES if dropped >= 0 else 0)
	expect("%s pops it takes" % label, rules.pops >= least and rules.pops <= n * Rules.LIVES, "%d pops (least %d)" % [rules.pops, least])
	var fuses_ok: bool = rules.fuses.size() == rules.pops
	for index in rules.fuses.size():
		var top := maxf(Rules.MIN_FUSE, Rules.FUSE.y * pow(Rules.SHRINK, index))
		if float(rules.fuses[index]) < Rules.MIN_FUSE - 0.001 or float(rules.fuses[index]) > top + 0.001: fuses_ok = false
	expect("%s every fuse in range, shorter as it goes, never under %.0f s" % [label, Rules.MIN_FUSE], fuses_ok, str(rules.fuses.map(func(f: float) -> float: return snappedf(f, 0.1))))
	expect("%s a POP beat after every pop, then 3, 2, 1" % label, int(entries.pop) == rules.pops and int(entries.count) == rules.pops - 1 and counts.has(3) and counts.has(2) and counts.has(1),
		"%s counts %s" % [str(entries), str(counts.keys())])
	var sides := 0
	for sent: Array in host.sent:
		var at: Vector3 = sent[1]
		if absf(absf(at.x - host.yard_center().x) - Rules.OUT_X) < 0.01 and order.has(int(sent[0])): sides += 1
	expect("%s players who go out stand at the side" % label, sides == order.size() - (1 if dropped >= 0 else 0), "%d sent of %d out" % [sides, order.size()])
	expect("%s state stays small" % label, biggest < 8192, "largest %d B" % biggest)
	var outcome: Dictionary = rules.results()
	var places := PackedStringArray()
	for index in range(order.size() - 1, -1, -1): places.append("%s %s" % [Rules._ordinal(order.size() - index + 1), host.name(order[index])])
	expect("%s results headline" % label, str(outcome.headline) == "%s WINS" % host.name(winner) and outcome.winners == [winner], str(outcome.headline))
	expect("%s results sub: the rest by place, last out first" % label, str(outcome.sub) == "  ·  ".join(places), str(outcome.sub))
	expect("%s results scores are the lives" % label, outcome.scores == rules.lives, str(outcome.scores))
	if n == 4: expect("%s the out grab and the drop happened" % label, out_grab != "" and dropped >= 0, "grab %s drop %d" % [out_grab, dropped])
	print("MODE_CHECK ", ID, " ", label, " ", outcome.headline, " | ", outcome.sub, " | ", rules.pops, " pops in ", roundi(seconds), " s")
	return {"states": states, "winner": winner, "names": range(n).map(func(slot: int) -> String: return host.name(slot))}

## Every captured state in the view (StubRun with rigs, the yard's props drawn as the shell draws them) and the mode HUD.
func show(n: int, game: Dictionary) -> void:
	var label := "%dp view:" % n
	var states: Array = game.states
	var names: Array = game.names
	var stub = StubRun.new()
	root.add_child(stub)
	stub.make(n, true)
	var drawn := PropLook.new()
	drawn.name = "LooseProps"
	stub.world.add_child(drawn)
	drawn.build(PropSim.new(LobbySpace.loose_props()))
	var view: Node3D = ModeViews.new_view(ID)
	stub.world.add_child(view)
	view.setup(stub, range(n), 0)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = range(n)
	var look := view.get_node_or_null("Potato/Painting" if n <= 2 else "Potato/Balloon")
	var rigs: int = stub.rigs.filter(func(found: Variant) -> bool: return found != null).size()
	expect("%s the potato is the team's %s" % [label, "painting" if n <= 2 else "balloon"], look != null and look.get_child_count() > 0, "%d rigs" % rigs)
	var potato := int((states[0] as Dictionary).get("potato", -1))
	var prop: Node3D = drawn.get_child(potato) if potato >= 0 and potato < drawn.get_child_count() else null
	var timer_shown := false
	var titles_ok := true
	var seen := {}
	var details := PackedStringArray()
	for state: Dictionary in states:
		view.present(state, 0.1)
		var model: Dictionary = view.hud(state)
		hud.show_model(model)
		if float(model.get("timer", -1.0)) >= 0.0: timer_shown = true
		if str(model.get("title", "")) != "HOT POTATO": titles_ok = false
		var phase := str(state.phase)
		var line := str(model.get("line", ""))
		if phase == "pop" and not seen.has("pop") and int(state.zapped) >= 0:
			seen.pop = str(model.get("big", "")) == "POP!" and line.begins_with(str(names[int(state.zapped)]))
			details.append("pop: %s / %s" % [model.get("big", ""), line])
		if phase == "count" and not seen.has("count"):
			seen.count = str(model.get("big", "")) in ["1", "2", "3"]
			details.append("count: %s" % model.get("big", ""))
		if phase == "live" and int(state.holder) > 0 and not seen.has("holder"):
			seen.holder = line.ends_with("%s HAS IT" % names[int(state.holder)])
			details.append("live: %s" % line)
		if phase == "live" and int(state.holder) < 0 and not seen.has("loose"):
			seen.loose = line.contains("NOBODY HAS IT")
			details.append("loose: %s" % line)
		if phase == "over" and not seen.has("over"):
			seen.over = str(model.get("big", "")) == "%s WINS" % names[int(game.winner)]
			details.append("over: %s" % model.get("big", ""))
	expect("%s the HUD shows the title, never the fuse" % label, titles_ok and not timer_shown)
	expect("%s HUD: POP! and who, 3 2 1, who has it, the winner" % label, seen.size() == 5 and seen.values().all(func(ok: bool) -> bool: return ok), " | ".join(details))
	expect("%s the yard prop under the potato is hidden" % label, prop != null and not prop.visible)
	var words: int = stub.world.get_children().filter(func(child: Node) -> bool: return child is Label3D).size()
	expect("%s the zap word showed over the zapped" % label, words > 0, "%d words" % words)
	view.queue_free()
	await process_frame
	expect("%s the yard prop shows again after the round" % label, prop != null and prop.visible)
	hud.queue_free()
	stub.queue_free()
	await process_frame

## A random point in the open middle of the yard, on the floor.
func _wander(host, script: RandomNumberGenerator) -> Vector3:
	var centre: Vector3 = host.yard_center()
	return Vector3(centre.x + script.randf_range(-6.0, 6.0), host.floor_y() + 0.25, centre.z + script.randf_range(-7.0, 5.0))

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
