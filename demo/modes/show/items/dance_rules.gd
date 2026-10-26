extends "res://modes/show/items/item_rule.gd"
## DANCE (the forced video): the user THROWS a phone along the way it faces. It flies under gravity; a racer inside the aim assist's cone (`assist` degrees, up to SEE m ahead) is locked
## when it leaves the hand and the shot bends towards the racer's lead point at a limited turn rate, so it hits when thrown roughly right and misses when thrown wrong (a racer outside the
## cone is never locked, a dodge is outrun by the turn rate). The first racer other than the user it touches gets the effect for `duration` s (the view, dance_view.gd: the letterbox and
## the zoom on its own screen, the dance and the plain look on every screen, the freeze on its own machine); a shot that reaches the floor or its lifetime pops. The item is spent either way.
## Shot `a` is the user's slot.
const GRAVITY := 5.0 ## m/s2: a light phone, a miss carries about 22 m
const LIFT := 2.2 ## m/s up at the throw
const CHEST := 1.15 ## m over the user's feet the shot leaves from
const MUZZLE := 0.55 ## m in front of the user
const REACH := 0.9 ## m on the ground from the shot to a racer's feet
const BODY := Vector2(-0.2, 2.0) ## m over a racer's feet the shot touches
const SEE := 45.0 ## m ahead the assist looks
const LIFE := 2.5 ## s a shot flies
const TURN := 2.1 ## radians per second the assist bends the shot (120 degrees)
const GIVE_UP := 1.4 ## radians: a shot that would have to turn further than this lets go of its racer
const LEAD := 1.2 ## s the lead point is at most ahead of a running racer
const AIM := 1.0 ## m over the feet the assist aims at
const STEP := 0.4 ## m: the most a shot moves between two touch checks

func use(user: int) -> bool:
	if not items.self_test(user).is_empty() and items.racers().size() < 2: # the lab alone: nobody to throw at, the phone films the user
		items.add_fx(user, id, items.tune(id, "duration"), 0.0, 0.0, user)
		return true
	var yaw: float = items.host.yaw(user)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var from: Vector3 = items.host.position(user) + Vector3(0.0, CHEST, 0.0) + forward * MUZZLE
	var speed: float = items.tune(id, "speed")
	items.spawn(id, from, forward * speed + Vector3.UP * LIFT, _lock(user, from, forward), float(user))
	return true

## The racer the assist takes: inside the cone round the user's facing, the straightest first, a little nearer preferred; -1 for none.
func _lock(user: int, from: Vector3, forward: Vector3) -> int:
	var cone := deg_to_rad(items.tune(id, "assist"))
	var ahead := Vector2(forward.x, forward.z)
	var best := -1
	var best_score := INF
	for slot: int in items.racers():
		if slot == user: continue
		var to: Vector3 = items.host.position(slot) - from
		var flat := Vector2(to.x, to.z)
		var reach := flat.length()
		if reach > SEE or reach < 0.3: continue
		var angle := absf(ahead.angle_to(flat))
		if angle > cone: continue
		var score := angle + reach / SEE * 0.35
		if score < best_score:
			best_score = score
			best = slot
	return best

func tick(dt: float) -> void:
	var kind: int = items.Catalog.index(id)
	for shot: Dictionary in items.projectiles.duplicate():
		if int(shot.kind) == kind: _fly(shot, dt)

func _fly(shot: Dictionary, dt: float) -> void:
	var speed: float = items.tune(id, "speed")
	var user := int(shot.a)
	var v: Vector3 = shot.v
	v.y -= GRAVITY * dt
	var p: Vector3 = shot.p
	var lock := int(shot.tgt)
	if lock >= 0:
		if not items.racers().has(lock):
			lock = -1
		else:
			var aim: Vector3 = items.host.position(lock) + Vector3(0.0, AIM, 0.0) + items.host.velocity(lock) * clampf(p.distance_to(items.host.position(lock)) / speed, 0.0, LEAD)
			var want := (aim - p).normalized()
			var now := v.normalized()
			var angle := now.angle_to(want)
			if angle > GIVE_UP:
				lock = -1
			elif angle > 0.0001:
				now = now.slerp(want, minf(angle, TURN * dt) / angle) if angle < PI - 0.05 else want
				v = now * speed
		shot.tgt = lock
	shot.v = v
	shot.age = float(shot.age) + dt
	var steps := maxi(ceili(v.length() * dt / STEP), 1)
	for step in steps:
		p += v * dt / float(steps)
		shot.p = p
		var hit := _touching(user, p)
		if hit >= 0:
			items.add_fx(hit, id, items.tune(id, "duration"), 0.0, 0.0, user)
			items.remove_projectile(shot)
			return
		var floor_y: float = items.host.floor_at(items.level, p)
		if not is_nan(floor_y) and p.y <= floor_y + 0.05:
			items.remove_projectile(shot)
			return
	if float(shot.age) >= LIFE: items.remove_projectile(shot)

## The first racer other than the thrower the point touches, -1 for none.
func _touching(user: int, p: Vector3) -> int:
	for slot: int in items.racers():
		if slot == user: continue
		var feet: Vector3 = items.host.position(slot)
		var rise := p.y - feet.y
		if rise < BODY.x or rise > BODY.y: continue
		if Vector2(p.x - feet.x, p.z - feet.z).length() <= REACH: return slot
	return -1
