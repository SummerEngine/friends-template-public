extends RefCounted
## What the hazards that hurt look like (levels/hazards.gd), in a realistic look that runs on the gl_compatibility renderer (the project
## default and the mobile one). All visuals of lasers, fire jets and spike crushers live here, and every material is built in ONE function,
## materials(), so the look can be restyled without touching gameplay code. Cheap on the web and phones: a few meshes and cards per hazard,
## shared materials, no lights, no particles; the flames and smoke move in their shaders.
##   laser   an emissive red core inside a faint additive glow (the glow is the hit radius), between two metal emitter housings with
##           red lenses; while it warns, the thin core flickers alone; off: only the housings.
##   fire    a dark metal grate where the jet comes out; on: a few flame cards (noise-driven shader, turned to the camera about the jet's
##           own up axis); warning: smoke cards over the grate.
##   spikes  brushed-metal cones on every face of a mover's parts (a spike crusher).
##   word()  the gameplay word over a player ("ZAP!", "BURNT!"): white Inter on a flat dark rounded plate (client/world_label.gd).
##   launcher  a push pad (a flat plate on the floor under its volume, chevrons running the way it throws, rim in a pale border) and a bumper (a
##           ball on a base standing on the floor), both in the brand accent of the cast: the volume itself is never drawn, so nothing hangs in the air.
##   dress_spin_bars()  the spin bars of the round the cast dresses (show.rounds.r21, docs/swappables.md): its label on both long faces, or its model instead of the bar's look.
## Every look is a child of its hazard's body, so it moves exactly as the hazard does; level_world.gd calls pose() each tick. Client only.
const Hazards := preload("res://levels/hazards.gd")
const TeamCast := preload("res://style/team_cast.gd")
const WorldLabel := preload("res://client/world_label.gd")
const SlotFrames := preload("res://style/slot_frames.gd")
const HeroProp := preload("res://style/hero_prop.gd")
const CourseSection := preload("res://course_section.gd")
const SPIN_ROUND := "r21"      ## the round whose spin bars the cast may label or replace with a model
const CORE_RADIUS := 0.045     ## m, the laser's bright core
const GLOW_RADIUS := Hazards.BEAM_RADIUS ## the faint glow around it: what you see is what zaps
const BEAM_SIDES := 16
const WARN_WIDTH := 0.5        ## share of the core's width while it warns
const HOUSING_RADIUS := 0.16
const HOUSING_LENGTH := 0.32
const FLAME_CARD := 0.9        ## m between flame cards across the jet
const MAX_CARDS := 6
const SMOKE_CARDS := 3
const SPIKE_GAP := 0.45        ## m between spikes on a face
const SPIKE_HEIGHT := 0.3
const SPIKE_RADIUS := 0.1
const WORD_SECONDS := 1.3
const PAD_HEIGHT := 0.14       ## a push pad's plate (m)
const PAD_RIM := 0.13          ## ... and its pale rim
const PAD_COLOR := Color("#ef7d2d") ## a pad and a bumper without a brand accent in the cast
const PAD_MARK := Color("#fff4de")
const BASE_HEIGHT := 0.16      ## a bumper's base disc
const POST_RADIUS := 0.2

static var _materials := {}

## Every material of the hazard looks, built once: {beam_core, beam_glow, housing, lens, grate, flame, smoke, spike}.
static func materials() -> Dictionary:
	if not _materials.is_empty(): return _materials
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA # drawn after the opaque world and writes no depth: no screen pass outlines it
	core.albedo_color = Color(1.0, 0.18, 0.12)
	core.emission_enabled = true
	core.emission = Color(1.0, 0.1, 0.06)
	core.emission_energy_multiplier = 4.0
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.albedo_color = Color(1.0, 0.12, 0.08, 0.28)
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.24, 0.25, 0.28)
	housing.metallic = 0.85
	housing.roughness = 0.35
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.6, 0.05, 0.04)
	lens.emission_enabled = true
	lens.emission = Color(1.0, 0.15, 0.08)
	lens.emission_energy_multiplier = 2.5
	lens.roughness = 0.1
	var grate := StandardMaterial3D.new()
	grate.albedo_color = Color(0.13, 0.13, 0.14)
	grate.metallic = 0.7
	grate.roughness = 0.6
	var flame := ShaderMaterial.new()
	flame.shader = _shader(FLAME_SHADER)
	var smoke := ShaderMaterial.new()
	smoke.shader = _shader(SMOKE_SHADER)
	var spike := StandardMaterial3D.new()
	spike.albedo_color = Color(0.74, 0.76, 0.8)
	spike.metallic = 1.0
	spike.roughness = 0.32
	_materials = {"beam_core": core, "beam_glow": glow, "housing": housing, "lens": lens, "grate": grate, "flame": flame, "smoke": smoke, "spike": spike}
	return _materials

static func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader

## Cards turn to the camera about the hazard's own up axis (a jet that points sideways stays sideways).
const CARD_VERTEX := """
void vertex() {
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_eye = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 side = cross(up, to_eye);
	side = length(side) > 0.0001 ? normalize(side) : normalize(MODEL_MATRIX[0].xyz);
	vec3 facing = cross(side, up);
	mat4 turned = mat4(vec4(side * length(MODEL_MATRIX[0].xyz), 0.0), vec4(up * length(MODEL_MATRIX[1].xyz), 0.0), vec4(facing, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * turned;
}
float vhash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), u.x), mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) { value += amplitude * vnoise(p); p *= 2.03; amplitude *= 0.5; }
	return value;
}
"""

## A flame on a card: a noise-torn tongue, white-yellow at its root, orange to red at its tips, added onto what is behind it.
const FLAME_SHADER := "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;\n" + \
	"uniform float seed = 0.0;\nuniform float intensity = 1.6;\n" + CARD_VERTEX + """
void fragment() {
	float h = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float n = fbm(vec2(UV.x * 2.5 + seed, h * 2.2 - TIME * 2.6 + seed));
	float sway = (n - 0.5) * 0.6 * h;
	float width = mix(0.75, 0.05, pow(h, 0.8)) + (n - 0.5) * 0.25;
	float body = smoothstep(width, width * 0.35, abs(x + sway));
	body *= smoothstep(1.0, 0.55 + n * 0.3, h) * smoothstep(0.0, 0.08, h);
	float heat = clamp(body * (1.15 - h), 0.0, 1.0);
	vec3 color = mix(vec3(0.9, 0.12, 0.02), vec3(1.0, 0.55, 0.08), smoothstep(0.15, 0.5, heat));
	color = mix(color, vec3(1.0, 0.93, 0.7), smoothstep(0.55, 0.9, heat));
	ALBEDO = color * intensity;
	ALPHA = body;
}
"""

## Smoke on a card: a soft grey puff that rises and thins out.
const SMOKE_SHADER := "shader_type spatial;\nrender_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;\n" + \
	"uniform float seed = 0.0;\n" + CARD_VERTEX + """
void fragment() {
	float rise = fract(TIME * 0.45 + seed);
	vec2 p = vec2(UV.x * 2.0 - 1.0, (1.0 - UV.y) * 2.0 - 0.4 - rise * 1.2);
	float n = fbm(UV * 3.0 + vec2(seed, -TIME * 0.6));
	float puff = smoothstep(0.85, 0.2, length(p) + (n - 0.5) * 0.6);
	ALBEDO = mix(vec3(0.32), vec3(0.55), n);
	ALPHA = puff * 0.55 * (1.0 - rise);
}
"""

static func _mesh(parent: Node3D, mesh: Mesh, material: Material, at := Transform3D.IDENTITY) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.transform = at
	parent.add_child(node)
	return node

static func _rod(radius: float, height: float, sides := 12, top := -1.0) -> CylinderMesh:
	var rod := CylinderMesh.new()
	rod.top_radius = radius if top < 0.0 else top
	rod.bottom_radius = radius
	rod.height = height
	rod.radial_segments = sides
	rod.rings = 1
	return rod

## A basis whose Y axis is `direction` (unit).
static func along(direction: Vector3) -> Basis:
	var side := direction.cross(Vector3.FORWARD if absf(direction.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, direction, side.cross(direction))

# ------------------------------------------------------------------ laser

static func laser(body: Node3D, to: Vector3) -> Dictionary:
	var look := materials()
	var length := maxf(to.length(), 0.01)
	var axis := along(to / length)
	var core := _mesh(body, _rod(CORE_RADIUS, length, 8), look.beam_core, Transform3D(axis, to * 0.5))
	core.name = "LaserCore"
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := _mesh(body, _rod(GLOW_RADIUS, length, BEAM_SIDES), look.beam_glow, Transform3D(axis, to * 0.5))
	glow.name = "LaserGlow"
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for end: float in [0.0, 1.0]:
		# Emitter housings: a metal can with a red lens towards the beam, sunk back so the beam leaves the lens.
		var facing := axis if end == 0.0 else Basis(axis.x, -axis.y, -axis.z)
		var at := to * end - facing.y * HOUSING_LENGTH * 0.5
		var housing := _mesh(body, _rod(HOUSING_RADIUS, HOUSING_LENGTH, 16), look.housing, Transform3D(facing, at))
		housing.name = "LaserHousing"
		_mesh(housing, _rod(HOUSING_RADIUS * 0.55, 0.03, 16), look.lens, Transform3D(Basis.IDENTITY, Vector3.UP * HOUSING_LENGTH * 0.5))
	return {"kind": "laser", "core": core, "glow": glow}

# ------------------------------------------------------------------ fire

static func fire(body: Node3D, g: String, size: Vector3) -> Dictionary:
	var look := materials()
	var half := size * 0.5
	var grate_mesh: Mesh
	if g == "cyl": grate_mesh = _rod(half.x, 0.1, 20)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(size.x, 0.1, size.z)
		grate_mesh = box
	var grate := _mesh(body, grate_mesh, look.grate, Transform3D(Basis.IDENTITY, Vector3(0.0, -half.y + 0.05, 0.0)))
	grate.name = "FireGrate"
	# Flame cards in a row across the jet (a second row for a deep one), each with its own seed.
	var flames := Node3D.new()
	flames.name = "Flames"
	body.add_child(flames)
	var across := clampi(roundi(size.x / FLAME_CARD), 1, MAX_CARDS)
	var rows := 2 if size.z > FLAME_CARD * 1.5 else 1
	var card := QuadMesh.new()
	card.size = Vector2(minf(size.x / across, 1.4) * 1.5, size.y * 1.15)
	for row in rows:
		for index in across:
			var x := (float(index) + 0.5) / across * size.x - half.x
			var z := (float(row) + 0.5) / rows * size.z - half.z
			var material: ShaderMaterial = (look.flame as ShaderMaterial).duplicate()
			material.set_shader_parameter("seed", float(index * 7 + row * 13) * 0.37)
			var node := _mesh(flames, card, material, Transform3D(Basis.IDENTITY, Vector3(x, size.y * 0.075, z)))
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smoke := Node3D.new()
	smoke.name = "Smoke"
	body.add_child(smoke)
	var puff := QuadMesh.new()
	puff.size = Vector2(maxf(minf(size.x, size.z), 0.8), maxf(minf(size.x, size.z), 0.8) * 1.4)
	for index in SMOKE_CARDS:
		var material: ShaderMaterial = (look.smoke as ShaderMaterial).duplicate()
		material.set_shader_parameter("seed", float(index) / SMOKE_CARDS)
		var angle := TAU * index / SMOKE_CARDS
		var node := _mesh(smoke, puff, material, Transform3D(Basis.IDENTITY, Vector3(cos(angle) * half.x * 0.3, -half.y + puff.size.y * 0.5, sin(angle) * half.z * 0.3)))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"kind": "fire", "flames": flames, "smoke": smoke}

# ------------------------------------------------------------------ launchers

## Chevrons that run the way a pad throws (or rings spreading out of one that throws straight up) over a plate with a pale rim; `lp` is the
## mesh's own position, so the plate may be any size. `dir` is the throw in the plate's xz plane, `half` the plate's half size (a round plate: x = radius).
const PAD_SHADER := "shader_type spatial;\nuniform vec4 base_color : source_color = vec4(0.94, 0.49, 0.18, 1.0);\n" + \
	"uniform vec4 mark_color : source_color = vec4(1.0, 0.96, 0.87, 1.0);\nuniform vec2 dir = vec2(0.0, -1.0);\nuniform float radial = 0.0;\n" + \
	"uniform float round_plate = 0.0;\nuniform vec2 half_size = vec2(2.0, 1.25);\nuniform float rim = 0.13;\nvarying vec3 lp;\n" + """
void vertex() { lp = VERTEX; }
void fragment() {
	vec2 p = lp.xz;
	float edge = round_plate > 0.5 ? half_size.x - length(p) : min(half_size.x - abs(p.x), half_size.y - abs(p.y));
	vec2 d = normalize(dir);
	float along = dot(p, d);
	float across = dot(p, vec2(-d.y, d.x));
	float phase = (radial > 0.5 ? -length(p) : along + 0.9 * abs(across)) * 0.8 - TIME * 0.9;
	float band = fract(phase);
	float stripe = smoothstep(0.0, 0.07, band) * (1.0 - smoothstep(0.34, 0.41, band));
	float border = 1.0 - smoothstep(rim * 0.8, rim, edge);
	float inside = smoothstep(rim, rim * 1.6, edge);
	float top = step(0.05, lp.y);
	ALBEDO = mix(base_color.rgb, mark_color.rgb, max(border, stripe * inside) * top);
	ROUGHNESS = 0.55;
}
"""

## A launcher's look (`h`: levels/hazards.gd normalize() of a push or bumper) under `area`, whose origin is the volume's centre and whose axes are the
## volume's own. `drop`: how far that centre is over the floor under it (m), -1 for none (the look then stays at the volume).
static func launcher(area: Node3D, h: Dictionary, drop: float) -> void:
	var accent := TeamCast.brand_accent()
	var color: Color = accent if accent.a > 0.0 else PAD_COLOR
	var base: Basis = h.base
	if h.k == "bumper": _bumper(area, float(h.rad), drop, color, base)
	else: _pad(area, h, drop, color, base)

## A push pad: a plate on the floor under the volume (without a floor under it: at the volume's underside), flat in the world, wearing the chevrons.
static func _pad(area: Node3D, h: Dictionary, drop: float, color: Color, base: Basis) -> void:
	var size: Vector3 = h.size
	var round_plate: bool = h.g == "cyl"
	var mesh: Mesh
	if round_plate: mesh = _rod(size.x * 0.5, PAD_HEIGHT, 28)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(size.x, PAD_HEIGHT, size.z)
		mesh = box
	var launch: Vector3 = h.v
	var flat := Vector2(launch.x, launch.z)
	var material := ShaderMaterial.new()
	material.shader = _shader(PAD_SHADER)
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("mark_color", PAD_MARK)
	material.set_shader_parameter("dir", flat if flat.length() >= 1.0 else Vector2(0.0, -1.0))
	material.set_shader_parameter("radial", 1.0 if flat.length() < 1.0 else 0.0)
	material.set_shader_parameter("round_plate", 1.0 if round_plate else 0.0)
	material.set_shader_parameter("half_size", Vector2(size.x * 0.5, size.z * 0.5))
	material.set_shader_parameter("rim", PAD_RIM)
	var centre_y := -drop + PAD_HEIGHT * 0.5 + 0.005 if drop >= 0.0 else -size.y * 0.5 + PAD_HEIGHT * 0.5
	var plate := _mesh(area, mesh, material, Transform3D(base.inverse(), base.inverse() * Vector3(0.0, centre_y, 0.0)))
	plate.name = "LaunchPad"

static func _bumper(area: Node3D, radius: float, drop: float, color: Color, base: Basis) -> void:
	var look := materials()
	var skin := StandardMaterial3D.new()
	skin.albedo_color = color
	skin.roughness = 0.35
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = PAD_MARK
	stripe.roughness = 0.45
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	ball.radial_segments = 32
	ball.rings = 16
	var body := _mesh(area, ball, skin, Transform3D(base.inverse(), Vector3.ZERO))
	body.name = "BumperBall"
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.02
	ring.outer_radius = radius + Hazards.BUMPER_BAND
	ring.rings = 32
	ring.ring_segments = 8
	_mesh(body, ring, stripe, Transform3D.IDENTITY).name = "BumperBand"
	if drop < 0.0: return
	# a base disc on the floor and a post up to the ball (no post when the ball nearly sits on the base)
	var gap := drop - radius
	var disc_radius := minf(radius * 0.75, 1.0)
	var disc := _mesh(area, _rod(disc_radius, BASE_HEIGHT, 28), look.housing, Transform3D(base.inverse(), base.inverse() * Vector3(0.0, -drop + BASE_HEIGHT * 0.5 + 0.005, 0.0)))
	disc.name = "BumperBase"
	if gap > BASE_HEIGHT + 0.05:
		var length := gap - BASE_HEIGHT + 0.1 # into the ball a little
		var post := _mesh(area, _rod(POST_RADIUS, length, 14), look.housing, Transform3D(base.inverse(), base.inverse() * Vector3(0.0, -drop + BASE_HEIGHT + length * 0.5, 0.0)))
		post.name = "BumperPost"

# ------------------------------------------------------------------ spikes

## Metal cones on every face of the box parts (and around the round ones) of a spiked mover: one MultiMesh per part.
static func spikes(body: Node3D, parts: Array) -> void:
	var cone := _rod(SPIKE_RADIUS, SPIKE_HEIGHT, 10, 0.0)
	for part: Dictionary in parts:
		var transforms: Array[Transform3D] = []
		var size: Vector3 = part.size
		var half := size * 0.5
		if part.k == "cyl":
			var radius := float(part.d) * 0.5
			var around := maxi(6, roundi(TAU * radius / SPIKE_GAP))
			var rows := maxi(1, roundi(float(part.h) / SPIKE_GAP))
			for row in rows:
				var y := (float(row) + 0.5) / rows * float(part.h) - float(part.h) * 0.5
				for step in around:
					var out := Vector3(cos(TAU * step / around), 0.0, sin(TAU * step / around))
					transforms.append(Transform3D(along(out), out * (radius + SPIKE_HEIGHT * 0.5) + Vector3(0.0, y, 0.0)))
		elif part.k == "box":
			for axis in 3:
				for sign_value: float in [-1.0, 1.0]:
					var normal := Vector3.ZERO
					normal[axis] = sign_value
					var u := (axis + 1) % 3
					var v := (axis + 2) % 3
					var count_u := maxi(1, floori(size[u] / SPIKE_GAP))
					var count_v := maxi(1, floori(size[v] / SPIKE_GAP))
					for i in count_u:
						for j in count_v:
							var at := normal * (half[axis] + SPIKE_HEIGHT * 0.5)
							at[u] = (float(i) + 0.5) / count_u * size[u] - half[u]
							at[v] = (float(j) + 0.5) / count_v * size[v] - half[v]
							transforms.append(Transform3D(along(normal), at))
		if transforms.is_empty(): continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cone
		multi.instance_count = transforms.size()
		for index in transforms.size(): multi.set_instance_transform(index, transforms[index])
		var holder := MultiMeshInstance3D.new()
		holder.name = "Spikes"
		holder.multimesh = multi
		holder.material_override = materials().spike
		holder.transform = part.xf
		body.add_child(holder)

# ------------------------------------------------------------------ rounds as metaphors

## The spin bars of level `level` (0-based; `level_root` is its drawn level, after the collision look): when the level is the round the cast dresses (SPIN_ROUND:
## show.rounds.r21), a bar wears its label on both long faces (a list of labels: bar 1 the first, bar 2 the second, round again) on a plate in the cast's obstacle colour (else the
## brand accent); the cast's model (TeamCast.round_model) replaces the bar's look instead: fitted evenly inside the bar's collision box, centred on the pivot, a child of the bar's
## box so it turns with it. Collision and gameplay are never touched. Nothing is drawn for a level of another round or a cast without either.
static func dress_spin_bars(level_root: Node3D, level: int) -> void:
	if CourseSection.round_id(level) != SPIN_ROUND: return
	var labels := TeamCast.round_labels(SPIN_ROUND)
	var bar := 0
	for body: Node in level_root.get_children():
		if not body is AnimatableBody3D or not str(body.name).begins_with("Hazard_spin_"): continue
		var model_used := false
		for node: Node in body.get_children():
			var shape_node := node as CollisionShape3D
			if shape_node == null or not shape_node.shape is BoxShape3D: continue
			var size: Vector3 = (shape_node.shape as BoxShape3D).size
			var model := HeroProp.fit_into(TeamCast.round_model(SPIN_ROUND), size)
			if model != null:
				_clear_faces(shape_node)
				shape_node.add_child(model)
				model_used = true
			elif not labels.is_empty():
				_clear_faces(shape_node)
				_label_long_faces(shape_node, size, labels[bar % labels.size()])
		if model_used:
			var look := body.get_node_or_null("CollisionLook") as Node3D
			if look != null: look.visible = false
		bar += 1

## Takes the cast's obstacle faces (SlotFrames.box_faces) off a box shape.
static func _clear_faces(shape_node: CollisionShape3D) -> void:
	for child: Node in shape_node.get_children():
		if str(child.name).begins_with("Obstacle"): child.queue_free()

## `text` on a plate on each of the two longest sides of a box of `size` (the sides, never the top or the ends), standing SlotFrames.BOX_LIFT off it, upright.
static func _label_long_faces(shape_node: CollisionShape3D, size: Vector3, text: String) -> void:
	var sides: Array = []
	for index in 4:
		sides.append(SlotFrames.BOX_FACES[index])
	sides.sort_custom(func(a: Array, b: Array) -> bool: return absf((a[1] as Vector3).dot(size)) > absf((b[1] as Vector3).dot(size)))
	var slot := TeamCast.obstacle(int(str(shape_node.get_meta("slot", "")).trim_prefix("obstacle_"))) if str(shape_node.get_meta("slot", "")).begins_with("obstacle_") else {}
	var color: Color = SlotFrames._accent(SlotFrames.SIGN_YELLOW)
	if not slot.is_empty() and (slot.color as Color).a > 0.0: color = slot.color
	for index in 2:
		var spec: Array = sides[index]
		var normal: Vector3 = spec[0]
		var right: Vector3 = spec[1]
		var up: Vector3 = spec[2]
		var face := Vector2(absf(right.dot(size)), absf(up.dot(size)))
		var inset := minf(SlotFrames.BOX_INSET, minf(face.x, face.y) * 0.25)
		var holder := Node3D.new()
		holder.name = "ObstacleLabel"
		holder.transform = Transform3D(Basis(right, up, normal), normal * (absf(normal.dot(size)) * 0.5 + SlotFrames.BOX_LIFT))
		shape_node.add_child(holder)
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		var quad := QuadMesh.new()
		quad.size = face - Vector2.ONE * inset * 2.0
		plate.mesh = quad
		plate.material_override = SlotFrames._flat(color)
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(plate)
		var pad := minf(face.x, face.y) * 0.1
		SlotFrames._lettering(holder, face, Rect2(pad, pad, face.x - pad * 2.0, face.y - pad * 2.0), text, SlotFrames._on(color))

# ------------------------------------------------------------------ state

## Each tick: `active` = dangerous, `warn` 0..1 through the warning before it turns on (0 = none), `clock` = the level clock.
static func pose(look: Dictionary, active: bool, warn: float, clock: float) -> void:
	match str(look.get("kind", "")):
		"laser":
			var core: MeshInstance3D = look.core
			var flicker := warn > 0.0 and sin(clock * 47.0 + warn * 9.0) > -0.2
			core.visible = active or flicker
			var width := 1.0 if active else WARN_WIDTH
			core.scale = Vector3(width, 1.0, width)
			(look.glow as MeshInstance3D).visible = active
		"fire":
			(look.flames as Node3D).visible = active
			(look.smoke as Node3D).visible = warn > 0.0

# ------------------------------------------------------------------ gameplay words

## The word over a player: it pops in, rises and fades, then frees itself. `at` is world space; `parent` must be in the tree.
static func word(parent: Node3D, text: String, at: Vector3) -> Label3D:
	var label := WorldLabel.make("", 96, 0.008, Color.WHITE, WorldLabel.DARK, 6)
	label.name = "HazardWord"
	label.no_depth_test = true
	WorldLabel.set_text(label, text) # the plate is built on top of the world too
	parent.add_child(label)
	label.global_position = at
	label.scale = Vector3.ONE * 0.3
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE, 0.08)
	tween.parallel().tween_property(label, "global_position", at + Vector3.UP * 1.2, WORD_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(alpha: float) -> void: WorldLabel.set_alpha(label, alpha), 1.0, 0.0, 0.3)
	tween.tween_callback(label.queue_free)
	return label
