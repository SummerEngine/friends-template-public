extends RefCounted
## ONE interrupting event at a time, so play is not broken up by quick-time events one after another. The show's events that break into play on their own clock all ask this gate before they start and tell it
## when they are over: the manager's rule (its prompt and the rule in force), the hot eggplant (from the handout to the pop), the clock's BOOST / SOAR ("new subscriber", "went viral") and a
## pigeon's splat on a living player's screen. The gate grants an event only when none is running and GAP s have passed since the last one ended. Authority side only (modes/show/rules.gd owns
## it, ticks it with the round's play phase and resets it with every round): the clients only draw what the granted events put in the state. It never touches a node.
## NOT gated, on purpose: the held items of the boxes (a player's own choice, one at a time, a roll every box respawn; a press must always do what the player means), the tandem (two players
## who chose to hold hands), a pigeon's COO (a ping, no cover), the item lab's and the tools' forced events.
## A denied request is queued when the caller's window can wait (`WAIT`: the caller asks again each tick; the gate keeps ONE waiting caller, the first, and forgets it when it stops asking)
## and skipped otherwise (`SKIP`: another caller already waits, or the caller does not queue; a clock caller tries again after RETRY s, a pigeon on its next press).
const GAP := 15.0 ## s between the end of one event and the start of the next
const STALE := 1.0 ## s a queued caller may stay silent before the queue forgets it
const RETRY := 7.0 ## s a skipped caller waits before it asks again (the queue holds one caller; the others come back a little later, never a whole clock cycle later)
const MARGIN := 5.0 ## s an event may overrun its announced length before the gate calls it over (a caller that forgot `end`)

enum Verdict { GRANTED, WAIT, SKIP }

var now := 0.0 ## s since `reset`
var running := "" ## the kind of the event on now ("" none)
var last_end := -GAP ## `now` when the last event ended: a fresh gate is open at once
var granted := 0 ## events granted since `reset` (the checks read it)
var denied := 0 ## requests that were told WAIT or SKIP
var log: Array = [] ## [kind, start, end] of every event so far (end -1 while it runs)
var _queued := ""
var _queued_seen := 0.0
var _until := 0.0 ## `now` at which the running event is called over

## A new round: nothing runs, nothing waits, and the first event may start at once.
func reset() -> void:
	now = 0.0
	running = ""
	last_end = -GAP
	granted = 0
	denied = 0
	log.clear()
	_queued = ""
	_queued_seen = 0.0
	_until = 0.0

func tick(dt: float) -> void:
	now += dt
	if running != "" and now >= _until: end(running)
	if _queued != "" and now - _queued_seen > STALE: _queued = ""

## True when an event may start now.
func open() -> bool:
	return running == "" and now - last_end >= GAP

## Seconds until an event could start, if the running one ends in time and nobody else takes the slot (0 when open; for a running event its announced end plus the gap).
func wait_left() -> float:
	if running != "": return maxf(_until - now, 0.0) + GAP
	return maxf(GAP - (now - last_end), 0.0)

## `kind` wants to start an event that lasts about `span` s. GRANTED: it runs now, and the caller must `end(kind)` when it is over. Otherwise WAIT (kept in the queue: ask again every tick,
## only when `queue`) or SKIP.
func request(kind: String, span: float, queue := true) -> int:
	var first_in_line := _queued == "" or _queued == kind
	if open() and first_in_line:
		if _queued == kind: _queued = ""
		running = kind
		_until = now + span + MARGIN
		granted += 1
		log.append([kind, now, -1.0])
		return Verdict.GRANTED
	denied += 1
	if queue and first_in_line:
		_queued = kind
		_queued_seen = now
		return Verdict.WAIT
	return Verdict.SKIP

## `kind`'s event is over (a no-op when it is not the one running: the lab's forced events never asked).
func end(kind: String) -> void:
	if running == "" or running != kind: return
	running = ""
	last_end = now
	if not log.is_empty() and float((log.back() as Array)[2]) < 0.0: (log.back() as Array)[2] = now

## A caller that gave up waiting (its round is over, its window passed).
func cancel(kind: String) -> void:
	if _queued == kind: _queued = ""
