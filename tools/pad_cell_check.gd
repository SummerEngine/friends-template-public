extends SceneTree
## Every launch pad of the `world: daylight` levels (push volumes 2.8 m or wider, drawn by style/pad_look.gd as a round button on a 2 x 2 block of tiles) stands on the middle of a 2 x 2 cell of
## the platform under it, as the real BlockKit.tile_grid has it (tools/kit_grid.py is the generators' mirror of that grid), and keeps clear of the platform's rim.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --rendering-driver dummy --path demo -s $PWD/tools/pad_cell_check.gd [-- --levels=29,30]
## Prints PAD_CELL lines and `PAD_CELL ok pads=<n>` (exit 0) or `PAD_CELL FAIL ...` (exit 1).
const BlockKit := preload("res://style/block_kit.gd")
const TOLERANCE := 0.03    ## m: how far a pad's middle may be from its cell's middle
const RIM_CLEAR := 0.3     ## m: the pad's round button keeps at least this far from the platform's edge
const PadLook := preload("res://style/pad_look.gd")

func _initialize() -> void:
	var levels: Array = [29, 30]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--levels="):
			levels = []
			for part in argument.trim_prefix("--levels=").split(","): levels.append(int(part))
	var pads := 0
	var failed := 0
	for number: int in levels:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/level_%02d.json" % number))
		if not data is Dictionary: continue
		for h: Dictionary in data.hazards:
			if str(h.k) != "push" or float(h.get("d", h.get("s", [0, 0, 0])[0])) < 2.8: continue
			pads += 1
			var p: Array = h.p
			var best := {}
			for b: Dictionary in data.blocks:
				if str(b.k) != "box" or b.has("r") or str(b.get("m", "")) in ["belt", "ice"]: continue
				var c: Array = b.p
				var s: Array = b.s
				if absf(float(c[1]) + float(s[1]) * 0.5 - (float(p[1]) - 1.0)) > 0.02: continue
				if absf(float(p[0]) - float(c[0])) > float(s[0]) * 0.5 or absf(float(p[2]) - float(c[2])) > float(s[2]) * 0.5: continue
				best = b
			if best.is_empty():
				print("PAD_CELL FAIL level %d %s: no platform under it" % [number, h.id])
				failed += 1
				continue
			var size := Vector3(float(best.s[0]), float(best.s[1]), float(best.s[2]))
			var xf := Transform3D(Basis.IDENTITY, Vector3(float(best.p[0]), float(best.p[1]), float(best.p[2])))
			var grid: Dictionary = BlockKit.tile_grid(xf, size)
			if grid.is_empty() or int(grid.nx) < 2 or int(grid.nz) < 2:
				print("PAD_CELL FAIL level %d %s: the platform %s has no 2 x 2 cell" % [number, h.id, str(size)])
				failed += 1
				continue
			var diameter := float(h.get("d", 0.0))
			var tiles := int(grid.nx)
			var span := float(tiles) * float(grid.t) + float(tiles - 1) * BlockKit.GROOVE
			if tiles == int(grid.nz) and diameter >= span - PadLook.FULL_SLACK:
				# a pad over the whole stone (style/pad_look.gd cell_side): centred on the stone, its round button the grid's side less the margin, clear of the stone's rim
				var middle := Vector2(float(p[0]) - float(best.p[0]), float(p[2]) - float(best.p[2])).length()
				var round_button := (span - PadLook.CELL_MARGIN) * 0.5
				var rim := minf(float(best.s[0]), float(best.s[2])) * 0.5 - round_button
				var full_ok := middle <= PadLook.FULL_CENTRE and rim >= RIM_CLEAR
				print("PAD_CELL level %d %s whole stone %s: %dx%d tiles of %.2f, pad %.2f m over the grid's %.2f, off %.3f, rim clear %.2f %s" % [number, h.id, str(size), tiles, tiles, float(grid.t), diameter, span, middle, rim, "ok" if full_ok else "FAIL"])
				if not full_ok: failed += 1
				continue
			var origin: Vector3 = grid.origin
			var pitch := float(grid.pitch)
			var i := roundf((float(p[0]) - origin.x) / pitch - 0.5)
			var j := roundf((float(p[2]) - origin.z) / pitch - 0.5)
			var cell := Vector2(origin.x + pitch * (i + 0.5), origin.z + pitch * (j + 0.5))
			var off := Vector2(float(p[0]), float(p[2])).distance_to(cell)
			var button := (2.0 * float(grid.t) + BlockKit.GROOVE - PadLook.CELL_MARGIN) * 0.5 # the button's radius: the cell less the margin, halved
			var edge := minf(minf(float(best.s[0]) * 0.5 - absf(float(p[0]) - float(best.p[0])), float(best.s[2]) * 0.5 - absf(float(p[2]) - float(best.p[2]))), 99.0) - button
			var ok := off <= TOLERANCE and edge >= RIM_CLEAR and i >= 0 and j >= 0 and i <= int(grid.nx) - 2 and j <= int(grid.nz) - 2
			print("PAD_CELL level %d %s platform %s tile %.2f cell (%d,%d) of %dx%d off %.3f rim clear %.2f %s" % [number, h.id, str(size), float(grid.t), int(i), int(j), int(grid.nx), int(grid.nz), off, edge, "ok" if ok else "FAIL"])
			if not ok: failed += 1
	print("PAD_CELL ", "ok" if failed == 0 else "FAIL", " pads=", pads, " failed=", failed)
	quit(0 if failed == 0 else 1)
