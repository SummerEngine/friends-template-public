extends "res://modes/show/items/item_rule.gd"
## GLITCH (the "hallucinating model", an item): everybody AHEAD of the user is drawn only once per `period` s (a lagging pose) and sees the screen sway, for `duration` s. `a` of the effect is
## the period, `b` the sway (the strength of the wobble). The effect is the whole of it: every client draws a victim's rig in jerks and the victim's own machine runs the wobble
## (glitch_view.gd `mods` lag, `camera`, the shader). Nobody ahead of the user: the item stays with its player.

func use(user: int) -> bool:
	var victims: Array = items.ahead_of(user)
	if victims.is_empty(): victims = items.behind_of(user) # in the lead: the pack behind gets it
	if victims.is_empty(): victims = items.self_test(user) # the lab alone: the user's own screen glitches
	if victims.is_empty(): return false
	var duration: float = items.tune(id, "duration")
	var period: float = items.tune(id, "period")
	var sway: float = items.tune(id, "sway")
	for slot: int in victims: items.add_fx(slot, id, duration, period, sway, user)
	return true
