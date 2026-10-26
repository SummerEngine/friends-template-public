extends RefCounted
## Words that float in the 3D world (name tags, catchphrase bubbles, gameplay words) in the clean UI type: a billboard
## Label3D in Inter on its own flat rounded plate, no outline. The plate is a child mesh that faces the camera with the
## label and is rebuilt when the text changes.
##   var tag := WorldLabel.make("MAJA", 76, 0.0042, Color.WHITE, WorldLabel.DARK)
##   WorldLabel.set_text(tag, "THEO")      # re-sizes the plate
##   WorldLabel.set_alpha(tag, 0.5)        # fades the word and its plate together
const Ui := preload("res://client/friends_ui.gd")
## Plate colours: near-black under white type (tags, words over the world), white under ink type (speech bubbles).
const DARK := Color(0.082, 0.086, 0.102, 0.9)
const LIGHT := Color(1, 1, 1, 0.97)
## Plate padding in font sizes (x: each side, y: top and bottom).
const PAD := Vector2(0.5, 0.26)

## A Label3D in Inter `weight` at `font_size` (px) x `pixel` (m per px), `ink` type on a `plate` colour (alpha 0 = no plate).
## `wrap_px` > 0 wraps long lines at that width. `priority` is the label's render priority (the plate draws one under it).
static func make(text: String, font_size: int, pixel: float, ink: Color, plate: Color, priority := 4, wrap_px := 0.0, weight := 800) -> Label3D:
	var label := Label3D.new()
	label.font = Ui.inter(weight)
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = ink
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.double_sided = true
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	label.render_priority = priority
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap_px > 0.0:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = wrap_px
	label.set_meta(&"plate_color", plate)
	set_text(label, text)
	return label

## New text: the plate follows its size (and the label's no_depth_test at this moment).
static func set_text(label: Label3D, text: String) -> void:
	label.text = text
	var old := label.get_node_or_null("Plate")
	if old != null:
		label.remove_child(old)
		old.queue_free()
	var color: Color = label.get_meta(&"plate_color", Color(0, 0, 0, 0))
	if text == "" or color.a <= 0.0: return
	var font := label.font if label.font != null else Ui.BOLD
	var wrap := label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.width > 0.0
	var box := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, label.width if wrap else -1.0, label.font_size)
	box.y = maxf(box.y, font.get_height(label.font_size))
	var size := (box + PAD * 2.0 * float(label.font_size)) * label.pixel_size
	var plate := mesh(_rounded(size, minf(size.y * 0.5, 0.45 * float(label.font_size) * label.pixel_size)), color, label.render_priority - 1, label.no_depth_test)
	plate.name = "Plate"
	label.add_child(plate)

## Fades the word and its plate together (`alpha` 0..1 of their own colours).
static func set_alpha(label: Label3D, alpha: float) -> void:
	label.modulate.a = alpha
	var plate := label.get_node_or_null("Plate") as MeshInstance3D
	if plate == null: return
	var color: Color = label.get_meta(&"plate_color", Color(0, 0, 0, 0))
	(plate.material_override as StandardMaterial3D).albedo_color.a = color.a * alpha

## Rounded rect `size` (metres, centred) as a polygon.
static func _rounded(size: Vector2, radius: float, tail := false) -> PackedVector2Array:
	var half := size * 0.5
	radius = minf(radius, minf(half.x, half.y))
	var points := PackedVector2Array()
	var corners := [Vector2(half.x - radius, half.y - radius), Vector2(-half.x + radius, half.y - radius), Vector2(-half.x + radius, -half.y + radius), Vector2(half.x - radius, -half.y + radius)]
	for corner in 4:
		for step in 7:
			var angle := (corner + step / 6.0) * PI * 0.5
			points.append(corners[corner] + Vector2(cos(angle), sin(angle)) * radius)
		if corner == 2 and tail: # bottom edge, left to right: a small rounded-off tail down to the speaker
			var root_x := -half.x * 0.25
			var reach := minf(0.18, size.y * 0.4)
			points.append(Vector2(root_x - reach * 0.4, -half.y))
			points.append(Vector2(root_x - reach * 0.55, -half.y - reach))
			points.append(Vector2(root_x + reach * 0.5, -half.y))
	return points

## A speech bubble's outline: the rounded rect with a small tail under its left half.
static func bubble_shape(size: Vector2, radius: float) -> PackedVector2Array:
	return _rounded(size, radius, true)

## A flat billboard mesh of `points` (metres) in `color`, unshaded, drawn at `priority`.
static func mesh(points: PackedVector2Array, color: Color, priority: int, on_top := false) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	for index in Geometry2D.triangulate_polygon(points): vertices.append(Vector3(points[index].x, points[index].y, 0.0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	if not vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = on_top
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	var plate := MeshInstance3D.new()
	plate.mesh = mesh
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return plate
