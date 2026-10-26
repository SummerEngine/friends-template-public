extends RefCounted
## The item boxes of a race level (`--show-level=29` .. `32`; docs/level-format.md "Item boxes"): every box stands on the floor, a scripted racer that walks the route takes a box of every row in order
## (a real walk through the box: the authority decides from its pose), a taken box is gone from the state's mask and from the client's view and is back 8 s later, and the numbers of the level are printed.
## Frames (`--shots`, `--view=0`): per row the runner 3 m before it and the moment after the pick (the burst, the HUD slot rolling).
const REACH := 1.15 ## m, `box.radius` in items.json: a racer within this horizontally takes the box
const STEEP := {"29:1": -65.0, "30:2": -65.0, "31:1": -55.0, "31:2": -60.0, "32:1": -65.0, "32:2": -65.0} ## rows right behind a gate wall or a ramp beam: the frame looks down over it (degrees, the others -32)
const LEAD := 3.5 ## m of route before a row where the runner is stood
const ROW_LINK := 3.2 ## boxes this near each other (m) are one row (a row's step is at most 3 m)

func run(h) -> void:
	for slot in 3: h.hold(slot)
	await h.tick(20)
	var items = h.rules().items
	var world = h.sim.level_world
	var level: int = int(h.state().level)
	var number: int = level + 1
	var route: PackedVector3Array = world.route(level)
	var spots: PackedVector3Array = items.boxes
	var length := 0.0
	for index in route.size() - 1: length += route[index].distance_to(route[index + 1])
	h.check(items.enabled and spots.size() >= 2 and spots.size() <= 12, "level %d has %d item boxes" % [number, spots.size()])
	# every box on the floor
	var worst := 0.0
	for spot: Vector3 in spots:
		var floor_y: float = world.floor_y(level, spot)
		worst = maxf(worst, 99.0 if is_nan(floor_y) else absf(floor_y - spot.y))
	h.check(worst <= 0.06, "every box stands on the floor (worst gap %.3f m)" % worst)
	# the rows
	var rows: Array = []
	for index in spots.size():
		var placed := false
		for row: Array in rows:
			var last: Vector3 = spots[row[row.size() - 1]]
			if Vector2(last.x - spots[index].x, last.z - spots[index].z).length() < ROW_LINK:
				row.append(index)
				placed = true
				break
		if not placed: rows.append([index])
	h.check(rows.size() >= 2 and rows.size() <= 3, "%d rows (2 or 3)" % rows.size())
	print("ITEMS_CHECK level %d: %d rows, %d boxes, route %.1f m" % [number, rows.size(), spots.size(), length])
	var respawn_checked := false
	if h.shots != "": (h.replicas[h.shot_view].get("camera") as Camera3D).make_current() # the shown view follows its courier all along (a camera that is not current is not placed)
	if h.shots != "": await h.tick(3) # the shell sets a new view's yaw and pitch on its first frame: ours come after
	for k in rows.size():
		var row: Array = rows[k]
		var centre := Vector3.ZERO
		for index: int in row: centre += spots[index] / float(row.size())
		# where the route is nearest the row, and how far it passes from the nearest box
		var best := INF
		var at := 0
		for i in route.size():
			var gap := Vector2(route[i].x - centre.x, route[i].z - centre.z).length()
			if gap < best:
				best = gap
				at = i
		var metres := 0.0
		for i in at: metres += route[i].distance_to(route[i + 1])
		var passes := INF
		for i in range(maxi(at - 2, 0), mini(at + 2, route.size() - 1)):
			for index: int in row:
				passes = minf(passes, _segment_gap(route[i], route[i + 1], spots[index]))
		h.check(passes <= REACH - 0.1, "row %d (%d boxes, %.0f m along, %d %%): the route passes %.2f m from a box" % [k + 1, row.size(), metres, roundi(metres / length * 100.0), passes])
		# stand the runner before the row, look, then walk through it
		h.hold(0)
		var stand := 0.0 # the last waypoint at least LEAD m of route before the row (never a waypoint inside the row's reach)
		var run := 0.0
		for i in at:
			if run <= metres - LEAD: stand = run
			run += route[i].distance_to(route[i + 1])
		h.progress(0, maxf(stand - 0.001, 0.0))
		if h.shots != "": # the stage view tipped to 32 degrees (a player's own orbit input), looking the way the row is crossed (yaw 0 looks towards -Z, positive turns left)
			var ahead: Vector3 = route[mini(at + 2, route.size() - 1)] - route[maxi(at - 2, 0)]
			if row.size() >= 2:
				var along: Vector3 = spots[row[row.size() - 1]] - spots[row[0]]
				ahead = Vector3(along.z, 0.0, -along.x) * (1.0 if Vector3(along.z, 0.0, -along.x).dot(ahead) >= 0.0 else -1.0)
			h.replicas[h.shot_view].yaw = atan2(-ahead.x, -ahead.z)
			h.replicas[h.shot_view].pitch = deg_to_rad(float(STEEP.get("%d:%d" % [number, k + 1], -32.0)))
		await h.tick(50)
		items.held[0] = -1 # the runner holds nothing again only now, away from the boxes it has taken
		items.roll_left[0] = 0.0
		h.speed[0] = 0.15
		var before := int(h.state().items.boxes)
		h.check(row.all(func(index: int) -> bool: return (before >> index) & 1 == 1), "row %d: all its boxes are there" % [k + 1])
		h.release(0)
		if h.shots != "": # the runner walks up to the row and stops 3 m short of it for the frame (after the gate wall that stands before some rows)
			await h.wait_until(func() -> bool: return Vector2(h.sim.actors[0].position.x - centre.x, h.sim.actors[0].position.z - centre.z).length() <= 3.2 or int(items.held[0]) >= 0, 60 * 10)
			h.hold(0)
			await h.tick(25)
			h.shoot("l%d_row%d_approach" % [number, k + 1])
			await h.tick(6)
			h.release(0)
		var took: bool = await h.wait_until(func() -> bool: return int(items.held[0]) >= 0, 60 * 14)
		h.hold(0)
		var picked_at: float = items.time
		h.check(took, "row %d: the runner walking the route takes a box (it holds %s)" % [k + 1, str(items.Catalog.id_of(int(items.held[0]))) if took else "nothing"])
		var mask := int(h.state().items.boxes)
		var gone: Array = row.filter(func(index: int) -> bool: return (mask >> index) & 1 == 0)
		h.check(gone.size() == 1, "row %d: exactly the box it walked through is gone from the state's mask (%d gone)" % [k + 1, gone.size()])
		await h.tick(9)
		if not gone.is_empty():
			var seen: bool = h.views[0]._items._boxes[int(gone[0])].there
			h.check(not seen, "row %d: the client's view has hidden it" % [k + 1])
		h.shoot("l%d_row%d_pick" % [number, k + 1])
		await h.tick(6)
		if not respawn_checked and not gone.is_empty():
			# the box is back 8 s later (the runner keeps its item, so it does not take it again)
			var index: int = int(gone[0])
			var back: bool = await h.wait_until(func() -> bool: return (int(h.state().items.boxes) >> index) & 1 == 1, 60 * 10)
			var waited: float = items.time - picked_at
			h.check(back and waited >= 7.9 and waited <= 8.6, "the taken box is back %.1f s later" % waited)
			await h.tick(9)
			var seen_back: bool = h.views[0]._items._boxes[index].there if back else false
			h.check(seen_back or not back, "the client's view shows it again")
			respawn_checked = true
	items.held[0] = -1
	items.roll_left[0] = 0.0

## Metres from `point` (horizontally) to the segment a-b.
func _segment_gap(a: Vector3, b: Vector3, point: Vector3) -> float:
	var from := Vector2(a.x, a.z)
	var to := Vector2(b.x, b.z)
	var along := to - from
	var t := 0.0 if along.length_squared() < 0.000001 else clampf((Vector2(point.x, point.z) - from).dot(along) / along.length_squared(), 0.0, 1.0)
	return (from + along * t).distance_to(Vector2(point.x, point.z))
