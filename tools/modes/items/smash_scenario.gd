extends RefCounted
const TeamCast := preload("res://style/team_cast.gd")
## SMASH end to end: slot 2 (the user) holds it, slots 0 and 1 race with slot 0 in the lead; ITEM sends the hand onto slot 0 and nobody else. The checks follow the effect on the replica clients:
## the shadow and the hand over slot 0 on every client, the victim's own machine freezing its courier and its rig squashed to Y 0.11 (the rig's real basis) while pinned, the spring back to
## scale 1 with nobody frozen after, a second use on a flat leader keeping the item, and the leader who uses it sending the hand onto the runner behind. With `--shots` it takes the frames
## of the strip: `--view=0` is the victim's screen; `--view=1` makes slot 1 the user (its pill, then the hand coming down on the leader ahead of it).
func run(h) -> void:
	var items = h.rules().items
	var user := 1 if h.shots != "" and h.shot_view == 1 else 2
	for slot in 3: h.hold(slot)
	await h.tick(20)
	h.check(items.boxes.size() > 0, "level 31 lists item boxes (%d)" % items.boxes.size())
	h.progress(0, 26.0)
	for seat in 3: # the leader stands on the tiles beside the disc's hub, not inside it (a flat character is hidden by the hub's dome)
		if h.controller._slot(seat) == 0 and h.warp.has(seat): h.warp[seat] += Vector3(-1.6, 0.0, 0.0)
	h.progress(1, 20.0)
	h.progress(2, 8.0)
	await h.tick(40)
	h.check(items.leader(user) == 0, "slot 0 leads and is the target of slot %d (leader besides the user: %d)" % [user, items.leader(user)])
	if user == 1:
		var spot: Vector3 = items.boxes[0]
		for seat in 3:
			if h.controller._slot(seat) == 1: h.warp[seat] = spot + Vector3.UP * 0.05
		await h.wait_until(func() -> bool: return int(h.state().items.held[1]) >= 0, 120)
		await h.tick(10)
		h.shoot("a_box_pickup")
		await h.tick(12)
		var roll_kind: int = items.held[1]
		h.check(roll_kind >= 0, "slot 1 took a roll in the box")
		h.progress(1, 20.0)
		await h.tick(20)
	h.check(h.give(user, "smash"), "slot %d holds SMASH" % user)
	await h.tick(8)
	h.shoot("b_pill")
	await h.tick(6)
	h.check(int(h.state().items.held[user]) == items.Catalog.index("smash"), "the state says slot %d holds it" % user)
	h.press_item(user)
	await h.tick(2)
	h.shoot("c_use")
	await h.tick(8)
	var st: Dictionary = h.state()
	var victims: Array = []
	for row: Array in st.items.fx:
		if int(row[2]) == items.Catalog.index("smash"): victims.append(int(row[1]))
	h.check(victims == [0], "SMASH is on slot 0 only, not on the user or the runner behind (%s)" % str(victims))
	h.check(int(st.items.held[user]) == -1, "the item is used up")
	var fx_row: Array = st.items.fx[0]
	h.check(is_equal_approx(float(fx_row[5]), 1.4) and is_equal_approx(float(fx_row[6]), 2.5) and is_equal_approx(float(fx_row[3]), 1.4 + 2.5 + 0.45), "the effect is warn 1.4 + pin 2.5 + spring 0.45 s (a %.2f, b %.2f, dur %.2f)" % [float(fx_row[5]), float(fx_row[6]), float(fx_row[3])])
	var items_view = h.views[0]._items
	h.check(str(items_view._banner.get("words", "")) == "", "no banner while the hand is still coming (it bangs in with the slap)")
	# warning: the shadow and the hand are over the victim on both clients, nobody is held yet
	var hands: Array = []
	var feet0: Vector3 = h.replicas[0].actors[0].global_position
	for view in h.views:
		var entry := _entry(view)
		var hand: Node3D = entry.get("hand")
		hands.append(hand)
	h.check(hands.all(func(hand: Variant) -> bool: return hand != null), "both clients draw the hand")
	var high: float = (hands[0] as Node3D).global_position.y - feet0.y
	h.check(high > 6.0, "the hand is high over the victim while it warns (%.1f m)" % high)
	h.check(not bool(h.replicas[0].item_mods.get(0, {}).get("freeze", false)), "the victim is free to run during the warning")
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 0.36, 60)
	h.shoot("c2_shadow_alone")
	await h.tick(2)
	var early: Dictionary = _entry(h.views[0])
	var shadow: MeshInstance3D = early.shadow
	h.check(float((early.hand as Node3D).global_position.y - feet0.y) > 10.0 and shadow.scale.x > 1.5 and (shadow.material_override as StandardMaterial3D).albedo_color.a > 0.15, "the shadow comes alone first: growing and dark (%.1f m wide) while the hand is still out of the frame (%.1f m up)" % [shadow.scale.x, (early.hand as Node3D).global_position.y - feet0.y])
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 0.9, 60)
	h.shoot("d_hand_coming")
	await h.tick(14)
	h.shoot("e_hand_cocked")
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 1.28, 90)
	h.shoot("f_hand_falls")
	await h.tick(4)
	h.shoot("g_impact")
	await h.tick(8)
	h.shoot("g2_impact_dust")
	# the slap: wait until the effect is past the warning
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 1.55, 60)
	h.check(str(items_view._banner.get("words", "")) == "SMASHED!" and str(items_view._banner.get("kind", "")) == "alert", "the slap brings the alert banner on the victim's screen (%s)" % str(items_view._banner.get("words", "")))
	var freeze_ok := bool(h.replicas[0].item_mods.get(0, {}).get("freeze", false))
	var scale0: Variant = h.replicas[0].rig_scales.get(0)
	h.check(freeze_ok, "the victim's own machine freezes its courier while it is pinned")
	h.check(scale0 is Vector3 and absf((scale0 as Vector3).y - 0.11) < 0.02 and absf((scale0 as Vector3).x - 1.15) < 0.06, "rig_scales[0] is the squash (%s)" % str(scale0))
	h.check(bool(h.replicas[1].item_mods.get(0, {}).get("freeze", false)) and h.replicas[1].rig_scales.get(0) is Vector3 and absf((h.replicas[1].rig_scales[0] as Vector3).y - 0.11) < 0.02, "the other client shows the leader flat too")
	var rig: Node3D = h.replicas[0].rigs[0]
	var drawn: Vector3 = rig.global_basis.get_scale()
	h.check(absf(drawn.y - 0.11) < 0.03 and drawn.x > 1.05, "the squashed rig really is flat (basis scale %s)" % str(drawn))
	h.check(not h.replicas[0].item_mods.has(user) and not h.replicas[0].rig_scales.has(user), "the user is not touched")
	h.check(not h.replicas[0].item_mods.has(1) and not h.replicas[1].item_mods.has(1), "the runner behind is not touched")
	var pressed: Node3D = _entry(h.views[0]).get("hand")
	var look = items_view.look_of("smash")
	var feet_now: Vector3 = h.replicas[0].actors[0].global_position
	var gap: float = pressed.global_position.y - feet_now.y
	var top: float = look._surface(Vector3(feet_now.x, feet_now.y, feet_now.z), float(_entry(h.views[0]).yaw), feet_now.y)
	h.check(gap > 0.1 and gap < 1.5 and (is_nan(top) or gap >= top - feet_now.y - 0.001), "the palm rests ON the highest surface under it, not in it (%.2f m over the victim's floor, surface %.2f)" % [gap, top - feet_now.y])
	h.check(float(_entry(h.views[0]).get("age", 0.0)) < 3.0, "still inside the pin")
	await h.tick(30)
	h.shoot("h_pinned")
	await h.tick(8)
	# a second use on a leader who is already flat keeps the item
	h.check(h.give(user, "smash"), "slot %d is handed another SMASH" % user)
	await h.tick(2)
	h.press_item(user)
	await h.tick(8)
	h.check(int(h.state().items.held[user]) == items.Catalog.index("smash") and items.fx.size() == 1, "the flat leader is skipped and the item stays with its player")
	items.held[user] = -1
	# the hand lets go while the character is still held: the pancake lies there alone, frozen, with stars over it
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 3.72, 60 * 6)
	h.shoot("i_pancake")
	await h.tick(2)
	var alone: Dictionary = _entry(h.views[0])
	var lifted: float = (alone.hand as Node3D).global_position.y - h.replicas[0].actors[0].global_position.y
	h.check(lifted > 3.0 and bool(h.replicas[0].item_mods.get(0, {}).get("freeze", false)) and absf((h.replicas[0].rig_scales[0] as Vector3).y - 0.11) < 0.02, "the hand has lifted away (%.1f m up) and the flat character is still pinned" % lifted)
	h.check(alone.has("stars") and (alone.stars as Node3D).visible, "stars circle over the flat character")
	# the pin ends, the spring back runs
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 3.96, 60 * 6)
	h.shoot("i_spring")
	await h.tick(6)
	var released := not bool(h.replicas[0].item_mods.get(0, {}).get("freeze", false))
	h.check(released, "the victim runs again once the pin is over")
	await h.tick(8)
	h.shoot("j_spring_over")
	await h.wait_until(func() -> bool: return h.state().items.fx.is_empty(), 60 * 3)
	await h.tick(8)
	h.check(h.state().items.fx.is_empty() and h.replicas[0].item_mods.is_empty() and h.replicas[1].item_mods.is_empty(), "when the effect ends nobody is frozen and the clients are free")
	h.check(not h.replicas[0].rig_scales.has(0) and not h.replicas[1].rig_scales.has(0), "no squash is left in the shells")
	var back: Vector3 = (h.replicas[0].rigs[0] as Node3D).global_basis.get_scale()
	h.check(absf(back.y - 1.0) < 0.02 and absf(back.x - 1.0) < 0.02, "the rig's scale is back to 1 (%s)" % str(back))
	h.check(_entry(h.views[0]).is_empty() and not h.views[0]._items.get_children().any(func(node: Node) -> bool: return node.name.begins_with("SmashFx")), "the hand and the dust are gone")
	# an example cast's wording (work/items/smash.entry.json of the cast repo): the banner on the victim's screen, the pill's name and the feed line the others read
	var cast: Dictionary = TeamCast.data().duplicate(true)
	cast["show"] = {"items": [{"id": "smash", "name": "BIG HAND", "banner": "A HAND FROM ABOVE", "line": "{user} SENT A HAND DOWN"}]}
	TeamCast.override(cast)
	h.check(items.Catalog.text("smash", "name") == "BIG HAND" and items.Catalog.text("smash", "banner") == "A HAND FROM ABOVE", "an example cast names the item BIG HAND with its banner")
	h.check(h.give(user, "smash"), "slot %d holds SMASH again, for the cast's wording" % user)
	await h.tick(2)
	h.press_item(user)
	await h.wait_until(func() -> bool: return float(_entry(h.views[0]).get("age", 0.0)) > 1.6, 60 * 3)
	h.check(str(items_view._banner.get("words", "")) == "A HAND FROM ABOVE", "the victim's banner reads the cast's words (%s)" % str(items_view._banner.get("words", "")))
	var told: Array = items_view._lines.map(func(line: Dictionary) -> String: return str(line.text))
	var user_name: String = ["MAYA", "THEO", "IDA"][user]
	h.check(told.has(user_name + " SENT A HAND DOWN"), "the feed line reads the cast's words (%s)" % str(told))
	h.shoot("k_cast_banner")
	await h.tick(6)
	if h.shots == "":
		await h.wait_until(func() -> bool: return h.state().items.fx.is_empty(), 60 * 6)
		await h.tick(8)
	h.fixture_cast()
	if h.shots != "": return
	# the leader who uses it sends the hand onto the runner behind (never onto itself)
	await h.tick(30)
	h.check(h.give(0, "smash"), "the leader holds SMASH")
	await h.tick(4)
	h.press_item(0)
	await h.tick(10)
	var second: Array = []
	for row: Array in h.state().items.fx:
		if int(row[2]) == items.Catalog.index("smash"): second.append(int(row[1]))
	h.check(second == [1], "the leader's SMASH lands on the second place, not on itself (%s)" % str(second))

## What the view keeps of the (first) SMASH effect on that replica's items manager; {} for none.
func _entry(view) -> Dictionary:
	for entry: Dictionary in view._items._fx.values():
		if int(entry.kind) == 0: return entry
	return {}
