// Shared by stage_tile.gdshader (the tiles) and stage_tile_fade.gdshader (a floor that is fading out or in): the tiles of a stage round (style/stage_tile_look.gd) are glossy
// chamfered slabs of the candy look: a flat authored colour (the instance colour, or `tint` for the one-off ground tray), lit by the engine's own PBR (roughness `roughness`), plus
// two additions for a tile: a self light (`self_light` of its own colour, added as emission) and an additive rim `rim_color * pow(1 - N.V, rim_power)`. A faint near-white
// sheen band lifts the colour on the flat top and the chamfer's slope is lifted towards white (its bright edge, `bevel_lift`), with a white fresnel on top of it (`bevel_fresnel`): an icy bevel
// that reads lighter than the tile's top. `glint`: a soft sun lobe on the top of a tile (the tops bow a little, each its own way, so the sun's mirror image catches a few tiles only) and `sheen`, a pale cyan fresnel. The vertical
// side of a slab is darkened towards a navy trim (`side_dark`, `trim`): the dark seam under a tile. The vertex colour only darkens the foot of the chamfer (a fake occlusion in the seam
// between two tiles).
// QUILTED MATS (`mat_size` > 0, the plain square floors): the floor is not a grid of its cells but big padded mats of `mat_size` m on a lattice turned by `mat_angle` and sheared by `mat_shear` (world
// space, so the seams ignore the cell borders): soft dark seams `mat_seam` m wide, a rounded shoulder `mat_shoulder` m wide whose normal tilts towards the seam (the pillow's sheen), every mat
// slightly lighter or deeper than its neighbours (`mat_deep`, `mat_boost`). No time.
uniform bool colors_linear = false;   // the Compatibility renderer hands COLOR over already linear (the look sets this)
uniform vec4 tint : source_color = vec4(0.0); // alpha > 0: this colour (linear) replaces the instance colour (the ground's tray)
uniform float roughness = 0.55;
uniform float tile_specular = 0.15;   // the engine's specular amount (0.5 = F0 0.04): a little less, so a far tile keeps its authored colour under the sky's reflection
uniform float self_light = 0.3;       // of the tile's albedo, as emission
uniform vec4 rim_color : source_color = vec4(1.0, 0.5, 1.0, 1.0);
uniform float rim_power = 4.0;
uniform float rim_strength = 1.0;     // 0: no rim
uniform float glyph = 0.14;           // 0: no glyph; else how far the glyph lifts the colour towards white
uniform float glyph_scale = 1.0;      // the glyph's size in tile widths of 4 m (the stage tiles are 3.5 to 4.1 m)
uniform float bevel_dark = 1.0;       // < 1: the chamfer slope is darkened by this factor (the seam between two cells of a plain floor)
uniform float centre_lift = 0.05;     // the flat top is this much lighter at its middle (towards white): a glossy slab's soft highlight
uniform float bevel_lift = 0.1;       // how far the chamfer's slope is lifted towards white: the bright edge of a glossy slab
uniform float bevel_fresnel = 0.0;    // white fresnel on the chamfer: pow(1 - N.V, 2.5) of this, additive
uniform float glint = 0.0;            // 0: none; else the strength of the soft sun lobe on a tile's top (a view dependent sheen: only tiles whose slightly bowled top mirrors the sun to the eye catch it)
uniform float sheen = 0.0;            // pale cyan fresnel on the top (pow(1 - N.V, 3) of this, additive)
uniform float bowl = 0.05;            // how far a tile's top bows: its normal leans this much per metre from the middle, plus a lean of its own per tile (a pillowy vinyl top)
uniform vec3 sun_dir = vec3(-0.42, 0.875, 0.24); // world direction towards the sun (style/candy_look.gd towards(); the look sets it)
uniform vec4 sheen_color : source_color = vec4(0.75, 0.97, 1.0, 1.0);
uniform float side_dark = 1.0;        // < 1: the vertical side takes this much of its own albedo, the rest the trim colour, and no own light (a thin navy trim under the chamfer, the dark accent)
uniform vec4 trim : source_color = vec4(0.012, 0.012, 0.05, 1.0); // the colour the side darkens towards (about #1c1c4a)
uniform float mat_size = 0.0;         // > 0: the floor is quilted mats of this size in metres
uniform float mat_angle = 0.62;       // rad: the mat lattice's turn
uniform float mat_shear = 0.35;       // the lattice's shear (a parallelogram, not a rectangle)
uniform float mat_seam = 0.45;        // m: the dark crease, centre to soft end
uniform float mat_shoulder = 2.0;     // m: the rounded shoulder along a seam, whose normal tilts towards it
uniform float mat_tilt = 0.7;         // how far the shoulder's normal leans over at the seam
uniform float mat_dark = 0.7;         // the albedo factor at the middle of a crease
uniform float mat_valley = 0.86;       // the albedo factor along the whole shoulder's far end (the quilt's valley between two pillows, a soft gradient)
uniform float mat_lift = 0.08;        // a mat's middle: this far towards white (the pillow's soft highlight)
uniform float mat_deep = 0.8;         // each mat's own brightness runs from the colour times `mat_deep` (a deeper mat) to the colour times `mat_boost` (a lighter one), clipped: the hue and the saturation of a vivid colour stay
uniform float mat_boost = 1.0;         

varying vec3 shade;                   // the colour (instance times vertex colour), sRGB
varying vec2 local;                   // the position on the tile, metres from its middle
varying vec2 world;                   // the position in the world (x, z) of a mat floor
varying float top;                    // 1 on the flat top face
varying float bevel;                  // 1 on the chamfer's slope (a normal tilted between up and out)
varying float side;                   // 1 on the vertical side

vec3 linear_of(vec3 c) {
	if (colors_linear) return c;
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

// What vertex() of both shaders does (a varying cannot be assigned in a function): the colour, the place on the tile and in the world, and whether it is the flat top, the chamfer or the side.
#define TILE_VERTEX shade = COLOR.rgb; local = VERTEX.xz; world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; top = step(0.999, NORMAL.y); bevel = step(0.15, NORMAL.y) * (1.0 - top); side = step(abs(NORMAL.y), 0.1);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// A faint macro pattern on the top: one wide soft diagonal sheen band (0..1), the glossy plastic's printed glyph at a whisper; nothing arrow-shaped, nothing that repeats inside a tile.
float glyph_mask(vec2 at) {
	float d = (at.x * 0.8 + at.y * 0.6) / 1.9;
	return (1.0 - smoothstep(0.0, 0.32, abs(d - 0.12))) * (1.0 - smoothstep(1.1, 1.9, length(at)));
}

// The lean of a tile top's normal (world xz): a bowl round the tile's middle plus a lean of its own (`id` from its colour), so the sun's mirror image falls on a few tiles and in a different place on each.
vec2 bowl_lean(vec2 at, float id) {
	return at * bowl + (vec2(fract(id * 5.3), fract(id * 9.7)) - 0.5) * 0.14;
}

// The mat under world point `at`: x the distance to the nearest seam in metres, yz the unit direction (world xz) from the mat's middle to that seam, w the mat's own number 0..1.
vec4 mat_at(vec2 at) {
	float c = cos(mat_angle);
	float s = sin(mat_angle);
	vec2 q = vec2(c * at.x + s * at.y, -s * at.x + c * at.y);
	q.x += mat_shear * q.y;
	q /= mat_size;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 a = abs(f);
	float distance_m = (0.5 - max(a.x, a.y)) * mat_size;
	vec2 axis_m = a.x > a.y ? vec2(sign(f.x), 0.0) : vec2(0.0, sign(f.y));
	vec2 axis = vec2(c * axis_m.x - s * axis_m.y, s * axis_m.x + c * axis_m.y);
	return vec4(distance_m, axis, hash21(id));
}

// The fragment's normal: on a quilted mat floor the shoulder along a seam leans towards the seam (a pillow's rounded edge, which the light and the sky's reflection shade); on a tile top with a `glint`
// the top bows (bowl_lean). `normal` is the fragment's NORMAL and `view_matrix` the VIEW_MATRIX (the lean is a world direction).
vec3 tile_normal(vec3 normal, mat4 view_matrix) {
	if (top < 0.5) return normal;
	vec3 n = normal;
	if (glint > 0.0) {
		vec2 lean = bowl_lean(local, fract(dot(shade, vec3(91.7, 37.3, 53.1))));
		n = normalize(n + (view_matrix * vec4(lean.x, 0.0, lean.y, 0.0)).xyz);
	}
	if (mat_size <= 0.0) return n;
	vec4 m = mat_at(world);
	float shoulder = 1.0 - smoothstep(0.0, mat_shoulder, m.x);
	vec3 lean = (view_matrix * vec4(m.y, 0.0, m.z, 0.0)).xyz;
	return normalize(n + lean * shoulder * shoulder * mat_tilt);
}

// The tile's albedo, its own light and its roughness; `normal` and `view` are the fragment's NORMAL and VIEW.
void tile_fragment(vec3 normal, vec3 view, vec3 sun_view, out vec3 albedo, out vec3 emission, out float rough) {
	vec3 ao = clamp(linear_of(shade), 0.0, 1.0);
	vec3 color = ao;
	if (tint.a > 0.0) color = tint.rgb * ao;
	float g = glyph * top * glyph_mask(local / glyph_scale);
	float middle = top * centre_lift * (1.0 - smoothstep(0.3, 1.9, length(local)));
	float seam = 0.0;
	float valley = 0.0;
	if (mat_size > 0.0 && top > 0.5) {
		vec4 m = mat_at(world);
		color = clamp(color * mix(mat_deep, mat_boost, m.w), 0.0, 1.0);
		seam = 1.0 - smoothstep(0.0, mat_seam, m.x);
		valley = 1.0 - smoothstep(0.0, mat_shoulder * 1.4, m.x);
		middle = mat_lift * smoothstep(0.4, 2.8, m.x);
	}
	albedo = mix(color, vec3(1.0), max(max(g, bevel * bevel_lift), middle)) * mix(1.0, bevel_dark, bevel) * mix(1.0, mat_dark, seam) * mix(1.0, mat_valley, valley * (1.0 - seam));
	albedo = mix(albedo, albedo * side_dark + trim.rgb * (1.0 - side_dark), side);
	float nv = clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0);
	float rim = pow(1.0 - nv, rim_power);
	emission = albedo * self_light * (1.0 - side * (1.0 - side_dark)) + rim_color.rgb * rim * rim_strength * bevel; // the pink fresnel rim is on the chamfers only: a rim on the flat top turns a far tile milky at a grazing view
	emission += vec3(pow(1.0 - nv, 2.5)) * bevel_fresnel * bevel + sheen_color.rgb * pow(1.0 - nv, 3.0) * sheen * top;
	if (glint > 0.0 && top > 0.5) {
		vec3 mirror = reflect(-normalize(view), normalize(normal));
		emission += vec3(pow(max(dot(mirror, normalize(sun_view)), 0.0), 40.0)) * glint;
	}
	rough = roughness;
}
