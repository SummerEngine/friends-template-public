extends Node3D
## All levels of the game in one node (docs/level-format.md, docs/level-world-api.md). Level k (1-based) is built at world x = (k - 1) * SPACING from
## its `level_NN.json`; only the active level stands in the tree, the others are detached (not drawn, not simulated).
## Hazards are pure functions of `clock` (hazards.gd): move it with advance() / set_clock() / sync_clock() and the movers follow.
## Zones (goal, kill), launch pads, ice and lasers / fire jets on couriers are geometric tests on positions, not physics callbacks.
##   role "authority": bodies only.   any other role: bodies plus the drawn look, the environment, the void and the ink pass.
const Data := preload("res://levels/level_data.gd")
const Hazards := preload("res://levels/hazards.gd")
const EdgeBumpers := preload("res://levels/edge_bumpers.gd")
const StepTiles := preload("res://levels/step_tiles.gd")
const StageStarts := preload("res://levels/stage_starts.gd")
const EnvironmentSetup := preload("res://levels/level_environment.gd")
const Look := preload("res://style/collision_look.gd")
const Style := preload("res://style/friends_style.gd")
const Backdrop := preload("res://style/backdrop.gd")
const RaceWorld := preload("res://style/race_world.gd")
const RaceHazardLooks := preload("res://style/race_hazard_looks.gd")
const TurntableLook := preload("res://style/turntable_look.gd")
const EdgeBumperLook := preload("res://style/edge_bumper_look.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const ShotLooks := preload("res://style/shot_looks.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const CandyMaterial := preload("res://style/candy_material.gd")
const RoomNumber := preload("res://style/room_number.gd")
const PosterDoors := preload("res://levels/poster_doors.gd")
const PosterDoorLook := preload("res://style/poster_door_look.gd")
const CourseSection := preload("res://course_section.gd")
const FinishRails := preload("res://style/finish_rails.gd")
const SPACING := 300.0
const LAYER_CAMERA := 256       ## static blocks of CAMERA_BLOCK_SIZE or more also sit here: the follow camera's pull-in looks only at this layer
const CAMERA_BLOCK_SIZE := 1.5
const LAYER_SOLID := 1
const LAYER_HIT := 8
const LAYER_MOVER := 16
const LAYER_SCORCH := 32        ## lasers and fire jets while on (with LAYER_HIT): couriers walk through them, the balloon and the painting do not
const SPIKE_REACH := 0.2        ## a spiked mover's hit shape reaches this far past its parts (the spike tips)
const CENTRE_HEIGHT := 0.9      ## a courier's centre above its feet (the point the zone and launch tests use)
const COURIER_RADIUS := 0.35    ## the courier capsule (courier_motion.gd): radius and half its inner segment, for scorch_at
const COURIER_HALF_SEGMENT := 0.55
const COURIER_HEIGHT := 1.8
const SLEW_PER_SECOND := 4.0    ## how fast sync_clock closes the gap to the authority's clock (1/s)
const HARD_SNAP := 0.5          ## a gap above this many seconds is jumped, not slewed
const STAGE_REWIND_HOLD := 5.0  ## a stage round's replica never runs its clock back by less than this (a stall's burst of old snapshots: a tile that has gone must not come back); more is a new round
const ICE_REACH := 0.4          ## a courier whose feet are within this of an ice block's top is on ice
const FLOOR_PROBE := 3.0        ## floor_y looks down from this far above the given point
## The bonk (bonk_at): a courier touched by a moving hazard that hurts (`hit`) is thrown the way the hazard moves, plus a little up.
const BONK_KINDS := ["slide", "lift", "spin", "swing", "ball", "cannon"]
const BONK_REACH := 0.12         ## the courier's capsule is grown this much (m) for the contact test: touching counts
const BONK_MIN_SPEED := 0.75     ## a hazard point slower than this (m/s) only blocks, it does not throw
const BONK_APPROACH := 0.5       ## the hazard must close in on the courier by this much (m/s) along the contact normal: a wall sliding past its face does not throw it, the wall's end does
const BONK_SPEED := 8.5          ## horizontal launch speed (m/s) = BONK_SPEED + BONK_GAIN * the hazard point's speed, at most BONK_MAX
const BONK_GAIN := 1.0
const BONK_MAX := 15.0
const BONK_UP := 6.0             ## vertical launch speed (m/s); half of it under a hazard coming down on the courier
const FLING_MIN := 12.0          ## a hit from a spinner, wheel or windmill of a `world: daylight` level (a race): horizontal launch speed at least this (m/s) ...
const FLING_MAX := 16.0          ## ... at most this, so a hit on a walkway sends the courier over its edge
const FLING_UP := 6.0            ## ... and this far up (m/s)
const FLING_ALONG := 0.7         ## a throw this parallel to the course (|cos|) is turned to the side the courier stands on, off the course
const BONK_COOLDOWN := 0.4       ## s of level clock before the same courier can be bonked again
const DOOR_LEAD := 2.0 / 60.0    ## s: a gate door's nudge looks this far ahead of the clock (the body follows the clock a tick late), so a courier is out of its way before the body arrives
const DOOR_NUDGE_STEP := 0.25    ## m per tick at most: how far a closing gate door moves a courier out of its volume (a depenetration, never a launch)
const BONK_PROBE := 1.0 / 120.0  ## the hazard's velocity is its pose a probe before and after the clock
const LAUNCHER_REACH := 1.0     ## a launcher's pad / base is drawn on the block under its volume when that is at most this far under it

signal level_changed(level: int)
## Blink blocks, for sound: the index of the hazard in the level (stable per level) and the block's world position. Not emitted while a level is
## being built; the authority has no use for them.
const GATE_GONE := 12.0 ## m: the start gate, risen this far over its place at GO, is out of every view: it is not drawn any more
signal blink_warned(index: int, position: Vector3)
signal blink_vanished(index: int, position: Vector3)
## Step tiles (levels/step_tiles.gd): the tile's index in its level and the world position of its top; same rules as the blink signals.
signal tile_warned(index: int, position: Vector3)
signal tile_vanished(index: int, position: Vector3)
## Poster doors (levels/poster_doors.gd), from the courier positions `observe_doors` is fed: a courier went through an open poster (its slot's place in the
## level's `slots`, the world point of its centre, the way it went) / pressed on a solid one. For sound; the drawn look reacts by itself.
signal door_burst(index: int, position: Vector3, heading: Vector3)
signal door_bonk(index: int, position: Vector3, who: int)

var role := "authority"
var level_dir := Data.DIR       ## where the level files are (the tools point it at test data)
var clock := 0.0
var _quiet := false             ## true while poses are set without events (building, switching level)
var active_level := -1          ## 0-based index of the level in the tree, -1 none

var _levels: Array = []         ## per level: {data, root, origin, movers, launchers, inside}
var _drawn := false
var _void: MeshInstance3D
var _environment: Environment   ## the level sky and fog (clients), recoloured per level by the backdrop
var _light := {}                ## the level environment and sun (levels/level_environment.gd build): `set_stage` swaps the stage rounds' fixed daylight in and out
var _backdrops := {}            ## level index -> its backdrop (built the first time the level is shown, then kept out of the tree)
var _backdrop: Node3D           ## the backdrop in the tree

var _bonk_query: PhysicsShapeQueryParameters3D ## the courier-sized probe of bonk_at, made on first use
var _pending := 0.0            ## clock correction still to be worked off by advance()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in _levels:
			var level_root: Node = entry.root
			if is_instance_valid(level_root) and level_root.get_parent() == null: level_root.free() # the levels that are not in the tree
		for backdrop: Node in _backdrops.values():
			if is_instance_valid(backdrop) and backdrop.get_parent() == null: backdrop.free()

func level_count() -> int:
	return _levels.size()

## Builds every level. A coroutine: with a `slicer` (due() / next()) frames are handed back between levels and shapes.
func build(build_role: String, slicer = null) -> void:
	role = build_role
	_drawn = role != "authority"
	var host: Node = get_parent() if get_parent() != null and is_inside_tree() else self
	if _drawn:
		Style.ensure_globals()
		if is_inside_tree():
			_light = EnvironmentSetup.build(host)
			_environment = _light.environment
		_void = Look.void_plane(self)
		Look.edges(self)
	var total := Data.count(level_dir)
	for number in range(1, total + 1):
		var data := Data.load_level(number, level_dir)
		if data.is_empty(): continue
		var entry := {"data": data, "origin": Vector3((number - 1) * SPACING, 0.0, 0.0), "movers": [], "launchers": [], "inside": [{}, {}], "bonked": {},
			"lengths": _cumulative(data.route), "doors": PosterDoors.list(data), "door_touch": {}, "door_seen": {}, "door_felt": {}, "pad_seen": {}}
		var level_root := Node3D.new()
		level_root.name = "Level%02d" % number
		level_root.position = entry.origin
		entry.root = level_root
		if _drawn and RaceWorld.wanted(data): level_root.set_meta("daylight", true) # the look dresses the blocks in the daylight palette (style/race_surfaces.gd) and the hazards in their own (style/shot_looks.gd)
		_build_level(entry)
		_levels.append(entry)
		if _drawn:
			add_child(level_root) # the look measures global positions
			if not (data.get("stage", {}) as Dictionary).is_empty(): level_root.set_meta("stage_round", true) # the look dresses its static blocks with the block kit (style/block_kit.gd)
			var route := PackedVector3Array()
			for point: Vector3 in data.route: route.append(point + (entry.origin as Vector3))
			await Look.draw_level(level_root, route, slicer)
			HazardLooks.dress_spin_bars(level_root, number - 1) # the cast's label or model on the spin bars of its round (style/hazard_looks.gd)
			if RaceWorld.wanted(data): RaceHazardLooks.dress(level_root) # a `world: daylight` level: striped spin bars, grey ride pads with a yellow rim, ringed push pads
			_mark(entry)
			CandyMaterial.dissolve_tree(level_root) # nothing of the look hides the courier from the follow camera: pieces near the eye dissolve (style/near_dissolve.gdshaderinc)
			remove_child(level_root)
		elif slicer != null and slicer.due():
			await slicer.next()
	if _void != null: _void.visible = false
	set_active_level(0 if not _levels.is_empty() else -1)

## ---- construction ----

## Every block gets its own Shape3D: the look caches its mesh per shape instance, and a block's role (ground / hop / wall / ice) depends on where it stands.
func _add_shape(body: CollisionObject3D, block: Dictionary, local: Transform3D = Transform3D.IDENTITY) -> void:
	var node := CollisionShape3D.new()
	node.shape = Hazards.make_shape(block)
	node.transform = local * (block.xf as Transform3D)
	if block.m == "ice": node.set_meta("ice", true)
	if block.m == "belt": node.set_meta("belt", block.belt) # the look draws a conveyor lane running that way (level-local planar m/s)
	if str(block.get("slot", "")) != "": node.set_meta("slot", str(block.slot)) # an obstacle box: the look puts a cast face on it
	if bool(block.get("bump", false)): node.set_meta("bump", true) # a bumper bar of a turning floor: the look (style/turntable_look.gd) draws it apart, so it can squash on a hit
	if str(block.get("tone", "")) != "": node.set_meta("tone", str(block.tone)) # a block of a `world: daylight` level asks for a surface (style/race_surfaces.gd)
	body.add_child(node)

func _static_body(label: String, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	return body

func _build_level(entry: Dictionary) -> void:
	var data: Dictionary = entry.data
	var level_root: Node3D = entry.root
	# Four static bodies: small or big (the follow camera's pull-in sees only big blocks), solid or `hit` (the painting breaks on layer 8).
	var bodies: Dictionary = {}
	var rims: Array = [] # the rim walls of a signed finish deck: solid as ever, drawn as railings by style/finish_rails.gd (SlotFrames.build), not by the block look
	if _drawn and SlotFrames.goal_signed(data.slots): rims = FinishRails.rims(data.blocks, FinishRails.deck(data.blocks, data.goal))
	for block: Dictionary in data.blocks:
		var big := maxf(maxf(block.size.x, block.size.y), block.size.z) >= CAMERA_BLOCK_SIZE
		var stand: bool = block.slot == Hazards.HERO_SLOT # a hero prop's stand: the `hero_prop` slot draws it (SlotFrames), the block look skips it
		var rail := not rims.is_empty() and rims.has(block)
		var key := "%s%s%s" % ["Stand" if stand else ("Rail" if rail else ""), "Hit" if block.hit else "Solid", "Big" if big else "Small"]
		if not bodies.has(key):
			bodies[key] = _static_body(key, LAYER_SOLID | (LAYER_HIT if block.hit else 0) | (LAYER_CAMERA if big else 0))
			if stand or rail: bodies[key].set_meta("fx", true)
		_add_shape(bodies[key], block)
	for body: StaticBody3D in bodies.values(): level_root.add_child(body)
	var ids: Dictionary = {}
	for h: Dictionary in data.hazards: _build_hazard(entry, h, ids)
	if not (data.tiles as Dictionary).is_empty():
		var tiles := StepTiles.new()
		tiles.build(level_root, data.tiles, entry.origin, _drawn, data.stage.get("ground", {}) if not data.stage.is_empty() else {})
		tiles.warned.connect(func(index: int, at: Vector3) -> void: tile_warned.emit(index, at))
		tiles.vanished.connect(func(index: int, at: Vector3) -> void: tile_vanished.emit(index, at))
		entry.tiles = tiles
	# launch volumes that ride on a hazard are resolved once every hazard exists
	for pill_index in (data.edge_bumpers.pills as Array).size(): entry.launchers.append({"h": data.edge_bumpers.pills[pill_index], "host": -1, "area": null, "pill": pill_index}) # the experiment's edge cushions (levels/edge_bumpers.gd): launchers with no area, drawn by one look per level
	for launcher: Dictionary in entry.launchers:
		var h: Dictionary = launcher.h
		launcher.host = int(ids[h.ride]) if h.ride != "" and ids.has(h.ride) else -1
		if _drawn and h.k != "cushion": launcher.area = _launcher_area(level_root, entry, launcher)
	_quiet = true
	_pose_all(entry)
	_quiet = false

## One hazard's bodies (and, drawn, the look of a laser, fire jet or spikes). Returns the bodies whose shapes the collision look draws.
func _build_hazard(entry: Dictionary, h: Dictionary, ids: Dictionary) -> Array:
	var level_root: Node3D = entry.root
	var drawn_bodies: Array = []
	match h.k:
		"slide", "lift", "spin", "swing", "blink", "spikes":
			var body := AnimatableBody3D.new()
			body.name = "Hazard_%s_%d" % [h.k, entry.movers.size()]
			body.sync_to_physics = true
			body.collision_mask = 0
			body.collision_layer = LAYER_MOVER | (LAYER_HIT if h.hit else 0)
			body.set_meta("hazard", true)
			if h.k == "spin": body.set_meta("axis", h.axis) # the look (style/spinner_look.gd) stands a hub on it
			if h.k == "slide" or h.k == "lift": # the look (style/mover_look.gd) turns the chevrons of a platform the way it is about to go: its run is pivot + to * (0..1)
				body.set_meta("pivot", h.pivot)
				body.set_meta("travel", h.to)
			for part: Dictionary in h.parts: _add_shape(body, part)
			level_root.add_child(body)
			drawn_bodies.append(body)
			var mover := {"h": h, "body": body, "pose": Hazards.Pose.new(), "layer": body.collision_layer, "active": true, "warned": false,
				"bonk": h.hit and h.k in BONK_KINDS, "fling": h.k == "spin" and RaceWorld.wanted(entry.data), "door": _is_gate_door(h), "bars": _bump_bars(h)}
			if h.look == "spikes":
				# A spike crusher: its spike tips are a hit-only shell around the parts (pops, breaks; couriers are pushed by the parts).
				var shell := _scorcher_body(body.name + "Spikes", LAYER_HIT)
				for part: Dictionary in h.parts:
					var grown := part.duplicate()
					grown.size = (part.size as Vector3) + Vector3.ONE * SPIKE_REACH * 2.0
					grown.d = float(part.d) + SPIKE_REACH * 2.0
					grown.h = float(part.h) + SPIKE_REACH * 2.0
					grown.slot = ""
					_add_shape(shell, grown)
				level_root.add_child(shell)
				mover.shell = shell
				if _drawn: HazardLooks.spikes(body, h.parts)
			if h.id != "": ids[h.id] = entry.movers.size()
			entry.movers.append(mover)
		"ball", "cannon":
			var shot := AnimatableBody3D.new()
			shot.name = "Hazard_%s_%d" % [h.k, entry.movers.size()]
			shot.sync_to_physics = true
			shot.collision_mask = 0
			shot.collision_layer = LAYER_MOVER | LAYER_HIT
			shot.set_meta("hazard", true)
			var sphere := SphereShape3D.new()
			sphere.radius = h.rad
			var node := CollisionShape3D.new()
			node.shape = sphere
			shot.add_child(node)
			level_root.add_child(shot)
			drawn_bodies.append(shot)
			var shot_mover := {"h": h, "body": shot, "pose": Hazards.Pose.new(), "layer": shot.collision_layer, "active": true, "warned": false, "bonk": true}
			Hazards.build_life(h, entry.data.blocks) # where it comes from and where it goes (hazards.gd): nothing pops in or out in view
			if _drawn: shot_mover.shot = ShotLooks.build(level_root, h, entry.data.blocks, shot, int(entry.data.number) - 1) # the ball's own look is a child of its body
			entry.movers.append(shot_mover)
			if h.k == "cannon" and not h.parts.is_empty():
				var barrel := _static_body("CannonBarrel", LAYER_SOLID)
				barrel.transform = Transform3D(h.base, h.pivot)
				for part: Dictionary in h.parts: _add_shape(barrel, part)
				level_root.add_child(barrel)
				drawn_bodies.append(barrel)
		"laser", "fire":
			# No collision for couriers (scorch_at tests them); the balloon and the painting meet the shape on LAYER_HIT.
			var body := _scorcher_body("Hazard_%s_%d" % [h.k, entry.movers.size()], LAYER_HIT | LAYER_SCORCH)
			var node := CollisionShape3D.new()
			if h.k == "laser":
				var length := maxf((h.to as Vector3).length(), 0.01)
				var cylinder := CylinderShape3D.new()
				cylinder.radius = Hazards.BEAM_RADIUS
				cylinder.height = length
				node.shape = cylinder
				node.transform = Transform3D(HazardLooks.along((h.to as Vector3) / length), (h.to as Vector3) * 0.5)
			elif h.g == "cyl":
				var jet := CylinderShape3D.new()
				jet.radius = h.size.x * 0.5
				jet.height = h.size.y
				node.shape = jet
			else:
				var box := BoxShape3D.new()
				box.size = h.size
				node.shape = box
			body.add_child(node)
			level_root.add_child(body)
			var scorcher := {"h": h, "body": body, "pose": Hazards.Pose.new(), "layer": body.collision_layer, "active": true, "warned": false}
			if _drawn: scorcher.look = HazardLooks.laser(body, h.to) if h.k == "laser" else HazardLooks.fire(body, h.g, h.size)
			if h.id != "": ids[h.id] = entry.movers.size()
			entry.movers.append(scorcher)
		"push", "bumper":
			entry.launchers.append({"h": h, "host": -2, "area": null})
	return drawn_bodies

## A body the collision look leaves alone (it has a look of its own, or none): lasers, fire jets, spike shells.
func _scorcher_body(label: String, layer: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = label
	body.sync_to_physics = true
	body.collision_mask = 0
	body.collision_layer = layer
	body.set_meta("fx", true)
	return body

## Tools: a hazard (a level file's hazard dictionary) added to level `k` after the build, posed at the current clock. Push pads and
## bumpers cannot ride on it. Returns its index among the level's movers, -1 when the kind is unknown.
func add_hazard(k: int, source: Dictionary) -> int:
	var entry := _entry(k)
	var h := Hazards.normalize(source)
	if entry.is_empty() or h.is_empty() or h.k in Hazards.VOLUMES: return -1
	entry.data.hazards.append(h)
	var bodies := _build_hazard(entry, h, {})
	if _drawn:
		var shapes: Array = []
		for body: Node in bodies:
			for child: Node in body.get_children():
				if child is CollisionShape3D: shapes.append(child)
		Look.draw_shapes(shapes, true)
	_quiet = true
	_pose_all(entry)
	_quiet = false
	return entry.movers.size() - 1

## The look of a launcher (a pad or a bumper), a child of a non-colliding Area3D at its volume (the test itself is geometric). It is drawn the way
## a person would build it, not as the volume: a pad lies on the floor under the volume, a bumper stands on a base (style/hazard_looks.gd).
func _launcher_area(level_root: Node3D, entry: Dictionary, launcher: Dictionary) -> Area3D:
	var h: Dictionary = launcher.h
	var area := Area3D.new()
	area.name = "Launcher_%s" % h.k
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta("fx", true) # the collision look leaves it alone: HazardLooks.launcher draws it
	area.transform = Transform3D(h.base, h.pivot)
	if launcher.host >= 0: (entry.movers[launcher.host].body as Node3D).add_child(area)
	else: level_root.add_child(area)
	HazardLooks.launcher(area, h, -1.0 if launcher.host >= 0 else _launcher_drop(entry, h))
	return area

## How far the centre of a launcher's volume is over the static block under it (m); -1 when the volume's underside is more than LAUNCHER_REACH
## over the nearest block top, or inside a block (then its look stays where the volume is).
func _launcher_drop(entry: Dictionary, h: Dictionary) -> float:
	var half := float(h.rad) if h.k == "bumper" else float(h.size.y) * 0.5
	var from: Vector3 = (h.pivot as Vector3) + Vector3.UP * half
	var best := INF
	for block: Dictionary in entry.data.blocks: best = minf(best, Hazards.ray_hit(block, from, Vector3.DOWN))
	return best - half if best > 0.0 and best - 2.0 * half <= LAUNCHER_REACH else -1.0

## START and GOAL pads, rings, flags and words (not on a show survival level: its floor falls away, so no pad may float where it was;
## no GOAL marks on a level whose goal is a hero prop, docs/hero-prop.md), the frames of the level's slots that the team cast fills (signs, posters, ...), and a balloon room's number on its wall.
func _mark(entry: Dictionary) -> void:
	var data: Dictionary = entry.data
	var origin: Vector3 = entry.origin
	var goal: Dictionary = data.goal
	var floor_point: Vector3 = goal.p - Vector3(0.0, (goal.size as Vector3).y * 0.5, 0.0)
	var lateral := Vector3.RIGHT.rotated(Vector3.UP, data.start_yaw)
	var stand := false # a hero prop stands over the goal: the prop is the goal's mark, no pad, word, flag or logo card
	for slot: Dictionary in data.slots:
		if slot.id == Hazards.HERO_SLOT: stand = true
	var signed := str(data.show) != "survival" and SlotFrames.goal_signed(data.slots) # the finish arch is the GOAL sign over the deck (style/goal_sign.gd): it says GOAL
	if str(data.show) != "survival": Look.mark_level(entry.root, origin + data.start, origin + floor_point, lateral, not stand, INF if signed else SlotFrames.goal_arch_under(data.slots, floor_point), not signed)
	var finish := {}
	if signed:
		var words := CourseSection.level_title(int(data.number) - 1) # the sign's subtitle: the round's title, the level's own words
		finish = {"title": words if words != "" else str(data.title), "goal": goal, "route": data.route}
	SlotFrames.build(entry.root, data.slots, data.blocks, finish)
	if _drawn and not (data.edge_bumpers.pills as Array).is_empty(): entry.cushions = EdgeBumperLook.build(entry.root, data.edge_bumpers) # the experiment's cushions: one node, pulsed by a touch
	if not (entry.doors as Array).is_empty(): entry.door_look = PosterDoorLook.build(entry.root, entry.doors, data.slots)
	RoomNumber.build(entry.root, data, level_dir)

## ---- activation and clock ----

## Puts level `k` (0-based) in the tree and takes the previous one out. Resets the launch memory.
func set_active_level(k: int) -> void:
	if k == active_level and (k < 0 or _levels[k].root.is_inside_tree()): return
	if active_level >= 0 and active_level < _levels.size() and _levels[active_level].root.get_parent() == self:
		remove_child(_levels[active_level].root)
	_hide_backdrop()
	active_level = k if k >= 0 and k < _levels.size() else -1
	EnvironmentSetup.set_stage(_light, active_level < 0 or _daylight(_levels[active_level].data)) # the lobby yard (no level: lobby/lobby_kit.gd), a stage round and a `world: daylight` level have the daylight
	if active_level >= 0:
		var entry: Dictionary = _levels[active_level]
		for memory: Dictionary in entry.inside: memory.clear()
		(entry.bonked as Dictionary).clear()
		_forget_doors(entry)
		_quiet = true
		_pose_all(entry)
		_quiet = false
		add_child(entry.root)
		if _void != null:
			_void.visible = not Backdrop.enabled   # the backdrop is the world below; the flat void is only its fallback
			_void.position = Vector3(entry.origin.x, Look.WATER_Y, 0.0)
		if _drawn and Backdrop.enabled: _show_backdrop(active_level)
	elif _void != null:
		_void.visible = false
	level_changed.emit(active_level)

## The world around and far below level `k`, built the first time the level is shown: the arena world of a stage round (style/backdrop.gd), the open-air race world of a
## `world: daylight` level (style/race_world.gd), else the cast's own (style/backdrop.gd).
func _show_backdrop(k: int) -> void:
	if not _backdrops.has(k):
		var entry: Dictionary = _levels[k]
		_backdrops[k] = RaceWorld.build(entry.data, entry.origin) if (entry.data.get("stage", {}) as Dictionary).is_empty() and RaceWorld.wanted(entry.data) else Backdrop.for_level(int(entry.data.number), entry.data, entry.origin)
	_backdrop = _backdrops[k]
	if not _daylight(_levels[k].data): Backdrop.apply_sky(_environment, int(_levels[k].data.number))
	add_child(_backdrop)

## Whether the level `data` has the stage rounds' daylight: a stage round (its own world, style/arena_world.gd) or a level that asks for `world: daylight`.
func _daylight(data: Dictionary) -> bool:
	return not (data.get("stage", {}) as Dictionary).is_empty() or RaceWorld.wanted(data)

func _hide_backdrop() -> void:
	if _backdrop != null and _backdrop.get_parent() == self: remove_child(_backdrop)
	_backdrop = null

func set_clock(t: float) -> void:
	clock = t
	_pending = 0.0
	_quiet = true
	_pose_active()
	_quiet = false

## One physics tick. A pending correction (correct_clock) is worked off smoothly on the way; a clock never runs backwards (a negative correction larger than the tick only stops it).
func advance(dt: float) -> void:
	var share := _pending * minf(dt * SLEW_PER_SECOND, 1.0)
	_pending -= share
	clock += maxf(dt + share, 0.0)
	_pose_active()

## A replica got the authority's clock `authority_t` (once per snapshot): the gap is closed over the next ticks of advance(); a gap above
## HARD_SNAP is jumped, except that a stage round's clock is not run back by up to STAGE_REWIND_HOLD s (the gap is slewed: the clock waits).
func correct_clock(authority_t: float) -> void:
	var gap := authority_t - clock
	if absf(gap) > HARD_SNAP and not _holds_back(gap):
		clock = authority_t
		_pending = 0.0
		_pose_active()
	else:
		_pending = gap

## One physics tick of a replica: advance by dt and close the gap to the authority's `authority_t` smoothly; a gap above HARD_SNAP is jumped (see correct_clock).
func sync_clock(authority_t: float, dt: float) -> void:
	var gap := authority_t - (clock + dt)
	if absf(gap) > HARD_SNAP and not _holds_back(gap): clock = authority_t
	else: clock += maxf(dt + gap * minf(dt * SLEW_PER_SECOND, 1.0), 0.0)
	_pose_active()

## True for a backwards gap (the authority's clock is behind ours) that a stage round's replica waits out instead of jumping back over.
func _holds_back(gap: float) -> bool:
	if gap > 0.0 or gap < -STAGE_REWIND_HOLD or active_level < 0: return false
	return not (_levels[active_level].data.get("stage", {}) as Dictionary).is_empty()

func _pose_active() -> void:
	if active_level >= 0: _pose_all(_levels[active_level])

func _pose_all(entry: Dictionary) -> void:
	var origin: Vector3 = entry.origin
	if entry.has("tiles"): (entry.tiles as StepTiles).pose(clock, _quiet)
	var door_look: Variant = entry.get("door_look")
	if door_look != null: door_look.follow(clock) # the poster doors that ride a slide move with it
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		var pose: Hazards.Pose = mover.pose
		Hazards.pose(mover.h, clock, pose)
		var body: AnimatableBody3D = mover.body
		body.transform = Transform3D(pose.basis, pose.position)
		if mover.has("shell"): (mover.shell as Node3D).transform = body.transform
		if mover.has("look"): HazardLooks.pose(mover.look, pose.active, pose.shake, clock)
		if mover.has("shot"): ShotLooks.pose(mover.shot, mover.h, clock)
		var shown: bool = pose.active or pose.lead # a ball or shot inside its housing, a blink block that has fallen away: drawn, harmless (collision off). Nothing pops out of view
		if shown and not pose.active and str(mover.h.get("slot", "")) == Hazards.GATE_SLOT and pose.position.y > (mover.h.pivot as Vector3).y + GATE_GONE: shown = false # the start gate has gone up and out of the picture
		if shown != bool(mover.get("shown", true)):
			mover.shown = shown
			if not mover.has("look"): body.visible = shown # a laser or fire jet draws its own off and warning states
		if pose.active != mover.active:
			mover.active = pose.active
			body.collision_layer = int(mover.layer) if pose.active else 0
			if not pose.active and mover.h.k == "blink" and not _quiet: blink_vanished.emit(index, origin + pose.position)
		if mover.h.k == "blink":
			var warning := pose.active and pose.shake > 0.0
			if warning and not mover.warned and not _quiet: blink_warned.emit(index, origin + pose.position)
			mover.warned = warning

## ---- step tiles (levels/step_tiles.gd; `k` is the 0-based level) ----

## How many step tiles level `k` has (0 for none).
func tile_count(k: int) -> int:
	var entry := _entry(k)
	return (entry.tiles as StepTiles).tile_count() if entry.has("tiles") else 0

## The steps a round of `players` starts with (one byte per tile, outer tiles gone when few play); empty for a level without tiles.
func tile_start(k: int, players: int) -> PackedByteArray:
	var entry := _entry(k)
	return StepTiles.start_steps(entry.data.tiles, players) if entry.has("tiles") else PackedByteArray()

## Sets the tiles' state of level `k` (one byte per tile, the rules' `tiles`); a list of another size is ignored. `quiet`: no sounds
## for what the state has already done (a client's first state).
func set_tile_steps(k: int, steps: PackedByteArray, quiet := false) -> void:
	var entry := _entry(k)
	if entry.has("tiles"): (entry.tiles as StepTiles).set_steps(steps, clock, quiet)

## The step byte a step of level `k` writes now (levels/step_tiles.gd stamp_at: rounded to the level's unit, wrapped on a wrapped level); 0 for a level without tiles.
func tile_stamp(k: int) -> int:
	var entry := _entry(k)
	return StepTiles.stamp_at(entry.data.tiles, clock) if entry.has("tiles") else 0

## True when tile `index` of level `k` has been gone so long that the authority may write SETTLED into its byte (a wrapped level only: its bytes are a clock modulo a window).
func tile_settled(k: int, index: int) -> bool:
	var entry := _entry(k)
	return entry.has("tiles") and bool(entry.data.tiles.wrap) and (entry.tiles as StepTiles).is_settled(index, clock)

## True once tile `index` of level `k` has no collision (as last posed).
func tile_gone(k: int, index: int) -> bool:
	var entry := _entry(k)
	return entry.has("tiles") and (entry.tiles as StepTiles).is_gone(index)

## The tiles of level `k` a courier standing at `feet` (world) is on now (indices; gone ones do not count).
func tiles_under(k: int, feet: Vector3) -> Array:
	var entry := _entry(k)
	if not entry.has("tiles"): return []
	return (entry.tiles as StepTiles).tiles_under(feet - (entry.origin as Vector3), clock)

## The tops (world heights) of the tile floors of level `k`, top floor first, when it is a stage round (one-way floors: courier/courier_motion.gd set_floors); empty otherwise.
func tile_floors(k: int) -> PackedFloat32Array:
	var entry := _entry(k)
	var tops := PackedFloat32Array()
	if not entry.has("tiles") or str(entry.data.tiles.style) != "stage": return tops
	for layout: Dictionary in entry.data.tiles.floors: tops.append(float(layout.y) + (entry.origin as Vector3).y)
	return tops

## The view's height for level `k`'s step tiles (client look only): a camera at world height `camera_y` following feet at `feet_y` does not see the floors over it
## (StepTiles.ghost_floors). INF as the camera height draws every floor (a fixed shot, first person). `dt` (s, the frame's time): a stage round's floors fade out and in
## over a fraction of a second; INF (the default) hides and shows them at once (a fixed shot, a check).
func ghost_tiles(k: int, camera_y: float, feet_y: float, dt := INF) -> void:
	var entry := _entry(k)
	if entry.has("tiles"): (entry.tiles as StepTiles).ghost_view(camera_y - (entry.origin as Vector3).y, feet_y - (entry.origin as Vector3).y, dt)

## ---- queries (world coordinates; `k` is the 0-based level) ----

func _entry(k: int) -> Dictionary:
	return _levels[k] if k >= 0 and k < _levels.size() else {}

func level_origin(k: int) -> Vector3:
	var entry := _entry(k)
	return entry.get("origin", Vector3.ZERO)

## 0-based level whose region holds world x.
func level_at(x: float) -> int:
	return clampi(roundi(x / SPACING), 0, maxi(_levels.size() - 1, 0))

func title(k: int) -> String:
	var entry := _entry(k)
	return str(entry.data.title) if not entry.is_empty() else ""

func blurb(k: int) -> String:
	var entry := _entry(k)
	return str(entry.data.blurb) if not entry.is_empty() else ""

## Where the two couriers start: {a, b (world, feet), yaw (radians, 0 faces -Z; the courier's own yaw convention)}.
func start_pose(k: int) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty(): return {"a": Vector3.ZERO, "b": Vector3.ZERO, "yaw": 0.0}
	var data: Dictionary = entry.data
	var right := Vector3.RIGHT.rotated(Vector3.UP, data.start_yaw)
	var at: Vector3 = entry.origin + data.start
	return {"a": at - right * Data.START_HALF_GAP, "b": at + right * Data.START_HALF_GAP, "yaw": data.start_yaw}

## The goal box: {p (world centre), size, yaw (radians), floor (world point on the floor under the centre)}.
func goal_volume(k: int) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty(): return {}
	var goal: Dictionary = entry.data.goal
	var centre: Vector3 = entry.origin + goal.p
	return {"p": centre, "size": goal.size, "yaw": goal.yaw, "floor": centre - Vector3(0.0, (goal.size as Vector3).y * 0.5, 0.0)}

## The path of the level in world coordinates (about every 4 to 6 m).
func route(k: int) -> PackedVector3Array:
	var entry := _entry(k)
	var result := PackedVector3Array()
	if entry.is_empty(): return result
	for point: Vector3 in entry.data.path: result.append(point + (entry.origin as Vector3))
	return result

## "goal" | "kill" | "" for a courier standing at `feet` (world). Kill: inside a kill volume or below the level's void height.
func zone_at(k: int, feet: Vector3) -> String:
	return point_zone(k, feet + Vector3(0.0, CENTRE_HEIGHT, 0.0))

## The same test for a point itself (the centre of the floating thing).
func point_zone(k: int, point: Vector3) -> String:
	var entry := _entry(k)
	if entry.is_empty(): return ""
	var data: Dictionary = entry.data
	var local: Vector3 = point - (entry.origin as Vector3)
	if local.y < float(data.void_y): return "kill"
	for volume: Dictionary in data.kill:
		if Data.inside(volume, local): return "kill"
	if Data.inside(data.goal_volume, local): return "goal"
	return ""

## The round modes level `k` may be played in ("carry", "balloon", "show").
func modes(k: int) -> Array:
	var entry := _entry(k)
	return entry.data.modes if not entry.is_empty() else ["carry"]

## The level's checkpoint volumes in path order (LevelData volumes, level-local). The live list: tools may add to it.
func checkpoints(k: int) -> Array:
	var entry := _entry(k)
	return entry.data.checkpoints if not entry.is_empty() else []

## The item boxes of level `k` (docs/items.md): world feet spots on the floor, [] for none.
func item_boxes(k: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	var entry := _entry(k)
	if entry.is_empty(): return result
	for box: Dictionary in (entry.data.get("item_boxes", []) as Array): result.append((box.p as Vector3) + (entry.origin as Vector3))
	return result

## Index of the checkpoint holding `point` (world), -1 for none.
func checkpoint_at(k: int, point: Vector3) -> int:
	var entry := _entry(k)
	if entry.is_empty(): return -1
	var local: Vector3 = point - (entry.origin as Vector3)
	var list: Array = entry.data.checkpoints
	for index in list.size():
		if Data.inside(list[index], local): return index
	return -1

## Where a team of `count` restarts on level `k`: at checkpoint `checkpoint` (-1 = the start pad). {pos: Array of feet
## positions (world) on a ring around the spot, yaw: facing (the start's; at a checkpoint along the course), spot: the spot on the floor (world)}.
func team_start(k: int, count: int, checkpoint := -1) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty(): return {"pos": [], "yaw": 0.0, "spot": Vector3.ZERO}
	var data: Dictionary = entry.data
	var origin: Vector3 = entry.origin
	var spot: Vector3 = origin + data.start
	var list: Array = data.checkpoints
	var yaw: float = data.start_yaw
	if checkpoint >= 0 and checkpoint < list.size():
		spot = checkpoint_spot(k, checkpoint)
		yaw = _course_yaw(data, spot - origin, yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var back := Vector3.BACK.rotated(Vector3.UP, yaw)
	var pads: Array = (data.stage.get("starts", []) as Array) if not data.stage.is_empty() and checkpoint < 0 else []
	if not pads.is_empty(): # a stage round: each player on a pad of its own, spread over the block when few play (levels/stage_starts.gd)
		var stood := []
		for at: Vector3 in StageStarts.pick(pads, count): stood.append(origin + at)
		return {"pos": stood, "yaw": yaw, "spot": spot}
	var points := []
	for index in count:
		# Two players stand where the carry start puts them (left and right); more stand on a ring around the spot.
		var angle := PI + TAU * index / maxf(count, 1.0)
		var at := spot + (right * cos(angle) + back * sin(angle)) * Data.START_HALF_GAP
		var ground := floor_y(k, at)
		if not is_nan(ground) and absf(ground - spot.y) < 1.5: at.y = ground
		else: at.y = spot.y
		points.append(at)
	return {"pos": points, "yaw": yaw, "spot": spot}

## The facing (courier yaw) a team has when it is put back at `point` (world): that of the start or of the checkpoint nearest to it (team_start's yaw),
## `fallback` when the level is unknown.
func facing_at(k: int, point: Vector3, fallback := 0.0) -> float:
	var entry := _entry(k)
	if entry.is_empty(): return fallback
	var best := -1
	var near: float = point.distance_to(entry.origin + entry.data.start)
	for index in (entry.data.checkpoints as Array).size():
		var gap := point.distance_to(checkpoint_spot(k, index))
		if gap < near:
			near = gap
			best = index
	return float(team_start(k, 1, best).yaw)

## The floor under checkpoint `index` (world), like team_start's spot; the start spot when the index is out of range.
func checkpoint_spot(k: int, index: int) -> Vector3:
	var entry := _entry(k)
	if entry.is_empty(): return Vector3.ZERO
	var origin: Vector3 = entry.origin
	var list: Array = entry.data.checkpoints
	if index < 0 or index >= list.size(): return origin + entry.data.start
	var box: Dictionary = list[index]
	var spot: Vector3 = origin + (box.xf as Transform3D).origin - Vector3(0.0, (box.half as Vector3).y, 0.0)
	var ground := floor_y(k, spot)
	if not is_nan(ground): spot.y = ground
	return spot

## The show round level `k` serves: "race" | "survival" | "final" | "" (not a show level).
func show_kind(k: int) -> String:
	var entry := _entry(k)
	return str(entry.data.show) if not entry.is_empty() else ""

## The feet spots (world, Vector3 each) of 1st, 2nd and 3rd place; fewer (or none) when the level lists fewer.
func podium_spots(k: int) -> Array:
	var entry := _entry(k)
	var result: Array = []
	if entry.is_empty(): return result
	for point: Vector3 in entry.data.podium: result.append((entry.origin as Vector3) + point)
	return result

## Metres along the level's route (the densified path) to the point nearest to `feet` (world): 0 at the start, route_length(k) at the goal.
func route_progress(k: int, feet: Vector3) -> float:
	var entry := _entry(k)
	if entry.is_empty(): return 0.0
	var route: PackedVector3Array = entry.data.route
	var lengths: PackedFloat64Array = entry.lengths
	if route.size() < 2: return 0.0
	var local: Vector3 = feet - (entry.origin as Vector3)
	var best := INF
	var progress := 0.0
	for index in range(1, route.size()):
		var near := Geometry3D.get_closest_point_to_segment(local, route[index - 1], route[index])
		var gap := local.distance_squared_to(near)
		if gap < best:
			best = gap
			progress = lengths[index - 1] + route[index - 1].distance_to(near)
	return progress

## Total length of the level's route in metres.
func route_length(k: int) -> float:
	var entry := _entry(k)
	if entry.is_empty(): return 0.0
	var lengths: PackedFloat64Array = entry.lengths
	return lengths[lengths.size() - 1] if not lengths.is_empty() else 0.0

## Running length at each point of `route` (0 at the first).
static func _cumulative(route: PackedVector3Array) -> PackedFloat64Array:
	var lengths := PackedFloat64Array()
	var total := 0.0
	for index in route.size():
		if index > 0: total += route[index].distance_to(route[index - 1])
		lengths.append(total)
	return lengths

## The facing (courier yaw: 0 faces -Z) along the course from a level-local point: towards the first path point at least FACE_AHEAD metres of
## path past the point of the path nearest to it (a checkpoint that stands to the side of a winding path then looks along it, not across it),
## or the goal when no point follows. `fallback` when there is no direction.
const FACE_AHEAD := 4.0
static func _course_yaw(data: Dictionary, at: Vector3, fallback: float) -> float:
	var path: PackedVector3Array = data.path
	var nearest := INF
	var next := path.size()
	var walked := 0.0 ## path metres from the nearest point to path[next]
	for index in range(1, path.size()):
		var near := Geometry3D.get_closest_point_to_segment(at, path[index - 1], path[index])
		var gap := at.distance_to(near)
		if gap < nearest:
			nearest = gap
			next = index
			walked = near.distance_to(path[index])
	var target: Vector3 = data.goal.p
	for index in range(next, path.size()):
		if index > next: walked += path[index - 1].distance_to(path[index])
		if walked >= FACE_AHEAD and Vector2(path[index].x - at.x, path[index].z - at.z).length() > 1.0:
			target = path[index]
			break
	var toward := Vector2(target.x - at.x, target.z - at.z)
	return atan2(-toward.x, -toward.y) if toward.length() > 0.01 else fallback

## "zap" (a laser) or "burn" (a fire jet) when a courier standing at `feet` (world) touches one that is on in level `k`, else "".
## Geometric, on the current poses: the same answer on every role without a physics step.
func scorch_at(k: int, feet: Vector3) -> String:
	var entry := _entry(k)
	if entry.is_empty(): return ""
	var origin: Vector3 = entry.origin
	var low: Vector3 = feet - origin + Vector3(0.0, CENTRE_HEIGHT - COURIER_HALF_SEGMENT, 0.0)
	var high: Vector3 = feet - origin + Vector3(0.0, CENTRE_HEIGHT + COURIER_HALF_SEGMENT, 0.0)
	for mover: Dictionary in entry.movers:
		var h: Dictionary = mover.h
		if not h.k in Hazards.SCORCHERS or not (mover.pose as Hazards.Pose).active: continue
		var frame := Transform3D((mover.pose as Hazards.Pose).basis, (mover.pose as Hazards.Pose).position)
		var touched := false
		if h.k == "laser":
			var near := Geometry3D.get_closest_points_between_segments(frame.origin, frame * (h.to as Vector3), low, high)
			touched = near[0].distance_to(near[1]) <= Hazards.BEAM_RADIUS + COURIER_RADIUS
		else:
			var inverse := frame.affine_inverse()
			var half: Vector3 = (h.size as Vector3) * 0.5 + Vector3.ONE * COURIER_RADIUS
			for step in 3:
				var point: Vector3 = inverse * low.lerp(high, step * 0.5)
				if h.g == "cyl": touched = touched or (absf(point.y) <= half.y and Vector2(point.x, point.z).length() <= half.x)
				else: touched = touched or (absf(point.x) <= half.x and absf(point.y) <= half.y and absf(point.z) <= half.z)
		if touched: return Hazards.SCORCH[h.k]
	return ""

## Highest static surface under `feet` (world), looking down from FLOOR_PROBE above it (so a block high overhead does not count): its world y,
## NAN when there is none. Movers are not counted.
func floor_y(k: int, feet: Vector3) -> float:
	var entry := _entry(k)
	if entry.is_empty(): return NAN
	var local: Vector3 = feet - (entry.origin as Vector3)
	var from := local + Vector3(0.0, FLOOR_PROBE, 0.0)
	var best := INF
	for block: Dictionary in entry.data.blocks:
		best = minf(best, Hazards.ray_hit(block, from, Vector3.DOWN))
	return from.y - best + entry.origin.y if best != INF else NAN

## The ground under a courier's feet: {"ice": true} on an ice block (CourierMotion.set_surface), {"slime": Vector2} on a slime wedge (the slope's downhill, `m` "slime"), {"belt": Vector2} on a conveyor block (level-local planar m/s,
## the world's too: levels are not rotated; CourierMotion.set_belt), both on an ice block under a belt, {} on normal ground. A pure function of `feet`.
func surface_at(k: int, feet: Vector3) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty(): return {}
	var ice: Array = entry.data.ice
	var belts: Array = entry.data.belts
	var slimes: Array = entry.data.slimes
	if ice.is_empty() and belts.is_empty() and slimes.is_empty(): return {}
	var from: Vector3 = feet - (entry.origin as Vector3) + Vector3(0.0, ICE_REACH, 0.0)
	var result := {}
	for block: Dictionary in ice:
		if Hazards.ray_hit(block, from, Vector3.DOWN) <= ICE_REACH * 2.0:
			result.ice = true
			break
	for block: Dictionary in slimes:
		if Hazards.ray_hit(block, from, Vector3.DOWN) <= ICE_REACH * 2.0:
			result.slime = block.slime # the slope's downhill, a unit planar vector (CourierMotion.SLIME)
			break
	for block: Dictionary in belts:
		if Hazards.ray_hit(block.carry, from, Vector3.DOWN) <= ICE_REACH * 2.0:
			result.belt = block.belt
			break
	return result

func reset_effects() -> void:
	for entry: Dictionary in _levels:
		for memory: Dictionary in entry.inside: memory.clear()
		(entry.bonked as Dictionary).clear()
		(entry.pad_seen as Dictionary).clear()
		_forget_doors(entry)

## The launch (push pad, bumper) the courier `who` (its slot) gets by being at `feet` (world) now: {"v": Vector3, "override_xy": bool,
## "override_z": bool, "id": int} on the tick it ENTERS a volume, {} otherwise. Feed it every physics tick of the owner's simulation. A pad it sets off is
## pressed in the look (style/pad_look.gd) on the same tick.
func effects_at(k: int, who: int, feet: Vector3) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty() or entry.launchers.is_empty(): return {}
	var local: Vector3 = feet - (entry.origin as Vector3) + Vector3(0.0, CENTRE_HEIGHT, 0.0)
	while entry.inside.size() <= who: entry.inside.append({})
	var memory: Dictionary = entry.inside[maxi(who, 0)]
	var result := {}
	for index in entry.launchers.size():
		var launcher: Dictionary = entry.launchers[index]
		var h: Dictionary = launcher.h
		var inside := _launcher_holds(entry, launcher, local)
		if inside and not memory.has(index) and result.is_empty():
			result = EdgeBumpers.launch(h) if h.k == "cushion" else Hazards.launch(h, local, _launcher_frame(entry, launcher).origin)
			result.id = index
			result.kind = str(h.k)
			if h.k == "cushion": result.at = feet + Vector3(0.0, CENTRE_HEIGHT, 0.0) # where the bump sounds
			_press_pad(entry, launcher)
		if inside: memory[index] = true
		else: memory.erase(index)
	return result

## Where a launcher's volume is now (level-local): its own frame, carried by the hazard it rides.
func _launcher_frame(entry: Dictionary, launcher: Dictionary) -> Transform3D:
	var h: Dictionary = launcher.h
	var frame := Transform3D(h.base, h.pivot)
	if launcher.host >= 0:
		var pose: Hazards.Pose = entry.movers[launcher.host].pose
		frame = Transform3D(pose.basis, pose.position) * frame
	return frame

## Whether the courier centre `local` (level-local) is in the launcher's volume (a bumper: touches the ball).
func _launcher_holds(entry: Dictionary, launcher: Dictionary, local: Vector3) -> bool:
	var h: Dictionary = launcher.h
	var frame := _launcher_frame(entry, launcher)
	if h.k == "bumper": return _bumper_touched(h, local, frame.origin)
	if h.k == "cushion": return EdgeBumpers.touched(h, local)
	var point := frame.affine_inverse() * local
	if h.g == "cyl": return absf(point.y) <= h.size.y * 0.5 and Vector2(point.x, point.z).length() <= h.size.x * 0.5
	return absf(point.x) <= h.size.x * 0.5 and absf(point.y) <= h.size.y * 0.5 and absf(point.z) <= h.size.z * 0.5

## The look of a push pad plays its press (style/pad_look.gd), an edge cushion squeezes (style/edge_bumper_look.gd); nothing on a machine that draws nothing, nothing for a bumper.
func _press_pad(entry: Dictionary, launcher: Dictionary) -> void:
	if launcher.h.k == "cushion":
		var look: Variant = entry.get("cushions")
		if look != null and is_instance_valid(look): look.pulse(int(launcher.pill))
		return
	var area: Variant = launcher.get("area")
	if not area is Area3D or not is_instance_valid(area): return
	var pad := (area as Area3D).get_node_or_null("LaunchPad")
	if pad != null and pad.has_method("press"): pad.call("press")

## Feed every rendered frame with every courier's feet (world), for the couriers this machine only SEES (the others' poses relay, nobody simulates them here): a
## courier that enters a push pad's volume presses its button, from the same test as `effects_at` and the positions each machine already has. A courier this
## machine simulates presses it from `effects_at` already; the pad ignores the second call. Look only: it launches nobody.
func observe_pads(k: int, who: int, feet: Vector3) -> void:
	var entry := _entry(k)
	if entry.is_empty() or entry.launchers.is_empty() or not _drawn: return
	var local: Vector3 = feet - (entry.origin as Vector3) + Vector3(0.0, CENTRE_HEIGHT, 0.0)
	var seen: Dictionary = entry.pad_seen
	var memory: Dictionary = seen.get(who, {})
	seen[who] = memory
	for index in entry.launchers.size():
		var launcher: Dictionary = entry.launchers[index]
		if not launcher.h.k in ["push", "cushion"]: continue
		if _launcher_holds(entry, launcher, local):
			if not memory.has(index): _press_pad(entry, launcher)
			memory[index] = true
		else: memory.erase(index)

## A bumper is bumped by what is drawn, not by a point inside it: true when the courier's capsule (its centre `local`, COURIER_HALF_SEGMENT up and down
## the vertical, COURIER_RADIUS round it) reaches the outer surface of the ball (`rad`) and its band (Hazards.BUMPER_BAND) round `centre` (level-local).
## A courier therefore never stands inside the ball it sees: it is thrown the moment its body touches it (one tick of walking or dashing, 0.2 m at most).
func _bumper_touched(h: Dictionary, local: Vector3, centre: Vector3) -> bool:
	var nearest := Vector3(local.x, local.y + clampf(centre.y - local.y, -COURIER_HALF_SEGMENT, COURIER_HALF_SEGMENT), local.z)
	return nearest.distance_to(centre) <= float(h.rad) + Hazards.BUMPER_BAND + COURIER_RADIUS

## Everything the level does to a courier at this tick of its simulation: ice and belt (CourierMotion.set_surface, set_belt) and ONE launch ({v, override_xy,
## override_z, id, kind}, {} for none): a push pad or bumper it just entered, else a bonk by a hazard (`kind` "bonk"), else the small push-back of a solid
## poster door (`kind` "bonk" too, `hazard` "door"). Feed it every physics tick of the
## owner's simulation: `body` is the courier's CharacterBody3D, `motion` its CourierMotion (surface, launch and the mover it stands on).
func apply_effects(k: int, who: int, body: CharacterBody3D, motion: RefCounted) -> Dictionary:
	var feet := body.global_position
	var surface := surface_at(k, feet)
	var ground := {"ice": true} if bool(surface.get("ice", false)) else ({"slime": surface.slime} if surface.has("slime") else {})
	motion.set_surface(ground) # {} also puts the belt away: set_belt follows
	motion.set_belt(surface.get("belt", Vector2.ZERO))
	var effect := effects_at(k, who, feet)
	if effect.is_empty(): effect = bonk_at(k, who, body, motion.platform)
	if effect.is_empty(): effect = bump_at(k, who, body)
	if effect.is_empty(): effect = door_push(k, who, feet)
	door_nudge(k, body)
	if not effect.is_empty(): motion.launch(effect.v, bool(effect.override_xy), bool(effect.override_z))
	return effect

## The indices of the parts of hazard `h` that are bumper bars (`bump: true`, turning floors only).
static func _bump_bars(h: Dictionary) -> Array:
	var bars: Array = []
	if h.k != "spin" or h.hit: return bars
	for index in h.parts.size():
		if bool(h.parts[index].bump): bars.append(index)
	return bars

## The bumper bar: a courier whose capsule touches a bump bar of a turning floor (the pointer bar of a turntable, `bump: true` part) is bounced off it like off a bumper: `kick` m/s
## horizontally away from the bar's plane (the side of the bar's own axis the courier is on; from the top it is the side it is nearer to) and `up` m/s, a springy knock, not a fling.
## A bonk's cooldown applies (BONK_COOLDOWN). The touch is geometric (the courier's vertical axis and radius against the bar's box at the clock's pose), so every machine agrees.
## The effect has `kind` "bumper" (the bumper sound of game_run.gd) and the bar's look squashes (style/turntable_look.gd pulse).
func bump_at(k: int, who: int, body: CharacterBody3D) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty(): return {}
	var bonked: Dictionary = entry.bonked
	if bonked.has(who):
		var since := clock - float(bonked[who])
		if since >= 0.0 and since < BONK_COOLDOWN: return {}
	var feet := body.global_position - (entry.origin as Vector3)
	var pose := Hazards.Pose.new()
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		var bars: Array = mover.get("bars", []) # balls and scorchers carry no bumper bars
		if bars.is_empty(): continue
		Hazards.pose(mover.h, clock, pose)
		var frame := Transform3D(pose.basis, pose.position)
		for part_index: int in bars:
			var part: Dictionary = mover.h.parts[part_index]
			var local: Vector3 = ((frame * (part.xf as Transform3D)).affine_inverse()) * feet
			var half: Vector3 = (part.size as Vector3) * 0.5
			var reach := COURIER_RADIUS + BONK_REACH
			var gap_y := maxf(maxf(local.y - half.y, -half.y - (local.y + COURIER_HEIGHT)), 0.0)
			var gap_x := maxf(absf(local.x) - half.x, 0.0)
			var gap_z := maxf(absf(local.z) - half.z, 0.0)
			if gap_x * gap_x + gap_y * gap_y + gap_z * gap_z > reach * reach: continue
			var side := Vector3.BACK if local.z >= 0.0 else Vector3.FORWARD     # away from the bar's plane, along its width
			var away := ((frame.basis * (part.xf as Transform3D).basis) * side)
			away = Vector3(away.x, 0.0, away.z).normalized()
			bonked[who] = clock
			_pulse_bar(mover, part_index)
			var at := body.global_position + Vector3(0.0, CENTRE_HEIGHT, 0.0)
			return {"v": away * float(mover.h.kick) + Vector3.UP * float(mover.h.up_speed), "override_xy": true, "override_z": true, "id": index, "kind": "bumper", "hazard": "bar", "at": at}
	return {}

## The squash of a bump bar's look (a drawn level only): the bar was built apart from the turntable, named by its part's index.
func _pulse_bar(mover: Dictionary, part_index: int) -> void:
	if not _drawn: return
	var visual := (mover.body as Node).get_node_or_null("RaceLook/Bar%d" % part_index)
	if visual is Node3D: TurntableLook.pulse(visual as Node3D)

## A gate door (tools/gate_piece.py): a solid `lift` (no `hit`) with a part of tone "door". It only blocks and, closing on a courier, nudges it out (door_nudge).
static func _is_gate_door(h: Dictionary) -> bool:
	if h.k != "lift" or h.hit: return false
	for part: Dictionary in h.parts:
		if str(part.tone) == "door": return true
	return false

## A gate door that comes down on a courier must not trap or crush it, and never throws it: the courier is moved out of the door's volume by the shortest way across
## (a horizontal depenetration of the least of the four exits, at most DOOR_NUDGE_STEP per tick, only where the way is free), no velocity, no bonk. The door's pose is read
## DOOR_LEAD ahead of the clock. A courier standing on top of a door, or under it, or merely touching it, is left alone.
func door_nudge(k: int, body: CharacterBody3D) -> void:
	var entry := _entry(k)
	if entry.is_empty() or not body.is_inside_tree() or not (entry.root as Node).is_inside_tree(): return
	var feet := body.global_position - (entry.origin as Vector3)
	var pose := Hazards.Pose.new()
	for mover: Dictionary in entry.movers:
		if not bool(mover.get("door", false)) or not (mover.pose as Hazards.Pose).active: continue
		Hazards.pose(mover.h, clock + DOOR_LEAD, pose)
		for part: Dictionary in (mover.h as Dictionary).parts:
			var centre: Vector3 = pose.position + (part.xf as Transform3D).origin
			var half: Vector3 = (part.size as Vector3) * 0.5
			if feet.y + COURIER_HEIGHT <= centre.y - half.y or feet.y >= centre.y + half.y - 0.1: continue
			var dx := feet.x - centre.x
			var dz := feet.z - centre.z
			var reach_x := half.x + COURIER_RADIUS
			var reach_z := half.z + COURIER_RADIUS
			if absf(dx) >= reach_x - 0.01 or absf(dz) >= reach_z - 0.01: continue
			var exits := [Vector3(reach_x - dx, 0.0, 0.0), Vector3(-(reach_x + dx), 0.0, 0.0), Vector3(0.0, 0.0, reach_z - dz), Vector3(0.0, 0.0, -(reach_z + dz))]
			exits.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.length() < b.length())
			body.add_collision_exception_with(mover.body as PhysicsBody3D)
			for way: Vector3 in exits:
				var step := way.normalized() * minf(way.length() + 0.02, DOOR_NUDGE_STEP)
				if not body.test_move(body.global_transform, step):
					body.global_position += step
					break
			body.remove_collision_exception_with(mover.body as PhysicsBody3D)
			return

## The poster doors' small memories (who touched which solid door, where each courier was seen last) start over with a level or a round.
func _forget_doors(entry: Dictionary) -> void:
	(entry.door_touch as Dictionary).clear()
	(entry.door_seen as Dictionary).clear()
	(entry.door_felt as Dictionary).clear()
	var look: Variant = entry.get("door_look")
	if look != null and is_instance_valid(look): look.reset()

## The push-back of a solid poster door (a pure function of the courier's feet, `feet` in world space, and the level clock for a door that rides a slide): the
## launch on the tick it first presses on the block behind a board, {} otherwise. A bonk in the effect's own terms (`kind` "bonk": the slap sound at `at`) but
## small: the push is 3.6 m/s and a hop, a hazard throws 8.5 to 15. Not a physics callback: the block already stops the courier, this only gives it back a little.
func door_push(k: int, who: int, feet: Vector3) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty() or (entry.doors as Array).is_empty(): return {}
	var local: Vector3 = feet - (entry.origin as Vector3)
	var touch: Dictionary = entry.door_touch
	var memory: Dictionary = touch.get(who, {})
	touch[who] = memory
	var result := {}
	for door: Dictionary in entry.doors:
		var index := int(door.index)
		if not PosterDoors.near(door, local):
			memory.erase(index)
			continue
		var moved := PosterDoors.travel(door, clock)
		if PosterDoors.touching(door, local, 0.0, moved):
			if not memory.has(index) and result.is_empty():
				result = PosterDoors.push(door)
				result.id = index
				result.kind = "bonk"
				result.hazard = "door"
				result.at = feet + Vector3(0.0, CENTRE_HEIGHT, 0.0)
			memory[index] = true
		elif memory.has(index) and not PosterDoors.touching(door, local, PosterDoors.LEAVE, moved):
			memory.erase(index)
	return result

## Feed every rendered frame with every courier's feet (world): a courier that goes through the plane of an open (or torn) poster door (a logo poster) bursts it,
## one that presses on a solid door (a problem poster) makes it shudder. A door that rides a slide is where the level clock puts it, at the time of each sample.
## The look is client only and each machine sees the same positions and the same clock, so nothing is sent.
func observe_doors(k: int, who: int, feet: Vector3) -> void:
	var entry := _entry(k)
	if entry.is_empty() or (entry.doors as Array).is_empty(): return
	var local: Vector3 = feet - (entry.origin as Vector3)
	var seen: Dictionary = entry.door_seen
	var mark: Dictionary = seen.get(who, {})
	if mark.is_empty():
		seen[who] = {"p": local, "t": clock} # the first sample only remembers where the courier was
		return
	var last: Vector3 = mark.p
	var last_time: float = mark.t
	mark.p = local
	mark.t = clock
	var felt: Dictionary = entry.door_felt
	var memory: Dictionary = felt.get(who, {})
	felt[who] = memory
	var look: Variant = entry.get("door_look")
	var centre := feet + Vector3(0.0, CENTRE_HEIGHT, 0.0)
	for door: Dictionary in entry.doors:
		var index := int(door.index)
		if not PosterDoors.near(door, local):
			memory.erase(index)
			continue
		var moved := PosterDoors.travel(door, clock)
		if str(door.kind) == PosterDoors.SOLID:
			if PosterDoors.touching(door, local, 0.0, moved):
				if not memory.has(index) and last.distance_to(local) <= PosterDoors.MAX_STEP:
					door_bonk.emit(index, centre, who)
					if look != null: look.bonk(index)
				memory[index] = true
			elif memory.has(index) and not PosterDoors.touching(door, local, PosterDoors.LEAVE, moved):
				memory.erase(index)
		elif PosterDoors.crossed(door, last, local, PosterDoors.travel(door, last_time), moved):
			var heading: Vector3 = local - last
			if str(door.kind) == PosterDoors.OPEN: door_burst.emit(index, centre, heading)
			if look != null: look.burst(index, centre, heading)

## The bonk: a moving hazard that hurts (`hit`: swing, spin, slide, lift, ball, cannon) throws the courier `body` it touches the way the hazard moves at that
## point (a swing's hammer head, the end of a spinning bar, a sweeper wall) and a little up; a hazard moving mostly up or down throws it away from the
## hazard's centre. {} when nothing moving touches it. The touch is a physics query (the movers are bodies on layer 16), the velocity is
## the hazard's pose a probe either side of the clock (levels/hazards.gd is a pure function of the clock), so every machine that simulates
## its own courier gets the same throw. `platform`: the mover the courier stands on, which only carries it.
func bonk_at(k: int, who: int, body: CharacterBody3D, platform: Node = null) -> Dictionary:
	var entry := _entry(k)
	if entry.is_empty() or not body.is_inside_tree() or not (entry.root as Node).is_inside_tree(): return {}
	var bonked: Dictionary = entry.bonked
	if bonked.has(who):
		var since := clock - float(bonked[who])
		if since >= 0.0 and since < BONK_COOLDOWN: return {}
	var bonkers: Dictionary = {} # body instance id -> mover index
	for index in entry.movers.size():
		var mover: Dictionary = entry.movers[index]
		if bool(mover.get("bonk", false)) and (mover.pose as Hazards.Pose).active and mover.body != platform: bonkers[(mover.body as Object).get_instance_id()] = index
	if bonkers.is_empty(): return {}
	if _bonk_query == null:
		_bonk_query = PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = COURIER_RADIUS + BONK_REACH
		capsule.height = COURIER_HEIGHT + 2.0 * BONK_REACH
		_bonk_query.shape = capsule
		_bonk_query.collision_mask = LAYER_MOVER
	var centre := body.global_position + Vector3(0.0, CENTRE_HEIGHT, 0.0)
	_bonk_query.transform = Transform3D(Basis.IDENTITY, centre)
	_bonk_query.exclude = [body.get_rid()]
	var origin: Vector3 = entry.origin
	var local := centre - origin
	var space := body.get_world_3d().direct_space_state
	for contact: Dictionary in space.intersect_shape(_bonk_query, 8):
		var id := (contact.collider as Object).get_instance_id()
		if not bonkers.has(id): continue
		var index: int = bonkers[id]
		var mover: Dictionary = entry.movers[index]
		var h: Dictionary = mover.h
		var velocity := _point_velocity(h, local, clock)
		var normal := _bonk_normal(space, entry, body, mover.body, centre)
		if normal == Vector3.ZERO or (velocity - body.velocity).dot(normal) < BONK_APPROACH: continue
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var direction := flat
		if flat.length() < BONK_MIN_SPEED:
			# mostly up or down (a crusher): away from its centre
			if velocity.length() < BONK_MIN_SPEED: continue
			var pose: Hazards.Pose = mover.pose
			direction = Vector3(local.x - pose.position.x, 0.0, local.z - pose.position.z)
			if direction.length_squared() < 0.0001: direction = Vector3.BACK.rotated(Vector3.UP, float(who))
		direction = direction.normalized()
		var power := clampf(BONK_SPEED + BONK_GAIN * velocity.length(), BONK_SPEED, BONK_MAX)
		if flat.length() < BONK_MIN_SPEED: power *= 1.25 # a crusher has to throw sideways what a sweeper throws along
		bonked[who] = clock
		var up := BONK_UP * (0.5 if velocity.y < -BONK_MIN_SPEED else 1.0)
		if bool(mover.get("fling", false)):
			power = clampf(BONK_SPEED + BONK_GAIN * velocity.length(), FLING_MIN, FLING_MAX)
			direction = _off_course(entry, local, direction, who)
			up = FLING_UP
		return {"v": direction * power + Vector3.UP * up, "override_xy": true, "override_z": true, "id": index, "kind": "bonk", "hazard": str(h.k), "at": centre}
	return {}

## `direction` (unit, horizontal) of a fling, turned to the side when it runs along the course at `local` (a wheel standing across a walkway sweeps along it): to the side of
## the course the courier is on (alternating by `who` when it is on the line), so a hit always sends it away from the walkway.
func _off_course(entry: Dictionary, local: Vector3, direction: Vector3, who: int) -> Vector3:
	var route: PackedVector3Array = entry.data.route
	if route.size() < 2: return direction
	var near := 0
	var best := INF
	for index in route.size() - 1:
		var gap := Vector2(route[index].x - local.x, route[index].z - local.z).length_squared()
		if gap < best:
			best = gap
			near = index
	var along := Vector3(route[near + 1].x - route[near].x, 0.0, route[near + 1].z - route[near].z).normalized()
	if absf(along.dot(direction)) < FLING_ALONG: return direction
	var side := Vector3(-along.z, 0.0, along.x)
	var offset := (local - route[near]).dot(side)
	return side * (signf(offset) if absf(offset) > 0.3 else (1.0 if who % 2 == 0 else -1.0))

## The unit normal of the touch between the courier `body` (capsule at `centre`) and the mover `hazard_body`, pointing from the hazard to the courier; ZERO when
## the capsule's rest info has none. Every other mover is excluded so the answer is about this hazard only.
func _bonk_normal(space: PhysicsDirectSpaceState3D, entry: Dictionary, body: CharacterBody3D, hazard_body: Object, centre: Vector3) -> Vector3:
	var exclude: Array[RID] = [body.get_rid()]
	for other: Dictionary in entry.movers:
		if other.body != hazard_body: exclude.append((other.body as CollisionObject3D).get_rid())
	_bonk_query.exclude = exclude
	var info := space.get_rest_info(_bonk_query)
	_bonk_query.exclude = [body.get_rid()]
	if info.is_empty(): return Vector3.ZERO
	var normal: Vector3 = (info.normal as Vector3).normalized()
	return normal if normal.dot(centre - (info.point as Vector3)) >= 0.0 else -normal

## Velocity (m/s, level-local) of the point `local` carried along by hazard `h` at clock `t`: the pose a probe after minus a probe before, for the
## point as if it stuck to the hazard. A ball and a shot only move (their turning is the roll of the look).
func _point_velocity(h: Dictionary, local: Vector3, t: float) -> Vector3:
	var now := Hazards.Pose.new()
	var before := Hazards.Pose.new()
	var after := Hazards.Pose.new()
	Hazards.pose(h, t, now)
	Hazards.pose(h, t - BONK_PROBE, before)
	Hazards.pose(h, t + BONK_PROBE, after)
	if h.k in Hazards.SHOTS: return (after.position - before.position) / (2.0 * BONK_PROBE)
	var held := Transform3D(now.basis, now.position).affine_inverse() * local
	return (Transform3D(after.basis, after.position) * held - Transform3D(before.basis, before.position) * held) / (2.0 * BONK_PROBE)
