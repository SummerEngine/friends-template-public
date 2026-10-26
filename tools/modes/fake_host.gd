extends "res://modes/mode_host.gd"
## A ModeHost without a shell for the mode checks (docs/modes.md "Checks"): the script sets where each player stands, which
## buttons are held and who holds whom; send_to moves the player at once and is recorded. The cast comes from TeamCast as usual
## (a check may TeamCast.override a cast of its own).
const PropSim := preload("res://players/prop_sim.gd")
const LobbySpace := preload("res://lobby_space.gd")

var positions: Array = [] ## slot -> Vector3 (feet)
var actions: Array = [] ## slot -> bool
var holders: Array = [] ## slot -> the slot holding it, -1
var actives: Array = [] ## slot -> bool
var retired: Array = [] ## slots out of the round (retire, begin_level's `out`)
var sent: Array = [] ## [slot, at, yaw] of every send_to
var holds: Dictionary = {} ## slot -> {at, radius, rise} of every hold (podium, a stage round's card) until release_holds
var _props

func _init(round_seats: Array, seed_value := 1) -> void:
	super(null, round_seats, seed_value)
	_props = PropSim.new(LobbySpace.loose_props())
	for slot in count:
		positions.append(spot(slot))
		actions.append(false)
		holders.append(-1)
		actives.append(true)

func active(slot: int) -> bool:
	return slot >= 0 and slot < count and bool(actives[slot])

func position(slot: int) -> Vector3:
	return positions[slot] if slot >= 0 and slot < count else Vector3.ZERO

func action(slot: int) -> bool:
	return slot >= 0 and slot < count and bool(actions[slot])

func input(_slot: int) -> Dictionary:
	return {}

func held_by(slot: int) -> int:
	return int(holders[slot]) if slot >= 0 and slot < count else -1

func props():
	return _props

func send_to(slot: int, at: Vector3, yaw := 0.0) -> void:
	if slot < 0 or slot >= count: return
	positions[slot] = at
	holders[slot] = -1
	sent.append([slot, at, yaw])

func hold(slot: int, at: Vector3, radius: float, rise := INF) -> void:
	holds[slot] = {"at": at, "radius": radius, "rise": rise}

func strays(_slot: int) -> int:
	return 0

func release_holds() -> void:
	holds.clear()

## The round's players: everybody but `out` (what begin_level does with its `out`).
func bench(out: Array) -> void:
	for slot in count: actives[slot] = not out.has(slot)
	retired = out.duplicate()

## A player is out of the round: not active any more, its courier stays where it is.
func retire(slot: int) -> void:
	if slot < 0 or slot >= count: return
	actives[slot] = false
	if not retired.has(slot): retired.append(slot)

func begin_podium(out: Array) -> void:
	bench(out)

## Walks a slot `step` metres toward `target` (XZ), keeping its height.
func walk(slot: int, target: Vector3, step: float) -> void:
	var at: Vector3 = positions[slot]
	var to := Vector3(target.x - at.x, 0.0, target.z - at.z)
	positions[slot] = at + (to if to.length() <= step else to.normalized() * step)
