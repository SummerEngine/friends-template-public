extends RefCounted
## The spinning bars and wheels of the race world (levels 29 / 30 / 31, style/race_hazard_looks.gd `_spin`) as rotating machines instead of sticks, in the candy look: every box part
## of a `spin` hazard becomes an inflatable-like bar (round, hot pink vinyl with diagonal white stripes from style/candy_prop.gdshader, gently pinched between the stripes' rhythm,
## plain rounded ends) fitted to a hard-plastic hub with amber collars where each bar leaves it; the hub is a smooth pink drum with an amber band under the shoulder, a white
## axle seat and an amber dome. No outline, no rim light, no dark parts.
##   spinner  (turns about y, bars lie flat)  the hub stands on a white base flange on the floor under the bars
##   wheel    (turns about x or z, standing)   the drum runs through the bars with a dome on both faces; no rim (nothing round it collides: you pass between the arms)
## Look only: the bars' collision boxes are untouched (a round bar sits inside its box) and the whole thing is ONE mesh child of the hazard's body, so it turns with it. The
## meshes are cached per bar layout (style/lathe_mesh.gd, one shared material), so the discs of a field share one mesh. Client only.
const Lathe := preload("res://style/lathe_mesh.gd")
const HUB_SCALE := 1.8         ## hub radius over bar radius
const BAR_HOVER := 0.25        ## m: the level data lifts a flat spinner's pivot this far over its floor (the collars clear it by 0.12); the flange still stands on the floor
const FLANGE := 0.6            ## m: how far the base flange reaches out past the hub
const SIDES := 16              ## bars, collars
const HUB_SIDES := 24
const PINCH := 0.1             ## the bar's radius shrinks by this share at its pinches ...
const PINCH_PITCH := 1.2       ## ... one every this many metres along it (an inflatable's pillow rhythm)
const BAR_STEP := 0.15         ## m between the profile samples of a bar
const END_ROUND := 0.55        ## share of the radius that the bar's ends are rolled over

static var _meshes := {}

## The look of a spin hazard whose collision boxes are `shapes` (CollisionShape3D children of the body, boxes only) turning about `axis` ("x", "y" or "z", the body's own
## axis): one MeshInstance3D, ready to be added to the body. Null when a shape is not a box.
static func build(shapes: Array[CollisionShape3D], axis: String) -> MeshInstance3D:
	var key := axis
	for shape_node in shapes:
		if not shape_node.shape is BoxShape3D: return null
		key += "|%s|%s" % [(shape_node.shape as BoxShape3D).size, shape_node.transform]
	if not _meshes.has(key): _meshes[key] = _mesh(shapes, axis)
	var visual := MeshInstance3D.new()
	visual.name = "RaceLook"
	visual.mesh = _meshes[key]
	return visual

static func _axis_vector(axis: String) -> Vector3:
	return Vector3.RIGHT if axis == "x" else (Vector3.BACK if axis == "z" else Vector3.UP)

## A transform whose y axis is `direction` (unit), at `origin`.
static func _along(direction: Vector3, origin := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis(Quaternion(Vector3.UP, direction)), origin)

static func _mesh(shapes: Array[CollisionShape3D], axis: String) -> ArrayMesh:
	var spin := _axis_vector(axis)
	var arms: Array = []     # {dir, centre, half, radius, offset}: offset = where the hub's centre lies along the bar from the bar's middle
	var bar_radius := 0.0
	var low := INF
	var high := -INF
	for shape_node in shapes:
		var size := (shape_node.shape as BoxShape3D).size
		var at := shape_node.transform
		var longest := 0
		for k in 3: if size[k] > size[longest]: longest = k
		var cross := INF
		for k in 3: if k != longest: cross = minf(cross, size[k])
		var direction := at.basis[longest].normalized()
		var arm := {"dir": direction, "centre": at.origin, "half": size[longest] * 0.5, "radius": cross * 0.5, "offset": -at.origin.dot(direction)}
		arms.append(arm)
		bar_radius = maxf(bar_radius, cross * 0.5)
		low = minf(low, at.origin.dot(spin) - cross * 0.5)
		high = maxf(high, at.origin.dot(spin) + cross * 0.5)
	var hub := bar_radius * HUB_SCALE
	var build := Lathe.Build.new()
	for arm: Dictionary in arms:
		bar(build, arm, hub)
	var spun := Transform3D(Basis(Quaternion(Vector3.UP, spin)), Vector3.ZERO)
	if axis == "y":
		build.lathe(spun, _spinner_hub(hub, low, high), HUB_SIDES)
	else:
		build.lathe(spun, _wheel_hub(hub, low, high), HUB_SIDES)
	return build.commit(Lathe.material())

# ------------------------------------------------------------------ the bar

static func bar(build: Lathe.Build, arm: Dictionary, hub: float) -> void:
	var half: float = arm.half
	var radius: float = arm.radius
	var hub_at: float = arm.offset            # the hub's centre along the bar (from its middle)
	var round_off := radius * END_ROUND
	# the body: striped vinyl, its radius pinched every PINCH_PITCH metres, the ends rolled over into a plain pink cap
	var profile: Array = [[0.0, -half, Lathe.PINK_SOFT]]
	profile.append_array(Lathe.arc(radius - round_off, -half + round_off, round_off, -90.0, 0.0, Lathe.PINK_SOFT, 4))
	var y := -half + round_off
	var end_y := half - round_off
	var steps := maxi(int(ceil((end_y - y) / BAR_STEP)), 1)
	for k in range(1, steps + 1):
		var at := lerpf(y, end_y, float(k) / steps)
		var pinch := 0.5 - 0.5 * cos(TAU * (at + half) / PINCH_PITCH)
		profile.append([radius * (1.0 - PINCH * pinch), at, Lathe.PINK_BAR])
	profile.append_array(Lathe.arc(radius - round_off, end_y, round_off, 0.0, 90.0, Lathe.PINK_SOFT, 4))
	profile.append([0.0, half, Lathe.PINK_SOFT])
	var xf := _along(arm.dir as Vector3, arm.centre as Vector3)
	build.lathe(xf, profile, SIDES)
	# collars where the bar leaves the hub (kept inside the bar's own span)
	for side in [-1.0, 1.0]:
		var at: float = hub_at + side * (hub + 0.1)
		if absf(at) + 0.2 < half: build.lathe(Transform3D(xf.basis, xf.origin + xf.basis.y * at), _collar(radius), SIDES)

## An amber hard-plastic ring round the bar, rolled over on both edges.
static func _collar(radius: float) -> Array:
	var outer := radius + 0.12
	var half := 0.14
	var bevel := 0.07
	var profile: Array = [[radius - 0.05, -half, Lathe.AMBER_DEEP], [outer - bevel, -half, Lathe.AMBER_DEEP]]
	profile.append_array(Lathe.arc(outer - bevel, -half + bevel, bevel, -90.0, 0.0, Lathe.AMBER, 2))
	profile.append([outer, half - bevel, Lathe.AMBER])
	profile.append_array(Lathe.arc(outer - bevel, half - bevel, bevel, 0.0, 90.0, Lathe.AMBER_LIGHT, 2))
	profile.append([radius - 0.05, half, Lathe.AMBER_LIGHT])
	return profile

# ------------------------------------------------------------------ the hub

## The upper half of a hub drum from `from` (its wall's start) to its top face at `top`: a pink wall, an amber band under the shoulder, the shoulder rolled over, a white axle seat and an
## amber dome. Walked upwards over the outside, from (hub, from) to the apex.
static func _hub_top(hub: float, from: float, top: float) -> Array:
	var seat := hub * 0.64
	var dome := seat - 0.06
	var roll := 0.16
	var profile: Array = [[hub, from, Lathe.PINK]]
	profile.append([hub, top - 0.46, Lathe.PINK])
	profile.append([hub, top - 0.30, Lathe.AMBER])
	profile.append([hub, top - roll, Lathe.PINK])
	profile.append_array(Lathe.arc(hub - roll, top - roll, roll, 0.0, 90.0, Lathe.PINK, 3))
	profile.append([seat, top, Lathe.WHITE])
	profile.append([seat, top + 0.05, Lathe.WHITE])
	profile.append([dome, top + 0.05, Lathe.WHITE])
	profile.append_array(Lathe.arc(0.0, top + 0.05, dome, 0.0, 90.0, Lathe.AMBER, 4))
	return profile

## A standing drum on a base flange: the flange (a chamfered white disc on the floor, reaching FLANGE past the drum), the drum up to over the bars and the cap.
static func _spinner_hub(hub: float, low: float, high: float) -> Array:
	var flange := hub + FLANGE
	var floor_y := low - BAR_HOVER - 0.03
	var profile: Array = [[0.0, floor_y, Lathe.WHITE], [flange - 0.12, floor_y, Lathe.WHITE]]
	profile.append_array(Lathe.arc(flange - 0.12, floor_y + 0.12, 0.12, -90.0, 0.0, Lathe.WHITE, 3))
	profile.append([flange, floor_y + 0.17, Lathe.WHITE])
	profile.append([hub + 0.1, floor_y + 0.36, Lathe.PINK_DEEP])
	profile.append_array(_hub_top(hub, floor_y + 0.36, high + 0.42))
	return profile

## A drum through the bars, a dome on both faces: the upper half mirrored about the middle.
static func _wheel_hub(hub: float, low: float, high: float) -> Array:
	var middle := (low + high) * 0.5
	var top := _hub_top(hub, middle, high + 0.34)
	var profile := Lathe.mirror(top, middle)
	top.remove_at(0)
	profile.append_array(top)
	return profile
