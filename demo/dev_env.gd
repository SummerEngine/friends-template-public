extends RefCounted
## The one gate for developer/QA switches: FRIENDS_* environment variables, QA user args
## (--bot, --play-bot, --online-bot, --lag-*, --glass-*, --menu-style*, --touch*, ...), the
## private-QA file and the periodic state prints. All of them work only in the editor binary
## (Local Play, tools, SDK acceptance) or a debug export; a release export (the hosted
## staging/production packs) ignores every one of them. The Summer Games runtime sandbox also
## blocks OS.get_environment and logs an ERROR for every call, so shipped builds never ask.

static func is_dev() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()

static func read(name: String) -> String:
	if not OS.has_feature("editor"):
		return ""
	return OS.get_environment(name)

## Command-line user args (after `--`); empty in a release build.
static func user_args() -> PackedStringArray:
	if not is_dev():
		return PackedStringArray()
	return OS.get_cmdline_user_args()

static func has_arg(flag: String) -> bool:
	return is_dev() and flag in OS.get_cmdline_user_args()

## A dev probe script (`--net-probe=<absolute path of a .gd>`, tools/net_stage_check.gd): attached to the authority's / the client's main node as `probe.attach(host, role)`;
## the client also asks it for its round input. Dev binary only: a release export has no user args, so nothing is ever loaded. Returns null for none.
static func attach_probe(host: Node, role: String) -> Object:
	for arg in user_args():
		if not arg.begins_with("--net-probe="): continue
		var script: Variant = load(arg.trim_prefix("--net-probe="))
		if not script is GDScript: return null
		var probe: Object = script.new()
		probe.call("attach", host, role)
		return probe
	return null

# ------------------------------------------------------------------ periodic performance line (dev only)
static var _perf_node: Timer
static var _perf_last_usec := 0
static var _perf_frames := 0
static var _perf_sum_usec := 0
static var _perf_max_usec := 0
static var _perf_physics := 0
static var _perf_physics_since_frame := 0
static var _perf_physics_max_per_frame := 0
static var _perf_started_msec := 0
static var _lap_on := false
static var _lap_usec := {}

## Dev lap timers (measurement only): `var t := DevEnv.now()` ... `DevEnv.lap("name", t)`. Costs one bool test while the perf line is off.
static func now() -> int:
	return Time.get_ticks_usec() if _lap_on else 0

static func lap(label: String, since: int) -> void:
	if _lap_on: _lap_usec[label] = int(_lap_usec.get(label, 0)) + Time.get_ticks_usec() - since

## Prints `GW_PERF ...` every `interval` seconds: fps, frame ms (mean/max), physics steps per rendered frame,
## engine time monitors, object/node/resource counts, draw calls, GPU and static memory. Dev/debug builds only;
## `force` is for the local test lab, whose release-template Android build is not a debug build.
static func perf_attach(host: Node, interval := 10.0, force := false) -> void:
	if not (force or is_dev()) or is_instance_valid(_perf_node): return
	var tree := host.get_tree()
	_perf_started_msec = Time.get_ticks_msec()
	_lap_on = true
	_perf_node = Timer.new()
	_perf_node.name = "PerfTimer"
	_perf_node.wait_time = interval
	_perf_node.autostart = true
	_perf_node.process_mode = Node.PROCESS_MODE_ALWAYS
	_perf_node.timeout.connect(_perf_print)
	host.add_child(_perf_node)
	tree.process_frame.connect(_perf_frame)
	tree.physics_frame.connect(_perf_step)
	var window := host.get_window()
	print("GW_PERF_INFO renderer=", RenderingServer.get_current_rendering_method(), " driver=", RenderingServer.get_current_rendering_driver_name(),
		" window=", window.size, " visible=", host.get_viewport().get_visible_rect().size, " screen=", DisplayServer.screen_get_size(),
		" refresh=", DisplayServer.screen_get_refresh_rate(), " vsync=", DisplayServer.window_get_vsync_mode(), " max_fps=", Engine.max_fps,
		" physics_hz=", Engine.physics_ticks_per_second, " max_steps=", Engine.max_physics_steps_per_frame, " scale3d=", window.scaling_3d_scale,
		" msaa=", window.msaa_3d, " debug=", OS.is_debug_build(), " user=", OS.get_user_data_dir())

static var _phase_phys_start := 0

## `lap.phys_wall` = wall time of all physics steps of a frame (script callbacks plus the engine's physics server step):
## from each physics_frame signal to the next physics_frame / the process_frame that follows the last step.
static func _perf_step() -> void:
	_perf_physics += 1
	_perf_physics_since_frame += 1
	var now := Time.get_ticks_usec()
	if _phase_phys_start != 0: _lap_usec["phys_wall"] = int(_lap_usec.get("phys_wall", 0)) + now - _phase_phys_start
	_phase_phys_start = now

static func _perf_frame() -> void:
	var now := Time.get_ticks_usec()
	if _phase_phys_start != 0:
		_lap_usec["phys_wall"] = int(_lap_usec.get("phys_wall", 0)) + now - _phase_phys_start
		_phase_phys_start = 0
	if _perf_last_usec != 0:
		var span := now - _perf_last_usec
		_perf_frames += 1
		_perf_sum_usec += span
		_perf_max_usec = maxi(_perf_max_usec, span)
	_perf_last_usec = now
	_perf_physics_max_per_frame = maxi(_perf_physics_max_per_frame, _perf_physics_since_frame)
	_perf_physics_since_frame = 0

static func _perf_print() -> void:
	var seconds := float(_perf_sum_usec) / 1000000.0
	var frames := maxi(1, _perf_frames)
	var mem := OS.get_memory_info()
	print("GW_PERF t=", (Time.get_ticks_msec() - _perf_started_msec) / 1000,
		" fps=", snappedf(float(_perf_frames) / maxf(seconds, 0.001), 0.1), " engine_fps=", Engine.get_frames_per_second(),
		" frame_ms=", snappedf(float(_perf_sum_usec) / 1000.0 / frames, 0.1), " frame_max_ms=", snappedf(float(_perf_max_usec) / 1000.0, 0.1),
		" steps=", _perf_physics, " steps_per_frame=", snappedf(float(_perf_physics) / frames, 0.01), " steps_max=", _perf_physics_max_per_frame,
		" process_ms=", snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
		" physics_ms=", snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
		" objects=", int(Performance.get_monitor(Performance.OBJECT_COUNT)), " nodes=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		" orphans=", int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), " resources=", int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		" draws=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), " prims=", int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		" vmem_mb=", snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		" tex_mb=", snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		" buf_mb=", snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		" static_mb=", snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		" phys_active=", int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), " pairs=", int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		" sys_avail_mb=", int(float(mem.get("available", 0)) / 1048576.0),
		" rs_setup_ms=", snappedf(RenderingServer.get_frame_setup_time_cpu(), 0.1), _lap_text(frames))
	_lap_usec.clear()
	_perf_frames = 0
	_perf_sum_usec = 0
	_perf_max_usec = 0
	_perf_physics = 0
	_perf_physics_max_per_frame = 0

## " lap.<name>=ms per rendered frame" for every lap that ran in the window, biggest first.
static func _lap_text(frames: int) -> String:
	var rows: Array = []
	for label: String in _lap_usec:
		rows.append([label, float(_lap_usec[label]) / 1000.0 / float(frames)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var text := ""
	for row: Array in rows: text += " lap.%s=%.2f" % [row[0], row[1]]
	return text
