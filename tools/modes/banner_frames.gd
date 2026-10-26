extends SceneTree
## Frames of the show's banners and countdown digits (style/show_banner.gd) over a sky-to-cream gradient with a few blocky buildings (to judge the contrast). One job per run,
## chosen by --only and laid out to the window's own size (--resolution): `strips` (1440x720: six ages 0.0, 0.08, 0.2, 0.35, 0.6, 1.5 s per kind), `overview` (1440x1080: every kind
## settled, and a 16-letter name), `countdown` (1440x360: 3, 2, 1, GO!), `pop` (1440x720: the digit's pop), `phone` (844x390: the title banner with the menu button's corner marked, VICTORY, a
## digit). Pure 2D, offscreen binary only, never windowed, about 5 s per run (ONE render at a time machine-wide):
##   <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1440x720 --path demo -s "$PWD/tools/modes/banner_frames.gd" -- --shots=<dir> --only=strips [--prefix=a_]
## Writes <prefix>strip_<kind>.png, <prefix>overview.png, <prefix>countdown.png, <prefix>countdown_pop.png, <prefix>phone_*.png and prints BANNER_FRAMES lines.
const ShowBanner := preload("res://style/show_banner.gd")
const ShowTheme := preload("res://client/show_theme.gd")

const AGES := [0.0, 0.08, 0.2, 0.35, 0.6, 1.5]
const WORDS := {"victory": "VICTORY", "champion": "CHAMPION", "qualified": "QUALIFIED", "eliminated": "ELIMINATED", "failure": "TOO SLOW", "timesup": "TIME'S UP", "title": "CIRCUIT BREAKER"}

## Draws the cells it is given: each {rect, banner: {kind, words, line, age, wide} or digit: {word, go, age, cap}, label}.
class Sheet extends Control:
	const Banner := preload("res://style/show_banner.gd")
	var cells: Array = []
	var corner := 0.0 ## px of the top right corner to mark (the phone's menu button)

	func _draw() -> void:
		for cell: Dictionary in cells:
			var rect: Rect2 = cell.rect
			_backdrop(rect)
			var middle := rect.get_center() + Vector2(0.0, rect.size.y * 0.04)
			if cell.has("banner"):
				var b: Dictionary = cell.banner
				Banner.draw(self, b.kind, b.words, b.age, middle, b.wide, 1.0, b.get("line", ""))
			else:
				var d: Dictionary = cell.digit
				Banner.countdown(self, d.word, d.age, middle, d.cap, d.go)
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(8.0, 18.0), str(cell.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.05, 0.1, 0.2, 0.9))
		if corner > 0.0: draw_rect(Rect2(size.x - corner, 0.0, corner, corner), Color(1.0, 0.0, 0.3, 0.3))

	## Sky blue to cream, a few blocky buildings in cool tints and a teal floor.
	func _backdrop(rect: Rect2) -> void:
		var sky := PackedColorArray([Color("63aef0"), Color("63aef0"), Color("f3ead2"), Color("f3ead2")])
		draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), sky)
		var blocks := [[0.04, 0.34, 0.2, Color("8fb4de")], [0.22, 0.5, 0.16, Color("7da3d3")], [0.4, 0.28, 0.14, Color("9ec1e6")], [0.58, 0.42, 0.2, Color("86abd8")], [0.8, 0.3, 0.16, Color("a8c8ea")]]
		for block: Array in blocks:
			var h := rect.size.y * float(block[1])
			draw_rect(Rect2(rect.position.x + rect.size.x * float(block[0]), rect.end.y - rect.size.y * 0.16 - h, rect.size.x * float(block[2]), h), block[3])
		draw_rect(Rect2(rect.position.x, rect.end.y - rect.size.y * 0.16, rect.size.x, rect.size.y * 0.16), Color("4fb39a"))

var sheet: Sheet
var shots := ""
var prefix := ""
var only: PackedStringArray = []
var made := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="): shots = arg.substr(8)
		elif arg.begins_with("--prefix="): prefix = arg.substr(9)
		elif arg.begins_with("--only="): only = arg.substr(7).split(",")
	if shots == "":
		print("BANNER_FRAMES need --shots=<dir>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED # real pixels at any --resolution
	sheet = Sheet.new()
	root.add_child(sheet)
	run.call_deferred()

func wanted(name: String) -> bool:
	return only.is_empty() or name in only

func grid(cols: int, rows: int) -> Array:
	var rects: Array = []
	var cell := Vector2(root.size) / Vector2(float(cols), float(rows))
	for i in cols * rows: rects.append(Rect2(Vector2(cell.x * float(i % cols), cell.y * float(i / cols)), cell))
	return rects

func run() -> void:
	await process_frame
	var rects: Array
	if wanted("strips"): # 1440x720
		rects = grid(3, 2)
		for kind: String in ShowBanner.KINDS:
			var cells: Array = []
			var line := "ROUND 2 OF 5" if kind == "title" else ""
			for i in AGES.size():
				cells.append({"rect": rects[i], "label": "%s  age %.2f" % [kind, AGES[i]], "banner": {"kind": kind, "words": WORDS[kind], "line": line, "age": AGES[i], "wide": rects[i].size.x * 0.8}})
			await shoot("strip_" + kind, cells)
	if wanted("overview"): # 1440x1080
		rects = grid(2, 4)
		var cells: Array = []
		var shown: Array = ShowBanner.KINDS.duplicate()
		shown.append("long")
		for i in shown.size():
			var kind: String = shown[i]
			var banner := {"kind": kind, "words": WORDS.get(kind, "MAXIMILIANA JOSE"), "age": 0.6, "wide": rects[i].size.x * 0.72}
			if kind == "title": banner["line"] = "ROUND 2 OF 5"
			if kind == "long": banner["kind"] = "victory"
			cells.append({"rect": rects[i], "label": kind, "banner": banner})
		await shoot("overview", cells)
	if wanted("countdown"): # 1440x360
		rects = grid(4, 1)
		var cells: Array = []
		var words := ["3", "2", "1", "GO!"]
		for i in words.size():
			cells.append({"rect": rects[i], "label": "digit " + words[i], "digit": {"word": words[i], "go": i == 3, "age": 0.6, "cap": 150.0 if i < 3 else 110.0}})
		await shoot("countdown", cells)
	if wanted("pop"): # 1440x720
		rects = grid(3, 2)
		var cells: Array = []
		var pop_ages := [0.0, 0.11, 0.14, 0.2, 0.27, 0.6]
		for i in pop_ages.size():
			cells.append({"rect": rects[i], "label": "3  age %.2f" % pop_ages[i], "digit": {"word": "3", "go": false, "age": pop_ages[i], "cap": 180.0}})
		await shoot("countdown_pop", cells)
	if wanted("phone"): # 844x390
		rects = grid(1, 1)
		sheet.corner = 120.0 * 0.54
		await shoot("phone_title", [{"rect": rects[0], "label": "phone 844x390", "banner": {"kind": "title", "words": "CIRCUIT BREAKER", "line": "ROUND 2 OF 5", "age": 0.6, "wide": 500.0}}])
		sheet.corner = 0.0
		await shoot("phone_victory", [{"rect": rects[0], "label": "phone 844x390", "banner": {"kind": "victory", "words": "VICTORY", "age": 0.6, "wide": 420.0}}])
		await shoot("phone_digit", [{"rect": rects[0], "label": "phone 844x390", "digit": {"word": "2", "go": false, "age": 0.6, "cap": 390.0 * 0.097}}])
	print("BANNER_FRAMES made ", made)
	quit(0)

func shoot(name: String, cells: Array) -> void:
	sheet.size = Vector2(root.size)
	sheet.cells = cells
	sheet.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	var file := "%s/%s%s.png" % [shots, prefix, name]
	var saved := image.save_png(file) == OK
	print("BANNER_FRAMES shot ", file.get_file(), " ", saved, " ", image.get_width(), "x", image.get_height())
	if saved: made += 1
