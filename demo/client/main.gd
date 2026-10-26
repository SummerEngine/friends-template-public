extends Node
const DevEnv := preload("res://dev_env.gd")
## Summer matchmaking, lobby, rounds and results for the online game (docs/online-lobby.md).
## Owner-local simulation: this client simulates its own courier and sends its pose; the other
## couriers (up to nine) are drawn from the authority's relay, smoothed.
const Game = preload("res://network/game.gd")
const OwnerCourier = preload("res://network/owner_courier.gd")
const OwnerPoseWire = preload("res://network/owner_pose_wire.gd")
const RemoteCourier = preload("res://network/remote_courier.gd")
const MAX_CATCHUP_STEPS := 3 # Physics steps per rendered frame after a stall (engine default 8); the rest of the stall is dropped, not replayed.
const OWNER_SEND_PERIOD := 0.016 # One owner pose per 60 Hz physics frame.
const Hud = preload("res://client/hud.gd")
const LevelHud = preload("res://client/level_hud.gd")
const Ui = preload("res://client/friends_ui.gd")
const Menus = preload("res://client/menus.gd")
const PrivateQa = preload("res://client/private_qa.gd")
const MainMenu = preload("res://client/main_menu.gd")
const TouchControls = preload("res://client/touch_controls.gd")
const CourseSection = preload("res://course_section.gd")
const MatchPresenter = preload("res://client/match_presenter.gd")
const TeamCast = preload("res://style/team_cast.gd")
const WalkInLobby = preload("res://network/walk_in_lobby.gd")
const WalkInMarkers = preload("res://client/walk_in_markers.gd")
const ModeViews = preload("res://modes/mode_views.gd")
const TandemView = preload("res://modes/show/tandem/tandem_view.gd")
const ModeHud = preload("res://modes/mode_hud.gd")
const BASELINE_WAIT_MSEC := 1500
const READY_TIMEOUT := 120.0 ## seconds after the seat is taken without reaching the lobby: leave with an error (never a silent hang)
const LEVEL_WAIT_CAP := 300.0 ## seconds a connected client waits for its own level build before it gives up with an error
var world_entered := false ## this client reached the lobby (its owner worker is running): it is "in the world"
var ready_timed_out := false
var peer_ready_mask := 0 ## match.ready of the last snapshot: seats whose client is in the world
var peer_loading_mask := 0 ## match.joined without match.ready: seats taken by a client that is still loading
var sync_fail := ""
var pose_encode_failures := 0
var owner_courier: RefCounted
var owner_sequence := 0
var owner_grant := -1
var relay_groups := {} # seat -> relay group
var remote_couriers := {} # seat -> RemoteCourier
var relay_pending := {}
var relay_grants := {}
var relay_revisions := {}
var owner_echoes := 0
var private_qa = PrivateQa.new()
var spawner: SummerNetworkSpawner
var simulation
var input_group: SummerNetworkStateGroup
var my_seat := -1
var my_slot := -1
var seat_count := 2
var joined := false
var searching := false
var summer_ready := false
var bot_number := 0
var probe: Object ## dev probe (DevEnv.attach_probe): drives the round input of a stage-round test, null in a release build
var latest_snapshot := {}
var snapshot_count := 0
var send_time := 0.0
var sequence := 0
var jump_presses := 0 ## JUMP / GRAB presses of this session: sent as counters (the authority turns the change into presses)
var grab_presses := 0
var slap_presses := 0
var item_tests := 0 ## item-lab presses of this session: seq * 8 + the number 1-7, sent as test_seq (docs/items.md "Item lab")
var item_presses := 0 ## ITEM presses of this session (the show's item slot, modes/show/items/): sent as the counter item_seq, an extra key of the input wire
var current_input := {"move": [0, 0]}
var message := Label.new() # last status text (read by private_qa)
var hud
var level_hud ## the level run's words over a round (client/level_hud.gd)
var stats_time := 0.0
var connected_seconds := 0.0
var input_sent_at := {}
var input_echo_msec := 0.0
var last_snapshot_tick := -1
var last_reset_number := -1
var last_world_id := ""
var menus
var main_menu
var screens: Control
var name_tags: Node3D
var walk_in_markers: Node3D ## the lobby's course pads and signs (client/walk_in_markers.gd)
var mode_view: Node3D ## a minigame round's view (modes/<id>/view.gd), null otherwise
var mode_view_id := ""
var tandem_view: Node3D ## the TANDEM experiment's look (modes/show/tandem/tandem_view.gd): the lobby yard and a show's races; fed `match.tandem`
var mode_hud: CanvasLayer ## the minigame's words (modes/mode_hud.gd)
var local_starting := false
## Seconds of this client's own running time without a snapshot (-1: none expected yet). Wall time would count a
## stall of the client itself (process descheduled for seconds) as a stalled server and pause the owner.
var snapshot_silence := -1.0
var snapshot_stall_visible := false
var requested_queue: StringName = Game.DEFAULT_QUEUE
var local_play_queue: StringName = &"" # Local Play fixes the queue; the menu choice follows it
var prepared_queue: StringName = &""
var replica_loading := false ## the level (Level 1 + lobby yard) is being built; it starts at launch, behind the menu
var level_fraction := 0.0 ## build progress 0..1 while replica_loading
var held_snapshot := {} ## newest server snapshot that arrived before the level was built
var menu_gap := {"frames": 0, "sum": 0, "max": 0, "over25": 0, "over50": 0, "over100": 0} ## wall time between frames on the menu while the level builds
var menu_gap_last_msec := 0
var menu_gap_label := ""
var level_label := "" ## last step the level build reported
signal replica_settled ## a level build ended (ok or not)
var join_attempt := 0
var admitted_mode_binding := {}
var retry_mode_binding := {}
var mode_rejection_pending := false
var leaving_match := false
# --- lobby / rounds ---
var phase := "" # lobby | round | results | ended (from the authority)
var match_info := {}
var slot_seats: Array = [] # slot -> seat
var seat_slot := {} # seat -> slot
var baseline_state := {} # {"epoch": int, "players": Array} from the last full snapshot
var baseline_asked_msec := 0
var ui_state := "menu" # menu | loading | lobby | round | results | ended
var chose := ""
var results_dead_end_msec := -1
var owner_move := Vector2.ZERO
var ended_notice_msec := -1
var pending_shots: Array = []

## One line per milestone of the Play flow (event-driven, a dozen lines per session): where the time between launch and standing in the lobby goes.
func _flow(milestone: String) -> void:
	print("GW_FLOW t_ms=", Time.get_ticks_msec(), " ", milestone)

## Test hooks for a slow client (dev binary only): --dev-load-delay=S holds this client's level build back for S seconds,
## --dev-ready-delay=S keeps it on the JOINING page for S seconds after its seat is taken.
func _dev_delay(flag: String) -> float:
	for arg in DevEnv.user_args():
		if arg.begins_with(flag): return float(arg.trim_prefix(flag).split(":")[0])
	return 0.0

func _ready() -> void:
	TeamCast.use_fonts() # Japanese / Chinese cast text (demo/cast/fonts/)
	preload("res://client/presentation_entry.gd").install()
	Engine.max_physics_steps_per_frame = MAX_CATCHUP_STEPS
	DevEnv.perf_attach(self)
	probe = DevEnv.attach_probe(self, "client")
	# Closing the window leaves the World first, so the partner gets "A player left." at once
	# instead of a frozen round for the whole reconnect grace.
	get_tree().set_auto_accept_quit(false)
	for arg in DevEnv.user_args():
		if arg.begins_with("--bot="): bot_number = int(arg.trim_prefix("--bot="))
	TouchControls.fit_ui(get_tree()) # phones: thumb-sized menu buttons
	_menu()
	_flow("client_ready")
	load("res://game/game_audio.gd").install_music(get_tree()) # menu music; lives on the root through every scene change
	spawner = Game.build_network(self)
	spawner.state_group_created.connect(_group_created)
	$World.server_disconnected.connect(_lost_connection)
	$World.connection_failed.connect(_lost_connection)
	preload("res://character/look_sync.gd").attach(self) # players' looks online (demo/character/look_sync.gd)
	var initialized: SummerResult = await Summer.initialize().get_result_or_completed_signal()
	if not initialized.ok:
		_error("Open this game through Summer Games.", str(initialized.code))
		return
	summer_ready = true
	_flow("summer_ready")
	Summer.client.ratings.match_result.connect(_match_result)
	var party := Summer.client.party
	if party.is_available(): party.search_started.connect(_party_search)
	# LocalPlay's declared queue is fixture identity, not a user preference.
	var bootstrap_world: SummerWorld = Summer.client.context.world
	if bootstrap_world != null and Game.seats_for_queue(StringName(bootstrap_world.queue)) > 0:
		local_play_queue = StringName(bootstrap_world.queue)
		requested_queue = local_play_queue
	screens.hide_all()
	_refresh_menu_actions()
	_build_level_in_background()
	if bot_number > 0 or "--autoplay" in DevEnv.user_args() or private_qa.enabled: _menu_find.call_deferred(requested_queue)

func _menu() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)
	main_menu = MainMenu.new()
	main_menu.actions = _main_menu_actions()
	canvas.add_child(main_menu)
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var overlay := CanvasLayer.new()
	overlay.layer = 40
	add_child(overlay)
	screens = load("res://client/online_screens.gd").new()
	overlay.add_child(screens)
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens.set_loading_steps(PackedStringArray(LOADING_STEPS))
	screens.cancel_pressed.connect(_cancel_search)
	screens.back_pressed.connect(_back_to_menu)
	screens.play_again_pressed.connect(_choose.bind("again"))
	screens.main_menu_pressed.connect(_choose.bind("menu"))
	hud = Hud.new()
	hud.visible = false
	add_child(hud)
	level_hud = LevelHud.new()
	add_child(level_hud)
	menus = Menus.new()
	add_child(menus)
	menus.back_to_main.connect(_back_to_menu)
	menus.end_run_requested.connect(_end_run_from_pause)
	menus.pause_changed.connect(_pause_changed)
	# The one pause menu (same as local co-op and Singleplayer); online it cannot stop the match.
	menus.leave_text = "Leave match"
	menus.status_provider = _pause_status
	menus.restart_requested.connect(_restart_from_pause)

func _main_menu_actions() -> Dictionary:
	var actions := {"Play":_menu_play,"Settings":_menu_settings,"Quit":_menu_quit}
	if summer_ready and Summer.client.party.is_available(): actions["Invite"] = _invite
	return actions

func _refresh_menu_actions() -> void:
	if main_menu == null or ui_state != "menu": return
	main_menu.show_page("main", _main_menu_actions())

func _menu_play() -> void:
	if searching or joined or leaving_match: return
	_menu_find(Game.DEFAULT_QUEUE)

func _menu_find(queue: StringName) -> void:
	if searching or joined or leaving_match or not summer_ready: return
	_flow("play_pressed level_loading=%s level_ready=%s" % [replica_loading, simulation != null and simulation.is_network_ready()])
	if Game.seats_for_queue(queue) <= 0: return
	requested_queue = Game.DEFAULT_QUEUE
	last_world_id = ""
	retry_mode_binding.clear()
	_play()

func _menu_settings() -> void:
	menus.show_pause(false)

func _menu_quit() -> void:
	if summer_ready and (joined or searching): await _cancel()
	get_tree().quit()

func _sync_main_menu() -> void:
	if main_menu==null or local_starting: return
	main_menu.visible = ui_state == "menu"
	main_menu.set_process(main_menu.visible)
	for key: String in ["Play"]:
		var button: Button = main_menu.action_button(key)
		if button!=null: button.disabled = not summer_ready or searching or leaving_match

func _pause_changed(open: bool) -> void:
	if ui_state == "menu" and main_menu != null: main_menu.set_dimmed(open)
	if open: current_input = Game.away_input(current_input) # also: no walk-in countdown under the menu
	if simulation != null:
		simulation.set_camera_input_enabled(joined and not open and not _screens_block())

func _screens_block() -> bool:
	return screens != null and screens.current() in ["loading", "error", "results"]

func _pause_status() -> Dictionary:
	return {"overline": "Lobby" if phase == "lobby" else ""}

func _open_pause() -> void:
	menus.restart_available = phase == "round"
	menus.end_run_available = phase == "round" and not _run_model().is_empty()
	menus.show_pause()

## The level run of this round (match.run, levels/level_run.gd state()), {} outside a run.
func _run_model() -> Dictionary:
	var run: Variant = match_info.get("run", {})
	return run if run is Dictionary else {}

func _hide_round_hud() -> void:
	if hud != null: hud.visible = false
	if level_hud != null: level_hud.update({}, 0.0)

func _end_run_from_pause() -> void:
	if phase == "round" and not _screens_block(): _command({"c": "end_run"})

func _restart_from_pause() -> void:
	if phase == "round" and not _screens_block(): _command({"c": "restart"})

## Esc (keyboard) / Start (pad) toggles the pause menu in a lobby or round; on the loading and
## error pages Esc / B is Cancel / Back, so no screen is a dead end for the keyboard or a pad.
func _unhandled_input(event: InputEvent) -> void:
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var start: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START
	var back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if joined and phase == "lobby" and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y and not menus.pause_open:
		_command({"c": "play"}) # pad Y: PLAY on the shared circle
	if joined and ui_state in ["lobby", "round"]:
		if escape or start:
			if menus.pause_open: menus.hide_pause()
			else: _open_pause()
			get_viewport().set_input_as_handled()
	elif (escape or back) and not menus.pause_open and screens != null:
		match screens.current():
			"loading":
				var cancel: Button = screens.find_button("loading_cancel")
				if cancel != null and cancel.is_visible_in_tree():
					_cancel_search()
					get_viewport().set_input_as_handled()
			"error":
				_back_to_menu()
				get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ status screens

## The loading page shows the platform's stage (search, match, server, connect, join) and, while the level is still
## being built in the background, that build as the bar: both run at once, no separate "loading" step in front.
const LOADING_STEPS := ["Level", "Search", "Match", "Server", "Connect", "Lobby"]

func _loading(title: String, detail: String, cancelable := true, step := -1, progress := -1.0) -> void:
	current_input = Game.neutral_input(current_input)
	if simulation != null: simulation.set_camera_input_enabled(false)
	_hide_round_hud()
	message.text = title + "\n" + detail
	if ui_state != "loading": print("GW_CLIENT_STATUS ", title, " | ", detail)
	ui_state = "loading"
	screens.show_loading(title, detail, cancelable, level_fraction if progress < 0.0 and replica_loading else progress, step)
	_paint_level_progress()

## Bar and caption of the loading page while the match is being found: the level's build progress, then "Level ready".
func _paint_level_progress() -> void:
	if ui_state != "loading" or screens == null: return
	if replica_loading: screens.update_loading_progress(level_fraction, "Building the level")
	elif searching and not joined: screens.update_loading_progress(-1.0, "Level ready")

## Behind the main menu nothing is drawn in 3D (an opaque title covers the world anyway) and the level build yields
## to the menu's frame rate (Slicer.background); on the loading page it takes the full slice budget again.
func _sync_background_build() -> void:
	var in_menu := ui_state == "menu"
	var viewport := get_viewport()
	if viewport.disable_3d != in_menu: viewport.disable_3d = in_menu
	if simulation != null and simulation.load_slicer != null and simulation.load_slicer.background != in_menu: simulation.load_slicer.background = in_menu
	if replica_loading and in_menu:
		var now := Time.get_ticks_msec()
		if menu_gap_last_msec > 0:
			var gap := now - menu_gap_last_msec
			menu_gap.frames += 1
			menu_gap.sum += gap
			menu_gap.max = maxi(int(menu_gap.max), gap)
			if gap > 25: menu_gap.over25 += 1
			if gap > 50: menu_gap.over50 += 1
			if gap > 100:
				menu_gap.over100 += 1
				print("GW_MENU_GAP ms=", gap, " build step '", menu_gap_label, "' -> '", level_label, "' ", snappedf(level_fraction, 0.001))
		menu_gap_last_msec = now
		menu_gap_label = level_label
	else:
		menu_gap_last_msec = 0

## One line per build: wall time between frames while the menu was what the player looked at.
func _report_menu_frames() -> void:
	var frames := int(menu_gap.frames)
	if frames > 0: print("GW_MENU_FRAMES frames=", frames, " mean_ms=", snappedf(float(menu_gap.sum) / frames, 0.1), " max_ms=", menu_gap.max, " over25=", menu_gap.over25, " over50=", menu_gap.over50, " over100=", menu_gap.over100)
	menu_gap = {"frames": 0, "sum": 0, "max": 0, "over25": 0, "over50": 0, "over100": 0}
	menu_gap_last_msec = 0

func _error(title: String, detail: String) -> void:
	current_input = Game.neutral_input(current_input)
	if simulation != null: simulation.set_camera_input_enabled(false)
	_hide_round_hud()
	message.text = title + "\n" + detail
	print("GW_CLIENT_STATUS ", title, " | ", detail)
	ui_state = "menu"
	screens.show_error(title, detail)

func _back_to_menu() -> void:
	screens.hide_all()
	menus.hide_pause()
	await _cancel()

func _cancel_search() -> void:
	await _cancel()

func _invite() -> void:
	var result: SummerResult = await Summer.client.party.show_invite_dialog().get_result_or_completed_signal()
	if not result.ok: _error("Invite unavailable", str(result.code))

func _party_sheet() -> void:
	var result: SummerResult = await Summer.client.party.show_party_dialog().get_result_or_completed_signal()
	if not result.ok: _error("Party unavailable", str(result.code))

# ------------------------------------------------------------------ joining

func _play() -> void:
	if leaving_match or searching or not summer_ready or joined: return
	if last_world_id != "":
		_enter(SummerJoinTarget.world(last_world_id))
		return
	var party := Summer.client.party
	if party.is_available() and party.is_in_party():
		if party.is_leader(): _enter(SummerJoinTarget.party_queue(requested_queue))
		else: _loading("WAITING FOR THE PARTY LEADER", "The leader's search brings the whole party into one lobby.", true)
	else:
		_enter(SummerJoinTarget.queue(requested_queue))

func _party_search(queue: StringName) -> void:
	if not joined and not searching and not Summer.client.party.is_leader():
		if queue==&"": queue=Summer.client.party.get_search_queue()
		_enter(SummerJoinTarget.party_queue(queue))

func _accept_match(proposal: SummerMatchmakingProposal) -> void:
	if proposal==null or proposal.is_decided(): return
	if StringName(proposal.queue)!=prepared_queue:
		proposal.decline()
		_reject_match_mode("The proposed queue differs from the prepared match mode.")
		return
	var accepted: SummerResult=proposal.accept()
	private_qa.note_join("proposal_decision",{"ok":accepted.ok,"code":str(accepted.code),"decided":proposal.is_decided(),"queue":str(proposal.queue),"accept_by_unix_ms":proposal.accept_by_unix_msec})

## Stage names of SummerJoinProgress -> what the player reads while the platform works.
func _join_progress(progress: SummerJoinProgress) -> void:
	_flow("join_stage %s elapsed_ms=%d" % [progress.stage, progress.elapsed_msec])
	match progress.stage:
		SummerJoinProgress.STAGE_RESOLVING, SummerJoinProgress.STAGE_RESERVED:
			_loading("FINDING A PARTNER", "", true, 1)
		SummerJoinProgress.STAGE_PROPOSED:
			_loading("PARTNER FOUND", "", true, 2)
		SummerJoinProgress.STAGE_LAUNCHING:
			_loading("STARTING THE SERVER", "" if progress.attempt <= 1 else "Attempt %d" % progress.attempt, true, 3)
		SummerJoinProgress.STAGE_CONNECTING:
			_loading("CONNECTING", "", true, 4)
		SummerJoinProgress.STAGE_ADMITTING:
			_loading("CONNECTING", "", true, 4)
		SummerJoinProgress.STAGE_CONNECTED:
			if replica_loading: _loading("BUILDING THE LEVEL", "Your match is ready", true, 0)
			else: _loading("JOINING", "", true, 5)
		SummerJoinProgress.STAGE_RECONNECTING:
			_loading("RECONNECTING", "", true, 4)
	private_qa.note_join("progress",{"stage":progress.stage,"elapsed_ms":progress.elapsed_msec,"attempt":progress.attempt,"region":str(progress.region),"resumed":progress.resumed})

func _target_match_queue(target: SummerJoinTarget) -> StringName:
	if target==null: return &""
	if target.get_kind() in [SummerJoinTarget.KIND_QUEUE,SummerJoinTarget.KIND_PARTY_QUEUE]:
		var queue := target.get_queue()
		return queue if not Game.match_mode_for_queue(queue).is_empty() else &""
	if target.get_kind()==SummerJoinTarget.KIND_WORLD:
		return Game.retry_queue(target.get_world_id(),retry_mode_binding)
	return &"" # No mode guess for an unknown invite/follow/provider.

func _replica_ready(queue: StringName) -> bool:
	var mode := Game.match_mode_for_queue(queue)
	return not mode.is_empty() and simulation != null and simulation.is_network_ready() and prepared_queue == queue

## The one level is built once per session, from launch, behind the main menu (`_build_level_in_background`). Play does
## not start it: it only waits for what is left of it, while the search runs at the same time. A second caller during a
## build waits for that build instead of starting another.
func _prepare_replica(queue: StringName) -> bool:
	var mode := Game.match_mode_for_queue(queue)
	if mode.is_empty() or joined: return false
	while replica_loading:
		await replica_settled
		if not is_inside_tree(): return false
	if _replica_ready(queue): return true
	replica_loading = true
	level_fraction = 0.0
	prepared_queue = queue
	seat_count = int(mode.seat_count)
	_flow("level_build_start")
	var built := await _build_replica(queue, mode)
	if not built: prepared_queue = &""
	replica_loading = false
	_flow("level_build_done ok=%s static_mb=%d" % [built, OS.get_static_memory_usage() / 1048576])
	_report_menu_frames()
	_paint_level_progress()
	replica_settled.emit()
	return built

func _build_level_in_background() -> void:
	await get_tree().process_frame
	await get_tree().process_frame # the menu is drawn before the first slice of the build
	if replica_loading or _replica_ready(Game.DEFAULT_QUEUE): return
	await _prepare_replica(Game.DEFAULT_QUEUE)

func _build_replica(queue: StringName, mode: Dictionary) -> bool:
	_dispose_workers()
	if name_tags != null:
		name_tags.queue_free()
		name_tags = null
	if walk_in_markers != null:
		walk_in_markers.queue_free()
		walk_in_markers = null
	if simulation!=null:
		simulation.queue_free()
		simulation=null
		await get_tree().process_frame
	if not is_inside_tree(): return false
	await get_tree().process_frame
	await get_tree().process_frame # Whatever is on screen is drawn before the level build starts taking frame time.
	var dev_load_delay := _dev_delay("--dev-load-delay=")
	if dev_load_delay > 0.0:
		_flow("dev_load_delay %.0f s" % dev_load_delay)
		await get_tree().create_timer(dev_load_delay).timeout
	simulation=load("res://game/game_run.gd").new()
	simulation.name="Replica"
	simulation.network_role="replica"
	simulation.carrier_count=int(mode.seat_count)
	simulation.load_yield = true # a frame between build steps: the menu / loading page keeps animating
	simulation.load_background = ui_state == "menu" # slices follow the frame time behind the menu
	simulation.load_progress.connect(_replica_load_progress)
	add_child(simulation)
	while is_inside_tree() and not simulation.is_network_ready(): await get_tree().process_frame
	if not is_inside_tree(): return false
	menus.configure_camera_settings(simulation.apply_camera_settings,["XSensitivity","YSensitivity","InvertX","InvertY"])
	simulation.set_camera_input_enabled(false)
	name_tags = load("res://client/name_tags.gd").new()
	name_tags.name = "NameTags"
	simulation.world.add_child(name_tags)
	name_tags.configure(simulation)
	walk_in_markers = WalkInMarkers.new()
	simulation.world.add_child(walk_in_markers)
	walk_in_markers.build(simulation)
	print("GW_REPLICA_MODE_READY queue=",queue," seats=",seat_count," transport_joined=false")
	if not held_snapshot.is_empty():
		var held := held_snapshot
		held_snapshot = {}
		_snapshot(held) # the server's state that arrived while the level was still being built
	return true

func _replica_load_progress(fraction: float, label: String) -> void:
	level_fraction = fraction
	level_label = label
	if ui_state == "loading" and replica_loading: screens.update_loading_progress(fraction, "Building the level")

func _reject_match_mode(detail: String) -> void:
	if mode_rejection_pending: return
	mode_rejection_pending=true
	current_input=Game.neutral_input(current_input)
	_finish_mode_rejection.call_deferred(detail,join_attempt)

func _finish_mode_rejection(detail: String, attempt: int) -> void:
	if not is_inside_tree() or attempt!=join_attempt or leaving_match: return
	await _cancel()
	if not is_inside_tree() or join_attempt!=attempt+1: return
	mode_rejection_pending=false
	_error("Incompatible match mode", detail)

func _fail_join_after_leave(detail: String, preserve_retry: bool, attempt: int) -> void:
	if not is_inside_tree() or attempt!=join_attempt or leaving_match: return
	await _cancel(not preserve_retry)
	# Cancel advances the attempt exactly once. Never overwrite a newer screen.
	if not is_inside_tree() or join_attempt!=attempt+1: return
	_error("Could not join", detail)

func _request_seat(queue: StringName, attempt: int) -> Dictionary:
	var answer := await _command({"c":"join","match_mode":Game.match_mode_for_queue(queue)})
	if not is_inside_tree() or attempt!=join_attempt: return {}
	private_qa.note_join("seat_command_result",{"ok":answer.get("ok",false),"error":str(answer.get("error",""))})
	if not answer.get("ok",false):
		var reason := str(answer.get("error","unknown"))
		if reason=="match_mode_mismatch":
			_reject_match_mode("The authority rejected the selected mode.")
		else:
			# An unavailable observation is not an authority mode verdict.
			var connection_failure: bool = int(answer.get("outcome",-1))==SummerNetworkCommandHandle.OUTCOME_DISCONNECTED or (int(answer.get("outcome",-1))==SummerNetworkCommandHandle.OUTCOME_UNAVAILABLE and reason in ["outcome_timeout","authority_epoch_lost"])
			_fail_join_after_leave.call_deferred("The world did not respond: "+reason,connection_failure,attempt)
		return {}
	return answer

func _enter(target: SummerJoinTarget) -> void:
	if searching or joined or leaving_match: return
	var queue := _target_match_queue(target)
	if queue==&"":
		_error("Cannot join", "This destination has no verified shared match mode.")
		return
	join_attempt+=1
	mode_rejection_pending=false
	var attempt := join_attempt
	last_snapshot_tick = -1
	last_reset_number = -1
	snapshot_silence = -1.0
	snapshot_stall_visible = false
	latest_snapshot.clear()
	held_snapshot = {}
	baseline_state.clear()
	match_info = {}
	phase = ""
	searching = true
	world_entered = false
	ready_timed_out = false
	peer_ready_mask = 0
	peer_loading_mask = 0
	admitted_mode_binding.clear()
	# The level has been building since launch. Play does not wait for it: the search starts now and the two run side
	# by side; the join below waits for whichever of them is slower.
	if not _replica_ready(queue): _prepare_replica(queue)
	_loading("FINDING A PARTNER", "", true, 1)
	private_qa.note_join("join_requested",{"queue":str(queue)})
	var operation := Summer.client.join(target)
	operation.acceptance_required.connect(_accept_match)
	operation.progress_changed.connect(_join_progress)
	if operation.progress!=null: _join_progress(operation.progress)
	# A resumed operation may already hold its current opaque proposal.
	# The decision handle is idempotent; no identity or grant is supplied.
	if operation.pending_proposal!=null: _accept_match(operation.pending_proposal)
	var result: SummerResult = await operation.get_result_or_completed_signal()
	if not is_inside_tree() or attempt!=join_attempt: return
	private_qa.note_join("join_result",{"ok":result.ok,"code":str(result.code),"retryable":result.retryable})
	if not result.ok:
		searching = false
		print("GW_JOIN_FAILED ", result.code, " ", result.message)
		_error("Could not join", str(result.code) + "\n" + str(result.message))
		return
	_flow("join_result ok=%s level_ready=%s" % [result.ok, _replica_ready(queue)])
	if not _replica_ready(queue):
		# The server is up before the level is: finish the level (the page shows its progress) before taking a seat.
		_loading("BUILDING THE LEVEL", "Your match is ready", true, 0)
		var waited := 0.0
		while replica_loading and waited < LEVEL_WAIT_CAP and is_inside_tree() and attempt==join_attempt:
			await get_tree().process_frame
			waited += get_process_delta_time()
		if not is_inside_tree() or attempt!=join_attempt: return
		var built := _replica_ready(queue)
		if not built and not replica_loading: built = await _prepare_replica(queue) # a failed build gets one more try
		if not is_inside_tree() or attempt!=join_attempt: return
		if not built:
			_fail_join_after_leave.call_deferred("The level could not be built in time.", false, attempt)
			return
	_loading("JOINING", "", true, 5)
	if operation.world!=null: private_qa.note_join("sdk_connected",{"world_id":operation.world.world_id})
	if not spawner.is_network_ready():
		private_qa.note_join("spawner_wait")
		await spawner.network_ready
	if not is_inside_tree() or attempt!=join_attempt: return
	private_qa.note_join("spawner_ready")
	var answer := await _request_seat(queue,attempt)
	if not is_inside_tree() or attempt!=join_attempt: return
	if answer.is_empty(): return
	var admitted_world: SummerWorld = Summer.client.context.world
	if admitted_world==null or (operation.world!=null and operation.world.world_id!=admitted_world.world_id) or (target.get_kind()==SummerJoinTarget.KIND_WORLD and target.get_world_id()!=admitted_world.world_id):
		_reject_match_mode("The admitted World differs from the requested destination.")
		return
	var binding := Game.bind_match_mode(admitted_world.world_id,StringName(admitted_world.queue),queue,answer.result.get("match_mode"))
	if binding.is_empty():
		_reject_match_mode("The admitted queue and authority mode disagree.")
		return
	admitted_mode_binding=binding
	retry_mode_binding=binding.duplicate()
	my_seat = int(answer.result.get("seat", -1))
	if my_seat < 0 or my_seat >= seat_count:
		_reject_match_mode("The authority returned an invalid player seat.")
		return
	my_slot = my_seat # lobby: slot == seat; the next snapshot's match.slots decides
	simulation.set_local_seat(my_slot)
	name_tags.set_local_slot(my_slot)
	if not latest_snapshot.is_empty():
		# Apply the displayed painting and courier positions before the owner courier is seeded.
		simulation.apply_network_state(latest_snapshot,1.0)
	input_group = spawner.get_state_group(Game.INPUT, Game.input_key(my_seat))
	_sync_owner()
	for seat in seat_count:
		var worker_group := spawner.get_state_group(Game.WORKER,Game.input_key(seat))
		if worker_group != null: _attach_relay_group(worker_group)
	joined=true
	_flow("joined seat=%d" % my_seat)
	searching=false
	connected_seconds = 0.0
	snapshot_silence = 0.0
	last_world_id = admitted_world.world_id
	chose = ""
	baseline_asked_msec = Time.get_ticks_msec()
	_loading("JOINING", "", false, 5)
	print("GW_CLIENT_JOINED seat=", my_seat, " own_input_only=true queue=",queue," seats=",seat_count)

func _leave_transport() -> void:
	await Summer.client.leave().get_result_or_completed_signal()

const QUIT_LEAVE_WAIT := 1.5 ## seconds a closing window waits for the leave to go out

var quitting := false
var quit_left := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit_after_leave()

func _quit_after_leave() -> void:
	if quitting: return
	quitting = true
	if joined or searching:
		print("GW_CLIENT_QUIT_LEAVE seat=", my_seat, " phase=", phase)
		leaving_match = true
		_leave_for_quit()
		var deadline := Time.get_ticks_msec() + int(QUIT_LEAVE_WAIT * 1000.0)
		while not quit_left and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	get_tree().quit()

func _leave_for_quit() -> void:
	if joined: await _command({"c": "leave"}) # the authority ends the round now instead of waiting out the reconnect grace
	await _leave_transport()
	quit_left = true

func _cancel(clear_retry := true) -> void:
	if leaving_match: return
	leaving_match=true
	join_attempt+=1
	admitted_mode_binding.clear()
	mode_rejection_pending=false
	if clear_retry:
		retry_mode_binding.clear()
		last_world_id=""
	_dispose_workers()
	searching = false
	joined = false
	my_seat = -1
	my_slot = -1
	phase = ""
	match_info = {}
	chose = ""
	current_input = Game.neutral_input(current_input)
	snapshot_silence = -1.0
	snapshot_stall_visible = false
	menus.hide_pause()
	if simulation != null: simulation.set_camera_input_enabled(false)
	if simulation != null and simulation.audio != null: simulation.audio.reset_baseline()
	_hide_round_hud()
	screens.hide_all()
	await _leave_transport()
	if not is_inside_tree(): return
	leaving_match=false
	ui_state = "menu"
	latest_snapshot.clear()
	held_snapshot = {}
	baseline_state.clear()
	if name_tags != null: name_tags.set_slots([])
	print("GW_CLIENT_MENU")

func _lost_connection(code: String, detail: String) -> void:
	admitted_mode_binding.clear() # Keep only the previously verified retry tuple.
	_dispose_workers()
	print("GW_CONNECTION_LOST code=", code, " detail=", detail)
	if leaving_match or (not joined and not searching): return
	var during_join := searching and not joined
	var was_over := phase == "ended" or (phase == "results" and chose == "menu")
	join_attempt+=1 # Fence pending spawner/seat awaits before their late outcomes.
	mode_rejection_pending=false
	searching=false
	joined = false
	my_seat = -1
	my_slot = -1
	current_input = Game.neutral_input(current_input)
	input_group = null
	snapshot_silence = -1.0
	snapshot_stall_visible = false
	menus.hide_pause()
	if simulation != null: simulation.set_camera_input_enabled(false)
	_hide_round_hud()
	latest_snapshot.clear()
	held_snapshot = {}
	baseline_state.clear()
	last_snapshot_tick = -1
	last_world_id = ""
	retry_mode_binding.clear()
	phase = ""
	match_info = {}
	if name_tags != null: name_tags.set_slots([])
	screens.hide_all()
	await _leave_transport()
	if not is_inside_tree(): return
	ui_state = "menu"
	if was_over:
		print("GW_CLIENT_MATCH_OVER")
		_error("Match over", "Thanks for playing. The lobby closed.")
	else:
		_error("Connection lost" + (" while joining" if during_join else ""), code)

func _match_result(result: SummerMatchResult) -> void:
	print("GW_MATCH_RESULT outcome=", result.outcome, " rating_state=", result.rating_state)

func _command(payload: Dictionary) -> Dictionary:
	var admission := spawner.enqueue_command(Game.COMMAND, Game.pack(payload))
	if not admission.is_enqueued(): return {"ok": false, "error": str(admission.get_code())}
	var handle := admission.get_handle()
	if not handle.is_terminal(): await handle.completed
	if handle.get_outcome() == SummerNetworkCommandHandle.OUTCOME_ACCEPTED:
		return {"ok": true, "result": Game.unpack(handle.get_result())}
	return {"ok": false, "error": str(handle.get_reason()),"outcome":handle.get_outcome()}

# ------------------------------------------------------------------ snapshots

func _group_created(group: SummerNetworkStateGroup) -> void:
	if group.get_stream_id() == Game.SNAPSHOT:
		_snapshot(group.get_state())
		group.state_installed.connect(func(state: Dictionary, _revision: int, _reset: bool) -> void: _snapshot(state))
	elif group.get_stream_id() == Game.INPUT and group.get_key() == Game.input_key(my_seat):
		input_group = group
	elif group.get_stream_id() == Game.WORKER:
		_attach_relay_group(group)

func _snapshot(fields: Dictionary) -> void:
	if simulation == null or not simulation.is_network_ready() or name_tags == null:
		held_snapshot = fields.duplicate() # the level is still being built: its newest state is applied right after
		return
	var state := Game.unpack_snapshot(fields)
	if state.is_empty(): return
	if prepared_queue==&"" or not Game.valid_match_mode(state,prepared_queue):
		_reject_match_mode("Snapshot mode does not match the initialized rig.")
		return
	var tick := int(state.get("tick", -1))
	var reset_number := int(state.get("resets", 0))
	if reset_number < last_reset_number: return
	if reset_number == last_reset_number and tick < last_snapshot_tick: return
	if reset_number > last_reset_number and last_reset_number >= 0:
		print("GW_CLIENT_EPOCH seat=", my_seat, " resets=", reset_number, " tick=", tick, " previous_tick=", last_snapshot_tick)
	last_reset_number = reset_number
	last_snapshot_tick = tick
	snapshot_silence = 0.0
	# Full owner baselines come in bursts (epoch, join, resync). Slim snapshots borrow the
	# baseline of their epoch, so everything downstream keeps reading players[slot].movement.
	var players: Array = state.get("players", [])
	if bool(state.get("baseline", false)):
		var movements := []
		for player: Dictionary in players: movements.append(player.get("movement", {}))
		baseline_state = {"epoch": reset_number, "players": movements}
	if int(baseline_state.get("epoch", -1)) == reset_number:
		for slot in mini(players.size(), (baseline_state.players as Array).size()):
			if not players[slot].has("movement") and not players[slot].get("inactive", false) and (baseline_state.players[slot] as Dictionary).has("yaw"):
				players[slot].movement = baseline_state.players[slot]
	latest_snapshot = state
	if state.get("match") is Dictionary: _apply_match(state.match)
	if joined: _sync_owner()
	snapshot_count += 1
	var acknowledgements: Array = state.get("input_sequences", [])
	if my_seat >= 0 and my_seat < acknowledgements.size():
		var acknowledged := int(acknowledgements[my_seat])
		if input_sent_at.has(acknowledged):
			var measured := float(Time.get_ticks_msec() - int(input_sent_at[acknowledged]))
			input_echo_msec = measured if input_echo_msec == 0.0 else lerpf(input_echo_msec, measured, .15)
			for sent: int in input_sent_at.keys():
				if sent <= acknowledged: input_sent_at.erase(sent)

func _snapshot_stalled() -> bool:
	return joined and snapshot_silence >= 3.0

func _refresh_snapshot_status() -> void:
	var stalled := _snapshot_stalled()
	if stalled != snapshot_stall_visible:
		print("GW_SNAPSHOT_STALL visible=", stalled, " tick=", last_snapshot_tick)
		if not stalled and ui_state == "loading": _sync_phase_ui(true)
	snapshot_stall_visible = stalled
	if stalled: _loading("SERVER UPDATES ARE DELAYED", "Waiting for the connection…", true, 5)

const PARTNER_GRACE := 30.0 ## summer.build.json reconnect grace: the server waits this long before "A player left."
var partner_banner: Label
var partner_wait_since_msec := -1

## The authority pauses the round while a roster player is disconnected. Say so, instead of a
## silently frozen world.
func _refresh_partner_banner() -> void:
	var waiting := joined and ui_state == "round" and bool(latest_snapshot.get("waiting_for_partner", false))
	if not waiting:
		partner_wait_since_msec = -1
		if partner_banner != null: partner_banner.visible = false
		return
	if partner_wait_since_msec < 0:
		partner_wait_since_msec = Time.get_ticks_msec()
		print("GW_CLIENT_PARTNER_WAIT seat=", my_seat)
	if partner_banner == null:
		var layer := CanvasLayer.new()
		layer.layer = 31
		add_child(layer)
		partner_banner = Ui.heading("", 30, Ui.WHITE)
		partner_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		partner_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preload("res://client/hud_comic.gd").style_label(partner_banner, 24) # white on the HUD's dark chip
		partner_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		partner_banner.offset_left = -480.0
		partner_banner.offset_right = 480.0
		partner_banner.offset_top = 90.0
		partner_banner.offset_bottom = 190.0
		layer.add_child(partner_banner)
	var left := maxf(PARTNER_GRACE - (Time.get_ticks_msec() - partner_wait_since_msec) * 0.001, 0.0)
	partner_banner.text = "A PLAYER DISCONNECTED\nWaiting for them to come back · %d s" % ceili(left)
	partner_banner.visible = true

# ------------------------------------------------------------------ lobby / round / results

## Slot mapping (slot = position in the round) and the phase come with every snapshot.
func _apply_match(info: Dictionary) -> void:
	var previous := phase
	match_info = info
	phase = str(info.get("phase", ""))
	_apply_slots(info.get("slots", []), info)
	var ready_mask := int(info.get("ready", info.get("joined", 0)))
	var loading_mask := int(info.get("joined", 0)) & ~ready_mask # joined, client not in the world yet
	if ready_mask != peer_ready_mask or loading_mask != peer_loading_mask:
		for seat in seat_count:
			if seat == my_seat: continue
			if (loading_mask >> seat) & 1 == 1 and (peer_loading_mask >> seat) & 1 == 0: print("GW_PEER_LOADING seat=", seat, " me=", my_seat)
			elif (ready_mask >> seat) & 1 == 1 and (peer_ready_mask >> seat) & 1 == 0: print("GW_PEER_READY seat=", seat, " me=", my_seat)
		peer_ready_mask = ready_mask
		peer_loading_mask = loading_mask
		_refresh_name_tags(info)
	if phase != previous:
		print("GW_CLIENT_PHASE seat=", my_seat, " ", previous, " -> ", phase, " round=", info.get("round", 0), " mode=", info.get("mode", ""))
		_sync_phase_ui(true)

func _seat_color(seat: int) -> Color:
	return MatchPresenter.seat_color(seat)

func _apply_slots(list: Array, info: Dictionary) -> void:
	if list == slot_seats: return
	slot_seats = list.duplicate()
	seat_slot.clear()
	for slot in slot_seats.size():
		if int(slot_seats[slot]) >= 0: seat_slot[int(slot_seats[slot])] = slot
	var new_slot := int(seat_slot.get(my_seat, -1))
	# A different slot for anyone invalidates the owner courier, the remote couriers and their queues;
	# the next baseline recreates them (a new epoch always comes with a slot change).
	_dispose_workers()
	my_slot = new_slot
	if my_slot >= 0 and simulation != null:
		simulation.set_local_seat(my_slot)
		name_tags.set_local_slot(my_slot)
	_refresh_name_tags(info)
	for seat: int in relay_groups: # re-attach the relay groups to their new slots
		_relay_installed(relay_groups[seat].get_state(), -1, true, seat, relay_groups[seat])
	print("GW_CLIENT_SLOTS seat=", my_seat, " slot=", my_slot, " slots=", slot_seats)

## Seats whose client is in the world (the authority's `match.ready`: its first owner pose was accepted) are drawn
## normally; a seat that is joined but still loading is a hidden pawn with a "NAME · LOADING" tag until then.
func _seat_loading(seat: int) -> bool:
	return seat >= 0 and seat != my_seat and (peer_ready_mask >> seat) & 1 == 0

func _refresh_name_tags(info: Dictionary) -> void:
	var names: Array = info.get("names", [])
	var entries := []
	for slot in simulation.carrier_count:
		var seat := int(slot_seats[slot]) if slot < slot_seats.size() else -1
		if seat < 0:
			entries.append({})
			continue
		simulation.set_slot_tint(slot, seat)
		var shown_name := str(names[seat]) if seat < names.size() else ""
		if _seat_loading(seat): shown_name = (shown_name if shown_name != "" else "Player") + " · LOADING"
		entries.append({"name": shown_name, "color": _seat_color(seat), "visible": true, "title": TeamCast.player(seat).title})
	name_tags.set_slots(entries)

## A loading seat's courier stays hidden (the authority has no pose from it yet: it would stand at the yard spot, still,
## looking present) until its client reports in; every other seat follows the snapshot's active flags.
func _sync_loading_peers() -> void:
	for slot in slot_seats.size():
		var seat := int(slot_seats[slot])
		if seat < 0 or seat == my_seat: continue
		simulation.set_peer_hidden(slot, _seat_loading(seat))

func _lobby_model() -> Dictionary:
	return MatchPresenter.lobby_model(match_info, seat_count, my_seat, false, MatchPresenter.input_kind(get_tree()))

func _results_model() -> Dictionary:
	return MatchPresenter.results_model(match_info, my_seat)

## Shows the screen of the current phase; `enter` is true when the phase just changed.
func _sync_phase_ui(enter: bool) -> void:
	# Phase-owned props must switch with the snapshot, even before the next render frame.
	if walk_in_markers != null: walk_in_markers.set_shown(joined and phase == "lobby")
	if not joined: return
	if phase != "round": _hide_round_hud()
	match phase:
		"lobby":
			if enter:
				screens.hide_results()
				screens.hide_lobby()
				hud.visible = false
				chose = ""
			ui_state = "lobby"
			var model := _lobby_model()
			if enter or screens.current() != "lobby": screens.show_lobby(model)
			else: screens.update_lobby(model)
		"round":
			if enter:
				screens.hide_all()
				chose = ""
			ui_state = "round"
			hud.visible = true
		"results":
			if enter:
				results_dead_end_msec = -1
				screens.hide_lobby()
				hud.visible = false
				current_input = Game.neutral_input(current_input)
				if my_seat in (match_info.get("excluded", []) as Array):
					print("GW_CLIENT_EXCLUDED seat=", my_seat)
			ui_state = "results"
			var results := _results_model()
			if int(results.remaining) < 2 and chose == "" and results_dead_end_msec < 0: results_dead_end_msec = Time.get_ticks_msec()
			if results_dead_end_msec >= 0 and chose == "" and Time.get_ticks_msec() - results_dead_end_msec > 1500:
				_choose.call_deferred("menu") # fewer than 2 can play again: only the Main Menu path is left
			if enter or screens.current() != "results": screens.show_results(results)
			else: screens.update_results(results)
		"ended":
			if enter:
				screens.hide_all()
				ui_state = "ended"
				ended_notice_msec = Time.get_ticks_msec()
				screens.show_loading("MATCH OVER", "Closing the lobby…", false)

## Dev runs (--bot / --autoplay) press no buttons: in the lobby their owner walks onto
## the default course's pad (--course=challenge picks Challenge; `--pick=<circle id>`, e.g. r25, any circle of the show),
## the same physical start a player makes.
func _auto_walk() -> bool:
	return bot_number > 0 or "--autoplay" in DevEnv.user_args()

## The circle a dev run walks onto: `--pick=<id>` or the default course's.
func _auto_pad() -> String:
	for arg in DevEnv.user_args():
		if arg.begins_with("--pick="): return arg.trim_prefix("--pick=")
	return CourseSection.default_course()

## A minigame round (match.minigame_id, docs/modes.md): its view in the world and its HUD over the game, built when the round
## starts and freed when it ends; the round HUD of the level game stays hidden.
func _present_minigame(dt: float) -> void:
	var id := str(match_info.get("minigame_id", "")) if ui_state == "round" and phase == "round" else ""
	if mode_view != null and not is_instance_valid(mode_view): mode_view = null
	if id != mode_view_id or (id != "" and mode_view == null):
		if mode_view != null: mode_view.queue_free()
		mode_view = null
		mode_view_id = id
		if mode_hud != null: mode_hud.show_model({})
		if id != "" and simulation != null:
			var seats := []
			for seat: Variant in slot_seats:
				if int(seat) < 0: break
				seats.append(int(seat))
			mode_view = ModeViews.new_view(id)
			if mode_view != null:
				mode_view.name = "ModeView"
				simulation.world.add_child(mode_view)
				mode_view.setup(simulation, seats, my_slot)
				if mode_hud == null:
					mode_hud = ModeHud.new()
					add_child(mode_hud)
				mode_hud.seats = seats
				print("GW_MODE_VIEW id=", id, " seat=", my_seat, " slot=", my_slot)
	if name_tags != null: name_tags.visible = not (mode_view != null and mode_view.hide_name_tags)
	if mode_view == null: return
	var state: Variant = match_info.get("minigame", {})
	var model: Dictionary = state if state is Dictionary else {}
	mode_view.present(model, dt)
	hud.visible = false
	mode_hud.show_model(mode_view.hud(model))

## The TANDEM experiment (docs/party-show.md "Tandem (experiment)"): the pairs the authority fused, their hands, pops and banner; nothing while `match.tandem` is absent (it is off, or nothing may fuse now).
func _present_tandem(dt: float) -> void:
	if simulation == null or simulation.world == null: return
	if tandem_view != null and not is_instance_valid(tandem_view): tandem_view = null
	if tandem_view == null:
		tandem_view = TandemView.new()
		simulation.world.add_child(tandem_view)
		tandem_view.setup(simulation, my_slot, slot_seats)
	tandem_view.set_viewer(my_slot, slot_seats)
	var state: Variant = match_info.get("tandem", {})
	tandem_view.present(state if state is Dictionary else {}, dt)

## The lobby's pads follow the phase: drawn and updated in the lobby only.
func _present_walk_in() -> void:
	if walk_in_markers == null: return
	var shown: bool = joined and phase == "lobby" and ui_state == "lobby" and my_slot >= 0 and simulation != null and my_slot < simulation.actors.size()
	walk_in_markers.set_shown(shown)
	var model := _lobby_model() if shown else {}
	if shown: walk_in_markers.present(model, simulation.actors[my_slot].position)
	var touch: Variant = simulation.get("touch") if simulation != null else null
	if touch != null: touch.set_optional("play", shown and bool(model.get("can_play", false))) # a phone has no Enter: the shared circle shows a PLAY button

func _choose(choice: String) -> void:
	if phase != "results" or chose != "": return
	chose = choice
	var answer := await _command({"c": "choose", "v": choice})
	if not answer.get("ok", false):
		chose = ""
		print("GW_CHOOSE_REFUSED ", answer.get("error", ""))
		return
	if choice == "menu":
		await _back_to_menu()

func _watch_baseline() -> void:
	# A client whose epoch has no full baseline asks for another burst (after a dropped burst).
	if not joined or latest_snapshot.is_empty(): return
	if int(baseline_state.get("epoch", -1)) == int(latest_snapshot.get("resets", -2)): return
	if Time.get_ticks_msec() - baseline_asked_msec < BASELINE_WAIT_MSEC: return
	baseline_asked_msec = Time.get_ticks_msec()
	_command({"c": "baseline_resync"})

# ------------------------------------------------------------------ per frame

func _route_overview_open() -> bool:
	if not is_instance_valid(simulation): return false
	var world: Variant = simulation.get("world")
	if not world is Node or not is_instance_valid(world): return false
	return bool(world.get_meta("blockout_overview",false)) or bool(world.get_meta("wardrobe_open",false)) # the lobby wardrobe covers the game too

func _process(dt: float) -> void:
	if private_qa.enabled: private_qa.observe_connection(self)
	_sync_background_build()
	_sync_main_menu()
	if ui_state == "ended" and ended_notice_msec >= 0 and Time.get_ticks_msec() - ended_notice_msec > 6000:
		ended_notice_msec = -1
		_back_to_menu()
		return
	_present_walk_in()
	_refresh_partner_banner() # also while not joined: leaving the match must take the banner down
	if not joined or simulation == null or not simulation.is_network_ready(): return
	connected_seconds += dt
	if not world_entered and not ready_timed_out and connected_seconds > READY_TIMEOUT:
		# Hard cap on "joined but not in the world yet": a client that cannot finish (stuck baseline, frozen rig setup)
		# leaves with an error page instead of showing JOINING forever and holding the partner in a lobby with a ghost.
		ready_timed_out = true
		print("GW_READY_TIMEOUT seat=", my_seat, " sync_fail=", sync_fail, " snapshots=", snapshot_count)
		_fail_join_after_leave.call_deferred("Your match did not finish loading (%s). Your partner was told." % (sync_fail if sync_fail != "" else "no server state"), false, join_attempt)
	if not latest_snapshot.is_empty():
		_sync_owner()
		simulation.apply_network_state(latest_snapshot, dt)
		_sync_loading_peers()
		_watch_baseline()
		if DevEnv.is_dev() and ui_state == "loading" and int(connected_seconds * 0.5) != int((connected_seconds - dt) * 0.5): print("GW_CLIENT_WAIT seat=", my_seat, " slot=", my_slot, " phase=", phase, " sync_fail=", sync_fail, " courier=", owner_courier != null)
		if ui_state == "loading" and phase != "" and owner_courier != null and owner_courier.configured:
			world_entered = true
			print("GW_CLIENT_READY seat=", my_seat, " phase=", phase, " t=", snappedf(connected_seconds, 0.01))
			_flow("lobby_ready phase=" + phase)
			_sync_phase_ui(true)
		elif ui_state in ["lobby", "results"]: _sync_phase_ui(false)
		if ui_state == "round":
			hud.visible = true
			hud.simulation = simulation
			hud.update_from_state(latest_snapshot)
		_present_minigame(dt)
		_present_tandem(dt)
		if level_hud != null: level_hud.update(_run_model() if ui_state == "round" else {}, float(latest_snapshot.get("elapsed_seconds", 0.0)))
	# A transport disconnect can arrive much later than a stalled snapshot stream.
	# Keep the Session/World intact, show the delay, and use the existing neutral
	# input path until a valid snapshot arrives or the SDK confirms disconnection.
	if snapshot_silence >= 0.0: snapshot_silence += minf(dt, 0.1)
	_refresh_snapshot_status()
	var paused: bool = menus.pause_open or _screens_block() or _route_overview_open()
	simulation.set_camera_input_enabled(not paused)
	if paused:
		# Keep publishing neutral input so the authority immediately stops this
		# seat. The partner and shared world continue; no stale movement TTL wait.
		# Marked away: a walk-in countdown never runs under a menu or overlay.
		current_input = Game.away_input(current_input)
	if private_qa.enabled: private_qa.observe(self)
	send_time += dt
	if send_time >= OWNER_SEND_PERIOD:
		_publish_input()
	stats_time += dt
	if stats_time >= 5.0:
		stats_time = 0.0
		if DevEnv.is_dev(): print("GW_CLIENT_STATE seat=", my_seat, " slot=", my_slot, " phase=", phase, " snapshots=", snapshot_count, " tick=", latest_snapshot.get("tick", -1), " input_seq=", sequence, " input_receipt_echo_ms=", input_echo_msec, " fps=", Engine.get_frames_per_second(), " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

func _unhandled_key_input(event: InputEvent) -> void:
	# R restarts the delivery inside a round (shared command, never while a screen is up).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and phase == "round" and not _screens_block() and not menus.pause_open:
		_command({"c": "restart"})
	# Enter starts the walk-in countdown when everybody stands on one circle (the authority checks it).
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and phase == "lobby" and not _screens_block() and not menus.pause_open:
		_command({"c": "play"})

func _publish_input() -> void:
	if not joined: return
	if input_group == null: input_group=spawner.get_state_group(Game.INPUT,Game.input_key(my_seat))
	if input_group == null or not input_group.is_active(): return
	sequence+=1
	current_input.seq=sequence
	current_input.erase("owner_pose")
	var live: bool = simulation.is_slot_active(my_slot) # a courier that is out of the round sends no pose
	var synced := owner_courier != null and _sync_owner()
	if synced and live:
		var pose: Dictionary = owner_courier.capture_pose()
		owner_sequence += 1
		pose["version"] = OwnerPoseWire.VERSION # Wire keys are String; dot insertion creates StringName.
		pose["seq"] = owner_sequence
		pose["time"] = float(Time.get_ticks_usec()) * .000001
		pose["floor_normal"] = owner_courier.motion.floor_normal
		var bytes := OwnerPoseWire.encode(pose)
		if not bytes.is_empty(): current_input.owner_pose = bytes
		else:
			# Never silent: without a pose the authority stops relaying and deriving this seat.
			pose_encode_failures += 1
			if pose_encode_failures == 1 or pose_encode_failures % 300 == 0: push_error("GW_OWNER_POSE_ENCODE_FAILED seat=%d count=%d" % [my_seat, pose_encode_failures])
	input_sent_at[sequence]=Time.get_ticks_msec()
	if input_sent_at.size()>300: input_sent_at.erase(sequence-300)
	input_group.submit(Game.pack(current_input))
	send_time=0.0

func _sample_physics_input(delta: float, paused: bool) -> void:
	# Sample once immediately before owner movement, never once more in _process.
	# A blocked frame drops the edges that were pressed under the menu.
	if paused:
		current_input = Game.away_input(current_input)
		simulation.collect_owner_input()
		return
	current_input = simulation.collect_owner_input()
	var jumps := int(current_input.get("jumps", 0))
	jump_presses += jumps
	if not simulation.hold_yaw is float: # the show's podium holds everybody still: no grab, no slap
		grab_presses += int(current_input.get("grabs", 0))
		slap_presses += int(current_input.get("slaps", 0))
		item_presses += int(current_input.get("items", 0))
		if int(current_input.get("tests", 0)) > 0: item_tests = ((item_tests >> 3) + 1) << 3 | int(current_input.tests)
	current_input.erase("jumps")
	current_input.erase("grabs")
	current_input.erase("slaps")
	current_input.erase("items")
	current_input.erase("tests")
	var dashes := int(current_input.get("dashes", 0)) # the owner's own physics: only the press reaches the courier, the pose carries the rest
	current_input.erase("dashes")
	current_input.erase("restart") # Restart is the R command, never part of the pose stream.
	if private_qa.enabled:
		current_input = private_qa.next_input(latest_snapshot,delta,my_seat,input_echo_msec*.001)
	elif bot_number > 0: _bot_input()
	elif probe != null and phase == "round" and my_slot >= 0: current_input.move = probe.call("round_move", delta)
	if phase == "lobby" and _auto_walk() and connected_seconds > 2.0 and my_slot >= 0:
		current_input.move = WalkInLobby.steer(simulation.actors[my_slot].position, _auto_pad())
		if str(match_info.get("ready_pad", "")) != "" and str(match_info.get("pick", "")) == "" and Engine.get_physics_frames() % 60 == 0: _command({"c": "play"}) # bots press PLAY
	var moving: Variant = current_input.get("move", Vector2.ZERO)
	if moving is Vector2: current_input.move = [moving.x, moving.y]
	current_input.jump_seq = jump_presses
	current_input.grab_seq = grab_presses
	current_input.slap_seq = slap_presses
	current_input.item_seq = item_presses
	current_input.test_seq = item_tests
	# One press = one jump: the press edge reaches the owner courier (its 0.15 s buffer lets one press just before landing count once).
	if owner_courier != null:
		for _press in jumps: owner_courier.jump_edge()
		for _press in dashes: owner_courier.dash_edge()
	owner_move = Vector2(float(current_input.move[0]), float(current_input.move[1]))

func _physics_process(delta: float) -> void:
	if not joined or simulation == null or not simulation.is_network_ready(): return
	var owner_ready := _sync_owner()
	_step_remote_couriers()
	if not owner_ready: return
	var paused: bool = menus.pause_open or _screens_block() or _snapshot_stalled() or _route_overview_open()
	_sample_physics_input(delta,paused)
	if owner_courier != null:
		# The jump sound follows the capsule actually leaving the ground, not every key edge (the shell plays it).
		simulation.owner_step({"move": owner_move},not paused,delta)

func _bot_input() -> void:
	# Basic stop/move probe for --bot=<n> clients.
	current_input = {"move": [0, 0], "height": 0.0, "roll": 0.0, "facing": 0.0}
	if connected_seconds > 3.0 and connected_seconds < 5.0:
		current_input.move = [0, -1]

# ------------------------------------------------------------------ owner / remote couriers

func _dispose_workers() -> void:
	if owner_courier != null: owner_courier.dispose()
	owner_courier = null
	if simulation != null:
		simulation.owner_courier = null
		simulation.invalidate_baseline()
	owner_grant = -1
	remote_couriers.clear()
	relay_pending.clear()
	relay_grants.clear()
	relay_revisions.clear()

func _owner_identity() -> Dictionary:
	if my_seat < 0 or my_seat >= seat_count or input_group == null or not input_group.is_active() or not input_group.is_local_writer(): return {}
	var context: SummerClientContext = Summer.client.context
	if context.world == null or context.session == null or admitted_mode_binding.get("world_id") != context.world.world_id: return {}
	var timing := input_group.get_timing()
	if timing == null or timing.lifetime_revision < 1: return {}
	for entity_id: int in spawner.get_entity_ids():
		var entity := spawner.get_entity(entity_id)
		if entity != null and entity.session == context.session:
			return {"world_id":context.world.world_id,"session_id":context.session.session_id,"entity_id":entity_id,"lifetime_revision":timing.lifetime_revision}
	return {}

func _sync_owner() -> bool:
	sync_fail = ""
	if connected_seconds < _dev_delay("--dev-ready-delay="):
		sync_fail = "dev_ready_delay"
		return false
	if simulation == null or admitted_mode_binding.is_empty() or latest_snapshot.is_empty():
		sync_fail = "no_sim_or_binding_or_snapshot"
		return false
	if my_slot < 0:
		sync_fail = "no_slot"
		return false
	if input_group == null: input_group = spawner.get_state_group(Game.INPUT,Game.input_key(my_seat))
	var identity := _owner_identity()
	if identity.is_empty():
		if owner_courier != null: owner_courier.active = false
		sync_fail = "identity"
		return false
	var epoch: int = latest_snapshot.get("resets",-1)
	var players: Array = latest_snapshot.get("players",[])
	if epoch < 1 or players.size()!=seat_count or my_slot >= players.size():
		sync_fail = "snapshot_players"
		return false
	var benched: bool = bool(players[my_slot].get("inactive", false)) # out of the round (the show's eliminated): no baseline, the courier stays where it is
	if not benched and not players[my_slot].get("movement") is Dictionary:
		sync_fail = "snapshot_players"
		return false
	var grant: int = input_group.get_timing().grant_revision
	if owner_courier != null and identity != owner_courier.lifetime:
		owner_courier.dispose()
		owner_courier = null
		simulation.owner_courier = null
	var grants: Variant = latest_snapshot.get("owner_grants")
	if not grants is Array or grants.size()!=seat_count or not grants[my_seat] is int or grants[my_seat]!=grant:
		# Input and shared snapshot are independent State streams. Wait for the
		# authority's matching grant in either delivery order, without reseeding.
		if owner_courier != null: owner_courier.active = false
		sync_fail = "grant_%s_vs_%d" % [str(grants[my_seat]) if grants is Array and grants.size()==seat_count else "?", grant]
		return false
	if not simulation.seed_baseline(latest_snapshot):
		sync_fail = "seed_baseline"
		return false
	var baseline := {"position": simulation.actors[my_slot].position, "yaw": simulation.motion_yaw(my_slot)} if benched else {"position": players[my_slot].position, "yaw": players[my_slot].movement.yaw}
	if owner_courier == null:
		var helper := OwnerCourier.new()
		if not helper.configure(simulation,my_slot,identity,epoch,baseline):
			sync_fail = "configure"
			return false
		owner_courier = helper
		simulation.owner_courier = helper
	elif epoch > owner_courier.reset_epoch and not benched:
		if not owner_courier.reset_from_authority(identity,epoch,baseline):
			sync_fail = "reset_from_authority"
			return false
	owner_grant = grant
	if not owner_courier.observe_shared(identity,latest_snapshot):
		sync_fail = "observe_shared"
		return false
	for seat: int in remote_couriers:
		remote_couriers[seat].reset(epoch)
	return true

func _attach_relay_group(group: SummerNetworkStateGroup) -> void:
	var key := str(group.get_key())
	if not key.begins_with("p"): return
	var seat := int(key.substr(1))
	if seat < 0 or seat >= seat_count or relay_groups.get(seat) == group: return
	relay_groups[seat] = group
	remote_couriers.erase(seat)
	relay_grants.erase(seat)
	relay_revisions.erase(seat)
	_relay_installed(group.get_state(),group.get_revision(),true,seat,group)
	group.state_installed.connect(_relay_installed.bind(seat,group))

func _relay_installed(fields: Dictionary, revision: int, _reset: bool, seat: int, group: SummerNetworkStateGroup) -> void:
	if simulation == null or not group.is_active() or relay_groups.get(seat)!=group: return
	var timing := group.get_timing()
	if timing == null: return
	var grant: int = timing.grant_revision
	if relay_grants.get(seat,-1) != grant:
		remote_couriers.erase(seat)
		relay_pending.erase(seat)
		relay_revisions.erase(seat)
		relay_grants[seat] = grant
	if revision >= 0:
		if revision <= int(relay_revisions.get(seat,-1)): return
		relay_revisions[seat] = revision
	var pose := OwnerPoseWire.decode(fields.get("b",PackedByteArray()))
	if pose.is_empty(): return
	if seat == my_seat:
		owner_echoes += 1 # Deliberately zero own transform/velocity writes.
		return
	var arrival := float(Time.get_ticks_usec()) * .000001
	if owner_courier != null and owner_courier.reset_epoch == pose.reset_epoch and remote_couriers.has(seat) and remote_couriers[seat].epoch == pose.reset_epoch and (relay_pending.get(seat,[]) as Array).is_empty():
		remote_couriers[seat].receive(pose,arrival)
	else:
		# Preserve each installation/arrival before baseline readiness.
		# The bounded queue is an adapter; never coalesce clock samples ourselves.
		var pending: Array = relay_pending.get(seat,[])
		pending.append({"pose":pose,"arrival":arrival})
		if pending.size()>120: pending.pop_front()
		relay_pending[seat] = pending

## Players in the World (match.joined): the authority thins the relay with it (Game.relay_every).
func _world_players() -> int:
	var mask := int(match_info.get("joined", 0))
	var players := 0
	for seat in seat_count: players += (mask >> seat) & 1
	return players

func _step_remote_couriers() -> void:
	if owner_courier == null: return
	var epoch: int = owner_courier.reset_epoch
	var now := float(Time.get_ticks_usec()) * .000001
	var back_time := RemoteCourier.BACK_TIME * Game.relay_every(_world_players())
	for seat: int in relay_groups:
		if seat == my_seat or not relay_groups[seat].is_active(): continue
		var slot := int(seat_slot.get(seat, -1))
		if slot < 0: continue
		if not remote_couriers.has(seat):
			var remote := RemoteCourier.new()
			remote.reset(epoch)
			remote_couriers[seat] = remote
		var remote: RefCounted = remote_couriers[seat]
		remote.back_time = back_time
		var pending: Array = relay_pending.get(seat,[])
		var future: Array = []
		for entry: Dictionary in pending:
			if int(entry.pose.reset_epoch)==epoch: remote.receive(entry.pose,float(entry.arrival))
			elif int(entry.pose.reset_epoch)>epoch: future.append(entry)
		if future.is_empty(): relay_pending.erase(seat)
		else: relay_pending[seat] = future
		var pose: Dictionary = remote.sample(now,{"transform":simulation.actors[slot].transform})
		if not pose.is_empty(): simulation.apply_remote_pose(slot,pose)
