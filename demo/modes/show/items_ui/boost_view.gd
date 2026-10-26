extends "res://modes/show/items_ui/item_look.gd"
## BOOST on a client (the "new subscriber" event): the runner glows gold on every machine (a light, a soft additive aura shell, a pulsing ring on the floor, gold sparks, and a burst of "$" at
## the start), runs `a` times as fast and flings what it runs into (`b`, game/game_run.gd item_power); its owner also gets the boon banner and thin gold speed lines at the screen's edges.
const Sparkle := preload("res://modes/show/items_ui/soar_sparkle.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const COINS := 14 ## "$" thrown up at the start
const COIN_LIFE := 1.15 ## s
const GOLD := Color(1.0, 0.8, 0.28)

const AURA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.76, 0.22, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	float band = 0.5 + 0.5 * sin(UV.y * 22.0 - TIME * 8.0);
	ALBEDO = tint.rgb * (0.4 + rim * 1.6) * mix(1.0, band, 0.3);
	ALPHA = clamp((0.2 + rim * 0.9) * strength, 0.0, 1.0);
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.76, 0.22, 1.0);
uniform float strength = 1.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float t = fract(TIME * 1.3);
	float wave = exp(-pow((r - (0.2 + 0.75 * t)) * 11.0, 2.0)) * (1.0 - t);
	float base = exp(-pow((r - 0.32) * 13.0, 2.0)) * 0.55;
	ALBEDO = tint.rgb * 1.3;
	ALPHA = clamp((wave + base) * strength, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r));
}
"""

## Thin gold streaks that run outwards from the screen's edges (not the middle: the runner stays clear).
const LINES_SHADER := """
shader_type canvas_item;
uniform float amount = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.45, 1.0);
void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * vec2(res.x / res.y, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float n = 150.0;
	float id = floor(a * n);
	float f = fract(a * n);
	float h = fract(sin(id * 12.9898) * 43758.5453);
	float h2 = fract(sin(id * 78.233) * 12345.6789);
	float w = mix(0.04, 0.2, h2);
	float line = smoothstep(0.5 - w, 0.5 - w * 0.25, f) - smoothstep(0.5 + w * 0.25, 0.5 + w, f);
	float t = fract(r * 0.8 - TIME * (1.2 + 1.5 * h) + h * 7.0);
	float run = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.06, 0.4, t));
	float edge = smoothstep(0.5, 0.95, r);
	float on = step(0.4, h2);
	COLOR = vec4(tint.rgb, line * run * edge * on * amount * 0.8);
}
"""

static var _shaders := {} ## shader source -> Shader (one compile per look)

static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_shaders[code] = shader
	return _shaders[code]

func banner_kind() -> String:
	return "boon"

func rehearsal() -> Dictionary:
	var catalog := preload("res://modes/show/items/catalog.gd")
	return {"dur": catalog.tuning(id, "duration"), "a": catalog.tuning(id, "speed"), "b": catalog.tuning(id, "shove")}

func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var gold := Color(1.0, 0.82, 0.25, a)
	ci.draw_circle(c, r * 0.8, Color(0.55, 0.35, 0.05, a))
	ci.draw_circle(c, r * 0.72, gold)
	ci.draw_arc(c, r * 0.54, 0.0, TAU, 32, Color(1.0, 0.95, 0.7, a), r * 0.1, true)
	var bolt := PackedVector2Array([c + Vector2(r * 0.12, -r * 0.46), c + Vector2(-r * 0.28, r * 0.06), c + Vector2(-r * 0.02, r * 0.06), c + Vector2(-r * 0.14, r * 0.46), c + Vector2(r * 0.3, -r * 0.1), c + Vector2(r * 0.04, -r * 0.1)])
	ci.draw_colored_polygon(bolt, Color(0.42, 0.25, 0.02, a))

func begin_fx(fx: Dictionary) -> void:
	if m == null: return
	if bool(fx.mine):
		var lines := ColorRect.new()
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.set_anchors_preset(Control.PRESET_FULL_RECT)
		var material := ShaderMaterial.new()
		material.shader = _shader(LINES_SHADER)
		material.set_shader_parameter("amount", 0.0)
		lines.material = material
		m.over_layer.add_child(lines)
		fx["lines"] = lines
	_dress(fx)
	_throw_coins(fx)

## The glow on the runner's rig (retried each frame until the rig exists).
func _dress(fx: Dictionary) -> void:
	var rig: Node3D = m.rig(int(fx.slot))
	if rig == null: return
	var root := Node3D.new()
	root.name = "BoostGlow"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 2.2
	light.omni_range = 4.5
	light.position.y = 1.1
	root.add_child(light)
	var aura := MeshInstance3D.new()
	aura.name = "Aura"
	var shell := CapsuleMesh.new()
	shell.radius = 0.56
	shell.height = 2.05
	shell.radial_segments = 24
	shell.rings = 8
	aura.mesh = shell
	var aura_material := ShaderMaterial.new()
	aura_material.shader = _shader(AURA_SHADER)
	aura.material_override = aura_material
	aura.position.y = 0.95
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(aura)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var plane := QuadMesh.new()
	plane.size = Vector2(3.8, 3.8)
	ring.mesh = plane
	var ring_material := ShaderMaterial.new()
	ring_material.shader = _shader(RING_SHADER)
	ring.material_override = ring_material
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var sparks := Sparkle.emitter(56, 0.9, 0.5, Vector2(0.4, 1.5), Vector2(0.2, 0.42), PackedColorArray([Color(1.0, 0.95, 0.7, 0.0), Color(1.0, 0.82, 0.3, 1.0), Color(1.0, 0.6, 0.15, 0.0)]), 1.2)
	sparks.name = "Sparks"
	sparks.position.y = 0.9
	root.add_child(sparks)
	rig.add_child(root)
	fx["node"] = root

## The "$" signs: thrown up from the runner at the start, they tumble down and fade.
func _throw_coins(fx: Dictionary) -> void:
	var rig: Node3D = m.rig(int(fx.slot))
	var base: Vector3 = rig.global_position if rig != null else m.feet(int(fx.slot))
	var from := base + Vector3(0.0, 1.3, 0.0)
	var holder := Node3D.new()
	holder.name = "BoostCoins"
	holder.top_level = true
	m.add_child(holder)
	holder.global_position = Vector3.ZERO
	var pieces: Array = []
	for index in COINS:
		var mark := Label3D.new()
		mark.text = "$"
		mark.font = ShowTheme.font()
		mark.font_size = 96
		mark.pixel_size = 0.0068
		mark.outline_size = 22
		mark.outline_modulate = Color(0.45, 0.24, 0.02)
		mark.modulate = Color(1.0, 0.86, 0.32)
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.shaded = false
		mark.double_sided = true
		mark.no_depth_test = false
		mark.render_priority = 6
		holder.add_child(mark)
		var angle := TAU * (float(index) + randf() * 0.6) / float(COINS)
		var out := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.8, 2.6)
		mark.global_position = from + Vector3(0.0, randf() * 0.4, 0.0)
		pieces.append({"node": mark, "v": out + Vector3(0.0, randf_range(3.6, 6.4), 0.0), "delay": randf() * 0.12, "turn": randf_range(-4.0, 4.0)})
	fx["coins"] = {"holder": holder, "pieces": pieces, "t": 0.0, "last": base}

func update_fx(fx: Dictionary, dt: float) -> void:
	if m == null: return
	var age := float(fx.age)
	var left := maxf(float(fx.dur) - age, 0.0)
	var fade := clampf(minf(age / 0.25, left / 0.5), 0.0, 1.0) # the glow comes in quickly and goes out over the last half second
	var root: Node3D = fx.get("node")
	if root == null or not is_instance_valid(root):
		if int(fx.slot) >= 0: _dress(fx)
		root = fx.get("node")
	if root != null:
		(root.get_node("Light") as OmniLight3D).light_energy = (2.2 + 4.5 * exp(-age * 5.0)) * fade
		var pulse := 1.0 + 0.08 * sin(age * 11.0)
		var aura := root.get_node("Aura") as MeshInstance3D
		aura.scale = Vector3.ONE * pulse
		(aura.material_override as ShaderMaterial).set_shader_parameter("strength", fade * (0.85 + 0.15 * sin(age * 9.0)))
		(root.get_node("Ring").material_override as ShaderMaterial).set_shader_parameter("strength", fade)
		(root.get_node("Sparks") as CPUParticles3D).emitting = left > 0.3
	var lines: ColorRect = fx.get("lines")
	if lines != null: (lines.material as ShaderMaterial).set_shader_parameter("amount", fade * (0.9 + 0.1 * sin(age * 17.0)))
	var coins: Dictionary = fx.get("coins", {})
	if not coins.is_empty():
		coins.t = float(coins.t) + dt
		var t: float = coins.t
		var rig: Node3D = m.rig(int(fx.slot))
		var moved := Vector3.ZERO # the runner is off at speed: the first of the burst goes along with it, then it hangs in the air
		if rig != null:
			moved = rig.global_position - (coins.last as Vector3)
			coins.last = rig.global_position
		for piece: Dictionary in coins.pieces:
			var mark: Label3D = piece.node
			var life := t - float(piece.delay)
			if life < 0.0:
				mark.visible = false
				continue
			mark.visible = true
			piece.v = (piece.v as Vector3) + Vector3(0.0, -11.0, 0.0) * dt
			mark.global_position += (piece.v as Vector3) * dt + moved * clampf(1.0 - life / 0.6, 0.0, 1.0)
			mark.rotation.z = float(piece.turn) * life
			mark.scale = Vector3.ONE * (ShowTheme.pop_scale(life, 0.18, 0.2) * clampf((COIN_LIFE - life) / 0.3, 0.0, 1.0))
		if t > COIN_LIFE + 0.2:
			(coins.holder as Node).queue_free()
			fx.erase("coins")

func end_fx(fx: Dictionary) -> void:
	for key: String in ["node", "lines"]:
		var node: Node = fx.get(key)
		if node != null and is_instance_valid(node): node.queue_free()
		fx.erase(key)
	var coins: Dictionary = fx.get("coins", {})
	if not coins.is_empty() and is_instance_valid(coins.holder): (coins.holder as Node).queue_free()
	fx.erase("coins")

func mods(fx: Dictionary) -> Dictionary:
	return {"speed": float(fx.a), "power": float(fx.b)}

func camera(fx: Dictionary, camera: Dictionary) -> void:
	camera["fov"] = float(camera.get("fov", 0.0)) + 7.0 * clampf(minf(float(fx.age) / 0.25, (float(fx.dur) - float(fx.age)) / 0.4), 0.0, 1.0) # the lens opens with the speed
