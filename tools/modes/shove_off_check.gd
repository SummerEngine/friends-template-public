extends SceneTree
## Headless check of SHOVE-OFF (docs/modes/shove_off.md): plays whole games of the rules with scripted players through the fake
## host (tools/modes/fake_host.gd) and checks rounds, eliminations, round wins, the end and the results; then builds the view under a
## stub shell with real rigs and presents every state it saw with the mode HUD.
## The players stand where the script puts them; a stand-in for the couriers' physics drops a player who is over no tile (or over a
## dropped one) the way gravity would, so a shove is "put them past the edge" and a dropped tile takes its player down with it.
## Prints MODE_CHECK shove_off ok=<bool> last; exits 1 on a failure.
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const TeamCast := preload("res://style/team_cast.gd")
const LobbySpace := preload("res://lobby_space.gd")
const Rules := preload("res://modes/shove_off/rules.gd")
const ID := "shove_off"
const DT := 1.0 / 60.0
const GRAVITY := 17.0
const STAND := 0.3 ## m past a tile's edge the stand-in still stands on it
const NAMES := ["Maya", "Theo", "Ida", "Noor", "Sam", "Lea", "Omar", "Kim", "Ana", "Bo"]
const LABELS := ["FLAKY CI", "MONDAY STANDUP", "CHAT PINGS"]
## The helpers next to this script (tools/ is outside the project: loaded by file path).
var FakeHost: GDScript
var StubRun: GDScript

var failures := 0

func expect(label: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("MODE_CHECK %s %s %s %s" % [ID, "ok  " if ok else "FAIL", label, detail])

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: # a script error stops _run: never hang the guard
		print("MODE_CHECK %s FAIL timed out" % ID)
		print("MODE_CHECK %s ok=false" % ID)
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	FakeHost = load(here + "/fake_host.gd")
	StubRun = load(here + "/stub_run.gd")
	var players: Array = []
	for name: String in NAMES: players.append({"name": name})
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Shove"}, "mode": ID, "players": players,
		"obstacles": [{"label": LABELS[0]}, {"label": LABELS[1]}, {"label": LABELS[2], "color": "#3a5bd9"}]})
	expect("the cast's mode is shove_off, 2-10 players", Modes.current() == ID and Modes.min_players(ID) == 2 and int(Modes.info(ID).get("max", 0)) == 10)
	await _two_players()
	await _four_players()
	await _ten_players()
	_frozen()
	_tie_and_cap()
	TeamCast.override({})
	print("MODE_CHECK %s ok=%s" % [ID, failures == 0])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ games

## 2 players: a shove before SHOVE! is undone; round 1 THEO is shoved off, round 2 MAYA; round 3 the tiles decide; 2-1.
func _two_players() -> void:
	var back := {"sent": -1, "out": false}
	var game := play([0, 1], 11, func(host, rules, _tick: int) -> void:
		if rules.phase == "count" and rules.round_number == 1 and at(rules, 1.5):
			back.sent = host.sent.size()
			shove(host, 0)
		if rules.phase == "play" and rules.round_number == 1 and at(rules, 0.5):
			back.out = rules.out.has(0) or host.positions[0].y < Rules.top_y() - 0.01 or host.sent.size() <= int(back.sent)
		if rules.phase != "play": return
		if rules.round_number == 1 and at(rules, 3.0): shove(host, 1)
		if rules.round_number == 2 and at(rules, 3.0): shove(host, 0))
	var rules = game.rules
	var host = game.host
	expect("2p: shoved off during the count, sent back onto the floor", int(back.sent) >= 0 and not bool(back.out))
	expect("2p: the round winners are MAYA, THEO, then whoever the tiles left", game.winners.slice(0, 2) == [0, 1] and game.winners.size() == 3 and int(game.winners[2]) >= 0, str(game.winners))
	var last: int = game.winners[game.winners.size() - 1]
	expect("2p: the game ends 2-1", rules.finished() and rules.wins == ([2, 1] if last == 0 else [1, 2]), str(rules.wins))
	var outcome: Dictionary = rules.results()
	expect("2p: results headline and score line", outcome.headline == "%s WINS" % NAMES[last].to_upper() and outcome.sub == rules.score_line(rules.wins)
		and outcome.winners == [last] and outcome.scores == rules.wins, str(outcome))
	expect("2p: an out player goes to the watch row", _sent_to(host, 1, Rules.watch_spot(1, 2)))
	_floor_checks("2p", game)
	await present_all("2p", game)

## 4 players: round 1 the last two fall in the same tick (nobody wins); round 2 Noor leaves and Maya wins; round 3 an out player
## who climbs back is sent away again and Ida wins; round 4 Maya wins 2-0-1-0.
func _four_players() -> void:
	var climb := {"before": -1, "after": -1, "still_out": false}
	var game := play([0, 1, 2, 3], 5, func(host, rules, _tick: int) -> void:
		if rules.phase != "play": return
		var round_number: int = rules.round_number
		if round_number == 1 and at(rules, 2.0):
			shove(host, 1)
			shove(host, 2)
		if round_number == 1 and at(rules, 4.0):
			shove(host, 0)
			shove(host, 3)
		if round_number == 2 and at(rules, 1.0):
			host.actives[3] = false
			rules.drop(3)
		if round_number == 2 and at(rules, 2.0): shove(host, 1)
		if round_number == 2 and at(rules, 3.0): shove(host, 2)
		if round_number == 3 and at(rules, 2.0): shove(host, 0)
		if round_number == 3 and at(rules, 5.0):
			climb.before = count_sent(host, 0)
			host.positions[0] = Rules.center()
		if round_number == 3 and at(rules, 5.5):
			climb.after = count_sent(host, 0)
			climb.still_out = rules.out.has(0)
		if round_number == 3 and at(rules, 6.0): shove(host, 1)
		if round_number == 4 and at(rules, 2.0):
			shove(host, 1)
			shove(host, 2))
	var rules = game.rules
	expect("4p: rounds won by nobody, Maya, Ida, Maya", game.winners == [-1, 0, 2, 0], str(game.winners))
	expect("4p: an out player back on the floor is sent away and stays out", int(climb.after) == int(climb.before) + 1 and bool(climb.still_out), str(climb))
	expect("4p: the game ends 2-0-1-0, Noor gone", rules.finished() and rules.wins == [2, 0, 1, 0] and rules.gone == [3], str(rules.wins))
	var outcome: Dictionary = rules.results()
	expect("4p: results", outcome.headline == "MAYA WINS" and outcome.sub == "MAYA 2  ·  IDA 1  ·  THEO 0  ·  NOOR 0" and outcome.winners == [0], str(outcome))
	_floor_checks("4p", game)
	await present_all("4p", game)

## 10 players, nobody shoves: the tiles decide every round. Lea leaves in round 2.
func _ten_players() -> void:
	var game := play(range(10), 23, func(host, rules, _tick: int) -> void:
		if rules.phase == "count" and rules.round_number == 2 and at(rules, 0.5):
			host.actives[5] = false
			rules.drop(5))
	var rules = game.rules
	var total := 0
	for value: int in rules.wins: total += value
	expect("10p: the game ends", rules.finished(), "rounds=%d" % rules.round_number)
	expect("10p: one win at most per round", total <= rules.round_number and total == game.winners.filter(func(slot: int) -> bool: return slot >= 0).size(), str(rules.wins))
	expect("10p: the round winner was the last one standing", game.last_ok, str(game.winners))
	expect("10p: the one who left never wins again", not game.winners.slice(1).has(5) and rules.gone == [5])
	var outcome: Dictionary = rules.results()
	var top := 0
	for slot in 10: top = maxi(top, int(rules.wins[slot]) if slot != 5 else 0)
	var leaders: Array = range(10).filter(func(slot: int) -> bool: return slot != 5 and int(rules.wins[slot]) == top)
	var expected := "%s WINS" % NAMES[leaders[0]].to_upper() if top > 0 and leaders.size() == 1 else ("IT'S A TIE" if top > 0 else "NOBODY WINS")
	expect("10p: results follow the round wins", outcome.headline == expected and outcome.sub == rules.score_line(rules.wins), "%s / %s" % [outcome.headline, outcome.sub])
	expect("10p: decided by 2 round wins or the 5-round cap", top >= Rules.WINS_NEEDED or rules.round_number == Rules.MAX_ROUNDS)
	_floor_checks("10p", game)
	await present_all("10p", game)

## 3 players: Ida's courier stops moving (it never falls on its own), Maya and Theo wait on the middle tiles (the last to drop):
## the rules take Ida out once she hangs over no tile, before the other two fall.
func _frozen() -> void:
	var hang := {"seen": false, "first": -1}
	var game := play([0, 1, 2], 9, func(host, rules, _tick: int) -> void:
		if rules.phase == "play" and at(rules, 0.1):
			host.positions[0] = Rules.center()
			host.positions[1] = Rules.center() + Vector3(Rules.TILE * 0.5, 0.0, Rules.TILE * 0.5)
			host.positions[2] = Rules.tile_center(0) + Vector3(0.0, 0.25, 0.0) # a corner tile of the outer ring
		if rules.phase == "play" and rules.round_number == 1 and hang.first < 0 and not rules.out.is_empty():
			hang.first = rules.out[0]
			hang.seen = rules.out[0] == 2 and host.positions[2].y >= Rules.top_y(), [2])
	expect("frozen: a courier that stops moving is out once it hangs over no tile, first", bool(hang.seen), str(hang))
	expect("frozen: the game still ends", game.rules.finished(), "rounds=%d" % game.rules.round_number)

## 2 players, one round each, then three rounds where both fall in the same tick: the cap of 5 rounds ends it in a tie.
func _tie_and_cap() -> void:
	var game := play([0, 1], 3, func(host, rules, _tick: int) -> void:
		if rules.phase != "play" or not at(rules, 2.0): return
		if rules.round_number != 2: shove(host, 1)
		if rules.round_number != 1: shove(host, 0))
	var rules = game.rules
	var outcome: Dictionary = rules.results()
	expect("cap: five rounds, 1-1, a tie", rules.finished() and rules.round_number == 5 and rules.wins == [1, 1] and game.winners == [0, 1, -1, -1, -1], str(game.winners))
	expect("cap: results of a tie", outcome.headline == "IT'S A TIE" and outcome.winners == [0, 1] and outcome.sub == "MAYA 1  ·  THEO 1", str(outcome))

# ------------------------------------------------------------------ the scripted game

## Plays one game: `script` (host, rules, tick) runs before every tick; then the stand-in physics moves the players; then the
## rules tick. Returns {rules, host, states: [[state, positions]], winners (per round, -1 none), last_ok, shakes (round -> the tiles
## in the order they started to shake, with the second they did), marks (round -> its marked tiles)}.
func play(seats: Array, seed_value: int, script: Callable, frozen: Array = []) -> Dictionary:
	var host = FakeHost.new(seats, seed_value)
	var rules = Modes.new_rules(ID)
	rules.start(host)
	var speeds: Array = []
	speeds.resize(seats.size())
	speeds.fill(0.0)
	var sent_seen := 0
	var states: Array = []
	var winners: Array = []
	var shakes := {}
	var marks := {}
	var last_ok := true
	var biggest := 0
	var phase := ""
	for tick in 60 * 600:
		script.call(host, rules, tick)
		for k in range(sent_seen, host.sent.size()): speeds[int(host.sent[k][0])] = 0.0
		sent_seen = host.sent.size()
		_physics(host, rules, speeds, frozen)
		var standing: Array = range(seats.size()).filter(func(slot: int) -> bool: return host.actives[slot] and not rules.out.has(slot) and not rules.gone.has(slot))
		rules.tick(DT)
		var state: Dictionary = rules.state()
		if rules.phase == "play":
			if not shakes.has(rules.round_number):
				shakes[rules.round_number] = []
				marks[rules.round_number] = rules.marked.duplicate()
			var seen: Array = shakes[rules.round_number]
			for index in rules.tiles.size():
				if int(rules.tiles[index]) != Rules.UP and not seen.any(func(entry: Array) -> bool: return entry[0] == index): seen.append([index, rules.phase_time])
		if rules.phase == "card" and phase == "play" or (rules.phase == "card" and phase == "count"):
			winners.append(rules.winner)
			if rules.winner >= 0 and not (standing.has(rules.winner) and rules.out.size() + rules.gone.size() >= seats.size() - 1): last_ok = false
		phase = rules.phase
		if tick % 6 == 0 or rules.finished():
			biggest = maxi(biggest, var_to_bytes(state).size())
			states.append([state, host.positions.duplicate()])
		if rules.finished(): break
	expect("%dp seed %d: state under 8 KB" % [seats.size(), seed_value], biggest < 8192, "largest %d B" % biggest)
	return {"rules": rules, "host": host, "states": states, "winners": winners, "last_ok": last_ok, "shakes": shakes, "marks": marks}

## The couriers, roughly: on a standing tile a player stays on its top; anywhere else it falls to the yard floor.
func _physics(host, rules, speeds: Array, frozen: Array) -> void:
	var top := Rules.top_y()
	var ground: float = host.floor_y()
	for slot in host.count:
		if not host.actives[slot] or frozen.has(slot): continue
		var at: Vector3 = host.positions[slot]
		var on_tile := at.y >= top - 0.3 and _over_tile(rules.tiles, at)
		if on_tile and at.y <= top + 0.001:
			at.y = top
			speeds[slot] = 0.0
		else:
			speeds[slot] = float(speeds[slot]) - GRAVITY * DT
			at.y += float(speeds[slot]) * DT
			if on_tile and at.y <= top:
				at.y = top
				speeds[slot] = 0.0
			if at.y <= ground:
				at.y = ground
				speeds[slot] = 0.0
		host.positions[slot] = at

func _over_tile(tiles: Array, at: Vector3) -> bool:
	for index in tiles.size():
		if int(tiles[index]) == Rules.GONE: continue
		var middle := Rules.tile_center(index)
		if absf(at.x - middle.x) <= Rules.TILE * 0.5 + STAND and absf(at.z - middle.z) <= Rules.TILE * 0.5 + STAND: return true
	return false

## A shove: `slot` ends up past the east edge at its height (the stand-in physics drops it).
func shove(host, slot: int) -> void:
	var at: Vector3 = host.positions[slot]
	host.positions[slot] = Vector3(Rules.area().end.x + 1.0, at.y, at.z)

## True on the one tick the phase clock passes `seconds`.
func at(rules, seconds: float) -> bool:
	return absf(float(rules.phase_time) - seconds) < DT * 0.5

func count_sent(host, slot: int) -> int:
	return host.sent.filter(func(entry: Array) -> bool: return int(entry[0]) == slot).size()

func _sent_to(host, slot: int, spot: Vector3) -> bool:
	return host.sent.any(func(entry: Array) -> bool: return int(entry[0]) == slot and (entry[1] as Vector3).distance_to(spot) < 0.01 and absf(float(entry[2]) - PI) < 0.001)

## The floor of every round: the labelled tiles (five, in the outer ring) drop first and in order, the outer ring before the inner
## ones, the first one FIRST_DROP s after SHOVE!, the gaps get shorter.
func _floor_checks(label: String, game: Dictionary) -> void:
	var first_ok := true
	var rings_ok := true
	var faster_ok := true
	var marks_ok := true
	var longest := 0
	for round_number: int in game.shakes:
		var seen: Array = game.shakes[round_number]
		var marked: Array = game.marks[round_number]
		longest = maxi(longest, seen.size())
		if marked.size() != Rules.LABELS or not marked.all(func(index: int) -> bool: return Rules.ring(index) == 0): marks_ok = false
		if seen.is_empty(): continue
		if absf(float(seen[0][1]) - Rules.FIRST_DROP) > DT * 1.5: first_ok = false
		for k in seen.size():
			if k < Rules.LABELS and int(seen[k][0]) != int(marked[k]): marks_ok = false
			if k >= 1 and Rules.ring(int(seen[k][0])) < Rules.ring(int(seen[k - 1][0])): rings_ok = false
			if k >= 2 and float(seen[k][1]) - float(seen[k - 1][1]) > float(seen[k - 1][1]) - float(seen[k - 2][1]) + DT * 1.5: faster_ok = false
	expect("%s: five marked tiles in the outer ring drop first, in order" % label, marks_ok)
	expect("%s: the first tile shakes %.0f s after SHOVE!" % [label, Rules.FIRST_DROP], first_ok)
	expect("%s: outer ring first, then inward" % label, rings_ok, "most tiles in a round %d" % longest)
	expect("%s: the tiles fall faster and faster" % label, faster_ok)

# ------------------------------------------------------------------ the view and the HUD

## Builds the view under a stub shell (with rigs) and presents every state with the mode HUD.
func present_all(label: String, game: Dictionary) -> void:
	var host = game.host
	var seats: Array = host.seats
	var stub = StubRun.new()
	root.add_child(stub)
	stub.make(seats.size(), true)
	var view: Node3D = ModeViews.new_view(ID)
	stub.world.add_child(view)
	view.setup(stub, seats, 0)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	var bodies := view.find_children("Tile*", "StaticBody3D", false, false)
	expect("%s view: 36 tiles on the yard's floor layer" % label, bodies.size() == Rules.GRID * Rules.GRID
		and bodies.all(func(body: StaticBody3D) -> bool: return body.collision_layer == LobbySpace.LAYER))
	var top := (bodies[0] as Node3D).global_position.y + Rules.THICK * 0.5 if not bodies.is_empty() else 0.0
	expect("%s view: the tiles' top is the rules' top" % label, absf(top - Rules.top_y()) < 0.001, str(top))
	var collision_ok := true
	var hud_ok := true
	var words := 0
	var danced := false
	var lettered: Array = []
	for k in game.states.size():
		var entry: Array = game.states[k]
		var state: Dictionary = entry[0]
		var positions: Array = entry[1]
		for slot in mini(positions.size(), stub.actors.size()): (stub.actors[slot] as Node3D).global_position = positions[slot]
		view.present(state, 0.1)
		var model: Dictionary = view.hud(state)
		hud.show_model(model)
		if lettered.is_empty() and int(state.round) == 1: lettered = _lettering(view, state)
		var tiles: Array = state.tiles
		for index in tiles.size():
			var layer: int = (bodies[index] as StaticBody3D).collision_layer
			if (int(tiles[index]) == Rules.GONE) != (layer == 0): collision_ok = false
		if not _hud_ok(state, model): hud_ok = false
		words = maxi(words, view.find_children("HazardWord", "Label3D", false, false).size())
		var winner := int(state.winner)
		if state.phase == "card" and winner >= 0 and view.rig(winner) != null and view.rig(winner).emote_playing() != "": danced = true
		if k % 40 == 0: await process_frame
	expect("%s view: a dropped tile has no collision, the others do" % label, collision_ok)
	expect("%s view: the HUD says the round, 3 2 1, SHOVE!, who won the round" % label, hud_ok)
	expect("%s view: the cast's labels lie on the marked tiles, in order" % label, lettered == LABELS, str(lettered))
	expect("%s view: a fall shows the cast's fall word" % label, words > 0)
	expect("%s view: the round's winner dances" % label, danced or not stub.rigs.any(func(rig) -> bool: return rig != null))
	# A client that joins mid-round sees the floor as it is (no falls replayed), and a state with missing keys draws nothing wrong.
	var late: Node3D = ModeViews.new_view(ID)
	stub.world.add_child(late)
	late.setup(stub, seats, 1)
	var middle: Dictionary = {}
	for entry: Array in game.states:
		if (entry[0].tiles as Array).has(Rules.GONE):
			middle = entry[0]
			break
	late.present(middle, 0.1)
	var hidden := true
	var late_bodies := late.find_children("Tile*", "StaticBody3D", false, false)
	for index in (middle.get("tiles", []) as Array).size():
		var gone: bool = int(middle.tiles[index]) == Rules.GONE
		var look := (late_bodies[index] as Node).get_node("Look") as MeshInstance3D
		if gone and (look.visible or (late_bodies[index] as StaticBody3D).collision_layer != 0): hidden = false
	expect("%s view: a late joiner sees dropped tiles gone at once" % label, not middle.is_empty() and hidden)
	for partial: Dictionary in [{}, {"phase": "play"}, {"phase": "card", "round": 2, "winner": 7, "wins": [1]}, {"tiles": [2, 2], "out": [99]}]:
		late.present(partial, 0.1)
		hud.show_model(late.hud(partial))
	expect("%s view: states with missing keys present" % label, is_instance_valid(late) and str(late.hud({}).get("title", "")) == "SHOVE-OFF")
	await process_frame
	hud.queue_free()
	stub.queue_free()
	await process_frame

func _lettering(view: Node3D, state: Dictionary) -> Array:
	var texts: Array = []
	for index: int in state.marked:
		var tile := view.get_node_or_null("Tile%02d/Look/Lettering" % index) as Label3D
		if tile != null: texts.append(tile.text.replace("\n", " "))
	return texts

func _hud_ok(state: Dictionary, model: Dictionary) -> bool:
	var t := float(state.t)
	if str(model.title) != "SHOVE-OFF  ·  ROUND %d" % int(state.round): return false
	if model.scores != state.wins or not str(model.note).begins_with("Walk into players to shove them."): return false
	for slot: int in state.out + state.gone:
		if not (model.out as Array).has(slot): return false
	match str(state.phase):
		"count": return str(model.big) == str(clampi(ceili(Rules.COUNT - t), 1, 3))
		"play": return (str(model.big) == "SHOVE!") == (t < Rules.SHOVE_SHOW)
		"card":
			var winner := int(state.winner)
			return str(model.big) == ("%s WINS THE ROUND" % NAMES[winner].to_upper() if winner >= 0 else "NOBODY WINS THE ROUND")
		"over":
			return str(model.big).ends_with("WINS") or str(model.big) == "GAME OVER"
	return false
