extends SceneTree
## The touch path of the lobby's PLAY, on one machine under the touch layout. A phone has no Enter:
##   - on the lobby circle (TIME ATTACK, ENDLESS, the party show's THE SHOW or one of its rounds' circles) a big PLAY button shows while both players stand on it, and only then;
##   - a finger on it sends the same PLAY as Enter (the circle's countdown starts), a finger on empty floor does not;
##   - the prompt names the input: "Tap PLAY to start" on touch, "Press Enter to start" on a keyboard, "Press Y to start" on a pad.
## Run offscreen (never windowed), the touch layout on; --shots=<dir> saves a frame of the phone layout on a ready circle:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 300 <Summer> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s $PWD/tools/touch_play_check.gd -- --touch [--size=2400x1080] [--shots=<dir>]
## Prints TOUCH_PLAY lines and TOUCH_PLAY ok=<bool>; exits 1 on a failure.
class VirtualLocal extends "res://client/presentation_entry.gd":
	func connected_pads() -> Array: return []

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const TeamCast := preload("res://style/team_cast.gd")
const MatchPresenter := preload("res://client/match_presenter.gd")
const TouchControls := preload("res://client/touch_controls.gd")
var shots := ""
var failures := 0
var sim: Node
var flow: Node

func expect(label: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("TOUCH_PLAY %s %s %s" % ["ok  " if ok else "FAIL", label, detail])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
	create_timer(280.0).timeout.connect(func() -> void:
		print("TOUCH_PLAY FAIL timed out")
		print("TOUCH_PLAY ok=false")
		quit(1))
	_set_cast("time_attack")
	_run.call_deferred()

func _set_cast(run_id: String) -> void:
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["run"] = run_id
	cast["mode"] = "carry"
	TeamCast.override(cast)

## The party show's cast: THE SHOW's circle and a circle per round.
func _set_show_cast() -> void:
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["mode"] = "show"
	TeamCast.override(cast)

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func capture(name: String) -> void:
	if shots == "": return
	DirAccess.make_dir_recursive_absolute(shots)
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	print("TOUCH_PLAY shot ", name, " ", image.save_png("%s/%s.png" % [shots, name]) == OK, " ", image.get_size())

## A finger down (and up) at a point, pushed through the viewport like the OS does.
func finger(at: Vector2, index := 0, hold := 2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = index
		event.position = at
		event.pressed = pressed
		root.push_input(event, true) # positions are in canvas units: no window stretch to undo
		if pressed: await frames(hold)
	await frames(4)

func stand(course: String) -> void:
	var centre := WalkInLobby.center(course)
	sim.actors[0].position = centre + Vector3(-0.7, 0.3, 0.0)
	sim.actors[1].position = centre + Vector3(0.7, 0.3, 0.0)
	await frames(30)

func leave_pad() -> void:
	for slot in 2: sim.actors[slot].position = WalkInLobby.spawn(slot)
	await frames(30)

func run_circle(label: String, course: String, shot: String) -> void:
	var touch: Node = sim.touch
	await leave_pad()
	expect("%s: no PLAY button while nobody stands on the circle" % label, not touch.has_optional("play"))
	await stand(course)
	expect("%s: both players on it wait for PLAY" % label, flow.probe().ready == course and flow.probe().pick == "", str(flow.probe().zones))
	expect("%s: the PLAY button shows" % label, touch.has_optional("play") and touch.is_active())
	var box: Rect2 = touch.region_rect("play")
	var canvas := root.get_visible_rect().size
	expect("%s: the button is big and on the screen" % label, box.size.x >= 200.0 and box.size.y >= 100.0 and Rect2(Vector2.ZERO, canvas).encloses(box), str(box))
	var jump: Dictionary = touch.jump_circle()
	expect("%s: it does not cover JUMP" % label, not box.intersects(Rect2(jump.c - Vector2(jump.r, jump.r), Vector2(jump.r, jump.r) * 2.0)))
	expect("%s: it does not cover GRAB" % label, not box.intersects(touch.region_rect("grab")))
	expect("%s: the prompt says TAP" % label, flow._level_hud._note.text.ends_with("Tap PLAY to start"), flow._level_hud._note.text)
	if shot != "": capture(shot)
	await finger(box.position - Vector2(60.0, 0.0)) # empty floor next to the button
	expect("%s: a finger beside the button does not start the circle" % label, flow.probe().pick == "")
	await finger(box.get_center())
	expect("%s: a finger on PLAY starts the countdown" % label, flow.probe().pick == course, str(flow.probe().pick))
	expect("%s: the button is gone once the countdown runs" % label, not touch.has_optional("play"))
	flow._enter_lobby() # as "play again": the next circle needs its own PLAY

func _run() -> void:
	sim = VirtualLocal.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 180000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("TOUCH_PLAY FAIL boot_timeout")
			print("TOUCH_PLAY ok=false")
			quit(2)
			return
	var hud_script = load("res://client/hud.gd")
	for key in ["move", "jump", "tilt", "lift"]: hud_script.taught[key] = true
	var ui = sim.local_presentation
	ui.show_local_job()
	ui._input_mode_selected(2)
	await process_frame
	ui.start_job()
	await frames(90)
	flow = ui.level_flow
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="): # a phone, e.g. 2400x1080: the settings reset the window while the game boots, so it is set here
			var parts := a.trim_prefix("--size=").split("x")
			root.size = Vector2i(int(parts[0]), int(parts[1]))
			await frames(10)
	print("TOUCH_PLAY window ", root.size, " canvas ", root.get_visible_rect().size)
	expect("the touch layout is on", TouchControls.touch_ui() and sim.touch != null, "forced=%d" % TouchControls.forced())
	# the prompt names the input
	expect("prompt: touch", MatchPresenter.play_prompt("touch") == "Tap PLAY to start")
	expect("prompt: keyboard", MatchPresenter.play_prompt("keyboard") == "Press Enter to start")
	expect("prompt: pad", MatchPresenter.play_prompt("pad") == "Press Y to start")
	expect("input kind under the touch layout is touch", MatchPresenter.input_kind(self) == "touch")
	var course := WalkInLobby.shown_course()
	for input: String in ["touch", "keyboard", "pad"]:
		var ready := {"joined": 3, "ready": 3, "names": ["A", "B"], "zones": [course, course], "ready_pad": course, "start_in": -1.0, "pick": ""}
		var model := MatchPresenter.lobby_model(ready, 2, 0, false, input)
		expect("lobby model (%s): a ready circle I stand on can be played and says so" % input, bool(model.can_play) and model.hint == MatchPresenter.play_prompt(input), str(model.hint))
		ready.zones = ["", course]
		expect("lobby model (%s): standing elsewhere has nothing to play" % input, not bool(MatchPresenter.lobby_model(ready, 2, 0, false, input).can_play))
		ready.zones = [course, course]
		ready.start_in = 2.0
		expect("lobby model (%s): a running countdown has nothing to play" % input, not bool(MatchPresenter.lobby_model(ready, 2, 0, false, input).can_play))
	# the circle the cast's run shows: TIME ATTACK, then ENDLESS
	_set_cast("time_attack")
	await frames(10)
	expect("the TIME ATTACK circle is shown", WalkInLobby.shown_course() == CourseSection.ADVENTURE)
	await run_circle("TIME ATTACK", CourseSection.ADVENTURE, "phone-ready-time-attack")
	_set_cast("endless")
	await frames(10)
	expect("the ENDLESS circle is shown", WalkInLobby.shown_course() == CourseSection.CHALLENGE)
	await run_circle("ENDLESS", CourseSection.CHALLENGE, "phone-ready-endless")
	# the party show: one circle, THE SHOW; the same PLAY button starts it
	_set_show_cast()
	await frames(10)
	var shown: Array = WalkInLobby.shown_pads()
	expect("THE SHOW is the first circle shown, with a circle per round", shown.size() > 1 and str(shown[0].title).to_upper().contains("SHOW") and str(shown[0].course) == WalkInLobby.shown_course(), str(shown.map(func(pad) -> String: return str(pad.title))))
	await run_circle("THE SHOW", WalkInLobby.shown_course(), "phone-ready-show")
	for pad: Dictionary in shown.slice(1): # the same PLAY button on every round's circle (two players stand on it)
		await run_circle(str(pad.title), str(pad.course), "phone-ready-%s" % str(pad.course))
	print("TOUCH_PLAY ok=", failures == 0)
	quit(0 if failures == 0 else 1)
