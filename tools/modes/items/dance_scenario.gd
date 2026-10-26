extends RefCounted
## DANCE end to end: a racer behind slot 0, facing it, picks up the phone and throws it (slot 2; with `--view=1` slot 1, so the frames show the throw from the thrower's own screen). The shot
## is in the state and moves, hits slot 0 and nobody else, and on the clients: slot 0's courier is frozen, its rig dances on both screens and wears the plain look (and gets its own back exactly
## when the seconds are up), the letterbox bars and the zoom exist on replica 0's screen only, the REC / LIVE tag on the other one. A second throw with nobody in front of the thrower pops
## on the floor and puts nothing on anybody; the item is spent either way. Frames: `--shots=<dir> --view=0` is the victim's screen, `--view=1` the thrower's.
const DanceFrame := preload("res://modes/show/items_ui/dance_frame.gd")

var _h

func run(h) -> void:
	_h = h
	var items = h.rules().items
	var kind: int = items.Catalog.index("dance")
	var thrower := 1 if h.shot_view == 1 else 2
	var other := 3 - thrower # the third racer stays far behind, out of every cone
	for slot in 3: h.hold(slot)
	await h.tick(20)
	h.check(items.rules_of.has("dance"), "the dance rule is in the round")

	# ---- the throw that hits
	await _stand(thrower, 36.0)
	await _stand(0, 42.0)
	await _stand(other, 6.0)
	var from: Vector3 = items.host.position(thrower)
	var to: Vector3 = items.host.position(0)
	var yaw: float = items.host.yaw(thrower)
	var off := absf(rad_to_deg(Vector2(-sin(yaw), -cos(yaw)).angle_to(Vector2(to.x - from.x, to.z - from.z))))
	h.check(off < 30.0 and from.distance_to(to) > 3.5, "the thrower faces slot 0, %.1f m away, %.1f degrees off its facing" % [from.distance_to(to), off])
	var rig_before: Node = h.replicas[0].rigs[0]
	var head_before := str((rig_before.get("_applied") as Dictionary).get("head", ""))
	var look_before: CharacterLook = rig_before.get_look()
	var other_head := str((h.replicas[0].rigs[other].get("_applied") as Dictionary).get("head", ""))
	h.check(head_before != "" and head_before != "head_bean", "slot 0 starts with its own head (%s)" % head_before)
	h.check(h.give(thrower, "dance"), "slot %d holds the dance" % thrower)
	await h.tick(4)
	_shoot("a_pickup")
	await h.tick(6)
	h.press_item(thrower)
	await h.tick(3)
	var st: Dictionary = h.state()
	h.check(st.items.proj.size() == 1 and int(st.items.proj[0][1]) == kind, "a dance projectile is in the state (%d)" % st.items.proj.size())
	h.check(int(st.items.held[thrower]) == -1, "the item is spent")
	var first: Vector3 = Vector3(float(st.items.proj[0][2]), float(st.items.proj[0][3]), float(st.items.proj[0][4])) if not st.items.proj.is_empty() else Vector3.ZERO
	_shoot("b_throw")
	await h.tick(6)
	st = h.state()
	var moved := Vector3.ZERO
	if not st.items.proj.is_empty():
		var row: Array = st.items.proj[0]
		moved = Vector3(float(row[2]), float(row[3]), float(row[4]))
	h.check(first.distance_to(moved) > 1.0 and moved.distance_to(first) < 12.0, "the projectile moves (%.1f m in 6 ticks)" % first.distance_to(moved))
	h.check(h.views[1]._items._shots.size() == 1 and h.views[0]._items._shots.size() == 1, "both clients draw the phone")
	_shoot("c_flight")
	await h.tick(8)
	var hit: bool = await h.wait_until(func() -> bool: return not _fx_of(0, kind).is_empty(), 90)
	h.check(hit, "the shot hits slot 0")
	st = h.state()
	h.check(_fx_of(thrower, kind).is_empty() and _fx_of(other, kind).is_empty(), "nobody else is filmed, not the thrower")
	h.check(st.items.proj.is_empty(), "the shot is gone")
	var entry: Array = _fx_of(0, kind)
	h.check(not entry.is_empty() and absf(float(entry[3]) - 3.0) < 0.01 and int(entry[7]) == thrower, "3 s on slot 0, sent by slot %d" % thrower)
	await h.tick(2)
	_shoot("d_hit")
	await h.tick(8)
	h.check(bool(h.replicas[0].item_mods.get(0, {}).get("freeze", false)), "slot 0 is frozen by its own machine")
	h.check(not h.replicas[0].item_mods.has(thrower) and not h.replicas[0].item_mods.has(other), "nobody else is")
	h.check(str(h.views[0]._items._banner.get("words", "")) == "FILMING!" and str(h.views[0]._items._banner.get("kind", "")) == "alert", "the victim reads FILMING! (alert)")
	h.check(_frames(0) == 1 and _frames(1) == 0, "the letterbox is on replica 0 only (%d, %d)" % [_frames(0), _frames(1)])
	await h.tick(24)
	_shoot("e_zoom")
	await h.tick(8)
	for index in 2:
		var rig: Node = h.replicas[index].rigs[0]
		h.check(rig.emote_playing() == "dance", "replica %d: slot 0's rig dances" % index)
		h.check(str((rig.get("_applied") as Dictionary).get("head", "")) == "head_bean", "replica %d: slot 0 wears the plain look (%s)" % [index, str((rig.get("_applied") as Dictionary).get("head", ""))])
		var applied: Dictionary = rig.get("_applied")
		h.check(str(applied.get("hat", "")) == "" and str(applied.get("hair", "")) == "" and str(applied.get("hand", "")) == "", "replica %d: no cap, hair or hand item while it dances (%s)" % [index, str(applied)])
		var shown: CharacterLook = rig.get("_look")
		h.check(int(shown.colors.get("skin", -1)) == 2, "replica %d: the plain skin tone (%s)" % [index, str(shown.colors.get("skin", -1))])
		h.check(str((h.replicas[index].rigs[other].get("_applied") as Dictionary).get("head", "")) == other_head, "replica %d: nobody else's look changed" % index)
	h.check(_zoom(0) > 0.5 and _zoom(1) == 0.0, "the camera zoom is on replica 0 only (%.2f, %.2f)" % [_zoom(0), _zoom(1)])
	h.check(float(h.replicas[0].follow.fx.get("fov", 0.0)) < 0.0 and h.replicas[0].follow.fx.get("around") != null, "the lens closes and the camera swings round")
	h.check(_tags(0, 1) == 1 and _tags(0, 0) == 0, "the REC / LIVE tag is over slot 0 on the other screen only (%d, %d)" % [_tags(0, 1), _tags(0, 0)])
	h.check(h.replicas[0].rigs[0].get_look().equals(look_before), "the player's own look is kept under the override")
	await h.tick(30)
	_shoot("f_filter")
	await h.tick(60)
	_shoot("g_late")
	await h.tick(30)
	_shoot("h_out")
	var over: bool = await h.wait_until(func() -> bool: return _fx_of(0, kind).is_empty(), 60 * 4)
	h.check(over, "the seconds run out")
	await h.tick(12)
	_shoot("i_restored")
	await h.tick(10)
	for index in 2:
		var rig: Node = h.replicas[index].rigs[0]
		h.check(str((rig.get("_applied") as Dictionary).get("head", "")) == head_before and rig.get_look().equals(look_before), "replica %d: slot 0's own look is back exactly" % index)
	await h.tick(40)
	for index in 2:
		h.check(h.replicas[index].rigs[0].emote_playing() != "dance", "replica %d: the dance has stopped" % index)
	h.check(_frames(0) == 0 and _zoom(0) == 0.0 and h.replicas[0].item_mods.is_empty(), "the letterbox, the zoom and the freeze are gone")
	h.check(_tags(0, 1) == 0, "the tag is gone")

	# ---- the throw that misses: nobody in front of the thrower
	await _stand(thrower, 43.5)
	await _stand(0, 38.5)
	await _stand(other, 37.5)
	h.check(h.give(thrower, "dance"), "slot %d holds a second dance" % thrower)
	await h.tick(4)
	h.press_item(thrower)
	await h.tick(6)
	st = h.state()
	h.check(st.items.proj.size() == 1 and int(st.items.proj[0][8]) == -1, "a throw with nobody in the cone has no lock")
	await h.tick(14)
	_shoot("j_miss_flight")
	var gone: bool = await h.wait_until(func() -> bool: return h.state().items.proj.is_empty(), 60 * 4)
	h.check(gone, "the miss pops on the floor or at the end of its life")
	await h.tick(3)
	_shoot("k_miss_pop")
	await h.tick(8)
	h.check(h.state().items.fx.is_empty() and int(h.state().items.held[thrower]) == -1, "a miss puts nothing on anybody and the item is spent")
	h.check(h.views[0]._items._shots.is_empty() and h.views[1]._items._shots.is_empty(), "the clients dropped the phone")

func _shoot(name: String) -> void:
	print("DANCE shot ", name, " at ", Time.get_ticks_msec() / 1000, " s, physics frame ", Engine.get_physics_frames())
	_h.shoot(name)

## Stands the scripted racer `metres` along the route, facing along it (it takes a few steps to turn).
func _stand(slot: int, metres: float) -> void:
	_h.progress(slot, metres)
	await _h.tick(8)
	_h.release(slot)
	await _h.tick(5)
	_h.hold(slot)
	await _h.tick(10)

func _fx_of(slot: int, kind: int) -> Array:
	for row: Array in _h.state().items.fx:
		if int(row[1]) == slot and int(row[2]) == kind: return row
	return []

func _frames(index: int) -> int:
	var count := 0
	for child in _h.views[index]._items.over_layer.get_children():
		if child.get_script() == DanceFrame: count += 1
	return count

func _zoom(index: int) -> float:
	return float(_h.replicas[index].follow.fx.get("zoom", 0.0))

## The REC / LIVE tags hanging on slot `slot`'s rig on replica `index`.
func _tags(slot: int, index: int) -> int:
	var count := 0
	for child in _h.replicas[index].rigs[slot].get_children():
		if child.name == "LiveTag": count += 1
	return count
