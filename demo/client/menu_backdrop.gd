extends Control
## The shared menu backdrop. With the cast's own title art (demo/cast/title_backdrop.png, .jpg or .webp; docs/slots.md)
## that picture, cover-scaled and nearly still: a few pixels of slow sway (plus a little mouse parallax on desktops).
## Without it, the show's own: the page of yellow concentric rings (menu_kit.gd draw_backdrop; the hue follows the brand) with the 3D stage over it for the title (style/menu_stage.gd: the cast on a round cushion),
## the podium room for the results, the rings page alone (a tone per page: yellow, sea, berry) for the loading, error and notice pages. No picture, no lettering.
##   MenuBackdrop.new()                  the title: the cast's art, else the stage with the whole cast
##   MenuBackdrop.new("results")         the results: the podium room (`stage().set_ranking(seats)`)
##   MenuBackdrop.new("loading")         the loading, error and notice pages: the rings page (`tone` picks its colour)
## A headless run builds no stage (nothing is drawn): the page's controls are all there is.
const MenuStyle := preload("res://client/menu_style.gd")
const Kit := preload("res://style/menu_kit.gd")
const MenuStage := preload("res://style/menu_stage.gd")
const OVERSCAN := 1.045
## The cast's title art: demo/cast/<CAST_ART>.<ending>, found by its name; kept at most CAST_MAX px on its longest side.
const CAST_ART := "title_backdrop"
const CAST_ENDINGS := ["png", "jpg", "jpeg", "webp"]
const CAST_MAX := 2048
static var cast_dir := "res" + "://cast/" ## checks point it at a folder of their own
static var _cast_art := {} ## path -> Texture2D (null when it does not load)
## Where the cover crop sits horizontally (1 = right edge): the title keeps its couriers on screen, the loading art centres.
const ANCHORS := {"title": 0.85, "loading": 0.5, "results": 0.5}
var anchor_x := 0.85
var kind := "title"
## The rings page's tone for the loading, error and notice pages: "sun", "sea", "berry" (menu_kit.gd draw_backdrop).
var tone := "sun"
var _clock := 0.0
var _mouse := Vector2.ZERO
var _sky: Texture2D
var _stage: Control

func _init(page_kind := "title") -> void:
	name = "MenuBackdrop"
	kind = page_kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_x = float(ANCHORS.get(kind, 0.85))
	_sky = MenuStyle.loading_texture() if kind == "loading" else (cast_backdrop() if kind == "title" else null)
	if _sky == null and kind == "title": _sky = MenuStyle.backdrop_texture()
	if _sky == null and kind != "loading" and DisplayServer.get_name() != "headless":
		_stage = MenuStage.new(kind)
		add_child(_stage)

## The 3D stage (null for the sky page, with the cast's art, and in a headless run).
func stage() -> Control:
	return _stage

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_clock += minf(delta, 0.05)
	var viewport := get_viewport().get_visible_rect().size
	if viewport.x > 0 and DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		var target := (get_viewport().get_mouse_position() / viewport - Vector2(0.5, 0.5)).clampf(-0.5, 0.5)
		_mouse = _mouse.lerp(target, minf(delta * 2.0, 1.0))
	queue_redraw()

func _draw() -> void:
	if _sky != null:
		draw_texture_rect(_sky, _frame(), false)
	elif kind == "loading" or _stage == null:
		Kit.draw_backdrop(self, Rect2(Vector2.ZERO, size), _clock, tone)
	elif kind == "title":
		Kit.draw_backdrop(self, Rect2(Vector2.ZERO, size), _clock, tone, Vector2(0.7, 0.56)) # behind the cast on the right


## Where a point of the art (0..1 across the picture) is drawn right now, in this control's pixels: things standing on the
## drawing (the menu pet) follow its sway. Without the art: the same share of the control.
func art_point(share: Vector2) -> Vector2:
	if _sky == null: return share * size
	var frame := _frame()
	return frame.position + share * frame.size

## The art's rectangle: cover-scaled, anchored, with a slow sway (tens of seconds a cycle) and mouse parallax of a few px.
func _frame() -> Rect2:
	var texture_size := _sky.get_size()
	var fit := maxf(size.x / texture_size.x, size.y / texture_size.y) * OVERSCAN
	var drawn := texture_size * fit
	var unit := size.y / 1080.0
	var sway := Vector2(sin(_clock * 0.11) * 6.0, cos(_clock * 0.083) * 3.0) * unit
	var parallax := _mouse * Vector2(-10.0, -5.0) * unit
	var slack := drawn - size
	return Rect2(Vector2(-slack.x * anchor_x, -slack.y * 0.5) + sway + parallax, drawn)

## The cast's own title art, null when the cast has none (or it does not load). A picture the engine has not imported yet
## (just dropped into demo/cast/) is read directly.
static func cast_backdrop() -> Texture2D:
	for ending: String in CAST_ENDINGS:
		var path: String = cast_dir + CAST_ART + "." + ending
		if not _cast_art.has(path):
			var art: Texture2D = null
			if ResourceLoader.exists(path): art = load(path) as Texture2D
			elif FileAccess.file_exists(path):
				var image := Image.load_from_file(path)
				if image != null and not image.is_empty():
					var longest := maxi(image.get_width(), image.get_height())
					if longest > CAST_MAX: image.resize(image.get_width() * CAST_MAX / longest, image.get_height() * CAST_MAX / longest, Image.INTERPOLATE_LANCZOS)
					art = ImageTexture.create_from_image(image)
			_cast_art[path] = art
		if _cast_art[path] != null: return _cast_art[path]
	return null
