extends "res://modes/show/items_ui/item_look.gd"
## CALL on a client (the urgent call, rules: call_rules.gd). The shot: a blue ring with a handset in it and a soft pulsing glow, a comet trail and a small light, flying along the
## replicated position (it is scaled up with the distance so it reads at 30 m); it bursts where it ends. The victim's own machine opens the call window (call_window.gd, over the
## game: it covers 72 % of the screen by area, its content kept clear of the HUD's pills, and the movement is not touched); everybody else sees a ringing phone over the victim's head for as long as it lasts.
const Catalog := preload("res://modes/show/items/catalog.gd")
const Glyph := preload("res://modes/show/items_ui/call_glyph.gd")
const CallWindow := preload("res://modes/show/items_ui/call_window.gd")

const HEAD := 2.5 ## m over a runner's feet: the phone over its head
const CHEST := 1.05 ## m: where the shot lands (as call_rules.gd CHEST)
const FAR := 16.0 ## m: beyond this the shot grows with the distance

## The window's length and the share of the screen it covers (`a`).
func rehearsal() -> Dictionary:
	return {"dur": Catalog.tuning(id, "window"), "a": Catalog.tuning(id, "cover"), "b": 0.0}

func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var col := Color(0.92, 0.96, 1.0, a)
	Glyph.draw_handset(ci, c + Vector2(0.0, r * 0.26), r * 0.72, col)
	Glyph.draw_waves(ci, c + Vector2(0.0, r * 0.12), r * 0.6, r * 0.24, r * 0.1, col, 2)

# ------------------------------------------------------------------ the shot

func begin_shot(shot: Dictionary) -> void:
	if m == null: return
	var root := Node3D.new()
	root.name = "CallShot"
	m.add_child(root)
	root.global_position = shot.p
	var body := Node3D.new()
	root.add_child(body)
	var halo := Glyph.piece(body, _quad(3.6), Glyph.material(Color(0.32, 0.58, 1.0, 0.85), true, Glyph.halo()), 0)
	var ripple_material := Glyph.material(Color(0.45, 0.7, 1.0, 0.7))
	var ripple := Glyph.piece(body, Glyph.ring_mesh(0.54, 0.6, -0.01), ripple_material, 1)
	Glyph.piece(body, Glyph.ring_mesh(0.0, 0.46, 0.0), Glyph.material(Color(0.02, 0.07, 0.3, 0.97)), 2)
	Glyph.piece(body, Glyph.ring_mesh(0.4, 0.56, 0.01), Glyph.material(Glyph.BLUE), 3)
	Glyph.piece(body, Glyph.handset_mesh(0.32, 0.02), Glyph.material(Glyph.LIGHT), 4)
	root.add_child(_trail())
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.62, 1.0)
	light.light_energy = 1.6
	light.omni_range = 6.0
	root.add_child(light)
	shot["node"] = root
	shot["body"] = body
	shot["halo"] = halo
	shot["ripple"] = ripple
	shot["ripple_material"] = ripple_material

func update_shot(shot: Dictionary, _dt: float) -> void:
	var root: Node3D = shot.get("node")
	if root == null or not is_instance_valid(root): return
	root.global_position = shot.p
	var camera := root.get_viewport().get_camera_3d()
	var far := camera.global_position.distance_to(shot.p) if camera != null else FAR
	var grow := clampf(far / FAR, 1.0, 2.6) # the shot stays readable far away
	var age := float(shot.age)
	(shot.body as Node3D).scale = Vector3.ONE * grow * (1.0 + 0.07 * sin(age * 14.0))
	(shot.halo as Node3D).scale = Vector3.ONE * (1.0 + 0.14 * sin(age * 9.0 + 1.0))
	var wave := fposmod(age, 0.7) / 0.7 # a ring leaves the shot every 0.7 s
	(shot.ripple as Node3D).scale = Vector3.ONE * lerpf(1.0, 2.3, wave)
	(shot.ripple_material as StandardMaterial3D).albedo_color.a = (1.0 - wave) * 0.7

func end_shot(shot: Dictionary) -> void:
	var root: Node3D = shot.get("node")
	if root == null or not is_instance_valid(root): return
	shot.erase("node")
	if not root.is_inside_tree():
		root.queue_free()
		return
	var at: Vector3 = root.global_position
	root.queue_free()
	var tgt := int(shot.get("tgt", -1))
	var hit: bool = tgt >= 0 and m != null and m.feet(tgt) != Vector3.ZERO and (m.feet(tgt) as Vector3 + Vector3(0.0, CHEST, 0.0)).distance_to(at) < 2.4
	_burst(at, hit)

## A comet trail: soft glowing dots that shrink and fade behind the shot.
func _trail() -> CPUParticles3D:
	var trail := CPUParticles3D.new()
	trail.amount = 90
	trail.lifetime = 0.55
	trail.local_coords = false
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.1
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.7
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.55
	trail.scale_amount_max = 0.9
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	trail.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.8, 0.92, 1.0, 0.95))
	ramp.set_color(1, Color(0.22, 0.42, 1.0, 0.0))
	trail.color_ramp = ramp
	trail.mesh = _dot_mesh(0.5)
	return trail

func _dot_mesh(size: float) -> QuadMesh:
	var quad := _quad(size)
	var mat := Glyph.material(Color.WHITE, true, Glyph.halo())
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	return quad

func _quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	return quad

## Where the shot ends: on its target a ring flash and sparks (the call lands), anywhere else it dissolves into a few falling sparks.
func _burst(at: Vector3, hit: bool) -> void:
	if m == null or not m.is_inside_tree(): return
	var puff := Node3D.new()
	puff.name = "CallBurst"
	m.add_child(puff)
	puff.global_position = at
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 30 if hit else 12
	sparks.lifetime = 0.55
	sparks.local_coords = false
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 2.0 if hit else 0.6
	sparks.initial_velocity_max = 6.5 if hit else 2.0
	sparks.gravity = Vector3(0.0, -6.0 if hit else -3.0, 0.0)
	sparks.scale_amount_min = 0.4
	sparks.scale_amount_max = 0.8
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	sparks.scale_amount_curve = shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.94, 1.0, 1.0))
	ramp.set_color(1, Color(0.25, 0.45, 1.0, 0.0))
	sparks.color_ramp = ramp
	sparks.mesh = _dot_mesh(0.4)
	puff.add_child(sparks)
	sparks.emitting = true
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_interval(0.7)
	var glow_material := Glyph.material(Color(0.6, 0.8, 1.0, 0.9 if hit else 0.35), true, Glyph.halo())
	var glow := Glyph.piece(puff, _quad(2.4), glow_material, 0)
	glow.scale = Vector3.ONE * 0.4
	tween.tween_property(glow, "scale", Vector3.ONE * (2.2 if hit else 1.0), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow_material, "albedo_color:a", 0.0, 0.32)
	if hit:
		var ring_material := Glyph.material(Color(0.5, 0.74, 1.0, 0.95))
		var ring := Glyph.piece(puff, Glyph.ring_mesh(0.45, 0.55, 0.0), ring_material, 1)
		ring.scale = Vector3.ONE * 0.5
		tween.tween_property(ring, "scale", Vector3.ONE * 3.2, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring_material, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(puff.queue_free)

# ------------------------------------------------------------------ the effect

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	if bool(fx.mine):
		var window := CallWindow.new()
		window.setup(self, fx, Catalog.media(id))
		m.over_layer.add_child(window)
		fx["node"] = window
	else:
		_head(fx)

## The phone over a runner's head (what the others see): a blue ring, a handset and two ring waves that blink outward.
func _head(fx: Dictionary) -> void:
	var rig: Node3D = m.rig(int(fx.slot))
	if rig == null: return
	var root := Node3D.new()
	root.name = "CallPhone"
	root.position = Vector3(0.0, HEAD, 0.0)
	rig.add_child(root)
	Glyph.piece(root, Glyph.ring_mesh(0.0, 0.27, 0.0, 0.0, TAU, 28), Glyph.material(Color(0.02, 0.07, 0.3, 0.95)), 2)
	Glyph.piece(root, Glyph.ring_mesh(0.23, 0.3, 0.01, 0.0, TAU, 28), Glyph.material(Glyph.BLUE), 3)
	Glyph.piece(root, Glyph.handset_mesh(0.18, 0.02), Glyph.material(Glyph.LIGHT), 4)
	var waves: Array = []
	for index in 2:
		var mat := Glyph.material(Glyph.LIGHT)
		Glyph.piece(root, Glyph.ring_mesh(0.4 + 0.1 * float(index), 0.45 + 0.1 * float(index), 0.02, deg_to_rad(40.0), deg_to_rad(140.0), 12), mat, 5)
		waves.append(mat)
	fx["node"] = root
	fx["waves"] = waves

func update_fx(fx: Dictionary, _dt: float) -> void:
	var node: Node = fx.get("node")
	if node == null or not is_instance_valid(node) or bool(fx.mine): return
	var age := float(fx.age)
	var phase := fposmod(age * 2.4, 1.0)
	var waves: Array = fx.get("waves", [])
	for index in waves.size():
		(waves[index] as StandardMaterial3D).albedo_color.a = 1.0 if phase > 0.2 + 0.3 * float(index) else 0.2
	var root := node as Node3D
	root.position.y = HEAD + 0.05 * sin(age * 9.0)
	root.scale = Vector3.ONE * 1.35 * (1.0 + 0.06 * sin(age * 28.0))

func end_fx(fx: Dictionary) -> void:
	var node: Node = fx.get("node")
	fx.erase("node")
	if node == null or not is_instance_valid(node): return
	if node.has_method("close"): node.close() # the window shrinks away and frees itself
	else: node.queue_free()
