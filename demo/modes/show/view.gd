extends "res://modes/mode_view.gd"
## THE SHOW view (modes/show/rules.gd), client only. Reads only the show state: the card (the level's title on a plate with the rule line, then
## the 2-1 and GO), the live THROUGH counter, the local player's banner (QUALIFIED / ELIMINATED / CHAMPION, or the round's placement in a
## points show, or the time in a show for one) with their catchphrase, other players' events in the line, the spectator note, the FACE WALL
## after every round (face_wall.gd) and the target cue of a level that lists `cues` (plates.gd). The screen stays calm: one thing at a time
## (the card, then GO; after a round the banner first, then the wall, never both), the HUD in `calm` size at the edges, the key hint only at
## the first round's start. Every round draws in the show's one look (modes/mode_hud.gd, style/show_hud_kit.gd): no objective text top left (the card says the rule once), the timer, the counter pills (`counters`: THROUGH n/need,
## STANDING n) and the finish / elimination feed (`feed`) in the right column, the countdown and the banners (`big_kind`, `big_age`). A tile stage round (state `stage`) has its own HUD (stage_hud.gd: the rule in a pill at the top centre while the digits count,
## Current eliminations n/M, kill feed, 3-2-1 and GO, VICTORY) and sounds (the countdown, falls, the tile cue pool); the HUD's chip, board, timer and lines stay out of it. Camera hooks on the shell (game/game_run.gd):
## `spectate_slot` (the leader, for players who are out) and `view_override` (the fixed podium camera). The winner's crown floats
## over their head in the podium phase.
const TeamCast := preload("res://style/team_cast.gd")
const FaceWall := preload("res://modes/show/face_wall.gd")
const Plates := preload("res://modes/show/plates.gd")
const CourseSection := preload("res://course_section.gd")
const BadgeLook := preload("res://modes/show/badge_look.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const StageHud := preload("res://modes/show/stage_hud.gd")
const ShowRules := preload("res://modes/show/rules.gd")
const VictoryFlow := preload("res://modes/show/shared/victory_flow.gd")
const GameAudio := preload("res://game/game_audio.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const ItemsView := preload("res://modes/show/items_ui/items_view.gd")
const PigeonView := preload("res://modes/show/pigeon/pigeon_view.gd")
const ManagerView := preload("res://modes/show/manager/manager_view.gd")

const KINDS := {"race": "RACE", "survival": "SURVIVAL", "final": "FINAL"}
const NOTE_KEYS := "WASD move  ·  Space jumps  ·  Shift dash  ·  F grabs"
const HINT := 7.0 ## s the key hint stays up at the first round's start (never on a phone: the buttons say it)
const BANNER := 1.8 ## s the local player's result banner stays (a banner during play stays for the whole of its own animation: ShowBanner.total)
const BANNER_FADE := 0.3 ## s the banner fades out over when its time runs out
const SOLO_RESULT := 3.0 ## s a show for one holds a round's result (the banner is all it has)
const EVENT := 2.0 ## s another player's event stays in the line
const EVENT_KEEP := 4 ## events remembered (the newest shows)
const GO_SHOW := 1.0 ## s GO! stays after the gate opens
const FEED_SHOW := 2.9 ## s a fallen player's red-X pill stays, then it is cut out (the finish feed of a race: the same)
const FEED_MAX := 4 ## pills shown at once (the newest)
const FAILURE_SHOW := 1.4 ## s the local player's grey plate stays after it went out
const MARKER_HEAD := 1.8 ## m over the feet: the point the own marker hangs over (stage rounds)
const FALL_RADIUS := 8.0 ## m: another player's elimination is heard at full gain within this of the followed player, ...
const FALL_FALLOFF := 40.0 ## ... fading out linearly over this
const FALL_MIN := 0.12 ## the gain a far elimination keeps (it is still the round's news)
const TILE_SOUND := 7400 ## the step tiles' ids for game/game_audio.gd blink_warn / blink_gone: TILE_SOUND + index
const BADGE_BACK := Vector3(0.0, 1.22, 0.3) ## KEEP THE LOGO: the plate on the wearer's back (skeleton space: the character faces -Z) ...
const BADGE_OVER := 2.4 ## ... and the turning one this high over the wearer's feet
const CROWN_HEIGHT := 0.42 ## m, the crown's own height: as wide as a head
const CROWN_SEAT := -0.05 ## m the crown's base sits over (+) or in (-) the head anchor (the top of the head)
const CROWN_TILT := Vector3(-0.03, 0.0, 0.1) ## radians: tipped back a little and cocked to one side, as a crown is worn
const CROWN_DROP := 1.1 ## m over its place the crown starts and comes down from (nothing pops in), over CROWN_FALL seconds
const CROWN_FALL := 0.3
const CROWN_HAT := "hat_crown" ## the catalog item the crown becomes (character/catalog.json): the winner's hat from the landing on
const LookSync := preload("res://character/look_sync.gd")
const Look := preload("res://character/look.gd")
const BADGE_FLY := 0.35 ## s a logo plate takes to fly to its new wearer (or to drop onto the first wearers from BADGE_DROP m over them)
const BADGE_ARC := 0.5 ## m the flight rises over the straight line
const BADGE_DROP := 3.5
const BADGE_FALL := 2.0 ## s a plate nobody takes tumbles away before it is freed (17 m/s²: 34 m under where it was, out of sight)
const FALL_GRAVITY := 17.0
const PODIUM_YAW := PI ## the podium's players face +Z, towards the camera (rules.gd sends them the same way)

var _round := -1
var _play_t := 0.0 ## the newest phase time seen in "play" (a show for one: the time the round lasted)
var _mine_t := -1.0 ## the phase time the local player crossed the goal or fell (-1: not yet)
var _wall_at := 0.0 ## s into "done" when the face wall comes up: after the banner that is up at the round's end
var _phase := ""
var _status: Array = [] ## the statuses seen last, per slot ([] until the round's first state)
var _banner := ""
var _banner_line := ""
var _banner_kind := "" ## a ShowBanner kind
var _banner_age := 0.0 ## s since the banner came up
var _banner_left := 0.0
var _finish_feed: Array = [] ## the round's finishes and falls in the right column: {name, tail, rank, age} (not a stage round: stage_hud.gd has its own)
var _through := 0 ## how many finished so far (the rank of the next)
var _counter_text := "" ## the counter pills' words shown last, and the s since they changed (they swell)
var _counter_age := 9.0
var _events: Array = [] ## other players' events: {text, left}
var _clock := 0.0
var _crown_node: Node3D
var _items: Node3D ## the race's item boxes, item pill, effects and banners (modes/show/items_ui/items_view.gd)
var _pigeons: PigeonView ## GHOST PIGEON (EXPERIMENT, modes/show/pigeon/, docs/pigeon.md): the birds, their coos and drops, the splat on the screen, the bird's own camera and buttons
var _manager: Node3D ## EXPERIMENT, THE MANAGER: the banner, the clipboard, the rule prompt and the rules' effects (modes/show/manager/manager_view.gd)
var _flow: CanvasLayer ## the show's ending (victory_flow.gd): the VICTORY banner, the podium room's camera, the winners' landings
var _worn: Dictionary = {} ## KEEP THE LOGO: slot -> {back, over} the plates that slot wears
var _badge_seen: Variant = null ## the badge slots of the last play state (null before the first)
var _flights: Array = [] ## KEEP THE LOGO and the crown: plates / crowns in the air, {node, kind "fly" | "fall", which "back" | "over", slot (the wearer it flies to), from (Transform3D), age}
var _inbound := {} ## slot -> how many of its two plates are still in the air on their way to it
var _crown_age := 0.0 ## s since the crown appeared
var _awarded := -1 ## the slot whose crown hat was handed out (once per podium)
var _wall: CanvasLayer
var _plates: CanvasLayer
var _tiles_seen := false ## the step tiles' first state has been applied (it is applied quietly: no sounds for what already happened)
var _stage: CanvasLayer ## the stage round's HUD (stage_hud.gd)
var _stage_on := false ## the state's round is a stage round
var _feed: Array = [] ## stage: the fallen players' red-X pills, oldest first: {name, age}
var _fell_seen := -1 ## stage: how many of the state's `fell` were told already (-1 until the round's first state)
var _elim_n := -1 ## stage: the eliminations count shown
var _elim_age := 9.0 ## s since it changed
var _digit_heard := -1 ## stage: the countdown digit last sounded
var _go_heard := false
var _victory_heard := false
var _failure_t := -1.0 ## stage: s since the local player went out (its grey plate), -1 none

func build() -> void:
	_wall = FaceWall.new()
	add_child(_wall)
	_wall.setup(seats)
	_plates = Plates.new()
	add_child(_plates)
	_stage = StageHud.new()
	add_child(_stage)
	_flow = VictoryFlow.new()
	add_child(_flow)
	_flow.setup(run, self)
	_items = ItemsView.new()
	add_child(_items)
	_items.setup(self, run, my_slot, seats)
	_pigeons = PigeonView.new()
	add_child(_pigeons)
	_pigeons.setup(self, run, my_slot, seats)
	_manager = ManagerView.new()
	add_child(_manager)
	_manager.setup(run, my_slot, seats, _items)
	var levels: Variant = run.get("level_world") if run != null else null
	if levels != null:
		levels.tile_warned.connect(_tile_warned)
		levels.tile_vanished.connect(_tile_vanished)
		levels.door_burst.connect(_door_burst)
		levels.door_bonk.connect(_door_bonk)

func present(state: Dictionary, dt: float) -> void:
	_clock += dt
	_stage_on = bool(state.get("stage", false)) # before the tiles' state is applied: their cues are a stage round's
	var phase := str(state.get("phase", ""))
	var round_number := int(state.get("round", 0))
	if round_number != _round:
		_round = round_number
		_status = []
		_phase = ""
		_events.clear()
		_banner_left = 0.0
		_mine_t = -1.0
		_finish_feed.clear()
		_through = 0
		_counter_text = ""
		_counter_age = 9.0
		_stage_reset()
	var status := _ints(state, "status")
	if not _status.is_empty():
		for slot in mini(status.size(), _status.size()): _changed(slot, int(_status[slot]), int(status[slot]), state)
		if phase == "done" and _phase != "done" and _phase != "" and bool(state.get("points_mode", false)) and not _victorious(state) and not bool(state.get("victory", false)): _placed(state)
	if phase == "done" and _phase != "done": _wall_at = INF if bool(state.get("victory", false)) else maxf(_banner_left, ShowRules.STAGE_DONE if _victorious(state) else 0.0) # the wall comes up when the banner (a stage round's VICTORY) is gone; a round that ends in the podium room has no wall
	if phase == "play": _play_t = float(state.get("t", 0.0))
	if not status.is_empty(): _status = status
	_phase = phase
	_banner_left = maxf(_banner_left - dt, 0.0)
	_banner_age += dt
	for event in _events: event.left = float(event.left) - dt
	_events = _events.filter(func(event: Dictionary) -> bool: return float(event.left) > 0.0)
	for entry: Dictionary in _finish_feed: entry.age = float(entry.age) + dt
	_finish_feed = _finish_feed.filter(func(entry: Dictionary) -> bool: return float(entry.age) < FEED_SHOW)
	var counters := _counters(state)
	var counter_text := "|".join(counters)
	_counter_age = 0.0 if counter_text != _counter_text and _counter_text != "" else _counter_age + dt
	_counter_text = counter_text
	_pigeons.present(state, dt) # before the cameras: a player who is a bird follows its bird, it does not spectate
	_cameras(state, status)
	_items.busy = _banner_left > 0.0 or str(state.get("phase", "")) != "play" or float(state.get("t", 0.0)) < GO_SHOW + 0.15 # one big banner at a time: item banners wait for the show's
	_items.present(state, dt)
	_manager.busy = _items.busy
	_manager.present(state, dt)
	_flow.present(state, dt)
	_crown(state, dt)
	_badges(state)
	_fly(dt)
	_wall.update(state, INF if _solo(state) else _wall_at, my_slot) # a show for one has no wall: the banner is its result
	var levels: Variant = run.get("level_world") if run != null else null
	_tiles(state, levels)
	_doors(state, levels)
	_plates.update(state, float(levels.clock) if levels != null else 0.0)
	_stage_flow(state, dt)

func hud(state: Dictionary) -> Dictionary:
	var phase := str(state.get("phase", ""))
	if phase == "podium": return {"title": "", "big": "", "line": "", "timer": -1.0, "scores": [], "out": [], "tint": true, "calm": true, "note": ""} # the podium room is a picture of its own, the results page follows
	var stage := bool(state.get("stage", false)) # a stage round: its own pills, digits and VICTORY (stage_hud.gd) take the title, the board, the timer, the digits and the lines
	var kind := str(KINDS.get(str(state.get("kind", "")), ""))
	var title := "THE SHOW"
	if phase != "podium" and kind != "":
		var of_show := "ROUND %d  ·  " % int(state.get("round", 1)) if int(state.get("rounds", 3)) > 1 else ""
		title = "%s%s" % [of_show, kind]
	if Plates.title_up(state) or (stage and phase != "podium"): title = "" # the round card takes the chip's place
	var status := _ints(state, "status")
	var model := {"title": title, "big": "", "big_kind": "", "big_age": 1.0, "line": "", "timer": -1.0, "scores": [] if _solo(state) or (stage and phase != "podium") else _ints(state, "pts"), "out": [], "tint": true, "calm": true,
		"note": _note(state, status), "counters": [], "counter_age": _counter_age, "feed": []}
	for slot in status.size():
		if status[slot] == 2 or status[slot] == 3: model.out.append(slot)
	var left := float(state.get("left", -1.0))
	if left >= 0.0 and not stage: model.timer = left
	var count := float(state.get("count", 0.0))
	if phase == "play" and not stage:
		model.counters = _counters(state)
		model.feed = _feed_shown()
	match phase:
		"card": # the card's plates (plates.gd) first; the digits only after they are gone
			if count > 0.0 and count <= Plates.COUNT_FROM and not stage:
				model.big = str(ceili(count))
				model.big_kind = "digit"
				model.big_age = float(ceili(count)) - count
		"play":
			if float(state.get("t", 0.0)) < GO_SHOW and not stage:
				model.big = TeamCast.show_word("go")
				model.big_kind = "go"
				model.big_age = float(state.get("t", 0.0))
	var wall_up := phase == "done" and not _solo(state) and float(state.get("t", 0.0)) >= _wall_at
	if _banner_left > 0.0 and not wall_up:
		model.big = _banner
		model.big_kind = _banner_kind
		model.big_age = _banner_age
		model.line = _banner_line
		model.big_alpha = clampf(_banner_left / BANNER_FADE, 0.0, 1.0) # a banner cut early (a result before the wall) fades out
	elif stage: # the kill feed and the objective say it all
		pass
	elif _local_status(status) == 0 and not _events.is_empty() and not wall_up:
		model.line = str(_events.back().text)
	elif _local_status(status) == 0 and phase == "play" and str(state.get("play", "")) == "badge":
		model.line = "YOU HAVE A LOGO  ·  KEEP IT" if _ints(state, "badge").has(my_slot) else "GRAB SOMEONE WITH A LOGO"
	if not stage and (phase == "card" or phase == "play"):
		var head: Variant = _marker_point(status)
		if head is Vector2: model.marker = head
	return model

func _exit_tree() -> void:
	for slot: int in _worn.keys(): _drop_plates(slot)
	var levels: Variant = run.get("level_world") if run != null and is_instance_valid(run) else null
	if levels != null:
		levels.tile_warned.disconnect(_tile_warned)
		levels.tile_vanished.disconnect(_tile_vanished)
		levels.door_burst.disconnect(_door_burst)
		levels.door_bonk.disconnect(_door_bonk)
	if run != null and is_instance_valid(run):
		run.set("spectate_slot", -1)
		run.set("view_override", null)
		run.set("hold_yaw", null)
		run.set("hold_start", false)

# ------------------------------------------------------------------ step tiles

## The step tiles' bytes of the state (published in pieces `tiles`, `tiles1`, ...: StepTiles.join_state) go into the level world, which poses the
## tiles (and their colliders) from them and the level clock: a state with tiles of the round's level is all a client needs, a late joiner
## included (its first state is applied without sounds).
func _tiles(state: Dictionary, levels: Variant) -> void:
	var steps := StepTiles.join_state(state, int(levels.tile_count(int(state.get("level", -1)))) if levels != null else 0)
	if levels == null or steps.is_empty(): return
	levels.set_tile_steps(int(state.get("level", -1)), steps, not _tiles_seen)
	_tiles_seen = true

## A tile turned white / dropped. A stage round's tiles use the tile cue pool (game/game_audio.gd: a few voices a moment, quieter far from the followed player);
## the step tile round (the red tiles) uses the block cues.
func _tile_warned(index: int, at: Vector3) -> void:
	var audio: Variant = run.get("audio") if run != null else null
	if audio == null: return
	if _stage_on: audio.tile_warn(index, at)
	else: audio.blink_warn(TILE_SOUND + index, at)

func _tile_vanished(index: int, at: Vector3) -> void:
	var audio: Variant = run.get("audio") if run != null else null
	if audio == null: return
	if _stage_on: audio.tile_drop(index, at)
	else: audio.blink_gone(TILE_SOUND + index, at)

# ------------------------------------------------------------------ stage rounds

## The round changed: the stage round's flow starts over.
func _stage_reset() -> void:
	_feed.clear()
	_fell_seen = -1
	_elim_n = -1
	_elim_age = 9.0
	_failure_t = -1.0
	_digit_heard = -1
	_go_heard = false
	_victory_heard = false

## True when the local player won a stage round at its end (VICTORY): it is through (a points show: it is still standing). Never in a show for one.
func _victorious(state: Dictionary) -> bool:
	if not bool(state.get("stage", false)) or _solo(state) or my_slot < 0: return false
	var mine := _local_status(_ints(state, "status"))
	return mine == 1 or mine == 4 or (mine == 0 and bool(state.get("points_mode", false)) and _ints(state, "field").has(my_slot))

## A stage round's flow of the state: the countdown digits and GO with their sounds, the objective, the eliminations count and the kill feed (who fell, in order of
## the state's `fell`), the sound of every elimination, VICTORY at the round's end. The pieces go to the stage HUD as one model.
func _stage_flow(state: Dictionary, dt: float) -> void:
	_stage_on = bool(state.get("stage", false))
	if not _stage_on:
		_stage.call("show_model", {})
		return
	var phase := str(state.get("phase", ""))
	var count := float(state.get("count", 0.0))
	var t := float(state.get("t", 0.0))
	var audio: Variant = run.get("audio") if run != null else null
	var fell := _ints(state, "fell")
	if _fell_seen < 0: _fell_seen = fell.size() # the round's first state: what already happened is not told again
	elif fell.size() > _fell_seen:
		for slot: int in fell.slice(_fell_seen): _fell(slot, audio, state)
		_fell_seen = fell.size()
	var shown: Array = []
	for entry: Dictionary in _feed:
		entry.age = float(entry.age) + dt
		if float(entry.age) < FEED_SHOW: shown.append(entry)
	_feed = shown
	_elim_age += dt
	var field := _ints(state, "field")
	var status := _ints(state, "status")
	var out := 0
	for slot: int in field:
		if slot < status.size() and status[slot] == 2: out += 1
	var need := int(state.get("need", 1))
	var players := int(state.get("n", field.size()))
	var model := {"pill": "", "pill_age": -1.0, "elim_n": 0, "elim_m": -1, "elim_pop": _elim_age, "feed": [],
		"digit": "", "digit_age": 0.0, "go": "", "go_age": 0.0, "go_len": GO_SHOW, "victory_age": -1.0, "victory_len": ShowRules.STAGE_DONE,
		"failure": "", "failure_age": -1.0, "failure_len": FAILURE_SHOW}
	var words: String = StageHud.objective(need, players)
	var counting := phase == "card" and count > 0.0 and count <= ShowRules.STAGE_COUNT
	if counting:
		var digit := ceili(count)
		model.digit = str(digit)
		model.digit_age = float(digit) - count
		model.pill = words # the speech bubble: while the digits count and GO shows
		model.pill_age = ShowRules.STAGE_COUNT - count
		if digit != _digit_heard and audio != null: audio.play_event("countdown")
		_digit_heard = digit
	if phase == "play":
		if t < GO_SHOW:
			model.go = TeamCast.show_word("go")
			model.go_age = t
			model.pill = words
			model.pill_age = ShowRules.STAGE_COUNT + t
			if not _go_heard and audio != null: audio.play_event("go")
			_go_heard = true
		if players > 1:
			var fell_now := maxi(fell.size(), out)
			if fell_now != _elim_n:
				if _elim_n >= 0: _elim_age = 0.0
				_elim_n = fell_now
			model.elim_n = _elim_n
			model.elim_m = maxi(field.size() - need, 1)
			model.elim_pop = _elim_age
			var shown_feed: Array = []
			for index in range(maxi(_feed.size() - FEED_MAX, 0), _feed.size()): # the oldest of the last few on top, a new one comes in under them
				var entry: Dictionary = _feed[index]
				shown_feed.append({"name": entry.name, "age": entry.age, "left": FEED_SHOW - float(entry.age)})
			model.feed = shown_feed
	if _failure_t >= 0.0:
		_failure_t += dt
		if _failure_t < FAILURE_SHOW:
			model.failure = TeamCast.show_word("eliminated")
			model.failure_age = _failure_t
	if phase == "done" and _victorious(state) and t < ShowRules.STAGE_DONE:
		model.victory_age = t
		if not _victory_heard and audio != null: audio.play_event("room_clear")
		_victory_heard = true
	var head: Variant = _marker_point(status)
	if head is Vector2: model.marker = head
	_stage.call("show_model", model)

## The screen point over the local courier's head (the yellow marker's place), null when the player is out, unseated or the head is behind the camera.
func _marker_point(status: Array) -> Variant:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null or my_slot < 0 or _local_status(status) != 0: return null
	var at := feet(my_slot)
	if run != null and run.rig_lag.has(my_slot) and rig(my_slot) != null: at = rig(my_slot).global_position # the GLITCH: the marker rides the lagging character, it must not give the true spot away
	var head := at + Vector3(0.0, MARKER_HEAD, 0.0)
	return null if camera.is_position_behind(head) else camera.unproject_position(head)

## `slot` fell out of the round: its red-X pill, and the sound of it: the local player's own fall at full gain, another's as loud as it is near the followed player
## (the local courier, or the leader the spectator follows).
func _fell(slot: int, audio: Variant, state: Dictionary) -> void:
	_feed.append({"slot": slot, "name": str(cast_player(slot).name).to_upper(), "age": 0.0})
	if audio == null: return
	if slot == my_slot:
		audio.play_event("fall")
		return
	var mine := _local_status(_ints(state, "status"))
	var followed := int(state.get("lead", -1)) if mine == 2 or mine == 3 else my_slot
	var gain := 1.0
	if followed >= 0 and followed < seats.size():
		gain = maxf(GameAudio.attenuation(feet(slot).distance_to(feet(followed)), FALL_RADIUS, FALL_FALLOFF), FALL_MIN)
	audio.play_event("fall", null, gain)

# ------------------------------------------------------------------ KEEP THE LOGO

## The logo wearers of the state wear a plate on their back and a turning one over their head (client only); a logo changing hands is an event line.
## A plate never pops: the first wearers get theirs dropped onto them from above, a logo that changes hands flies from the one that lost it to the one that took
## it (every plate lost in the same state is paired with a plate gained, in slot order), a plate nobody takes tumbles away under the arena.
func _badges(state: Dictionary) -> void:
	var now := _ints(state, "badge")
	if str(state.get("phase", "")) == "play":
		if _badge_seen is Array:
			for slot: int in now:
				if not (_badge_seen as Array).has(slot):
					_events.append({"text": "YOU TOOK A LOGO" if slot == my_slot else "%s TOOK A LOGO" % str(cast_player(slot).name).to_upper(), "left": EVENT})
			for slot: int in _badge_seen:
				if slot == my_slot and not now.has(slot): _events.append({"text": "YOUR LOGO WAS TAKEN", "left": EVENT})
			if _events.size() > EVENT_KEEP: _events = _events.slice(_events.size() - EVENT_KEEP)
		_badge_seen = now
	else:
		_badge_seen = null
	var lost: Array = []
	for slot: int in _worn.keys():
		if not now.has(slot) or rig(slot) == null: lost.append(slot)
	var gained: Array = []
	for slot: int in now:
		if rig(slot) != null and not _worn.has(slot) and not _inbound.has(slot): gained.append(slot)
	lost.sort()
	gained.sort()
	for index in maxi(lost.size(), gained.size()):
		var from_slot: int = lost[index] if index < lost.size() else -1
		var to_slot: int = gained[index] if index < gained.size() else -1
		if from_slot >= 0: _take_off(from_slot, to_slot)
		elif to_slot >= 0: _bring(to_slot)
	for slot: int in _worn.keys():
		var over_node: Node3D = _worn[slot].over
		over_node.position = Vector3(0.0, BADGE_OVER + sin(_clock * 3.0 + float(slot)) * 0.05, 0.0)
		over_node.rotation.y = _clock * 2.4 + float(slot)

## The two plates of `slot` on its rig: the one on the back, the turning one over the head.
func _wear(slot: int) -> void:
	var rig_node := rig(slot)
	if rig_node == null or _worn.has(slot): return
	var back := BadgeLook.plate(0.19)
	var over := BadgeLook.floating(0.3)
	var skeleton: Variant = rig_node.call("skeleton") if rig_node.has_method("skeleton") else null
	(skeleton if skeleton is Node3D else rig_node).add_child(back)
	back.position = BADGE_BACK
	back.rotation.y = 0.0
	rig_node.add_child(over)
	_worn[slot] = {"back": back, "over": over}

## Where a plate of `slot` hangs once worn (world): "back" on the skeleton, "over" turning over the head.
func _plate_spot(slot: int, which: String) -> Transform3D:
	var rig_node := rig(slot)
	if which == "back":
		var skeleton: Variant = rig_node.call("skeleton") if rig_node.has_method("skeleton") else null
		var holder: Node3D = skeleton if skeleton is Node3D else rig_node
		return holder.global_transform * Transform3D(Basis.IDENTITY, BADGE_BACK)
	return rig_node.global_transform * Transform3D(Basis(Vector3.UP, _clock * 2.4 + float(slot)), Vector3(0.0, BADGE_OVER + sin(_clock * 3.0 + float(slot)) * 0.05, 0.0))

## `slot` loses its plates: they fly to `target` (-1: nobody took the logo, they tumble away).
func _take_off(slot: int, target: int) -> void:
	var parts: Dictionary = _worn.get(slot, {})
	_worn.erase(slot)
	var launched := 0
	for key: String in ["back", "over"]:
		var node: Variant = parts.get(key)
		if not node is Node3D or not is_instance_valid(node) or not (node as Node3D).is_inside_tree(): continue
		_launch(node as Node3D, "fly" if target >= 0 else "fall", key, target)
		launched += 1
	if target >= 0 and launched > 0: _inbound[target] = launched

## New plates over the first wearer `slot` (nobody lost a logo to it): they come down onto it from BADGE_DROP m above.
func _bring(slot: int) -> void:
	_inbound[slot] = 2
	for key: String in ["back", "over"]:
		var node := BadgeLook.plate(0.19) if key == "back" else BadgeLook.floating(0.3)
		add_child(node)
		var spot := _plate_spot(slot, key)
		node.global_transform = Transform3D(spot.basis, spot.origin + Vector3.UP * BADGE_DROP)
		_flights.append({"node": node, "kind": "fly", "which": key, "slot": slot, "from": node.global_transform, "age": 0.0})

## A node of the view or of a rig goes into the air as a flight (it stays where it is in the world and leaves its parent).
func _launch(node: Node3D, kind: String, which: String, slot: int) -> void:
	var at := node.global_transform
	if node.get_parent() != self:
		node.get_parent().remove_child(node)
		add_child(node)
	node.global_transform = at
	_flights.append({"node": node, "kind": kind, "which": which, "slot": slot, "from": at, "age": 0.0})

## Moves every flight: a plate flies to its wearer and becomes the plate it wears; a fallen one tumbles under the arena and is freed far below.
func _fly(dt: float) -> void:
	for flight: Dictionary in _flights.duplicate():
		var node: Node3D = flight.node
		if not is_instance_valid(node):
			_flights.erase(flight)
			continue
		flight.age = float(flight.age) + dt
		var age: float = flight.age
		var from: Transform3D = flight.from
		if str(flight.kind) == "fly" and rig(int(flight.slot)) == null: # its wearer left: it falls instead
			_inbound.erase(int(flight.slot))
			flight.kind = "fall"
			flight.from = node.global_transform
			flight.age = 0.0
			continue
		if str(flight.kind) == "fall":
			node.global_transform = Transform3D(Basis(Vector3(0.6, 0.2, 1.0).normalized(), age * 4.0) * from.basis, from.origin - Vector3(0.0, 0.5 * FALL_GRAVITY * age * age, 0.0))
			if age >= BADGE_FALL:
				node.queue_free()
				_flights.erase(flight)
			continue
		var progress := clampf(age / BADGE_FLY, 0.0, 1.0)
		var eased := progress * progress * (3.0 - 2.0 * progress)
		var moved := from.interpolate_with(_plate_spot(int(flight.slot), str(flight.which)), eased)
		node.global_transform = Transform3D(moved.basis, moved.origin + Vector3.UP * sin(PI * eased) * BADGE_ARC)
		if progress >= 1.0:
			node.queue_free()
			_flights.erase(flight)
			var slot := int(flight.slot)
			_inbound[slot] = int(_inbound.get(slot, 1)) - 1
			if int(_inbound[slot]) <= 0:
				_inbound.erase(slot)
				_wear(slot)

func _drop_plates(slot: int) -> void:
	var parts: Dictionary = _worn.get(slot, {})
	for key: String in ["back", "over"]:
		var node: Variant = parts.get(key)
		if node is Node and is_instance_valid(node): (node as Node).queue_free()
	_worn.erase(slot)

# ------------------------------------------------------------------ poster doors

## Every courier's position goes to the level world (it tells the poster doors, levels/poster_doors.gd, who went through or bumped them, and the launch pads
## who stepped on them): the doors burst and shudder and the pad buttons press on every machine for every player, from the positions each machine already has.
func _doors(state: Dictionary, levels: Variant) -> void:
	var level := int(state.get("level", -1))
	if levels == null or level < 0 or str(state.get("phase", "")) == "podium": return
	for slot in seats.size():
		levels.observe_doors(level, slot, feet(slot))
		levels.observe_pads(level, slot, feet(slot))

## A courier tore through a poster: a soft rip (a quick swing, pitched up) where it happened.
func _door_burst(_index: int, at: Vector3, _heading: Vector3) -> void:
	var audio: Variant = run.get("audio") if run != null else null
	if audio != null: audio.play_event("swing", at, 0.8, 7.0)

## A courier hit a solid poster: a dull thud. The local courier's own bump already plays the slap (game_run.gd, the level world's push-back), so this is for the others.
func _door_bonk(_index: int, at: Vector3, who: int) -> void:
	var audio: Variant = run.get("audio") if run != null else null
	if audio != null and who != my_slot: audio.play_event("bump", at, 0.9, -4.0)

# ------------------------------------------------------------------ banners

## A slot's status changed: the local player gets a banner, anybody else an event line.
func _changed(slot: int, was: int, now: int, state: Dictionary) -> void:
	if was == now: return
	if slot == my_slot and (now == 1 or now == 2) and str(state.get("phase", "")) == "play": _mine_t = float(state.get("t", 0.0))
	var word := ""
	var stage := bool(state.get("stage", false))
	match now:
		1: # safe: qualified / survived; a points show only finishes, the final's winner gets the crown's word instead
			if not bool(state.get("points_mode", false)) and str(state.get("kind", "")) != "final" and not stage: word = "qualified" # a stage round's VICTORY (stage_hud.gd) is the word
			if str(state.get("kind", "")) == "race" and str(state.get("phase", "")) == "play" and not stage: # the finish feed: the next rank, with the cast's word in a race that qualifies
				_through += 1
				_feed_add(slot, TeamCast.show_word("qualified") if word != "" else "", _through)
		2:
			word = "eliminated"
			if str(state.get("phase", "")) == "play" and not stage and str(state.get("kind", "")) == "survival": _feed_add(slot, TeamCast.show_word("eliminated"), 0)
		4: pass # the champion has no banner of its own: the victory flow's VICTORY banner and the podium room say it (victory_flow.gd)
	if word == "": return
	var text := TeamCast.show_word(word)
	if slot == my_slot:
		if word == "eliminated" and stage: _failure_t = 0.0 # a stage round's grey plate (stage_hud.gd) says it, no banner
		else: _say(text, str(cast_player(slot).get("catchphrase", "")), ShowBanner.total(word) if str(state.get("phase", "")) == "play" else BANNER, word) # in play the banner runs its whole animation
		var audio: Variant = run.get("audio") if run != null else null
		if word == "qualified" and audio != null and audio.has_method("play_checkpoint"): audio.call("play_checkpoint")

## `slot` finished or fell: its pill goes into the right column's feed (`rank` >= 1 a gold rank badge, 0 the red X).
func _feed_add(slot: int, tail: String, rank: int) -> void:
	_finish_feed.append({"name": str(cast_player(slot).name).to_upper(), "tail": tail, "rank": rank, "age": 0.0})
	if _finish_feed.size() > FEED_MAX: _finish_feed.pop_front()

## The feed of the model: {name, tail, rank, age, left}, the oldest on top.
func _feed_shown() -> Array:
	var shown: Array = []
	for entry: Dictionary in _finish_feed: shown.append({"name": entry.name, "tail": entry.tail, "rank": entry.rank, "age": entry.age, "left": FEED_SHOW - float(entry.age)})
	return shown

## A points round ended: the local player's place in it (the time it took in a show for one).
func _placed(state: Dictionary) -> void:
	if _solo(state):
		var status := _ints(state, "status")
		var seconds := "%.1f s" % (_mine_t if _mine_t >= 0.0 else _play_t)
		if str(state.get("kind", "")) == "survival": _say("LASTED", seconds, SOLO_RESULT, "victory")
		elif _local_status(status) == 1: _say("CLEARED", seconds, SOLO_RESULT, "victory")
		else: _say("TIME'S UP", "", SOLO_RESULT, "timesup")
		return
	var place := _ints(state, "place")
	var at := place.find(my_slot)
	if my_slot >= 0 and at >= 0: _say(FaceWall.ordinal(at + 1), str(cast_player(my_slot).get("catchphrase", "")), BANNER, "victory" if at == 0 else "qualified")

func _say(text: String, line: String, hold := BANNER, kind := "title") -> void:
	if _items != null: _items.cut_banner() # one big banner at a time: an item banner on screen makes room
	_banner = text
	_banner_line = line
	_banner_kind = kind
	_banner_age = 0.0
	_banner_left = hold

# ------------------------------------------------------------------ camera and crown

## The spectators follow the leader; the podium phase has its own fixed camera for everybody (the victory flow's: the podium room's three shots, modes/show/shared/victory_flow.gd), and holds everybody still on
## their spots (the shell's `hold_yaw`: no steering, no dash, no grab, facing the camera). The authority keeps them there too (rules.gd).
func _cameras(state: Dictionary, status: Array) -> void:
	if run == null: return
	var podium := str(state.get("phase", "")) == "podium"
	var out := _local_status(status) == 2 or _local_status(status) == 3
	run.set("spectate_slot", int(state.get("lead", -1)) if out and not podium and not _pigeons.mine() else -1)
	run.set("hold_yaw", PODIUM_YAW if podium else null)
	run.set("hold_start", bool(state.get("stage", false)) and str(state.get("phase", "")) == "card") # a tile round's card: stand on your start tiles until GO (the authority holds them there too, rules.gd)
	if not podium: run.set("view_override", null)

## True when a world point is inside the picture of `shot` (a camera of vertical field of view `fov` degrees, `aspect` width / height).
static func in_picture(shot: Transform3D, fov: float, aspect: float, point: Vector3) -> bool:
	var local := shot.affine_inverse() * point
	if local.z >= -0.1: return false
	var reach := tan(deg_to_rad(fov) * 0.5)
	return absf(local.y) <= -local.z * reach and absf(local.x) <= -local.z * reach * aspect

## The crown on the podium: a child of the winner's head anchor (character_rig.gd `head_anchor`), so it rides the head through every clip and the body's squash, tipped and seated as the
## wardrobe's CROWN hat is (tools/export_crown_hat.gd), and it comes down onto the head over CROWN_FALL seconds when the victory flow crowns the winner. From then on the crown is the winner's
## HAT (`_award`: saved, sent to the other players like any look, removable in the wardrobe): the podium crown steps aside the moment the rig wears it, and no crown is drawn after the podium.
func _crown(state: Dictionary, dt: float) -> void:
	var slot := int(state.get("crown", -1))
	var actors: Variant = run.get("actors") if run != null else null
	var phase := str(state.get("phase", ""))
	var waiting := phase == "podium" and float(state.get("t", 0.0)) < VictoryFlow.CROWN_AT # the winner is crowned on the podium when the victory flow says so
	var head: Node3D = null
	var body: Variant = rig(slot) if slot >= 0 else null
	if body != null and body.has_method("head_anchor"): head = body.call("head_anchor")
	if slot < 0 or phase != "podium" or waiting or head == null or not actors is Array or slot >= (actors as Array).size():
		if _crown_node != null:
			if _crown_node.is_inside_tree() and not _wears_crown(body): _launch(_crown_node, "fall", "", -1) # the crown falls away, it does not blink out
			else: _crown_node.queue_free()
			_crown_node = null
		if phase != "podium": _awarded = -1
		return
	if _crown_node == null:
		var made: Variant = load("res://style/show_crown.gd").call("crown", CROWN_HEIGHT)
		if made is Node3D:
			_crown_node = made
			_crown_node.name = "Crown"
			_crown_age = 0.0
	if _crown_node == null: return
	if _crown_node.get_parent() != head:
		if _crown_node.get_parent() != null: _crown_node.get_parent().remove_child(_crown_node)
		head.add_child(_crown_node)
	_crown_age += dt
	var coming := pow(maxf(1.0 - _crown_age / CROWN_FALL, 0.0), 2.0) * CROWN_DROP
	_crown_node.position = Vector3(0.0, CROWN_SEAT + coming, 0.0)
	_crown_node.rotation = CROWN_TILT
	if _crown_age >= CROWN_FALL and slot != _awarded: _award(slot, body)
	_crown_node.visible = not _wears_crown(body) # the hat is the same crown: never two on one head

## True when this character's look has the crown hat on.
func _wears_crown(body: Variant) -> bool:
	if body == null or not body.has_method("get_look"): return false
	var look: Variant = body.call("get_look")
	return look != null and str((look as Look).items.get("hat", "")) == CROWN_HAT

## The crown has landed on `slot`: on a seat of this device it becomes that player's hat (saved with the award, so the wardrobe offers it for good) and goes out to the others like any wardrobe pick
## (LookSync.commit; online only, a local show dresses its own characters). Everybody else's client dresses that character from the look it is sent.
func _award(slot: int, body: Variant) -> void:
	_awarded = slot
	if run == null or body == null or not body.has_method("set_look") or str(run.get("network_role")) == "authority": return
	var seat := -1
	if str(run.get("network_role")) == "local": seat = slot if slot < int(run.get("local_players")) else -1
	elif slot == my_slot: seat = LookSync.SAVE_SEAT
	if seat < 0: return
	var base: Look = (body.call("get_look") as Look) if body.has_method("get_look") and body.call("get_look") != null else Look.load_saved(seat)
	var look := Look.award(seat, CROWN_HAT, base)
	body.call("set_look", look)
	if str(run.get("network_role")) != "local": LookSync.commit(look)

# ------------------------------------------------------------------ helpers

func _note(state: Dictionary, status: Array) -> String:
	var local := _local_status(status)
	var phase := str(state.get("phase", ""))
	if phase == "done" or phase == "podium": return ""
	if _pigeons != null and _pigeons.mine(): return _pigeons.note() # a bird has its own keys
	if local == 2 or local == 3:
		var lead := int(state.get("lead", -1))
		return "SPECTATING  ·  %s" % str(cast_player(lead).name) if lead >= 0 else "SPECTATING"
	if has_method("touching") and bool(call("touching")): return ""
	if bool(state.get("stage", false)): return "" # a stage round has no dash and no grab: no key hint
	return NOTE_KEYS if int(state.get("round", 0)) == 1 and phase == "play" and float(state.get("t", 0.0)) < HINT else ""

## The show has one player (the solo app): no scoreboard, no wall.
func _solo(state: Dictionary) -> bool:
	return int(state.get("n", seats.size())) <= 1

func _local_status(status: Array) -> int:
	return int(status[my_slot]) if my_slot >= 0 and my_slot < status.size() else 0

## The counter pills (dark pills in the right column) while a round of an elimination show is on: how many are through (race), how many still stand (survival), the logos in play (keep the logo).
func _counters(state: Dictionary) -> Array:
	if str(state.get("phase", "")) != "play" or bool(state.get("points_mode", false)) or bool(state.get("stage", false)): return []
	var status := _ints(state, "status")
	var field := _ints(state, "field")
	var need := int(state.get("need", 0))
	match str(state.get("kind", "")):
		"race": return ["Through: %d/%d" % [status.count(1), need]]
		"survival":
			if str(state.get("play", "")) == "badge": return ["Logos in play: %d" % need]
			return ["Standing: %d" % field.filter(func(slot: int) -> bool: return slot < status.size() and status[slot] == 0).size(), "%d go through" % need]
	return []

static func _vector(spot: Variant) -> Vector3:
	if spot is Vector3: return spot
	if spot is Array and (spot as Array).size() >= 3: return Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
	return Vector3.ZERO

## A list of ints from the state ([] when it is missing or not a list).
static func _ints(state: Dictionary, key: String) -> Array:
	var value: Variant = state.get(key, [])
	var result: Array = []
	if value is Array:
		for entry: Variant in value: result.append(int(entry))
	return result
