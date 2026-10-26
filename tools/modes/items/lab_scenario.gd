extends RefCounted
## The item lab: with it off a lab press does nothing; with it on, 1-5 put the item in the slot, 6 and 7 make the event happen, and the user who LEADS can still use every attack item (smash on the next best,
## call on the nearest racer behind, glitch on the pack behind, dance thrown at anyone).
func run(h) -> void:
	for slot in 3: h.hold(slot)
	h.progress(2, 30.0) # slot 2 leads
	h.progress(1, 20.0)
	h.progress(0, 10.0)
	await h.tick(30)
	var items = h.rules().items
	var Catalog = items.Catalog
	h.press_lab(2, 1)
	await h.tick(6)
	h.check(int(h.state().items.held[2]) == -1, "lab off: a lab press hands out nothing")
	items.lab = true
	h.press_lab(2, 2)
	await h.tick(6)
	h.check(int(h.state().items.held[2]) == Catalog.index("call"), "lab on: key 2 puts the call in slot 2")
	h.press_lab(2, 1)
	await h.tick(6)
	h.check(int(h.state().items.held[2]) == Catalog.index("smash"), "key 1 replaces it with the smash")
	h.press_item(2)
	await h.tick(8)
	var victims: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == Catalog.index("smash"): victims.append(int(row[1]))
	h.check(victims == [1], "the leader's smash lands on the next best (slot 1): %s" % str(victims))
	h.press_lab(2, 2)
	await h.tick(4)
	h.press_item(2)
	await h.tick(8)
	h.check(h.state().items.proj.size() > 0 and int(h.state().items.held[2]) == -1, "the leader's call flies at somebody behind")
	h.press_lab(2, 4)
	await h.tick(4)
	h.press_item(2)
	await h.tick(8)
	var glitched: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == Catalog.index("glitch"): glitched.append(int(row[1]))
	glitched.sort()
	h.check(glitched == [0, 1], "the leader's glitch hits the pack behind: %s" % str(glitched))
	h.press_lab(2, 5)
	await h.tick(4)
	h.check(int(h.state().items.held[2]) == Catalog.index("dance"), "key 5 holds the dance")
	h.press_lab(0, 6)
	await h.tick(8)
	var boosted := false
	for row: Array in h.state().items.fx:
		if int(row[2]) == Catalog.index("boost") and int(row[1]) == 0: boosted = true
	h.check(boosted, "key 6 makes the boost happen to the presser at once")
	h.press_lab(1, 7)
	await h.tick(8)
	var soared := false
	for row: Array in h.state().items.fx:
		if int(row[2]) == Catalog.index("soar") and int(row[1]) == 1: soared = true
	h.check(soared, "key 7 makes the soar happen to the presser")
	items.TeamCast.override({"format": "team-cast-v2", "team": {"name": "Items Check"}, "mode": "show", "show": {"item_lab": true},
		"players": [{"name": "Maya", "color": "#ff5a36"}, {"name": "Theo", "color": "#2c4bff"}, {"name": "Ida", "color": "#2ec27e"}]})
	await h.tick(12)
	h.check(bool(h.views[0]._items._lab) and bool(h.replicas[0].item_slot.get("lab", false)), "the cast's item_lab reaches the HUD (the hint pill) and the shell (keys 1-7)")
	h.shoot("lab_hint")
	await h.tick(10)
