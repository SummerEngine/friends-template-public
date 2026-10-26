extends CanvasLayer
## The dash's cooldown, shown subtly (game_run.gd, only where the mode has a dash, never in a stage round, which has none): a thin dark pill low in the middle of the
## screen whose light bar fills while the dash recharges (courier_motion.gd DASH_COOLDOWN, `dash_cooldown`) and that fades out a moment after it is ready. Nothing is
## shown while the dash is ready. Client only, pure look: the owner's own motion state in, pixels out; it has no state of the game.
const ShowTheme := preload("res://client/show_theme.gd")
const FADE_IN := 0.12 ## s
const FADE_OUT := 0.35 ## s after the cooldown is over
const WIDE := 132.0 ## px at the 720 px reference
const HIGH := 12.0
const ABOVE := 96.0 ## px from the bottom edge at the reference (above the hint line, clear of the touch buttons' middle)
const FILL := Color("ffd23f")
const READY := Color("7cf0a8")

var _face: Control
var _left := 0.0
var _total := 1.0
var _alpha := 0.0
var _ready_flash := 0.0

class Face extends Control:
	var meter

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if meter == null or meter._alpha <= 0.01: return
		var k := ShowTheme.unit(self)
		var view := get_viewport_rect().size
		var rect := Rect2(Vector2((view.x - WIDE * k) * 0.5, view.y - ABOVE * k), Vector2(WIDE * k, HIGH * k))
		var a: float = meter._alpha
		ShowTheme.pill(self, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, 1.2, a * 0.8)
		var share: float = clampf(1.0 - meter._left / maxf(meter._total, 0.001), 0.0, 1.0)
		var inner := rect.grow(-2.0 * k)
		if share > 0.0:
			var bar := Rect2(inner.position, Vector2(inner.size.x * share, inner.size.y))
			var colour: Color = READY if meter._left <= 0.0 else FILL
			ShowTheme.box(self, bar, Color(colour, a * 0.9))

func _init() -> void:
	layer = 21
	visible = false

func _ready() -> void:
	_face = Face.new()
	_face.meter = self
	_face.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_face)

## One rendered frame: `left` s of cooldown still to go of `total` (a negative `left`: no dash to show, hidden at once).
func update(delta: float, left: float, total: float) -> void:
	if left < 0.0:
		_alpha = 0.0
		_left = 0.0
		visible = false
		return
	_total = total
	if left > 0.0:
		_left = left
		_ready_flash = FADE_OUT
		_alpha = minf(_alpha + delta / FADE_IN, 1.0)
	else:
		_left = 0.0
		_ready_flash = maxf(_ready_flash - delta, 0.0)
		_alpha = clampf(_ready_flash / FADE_OUT, 0.0, 1.0)
	visible = _alpha > 0.01
	if _face != null: _face.queue_redraw()
