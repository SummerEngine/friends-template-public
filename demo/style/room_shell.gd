extends RefCounted
## The room around a level or the lobby yard: a tiled hall well clear of the course on every side, its floor deep under the lowest block
## (a fall reads as a fall; the lobby yard stands on it instead), its ceiling high over the highest one with a grid of skylights, so the
## follow camera stays inside. Decor only: no collision, casts no shadows (the light comes in through the skylights). Three draw calls.
const Surfaces := preload("res://style/surfaces.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const MARGIN := 16.0          ## metres from the course's box to the walls
const DEPTH := 18.0           ## the floor's depth under the lowest block
const HEADROOM := 14.0        ## the ceiling's height over the highest block
const THICK := 1.0
const SKYLIGHT := Vector2(3.5, 7.0)
const SKYLIGHT_STEP := Vector2(9.0, 12.0)

## The room of a level from its box (style/backdrop.gd level_spec), standing at `origin`, named `label`.
static func build(spec: Dictionary, origin: Vector3, label: String) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.position = origin
	var box: Rect2 = (spec.bbox as Rect2).grow(MARGIN)
	var floor_y := float(spec.y_low) - float(spec.get("depth", DEPTH))
	var ceiling_y := float(spec.y_high) + HEADROOM
	var batch := BlockMesh.Batch.new()
	var lamps := BlockMesh.Batch.new()
	var centre := Vector3(box.get_center().x, 0.0, box.get_center().y)
	var height := ceiling_y - floor_y
	batch.box(Transform3D(Basis(), Vector3(centre.x, floor_y - THICK * 0.5, centre.z)), Vector3(box.size.x + THICK * 2.0, THICK, box.size.y + THICK * 2.0), 0.0, 1, "room_floor", "room_floor")
	var mid_y := floor_y + height * 0.5
	for side: Array in [[Vector3(box.position.x - THICK * 0.5, mid_y, centre.z), Vector3(THICK, height, box.size.y)],
			[Vector3(box.end.x + THICK * 0.5, mid_y, centre.z), Vector3(THICK, height, box.size.y)],
			[Vector3(centre.x, mid_y, box.position.y - THICK * 0.5), Vector3(box.size.x + THICK * 2.0, height, THICK)],
			[Vector3(centre.x, mid_y, box.end.y + THICK * 0.5), Vector3(box.size.x + THICK * 2.0, height, THICK)]]:
		batch.box(Transform3D(Basis(), side[0]), side[1], 0.05, 1, "room_wall", "room_wall")
	batch.box(Transform3D(Basis(), Vector3(centre.x, ceiling_y + THICK * 0.5, centre.z)), Vector3(box.size.x + THICK * 2.0, THICK, box.size.y + THICK * 2.0), 0.0, 1, "ceiling", "ceiling")
	_skylights(lamps, box, ceiling_y)
	var materials := {}
	for key: String in batch.groups: materials[key] = Surfaces.material(key)
	_add_mesh(root, "RoomShell", batch.commit(materials))
	if not lamps.is_empty(): _add_mesh(root, "RoomLights", lamps.commit({"lamp": Surfaces.lamp_material()}))
	return root

static func _add_mesh(root: Node3D, label: String, mesh: Mesh) -> void:
	if mesh == null: return
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)

## Glowing panels in a grid under the ceiling.
static func _skylights(lamps: BlockMesh.Batch, box: Rect2, ceiling_y: float) -> void:
	var columns := maxi(1, floori(box.size.x / SKYLIGHT_STEP.x))
	var rows := maxi(1, floori(box.size.y / SKYLIGHT_STEP.y))
	var step := Vector2(box.size.x / columns, box.size.y / rows)
	for i in columns:
		for j in rows:
			var at := Vector3(box.position.x + step.x * (i + 0.5), ceiling_y - 0.05, box.position.y + step.y * (j + 0.5))
			lamps.box(Transform3D(Basis(), at), Vector3(SKYLIGHT.x, 0.1, SKYLIGHT.y), 0.0, 1, "lamp", "lamp")

