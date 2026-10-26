extends "res://modes/show/items/item_rule.gd"
## SMASH (a held item, the hand from above): a giant hand comes down on the racer in the lead (never the user; the second place when the user leads). The effect lasts
## `warn` s of the shadow growing and the hand coming, `pin` s of the character lying flat and held in place, and SPRING s of it springing back; `a` is `warn`, `b` is `pin` for the
## views. The squash itself and the freeze are applied by the victim's own machine from the replicated effect (smash_view.gd `mods`). A leader who is already flat keeps the item
## with its player: nobody is smashed twice at once.
const SPRING := 0.45 ## s of the spring back (the view reads it as what is left of the effect's length after `a` and `b`)

func use(user: int) -> bool:
	var victim: int = items.leader(user)
	if victim < 0 and not items.self_test(user).is_empty(): victim = user # the lab alone: the hand comes down on the user
	if victim < 0 or not items.fx_of(victim, id).is_empty(): return false
	var warn: float = items.tune(id, "warn")
	var pin: float = items.tune(id, "pin")
	items.add_fx(victim, id, warn + pin + SPRING, warn, pin, user)
	return true
