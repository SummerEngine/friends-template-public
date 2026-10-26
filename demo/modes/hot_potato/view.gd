extends "res://modes/mode_view.gd"
## HOT POTATO view (docs/modes/hot_potato.md). The potato is the team's carried thing, drawn over the yard prop the rules picked
## (players/prop_look.gd draws the props under the world node "LooseProps"; this view hides that one and follows it): with two
## players the team's painting (style/carry_item.gd: the cast's object and picture) standing up and turned to the camera, with three or
## more the team's balloon look (balloon/balloon_look.gd: its shape and print) without its string. Both are bigger than the other
## props and throb on a beat that speeds up as the hidden fuse burns down (state heat); a flat ring on the floor marks where it is.
## A pop: the thing bursts, the cast's zap word over the player it zapped, the pop and zap sounds, a cry when it was their last life.
## The HUD: the title, POP! and who it zapped, "3, 2, 1", who has it, the lives as the scoreboard (players out greyed); never the fuse.
const TeamCast := preload("res://style/team_cast.gd")
const CarryItem := preload("res://style/carry_item.gd")
const BalloonLook := preload("res://balloon/balloon_look.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const PropSim := preload("res://players/prop_sim.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Modes := preload("res://modes/modes.gd")
const Ui := preload("res://client/friends_ui.gd")
const NOTE := "WASD move  ·  Space jumps  ·  F grabs and throws  ·  Don't hold it when it pops"
const PAINTING_SCALE := 0.34 ## the 3.25 m painting at about 1.1 m across
const BALLOON_SCALE := 0.7 ## the balloon look at 0.84 m across (the yard props are 0.5 m)
const PAINTING_LIFT := 0.06 ## m the standing painting sits above the prop's centre (its foot just over the floor)
const BEAT := Vector2(1.0, 6.5) ## throbs per second: a fresh fuse, a fuse about to pop
const THROB := Vector2(0.08, 0.24) ## how much a throb swells it: a fresh fuse, a fuse about to pop
const RING_RADIUS := 0.7
const RING_COLOR := Ui.DANGER
const WORD_HEIGHT := 2.4 ## m above the zapped player's feet
const FLECK_SECONDS := 1.4
const FOLLOW := 16.0 ## 1/s: without the yard's prop node the potato eases to the replicated spot

var _potato: Node3D ## the pivot: where the potato is, its throb
var _painting: Node3D ## 2 players: the team's carried thing
var _balloon: BalloonLook ## 3+ players: the team's balloon look
var _sim: BalloonSim ## what the balloon look draws (alive, velocity), at the pivot
var _ring: MeshInstance3D
var _prop: Node3D ## the drawn yard prop the potato covers
var _prop_index := -1
var _drawn := Vector3.INF
var _velocity := Vector3.ZERO
var _beat := 0.0
var _pops_seen := -1
var _count_heard := 0
var _go_heard := false
var _cheered := false
var _flecks: Node3D
var _fleck_age := 0.0

func build() -> void:
	_potato = Node3D.new()
	_potato.name = "Potato"
	add_child(_potato)
	if seats.size() <= 2:
		var item := CarryItem.build_intact()
		# The tray-flat painting stands up: its picture (+y) faces the pivot's +z, the picture's top (+x) points up.
		item.basis = Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT).scaled(Vector3.ONE * PAINTING_SCALE)
		_painting = Node3D.new()
		_painting.name = "Painting"
		_painting.add_child(item)
		_potato.add_child(_painting)
	else:
		_balloon = BalloonLook.new()
		_balloon.name = "Balloon"
		_potato.add_child(_balloon)
		if _balloon.shape == "balloon": _balloon.shape = "ball" # no knot and string trailing on the floor
		_balloon.scale = Vector3.ONE * BALLOON_SCALE
		var sticker := _balloon.get_node_or_null("BalloonPrint") as MeshInstance3D
		if sticker != null: # the print faces the camera unscaled (balloon_print.gdshader): size it to the smaller body
			var quad := sticker.mesh as QuadMesh
			quad.size *= BALLOON_SCALE
			(sticker.material_override as ShaderMaterial).set_shader_parameter("lift", BalloonSim.RADIUS * 1.15 * BALLOON_SCALE)
		_sim = BalloonSim.new()
	_ring = MeshInstance3D.new()
	_ring.name = "PotatoRing"
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.07
	torus.outer_radius = RING_RADIUS
	torus.rings = 32
	torus.ring_segments = 6
	_ring.mesh = torus
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = RING_COLOR
	_ring.material_override = paint
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	add_child(_ring)

func _exit_tree() -> void:
	if _prop != null and is_instance_valid(_prop): _prop.visible = true
	if _flecks != null and is_instance_valid(_flecks): _flecks.queue_free()

func present(state: Dictionary, dt: float) -> void:
	if _potato == null: return
	_step_flecks(dt)
	if state.is_empty():
		_potato.visible = false
		_ring.visible = false
		return
	var phase := str(state.get("phase", "live"))
	_cover(int(state.get("potato", -1)), str(state.get("kind", "")))
	_hear(state)
	var shown := phase == "live" or phase == "count"
	var heat := float(state.get("heat", 0.0)) if phase == "live" else 0.0
	_beat += dt * (lerpf(BEAT.x, BEAT.y, pow(heat, 1.5)) if phase == "live" else BEAT.x * 0.8)
	var throb := pow(maxf(sin(_beat * TAU), 0.0), 3.0) * lerpf(THROB.x, THROB.y, heat)
	var at := _where(state, dt)
	if phase == "pop" or phase == "over": at = _vector(state.get("pop_at"), at)
	var radius := float(PropSim.KINDS.get(str(state.get("kind", "")), 0.25))
	_potato.visible = true
	_potato.scale = Vector3.ONE * (1.0 + throb)
	if _painting != null:
		_painting.visible = shown
		_potato.position = at + Vector3.UP * PAINTING_LIFT
		var camera := _camera()
		if camera != null:
			var to := camera.global_position - _potato.global_position
			_potato.basis = Basis(Vector3.UP, atan2(to.x, to.z)).scaled(Vector3.ONE * (1.0 + throb))
	else:
		_potato.position = at + Vector3.UP * (BalloonSim.RADIUS * BALLOON_SCALE * (1.0 + throb) - radius + 0.02)
		_sim.alive = shown
		_sim.velocity = _velocity
		_balloon.follow(_sim, dt)
	_ring.visible = shown
	_ring.position = Vector3(at.x, WalkInLobby.FLOOR_Y + 0.02, at.z)
	var swell := 1.0 + throb * 1.5
	_ring.scale = Vector3(swell, 0.15, swell)
	if phase == "over" and not _cheered:
		_cheered = true
		_emote(int(state.get("winner", -1)), "dance")

func hud(state: Dictionary) -> Dictionary:
	var model := {"title": str(Modes.info("hot_potato").get("title", "HOT POTATO")), "timer": -1.0, "note": NOTE}
	if state.is_empty(): return model
	var lives: Array = state.get("lives", []) if state.get("lives") is Array else []
	model.scores = lives
	model.out = state.get("out", []) if state.get("out") is Array else []
	match str(state.get("phase", "live")):
		"pop":
			model.big = TeamCast.word("pop")
			var zapped := int(state.get("zapped", -1))
			if zapped >= 0:
				var left := int(lives[zapped]) if zapped < lives.size() else 0
				model.line = "%s IS OUT" % _name(zapped) if bool(state.get("zapped_out", false)) else "%s  ·  %d %s LEFT" % [_name(zapped), left, "LIFE" if left == 1 else "LIVES"]
		"count":
			model.big = str(maxi(int(state.get("count", 0)), 1))
			model.line = "PASS IT ON BEFORE IT POPS"
		"over":
			var winner := int(state.get("winner", -1))
			model.big = "%s WINS" % _name(winner) if winner >= 0 else "GAME OVER"
			model.line = "LAST ONE WITH LIVES LEFT"
		_:
			if bool(state.get("go", false)): model.big = "GO!"
			var holder := int(state.get("holder", -1))
			var own := _own_slot()
			if holder >= 0 and holder == own: model.line = "YOU HAVE IT! THROW IT ON"
			elif holder >= 0: model.line = "%s HAS IT" % _name(holder)
			else: model.line = "NOBODY HAS IT  ·  THE CLOSEST ONE POPS"
			if own >= 0 and own < lives.size() and int(lives[own]) <= 0: model.line = "YOU ARE OUT  ·  " + str(model.line)
	return model

# ------------------------------------------------------------------ drawing

## The yard prop the rules made the potato: hidden while this view is up (it draws the potato in its place).
func _cover(index: int, kind: String) -> void:
	if index == _prop_index and (_prop == null or is_instance_valid(_prop)): return
	if _prop != null and is_instance_valid(_prop): _prop.visible = true
	_prop = null
	_prop_index = index
	var props: Node = run.world.get_node_or_null("LooseProps") if run != null and run.world != null else null
	if props == null or index < 0: return
	_prop = props.get_node_or_null("Prop_%s_%d" % [kind, index]) as Node3D
	if _prop != null: _prop.visible = false

## Where the potato is drawn: the yard prop's drawn node (it eases between snapshots and sits in its holder's hands), else
## the replicated spot.
func _where(state: Dictionary, dt: float) -> Vector3:
	var target: Vector3
	if _prop != null and is_instance_valid(_prop): target = _prop.global_position
	else:
		target = _vector(state.get("at"), Vector3.ZERO)
		if _drawn.is_finite() and _drawn.distance_to(target) < 3.0: target = _drawn.lerp(target, 1.0 - exp(-dt * FOLLOW))
	if _drawn.is_finite() and dt > 0.0: _velocity = _velocity.lerp((target - _drawn) / dt, clampf(dt * 8.0, 0.0, 1.0))
	_drawn = target
	return target

func _camera() -> Camera3D:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null and run != null: camera = run.get("camera") as Camera3D
	return camera

## The painting bursts into flecks (the balloon look bursts by itself when it is no longer alive).
func _burst(at: Vector3, seed_value: int) -> void:
	if _painting == null: return
	if _flecks != null and is_instance_valid(_flecks): _flecks.queue_free()
	var anchors: Array = []
	for i in 8: anchors.append(at + Vector3(cos(TAU * i / 8.0) * 0.5, 0.15 + 0.1 * sin(i * 1.7), sin(TAU * i / 8.0) * 0.2))
	_flecks = CarryItem.build_flecks(seed_value, anchors, at)
	_fleck_age = 0.0
	if _flecks != null: add_child(_flecks)

func _step_flecks(dt: float) -> void:
	if _flecks == null or not is_instance_valid(_flecks): return
	_fleck_age += dt
	CarryItem.animate_flecks(_flecks, _fleck_age, WalkInLobby.FLOOR_Y, FLECK_SECONDS * 0.6, FLECK_SECONDS)
	if _fleck_age >= FLECK_SECONDS:
		_flecks.queue_free()
		_flecks = null

# ------------------------------------------------------------------ events (counters in the state: shown once, never replayed)

func _hear(state: Dictionary) -> void:
	var audio = run.get("audio") if run != null else null
	var pops := int(state.get("pops", 0))
	if _pops_seen < 0: _pops_seen = pops # a view built mid-round shows no old pops
	elif pops > _pops_seen:
		_pops_seen = pops
		var at := _vector(state.get("pop_at"), Vector3.ZERO)
		var zapped := int(state.get("zapped", -1))
		_burst(at, pops * 7919)
		if audio != null: audio.play_event("pop", at)
		if zapped >= 0 and zapped < seats.size():
			var feet_at := feet(zapped)
			if run.world != null: HazardLooks.word(run.world, TeamCast.word("zap"), feet_at + Vector3.UP * WORD_HEIGHT)
			if audio != null: audio.play_event("zap", feet_at + Vector3.UP)
			if bool(state.get("zapped_out", false)): _emote(zapped, "cry")
	var count := int(state.get("count", 0))
	if count > 0 and count != _count_heard and audio != null: audio.play_event("countdown", null, 1.0, 2.0 * (3 - count))
	_count_heard = count
	var go := bool(state.get("go", false))
	if go and not _go_heard and audio != null and _pops_seen > 0: audio.play_event("go")
	_go_heard = go

func _emote(slot: int, emote: String) -> void:
	var body := rig(slot)
	if body != null and body.has_method("play_emote"): body.play_emote(emote)

## The slot this screen plays, -1 on one machine (two players share the screen: names only).
func _own_slot() -> int:
	return -1 if run != null and str(run.get("network_role")) == "local" else my_slot

func _name(slot: int) -> String:
	return str(cast_player(slot).name)

static func _vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
