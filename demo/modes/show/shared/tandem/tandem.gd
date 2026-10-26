extends RefCounted
## EXPERIMENT (switchable): TANDEM, the rules side (docs/party-show.md "Tandem (experiment)"). Two players who run towards or alongside each other, both moving, within `close` m for
## `hold` s grab hands and FUSE for `duration` s: the pair walks `speed` times as fast, each steers by the AVERAGE of both players' inputs (both must agree to turn), whoever the pair runs
## into is flung (`shove` times the shove, the show's BOOST shove), and at the end they spin apart with a fling. A pair that has just been a tandem cannot fuse again for `cooldown` s.
## Races (a racer on course in the play phase) and the lobby yard. Alone, a BUDDY (a kinematic runner that retraces the player's own trail, so it is always on ground) catches up, runs alongside
## and fuses with the player the same way, so the mechanic can be seen in a show for one player.
##
## Built by network/match_controller.gd (online, the authority) and client/local_level_flow.gd (one machine), which tick it with the slots that may fuse now (`tick`) and publish `state()` as
## `tandem` in the match state; modes/show/rules.gd says which slots may fuse in a race (`tandem_ok`). It never touches a node and never moves a courier except by `shell.fling_courier`
## (the exit's fling). Couriers move on their owners' machines: the owner's machine applies the speed, the averaged steering and the shove from the replicated pair (tandem_view.gd,
## game/game_run.gd `tandem`), because the authority only checks poses.
const Config := preload("res://modes/show/shared/tandem/tandem_config.gd")

const BUDDY := -1 ## the pseudo slot of the solo buddy in a pair
enum Event { FUSE, END, SLIP, BUDDY_IN, BUDDY_OUT } ## the `ev` types: two fused (a, b), spun apart at the end (a, b), came apart early (a, b), the buddy came / left
enum Phase { CHASE, BESIDE, FUSED, FLUNG } ## the buddy's phase (state `buddy[6]`)
const EVENT_KEEP := 8
const DY_MAX := 0.9 ## m: two couriers on different heights (a jump over the other) do not hold hands
const SLIP_AFTER := 0.6 ## s further apart than `break_dist`: the tandem comes apart
const WARM_SHOW := 0.3 ## s: a pair this long close is in the state (the view's spark between them)
const BUDDY_RUN := 2.0 ## m/s: the lone player must run this fast ...
const BUDDY_AFTER := 2.0 ## ... for this long before the buddy comes
const BUDDY_CHASE := 2.5 ## s behind the player (along its own trail) the buddy comes in
const BUDDY_SIDE := 1.0 ## m beside the player the buddy runs
const BUDDY_FUSED_SIDE := 0.95 ## m beside the player while they hold hands
const BUDDY_WAIT := 4.0 ## s the player may stand still before the buddy leaves
const BUDDY_OUT := 0.9 ## s the buddy spins away after a tandem
const BUDDY_LAG := 0.45 ## s: the buddy's own steering is the player's, this late (a sluggish partner: the pair turns wide)
const TRAIL_KEEP := 6.0 ## s of the lone player's trail

var shell ## game/game_run.gd (authority or local role)
var scope := "" ## "race" | "lobby" | "" (nothing may fuse now)
var active := false ## the experiment is on for this scope
var time := 0.0
var pairs: Array = [] ## {id, a, b, age, dur, apart}
var warm := {} ## pair key -> [a, b, s the two have been close, both moving]
var cooling := {} ## pair key -> s until they may fuse again
var events: Array = [] ## [seq, type, a, b]
var buddy := {} ## {phase, pos, vel, yaw, side, delay, out}; empty: no buddy
var buddy_cool := 0.0 ## s until a buddy may come again
var fused_total := 0 ## tandems begun since the match began (the checks read it)
var _next_id := 1
var _next_seq := 1
var _epoch := -1
var _trail: Array = [] ## [time, position] of the lone player
var _running_for := 0.0
var _still_for := 0.0
var _heading := Vector2(0.0, -1.0)
var _buddy_intent := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _me := -1 ## the lone player the buddy runs with (-1: none)

func _init(owner_shell) -> void:
	shell = owner_shell
	_rng.seed = 2510

## `eligible`: the slots that may fuse now (in the lobby everybody who joined, in a race the racers on course); `solo`: there is one player in all, so a buddy may come.
func tick(dt: float, new_scope: String, eligible: Array, solo: bool) -> void:
	time += dt
	for key: int in cooling.keys():
		cooling[key] = float(cooling[key]) - dt
		if float(cooling[key]) <= 0.0: cooling.erase(key)
	buddy_cool = maxf(buddy_cool - dt, 0.0)
	var fresh_epoch: bool = shell.reset_count != _epoch
	if fresh_epoch or new_scope != scope:
		_epoch = shell.reset_count
		clear()
		if fresh_epoch: cooling.clear()
	scope = new_scope
	active = scope != "" and Config.on(scope)
	if not active:
		if not pairs.is_empty() or not buddy.is_empty(): clear()
		return
	var valid: Array = eligible.filter(func(slot: int) -> bool: return shell.is_slot_active(slot) and shell.team.held_by(slot) < 0)
	_buddy_tick(dt, valid, solo)
	for pair: Dictionary in pairs.duplicate(): _tick_pair(pair, valid, dt)
	_find_pairs(dt, valid)
	if not buddy.is_empty(): _buddy_follow(dt)

## Forget every pair, warm-up and the buddy (a new epoch, another scope): nothing is on anybody any more. Cooldowns stay (a round change drops them with the epoch).
func clear() -> void:
	pairs.clear()
	warm.clear()
	buddy.clear()
	_trail.clear()
	_running_for = 0.0
	_still_for = 0.0

# ------------------------------------------------------------------ members

static func key_of(a: int, b: int) -> int:
	return mini(a, b) * 100 + maxi(a, b)

func position_of(slot: int) -> Vector3:
	if slot == BUDDY: return buddy.get("pos", Vector3.ZERO)
	return shell.actors[slot].position

func velocity_of(slot: int) -> Vector3:
	if slot == BUDDY: return buddy.get("vel", Vector3.ZERO)
	return shell.actors[slot].velocity

func intent_of(slot: int) -> Vector2:
	if slot == BUDDY: return _buddy_intent
	return shell.intent(slot)

func partner_of(slot: int) -> int:
	for pair: Dictionary in pairs:
		if int(pair.a) == slot: return int(pair.b)
		if int(pair.b) == slot: return int(pair.a)
	return -2

func _paired(slot: int) -> bool:
	return partner_of(slot) != -2

func _planar_speed(slot: int) -> float:
	var v := velocity_of(slot)
	return Vector2(v.x, v.z).length()

func _close(a: int, b: int) -> bool:
	var pa := position_of(a)
	var pb := position_of(b)
	if Vector2(pa.x - pb.x, pa.z - pb.z).length() > Config.tune("close") or absf(pa.y - pb.y) > DY_MAX: return false
	var least := Config.tune("min_speed")
	return _planar_speed(a) >= least and _planar_speed(b) >= least

# ------------------------------------------------------------------ pairs

func _find_pairs(dt: float, valid: Array) -> void:
	var members: Array = valid.filter(func(slot: int) -> bool: return not _paired(slot))
	if not buddy.is_empty() and int(buddy.phase) == Phase.BESIDE and valid.size() == 1 and not _paired(BUDDY): members.append(BUDDY)
	var touched := {}
	var used := {}
	for i in members.size():
		for j in range(i + 1, members.size()):
			var a: int = members[i]
			var b: int = members[j]
			if used.has(a) or used.has(b): continue
			var key := key_of(a, b)
			if cooling.has(key) or not _close(a, b): continue
			touched[key] = true
			var held: float = float((warm.get(key, [a, b, 0.0]) as Array)[2]) + dt
			warm[key] = [a, b, held]
			if held >= Config.tune("hold"):
				warm.erase(key)
				_fuse(a, b)
				used[a] = true
				used[b] = true
	for key: int in warm.keys():
		if touched.has(key): continue
		var row: Array = warm[key]
		row[2] = float(row[2]) - dt * 2.0
		if float(row[2]) <= 0.0: warm.erase(key)

func _fuse(a: int, b: int) -> void:
	pairs.append({"id": _next_id, "a": a, "b": b, "age": 0.0, "dur": Config.tune("duration"), "apart": 0.0})
	_next_id += 1
	fused_total += 1
	if a == BUDDY or b == BUDDY: buddy.phase = Phase.FUSED
	_announce(Event.FUSE, a, b)

func _tick_pair(pair: Dictionary, valid: Array, dt: float) -> void:
	var a := int(pair.a)
	var b := int(pair.b)
	var here_a: bool = valid.has(a) if a != BUDDY else not buddy.is_empty()
	var here_b: bool = valid.has(b) if b != BUDDY else not buddy.is_empty()
	if not (here_a and here_b):
		_end(pair, Event.SLIP)
		return
	pair.age = float(pair.age) + dt
	var pa := position_of(a)
	var pb := position_of(b)
	if Vector2(pa.x - pb.x, pa.z - pb.z).length() > Config.tune("break_dist"): pair.apart = float(pair.apart) + dt
	else: pair.apart = 0.0
	if float(pair.apart) > SLIP_AFTER: _end(pair, Event.SLIP)
	elif float(pair.age) >= float(pair.dur): _end(pair, Event.END)

## The pair is over: `Event.END` at the full time (they spin apart with a fling), `Event.SLIP` for any other end (nobody is flung); the pair waits `cooldown` s.
func _end(pair: Dictionary, kind: int) -> void:
	pairs.erase(pair)
	var a := int(pair.a)
	var b := int(pair.b)
	cooling[key_of(a, b)] = Config.tune("cooldown")
	_announce(kind, a, b)
	var away := Vector2(position_of(a).x - position_of(b).x, position_of(a).z - position_of(b).z)
	if away.length() < 0.05: away = Vector2.from_angle(float(pair.id) * 2.4)
	away = away.normalized()
	var fling := kind == Event.END
	var push := Vector3(away.x, 0.0, away.y) * Config.tune("fling") + Vector3.UP * Config.tune("lift")
	for slot: int in [a, b]:
		var sign := 1.0 if slot == a else -1.0
		if slot == BUDDY:
			if not buddy.is_empty(): _fling_buddy(Vector3(push.x, 0.0, push.z) * sign if fling else Vector3.ZERO)
		elif fling and shell.is_slot_active(slot):
			shell.fling_courier(slot, Vector3(push.x * sign, push.y, push.z * sign))

# ------------------------------------------------------------------ the buddy (a show for one player)

func _buddy_tick(dt: float, valid: Array, solo: bool) -> void:
	var want := solo and Config.solo_buddy() and valid.size() == 1
	if not want:
		if not buddy.is_empty():
			if int(buddy.phase) != Phase.FLUNG: _announce(Event.BUDDY_OUT, BUDDY, -2)
			for pair: Dictionary in pairs.duplicate():
				if int(pair.a) == BUDDY or int(pair.b) == BUDDY: _end(pair, Event.SLIP)
			buddy.clear()
		_trail.clear()
		_running_for = 0.0
		_me = -1
		return
	var me: int = valid[0]
	_me = me
	var here := position_of(me)
	_trail.append([time, here])
	while _trail.size() > 2 and time - float((_trail[0] as Array)[0]) > TRAIL_KEEP: _trail.pop_front()
	var v := velocity_of(me)
	var speed := Vector2(v.x, v.z).length()
	if speed > 0.5: _heading = Vector2(v.x, v.z) / speed
	_buddy_intent = _buddy_intent.lerp(intent_of(me), 1.0 - exp(-dt / BUDDY_LAG))
	if buddy.is_empty():
		_running_for = _running_for + dt if speed >= BUDDY_RUN else 0.0
		if _running_for >= BUDDY_AFTER and buddy_cool <= 0.0 and not cooling.has(key_of(me, BUDDY)) and not _paired(me): _buddy_come(here)
		return
	match int(buddy.phase):
		Phase.CHASE:
			buddy.delay = float(buddy.delay) - dt
			if float(buddy.delay) <= 0.0: buddy.phase = Phase.BESIDE
		Phase.BESIDE:
			_still_for = _still_for + dt if speed < Config.tune("min_speed") * 0.5 else 0.0
			if _still_for >= BUDDY_WAIT:
				_announce(Event.BUDDY_OUT, BUDDY, -2)
				buddy.clear()
				buddy_cool = 3.0
				warm.clear()
				_still_for = 0.0
		Phase.FLUNG:
			buddy.out = float(buddy.out) - dt
			if float(buddy.out) <= 0.0:
				buddy.clear()
				buddy_cool = 2.0
	if not buddy.is_empty(): buddy.yaw = atan2(-_heading.x, -_heading.y)

func _buddy_come(at: Vector3) -> void:
	buddy = {"phase": Phase.CHASE, "pos": at, "vel": Vector3.ZERO, "yaw": atan2(-_heading.x, -_heading.y), "side": 1.0 if _rng.randf() < 0.5 else -1.0, "delay": BUDDY_CHASE, "out": 0.0}
	_still_for = 0.0
	_announce(Event.BUDDY_IN, BUDDY, -2)

## Where the buddy is this tick: behind the player along its own trail (a ground it stood on), closing in; then beside it; while fused beside it, holding hands.
func _buddy_follow(dt: float) -> void:
	var before: Vector3 = buddy.pos
	var phase := int(buddy.phase)
	if phase == Phase.FLUNG:
		buddy.pos = before + (buddy.vel as Vector3) * dt
		buddy.vel = (buddy.vel as Vector3) * maxf(1.0 - 3.0 * dt, 0.0)
		return
	var me := _me
	if me < 0 or _trail.is_empty(): return
	var here := position_of(me)
	var right := Vector3(-_heading.y, 0.0, _heading.x)
	var side: float = buddy.side
	match phase:
		Phase.CHASE:
			var delay := float(buddy.delay)
			var back := _trail_at(time - delay)
			var wide := lerpf(BUDDY_SIDE, 2.4, clampf(delay / BUDDY_CHASE, 0.0, 1.0))
			buddy.pos = back + right * side * wide
			buddy.pos.y = back.y
		Phase.BESIDE:
			buddy.pos = here + right * side * BUDDY_SIDE
		Phase.FUSED:
			buddy.pos = here + right * side * BUDDY_FUSED_SIDE
	if phase == Phase.CHASE: buddy.vel = ((buddy.pos as Vector3) - before) / maxf(dt, 0.0001)
	else: buddy.vel = velocity_of(me)

func _trail_at(t: float) -> Vector3:
	var last: Vector3 = (_trail.back() as Array)[1]
	if _trail.size() < 2: return last
	for i in range(_trail.size() - 1, 0, -1):
		var late: Array = _trail[i]
		var early: Array = _trail[i - 1]
		if float(early[0]) <= t:
			var span := maxf(float(late[0]) - float(early[0]), 0.0001)
			return (early[1] as Vector3).lerp(late[1] as Vector3, clampf((t - float(early[0])) / span, 0.0, 1.0))
	return (_trail[0] as Array)[1]

func _fling_buddy(velocity: Vector3) -> void:
	buddy.phase = Phase.FLUNG
	buddy.vel = velocity
	buddy.out = BUDDY_OUT

# ------------------------------------------------------------------ the state

func _announce(type: int, a: int, b: int) -> void:
	events.append([_next_seq, type, a, b])
	_next_seq += 1
	while events.size() > EVENT_KEEP: events.pop_front()

## `tandem` in the match state, small and plain: `pairs` [id, a, b, age, dur, ax, az, bx, bz] (a and b slots, -1 the buddy, a's and b's steering: the world move the partner's machine averages with its own),
## `warm` [a, b, share of the hold], `buddy` [x, y, z, yaw, vx, vz, phase] or [], `ev` [seq, type, a, b] and `seq`, the next event's number.
func state() -> Dictionary:
	var rows: Array = []
	for pair: Dictionary in pairs:
		var ma := intent_of(int(pair.a))
		var mb := intent_of(int(pair.b))
		rows.append([int(pair.id), int(pair.a), int(pair.b), snappedf(float(pair.age), 0.01), float(pair.dur), snappedf(ma.x, 0.01), snappedf(ma.y, 0.01), snappedf(mb.x, 0.01), snappedf(mb.y, 0.01)])
	var heat: Array = []
	var hold := maxf(Config.tune("hold"), 0.1)
	for row: Array in warm.values():
		if float(row[2]) >= WARM_SHOW: heat.append([int(row[0]), int(row[1]), snappedf(clampf(float(row[2]) / hold, 0.0, 1.0), 0.01)])
	var out := {"scope": scope, "seq": _next_seq, "pairs": rows, "warm": heat, "ev": events.duplicate(true)}
	if not buddy.is_empty():
		var p: Vector3 = buddy.pos
		var v: Vector3 = buddy.vel
		out["buddy"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(float(buddy.yaw), 0.01), snappedf(v.x, 0.01), snappedf(v.z, 0.01), int(buddy.phase)]
	return out
