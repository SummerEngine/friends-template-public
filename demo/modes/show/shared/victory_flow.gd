extends CanvasLayer
## The show's ending (docs/party-show.md "The victory sequence"), client only, a pure function of the state it is given (phase "done" with `victory`, then "podium", `t` = the phase's seconds):
##   1. the winner's VICTORY banner pops over the gameplay (ShowBanner, a 2D overlay of this layer) with a short burst of paper ribbons, holds still, and is gone on one frame; a short beat of plain gameplay;
##   2. a hard cut into the podium room (style/podium_room.gd, built far away, with its own sky and light) in three shots: low and close under the middle screen, a pedestal close-up that tilts up, then the wide
##      frontal shot that settles and creeps in on the winner;
##   3. the top three stand on their pedestals from the cut on (3rd, 2nd and 1st are in every shot that frames a pedestal, on every client: the flow draws them on their spots whatever their actors say); they take
##      their moment 3 -> 2 -> 1, each with a squash-and-stretch hop about its feet, a burst from its screen's horns and the screen's flash; the winner's crown comes down onto its head; every winner plays
##      the cast's own emote; the winners' names come up on the plates under the billboards and the champion banner pops in over the middle one; the screens glint, the horns fire again; then the results page.
## The hold of the winners on their spots, the authority's side of all this, is modes/show/rules.gd (PODIUM_*), the pedestals' collision is the room's own.
const PodiumRoom := preload("res://style/podium_room.gd")
const ShowBanner := preload("res://style/show_banner.gd")
const ShowTheme := preload("res://client/show_theme.gd")
const TeamCast := preload("res://style/team_cast.gd")

# The podium phase's clock (seconds from the hard cut into the room): three shots of 0.67 / 0.67 / settling in 0.8 s, the names on the screens 2.3 s after the cut and the glint
# sweep a second after them; the landings, the crown and the bursts are ours.
const SHOT_2 := 0.7 ## s: the pedestal close-up (the cut)
const SHOT_3 := 1.4 ## s: the wide shot (the cut)
const SETTLE := 0.8 ## s the wide shot's dolly-out takes to settle
const LAND := [3.5, 2.6, 1.7] ## s each rank's winner takes its moment (1st, 2nd, 3rd): the hop, the burst, the emote follows (they stand on the pedestal before)
const FACE := PI ## the winners face +Z, towards the camera (rules.gd PODIUM_YAW)
const DROP := 0.5 ## s of a moment's squash and stretch
const EMOTE_AFTER := 0.4 ## s after its moment the winner starts its emote
const CROWN_AT := 3.9 ## s the crown comes down onto the winner
const CHAMPION_AT := 3.85 ## s the champion banner pops in over the middle billboard
const GLINT := 5.0 ## s the glint sweeps the screens (left to right: 2nd, 1st, 3rd, 0.2 s apart)
const GLINT_ORDER := [1, 0, 2]
const PUSH_FROM := 3.6 ## s the slow push in on the winner begins
const PUSH_TO := 9.6
const CUE := 0.5 ## s the room is up before the first horn goes off
## The victory banner (rules.gd VICTORY is its length): 1.45 s on screen, the cut 0.25 s after it.
const BANNER_SHOW := 1.45
const BANNER_WIDE := 0.4 ## share of the screen's width
const BANNER_AT := 0.35 ## share of the screen's height
const RIBBONS := 26
const RIBBON_LIFE := 0.7
const WIDE_FIT := 10.6 ## m: half the width the wide shot shows at the screens' plane
const VERT_FIT := 5.8 ## m: half the height the wide shot shows at the screens' plane at least (a wide phone window is fitted by its height)
const FRAME_FOV := 44.0 ## the wide shot's fov

var _room: Node3D
var _overlay: Control
var _shell: Variant
var _view: Node3D
var _suns: Array = [] ## [{node, visible}] the course's lights, off while the room is up
var _kept_environment: Environment
var _kept_fov := 0.0
var _taken := false ## the camera's environment and fov are the room's
var _heard := {}
var _emoted := {}
var _scaled: Array[int] = []
var _age := 0.0 ## the overlay's banner age (done phase) or -1
var _words := ""
var _line := ""
var _top: Array = []

func setup(shell: Variant, view: Node3D) -> void:
	_shell = shell
	_view = view
	layer = 30
	_overlay = _Overlay.new()
	_overlay.flow = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

# ------------------------------------------------------------------ the timeline (static: the tools and the checks read it)

## Per rank (1st, 2nd, 3rd) the time of that rank's moment, or -1 for a rank with nobody on it.
static func landed(players: int) -> Array:
	var result: Array = []
	for rank in 3: result.append(float(LAND[rank]) if rank < players else -1.0)
	return result

## The bursts of the podium phase: {at, horn} a cannon from a horn (0 the left one, 1 the right one), {at, pop} a round pop at a point of the room, {at, rain} confetti from the ceiling. Every landing pops over the winner and fires the horn
## on its side (the winner's both, and a rain); the glint and the push in fire them again.
static func bursts(players: int) -> Array:
	var list: Array = []
	for horn in 2: list.append({"at": CUE, "horn": horn, "seed": 11 + horn})
	var spots := PodiumRoom.spots()
	for rank in [2, 1, 0]:
		if rank >= players: continue
		var at: float = LAND[rank]
		var pop: Vector3 = (spots[rank] as Vector3) - PodiumRoom.ORIGIN + Vector3(0.0, 1.3, 0.3)
		list.append({"at": at, "pop": pop, "seed": 100 + rank})
		list.append({"at": at + 0.12, "pop": pop + Vector3(0.0, 0.8, 0.0), "seed": 110 + rank})
		if rank == 0:
			for horn in 2: list.append({"at": at + 0.05, "horn": horn, "seed": 120 + horn})
			list.append({"at": at + 0.15, "rain": true, "seed": 150})
		else:
			var horn := 0 if rank == 1 else 1
			list.append({"at": at + 0.05, "horn": horn, "seed": 130 + rank})
			list.append({"at": at + 0.4, "horn": horn, "seed": 140 + rank})
	if players > 0:
		list.append({"at": GLINT + 0.4, "rain": true, "seed": 165})
		for horn in 2: list.append({"at": GLINT + 0.5, "horn": horn, "seed": 170 + horn})
		list.append({"at": PUSH_TO - 2.4, "rain": true, "seed": 180})
		for horn in 2: list.append({"at": PUSH_TO - 2.3, "horn": horn, "seed": 190 + horn})
	return list

## The camera at `t` s of the podium: {xf: Transform3D (world), fov}. `aspect` = width / height. Three hard cuts (close and low under the middle screen, the pedestals' close-up tilting up, the wide frontal shot),
## then the wide shot settles and creeps in on the winner.
static func shot(t: float, aspect: float, base_fov := FRAME_FOV) -> Dictionary:
	var origin := PodiumRoom.ORIGIN
	var reach := tan(deg_to_rad(base_fov) * 0.5)
	var fit := maxf(maxf(WIDE_FIT / (reach * maxf(aspect, 0.5)), VERT_FIT / reach), 8.0)
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := base_fov
	if t < SHOT_2: # low and close under the middle screen, backing off, ease out
		var f := _ease_out(clampf(t / SHOT_2, 0.0, 1.0))
		eye = Vector3(0.0, lerpf(1.1, 1.45, f), lerpf(3.0, 4.2, f))
		look = Vector3(0.0, 4.9, PodiumRoom.SCREEN_Z)
		fov = 68.0
	elif t < SHOT_3: # the pedestals' close-up, a crane up and a tilt up the front
		var f := clampf((t - SHOT_2) / (SHOT_3 - SHOT_2), 0.0, 1.0)
		eye = Vector3(lerpf(1.0, 0.3, f), lerpf(0.55, 1.3, f), lerpf(4.9, 5.4, f))
		look = Vector3(0.0, lerpf(0.9, 2.5, _ease_out(f)), 0.4)
		fov = 62.0
	else:
		var u := t - SHOT_3
		var settle := _ease_out(clampf(u / SETTLE, 0.0, 1.0))
		var push := _smooth(clampf((t - PUSH_FROM) / (PUSH_TO - PUSH_FROM), 0.0, 1.0))
		var distance := lerpf(fit * 0.74, fit, settle) - fit * 0.12 * push
		look = Vector3(0.0, lerpf(4.0, 4.5, push), PodiumRoom.SCREEN_Z)
		eye = Vector3(0.0, lerpf(3.9, 3.8, push), PodiumRoom.SCREEN_Z + distance)
		fov = base_fov - 2.0 * push
	var shake := 0.0
	for rank in 3:
		var since: float = t - float(LAND[rank])
		if since >= 0.0 and since < 0.5: shake += sin(since * 70.0) * exp(-since * 9.0) * 0.045
	eye.y += shake
	var xf := Transform3D(Basis.IDENTITY, origin + eye).looking_at(origin + look, Vector3.UP)
	return {"xf": xf, "fov": fov}

static func _ease_out(f: float) -> float:
	return 1.0 - pow(1.0 - f, 3.0)

static func _smooth(f: float) -> float:
	return f * f * (3.0 - 2.0 * f)

## A winner's squash and stretch since its moment (age in s): the scale of the character about its feet, a crouch and a spring. Before and after it the character stands as it is.
static func drop_scale(age: float) -> Vector3:
	if age < 0.0 or age >= DROP: return Vector3.ONE
	var f := age / DROP
	var wave := sin(f * TAU) * (1.0 - f) # + first (crouch), then - (the spring up)
	return Vector3(1.0 + wave * 0.16, 1.0 - wave * 0.24, 1.0 + wave * 0.16)

# ------------------------------------------------------------------ per frame

## The newest state. `dt` the frame time.
func present(state: Dictionary, dt: float) -> void:
	var phase := str(state.get("phase", ""))
	var t := float(state.get("t", 0.0))
	_top = state.get("top", []) if state.get("top", []) is Array else []
	if phase == "done" and bool(state.get("victory", false)):
		_ensure_room(false)
		_banner(state, t)
	elif phase == "podium" and state.get("podium", []) is Array and not (state.get("podium", []) as Array).is_empty():
		_age = -1.0
		_ensure_room(true)
		_room_phase(state, t)
	else:
		_age = -1.0
		_clear()
	_overlay.queue_redraw()

func _ensure_room(show: bool) -> void:
	if _room == null:
		var made := PodiumRoom.new()
		_view.get_parent().add_child(made) # beside the view, under the shell's world
		made.build()
		_room = made
	if show and not _taken: _take_camera()

func _banner(state: Dictionary, t: float) -> void:
	_age = t if t < BANNER_SHOW and not bool(state.get("stage", false)) else -1.0 # a stage round's own VICTORY plate (stage_hud.gd) is its banner
	var winner := int(state.get("crown", -1))
	var top: Array = _top
	var slot: int = int(top[0]) if not top.is_empty() else winner
	_words = TeamCast.show_word("champion")
	_line = ""
	if slot >= 0:
		var player: Dictionary = _view.call("cast_player", slot)
		_line = "%s  ·  %s" % [str(player.get("name", "")).to_upper(), str(player.get("catchphrase", ""))] if str(player.get("catchphrase", "")) != "" else str(player.get("name", "")).to_upper()
	_audio("room_clear", "banner", t >= 0.0)

func _room_phase(state: Dictionary, t: float) -> void:
	var cam: Variant = _shell.get("camera")
	var players := mini(_top.size(), 3)
	var names: Array = []
	for rank in players: names.append(str((_view.call("cast_player", int(_top[rank])) as Dictionary).get("name", "")).to_upper())
	(_room as Object).call("set_captions", TeamCast.show_word("champion"), names)
	var times := landed(players)
	var spots := PodiumRoom.spots()
	(_room as Object).call("update", t, times, bursts(players), _flashes(t), CHAMPION_AT if players > 0 else -1.0)
	if cam is Camera3D:
		var size: Vector2 = (cam as Camera3D).get_viewport().get_visible_rect().size
		var aspect := size.x / maxf(size.y, 1.0)
		var framed := shot(t, aspect)
		_shell.set("view_override", framed.xf)
		(cam as Camera3D).fov = float(framed.fov)
	for rank in players:
		var slot := int(_top[rank])
		var rig: Variant = _view.call("rig", slot)
		if rig == null: continue
		var since := t - float(times[rank])
		var rig_scales: Variant = _shell.get("rig_scales")
		if rig_scales is Dictionary: (rig_scales as Dictionary)[slot] = drop_scale(since) # the shell applies it after each rig update (the rig turns itself every update)
		var rig_places: Variant = _shell.get("rig_places")
		if rig_places is Dictionary: (rig_places as Dictionary)[slot] = {"at": spots[rank], "yaw": FACE} # drawn on its pedestal on every client, from the first frame
		if not _scaled.has(slot): _scaled.append(slot)
		if since >= 0.0:
			_audio("slap", "land%d" % rank, true)
			if since >= EMOTE_AFTER and not _emoted.has(slot):
				_emoted[slot] = true
				_emote(rig, slot, rank)
	_view.set("hide_name_tags", true)

## The screens' glint sweep: a white flash from 2nd over 1st to 3rd, per rank.
func _flashes(t: float) -> Array:
	var result := [0.0, 0.0, 0.0]
	for index in GLINT_ORDER.size():
		var since := t - (GLINT + 0.2 * float(index))
		if since >= 0.0 and since <= 0.4: result[GLINT_ORDER[index]] = 1.0 - since / 0.4
	return result

func _emote(rig: Variant, _slot: int, rank: int) -> void:
	if not rig.has_method("play_cast_emote"): return
	var before := ""
	if rig.has_method("cast_emote"): before = str(rig.call("cast_emote"))
	if before != "": rig.call("play_cast_emote")
	elif rig.has_method("play_emote"): rig.call("play_emote", "dance" if rank == 0 else "yes")

func _audio(id: String, key: String, when: bool) -> void:
	if not when or _heard.has(key): return
	_heard[key] = true
	var audio: Variant = _shell.get("audio") if _shell != null else null
	if audio != null and audio.has_method("play_event"): audio.call("play_event", id)

func _take_camera() -> void:
	_taken = true
	var cam: Variant = _shell.get("camera")
	if cam is Camera3D:
		_kept_environment = (cam as Camera3D).environment
		_kept_fov = (cam as Camera3D).fov
		(cam as Camera3D).environment = PodiumRoom.environment()
	var world: Variant = _shell.get("world")
	if world is Node:
		for light: Node in (world as Node).find_children("*", "DirectionalLight3D", true, false):
			if _room != null and _room.is_ancestor_of(light): continue
			if (light as Node3D).visible:
				_suns.append(light)
				(light as Node3D).visible = false

## Everything back as it was: the course's lights, the camera's environment and lens, the characters' scale, the room freed.
func _clear() -> void:
	if _taken:
		_taken = false
		var cam: Variant = _shell.get("camera") if _shell != null else null
		if cam is Camera3D and is_instance_valid(cam):
			(cam as Camera3D).environment = _kept_environment
			(cam as Camera3D).fov = _kept_fov
		for light: Variant in _suns:
			if is_instance_valid(light): (light as Node3D).visible = true
		_suns.clear()
	if _room != null:
		_room.queue_free()
		_room = null
	var rig_scales: Variant = _shell.get("rig_scales") if _shell != null and is_instance_valid(_shell) else null
	if rig_scales is Dictionary:
		for slot in _scaled: (rig_scales as Dictionary).erase(slot)
	var rig_places: Variant = _shell.get("rig_places") if _shell != null and is_instance_valid(_shell) else null
	if rig_places is Dictionary:
		for slot in _scaled: (rig_places as Dictionary).erase(slot)
	_scaled.clear()
	_heard.clear()
	_emoted.clear()
	if is_instance_valid(_view): _view.set("hide_name_tags", false)

func _exit_tree() -> void:
	_clear()

## Draws the banner and its ribbons over the gameplay.
class _Overlay extends Control:
	var flow: Node

	func _draw() -> void:
		var age: float = flow.get("_age")
		if age < 0.0: return
		var size := get_viewport_rect().size
		var wide := size.x * BANNER_WIDE
		var centre := Vector2(size.x * 0.5, size.y * BANNER_AT)
		_ribbons(age, centre, size)
		ShowBanner.draw(self, "victory", str(flow.get("_words")), age, centre, wide, 1.0, str(flow.get("_line")))

	## A short burst of thin paper ribbons thrown over the banner: white, pale green and blue, salmon; deterministic from the age.
	func _ribbons(age: float, centre: Vector2, size: Vector2) -> void:
		if age > RIBBON_LIFE: return
		var colors := [Color("ffffff"), Color("bff0c8"), Color("b9e4ff"), Color("ffb08a")]
		for index in RIBBONS:
			var rng := RandomNumberGenerator.new()
			rng.seed = 4242 + index * 31
			var angle := rng.randf_range(-PI * 0.95, -PI * 0.05)
			var speed := rng.randf_range(0.25, 0.7) * size.y
			var at := centre + Vector2(rng.randf_range(-0.2, 0.2) * size.x, -size.y * 0.1) + Vector2(cos(angle), sin(angle)) * speed * age + Vector2(0.0, 0.55 * size.y * age * age)
			var turn := rng.randf_range(-8.0, 8.0) * age + rng.randf() * TAU
			var half := Vector2(cos(turn), sin(turn)) * size.y * rng.randf_range(0.012, 0.028)
			var fade := clampf((RIBBON_LIFE - age) / 0.2, 0.0, 1.0)
			draw_line(at - half, at + half, Color(colors[index % colors.size()], fade), maxf(size.y * 0.004, 2.0), true)
