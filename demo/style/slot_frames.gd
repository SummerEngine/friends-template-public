extends RefCounted
## The frames a team's cast fills (docs/slots.md): obstacle signs, posters, the logo wall, the team wall and small hidden boards, at the
## `slots` a level file (docs/level-format.md) or the lobby yard places. Client only, pure look: no collision, no rule reads them.
## A picture never goes on level geometry or a character, only into these frames, so every team's game keeps the house style.
##
##   SlotFrames.build(parent, slots, blocks)   # slots: [{id, p (Vector3, face centre), yaw (radians), size (Vector2)}] in parent space;
##                                             # blocks: the parsed blocks around them (levels/hazards.gd block()), in the same space
##   SlotFrames.card(picture)                  # the picture on a card (the goal sign): plain white, an ink border in the comic look
##   SlotFrames.team_wall_style()              # the team wall's colours, frame and lettering, in one place
##
## The facility look prints each face (one composed picture texture, lit like the room) with printed lettering, in a thin metal frame
## or with a rolled edge; the comic look draws an ink border and comic lettering (Label3D). A board whose face has a block right behind
## it (0.5 m or less) is as deep as the gap, so it sits on the wall; any other board stands on two posts down to the floor below it.
## An empty slot draws nothing, except the logo wall (the team name when there is no logo), arches and banners (the team name) and floor
## decals (the logo, else the team name); a billboard needs a picture or a logo, the crown is always there (style/show_crown.gd).
## The show's slots: arch_start (the START gate across the start platform: style/start_gate.gd; a start with no floor under both ends keeps the pillar arch of style/goal_arch.gd) / arch_finish (two legs and a beam with the logo plate and the team name), banner_1/2 (cloth hung between two
## thin posts), billboard_1/2 (a framed board on two posts), floor_start / floor_finish (a decal on the floor), crown (a pedestal and the
## crown turning over it), hero_prop (the cast's hero_prop.glb or a stepped stand in the brand colours, standing on the level's own
## cylinder blocks: style/hero_prop.gd, docs/hero-prop.md; `p` is the bottom centre, `size` = [footprint, height]; a level with one has no
## crown pedestal). box_faces() puts the cast's obstacle on the faces of obstacle boxes (a box shape with meta "slot"). A decor board with a
## `door` (POSTER RUSH, levels/poster_doors.gd) is a poster door board, drawn by _poster_door(): `solid` = a PROBLEM poster (the obstacle's picture,
## label and colour on a plate in a hazard stripe, a no-entry mark: a wall), `open` / `torn` = the LOGO poster (the logo, the win word
## `TeamCast.round_labels("r17")` else the show's "qualified" word, chevrons and a check mark: the one that tears); both print one cached face.
##   SlotFrames.box_faces(shapes)              # shapes: CollisionShape3D nodes; the ones with an obstacle slot get faces (collision_look calls it)
const TeamCast := preload("res://style/team_cast.gd")
const Ink := preload("res://style/style_ink.gd")
const Party := preload("res://style/party_look.gd")
const Surfaces := preload("res://style/surfaces.gd")
const PRINT_FONT := preload("res://assets/fonts/Archivo.ttf")
const Hazards := preload("res://levels/hazards.gd")
const GoalSign := preload("res://style/goal_sign.gd")
const FinishRails := preload("res://style/finish_rails.gd")
const ShowCrown := preload("res://style/show_crown.gd")
const HeroProp := preload("res://style/hero_prop.gd")
const GoalArch := preload("res://style/goal_arch.gd")
const StartGate := preload("res://style/start_gate.gd")
## The clean display type (Inter ExtraBold, client/friends_ui.gd).
static var DISPLAY: Font = preload("res://client/friends_ui.gd").inter(800)
const PX_PER_METRE := 256.0
const MAX_FACE_PX := 1024.0
const BORDER := 0.05          ## ink border of a face (m)
const DEPTH := 0.12           ## a free-standing board's thickness (m)
const WALL_REACH := 0.5       ## a block this close behind the face carries the board
const POST_REACH := 8.0       ## posts reach a floor at most this far below the board
const POST := 0.09            ## post width (m)
const FONT_SIZE := 96
const SIGN_YELLOW := Color("#ffd23f")
const NIGHT_PRINT := 0.35 ## the night look: how much of its own picture a print gives off (a lit board in a dark world)
const POST_COLOR := Color("#2d3052")
const FRAME_BAR := 0.045      ## facility look: the frame around a poster (m) ...
const FRAME_DEPTH := 0.035
const SIGN_EDGE := 0.025      ## ... and the rolled edge of a sign
const ARCH_COLOR := Color("#2c4bff") ## the arches', banners' and billboards' colour without a brand colour
const ARCH_POST := 0.4        ## an arch leg's width (m) ...
const ARCH_DEPTH := 0.4       ## ... and the beam's and legs' depth
const ARCH_REACH := 14.0      ## legs reach a floor at most this far below the beam
const BANNER_PAD := 0.02      ## a banner picture keeps this share of its content on every side when its empty margins are trimmed
const BANNER_DEPTH := 0.03
const BANNER_POST_GAP := 0.2  ## a banner's posts stand this far outside its ends
const RIM_SHARE := 0.012     ## a floor decal logo's dark rim (_backed): its width, of the picture's longer side
const RIM_STEPS := 12        ## the directions the rim is laid in
const FLOOR_LIFT := 0.06      ## a floor decal lies this far over the floor (m): clear of the floor meshes' own lifts (real_look.gd LIFT_STEP, HAZARD_LIFT: 4 cm at most) and the START / GOAL pads (2 cm)
const PEDESTAL_GAP := 0.12    ## the crown floats this far over its pedestal
const PEDESTAL_CAP := 0.06
const PEDESTAL_REACH := 12.0
const BOX_LIFT := 0.012       ## obstacle box faces stand this far off the box (m)
const BOX_INSET := 0.04       ## ... and stop this far short of its edges (the rounded edge of the box look)
const PICTURE_TINT := 0.5     ## a picture on an obstacle box is multiplied by this share of the obstacle's own colour (0 = the plain picture)
const ARCHES := ["arch_start", "arch_finish"]
const BANNERS := ["banner_1", "banner_2"]
const BILLBOARDS := ["billboard_1", "billboard_2"]
const FLOORS := ["floor_start", "floor_finish"]
const GOAL_WORD_Y := 3.4      ## the GOAL word's centre over the goal floor (m) ...
const GOAL_CARD_Y := 4.15     ## ... and the underside of the logo card over it (the card is GOAL_CARD_SIZE high)
const GOAL_CARD_SIZE := 1.7
const GOAL_ARCH_CLEAR := 0.25 ## the card and the word keep this far under an arch's beam
const GOAL_ARCH_NEAR := 12.0  ## an arch this near the goal floor along the course (and as wide as its beam, plus GOAL_ARCH_SIDE) is the goal's arch
const GOAL_ARCH_SIDE := 2.0
## The faces of an obstacle box: [outward normal, right, up] (right x up = normal): the four sides and the top.
const BOX_FACES: Array = [[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP], [Vector3.LEFT, Vector3.BACK, Vector3.UP], [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD]]
static var _flat_materials := {}
static var _cards := {}
static var _contents := {} ## picture instance id -> the picture cropped to its visible content (a decal is centred by what is seen)
static var _box_materials := {}
static var _prints := {} ## the printed faces already composed (key of _print): a hall of twenty-five posters shares five textures
static var _print_font: FontVariation

## True when the level's `arch_finish` is drawn as the GOAL sign over the finish deck (style/goal_sign.gd) and not as an arch: in every look but the comic one.
static func goal_signed(slots: Array) -> bool:
	if Surfaces.ink(): return false
	for slot: Dictionary in slots:
		if slot.id == "arch_finish": return true
	return false

## Builds a frame for every slot the cast fills; returns how many. `finish` (a race level's, else empty): {title (the sign's subtitle), goal ({p, size, yaw}, the level's
## goal volume), route (the level's route)}: with it the `arch_finish` slot is the GOAL sign over the finish deck and the deck gets its railings (style/finish_rails.gd).
static func build(parent: Node3D, slots: Array, blocks: Array, finish := {}) -> int:
	var built := 0
	var stand := false
	for slot: Dictionary in slots:
		if slot.id == Hazards.HERO_SLOT: stand = true
	var deck := {}
	if not finish.is_empty() and goal_signed(slots): deck = FinishRails.deck(blocks, finish.goal)
	if not deck.is_empty(): deck.ahead = _ahead(finish.route) # the way the course runs into the finish: the GOAL sign stands beyond the deck's far edge on it
	for index in slots.size():
		var slot := _fitted(slots[index])
		var gate := StartGate.plan(slot, blocks) if str(slot.id) == "arch_start" and not Surfaces.ink() else {}
		var frame: Node3D
		if gate.is_empty():
			frame = _frame(slot, finish, deck)
		else: # the START gate (style/start_gate.gd): one gantry across the platform, standing on its own legs
			frame = Node3D.new()
			frame.name = "Slot_arch_start"
			StartGate.build(frame, slot, gate)
		if frame == null: continue
		frame.transform = Transform3D(Basis(Vector3.UP, float(slot.yaw)), slot.p)
		frame.set_meta("slot_index", index) # a poster door's look finds its board by it (style/poster_door_look.gd)
		if gate.is_empty(): _mount(frame, slot, blocks, stand, not deck.is_empty())
		parent.add_child(frame)
		built += 1
	if not deck.is_empty(): FinishRails.build(parent, deck, blocks, finish.route)
	return built

## The flat unit direction of the route's last metres (Vector2 over x, z), ZERO when there is none.
static func _ahead(route: PackedVector3Array) -> Vector2:
	if route.size() < 2: return Vector2.ZERO
	var end := route[route.size() - 1]
	for index in range(route.size() - 2, -1, -1):
		var flat := Vector2(end.x - route[index].x, end.z - route[index].z)
		if flat.length() >= 3.0 or index == 0: return flat.normalized() if flat.length() > 0.01 else Vector2.ZERO
	return Vector2.ZERO

## The slot as it hangs: a banner whose picture is a strip (its content, without the plain margins around it, is longer than the slot) hangs
## from the same top edge as a cloth just as tall as the strip, so the cloth carries no empty bands. Any other slot as listed.
static func _fitted(slot: Dictionary) -> Dictionary:
	var id := str(slot.id)
	if not id in BANNERS: return slot
	var picture := TeamCast.trimmed(TeamCast.slot_picture(id), BANNER_PAD)
	if picture == null: return slot
	var size: Vector2 = slot.size
	var height := size.x * float(picture.get_height()) / picture.get_width()
	if height >= size.y - 0.01: return slot
	var fitted := slot.duplicate()
	fitted.size = Vector2(size.x, height)
	var at: Vector3 = slot.p
	fitted.p = at - Vector3(0.0, (size.y - height) * 0.5, 0.0) # the top edge stays where the level put it
	return fitted

static func _number(id: String, prefix: String) -> int:
	return int(id.trim_prefix(prefix)) if id.begins_with(prefix) and id.trim_prefix(prefix).is_valid_int() else 0

## The board of one slot (face and lettering, in the slot's own frame: face centre at the origin, looking down +Z), or null.
static func _frame(slot: Dictionary, finish := {}, deck := {}) -> Node3D:
	var id := str(slot.id)
	var size: Vector2 = slot.size
	var holder := Node3D.new()
	holder.name = "Slot_" + id
	if slot.has("door"):
		_poster_door(holder, size, slot) # a poster door of POSTER RUSH: a problem poster or the logo poster, whatever the id (below)
	elif id.begins_with("obstacle_"):
		var sign := TeamCast.obstacle(_number(id, "obstacle_"))
		if sign.is_empty(): return _drop(holder)
		_sign(holder, size, sign)
	elif id.begins_with("poster_"):
		var poster: Dictionary = slot.poster if slot.has("poster") else TeamCast.poster(_number(id, "poster_")) # the lobby hands over its own
		if poster.is_empty(): return _drop(holder)
		_poster(holder, size, poster)
	elif id == "team_wall":
		var people := TeamCast.team_wall()
		if people.is_empty(): return _drop(holder)
		_team_wall(holder, size, people)
	elif id == "logo_wall":
		_logo_wall(holder, size)
	elif id.begins_with("egg_"):
		var line := TeamCast.egg(_number(id, "egg_"))
		if line == "": return _drop(holder)
		_egg(holder, size, line)
	elif id == "arch_finish" and not deck.is_empty():
		GoalSign.build(holder, slot, deck, str(finish.title)) # the GOAL sign hangs over the finish deck (its own gantry: _mount adds no legs)
	elif id in ARCHES:
		if Surfaces.ink():
			_arch(holder, size)
		else: # the sign between the columns of the arch (style/goal_arch.gd), on both faces: a runner reads it from either side
			var face := Vector2(GoalArch.inner(size.x), size.y)
			_arch(holder, face)
			var back := Node3D.new()
			back.name = "BackFace"
			back.rotation.y = PI
			back.position.z = -ARCH_DEPTH
			holder.add_child(back)
			_arch(back, face)
	elif id in BANNERS:
		_banner(holder, size, _number(id, "banner_"))
	elif id in BILLBOARDS:
		if not _billboard(holder, size, _number(id, "billboard_")): return _drop(holder)
	elif id in FLOORS:
		_floor(holder, size)
	elif id == "crown":
		_crown(holder, size)
	elif id == Hazards.HERO_SLOT:
		holder.add_child(HeroProp.build(size))
	else:
		return _drop(holder)
	return holder

static func _drop(holder: Node3D) -> Node3D:
	holder.free()
	return null

# ------------------------------------------------------------------ the frames

## Obstacle sign: the picture in the top part, the label lettered under it; without a picture the label fills the face.
static func _sign(holder: Node3D, size: Vector2, sign: Dictionary) -> void:
	if not Surfaces.ink():
		_sign_print(holder, size, sign)
		return
	var accent := TeamCast.brand_accent()
	var color: Color = sign.color if (sign.color as Color).a > 0.0 else (accent if accent.a > 0.0 else SIGN_YELLOW)
	var pad := _pad(size)
	var picture: Texture2D = sign.picture
	var letters := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var shown := Rect2()
	if picture != null:
		shown = Rect2(pad, pad, size.x - pad * 2.0, size.y * 0.58 - pad)
		letters = Rect2(pad, shown.end.y + pad * 0.4, size.x - pad * 2.0, size.y - shown.end.y - pad * 1.2)
	_face(holder, size, color, picture, shown, false)
	var light := color.get_luminance() > 0.5
	_letters(holder, size, letters, str(sign.label), Ink.INK if light else Ink.PAPER, not light)

## Poster: the picture on a paper mat in an ink frame, the caption under it.
static func _poster(holder: Node3D, size: Vector2, poster: Dictionary) -> void:
	if not Surfaces.ink():
		_poster_print(holder, size, poster)
		return
	var pad := _pad(size)
	var caption := str(poster.caption)
	var bottom := size.y * 0.16 if caption != "" else 0.0
	var shown := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0 - bottom)
	_face(holder, size, Ink.PAPER, poster.picture, shown, false)
	if caption != "": _letters(holder, size, Rect2(pad, shown.end.y + pad * 0.4, size.x - pad * 2.0, bottom - pad * 0.4), caption, Ink.INK, false)

## The outer size of the largest poster frame inside `box` (m) that shows `picture` whole, without a caption: the mat (7% of the frame's
## shorter inner side on every side) and the frame bars of _poster_print included.
static func poster_fit(picture: Texture2D, box: Vector2) -> Vector2:
	var aspect := float(picture.get_width()) / maxf(float(picture.get_height()), 1.0)
	var inner := Vector2.ONE # inner size at a shorter side of 1: the picture plus 0.07 mat on every side of the shorter side
	if aspect >= 1.0: inner = Vector2(aspect * 0.86 + 0.14, 1.0)
	else: inner = Vector2(1.0, 0.86 / aspect + 0.14)
	var room := box - Vector2.ONE * FRAME_BAR * 2.0
	return inner * minf(room.x / inner.x, room.y / inner.y) + Vector2.ONE * FRAME_BAR * 2.0

## The logo wall: the logo on paper in a panel of the brand colour, or the team name lettered on it.
static func _logo_wall(holder: Node3D, size: Vector2) -> void:
	if not Surfaces.ink():
		_logo_print(holder, size)
		return
	var accent := TeamCast.brand_accent()
	var color := accent if accent.a > 0.0 else Ink.COBALT
	var pad := _pad(size)
	var inner := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var logo := TeamCast.logo()
	_face(holder, size, color, logo, inner if logo != null else Rect2(), false)
	if logo == null: _letters(holder, size, inner.grow(-pad * 0.5), TeamCast.team_name(), Ink.YELLOW, true)

## A small hidden board: a line in ink on paper, wrapped.
static func _egg(holder: Node3D, size: Vector2, line: String) -> void:
	if not Surfaces.ink():
		_egg_print(holder, size, line)
		return
	var pad := _pad(size)
	_face(holder, size, Ink.PAPER, null, Rect2(), false)
	_letters(holder, size, Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0), line.to_upper(), Ink.INK, false, 4)

static func _pad(size: Vector2) -> float:
	return BORDER + minf(size.x, size.y) * 0.05

# ------------------------------------------------------------------ the poster doors of POSTER RUSH (levels/poster_doors.gd)

## A door slot (`door` in the level file) is one of two boards, told apart at a glance from the far end of the hall: a PROBLEM poster (kind `solid`, a wall) is the
## cast's obstacle (its picture and its word) on a plate in the obstacle's colour inside a yellow-and-ink hazard stripe, with a red no-entry mark on its corner; the
## LOGO poster (kind `open` or `torn`, the one that tears) is a light board in a green edge with the brand's logo (the team name without one) big, the win word under
## it (round r17's `label`, else the show's "qualified" word) and green chevrons pointing up, with a green check mark on its corner. Each face is one composed
## picture (cached: a hall of fifty posters shares a handful of textures), the words are lettering fitted into their rectangle: they never overflow.
const DOOR_PX := 160.0                     ## px per metre of a door board's face
const DOOR_STRIPE := 0.34                  ## m along the edge of one hazard stripe
const DOOR_PAD := 0.08                     ## m inside the edge before the picture or the word
const DOOR_BADGE := 0.3                    ## m radius of the corner mark (less on a narrow board)
const HAZARD_INK := Color("#16181d")
const NO_ENTRY_RED := Color("#e5202f")
const PROBLEM_PLATE := Color("#d8243a")    ## a problem poster whose obstacle the cast gives no colour
const PROBLEM_WORD := "BLOCKED"            ## ... or no word at all
const LOGO_GREEN := Color("#22b35a")
const LOGO_GREEN_DEEP := Color("#0b7a3b")  ## the win word's colour on the light board
const LOGO_PAPER := Color("#fffdf8")

static func _poster_door(holder: Node3D, size: Vector2, slot: Dictionary) -> void:
	var image: Image
	var rect := Rect2()
	var words := Rect2()
	var text := ""
	var ink := HAZARD_INK
	var key := "door|%s|%s|%s" % [str(slot.door) == "solid", size, Party.night()]
	var edge := clampf(size.x * 0.08, 0.14, 0.2)
	var inner := Rect2(edge + 0.03, edge + 0.03, size.x - (edge + 0.03) * 2.0, size.y - (edge + 0.03) * 2.0)
	if str(slot.door) == "solid":
		var sign := TeamCast.obstacle(_number(str(slot.id), "obstacle_"))
		var plate: Color = sign.color if not sign.is_empty() and (sign.color as Color).a > 0.0 else PROBLEM_PLATE
		var picture: Texture2D = sign.get("picture") if not sign.is_empty() else null
		text = str(sign.label) if not sign.is_empty() else PROBLEM_WORD
		ink = _on(plate)
		if picture != null:
			rect = Rect2(inner.position.x + DOOR_PAD, inner.position.y + DOOR_PAD, inner.size.x - DOOR_PAD * 2.0, inner.size.y * 0.5)
			words = Rect2(rect.position.x, rect.end.y + DOOR_PAD * 0.8, rect.size.x, inner.end.y - rect.end.y - DOOR_PAD * 1.8)
		else:
			words = Rect2(inner.position.x + DOOR_PAD, inner.position.y + DOOR_PAD, inner.size.x - DOOR_PAD * 2.0, inner.size.y - DOOR_PAD * 2.0)
		key += "|%s|%d|%s" % [plate.to_html(), picture.get_instance_id() if picture != null else 0, text]
		if not _prints.has(key) or Surfaces.ink(): image = _problem_image(size, edge, inner, plate, picture, rect)
	else:
		var logo := TeamCast.logo()
		var listed := TeamCast.round_labels("r17")
		text = listed[posmod(int(absf((slot.p as Vector3).z)), listed.size())] if not listed.is_empty() else TeamCast.show_word("qualified")
		ink = LOGO_GREEN_DEEP
		rect = Rect2(inner.position.x + DOOR_PAD, inner.position.y + DOOR_PAD, inner.size.x - DOOR_PAD * 2.0, inner.size.y * 0.36)
		words = Rect2(rect.position.x, rect.end.y + DOOR_PAD * 0.6, rect.size.x, inner.size.y * 0.27)
		key += "|%d" % (logo.get_instance_id() if logo != null else 0) # the word and the team name are lettering on top, not part of the picture
		if not _prints.has(key) or Surfaces.ink(): image = _logo_image(size, edge, inner, logo, rect)
	if Surfaces.ink():
		_face_quad(holder, size, image)
	else:
		if image != null: _prints[key] = _lit_material(image, 0.6, 0.0)
		_quad(holder, size, _prints[key])
	_lettering(holder, size, words, text, ink, _door_lines(text))
	if str(slot.door) != "solid" and TeamCast.logo() == null: # no logo: the team name stands in its place
		var name := TeamCast.team_name()
		_lettering(holder, size, rect, name, HAZARD_INK, _door_lines(name))

## Lines a door board's word may take: two for words that split about evenly (a line never breaks inside a word), else one.
static func _door_lines(text: String) -> int:
	var longest := 0
	for word in text.split(" ", false): longest = maxi(longest, word.length())
	return 2 if text.contains(" ") and float(longest) <= 0.65 * float(text.length()) else 1

## The face of a problem poster: ink, a hazard-striped edge, the plate, the picture on white, a no-entry mark.
static func _problem_image(size: Vector2, edge: float, inner: Rect2, plate: Color, picture: Texture2D, rect: Rect2) -> Image:
	var image := _door_canvas(size, HAZARD_INK)
	var px := DOOR_PX
	var wide := image.get_width()
	var high := image.get_height()
	var band := roundi(edge * px)
	for stripe: Rect2i in [Rect2i(0, 0, wide, band), Rect2i(0, high - band, wide, band), Rect2i(0, band, band, high - band * 2), Rect2i(wide - band, band, band, high - band * 2)]:
		_stripes(image, stripe, SIGN_YELLOW, HAZARD_INK, DOOR_STRIPE * px)
	image.fill_rect(_px_rect(inner, px), plate)
	if picture != null and rect.has_area():
		var area := _px_rect(rect, px)
		image.fill_rect(area.grow(2), HAZARD_INK)
		image.fill_rect(area, Color.WHITE)
		_fit_into(image, picture, area, false)
	var radius := minf(DOOR_BADGE, size.x * 0.15) * px
	var centre := Vector2(inner.end.x, inner.position.y) * px + Vector2(-radius * 0.75, radius * 0.75)
	_disc(image, centre, radius, HAZARD_INK)
	_disc(image, centre, radius - 0.03 * px, Color.WHITE)
	_disc(image, centre, radius - 0.07 * px, NO_ENTRY_RED)
	_line(image, centre - Vector2(radius * 0.55, 0.0), centre + Vector2(radius * 0.55, 0.0), radius * 0.3, Color.WHITE)
	return image

## The face of a logo poster: light paper, a green edge, the logo on its plate (nothing there without a logo: the team name is lettered on the paper), the word
## zone, three green chevrons pointing up, a green check mark.
static func _logo_image(size: Vector2, edge: float, inner: Rect2, logo: Texture2D, rect: Rect2) -> Image:
	var image := _door_canvas(size, HAZARD_INK)
	var px := DOOR_PX
	image.fill_rect(Rect2i(roundi(0.03 * px), roundi(0.03 * px), image.get_width() - roundi(0.06 * px), image.get_height() - roundi(0.06 * px)), LOGO_GREEN)
	image.fill_rect(_px_rect(inner.grow(0.02), px), HAZARD_INK)
	image.fill_rect(_px_rect(inner, px), LOGO_PAPER)
	if logo != null and rect.has_area():
		var area := _px_rect(rect, px)
		image.fill_rect(area.grow(2), HAZARD_INK)
		image.fill_rect(area, TeamCast.logo_backing())
		_fit_into(image, logo, area, false)
	var chevrons := Rect2(inner.position.x + DOOR_PAD, inner.position.y + inner.size.y * 0.7, inner.size.x - DOOR_PAD * 2.0, inner.size.y * 0.27)
	var half := minf(chevrons.size.x * 0.34, 0.55)
	var rise := minf(chevrons.size.y * 0.2, half * 0.7)
	for step in 3:
		var top := chevrons.position.y + chevrons.size.y * (0.12 + 0.26 * step)
		var apex := Vector2(chevrons.get_center().x, top) * px
		var shoulder := Vector2(half, rise) * px
		_line(image, apex + Vector2(-shoulder.x, shoulder.y), apex, 0.085 * px, LOGO_GREEN)
		_line(image, apex, apex + shoulder, 0.085 * px, LOGO_GREEN)
	var radius := minf(DOOR_BADGE, size.x * 0.15) * px
	var centre := Vector2(inner.end.x, inner.position.y) * px + Vector2(-radius * 0.75, radius * 0.75)
	_disc(image, centre, radius, HAZARD_INK)
	_disc(image, centre, radius - 0.03 * px, Color.WHITE)
	_disc(image, centre, radius - 0.07 * px, LOGO_GREEN)
	var tick := radius * 0.5
	_line(image, centre + Vector2(-tick * 0.85, 0.05 * tick), centre + Vector2(-tick * 0.25, tick * 0.7), radius * 0.2, Color.WHITE)
	_line(image, centre + Vector2(-tick * 0.25, tick * 0.7), centre + Vector2(tick * 0.95, -tick * 0.6), radius * 0.2, Color.WHITE)
	return image

static func _door_canvas(size: Vector2, fill: Color) -> Image:
	var image := Image.create_empty(maxi(8, roundi(size.x * DOOR_PX)), maxi(8, roundi(size.y * DOOR_PX)), false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return image

static func _px_rect(rect: Rect2, px: float) -> Rect2i:
	return Rect2i(roundi(rect.position.x * px), roundi(rect.position.y * px), roundi(rect.size.x * px), roundi(rect.size.y * px))

## Diagonal stripes of `a` and `b`, `period` px along each, inside `area` of `image`.
static func _stripes(image: Image, area: Rect2i, a: Color, b: Color, period: float) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			image.set_pixel(x, y, a if int(floorf(float(x + y) / period)) % 2 == 0 else b)

## A disc of `radius` px, its edge blended over a pixel.
static func _disc(image: Image, centre: Vector2, radius: float, color: Color) -> void:
	for y in range(maxi(0, floori(centre.y - radius) - 1), mini(image.get_height(), ceili(centre.y + radius) + 2)):
		for x in range(maxi(0, floori(centre.x - radius) - 1), mini(image.get_width(), ceili(centre.x + radius) + 2)):
			var cover := clampf(radius - Vector2(x + 0.5, y + 0.5).distance_to(centre) + 0.5, 0.0, 1.0)
			if cover > 0.0: image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, cover))

## A line of `width` px from `a` to `b` with round ends, its edge blended over a pixel.
static func _line(image: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var half := width * 0.5
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half + 1.0)
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half + 1.0)
	for y in range(maxi(0, floori(low.y)), mini(image.get_height(), ceili(high.y) + 1)):
		for x in range(maxi(0, floori(low.x)), mini(image.get_width(), ceili(high.x) + 1)):
			var at := Vector2(x + 0.5, y + 0.5)
			var cover := clampf(half - at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)) + 0.5, 0.0, 1.0)
			if cover > 0.0: image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, cover))

# ------------------------------------------------------------------ the show's frames: arches, banners, billboards, floor decals, the crown

static func _accent(fallback: Color) -> Color:
	var accent := TeamCast.brand_accent()
	return accent if accent.a > 0.0 else fallback

## The fill of the show's own boards (arch beams, banners and billboards without a picture, the gate): the brand accent, and in the night look a plate of dark
## metal (white lettering on it, the accent only as trim), like the brand's own screens.
static func _board_fill(fallback: Color) -> Color:
	return Color(str(Surfaces.signage().mat)) if Party.night() else _accent(fallback)

## A composed face for any look: the printed face of the facility look, the inked one of the comic look.
static func _plate(holder: Node3D, size: Vector2, fill: Color, picture: Texture2D, shown: Rect2, cover: bool, under: Color) -> void:
	if Surfaces.ink(): _face(holder, size, fill, picture, shown, cover)
	else: _print(holder, size, fill, picture, shown, cover, under, 0.6)

## Lettering for any look (Archivo printed in the facility look, the comic face in the comic look).
static func _lettering(holder: Node3D, size: Vector2, rect: Rect2, text: String, fill: Color, lines := 1) -> void:
	if Surfaces.ink(): _letters(holder, size, rect, text, fill, fill.get_luminance() > 0.5, lines)
	else: _print_letters(holder, size, rect, text, fill, lines)

## Ink for lettering on `color`: dark on light, white on dark.
static func _on(color: Color) -> Color:
	return Color("#16181d") if color.get_luminance() > 0.55 else Color.WHITE

## The arch's beam face: the brand accent with the logo on a white plate at the left and the team name beside it (just the name without a logo).
static func _arch(holder: Node3D, size: Vector2) -> void:
	var color := _board_fill(ARCH_COLOR)
	var pad := minf(size.x, size.y) * 0.08
	var logo := TeamCast.logo()
	var plate := Rect2()
	var letters := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	if logo != null:
		var side := size.y - pad * 2.0
		plate = Rect2(pad, pad, side, side)
		letters = Rect2(plate.end.x + pad, pad, size.x - plate.end.x - pad * 2.0, side)
	_plate(holder, size, color, logo, plate, false, TeamCast.logo_backing()) # the logo plate: white behind a dark or colourful logo
	_lettering(holder, size, letters, TeamCast.team_name(), _on(color))

## A banner's cloth: the picture covering it, else the team name on the brand accent.
static func _banner(holder: Node3D, size: Vector2, index: int) -> void:
	var picture := TeamCast.trimmed(TeamCast.slot_picture("banner_%d" % index), BANNER_PAD)
	var color := _board_fill(ARCH_COLOR)
	var edge := BORDER * 1.5 if Surfaces.ink() else 0.0
	_plate(holder, size, color, picture, Rect2(edge, edge, size.x - edge * 2.0, size.y - edge * 2.0), true, color)
	if picture != null: return
	var pad := minf(size.x, size.y) * 0.12
	_lettering(holder, size, Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0), TeamCast.team_name(), _on(color))

## A billboard's face: the picture covering the board, else the logo contained on the brand accent; false when it has neither (no board).
static func _billboard(holder: Node3D, size: Vector2, index: int) -> bool:
	var picture := TeamCast.slot_picture("billboard_%d" % index)
	var art := picture if picture != null else TeamCast.logo()
	if art == null: return false
	var color := _board_fill(ARCH_COLOR)
	var pad := 0.0 if picture != null else minf(size.x, size.y) * 0.1
	if Surfaces.ink():
		var edge := _pad(size) + pad
		_face(holder, size, color, art, Rect2(edge, edge, size.x - edge * 2.0, size.y - edge * 2.0), picture != null)
	else:
		var inner := size - Vector2.ONE * FRAME_BAR * 2.0
		_print(holder, inner, color, art, Rect2(pad, pad, inner.x - pad * 2.0, inner.y - pad * 2.0), picture != null, color, 0.55)
		_frame_bars(holder, size, FRAME_BAR, FRAME_DEPTH)
	return true

## A decal lying on the floor (the slot's face turned to look up, its top towards -Z, the way the course runs): the logo with its
## transparency, else the team name lettered.
static func _floor(holder: Node3D, size: Vector2) -> void:
	var decal := Node3D.new()
	decal.name = "Decal"
	decal.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	decal.position = Vector3(0.0, FLOOR_LIFT, 0.0)
	holder.add_child(decal)
	var logo := content(TeamCast.logo()) # cut to what is seen: a logo with uneven empty margins would sit off the centre of its decal (and of the pad under it)
	if logo == null:
		var pad := minf(size.x, size.y) * 0.05
		# the party look's floor is the brand colour itself: the name goes in the look's dark ink so it reads on it
		var fill := Color(str(Surfaces.signage().text)) if Party.on() else _accent(ARCH_COLOR)
		_lettering(decal, size, Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0), TeamCast.team_name(), fill)
		return
	var scale := minf(PX_PER_METRE, MAX_FACE_PX / maxf(size.x, size.y))
	var image := Image.create_empty(maxi(8, roundi(size.x * scale)), maxi(8, roundi(size.y * scale)), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_fit_into(image, logo, Rect2i(Vector2i.ZERO, image.get_size()), false)
	image = _backed(image)
	image.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = size
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 2 # over any other see-through thing lying on the floor
	material.roughness = 0.8
	face.material_override = material
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal.add_child(face)

## `art` (a logo with transparency, lying on a floor decal) over a dark rim of itself: a logo whose dark edge was keyed out with its black background (cast_prep) has bites and
## see-through specks along that edge, and the colour of the pad under the decal showed through them. The rim is the silhouette in near black, shifted by a quarter, a half and the whole rim width
## in every direction (so a bay or a gap narrower than the rim fills with the dark and the whole edge is solid), then the art on top; the art's own pixels never change.
static func _backed(art: Image) -> Image:
	var shape := art.duplicate() as Image
	shape.adjust_bcs(0.0, 1.0, 1.0) # black, the alpha stays
	var width := art.get_width()
	var height := art.get_height()
	var reach := maxf(3.0, float(maxi(width, height)) * RIM_SHARE)
	var backing := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	backing.fill(Color(0, 0, 0, 0))
	for ring in [0.25, 0.5, 1.0]:
		for step in RIM_STEPS:
			var around := TAU * float(step) / float(RIM_STEPS)
			backing.blend_rect(shape, Rect2i(0, 0, width, height), Vector2i(roundi(cos(around) * reach * ring), roundi(sin(around) * reach * ring)))
	backing.blend_rect(art, Rect2i(0, 0, width, height), Vector2i.ZERO)
	return backing

## The crown over its pedestal: the crown (built-in or the cast's crown.glb) as tall as the slot, turning slowly with its base at the slot's
## bottom edge. The pedestal is added by _mount.
static func _crown(holder: Node3D, size: Vector2) -> void:
	var floating := ShowCrown.floating(size.y if size.y > 0.05 else 0.5)
	floating.position = Vector3(0.0, -size.y * 0.5, 0.0)
	holder.add_child(floating)

## The paint of big structure (an arch): the colour in the look's own material.
static func _body_paint(color: Color) -> StandardMaterial3D:
	if Surfaces.ink(): return _flat(color)
	var key := "body_" + color.to_html()
	if not _flat_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.5
		material.metallic = 0.1
		_flat_materials[key] = material
	return _flat_materials[key]

## A thin pole standing `height` up from `base` (frame space), in the look's post material.
static func _pole(holder: Node3D, base: Vector3, height: float) -> void:
	var post := MeshInstance3D.new()
	post.name = "Post"
	if Surfaces.ink():
		var rod := BoxMesh.new()
		rod.size = Vector3(POST, height, POST)
		post.mesh = rod
		post.material_override = _flat(POST_COLOR)
	else:
		var tube := CylinderMesh.new()
		tube.top_radius = POST * 0.45
		tube.bottom_radius = POST * 0.45
		tube.height = height
		tube.radial_segments = 12
		tube.rings = 1
		post.mesh = tube
		post.material_override = _paint("post")
	post.position = base + Vector3(0.0, height * 0.5, 0.0)
	holder.add_child(post)

## An arch's beam (behind the face) and its two legs down to the floor below the ends of the beam.
static func _legs(holder: Node3D, slot: Dictionary, blocks: Array) -> void:
	var size: Vector2 = slot.size
	var basis := Basis(Vector3.UP, float(slot.yaw))
	if not Surfaces.ink(): # the facility, party and night looks: rounded columns on plinths, a framed sign, lamps (style/goal_arch.gd)
		var drops: Array = []
		for side: float in [-1.0, 1.0]:
			var drop := _nearest(blocks, (slot.p as Vector3) + basis.x * side * (size.x * 0.5 - GoalArch.PLINTH) - Vector3(0.0, size.y * 0.5, 0.0), Vector3.DOWN)
			drops.append(drop if drop <= ARCH_REACH and drop >= 0.05 else -1.0)
		GoalArch.build(holder, size, drops, _accent(ARCH_COLOR))
		return
	var paint := _body_paint(_accent(ARCH_COLOR))
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, ARCH_DEPTH)
	beam.mesh = box
	beam.material_override = paint
	beam.position = Vector3(0.0, 0.0, -ARCH_DEPTH * 0.5)
	holder.add_child(beam)
	for side: float in [-1.0, 1.0]:
		var x := side * (size.x * 0.5 - ARCH_POST * 0.5)
		var drop := _nearest(blocks, (slot.p as Vector3) + basis.x * x - Vector3(0.0, size.y * 0.5, 0.0), Vector3.DOWN)
		if drop > ARCH_REACH or drop < 0.05: continue
		var leg := MeshInstance3D.new()
		leg.name = "Leg"
		var column := BoxMesh.new()
		column.size = Vector3(ARCH_POST, drop, ARCH_DEPTH)
		leg.mesh = column
		leg.material_override = paint
		leg.position = Vector3(x, -size.y * 0.5 - drop * 0.5, -ARCH_DEPTH * 0.5)
		holder.add_child(leg)

## A banner's cloth backing, the rod it hangs from and the two thin posts at its ends (down to the floor below, none without one).
static func _hang(holder: Node3D, slot: Dictionary, blocks: Array) -> void:
	var size: Vector2 = slot.size
	var basis := Basis(Vector3.UP, float(slot.yaw))
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	var sheet := BoxMesh.new()
	sheet.size = Vector3(size.x, size.y, BANNER_DEPTH)
	cloth.mesh = sheet
	cloth.material_override = _flat(Ink.INK) if Surfaces.ink() else _paint("board")
	cloth.position = Vector3(0.0, 0.0, -BANNER_DEPTH * 0.5)
	holder.add_child(cloth)
	var reach := size.x * 0.5 + BANNER_POST_GAP
	var rod := MeshInstance3D.new()
	rod.name = "Rod"
	var bar := BoxMesh.new()
	bar.size = Vector3(reach * 2.0 + POST, POST * 0.7, POST * 0.7)
	rod.mesh = bar
	rod.material_override = _flat(POST_COLOR) if Surfaces.ink() else _paint("post")
	rod.position = Vector3(0.0, size.y * 0.5 + POST * 0.35, -BANNER_DEPTH * 0.5)
	holder.add_child(rod)
	for side: float in [-1.0, 1.0]:
		var drop := _nearest(blocks, (slot.p as Vector3) + basis.x * reach * side - Vector3(0.0, size.y * 0.5, 0.0), Vector3.DOWN)
		if drop > POST_REACH or drop < 0.05: continue
		_pole(holder, Vector3(reach * side, -size.y * 0.5 - drop, -BANNER_DEPTH * 0.5), drop + size.y + POST * 0.7)

## The crown's pedestal: a column from the floor below up to just under the crown, with a cap in the brand accent (none without a floor).
static func _pedestal(holder: Node3D, slot: Dictionary, blocks: Array) -> void:
	var size: Vector2 = slot.size
	var top := -size.y * 0.5 - PEDESTAL_GAP
	var drop := _nearest(blocks, (slot.p as Vector3) + Vector3(0.0, top, 0.0), Vector3.DOWN)
	if drop > PEDESTAL_REACH or drop < 0.05: return
	var radius := maxf(size.x * 0.3, 0.25)
	var column := MeshInstance3D.new()
	column.name = "Pedestal"
	var tube := CylinderMesh.new()
	tube.top_radius = radius * 0.8
	tube.bottom_radius = radius
	tube.height = drop
	tube.radial_segments = 20
	tube.rings = 1
	column.mesh = tube
	column.material_override = _flat(POST_COLOR) if Surfaces.ink() else _paint("post")
	column.position = Vector3(0.0, top - drop * 0.5, 0.0)
	holder.add_child(column)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 1.1
	disc.bottom_radius = radius * 1.1
	disc.height = PEDESTAL_CAP
	disc.radial_segments = 20
	disc.rings = 1
	cap.mesh = disc
	cap.material_override = _body_paint(_accent(SIGN_YELLOW))
	cap.position = Vector3(0.0, top - PEDESTAL_CAP * 0.5, 0.0)
	holder.add_child(cap)

# ------------------------------------------------------------------ parts

## The team wall: everyone's own photo in a rounded frame with their name under it, in a grid that makes the photos as big as the
## board allows; a person without a photo shows their cast colour. The look is in team_wall_style().
static func _team_wall(holder: Node3D, size: Vector2, people: Array) -> void:
	var style := team_wall_style()
	var pad := _pad(size)
	var inner := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var share: float = style.name_share
	var columns := 1
	var tile := 0.0
	for count in range(1, people.size() + 1):
		var rows := ceili(float(people.size()) / count)
		var side := minf(inner.size.x / count, inner.size.y / (rows * (1.0 + share)))
		if side > tile:
			tile = side
			columns = count
	var rows := ceili(float(people.size()) / columns)
	var gap := tile * 0.12
	var top := inner.position.y + (inner.size.y - rows * tile * (1.0 + share)) * 0.5
	var scale := minf(PX_PER_METRE, MAX_FACE_PX / maxf(size.x, size.y))
	var printed := not Surfaces.ink()
	var image := _solid(Vector2i(maxi(8, roundi(size.x * scale)), maxi(8, roundi(size.y * scale))), style.board) if printed else _board_image(size, scale, style.board)
	for index in people.size():
		var person: Dictionary = people[index]
		var row := index / columns
		var in_row := mini(columns, people.size() - row * columns)
		var left := inner.position.x + (inner.size.x - in_row * tile) * 0.5 + (index % columns) * tile
		var photo := Rect2(left + gap * 0.5, top + row * tile * (1.0 + share) + gap * 0.5, tile - gap, tile - gap)
		_framed_photo(image, Rect2i((photo.position * scale).round(), (photo.size * scale).round()), person.picture, person.color, style)
		var name_rect := Rect2(left, photo.end.y + gap * 0.15, tile, tile * share - gap * 0.15)
		if printed: _print_letters(holder, size, name_rect, str(person.name), style.name_fill)
		else: _letters(holder, size, name_rect, str(person.name), style.name_fill, style.name_edge, 1, style.font)
	if printed:
		_lit_quad(holder, size, image, 0.5)
		_frame_bars(holder, size, FRAME_BAR, FRAME_DEPTH)
	else:
		_face_quad(holder, size, image)

## Everything the team wall looks like, in one place: board and frame colours, the photo frame's corner and ring (shares of a photo's
## side), the name lettering (font, fill, ink edge) and the height of the name row (share of a photo's side). The facility look prints
## it on a paper board in a thin metal frame (names in the print font); the comic look keeps paper, ink and comic letters.
static func team_wall_style() -> Dictionary:
	if not Surfaces.ink():
		var signage := Surfaces.signage()
		return {"board": Color(str(signage.mat)), "frame": Color(str(signage.frame)), "corner": 0.12, "ring": 0.03, "font": DISPLAY,
			"name_fill": Color(str(signage.text)), "name_edge": false, "name_share": 0.24}
	return {"board": Ink.PAPER, "frame": Ink.INK, "corner": 0.22, "ring": 0.045, "font": DISPLAY, "name_fill": Ink.INK, "name_edge": false,
		"name_share": 0.26}

## A photo (or a colour) in a rounded frame with an ink ring, drawn into `area` (px) of `canvas` (RGBA8). The photo covers the frame.
static func _framed_photo(canvas: Image, area: Rect2i, picture: Texture2D, color: Color, style: Dictionary) -> void:
	if area.size.x < 4 or area.size.y < 4: return
	var ring := maxi(2, roundi(area.size.x * float(style.ring)))
	var corner: float = style.corner
	canvas.blit_rect_mask(_solid(area.size, style.frame), _rounded_mask(area.size, corner), Rect2i(Vector2i.ZERO, area.size), area.position)
	var inside := area.grow(-ring)
	var content: Image = null
	var art := picture.get_image() if picture != null else null
	if art != null and not art.is_empty():
		content = art.duplicate() as Image
		if content.is_compressed(): content.decompress()
		content.convert(Image.FORMAT_RGBA8)
		var side := mini(content.get_width(), content.get_height())
		content = content.get_region(Rect2i((content.get_width() - side) / 2, (content.get_height() - side) / 2, side, side))
		content.resize(inside.size.x, inside.size.y, Image.INTERPOLATE_LANCZOS)
	else:
		content = _solid(inside.size, color)
	canvas.blit_rect_mask(content, _rounded_mask(inside.size, corner), Rect2i(Vector2i.ZERO, inside.size), inside.position)

static func _solid(size: Vector2i, color: Color) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image

## Opaque inside a rounded square of `size` px (corner radius `corner` of the shorter side), clear outside.
static func _rounded_mask(size: Vector2i, corner: float) -> Image:
	var mask := _solid(size, Color.WHITE)
	var radius := maxi(1, roundi(mini(size.x, size.y) * corner))
	for corner_index in 4:
		var origin := Vector2i(0 if corner_index % 2 == 0 else size.x - radius, 0 if corner_index < 2 else size.y - radius)
		var centre := Vector2(radius if corner_index % 2 == 0 else 0, radius if corner_index < 2 else 0)
		for y in radius:
			for x in radius:
				if Vector2(x + 0.5, y + 0.5).distance_to(centre) > radius: mask.set_pixel(origin.x + x, origin.y + y, Color(0, 0, 0, 0))
	return mask

## The face: one quad at z = +0.01 with a composed texture (ink border, `fill`, the picture fitted into `shown`, metres from the
## top left corner, on paper in an ink frame). The board behind it is added by _mount.
static func _face(holder: Node3D, size: Vector2, fill: Color, picture: Texture2D, shown: Rect2, cover: bool) -> void:
	var scale := minf(PX_PER_METRE, MAX_FACE_PX / maxf(size.x, size.y))
	var image := _board_image(size, scale, fill)
	var border := maxi(2, roundi(BORDER * scale))
	if picture != null and shown.has_area():
		var area := Rect2i(roundi(shown.position.x * scale), roundi(shown.position.y * scale), roundi(shown.size.x * scale), roundi(shown.size.y * scale))
		image.fill_rect(area.grow(maxi(1, border / 2)), Ink.INK)
		image.fill_rect(area, Ink.PAPER)
		_fit_into(image, picture, area, cover)
	_face_quad(holder, size, image)

## A face image of `size` (m) at `scale` px per metre: `fill` inside an ink border.
static func _board_image(size: Vector2, scale: float, fill: Color) -> Image:
	var width := maxi(8, roundi(size.x * scale))
	var height := maxi(8, roundi(size.y * scale))
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Ink.INK)
	var border := maxi(2, roundi(BORDER * scale))
	image.fill_rect(Rect2i(border, border, width - border * 2, height - border * 2), fill)
	return image

## The face quad at z = +0.01 showing `image`.
static func _face_quad(holder: Node3D, size: Vector2, image: Image) -> void:
	image.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = size
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = quad
	face.material_override = _textured(ImageTexture.create_from_image(image))
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0.0, 0.0, 0.01)
	holder.add_child(face)

## `picture` scaled into `area` of `canvas` (RGBA8): contained (whole picture, centred) or covering (cropped centre), alpha blended.
static func _fit_into(canvas: Image, picture: Texture2D, area: Rect2i, cover: bool) -> void:
	var art := picture.get_image()
	if art == null or art.is_empty(): return
	art = art.duplicate() as Image
	if art.is_compressed(): art.decompress()
	art.convert(Image.FORMAT_RGBA8)
	var sx := float(area.size.x) / art.get_width()
	var sy := float(area.size.y) / art.get_height()
	var scale := maxf(sx, sy) if cover else minf(sx, sy)
	art.resize(maxi(1, roundi(art.get_width() * scale)), maxi(1, roundi(art.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var crop := Rect2i(maxi(0, (art.get_width() - area.size.x) / 2), maxi(0, (art.get_height() - area.size.y) / 2),
		mini(art.get_width(), area.size.x), mini(art.get_height(), area.size.y))
	canvas.blend_rect(art, crop, area.position + (area.size - crop.size) / 2)

## Comic lettering fitted into `rect` (metres from the face's top left corner): `fill` letters, an ink edge when `edge`. Up to
## `lines` lines (wrapped at words) when that makes the letters bigger. `font`: the comic face unless a look asks for another.
static func _letters(holder: Node3D, size: Vector2, rect: Rect2, text: String, fill: Color, edge: bool, lines := 1, font: Font = DISPLAY) -> void:
	if text == "" or not rect.has_area(): return
	var one := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var line_height := font.get_height(FONT_SIZE)
	var best := 0.0
	var best_width := one.x
	for count in range(1, lines + 1):
		var width := one.x if count == 1 else one.x / count * 1.2
		var pixel := minf(rect.size.x / maxf(width, 1.0), rect.size.y / (line_height * count))
		if pixel > best * 1.05:
			best = pixel
			best_width = width
	var label := Label3D.new()
	label.name = "Letters"
	label.text = text
	label.font = font
	label.font_size = FONT_SIZE
	label.pixel_size = best
	label.modulate = fill
	label.outline_size = 18 if edge else 0
	label.outline_modulate = Ink.INK
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if lines > 1:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = rect.size.x / best
	label.position = Vector3(rect.get_center().x - size.x * 0.5, size.y * 0.5 - rect.get_center().y, 0.02)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(label)

## The board behind the face (facility look: in the board colour, on round posts): as deep as the gap to a block right behind it
## (it sits on that wall), else DEPTH deep on two posts down to the floor below (no post where there is no floor).
static func _mount(holder: Node3D, slot: Dictionary, blocks: Array, stand := false, signed := false) -> void:
	var id := str(slot.id)
	if id in BANNERS:
		_hang(holder, slot, blocks)
		return
	if id == "arch_finish" and signed: return # the GOAL sign brings its own gantry
	if id in ARCHES:
		_legs(holder, slot, blocks)
		return
	if id == "crown":
		if not stand: _pedestal(holder, slot, blocks)
		return
	if id == Hazards.HERO_SLOT: return # stands on its own blocks (the level's cylinders, style/hero_prop.gd)
	if id in FLOORS: return
	var size: Vector2 = slot.size
	var centre: Vector3 = slot.p
	var basis := Basis(Vector3.UP, float(slot.yaw))
	var behind := _nearest(blocks, centre + basis.z * 0.01, -basis.z)
	var on_wall := behind <= WALL_REACH
	var depth := maxf(behind, 0.04) if on_wall else DEPTH
	var board := MeshInstance3D.new()
	board.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, depth)
	board.mesh = box
	board.material_override = _flat(Ink.INK) if Surfaces.ink() else _paint("board")
	board.position = Vector3(0.0, 0.0, -depth * 0.5)
	holder.add_child(board)
	if on_wall: return
	for side: float in [-0.32, 0.32]:
		var foot := centre + basis.x * size.x * side - Vector3(0.0, size.y * 0.5, 0.0)
		var drop := _nearest(blocks, foot, Vector3.DOWN)
		if drop > POST_REACH or drop < 0.05: continue
		var post := MeshInstance3D.new()
		post.name = "Post"
		if Surfaces.ink():
			var rod := BoxMesh.new()
			rod.size = Vector3(POST, drop, POST)
			post.mesh = rod
			post.material_override = _flat(POST_COLOR)
		else:
			var tube := CylinderMesh.new()
			tube.top_radius = POST * 0.45
			tube.bottom_radius = POST * 0.45
			tube.height = drop
			tube.radial_segments = 12
			tube.rings = 1
			post.mesh = tube
			post.material_override = _paint("post")
		post.position = Vector3(size.x * side, -size.y * 0.5 - drop * 0.5, -depth - POST * 0.5)
		holder.add_child(post)

## Distance from `from` along `direction` to the first block, INF for none.
static func _nearest(blocks: Array, from: Vector3, direction: Vector3) -> float:
	var best := INF
	for block: Dictionary in blocks:
		best = minf(best, Hazards.ray_hit(block, from, direction))
	return best

# ------------------------------------------------------------------ materials and cards

static func _flat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _flat_materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_flat_materials[key] = material
	return _flat_materials[key]

static func _textured(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material

## `picture` contained on a square paper card with an ink border (512 px; a plain white card in the realistic looks), made once per
## picture; null for no picture.
static func card(picture: Texture2D) -> Texture2D:
	if picture == null: return null
	var key := "%d%s" % [picture.get_instance_id(), Surfaces.ink()]
	if not _cards.has(key):
		var image := Image.create_empty(512, 512, false, Image.FORMAT_RGBA8)
		image.fill(Ink.INK if Surfaces.ink() else Color.WHITE)
		image.fill_rect(Rect2i(18, 18, 476, 476), Ink.PAPER if Surfaces.ink() else Color.WHITE)
		_fit_into(image, picture, Rect2i(44, 44, 424, 424), false)
		image.generate_mipmaps()
		_cards[key] = ImageTexture.create_from_image(image)
	return _cards[key]

## How high (m) over the goal floor the underside of the arch that frames the goal is: the lowest beam within GOAL_ARCH_NEAR of `floor_point` along the course
## and the width of its beam (+ GOAL_ARCH_SIDE) across it, INF when there is none. `slots` and `floor_point` level-local (levels/level_data.gd slots()).
static func goal_arch_under(slots: Array, floor_point: Vector3) -> float:
	var under := INF
	for slot: Dictionary in slots:
		if not slot.id in ARCHES: continue
		var local: Vector3 = Basis(Vector3.UP, float(slot.yaw)).inverse() * (floor_point - (slot.p as Vector3))
		var face: Vector2 = slot.size
		if absf(local.z) <= GOAL_ARCH_NEAR and absf(local.x) <= face.x * 0.5 + GOAL_ARCH_SIDE:
			under = minf(under, (slot.p as Vector3).y - face.y * 0.5 - floor_point.y)
	return under

## Where the GOAL word and its logo card hang over the goal floor: {"word": y of the word's centre, "card": y of the card's centre, -1 for no card}.
## `word_half` half the word's height (m, the look's lettering), `arch_under` goal_arch_under(). With an arch over the goal neither may reach its beam
## (the arch wears the logo, its sign letters run along the beam): the card is dropped when it would only repeat the logo the arch already wears,
## else it hangs under the beam with the word below it. Without an arch the word and the card stand where they always did.
static func goal_marks(word_half: float, arch_under: float) -> Dictionary:
	var word := GOAL_WORD_Y
	var card := GOAL_CARD_Y + GOAL_CARD_SIZE * 0.5 if TeamCast.goal_sign() != null else -1.0
	if arch_under < INF:
		var ceiling := arch_under - GOAL_ARCH_CLEAR
		if card >= 0.0 and TeamCast.goal_sign() == TeamCast.logo(): card = -1.0
		if card >= 0.0:
			card = minf(card, ceiling - GOAL_CARD_SIZE * 0.5)
			word = minf(word, card - GOAL_CARD_SIZE * 0.5 - 0.1 - word_half)
		else:
			word = minf(word, ceiling - word_half)
	return {"word": word, "card": card}

## `picture` cut to the box of its visible pixels (alpha above 24/255, sampled on a grid of at most 512 x 512), so that a logo whose empty margins are
## uneven lies centred on what is seen; the picture itself when nothing is visible or it has no empty margin. Cached.
static func content(picture: Texture2D) -> Texture2D:
	if picture == null: return null
	var key := picture.get_instance_id()
	if not _contents.has(key):
		var result := picture
		var art := picture.get_image()
		if art != null and not art.is_empty():
			art = art.duplicate() as Image
			if art.is_compressed(): art.decompress()
			art.convert(Image.FORMAT_RGBA8)
			var step := maxi(1, maxi(art.get_width(), art.get_height()) / 512)
			var x0 := art.get_width()
			var y0 := art.get_height()
			var x1 := -1
			var y1 := -1
			for y in range(0, art.get_height(), step):
				for x in range(0, art.get_width(), step):
					if art.get_pixel(x, y).a > 24.0 / 255.0:
						x0 = mini(x0, x)
						x1 = maxi(x1, x)
						y0 = mini(y0, y)
						y1 = maxi(y1, y)
			if x1 >= x0 and y1 >= y0:
				var box := Rect2i(x0, y0, mini(x1 + step, art.get_width()) - x0, mini(y1 + step, art.get_height()) - y0)
				if box.size != art.get_size():
					var cut := art.get_region(box)
					cut.generate_mipmaps()
					result = ImageTexture.create_from_image(cut)
		_contents[key] = result
	return _contents[key]

# ------------------------------------------------------------------ the facility look: real prints in real frames

## A printed sign: the picture on white in the top part, the label printed under it on the sign colour, a thin rolled edge.
static func _sign_print(holder: Node3D, size: Vector2, sign: Dictionary) -> void:
	var accent := TeamCast.brand_accent()
	var color: Color = sign.color if (sign.color as Color).a > 0.0 else (accent if accent.a > 0.0 else SIGN_YELLOW)
	var inner := size - Vector2.ONE * SIGN_EDGE * 2.0
	var pad := minf(inner.x, inner.y) * 0.06
	var picture: Texture2D = sign.picture
	var letters := Rect2(pad, pad, inner.x - pad * 2.0, inner.y - pad * 2.0)
	var shown := Rect2()
	if picture != null:
		shown = Rect2(pad, pad, inner.x - pad * 2.0, inner.y * 0.6 - pad)
		letters = Rect2(pad, shown.end.y + pad * 0.6, inner.x - pad * 2.0, inner.y - shown.end.y - pad * 1.4)
	_print(holder, inner, color, picture, shown, false, Color.WHITE, 0.4)
	var light := color.get_luminance() > 0.55
	_print_letters(holder, inner, letters, str(sign.label), Color("#16181d") if light else Color.WHITE)
	_frame_bars(holder, size, SIGN_EDGE, 0.03)

## A poster: the print on a paper mat behind glass in a thin frame, the caption printed under the picture.
static func _poster_print(holder: Node3D, size: Vector2, poster: Dictionary) -> void:
	var inner := size - Vector2.ONE * FRAME_BAR * 2.0
	var pad := minf(inner.x, inner.y) * 0.07
	var caption := str(poster.caption)
	var bottom := inner.y * 0.14 if caption != "" else 0.0
	var shown := Rect2(pad, pad, inner.x - pad * 2.0, inner.y - pad * 2.0 - bottom)
	var paper := Color(str(Surfaces.signage().mat))
	_print(holder, inner, paper, poster.picture, shown, not poster.get("fit", false), paper, 0.75)
	if caption != "": _print_letters(holder, inner, Rect2(pad, shown.end.y + pad * 0.5, inner.x - pad * 2.0, bottom - pad * 0.5), caption, Color(str(Surfaces.signage().text)))
	_frame_bars(holder, size, FRAME_BAR, FRAME_DEPTH)
	_glass(holder, inner)

## The logo wall: a panel painted in the brand colour with the logo printed on it, or the team name when there is no logo. When the
## team's colour paints the walls (brand.walls "accent", "full") the panel is white in a thin frame.
static func _logo_print(holder: Node3D, size: Vector2) -> void:
	var accent := TeamCast.brand_accent()
	var color := accent if accent.a > 0.0 else Color("#2c4bff")
	if TeamCast.brand_walls() != "stripe" and TeamCast.brand_paint().a > 0.0:
		# the team's colour already paints the walls around it: the logo on a white panel in a thin frame
		color = Color(str(Surfaces.signage().mat))
		_frame_bars(holder, size, FRAME_BAR, FRAME_DEPTH)
	var pad := minf(size.x, size.y) * 0.1
	var inner := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
	var logo := TeamCast.logo()
	_print(holder, size, color, logo, inner if logo != null else Rect2(), false, color, 0.5)
	if logo == null: _print_letters(holder, size, inner, TeamCast.team_name(), Color.WHITE if color.get_luminance() < 0.6 else (Party.text_on(color) if Party.night() else Color(str(Surfaces.signage().text))))

## A small hidden plaque: the line engraved dark on the frame material.
static func _egg_print(holder: Node3D, size: Vector2, line: String) -> void:
	var pad := minf(size.x, size.y) * 0.1
	var plate := Color(str(Surfaces.signage().frame))
	_print(holder, size, plate, null, Rect2(), false, plate, float(Surfaces.signage().frame_rough), float(Surfaces.signage().frame_metal))
	_print_letters(holder, size, Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0), line.to_upper(), Color(str(Surfaces.signage().text)), 4)

## The printed face: one lit quad of `size` at z = +0.012 with a composed texture (`fill`, the picture fitted into `shown`, metres from
## the top left corner, on `under`). The same print is composed once.
static func _print(holder: Node3D, size: Vector2, fill: Color, picture: Texture2D, shown: Rect2, cover: bool, under: Color, rough: float, metal := 0.0) -> void:
	var key := "%s|%s|%d|%s|%s|%s|%s|%s" % [size, fill.to_html(), picture.get_instance_id() if picture != null else 0, shown, cover, under.to_html(), rough, metal]
	if not _prints.has(key):
		var scale := minf(PX_PER_METRE, MAX_FACE_PX / maxf(size.x, size.y))
		var width := maxi(8, roundi(size.x * scale))
		var height := maxi(8, roundi(size.y * scale))
		var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
		image.fill(fill)
		if picture != null and shown.has_area():
			var area := Rect2i(roundi(shown.position.x * scale), roundi(shown.position.y * scale), roundi(shown.size.x * scale), roundi(shown.size.y * scale))
			image.fill_rect(area, under)
			_fit_into(image, picture, area, cover)
		_prints[key] = _lit_material(image, rough, metal)
	_quad(holder, size, _prints[key])

## A printed face quad at z = +0.012 showing `image`, lit like the room.
static func _lit_quad(holder: Node3D, size: Vector2, image: Image, rough: float, metal := 0.0) -> void:
	_quad(holder, size, _lit_material(image, rough, metal))

static func _lit_material(image: Image, rough: float, metal: float) -> StandardMaterial3D:
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = rough
	material.metallic = metal
	if Party.night(): # the night look's light is dim: a print glows a little with its own picture, so it reads like a lit board
		material.emission_enabled = true
		material.emission_texture = material.albedo_texture
		material.emission_energy_multiplier = NIGHT_PRINT
	return material

static func _quad(holder: Node3D, size: Vector2, material: StandardMaterial3D) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = quad
	face.material_override = material
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.position = Vector3(0.0, 0.0, 0.012)
	holder.add_child(face)

## Printed lettering fitted into `rect` (metres from the top left corner of a face of `size`): Archivo extra bold, lit like the print.
static func _print_letters(holder: Node3D, size: Vector2, rect: Rect2, text: String, fill: Color, lines := 1) -> void:
	if text == "" or not rect.has_area(): return
	text = text.to_upper() # as the comic font always drew it
	if _print_font == null:
		_print_font = FontVariation.new()
		_print_font.base_font = PRINT_FONT
		_print_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	var one := _print_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var line_height := _print_font.get_height(FONT_SIZE)
	var best := 0.0
	var longest := 0.0 # the widest word: a wrapped line never breaks inside it, so the letters are never bigger than it allows
	if lines > 1:
		for word in text.split(" ", false): longest = maxf(longest, _print_font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	for count in range(1, lines + 1):
		var width := one.x if count == 1 else maxf(one.x / count * 1.2, longest * 1.04)
		var pixel := minf(rect.size.x / maxf(width, 1.0), rect.size.y / (line_height * count))
		if pixel > best * 1.05: best = pixel
	var label := Label3D.new()
	label.name = "Letters"
	label.text = text
	label.font = _print_font
	label.font_size = FONT_SIZE
	label.pixel_size = best
	label.modulate = fill
	label.outline_size = 0
	label.shaded = not Party.night() # the night look's light is dim: lettering keeps its own colour
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if lines > 1:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = rect.size.x / best
	label.position = Vector3(rect.get_center().x - size.x * 0.5, size.y * 0.5 - rect.get_center().y, 0.016)
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(label)

## Four bars around a face of `size` (outer size), `bar` wide, `depth` proud of the board, in the look's frame material.
static func _frame_bars(holder: Node3D, size: Vector2, bar: float, depth: float) -> void:
	var material := _paint("frame")
	for spec: Array in [[Vector3(0.0, size.y * 0.5 - bar * 0.5, 0.0), Vector3(size.x, bar, depth)], [Vector3(0.0, -size.y * 0.5 + bar * 0.5, 0.0), Vector3(size.x, bar, depth)],
			[Vector3(-size.x * 0.5 + bar * 0.5, 0.0, 0.0), Vector3(bar, size.y - bar * 2.0, depth)], [Vector3(size.x * 0.5 - bar * 0.5, 0.0, 0.0), Vector3(bar, size.y - bar * 2.0, depth)]]:
		var piece := MeshInstance3D.new()
		piece.name = "Frame"
		var box := BoxMesh.new()
		box.size = spec[1]
		piece.mesh = box
		piece.material_override = material
		piece.position = (spec[0] as Vector3) + Vector3(0.0, 0.0, depth * 0.5)
		holder.add_child(piece)

## A sheet of glass over a poster: nearly clear, glossy, so it catches the room.
static func _glass(holder: Node3D, size: Vector2) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = quad
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.05)
	material.roughness = 0.06
	material.metallic_specular = 0.8
	glass.material_override = material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = Vector3(0.0, 0.0, FRAME_DEPTH * 0.6)
	holder.add_child(glass)

## The look's frame, board or post material (style/surfaces.gd signage), shared.
static func _paint(part: String) -> StandardMaterial3D:
	var key := "print_" + part
	if not _flat_materials.has(key):
		var spec := Surfaces.signage()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(str(spec[part]))
		material.metallic = float(spec.get(part + "_metal", spec.frame_metal if part == "frame" else 0.0))
		material.roughness = float(spec.frame_rough) if part == "frame" else 0.55
		_flat_materials[key] = material
	return _flat_materials[key]

# ------------------------------------------------------------------ obstacle boxes

## The faces of OBSTACLE BOXES: every box shape whose meta "slot" names a cast obstacle (obstacle_1 .. obstacle_5, set by the level world on
## blocks and hazard parts) gets the cast's picture on its four sides and its top, or a plate in the obstacle's colour (else the brand
## accent) with the label lettered on the four sides. The faces are children of the shape node, so a moving hazard carries them; they stand
## BOX_LIFT off the box and touch no collision. One material per obstacle id, one mesh per box. A box whose obstacle the cast does not
## list keeps the look it was drawn with. `shapes`: CollisionShape3D nodes (others are skipped). Returns how many boxes got faces.
static func box_faces(shapes: Array) -> int:
	var done := 0
	for node in shapes:
		var shape_node := node as CollisionShape3D
		if shape_node == null or not shape_node.has_meta("slot") or not shape_node.shape is BoxShape3D: continue
		var id := str(shape_node.get_meta("slot"))
		if id == Hazards.GATE_SLOT: continue # the start gate is a chevron door (style/race_surfaces.gd is_door): the brand is on the START sign only
		var sign := TeamCast.obstacle(_number(id, "obstacle_"))
		if not id.begins_with("obstacle_") or sign.is_empty(): continue
		_box_faces(shape_node, id, sign)
		done += 1
	return done

static func _box_faces(shape_node: CollisionShape3D, id: String, sign: Dictionary) -> void:
	var size: Vector3 = (shape_node.shape as BoxShape3D).size
	var picture: Texture2D = sign.picture
	var color: Color = sign.color if (sign.color as Color).a > 0.0 else _accent(SIGN_YELLOW)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var plates: Array = [] # [Transform3D, Vector2] of the sides, for the lettering
	var art: Texture2D = TeamCast.trimmed(picture, 0.06) # without the empty bands around its content
	var flat := art != null and TeamCast.plain_edge(art) # a picture on a flat background: shown whole, the rest of the face in its edge colour
	var art_aspect := float(art.get_width()) / art.get_height() if art != null else 1.0
	for index in BOX_FACES.size():
		var spec: Array = BOX_FACES[index]
		var normal: Vector3 = spec[0]
		var right: Vector3 = spec[1]
		var up: Vector3 = spec[2]
		var width := absf(right.dot(size))
		var height := absf(up.dot(size))
		var centre := normal * (absf(normal.dot(size)) * 0.5 + BOX_LIFT)
		var inset := minf(BOX_INSET, minf(width, height) * 0.25)
		var half := Vector2(width * 0.5 - inset, height * 0.5 - inset)
		# [x0, x1, y0, y1, u0, u1, v0, v1]: pieces of the face (its own x right, y up from the middle) and the part of the picture each shows
		var pieces: Array = []
		if picture == null:
			pieces.append([-half.x, half.x, -half.y, half.y, 0.0, 1.0, 0.0, 1.0])
		elif flat:
			# the whole content, never cropped, as large as the face allows; a face wider (taller) than that gets the picture's own edge colour
			# on both sides, made by stretching the picture's outermost row / column (the picture's edge is one plain colour)
			var face_aspect := half.x / half.y
			if face_aspect >= art_aspect:
				# a long wall repeats the picture in cells that are at least 2:1 (a narrow picture stands alone in its cell, not many in a row)
				var count := maxf(1.0, floorf(face_aspect / maxf(art_aspect, 2.0) + 0.001))
				var cell := half.x * 2.0 / count
				var tile := minf(cell, half.y * 2.0 * art_aspect)
				var margin := (cell - tile) * 0.5
				for cell_index in int(count):
					var x0 := -half.x + cell * cell_index
					if margin > 0.001:
						pieces.append([x0, x0 + margin, -half.y, half.y, 0.0, 0.0, 0.0, 1.0])
						pieces.append([x0 + cell - margin, x0 + cell, -half.y, half.y, 1.0, 1.0, 0.0, 1.0])
					pieces.append([x0 + margin, x0 + margin + tile, -half.y, half.y, 0.0, 1.0, 0.0, 1.0])
			else:
				var tile := half.x * 2.0 / art_aspect
				var margin := half.y - tile * 0.5
				pieces.append([-half.x, half.x, half.y - margin, half.y, 0.0, 1.0, 0.0, 0.0])
				pieces.append([-half.x, half.x, -half.y, -half.y + margin, 0.0, 1.0, 1.0, 1.0])
				pieces.append([-half.x, half.x, -half.y + margin, half.y - margin, 0.0, 1.0, 0.0, 1.0])
		else:
			var crop := Vector2(1.0, 1.0) # share of the picture the face shows (cover: the centre of the picture)
			var tiles := 1.0 # a face much wider than the picture repeats it along its width instead of cropping half of it away
			var fit := (width / height) / (float(art.get_width()) / art.get_height())
			if fit > 1.0:
				tiles = maxf(1.0, floorf(fit + 0.001))
				crop.y = tiles / fit
			else: crop.x = fit
			var u0 := (1.0 - crop.x) * 0.5
			var v0 := (1.0 - crop.y) * 0.5
			pieces.append([-half.x, half.x, -half.y, half.y, u0, u0 + crop.x * tiles, v0, 1.0 - v0])
		for piece: Array in pieces:
			var corners: Array = [[piece[0], piece[3], piece[4], piece[6]], [piece[1], piece[3], piece[5], piece[6]], [piece[1], piece[2], piece[5], piece[7]], [piece[0], piece[2], piece[4], piece[7]]]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				var c: Array = corners[corner]
				vertices.append(centre + right * float(c[0]) + up * float(c[1]))
				normals.append(normal)
				uvs.append(Vector2(float(c[2]), float(c[3])))
		if index < 4: plates.append([Transform3D(Basis(right, up, normal), centre), Vector2(width, height)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var faces := MeshInstance3D.new()
	faces.name = "ObstacleFaces"
	faces.mesh = mesh
	faces.material_override = _box_material(id, art, color, Color.WHITE.lerp(sign.color, PICTURE_TINT) if picture != null and (sign.color as Color).a > 0.0 else Color.WHITE)
	faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shape_node.add_child(faces)
	if picture != null: return
	var ink := Color("#16181d") if color.get_luminance() > 0.55 else Color.WHITE
	for plate: Array in plates:
		var face_size: Vector2 = plate[1]
		var pad := minf(face_size.x, face_size.y) * 0.1
		var holder := Node3D.new()
		holder.name = "ObstacleLetters"
		holder.transform = plate[0]
		shape_node.add_child(holder)
		_lettering(holder, face_size, Rect2(pad, pad, face_size.x - pad * 2.0, face_size.y - pad * 2.0), str(sign.label), ink, 2)

## The shared material of one obstacle id: the picture (tinted a little towards the obstacle's own colour, so pale pictures still tell apart), or the plate colour.
static func _box_material(id: String, picture: Texture2D, color: Color, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%d|%s|%s" % [id, picture.get_instance_id() if picture != null else 0, color.to_html(), tint.to_html()]
	if not _box_materials.has(key):
		var material := StandardMaterial3D.new()
		material.roughness = 0.6
		if picture != null:
			material.albedo_texture = picture
			material.albedo_color = tint
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if Party.night(): # a dark world: the picture glows a little with its own colours
				material.emission_enabled = true
				material.emission_texture = picture
				material.emission_energy_multiplier = NIGHT_PRINT
		else:
			material.albedo_color = color
		_box_materials[key] = material
	return _box_materials[key]
