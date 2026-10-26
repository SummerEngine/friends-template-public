extends RefCounted
## The base of one minigame's rules (docs/modes.md). Shared: the authority (network/match_controller.gd) and the local game
## (client/local_level_flow.gd) run the same rules through a ModeHost (modes/mode_host.gd). Rules decide everything that counts
## (rounds, scores, who is out, the end) from the host's clock, the players' positions and their inputs; they never draw.
## Their state() rides in every snapshot (match.minigame) and is all a client's view (modes/mode_view.gd) gets.
##
## A mode's rules.gd extends this file and overrides start, tick, state, finished and results. Keep state() small and plain:
## ints, floats, bools, strings, arrays and dictionaries of those (a few KB at most; it is sent 20 times a second).

var host ## modes/mode_host.gd: the players, their positions and inputs, the yard, the cast, the props, send_to
var time := 0.0 ## seconds since the round started (tick adds dt)

## The round starts: every player stands on its yard spot. Seed anything random from host.rng (the same on every machine
## that runs the rules: there is only ever one).
func start(round_host) -> void:
	host = round_host
	time = 0.0

## One fixed tick (1/60 s) of the authority or the local game.
func tick(dt: float) -> void:
	time += dt

## Everything a view needs, every snapshot.
func state() -> Dictionary:
	return {}

## True once the round is over: the results page follows.
func finished() -> bool:
	return false

## The results page: {"headline": String (big, capitals), "sub": String (one line), "scores": Array (per slot, ints),
## "winners": Array (slots), optionally "order": Array (slots, best first: the table's ranks and the podium; without it the scores rank)}.
func results() -> Dictionary:
	return {"headline": "", "sub": "", "scores": [], "winners": []}

## A slot left the round (online): the rules play on without it when they can.
func drop(_slot: int) -> void:
	pass

# ------------------------------------------------------------------ helpers for every mode

## The scores line of the results page: "MAYA 12 · THEO 9 · IDA 4", best first.
func score_line(scores: Array) -> String:
	var order: Array = range(scores.size())
	order.sort_custom(func(a: int, b: int) -> bool: return int(scores[a]) > int(scores[b]) or (int(scores[a]) == int(scores[b]) and a < b))
	var parts := PackedStringArray()
	for slot: int in order: parts.append("%s %d" % [str(host.name(slot)), int(scores[slot])])
	return "  ·  ".join(parts)

## The slots with the highest score.
func best(scores: Array) -> Array:
	var top: int = -1073741824
	for entry: Variant in scores: top = maxi(top, int(entry))
	var result: Array = []
	for slot in scores.size():
		if int(scores[slot]) == top: result.append(slot)
	return result
