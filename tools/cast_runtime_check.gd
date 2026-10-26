extends SceneTree
## In-engine check of the team cast and of every script it feeds. Needs no level build or window, so it runs on a bare template:
##
##   "$SUMMER" --headless --path demo -s "$PWD/tools/cast_runtime_check.gd"
##
## 1. Every .gd under res:// compiles (a cast edit can never be the cause, but a broken template is found before a run).
## 2. res://cast/cast.json is a team-cast-v2 (or v1) file and every value the game reads from it resolves; every file it names
##    (logo, print, balloon, sign and poster pictures, voice clips, videos) loads, and the painting atlas and the glass pane's etched print are built from the print or logo.
## 3. The frames (style/slot_frames.gd) of every level's slots and of the lobby yard are built from the cast: exactly the slots the
##    cast fills, each with its board and face.
## 4. The catchphrase bubbles (client/cast_bubbles.gd) pop over the right courier on a break and for everyone with a line at the goal;
##    the results screen shows the team's credit line exactly when the cast has a credit_link, and words.reveal only on a
##    delivered run; the floating thing
##    (balloon/balloon_look.gd) takes the cast's shape and shows its print.
## 5. The team pack: every file in announcer/, voice/ and team/ loads; the announcer (client/cast_announcer.gd) speaks on start,
##    zap, break, pop, goal / perfect and near_drop (balloon and painting) when the cast has those lines, one at a time; the intro's
##    once-per-device flag sets and clears.
## 6. A broken cast (wrong types everywhere) and a v1 cast still resolve field by field to the defaults: the cast never stops the game.
## 7. Every music id (demo/audio/music/friends-<id>.ogg or .wav) resolves from a cast's `music` and loads as a repeating stream;
##    an Ogg Vorbis loop also loads as the engine's imported resource.
## 8. Rounds as metaphors (show.rounds, docs/swappables.md): the TeamCast accessors (text upper-cased and clipped, keys a round does not take give
##    nothing, labels capped, a model only from its own file), CourseSection.round_id / level_title / level_rule / level_hint with and without
##    an override (POSTER RUSH is one round, r17), the lobby's round list keeps its rounds whatever they are called, HeroProp.fit_into fits
##    evenly inside a box, and the labelled step tile (style/step_tile_look.gd) deals its words and lays its letters inside the card.
## One step per frame; a step stopped by a script error counts as a failure. Prints CAST_RUNTIME_CHECK ok=<bool> and exits 0 only when
## everything passed.
const TeamCast := preload("res://style/team_cast.gd")
const CarryItem := preload("res://style/carry_item.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const LevelData := preload("res://levels/level_data.gd")
const LobbySpace := preload("res://lobby_space.gd")
const LobbyVisuals := preload("res://lobby_visuals.gd")
const Hazards := preload("res://levels/hazards.gd")
const CastBubbles := preload("res://client/cast_bubbles.gd")
const GameAudio := preload("res://game/game_audio.gd")
const CastAnnouncer := preload("res://client/cast_announcer.gd")
const CastVideo := preload("res://client/cast_video.gd")
const CourseSection := preload("res://course_section.gd")
const RoundList := preload("res://modes/lineup/round_list.gd")
const HeroProp := preload("res://style/hero_prop.gd")
const ShowCrown := preload("res://style/show_crown.gd")
const StepTileLook := preload("res://style/step_tile_look.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const SKIP_DIRS := ["res://.godot", "res://.summer", "res://test_lab"]
const STEPS := ["_compile", "_check_cast", "_check_frames", "_check_bubbles", "_check_credit", "_check_balloon", "_check_pack", "_check_announcer",
	"_check_broken_cast", "_check_music", "_check_rounds"]
var failures: Array[String] = []
var _step := 0
var _done := {}

func _process(_delta: float) -> bool:
	if _step < STEPS.size():
		var name: String = STEPS[_step]
		_step += 1
		call(name)
		if not _done.has(name): failures.append("step stopped by a script error: " + name)
		return false
	for failure in failures: printerr("CAST_RUNTIME_CHECK_FAIL ", failure)
	print("CAST_RUNTIME_CHECK ok=", failures.is_empty(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
	return true

func _compile() -> void:
	_compile_scripts("res://")
	_done["_compile"] = true

func _compile_scripts(dir: String) -> void:
	if dir.trim_suffix("/") in SKIP_DIRS: return
	for sub in DirAccess.get_directories_at(dir): _compile_scripts(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"): continue
		var path := dir.path_join(file)
		var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate(): failures.append("script does not compile: " + path)

# ------------------------------------------------------------------ 2. the cast

## The file name the cast gives `section`.`key`, "" for none.
func _named(section: String, key: String) -> String:
	var part = TeamCast.data().get(section, {})
	return str(part.get(key)) if part is Dictionary and part.get(key) is String else ""

## The file name of entry `index` (0-based) of the list `key`, "" for none.
func _listed(key: String, index: int) -> String:
	var listed = TeamCast.data().get(key, [])
	if not listed is Array or index >= listed.size() or not listed[index] is Dictionary: return ""
	return str(listed[index].get("picture")) if listed[index].get("picture") is String else ""

func _check_cast() -> void:
	if not FileAccess.file_exists(TeamCast.PATH):
		failures.append("missing " + TeamCast.PATH)
		return
	if TeamCast.data().is_empty(): failures.append("cast is not a %s file: %s" % [" or ".join(TeamCast.FORMATS), TeamCast.PATH])
	if TeamCast.team_name().is_empty(): failures.append("empty team name")
	for key in TeamCast.DEFAULTS["words"].keys():
		if TeamCast.word(key).is_empty(): failures.append("empty word " + key)
	for seat in TeamCast.members().size():
		var member := TeamCast.player(seat)
		var named := str((TeamCast.members()[seat] as Dictionary).get("voice", ""))
		var clip := TeamCast.voice(seat)
		if named != "" and clip == null: failures.append("players[%d].voice does not load: res://cast/%s" % [seat, named])
		print("CAST_MEMBER seat=", seat, " name=", member["name"], " title=", member["title"], " color=", Color(member["color"]).to_html(false), " catchphrase=", member["catchphrase"], " voice=", clip != null)
	if _named("brand", "logo") != "" and TeamCast.logo() == null: failures.append("brand.logo does not load: res://cast/" + _named("brand", "logo"))
	if _named("object", "picture") != "" and TeamCast.print_picture() == null: failures.append("object.picture does not load: res://cast/" + _named("object", "picture"))
	if _named("balloon", "picture") != "" and TeamCast.balloon_picture() == null: failures.append("balloon.picture does not load: res://cast/" + _named("balloon", "picture"))
	for index in TeamCast.OBSTACLES:
		if _listed("obstacles", index) != "" and TeamCast.obstacle(index + 1).get("picture") == null:
			failures.append("obstacles[%d].picture does not load (or the sign has no label): res://cast/%s" % [index, _listed("obstacles", index)])
	for index in TeamCast.POSTERS:
		if _listed("posters", index) != "" and TeamCast._load(_listed("posters", index)) == null:
			failures.append("posters[%d].picture does not load: res://cast/%s" % [index, _listed("posters", index)])
	for kind: String in TeamCast.VIDEOS:
		if _named("video", kind) != "" and TeamCast.video_path(kind) == "": failures.append("video.%s is not in demo/cast/: %s" % [kind, _named("video", kind)])
	var music := TeamCast.music_path()
	if not (ResourceLoader.exists(music) or FileAccess.file_exists(music)): failures.append("music is missing: " + music)
	if TeamCast.picture() != null:
		var atlas := CarryItem.picture()
		if atlas == null or atlas.get_size() != Vector2(512, 404): failures.append("painting atlas was not built from the cast picture")
		var etched := CarryItem.etched_picture()
		if etched == null or etched.get_size() != Vector2(1024, 512): failures.append("the glass pane's etched print was not built from the cast picture")
	# every letter of the cast's text is drawn: by the game's fonts, else by the cast fonts (tools/cast_fonts.py), also through
	# a FontVariation (the interface's Inter weights)
	TeamCast.use_fonts()
	var display := FontVariation.new()
	display.base_font = load("res://assets/fonts/Inter.ttf")
	display.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 800}
	var undrawn := {}
	for letter: String in _letters(TeamCast.data()):
		var code := letter.unicode_at(0)
		for font: Font in [display, load("res://assets/fonts/Archivo.ttf") as Font]:
			if code > 32 and not font.has_char(code): undrawn[letter] = true
	if not undrawn.is_empty(): failures.append("letters of the cast no font draws (run tools/cast_fonts.py): " + "".join(undrawn.keys()))
	# one game, one mode: only the cast's circle (run) shows and can be stood on; an unknown run is TIME ATTACK
	var lobby: GDScript = load("res://network/walk_in_lobby.gd")
	var courses: GDScript = load("res://course_section.gd")
	for run: String in ["time_attack", "endless", "bogus"]:
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "Run"}, "players": [{"name": "Ida"}], "run": run})
		var shown: Array = lobby.shown_pads()
		var hidden: String = courses.ADVENTURE if run == "endless" else courses.CHALLENGE
		var expected: String = courses.CHALLENGE if run == "endless" else courses.ADVENTURE
		if shown.size() != 1 or shown[0].course != expected or lobby.zone_at(shown[0].center) != expected or lobby.zone_at(lobby.center(hidden)) != "":
			failures.append("run %s does not show exactly its one circle: %s" % [run, shown.map(func(p): return p.course)])
	TeamCast.override({})
	# a transparent picture sits on the canvas colour, not on black
	var clear := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	var on_canvas := CarryItem.cast_atlas(Image.create_empty(512, 404, false, Image.FORMAT_RGB8), clear, false).get_image()
	var centre := on_canvas.get_pixelv(CarryItem.PICTURE_RECTS["landscape"].get_center())
	if not centre.is_equal_approx(Color(CarryItem.CANVAS.r, CarryItem.CANVAS.g, CarryItem.CANVAS.b)): failures.append("a transparent picture is not on the canvas colour: %s" % centre)
	if TeamCast.logo() != null and SlotFrames.card(TeamCast.logo()) == null: failures.append("no logo card for the goal sign")
	for picture: Texture2D in [TeamCast.logo(), TeamCast.print_picture(), TeamCast.balloon_picture()]:
		var pixels := picture.get_image() if picture != null else null
		if picture != null and (pixels == null or pixels.is_empty()): failures.append("a cast picture loads but its pixels cannot be read: " + picture.resource_path)
	var accent := TeamCast.brand_accent()
	print("CAST team=", TeamCast.team_name(), " format=", TeamCast.data().get("format", ""), " object=", TeamCast.object_kind(), " members=", TeamCast.members().size(),
		" print=", TeamCast.print_picture() != null, " logo=", TeamCast.logo() != null, " accent=", accent.to_html(false) if accent.a > 0.0 else "none",
		" wall_hue=", snappedf(TeamCast.wall_hue(), 0.01), " theme=", TeamCast.world_theme(), " balloon=", TeamCast.balloon_shape(), "/", TeamCast.balloon_picture() != null,
		" music=", TeamCast.music_id(), " intro=", TeamCast.video_path("intro") != "", " win=", TeamCast.video_path("win") != "", " credit=", TeamCast.credit_link())
	var team = TeamCast.data().get("team", {})
	if team is Dictionary and str(team.get("credit_link", "")) != "" and TeamCast.credit_link() == "": failures.append("team.credit_link is not an https:// link")
	_done["_check_cast"] = true

# ------------------------------------------------------------------ 3. the frames

## Whether the cast fills slot `id` (what SlotFrames must build).
## Every letter of every text value of the cast.
func _letters(value) -> Array:
	var result := []
	if value is String:
		for i in (value as String).length(): result.append((value as String)[i])
	elif value is Dictionary:
		for key in value: result.append_array(_letters(value[key]))
	elif value is Array:
		for item in value: result.append_array(_letters(item))
	return result

func _filled(id: String) -> bool:
	if id == "team_wall": return not TeamCast.team_wall().is_empty()
	if id == "logo_wall": return true
	if id.begins_with("obstacle_"): return not TeamCast.obstacle(int(id.trim_prefix("obstacle_"))).is_empty()
	if id.begins_with("poster_"): return not TeamCast.poster(int(id.trim_prefix("poster_"))).is_empty()
	if id.begins_with("egg_"): return TeamCast.egg(int(id.trim_prefix("egg_"))) != ""
	# the show's frames: arches, banners, floor decals, the crown and the hero prop stand are always there (the team name, else the built-in crown / stand);
	# a billboard needs its picture or the logo
	if id.begins_with("arch_") or id.begins_with("banner_") or id.begins_with("floor_") or id == "crown" or id == "hero_prop": return true
	if id.begins_with("billboard_"): return TeamCast.slot_picture(id) != null or TeamCast.logo() != null
	return false

func _frames(label: String, slots: Array, blocks: Array) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var built := SlotFrames.build(holder, slots, blocks)
	var expected := 0
	var standing := 0
	for slot: Dictionary in slots:
		var door := str(slot.get("door", "")) != "" # a poster door always stands (the logo poster, and the problem posters in the default look), whatever the cast filled; the ids of a door row repeat
		var filled := door or _filled(str(slot.id))
		var frame := holder.get_node_or_null("Slot_" + str(slot.id))
		if filled: expected += 1
		if not door and filled != (frame != null): failures.append("%s slot %s: %s" % [label, slot.id, "not built" if filled else "built for an empty slot"])
		if frame != null:
			var show_slot := door or ["arch_", "banner_", "billboard_", "floor_", "crown", "hero_prop"].any(func(prefix: String) -> bool: return str(slot.id).begins_with(prefix)) # the show's frames are built differently (style/slot_frames.gd)
			if not show_slot and (frame.get_node_or_null("Board") == null or frame.get_node_or_null("Face") == null): failures.append("%s slot %s has no board or face" % [label, slot.id])
			if frame.get_node_or_null("Post") != null: standing += 1
	print("CAST_SLOTS ", label, " slots=", slots.size(), " built=", built, " expected=", expected, " standing=", standing)
	if built != expected: failures.append("%s: %d frames built, %d expected" % [label, built, expected])
	holder.free()

func _check_frames() -> void:
	for number in range(1, LevelData.count() + 1):
		var level := LevelData.load_level(number)
		_frames("level=%d" % number, level.get("slots", []), level.get("blocks", []))
	var blocks: Array = []
	for row: Dictionary in LobbySpace.architecture():
		var at: Vector3 = row.center
		var size: Vector3 = row.size
		blocks.append(Hazards.block({"k": "box", "p": [at.x, at.y, at.z], "s": [size.x, size.y, size.z], "r": [0.0, float(row.yaw), 0.0]}))
	var wall := LobbyVisuals._wall_slots()
	_frames("lobby", wall, blocks)
	# the lobby walls: the logo hangs once (never again on a poster or the easel) and no frame reaches the bunting above them
	var logo := TeamCast.logo()
	var art := LobbyVisuals._wall_art()
	if logo != null and art.easel == logo: failures.append("lobby: the easel shows the logo again")
	for slot: Dictionary in wall:
		if logo != null and slot.has("poster") and (slot.poster as Dictionary).picture == logo: failures.append("lobby slot %s shows the logo again" % slot.id)
		var top: float = (slot.p as Vector3).y + (slot.size as Vector2).y * 0.5
		if top > LobbyVisuals.BUNTING_HEIGHT - 0.3 - 0.46: failures.append("lobby slot %s reaches the bunting (top %.2f m)" % [slot.id, top])
	_done["_check_frames"] = true

# ------------------------------------------------------------------ 4. the catchphrase bubbles

## The few fields of a game run the bubbles and the announcer read (game/game_run.gd, game/team_play.gd, levels/level_world.gd).
class FakeRun extends Node3D:
	var actors: Array = []
	var rigs: Array = []
	var world: Node3D
	var breaks_by_slot: Array = [0, 0]
	var round_mode := "level"
	var play_mode := "carry"
	var course_plan := {"level": 0}
	var team := FakeTeam.new()
	var level_world := FakeLevels.new()

class FakeTeam extends RefCounted:
	var scorches := PackedInt32Array([0, 0, 0, 0])
	var view := BalloonSim.new()

class FakeLevels extends RefCounted:
	var active_level := 0
	func floor_y(_k: int, _feet: Vector3) -> float: return 0.0

func _check_bubbles() -> void:
	var run := FakeRun.new()
	run.world = Node3D.new()
	run.add_child(run.world)
	for slot in 2:
		var body := CharacterBody3D.new()
		run.world.add_child(body)
		body.position = Vector3(slot * 3.5, 0.0, 0.0)
		run.actors.append(body)
		run.rigs.append(null)
	root.add_child(run)
	var bubbles := CastBubbles.new()
	root.add_child(bubbles)
	bubbles.simulation = run
	var lines := [str(TeamCast.player(0).catchphrase) != "", str(TeamCast.player(1).catchphrase) != ""]
	bubbles.observe({"breaks": 0, "resets": 0, "won": false})
	run.breaks_by_slot = [0, 1]
	bubbles.observe({"breaks": 1, "resets": 0, "won": false, "failure_kind": "break"})
	var after_break: int = bubbles._bubbles.size()
	bubbles.observe({"breaks": 1, "resets": 1, "won": true})
	var after_goal: int = bubbles._bubbles.size()
	for frame in 10: bubbles._process(0.1)
	var shown := 0
	for bubble: Dictionary in bubbles._bubbles:
		if is_instance_valid(bubble.node) and (bubble.node as Node3D).visible: shown += 1
	print("CAST_BUBBLES break=", after_break, " goal=", after_goal, " shown=", shown)
	if after_break != (1 if lines[1] else 0): failures.append("a break by seat 1 popped %d bubbles" % after_break)
	if after_goal != int(lines[0]) + int(lines[1]): failures.append("the goal popped %d bubbles for %d lines" % [after_goal, int(lines[0]) + int(lines[1])])
	if after_goal > 0 and shown == 0: failures.append("no bubble shows a second after the goal")
	bubbles.free()
	run.free()
	_done["_check_bubbles"] = true

## The credit line of the results screen (client/online_screens.gd): shown with the team name and link only when the cast has a link.
func _check_credit() -> void:
	var menu_style = load("res://client/menu_style.gd")
	menu_style.set_asset_reader(func(path: String) -> Resource: return ResourceLoader.load(path) if ResourceLoader.exists(path) else null) # as the lab does
	var screens: Control = load("res://client/online_screens.gd").new()
	var credit := screens.find_child("Credit", true, false) as Button
	var link := TeamCast.credit_link()
	if credit == null: failures.append("the results screen has no credit line")
	elif credit.visible != (link != ""): failures.append("the credit line is %s without a credit_link" % ("shown" if credit.visible else "hidden"))
	elif link != "" and not (credit.text.contains(TeamCast.team_name()) and credit.text.contains(link.trim_prefix("https://").trim_suffix("/"))): failures.append("the credit line misses the team or link: " + credit.text)
	# a watermark, not a button: flat, no plate in any state, half see-through type
	if credit != null:
		if not credit.flat: failures.append("the credit line is not flat")
		for state: String in ["normal", "hover", "pressed", "focus"]:
			if not credit.get_theme_stylebox(state) is StyleBoxEmpty: failures.append("the credit line has a plate in its %s state" % state)
		var tint := credit.get_theme_color("font_color")
		if tint.a < 0.3 or tint.a > 0.5: failures.append("the credit watermark's alpha is %.2f, not 0.3-0.5" % tint.a)
		if credit.mouse_default_cursor_shape != Control.CURSOR_POINTING_HAND: failures.append("the credit line has no hand cursor")
	var invite := screens.find_child("CreditInvite", true, false) as Label
	if invite == null or invite.visible != (link != ""): failures.append("\"Make one for your team\" is not shown exactly with the credit line")
	var title := screens.find_child("TeamTitle", true, false) as Label
	if title == null or title.visible != TeamCast.has_title() or (TeamCast.has_title() and title.text != TeamCast.title()):
		failures.append("the results do not show the team title exactly when the cast has one")
	var lines: PackedStringArray = load("res://client/menu_skin.gd").title_lines(TeamCast.title())
	if lines.is_empty() or lines.size() > 2 or " ".join(lines) != TeamCast.title(): failures.append("the title screen splits the title wrongly: %s" % lines)
	print("CAST_CREDIT shown=", credit != null and credit.visible, " text=", credit.text if credit != null else "", " title=", TeamCast.title(), " lines=", lines)
	# a link with a trailing slash is shown without it
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Slash", "credit_link": "https://www.summerengine.com/"}, "players": [{"name": "Ida"}]})
	var slashed: Control = load("res://client/online_screens.gd").new()
	var slashed_credit := slashed.find_child("Credit", true, false) as Button
	if slashed_credit == null or not slashed_credit.visible or not slashed_credit.text.ends_with("·  www.summerengine.com"):
		failures.append("a credit_link with a trailing slash is not shown: %s" % (slashed_credit.text if slashed_credit != null else "no credit line"))
	slashed.free()
	# words.reveal: big on the results in place of the delivered word, only when the run was delivered
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Gift"}, "players": [{"name": "Ida"}], "words": {"reveal": " Will you marry me? "}})
	var headline: Label = screens.get("_results_headline")
	var row := {"seat": 0, "name": "IDA", "arrived": true, "time": 31.0, "breaks": 0}
	var shown := []
	for model: Dictionary in [{"rows": [row]}, {"rows": [row.merged({"arrived": false}, true)], "headline": "ROUND ENDED"},
			{"rows": [row], "run": {"finished": true, "times": [31.0]}, "headline": "ALL ROOMS CLEARED", "sub": "1 room"},
			{"rows": [row], "run": {"finished": false, "times": [31.0]}, "headline": "ROOM RUN ENDED", "sub": "1 of 10 rooms cleared"}]:
		screens.update_results(model)
		shown.append(headline.text)
	TeamCast.override({})
	if shown != ["WILL YOU MARRY ME?", "ROUND ENDED", "WILL YOU MARRY ME?", "ROOM RUN ENDED"]: failures.append("words.reveal is not shown exactly on a delivered run: %s" % [shown])
	screens.free()
	menu_style.set_asset_reader(Callable())
	_done["_check_credit"] = true

## The floating thing of 3+ player rounds: the cast's shape, its print when the cast has a picture or a logo.
func _check_balloon() -> void:
	var look: Node3D = load("res://balloon/balloon_look.gd").new()
	root.add_child(look)
	var printed := look.get_node_or_null("BalloonPrint") != null
	if look.get("shape") != TeamCast.balloon_shape(): failures.append("the floating thing is not the cast's shape " + TeamCast.balloon_shape())
	if printed != (TeamCast.balloon_picture() != null): failures.append("the floating thing's print is %s" % ("there without a picture" if printed else "missing"))
	print("CAST_BALLOON shape=", look.get("shape"), " print=", printed)
	look.free()
	_done["_check_balloon"] = true

# ------------------------------------------------------------------ 5. the team pack

## Every pack file that is there loads: the announcer's lines, the players' clips, the team wall's photos.
func _check_pack() -> void:
	var lines := 0
	for event: String in TeamCast.ANNOUNCER_EVENTS:
		var present := 0
		for variant in range(1, TeamCast.ANNOUNCER_VARIANTS + 1):
			if TeamCast._exists(TeamCast.PICTURE_DIR + "announcer/%s_%d.ogg" % [event, variant]): present += 1
		var loaded := TeamCast.announcer(event).size()
		if loaded != present: failures.append("announcer %s: %d of %d lines load" % [event, loaded, present])
		lines += loaded
	var clips := 0
	for seat in 8:
		clips += TeamCast.voices(seat).size()
	var wall := TeamCast.team_wall()
	var photos := 0
	for index in wall.size():
		var named := _listed("team_wall", index)
		if named != "" and wall[index].picture == null: failures.append("team_wall[%d].picture does not load: res://cast/%s" % [index, named])
		if wall[index].picture != null: photos += 1
	var intro := TeamCast.PATH # any file of the project stands in for an intro video
	CastVideo.forget_seen(intro)
	var unseen := not CastVideo.seen(intro)
	CastVideo.mark_seen(intro)
	var marked := CastVideo.seen(intro)
	CastVideo.forget_seen(intro)
	if not (unseen and marked and not CastVideo.seen(intro)): failures.append("the intro's once-per-device flag does not set and clear")
	print("CAST_PACK announcer_lines=", lines, " voice_clips=", clips, " team_wall=", wall.size(), " photos=", photos)
	_done["_check_pack"] = true

## The announcer on a scripted round: which lines it says depends on the lines the cast has.
func _check_announcer() -> void:
	var run := FakeRun.new()
	root.add_child(run)
	var announcer := CastAnnouncer.new()
	root.add_child(announcer)
	announcer.simulation = run
	var expected: Array[String] = []
	var say := func(event: String, state: Dictionary) -> void:
		if announcer._player != null: announcer._player.stop()
		announcer._calm = 0.0
		announcer.observe(state)
		if not TeamCast.announcer(event).is_empty(): expected.append(event)
	say.call("start", {"breaks": 0, "resets": 1, "won": false, "playing": true, "elapsed_seconds": 0.5})
	say.call("zap", {"breaks": 0, "resets": 1, "won": false, "playing": true, "elapsed_seconds": 2.0, "scorch": PackedInt32Array([1, 1, 0, 0])})
	say.call("break", {"breaks": 1, "resets": 1, "won": false, "playing": true, "elapsed_seconds": 3.0, "failure_kind": "break", "scorch": PackedInt32Array([1, 1, 0, 0])})
	say.call("pop", {"breaks": 2, "resets": 2, "won": false, "playing": true, "elapsed_seconds": 4.0, "failure_kind": "pop"})
	var goal := "goal"
	say.call(goal, {"breaks": 2, "resets": 3, "won": true, "playing": false, "elapsed_seconds": 9.0})
	run.course_plan = {"level": 1}
	say.call("start", {"breaks": 2, "resets": 4, "won": false, "playing": true, "elapsed_seconds": 0.2})
	var clean := "perfect" if not TeamCast.announcer("perfect").is_empty() else "goal"
	say.call(clean, {"breaks": 2, "resets": 4, "won": true, "playing": false, "elapsed_seconds": 7.0})
	run.course_plan = {"level": 0}
	say.call("start", {"breaks": 0, "resets": 5, "won": false, "playing": true, "elapsed_seconds": 0.2})
	say.call("near_drop", {"breaks": 0, "resets": 5, "won": false, "playing": true, "elapsed_seconds": 3.0, "roll": 1.3})
	run.play_mode = "balloon"
	run.team.view.alive = true
	run.team.view.position = Vector3(0.0, 1.0, 0.0)
	run.team.view.velocity = Vector3(0.0, -3.0, 0.0)
	say.call("near_drop", {"breaks": 0, "resets": 5, "won": false, "playing": true, "elapsed_seconds": 4.0})
	if announcer._player != null: announcer._player.stop()
	var busy := 0
	if not TeamCast.announcer("break").is_empty():
		announcer.announce("break")
		busy = 1 if not announcer.announce("break") else 0
		if busy == 0: failures.append("a second line plays over the first")
	print("CAST_ANNOUNCER heard=", announcer.heard, " expected=", expected, " overlap_refused=", busy)
	var heard: Array[String] = announcer.heard.slice(0, expected.size())
	if heard != expected: failures.append("the announcer said %s, expected %s" % [heard, expected])
	announcer.free()
	run.free()
	_done["_check_announcer"] = true

# ------------------------------------------------------------------ 6. a broken cast

func _check_broken_cast() -> void:
	TeamCast.override({"format": "team-cast-v2", "team": 5, "brand": {"logo": 7, "colors": "red"}, "world": [], "object": {"kind": 3, "picture": ["x"]},
		"balloon": "blimp", "obstacles": {"a": 1}, "posters": [1, "x", {"picture": 5, "caption": 9}], "eggs": "egg", "music": 9, "video": "intro.ogv",
		"players": [5, {"name": 7, "color": "blue", "voice": "../x.ogg", "catchphrase": ["no"]}], "words": ["BUG"]})
	var expect := {"team": TeamCast.team_name() == "FRIENDS", "word": TeamCast.word("break") == "CRACK!", "seat": TeamCast.player(0)["name"] == "PLAYER 1",
		"logo": TeamCast.logo() == null, "picture": TeamCast.picture() == null, "accent": TeamCast.brand_accent().a == 0.0, "walls": TeamCast.wall_hue() < 0.0,
		"theme": TeamCast.world_theme() == "office", "balloon": TeamCast.balloon_shape() == "balloon" and TeamCast.balloon_picture() == null,
		"obstacle": TeamCast.obstacle(1).is_empty(), "poster": TeamCast.poster_own(3).is_empty(), "egg": TeamCast.egg(1) == "", "voice": TeamCast.voice(1) == null,
		"music": TeamCast.music_id() == TeamCast.DEFAULT_MUSIC, "video": TeamCast.video_path("intro") == "", "reveal": TeamCast.reveal() == ""}
	for key: String in expect:
		if not expect[key]: failures.append("broken cast does not fall back: " + key)
	var level := LevelData.load_level(1)
	_frames("broken-cast level=1", level.get("slots", []), level.get("blocks", []))
	TeamCast.override({"format": "team-cast-v1", "team": {"name": "Sommer"}, "object": {"kind": "portrait"}, "players": [{"name": "Ida", "color": "#aa22cc"}]})
	if TeamCast.team_name() != "SOMMER" or TeamCast.object_kind() != "portrait" or TeamCast.player_name(0) != "IDA" or TeamCast.world_theme() != "office":
		failures.append("a team-cast-v1 cast does not load")
	TeamCast.override({})
	# brand.walls "auto": a vivid first brand colour paints accent walls, black, white or dull ones keep the stripe
	for case: Array in [[["#FF6600", "#FFFFFF"], "", "accent"], [["#111111", "#FFFFFF"], "", "stripe"], [["#F2F2F2"], "auto", "stripe"],
			[["#111111"], "full", "full"], [[], "", "stripe"]]:
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "Walls"}, "players": [{"name": "Ida"}], "brand": {"colors": case[0], "walls": case[1]}})
		if TeamCast.brand_walls() != case[2]: failures.append("brand.walls %s with %s gives %s, not %s" % [case[1], case[0], TeamCast.brand_walls(), case[2]])
	TeamCast.override({})
	_done["_check_broken_cast"] = true

# ------------------------------------------------------------------ 7. the music ids

func _check_music() -> void:
	var ids := {}
	for file in DirAccess.get_files_at(TeamCast.MUSIC_DIR):
		if file.begins_with("friends-") and file.get_extension() in ["ogg", "wav"]: ids[file.get_basename().trim_prefix("friends-")] = true
	for id: String in ids:
		TeamCast.override({"format": "team-cast-v2", "team": {"name": "Music"}, "players": [{"name": "Ida"}], "music": id})
		var path := TeamCast.music_path()
		var stream := GameAudio.music_stream(path)
		var looped: bool = stream is AudioStreamOggVorbis and stream.loop or stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		var seconds := stream.get_length() if stream != null else 0.0
		print("MUSIC id=", id, " path=", path, " seconds=", snappedf(seconds, 0.01), " loop=", looped)
		if TeamCast.music_id() != id or path.get_file().get_basename() != "friends-" + id: failures.append("music %s does not resolve: %s" % [id, path])
		elif not looped or seconds < 30.0 or seconds > 120.0: failures.append("music %s does not load as a 30-120 s loop: %s" % [id, path])
		elif path.ends_with(".ogg"):
			var imported := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamOggVorbis
			if imported == null or absf(imported.get_length() - seconds) > 0.05: failures.append("music %s is not imported: %s" % [id, path])
	TeamCast.override({})
	_done["_check_music"] = true

# ------------------------------------------------------------------ 8. rounds as metaphors

func _rounds_cast(rounds: Variant) -> void:
	TeamCast.override({"format": "team-cast-v2", "team": {"name": "Rounds"}, "players": [{"name": "Ida"}], "mode": "show", "show": {"rounds": rounds}})

func _check_rounds() -> void:
	_rounds_cast({}) # a cast of its own with no overrides, whatever the shipped one says
	var plain := {}
	for level in CourseSection.level_count(): plain[level] = [CourseSection.level_title(level), CourseSection.level_rule(level), CourseSection.level_hint(level)]
	# the accessors
	_rounds_cast({"r15": {"title": "don't drown in prs", "rule": "r" + "u".repeat(60), "hint": "stay on the move", "label": ["#1234", "lgtm", "A".repeat(20), 5, ""]},
		"r21": {"title": "T".repeat(30), "model": "round_r23.glb"}, "r23": {"label": "conflict"}, "r16": {"label": "NOPE", "model": "round_r21.glb"}, "r20": {"title": "NOPE"}})
	if TeamCast.round_text("r15", "title") != "DON'T DROWN IN PRS": failures.append("round_text r15 title: " + TeamCast.round_text("r15", "title"))
	if TeamCast.round_text("r15", "rule").length() != TeamCast.ROUND_LINE_MAX or TeamCast.round_text("r15", "rule") != TeamCast.round_text("r15", "rule").to_upper():
		failures.append("round_text r15 rule is not clipped to %d upper-case letters" % TeamCast.ROUND_LINE_MAX)
	if TeamCast.round_text("r15", "hint") != "STAY ON THE MOVE": failures.append("round_text r15 hint: " + TeamCast.round_text("r15", "hint"))
	if TeamCast.round_text("r21", "title").length() != TeamCast.ROUND_TITLE_MAX: failures.append("round_text r21 title is not clipped to %d" % TeamCast.ROUND_TITLE_MAX)
	if TeamCast.round_text("r15", "label") != "" or TeamCast.round_text("r15", "nope") != "": failures.append("round_text answers for a key that is no text key")
	if TeamCast.round_text("r20", "title") != "" or TeamCast.round_text("r99", "title") != "" or TeamCast.round_text("", "title") != "": failures.append("round_text answers for a round that does not exist")
	if TeamCast.round_text("r14", "title") != "": failures.append("round_text gives a title for a round the cast leaves alone")
	var words := TeamCast.round_labels("r15")
	if words != PackedStringArray(["#1234", "LGTM", "A".repeat(TeamCast.ROUND_LABEL_MAX)]): failures.append("round_labels r15 (upper case, clipped, texts only, no empty): " + str(words))
	if TeamCast.round_labels("r23") != PackedStringArray(["CONFLICT"]): failures.append("round_labels r23 of one text: " + str(TeamCast.round_labels("r23")))
	if not TeamCast.round_labels("r16").is_empty() or not TeamCast.round_labels("r14").is_empty() or not TeamCast.round_labels("r99").is_empty():
		failures.append("round_labels answers for a round that takes no label")
	_rounds_cast({"r15": {"label": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]}})
	if TeamCast.round_labels("r15").size() != TeamCast.ROUND_LABELS: failures.append("round_labels keeps more than %d labels" % TeamCast.ROUND_LABELS)
	if TeamCast.round_model("r21") != null or TeamCast.round_model("r15") != null or TeamCast.round_model("r16") != null: failures.append("round_model gives a model nobody named")
	_rounds_cast({"r21": {"model": "round_r23.glb"}, "r23": {"model": "round_r21.glb"}, "r15": {"model": "round_r15.glb"}})
	if TeamCast.round_model("r21") != null or TeamCast.round_model("r23") != null or TeamCast.round_model("r15") != null: failures.append("round_model takes a file that is not the round's own")
	_rounds_cast({"r21": {"model": "round_r21.glb"}})
	var model := TeamCast.round_model("r21")
	var shipped := FileAccess.file_exists(TeamCast.PICTURE_DIR + "round_r21.glb") or ResourceLoader.exists(TeamCast.PICTURE_DIR + "round_r21.glb")
	if shipped and model == null: failures.append("round_r21.glb is in the cast and does not load")
	if not shipped and model != null: failures.append("round_model gives a model without its file")
	if model != null:
		var box := ShowCrown.bounds(model)
		if not box.has_volume(): failures.append("round_r21.glb has no size")
		model.free()
	_rounds_cast("broken")
	if TeamCast.round_text("r15", "title") != "" or not TeamCast.round_labels("r15").is_empty() or TeamCast.round_model("r21") != null: failures.append("a show.rounds that is no object is not ignored")
	_rounds_cast({"r15": "WIP", "r21": [1], "r23": {"label": {"a": 1}, "title": 7}})
	if TeamCast.round_text("r15", "title") != "" or TeamCast.round_text("r23", "title") != "" or not TeamCast.round_labels("r23").is_empty(): failures.append("round entries of the wrong type are not ignored")
	# CourseSection: round ids and the overrides
	var ids := {}
	for level in CourseSection.level_count():
		var round_id := CourseSection.round_id(level)
		if round_id != "": ids[level] = round_id
	if CourseSection.round_id(-1) != "" or CourseSection.round_id(9999) != "": failures.append("round_id of a level that does not exist is not empty")
	for expected: Array in [["POSTER RUSH", "r17"], ["LAST TILE STANDING", "r15"], ["SPIN BARS", "r21"], ["ROLLING ROAD", "r23"], ["KEEP THE LOGO", "r24"], ["SQUARE STACK A", "r25"], ["HEX STACK A", "r26"], ["SQUARE STACK B", "r27"], ["HEX STACK B", "r28"], ["ROOFTOP RUN", "r29"], ["FERRY CROSSING", "r30"], ["SPINNER GARDEN", "r31"], ["GATE RUSH", "r32"], ["CROWN CLIMB", "r16"], ["CIRCUIT BREAKER", "r14"]]:
		var found := false
		for level: int in ids:
			if CourseSection.level_raw_title(level) != expected[0]: continue
			found = true
			if ids[level] != expected[1]: failures.append("%s (level %d) is round %s, not %s" % [expected[0], level + 1, ids[level], expected[1]])
		if not found: failures.append("no level of the round " + str(expected[0]))
	var posters: Array = []
	for level: int in ids:
		if ids[level] == "r17": posters.append(level)
	if posters.size() != 2: failures.append("POSTER RUSH is %d levels of r17, not 2" % posters.size())
	_rounds_cast({"r17": {"title": "break through", "rule": "run through the logo", "hint": "go go"}, "r15": {"title": "Don't drown in PRs"}})
	for level in CourseSection.level_count():
		var own: String = str(ids.get(level, ""))
		var want_title: String = plain[level][0]
		var want_rule: String = plain[level][1]
		var want_hint: String = plain[level][2]
		if own == "r17":
			want_title = "BREAK THROUGH"
			want_rule = "RUN THROUGH THE LOGO"
			want_hint = "GO GO"
		elif own == "r15": want_title = "DON'T DROWN IN PRS"
		if CourseSection.level_title(level) != want_title: failures.append("level %d title %s, not %s" % [level + 1, CourseSection.level_title(level), want_title])
		if CourseSection.level_rule(level) != want_rule: failures.append("level %d rule %s, not %s" % [level + 1, CourseSection.level_rule(level), want_rule])
		if CourseSection.level_hint(level) != want_hint: failures.append("level %d hint %s, not %s" % [level + 1, CourseSection.level_hint(level), want_hint])
		if CourseSection.level_raw_title(level) == "" and CourseSection.level_title(level) != "": failures.append("level %d has a title without a raw one" % (level + 1))
	if CourseSection.level_title(-1) != "" or CourseSection.level_rule(9999) != "" or CourseSection.level_hint(-1) != "": failures.append("a level that does not exist has text")
	# the lobby's round list keeps its rounds: ids and grouping follow the files, the names follow the cast
	_rounds_cast({})
	var before := RoundList.entries()
	var plain_ids: Array = before.map(func(row: Dictionary) -> String: return str(row.id))
	_rounds_cast({"r14": {"title": "SAME NAME", "rule": "SAME RULE"}, "r19": {"title": "SAME NAME"}, "r17": {"title": "BREAK THROUGH"}})
	var after := RoundList.entries()
	if after.map(func(row: Dictionary) -> String: return str(row.id)) != plain_ids: failures.append("renaming rounds changes the lobby's circles: %s -> %s" % [plain_ids, after.map(func(row: Dictionary) -> String: return str(row.id))])
	for row: Dictionary in after:
		if str(row.id) == "r17":
			if str(row.title) != "BREAK THROUGH" or (row.levels as Array).size() != 2: failures.append("r17 in the round list: " + str(row))
		elif str(row.id) == "r14" and (str(row.title) != "SAME NAME" or str(row.rule) != "SAME RULE"): failures.append("r14 in the round list: " + str(row))
		elif str(row.id) == "r19" and str(row.title) != "SAME NAME": failures.append("r19 in the round list: " + str(row))
		if RoundList.entry(str(row.id)).is_empty(): failures.append("a circle id does not give its round: " + str(row.id))
	TeamCast.override({})
	_check_round_looks()
	_done["_check_rounds"] = true

## HeroProp.fit_into (the round models) and the labelled step tile.
func _check_round_looks() -> void:
	var source := Node3D.new()
	var part := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(4.0, 2.0, 1.0)
	part.mesh = block
	part.position = Vector3(10.0, 5.0, -3.0) # a model far from its origin: fitted by its bounds
	source.add_child(part)
	var holder := HeroProp.fit_into(source, Vector3(20.0, 1.0, 0.5))
	if holder == null: failures.append("fit_into gives nothing for a model with a size")
	else:
		var box := ShowCrown.bounds(holder)
		if not box.size.is_equal_approx(Vector3(2.0, 1.0, 0.5)) or not box.get_center().is_equal_approx(Vector3.ZERO):
			failures.append("fit_into: 4 x 2 x 1 in a 20 x 1 x 0.5 box should be 2 x 1 x 0.5 about the origin, got %s about %s" % [box.size, box.get_center()])
		holder.free()
	if HeroProp.fit_into(Node3D.new(), Vector3.ONE) != null: failures.append("fit_into gives a holder for a model without meshes")
	if HeroProp.fit_into(null, Vector3.ONE) != null: failures.append("fit_into gives a holder for no model")
	# the labelled tile: words dealt round the plain tiles, none on the others
	var look := StepTileLook.new()
	var tiles: Array = []
	for index in 12: tiles.append({"kind": "n" if index % 6 != 5 else "L"})
	look._tiles = tiles
	var kinds := {"n": {"look": "plain"}, "L": {"look": "logo"}}
	var keys := look._group_keys(kinds, PackedStringArray(["A", "B", "C"]))
	var counts := {}
	for index in tiles.size():
		if tiles[index].kind == "L" and keys[index] != "L": failures.append("a logo tile wears a label: " + keys[index])
		counts[keys[index]] = int(counts.get(keys[index], 0)) + 1
	for number in 3:
		var key := "n%s%d" % [StepTileLook.LABEL_JOIN, number]
		if int(counts.get(key, 0)) < 3 or int(counts.get(key, 0)) > 4: failures.append("label %d is worn by %d of the 10 plain tiles, not 3 or 4" % [number, int(counts.get(key, 0))])
	if look._group_keys(kinds, PackedStringArray()) != ["n", "n", "n", "n", "n", "L", "n", "n", "n", "n", "n", "L"]: failures.append("without labels the tiles are not their kinds")
	if look._group_keys(kinds, PackedStringArray(["A", "B", "C"])) != keys: failures.append("the labels are not dealt the same way twice")
	# the letters fit the room evenly and lie on the card (TextMesh gives its arrays headless too)
	var room := Vector2(1.5, 0.6)
	var one := StepTileLook._letters("LGTM", room)
	var two := StepTileLook._letters("DON'T DROWN IN PRS", room)
	for arrays: Array in [one, two]:
		if arrays.is_empty(): failures.append("a label makes no letters")
		else:
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for vertex: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				low = Vector3(minf(low.x, vertex.x), minf(low.y, vertex.y), minf(low.z, vertex.z))
				high = Vector3(maxf(high.x, vertex.x), maxf(high.y, vertex.y), maxf(high.z, vertex.z))
			if high.x - low.x > room.x + 0.001 or high.z - low.z > room.y + 0.001: failures.append("the letters of a label stick out of the card: %s" % [high - low])
			if absf(low.x + high.x) > 0.01 or absf(low.z + high.z) > 0.01: failures.append("the letters of a label are not centred on the card")
			if low.y < StepTileLook.CARD_LIFT: failures.append("the letters of a label sink into the card")
	if one.is_empty() or two.is_empty(): pass
	elif ((two[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < (one[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()): failures.append("a long label has fewer letters than a short one")
	var mesh := StepTileLook._tile_mesh(1.4, 0.5, [StandardMaterial3D.new(), StandardMaterial3D.new()], "LGTM")
	var bare := StepTileLook._tile_mesh(1.4, 0.5, [StandardMaterial3D.new(), StandardMaterial3D.new()])
	if bare.get_surface_count() != 2: failures.append("a tile without a label is no longer two surfaces")
	if mesh.get_surface_count() != 4: failures.append("a labelled tile is not four surfaces (plate, rim, card, letters): %d" % mesh.get_surface_count())
