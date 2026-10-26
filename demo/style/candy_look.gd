extends RefCounted
## The numbers of the show's daylight look, ONE place (pure data, no nodes): sun, fill, ambient, grade, fog, sky, the material families and the colours of the world around the
## course. Every look file of the daylight look reads them from here, none keeps its own copy: `style/candy_light.gd` (environment, sun, fill, sky, grade), `style/candy_world.gd`
## (the background diorama), the course surfaces (`style/candy_surface.gdshader` and the block, pad, tile looks).
## The look is physically based and plain, not toon: glossy plastic and vinyl under one warm sun, a cool fill and a violet and blue ambient, flat saturated authored colours, smooth
## chamfered or pillow geometry, a saturating per-channel tone curve. No outlines, no toon ramp, no wrap light, no dim desaturated background: the world around the course is as bright and
## as saturated as the course. Colours are sRGB hex as authored (a Godot `source_color` or `Color("#...")` takes them as they are); `*_LIN` are linear light.

# ------------------------------------------------------------------ light
const SUN_COLOR := Color("#ffe9c4")
const SUN_ENERGY := 1.05
const SUN_ELEVATION := 61.0                 ## degrees over the horizon (a raking sun: a shadow is about 0.55 of its object's height)
const SUN_AZIMUTH := 300.0                  ## degrees, the default azimuth: the light comes FROM the far left of a camera that looks along +Z (the show's courses run towards +Z): shadows fall towards the camera and to the right. Direction is (sin az, ., cos az)
const FILL_COLOR := Color("#d9f9ff")        ## the cool fill: a second directional light without shadows (or folded into the ambient on the weakest tier)
const FILL_ENERGY := 0.6
const FILL_ELEVATION := 49.0
const FILL_AZIMUTH := 74.0
## The ambient gradient in LINEAR light. Set-up A (with the fill light): up, horizon, down. Set-up B (no fill light, phones): the fill folded in. The Environment's own ambient is ONE flat colour (`ambient_flat`: what an
## up-facing surface gets, which the lit floors and tops are judged by; a flat colour keeps the sky's radiance free for bright reflections and is exact on Compatibility); the gradient itself is what the backdrop shaders light themselves with.
const AMBIENT_A_UP := Color(0.22, 0.025, 0.42)
const AMBIENT_A_SIDE := Color(0.28, 0.07, 0.62)
const AMBIENT_A_DOWN := Color(0.004, 0.12, 1.0)
const AMBIENT_B_UP := Color(0.57, 0.46, 0.97)
const AMBIENT_B_SIDE := Color(0.44, 0.27, 0.86)
const AMBIENT_B_DOWN := Color(0.05, 0.20, 1.0)
## Shadows: soft, 60 m, two cascades.
const SHADOW_DISTANCE := 60.0
const SHADOW_BLUR := 0.8
const SHADOW_BIAS := 0.05
const SHADOW_NORMAL_BIAS := 0.8
## The Compatibility renderer corrections, applied AFTER the values above so it draws what Mobile draws (fitted with `tools/candy_light_check.gd`'s floors: lit and shadowed white, blue, orange, grey, purple). Without sun shadows
## (Quality Low) it is linear and exact: all factors 1. With sun shadows a directional light that casts them adds to the ambient and to the other lights in a non-linear way (a shadowed sun of 0.3 over an ambient of 0.2 reads 1.0,
## not 0.47), so the sun is scaled down hard (fill and ambient stay about 1): {sun, fill, ambient} per ambient set-up (A with the fill light, B folded into the ambient).
const COMPAT_SHADOWED_A := {"sun": 0.156, "fill": 1.0, "ambient": Color(0.99, 1.23, 0.96)}
const COMPAT_SHADOWED_B := {"sun": 0.171, "fill": 1.0, "ambient": Color(1.0, 1.03, 0.98)}
## Compatibility draws a sky shader's COLOR without the sRGB encoding and with exposure about 0.89 (measured: a sky value v shows as `grade(0.89 v)`), so a sky colour is given as `grade_inverse(screen) / COMPAT_SKY_GAIN`.
const COMPAT_SKY_GAIN := 0.89

# ------------------------------------------------------------------ grade (tone curve)
## 33 samples of sRGB in [0, 1] -> sRGB out, for `Environment.adjustment_color_correction`: built as enc(curve(1.3 * dec(s))), so it pairs with `tonemap_mode` LINEAR and
## `tonemap_exposure` TONE_EXPOSURE (scene linear 1.3 lands on 1.0). The curve crushes the toe, keeps the mids a little darker (the curve to the power 1.06) and clips HIGHER than a smooth shoulder
## (the shoulder of a smooth curve, 0.95 to 0.99 at inputs 0.84 to 0.97, is cut: from display 0.875 up, scene linear about 0.95, everything is 1.0 and a pastel's top channel clips), so lit tops, the lime meadow
## and the pink slime reach V 1.0 (about 40 % of a full frame) while the saturating toe keeps the other channels low.
const TONE_EXPOSURE := 1.0 / 1.3
const GRADE_SATURATION := 1.16              ## `Environment.adjustment_saturation`, applied BEFORE the grade: pastel organic colours (meadow, slime, mountains) keep their chroma where the shoulder clips their top channels (Mobile only: Compatibility draws them more saturated, see candy_light.gd)
const GRADE := [0.0000, 0.0000, 0.0037, 0.0201, 0.0530, 0.0863, 0.1196, 0.1545, 0.1894, 0.2237, 0.2598,
	0.2962, 0.3311, 0.3707, 0.4057, 0.4472, 0.4831, 0.5256, 0.5645, 0.6053, 0.6478, 0.6855,
	0.7306, 0.7735, 0.8120, 0.8600, 0.9150, 0.9450, 0.9650, 0.9850, 1.0000, 1.0000, 1.0000]
## The variant for a renderer that clamps at 1.0 before the curve (exposure 1.0); its last sample is forced to 1.0 so a lit white clips.
const GRADE_EXPOSURE_1 := [0.0, 0.0, 0.0005, 0.0121, 0.0397, 0.0737, 0.1057, 0.1380, 0.1713, 0.2036, 0.2354, 0.2693, 0.3002, 0.3347, 0.3669, 0.4018, 0.4337, 0.4702, 0.5019, 0.5390,
	0.5739, 0.6068, 0.6455, 0.6803, 0.7137, 0.7535, 0.7897, 0.8224, 0.8625, 0.9013, 0.9369, 0.9680, 1.0]

# ------------------------------------------------------------------ fog (exp2, done in the backdrop shaders, `style/candy_fog.gdshaderinc`)
const FOG_COLOR := Color("#83ddff")
const FOG_DENSITY := 0.0005                 ## f = exp(-(density * z)^2) with z the view depth in metres; the sky is not fogged
const FOG_COLOR_LIN := Color(0.227, 0.723, 1.0)

# ------------------------------------------------------------------ sky
## The visible sky (`style/candy_sky.gdshader`): a gradient from a deep zenith to a cyan horizon with faint LIGHTER triangle facets round the middle of the view. The target dome runs
## #0059FF -> #00BBCC with t = (1 - sin elevation)^5; what lands on screen after the grade is the three SCREEN colours below (the facet-free blue: #14A0F8 up high, #1AB4F5 in the middle,
## #2EDDE8 at the lowest sky pixel; the facets lift R and G to #30ABF6 .. #5CC5F7 in the lighter triangles); `scene_linear` turns them into the light the shader has to give so that the grade brings them back.
const SKY_HIGH := Color("#2ca2f7")          ## screen colour of the sky from `SKY_HIGH_AT` degrees up to the zenith
const SKY_MID := Color("#30b2f6")           ## ... at `SKY_MID_AT` degrees
const SKY_LOW := Color("#2edde8")           ## ... at the horizon (smooth steps between the three)
const SKY_REFLECT_GAIN := 0.35              ## the sky as the reflections see it (the radiance map), times the picture's colours: bright enough to give glossy plastic a broad sheen
const SKY_MID_AT := 15.0
const SKY_HIGH_AT := 40.0
const SKY_FACET_GAIN := 0.8                 ## the facet term `0.1 * (1 + m) * (1 + m)` (+0.17 .. +0.40 linear in every channel) times this, times the cone
const COMPAT_FACET_GAIN := 0.85             ## Compatibility draws the tonal facets stronger than Mobile (measured on 03: the lightest triangles glow white): multiply the gain
const SKY_FACET_LINE_GAIN := 0.05           ## the white edge lines of the triangles, added (linear) in the cone, times the triangle's level
const SKY_FACET_CONE := 14.0                ## cos^power round the camera axis (0.5 at 19 degrees, 0.17 at the top edge of a 60 degree frame)
const SKY_FACET_CELLS := Vector2(80.0, 40.0) ## triangle columns over the azimuth turn and rows over sin(elevation) * 0.5 + 0.5 (4.5 degrees a triangle)

# ------------------------------------------------------------------ material families (roughness = 1 - smoothness)
const ROUGH_PLASTIC := 0.11                 ## hard plastic: posts, doors, obstacle bodies
const ROUGH_VINYL := 0.45                   ## inflatables, walls, bumpers, pillows (0.32 to 0.65 across the family)
const ROUGH_VINYL_GLOSSY := 0.3             ## the striped pillow bars and cubes of the hazards: the glossy end of the vinyl range
const ROUGH_TILE := 0.55                    ## hexagon floor tiles
const ROUGH_FELT := 1.0
const ROUGH_METAL := 0.38
const ROUGH_SLIME := 0.05
const ROUGH_FOLIAGE := 1.0
const ROUGH_MOUNTAIN := 0.75
const HEX_SELF_LIGHT := 0.3                 ## a hexagon tile adds 30 % of its own albedo as emission ...
const HEX_RIM_COLOR := Color("#ff80ff")     ## ... plus a pink rim, additive, pow(1 - N.V, HEX_RIM_POWER)
const HEX_RIM_POWER := 4.0
const CHAMFER_DOOR := 0.09                  ## m of chamfer on a door-sized hard piece
const CHAMFER_SLAB := 0.25                  ## m on a 0.5 m floor slab (half its thickness)
const PILLOW_NORMAL_DEG := 14.0             ## vertex normals of an inflatable lean this far off the face normal

# ------------------------------------------------------------------ the course palette (2-3 hues + near white + a few dark accents)
const HARD_PLASTIC := {"salmon": Color("#c32258"), "purple": Color("#8b187d"), "blue": Color("#1554d6"), "mid_blue": Color("#0069dc"), "light_purple": Color("#783ec5"), "turquoise": Color("#59e4e4"), "white": Color("#e7f4c2")}
const VINYL := {"amber": Color("#ffb308"), "indigo": Color("#0d11b5"), "blue": Color("#005dff"), "azure": Color("#006fff"), "pink_red": Color("#b00047"), "magenta": Color("#f40b6f"), "felt": Color("#1e1461")}
const TILES := {"b1": Color("#13acd6"), "b2": Color("#058ee0"), "b3": Color("#0066ff"), "y1": Color("#e09300"), "y2": Color("#ff7100"), "y3": Color("#ffad00"), "p2": Color("#610c82"), "p3": Color("#560a78")}
## The tile rounds' colour families: a floor wears ONE family, each tile one of its three shades (blue, yellow-orange, purple: the course palette's 2-3 hues). The purple is the measured dark purple, the magenta of the hex tiles (#B02DA2) and a lighter purple.
const TILE_FAMILIES := {"blue": [Color("#1188ec"), Color("#1696f0"), Color("#2aa0f0")], "cyan": [Color("#55ccee"), Color("#66d6f0"), Color("#7adef2")], "yellow": [Color("#f07a0a"), Color("#ff9a10"), Color("#ffa81a")], "purple": [Color("#b02da2"), Color("#a82aa0"), Color("#b83aae")]}
const TILE_PADS_SQUARE := [Color("#1c96f0"), Color("#1e9bf2"), Color("#2aa4f4")] ## the square rounds' start pads: a saturated mid blue over the deeper blue mats (the whole arena is blue; the orange is the rail)
const TILE_MATS_SQUARE := [Color("#0a4cd0"), Color("#1056d8"), Color("#1a62e0")] ## the square rounds' blue mats under the start layer: a deeper blue than the pads (lit, the mats land near a #2BA8F5 field, the pads stand out of it)
const TILE_WARN_LIFT := 0.75                ## a warned tile: its own colour lifted this far towards white (a pale lemon, a pale cyan), nothing else about it changes
const TILE_GLYPH := 0.05                    ## how far the faint near-white macro glyph on a tile's top lifts its colour towards white
const TILE_SQUARE_RIM_COLOR := Color("#12689c") ## square tiles: the cool dark rim of the tip-toe tile, power 6 (no self light)
const TILE_SQUARE_RIM_POWER := 6.0
const COURSE_HUES := {"blue": [Color("#1aa8f4"), Color("#1064e1"), Color("#3dd1f4")], "pink": [Color("#d41791"), Color("#b02da2"), Color("#e299ec")], "purple": [Color("#ae4ee1"), Color("#6130b0"), Color("#8e4cd9")],
	"orange": [Color("#e06418"), Color("#ef860f"), Color("#e9a538"), Color("#efaa2b")], "lime": [Color("#e4fd97"), Color("#cffa65"), Color("#72fdae")], "white": [Color("#f8f4f3"), Color("#f0e1f7")],
	"dark": [Color("#473255"), Color("#32315d"), Color("#35353e")]}
const RAIL_ORANGE := Color("#ef860f")       ## the inflatable rail ring at a platform's rim

# ------------------------------------------------------------------ the course props of a race (hazards, movers, gates, start and goal; style/spinner_look.gd and friends)
## A race level is 2-3 hues + white: the floor's blue, the obstacles hot pink with white stripes, amber accents, and a purple for structure (gate frames, the start and goal signs).
## Hard plastic (posts, hubs, frames, signs) is ROUGH_PLASTIC, inflatable-like bars and soft pieces ROUGH_VINYL; stripes and chevrons are flat white masks over the tint.
const PROP_PINK := Color("#d41791")
const PROP_PINK_DEEP := Color("#bd1480")
const PROP_PINK_LIGHT := Color("#f45cb8")
const PROP_AMBER := Color("#efaa2b")
const PROP_AMBER_DEEP := Color("#e06418")
const PROP_AMBER_LIGHT := Color("#f7c95e")
const PROP_PURPLE := Color("#8e4cd9")
const PROP_PURPLE_DEEP := Color("#6130b0")
const PROP_PURPLE_LIGHT := Color("#ae4ee1")
const PROP_BLUE := Color("#1064e1")
const PROP_WHITE := Color("#f8f4f3")
const STRIPE_PERIOD := 0.7                  ## m: one diagonal white stripe plus its gap on an inflatable bar (half each)

# ------------------------------------------------------------------ the world around the course (a static pastel diorama; sizes are the full scale, `world_scale` shrinks them)
const CLOUD_WALL := Color("#dcf8fd")        ## unlit, fogged: a pale cyan band 3-6 degrees over the horizon
const CLOUD_WALL_RADIUS := 2600.0
const CLOUD_FAKE_FOG := Color("#7aa6e5")
const TERRAIN_LIME := Color("#a1e531")
const TERRAIN_TINTS := [Color("#e5dfcc"), Color("#dbc7c7")]
const TERRAIN_EDGE := Color("#ffa000")
const TERRAIN_HOLE_RADIUS := 196.0
const TERRAIN_PLATEAU_RADIUS := 800.0
const FOLIAGE := {"lime": [Color("#b2df6a"), Color("#daef8d")], "pink": Color("#f18ec3"), "blue": Color("#5aa9ff"), "green": Color("#4ec35a")}  ## 55 % green / 22 % red-pink / 21 % blue
const MOUNTAIN_BROAD := [Color("#8ad230"), Color("#e9d3d2"), Color("#fad4db"), Color("#faf5f5"), Color("#faf7f7")]  ## bottom to top
const MOUNTAIN_SKINNY := [Color("#a0d380"), Color("#ff83a5"), Color("#ff81a5"), Color("#f9dfe2"), Color("#faf9f9")]
const SLIME := Color("#fa9fcc")
const SLIME_LIGHT := Color("#ffb6da")
const SLIME_DEEP := Color("#db5a9a")
const SLIME_EDGE := Color("#ff39b3")

# ------------------------------------------------------------------ helpers
## The direction the light comes FROM (a unit vector, world, y up) for a sun at `elevation` degrees over the horizon and `azimuth` degrees (compass-like: (sin az, ., cos az)).
static func towards(elevation: float, azimuth: float) -> Vector3:
	var e := deg_to_rad(elevation)
	var a := deg_to_rad(azimuth)
	return Vector3(sin(a) * cos(e), sin(e), cos(a) * cos(e))

## `1 / world_scale` times the fog density keeps the look of a backdrop built at `world_scale` of the full size (exp2 fog is scale covariant).
static func fog_density(world_scale := 1.0) -> float:
	return FOG_DENSITY / maxf(world_scale, 0.01)

## The 33-sample grade as a 256 x 1 image (same value in R, G, B), the shape `adjustment_color_correction` takes as a 1D lookup. A texel holds the grade at its CENTRE: the lookup samples at the
## input value with linear filtering, so the table is exact up to its own resolution.
static func grade_image(exposure_one := false) -> Image:
	var image := Image.create(256, 1, false, Image.FORMAT_RGB8)
	for x in 256:
		var v := grade_value((float(x) + 0.5) / 256.0, exposure_one)
		image.set_pixel(x, 0, Color(v, v, v))
	return image

## The grade (`GRADE` or `GRADE_EXPOSURE_1`) of a display value in [0, 1] (what the tone mapper writes, sRGB encoded), linear between the 33 samples.
static func grade_value(v: float, exposure_one := false) -> float:
	var table: Array = GRADE_EXPOSURE_1 if exposure_one else GRADE
	var at := clampf(v, 0.0, 1.0) * float(table.size() - 1)
	var i := mini(int(at), table.size() - 2)
	return lerpf(float(table[i]), float(table[i + 1]), at - float(i))

## The inverse of `grade_value` (the table is monotone), the lowest input for an output in [0, 1].
static func grade_inverse(v: float, exposure_one := false) -> float:
	var table: Array = GRADE_EXPOSURE_1 if exposure_one else GRADE
	var out := clampf(v, 0.0, float(table[table.size() - 1]))
	for i in table.size() - 1:
		var lo: float = table[i]
		var hi: float = table[i + 1]
		if out <= hi and hi > lo:
			return (float(i) + (out - lo) / (hi - lo)) / float(table.size() - 1)
	return 1.0

## What the show's picture makes of a scene-linear colour: exposure, sRGB encode, the grade (in sRGB). Returns the SCREEN colour (sRGB, as a file would hold it).
static func screen_colour(linear: Color, exposure_one := false) -> Color:
	var e := 1.0 if exposure_one else TONE_EXPOSURE
	var c := Color(clampf(linear.r * e, 0.0, 1.0), clampf(linear.g * e, 0.0, 1.0), clampf(linear.b * e, 0.0, 1.0)).linear_to_srgb()
	return Color(grade_value(c.r, exposure_one), grade_value(c.g, exposure_one), grade_value(c.b, exposure_one))

## The scene-linear light that the picture turns into the SCREEN colour `screen` (sRGB hex as seen): the inverse of `screen_colour`. A sky or an unshaded backdrop given this light shows `screen`.
static func scene_linear(screen: Color, exposure_one := false) -> Color:
	var e := 1.0 if exposure_one else TONE_EXPOSURE
	var c := Color(grade_inverse(screen.r, exposure_one), grade_inverse(screen.g, exposure_one), grade_inverse(screen.b, exposure_one)).srgb_to_linear()
	return Color(c.r / e, c.g / e, c.b / e)

## The flat ambient colour (linear) of the Environment: the cosine-weighted mean of the gradient for an up-facing surface, (2 up + horizon) / 3. `fill`: set-up A (the fill is a light), else B.
static func ambient_flat(fill := true) -> Color:
	var up := AMBIENT_A_UP if fill else AMBIENT_B_UP
	var side := AMBIENT_A_SIDE if fill else AMBIENT_B_SIDE
	return (up * 2.0 + side) / 3.0
