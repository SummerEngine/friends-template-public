extends RefCounted
## The hexagon grid of the step tiles (levels/step_tiles.gd), pure maths. Pointy-top hexagons of `pitch` metres across the flats (the
## distance between two neighbours' middles), rows along X. A floor's `rows` are drawn in ASCII with one character per HALF tile width: a tile
## is a kind character, its neighbour in the same row is 2 columns on, the next row's neighbours sit 1 column to either side, so
## (column + row) is always even; spaces and '.' are holes. A cell is (column, row) of that text, which is axial (q, r) with
## column = 2q + r and row = r (q grows along the row). `layout` is {centre (Vector2 x, z), cols, rows}: the text's middle is `centre`.

const ROW := 0.8660254037844386  ## sqrt(3) / 2: the distance between two rows, in pitches
const SIDES := 6

## Level-local (x, z) of the middle of `cell` on `layout`.
static func cell_centre(pitch: float, layout: Dictionary, cell: Vector2i) -> Vector2:
	var centre: Vector2 = layout.centre
	return Vector2(centre.x + (cell.x - (int(layout.cols) - 1) * 0.5) * pitch * 0.5, centre.y + (cell.y - (int(layout.rows) - 1) * 0.5) * pitch * ROW)

## The cell of `layout` (it need not be a tile) whose hexagon holds the level-local point (x, z): cube rounding of the axial coordinates.
static func cell_of(pitch: float, layout: Dictionary, x: float, z: float) -> Vector2i:
	var centre: Vector2 = layout.centre
	var column := (x - centre.x) / (pitch * 0.5) + (int(layout.cols) - 1) * 0.5
	var row := (z - centre.y) / (pitch * ROW) + (int(layout.rows) - 1) * 0.5
	var qf := (column - row) * 0.5
	var sf := -qf - row
	var q := roundf(qf)
	var r := roundf(row)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - row)
	var ds := absf(s - sf)
	if dq > dr and dq > ds: q = -r - s
	elif dr > ds: r = -q - s
	return Vector2i(int(2.0 * q + r), int(r))

## True when (dx, dz) from a hexagon's middle is within `reach` of its edges (a hexagon of `pitch` across the flats, flats facing +-X and +-60 degrees).
static func hex_holds(pitch: float, dx: float, dz: float, reach: float) -> bool:
	var apothem := pitch * 0.5 + reach
	return absf(dx) <= apothem and absf(dx * 0.5 + dz * ROW) <= apothem and absf(dx * 0.5 - dz * ROW) <= apothem

## The corners of a pointy-top hexagon of circumradius `radius` around the origin (x, z), the first on +Z.
static func hex_corners(radius: float) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for k in SIDES: corners.append(Vector2(sin(TAU * k / SIDES), cos(TAU * k / SIDES)) * radius)
	return corners
