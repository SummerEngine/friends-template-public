extends CanvasLayer
## The team's own videos (docs/slots.md, TeamCast.video_path()): `intro` over the title the first time the game is opened on this
## device (a local flag in SEEN_FILE; a new intro file plays once again), `win` over the results of a delivered run. A full-screen
## player above everything; any key, click, tap or pad button skips it. Nothing plays when the cast has no video, the file does not
## load, the engine cannot play video, or the run is headless.
const TeamCast := preload("res://style/team_cast.gd")
const LONGEST := 60.0           ## seconds; a video still running then is cut
const START_GRACE := 1.5        ## a video that has not started playing by then is dropped
const SEEN_FILE := "user://cast_videos.cfg"
static var _played := {}

var _player: VideoStreamPlayer
var _age := 0.0

## Plays the cast's video `kind` over the window of `host` (`once`: at most once per app run; the intro at most once per device).
## Returns the overlay, null when nothing plays.
static func play(host: Node, kind: String, once := true) -> CanvasLayer:
	if host == null or not host.is_inside_tree() or (once and _played.has(kind)): return null
	var path := TeamCast.video_path(kind)
	if path == "" or DisplayServer.get_name() == "headless" or not ClassDB.class_exists("VideoStreamTheora"): return null
	if kind == "intro" and seen(path): return null
	var stream: VideoStream = load(path) as VideoStream if ResourceLoader.exists(path) else null
	if stream == null:
		stream = ClassDB.instantiate("VideoStreamTheora") as VideoStream
		if stream == null: return null
		stream.file = path
	_played[kind] = true
	if kind == "intro": mark_seen(path)
	var overlay: CanvasLayer = load("res://client/cast_video.gd").new()
	overlay.name = "CastVideo_" + kind
	host.get_tree().root.add_child(overlay)
	overlay.start(stream)
	return overlay

## Whether this device has shown the video at `path` (the same file: its path and length).
static func seen(path: String) -> bool:
	var flags := ConfigFile.new()
	return flags.load(SEEN_FILE) == OK and flags.get_value("seen", _key(path), false)

static func mark_seen(path: String) -> void:
	var flags := ConfigFile.new()
	flags.load(SEEN_FILE)
	flags.set_value("seen", _key(path), true)
	flags.save(SEEN_FILE)

## Forgets that this device has shown the video at `path` (tools).
static func forget_seen(path: String) -> void:
	var flags := ConfigFile.new()
	if flags.load(SEEN_FILE) != OK or not flags.has_section_key("seen", _key(path)): return
	flags.erase_section_key("seen", _key(path))
	flags.save(SEEN_FILE)

static func _key(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "%s_%d" % [path.get_file().get_basename(), file.get_length() if file != null else 0]

func start(stream: VideoStream) -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var frame := AspectRatioContainer.new()
	frame.ratio = 16.0 / 9.0
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.stream = stream
	_player.finished.connect(queue_free)
	frame.add_child(_player)
	_player.play()

func _process(delta: float) -> void:
	_age += delta
	if _age > LONGEST or (_age > START_GRACE and not _player.is_playing()): queue_free()

func _input(event: InputEvent) -> void:
	var skip := (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton) and event.is_pressed()
	if not skip: return
	get_viewport().set_input_as_handled()
	queue_free()
