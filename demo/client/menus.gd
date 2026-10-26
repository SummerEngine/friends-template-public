extends CanvasLayer
const _DevLap := preload("res://dev_env.gd")
## FRIENDS pause and Settings. The overlay never pauses simulation or
## authority time. Settings values, persistence and handlers live in
## settings.gd; this only lays them out and animates them.
signal back_to_main
signal restart_requested
signal end_run_requested
signal pause_changed(open: bool)
signal setting_changed(key: String, value: Variant)
const Ui = preload("res://client/friends_ui.gd")
const Widgets = preload("res://client/friends_widgets.gd")
const Settings = preload("res://client/settings.gd")
const ComicSkin = preload("res://client/menu_skin.gd")
const Kit = preload("res://style/menu_kit.gd")
const HudParts = preload("res://client/hud_comic_parts.gd")
const TeamCast = preload("res://style/team_cast.gd")
const DESIGN := Vector2(1280, 720)
const TABS := ["Display", "Gameplay", "Audio"]
const GROUPS := [
	["Fullscreen","Resolution","Vsync","MaxFPS","Quality","Palette","TouchControls","TouchLook"],
	["XSensitivity","YSensitivity","InvertX","InvertY"],
	["MasterVolume","MusicVolume","EffectsVolume","VoiceVolume"]]
const LABELS := {"Fullscreen":"Display mode","Resolution":"Resolution","Vsync":"VSync","MaxFPS":"Frame limit",
	"XSensitivity":"Look speed · horizontal","YSensitivity":"Look speed · vertical","InvertX":"Invert horizontal look","InvertY":"Invert vertical look",
	"MasterVolume":"Master volume","MusicVolume":"Music volume","EffectsVolume":"Effects volume","VoiceVolume":"Voice volume","Quality":"Graphics quality","Palette":"Colour palette","TouchControls":"Touch controls","TouchLook":"Touch look speed"}
var settings = Settings.new()
var settings_inputs: Dictionary = {}
var settings_root: Control
var viewport_root: Control
var pause: Control
var pause_open := false
## Optional pause header: `overline` is the small word above PAUSED (Lobby, Practice, Singleplayer).
var status_provider: Callable
## What the one pause menu offers in this mode (set by the owner, read when it opens):
## Restart from checkpoint only where the mode has one; the way out is "Main menu"
## offline and "Leave match" online.
var restart_available := false
## "End run": only inside a level run (time attack / endless); the run stops after the level it is on and the results page follows.
var end_run_available := false
var leave_text := "Main menu"
## Offline modes stop the simulation while the pause menu is open; online cannot.
var pause_tree := false
var _design: Control
var _wash: ColorRect
var _pause_panel: PanelContainer
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _gameplay_empty: Label
var _selected_tab := 0
var _in_game := true
var _pause_title: Label
var _pause_over_pill: PanelContainer
var _sky: Control
var _pause_over: Label
var _pause_status: Label
var _pause_column: VBoxContainer
const TITLE_SIZE := 84
const TITLE_SIZE_COMPACT := 48
## Tallest the left pause column's content may be (design px, centred in the 720 canvas) before its heading gives up room.
const PAUSE_CONTENT_MAX := 634.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # the pause menu works while the tree is paused
	Settings.TouchControls.fit_ui(get_tree()) # phones: thumb-sized buttons (no-op on a desktop)
	# Above the HUD and the route-overview hint (110) so pause covers them.
	layer = 120
	settings.initialize()
	viewport_root = Control.new()
	viewport_root.theme = ComicSkin.theme()
	viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_root)
	var blur := ColorRect.new()
	blur.material = ShaderMaterial.new()
	blur.material.shader = preload("res://client/blur.gdshader")
	blur.material.set_shader_parameter("strength", 3.0)
	blur.mouse_filter = Control.MOUSE_FILTER_STOP
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_root.add_child(blur)
	# From the title there is no world to show through: the rings page sits under the wash (show_pause picks the page).
	_sky = SkyPage.new()
	viewport_root.add_child(_sky)
	_wash = ColorRect.new()
	_wash.color = Kit.wash_color(true)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_root.add_child(_wash)
	_design = Control.new()
	_design.name = "FriendsDesign"
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.size = DESIGN
	viewport_root.add_child(_design)
	viewport_root.visible = false
	_layout()

static func clock_text(seconds: float) -> String:
	var whole := maxi(int(seconds), 0)
	if whole >= 3600: return "%d:%02d:%02d" % [whole / 3600, whole / 60 % 60, whole % 60]
	return "%02d:%02d" % [whole / 60, whole % 60]

func _column(parent: Node, separation := 16) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",separation)
	parent.add_child(box)
	return box

## Buttons sit inside a named wrapper: callers reach them by find_child(name).get_child(0).
func _button(parent: Node, node_name: String, text: String, handler: Callable, role := "plain") -> Button:
	var wrapper := HBoxContainer.new()
	wrapper.name = node_name
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrapper)
	var button := make_button(text,role == "primary",true,role)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(button)
	button.pressed.connect(handler)
	return button

## One action button for every sheet and for owners that add rows (the lab's Practice box): a chunky kit plate (`role`: primary gold, plain dark pill,
## danger red, tab ...; default primary or plain) with its text drawn in the kit's lettering. Buttons of one scope (the pause column, a lab's Practice box) letter
## at one cap height; a caption too long for its box breaks into two lines at that same height (menu_skin.gd).
func make_button(text: String, primary := false, compact := true, role := "") -> Button:
	var kind := role if role != "" else ("primary" if primary else "plain")
	var drawn := Kit.button(text,kind == "primary",compact)
	if kind != "primary" and kind != "plain":
		Kit.dress(drawn, kind)
		drawn.set_meta(&"comic_role", kind)
	if text.length() > 14: drawn.custom_minimum_size.y = 84
	ComicSkin.comicify(drawn, 0.5, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true, &"primary" if kind == "primary" else &"buttons")
	return drawn

# ------------------------------------------------------------------ pause actions

func _request_restart() -> void:
	hide_pause()
	restart_requested.emit()

func _request_end_run() -> void:
	hide_pause()
	end_run_requested.emit()

func request_back_to_main() -> void:
	hide_pause()
	back_to_main.emit()

func configure_camera_settings(handler: Callable, fields: PackedStringArray = ["XSensitivity","YSensitivity","InvertX","InvertY"]) -> void:
	settings.configure_camera(handler,fields)
	if pause != null: _refresh_controls()

# ------------------------------------------------------------------ pause / settings

func _build_pause() -> void:
	pause = Control.new()
	pause.name = "FriendsSettings"
	pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause.size = DESIGN
	_design.add_child(pause)
	_design.move_child(pause, 0)
	# One root for both halves: callers look up rows and the Back/Leave
	# wrappers by name under settings_root.
	settings_root = Control.new()
	settings_root.name = "Settings"
	settings_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.size = DESIGN
	pause.add_child(settings_root)
	# Left column: what this screen is, the run so far, and the way out.
	var side := VBoxContainer.new()
	side.name = "PauseColumn"
	# Full canvas height, content centred vertically: the heading and the buttons stay together in the middle.
	side.position = Vector2(56, 0)
	side.size = Vector2(364, DESIGN.y)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	settings_root.add_child(side)
	ComicSkin.set_scope(side)
	_pause_column = side
	# The small word above the heading sits on a cyan chip with the white rim.
	_pause_over_pill = PanelContainer.new()
	_pause_over_pill.name = "PauseOverline"
	_pause_over_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_over_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_over_pill.add_theme_stylebox_override("panel", Kit.pill_box(false, 22, 3))
	side.add_child(_pause_over_pill)
	_pause_over = Kit.overline("Level 1", Kit.ON_DARK, 26 if _phone() else 20)
	_pause_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_over_pill.add_child(_pause_over)
	_pause_title = Kit.heading("PAUSED", TITLE_SIZE)
	_pause_title.set_meta(&"comic_style", "headline")
	side.add_child(_pause_title)
	# One axis for the whole column: heading, overline, status and buttons all centre on the column's centre line.
	ComicSkin.comicify(_pause_title, 0.72, HORIZONTAL_ALIGNMENT_CENTER)
	_pause_status = Kit.label("", 28 if _phone() else 22, Kit.ON_DARK)
	_pause_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_status.name = "PauseStatus"
	side.add_child(_pause_status)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 34
	side.add_child(spacer)
	var resume := _button(side,"BackButton","RESUME",hide_pause,"primary")
	resume.custom_minimum_size = Vector2(320, 86)
	ComicSkin.comicify(resume, 0.6)
	resume.pressed.connect(func() -> void: Ui.play(resume, &"back"))
	var restart := _button(side,"Restart","Restart level",_request_restart,"plain")
	restart.custom_minimum_size = Vector2(320, 62)
	var end_run := _button(side,"EndRun","End run",_request_end_run,"plain")
	end_run.custom_minimum_size = Vector2(320, 62)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	side.add_child(gap)
	var leave := _button(side,"Leave",leave_text,request_back_to_main,"danger")
	leave.custom_minimum_size = Vector2(320, 62)
	# Right: the settings sheet, the violet sheet with the white rim.
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "SettingsSheet"
	_pause_panel.add_theme_stylebox_override("panel", Kit.panel("sheet", 30, 22))
	_pause_panel.position = Vector2(440, 44) # tall enough for the seven rows of Display without scrolling (the other tabs scroll)
	_pause_panel.size = Vector2(792, 632)
	settings_root.add_child(_pause_panel)
	var sheet := _column(_pause_panel,12)
	sheet.name = "SettingsColumn"
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	sheet.add_child(tabs)
	ComicSkin.set_scope(tabs)
	for index in TABS.size():
		var wrapper := HBoxContainer.new()
		wrapper.name = TABS[index]
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(wrapper)
		var button := make_button(TABS[index].to_upper(),false,true,"tab")
		button.custom_minimum_size.y = 58
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.add_child(button)
		button.pressed.connect(_select_tab.bind(index))
		_tabs.append(button)
	var stack := Control.new()
	stack.name = "WidgetSwitcher_134"
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size.y = 160
	sheet.add_child(stack)
	var definitions: Dictionary = Settings.DEFINITIONS
	for index in TABS.size():
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(scroll)
		_pages.append(scroll)
		var page := _column(scroll,6)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for key: String in GROUPS[index]: _setting_row(page,key,definitions[key])
		if index == 1:
			_gameplay_empty = Kit.label("Look settings are available during a run.",30 if _phone() else 24,Kit.MUTED_ON_DARK)
			_gameplay_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(_gameplay_empty)
	# The foot of the sheet: the note on the left, the key hints (cream keycaps) on the right.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	sheet.add_child(foot)
	var note := Kit.overline("Changes apply immediately", Kit.MUTED_ON_DARK, 22 if _phone() else 17)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(note)
	var hint := Widgets.KeyHints.new([{"keys": ["Q", "E"], "pad": ["LB", "RB"], "label": "Switch tab"}, {"keys": ["Esc"], "pad": ["B"], "label": "Back"}])
	hint.custom_minimum_size = Vector2(430, 50)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	for tab in _tabs: ComicSkin.comicify(tab, 0.56, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, &"tabs")
	ComicSkin.legible(_pause_status)
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refresh_controls()

## Phones scale the 1280x720 design down (844x390 draws it at 0.54): the small lines take bigger type there.
static func _phone() -> bool:
	return Settings.TouchControls.touch_ui()

## One row of a page: a sub-pill (named by the setting's key) with the label on the left and the control (named Input) on the right.
func _setting_row(parent: Node, key: String, definition: Dictionary) -> void:
	var row := PanelContainer.new()
	row.name = key
	row.custom_minimum_size.y = 58
	row.add_theme_stylebox_override("panel", _row_box())
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)
	var label := Kit.label(str(LABELS.get(key,key)),30 if _phone() else 23,Kit.ON_DARK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var input: Control
	match int(definition.type):
		1:
			var check := Widgets.Toggle.new()
			check.custom_minimum_size = Vector2(132, 44)
			line.add_child(check)
			check.toggled.connect(_changed.bind(key))
			input = check
		2:
			var slider := Widgets.ComicSlider.new()
			var limits: Array = definition.range
			slider.min_value = float(limits[0]); slider.max_value = float(limits[1])
			slider.step = float(definition.step)
			slider.custom_minimum_size = Vector2(290, 44)
			line.add_child(slider)
			var preview := Kit.label("",30 if _phone() else 24,Kit.GOLD,3)
			preview.name = "SliderPreviewValue"
			preview.custom_minimum_size = Vector2(70, 0)
			preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(preview)
			slider.value_changed.connect(_changed.bind(key))
			slider.value_changed.connect(_slider_preview.bind(row,key))
			input = slider
		3:
			var combo := Widgets.Picker.new()
			combo.custom_minimum_size = Vector2(380, 44)
			for option: String in definition.items: combo.add_item(option)
			line.add_child(combo)
			combo.item_selected.connect(_option_changed.bind(key))
			input = combo
	assert(input != null)
	input.name = "Input"
	input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_inputs[key] = input

## A row's sub-pill: a lighter veil on the violet sheet with a thin light outline.
static func _row_box() -> StyleBoxFlat:
	var box := Kit.pill_box(false, 24, 2)
	box.bg_color = Color(1, 1, 1, 0.13)
	box.border_color = Color(1, 1, 1, 0.38)
	box.shadow_size = 0
	box.content_margin_left = 20
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

## The rings page behind the sheet when Settings opens from the title (no world to show through).
class SkyPage extends Control:
	func _init() -> void:
		name = "SettingsSky"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false

	func _process(_delta: float) -> void:
		if is_visible_in_tree(): queue_redraw()

	func _draw() -> void:
		Kit.draw_backdrop(self, Rect2(Vector2.ZERO, size), float(Time.get_ticks_msec()) * 0.001, "sun", Vector2(0.5, 0.5))

func show_pause(in_game: bool = true) -> void:
	if pause == null: _build_pause()
	_in_game = in_game
	_refresh_controls()
	_refresh_context()
	pause.visible = true
	pause_open = true
	if pause_tree and in_game: get_tree().paused = true
	viewport_root.visible = true
	# In a run the world shows through the wash; from the title the rings page is the page (no veil over it).
	_sky.visible = not in_game
	_wash.color = Kit.wash_color(true) if in_game else Color(0.0, 0.0, 0.0, 0.0)
	_select_tab(0)
	pause_changed.emit(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout()
	Ui.enter(settings_root.find_child("PauseColumn", false, false), 0.0, Vector2(-36, 0), 0.4)
	Ui.enter(_pause_panel, 0.04, Vector2(40, 0), 0.45)

## Paused in a job: run summary and Main menu. From the title: plain Settings.
func _refresh_context() -> void:
	_pause_title.text = "PAUSED" if _in_game else "SETTINGS"
	(pause.find_child("Leave", true, false) as Control).visible = _in_game
	(pause.find_child("Leave", true, false).get_child(0) as Button).text = leave_text
	(pause.find_child("Restart", true, false) as Control).visible = _in_game and restart_available
	(pause.find_child("EndRun", true, false) as Control).visible = _in_game and end_run_available
	(pause.find_child("BackButton", true, false).get_child(0) as Button).text = "RESUME" if _in_game else "BACK"
	var status := {}
	if _in_game and status_provider.is_valid(): status = status_provider.call()
	_pause_over.text = str(status.get("overline", "")).to_upper() if _in_game else TeamCast.team_name().to_upper()
	_pause_over_pill.visible = _pause_over.text != ""
	# Only the Settings page describes itself; the in-game pause is the heading and the buttons.
	_pause_status.text = "" if _in_game else "Display, look, audio and controls."
	_pause_status.visible = _pause_status.text != ""
	_fit_pause_column()
	_sync_comics()

## The title, RESUME/BACK and the tabs are display type drawn over the real text.
func _sync_comics() -> void:
	if pause == null: return
	for node: Node in pause.find_children("*", "Control", true, false):
		if node.has_meta(&"comic"): ComicSkin.sync_comic(node)

## Touch grows every button to 76 (TouchControls.fit_ui) and owners may add rows to PauseColumn
## after show_pause (the lab's Practice box). The column is the full canvas height with its content
## centred. When the content would pass PAUSE_CONTENT_MAX, the heading gives up the room instead (a smaller
## title); buttons keep their thumb size. The column never moves, so Ui.enter is undisturbed.
## The decision measures what the full heading would need, so it cannot flip back and forth.
func _fit_pause_column() -> void:
	if _pause_column == null or not pause.visible: return
	var title_font := _pause_title.get_theme_font("font")
	var title_size := _pause_title.get_theme_font_size("font_size")
	var need := _pause_column.get_combined_minimum_size().y
	need += title_font.get_height(TITLE_SIZE) - title_font.get_height(title_size)
	var wanted := TITLE_SIZE_COMPACT if need > PAUSE_CONTENT_MAX else TITLE_SIZE
	if title_size != wanted: _pause_title.add_theme_font_size_override("font_size", wanted)
	# A Control only ever grows to its minimum; shrink back once rows go or the heading compacts.
	var height := maxf(DESIGN.y, _pause_column.get_combined_minimum_size().y)
	if _pause_column.size.y != height: _pause_column.size.y = height

func _select_tab(index: int) -> void:
	_selected_tab = clampi(index,0,TABS.size()-1)
	for number in _pages.size():
		var chosen := number == _selected_tab
		_pages[number].visible = chosen
		var tab := _tabs[number]
		ComicSkin.set_chosen(tab, chosen)
	_tabs[_selected_tab].grab_focus()
	_sync_comics()
	_layout()

func _unhandled_input(event: InputEvent) -> void:
	if not pause_open: return
	var step := 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE and not _in_game:
			hide_pause()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_Q: step = -1
		elif event.physical_keycode == KEY_E: step = 1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER: step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER: step = 1
		elif event.button_index == JOY_BUTTON_B or (event.button_index == JOY_BUTTON_START and _in_game):
			hide_pause()
			get_viewport().set_input_as_handled()
			return
	if step != 0:
		Ui.play(_tabs[0], &"toggle")
		_select_tab(wrapi(_selected_tab + step, 0, TABS.size()))
		get_viewport().set_input_as_handled()

func _refresh_controls() -> void:
	for key: String in settings_inputs:
		var input: Control = settings_inputs[key]
		var supported: bool = settings.supports(key)
		settings_root.find_child(key,true,false).visible = supported and _shown_here(key)
		if input is HSlider:
			input.editable = supported
			input.set_value_no_signal(float(settings.values.get(key,0)))
			_slider_preview(input.value,settings_root,key)
			input.queue_redraw()
		elif input is CheckBox:
			input.disabled = not supported
			input.set_pressed_no_signal(bool(settings.values.get(key,false)))
		elif input is OptionButton:
			input.disabled = not supported
			var value: Variant = settings.values.get(key,null)
			if key == "Fullscreen": input.select(int(value))
			elif value != null:
				var found := false
				for index in input.item_count:
					if input.get_item_text(index)==str(value): input.select(index); found=true; break
				# Present the actual window size, including800x450; do not change settings.
				if not found and key=="Resolution": input.add_item(str(value));input.select(input.item_count-1)
	if _gameplay_empty != null:
		_gameplay_empty.visible = not GROUPS[1].any(func(key:String)->bool:return settings.supports(key))

## Phones have no window, refresh-rate cap or VSync to choose; desktops without touch need no touch look speed.
const DESKTOP_ONLY := ["Fullscreen", "Resolution", "Vsync", "MaxFPS"]
func _shown_here(key: String) -> bool:
	var touch := Settings.TouchControls.touch_ui()
	if key in DESKTOP_ONLY: return not Settings.TouchControls.is_phone()
	if key == "TouchLook": return touch
	return true

func _slider_preview(value: float, _panel: Control, key: String) -> void:
	if settings_root == null: return
	var panel := settings_root.find_child(key,true,false)
	var label := panel.find_child("SliderPreviewValue",true,false) as Label
	if label != null:
		label.text = str(roundi(value*100))+"%" if Settings.DEFINITIONS[key].get("percent", false) else str(roundf(value*10)/10)

func _option_changed(index: int, key: String) -> void:
	var input: OptionButton = settings_inputs[key]
	_changed(index if key=="Fullscreen" else input.get_item_text(index),key)

func _changed(value: Variant, key: String) -> void:
	if settings.apply(key,value): setting_changed.emit(key,value)

func hide_pause() -> void:
	if pause != null: pause.visible = false
	if pause_open:
		pause_open = false
		if pause_tree and _in_game: get_tree().paused = false
		pause_changed.emit(false)
	if viewport_root != null: viewport_root.visible = false

func _process(_dt: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(_dt)
	_DevLap.lap("menus.p", _lap)

func _process_timed(_dt: float) -> void:
	if viewport_root != null and viewport_root.is_visible_in_tree():
		_layout()

func _layout() -> void:
	if viewport_root == null: return
	var viewport := get_viewport().get_visible_rect().size
	viewport_root.size = viewport
	var factor := minf(viewport.x / DESIGN.x, viewport.y / DESIGN.y)
	_design.scale = Vector2.ONE * maxf(factor, .01)
	_design.position = (viewport - DESIGN * factor) * 0.5
	_fit_pause_column()

func probe() -> Dictionary:
	return {"pause_open": pause_open, "supported_settings": settings_inputs.keys().filter(func(key): return settings.supports(key)),
		"settings_tab": TABS[_selected_tab], "in_game": _in_game}
