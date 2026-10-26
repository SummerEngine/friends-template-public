extends RefCounted
## Hazard kinds of a level (docs/level-format.md) as pure functions of the level clock: the same `t` gives the same pose on every peer,
## nothing here touches physics or random numbers. `normalize()` turns a JSON hazard into typed fields once, `pose()` evaluates it.
const GRAVITY := 17.0
const MOVERS := ["slide", "lift", "spin", "swing", "blink", "spikes"]
const VOLUMES := ["push", "bumper"]
const SHOTS := ["ball", "cannon"]
## Lasers and fire jets: no collision for couriers; touching one pops the balloon, breaks the painting and zaps / burns a player.
const SCORCHERS := ["laser", "fire"]
const KINDS := ["slide", "lift", "spin", "swing", "blink", "spikes", "push", "bumper", "ball", "cannon", "laser", "fire"]
## Movers that may wear "look": "spikes" (a spike crusher: always `hit`).
const SPIKED := ["slide", "lift", "spin", "swing"]
## Default of `hit` (touching it with the painting breaks it) per kind.
const DEFAULT_HIT := {"slide": false, "lift": false, "spin": true, "swing": true, "blink": true, "spikes": true, "ball": true, "cannon": true,
	"laser": true, "fire": true}
## What a scorcher does to a player who touches it: the comic word and the respawn cause.
const SCORCH := {"laser": "zap", "fire": "burn"}
const BEAM_RADIUS := 0.1     ## the laser's hit radius (m), also the drawn beam's
const SPIKE_MOVE := 0.5      ## seconds a spike takes to rise and to sink
const SPIKE_PEEK := 0.25     ## metres the spikes shiver upward during `warn`
const SHAKE_AMPLITUDE := 0.06
const DEFAULT_KICK := 7.5
const DEFAULT_UP := 15.0
## A bump bar (a part with `bump: true` of a turning floor, `spin` without `hit`: the pointer bar of a turntable) throws the courier it touches like a bumper does: away from the bar's plane.
const BAR_KICK := 9.0        ## m/s horizontal (hazard key `kick`)
const BAR_UP := 4.0          ## m/s up, a small pop (hazard key `up`)
## A bumper's drawn ball (radius `rad`) wears a band this far proud of it (style/hazard_looks.gd): the outermost thing a courier can see of the bumper.
## The bump fires when the courier's capsule reaches that surface (level_world.gd effects_at), so no part of a courier is ever inside what is drawn.
const BUMPER_BAND := 0.1
## ---- a blink block that is gone ----
## Nothing in the game vanishes into nowhere: a blink block that stops being solid falls away under the level and (a periodic one) climbs back, so it is never
## drawn popping out or in. `active` (collision, the schedule) is exactly on / off / warn; only where the block is while it is not solid changes.
const BLINK_CLEAR := 2.0          ## m under its own underside a gone block hangs, out of reach
const BLINK_FALL_TIME := 0.4      ## s it takes to fall that far: an accelerating fall, much faster than a courier's own, so nobody is left standing in it
const BLINK_RISE_TIME := 0.5      ## s it takes to climb back, ending exactly when it is solid again
const BLINK_AWAY_OFF := 20.0      ## an `off` this long or longer: the block is gone for the round, it falls on out of sight (and climbs back for the next one)
const BLINK_AWAY_DEPTH := 60.0    ## m
const BLINK_AWAY_RISE := 2.0      ## s its climb back from there takes at most: a swoosh up out of the depth that is seen only over its last metres (the tiles of a picture that stands from S to E come up into place just before S)
const BLINK_MIN_OFF := BLINK_FALL_TIME + BLINK_RISE_TIME ## s: a shorter `off` could not fall out of reach before it is rising again (level_lint.py rejects it)
## The cast slots an obstacle box may wear (`slot` on a block or hazard part, docs/level-format.md).
const OBSTACLE_SLOTS := ["obstacle_1", "obstacle_2", "obstacle_3", "obstacle_4", "obstacle_5"]
## The start gate of a race or final: its two big faces wear the brand (the logo, the accent colour, the team name).
const GATE_SLOT := "gate"
## A cylinder block of a hero prop's stand (docs/hero-prop.md): the look draws no block there, the `hero_prop` slot draws the prop.
const HERO_SLOT := "hero_prop"

## The evaluated state of one hazard at one instant (reused between ticks).
class Pose extends RefCounted:
	var position := Vector3.ZERO     ## level-local
	var basis := Basis.IDENTITY
	var active := true               ## false: absent for gameplay (collision off, harmless): a blink block that is gone, a ball between shots; a laser or fire jet that is off
	var shake := 0.0                 ## 0..1 warning intensity of a blink block (visual shiver already included in `position`), a laser or a fire jet
	var lead := false                ## not `active` but still drawn, harmless: a blink block that has fallen away (`position` is where it hangs), a ball or cannon ball inside its housing (a wall slot, a floor hole, the barrel): it comes out of / goes into it

static func vec(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and (value as Array).size() >= 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func euler(value: Variant) -> Basis:
	var angles := vec(value)
	return Basis.from_euler(Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z)), EULER_ORDER_YXZ)

static func axis_basis(axis: String, degrees: float) -> Basis:
	var direction := Vector3.UP
	if axis == "x": direction = Vector3.RIGHT
	elif axis == "z": direction = Vector3.BACK
	return Basis(direction, deg_to_rad(degrees))

## A courier at rest on the downstream rim of a belt hangs on it, its capsule's round foot on the edge, up to radius * sin(floor angle) past the edge (CourierMotion
## CAPSULE_RADIUS): the belt keeps carrying it over that far so it is taken off the end and falls instead of perching there.
const BELT_RIM := 0.35

## The box in which a belt carries a courier (`carry` of a belt block): the belt's own box, longer by BELT_RIM at its downstream end (a box turned about y; the
## side the flow runs along is the one of its two horizontal axes the flow lies closer to).
static func belt_carry(b: Dictionary) -> Dictionary:
	var carry := b.duplicate()
	var xf: Transform3D = b.xf
	var flow: Vector2 = b.belt
	var axes := [xf.basis.x, xf.basis.z]
	var best := 0
	var along := 0.0
	for index in 2:
		var horizontal := Vector2((axes[index] as Vector3).x, (axes[index] as Vector3).z).normalized()
		if absf(horizontal.dot(flow)) > absf(along):
			along = horizontal.dot(flow)
			best = index
	var size: Vector3 = b.size
	var axis: Vector3 = (axes[best] as Vector3).normalized() * signf(along)
	if best == 0: size.x += BELT_RIM
	else: size.z += BELT_RIM
	carry.size = size
	carry.xf = Transform3D(xf.basis, xf.origin + axis * BELT_RIM * 0.5)
	return carry

## One block (static block or hazard part) as typed fields: {k, xf, size, d, h, m, belt, hit, slot, tone, bump}. `bump` is a bumper bar of a turning floor (BAR_KICK). `slot` is an obstacle box's cast slot ("" none). `tone` is the daylight surface a part of a `slide` / `lift` wears ("" none).
## `belt` (level-local planar m/s, world x / z) is the velocity of a conveyor block (`m` "belt"), ZERO on every other block.
static func block(source: Dictionary) -> Dictionary:
	var kind := str(source.get("k", "box"))
	var size := vec(source.get("s"), Vector3.ONE)
	var diameter := float(source.get("d", 1.0))
	var height := float(source.get("h", 1.0))
	if kind == "cyl": size = Vector3(diameter, height, diameter)
	var slot := str(source.get("slot", ""))
	var material := str(source.get("m", "ground"))
	var belt := Vector2.ZERO
	var listed: Variant = source.get("belt")
	if material == "belt" and listed is Array and (listed as Array).size() >= 2: belt = Vector2(float(listed[0]), float(listed[1]))
	var xf := Transform3D(euler(source.get("r")), vec(source.get("p")))
	var slime := Vector2.ZERO # `m` "slime" (a wedge): the slope's downhill, a unit planar vector (the wedge's low edge, local -Z)
	if material == "slime":
		var downhill := xf.basis * Vector3(0.0, 0.0, -1.0)
		slime = Vector2(downhill.x, downhill.z).normalized()
	return {"k": kind, "xf": xf, "size": size, "d": diameter, "h": height,
		"m": material, "belt": belt, "slime": slime, "hit": bool(source.get("hit", false)), "slot": slot if slot in OBSTACLE_SLOTS or slot == GATE_SLOT or slot == HERO_SLOT else "",
		"tone": str(source.get("tone", "")), "bump": bool(source.get("bump", false))}

## One hazard of the level file with every default filled in and vectors typed. Returns {} for an unknown kind.
static func normalize(source: Dictionary) -> Dictionary:
	var kind := str(source.get("k", ""))
	if not kind in KINDS: return {}
	var result := {"k": kind, "id": str(source.get("id", "")), "pivot": vec(source.get("p")), "base": euler(source.get("r")),
		"phase": float(source.get("phase", 0.0)), "hit": bool(source.get("hit", DEFAULT_HIT.get(kind, false))), "ride": str(source.get("ride", "")),
		"look": "spikes" if kind in SPIKED and str(source.get("look", "")) == "spikes" else ""}
	if result.look == "spikes" or kind in SCORCHERS: result.hit = true
	var parts: Array = []
	if source.get("parts") is Array:
		for part: Variant in source.parts:
			if part is Dictionary: parts.append(block(part))
	elif source.has("s") and kind in MOVERS:
		parts.append(block({"k": "box", "s": source.s, "slot": source.get("slot", "")}))
	result.parts = parts
	match kind:
		"slide":
			result.to = vec(source.get("to"))
			result.period = maxf(float(source.get("period", 4.0)), 0.25)
			result.pause = float(source.get("pause", 0.0))
			result.ease = str(source.get("ease", "sine"))
		"lift":
			result.to = Vector3(0.0, float(source.get("rise", 4.0)), 0.0)
			result.period = maxf(float(source.get("period", 8.0)), 0.25)
			result.pause = float(source.get("pause", 1.0))
			result.hold = float(source.get("hold", result.pause))
			result.ease = str(source.get("ease", "sine"))
		"spin":
			result.axis = str(source.get("axis", "y"))
			result.rate = float(source.get("rate", 30.0))
			result.kick = float(source.get("kick", BAR_KICK))
			result.up_speed = float(source.get("up", BAR_UP))
		"swing":
			result.axis = str(source.get("axis", "x"))
			result.a0 = float(source.get("a0", -60.0))
			result.a1 = float(source.get("a1", 60.0))
			result.period = maxf(float(source.get("period", 4.0)), 0.25)
			result.pause = float(source.get("pause", 0.0))
			result.ease = str(source.get("ease", "sine"))
		"blink":
			result.on_time = maxf(float(source.get("on", 3.0)), 0.25)
			result.off_time = maxf(float(source.get("off", 3.0)), 0.25)
			result.warn = float(source.get("warn", 1.0))
			_blink_fall(result)
		"spikes":
			result.rise = float(source.get("rise", 2.5))
			result.period = float(source.get("period", 0.0))
			result.up = float(source.get("up", 1.0))
			result.warn = float(source.get("warn", 0.5))
		"push":
			result.g = str(source.get("g", "box"))
			result.size = vec(source.get("s"), Vector3.ONE)
			if result.g == "cyl": result.size = Vector3(float(source.get("d", 1.0)), float(source.get("h", 1.0)), float(source.get("d", 1.0)))
			result.v = vec(source.get("v"))
		"bumper":
			result.rad = float(source.get("rad", 1.0))
			result.kick = float(source.get("kick", DEFAULT_KICK))
			result.up_speed = float(source.get("up", DEFAULT_UP))
		"ball":
			var points := PackedVector3Array()
			for point: Variant in source.get("path", []): points.append(vec(point))
			result.path = points
			result.lengths = _lengths(points)
			result.speed = maxf(float(source.get("speed", 4.0)), 0.5)
			result.rad = float(source.get("rad", 1.0))
			result.period = maxf(float(source.get("period", 8.0)), 0.25)
		"cannon":
			result.v = vec(source.get("v"))
			result.rad = float(source.get("rad", 0.5))
			result.period = maxf(float(source.get("period", 4.0)), 0.25)
			result.life = minf(float(source.get("life", 3.0)), result.period)
		"laser":
			result.to = vec(source.get("to"), Vector3(0.0, 0.0, -4.0))
			_schedule_fields(source, result, 0.5)
			result.move = vec(source.get("move"))
			result.period = maxf(float(source.get("period", 4.0)), 0.25)
			result.pause = float(source.get("pause", 0.0))
			result.ease = str(source.get("ease", "sine"))
			result.axis = str(source.get("axis", "y"))
			result.rate = float(source.get("rate", 0.0))
		"fire":
			result.g = str(source.get("g", "box"))
			result.size = vec(source.get("s"), Vector3(1.0, 3.0, 1.0))
			if result.g == "cyl": result.size = Vector3(float(source.get("d", 1.0)), float(source.get("h", 3.0)), float(source.get("d", 1.0)))
			_schedule_fields(source, result, 1.0)
	return result

## on / off / warn of a laser or fire jet. No `on` and `off`: always on.
static func _schedule_fields(source: Dictionary, result: Dictionary, default_warn: float) -> void:
	result.on_time = maxf(float(source.get("on", 0.0)), 0.0)
	result.off_time = maxf(float(source.get("off", 0.0)), 0.0)
	result.warn = clampf(float(source.get("warn", default_warn)), 0.0, result.off_time)

## How a blink block falls away (BLINK_*): `sink` the depth it falls to (its own height plus BLINK_CLEAR; BLINK_AWAY_DEPTH for a block that is gone for the round),
## `fall_accel` the fall's acceleration (m/s², the same for both: BLINK_FALL_TIME to cover height + clearance), `rise_time` s of its climb back.
static func _blink_fall(h: Dictionary) -> void:
	var low := INF
	var high := -INF
	for part: Dictionary in h.parts:
		var half: Vector3 = (part.size as Vector3) * 0.5
		var turn: Transform3D = Transform3D(h.base as Basis, Vector3.ZERO) * (part.xf as Transform3D)
		for corner in 8:
			var y := (turn * Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y, half.z if corner & 4 else -half.z)).y
			low = minf(low, y)
			high = maxf(high, y)
	var clear := (high - low if high > low else 1.0) + BLINK_CLEAR
	var away: bool = float(h.off_time) >= BLINK_AWAY_OFF
	h.sink = BLINK_AWAY_DEPTH if away else clear
	h.fall_accel = 2.0 * clear / (BLINK_FALL_TIME * BLINK_FALL_TIME)
	h.rise_time = minf(BLINK_AWAY_RISE, float(h.off_time) * 0.5) if away else BLINK_RISE_TIME

## How far under its place a blink block hangs `m` seconds into its cycle (0 while it is solid): an accelerating fall from the moment it stops being solid,
## and a climb that ends exactly when it is solid again (a gone block short of time never reaches its full depth; `off` is at least BLINK_MIN_OFF).
static func blink_depth(h: Dictionary, m: float) -> float:
	var on_time: float = h.on_time
	if m < on_time: return 0.0
	var s := m - on_time
	var depth := minf(0.5 * float(h.fall_accel) * s * s, float(h.sink))
	var until: float = on_time + float(h.off_time) - m
	var rise_time: float = h.rise_time
	if until < rise_time:
		var u := maxf(until, 0.0) / rise_time
		depth = minf(depth, float(h.sink) * u * u)
	return depth

static func _lengths(points: PackedVector3Array) -> PackedFloat64Array:
	var lengths := PackedFloat64Array()
	var total := 0.0
	lengths.append(0.0)
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
		lengths.append(total)
	return lengths

## One round trip of `period` seconds: 0 -> 1 -> 0 with `pause` seconds of rest at the 0 end and `hold` seconds at the 1 end (`hold` < 0: the same as `pause`).
## Starts at 0 for tau = 0. Requires period > pause + hold.
static func cycle(tau: float, period: float, pause: float, ease_name: String, hold := -1.0) -> float:
	var top := pause if hold < 0.0 else hold
	var moving := maxf((period - pause - top) * 0.5, 0.001)
	var m := fposmod(tau, period)
	var f: float
	if m < pause: f = 0.0
	elif m < pause + moving: f = (m - pause) / moving
	elif m < pause + moving + top: f = 1.0
	else: f = 1.0 - (m - pause - moving - top) / moving
	f = clampf(f, 0.0, 1.0)
	if ease_name == "sine": f = 0.5 - 0.5 * cos(f * PI)
	return f

## ---- the life of a ball and of a cannon ball: what it comes out of and where it goes (levels/level_world.gd calls build_life once the level's blocks are known) ----
## Nothing may pop in or out in view: a ball's two ends are each a round slot in a wall right at the end of its path, or a hole in the floor under it
## (the look draws the slot or the hole, style/shot_looks.gd); a cannon ball starts inside its barrel and leaves through a wall slot (or over a floor edge).
## `active` (collision, hurts) is the shot's whole gameplay life; the drawn extra (`Pose.lead`) is harmless. Mirrored by tools/shot_plan.py (the linter).
const NO_FLOOR := -1.0e9
const WALL_REACH := 0.3          ## a path end this near a wall (centre distance - radius) is in that wall's slot
const PORT_TIME := 0.5           ## s a ball takes to come up out of / sink into a floor hole
const SWALLOW := 0.1             ## m past fully inside a wall
const SHOT_RESTITUTION := 0.5    ## a cannon ball keeps this share of its fall speed on a bounce ...
const SHOT_FRICTION := 0.85      ## ... and of its flat speed
const SHOT_REST := 2.5           ## a bounce slower than this (m/s) is a roll
const SHOT_MAX_ARCS := 10
const SHOT_MAX_ROLL := 40.0      ## m
const SHOT_ROLL_STEP := 0.25
const SHOT_FALL_DEPTH := 14.0    ## a ball that rolls off a floor falls this far, then it is gone

## Builds the life cycle of a ball (`ports`) or a cannon ball (`plan`) from the blocks of its level. Pure and static: every peer builds the same.
static func build_life(h: Dictionary, blocks: Array) -> void:
	if h.k == "ball":
		if (h.path as PackedVector3Array).size() >= 2: h.ports = ball_ports(h, blocks)
	elif h.k == "cannon":
		var plan := shot_plan(h, blocks)
		if not (plan.segments as Array).is_empty(): h.plan = plan

## The top of the highest block under `at` (a ray straight down); NO_FLOOR for none.
static func floor_top(blocks: Array, at: Vector3) -> float:
	var best := INF
	for block: Dictionary in blocks: best = minf(best, ray_hit(block, at, Vector3.DOWN))
	return at.y - best if best < INF else NO_FLOOR

## Distance along the ray to the nearest block, INF for none.
static func wall_distance(blocks: Array, at: Vector3, direction: Vector3) -> float:
	var best := INF
	for block: Dictionary in blocks: best = minf(best, ray_hit(block, at, direction))
	return best

## The housing of one end of a ball's path: the ball (centre `at`, radius `rad`) leaves / enters along `direction`. {kind "wall", point, normal, hide}: a wall
## within reach, the ball goes through a round slot in it, `hide` m of centre travel to be fully inside; {kind "floor", point}: it comes up out of / sinks into
## a hole in the floor under it; {kind "none"}: nothing hides it.
static func ball_port(blocks: Array, at: Vector3, direction: Vector3, rad: float) -> Dictionary:
	var wall := wall_distance(blocks, at, direction)
	if wall <= rad + WALL_REACH:
		return {"kind": "wall", "point": at + direction * wall, "normal": -direction, "hide": wall + rad + SWALLOW}
	var floor_at := floor_top(blocks, at)
	if floor_at > NO_FLOOR * 0.5 and at.y - floor_at <= rad + WALL_REACH:
		return {"kind": "floor", "point": Vector3(at.x, floor_at, at.z)}
	return {"kind": "none"}

static func _lead_time(port: Dictionary, speed: float) -> float:
	if port.kind == "wall": return float(port.hide) / speed
	if port.kind == "floor": return PORT_TIME
	return 0.0

## {enter, leave: the two ports, lead_in, lead_out: s of drawn lead before the path starts / after it ends} of a `ball`. The leads share the gap of the period
## outside the path (shrunk together when they do not both fit: the linter then rejects the level).
static func ball_ports(h: Dictionary, blocks: Array) -> Dictionary:
	var points: PackedVector3Array = h.path
	var rad := float(h.rad)
	var speed := float(h.speed)
	var first := (points[1] - points[0]).normalized()
	var last := (points[points.size() - 1] - points[points.size() - 2]).normalized()
	var enter := ball_port(blocks, points[0], -first, rad)
	var leave := ball_port(blocks, points[points.size() - 1], last, rad)
	var lengths: PackedFloat64Array = h.lengths
	var gap := maxf(float(h.period) - lengths[lengths.size() - 1] / speed, 0.0)
	var lead_in := _lead_time(enter, speed)
	var lead_out := _lead_time(leave, speed)
	var both := lead_in + lead_out
	if both > gap and both > 0.0:
		lead_in *= gap / both
		lead_out *= gap / both
	return {"enter": enter, "leave": leave, "lead_in": lead_in, "lead_out": lead_out}

## Metres the ball is from the end of its path (x) and how deep it has sunk (y), `e` seconds into a lead of `time` seconds: a wall slot is plain rolling,
## a floor hole speeds it up (out of the hole) or slows it down (into it) while it rises or sinks.
static func _lead_offset(kind: String, e: float, time: float, speed: float, rad: float) -> Vector2:
	if kind == "wall": return Vector2(speed * e, 0.0)
	var length := maxf(time, 0.001)
	var u := e / length
	return Vector2(speed * (e - e * e / (2.0 * length)), (2.0 * rad + SWALLOW) * u * u)

## A ball at distance `along` of its path (before the start and past the end it goes on along the first / last stretch).
static func _ball_place(h: Dictionary, along: float, out: Pose) -> void:
	var points: PackedVector3Array = h.path
	var lengths: PackedFloat64Array = h.lengths
	var last := points.size() - 1
	if along <= 0.0:
		out.position = points[0] + (points[1] - points[0]).normalized() * along
	elif along >= lengths[last]:
		out.position = points[last] + (points[last] - points[last - 1]).normalized() * (along - lengths[last])
	else:
		var segment := 1
		while segment < last and along > lengths[segment]: segment += 1
		var span := maxf(lengths[segment] - lengths[segment - 1], 0.0001)
		var u := clampf((along - lengths[segment - 1]) / span, 0.0, 1.0)
		out.position = points[segment - 1].lerp(points[segment], u)
	out.basis = _ball_roll(h, along)

## The turn of a ball that has rolled `along` metres of its path: on each stretch it turns about that stretch's own roll axis (up x heading) by the distance it
## rolled on it, the turns composed in order, so a bounce changes the axis without the look jumping. Before the start and past the end it rolls on along the
## first / last stretch. Look only (the collision is a sphere).
static func _ball_roll(h: Dictionary, along: float) -> Basis:
	var points: PackedVector3Array = h.path
	var lengths: PackedFloat64Array = h.lengths
	var last := points.size() - 1
	var radius := maxf(float(h.rad), 0.1)
	var turn := Basis.IDENTITY
	for segment in range(1, last + 1):
		var start := float(lengths[segment - 1])
		var rolled := along - start
		if segment > 1: rolled = maxf(rolled, 0.0)
		if segment < last: rolled = minf(rolled, float(lengths[segment]) - start)
		if absf(rolled) < 0.0001: continue
		var axis := Vector3.UP.cross((points[segment] - points[segment - 1]).normalized())
		if axis.length_squared() > 0.0001: turn = Basis(axis.normalized(), rolled / radius) * turn
	return turn

## A ball outside its path, `m` seconds into its period: waiting (not drawn), or in the lead out of the path's end / into its start (drawn, harmless).
static func _ball_lead(h: Dictionary, m: float, out: Pose) -> void:
	var points: PackedVector3Array = h.path
	out.active = false
	# wait at the start of the roll, not at the pivot (the level origin when `p` is left out: the start pad)
	out.position = points[0]
	if not h.has("ports"): return
	var ports: Dictionary = h.ports
	var speed := float(h.speed)
	var rad := float(h.rad)
	var lengths: PackedFloat64Array = h.lengths
	var total := lengths[lengths.size() - 1]
	var after := m - total / speed
	var before := float(h.period) - m
	var lead_out := float(ports.lead_out)
	var lead_in := float(ports.lead_in)
	if after < lead_out:
		var leaving: Dictionary = ports.leave
		var gone := _lead_offset(str(leaving.kind), after, lead_out, speed, rad)
		_ball_place(h, total + gone.x, out)
		out.position.y -= gone.y
		out.lead = true
	elif before < lead_in:
		var entering: Dictionary = ports.enter
		var coming := _lead_offset(str(entering.kind), before, lead_in, speed, rad)
		_ball_place(h, -coming.x, out)
		out.position.y -= coming.y
		out.lead = true

static func _landing_time(dy: float, vy: float) -> float:
	return (vy + sqrt(vy * vy + 2.0 * GRAVITY * maxf(dy, 0.0))) / GRAVITY

## The flight of a cannon ball from the muzzle (`pivot`, speed `v`): ballistic arcs and bounces on the floor under it, then a roll across the floor, until a
## wall swallows it (kind "wall", `port`: the slot) or the floor ends under it (kind "edge": it falls). {segments: [[t0, p0, v0, g, spin0], ...], hit: s it hurts
## until, end: s it is gone, kind, port, land, landed}. Mirrored by tools/shot_plan.py.
static func shot_plan(h: Dictionary, blocks: Array) -> Dictionary:
	var rad := float(h.rad)
	var p: Vector3 = h.pivot
	var v: Vector3 = h.v
	var t := 0.0
	var spin := 0.0
	var segments: Array = []
	var kind := "none"
	var port := {}
	var hit := -1.0
	var land := Vector3.ZERO
	var landed := false
	for _arc in SHOT_MAX_ARCS:
		var floor_at := floor_top(blocks, p)
		var speed := Vector2(v.x, v.z).length()
		var heading := Vector3(v.x, 0.0, v.z).normalized()
		if floor_at <= NO_FLOOR * 0.5: # no floor under it: it falls
			segments.append([t, p, v, GRAVITY, spin])
			t += sqrt(2.0 * SHOT_FALL_DEPTH / GRAVITY)
			hit = t
			kind = "edge"
			break
		var rest := floor_at + rad
		var rolling := p.y <= rest + 0.001 and v.y <= 0.001
		if not rolling:
			var s := _landing_time(p.y - rest, v.y)
			var wall: float = wall_distance(blocks, Vector3(p.x, rest, p.z), heading) if speed > 0.01 else INF
			if wall - rad < speed * s: # a wall before the ground: swallowed in the air
				s = maxf(wall - rad, 0.0) / speed
				segments.append([t, p, v, GRAVITY, spin])
				hit = t + s
				var end := p + v * s + Vector3(0.0, -0.5 * GRAVITY * s * s, 0.0)
				kind = "wall"
				port = {"point": end + heading * rad, "normal": -heading, "hide": 2.0 * rad + SWALLOW}
				t = hit + float(port.hide) / speed
				break
			segments.append([t, p, v, GRAVITY, spin])
			spin += speed * s
			t += s
			p = p + v * s + Vector3(0.0, -0.5 * GRAVITY * s * s, 0.0)
			p.y = rest
			if not landed:
				land = p
				landed = true
			var bounce := SHOT_RESTITUTION * (GRAVITY * s - v.y)
			v = Vector3(v.x * SHOT_FRICTION, bounce if bounce >= SHOT_REST else 0.0, v.z * SHOT_FRICTION)
			continue
		if speed < 0.01: break
		# rolling on the floor
		var wall_at := wall_distance(blocks, Vector3(p.x, rest, p.z), heading)
		var edge := INF
		for step in int(SHOT_MAX_ROLL / SHOT_ROLL_STEP):
			var probe := p + heading * float(step + 1) * SHOT_ROLL_STEP
			var probe_floor := floor_top(blocks, Vector3(probe.x, rest, probe.z))
			if probe_floor <= NO_FLOOR * 0.5 or absf(probe_floor - floor_at) > 0.3:
				edge = float(step) * SHOT_ROLL_STEP
				break
		var run := maxf(minf(minf(wall_at - rad, edge), SHOT_MAX_ROLL), 0.0)
		segments.append([t, p, v, 0.0, spin])
		t += run / speed
		spin += run
		p = p + heading * run
		if wall_at - rad <= edge and wall_at - rad <= SHOT_MAX_ROLL:
			hit = t
			kind = "wall"
			port = {"point": p + heading * rad, "normal": -heading, "hide": 2.0 * rad + SWALLOW}
			t += float(port.hide) / speed
		elif edge < SHOT_MAX_ROLL:
			segments.append([t, p, v, GRAVITY, spin])
			t += sqrt(2.0 * SHOT_FALL_DEPTH / GRAVITY)
			hit = t
			kind = "edge"
		else:
			hit = t
		break
	if hit < 0.0: hit = t
	return {"segments": segments, "hit": hit, "end": t, "kind": kind, "port": port, "land": land, "landed": landed}

## A cannon ball at `s` seconds after the shot: on its planned path while it is in play (`active`: hurts), harmless (`lead`) while the wall swallows it.
static func _shot_pose(h: Dictionary, s: float, out: Pose) -> void:
	var plan: Dictionary = h.plan
	var cap := minf(float(h.life), float(h.period))
	var hit := minf(float(plan.hit), cap)
	var gone := minf(float(plan.end), cap)
	out.active = s < hit
	out.lead = not out.active and s < gone
	out.basis = Basis.IDENTITY
	out.position = h.pivot
	if s >= gone: return
	var segments: Array = plan.segments
	var index := segments.size() - 1
	while index > 0 and s < float((segments[index] as Array)[0]): index -= 1
	var segment: Array = segments[index]
	var dt := s - float(segment[0])
	var v0: Vector3 = segment[2]
	var g := float(segment[3])
	out.position = (segment[1] as Vector3) + v0 * dt + Vector3(0.0, -0.5 * g * dt * dt, 0.0)
	var flat := Vector2(v0.x, v0.z).length()
	if flat > 0.01:
		var heading := Vector3(v0.x, 0.0, v0.z).normalized()
		out.basis = Basis(Vector3.UP.cross(heading).normalized(), (float(segment[4]) + flat * dt) / maxf(float(h.rad), 0.1))

## Fills `out` with the pose of a mover or a shot at level clock `t`. Volumes (push, bumper) are static in their frame: pose = pivot and base.
static func pose(h: Dictionary, t: float, out: Pose) -> void:
	var tau := t + float(h.phase)
	var pivot: Vector3 = h.pivot
	var base: Basis = h.base
	out.active = true
	out.shake = 0.0
	out.lead = false
	out.position = pivot
	out.basis = base
	match h.k:
		"slide", "lift":
			out.position = pivot + (h.to as Vector3) * cycle(tau, h.period, h.pause, h.ease, float(h.get("hold", -1.0)))
		"spin":
			out.basis = base * axis_basis(h.axis, fposmod(float(h.rate) * tau, 360.0))
		"swing":
			var angle: float = lerpf(float(h.a0), float(h.a1), cycle(tau, h.period, h.pause, h.ease))
			out.basis = base * axis_basis(h.axis, angle)
		"blink":
			var total: float = float(h.on_time) + float(h.off_time)
			var m := fposmod(tau, total)
			out.active = m < float(h.on_time)
			out.lead = not out.active
			out.position = pivot + Vector3(0.0, blink_depth(h, m) * (1.0 if str(h.get("slot", "")) == GATE_SLOT else -1.0), 0.0) # a gone block falls away under its place, the start gate (a door) goes up instead
			var warn_from: float = float(h.on_time) - float(h.warn)
			if out.active and float(h.warn) > 0.0 and m > warn_from:
				out.shake = (m - warn_from) / float(h.warn)
				out.position = pivot + Vector3(sin(tau * 53.0), 0.0, cos(tau * 47.0)) * SHAKE_AMPLITUDE * out.shake
		"spikes":
			var hidden: Vector3 = pivot - base.y * float(h.rise)
			if float(h.period) <= 0.0:
				out.position = pivot
			else:
				var m := fposmod(tau, float(h.period))
				var warn: float = float(h.warn)
				var f := 0.0
				if m < warn: f = 0.0
				elif m < warn + SPIKE_MOVE: f = (m - warn) / SPIKE_MOVE
				elif m < warn + SPIKE_MOVE + float(h.up): f = 1.0
				elif m < warn + 2.0 * SPIKE_MOVE + float(h.up): f = 1.0 - (m - warn - SPIKE_MOVE - float(h.up)) / SPIKE_MOVE
				var lift := 0.0
				if m < warn: lift = SPIKE_PEEK * (0.5 + 0.5 * sin(tau * 40.0))
				out.position = hidden.lerp(pivot, 0.5 - 0.5 * cos(f * PI)) + base.y * lift
		"ball":
			var points: PackedVector3Array = h.path
			if points.size() < 2:
				out.active = false
				if not points.is_empty(): out.position = points[0]
				return
			var lengths: PackedFloat64Array = h.lengths
			var m := fposmod(tau, float(h.period))
			if m * float(h.speed) <= lengths[lengths.size() - 1]: _ball_place(h, m * float(h.speed), out)
			else: _ball_lead(h, m, out)
		"cannon":
			var s := fposmod(tau, float(h.period))
			if h.has("plan"):
				_shot_pose(h, s, out)
			else:
				out.active = s < float(h.life)
				out.position = pivot + (h.v as Vector3) * s + Vector3(0.0, -0.5 * GRAVITY * s * s, 0.0)
				out.basis = Basis.IDENTITY
		"laser":
			if (h.move as Vector3) != Vector3.ZERO: out.position = pivot + (h.move as Vector3) * cycle(tau, h.period, h.pause, h.ease)
			if float(h.rate) != 0.0: out.basis = base * axis_basis(h.axis, fposmod(float(h.rate) * tau, 360.0))
			_schedule(h, tau, out)
		"fire":
			_schedule(h, tau, out)

## A laser or fire jet with on / off: dangerous for `on` seconds, then off; the last `warn` seconds of `off` it warns (flicker, smoke),
## still harmless. `shake` is 0..1 through the warning.
static func _schedule(h: Dictionary, tau: float, out: Pose) -> void:
	var on_time: float = h.on_time
	var off_time: float = h.off_time
	if on_time <= 0.0 or off_time <= 0.0: return
	var m := fposmod(tau, on_time + off_time)
	out.active = m < on_time
	var warn_from: float = on_time + off_time - float(h.warn)
	if not out.active and float(h.warn) > 0.0 and m >= warn_from: out.shake = (m - warn_from) / float(h.warn)

## The launch a bumper or push volume gives a courier whose centre is at `centre` (level-local) and `volume_centre`: {v, override_xy, override_z}.
static func launch(h: Dictionary, centre: Vector3, volume_centre: Vector3) -> Dictionary:
	if h.k == "push":
		return {"v": h.v, "override_xy": true, "override_z": true}
	var away := (centre - volume_centre)
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.UP
	return {"v": Vector3(away.x * float(h.kick), maxf(away.y, 0.5) * float(h.up_speed), away.z * float(h.kick)), "override_xy": false, "override_z": true}

## ---- static geometry tests (no physics space needed: they work for hidden levels and on the authority) ----

## The half-spaces `n . x <= c` (block-local) of a box or wedge block; empty for a cylinder.
static func planes(b: Dictionary) -> Array:
	var half: Vector3 = (b.size as Vector3) * 0.5
	var list: Array = [[Vector3.RIGHT, half.x], [Vector3.LEFT, half.x]]
	match b.k:
		"box":
			list.append_array([[Vector3.UP, half.y], [Vector3.DOWN, half.y], [Vector3.BACK, half.z], [Vector3.FORWARD, half.z]])
		"wedge":
			list.append_array([[Vector3.DOWN, half.y], [Vector3.BACK, half.z], [Vector3(0.0, 1.0, -b.size.y / b.size.z), 0.0]])
		"cyl":
			list = [[Vector3.UP, half.y], [Vector3.DOWN, half.y]]
	return list

## Distance along the level-space ray (origin, direction) at which it enters block `b`; INF if it misses. A ray that starts inside returns 0.
static func ray_hit(b: Dictionary, origin: Vector3, direction: Vector3) -> float:
	var inverse := (b.xf as Transform3D).affine_inverse()
	var o := inverse * origin
	var d := inverse.basis * direction
	var t_enter := -INF
	var t_exit := INF
	for plane: Array in planes(b):
		var n: Vector3 = plane[0]
		var denom := n.dot(d)
		var num: float = float(plane[1]) - n.dot(o)
		if absf(denom) < 1e-9:
			if num < 0.0: return INF
			continue
		var t := num / denom
		if denom > 0.0: t_exit = minf(t_exit, t)
		else: t_enter = maxf(t_enter, t)
	if b.k == "cyl":
		var radius := float(b.d) * 0.5
		var a := d.x * d.x + d.z * d.z
		var c := o.x * o.x + o.z * o.z - radius * radius
		if a < 1e-9:
			if c > 0.0: return INF
		else:
			var bb := 2.0 * (o.x * d.x + o.z * d.z)
			var disc := bb * bb - 4.0 * a * c
			if disc < 0.0: return INF
			var root := sqrt(disc)
			t_enter = maxf(t_enter, (-bb - root) / (2.0 * a))
			t_exit = minf(t_exit, (-bb + root) / (2.0 * a))
	if t_enter > t_exit or t_exit < 0.0: return INF
	return maxf(t_enter, 0.0)

## The shape of a block (box, upright cylinder, wedge prism whose slope rises towards +Z).
static func make_shape(b: Dictionary) -> Shape3D:
	match b.k:
		"cyl":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(b.d) * 0.5
			cylinder.height = float(b.h)
			return cylinder
		"wedge":
			var half: Vector3 = (b.size as Vector3) * 0.5
			var hull := ConvexPolygonShape3D.new()
			hull.points = PackedVector3Array([
				Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z), Vector3(-half.x, -half.y, half.z),
				Vector3(half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z), Vector3(half.x, half.y, half.z)])
			return hull
	var box := BoxShape3D.new()
	box.size = b.size
	return box
