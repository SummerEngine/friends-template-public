extends SceneTree
## Frames of the podium room and the victory sequence (style/podium_room.gd, modes/show/shared/victory_flow.gd) with the real characters (character_rig.gd, the project's own demo/cast). Offscreen binary only, never windowed,
## one render at a time machine-wide (the render lock), about 30 s per run:
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 240 lockf -k $HOME/.local/state/friends-slots/render.lock <Summer offscreen> --summer-offscreen --audio-driver Dummy --fixed-fps 60 \
##     --resolution 1280x720 --path demo -s "$PWD/tools/modes/podium_frames.gd" -- --shots=<dir> [--prefix=x_] [--only=empty,three,strip] [--fps=5] [--players=3] [--stale]
## empty: the room without anybody (wide and close); three: the three winners on the pedestals (wide and close, a crown on 1st); strip: the whole sequence as numbered frames `strip_NNN_<phase>_<t>.png`
## (the VICTORY banner over the final's summit, the cut into the room, the three shots, the landings, the celebration, the push in). Prints PODIUM_FRAMES lines.
const LevelWorld := preload("res://levels/level_world.gd")
const CharRig := preload("res://character/character_rig.gd")
const PodiumRoom := preload("res://style/podium_room.gd")
const VictoryFlow := preload("res://modes/show/shared/victory_flow.gd")
const ShowCrown := preload("res://style/show_crown.gd")
const ShowView := preload("res://modes/show/view.gd")
const TeamCast := preload("res://style/team_cast.gd")

## What the flow asks of the shell and of the view, as the game has it (game/game_run.gd, modes/show/view.gd).
class Shell extends Node3D:
	var camera: Camera3D
	var world: Node3D
	var view_override: Variant = null
	var audio: Variant = null
	var rig_scales := {}
	var rig_places := {}

class ViewStub extends Node3D:
	var rigs: Array = []
	var hide_name_tags := false

	func rig(slot: int) -> Node3D:
		return rigs[slot] if slot >= 0 and slot < rigs.size() else null

	func cast_player(slot: int) -> Dictionary:
		return TeamCast.player(slot)

var shots := ""
var prefix := ""
var only: PackedStringArray = []
var fps := 5
var players := 3
var times: Array[float] = [] ## --times=0.2,0.9,...: the strip shows exactly these seconds of the podium (no banner part)
var stale := false ## a replica: the actors still stand on the course (far from the room) when the podium starts: only the flow's rig places bring the characters in
var holder: Node3D
var world: Node3D
var shell: Shell
var view: ViewStub
var camera: Camera3D
var flow: CanvasLayer
var crown: Node3D
var done := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shots="): shots = argument.trim_prefix("--shots=")
		if argument.begins_with("--prefix="): prefix = argument.trim_prefix("--prefix=")
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=").split(",")
		if argument.begins_with("--fps="): fps = maxi(int(argument.trim_prefix("--fps=")), 1)
		if argument == "--stale": stale = true
		if argument.begins_with("--times="):
			for part in argument.trim_prefix("--times=").split(","): times.append(float(part))
		if argument.begins_with("--players="): players = clampi(int(argument.trim_prefix("--players=")), 0, 3)
	create_timer(220.0).timeout.connect(func() -> void:
		print("PODIUM_FRAMES FAIL timed out")
		quit(1))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func save(label: String) -> void:
	await frames(2)
	RenderingServer.force_draw(false)
	var file := "%s/%s%s.png" % [shots, prefix, label]
	print("PODIUM_FRAMES shot ", file.get_file(), " ", root.get_texture().get_image().save_png(file) == OK)
	done += 1

func wanted(name: String) -> bool:
	return only.is_empty() or name in only

func run() -> void:
	if shots == "":
		print("PODIUM_FRAMES needs --shots=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	holder = Node3D.new()
	root.add_child(holder)
	world = LevelWorld.new()
	holder.add_child(world)
	await world.build("local")
	world.set_active_level(15)
	world.set_clock(3.0)
	shell = Shell.new()
	shell.name = "Shell"
	shell.world = holder
	holder.add_child(shell)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 4000.0 # as the game camera (Camera3D default); the candy world reaches 2600 m (the cloud wall)
	holder.add_child(camera)
	camera.current = true
	shell.camera = camera
	view = ViewStub.new()
	holder.add_child(view)
	flow = VictoryFlow.new()
	view.add_child(flow)
	flow.setup(shell, view)
	for rank in players:
		var rig: Node3D = CharRig.new()
		holder.add_child(rig)
		rig.setup(rank, {})
		view.rigs.append(rig)
	if wanted("empty"): await empty_shots()
	if wanted("three"): await three_shots()
	if wanted("crown"): await crown_shots()
	if wanted("strip"): await strip_shots()
	print("PODIUM_FRAMES ok=", done > 0)
	holder.queue_free()
	await process_frame
	quit(0 if done > 0 else 1)

## A podium-phase state at `t` s.
func podium_state(t: float, count: int) -> Dictionary:
	var spots: Array = []
	for spot: Vector3 in PodiumRoom.spots(): spots.append([spot.x, spot.y, spot.z])
	var top: Array = []
	for rank in count: top.append(rank)
	return {"phase": "podium", "t": t, "podium": spots, "top": top, "crown": 0 if count > 0 else -1}

func place_rigs(count: int) -> void:
	var spots := PodiumRoom.spots()
	for rank in view.rigs.size():
		var rig: Node3D = view.rigs[rank]
		rig.visible = rank < count
		rig.global_position = Vector3(40.0, 0.0, 0.0) if stale else spots[rank]
		rig.rotation.y = PI
	for rank in mini(count, view.rigs.size()):
		var rig: Node3D = view.rigs[rank]
		rig.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": PI, "carrying": false})

func step_rigs(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 0.04)
		for slot in view.rigs.size(): # as game/game_run.gd `_update_rigs` does it
			var rig: Node3D = view.rigs[slot]
			var motion := {"velocity": Vector3.ZERO, "grounded": true, "yaw": PI, "carrying": false}
			rig.visible = slot < players
			if not rig.visible: continue
			var placed: Variant = shell.rig_places.get(slot)
			if placed is Dictionary:
				rig.global_position = (placed as Dictionary).at
				motion.yaw = float((placed as Dictionary).yaw)
			rig.update(dt, motion)
			var scaled: Variant = shell.rig_scales.get(slot)
			if scaled is Vector3: rig.global_basis = rig.global_basis.orthonormalized() * Basis.from_scale(scaled)
		left -= dt

## The winner's crown as modes/show/view.gd wears it: a child of the head anchor, `age` s after it was set on.
func crown_on(rank: int, age: float) -> void:
	var anchor: Node3D = (view.rigs[rank] as Node3D).call("head_anchor")
	if anchor == null: return
	if crown == null:
		crown = ShowCrown.crown(ShowView.CROWN_HEIGHT)
	if crown.get_parent() != anchor:
		if crown.get_parent() != null: crown.get_parent().remove_child(crown)
		anchor.add_child(crown)
	var coming := pow(maxf(1.0 - age / ShowView.CROWN_FALL, 0.0), 2.0) * ShowView.CROWN_DROP
	crown.position = Vector3(0.0, ShowView.CROWN_SEAT + coming, 0.0)
	crown.rotation = ShowView.CROWN_TILT

func aim() -> void:
	if shell.view_override is Transform3D: camera.global_transform = shell.view_override

func empty_shots() -> void:
	place_rigs(0)
	flow.present(podium_state(6.0, 0), 0.0)
	for entry: Array in [["room_empty_wide", 3.0], ["room_empty_close", 0.3], ["room_empty_feet", 1.0]]:
		flow.present(podium_state(float(entry[1]), 0), 0.0)
		aim()
		await save(str(entry[0]))
	flow.present({"phase": "play", "t": 1.0}, 0.0)

func three_shots() -> void:
	place_rigs(3)
	step_rigs(1.0)
	var times := [["room_three_wide", 4.4], ["room_three_close", 8.6]]
	for entry: Array in times:
		flow.present(podium_state(float(entry[1]), 3), 0.0)
		crown_on(0, 5.0)
		step_rigs(0.1)
		aim()
		await save(str(entry[0]))
	crown.queue_free()
	crown = null
	flow.present({"phase": "play", "t": 1.0}, 0.0)

## The winner's head, close, from the front, the side and above (the crown on it): crown_front, crown_side, crown_top; prints where the head anchor is and how big.
func crown_shots() -> void:
	place_rigs(3)
	flow.present(podium_state(8.0, 3), 0.0)
	crown_on(0, 5.0)
	step_rigs(0.5)
	var anchor: Node3D = (view.rigs[0] as Node3D).call("head_anchor")
	print("PODIUM_FRAMES anchor above feet ", anchor.global_position.y - (view.rigs[0] as Node3D).global_position.y, " scale ", anchor.global_basis.get_scale(), " crown scale ", crown.global_basis.get_scale())
	var head := anchor.global_position
	for entry: Array in [["crown_front", Vector3(0.0, 0.25, 2.6)], ["crown_side", Vector3(2.6, 0.25, 0.0)], ["crown_top", Vector3(0.0, 2.2, 1.4)], ["crown_back34", Vector3(-1.6, 0.6, -1.9)]]:
		camera.global_transform = Transform3D(Basis.IDENTITY, head + (entry[1] as Vector3)).looking_at(head + Vector3(0.0, 0.1, 0.0), Vector3.UP)
		camera.fov = 30.0
		await save(str(entry[0]))
	crown.queue_free()
	crown = null
	flow.present({"phase": "play", "t": 1.0}, 0.0)

## The whole sequence: the banner over the summit (final level, the winner standing at the crown), the room's cut, every `1/fps` s.
func strip_shots() -> void:
	var origin: Vector3 = world.level_origin(15)
	var gameplay := Transform3D(Basis.IDENTITY, origin + Vector3(12.0, 34.2, -33.0)).looking_at(origin + Vector3(12.0, 33.0, -41.0), Vector3.UP)
	var winner: Node3D = CharRig.new()
	holder.add_child(winner)
	winner.setup(0, {})
	winner.global_position = origin + Vector3(12.0, 32.1, -39.5)
	winner.snap({"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": false})
	var index := 0
	var beat := 1.0 / float(fps)
	var t := 0.0
	var count := players
	var top: Array = []
	for rank in count: top.append(rank)
	view.rigs[0].visible = false # the winner of the gameplay frames is the extra rig
	while t < 1.7 - 0.001 and times.is_empty(): # the banner and a beat of gameplay
		flow.present({"phase": "done", "victory": true, "t": t, "crown": 0, "top": top, "stage": false}, 0.0)
		camera.global_transform = gameplay
		winner.update(beat, {"velocity": Vector3.ZERO, "grounded": true, "yaw": 0.0, "carrying": false})
		await save("strip_%03d_banner_%04.2f" % [index, t])
		index += 1
		t += beat
	winner.queue_free()
	place_rigs(count)
	t = 0.0
	var podium_length := 9.6
	var last_state := podium_state(0.0, count)
	var moments: Array[float] = times.duplicate()
	if moments.is_empty():
		while t <= podium_length + 0.001:
			moments.append(t)
			t += beat
	var clock := 0.0
	for moment in moments:
		last_state = podium_state(moment, count)
		flow.present(last_state, 0.0)
		if count > 0 and moment >= VictoryFlow.CROWN_AT: crown_on(0, moment - VictoryFlow.CROWN_AT)
		aim()
		step_rigs(maxf(moment - clock, 0.0))
		clock = moment
		await save("strip_%03d_room_%05.2f" % [index, moment])
		index += 1
	if crown != null:
		crown.queue_free()
		crown = null
	flow.present({"phase": "play", "t": 1.0}, 0.0) # back to the course: the room is gone, the lights and the lens are back
	await frames(2)
	print("PODIUM_FRAMES restored room_gone=", holder.find_child("PodiumRoom", true, false) == null, " fov=", camera.fov)
