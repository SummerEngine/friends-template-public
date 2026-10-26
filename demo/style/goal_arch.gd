extends RefCounted
## The arch over the goal and the start (the slots `arch_finish` / `arch_start`, style/slot_frames.gd draws them in every look but the comic one): two round columns on stepped plinths,
## a beam between them wrapped in a rounded frame that carries the sign (the logo and the team name, printed by SlotFrames on BOTH faces, so the runner reads it from
## either side), and a warm lamp on top of each column. Built from lathed drums (rounded rims) and rounded boxes (style/block_mesh.gd) in one mesh with two surfaces:
## the body in vertex colours (the brand accent on the columns and the beam, white and amber on the trims) and the lamps. The mesh is made once per arch size, drop and accent.
##   frame space    the slot's own: the sign's centre at the origin, +Z the way it faces; the beam's core z -0.4 .. 0, the sign's print at z +0.012 (SlotFrames._quad)
##   `inner`        the width of the sign between the columns: SlotFrames prints its face at this size
const PadLook := preload("res://style/pad_look.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const DEPTH := 0.4               ## m: the beam's core (SlotFrames.ARCH_DEPTH)
const COLUMN := 0.36             ## m: a column's radius ...
const PLINTH := 0.62             ## ... its plinth's, and the capital's (so the whole arch stays inside the slot's width)
const CAPITAL := 0.55
const SIDES := 18
const BAR := 0.16                ## m: the frame bars over and under the sign
const CandyLook := preload("res://style/candy_look.gd")
const CREAM := CandyLook.PROP_WHITE
const TAN := CandyLook.PROP_AMBER
const LAMP_GLOW := Color("#ffd35a")

static var _meshes := {}
static var _body_material: StandardMaterial3D
static var _lamp_material: StandardMaterial3D

## The width of the sign between the columns for a beam `slot_width` wide.
static func inner(slot_width: float) -> float:
	return 2.0 * (slot_width * 0.5 - PLINTH - COLUMN + 0.16)

## Adds the arch to `holder` (frame space). `size` the slot's size, `drops` how far the floor is under the beam's underside at the left and the right column (m, <= 0 for no
## floor there: that column is left out), `accent` the colour of the columns and the beam.
static func build(holder: Node3D, size: Vector2, drops: Array, accent: Color) -> void:
	var key := "%s|%s|%s" % [size, drops, accent.to_html()]
	if not _meshes.has(key): _meshes[key] = _make(size, drops, accent)
	var arch := MeshInstance3D.new()
	arch.name = "Arch"
	arch.mesh = _meshes[key]
	holder.add_child(arch)

static func _make(size: Vector2, drops: Array, accent: Color) -> ArrayMesh:
	var batch := BlockMesh.Batch.new()
	var body := batch.group("body")
	var lamps := batch.group("lamp")
	var reach := size.x * 0.5 - PLINTH         ## a column's axis
	var half := size.y * 0.5
	var top := half + 0.26                      ## the capital's top
	var middle := Vector3(0.0, 0.0, -DEPTH * 0.5)
	# the beam between the columns, and the frame round the sign: two bars, bevelled (the bars end inside the round columns, the core a little short of their skin)
	batch.box(Transform3D(Basis.IDENTITY, middle), Vector3((reach + 0.2) * 2.0, size.y, DEPTH), 0.04, 1, "body", "body", accent.darkened(0.12))
	for side: float in [-1.0, 1.0]:
		batch.box(Transform3D(Basis.IDENTITY, middle + Vector3(0.0, side * (half + BAR * 0.5 - 0.02), 0.0)), Vector3((reach + 0.1) * 2.0, BAR, DEPTH + 0.16), 0.07, 2, "body", "body", CREAM)
	# a crest strip on top of the frame, between the lamps
	batch.box(Transform3D(Basis.IDENTITY, middle + Vector3(0.0, half + BAR + 0.03, 0.0)), Vector3(reach * 2.0 - 1.2, 0.1, DEPTH - 0.04), 0.04, 1, "body", "body", TAN)
	for index in 2:
		var side := -1.0 if index == 0 else 1.0
		var drop := float(drops[index])
		var axis := Vector3(side * reach, 0.0, -DEPTH * 0.5)
		var bottom := -half - drop if drop > 0.05 else -half - 0.5
		if drop > 0.05: _column(body, axis, bottom, top, accent)
		# the capital and the lamp over it, also for a column without a floor under it (it then just ends under the beam: nothing to stand on)
		_capital(body, lamps, axis, top)
	return batch.commit({"body": _body(), "lamp": _lamp()})

## One column: a stepped plinth, a round shaft in the accent, cream collars at its foot, its middle and its head, a flared capital.
static func _column(body: BlockMesh.Group, axis: Vector3, floor_y: float, top: float, accent: Color) -> void:
	PadLook.revolve(body, _drum(PLINTH, floor_y, floor_y + 0.26, 0.09, CREAM), SIDES, axis)
	PadLook.revolve(body, _drum(PLINTH - 0.13, floor_y + 0.26, floor_y + 0.46, 0.06, TAN), SIDES, axis)
	var foot := floor_y + 0.4
	var head := top - 0.2
	PadLook.revolve(body, _tube(COLUMN, foot, head, accent), SIDES, axis)
	PadLook.revolve(body, _drum(COLUMN + 0.1, foot, foot + 0.17, 0.05, CREAM), SIDES, axis)
	PadLook.revolve(body, _drum(COLUMN + 0.1, head - 0.17, head, 0.05, CREAM), SIDES, axis)
	var rings := int((head - foot) / 2.6)
	var half := top - 0.26
	var bars: Array = [[-half - BAR + 0.02, -half + 0.02], [half - 0.02, half + BAR - 0.02]]   # the frame bars' spans (y), the rings may not hang a hairline off them
	for k in rings:
		var at := foot + (head - foot) * float(k + 1) / float(rings + 1)
		for span: Array in bars:
			var below := float(span[0]) - (at + 0.08)
			var above := (at - 0.08) - float(span[1])
			if below > -0.001 and below < 0.06: at += below + 0.02   # a ring that stops just short of a bar goes into it
			elif above > -0.001 and above < 0.06: at -= above + 0.02
		PadLook.revolve(body, _drum(COLUMN + 0.08, at - 0.08, at + 0.08, 0.04, CREAM), SIDES, axis)

## The capital (a flared drum) with a stem and a lamp (a ball that gives off light of its own) on it.
static func _capital(body: BlockMesh.Group, lamps: BlockMesh.Group, axis: Vector3, top: float) -> void:
	PadLook.revolve(body, _drum(CAPITAL, top - 0.27, top, 0.08, TAN, true), SIDES, axis)   # 3 cm into the beam's top: no hairline between them
	PadLook.revolve(body, _drum(0.1, top, top + 0.2, 0.0, CREAM), SIDES, axis)
	var ball: Array = []
	for k in 9:
		var angle := -PI * 0.5 + PI * float(k) / 8.0
		ball.append([cos(angle) * 0.24, top + 0.2 + 0.2 + sin(angle) * 0.24, Vector2(cos(angle), sin(angle)), Color.WHITE])
	PadLook.revolve(lamps, ball, 14, axis)

## A drum from y0 to y1 with `bevel` rounded rims, as a profile for PadLook.revolve (`under`: with a bottom cap, else it is open there: it stands on something).
static func _drum(radius: float, y0: float, y1: float, bevel: float, color: Color, under := false) -> Array:
	var profile: Array = [[radius - bevel, y0, Vector2(0.0, -1.0), color]]
	if under: profile.push_front([0.0, y0, Vector2(0.0, -1.0), color])
	for k in range(1, 3):
		var angle := -PI * 0.5 + PI * 0.5 * float(k) / 2.0
		profile.append([radius - bevel + cos(angle) * bevel, y0 + bevel + sin(angle) * bevel, Vector2(cos(angle), sin(angle)), color])
	for k in range(0, 3):
		var angle := PI * 0.5 * float(k) / 2.0
		profile.append([radius - bevel + cos(angle) * bevel, y1 - bevel + sin(angle) * bevel, Vector2(cos(angle), sin(angle)), color])
	profile.append([0.0, y1, Vector2(0.0, 1.0), color])
	return profile

## An open tube (no caps: they are covered by the drums at its ends).
static func _tube(radius: float, y0: float, y1: float, color: Color) -> Array:
	return [[radius, y0, Vector2(1.0, 0.0), color], [radius, y1, Vector2(1.0, 0.0), color]]

static func _body() -> StandardMaterial3D:
	if _body_material == null:
		_body_material = StandardMaterial3D.new()
		_body_material.vertex_color_use_as_albedo = true
		_body_material.roughness = CandyLook.ROUGH_PLASTIC
	return _body_material

static func _lamp() -> StandardMaterial3D:
	if _lamp_material == null:
		_lamp_material = StandardMaterial3D.new()
		_lamp_material.albedo_color = LAMP_GLOW
		_lamp_material.emission_enabled = true
		_lamp_material.emission = LAMP_GLOW
		_lamp_material.emission_energy_multiplier = 1.4
		_lamp_material.roughness = 0.3
	return _lamp_material
