extends Node
## The level game on one machine (local co-op, res://main.tscn): the same flow the online match has, without a server.
## PLAY -> the lobby yard (both players walk onto one of the two circles: TIME ATTACK or ENDLESS, then press PLAY: Enter or pad Y)
## -> the run (levels/level_run.gd:
## each level is its own file, entered at its start pad) -> the results page -> the lobby again. Two players carry the painting;
## the dev switch of course_section.gd (--balloon, FRIENDS_BALLOON=1) plays the balloon mode with them instead.
## It plays the authority's part (network/match_controller.gd) for the two local couriers and the client's part (lobby pads,
## level HUD, results page); the rules it shares with the online game are LevelRun, WalkInLobby and CourseSection.
## Installed by client/presentation_entry.gd (tree meta `gw_level_flow`), so shared code never names a client file.
const LevelRun := preload("res://levels/level_run.gd")
const CourseSection := preload("res://course_section.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const WalkInMarkers := preload("res://client/walk_in_markers.gd")
const MatchPresenter := preload("res://client/match_presenter.gd")
const LevelHud := preload("res://client/level_hud.gd")
const OnlineScreens := preload("res://client/online_screens.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Modes := preload("res://modes/modes.gd")
const ModeHost := preload("res://modes/mode_host.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")
const TandemView := preload("res://modes/show/tandem/tandem_view.gd")

var simulation: Node
var presentation: Node
var phase := "" ## lobby | round | results
var run: RefCounted
var play_mode := CourseSection.CARRY
var round_number := 0
var _markers: Node3D
var _level_hud: CanvasLayer
var _screens: Control
var _clock := 0.0
var _zones := ["", ""]
var _pick := ""
var _ready := "" ## the circle both players stand on, waiting for PLAY
var _play := "" ## the circle PLAY was pressed for; cleared when the shared circle changes
var _start_at := -1.0
var _clearing := false
var _next_at := -1.0
var minigame: RefCounted ## a minigame round's rules (modes/<id>/rules.gd; the cast's mode), null otherwise
var minigame_id := ""
var _mode_view: Node3D
var _mode_hud: CanvasLayer
var tandem: RefCounted ## the TANDEM experiment (modes/show/shared/tandem/tandem.gd): the lobby yard and a show's races, ticked here as the authority would
var _tandem_view: Node3D
var players := 2 ## humans on this machine (simulation.local_players): 1 = the show for one player, no partner to wait for

func configure(owner_presentation: Node, owner_simulation: Node) -> void:
	presentation = owner_presentation
	simulation = owner_simulation
	players = int(simulation.local_players)
	WalkInLobby.local_players = players
	process_mode = Node.PROCESS_MODE_PAUSABLE # the pause menu stops the game: and the countdown with it
	_level_hud = LevelHud.new()
	add_child(_level_hud)
	var overlay := CanvasLayer.new()
	overlay.layer = 40
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	_screens = OnlineScreens.new()
	overlay.add_child(_screens)
	_screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screens.play_again_pressed.connect(_enter_lobby)
	_screens.main_menu_pressed.connect(func() -> void: presentation.return_to_main())
	_markers = WalkInMarkers.new()
	add_child(_markers)
	_markers.build(simulation)
	if Modes.current() == "show":
		tandem = Tandem.new(simulation)
		_tandem_view = TandemView.new()
		simulation.world.add_child(_tandem_view)
		_tandem_view.setup(simulation, 0, [0, 1])

## PLAY was pressed: the lobby yard.
func start() -> void:
	_enter_lobby()

func in_run() -> bool:
	return phase == "round" and (run != null or minigame != null)

func _enter_lobby() -> void:
	_screens.hide_all()
	_end_minigame_view()
	phase = "lobby"
	run = null
	minigame = null
	minigame_id = ""
	_clearing = false
	_zones = ["", ""]
	_pick = ""
	_ready = ""
	_play = ""
	_start_at = -1.0
	presentation.hud.visible = false
	_level_hud.update({}, 0.0)
	simulation.set_course_plan(CourseSection.plan(CourseSection.default_course(), 0))
	simulation.configure_phase("lobby", [true, players > 1])
	simulation.set_local_input_enabled(true)
	_markers.set_shown(true)
	print("LEVEL_FLOW lobby")

func _physics_process(delta: float) -> void:
	if phase == "" or not is_instance_valid(simulation) or not simulation.is_network_ready(): return
	_clock += delta
	if phase == "lobby": _tick_lobby()
	elif phase == "round": _tick_round()
	_tick_tandem(delta)

## The TANDEM experiment (docs/party-show.md "Tandem (experiment)"): the lobby yard and a show's races, as the online authority ticks it (network/match_controller.gd).
func _tick_tandem(delta: float) -> void:
	if tandem == null: return
	var scope := ""
	var eligible: Array = []
	var solo := players == 1
	if phase == "lobby":
		scope = "lobby"
		for slot in players: eligible.append(slot)
	elif phase == "round" and minigame != null and minigame.has_method("tandem_ok"):
		scope = "race"
		for slot in players:
			if minigame.tandem_ok(slot): eligible.append(slot)
		solo = minigame.tandem_solo()
	tandem.tick(delta, scope, eligible, solo)

func _tick_lobby() -> void:
	for slot in players: _zones[slot] = WalkInLobby.zone_at(simulation.actors[slot].position, _zones[slot])
	var ready: String = str(_zones[0]) if players == 1 else WalkInLobby.shared_pick(_zones)
	if ready != _ready:
		_ready = ready
		_play = "" # a new shared circle (or none) needs its own PLAY
	var pick := _ready if _play == _ready else ""
	if pick != _pick:
		_pick = pick
		_start_at = _clock + WalkInLobby.COUNTDOWN if pick != "" else -1.0
	if _start_at >= 0.0 and _clock >= _start_at: _begin_run(_pick)

## PLAY (Enter, pad Y): with both players on one circle, its countdown starts.
func press_play() -> void:
	if phase != "lobby" or _ready == "" or not _may_play(_ready): return
	_play = _ready
	print("LEVEL_FLOW play ", _play)

## A round that needs other players (`"solo": false` in its level file) cannot be started in a show for one player.
func _may_play(pad: String) -> bool:
	if players > 1 or not Modes.is_minigame(Modes.current()): return true
	var row: Dictionary = RoundList.entry(str(WalkInLobby.pad(pad).get("pick", "")))
	return row.is_empty() or bool(row.solo)

func _unhandled_input(event: InputEvent) -> void:
	if phase != "lobby" or not event.is_pressed() or event.is_echo(): return
	var key: bool = event is InputEventKey and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER)
	if key or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y): press_play()

func _begin_run(course: String) -> void:
	if Modes.is_minigame(Modes.current()):
		_begin_minigame(Modes.current(), course)
		return
	play_mode = CourseSection.play_mode_for(2)
	run = LevelRun.new(course, CourseSection.level_count(), -1, CourseSection.pool_levels(play_mode))
	run.play_mode = play_mode
	round_number += 1
	phase = "round"
	_markers.set_shown(false)
	presentation.hud.visible = true
	print("LEVEL_FLOW run ", run.mode, " play=", play_mode, " queue=", run.queue)
	_start_level(course)

func _start_level(course: String) -> void:
	_clearing = false
	simulation.set_course_plan(CourseSection.plan(course, run.level(), play_mode))
	simulation.configure_phase("level", [true, true])
	simulation.set_local_input_enabled(true)
	print("LEVEL_FLOW level number=", run.number(), " level=", run.level() + 1, " ", CourseSection.level_title(run.level()))

## A minigame on one machine (docs/modes.md): the two local players in the yard, the mode's rules ticked here as the authority
## would, its view and HUD on top. Online a mode may need more players; here it always plays with the two.
func _begin_minigame(id: String, pad := "") -> void:
	minigame_id = id
	round_number += 1
	phase = "round"
	run = null
	_markers.set_shown(false)
	_level_hud.note("") # the lobby's line ("WHO SAID IT? in 2") would stay behind the mode's title
	_level_hud.update({}, 0.0)
	presentation.hud.visible = false
	simulation.configure_phase("lobby", [true, players > 1])
	simulation.set_local_input_enabled(true)
	minigame = Modes.new_rules(id)
	var host := ModeHost.new(simulation, range(players), int(Time.get_ticks_usec() & 0x7fffffff))
	host.pick = str(WalkInLobby.pad(pad).get("pick", ""))
	minigame.start(host)
	_mode_view = ModeViews.new_view(id)
	if _mode_view != null:
		_mode_view.name = "ModeView"
		simulation.world.add_child(_mode_view)
		_mode_view.setup(simulation, range(players), 0)
	if _mode_hud == null:
		_mode_hud = ModeHud.new()
		add_child(_mode_hud)
	_mode_hud.seats = range(players)
	print("LEVEL_FLOW minigame ", id)

func _finish_minigame(reason := "mode_done") -> void:
	if phase != "round" or minigame == null: return
	phase = "results"
	simulation.set_local_input_enabled(false)
	var outcome: Dictionary = minigame.results()
	var scores: Array = outcome.get("scores", [])
	_end_minigame_view()
	var ranks: Array = Modes.ranks(outcome, players)
	var rows := []
	for slot in players:
		var score := int(scores[slot]) if slot < scores.size() else 0
		rows.append({"seat": slot, "name": TeamCast.player_name(slot), "color": MatchPresenter.seat_color(slot), "me": slot == 0, "time": -1.0,
			"panes_intact": -1, "breaks": score, "arrived": false, "choice": "", "rank": int(ranks[slot]), "points": score})
	var headline := str(outcome.get("headline", ""))
	if headline == "": headline = str(Modes.info(minigame_id).get("title", "")).to_upper()
	_screens.show_results({"round": round_number, "headline": headline, "sub": str(outcome.get("sub", "")), "choose_in": -1.0, "remaining": players, "rows": rows,
		"course": "", "reason": reason, "time_limit": -1.0})
	print("LEVEL_FLOW results ", headline, " ", outcome.get("sub", ""))

func _end_minigame_view() -> void:
	if _mode_view != null and is_instance_valid(_mode_view): _mode_view.queue_free()
	_mode_view = null
	if _mode_hud != null: _mode_hud.show_model({})

func _tick_round() -> void:
	if minigame != null:
		minigame.tick(get_physics_process_delta_time())
		if minigame.finished(): _finish_minigame()
		return
	if _clearing:
		if _clock >= _next_at: _start_level(str(simulation.course_plan.get("course", CourseSection.ADVENTURE)))
		return
	if not simulation.won: return
	var seconds: float = simulation.elapsed_seconds
	var more: bool = run.level_cleared(seconds, int(simulation.breaks))
	print("LEVEL_FLOW cleared level=", run.queue[maxi(run.times.size() - 1, 0)] + 1, " seconds=", snappedf(seconds, 0.01), " more=", more)
	if more:
		_clearing = true
		_next_at = _clock + LevelRun.CLEARED_SECONDS
	else: finish_run()

## The pause menu's End run, or the last level of a time attack.
func finish_run() -> void:
	if phase == "round" and minigame != null:
		_finish_minigame("run_ended")
		return
	if phase != "round" or run == null: return
	phase = "results"
	_clearing = false
	simulation.set_local_input_enabled(false)
	presentation.hud.visible = false
	_level_hud.update({}, 0.0)
	var success: bool = run.finished or run.cleared() > 0
	var rows := []
	for slot in 2:
		rows.append({"seat": slot, "name": TeamCast.player_name(slot), "color": MatchPresenter.seat_color(slot), "me": slot == 0, "time": run.total() if run.cleared() > 0 else -1.0,
			"panes_intact": -1, "breaks": run.breaks, "arrived": success, "choice": ""})
	_screens.show_results({"round": round_number, "headline": run.headline(), "sub": run.summary(), "choose_in": -1.0, "remaining": 2, "rows": rows,
		"course": "", "reason": "", "time_limit": -1.0, "run": run.state()})
	print("LEVEL_FLOW results ", run.headline(), " ", run.summary())

## The run the HUDs show ({} outside a run).
func run_state() -> Dictionary:
	if phase != "round" or run == null: return {}
	return run.state(_clearing, maxf(_next_at - _clock, 0.0) if _clearing else -1.0)

## The overlay's PLAY button (a phone has no Enter) shows while both players wait on one circle.
func _play_button(on: bool) -> void:
	var touch: Variant = simulation.get("touch") if is_instance_valid(simulation) else null
	if touch != null: touch.set_optional("play", on)

func _process(delta: float) -> void:
	if _tandem_view != null: _tandem_view.present(tandem.state() if tandem != null and tandem.active else {}, delta)
	if phase != "lobby": _play_button(false)
	if phase == "lobby":
		var input := MatchPresenter.input_kind(get_tree())
		var model := MatchPresenter.lobby_model({"joined": 3, "ready": 3, "names": [TeamCast.player_name(0), TeamCast.player_name(1)], "zones": _zones, "pick": _pick, "start_in": maxf(_start_at - _clock, 0.0) if _start_at >= 0.0 else -1.0}, players, 0, players == 1, input)
		_markers.present(model, simulation.actors[0].position)
		var note := "Walk onto the circle" if players == 1 else "Both players: walk onto a circle together"
		if _pick != "": note = "%s in %d" % [WalkInLobby.title(_pick).capitalize(), ceili(maxf(_start_at - _clock, 0.0))]
		elif _ready != "" and not _may_play(_ready): note = "%s needs 2+ players" % WalkInLobby.title(_ready).capitalize()
		elif _ready != "": note = "%s: %s" % [WalkInLobby.title(_ready).capitalize(), MatchPresenter.play_prompt(input)]
		_level_hud.note(note)
		_play_button(_ready != "" and _pick == "" and _may_play(_ready))
	elif phase == "round" and minigame != null:
		var state: Dictionary = minigame.state()
		if _mode_view != null:
			_mode_view.present(state, delta)
			_mode_hud.show_model(_mode_view.hud(state))
	elif phase == "round":
		_level_hud.update(run_state(), float(simulation.elapsed_seconds))

func probe() -> Dictionary:
	return {"phase": phase, "run": run_state(), "zones": _zones, "pick": _pick, "ready": _ready, "hud": _level_hud.probe() if _level_hud != null else {},
		"minigame": minigame.state() if minigame != null else {}, "mode_hud": _mode_hud.probe() if _mode_hud != null else {}}
