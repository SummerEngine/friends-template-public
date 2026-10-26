extends RefCounted
## EXPERIMENT (switchable): THE MANAGER. The icons of the rules, plain light strokes on the dark pill (the item pills' way: no disc behind them), drawn into any CanvasItem within radius `r`
## around `c`: the rule's card in the prompt and the pill that counts a rule down. All code, no pictures, no people.
const CREAM := Color(0.94, 0.97, 1.0)
const RED := Color("ff5a60")

static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, alpha := 1.0) -> void:
	var col := Color(CREAM, alpha)
	var w := r * 0.2
	match id:
		"flip": # two arrows the other way round: left is right
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.32), c + Vector2(r * 0.6, -r * 0.32), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.85, -r * 0.32), c + Vector2(r * 0.4, -r * 0.7), c + Vector2(r * 0.4, r * 0.06)]), col)
			ci.draw_line(c + Vector2(r * 0.7, r * 0.38), c + Vector2(-r * 0.6, r * 0.38), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.38), c + Vector2(-r * 0.4, r * 0.0), c + Vector2(-r * 0.4, r * 0.76)]), col)
		"moon": # a crescent and a spark
			ci.draw_arc(c + Vector2(-r * 0.08, 0.0), r * 0.62, deg_to_rad(-60.0), deg_to_rad(240.0), 28, col, r * 0.34, true)
			ci.draw_circle(c + Vector2(r * 0.52, -r * 0.5), r * 0.12, col)
		"nojump": # a jump arrow crossed out
			ci.draw_line(c + Vector2(0.0, r * 0.5), c + Vector2(0.0, -r * 0.25), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -r * 0.8), c + Vector2(-r * 0.46, -r * 0.2), c + Vector2(r * 0.46, -r * 0.2)]), col)
			ci.draw_arc(c, r * 0.86, 0.0, TAU, 32, Color(RED, alpha), w * 0.9, true)
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), Color(RED, alpha), w * 0.9, true)
		"giant": # a big block and the way up
			ci.draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.2), Vector2(r * 1.24, r * 0.98)), col, false, w)
			ci.draw_line(c + Vector2(0.0, -r * 0.3), c + Vector2(0.0, -r * 0.82), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -r * 1.0), c + Vector2(-r * 0.32, -r * 0.6), c + Vector2(r * 0.32, -r * 0.6)]), col)
		"tiny": # a small block and the way down
			ci.draw_rect(Rect2(c + Vector2(-r * 0.28, r * 0.24), Vector2(r * 0.56, r * 0.5)), col, false, w)
			ci.draw_line(c + Vector2(0.0, -r * 0.82), c + Vector2(0.0, -r * 0.2), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, 0.0), c + Vector2(-r * 0.32, -r * 0.4), c + Vector2(r * 0.32, -r * 0.4)]), col)
		"ice": # a snowflake
			for index in 3:
				var dir := Vector2.from_angle(PI * float(index) / 3.0 + PI * 0.5)
				ci.draw_line(c - dir * r * 0.86, c + dir * r * 0.86, col, w * 0.8, true)
			for index in 6:
				var tip := Vector2.from_angle(TAU * float(index) / 6.0 + PI * 0.5) * r * 0.56
				var along := tip.normalized()
				var side := Vector2(-along.y, along.x)
				ci.draw_line(c + tip, c + tip + (side + along) * r * 0.2, col, w * 0.6, true)
				ci.draw_line(c + tip, c + tip + (-side + along) * r * 0.2, col, w * 0.6, true)
		"walk": # two footprints
			_foot(ci, c + Vector2(-r * 0.3, r * 0.22), r * 0.5, -0.2, col)
			_foot(ci, c + Vector2(r * 0.34, -r * 0.2), r * 0.5, 0.2, col)
		"upside": # a camera turned over
			ci.draw_set_transform(c, PI, Vector2.ONE)
			ci.draw_rect(Rect2(Vector2(-r * 0.78, -r * 0.4), Vector2(r * 1.56, r * 1.0)), col, false, w)
			ci.draw_rect(Rect2(Vector2(-r * 0.3, -r * 0.62), Vector2(r * 0.6, r * 0.22)), col)
			ci.draw_arc(Vector2(0.0, r * 0.1), r * 0.3, 0.0, TAU, 20, col, w * 0.8, true)
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		_:
			ci.draw_circle(c, r * 0.5, col)

## A footprint: a sole and a heel, `turn` radians off straight up.
static func _foot(ci: CanvasItem, at: Vector2, size: float, turn: float, col: Color) -> void:
	var sole := PackedVector2Array()
	var heel := PackedVector2Array()
	for step in 14:
		var a := TAU * float(step) / 14.0
		sole.append(at + Vector2(cos(a) * size * 0.3, sin(a) * size * 0.46 - size * 0.2).rotated(turn))
		heel.append(at + Vector2(cos(a) * size * 0.22, sin(a) * size * 0.22 + size * 0.5).rotated(turn))
	ci.draw_colored_polygon(sole, col)
	ci.draw_colored_polygon(heel, col)
