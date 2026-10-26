extends RefCounted
## Animated HUD parts in the clean display type, each word on its own flat chip (helpers in hud_comic.gd).
## Presentational only: the HUD of each mode decides when to show them.
##   Clock             top-left run time, digits only
##   CheckpointNotice  the CHECKPOINT word: pop in, hold, rise and fade
##   Stamp             a word that drops in on the accent (results)
##   Keys              a row of keys, the held one lit
const HudComic := preload("res://client/hud_comic.gd")
const ComicText := preload("res://client/comic_text.gd")
const Ui := preload("res://client/friends_ui.gd")

# ================================================================== clock

## Top-left run time: tabular digits on a dark chip, nothing else (no label or icon). An optional second small line
## (hard mode's last run, chain mode's intact panes) sits under it. Touch controls keep the top right.
class Clock extends Control:
	const CAP := 46.0
	const SUB_CAP := 19.0
	var seconds := 0
	## The final seconds of a timed challenge count down: the digits turn red.
	var urgent := false
	var sub := ""
	var shown := 0.0
	var _time: ComicText
	var _sub: ComicText

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_time = HudComic.word("00:00", CAP, HORIZONTAL_ALIGNMENT_LEFT)
		_time.set_tabular(true)
		_sub = HudComic.word("", SUB_CAP, HORIZONTAL_ALIGNMENT_LEFT)
		add_child(_time)
		add_child(_sub)

	## Place at the top-left corner for this pixel scale.
	func fit(unit: float) -> void:
		var cap := CAP * unit
		HudComic.update(_time, HudComic.clock_text(seconds), cap)
		var warm := urgent and seconds <= 10
		if warm != (_time.plate_color == HudComic.TINT_FAIL):
			if warm: HudComic.fail_style(_time)
			else: HudComic.plain_style(_time)
		var below := _time.size.y + 8.0 * unit
		HudComic.update(_sub, sub, SUB_CAP * unit)
		_sub.visible = sub != ""
		_sub.position = Vector2(0.0, below)
		position = Vector2(24.0, 20.0) * unit
		size = Vector2(maxf(_time.size.x, _sub.size.x), below + (_sub.size.y if sub != "" else 0.0))

	func _process(delta: float) -> void:
		shown = minf(shown + delta / 0.55, 1.0)
		modulate.a = clampf(shown * 3.0, 0.0, 1.0)
		_time.position.x = (1.0 - Ui.out_expo(shown)) * -70.0 * HudComic.unit_of(self)

	## The text currently shown (probes and proofs read it).
	func text() -> String:
		return _time.text

# ================================================================== checkpoint

## The CHECKPOINT word, big and centred high on the team's accent, nothing else: it pops in, holds, then rises a little
## and fades.
class CheckpointNotice extends Control:
	const IMPACT := 0.20
	const HOLD := 1.45
	const LEAVE := 0.42
	const CAP := 52.0
	## Centre height of the word as a share of the screen.
	var centre_share := 0.20
	## Pixel scale; 0 = derive from the viewport height.
	var pixel_scale := 0.0
	var clock := 99.0
	var number := 0
	var total := 0
	var split := -1.0
	## The word shown; an order handover ("ORDER 2: WEDDING PORTRAIT") replaces CHECKPOINT for its one popup.
	var text := "CHECKPOINT"
	var _word: ComicText

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_word = HudComic.word("CHECKPOINT", CAP)
		HudComic.accent_style(_word)
		_word.visible = false
		add_child(_word)
		set_process(false)

	## n of total checkpoints; split = seconds since the previous one. The notice shows only the word; both stay
	## in the log line for the bots.
	func present(n: int, of_total: int, split_seconds := -1.0, mode := "", word := "CHECKPOINT") -> void:
		text = word
		if _word.text != word: _word.set_text(word)
		number = n
		total = maxi(of_total, n)
		split = split_seconds
		clock = 0.0
		set_process(true)
		visible = true
		_apply()
		print("GW_CP_POPUP n=", n, " total=", total, " split=", snappedf(split_seconds, 0.1), " mode=", mode, " text=", word)

	func cancel() -> void:
		clock = 99.0
		set_process(false)
		_word.visible = false

	func active() -> bool:
		return clock < HOLD + LEAVE

	func _process(delta: float) -> void:
		clock += minf(delta, 0.05)
		if clock >= HOLD + LEAVE:
			set_process(false)
			_word.visible = false
			return
		_apply()

	func _apply() -> void:
		var unit := pixel_scale if pixel_scale > 0.0 else HudComic.unit_of(self)
		var cap := CAP * unit
		# A long word (the handover banner) shrinks to fit 86% of the screen width instead of running off it.
		var room := get_viewport_rect().size.x * 0.86
		var fit := room / maxf(ComicText.unit_width(text), 0.001)
		if fit < cap: cap = fit
		if absf(_word.cap_height - cap) > 0.5: _word.set_cap_height(cap)
		_word.size = _word.custom_minimum_size
		var arrive := clampf(clock / IMPACT, 0.0, 1.0)
		var after := maxf(clock - IMPACT, 0.0)
		var grow := lerpf(1.25, 1.0, Ui.out_expo(arrive)) if clock < IMPACT else 1.0 + 0.02 * exp(-7.0 * after) * sin(after * 20.0)
		var leave := clampf((clock - HOLD) / LEAVE, 0.0, 1.0)
		_word.visible = true
		_word.modulate.a = minf(arrive * 2.4, 1.0) * (1.0 - leave * leave)
		_word.pivot_offset = _word.size * 0.5
		_word.scale = Vector2.ONE * (grow + leave * 0.07)
		var viewport := get_viewport_rect().size
		_word.position = Vector2((viewport.x - _word.size.x) * 0.5, viewport.y * centre_share - _word.size.y * 0.5 - leave * leave * 22.0 * unit)

# ================================================================== stamp

## A word on the team's accent that drops in after `delay` (results). Optional small line under it.
class Stamp extends Control:
	signal landed
	var delay := 0.0
	## Tilt in degrees (0: the word stays level).
	var angle := 0.0
	var clock := 0.0
	var _word: ComicText
	var _line: ComicText
	var _landed := false

	func _init(title: String, line := "", cap := 84.0) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_word = HudComic.word(title, cap, HORIZONTAL_ALIGNMENT_CENTER)
		HudComic.accent_style(_word)
		add_child(_word)
		_line = HudComic.word(line, cap * 0.28, HORIZONTAL_ALIGNMENT_CENTER)
		_line.visible = line != ""
		add_child(_line)
		var width := maxf(_word.size.x, _line.size.x)
		var gap := cap * 0.16
		_word.position = Vector2((width - _word.size.x) * 0.5, 0.0)
		_line.position = Vector2((width - _line.size.x) * 0.5, _word.size.y + gap)
		size = Vector2(width, _word.size.y + (gap + _line.size.y if line != "" else 0.0))
		pivot_offset = size * 0.5
		modulate.a = 0.0

	func _process(delta: float) -> void:
		clock += delta
		var t := clampf((clock - delay) / 0.26, 0.0, 1.0)
		var settle := maxf(clock - delay - 0.26, 0.0)
		modulate.a = clampf(t * 3.0, 0.0, 1.0)
		scale = Vector2.ONE * (lerpf(1.3, 1.0, Ui.out_expo(t)) + 0.015 * exp(-8.0 * settle) * sin(settle * 20.0))
		rotation = deg_to_rad(angle)
		if t >= 1.0 and not _landed:
			_landed = true
			landed.emit()
		if _landed and settle > 0.8: set_process(false)

# ================================================================== keys

## A row of keys (ComicText.keycap: flat white caps with a hairline). `height` is the key height; every key sits in a
## cell at least `cell` wide so a hint never reflows. An empty name is a gap of one cell (between two players' keys). The
## key that is down turns the accent (light()).
class Keys extends Control:
	const GAP := 0.16
	var cap := 40.0
	var _caps: Array = []   # KeyCap controls (comic_text.gd inner class: set_held / set_lit are called dynamically)
	var _names: Array[String] = []
	var _given := "<unset>" ## the list last laid out (gaps included), joined by a unit separator
	var _cell := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_keys(list: Array, height: float, cell := 0.0) -> void:
		var wanted := "\u001f".join(PackedStringArray(list.map(func(key: Variant) -> String: return str(key))))
		if wanted == _given and absf(cap - height) < 0.5 and absf(cell - _cell) < 0.5: return
		_given = wanted
		_cell = cell
		cap = height
		for node in _caps: node.queue_free()
		_caps.clear()
		_names.clear()
		var x := 0.0
		for key: Variant in list:
			if str(key) == "":
				x += maxf(cell, cap * 0.5) + GAP * cap
				continue
			var node: Control = ComicText.keycap(str(key), cap)
			var slot := maxf(cell, node.size.x)
			node.position = Vector2(x + (slot - node.size.x) * 0.5, 0.0)
			add_child(node)
			_caps.append(node)
			_names.append(str(key))
			x += slot + GAP * cap
		size = Vector2(maxf(x - GAP * cap, 0.0), cap)
		custom_minimum_size = size

	## Key down (the accent).
	func light(key: String, on: bool) -> void:
		for index in _names.size():
			if _names[index] == key: _caps[index].set_held(on)

	## Every key lit without the dip (a prompt: "press this").
	func light_all(on: bool) -> void:
		for node in _caps: node.set_lit(on)
