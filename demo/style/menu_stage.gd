extends SubViewportContainer
## The 3D backdrop of the title and the results. Title: the cast's characters (the real rigs with the cast's looks and emotes) standing in an arc on a round cushion in the brand's primary colour, idling, now and then doing
## their emote, over nothing: the viewport is transparent, the page's yellow rings (menu_backdrop.gd) show behind them. Results: the podium room of the show's ending (style/podium_room.gd: glossy gold, pink and turquoise pedestals, runners, sunburst billboards, horns, confetti)
## with the top three on it. It is its own World3D in a SubViewport, so the live course behind the menu is never touched.
##   MenuStage.new("title")       the whole cast grouped on blocks at staggered heights on a tile deck, the picture shifted right (the menu column sits on the left)
##   MenuStage.new("results")     the top of `set_ranking([seat, ...])` on the three pedestals, the picture shifted right by `shift` (the table sits on the left)
##   stage.cheer()                everybody jumps for joy (PLAY pressed)
## Nothing here reads input; `process_mode` is always, so it plays under the paused tree.
const CandyLight := preload("res://style/candy_light.gd")
const CandyLook := preload("res://style/candy_look.gd")
const Rig := preload("res://character/character_rig.gd")
const Look := preload("res://character/look.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const PodiumRoom := preload("res://style/podium_room.gd")
const VictoryFlow := preload("res://modes/show/shared/victory_flow.gd")
const Kit := preload("res://style/menu_kit.gd")

const ROOM_SKIP := 1.0 ## s of the victory flow's podium timeline skipped on the results page (the first landing comes sooner)
const ROOM_LOOK_Y := 2.6 ## m: the height the results' camera looks at (the pedestals and their winners; the billboards rise behind the banner)
const CAST_MIN := 5 ## characters on the title even for a small cast (the other seats wear the default looks)
const CAST_MAX := 8
const FOV := 30.0
const SUN_AZIMUTH := 39.0 ## degrees: the title stage's sun comes from the front left
const EMOTES := ["yes", "dance", "point", "dance", "yes"] ## what the characters do in turn (the cast's own emote first)
const CUSHION_RADIUS := 4.1 ## m: the round cushion the title's cast stands on
const CUSHION_THICK := 0.5

var kind := "title"
var _vp: SubViewport
var _world: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _figures: Array[Dictionary] = [] ## {rig, home, yaw, next, jump}
var _clock := 0.0
var _room: Node3D ## results: the podium room
var shift := 0.0 ## results: how far the picture sits right of the middle (a share of half the width at the screens: the results page keeps its table on the left)
var zoom := 1.0 ## results: the camera's distance as a factor of the default (a table on both sides leaves the middle narrower)
var _ranking: Array = []

func _init(stage_kind := "title") -> void:
	kind = stage_kind
	name = "MenuStage"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = stage_kind == "title" # the title's page draws its rings behind the characters
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	add_child(_vp)

func _ready() -> void:
	_build()

func _build() -> void:
	_world = Node3D.new()
	_world.name = "World"
	_vp.add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = PodiumRoom.environment() if kind == "results" else _title_environment()
	_world.add_child(environment)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_world.add_child(_sun)
	CandyLight.apply_sun(_sun, SUN_AZIMUTH) # from the front left and above: faces lit, the shadow falls back and right
	_sun.directional_shadow_max_distance = 26.0
	var fill: DirectionalLight3D = null
	if CandyLight.has_fill(CandyLight.world_scale()):
		fill = CandyLight.make_fill()
		_world.add_child(fill)
		fill.global_basis = Basis.looking_at(-CandyLook.towards(CandyLook.FILL_ELEVATION, CandyLook.FILL_AZIMUTH), Vector3.UP)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = FOV
	_camera.current = true
	_camera.far = 5000.0 # the candy world's cloud wall stands 2600 m out (650 m on a phone)
	_world.add_child(_camera)
	if kind == "results": # the podium room of the show's ending (its own sky and lights)
		_sun.visible = false # the room has its own sun and fill
		if fill != null: fill.visible = false
		_room = PodiumRoom.new()
		_world.add_child(_room)
		_room.build()
		return
	_stage()
	if Rig.available(): _cast()

# ------------------------------------------------------------------ the stage

func _material(color: Color, rough := 0.6) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic_specular = 0.3
	return material

func _mesh(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

## A rounded block of the podium room's kind (`PodiumRoom.rounded_box`).
func _box(parent: Node3D, size3: Vector3, color: Color, at: Vector3, rough := 0.5, radius := 0.08) -> MeshInstance3D:
	return _mesh(parent, PodiumRoom.rounded_box(size3 * 0.5, minf(radius, minf(size3.x, minf(size3.y, size3.z)) * 0.45)), _material(color, rough), at)

## The title's light: the candy world's grade and ambient (so the characters look as they do in the show) over a clear background (the viewport is transparent).
func _title_environment() -> Environment:
	var env := CandyLight.environment(CandyLight.world_scale())
	env.background_mode = Environment.BG_CLEAR_COLOR
	return env

## The title's cushion: a round satin pad in the primary colour with a violet foot and a lighter lip, the podium blocks of `_blocks()` on it. The characters stand on its top (y 0).
func _stage() -> void:
	var primary := Kit.primary_color()
	var foot := CylinderMesh.new()
	foot.top_radius = CUSHION_RADIUS * 1.05
	foot.bottom_radius = CUSHION_RADIUS * 1.05
	foot.height = CUSHION_THICK * 0.6
	foot.radial_segments = 72
	_mesh(_world, foot, _material(Kit.VIOLET, 0.42), Vector3(0.0, -CUSHION_THICK * 0.7, 0.0)).name = "CushionFoot"
	var pad := CylinderMesh.new()
	pad.top_radius = CUSHION_RADIUS
	pad.bottom_radius = CUSHION_RADIUS
	pad.height = CUSHION_THICK * 0.85
	pad.radial_segments = 72
	_mesh(_world, pad, _material(primary, 0.4), Vector3(0.0, -CUSHION_THICK * 0.42, 0.0)).name = "Cushion"
	var lip := TorusMesh.new()
	lip.inner_radius = CUSHION_RADIUS - 0.2
	lip.outer_radius = CUSHION_RADIUS + 0.12
	lip.rings = 72
	lip.ring_segments = 14
	_mesh(_world, lip, _material(primary.lerp(Color.WHITE, 0.3), 0.35), Vector3(0.0, -0.06, 0.0)).name = "CushionLip"
	_blocks()

## The title's blocks under the characters (the slots with a height): rounded podium blocks in the show's colours.
func _blocks() -> void:
	var colors := {2: PodiumRoom.PEDESTAL[0], 1: PodiumRoom.PEDESTAL[1], 3: PodiumRoom.PEDESTAL[2]} # gold in the middle, pink and turquoise either side: the podium room's pedestals
	for index: int in colors:
		var slot: Vector3 = SLOTS[index]
		_block(Vector3(slot.x, 0.0, slot.z), 1.4, slot.y, colors[index])

## A block with a lighter cap.
func _block(at: Vector3, edge: float, height: float, color: Color) -> void:
	_box(_world, Vector3(edge, height, edge), color, Vector3(at.x, height * 0.5, at.z), PodiumRoom.PEDESTAL_ROUGH, PodiumRoom.PEDESTAL_R).name = "Block"
	_box(_world, Vector3(edge + 0.1, 0.12, edge + 0.1), color.lightened(0.3), Vector3(at.x, height - 0.04, at.z), PodiumRoom.PEDESTAL_ROUGH, 0.05).name = "BlockCap"

# ------------------------------------------------------------------ the cast

## Where the title's characters stand on the deck (x, height of their block, z): front corners on the deck, the rest on the blocks of `_blocks()`, the middle one the highest; seven slots, the cast fills them in order.
const SLOTS := [Vector3(-2.5, 0.0, 0.7), Vector3(-1.1, 0.55, -1.0), Vector3(0.35, 0.95, -1.9), Vector3(1.75, 0.55, -1.0), Vector3(2.6, 0.0, 0.8), Vector3(-0.9, 0.0, 1.9), Vector3(1.0, 0.0, 2.0)]
## The slot order the cast takes: the middle block first, so a small cast is still a group.
const SLOT_ORDER := [2, 1, 3, 0, 4, 5, 6]

func _cast() -> void:
	var count := clampi(maxi(TeamCast.members().size(), CAST_MIN), CAST_MIN, CAST_MAX - 1)
	for index in count:
		var slot: Vector3 = SLOTS[SLOT_ORDER[index]]
		_figure(index, slot, PI - clampf(slot.x * 0.08, -0.3, 0.3))

## `set_ranking([seat, ...])`: the results' top three (best first) on the podium room's pedestals (1st in the middle, 2nd left, 3rd right), each landing on the victory flow's timeline.
## Everybody else is in the page's table, not on the stage.
func set_ranking(seats: Array) -> void:
	for figure: Dictionary in _figures:
		(figure.rig as Node).queue_free()
	_figures.clear()
	_ranking = seats.duplicate()
	_clock = 0.0
	if _room == null or not Rig.available(): return
	var count := mini(seats.size(), 3)
	var spots := PodiumRoom.spots()
	var lands := VictoryFlow.landed(count)
	for rank in count:
		_figure(int(seats[rank]), spots[rank], PI, rank == 0, float(lands[rank]))

func _figure(seat: int, home: Vector3, yaw: float, cheering := false, land := -1.0) -> void:
	var rig: Node3D = Rig.new()
	rig.name = "Seat%d" % seat
	_world.add_child(rig)
	rig.setup(seat, {"look": Look.defaults_for_seat(seat)})
	rig.position = home
	var still := {"yaw": yaw, "grounded": true, "velocity": Vector3.ZERO}
	rig.snap(still)
	var figure := {"rig": rig, "home": home, "yaw": yaw, "next": 0.4 + 0.9 * float(_figures.size()), "jump": -1.0, "cheering": cheering, "pick": _figures.size(), "stop": 0.0, "first": true}
	if land >= 0.0:
		figure.land = land
		rig.visible = false
	_figures.append(figure)

## Everybody jumps (PLAY pressed).
func cheer() -> void:
	for figure: Dictionary in _figures: figure.jump = 0.0

# ------------------------------------------------------------------ motion and framing

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var dt := minf(delta, 0.05)
	_clock += dt
	_frame()
	for figure: Dictionary in _figures:
		var rig: Node3D = figure.rig
		if figure.has("land"): # a winner on the podium appears with its landing (the victory flow's timeline) and hops once
			var down := _clock + ROOM_SKIP >= float(figure.land)
			rig.visible = down
			if down and not bool(figure.get("down", false)):
				figure.down = true
				figure.jump = 0.0
		var lift := 0.0
		if float(figure.jump) >= 0.0:
			figure.jump = float(figure.jump) + dt
			var t := float(figure.jump) / 0.7
			lift = maxf(sin(t * PI), 0.0) * 0.9
			if t >= 1.0: figure.jump = -1.0
		rig.position = (figure.home as Vector3) + Vector3(0.0, lift, 0.0)
		var stopping := float(figure.stop) > 0.0 and _clock >= float(figure.stop)
		rig.update(dt, {"yaw": figure.yaw, "grounded": lift <= 0.01, "velocity": Vector3(1.0 if stopping else 0.0, 4.0 if lift > 0.01 else 0.0, 0.0)})
		if stopping: figure.stop = 0.0 # a moving frame ends a looping emote (the dance)
		figure.next = float(figure.next) - dt
		if float(figure.next) <= 0.0:
			figure.next = 3.0 + randf() * 3.0
			if rig.emote_playing() == "":
				var pick: String = EMOTES[int(figure.pick) % EMOTES.size()]
				if figure.first and rig.cast_emote() != "": pick = rig.cast_emote()
				figure.first = false
				figure.pick = int(figure.pick) + 1
				rig.play_emote(pick)
				if pick in ["dance", "sit", "cry"]: figure.stop = _clock + 2.6 + randf() * 1.5 # the looping emotes

## The camera: above the deck, looking at the characters, the picture shifted so the group stands in the right half of the screen (title: the menu column sits on the left) or in the middle
## (results); it drifts slowly. The framing follows the aspect, so a phone (2.2) and a desktop (1.8) both keep the group whole.
func _frame() -> void:
	var aspect := minf(maxf(size.x / maxf(size.y, 1.0), 0.5), 2.0)
	if kind == "results":
		_frame_room(aspect)
		return
	var reach := tan(deg_to_rad(FOV) * 0.5)
	var width := 12.5 ## metres of the scene across the picture at the characters
	var distance := maxf(width / (2.0 * reach * aspect), 4.2 / reach)
	var drift := sin(_clock * 0.25) * 0.4
	var eye := Vector3(drift, 3.6, distance)
	var look := Vector3(drift * 0.4, 0.9, 0.0)
	_camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look, Vector3.UP)
	_camera.h_offset = -0.30 * width ## the group's centre at about 72 % of the width

## The results' camera: the podium room's wide frontal shot (the one the victory flow settles on), backed off by `zoom`, drifting a little, the picture shifted right by `shift` (a share of half the width at the screens).
func _frame_room(aspect: float) -> void:
	var framed := VictoryFlow.shot(3.0, aspect)
	var back: float = ((framed.xf as Transform3D).origin - (PodiumRoom.ORIGIN + Vector3(0.0, 4.0, 0.0))).z # how far the wide shot stands from the pedestals' plane
	var look := PodiumRoom.ORIGIN + Vector3(0.0, ROOM_LOOK_Y, 0.0)
	var eye := look + Vector3(0.0, 1.2, back) * zoom
	var drift := sin(_clock * 0.25) * 0.35
	eye.x += drift
	_camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(look + Vector3(drift * 0.4, 0.0, 0.0), Vector3.UP)
	_camera.fov = float(framed.fov)
	_camera.h_offset = -back * zoom * tan(deg_to_rad(_camera.fov) * 0.5) * minf(aspect, 2.0) * shift
	var t := _clock + ROOM_SKIP
	var count := mini(_ranking.size(), 3)
	(_room as Object).call("update", t, VictoryFlow.landed(count), VictoryFlow.bursts(count)) # no champion banner or name plates: the page's own banner and table say it
