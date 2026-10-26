extends Node
## Client sound: courier footsteps, jump and landing (from the courier rig's signals), the painting's break, hazard cues, the
## checkpoint chime and the shared music loop. The contract is `audio/sfx/mix.json` (every slot, its resource and gain);
## resources are whole WAV or Ogg Vorbis files, or regions of an atlas WAV (`path#start+frames`). The authority builds no instance.
## Besides the calls it gets, the node watches its run (the parent, game/game_run.gd) every frame and plays what it sees: grabs,
## throws, escapes, slaps, shoves, respawns, hazards, the walk-in pads and countdown, level start and goal, the music of the
## phase. Every client role reads the same state, so a replica hears its friends without extra network fields.
## Buses: effects on GW_Effects, music on GW_Music, voices (announcer, catchphrase clips) belong on GW_Voice (ensure_buses()).
## API: docs/painting-api.md.
signal played(event: Dictionary) ## every sound this node starts, for tools

const MIX_SCHEMA := "friends.sfx-mix.v2"
const MUSIC_BUS := "GW_Music"
const SFX_BUS := "GW_Effects"
const VOICE_BUS := "GW_Voice"
const MUSIC_NAME := "FriendsMusic"
const MUSIC_VOLUME_DB := -2.0 ## player gain below the bus; the Music setting is a linear bus gain on top
const MUSIC_FADE := 0.5 ## s, a track change fades out and back in
const LAND_MIN_SPEED := 3.0 ## m/s of fall speed below which landing is silent
const LAND_SPEED_FULL := 12.0
const LAND_PITCH_SEMITONES := -3.0
const BREAK_RADIUS := 10.0 ## m, full volume inside; linear fall-off over BREAK_FALLOFF
const BREAK_FALLOFF := 36.0
const MAX_SIMULTANEOUS_EVENTS := 2 ## per counter and snapshot
const TILE_VOICES := 3 ## stage tiles: voices started per kind in TILE_WINDOW
const TILE_WINDOW := 0.1 ## s
const TILE_POOL := 8 ## stage tiles: players that exist at all
const TILE_RADIUS := 7.0 ## m, a tile this near the listener is heard at full gain; linear fall-off over TILE_FALLOFF
const TILE_FALLOFF := 30.0
const TILE_AUDIBLE := 0.04 ## listener-distance gain under which a tile's cue is not played at all
const TILE_GAIN := 0.7 ## a tile's cue next to a hazard's (there are many tiles)
## Watching the run.
const CENTRE := Vector3(0.0, 0.9, 0.0) ## capsule centre above a courier's feet
const SHOVE_RANGE := 0.85 ## m between two couriers (horizontal) that counts as touching
const SHOVE_SPEED := 1.4 ## m/s of closing speed that makes a touch a shove
const SHOVE_GAP := 0.45 ## s per pair between two shove sounds
const TELEPORT := 4.0 ## m a courier moves in one frame: a respawn
const THROW_TEST := 0.14 ## s after a release: moved this far (THROW_MOVE) is a throw, else an escape
const THROW_MOVE := 0.55
const NEAR_DROP_HEIGHT := 1.5 ## m of the balloon's centre above the floor while falling
const NEAR_DROP_GAP := 3.0
const HAZARD_VOICES := 4 ## looping hazards heard at once (the nearest)
const HAZARD_RANGE := 20.0 ## m, farther looping hazards are not started
const WOBBLE_MARGIN := 0.45 ## m around the painting's break box: something this close makes it rattle
const WOBBLE_GAP := 1.3
const MOVER_LAYER := 16 ## levels/level_world.gd LAYER_MOVER: footsteps on it sound metal
const QUIET_AFTER_JUMP := 1.0 ## s after a level or phase change without respawn poofs (everybody teleports then)

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const Painting := preload("res://game/painting.gd")

static var _mix := {}
static var _atlases := {}
static var _static_streams := {}
static var _music_pending: AudioStreamPlayer

var playback_enabled := true

var _streams := {}
var _listener: Node3D
var _spatial: Array = [] ## {node, gain, radius, falloff}
var _hazard_players := {}
var _epoch := -1
var _counts := {"death": 0, "push": 0, "bounce": 0}
var _easter := 0
var _event_at := {} ## event id -> time it last played (cooldowns)
var _clock := 0.0
var _tile_windows := {} ## kind -> {at, used}: the voices started in the current TILE_WINDOW
var _tile_voices: Array = [] ## the pool (AudioStreamPlayer3D)
var _tile_owner: Array = [] ## per pool voice: the tile whose cue it plays (-1 none)
var _tile_started: Array = [] ## per pool voice: _clock when it last started

var _run: Node
var _phase := ""
var _level := -2
var _won := false
var _quiet_until := 0.0
var _last_pos: Array = []
var _pair_gap := {}
var _pair_at := {}
var _zones := {}
var _beep := 0
var _held := PackedInt32Array()
var _held_since := {}
var _releases: Array = []
var _swings := -1
var _scorches := PackedInt32Array()
var _scorch_pending := false
var _balloon_alive := true
var _near_drop_at := -100.0
var _hazard_level := -2
var _hazards := {} ## mover index -> {active, at, dy, speed}
var _loops := {} ## mover index -> AudioStreamPlayer3D
var _wobble_wait := 0.0
var _wardrobe: Node
var _wardrobe_look := 0.0
var _music_context := ""
var _music_retry := 0.0

func _ready() -> void:
	ensure_buses()

func _exit_tree() -> void:
	if _run == null or not is_inside_tree(): return
	var scene := get_tree().current_scene
	if scene == null or scene.get("ui_state") == null or scene.get("ui_state") == "menu": set_music(get_tree(), "menu")

func configure(listener: Node3D) -> void:
	_listener = listener

# ------------------------------------------------------------------ couriers
## Connects the rig's footstep(side), jumped and landed(speed) signals. `local`: this seat is played on this machine
## (only it makes the 2D jump sound).
func bind_courier(seat: int, rig: Node3D, local: bool) -> void:
	var on_step := _on_footstep.bind(rig)
	if not rig.footstep.is_connected(on_step): rig.footstep.connect(on_step)
	var on_land := _on_landed.bind(rig)
	if not rig.landed.is_connected(on_land): rig.landed.connect(on_land)
	if local and not rig.jumped.is_connected(play_jump): rig.jumped.connect(play_jump)

func _on_footstep(_side, rig: Node3D) -> void:
	if is_instance_valid(rig): _play_step(rig.global_position, 1.0, 0.0)

func _on_landed(speed: float, rig: Node3D) -> void:
	if speed < LAND_MIN_SPEED or not is_instance_valid(rig): return
	var land := event_entry("land")
	if land.is_empty():
		_play_step(rig.global_position, clampf(speed / LAND_SPEED_FULL, 0.25, 1.0), LAND_PITCH_SEMITONES)
		return
	var semitones := randf_range(float(land.pitch_semitones[0]), float(land.pitch_semitones[1]))
	_play_3d("step", str(land.variants.pick_random()), float(land.gain) * clampf(speed / LAND_SPEED_FULL, 0.35, 1.0), pow(2.0, semitones / 12.0),
		rig.global_position, float(land.radius_m), float(land.falloff_m))

## A footstep at `at`: the takes of the surface under it (mix.json footsteps.surfaces: "metal" on movers, "ice"), else the
## floor's.
func _play_step(at: Vector3, gain_scale: float, extra_semitones: float) -> void:
	var mix := load_mix()
	if mix.is_empty(): return
	var steps: Dictionary = mix.footsteps
	var surface: Dictionary = steps.get("surfaces", {}).get(surface_under(at), {})
	var resource := str(surface.waves.pick_random()) if not surface.is_empty() else str(steps.waves.pick_random().resource)
	var semitones := randf_range(float(steps.pitch_semitones[0]), float(steps.pitch_semitones[1])) + extra_semitones
	var shape: Dictionary = steps.attenuation
	_play_3d("step", resource, float(surface.get("gain", steps.gain)) * gain_scale, pow(2.0, semitones / 12.0), at, float(shape.radius_m), float(shape.falloff_m))

## The kind of ground under `at` (a courier's feet): "metal" (a mover: lifts, ferries, platforms), "ice" (an ice block of a
## level, levels/level_world.gd meta "ice") or "" (the floor).
func surface_under(at: Vector3) -> String:
	if not is_instance_valid(_listener) or not _listener.is_inside_tree(): return ""
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at - Vector3.UP * 0.4, 1 | MOVER_LAYER)
	var hit := _listener.get_world_3d().direct_space_state.intersect_ray(query)
	var body := hit.get("collider") as CollisionObject3D
	if body == null: return ""
	if body.collision_layer & MOVER_LAYER: return "metal"
	var shape := body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape))) as Node
	return "ice" if shape != null and shape.has_meta("ice") else ""

# ------------------------------------------------------------------ one-shots
func play_jump() -> void: _play_slot("jump")
func play_push() -> void: _play_slot("push")
func play_easter() -> void: _play_slot("easter")
func play_checkpoint() -> void: _play_slot("checkpoint")

## Carry: a courier fell (the slide whistle and the splash). Balloon rounds call it for a pop and for a laser or fire hit:
## the pop plays at the balloon, a hit waits for the watcher to name it (zap or burn) and where.
func play_death() -> void:
	if _in_balloon_round():
		if str(_run.failure_kind) == "pop": play_pop()
		else: _scorch_pending = true
		return
	_play_slot("death")
	if _run != null: play_event("fall")

## A touch of the balloon (a bump, a header or a slap's hit): a rubbery bonk at the balloon.
func play_bounce() -> void:
	if _in_balloon_round() and play_event("bump", _balloon_point()): return
	_play_slot("bounce")

func play_pop() -> void: play_event("pop", _balloon_point())
func play_slap(at: Variant = null) -> void: play_event("slap", at)
func play_grab(at: Variant = null) -> void: play_event("grab", at)
func play_throw(at: Variant = null) -> void: play_event("throw", at)
func play_escape(at: Variant = null) -> void: play_event("escape", at)
## A yard prop event (players/prop_sim.gd step(): {kind: "pick" | "throw" | "knock", position}): a grab, a throw, a bump.
func play_prop(event: Dictionary) -> void:
	var at: Variant = event.get("position")
	match str(event.get("kind", "")):
		"pick": play_grab(at)
		"throw": play_throw(at)
		"knock": play_event("shove", at)
## "zap" (laser) or "burn" (fire) on a courier.
func play_scorch(kind: String, at: Variant = null) -> void: play_event("burn" if kind == "burn" else "zap", at)

func _play_slot(slot: String) -> void:
	var entry: Dictionary = load_mix().get(slot, {})
	if entry.is_empty(): return
	var pitch := float(entry.pitch)
	if entry.get("pitch_semitones") is Array:
		pitch *= pow(2.0, randf_range(float(entry.pitch_semitones[0]), float(entry.pitch_semitones[1])) / 12.0)
	_play_2d(slot, str(entry.resource), float(entry.gain), pitch)

## One of mix.json "events" by id: a random variant, its gain times `gain_scale`, a random pitch in its range plus
## `semitones`. With `at` and a radius in the entry it is placed in the world. False when the id is unknown or cooling down.
func play_event(id: String, at: Variant = null, gain_scale := 1.0, semitones := 0.0) -> bool:
	var entry := event_entry(id)
	if entry.is_empty(): return false
	var cooldown := float(entry.get("cooldown_s", 0.0))
	if cooldown > 0.0 and _clock - float(_event_at.get(id, -100.0)) < cooldown: return true
	_event_at[id] = _clock
	var variants: Array = entry.variants
	var shift := semitones
	if entry.get("pitch_semitones") is Array: shift += randf_range(float(entry.pitch_semitones[0]), float(entry.pitch_semitones[1]))
	var gain := float(entry.get("gain", 1.0)) * gain_scale
	var pitch := pow(2.0, shift / 12.0)
	if at is Vector3 and entry.has("radius_m"):
		_play_3d(id, str(variants.pick_random()), gain, pitch, at, float(entry.radius_m), float(entry.get("falloff_m", 24.0)))
	else:
		_play_2d(id, str(variants.pick_random()), gain, pitch)
	return true

## The painting's break at `at`; `age` is how long ago it broke (a late joiner does not replay a finished crash).
func play_break(at: Vector3, age := 0.0) -> void:
	var entry := break_entry(CarryItem.break_sound_id())
	if entry.is_empty() or age > float(entry.duration_s): return
	_play_3d("break", str(entry.resource), float(entry.gain), float(entry.pitch), at, BREAK_RADIUS, BREAK_FALLOFF)

# ------------------------------------------------------------------ blinking blocks
## The long crack of a block about to vanish. One voice per block: a new cue replaces the old one.
func blink_warn(id: int, at: Vector3) -> void:
	_hazard_cue(id, at, "crack")

## The block is gone: the crack stops, the short break plays.
func blink_gone(id: int, at: Vector3) -> void:
	_hazard_cue(id, at, "broken")

func stop_hazard(id: int) -> void:
	var player: AudioStreamPlayer3D = _hazard_players.get(id)
	if is_instance_valid(player): player.stop()

func _hazard_cue(id: int, at: Vector3, kind: String) -> void:
	var timer: Dictionary = load_mix().get("timer", {})
	if timer.is_empty(): return
	var entry: Dictionary = timer[kind]
	played.emit({"kind": "blink_" + kind, "id": id, "resource": entry.resource, "gain": float(entry.gain), "pitch": float(entry.pitch), "position": at})
	if not playback_enabled: return
	var shape: Dictionary = timer.attenuation
	var player: AudioStreamPlayer3D = _hazard_players.get(id)
	if not is_instance_valid(player):
		player = AudioStreamPlayer3D.new()
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.bus = SFX_BUS
		add_child(player)
		_hazard_players[id] = player
		_spatial.append({"node": player, "gain": float(entry.gain), "radius": float(shape.radius_m), "falloff": float(shape.falloff_m)})
	player.global_position = at
	player.stop()
	player.stream = _stream(str(entry.resource))
	player.pitch_scale = float(entry.pitch)
	_set_gain(player, float(entry.gain), float(shape.radius_m), float(shape.falloff_m))
	player.play()

# ------------------------------------------------------------------ stage tiles
## A stage round's tile turns white (the crack of a block about to vanish) or is gone (the short break): many tiles go at once (the whole field of a
## 12 player round), so the voices are a small pool, at most TILE_VOICES start per TILE_WINDOW s per kind, and a cue is quieter the farther the tile is
## from the listener (the followed courier's camera) and not played at all when it would be silent. A tile's break takes over the voice of its own crack.
func tile_warn(index: int, at: Vector3) -> void:
	_tile_cue(index, at, "crack")

func tile_drop(index: int, at: Vector3) -> void:
	_tile_cue(index, at, "broken")

func _tile_cue(index: int, at: Vector3, kind: String) -> void:
	var timer: Dictionary = load_mix().get("timer", {})
	if timer.is_empty(): return
	var entry: Dictionary = timer[kind]
	var near := 1.0
	if is_instance_valid(_listener): near = attenuation(at.distance_to(_listener.global_position), TILE_RADIUS, TILE_FALLOFF)
	if near < TILE_AUDIBLE: return
	var window: Dictionary = _tile_windows.get(kind, {"at": -100.0, "used": 0})
	if _clock - float(window.at) >= TILE_WINDOW: window = {"at": _clock, "used": 0}
	if int(window.used) >= TILE_VOICES: return
	window.used = int(window.used) + 1
	_tile_windows[kind] = window
	var gain := float(entry.gain) * TILE_GAIN
	played.emit({"kind": "tile_" + kind, "id": index, "resource": entry.resource, "gain": gain * near, "pitch": float(entry.pitch), "position": at})
	if not playback_enabled: return
	var player := _tile_voice(index)
	player.global_position = at
	player.stop()
	player.stream = _stream(str(entry.resource))
	player.pitch_scale = float(entry.pitch)
	_set_gain(player, gain, TILE_RADIUS, TILE_FALLOFF)
	player.play()
	for item: Dictionary in _spatial:
		if item.node == player:
			item.gain = gain
			break

## The pool voice of tile `index` (its crack still sounding), else a free one, else the one that started longest ago.
func _tile_voice(index: int) -> AudioStreamPlayer3D:
	var pick := -1
	for slot in _tile_voices.size():
		if int(_tile_owner[slot]) == index:
			pick = slot
			break
	if pick < 0:
		for slot in _tile_voices.size():
			if not (_tile_voices[slot] as AudioStreamPlayer3D).playing:
				pick = slot
				break
	if pick < 0 and _tile_voices.size() < TILE_POOL:
		var made := AudioStreamPlayer3D.new()
		made.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		made.bus = SFX_BUS
		add_child(made)
		_spatial.append({"node": made, "gain": 1.0, "radius": TILE_RADIUS, "falloff": TILE_FALLOFF})
		_tile_voices.append(made)
		_tile_owner.append(-1)
		_tile_started.append(0.0)
		pick = _tile_voices.size() - 1
	if pick < 0:
		pick = 0
		for slot in _tile_voices.size():
			if float(_tile_started[slot]) < float(_tile_started[pick]): pick = slot
	_tile_owner[pick] = index
	_tile_started[pick] = _clock
	return _tile_voices[pick]

# ------------------------------------------------------------------ replicated counters
## `counts` = {death, push, bounce, easter}: monotonic counters from the snapshot. The first call and the first call after
## an epoch change only install a baseline (a join or a reset is not a history of sounds); easter keeps its baseline across resets.
func observe(counts: Dictionary, epoch: int) -> void:
	if epoch < _epoch: return
	var easter := int(counts.get("easter", 0))
	if _epoch < 0: _easter = easter
	elif easter > _easter:
		for i in mini(easter - _easter, MAX_SIMULTANEOUS_EVENTS): play_easter()
	_easter = maxi(_easter, easter)
	if epoch != _epoch:
		_epoch = epoch
		for key in _counts: _counts[key] = int(counts.get(key, 0))
		return
	for key in _counts:
		var value := int(counts.get(key, 0))
		if value > _counts[key]:
			for i in mini(value - _counts[key], MAX_SIMULTANEOUS_EVENTS): call("play_" + str(key))
		_counts[key] = maxi(_counts[key], value)

func reset_baseline() -> void:
	_epoch = -1
	_easter = 0
	for key in _counts: _counts[key] = 0
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.queue_free()
	_spatial.clear()
	_hazard_players.clear()
	_loops.clear()
	_hazards.clear()
	_hazard_level = -2

# ------------------------------------------------------------------ playback
func _play_2d(kind: String, resource: String, gain: float, pitch: float) -> void:
	played.emit({"kind": kind, "resource": resource, "gain": gain, "pitch": pitch})
	if not playback_enabled: return
	var stream := _stream(resource)
	if stream == null: return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_linear = gain
	player.pitch_scale = pitch
	player.bus = SFX_BUS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _play_3d(kind: String, resource: String, gain: float, pitch: float, at: Vector3, radius: float, falloff: float) -> void:
	played.emit({"kind": kind, "resource": resource, "gain": gain, "pitch": pitch, "position": at})
	if not playback_enabled: return
	var stream := _stream(resource)
	if stream == null: return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED # the distance gain below is the fall-off
	player.pitch_scale = pitch
	player.bus = SFX_BUS
	add_child(player)
	player.global_position = at
	_spatial.append({"node": player, "gain": gain, "radius": radius, "falloff": falloff})
	_set_gain(player, gain, radius, falloff)
	player.finished.connect(player.queue_free)
	player.play()

func _stream(resource: String) -> AudioStream:
	if not _streams.has(resource):
		var stream := stream_for(resource)
		if stream == null: return null
		_streams[resource] = stream
	return _streams[resource]

func _set_gain(player: AudioStreamPlayer3D, gain: float, radius: float, falloff: float) -> void:
	if not is_instance_valid(_listener): return
	player.volume_linear = gain * attenuation(player.global_position.distance_to(_listener.global_position), radius, falloff)

func _process(delta: float) -> void:
	_clock += delta
	for index in range(_spatial.size() - 1, -1, -1):
		var item: Dictionary = _spatial[index]
		if not is_instance_valid(item.node): _spatial.remove_at(index)
		else: _set_gain(item.node, item.gain, item.radius, item.falloff)
	_watch(delta)

func _physics_process(delta: float) -> void:
	if _run != null and _phase == "round": _watch_painting(delta)

# ------------------------------------------------------------------ watching the run
func _watch(delta: float) -> void:
	if _run == null:
		var parent := get_parent()
		if parent == null or parent.get("round_mode") == null or parent.get("network_role") == "authority": return
		_run = parent
	if _run.get("actors") == null or _run.world == null: return
	var phase := _current_phase()
	if phase != _phase:
		if _phase == "lobby" and phase == "round": play_event("go")
		_phase = phase
		_quiet_until = _clock + QUIET_AFTER_JUMP
	var context: String = {"menu": "menu", "lobby": "lobby", "results": "results"}.get(phase, "game")
	if context != _music_context or _clock >= _music_retry: # the music player may come later than the phase
		_music_context = context
		_music_retry = _clock + 1.0
		set_music(get_tree(), context)
	if phase == "menu": return
	_watch_moves(delta)
	if _run.round_mode == "lobby":
		_watch_lobby()
		_watch_wardrobe()
		_stop_loops()
		return
	var level: int = _run.current_level()
	if level != _level:
		if _level >= 0 and level >= 0: play_event("level_start")
		_level = level
		_won = bool(_run.won)
		_quiet_until = _clock + QUIET_AFTER_JUMP
	if bool(_run.won) and not _won: play_event("goal" if str(_run.play_mode) == "carry" else "room_clear")
	_won = bool(_run.won)
	_watch_team(delta)
	_watch_hazards(delta)

## menu | lobby | round | results: the title is up (local play before PLAY, online on the main menu), the walk-in yard, a
## round of levels, the results.
func _current_phase() -> String:
	var presentation = _run.get("local_presentation")
	if presentation != null:
		if not bool(presentation.get("started")): return "menu"
		var flow = presentation.get("level_flow")
		var local_phase: String = str(flow.get("phase")) if flow != null else ""
		if local_phase == "results": return "results"
		return "lobby" if _run.round_mode == "lobby" else "round"
	var scene := get_tree().current_scene
	var state = scene.get("ui_state") if scene != null else null
	if state is String:
		if state in ["menu", "loading"]: return "menu"
		if state in ["results", "ended"]: return "results"
	return "lobby" if _run.round_mode == "lobby" else "round"

func _in_balloon_round() -> bool:
	return _run != null and _run.round_mode != "lobby" and str(_run.play_mode) == "balloon" and _run.team != null

func _balloon_point() -> Variant:
	if not _in_balloon_round(): return null
	var shown = _run.team.view if _run.team.view != null else _run.team.balloon
	return shown.position if shown != null else null

func _active(slot: int) -> bool:
	return slot < _run.actors.size() and _run.is_slot_active(slot) and is_instance_valid(_run.actors[slot])

## Shoves (two couriers closing fast while touching) and respawns (a courier that jumped far in one frame), in every mode.
func _watch_moves(delta: float) -> void:
	var actors: Array = _run.actors
	if _last_pos.size() != actors.size():
		_last_pos.resize(actors.size())
		_last_pos.fill(null)
	var held: PackedInt32Array = _run.team.contact.held_by if _in_balloon_round() and _run.team.contact != null else PackedInt32Array()
	for slot in actors.size():
		if not _active(slot):
			_last_pos[slot] = null
			continue
		var at: Vector3 = actors[slot].global_position
		if _last_pos[slot] is Vector3 and at.distance_to(_last_pos[slot]) > TELEPORT and _clock > _quiet_until \
				and (slot >= held.size() or held[slot] < 0):
			play_event("respawn", at + CENTRE)
		_last_pos[slot] = at
	for a in actors.size():
		for b in range(a + 1, actors.size()):
			var key := a * 64 + b
			if not _active(a) or not _active(b) or (a < held.size() and (held[a] >= 0 or held[b] >= 0)):
				_pair_gap.erase(key)
				continue
			var pa: Vector3 = actors[a].global_position
			var pb: Vector3 = actors[b].global_position
			var gap := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			var before = _pair_gap.get(key)
			_pair_gap[key] = gap
			if before == null or gap > SHOVE_RANGE or absf(pa.y - pb.y) > 1.2 or delta <= 0.0: continue
			if (float(before) - gap) / delta < SHOVE_SPEED or _clock - float(_pair_at.get(key, -100.0)) < SHOVE_GAP: continue
			_pair_at[key] = _clock
			play_event("shove", (pa + pb) * 0.5 + CENTRE)

## The yard: a courier stepping onto a walk-in pad, the countdown's last three seconds.
func _watch_lobby() -> void:
	for slot in _run.actors.size():
		if not _active(slot): continue
		var before: String = _zones.get(slot, "")
		var zone := WalkInLobby.zone_at(_run.actors[slot].position, before)
		if zone != "" and zone != before and _zones.has(slot): play_event("pad_enter", _run.actors[slot].global_position + CENTRE)
		_zones[slot] = zone
	var left := _countdown()
	var tick := ceili(left) if left > 0.0 else 0
	if tick != _beep and tick > 0 and tick <= 3: play_event("countdown", null, 1.0, 2.0 * (3 - tick))
	_beep = tick

## Seconds until the round starts, -1 without a countdown: the local flow's clock, or the match the client got online.
func _countdown() -> float:
	var presentation = _run.get("local_presentation")
	if presentation != null:
		var flow = presentation.get("level_flow")
		if flow == null or flow.get("_start_at") == null or float(flow.get("_start_at")) < 0.0: return -1.0
		return float(flow.get("_start_at")) - float(flow.get("_clock"))
	var scene := get_tree().current_scene
	var info = scene.get("match_info") if scene != null else null
	return float(info.get("start_in", -1.0)) if info is Dictionary and info.get("phase", "lobby") == "lobby" else -1.0

## The wardrobe (character/wardrobe/wardrobe.gd) in the yard: its opened and closed signals and the picker's look changes.
func _watch_wardrobe() -> void:
	if is_instance_valid(_wardrobe): return
	if int(_clock * 2.0) % 2 != 0: return # look for it twice a second at most
	_wardrobe = _run.world.find_child("Wardrobe", true, false)
	if _wardrobe == null or not _wardrobe.has_signal("opened"): return
	_wardrobe.opened.connect(_on_wardrobe_opened)
	_wardrobe.closed.connect(func(_slot: int) -> void: play_event("wardrobe_close"))

func _on_wardrobe_opened(_slot: int) -> void:
	play_event("wardrobe_open")
	var panel = _wardrobe.get("panel")
	if panel != null and panel.has_signal("look_changed") and not panel.look_changed.is_connected(_on_look_changed):
		panel.look_changed.connect(_on_look_changed)

func _on_look_changed(_look) -> void:
	if _clock - _wardrobe_look < 0.12: return # a slider drag is one sound
	_wardrobe_look = _clock
	play_event("wardrobe_pick")

## Balloon rounds: grabs and lifts, throws and escapes (the replicated holders), slaps (the arm swings every client starts),
## zaps and burns (the scorch counters), the balloon falling low and coming back.
func _watch_team(delta: float) -> void:
	if not _in_balloon_round():
		_held = PackedInt32Array()
		_releases.clear()
		return
	var team = _run.team
	var actors: Array = _run.actors
	var held: PackedInt32Array = team.contact.held_by if team.contact != null else PackedInt32Array()
	if _held.size() == held.size():
		for slot in held.size():
			if held[slot] == _held[slot] or slot >= actors.size(): continue
			if held[slot] >= 0 and held[slot] < actors.size():
				var lift_at: Vector3 = actors[held[slot]].global_position + CENTRE
				play_grab(lift_at)
				play_event("lift", lift_at)
				_held_since[slot] = _clock
			elif held[slot] < 0:
				_releases.append({"slot": slot, "from": actors[slot].global_position, "age": 0.0})
	_held = held.duplicate()
	for index in range(_releases.size() - 1, -1, -1):
		var release: Dictionary = _releases[index]
		release.age = float(release.age) + delta
		if float(release.age) < THROW_TEST: continue
		_releases.remove_at(index)
		var now: Vector3 = actors[int(release.slot)].global_position
		if now.distance_to(release.from) > THROW_MOVE: play_throw(now + CENTRE)
		else: play_escape(now + CENTRE)
	var swings := int(team.slaps_shown)
	if _swings >= 0 and swings > _swings:
		var near: Variant = _nearest_to_balloon()
		play_event("swing", near)
		if near is Vector3 and _balloon_point() is Vector3 and (near as Vector3).distance_to(_balloon_point()) < 2.2: play_slap(near)
	_swings = swings
	var counts: PackedInt32Array = team.scorches if not team.scorches.is_empty() else team._scorches_seen
	if _scorches.size() == counts.size():
		for slot in mini(counts.size() / 2, actors.size()):
			if counts[slot * 2] > _scorches[slot * 2]:
				play_scorch("burn" if counts[slot * 2 + 1] == 2 else "zap", actors[slot].global_position + CENTRE)
				_scorch_pending = false
	_scorches = counts.duplicate()
	if _scorch_pending:
		_scorch_pending = false
		play_scorch("zap")
	var shown = team.view if team.view != null else team.balloon
	if shown == null: return
	if shown.alive and not _balloon_alive: play_event("balloon_respawn", shown.position)
	_balloon_alive = shown.alive
	if shown.alive and shown.velocity.y < -0.4 and _clock - _near_drop_at > NEAR_DROP_GAP:
		var floor_y: float = _run.floor_at(shown.position).y
		if shown.position.y - floor_y < NEAR_DROP_HEIGHT and shown.position.y - floor_y > 0.0:
			_near_drop_at = _clock
			play_event("near_drop", shown.position)

func _nearest_to_balloon() -> Variant:
	var point = _balloon_point()
	if not point is Vector3: return null
	var best: Variant = null
	for slot in _run.actors.size():
		if not _active(slot): continue
		var at: Vector3 = _run.actors[slot].global_position + CENTRE
		if best == null or at.distance_to(point) < (best as Vector3).distance_to(point): best = at
	return best

## The level's movers (levels/level_world.gd, posed from the level clock on every role): fire jets ignite, spike beds rise,
## crushers slam, sweepers swing; lasers hum, balls roll and lifts whir on looping voices (the nearest few).
func _watch_hazards(delta: float) -> void:
	var world = _run.level_world
	var k: int = _run.current_level()
	var levels = world.get("_levels") if world != null else null
	if not levels is Array or k < 0 or k >= (levels as Array).size():
		_stop_loops()
		return
	if k != _hazard_level:
		_stop_loops()
		_hazards.clear()
		_hazard_level = k
	var ear: Vector3 = _listener.global_position if is_instance_valid(_listener) else Vector3.ZERO
	var movers: Array = levels[k].movers
	var wanted := []
	for index in movers.size():
		var mover: Dictionary = movers[index]
		var h: Dictionary = mover.h
		var pose = mover.pose
		var body = mover.get("body")
		var at: Vector3 = (body as Node3D).global_position if body is Node3D and is_instance_valid(body) else world.level_origin(k) + pose.position
		var memo: Dictionary = _hazards.get(index, {})
		var kind := str(h.k)
		var spiked := str(h.get("look", "")) == "spikes"
		var rides := str(h.get("ride", "")) != "" # a ferry or lift people stand on (levels/hazards.gd normalize)
		var speed := 0.0
		var dy := 0.0
		if not memo.is_empty() and delta > 0.0:
			speed = at.distance_to(memo.at) / delta
			dy = (at.y - (memo.at as Vector3).y) / delta
			if at.distance_to(ear) < HAZARD_RANGE * 1.5:
				if kind == "fire" and pose.active and not memo.active: play_event("fire", at)
				elif kind == "spikes" and dy > 0.5 and float(memo.dy) <= 0.5: play_event("spikes", at)
				elif kind == "lift" and spiked and float(memo.dy) < -0.5 and dy > -0.1: play_event("crusher", at)
				elif kind == "slide" and not rides and speed > 0.8 and float(memo.speed) <= 0.8: play_event("sweeper", at)
		_hazards[index] = {"active": pose.active, "at": at, "dy": dy, "speed": speed}
		var loop := ""
		if kind == "laser" and pose.active: loop = "laser"
		elif kind == "ball" and pose.active and speed > 0.5: loop = "ball"
		elif ((kind == "lift" and not spiked) or (kind == "slide" and rides)) and speed > 0.2: loop = "lift"
		var distance := at.distance_to(ear)
		if loop != "" and distance < HAZARD_RANGE: wanted.append([distance, index, loop, at])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	wanted.resize(mini(wanted.size(), HAZARD_VOICES))
	var keep := {}
	for item: Array in wanted:
		keep[item[1]] = true
		_loop_voice(int(item[1]), str(item[2]), item[3])
	for index in _loops.keys():
		if not keep.has(index): _stop_loop(index)

func _loop_voice(index: int, id: String, at: Vector3) -> void:
	var entry: Dictionary = load_mix().get("loops", {}).get(id, {})
	if entry.is_empty() or not playback_enabled: return
	var player: AudioStreamPlayer3D = _loops.get(index)
	if not is_instance_valid(player) or player.get_meta("loop", "") != id:
		_stop_loop(index)
		var stream := _stream(str(entry.resource))
		if stream == null: return
		if stream is AudioStreamOggVorbis: (stream as AudioStreamOggVorbis).loop = true
		player = AudioStreamPlayer3D.new()
		player.stream = stream
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.bus = SFX_BUS
		player.set_meta("loop", id)
		add_child(player)
		player.global_position = at
		_spatial.append({"node": player, "gain": float(entry.gain), "radius": float(entry.radius_m), "falloff": float(entry.falloff_m)})
		_set_gain(player, float(entry.gain), float(entry.radius_m), float(entry.falloff_m))
		player.play(randf() * stream.get_length())
		_loops[index] = player
		played.emit({"kind": "loop_" + id, "resource": entry.resource, "gain": float(entry.gain), "pitch": 1.0, "position": at})
	player.global_position = at

func _stop_loop(index: int) -> void:
	var player: AudioStreamPlayer3D = _loops.get(index)
	_loops.erase(index)
	if is_instance_valid(player): player.queue_free()

func _stop_loops() -> void:
	for index in _loops.keys(): _stop_loop(index)

## Carry rounds: the painting rattles when a hit block or hazard comes within WOBBLE_MARGIN of its break box.
func _watch_painting(delta: float) -> void:
	_wobble_wait -= delta
	if _wobble_wait > 0.0 or str(_run.play_mode) != "carry" or _run.round_mode == "lobby": return
	_wobble_wait = 0.1
	var painting = _run.painting
	if painting == null or not is_instance_valid(painting) or painting.broken or bool(_run.won) or float(painting.age) < Painting.BREAK_GRACE: return
	var box := BoxShape3D.new()
	box.size = Painting.BREAK_SIZE + Vector3.ONE * WOBBLE_MARGIN * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = (painting as Node3D).global_transform
	query.collision_mask = Painting.BREAK_LAYER
	if _run.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return
	_wobble_wait = WOBBLE_GAP
	play_event("wobble", (painting as Node3D).global_position)

# ------------------------------------------------------------------ data
const CarryItem := preload("res://style/carry_item.gd")

## The complete sound contract (audio/sfx/mix.json).
static func load_mix() -> Dictionary:
	if _mix.is_empty():
		var path := "res" + "://audio/sfx/mix.json"
		if not FileAccess.file_exists(path):
			push_error("GW_AUDIO sound mix is missing: " + path)
			return _mix
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("schema") == MIX_SCHEMA: _mix = parsed
		else: push_error("GW_AUDIO sound mix is invalid")
	return _mix

## An entry of mix.json "events": {variants, gain, pitch_semitones?, cooldown_s?, radius_m?, falloff_m?}.
static func event_entry(id: String) -> Dictionary:
	return load_mix().get("events", {}).get(id, {})

## A random variant of the event `id` as a stream (the menu pet, the UI cues); null when unknown.
static func event_stream(id: String) -> AudioStream:
	var entry := event_entry(id)
	return stream_for(str(entry.variants.pick_random())) if not entry.is_empty() else null

## The UI cue `cue` (hover, click, back, toggle, stamp, start): event "ui_<cue>".
static func ui_stream(cue: StringName) -> AudioStream:
	return event_stream("ui_" + str(cue))

## The menu pet's sound for `cue` (happy, sad, pet, idle, poke, curious): event "pet_<cue>".
static func pet_stream(cue: String) -> AudioStream:
	return event_stream("pet_" + cue)

## Break sound by id: "break_painting" (default). {resource, duration_s, gain, pitch, ...}.
static func break_entry(id := "break_painting") -> Dictionary:
	var breaks: Dictionary = load_mix().get("breaks", {})
	return breaks.get(id, breaks.get("break_painting", {}))

static func attenuation(distance: float, radius := 0.32, falloff := 12.0) -> float:
	return clampf(1.0 - maxf(distance - radius, 0.0) / falloff, 0.0, 1.0)

static func break_gain(distance: float) -> float:
	return attenuation(distance, BREAK_RADIUS, BREAK_FALLOFF)

## Any sound resource of the mix, loaded once: an Ogg Vorbis file, a whole WAV or an atlas region (load_wave).
static func stream_for(resource: String) -> AudioStream:
	if _static_streams.has(resource): return _static_streams[resource]
	var stream: AudioStream = load_ogg(resource) if resource.ends_with(".ogg") else load_wave(resource)
	if stream == null:
		push_error("GW_AUDIO cannot load sound: " + resource)
		return null
	_static_streams[resource] = stream
	return stream

## An Ogg Vorbis file: the raw file in a source checkout, the imported resource in a pack.
static func load_ogg(path: String) -> AudioStreamOggVorbis:
	if FileAccess.file_exists(path): return AudioStreamOggVorbis.load_from_file(path)
	if ResourceLoader.exists(path): return ResourceLoader.load(path) as AudioStreamOggVorbis
	return null

## A whole WAV (a file in a source checkout, an imported resource in a pack) or, for `path#start+frames`, that region (in
## frames) of a PCM16 atlas WAV, cut out once per use.
static func load_wave(path: String) -> AudioStreamWAV:
	var cut := path.find("#")
	if cut < 0: return _whole(path)
	var spec := path.substr(cut + 1).split("+")
	var file := path.substr(0, cut)
	var base: AudioStreamWAV = _atlases.get(file)
	if base == null:
		base = _whole(file)
		_atlases[file] = base
	if base == null or spec.size() != 2 or base.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error("GW_AUDIO cannot cut atlas region: " + path)
		return null
	var width := 2 * (2 if base.stereo else 1)
	var start := int(spec[0]) * width
	var length := int(spec[1]) * width
	if start < 0 or length <= 0 or start + length > base.data.size():
		push_error("GW_AUDIO atlas region out of range: " + path)
		return null
	var stream := AudioStreamWAV.new()
	stream.format = base.format
	stream.stereo = base.stereo
	stream.mix_rate = base.mix_rate
	stream.data = base.data.slice(start, start + length)
	return stream

static func _whole(path: String) -> AudioStreamWAV:
	# Imported WAVs use a lossless policy (the default QOA is lossy): prefer the raw file when it exists.
	if FileAccess.file_exists(path): return AudioStreamWAV.load_from_file(path)
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		var resource := ResourceLoader.load(path, "AudioStreamWAV")
		if resource is AudioStreamWAV: return resource
	push_error("GW_AUDIO cannot load WAV: " + path)
	return null

## The three buses below Master: GW_Music, GW_Effects, GW_Voice (client/settings.gd VOLUME_BUSES: the Settings sliders).
static func ensure_buses() -> void:
	var added := false
	for bus: String in [MUSIC_BUS, SFX_BUS, VOICE_BUS]:
		if AudioServer.get_bus_index(bus) >= 0: continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")
		added = true
	if added: load("res://client/settings.gd").apply_saved_audio() # the saved Effects and Voice volumes onto the new buses

# ------------------------------------------------------------------ music
const TeamCast := preload("res://style/team_cast.gd")

## The one music player. It lives on the scene-tree root, not in a scene, so it keeps playing across menu, online match and
## local play; the first caller creates it (with the title's track), later callers find it. set_music() changes the track.
static func install_music(tree: SceneTree) -> AudioStreamPlayer:
	if tree == null: return null
	var existing := tree.root.get_node_or_null(NodePath(MUSIC_NAME))
	if existing is AudioStreamPlayer: return existing
	if is_instance_valid(_music_pending): return _music_pending
	var path := music_path("menu")
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("GW_AUDIO music stream is unavailable: " + path)
		return null
	var stream := music_stream(path)
	if stream == null: return null
	var settings = load("res://client/settings.gd")
	settings.ensure_music_bus()
	ensure_buses()
	settings.apply_saved_audio() # volumes before the first note, also where no Settings screen exists yet
	var player := AudioStreamPlayer.new()
	player.name = MUSIC_NAME
	player.stream = stream
	player.bus = MUSIC_BUS
	player.volume_db = MUSIC_VOLUME_DB
	player.process_mode = Node.PROCESS_MODE_ALWAYS # plays through pauses and menus
	player.set_meta("music_path", path)
	_music_pending = player
	tree.root.add_child.call_deferred(player) # the root is busy while a scene's _ready runs
	player.play.call_deferred()
	return player

## The track of a phase: "menu" (title), "lobby" (the yard), "results" (the end sting, once), "game" (the cast's music id,
## style/team_cast.gd music_path()). mix.json "music" names the first three; a missing one plays the cast's.
static func music_path(context: String) -> String:
	var path := str(load_mix().get("music", {}).get(context, ""))
	if path != "" and (FileAccess.file_exists(path) or ResourceLoader.exists(path)): return path
	return TeamCast.music_path()

## Fades the music player over to the track of `context` (no change when it already plays it).
static func set_music(tree: SceneTree, context: String) -> void:
	if tree == null: return
	var player := tree.root.get_node_or_null(NodePath(MUSIC_NAME)) as AudioStreamPlayer
	if player == null or not player.is_inside_tree(): return
	var path := music_path(context)
	if str(player.get_meta("music_path", "")) == path: return
	player.set_meta("music_path", path)
	var stream := music_stream(path, context != "results")
	if stream == null: return
	var fade := player.create_tween()
	fade.tween_property(player, "volume_db", -40.0, MUSIC_FADE * 0.5)
	fade.tween_callback(func() -> void:
		player.stream = stream
		player.play())
	fade.tween_property(player, "volume_db", MUSIC_VOLUME_DB, MUSIC_FADE)

## The music file at `path` as a stream that repeats from its first sample (`loop`): a PCM16 WAV or an Ogg Vorbis loop (the
## loop is set here, so no import setting is needed). Null when it does not load.
static func music_stream(path: String, loop := true) -> AudioStream:
	if path.ends_with(".ogg"):
		var ogg := load_ogg(path)
		if ogg == null:
			push_error("GW_AUDIO music must be an Ogg Vorbis loop: " + path)
			return null
		ogg.loop = loop
		ogg.loop_offset = 0.0
		return ogg
	var stream := load_wave(path)
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error("GW_AUDIO music must be a PCM16 loop")
		return null
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream

## Evidence for tools: the music player and its bus.
static func music_probe(tree: SceneTree) -> Dictionary:
	var player := tree.root.get_node_or_null(NodePath(MUSIC_NAME)) as AudioStreamPlayer
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	return {"exists": player != null, "playing": player != null and player.playing,
		"track": str(player.get_meta("music_path", "")) if player != null else "",
		"position": player.get_playback_position() if player != null and player.playing else -1.0,
		"bus_found": bus >= 0, "bus_volume_linear": AudioServer.get_bus_volume_linear(bus) if bus >= 0 else -1.0,
		"bus_muted": AudioServer.is_bus_mute(bus) if bus >= 0 else false,
		"master_linear": AudioServer.get_bus_volume_linear(0),
		"peak_db": [AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0)] if bus >= 0 else [-200.0, -200.0],
		"master_peak_db": [AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0)]}
