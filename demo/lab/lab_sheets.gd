extends CanvasLayer
## The lab's words over the world, all in the clean UI kit: the level clock, the help sheet (keys, and keys with the stop list), the
## toast line, the typed stop number and the pause sheet (RESUME, < Level, Level >, Respawn, Restart, the stop list as buttons).
## Laid out on a 1280 x 720 design stage that scales to the window.
const Ui = preload("res://client/friends_ui.gd")
const ComicText = preload("res://client/comic_text.gd")
const ComicSkin = preload("res://client/menu_skin.gd")
const HudComic = preload("res://client/hud_comic.gd")
const LevelRun = preload("res://levels/level_run.gd")
const DESIGN := Vector2(1280, 720)
const TOAST_SECONDS := 4.0
const HELP_AT := Vector2(24, 100)
const STOPS_PER_COLUMN := 12

var lab
var stage: Control
var clock_word: ComicText
var toast_label: Label
var digits_label: Label
var help_keys: PanelContainer
var help_stops: PanelContainer
var pause_root: Control
var pause_title: ComicText
var pause_name: Label
var pause_buttons := {}
var stop_buttons: Array[Button] = []
var _toast_left := 0.0
var _help_sig := ""
var _stops_sig := ""

func configure(owner_lab) -> void:
	lab = owner_lab
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Ui.theme()
	root.resized.connect(_layout.bind(root))
	add_child(root)
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = DESIGN
	root.add_child(stage)
	clock_word = HudComic.word("0:00.0", 46.0, HORIZONTAL_ALIGNMENT_LEFT)
	clock_word.set_tabular(true)
	clock_word.position = Vector2(34, 30)
	stage.add_child(clock_word)
	toast_label = HudComic.small("", 26)
	toast_label.visible = false
	stage.add_child(toast_label)
	digits_label = HudComic.small("", 26)
	digits_label.visible = false
	stage.add_child(digits_label)
	help_keys = Ui.panel(Ui.PAPER, 14)
	help_keys.visible = false
	help_keys.position = HELP_AT
	stage.add_child(help_keys)
	help_stops = Ui.panel(Ui.PAPER, 14)
	help_stops.visible = false
	stage.add_child(help_stops)
	_build_pause()
	_layout(root)

func _layout(root: Control) -> void:
	if stage == null or root.size.x <= 0.0 or root.size.y <= 0.0: return
	var factor := minf(root.size.x / DESIGN.x, root.size.y / DESIGN.y)
	stage.scale = Vector2.ONE * factor
	stage.position = (root.size - DESIGN * factor) * 0.5

func toast(text: String) -> void:
	toast_label.text = text
	_toast_left = TOAST_SECONDS

# ------------------------------------------------------------------ per frame

func refresh(delta: float) -> void:
	var live: bool = lab.lab_ready and not lab.pause_open
	clock_word.visible = live
	if live: HudComic.update(clock_word, LevelRun.format_time(lab.elapsed), 46.0)
	_toast_left = maxf(_toast_left - delta, 0.0)
	toast_label.visible = live and _toast_left > 0.0
	if toast_label.visible:
		toast_label.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)
		toast_label.size = Vector2.ZERO
		toast_label.position = Vector2((DESIGN.x - toast_label.get_minimum_size().x) * 0.5, 640.0)
	var typing: bool = live and lab.digits != ""
	digits_label.visible = typing
	if typing:
		digits_label.text = "Stop number: %s_   (Enter = go)" % lab.digits
		digits_label.size = Vector2.ZERO
		digits_label.position = Vector2((DESIGN.x - digits_label.get_minimum_size().x) * 0.5, 590.0)
	var help: bool = live and lab.help_mode > 0
	help_keys.visible = help
	help_stops.visible = help and lab.help_mode == 2
	if help: _refresh_help()
	if lab.pause_open: _refresh_pause()

# ------------------------------------------------------------------ help sheet

func _refresh_help() -> void:
	var sig := "%d|%s|%s" % [lab.help_mode, lab.fly, lab.god]
	if sig != _help_sig:
		_help_sig = sig
		_fill_keys()
	if lab.help_mode == 2:
		var stops_sig := "%d|%d" % [lab.stop, lab.stops.size()]
		if stops_sig != _stops_sig:
			_stops_sig = stops_sig
			_fill_stops()
		help_stops.position = HELP_AT + Vector2(help_keys.size.x + 14.0, 0.0)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _key_row(keys: Array, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caps := HBoxContainer.new()
	caps.add_theme_constant_override("separation", 4)
	caps.custom_minimum_size.x = 128.0
	caps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key: String in keys:
		var cap := ComicText.keycap(key, 26.0)
		caps.add_child(cap)
	row.add_child(caps)
	var label := Ui.label(text, 17, Ui.INK)
	label.add_theme_font_override("font", Ui.BOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row

func _fill_keys() -> void:
	_clear(help_keys)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_keys.add_child(column)
	var head := ComicText.make("KEYS", 30.0, HORIZONTAL_ALIGNMENT_LEFT)
	column.add_child(head)
	var count: int = lab.stops.size()
	var rows := [
		[["W", "A", "S", "D"], "move"],
		[["MOUSE"], "look"],
		[["SPACE"], "jump"],
		[["ESC"], "pause sheet, stops"],
		[["R"], "restart the level"],
		[["[", "]"], "previous / next stop (PgUp PgDn)"],
		[["1-%d" % count], "type a stop number"],
		[["N"], "fly: %s (Space/C up/down, Shift)" % ("ON" if lab.fly else "off")],
		[["G"], "no-death: %s" % ("ON" if lab.god else "off")],
		[["H"], "help: keys / + stops / hidden"],
	]
	for row: Array in rows: column.add_child(_key_row(row[0], str(row[1])))
	help_keys.size = Vector2.ZERO

func _fill_stops() -> void:
	_clear(help_stops)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_stops.add_child(column)
	column.add_child(ComicText.make("STOPS", 30.0, HORIZONTAL_ALIGNMENT_LEFT))
	var columns := HBoxContainer.new() ## twelve stops to a column
	columns.add_theme_constant_override("separation", 18)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(columns)
	var list: VBoxContainer
	for index in lab.stops.size():
		if index % STOPS_PER_COLUMN == 0:
			list = VBoxContainer.new()
			list.add_theme_constant_override("separation", 1)
			list.mouse_filter = Control.MOUSE_FILTER_IGNORE
			columns.add_child(list)
		var here: bool = index == lab.stop
		var label := Ui.label(("> " if here else "   ") + str(lab.stops[index].name), 18, Ui.RED_DARK if here else Ui.INK)
		label.add_theme_font_override("font", Ui.BOLD)
		list.add_child(label)
	help_stops.size = Vector2.ZERO

# ------------------------------------------------------------------ pause sheet

func _button(text: String, handler: Callable, primary := false, height := 52.0) -> Button:
	var drawn := Ui.button(text, primary, true)
	drawn.custom_minimum_size.y = height
	drawn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawn.set_meta(&"comic_role", "primary" if primary else "plain")
	ComicSkin.comicify(drawn, 0.5, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, &"primary" if primary else &"buttons")
	drawn.pressed.connect(handler)
	return drawn

func _build_pause() -> void:
	pause_root = Control.new()
	pause_root.name = "PauseSheet"
	pause_root.size = DESIGN
	pause_root.visible = false
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.add_child(pause_root)
	var wash := ColorRect.new()
	wash.color = Color(Ui.PAPER, 0.8)
	wash.position = Vector2(-2000, -2000)
	wash.size = DESIGN + Vector2(4000, 4000)
	wash.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.add_child(wash)
	var side := VBoxContainer.new()
	side.name = "PauseColumn"
	side.position = Vector2(64, 0)
	side.size = Vector2(340, DESIGN.y)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	ComicSkin.set_scope(side)
	pause_root.add_child(side)
	pause_name = Ui.overline("", Ui.BLUE_DEEP, 17)
	pause_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(pause_name)
	pause_title = ComicText.make("PAUSED", 84.0, HORIZONTAL_ALIGNMENT_CENTER)
	side.add_child(pause_title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	side.add_child(gap)
	var resume := _button("RESUME", func() -> void: lab.set_pause(false), true, 70.0)
	side.add_child(resume)
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 8)
	side.add_child(stepper)
	stepper.add_child(_button("< Level", func() -> void:
		lab.set_pause(false)
		lab.travel_step(-1)))
	stepper.add_child(_button("Level >", func() -> void:
		lab.set_pause(false)
		lab.travel_step(1)))
	side.add_child(_button("Respawn", func() -> void:
		lab.set_pause(false)
		lab.respawn()))
	side.add_child(_button("Restart level", func() -> void:
		lab.set_pause(false)
		lab.restart()))
	pause_buttons = {"resume": resume}
	var sheet := Ui.panel(Ui.WHITE, 20)
	sheet.name = "StopSheet"
	sheet.position = Vector2(440, 44)
	sheet.size = Vector2(776, 632)
	pause_root.add_child(sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	sheet.add_child(column)
	var head := Ui.overline("Go to a stop", Ui.MUTED, 16)
	column.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Stops"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	ComicSkin.set_scope(grid)

func set_pause(open: bool) -> void:
	pause_root.visible = open
	if not open: return
	_build_stop_buttons()
	_refresh_pause()
	pause_buttons.resume.grab_focus.call_deferred()

func _build_stop_buttons() -> void:
	var grid: GridContainer = pause_root.find_child("Stops", true, false)
	_clear(grid)
	stop_buttons.clear()
	for index in lab.stops.size():
		var button := _button(str(lab.stops[index].name), func() -> void:
			lab.set_pause(false)
			lab.travel(index), false, 42.0)
		grid.add_child(button)
		stop_buttons.append(button)

func _refresh_pause() -> void:
	pause_name.text = "Stop %d of %d" % [lab.stop + 1, lab.stops.size()]
	for index in stop_buttons.size():
		ComicSkin.set_chosen(stop_buttons[index], index == lab.stop)

func probe() -> Dictionary:
	return {"pause": pause_root.visible, "help_keys": help_keys.visible, "help_stops": help_stops.visible, "toast": toast_label.text if toast_label.visible else "",
		"clock": clock_word.text, "stop_buttons": stop_buttons.size()}
