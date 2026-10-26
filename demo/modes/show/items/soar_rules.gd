extends "res://modes/show/items/item_rule.gd"
## SOAR (an event, "the video went viral"): the clock picks a runner at the back; for `duration` s its jump is `jump` times as fast off the ground and it has `air_jumps` more jumps in the air (a double jump). The owner's machine applies it from the replicated effect (soar_view.gd `mods`, game/game_run.gd item_mods, courier/courier_motion.gd); the views counter
## that climbs 10K, 100K, 1M is only drawn (soar_view.gd).

func happen(slot: int) -> void:
	items.add_fx(slot, id, items.tune(id, "duration"), items.tune(id, "jump"), items.tune(id, "air_jumps"))
