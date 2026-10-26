extends "res://modes/show/items_ui/item_look.gd"
## HOT EGGPLANT on a client (EXPERIMENT, docs/items.md): a 3 m cartoon eggplant strapped to the carrier's back on every machine (eggplant_mesh.gd, a child of the carrier's rig), the carrier's
## own machine walks `a` times as fast and jumps `b` times as high from the replicated effect (`mods`), a pill at the bottom counts the seconds on its owner's screen, a number hangs over the
## eggplant in the last seconds while it heats up and shakes. A pass is a new effect with a source: the same eggplant flies over in an arc from the passer to the new carrier and lands on its
## back with a squash. When the effect goes without a pass (time, the goal) the eggplant pops: confetti and chunks, and the carrier's screen reads the cast's "pop" banner.
const EggMesh := preload("res://modes/show/items_ui/eggplant_mesh.gd")
const ItemsRules := preload("res://modes/show/items/items.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const DROP_FROM := 4.2 ## m the first strap-on falls from
const DROP_TIME := 0.42 ## s of the fall
const ARC_TIME := 0.55 ## s a pass flies
const ARC_HEIGHT := 3.0 ## m the arc rises over the straight line
const HOT := 5.0 ## s before the end that the eggplant heats up and the number shows
const CONFETTI := [Color("7a2fa8"), Color("4fb03f"), Color("fff3d1"), Color("f2b632"), Color("ff6fa8"), Color("3d7bff")]

var _carried := {} ## slot -> the effect that carries the eggplant there

class Pill extends Control:
	var fx: Dictionary = {}
	var icon: Callable
	var words := "EGGPLANT"
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if fx.is_empty(): return
		var view := get_viewport_rect().size
		var k := Kit.k(self)
		var left := maxf(float(fx.dur) - float(fx.age), 0.0)
		var pop := ShowTheme.pop_scale(float(fx.age), 0.35, 0.3)
		var alpha := clampf(left / 0.3, 0.0, 1.0)
		var right := view.x * 0.5 + 150.0 * k * pop
		var rect := Kit.icon_pill(self, "%s  %d" % [words, ceili(left)], right, view.y - 205.0 * k, k * pop, alpha, 1.0, 300.0 * k, ShowTheme.RED if left < HOT else ShowTheme.PURPLE)
		icon.call(self, Kit.icon_centre(rect), Kit.icon_radius(rect), alpha)

func banner_kind() -> String:
	return "alert"

func rehearsal() -> Dictionary:
	var catalog := preload("res://modes/show/items/catalog.gd")
	return {"dur": catalog.tuning(id, "duration"), "a": catalog.tuning(id, "speed"), "b": catalog.tuning(id, "jump")}

## A tilted purple eggplant with a green cap.
func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var turn := deg_to_rad(38.0)
	var axis := Vector2(sin(turn), -cos(turn)) # up and to the right
	var side := Vector2(cos(turn), sin(turn))
	var body := PackedVector2Array()
	for step in 28:
		var t := float(step) / 28.0 * TAU
		var along := sin(t) # -1 the bulb, 1 the neck
		var wide := cos(t) * 0.46 * (1.0 - 0.34 * clampf((along + 0.2) / 1.2, 0.0, 1.0)) # round at the bottom, slimmer towards the neck
		body.append(c - axis * r * 0.1 + axis * along * 0.78 * r + side * wide * r)
	ci.draw_colored_polygon(body, Color(0.5, 0.2, 0.68, a))
	var shine := c - axis * r * 0.38 - side * r * 0.2
	ci.draw_circle(shine, r * 0.09, Color(1.0, 0.9, 1.0, a * 0.7))
	var cap_at := c + axis * r * 0.66
	var cap := PackedVector2Array()
	for step in 10:
		var t := float(step) / 10.0 * TAU
		var spike := 0.2 + 0.1 * (step % 2)
		cap.append(cap_at + (axis * cos(t) + side * sin(t)) * r * spike * 1.5)
	ci.draw_colored_polygon(cap, Color(0.35, 0.75, 0.3, a))
	ci.draw_line(cap_at, cap_at + axis * r * 0.34 + side * r * 0.08, Color(0.3, 0.62, 0.24, a), r * 0.12, true)

# ------------------------------------------------------------------ the effect

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	var slot := int(fx.slot)
	var src := int(fx.src)
	var old: Variant = _carried.get(src) if src >= 0 else null
	var node: Node3D = null
	fx["mode"] = "drop"
	if old is Dictionary and (old as Dictionary).get("node") != null and is_instance_valid((old as Dictionary).node) and int((old as Dictionary).slot) != slot:
		node = (old as Dictionary).node # the same eggplant, flown over
		(old as Dictionary).erase("node")
		(old as Dictionary)["passed"] = true
		if node.get_parent() != null: node.reparent(m, true)
		fx["from"] = node.global_transform
		fx["mode"] = "arc"
	else:
		node = EggMesh.build()
		m.add_child(node)
		node.visible = false
		if src >= 0: # a pass this machine did not see start: it flies in from where the passer stands
			fx["from"] = Transform3D(EggMesh.mount().basis, m.feet(src) + Vector3(0.0, 1.0, 0.0))
			fx["mode"] = "arc"
	if float(fx.age) > 1.0: fx["mode"] = "worn" # a machine that joined late sees it worn, not falling or flying
	fx["node"] = node
	fx["t"] = 0.0
	fx["num"] = -1
	var label := Label3D.new()
	label.name = "Count"
	label.font = ShowTheme.font()
	label.font_size = 128
	label.pixel_size = 0.012
	label.outline_size = 26
	label.outline_modulate = Color(0.25, 0.02, 0.05)
	label.modulate = Color(1.0, 0.86, 0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.double_sided = true
	label.no_depth_test = true
	label.render_priority = 8
	label.position = Vector3(0.5, 3.4, 0.0)
	label.visible = false
	node.add_child(label)
	_carried[slot] = fx
	if bool(fx.mine):
		var pill := Pill.new()
		pill.name = "EggplantPill"
		pill.fx = fx
		pill.icon = draw_icon
		pill.words = preload("res://modes/show/items/catalog.gd").text(id, "name")
		m.over_layer.add_child(pill)
		fx["pill"] = pill

func update_fx(fx: Dictionary, dt: float) -> void:
	var node: Node3D = fx.get("node")
	if m == null or node == null or not is_instance_valid(node): return
	var rig: Node3D = m.rig(int(fx.slot))
	if rig == null:
		node.visible = false
		return
	var age := float(fx.age)
	var left := maxf(float(fx.dur) - age, 0.0)
	var mount := EggMesh.mount()
	var hot := clampf(1.0 - left / HOT, 0.0, 1.0)
	var sway := Basis(Vector3.BACK, 0.035 * sin(age * 4.6) + 0.025 * hot * sin(age * 41.0)) # a slow sway, a nervous shake as it heats up
	var worn := Transform3D(mount.basis * sway, mount.origin)
	fx["t"] = float(fx.t) + dt
	var t := float(fx.t)
	match str(fx.mode):
		"drop":
			if node.get_parent() != rig: _wear(node, rig)
			node.visible = true
			var u := clampf(t / DROP_TIME, 0.0, 1.0)
			var landed := t - DROP_TIME
			var squash := 0.2 * exp(-maxf(landed, 0.0) * 8.0) * sin(maxf(landed, 0.0) * 26.0) if landed > 0.0 else 0.0
			node.transform = Transform3D(Basis(Vector3.RIGHT, -0.9 * (1.0 - u)) * worn.basis * Basis.from_scale(Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash)), worn.origin + Vector3(0.0, DROP_FROM * (1.0 - u * u), 0.0))
		"arc":
			node.visible = true
			if node.get_parent() != m: node.reparent(m, true)
			var u := clampf(t / ARC_TIME, 0.0, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var target: Transform3D = rig.global_transform * worn
			var start: Transform3D = fx.from
			var turn := Quaternion(Vector3.RIGHT, -TAU * e)
			var spun := Basis(start.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), e) * turn)
			node.global_transform = Transform3D(spun, start.origin.lerp(target.origin, e) + Vector3.UP * ARC_HEIGHT * 4.0 * e * (1.0 - e))
			if u >= 1.0:
				_wear(node, rig)
				fx["mode"] = "land"
				fx["t"] = 0.0
		_:
			if node.get_parent() != rig: _wear(node, rig)
			node.visible = true
			var squash := 0.16 * exp(-t * 8.0) * sin(t * 26.0) if str(fx.mode) == "land" else 0.0
			node.transform = Transform3D(worn.basis * Basis.from_scale(Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash)), worn.origin)
	_heat(fx, node, left, hot)
	var pill: Control = fx.get("pill")
	if pill != null: pill.queue_redraw()

## Hangs the eggplant on `rig` at the mount.
func _wear(node: Node3D, rig: Node3D) -> void:
	if node.get_parent() != null: node.get_parent().remove_child(node)
	rig.add_child(node)
	node.transform = EggMesh.mount()

## Heats the body (a red glow that pulses faster and faster) and counts the last seconds over the stem.
func _heat(fx: Dictionary, node: Node3D, left: float, hot: float) -> void:
	var body := node.get_node_or_null("Body") as MeshInstance3D
	if body != null:
		var material := body.material_override as StandardMaterial3D
		material.emission_enabled = hot > 0.0
		if hot > 0.0:
			material.emission = Color(1.0, 0.18, 0.08)
			material.emission_energy_multiplier = hot * (0.25 + 0.55 * (0.5 + 0.5 * sin(float(fx.age) * (8.0 + 18.0 * hot))))
	var label := node.get_node_or_null("Count") as Label3D
	if label == null: return
	var number := ceili(left)
	label.visible = left <= HOT and left > 0.0 and str(fx.mode) != "arc"
	if label.visible and number != int(fx.num):
		fx["num"] = number
		label.text = str(number)
		fx["num_at"] = float(fx.age)
	if label.visible: label.scale = Vector3.ONE * ShowTheme.pop_scale(float(fx.age) - float(fx.get("num_at", 0.0)), 0.3, 0.5)

func end_fx(fx: Dictionary) -> void:
	var pill: Control = fx.get("pill")
	if pill != null and is_instance_valid(pill): pill.queue_free()
	fx.erase("pill")
	if _carried.get(int(fx.slot)) == fx: _carried.erase(int(fx.slot))
	var node: Node3D = fx.get("node")
	fx.erase("node")
	if node == null or not is_instance_valid(node): return # handed on: the new effect owns the eggplant now
	var at := node.global_position + node.global_basis.y.normalized() * 1.3 if node.is_inside_tree() else Vector3.ZERO
	node.queue_free()
	if node.is_inside_tree(): _pop(at)

func mods(fx: Dictionary) -> Dictionary:
	return {"speed": maxf(float(fx.a), 0.3), "jump": maxf(float(fx.b), 0.3), "dash": maxf(float(fx.a), 0.3)}

# ------------------------------------------------------------------ pop

## Confetti and chunks of eggplant burst from `at`, with a flash.
func _pop(at: Vector3) -> void:
	if m == null or m.leaving or not m.is_inside_tree(): return
	var holder := Node3D.new()
	holder.name = "EggplantPop"
	m.add_child(holder)
	holder.global_position = at
	m.sfx(id, "pop", at, 2.0)
	var ramp := Gradient.new()
	var colours := PackedColorArray(CONFETTI)
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT # single colours, not a blend of them
	ramp.colors = colours
	var offsets := PackedFloat32Array()
	for index in colours.size(): offsets.append(float(index) / float(colours.size() - 1))
	ramp.offsets = offsets
	var paper := CPUParticles3D.new()
	paper.name = "Confetti"
	paper.amount = 120
	paper.lifetime = 1.7
	paper.one_shot = true
	paper.explosiveness = 1.0
	paper.local_coords = false
	paper.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	paper.emission_sphere_radius = 0.6
	paper.direction = Vector3.UP
	paper.spread = 180.0
	paper.initial_velocity_min = 4.0
	paper.initial_velocity_max = 11.0
	paper.gravity = Vector3(0.0, -9.0, 0.0)
	paper.damping_min = 1.5
	paper.damping_max = 3.0
	paper.angle_min = 0.0
	paper.angle_max = 360.0
	paper.angular_velocity_min = -540.0
	paper.angular_velocity_max = 540.0
	paper.scale_amount_min = 0.7
	paper.scale_amount_max = 1.3
	paper.color_initial_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.24)
	var sheet := StandardMaterial3D.new()
	sheet.vertex_color_use_as_albedo = true
	sheet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheet.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = sheet
	paper.mesh = quad
	holder.add_child(paper)
	paper.emitting = true
	var chunks := CPUParticles3D.new()
	chunks.name = "Chunks"
	chunks.amount = 12
	chunks.lifetime = 1.4
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.local_coords = false
	chunks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chunks.emission_sphere_radius = 0.4
	chunks.direction = Vector3.UP
	chunks.spread = 180.0
	chunks.initial_velocity_min = 3.0
	chunks.initial_velocity_max = 8.0
	chunks.gravity = Vector3(0.0, -16.0, 0.0)
	chunks.angular_velocity_min = -360.0
	chunks.angular_velocity_max = 360.0
	chunks.scale_amount_min = 0.7
	chunks.scale_amount_max = 1.5
	var piece := BoxMesh.new()
	piece.size = Vector3(0.22, 0.22, 0.22)
	piece.material = EggMesh.material("body")
	chunks.mesh = piece
	holder.add_child(chunks)
	chunks.emitting = true
	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	flash.mesh = ball
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(1.0, 0.7, 0.95, 0.7)
	flash.material_override = glow
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(flash)
	flash.scale = Vector3.ONE * 0.6
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 5.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(glow, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_interval(2.0)
	tween.chain().tween_callback(holder.queue_free)

# ------------------------------------------------------------------ events

func on_event(type: int, a: int, b: int) -> void:
	if m == null: return
	var catalog := preload("res://modes/show/items/catalog.gd")
	match type:
		ItemsRules.Event.HIT:
			if a >= 0: m.tell(catalog.line(id, m.name_of(a), m.name_of(b), "pass")) # a pass (the clock's first handout has no passer: the manager's own line)
		ItemsRules.Event.END:
			if b == m.my_slot: m.say("boon", catalog.text(id, "pop"))
