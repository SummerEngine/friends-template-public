extends "res://modes/show/items_ui/item_look.gd"
## FLIP on a client: the victim's steering is flipped by its own machine (`mods` invert), the camera does one quick barrel roll (a full turn) when it hits, and a pill at the bottom says
## CONTROLS FLIPPED with the seconds left, the item's icon at its left end and a red outline. Reference look for the other items (docs/items.md "Writing an item").
const Kit := preload("res://style/show_hud_kit.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const ROLL_TIME := 0.7 ## s of the barrel roll at the start

class Pill extends Control:
	var fx: Dictionary = {}
	var icon: Callable ## draw_icon of the look
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
		var top := view.y - 140.0 * k # over the controls hint of a round's first seconds
		# the pill's outline wears red: the effect is against you
		var rect := Kit.icon_pill(self, "CONTROLS FLIPPED  %d" % ceili(left), right, top, k * pop, alpha, 1.0, 300.0 * k, ShowTheme.RED)
		icon.call(self, Kit.icon_centre(rect), Kit.icon_radius(rect), alpha)

func banner_kind() -> String:
	return "alert"

## A U-turn arrow: up, round and back down. It says "the other way" with no words.
func draw_icon(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	var col := Color(0.94, 0.97, 1.0, a)
	var w := r * 0.24
	var half := r * 0.36 ## the bend's radius, also half the gap between the legs
	var bend := c + Vector2(0.0, -r * 0.18)
	var foot := c + Vector2(-half, r * 0.62)
	ci.draw_line(foot, Vector2(foot.x, bend.y), col, w, true)
	ci.draw_arc(bend, half, PI, TAU, 20, col, w, true)
	var tip_x := c.x + half
	ci.draw_line(Vector2(tip_x, bend.y), Vector2(tip_x, c.y + r * 0.2), col, w, true)
	ci.draw_circle(foot, w * 0.5, col)
	var wing := r * 0.5 # the head: a triangle pointing down
	ci.draw_colored_polygon(PackedVector2Array([Vector2(tip_x, c.y + r * 0.72), Vector2(tip_x - wing, c.y + r * 0.14), Vector2(tip_x + wing, c.y + r * 0.14)]), col)

func begin_fx(fx: Dictionary) -> void:
	if not bool(fx.mine) or m == null: return
	var pill := Pill.new()
	pill.name = "FlipPill"
	pill.fx = fx
	pill.icon = draw_icon
	m.over_layer.add_child(pill)
	fx["node"] = pill

func update_fx(fx: Dictionary, _dt: float) -> void:
	var pill: Control = fx.get("node")
	if pill != null: pill.queue_redraw()

func end_fx(fx: Dictionary) -> void:
	var pill: Control = fx.get("node")
	if pill != null and is_instance_valid(pill): pill.queue_free()
	fx.erase("node")

func mods(_fx: Dictionary) -> Dictionary:
	return {"invert": true}

func camera(fx: Dictionary, camera: Dictionary) -> void:
	var t := float(fx.age) / ROLL_TIME
	if t < 1.0: camera["roll"] = float(camera.get("roll", 0.0)) + TAU * ease(t, -2.2) * (1.0 if int(fx.id) % 2 == 0 else -1.0)
