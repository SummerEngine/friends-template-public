extends Control
## GHOST PIGEON (docs/pigeon.md): the splat a pigeon's drop leaves on the LOCAL player's screen: a few big white blobs that pop in, sag and drip over about a third of the picture (the rest stays in view:
## it half blocks, it never blinds), then fade out over the last 0.4 s. Pure drawing from a small model; the authority decides who wears one and for how long (state `pigeon.s`).
## model: {age (s since it landed), left (s it still stays), seed (int: the shape, the same for a given drop)}; an empty model draws nothing.
const ShowTheme := preload("res://client/show_theme.gd")

const FADE := 0.4 ## s the splat fades out over at the end
const SKY := Color(0.97, 0.98, 0.96)
const RIM := Color(0.78, 0.83, 0.92)
const SHADE := Color(0.62, 0.68, 0.8)

var model := {}
var _shape_seed := -1
var _blobs: Array = [] ## {u, v, r (of the screen's height), points: [unit offsets], drips: [{dx, len, wide}]}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func show_model(next: Dictionary) -> void:
	model = next
	visible = not next.is_empty()
	queue_redraw()

## The blobs of `seed`: three big ones across the middle of the picture, three medium, a few flecks.
func _make(seed_value: int) -> void:
	_shape_seed = seed_value
	_blobs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var sizes := [0.22, 0.2, 0.23, 0.12, 0.11, 0.13, 0.045, 0.035, 0.05]
	var spots := [Vector2(0.27, 0.42), Vector2(0.52, 0.5), Vector2(0.77, 0.4), Vector2(0.4, 0.2), Vector2(0.66, 0.25), Vector2(0.14, 0.62), Vector2(0.9, 0.62), Vector2(0.5, 0.78), Vector2(0.3, 0.8)]
	for index in sizes.size():
		var spot: Vector2 = spots[index] + Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
		var points := PackedVector2Array()
		var phase_a := rng.randf() * TAU
		var phase_b := rng.randf() * TAU
		for step in 18:
			var angle := TAU * float(step) / 18.0
			var wobble := 1.0 + 0.16 * sin(angle * 3.0 + phase_a) + 0.1 * sin(angle * 5.0 + phase_b)
			points.append(Vector2(cos(angle), sin(angle)) * wobble)
		var drips := []
		if float(sizes[index]) > 0.1:
			for drip in rng.randi_range(1, 2): drips.append({"dx": rng.randf_range(-0.5, 0.5), "len": rng.randf_range(0.9, 1.9), "wide": rng.randf_range(0.14, 0.24)})
		_blobs.append({"u": spot.x, "v": spot.y, "r": float(sizes[index]), "points": points, "drips": drips})

func _draw() -> void:
	if model.is_empty(): return
	if int(model.get("seed", 0)) != _shape_seed: _make(int(model.get("seed", 0)))
	var view := get_viewport_rect().size
	var age := float(model.get("age", 0.0))
	var alpha := clampf(float(model.get("left", 0.0)) / FADE, 0.0, 1.0)
	if alpha <= 0.0: return
	var sag := age * view.y * 0.012 # the whole of it slides down a little
	for layer in 2: # the shade of every blob first, then the blobs
		for index in _blobs.size():
			var blob: Dictionary = _blobs[index]
			var pop := ShowTheme.pop_scale(age - float(index) * 0.025, 0.2, 0.25)
			if pop <= 0.0: continue
			var centre := Vector2(float(blob.u) * view.x, float(blob.v) * view.y + sag)
			var radius := float(blob.r) * view.y * pop
			var offset := Vector2(5.0, 7.0) if layer == 0 else Vector2.ZERO
			var points := PackedVector2Array()
			for unit: Vector2 in blob.points: points.append(centre + offset + unit * radius)
			if layer == 0:
				draw_colored_polygon(points, Color(SHADE.r, SHADE.g, SHADE.b, 0.55 * alpha))
				continue
			for drip: Dictionary in blob.drips: # drips run down from the blob's belly, growing with the age
				var grow := 1.0 - exp(-age * 2.2)
				var length := radius * float(drip.len) * grow
				var wide := radius * float(drip.wide)
				var x := centre.x + radius * float(drip.dx)
				draw_rect(Rect2(x - wide * 0.5, centre.y, wide, radius * 0.7 + length), Color(SKY.r, SKY.g, SKY.b, alpha))
				draw_circle(Vector2(x, centre.y + radius * 0.7 + length), wide * 0.75, Color(SKY.r, SKY.g, SKY.b, alpha))
			draw_colored_polygon(points, Color(SKY.r, SKY.g, SKY.b, alpha))
			var rim := PackedVector2Array(points)
			rim.append(points[0])
			draw_polyline(rim, Color(RIM.r, RIM.g, RIM.b, alpha), maxf(radius * 0.05, 2.0), true)
			draw_circle(centre + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.22, Color(1.0, 1.0, 1.0, alpha * 0.9)) # a wet glint
