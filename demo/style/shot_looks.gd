extends RefCounted
## What a ball and a cannon ball come out of and go into (levels/hazards.gd build_life: the ports and the plan), so nothing pops in or out in view. Decor only,
## client only: collision, hit volumes and timing are the hazards'. Cheap on phones: a flat decal per port (one quad, an SDF shader), a cannon is a metal
## tube, a post, a muzzle decal and two cards; everything is a child of the level, in level-local space.
##   wall slot   a ball whose path starts / ends against a wall rolls through a round slot in it: a dark disc with a rim in the brand accent on the wall face
##               (the ball is drawn rolling on through the wall, hidden by it, until it is fully inside, hazards.gd `lead`).
##   floor hole  a ball in the open comes up out of / sinks into a dark slot in the floor (a stadium as long as the way it speeds up or slows down).
##   cannon      a mortar: a tube along the shot with the ball inside it at the shot (it leaves through the muzzle's dark disc), a post to what holds it, a muzzle
##               flash, a puff of smoke and a short recoil of the whole barrel once the ball is clear. The ball then bounces, rolls on and is swallowed by the
##               wall slot where the plan ends (levels/hazards.gd shot_plan).
##   ball        the ball itself (and a cannon ball, in the same three tones): a sphere in a colour of the world style's palette (an accent / second / silver role by size,
##               never the hazard red), panels in a second tone (the night look: glowing grid lines) that show it rolling, a child of its hazard's body so it turns with
##               the roll. In the round the cast dresses (show.rounds.r23, docs/swappables.md) a big ball wears the round's labels on four spots (two on the roll axis, two
##               across it, so a word comes round to the camera now and then), or the cast's model (TeamCast.round_model) replaces the sphere, fitted to its diameter.
const Hazards := preload("res://levels/hazards.gd")
const HazardLooks := preload("res://style/hazard_looks.gd")
const TeamCast := preload("res://style/team_cast.gd")
const Party := preload("res://style/party_look.gd")
const Surfaces := preload("res://style/surfaces.gd")
const BlockMesh := preload("res://style/block_mesh.gd")
const HeroProp := preload("res://style/hero_prop.gd")
const CannonLook := preload("res://style/cannon_look.gd")
const CourseSection := preload("res://course_section.gd")
const WORD_FONT := preload("res://assets/fonts/Archivo.ttf")
const BALL_ROUND := "r23"          ## the round whose balls the cast may label or replace with a model
const TONE_ROLES := ["a", "p", "x"] ## palette roles of a big, a middle-sized and a small (hop size) ball
const BIG_BALL := 1.4              ## m radius from which a ball is big (it wears the round's words) ...
const MIDDLE_BALL := 0.7           ## ... and from which it is middle-sized (a cannon ball, 0.75, is one); the smaller ones are hop size
const FLOOR_CONTRAST := 2.4        ## party look: a ball is darkened until it has this much contrast to both floor tones ...
const PANEL_CONTRAST := 1.6        ## ... and its panels this much
const PANELS := 8                  ## party look: stripes round a ball (an even number: two tones alternate)
const GLOW_CELLS := 6              ## night look: grid lines round a ball
const NIGHT_CONTRAST := 3.2        ## night look: the ball's body and its glowing lines are lightened until they have this much contrast to both floor tones
const WORD_WIDTH := 1.25           ## a word is this many radii wide at most ...
const WORD_HEIGHT := 0.5           ## ... and this many radii tall
const WORD_LIFT := 0.03            ## m a word stands off the ball's surface
const WORD_FONT_SIZE := 64
const SLOT_MARGIN := 0.12      ## m the slot / hole is wider than the ball
const RIM := 0.14              ## m, the rim ring around a slot
const WALL_LIFT := 0.1         ## m a wall slot's decal stands off the wall (over a picture on it)
const FLOOR_LIFT := 0.02       ## m a floor hole's decal stands off the floor
const TUBE_SLACK := 0.18       ## m the cannon tube is wider than its ball
const TUBE_BACK := 0.3         ## m of tube behind the ball
const POST_REACH := 3.0        ## m: a post under the barrel when a block holds it from this near
const POST_RADIUS := 0.4
const RECOIL_AT := 0.2         ## s after the shot the barrel starts to kick back (the ball is clear of it by then) ...
const RECOIL_TIME := 0.5       ## ... and is back after this long
const RECOIL_BACK := 0.3       ## m
const FLASH_TIME := 0.16
const PUFF_TIME := 0.9

static var _port_shader: Shader
static var _puff_shader: Shader
static var _ball_meshes := {}       ## "<size index>_<radius>" -> the ball's mesh (one per size and tone, shared by every ball of it)
static var _ball_palette := ""      ## the palette key the meshes were made for
static var _word_font: FontVariation

## A dark opening with a rim: a stadium (a circle when `half_length` is 0) in the plane of the quad; outside the rim nothing is drawn.
const PORT_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\n" + \
	"uniform vec4 rim_color : source_color = vec4(0.94, 0.49, 0.18, 1.0);\nuniform vec2 shape = vec2(0.0, 1.0);\nuniform float rim = 0.14;\nvarying vec2 lp;\n" + """
void vertex() { lp = VERTEX.xy; }
void fragment() {
	float d = length(vec2(max(abs(lp.x) - shape.x, 0.0), lp.y)) - shape.y;
	if (d > rim) discard;
	float depth = clamp(-d / shape.y, 0.0, 1.0);
	vec3 dark = mix(vec3(0.11, 0.1, 0.12), vec3(0.01, 0.01, 0.02), smoothstep(0.0, 0.5, depth));
	ALBEDO = d > 0.0 ? rim_color.rgb : dark;
}
"""

## A muzzle flash (flash 1) or a puff of smoke on a card that turns to the camera about the up axis; `age` 0..1 through its short life.
const PUFF_SHADER := "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;\n" + \
	"uniform float age = 1.0;\nuniform float flash = 0.0;\nuniform vec3 tint = vec3(0.78);\n" + HazardLooks.CARD_VERTEX + """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(UV * 3.0 + vec2(age * 2.0, 3.1));
	if (flash > 0.5) {
		float star = 0.72 + 0.28 * cos(atan(p.y, p.x) * 7.0);
		float r = length(p) / star + (n - 0.5) * 0.3;
		float body = smoothstep(0.95, 0.15, r);
		vec3 color = mix(vec3(1.0, 0.5, 0.08), vec3(1.0, 0.95, 0.7), smoothstep(0.55, 0.15, r));
		ALBEDO = color;
		ALPHA = body * (1.0 - age);
	} else {
		float r = length(p) + (n - 0.5) * 0.55;
		ALBEDO = tint * mix(0.8, 1.0, n);
		ALPHA = smoothstep(0.9, 0.2, r) * 0.7 * (1.0 - age) * smoothstep(0.0, 0.08, age);
	}
}
"""

static func _shader(code: String, cached: Shader) -> Shader:
	if cached != null: return cached
	var shader := Shader.new()
	shader.code = code
	return shader

static func _rim_color() -> Color:
	var accent := TeamCast.brand_accent()
	return accent if accent.a > 0.0 else HazardLooks.PAD_COLOR

## The decal of one opening: `point` on the surface, `normal` out of it, `along` the long axis of a stadium.
static func _port(parent: Node3D, point: Vector3, normal: Vector3, along: Vector3, half_length: float, radius: float, lift: float) -> MeshInstance3D:
	if _port_shader == null: _port_shader = _shader(PORT_SHADER, null)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0 * (half_length + radius + RIM), 2.0 * (radius + RIM))
	var material := ShaderMaterial.new()
	material.shader = _port_shader
	material.set_shader_parameter("rim_color", _rim_color())
	material.set_shader_parameter("shape", Vector2(half_length, radius))
	material.set_shader_parameter("rim", RIM)
	var node := HazardLooks._mesh(parent, quad, material, Transform3D(Basis(along, normal.cross(along), normal), point + normal * lift))
	node.name = "BallPort"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func _wall_port(parent: Node3D, point: Vector3, normal: Vector3, radius: float) -> void:
	_port(parent, point, normal, Vector3.UP.cross(normal).normalized(), 0.0, radius, WALL_LIFT)

## Builds the look of hazard `h` (a ball or a cannon; `build_life` has run) under `level_root`: its housings, and, when `body` (the hazard's body) is given, the ball
## itself as a child of it (`level` is the 0-based level, for the round the cast dresses). Returns the state `pose()` drives ({} for a ball: static).
static func build(level_root: Node3D, h: Dictionary, blocks: Array, body: Node3D = null, level := -1) -> Dictionary:
	if body != null: _skin(level_root, h, body, level)
	if h.k == "ball":
		_ball(level_root, h)
		return {}
	return _cannon(level_root, h, blocks)

# ------------------------------------------------------------------ the ball itself

## 0 for a big ball, 1 for a middle-sized one (a cannon ball), 2 for a hop-size one.
static func size_index(rad: float) -> int:
	if rad >= BIG_BALL: return 0
	return 1 if rad >= MIDDLE_BALL else 2

## [body, second] colours of ball size `index` from the world style's palette (`palette` = Party.palette(), `night` = Party.night()): night, the role's bright main with
## glowing lines in its pale tone, both lightened until they have NIGHT_CONTRAST to both floor tones; party, the role darkened until it has FLOOR_CONTRAST to both floor
## tones (a hazard that reads on the track), its soft tone darkened to PANEL_CONTRAST for the panels. Pure: tools/party_look_check.gd runs it over many palettes.
static func tone_colors(palette: Dictionary, night: bool, index: int) -> Array:
	var role: Dictionary = palette[TONE_ROLES[index]]
	var main: Color = role.main
	var soft: Color = role.soft
	var floors: Array = [palette.floor_a, palette.floor_b]
	if night: return [_lighter_than_all(main, floors, NIGHT_CONTRAST), _lighter_than_all(role.pale, floors, NIGHT_CONTRAST)]
	return [Party.against_all(main, floors, FLOOR_CONTRAST), Party.against_all(soft, floors, PANEL_CONTRAST)]

## `color` mixed towards white until it has at least `ratio` contrast to every colour of `others` (itself when it already has).
static func _lighter_than_all(color: Color, others: Array, ratio: float) -> Color:
	var result := color
	for step in 30:
		var ok := true
		for other: Color in others:
			if Party.contrast(result, other) < ratio: ok = false
		if ok: break
		result = result.lerp(Color.WHITE, 0.12)
	return result

static func _ball_material(index: int, rad: float) -> ShaderMaterial:
	var colors := tone_colors(Party.palette(), Party.night(), index)
	var material := Surfaces.material("danger")
	material.set_shader_parameter("tint", colors[0])
	material.set_shader_parameter("tint2", colors[1])
	if Party.night():
		material.set_shader_parameter("pattern", 5) # the night look's glowing grid
		material.set_shader_parameter("pattern_size", TAU * rad / GLOW_CELLS)
		material.set_shader_parameter("line_width", maxf(rad * 0.06, 0.04))
		material.set_shader_parameter("glow", 1.1)
		material.set_shader_parameter("emit", 0.6)
	else:
		material.set_shader_parameter("pattern", 2) # stripes along u: panels round the ball, a whole number of them
		material.set_shader_parameter("pattern_size", TAU * rad / PANELS)
	return material

## The ball's mesh: a lathed sphere with a material of its size's tone; shared by every ball of that size and radius until the palette changes.
static func _ball_mesh(index: int, rad: float) -> Mesh:
	var palette := str(TeamCast.brand_colors()) + TeamCast.world_style() + str(Party.night())
	if palette != _ball_palette:
		_ball_palette = palette
		_ball_meshes.clear()
	var key := "%d_%.2f" % [index, rad]
	if not _ball_meshes.has(key):
		var batch := BlockMesh.Batch.new()
		batch.lathe(Transform3D.IDENTITY, rad, 0.0, 0.0, "ball", "ball")
		_ball_meshes[key] = batch.commit({"ball": _ball_material(index, rad)})
	return _ball_meshes[key]

## The ball of hazard `h` as a child of its `body` (the collision look leaves the body alone: meta "fx"). Only in the party / night look: other looks keep the
## collision look's ball. In the round the cast dresses the model replaces the sphere; else a big ball of a ball hazard wears the round's words.
static func _skin(level_root: Node3D, h: Dictionary, body: Node3D, level: int) -> void:
	if not Party.on(): return
	body.set_meta("fx", true)
	var rad := float(h.rad)
	var round_id := CourseSection.round_id(level) if level >= 0 else ""
	if round_id == BALL_ROUND:
		var model := HeroProp.fit_into(TeamCast.round_model(BALL_ROUND), Vector3.ONE * rad * 2.0)
		if model != null:
			model.name = "BallModel"
			body.add_child(model)
			return
	var index := size_index(rad)
	var node := MeshInstance3D.new()
	node.name = "BallLook"
	node.mesh = _ball_mesh(index, rad)
	body.add_child(node)
	if round_id != BALL_ROUND or h.k != "ball" or index != 0: return
	var words := TeamCast.round_labels(BALL_ROUND)
	if words.is_empty(): return
	var count := int(level_root.get_meta("ball_words", 0)) # the balls take the words in turn, in the file's order
	level_root.set_meta("ball_words", count + 1)
	var colors := tone_colors(Party.palette(), Party.night(), index)
	_words(body, h, words[count % words.size()], rad, Party.text_on(colors[0]))

## `text` on four spots of a ball: two on its roll axis (the sides of a ball that rolls down the road) and two across it (top and bottom: they come round as it
## rolls), each a flat label standing WORD_LIFT off the sphere, upright for its spot. A child of the body, so it turns with the roll.
static func _words(body: Node3D, h: Dictionary, text: String, rad: float, fill: Color) -> void:
	var points: PackedVector3Array = h.path
	if points.size() < 2: return
	if _word_font == null:
		_word_font = FontVariation.new()
		_word_font.base_font = WORD_FONT
		_word_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	var wide := _word_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_FONT_SIZE).x
	var pixel := minf(WORD_WIDTH * rad / maxf(wide, 1.0), WORD_HEIGHT * rad / maxf(_word_font.get_height(WORD_FONT_SIZE), 1.0))
	var first := (points[1] - points[0]).normalized()
	var roll := Vector3.UP.cross(first).normalized()
	if roll.length_squared() < 0.5: return # a ball that starts by rolling straight up or down has no roll axis to put words on
	for spot: Array in [[roll, Vector3.UP], [-roll, Vector3.UP], [Vector3.UP, first], [Vector3.DOWN, first]]:
		var normal: Vector3 = spot[0]
		var across := (spot[1] as Vector3).cross(normal).normalized()
		var label := Label3D.new()
		label.name = "BallWord"
		label.text = text
		label.font = _word_font
		label.font_size = WORD_FONT_SIZE
		label.pixel_size = pixel
		label.modulate = fill
		label.outline_size = 0
		label.shaded = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.double_sided = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.transform = Transform3D(Basis(across, normal.cross(across), normal), normal * (rad + WORD_LIFT))
		body.add_child(label)

# ------------------------------------------------------------------ rolling balls

static func _ball(level_root: Node3D, h: Dictionary) -> void:
	if not h.has("ports"): return
	var ports: Dictionary = h.ports
	var points: PackedVector3Array = h.path
	var rad := float(h.rad)
	var speed := float(h.speed)
	var first := (points[1] - points[0]).normalized()
	var last := (points[points.size() - 1] - points[points.size() - 2]).normalized()
	_end(level_root, ports.enter, points[0], -first, float(ports.lead_in), rad, speed)
	_end(level_root, ports.leave, points[points.size() - 1], last, float(ports.lead_out), rad, speed)

## One end of a path: `anchor` is the path's end, `outward` the way the ball goes beyond it (away from the path).
static func _end(level_root: Node3D, port: Dictionary, anchor: Vector3, outward: Vector3, lead: float, rad: float, speed: float) -> void:
	if port.kind == "wall":
		_wall_port(level_root, port.point as Vector3, port.normal as Vector3, rad + SLOT_MARGIN)
	elif port.kind == "floor" and lead > 0.0:
		var reach := speed * lead * 0.5 # the way it speeds up out of / slows down into the hole
		var middle := anchor + outward * reach * 0.5
		_port(level_root, Vector3(middle.x, (port.point as Vector3).y, middle.z), Vector3.UP, outward, reach * 0.5, rad + SLOT_MARGIN, FLOOR_LIFT)

# ------------------------------------------------------------------ cannons

static func _cannon(level_root: Node3D, h: Dictionary, blocks: Array) -> Dictionary:
	var look := HazardLooks.materials()
	var rad := float(h.rad)
	var pivot: Vector3 = h.pivot
	var dir := (h.v as Vector3).normalized()
	if dir.length_squared() < 0.5: return {}
	var radius := rad + TUBE_SLACK
	var length := 2.0 * rad + TUBE_BACK
	var muzzle := pivot + dir * rad # the ball sits just inside it at the shot
	var holder := Node3D.new()
	holder.name = "Cannon"
	level_root.add_child(holder)
	var breech := muzzle - dir * length
	var down := Hazards.wall_distance(blocks, breech, Vector3.DOWN)
	if level_root.has_meta("daylight"): # the race world: a striped barrel on a round base (style/cannon_look.gd)
		CannonLook.build(holder, level_root, dir, muzzle, rad, radius, length, down if down <= POST_REACH else -1.0)
	else:
		var tube := HazardLooks._mesh(holder, HazardLooks._rod(radius, length, 24), look.housing, Transform3D(HazardLooks.along(dir), muzzle - dir * length * 0.5))
		tube.name = "CannonTube"
		var mouth := _port(holder, muzzle, dir, Vector3.UP.cross(dir).normalized(), 0.0, rad + 0.05, FLOOR_LIFT)
		mouth.name = "CannonMouth"
		# a post down to what holds it (a wall's top), not a pole to a faraway floor
		if down <= POST_REACH and down > radius:
			var post := HazardLooks._mesh(level_root, HazardLooks._rod(POST_RADIUS, down, 14), look.housing, Transform3D(Basis.IDENTITY, breech + Vector3.DOWN * down * 0.5))
			post.name = "CannonPost"
	var state := {"holder": holder, "dir": dir, "muzzle": muzzle, "radius": radius}
	state.flash = _card(holder, "CannonFlash", 1.0, radius * 3.2)
	state.smoke = _card(holder, "CannonSmoke", 0.0, radius * 2.6)
	if h.has("plan"):
		var plan: Dictionary = h.plan
		if plan.kind == "wall":
			var port: Dictionary = plan.port
			_wall_port(level_root, port.point as Vector3, port.normal as Vector3, rad + SLOT_MARGIN)
	return state

static func _card(parent: Node3D, label: String, flash: float, size: float) -> MeshInstance3D:
	if _puff_shader == null: _puff_shader = _shader(PUFF_SHADER, null)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := ShaderMaterial.new()
	material.shader = _puff_shader
	material.set_shader_parameter("flash", flash)
	var node := HazardLooks._mesh(parent, quad, material)
	node.name = label
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

# ------------------------------------------------------------------ state

## Each tick: the barrel's recoil, the flash and the puff of a cannon, from the clock alone (the same on every peer).
static func pose(state: Dictionary, h: Dictionary, clock: float) -> void:
	if not state.has("holder"): return
	var s := fposmod(clock + float(h.phase), float(h.period))
	var dir: Vector3 = state.dir
	var muzzle: Vector3 = state.muzzle
	var x := (s - RECOIL_AT) / RECOIL_TIME
	(state.holder as Node3D).position = -dir * RECOIL_BACK * sin(PI * x) if x > 0.0 and x < 1.0 else Vector3.ZERO
	var flash: MeshInstance3D = state.flash
	flash.visible = s < FLASH_TIME
	if flash.visible:
		flash.position = muzzle + dir * (float(state.radius) * 0.8)
		(flash.material_override as ShaderMaterial).set_shader_parameter("age", s / FLASH_TIME)
	var smoke: MeshInstance3D = state.smoke
	smoke.visible = s < PUFF_TIME
	if smoke.visible:
		var age := s / PUFF_TIME
		smoke.position = muzzle + dir * (0.4 + age * 1.6) + Vector3.UP * age * 0.8
		smoke.scale = Vector3.ONE * (0.5 + age * 1.3)
		(smoke.material_override as ShaderMaterial).set_shader_parameter("age", age)
