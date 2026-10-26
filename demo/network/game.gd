extends RefCounted
## Shared Summer SDK contract: owner-simulated couriers (pose wire) and the authority's shared game state (snapshot v11).

## Dev measurement: per-key uncompressed size of the last snapshot.
static var measure_wire := false
static var wire_sizes := {}

const InputWire = preload("res://network/input_wire.gd")
const MetadataWire = preload("res://network/snapshot_metadata_wire.gd")
const OwnerPoseWire = preload("res://network/owner_pose_wire.gd")

## One queue for 2 to 10 players. Both client admission and authority configuration reject any other queue.
const QUEUES := {&"lobby_10": 10}
const DEFAULT_QUEUE := &"lobby_10"
const MATCH_MODE_VERSION := 4
const WIRE_VERSION := 12
const INPUT := &"gw.input"
const WORKER := &"gw.worker"
const SNAPSHOT := &"gw.world"
const COMMAND := &"gw.command"
const MAX_PLAYERS := 10
const HOLDING_FLAG := 1
const PLAY_MODES := ["carry", "balloon", "show"]
## Balloon rounds: `balloon` = BalloonSim.snapshot() (8 floats) + [hover, checkpoint, bumps]; `contact` = per slot
## [held_by, kick x, y, z, respawns, respawn x, y, z] (kick and respawns count up within an epoch). Every snapshot: `scorch` = per
## slot [zaps and burns so far, kind of the last: 1 zap, 2 burn] (game/team_play.gd). Balloon rounds: `slaps` = per slot [slaps so far,
## hand of the last: 1 left, 2 right]. Lobby: `props` = PropSim.snapshot(), per loose prop [x, y, z, vx, vy, vz, held_by]
## (players/prop_sim.gd).
const BALLOON_FLOATS := 11
const CONTACT_FLOATS := 8
const PROP_FLOATS := 7
const MAX_PROPS := 16
## Seats are network identities (input/worker group keys); slots are positions in the round.
static func seats_for_queue(queue: StringName) -> int:
	return int(QUEUES.get(queue, 0))

static func match_mode_for_queue(queue: StringName) -> Dictionary:
	var seats := seats_for_queue(queue)
	if seats == 0: return {}
	return {"mode_version":MATCH_MODE_VERSION,"match_queue":str(queue),"seat_count":seats}

static func valid_match_mode(value: Variant, expected_queue: StringName = &"") -> bool:
	# Command pack/unpack is JSON, whose numeric values decode as floats; snapshots retain the Variant int.
	if not value is Dictionary or not (value.get("mode_version") is int or value.get("mode_version") is float) or value.mode_version!=MATCH_MODE_VERSION: return false
	if not value.get("match_queue") is String: return false
	var queue := StringName(value.match_queue)
	var expected := match_mode_for_queue(queue)
	if not (value.get("seat_count") is int or value.get("seat_count") is float): return false
	return not expected.is_empty() and value.seat_count==expected.seat_count and (expected_queue==&"" or queue==expected_queue)

static func with_match_mode(state: Dictionary, queue: StringName) -> Dictionary:
	var mode := match_mode_for_queue(queue)
	if mode.is_empty(): return {}
	var result := state.duplicate()
	result.merge(mode,true)
	return result

static func bind_match_mode(world_id: String, context_queue: StringName, expected_queue: StringName, mode: Variant) -> Dictionary:
	# The caller supplies admitted SDK facts + the authority's join result.
	# Empty context.queue is possible on direct joins before World facts arrive;
	# expected_queue must still come from explicit target or verified retry tuple.
	if world_id.is_empty() or expected_queue==&"" or not valid_match_mode(mode,expected_queue): return {}
	if context_queue!=&"" and context_queue!=expected_queue: return {}
	return {"world_id":world_id,"queue":str(expected_queue),"mode_version":MATCH_MODE_VERSION}

static func retry_queue(world_id: String, binding: Dictionary) -> StringName:
	if world_id.is_empty() or binding.get("world_id")!=world_id or not binding.get("queue") is String: return &""
	var queue := StringName(binding.queue)
	var mode := {"mode_version":binding.get("mode_version"),"match_queue":str(queue),"seat_count":seats_for_queue(queue)}
	return queue if valid_match_mode(mode,queue) else &""

static func schema(id: String) -> SummerNetworkSchema:
	var field := SummerNetworkField.new()
	field.field_name = &"b"
	field.type = 20 # Summer wire bytes, not Godot Variant.Type.
	var resource := SummerNetworkSchema.new()
	resource.schema_id = StringName(id)
	resource.state_fields = [field]
	return resource

static func composition() -> SummerNetworkComposition:
	var audience := SummerWorldAudience.new()
	audience.max_expansion = MAX_PLAYERS
	var inputs := SummerNetworkStateStream.new()
	inputs.stream_id = INPUT
	inputs.writer_policy = 1
	inputs.skip_writer_echo = true
	inputs.state_schema = schema("gw.input.v1")
	inputs.audience_policy = SummerTargetSessionAudience.new()
	inputs.max_audience_count = 1
	inputs.max_keys = MAX_PLAYERS
	inputs.max_state_bytes = 1024
	inputs.max_total_bytes = 1024 * MAX_PLAYERS
	# Authority relay is bound to the admitted worker entity lifetime. INPUT
	# remains private; only the small accepted owner pose reaches observers.
	var workers := SummerNetworkStateStream.new()
	workers.stream_id = WORKER
	workers.state_schema = schema("gw.worker.v1")
	workers.audience_policy = audience
	workers.max_audience_count = MAX_PLAYERS
	workers.max_keys = MAX_PLAYERS
	workers.max_state_bytes = 512
	workers.max_total_bytes = 512 * MAX_PLAYERS
	var snapshot := SummerNetworkStateStream.new()
	snapshot.stream_id = SNAPSHOT
	snapshot.state_schema = schema("gw.world.v1")
	snapshot.audience_policy = audience
	snapshot.max_audience_count = MAX_PLAYERS
	snapshot.max_keys = 1
	snapshot.max_state_bytes = 32768
	snapshot.max_total_bytes = 32768
	var command := SummerNetworkOccurrenceStream.new()
	command.stream_id = COMMAND
	command.command_scope = 2
	command.command_tick_dispatch = true
	command.command_timeout_msec = 8000
	command.payload_schema = schema("gw.command.v1")
	command.result_schema = schema("gw.command.result.v1")
	var resource := SummerNetworkComposition.new()
	resource.network_version = "1.3.0"
	resource.state_streams = [inputs, snapshot, workers]
	resource.occurrence_streams = [command]
	return resource

static func build_network(parent: Node) -> SummerNetworkSpawner:
	var world := SummerNetworkWorld.new()
	world.name = "World"
	parent.add_child(world)
	var entities := Node3D.new()
	entities.name = "Entities"
	parent.add_child(entities)
	var marker := Node3D.new()
	marker.name = "PlayerSession"
	var scene := PackedScene.new()
	scene.pack(marker)
	marker.free()
	var archetype := SummerEntityArchetype.new()
	archetype.archetype_id = &"player"
	archetype.network_schema = SummerNetworkSchema.new()
	archetype.network_schema.schema_id = &"gw.player.v1"
	archetype.authority_model_scene = scene
	archetype.owner_projection_scene = scene
	archetype.observer_projection_scene = scene
	var spawner := SummerNetworkSpawner.new()
	spawner.name = "Spawner"
	spawner.network_world_path = NodePath("../World")
	spawner.entities_root_path = NodePath("../Entities")
	spawner.archetypes = [archetype]
	spawner.player_archetype = &"player"
	spawner.network_composition = composition()
	parent.add_child(spawner)
	return spawner

static func input_key(seat: int) -> StringName:
	return StringName("p%d" % seat)

## Owner poses relayed per owner: every pose with up to 2 players in the World, every 2nd up to 4, every 3rd above
## (60/30/20 Hz: the relayed bytes grow with players x players). Observers widen their back time to match.
static func relay_every(players: int) -> int:
	return 1 if players <= 2 else (2 if players <= 4 else 3)

static func pack(document: Dictionary) -> Dictionary:
	if document.get("move") is Array and document.move.size() == 2 and document.has("seq"):
		return {"b": InputWire.encode(document)}
	return {"b": JSON.stringify(document).to_utf8_buffer()}

static func unpack(fields: Dictionary) -> Dictionary:
	var bytes: PackedByteArray = fields.get("b", PackedByteArray())
	if InputWire.recognizes(bytes): return InputWire.decode(bytes)
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return value if value is Dictionary else {}

## Snapshot wire v12 (WIRE_VERSION): the shared fields plus play_mode, balloon, contact, scorch, slaps and props. Players are per-slot arrays, not dictionaries: [position, flags, acceleration] and, only while
## `state.baseline` is true (the authority sets it for a burst after a reset epoch, a join or a resync request), a
## fourth element, the owner's start yaw. `flags` bit 0 = holding the painting. Owners simulate their own couriers
## and send poses on their own wires, so the shared snapshot only needs this slim part per player.
## An empty slot is the int 0. `fragments` is the painting's compact shard state, carried as is.
static func pack_snapshot(state: Dictionary) -> Dictionary:
	if not state.get("players",[]) is Array: return {}
	var baseline: bool = bool(state.get("baseline", false))
	var wire := state.duplicate()
	wire.metadata_frame=MetadataWire.encode(state)
	if wire.metadata_frame.is_empty():return {}
	for key:String in MetadataWire.FIELDS:wire.erase(key)
	var players := []
	for entry_value: Variant in state.get("players", []):
		if not entry_value is Dictionary:return {}
		var source:Dictionary=entry_value
		if source.get("inactive", false):
			players.append(0)
			continue
		if not source.get("position") is Vector3 or not source.position.is_finite():return {}
		if not source.get("acceleration") is Vector3 or not source.acceleration.is_finite():return {}
		var entry := [source.position, HOLDING_FLAG if bool(source.get("holding", false)) else 0, source.acceleration]
		if baseline:
			var yaw: Variant = source.get("yaw")
			if not (yaw is float or yaw is int) or not is_finite(float(yaw)):return {}
			entry.append(float(yaw))
		players.append(entry)
	wire.players = players
	wire.wire_version = WIRE_VERSION
	if measure_wire:
		wire_sizes = {}
		for key: Variant in wire: wire_sizes[str(key)] = var_to_bytes(wire[key]).size()
	return {"b": var_to_bytes(wire).compress(FileAccess.COMPRESSION_DEFLATE)}

static func unpack_snapshot(fields: Dictionary) -> Dictionary:
	var packed: PackedByteArray = fields.get("b", PackedByteArray())
	if packed.is_empty() or packed.size() > 32768: return {}
	var raw := packed.decompress_dynamic(2097152, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty(): return {}
	var value: Variant = bytes_to_var(raw)
	if not value is Dictionary: return {}
	if int(value.get("wire_version", 0)) != WIRE_VERSION or not value.get("players",[]) is Array: return {}
	var metadata:=MetadataWire.decode(value.get("metadata_frame"))
	if metadata.is_empty():return {}
	for key:String in MetadataWire.FIELDS:
		if value.has(key):return {}
	value.merge(metadata.value);value.erase("metadata_frame")
	var baseline: bool = bool(value.get("baseline", false))
	var players := []
	var holding := []
	for entry: Variant in value.players:
		if entry is int:
			if entry != 0:return {}
			players.append({"inactive": true})
			holding.append(false)
			continue
		if not entry is Array or entry.size() != (4 if baseline else 3):return {}
		if not entry[0] is Vector3 or not entry[0].is_finite() or not entry[1] is int or entry[1] < 0 or not entry[2] is Vector3 or not entry[2].is_finite():return {}
		var player := {"position": entry[0], "velocity": Vector3.ZERO, "acceleration": entry[2], "holding": bool(entry[1] & HOLDING_FLAG)}
		if baseline:
			if not entry[3] is float or not is_finite(entry[3]):return {}
			player.movement = {"yaw": entry[3]}
		holding.append(player.holding)
		players.append(player)
	value.players = players
	value.holding = holding
	if value.has("play_mode") and not (value.play_mode is String and value.play_mode in PLAY_MODES): return {}
	if value.has("balloon") and not _floats(value.balloon, BALLOON_FLOATS): return {}
	if value.has("contact") and not _floats(value.contact, CONTACT_FLOATS * players.size()): return {}
	if value.has("scorch") and not _counters(value.scorch, 2 * players.size()): return {}
	if value.has("slaps") and not _counters(value.slaps, 2 * players.size()): return {}
	if value.has("props") and not _props(value.props, players.size()): return {}
	return value

## The loose props: whole entries, at most MAX_PROPS, finite, each held by nobody (-1) or a slot.
static func _props(value: Variant, slots: int) -> bool:
	if not value is PackedFloat32Array or value.size() % PROP_FLOATS != 0 or value.size() > PROP_FLOATS * MAX_PROPS: return false
	if not _floats(value, value.size()): return false
	for at in range(PROP_FLOATS - 1, value.size(), PROP_FLOATS):
		if value[at] != floorf(value[at]) or value[at] < -1.0 or value[at] >= slots: return false
	return true

static func _counters(value: Variant, size: int) -> bool:
	if not value is PackedInt32Array or value.size() != size: return false
	for number: int in value:
		if number < 0: return false
	return true

static func _floats(value: Variant, size: int) -> bool:
	if not value is PackedFloat32Array or value.size() != size: return false
	for number: float in value:
		if not is_finite(number): return false
	return true

static func valid_input(data: Dictionary) -> bool:
	if data.has("movement"): return false # The owner pose is the only movement wire.
	if data.has("owner_pose"):
		if not data.owner_pose is PackedByteArray or OwnerPoseWire.decode(data.owner_pose).is_empty(): return false
	if not data.get("move") is Array or data.move.size() != 2: return false
	for number in [data.move[0], data.move[1], data.get("facing", 0.0), data.get("height", 0.0), data.get("roll", 0.0)]:
		if not (number is float or number is int) or not is_finite(float(number)): return false
	for count in [data.get("jump_seq", 0), data.get("grab_seq", 0), data.get("slap_seq", 0), data.get("item_seq", 0), data.get("test_seq", 0)]: # item_seq: the show's ITEM presses, an extra key (network/input_wire.gd)
		if not count is int or count < 0: return false
	if Vector2(data.move[0], data.move[1]).length() > 1.01: return false
	if absf(float(data.get("height", 0))) > 1.0 or absf(float(data.get("roll", 0))) > 1.0: return false
	# Walk-in lobby: the owner says a menu/overlay covers its game (it can only opt out of a start).
	if data.has("menu") and not data.menu is bool: return false
	return int(data.get("seq", -1)) >= 0

static func neutral_input(data: Dictionary = {}) -> Dictionary:
	var neutral := data.duplicate(true)
	neutral.move = [0, 0]
	neutral.jump = false
	neutral.height = 0.0
	neutral.roll = 0.0
	neutral.restart = false
	neutral.erase("owner_pose")
	return neutral

## Neutral input of a player whose menu or overlay covers the game: no movement and, in the
## walk-in lobby, no pad occupancy (network/match_controller.gd _seat_zone).
static func away_input(data: Dictionary = {}) -> Dictionary:
	var away := neutral_input(data)
	away.menu = true
	return away
