extends Node
## --lab-shots=<dir> [--lab-poses=<json text or file>] [--lab-hide-help]: PNG frames of the lab (offscreen runs only).
## A pose: {"name": "stop01", "stop": 0, "ui": "none|help|stops|pause|cleared|loading", "yaw": deg, "pitch": deg, "wait": ticks,
## "offset": [x, y, z], "fly": true (hover there)}. `stop` is 0-based; `offset` moves the courier from the pad (level axes, metres); `ui` picks the sheet in view
## (default: the help keys unless --lab-hide-help). Prints GW_LAB_SHOT lines and quits.
var lab

func run_shots(owner_lab, dir: String) -> void:
	lab = owner_lab
	_run.call_deferred(dir)

func _poses() -> Array:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--lab-poses="): continue
		var text := arg.trim_prefix("--lab-poses=")
		if FileAccess.file_exists(text): text = FileAccess.get_file_as_string(text)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Array: return parsed
		print("GW_LAB_SHOT poses are not a JSON array")
	return [{"name": "stop01", "stop": 0}]

func _hide_help() -> bool:
	return OS.get_cmdline_user_args().has("--lab-hide-help")

func _ticks(count: int) -> void:
	for index in count: await get_tree().physics_frame

func _save(dir: String, name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_tree().root.get_texture().get_image()
	print("GW_LAB_SHOT ", name, " ", image.save_png("%s/%s.png" % [dir, name]) == OK, " ", image.get_size())

func _run(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _ticks(2)
	for pose: Dictionary in _poses():
		var name := str(pose.get("name", "shot"))
		var ui := str(pose.get("ui", "none" if _hide_help() else "help"))
		lab.set_pause(false)
		lab.help_mode = 1 if ui == "help" else (2 if ui == "stops" else 0)
		lab.fly = false
		lab.travel(clampi(int(pose.get("stop", 0)), 0, lab.stops.size() - 1))
		lab.sheets._toast_left = 0.0
		lab.yaw = deg_to_rad(float(pose.get("yaw", rad_to_deg(lab.yaw))))
		lab.pitch = deg_to_rad(float(pose.get("pitch", 0.0)))
		var offset: Array = pose.get("offset", [])
		if offset.size() == 3:
			var at: Vector3 = lab.stops[lab.stop].pad + Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
			lab.motion.teleport(lab.body, at)
		if bool(pose.get("fly", false)): lab.fly = true
		lab.follow.reset_lag()
		await _ticks(int(pose.get("wait", 40)))
		match ui:
			"cleared":
				var goal: Dictionary = lab.level_world.goal_volume(lab.current_level())
				lab.motion.teleport(lab.body, (goal.p as Vector3) - Vector3(0.0, 0.8, 0.0))
				await _ticks(30)
			"pause": lab.set_pause(true)
			"loading":
				lab.screens.set_loading_kicker(lab.LABEL)
				lab.screens.show_loading("THE LEVELS", "Building the levels", false, 0.0)
				lab.screens.update_loading_progress(0.62, "Levels")
				await _ticks(20)
		await _save(dir, name)
		if ui == "loading": lab.screens.hide_all()
	lab.set_pause(false)
	print("GW_LAB_SHOT done")
	get_tree().quit(0)
