extends RefCounted
## The show's EVENT GATE in a real race (modes/show/shared/event_gate.gd; the pure rules are tools/modes/event_gate_check.gd): the manager's prompt and rule, the hot eggplant and the clock's
## BOOST / SOAR are all due in the same second and the three of them are asked for again whenever they are free: for two minutes of play never two run at once, every one starts 15 s or
## more after the one before ended (the gate's own log, checked against what is really on the state: the manager's phase, the eggplant's carrier, the effects), the first is granted at once, and
## the manager's rule is not cut short. The pigeon's splat (a second event kind) has its own check in the pigeon scenario.
const SPAN := 60 * 130

func run(h) -> void:
	for slot in 3: h.hold(slot)
	h.progress(0, 6.0)
	h.progress(1, 4.0)
	h.progress(2, 2.0)
	await h.tick(30)
	var rules = h.rules()
	var items = rules.items
	var manager = rules.manager
	var egg = items.rules_of.get("eggplant")
	h.check(egg != null and egg.active and manager.enabled and items.rules_of.has("boost"), "the race has the manager, the eggplant and the clock's events")
	rules._deadline = 1.0e9 # the round is not called in the middle of the check
	manager._next_at = 0.0
	egg._next_at = 0.0
	items._next_event_at = 0.0
	var t0: float = rules.gate.now
	var peak := 0
	var overlap := 0
	var started := {}
	for tick in SPAN:
		await h.tick(1)
		var live := 0
		if manager.phase != manager.Phase.IDLE: live += 1
		if egg.holder >= 0: live += 1
		if not items.none_on_anybody(items.Catalog.EVENTS): live += 1
		peak = maxi(peak, live)
		if live > 1: overlap += 1
	var log: Array = rules.gate.log
	for entry: Array in log: started[str(entry[0])] = true
	var spaced := true
	for index in range(1, log.size()):
		var before: Array = log[index - 1]
		var after: Array = log[index]
		if float(before[2]) < 0.0 or float(after[1]) - float(before[2]) < 15.0 - 0.02: spaced = false
	h.check(log.size() >= 3, "two minutes with everything due at once: %d events ran (%s)" % [log.size(), str(log.map(func(e: Array) -> String: return "%s@%.0f-%.0f" % [str(e[0]), float(e[1]), float(e[2])]))])
	h.check(overlap == 0 and peak <= 1, "never two at once on the real state (peak %d, ticks with two %d)" % [peak, overlap])
	h.check(spaced, "every event started 15 s or more after the one before had ended")
	h.check(float((log[0] as Array)[1]) - t0 < 1.0 and rules.gate.granted == log.size(), "the first was granted at once")
	h.check(started.size() >= 2, "at least two different kinds got their turn (%s)" % str(started.keys()))
