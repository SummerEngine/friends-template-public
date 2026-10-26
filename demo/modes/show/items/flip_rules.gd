extends "res://modes/show/items/item_rule.gd"
## FLIP (a global item): every racer but the user walks the other way (left is right, forward is back) for `duration` s. The effect is the whole of it: each victim's own machine flips
## its steering from the replicated effect (flip_view.gd `mods`, game/game_run.gd item_move).

func use(user: int) -> bool:
	var victims: Array = items.racers().filter(func(slot: int) -> bool: return slot != user)
	if victims.is_empty(): victims = items.self_test(user) # the lab alone: the user's own controls flip
	if victims.is_empty(): return false
	var duration: float = items.tune(id, "duration")
	for slot: int in victims: items.add_fx(slot, id, duration, 0.0, 0.0, user)
	return true
