extends RefCounted
## Local settings: the values, their definitions (what the Settings pages draw), applying them and saving them.
## One plain file, `user://settings.cfg`, section "values", one key per setting.
const FriendsStyle = preload("res://style/friends_style.gd")
const TouchControls = preload("res://client/touch_controls.gd")
const SAVE_PATH := "user://settings.cfg"
const MUSIC_BUS := "GW_Music"
## Music is a linear bus gain; the default sits under the effects.
const MUSIC_DEFAULT := 0.6
## The bus each volume slider drives, found by name: the first of its names that exists. A slider whose bus does not exist
## yet keeps its value and drives the bus once the audio code has made it (apply_saved_audio after adding buses).
const VOLUME_BUSES := {"MasterVolume": ["Master"], "MusicVolume": [MUSIC_BUS, "Music"], "EffectsVolume": ["GW_Effects", "Effects", "SFX"], "VoiceVolume": ["GW_Voice", "Voice"]}
const VOLUME_DEFAULTS := {"MasterVolume": 1.0, "MusicVolume": MUSIC_DEFAULT, "EffectsVolume": 1.0, "VoiceVolume": 1.0}
const DEFAULTS := {"MasterVolume": 1.0, "MusicVolume": MUSIC_DEFAULT, "EffectsVolume": 1.0, "VoiceVolume": 1.0, "XSensitivity": 1.0, "YSensitivity": 1.0, "InvertX": false, "InvertY": false}
## How each setting is drawn: type 1 = switch, 2 = slider, 3 = picker. Sliders carry their range, pickers their items.
const DEFINITIONS := {
	"Fullscreen": {"type": 3, "items": ["Exclusive", "Borderless", "Windowed"]},
	"Resolution": {"type": 3, "items": ["2560x1440", "1920x1080", "1600x900", "1366x768", "1280x720", "1024x768"]},
	"Vsync": {"type": 1},
	"MaxFPS": {"type": 3, "items": ["Unlimited", "144", "120", "60", "30"]},
	"Quality": {"type": 3, "items": ["Low", "Medium", "High"]},
	"Palette": {"type": 3, "items": ["Vivid", "Calm"]},
	"TouchControls": {"type": 3, "items": ["Auto", "On", "Off"]},
	"TouchLook": {"type": 2, "range": [0.2, 3.0], "step": 0.1},
	"XSensitivity": {"type": 2, "range": [0.1, 5.0], "step": 0.1},
	"YSensitivity": {"type": 2, "range": [0.1, 5.0], "step": 0.1},
	"InvertX": {"type": 1},
	"InvertY": {"type": 1},
	"MasterVolume": {"type": 2, "range": [0.0, 1.0], "step": 0.01, "percent": true},
	"MusicVolume": {"type": 2, "range": [0.0, 1.0], "step": 0.01, "percent": true},
	"EffectsVolume": {"type": 2, "range": [0.0, 1.0], "step": 0.01, "percent": true},
	"VoiceVolume": {"type": 2, "range": [0.0, 1.0], "step": 0.01, "percent": true},
}
## Settings that act without a camera: everything else needs the running game to listen (look speed, inversion).
const DIRECT = ["MasterVolume", "MusicVolume", "EffectsVolume", "VoiceVolume", "Vsync", "MaxFPS", "Fullscreen", "Resolution", "Quality", "Palette", "TouchControls", "TouchLook"]
var values: Dictionary = {}
var camera_handler: Callable
var camera_fields: PackedStringArray = []
var save := ConfigFile.new()

func initialize() -> void:
	values = DEFAULTS.duplicate(true)
	values.Vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	values.MaxFPS = "Unlimited" if Engine.max_fps == 0 else str(Engine.max_fps)
	var mode := DisplayServer.window_get_mode()
	values.Fullscreen = 0 if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else (1 if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else 2)
	var resolution := DisplayServer.window_get_size()
	values.Resolution = "%dx%d" % [resolution.x, resolution.y]
	values.Quality = FriendsStyle.QUALITY_NAMES[FriendsStyle.quality_default()]
	values.Palette = FriendsStyle.PALETTE_NAMES[FriendsStyle.palette()]
	values.TouchControls = TouchControls.mode
	values.TouchLook = TouchControls.look_sensitivity
	save.load(SAVE_PATH)
	for key: String in values:
		if save.has_section_key("values", key): values[key] = save.get_value("values", key)
	# --glass-palette= wins over the saved value (the saved one shows again without the argument).
	values.Palette = FriendsStyle.PALETTE_NAMES[FriendsStyle.palette()]
	ensure_music_bus()
	for key: String in VOLUME_BUSES: _set_volume(key, float(values[key]))
	# A desktop window with no saved choice starts fullscreen.
	if not save.has_section_key("values", "Fullscreen") and _fullscreen_by_default():
		values.Fullscreen = 1
		apply("Fullscreen", 1)
	for key: String in DIRECT:
		if save.has_section_key("values", key) and key != "Palette": apply(key, values[key])

## Exported desktop builds only (what players launch): never dev/test runs from the editor
## binary, phones, the browser (fullscreen there needs a user gesture) or headless runs.
static func _fullscreen_by_default() -> bool:
	if not OS.has_feature("template") or not OS.has_feature("pc") or OS.has_feature("web"): return false
	if DisplayServer.get_name() == "headless": return false
	return not OS.get_cmdline_args().has("--summer-offscreen")

## Every volume bus's gain from the saved file (or the defaults), for scenes that play audio before any Settings screen has
## been built (the shared music loop), and again after the audio code adds its buses.
static func apply_saved_audio() -> void:
	ensure_music_bus()
	var file := ConfigFile.new()
	file.load(SAVE_PATH)
	for key: String in VOLUME_BUSES: _set_volume(key, float(file.get_value("values", key, VOLUME_DEFAULTS[key])))

## The bus a volume setting drives (the first of its VOLUME_BUSES names that exists), -1 when none exists yet.
static func volume_bus(key: String) -> int:
	for bus_name: String in VOLUME_BUSES.get(key, []):
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0: return index
	return -1

static func _set_volume(key: String, value: float) -> void:
	var index := volume_bus(key)
	if index >= 0: AudioServer.set_bus_volume_linear(index, clampf(value, 0, 1))

static func ensure_music_bus() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) >= 0: return
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index, MUSIC_BUS)
	AudioServer.set_bus_send(index, "Master")

func supports(key: String) -> bool:
	return key in DIRECT or (camera_handler.is_valid() and key in camera_fields)

func configure_camera(handler: Callable, fields: PackedStringArray) -> void:
	camera_handler = handler
	camera_fields = fields
	if camera_handler.is_valid(): camera_handler.call(values.duplicate(true))

func apply(key: String, value: Variant) -> bool:
	if not supports(key): return false
	if key in VOLUME_BUSES:
		if not (value is float or value is int): return false
		value = clampf(float(value), 0, 1)
		_set_volume(key, value)
	elif key == "Vsync":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED)
	elif key == "MaxFPS":
		var rate := 0 if str(value) == "Unlimited" else int(value)
		if rate not in [0, 30, 60, 120, 144]: return false
		Engine.max_fps = rate
	elif key == "Fullscreen":
		if int(value) not in [0, 1, 2]: return false
		DisplayServer.window_set_mode([DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED][int(value)])
	elif key == "Quality":
		var level: int = FriendsStyle.QUALITY_NAMES.find(str(value))
		if level < 0: return false
		FriendsStyle.set_quality(level)
	elif key == "TouchControls":
		if str(value) not in TouchControls.MODES: return false
		TouchControls.mode = str(value)
	elif key == "TouchLook":
		if not (value is float or value is int) or not is_finite(float(value)): return false
		value = clampf(float(value), 0.2, 3.0)
		TouchControls.look_sensitivity = value
	elif key == "Palette":
		var index: int = FriendsStyle.PALETTE_NAMES.find(str(value))
		if index < 0: return false
		FriendsStyle.set_palette(index)
	elif key == "Resolution":
		var fields := str(value).split("x")
		if fields.size() != 2 or not fields[0].is_valid_int() or not fields[1].is_valid_int(): return false
		var dimensions := Vector2i(int(fields[0]), int(fields[1]))
		if dimensions.x < 320 or dimensions.y < 240: return false
		DisplayServer.window_set_size(dimensions)
	values[key] = value
	if key in camera_fields: camera_handler.call(values.duplicate(true))
	save.set_value("values", key, value)
	save.save(SAVE_PATH)
	return true
