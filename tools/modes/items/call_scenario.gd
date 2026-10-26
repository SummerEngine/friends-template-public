extends RefCounted
## CALL end to end: slot 2 (behind) holds it and presses ITEM; a homing shot leaves for slot 0 (the nearest racer ahead, slot 1 is further back), flies in a curve and lands; the call effect is
## on slot 0 only; slot 0's client builds the call window (70 % of the screen by area, the footage or the code-drawn sheet) and its courier is not frozen; slot 1's client sees a phone over
## slot 0's head; slot 0's GRAB presses shorten the effect but never below `least` s; the window closes and the effect is gone. Frames (--shots) at: before, use, the shot in flight, the toast,
## the window, DECLINE shaking, the end.
const MEDIA := "res://cast/items/call.ogv"

func run(h) -> void:
	if FileAccess.file_exists(MEDIA): # a local cast's footage: the same scenario with the real recording in the window
		h.TeamCast.override({"format": "team-cast-v2", "team": {"name": "Items Check"}, "mode": "show",
			"players": [{"name": "Maya", "color": "#ff5a36"}, {"name": "Theo", "color": "#2c4bff"}, {"name": "Ida", "color": "#2ec27e"}],
			"show": {"items": [{"id": "call", "name": "5-MIN CALL", "media": "items/call.ogv", "banner": "URGENT 5-MIN CALL", "line": "{user} SCHEDULED A QUICK SYNC WITH {victim}"}]}})
	for slot in 3: h.hold(slot)
	var close_up: bool = h.shot_view == 1 # frames of the bystander's screen: the racers stand closer, so the victim and the phone over its head are in view
	h.progress(0, 25.0 if close_up else 30.0)
	h.progress(1, 17.5 if close_up else 16.0)
	h.progress(2, 21.5 if close_up else 21.0)
	await h.tick(30)
	var items = h.rules().items
	var call: int = items.Catalog.index("call")
	h.check(items.ahead_of(2) == [0] and items.ahead_of(1) == [2, 0], "slot 0 is the nearest racer ahead of slot 2, slot 1 is behind (%s)" % str(items.ahead_of(2)))
	h.check(h.give(0, "call"), "the leader holds CALL")
	await h.tick(4)
	h.press_item(0)
	await h.tick(6)
	h.check(int(h.state().items.held[0]) == -1 and h.state().items.proj.size() == 1, "nobody is ahead of the leader: its call flies at the nearest racer behind")
	items.projectiles.clear() # the scene goes on with the clean start
	items.held[0] = -1
	h.check(h.give(2, "call"), "slot 2 holds CALL")
	h.shoot("call_1_before")
	await h.tick(8)
	var window: float = items.tune("call", "window")
	var least: float = items.tune("call", "least")
	var cover: float = items.tune("call", "cover")
	h.press_item(2)
	await h.tick(2)
	var st: Dictionary = h.state()
	var shot: Array = (st.items.proj[0] as Array) if not st.items.proj.is_empty() else []
	h.check(shot.size() == 10 and int(shot[1]) == call and int(shot[8]) == 0, "the shot is in the state and goes for slot 0 (%s)" % str(shot.slice(0, 2) + shot.slice(8, 9)))
	h.check(int(st.items.held[2]) == -1, "the item is used up")
	h.check(st.items.fx.is_empty(), "nothing has landed yet")
	var start := Vector3(float(shot[2]), float(shot[3]), float(shot[4])) if shot.size() == 10 else Vector3.ZERO
	var chest: Vector3 = items.position_of(2) + Vector3(0.0, 1.05, 0.0)
	h.check(start.distance_to(chest) < 1.2, "it leaves the user's chest (%.2f m off)" % start.distance_to(chest))
	h.shoot("call_2_use")
	await h.tick(6)
	var peak := start.y
	var flight_frames := 0
	var gap_first := -1.0
	var gap_last := 0.0
	var shot_framed := false
	while flight_frames < 60 * 5 and not (h.state().items.proj as Array).is_empty():
		var row: Array = (h.state().items.proj as Array)[0]
		var at := Vector3(float(row[2]), float(row[3]), float(row[4]))
		var gap: float = at.distance_to(items.position_of(0) + Vector3(0.0, 1.05, 0.0))
		if gap_first < 0.0: gap_first = gap
		gap_last = gap
		peak = maxf(peak, at.y)
		if not shot_framed and gap < 5.5:
			shot_framed = true
			h.shoot("call_3_flight")
		await h.tick()
		flight_frames += 1
	h.check(flight_frames > (5 if close_up else 20) and flight_frames < 60 * 3, "it flies for a moment and arrives (%d ticks)" % flight_frames)
	h.check(peak > start.y + (0.4 if close_up else 1.0), "it flies in an arc (rises %.1f m over its start)" % (peak - start.y))
	h.check(gap_last < gap_first, "it closes in on its target (%.1f m, then %.1f m)" % [gap_first, gap_last])
	await h.tick(2)
	var landed: Array = h.state().items.fx.filter(func(row: Array) -> bool: return int(row[2]) == call)
	h.check(landed.size() == 1 and int((landed[0] as Array)[1]) == 0 and int((landed[0] as Array)[7]) == 2, "the call lands on slot 0 only, sent by slot 2 (%d effects)" % landed.size())
	h.check(is_equal_approx(float((landed[0] as Array)[5]), cover) if not landed.is_empty() else false, "the window covers %.0f %% (the effect carries it)" % (cover * 100.0))
	await h.tick(8)
	var victim_items = h.views[0]._items
	var window_node: Control = null
	for entry: Dictionary in victim_items._fx.values():
		if entry.get("node") is Control: window_node = entry.node
	h.check(window_node != null and window_node.name == "CallWindow", "slot 0's client builds the call window")
	h.check(window_node != null and absf(window_node.cover_ratio() - cover) < 0.03, "the window covers about %.0f %% of the screen (%.2f)" % [cover * 100.0, window_node.cover_ratio() if window_node != null else -1.0])
	var gutters_ok := false
	if window_node != null:
		var view_size: Vector2 = window_node.get_viewport_rect().size
		var rect: Rect2 = window_node.panel_rect()
		var parts: Dictionary = window_node.layout(rect.size)
		var shared_screen: Rect2 = parts.video
		var tiles: Array = parts.tiles
		gutters_ok = rect.position.x + shared_screen.position.x >= view_size.x * 0.17 - 1.0 and rect.position.x + (tiles[0] as Rect2).end.x <= view_size.x * 0.83 + 1.0 and rect.size.y < view_size.y - 40.0 and rect.size.x < view_size.x - 40.0
	h.check(gutters_ok, "the HUD's side pills land on the window's dark gutters (the content stays inside 17-83 % of the width) and a strip of the game stays visible around it")
	h.check(h.replicas[0].item_mods.has(0) and not bool(h.replicas[0].item_mods[0].get("freeze", false)) and not bool(h.replicas[0].item_mods[0].get("invert", false)), "the victim keeps running: no freeze (%s)" % str(h.replicas[0].item_mods.get(0, "none")))
	h.check(str(victim_items._banner.get("words", "")) == items.Catalog.text("call", "banner"), "the victim's screen shows the banner (%s)" % str(victim_items._banner.get("words", "")))
	var seen_by_slot_1 := false
	for entry: Dictionary in h.views[1]._items._fx.values():
		if int(entry.slot) == 0 and entry.get("node") is Node3D and not bool(entry.mine): seen_by_slot_1 = true
	h.check(seen_by_slot_1, "slot 1's client draws a phone over slot 0's head")
	h.check(not h.views[1]._items._fx.values().any(func(entry: Dictionary) -> bool: return entry.get("node") is Control), "slot 1 gets no window")
	h.shoot("call_4_toast")
	await h.tick(80)
	h.shoot("call_5_window")
	await h.tick(30)
	var entry_now: Dictionary = items.fx_of(0, "call")
	h.check(absf(float(entry_now.dur) - window) < 0.001, "no taps yet: the window is %.1f s" % window)
	var dur_after_one := 0.0
	var below_least := false
	var window_taps := 0
	var authority_taps := 0.0
	for tap in 12:
		h.press_grab(0)
		h.replicas[0].grab_taps += 1 # the owner's own machine counts its tap as it happens
		if tap == 1: h.shoot("call_6_tap")
		await h.tick(3)
		var live: Dictionary = items.fx_of(0, "call")
		if live.is_empty(): break
		if tap == 0: dur_after_one = float(live.dur)
		if float(live.dur) < least - 0.001: below_least = true
		authority_taps = float(live.b)
		if window_node != null and is_instance_valid(window_node): window_taps = window_node.taps
	h.check(absf(dur_after_one - (window - items.tune("call", "tap"))) < 0.001, "one GRAB press takes %.1f s off (%.2f s left)" % [items.tune("call", "tap"), dur_after_one])
	h.check(not below_least, "however many presses, the window never gets shorter than %.1f s" % least)
	h.check(window_taps >= 3, "the window counted the taps on the victim's machine (%d)" % window_taps)
	h.check(authority_taps >= 3.0, "the authority counted the presses in the effect (%d)" % int(authority_taps))
	var last_age := 0.0
	while not items.fx_of(0, "call").is_empty():
		last_age = float(items.fx_of(0, "call").age)
		await h.tick()
	h.check(last_age >= least - 0.05 and last_age < least + 0.4, "the call ran its minimum and ended with the presses in (%.2f s of %.1f)" % [last_age, least])
	await h.tick(4)
	h.shoot("call_7_end") # the window is shrinking away
	await h.tick(30)
	h.check(h.state().items.fx.is_empty() and h.replicas[0].item_mods.is_empty(), "the effect is gone and the courier is free")
	h.check(victim_items._fx.is_empty() and (window_node == null or not is_instance_valid(window_node)), "the window is closed and gone")
	h.check(h.views[1]._items._fx.is_empty(), "the phone over slot 0's head is gone")
