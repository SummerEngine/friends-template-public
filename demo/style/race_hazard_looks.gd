extends RefCounted
## The hazards of a level with `"world": "daylight"` (style/race_world.gd) in the candy look's props palette (style/candy_look.gd PROP_*: hot pink with white stripes, amber, purple, white) instead of the party look's red and orange. A pass over the drawn level
## (levels/level_world.gd `build`, after the collision look and the cast's spin-bar dressing):
##   spin hazards   spinners and wheels (style/spinner_look.gd): pink striped inflatable bars on a pink hub with an amber dome, a white base flange on the floor
##   rideable discs  a `spin` without `hit` with a cylinder part: a turntable (style/turntable_look.gd): purple tiles, white rim, pink hub, a pink striped bar
##   ride platforms `slide` / `lift` without `hit`: an amber machine in the block kit's platform language, white chevrons along its way (style/mover_look.gd)
##   hurting blocks `slide` with `hit` and box parts: pillow cubes in hot pink with white stripes (style/hit_block_look.gd)
##   push pads      the pad of a `push` volume: a round pink button in a white collar that presses down when a courier sets it off (style/pad_look.gd)
## Look only: no collision or gameplay is touched; a body with a cast picture on it (an obstacle slot) keeps its own look. Client only.
const SpinnerLook := preload("res://style/spinner_look.gd")
const TurntableLook := preload("res://style/turntable_look.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const PadLook := preload("res://style/pad_look.gd")
const GateLook := preload("res://style/gate_look.gd")
const MoverLook := preload("res://style/mover_look.gd")
const HitBlockLook := preload("res://style/hit_block_look.gd")
const LAYER_HIT := 8         ## levels/level_world.gd: the bodies that hurt

## Dresses the hazards of the drawn level under `level_root`.
static func dress(level_root: Node3D) -> void:
	for body: Node in level_root.get_children():
		if body is AnimatableBody3D:
			var named := str(body.name)
			if named.begins_with("Hazard_spin_"): _spin(body as AnimatableBody3D)
			elif (named.begins_with("Hazard_slide_") or named.begins_with("Hazard_lift_")) and ((body as AnimatableBody3D).collision_layer & LAYER_HIT) == 0: _platform(body as AnimatableBody3D)
			elif named.begins_with("Hazard_slide_"): _hit_blocks(body as AnimatableBody3D)
	for pad: Node in level_root.find_children("LaunchPad", "MeshInstance3D", true, false): PadLook.dress(pad as MeshInstance3D, HazardLooks.PAD_HEIGHT, PadLook.cell_side(level_root, pad as Node3D))
	GateLook.dress(level_root)

## The shapes of `body` the look may replace: every one a box or an upright cylinder without a cast picture; empty when one is not (the body keeps the party look then).
static func _shapes(body: AnimatableBody3D) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for node: Node in body.get_children():
		var shape_node := node as CollisionShape3D
		if shape_node == null: continue
		if shape_node.has_meta("slot") or shape_node.has_meta("tone") or not (shape_node.shape is BoxShape3D or shape_node.shape is CylinderShape3D): return []
		shapes.append(shape_node)
	return shapes

static func _replace(body: AnimatableBody3D, pieces: Array) -> void:
	var look := body.get_node_or_null("CollisionLook") as Node3D
	if look != null: look.visible = false
	for piece: Array in pieces: (piece[0] as Node).add_child(piece[1])

static func _spin(body: AnimatableBody3D) -> void:
	var shapes := _shapes(body)
	if shapes.is_empty(): return
	var rideable := (body.collision_layer & LAYER_HIT) == 0
	var look := TurntableLook.build(shapes) if rideable else SpinnerLook.build(shapes, str(body.get_meta("axis", "y")))
	if look != null: _replace(body, [[body, look]])

static func _platform(body: AnimatableBody3D) -> void:
	var shapes := _shapes(body)
	if shapes.is_empty(): return
	for shape_node in shapes:
		if not shape_node.shape is BoxShape3D: return # a round platform keeps the party look
	var pieces: Array = []
	for shape_node in shapes: pieces.append([shape_node, MoverLook.build(shape_node, body)])
	_replace(body, pieces)

## A sliding block that hurts: every box part (a tone `crate` or none, no cast picture) becomes a striped pillow cube; one of any other shape leaves the block as it is.
static func _hit_blocks(body: AnimatableBody3D) -> void:
	var pieces: Array = []
	for node: Node in body.get_children():
		var shape_node := node as CollisionShape3D
		if shape_node == null: continue
		if shape_node.has_meta("slot") or not shape_node.shape is BoxShape3D or str(shape_node.get_meta("tone", "crate")) != "crate": return
		pieces.append([shape_node, HitBlockLook.build(shape_node)])
	if not pieces.is_empty(): _replace(body, pieces)
