extends SceneTree
## Headless check of the backdrop rules (style/backdrop.gd) for every level and the lobby: builds each backdrop and reads its instance data back.
## Every piece that is not drifting must lie entirely 25 m or more below the lowest walkable surface, or keep 12 m or more from the course's
## bounding box on x/z; every drifting piece flies in a lane that keeps 12 m or more from that box. Prints GW_BACKDROPCHECK lines; exit 1 on a violation.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer 0.7.2> --headless --audio-driver Dummy --path demo -s $PWD/tools/backdrop_check.gd
const Data := preload("res://levels/level_data.gd")
const Backdrop := preload("res://style/backdrop.gd")
const Themes := preload("res://style/backdrop_themes.gd")
const MIN_SIDE := 12.0
const MIN_BELOW := 25.0
const STRIDE := 20

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	preload("res://style/surfaces.gd").set_ink(true) # the comic backdrop (the facility look builds a plain room instead: style/room_shell.gd)
	var failures := 0
	var count := Data.count()
	for number in range(1, count + 1):
		var data := Data.load_level(number)
		if not (data.stage as Dictionary).is_empty() or data.world == "daylight": continue # a stage round's world is the arena cage and city (style/arena_world.gd), built to hug the tiles, and a `world: daylight` level's the open-air race world (style/race_world.gd, tools/race_world_check.gd): their own rules
		var spec := Backdrop.level_spec(data)
		var started := Time.get_ticks_usec()
		var root := Backdrop.for_level(number, data, Vector3.ZERO)
		var built := float(Time.get_ticks_usec() - started) / 1000.0
		failures += _check(root, spec, "level %02d" % number, built)
		root.free()
	var lobby_spec := {"bbox": Backdrop.LOBBY_BOX, "y_low": -0.65}
	var lobby := Backdrop.for_lobby(Vector3.ZERO)
	failures += _check(lobby, lobby_spec, "lobby", 0.0)
	lobby.free()
	print("GW_BACKDROPCHECK %s: %d levels, %d violations" % ["OK" if failures == 0 else "FAILED", count, failures])
	quit(1 if failures > 0 else 0)

func _check(root: Node3D, spec: Dictionary, label: String, built_ms: float) -> int:
	var bbox: Rect2 = spec.bbox
	var y_low: float = spec.y_low
	var bad := 0
	var instances := 0
	var draws := 0
	var drifting := 0
	var highest_below := -INF
	var lanes_along_z := bbox.size.y >= bbox.size.x
	var nearest := INF
	for child: Node in root.get_children():
		var node := child as MultiMeshInstance3D
		if node == null: continue
		draws += 1
		var data: PackedFloat32Array = node.multimesh.buffer
		for i in node.multimesh.instance_count:
			var b := i * STRIDE
			var o := Vector3(data[b + 3], data[b + 7], data[b + 11])
			var half := Vector3(absf(data[b]) + absf(data[b + 1]) + absf(data[b + 2]), absf(data[b + 4]) + absf(data[b + 5]) + absf(data[b + 6]),
				absf(data[b + 8]) + absf(data[b + 9]) + absf(data[b + 10])) * 0.5
			instances += 1
			var speed := data[b + 19]
			var gap_x := maxf(maxf(bbox.position.x - (o.x + half.x), (o.x - half.x) - bbox.end.x), 0.0)
			var gap_z := maxf(maxf(bbox.position.y - (o.z + half.z), (o.z - half.z) - bbox.end.y), 0.0)
			if absf(speed) > 0.001:
				drifting += 1
				var lane_gap := gap_x if lanes_along_z else gap_z
				nearest = minf(nearest, lane_gap)
				if lane_gap < MIN_SIDE:
					bad += 1
					print("GW_BACKDROPCHECK   %s: drifting piece at %s only %.1f m from the course in its lane" % [label, o, lane_gap])
			elif o.y + half.y <= y_low - MIN_BELOW:
				highest_below = maxf(highest_below, o.y + half.y)
			else:
				var side := Vector2(gap_x, gap_z).length()
				nearest = minf(nearest, side)
				if side < MIN_SIDE:
					bad += 1
					print("GW_BACKDROPCHECK   %s: piece at %s (half %s) is %.1f m from the course box and not %.0f m below it" % [label, o, half, side, MIN_BELOW])
	print("GW_BACKDROPCHECK %s: %d instances in %d bodies (%d drifting), highest piece below the course %.1f m under it, nearest other piece %.1f m, built in %.1f ms, %d violations" % [label, instances, draws, drifting, y_low - highest_below, nearest, built_ms, bad])
	return bad
