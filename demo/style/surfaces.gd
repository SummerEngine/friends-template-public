extends RefCounted
## The world look: a bright test facility (white tiled walls, soft foam blocks on a blue mat, skylights). Its CC0 texture sets
## (demo/assets/surfaces/, docs/PROVENANCE.md), the surfaces a level is made of and the light of its room. Pure data plus material
## builders; style/real_look.gd lays the surfaces on the blocks, style/room_shell.gd builds the room around a level,
## levels/level_environment.gd lights it. The comic ink look (style/ink_look.gd, backdrop, ink sky) is reachable in dev runs
## only, for comparison. The show mode (cast `mode` "show") has the party look instead (style/party_look.gd): `spec()` hands out its
## surfaces, blocks, signage and light in the same shape, painted from the cast's brand colours; the sets below are shared.
const DevEnv := preload("res://dev_env.gd")
const Party := preload("res://style/party_look.gd")
const SHADER := preload("res://style/surface.gdshader")
const DIR := "res" + "://assets/surfaces/"

## Texture sets: mean linear brightness of the albedo (the shader divides it out) and the size of one repeat in metres as photographed.
const SETS := {
	"tiles": {"mean": 0.636},
	"panels": {"mean": 0.357},
	"vinyl": {"mean": 0.662},
	"brushed": {"mean": 0.301},
	"plastic": {"mean": 0.828},
}

## Surface keys: floor (tops of ground), base (sides of ground), wall (blocks you bump into; wall_brand: painted in the team's colour,
## its tint set per level from TeamCast.brand_paint()), block (hop blocks), ice, mover (platforms
## that move, mover_top their tops), danger (moving things that hurt), trim (the square border around a cast picture on a hazard; the brand accent
## in real_look._trim_material), steel (bars, posts), and the room: room_wall, room_floor, ceiling.
## Fields: set, tint (the average colour), tile (metres per repeat), detail, rough, rough_add, metal, normal, seam, vtint, stripes, ao,
## spec; the party look adds pattern (1 checker, 2 vertical stripes, 3 bands, 4 dots), tint2 (its second colour), pattern_size (m), rim; the night look
## (style/night_look.gd) pattern 5 to 7 (glowing grid / lines in tint2 over a checker of tint and tint3), line (m), glow, emit. Block shapes: radius (edge rounding, m) and segments per surface key; band: the team colour's painted stripe (m over the floor);
## signage: frames, boards and posts of the team's prints; room: the painted room number; light: the sun, sky, haze and exposure.
const LOOK := {
	"surfaces": {
		"floor": {"set": "vinyl", "tint": "#2350c8", "tile": 2.0, "detail": 0.8, "rough": 1.0, "normal": 1.4, "seam": 2.0, "ao": 0.9},
		"base": {"set": "panels", "tint": "#cfd2d6", "tile": 4.0, "detail": 0.7, "ao": 0.7},
		"wall": {"set": "tiles", "tint": "#ecece8", "tile": 14.0, "detail": 0.8, "rough": 2.0, "ao": 0.9},
		"wall_brand": {"set": "tiles", "tint": "#ffffff", "tile": 14.0, "detail": 0.45, "rough": 1.7, "ao": 0.9},
		"block": {"set": "vinyl", "tint": "#ffffff", "tile": 1.5, "detail": 0.6, "rough": 1.5, "vtint": 1.0, "ao": 0.9},
		"ice": {"set": "plastic", "tint": "#bfe2f2", "tile": 3.0, "detail": 0.25, "rough": 0.25, "ao": 0.6, "spec": 0.7},
		"mover": {"set": "brushed", "tint": "#e9b824", "tile": 2.0, "detail": 0.5, "rough": 1.0, "stripes": 1.0, "ao": 0.0},
		"mover_top": {"set": "brushed", "tint": "#b9bdc3", "tile": 2.0, "detail": 1.0, "rough": 0.9, "metal": 1.0, "ao": 0.0},
		"danger": {"set": "brushed", "tint": "#d4432c", "tile": 2.0, "detail": 0.4, "rough": 1.0, "ao": 0.0},
		"trim": {"set": "plastic", "tint": "#e9ebee", "tile": 2.0, "detail": 0.15, "rough": 0.6, "ao": 0.0},
		"steel": {"set": "brushed", "tint": "#c4c8ce", "tile": 1.0, "detail": 1.0, "rough": 0.8, "metal": 1.0, "ao": 0.0},
		"room_wall": {"set": "tiles", "tint": "#e4e4e0", "tile": 16.0, "detail": 0.8, "rough": 2.0},
		"room_floor": {"set": "panels", "tint": "#7c828a", "tile": 6.0, "detail": 0.8},
		"ceiling": {"set": "panels", "tint": "#dcdedf", "tile": 6.0, "detail": 0.6},
	},
	"block_colors": ["#f2c230", "#ef7d2d", "#2fb7a5", "#e8584f", "#7b6fd6", "#f2f2f2"],
	"radius": {"floor": 0.03, "wall": 0.04, "block": 0.14, "ice": 0.03, "mover": 0.04, "danger": 0.05, "trim": 0.0},
	"segments": {"block": 3},
	"band": [1.0, 1.3],
	"signage": {"frame": "#c9ccd1", "frame_metal": 0.9, "frame_rough": 0.35, "board": "#eceeef", "post": "#b9bdc3", "post_metal": 0.8,
		"mat": "#f6f6f4", "text": "#1d2026"},
	"room": {"number": "#2f2f33"},
	"light": {"sun": "#fff4e6", "sun_energy": 1.0, "sun_dir": [-0.3, -0.88, -0.36], "shadow_blur": 1.5,
		"sky_top": "#dbe5f0", "sky_horizon": "#eaeef2", "ground": "#8a93a0", "ambient_energy": 0.5,
		"fog": "#d9e0e8", "fog_density": 0.004, "background": 1.0, "lamp": "#f4f8ff", "lamp_energy": 3.0,
		"tonemap": "agx", "contrast": 1.5, "white": 4.0, "exposure": 0.9},
}
static var _ink := -1
static var _textures := {}

## The comic ink look is in use instead (dev runs only: `--look=comic` after the `--`).
static func ink() -> bool:
	if _ink < 0: _ink = 1 if DevEnv.user_args().has("--look=comic") else 0
	return _ink == 1

## Tools: switch between the facility look and the comic one before anything is built.
static func set_ink(on: bool) -> void:
	_ink = 1 if on else 0

static func spec() -> Dictionary:
	return Party.spec() if Party.on() else LOOK

static func light() -> Dictionary:
	return spec().light

static func room() -> Dictionary:
	return spec().room

## Frames, boards and posts of the team's signs and posters (style/slot_frames.gd).
static func signage() -> Dictionary:
	return spec().signage

static func radius(key: String) -> float:
	return float(spec().radius.get(key, 0.03))

static func segments(key: String) -> int:
	return int(spec().segments.get(key, 1))

## The colour of hop block number `index` (a stable pick per block).
static func block_color(index: int) -> Color:
	var colors: Array = spec().block_colors
	return Color(colors[posmod(index, colors.size())])

static func _texture(set_name: String, map: String) -> Texture2D:
	var path := "%s%s/%s.jpg" % [DIR, set_name, map]
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path]

## A new material for surface `key` (a level gives it its height field afterwards).
static func material(key: String) -> ShaderMaterial:
	var s: Dictionary = spec().surfaces.get(key, spec().surfaces.wall)
	var set_name := str(s.set)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", _texture(set_name, "albedo"))
	m.set_shader_parameter("normal_tex", _texture(set_name, "normal"))
	m.set_shader_parameter("rough_tex", _texture(set_name, "rough"))
	m.set_shader_parameter("mean", float(SETS[set_name].mean))
	m.set_shader_parameter("tint", Color(str(s.tint)))
	m.set_shader_parameter("tile", float(s.get("tile", 2.0)))
	m.set_shader_parameter("detail", float(s.get("detail", 1.0)))
	m.set_shader_parameter("roughness", float(s.get("rough", 1.0)))
	m.set_shader_parameter("roughness_add", float(s.get("rough_add", 0.0)))
	m.set_shader_parameter("metallic", float(s.get("metal", 0.0)))
	m.set_shader_parameter("normal_depth", float(s.get("normal", 1.0)))
	m.set_shader_parameter("seam_every", float(s.get("seam", 0.0)))
	m.set_shader_parameter("vertex_tint", float(s.get("vtint", 0.0)))
	m.set_shader_parameter("stripes", float(s.get("stripes", 0.0)))
	m.set_shader_parameter("specular", float(s.get("spec", 0.5)))
	m.set_shader_parameter("ao", float(s.get("ao", 0.0)))
	m.set_shader_parameter("pattern", int(s.get("pattern", 0)))
	if s.has("tint2"): m.set_shader_parameter("tint2", Color(str(s.tint2)))
	m.set_shader_parameter("pattern_size", float(s.get("pattern_size", 1.0)))
	m.set_shader_parameter("rim", float(s.get("rim", 0.0)))
	if s.has("tint3"): m.set_shader_parameter("tint3", Color(str(s.tint3)))
	m.set_shader_parameter("line_width", float(s.get("line", 0.03)))
	m.set_shader_parameter("glow", float(s.get("glow", 0.0)))
	m.set_shader_parameter("emit", float(s.get("emit", 0.0)))
	return m

## A glowing material (skylights, windows, lamps): pure emission, bright enough to bloom.
static func lamp_material(energy_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var color := Color(str(light().lamp))
	m.albedo_color = Color.BLACK
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = float(light().lamp_energy) * energy_scale
	m.disable_receive_shadows = true
	return m

## Painted floor marking or a plain painted part (pads, flags, frames): one colour, a roughness.
static func paint(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
