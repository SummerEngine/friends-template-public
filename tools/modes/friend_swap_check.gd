extends SceneTree
## Headless check of FRIEND SWAP (docs/modes/friend_swap.md). It plays whole rounds of modes/friend_swap/rules.gd with 2, 4 and 10
## scripted players through tools/modes/fake_host.gd and checks: the swap is a derangement; a line counts once per press and
## LINE_GAP apart; every vote sends everybody to the ring and puts up one pad per player, clear of the yard's walls, furniture and
## playground; the scores follow the votes (the right pad +1, the player behind the character +1 per wrong pad, no pad nothing); a
## player who leaves votes no more and the character they played is skipped (also in the middle of its own vote); the end, the
## results headline and line. Then it presents every captured state in the view under tools/modes/stub_run.gd (with the character
## rigs) and the mode HUD: the swapped looks, the tags, the bubbles, the pads, the HUD words, and the real looks back when it goes.
## Prints MODE_CHECK friend_swap ok=<bool> last; exits 1 on a failure.
const Rules := preload("res://modes/friend_swap/rules.gd")
const View := preload("res://modes/friend_swap/view.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const Modes := preload("res://modes/modes.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Look := preload("res://character/look.gd")
const Playground := preload("res://lobby/playground.gd")
const LobbySpace := preload("res://lobby_space.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const WalkInLook := preload("res://style/walk_in_look.gd")
const ID := "friend_swap"
const DT := 1.0 / 60.0
const CAPTURE_TICKS := 10 ## a state for the view every 1/6 s
const RUN_SPEED := 5.0 ## m/s the scripted players walk
## The free play's scripted presses of every player, [from, to) host seconds the button is held: 1.0 says a line, 2.0 is too soon
## after it, 3.5 says one, the long hold from 10 says one.
const PRESSES := [[1.0, 1.1], [2.0, 2.1], [3.5, 3.6], [10.0, 20.0]]
const LINES_EACH := 3
## Eight members (seats 9 and 10 are "PLAYER n"), one without a catchphrase, one with an emote the catalog does not have.
const CAST := {"format": "team-cast-v2", "team": {"name": "Swap Test"}, "mode": "friend_swap", "players": [
	{"name": "Maya", "catchphrase": "Ship it!", "emote": "dance"}, {"name": "Theo", "catchphrase": "On my way!", "emote": "point"},
	{"name": "Ida"}, {"name": "Noor", "catchphrase": "Coffee first", "emote": "wave"}, {"name": "Sami", "catchphrase": "Quick one"},
	{"name": "Lena", "catchphrase": "Looks good to me"}, {"name": "Omar", "catchphrase": "Let's go"}, {"name": "Jo", "catchphrase": "Where is my mug?"}]}

var FakeHost: GDScript
var StubRun: GDScript
var failures := 0
var _cast_looks := {}

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
	TeamCast.override(CAST)
	expect("the cast picks the mode", Modes.current() == ID, Modes.current())
	check_layout()
	var two := play_round(2, 11)
	var four := play_round(4, 23, {30.0: 2})
	var ten := play_round(10, 37, {}, 3)
	for each: Array in [[two, true], [four, false], [ten, false]]: # a script error inside stops it before it says true
		var done: Variant = await present_round(each[0], each[1])
		expect("%s: the view and HUD ran through every state" % str(each[0].label), done == true)
	TeamCast.override({})
	print("MODE_CHECK ", ID, " ok=", failures == 0)
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ the yard

## Every count of pads at every turn the rules may draw: the pads and their name boards keep clear of the walls, the furniture and
## the playground, and neighbouring pads never touch.
func check_layout() -> void:
	var worst := INF
	var tight := INF
	var rim := Rules.PAD_RADIUS + WalkInLook.RIM
	for count in range(2, 11):
		for step in 180:
			var points: Array = []
			for k in count:
				var angle := TAU * step / 180.0 + TAU * k / count
				var middle := Vector2(sin(angle), cos(angle)) * Rules.PAD_RING
				points.append(middle)
				worst = minf(worst, clearance(middle, rim))
				var out := middle.normalized()
				var side := Vector2(out.y, -out.x)
				for across: float in [-0.5, -0.36, 0.0, 0.36, 0.5]: # the board's ends and its two posts
					worst = minf(worst, clearance(middle + out * (rim + View.BOARD_BACK) + side * across * View.BOARD.x, WalkInLook.POST_RADIUS))
			for k in count: tight = minf(tight, (points[k] as Vector2).distance_to(points[(k + 1) % count]) - 2.0 * rim)
	expect("every pad and its name board keep clear of the yard's walls, furniture and playground (2-10 pads, any turn)", worst > 0.05, "closest %.2f m" % worst)
	expect("neighbouring pads never touch", tight > 0.3, "closest gap %.2f m" % tight)

## Metres from `at` (yard-local x, z) to the nearest wall, furniture or playground part, less `reach`.
func clearance(at: Vector2, reach: float) -> float:
	var room := WalkInLobby.interior_rect()
	var best := minf(minf(at.x - room.position.x, room.end.x - at.x), minf(at.y - room.position.y, room.end.y - at.y))
	for row: Dictionary in Playground.SOLIDS:
		var p: Vector3 = row.p
		var s: Vector3 = row.s
		var middle := Vector2(p.x, p.z)
		if str(row.k) == "cyl": best = minf(best, at.distance_to(middle) - s.x * 0.5)
		elif row.has("r"): best = minf(best, at.distance_to(middle) - s.length() * 0.5) # a tilted part: its whole size round it
		else: best = minf(best, box_distance(at, middle, Vector2(s.x, s.z) * 0.5))
	for row: Dictionary in Playground.MOVERS: # a swing or a seesaw: everywhere it rocks to
		var pivot: Vector3 = row.pivot
		var sweep := 0.0
		for part: Dictionary in row.parts:
			var p: Vector3 = part.p
			var s: Vector3 = part.s
			sweep = maxf(sweep, Vector2(p.x, p.z).length() + absf(p.y) * sin(deg_to_rad(float(row.amp))) + Vector2(s.x, s.z).length() * 0.5)
		best = minf(best, at.distance_to(Vector2(pivot.x, pivot.z)) - sweep)
	for row: Dictionary in LobbySpace.PROPS:
		var base: Vector3 = row.base
		var size: Vector3 = row.size
		best = minf(best, at.distance_to(Vector2(base.x, base.z)) - Vector2(size.x, size.z).length() * 0.5)
	return best - reach

static func box_distance(at: Vector2, middle: Vector2, half: Vector2) -> float:
	var outside := (at - middle).abs() - half
	return Vector2(maxf(outside.x, 0.0), maxf(outside.y, 0.0)).length()

# ------------------------------------------------------------------ the rules

## One whole scripted round. `drop_at`: host second -> the slot that leaves then. `drop_actor_vote`: the vote number whose
## character's player leaves one second into it (0: nobody).
func play_round(count: int, seed_value: int, drop_at := {}, drop_actor_vote := 0) -> Dictionary:
	var label := "%d players" % count
	if not drop_at.is_empty(): label += ", one leaves in the free play"
	if drop_actor_vote > 0: label += ", one leaves in their own vote"
	var seats: Array = range(count)
	var host = FakeHost.new(seats, seed_value)
	var rules = Rules.new()
	rules.start(host)
	var perm: Array = rules.state().perm
	expect("%s: the swap is a derangement" % label, is_derangement(perm, count), str(perm))
	if count == 2: expect("%s: two players simply swap" % label, perm == [1, 0], str(perm))
	var expected: Array = []
	for slot in count: expected.append(0)
	var gone: Array = []
	var voted: Array = [] ## characters whose vote closed
	var skipped: Array = [] ## characters skipped: their player left first
	var captured: Array = []
	var target := -1
	var vote_started := 0.0
	var plan := {} ## slot -> the pad (its slot) it runs to, -1 stays
	var goal := {} ## slot -> where that pad is
	var pending := [0, 0] ## right and wrong voters of the vote on now
	var sends_seen := 0
	var phase := "play"
	var biggest := 0
	var lines_after_soon: Array = []
	var lines_after_play: Array = []
	var sends_ok := true
	var pads_ok := true
	var actors_ok := true
	var reveals_ok := true
	var scores_ok := true
	var abort_ok := true
	var actor_left := false
	var pads_detail := ""
	var limit := int((Rules.PLAY_SECONDS + count * (Rules.VOTE_SECONDS + Rules.REVEAL_SECONDS) + 2.0) / DT)
	var tick := 0
	while tick < limit and not rules.finished():
		var t: float = rules.time
		for at: float in drop_at:
			var slot: int = drop_at[at]
			if t >= at and not gone.has(slot):
				leave(host, rules, slot, gone)
				if not voted.has(int(perm[slot])): skipped.append(int(perm[slot]))
		var state: Dictionary = rules.state()
		var now := str(state.phase)
		if now == "vote" and (phase != "vote" or int(state.target) != target):
			# a new vote: the ring, the pads, then the scripted choices
			target = int(state.target)
			vote_started = t
			var actor := int(state.actor)
			actors_ok = actors_ok and actor == perm.find(target) and not gone.has(actor) and not voted.has(target) and not skipped.has(target)
			if lines_after_play.is_empty(): lines_after_play = (state.lines as Array).duplicate()
			var players: Array = seats.filter(func(slot: int) -> bool: return not gone.has(slot))
			var sent: Array = host.sent.slice(sends_seen)
			sends_seen = host.sent.size()
			var radius := Rules.START_RING + Rules.RING_PER_PLAYER * players.size()
			var sent_slots: Array = sent.map(func(entry: Array) -> int: return int(entry[0]))
			sent_slots.sort()
			sends_ok = sends_ok and sent_slots == players
			for entry: Array in sent:
				var at: Vector3 = entry[1]
				var flat := Vector2(at.x - host.yard_center().x, at.z - host.yard_center().z)
				sends_ok = sends_ok and absf(flat.length() - radius) < 0.01 and absf(at.y - host.floor_y() - Rules.FEET_LIFT) < 0.001
			var pads: Array = state.pads
			var pad_slots: Array = pads.map(func(pad: Array) -> int: return int(pad[0]))
			pad_slots.sort()
			var where := {}
			for pad: Array in pads:
				var flat := Vector2(float(pad[1]) - host.yard_center().x, float(pad[2]) - host.yard_center().z)
				where[int(pad[0])] = Vector3(float(pad[1]), host.floor_y(), float(pad[2]))
				var room := clearance(flat, Rules.PAD_RADIUS + WalkInLook.RIM)
				if absf(flat.length() - Rules.PAD_RING) > 0.01 or room <= 0.0:
					pads_ok = false
					pads_detail = "pad %s at %s, clearance %.2f" % [pad[0], flat, room]
			if pad_slots != players:
				pads_ok = false
				pads_detail = "pads %s for players %s" % [pad_slots, players]
			# the choices: two of every four voters the right pad, one a wrong pad, one stays; the character's player runs to a wrong pad
			plan = {}
			goal = {}
			pending = [0, 0]
			for slot: int in players:
				var pick := -1
				var other := -1
				for each: int in players:
					if each != actor and each != slot: other = each
				if slot == actor: pick = other
				else:
					match (slot + voted.size()) % 4:
						0, 1: pick = actor
						2: pick = other
				plan[slot] = pick
				if pick >= 0: goal[slot] = where[pick]
				if slot != actor and pick == actor: pending[0] += 1
				elif slot != actor and pick >= 0: pending[1] += 1
		if now == "reveal" and phase != "reveal":
			var actor := int(state.actor)
			reveals_ok = reveals_ok and int(state.right) == pending[0] and int(state.wrong) == pending[1] and bool((state.shown as Array)[actor]) and int((state.picks as Array)[actor]) == -2
			for slot: int in plan:
				if slot != actor and int(plan[slot]) == actor: expected[slot] += 1
			expected[actor] += pending[1]
			voted.append(target)
			scores_ok = scores_ok and rules.scores == expected
		phase = now
		# the scripted players
		for slot in count: host.actions[slot] = false
		if now == "play":
			for slot in count:
				for hold: Array in PRESSES:
					if t >= float(hold[0]) and t < float(hold[1]): host.actions[slot] = true
				host.walk(slot, host.yard_center() + Vector3(sin(t * 0.3 + slot) * 4.0, 0.0, cos(t * 0.37 + slot * 2.0) * 4.0), RUN_SPEED * DT)
		elif now == "vote":
			if drop_actor_vote > 0 and not actor_left and int(state.vote) == drop_actor_vote and t - vote_started >= 1.0:
				actor_left = true
				var actor := int(state.actor)
				leave(host, rules, actor, gone)
				skipped.append(target)
				var after: Dictionary = rules.state()
				abort_ok = str(after.phase) == "vote" and int(after.target) != target and int(after.closed) == voted.size()
			for slot: int in goal:
				if not gone.has(slot): host.walk(slot, goal[slot], RUN_SPEED * DT)
		if tick % CAPTURE_TICKS == 0:
			captured.append([state, host.positions.duplicate()])
			biggest = maxi(biggest, var_to_bytes(state).size())
		rules.tick(DT)
		tick += 1
		if t < 2.5 and rules.time >= 2.5: lines_after_soon = (rules.state().lines as Array).duplicate()
	captured.append([rules.state(), host.positions.duplicate()])
	var ones: Array = []
	var each: Array = []
	for slot in count:
		ones.append(1)
		each.append(LINES_EACH)
	expect("%s: a press says a line, a second one within %.0f s does not" % [label, Rules.LINE_GAP], lines_after_soon == ones, str(lines_after_soon))
	expect("%s: %d lines each after the free play (a long hold says one)" % [label, LINES_EACH], lines_after_play == each, str(lines_after_play))
	expect("%s: every vote sends everybody still there to the ring round the centre" % label, sends_ok)
	expect("%s: every vote puts up one pad per player on the pad ring, clear of the yard's furniture" % label, pads_ok, pads_detail)
	expect("%s: every vote asks about a new character whose player is still there" % label, actors_ok)
	expect("%s: every close counts the right and wrong pads and reveals the player" % label, reveals_ok)
	expect("%s: the scores follow the votes after every close" % label, scores_ok, "%s vs %s" % [rules.scores, expected])
	if drop_actor_vote > 0: expect("%s: the vote stops when its player leaves and the next starts" % label, actor_left and abort_ok)
	var all_done: Array = voted + skipped
	all_done.sort()
	expect("%s: every character is voted on once or skipped because its player left" % label, all_done == seats and voted.size() == int(rules.state().closed), "voted %s skipped %s" % [voted, skipped])
	expect("%s: the round ends after the last reveal" % label, rules.finished() and rules.time <= Rules.PLAY_SECONDS + voted.size() * (Rules.VOTE_SECONDS + Rules.REVEAL_SECONDS) + skipped.size() * Rules.VOTE_SECONDS + 0.1, "%.1f s" % rules.time)
	expect("%s: the state stays small" % label, biggest < 8192, "largest %d B" % biggest)
	var outcome: Dictionary = rules.results()
	var top := -1
	for slot in count:
		if not gone.has(slot): top = maxi(top, int(expected[slot]))
	var winners: Array = seats.filter(func(slot: int) -> bool: return not gone.has(slot) and int(expected[slot]) == top)
	var headline := str(outcome.headline)
	var named := winners.all(func(slot: int) -> bool: return headline.contains(name_of(slot)))
	var worded := headline == "%s WINS" % name_of(winners[0]) if winners.size() == 1 else (headline.ends_with(" WIN") and named if winners.size() <= 4 else headline == "A %d-WAY TIE" % winners.size())
	expect("%s: the results name the winners" % label, outcome.winners == winners and worded, "%s %s" % [headline, outcome.winners])
	expect("%s: the results line is the score line" % label, str(outcome.sub) == rules.score_line(expected) and outcome.scores == expected, str(outcome.sub))
	return {"label": label, "count": count, "seats": seats, "perm": perm, "captured": captured}

func leave(host, rules, slot: int, gone: Array) -> void:
	host.actives[slot] = false
	rules.drop(slot)
	gone.append(slot)

static func is_derangement(perm: Array, count: int) -> bool:
	if perm.size() != count: return false
	var sorted := perm.duplicate()
	sorted.sort()
	if sorted != range(count): return false
	for slot in count:
		if int(perm[slot]) == slot: return false
	return true

# ------------------------------------------------------------------ the view and the HUD

## Every captured state of a round in the view (slot 0 is this machine's player) and the mode HUD, with the character rigs.
func present_round(played: Dictionary, local: bool) -> bool:
	var count: int = played.count
	var seats: Array = played.seats
	var perm: Array = played.perm
	var label: String = str(played.label) + (", on one machine" if local else "")
	var stub = StubRun.new()
	root.add_child(stub)
	stub.make(count, true)
	if local: stub.network_role = "local"
	var originals := {}
	for slot in count:
		if stub.rigs[slot] == null: continue
		originals[slot] = stub.rigs[slot].get_look()
		stub.rigs[slot].idle_emotes = true # as game/game_run.gd has them
	if originals.is_empty(): print("MODE_CHECK ", ID, " note: no character model here, the look checks are skipped")
	var view: Node3D = ModeViews.new_view(ID)
	expect("%s: the view builds" % label, view != null)
	if view == null:
		stub.queue_free()
		return false
	view.name = "ModeView"
	stub.world.add_child(view)
	view.setup(stub, seats, 0)
	var hud = ModeHud.new()
	root.add_child(hud)
	hud.seats = seats
	expect("%s: the view hides the game's name tags" % label, bool(view.hide_name_tags))
	for partial: Dictionary in [{}, {"phase": "vote"}, {"phase": "reveal", "perm": [], "pads": [[0]], "lines": [3]}]:
		view.present(partial, 0.1)
		hud.show_model(view.hud(partial))
	expect("%s: a missing or partial state shows the title and nothing else" % label, str(hud.probe().get("title", "")) == View.TITLE and (view.probe().pads as Array).is_empty())
	var titles_ok := true
	var play_ok := true
	var votes_ok := true
	var reveals_ok := true
	var board_ok := true
	var looks_ok := true
	var tags_ok := true
	var shows_ok := true
	var bubbles_ok := true
	var said := 0
	var last_lines: Array = []
	var detail := ""
	for entry: Array in played.captured:
		var state: Dictionary = entry[0]
		var positions: Array = entry[1]
		for slot in count: (stub.actors[slot] as Node3D).global_position = positions[slot]
		view.present(state, CAPTURE_TICKS * DT)
		var model: Dictionary = view.hud(state)
		hud.show_model(model)
		var probe: Dictionary = view.probe()
		var phase := str(state.phase)
		var shown: Array = state.shown
		var gone: Array = state.gone
		titles_ok = titles_ok and str(model.title) == View.TITLE
		match phase:
			"play":
				if local: play_ok = play_ok and str(model.line).contains("%s, PLAY AS %s" % [name_of(0), name_of(perm[0])]) and str(model.line).contains("%s, PLAY AS %s" % [name_of(1), name_of(perm[1])])
				else: play_ok = play_ok and (str(model.big) == "YOU ARE " + name_of(perm[0]) or str(model.line) == "PLAY AS " + name_of(perm[0])) and float(model.timer) >= 0.0
			"vote":
				var ok: bool = str(model.big) == "WHO IS PLAYING %s?" % name_of(int(state.target)) and bool(probe.asked) and (probe.pads as Array).size() == (state.pads as Array).size()
				if not ok and detail == "": detail = "vote: %s %s" % [model.big, probe]
				votes_ok = votes_ok and ok
			"reveal":
				reveals_ok = reveals_ok and str(model.big) == "IT WAS %s!" % name_of(int(state.actor)) and bool(probe.asked)
		board_ok = board_ok and (model.scores as Array).is_empty() == (int(state.closed) == 0)
		for slot in count:
			var wears := slot if bool(shown[slot]) else int(perm[slot])
			shows_ok = shows_ok and int(probe.shows[slot]) == wears
			var tag := "" if gone.has(slot) or (slot == 0 and not local) else name_of(wears)
			tags_ok = tags_ok and str(probe.tags[slot]) == tag
			if originals.has(slot): looks_ok = looks_ok and stub.rigs[slot].get_look().equals(originals[slot] if wears == slot else cast_look(wears)) and stub.rigs[slot].idle_emotes == (wears == slot)
		var lines: Array = state.lines
		if last_lines.size() == lines.size():
			for slot in count:
				if int(lines[slot]) > int(last_lines[slot]):
					said += 1
					bubbles_ok = bubbles_ok and (probe.bubbles as Array).has(slot)
		last_lines = lines
	expect("%s: the HUD title is FRIEND SWAP throughout" % label, titles_ok)
	expect("%s: the free play says who you play" % label, play_ok)
	expect("%s: every vote asks WHO IS PLAYING <NAME>?, rings the character and shows its pads" % label, votes_ok, detail)
	expect("%s: every reveal names the player" % label, reveals_ok)
	expect("%s: the scoreboard shows from the first close on" % label, board_ok)
	expect("%s: every character shows the one it plays, its own once revealed" % label, shows_ok)
	expect("%s: the tags name the characters (online the own tag hides)" % label, tags_ok)
	expect("%s: every line pops a bubble over its character" % label, bubbles_ok and said > 0, "%d lines" % said)
	if not originals.is_empty(): expect("%s: the rigs wear the swapped looks (no idle emote of their own), their own once revealed" % label, looks_ok)
	view.queue_free()
	await process_frame
	var restored := true
	for slot: int in originals: restored = restored and stub.rigs[slot].get_look().equals(originals[slot]) and stub.rigs[slot].idle_emotes
	if not originals.is_empty(): expect("%s: the real looks are back when the view goes" % label, restored)
	hud.queue_free()
	stub.queue_free()
	await process_frame
	return true

func name_of(seat: int) -> String:
	return str(TeamCast.player(seat).name)

func cast_look(seat: int) -> CharacterLook:
	if not _cast_looks.has(seat): _cast_looks[seat] = Look.defaults_for_seat(seat)
	return _cast_looks[seat]
