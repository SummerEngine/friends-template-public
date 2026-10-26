extends SceneTree
## Headless check of the minigame framework (docs/modes.md): the registry, the cast's mode, the lobby circle, and that every
## minigame's rules play 30 s with three scripted players (standing, then walking about) without errors and with a small state,
## and that its view builds and presents under a stub shell.
## Prints MODE_FRAMEWORK_CHECK ok=<bool> last; exits 1 on a failure.
const Modes := preload("res://modes/modes.gd")
const ModeViews := preload("res://modes/mode_views.gd")
const ModeHud := preload("res://modes/mode_hud.gd")
const TeamCast := preload("res://style/team_cast.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
## The helpers next to this script (tools/ is outside the project: loaded by file path).
var FakeHost: GDScript
var StubRun: GDScript

var failures := 0

func expect(label: String, ok: bool, detail := "") -> void:
	if not ok: failures += 1
	print("MODE_FRAMEWORK_CHECK ", "ok  " if ok else "FAIL", " ", label, " ", detail)

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void: # a script error stops _run: never hang the guard
		print("MODE_FRAMEWORK_CHECK FAIL timed out")
		print("MODE_FRAMEWORK_CHECK ok=false")
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	FakeHost = load(here + "/fake_host.gd")
	StubRun = load(here + "/stub_run.gd")
	var ids: Array = Modes.ids()
	var minigames := ids.filter(func(id: String) -> bool: return Modes.is_minigame(id))
	expect("modes.json lists carry and the five minigames", ids.has("carry") and minigames.size() == 5, str(ids))
	expect("every minigame has rules and a view", minigames.all(func(id: String) -> bool: return Modes.RULES.has(id) and ModeViews.VIEWS.has(id)), str(Modes.RULES.keys()))
	minigames = minigames.filter(func(id: String) -> bool: return id != "show") # the show plays level rounds: tools/modes/show_check.gd
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Modes"}, "players": [{"name": "Ida"}], "mode": "nope"})
	expect("an unknown mode is carry", Modes.current() == "carry")
	for id: String in minigames:
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "Modes"}, "players": [{"name": "Maya", "catchphrase": "Ship it!"},
			{"name": "Theo", "catchphrase": "On my way!"}, {"name": "Ida", "catchphrase": "Coffee first"}], "mode": id,
			"obstacles": [{"label": "FLAKY CI"}, {"label": "CHAT PINGS"}], "eggs": ["Someone always says it's a quick one"]})
		var pads := WalkInLobby.shown_pads()
		expect("%s: the lobby shows one circle with its title" % id, pads.size() == 1 and str(pads[0].title) == str(Modes.info(id).title), str(pads))
		var host = FakeHost.new([0, 1, 2], 7)
		var rules = Modes.new_rules(id)
		rules.start(host)
		var biggest := 0
		var states: Array = []
		for tick in 60 * 30:
			if tick > 120:
				for slot in 3: host.walk(slot, host.yard_center() + Vector3(sin(tick * 0.01 + slot) * 4.0, 0.0, cos(tick * 0.013 + slot * 2.0) * 4.0), 4.0 / 60.0)
			rules.tick(1.0 / 60.0)
			if tick % 30 == 0:
				var state: Dictionary = rules.state()
				biggest = maxi(biggest, var_to_bytes(state).size())
				states.append(state)
			if rules.finished(): break
		expect("%s: 30 s of rules, state under 8 KB" % id, biggest < 8192, "largest %d B" % biggest)
		var stub = StubRun.new()
		root.add_child(stub)
		stub.make(3, false)
		var view: Node3D = ModeViews.new_view(id)
		stub.world.add_child(view)
		view.setup(stub, [0, 1, 2], 0)
		var hud = ModeHud.new()
		root.add_child(hud)
		hud.seats = [0, 1, 2]
		for state: Dictionary in states:
			view.present(state, 0.5)
			hud.show_model(view.hud(state))
		await process_frame
		expect("%s: the view builds and presents every state" % id, is_instance_valid(view))
		hud.queue_free()
		stub.queue_free()
		await process_frame
	TeamCast.override({})
	print("MODE_FRAMEWORK_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)
