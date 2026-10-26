extends Node
## The simulation shell: one node, three roles (docs/core-shell.md).
##   authority  rigless: no couriers' rigs, no camera, no visuals. Accepts owner poses, derives the painting from the two anchors,
##              runs breaks, kill / goal zones, the round clock and the hazard clock.
##   replica    an online client: the owner steps its own courier (network/owner_courier.gd), the other one is drawn from relayed poses,
##              the painting is derived locally and corrected from the snapshot.
##   local      everything on one machine: one or two human couriers, split screen.
## `play_mode` (the round's plan): "carry", two couriers carry the painting; "balloon", 3 to 10 keep a balloon in the air
## (game/team_play.gd, which also runs players touching players in every mode).
const DevEnv := preload("res://dev_env.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Motion = preload("res://courier/courier_motion.gd")
const Anchor = preload("res://courier/courier_anchor.gd")
const Painting = preload("res://game/painting.gd")
const Shards = preload("res://game/painting_shards.gd")
const LevelWorld = preload("res://levels/level_world.gd")
const LoadSlicer = preload("res://game/load_slicer.gd")
const GameInput = preload("res://game/game_input.gd")
const OwnerPoseWire = preload("res://network/owner_pose_wire.gd")
const CourseSection = preload("res://course_section.gd")
const WalkInLobby = preload("res://network/walk_in_lobby.gd")
const LobbySpace = preload("res://lobby_space.gd")
const TeamPlay = preload("res://game/team_play.gd")
const BalloonSim = preload("res://balloon/balloon_sim.gd")
const Modes = preload("res://modes/modes.gd")
const VisualTrack = preload("res://game/visual_track.gd")

signal load_progress(fraction: float, label: String)

const BLOCKER_LAYER := 1024 ## the painting's blocker: only the courier capsules that simulate collide with it
const ANCHOR_OFFSET := Anchor.ANCHOR_OFFSET
const BREAK_CARD_AT := 1.5 ## seconds after a break until the retry card shows
const RESPAWN_AT := 6.5 ## seconds after a break until everybody respawns at the level start
const POSE_STEP_LIMIT := 12.0 ## metres: the largest jump between two accepted owner poses
const POSE_ANCHOR_LIMIT := 1.0 ## metres: how far an owner's anchor may be from its position + offset
const POSE_HEIGHT_LIMIT := 1000.0
const SNAP_ERROR := 1.5 ## metres: a replica painting further from the snapshot than this snaps to it
const CAMERA_FOCUS := Vector3(0.0, 1.0, 0.0) ## above the courier's feet
const FRAME_TEAM := 10.0 ## m: in a balloon round the view pulls back to frame the teammates this close to the own courier
const TURN_SPEED := 2.6 ## rad/s: turning with keys (two players on one keyboard: Q/E and U/O)
const CARRY_LOOK := 0.5 ## rad: a carrier's first view turns this far from the course towards its partner (the glass in sight)
const LOBBY_CENTER := WalkInLobby.SPAWN_CENTER
const LOAD_LEVELS_TO := 0.8

var network_role := "local"
var carrier_count := 2
var local_players := 2 ## local role: humans on this machine. 2 = a view each (or one shared view on one keyboard); 1 = one player, one full view (client/solo_entry.gd)
var load_yield := false ## replica client: give a frame back between build steps so the loading screen keeps animating
var load_background := false ## replica client: the build runs behind the main menu (slices follow the frame time)
var load_slicer
var world: Node3D
var level_world
var painting
var shards
var audio
var camera: Camera3D
var local_views
var touch
var local_presentation
var actors: Array = [] ## CharacterBody3D per slot (authority: shapeless carriers of the last accepted pose)
var rigs: Array = [] ## CourierRig per slot, null on the authority
var motions: Array = [] ## CourierMotion per slot, null on the authority
var anchors: Array = [] ## CourierAnchor per slot, authority only
var owner_courier: RefCounted ## replica: the owner's own courier (set by the client)
var round_mode := "lobby" ## lobby | level
var play_mode := CourseSection.CARRY ## carry | balloon, from the plan of the round
var spectate_slot := -1 ## the show: an eliminated local player's camera follows this slot (-1 = its own courier); set by modes/show/view.gd
var view_override: Variant = null ## the show's podium: a Transform3D the camera takes instead of following anyone (null = none); set by modes/show/view.gd
var hold_start := false ## a tile stage round's card: this player's courier stays on its start tile until GO: no steering, no jump, no dash (the camera still turns); set by modes/show/view.gd, the authority enforces it too (rules.gd, hold_courier)
var hold_yaw: Variant = null ## the show's podium: a float (radians, 0 faces -Z) holds this player's courier still on its spot facing that way: no steering, no dash, no grab (a jump in place stays); null = free; set by modes/show/view.gd
var pigeon_focus: Variant = null ## GHOST PIGEON (modes/show/pigeon/): while the local player is a pigeon, the world point of its bird (Vector3); the camera follows it, the height keys steer it and the courier takes no input; null = not a pigeon; set by the show's pigeon view each frame
var owner_command := {} ## replica: the owner's command of the last physics tick (collect_owner_input: move = the world direction, height = GHOST PIGEON's climb): the pigeon view predicts the own bird from it
var rig_scales := {} ## the show's podium (the victory flow): slot -> Vector3, a winner's squash and stretch about its feet; applied after each rig update
var rig_places := {} ## the show's podium: slot -> {at: Vector3, yaw: float}, where a winner's character is DRAWN (on its pedestal from the first frame on every client, whatever the actor's pose says: a replica's actor still sits on the course until the new epoch's poses arrive)
var item_mods := {} ## the show's items (modes/show/items/): slot -> {freeze, invert, speed, jump, air_jumps, dash} on that courier, set by the show's view each frame from the replicated effects (CourierMotion.mods; `invert` flips the steering here)
var item_power := {} ## slot -> the shove multiplier of that player (BOOST; players/player_contact.gd power)
var tandem := {} ## the TANDEM (modes/show/tandem/): slot -> {with, move (the partner's world steering), at (the partner's feet), speed, power} for every fused courier, set by tandem_view.gd each frame from the replicated pairs
var rig_hold := {} ## the TANDEM: slot -> world point where that fused character reaches to hold its partner's hand (the arms reach it, `carrying` pose)
var rig_spin := {} ## the TANDEM's exit: slot -> radians added to that rig's turn (they spin apart)
const TANDEM_TIE := 1.5 ## m: a fused pair drifting further than this is pulled together
const TANDEM_PULL := 0.8 ## the pull's share of full steering at twice TANDEM_TIE
var rule_mods := {} ## the manager's rules (modes/show/manager/): slot -> the same kind of mods as item_mods plus {no_jump, no_dash, gravity, ice}, set by the show's view; slot_mods() merges both
var rule_scales := {} ## slot -> Vector3: a rule's giant or tiny character, the rig is drawn that much bigger or smaller about its feet (it multiplies rig_scales)
var number_keys := false ## the manager's prompt is open for this player (modes/show/manager/manager_view.gd): the number keys 1-3 go to the authority as test_seq, as in the item lab
var rig_lag := {} ## slot -> seconds: that rig is drawn only every that many seconds (the GLITCH's lag: the character updates in jerks), set by the show's view
var item_slot := {"kind": -1, "roll": 0.0} ## the local player's item for the touch ITEM button (modes/show/items_ui/items_view.gd sets it): the item's catalog index, -1 none, and the seconds its roll still spins
var grab_taps := 0 ## GRAB presses of the local player so far (this machine's own count: the show's call window shakes its Decline button on each tap, modes/show/items_ui/call_view.gd)
var _rig_lag_clock := {}

var team ## TeamPlay: the balloon and players touching players
var slot_active: Array = [true, true]
var course_plan: Dictionary = CourseSection.default_plan()
var playing := false
var won := false
var reset_count := 0
var frame := 0
var elapsed_seconds := 0.0
var breaks := 0
var breaks_by_slot: Array = [0, 0]
var failure_kind := ""
var death_ui_visible := false
var break_elapsed := -1.0
var break_event := 0
var death_events := 0
var holding_states := [false, false]
var selected := 0 ## the local seat of this client (replica) / the seat whose view is the main one (local)

var _network_ready := false
var _load_t0 := 0
var started_moving := false
var _spawn_yaws: Array = [0.0, 0.0]
var _network_inputs: Array = [{}, {}]
var _owner_pending := {}
var _owner_accepted := {}
var _holds := {} ## authority: slot -> {at, radius, rise}: the show's podium and a stage round's card (mode_host.hold): an owner pose further than radius from `at` on x/z, or more than rise from its height, is dropped
var _strays := {} ## authority: slot -> owner poses dropped by a hold since take_strays
var _owner_sequences := [0, 0]
var _baseline_epoch := -1
var _replica_received := false
var _remote_state := {}
var _applied_tick := -1
var _last_break_event := 0
var _viewed := -2
var _stage_air_follow := false ## ... and it follows a throw's rise and fall in the air (FollowCamera `stage_air_follow`): a race level, not a tile round
var _stage_view := false ## the stage view is on (FollowCamera.set_stage_view): a tile stage round
var _lobby_shown: Variant = null ## the yard's last switch (null = never switched)

# local input and cameras
var local_input_enabled := true
var local_input := GameInput.new()
var local_split_screen := true
var local_camera_yaws := [0.0, 0.0]
var local_camera_pitches := [0.0, 0.0]
var camera_input_enabled := true
var yaw := 0.0
var pitch := 0.0
var follow ## FollowCamera of the main view
var _visual := VisualTrack.new() ## where each courier is drawn between two physics ticks (visual_position)
var split_follow: Array = []
var _local_commands := [{}, {}]
var _local_jumps := [0, 0]
var _local_dashes := [0, 0]
var _local_presses := [{"item": 0, "grab": 0, "test": 0}, {"item": 0, "grab": 0, "test": 0}] ## local: ITEM and GRAB presses so far per slot (press_count)
var _local_prime := true
var _local_roll := [0.0, 0.0]
var _local_height := [0.0, 0.0]
var _owner_jumps := 0
var _camera_seat := -1
var last_face := {} ## the last turn of a camera to the course forward on a respawn: {slot, yaw, at} (tools/modes/show_check.gd reads it)
var camera_settings := {}
## The mode's view (modes.json `camera`): "third" plays over the shoulder (FollowCamera.set_shoulder_view) with the own body in view and no first-person arms;
## every other mode plays in first person. Third person behind and above (the carry rounds) is a dev switch (--third-person, FRIENDS_CAMERA=third) or a
## setting a menu may flip with set_first_person().
var shoulder_view := Modes.camera() == "third"
var first_person := not (shoulder_view or DevEnv.has_arg("--third-person") or DevEnv.read("FRIENDS_CAMERA") == "third")
## The mode lets the couriers dash (modes.json `dash`): Shift, pad B or the right bumper, the phone's DASH button.
var dash_enabled := Modes.dash()
var dash_flop := Modes.dash_flop() ## the dash costs a belly flop and a wall stun (modes.json `dash_flop`, off in the show: only the cooldown)
var dash_meter: CanvasLayer ## client: the dash's cooldown (game/dash_meter.gd), only where dash_enabled
var dash_trail: Node3D ## client: the dash's puffs (game/dash_trail.gd), only where dash_enabled

func _ready() -> void:
	call_deferred("_boot")

func is_network_ready() -> bool:
	return _network_ready

# ------------------------------------------------------------------ boot

func _load_mark(label: String, fraction: float) -> void:
	print("GW_LOAD role=", network_role, " t_ms=", Time.get_ticks_msec() - _load_t0, " frac=", snappedf(fraction, 0.001), " ", label)
	load_progress.emit(fraction, label)
	if load_slicer != null: await load_slicer.next()

func _slice_progress(part: float, label: String) -> void:
	load_progress.emit(lerpf(0.05, LOAD_LEVELS_TO, part), label)

func _boot() -> void:
	if network_role != "authority":
		_configure_window()
	_load_t0 = Time.get_ticks_msec()
	if load_yield:
		load_slicer = LoadSlicer.new(get_tree(), _slice_progress)
		load_slicer.background = load_background
	slot_active.resize(carrier_count)
	slot_active.fill(true)
	_network_inputs.resize(carrier_count)
	breaks_by_slot.resize(carrier_count)
	breaks_by_slot.fill(0)
	_spawn_yaws.resize(carrier_count)
	_spawn_yaws.fill(0.0)
	_owner_sequences = []
	_owner_sequences.resize(carrier_count)
	_owner_sequences.fill(0)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	await _load_mark("boot start", 0.0)
	level_world = LevelWorld.new()
	level_world.name = "Levels"
	world.add_child(level_world)
	await level_world.build("authority" if network_role == "authority" else "client", load_slicer)
	await _load_mark("levels", LOAD_LEVELS_TO - 0.02)
	LobbySpace.ensure(world, network_role)
	await _load_mark("lobby yard", LOAD_LEVELS_TO)
	_build_couriers()
	team = TeamPlay.new(self)
	await _load_mark("couriers", 0.86)
	_build_painting()
	await _load_mark("painting", 0.92)
	if network_role != "authority": _build_presentation()
	await _load_mark("camera, audio", 0.96)
	_sync_level_view()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reset()
	if load_slicer != null: load_slicer.release() # hazards start moving now that the level is drawn
	if network_role == "local" and local_presentation == null: playing = false
	if network_role == "replica": _make_replica()
	_network_ready = true
	await _load_mark("ready", 1.0)
	if camera != null: _update_camera(1.0)
	print("GW_READY role=", network_role, " levels=", level_world.level_count())

func _configure_window() -> void:
	var root_window := get_tree().root
	root_window.title = TeamCast.team_name()
	root_window.content_scale_size = Vector2i(1280, 720)
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# Expand: a 20:9 phone fills the screen instead of showing 16:9 with black bars.
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func _build_couriers() -> void:
	for slot in carrier_count:
		var body: CharacterBody3D
		if network_role == "authority":
			body = CharacterBody3D.new() # carries the last accepted owner pose, no shape, no collision
			body.name = "Courier%d" % (slot + 1)
			body.collision_layer = 0
			body.collision_mask = 0
			var anchor := Anchor.new()
			anchor.setup(body)
			anchors.append(anchor)
			motions.append(null)
		else:
			body = Motion.make_body("Courier%d" % (slot + 1))
			var motion := Motion.new()
			motion.setup(body)
			motions.append(motion)
		world.add_child(body)
		actors.append(body)
		rigs.append(null)

func _make_replica() -> void:
	# Nobody collides until the owner's courier is configured; the other courier is only drawn.
	for body: CharacterBody3D in actors:
		body.collision_layer = 0
		body.collision_mask = 0
	for rig in rigs: rig.set_replica(true)

func _build_painting() -> void:
	painting = Painting.new()
	painting.name = "Painting"
	world.add_child(painting)
	painting.configure(network_role)
	shards = Shards.new()
	shards.name = "PaintingShards"
	world.add_child(shards)
	shards.configure(network_role != "authority", network_role != "replica")
	if network_role != "authority":
		painting.make_blocker()
		painting.set_blocker_enabled(false)
	if network_role == "local":
		for body: CharacterBody3D in actors: body.collision_mask = body.collision_mask | BLOCKER_LAYER

func _build_presentation() -> void:
	var rig_script: GDScript = load("res://character/character_rig.gd")
	if not rig_script.call("available"): rig_script = load("res://courier/courier_rig.gd") # no body model yet (art not in)
	var audio_script: GDScript = load("res://game/game_audio.gd")
	var follow_script: GDScript = load("res://game/follow_camera.gd")
	audio = audio_script.new()
	audio.name = "GameAudio"
	add_child(audio)
	for slot in carrier_count:
		var rig: Node3D = rig_script.new()
		rig.name = "CourierRig%d" % (slot + 1)
		world.add_child(rig)
		rig.setup(slot) # the seat's default look (an animal head per seat); online looks come from character/look_sync.gd
		rig.set("idle_emotes", true) # the cast's emote for the player after a while standing still (the courier rig has none)
		rigs[slot] = rig
	camera = Camera3D.new()
	follow = follow_script.new()
	follow.first_person = first_person
	follow.set_shoulder_view(shoulder_view)
	follow.configure(camera)
	camera.current = true
	world.add_child(camera)
	audio.configure(camera)
	for slot in carrier_count: audio.bind_courier(slot, rigs[slot], network_role == "local")
	if dash_enabled:
		dash_trail = load("res://game/dash_trail.gd").new()
		dash_trail.name = "DashTrail"
		world.add_child(dash_trail)
		dash_meter = load("res://game/dash_meter.gd").new()
		dash_meter.name = "DashMeter"
		add_child(dash_meter)
	if network_role == "local" and local_players == 1: follow.own_body(rigs[0], 0) # the one full view is the own view: hides its body, draws its arms
	if network_role == "local":
		local_views = load("res://game/split_views.gd").new()
		local_views.name = "SplitViews"
		add_child(local_views)
		local_views.configure(world)
		for slot in 2:
			var view_follow = follow_script.new()
			view_follow.first_person = first_person
			view_follow.set_shoulder_view(shoulder_view)
			view_follow.configure(local_views.cameras[slot])
			view_follow.own_body(rigs[slot], slot)
			split_follow.append(view_follow)
		_build_local_ui()
	audio.install_music(get_tree())
	team.build_look(world)
	_build_touch()
	for index in 2:
		local_camera_yaws[index] = 0.0
		local_camera_pitches[index] = follow.default_pitch()

func _build_local_ui() -> void:
	# The authority excludes client presentation resources; never preload this.
	local_presentation = load("res://client/local_presentation.gd").new()
	local_presentation.name = "LocalPresentation"
	add_child(local_presentation)
	local_presentation.configure(self)

func _build_touch() -> void:
	if touch != null or not ResourceLoader.exists("res://client/touch_controls.gd"): return
	touch = load("res://client/touch_controls.gd").new()
	touch.name = "TouchControls"
	add_child(touch)

# ------------------------------------------------------------------ phases

func lobby_spot(slot: int) -> Vector3:
	return WalkInLobby.spawn(slot, carrier_count)

func is_slot_active(slot: int) -> bool:
	return slot >= 0 and slot < slot_active.size() and bool(slot_active[slot])

## Where `slot` stands among the slots that are in the round (the start ring has one place per active slot), -1 for a slot that is out of it.
func start_rank(slot: int) -> int:
	if not is_slot_active(slot): return -1
	var rank := 0
	for other in slot:
		if is_slot_active(other): rank += 1
	return rank

## The courier whose position decides this courier's pull and facing (itself in the lobby and in balloon rounds: no pull).
func partner_actor(slot: int) -> CharacterBody3D:
	if round_mode == "lobby" or play_mode != CourseSection.CARRY or slot > 1: return actors[slot]
	return actors[1 - slot]

func active_count() -> int:
	return slot_active.count(true)

## The level being played (0-based), -1 in the lobby.
func current_level() -> int:
	return _level()

## Authority: the last input of a slot (the balloon round reads its press counters).
func player_input(slot: int) -> Dictionary:
	return _network_inputs[slot] if slot >= 0 and slot < _network_inputs.size() and _network_inputs[slot] is Dictionary else {}

## A minigame's action button for a slot (modes/mode_host.gd action): either lift key (Z / X, the pad's lift buttons) held.
## The owner's input on the authority, the local devices in the local game; outside a carry the lift does nothing else.
func mode_action(slot: int) -> bool:
	if network_role == "local":
		return slot >= 0 and slot < _local_commands.size() and _local_commands[slot] is Dictionary and bool(_local_commands[slot].get("action", false))
	return absf(float(player_input(slot).get("height", 0.0))) > 0.5

## Presses of the ITEM or GRAB button of `slot` so far ("item" | "grab"; the owner's counters on the authority, the local devices in the local game): the show's items act on the change.
func press_count(slot: int, key: String) -> int:
	if network_role == "local":
		return int((_local_presses[slot] as Dictionary).get(key, 0)) if slot >= 0 and slot < _local_presses.size() else 0
	return int(player_input(slot).get(key + "_seq", 0))

## GHOST PIGEON (modes/mode_host.gd pigeon_input): how the slot's player steers its bird: the world direction of the stick (the owner's camera's way) and the climb, JUMP held up and DASH held down.
func pigeon_input(slot: int) -> Dictionary:
	if network_role == "local":
		if slot < 0 or slot >= _local_commands.size() or not _local_commands[slot] is Dictionary: return {}
		var command: Dictionary = _local_commands[slot]
		var raw: Vector2 = command.get("move", Vector2.ZERO)
		return {"move": GameInput.world_move(raw, float(local_camera_yaws[slot]) if _split_views() else yaw), "climb": float(command.get("climb", 0.0))}
	var input := player_input(slot)
	var wire: Variant = input.get("move", [0.0, 0.0])
	var move := Vector2.ZERO
	if wire is Vector2: move = wire
	elif wire is Array and (wire as Array).size() == 2: move = Vector2(float(wire[0]), float(wire[1]))
	return {"move": move.limit_length(1.0), "climb": clampf(float(input.get("height", 0.0)), -1.0, 1.0)}

## The mods on a courier's motion: the show's items and the manager's rules together (flags either, `speed` and `gravity` multiply).
func slot_mods(slot: int) -> Dictionary:
	var items: Dictionary = item_mods.get(slot, {})
	var rules: Dictionary = rule_mods.get(slot, {})
	if rules.is_empty(): return items
	var merged := items.duplicate()
	for key: String in rules:
		match key:
			"speed", "gravity", "jump", "dash": merged[key] = float(merged.get(key, 1.0)) * float(rules[key])
			_: merged[key] = bool(merged.get(key, false)) or bool(rules[key])
	return merged

## The courier's steering after the show's items (an inverted one walks the other way) and the TANDEM (modes/show/tandem/): a fused courier steers by the average of its own input and its
## partner's (`tandem[slot].move`, the partner's world move as the authority last heard it), with a pull towards the partner when the two drift more than TANDEM_TIE apart.
func item_move(slot: int, move: Vector2) -> Vector2:
	var mods: Dictionary = slot_mods(slot)
	var own: Vector2 = -move if bool(mods.get("invert", false)) else move
	var fused: Variant = tandem.get(slot)
	if not fused is Dictionary: return own
	var steer: Vector2 = (own + (fused.move as Vector2)) * 0.5
	var gap := Vector2((fused.at as Vector3).x - actors[slot].global_position.x, (fused.at as Vector3).z - actors[slot].global_position.z)
	if gap.length() > TANDEM_TIE: steer += gap.normalized() * clampf((gap.length() - TANDEM_TIE) / TANDEM_TIE, 0.0, 1.0) * TANDEM_PULL
	return steer.limit_length(1.0)

## The motion mods of a courier: the items' (`item_mods`) with the tandem's walking speed on top.
func courier_mods(slot: int) -> Dictionary:
	var mods: Dictionary = slot_mods(slot)
	var fused: Variant = tandem.get(slot)
	if not fused is Dictionary: return mods
	var merged := mods.duplicate()
	merged["speed"] = float(mods.get("speed", 1.0)) * float(fused.speed)
	return merged

## The shove multiplier of every player: the items' (`item_power`) and a tandem's (the pair flings whoever it runs into, like a BOOST).
func shove_power() -> Dictionary:
	if tandem.is_empty(): return item_power
	var merged := item_power.duplicate()
	for slot: int in tandem: merged[slot] = maxf(float(merged.get(slot, 1.0)), float((tandem[slot] as Dictionary).power))
	return merged

## slot -> the slot it holds hands with (players/player_contact.gd: two fused partners never shove each other).
func tandem_partners() -> Dictionary:
	var result := {}
	for slot: int in tandem: result[slot] = int((tandem[slot] as Dictionary).with)
	return result

## Authority: `slot`'s owner is thrown by `impulse` (m/s; the exit of a tandem): the cumulative kick every owner applies (game/team_play.gd); the local game launches its own courier.
func fling_courier(slot: int, impulse: Vector3) -> void:
	if slot < 0 or slot >= carrier_count: return
	if network_role == "authority": team.kicks[slot] += impulse
	elif network_role == "local" and motions[slot] != null: motions[slot].launch(impulse, false, false)

## The world-space steering the player of `slot` is giving now (x, z; the authority: what its owner sent, the local game: the devices through the camera's yaw).
func intent(slot: int) -> Vector2:
	if network_role == "local":
		if slot < 0 or slot >= _local_commands.size() or not _local_commands[slot] is Dictionary: return Vector2.ZERO
		return GameInput.world_move(_local_commands[slot].get("move", Vector2.ZERO), local_camera_yaws[slot] if _split_views() else yaw)
	var raw: Variant = player_input(slot).get("move", [0.0, 0.0])
	return Vector2(float(raw[0]), float(raw[1])).limit_length(1.0) if raw is Array and raw.size() == 2 else Vector2.ZERO

func is_peer_hidden(slot: int) -> bool:
	return bool(_hidden_peers.get(slot, false))

func floor_at(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 8.0, 1 | 16)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.position as Vector3) + Vector3.UP * 0.02 if not hit.is_empty() else at

func _level() -> int:
	return int(course_plan.get("level", -1)) if round_mode != "lobby" else -1

## Authority / local: the plan of the next round (the level it plays, carry or balloon).
func set_course_plan(plan: Dictionary) -> void:
	course_plan = plan.duplicate()
	play_mode = str(plan.get("play_mode", CourseSection.CARRY))
	_sync_level_view()

## The level world shows and simulates only the level being played; the lobby yard has its own switch.
func _sync_level_view() -> void:
	if level_world == null: return
	var level := _level()
	if level != _viewed:
		_viewed = level
		level_world.set_active_level(level)
		if shards != null: shards.reset()
	if _lobby_shown != (round_mode == "lobby"):
		_lobby_shown = round_mode == "lobby"
		LobbySpace.sync(world, network_role, _lobby_shown)

## Authority / local: put the world into a phase and start a new epoch. `active` holds a bool per slot.
## "lobby": active slots walk free in the yard, no painting. "level": the two couriers carry one painting through the level of `course_plan`.
func configure_phase(mode: String, active: Array, keep_clock := false) -> void:
	round_mode = mode
	_camera_seat = -1
	for slot in carrier_count: slot_active[slot] = slot < active.size() and bool(active[slot])
	if mode != "lobby":
		elapsed_seconds = 0.0
		started_moving = false
		breaks = 0
		for slot in carrier_count: breaks_by_slot[slot] = 0
	team.checkpoint = -1
	_sync_level_view()
	var clock_before: float = level_world.clock if keep_clock and level_world != null else 0.0
	_reset()
	if keep_clock and level_world != null: level_world.set_clock(clock_before) # the show's podium: a new epoch on the level as it stands
	playing = true
	print("GW_PHASE mode=", mode, " play=", play_mode, " active=", slot_active.count(true), " epoch=", reset_count, " level=", _level())

## Authority, lobby only: a player joined or left; no new epoch, the slot just starts or stops being simulated.
func set_slot_active(slot: int, active: bool) -> void:
	if slot < 0 or slot >= carrier_count or round_mode != "lobby": return
	slot_active[slot] = active
	if not active:
		clear_authority_owner_pose(slot)
		actors[slot].position = floor_at(lobby_spot(slot))
		actors[slot].velocity = Vector3.ZERO

## Authority, balloon round: a player left; the others play on without that courier.
func drop_slot(slot: int) -> void:
	if slot < 0 or slot >= carrier_count: return
	slot_active[slot] = false
	clear_authority_owner_pose(slot)
	team.contact.release(slot)

func restart_delivery() -> void:
	if network_role == "replica": return
	_reset()
	playing = true

## Where the couriers stand after a reset: {pos: [Vector3 per slot], yaw: [float per slot], spot: the team's spot}.
## A level: carry on the two start points; balloon on a ring around the start pad or the last checkpoint the balloon passed.
func _spawn_points() -> Dictionary:
	var level := _level()
	var points := []
	var yaws := []
	if round_mode == "lobby" or level < 0 or level_world == null:
		for slot in carrier_count:
			var spot := lobby_spot(slot)
			points.append(floor_at(spot))
			var toward := LOBBY_CENTER - spot
			yaws.append(atan2(-toward.x, -toward.z))
		return {"pos": points, "yaw": yaws, "spot": LOBBY_CENTER}
	var ring := maxi(active_count(), 2) if play_mode in [CourseSection.BALLOON, CourseSection.SHOW] else 2
	var start: Dictionary = level_world.team_start(level, ring, team.checkpoint if play_mode == CourseSection.BALLOON else -1)
	for slot in carrier_count:
		var place := start_rank(slot)
		points.append((start.pos[place] if place >= 0 and place < start.pos.size() else start.spot) + Vector3.UP * 0.05)
		yaws.append(float(start.yaw))
	return {"pos": points, "yaw": yaws, "spot": start.spot}

## A new epoch: everybody back at the start, painting whole, hazards at clock zero. Authority and local only.
func _reset() -> void:
	_owner_pending.clear()
	_owner_accepted.clear()
	_holds.clear()
	_strays.clear()
	_owner_sequences.fill(0)
	for slot in carrier_count: _network_inputs[slot] = {"move": [0.0, 0.0], "jump": false}
	reset_count += 1
	won = false
	failure_kind = ""
	death_ui_visible = false
	break_elapsed = -1.0
	holding_states = []
	for slot in carrier_count: holding_states.append(_carrying() and is_slot_active(slot))
	var spawn := _spawn_points()
	for slot in carrier_count:
		var at: Vector3 = spawn.pos[slot]
		_spawn_yaws[slot] = float(spawn.yaw[slot])
		if play_mode == CourseSection.SHOW and round_mode != "lobby" and not is_slot_active(slot): continue # the show's eliminated stay where they are
		_place_courier(slot, at, float(spawn.yaw[slot]))
	_reset_painting()
	team.reset(spawn.spot)
	if round_mode != "lobby" and level_world != null: level_world.set_clock(0.0)
	_local_jumps = [0, 0]
	_local_dashes = [0, 0]
	print("GW_RESET epoch=", reset_count, " a=", actors[0].position, " b=", actors[1].position)

## A carry round: the painting is in play.
func _carrying() -> bool:
	return round_mode != "lobby" and play_mode == CourseSection.CARRY

func _place_courier(slot: int, at: Vector3, facing: float) -> void:
	var body: CharacterBody3D = actors[slot]
	if motions[slot] != null: motions[slot].reset(body, at, facing)
	else:
		body.position = at
		body.rotation = Vector3(0.0, facing, 0.0)
		body.velocity = Vector3.ZERO
	if network_role == "authority": anchors[slot].clear()
	if rigs[slot] != null:
		rigs[slot].global_position = at
		_visual.snap(slot, body.global_position)
		rigs[slot].snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": facing, "carrying": false, "paused": false})
	_remote_state.erase(slot)

func _reset_painting() -> void:
	painting.reset(_anchor_of(0), _anchor_of(1))
	var on := _carrying()
	painting.set_intact_visible(on)
	if network_role != "authority": painting.set_blocker_enabled(on)

## The point slot's painting end hangs from: authority = the last accepted owner anchor, elsewhere the courier's position + offset.
func _anchor_of(slot: int) -> Vector3:
	if network_role == "authority": return anchors[slot].anchor()
	return actors[slot].global_position + ANCHOR_OFFSET

# ------------------------------------------------------------------ tick: authority and local

func _physics_process(delta: float) -> void:
	if not _network_ready: return
	_sync_courier_bodies()
	if network_role == "replica": _tick_replica(delta)
	else: _tick_simulation(delta)
	_sample_visuals()

## The couriers' positions after this tick: what the rigs and the follow camera draw between two ticks (game/visual_track.gd). Nothing is drawn on the authority.
func _sample_visuals() -> void:
	if network_role == "authority": return
	for slot in actors.size(): _visual.sample(slot, actors[slot].global_position)

## Where the courier in `slot` is DRAWN this frame: between its last two ticks, never the raw physics position (that one steps at the tick rate, the screen does not). The rig and every
## follow camera use it; the simulation keeps reading `actors[slot]`.
func visual_position(slot: int) -> Vector3:
	return _visual.at(slot, actors[slot].global_position)

## True while a tile stage round is played (the level's `stage` section, docs/level-format.md "Stage rounds"): its camera, movement feel and the couriers
## stopping each other (courier_motion.gd MASK_STAGE) apply to these rounds and to no other.
func stage_round() -> bool:
	var level := _level()
	return level >= 0 and not CourseSection.level_stage(level).is_empty()

## The tops (world heights) of the tile floors of the stage round played, top floor first; empty outside one. The simulated couriers' motion collides with the floors under its feet only
## (courier_motion.gd set_floors: one-way floors).
func stage_floors() -> PackedFloat32Array:
	var level := _level()
	return level_world.tile_floors(level) if level >= 0 and level_world != null else PackedFloat32Array()

## Stage rounds: the couriers are solid for each other. The simulated courier's own mask is switched by its motion (courier_motion.gd); here the bodies it
## runs into get a layer: on a replica the other couriers are drawn from relayed poses and have none otherwise, a held courier (it rides over its holder's head)
## is never solid. Outside stage rounds nothing is solid but the owner's own courier.
func _sync_courier_bodies() -> void:
	if network_role == "authority": return
	var seat: int = owner_courier.seat if owner_courier != null and owner_courier.configured else -1
	var stage := stage_round()
	for slot in carrier_count:
		if network_role == "replica" and slot == seat: continue # the owner's courier: set by its client (network/owner_courier.gd)
		var solid: bool = stage and is_slot_active(slot) and not is_peer_hidden(slot) and int(team.held_by(slot)) < 0
		var layer: int = Motion.LAYER_COURIER if solid or (network_role == "local" and not stage) else 0
		if actors[slot].collision_layer != layer: actors[slot].collision_layer = layer

func _tick_simulation(delta: float) -> void:
	if playing: _update_break_flow(delta)
	if round_mode != "lobby" and playing and started_moving and not won: elapsed_seconds += delta
	if not playing:
		_place_rigs()
		return
	frame += 1
	if round_mode != "lobby": level_world.advance(delta)
	if network_role == "authority":
		for slot in carrier_count:
			if is_slot_active(slot): _tick_authority_courier(slot)
		team.step_contact(delta)
	else:
		team.step_contact(delta)
		for slot in carrier_count:
			if is_slot_active(slot) and team.held_by(slot) < 0: _step_local_courier(slot, delta)
		for slot in carrier_count: # held couriers last, above where their holders are now
			if is_slot_active(slot) and team.place_held(slot) and slot < _local_jumps.size():
				_local_jumps[slot] = 0
				_local_dashes[slot] = 0
	_place_rigs()
	if round_mode == "lobby": return
	if play_mode == CourseSection.BALLOON: team.tick_balloon(delta)
	elif play_mode == CourseSection.SHOW: return # the show's rules (modes/show/rules.gd) read the positions: nothing of the painting or the balloon
	else: _tick_round(delta)

func _tick_authority_courier(slot: int) -> void:
	var command: Dictionary = _network_inputs[slot]
	var move: Variant = command.get("move", Vector2.ZERO)
	if move is Array and move.size() == 2: move = Vector2(float(move[0]), float(move[1]))
	if move is Vector2 and move.is_finite() and move.length_squared() > 0.0 and round_mode != "lobby": started_moving = true
	_apply_authority_pose(slot)

func _step_local_courier(slot: int, delta: float) -> void:
	var move := Vector2.ZERO
	var jump := false
	var dash := false
	var held_still := hold_yaw is float
	var frozen := hold_start
	if local_input_enabled:
		var raw: Vector2 = _local_commands[slot].get("move", Vector2.ZERO)
		var control_yaw: float = local_camera_yaws[slot] if _split_views() else yaw
		move = item_move(slot, GameInput.world_move(raw, control_yaw)) if not (held_still or frozen) else Vector2.ZERO
		if int(_local_jumps[slot]) > 0:
			_local_jumps[slot] = int(_local_jumps[slot]) - 1
			jump = not frozen
		if int(_local_dashes[slot]) > 0:
			_local_dashes[slot] = int(_local_dashes[slot]) - 1
			dash = not (held_still or frozen)
	else:
		_local_jumps[slot] = 0
		_local_dashes[slot] = 0
	if held_still: _hold_facing(slot)
	if move.length_squared() > 0.0 and round_mode != "lobby": started_moving = true
	var touch: Dictionary = team.result(slot)
	team.push(slot, touch)
	_apply_level_effects(slot)
	move = team.steer(slot, touch, move)
	var partner := partner_actor(slot)
	var events: Dictionary = motions[slot].step(actors[slot], {"move": move, "jump": jump, "dash": dash, "toward": partner.global_position, "partner_velocity": partner.velocity, "holding": bool(holding_states[slot]) and round_mode != "lobby"}, delta)
	if bool(events.get("dashed", false)): _dash_started(slot)
	_flop_heard(slot, events)
	if local_input_enabled and not held_still: _face_view(slot, local_camera_yaws[slot] if _split_views() else yaw)

## Launch pads, bumpers, hazard bonks and ice reach a simulated courier through the level world (levels/level_world.gd apply_effects).
func _apply_level_effects(slot: int) -> void:
	var level := _level()
	var motion = motions[slot]
	motion.set_mods(courier_mods(slot))
	motion.set_stage(stage_round()) # the stage feel and the couriers solid for each other: tile stage rounds only
	motion.set_floors(stage_floors())
	motion.set_dash_flop(dash_flop)
	if level < 0 or level_world == null:
		motion.set_surface({})
		return
	var effects: Dictionary = level_world.apply_effects(level, slot, actors[slot], motion)
	if effects.is_empty() or audio == null: return
	if str(effects.kind) == "bonk": audio.play_event("slap", effects.at)
	elif str(effects.kind) == "cushion": audio.play_event("bump", effects.at, 1.25) # an edge cushion (levels/edge_bumpers.gd) pops the courier off with a rubbery bump
	else: audio.play_push()

func _place_rigs() -> void:
	for slot in carrier_count:
		if rigs[slot] != null and not rig_lag.has(slot): rigs[slot].global_position = actors[slot].global_position # a lagging rig is placed by _update_rigs, once per period

## Round rules, once per tick: roll and height from the inputs, the painting, kill and goal zones.
func _tick_round(delta: float) -> void:
	_apply_painting_inputs(delta)
	if not painting.broken:
		painting.anchor_a = _anchor_of(0)
		painting.anchor_b = _anchor_of(1)
		painting.step(delta)
	if painting.broken and break_elapsed < 0.0: _begin_break("break", painting.hit_name)
	if painting.broken or won: return
	var level := _level()
	for slot in carrier_count:
		if not is_slot_active(slot): continue
		var zone: String = level_world.zone_at(level, actors[slot].global_position)
		var scorch: String = level_world.scorch_at(level, actors[slot].global_position)
		if scorch != "": # a laser or fire jet on a carrier: the painting breaks, like a fall
			team.note_scorch(slot, scorch)
			painting.break_with(scorch, 0.0)
			_begin_break("death", scorch, slot)
			return
		if zone == "kill":
			painting.break_with("kill", 0.0)
			_begin_break("death", "kill", slot)
			return
		if zone == "goal":
			won = true
			playing = false
			print("GW_GOAL level=", level, " seconds=", snappedf(elapsed_seconds, 0.01), " breaks=", breaks)
			return

func _apply_painting_inputs(delta: float) -> void:
	match network_role:
		"authority":
			for command: Dictionary in _network_inputs:
				painting.roll_input(float(command.get("roll", 0.0)), delta)
				painting.height_input(float(command.get("height", 0.0)), delta)
		"local":
			if local_input_enabled:
				for slot in 2:
					painting.roll_input(float(_local_roll[slot]), delta)
					painting.height_input(float(_local_height[slot]), delta)

func _begin_break(kind: String, cause: String, culprit := -1) -> void:
	breaks += 1
	break_event += 1
	break_elapsed = 0.0
	failure_kind = kind
	death_ui_visible = kind == "death"
	if kind == "death": death_events += 1
	if culprit < 0: culprit = 0 if actors[0].velocity.length() >= actors[1].velocity.length() else 1 # the faster courier
	breaks_by_slot[culprit] = int(breaks_by_slot[culprit]) + 1
	holding_states.fill(false)
	painting.set_intact_visible(false)
	if network_role != "authority": painting.set_blocker_enabled(false)
	shards.burst(painting.global_transform, reset_count * 1000 + break_event)
	if audio != null:
		audio.play_break(painting.global_position)
		if kind == "death": audio.play_death()
	print("GW_BROKEN kind=", kind, " cause=", cause, " frame=", frame, " breaks=", breaks)

func _update_break_flow(delta: float) -> void:
	if break_elapsed < 0.0 or network_role == "replica": return
	break_elapsed += delta
	if break_elapsed >= BREAK_CARD_AT and not death_ui_visible: death_ui_visible = true
	if break_elapsed >= (BalloonSim.RESPAWN_SECONDS if failure_kind == "pop" else RESPAWN_AT):
		_reset()
		playing = true

## Balloon round (game/team_play.gd): the balloon popped. The POP! card at once; the team restarts after BalloonSim.RESPAWN_SECONDS.
func begin_pop() -> void:
	breaks += 1
	break_event += 1
	break_elapsed = 0.0
	failure_kind = "pop"
	death_ui_visible = true
	if audio != null: audio.play_death()
	print("GW_POP frame=", frame, " pops=", breaks, " checkpoint=", team.checkpoint, " at=", team.balloon.position)

## Balloon round: the balloon entered the goal volume.
func balloon_goal() -> void:
	if won: return
	won = true
	playing = false
	print("GW_GOAL level=", _level(), " seconds=", snappedf(elapsed_seconds, 0.01), " pops=", breaks)

## A courier respawns alone (balloon round, it fell out). Authority: its next accepted pose must come from there; local: moved now.
func respawn_courier(slot: int, at: Vector3, facing: float) -> void:
	if network_role == "authority":
		_owner_pending.erase(slot)
		_owner_accepted.erase(slot)
		actors[slot].position = at
		actors[slot].velocity = Vector3.ZERO
	elif motions[slot] != null:
		motions[slot].reset(actors[slot], at, facing)
		face_camera(slot, facing)

## A courier put back on the course (a checkpoint or the start, on any client that has a view of it): the camera turns at once to the way it
## faces (the course forward there), so nobody is left looking at a wall or back down the course.
func face_camera(slot: int, facing: float) -> void:
	if slot < 0 or slot >= actors.size() or network_role == "authority" or view_override is Transform3D: return
	last_face = {"slot": slot, "yaw": facing, "at": actors[slot].global_position}
	if _split_views() and slot < split_follow.size():
		local_camera_yaws[slot] = wrapf(facing, -PI, PI)
		split_follow[slot].reset_lag()
	elif slot == selected:
		yaw = wrapf(facing, -PI, PI)
		follow.reset_lag()

## Authority, the show's podium and a stage round's card: poses of `slot` more than `radius` m from `at` on x/z, or more than `rise` m over or under its height, are dropped (counted in
## take_strays) until release_holds, so a client that does not hold still cannot leave its spot (the podium allows a jump in place: no `rise`); the rules put it back with send_to.
func hold_courier(slot: int, at: Vector3, radius: float, rise := INF) -> void:
	if network_role == "replica" or slot < 0 or slot >= carrier_count: return
	_holds[slot] = {"at": at, "radius": radius, "rise": rise}
	_strays[slot] = 0

func release_holds() -> void:
	_holds.clear()
	_strays.clear()

## The owner poses of `slot` a hold dropped since this was last asked.
func take_strays(slot: int) -> int:
	var dropped := int(_strays.get(slot, 0))
	_strays[slot] = 0
	return dropped

# ------------------------------------------------------------------ authority: owner poses

## Trusted transport must bind the current seat/session/entity before calling this.
## Validation here is structural, epoch, sequence and position sanity, never network permission.
func queue_authority_owner_pose(slot: int, pose: Dictionary) -> bool:
	if network_role != "authority" or slot < 0 or slot >= carrier_count: return false
	if not OwnerPoseWire.valid(pose) or int(pose.reset_epoch) != reset_count: return false
	if int(pose.seq) <= int(_owner_sequences[slot]): return false
	var position: Vector3 = (pose.transform as Transform3D).origin
	if absf(position.y) > POSE_HEIGHT_LIMIT or absf(position.x) > POSE_HEIGHT_LIMIT * 10.0 or absf(position.z) > POSE_HEIGHT_LIMIT * 10.0: return false
	if (pose.anchor as Vector3).distance_to(position + ANCHOR_OFFSET) > POSE_ANCHOR_LIMIT: return false
	var before: Dictionary = _owner_accepted.get(slot, {})
	var reference: Vector3 = (before.transform as Transform3D).origin if not before.is_empty() else (actors[slot] as Node3D).position
	if position.distance_to(reference) > POSE_STEP_LIMIT: return false
	_owner_sequences[slot] = int(pose.seq)
	_owner_pending[slot] = pose.duplicate(true)
	return true

func freeze_authority_owner_pose(slot: int) -> void:
	if network_role != "authority" or slot < 0 or slot >= carrier_count: return
	_owner_pending.erase(slot)
	if slot < actors.size(): actors[slot].velocity = Vector3.ZERO
	var pose: Dictionary = _owner_accepted.get(slot, {})
	if not pose.is_empty():
		# A transport pause does not erase the last admitted pose or lower the sequence high-water mark.
		pose.velocity = Vector3.ZERO
		pose.acceleration = Vector3.ZERO
		_owner_accepted[slot] = pose

func clear_authority_owner_pose(slot: int) -> void:
	if network_role != "authority" or slot < 0 or slot >= carrier_count: return
	_owner_pending.erase(slot)
	_owner_accepted.erase(slot)
	_owner_sequences[slot] = 0
	actors[slot].velocity = Vector3.ZERO
	anchors[slot].clear()

func _apply_authority_pose(slot: int) -> bool:
	var pose: Dictionary = _owner_pending.get(slot, {})
	if pose.is_empty(): return false # keep the last accepted pose, no gravity step
	_owner_pending.erase(slot)
	if int(pose.reset_epoch) != reset_count: return false
	var pinned: Dictionary = _holds.get(slot, {})
	if not pinned.is_empty():
		var origin: Vector3 = (pose.transform as Transform3D).origin
		var held_at: Vector3 = pinned.at
		if Vector2(origin.x - held_at.x, origin.z - held_at.z).length() > float(pinned.radius) or absf(origin.y - held_at.y) > float(pinned.rise):
			_strays[slot] = int(_strays.get(slot, 0)) + 1
			return false
	actors[slot].transform = pose.transform
	actors[slot].velocity = pose.velocity
	anchors[slot].set_anchor(pose.anchor)
	_owner_accepted[slot] = pose
	return true

func set_player_input(slot: int, command: Dictionary) -> void:
	if slot < 0 or slot >= carrier_count: return
	_network_inputs[slot] = command.duplicate(true)

# ------------------------------------------------------------------ replica: owner and remote couriers

## Replica: the baseline of a new epoch (every active courier where the authority put it).
func seed_baseline(state: Dictionary) -> bool:
	if network_role != "replica": return false
	if not state.get("resets") is int or state.resets < 1: return false
	var epoch: int = state.resets
	if epoch < _baseline_epoch: return false
	if epoch == _baseline_epoch: return true
	var players: Variant = state.get("players")
	if not players is Array or players.size() != carrier_count: return false
	for player: Variant in players:
		if player is Dictionary and player.get("inactive", false): continue
		if not player is Dictionary or not player.get("movement") is Dictionary or not player.get("position") is Vector3: return false
		var facing: Variant = player.movement.get("yaw")
		if not (facing is float or facing is int) or not is_finite(float(facing)): return false
	for slot in carrier_count:
		var player: Dictionary = players[slot]
		if player.get("inactive", false): continue
		_place_courier(slot, player.position, float(player.movement.yaw))
	_baseline_epoch = epoch
	_reset_painting_from_actors()
	if state.get("hazard_t") != null and round_mode != "lobby": level_world.set_clock(float(state.hazard_t))
	_camera_seat = -1
	return true

func invalidate_baseline() -> void:
	_baseline_epoch = -1

func _reset_painting_from_actors() -> void:
	painting.reset(_anchor_of(0), _anchor_of(1))
	painting.set_intact_visible(_carrying() and not painting.broken)

## Replica: the smoothed pose of the other player's courier (already authenticated by the caller).
func apply_remote_pose(slot: int, pose: Dictionary) -> bool:
	if network_role != "replica" or slot < 0 or slot >= carrier_count: return false
	if not OwnerPoseWire.valid(pose) or int(pose.reset_epoch) != _baseline_epoch: return false
	if owner_courier != null and owner_courier.configured and owner_courier.seat == slot: return false
	actors[slot].transform = pose.transform
	actors[slot].velocity = pose.velocity
	_remote_state[slot] = {"grounded": pose.grounded, "yaw": pose.yaw, "acceleration": pose.acceleration, "flop": pose.flop}
	return true

## Replica: step the owner's courier (the client calls this once per physics tick, before the shell's own tick).
## Players touching players: held above its holder, the authority's kicks and respawns, its own shoves (game/team_play.gd).
func owner_step(command: Dictionary, enabled: bool, delta: float) -> bool:
	if owner_courier == null or not owner_courier.configured or not owner_courier.active or not is_slot_active(owner_courier.seat): return false # out of the round: the courier stays where it is
	var seat: int = owner_courier.seat
	team.owner_pending(seat)
	if team.place_held(seat): return true
	var touch: Dictionary = team.owner_contact(seat, delta)
	team.push(seat, touch)
	_apply_level_effects(seat)
	var move: Variant = command.get("move", Vector2.ZERO)
	if move is Vector2:
		command = command.duplicate()
		command.move = item_move(seat, team.steer(seat, touch, move))
	owner_courier.still = hold_yaw is float
	owner_courier.frozen = hold_start
	var stepped: bool = owner_courier.physics_step(command, enabled, delta)
	if owner_courier.still: _hold_facing(seat) # after the step: nothing the motion does (a face towards a partner, a dash) turns the courier away from the camera
	elif stepped: _face_view(seat, yaw)
	if stepped and bool(owner_courier.last_events.get("jumped", false)) and audio != null: audio.play_jump()
	if stepped and bool(owner_courier.last_events.get("dashed", false)): _dash_started(seat)
	if stepped: _flop_heard(seat, owner_courier.last_events)
	return stepped

## The podium hold (`hold_yaw`): the courier faces the camera whatever its player does with the mouse or the stick.
func _hold_facing(slot: int) -> void:
	if not hold_yaw is float or motions[slot] == null: return
	motions[slot].yaw = float(hold_yaw)
	actors[slot].rotation.y = float(hold_yaw)

## First person: a courier faces where its player looks (what it grabs and carries stays in view); a carrier faces the glass.
func _face_view(slot: int, view_yaw: float) -> void:
	var carrying: bool = slot < holding_states.size() and bool(holding_states[slot]) and round_mode != "lobby"
	if not first_person or motions[slot] == null or carrying: return
	motions[slot].yaw = view_yaw
	actors[slot].rotation.y = view_yaw

func _tick_replica(delta: float) -> void:
	if not _replica_received: return
	if playing and round_mode != "lobby" and not won: level_world.advance(delta)
	team.replica_tick(delta, owner_courier.seat if owner_courier != null and owner_courier.configured else -1)
	_place_rigs()
	if not _carrying() or painting.broken or _baseline_epoch < 0: return
	painting.anchor_a = _anchor_of(0)
	painting.anchor_b = _anchor_of(1)
	painting.step(delta)

# ------------------------------------------------------------------ rendering: rigs, camera

func _process(delta: float) -> void:
	if not _network_ready or network_role == "authority": return
	if network_role == "local" and local_input_active(): _sample_local_inputs(delta)
	_touch_frame(delta)
	_update_camera(delta)
	_update_rigs(delta)
	team.draw(delta)

func _motion_state(slot: int) -> Dictionary:
	var body: CharacterBody3D = actors[slot]
	var motion = motions[slot]
	var simulated: bool = network_role == "local" or (owner_courier != null and owner_courier.configured and owner_courier.seat == slot)
	var state := {"velocity": body.velocity, "carrying": bool(holding_states[slot]) and round_mode != "lobby" and not painting.broken, "paused": not playing and round_mode != "lobby"}
	if simulated:
		state.grounded = motion.grounded
		state.yaw = motion.yaw
		state.acceleration = motion.acceleration
		state.floor_normal = motion.floor_normal
		state.flop = motion.flop_left
	else:
		var remote: Dictionary = _remote_state.get(slot, {})
		state.grounded = bool(remote.get("grounded", true))
		state.yaw = float(remote.get("yaw", body.rotation.y))
		state.acceleration = remote.get("acceleration", Vector3.ZERO)
		state.flop = float(int(remote.get("flop", 0))) * 0.01 # the pose's 1/100 s
	state.look_at = partner_actor(slot).global_position
	return state

## The way the courier in `slot` faces, as simulated or last heard (radians, 0 faces -Z).
func courier_yaw(slot: int) -> float:
	return float(_motion_state(slot).yaw)

func _update_rigs(delta: float) -> void:
	for slot in carrier_count:
		var rig: Node3D = rigs[slot]
		if rig == null: continue
		rig.visible = is_slot_active(slot) and (network_role != "replica" or _replica_received) and not _hidden_peers.get(slot, false)
		var scaled: Variant = rig_scales.get(slot)
		var rule_scaled: Variant = rule_scales.get(slot)
		if rule_scaled is Vector3: scaled = (scaled as Vector3) * (rule_scaled as Vector3) if scaled is Vector3 else rule_scaled
		if not rig.visible: continue
		var state := _motion_state(slot)
		if not rig_lag.has(slot): rig.global_position = visual_position(slot) # drawn between the last two ticks (a lagging rig is placed below, once per period)
		var placed: Variant = rig_places.get(slot)
		if placed is Dictionary:
			rig.global_position = (placed as Dictionary).at
			state.yaw = float((placed as Dictionary).yaw)
		var grips := []
		if state.carrying and round_mode != "lobby": grips = painting.grip_points(slot)
		var holding_hands: Variant = rig_hold.get(slot)
		if holding_hands is Vector3: # the TANDEM: one hand reaches the partner's, the other hangs loose at its side (the carry pose with two grips)
			var towards: bool = rig.to_local(holding_hands as Vector3).x > 0.0
			var loose: Vector3 = rig.to_global(Vector3(-0.42 if towards else 0.42, 0.8, -0.15))
			grips = [loose, holding_hands] if towards else [holding_hands, loose]
			state.carrying = true
		if rig_lag.has(slot): # the GLITCH: this rig shows the courier as it was up to a period ago, and jumps to where it is now once per period
			var held_for := float(_rig_lag_clock.get(slot, 1.0e9)) + delta
			if held_for < float(rig_lag[slot]):
				_rig_lag_clock[slot] = held_for
				continue
			_rig_lag_clock[slot] = 0.0
			delta = held_for
			rig.global_position = actors[slot].global_position
		else: _rig_lag_clock.erase(slot)
		rig.update(delta, state, grips)
		if scaled is Vector3: rig.global_basis = rig.global_basis.orthonormalized() * Basis.from_scale(scaled) # the rig turns itself every update; the scale goes on after (a winner dropping in)
		if rig_spin.has(slot): rig.global_basis = Basis(Vector3.UP, float(rig_spin[slot])) * rig.global_basis # the TANDEM's exit: they spin apart
	if dash_meter != null: dash_meter.update(delta, local_dash_cooldown(), Motion.DASH_COOLDOWN)
	if dash_trail != null:
		for slot in carrier_count:
			if rigs[slot] != null: dash_trail.follow(slot, rigs[slot].visible, visual_position(slot), actors[slot].velocity)

## Seconds of dash cooldown left on the courier this machine plays (a replica: the owner's, a local game: the first player's), -1 when there is nothing to show
## (no dash in this round, a stage round, the podium hold, no round running).
func local_dash_cooldown() -> float:
	if not dash_enabled or stage_round() or hold_yaw is float or not playing or round_mode == "lobby": return -1.0
	if network_role == "replica": return float(owner_courier.motion.dash_cooldown) if owner_courier != null and owner_courier.configured and owner_courier.active else -1.0
	return float(motions[0].dash_cooldown) if not motions.is_empty() and motions[0] != null else -1.0

## A dash began (the owner's own step: courier_motion.gd `dashed`): its whoosh. The puffs follow from the speeds (dash_trail.gd).
func _dash_started(slot: int) -> void:
	if audio != null: audio.play_event("swing", actors[slot].global_position, 1.4, 4.0)

## The dive ended on the floor (`flopped`: the belly slap) or ran into a wall (`wall_stun`: the bonk): the owner's own step, a sound each.
func _flop_heard(slot: int, events: Dictionary) -> void:
	if audio == null: return
	if bool(events.get("flopped", false)): audio.play_event("slap", actors[slot].global_position, 1.0, 2.0)
	if bool(events.get("wall_stun", false)): audio.play_event("bump", actors[slot].global_position, 1.0, 3.0)

var _hidden_peers := {} ## slot -> true while that seat's client is still loading (the client sets it)

func set_peer_hidden(slot: int, hidden: bool) -> void:
	_hidden_peers[slot] = hidden

## Hat and shirt colour of the courier in `slot` (palette index = the player's seat).
func set_slot_tint(slot: int, palette_index: int) -> void:
	if rigs[slot] != null: rigs[slot].set_slot_tint(palette_index)

func set_local_seat(slot: int) -> void:
	selected = clampi(slot, 0, maxi(carrier_count - 1, 0))
	if audio != null: audio.reset_baseline()
	if follow != null:
		follow.clear_bodies()
		follow.own_body(rigs[selected], selected)

## First person, carrying: the flat way from the partner back to this carrier (the eye goes behind the hands), ZERO otherwise.
func _carry_back(slot: int) -> Vector3:
	if not _carrying() or painting.broken or slot > 1 or slot >= holding_states.size() or not bool(holding_states[slot]): return Vector3.ZERO
	var back: Vector3 = (actors[slot].global_position - actors[1 - slot].global_position) * Vector3(1, 0, 1)
	return back if back.length() > 0.01 else Vector3.ZERO

func _spawn_camera_yaw(slot := -1) -> float:
	if round_mode == "lobby": return WalkInLobby.CAMERA_YAW
	var course := float(_spawn_yaws[0])
	if not first_person or slot < 0 or not _carrying() or slot > 1: return course
	# A carrier looks a little towards its partner: the glass in its hands and the way ahead both in view.
	var partner: Vector3 = actors[1 - slot].global_position - actors[slot].global_position
	var right := Vector3.RIGHT.rotated(Vector3.UP, course)
	return course + (-CARRY_LOOK if partner.dot(right) > 0.0 else CARRY_LOOK)

## First person or third for every view (a settings or dev switch).
func set_first_person(on: bool) -> void:
	first_person = on
	if follow != null: follow.set_first_person(on)
	for view in split_follow: view.set_first_person(on)
	_camera_seat = -1

# ------------------------------------------------------------------ camera

func set_camera_input_enabled(enabled: bool) -> void:
	camera_input_enabled = enabled
	if not enabled:
		if follow != null: follow.discard_look()
		for view in split_follow: view.discard_look()
		if DisplayServer.get_name() != "headless": Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func apply_camera_settings(values: Dictionary) -> void:
	camera_settings = values.duplicate()
	if follow != null: follow.apply_settings(values)
	for view in split_follow: view.apply_settings(values)

func local_input_active() -> bool:
	return network_role == "local" and local_presentation != null

func _touch_active() -> bool:
	return touch != null and touch.is_active()

const VIEW_ARM_BITS := 3 << 20 ## character_rig.gd FP_VIEW_FIRST_BIT, both seats: the own view arms' render layers
var _spectated := -1 ## the slot the spectator camera follows (reset_lag on a change)
var _pigeon_cam := false ## GHOST PIGEON: the camera is following the bird (the view starts from a clean lag when it begins)
var _arms_taken := 0 ## the view-arm bits taken off the camera while it watches somebody else (the show's podium and spectating)

## The own first-person arms are drawn by the own camera only; a camera that watches somebody else (the show) must not draw them.
func _view_arms(shown: bool) -> void:
	if camera == null: return
	if shown:
		camera.cull_mask |= _arms_taken
		_arms_taken = 0
	elif _arms_taken == 0:
		_arms_taken = camera.cull_mask & VIEW_ARM_BITS
		camera.cull_mask &= ~VIEW_ARM_BITS

func _update_camera(delta: float) -> void:
	_place_camera(delta)
	_ghost_tiles(delta)

## The step tiles' floors over the camera are not drawn (levels/step_tiles.gd ghost_floors): the shoulder view stands under the next floor and its slabs would
## fill the top of the picture. Judged from the courier the view follows (the leader while spectating): its own floor and the ones below always stay. A fixed
## shot (the podium) and first person draw every floor. The stage view looks down from above the next floor as often as from under it, and an overhead slab would
## hide the courier it follows: there every floor over the viewed courier is left out (the camera height counts as -INF).
func _ghost_tiles(delta: float) -> void:
	var level := _level()
	if level_world == null or camera == null or level < 0: return
	var viewed := _spectated if _spectated >= 0 else selected
	var flying: bool = pigeon_focus is Vector3 and not first_person and not view_override is Transform3D # GHOST PIGEON: the view follows the bird
	var fixed: bool = first_person or view_override is Transform3D or (not flying and (viewed < 0 or viewed >= actors.size()))
	var camera_y := INF if fixed else (-INF if _stage_view else camera.global_position.y)
	var feet_y: float = (pigeon_focus as Vector3).y if flying else (0.0 if fixed else actors[viewed].position.y)
	level_world.ghost_tiles(level, camera_y, feet_y, delta)

## The stage view plays in the tile stage rounds (a level with a `stage` section) and in the levels that ask for it (`"camera": "stage"`: the long race courses), and in no other
## round; switched here when the round changes.
func _sync_stage_view() -> void:
	var level := _level()
	var stage := (stage_round() or (level >= 0 and CourseSection.level_camera(level) == "stage")) and not first_person and not pigeon_focus is Vector3 # a pigeon flies in the shoulder view
	var air_follow := stage and not stage_round() # the race levels follow a pad's throw in the air, the tile rounds freeze the picture there
	if stage == _stage_view and air_follow == _stage_air_follow: return
	_stage_view = stage
	_stage_air_follow = air_follow
	follow.set_stage_view(stage, air_follow)
	for view in split_follow: view.set_stage_view(stage, air_follow)
	_camera_seat = -1

## The stage view's options for `slot`: whether the courier stands on a floor and how much of the full run it is doing (the view tips down with it).
func _stage_options(slot: int) -> Dictionary:
	var velocity: Vector3 = _motion_state(slot).velocity
	return {"grounded": _grounded(slot), "run": Vector2(velocity.x, velocity.z).length() / float(Motion.STAGE_FEEL.walk)}

func _place_camera(delta: float) -> void:
	if camera == null: return
	_sync_stage_view()
	if view_override is Transform3D and camera.current: # the show's podium: a fixed shot for everybody
		_view_arms(false)
		camera.cull_mask |= follow.BODY_BITS # a first-person player's own body is drawn in the fixed shot (the winner stands on the podium)
		camera.global_transform = view_override
		return
	# Two players on one machine get a view each: always in first person, as chosen in third.
	var split_active := local_input_active() and _split_views() and playing and camera.current
	if local_views != null: local_views.set_active(split_active)
	if not camera.current:
		follow.discard_look()
		for view in split_follow: view.discard_look()
		return
	var active_input := camera_input_enabled and playing
	if DisplayServer.get_name() != "headless":
		var capture := active_input and DisplayServer.window_is_focused() and not _touch_active()
		var wanted := Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != wanted: Input.mouse_mode = wanted
	if split_active:
		local_views.sync_camera_properties(camera)
		if _camera_seat != selected: # a new round or phase: each view starts from its courier's start facing
			_camera_seat = selected
			for slot in 2:
				local_camera_yaws[slot] = _spawn_camera_yaw(slot)
				local_camera_pitches[slot] = split_follow[slot].default_pitch()
				split_follow[slot].reset_lag()
		for slot in 2:
			var view = split_follow[slot]
			if active_input:
				var angles: Vector2 = view.look(float(local_camera_yaws[slot]), float(local_camera_pitches[slot]))
				local_camera_yaws[slot] = angles.x
				local_camera_pitches[slot] = angles.y
			else: view.discard_look()
			if first_person: view.update_first_person(delta, visual_position(slot), float(local_camera_yaws[slot]), float(local_camera_pitches[slot]), _carry_back(slot))
			else: view.update(delta, visual_position(slot) + CAMERA_FOCUS, float(local_camera_yaws[slot]), float(local_camera_pitches[slot]), _view_targets(slot), _stage_options(slot))
		yaw = float(local_camera_yaws[0])
		pitch = float(local_camera_pitches[0])
		camera.global_transform = local_views.cameras[0].global_transform # the listener stays with the first view
		return
	if pigeon_focus is Vector3 and (not local_input_active() or local_players == 1):
		# GHOST PIGEON (modes/show/pigeon/): the player is a bird now: the shoulder view orbits it, the mouse and the stick look around, the move keys steer it.
		_view_arms(false)
		_camera_seat = -1
		_spectated = -1
		if not _pigeon_cam:
			_pigeon_cam = true
			follow.reset_lag()
			pitch = deg_to_rad(-18.0)
		if active_input:
			var angles: Vector2 = follow.look(yaw, pitch)
			yaw = angles.x
			pitch = angles.y
		else: follow.discard_look()
		follow.update(delta, (pigeon_focus as Vector3) + Vector3(0.0, 0.5, 0.0), yaw, pitch, null, {})
		return
	_pigeon_cam = false
	if spectate_slot >= 0 and spectate_slot < actors.size() and spectate_slot != selected and is_slot_active(spectate_slot) and not local_input_active():
		# The show: an eliminated player watches the leader from behind and above.
		_view_arms(false)
		_camera_seat = -1
		if _stage_view:
			# The stage view keeps the player's own orbit (the arena in view, never the pen) and only changes whom it follows.
			if _spectated < 0: follow.reset_lag()
			_spectated = spectate_slot
			if active_input:
				var angles: Vector2 = follow.look(yaw, pitch)
				yaw = angles.x
				pitch = angles.y
			else: follow.discard_look()
			follow.update(delta, visual_position(spectate_slot) + CAMERA_FOCUS, yaw, pitch, null, _stage_options(spectate_slot))
			return
		if _spectated != spectate_slot: # a new leader (or the first): the camera starts behind it instead of flying over from the pen
			_spectated = spectate_slot
			follow.reset_lag()
			yaw = courier_yaw(spectate_slot)
		yaw = lerp_angle(yaw, courier_yaw(spectate_slot), 1.0 - exp(-2.5 * delta))
		pitch = deg_to_rad(-30.0)
		follow.update(delta, visual_position(spectate_slot) + CAMERA_FOCUS, yaw, pitch, null, {})
		return
	_view_arms(true)
	_spectated = -1
	# A new round or a new seat initialises the view; a respawn inside a round turns it to the course forward (face_camera).
	if _camera_seat != selected:
		_camera_seat = selected
		yaw = _spawn_camera_yaw(selected if network_role == "replica" else -1)
		pitch = follow.default_pitch()
		follow.reset_lag()
	if active_input:
		var angles: Vector2 = follow.look(yaw, pitch)
		yaw = angles.x
		pitch = angles.y
	else: follow.discard_look()
	if first_person and (not local_input_active() or local_players == 1):
		follow.update_first_person(delta, visual_position(selected), yaw, pitch, _carry_back(selected))
		return
	# From behind and above: one shared view frames the pair (local play, a carry round: both carriers and the painting between
	# them); in a balloon round the own courier, the balloon and the teammates near it.
	var focus: Vector3 = visual_position(selected) + CAMERA_FOCUS
	var options := {}
	var own := selected
	if (local_input_active() and local_players > 1) or (_carrying() and is_slot_active(0) and is_slot_active(1)):
		focus = (visual_position(0) + visual_position(1)) * 0.5 + CAMERA_FOCUS
		options = {"frame": true}
		own = -1
	elif team.active():
		options = {"frame": true, "frame_points": _team_near(selected)}
	if _stage_view: options = _stage_options(selected)
	follow.update(delta, focus, yaw, pitch, _view_targets(own), options)

## True while `slot`'s courier stands on a floor (as simulated or last heard): the stage view follows floors, not jumps.
func _grounded(slot: int) -> bool:
	return bool(_motion_state(slot).grounded)

## Balloon round: the other couriers within FRAME_TEAM of `slot` (the view widens to show them).
func _team_near(slot: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for other in actors.size():
		if other != slot and is_slot_active(other) and actors[other].position.distance_to(actors[slot].position) <= FRAME_TEAM: points.append(visual_position(other) + Vector3.UP)
	return points

## World points the camera keeps visible: the other courier (both when the view is shared); the balloon in a balloon round; nobody in
## the lobby (up to ten players walk about there: one behind a crate must not pull the camera in).
func _view_targets(own_slot: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	if round_mode == "lobby": return points
	if team.active():
		points.append(team.focus_point())
		if network_role == "replica": return points # up to ten players: the balloon is what to watch
	for slot in actors.size():
		if slot != own_slot and is_slot_active(slot): points.append(visual_position(slot) + Vector3.UP)
	return points

func _input(event: InputEvent) -> void:
	if not _network_ready or network_role == "authority": return
	if network_role == "local":
		if local_input_active():
			local_input.push_event(event)
			if local_presentation.handle_gameplay_input(event): return
	else: local_input.push_event(event)
	if event is InputEventMouseMotion and camera_input_enabled and playing and camera != null and camera.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if local_input_active() and _split_views(): split_follow[0].queue_look(event.screen_relative)
		else: follow.queue_look(event.screen_relative)
	elif event is InputEventMouseButton and event.pressed and not local_input_active() and camera_input_enabled and playing and camera != null and camera.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and Input.is_key_pressed(KEY_CTRL): follow.zoom(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and Input.is_key_pressed(KEY_CTRL): follow.zoom(-1.0)

# ------------------------------------------------------------------ local input

func set_local_input_enabled(enabled: bool) -> void:
	local_input_enabled = enabled
	if not enabled:
		_local_commands = [{}, {}]
		_local_jumps = [0, 0]
		_local_dashes = [0, 0]
		_local_roll = [0.0, 0.0]
		_local_height = [0.0, 0.0]
	set_camera_input_enabled(enabled)

func configure_local_input_mode(mode: int) -> void:
	local_input.configure(mode)
	_local_prime = true
	_local_commands = [{}, {}]
	_local_jumps = [0, 0]
	_local_dashes = [0, 0]

## The next sampled frame only drains edges (closing a menu must not replay the keys that closed it).
func prime_local_input() -> void:
	_local_prime = true

## Two players on one machine get a view each: always in first person, as chosen (local_split_screen) in third.
func _split_views() -> bool:
	return local_players > 1 and (local_split_screen or first_person)

func configure_local_split_screen(enabled: bool) -> void:
	local_split_screen = enabled
	if not enabled:
		yaw = float(local_camera_yaws[0])
		pitch = float(local_camera_pitches[0])

func connected_pads() -> Array:
	return Array(Input.get_connected_joypads())

## Once per rendered frame: sample every device a seat uses and turn it into this frame's commands.
func _sample_local_inputs(delta: float) -> void:
	var sources: Array = local_input.seat_sources(connected_pads())
	var sampled := {}
	for devices: Array in sources:
		for device: int in devices:
			if not sampled.has(device): sampled[device] = local_input.sample(device, delta)
	if touch != null and touch.is_active() and sampled.has(GameInput.KEYBOARD): _merge_touch(sampled[GameInput.KEYBOARD])
	var prime := _local_prime # sampling while a menu is open drains the edges: closing it must not replay them
	_local_prime = false
	var restart := false
	var options := false
	for slot in local_players:
		var move := Vector2.ZERO
		var roll := 0.0
		var height := 0.0
		var climb := 0.0
		for device: int in sources[slot]:
			var action: Dictionary = sampled[device]
			if device >= 0 and bool(action.options) and not prime: options = true
			# Restart (R, pad Y) is a level run's retry: in the lobby pad Y is PLAY, and the show's rounds are never restarted by a key.
			if local_input_enabled and not won and not prime and round_mode != "lobby" and play_mode != CourseSection.SHOW: restart = restart or bool(action.restart)
			if not local_input_enabled or not playing or won or prime: continue
			var contribution: Vector2 = action.move
			if absf(contribution.x) >= absf(move.x): move.x = contribution.x
			if absf(contribution.y) >= absf(move.y): move.y = contribution.y
			_local_jumps[slot] = mini(int(_local_jumps[slot]) + int(action.jumps), 8)
			if dash_enabled: _local_dashes[slot] = mini(int(_local_dashes[slot]) + int(action.dashes), 2)
			var split: Array = team.split_grabs(slot, int(action.get("grabs", 0)) if not hold_yaw is float else 0) # a GRAB near the balloon slaps it; the show's podium holds everybody still
			team.note_presses(slot, int(action.jumps), split[0], split[1])
			(_local_presses[slot] as Dictionary).item = int(_local_presses[slot].item) + int(action.get("items", 0))
			(_local_presses[slot] as Dictionary).grab = int(_local_presses[slot].grab) + int(action.get("grabs", 0))
			if int(action.get("tests", 0)) > 0 and (bool(item_slot.get("lab", false)) or number_keys): _local_presses[slot].test = ((int(_local_presses[slot].test) >> 3) + 1) << 3 | int(action.tests) # the item lab and the manager's prompt: seq * 8 + the number pressed
			if slot == selected: grab_taps += int(action.get("grabs", 0))
			var look: Vector2 = GameInput.look_delta(action.look, camera_settings)
			look.x -= float(action.get("turn", 0.0)) * TURN_SPEED * delta # keys that turn (one keyboard: Q/E, U/O)
			if _split_views():
				local_camera_yaws[slot] = wrapf(float(local_camera_yaws[slot]) + look.x, -PI, PI)
				local_camera_pitches[slot] = follow.clamp_pitch(float(local_camera_pitches[slot]) + look.y)
			else:
				yaw = wrapf(yaw + look.x, -PI, PI)
				pitch = follow.clamp_pitch(pitch + look.y)
			roll += float(action.roll)
			height += float(action.height)
			climb += float(bool(action.get("jump_held", false))) - float(bool(action.get("dash_held", false))) # GHOST PIGEON: JUMP held climbs, DASH held dives
		_local_commands[slot] = {"move": move, "action": absf(height) > 0.5, "climb": clampf(climb, -1.0, 1.0)} # action: a minigame's button (the lift keys), mode_action
		_local_roll[slot] = clampf(roll, -1.0, 1.0) * (1.0 if slot == 0 else -1.0) if round_mode != "lobby" and holding_states[slot] and not painting.broken else 0.0
		_local_height[slot] = clampf(height, -1.0, 1.0) if round_mode != "lobby" and holding_states[slot] and not painting.broken else 0.0
	if options: local_presentation.toggle_options()
	if restart and local_input_enabled: restart_delivery()

func _merge_touch(action: Dictionary) -> void:
	if touch.stick != Vector2.ZERO: action.move = Vector2(touch.stick.x, -touch.stick.y)
	action.roll = float(touch.tilt_right) - float(touch.tilt_left)
	action.height = float(touch.lift_up) - float(touch.lift_down)

## Once per rendered frame: tell the overlay whether a round is being played, move the camera by the finger that looks around.
func _touch_frame(_delta: float) -> void:
	if touch == null: return
	touch.set_context(camera_input_enabled and playing and camera != null and camera.current and (network_role != "local" or local_input_enabled))
	touch.set_glass_controls(_carrying())
	touch.set_optional("map", false)
	var flying: bool = pigeon_focus is Vector3 # GHOST PIGEON: the buttons are the bird's (UP, DOWN, COO, DROP)
	touch.set_pigeon(flying)
	touch.set_optional("grab", team.grabs_allowed() or flying)
	touch.set_optional("dash", (dash_enabled and not stage_round()) or flying) # the stage rounds have no dash (courier_motion.gd STAGE_FEEL)
	touch.set_item(int(item_slot.kind) if playing else -1, playing and bool(item_slot.get("lab", false))) # the show's item slot (modes/show/items_ui/items_view.gd)
	touch.set_round_buttons(stage_round() and not flying) # a stage round: the stick and one dark round button, no hint text
	if not touch.is_active(): return
	var look: Vector2 = touch.take_look() * touch.look_sensitivity
	if look != Vector2.ZERO:
		(split_follow[0] if local_input_active() and _split_views() else follow).queue_touch_look(look)

## Replica: the owner's command for this physics tick (keyboard, any pad and touch). `jumps` = press edges since the last call.
func collect_owner_input() -> Dictionary:
	var sampled := {}
	var devices := [GameInput.KEYBOARD]
	var pads := connected_pads()
	if not pads.is_empty(): devices.append(int(pads[0]))
	var move := Vector2.ZERO
	var roll := 0.0
	var height := 0.0
	var climb := 0.0
	var jumps := 0
	var grabs := 0
	var dashes := 0
	var items := 0
	var tests := 0
	var look := Vector2.ZERO
	for device: int in devices:
		var action: Dictionary = local_input.sample(device, 1.0 / 60.0)
		if device == GameInput.KEYBOARD and touch != null and touch.is_active(): _merge_touch(action)
		if absf(action.move.x) >= absf(move.x): move.x = action.move.x
		if absf(action.move.y) >= absf(move.y): move.y = action.move.y
		roll += float(action.roll)
		height += float(action.height)
		climb += float(bool(action.get("jump_held", false))) - float(bool(action.get("dash_held", false))) # GHOST PIGEON: JUMP held climbs, DASH held dives
		jumps += int(action.jumps)
		grabs += int(action.get("grabs", 0))
		grab_taps += int(action.get("grabs", 0)) if spectate_slot < 0 else 0
		dashes += int(action.get("dashes", 0))
		items += int(action.get("items", 0))
		if int(action.get("tests", 0)) > 0: tests = int(action.tests)
		look += action.look
		sampled[device] = action
	if spectate_slot >= 0: # out of the round and watching the others: the courier takes no input
		move = Vector2.ZERO
		jumps = 0
		grabs = 0
		dashes = 0
		items = 0
		tests = 0
	if look != Vector2.ZERO and camera_input_enabled and playing:
		var delta_angles := GameInput.look_delta(look, camera_settings)
		yaw = wrapf(yaw + delta_angles.x, -PI, PI)
		pitch = follow.clamp_pitch(pitch + delta_angles.y)
	var direction := GameInput.world_move(move, yaw)
	var split: Array = team.split_grabs(selected, grabs) if _network_ready else [grabs, 0] # a GRAB near the balloon slaps it
	var command := {"move": direction, "jumps": jumps, "grabs": split[0], "slaps": split[1], "dashes": dashes if dash_enabled else 0, "height": clampf(climb if pigeon_focus is Vector3 else height, -1.0, 1.0), "roll": clampf(roll, -1.0, 1.0) * (1.0 if selected % 2 == 0 else -1.0), "items": items, "tests": tests if bool(item_slot.get("lab", false)) or number_keys else 0, "restart": false}
	command["facing"] = atan2(-direction.x, -direction.y) if direction.length_squared() > 0.0 else (motion_yaw(selected) if _network_ready else yaw)
	owner_command = command
	return command

func motion_yaw(slot: int) -> float:
	return float(motions[slot].yaw) if motions[slot] != null else 0.0

# ------------------------------------------------------------------ snapshot

## Authority: the shared state of this tick (the match controller adds its own fields).
func capture_network_state(with_baseline := true) -> Dictionary:
	if not _network_ready: return {}
	var players := []
	for slot in carrier_count:
		if not is_slot_active(slot):
			players.append({"inactive": true})
			continue
		var accepted: Dictionary = _owner_accepted.get(slot, {})
		var entry := {"position": actors[slot].position, "acceleration": accepted.get("acceleration", Vector3.ZERO), "holding": bool(holding_states[slot])}
		if with_baseline: entry.yaw = float(accepted.get("yaw", _spawn_yaws[slot]))
		players.append(entry)
	var state := {"tick": frame, "players": players, "painting": painting.global_transform, "roll": painting.roll, "height": painting.height, "level": int(course_plan.get("level", -1)),
		"playing": playing, "broken": painting.broken, "hit": painting.hit_name, "won": won, "resets": reset_count, "failure_kind": failure_kind, "death_ui_visible": death_ui_visible,
		"break_elapsed": break_elapsed, "break_event": break_event, "elapsed_seconds": elapsed_seconds, "breaks": breaks, "audio_events": {"death": death_events},
		"hazard_t": level_world.clock if round_mode != "lobby" else 0.0, "round_mode": round_mode, "course": str(course_plan.get("course", CourseSection.ADVENTURE)), "fragments": shards.capture_state()}
	team.capture(state)
	return state

## The shape the HUD reads, for the local role (the same keys a snapshot has).
func hud_state() -> Dictionary:
	return {"elapsed_seconds": elapsed_seconds, "death_ui_visible": death_ui_visible, "won": won, "playing": playing, "broken": painting.broken, "roll": painting.roll, "height": painting.height,
		"breaks": breaks, "resets": reset_count, "failure_kind": failure_kind, "play_mode": play_mode if round_mode != "lobby" else CourseSection.CARRY}

## Replica: follow the authority's snapshot (called every rendered frame with the newest one).
func apply_network_state(state: Dictionary, delta: float) -> void:
	if not _network_ready or network_role != "replica" or state.is_empty(): return
	_apply_round_mode(state)
	var fresh_epoch := int(state.get("resets", reset_count)) != reset_count
	var weight := 1.0 if not _replica_received or fresh_epoch else 1.0 - exp(-18.0 * maxf(delta, 0.0))
	_replica_received = true
	var new_tick := int(state.get("tick", -1)) != _applied_tick or fresh_epoch
	_applied_tick = int(state.get("tick", _applied_tick))
	playing = bool(state.get("playing", false))
	won = bool(state.get("won", false))
	failure_kind = str(state.get("failure_kind", ""))
	death_ui_visible = bool(state.get("death_ui_visible", false))
	break_elapsed = float(state.get("break_elapsed", -1.0))
	break_event = int(state.get("break_event", break_event))
	holding_states = (state.get("holding", [false, false]) as Array).duplicate()
	frame = int(state.get("tick", frame))
	elapsed_seconds = float(state.get("elapsed_seconds", 0.0))
	breaks = int(state.get("breaks", 0))
	reset_count = int(state.get("resets", reset_count))
	var broken := bool(state.get("broken", false))
	painting.broken = broken
	painting.hit_name = str(state.get("hit", ""))
	painting.set_intact_visible(not broken and _carrying())
	painting.set_blocker_enabled(not broken and _carrying())
	painting.roll = lerpf(painting.roll, float(state.get("roll", 0.0)), weight)
	painting.height = lerpf(painting.height, float(state.get("height", 0.0)), weight)
	_correct_painting(state, weight)
	if broken and break_event > _last_break_event:
		if audio != null: audio.play_break(painting.global_position, break_elapsed)
	_last_break_event = break_event
	shards.apply_state(state.get("fragments", []), weight)
	team.apply(state, new_tick)
	if new_tick:
		if round_mode != "lobby" and state.get("hazard_t") != null: level_world.correct_clock(float(state.hazard_t))
		if audio != null:
			var events: Dictionary = state.get("audio_events", {})
			audio.observe({"death": int(events.get("death", 0)), "push": 0, "bounce": 0, "easter": 0}, reset_count)

## The replica derives the painting from its own two couriers; the snapshot only corrects it.
func _correct_painting(state: Dictionary, weight: float) -> void:
	var transform: Variant = state.get("painting")
	if not transform is Transform3D: return
	var derived: bool = _baseline_epoch >= 0 and _carrying() and not painting.broken
	if derived:
		if (painting.global_transform.origin - (transform as Transform3D).origin).length() > SNAP_ERROR: painting.global_transform = transform
	else: painting.global_transform = painting.global_transform.interpolate_with(transform, weight)

## Replica: follow the authority's round mode, level and slot activity.
func _apply_round_mode(state: Dictionary) -> void:
	var mode := str(state.get("round_mode", "level"))
	var course_id := str(state.get("course", course_plan.get("course", "")))
	var level_index := int(state.get("level", course_plan.get("level", -1)))
	var played := str(state.get("play_mode", play_mode))
	if mode != round_mode:
		round_mode = mode
		_camera_seat = -1
		print("GW_REPLICA_ROUND_MODE ", mode)
	if played != play_mode:
		play_mode = played
		print("GW_REPLICA_PLAY_MODE ", played)
	if (course_id != str(course_plan.get("course", "")) or level_index != int(course_plan.get("level", -1)) or played != str(course_plan.get("play_mode", ""))) and CourseSection.valid(course_id):
		course_plan = CourseSection.plan(course_id, level_index, played)
	var players: Variant = state.get("players", [])
	if players is Array:
		for slot in mini(players.size(), carrier_count):
			slot_active[slot] = not (players[slot] is Dictionary and players[slot].get("inactive", false))
	_sync_level_view()
