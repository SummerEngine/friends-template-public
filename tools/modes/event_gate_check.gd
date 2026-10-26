extends SceneTree
## The show's EVENT GATE (modes/show/shared/event_gate.gd, docs/party-show.md "One interrupting event at a time"): the pure rules, then the real show rules.
##   A. the gate alone: events asked for at t = 0, 5, 10 s: only the first runs; the others wait or are skipped; the next one is granted 15 s after the first ENDED, not before
##   B. one waiting caller at most: the second caller is skipped; a waiting caller that stops asking is forgotten; a pigeon's no-queue request is skipped, not queued
##   C. an event whose owner forgot to end it is called over by the gate after its span + 5 s; ending the wrong kind does nothing; `reset` opens it at once
## The gate inside the real show (the manager, the eggplant and the clock's boost/soar due in the same second) is `tools/modes/items_harness.gd -- --scenario=gate --show-level=31`.
## Prints EVENT_GATE_CHECK ok=<bool> last; exits 1 on a failure.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo -s "$PWD/tools/modes/event_gate_check.gd"
const Gate := preload("res://modes/show/shared/event_gate.gd")
const DT := 1.0 / 60.0

var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("EVENT_GATE_CHECK ", "ok   " if condition else "FAIL ", label)

func _initialize() -> void:
	scenario_pure()
	scenario_edges()
	print("EVENT_GATE_CHECK ok=", failures == 0)
	quit(1 if failures > 0 else 0)

func advance(gate: Gate, seconds: float) -> void:
	for tick in int(round(seconds * 60.0)): gate.tick(DT)

# ------------------------------------------------------------------ A

func scenario_pure() -> void:
	var gate := Gate.new()
	check(gate.open() and gate.GAP == 15.0, "A: a fresh gate is open and the gap is 15 s")
	check(gate.request("a", 20.0) == Gate.Verdict.GRANTED and gate.running == "a", "A: t=0: the first event is granted and runs")
	advance(gate, 5.0)
	check(gate.request("b", 4.0) == Gate.Verdict.WAIT and gate.running == "a", "A: t=5: a second event is denied (waits in the queue), the first still runs")
	advance(gate, 5.0)
	check(gate.request("b", 4.0) == Gate.Verdict.WAIT and gate.running == "a", "A: t=10: asked again, still waiting, the first still runs (%.1f)" % gate.now)
	check(gate.request("c", 4.0) == Gate.Verdict.SKIP, "A: t=10: a third caller finds the queue taken and is skipped")
	advance(gate, 2.0)
	gate.end("a") # the first ends at t=12
	var ended_at: float = gate.now
	check(gate.running == "" and not gate.open() and absf(gate.wait_left() - 15.0) < 0.05, "A: t=12: the first ends; the gate is closed for 15 s (%.2f s left)" % gate.wait_left())
	advance(gate, 14.9)
	check(gate.request("b", 4.0) == Gate.Verdict.WAIT, "A: 14.9 s after the end: still denied")
	advance(gate, 0.15)
	var verdict: int = gate.request("b", 4.0)
	check(verdict == Gate.Verdict.GRANTED and gate.now - ended_at >= 15.0, "A: %.2f s after the end: the waiting event is granted (>= 15 s)" % (gate.now - ended_at))
	check(gate.granted == 2 and (gate.log[1] as Array)[1] - (gate.log[0] as Array)[2] >= 15.0 and (gate.log[0] as Array)[2] > 0.0, "A: the log has two events, the second starting %.2f s after the first ended" % float((gate.log[1] as Array)[1] - (gate.log[0] as Array)[2]))

# ------------------------------------------------------------------ B, C

func scenario_edges() -> void:
	var gate := Gate.new()
	gate.request("a", 3.0)
	check(gate.request("manager", 3.0) == Gate.Verdict.WAIT and gate.request("eggplant", 3.0) == Gate.Verdict.SKIP, "B: one waiting caller (the first), the next is skipped")
	check(gate.request("splat", 3.0, false) == Gate.Verdict.SKIP, "B: a request that does not queue (the pigeon's drop) is skipped")
	advance(gate, 1.5) # the manager stops asking
	check(gate.request("eggplant", 3.0) == Gate.Verdict.WAIT, "B: a caller that stops asking is forgotten after a second: the next may queue")
	# C
	advance(gate, 3.0 + Gate.MARGIN)
	check(gate.running == "", "C: an event nobody ended is called over after its span + 5 s")
	check(gate.request("a", 3.0) == Gate.Verdict.WAIT and not gate.open(), "C: ... and the gap counts from then")
	gate.end("not-a")
	check(not gate.open(), "C: ending a kind that is not the one running does nothing")
	gate.reset()
	check(gate.open() and gate.request("a", 3.0) == Gate.Verdict.GRANTED, "C: reset opens the gate at once")
