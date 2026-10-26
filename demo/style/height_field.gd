extends RefCounted
## The height field of a level for the contact shadows of the realistic look (surface.gdshader `contact`): per cell of CELL metres, the
## height of the highest static top over it (world y), EMPTY where there is none. Built once per level from the upward faces of the
## static collision shapes, as a half-float texture. Client only.
const CELL := 0.25
const MAX_CELLS := 1024
const MARGIN := 2.0
const EMPTY := -1000.0

var texture: ImageTexture
var rect := Vector4.ZERO    ## world x, z of the corner, 1 / width, 1 / depth (the shader's height_rect)

## `tops`: Array of world-space triangles [a, b, c] facing up.
static func build(tops: Array) -> RefCounted:
	var field := new()
	if tops.is_empty(): return field
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for tri: Array in tops:
		for p: Vector3 in tri:
			low = Vector2(minf(low.x, p.x), minf(low.y, p.z))
			high = Vector2(maxf(high.x, p.x), maxf(high.y, p.z))
	low -= Vector2.ONE * MARGIN
	high += Vector2.ONE * MARGIN
	var cell := maxf(CELL, maxf(high.x - low.x, high.y - low.y) / MAX_CELLS)
	var width := clampi(ceili((high.x - low.x) / cell), 1, MAX_CELLS)
	var depth := clampi(ceili((high.y - low.y) / cell), 1, MAX_CELLS)
	var heights := PackedFloat32Array()
	heights.resize(width * depth)
	heights.fill(EMPTY)
	for tri: Array in tops:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var normal := (b - a).cross(c - a)
		if absf(normal.y) < 1e-6: continue
		var x0 := clampi(floori((minf(a.x, minf(b.x, c.x)) - low.x) / cell), 0, width - 1)
		var x1 := clampi(ceili((maxf(a.x, maxf(b.x, c.x)) - low.x) / cell), 0, width - 1)
		var z0 := clampi(floori((minf(a.z, minf(b.z, c.z)) - low.y) / cell), 0, depth - 1)
		var z1 := clampi(ceili((maxf(a.z, maxf(b.z, c.z)) - low.y) / cell), 0, depth - 1)
		var pa := Vector2(a.x, a.z)
		var pb := Vector2(b.x, b.z)
		var pc := Vector2(c.x, c.z)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(low.x + (x + 0.5) * cell, low.y + (z + 0.5) * cell)
				if not _inside(p, pa, pb, pc): continue
				# the plane through the triangle at p
				var y := a.y - (normal.x * (p.x - a.x) + normal.z * (p.y - a.z)) / normal.y
				var index := z * width + x
				if y > heights[index]: heights[index] = y
	var image := Image.create_from_data(width, depth, false, Image.FORMAT_RF, heights.to_byte_array())
	image.convert(Image.FORMAT_RH)
	field.texture = ImageTexture.create_from_image(image)
	field.rect = Vector4(low.x, low.y, 1.0 / (width * cell), 1.0 / (depth * cell))
	return field

## Inside or on the edge of a triangle (grown by a hair so cells on a shared edge count).
static func _inside(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var negative := d1 < -1e-4 or d2 < -1e-4 or d3 < -1e-4
	var positive := d1 > 1e-4 or d2 > 1e-4 or d3 > 1e-4
	return not (negative and positive)

func apply(material: ShaderMaterial) -> void:
	if texture == null: return
	material.set_shader_parameter("height_map", texture)
	material.set_shader_parameter("height_rect", rect)
