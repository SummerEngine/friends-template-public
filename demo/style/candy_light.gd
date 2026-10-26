extends RefCounted
## The light of every daylight scene of the show (the stage rounds, the daylight races, the lobby yard, the podium room, the title and results stage); the numbers are all in style/candy_look.gd.
## The picture is physically based and plain: ONE warm sun (#FFE9C4 x0.9, 61 degrees up, soft shadows over 60 m in two cascades), ONE cool fill (#D9F9FF x0.6, 49 degrees up, azimuth 74,
## no shadow) and a violet and blue ambient gradient from a static sky (style/candy_sky.gdshader: its radiance pass returns the ambient gradient, its picture is the blue-to-cyan sky), linear
## tone mapping at exposure 1/1.3 and the saturating grade of `CandyLook.GRADE` as the colour correction: scene-linear light 1.3 is white, the toe is crushed, shadows go violet and blue.
## No fog here (the exp2 fog of the world is inside the backdrop shaders, style/candy_fog.gdshaderinc), no glow, no SSAO, no SSR, no outline.
## `environment` / `apply_sun` / `make_fill` / `rig`: the parts and the whole. A phone (`CandyLook`'s world scale below 1: Android or Quality Low) has no fill light, the fill is folded into the
## ambient gradient (set-up B). Mobile and Compatibility are brought to the same picture: COMPAT_SUN, COMPAT_FILL and COMPAT_AMBIENT multiply the lights and the ambient on Compatibility.
## `tools/candy_light_check.gd` measures all of it (white plane, grey ramp, lit and shadow anchors, sky) on both renderers.
const CandyLook := preload("res://style/candy_look.gd")
const Style := preload("res://style/friends_style.gd")
const SKY := preload("res://style/candy_sky.gdshader")
const FACETS := preload("res://style/candy_sky_facets.gdshader")

static var _grade: ImageTexture

static func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"

## The world scale of this device: 0.25 on a phone (Android or Quality Low), else 1. `CandyWorld.build` takes it as its `world_scale`; `environment` and `rig` take it to pick the ambient set-up.
static func world_scale() -> float:
	return 0.25 if OS.get_name() == "Android" or Style.quality() == 0 else 1.0

## Whether the fill is a light of its own (it is folded into the ambient on a phone).
static func has_fill(scale := 1.0) -> bool:
	return scale >= 1.0

## Whether sun shadows are on (Quality Medium and High).
static func shadows_on() -> bool:
	return Style.quality() > 0

## What Compatibility needs on top of the numbers of `CandyLook`: {sun, fill, ambient (Color)} factors (all 1 on Mobile and without shadows), for the set-up with (`fill`) or without the fill light.
static func rig_factors(fill: bool) -> Dictionary:
	if not _compat() or not shadows_on(): return {"sun": 1.0, "fill": 1.0, "ambient": Color.WHITE}
	return CandyLook.COMPAT_SHADOWED_A if fill else CandyLook.COMPAT_SHADOWED_B

## The sun's energy on this renderer and tier (`scale` the world scale, default this device's).
static func sun_energy(scale := -1.0) -> float:
	return CandyLook.SUN_ENERGY * float(rig_factors(has_fill(world_scale() if scale < 0.0 else scale)).sun)

## A new Environment: the static sky as the visible background and the ambient light, linear tone mapping at `CandyLook.TONE_EXPOSURE`, the grade as the colour correction. No fog, glow, SSAO, SSR.
static func environment(scale := 1.0) -> Environment:
	var fill := has_fill(scale)
	var ambient_scale: Color = rig_factors(fill).ambient
	var material := ShaderMaterial.new()
	material.shader = SKY
	var high := _sky_light(CandyLook.SKY_HIGH)
	var mid := _sky_light(CandyLook.SKY_MID)
	var low := _sky_light(CandyLook.SKY_LOW)
	material.set_shader_parameter("high_colour", Vector3(high.r, high.g, high.b))
	material.set_shader_parameter("mid_colour", Vector3(mid.r, mid.g, mid.b))
	material.set_shader_parameter("low_colour", Vector3(low.r, low.g, low.b))
	material.set_shader_parameter("mid_at", CandyLook.SKY_MID_AT)
	material.set_shader_parameter("high_at", CandyLook.SKY_HIGH_AT)
	material.set_shader_parameter("reflect_gain", CandyLook.SKY_REFLECT_GAIN)
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY # the sky never changes: the radiance map (ambient light) is made once, not refreshed over frames
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var ambient := CandyLook.ambient_flat(fill)
	env.ambient_light_color = Color(ambient.r * ambient_scale.r, ambient.g * ambient_scale.g, ambient.b * ambient_scale.b).linear_to_srgb() # the property takes sRGB
	env.ambient_light_energy = 1.0
	env.reflected_light_source = 2 # reflections of the sky (its radiance map: candy_sky.gdshader)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = CandyLook.TONE_EXPOSURE
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0 if _compat() else CandyLook.GRADE_SATURATION # Compatibility already draws the pastels more saturated (measured: mean S .656 against .565)
	env.adjustment_color_correction = grade_texture()
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	return env

## The light a sky shader has to return so that the picture shows `screen` (Compatibility does not encode a sky's colour: see `CandyLook.COMPAT_SKY_GAIN`).
static func _sky_light(screen: Color) -> Color:
	if not _compat(): return CandyLook.scene_linear(screen)
	var gain := CandyLook.COMPAT_SKY_GAIN
	return Color(CandyLook.grade_inverse(screen.r) / gain, CandyLook.grade_inverse(screen.g) / gain, CandyLook.grade_inverse(screen.b) / gain)

## The grade as the 256 x 1 lookup `adjustment_color_correction` takes (made once).
static func grade_texture() -> ImageTexture:
	if _grade == null: _grade = ImageTexture.create_from_image(CandyLook.grade_image())
	return _grade

## Sets `sun` (a DirectionalLight3D in the tree) to the show's sun: #FFE9C4 x0.9 at 61 degrees up, from `azimuth` (degrees, see `CandyLook.towards`), soft shadows over 60 m, two cascades.
static func apply_sun(sun: DirectionalLight3D, azimuth := CandyLook.SUN_AZIMUTH, scale := -1.0) -> void:
	sun.light_color = CandyLook.SUN_COLOR
	sun.light_energy = sun_energy(scale)
	sun.shadow_enabled = true
	sun.shadow_bias = CandyLook.SHADOW_BIAS
	sun.shadow_normal_bias = CandyLook.SHADOW_NORMAL_BIAS
	sun.shadow_blur = CandyLook.SHADOW_BLUR
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = CandyLook.SHADOW_DISTANCE
	sun.directional_shadow_split_1 = 0.31
	sun.light_angular_distance = 0.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.global_basis = Basis.looking_at(-CandyLook.towards(CandyLook.SUN_ELEVATION, azimuth), Vector3.UP)
	if sun.has_meta("quality_distance"): sun.set_meta("quality_distance", CandyLook.SHADOW_DISTANCE)
	Style.apply_quality(sun)

## The cool fill: a second directional light without shadows. Not yet in the tree (add it, its direction is world space).
static func make_fill() -> DirectionalLight3D:
	var fill := DirectionalLight3D.new()
	fill.name = "CandyFill"
	fill.light_color = CandyLook.FILL_COLOR
	fill.light_energy = CandyLook.FILL_ENERGY * rig_factors(true).fill
	fill.shadow_enabled = false
	fill.light_angular_distance = 0.0
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.basis = Basis.looking_at(-CandyLook.towards(CandyLook.FILL_ELEVATION, CandyLook.FILL_AZIMUTH), Vector3.UP)
	return fill

## The whole rig under `parent`: a WorldEnvironment, the sun (apply_sun at `azimuth`) and, unless the device is a phone (`scale` below 1), the fill. Returns {environment, holder, sun, fill (null on a phone)}.
static func rig(parent: Node, azimuth := CandyLook.SUN_AZIMUTH, scale := 1.0) -> Dictionary:
	var env := environment(scale)
	var holder := WorldEnvironment.new()
	holder.name = "CandyEnvironment"
	holder.environment = env
	parent.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.name = "CandySun"
	parent.add_child(sun)
	apply_sun(sun, azimuth, scale)
	var fill: DirectionalLight3D = null
	if has_fill(scale):
		fill = make_fill()
		parent.add_child(fill)
		fill.global_basis = Basis.looking_at(-CandyLook.towards(CandyLook.FILL_ELEVATION, CandyLook.FILL_AZIMUTH), Vector3.UP)
	return {"environment": env, "holder": holder, "sun": sun, "fill": fill}

## The faint triangle facets of the sky as a node (`candy_sky_facets.gdshader`: a fullscreen quad at the far plane, additive, camera-independent, one per world): they are strongest in a cone round
## the camera's axis, which an Environment sky shader cannot know. `CandyWorld.build` adds it. Null on a phone (world scale below 1: the facets are a luxury).
static func sky_node(scale := -1.0) -> Node3D:
	if (world_scale() if scale < 0.0 else scale) < 1.0: return null
	var material := ShaderMaterial.new()
	material.shader = FACETS
	material.set_shader_parameter("gain", CandyLook.SKY_FACET_GAIN * (CandyLook.COMPAT_FACET_GAIN if _compat() else 1.0))
	material.set_shader_parameter("cone_power", CandyLook.SKY_FACET_CONE)
	material.set_shader_parameter("cells", CandyLook.SKY_FACET_CELLS)
	material.set_shader_parameter("line_gain", CandyLook.SKY_FACET_LINE_GAIN)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var node := MeshInstance3D.new()
	node.name = "SkyFacets"
	node.mesh = quad
	node.material_override = material
	node.extra_cull_margin = 16384.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
