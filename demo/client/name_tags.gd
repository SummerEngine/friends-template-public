extends Node3D
const _DevLap := preload("res://dev_env.gd")
## Floating player names: one billboard Label3D per slot, parented to that
## slot's actor (capsule feet origin, character ~1.8 m). Client only.
## Tags grow with distance so they stay readable, then fade and vanish far away. Each tag is the show's pill (client/show_theme.gd): slanted Lilita One words in the player's colour
## (lifted towards white) on a dark pill with the thin light outline and a gold ring badge at its end (a gold rank badge with the number when the slot's entry carries a `rank`), all one
## vertex-coloured billboard mesh under the Label3D. In the lobby a player's title from the team cast ("THE FIXER", entries' `title`) hangs small under the name on its own plate.
const WorldLabel := preload("res://client/world_label.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const MAX_CHARS := 16
const HEIGHT := 2.3
const BASE_SCALE_DISTANCE := 6.0 # up to here the tag has its natural world size
const MAX_GROWTH := 2.4
const FADE_START := 22.0
const FADE_END := 32.0
const TITLE_DROP := 0.3 ## the title sits this far under the name (before growth)
const STAGE_TAG_PER_METRE := 0.14 ## a stage round: the tag's scale per metre from the camera, so it keeps its size on the screen (about 11 px high at 720: 1.7 at the 12 m camera)
const FONT_SIZE := 60
const PIXEL := 0.0025 ## m per px of the tag's type
const PAD_X := 0.45 ## the pill's padding left of the name, in font sizes
const BADGE := 0.62 ## the badge's diameter, in font sizes
const EDGE := 0.045 ## the thin outline, in font sizes

static var _font: FontVariation

## Lilita One leaning right (the show's italic).
static func tag_font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ShowTheme.font()
		_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(ShowTheme.SLANT, 1.0), Vector2.ZERO)
	return _font

var _labels: Array[Label3D] = []
var _titles: Array[Label3D] = []
var _simulation
var _wanted: Array[bool] = []
var _local_slot := -1

func configure(simulation) -> void:
	assert(_labels.is_empty(), "NameTags.configure is called once")
	_simulation = simulation
	for actor: CharacterBody3D in simulation.actors:
		var label := WorldLabel.make("", FONT_SIZE, PIXEL, Color.WHITE, Color(0, 0, 0, 0), 4)
		label.font = tag_font()
		label.name = "NameTag"
		label.position = Vector3(0.0, HEIGHT, 0.0)
		label.visible = false
		actor.add_child(label)
		_labels.append(label)
		var title := WorldLabel.make("", 36, PIXEL, Color.WHITE, WorldLabel.DARK, 4, 0.0, 600)
		title.name = "TitleTag"
		title.position = Vector3(0.0, -TITLE_DROP, 0.0)
		label.add_child(title)
		_titles.append(title)
		_wanted.append(false)
	set_process(true)

## entries[slot] is {name, color, visible, title} or {} for an empty slot (title: the cast's player title, shown in the lobby).
func set_slots(entries: Array) -> void:
	for slot in _labels.size():
		var entry: Dictionary = entries[slot] if slot < entries.size() else {}
		var label := _labels[slot]
		var shown := not entry.is_empty() and bool(entry.get("visible", true)) and slot != _local_slot
		_wanted[slot] = shown
		if not entry.is_empty():
			var shown_name := str(entry.get("name", ""))
			var tag := shown_name if shown_name.length() <= MAX_CHARS else shown_name.substr(0, MAX_CHARS - 1) + "…"
			var rank := int(entry.get("rank", 0))
			var tone := Color(entry.get("color", Color.WHITE))
			if label.text != tag or int(label.get_meta(&"rank", 0)) != rank or label.get_meta(&"tone", Color.BLACK) != tone: _set_tag(label, tag, rank, tone) # white words, the player's colour in the badge's dot
			label.modulate = Color.WHITE
		var title_text := str(entry.get("title", ""))
		if _titles[slot].text != title_text: WorldLabel.set_text(_titles[slot], title_text)
		label.visible = shown

## The own tag is hidden: you never need to read your own name.
func set_local_slot(slot: int) -> void:
	_local_slot = slot
	for index in _labels.size():
		if index == slot:
			_wanted[index] = false
			_labels[index].visible = false

func _process(_delta: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(_delta)
	_DevLap.lap("name_tags.p", _lap)

func _process_timed(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var eye := camera.global_position
	var stage: bool = _simulation != null and is_instance_valid(_simulation) and _simulation.has_method("stage_round") and bool(_simulation.stage_round())
	for slot in _labels.size():
		var label := _labels[slot]
		if not _wanted[slot] or not is_instance_valid(label): continue
		var distance := eye.distance_to(label.global_position)
		var fade := 1.0 if stage else 1.0 - smoothstep(FADE_START, FADE_END, distance) # a stage round's tags are as big and as clear near and far
		label.visible = fade > 0.01
		if not label.visible: continue
		label.scale = Vector3.ONE * (distance * STAGE_TAG_PER_METRE if stage else clampf(distance / BASE_SCALE_DISTANCE, 1.0, MAX_GROWTH))
		_set_alpha(label, fade)
		var title := _titles[slot]
		title.visible = title.text != "" and _simulation != null and is_instance_valid(_simulation) and str(_simulation.get("round_mode")) == "lobby"
		WorldLabel.set_alpha(title, fade)

## The tag's words and pill: the pill (outline, dark body, gold badge) is one vertex-coloured billboard mesh child "Plate", rebuilt when the words or rank change.
static func _set_tag(label: Label3D, words: String, rank: int, tone: Color) -> void:
	label.text = words
	label.set_meta(&"rank", rank)
	label.set_meta(&"tone", tone)
	for old in ["Plate", "Rank"]:
		var node := label.get_node_or_null(old)
		if node != null:
			label.remove_child(node)
			node.queue_free()
	if words == "": return
	var font := label.font
	var size := float(label.font_size)
	var text_wide := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	var high := size * 0.95
	var badge := size * BADGE
	var wide := size * PAD_X + text_wide + size * 0.3 + badge + size * 0.22
	var edge := size * EDGE
	label.offset = Vector2(-wide * 0.5 + size * PAD_X + text_wide * 0.5, 0.0) # the words sit left of the pill's middle, the badge on its right end
	var centre_badge := Vector2(wide * 0.5 - size * 0.22 - badge * 0.5, 0.0)
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var layer := 0
	var parts: Array = [
		[_pill(Vector2(wide + edge * 2.0, high + edge * 2.0)), ShowTheme.PILL_EDGE],
		[_pill(Vector2(wide, high)), Color(ShowTheme.PILL, 0.95)],
		[_disc(centre_badge, badge * 0.5), ShowTheme.GOLD_DEEP],
		[_disc(centre_badge + Vector2(0.0, size * 0.015), badge * 0.47), ShowTheme.GOLD],
	]
	if rank <= 0:
		parts.append([_disc(centre_badge, badge * 0.34), ShowTheme.NAVY])
		parts.append([_disc(centre_badge, badge * 0.2), tone])
	for part: Array in parts:
		var polygon: PackedVector2Array = part[0]
		var color: Color = part[1]
		for index in Geometry2D.triangulate_polygon(polygon):
			points.append(Vector3(polygon[index].x * label.pixel_size, polygon[index].y * label.pixel_size, -0.0004 * layer))
			colors.append(color)
		layer += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = label.render_priority - 1
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	plate.mesh = mesh
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.add_child(plate)
	if rank > 0:
		var number := WorldLabel.make(str(rank), label.font_size, label.pixel_size, Color("1b1d24"), Color(0, 0, 0, 0), label.render_priority + 1)
		number.font = label.font
		number.name = "Rank"
		number.font_size = roundi(badge * 0.78)
		number.position = Vector3(centre_badge.x * label.pixel_size, 0.0, 0.0)
		label.add_child(number)

## Fades the tag's words and pill together.
static func _set_alpha(label: Label3D, alpha: float) -> void:
	label.modulate.a = alpha
	var plate := label.get_node_or_null("Plate") as MeshInstance3D
	if plate != null: (plate.material_override as StandardMaterial3D).albedo_color.a = alpha
	var number := label.get_node_or_null("Rank") as Label3D
	if number != null: number.modulate.a = alpha

## A pill (rounded ends) of `size` px about the origin.
static func _pill(size: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius := size.y * 0.5
	var half := size.x * 0.5 - radius
	for step in 13:
		var a := -PI * 0.5 + PI * float(step) / 12.0
		points.append(Vector2(half + cos(a) * radius, sin(a) * radius))
	for step in 13:
		var a := PI * 0.5 + PI * float(step) / 12.0
		points.append(Vector2(-half + cos(a) * radius, sin(a) * radius))
	return points

## A disc of `radius` px about `at`.
static func _disc(at: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 24: points.append(at + Vector2(cos(TAU * float(step) / 24.0), sin(TAU * float(step) / 24.0)) * radius)
	return points
