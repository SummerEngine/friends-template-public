extends "res://modes/show/items_ui/item_look.gd"
## DANCE (the forced video) on a client. The projectile is a spinning phone with a sparkle trail that pops in confetti where it ends. When it hits, on EVERY screen the victim stands and dances
## (the rig's own dance emote, the courier frozen by its owner's machine through `mods`), wears the plain base look for the seconds (the rig's `set_look_over`, put back exactly when the effect
## goes, whatever way it goes) and carries a REC dot and a LIVE tag over its head; on the VICTIM'S screen only (`fx.mine`) dark bars close in to a vertical 9:16 frame, the camera swings round
## to the character's face and zooms in, and the frame wears a dumb filter (a shader that pulses saturation and tint), floating hearts and sparkles, a LIVE badge, a climbing view counter,
## a column of heart / comment / share buttons, a blinking REC and a few comments; all of it drawn as shapes, no logos.
const ShowTheme := preload("res://client/show_theme.gd")
const CharacterCatalog := preload("res://character/catalog.gd")
const DanceFrame := preload("res://modes/show/items_ui/dance_frame.gd")

const ZOOM_IN := 0.45 ## s the camera takes to swing round and in
const ZOOM_OUT := 0.4 ## s it takes to swing back, ending with the effect
const RANGE := 2.3 ## m from the character: a phone held out at arm's length, the upper body in the 9:16 frame
const FOV_CUT := 4.0 ## degrees the lens closes at the close-up
const FACE := 1.7 ## m over the feet the camera looks at: the face, so the head stands in the middle of the frame under the banner, the shoulders and chest below it and room above
const SOLID_LAYER := 1 ## physics layers the face-zoom camera stops at: the solid world, ...
const MOVER_LAYER := 16 ## ... the spinning and moving parts (couriers, layer 2, never stop it) ...
const CAMERA_BLOCKER := 256 ## ... and the big blocks that stop the follow camera
const TAG_HEIGHT := 2.75 ## m over the feet the REC / LIVE tag floats
const SPIN := 9.0 ## rad/s the phone tumbles end over end
const PHONE := Vector2(0.44, 0.74) ## m, the phone's body: 9:16 screen inside a thin bezel

static var _screen: Texture2D
static var _star: Texture2D
static var _glow: Texture2D
static var _phone: ArrayMesh

var _slots := {} ## slot -> {count, rig (instance id), plain}
var _hit_at := -1000000 ## Time.get_ticks_msec() of the last effect that began: a shot that ends then hit

func banner_kind() -> String:
	return "alert"

func tells_on_hit() -> bool:
	return true

# ------------------------------------------------------------------ the icon

func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var body := Rect2(c - Vector2(r * 0.45, r * 0.78), Vector2(r * 0.9, r * 1.56))
	ShowTheme.box(ci, body, Color(0.92, 0.96, 1.0, a), Color(0, 0, 0, 0), 0.0, r * 0.2)
	var screen := body.grow_individual(-r * 0.09, -r * 0.2, -r * 0.09, -r * 0.2)
	ShowTheme.box(ci, screen, Color(ShowTheme.NAVY, a), Color(0, 0, 0, 0), 0.0, r * 0.1)
	var mid := screen.get_center()
	ci.draw_colored_polygon(PackedVector2Array([mid + Vector2(-r * 0.15, -r * 0.24), mid + Vector2(-r * 0.15, r * 0.24), mid + Vector2(r * 0.25, 0.0)]), Color(1.0, 0.45, 0.72, a))
	ci.draw_circle(Vector2(c.x, body.position.y + r * 0.11), r * 0.04, Color(ShowTheme.NAVY, a))

# ------------------------------------------------------------------ the effect

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	_hit_at = Time.get_ticks_msec()
	var slot := int(fx.slot)
	var state: Dictionary = _slots.get(slot, {"count": 0, "rig": 0, "plain": null})
	state.count = int(state.count) + 1
	_slots[slot] = state
	_dress(slot)
	var rig: Node3D = m.rig(slot)
	if bool(fx.mine):
		var frame: Control = DanceFrame.new()
		frame.set("fx", fx)
		frame.set("who", m.name_of(slot).to_upper())
		m.over_layer.add_child(frame)
		fx["frame"] = frame
	elif rig != null:
		var tag := _tag()
		rig.add_child(tag)
		tag.position.y = TAG_HEIGHT
		fx["tag"] = tag

func update_fx(fx: Dictionary, _dt: float) -> void:
	if m == null: return
	var slot := int(fx.slot)
	_dress(slot)
	var rig: Node3D = m.rig(slot)
	if rig != null and rig.has_method("play_emote") and rig.emote_playing() != "dance":
		var body: CharacterBody3D = m.run.actors[slot] if slot < m.run.actors.size() else null
		if body == null or Vector2(body.velocity.x, body.velocity.z).length() < 0.5: rig.play_emote("dance") # it starts once the courier has come to a stop
	var frame: Control = fx.get("frame")
	if frame != null and is_instance_valid(frame): frame.call("refresh")

func end_fx(fx: Dictionary) -> void:
	var frame: Control = fx.get("frame")
	if frame != null and is_instance_valid(frame): frame.queue_free()
	fx.erase("frame")
	var tag: Node3D = fx.get("tag")
	if tag != null and is_instance_valid(tag): tag.queue_free()
	fx.erase("tag")
	if m == null: return
	var slot := int(fx.slot)
	if not _slots.has(slot): return
	var state: Dictionary = _slots[slot]
	state.count = int(state.count) - 1
	if int(state.count) > 0: return # a second shot started over the first: the look stays plain until the last one ends
	_slots.erase(slot)
	var rig: Node3D = m.rig(slot)
	if rig == null or not rig.has_method("set_look_over"): return
	rig.set_look_over(null)
	rig.stop_emote()
	_poof(rig.global_position + Vector3(0.0, 1.0, 0.0))

## The dancer wears the plain look: on first call and on a new rig (the slot's character was built again).
func _dress(slot: int) -> void:
	var state: Dictionary = _slots.get(slot, {})
	var rig: Node3D = m.rig(slot)
	if state.is_empty() or rig == null or not rig.has_method("set_look_over"): return
	if int(state.rig) == rig.get_instance_id(): return
	var first := int(state.rig) == 0
	state.rig = rig.get_instance_id()
	rig.set_look_over(_plain_look(int(m.seats[slot]) if slot < m.seats.size() else slot))
	if first: _poof(rig.global_position + Vector3(0.0, 1.0, 0.0))

## The base look, "the model restyled you": a bare bean head in the plain skin tone, none of the seat's animal, cap, hair or hand item, only the face's default features, the catalog's default
## skin, pants and shoes, no sliders; the seat's own shirt colour stays so the team still tells who it is.
static func _plain_look(seat: int) -> CharacterLook:
	var look := CharacterLook.new()
	var own := CharacterLook.defaults_for_seat(seat)
	var defaults: Dictionary = CharacterCatalog.data().get("color_defaults", {})
	for slot: String in CharacterCatalog.color_slots():
		look.colors[slot] = int(defaults.get(slot, 0))
	look.colors["shirt"] = int(own.colors.get("shirt", 0))
	for slot: String in CharacterCatalog.slots():
		look.items[slot] = CharacterCatalog.default_item(slot) if slot in ["eyes", "brows", "nose"] else ""
	var bean_there := not CharacterCatalog.item("head_bean").is_empty() and not CharacterCatalog.left_out().has("head_bean")
	look.items["head"] = "head_bean" if bean_there else CharacterCatalog.default_item("head")
	return look.fitted()

func mods(_fx: Dictionary) -> Dictionary:
	return {"freeze": true}

func camera(fx: Dictionary, camera: Dictionary) -> void:
	if m == null: return
	var age := float(fx.age)
	var swing := smoothstep(0.0, 1.0, minf(age / ZOOM_IN, (float(fx.dur) - age) / ZOOM_OUT))
	if swing <= 0.0: return
	var slot := int(fx.slot)
	var rig: Node3D = m.rig(slot)
	var forward := -rig.global_basis.z if rig != null else Vector3(0.0, 0.0, -1.0)
	camera["zoom"] = swing
	camera["point"] = m.feet(slot) + Vector3(0.0, FACE, 0.0)
	camera["range"] = RANGE
	camera["around"] = atan2(-forward.x, -forward.z)
	camera["rise"] = 0.1 # about eye level, like a phone held up
	camera["mask"] = SOLID_LAYER | MOVER_LAYER | CAMERA_BLOCKER # a wall, a spinning hub or a platform in front of the face stops the camera short
	camera["fov"] = float(camera.get("fov", 0.0)) - FOV_CUT * swing

# ------------------------------------------------------------------ the phone in the air

func begin_shot(shot: Dictionary) -> void:
	if m == null: return
	var root := Node3D.new()
	root.name = "Phone"
	var spin := Node3D.new()
	spin.name = "Spin"
	var body := MeshInstance3D.new()
	body.mesh = phone_mesh()
	spin.add_child(body)
	spin.scale = Vector3.ONE * 1.7
	root.add_child(spin)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.8
	halo.mesh = quad
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_texture = glow_texture()
	glow.albedo_color = Color(1.0, 0.55, 0.85, 0.75)
	glow.no_depth_test = false
	halo.material_override = glow
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var trail := _sparkles(60, 0.7, 0.22, Vector2(0.2, 1.1), Vector2(0.16, 0.34), PackedColorArray([Color("ff8fb8"), Color("8fd3ff"), Color("ffe08a"), Color("c9b2ff"), Color.WHITE]))
	trail.name = "Trail"
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.gravity = Vector3(0.0, -0.4, 0.0)
	root.add_child(trail)
	m.add_child(root)
	root.global_position = shot.p
	shot["node"] = root
	shot["spin"] = randf() * TAU

func update_shot(shot: Dictionary, dt: float) -> void:
	var root: Node3D = shot.get("node")
	if root == null or not is_instance_valid(root): return
	root.global_position = shot.p
	var v: Vector3 = shot.v
	if v.length() > 0.5:
		var up := Vector3.UP if absf(v.normalized().y) < 0.95 else Vector3.RIGHT
		root.look_at(root.global_position + v, up)
	shot.spin = float(shot.spin) + SPIN * dt
	var spin: Node3D = root.get_node("Spin")
	spin.rotation = Vector3(float(shot.spin), 0.0, 0.0)
	root.scale = Vector3.ONE * lerpf(0.3, 1.0, smoothstep(0.0, 0.14, float(shot.age)))

func end_shot(shot: Dictionary) -> void:
	var root: Node3D = shot.get("node")
	shot.erase("node")
	if m == null or root == null or not is_instance_valid(root): return
	var hit := Time.get_ticks_msec() - _hit_at < 500
	var at: Vector3 = shot.p
	root.get_node("Spin").queue_free()
	for child in root.get_children():
		if child is MeshInstance3D: child.queue_free()
	(root.get_node("Trail") as CPUParticles3D).emitting = false
	m.get_tree().create_timer(1.0).timeout.connect(root.queue_free)
	_confetti(at, 30 if hit else 64)
	if not hit: m.sfx(id, "pop", at, 0.0)

## A one-shot burst of confetti: small flat coloured pieces that tumble and fall.
func _confetti(at: Vector3, amount: int) -> void:
	var parts := CPUParticles3D.new()
	parts.amount = amount
	parts.lifetime = 1.1
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.local_coords = false
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = 0.15
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.initial_velocity_min = 2.5
	parts.initial_velocity_max = 6.5
	parts.gravity = Vector3(0.0, -9.0, 0.0)
	parts.damping_min = 1.2
	parts.damping_max = 2.4
	parts.angle_min = 0.0
	parts.angle_max = 360.0
	parts.angular_velocity_min = -540.0
	parts.angular_velocity_max = 540.0
	var piece := QuadMesh.new()
	piece.size = Vector2(0.17, 0.28)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	piece.material = material
	parts.mesh = piece
	parts.color_initial_ramp = _palette(PackedColorArray([Color("ff4f86"), Color("ffd447"), Color("5fd2ff"), Color("9b7bff"), Color("7be37b"), Color.WHITE]))
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	parts.color_ramp = fade
	m.add_child(parts)
	parts.global_position = at
	parts.emitting = true
	m.get_tree().create_timer(1.5).timeout.connect(parts.queue_free)

## The look swapping: a puff of pastel sparkles round the character.
func _poof(at: Vector3) -> void:
	if m == null: return
	var parts := _sparkles(30, 0.8, 0.45, Vector2(1.5, 4.0), Vector2(0.12, 0.26), PackedColorArray([Color("ff8fb8"), Color("8fd3ff"), Color("ffe08a"), Color("c9b2ff"), Color.WHITE]))
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.damping_min = 2.0
	parts.damping_max = 3.5
	parts.gravity = Vector3.ZERO
	m.add_child(parts)
	parts.global_position = at
	parts.emitting = true
	m.get_tree().create_timer(1.4).timeout.connect(parts.queue_free)

## Billboarded four-point stars that shrink and fade, in colours picked at random from `colors`.
func _sparkles(amount: int, lifetime: float, radius: float, speed: Vector2, size: Vector2, colors: PackedColorArray) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.amount = amount
	parts.lifetime = lifetime
	parts.local_coords = false
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = radius
	parts.initial_velocity_min = speed.x
	parts.initial_velocity_max = speed.y
	parts.scale_amount_min = size.x / 0.16
	parts.scale_amount_max = size.y / 0.16
	parts.angle_min = 0.0
	parts.angle_max = 360.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	parts.scale_amount_curve = shrink
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	parts.color_ramp = fade
	parts.color_initial_ramp = _palette(colors)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.16
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.albedo_texture = star_texture()
	quad.material = material
	parts.mesh = quad
	return parts

## A gradient of hard stops, one per colour: a random pick of the ramp is one of the colours.
static func _palette(colors: PackedColorArray) -> Gradient:
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for index in colors.size(): offsets.append(float(index) / float(colors.size()))
	ramp.offsets = offsets
	ramp.colors = colors
	return ramp

# ------------------------------------------------------------------ the tag over a dancer's head

## A billboard with a blinking REC dot and a red LIVE tag, drawn once by a small viewport.
func _tag() -> Node3D:
	var root := Node3D.new()
	root.name = "LiveTag"
	var port := SubViewport.new()
	port.size = Vector2i(256, 84)
	port.transparent_bg = true
	port.disable_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.add_child(TagFace.new())
	root.add_child(port)
	var sprite := Sprite3D.new()
	sprite.texture = port.get_texture()
	sprite.pixel_size = 0.0078
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.no_depth_test = true # the tag shows through walls: everybody must see who is filming
	root.add_child(sprite)
	return root

class TagFace extends Control:
	const ShowTheme := preload("res://client/show_theme.gd")
	const LIVE_RED := Color("ff2d55")
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(256, 84)
	func _process(_dt: float) -> void:
		queue_redraw()
	func _draw() -> void:
		ShowTheme.box(self, Rect2(6, 12, 130, 64), Color(ShowTheme.PILL.r, ShowTheme.PILL.g, ShowTheme.PILL.b, 0.92), Color(1, 1, 1, 0.5), 2.0)
		if fposmod(float(Time.get_ticks_msec()) / 1000.0, 0.9) < 0.55:
			draw_circle(Vector2(42, 44), 13.0, Color(1.0, 0.18, 0.25, 0.35))
			draw_circle(Vector2(42, 44), 10.0, Color(1.0, 0.16, 0.22))
		else:
			draw_circle(Vector2(42, 44), 9.0, Color(0.45, 0.1, 0.13))
		ShowTheme.text(self, "REC", Vector2(62, 44), 30.0, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, 0.0, 1.0, HORIZONTAL_ALIGNMENT_LEFT)
		ShowTheme.box(self, Rect2(124, 12, 126, 64), LIVE_RED, Color.WHITE, 2.5)
		ShowTheme.text(self, "LIVE", Vector2(187, 44), 38.0, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT)

# ------------------------------------------------------------------ pictures drawn once

## The phone's screen: a pastel gradient with soft bands, a white disc with a pink play triangle and a progress bar at the foot.
static func screen_texture() -> Texture2D:
	if _screen != null: return _screen
	var w := 144
	var h := 256
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var stops := [Color("ff9ec9"), Color("b9a2ff"), Color("8be4ff")]
	var corners := [Vector2(-11.0, -17.0), Vector2(-11.0, 17.0), Vector2(19.0, 0.0)]
	for y in h:
		for x in w:
			var gx := float(x) / float(w - 1)
			var gy := float(y) / float(h - 1)
			var k := clampf(gx * 0.45 + gy * 0.8 - 0.08, 0.0, 1.0)
			var color: Color = (stops[0] as Color).lerp(stops[1], k * 2.0) if k < 0.5 else (stops[1] as Color).lerp(stops[2], (k - 0.5) * 2.0)
			color = color.lerp(Color("ffd9a8"), clampf(1.0 - Vector2(gx, gy).distance_to(Vector2(0.1, 0.05)) * 2.2, 0.0, 0.45)) # a warm corner
			color = color.lightened(0.05 * sin(k * 20.0)) # soft bands
			var p := Vector2(float(x) - float(w) * 0.5, float(y) - float(h) * 0.46)
			var disc := smoothstep(1.5, -1.5, p.length() - 36.0)
			color = color.lerp(Color(1, 1, 1), disc * 0.92)
			var inside := -INF
			for index in 3:
				var edge: Vector2 = (corners[(index + 1) % 3] as Vector2) - (corners[index] as Vector2)
				var normal := Vector2(edge.y, -edge.x).normalized()
				inside = maxf(inside, (p - (corners[index] as Vector2)).dot(normal))
			color = color.lerp(Color("ff4f86"), smoothstep(1.0, -1.0, inside) * disc)
			var bar := smoothstep(0.5, -0.5, absf(float(y) - float(h) * 0.93) - 2.0)
			var track := Color(1, 1, 1, 0.55)
			if bar > 0.0 and x > 14 and x < w - 14: color = color.lerp(Color(1, 1, 1) if x < 14 + int(float(w - 28) * 0.38) else track, bar * (1.0 if x < 14 + int(float(w - 28) * 0.38) else 0.55))
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	_screen = ImageTexture.create_from_image(image)
	return _screen

## A four-point star, white, soft at the tips.
static func star_texture() -> Texture2D:
	if _star != null: return _star
	var size := 48
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(float(x) + 0.5, float(y) + 0.5) - Vector2(size, size) * 0.5) / (float(size) * 0.5)
			var cross := exp(-absf(p.x) * 14.0) * exp(-absf(p.y) * 2.6) + exp(-absf(p.y) * 14.0) * exp(-absf(p.x) * 2.6)
			var core := exp(-p.length() * 7.0)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(cross + core * 0.8, 0.0, 1.0)))
	image.generate_mipmaps()
	_star = ImageTexture.create_from_image(image)
	return _star

## A round soft glow, white to transparent.
static func glow_texture() -> Texture2D:
	if _glow != null: return _glow
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 96
	texture.height = 96
	_glow = texture
	return _glow

# ------------------------------------------------------------------ the phone's mesh

## A rounded 9:16 slab: a pastel-edged body, a bezel, the glowing screen on the front and a pastel back with a lens ring.
static func phone_mesh() -> ArrayMesh:
	if _phone != null: return _phone
	var depth := 0.07
	var body := _rounded(PHONE.x, PHONE.y, 0.08)
	var screen_size := Vector2(PHONE.y * 0.9 * 9.0 / 16.0, PHONE.y * 0.9)
	var screen := _rounded(screen_size.x, screen_size.y, 0.055)
	var back := _rounded(PHONE.x * 0.86, PHONE.y * 0.88, 0.06)
	var mesh := ArrayMesh.new()
	var tool := SurfaceTool.new()
	# 0: the body: the sides, the bezel front, the back
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := body.size()
	for index in count:
		var a := body[index]
		var b := body[(index + 1) % count]
		var before := body[(index + count - 1) % count]
		var after := body[(index + 2) % count]
		var na := _outward(before, a, b)
		var nb := _outward(a, b, after)
		tool.set_normal(Vector3(na.x, na.y, 0.0)); tool.add_vertex(Vector3(a.x, a.y, depth * 0.5))
		tool.set_normal(Vector3(nb.x, nb.y, 0.0)); tool.add_vertex(Vector3(b.x, b.y, depth * 0.5))
		tool.set_normal(Vector3(nb.x, nb.y, 0.0)); tool.add_vertex(Vector3(b.x, b.y, -depth * 0.5))
		tool.set_normal(Vector3(na.x, na.y, 0.0)); tool.add_vertex(Vector3(a.x, a.y, depth * 0.5))
		tool.set_normal(Vector3(nb.x, nb.y, 0.0)); tool.add_vertex(Vector3(b.x, b.y, -depth * 0.5))
		tool.set_normal(Vector3(na.x, na.y, 0.0)); tool.add_vertex(Vector3(a.x, a.y, -depth * 0.5))
	_cap(tool, body, depth * 0.5, 1.0)
	_cap(tool, body, -depth * 0.5, -1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd2e6")
	material.roughness = 0.4
	material.metallic = 0.15
	material.emission_enabled = true
	material.emission = Color("ff9ec9")
	material.emission_energy_multiplier = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(material)
	tool.commit(mesh)
	# 1: the screen
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(tool, screen, depth * 0.5 + 0.004, 1.0, screen_size)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_texture = screen_texture()
	lit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	lit.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(lit)
	tool.commit(mesh)
	# 2: the back
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cap(tool, back, -depth * 0.5 - 0.004, -1.0)
	var panel := StandardMaterial3D.new()
	panel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.albedo_color = Color("c9b2ff")
	panel.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(panel)
	tool.commit(mesh)
	# 3: the lens ring on the back
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lens := _rounded(0.11, 0.11, 0.05)
	for index in lens.size(): lens[index] += Vector2(-0.1, 0.24)
	_cap(tool, lens, -depth * 0.5 - 0.008, -1.0)
	var ring := StandardMaterial3D.new()
	ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.albedo_color = Color("2a2350")
	ring.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(ring)
	tool.commit(mesh)
	_phone = mesh
	return _phone

## The outline of a rounded rectangle, counter-clockwise from the top right corner, centred on the origin.
static func _rounded(wide: float, high: float, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corners := [Vector2(wide * 0.5 - radius, high * 0.5 - radius), Vector2(-wide * 0.5 + radius, high * 0.5 - radius), Vector2(-wide * 0.5 + radius, -high * 0.5 + radius), Vector2(wide * 0.5 - radius, -high * 0.5 + radius)]
	for corner in 4:
		for step in 7:
			var a := (float(corner) + float(step) / 6.0) * PI * 0.5
			points.append((corners[corner] as Vector2) + Vector2(cos(a), sin(a)) * radius)
	return points

## The outward unit normal of the outline at `b`, from the edges `a`-`b` and `b`-`c`.
static func _outward(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var first := (b - a).normalized()
	var second := (c - b).normalized()
	return (Vector2(first.y, -first.x) + Vector2(second.y, -second.x)).normalized()

## A flat fan over an outline at height `z` facing `facing` (+1 front, -1 back); uvs span `box` (the screen's size) when given.
static func _cap(tool: SurfaceTool, outline: PackedVector2Array, z: float, facing: float, box := Vector2.ZERO) -> void:
	var count := outline.size()
	var normal := Vector3(0.0, 0.0, facing)
	for index in count:
		var a := outline[index]
		var b := outline[(index + 1) % count]
		for point: Vector2 in [Vector2.ZERO, b if facing > 0.0 else a, a if facing > 0.0 else b]:
			tool.set_normal(normal)
			if box != Vector2.ZERO: tool.set_uv(Vector2(point.x / box.x + 0.5, 0.5 - point.y / box.y))
			tool.add_vertex(Vector3(point.x, point.y, z))
