extends SceneTree
## Cross-check of tools/mover_clearance_check.py against the real motion code: the checker's pure-data `slide` / `lift` poses (`--poses`, the same formulas)
## must equal `Hazards.pose` (levels/hazards.gd, the level clock the world poses its movers with) for every mover of levels 29-32 at 13 clock values.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 60 "/Applications/Summer Engine.app/Contents/MacOS/Summer" --headless --audio-driver Dummy --fixed-fps 60 --path demo -s $PWD/tools/mover_pose_check.gd
const Hazards := preload("res://levels/hazards.gd")
const LEVELS := [29, 30, 31, 32]
const TOLERANCE := 0.001

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var script := root.path_join("tools/mover_clearance_check.py")
	var args := PackedStringArray([script, "--poses"])
	for n in LEVELS: args.append(root.path_join("demo/levels/level_%d.json" % n))
	var out: Array = []
	var code := OS.execute("python3", args, out, true)
	var checks := 0
	var fails := 0
	if code != 0:
		print("FAIL python3 mover_clearance_check.py --poses exited %d: %s" % [code, str(out)])
		quit(1)
		return
	var movers := {}
	for n in LEVELS:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/level_%d.json" % n))
		for source: Dictionary in data.hazards:
			if source.k == "slide" or source.k == "lift":
				movers["level_%d.json %s" % [n, str(source.get("id", ""))]] = Hazards.normalize(source)
	var pose := Hazards.Pose.new()
	for line in (out[0] as String).split("\n", false):
		var cols := line.split(" ")
		var key := "%s %s" % [cols[0], cols[1]]
		if cols.size() != 6 or not movers.has(key):
			print("FAIL unparsed or unknown line: ", line)
			fails += 1
			continue
		var want := Vector3(float(cols[3]), float(cols[4]), float(cols[5]))
		Hazards.pose(movers[key], float(cols[2]), pose)
		checks += 1
		if pose.position.distance_to(want) > TOLERANCE:
			fails += 1
			print("FAIL %s at t=%s: engine %s, checker %s" % [key, cols[2], pose.position, want])
	print("mover_pose_check: %d poses compared, %d movers, %d failures" % [checks, movers.size(), fails])
	quit(1 if fails > 0 else 0)
