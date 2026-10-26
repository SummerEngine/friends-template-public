extends RefCounted
## A cannon of the race world (levels/hazards.gd `cannon`, drawn by style/shot_looks.gd `_cannon` in a `world: daylight` level) as a round machine instead of a bare tube, in the candy look:
## a hot pink striped vinyl barrel (diagonal white stripes, style/candy_prop.gdshader), a white rolled lip round a deep purple muzzle disc (the ball leaves through it), a rounded pink breech,
## and an amber axle through the middle with a white hub on each side, on a purple column over a round base disc (white rim, amber top with a pink ring). The barrel and axle are ONE mesh
## under the cannon's holder (they kick back with it, shot_looks.gd `pose`); the column and disc are ONE mesh in the level, on the wall that holds the cannon (or hanging
## under the barrel when no wall is near). One shared material (style/lathe_mesh.gd); the meshes are cached per size. Look only, client only.
const Lathe := preload("res://style/lathe_mesh.gd")
const DISC_HEIGHT := 0.3
const DISC_SCALE := 1.95       ## base disc radius over barrel radius
const HOVER := 0.55            ## m between the barrel's underside and the base disc of a cannon with no wall under it
const SIDES := 24

static var _meshes := {}

## Builds the look of a cannon under `holder` (barrel and axle) and `level_root` (column and disc). `dir`: the way it shoots (unit), `muzzle`: the middle of the muzzle,
## `rad`: the ball's radius, `radius`: the barrel's, `length`: its length, `down`: how far the wall under the breech is (m; negative: none near).
static func build(holder: Node3D, level_root: Node3D, dir: Vector3, muzzle: Vector3, rad: float, radius: float, length: float, down: float) -> void:
	var key := "barrel_%.3f_%.3f_%.3f" % [radius, length, rad]
	if not _meshes.has(key): _meshes[key] = _barrel(radius, length, rad)
	var side := Vector3.UP.cross(dir)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var barrel := MeshInstance3D.new()
	barrel.name = "CannonBarrel"
	barrel.mesh = _meshes[key]
	# the barrel's y axis along the shot, its x axis across it (the axle runs along it)
	var forward := dir.normalized()
	barrel.transform = Transform3D(Basis(side, forward, side.cross(forward)), muzzle)
	holder.add_child(barrel)
	var middle := muzzle - forward * length * 0.5
	var breech := muzzle - forward * length
	var foot_y := breech.y - down if down >= 0.0 else middle.y - radius - HOVER
	var column := middle.y - (foot_y + DISC_HEIGHT)
	var base_key := "base_%.3f_%.3f" % [radius, column]
	if not _meshes.has(base_key): _meshes[base_key] = _base(radius, column)
	var base := MeshInstance3D.new()
	base.name = "CannonBase"
	base.mesh = _meshes[base_key]
	base.position = Vector3(middle.x, foot_y, middle.z)
	level_root.add_child(base)

## The barrel (axis y, the muzzle at the origin, the breech at -length) and the axle through its middle along x.
static func _barrel(radius: float, length: float, rad: float) -> ArrayMesh:
	var build := Lathe.Build.new()
	var round_back := radius * 0.5
	var lip := radius + 0.07
	var bore := minf(rad + 0.05, radius - 0.04)
	var profile: Array = [[0.0, -length, Lathe.PINK_SOFT]]
	profile.append_array(Lathe.arc(radius - round_back, -length + round_back, round_back, -90.0, 0.0, Lathe.PINK_SOFT, 4))
	profile.append([radius, -0.2, Lathe.PINK_BAR]) # the body: striped vinyl up to the lip
	# muzzle: a rolled lip, the flat ring inside it, and the deep bore the ball comes out of
	profile.append([lip, -0.2, Lathe.WHITE])
	profile.append([lip, -0.06, Lathe.WHITE])
	profile.append_array(Lathe.arc(lip - 0.06, -0.06, 0.06, 0.0, 90.0, Lathe.WHITE, 3))
	profile.append([bore, 0.0, Lathe.WHITE])
	profile.append([bore, -0.04, Lathe.PURPLE_DEEP])
	profile.append([0.0, -0.04, Lathe.PURPLE_DEEP])
	build.lathe(Transform3D.IDENTITY, profile, SIDES)
	# the axle: a short amber shaft through the barrel's middle with a white hub standing a little out of each side
	var reach := radius + 0.12
	var shaft := radius * 0.3
	var hub := radius * 0.42
	var half: Array = [[shaft, 0.0, Lathe.AMBER], [shaft, reach - 0.1, Lathe.AMBER], [hub, reach - 0.1, Lathe.AMBER_DEEP], [hub, reach - 0.04, Lathe.WHITE]]
	half.append_array(Lathe.arc(hub - 0.04, reach - 0.04, 0.04, 0.0, 90.0, Lathe.WHITE, 2))
	half.append([hub * 0.5, reach, Lathe.WHITE])
	half.append([hub * 0.5, reach + 0.03, Lathe.AMBER])
	half.append([0.0, reach + 0.03, Lathe.AMBER])
	var axle := Lathe.mirror(half, 0.0)
	half.remove_at(0)
	axle.append_array(half)
	build.lathe(Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(0.0, -length * 0.5, 0.0)), axle, 16)
	return build.commit(Lathe.material())

## The round base disc (origin on the wall's top) and the column up to the axle's height (`column` m over the disc's top; none when it is not tall enough).
static func _base(radius: float, column: float) -> ArrayMesh:
	var build := Lathe.Build.new()
	var disc := radius * DISC_SCALE
	var rim := 0.1
	var profile: Array = [[0.0, -0.02, Lathe.WHITE], [disc - rim, -0.02, Lathe.WHITE]]
	profile.append_array(Lathe.arc(disc - rim, rim - 0.02, rim, -90.0, 0.0, Lathe.WHITE, 3))
	profile.append([disc, DISC_HEIGHT - rim, Lathe.WHITE])
	profile.append_array(Lathe.arc(disc - rim, DISC_HEIGHT - rim, rim, 0.0, 90.0, Lathe.WHITE, 3))
	profile.append([disc * 0.84, DISC_HEIGHT, Lathe.WHITE])
	profile.append([disc * 0.78, DISC_HEIGHT, Lathe.PINK])
	profile.append([disc * 0.6, DISC_HEIGHT, Lathe.PINK])
	profile.append([disc * 0.6, DISC_HEIGHT, Lathe.AMBER])
	profile.append([0.0, DISC_HEIGHT, Lathe.AMBER])
	build.lathe(Transform3D.IDENTITY, profile, SIDES)
	if column > 0.1:
		var post := radius * 0.72
		var top := DISC_HEIGHT + column
		var shaft: Array = [[0.0, DISC_HEIGHT - 0.05, Lathe.PURPLE_DEEP], [post + 0.16, DISC_HEIGHT - 0.05, Lathe.PURPLE_DEEP], [post, DISC_HEIGHT + 0.14, Lathe.PURPLE]]
		shaft.append([post, top, Lathe.PURPLE])
		shaft.append([0.0, top, Lathe.PURPLE])
		build.lathe(Transform3D.IDENTITY, shaft, 20)
	return build.commit(Lathe.material())
