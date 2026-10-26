extends Control
## Hearts that float up from the menu pet while it is petted: drawn shapes (soft pink, white rim), no textures.
##   hearts.emit(at)      # one heart rising from `at` (local px)
const FILL := Color("ff8fab")
const RIM := Color("fff6f8")
## Seconds a heart lives, how far it rises and its size, in shares of the title height.
const LIFE := 1.6
const RISE := 0.16
const SIZE := 0.032

var _hearts: Array = []
var _random := RandomNumberGenerator.new()
static var _outline := PackedVector2Array()

func _init() -> void:
	name = "PetHearts"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_random.randomize()

func emit(at: Vector2) -> void:
	_hearts.append({"from": at + Vector2(_random.randf_range(-1.0, 1.0), 0.0) * size.y * 0.03, "age": 0.0,
		"drift": _random.randf_range(-1.0, 1.0), "scale": _random.randf_range(0.8, 1.2), "tilt": _random.randf_range(-0.25, 0.25)})

func count() -> int:
	return _hearts.size()

func _process(delta: float) -> void:
	if _hearts.is_empty(): return
	for heart in _hearts: heart.age += delta
	_hearts = _hearts.filter(func(heart: Dictionary) -> bool: return heart.age < LIFE)
	queue_redraw()

func _draw() -> void:
	if _outline.is_empty(): _outline = _shape()
	for heart in _hearts:
		var t: float = heart.age / LIFE
		# Pops in, rises and sways, fades over its last third.
		var grow := minf(t / 0.15, 1.0)
		var at: Vector2 = heart.from + Vector2(sin(t * TAU * 0.8) * heart.drift * size.y * 0.02, -t * RISE * size.y)
		var scale: float = size.y * SIZE * heart.scale * (0.5 + 0.5 * ease(grow, 0.4))
		var alpha := clampf((1.0 - t) / 0.35, 0.0, 1.0)
		draw_set_transform(at, heart.tilt, Vector2.ONE * scale)
		draw_colored_polygon(_outline, Color(FILL, alpha))
		var closed := _outline.duplicate()
		closed.append(_outline[0])
		draw_polyline(closed, Color(RIM, alpha * 0.9), 0.12, true)
	draw_set_transform(Vector2.ZERO)

## A unit heart (about 1 wide), centred on its middle.
static func _shape() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 48:
		var t := TAU * index / 48.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		points.append(Vector2(x, y + 2.0) / 32.0)
	return points
