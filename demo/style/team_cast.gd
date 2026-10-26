extends RefCounted
## The team cast: everything a creator (or their agent) personalises lives in ONE file, demo/cast/cast.json, plus the
## files with fixed names next to it in demo/cast/ (docs/slots.md: format team-cast-v2; a team-cast-v1 file loads too).
## Every other file of the template is locked (tools/cast_check.py fails on any change outside demo/cast/). This script only
## reads the cast; it never decides rules. Shared: the authority reads the words too.
##
##   TeamCast.team_name()          # "FRIENDS": window title, wordmark, lobby floor word, pause screen
##   TeamCast.title()              # the team's long title (team.title, up to 40) for the title screen and the results, else the name
##   TeamCast.tagline()            # caption strip under the title (without one, a template line naming the carried thing)
##   TeamCast.credit_link()        # the team's https link, shown only on the results screen ("made by the <team> team"), "" for none
##   TeamCast.player(seat)         # {name, color, hair, skin, catchphrase, title, look, emote}; seats beyond the cast keep the default seat look
##   TeamCast.voice(seat)          # the seat's clip (demo/cast/voice/member_<n>.ogg) played with the catchphrase, null for none
##   TeamCast.voices(seat)         # every clip of the seat: voice/member_<n>.ogg and its variants voice/member_<n>_<k>.ogg (k = 1..3)
##   TeamCast.announcer("goal")    # the announcer's clips for an event (announcer/<event>_<n>.ogg, n = 1..4), [] for none
##   TeamCast.team_wall()          # [{name, picture, color}] for the team wall board (team/member_<n>.png), [] for none
##   TeamCast.word("break")        # the comic words: delivered, break, fall, pop
##   TeamCast.reveal()             # the line shown big on the results of a delivered run (words.reveal, up to 40), "" for none
##   TeamCast.goal_sign()          # the goal sign's picture (goal_sign.png, .jpg or .webp), else the logo, null for none
##   TeamCast.run()                # the one lobby circle the game shows: "time_attack" (default) or "endless" (run)
##   TeamCast.mode()               # the cast's mode id as written ("show" = the party show; modes/modes.gd checks it; "" = carry)
##   TeamCast.use_fonts()          # hangs the cast's Japanese / Chinese letters (fonts/, tools/cast_fonts.py) behind the game's fonts
##   TeamCast.object_kind()        # "landscape" (default) | "portrait" | "glass"
##   TeamCast.picture()            # the carried thing's print (object.picture, else the logo), null for the built-in look
##   TeamCast.logo()               # the team logo (brand.logo; the keyed copy in cast/prepared/ when tools/cast_prep.py made one), null for none
##   TeamCast.logo_backing()       # the colour of a plate the logo sits on so it reads: near white for a dark or colourful logo, ink for a pale one
##   TeamCast.brand_accent()       # the first brand colour, clamped so it reads on paper and under ink; alpha 0 for none
##   TeamCast.brand_walls()        # "stripe" | "accent" | "full": how much of each room the brand colour paints (brand.walls; "auto" resolved)
##   TeamCast.brand_paint()        # the colour brand.walls paints: the first brand colour with colour in it, as it is; alpha 0 for none
##   TeamCast.wall_hue()           # the hue the level walls take (a brand colour clear of the hazard colours), -1 to keep teal
##   TeamCast.world_theme()        # "office" | "outdoor": the backdrop around the levels and the lobby
##   TeamCast.world_style()        # "party" | "night": the show's world, bright candy or dark sci-fi (world.style; "auto" = night for a near-black first brand colour)
##   TeamCast.balloon_shape()      # "balloon" | "blimp" | "ball": the floating thing (3+ players)
##   TeamCast.balloon_picture()    # its print (balloon.picture, else the logo), null for none
##   TeamCast.obstacle(i)          # 1-based: {label, picture, color} for the sign at level slot obstacle_<i> and the faces of obstacle boxes (shape meta slot), {} for none
##   TeamCast.plain_edge(picture)  # true when the picture's edge is one plain colour (a picture on a flat background)
##   TeamCast.trimmed(picture)     # the picture without the plain margins around its content (itself when it has none or its edge is not plain)
##   TeamCast.poster(i)            # 1-based: {picture, caption} for slot poster_<i> (picture falls back to the cast's other pictures, poster 1 to the logo), {} for none
##   TeamCast.poster_own(i)        # 1-based: {picture, caption} of posters[i] only, {} for none
##   TeamCast.scene_art()          # [{picture, caption}] the cast's pictures that are not the logo: billboard_1/2, banner_1/2, then obstacle 1..5
##   TeamCast.egg(i)               # 1-based: the line on the hidden board at slot egg_<i>, "" for none
##   TeamCast.music_path()         # the gameplay loop (music: an id of demo/audio/music/friends-<id>.ogg or .wav)
##   TeamCast.show_word("go")      # the show's lines: qualified, eliminated, champion, go (show.words.<kind>, up to 16, upper case; defaults QUALIFIED! ELIMINATED CHAMPION! GO!)
##   TeamCast.slot_picture(id)     # banner_1/2, billboard_1/2: that file name's picture (.png, .jpg or .webp), null for none
##   TeamCast.crown_model()        # the cast's crown.glb as a new Node3D (about 0.5 m wide, origin at its base centre, +Y up), null for none
##   TeamCast.hero_prop_model()    # the cast's hero_prop.glb as a new Node3D (the stand under the crown, style/hero_prop.gd fits it), null for none
##   TeamCast.round_text("r15", "title")  # a round's own title / rule / hint (show.rounds.<id>.title|rule|hint, upper case, clipped), "" for none (docs/swappables.md)
##   TeamCast.round_labels("r15")  # the words the round's main hazard wears (show.rounds.<id>.label: a text or up to 8), [] for none
##   TeamCast.round_model("r21")   # the round's own model (cast/round_<id>.glb, r21 and r23 only) as a new Node3D, null for none
##   TeamCast.video_path("intro")  # "intro" | "win": cast/video/<kind>.ogv in the project when the cast names it and it is there, else ""
##   TeamCast.show_item("smash")   # the cast's own entry for a show item or event id (show.items[], docs/items.md): {name, banner, line, off, voice, sfx, media, tuning}, {} for none
##   TeamCast.show_pigeon()        # the cast's own show.pigeon entry (GHOST PIGEON, docs/pigeon.md): {off, banner, coo, splat, line, drop_line, tuning}, {} for none
##   TeamCast.show_manager()       # the cast's `show.manager` (the manager experiment, modes/show/manager/): {off, title, line, you, prompt, waiting, made, rules: {id: {name, banner, line, off, tuning}}}; {} for none
##   TeamCast.item_file("items/x.ogg")  # a file of demo/cast/items/ (voice, sfx: AudioStream; media: its res:// path, ogv only), null / "" when it is not there
##
## A missing, unreadable or partly filled cast falls back field by field to the defaults (the FRIENDS look), so a broken
## cast never stops the game; tools/cast_check.py is where a bad cast is reported.
const PATH := "res://cast/cast.json"
const PICTURE_DIR := "res" + "://cast/" ## a payload directory (tools/build_domain_graph.py SHARED_PAYLOADS)
const MUSIC_DIR := "res" + "://audio/music/"
const FORMAT := "team-cast-v2"
const FORMATS := ["team-cast-v1", "team-cast-v2"]
const OBJECT_KINDS := ["landscape", "portrait", "glass"]
const RUNS := ["time_attack", "endless"] ## run: the one lobby circle a game shows (one game, one mode: AGENTS.md)
## The game's fonts that take the cast's fallback fonts (the stencil room numbers are digits only).
const GAME_FONTS := ["res://assets/fonts/Inter.ttf", "res://assets/fonts/Archivo.ttf", "res://assets/fonts/Bangers-Regular.ttf", "res://assets/fonts/Nunito.ttf", "res://assets/fonts/LilitaOne-Regular.ttf"]
const FALLBACK_FONTS := 2 ## fonts/fallback_1.ttf, fonts/fallback_2.ttf
const GOAL_SIGN := "goal_sign" ## demo/cast/goal_sign.<ending>: the goal sign's face instead of the logo
const PICTURE_ENDINGS := ["png", "jpg", "jpeg", "webp"] ## the endings of a picture found by its fixed name
const PREPARED_DIR := "res" + "://cast/prepared/" ## tools/cast_prep.py: a logo with an opaque background, keyed out, as <stem>.png
const SLOT_PICTURES := ["banner_1", "banner_2", "billboard_1", "billboard_2"] ## demo/cast/<id>.<ending>
const CROWN_FILE := "crown.glb" ## demo/cast/crown.glb: the show's crown model instead of the built-in one
const HERO_PROP_FILE := "hero_prop.glb" ## demo/cast/hero_prop.glb: the show's hero prop, the stand the crown floats over (docs/hero-prop.md)
const SHOW_WORDS := {"qualified": "QUALIFIED!", "eliminated": "ELIMINATED", "champion": "CHAMPION!", "go": "GO!"}
const SHOW_WORD_MAX := 16
## show.rounds.<id>: the keys a round accepts, the longest text of a key and of a label, the most labels (tools/cast_check.py checks the same).
const ROUND_KEYS := {"r14": ["title", "rule", "hint"], "r15": ["title", "rule", "hint", "label"], "r16": ["title", "rule", "hint"], "r17": ["title", "rule", "hint", "label"],
	"r18": ["title", "rule", "hint"], "r19": ["title", "rule", "hint"], "r21": ["title", "rule", "hint", "label", "model"], "r22": ["title", "rule", "hint"],
	"r23": ["title", "rule", "hint", "label", "model"], "r24": ["title", "rule", "hint"], "r25": ["title", "rule", "hint"], "r26": ["title", "rule", "hint"],
	"r27": ["title", "rule", "hint"], "r28": ["title", "rule", "hint"], "r29": ["title", "rule", "hint"], "r30": ["title", "rule", "hint"], "r31": ["title", "rule", "hint"], "r32": ["title", "rule", "hint"]}
const ROUND_TITLE_MAX := 24
const ROUND_LINE_MAX := 48
const ROUND_LABEL_MAX := 16
const ROUND_LABELS := 8
const ROUND_MODELS := ["r21", "r23"] ## the rounds that take a model: cast/round_<id>.glb
const GLASS_TAGLINE := "Two players · one pane of glass · don't drop it" ## the template tagline when the cast carries the glass
const THEMES := ["office", "outdoor"]
const NIGHT_VALUE := 0.30 ## "auto": a first brand colour with a lower HSV value than this is a dark brand
const BRAND_WALLS := ["auto", "stripe", "accent", "full"]
## brand.walls "auto": the first brand colour is vivid enough to paint whole walls at this saturation, value and chroma (s * v).
const VIVID_SATURATION := 0.45
const VIVID_VALUE := 0.35
const VIVID_CHROMA := 0.3
const BALLOON_SHAPES := ["balloon", "blimp", "ball"]
const VIDEOS := ["intro", "win"]
## The team pack (docs/slots.md): files found by their fixed names, each optional.
const ANNOUNCER_EVENTS := ["start", "near_drop", "break", "pop", "zap", "goal", "perfect"]
const ANNOUNCER_VARIANTS := 4
const VOICE_VARIANTS := 3
const TEAM_WALL := 10
const OBSTACLES := 5
const POSTERS := 3
const EGGS := 5
const DEFAULT_MUSIC := "careful-step"
const MAX_PICTURE := 1024     ## a picture longer than this (px) is scaled down when it is loaded
## Brand colours: one with less colour than this (greys, near black, near white) is not used as an accent.
const GREY_SATURATION := 0.18
const GREY_VALUE := 0.2
## Hues of the hazard warning stripes (reds, oranges, yellows): walls never take them, so a hazard always reads.
const WARNING_HUES := Vector2(0.93, 0.17)
## Default seat look: the courier palette and the two skin / hair tones the couriers had before the cast.
const SEAT_COLORS: Array = [Color("#ff5a36"), Color("#2c4bff"), Color("#2ec27e"), Color("#ffd23f"), Color("#9b5de5"), Color("#18b5b5"), Color("#ff7eb6"), Color("#9aa0ad")]
const SKINS: Array = [Color("#e9b48e"), Color("#a56b45")]
const HAIRS: Array = [Color("#2b1a12"), Color("#e3b04a")]
const DEFAULTS := {
	"team": {"name": "FRIENDS", "tagline": "Two players · one painting · don't drop it"},
	"object": {"kind": "landscape", "picture": "", "fit": "contain"},
	"words": {"delivered": "DELIVERED", "break": "CRACK!", "fall": "WHOOPS!", "pop": "POP!", "zap": "ZAP!", "burnt": "BURNT!"},
}
static var _cast: Dictionary = {}
static var _loaded := false
static var _fonts_used := false
static var _files := {}       ## cast file name -> loaded Texture2D / AudioStream (null when it does not load)

static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if parsed is Dictionary and str(parsed.get("format", "")) in FORMATS: _cast = parsed
			else: push_warning("Team cast ignored (not %s): %s" % [" or ".join(FORMATS), PATH])
	return _cast

## Tests and tools only: use `cast` instead of the file (an empty dictionary goes back to the file).
static func override(cast: Dictionary) -> void:
	_cast = cast
	_loaded = not cast.is_empty()
	_files.clear()

static func _section(key: String) -> Dictionary:
	var part = data().get(key, {})
	return part if part is Dictionary else {}

static func _list(key: String) -> Array:
	var part = data().get(key, [])
	return part if part is Array else []

static func _string(value) -> String:
	return str(value).strip_edges() if value is String else ""

static func _text(section: String, key: String) -> String:
	var text := _string(_section(section).get(key))
	return text if text != "" else str(DEFAULTS[section][key])

static func team_name() -> String:
	return _text("team", "name").to_upper()

static func tagline() -> String:
	var own := _string(_section("team").get("tagline"))
	if own != "": return own
	return GLASS_TAGLINE if object_kind() == "glass" else str(DEFAULTS["team"]["tagline"])

## The team's long title (team.title, "ACME: DON'T DROP THE PARCEL"): big on the title screen and over the results headline. Without
## one, the team name.
static func title() -> String:
	var own := _string(_section("team").get("title")).to_upper()
	return own if own != "" else team_name()

static func has_title() -> bool:
	return _string(_section("team").get("title")) != ""

## The team's own link (team.credit_link) for the one credit line of the results screen: an https:// address, "" when the cast has none
## or it is not one. The game never opens it by itself.
static func credit_link() -> String:
	var link := _string(_section("team").get("credit_link"))
	var ok := link.begins_with("https://") and link.length() <= 100 and link.trim_prefix("https://").contains(".") and not link.contains(" ")
	return link if ok else ""

## The surprise line of a gift or proposal game ("WILL YOU MARRY ME?"): shown big on the results only when the run was
## delivered, never before; "" for none.
static func reveal() -> String:
	return _string(_section("words").get("reveal")).to_upper()

## The picture on the goal sign: the cast's goal_sign.png (.jpg, .webp) found by its name, else the logo; null for none.
static func goal_sign() -> Texture2D:
	for ending in PICTURE_ENDINGS:
		var picture := _present(GOAL_SIGN + "." + ending, "") as Texture2D
		if picture != null: return picture
	return logo()

## Hangs the cast's fallback fonts (demo/cast/fonts/fallback_<n>.ttf from tools/cast_fonts.py: exactly the Japanese and
## Chinese letters the cast uses) behind every font of the game, once; nothing without them. The client calls it before it
## draws text; Font and FontVariation pick them up for every letter their own font lacks.
static func use_fonts() -> void:
	if _fonts_used: return
	_fonts_used = true
	var extra: Array[Font] = []
	for n in range(1, FALLBACK_FONTS + 1):
		var font := _font("fonts/fallback_%d.ttf" % n)
		if font != null: extra.append(font)
	if extra.is_empty(): return
	for path: String in GAME_FONTS:
		var font := load(path) as Font
		if font == null: continue
		var list: Array[Font] = font.fallbacks.duplicate()
		for each in extra:
			if not list.has(each): list.append(each)
		font.fallbacks = list

static func _font(file: String) -> Font:
	var path := PICTURE_DIR + file
	if not _cast_file(file, "fonts") or not _exists(path): return null
	if ResourceLoader.exists(path): return load(path) as Font
	var font := FontFile.new() # dropped in, not imported yet
	return font if font.load_dynamic_font(path) == OK else null

## The cast's mode as written (cast `mode`): modes/modes.gd current() turns it into a known mode id, "carry" by default.
static func mode() -> String:
	return _string(data().get("mode"))

## The one lobby circle this game shows (cast `run`): "time_attack" (5 levels, total time; the default) or "endless".
static func run() -> String:
	var value := _string(data().get("run"))
	return value if value in RUNS else RUNS[0]

static func word(key: String) -> String:
	var text := _string(_section("words").get(key))
	return (text if text != "" else str(DEFAULTS["words"].get(key, key))).to_upper()

## The line of the show's moment `kind` ("qualified", "eliminated", "champion", "go"): show.words.<kind> (up to SHOW_WORD_MAX letters), else
## the default (QUALIFIED! / ELIMINATED / CHAMPION! / GO!), upper case.
static func show_word(kind: String) -> String:
	var words = _section("show").get("words", {})
	var own := _string(words.get(kind)) if words is Dictionary else ""
	return (own if own != "" else str(SHOW_WORDS.get(kind, kind))).left(SHOW_WORD_MAX).to_upper()

## The cast members as listed (may be empty).
static func members() -> Array:
	var result: Array = []
	for entry in _list("players"):
		if entry is Dictionary: result.append(entry)
	return result

## The look and name of `seat`. Seats the cast lists use the cast (missing fields fall back to the default seat look);
## seats beyond it keep the default look and are "PLAYER n".
static func player(seat: int) -> Dictionary:
	var cast := members()
	var entry: Dictionary = cast[seat] if seat >= 0 and seat < cast.size() else {}
	var index := maxi(seat, 0)
	var name := _string(entry.get("name"))
	return {
		"name": (name if name != "" else "PLAYER %d" % (index + 1)).to_upper(),
		"color": _color(entry.get("color"), SEAT_COLORS[index % SEAT_COLORS.size()]),
		"hair": _color(entry.get("hair"), HAIRS[index % HAIRS.size()]),
		"skin": _color(entry.get("skin"), SKINS[index % SKINS.size()]),
		"catchphrase": _string(entry.get("catchphrase")),
		"title": _string(entry.get("title")).to_upper(),
		"look": _look(entry.get("look")),
		"emote": _string(entry.get("emote")), # an emote id of the character catalog; the rig checks it
	}

## players[i].look as written: catalog slot -> item id, text values only (CharacterLook.defaults_for_seat checks the ids).
static func _look(value) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for slot in value:
			if value[slot] is String: result[str(slot)] = _string(value[slot])
	return result

static func player_name(seat: int) -> String:
	return player(seat)["name"]

static func player_color(seat: int) -> Color:
	return player(seat)["color"]

## The voice clip of `seat` (players[seat].voice, a file under demo/cast/voice/), null when the cast has none or it does not load.
static func voice(seat: int) -> AudioStream:
	var cast := members()
	if seat < 0 or seat >= cast.size(): return null
	return _load(_string((cast[seat] as Dictionary).get("voice")), "voice") as AudioStream

## Every clip of `seat` that is there: players[seat].voice, voice/member_<n>.ogg and voice/member_<n>_<k>.ogg (n = seat + 1,
## k = 1..VOICE_VARIANTS). One of them plays, at random, with that player's catchphrase.
static func voices(seat: int) -> Array:
	var names: Array = []
	var named := voice(seat)
	var result: Array = [named] if named != null else []
	names.append("voice/member_%d.ogg" % (seat + 1))
	for variant in range(1, VOICE_VARIANTS + 1): names.append("voice/member_%d_%d.ogg" % [seat + 1, variant])
	for file: String in names:
		var clip := _present(file, "voice") as AudioStream
		if clip != null and not clip in result: result.append(clip)
	return result

## The announcer's clips for `event` (one of ANNOUNCER_EVENTS): announcer/<event>_<n>.ogg, n = 1..ANNOUNCER_VARIANTS, the ones that
## are there.
static func announcer(event: String) -> Array:
	var result: Array = []
	if not event in ANNOUNCER_EVENTS: return result
	for variant in range(1, ANNOUNCER_VARIANTS + 1):
		var clip := _present("announcer/%s_%d.ogg" % [event, variant], "announcer") as AudioStream
		if clip != null: result.append(clip)
	return result

## The team wall (team_wall: up to TEAM_WALL people, each with their own opt-in photo team/member_<n>.png): [{name, picture
## (Texture2D or null), color}]. Without a photo a person shows their cast colour (the player of the same name, else a seat colour).
## [] when the cast has no team wall.
static func team_wall() -> Array:
	var result: Array = []
	for entry in _list("team_wall"):
		if result.size() >= TEAM_WALL: break
		if not entry is Dictionary: continue
		var name := _string(entry.get("name")).to_upper()
		if name == "": continue
		var color: Color = SEAT_COLORS[result.size() % SEAT_COLORS.size()]
		for seat in members().size():
			if player_name(seat) == name: color = player_color(seat)
		result.append({"name": name, "picture": _load(_string(entry.get("picture")), "team") as Texture2D, "color": color})
	return result

static func _color(value, fallback: Color) -> Color:
	if value is String and value.begins_with("#") and value.length() == 7 and Color.html_is_valid(value): return Color.html(value)
	return fallback

# ------------------------------------------------------------------ the carried thing, the logo, the floating thing

static func object_kind() -> String:
	var kind := _text("object", "kind")
	return kind if kind in OBJECT_KINDS else str(DEFAULTS["object"]["kind"])

## The carried thing's own print (object.picture), null when the cast names none or it does not load.
static func print_picture() -> Texture2D:
	return _load(_string(_section("object").get("picture"))) as Texture2D

## How the picture sits on a painting: "contain" (whole picture on the canvas, default: logos) | "cover" (fills, crops).
## The logo standing in for a missing print is always contained, and so is the glass pane's etched print.
static func picture_fit() -> String:
	return "cover" if _text("object", "fit") == "cover" and print_picture() != null else "contain"

## What the carried thing shows (the painting's picture, the pane's etched print): its print, else the team logo; null keeps
## the built-in look.
static func picture() -> Texture2D:
	var own := print_picture()
	return own if own != null else logo()

## The team logo (brand.logo), null when the cast names none or it does not load.
static func logo() -> Texture2D:
	return _load(_string(_section("brand").get("logo"))) as Texture2D

## The colour of a plate behind the logo so that it reads: near white for a dark or colourful logo, the game's ink for a pale one
## (judged from the opaque pixels; a logo without transparency counts all of them). White without a logo.
static func logo_backing() -> Color:
	var picture := logo()
	if picture == null: return Color.WHITE
	var key := "backing|%d" % picture.get_instance_id()
	if not _files.has(key):
		var image := picture.get_image()
		var light := 0.0
		var weight := 0.0
		if image != null and not image.is_empty():
			if image.is_compressed():
				image = image.duplicate() as Image
				image.decompress()
			var step := maxi(1, maxi(image.get_width(), image.get_height()) / 96)
			for y in range(0, image.get_height(), step):
				for x in range(0, image.get_width(), step):
					var pixel := image.get_pixel(x, y)
					light += pixel.get_luminance() * pixel.a
					weight += pixel.a
		_files[key] = Color("#1d2026") if weight > 0.0 and light / weight > 0.72 else Color.WHITE
	return _files[key]

## The shape of the floating thing of 3+ player rounds.
static func balloon_shape() -> String:
	var shape := _string(_section("balloon").get("shape"))
	return shape if shape in BALLOON_SHAPES else BALLOON_SHAPES[0]

## The print on the floating thing: balloon.picture, else the logo, else null.
static func balloon_picture() -> Texture2D:
	var own := _load(_string(_section("balloon").get("picture"))) as Texture2D
	return own if own != null else logo()

# ------------------------------------------------------------------ brand colours and world

## The brand colours as listed (up to 3, bad entries left out).
static func brand_colors() -> Array[Color]:
	var result: Array[Color] = []
	var listed = _section("brand").get("colors", [])
	if listed is Array:
		for value in listed:
			var color := _color(value, Color(0, 0, 0, 0))
			if result.size() < 3 and color.a > 0.0: result.append(color)
	return result

static func _chromatic(color: Color) -> bool:
	return color.s >= GREY_SATURATION and color.v >= GREY_VALUE

## The accent the UI and the flags take: the first brand colour with colour in it (greys and near black are skipped),
## clamped so it is never washed out or muddy (saturation 0.45..0.9, value 0.55..0.92). Alpha 0 when the cast has none.
static func brand_accent() -> Color:
	for color in brand_colors():
		if _chromatic(color): return Color.from_hsv(color.h, clampf(color.s, 0.45, 0.9), clampf(color.v, 0.55, 0.92))
	return Color(0, 0, 0, 0)

## How much of each room the first brand colour paints (brand.walls, style/real_look.gd), resolved: "stripe" a painted stripe along the
## walls; "accent" also the end walls, pillars, door frames and short wall pieces, the lobby's back wall; "full" every wall. The
## default "auto" (and any unknown value) is "accent" when the first brand colour is vivid, else "stripe": a black, white, grey or
## dull brand keeps the facility's own colours on the walls and shows on the stripe, signs, logo wall and posters. The white tile
## stays the base. Orange paint is fine here: the facility's hazards are lasers, metal spikes and fire.
static func brand_walls() -> String:
	var mode := _string(_section("brand").get("walls"))
	if mode in BRAND_WALLS and mode != "auto": return mode
	var colors := brand_colors()
	return "accent" if not colors.is_empty() and vivid(colors[0]) else "stripe"

## A colour strong enough to paint whole walls with (brand.walls "auto").
static func vivid(color: Color) -> bool:
	return color.s >= VIVID_SATURATION and color.v >= VIVID_VALUE and color.s * color.v >= VIVID_CHROMA

## The paint of brand.walls: the first brand colour with colour in it, as the team gave it (not clamped, orange too); alpha 0 when
## the cast has none.
static func brand_paint() -> Color:
	for color in brand_colors():
		if _chromatic(color): return color
	return Color(0, 0, 0, 0)

## The hue (0..1) the teal walls of the levels take: the first brand colour with colour in it that is clear of the hazard
## warning hues (red, orange, yellow), so hazards keep standing out. -1 keeps the template's teal.
static func wall_hue() -> float:
	for color in brand_colors():
		if _chromatic(color) and color.h > WARNING_HUES.y and color.h < WARNING_HUES.x: return color.h
	return -1.0

## "office" (city and building-site backdrops) | "outdoor" (parks and hills).
static func world_theme() -> String:
	var theme := _string(_section("world").get("theme"))
	return theme if theme in THEMES else THEMES[0]

## The show's world, resolved: "party" (the default: a bright candy world) | "night" (a dark sci-fi world, style/night_look.gd). world.style "auto" is
## "night" when the first brand colour is near black (HSV value under NIGHT_VALUE), else "party". Anything else is "party".
static func world_style() -> String:
	var style := _string(_section("world").get("style")).to_lower()
	if style == "auto":
		var colors := brand_colors()
		return "night" if not colors.is_empty() and colors[0].v < NIGHT_VALUE else "party"
	return "night" if style == "night" else "party"

# ------------------------------------------------------------------ level slots

## The sign of obstacle `index` (1-based): {label, picture (Texture2D or null), color (Color, alpha 0 for the default)}.
## No label means no board: {}.
static func obstacle(index: int) -> Dictionary:
	var entry := _entry("obstacles", index, OBSTACLES)
	var label := _string(entry.get("label")).to_upper()
	if label == "": return {}
	var color := _color(entry.get("color"), Color(0, 0, 0, 0))
	if color.a > 0.0 and color.v < NIGHT_VALUE and mode() == "show" and world_style() == "night": # a near-black plate would vanish on the night look's dark floors and walls
		color = Color.from_hsv(color.h, color.s * 0.6, 0.46)
	return {"label": label, "picture": _load(_string(entry.get("picture"))) as Texture2D, "color": color}

## Poster `index` (1-based): {picture, caption}; the picture falls back to the logo, and with neither there is no poster ({}).
static func poster(index: int) -> Dictionary:
	var own := poster_own(index)
	if not own.is_empty(): return own
	var art := scene_art()
	if index >= 1 and index <= art.size(): return art[index - 1]
	var shown: Texture2D = logo() if index == 1 else null
	return {"picture": shown, "caption": ""} if shown != null else {}

## Poster `index` (1-based) as the cast lists it (posters[i]): {picture, caption}, {} when the cast has none or the picture does not load.
static func poster_own(index: int) -> Dictionary:
	var entry := _entry("posters", index, POSTERS)
	var shown := _load(_string(entry.get("picture"))) as Texture2D
	if shown == null: return {}
	return {"picture": shown, "caption": _string(entry.get("caption")).to_upper()}

## The cast's pictures that are not its logo, in the order the walls take them: billboard_1, billboard_2, banner_1, banner_2, then the
## pictures of obstacles 1..5 (captioned with the label). Each {picture, caption}; [] for a cast with only a logo.
static func scene_art() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id: String in ["billboard_1", "billboard_2", "banner_1", "banner_2"]:
		var picture := slot_picture(id)
		if picture != null: found.append({"picture": picture, "caption": ""})
	for index in OBSTACLES:
		var sign := obstacle(index + 1)
		if not sign.is_empty() and sign.picture != null: found.append({"picture": sign.picture, "caption": str(sign.label)})
	return found

## The line on hidden board `index` (1-based), "" for none.
static func egg(index: int) -> String:
	var listed := _list("eggs")
	return _string(listed[index - 1]) if index >= 1 and index <= mini(listed.size(), EGGS) else ""

## The picture of banner / billboard slot `id` ("banner_1", "banner_2", "billboard_1", "billboard_2": that name with .png, .jpg or .webp in
## demo/cast/), null for none or any other id.
static func slot_picture(id: String) -> Texture2D:
	if not id in SLOT_PICTURES: return null
	for ending in PICTURE_ENDINGS:
		var picture := _present(id + "." + ending, "") as Texture2D
		if picture != null: return picture
	return null

# ------------------------------------------------------------------ rounds as metaphors

static func _round(round_id: String) -> Dictionary:
	var rounds = _section("show").get("rounds", {})
	var entry = rounds.get(round_id, {}) if rounds is Dictionary and round_id in ROUND_KEYS else {}
	return entry if entry is Dictionary else {}

## The cast's own `key` ("title" | "rule" | "hint") of round `round_id` ("r14".."r28", CourseSection.round_id): show.rounds.<id>.<key>, upper case and
## clipped (24 letters for a title, 48 for a rule or a hint); "" when the cast has none, the level file's own text then stands.
static func round_text(round_id: String, key: String) -> String:
	if not key in ["title", "rule", "hint"]: return ""
	var most := ROUND_TITLE_MAX if key == "title" else ROUND_LINE_MAX
	return _string(_round(round_id).get(key)).to_upper().left(most).strip_edges()

## The words round `round_id`'s main hazard wears (show.rounds.<id>.label: one text or a list of up to 8, each up to 16 letters, upper case);
## empty for none, and for a round that takes no label (r15, r17, r21, r23 only).
static func round_labels(round_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not "label" in (ROUND_KEYS.get(round_id, []) as Array): return result
	var listed = _round(round_id).get("label")
	var items: Array = listed if listed is Array else [listed]
	for item in items:
		var text := _string(item).to_upper().left(ROUND_LABEL_MAX).strip_edges()
		if text != "" and result.size() < ROUND_LABELS: result.append(text)
	return result

## The model of round `round_id` (r21: the spin bars, r23: the balls): demo/cast/round_<id>.glb when show.rounds.<id>.model names exactly that file, as
## a new Node3D each call (long axis +X, origin at the centre, +Y up; the round fits it, style/hero_prop.gd fit_into). Null for none or when it
## does not load: the round keeps its default look.
static func round_model(round_id: String) -> Node3D:
	if not round_id in ROUND_MODELS: return null
	var file := "round_%s.glb" % round_id
	if _string(_round(round_id).get("model")) != file: return null
	return _glb_model(PICTURE_DIR + file)

## The cast's own crown (demo/cast/crown.glb, any glTF binary), a fresh instance each call; null when there is none or it does not load
## (style/show_crown.gd falls back to the built-in crown). An imported file loads as a scene; one just dropped in is read directly.
static func crown_model() -> Node3D:
	return _glb_model(PICTURE_DIR + CROWN_FILE)

## The cast's hero prop (demo/cast/hero_prop.glb, any glTF binary), a fresh instance each call; null when there is none or it does not
## load (style/hero_prop.gd then builds the stand in the brand colours). Loaded like the crown.
static func hero_prop_model() -> Node3D:
	return _glb_model(PICTURE_DIR + HERO_PROP_FILE)

static func _glb_model(path: String) -> Node3D:
	if not _exists(path): return null
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		return scene.instantiate() as Node3D if scene != null else null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK: return null
	return document.generate_scene(state) as Node3D

static func _entry(key: String, index: int, most: int) -> Dictionary:
	var listed := _list(key)
	if index < 1 or index > mini(listed.size(), most): return {}
	return listed[index - 1] if listed[index - 1] is Dictionary else {}

# ------------------------------------------------------------------ show items

const ITEM_TEXT_MAX := {"name": 16, "banner": 30, "line": 48, "pass": 48, "pop": 30}
const ITEM_DIR := "items" ## demo/cast/items/: the clips and the media of the show's items (voice, sfx, media of show.items[])
const ITEM_TUNING_MAX := 8

## The cast's `show.item_lab`: true turns the item lab on (the keys 1-7 hand the local player an item or event, docs/items.md "Item lab"). False when the cast says nothing.
static func show_item_lab() -> bool:
	return _section("show").get("item_lab") == true

## The cast's entry for the show item or event `id` (show.items[] with that id): texts clipped to ITEM_TEXT_MAX and upper case (the line and the pass line keep {user} and {victim} as written),
## `off` (true: the item is not in this show), `voice`, `sfx` and `media` as file names under items/ (checked as plain names), `tuning` numbers only. {} when the cast has none.
## Which keys and ranges an id takes is modes/show/items/items.json (modes/show/items/catalog.gd clamps).
static func show_item(id: String) -> Dictionary:
	var listed = _section("show").get("items", [])
	if not listed is Array: return {}
	for entry in listed:
		if not entry is Dictionary or _string(entry.get("id")) != id: continue
		var result := {"off": entry.get("off") == true}
		for key: String in ITEM_TEXT_MAX:
			var text := _string(entry.get(key))
			if text != "": result[key] = (text if key == "line" or key == "pass" else text.to_upper()).left(int(ITEM_TEXT_MAX[key])).strip_edges()
		for key in ["voice", "sfx", "media"]:
			var file := _string(entry.get(key))
			if _cast_file(file, ITEM_DIR) and file.begins_with(ITEM_DIR + "/"): result[key] = file
		var tuning := {}
		var numbers = entry.get("tuning", {})
		if numbers is Dictionary:
			for key in numbers:
				if (numbers[key] is float or numbers[key] is int) and tuning.size() < ITEM_TUNING_MAX: tuning[str(key)] = float(numbers[key])
		result["tuning"] = tuning
		return result
	return {}

## The cast's `show.tandem` (the TANDEM experiment, docs/party-show.md "Tandem (experiment)"): {off, name, banner, line}, the texts clipped to ITEM_TEXT_MAX and upper case (`line` keeps {a} and {b} as written). {} when the cast has none.
static func show_tandem() -> Dictionary:
	var entry = _section("show").get("tandem")
	if not entry is Dictionary: return {}
	var result := {"off": entry.get("off") == true}
	for key: String in ITEM_TEXT_MAX:
		var text := _string(entry.get(key))
		if text != "": result[key] = (text if key == "line" else text.to_upper()).left(int(ITEM_TEXT_MAX[key])).strip_edges()
	return result

# ------------------------------------------------------------------ the manager (experiment)

const MANAGER_TEXT_MAX := {"title": 24, "line": 48, "you": 48, "prompt": 24, "waiting": 48, "made": 48} ## `show.manager` texts: the longest (characters)
const MANAGER_RULE_TEXT_MAX := {"name": 16, "banner": 30, "line": 48} ## `show.manager.rules[]` texts
const MANAGER_TUNING_MAX := 4

## The cast's `show.manager`: `off` (true: no manager in this show), the texts clipped to MANAGER_TEXT_MAX (title and prompt upper case, the lines keep {manager} as written) and
## `rules`: id -> {name, banner (upper case), line, off, tuning (numbers)} from `show.manager.rules[]`. {} when the cast has none. The ids, defaults and ranges are modes/show/shared/manager/manager.json.
static func show_manager() -> Dictionary:
	var section = _section("show").get("manager", {})
	if not section is Dictionary: return {}
	var result := {"off": section.get("off") == true, "rules": {}}
	for key: String in MANAGER_TEXT_MAX:
		var text := _string(section.get(key))
		if text != "": result[key] = (text.to_upper() if key == "title" or key == "prompt" else text).left(int(MANAGER_TEXT_MAX[key])).strip_edges()
	var listed = section.get("rules", [])
	if listed is Array:
		for entry in listed:
			if not entry is Dictionary or _string(entry.get("id")) == "": continue
			var rule := {"off": entry.get("off") == true}
			for key: String in MANAGER_RULE_TEXT_MAX:
				var text := _string(entry.get(key))
				if text != "": rule[key] = (text if key == "line" else text.to_upper()).left(int(MANAGER_RULE_TEXT_MAX[key])).strip_edges()
			var tuning := {}
			var numbers = entry.get("tuning", {})
			if numbers is Dictionary:
				for key in numbers:
					if (numbers[key] is float or numbers[key] is int) and tuning.size() < MANAGER_TUNING_MAX: tuning[str(key)] = float(numbers[key])
			rule["tuning"] = tuning
			(result.rules as Dictionary)[_string(entry.get("id"))] = rule
	return result

## A file of demo/cast/items/ by its name in the cast ("items/call.ogv"): a sound (.ogg) as an AudioStream, null when it is not there or does not load; a video (.ogv) as its
## res:// path, "" when it is not there.
static func item_file(file: String) -> Variant:
	if not file.begins_with(ITEM_DIR + "/") or not _cast_file(file, ITEM_DIR): return "" if file.ends_with(".ogv") else null
	if file.ends_with(".ogv"): return PICTURE_DIR + file if _exists(PICTURE_DIR + file) else ""
	return _present(file, ITEM_DIR)

## The cast's `show.pigeon` (GHOST PIGEON, docs/pigeon.md): {off, banner, coo, splat, line, drop_line, tuning}. The texts are clipped to PIGEON_TEXT_MAX (upper case, but `line` and `drop_line`
## keep {user} and {victim} as written), `off` true takes the experiment out of this show, `tuning` numbers only (modes/show/shared/pigeon/pigeon_catalog.gd clamps them). {} when the cast has none.
const PIGEON_TEXT_MAX := {"banner": 30, "coo": 16, "splat": 16, "line": 48, "drop_line": 48}
static func show_pigeon() -> Dictionary:
	var entry = _section("show").get("pigeon", {})
	if not entry is Dictionary: return {}
	var result := {"off": entry.get("off") == true}
	for key: String in PIGEON_TEXT_MAX:
		var text := _string(entry.get(key))
		if text != "": result[key] = (text if key.ends_with("line") else text.to_upper()).left(int(PIGEON_TEXT_MAX[key])).strip_edges()
	var tuning := {}
	var numbers = entry.get("tuning", {})
	if numbers is Dictionary:
		for key in numbers:
			if (numbers[key] is float or numbers[key] is int) and tuning.size() < ITEM_TUNING_MAX: tuning[str(key)] = float(numbers[key])
	result["tuning"] = tuning
	return result

# ------------------------------------------------------------------ music and video

## The id of the gameplay loop: the cast's `music` when demo/audio/music/friends-<id>.ogg (or .wav) exists, else the default.
static func music_id() -> String:
	var id := _string(data().get("music"))
	return id if _plain(id) and (_exists(MUSIC_DIR + "friends-%s.ogg" % id) or _exists(MUSIC_DIR + "friends-%s.wav" % id)) else DEFAULT_MUSIC

static func music_path() -> String:
	var path := MUSIC_DIR + "friends-%s.ogg" % music_id()
	return path if _exists(path) else MUSIC_DIR + "friends-%s.wav" % music_id()

## The cast's video for `kind` ("intro" before the first level, "win" on the results), "" when it names none or the file
## is not there.
static func video_path(kind: String) -> String:
	if not kind in VIDEOS: return ""
	var file := _string(_section("video").get(kind))
	if not _cast_file(file, "video") or not file.ends_with(".ogv"): return ""
	var path := PICTURE_DIR + file
	return path if _exists(path) else ""

# ------------------------------------------------------------------ plain margins

const EDGE_TOLERANCE := 26   ## per channel (0..255): a pixel this close to the edge colour is background
const EDGE_PLAIN := 0.92     ## share of the edge ring that must be background for the edge to count as plain
const TRIM_MIN := 0.08       ## margins thinner than this share of the picture (on every side) are left alone

## The RGBA8 bytes and size of a picture, decompressed; [] when it cannot be read.
static func _pixels(picture: Texture2D) -> Array:
	var image := picture.get_image()
	if image == null or image.is_empty(): return []
	if image.is_compressed():
		image = image.duplicate() as Image
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
	return [image.get_data(), image.get_width(), image.get_height()]

## {plain: bool, colour: Color (the edge colour), rect: Rect2i (the box of pixels that differ from it)} of a picture, cached. A transparent
## picture counts as plain with a transparent edge; its rect is the box of its visible pixels.
static func _edge_info(picture: Texture2D) -> Dictionary:
	var key := "edge|%d" % picture.get_instance_id()
	if _files.has(key): return _files[key]
	var info := {"plain": false, "trims": false, "colour": Color(0, 0, 0, 0), "rect": Rect2i(0, 0, picture.get_width(), picture.get_height())}
	var data := _pixels(picture)
	if not data.is_empty():
		var bytes: PackedByteArray = data[0]
		var width: int = data[1]
		var height: int = data[2]
		var sides: Array = [[], [], [], []] # top row, bottom row, left column, right column (pixel numbers)
		var step := maxi(1, maxi(width, height) / 512)
		for x in range(0, width, step):
			sides[0].append(x)
			sides[1].append((height - 1) * width + x)
		for y in range(0, height, step):
			sides[2].append(y * width)
			sides[3].append(y * width + width - 1)
		var channels: Array = [[], [], [], []]
		var count := 0
		for side: Array in sides:
			for at: int in side:
				count += 1
				for c in 4: channels[c].append(bytes[at * 4 + c])
		var edge := PackedInt32Array()
		for c in 4:
			(channels[c] as Array).sort()
			edge.append((channels[c] as Array)[count / 2])
		var plain_sides: Array[bool] = []
		for side: Array in sides:
			var near := 0
			for at: int in side:
				if not _differs(bytes, at * 4, edge): near += 1
			plain_sides.append(float(near) / side.size() >= EDGE_PLAIN)
		info.plain = not plain_sides.has(false)
		info.trims = plain_sides.has(true)
		info.colour = Color8(edge[0], edge[1], edge[2], edge[3])
		if info.trims:
			var sample := maxi(1, maxi(width, height) / 256)
			var top := height
			var bottom := -1
			var left := width
			var right := -1
			for y in range(0, height, sample):
				var seen := 0
				for x in range(0, width, sample):
					if _differs(bytes, (y * width + x) * 4, edge):
						seen += 1
						left = mini(left, x)
						right = maxi(right, x)
				if seen >= 2:
					top = mini(top, y)
					bottom = maxi(bottom, y)
			if bottom >= 0:
				# a side that is not plain (content runs off that edge) is not trimmed
				var x0 := left if plain_sides[2] else 0
				var x1 := right + sample if plain_sides[3] else width
				var y0 := top if plain_sides[0] else 0
				var y1 := bottom + sample if plain_sides[1] else height
				info.rect = Rect2i(x0, y0, mini(x1, width) - x0, mini(y1, height) - y0)
	_files[key] = info
	return info

static func _differs(bytes: PackedByteArray, at: int, edge: PackedInt32Array) -> bool:
	if edge[3] < 128: return bytes[at + 3] > 24
	for c in 3:
		if absi(bytes[at + c] - edge[c]) > EDGE_TOLERANCE: return true
	return false

## True when the picture's edge is one plain colour (or transparent): a picture on a flat background, whose margins can be stretched.
static func plain_edge(picture: Texture2D) -> bool:
	return picture != null and _edge_info(picture).plain

## The picture without the plain margins around its content, `pad` (share of the content's size) left on every side; the picture itself when
## no edge of it is plain or the margins are thin (under TRIM_MIN of the picture on every side). Cached.
static func trimmed(picture: Texture2D, pad := 0.05) -> Texture2D:
	if picture == null: return null
	var key := "trim|%d|%s" % [picture.get_instance_id(), pad]
	if _files.has(key): return _files[key]
	var result := picture
	var info := _edge_info(picture)
	if info.trims:
		var width := picture.get_width()
		var height := picture.get_height()
		var box: Rect2i = info.rect
		var margin := maxf(maxf(box.position.x / float(width), box.position.y / float(height)), maxf((width - box.end.x) / float(width), (height - box.end.y) / float(height)))
		if margin >= TRIM_MIN:
			var grow := roundi(maxf(box.size.x, box.size.y) * pad)
			var area := box.grow(grow).intersection(Rect2i(0, 0, width, height))
			var image := picture.get_image()
			if image != null and not image.is_empty():
				if image.is_compressed():
					image = image.duplicate() as Image
					image.decompress()
				var cut := image.get_region(area)
				cut.generate_mipmaps()
				result = ImageTexture.create_from_image(cut)
	_files[key] = result
	return result

# ------------------------------------------------------------------ files

static func _plain(name: String) -> bool:
	return name != "" and not name.contains("..") and not name.contains("/") and not name.contains("\\") and not name.begins_with(".")

## A file name inside demo/cast/: plain, or in the one sub-folder `folder` ("voice/member_1.ogg").
static func _cast_file(name: String, folder := "") -> bool:
	if folder != "" and name.begins_with(folder + "/"): return _plain(name.trim_prefix(folder + "/"))
	return _plain(name)

static func _exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

## A cast file found by its fixed name: loaded when it is there, null (and no warning) when it is not.
static func _present(file: String, folder: String) -> Resource:
	return _load(file, folder) if _cast_file(file, folder) and _exists(PICTURE_DIR + file) else null

## A cast picture (Texture2D) or sound (AudioStream) by file name, loaded once; null when it is missing or does not load.
## Files the engine has not imported yet (a picture just dropped in) are read directly. Pictures longer than MAX_PICTURE px
## are scaled down.
static func _load(file: String, folder := "") -> Resource:
	if not _cast_file(file, folder): return null
	if _files.has(file): return _files[file]
	var path := PICTURE_DIR + file
	if folder == "" and file.get_extension().to_lower() in PICTURE_ENDINGS:
		var keyed := PREPARED_DIR + file.get_basename() + ".png" # the cast prep's copy without the opaque background, when it made one
		if _exists(keyed): path = keyed
	var result: Resource = null
	if ResourceLoader.exists(path): result = load(path)
	elif FileAccess.file_exists(path):
		if file.ends_with(".ogg"): result = AudioStreamOggVorbis.load_from_file(path)
		else:
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty(): result = ImageTexture.create_from_image(image)
	if result is Texture2D and maxi(result.get_width(), result.get_height()) > MAX_PICTURE:
		var image: Image = (result as Texture2D).get_image()
		if image != null:
			if image.is_compressed(): image.decompress()
			var scale := float(MAX_PICTURE) / maxi(image.get_width(), image.get_height())
			image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
			result = ImageTexture.create_from_image(image)
	if not (result is Texture2D or result is AudioStream):
		push_warning("Team cast file not found or not loadable: " + path)
		result = null
	_files[file] = result
	return result
