extends SceneTree
## Strafe smear probe: THE SHOW for one player (the standalone app's path: client/solo_entry.gd, network role "local", the real follow camera of the round) with a
## scripted courier that strafes sideways at the full run, left and right, in a race round (default ROOFTOP RUN, stage camera) or in the lobby yard (`--lobby`, the shoulder
## camera). Per RENDERED frame (after the camera and the rig were placed) it logs the rig's visual position, the camera position and the courier's screen x, and then reports the
## jitter of the screen x while the courier runs steadily: with a constant velocity the camera's follow settles to a constant offset, so any wobble left in the courier's screen x
## (peak to peak, standard deviation, the biggest frame-to-frame step) is the smear. Also reports the same for the courier's chest point projected from the PHYSICS position (what the
## camera would follow without the visual track), and the camera-relative offset of the visual.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 200 "/Applications/Summer Engine.app/Contents/MacOS/Summer" --headless --audio-driver Dummy --rendering-driver dummy \
##     --fixed-fps 120 --path demo -s "$PWD/tools/strafe_jitter_probe.gd" -- [--level=r29] [--lobby] [--seconds=6] [--csv=<file>] [--fps=0|60|120] [--vsync=0|1] [--hitch=<ms>] [--shots=<dir> [--shot-at=<s>] [--shot-count=<n>] [--shot-every=<frames>]]
## `--fixed-fps N` (engine flag) fixes the frame step: 60 = one physics tick per frame, 120 = a tick every other frame. Without it the frames run in real time:
## `--fps=N` sets Engine.max_fps (0 = uncapped), `--vsync=` the window's vsync mode.
## Prints STRAFE lines and `STRAFE ok=<bool>` (the jitter must stay under --limit px, default 1.0).
class Solo extends "res://client/presentation_entry.gd":
	var strafe := 0.0
	func _init() -> void:
		super()
		local_players = 1
	func connected_pads() -> Array: return []
	func _sample_local_inputs(_delta: float) -> void:
		if local_input_enabled and playing: _local_commands[0] = {"move": Vector2(strafe, 0.0), "action": false}
		else: _local_commands[0] = {"move": Vector2.ZERO, "action": false}

class Sampler extends Node:
	var probe
	func _process(delta: float) -> void:
		probe._frame(delta)
		if probe.hitch_ms > 0: OS.delay_usec(randi_range(0, probe.hitch_ms * 1000)) # real-time runs: an irregular frame pace (a busy machine), the physics tick count per frame varies

const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const TeamCast := preload("res://style/team_cast.gd")
const HALF := 1.2 ## s of every run to the left or to the right
var level_pad := "r29"
var lobby := false
var seconds := 6.0
var settle := 0.25 ## s after the courier reached the full run before a sample counts (the camera's follow has settled: the stage view's tau is 0.03 s, the shoulder view's 0.1 s)
var shot_at := 0.7
var shot_count := 8
var shot_every := 1
var hitch_ms := 0
var csv := ""
var shots := ""
var limit := 1.0
var fps := -1
var vsync := -1
var sim: Node
var rows: Array = []
var recording := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): level_pad = a.trim_prefix("--level=")
		if a == "--lobby": lobby = true
		if a.begins_with("--seconds="): seconds = float(a.trim_prefix("--seconds="))
		if a.begins_with("--settle="): settle = float(a.trim_prefix("--settle="))
		if a.begins_with("--hitch="): hitch_ms = int(a.trim_prefix("--hitch="))
		if a.begins_with("--csv="): csv = a.trim_prefix("--csv=")
		if a.begins_with("--shot-at="): shot_at = float(a.trim_prefix("--shot-at="))
		if a.begins_with("--shot-every="): shot_every = maxi(int(a.trim_prefix("--shot-every=")), 1)
		if a.begins_with("--shot-count="): shot_count = int(a.trim_prefix("--shot-count="))
		if a.begins_with("--shots="): shots = a.trim_prefix("--shots=")
		if a.begins_with("--limit="): limit = float(a.trim_prefix("--limit="))
		if a.begins_with("--fps="): fps = int(a.trim_prefix("--fps="))
		if a.begins_with("--vsync="): vsync = int(a.trim_prefix("--vsync="))
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["mode"] = "show"
	TeamCast.override(cast)
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame
	await process_frame

func _run() -> void:
	sim = Solo.new()
	root.add_child(sim)
	current_scene = sim
	var deadline := Time.get_ticks_msec() + 120000
	while not sim.is_network_ready() or sim.local_presentation == null or not sim.local_presentation.ready_for_play:
		await process_frame
		if Time.get_ticks_msec() > deadline:
			print("STRAFE FAIL boot_timeout")
			quit(2)
			return
	if DisplayServer.get_name() == "headless": root.size = Vector2i(1280, 720) # px are measured on the app's design size (the headless window is 64 x 64)
	if fps >= 0: Engine.max_fps = fps
	if vsync >= 0: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync == 1 else DisplayServer.VSYNC_DISABLED)
	var ui = sim.local_presentation
	var hud_script = load("res://client/hud.gd")
	for key in ["move", "jump", "tilt", "lift"]: hud_script.taught[key] = true
	await frames(60)
	var flow = ui.level_flow
	print("STRAFE info display=", DisplayServer.get_name(), " fixed_fps=", Engine.physics_ticks_per_second, " max_fps=", Engine.max_fps, " vsync=", DisplayServer.window_get_vsync_mode(), " driver=", RenderingServer.get_current_rendering_driver_name(), " first_person=", sim.first_person, " window=", root.size)
	if not lobby:
		sim.actors[0].position = WalkInLobby.center(level_pad) + Vector3(0.0, 0.3, 0.0)
		await frames(20)
		flow.press_play()
		var wait_until := Time.get_ticks_msec() + 60000
		while not (sim.round_mode != "lobby" and sim.playing and flow.minigame != null and str(flow.minigame.phase) == "play"):
			await frames(10)
			if Time.get_ticks_msec() > wait_until:
				print("STRAFE FAIL round did not start phase=", flow.minigame.phase if flow.minigame != null else "none", " pick=", flow.probe())
				quit(2)
				return
		print("STRAFE info round started level=", flow.minigame.level if "level" in flow.minigame else "?", " stage_view=", sim._stage_view, " air_follow=", sim._stage_air_follow)
	else:
		print("STRAFE info lobby stage_view=", sim._stage_view)
	await frames(30)
	sim.actors[0].velocity = Vector3.ZERO
	seed(7)
	var sampler := Sampler.new()
	sampler.probe = self
	sampler.process_priority = 1000000 # after every other node's _process (the shell's camera and rigs): what the frame will draw
	root.add_child(sampler)
	recording = true
	if shots != "" and DisplayServer.get_name() != "headless": _shoot.call_deferred()
	while clock < seconds: await process_frame
	recording = false
	sampler.queue_free()
	_report()
	quit(0 if _ok else 1)

var clock := 0.0

## Once per frame, last: steers the courier for the next tick and records the picture this frame will draw.
func _frame(delta: float) -> void:
	if not recording: return
	clock += delta
	sim.strafe = 1.0 if int(clock / HALF) % 2 == 0 else -1.0
	_sample(clock)

## `--shots=<dir>`: `--shot-count` consecutive frames from `--shot-at` s on (the first right-hand run is at full speed from 0.4 s), as they are drawn.
func _shoot() -> void:
	var saved := 0
	var seen := 0
	DirAccess.make_dir_recursive_absolute(shots)
	while saved < shot_count and recording:
		await RenderingServer.frame_post_draw
		if clock < shot_at: continue
		seen += 1
		if (seen - 1) % shot_every != 0: continue
		root.get_texture().get_image().save_png("%s/f%02d.png" % [shots, saved])
		saved += 1

var _ok := true
var _meshes: Array = []

func _sample(clock: float) -> void:
	var camera: Camera3D = sim.camera
	var rig: Node3D = sim.rigs[0]
	var body: CharacterBody3D = sim.actors[0]
	var chest := Vector3(0.0, 1.0, 0.0)
	var visual: Vector3 = rig.global_position
	var vp := root.get_visible_rect().size
	var sx := camera.unproject_position(visual + chest).x
	var sx_body := camera.unproject_position(body.global_position + chest).x
	if _meshes.is_empty(): _meshes = rig.find_children("*", "MeshInstance3D", true, false)
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in _meshes:
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var world_box := mesh.global_transform * mesh.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	var sx_mesh := camera.unproject_position(box.get_center()).x if not first else sx
	# the deformed body: the head, hand and foot bones (the animation's own motion: a gait that swings the body about the rig's origin shows here, not in the meshes' rest boxes)
	var sx_head := sx
	var sx_bones := sx
	var skeleton: Skeleton3D = rig._skeleton
	if skeleton != null and rig._bone.get("head", -1) >= 0:
		var indices: Array = [rig._bone["head"]]
		indices.append_array(rig._bone["hand"])
		indices.append_array(rig._bone["foot"])
		var total := 0.0
		for index: int in indices: total += camera.unproject_position(skeleton.global_transform * skeleton.get_bone_global_pose(index).origin).x
		sx_bones = total / float(indices.size())
		sx_head = camera.unproject_position(skeleton.global_transform * skeleton.get_bone_global_pose(rig._bone["head"]).origin).x
	rows.append({"t": clock, "wall": Time.get_ticks_usec() * 1.0e-6, "frame": Engine.get_process_frames(), "phys": Engine.get_physics_frames(), "alpha": Engine.get_physics_interpolation_fraction(), "vx": body.velocity.x, "sx": sx, "sx_body": sx_body, "sx_mesh": sx_mesh, "height_px": absf(camera.unproject_position(visual).y - camera.unproject_position(visual + Vector3(0.0, 1.8, 0.0)).y), "sx_head": sx_head, "sx_bones": sx_bones,
		"vis": visual, "body": body.global_position, "cam": camera.global_position, "vp": vp})

func _report() -> void:
	if csv != "":
		var file := FileAccess.open(csv, FileAccess.WRITE)
		file.store_line("t,wall,frame,physics_frame,alpha,vx,screen_x_visual,screen_x_body,screen_x_mesh,screen_x_head,screen_x_bones,visual_x,visual_y,visual_z,body_x,body_z,cam_x,cam_y,cam_z")
		for r: Dictionary in rows:
			file.store_line("%.5f,%.5f,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f" % [r.t, r.wall, r.frame, r.phys, r.alpha, r.vx, r.sx, r.sx_body, r.sx_mesh, r.sx_head, r.sx_bones, r.vis.x, r.vis.y, r.vis.z, r.body.x, r.body.z, r.cam.x, r.cam.y, r.cam.z])
		file.close()
	# steady segments: the courier at the full run (|vx| within 2 % of its peak), the same way, from `settle` s after it got there until it lets go
	var peak := 0.0
	for r: Dictionary in rows: peak = maxf(peak, absf(r.vx))
	var segments: Array = []
	var current: Array = []
	var run_start := -1.0
	var sign_now := 0.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var s := signf(r.vx)
		var full: bool = absf(r.vx) >= peak * 0.98
		if not full or s != sign_now:
			sign_now = s
			run_start = float(r.t) if full else -1.0
			if not current.is_empty():
				segments.append(current)
				current = []
			continue
		if run_start < 0.0: run_start = float(r.t) # reached the full run (the sign had already turned while it was still speeding up)
		if float(r.t) - run_start >= settle: current.append(i)
	if not current.is_empty(): segments.append(current)
	segments = segments.filter(func(segment: Array) -> bool: return segment.size() >= 10)
	var frame_dt := PackedFloat64Array()
	for i in range(1, rows.size()): frame_dt.append(float(rows[i].t) - float(rows[i - 1].t))
	frame_dt.sort()
	var med := frame_dt[frame_dt.size() / 2] if frame_dt.size() > 0 else 0.0
	var wall_dt := PackedFloat64Array()
	for i in range(1, rows.size()): wall_dt.append(float(rows[i].wall) - float(rows[i - 1].wall))
	wall_dt.sort()
	if wall_dt.size() > 10: print("STRAFE wall frame times: median %.2f ms  p5 %.2f  p95 %.2f  max %.2f" % [wall_dt[wall_dt.size() / 2] * 1000.0, wall_dt[wall_dt.size() / 20] * 1000.0, wall_dt[wall_dt.size() * 19 / 20] * 1000.0, wall_dt[wall_dt.size() - 1] * 1000.0])
	var vp: Vector2 = rows[0].vp
	var samples := 0
	for segment: Array in segments: samples += segment.size()
	print("STRAFE result frames=%d segments=%d steady_samples=%d peak_vx=%.3f m/s viewport=%dx%d median_frame=%.2f ms (%.1f fps)" % [rows.size(), segments.size(), samples, peak, vp.x, vp.y, med * 1000.0, 1.0 / maxf(med, 1.0e-6)])
	var visual := _jitter(segments, "sx")
	# the lag swing: where the courier stands on the screen in the steady run to the right against the steady run to the left (the camera's follow trails the courier by speed / rate), in px and in its own height
	var right := 0.0
	var left := 0.0
	var right_n := 0
	var left_n := 0
	var heights := PackedFloat64Array()
	for segment: Array in segments:
		for i: int in segment:
			if float(rows[i].vx) > 0.0:
				right += float(rows[i].sx)
				right_n += 1
			else:
				left += float(rows[i].sx)
				left_n += 1
			heights.append(float(rows[i].height_px))
	heights.sort()
	if right_n > 0 and left_n > 0 and heights.size() > 0:
		var swing := right / float(right_n) - left / float(left_n)
		print("STRAFE lag swing: courier stands %.1f px right of its left-run place in the right run (courier %.0f px tall: %.2f x its height)" % [swing, heights[heights.size() / 2], swing / heights[heights.size() / 2]])
	var body := _jitter(segments, "sx_body")
	print("STRAFE jitter visual (the courier the player sees): p2p=%.3f px  max_step=%.3f px  rms=%.3f px" % [visual.p2p, visual.step, visual.rms])
	var mesh_box := _jitter(segments, "sx_mesh")
	print("STRAFE jitter body_meshes_centre (animation included): p2p=%.3f px  max_step=%.3f px  rms=%.3f px" % [mesh_box.p2p, mesh_box.step, mesh_box.rms])
	var head := _jitter(segments, "sx_head")
	var bones := _jitter(segments, "sx_bones")
	print("STRAFE jitter head_bone (animation included): p2p=%.3f px  max_step=%.3f px  rms=%.3f px" % [head.p2p, head.step, head.rms])
	print("STRAFE jitter bones_centroid (head, hands, feet): p2p=%.3f px  max_step=%.3f px  rms=%.3f px" % [bones.p2p, bones.step, bones.rms])
	print("STRAFE jitter raw_physics_point (where the courier was drawn before the fix): p2p=%.3f px  max_step=%.3f px  rms=%.3f px" % [body.p2p, body.step, body.rms])
	_ok = visual.p2p <= limit and samples >= 10
	print("STRAFE ok=%s" % [_ok])

## The screen-x residual against the least-squares parabola of each steady segment (removes the camera's slow settle and any slow change of the run's speed, keeps everything that changes from frame to
## frame): the worst peak to peak, the biggest frame step of the residual, the RMS.
func _jitter(segments: Array, key: String) -> Dictionary:
	var p2p := 0.0
	var step := 0.0
	var sum2 := 0.0
	var count := 0
	for segment: Array in segments:
		var n := float(segment.size())
		var mean_t := 0.0
		for i: int in segment: mean_t += float(rows[i].t)
		mean_t /= n
		var s2 := 0.0
		var s3 := 0.0
		var s4 := 0.0
		var t0 := 0.0
		var t1 := 0.0
		var t2 := 0.0
		for i: int in segment:
			var tau: float = float(rows[i].t) - mean_t
			var v: float = rows[i][key]
			s2 += tau * tau
			s3 += tau * tau * tau
			s4 += tau * tau * tau * tau
			t0 += v
			t1 += tau * v
			t2 += tau * tau * v
		# normal equations of v = a + b tau + c tau^2 with sum(tau) = 0:  [n 0 s2; 0 s2 s3; s2 s3 s4] [a b c] = [t0 t1 t2]
		var det := _det3([[n, 0.0, s2], [0.0, s2, s3], [s2, s3, s4]])
		var coefficients := _solve3([[n, 0.0, s2], [0.0, s2, s3], [s2, s3, s4]], [t0, t1, t2]) if absf(det) > 1.0e-18 else [t0 / n, 0.0, 0.0]
		var low := 1.0e18
		var high := -1.0e18
		var before := 0.0
		for k in segment.size():
			var i: int = segment[k]
			var tau: float = float(rows[i].t) - mean_t
			var e: float = float(rows[i][key]) - (float(coefficients[0]) + float(coefficients[1]) * tau + float(coefficients[2]) * tau * tau)
			low = minf(low, e)
			high = maxf(high, e)
			if k > 0: step = maxf(step, absf(e - before))
			before = e
			sum2 += e * e
			count += 1
		p2p = maxf(p2p, high - low)
	return {"p2p": p2p, "step": step, "rms": sqrt(sum2 / maxf(float(count), 1.0))}

## Cramer's rule for a 3 x 3 system.
func _solve3(m: Array, r: Array) -> Array:
	var d := _det3(m)
	var out := []
	for column in 3:
		var swapped: Array = [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
		for row in 3: swapped[row][column] = r[row]
		out.append(_det3(swapped) / d)
	return out

func _det3(m: Array) -> float:
	return float(m[0][0]) * (float(m[1][1]) * float(m[2][2]) - float(m[1][2]) * float(m[2][1])) - float(m[0][1]) * (float(m[1][0]) * float(m[2][2]) - float(m[1][2]) * float(m[2][0])) + float(m[0][2]) * (float(m[1][0]) * float(m[2][1]) - float(m[1][1]) * float(m[2][0]))
