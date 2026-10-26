extends RefCounted
## The poster doors of POSTER RUSH (docs/level-format.md, "Poster doors"): an obstacle slot that carries `"door": "open" | "solid" | "torn"`.
## The board is a decor frame (SlotFrames): a `solid` door is a PROBLEM poster (a wall: a hidden block a little behind it), an `open` one is the brand's LOGO
## poster (nothing behind it, it tears), and a `torn` one is a logo poster that starts out already burst (the idea shown once). A door may carry
## `"ride": "<id>"`, the id of a `slide` hazard: the door then moves with that hazard (the hazard's parts are the hidden blocks of the solid doors beside it),
## so the door's place is its listed place plus the hazard's travel at the level clock. Pure functions of level-local positions and the clock, no nodes,
## no state: every machine that asks gets the same answer, so a burst, a thud and the push-back never need a message. The level world (levels/level_world.gd)
## keeps the small per-courier memories and the signals; the look (style/poster_door_look.gd) is client only.
const Hazards := preload("res://levels/hazards.gd")
const OPEN := "open"
const SOLID := "solid"
const TORN := "torn"
const KINDS := [OPEN, SOLID, TORN]
const CENTRE := 0.9 ## m, a courier's centre over its feet (the point the crossing test follows)
const RADIUS := 0.35 ## the courier capsule
const BLOCK_GAP := 0.125 ## m the hidden block's front face stands behind the board's plane (the level files' convention, level_lint checks it)
const TOUCH := 0.04 ## m of reach on top of the block for a touch (a tick of the walk is 0.08)
const TOUCH_SIDE := 0.2 ## m a courier's side may overlap the door's edge and still touch its block
const LEAVE := 0.15 ## m further out than the touch band, a courier has left the door (a new touch counts)
const MAX_STEP := 2.5 ## m: a bigger jump between two samples is a respawn or a send, not a run
const PUSH := 3.6 ## m/s: the solid door's push-back (a hazard's bonk throws 8.5 to 15)
const PUSH_UP := 2.2 ## m/s of hop with it
const NEAR := 4.0 ## m: a door whose plane is farther than this from a courier (along the door's normal) is not asked at all (a hall has dozens of doors)

static var _scratch := Hazards.Pose.new()

## The doors of a level's data (Data.parse): [{index (the slot's place in `slots`), id, kind, p (at the hazard's rest pose for a riding door), normal, right,
## half, bottom, top, ride (the normalized `slide` hazard the door rides on, {} for a door that stands still)}], level-local.
static func list(data: Dictionary) -> Array:
	var doors: Array = []
	var slots: Array = data.get("slots", [])
	var rides := {}
	for h: Dictionary in data.get("hazards", []):
		if str(h.get("k", "")) == "slide" and str(h.get("id", "")) != "": rides[str(h.id)] = h
	for index in slots.size():
		var slot: Dictionary = slots[index]
		var kind := str(slot.get("door", ""))
		if kind == "": continue
		var size: Vector2 = slot.size
		var basis := Basis(Vector3.UP, float(slot.yaw))
		var at: Vector3 = slot.p
		doors.append({"index": index, "id": str(slot.id), "kind": kind, "p": at, "normal": basis * Vector3.BACK, "right": basis * Vector3.RIGHT,
			"half": size.x * 0.5, "bottom": at.y - size.y * 0.5, "top": at.y + size.y * 0.5, "ride": rides.get(str(slot.get("ride", "")), {})})
	return doors

## How far a door has moved from its listed place at level clock `t` (level-local; zero for a door that stands still): the travel of the slide hazard it rides.
static func travel(door: Dictionary, t: float) -> Vector3:
	var ride: Dictionary = door.ride
	if ride.is_empty(): return Vector3.ZERO
	Hazards.pose(ride, t, _scratch)
	return _scratch.position - (ride.pivot as Vector3)

## False when the courier at `feet` (level-local) is farther than NEAR from the door's plane: it can neither touch nor cross the door.
static func near(door: Dictionary, feet: Vector3) -> bool:
	return absf(((feet - (door.p as Vector3)).dot(door.normal))) <= NEAR

## A courier's feet (level-local) in a door's own frame: x across (right), y up, z in front of the board (the side the courier comes from). `shift`: the door's
## travel from its listed place (travel()).
static func frame(door: Dictionary, feet: Vector3, shift := Vector3.ZERO) -> Vector3:
	var rel: Vector3 = feet - ((door.p as Vector3) + shift)
	return Vector3(rel.dot(door.right), feet.y, rel.dot(door.normal))

## True when the courier moved through the door's plane inside its opening (width and height) between `from` and `to` (level-local feet); `shift_from` and
## `shift_to`: the door's travel (travel()) at the two moments.
static func crossed(door: Dictionary, from: Vector3, to: Vector3, shift_from := Vector3.ZERO, shift_to := Vector3.ZERO) -> bool:
	if from.distance_to(to) > MAX_STEP: return false
	var a := frame(door, from, shift_from)
	var b := frame(door, to, shift_to)
	if (a.z > 0.0) == (b.z > 0.0): return false # both on one side (a point exactly on the plane counts as the far side: one crossing, not two)
	var t := clampf(a.z / (a.z - b.z), 0.0, 1.0)
	var at := a.lerp(b, t)
	return absf(at.x) <= float(door.half) + RADIUS * 0.5 and at.y + CENTRE >= float(door.bottom) and at.y + CENTRE <= float(door.top) + 0.2

## True while the courier presses on a solid door: its capsule against the hidden block's face (front side only). `shift`: the door's travel (travel()).
static func touching(door: Dictionary, feet: Vector3, band := 0.0, shift := Vector3.ZERO) -> bool:
	if str(door.kind) != SOLID: return false
	var at := frame(door, feet, shift)
	var reach := BLOCK_GAP + RADIUS + TOUCH + band
	return at.z > 0.0 and at.z <= reach and absf(at.x) <= float(door.half) + TOUCH_SIDE + band * 0.5 \
		and at.y + CENTRE >= float(door.bottom) and at.y <= float(door.top)

## The push-back a touch gives: away from the board, a little up (a launch: {v, override_xy, override_z}).
static func push(door: Dictionary) -> Dictionary:
	var away: Vector3 = door.normal
	return {"v": Vector3(away.x, 0.0, away.z).normalized() * PUSH + Vector3.UP * PUSH_UP, "override_xy": true, "override_z": true}
