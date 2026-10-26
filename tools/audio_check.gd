extends SceneTree
## Headless check of the sound contract (demo/audio/sfx/mix.json, game/game_audio.gd):
##
##   "$SUMMER" --headless --audio-driver Dummy --path demo -s "$PWD/tools/audio_check.gd"
##
## 1. Every resource the mix names (slots, footsteps, blink cues, breaks, end music, events, loops, music) loads as a stream
##    with a length.
## 2. Every event plays: play_event() starts a player on the GW_Effects bus with a stream, placed in the world when it has a radius.
## 3. The UI cues and the menu pet's cues resolve; the hazard loops repeat.
## 4. The buses GW_Music, GW_Effects and GW_Voice exist under Master; the music player changes track per phase and loops.
## 5. The watcher on a stand-in run (the fields game_audio reads): a walk-in pad, the countdown, GO, a grab and lift, a throw, an
##    escape, a slap, a zap, a pop, the balloon back and falling low, a fire jet, a room cleared, the results' music.
## Prints AUDIO_CHECK ok=<bool> and exits 0 only when all pass.
const GameAudio := preload("res://game/game_audio.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const UI_CUES := ["hover", "click", "back", "toggle", "stamp", "start"]
const PET_CUES := ["happy", "sad", "pet", "idle", "poke", "curious"]
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok: failures.append(what)

func _run() -> void:
	var mix := GameAudio.load_mix()
	check(not mix.is_empty(), "mix.json loads")
	var resources := {}
	for slot: String in ["jump", "death", "push", "bounce", "checkpoint", "easter", "end_music"]: resources[str(mix[slot].resource)] = slot
	for wave: Dictionary in mix.footsteps.waves: resources[str(wave.resource)] = "footsteps"
	for surface: String in mix.footsteps.get("surfaces", {}):
		for wave in mix.footsteps.surfaces[surface].waves: resources[str(wave)] = "footsteps " + surface
	for kind: String in ["crack", "broken"]: resources[str(mix.timer[kind].resource)] = "timer"
	for id: String in mix.breaks: resources[str(mix.breaks[id].resource)] = "breaks"
	for id: String in mix.events:
		check(not (mix.events[id].variants as Array).is_empty(), "event %s has variants" % id)
		for variant in mix.events[id].variants: resources[str(variant)] = "event " + id
	for id: String in mix.loops: resources[str(mix.loops[id].resource)] = "loop " + id
	for context: String in mix.music: resources[str(mix.music[context])] = "music " + context
	var loaded := 0
	for resource: String in resources:
		var stream := GameAudio.music_stream(resource) if str(resources[resource]).begins_with("music") else GameAudio.stream_for(resource)
		if stream == null or stream.get_length() <= 0.0: failures.append("%s does not load: %s" % [resources[resource], resource])
		else: loaded += 1
	# 2. every event plays a stream
	GameAudio.ensure_buses()
	for bus: String in [GameAudio.MUSIC_BUS, GameAudio.SFX_BUS, GameAudio.VOICE_BUS]:
		var index := AudioServer.get_bus_index(bus)
		check(index > 0 and AudioServer.get_bus_send(index) == &"Master", "bus %s exists and sends to Master" % bus)
	var world := Node3D.new()
	root.add_child(world)
	var ear := Node3D.new()
	world.add_child(ear)
	var audio := GameAudio.new()
	world.add_child(audio)
	audio.configure(ear)
	var heard: Array = []
	audio.played.connect(func(event: Dictionary) -> void: heard.append(event))
	var played := 0
	for id: String in mix.events:
		heard.clear()
		var before := audio.get_child_count()
		var at: Variant = Vector3(1.0, 0.0, 1.0) if mix.events[id].has("radius_m") else null
		var ok := audio.play_event(id, at)
		var player: Node = audio.get_child(audio.get_child_count() - 1) if audio.get_child_count() > before else null
		var stream: AudioStream = player.get("stream") if player != null else null
		if not ok or heard.size() != 1 or heard[0].kind != id or stream == null:
			failures.append("event %s does not play (ok=%s heard=%d stream=%s)" % [id, ok, heard.size(), stream != null])
			continue
		check(str(player.get("bus")) == GameAudio.SFX_BUS, "event %s plays on %s" % [id, GameAudio.SFX_BUS])
		check((player is AudioStreamPlayer3D) == (at != null), "event %s is placed in the world exactly when it has a radius" % id)
		check(bool(player.get("playing")), "event %s player is playing" % id)
		played += 1
	# 3. UI, pet, loops
	for cue: String in UI_CUES: check(GameAudio.ui_stream(cue) != null, "UI cue %s resolves" % cue)
	for cue: String in PET_CUES: check(GameAudio.pet_stream(cue) != null, "pet cue %s resolves" % cue)
	for id: String in mix.loops:
		audio.call("_loop_voice", 100 + (mix.loops.keys() as Array).find(id), id, Vector3(2.0, 0.0, 0.0))
	var loops: Dictionary = audio.get("_loops")
	check(loops.size() == mix.loops.size(), "every hazard loop starts a voice (%d of %d)" % [loops.size(), mix.loops.size()])
	for index in loops:
		var voice: AudioStreamPlayer3D = loops[index]
		check(voice.playing and voice.stream is AudioStreamOggVorbis and (voice.stream as AudioStreamOggVorbis).loop, "hazard loop %s repeats" % voice.get_meta("loop"))
	audio.call("_stop_loops")
	# 3b. stage tiles: a tile out of earshot plays nothing, a burst of tiles starts a bounded number of voices, a nearer tile is louder than a farther one, a tile's drop takes over the
	# voice of its own crack, and the pool never grows past TILE_POOL players
	heard.clear()
	audio.tile_warn(900, Vector3(500.0, 0.0, 0.0))
	check(heard.is_empty(), "a stage tile 500 m away is not played")
	for index in 20: audio.tile_warn(index, Vector3(1.0, 0.0, 1.0))
	check(heard.size() == GameAudio.TILE_VOICES and heard.all(func(event: Dictionary) -> bool: return str(event.kind) == "tile_crack"), "a burst of 20 white tiles starts %d crack voices (%d)" % [GameAudio.TILE_VOICES, heard.size()])
	await create_timer(GameAudio.TILE_WINDOW * 1.5).timeout
	heard.clear()
	audio.tile_warn(40, Vector3(1.0, 0.0, 0.0))
	audio.tile_warn(41, Vector3(25.0, 0.0, 0.0))
	check(heard.size() == 2 and float(heard[0].gain) > float(heard[1].gain) and float(heard[1].gain) > 0.0, "a tile 25 m away is quieter than one beside the listener (%s)" % str(heard.map(func(event: Dictionary) -> float: return snappedf(float(event.gain), 0.01))))
	await create_timer(GameAudio.TILE_WINDOW * 1.5).timeout
	var pool_before := (audio.get("_tile_voices") as Array).size()
	heard.clear()
	audio.tile_drop(40, Vector3(1.0, 0.0, 0.0))
	check(heard.size() == 1 and str(heard[0].kind) == "tile_broken" and (audio.get("_tile_voices") as Array).size() == pool_before, "the drop of tile 40 takes over its crack's voice (pool %d)" % (audio.get("_tile_voices") as Array).size())
	check((audio.get("_tile_voices") as Array).size() <= GameAudio.TILE_POOL, "the tile voice pool stays at %d players or fewer" % GameAudio.TILE_POOL)
	# 4. music per phase
	GameAudio.install_music(self)
	await process_frame
	await process_frame
	var probe := GameAudio.music_probe(self)
	check(probe.exists and probe.playing and probe.track == str(mix.music.menu), "the music starts on the title track (%s)" % probe.track)
	for context: String in ["lobby", "game", "results", "menu"]:
		GameAudio.set_music(self, context)
		for i in 60: await process_frame
		probe = GameAudio.music_probe(self)
		var player := root.get_node(GameAudio.MUSIC_NAME) as AudioStreamPlayer
		check(probe.track == GameAudio.music_path(context) and probe.playing, "music %s plays its track (%s)" % [context, probe.track])
		check(player.bus == &"GW_Music", "music plays on GW_Music")
	await _check_watcher()
	print("AUDIO_CHECK resources=", loaded, "/", resources.size(), " events=", played, "/", mix.events.size(), " loops=", mix.loops.size())
	for failure in failures: printerr("AUDIO_CHECK_FAIL ", failure)
	print("AUDIO_CHECK ok=", failures.is_empty(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ------------------------------------------------------------------ 5. the watcher on a stand-in run
## A run with just the fields game_audio reads (game/game_run.gd, game/team_play.gd, levels/level_world.gd, the local flow).
class FakePose extends RefCounted:
	var position := Vector3.ZERO
	var active := false

class FakeBalloon extends RefCounted:
	var position := Vector3(0.0, 3.0, 0.0)
	var velocity := Vector3.ZERO
	var alive := true

class FakeContact extends RefCounted:
	var held_by := PackedInt32Array([-1, -1, -1])

class FakeTeam extends RefCounted:
	var contact := FakeContact.new()
	var balloon := FakeBalloon.new()
	var view = null
	var slaps_shown := 0
	var scorches := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var _scorches_seen := PackedInt32Array()

class FakeFlow extends RefCounted:
	var phase := "lobby"
	var _start_at := -1.0
	var _clock := 0.0

class FakePresentation extends RefCounted:
	var started := true
	var level_flow := FakeFlow.new()

class FakeLevels extends RefCounted:
	var _levels: Array = []
	func level_origin(_k: int) -> Vector3: return Vector3.ZERO

class FakeRun extends Node3D:
	var round_mode := "lobby"
	var network_role := "local"
	var play_mode := "balloon"
	var failure_kind := ""
	var won := false
	var actors: Array = []
	var world: Node3D
	var team := FakeTeam.new()
	var level_world := FakeLevels.new()
	var painting = null
	var local_presentation := FakePresentation.new()
	var level := -1
	func current_level() -> int: return level if round_mode != "lobby" else -1
	func is_slot_active(slot: int) -> bool: return slot < actors.size()
	func floor_at(at: Vector3) -> Vector3: return Vector3(at.x, 0.0, at.z)

func _frames(count: int) -> void:
	for i in count: await process_frame

func _check_watcher() -> void:
	var run := FakeRun.new()
	run.world = Node3D.new()
	run.add_child(run.world)
	for slot in 3:
		var body := CharacterBody3D.new()
		run.world.add_child(body)
		body.position = Vector3(slot * 3.0, 0.0, 6.0)
		run.actors.append(body)
	var fire := FakePose.new()
	var fire_body := Node3D.new()
	run.world.add_child(fire_body)
	run.level_world._levels = [{"movers": [{"h": {"k": "fire", "look": "", "ride": ""}, "pose": fire, "body": fire_body}]}]
	root.add_child(run)
	var audio := GameAudio.new()
	audio.playback_enabled = false
	run.add_child(audio)
	audio.configure(run.actors[0])
	var kinds: Array = []
	audio.played.connect(func(event: Dictionary) -> void: kinds.append(event.kind))
	await _frames(3)
	# the yard: a pad, the countdown, GO
	run.actors[1].position = WalkInLobby.center(WalkInLobby.PADS[0].course) + Vector3(0.0, 0.0, 0.0)
	await _frames(2)
	check("pad_enter" in kinds, "watcher: stepping onto a walk-in pad chimes (%s)" % [kinds])
	run.local_presentation.level_flow._start_at = 2.5
	await _frames(2)
	run.local_presentation.level_flow._clock = 1.2
	await _frames(2)
	check(kinds.count("countdown") == 2, "watcher: one beep per countdown second (%s)" % [kinds])
	kinds.clear()
	run.local_presentation.level_flow._start_at = -1.0
	run.round_mode = "level"
	run.level = 0
	run.local_presentation.level_flow.phase = "round"
	await _frames(2)
	check("go" in kinds, "watcher: GO when the round starts (%s)" % [kinds])
	kinds.clear()
	# a grab, then a throw
	run.team.contact.held_by[1] = 0
	await _frames(2)
	check("grab" in kinds and "lift" in kinds, "watcher: a grab and a lift (%s)" % [kinds])
	run.team.contact.held_by[1] = -1
	await _frames(1)
	run.actors[1].position += Vector3(0.0, 1.0, 2.0)
	await create_timer(0.3).timeout
	check("throw" in kinds and not "escape" in kinds, "watcher: a release that flies is a throw (%s)" % [kinds])
	kinds.clear()
	run.team.contact.held_by[2] = 0
	await _frames(2)
	run.team.contact.held_by[2] = -1
	await create_timer(0.3).timeout
	check("escape" in kinds, "watcher: a release that stays is an escape (%s)" % [kinds])
	kinds.clear()
	# a slap near the balloon, a zap, a pop, the balloon back, a low balloon, the hazards, the goal
	run.team.balloon.position = run.actors[0].position + Vector3(0.0, 1.5, 0.5)
	run.team.slaps_shown += 1
	await _frames(2)
	check("swing" in kinds and "slap" in kinds, "watcher: a slap near the balloon swings and smacks (%s)" % [kinds])
	run.team.scorches[3] = 1
	run.team.scorches[2] = 1
	await _frames(2)
	check("zap" in kinds, "watcher: a scorch counter going up zaps that player (%s)" % [kinds])
	kinds.clear()
	for kind: String in ["pick", "throw", "knock"]: audio.play_prop({"kind": kind, "position": Vector3(1.0, 0.0, 1.0)})
	check(kinds == ["grab", "throw", "shove"], "yard props: pick, throw and knock sounds (%s)" % [kinds])
	run.failure_kind = "pop"
	audio.play_death()
	check("pop" in kinds and not "death" in kinds, "a pop in a balloon round pops, no sad splash (%s)" % [kinds])
	run.failure_kind = ""
	run.team.balloon.alive = false
	await _frames(2)
	run.team.balloon.alive = true
	run.team.balloon.position = Vector3(0.0, 1.0, 0.0)
	run.team.balloon.velocity = Vector3(0.0, -1.0, 0.0)
	await _frames(2)
	check("balloon_respawn" in kinds and "near_drop" in kinds, "watcher: the balloon comes back, then falls low (%s)" % [kinds])
	fire.active = true
	await _frames(2)
	check("fire" in kinds, "watcher: a fire jet igniting whooshes (%s)" % [kinds])
	run.won = true
	await _frames(2)
	check("room_clear" in kinds, "watcher: a balloon room cleared (%s)" % [kinds])
	run.local_presentation.level_flow.phase = "results"
	await _frames(2)
	check(GameAudio.music_probe(self).track == str(GameAudio.load_mix().music.results), "watcher: the results play the end sting")
	run.queue_free()
	await _frames(2)
