extends RefCounted
## The number of a balloon room (ROOM 03), stencil-painted on the wall the team faces from the start pad (the first block straight
## ahead of the pad, HEIGHT metres up), as high up that wall as it fits: the follow camera sits behind each player's own courier, so
## only the top of a far wall shows over it at the start. A smaller ROOM sits over the two digits. The letters are flat meshes in one
## condensed stencil face, and paint_material() is the worn paint they share (restyle the look there). Client look only, built with
## the level's other marks (levels/level_world.gd _mark); a level that is not a room (course_section.gd room_of) gets nothing.
const CourseSection := preload("res://course_section.gd")
const Hazards := preload("res://levels/hazards.gd")
const TeamCast := preload("res://style/team_cast.gd")
const STENCIL := preload("res://assets/fonts/BigShouldersStencilDisplay-ExtraBold.ttf") ## OFL (docs/PROVENANCE.md)
const HEIGHT := 7.0     ## metres above the start pad: the height the wall is looked for at
const MARGIN := 0.5     ## metres between the top of the lettering and the top of the wall
const DIGITS := 3.2     ## metres, the height of the digits
const WORD := 0.9       ## metres, the height of ROOM over them
const REACH := 150.0    ## metres: no wall within this, no number
const PROUD := 0.02     ## metres in front of the wall face
const FONT_SIZE := 64
const CAPITALS := 0.7   ## share of the line height the capitals and figures fill
static var _paint: Material

static func build(level_root: Node3D, data: Dictionary, dir: String) -> Node3D:
	var room := CourseSection.room_of(int(data.number) - 1, dir)
	if room <= 0: return null
	var forward := Vector3.FORWARD.rotated(Vector3.UP, float(data.start_yaw))
	var from: Vector3 = (data.start as Vector3) + Vector3.UP * HEIGHT
	var nearest := REACH
	var top := from.y
	for block: Dictionary in data.blocks:
		var distance := Hazards.ray_hit(block, from, forward)
		if distance < nearest:
			nearest = distance
			top = (block.xf as Transform3D).origin.y + (block.size as Vector3).y * 0.5
	if nearest >= REACH: return null
	var middle := maxf(from.y, top - MARGIN - WORD - 0.2 - DIGITS * 0.5)
	var holder := Node3D.new()
	holder.name = "RoomNumber"
	holder.transform = Transform3D(Basis.looking_at(forward), Vector3(from.x, middle, from.z) + forward * (nearest - PROUD))
	holder.add_child(_letters("%02d" % room, DIGITS, 0.0))
	holder.add_child(_letters("ROOM", WORD, (DIGITS + WORD) * 0.5 + 0.2))
	level_root.add_child(holder)
	return holder

## The paint of the stencil letters: a safety-yellow marking paint (it reads on light concrete and on dark tile alike), matte, a
## little paler where it went on thin and worn away in small chips (a value noise over the letters' surface, so every room wears
## differently). White when the team's colour paints the end wall (TeamCast.brand_walls() "accent" or "full"), so the number reads on
## it. Shared by every room number.
static func paint_material() -> Material:
	if _paint != null: return _paint
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec4 paint : source_color = vec4(0.88, 0.58, 0.04, 1.0);
uniform float wear : hint_range(0.0, 1.0) = 0.22; // how much of the paint has chipped off
uniform float grain = 2.5;                          // noise cells per metre of lettering
varying vec3 surface;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { surface = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = surface.xy * grain + surface.z * grain * 0.37;
	float n = noise(p) * 0.55 + noise(p * 4.1) * 0.3 + noise(p * 15.3) * 0.15;
	if (n < wear * 0.55) discard;
	ALBEDO = mix(paint.rgb, vec3(0.93, 0.9, 0.82), (1.0 - smoothstep(wear * 0.55, 0.75, n)) * 0.2);
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	if TeamCast.brand_walls() != "stripe" and TeamCast.brand_paint().a > 0.0: material.set_shader_parameter("paint", Color(0.95, 0.95, 0.93))
	_paint = material
	return _paint

## One line of stencil letters `metres` tall, centred `up` metres over the holder, facing back along the ray.
static func _letters(text: String, metres: float, up: float) -> MeshInstance3D:
	var mesh := TextMesh.new()
	mesh.text = text
	mesh.font = STENCIL
	mesh.font_size = FONT_SIZE
	mesh.pixel_size = metres / (STENCIL.get_height(FONT_SIZE) * CAPITALS)
	mesh.depth = 0.0
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var letters := MeshInstance3D.new()
	letters.name = text
	letters.mesh = mesh
	letters.material_override = paint_material()
	letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	letters.position = Vector3(0.0, up, 0.0)
	return letters
