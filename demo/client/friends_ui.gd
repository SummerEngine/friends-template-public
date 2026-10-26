extends RefCounted
## FRIENDS interface kit, clean look: palette, type, flat panels with soft rounded corners, motion helpers and synthesized
## UI sounds. White and near-black like the bright test facility the levels are, with one accent: the team's brand colour
## (TeamCast.brand_accent()), cobalt when the cast has none. No ink outlines, no offset shadows, no halftone.
## Type is Inter (OFL, variable): DISPLAY/HEAVY at 800 for titles, buttons and HUD numbers, BOLD 700 and BODY 500 for
## small text. assets/fonts/.
const TeamCast := preload("res://style/team_cast.gd")
const GameAudio := preload("res://game/game_audio.gd") ## [audio] UI cues and the effects bus
const PAPER := Color("f2f3f5")
const WHITE := Color("ffffff")
const WALL := Color("d8dade")
const SLATE := Color("5c5f68")
const INK := Color("15161a")
const MUTED := Color("6b6e77")
const LINE := Color("e2e4e8")
## Failure (a broken delivery, the last seconds of a timed run).
const DANGER := Color("e5484d")
## The accent when the cast names no brand colour.
const COBALT := Color("2f5bff")
## Wash colour of the left title scrim.
const SCRIM := Color("f2f3f5")
## The one accent (the team's brand colour) and its shades, under these names: RED is the primary action, YELLOW the
## chosen / lit fill under ink type (a pale accent), BLUE_DEEP the plain plate (near-black).
static var ACCENT: Color = _accent()
static var RED: Color = ACCENT
static var RED_DARK: Color = ACCENT.darkened(0.16)
static var RED_HOT: Color = ACCENT.lightened(0.1)
static var BLUE: Color = ACCENT.lerp(WHITE, 0.55)
static var BLUE_DEEP: Color = INK
static var YELLOW: Color = ACCENT.lerp(WHITE, 0.82)
## Type on an accent plate: white, or ink when the brand colour is light.
static var ON_ACCENT: Color = WHITE if ACCENT.get_luminance() < 0.6 else INK
const INTER := preload("res://assets/fonts/Inter.ttf")
static var _cast_letters: bool = _use_cast_fonts() ## before any text: the cast's Japanese / Chinese letters (TeamCast.use_fonts)
## FontVariations made so far (declared before the fonts below, which fill it as they initialise).
static var _fonts: Dictionary = {}
## DISPLAY and HEAVY are Inter ExtraBold (its display optical size); BODY / BOLD are Inter at 500 / 700.
static var DISPLAY: Font = inter(800, 32)
static var HEAVY: Font = DISPLAY
static var BODY: Font = inter(500)
static var BOLD: Font = inter(700)
## Always 0: the clean look has no offset shadows.
const SHADOW_STEP := 0.0
const DUR := 0.32

static func _use_cast_fonts() -> bool:
	TeamCast.use_fonts()
	return true

static func _accent() -> Color:
	var brand := TeamCast.brand_accent()
	return brand if brand.a > 0.0 else COBALT

## Inter at a weight from 100 to 900; `optical` 14..32 picks the optical size (32 = display, tighter).
static func inter(weight: int, optical := 0) -> Font:
	var key := weight * 100 + optical
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = INTER
		var server := TextServerManager.get_primary_interface()
		var axes := {server.name_to_tag("weight"): weight}
		if optical > 0: axes[server.name_to_tag("opsz")] = optical
		variation.variation_opentype = axes
		_fonts[key] = variation
	return _fonts[key]

static var _sounds: Dictionary = {}
static var _player: AudioStreamPlayer

# ---------------------------------------------------------------- shapes

static func rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])

static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result

## Draws nothing: the clean look has no halftone.
static func draw_halftone(_item: CanvasItem, _rect: Rect2, _corner: int, _color: Color, _reach := 0.55, _pitch := 12.0) -> void:
	return

## A flat plate: `fill`, soft rounded corners (`radius`, scaled up a little) and, when `border`
## > 0, a 1-2 px hairline. A dark (ink) border colour is drawn as a quiet line at 14% so it never reads as an outline.
## No offset shadow: `offset` is ignored.
static func comic_box(fill: Color, border := 0, radius := 8, _offset := 0.0, border_color: Color = LINE) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	if border > 0:
		result.border_color = Color(border_color, border_color.a * 0.14) if border_color.get_luminance() < 0.3 else border_color
		result.set_border_width_all(2 if border >= 5 else 1)
	result.set_corner_radius_all(int(round(radius * 1.6)))
	result.corner_detail = 10
	result.anti_aliasing = true
	result.content_margin_left = 24
	result.content_margin_right = 24
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result

## A rounded focus ring in the accent, `gap` px outside the box.
static func focus_ring(radius := 12, gap := 4.0, width := 3) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = ACCENT
	ring.set_border_width_all(width)
	ring.set_corner_radius_all(radius + int(gap))
	ring.set_expand_margin_all(gap)
	ring.corner_detail = 10
	ring.anti_aliasing = true
	return ring

## A key: a flat white cap with a hairline (the dark key of a pad button is a circle).
static func key_width(text: String, height: float, round_button := false) -> float:
	if round_button or ARROWS.has(text) or text == "DPAD": return height
	return maxf(height, BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(height * 0.46)).x + height * 0.6)

const ARROWS := {"UP": 0.0, "RIGHT": 90.0, "DOWN": 180.0, "LEFT": 270.0}

## A keycap: white cap with a hairline, or a round gamepad face button. UP/DOWN/LEFT/RIGHT draw arrow shapes; DPAD draws
## a plus.
static func draw_key(item: CanvasItem, at: Vector2, text: String, height: float, round_button := false, dark := false) -> float:
	var size := int(height * 0.46)
	var shape := ARROWS.has(text) or text == "DPAD"
	var body := Rect2(at, Vector2(key_width(text, height, round_button), height))
	var face := INK if dark else WHITE
	var ink := WHITE if dark else INK
	if round_button:
		item.draw_circle(body.get_center(), body.size.x * 0.5, face, true, -1, true)
		if not dark: item.draw_circle(body.get_center(), body.size.x * 0.5, Color(INK, 0.16), false, 1.5, true)
	else:
		item.draw_style_box(comic_box(face, 0 if dark else 2, int(height * 0.14)), body)
	var c := body.get_center()
	if text == "DPAD":
		var arm := height * 0.26
		var thick := height * 0.13
		item.draw_rect(Rect2(c - Vector2(arm, thick * 0.5), Vector2(arm * 2, thick)), ink)
		item.draw_rect(Rect2(c - Vector2(thick * 0.5, arm), Vector2(thick, arm * 2)), ink)
	elif shape:
		var r := height * 0.18
		var tri := PackedVector2Array([Vector2(0, -r * 1.1), Vector2(r, r * 0.7), Vector2(-r, r * 0.7)])
		for index in tri.size(): tri[index] = c + tri[index].rotated(deg_to_rad(float(ARROWS[text])))
		item.draw_colored_polygon(tri, ink)
	else:
		var ascent := BOLD.get_ascent(size)
		item.draw_string(BOLD, Vector2(body.position.x, body.position.y + (body.size.y + ascent - BOLD.get_descent(size)) * 0.5), text, HORIZONTAL_ALIGNMENT_CENTER, body.size.x, size, ink)
	return body.size.x

# ---------------------------------------------------------------- engine drawing

static func blank_texture(size := Vector2i(1, 1)) -> ImageTexture:
	var image := Image.create_empty(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)

static func hide_engine_drawing(control: Control, kind: String) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed", "normal_mirrored", "hover_mirrored", "pressed_mirrored", "disabled_mirrored", "hover_pressed_mirrored"]:
		control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		control.add_theme_color_override(key, Color(0, 0, 0, 0))
	if kind == "CheckBox":
		for icon: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled", "radio_checked", "radio_unchecked", "radio_checked_disabled", "radio_unchecked_disabled"]:
			control.add_theme_icon_override(icon, blank_texture())
	if kind == "OptionButton":
		control.add_theme_icon_override("arrow", blank_texture())

## Last input family, for keycap vs face-button glyphs.
static var using_gamepad := false

static func note_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed: using_gamepad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5: using_gamepad = true
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed): using_gamepad = false

# ---------------------------------------------------------------- theme

## Button/field plate: `color` fill with a hairline in `border` (alpha 0 = none). `offset` is ignored.
static func style(color: Color, border: Color = LINE, radius: int = 8, _offset := 0.0) -> StyleBoxFlat:
	return comic_box(color, 0 if border.a <= 0.0 else 2, radius, 0.0, border)

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 20
	for kind: String in ["Button", "OptionButton", "CheckBox", "LineEdit", "Label"]:
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			result.set_color(key, kind, INK)
		result.set_color("font_disabled_color", kind, Color(INK, 0.4))
	result.set_font("font", "Button", DISPLAY)
	result.set_font_size("font_size", "Button", 20)
	result.set_stylebox("normal", "Button", style(WHITE))
	result.set_stylebox("hover", "Button", style(PAPER))
	result.set_stylebox("pressed", "Button", style(WALL))
	result.set_stylebox("disabled", "Button", style(Color(PAPER, 0.7), Color(0, 0, 0, 0)))
	result.set_stylebox("focus", "Button", focus_ring(13))
	result.set_stylebox("normal", "LineEdit", style(WHITE, LINE, 6))
	result.set_stylebox("focus", "LineEdit", style(WHITE, ACCENT, 6))
	result.set_stylebox("panel", "PopupMenu", style(WHITE, LINE, 6))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_stylebox("hover", "PopupMenu", style(YELLOW, Color(0, 0, 0, 0), 4))
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(INK, 0.5)
	grabber.set_corner_radius_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.06)
	track.set_corner_radius_all(4)
	track.content_margin_left = 6
	track.content_margin_right = 6
	result.set_stylebox("grabber", "VScrollBar", grabber)
	result.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	result.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	result.set_stylebox("scroll", "VScrollBar", track)
	result.set_stylebox("scroll_focus", "VScrollBar", track)
	return result

static func label(value: String, font_size: int = 20, color: Color = INK, display: bool = false) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_override("font", DISPLAY if display else BODY)
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func heading(value: String, font_size: int = 56, color: Color = INK) -> Label:
	var result := label(value, font_size, color)
	result.add_theme_font_override("font", HEAVY)
	return result

static func overline(value: String, color: Color = MUTED, font_size: int = 15) -> Label:
	var result := label(value.to_upper(), font_size, color)
	result.add_theme_font_override("font", BOLD)
	result.add_theme_constant_override("outline_size", 0)
	return result

## Action button: white plate with a hairline and ink type; primary is the accent with white type. Focus is an accent ring.
static func button(value: String, primary: bool = false, compact: bool = false) -> Button:
	var result := Button.new()
	result.text = value
	result.theme = theme()
	result.custom_minimum_size.y = 46 if compact else 56
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_override("font", DISPLAY)
	result.add_theme_font_size_override("font_size", (20 if compact else 24) if primary else (18 if compact else 20))
	result.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if primary:
		result.add_theme_stylebox_override("normal", style(RED, Color(0, 0, 0, 0)))
		result.add_theme_stylebox_override("hover", style(RED_HOT, Color(0, 0, 0, 0)))
		result.add_theme_stylebox_override("pressed", style(RED_DARK, Color(0, 0, 0, 0)))
		result.add_theme_stylebox_override("disabled", style(Color(RED, 0.4), Color(0, 0, 0, 0)))
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			result.add_theme_color_override(key, ON_ACCENT)
		result.add_theme_color_override("font_disabled_color", Color(ON_ACCENT, 0.7))
	result.mouse_entered.connect(func() -> void:
		if not result.disabled and result.focus_mode != Control.FOCUS_NONE: result.grab_focus())
	result.focus_entered.connect(func() -> void: play(result, &"hover"))
	result.pressed.connect(func() -> void: play(result, &"start" if primary else &"click"))
	return result

## Solid sheet used for forms and settings: white, a hairline, soft rounded corners.
static func panel(tint: Color = WHITE, padding: int = 28) -> PanelContainer:
	var result := PanelContainer.new()
	result.theme = theme()
	var box := comic_box(tint, 2, 12)
	box.set_content_margin_all(padding)
	result.add_theme_stylebox_override("panel", box)
	return result

# ---------------------------------------------------------------- motion

static func tween(node: Node) -> Tween:
	var result := node.create_tween()
	result.set_ignore_time_scale(true)
	result.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return result

static func out_expo(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)

static func out_back(t: float, s: float = 1.7) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0

static func in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5

static func damp(sharpness: float, delta: float) -> float:
	return 1.0 - exp(-sharpness * delta)

static func stagger(t: float, index: int, delay: float, duration: float) -> float:
	return clampf((t - float(index) * delay) / duration, 0.0, 1.0)

## Fade + slide in from `offset`, ending at the control's current position.
## Children of containers (whose position the container owns) fade and scale.
static func enter(control: CanvasItem, delay: float = 0.0, offset := Vector2(-40, 0), duration := 0.5) -> Tween:
	if control.get_parent() is Container:
		var item := control as Control
		item.pivot_offset = item.size * 0.5
		item.scale = Vector2.ONE * 0.94
		item.modulate.a = 0.0
		var pop := tween(item)
		pop.set_parallel(true)
		pop.tween_property(item, "modulate:a", 1.0, duration * 0.6).set_delay(delay)
		pop.tween_property(item, "scale", Vector2.ONE, duration).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return pop
	var target: Vector2 = control.get("position")
	control.set("position", target + offset)
	control.modulate.a = 0.0
	var motion := tween(control)
	motion.set_parallel(true)
	motion.tween_property(control, "modulate:a", 1.0, duration * 0.6).set_delay(delay)
	motion.tween_property(control, "position", target, duration).set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return motion

# ---------------------------------------------------------------- sound

## UI cues synthesised once: short soft ticks and tones, no imported assets.
static func play(context: Node, cue: StringName) -> void:
	if context == null or not context.is_inside_tree() or DisplayServer.get_name() == "headless": return
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = AudioStreamPlayer.new()
		_player.name = "FriendsUiSound"
		_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_player.max_polyphony = 6
		_player.volume_db = -11.0
		GameAudio.ensure_buses()
		_player.bus = GameAudio.SFX_BUS # [audio] the effects bus (Settings: Effects volume)
		context.get_tree().root.add_child(_player)
	# [audio] the generated cue (audio/sfx/mix.json event "ui_<cue>"); the synthesised tick below is the fallback.
	var made := GameAudio.ui_stream(cue)
	var stream: AudioStream = made if made != null else _sound(cue)
	if stream == null: return
	_player.volume_db = (-5.0 + linear_to_db(float(GameAudio.event_entry("ui_" + str(cue)).get("gain", 1.0)))) if made != null else -11.0
	_player.stream = stream
	_player.play()

static func _sound(cue: StringName) -> AudioStreamWAV:
	if _sounds.has(cue): return _sounds[cue]
	var spec: Dictionary = {
		&"hover": {"partials": [[760.0, 0.32, 38.0], [1140.0, 0.12, 52.0]], "length": 0.07},
		&"click": {"partials": [[240.0, 0.75, 26.0], [480.0, 0.30, 34.0]], "length": 0.16, "noise": 0.10, "noise_decay": 70.0},
		&"back": {"partials": [[330.0, 0.5, 24.0], [247.0, 0.4, 20.0]], "length": 0.18},
		&"toggle": {"partials": [[523.0, 0.4, 40.0], [784.0, 0.2, 50.0]], "length": 0.1},
		&"stamp": {"partials": [[70.0, 0.95, 14.0], [140.0, 0.4, 20.0]], "length": 0.3, "noise": 0.30, "noise_decay": 26.0},
		&"start": {"partials": [[262.0, 0.5, 10.0], [392.0, 0.4, 9.0], [523.0, 0.32, 8.0]], "length": 0.5, "noise": 0.22, "noise_decay": 14.0},
	}.get(cue, {})
	if spec.is_empty(): return null
	var rate := 44100
	var count := int(float(spec.length) * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var random := RandomNumberGenerator.new()
	random.seed = hash(String(cue))
	var partials: Array = spec.partials
	var noise := float(spec.get("noise", 0.0))
	var noise_decay := float(spec.get("noise_decay", 20.0))
	var previous := 0.0
	for sample in count:
		var t := float(sample) / rate
		var value := 0.0
		for partial: Array in partials:
			value += sin(TAU * float(partial[0]) * t) * float(partial[1]) * exp(-float(partial[2]) * t)
		if noise > 0.0:
			var white := random.randf_range(-1.0, 1.0)
			# First-order high-pass keeps the noise a crisp tick rather than a rumble.
			value += (white - previous) * 0.5 * noise * exp(-noise_decay * t)
			previous = white
		var attack := minf(t / 0.003, 1.0)
		var tail := minf((float(spec.length) - t) / 0.02, 1.0)
		data.encode_s16(sample * 2, int(clampf(value * attack * tail, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	_sounds[cue] = stream
	return stream
