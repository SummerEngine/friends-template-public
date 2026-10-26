extends RefCounted
## The night look: the show's second world (cast `world.style` "night", docs/backdrop.md "The night look"): near-black glossy metal under a dark sky
## with a metal sun, thin glowing lines in the brand's accent, dark obstacles with accent trim, and the same palette roles as the party look
## (style/party_look.gd makes the palette in night tones and hands it here). Pure data: `spec()` has the shape of `Surfaces.LOOK` (style/surfaces.gd
## hands it out through Party.spec()), so the whole course takes it without any other change; the open-air world is style/night_backdrop.gd and the
## sky style/night_sky.gdshader (levels/level_environment.gd builds it from `light`).
##
## What it keeps from the party look: the lit, readable course. Players, hop blocks and hazards (the red is the same) stand out of a dark floor,
## picture faces are lit prints on light boards, and lettering is light on dark and dark on the accent. Only emission carries the light of the
## world: one sun (warm, low) and one ambient colour, no other light; the glow is the environment's own (hdr threshold 1: only the lines and the
## trim bloom).

static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)

## The `Surfaces.LOOK` of the night look from the night palette `p` (style/party_look.gd `palette()`).
static func spec(p: Dictionary) -> Dictionary:
	var cp: Dictionary = p.p
	var cs: Dictionary = p.s
	var line := _hex(cp.main)
	var blocks: Array = []
	for color: Color in p.blocks: blocks.append(_hex(color))
	var floor_top := {"set": "plastic", "tint": _hex(p.floor_a), "tint3": _hex(p.floor_b), "tint2": line, "pattern": 5, "pattern_size": 2.0, "line": 0.03, "glow": 0.9,
		"tile": 4.0, "detail": 0.0, "rough": 0.34, "metal": 0.2, "spec": 0.9, "ao": 0.9}
	var wall := {"set": "plastic", "tint": _hex(p.wall), "tint3": _hex(p.wall2), "tint2": _hex((cp.deep as Color)), "pattern": 6, "pattern_size": 4.0, "line": 0.03, "glow": 0.8,
		"tile": 4.0, "detail": 0.0, "rough": 0.5, "metal": 0.15, "spec": 0.6, "ao": 0.9, "rim": 0.3}
	var accent_wall := wall.duplicate()
	accent_wall.tint2 = _hex((cs.main as Color))
	var spec := {
		"surfaces": {
			"floor": floor_top,
			"base": {"set": "plastic", "tint": _hex(p.base), "tint2": line, "pattern": 7, "pattern_size": 1.5, "line": 0.035, "glow": 0.8, "tile": 4.0, "detail": 0.0,
				"rough": 0.4, "metal": 0.2, "ao": 0.7, "rim": 0.2},
			"wall": wall,
			"wall_brand": accent_wall,
			"block": {"set": "plastic", "tint": "#ffffff", "tile": 3.0, "detail": 0.05, "rough": 0.45, "metal": 0.2, "rough_add": 0.0, "vtint": 1.0, "ao": 0.9, "rim": 0.35, "emit": 0.28},
			"ice": {"set": "plastic", "tint": _hex(p.ice), "tint2": _hex((cs.soft as Color)), "pattern": 5, "pattern_size": 1.0, "line": 0.03, "glow": 0.9, "tile": 3.0,
				"detail": 0.0, "rough": 0.08, "metal": 0.3, "ao": 0.6, "spec": 1.0, "rim": 0.25},
			"mover": {"set": "plastic", "tint": _hex(p.steel_dark), "tint2": _hex((cp.main as Color)), "pattern": 3, "pattern_size": 0.25, "tile": 3.0, "detail": 0.0, "rough": 0.5, "metal": 0.4,
				"ao": 0.0, "rim": 0.2, "emit": 0.3},
			"mover_top": {"set": "plastic", "tint": _hex(p.steel_dark), "tint3": _hex(p.floor_b), "tint2": line, "pattern": 5, "pattern_size": 0.5, "line": 0.03, "glow": 1.2,
				"tile": 3.0, "detail": 0.0, "rough": 0.4, "metal": 0.5, "ao": 0.0, "rim": 0.1},
			"danger": {"set": "plastic", "tint": _hex(p.danger), "tile": 3.0, "detail": 0.0, "rough": 0.5, "metal": 0.2, "ao": 0.0, "rim": 0.3, "emit": 0.55},
			"trim": {"set": "plastic", "tint": _hex(cp.soft), "tile": 2.0, "detail": 0.0, "rough": 0.4, "metal": 0.3, "ao": 0.0, "rim": 0.1, "emit": 0.85},
			"steel": {"set": "plastic", "tint": _hex(p.steel), "tile": 1.0, "detail": 0.0, "rough": 0.35, "metal": 1.0, "ao": 0.0, "rim": 0.2},
			"room_wall": wall,
			"room_floor": floor_top,
			"ceiling": floor_top,
		},
		"block_colors": blocks,
		"radius": {"floor": 0.03, "base": 0.03, "wall": 0.05, "block": 0.2, "ice": 0.05, "mover": 0.05, "danger": 0.08, "trim": 0.0},
		"segments": {"block": 3, "mover": 2},
		"band": [1.0, 1.3],
		"signage": {"frame": _hex(p.steel), "frame_metal": 0.9, "frame_rough": 0.35, "board": "#e9e6df", "post": _hex(p.steel), "post_metal": 0.9,
			"mat": _hex(p.mat), "text": _hex(p.lettering)},
		"room": {"number": _hex(p.lettering)},
		"light": {"sun": _hex(p.sun), "sun_energy": 1.4, "sun_dir": [-0.42, -0.55, -0.55], "shadow_blur": 1.5,
			"sky_top": _hex(p.sky_top), "sky_horizon": _hex(p.sky_horizon), "ground": _hex(p.sea), "ambient_energy": 1.0, "ambient_color": _hex(p.ambient),
			"fog": _hex(p.fog), "fog_density": 0.0007, "background": 1.0, "sky_background": true, "lamp": "#ffffff", "lamp_energy": 1.0,
			"night": true, "glow_color": _hex(cp.main), "disc_core": _hex(p.trim), "disc_dir": [0.28, 0.2, -1.0], "planet_dir": [-0.75, 0.36, -0.55],
			"tonemap": "aces", "contrast": 1.0, "white": 4.0, "exposure": 1.25},
	}
	return spec
