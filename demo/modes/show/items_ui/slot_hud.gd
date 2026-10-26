extends Control
## The item pill, the banners and the lines of the show's items, one control drawing in the show's one look (client/show_theme.gd, client/show_hud_kit.gd). The model comes from
## items_view.gd: {held (catalog index, -1 none), spin (s of the roll left), age (clock), banner {kind, words, line, age}, lines [{text, left}], pool [catalog indexes the roll spins through]}.
## Top left: a dark pill with the item's icon (ItemIcons) at its left end, the item's name in slanted words and the key to press (not on a phone: the
## round ITEM button says it); empty it is dimmed ("ITEM"). While the box's roll spins the icon flips through the pool and the name reads "???", then the item pops in.
## The banner is the show's (client/show_banner.gd): the effect's big words in the middle, high up; the lines (another player's item) are pills at the top centre.
const ShowTheme := preload("res://client/show_theme.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const Kit := preload("res://style/show_hud_kit.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const Catalog := preload("res://modes/show/items/catalog.gd")
const ItemIcons := preload("res://modes/show/items/item_icons.gd")

const PILL_H := 56.0
const FLIP := 0.08 ## s per icon while the box's roll spins
const BANNER_AT := 0.3

var manager
var model := {}
var _was_spin := false
var _revealed := 0.0 ## s since the roll ended

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if model.is_empty(): return
	_revealed += delta

var _pill_rect := Rect2()

func _draw() -> void:
	_pill_rect = Rect2()
	if model.is_empty(): return
	var view := get_viewport_rect().size
	var k := Kit.k(self)
	_pill(k)
	if bool(model.get("lab", false)) and _pill_rect.size.x > 0.0: # the item lab: a small hint pill under the item pill
		Kit.line_pill(self, "1-7: TEST ITEMS", Vector2(_pill_rect.get_center().x, _pill_rect.end.y + 16.0 * k), k * 0.62, 0.9, 0.0, view.x * 0.4)
	_lines(view, k)
	_banner(view, k)

## The key that uses the item, as the hint under its name shows it.
static func key_name(touching: bool) -> String:
	if touching: return ""
	return "Y" if TouchControls.last_device == "pad" else "E"

func _pill(k: float) -> void:
	var held := int(model.get("held", -1))
	var spin := float(model.get("spin", 0.0))
	var clock := float(model.get("age", 0.0))
	var spinning := held >= 0 and spin > 0.0
	if _was_spin and not spinning and held >= 0: _revealed = 0.0
	_was_spin = spinning
	var h := PILL_H * k
	var top := (Kit.TOP + 6.0) * k
	var left := Kit.MARGIN * k
	var icon_r := h * 0.36 ## the icon's radius, centred h/2 from the pill's left end
	var centre := Vector2(left + h * 0.5, top + h * 0.5)
	var text_left := centre.x + icon_r + h * 0.2 ## where the words start
	var kind := held
	if spinning:
		var pool: Array = model.get("pool", [])
		kind = int(pool[int(clock / FLIP) % pool.size()]) if not pool.is_empty() else held
	var words := "ITEM"
	if spinning: words = "???"
	elif held >= 0: words = Catalog.text(Catalog.id_of(held), "name")
	var empty := held < 0
	var alpha := 0.55 if empty else 1.0
	var pop := 1.0 if empty or spinning else 1.0 + 0.18 * exp(-_revealed * 9.0) * cos(_revealed * 22.0)
	var size := h * 0.46
	var wide := maxf(text_left - left + ShowTheme.width(words, size) * (1.0 + ShowTheme.SLANT * 0.1) + h * 0.45, h * 3.0)
	var rect := Rect2(left, top, wide, h)
	_pill_rect = rect
	ShowTheme.pill(self, rect, ShowTheme.PILL, ShowTheme.PILL_EDGE, maxf(h * 0.04, 1.2), alpha)
	var shown := not empty and not spinning
	# the icon at the left end, no disc behind it (the roll's flipping icons are plain too)
	if kind >= 0: ItemIcons.draw(self, kind, centre, icon_r * pop, alpha)
	else: ShowTheme.text(self, "?", centre, icon_r * 1.6, Color(1, 1, 1, 0.5), Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha)
	var hint := key_name(manager != null and manager.run != null and manager.run.get("touch") != null and is_instance_valid(manager.run.touch) and manager.run.touch.is_active()) if shown else ""
	var middle := top + h * 0.5 - (h * 0.1 if hint != "" else 0.0)
	ShowTheme.text(self, words, Vector2(text_left, middle), size, Color.WHITE if not empty else Color(1, 1, 1, 0.8), Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, alpha, HORIZONTAL_ALIGNMENT_LEFT)
	if hint != "":
		var cap := Rect2(text_left, top + h * 0.62, h * 0.28, h * 0.28)
		ShowTheme.box(self, cap, ShowTheme.CREAM, ShowTheme.NAVY, 1.4, h * 0.07)
		ShowTheme.text(self, hint, cap.get_center(), cap.size.y * 0.8, ShowTheme.NAVY, Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, 0.0, 1.0)
		ShowTheme.text(self, "TO USE", Vector2(cap.end.x + h * 0.1, cap.get_center().y), h * 0.26, Color(1, 1, 1, 0.78), Color(0, 0, 0, 0), 0.0, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)

func _lines(view: Vector2, k: float) -> void:
	var list: Array = model.get("lines", [])
	var top := (Kit.TOP + 76.0) * k
	for index in range(list.size() - 1, -1, -1):
		var line: Dictionary = list[index]
		var left := float(line.left)
		var rect := Kit.line_pill(self, str(line.text), Vector2(view.x * 0.5, top + Kit.ROW_H * k * 0.6), k * 0.9, clampf(left / 0.3, 0.0, 1.0), 0.0, view.x * 0.7)
		top = rect.end.y + 6.0 * k

func _banner(view: Vector2, k: float) -> void:
	var banner: Dictionary = model.get("banner", {})
	if banner.is_empty(): return
	var wide := ShowBanner.small_wide(view.x, k)
	ShowBanner.draw(self, str(banner.kind), str(banner.words), float(banner.age), Vector2(view.x * 0.5, view.y * BANNER_AT), wide, 1.0, str(banner.get("line", "")))
