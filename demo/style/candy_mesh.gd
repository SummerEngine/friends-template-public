extends RefCounted
## Mesh builder of the candy world's decor (style/candy_world.gd): lumpy blobs, lobes of revolution, tubes and a polyline cage, collected into ONE surface with vertex colours (the colour
## is the surface's colour, light comes from the shader). Everything is placed by the current transform (`push` / `pop`). Normals are smooth: every shape computes them from its own
## triangles after it is added (area weighted, shared vertices), which is what makes a blob read as a pillow or a puff. Godot's front faces wind clockwise. Colours are authored sRGB
## and stored linear (`Color.srgb_to_linear`), the way the world's shaders read `COLOR`.
var xf := Transform3D.IDENTITY
## true: colours are DATA (a shader reads them as numbers, not as colours) and are stored as given.
var raw := false

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()
var _stack: Array[Transform3D] = []

func push(t: Transform3D) -> void:
	_stack.append(xf)
	xf = xf * t

func pop() -> void:
	xf = _stack.pop_back()

func triangle_count() -> int:
	return _i.size() / 3

func is_empty() -> bool:
	return _i.is_empty()

func _add(p: Vector3, color: Color) -> int:
	_v.append(xf * p)
	_n.append(Vector3.ZERO)
	_c.append(color if raw else color.srgb_to_linear())
	return _v.size() - 1

func _tri(a: int, b: int, c: int) -> void:
	_i.append(a)
	_i.append(b)
	_i.append(c)

## Smooth normals of the vertices from `v0` and the triangles from index `i0` on (area weighted). `inside` (when given) is a point inside the closed shape: if its triangles wind
## the wrong way round (their normals point at it) they are all turned over first.
func _smooth(v0: int, i0: int, inside := Vector3.INF) -> void:
	if inside != Vector3.INF:
		var turn := 0.0
		var j := i0
		while j < _i.size():
			var face := (_v[_i[j + 2]] - _v[_i[j]]).cross(_v[_i[j + 1]] - _v[_i[j]])
			turn += face.dot((_v[_i[j]] + _v[_i[j + 1]] + _v[_i[j + 2]]) / 3.0 - inside)
			j += 3
		if turn < 0.0:
			j = i0
			while j < _i.size():
				var swap := _i[j + 1]
				_i[j + 1] = _i[j + 2]
				_i[j + 2] = swap
				j += 3
	var k := i0
	while k < _i.size():
		var a := _i[k]
		var b := _i[k + 1]
		var c := _i[k + 2]
		var face := (_v[c] - _v[a]).cross(_v[b] - _v[a]) # clockwise front faces: the normal of (a, b, c) points out
		_n[a] += face
		_n[b] += face
		_n[c] += face
		k += 3
	for index in range(v0, _v.size()):
		_n[index] = _n[index].normalized() if _n[index].length_squared() > 1e-12 else Vector3.UP

## A lumpy ellipsoid: `radii` (x, y, z), `rings` x `sectors` (poles are single vertices), the radius moved by `lump` (a share of itself) with a few seeded sine lobes, the vertex colour
## from `top` at the pole up to `bottom` at the pole down. `flat_below` (-1..1, -1 = off) squashes everything under that sine of latitude to a flat floor, for the cloud puffs.
func blob(centre: Vector3, radii: Vector3, top: Color, bottom: Color, rings := 7, sectors := 12, lump := 0.0, seed_value := 0, flat_below := -1.0) -> void:
	var v0 := _v.size()
	var i0 := _i.size()
	var phase := Vector3(float(seed_value % 17) * 0.7, float(seed_value % 29) * 0.31, float(seed_value % 13) * 0.9)
	var floor_y := radii.y * flat_below
	_add(centre + Vector3(0.0, radii.y, 0.0), top)
	for ring in range(1, rings):
		var lat := PI * 0.5 - PI * float(ring) / float(rings) # +90 .. -90
		var colour := top.lerp(bottom, float(ring) / float(rings))
		for sector in sectors:
			var lon := TAU * float(sector) / float(sectors)
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var wobble := 1.0 + lump * (sin(lon * 3.0 + phase.x) * 0.5 + sin(lat * 4.0 + lon * 2.0 + phase.y) * 0.35 + sin(lon * 5.0 - lat * 3.0 + phase.z) * 0.15)
			var p := Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * wobble
			if flat_below > -1.0 and p.y < floor_y: p.y = floor_y + (p.y - floor_y) * 0.12
			_add(centre + p, colour)
	_add(centre + Vector3(0.0, -radii.y if flat_below <= -1.0 else floor_y, 0.0), bottom)
	var last := _v.size() - 1
	for sector in sectors: # top fan
		_tri(v0, v0 + 1 + (sector + 1) % sectors, v0 + 1 + sector)
	for ring in range(0, rings - 2):
		for sector in sectors:
			var a := v0 + 1 + ring * sectors + sector
			var b := v0 + 1 + ring * sectors + (sector + 1) % sectors
			var c := a + sectors
			var d := b + sectors
			_tri(a, b, c)
			_tri(b, d, c)
	var base := v0 + 1 + (rings - 2) * sectors
	for sector in sectors: # bottom fan
		_tri(last, base + sector, base + (sector + 1) % sectors)
	_smooth(v0, i0, xf * centre)

## A lobe of revolution about +y standing on y = 0: `profile` is (radius, y) from the foot up to the tip (radius 0), `colors` one colour per profile point; `sectors` around; `wobble`
## makes the section lumpy (a share of the radius) with `lobes` bumps round it; `squash` stretches x and z separately.
func lathe(profile: PackedVector2Array, colors: PackedColorArray, sectors: int, wobble := 0.0, lobes := 5, phase := 0.0, squash := Vector2.ONE) -> void:
	var v0 := _v.size()
	var i0 := _i.size()
	var rows := profile.size()
	for row in rows:
		var p := profile[row]
		for sector in sectors:
			var angle := TAU * float(sector) / float(sectors)
			var bump := 1.0 + wobble * (sin(angle * float(lobes) + phase + p.y * 2.0) * 0.6 + sin(angle * float(lobes + 2) - phase * 1.7 + p.y * 3.0) * 0.4)
			var radius := p.x * bump
			_add(Vector3(cos(angle) * radius * squash.x, p.y, sin(angle) * radius * squash.y), colors[row])
	for row in range(0, rows - 1):
		for sector in sectors:
			var a := v0 + row * sectors + sector
			var b := v0 + row * sectors + (sector + 1) % sectors
			var c := a + sectors
			var d := b + sectors
			_tri(a, c, b)
			_tri(b, c, d)
	_smooth(v0, i0, xf * Vector3(0.0, (profile[0].y + profile[rows - 1].y) * 0.5, 0.0))

## A tube of `radius` along the polyline `path` (round, `sides` sections, rounded ends): a rail or a post. `pinch` (0..1) makes it an inflatable: the radius shrinks by that share between full-size points every `period`
## metres of the path (a string of pillows, full size at both ends of an open path), so the path wants a point every metre or so.
func tube(path: PackedVector3Array, radius: float, sides: int, color: Color, pinch := 0.0, period := 3.0) -> void:
	var v0 := _v.size()
	var i0 := _i.size()
	var count := path.size()
	var previous := Vector3.UP
	var run := 0.0
	for k in count:
		if k > 0: run += path[k].distance_to(path[k - 1])
		var swell := 1.0 - pinch * (0.5 - 0.5 * cos(TAU * run / period))
		var along := (path[mini(k + 1, count - 1)] - path[maxi(k - 1, 0)]).normalized()
		var side := along.cross(previous)
		if side.length_squared() < 1e-6: side = along.cross(Vector3.RIGHT if absf(along.x) < 0.9 else Vector3.FORWARD)
		side = side.normalized()
		var up := side.cross(along).normalized()
		previous = up
		for s in sides:
			var angle := TAU * float(s) / float(sides)
			_add(path[k] + (side * cos(angle) + up * sin(angle)) * radius * swell, color)
	for k in range(0, count - 1):
		var middle := xf * ((path[k] + path[k + 1]) * 0.5)
		for s in sides:
			var a := v0 + k * sides + s
			var b := v0 + k * sides + (s + 1) % sides
			var c := a + sides
			var d := b + sides
			_tri_out(a, b, c, middle)
			_tri_out(b, d, c, middle)
	for end in [0, count - 1]: # round ends: a fan to one vertex a little beyond the end
		var dir := (path[0] - path[1]).normalized() if end == 0 else (path[count - 1] - path[count - 2]).normalized()
		var tip := _add(path[end] + dir * radius * 0.6, color)
		var inside := xf * (path[end] - dir * radius)
		for s in sides:
			_tri_out(tip, v0 + end * sides + s, v0 + end * sides + (s + 1) % sides, inside)
	_smooth(v0, i0)

## A triangle wound so that its front (clockwise) face looks away from the point `inside`.
func _tri_out(a: int, b: int, c: int, inside: Vector3) -> void:
	var face := (_v[c] - _v[a]).cross(_v[b] - _v[a])
	if face.dot((_v[a] + _v[b] + _v[c]) / 3.0 - inside) >= 0.0: _tri(a, b, c)
	else: _tri(a, c, b)

## The mesh of everything added, one surface, with `material`.
func to_mesh(material: Material = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_INDEX] = _i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null: mesh.surface_set_material(0, material)
	return mesh

## Smooth normals for a mesh made elsewhere (a height field): `v` positions, `i` triangle indices; returns the normals.
static func normals_of(v: PackedVector3Array, i: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(v.size())
	var k := 0
	while k < i.size():
		var a := i[k]
		var b := i[k + 1]
		var c := i[k + 2]
		var face := (v[c] - v[a]).cross(v[b] - v[a])
		n[a] += face
		n[b] += face
		n[c] += face
		k += 3
	for index in n.size():
		n[index] = n[index].normalized() if n[index].length_squared() > 1e-12 else Vector3.UP
	return n
