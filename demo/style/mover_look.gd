extends RefCounted
## A platform that carries the courier (a `slide` / `lift` without `hit` of a `world: daylight` level, style/race_hazard_looks.gd `_platform`) as a MACHINE of the block kit's platform language: the
## same chamfered slab as a stone (BlockKit.floor_block) but in the amber of BlockKit.FLOORS.mover (the obstacles that move are amber, the floor blue), with
## ONE big white chevron inlaid in every tile cell, all of one size and one way: the way the platform goes next (the arrows turn about the platform's middle while it stands at the end of its run, so they
## always point where it is about to move), and a thicker underside: a deep purple chassis under the slab with a rounded hover pad at each corner (a white pod with an amber disc under it). A lift's up / down
## chevron stands on each of the slab's four sides instead (it flips about the horizontal axis). The platform is ONE mesh per size, the arrows another per size and way (`Arrows`, a child of the
## platform mesh), both on the one shared vertex-colour material (BlockKit.material), children of the collision shape so they move with the body.
## Look only: the collision is the body's box, untouched: the slab's top, its rim and the tiles stand where a stone's do (at most BlockKit.RIM_TOP over it), the slab and the underside hang below the box.
## Every part is fused with the one above it: the chassis starts inside the slab, the pods inside the chassis, the disc inside its pod, a chevron stands in its tile. Client only.
const BlockMesh := preload("res://style/block_mesh.gd")
const BlockKit := preload("res://style/block_kit.gd")
const SLAB_THICK := 0.8        ## m: the slab's thickness at least (the collision box may be thinner: the slab hangs below it)
const CHASSIS_INSET := 0.3     ## m: the chassis stands this far in from the slab's edge
const CHASSIS_HEIGHT := 0.42   ## m: from its underside to the inside of the slab
const CHASSIS_BURY := 0.1      ## m: how far its top goes up into the slab
const CHASSIS_BEVEL := 0.08
const POD_RADIUS := 0.42
const POD_HEIGHT := 0.3
const POD_BURY := 0.08         ## m: how far a pod's top goes up into the chassis
const POD_BEVEL := 0.07
const DISC_RADIUS := 0.3       ## m: the light disc under a pod
const DISC_HEIGHT := 0.06
const POD_EDGE := 0.14         ## m: a pod's rim keeps this far in from the chassis's edge
const ARROW_LIFT := 0.014      ## m: a chevron stands this far over its tile (its foot ARROW_FOOT under the surface)
const ARROW_FOOT := 0.03
const ARROW_LONG := 0.42       ## a chevron's arm length across the travel, and its thickness along it, as shares of the tile
const ARROW_THICK := 0.22
const ARROW_REST := 0.15       ## s: a platform that has not moved for this long is at the end of its run: its arrows turn
const ARROW_STEP := 0.0005     ## m: a body that moved this far in a frame is moving
const CandyLook := preload("res://style/candy_look.gd")
const CHASSIS_COLOUR := CandyLook.PROP_PURPLE_DEEP
const POD_COLOUR := CandyLook.PROP_WHITE
const DISC_COLOUR := CandyLook.PROP_AMBER_LIGHT
const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 2

static var _meshes := {}
static var _arrows := {}

## The look of the platform box `shape_node` (a child of `body`, which carries the metas `pivot` and `travel`: where its run starts and the offset it goes, level space); null for a shape the look does not dress.
static func build(shape_node: CollisionShape3D, body: Node3D) -> MeshInstance3D:
	if not shape_node.shape is BoxShape3D: return null
	var travel: Vector3 = body.get_meta("travel", Vector3.ZERO)
	var size := (shape_node.shape as BoxShape3D).size
	var way := shape_node.transform.basis.inverse() * travel # in the shape's own space
	var axis := AXIS_Y if absf(way.y) > maxf(absf(way.x), absf(way.z)) else (AXIS_X if absf(way.x) >= absf(way.z) else AXIS_Z)
	var along := Vector3.UP if axis == AXIS_Y else (Vector3.RIGHT if axis == AXIS_X else Vector3.BACK) # the way the arrows' mesh points
	var key := "%s|%d" % [str(size), axis]
	if not _meshes.has(size): _meshes[size] = _mesh(size)
	if not _arrows.has(key): _arrows[key] = _arrow_mesh(size, axis)
	var visual := MeshInstance3D.new()
	visual.name = "RaceLook"
	visual.mesh = _meshes[size]
	var top := size.y * 0.5
	var arrows := Arrows.new()
	arrows.name = "Arrows"
	arrows.mesh = _arrows[key]
	arrows.position = Vector3(0.0, top - 0.5 if axis == AXIS_Y else top, 0.0) # the arrows' mesh is built round this point: a lift's arrows turn about their own middle
	arrows.body = body
	arrows.way = shape_node.transform.basis * along
	arrows.spin = Vector3.BACK if axis == AXIS_Y else Vector3.UP
	arrows.pivot = body.get_meta("pivot", Vector3.ZERO)
	arrows.travel = travel
	arrows.facing = arrows.at_rest()
	visual.add_child(arrows)
	return visual

## The platform: slab, rim, tiles, chassis and pods (no arrows).
static func _mesh(size: Vector3) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var palette: Dictionary = BlockKit.FLOORS.mover
	var top := size.y * 0.5
	var thick := maxf(size.y, SLAB_THICK)
	var slab_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, top - thick * 0.5, 0.0))
	var slab := Vector3(size.x, thick, size.z)
	var half := slab * 0.5
	if not BlockKit.floor_block(batch, slab_xf, slab, "mover", null, [[], [], [], []]):
		batch.prism(BlockKit.KEY, slab_xf, Vector3.ZERO, half, [[0.1, -half.y], [0.0, -half.y + 0.1], [0.0, half.y - 0.1], [0.1, half.y]], PackedFloat32Array([0.1, 0.1, 0.1, 0.1]), Color(str(palette.side), BlockKit.BRICK), Color(str(palette.a)))
	_underside(batch, Vector2(half.x, half.z), top - thick)
	return batch.commit({BlockKit.KEY: BlockKit.material()})

## The arrows of a platform that goes along `axis` (x, z or, for a lift, y), pointing the positive way: relative to the point the node stands on (the top of the tiles; a lift's, the height of its side arrows).
static func _arrow_mesh(size: Vector3, axis: int) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var top := size.y * 0.5
	var thick := maxf(size.y, SLAB_THICK)
	var slab_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, top - thick * 0.5, 0.0))
	var slab := Vector3(size.x, thick, size.z)
	var arrow := Color(str(BlockKit.FLOORS.mover.arrow))
	if axis == AXIS_Y: _side_arrows(batch, slab, Vector3(0.0, top - 0.5, 0.0), arrow)
	else: _tile_arrows(batch, slab_xf, slab, axis, arrow)
	return batch.commit({BlockKit.KEY: BlockKit.material()})

## The chassis under the slab (its underside at `slab_bottom`, `half` the slab's half extents x, z) and a hover pad under each corner of it.
static func _underside(batch: BlockMesh.Batch, half: Vector2, slab_bottom: float) -> void:
	var inset := minf(CHASSIS_INSET, minf(half.x, half.y) * 0.3)
	var body := Vector3(half.x - inset, 0.0, half.y - inset)
	var low := slab_bottom - CHASSIS_HEIGHT + CHASSIS_BURY
	var bevel := CHASSIS_BEVEL
	var rings: Array = [[bevel, low], [bevel * 0.2929, low + bevel * 0.2929], [0.0, low + bevel], [0.0, slab_bottom + CHASSIS_BURY]]
	batch.prism(BlockKit.KEY, Transform3D.IDENTITY, Vector3.ZERO, body, rings, PackedFloat32Array([0.1, 0.1, 0.1, 0.1]), CHASSIS_COLOUR, CHASSIS_COLOUR, 1)
	var reach := Vector2(body.x - POD_RADIUS - POD_EDGE, body.z - POD_RADIUS - POD_EDGE)
	var pod_top := low + POD_BURY
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var at := Vector3(sx * maxf(reach.x, 0.0), 0.0, sz * maxf(reach.y, 0.0))
			batch.lathe(Transform3D(Basis.IDENTITY, at + Vector3(0.0, pod_top - POD_HEIGHT * 0.5, 0.0)), POD_RADIUS, POD_HEIGHT, POD_BEVEL, BlockKit.KEY, BlockKit.KEY, POD_COLOUR)
			batch.lathe(Transform3D(Basis.IDENTITY, at + Vector3(0.0, pod_top - POD_HEIGHT, 0.0)), DISC_RADIUS, DISC_HEIGHT, 0.02, BlockKit.KEY, BlockKit.KEY, DISC_COLOUR)

## One chevron in every tile of the slab's grid, all alike, pointing along `axis` (x or z) the positive way.
static func _tile_arrows(batch: BlockMesh.Batch, slab_xf: Transform3D, slab: Vector3, axis: int, colour: Color) -> void:
	var grid := BlockKit.tile_grid(slab_xf, slab)
	if grid.is_empty(): return
	var along: Vector3 = grid.axis_x if axis == AXIS_X else grid.axis_z
	var across: Vector3 = grid.axis_z if axis == AXIS_X else grid.axis_x
	var t := float(grid.t)
	var raise := Vector3(0.0, float(grid.top), 0.0)
	for i in int(grid.nx):
		for j in int(grid.nz):
			var centre: Vector3 = grid.origin + grid.axis_x * float(grid.pitch) * float(i) + grid.axis_z * float(grid.pitch) * float(j) - raise
			_chevron(batch, centre, along, across, Vector3.UP, t * ARROW_LONG, t * ARROW_THICK, colour)

## A lift's arrows: an up chevron on the middle of each of the slab's four sides under the rim, centred on height `at.y` (x, z the slab's middle).
static func _side_arrows(batch: BlockMesh.Batch, slab: Vector3, at: Vector3, colour: Color) -> void:
	var half := slab * 0.5
	for face in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var n: Vector3 = face
		_chevron(batch, Vector3(n.x * half.x, 0.0, n.z * half.z), Vector3.UP, Vector3.UP.cross(n), n, 0.22, 0.12, colour)

## One chevron (a V of two arms) in the plane that has normal `n`, centred on `at`: the tip points along `heading`, the arms spread along `across`, `arm` long across and `thick` thick along the heading,
## raised ARROW_LIFT over the face, its walls going ARROW_FOOT under it.
static func _chevron(batch: BlockMesh.Batch, at: Vector3, heading: Vector3, across: Vector3, n: Vector3, arm: float, thick: float, colour: Color) -> void:
	var tip := (arm + thick) * 0.5
	# the outline, going round once: tip, the upper arm's outer end and inner end, the inner notch, the lower arm's inner end and outer end (in heading / across)
	var outline: Array[Vector2] = [Vector2(tip, 0.0), Vector2(tip - arm, arm), Vector2(tip - arm - thick, arm), Vector2(tip - thick, 0.0), Vector2(tip - arm - thick, -arm), Vector2(tip - arm, -arm)]
	var g := batch.group(BlockKit.KEY)
	var high: Array[int] = []
	var low: Array[int] = []
	for p: Vector2 in outline:
		var flat := at + heading * p.x + across * p.y
		high.append(g.add(flat + n * ARROW_LIFT, n, Vector2.ZERO, colour))
		low.append(g.add(flat - n * ARROW_FOOT, n, Vector2.ZERO, colour))
	g.quad(high[0], high[1], high[2], high[3], n)
	g.quad(high[0], high[3], high[4], high[5], n)
	for e in 6:
		var f := (e + 1) % 6
		var mid := (g.v[high[e]] + g.v[high[f]]) * 0.5
		var wall := (g.v[high[f]] - g.v[high[e]]).cross(n)
		var outward := mid - (at + n * ARROW_LIFT)
		if wall.dot(outward) < 0.0: wall = -wall
		wall = wall.normalized()
		var base := g.v.size()
		g.add(g.v[high[e]], wall, Vector2.ZERO, colour)
		g.add(g.v[high[f]], wall, Vector2.ZERO, colour)
		g.add(g.v[low[f]], wall, Vector2.ZERO, colour)
		g.add(g.v[low[e]], wall, Vector2.ZERO, colour)
		g.quad(base, base + 1, base + 2, base + 3, wall)

## The arrows of a platform: they point the way the body is about to go. `way` is the level-space unit vector the arrows' mesh points along (the positive way), `facing` (+1 / -1) which way they
## point now. A body that moves points them along its motion; one that has stood still for ARROW_REST s is at an end of its run (its position is `pivot` + `travel` * progress, 0 at the start, 1 at the far
## end): they point the way it will go from there, towards the far end from the first half, back from the second.
class Arrows extends MeshInstance3D:
	var body: Node3D
	var way := Vector3.RIGHT
	var spin := Vector3.UP
	var pivot := Vector3.ZERO
	var travel := Vector3.ZERO
	var facing := 1.0
	var _last := Vector3.ZERO
	var _still := 0.0

	func _ready() -> void:
		_last = body.position
		_turn()

	func _process(delta: float) -> void:
		var step := (body.position - _last).dot(way)
		_last = body.position
		if absf(step) > ARROW_STEP:
			facing = signf(step)
			_still = 0.0
		else:
			_still += delta
			if _still > ARROW_REST: facing = at_rest()
		_turn()

	## The way (+1 / -1 along `way`) a body standing still at its current place goes next.
	func at_rest() -> float:
		var length := travel.length_squared()
		if length < 1e-6: return 1.0
		var outbound := signf(way.dot(travel))
		return outbound if (body.position - pivot).dot(travel) / length < 0.5 else -outbound

	func _turn() -> void:
		basis = Basis(spin, 0.0 if facing > 0.0 else PI)
