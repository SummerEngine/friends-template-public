extends RefCounted
## Step tiles (docs/level-format.md "Step tiles"): floors of tiles that fall for good once somebody has stood on them. A level's `tiles`
## section lists the floors and the kinds; the level world builds ONE static body per floor with a shape owner per tile (no node per tile: a stage round
## has thousands; every role: the physics of the owners, the local game and the tools stand on them) and, on a client, the look (style/step_tile_look.gd,
## or style/stage_tile_look.gd for `"style": "stage"`).
##
## Grids: `"grid": "hex"` (default; levels/hex_grid.gd: pointy-top hexagons, `pitch` metres across the flats, a floor's `rows` draw the layout in ASCII with one
## character per HALF tile width; `"orient": "flat"` turns the grid a quarter: flat-top hexagons) or `"grid": "square"` (levels/square_grid.gd: `pitch` metres a side,
## one character per tile). A tile is found from a position by rounding of its cell coordinates, never by a scan.
##
## State: `steps`, one byte per tile in file order. 0 = untouched. 1..254 = stood on at level clock `byte * STEP_UNIT`: the tile warns
## for its kind's `delay` seconds from then, then it is gone (collision off, the look falls away). PRE_GONE = never there this round (the
## show takes the outer tiles away when few play). The authority's rules write the bytes (they see who stands where), every client gets
## them in the show state (in pieces of CHUNK bytes: chunk_state / join_state) and calls set_steps(): a tile is a pure function of (clock, byte), so a late joiner is right at once.
## `"wrap": true` levels (the stage rounds) read the byte as a clock modulo a window (WRAP_MAX), see the constants.
## A stage round's tile exits at once (STAGE_FALL 0): the stepped tile turns cream and sinks by 0.4 of its thickness in the LOOK only (the collider keeps its height, so a runner stays level
## and the sinking tile sits under its feet), holds weight for its `delay`, and is gone in one frame (no drop, no shrink). Only stepped tiles go: nothing takes a tile by the clock.
##
## Collision of a stage round is one-way (docs/level-format.md "One-way floors"): floor k's body sits on the collision layer TILE_LAYER_BASE << k, and a courier collides
## with the layers whose top is at or under its feet (courier/courier_motion.gd), never with a layer over its head.
const Hazards := preload("res://levels/hazards.gd")
const Look := preload("res://style/step_tile_look.gd")
const StageLook := preload("res://style/stage_tile_look.gd")
const HexGrid := preload("res://levels/hex_grid.gd")
const SquareGrid := preload("res://levels/square_grid.gd")

const STEP_UNIT := 0.25     ## s per unit of a step byte (254 units: 63.5 s of level clock)
const STEP_MAX := 254
const PRE_GONE := 255
## A `"wrap": true` level (the stage rounds, rounds of up to 150 s of level clock) keeps the same one byte per tile: a step byte 1..WRAP_MAX is the step clock in
## WRAP_UNIT modulo WRAP_MAX units (a window of WRAP_MAX * WRAP_UNIT = 12.5 s and a resolution of 3 frames), read against the level clock (a tile is stepped at most
## LOOKAHEAD s ahead of a replica's clock, and was stepped less than a window ago while it is still warning or falling); SETTLED is written by the authority once the
## tile has fallen and nobody can see its clock any more; PRE_GONE never there. `unit_of(data)` is the unit a level's bytes count in.
const WRAP_UNIT := 0.05
const WRAP_MAX := 250
const SETTLED := 251
const LOOKAHEAD := 1.0      ## s a wrapped stamp may lie ahead of a replica's clock
const SETTLE_AFTER := 1.5   ## s after a tile is gone that the authority settles its byte (far under the 12.5 s window)
const STAGE_FALL := 0.0     ## s a tile of the stage look takes to go after its delay: none, it is gone in one frame (FALL_TIME for the hexagons of LAST TILE STANDING: 2.4)
const CHUNK := 240          ## bytes of a state field: the platform refuses a byte field over 256 B, so the steps travel in pieces (chunk_state)
const MAX_CHUNKS := 4
const MAX_TILES := CHUNK * MAX_CHUNKS ## one byte each
const LIVE_PIECE := 240     ## bytes of a piece of the packed list of tiles with a clock still to read (80 tiles)
const MAX_PIECES := 4       ## pieces of each packed field
const MAX_PACKED_TILES := CHUNK * 8 * MAX_PIECES ## tiles a packed state holds (7680)
const COLLIDER_GROW := 0.01 ## m the collider's corners reach past the exact hexagon: neighbours overlap a hair, nothing to catch a foot on
const SQUARE_GROW := 0.004  ## m a stage tile's collider reaches past the tile on every side (a square's half width, a hexagon's circumradius): the look draws the tile to its exact edge, the bevel is a visible line, and neighbours overlap a hair
const FALL_TIME := Look.FALL_TIME ## s the look of a vanished hexagon falls (gravity, no shrinking) before it rests far under the arena (no collision from the first moment)
const LAYER := 1            ## the solid layer the couriers stand on (not the camera's); the floors of a stage round use TILE_LAYER_BASE << floor instead
const TILE_LAYER_BASE := 2048 ## collision layer bit of floor 0 of a stage round, floor k has TILE_LAYER_BASE << k (9 floors: 2048 .. 524288; 512 is the lobby yard, 1024 the painting's blocker)
const TILE_LAYERS_ALL := TILE_LAYER_BASE * 511 ## every floor bit (9 floors)
const REACH_XZ := 0.1       ## m past a tile's edge that still counts as standing on it
const STAGE_REACH_XZ := 0.3 ## m past a stage tile's edge that still counts as standing on it: a courier's round feet (radius 0.35 m) rest on a tile's edge or corner with the middle up to 0.35 * sin(55 degrees, the steepest floor) = 0.29 m past it and stay; the tile they rest on must be one it steps on, or the courier hangs there for good
const REACH_BELOW := 0.6    ## a courier whose feet are this far below the top (a fall's last tick, a physics margin), or ...
const REACH_ABOVE := 0.12   ## ... this far above it, stands on it
const GHOST_ABOVE := 1.0    ## a floor whose top is more than this over a courier's feet is over its head (the floor it stands on, REACH_BELOW at most above them, and the ones below never are)
const GHOST_MARGIN := 0.3   ## m over a floor's top the camera still counts as under it (its near plane and a jump of the courier would cut into the slab)
const CELL_STEPS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)] ## a cell and its six neighbours
const SQUARE_STEPS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)] ## a cell and its eight neighbours
const MODE_SOLID := 0
const MODE_WARN := 1
const MODE_FALL := 2
const MODE_GONE := 3

signal warned(index: int, position: Vector3)   ## a tile starts to warn (world position of its top), not while poses are set quietly
signal vanished(index: int, position: Vector3)

var data: Dictionary = {}                ## parse() of the level's `tiles`
var steps := PackedByteArray()
var tile_bodies: Array = []              ## StaticBody3D per FLOOR (a shape owner per tile)
var look                                 ## style/step_tile_look.gd or style/stage_tile_look.gd instance on a client, null elsewhere
var origin := Vector3.ZERO               ## world position of the level (for the signals)
var ground: StaticBody3D = null          ## a stage round's permanent floor under the last layer (build_ground), null for none
var ghosted := PackedInt32Array()        ## the floors the view hides now (ghost_floors of the last ghost_view), on every role
var _mode := PackedByteArray()           ## per tile: MODE_*
var _owner := PackedInt32Array()         ## per tile: the shape owner of its floor's body
var _at := PackedFloat64Array()          ## per tile: the level clock it is gone at (INF untouched, -INF never there or settled), as read inside the window `_valid_from`..`_wake`
var _delays := PackedFloat32Array()      ## per tile: its kind's delay
var _live := PackedInt32Array()          ## tiles to pose each tick: a step to come or warning (a gone tile sleeps until the byte or the clock window changes)
var _listed := PackedByteArray()         ## per tile: 1 while in `_live`
var _valid_from := -INF                  ## the level clock window the read `_at` hold for (a wrapped byte is a clock modulo a window)
var _wake := INF
var _asleep_from := -INF                 ## the clock a sleeping (gone) tile went at the latest: a clock before it wakes everything (a new round)
var _stage := false

## `tiles` of a level file as typed data; {} when the level has none. Tiles: [{p (level-local centre of the top face), kind (key), floor,
## cell (Vector2i: column, row of the floor's text)}]; floors: [{y, centre (Vector2 x, z), cols, rows, cells (cell -> tile index), tone (String, "" none)}].
## Also: grid ("hex" | "square"), flat (flat-top hexagons), style ("" | "stage"), wrap (bool), fall (s a vanished tile takes to go: the look's), raise_max (the tallest kind's `raise`).
static func parse(source: Variant) -> Dictionary:
	if not source is Dictionary: return {}
	var square := str(source.get("grid", "hex")) == "square"
	var flat := not square and str(source.get("orient", "pointy")) == "flat"
	var pitch := float(source.get("pitch", 2.5))
	var thick := float(source.get("thick", 0.5))
	var kinds := {}
	var listed: Variant = source.get("kinds", {})
	if listed is Dictionary:
		for key: Variant in listed:
			var entry: Variant = (listed as Dictionary)[key]
			if str(key).length() != 1 or not entry is Dictionary: continue
			kinds[str(key)] = {"delay": float(entry.get("delay", 1.0)), "look": str(entry.get("look", "plain")), "slot": str(entry.get("slot", "")),
				"raise": float(entry.get("raise", 0.0)), "tone": str(entry.get("tone", ""))}
	var tiles: Array = []
	var layouts: Array = []
	var floors: Variant = source.get("floors", [])
	if floors is Array:
		for floor_index in (floors as Array).size():
			var floor_data: Variant = floors[floor_index]
			if not floor_data is Dictionary or not floor_data.get("rows") is Array: continue
			var at: Variant = floor_data.get("origin", [0.0, 0.0])
			var centre := Vector2(float(at[0]), float(at[1])) if at is Array and (at as Array).size() >= 2 else Vector2.ZERO
			var rows: Array = floor_data.rows
			var width := 0
			for row: Variant in rows: width = maxi(width, str(row).length())
			var layout := {"y": float(floor_data.get("y", 0.0)), "centre": centre, "cols": width, "rows": rows.size(), "cells": {}, "tone": str(floor_data.get("tone", ""))}
			for row_index in rows.size():
				var text := str(rows[row_index])
				for column in text.length():
					var key := text[column]
					if key == "." or key == " " or not kinds.has(key) or (not square and (column + row_index) % 2 != 0): continue
					var cell := Vector2i(column, row_index)
					var local := SquareGrid.cell_centre(pitch, layout, cell) if square else HexGrid.cell_centre(pitch, layout, cell)
					if flat: local = Vector2(local.y, local.x) # a flat-top hexagon grid is the pointy one turned a quarter
					(layout.cells as Dictionary)[cell] = tiles.size()
					tiles.append({"p": Vector3(local.x, float(layout.y) + float((kinds[key] as Dictionary).raise), local.y), "kind": key, "floor": layouts.size(), "cell": cell})
			layouts.append(layout)
	var fit: Array = []
	var sizes: Variant = source.get("fit", [])
	if sizes is Array:
		for entry: Variant in sizes:
			if entry is Dictionary: fit.append({"players": int(entry.get("players", 0)), "radius": float(entry.get("radius", 0.0))})
	if tiles.is_empty(): return {}
	var style := str(source.get("style", ""))
	var result := {"pitch": pitch, "thick": thick, "kinds": kinds, "tiles": tiles, "floors": layouts, "fit": fit, "grid": "square" if square else "hex", "style": style, "flat": flat,
		"wrap": bool(source.get("wrap", false)), "fall": STAGE_FALL if style == "stage" else FALL_TIME}
	var raise_max := 0.0
	for kind: Dictionary in kinds.values(): raise_max = maxf(raise_max, float(kind.raise))
	result["raise_max"] = raise_max
	return result

## The corners (x, z) of a tile of `tile_data` around its middle, `grow` metres further out (a hexagon's circumradius, a square's half width): pointy- or flat-top as the level has it.
static func tile_corners(tile_data: Dictionary, grow := 0.0) -> PackedVector2Array:
	var pitch := float(tile_data.pitch)
	if str(tile_data.grid) == "square": return SquareGrid.corners(pitch * 0.5 + grow)
	var corners := HexGrid.hex_corners(pitch / sqrt(3.0) + grow)
	if bool(tile_data.get("flat", false)):
		for index in corners.size(): corners[index] = Vector2(corners[index].y, corners[index].x)
	return corners

## The steps a round starts with for `players`: all 0, except the tiles outside the first `fit` entry whose `players` reaches the count
## (their middle further than `radius` from the level's middle, in x and z) which start gone.
static func start_steps(tile_data: Dictionary, players: int) -> PackedByteArray:
	var list: Array = tile_data.get("tiles", [])
	var result := PackedByteArray()
	result.resize(list.size())
	var radius := INF
	for entry: Dictionary in tile_data.get("fit", []):
		if players <= int(entry.players):
			radius = float(entry.radius)
			break
	if radius == INF: return result
	for index in list.size():
		var at: Vector3 = (list[index] as Dictionary).p
		if Vector2(at.x, at.z).length() > radius + 0.01: result[index] = PRE_GONE
	return result

## The steps as state fields of at most CHUNK bytes each: `tiles` (the first piece, also the whole list when it is short or empty), `tiles1`,
## `tiles2`, ... A state of a show that publishes these keys is what join_state() puts back together.
static func chunk_state(bytes: PackedByteArray) -> Dictionary:
	var fields := {"tiles": bytes.slice(0, CHUNK)}
	for piece in range(1, ceili(bytes.size() / float(CHUNK))):
		fields["tiles%d" % piece] = bytes.slice(piece * CHUNK, (piece + 1) * CHUNK)
	return fields

## The steps of a state published with chunk_state() or pack_state(): the pieces `tiles`, `tiles1`, ... in order (empty when the state has none or a piece is
## no byte array); a packed state (`tg` ...) needs the level's tile count `count`.
static func join_state(state: Dictionary, count := 0) -> PackedByteArray:
	if state.has("tg"): return unpack_state(state, count)
	var bytes := PackedByteArray()
	var piece: Variant = state.get("tiles", PackedByteArray())
	var piece_index := 0
	while piece is PackedByteArray:
		bytes.append_array(piece)
		piece_index += 1
		if piece_index >= MAX_CHUNKS: break
		piece = state.get("tiles%d" % piece_index)
	return bytes

## The wire form of a wrapped level's steps (thousands of tiles: one byte each would be several kilobytes in every snapshot). Most tiles are untouched or settled
## for good, so: `tg`, `tg1`, ... a bitmap (bit i of byte i / 8: tile i is gone for good, SETTLED or PRE_GONE), and `ta`, `ta1`, ...  the tiles with a clock still to read, three bytes each
## (index low, index high, step byte). Pieces of at most CHUNK bytes (a multiple of 3 for the list); unpack_state() puts the bytes back, a gone-for-good tile as SETTLED.
static func pack_state(bytes: PackedByteArray) -> Dictionary:
	var gone := PackedByteArray()
	gone.resize((bytes.size() + 7) / 8)
	var live := PackedByteArray()
	for index in bytes.size():
		var step := int(bytes[index])
		if step == SETTLED or step == PRE_GONE: gone[index >> 3] = int(gone[index >> 3]) | (1 << (index & 7))
		elif step != 0:
			live.append(index & 255)
			live.append(index >> 8)
			live.append(step)
	var fields := {}
	for piece in maxi(ceili(gone.size() / float(CHUNK)), 1):
		fields["tg" if piece == 0 else "tg%d" % piece] = gone.slice(piece * CHUNK, (piece + 1) * CHUNK)
	for piece in maxi(ceili(live.size() / float(LIVE_PIECE)), 1):
		fields["ta" if piece == 0 else "ta%d" % piece] = live.slice(piece * LIVE_PIECE, (piece + 1) * LIVE_PIECE)
	return fields

static func unpack_state(state: Dictionary, count: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	if count <= 0 or count > MAX_PACKED_TILES: return bytes
	bytes.resize(count)
	var gone := PackedByteArray()
	var piece: Variant = state.get("tg")
	var piece_index := 0
	while piece is PackedByteArray and piece_index < MAX_PIECES:
		gone.append_array(piece)
		piece_index += 1
		piece = state.get("tg%d" % piece_index)
	for index in mini(count, gone.size() * 8):
		if int(gone[index >> 3]) & (1 << (index & 7)) != 0: bytes[index] = SETTLED
	piece = state.get("ta")
	piece_index = 0
	while piece is PackedByteArray and piece_index < MAX_PIECES:
		var live: PackedByteArray = piece
		for at in range(0, live.size() - 2, 3):
			var index := int(live[at]) | (int(live[at + 1]) << 8)
			if index < count: bytes[index] = live[at + 2]
		piece_index += 1
		piece = state.get("ta%d" % piece_index)
	return bytes

## Builds the floors' bodies (and the look on a client). `ground_data`: a stage round's `stage.ground` ({y, size, centre, thick, tone}, level-local), {} for none.
func build(level_root: Node3D, tile_data: Dictionary, world_origin: Vector3, drawn: bool, ground_data := {}) -> void:
	data = tile_data
	origin = world_origin
	var list: Array = data.tiles
	var floors: Array = data.floors
	var thick := float(data.thick)
	_stage = str(data.style) == "stage"
	var shapes := {} # raise -> Shape3D: one shape for every tile of that height
	for floor_index in floors.size():
		var body := StaticBody3D.new()
		body.name = "Floor%d" % floor_index
		body.collision_layer = (TILE_LAYER_BASE << floor_index) if _stage else LAYER
		body.collision_mask = 0
		body.set_meta("fx", true) # the collision look leaves it alone: the tile look draws it
		level_root.add_child(body)
		tile_bodies.append(body)
	steps.resize(list.size())
	_mode.resize(list.size())
	_owner.resize(list.size())
	_at.resize(list.size())
	_at.fill(INF)
	_delays.resize(list.size())
	_listed.resize(list.size())
	for index in list.size():
		var tile: Dictionary = list[index]
		var kind: Dictionary = (data.kinds as Dictionary)[tile.kind]
		var raise := float(kind.raise)
		if not shapes.has(raise): shapes[raise] = _tile_shape(thick + raise)
		var body: StaticBody3D = tile_bodies[int(tile.floor)]
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shapes[raise])
		body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, (tile.p as Vector3) - Vector3(0.0, (thick + raise) * 0.5, 0.0)))
		_owner[index] = owner_id
		_delays[index] = float(kind.delay)
	if not ground_data.is_empty(): build_ground(level_root, ground_data)
	if drawn:
		if _stage:
			look = StageLook.new()
			look.build(level_root, data, ground_data)
		else:
			look = Look.new()
			look.build(level_root, data)

## The collider of one tile `height` metres thick (its top at the tile's top): the box of a square, the prism of a hexagon.
func _tile_shape(height: float) -> Shape3D:
	if str(data.grid) == "square":
		var box := BoxShape3D.new()
		var side := float(data.pitch) + SQUARE_GROW * 2.0
		box.size = Vector3(side, height, side)
		return box
	var corners := tile_corners(data, SQUARE_GROW if _stage else COLLIDER_GROW)
	var points := PackedVector3Array()
	for y in [-height * 0.5, height * 0.5]:
		for corner in corners: points.append(Vector3(corner.x, y, corner.y))
	var hexagon := ConvexPolygonShape3D.new()
	hexagon.points = points
	return hexagon

## A stage round's permanent ground: one solid box (layer LAYER) whose top is `ground_data.y`, centred on `ground_data.centre` (x, z), `size` (x, z) wide, `thick` deep.
func build_ground(level_root: Node3D, ground_data: Dictionary) -> void:
	var size: Array = ground_data.size
	var height := float(ground_data.thick)
	var middle: Array = ground_data.centre
	ground = StaticBody3D.new()
	ground.name = "StageGround"
	ground.collision_layer = LAYER
	ground.collision_mask = 0
	ground.set_meta("fx", true) # the collision look leaves it alone: the tile look draws it
	ground.position = Vector3(float(middle[0]), float(ground_data.y) - height * 0.5, float(middle[1]))
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(size[0]), height, float(size[1]))
	collider.shape = box
	ground.add_child(collider)
	level_root.add_child(ground)

## True once tile `index` has no collision (gone or falling away, as last posed).
func is_gone(index: int) -> bool:
	return index >= 0 and index < _mode.size() and _mode[index] >= MODE_FALL

## The floors (indices into `floors` of parse()) a camera at `camera_y` must not draw while it follows a courier whose feet are at `feet_y` (both level-local):
## a floor whose top is more than GHOST_ABOVE over the feet and the camera is below its top + GHOST_MARGIN. Such a floor hangs over the camera as a slab
## across the view; the courier's own floor and every floor below it, and every floor a camera that looks down from above sees, are never in the list. Pure
## function of the level and two heights: the same on every machine, nothing authoritative.
static func ghost_floors(tile_data: Dictionary, camera_y: float, feet_y: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var floors: Array = tile_data.get("floors", [])
	for index in floors.size():
		var top := float((floors[index] as Dictionary).y)
		if top > feet_y + GHOST_ABOVE and camera_y < top + GHOST_MARGIN: result.append(index)
	return result

## Hides (or brings back) the floors over a camera at `camera_y` (level-local) that follows feet at `feet_y`; the look changes only when the set changes. A stage round's look
## fades the floors over `dt` seconds a frame (INF: at once, the other looks always are).
func ghost_view(camera_y: float, feet_y: float, dt := INF) -> void:
	if data.is_empty(): return
	var floors := ghost_floors(data, camera_y, feet_y)
	var fading := _stage and dt != INF
	if floors != ghosted:
		ghosted = floors
		if look != null:
			if _stage: look.set_ghosted(floors, not fading)
			else: look.set_ghosted(floors)
	if fading and look != null: look.advance_fade(dt)

func tile_count() -> int:
	return (data.tiles as Array).size() if data.has("tiles") else 0

## Takes the round's steps (one byte per tile; a list of another size is ignored). `clock`: the level clock, for the poses; `quiet`: no
## events for what the new state has already done. Only the tiles with a new byte are looked at (comparing whole CHUNK-byte slices finds them).
func set_steps(bytes: PackedByteArray, clock: float, quiet := false) -> void:
	if bytes.size() != tile_count() or bytes == steps: return
	var before := steps
	steps = bytes.duplicate() # packed arrays are passed by reference: the caller keeps writing its own
	for first in range(0, steps.size(), CHUNK):
		var last := mini(first + CHUNK, steps.size())
		if steps.slice(first, last) == before.slice(first, last): continue
		for index in range(first, last):
			if steps[index] == before[index]: continue
			_resolve(index, clock)
			_list(index)
	pose(clock, quiet)

## Puts tile `index` on the list of tiles posed every tick.
func _list(index: int) -> void:
	if _listed[index] != 0: return
	_listed[index] = 1
	_live.append(index)

## Reads tile `index`'s byte against `clock` into `_at` and narrows the clock window the readings hold for. A tile with no step or with the byte of a settled or absent tile needs no window.
func _resolve(index: int, clock: float) -> void:
	var step := int(steps[index])
	if step == 0:
		_at[index] = INF
	elif step == PRE_GONE or step == SETTLED:
		_at[index] = -INF
	else:
		var stepped := stepped_at(index, clock)
		_at[index] = stepped + _delays[index]
		if bool(data.get("wrap", false)):
			_valid_from = maxf(_valid_from, stepped - LOOKAHEAD)
			_wake = minf(_wake, stepped + WRAP_MAX * WRAP_UNIT - LOOKAHEAD)

## Reads every byte again (the clock left the window the readings hold for, or went back before a gone tile) and lists every tile that has a clock to read.
func _resolve_all(clock: float) -> void:
	_valid_from = -INF
	_wake = INF
	_asleep_from = -INF
	_live = PackedInt32Array()
	_listed.fill(0)
	for index in steps.size():
		if steps[index] == 0 and _mode[index] == MODE_SOLID: continue
		_resolve(index, clock)
		_list(index)

## The level clock at which tile `index` was stepped on, resolved against the level clock `clock` (a wrapped byte is a clock modulo a window); INF while
## untouched, -INF when it was never there or has settled.
func stepped_at(index: int, clock: float) -> float:
	var step := int(steps[index]) if index < steps.size() else 0
	if step == 0: return INF
	if step == PRE_GONE or step == SETTLED: return -INF
	if not bool(data.get("wrap", false)): return step * STEP_UNIT
	var window := WRAP_MAX * WRAP_UNIT
	var stamp := step * WRAP_UNIT
	return stamp + window * floorf((clock + LOOKAHEAD - stamp) / window)

## The seconds of level clock one unit of a step byte counts on a level (its `tiles` data): STEP_UNIT, or WRAP_UNIT on a wrapped level.
static func unit_of(tile_data: Dictionary) -> float:
	return WRAP_UNIT if bool(tile_data.get("wrap", false)) else STEP_UNIT

## The step byte of a step at level clock `clock` on a level with `tile_data`: rounded to the unit, wrapped into 1..WRAP_MAX on a wrapped level.
static func stamp_at(tile_data: Dictionary, clock: float) -> int:
	var count := roundi(clock / unit_of(tile_data))
	if bool(tile_data.get("wrap", false)): return posmod(count - 1, WRAP_MAX) + 1
	return clampi(ceili(clock / STEP_UNIT), 1, STEP_MAX)

## The level clock at which tile `index` is gone: INF while untouched, -INF when it was never there or has settled.
func gone_at(index: int, clock := 0.0) -> float:
	var step := stepped_at(index, clock)
	return step if absf(step) == INF else step + _delay(index)

func _delay(index: int) -> float:
	return float(((data.kinds as Dictionary)[(data.tiles[index] as Dictionary).kind] as Dictionary).delay)

## True when tile `index` is gone for good by the level clock `clock`, its fall long over: the authority writes SETTLED into such a tile's byte.
func is_settled(index: int, clock: float) -> bool:
	return steps[index] != SETTLED and steps[index] != 0 and steps[index] != PRE_GONE and clock > gone_at(index, clock) + float(data.fall) + SETTLE_AFTER

## Poses every tile that has a step to come or is warning or falling at level clock `clock`. `quiet`: no events (building, a jump of the clock). A tile that is gone
## sleeps (it is not looked at again) until its byte changes, the clock leaves the window its byte is read in, or the clock goes back before it went.
func pose(clock: float, quiet := false) -> void:
	if clock < _valid_from or clock >= _wake or clock < _asleep_from: _resolve_all(clock)
	var fall := float(data.fall)
	var at := 0
	while at < _live.size():
		var index := _live[at]
		var gone := _at[index]
		var delay := _delays[index]
		var mode := MODE_SOLID
		var tau := 0.0
		if gone == -INF or clock >= gone + fall: mode = MODE_GONE
		elif clock >= gone:
			mode = MODE_FALL
			tau = clock - gone
		elif clock >= gone - delay:
			mode = MODE_WARN
			tau = clock - (gone - delay)
		if mode != _mode[index] or mode == MODE_FALL or (mode == MODE_WARN and not _stage): _apply(index, mode, tau, clock, quiet) # the stage look changes a warned tile once, the others every tick
		if mode == MODE_GONE or (mode == MODE_SOLID and gone == INF):
			if mode == MODE_GONE and gone != -INF: _asleep_from = maxf(_asleep_from, gone)
			_listed[index] = 0
			_live[at] = _live[_live.size() - 1]
			_live.resize(_live.size() - 1)
		else:
			at += 1

func _apply(index: int, mode: int, tau: float, _clock: float, quiet: bool) -> void:
	var before := int(_mode[index])
	if mode != before:
		_mode[index] = mode
		var solid := mode == MODE_SOLID or mode == MODE_WARN
		var body: StaticBody3D = tile_bodies[int((data.tiles[index] as Dictionary).floor)]
		body.shape_owner_set_disabled(_owner[index], not solid)
		# a warned stage tile sinks in the look only: the collider keeps its height until the tile is gone, so a runner stays level (no bob on every fresh tile)
		var at: Vector3 = origin + (data.tiles[index] as Dictionary).p
		if not quiet:
			if mode == MODE_WARN and before == MODE_SOLID: warned.emit(index, at)
			elif mode >= MODE_FALL and before <= MODE_WARN: vanished.emit(index, at)
	if look != null: look.pose(index, mode, tau, _delays[index])

## The tiles (indices, gone or not) a courier standing at `feet` (level-local) is on: within `reach` of the tile's edges sideways and
## REACH_BELOW / REACH_ABOVE of its top. The cell under the feet and the ones around it are looked at: a courier on an edge stands on two
## tiles, on a corner on three (hexagons) or four (squares).
func tiles_at(feet: Vector3, reach: float) -> Array:
	var result: Array = []
	var pitch := float(data.pitch)
	var square := str(data.grid) == "square"
	var flat := bool(data.get("flat", false))
	var gx := feet.z if flat else feet.x # a flat-top grid is the pointy one turned a quarter: ask in the pointy grid's own axes
	var gz := feet.x if flat else feet.z
	var raise := float(data.get("raise_max", 0.0))
	for layout: Dictionary in data.floors:
		var rise := feet.y - float(layout.y)
		if rise < -REACH_BELOW or rise > REACH_ABOVE + raise: continue
		var cell := SquareGrid.cell_of(pitch, layout, gx, gz) if square else HexGrid.cell_of(pitch, layout, gx, gz)
		for step: Vector2i in (SQUARE_STEPS if square else CELL_STEPS):
			var found: Variant = (layout.cells as Dictionary).get(cell + step)
			if found == null: continue
			var over := feet.y - float((data.tiles[int(found)] as Dictionary).p.y) # over this tile's own top (a raised pad stands higher than its floor)
			if over < -REACH_BELOW or over > REACH_ABOVE: continue
			if square:
				var middle_square := SquareGrid.cell_centre(pitch, layout, cell + step)
				if SquareGrid.holds(pitch, gx - middle_square.x, gz - middle_square.y, reach): result.append(int(found))
				continue
			var middle := HexGrid.cell_centre(pitch, layout, cell + step)
			if HexGrid.hex_holds(pitch, gx - middle.x, gz - middle.y, reach): result.append(int(found))
	return result

## The tiles a courier standing at `feet` (level-local) is on now: tiles_at, without the ones that are gone at level clock `clock`. A stage round reaches STAGE_REACH_XZ past a tile's
## edge (where its round feet can rest), the other step-tile rounds REACH_XZ.
func tiles_under(feet: Vector3, clock: float) -> Array:
	return tiles_at(feet, STAGE_REACH_XZ if _stage else REACH_XZ).filter(func(index: int) -> bool: return clock < gone_at(index, clock))
