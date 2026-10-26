extends Control
## GHOST PIGEON (docs/pigeon.md): the two buttons of the local player's bird at the bottom of the screen, in the show's look: COO and DROP, each a dark pill with its glyph, its key and a bar that fills while
## the cooldown runs (the authority's numbers: state `pigeon.b`). On a phone the round buttons of the overlay say it (client/touch_controls.gd): only the bars are drawn there.
## model: {coo (s of cooldown left), coo_total, drop, drop_total, keys {coo, drop}, touch (bool), alpha}; an empty model draws nothing.
const ShowTheme := preload("res://client/show_theme.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const Icons := preload("res://modes/show/shared/pigeon/pigeon_icons.gd")

const READY := Color("86f0c6")
const WAIT := Color(1.0, 1.0, 1.0, 0.35)

var model := {}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func show_model(next: Dictionary) -> void:
	model = next
	visible = not next.is_empty()
	queue_redraw()

func _draw() -> void:
	if model.is_empty(): return
	var view := get_viewport_rect().size
	var k := Kit.k(self)
	var height := 52.0 * k
	var wide := 176.0 * k
	var middle := view.y - (150.0 if bool(model.get("touch", false)) else 118.0) * k
	var touching := bool(model.get("touch", false))
	var centres := [view.x * 0.5 - wide * 0.56, view.x * 0.5 + wide * 0.56]
	if touching: centres = [view.x * 0.5 - wide * 0.56, view.x * 0.5 + wide * 0.56]
	var keys: Dictionary = model.get("keys", {})
	for index in 2:
		var which := "coo" if index == 0 else "drop"
		var left := float(model.get(which, 0.0))
		var total := maxf(float(model.get(which + "_total", 1.0)), 0.01)
		var ready := left <= 0.0
		var rect := Rect2(Vector2(float(centres[index]) - wide * 0.5, middle - height * 0.5), Vector2(wide, height))
		ShowTheme.pill(self, rect, ShowTheme.PILL, Color(READY.r, READY.g, READY.b, 0.9) if ready else ShowTheme.PILL_EDGE, maxf(height * 0.04, 1.4))
		var glyph_at := rect.position + Vector2(height * 0.62, height * 0.5)
		if which == "coo": Icons.coo_glyph(self, glyph_at + Vector2(-height * 0.05, 0.0), height * 0.2, Color.WHITE if ready else WAIT)
		else: Icons.drop_glyph(self, glyph_at + Vector2(0.0, height * 0.05), height * 0.14, Color.WHITE, 1.0 if ready else 0.4)
		var words := which.to_upper() if touching else "%s  %s" % [which.to_upper(), str(keys.get(which, ""))]
		ShowTheme.text(self, words, rect.get_center() + Vector2(height * 0.34, 0.0), height * 0.44, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0 if ready else 0.55)
		if not ready: # the bar fills as the cooldown runs out
			var share := clampf(1.0 - left / total, 0.0, 1.0)
			var bar := Rect2(rect.position + Vector2(height * 0.5, height * 0.84), Vector2((wide - height) * share, height * 0.07))
			draw_rect(Rect2(bar.position, Vector2(wide - height, bar.size.y)), Color(1.0, 1.0, 1.0, 0.16))
			draw_rect(bar, READY)
