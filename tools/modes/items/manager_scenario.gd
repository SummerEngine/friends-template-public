extends RefCounted
## EXPERIMENT (switchable): THE MANAGER end to end (modes/show/manager/, docs/party-show.md): the authority, three scripted racers and two replica clients with the show's real view and HUD.
## Run it in a race (`--show-level=31`: also checks that the manager's press does not use its item) and in a tile round (`--pick=r25`):
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 280 "$SUMMER" --headless --audio-driver Dummy --rendering-driver dummy --fixed-fps 60 --path demo \
##     -s "$PWD/tools/modes/items_harness.gd" -- --scenario=manager --show-level=31        (or: -- --scenario=manager --pick=r25)
## Slot 2 has no client: it is the manager of the first half (both clients are its victims, every rule is forced in turn and read on both machines). Then slot 0 is the manager: its client
## asks for the number keys, shows the cards, a typed key and a tap travel as test_seq to the authority and pick the rule.
const Catalog := preload("res://modes/show/shared/manager/manager_catalog.gd")
const ManagerRules := preload("res://modes/show/shared/manager/manager_rules.gd")

func run(h) -> void:
	for slot in 3: h.hold(slot)
	await h.tick(20)
	await h.wait_until(func() -> bool: return float(h.state().get("t", 0.0)) > 1.4, 60 * 4) # the show's GO banner has cleared (a banner of ours waits for it too)
	var rules = h.rules()
	var m: ManagerRules = rules.manager
	var race: bool = str(h.state().kind) == "race"
	if race: rules.items._next_event_at = 1.0e9 # the clock's BOOST / SOAR stay out of the way of what is read here
	h.check(m.enabled and h.state().has("manager") and rules.field.has(m.manager), "the round has a manager from the field (slot %d) and its state is in the show's state" % m.manager)
	# the first banner and the clipboard, on both machines
	await h.wait_until(func() -> bool: return str(h.views[0]._manager.banner.get("words", "")) == "THE MANAGER" and str(h.views[1]._manager.banner.get("words", "")) == "THE MANAGER", 60 * 4)
	for index in 2: h.check(str(h.views[index]._manager.banner.get("words", "")) == "THE MANAGER", "client %d reads the banner THE MANAGER (%s)" % [index, str(h.views[index]._manager.banner.get("line", ""))])
	h.shoot("intro")
	for index in 2:
		var rig: Node = h.replicas[index].rigs[m.manager]
		var anchor: Node = rig.call("head_anchor") if rig != null and rig.has_method("head_anchor") else null
		h.check(anchor != null and anchor.get_node_or_null("ManagerMarker") != null, "client %d draws the clipboard on the manager's head" % index)
	# slot 2 is the manager from here on; both clients are ruled; the prompts come when this script says (the clock's next prompt is put far away)
	m.manager = 2
	h.check(not h.replicas[0].number_keys and not h.replicas[1].number_keys, "no client asks for the number keys while no prompt is open")
	m._next_at = m.time + 0.3
	rules.gate.reset() # the gate is open for the next prompt (a rule that just ended keeps it closed for 15 s)
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 60 * 3)
	m._next_at = 1.0e9
	await h.tick(12)
	h.check(m.phase == ManagerRules.Phase.PROMPT and (h.state().manager.ch as Array).size() == 3, "the prompt is open with three choices (%s)" % str(h.state().manager.ch))
	for index in 2:
		var model: Dictionary = h.views[index]._manager.hud.model
		h.check(int(model.info.ph) == 1 and not bool(model.mine) and not h.replicas[index].number_keys, "client %d (not the manager) sees that the manager is picking and asks for no keys" % index)
	h.shoot("waiting")
	var choices: Array = m.choices.duplicate()
	if race: # the manager holds an item and presses ITEM for its random pick: the item stays
		h.check(h.give(2, "flip"), "the manager holds FLIP")
		await h.tick(4)
	h.press_item(2)
	await h.tick(3)
	h.check(m.phase == ManagerRules.Phase.RULE and choices.has(m.rule), "ITEM picked a random one of the three (%s)" % Catalog.id_of(m.rule))
	if race: h.check(int(h.rules().items.held[2]) == h.rules().items.Catalog.index("flip"), "the same press did not use the manager's FLIP")
	await h.tick(8)
	h.check(not bool((h.state().manager.tg as Array).has(2)) and (h.state().manager.tg as Array).size() == 2, "the rule is for the two clients, not for the manager (%s)" % str(h.state().manager.tg))
	h.check(h.views[0]._manager.banner.get("words", "") == Catalog.rule_text(Catalog.id_of(m.rule), "banner") and h.views[0]._manager.banner.kind == "alert", "a victim's screen shows the rule's banner in red (%s)" % str(h.views[0]._manager.banner.get("words", "")))
	h.shoot("rule_banner")
	m.age = m.dur - 0.2 # let that one go
	await h.tick(30)
	# every rule, forced one after the other, read on both machines
	for id: String in Catalog.order():
		await _rule(h, m, id)
	# slot 0 is the manager: its client asks for the keys, a typed key and a tap pick
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 60 * 5)
	m.manager = 0
	m._next_at = m.time + 0.3
	rules.gate.reset() # the gate is open for the next prompt (a rule that just ended keeps it closed for 15 s)
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.PROMPT, 60 * 3)
	h.check(m.phase == ManagerRules.Phase.PROMPT and m.manager == 0, "slot 0's prompt is open")
	m._next_at = 1.0e9
	await h.tick(12)
	h.check(h.replicas[0].number_keys and not h.replicas[1].number_keys, "only the manager's client asks for the number keys (phase %d, manager %d, state %s)" % [m.phase, m.manager, str(h.state().get("manager"))])
	var cards: Array = h.views[0]._manager.hud._cards
	h.check(cards.size() == 3 and cards.all(func(card: Control) -> bool: return card.visible), "the manager's screen shows the three cards")
	h.check(not (h.views[1]._manager.hud._cards as Array).any(func(card: Control) -> bool: return card.visible), "the other screen shows none")
	h.shoot("prompt")
	_key(KEY_2)
	await h.tick(2)
	var typed: Dictionary = h.replicas[0].collect_owner_input()
	var other: Dictionary = h.replicas[1].collect_owner_input()
	h.check(int(typed.get("tests", 0)) == 2 and int(other.get("tests", 0)) == 0, "the key 2 reaches the manager's input as test 2 (%s) and no other client's (%s)" % [str(typed.get("tests", 0)), str(other.get("tests", 0))])
	h.views[0]._manager.tap(0)
	await h.tick(2)
	typed = h.replicas[0].collect_owner_input()
	h.check(int(typed.get("tests", 0)) == 1, "a tap on the first card travels as the key 1 (%s)" % str(typed.get("tests", 0)))
	choices = m.choices.duplicate()
	h.press_lab(0, 3) # what the client's test_seq carries to the authority for the key 3
	await h.tick(3)
	h.check(m.phase == ManagerRules.Phase.RULE and m.rule == int(choices[2]), "the key 3 picked the third card (%s)" % Catalog.id_of(m.rule))
	h.check(not (h.state().manager.tg as Array).has(0) and (h.state().manager.tg as Array).size() == 2, "the manager (slot 0) is not ruled, the others are (%s)" % str(h.state().manager.tg))
	await h.tick(8)
	h.check(not h.replicas[0].number_keys, "the prompt is closed: the keys are not asked for any more")
	m.age = m.dur - 0.2
	await h.tick(30)
	# the upside-down camera is the victims': slot 0 is the manager, client 0 keeps its camera upright, client 1 (a victim) turns over
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 60 * 5)
	m.manager = 0
	m._next_at = 1.0e9
	m._issue(Catalog.index("upside"))
	m.dur = 2.6
	await h.tick(54 + 66)
	var manager_roll := float(h.replicas[0].follow.fx.get("roll", 0.0))
	var victim_roll := float(h.replicas[1].follow.fx.get("roll", 0.0))
	h.check(absf(manager_roll) < 0.01 and absf(victim_roll - Catalog.camera_roll("upside")) < 0.05, "upside with slot 0 as the manager: its screen stays upright (%.2f), the victim's turns over (%.2f)" % [manager_roll, victim_roll])
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 60 * 5)
	await h.tick(40)

## Forces rule `id` (3 s) with slot 2 as the manager and reads both machines.
func _rule(h, m: ManagerRules, id: String) -> void:
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 60 * 5)
	m.manager = 2
	m._next_at = 1.0e9
	m._issue(Catalog.index(id))
	m.dur = 2.6
	await h.tick(54 + 66) # the lead (0.9 s), then 1.1 s of the rule: the rig scale and the camera have grown in
	var label := "rule %s" % id
	h.check(int(h.state().manager.rule) == Catalog.index(id) and int(h.state().manager.ph) == 2, "%s: the state says it is on" % label)
	for index in 2:
		var shell = h.replicas[index]
		var mods: Dictionary = shell.rule_mods.get(index, {})
		h.check(shell.rule_mods.get(2) == null and shell.rule_scales.get(2) == null, "%s: client %d: nothing on the manager (slot 2)" % [label, index])
		var spec: Dictionary = Catalog.mods(id)
		for key: String in spec:
			h.check(mods.get(key) == spec[key], "%s: client %d: slot %d carries %s = %s" % [label, index, index, key, str(spec[key])])
		var want := Catalog.scale_of(id)
		if want != Vector3.ONE:
			var got: Vector3 = shell.rule_scales.get(index, Vector3.ONE)
			var rig: Node3D = shell.rigs[index]
			var drawn := rig.global_basis.get_scale() if rig != null else Vector3.ONE
			h.check(absf(got.x - want.x) < 0.05 and absf(drawn.x - want.x) < 0.1, "%s: client %d: its own rig is scaled to %.2f (rule %.2f, drawn %.2f)" % [label, index, want.x, got.x, drawn.x])
			var other: Node3D = shell.rigs[1 - index]
			h.check(absf(other.global_basis.get_scale().x - want.x) < 0.1, "%s: client %d sees the other victim's rig at %.2f" % [label, index, other.global_basis.get_scale().x])
			h.check(absf(shell.rigs[2].global_basis.get_scale().x - 1.0) < 0.02, "%s: client %d sees the manager's rig at its own size" % [label, index])
		if id == "flip":
			var step := Vector2(0.6, -0.8)
			h.check(shell.item_move(index, step) == -step and shell.item_move(2, step) == step, "%s: client %d: the steering is flipped for it, not for the manager" % [label, index])
		if Catalog.camera_roll(id) != 0.0:
			var roll := float(shell.follow.fx.get("roll", 0.0))
			h.check(absf(roll - Catalog.camera_roll(id)) < 0.05, "%s: client %d: the camera is turned over (roll %.2f)" % [label, index, roll])
	if id == "giant" or id == "upside" or id == "flip": h.shoot("rule_" + id)
	await h.wait_until(func() -> bool: return m.phase == ManagerRules.Phase.IDLE, 60 * 5)
	await h.tick(40)
	for index in 2:
		var shell = h.replicas[index]
		var fx: Dictionary = shell.follow.fx
		var free: bool = shell.rule_mods.is_empty() and shell.rule_scales.is_empty() and absf(float(shell.follow.fx.get("roll", 0.0))) < 0.02 and not shell.follow.fx.has("manager_roll")
		var detail := "rig scale %.2f, roll %.2f, mods %s, scales %s, fx %s, items %s" % [shell.rigs[index].global_basis.get_scale().x, float(fx.get("roll", 0.0)), str(shell.rule_mods), str(shell.rule_scales), str(fx), str(shell.item_mods)]
		h.check(free and absf(shell.rigs[index].global_basis.get_scale().x - 1.0) < 0.05, "%s: client %d is free again when it ends (%s)" % [label, index, detail])

func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		Input.parse_input_event(event)
