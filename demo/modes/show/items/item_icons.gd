extends RefCounted
## The icons of the show's items, drawn by each item's look (`draw_icon` of `<id>_view.gd`) into any CanvasItem: the HUD's item pill, the touch ITEM button. One instance of each look
## without a manager draws its icon.
const Catalog := preload("res://modes/show/items/catalog.gd")
const ShowTheme := preload("res://client/show_theme.gd")

static var _looks := {}

## The look instance of catalog index `kind` (an icon-only one), null when the item has no view script.
static func look(kind: int):
	var id := Catalog.id_of(kind)
	if id == "": return null
	if not _looks.has(id):
		var path := "res" + "://modes/show/items_ui/%s_view.gd" % id
		_looks[id] = (load(path) as GDScript).new() if ResourceLoader.exists(path) else null
		if _looks[id] != null: _looks[id].setup(null, id)
	return _looks[id]

## The icon of item `kind` centred on `c` within radius `r` (nothing for -1 or an item without a look).
static func draw(ci: CanvasItem, kind: int, c: Vector2, r: float, alpha := 1.0) -> void:
	var item = look(kind)
	if item != null: item.draw_icon(ci, c, r, alpha)

## The round ITEM key of the phone: a dark disc with a light outline, the item's icon on it and the caption under it, filling `rect` (a square).
static func touch_button(ci: CanvasItem, rect: Rect2, kind: int, held: bool) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5 * 0.9
	ci.draw_circle(c, r, Color(ShowTheme.PILL.r, ShowTheme.PILL.g, ShowTheme.PILL.b, 0.82 if held else 0.66))
	ci.draw_arc(c, r - 1.5, 0.0, TAU, 56, ShowTheme.CREAM if held else Color(1.0, 1.0, 1.0, 0.55), 3.5, true)
	draw(ci, kind, c + Vector2(0.0, -r * 0.08), r * 0.62)
	ShowTheme.text(ci, "ITEM", c + Vector2(0.0, r * 0.74), r * 0.36, Color.WHITE, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 0.95)
