extends "res://modes/show/items_ui/item_look.gd"
## SOAR on a client ("the video went viral"): the owner's machine jumps `a` times as fast and has `b` jumps more in the air (`mods`); everybody sees a cyan-and-pink braided
## ribbon trailing the runner, sparkles, and a small VIEWS pill over its head that climbs 10K, 100K, 1M. The owner also gets the show-style views counter at the screen's right edge (a bump at each
## tier) and the lens opening on every jump. The counter reads the effect's age only: 10K at the start, 100K at 40 % of the time, 1M after 80 %, held to the end.
const Kit := preload("res://style/show_hud_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const Sparkle := preload("res://modes/show/items_ui/soar_sparkle.gd")
const NameTags := preload("res://client/name_tags.gd")

const LOW := 10000.0
const HIGH := 1000000.0
const REACH := 0.8 ## the share of the time the count takes to reach 1M (it holds 1M to the end)
const CYAN := Color(0.3, 0.92, 1.0)
const PINK := Color(1.0, 0.36, 0.76)
const TRAIL_LIFE := 0.7 ## s a point of the ribbon lives
const TRAIL_WIDTH := 0.1 ## m, half the width at the head
const PILL_HEIGHT := 2.75 ## m over the feet
const PILL_FONT := 72 ## px of the pill's words (x PILL_PIXEL m)
const PILL_PIXEL := 0.0027

## The VIEWS pill's plate: a camera-facing rounded plate in the show's pill colours with a gold badge at its end (a dot in the count's colour), drawn over the world.
const PLATE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec2 half_size = vec2(0.5, 0.08);
uniform vec4 tone : source_color = vec4(0.3, 0.92, 1.0, 1.0);
void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = (UV - 0.5) * half_size * 2.0;
	float r = half_size.y;
	vec2 q = abs(p) - (half_size - vec2(r));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	float aa = max(fwidth(d), 0.0001);
	float body = 1.0 - smoothstep(-aa, aa, d);
	float inner = 1.0 - smoothstep(-aa, aa, d + r * 0.08);
	vec3 col = mix(vec3(1.0), vec3(0.075, 0.082, 0.105), inner);
	float alpha = mix(0.6, 0.95, inner);
	float db = length(p - vec2(half_size.x - r * 0.95, 0.0));
	float disc = 1.0 - smoothstep(r * 0.6 - aa, r * 0.6 + aa, db);
	float core = 1.0 - smoothstep(r * 0.46 - aa, r * 0.46 + aa, db);
	float dot_ = 1.0 - smoothstep(r * 0.27 - aa, r * 0.27 + aa, db);
	col = mix(col, vec3(0.95, 0.71, 0.2), disc);
	col = mix(col, vec3(0.012, 0.065, 0.255), core);
	col = mix(col, tone.rgb, dot_);
	alpha = mix(alpha, 1.0, disc);
	ALBEDO = col;
	ALPHA = alpha * body;
}
"""

static var _plate_shader: Shader

## The views at `age` of `dur` s: 10^4 growing to 10^6, an even climb in the exponent.
static func views(age: float, dur: float) -> float:
	return pow(10.0, lerpf(4.0, 6.0, clampf(age / maxf(dur * REACH, 0.01), 0.0, 1.0)))

## The tier the count is in: 0 under 100K, 1 under 1M, 2 at 1M.
static func tier_of(count: float) -> int:
	return 0 if count < 100000.0 else (1 if count < HIGH else 2)

## The second a tier begins at.
static func tier_at(tier: int, dur: float) -> float:
	return 0.0 if tier <= 0 else dur * REACH * (0.5 if tier == 1 else 1.0)

## "10K", "48K", "999K", "1M".
static func words(count: float) -> String:
	return "1M" if count >= HIGH * 0.9999 else "%dK" % int(count / 1000.0)

## The text of the counter of an effect now (the check reads it).
func counter_text(fx: Dictionary) -> String:
	return words(views(float(fx.age), float(fx.dur)))

## The colour of the count: cyan, pink, then gold at 1M.
static func tone(count: float) -> Color:
	if count >= HIGH * 0.9999: return ShowTheme.YELLOW
	var along := clampf((log(count) / log(10.0) - 4.0) / 2.0, 0.0, 1.0)
	return CYAN.lerp(Color(1.0, 0.55, 0.85), along)

# ------------------------------------------------------------------ the owner's counter

class Counter extends Control:
	var look
	var fx: Dictionary = {}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if fx.is_empty() or look == null: return
		var age := float(fx.age)
		var dur := float(fx.dur)
		var count: float = look.views(age, dur)
		var tier: int = look.tier_of(count)
		var since: float = age - look.tier_at(tier, dur)
		var bump := exp(-since * 6.5) * cos(since * 17.0) * (0.5 if tier == 0 else 1.0)
		var alpha := clampf(age / 0.12, 0.0, 1.0) * clampf((dur - age) / 0.35, 0.0, 1.0)
		if alpha <= 0.0: return
		var view := get_viewport_rect().size
		var k := Kit.k(self)
		var kk := k * ShowTheme.pop_scale(age, 0.45, 0.3) * (1.0 + 0.2 * bump)
		var h := 70.0 * kk
		var middle := view.y * 0.46
		var right := Kit.right_edge(self) + pow(1.0 - clampf(age / 0.3, 0.0, 1.0), 2.0) * 260.0 * k
		var words_now: String = look.words(count)
		var size := ShowTheme.size_for_cap(h * 0.5)
		var cell := ShowTheme.width("0", size)
		var area := cell * 4.0
		var label_size := h * 0.27
		var views_wide := ShowTheme.width("VIEWS", label_size) * (1.0 + ShowTheme.SLANT * 0.1)
		var gap := h * 0.16
		var wide := h * 0.35 + area + gap + views_wide + h * 0.1 + h
		var rect := Rect2(right - wide, middle - h * 0.5, wide, h)
		var tint: Color = look.tone(count)
		ShowTheme.pill(self, rect, ShowTheme.PILL, Color(tint, 0.75), maxf(h * 0.045, 1.5), alpha)
		var digits_right := rect.position.x + h * 0.35 + area
		var fill := tint.lerp(Color.WHITE, clampf(bump, 0.0, 1.0) * 0.8 + 0.25)
		Kit.digits(self, words_now, Vector2(digits_right - cell * words_now.length() * 0.5, middle + h * 0.02), size, fill, Color(ShowTheme.NAVY, 0.95), alpha)
		ShowTheme.text(self, "VIEWS", Vector2(digits_right + gap, middle + h * 0.1), label_size, Color(1, 1, 1, 0.92), Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha, HORIZONTAL_ALIGNMENT_LEFT)
		# the climb to 1M under the pill: a thin bar, cyan to pink
		var bar := Rect2(rect.position.x + h * 0.3, rect.end.y - h * 0.14, (rect.size.x - h * 0.3) * 0.88, h * 0.05)
		draw_rect(bar, Color(1, 1, 1, 0.16 * alpha))
		var along: float = clampf(age / maxf(dur * look.REACH, 0.01), 0.0, 1.0)
		var done := Rect2(bar.position, Vector2(bar.size.x * along, bar.size.y))
		draw_rect(done, Color(tint, alpha))
		# the icon at the pill's end, no disc behind it
		var icon := Vector2(rect.end.x - h * 0.55, middle)
		look.draw_icon(self, icon, h * 0.4, alpha)
		if tier > 0 and since < 0.8: _sparks(icon, rect, since, k, alpha)

	## Stars thrown off the pill at a tier.
	func _sparks(icon: Vector2, rect: Rect2, since: float, k: float, alpha: float) -> void:
		var colors := [CYAN, PINK, Color.WHITE, ShowTheme.YELLOW]
		for index in 16:
			var angle := TAU * float(index) / 16.0 + 0.3 * float(index % 3)
			var reach := (80.0 + 90.0 * float((index * 7) % 5) / 4.0) * k
			var run := ease(clampf(since / 0.8, 0.0, 1.0), 0.35)
			var at := rect.get_center().lerp(icon, 0.4) + Vector2(cos(angle) * 1.3, sin(angle)) * reach * run
			var star := (1.0 - run) * 13.0 * k
			var fade := (1.0 - clampf(since / 0.8, 0.0, 1.0)) * alpha
			_star(at, star, Color(colors[index % 4], fade))

	func _star(at: Vector2, radius: float, color: Color) -> void:
		if radius < 0.5: return
		var points := PackedVector2Array()
		for index in 8:
			var reach := radius if index % 2 == 0 else radius * 0.28
			var angle := PI * 0.25 * float(index) - PI * 0.5
			points.append(at + Vector2(cos(angle), sin(angle)) * reach)
		draw_colored_polygon(points, color)

func banner_kind() -> String:
	return "boon"

func rehearsal() -> Dictionary:
	var catalog := preload("res://modes/show/items/catalog.gd")
	return {"dur": catalog.tuning(id, "duration"), "a": catalog.tuning(id, "jump"), "b": catalog.tuning(id, "air_jumps")}

## An up-arrow over three rising bars (cyan, white, pink), a spark top left.
func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var bars := [[-0.52, 0.36, CYAN], [0.0, 0.64, Color.WHITE], [0.52, 0.98, PINK]]
	var base := c.y + r * 0.72
	var wide := r * 0.34
	for bar: Array in bars:
		var high := float(bar[1]) * r
		ci.draw_rect(Rect2(c.x + float(bar[0]) * r - wide * 0.5, base - high, wide, high), Color(bar[2] as Color, a * 0.5))
	var from := c + Vector2(-0.62, 0.34) * r
	var to := c + Vector2(0.5, -0.64) * r
	var color := Color(1, 1, 1, a)
	ci.draw_line(from, to, color, r * 0.2, true)
	var along := (to - from).normalized()
	var side := Vector2(-along.y, along.x)
	ci.draw_colored_polygon(PackedVector2Array([to + along * r * 0.3, to - along * r * 0.12 + side * r * 0.42, to - along * r * 0.12 - side * r * 0.42]), color)
	var spark := c + Vector2(-0.58, -0.58) * r
	var points := PackedVector2Array()
	for index in 8:
		var reach := r * (0.26 if index % 2 == 0 else 0.08)
		var angle := PI * 0.25 * float(index) - PI * 0.5
		points.append(spark + Vector2(cos(angle), sin(angle)) * reach)
	ci.draw_colored_polygon(points, Color(1.0, 0.92, 0.45, a))

# ------------------------------------------------------------------ the effect

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	fx["tier"] = -1
	fx["open"] = 0.0
	if bool(fx.mine):
		var counter := Counter.new()
		counter.look = self
		counter.fx = fx
		m.over_layer.add_child(counter)
		fx["counter"] = counter
	_dress(fx)

func _dress(fx: Dictionary) -> void:
	var rig: Node3D = m.rig(int(fx.slot))
	if rig == null: return
	var root := Node3D.new()
	root.name = "SoarAura"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = CYAN
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.position.y = 1.0
	root.add_child(light)
	var sparks := Sparkle.emitter(44, 0.9, 0.55, Vector2(0.2, 0.9), Vector2(0.14, 0.3), PackedColorArray([Color(0.6, 0.97, 1.0, 0.0), Color(0.3, 0.92, 1.0, 1.0), Color(1.0, 0.4, 0.78, 0.8), Color(1.0, 0.4, 0.78, 0.0)]), 0.5)
	sparks.name = "Sparks"
	sparks.position.y = 0.9
	root.add_child(sparks)
	if not bool(fx.mine): # the others read a small pill over the runner's head; the owner has the big counter
		var pill := _pill("10K VIEWS", CYAN)
		pill.name = "Views"
		pill.position.y = PILL_HEIGHT
		root.add_child(pill)
		fx["pill_text"] = "10K VIEWS"
	rig.add_child(root)
	fx["node"] = root
	if not fx.has("trail"):
		var mesh := ImmediateMesh.new()
		var node := MeshInstance3D.new()
		node.name = "SoarRibbon"
		node.mesh = mesh
		node.top_level = true
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 60.0
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		node.material_override = material
		m.add_child(node)
		node.global_transform = Transform3D.IDENTITY
		fx["trail"] = {"node": node, "mesh": mesh, "points": [], "material": material}

func update_fx(fx: Dictionary, dt: float) -> void:
	if m == null: return
	var age := float(fx.age)
	var dur := float(fx.dur)
	var slot := int(fx.slot)
	var root: Node3D = fx.get("node")
	if root == null or not is_instance_valid(root):
		_dress(fx)
		root = fx.get("node")
	var fade := clampf(minf(age / 0.2, (dur - age) / 0.5), 0.0, 1.0)
	var count := views(age, dur)
	var tier := tier_of(count)
	if tier != int(fx.tier):
		fx.tier = tier
		_burst(fx, tier)
	if root != null:
		var light := root.get_node("Light") as OmniLight3D
		light.light_color = CYAN.lerp(PINK, 0.5 + 0.5 * sin(age * 5.0))
		light.light_energy = 1.4 * fade
		(root.get_node("Sparks") as CPUParticles3D).emitting = dur - age > 0.3
		var pill := root.get_node_or_null("Views") as Node3D
		if pill != null:
			var text := "%s VIEWS" % words(count)
			if text != str(fx.pill_text):
				fx.pill_text = text
				_pill_set(pill, text, tone(count))
			var camera := pill.get_viewport().get_camera_3d()
			var distance := camera.global_position.distance_to(pill.global_position) if camera != null else 6.0
			var pop := 1.0 + 0.3 * exp(-(age - tier_at(tier, dur)) * 7.0) * cos((age - tier_at(tier, dur)) * 17.0) * (0.5 if tier == 0 else 1.0)
			pill.scale = Vector3.ONE * clampf(distance / 5.0, 1.3, 3.4) * pop * ShowTheme.pop_scale(age, 0.4, 0.2) * clampf((dur - age) / 0.3, 0.0, 1.0)
			pill.position.y = PILL_HEIGHT + 0.32 * clampf(age / (dur * REACH), 0.0, 1.0) + 0.05 * sin(age * 4.0) # it climbs with the count
	var counter: Control = fx.get("counter")
	if counter != null: counter.queue_redraw()
	_ribbon(fx, fade)
	# the lens opens on a jump: wide while the runner climbs or falls fast (the vertical speed), back on the ground
	if bool(fx.mine) and m.run != null and slot >= 0 and slot < m.run.actors.size():
		var body: CharacterBody3D = m.run.actors[slot]
		var air := clampf(absf(body.velocity.y) / 11.0, 0.0, 1.0)
		fx.open = lerpf(float(fx.open), air, clampf(dt * (7.0 if air > float(fx.open) else 3.5), 0.0, 1.0))

## The pill over a bystander's head: the plate (a quad with PLATE_SHADER) and the words (a Label3D in the show's slanted Lilita One) on it.
func _pill(text: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	plate.mesh = QuadMesh.new()
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	if _plate_shader == null:
		_plate_shader = Shader.new()
		_plate_shader.code = PLATE_SHADER
	material.shader = _plate_shader
	material.render_priority = 4
	plate.material_override = material
	root.add_child(plate)
	var label := Label3D.new()
	label.name = "Words"
	label.font = NameTags.tag_font()
	label.font_size = PILL_FONT
	label.pixel_size = PILL_PIXEL
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.double_sided = true
	label.no_depth_test = true
	label.render_priority = 6
	label.outline_size = 0
	label.modulate = Color.WHITE
	root.add_child(label)
	_pill_set(root, text, color)
	return root

func _pill_set(root: Node3D, text: String, color: Color) -> void:
	var label := root.get_node("Words") as Label3D
	label.text = text
	var high := float(PILL_FONT) * 0.95
	var wide := NameTags.tag_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_FONT).x
	var badge := float(PILL_FONT) * 0.62
	var total := float(PILL_FONT) * 0.45 + wide + float(PILL_FONT) * 0.3 + badge + float(PILL_FONT) * 0.22
	label.offset = Vector2(-total * 0.5 + float(PILL_FONT) * 0.45 + wide * 0.5, 0.0) # the words sit left of the middle, the badge on the right end
	var plate := root.get_node("Plate") as MeshInstance3D
	(plate.mesh as QuadMesh).size = Vector2(total, high) * PILL_PIXEL
	var material := plate.material_override as ShaderMaterial
	material.set_shader_parameter("half_size", Vector2(total, high) * PILL_PIXEL * 0.5)
	material.set_shader_parameter("tone", color)

## The tier's burst of stars at the runner (the first one is the launch).
func _burst(fx: Dictionary, tier: int) -> void:
	var root: Node3D = fx.get("node")
	if root == null: return
	var parts := Sparkle.emitter(26 + tier * 14, 0.9, 0.3, Vector2(2.2, 5.0), Vector2(0.18, 0.4), PackedColorArray([Color(1, 1, 1, 0.0), Color(0.3, 0.92, 1.0, 1.0), Color(1.0, 0.4, 0.78, 0.9), Color(1.0, 0.85, 0.4, 0.0)]), -2.5)
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.position.y = 1.0
	root.add_child(parts)
	parts.emitting = true
	parts.finished.connect(parts.queue_free)

## The braided ribbon behind the runner, rebuilt each frame from where it has been: a cyan and a pink strand wind round each other, facing the camera, thinning and fading to the tail.
func _ribbon(fx: Dictionary, fade: float) -> void:
	var trail: Dictionary = fx.get("trail", {})
	if trail.is_empty(): return
	var rig: Node3D = m.rig(int(fx.slot))
	var now := float(Time.get_ticks_msec()) * 0.001
	var points: Array = trail.points
	if rig != null: points.append({"p": rig.global_position + Vector3(0.0, 0.95, 0.0), "t": now})
	while not points.is_empty() and now - float(points[0].t) > TRAIL_LIFE: points.pop_front()
	var mesh: ImmediateMesh = trail.mesh
	mesh.clear_surfaces()
	var camera: Camera3D = m.get_viewport().get_camera_3d()
	if points.size() < 3 or camera == null: return
	var eye := camera.global_position
	var count := points.size()
	for strand in 2:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for index in range(count - 1, -1, -1):
			var here: Vector3 = points[index].p
			var along := float(now - float(points[index].t)) / TRAIL_LIFE # 0 at the head, 1 at the tail
			var ahead: Vector3 = points[mini(index + 1, count - 1)].p
			var behind: Vector3 = points[maxi(index - 1, 0)].p
			var side := (ahead - behind).cross(eye - here)
			side = side.normalized() if side.length_squared() > 1e-8 else camera.global_basis.x
			var wind := sin(float(points[index].t) * 13.0 + float(strand) * PI) * 0.2 * (1.0 - along * 0.5)
			var centre := here + side * wind
			var half := TRAIL_WIDTH * pow(1.0 - along, 0.7)
			var head := Color(0.1, 0.86, 1.0) if strand == 0 else Color(1.0, 0.25, 0.66)
			var tail := Color(0.42, 0.3, 1.0) if strand == 0 else Color(1.0, 0.62, 0.25)
			var color := head.lerp(tail, along)
			color.a = pow(1.0 - along, 1.1) * 0.95 * fade
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(centre + side * half)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(centre - side * half)
		mesh.surface_end()

func end_fx(fx: Dictionary) -> void:
	for key: String in ["node", "counter"]:
		var node: Node = fx.get(key)
		if node != null and is_instance_valid(node): node.queue_free()
		fx.erase(key)
	var trail: Dictionary = fx.get("trail", {})
	if not trail.is_empty() and is_instance_valid(trail.node):
		var material: StandardMaterial3D = trail.material
		var tween: Tween = (trail.node as Node).create_tween() # the ribbon hangs in the air a moment and fades
		tween.tween_property(material, "albedo_color:a", 0.0, 0.4)
		tween.tween_callback((trail.node as Node).queue_free)
	fx.erase("trail")

func mods(fx: Dictionary) -> Dictionary:
	return {"jump": float(fx.a), "air_jumps": int(fx.b)}

func camera(fx: Dictionary, camera: Dictionary) -> void:
	var edge := clampf(minf(float(fx.age) / 0.2, (float(fx.dur) - float(fx.age)) / 0.4), 0.0, 1.0)
	camera["fov"] = float(camera.get("fov", 0.0)) + edge * (3.0 + 9.0 * float(fx.get("open", 0.0)))
