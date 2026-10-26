extends RefCounted
## What a minigame's rules (modes/mode_rules.gd) may read and do, the same on the authority and in the local game.
## Built by network/match_controller.gd (online) and client/local_level_flow.gd (one machine) at a round start.
##
## Players are slots 0..count-1 (the round's roster). Each slot plays a cast member: seat(slot) is its cast index, so
## name(slot) and player(slot) are what everyone sees on that character (its look, name tag, catchphrase).
const TeamCast := preload("res://style/team_cast.gd")
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const CourseSection := preload("res://course_section.gd")
const PodiumRoom := preload("res://style/podium_room.gd")

var simulation ## game/game_run.gd (authority or local role), the shell in its "lobby" phase: the yard, contact and props
var count := 0 ## players in the round
var seats: Array = [] ## slot -> cast index (seat)
var rng := RandomNumberGenerator.new()
var pick := "" ## the lobby circle this round was started from ("" or the cast's own circle: the mode's whole game; the show: a circle of one round, modes/lineup/round_list.gd)

func _init(shell, round_seats: Array, seed_value: int) -> void:
	simulation = shell
	seats = round_seats.duplicate()
	count = seats.size()
	rng.seed = seed_value

## The cast member a slot plays (TeamCast.player: name, color, catchphrase, title, look, emote).
func player(slot: int) -> Dictionary:
	return TeamCast.player(seat(slot))

func seat(slot: int) -> int:
	return int(seats[slot]) if slot >= 0 and slot < seats.size() else slot

func name(slot: int) -> String:
	return str(player(slot).name)

## False once the slot left the round (online).
func active(slot: int) -> bool:
	return slot >= 0 and slot < count and simulation.is_slot_active(slot)

## Where the slot's character stands (its feet), world space.
func position(slot: int) -> Vector3:
	return simulation.actors[slot].position if slot >= 0 and slot < count else Vector3.ZERO

## True while the slot holds the mode's action button (either lift key: Z / X on the keyboard, the lift buttons on a pad).
## The same online and on one machine; read it every tick and act on the press edge.
func action(slot: int) -> bool:
	return simulation.mode_action(slot)

## The slot's latest network input on the authority ({} in the local game; prefer action() and position()).
func input(slot: int) -> Dictionary:
	return simulation.player_input(slot)

## The slot holding this slot's character (a grab), -1 for none.
func held_by(slot: int) -> int:
	return simulation.team.held_by(slot)

## The yard's loose props (players/prop_sim.gd: positions, velocities, held_by per prop, reset()).
func props():
	return simulation.team.props

## Moves a slot's character to `at` facing `yaw` (released if held); its owner is told through the snapshot.
func send_to(slot: int, at: Vector3, yaw := 0.0) -> void:
	simulation.team.send_to(slot, at, yaw)

## Keeps a slot's character within `radius` m of `at` on x/z (the show's podium): on the authority an owner pose further away is dropped, so a client
## that walks off stays where it is; strays(slot) counts the dropped poses (the rules then send_to the slot back so its client moves too). Ends with
## the round (release_holds, or the next epoch). `rise` (default: none) also drops a pose more than that far over or under `at` (a stage round's card: no jump). No effect in the local game,
## where the one machine decides itself.
func hold(slot: int, at: Vector3, radius: float, rise := INF) -> void:
	simulation.hold_courier(slot, at, radius, rise)

func strays(slot: int) -> int:
	return simulation.take_strays(slot)

func release_holds() -> void:
	simulation.release_holds()

# ------------------------------------------------------------------ the yard (network/walk_in_lobby.gd, lobby_space.gd)

## The yard floor's centre, world space.
func yard_center() -> Vector3:
	return WalkInLobby.ORIGIN

## The yard inside its walls, world XZ (x = world x, y = world z).
func yard_rect() -> Rect2:
	var local := WalkInLobby.interior_rect()
	return Rect2(local.position + Vector2(WalkInLobby.ORIGIN.x, WalkInLobby.ORIGIN.z), local.size)

func floor_y() -> float:
	return WalkInLobby.FLOOR_Y

## The yard spot of a slot (where the round starts it).
func spot(slot: int) -> Vector3:
	return WalkInLobby.spawn(slot, count)

# ------------------------------------------------------------------ level rounds (the show, modes/show/rules.gd)

## Starts a level-phase round on level `level` (0-based): the shell plays it in "show" mode (no painting, no balloon; contact and
## grabs on), a new epoch puts everybody on the start ring and the level clock at zero. The rules decide from positions.
## `out` lists the slots that are out of the show: they are not simulated in the round (no courier, nothing to collide with), they only watch.
func begin_level(level: int, out := []) -> void:
	var active := []
	for slot in simulation.carrier_count: active.append(slot < count and not out.has(slot))
	simulation.set_course_plan(CourseSection.plan(str(simulation.course_plan.get("course", CourseSection.ADVENTURE)), level, CourseSection.SHOW))
	simulation.configure_phase("level", active)

## A player is out of the round: its courier stays where it is, hidden and no longer simulated (no input, no contact, nobody collides with it or targets it). The camera of
## its player follows somebody else (modes/show/view.gd `spectate_slot`). The next `begin_level` brings it back unless it is listed in `out`.
func retire(slot: int) -> void:
	if slot >= 0 and slot < count: simulation.drop_slot(slot)

## The podium: a new epoch on the level as it stands (its clock runs on); only the slots not in `out` are simulated again (an eliminated player who earned a podium spot comes back), the rest watch.
func begin_podium(out: Array) -> void:
	var active := []
	for slot in simulation.carrier_count: active.append(slot < count and not out.has(slot))
	simulation.configure_phase("level", active, true)

func levels():
	return simulation.level_world

## Seconds on the level clock (the hazards' clock: a start gate opens at its own time).
func level_clock() -> float:
	return simulation.level_world.clock

## "goal" | "kill" | "" for a slot's character in level `level` (a courier below the level's void counts as "kill").
func zone(slot: int, level: int) -> String:
	return simulation.level_world.zone_at(level, position(slot))

## "zap" | "burn" | "" (a laser or a fire jet touches the character).
func scorch(slot: int, level: int) -> String:
	return simulation.level_world.scorch_at(level, position(slot))

## The step tiles (levels/step_tiles.gd) of level `level`: the steps a round of `players` starts with (one byte per tile; empty when the
## level has none), the tiles the slot's character stands on, and putting the rules' steps into the level world (what the colliders follow).
func tile_start(level: int, players: int) -> PackedByteArray:
	return simulation.level_world.tile_start(level, players)

func tiles_under(slot: int, level: int) -> Array:
	return simulation.level_world.tiles_under(level, position(slot))

func apply_tiles(level: int, steps: PackedByteArray) -> void:
	simulation.level_world.set_tile_steps(level, steps)

## The step byte a step writes now, and whether a tile's byte may be settled (a wrapped level's bytes are a clock modulo a window, levels/step_tiles.gd).
func tile_stamp(level: int) -> int:
	return simulation.level_world.tile_stamp(level)

func tile_settled(level: int, index: int) -> bool:
	return simulation.level_world.tile_settled(level, index)

## The checkpoint (index in the level's list) the character stands in, -1 for none.
func checkpoint_at(slot: int, level: int) -> int:
	return simulation.level_world.checkpoint_at(level, position(slot))

## Counts the zap or burn word over a scorched character.
func note_scorch(slot: int, kind: String) -> void:
	simulation.team.note_scorch(slot, kind)

## Puts a character back on its spot at checkpoint `checkpoint` of level `level` (-1 = the start ring), facing along the course.
func respawn(slot: int, level: int, checkpoint: int) -> void:
	var spot: Dictionary = simulation.level_world.team_start(level, maxi(simulation.active_count(), 1), checkpoint)
	var points: Array = spot.pos
	var place: int = simulation.start_rank(slot)
	send_to(slot, (points[place] if place >= 0 and place < points.size() else spot.spot) + Vector3.UP * 0.05, float(spot.yaw))

## The item boxes of level `level` (world feet spots on the floor; the show's items, modes/show/items/, docs/items.md), empty for none.
func item_boxes(level: int) -> PackedVector3Array:
	return simulation.level_world.item_boxes(level)

## The height of the floor under `feet` on level `level` (world), NAN when there is none.
func floor_at(level: int, feet: Vector3) -> float:
	return simulation.level_world.floor_y(level, feet)

## Presses of the ITEM or GRAB button of a slot so far (`key` "item" | "grab"): act on the change, as the show's items do. The owner's counters online, the local devices on one machine.
func presses(slot: int, key: String) -> int:
	return simulation.press_count(slot, key)

## GHOST PIGEON (modes/show/pigeon/): how the slot's player steers its bird now, {move: Vector2 (world x/z, the camera's way, length up to 1), climb: -1 (DASH held) .. 1 (JUMP held)}.
## The owner's input on the authority, the local devices in the local game.
func pigeon_input(slot: int) -> Dictionary:
	return simulation.pigeon_input(slot)

## The way the slot's character faces (radians, 0 faces -Z) and how it moves (m/s), as the authority last heard it (the local game: as simulated).
func yaw(slot: int) -> float:
	return simulation.actors[slot].rotation.y if slot >= 0 and slot < count else 0.0

func velocity(slot: int) -> Vector3:
	return simulation.actors[slot].velocity if slot >= 0 and slot < count else Vector3.ZERO

## Metres along the level's route to the character's nearest point (how far it got), and the route's length.
func progress(slot: int, level: int) -> float:
	return simulation.level_world.route_progress(level, position(slot))

func route_length(level: int) -> float:
	return simulation.level_world.route_length(level)

## Where first, second and third stand (world feet): on the pedestals of the podium room (style/podium_room.gd), which stands far from every level, whatever level the show ended on.
func podium(_level: int) -> Array:
	return PodiumRoom.spots()
