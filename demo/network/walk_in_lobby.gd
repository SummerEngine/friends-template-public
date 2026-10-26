extends RefCounted
## Shared spatial contract for the dedicated lobby yard (docs/dedicated-lobby-design.md).
## Authority occupancy, client markers, room collision and spawning use these values.
## Pure data and math: the Android standalone lab can preload this module.
const CourseSection = preload("res://course_section.gd")
const TeamCast = preload("res://style/team_cast.gd")
const Modes = preload("res://modes/modes.gd")
const RoundList = preload("res://modes/lineup/round_list.gd")
const Party = preload("res://style/party_look.gd")

## Seconds between a PLAY press with everybody on one pad and the round: none, PLAY starts it at once (the press is the
## consent).
const COUNTDOWN := 0.0
## Standing on one pad together never starts the round by itself: somebody on it presses PLAY (Enter, pad Y, the PLAY button
## on a phone; online the client sends {"c": "play"}). The prompt the clients show meanwhile names that input (client/match_presenter.gd play_prompt).
## A player is on a pad within ENTER_RADIUS of its centre (horizontal) and stays on it until
## EXIT_RADIUS: standing on the painted edge does not flicker the countdown.
const ENTER_RADIUS := 1.4
const EXIT_RADIUS := 1.75
## Vertical window around the pad's floor height: a jump on the pad keeps the player on it.
const BELOW := 0.7
const ABOVE := 2.6
## Painted ring radius (visual): between the two radii above.
const RING_RADIUS := 1.55
## Lobby camera heading: both pads in front.
const CAMERA_YAW := 0.0
## This room is separate from the levels. Values below are world-space unless marked.
const ORIGIN := Vector3(0.0, 512.0, 0.0)
const FLOOR_Y := 512.0
const SPAWN_CENTER := ORIGIN + Vector3(0.0, 0.25, 1.0)
const SPAWN_RADIUS := 1.5
## Local XZ bounds at the inner wall faces; walls extend upward 5.65 m (lobby_space.gd). The yards of the single-circle minigames are 34.6 m wide (HALF_WIDTH 17.3) and 24 m deep (-14 to 10).
## The show's yard is cut to its circles (`interior_rect()`): the walls stand SIDE_MARGIN m outside the outermost ring (and no closer than MIN_HALF_WIDTH, the room the spawn seats and the
## wardrobe's ring need), the tile grid of lobby/lobby_kit.gd rounds the width up to a whole even number of tiles, the north wall stands behind THE SHOW's pylon (SHOW_NORTH).
const HALF_WIDTH := 17.3
const YARD_NORTH := -14.0
const YARD_SOUTH := 10.0
const SHOW_NORTH := -10.9
const SIDE_MARGIN := 0.9
const MIN_HALF_WIDTH := 9.3
const TILE_PITCH := 1.65 ## the lobby kit's tile pitch (lobby_kit.gd TILE + BlockKit.GROOVE) = half the circles' pitch
const WALL_DEPTH := 0.9 ## the walls' thickness (lobby_space.gd WALL_THICKNESS)
const GRID_RIM := 0.055 ## half a groove: the grid's width is NX * TILE_PITCH + 0.11

## The wardrobe ring's middle in the yard (character/wardrobe/): the single-circle yards keep it in the middle of the west half; the show's yard has the circles' rows there, so its ring stands in the
## south-west corner (WARDROBE_INSET m from the west wall) by the mirror board on the west wall (lobby_space.gd props).
const WARDROBE_CENTER := Vector3(-7.5, 0.0, 0.5)
const WARDROBE_INSET := 2.25
const WARDROBE_Z_SHOW := 4.6
static func wardrobe_center() -> Vector3:
	return Vector3(-(yard_half_width() - WARDROBE_INSET), 0.0, WARDROBE_Z_SHOW) if show_yard() else WARDROBE_CENTER

## The wardrobe nook of the show's yard: the ring stands in a three-sided booth on the west wall, the wall behind it and two low cushion wings (NOOK_DEPTH m out from the wall, NOOK_THICK thick, NOOK_HIGH
## tall: the camera sits over them) either side, NOOK_SIDE m from the ring's middle: the ring, its sign's pillar and the mirror stand between them, the yard's side is open. They are collision too (lobby_space.gd
## props) and look (lobby/lobby_kit.gd). Yard-local boxes {name, center, size}; none for the single-circle yards.
const NOOK_DEPTH := 3.3
const NOOK_SIDE := 3.15
const NOOK_THICK := 0.5
const NOOK_HIGH := 1.0
static func nook_wings() -> Array:
	var wings: Array = []
	if not show_yard(): return wings
	var ring := wardrobe_center()
	for side: float in [-1.0, 1.0]:
		wings.append({"name": "wardrobe_wing_%s" % ("n" if side < 0.0 else "s"), "center": Vector3(-yard_half_width() + NOOK_DEPTH * 0.5 - 0.015, NOOK_HIGH * 0.5, ring.z + side * NOOK_SIDE), "size": Vector3(NOOK_DEPTH + 0.03, NOOK_HIGH, NOOK_THICK)})
	return wings

## The yard's half width: the single-circle yards' HALF_WIDTH, or the show's, cut to its circles (see above). The tile count is the grid's (an even number: a groove on the middle line).
static func yard_half_width() -> float:
	return HALF_WIDTH if not show_yard() else float(show_tiles_x()) * TILE_PITCH * 0.5 + GRID_RIM - WALL_DEPTH

static func show_tiles_x() -> int:
	var reach := 0.0
	for entry: Dictionary in shown_pads():
		reach = maxf(reach, absf((entry.center as Vector3).x - ORIGIN.x) + maxf(RING_RADIUS, (entry.get("board", Vector2.ZERO) as Vector2).x * 0.5))
	var wanted := maxf(reach + SIDE_MARGIN, MIN_HALF_WIDTH) + WALL_DEPTH - GRID_RIM
	var tiles := int(ceil(wanted / (TILE_PITCH * 0.5) - 0.001))
	return tiles + tiles % 2

## The play rectangle inside the walls (local XZ).
static func interior_rect() -> Rect2:
	var half := yard_half_width()
	var north := SHOW_NORTH if show_yard() else YARD_NORTH
	return Rect2(-half, north, half * 2.0, YARD_SOUTH - north)

const PADS := [
	{"course": CourseSection.ADVENTURE, "center": ORIGIN + Vector3(-4.5, 0.0, -6.0), "title": "TIME ATTACK", "subtitle": "5 random levels · total time", "color": Color("2fa35b")},
	{"course": CourseSection.CHALLENGE, "center": ORIGIN + Vector3(4.5, 0.0, -6.0), "title": "ENDLESS", "subtitle": "Random levels until you leave", "color": Color("e0582b")},
]

## Yard spots of up to ten seats, all facing the pads: seats 0 and 1 left and right of the spawn centre, the others in rows
## beside and behind them. Count is accepted by common callers; diagnostics with one player use the left seat.
const SPOTS := [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(-3.0, 0.0), Vector2(3.0, 0.0), Vector2(-1.0, 1.7), Vector2(1.0, 1.7),
	Vector2(-3.0, 1.7), Vector2(3.0, 1.7), Vector2(-1.0, 3.4), Vector2(1.0, 3.4)]
static func spawn(slot: int, _count: int = 2) -> Vector3:
	var spot: Vector2 = SPOTS[posmod(slot, SPOTS.size())] * SPAWN_RADIUS
	return SPAWN_CENTER + Vector3(spot.x, 0.0, spot.y)

## PADS with the title and subtitle an authored course gives its two orders (course_section.gd orders()).
static func pads() -> Array:
	var orders := CourseSection.orders()
	if orders.is_empty(): return PADS
	var result: Array = []
	for entry: Dictionary in PADS:
		var merged := entry.duplicate()
		var order: Dictionary = orders.get(entry.course, {})
		if order.has("title"): merged.title = str(order.title)
		if order.has("subtitle"): merged.subtitle = str(order.subtitle)
		result.append(merged)
	return result

## One game shows one mode (AGENTS.md): the one pad drawn and stood on is the cast's `run` (TeamCast.run(): TIME ATTACK by
## default, or ENDLESS). PADS, pads(), pad() and center() still know both, for the course data and the checks.
static func shown_course() -> String:
	return CourseSection.CHALLENGE if TeamCast.run() == "endless" else CourseSection.ADVENTURE

## The show's lobby (docs/party-show.md "Pick a round"): THE SHOW and a circle per listed round (modes/lineup/lineup.json, the polished rounds), in two staggered rows of round circles, THE SHOW's
## circle in the middle of the rear row with the highest board and the rear row two rounds wider for every four rounds (8 rounds: a front row of 4, a rear row of 2 + THE SHOW + 2; 18
## rounds: 10 and 8 + THE SHOW). The rear circles stand in the gaps of the front row (pitch 3.3 m, a circle is 3.1 m across): with an even number of rounds the two rows stagger, with an odd number a front
## circle stands in front of a rear one. Every signboard stands behind its circle on posts above the head of the player on it (the shoulder camera sits behind and about 3.4 m up: a head covers a
## board's first 1.4 m at most); the front boards are narrower than the pitch (2.2 m of 3.3), so the camera, which looks over the player's right shoulder, sees a player on a rear circle through
## the gap; the rear boards stand above the front ones, with the camera's sight line to their lower edge clear of the front boards' top from anywhere in the yard: all of them read from the spawn and
## from any circle (tools/party_look_check.gd walks the sight lines). The yard is cut to the rows (`interior_rect()`).
const FRONT_Z := -1.8
const REAR_Z := -5.8
const PITCH := 3.3
const BOARD_FRONT := Vector2(2.2, 1.4) ## a front circle's sign plate (title, rule line in up to two lines)
const BOARD := Vector2(3.0, 1.4) ## a rear circle's
const BOARD_BIG := Vector2(5.0, 3.5) ## THE SHOW's shield (style/goal_sign.gd family): its bounding box, the V's tip at SHOW_LIFT
const FRONT_LIFT := 1.5 ## height of the sign plate's lower edge over the floor: on a masonry pillar of whole courses (lobby/lobby_sign.gd)
const REAR_LIFT := 3.5
const SHOW_LIFT := 4.0
const KIND_RULES := {"race": "RACE TO THE GOAL", "survival": "STAY ON THE FLOOR TO THE END", "final": "CLIMB TO THE CROWN"}
const SOLO_NOTE := "NEEDS 2+ PLAYERS"

## How many humans play on this machine (the local game sets it): the circles of a round that needs more players say so.
static var local_players := 2
static var _shown_key := ""
static var _shown: Array = []

## The one shown pad; a minigame (the cast's mode, modes/modes.gd) puts its own title and subtitle on it. The show also shows a circle per round.
static func shown_pads() -> Array:
	var mode := Modes.current()
	var key := "%s|%d|%d|%d|%s" % [mode, CourseSection.level_count(), local_players, 1 if TeamCast.run() == "endless" else 0, str(TeamCast.brand_colors())]
	if key == _shown_key: return _shown
	_shown = _build_shown(mode)
	_shown_key = key
	return _shown

static func _build_shown(mode: String) -> Array:
	var course := shown_course()
	var shown := pads().filter(func(entry: Dictionary) -> bool: return entry.course == course)
	if Modes.is_minigame(mode) and not shown.is_empty():
		var entry: Dictionary = (shown[0] as Dictionary).duplicate()
		var info := Modes.info(mode)
		entry.title = str(info.get("title", entry.title))
		entry.subtitle = str(info.get("subtitle", entry.subtitle)) + ("  ·  %d+ players" % Modes.min_players(mode) if Modes.min_players(mode) > 2 else "")
		shown = [entry]
		if mode == "show": shown = _show_pads(entry)
	return shown

## THE SHOW first (the circle that plays the whole show), then one circle per listed round (modes/lineup/round_list.gd), races first, the final last: the first ones in the front row, the rest in the
## rear row on either side of THE SHOW (in order, left to right). Rows keep their heights for any count, the yard follows the widest row (round_pick_check.gd fails while a circle stands outside it).
static func _show_pads(whole: Dictionary) -> Array:
	var rounds: Array = []
	for kind: String in ["race", "survival", "final"]: rounds.append_array(RoundList.entries().filter(func(row: Dictionary) -> bool: return row.kind == kind))
	var rear_count := 1 + 2 * int(rounds.size() * 0.25) # THE SHOW and a pair of rounds for every four
	var front_count := rounds.size() - (rear_count - 1)
	var result: Array = []
	var middle := int(rear_count * 0.5)
	var show_entry := whole.duplicate()
	show_entry.center = _row_spot(middle, rear_count, REAR_Z)
	show_entry.board = BOARD_BIG
	show_entry.lift = SHOW_LIFT
	show_entry.color = (Party.palette().signs as Dictionary).show
	show_entry.pick = RoundList.SHOW
	show_entry.kind = "show"
	result.append(show_entry)
	for index in front_count:
		result.append(_round_pad(rounds[index], _row_spot(index, front_count, FRONT_Z), FRONT_LIFT, BOARD_FRONT))
	for index in rear_count - 1:
		var column := index if index < middle else index + 1
		result.append(_round_pad(rounds[front_count + index], _row_spot(column, rear_count, REAR_Z), REAR_LIFT, BOARD))
	return result

## Circle `index` of a row of `count` centred on the yard's middle line.
static func _row_spot(index: int, count: int, z: float) -> Vector3:
	return ORIGIN + Vector3((float(index) - (count - 1) * 0.5) * PITCH, 0.0, z)

static func _round_pad(row: Dictionary, centre: Vector3, lift: float, board: Vector2) -> Dictionary:
	var rule := str(row.rule) if str(row.rule) != "" else str(KIND_RULES.get(row.kind, ""))
	var needs_more: bool = not bool(row.solo) and local_players < 2
	return {"course": str(row.id), "center": centre, "title": str(row.title), "subtitle": SOLO_NOTE if needs_more else rule, "color": (Party.palette().signs as Dictionary)[str(row.kind)],
		"board": board, "lift": lift, "pick": str(row.id), "kind": str(row.kind)}

## Whether this is the show's yard (a circle per round, docs/party-show.md "Pick a round"): it wears the lobby kit (lobby/lobby_kit.gd) and has no playground, props or
## furniture; the yards of the single-circle minigames keep theirs.
static func show_yard() -> bool:
	return shown_pads().size() > 1

static func pad(course: String) -> Dictionary:
	for entry: Dictionary in shown_pads():
		if entry.course == course: return entry
	for entry: Dictionary in pads():
		if entry.course == course: return entry
	return {}

static func center(course: String) -> Vector3:
	return pad(course).get("center", Vector3.ZERO)

static func title(course: String) -> String:
	for entry: Dictionary in shown_pads():
		if entry.course == course: return str(entry.title)
	return str(pad(course).get("title", ""))

## The pad a position stands on ("" for none). `previous` is the pad it stood on last time: it
## is kept up to EXIT_RADIUS (hysteresis), any other pad needs ENTER_RADIUS.
static func zone_at(position: Vector3, previous := "") -> String:
	if not position.is_finite(): return ""
	for entry: Dictionary in shown_pads(): # the hidden pad is not there
		var middle: Vector3 = entry.center
		var height := position.y - middle.y
		if height < -BELOW or height > ABOVE: continue
		var reach := EXIT_RADIUS if entry.course == previous else ENTER_RADIUS
		if Vector2(position.x - middle.x, position.z - middle.z).length() <= reach: return str(entry.course)
	return ""

## The course every listed player stands on, "" unless there are at least two and all agree.
## `zones` holds one entry per joined player ("" = not on a pad or not eligible).
static func shared_pick(zones: Array) -> String:
	if zones.size() < 2: return ""
	var first := str(zones[0])
	if first == "": return ""
	for zone: Variant in zones:
		if str(zone) != first: return ""
	return first

## World-space move input (x, z) that walks a character from `position` to the middle of a pad;
## zero once there. Dev automation and selftests use it; players walk with their own input.
static func steer(position: Vector3, course: String) -> Vector2:
	var target := center(course)
	var to := Vector2(target.x - position.x, target.z - position.z)
	if to.length() < 0.35: return Vector2.ZERO
	return to.normalized() * clampf(to.length(), 0.5, 1.0)

## Same, toward any point (walking off a pad back to the spawn).
static func steer_to(position: Vector3, target: Vector3) -> Vector2:
	var to := Vector2(target.x - position.x, target.z - position.z)
	if to.length() < 0.35: return Vector2.ZERO
	return to.normalized() * clampf(to.length(), 0.5, 1.0)
