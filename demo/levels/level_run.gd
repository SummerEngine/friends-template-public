extends RefCounted
## One run of the level game (docs/levels-mode.md): the sequence of levels a lobby circle starts and what has been cleared so far.
## Pure rules, shared by the authority (network/match_controller.gd) and the local flow (client/local_level_flow.gd); the levels themselves
## are the level files (levels/level_world.gd, course_section.gd level_count()).
##   time_attack  TIME_ATTACK_COUNT random, different levels in a row; the run ends after the last one, the total time counts
##   endless      random levels (never the same twice in a row) until the players end the run; the number cleared counts
## A balloon run is a run of ROOMS instead: every balloon level in file order (ROOM 01, ROOM 02, ...), the time attack ends after the last
## room, the endless run starts over at ROOM 01.
const CourseSection := preload("res://course_section.gd")
const TIME_ATTACK := "time_attack"
const ENDLESS := "endless"
const TIME_ATTACK_COUNT := 5
## Seconds the LEVEL CLEARED card stays up before the next level starts.
const CLEARED_SECONDS := 2.6

var mode := TIME_ATTACK
var level_count := 0
var pool: Array = []     ## level indices the run may draw from (all levels when empty)
var queue: Array = []    ## level indices (0-based) of the run so far; queue[position] is the level being played
var position := 0
var times: Array = []    ## seconds of every cleared level, in order
var breaks := 0          ## glass breaks (carry) or pops (balloon) over the cleared levels
var rooms := false       ## a balloon run: the pool in file order, not a random draw
## course_section.gd CARRY | BALLOON: what the run plays and how the results word it. Set before the first level is cleared; BALLOON
## turns the run into the room run.
var play_mode := "carry":
	set(value):
		play_mode = value
		if value == CourseSection.BALLOON and times.is_empty(): _start_rooms()
var finished := false    ## a time attack whose last level is cleared
var _bag: Array = []
var _random := RandomNumberGenerator.new()

## The mode a lobby circle starts: the Adventure pad is the time attack, the Challenge pad the endless run (the wire ids of course_section.gd).
static func mode_for(course: String) -> String:
	return ENDLESS if course == CourseSection.CHALLENGE else TIME_ATTACK

func _init(course_id: String, levels_in_course: int, seed_value := -1, drawable: Array = []) -> void:
	mode = mode_for(course_id)
	level_count = maxi(levels_in_course, 1)
	pool = drawable.duplicate() if not drawable.is_empty() else range(level_count)
	if seed_value >= 0: _random.seed = seed_value
	else: _random.randomize()
	if mode == TIME_ATTACK:
		var order: Array = pool.duplicate()
		_shuffle(order)
		queue = order.slice(0, mini(TIME_ATTACK_COUNT, order.size()))
	else:
		queue = [_draw(-1)]

func _start_rooms() -> void:
	rooms = true
	pool.sort()
	position = 0
	queue = pool.duplicate() if mode == TIME_ATTACK else [pool[0]]

func _shuffle(list: Array) -> void:
	for index in range(list.size() - 1, 0, -1):
		var other := _random.randi_range(0, index)
		var held: Variant = list[index]
		list[index] = list[other]
		list[other] = held

## Endless: every level once in a random order, then again; never the same level twice in a row.
func _draw(avoid: int) -> int:
	if _bag.is_empty():
		_bag = pool.duplicate()
		_shuffle(_bag)
	var pick: int = _bag.pop_back()
	if pick == avoid and pool.size() > 1:
		var other := -1
		if _bag.is_empty():
			_bag = pool.duplicate()
			_bag.erase(pick)
			_shuffle(_bag)
			other = _bag.pop_back()
		else: other = _bag.pop_back()
		_bag.insert(0, pick)
		pick = other
	return pick

func level() -> int:
	return int(queue[position])

## 1-based number of the level being played in this run.
func number() -> int:
	return position + 1

## Levels the run has in all (time attack), -1 for an endless run.
func count() -> int:
	return queue.size() if mode == TIME_ATTACK else -1

func cleared() -> int:
	return times.size()

func total() -> float:
	var sum := 0.0
	for seconds: float in times: sum += seconds
	return sum

## The current level was cleared in `seconds`. True when another level follows (the queue has moved on to it).
func level_cleared(seconds: float, glass_breaks := 0) -> bool:
	times.append(seconds)
	breaks += glass_breaks
	if mode == TIME_ATTACK:
		if position + 1 >= queue.size():
			finished = true
			return false
		position += 1
	else:
		queue.append(pool[(pool.find(level()) + 1) % pool.size()] if rooms else _draw(level()))
		position += 1
	return true

## Room run: the number of the room being played (1-based, its place among the balloon levels) and how many rooms there are.
func room() -> int:
	return pool.find(level()) + 1

func room_count() -> int:
	return pool.size()

## The run as the authority replicates it (match.run): everything the HUD and the results need.
func state(clearing := false, next_in := -1.0) -> Dictionary:
	return {"mode": mode, "level": level(), "number": number(), "count": count(), "cleared": cleared(), "base": total(), "times": times.duplicate(),
		"queue": queue.slice(0, times.size() + (0 if finished else 1)), "clearing": clearing, "next_in": next_in, "finished": finished, "breaks": breaks,
		"play_mode": play_mode, "room": room() if rooms else 0, "rooms": room_count() if rooms else 0}

## The results page of a run that has ended: the headline and the one line under it.
func headline() -> String:
	if rooms and mode == TIME_ATTACK: return "ALL ROOMS CLEARED" if finished else "ROOM RUN ENDED"
	if rooms: return "ENDLESS · %d ROOM%s" % [cleared(), "" if cleared() == 1 else "S"]
	if mode == TIME_ATTACK: return "TIME ATTACK COMPLETE" if finished else "TIME ATTACK ENDED"
	return "ENDLESS · %d LEVEL%s" % [cleared(), "" if cleared() == 1 else "S"]

func summary(player_left := false) -> String:
	var note := "A player left. " if player_left else ""
	var line := ""
	var unit := "room" if rooms else "level"
	if mode == TIME_ATTACK:
		if finished: line = "%d %s%s · total %s" % [cleared(), unit, "" if cleared() == 1 else "s", format_time(total())]
		else: line = note + "%d of %d %ss cleared" % [cleared(), queue.size(), unit]
	else: line = note + ("Total %s" % format_time(total()) if cleared() > 0 else "No %s cleared" % unit)
	# Balloon rounds count the pops next to the time.
	if play_mode == "balloon" and cleared() > 0: line += " · %d pop%s" % [breaks, "" if breaks == 1 else "s"]
	return line

static func format_time(seconds: float) -> String:
	var tenths := int(round(maxf(seconds, 0.0) * 10.0))
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]
