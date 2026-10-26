extends RefCounted
## The show's lobby yard in the candy look of the race levels (docs/backdrop.md "The lobby kit"): ONE chamfered deck slab in the P tone (the block kit's floor, style/block_kit.gd), pillow walls (the S tone, vinyl),
## pillow-segment columns under the deck down to the sea (style/pillar_kit.gd), and the candy world of the daylight levels around it (style/candy_world.gd: the slime sea under the deck, the meadow, mountains and clouds).
## The collision is the yard's (lobby_space.gd architecture(): a 0.65 m slab and four walls 5.65 m high round the interior Layout.interior_rect()); this kit is only the picture. Client only.
## The deck is a little wider than the walls (their outer faces stand on it) and the walls plant 3 cm in it. Its size is the yard's tile grid: TILE (1.54 m) tiles with GROOVE between, pitch 1.65 m = half
## of the circles' pitch (network/walk_in_lobby.gd PITCH 3.3), Layout.show_tiles_x() tiles across and NZ along z, its middle line a whole pitch behind the front row (z = FRONT_Z), so every circle
## still stands where the grid put it; nothing is drawn on the grid, the rim runs round the deck outside the walls (the only open edge of the yard: the walls close every inner edge).
## Everything is one mesh in two material families of style/candy_surface.gdshader: the kit's vertex colours (BlockKit.material) and the races' surfaces (RaceSurfaces).
const BlockMesh := preload("res://style/block_mesh.gd")
const BlockKit := preload("res://style/block_kit.gd")
const CandyMaterial := preload("res://style/candy_material.gd")
const RaceSurfaces := preload("res://style/race_surfaces.gd")
const CandyWorld := preload("res://style/candy_world.gd")
const PillarKit := preload("res://style/pillar_kit.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const CandyLook := preload("res://style/candy_look.gd")
const CandyCourse := preload("res://style/candy_course.gd")
const RINGS := preload("res://lobby/lobby_rings.gdshader")
const PANEL_YELLOW := Color("ffbe0a")   ## the back panel's screen colour (a warm yellow studio wall)
const PANEL_RING := Color("ffd95a")     ## and its lighter concentric rings
const PANEL_GLOW := Color("ffe070")     ## the warm glow round the rings' centre

const WALL_LIGHTEN := 0.15       ## how far the walls move from the S role's light tone towards white
const TILE := 1.54              ## m: a tile's side; the tile pitch (TILE + BlockKit.GROOVE) is half of the circles' pitch
const NZ := 14                  ## tiles along z (an even number: a groove on the middle line)
const RIM := 0.3                ## m: the rim ring outside the tiles
const THICK := 0.65             ## m: the slab (lobby_space.gd SLAB_DEPTH)
const WALL_TOP := 5.65          ## m: lobby_space.gd WALL_HEIGHT: the collision of every wall, and the picture of the north one (the backdrop of the signs)
const WALL_SIDE_TOP := 2.4      ## m: the picture of the west, east and south walls: a low cushion rim under the shoulder camera's eye (3.4 m up), so a wall at the camera's side never fills the view; their collision is WALL_TOP
const WING_PINK := Color("f28ca8")  ## the wardrobe nook's cushion wings (the wardrobe sign's and ring's pink)
const PLANT := 0.03             ## m: a wall's foot in the tiles
const PILLAR_WIDTH := 1.5
const PILLAR_X: Array[float] = [0.65, 0.22]  ## the pillars' x as shares of the deck's half width (both sides)
const PILLAR_Z: Array[float] = [-7.5, 5.0]
const PLANE := -11.0            ## m: the sea's height (the deck's top is 0)
const Y_TOP := 8.0              ## m: what the skyline reaches over (the hero sign's top is 7.5)
const OVERLAP := 0.03           ## m: how far a part sits into the part it stands on

## The deck's half size and centre z (yard-local).
static func deck_half() -> Vector2:
	var pitch := TILE + BlockKit.GROOVE
	return Vector2((Layout.show_tiles_x() * pitch + BlockKit.GROOVE) * 0.5 + RIM, (NZ * pitch + BlockKit.GROOVE) * 0.5 + RIM)

## The middle line of the tile grid: a pitch behind the front row, so that the yard's south end stays where the single-circle yards have it and the north wall stands behind THE SHOW's pylon.
static func deck_z() -> float:
	return Layout.FRONT_Z + TILE + BlockKit.GROOVE

## Adds the yard's kit and its world to `room` (lobby_space.gd's node; everything yard-local under one node at Layout.ORIGIN).
static func dress(room: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "LobbyKit"
	holder.position = Layout.ORIGIN
	room.add_child(holder)
	var batch := BlockMesh.Batch.new()
	_deck(batch)
	_walls(batch)
	_nook(batch)
	_supports(batch)
	var mesh := MeshInstance3D.new()
	mesh.name = "Yard"
	mesh.mesh = batch.commit(_materials(batch))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(mesh)
	_backdrop(holder)
	holder.add_child(_world())

static func _materials(batch: BlockMesh.Batch) -> Dictionary:
	var result := {}
	for key: String in batch.groups:
		result[key] = BlockKit.material_of(key, CandyMaterial.NEAR_FLOOR_LOW) if BlockKit.is_key(key) else RaceSurfaces.material(key)
	return result

## The floor: ONE chamfered slab in the P tone (the block kit's floor), the walls stand on it inside its rim.
static func _deck(batch: BlockMesh.Batch) -> void:
	var half2 := deck_half()
	var size := Vector3(half2.x * 2.0, THICK, half2.y * 2.0)
	BlockKit.floor_block(batch, Transform3D(Basis.IDENTITY, Vector3(0.0, -THICK * 0.5, deck_z())), size, "teal", null, [[], [], [], []], true)

## Four pillow walls (the S tone, vinyl) on the deck, from the interior's faces out to the rim's inner edge. The north wall stands tall behind the signs; the other three are a low rim (WALL_SIDE_TOP).
static func _walls(batch: BlockMesh.Batch) -> void:
	var inner := Layout.interior_rect()
	var half := deck_half()
	var out_x := half.x - RIM + 0.01
	var north := deck_z() - (half.y - RIM) - 0.01
	var south := deck_z() + (half.y - RIM) + 0.01
	var bottom := -PLANT
	var reach := 0.4 # the side walls reach this far into the north and south walls: no two faces meet in a plane
	var rows: Array = [ # [x0, x1, z0, z1, top]
		[-out_x, out_x, north, inner.position.y, WALL_TOP],
		[-out_x, out_x, inner.end.y, south, WALL_SIDE_TOP],
		[-out_x, inner.position.x, inner.position.y + reach, inner.end.y - reach, WALL_SIDE_TOP],
		[inner.end.x, out_x, inner.position.y + reach, inner.end.y - reach, WALL_SIDE_TOP],
	]
	for row: Array in rows:
		var top := float(row[4])
		var size := Vector3(float(row[1]) - float(row[0]), top - bottom, float(row[3]) - float(row[2]))
		var middle := Vector3((float(row[0]) + float(row[1])) * 0.5, (top + bottom) * 0.5, (float(row[2]) + float(row[3])) * 0.5)
		BlockKit.pillow(batch, Transform3D(Basis.IDENTITY, middle), size, RaceSurfaces.keys("navy", 1), [WALL_MAIN(), WALL_LIGHT()])

## The wardrobe nook's two cushion wings (Layout.nook_wings, collision in lobby_space.gd props): pink pillows standing on the deck, their backs in the west wall.
static func _nook(batch: BlockMesh.Batch) -> void:
	var stone := RaceSurfaces.keys("stone", 1)
	for wing: Dictionary in Layout.nook_wings():
		var size: Vector3 = wing.size
		var middle: Vector3 = wing.center
		batch.box(Transform3D(Basis.IDENTITY, middle + Vector3.DOWN * PLANT * 0.5), size + Vector3.UP * PLANT, minf(size.z * 0.5 * BlockKit.PILLOW_SHARE, 0.24), BlockKit.PILLOW_SEGMENTS, stone[0], stone[1], WING_PINK, 0.0, true, stone[2], 1.0)

## Pillar columns from the deck down to the sea.
static func _supports(batch: BlockMesh.Batch) -> void:
	var half := deck_half()
	var top := -THICK + OVERLAP
	for share: float in PILLAR_X:
		for side: float in [-1.0, 1.0]:
			for z: float in PILLAR_Z:
				var x: float = side * roundf(share * half.x * 2.0) * 0.5
				var height := top - PLANE
				PillarKit.support(batch, Transform3D(Basis.IDENTITY, Vector3(x, PLANE + height * 0.5, z)), Vector3(PILLAR_WIDTH, height, PILLAR_WIDTH), -height * 0.5 + 0.002)

## The world round it: the candy world of the daylight levels (style/candy_world.gd), centred on the deck, the sea at PLANE (the pillars' feet stand in the slime).
static func _world() -> Node3D:
	var half := deck_half()
	var root := Node3D.new()
	root.name = "LobbyWorld"
	root.add_child(CandyWorld.build({"centre": Vector3(0.0, 0.0, deck_z()), "floor_y": -THICK, "course_radius": half.length(), "world_scale": CandyWorld.default_scale(), "seed": 7,
		"sea": "slime", "sea_y": PLANE, "view_y": Y_TOP + 4.0 - PLANE, "foliage_from": 900.0})) # no treetop shows over the yard walls
	return root

## A yellow panel with concentric lighter rings on the north wall's inside face, behind the sign boards (visual only: no collision; the wall's own face is 3 cm behind it).
static func _backdrop(holder: Node3D) -> void:
	var inner := Layout.interior_rect()
	var quad := QuadMesh.new()
	quad.size = Vector2(inner.size.x, WALL_TOP)
	var material := ShaderMaterial.new()
	material.shader = RINGS
	material.set_shader_parameter("base", CandyLook.scene_linear(PANEL_YELLOW).linear_to_srgb())
	material.set_shader_parameter("ring", CandyLook.scene_linear(PANEL_RING).linear_to_srgb())
	material.set_shader_parameter("glow", CandyLook.scene_linear(PANEL_GLOW).linear_to_srgb())
	material.set_shader_parameter("size", quad.size)
	var panel := MeshInstance3D.new()
	panel.name = "BackPanel"
	panel.mesh = quad
	panel.material_override = material
	panel.position = Vector3(0.0, WALL_TOP * 0.5, inner.position.y + 0.03)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(panel)

## The yard walls' two tones: the brand's S role: its light tone mixed half way to white (a lavender-lilac in the default scheme: the walls are the frame, not the picture); they follow the brand.
static func WALL_MAIN() -> Color:
	var s := CandyCourse.scheme().s as Dictionary
	return (s.light as Color).lerp(Color.WHITE, WALL_LIGHTEN)

static func WALL_LIGHT() -> Color:
	var s := CandyCourse.scheme().s as Dictionary
	return (s.light as Color).lerp(Color.WHITE, WALL_LIGHTEN + 0.15)
