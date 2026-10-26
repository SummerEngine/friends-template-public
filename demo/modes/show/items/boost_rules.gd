extends "res://modes/show/items/item_rule.gd"
## BOOST (an event, the "new subscriber"): the clock picks a runner at the back; for `duration` s it runs `speed` times as fast, glows gold and flings whoever it runs into (`shove`).
## The owner's machine applies the speed and the shove from the replicated effect (boost_view.gd `mods`, game/game_run.gd item_mods / item_power).

func happen(slot: int) -> void:
	items.add_fx(slot, id, items.tune(id, "duration"), items.tune(id, "speed"), items.tune(id, "shove"))
