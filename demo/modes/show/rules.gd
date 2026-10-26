extends "res://modes/mode_rules.gd"
## THE SHOW rules (docs/party-show.md): three rounds of minigames and a crown. Every round is a level-phase round on a show level
## (levels with `"show": "<kind>"`, docs/level-format.md; `host.begin_level`): 1 RACE (the first across the goal qualify), 2 SURVIVAL
## (a floor of tiles that falls away for good: the last ones standing survive), 3 FINAL (the first to the crown wins). The rules decide
## from the players' positions alone: a kill volume sends a racer back to its last checkpoint, the goal volume qualifies it, the level's
## start gate (a blink hazard) holds everybody until the countdown is over.
## A tile stage round (level `stage` section) differs in one rule: a player is out when it lands on the GROUND floor under the last layer (STAGE_LAND), not when it falls through a hole to the next
## layer; a stage round the cap ends with too many standing ranks them by floor height. Spawn pads for fewer than 12 players are spread over the block (levels/stage_starts.gd).
##
## 4 or more players: elimination (RACE_SHARE of them qualify, about half of those survive, the final is between the survivors).
## 2 or 3 players: nobody is eliminated, every round awards placement points, the highest total wears the crown.
## One round only: a lobby circle of one round (`host.pick`, modes/lineup/round_list.gd) plays just that round (kind, level and rules as in the show); a round with a winner ends in the same victory banner and podium room, a round without one (a time out)
## ends at its result.
## Eliminated players stay where they are: their courier is retired (host.retire: hidden, not simulated, nothing collides with it or targets it) and their camera follows
## the leader (`lead`); a later round does not even bring it back (host.begin_level lists them as out). After the final the VICTORY banner, then the top three stand on the
## podium room's pedestals (style/podium_room.gd, far from every course) and the winner wears the crown; everybody else is retired for the podium phase.
##
## A round: "card" (the level starts, CARD s, the gate is shut; a tile stage round's card is STAGE_CARD s: the title, then 3, 2, 1), "play", "done" (who is through, a stage round's
## VICTORY first; the next round starts after it); "podium" after the final (state `victory` in its "done": VICTORY seconds of banner), then the results page. State (state()) is documented in docs/party-show.md.
const CourseSection := preload("res://course_section.gd")
const DevEnv := preload("res://dev_env.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const Lineup := preload("res://modes/lineup/lineup.gd")
const ShowItems := preload("res://modes/show/items/items.gd")
const PigeonRules := preload("res://modes/show/shared/pigeon/pigeon_rules.gd")
const ShowManager := preload("res://modes/show/shared/manager/manager_rules.gd")
const EventGate := preload("res://modes/show/shared/event_gate.gd")

const CARD := 4.0 ## s of the round's card and 3, 2, 1: the level's start gate is shut for the same time (blink "on": 4.0)
const STAGE_TITLE := 1.2 ## s of a stage round's title card (modes/show/plates.gd), then the digits 3, 2, 1 one second apart
const STAGE_COUNT := 3.0 ## s of the digits: a stage round's card is STAGE_TITLE + STAGE_COUNT, its play begins with GO
const STAGE_CARD := STAGE_TITLE + STAGE_COUNT
const STAGE_DONE := 2.3 ## s of the VICTORY banner a stage round shows at its end, before the usual DONE (the result wall) follows
const STAGE_DROP := 1.5 ## m under the top layer: a player who steps off the arena during a stage round's card goes back to its start
const STAGE_LAND := 0.3 ## m over the ground floor's top: a stage round's player whose feet are this low is on the ground (it landed there) and is out; falling a layer is nothing
const STAGE_HOLD := 0.25 ## m on x/z a player of a stage round may stray from its start spot during the card before the authority puts it back (an honest owner does not move at all; a pose that left is dropped, host.hold)
const STAGE_RISE := 0.2 ## m over or under its start height a stage round's player may be during the card (no jump: the first ticks of a jump lift 0.1 m each; a courier settles 5 cm onto its tile)
const DONE := 4.5 ## s the result of a round stays up
const PODIUM := 9.6 ## s of the podium room (the victory flow: three shots, the winners landing 3 - 2 - 1 at 1.7 / 2.6 / 3.5 s, the crown at 3.9, a glint at 5.0, a slow push in on the winner), then the results page
const VICTORY := 1.7 ## s the last round's "done" lasts when a podium follows: the VICTORY banner (1.45 s) and a short beat of plain gameplay, then the cut into the room
const PODIUM_YAW := PI ## the podium's players face +Z, towards the podium camera (modes/show/view.gd)
const PODIUM_DRIFT := 0.3 ## m on x/z a player may stray from its podium spot before the authority puts it back (a pose from a client that did not hold still)
const PODIUM_FALL := 1.0 ## m under its spot a player may sink before it is put back
const CAPS := {"race": 100.0, "survival": 60.0, "final": 90.0} ## s: a round ends at its cap
const RACE_SHARE := 0.65 ## of the players qualify from the race
const END_GRACE := 1.5 ## s after the deciding finish before the round is called
const WINDOW := 30.0 ## s the others get after the first finisher in points mode
const GRACE := 1.0 ## s after a send_to without a test (late poses from before the move)
const FALL_SHOW := 1.2 ## s a fallen survival player stays in sight (its fall shows) before its courier is retired
const PLAY_CAPS := {"badge": 45.0} ## s: a level's own `play` (KEEP THE LOGO) has its own cap
const BADGE_IMMUNE := 1.5 ## s a logo that was just taken cannot be taken away again (no grab-back ping-pong)
const POINTS_MAX := 3 ## up to this many players: points mode
const LEVEL_FLAG := "--show-level=" ## dev and tools only (DevEnv): play this level (its file number) in the round whose kind it serves

const PLAYING := 0
const SAFE := 1
const OUT := 2
const SPECTATOR := 3
const CHAMPION := 4

var phase := "card"
var single := false ## the show is ONE round, picked on a lobby circle (host.pick): its levels, no podium
var rounds := 3 ## rounds in this show (the lineup's playlist, 1 when `single`)
var play := "" ## the level's own way to play a survival round (`play` in its file): "" the floor decides, "badge" KEEP THE LOGO
var badge: Array = [] ## KEEP THE LOGO: the slots wearing a logo on their back
var round_index := 0 ## 0..rounds-1
var _played: Array = [] ## the levels this show has played
var kind := "race"
var level := -1
var phase_time := 0.0
var points_mode := false
var need := 1
var field: Array = [] ## slots playing this round
var status: Array = [] ## per slot, PLAYING .. CHAMPION
var pts: Array = [] ## per slot, the show's points
var across: Array = [] ## slots across the goal, in order (race, final)
var fell: Array = [] ## slots that fell, in order (survival)
var place: Array = [] ## this round's ranking so far, best first
var eliminated: Array = [] ## slots out of the show, in order (the worst of a round first)
var gone: Array = [] ## slots that left the game
var crown := -1
var standings: Array = [] ## the show's final order, best first (set at the podium)
var podium_spots: Array = [] ## world feet of 1st, 2nd, 3rd: the podium room's (style/podium_room.gd, host.podium), set at the podium
var _victory := false ## this round ends in the victory banner and the podium room (the show's final, a one-round show's winner)
var _start_hold: Dictionary = {} ## a stage round's card: slot -> {at (Vector3)}: where each player is kept until GO (its own start spot)
var _hold: Dictionary = {} ## the podium phase: slot -> {at (Vector3), yaw}: where each of the top three is kept
var lead := -1
var card_line := "" ## the card's qualify / scoring line (the goal line of the level is the view's: plates.gd)
var _entry: Dictionary = {} ## `single`: the round's entry of the round list
var _dt := 1.0 / 60.0
var _held_for: Array = [] ## per slot: seconds it wore a logo this round
var _immune_until: Array = [] ## per slot: phase time until its logo cannot be taken
var _held_before: Array = [] ## per slot: who held it a tick ago (the grab's rising edge)
var _done_at: Dictionary = {} ## slot -> phase time it crossed the goal or fell this round
var _progress: Array = [] ## per slot: metres along the route
var _checkpoint: Array = [] ## per slot: the last checkpoint it stood in this round, -1 for none
var _grace: Array = []
var _retire_at: Array = [] ## per slot: when a fallen survival player's courier is retired, -1 for not pending
var _benched: Array = [] ## slots the host has out of the round (retired, or listed as out when the round began)
var _deadline := 0.0 ## s into "play" when the round ends
var _end_at := -1.0 ## s into "play" when the deciding finish was called
var _first_finish := -1.0
var items: ShowItems ## the race's item boxes, items and events (modes/show/items/items.gd, docs/items.md): its state is `items` in this state, empty when the level has no boxes
var pigeons: PigeonRules ## GHOST PIGEON (EXPERIMENT, modes/show/pigeon/, docs/pigeon.md): the players who are out are birds that coo at and drop on the living; its state is `pigeon` in this state, absent when the experiment is off in this round
var manager: ShowManager ## EXPERIMENT, THE MANAGER (modes/show/manager/, docs/party-show.md): one player makes rules for the rest; its state is `manager` in this state while the round has one
var gate := EventGate.new() ## ONE interrupting event at a time, 15 s apart (modes/show/shared/event_gate.gd): the manager's rules, the eggplant, the clock's boost/soar and a pigeon's splat ask it; reset with every round
var tiles := PackedByteArray() ## step tiles (levels/step_tiles.gd): one byte per tile, 0 standing, else the level clock it was stood on in StepTiles.STEP_UNIT, PRE_GONE never there
var _ground_y := -INF ## a stage round: the height of the top of the ground floor under the last layer (level file `stage.ground.y`), -INF for every other round

func start(round_host) -> void:
	super(round_host)
	points_mode = host.count <= POINTS_MAX
	items = ShowItems.new(self)
	pigeons = PigeonRules.new()
	pigeons.setup(host)
	pigeons.gate = gate
	manager = ShowManager.new(self)
	var chosen: String = str(host.pick) if "pick" in host else ""
	_entry = RoundList.entry(chosen)
	single = not _entry.is_empty()
	rounds = 1 if single else Lineup.playlist().size()
	for slot in host.count:
		status.append(PLAYING)
		pts.append(0)
		_progress.append(0.0)
		_checkpoint.append(-1)
		_grace.append(0.0)
		_retire_at.append(-1.0)
		_held_for.append(0.0)
		_immune_until.append(0.0)
		_held_before.append(-1)
	_begin_round(0)

func tick(dt: float) -> void:
	super(dt)
	_dt = dt
	phase_time += dt
	gate.tick(dt)
	for slot in host.count: _grace[slot] = maxf(float(_grace[slot]) - dt, 0.0)
	match phase:
		"card":
			_hold_on_course()
			_hold_start()
			_measure()
			if phase_time >= _card_length():
				_release_start()
				_set_phase("play")
		"play":
			_measure()
			match kind:
				"survival": _tick_badge() if play == "badge" else _tick_survival()
				_:
					items.tick(dt)
					_tick_course()
			manager.tick(dt)
			_retire_pending()
		"done":
			items.finish() # nothing is on anybody once the round is called
			manager.finish() # no prompt and no rule once the round is called
			_retire_pending()
			_measure()
			if phase_time >= _done_length():
				if _victory: _begin_podium()
				elif not single and round_index < rounds - 1: _begin_round(round_index + 1)
		"podium":
			items.finish()
			manager.finish()
			_hold_podium()
	pigeons.tick(dt, phase == "play" or phase == "done") # a bird flies from the card on; its coo and drop count from GO to the end of the round's result

func finished() -> bool:
	if phase == "podium": return phase_time >= PODIUM
	return single and not _victory and phase == "done" and phase_time >= _done_length()

func state() -> Dictionary:
	var podium := []
	for spot: Vector3 in podium_spots: podium.append([snappedf(spot.x, 0.01), snappedf(spot.y, 0.01), snappedf(spot.z, 0.01)])
	var left := -1.0
	if phase == "play": left = maxf(_deadline - phase_time, 0.0)
	return {"phase": phase, "round": round_index + 1, "rounds": rounds, "play": play, "badge": badge.duplicate(), "kind": kind, "t": snappedf(phase_time, 0.01), "count": maxf(_card_length() - phase_time, 0.0) if phase == "card" else 0.0,
		"left": snappedf(left, 0.1) if left >= 0.0 else -1.0, "level": level, "n": host.count, "points_mode": points_mode, "need": need, "field": field.duplicate(),
		"status": status.duplicate(), "place": place.duplicate(), "pts": pts.duplicate(), "lead": lead, "crown": crown, "podium": podium, "top": _top(), "victory": phase == "done" and _victory, "card": card_line,
		"stage": _stage(), "fell": fell.duplicate(),
		}.merged({"items": items.state()} if items != null and items.enabled else {}).merged({"pigeon": pigeons.state()} if pigeons.enabled else {}).merged({"manager": manager.state()} if manager != null and manager.enabled and (phase == "card" or phase == "play") else {}).merged(StepTiles.pack_state(tiles) if _stage() else StepTiles.chunk_state(tiles)) # the steps in pieces: no byte field over 256 B (levels/step_tiles.gd; a stage round's thousands of tiles go as a bitmap and a short list)

## The slots best first: the show's standings with the champion first (the results page's ranks and its podium).
func _final_order(winner: int) -> Array:
	var order: Array = _standings()
	if winner >= 0:
		order.erase(winner)
		order.push_front(winner)
	return order

func results() -> Dictionary:
	if single: return _single_results()
	var winner := crown if crown >= 0 else _leader_by_points()
	var scores := pts.duplicate()
	if winner < 0: return {"headline": "NO CHAMPION", "sub": score_line(scores) if not scores.is_empty() else "", "scores": scores, "winners": [], "order": _final_order(-1)}
	return {"headline": "%s TAKES THE CROWN" % host.name(winner), "sub": score_line(scores), "scores": scores, "winners": [winner], "order": _final_order(winner)}

## A player left: out of the show; the round goes on without it.
func drop(slot: int) -> void:
	if slot < 0 or slot >= host.count or gone.has(slot): return
	gone.append(slot)
	items.drop(slot)
	pigeons.drop(slot)
	manager.drop(slot)

## The TANDEM experiment (modes/show/shared/tandem/tandem.gd, ticked by the match controller / the local flow): may `slot` fuse with somebody now? A racer on course in a race's play phase.
func tandem_ok(slot: int) -> bool:
	return phase == "play" and kind == "race" and field.has(slot) and not gone.has(slot) and host.active(slot) and not across.has(slot) and int(status[slot]) == PLAYING and float(_grace[slot]) <= 0.0

## A show for one player (a buddy may come to run with it).
func tandem_solo() -> bool:
	return host.count == 1

# ------------------------------------------------------------------ the rounds

func _begin_round(index: int) -> void:
	round_index = index
	kind = str(_entry.kind) if single else str(Lineup.playlist()[index].rules)
	var choices: Array = (_entry.levels as Array).duplicate() if single else Lineup.draw(index)
	level = _pick_level(choices, index)
	if level >= 0: _played.append(level)
	play = CourseSection.level_play(level) if level >= 0 else ""
	field = []
	var was_out: Array = _benched.duplicate() # retired in the last round: no longer active in the host, but they play on unless eliminated
	_benched.clear()
	for slot in host.count:
		if gone.has(slot) or not (host.active(slot) or was_out.has(slot)): continue
		if eliminated.has(slot): status[slot] = SPECTATOR
		else:
			status[slot] = PLAYING
			field.append(slot)
	across = []
	fell = []
	place = []
	badge = []
	_done_at = {}
	_end_at = -1.0
	_first_finish = -1.0
	_victory = false
	_deadline = float(PLAY_CAPS.get(play, CAPS[kind]))
	var level_cap := CourseSection.level_cap(level) if level >= 0 else 0.0
	if level_cap > 0.0: _deadline = level_cap # a long course has its own cap (level file: cap)
	var stage_cap := float(CourseSection.level_stage(level).get("cap", 0.0)) if level >= 0 else 0.0
	if stage_cap > 0.0: _deadline = stage_cap # a stage round has its own cap (level file: stage.cap)
	var ground: Dictionary = (CourseSection.level_stage(level).get("ground", {}) as Dictionary) if level >= 0 else {}
	_ground_y = float(ground.y) if not ground.is_empty() else -INF # a stage round's ground floor (level origins stand at height 0): landing on it is the elimination
	_plan_round()
	if play == "badge": _deal_badges()
	var watchers: Array = eliminated.filter(func(slot: int) -> bool: return not gone.has(slot))
	_benched = watchers.duplicate()
	host.begin_level(level, watchers)
	tiles = host.tile_start(level, field.size()) if level >= 0 else PackedByteArray()
	host.apply_tiles(level, tiles)
	for slot in host.count:
		_checkpoint[slot] = -1
		_retire_at[slot] = -1.0
		_grace[slot] = GRACE
	_update_lead()
	gate.reset()
	items.begin(level, kind, field.size())
	manager.begin(level, kind, field)
	_freeze_start()
	pigeons.begin_round(kind, level, watchers) # the players who are out of the show fly over this round as pigeons
	_set_phase("card")

## The round's level: drawn from the show's seeded rng (the same on every machine), or the one a tool asked for (any show level of the kind, also one the draw
## holds back with `draw: false`: LAST TILE STANDING stays reachable for the tools).
func _pick_level(choices: Array, index: int) -> int:
	if choices.is_empty(): return -1
	if not single: # a show does not play a level twice (the lineup's playlist may draw two rounds from the same kind of level)
		var fresh := choices.filter(func(candidate: int) -> bool: return not _played.has(candidate))
		if not fresh.is_empty(): choices = fresh
	if host.count == 1: # a show for one player never draws a level that needs other players
		var alone := choices.filter(func(candidate: int) -> bool: return CourseSection.level_solo(candidate))
		if not alone.is_empty(): choices = alone
	var forceable: Array = choices if single else CourseSection.show_levels(str(Lineup.playlist()[index].levels)).filter(func(candidate: int) -> bool: return not _played.has(candidate))
	for argument in DevEnv.user_args():
		if argument.begins_with(LEVEL_FLAG) and forceable.has(int(argument.trim_prefix(LEVEL_FLAG)) - 1): return int(argument.trim_prefix(LEVEL_FLAG)) - 1
	return int(choices[host.rng.randi_range(0, choices.size() - 1)])

## How many go through this round, and the qualify / scoring line the card shows under the level's own goal line (modes/show/plates.gd).
func _plan_round() -> void:
	var total := field.size()
	var q1 := maxi(3, roundi(host.count * RACE_SHARE))
	var q2 := maxi(2, ceili(q1 / 2.0))
	match kind:
		"race":
			need = total if points_mode else clampi(q1, 1, maxi(total - 1, 1))
			card_line = "EVERYBODY RACES  ·  PLACES SCORE POINTS" if points_mode else "FIRST %d ACROSS QUALIFY" % need
			if host.count == 1: card_line = "AS FAST AS YOU CAN"
		"survival":
			need = 1 if points_mode else clampi(q2, 1, maxi(total - 1, 1))
			card_line = "LAST ONE STANDING SCORES MOST" if points_mode else "LAST %d STANDING SURVIVE" % need
			if play == "badge": card_line = "THE LOGO HOLDER SCORES MOST" if points_mode else "%d LOGO%s  ·  HOLD ONE WHEN TIME RUNS OUT" % [need, "" if need == 1 else "S"]
			if host.count == 1: card_line = "STAY ON THE FLOOR AS LONG AS YOU CAN"
		_:
			need = 1
			card_line = "FIRST TO THE CROWN WINS"
			if host.count == 1: card_line = "AS FAST AS YOU CAN"

func _set_phase(next: String) -> void:
	phase = next
	phase_time = 0.0

## A tile stage round (a level with a `stage` section, docs/level-format.md "Stage rounds"): its own card, 3, 2, 1 and VICTORY (modes/show/stage_hud.gd).
func _stage() -> bool:
	return level >= 0 and not CourseSection.level_stage(level).is_empty()

## How long the round's card runs: a stage round's is the title and the three digits, every other round's is CARD (its start gate is shut for as long).
func _card_length() -> float:
	return STAGE_CARD if _stage() else CARD

## How long the result of a round stays up: a stage round shows VICTORY first; a round that ends in the podium room shows only the victory banner (the victory flow).
func _done_length() -> float:
	if _victory: return STAGE_DONE if _stage() else VICTORY # a stage round's own VICTORY plate (stage_hud.gd) is the banner
	return DONE + (STAGE_DONE if _stage() else 0.0)

## The round that just ended leads to the victory banner and the podium room: the show's last round, a one-round show's with a winner (not a time out).
func _ends_in_podium() -> bool:
	if single: return not (_single_results().winners as Array).is_empty()
	return round_index >= rounds - 1

## The slots on the podium, best first (at most three): the final order of the podium phase; in the round's "done" the order it will have.
func _top() -> Array:
	if phase != "podium" and not (phase == "done" and _victory): return []
	var order: Array = standings if phase == "podium" else _standings()
	var result: Array = []
	for slot: int in order:
		if result.size() < 3 and not gone.has(slot) and (phase != "podium" or _hold.has(slot)): result.append(slot)
	return result

## Between the shut gate and the countdown's end a player who fell (a kill volume) goes back to the start; on a stage round, which has no gate, so does one who
## stepped off the top layer (the tiles are not stepped before play, nobody may start a layer lower).
func _hold_on_course() -> void:
	var stage := _stage()
	for slot: int in field:
		if float(_grace[slot]) > 0.0 or host.held_by(slot) >= 0: continue
		if host.zone(slot, level) == "kill" or (stage and host.position(slot).y < -STAGE_DROP): _respawn(slot)

## A tile stage round has no gate, so the authority holds every player on its own start tiles from the spawn until GO (the card): the host drops any owner pose that leaves the spot (no walk, no jump,
## no dash can move anybody, whatever its client does; `host.hold`) and the rules put the player that tried back at its start. The honest clients freeze their own couriers (game_run.gd `hold_start`,
## set by modes/show/view.gd) and only the camera still turns. GO (the play phase) releases everybody. Every other round keeps its start gate shut for the card.
func _freeze_start() -> void:
	_start_hold.clear()
	if not _stage(): return
	for slot: int in field:
		if not host.active(slot): continue
		var at: Vector3 = host.position(slot) # a new epoch has just put every courier on its start spot
		_start_hold[slot] = {"at": at}
		host.hold(slot, at, STAGE_HOLD, STAGE_RISE)

func _hold_start() -> void:
	for slot: int in _start_hold:
		if gone.has(slot) or not host.active(slot): continue
		var at: Vector3 = (_start_hold[slot] as Dictionary).at
		var here: Vector3 = host.position(slot)
		var strayed: int = host.strays(slot)
		if strayed > 0 or Vector2(here.x - at.x, here.z - at.z).length() > STAGE_HOLD or absf(here.y - at.y) > STAGE_RISE or host.held_by(slot) >= 0:
			host.respawn(slot, level, -1)

func _release_start() -> void:
	if _start_hold.is_empty(): return
	_start_hold.clear()
	host.release_holds()

## Where everybody got (race and final: for the order of those who did not finish; survival: unused) and who the spectators follow.
func _measure() -> void:
	for slot: int in field:
		if host.active(slot) and kind != "survival": _progress[slot] = host.progress(slot, level)
	_update_lead()
	place = _ranking()

func _update_lead() -> void:
	lead = -1
	var best := -INF
	for slot: int in field:
		if gone.has(slot) or not host.active(slot) or status[slot] == OUT: continue
		var value: float = (float(_progress[slot]) + (1000.0 if across.has(slot) else 0.0)) if kind != "survival" else (0.0 if fell.has(slot) else 1.0)
		if value > best:
			best = value
			lead = slot
	if lead < 0 and crown >= 0: lead = crown

# ------------------------------------------------------------------ race and final

func _tick_course() -> void:
	for slot: int in field:
		if gone.has(slot) or not host.active(slot) or across.has(slot): continue
		if float(_grace[slot]) > 0.0 or host.held_by(slot) >= 0: continue
		var cp: int = host.checkpoint_at(slot, level)
		if cp > int(_checkpoint[slot]): _checkpoint[slot] = cp
		var scorch: String = host.scorch(slot, level)
		if scorch != "":
			host.note_scorch(slot, scorch)
			_respawn(slot)
			continue
		match host.zone(slot, level):
			"kill": _respawn(slot)
			"goal": _cross(slot)
	if _end_at < 0.0:
		var active_field: Array = field.filter(func(slot: int) -> bool: return not gone.has(slot) and (host.active(slot) or across.has(slot))) # a finisher who became a pigeon (its courier retired) still counts as in the race
		var done := across.size() >= mini(need, active_field.size())
		if kind == "race" and points_mode: done = across.size() >= active_field.size()
		if done or active_field.is_empty(): _end_at = phase_time + END_GRACE
	if _end_at >= 0.0 and phase_time >= _end_at or phase_time >= _deadline: _end_round()

func _cross(slot: int) -> void:
	across.append(slot)
	items.drop(slot)
	_done_at[slot] = phase_time
	if _first_finish < 0.0:
		_first_finish = phase_time
		if kind == "race" and points_mode: _deadline = minf(_deadline, phase_time + WINDOW)
	var through := across.size() <= need
	if kind == "race": status[slot] = SAFE if through or points_mode else OUT
	elif kind == "final": status[slot] = CHAMPION if across.size() == 1 and not points_mode else SAFE
	if kind == "race" and pigeons.enabled: _retire_at[slot] = time + FALL_SHOW # GHOST PIGEON: the finisher's character stays in sight a moment, then it is a bird (_retire)

func _respawn(slot: int) -> void:
	host.respawn(slot, level, int(_checkpoint[slot]))
	_grace[slot] = GRACE

# ------------------------------------------------------------------ survival

func _tick_survival() -> void:
	_step_tiles()
	var falling: Array = []
	for slot: int in field:
		if gone.has(slot) or not host.active(slot) or fell.has(slot) or float(_grace[slot]) > 0.0: continue
		if host.held_by(slot) >= 0: continue
		if host.zone(slot, level) == "kill" or host.scorch(slot, level) != "" or host.position(slot).y <= _ground_y + STAGE_LAND: falling.append(slot)
	for slot: int in falling:
		fell.append(slot)
		_done_at[slot] = phase_time
		status[slot] = OUT
		_retire_at[slot] = time + FALL_SHOW
	var alive := _alive()
	# Alone there is nobody to outlast: the round ends when the player falls or at the cap.
	if _end_at < 0.0 and ((alive.size() <= need and host.count > 1) or alive.is_empty()): _end_at = phase_time + END_GRACE
	if _end_at >= 0.0 and phase_time >= _end_at or phase_time >= _deadline: _end_round()

## Step tiles: whoever is standing on a tile that nobody has stood on yet starts it: the tile goes at the level clock of now (rounded up to
## StepTiles.STEP_UNIT) plus its kind's delay, for every machine (the bytes ride in the state; the colliders and the look follow them).
func _step_tiles() -> void:
	if tiles.is_empty(): return
	var stamp: int = host.tile_stamp(level)
	var changed := false
	for slot: int in _alive():
		if host.held_by(slot) >= 0: continue
		for index: int in host.tiles_under(slot, level):
			if tiles[index] != 0: continue
			tiles[index] = stamp
			changed = true
	for index in tiles.size(): # a wrapped level's bytes are a clock modulo a window: a tile that has fallen is settled for good before its stamp comes round again
		var step := int(tiles[index])
		if step != 0 and step != StepTiles.SETTLED and step != StepTiles.PRE_GONE and host.tile_settled(level, index):
			tiles[index] = StepTiles.SETTLED
			changed = true
	if changed: host.apply_tiles(level, tiles)

func _alive() -> Array:
	return field.filter(func(slot: int) -> bool: return not gone.has(slot) and host.active(slot) and not fell.has(slot))

## Fallen survival players are retired once their fall has shown: they stay where they fell and watch (a pigeon, when the experiment is on); so do the racers who crossed the goal when it is.
func _retire_pending() -> void:
	for slot: int in fell + across:
		if float(_retire_at[slot]) < 0.0 or time < float(_retire_at[slot]): continue
		_retire_at[slot] = -1.0
		_retire(slot)

func _retire(slot: int) -> void:
	if _benched.has(slot): return
	_benched.append(slot)
	host.retire(slot)
	pigeons.spawn(slot, host.position(slot)) # GHOST PIGEON: a bird from the spot the courier stood on

# ------------------------------------------------------------------ KEEP THE LOGO (a survival level with `"play": "badge"`)

## `need` players start with a logo on their back (one fewer than the players, at least one); GRAB somebody wearing one and it is yours. When the time is up the
## logo wearers go through (points show: the one who wore a logo longest scores most). Nobody is out until then: a courier that leaves the floor goes back to
## the start ring, logo and all.
func _deal_badges() -> void:
	var pool: Array = field.duplicate()
	for index in range(pool.size() - 1, 0, -1):
		var other: int = host.rng.randi_range(0, index)
		var swap: int = pool[index]
		pool[index] = pool[other]
		pool[other] = swap
	badge = pool.slice(0, clampi(need, 1, maxi(pool.size() - 1, 1)))
	for slot in host.count:
		_held_for[slot] = 0.0
		_immune_until[slot] = 0.0
		_held_before[slot] = -1

func _tick_badge() -> void:
	for slot: int in field:
		if gone.has(slot) or not host.active(slot): continue
		var holder: int = host.held_by(slot)
		var before: int = int(_held_before[slot])
		_held_before[slot] = holder
		if holder >= 0 and before < 0 and holder != slot: _take_badge(holder, slot)
		if float(_grace[slot]) > 0.0 or holder >= 0: continue
		if host.zone(slot, level) == "kill" or host.scorch(slot, level) != "":
			host.respawn(slot, level, -1)
			_grace[slot] = GRACE
	for slot: int in badge: _held_for[slot] = float(_held_for[slot]) + _dt
	if phase_time >= _deadline: _end_round()

## `thief` grabbed `victim`: a logo changes hands unless the thief already wears one or the victim just took its own.
func _take_badge(thief: int, victim: int) -> void:
	if not badge.has(victim) or badge.has(thief) or phase_time < float(_immune_until[victim]): return
	badge.erase(victim)
	badge.append(thief)
	_immune_until[thief] = phase_time + BADGE_IMMUNE

# ------------------------------------------------------------------ results of a round

## This round's ranking, best first: race and final by the finish order and then how far they got; survival by who is still up and
## then who fell last.
func _ranking() -> Array:
	var order: Array = field.filter(func(slot: int) -> bool: return not gone.has(slot))
	if play == "badge":
		var by_time := func(a: int, b: int) -> bool: return float(_held_for[a]) > float(_held_for[b]) or (float(_held_for[a]) == float(_held_for[b]) and a < b)
		var wearing := order.filter(func(slot: int) -> bool: return badge.has(slot))
		var bare := order.filter(func(slot: int) -> bool: return not badge.has(slot))
		wearing.sort_custom(by_time)
		bare.sort_custom(by_time)
		return wearing + bare
	if kind == "survival":
		var alive := order.filter(func(slot: int) -> bool: return not fell.has(slot))
		if _ground_y > -INF: # a stage round the cap ended with more players standing than `need`: the higher floor stands better (it has fallen less far), then the lower slot
			alive.sort_custom(func(a: int, b: int) -> bool:
				var up_a: float = snappedf(host.position(a).y, 0.5)
				var up_b: float = snappedf(host.position(b).y, 0.5)
				return up_a > up_b or (up_a == up_b and a < b))
		var down := order.filter(func(slot: int) -> bool: return fell.has(slot))
		down.sort_custom(func(a: int, b: int) -> bool: return fell.find(a) > fell.find(b))
		return alive + down
	var crossed := across.filter(func(slot: int) -> bool: return order.has(slot)) # already in the order they crossed
	var running := order.filter(func(slot: int) -> bool: return not across.has(slot))
	running.sort_custom(func(a: int, b: int) -> bool: return float(_progress[a]) > float(_progress[b]) or (float(_progress[a]) == float(_progress[b]) and a < b))
	return crossed + running

func _end_round() -> void:
	if phase != "play": return
	place = _ranking()
	for rank in place.size(): pts[place[rank]] = int(pts[place[rank]]) + (place.size() - rank)
	if host.count == 1 and not place.is_empty() and status[place[0]] == OUT: status[place[0]] = SAFE # alone nobody is out: the fall showed, the face wall shows the placing
	if not points_mode and kind != "final":
		var through: Array = place.slice(0, need)
		var dropped: Array = place.slice(need)
		for slot: int in through: status[slot] = SAFE
		dropped.reverse() # the worst first: the later out, the better the standing
		for slot: int in dropped:
			status[slot] = OUT
			if not eliminated.has(slot): eliminated.append(slot)
	elif not points_mode and kind == "final":
		for slot in place.size(): status[place[slot]] = CHAMPION if slot == 0 else SAFE
	_update_lead()
	_victory = _ends_in_podium()
	_set_phase("done")

## The results of a lobby circle that played one round: the winner (first of the round's ranking), or the clear time in a show for one.
func _single_results() -> Dictionary:
	var title := CourseSection.level_title(level)
	var scores := pts.duplicate()
	if host.count == 1:
		var seconds := float(_done_at.get(0, phase_time))
		if kind == "survival": return {"headline": title, "sub": "LASTED %.1f S" % seconds, "scores": scores, "winners": [0], "order": [0]}
		return {"headline": "%s CLEARED" % title, "sub": "%.1f S" % seconds if _done_at.has(0) else "TIME'S UP", "scores": scores, "winners": [0] if _done_at.has(0) else [], "order": [0]}
	var order: Array = place.filter(func(slot: int) -> bool: return not gone.has(slot)) # the round's ranking, then whoever did not place by points
	var unplaced: Array = range(host.count).filter(func(slot: int) -> bool: return not order.has(slot) and not gone.has(slot))
	unplaced.sort_custom(func(a: int, b: int) -> bool: return int(scores[a]) > int(scores[b]) or (int(scores[a]) == int(scores[b]) and a < b))
	order.append_array(unplaced)
	if place.is_empty(): return {"headline": "NO WINNER", "sub": title, "scores": scores, "winners": [], "order": order}
	var winner: int = place[0]
	return {"headline": "%s WINS" % host.name(winner), "sub": "%s  ·  %s" % [title, score_line(scores)], "scores": scores, "winners": [winner], "order": order}

# ------------------------------------------------------------------ the podium

func _begin_podium() -> void:
	pigeons.clear()
	standings = _standings()
	crown = int(standings[0]) if not standings.is_empty() else -1
	for slot in host.count:
		if slot == crown: status[slot] = CHAMPION
		elif status[slot] == OUT: status[slot] = SPECTATOR
	podium_spots = host.podium(level)
	_hold.clear()
	for rank in standings.size():
		var slot := int(standings[rank])
		if gone.has(slot): continue
		if rank < mini(3, podium_spots.size()): _hold[slot] = {"at": podium_spots[rank], "yaw": PODIUM_YAW}
	var away: Array = range(host.count).filter(func(slot: int) -> bool: return not _hold.has(slot)) # nobody stands in the podium shot but the top three
	_benched = away.duplicate()
	host.begin_podium(away) # a new epoch on the final's level: an eliminated player with a podium spot is simulated again, the others stay out
	for slot: int in _hold:
		host.send_to(slot, _hold[slot].at, float(_hold[slot].yaw))
		host.hold(slot, _hold[slot].at, PODIUM_DRIFT)
		_grace[slot] = GRACE
	lead = crown
	_set_phase("podium")

## The podium phase keeps everybody on their spot: the clients freeze their own couriers (modes/show/view.gd `hold_yaw`), and the authority drops
## every pose that strays more than PODIUM_DRIFT m from the spot (`host.hold`), so a client that walks off stays put on every screen; it is
## put back with send_to (so its own courier moves too) when poses were dropped, when it sank under its spot or when it was grabbed.
## Jumping in place is allowed (it stays on x/z).
func _hold_podium() -> void:
	for slot: int in _hold:
		if gone.has(slot) or not host.active(slot): continue
		var want: Dictionary = _hold[slot]
		var at: Vector3 = want.at
		var here: Vector3 = host.position(slot)
		var strayed: int = host.strays(slot)
		if strayed > 0 or Vector2(here.x - at.x, here.z - at.z).length() > PODIUM_DRIFT or here.y < at.y - PODIUM_FALL or host.held_by(slot) >= 0:
			host.send_to(slot, at, float(want.yaw))

## The show's order, best first: elimination by the final's place, then the later out the better; points by the total (the final's
## place breaks a tie).
func _standings() -> Array:
	var everyone: Array = range(host.count).filter(func(slot: int) -> bool: return not gone.has(slot))
	if points_mode:
		var final_rank := place.duplicate()
		everyone.sort_custom(func(a: int, b: int) -> bool:
			return int(pts[a]) > int(pts[b]) or (int(pts[a]) == int(pts[b]) and final_rank.find(a) < final_rank.find(b)))
		return everyone
	var order: Array = place.filter(func(slot: int) -> bool: return not gone.has(slot))
	var out_later_first := eliminated.duplicate()
	out_later_first.reverse()
	for slot: int in out_later_first:
		if not order.has(slot) and not gone.has(slot): order.append(slot)
	for slot: int in everyone:
		if not order.has(slot): order.append(slot)
	return order

func _leader_by_points() -> int:
	var best := -1
	for slot in host.count:
		if gone.has(slot): continue
		if best < 0 or int(pts[slot]) > int(pts[best]): best = slot
	return best if best >= 0 and int(pts[best]) > 0 else -1
