extends Control
## The customizer (wardrobe.gd opens it at the booth). On the left the player's own character, big, on a painted-sky stage (the
## preview camera, wardrobe_camera.gd) with turn and zoom buttons (dragging works too); on the right a sheet headed
## "PLAYER: <name>" with the tabs BODY, FACE, HAIR, HAT, OUTFIT and PARAMS. A tab shows its pickers on top (items with a None
## tile, colour swatches) and the sliders of its param groups below; PARAMS shows every slider. A slider runs -1..1 and shows
## its value with one decimal (tap the value: back to 0). The sliders come from the catalog's "params" list, so a new param
## appears without a change here. The bottom bar: RANDOMIZE ALL, RANDOMIZE PARAMS, RESET PARAMS, CANCEL (the look before
## opening comes back) and CONFIRM (saved). Every change emits look_changed at once; the booth wears it.
## The show's menu look (style/menu_kit.gd: a violet sheet, chunky plates, Lilita One lettering), big touch targets. Landscape: preview left, sheet right. An upright phone:
## preview on top, sheet below, all grown to the size it has on the same phone held sideways (ui_scale). Pads move the focus
## (d-pad, left stick; a focused slider moves a tenth per press) and pick with A; wardrobe.gd forwards LB / RB (tabs), Y (randomize
## all), B (cancel) and Start (confirm). Item tiles show the item's picture (wardrobe_thumbs.gd), until then its name.
signal look_changed(look)
signal confirm_pressed
signal cancel_pressed
signal zoom_step(factor: float)
signal layout_changed(frame: Vector2, free_height: float)

const Catalog = preload("res://character/catalog.gd")
const Look = preload("res://character/look.gd")
const Thumbs = preload("res://character/wardrobe/wardrobe_thumbs.gd")
const TouchControls = preload("res://client/touch_controls.gd")
const Kit = preload("res://style/menu_kit.gd")
const ComicSkin = preload("res://client/menu_skin.gd")
const Widgets = preload("res://client/friends_widgets.gd")

## The tabs: rows of pickers ("item:<slot>" or "color:<colour slot>", in this order; catalog slots no tab names join
## OUTFIT) and the param groups whose sliders follow ("*": every param).
const TABS := [
	{"title": "BODY", "rows": ["color:skin"], "groups": ["body", "fun"]},
	{"title": "FACE", "rows": ["item:head", "item:eyes", "item:eyelids", "item:brows", "item:nose", "item:mouth", "item:ears"], "groups": ["head", "face"]},
	{"title": "HAIR", "rows": ["item:hair"], "groups": []},
	{"title": "HAT", "rows": ["item:hat"], "groups": ["hat"]},
	{"title": "OUTFIT", "rows": ["item:outfit", "item:shirt", "color:shirt", "color:pants", "color:shoes", "item:hand"], "groups": []},
	{"title": "PARAMS", "rows": [], "groups": ["*"]},
]
const ROW_TITLES := {"item:head": "Head", "item:eyes": "Eyes", "item:eyelids": "Eyelids", "item:brows": "Brows", "item:nose": "Nose",
	"item:mouth": "Mouth", "item:ears": "Ears", "item:hair": "Hair", "item:hat": "Hat", "item:outfit": "Outfit", "item:shirt": "Shirt print", "item:hand": "In your hand",
	"color:skin": "Skin colour", "color:shirt": "Shirt colour", "color:pants": "Pants colour", "color:shoes": "Shoes colour"}
const GROUP_TITLES := {"body": "Body", "head": "Head shape", "face": "Face", "hat": "Hat shape", "fun": "Fun"}

const TILE := Color("6a48e0") ## an item tile: a lighter violet plate on the violet sheet
const TILE_HOVER := Color("7d5cf0")
const TILE_PICKED := Color("8f70f7")
const SOFT_INK := Kit.MUTED_ON_DARK
const PICKED := Kit.GOLD ## the ring of the picked tile / swatch
const MARGIN := 20.0
const TURN_SPEED := 1.8 ## radians per second while a turn button is held

var look ## the CharacterLook being edited
var tab := -1
var portrait := false
var spin := 0.0 ## -1 / 1 while a turn button is held (wardrobe.gd turns the camera)
var thumbs: Node
var seat := 0 ## the local seat whose look this is (its awards decide which won items the Hat tab offers)
var _sheet: PanelContainer
var _name_label: Label
var _tab_grid: GridContainer
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _page: VBoxContainer
var _bar: VBoxContainer
var _bar_rows: Array[HBoxContainer] = []
var _bar_buttons := {} ## name -> Button
var _view_tools: HBoxContainer
var _tiles := {} ## row ("item:<slot>" / "color:<slot>") -> {value -> Button}
var _sliders := {} ## param id -> {"slider": HSlider, "value": Button}
var _waiting := {} ## picture key (Thumbs.key) -> tiles waiting for it
var _shown_colors := {} ## the colours the item pictures show
var _pad := false
var _rng := RandomNumberGenerator.new()

## A round chunky button with a drawn sign: "plus", "minus", "left" or "right" (a turning arrow).
class SignButton extends Button:
	var sign_name := ""
	func _draw() -> void:
		# On the plate's face (above its lip), white with a dark edge.
		var middle := Vector2(size.x * 0.5, Kit.Chunk.face_middle(size.y))
		var reach := minf(size.x, size.y) * 0.2
		for pass_index in 2:
			var ink := Kit.EDGE if pass_index == 0 else Color.WHITE
			var grow := 4.0 if pass_index == 0 else 0.0
			match sign_name:
				"plus", "minus":
					draw_line(middle - Vector2(reach, 0.0), middle + Vector2(reach, 0.0), ink, 5.0 + grow, true)
					if sign_name == "plus": draw_line(middle - Vector2(0.0, reach), middle + Vector2(0.0, reach), ink, 5.0 + grow, true)
				"left", "right":
					var turn := -1.0 if sign_name == "left" else 1.0
					draw_arc(middle, reach, deg_to_rad(-200.0), deg_to_rad(20.0), 24, ink, 4.5 + grow, true)
					var tip := middle + Vector2(cos(deg_to_rad(20.0)), sin(deg_to_rad(20.0))) * reach if turn > 0.0 else middle + Vector2(cos(deg_to_rad(-200.0)), sin(deg_to_rad(-200.0))) * reach
					var along := Vector2(-sin(deg_to_rad(20.0)), cos(deg_to_rad(20.0))) if turn > 0.0 else Vector2(sin(deg_to_rad(-200.0)), -cos(deg_to_rad(-200.0)))
					var side := Vector2(-along.y, along.x)
					var wide := 7.0 + grow * 0.5
					draw_colored_polygon(PackedVector2Array([tip + along * (8.0 + grow * 0.5), tip - along * 3.0 + side * wide, tip - along * 3.0 - side * wide]), ink)

# ------------------------------------------------------------------ shared look (the prompt uses it too)

## A tile / swatch plate: `color` fill, a ring of `border` px in `ring`, a glow when `glow` has alpha.
static func box(color: Color, radius: float, border := 0.0, ring := Color.TRANSPARENT, padding := Vector2(16.0, 10.0), glow := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.corner_detail = 10
	style.anti_aliasing = true
	if border > 0.0:
		style.set_border_width_all(int(border))
		style.border_color = ring
	if glow.a > 0.0:
		style.shadow_color = glow
		style.shadow_size = 7
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	return style

## A sub-pill on the sheet: a lighter veil with the thin light outline (the Settings rows' look).
static func pill(padding := Vector2(14.0, 4.0)) -> StyleBoxFlat:
	var style := Kit.pill_box(false, 22, 2)
	style.bg_color = Color(1, 1, 1, 0.13)
	style.border_color = Color(1, 1, 1, 0.38)
	style.shadow_size = 0
	style.content_margin_left = padding.x
	style.content_margin_right = padding.x
	style.content_margin_top = padding.y
	style.content_margin_bottom = padding.y
	return style

## Design pixels per customizer pixel: 1 on a wide screen; held upright the 1280-wide design canvas makes everything small,
## so the customizer grows to the size it has on the same phone held sideways.
static func ui_scale(view: Vector2) -> float:
	return maxf(1.0, view.x / 720.0) if view.y > view.x * 1.05 else 1.0

## The ring prompt: a gold chunky pill with a key cap ("" hides the cap: on a touch screen the pill is the button).
static func prompt_button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size = size
	button.custom_minimum_size = size
	var spec: Dictionary = Kit.role("primary")
	button.add_theme_font_override("font", Kit.font())
	button.add_theme_font_size_override("font_size", 28)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, spec.ink)
	button.add_theme_color_override("font_outline_color", spec.edge)
	button.add_theme_constant_override("outline_size", 7)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var look := Kit.style("primary", "pressed" if state == "hover_pressed" else state)
		look.content_margin_bottom = Kit.Chunk.lip(size.y) + Kit.Chunk.drop(size.y) + 4.0
		button.add_theme_stylebox_override(state, look)
	var cap := Label.new()
	cap.name = "Key"
	cap.text = "?" # set_prompt_key() fills it
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", Kit.font())
	cap.add_theme_font_size_override("font_size", 28)
	cap.add_theme_color_override("font_color", Color.WHITE)
	var cap_box := Kit.pill_box(false, 16, 2)
	cap_box.bg_color = Color(Kit.EDGE, 0.92)
	cap_box.content_margin_left = 0.0
	cap_box.content_margin_right = 0.0
	cap.add_theme_stylebox_override("normal", cap_box)
	cap.position = Vector2(18.0, (size.y - 56.0) * 0.5 - 4.0)
	cap.size = Vector2(56.0, 56.0)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(cap)
	return button

static func set_prompt_key(button: Button, key: String) -> void:
	var cap: Label = button.get_node("Key")
	if cap.text == key and button.text != "": return
	cap.text = key
	cap.visible = key != ""
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		(button.get_theme_stylebox(state) as StyleBox).content_margin_left = 90.0 if key != "" else 28.0
	button.text = "Change your look" if key != "" else "Tap: change your look"

# ------------------------------------------------------------------ the catalog's tabs

## The picker rows of a tab that the catalog has (OUTFIT also takes the slots and colour slots no tab names).
static func tab_rows(index: int) -> Array:
	var known := {}
	for slot: String in Catalog.slots(): known["item:" + slot] = true
	for slot: String in Catalog.color_slots(): known["color:" + slot] = true
	var result: Array = []
	for row: String in TABS[index].rows:
		if known.has(row): result.append(row)
	if str(TABS[index].title) == "OUTFIT":
		var named := {}
		for spec: Dictionary in TABS:
			for row: String in spec.rows: named[row] = true
		for row: String in known:
			if not named.has(row): result.append(row)
	return result

## The params whose sliders a tab shows.
static func tab_params(index: int) -> Array:
	var groups: Array = TABS[index].groups
	return Catalog.params().filter(func(entry: Dictionary) -> bool: return "*" in groups or str(entry.get("group", "")) in groups)

# ------------------------------------------------------------------ open

## Starts editing `edit_look` for `player_name`; `pad`: the owner uses a pad (the focus starts on the picked tile).
func open(edit_look, player_name: String, pad := false, owner_seat := 0) -> void:
	look = edit_look
	seat = owner_seat
	_pad = pad
	_rng.randomize()
	_build(player_name)
	get_viewport().size_changed.connect(_layout)
	_layout()
	select_tab(0)

func step_tab(step: int) -> void:
	select_tab(posmod(tab + step, TABS.size()))

func select_tab(index: int) -> void:
	tab = clampi(index, 0, TABS.size() - 1)
	for i in _tab_buttons.size(): ComicSkin.set_chosen(_tab_buttons[i], i == tab)
	_fill_page()
	_scroll.scroll_vertical = 0
	if _pad: _focus_page.call_deferred()

func randomize_all() -> void:
	_set_look(look.randomized(_rng))

func randomize_params() -> void:
	look = look.randomized_params(_rng)
	_changed()

func reset_params() -> void:
	look.params.clear() # a missing param is 0
	_changed()

# ------------------------------------------------------------------ building

func _build(player_name: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbs = Thumbs.new()
	thumbs.name = "Thumbs"
	add_child(thumbs)
	thumbs.thumb_ready.connect(_on_thumb)
	_build_view_tools()
	_build_bar()
	theme = Kit.theme()
	_sheet = PanelContainer.new()
	_sheet.name = "Sheet"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.add_theme_stylebox_override("panel", Kit.panel("sheet", 30, 22))
	add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_sheet.add_child(column)
	_name_label = Label.new()
	_name_label.name = "Player"
	_name_label.text = "PLAYER: " + player_name.to_upper()
	_name_label.add_theme_font_override("font", Kit.font())
	_name_label.add_theme_font_size_override("font_size", 40)
	_name_label.set_meta(&"comic_style", "headline")
	column.add_child(_name_label)
	ComicSkin.comicify(_name_label, 0.62, HORIZONTAL_ALIGNMENT_LEFT)
	_tab_grid = GridContainer.new()
	_tab_grid.add_theme_constant_override("h_separation", 8)
	_tab_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_tab_grid)
	ComicSkin.set_scope(_tab_grid)
	for index in TABS.size():
		var button := Button.new()
		button.name = "Tab" + str(TABS[index].title)
		button.text = str(TABS[index].title)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, maxf(_target() - 6.0, 60.0))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.set_meta(&"comic_role", "tab")
		button.pressed.connect(select_tab.bind(index))
		_tab_grid.add_child(button)
		ComicSkin.comicify(button, 0.46, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, &"tabs")
		button.clip_text = true # the lettering is drawn over it: the real text must not widen the six tabs
		_tab_buttons.append(button)
	_scroll = ScrollContainer.new()
	_scroll.name = "Page"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 12)
	_scroll.add_child(_page)

## Turn and zoom buttons under the preview: a held turn button keeps turning.
func _build_view_tools() -> void:
	_view_tools = HBoxContainer.new()
	_view_tools.name = "ViewTools"
	_view_tools.add_theme_constant_override("separation", 14)
	add_child(_view_tools)
	for spec: Array in [["TurnLeft", "left"], ["ZoomOut", "minus"], ["ZoomIn", "plus"], ["TurnRight", "right"]]:
		var button := SignButton.new()
		button.name = spec[0]
		button.sign_name = spec[1]
		button.custom_minimum_size = Vector2.ONE * _target()
		button.focus_mode = Control.FOCUS_ALL
		Kit.dress(button, "blue")
		_view_tools.add_child(button)
		match str(spec[1]):
			"minus": button.pressed.connect(func() -> void: zoom_step.emit(1.0 / 0.85))
			"plus": button.pressed.connect(func() -> void: zoom_step.emit(0.85))
			_:
				var way := -1.0 if spec[1] == "left" else 1.0
				button.button_down.connect(func() -> void: spin = way)
				button.button_up.connect(func() -> void: spin = 0.0)

func _build_bar() -> void:
	_bar = VBoxContainer.new()
	_bar.name = "Bar"
	ComicSkin.set_scope(_bar)
	_bar.add_theme_constant_override("separation", 10)
	add_child(_bar)
	for _i in 2:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_bar.add_child(row)
		_bar_rows.append(row)
	for spec: Array in [["RandomizeAll", "RANDOMIZE ALL", randomize_all], ["RandomizeParams", "RANDOMIZE PARAMS", randomize_params],
			["ResetParams", "RESET PARAMS", reset_params], ["Cancel", "CANCEL", func() -> void: cancel_pressed.emit()],
			["Confirm", "CONFIRM", func() -> void: confirm_pressed.emit()]]:
		var button := Button.new()
		button.name = spec[0]
		button.text = spec[1]
		button.custom_minimum_size = Vector2(0.0, _target())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var role := "go" if spec[0] == "Confirm" else ("danger" if spec[0] == "Cancel" else ("blue" if spec[0] == "RandomizeAll" else "plain"))
		button.set_meta(&"comic_role", role)
		button.pressed.connect(spec[2])
		ComicSkin.comicify(button, 0.46, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true, &"bar")
		button.clip_text = true
		_bar_buttons[spec[0]] = button
	_arrange_bar()

## One row on a wide screen; upright, the randomize row above CANCEL and CONFIRM.
func _arrange_bar() -> void:
	for name: String in _bar_buttons:
		var button: Button = _bar_buttons[name]
		var row := _bar_rows[1] if portrait and name in ["Cancel", "Confirm"] else _bar_rows[0]
		if button.get_parent() != row:
			if button.get_parent() != null: button.get_parent().remove_child(button)
			row.add_child(button)
	for name: String in ["RandomizeAll", "RandomizeParams", "ResetParams", "Cancel", "Confirm"]:
		var button: Button = _bar_buttons[name]
		button.get_parent().move_child(button, -1)
	_bar_rows[1].visible = portrait
	(_bar_buttons["Confirm"] as Button).size_flags_stretch_ratio = 1.4

## Touch target height (design px): 76 on phones (7 mm), a little less with a mouse.
func _target() -> float:
	return TouchControls.MIN_BUTTON_HEIGHT if TouchControls.touch_ui() else 64.0

func _tile_size() -> float:
	return 104.0 if TouchControls.touch_ui() else 96.0

func _swatch_size() -> float:
	return TouchControls.MIN_BUTTON_HEIGHT if TouchControls.touch_ui() else 60.0

func _layout() -> void:
	if _sheet == null: return
	var full := get_viewport_rect().size
	var factor := ui_scale(full)
	position = Vector2.ZERO
	scale = Vector2.ONE * factor
	size = full / factor
	var view := size
	portrait = view.y > view.x * 1.05
	_arrange_bar()
	var bar_height := _target() * (2.0 if portrait else 1.0) + (10.0 if portrait else 0.0)
	var bar_top := view.y - MARGIN - bar_height
	_bar.position = Vector2(MARGIN, bar_top)
	_bar.size = Vector2(view.x - MARGIN * 2.0, bar_height)
	var preview: Rect2
	if portrait:
		var height := clampf(view.y * 0.5, minf(560.0, bar_top - 260.0), bar_top - 300.0)
		_sheet.position = Vector2(MARGIN, bar_top - MARGIN - height)
		_sheet.size = Vector2(view.x - MARGIN * 2.0, height)
		preview = Rect2(MARGIN, MARGIN, view.x - MARGIN * 2.0, _sheet.position.y - MARGIN * 2.0)
	else:
		var width := clampf(view.x * 0.48, 560.0, 720.0)
		_sheet.position = Vector2(view.x - MARGIN - width, MARGIN)
		_sheet.size = Vector2(width, bar_top - MARGIN * 2.0)
		preview = Rect2(MARGIN, MARGIN, _sheet.position.x - MARGIN * 2.0, bar_top - MARGIN * 2.0)
	var tools := _view_tools.get_combined_minimum_size()
	_view_tools.size = tools
	_view_tools.position = Vector2(preview.get_center().x - tools.x * 0.5, preview.end.y - tools.y)
	_tab_grid.columns = TABS.size() if _sheet.size.x - 44.0 >= TABS.size() * 92.0 else 3
	# The character stands in the middle of the preview, above its buttons.
	var stage := Rect2(preview.position, Vector2(preview.size.x, preview.size.y - tools.y - 10.0))
	var middle := stage.get_center()
	layout_changed.emit(Vector2(middle.x / view.x * 2.0 - 1.0, 1.0 - middle.y / view.y * 2.0), stage.size.y / view.y)

## The tab's content: its picker rows, then its sliders.
func _fill_page() -> void:
	for child: Node in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_sliders.clear()
	_waiting.clear()
	for row: String in tab_rows(tab):
		if row.begins_with("color:"): _color_row(row.trim_prefix("color:"))
		else: _item_row(row.trim_prefix("item:"))
	var group := ""
	var titled: bool = TABS[tab].groups.size() > 1 or "*" in TABS[tab].groups or not tab_rows(tab).is_empty()
	for entry: Dictionary in tab_params(tab):
		if titled and str(entry.get("group", "")) != group:
			group = str(entry.get("group", ""))
			_heading(str(GROUP_TITLES.get(group, group.capitalize())))
		_slider_row(entry)
	_refresh()

func _heading(title: String) -> void:
	var label := Kit.label(title, 24, Kit.GOLD, 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page.add_child(label)

func _flow(title: String) -> HFlowContainer:
	_heading(title)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	_page.add_child(flow)
	return flow

func _color_row(slot: String) -> void:
	var key := "color:" + slot
	var flow := _flow(str(ROW_TITLES.get(key, slot.capitalize() + " colour")))
	_tiles[key] = {}
	var size := _swatch_size()
	var colors := Catalog.palette_for(slot)
	for index in colors.size():
		var tile := Button.new()
		tile.toggle_mode = true
		tile.custom_minimum_size = Vector2(size, size)
		tile.tooltip_text = "%s %d" % [str(ROW_TITLES.get(key, slot)), index + 1]
		var color := colors[index]
		var radius := size * 0.5
		tile.add_theme_stylebox_override("normal", box(color, radius, 3.0, Color(1, 1, 1, 0.85), Vector2.ZERO))
		tile.add_theme_stylebox_override("hover", box(color.lightened(0.12), radius, 4.0, Color.WHITE, Vector2.ZERO))
		tile.add_theme_stylebox_override("pressed", box(color, radius, 7.0, PICKED, Vector2.ZERO, Color(PICKED, 0.55)))
		tile.add_theme_stylebox_override("hover_pressed", box(color.lightened(0.12), radius, 7.0, PICKED, Vector2.ZERO, Color(PICKED, 0.55)))
		tile.add_theme_stylebox_override("focus", Kit.focus_ring(3.0, 3))
		tile.set_meta("row", key)
		tile.set_meta("value", index)
		tile.pressed.connect(_pick_color.bind(slot, index))
		flow.add_child(tile)
		_tiles[key][index] = tile

func _item_row(slot: String) -> void:
	var key := "item:" + slot
	var flow := _flow(str(ROW_TITLES.get(key, slot.capitalize())))
	_tiles[key] = {}
	flow.add_child(_item_tile(slot, {"id": "", "name": "None"}))
	for item: Dictionary in Catalog.items(slot):
		if slot == "head" or Catalog.fits(item, str(look.items.get("head", ""))): flow.add_child(_item_tile(slot, item))
	for item: Dictionary in Catalog.awards(slot): # a won item (the champion's crown): offered to its winner, and to whoever wears it, so it can come off and go back on
		if str(look.items.get(slot, "")) == str(item.get("id", "")) or Look.has_award(seat, Catalog.award_of(str(item.get("id", "")))):
			if Catalog.fits(item, str(look.items.get("head", ""))): flow.add_child(_item_tile(slot, item))

func _item_tile(slot: String, item: Dictionary) -> Button:
	var id := str(item.get("id", ""))
	var size := _tile_size()
	var tile := Button.new()
	tile.toggle_mode = true
	tile.custom_minimum_size = Vector2(size, size)
	tile.tooltip_text = str(item.get("name", id))
	tile.expand_icon = true
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.clip_text = true
	tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile.add_theme_font_override("font", Kit.font())
	tile.add_theme_font_size_override("font_size", 19)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		tile.add_theme_color_override(state, Color.WHITE if id != "" else SOFT_INK)
	tile.add_theme_color_override("font_outline_color", Kit.EDGE)
	tile.add_theme_constant_override("outline_size", 5)
	var line := Color(1, 1, 1, 0.3)
	tile.add_theme_stylebox_override("normal", box(TILE, 22.0, 2.0, line, Vector2(10.0, 10.0)))
	tile.add_theme_stylebox_override("hover", box(TILE_HOVER, 22.0, 3.0, Color(1, 1, 1, 0.7), Vector2(10.0, 10.0)))
	tile.add_theme_stylebox_override("pressed", box(TILE_PICKED, 22.0, 5.0, PICKED, Vector2(10.0, 10.0), Color(PICKED, 0.5)))
	tile.add_theme_stylebox_override("hover_pressed", box(TILE_PICKED.lightened(0.1), 22.0, 5.0, PICKED, Vector2(10.0, 10.0), Color(PICKED, 0.5)))
	tile.add_theme_stylebox_override("focus", Kit.focus_ring(4.0, 3))
	tile.text = str(item.get("name", id))
	tile.set_meta("item", item)
	_show_picture(tile)
	tile.set_meta("row", "item:" + slot)
	tile.set_meta("value", id)
	tile.pressed.connect(_pick_item.bind(slot, id))
	_tiles["item:" + slot][id] = tile
	return tile

## A param: its label, the slider (-1..1) and its value (tap: back to 0).
func _slider_row(entry: Dictionary) -> void:
	var id := str(entry.id)
	var pill_box := PanelContainer.new()
	pill_box.name = "ParamPill_" + id
	pill_box.add_theme_stylebox_override("panel", pill(Vector2(18.0, 4.0)))
	_page.add_child(pill_box)
	var row := HBoxContainer.new()
	row.name = "Param_" + id
	row.add_theme_constant_override("separation", 14)
	pill_box.add_child(row)
	var label := Kit.label(str(entry.get("label", id.capitalize())), 22, Kit.ON_DARK)
	label.custom_minimum_size = Vector2(150.0, 0.0)
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var slider := Widgets.ComicSlider.new()
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.1 # the value shows one decimal; a pad moves it a tenth per press
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0.0, maxf(_target() - 8.0, TouchControls.MIN_SLIDER_HEIGHT))
	slider.set_meta("param", id)
	slider.value_changed.connect(_set_param.bind(id))
	row.add_child(slider)
	var value := Button.new()
	value.name = "Value"
	value.custom_minimum_size = Vector2(80.0, 0.0)
	value.tooltip_text = "Back to 0"
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.text = "0.0"
	Kit.dress(value, "plain") # not lettered by ComicSkin: it lives in a scrolling page (a drawn overlay would be cut at the page's edge)
	value.add_theme_font_override("font", Kit.font())
	value.add_theme_font_size_override("font_size", 26)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		value.add_theme_color_override(state, Color.WHITE)
	value.add_theme_color_override("font_outline_color", Kit.EDGE)
	value.add_theme_constant_override("outline_size", 5)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		(value.get_theme_stylebox(state) as StyleBox).content_margin_bottom = 12.0 # the face sits above the lip
	value.pressed.connect(func() -> void: slider.value = 0.0)
	row.add_child(value)
	_sliders[id] = {"slider": slider, "value": value}

## The tile's item in the look's colours: at once when that picture exists, else when thumbs has rendered it (the tile keeps
## its last picture, or its name, until then).
func _show_picture(tile: Button) -> void:
	var item: Dictionary = tile.get_meta("item")
	if str(item.get("id", "")) == "": return
	var colors := _picture_colors()
	var name := Thumbs.key(item, colors)
	tile.set_meta("picture", name)
	var picture: Texture2D = thumbs.request(item, colors)
	if picture != null:
		tile.icon = picture
		tile.text = ""
	elif not _waiting.has(name): _waiting[name] = [tile]
	else: _waiting[name].append(tile)

## The look's colour per colour slot (the pictures show them).
func _picture_colors() -> Dictionary:
	var colors := {}
	for slot: String in Catalog.color_slots(): colors[slot] = Catalog.color(slot, int(look.colors.get(slot, 0)))
	return colors

func _on_thumb(name: String, texture: Texture2D) -> void:
	for tile: Button in _waiting.get(name, []):
		if not is_instance_valid(tile) or tile.get_meta("picture", "") != name: continue
		tile.icon = texture
		tile.text = ""
	_waiting.erase(name)

func _focus_page() -> void:
	var first: Control = null
	for control: Control in _page.find_children("*", "Control", true, false):
		if control.focus_mode == Control.FOCUS_NONE or not control.is_visible_in_tree() or (control is BaseButton and control.disabled): continue
		if not (control is BaseButton or control is Range): continue
		if first == null: first = control
		if control is Button and control.toggle_mode and control.button_pressed:
			control.grab_focus()
			return
	if first != null: first.grab_focus()

# ------------------------------------------------------------------ picking

func _pick_item(slot: String, id: String) -> void:
	look.items[slot] = id
	if slot == "head":
		var skin: Variant = Catalog.item(id).get("skin")
		if skin is int or skin is float: look.colors["skin"] = int(skin) # the skin colour that suits the head
		look = look.fitted() # face items that do not fit the new head are swapped
		var scroll := _scroll.scroll_vertical
		_fill_page() # the face rows show what fits the new head
		_scroll.set_deferred("scroll_vertical", scroll)
	_changed()

func _pick_color(slot: String, index: int) -> void:
	look.colors[slot] = index
	_changed()

func _set_param(value: float, id: String) -> void:
	look.set_param(id, value)
	_show_value(id)
	look_changed.emit(look)

func _set_look(next) -> void:
	look = next
	_fill_page()
	look_changed.emit(look)

func _changed() -> void:
	_refresh()
	look_changed.emit(look)

## Every tile shows whether the look wears it, every slider the look's value, every item picture the look's colours.
func _refresh() -> void:
	if look.colors != _shown_colors:
		_shown_colors = look.colors.duplicate()
		for key: String in _tiles:
			if not key.begins_with("item:"): continue
			for tile: Button in (_tiles[key] as Dictionary).values(): _show_picture(tile)
	for key: String in _tiles:
		var picked: Variant
		if key.begins_with("color:"): picked = int(look.colors.get(key.trim_prefix("color:"), -1))
		else: picked = str(look.items.get(key.trim_prefix("item:"), ""))
		var tiles: Dictionary = _tiles[key]
		for value: Variant in tiles:
			(tiles[value] as Button).set_pressed_no_signal(value == picked)
	for id: String in _sliders:
		(_sliders[id].slider as HSlider).set_value_no_signal(look.param(id))
		_show_value(id)

func _show_value(id: String) -> void:
	if not _sliders.has(id): return
	var text := "%.1f" % look.param(id)
	(_sliders[id].value as Button).text = "0.0" if text == "-0.0" else text

func probe() -> Dictionary:
	return {"tab": tab, "portrait": portrait, "sliders": _sliders.size(), "tiles": _tiles.size(), "look": look.to_dict() if look != null else {}}
