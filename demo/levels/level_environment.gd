extends RefCounted
## The light of the levels in the facility look (style/surfaces.gd `light`; the party look's open air sets `sky_background`, so its sky is
## seen and the haze is the horizon's colour): one sun with soft shadows coming in through the room's
## openings, ambient light and reflections from a soft sky (bright from above, the floor's colour from below), light haze that fades
## the far walls, ACES or AgX tone mapping and a soft glow on what shines (skylights, windows). All of it runs on the Compatibility renderer.
## The comic look (dev runs) has its ink sky, paper-cream ambient and fog (build_ink). Clients only; the authority has no environment.
## The stage rounds (levels with a `stage` section) and the levels with `"world": "daylight"` (style/race_world.gd) have the fixed daylight of style/candy_light.gd (sun, fill, violet ambient, sky, grade): `set_stage` swaps it into the one environment and sun and back out again.
const Style := preload("res://style/friends_style.gd")
const Surfaces := preload("res://style/surfaces.gd")
const Ink := preload("res://style/style_ink.gd")
const INK_SKY := preload("res://style/ink_sky.gdshader")
const NIGHT_SKY := preload("res://style/night_sky.gdshader")
const CandyLight := preload("res://style/candy_light.gd")
const CandyLook := preload("res://style/candy_look.gd")
const SHADOW_DISTANCE := 90.0
const TONEMAPPERS := {"agx": Environment.TONE_MAPPER_AGX, "aces": Environment.TONE_MAPPER_ACES, "filmic": Environment.TONE_MAPPER_FILMIC, "linear": Environment.TONE_MAPPER_LINEAR}
## The look is set for the web renderer (Mobile on WebGPU; Mobile on macOS). The Compatibility renderer (the phone apps, Windows and
## Linux) draws the same scene brighter and paler, so it gets a little less exposure and ambient light (measured on the picker room).
const COMPAT_EXPOSURE := 0.9
const COMPAT_AMBIENT := 0.7

static func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

## Exposure factor of the renderer in use.
static func renderer_exposure() -> float:
	return COMPAT_EXPOSURE if _compat() else 1.0

## What `set_stage` puts back of the sun: the properties the stage light overrides.
const SUN_KEYS := ["light_color", "light_energy", "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur", "directional_shadow_max_distance", "directional_shadow_blend_splits",
	"directional_shadow_mode", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "light_angular_distance", "sky_mode"]

## Adds `WorldEnvironment` and `LevelSun` to `parent` and returns {environment, sun, holder, sun_state}: `environment` and the sun's usual state are what `set_stage` swaps back.
static func build(parent: Node) -> Dictionary:
	if Surfaces.ink(): return build_ink(parent)
	var light := Surfaces.light()
	var environment := make_environment(light)
	var holder := WorldEnvironment.new()
	holder.name = "LevelEnvironment"
	holder.environment = environment
	parent.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "LevelSun"
	sun.light_color = Color(str(light.sun))
	sun.light_energy = float(light.sun_energy)
	sun.shadow_enabled = true
	sun.shadow_blur = float(light.shadow_blur)
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = SHADOW_DISTANCE
	sun.directional_shadow_blend_splits = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # no sun disc in the sky: the sky is only the soft ambient of the room
	parent.add_child(sun)
	var direction: Array = light.sun_dir
	sun.global_basis = Basis.looking_at(Vector3(direction[0], direction[1], direction[2]).normalized(), Vector3.UP)
	Style.apply_quality(sun)
	return {"environment": environment, "sun": sun, "holder": holder, "sun_state": _sun_state(sun)}

## The daylight (style/candy_light.gd: a stage round, or a level with `world: daylight`) or the level's usual light again: `handles` is what `build` returned (kept by the level world, which flips it as the active level
## changes). The daylight's environment and its fill light (not on a phone) are made the first time; the fill light stays in the tree and is only shown while the daylight is on. Does nothing for a world without an environment (the authority) or when the light already is as asked.
static func set_stage(handles: Dictionary, stage: bool) -> void:
	var holder := handles.get("holder") as WorldEnvironment
	var sun := handles.get("sun") as DirectionalLight3D
	if holder == null or sun == null or bool(handles.get("stage", false)) == stage: return
	handles["stage"] = stage
	if stage:
		if not handles.has("stage_environment"):
			var scale := CandyLight.world_scale()
			handles["stage_environment"] = CandyLight.environment(scale)
			if CandyLight.has_fill(scale):
				var fill := CandyLight.make_fill()
				sun.get_parent().add_child(fill)
				fill.global_basis = Basis.looking_at(-CandyLook.towards(CandyLook.FILL_ELEVATION, CandyLook.FILL_AZIMUTH), Vector3.UP)
				handles["stage_fill"] = fill
		holder.environment = handles.stage_environment
		CandyLight.apply_sun(sun)
		var day_fill := handles.get("stage_fill") as DirectionalLight3D
		if day_fill != null: day_fill.visible = true
		return
	var night_fill := handles.get("stage_fill") as DirectionalLight3D
	if night_fill != null: night_fill.visible = false
	holder.environment = handles.environment
	var state: Dictionary = handles.sun_state
	for key: String in state.properties: sun.set(key, state.properties[key])
	sun.global_basis = state.basis
	if sun.has_meta("quality_distance"): sun.set_meta("quality_distance", state.distance)
	Style.apply_quality(sun)

static func _sun_state(sun: DirectionalLight3D) -> Dictionary:
	var properties := {}
	for key: String in SUN_KEYS: properties[key] = sun.get(key)
	var distance: float = sun.get_meta("quality_distance") if sun.has_meta("quality_distance") else sun.directional_shadow_max_distance
	return {"properties": properties, "basis": sun.global_basis, "distance": distance}

## The environment of a look: a soft sky for ambient light and reflections, the haze colour as background, haze, tone mapping, glow.
static func make_environment(light: Dictionary) -> Environment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(str(light.sky_top))
	sky_material.sky_horizon_color = Color(str(light.sky_horizon))
	sky_material.ground_bottom_color = Color(str(light.ground))
	sky_material.ground_horizon_color = Color(str(light.sky_horizon)).lerp(Color(str(light.ground)), 0.5)
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	if bool(light.get("night", false)): sky.sky_material = _night_sky(light) # the night look: a dark sky with stars, a metal sun and a planet
	var environment := Environment.new()
	environment.sky = sky
	if bool(light.get("sky_background", false)):
		environment.background_mode = Environment.BG_SKY # the party look's open air: the sky is seen
		sky_material.sky_curve = 0.25
		sky_material.ground_curve = 0.1
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(str(light.fog))
	environment.background_energy_multiplier = float(light.get("background", 1.0))
	environment.ambient_light_source = 3 # ambient light from the sky
	environment.ambient_light_energy = float(light.ambient_energy) * (COMPAT_AMBIENT if _compat() else 1.0)
	environment.ambient_light_sky_contribution = 1.0
	if light.has("ambient_color"): # the night look: one flat ambient colour (a dark sky gives none), reflections still come from the sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(str(light.ambient_color))
	environment.reflected_light_source = 2 # reflections of the sky
	environment.tonemap_mode = TONEMAPPERS.get(str(light.get("tonemap", "agx")), Environment.TONE_MAPPER_AGX)
	environment.tonemap_white = float(light.get("white", 6.0))
	environment.tonemap_agx_white = float(light.get("white", 6.0))
	environment.tonemap_exposure = float(light.exposure) * renderer_exposure()
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(str(light.fog))
	environment.fog_density = float(light.fog_density)
	environment.fog_sky_affect = 0.0
	environment.tonemap_agx_contrast = float(light.get("contrast", 1.5))
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	return environment

## The sky shader of the night look from its `light` (style/night_sky.gdshader): the palette's void and horizon as the gradient, the accent as the glow.
static func _night_sky(light: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = NIGHT_SKY
	material.set_shader_parameter("zenith", Color(str(light.sky_top)))
	material.set_shader_parameter("horizon", Color(str(light.sky_horizon)))
	material.set_shader_parameter("below", Color(str(light.ground)))
	material.set_shader_parameter("glow_color", Color(str(light.glow_color)))
	material.set_shader_parameter("disc_core", Color(str(light.disc_core)))
	var disc: Array = light.disc_dir
	material.set_shader_parameter("disc_dir", Vector3(disc[0], disc[1], disc[2]))
	var planet: Array = light.planet_dir
	material.set_shader_parameter("planet_dir", Vector3(planet[0], planet[1], planet[2]))
	return material

## The comic setting (dev runs): the ink sky (halftone gradient, inked clouds), paper-cream ambient light, light paper fog and one warm sun.
static func build_ink(parent: Node) -> Dictionary:
	var environment := Environment.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = INK_SKY
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff4dc")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Ink.PAPER
	environment.fog_density = 0.0045
	environment.fog_sky_affect = 0.0
	var holder := WorldEnvironment.new()
	holder.name = "LevelEnvironment"
	holder.environment = environment
	parent.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "LevelSun"
	sun.light_color = Color("#fffaf0")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0   # hard (0) shadows alias: the halftone flips as the camera moves; a 1-texel soft edge is stable
	sun.directional_shadow_max_distance = 120.0
	parent.add_child(sun)
	sun.global_basis = Basis.looking_at(Vector3(-0.5, -0.75, -0.35).normalized(), Vector3.UP)
	Style.apply_quality(sun)
	return {"environment": environment, "sun": sun, "holder": holder, "sun_state": _sun_state(sun)}
