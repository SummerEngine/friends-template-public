extends RefCounted
const DevEnv := preload("res://dev_env.gd")
## Shared look helpers: graphics quality, colour palette, the characters' materials and the ink materials the comic UI and the
## comic world look use. Pure look: no gameplay, physics or network code. The world look is in style/surfaces.gd; the player's choices
## are Quality and Palette (Settings > Display), saved in SETTINGS_FILE.
const SETTINGS_FILE := "user://settings.cfg"
static var _shaders: Dictionary = {}

# ------------------------------------------------------------------ graphics quality
## Player-facing Quality (Settings > Display): Low = no sun shadows, Medium = two shadow cascades over 60 m, High = the authored look
## (four cascades, the light's own distance). macOS defaults to High, Android to Low, other platforms to Medium.
const QUALITY_NAMES := ["Low", "Medium", "High"]
const QUALITY_MEDIUM_DISTANCE := 60.0
static var _quality := -1

static func quality_default() -> int:
	match OS.get_name():
		"macOS": return 2
		"Android": return 0
		_: return 1

static func quality() -> int:
	if _quality < 0:
		_quality = quality_default()
		var saved := ConfigFile.new()
		if saved.load(SETTINGS_FILE) == OK and saved.has_section_key("values", "Quality"):
			var index := QUALITY_NAMES.find(str(saved.get_value("values", "Quality")))
			if index >= 0: _quality = index
	return _quality

static func set_quality(level: int) -> void:
	_quality = clampi(level, 0, QUALITY_NAMES.size() - 1)
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null: return
	for light: Node in loop.get_nodes_in_group("friends_sun"):
		apply_quality(light as DirectionalLight3D)

## Called once for each sun after its environment is set up, and again by set_quality for the live suns.
static func apply_quality(light: DirectionalLight3D) -> void:
	if light == null or DisplayServer.get_name() == "headless": return
	if not light.is_in_group("friends_sun"):
		light.add_to_group("friends_sun")
		light.set_meta("quality_distance", light.directional_shadow_max_distance)
	var distance: float = light.get_meta("quality_distance")
	match quality():
		0:
			light.shadow_enabled = false
		1:
			light.shadow_enabled = true
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			light.directional_shadow_max_distance = minf(distance, QUALITY_MEDIUM_DISTANCE)
		_:
			light.shadow_enabled = true
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			light.directional_shadow_max_distance = distance

# ------------------------------------------------------------------ palette
## Player-facing Palette (Settings > Display): Vivid = the full comic inks (default), Calm = the same world with lower saturation and less
## competing hue; hazards and characters keep their accent. One shader global (`glass_calm`, style/calm_palette.gdshaderinc) switches every
## ink shader live, so no material is rebuilt. Order of precedence: `--glass-palette=calm|vivid` (after the `--` of the engine command line),
## FRIENDS_PALETTE (editor binary only), the saved setting, Vivid.
const PALETTE_NAMES := ["Vivid", "Calm"]
const CALM_GLOBAL := "glass_calm"
static var _palette := -1
static var _globals_ready := false

## Declares the shader globals once, before any shader that uses them is loaded.
static func ensure_globals() -> void:
	if _globals_ready: return
	_globals_ready = true
	RenderingServer.global_shader_parameter_add(CALM_GLOBAL, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0 if palette() == 1 else 0.0)

static func palette() -> int:
	if _palette < 0:
		_palette = 0
		var saved := ConfigFile.new()
		if saved.load(SETTINGS_FILE) == OK and saved.has_section_key("values", "Palette"):
			var saved_index := PALETTE_NAMES.find(str(saved.get_value("values", "Palette")))
			if saved_index >= 0: _palette = saved_index
		var chosen := DevEnv.read("FRIENDS_PALETTE")
		for arg in DevEnv.user_args():
			if arg.begins_with("--glass-palette="): chosen = arg.trim_prefix("--glass-palette=")
		var index := PALETTE_NAMES.find(chosen.capitalize())
		if index >= 0: _palette = index
	return _palette

static func calm() -> bool:
	return palette() == 1

static func set_palette(index: int) -> void:
	_palette = clampi(index, 0, PALETTE_NAMES.size() - 1)
	ensure_globals()
	RenderingServer.global_shader_parameter_set(CALM_GLOBAL, 1.0 if _palette == 1 else 0.0)

# ------------------------------------------------------------------ helpers
static func shader_material(path: String, params: Dictionary = {}) -> ShaderMaterial:
	ensure_globals()
	if not _shaders.has(path): _shaders[path] = load(path)
	var result := ShaderMaterial.new()
	result.shader = _shaders[path]
	for key in params: result.set_shader_parameter(key, params[key])
	return result

## `material` with an ink outline as its next pass; the facility look draws no outlines in the world, so it stays as it is there.
static func outlined(material: ShaderMaterial, ink: Color, width: float, boxy: bool, world_units := false) -> ShaderMaterial:
	if not preload("res://style/surfaces.gd").ink(): return material
	material.next_pass = shader_material("res://style/ink_outline.gdshader", {"ink_color": ink, "width": width, "boxy": boxy, "world_units": world_units})
	return material

# ------------------------------------------------------------------ characters
## The material of one part of a character (character/character_rig.gd, pet/ call it through has_method; they cache the result).
## kind: skin | shirt | pants | shoes | accent | eye | hat | hat_logo | hair | pet. A fresh material per call, or null for "the look
## has none": the facility look keeps the characters' own soft toy material (character/character_soft.gdshader: flat saturated colours,
## soft light); the comic look (dev runs) gets toon shading and an ink outline.
const CHARACTER_INK := Color("#1b1d3a")

static func character_material(kind: String, color: Color, texture: Texture2D = null) -> Material:
	if not preload("res://style/surfaces.gd").ink(): return null
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if texture != null:
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	if kind != "eye":
		material.next_pass = shader_material("res://style/ink_outline.gdshader", {"ink_color": CHARACTER_INK, "width": 0.022, "boxy": false})
	return material
