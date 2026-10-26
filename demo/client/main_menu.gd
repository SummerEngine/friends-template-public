extends Control
## The title: the show logo, one line saying what the game is, one Play and two small
## ways out (Settings, Quit). Play is the button id "Play" in every host: online it enters
## the two-player queue, in the local standalone it starts the local two-player delivery.
## Controls are taught in the round (client/hud.gd key hints); nothing else sits here.
## The page itself is built by the menu skin (menu_skin.gd, the menu kit) over the 3D stage (menu_backdrop.gd): the cast's characters in the painted sky.
signal view_changed(page: String)
const Ui := preload("res://client/friends_ui.gd")
const ComicSkin := preload("res://client/menu_skin.gd")
const MenuStyle := preload("res://client/menu_style.gd")
const MenuBackdrop := preload("res://client/menu_backdrop.gd")
const TeamCast := preload("res://style/team_cast.gd")
const MenuPet := preload("res://pet/menu_pet.gd")
const CastVideo := preload("res://client/cast_video.gd")
const SKIN_KEYS := ["Play", "Settings", "Invite", "Quit"]
var view: Control
var page := "main"
var actions: Dictionary = {}
var live_world := false
## Small line above PLAY: where the delivery happens ("Online · two players" / "Two players · this screen").
var play_note := "Online · two players"
var _last_action_ms := -1000
var _last_action_key := ""
var _buttons := {}
var _backdrop: Control
var _layer: Control
## The menu pet (a dog, demo/pet/) stands on the title only when this is on; the title's characters are the cast's.
static var pet_enabled := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ComicSkin.theme()
	# The comic backdrop sits under the page (live course or not).
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	# The menu pet stands in the free right half (demo/pet/), when it is on.
	if pet_enabled: add_child(MenuPet.new(self))
	_layer = Control.new()
	_layer.name = "FriendsDesign"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	resized.connect(_layout)
	show_page(page, actions)
	_intro.call_deferred()

## The team's intro video (demo/cast/video/intro.ogv) over the title, once per app run, before the first level.
func _intro() -> void:
	CastVideo.play(self, "intro")

## Hide the menu (not the backdrop) while Settings sits over the title.
func set_dimmed(dimmed: bool) -> void:
	if _layer == null: return
	var motion := Ui.tween(_layer)
	motion.tween_property(_layer, "modulate:a", 0.0 if dimmed else 1.0, 0.18)

## The backdrop is drawn from the first frame and hides the course behind the menu: nothing to lift.
func reveal() -> void:
	pass

## The title is the only page; owners call this again to swap the action table.
func show_page(page_name: String, table: Dictionary = {}) -> void:
	page = page_name
	actions = table
	_buttons.clear()
	if view != null: _retire(view)
	view = Control.new()
	view.name = "FriendsPage"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(view)
	_layer.move_child(view, 0)
	_build_page()
	_layout()
	_focus_initial.call_deferred()
	view_changed.emit(page)

## The skin builds the whole page; the shell keeps the contract: buttons named by action key,
## presses routed through _activate, play note and tagline as meta.
func _build_page() -> void:
	view.set_meta("activate", Callable(self, "_activate"))
	view.set_meta("play_note", play_note)
	view.set_meta("tagline", TeamCast.tagline())
	ComicSkin.build_main_menu(view, actions)
	for key: String in SKIN_KEYS:
		var button := view.find_child(key, true, false) as Button
		if button != null: _buttons[key] = button

## A page being left gives up input/focus at once, then fades out.
func _retire(old: Control) -> void:
	old.name = "RetiredPage"
	for control: Control in old.find_children("*", "Control", true, false):
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var motion := Ui.tween(old)
	motion.set_parallel(true)
	motion.tween_property(old, "modulate:a", 0.0, 0.18)
	motion.tween_property(old, "position:x", old.position.x - 30.0, 0.18).set_ease(Tween.EASE_IN)
	motion.chain().tween_callback(old.queue_free)

func _supported(key: String) -> bool:
	return actions.get(key) is Callable and actions[key].is_valid()

func action_button(key: String) -> Button:
	return _buttons.get(key)

func _activate(key: String) -> void:
	# Swallow a double activation of the same control (key repeat, click +
	# accept); a different control right after is a real choice.
	if (key == _last_action_key and Time.get_ticks_msec() - _last_action_ms < 250) or not _supported(key): return
	_last_action_ms = Time.get_ticks_msec()
	_last_action_key = key
	if key == "Play" and _backdrop != null and _backdrop.has_method("stage") and _backdrop.call("stage") != null: _backdrop.call("stage").cheer()
	actions[key].call()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	# Nothing focused (e.g. after a click on empty space): the first direction
	# or accept press puts focus back instead of doing nothing.
	if get_viewport().gui_get_focus_owner() == null and _layer.modulate.a > 0.5:
		for name: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
			if event.is_action_pressed(name):
				_focus_initial()
				get_viewport().set_input_as_handled()
				return

func _focus_initial() -> void:
	if not is_inside_tree() or view == null: return
	var preferred: Button = action_button("Play")
	if preferred == null or preferred.disabled:
		for button: Button in _buttons.values():
			if not button.disabled: preferred = button; break
	if preferred != null and not preferred.disabled: preferred.grab_focus()

func _layout() -> void:
	if _layer == null or size.x <= 0 or size.y <= 0: return
	# The skin lays itself out against the real viewport.
	_layer.size = size
	_layer.scale = Vector2.ONE
	_layer.position = Vector2.ZERO
