extends SceneTree
## Headless check of the party look (style/party_look.gd, style/party_backdrop.gd): the palette rules over many brand palettes (greys, one
## colour, two near hues, dark, pastel, 3 vivid ones, none at all) and the backdrop rules for every show level and the lobby.
## Palette: the roles' hues keep apart, the stripes read on the cream, the checker is visible and light, the hazard red and the dark
## ink stand out of the track, the hop blocks stand out of it. Backdrop: every piece of the lit batches is entirely 25 m under the
## course or 14 m from its box on x/z; the confetti keeps off the route; counts stay inside the budget (draw calls, instances).
## Prints PARTY_CHECK lines; exit 1 on a violation.
##   FRIENDS_PRIORITY=1 tools/engine_slot.sh timeout -k 10 120 <Summer> --headless --audio-driver Dummy --path demo -s $PWD/tools/party_look_check.gd
const Data := preload("res://levels/level_data.gd")
const Backdrop := preload("res://style/backdrop.gd")
const PartyBackdrop := preload("res://style/party_backdrop.gd")
const Party := preload("res://style/party_look.gd")
const BuntingRule := preload("res://style/bunting_rule.gd")
const LobbyVisuals := preload("res://lobby_visuals.gd")
const Layout := preload("res://network/walk_in_lobby.gd")
const LobbySign := preload("res://lobby/lobby_sign.gd")
const TeamCast := preload("res://style/team_cast.gd")
const ShotLooks := preload("res://style/shot_looks.gd")
const PALETTES := [
	[], ["#ffffff"], ["#000000", "#ffffff"], ["#1d1d1f", "#888888"], ["#ff6a13"], ["#ff6a13", "#1d1d1f", "#3a5bd9"], ["#0e9aa7", "#4a2c82", "#8fe3b8"],
	["#2fb85a", "#ff5fa8"], ["#e60012"], ["#ffd400"], ["#fff200", "#ffe14d"], ["#1a237e"], ["#0d0d3a", "#12124f", "#1b1b6b"], ["#ffb3c1", "#b3e5fc", "#fff9c4"],
	["#ff0000", "#ff3300", "#ff6600"], ["#00ff00"], ["#0000ff"], ["#7b1fa2", "#f50057"], ["#795548", "#ffcc80"], ["#37474f", "#ff7043"],
	["#e53935", "#fdd835", "#1e88e5"], ["#006064", "#00acc1", "#b2ebf2"], ["#f48fb1"], ["#a5d6a7", "#2e7d32"],
	["#f0b566", "#141414", "#d9d9d9"], ["#0e9aa7", "#4a2c82", "#8fe3b8"], ["#ff6a13", "#1d1d1f", "#3a5bd9"], # the Summer cast, tidewheat, acme
]
const VIEWS := [Vector2(0.0, 2.8), Vector2(0.0, 3.6), Vector2(0.8, 2.8), Vector2(0.8, 3.6)] ## the lobby camera: m to the right (the shoulder view), m up
const MIN_SIDE := 14.0
const MIN_BELOW := 25.0
const MAX_DRAWS := 12
const MAX_INSTANCES := 1400
const MAX_TRIANGLES := 60000
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func fail(text: String) -> void:
	failures += 1
	print("PARTY_CHECK   FAIL ", text)

func run() -> void:
	var palettes: Array = PALETTES.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	for i in 37:
		var colors: Array = []
		for k in rng.randi_range(1, 3): colors.append("#" + Color.from_hsv(rng.randf(), rng.randf_range(0.2, 1.0), rng.randf_range(0.25, 1.0)).to_html(false))
		palettes.append(colors)
	for colors: Array in palettes: check_palette(colors)
	TeamCast.override({"format": "team-cast-v2", "mode": "show", "brand": {"colors": ["#ff6a13", "#1d1d1f", "#3a5bd9"]}})
	check_backdrops()
	for colors: Array in [["#0e9aa7", "#4a2c82", "#8fe3b8"], ["#ff6a13", "#1d1d1f", "#3a5bd9"], ["#f0b566", "#141414", "#d9d9d9"]]: check_lobby(colors)
	check_bunting_rule()
	check_bunting()
	var night_palettes: Array = PALETTES.duplicate()
	night_palettes.append_array([["#0b1f3a", "#22d3ee"], ["#0b1f3a", "#22d3ee", "#e6f7ff"], ["#05060a"], ["#101010", "#ffffff"], ["#7b1fa2", "#0d0d3a"]])
	night_palettes.append_array(palettes.slice(PALETTES.size()))
	for colors: Array in night_palettes: check_night_palette(colors)
	check_night_style()
	check_night_plates()
	TeamCast.override({"format": "team-cast-v2", "mode": "show", "world": {"style": "night"}, "brand": {"colors": ["#f0b566", "#141414", "#d9d9d9"]}})
	check_backdrops("night ")
	check_bunting()
	for colors: Array in [["#f0b566", "#141414", "#d9d9d9"], ["#0b1f3a", "#22d3ee"]]: check_lobby(colors, true)
	TeamCast.override({})
	print("PARTY_CHECK %s: %d palettes (+ %d night), %d violations" % ["OK" if failures == 0 else "FAILED", palettes.size(), night_palettes.size(), failures])
	quit(1 if failures > 0 else 0)

func check_palette(colors: Array) -> void:
	TeamCast.override({"format": "team-cast-v2", "mode": "show", "brand": {"colors": colors}})
	if not Party.on(): fail("%s: the party look is not on in show mode" % str(colors))
	var p := Party.palette()
	var spec := Party.spec()
	var label := str(colors)
	var h := Party.hues()
	for i in h.size():
		for k in range(i + 1, h.size()):
			var gap := Party.hue_gap(h[i], h[k])
			if gap < 0.03: fail("%s: roles %d and %d are %.2f of hue apart" % [label, i, k, gap])
	var cream: Color = p.cream
	if Party.contrast(p.wall, cream) < 1.65: fail("%s: wall stripes %.2f against the cream" % [label, Party.contrast(p.wall, cream)])
	if Party.contrast(p.base, cream) < 1.75: fail("%s: curb stripes %.2f" % [label, Party.contrast(p.base, cream)])
	if Party.contrast(p.floor_a, p.floor_b) < 1.2: fail("%s: the checker %.2f" % [label, Party.contrast(p.floor_a, p.floor_b)])
	if Party.luminance(p.floor_a) < 0.2: fail("%s: a dark track (%.2f)" % [label, Party.luminance(p.floor_a)])
	for floor_color: Color in [p.floor_a, p.floor_b]:
		if Party.contrast(p.danger, floor_color) < 1.5: fail("%s: the hazard red on the track %.2f" % [label, Party.contrast(p.danger, floor_color)])
		if Party.contrast(p.ink, floor_color) < 4.5: fail("%s: the ink on the track %.2f" % [label, Party.contrast(p.ink, floor_color)])
		for block: Color in p.blocks:
			if Party.contrast(block, floor_color) < 1.2: fail("%s: a hop block %s on the track %.2f" % [label, block.to_html(false), Party.contrast(block, floor_color)])
	for key: String in ["floor", "base", "wall", "wall_brand", "block", "ice", "mover", "mover_top", "danger", "steel"]:
		if not (spec.surfaces as Dictionary).has(key): fail("%s: no surface %s" % [label, key])
	if (spec.block_colors as Array).size() != p.blocks.size(): fail("%s: block colours" % label)
	for key: String in ["ink", "trim", "tiles", "signs"]:
		if not p.has(key): fail("%s: no %s" % [label, key])
	check_brand_surfaces(colors, p)
	check_ball_tones(p, false, label)

## The three tones of the balls (style/shot_looks.gd tone_colors: the ROLLING ROAD balls and the cannon balls, never the hazard red) stand out of both floor tones in either look:
## party, the body 2.0 and the panels 1.4 at least (and the panels differ from the body); night, the bright body 3.0 and the glowing lines (a paler tone) 3.0.
func check_ball_tones(p: Dictionary, night: bool, label: String) -> void:
	for index in 3:
		var tones := ShotLooks.tone_colors(p, night, index)
		var body: Color = tones[0]
		var second: Color = tones[1]
		for floor_color: Color in [p.floor_a, p.floor_b]:
			if Party.contrast(body, floor_color) < (3.0 if night else 2.0): fail("%s: ball tone %d %s on the floor %.2f" % [label, index, body.to_html(false), Party.contrast(body, floor_color)])
			if Party.contrast(second, floor_color) < (3.0 if night else 1.4): fail("%s: ball tone %d's second colour %s on the floor %.2f" % [label, index, second.to_html(false), Party.contrast(second, floor_color)])
		if not night and Party.contrast(body, second) < 1.15: fail("%s: ball tone %d panels %.2f from the body" % [label, index, Party.contrast(body, second)])

## The night look's palette for a brand (world.style "night"): every key of the party palette in dark tones that keep their contrast rules: floors and walls dark but not black,
## the accent lines, the hazard red, the hop blocks and the lettering far lighter than the floor, the lettering on the dark plates and the ink on the banners readable,
## the tiles a step apart and dark, the sky darker than any floor.
func check_night_palette(colors: Array) -> void:
	TeamCast.override({"format": "team-cast-v2", "mode": "show", "world": {"style": "night"}, "brand": {"colors": colors}})
	var label := "night " + str(colors)
	if not Party.night(): fail("%s: the night look is not on" % label)
	var p := Party.palette()
	var spec := Party.spec()
	for role: String in ["p", "s", "a", "x", "y"]:
		for tone: String in ["main", "deep", "soft", "pale"]:
			if not ((p[role] as Dictionary).has(tone)): fail("%s: no %s.%s" % [label, role, tone])
	for key: String in ["cream", "lettering", "ink", "trim", "danger", "tiles", "signs", "sky_top", "sky_horizon", "sea", "fog", "floor_a", "floor_b", "wall", "wall2", "base", "steel", "steel_dark",
			"mat", "sun", "ambient", "blocks", "confetti", "support", "ice"]:
		if not p.has(key): fail("%s: no %s" % [label, key])
	for key: String in ["floor", "base", "wall", "wall_brand", "block", "ice", "mover", "mover_top", "danger", "steel", "trim", "room_wall", "room_floor", "ceiling"]:
		if not (spec.surfaces as Dictionary).has(key): fail("%s: no surface %s" % [label, key])
	if not bool((spec.light as Dictionary).get("night", false)): fail("%s: the light is not the night's" % label)
	if (spec.block_colors as Array).size() != p.blocks.size(): fail("%s: block colours" % label)
	for dark: String in ["floor_a", "floor_b", "wall", "wall2", "base"]:
		var luminance := Party.luminance(p[dark])
		if luminance > 0.14 or luminance < 0.004: fail("%s: %s has luminance %.3f (a dark surface is 0.004 .. 0.14)" % [label, dark, luminance])
	if Party.luminance(p.sky_top) > 0.02: fail("%s: the sky's top is %.3f" % [label, Party.luminance(p.sky_top)])
	if Party.contrast(p.floor_a, p.floor_b) < 1.1: fail("%s: the two panel tones of the floor are %.2f apart" % [label, Party.contrast(p.floor_a, p.floor_b)])
	var accent: Color = (p.p as Dictionary).main
	for floor_color: Color in [p.floor_a, p.floor_b]:
		if Party.contrast(accent, floor_color) < 3.0: fail("%s: the glowing lines on the floor %.2f" % [label, Party.contrast(accent, floor_color)])
		if Party.contrast(p.danger, floor_color) < 1.8: fail("%s: the hazard red on the floor %.2f" % [label, Party.contrast(p.danger, floor_color)])
		if Party.contrast(p.lettering, floor_color) < 6.5: fail("%s: the lettering on the floor %.2f" % [label, Party.contrast(p.lettering, floor_color)])
		for block: Color in p.blocks:
			if Party.contrast(block, floor_color) < 1.6: fail("%s: a hop block %s on the floor %.2f" % [label, block.to_html(false), Party.contrast(block, floor_color)])
	for wall_color: Color in [p.wall, p.wall2]:
		if Party.contrast((p.p as Dictionary).deep, wall_color) < 2.0: fail("%s: the lines on the walls %.2f" % [label, Party.contrast((p.p as Dictionary).deep, wall_color)])
		if Party.contrast((p.s as Dictionary).main, wall_color) < 2.0: fail("%s: the accent wall's lines %.2f" % [label, Party.contrast((p.s as Dictionary).main, wall_color)])
	if Party.contrast(p.lettering, p.mat) < 8.0: fail("%s: the lettering on the plates %.2f" % [label, Party.contrast(p.lettering, p.mat)])
	if Party.contrast(p.lettering, p.steel) < 4.5: fail("%s: the lettering on the frames %.2f" % [label, Party.contrast(p.lettering, p.steel)])
	if Party.contrast(p.ink, Color.WHITE) < 10.0: fail("%s: the ink %s is not dark" % [label, (p.ink as Color).to_html(false)])
	check_ball_tones(p, true, label)
	var tiles: Array = p.tiles
	if tiles.size() != 3: fail("%s: %d tile tones" % [label, tiles.size()])
	for i in tiles.size():
		if Party.luminance(tiles[i]) > 0.1: fail("%s: tile tone %d is bright (%.3f)" % [label, i, Party.luminance(tiles[i])])
		for k in range(i + 1, tiles.size()):
			if Party.contrast(tiles[i], tiles[k]) < 1.1: fail("%s: tile tones %d and %d are %.2f apart" % [label, i, k, Party.contrast(tiles[i], tiles[k])])
	for kind: String in p.signs:
		var banner: Color = p.signs[kind]
		if Party.contrast(Party.text_on(banner), banner) < 3.5: fail("%s: the %s banner's text %.2f" % [label, kind, Party.contrast(Party.text_on(banner), banner)])
	for text: String in colors:
		var brand := Color(text)
		if Party._is_dark(brand):
			if (p.ink as Color).v > brand.v + 0.001: fail("%s: the near black %s is not the ink (%s)" % [label, text, (p.ink as Color).to_html(false)])
			break

## world.style: "night" and "party" as written, "auto" is night for a near-black first brand colour only, anything else (and nothing) is the party look; outside the
## show mode nothing is on at all.
func check_night_style() -> void:
	var cases := [["night", ["#f0b566"], "night"], ["party", ["#141414"], "party"], [null, ["#141414"], "party"], ["auto", ["#141414", "#f0b566"], "night"],
		["auto", ["#0b1f3a", "#22d3ee"], "night"], ["auto", ["#f0b566", "#141414"], "party"], ["auto", [], "party"], ["sunset", ["#141414"], "party"], ["NIGHT", ["#f0b566"], "night"]]
	for entry: Array in cases:
		var world := {} if entry[0] == null else {"style": entry[0]}
		TeamCast.override({"format": "team-cast-v2", "mode": "show", "world": world, "brand": {"colors": entry[1]}})
		if TeamCast.world_style() != entry[2]: fail("world.style %s with %s resolves to %s, expected %s" % [str(entry[0]), str(entry[1]), TeamCast.world_style(), entry[2]])
		if Party.night() != (entry[2] == "night"): fail("world.style %s with %s: Party.night() is %s" % [str(entry[0]), str(entry[1]), Party.night()])
	TeamCast.override({"format": "team-cast-v2", "mode": "carry", "world": {"style": "night"}, "brand": {"colors": ["#f0b566"]}})
	if Party.night(): fail("the night look is on outside the show mode")
	print("PARTY_CHECK night style: %d cases" % cases.size())

## A near-black obstacle plate would vanish on the night look's dark world: the cast's colour is lifted until white lettering reads on it; every other plate, and every plate in
## the party look, is the cast's own.
func check_night_plates() -> void:
	for text: String in ["#141414", "#000000", "#0b1f3a", "#1a0f2e", "#f0b566", "#d9d9d9", "#e5484d"]:
		var given := Color(text)
		for style: String in ["night", "party"]:
			TeamCast.override({"format": "team-cast-v2", "mode": "show", "world": {"style": style}, "obstacles": [{"label": "X", "color": text}]})
			var plate: Color = TeamCast.obstacle(1).color
			if style == "party" or given.v >= TeamCast.NIGHT_VALUE:
				if not plate.is_equal_approx(given): fail("%s plate %s was changed to %s" % [style, text, plate.to_html(false)])
			elif plate.get_luminance() <= 0.55 and Party.contrast(plate, Color.WHITE) < 4.0: fail("night plate %s lifted to %s: white lettering %.2f" % [text, plate.to_html(false), Party.contrast(plate, Color.WHITE)])
	print("PARTY_CHECK night plates ok")

## The brand leads the tiles and the signboards: every tile and every banner stays in the first colour's hue family (a derived tint, never another hue),
## the tiles' neighbours differ, the text of a banner reads, and a near-black brand colour is the ink and a light grey one the trim (never a floor).
func check_brand_surfaces(colors: Array, p: Dictionary) -> void:
	var label := str(colors)
	var h := Party.hues()
	var tiles: Array = p.tiles
	if tiles.size() != 3: fail("%s: %d tile tones" % [label, tiles.size()])
	for i in tiles.size():
		var tone: Color = tiles[i]
		if Party.hue_gap(tone.h, h[0]) > 0.05: fail("%s: tile tone %d is hue %.2f, the primary %.2f" % [label, i, tone.h, h[0]])
		if tone.s < 0.2: fail("%s: tile tone %d is washed out (s %.2f)" % [label, i, tone.s])
		if tone.v < 0.2: fail("%s: tile tone %d is mud (v %.2f)" % [label, i, tone.v])
		for k in range(i + 1, tiles.size()):
			if Party.contrast(tone, tiles[k]) < 1.1: fail("%s: tile tones %d and %d are %.2f apart" % [label, i, k, Party.contrast(tone, tiles[k])])
	for kind: String in p.signs:
		var banner: Color = p.signs[kind]
		if Party.hue_gap(banner.h, h[0]) > 0.06: fail("%s: the %s banner is hue %.2f, the primary %.2f" % [label, kind, banner.h, h[0]])
		if Party.contrast(Party.text_on(banner), banner) < 3.5: fail("%s: the %s banner's text %.2f" % [label, kind, Party.contrast(Party.text_on(banner), banner)])
	if Party._brand_hue_count() < 3 and not Party.night():
		var burnt: Color = (p.a as Dictionary).main
		if Party.hue_gap(burnt.h, h[0]) > 0.09 or burnt.v > 0.7: fail("%s: the accent (movers, flags) %s is not a burnt shade of the primary" % [label, burnt.to_html(false)])
		for role: String in ["x", "y"]:
			if Party.hue_gap(((p[role] as Dictionary).main as Color).h, h[0]) > 0.2: fail("%s: role %s is not a neighbour of the primary" % [label, role])
	if Party.contrast(p.ink, Color.WHITE) < 10.0: fail("%s: the ink %s is not dark" % [label, (p.ink as Color).to_html(false)])
	for text: String in colors:
		var brand := Color(text)
		if Party._is_dark(brand):
			if (p.ink as Color).v > brand.v + 0.001: fail("%s: the near black %s is not the ink (%s)" % [label, text, (p.ink as Color).to_html(false)])
			break
	for text: String in colors:
		var brand := Color(text)
		if Party._is_light_grey(brand):
			if not (p.trim as Color).is_equal_approx(brand): fail("%s: the light grey %s is not the trim (%s)" % [label, text, (p.trim as Color).to_html(false)])
			break

## The lobby of a brand: the circles' banners are the palette's, and all 9 boards read from the spawn and from every circle: from the shoulder camera
## (about 5.3 m behind the player, 2.8 and 3.6 m up, over the left or the right shoulder) no sight line to the text of a board (the title banner and the rule line, five points across)
## meets another board or a player standing on any circle or at a spawn seat (a character is a 0.35 m radius, 1.95 m tall column).
func check_lobby(colors: Array, night := false) -> void:
	TeamCast.override({"format": "team-cast-v2", "mode": "show", "world": {"style": "night" if night else "party"}, "brand": {"colors": colors}})
	var label := ("night lobby " if night else "lobby ") + str(colors)
	var pads: Array = Layout.shown_pads()
	var signs: Dictionary = Party.palette().signs
	if pads.size() != 9: fail("%s: %d circles, not 9 (THE SHOW and the 8 polished rounds: a front row of 4, a rear row of 5)" % [label, pads.size()])
	if not ((pads[0].color as Color).is_equal_approx(signs.show)): fail("%s: THE SHOW's banner is not the primary" % label)
	var boards: Array = [] # the plates (targets and blockers) and the masonry under them (blockers only)
	var spots: Array = []
	for entry: Dictionary in pads:
		var middle: Vector3 = entry.center - Layout.ORIGIN
		var sight := LobbySign.sight(entry)
		boards.append({"course": entry.course, "z": middle.z + LobbySign.FACE_Z, "x": middle.x, "size": sight.size, "bottom": float(sight.bottom), "rows": sight.rows, "columns": sight.columns})
		for solid: Dictionary in sight.solids:
			boards.append({"course": entry.course, "solid": true, "z": middle.z + float(solid.z), "x": middle.x, "size": Vector2(float(solid.width), float(solid.top) - float(solid.bottom)), "bottom": float(solid.bottom)})
		spots.append(middle)
	for slot in 4: spots.append(Layout.spawn(slot) - Layout.ORIGIN)
	var checked := 0
	for spot: Vector3 in spots:
		for view: Vector2 in VIEWS:
			var height := view.y
			var camera := Vector3(spot.x + view.x, height, spot.z + 5.3)
			for board: Dictionary in boards:
				if board.has("solid"): continue
				var size: Vector2 = board.size
				for line in 2:
					var row: float = (board.rows as Array)[line]
					for column: float in board.columns:
						var target := Vector3(float(board.x) + column * size.x, float(board.bottom) + row * size.y, float(board.z) + 0.02)
						var blocker := first_blocker(camera, target, boards, board, spots)
						checked += 1
						if blocker != "": fail("%s: from %s (camera %.1f m up) the %s sign's %s at x %+.1f is hidden by %s" % [label, spot.snapped(Vector3.ONE * 0.1), height, board.course, "title" if line == 0 else "rule line", column * size.x, blocker])
	for index in pads.size(): # the player on a circle is seen too (through the gaps of the front boards when it stands on a rear circle)
		var spot: Vector3 = spots[index]
		for view: Vector2 in VIEWS:
			var height := view.y
			var camera := Vector3(spot.x + view.x, height, spot.z + 5.3)
			for side: float in [-0.25, 0.0, 0.25]: # the body's width without the arms
				for body: float in [0.5, 1.2, 1.8]:
					checked += 1
					var blocker := first_blocker(camera, spot + Vector3(side, body, 0.0), boards, {}, [])
					if blocker != "": fail("%s: from %s (camera %.1f m up) the player on it (x %+.1f, %.1f m up) is hidden by %s" % [label, spot.snapped(Vector3.ONE * 0.1), height, side, body, blocker])
	print("PARTY_CHECK %s: %d circles, banners %s, %d sight lines" % [label, pads.size(), str(signs.keys()), checked])

## What stands between `camera` and `target` ("" for nothing): another board's face, or a character at one of `spots`.
func first_blocker(camera: Vector3, target: Vector3, boards: Array, board: Dictionary, spots: Array) -> String:
	for other: Dictionary in boards:
		if other == board or (other.has("solid") and other.course == board.get("course", "")): continue
		var z := float(other.z)
		if (camera.z - z) * (target.z - z) >= 0.0: continue # both on one side of the face
		var point := camera.lerp(target, (z - camera.z) / (target.z - camera.z))
		var half: Vector2 = (other.size as Vector2) * 0.5 + Vector2(0.04, 0.04)
		if absf(point.x - float(other.x)) <= half.x and point.y >= float(other.bottom) - 0.04 and point.y <= float(other.bottom) + (other.size as Vector2).y + 0.04: return "the %s %s" % [other.course, "pillar" if other.has("solid") else "sign"]
	for who: Vector3 in spots:
		for step in 80:
			var point := camera.lerp(target, (step + 1.0) / 82.0)
			if point.y > 1.95: break
			if Vector2(point.x - who.x, point.z - who.z).length() < 0.35: return "a player at %s" % who.snapped(Vector3.ONE * 0.1)
	return ""

func check_backdrops(prefix := "") -> void:
	var counts := Data.count()
	for number in range(1, counts + 1):
		var data := Data.load_level(number)
		if (data.modes as Array).has("show") == false: continue
		var spec := Backdrop.level_spec(data)
		var started := Time.get_ticks_usec()
		var root := Backdrop.for_level(number, data, Vector3.ZERO)
		check_world(root, spec, "%slevel %02d" % [prefix, number], float(Time.get_ticks_usec() - started) / 1000.0)
		root.free()
	var lobby_spec := {"bbox": Backdrop.LOBBY_BOX, "y_low": -0.65, "y_high": 3.4}
	var started := Time.get_ticks_usec()
	var lobby := Backdrop.for_lobby(Vector3.ZERO)
	check_world(lobby, lobby_spec, prefix + "lobby", float(Time.get_ticks_usec() - started) / 1000.0)
	lobby.free()

func check_world(root: Node3D, spec: Dictionary, label: String, built_ms: float) -> void:
	var bbox: Rect2 = spec.bbox
	var y_low: float = spec.y_low
	var y_high: float = spec.y_high
	var instances := 0
	var draws := 0
	var triangles := 0
	var parts: Array = []
	var nearest := INF
	for child: Node in root.get_children():
		if child is MeshInstance3D: draws += 1
		var node := child as MultiMeshInstance3D
		if node == null: continue
		draws += 1
		var multi := node.multimesh
		instances += multi.instance_count
		var shape_tris := 0
		for surface in multi.mesh.get_surface_count(): shape_tris += (multi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3) if multi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] != null else (multi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size() / 3)
		triangles += shape_tris * multi.instance_count
		parts.append("%s %d" % [node.name, multi.instance_count])
		var data: PackedFloat32Array = multi.buffer # 12 floats of transform (rows) then 4 of colour per instance
		for i in multi.instance_count:
			var b := i * 16
			var o := Vector3(data[b + 3], data[b + 7], data[b + 11])
			if node.name == "Supports": continue # hung straight under the course's own ground
			if node.name == "Bunting": continue # on the faces of the tall walls (they are the course)
			if node.name == "Confetti" or node.name == "Embers": # the night world's embers climb from the column's foot: the same start rule
				if bbox.has_point(Vector2(o.x, o.z)) and o.y < y_high + 8.0: fail("%s: %s column starts inside the course box at %s" % [label, node.name, o])
				continue
			var half := Vector3(absf(data[b]) + absf(data[b + 1]) + absf(data[b + 2]), absf(data[b + 4]) + absf(data[b + 5]) + absf(data[b + 6]),
				absf(data[b + 8]) + absf(data[b + 9]) + absf(data[b + 10])) * 0.5
			var gap_x := maxf(maxf(bbox.position.x - (o.x + half.x), (o.x - half.x) - bbox.end.x), 0.0)
			var gap_z := maxf(maxf(bbox.position.y - (o.z + half.z), (o.z - half.z) - bbox.end.y), 0.0)
			var side := Vector2(gap_x, gap_z).length()
			if o.y + half.y <= y_low - MIN_BELOW: continue
			nearest = minf(nearest, side)
			if side < MIN_SIDE: fail("%s: %s piece at %s (half %s) is %.1f m from the course box and not %.0f m below it" % [label, node.name, o, half, side, MIN_BELOW])
	if draws > MAX_DRAWS: fail("%s: %d draw calls (budget %d)" % [label, draws, MAX_DRAWS])
	if instances > MAX_INSTANCES: fail("%s: %d instances (budget %d)" % [label, instances, MAX_INSTANCES])
	if triangles > MAX_TRIANGLES: fail("%s: %d triangles (budget %d)" % [label, triangles, MAX_TRIANGLES])
	print("PARTY_CHECK %s: %d instances (%s) in %d draws, %d triangles, nearest lit piece %.1f m from the course box, built in %.1f ms" % [label, instances, ", ".join(parts), draws, triangles, nearest, built_ms])

## A made-up level with only blocks: {blocks, hazards, tiles, route, podium} as levels/level_data.gd gives them.
func synthetic(boxes: Array) -> Dictionary:
	var blocks: Array = []
	for box: Array in boxes:
		var size: Vector3 = box[1]
		blocks.append({"k": "box", "xf": Transform3D(Basis.IDENTITY, box[0]), "size": size, "m": "ground", "hit": false, "slot": ""})
	return {"blocks": blocks, "hazards": [], "tiles": {}, "route": PackedVector3Array(), "podium": []}

func kept_pennants(data: Dictionary) -> int:
	return BuntingRule.pennants(data).size()

## The placement rule on made-up levels: a tall wall over the floor wears bunting on both faces, stair risers, a wall that is a step of a
## flight, a low ledge and a wall that only rises a step over a platform wear none, and a wall hidden behind a taller one wears none on that face.
func check_bunting_rule() -> void:
	var ground := [Vector3(0, -0.5, 0), Vector3(80, 1, 80)]
	var hall := synthetic([ground, [Vector3(0, 3.0, -20), Vector3(24, 6, 1)]])
	if kept_pennants(hall) < 2 * 12: fail("bunting rule: a 6 m wall over the floor wears %d pennants, expected both faces" % kept_pennants(hall))
	for run: Dictionary in BuntingRule.plan(hall):
		if run.kept and run.clear < BuntingRule.MIN_CLEAR: fail("bunting rule: kept a run with clearance %.2f" % run.clear)
	var flight: Array = [ground]
	for step in 6: flight.append([Vector3(0, 0.75 + 0.75 * step, -4.0 * step), Vector3(12, 1.5 + 1.5 * step, 4)]) # risers every 1.5 m: steps 3 m and higher qualify as walls by height
	var stairs := synthetic(flight)
	var risers := 0
	for run: Dictionary in BuntingRule.plan(stairs):
		if run.kept and run.normal.z > 0.0: risers += run.count
	if risers > 0: fail("bunting rule: %d pennants on the risers of a flight of stairs" % risers)
	var ledge := synthetic([ground, [Vector3(0, 1.0, -10), Vector3(20, 2, 3)]])
	if kept_pennants(ledge) > 0: fail("bunting rule: pennants on a 2 m ledge")
	var platform := synthetic([ground, [Vector3(0, 3.0, -10), Vector3(20, 6, 3)], [Vector3(0, 2.0, -6), Vector3(20, 4, 4)]])
	for run: Dictionary in BuntingRule.plan(platform):
		if run.kept and run.block == 1 and run.normal.z > 0.0: fail("bunting rule: pennants on a wall face that rises 2 m over a platform in front of it")
	var free_face := BuntingRule.clearance(BuntingRule.solids(hall), 5.65, Vector3(0, 5.65, -19.5), Vector3.BACK, Vector3.RIGHT, 0.7, 1)
	if free_face < BuntingRule.MIN_CLEAR: fail("bunting rule: clearance of a free wall face %.2f" % free_face)
	print("PARTY_CHECK bunting rule: wall %d pennants, stair risers %d, 2 m ledge %d" % [kept_pennants(hall), risers, kept_pennants(ledge)])

## Every show level's bunting, listed run by run (block, face, pennants, line height, clearance over the nearest walkable top), and the pennants
## the backdrop really built re-measured against the solids: none may hang lower than MIN_CLEAR over a walkable top. The lobby's strings too.
func check_bunting() -> void:
	var counts := Data.count()
	for number in range(1, counts + 1):
		var data := Data.load_level(number)
		if (data.modes as Array).has("show") == false: continue
		var kept := 0
		var dropped := 0
		var lowest := INF
		for run: Dictionary in BuntingRule.plan(data):
			var text := "level %02d wall %3d %s face %+d: %2d pennants, line %.2f m, clearance %s%s" % [number, run.block, "kept   " if run.kept else "dropped", int(run.side), run.count, run.line_y, ("%.2f m" % run.clear) if run.clear != INF else "free", " (a walkway: its top is walked on)" if run.walkway else ""]
			if run.kept:
				kept += run.count
				lowest = minf(lowest, run.clear)
				if run.clear < BuntingRule.MIN_CLEAR: fail("%s: below the %.1f m limit" % [text, BuntingRule.MIN_CLEAR])
			else:
				dropped += run.count
			print("PARTY_CHECK   ", text)
		var root := Backdrop.for_level(number, data, Vector3.ZERO)
		var node := root.get_node_or_null("Bunting") as MultiMeshInstance3D
		var built := 0
		var list := BuntingRule.solids(data)
		if node != null:
			var multi := node.multimesh
			var buffer: PackedFloat32Array = multi.buffer
			built = multi.instance_count
			for i in built:
				var b := i * 16
				var at := Vector3(buffer[b + 3], buffer[b + 7], buffer[b + 11])
				var normal := Vector3(buffer[b + 2], 0.0, buffer[b + 10]).normalized() # the pennant's +z axis points out of the face
				var along := Vector3.UP.cross(normal)
				var clear := BuntingRule.clearance(list, at.y, at - normal * 0.1, normal, along, BuntingRule.STEP * 0.5)
				if clear < BuntingRule.MIN_CLEAR: fail("level %02d: built pennant %d at %s hangs %.2f m over a walkable top (limit %.1f)" % [number, i, at, clear, BuntingRule.MIN_CLEAR])
				if BuntingRule.near_podium(data.podium, at): fail("level %02d: built pennant %d at %s hangs in the podium shot" % [number, i, at])
		if built != kept: fail("level %02d: the backdrop built %d pennants, the plan keeps %d" % [number, built, kept])
		root.free()
		print("PARTY_CHECK level %02d bunting: %d pennants kept, %d dropped, lowest line over a walkable top %s" % [number, kept, dropped, ("%.2f m" % lowest) if lowest != INF else "none"])
	# the lobby: strings on the walls, every vertex (flags included) at head height or more over the yard's floor
	var room := Node3D.new()
	LobbyVisuals._bunting(room)
	var holder := room.get_node_or_null("Bunting") as MeshInstance3D
	if holder == null:
		fail("lobby: no bunting")
	else:
		var low := INF
		for surface in holder.mesh.get_surface_count(): for point: Vector3 in holder.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: low = minf(low, point.y - Layout.ORIGIN.y)
		if low < BuntingRule.MIN_CLEAR - BuntingRule.LINE_DROP - 0.8: fail("lobby: bunting reaches down to %.2f m over the floor" % low)
		print("PARTY_CHECK lobby bunting: lowest point %.2f m over the floor" % low)
	room.free()
