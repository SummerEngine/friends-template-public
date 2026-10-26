extends "res://modes/show/items/item_rule.gd"
## CALL (the urgent call): a homing shot leaves the user's chest in an arc and curves onto the nearest racer ahead; a hit opens a call window on that racer's screen (call_view.gd) for
## `window` s, never shorter than `least` s, and every GRAB press of the victim takes `tap` s off what is left. The victim is not blocked: the window is the whole effect (`mods` stays empty).
## The effect: `a` = the share of the screen the window covers, `b` = the GRAB presses the authority has counted since the window opened.
const CHEST := Vector3(0.0, 1.05, 0.0) ## m over a racer's feet: where the shot leaves and where it lands
const HIT_RADIUS := 1.2 ## m from the target's chest
const LIFE := 6.0 ## s in the air; then it dissolves
const LAUNCH_SPEED := 8.0 ## m/s at the start, ramping to the tuned speed over RAMP s
const RAMP := 0.45
const TURN := Vector2(2.4, 11.0) ## rad/s the shot may bend toward its target: loose at the start (a wide arc), tight later (it cannot orbit)
const TURN_RAMP := 0.9
const LIFT := 9.5 ## m/s upward at launch
const ARC_SIDE := 3.2 ## m/s sideways at launch: the curve

var _calls: Array = [] ## {entry, seen}: the windows open now and the victim's GRAB count when each opened
var _flips := 0 ## the side the next shot curves to

func begin() -> void:
	_calls.clear()

func use(user: int) -> bool:
	var ahead: Array = items.ahead_of(user)
	if ahead.is_empty(): ahead = items.behind_of(user) # in the lead there is nobody ahead: the nearest racer behind gets the call
	if ahead.is_empty(): ahead = items.self_test(user) # the lab alone: the call comes to the user
	if ahead.is_empty(): return false
	var target: int = ahead[0]
	var forward := _flat(items.position_of(target) - items.position_of(user), Vector3(-sin(items.host.yaw(user)), 0.0, -cos(items.host.yaw(user))))
	var side := Vector3(forward.z, 0.0, -forward.x) * (1.0 if _flips % 2 == 0 else -1.0)
	_flips += 1
	var from: Vector3 = items.position_of(user) + CHEST + forward * 0.35
	var shot: Dictionary = items.spawn(id, from, forward * LAUNCH_SPEED * 0.5 + side * ARC_SIDE + Vector3.UP * LIFT, target, float(user))
	shot["user"] = user
	aimed = target
	return true

func tick(dt: float) -> void:
	_fly(dt)
	_taps()

## Every shot of this item flies on toward its target's chest.
func _fly(dt: float) -> void:
	var live: Array = items.racers()
	var speed: float = items.tune(id, "speed")
	for shot: Dictionary in items.projectiles.duplicate():
		if int(shot.kind) != items.Catalog.index(id): continue
		shot.age = float(shot.age) + dt
		var target := int(shot.tgt)
		if float(shot.age) > LIFE or not live.has(target):
			items.remove_projectile(shot) # a miss: it dissolves
			continue
		var goal: Vector3 = items.position_of(target) + CHEST
		var at: Vector3 = shot.p
		var heading: Vector3 = (shot.v as Vector3).normalized()
		var want := (goal - at).normalized()
		var age := float(shot.age)
		var turn := lerpf(TURN.x, TURN.y, clampf(age / TURN_RAMP, 0.0, 1.0)) * (1.6 if at.distance_to(goal) < 5.0 else 1.0)
		var angle := heading.angle_to(want)
		var axis := heading.cross(want)
		if angle > 0.0001 and axis.length() > 0.0001: heading = heading.rotated(axis.normalized(), minf(angle, turn * dt))
		var pace := lerpf(LAUNCH_SPEED, speed, clampf(age / RAMP, 0.0, 1.0))
		var step := heading * pace * dt
		var gap := at.distance_to(goal)
		if gap <= HIT_RADIUS or _closest(at, step, goal) <= HIT_RADIUS:
			items.remove_projectile(shot)
			_land(int(shot.get("user", -1)), target)
			continue
		shot.v = heading * pace
		shot.p = at + step

## The shortest distance from `goal` to the segment `at` .. `at + step` (a fast shot must not skip over its target between two ticks).
func _closest(at: Vector3, step: Vector3, goal: Vector3) -> float:
	var length_sq := step.length_squared()
	var along := clampf((goal - at).dot(step) / length_sq, 0.0, 1.0) if length_sq > 0.0 else 0.0
	return (at + step * along).distance_to(goal)

## The shot reached `victim`: the call window opens there.
func _land(user: int, victim: int) -> void:
	var window: float = items.tune(id, "window")
	var entry: Dictionary = items.add_fx(victim, id, window, items.tune(id, "cover"), 0.0, user)
	_calls.append({"entry": entry, "seen": int(items.host.presses(victim, "grab"))})

## Every GRAB press of a victim since its window opened takes `tap` s off what is left, never below `least` s from the start (a window already past that closes at once).
func _taps() -> void:
	var tap: float = items.tune(id, "tap")
	var least: float = items.tune(id, "least")
	for watch: Dictionary in _calls.duplicate():
		var entry: Dictionary = watch.entry
		if not items.fx.has(entry):
			_calls.erase(watch)
			continue
		var count: int = items.host.presses(int(entry.slot), "grab")
		var fresh: int = count - int(watch.seen)
		watch.seen = count
		if fresh <= 0: continue
		entry.b = float(entry.b) + float(fresh)
		entry.dur = maxf(float(entry.dur) - tap * float(fresh), least)

func ended(entry: Dictionary) -> void:
	for watch: Dictionary in _calls.duplicate():
		if watch.entry == entry: _calls.erase(watch)

## `v` flattened on the ground and normalised, `fallback` when it has no length.
func _flat(v: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length() > 0.01 else fallback.normalized()
