extends SceneTree
## Headless check of picking a round in the lobby (docs/party-show.md "Pick a round") and of KEEP THE LOGO and the scoring of the show's rounds:
##   * the round list (modes/lineup/round_list.gd): one entry per round title of the show levels, races then the final then the survival rounds;
##   * the lobby circles (network/walk_in_lobby.gd): THE SHOW and one circle per round, all inside the yard, none overlapping another or the playground,
##     nobody spawns on one, a circle finds a courier standing on it, the board of a circle that needs more players says so in a show for one;
##   * a lobby circle of one round (`host.pick`) plays just that round: its kind and levels, one round, the victory banner and the podium room for its winner (none for a time out), `finished()` after them;
##   * the full show for 2 players scores 2 / 1 per round and the final like any round (no double points): 9 points in all;
##   * KEEP THE LOGO (`play: badge`): the logos go to `need` players, a grab takes one, a logo just taken cannot be taken back at once, the wearers go
##     through at the cap, a courier that leaves the floor goes back to the start with its logo.
## Run: FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s $PWD/tools/modes/round_pick_check.gd
## Prints ROUND_PICK ok=<bool> last; exits 1 on a failure.
const Modes := preload("res://modes/modes.gd")
const TeamCast := preload("res://style/team_cast.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const Lineup := preload("res://modes/lineup/lineup.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const CourseSection := preload("res://course_section.gd")
const Playground := preload("res://lobby/playground.gd")
const STAGE_RULE := "DON'T FALL  ·  BE ONE OF THE LAST STANDING" ## the rule line of the stage rounds' boards (level files 25-28)
const TILE_LEVEL := 14 ## 0-based: level_15.json, LAST TILE STANDING (`draw: false`)
var FakeHost: GDScript

var failures := 0

class LevelHost extends "res://modes/mode_host.gd":
	## A fake host with the level-facing queries answered by the script: positions, who holds whom, and the zone each slot is in.
	var positions: Array = []
	var holders: Array = []
	var zones: Array = []
	var sent: Array = []
	var respawns := 0
	var retired: Array = []
	func _init(round_seats: Array, seed_value := 1) -> void:
		super(null, round_seats, seed_value)
		for slot in count:
			positions.append(WalkInLobby.spawn(slot))
			holders.append(-1)
			zones.append("")
	func active(slot: int) -> bool: return slot >= 0 and slot < count
	func position(slot: int) -> Vector3: return positions[slot]
	func held_by(slot: int) -> int: return int(holders[slot])
	func send_to(slot: int, at: Vector3, _yaw := 0.0) -> void:
		positions[slot] = at
		holders[slot] = -1
		sent.append(slot)
	func begin_level(_level: int, out := []) -> void: retired = out.duplicate()
	func begin_podium(out: Array) -> void: retired = out.duplicate()
	func tile_start(_level: int, _players: int) -> PackedByteArray: return PackedByteArray()
	func tiles_under(_slot: int, _level: int) -> Array: return []
	func apply_tiles(_level: int, _steps: PackedByteArray) -> void: pass
	func zone(slot: int, _level: int) -> String: return str(zones[slot])
	func scorch(_slot: int, _level: int) -> String: return ""
	func checkpoint_at(_slot: int, _level: int) -> int: return -1
	func note_scorch(_slot: int, _kind: String) -> void: pass
	func respawn(slot: int, _level: int, _checkpoint: int) -> void:
		respawns += 1
		zones[slot] = ""
		send_to(slot, Vector3(0.0, 0.05, 0.0))
	func progress(slot: int, _level: int) -> float: return float(positions[slot].x)
	func route_length(_level: int) -> float: return 100.0
	func level_clock() -> float: return 0.0
	func retire(slot: int) -> void: if not retired.has(slot): retired.append(slot)
	func podium(_level: int) -> Array: return [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]
	func hold(_slot: int, _at: Vector3, _radius: float, _rise := INF) -> void: pass
	func strays(_slot: int) -> int: return 0
	func release_holds() -> void: pass

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("ROUND_PICK ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	create_timer(200.0).timeout.connect(func() -> void:
		print("ROUND_PICK FAIL timed out")
		print("ROUND_PICK ok=false")
		quit(1))
	_run.call_deferred()

func cast(players: int) -> void:
	var list := []
	for index in players: list.append({"name": "P%d" % (index + 1), "color": ["#ff5a36", "#2c4bff", "#2ec27e", "#f2c230", "#9a4dff", "#00b8d9"][index % 6]})
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "PICK"}, "players": list, "mode": "show"})

func _run() -> void:
	cast(6)
	check(Modes.current() == "show", "the cast plays the show")
	# ---- the round list
	var rounds: Array = RoundList.entries()
	var ids := {}
	var order := []
	for row: Dictionary in rounds:
		ids[str(row.id)] = true
		order.append(str(row.kind))
		for level: int in row.levels: check(CourseSection.show_levels(str(row.kind)).has(level) and CourseSection.level_title(level) == str(row.title), "%s: level %d is a %s level titled %s" % [row.id, level + 1, row.kind, row.title])
	var round_ids: Array = rounds.map(func(row: Dictionary) -> String: return str(row.id))
	check(round_ids == ["r29", "r30", "r31", "r32", "r25", "r26", "r27", "r28"], "the lobby lists the polished rounds only: the four races, then the four stage rounds (%s)" % str(round_ids))
	var race_ids: Array = rounds.filter(func(row: Dictionary) -> bool: return str(row.kind) == "race").map(func(row: Dictionary) -> String: return str(row.id))
	check(race_ids == ["r29", "r30", "r31", "r32"], "the races are r29 r30 r31 r32 (%s)" % str(race_ids))
	check(CourseSection.show_levels("race") == [13, 16, 18, 19, 22, 28, 29, 30, 31] and CourseSection.draw_levels("race") == CourseSection.show_levels("race"), "the other races are still show levels 14, 17, 19, 20, 23, 29, 30, 31, 32 (%s)" % str(CourseSection.draw_levels("race")))
	var hidden: Array = RoundList.entries(true).filter(func(row: Dictionary) -> bool: return not round_ids.has(str(row.id)))
	check(hidden.size() >= 10 and hidden.all(func(row: Dictionary) -> bool: return not RoundList.entry(str(row.id)).is_empty() and not WalkInLobby.pad(str(row.id)).has("pick")), "%d unpolished rounds are hidden from the lobby and still known to RoundList.entry (%s)" % [hidden.size(), str(hidden.map(func(row: Dictionary) -> String: return str(row.id)))])
	var playlist := Lineup.playlist()
	check(playlist.size() == 3 and str(playlist[0].rules) == "race" and str(playlist[1].rules) == "survival" and str(playlist[2].rules) == "final", "THE SHOW plays a race, a stage round and a finish (%s)" % str(playlist))
	var polished := [24, 25, 26, 27, 28, 29, 30, 31]
	var playlist_ok := true
	for index in playlist.size(): playlist_ok = playlist_ok and (Lineup.draw(index) as Array).all(func(level: int) -> bool: return polished.has(level)) and not Lineup.draw(index).is_empty()
	check(playlist_ok and Lineup.draw(0) == [28, 29, 30, 31] and Lineup.draw(1) == [24, 25, 26, 27] and Lineup.draw(2) == [28, 29, 30, 31], "THE SHOW draws only the polished rounds: race %s, stage %s, finish %s" % [str(Lineup.draw(0)), str(Lineup.draw(1)), str(Lineup.draw(2))])
	check(ids.size() == rounds.size(), "the round ids are unique")
	var kinds_ok := true
	var rank := {"race": 0, "final": 1, "survival": 2}
	for index in range(1, order.size()): kinds_ok = kinds_ok and int(rank[order[index]]) >= int(rank[order[index - 1]])
	check(kinds_ok, "races first, then the final, then the survival rounds (%s)" % str(order))
	var covered := 0
	for kind: String in ["race", "survival", "final"]: covered += CourseSection.show_levels(kind).size()
	var listed := 0
	for row: Dictionary in RoundList.entries(true): listed += (row.levels as Array).size()
	check(listed == covered, "every show level is in one round (%d of %d)" % [listed, covered])
	var polished_count := 0
	for row: Dictionary in rounds: polished_count += (row.levels as Array).size()
	check(polished_count == polished.size(), "the lobby's rounds hold the %d polished levels (%d)" % [polished.size(), polished_count])
	check(RoundList.entry("nope").is_empty() and RoundList.entry(RoundList.SHOW).is_empty(), "an unknown id and the whole show are no round")
	var logo_row: Dictionary = {}
	for row: Dictionary in RoundList.entries(true): # KEEP THE LOGO has no circle in the lobby; its rules are played (a pick, the dev flag)
		if CourseSection.level_play(int(row.levels[0])) == "badge": logo_row = row
	check(not logo_row.is_empty() and not bool(logo_row.solo) and not round_ids.has(str(logo_row.id)), "KEEP THE LOGO is a round that needs other players and is hidden from the lobby")
	var stage_rows: Array = []
	for row: Dictionary in rounds:
		if not CourseSection.level_stage(int(row.levels[0])).is_empty(): stage_rows.append(row)
	var stage_titles: Array = stage_rows.map(func(row: Dictionary) -> String: return str(row.title))
	check(stage_titles == ["SQUARE STACK A", "HEX STACK A", "SQUARE STACK B", "HEX STACK B"], "the four stage rounds are four circles, A and B of one shape apart (%s)" % str(stage_titles))
	check(stage_rows.all(func(row: Dictionary) -> bool: return str(row.kind) == "survival" and (row.levels as Array).size() == 1 and bool(row.solo) and str(row.rule) == STAGE_RULE), "each stage circle is one solo survival level with the rule line %s" % STAGE_RULE)
	var drawn := Lineup.draw(1)
	check(not drawn.has(TILE_LEVEL) and CourseSection.show_levels("survival").has(TILE_LEVEL) and stage_rows.all(func(row: Dictionary) -> bool: return drawn.has(int(row.levels[0]))), "THE SHOW draws the stage rounds and not LAST TILE STANDING (still a show level): %s" % str(drawn))
	var picked := {}
	for seed_value in range(1, 61):
		var draw_host := LevelHost.new([0, 1], seed_value)
		var draw_rules := ShowRules.new()
		draw_rules.start(draw_host)
		draw_rules._begin_round(1) # the survival round of that seed's show
		picked[int(draw_rules.level)] = true
	check(picked.keys().all(func(level: int) -> bool: return drawn.has(level)) and stage_rows.all(func(row: Dictionary) -> bool: return picked.has(int(row.levels[0]))), "60 shows draw their survival from the draw list only, the four stage rounds among them (%s)" % str(picked.keys()))
	var played_ok := true
	var played_label := ""
	for seed_value in range(1, 61):
		var show_host := LevelHost.new([0, 1, 2, 3], seed_value)
		var show_rules := ShowRules.new()
		show_rules.start(show_host)
		var levels: Array = [int(show_rules.level)]
		var kinds: Array = [str(show_rules.kind)]
		for index in range(1, 3):
			show_rules._begin_round(index)
			levels.append(int(show_rules.level))
			kinds.append(str(show_rules.kind))
		var distinct: bool = levels.size() == 3 and levels[0] != levels[2]
		played_ok = played_ok and distinct and kinds == ["race", "survival", "final"] and levels.all(func(level: int) -> bool: return polished.has(level)) and [28, 29, 30, 31].has(levels[0]) and [24, 25, 26, 27].has(levels[1]) and [28, 29, 30, 31].has(levels[2])
		if not played_ok and played_label == "": played_label = " seed %d: %s %s" % [seed_value, str(kinds), str(levels)]
	check(played_ok, "60 shows play a race, a stage round and a race as the finish (never the same level twice, no unpolished level)%s" % played_label)
	# ---- the lobby circles
	WalkInLobby.local_players = 2
	var pads: Array = WalkInLobby.shown_pads()
	check(pads.size() == 1 + rounds.size() and str(pads[0].course) == CourseSection.ADVENTURE and str(pads[0].pick) == RoundList.SHOW, "the lobby has THE SHOW and a circle per round (%d circles)" % pads.size())
	var room := WalkInLobby.interior_rect()
	var bad := ""
	for index in pads.size():
		var centre: Vector3 = pads[index].center
		var flat := Vector2(centre.x - WalkInLobby.ORIGIN.x, centre.z - WalkInLobby.ORIGIN.z)
		if not room.grow(-WalkInLobby.RING_RADIUS).has_point(flat): bad += " %s outside the yard;" % pads[index].title
		for other in index:
			var gap := Vector2(centre.x - pads[other].center.x, centre.z - pads[other].center.z).length()
			if gap < WalkInLobby.RING_RADIUS * 2.0: bad += " %s and %s overlap (%.2f m);" % [pads[index].title, pads[other].title, gap]
		for solid: Dictionary in Playground.SOLIDS:
			var at: Vector3 = (solid.p as Vector3) + WalkInLobby.ORIGIN
			var size: Vector3 = solid.s
			var reach := (size.x if solid.k == "cyl" else maxf(size.x, size.z)) * 0.5
			if Vector2(centre.x - at.x, centre.z - at.z).length() < WalkInLobby.RING_RADIUS + reach * 0.7 and at.y - size.y * 0.5 < 2.0: bad += " %s stands on %s;" % [pads[index].title, solid.name]
		if str(pads[index].title) == "" or str(pads[index].subtitle) == "": bad += " a circle without a title or a rule line;"
		if WalkInLobby.zone_at(centre + Vector3(0.0, 0.1, 0.0)) != str(pads[index].course): bad += " %s: the zone at its middle is %s;" % [pads[index].title, WalkInLobby.zone_at(centre)]
		if WalkInLobby.zone_at(centre + Vector3(WalkInLobby.EXIT_RADIUS + 0.9, 0.1, 0.0)) == str(pads[index].course): bad += " %s: the zone reaches 2.65 m out;" % pads[index].title
	check(bad == "", "every circle is inside the yard, clear of the other circles and the playground, and found by zone_at%s" % bad)
	var spawn_on := ""
	for slot in 10:
		var zone := WalkInLobby.zone_at(WalkInLobby.spawn(slot, 10))
		if zone != "": spawn_on += " seat %d on %s" % [slot, zone]
	check(spawn_on == "", "nobody spawns on a circle (10 seats)%s" % spawn_on)
	var logo_pad := WalkInLobby._round_pad(logo_row, Vector3.ZERO, WalkInLobby.FRONT_LIFT, WalkInLobby.BOARD_FRONT) # the circle a hidden round would have
	check(str(logo_pad.subtitle) == str(logo_row.rule), "with two players a circle of a round that needs others shows its rule (%s)" % str(logo_pad.subtitle))
	WalkInLobby.local_players = 1
	logo_pad = WalkInLobby._round_pad(logo_row, Vector3.ZERO, WalkInLobby.FRONT_LIFT, WalkInLobby.BOARD_FRONT)
	check(str(logo_pad.subtitle) == WalkInLobby.SOLO_NOTE, "in a show for one it says it needs 2+ players (%s)" % str(logo_pad.subtitle))
	WalkInLobby.local_players = 2
	var first: Vector3 = pads[1].center
	var share := WalkInLobby.shared_pick([WalkInLobby.zone_at(first + Vector3(0.3, 0.1, 0.0)), WalkInLobby.zone_at(first + Vector3(-0.3, 0.1, 0.4))])
	check(share != "", "two players on one round circle share it (%s)" % share)
	# ---- one round per circle
	for row: Dictionary in rounds:
		var host := LevelHost.new([0, 1, 2, 3, 4, 5], 5)
		host.pick = str(row.id)
		var rules := ShowRules.new()
		rules.start(host)
		var state: Dictionary = rules.state()
		check(bool(rules.single) and int(state.rounds) == 1 and str(state.kind) == str(row.kind) and (row.levels as Array).has(int(state.level)), "%s: the circle plays one %s round on level %d" % [row.id, state.kind, int(state.level) + 1])
	# one race round to its end: the victory banner, then the podium room for its winner
	var one := LevelHost.new([0, 1, 2, 3, 4, 5], 9)
	for row: Dictionary in rounds:
		if str(row.kind) == "race": one.pick = str(row.id)
	var race := ShowRules.new()
	race.start(one)
	for tick in 60 * 5: race.tick(1.0 / 60.0)
	check(str(race.state().phase) == "play", "a one-round show is in its play phase after the card")
	for slot in 6:
		one.zones[slot] = "goal"
		for tick in 3: race.tick(1.0 / 60.0)
	for tick in 60 * 2: race.tick(1.0 / 60.0)
	var banner: Dictionary = race.state()
	check(str(banner.phase) == "done" and bool(banner.victory) and (banner.top as Array).size() == 3 and int((banner.top as Array)[0]) == 0, "a one-round show with a winner shows the victory banner after the play (phase %s, top %s)" % [str(banner.phase), str(banner.top)])
	for tick in 60 * 14: race.tick(1.0 / 60.0)
	check(race.finished() and str(race.state().phase) == "podium" and (race.state().podium as Array).size() == 3, "a one-round show with a winner ends in the podium room after its banner (phase %s)" % str(race.state().phase))
	var result: Dictionary = race.results()
	check(str(result.headline).ends_with(" WINS") and (result.winners as Array).size() == 1 and int((result.winners as Array)[0]) == 0, "its result names the first across (%s | %s)" % [result.headline, result.sub])
	# ---- the show for two: no double points
	cast(2)
	var two := LevelHost.new([0, 1], 3)
	var show := ShowRules.new()
	show.start(two)
	var guard := 0
	while not show.finished() and guard < 60 * 60 * 20:
		guard += 1
		var st: Dictionary = show.state()
		if str(st.phase) == "play":
			if str(st.kind) == "survival" and str(st.play) != "badge" and float(st.t) > 6.0: two.zones[1] = "kill"
			elif str(st.kind) != "survival":
				two.zones[0] = "goal" if float(st.t) > 3.0 else ""
				two.zones[1] = "goal" if float(st.t) > 6.0 else ""
		else:
			two.zones = ["", ""]
		show.tick(1.0 / 60.0)
	var totals: Array = show.pts
	check(show.finished() and int(totals[0]) + int(totals[1]) == 9, "a show for two awards 2 + 1 points in each of the three rounds, the final included (%s)" % str(totals))
	check(int(totals[0]) >= 5, "the player who won the rounds leads (%s)" % str(totals))
	# ---- KEEP THE LOGO
	cast(4)
	var four := LevelHost.new([0, 1, 2, 3], 11)
	four.pick = str(logo_row.id)
	var rules := ShowRules.new()
	rules.start(four)
	var st := rules.state()
	check(str(st.play) == "badge" and (st.badge as Array).size() == int(st.need) and int(st.need) == 2, "four players: two logos are dealt (%s, need %d)" % [str(st.badge), int(st.need)])
	check(str(st.card) != "" and str(st.card).length() <= 48, "the card line fits a phone (%s)" % str(st.card))
	for tick in 60 * 5: rules.tick(1.0 / 60.0)
	st = rules.state()
	var wearers: Array = (st.badge as Array).duplicate()
	var bare: Array = [0, 1, 2, 3].filter(func(slot: int) -> bool: return not wearers.has(slot))
	check(str(st.phase) == "play" and wearers.size() == 2 and bare.size() == 2, "the round is on (%s wear a logo)" % str(wearers))
	var thief: int = bare[0]
	var victim: int = wearers[0]
	four.holders[victim] = thief
	for tick in 3: rules.tick(1.0 / 60.0)
	st = rules.state()
	check((st.badge as Array).has(thief) and not (st.badge as Array).has(victim) and (st.badge as Array).size() == 2, "a grab takes the logo (%s)" % str(st.badge))
	four.holders[victim] = -1
	for tick in 10: rules.tick(1.0 / 60.0)
	four.holders[thief] = victim
	for tick in 3: rules.tick(1.0 / 60.0)
	st = rules.state()
	check((st.badge as Array).has(thief) and not (st.badge as Array).has(victim), "a logo just taken cannot be taken back at once (%s)" % str(st.badge))
	four.holders[thief] = -1
	for tick in 60 * 2: rules.tick(1.0 / 60.0)
	four.holders[thief] = victim
	for tick in 3: rules.tick(1.0 / 60.0)
	st = rules.state()
	check((st.badge as Array).has(victim) and not (st.badge as Array).has(thief), "after 1.5 s it can be taken (%s)" % str(st.badge))
	four.holders[thief] = -1
	var wearing: Array = (st.badge as Array).duplicate()
	var fallen: int = wearing[0]
	four.zones[fallen] = "kill"
	for tick in 3: rules.tick(1.0 / 60.0)
	check(four.respawns == 1 and (rules.state().badge as Array).has(fallen) and (rules.state().status as Array)[fallen] == 0, "a courier that leaves the floor goes back to the start, logo and all, and is not out")
	var guard_ticks := 0
	while str(rules.state().phase) != "done" and guard_ticks < 60 * 50:
		rules.tick(1.0 / 60.0)
		guard_ticks += 1
	st = rules.state()
	var final_badge: Array = (st.badge as Array).duplicate()
	check(str(st.phase) == "done" and bool(st.victory), "the round ends at its cap (45 s) with the victory banner")
	for tick in 60 * 14: rules.tick(1.0 / 60.0)
	check(rules.finished() and str(rules.state().phase) == "podium", "and is over after the banner and the podium room")
	var through: Array = []
	var out: Array = []
	for slot in 4:
		if int((st.status as Array)[slot]) == 1: through.append(slot)
		if int((st.status as Array)[slot]) == 2: out.append(slot)
	check(through.size() == 2 and out.size() == 2 and through.all(func(slot: int) -> bool: return final_badge.has(slot)), "the two who wear a logo go through, the other two are out (%s / %s)" % [str(through), str(out)])
	# a show for two: one logo, the holder scores most
	cast(2)
	var pair := LevelHost.new([0, 1], 13)
	pair.pick = str(logo_row.id)
	var duel := ShowRules.new()
	duel.start(pair)
	var wearer: int = (duel.state().badge as Array)[0]
	check((duel.state().badge as Array).size() == 1 and bool(duel.state().points_mode), "two players: one logo, a points round")
	for tick in 60 * 60: duel.tick(1.0 / 60.0)
	check(int(duel.pts[wearer]) == 2 and int(duel.pts[1 - wearer]) == 1, "the one who wore the logo longest takes 2 points (%s)" % str(duel.pts))
	TeamCast.override({})
	print("ROUND_PICK ok=", failures == 0)
	quit(1 if failures > 0 else 0)
