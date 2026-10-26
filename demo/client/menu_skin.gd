extends RefCounted
## The skin of every menu: the title page, the pause/settings sheet, results and the online screens, on the menu kit (style/menu_kit.gd, the candy menu look).
##  - Words are the kit's lettering (comic_text.gd `kit`: Lilita One, slanted, a dark outline, an extrusion on the headlines). Real Labels and
##    Buttons keep their text (probes and accessibility read it): their own glyphs are made transparent and the
##    word is drawn over them (comicify / sync_comic; the names stay from the comic look).
##  - Buttons are chunky plates (Kit.Chunk: white rim, thick bottom bevel, drop shadow; they sink when pressed and spring back). PLAY and RESUME are the big primary (pink, or the brand's colour),
##    secondary buttons the cyan plate, the chosen tab the primary. Hover lightens the plate and grows the word a little; a white ring with a dark halo marks keyboard focus.
##  - The title page: a charcoal top bar with the page's name and the tabs (Settings, Invite, Quit), the logo and the tagline chip on the left, the cast on the right, a big slanted PLAY at the foot.
const Ui := preload("res://client/friends_ui.gd")
const Kit := preload("res://style/menu_kit.gd")
const TouchControls := preload("res://client/touch_controls.gd")
const MenuStyle := preload("res://client/menu_style.gd")
const ComicText := preload("res://client/comic_text.gd")
const HudComic := preload("res://client/hud_comic.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ShowTheme := preload("res://client/show_theme.gd")

## Ink on a cream card and muted lines (the dark sheets use Kit.ON_DARK / Kit.MUTED_ON_DARK).
const INK := Kit.INK
const MUTED := Kit.INK_SOFT

static func palette() -> Dictionary:
	return {"ink": INK, "muted": MUTED, "accent": Kit.primary_color()}

static func theme() -> Theme:
	return Kit.theme()

## Wash over the screen behind the pause sheet and results (violet; lighter in a run so the world stays readable).
static func wash_color(in_game: bool) -> Color:
	return Kit.wash_color(in_game)

## Background of the Settings sheet and results panel: the violet sheet with the white rim.
static func panel_style() -> StyleBox:
	return Kit.panel("sheet")

# ------------------------------------------------------------------ lettering

const DISABLED_TINT := Color(1, 1, 1, 0.85)
## Share of its ideal height a word may shrink to (to fit its box) before it takes two lines instead.
const WRAP_FLOOR := 0.72
const SCOPE_META := &"comic_scope"
## Captions up to this many characters never wrap.
const WRAP_MIN_CHARS := 14
## The lettering of a Label by meta &"comic_style" (default "label"): fill, edge (outline), deep (extrusion; alpha 0 = none).
static func letters(style: String) -> Dictionary:
	match style:
		"headline": return {"fill": Color("ffffff"), "edge": Kit.EDGE, "deep": Kit.role("primary").lip}
		"mint": return {"fill": Color("ffffff"), "edge": Color("0b5c36"), "deep": Color("118049")}
		"muted": return {"fill": Kit.MUTED_ON_DARK, "edge": Kit.EDGE, "deep": Color(0, 0, 0, 0)}
		"ink": return {"fill": Kit.INK, "edge": Color(0, 0, 0, 0), "deep": Color(0, 0, 0, 0)}
	return {"fill": Color("ffffff"), "edge": Kit.EDGE, "deep": Color(0, 0, 0, 0)}

## One word or line in the kit's lettering at `height` (cap height, design px), left aligned, white with the dark edge. Falls back to nothing:
## the font ships with the game.
static func word(text: String, height: float, tracking := 0.0) -> Control:
	var made: Control = ComicText.make(text, height, HORIZONTAL_ALIGNMENT_LEFT, true)
	made.call("set_kit", Color("ffffff"), Kit.EDGE)
	if tracking != 0.0: made.set_tracking(tracking)
	return made

## Draws `control`'s text (a Label or Button) in the display type. The control keeps its text and its layout (and its hit
## rect): only its own glyphs go transparent. A Button gets a flat plate (see PLATES); its hover, focus and press move
## the word a little. `ratio` is the cap height as a share of the control's height; `tracking` is extra letter spacing in cap
## heights; `set_chosen` marks the current tab.
##
## One cap height per group: controls comicified with the same non-empty `group` under the same scope (the nearest
## ancestor marked with `set_scope`) share one cap height, the smallest of their ideal heights (`ratio` x control height)
## and of the height at which the widest word fits its box, so a row of buttons or tabs always letters at one size. Only
## a word that would have to shrink below WRAP_FLOOR of the ideal height may (with `wrap`) break at its middle space
## into two lines of the same cap height. A control without group or scope letters on its own. The focused word stays
## unclipped: the owner's own clipping is turned off (ComicText.unclip).
static func comicify(control: Control, ratio := 0.62, align := HORIZONTAL_ALIGNMENT_CENTER, tracking := 0.0, wrap := false, group := &"") -> void:
	if control.has_meta(&"comic"):
		# Already lettered (make_button did it): the caller only sets its own proportions.
		var state: Dictionary = control.get_meta(&"comic")
		state.ratio = ratio
		state.align = align
		state.tracking = tracking
		state.wrap = wrap
		if group != &"": state.group = group
		sync_comic(control)
		return
	var clear := Color(0, 0, 0, 0)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
		control.add_theme_color_override(key, clear)
	if control is BaseButton: _plate(control as BaseButton, str(control.get_meta(&"comic_role", "plain")))
	ComicText.unclip(control)
	var overlay := Control.new()
	overlay.name = "ComicOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.clip_contents = false
	control.add_child(overlay)
	control.set_meta(&"comic", {"overlay": overlay, "ratio": ratio, "align": align, "tracking": tracking, "wrap": wrap, "chosen": -1, "lit": false, "key": "", "group": group, "cap": 0.0})
	control.resized.connect(sync_comic.bind(control))
	control.draw.connect(_poll.bind(control))
	control.visibility_changed.connect(_regroup.bind(control))
	if control is BaseButton:
		var button := control as BaseButton
		button.button_down.connect(_press.bind(control, true))
		button.button_up.connect(_press.bind(control, false))
	sync_comic(control)

## Marks the container whose comicified descendants may share cap heights (see comicify `group`).
static func set_scope(container: Control) -> void:
	container.set_meta(SCOPE_META, true)

## A Button's chunky plate for `role` (Kit.roles(): primary, go, danger, blue, plain, tab, chosen): rim, bevel, drop shadow, the focus ring, the springy press.
static func _plate(button: BaseButton, role: String) -> void:
	Kit.dress(button, role)

## Marks a comicified control as the chosen one of a set (tabs): the primary's plate; the others stay the same size in light violet.
## Controls never passed here are not part of a set.
static func set_chosen(control: Control, chosen: bool) -> void:
	if not control.has_meta(&"comic"): return
	var state: Dictionary = control.get_meta(&"comic")
	state.chosen = 1 if chosen else 0
	if control is BaseButton:
		control.set_meta(&"comic_role", "chosen" if chosen else "tab")
		_plate(control as BaseButton, "chosen" if chosen else "tab")
	sync_comic(control)

static func _words(control: Control) -> Array[Control]:
	var result: Array[Control] = []
	if not control.has_meta(&"comic"): return result
	var overlay: Control = (control.get_meta(&"comic") as Dictionary).overlay
	for child: Node in overlay.get_children():
		if child is Control: result.append(child as Control)
	return result

static func _key(control: Control, state: Dictionary) -> String:
	return "%s|%d|%d|%s|%d" % [control.get("text"), roundi(control.size.x), roundi(control.size.y), control is BaseButton and (control as BaseButton).disabled, state.chosen]

## Runs on every redraw of the control (text, disabled and hover/focus changes all redraw a Button).
static func _poll(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta(&"comic"): return
	var state: Dictionary = control.get_meta(&"comic")
	if _key(control, state) != state.key: sync_comic(control)
	if control is BaseButton:
		var button := control as BaseButton
		var lit := not button.disabled and int(state.chosen) == 0 and (button.has_focus() or button.is_hovered()) # a chosen tab is already marked
		if lit != state.lit:
			state.lit = lit
			for item in _words(control):
				if item.has_method("set_focus"): item.call("set_focus", lit)

static func _press(control: Control, down: bool) -> void:
	for item in _words(control):
		if item.has_method("set_press"): item.call("set_press", down)

## Re-reads the control's text and size into its lettering, at the cap height its group agrees on (see comicify).
static func sync_comic(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta(&"comic"): return
	var state: Dictionary = control.get_meta(&"comic")
	var overlay: Control = state.overlay
	state.key = _key(control, state)
	_clear(overlay)
	var text := str(control.get("text"))
	var area := control.size
	if area.x < 4.0 or area.y < 4.0 or text == "": return
	var chosen := int(state.chosen)
	var members := _members(control, state)
	var plan := _plan(members)
	var cap: float = plan.cap
	var lines: Array[String] = [text]
	if plan.wraps.get(control.get_instance_id(), false): lines = _split(text)
	var made: Array[Control] = []
	for line in lines: made.append(word(line, cap, float(state.tracking)))
	state.cap = cap
	var gap := cap * 0.32
	var block := cap * made.size() + gap * (made.size() - 1)
	# A plate's words sit on its face (above the lip and the shadow); a Label's on its middle.
	var plated := control is BaseButton and control.get_theme_stylebox("normal") is Kit.Chunk
	var middle := Kit.Chunk.face_middle(area.y) if plated else area.y * 0.5
	var top := middle - block * 0.5
	var tint := Color.WHITE
	var spec := {}
	if control is BaseButton:
		spec = Kit.DISABLED if (control as BaseButton).disabled else Kit.role(str(control.get_meta(&"comic_role", "plain")))
		spec = {"fill": spec.ink, "edge": spec.edge, "deep": spec.deep}
	else: spec = letters(str(control.get_meta(&"comic_style", "label")))
	for index in made.size():
		var item: Control = made[index]
		var fitted := item.custom_minimum_size
		var x := 0.0
		match int(state.align):
			HORIZONTAL_ALIGNMENT_CENTER: x = (area.x - fitted.x) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT: x = area.x - fitted.x
		item.size = fitted
		item.position = Vector2(x, top + (cap + gap) * index)
		if item.has_method("set_tint"): item.call("set_tint", tint)
		item.call("set_kit", spec.fill, spec.edge, spec.deep)
		if plated: item.set("press_drop", Kit.Chunk.lip(area.y) * 0.8)
		if bool(state.lit) and chosen != 1 and item.has_method("set_focus"): item.call("set_focus", true, false)
		overlay.add_child(item)
	# The others of the group follow when this word changed what the group agrees on.
	if not _syncing:
		_syncing = true
		for other in members:
			if other != control and absf(float((other.get_meta(&"comic") as Dictionary).cap) - cap) > 0.05: sync_comic(other)
		_syncing = false

static var _syncing := false

## Comicified controls of the same group and scope that are on screen, plus `control` itself when it is (or when it is
## the only one). Words that are hidden or have no size yet take no part in the group's decision.
static func _members(control: Control, state: Dictionary) -> Array[Control]:
	var result: Array[Control] = []
	if control.is_visible_in_tree() or state.group == &"": result.append(control)
	if state.group == &"": return result
	var scope: Control = control
	while scope != null and not scope.has_meta(SCOPE_META):
		scope = scope.get_parent() as Control
	if scope == null:
		if result.is_empty(): result.append(control)
		return result
	for node: Node in scope.find_children("*", "Control", true, false):
		if node == control or not node.has_meta(&"comic"): continue
		var other := node as Control
		var other_state: Dictionary = other.get_meta(&"comic")
		if other_state.group != state.group or not other.is_visible_in_tree(): continue
		if other.size.x < 4.0 or other.size.y < 4.0 or str(other.get("text")) == "": continue
		result.append(other)
	if result.is_empty(): result.append(control)
	return result

## One cap height for the group and which members break into two lines. Ideal height of a member is its height x ratio;
## the group takes the smallest, then shrinks (never one word alone) until the widest single-line word fits its box.
## Only a long caption (more than WRAP_MIN_CHARS characters, a space, `wrap` set) may take two lines instead, and only
## when fitting on one line would cost more than WRAP_FLOOR of the ideal height; the lines then keep the group's height.
## Short labels ("TEST PEER: OFF", "< CHECKPOINT") never wrap: the whole group gets smaller instead.
static func _plan(members: Array[Control]) -> Dictionary:
	var ideal := INF
	for member in members:
		var state: Dictionary = member.get_meta(&"comic")
		ideal = minf(ideal, member.size.y * float(state.ratio))
	var floor_cap := ideal * WRAP_FLOOR
	var cap := ideal
	var wraps := {}
	var may_wrap: Array[Dictionary] = []   # {member, single}
	for member in members:
		var state: Dictionary = member.get_meta(&"comic")
		var text := str(member.get("text"))
		var wide := member.size.x * 0.9
		var single: float = wide / float(ComicText.unit_width(text, float(state.tracking), true))
		if bool(state.wrap) and text.length() > WRAP_MIN_CHARS and text.contains(" "): may_wrap.append({"member": member, "single": single})
		else: cap = minf(cap, single)
	# Long captions, widest-fitting first: one line while it costs at most WRAP_FLOOR of the ideal height, else two lines.
	may_wrap.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.single > b.single)
	for entry in may_wrap:
		var member: Control = entry.member
		var single: float = entry.single
		if single >= cap:
			continue
		if single >= floor_cap:
			cap = single
			continue
		var state: Dictionary = member.get_meta(&"comic")
		var lines := _split(str(member.get("text")))
		var tracking := float(state.tracking)
		var longest := maxf(float(ComicText.unit_width(lines[0], tracking, true)), float(ComicText.unit_width(lines[1], tracking, true)))
		cap = minf(cap, minf(member.size.x * 0.9 / longest, member.size.y * 0.9 / 2.32))
		wraps[member.get_instance_id()] = true
	return {"cap": cap, "wraps": wraps}

## The group's members changed (one was shown or hidden): everybody visible re-reads the group.
static func _regroup(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta(&"comic"): return
	var state: Dictionary = control.get_meta(&"comic")
	sync_comic(control)
	if state.group == &"" or _syncing: return
	_syncing = true
	for other in _members(control, state):
		if other != control: sync_comic(other)
	_syncing = false

## Two balanced lines: break at the space nearest the middle.
static func _split(text: String) -> Array[String]:
	var best := -1
	for index in text.length():
		if text[index] == " " and (best < 0 or absi(index - text.length() / 2) < absi(best - text.length() / 2)): best = index
	return [text.substr(0, best), text.substr(best + 1)] as Array[String]

static func _clear(overlay: Control) -> void:
	for child: Node in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()

# ------------------------------------------------------------------ title page

## Title page, design units of a 2160-high layer (scaled to the window): hit rect heights and cap-height share of each word.
## 234 units = 7 mm on a 6.8" 2400x1080 phone, which is the smallest hit area allowed.
const DESIGN_H := 2160.0
const PLAY_HEIGHT := 330.0
const ITEM_HEIGHT := 234.0
const PLAY_CAP := 0.56
const ITEM_CAP := 0.46

static func _body_label(value: String, font_size: int, _weight := 800) -> Label:
	var result := Kit.label(value, font_size, Kit.ON_DARK)
	return result

## The show logo: the team's title in big outlined type (TeamCast.title(): team.title, else the team name) and the second part of the title (after a colon, or the balanced second line of a
## long one) in its smaller line on a chip under the name; it pops in and then bobs. A Control: `fit(width)` sizes it.
static func logo_control(width: float) -> Control:
	var words := Kit.logo_words()
	if str(words[1]) == "":
		var lines := title_lines(TeamCast.title())
		if lines.size() == 2: words = [lines[0], lines[1]]
	var mark := Kit.logo_mark(str(words[0]), str(words[1]))
	mark.name = "Title"
	mark.fit(width)
	return mark

## The title as one line, or as two when two lines make the letters clearly bigger (split at the space that balances them best).
static func title_lines(text: String) -> PackedStringArray:
	var one: float = ComicText.unit_width(text)
	var best := PackedStringArray([text])
	var widest := one
	var words := text.split(" ", false)
	for cut in range(1, words.size()):
		var first := " ".join(words.slice(0, cut))
		var second := " ".join(words.slice(cut))
		var wide := maxf(ComicText.unit_width(first), ComicText.unit_width(second))
		if wide < widest:
			widest = wide
			best = PackedStringArray([first, second])
	return best if best.size() == 1 or widest < one * 0.7 else PackedStringArray([text])


## The tagline on a cyan chip with the white rim.
static func caption_strip(value: String, font_size: int) -> Control:
	var strip := PanelContainer.new()
	strip.name = "Tagline"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Kit.pill_box(false, 80, 6)
	box.content_margin_left = 64
	box.content_margin_right = 64
	box.content_margin_top = 22
	box.content_margin_bottom = 22
	strip.add_theme_stylebox_override("panel", box)
	var label := Kit.label(value, font_size, Kit.ON_DARK, maxi(roundi(font_size * 0.1), 3))
	label.name = "TaglineText"
	strip.add_child(label)
	return strip

## The team's name on a cyan slab with a crown, at the title's foot left (the lobby's name plate): a drawn Control.
class TeamChip extends Control:
	var words := ""

	func _init(team_name := "") -> void:
		words = team_name
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := size.y
		Kit.slab(self, Rect2(Vector2.ZERO, size), Kit.CHIP, Color.WHITE, h * 0.045, 0.1, -1.0, 1.0)
		ShowTheme.crown(self, Vector2(h * 0.62, h * 0.7), h * 0.42, ShowTheme.YELLOW, Color("7c2d0a"), 1.0, -0.2)
		var fs := h * 0.46
		var room := size.x - h * 1.25 - h * 0.3
		var wide := ShowTheme.width(words, fs) * (1.0 + ShowTheme.SLANT * 0.1)
		if wide > room: fs *= room / wide
		ShowTheme.text(self, words, Vector2(h * 1.12, h * 0.5), fs, Color.WHITE, Kit.EDGE, fs * 0.16, Color(0, 0, 0, 0), 0.0, 1.0, 0.0, ShowTheme.SLANT, 1.0, HORIZONTAL_ALIGNMENT_LEFT)

## Heights of the title page's top bar and its tabs, design units (a 2160-high layer): a phone's are thumb-sized (the tabs 234 units = 7 mm).
const BAR_HEIGHT := 250.0
const BAR_HEIGHT_TOUCH := 300.0
const TAB_HEIGHT := 170.0
const TAB_CAP := 0.5
## PLAY's lean (the plate's shear) and how far it runs off the right edge of the screen.
const PLAY_SLANT := 0.2
const PLAY_BLEED := 170.0

## The title page over the backdrop (the page's yellow rings and the cast on its cushion): a charcoal top bar (the page's name on the left, the tabs Settings / Invite / Quit in the middle, the play note
## chip on the right), the logo and the tagline chip on the left, a big slanted pink PLAY at the foot right with the play note's line over it. Buttons are real Buttons named by action key (Play, Settings, Invite, Quit).
static func build_main_menu(root: Control, actions: Dictionary) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var activate: Callable = root.get_meta("activate", Callable())
	var layer := Control.new()
	layer.name = "ComicLayer"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layer)
	var left := VBoxContainer.new()
	left.name = "ComicColumn"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 48)
	layer.add_child(left)
	var mark := logo_control(1500.0)
	mark.name = "Wordmark"
	left.add_child(mark)
	var tagline_row := HBoxContainer.new()
	tagline_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tagline_row)
	var tagline := caption_strip(TeamCast.tagline(), 70)
	tagline_row.add_child(tagline)

	# The top bar: its band, the page's name, the tabs, the play note's chip.
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", Kit.bar_box())
	layer.add_child(bar)
	var bar_name := Kit.label("MAIN MENU", 96, Kit.ON_DARK, 8)
	bar_name.name = "BarTitle"
	bar_name.set_meta(&"comic_style", "label")
	layer.add_child(bar_name)
	comicify(bar_name, 0.34, HORIZONTAL_ALIGNMENT_LEFT)
	var team_chip := TeamChip.new(TeamCast.team_name().to_upper())
	team_chip.name = "TeamChip"
	layer.add_child(team_chip)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override("separation", 36)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	set_scope(tabs)
	layer.add_child(tabs)
	var entries: Array[Button] = []
	var secondary: Array = [["Settings", "SETTINGS"]]
	if actions.get("Invite") is Callable and actions["Invite"].is_valid(): secondary.append(["Invite", "INVITE A FRIEND"])
	# Phones leave through the system; a Quit button there only closes the app by surprise.
	if not TouchControls.touch_ui(): secondary.append(["Quit", "QUIT"])
	for entry: Array in secondary:
		var tab := _item(entry[0], entry[1], false, actions, activate)
		tab.custom_minimum_size = Vector2(0, TAB_HEIGHT if not TouchControls.touch_ui() else ITEM_HEIGHT)
		tabs.add_child(tab)
		entries.append(tab)
		comicify(tab, TAB_CAP, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, &"secondary")
	var note_text := str(root.get_meta("play_note", ""))
	var play := _item("Play", "PLAY", true, actions, activate)
	play.set_meta(&"kit_slant", PLAY_SLANT)
	play.custom_minimum_size = Vector2(1500.0, PLAY_HEIGHT)
	layer.add_child(play)
	comicify(play, PLAY_CAP)
	if note_text != "":
		var note := Kit.label(note_text, 70, Kit.ON_DARK, 9)
		note.name = "PlayNote"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.set_meta(&"comic_style", "label")
		layer.add_child(note)
		comicify(note, 0.55, HORIZONTAL_ALIGNMENT_CENTER)
	entries.insert(0, play)
	for index in entries.size():
		var item := entries[index]
		var next := entries[wrapi(index + 1, 0, entries.size())]
		var previous := entries[wrapi(index - 1, 0, entries.size())]
		if item == play:
			play.focus_neighbor_top = play.get_path_to(entries[1])
			play.focus_neighbor_left = play.get_path_to(entries[entries.size() - 1])
			play.focus_neighbor_right = play.get_path_to(play)
			play.focus_neighbor_bottom = play.get_path_to(play)
		else:
			item.focus_neighbor_bottom = item.get_path_to(play)
			item.focus_neighbor_top = item.get_path_to(item)
			item.focus_neighbor_left = item.get_path_to(previous if previous != play else entries[entries.size() - 1])
			item.focus_neighbor_right = item.get_path_to(next if next != play else entries[1])
	var fit := func() -> void: _fit(root, layer)
	root.resized.connect(fit)
	fit.call_deferred()
	layer.modulate.a = 0.0
	var fade := Ui.tween(layer)
	fade.tween_property(layer, "modulate:a", 1.0, 0.35)

static func _fit(root: Control, layer: Control) -> void:
	if not is_instance_valid(root) or root.size.y <= 0.0 or root.size.x <= 0.0: return
	var factor := root.size.y / DESIGN_H
	layer.scale = Vector2.ONE * factor
	layer.size = root.size / factor
	var wide := layer.size.x
	var bar_high := BAR_HEIGHT_TOUCH if TouchControls.touch_ui() else BAR_HEIGHT
	var bar: Control = layer.get_node_or_null("TopBar")
	if bar != null:
		bar.position = Vector2.ZERO
		bar.size = Vector2(wide, bar_high)
	var bar_name: Label = layer.get_node_or_null("BarTitle")
	if bar_name != null:
		bar_name.size = Vector2(900.0, bar_high)
		bar_name.position = Vector2(wide * 0.05, 0.0)
		bar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tabs: Control = layer.get_node_or_null("Tabs")
	if tabs != null:
		var tab_high := ITEM_HEIGHT if TouchControls.touch_ui() else TAB_HEIGHT
		var tab_width := 640.0
		var count := tabs.get_child_count()
		tabs.size = Vector2(tab_width * count + 36.0 * (count - 1), tab_high)
		tabs.position = Vector2((wide - tabs.size.x) * 0.5 + wide * 0.04, (bar_high - tab_high) * 0.5 - 6.0)
		for node: Node in tabs.get_children():
			if node is Button: node.custom_minimum_size = Vector2(tab_width, tab_high)
	var left: Control = layer.get_node_or_null("ComicColumn")
	var column_width := minf(1500.0, wide * 0.4)
	if left != null:
		left.position = Vector2(wide * 0.05, bar_high + DESIGN_H * 0.07)
		left.size = Vector2(column_width, DESIGN_H * 0.5)
		var mark: Control = left.get_node_or_null("Wordmark")
		if mark != null: mark.call("fit", column_width)
	var chip: Control = layer.get_node_or_null("TeamChip")
	if chip != null:
		chip.size = Vector2(minf(900.0, wide * 0.24), 210.0)
		chip.position = Vector2(wide * 0.05, DESIGN_H - 210.0 - DESIGN_H * 0.07)
		chip.queue_redraw()
	var play: Control = layer.get_node_or_null("Play")
	var play_wide := minf(1800.0, wide * 0.42)
	var play_at := Vector2(wide - play_wide + PLAY_BLEED, DESIGN_H - PLAY_HEIGHT - DESIGN_H * 0.07)
	if play != null:
		play.custom_minimum_size = Vector2(play_wide, PLAY_HEIGHT)
		play.position = play_at
		play.size = Vector2(play_wide, PLAY_HEIGHT)
	var note: Label = layer.get_node_or_null("PlayNote")
	if note != null:
		note.size = Vector2(play_wide, 110.0)
		note.position = Vector2(play_at.x, play_at.y - 130.0)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## A real Button: flat plate and display type. Mouse hover and keyboard/pad focus are one thing here (the hovered word
## takes focus), so a single lit state shows both.
static func _item(key: String, caption: String, primary: bool, actions: Dictionary, activate: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = caption
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(0, PLAY_HEIGHT if primary else ITEM_HEIGHT)
	button.set_meta(&"comic_role", "primary" if primary else "plain")
	button.focus_entered.connect(func() -> void: Ui.play(button, &"hover"))
	button.mouse_entered.connect(func() -> void: if not button.disabled and button.focus_mode != Control.FOCUS_NONE: button.grab_focus())
	var supported: bool = actions.get(key) is Callable and actions[key].is_valid()
	button.disabled = not supported
	if supported and activate.is_valid():
		button.pressed.connect(activate.bind(key))
		button.pressed.connect(func() -> void: Ui.play(button, &"start" if primary else &"click"))
	return button

## Small lines that sit straight on the backdrop (overline, run status, notes): ink, no outline.
static func legible(label: Label, ink := Kit.ON_DARK) -> void:
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_outline_color", Kit.EDGE)
	label.add_theme_constant_override("outline_size", 6)
