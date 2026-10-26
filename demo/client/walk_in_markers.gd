extends Node3D
const _DevLap := preload("res://dev_env.gd")
## Walk-in props in the dedicated lobby yard (docs/dedicated-lobby-design.md), built from the shared definition in network/walk_in_lobby.gd: per circle a press plate in the floor
## (lobby/pick_plate.gd, the pad family of the race levels) and its sign behind it on masonry, facing the lobby camera (lobby/lobby_sign.gd: round signs in the show's UI style,
## THE SHOW as the GOAL sign's shield on a pylon).
## - The signs are one-sided: seen from behind (a camera orbiting past a sign from its circle) only the masonry remains, so a sign can never hide the own player.
## - Lamps, one per shown player, are little domes on the collar of the circle, lit in that player's colour while the authority sees them on it (match.zones, from accepted owner positions).
## - The own circle presses at once from the local owner position (no round trip); the counting circle pulses. The countdown number itself is only the HUD status line ("Adventure in 3").
## No collision anywhere: the props never touch play. Shown only in the lobby.
const WalkInLobby := preload("res://network/walk_in_lobby.gd")
const PickPlate := preload("res://lobby/pick_plate.gd")
const LobbySign := preload("res://lobby/lobby_sign.gd")

var _pads := {} ## course -> {root, plate, lit, counting}
var local_zone := "" ## pad under the local player, from its own position (hysteresis as the authority)
var _clock := 0.0
var _settled := false ## the plates have been put in their state once without easing (the first `present` of a shown lobby)

## Builds the props. The yard is flat (its floor is y = WalkInLobby.FLOOR_Y): every circle stands exactly on the tiles (`run.floor_at` adds a lift of 2 cm for paint, which would lift a plate off them).
func build(_run) -> void:
	name = "WalkInLobby"
	var index := 0
	for entry: Dictionary in WalkInLobby.shown_pads():
		_pads[entry.course] = _build_pad(entry, entry.center, index)
		index += 1
	LobbySign.build_rear(self, WalkInLobby.shown_pads())
	set_shown(false)

func set_shown(on: bool) -> void:
	if visible != on: visible = on
	set_process(on)
	if not on:
		local_zone = ""
		_settled = false

## `model` is MatchPresenter.lobby_model(); `local_position` the local owner's feet.
func present(model: Dictionary, local_position: Vector3) -> void:
	local_zone = WalkInLobby.zone_at(local_position, local_zone)
	for pad: Dictionary in model.get("pads", []):
		var parts: Dictionary = _pads.get(pad.course, {})
		if parts.is_empty(): continue
		parts.counting = bool(pad.counting)
		parts.lit = local_zone == pad.course or not (pad.occupants as Array).is_empty()
		_sync_lamps(parts, model.get("lamps", []), pad.occupants)
	if not _settled:
		_settled = true
		_paint(0.0)

func _process(delta: float) -> void:
	var _lap := _DevLap.now()
	_process_timed(delta)
	_DevLap.lap("walk_in_markers.p", _lap)

func _process_timed(delta: float) -> void:
	_clock += delta
	_paint(delta)

## Every plate in its state: resting, pressed and lit while somebody (or this player) stands on it, pulsing while its countdown runs.
func _paint(delta: float) -> void:
	for parts: Dictionary in _pads.values():
		(parts.plate as PickPlate.Plate).paint(bool(parts.get("lit", false)), bool(parts.get("counting", false)), _clock, delta)

func _sync_lamps(parts: Dictionary, lamps: Array, occupants: Array) -> void:
	var on := {}
	for member: Dictionary in occupants: on[int(member.seat)] = member.color
	var colours: Array = []
	for lamp: Dictionary in lamps: colours.append(on.get(int(lamp.seat), null))
	(parts.plate as PickPlate.Plate).set_lamps(colours)

# ------------------------------------------------------------------ construction

func _build_pad(entry: Dictionary, at: Vector3, index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = str(entry.title).capitalize()
	root.position = at
	add_child(root)
	var plate := PickPlate.build(root, WalkInLobby.RING_RADIUS, str(entry.get("kind", "")))
	LobbySign.build(root, entry, 11 + index * 13)
	return {"root": root, "plate": plate, "lit": false, "counting": false}
