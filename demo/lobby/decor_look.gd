extends RefCounted
## Client-only dressing of the lobby yard that nobody touches: twinkling string lights over the yard, floor paint (a hopscotch in front of
## the spawn, arrows to the two circles, confetti dots, a rug in the sofa corner), a rainbow on the south wall, a sun on the east wall and
## a whiteboard with doodles. Flat paint lies on the floor and the wall faces, lights hang above reach; the paint is one mesh, the lights
## another. Colours follow the team's brand colours (lobby/playground_look.gd brand()).
const Layout = preload("res://network/walk_in_lobby.gd")
const Look = preload("res://lobby/playground_look.gd")
const BlockMesh = preload("res://style/block_mesh.gd")
const TWINKLE = preload("res://lobby/twinkle.gdshader")
const FriendsUi = preload("res://client/friends_ui.gd")
const WARM := Color("ffe2a8")
const SUNNY := Color("f2c230")
const MARKERS: Array[Color] = [Color("2c4bff"), Color("e8584f"), Color("2ec27e"), Color("1d2026")]
## Strands of lights across the yard: z, height at the walls, sag in the middle, bulbs. The show's lobby (a circle per round, boards 1.6 to 5 m up) keeps only the
## strand behind the boards: the others would cross their text from the camera behind the spawn.
const STRANDS := [[-11.2, 3.38, 0.4, 44], [-3.6, 3.35, 0.6, 44], [4.4, 3.35, 0.6, 44]]
const STRANDS_CROWDED := [[-11.2, 3.38, 0.4, 44]]
const SOUTH_FACE := 9.995   ## the south wall's inner face (lobby_space.gd wall_s)
const EAST_FACE := 17.295
const HOPSCOTCH := [[0.0, -0.2, 1], [0.0, -0.85, 2], [-0.33, -1.5, 3], [0.33, -1.5, 4], [0.0, -2.15, 5], [-0.33, -2.8, 6], [0.33, -2.8, 7], [0.0, -3.45, 8]]

static func dress(room: Node3D) -> void:
	var paint := BlockMesh.Batch.new()
	var crowded: bool = Layout.shown_pads().size() > 1 # the show's lobby: a circle per round where the hopscotch and the arrows would go
	if not crowded:
		_hopscotch(paint, room)
		_arrows(paint)
	_confetti(paint)
	_rug(paint)
	_rainbow(paint)
	_sun(paint)
	_whiteboard(paint)
	var node := Look._add(room, "YardPaint", paint, false)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights(room, crowded)

## A flat painted rectangle on the floor: centre (x, z), size, turn (radians), colour, height of its top over the floor.
static func _floor_box(batch: BlockMesh.Batch, at: Vector2, size: Vector2, turn: float, color: Color, top := 0.012) -> void:
	var xf := Transform3D(Basis(Vector3.UP, turn), Layout.ORIGIN + Vector3(at.x, top * 0.5, at.y))
	batch.box(xf, Vector3(size.x, top, size.y), 0.0, 1, Look.paint(0.7), Look.paint(0.7), color)

static func _floor_disc(batch: BlockMesh.Batch, at: Vector2, radius: float, color: Color, top := 0.012) -> void:
	batch.lathe(Transform3D(Basis(), Layout.ORIGIN + Vector3(at.x, top * 0.5, at.y)), radius, top, 0.0, Look.paint(0.7), Look.paint(0.7), color)

## The hopscotch between the spawn and the trampoline: white-edged squares in the team's colours, numbered, a round 8 at the far end.
static func _hopscotch(batch: BlockMesh.Batch, room: Node3D) -> void:
	for cell: Array in HOPSCOTCH:
		var at := Vector2(float(cell[0]), float(cell[1]))
		var number := int(cell[2])
		var fill := [Look.brand(0), SUNNY, Look.brand(1), Color("2fb7a5")][number % 4] as Color
		if number == 8:
			_floor_disc(batch, at, 0.36, Color.WHITE, 0.008)
			_floor_disc(batch, at, 0.31, fill)
		else:
			_floor_box(batch, at, Vector2(0.62, 0.62), 0.0, Color.WHITE, 0.008)
			_floor_box(batch, at, Vector2(0.54, 0.54), 0.0, fill)
		var label := Label3D.new()
		label.text = str(number)
		label.font = FriendsUi.inter(800)
		label.font_size = 96
		label.pixel_size = 0.0032
		label.modulate = Color.WHITE
		label.outline_size = 0
		label.shaded = true
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		label.position = Layout.ORIGIN + Vector3(at.x, 0.016, at.y)
		room.add_child(label)

## Three chevrons in each circle's colour, pointing from the spawn rows to its circle (the one the game shows).
static func _arrows(batch: BlockMesh.Batch) -> void:
	for pad: Dictionary in Layout.shown_pads():
		var target: Vector3 = (pad.center as Vector3) - Layout.ORIGIN
		var goal := Vector2(target.x, target.z)
		var from := Vector2(signf(goal.x) * 1.7, -0.4)
		var heading := (goal - from).normalized()
		var reach := from.distance_to(goal) - 2.1
		for k in 3:
			var tip := from + heading * reach * (0.25 + 0.33 * k)
			for side: float in [-1.0, 1.0]:
				var arm := heading.rotated(PI - side * 0.75)
				var middle := tip + arm * 0.24
				_floor_box(batch, middle, Vector2(0.5, 0.13), -arm.angle(), pad.color)

## Confetti dots in the team's colours on the open floor (a fixed pattern: the same on every screen).
static func _confetti(batch: BlockMesh.Batch) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 11
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var at := Vector2(random.randf_range(-5.6, 5.6), random.randf_range(-12.4, 7.0))
		if _busy(at): continue
		var color: Color = [Look.brand(0), SUNNY, Look.brand(1), Color.WHITE][placed % 4]
		_floor_disc(batch, at, random.randf_range(0.07, 0.15), color)
		placed += 1

## Floor the dots keep off: the circles, the hopscotch, the team name, the spawn rows, the trampoline and the easel.
static func _busy(at: Vector2) -> bool:
	for pad: Dictionary in Layout.shown_pads():
		var middle: Vector3 = (pad.center as Vector3) - Layout.ORIGIN
		if at.distance_to(Vector2(middle.x, middle.z)) < 2.4: return true
	if absf(at.x) < 1.0 and at.y > -4.0 and at.y < 0.4: return true
	if absf(at.x) < 3.2 and at.y > 2.4 and at.y < 4.4: return true
	if at.distance_to(Vector2(0.0, -9.4)) < 1.8: return true
	if absf(at.x) < 1.6 and at.y < -12.6: return true
	for slot in Layout.SPOTS.size():
		var spot := Layout.spawn(slot) - Layout.ORIGIN
		if at.distance_to(Vector2(spot.x, spot.z)) < 0.6: return true
	return false

## A round rug in the sofa corner.
static func _rug(batch: BlockMesh.Batch) -> void:
	_floor_disc(batch, Vector2(4.95, 8.35), 1.55, Look.brand(0).lightened(0.55), 0.006)
	_floor_disc(batch, Vector2(4.95, 8.35), 1.3, Color.WHITE.lerp(Look.brand(1), 0.25), 0.009)

## Paint on a wall face: `origin` the face point of the shape's (0, 0), `right` and `up` the face's axes, `out` its normal into the yard.
class WallPaint extends RefCounted:
	var batch: BlockMesh.Batch
	var origin: Vector3
	var right: Vector3
	var up: Vector3
	var out: Vector3

	func _init(target: BlockMesh.Batch, at: Vector3, face_right: Vector3, face_out: Vector3) -> void:
		batch = target
		origin = at
		right = face_right
		out = face_out
		up = Vector3.UP

	func point(p: Vector2, lift: float) -> Vector3:
		return origin + right * p.x + up * p.y + out * lift

	## A filled convex fan (or any polygon Geometry2D can triangulate).
	func polygon(points: PackedVector2Array, color: Color, lift: float) -> void:
		var indices := Geometry2D.triangulate_polygon(points)
		var g := batch.group(Look.paint(0.7))
		var base := g.v.size()
		for p: Vector2 in points: g.add(point(p, lift), out, p, color)
		for k in range(0, indices.size(), 3): g.triangle(base + indices[k], base + indices[k + 1], base + indices[k + 2], out)

	## A band `width` wide along `points`.
	func stroke(points: PackedVector2Array, width: float, color: Color, lift: float) -> void:
		var g := batch.group(Look.paint(0.5))
		for k in points.size() - 1:
			var a := points[k]
			var b := points[k + 1]
			var side := (b - a).normalized().orthogonal() * width * 0.5
			var base := g.v.size()
			for p: Vector2 in [a - side, a + side, b + side, b - side]: g.add(point(p, lift), out, p, color)
			g.quad(base, base + 1, base + 2, base + 3, out)

	## An arc band from radius `inner` to `outer` between two angles.
	func arc(centre: Vector2, inner: float, outer: float, from: float, to: float, color: Color, lift: float, steps := 28) -> void:
		var g := batch.group(Look.paint(0.7))
		var base := g.v.size()
		for k in steps + 1:
			var angle := lerpf(from, to, float(k) / steps)
			var direction := Vector2(cos(angle), sin(angle))
			g.add(point(centre + direction * inner, lift), out, direction, color)
			g.add(point(centre + direction * outer, lift), out, direction, color)
		for k in steps: g.quad(base + k * 2, base + k * 2 + 1, base + k * 2 + 3, base + k * 2 + 2, out)

static func _circle(centre: Vector2, radius: float, steps := 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in steps: points.append(centre + Vector2(cos(TAU * k / steps), sin(TAU * k / steps)) * radius)
	return points

## A rainbow over the free floor on the south wall (behind the spawn), in the team's colours.
static func _rainbow(batch: BlockMesh.Batch) -> void:
	var wall := WallPaint.new(batch, Layout.ORIGIN + Vector3(0.0, 0.0, SOUTH_FACE), Vector3.LEFT, Vector3.FORWARD)
	var bands: Array[Color] = [Look.brand(0), SUNNY, Look.brand(1), Color("2fb7a5")]
	for k in bands.size():
		wall.arc(Vector2(0.0, 0.95), 2.3 - 0.32 * (k + 1), 2.3 - 0.32 * k, 0.0, PI, bands[k], 0.01)
	for side: float in [-1.0, 1.0]:
		for puff: Array in [[Vector2(1.6, 0.95), 0.32], [Vector2(2.0, 1.05), 0.36], [Vector2(2.4, 0.95), 0.3]]:
			var p: Vector2 = puff[0]
			wall.polygon(_circle(Vector2(p.x * side, p.y), float(puff[1])), Color("dfe9f5"), 0.014)

## A sun on the east wall past the team wall.
static func _sun(batch: BlockMesh.Batch) -> void:
	var wall := WallPaint.new(batch, Layout.ORIGIN + Vector3(EAST_FACE, 0.0, 0.0), Vector3.BACK, Vector3.LEFT)
	var centre := Vector2(6.6, 2.1)
	wall.polygon(_circle(centre, 0.62, 28), SUNNY, 0.01)
	for k in 12:
		var angle := TAU * k / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		var across := direction.orthogonal() * 0.11
		wall.polygon(PackedVector2Array([centre + direction * 0.74 - across, centre + direction * 1.05, centre + direction * 0.74 + across]), SUNNY, 0.01)
	wall.polygon(_circle(centre + Vector2(-0.2, 0.15), 0.07, 12), Color("1d2026"), 0.014)
	wall.polygon(_circle(centre + Vector2(0.2, 0.15), 0.07, 12), Color("1d2026"), 0.014)
	var smile := PackedVector2Array()
	for k in 9: smile.append(centre + Vector2(cos(PI * (1.15 + 0.7 * k / 8.0)), sin(PI * (1.15 + 0.7 * k / 8.0))) * 0.32)
	wall.stroke(smile, 0.06, Color("1d2026"), 0.014)

## A whiteboard on the south wall with marker doodles: a smiley, a star, a game of noughts and crosses and a squiggle.
static func _whiteboard(batch: BlockMesh.Batch) -> void:
	var centre := Vector3(-7.0, 1.55, SOUTH_FACE)
	batch.box(Transform3D(Basis(), Layout.ORIGIN + centre + Vector3(0.0, 0.0, -0.02)), Vector3(2.7, 1.3, 0.04), 0.01, 1, "steel", "steel")
	batch.box(Transform3D(Basis(), Layout.ORIGIN + centre + Vector3(0.0, 0.0, -0.035)), Vector3(2.58, 1.18, 0.02), 0.0, 1, Look.paint(0.15), Look.paint(0.15), Color("fbfbfa"))
	batch.box(Transform3D(Basis(), Layout.ORIGIN + centre + Vector3(0.0, -0.7, -0.07)), Vector3(1.2, 0.04, 0.1), 0.01, 1, "steel", "steel")
	for k in 3:
		batch.box(Transform3D(Basis(), Layout.ORIGIN + centre + Vector3(-0.3 + k * 0.22, -0.66, -0.08)), Vector3(0.16, 0.035, 0.035), 0.01, 1, Look.paint(0.4), Look.paint(0.4), MARKERS[k])
	var board := WallPaint.new(batch, Layout.ORIGIN + Vector3(centre.x, centre.y, SOUTH_FACE), Vector3.LEFT, Vector3.FORWARD)
	var lift := 0.05
	# smiley
	var face := _circle(Vector2(-0.8, 0.1), 0.3, 20)
	face.append(face[0])
	board.stroke(face, 0.035, MARKERS[0], lift)
	board.polygon(_circle(Vector2(-0.9, 0.18), 0.035, 8), MARKERS[0], lift)
	board.polygon(_circle(Vector2(-0.7, 0.18), 0.035, 8), MARKERS[0], lift)
	var smile := PackedVector2Array()
	for k in 9: smile.append(Vector2(-0.8, 0.1) + Vector2(cos(PI * (1.2 + 0.6 * k / 8.0)), sin(PI * (1.2 + 0.6 * k / 8.0))) * 0.17)
	board.stroke(smile, 0.03, MARKERS[0], lift)
	# star
	var star := PackedVector2Array()
	for k in 11:
		var radius := 0.28 if k % 2 == 0 else 0.12
		var angle := PI * 0.5 + TAU * k / 10.0
		star.append(Vector2(0.05, 0.12) + Vector2(cos(angle), sin(angle)) * radius)
	board.stroke(star, 0.03, MARKERS[1], lift)
	# noughts and crosses
	var grid := Vector2(0.8, 0.08)
	for k: float in [-0.1, 0.1]:
		board.stroke(PackedVector2Array([grid + Vector2(k, -0.3), grid + Vector2(k, 0.3)]), 0.025, MARKERS[3], lift)
		board.stroke(PackedVector2Array([grid + Vector2(-0.3, k), grid + Vector2(0.3, k)]), 0.025, MARKERS[3], lift)
	for cell: Vector2 in [Vector2(-0.2, 0.2), Vector2(0.0, 0.0), Vector2(0.2, -0.2)]:
		board.stroke(PackedVector2Array([grid + cell + Vector2(-0.06, -0.06), grid + cell + Vector2(0.06, 0.06)]), 0.025, MARKERS[1], lift)
		board.stroke(PackedVector2Array([grid + cell + Vector2(-0.06, 0.06), grid + cell + Vector2(0.06, -0.06)]), 0.025, MARKERS[1], lift)
	var nought := _circle(grid + Vector2(0.2, 0.2), 0.065, 12)
	nought.append(nought[0])
	board.stroke(nought, 0.025, MARKERS[2], lift)
	# squiggle
	var wave := PackedVector2Array()
	for k in 25: wave.append(Vector2(-1.05 + k * 0.08, -0.38 + sin(k * 0.9) * 0.05))
	board.stroke(wave, 0.03, MARKERS[2], lift)

## Strands of twinkling bulbs from wall top to wall top: a dark cord and bulbs in the team's colours and warm white (one mesh).
static func _lights(room: Node3D, crowded := false) -> void:
	var cords := BlockMesh.Batch.new()
	var bulbs := BlockMesh.Batch.new()
	var colors: Array[Color] = [WARM, Look.brand(0), WARM, SUNNY, WARM, Look.brand(1)]
	var count := 0
	for strand: Array in (STRANDS_CROWDED if crowded else STRANDS):
		var z := float(strand[0])
		var top := float(strand[1])
		var sag := float(strand[2])
		var steps := 40
		var previous := Vector3(-17.25, top, z)
		for k in range(1, steps + 1):
			var t := float(k) / steps
			var point := Vector3(lerpf(-17.25, 17.25, t), top - sag * 4.0 * t * (1.0 - t), z)
			var middle := (previous + point) * 0.5
			var along := (point - previous)
			cords.box(Transform3D(Basis(Vector3.BACK, atan2(along.y, along.x)), Layout.ORIGIN + middle), Vector3(along.length() + 0.01, 0.02, 0.02), 0.0, 1, Look.paint(0.6), Look.paint(0.6), Color("3a3d44"))
			previous = point
		for k in int(strand[3]):
			var t := (k + 0.5) / float(strand[3])
			var point := Vector3(lerpf(-17.25, 17.25, t), top - sag * 4.0 * t * (1.0 - t) - 0.07, z)
			var color := colors[count % colors.size()]
			color.a = fposmod(count * 0.618, 1.0)
			bulbs.box(Transform3D(Basis(), Layout.ORIGIN + point), Vector3(0.11, 0.15, 0.11), 0.05, 2, "bulb", "bulb", color)
			count += 1
	Look._add(room, "LightCords", cords, false)
	var node := MeshInstance3D.new()
	node.name = "LightBulbs"
	var material := ShaderMaterial.new()
	material.shader = TWINKLE
	node.mesh = bulbs.commit({"bulb": material})
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(node)
