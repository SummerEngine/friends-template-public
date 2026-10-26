extends RefCounted
## Frame times around every item's pick and use (the "game freezes for a second when I use a power-up" check), first use against second use. Needs the offscreen binary with `--measure=<csv>` (one row per drawn frame,
## see tools/modes/items_harness.gd) and the cast with the item lab on (`--cast=<cast.json>`); `tools/modes/items_hitch_report.py <csv>` prints the table.
##   --view=1: the user's screen (slot 1 uses, slot 0 ahead is hit)    --view=0: the victim's screen (slot 2 uses, slots 0 and 1 are hit)
##   --order=smash,call,...   the items' order (default all, the catalog's); --rounds=2   how many times each is used
## Labels in the csv: `<id>/<n>/pick` (the lab key until ITEM is pressed), `<id>/<n>/use` (ITEM pressed until the effect has had time to show), `idle` (nothing happening), `warm` (the first seconds).
const PICK_TICKS := 75
const USE_TICKS := 240
const SETTLE_MAX := 900

func run(h) -> void:
	var order: Array = ["smash", "call", "flip", "glitch", "dance", "boost", "soar"]
	var rounds := 2
	var user: int = 1 if h.shot_view == 1 else 2
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--order="): order = argument.trim_prefix("--order=").split(",")
		if argument.begins_with("--rounds="): rounds = int(argument.trim_prefix("--rounds="))
	for slot in 3: h.hold(slot)
	h.focus()
	h.mark("warm")
	h.progress(0, 22.0)
	h.progress(1, 14.0)
	h.progress(2, 6.0)
	await h.tick(20)
	await h.wait_until(func() -> bool: return float(h.state().get("t", 0.0)) > 1.4, 60 * 4) # the show's GO banner has cleared
	var items = h.rules().items
	items.lab = true
	items._next_event_at = INF # the clock's own boost / soar (40 to 55 s into the race) would be a first use that is not in the table
	await h.tick(90)
	for round_no in range(1, rounds + 1):
		for id: String in order:
			await _settle(h, items)
			h.mark("idle")
			await h.tick(40)
			var number: int = items.Catalog.KINDS.find(id) + 1
			var event: bool = items.Catalog.EVENTS.has(id)
			h.mark("%s/%d/%s" % [id, round_no, "use" if event else "pick"])
			h.press_lab(user, number)
			if event:
				await h.tick(USE_TICKS)
				continue
			await h.tick(PICK_TICKS)
			h.check(int(h.state().items.held[user]) == number - 1, "%s #%d is in hand" % [id, round_no])
			h.mark("%s/%d/use" % [id, round_no])
			h.press_item(user)
			await h.tick(USE_TICKS)
	h.mark("idle")
	await _settle(h, items)
	h.mark("")

func _settle(h, items) -> void:
	h.mark("idle")
	await h.wait_until(func() -> bool: return h.state().items.fx.is_empty() and h.state().items.proj.is_empty(), SETTLE_MAX)
	for slot in 3: items.held[slot] = -1
	h.progress(0, 22.0)
	h.progress(1, 14.0)
	h.progress(2, 6.0)
	await h.tick(60)
