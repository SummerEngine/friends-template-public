extends RefCounted
## The select plate of a lobby circle (client/walk_in_markers.gd): a flat round plate let into the floor, NOT the race levels' bounce pad (no raised button, no orange / yellow rings): a cream
## rim (the pad family's cream, rounded) round a flush face in ONE colour per kind of round (race mint, survival blue, final purple, THE SHOW gold, the wardrobe pink), a cream stud in the
## middle and an inlaid ring that lights up (white) while somebody stands on the plate and pulses while its countdown runs. Standing on it sinks the face a little.
## The players on the circle show as lamps: little domes on the rim's front arc, each lit in its player's colour.
## Look only: no collision, the circle's zone is the game's (network/walk_in_lobby.gd).
##   PickPlate.build(parent, radius, kind) -> Plate     origin on the floor in the circle's middle; `radius` the rim's outer radius
##   Plate.paint(lit, counting, clock, delta)           state: resting, somebody (or this player) on it, countdown running
##   Plate.set_lamps(colours)                           one dome per seat, `Color` lit / null off, on the rim's front arc
##   KINDS[kind].band                                   the colour of the kind's sign plate (lobby/lobby_sign.gd)
const PadLook := preload("res://style/pad_look.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const KINDS := {
	"race": {"face": Color("#37c293"), "glow": Color("#c9ffe9"), "band": ShowTheme.MINT},
	"survival": {"face": Color("#3470f0"), "glow": Color("#cfe0ff"), "band": ShowTheme.BLUE},
	"final": {"face": Color("#6c4cd6"), "glow": Color("#ded4ff"), "band": ShowTheme.PURPLE},
	"show": {"face": Color("#e0a21c"), "glow": Color("#fff0b8"), "band": ShowTheme.GOLD},
	"wardrobe": {"face": Color("#ee7fa0"), "glow": Color("#ffe3ec"), "band": Color("#ee7fa0")},
}
const RIM_WIDTH := 0.15         ## m: the cream rim
const RIM_TOP := 0.05           ## m: the rim's top over the floor (its foot is ON the tile top)
const FACE_TOP := 0.022         ## m: the face's top over the floor at rest: 2.8 cm under the rim's top, flush with the floor for a foot
const FACE_TUCK := 0.03         ## m: the face runs this far under the rim
const FACE_DEPTH := 0.04        ## m: the face's side runs this far under the floor's top (a press, at most 2 cm, never shows its underside)
const STUD_RADIUS := 0.34
const STUD_TOP := 0.032         ## m: the stud's top over the face
const GLOW_FROM := 0.95         ## m: the inlaid ring
const GLOW_TO := 1.17
const GLOW_RISE := 0.006
const PRESS_LIT := 0.012        ## m: how far the face sinks while somebody stands on the plate ...
const PRESS_COUNT := 0.02       ## ... and while the countdown runs
const EASE := 14.0              ## per second: how fast the plate follows its state
const LAMP_RADIUS := 0.055      ## m: a lamp dome (the rim is 0.15 m wide)
const LAMP_STEP := 0.17         ## rad between two lamps on the arc
const LAMP_OFF := Color("#cdbf9c") ## an unlit lamp: a little darker than the rim
const LAMP_BASE := 0.045        ## m: the dome's foot (the rim's top is 0.05 m, so the dome stands in it by 5 mm)
const SIDES := 48

## The plate under `parent` (a Node3D standing on the floor in the middle of the circle) of `kind` (a key of KINDS).
static func build(parent: Node3D, radius: float, kind: String) -> Plate:
	var look: Dictionary = KINDS.get(kind, KINDS.race)
	var face: Color = look.face
	var plate := Plate.new()
	plate.name = "Plate"
	var well := radius - RIM_WIDTH
	# the rim: a rounded cream ring on the floor
	var rim: Array = [[radius, 0.0, Vector2(1.0, 0.0), PadLook.CREAM], [radius, RIM_TOP - 0.03, Vector2(1.0, 0.0), PadLook.CREAM]]
	for k in range(1, 4):
		var angle := PI * 0.5 * float(k) / 3.0
		rim.append([radius - 0.03 + cos(angle) * 0.03, RIM_TOP - 0.03 + sin(angle) * 0.03, Vector2(cos(angle), sin(angle)), PadLook.CREAM])
	rim.append([well + 0.02, RIM_TOP, Vector2(0.0, 1.0), PadLook.CREAM])
	for k in range(1, 3):
		var angle := PI * 0.5 + PI * 0.5 * float(k) / 2.0
		rim.append([well + 0.02 + cos(angle) * 0.02, RIM_TOP - 0.02 + sin(angle) * 0.02, Vector2(cos(angle), sin(angle)), PadLook.CREAM])
	rim.append([well, 0.0, Vector2(-1.0, 0.0), PadLook.CREAM])
	var base := BlockMesh.Batch.new()
	PadLook.revolve(base.group("base"), rim, SIDES)
	plate.add_child(_node("Rim", base.commit({"base": _gloss_material()})))
	# the face: a flush disc with a cream stud, sinking as one
	var reach := well + FACE_TUCK
	# (profiles run with the solid on their left: the underside outwards, the side up, the top inwards)
	var disc: Array = [[0.0, -FACE_DEPTH, Vector2(0.0, -1.0), face], [reach, -FACE_DEPTH, Vector2(0.0, -1.0), face], [reach, -FACE_DEPTH, Vector2(1.0, 0.0), face], [reach, FACE_TOP - 0.015, Vector2(1.0, 0.0), face], [reach - 0.015, FACE_TOP, Vector2(0.0, 1.0), face], [0.0, FACE_TOP, Vector2(0.0, 1.0), face]]
	var stud: Array = [[STUD_RADIUS, FACE_TOP - 0.01, Vector2(1.0, 0.0), PadLook.CREAM], [STUD_RADIUS, FACE_TOP + STUD_TOP - 0.03, Vector2(1.0, 0.0), PadLook.CREAM]]
	for k in range(1, 4):
		var angle := PI * 0.5 * float(k) / 3.0
		stud.append([STUD_RADIUS - 0.03 + cos(angle) * 0.03, FACE_TOP + STUD_TOP - 0.03 + sin(angle) * 0.03, Vector2(cos(angle), sin(angle)), PadLook.CREAM])
	stud.append([0.0, FACE_TOP + STUD_TOP, Vector2(0.0, 1.0), PadLook.CREAM])
	var top := BlockMesh.Batch.new()
	PadLook.revolve(top.group("face"), disc, SIDES)
	PadLook.revolve(top.group("face"), stud, SIDES)
	var face_node := _node("Face", top.commit({"face": _gloss_material()}))
	plate.add_child(face_node)
	# the inlaid ring: flat, unshaded, its colour is the state
	var ring: Array = [[GLOW_TO, FACE_TOP + GLOW_RISE, Vector2(0.0, 1.0), Color.WHITE], [GLOW_FROM, FACE_TOP + GLOW_RISE, Vector2(0.0, 1.0), Color.WHITE]]
	var glow := BlockMesh.Batch.new()
	PadLook.revolve(glow.group("glow"), ring, SIDES)
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.vertex_color_use_as_albedo = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glow_node := _node("Glow", glow.commit({"glow": paint}))
	face_node.add_child(glow_node)
	plate.face = face_node
	plate.paint_material = paint
	plate.rest = face.lightened(0.16)
	plate.lit = look.glow
	paint.albedo_color = plate.rest
	plate.arc = radius - RIM_WIDTH * 0.5
	parent.add_child(plate)
	return plate

## The plate's glossy hard plastic: PadLook's collar material (vertex colours, hard plastic) at roughness 0.05, a clear wet sheen with a little specular lift.
static var _gloss: StandardMaterial3D
static func _gloss_material() -> StandardMaterial3D:
	if _gloss == null:
		_gloss = PadLook._collar_material().duplicate()
		_gloss.roughness = 0.05
		_gloss.metallic_specular = 1.0
	return _gloss

static func _node(label: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## The node: moves its face and lights its ring and lamps.
class Plate extends Node3D:
	var face: MeshInstance3D
	var paint_material: StandardMaterial3D
	var rest := Color.WHITE        ## the ring's colour at rest
	var lit := Color.WHITE         ## ... and lit
	var arc := 1.45                ## m: the radius the lamps stand on
	var _lamps: Array[MeshInstance3D] = []
	var _depth := 0.0
	var _mix := 0.0
	static var _dome: SphereMesh

	static func _lamp_mesh() -> SphereMesh:
		if _dome == null:
			_dome = SphereMesh.new()
			_dome.radius = LAMP_RADIUS
			_dome.height = LAMP_RADIUS
			_dome.is_hemisphere = true
			_dome.radial_segments = 12
			_dome.rings = 4
		return _dome

	## `lit`: somebody stands on it; `counting`: its countdown runs (`clock`: seconds, for the pulse); `delta`: seconds since the last call (0: jump to the state).
	func paint(on: bool, counting: bool, clock: float, delta: float) -> void:
		var want := 0.0
		var glow := 0.0
		if counting:
			want = PRESS_COUNT
			glow = 0.55 + 0.45 * (0.5 + 0.5 * sin(clock * TAU * 2.0))
		elif on:
			want = PRESS_LIT
			glow = 0.8
		var follow := 1.0 if delta <= 0.0 else 1.0 - exp(-EASE * delta)
		_depth = lerpf(_depth, want, follow)
		_mix = lerpf(_mix, glow, follow)
		face.position.y = -_depth
		paint_material.albedo_color = rest.lerp(lit, _mix)

	## One lamp per entry of `colours` (a Color: lit, null: off), a row of domes on the rim's front arc, the middle one in front of the circle.
	func set_lamps(colours: Array) -> void:
		while _lamps.size() < colours.size():
			var lamp := MeshInstance3D.new()
			lamp.name = "Lamp"
			lamp.mesh = _lamp_mesh()
			var paint := StandardMaterial3D.new()
			paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lamp.material_override = paint
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lamp)
			_lamps.append(lamp)
		while _lamps.size() > colours.size(): _lamps.pop_back().queue_free()
		for index in _lamps.size():
			var angle := (float(index) - (_lamps.size() - 1) * 0.5) * LAMP_STEP
			_lamps[index].position = Vector3(sin(angle) * arc, LAMP_BASE, cos(angle) * arc)
			var colour: Variant = colours[index]
			(_lamps[index].material_override as StandardMaterial3D).albedo_color = colour if colour is Color else LAMP_OFF
