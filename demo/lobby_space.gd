extends Node3D
## The lobby yard: a slab with four walls, foam blocks and a playground (lobby/playground.gd: swing, trampoline, slide, ball pit,
## seesaw, furniture), built from boxes and cylinders. The same shapes are the collision on every role and (client only) the picture:
## lobby_visuals.gd draws each shape the way the levels are drawn (style/collision_look.gd), so what you see is what you collide with.
const Layout = preload("res://network/walk_in_lobby.gd")
const Playground = preload("res://lobby/playground.gd")
var Visuals
static var client_draw_factory: Callable
var _client_draw := {}

const NAME := "DedicatedLobbySpace"
const LAYER := 1 | 512
const CAMERA_LAYER := 256  ## the slab and the walls also stop the follow camera (game/follow_camera.gd), so it never dips under the floor
## The slab is 0.65 thick (a "ground" shape of the look: the floor on top, the base on the sides). Walls stand outside the
## play rectangle (Layout.interior_rect()) with their inner faces on it, 5.65 m above the floor, and reach down to the slab's underside. The trampoline
## throws a courier 3.05 m up and a dash at the top of the bounce adds up to 1.9 m more (tools/exploit_probe.gd --lobby): the walls stand 0.7 m over that.
const WALL_THICKNESS := 0.9
const WALL_HEIGHT := 5.65
const SLAB_DEPTH := 0.65
## The yard is the play rectangle Layout.interior_rect(): 34.6 x 24 m for the single-circle minigames, the show's own size (cut to its circles) for the show.
static func architecture() -> Array:
	var rect := Layout.interior_rect()
	var half := rect.size.x * 0.5
	var middle := rect.position.y + rect.size.y * 0.5
	var wide := rect.size.x + 2.0 * WALL_THICKNESS
	return [
		{"name":"yard_slab","center":Vector3(0,-0.325,middle),"size":Vector3(rect.size.x,0.65,rect.size.y),"yaw":0},
		{"name":"wall_n","center":Vector3(0,2.5,rect.position.y-WALL_THICKNESS*0.5),"size":Vector3(wide,6.3,WALL_THICKNESS),"yaw":0},
		{"name":"wall_s","center":Vector3(0,2.5,rect.end.y+WALL_THICKNESS*0.5),"size":Vector3(wide,6.3,WALL_THICKNESS),"yaw":0},
		{"name":"wall_w","center":Vector3(-half-WALL_THICKNESS*0.5,2.5,middle),"size":Vector3(WALL_THICKNESS,6.3,rect.size.y),"yaw":0},
		{"name":"wall_e","center":Vector3(half+WALL_THICKNESS*0.5,2.5,middle),"size":Vector3(WALL_THICKNESS,6.3,rect.size.y),"yaw":0},
	]
## Solid props: `base` is the middle of the foot, `size` the box (the crate or board you bump into), `kind` how the client dresses it.
const PROPS := [
	{"name":"crate_a","kind":"crate","base":Vector3(-4.6,0,9.4),"size":Vector3(0.9,0.9,0.9),"yaw":8},
	{"name":"crate_b","kind":"crate","base":Vector3(-4.6,0.9,9.4),"size":Vector3(0.6,0.6,0.6),"yaw":28},
	{"name":"crate_c","kind":"crate","base":Vector3(-3.75,0,9.5),"size":Vector3(0.6,0.6,0.6),"yaw":-12},
	{"name":"crate_d","kind":"crate","base":Vector3(5.9,0,-13.3),"size":Vector3(0.9,0.9,0.9),"yaw":-10},
	{"name":"crate_e","kind":"crate","base":Vector3(5.9,0.9,-13.3),"size":Vector3(0.6,0.6,0.6),"yaw":24},
	{"name":"crate_f","kind":"crate","base":Vector3(16.55,0,9.25),"size":Vector3(1.2,1.2,1.2),"yaw":0},
	{"name":"crate_g","kind":"crate","base":Vector3(16.55,1.2,9.25),"size":Vector3(0.7,0.7,0.7),"yaw":20},
	{"name":"crate_h","kind":"crate","base":Vector3(15.4,0,9.5),"size":Vector3(0.8,0.5,0.8),"yaw":-20},
	{"name":"easel","kind":"easel","base":Vector3(0,0,-13.73),"size":Vector3(2.2,2.2,0.5),"yaw":0},
	{"name":"wardrobe_mirror","kind":"wardrobe","base":Vector3(-17.15,0.45,0.5),"size":Vector3(0.3,2.3,1.5),"yaw":0},
]
## Loose props players pick up, carry and throw (players/prop_sim.gd, simulated by game/team_play.gd): `at` is the centre of
## the prop's collision sphere, resting on the floor, in front of the spawn spots and between the circles.
const LOOSE_PROPS := [
	{"kind":"box","at":Vector3(0.0,0.25,-2.2)},
	{"kind":"ball","at":Vector3(-2.2,0.25,-2.8)},
	{"kind":"cone","at":Vector3(2.2,0.22,-2.6)},
	{"kind":"box","at":Vector3(-7.0,0.25,-1.5)},
	{"kind":"ball","at":Vector3(7.0,0.25,-1.0)},
	{"kind":"cone","at":Vector3(0.0,0.22,7.5)},
]
var placements: Array[Dictionary] = []
var _bodies: Array[StaticBody3D] = []
var _drawn := false
var _environment
var playground: Playground

## `world` = the node the level world lives under, `role` = "authority" (bodies only), "local" or "replica" (drawn).
static func ensure(world: Node3D, role: String) -> Node3D:
	if world == null:return null
	var existing: Node3D=world.get_node_or_null(NAME)
	if existing!=null:return existing
	var room: Node3D=load("res://lobby_space.gd").new()
	room.name=NAME
	world.add_child(room)
	room.build(world,role)
	return room
## LOOSE_PROPS in world space, for PropSim.new.
static func loose_props() -> Array:
	var layout := []
	if Layout.show_yard(): return layout # the show's yard is clear: nothing lies about
	for row: Dictionary in LOOSE_PROPS: layout.append({"kind": row.kind, "position": Layout.ORIGIN + (row.at as Vector3)})
	return layout
static func sync(world: Node3D, role: String, in_lobby: bool) -> void:
	var room:=ensure(world,role)
	if room!=null:room.set_active(in_lobby)

## The solid props this yard has: the show's yard (Layout.show_yard) keeps the wardrobe's mirror board and the two cushion wings of its nook (Layout.nook_wings); the others' yards all of PROPS.
static func props() -> Array:
	if not Layout.show_yard(): return PROPS
	var kept: Array = []
	for row: Dictionary in PROPS:
		if str(row.kind) != "wardrobe": continue
		var moved := row.duplicate()
		moved.base = Vector3(-Layout.yard_half_width() + 0.15, float(row.base.y), Layout.wardrobe_center().z) # the mirror board stands behind the ring, against the west wall
		kept.append(moved)
	for wing: Dictionary in Layout.nook_wings():
		var middle: Vector3 = wing.center
		var size: Vector3 = wing.size
		kept.append({"name": wing.name, "kind": "wing", "base": Vector3(middle.x, 0.0, middle.z), "size": size, "yaw": 0})
	return kept

func build(world: Node3D, role: String) -> void:
	_drawn=role!="authority"
	if _drawn:
		assert(client_draw_factory.is_valid(), "Client presentation bootstrap must precede lobby construction")
		_client_draw=client_draw_factory.call()
		Visuals=_client_draw.visuals
		_environment=_client_draw.environment
	for row: Dictionary in architecture():
		_primitive(row.name,row.center,row.size,float(row.yaw)).set_meta("layer",LAYER|CAMERA_LAYER)
	var yard_props:=props()
	for row: Dictionary in yard_props:
		_primitive(row.name,row.base+Vector3.UP*row.size.y*.5,row.size,float(row.yaw))
	if not Layout.show_yard(): # the show's yard has no playground (swing, trampoline, slide, seesaw, furniture)
		playground=Playground.new()
		for body: StaticBody3D in playground.build(self):_bodies.append(body)
	if _drawn:
		Visuals.dress(self,yard_props)
		_environment.build(world,self)
	set_active(false)

func _primitive(label: String, center: Vector3, size: Vector3, yaw: float) -> Node3D:
	var body:=StaticBody3D.new()
	body.name=label;add_child(body)
	body.global_position=Layout.ORIGIN+center
	body.rotation.y=deg_to_rad(yaw)
	body.collision_layer=LAYER;body.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);_bodies.append(body)
	placements.append({"name":label,"origin":body.global_position,"size":size,"yaw":yaw,"layer":LAYER,"drawn":_drawn})
	return body

func set_active(on: bool) -> void:
	visible=on
	for body: StaticBody3D in _bodies:body.collision_layer=int(body.get_meta("layer",LAYER)) if on else 0
	if _drawn:_environment.set_active(on)
	set_process(on)
	set_physics_process(on)

## The playground's movers, trampoline and slide (lobby/playground.gd) on the run this yard stands in (game/game_run.gd: World/<yard>).
func _physics_process(_delta: float) -> void:
	if playground==null:return
	var world:=get_parent()
	playground.tick(world.get_parent() if world!=null else null)
