extends RefCounted
## The square grid of the stage tiles (levels/step_tiles.gd with `"grid": "square"`), pure maths; the same functions as levels/hex_grid.gd so the tiles ask
## either one. Square tiles of `pitch` metres a side, a floor's `rows` draw the layout in ASCII with ONE character per tile (a space or '.' is a hole).
## A cell is (column, row) of that text; `layout` is {centre (Vector2 x, z), cols, rows}: the text's middle is `centre`, columns run along +X, rows along +Z.

## Level-local (x, z) of the middle of `cell` on `layout`.
static func cell_centre(pitch: float, layout: Dictionary, cell: Vector2i) -> Vector2:
	var centre: Vector2 = layout.centre
	return Vector2(centre.x + (cell.x - (int(layout.cols) - 1) * 0.5) * pitch, centre.y + (cell.y - (int(layout.rows) - 1) * 0.5) * pitch)

## The cell of `layout` (it need not be a tile) whose square holds the level-local point (x, z).
static func cell_of(pitch: float, layout: Dictionary, x: float, z: float) -> Vector2i:
	var centre: Vector2 = layout.centre
	return Vector2i(roundi((x - centre.x) / pitch + (int(layout.cols) - 1) * 0.5), roundi((z - centre.y) / pitch + (int(layout.rows) - 1) * 0.5))

## True when (dx, dz) from a square's middle is within `reach` of its edges.
static func holds(pitch: float, dx: float, dz: float, reach: float) -> bool:
	var half := pitch * 0.5 + reach
	return absf(dx) <= half and absf(dz) <= half

## The corners of a square of half-width `half` around the origin (x, z).
static func corners(half: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
