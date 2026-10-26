extends "res://modes/show/items_ui/item_look.gd"
## GLITCH on a client (the "hallucinating model"): two effects for the victim's whole time.
##  1. The lag: `mods` returns {"lag": period}, so the shell (game/game_run.gd rig_lag) draws the victim's rig once per period on EVERY client: jerk, hold, jerk. The camera follows the courier
##     itself, so it keeps turning smoothly while the character on the screen only moves every half second: the player cannot see where the character steps, the others see it stutter.
##  2. The wobble (the victim's own screen only): a full-rect ColorRect with glitch_wobble.gdshader in `m.post_layer` (under the HUD and the touch buttons) is a trip (big slow swells, split colour channels, a drifting hue, double vision); the camera sways
##     (roll +-10 degrees at 0.3 Hz, the lens breathes +-9 degrees) and a small PING 999 pill flickers at the bottom. All of it eases in over 0.5 s, holds, and goes out over 0.5 s, scaled by `sway` (`fx.b`).
## `fx.a` is the period (s), `fx.b` the sway.
const Kit := preload("res://style/show_hud_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const WobbleShader := preload("res://modes/show/items_ui/glitch_wobble.gdshader")

const RAMP_IN := 0.5 ## s the effect takes to come in
const RAMP_OUT := 0.5 ## s it takes to go out ...
const LEAD_OUT := 0.12 ## ... finished this long before the time is up (a client's clock runs a little behind the authority's: it never ends in the middle of the ramp)
const ROLL_DEGREES := 10.0 ## the camera sways +-10 degrees ...
const ROLL_HZ := 0.3 ## ... slowly (a swing every 3.3 s)
const FOV_DEGREES := 9.0 ## the lens breathes +-9 degrees
const FOV_HZ := 0.45

## 0..1: the ramp of an effect `age` s old of `dur` s (smooth in, smooth out).
static func envelope(age: float, dur: float) -> float:
	var rise := clampf(age / RAMP_IN, 0.0, 1.0)
	var fall := clampf((dur - LEAD_OUT - age) / RAMP_OUT, 0.0, 1.0)
	return smoothstep(0.0, 1.0, rise) * smoothstep(0.0, 1.0, fall)

## The PING pill at the bottom: the lag's tag, flickering like a bad connection.
class Tag extends Control:
	var fx: Dictionary = {}
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		if fx.is_empty(): return
		var view := get_viewport_rect().size
		var k := Kit.k(self)
		var age := float(fx.age)
		var pop := ShowTheme.pop_scale(age, 0.35, 0.3)
		var cell := int(age * 12.0)
		var dim := fposmod(sin(float(cell) * 12.9898) * 43758.5453, 1.0) < 0.2
		var alpha := (0.38 if dim else 1.0) * clampf((float(fx.dur) - age) / 0.3, 0.0, 1.0)
		var right := view.x * 0.5 + 150.0 * k * pop
		var top := view.y - (140.0 + (54.0 if get_parent().has_node("FlipPill") else 0.0)) * k # over the controls hint; above the FLIP pill when both are up
		var rect := Kit.icon_pill(self, "PING 999", right, top, k * pop, alpha, 1.0, 300.0 * k, ShowTheme.RED) # a red outline: signal bars, one lit
		var at := Kit.icon_centre(rect)
		var r := Kit.icon_radius(rect) * 1.1
		for bar in 4:
			var h := r * (0.3 + 0.2 * bar)
			var left := at.x - r * 0.5 + bar * r * 0.27
			var col := Color(0.94, 0.97, 1.0, alpha) if bar == 0 else Color(1.0, 1.0, 1.0, 0.22 * alpha)
			draw_rect(Rect2(left, at.y + r * 0.42 - h, r * 0.17, h), col)

func banner_kind() -> String:
	return "alert"

func rehearsal() -> Dictionary:
	var catalog := preload("res://modes/show/items/catalog.gd")
	return {"dur": catalog.tuning(id, "duration"), "a": catalog.tuning(id, "period"), "b": catalog.tuning(id, "sway")}

## A wave that tears: the right part of the line jumps up and sideways, with a red and a cyan ghost behind it.
func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var tear := 0.1 * r ## x of the tear, from the centre
	var white := Color(0.94, 0.97, 1.0, a)
	var ghosts := [[Color(1.0, 0.32, 0.4, 0.85 * a), Vector2(r * 0.1, r * 0.06)], [Color(0.3, 0.92, 1.0, 0.85 * a), Vector2(-r * 0.1, -r * 0.06)]]
	var width := r * 0.17
	for ghost: Array in ghosts:
		_wave(ci, c + (ghost[1] as Vector2), r, tear, ghost[0] as Color, width * 0.85)
	_wave(ci, c, r, tear, white, width)
	var block := r * 0.14 # a few pixels that came loose at the tear
	ci.draw_rect(Rect2(c + Vector2(tear - block * 2.4, -r * 0.62), Vector2(block, block)), Color(0.3, 0.92, 1.0, a))
	ci.draw_rect(Rect2(c + Vector2(tear + block * 0.6, r * 0.5), Vector2(block * 1.4, block * 0.8)), Color(1.0, 0.32, 0.4, a))
	ci.draw_rect(Rect2(c + Vector2(tear + block * 2.4, -r * 0.5), Vector2(block * 0.8, block * 0.8)), white)

## Two strokes of one sine wave: left of `tear` as it is, right of it moved up and out.
func _wave(ci: CanvasItem, c: Vector2, r: float, tear: float, color: Color, width: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var span := r * 0.8
	var steps := 28
	for i in steps + 1:
		var x := lerpf(-span, span, float(i) / float(steps))
		var y := sin(x / span * PI * 1.5) * r * 0.34
		if x <= tear: left.append(c + Vector2(x, y))
		else: right.append(c + Vector2(x + r * 0.1, y - r * 0.32))
	if left.size() >= 2: ci.draw_polyline(left, color, width, true)
	if right.size() >= 2: ci.draw_polyline(right, color, width, true)
	if left.size() >= 1: ci.draw_circle(left[0], width * 0.5, color)
	if right.size() >= 1: ci.draw_circle(right[right.size() - 1], width * 0.5, color)

func begin_fx(fx: Dictionary) -> void:
	if not bool(fx.mine) or m == null: return
	var rect := ColorRect.new()
	rect.name = "GlitchWobble"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = WobbleShader
	material.set_shader_parameter("amount", 0.0)
	material.set_shader_parameter("clock", 0.0)
	rect.material = material
	rect.visible = false # nothing to copy until the wobble comes in
	m.post_layer.add_child(rect)
	var tag := Tag.new()
	tag.name = "GlitchPing"
	tag.fx = fx
	m.over_layer.add_child(tag)
	fx["nodes"] = [rect, tag]

func update_fx(fx: Dictionary, _dt: float) -> void:
	var nodes: Array = fx.get("nodes", [])
	if nodes.is_empty(): return
	var rect: ColorRect = nodes[0]
	var amount := envelope(float(fx.age), float(fx.dur)) * float(fx.b)
	rect.visible = amount > 0.0005
	(rect.material as ShaderMaterial).set_shader_parameter("amount", amount)
	(rect.material as ShaderMaterial).set_shader_parameter("clock", float(fx.age))
	(nodes[1] as Control).queue_redraw()

func end_fx(fx: Dictionary) -> void:
	for node: Node in fx.get("nodes", []):
		if node != null and is_instance_valid(node): node.queue_free()
	fx.erase("nodes")

## Every client draws the victim's rig once per period (game_run.gd rig_lag).
func mods(fx: Dictionary) -> Dictionary:
	return {"lag": maxf(float(fx.a), 0.05)}

## The victim's camera: a slow roll and the lens breathing, both eased in and out.
func camera(fx: Dictionary, camera: Dictionary) -> void:
	var k := envelope(float(fx.age), float(fx.dur)) * float(fx.b)
	var age := float(fx.age)
	camera["roll"] = float(camera.get("roll", 0.0)) + deg_to_rad(ROLL_DEGREES) * k * sin(age * TAU * ROLL_HZ)
	camera["fov"] = float(camera.get("fov", 0.0)) + FOV_DEGREES * k * sin(age * TAU * FOV_HZ + 1.1)
