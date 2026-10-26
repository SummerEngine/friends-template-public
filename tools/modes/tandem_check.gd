extends SceneTree
## EXPERIMENT TANDEM (docs/party-show.md "Tandem (experiment)"), the rules without a network: modes/show/shared/tandem/tandem.gd on a stub shell (positions, velocities, steering and the fling are set by the
## script). Checks: two runners alongside within 1.2 m fuse after 1.5 s, standing or far apart ones do not, the pair lasts 6 s and spins apart with a fling for both, nobody is flung when a
## tandem slips, the pair's cooldown is 10 s, a third runner cannot join, four runners make two pairs, a held or lost racer ends a tandem, the lobby and the race scopes, the cast's `off`, a lone
## player's buddy (it comes, runs beside the player, fuses, the player is flung, it spins away, comes again after the cooldown), the state stays small and plain, the cast's words.
## Headless: `tools/engine_slot.sh timeout -k 10 120 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --path demo -s "$PWD/tools/modes/tandem_check.gd"`; prints TANDEM_CHECK ok=<bool> last.
const Tandem := preload("res://modes/show/shared/tandem/tandem.gd")
const Config := preload("res://modes/show/shared/tandem/tandem_config.gd")
const TeamCast := preload("res://style/team_cast.gd")
const DT := 1.0 / 60.0

class Body extends RefCounted:
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO

class Team extends RefCounted:
	var held := {}
	func held_by(slot: int) -> int:
		return int(held.get(slot, -1))

class Shell extends RefCounted:
	var reset_count := 1
	var carrier_count := 4
	var actors: Array = []
	var team := Team.new()
	var active := [true, true, true, true]
	var steer := {}
	var flings: Array = [] ## [slot, impulse]
	func _init() -> void:
		for index in 4: actors.append(Body.new())
	func is_slot_active(slot: int) -> bool:
		return slot >= 0 and slot < active.size() and bool(active[slot])
	func intent(slot: int) -> Vector2:
		return steer.get(slot, Vector2.ZERO)
	func fling_courier(slot: int, impulse: Vector3) -> void:
		flings.append([slot, impulse])

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("TANDEM_CHECK ", "ok   " if ok else "FAIL ", label)

func _initialize() -> void:
	create_timer(100.0).timeout.connect(func() -> void:
		print("TANDEM_CHECK FAIL timed out")
		print("TANDEM_CHECK ok=false")
		quit(1))
	_run.call_deferred()

## `slots` run along +x at `speed`, side by side `gap` m apart in z, for `seconds`; returns the tandem.
func _run_together(tandem: RefCounted, shell: Shell, slots: Array, seconds: float, gap := 1.0, speed := 5.0, scope := "race", solo := false) -> void:
	for tick in int(seconds / DT):
		for index in slots.size():
			var body: Body = shell.actors[int(slots[index])]
			body.velocity = Vector3(speed, 0.0, 0.0)
			body.position += body.velocity * DT
			body.position.z = float(index) * gap
		tandem.tick(DT, scope, slots, solo)

func _fresh() -> Array:
	var shell := Shell.new()
	return [Tandem.new(shell), shell]

func _events(tandem: RefCounted, type: int) -> int:
	return (tandem.events as Array).filter(func(row: Array) -> bool: return int(row[1]) == type).size()

func _run() -> void:
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Tandem"}, "mode": "show", "players": [{"name": "Maya"}, {"name": "Theo"}, {"name": "Ida"}, {"name": "Kai"}]})
	Config.reset()
	check(Config.on("race") and Config.on("lobby") and not Config.on("tile") and not Config.on(""), "tandem.json is on for the race and the lobby, for nothing else")
	check(Config.tune("close") == 1.2 and Config.tune("hold") == 1.5 and Config.tune("duration") == 6.0 and Config.tune("speed") == 1.6 and Config.tune("cooldown") == 10.0, "the numbers are the brief's: 1.2 m, 1.5 s, 6 s, 1.6 x, 10 s")
	# ---------------------------------------------------------------- the fuse
	var made := _fresh()
	var tandem: RefCounted = made[0]
	var shell: Shell = made[1]
	_run_together(tandem, shell, [0, 1], 1.3)
	check(tandem.pairs.is_empty(), "1.3 s alongside is not enough")
	_run_together(tandem, shell, [0, 1], 0.4)
	check(tandem.pairs.size() == 1 and int(tandem.pairs[0].a) == 0 and int(tandem.pairs[0].b) == 1, "alongside for 1.5 s: fused (pairs %s)" % str(tandem.pairs))
	check(_events(tandem, Tandem.Event.FUSE) == 1, "one FUSE event")
	var row: Array = (tandem.state().pairs as Array)[0]
	check(row.size() == 9 and float(row[4]) == 6.0, "the state row carries ids, slots, age, duration and both steerings")
	# the steering the partners get: a's row has b's input
	shell.steer = {0: Vector2(1.0, 0.0), 1: Vector2(0.0, -1.0)}
	tandem.tick(DT, "race", [0, 1], false)
	row = (tandem.state().pairs as Array)[0]
	check(Vector2(row[5], row[6]).is_equal_approx(Vector2(1.0, 0.0)) and Vector2(row[7], row[8]).is_equal_approx(Vector2(0.0, -1.0)), "the pair row hands each machine the other's world steering")
	# ---------------------------------------------------------------- the exit
	_run_together(tandem, shell, [0, 1], 5.9)
	check(tandem.pairs.is_empty() and _events(tandem, Tandem.Event.END) == 1 and _events(tandem, Tandem.Event.SLIP) == 0, "after 6 s the tandem ends with END (not SLIP)")
	check(shell.flings.size() == 2, "both are flung")
	if shell.flings.size() == 2:
		var fa: Vector3 = shell.flings[0][1]
		var fb: Vector3 = shell.flings[1][1]
		check(fa.y > 0.0 and fb.y > 0.0 and fa.x * fb.x + fa.z * fb.z < 0.0 and Vector2(fa.x, fa.z).length() > 4.0, "they are thrown apart (opposite ways, with a lift): %s %s" % [fa, fb])
	# ---------------------------------------------------------------- the cooldown
	_run_together(tandem, shell, [0, 1], 8.0)
	check(tandem.pairs.is_empty(), "no new tandem within 10 s (8 s later)")
	_run_together(tandem, shell, [0, 1], 3.6)
	check(tandem.pairs.size() == 1, "the pair may fuse again after the cooldown and another 1.5 s alongside")
	# ---------------------------------------------------------------- who does not fuse
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	_run_together(tandem, shell, [0, 1], 4.0, 1.4)
	check(tandem.pairs.is_empty(), "1.4 m apart is too far")
	_run_together(tandem, shell, [0, 1], 4.0, 1.0, 0.8)
	check(tandem.pairs.is_empty(), "two who barely move do not fuse")
	_run_together(tandem, shell, [0, 1], 4.0, 1.0, 5.0, "")
	check(tandem.pairs.is_empty() and not tandem.active, "no scope (a card, a result): nothing fuses")
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Tandem"}, "mode": "show", "players": [{"name": "Maya"}, {"name": "Theo"}], "show": {"tandem": {"off": true}}})
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	_run_together(tandem, shell, [0, 1], 4.0)
	check(tandem.pairs.is_empty() and not tandem.active, "the cast's show.tandem.off switches it off")
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Tandem"}, "mode": "show", "players": [{"name": "Maya"}, {"name": "Theo"}, {"name": "Ida"}, {"name": "Kai"}]})
	# ---------------------------------------------------------------- crowds
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	for tick in 120:
		for slot in 3:
			var body: Body = shell.actors[slot]
			body.velocity = Vector3(5.0, 0.0, 0.0)
			body.position += body.velocity * DT
			body.position.z = float(slot) * 0.9
		tandem.tick(DT, "lobby", [0, 1, 2], false)
	check(tandem.pairs.size() == 1, "three runners abreast: one pair, the third cannot join (%s)" % str(tandem.pairs))
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	for tick in 120:
		for slot in 4:
			var body: Body = shell.actors[slot]
			body.velocity = Vector3(5.0, 0.0, 0.0)
			body.position += body.velocity * DT
			body.position.z = float(slot / 2) * 20.0 + float(slot % 2) * 1.0
		tandem.tick(DT, "race", [0, 1, 2, 3], false)
	check(tandem.pairs.size() == 2, "four runners in two couples: two pairs")
	# ---------------------------------------------------------------- ends that are not the full time
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	_run_together(tandem, shell, [0, 1], 1.6)
	check(tandem.pairs.size() == 1, "a pair to break")
	shell.team.held[1] = 0 # grabbed
	_run_together(tandem, shell, [0, 1], 0.1)
	check(tandem.pairs.is_empty() and _events(tandem, Tandem.Event.SLIP) == 1 and shell.flings.is_empty(), "a grabbed partner ends it quietly (SLIP, no fling)")
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	_run_together(tandem, shell, [0, 1], 1.6)
	for tick in 90: # one stays, the other runs on: they drift apart
		shell.actors[1].position.x += 5.0 * DT
		shell.actors[1].velocity = Vector3(5.0, 0, 0)
		shell.actors[0].velocity = Vector3(5.0, 0, 0)
		shell.actors[0].position.x += 1.0 * DT
		tandem.tick(DT, "race", [0, 1], false)
	check(tandem.pairs.is_empty() and _events(tandem, Tandem.Event.SLIP) == 1, "more than 3.4 m apart for 0.6 s: SLIP")
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	_run_together(tandem, shell, [0, 1], 1.6)
	_run_together(tandem, shell, [0], 0.1) # the other is no longer eligible (it crossed the goal / left)
	check(tandem.pairs.is_empty() and shell.flings.is_empty(), "a partner that may no longer fuse ends the pair, nobody is flung")
	_run_together(tandem, shell, [0, 1], 0.1, 1.0, 5.0, "lobby")
	_run_together(tandem, shell, [0, 1], 1.6, 1.0, 5.0, "lobby")
	check(tandem.pairs.is_empty(), "the end started a cooldown for that pair in the other scope too (same epoch)")
	shell.reset_count += 1 # a new round
	_run_together(tandem, shell, [0, 1], 1.7, 1.0, 5.0, "race")
	check(tandem.pairs.size() == 1, "a new round forgets cooldowns")
	# ---------------------------------------------------------------- the buddy
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	var fused_at := -1.0
	var buddy_seen := -1.0
	var phases := {}
	for tick in 60 * 15:
		var body: Body = shell.actors[0]
		body.velocity = Vector3(5.0, 0.0, 0.0)
		body.position += body.velocity * DT
		shell.steer = {0: Vector2(1.0, 0.0)}
		tandem.tick(DT, "race", [0], true)
		if not tandem.buddy.is_empty():
			phases[int(tandem.buddy.phase)] = true
			if buddy_seen < 0.0: buddy_seen = tandem.time
		if fused_at < 0.0 and not tandem.pairs.is_empty(): fused_at = tandem.time
	check(buddy_seen >= 1.9 and buddy_seen <= 2.2, "a lone runner gets a buddy after 2 s of running (%.2f s)" % buddy_seen)
	check(phases.has(Tandem.Phase.CHASE) and phases.has(Tandem.Phase.BESIDE) and phases.has(Tandem.Phase.FUSED) and phases.has(Tandem.Phase.FLUNG), "the buddy chases, runs beside, holds hands and is flung (%s)" % str(phases.keys()))
	check(fused_at > 5.0 and fused_at < 7.5, "the lone runner and the buddy fuse about 6 s in (%.2f s)" % fused_at)
	check(shell.flings.size() == 1 and int(shell.flings[0][0]) == 0, "at the end the player is flung once (%s)" % str(shell.flings.size()))
	check(_events(tandem, Tandem.Event.FUSE) == 1 and _events(tandem, Tandem.Event.END) == 1, "FUSE and END told once each")
	check(tandem.buddy.is_empty() or int(tandem.buddy.phase) != Tandem.Phase.FUSED, "the buddy is gone or spinning away after the tandem")
	var shown: Dictionary = tandem.state()
	check(var_to_bytes(shown).size() < 600, "the state is small (%d B)" % var_to_bytes(shown).size())
	# the buddy while fused: beside, 0.95 m
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	for tick in 60 * 8:
		var body: Body = shell.actors[0]
		body.velocity = Vector3(5.0, 0.0, 0.0)
		body.position += body.velocity * DT
		tandem.tick(DT, "lobby", [0], true)
		if not tandem.pairs.is_empty(): break
	var gap: float = Vector2(tandem.buddy.pos.x - shell.actors[0].position.x, tandem.buddy.pos.z - shell.actors[0].position.z).length() if not tandem.buddy.is_empty() else -1.0
	check(not tandem.pairs.is_empty() and int((tandem.pairs[0] as Dictionary).b) == Tandem.BUDDY and gap > 0.5 and gap < 1.25, "in the lobby too: the buddy holds the player's hand beside it (%.2f m)" % gap)
	var wait := Tandem.new(shell)
	wait.tick(DT, "lobby", [0], false)
	check(wait.buddy.is_empty(), "with company (not solo) no buddy comes")
	# a runner who stops: the buddy leaves
	made = _fresh()
	tandem = made[0]
	shell = made[1]
	for tick in 60 * 5:
		var body: Body = shell.actors[0]
		body.velocity = Vector3(5.0, 0.0, 0.0)
		body.position += body.velocity * DT
		tandem.tick(DT, "race", [0], true)
		if not tandem.buddy.is_empty() and int(tandem.buddy.phase) == Tandem.Phase.BESIDE: break
	check(not tandem.buddy.is_empty(), "a buddy is beside the runner")
	shell.actors[0].velocity = Vector3.ZERO
	for tick in 60 * 5: tandem.tick(DT, "race", [0], true)
	check(tandem.buddy.is_empty() and _events(tandem, Tandem.Event.BUDDY_OUT) == 1, "the runner stopped: the buddy leaves after 4 s")
	# ---------------------------------------------------------------- the cast's words
	check(Config.text("banner") == "TANDEM!" and Config.line("MAYA", "THEO") == "MAYA AND THEO ARE HOLDING HANDS", "the template's own words are neutral")
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Tandem"}, "mode": "show", "players": [{"name": "Maya"}, {"name": "Theo"}], "show": {"tandem": {"banner": "side by side!", "line": "{a} and {b} walk together"}}})
	check(Config.text("banner") == "SIDE BY SIDE!" and Config.line("MAYA", "THEO") == "MAYA AND THEO WALK TOGETHER", "the cast's words win")
	TeamCast.override({})
	print("TANDEM_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)
