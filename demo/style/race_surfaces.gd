extends RefCounted
## The surfaces of the blocks of a level with `"world": "daylight"` (levels/level_data.gd `world`, style/race_world.gd): style/real_look.gd asks `keys` for the surface keys of a block and
## `material` for their materials, `radius` / `segments` for the rounding. A block wears the surface of its `tone` (level file key, one of TONES) or, without one, of its role: a floor (ground and
## hop blocks) is the P tone, a wall the S tone. Every surface is one material of style/candy_surface.gdshader, flat authored colour, glossy, no texture, no outline; the colours are the course
## scheme of the cast (style/candy_course.gd: P floor, S walls and frames, A accents, white, dark), so a brand colour recolours a course and a cast without brand colours gets blue, purple and amber.
##   teal    the floor (P, vinyl 0.32): the default of every ground and hop block
##   warm    an accent floor (A, vinyl)
##   navy    the pillow wall (S, vinyl): the default wall, the gate walls, the lobby yard's walls
##   frame   door frames and posts (S, hard plastic)
##   door    a closed door slab: white hard plastic with S chevron stripes on both big faces (also every cycling door: a tall thin box of a `blink` hazard, `is_door`)
##   crate   white vinyl
##   eye     the round eyes on a gate's crown (a cylinder lying on its side): the flat ends white with a dark pupil (concentric rings, the disc's own unit UV, `unit_caps`), the rim S plastic
##   court   a court's floor: the light P tone, vinyl
##   hub     the hub of a spinner disc: S plastic
##   disc    the floor of a spinner disc (a cylinder): A with white concentric rings on top, A deep sides
##   stone   the vertex colours of the mesh (style/pillar_kit.gd: the pillars)
##   slime   the slime slope of level 32: glossy pink (the world's slime colour), roughness 0.05
##   finish  the chequered finish strip: white and dark squares
const CandyMaterial := preload("res://style/candy_material.gd")
const CandyCourse := preload("res://style/candy_course.gd")
const CandyLook := preload("res://style/candy_look.gd")
const PREFIX := "race:"
const TONES := ["teal", "warm", "navy", "frame", "door", "crate", "eye", "court", "disc", "hub", "stone", "slime", "finish"]
const FLOOR_TONES := ["teal", "warm", "court", "disc", "slime", "finish"]   ## the surfaces a courier stands on: they dissolve near the eye only when the camera really comes up against them (CandyMaterial.NEAR_FLOOR); every other tone is NEAR_TALL
const DOOR_HEIGHT := 2.5    ## m: a `blink` box at least this tall and at most DOOR_THICK thin is a door
const DOOR_THICK := 1.0
const FLOOR_ROUGH := 0.3   ## near the inflatable family's median (0.32): a broad soft sheen that the sky reflection brightens towards the horizon
const VINYL_ROUGH := 0.35
const GRAZE_COLOR := Color(0.03, 0.14, 0.22)   ## additive, linear: the faint cyan lift of the sky reflection at grazing angles and distance
const GRAZE_POWER := 3.0
const GATE_SHOWN := 1.7     ## m: the start gate's door is DRAWN this high from its foot (its collision stays the whole door): a low cushion barrier the course can be seen over
const GATE_SECTION := 4.5    ## m: about the length of one cushion of that barrier
const GATE_ROUND := 0.24     ## m: the rounding of that barrier
const CHEVRON_PERIOD := 0.7  ## m (along a door face's height) of one chevron stripe and its gap
const CHEVRON_SLOPE := 0.8

const Hazards := preload("res://levels/hazards.gd")
## Rounding of an edge (m) by tone: a chamfer on the floors' top (the kit's own slabs bring their 0.25 m chamfer through geometry), the pillow walls much rounder.
const RADIUS := {"teal": 0.1, "warm": 0.1, "navy": 0.3, "frame": 0.09, "door": 0.09, "crate": 0.15, "eye": 0.03, "court": 0.1, "disc": 0.1, "hub": 0.1, "stone": 0.0,
	"slime": 0.0, "finish": 0.05}
## Tones whose cylinder caps carry a picture in the disc's own unit UV (BlockMesh.Batch.lathe `unit_caps`).
const UNIT_CAP_TONES := ["eye", "disc"]

## Whether the level root `level_root` wears this palette (levels/level_world.gd marks it with the meta "daylight" before the look is drawn).
static func wanted(level_root: Node3D) -> bool:
	return level_root != null and bool(level_root.get_meta("daylight", false))

## The surface keys [top, side, end] of a block of `tone` ("" = by role: `role` 1 a wall, else a floor).
static func keys(tone: String, role: int) -> Array:
	var name := tone if tone in TONES else ("navy" if role == 1 else "teal")
	return ["%s%s:top" % [PREFIX, name], "%s%s:side" % [PREFIX, name], "%s%s:%s" % [PREFIX, name, "end" if name == "door" else "side"]]

## Whether a collision shape of a moving body is a cycling door: a tall, thin box of a `blink` hazard that wears no cast picture (it then wears the "door" surface), or a part of a `lift`
## hazard that names the tone "door" (a gate row's door: it hangs from a lintel and slides up, levels 32).
static func is_door(body: Node, shape_node: CollisionShape3D) -> bool:
	if body == null or not shape_node.shape is BoxShape3D: return false
	if shape_node.has_meta("slot") and str(shape_node.get_meta("slot")) != Hazards.GATE_SLOT: return false # the start gate (a blink box with the slot gate) is a door too: it goes up at GO
	if str(body.name).begins_with("Hazard_lift_"): return str(shape_node.get_meta("tone", "")) == "door"
	if not str(body.name).begins_with("Hazard_blink_"): return false
	var size := (shape_node.shape as BoxShape3D).size
	return size.y >= DOOR_HEIGHT and minf(size.x, size.z) <= DOOR_THICK

static func is_key(key: String) -> bool:
	return key.begins_with(PREFIX)

## Whether the flat caps of a cylinder wearing this surface key carry a picture in the disc's unit UV.
static func unit_caps(key: String) -> bool:
	return _tone_of(key) in UNIT_CAP_TONES

static func _tone_of(key: String) -> String:
	return key.trim_prefix(PREFIX).get_slice(":", 0)

static func radius(key: String) -> float:
	return float(RADIUS.get(_tone_of(key), 0.1))

## The material of a surface key.
static func material(key: String) -> ShaderMaterial:
	var parts := key.trim_prefix(PREFIX).split(":")
	var made := spec(parts[0], parts[1])
	if parts[0] != "slime" and parts[0] != "finish" and not made.has("rim_color"): # every course surface lifts toward light cyan at grazing angles: the sky sheen of a glossy surface
		made["rim_color"] = GRAZE_COLOR
		made["rim_power"] = GRAZE_POWER
	made.merge(CandyMaterial.NEAR_FLOOR if parts[0] in FLOOR_TONES else CandyMaterial.NEAR_TALL, true)
	return CandyMaterial.make(made)

## The colour of a tone's face (`face` "top" or "side"), for the block kit's vertex colours.
static func colour(tone: String, face: String) -> Color:
	var found: Variant = spec(tone, face).get("albedo", Color.WHITE)
	return found if found is Color else Color(str(found))

## The family of a tone: true for hard plastic (roughness 0.11), false for vinyl.
static func is_plastic(tone: String) -> bool:
	return float(spec(tone, "top").get("roughness", CandyLook.ROUGH_VINYL)) <= CandyLook.ROUGH_PLASTIC + 0.001

## The candy_surface uniforms of face `face` (top, side, end) of `tone` under the scheme of the current cast.
static func spec(tone: String, face: String) -> Dictionary:
	var c := CandyCourse.scheme()
	var p: Dictionary = c.p
	var s: Dictionary = c.s
	var a: Dictionary = c.a
	var vinyl := VINYL_ROUGH
	var plastic := CandyLook.ROUGH_PLASTIC
	match tone:
		"teal": return {"albedo": p.main, "roughness": FLOOR_ROUGH}
		"warm": return {"albedo": a.main, "roughness": FLOOR_ROUGH}
		"navy": return {"albedo": s.main, "roughness": vinyl}
		"frame": return {"albedo": s.main, "roughness": plastic}
		"door":
			if face == "side": return {"albedo": c.white, "albedo2": s.main, "roughness": plastic, "pattern": 2, "pattern_period": CHEVRON_PERIOD, "pattern_duty": 0.5, "pattern_slope": CHEVRON_SLOPE}
			return {"albedo": s.main, "roughness": plastic}
		"crate": return {"albedo": c.white, "roughness": vinyl}
		"eye":
			if face == "top": return {"albedo": c.white, "albedo2": c.ink, "roughness": plastic, "pattern": 5, "pattern_period": 1.0, "pattern_duty": 0.35}
			return {"albedo": s.main, "roughness": plastic}
		"court": return {"albedo": p.light, "roughness": FLOOR_ROUGH}
		"hub": return {"albedo": s.main, "roughness": plastic}
		"disc":
			if face == "top": return {"albedo": a.main, "albedo2": c.white, "roughness": vinyl, "pattern": 5, "pattern_period": 0.2, "pattern_duty": 0.14}
			return {"albedo": a.deep, "roughness": vinyl}
		"stone": return {"albedo": Color.WHITE, "use_vertex_color": true, "roughness": vinyl}
		"slime": return {"albedo": CandyLook.SLIME, "roughness": CandyLook.ROUGH_SLIME}
		"finish":
			if face == "top": return {"albedo": c.white, "albedo2": c.ink, "roughness": plastic, "pattern": 3, "pattern_period": 1.0}
			return {"albedo": c.white, "roughness": plastic}
	return {"albedo": p.main, "roughness": FLOOR_ROUGH}
