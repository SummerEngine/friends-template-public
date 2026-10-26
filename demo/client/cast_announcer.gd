extends Node
## The team's announcer (docs/slots.md, team pack): a short line from demo/cast/announcer/<event>_<n>.ogg, a random one of up to 4, on
## the moments of a round:
##   start      a level starts
##   near_drop  the balloon is falling close to the floor, or the painting is tilted near its limit
##   break      the painting breaks (a hit or a fall)
##   pop        the balloon pops
##   zap        a laser zaps a player (read from the run's scorch counters when the hazards are in the game, else never)
##   goal       the level is cleared; `perfect` instead when it was cleared without a break or a pop (and the cast has that line)
## Client only and pure presentation: each client hears it from the state it already has (local state or snapshots), nothing new goes
## on the wire. One line at a time: an event while a line plays is dropped. The music ducks under the line.
const TeamCast := preload("res://style/team_cast.gd")
const GameAudio := preload("res://game/game_audio.gd")
const Painting := preload("res://game/painting.gd")
const BalloonSim := preload("res://balloon/balloon_sim.gd")
const DUCK_DB := -10.0              ## the music under a line
const DUCK_FADE := 0.2              ## s to duck and to come back
const START_LATE := 3.0             ## s into a level after which a client that just arrived does not announce the start
const NEAR_DROP_COOLDOWN := 8.0     ## s between two near_drop lines
const NEAR_DROP_GRACE := 2.5        ## s after a start or a respawn without near_drop
const ROLL_SHARE := 0.9             ## |roll| at this share of the painting's limit is near a drop
const BALLOON_CLEARANCE := 1.3      ## m between the balloon's bottom and the floor under it ...
const BALLOON_FALL := -1.5          ## ... while it falls at least this fast (m/s)
const ZAP_KIND := 1                 ## a scorch of this kind is a laser zap (the hazards' scorch codes)

signal announced(event: String)     ## every line this node starts, for tools

var simulation: Node
var heard: Array[String] = []       ## tools: the events announced so far
var _breaks := -1
var _resets := -1
var _won := false
var _level := -2
var _level_breaks := 0
var _scorches := PackedInt32Array()
var _calm := 0.0                    ## s left before near_drop may play again
var _player: AudioStreamPlayer
var _duck: Tween

## One round state (the local hud_state() or a snapshot); called every frame the round HUD is up.
func observe(state: Dictionary) -> void:
	if simulation == null or not is_instance_valid(simulation): return
	var breaks := int(state.get("breaks", 0))
	var resets := int(state.get("resets", 0))
	var won := bool(state.get("won", false))
	var playing := bool(state.get("playing", false))
	var in_level := str(simulation.get("round_mode")) == "level"
	var plan: Variant = simulation.get("course_plan")
	var level := int((plan as Dictionary).get("level", -1)) if plan is Dictionary else -1
	var scorches := _scorch_counts(state)
	var fresh := _breaks < 0 or breaks < _breaks
	var events: Array[String] = []
	if in_level and level != _level:
		_level = level
		_level_breaks = breaks
		_calm = NEAR_DROP_GRACE
		if playing and float(state.get("elapsed_seconds", 0.0)) < START_LATE: events.append("start")
	elif not fresh:
		if _zapped(scorches): events.append("zap")
		if breaks > _breaks: events.append("pop" if str(state.get("failure_kind", "")) == "pop" else "break")
		if won and not _won:
			var clean := breaks == _level_breaks
			events.append("perfect" if clean and not TeamCast.announcer("perfect").is_empty() else "goal")
	if resets != _resets: _calm = maxf(_calm, NEAR_DROP_GRACE)
	if events.is_empty() and in_level and playing and not won and _calm <= 0.0 and _near_drop(state):
		events.append("near_drop")
		_calm = NEAR_DROP_COOLDOWN
	for event in events:
		if announce(event): break
	if fresh: _level_breaks = breaks
	_breaks = breaks
	_resets = resets
	_won = won
	_scorches = scorches

## Plays a random line of `event`; false when the cast has none or a line is still playing (lines never overlap).
func announce(event: String) -> bool:
	var clips := TeamCast.announcer(event)
	if clips.is_empty() or (_player != null and _player.playing): return false
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.name = "AnnouncerVoice"
		_player.bus = GameAudio.VOICE_BUS # [audio] Settings: Voice volume
		add_child(_player)
		_player.finished.connect(_unduck)
	_player.stream = clips.pick_random()
	_player.play()
	_duck_music(GameAudio.MUSIC_VOLUME_DB + DUCK_DB)
	heard.append(event)
	announced.emit(event)
	return true

func _process(delta: float) -> void:
	_calm = maxf(_calm - delta, 0.0)

## The round HUD went away (lobby, menus): the next level that starts is announced again, whatever its number.
func forget_level() -> void:
	_level = -2

## Per slot [zaps and burns so far, kind of the last]: the snapshot's `scorch` on a replica, the run's own counters locally; empty
## when the game has no such hazards.
func _scorch_counts(state: Dictionary) -> PackedInt32Array:
	var listed: Variant = state.get("scorch")
	if listed == null:
		var team: Variant = simulation.get("team")
		listed = team.get("scorches") if team is Object else null
	return PackedInt32Array(listed) if listed is PackedInt32Array or listed is Array else PackedInt32Array()

func _zapped(scorches: PackedInt32Array) -> bool:
	for index in range(0, scorches.size() - 1, 2):
		var before := _scorches[index] if index < _scorches.size() else 0
		if scorches[index] > before and scorches[index + 1] == ZAP_KIND: return true
	return false

## The balloon falling close to the floor under it, or the painting tilted near its limit.
func _near_drop(state: Dictionary) -> bool:
	if str(simulation.get("play_mode")) == "balloon":
		var team: Variant = simulation.get("team")
		var view: Variant = team.get("view") if team is Object else null
		var world: Variant = simulation.get("level_world")
		if not view is BalloonSim or not world is Object or not view.alive or view.velocity.y > BALLOON_FALL: return false
		var bottom: Vector3 = view.position - Vector3(0.0, BalloonSim.RADIUS, 0.0)
		var floor_height: float = world.floor_y(int(world.get("active_level")), bottom)
		return not is_nan(floor_height) and bottom.y - floor_height < BALLOON_CLEARANCE
	return not bool(state.get("broken", false)) and absf(float(state.get("roll", 0.0))) >= Painting.ROLL_LIMIT * ROLL_SHARE

func _music() -> AudioStreamPlayer:
	return get_tree().root.get_node_or_null(NodePath(GameAudio.MUSIC_NAME)) as AudioStreamPlayer if is_inside_tree() else null

func _duck_music(volume_db: float) -> void:
	var music := _music()
	if music == null: return
	if _duck != null and _duck.is_valid(): _duck.kill()
	_duck = create_tween()
	_duck.tween_property(music, "volume_db", volume_db, DUCK_FADE)

func _unduck() -> void:
	_duck_music(GameAudio.MUSIC_VOLUME_DB)

func _exit_tree() -> void:
	# The music lives on after this node: never leave it ducked.
	if _duck != null and _duck.is_valid(): _duck.kill()
	var music := _music()
	if music != null: music.volume_db = GameAudio.MUSIC_VOLUME_DB
