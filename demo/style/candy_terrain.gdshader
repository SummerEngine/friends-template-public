shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
// The candy world's terrain donut (style/candy_world.gd): lime vertex colours, hand-lit like the other backdrop pieces, a white contour line every few metres of height, a few winding
// swirl tracks (iso-lines of a smooth noise) and the land half of the white foam line where the ground meets the slime sea (the sea's shader draws the other half). The shoreline is read
// from the SHORE FIELD texture (signed metres to the waterline, shared with candy_sea.gdshader): the terrain is cut at the waterline (nothing of it shows on the slime), so the shore is a
// smooth analytic curve, not the mesh's own intersection with the sea. All in world metres of the full-size world (`world_scale` undoes a phone-sized one), no TIME.
#include "res://style/candy_fog.gdshaderinc"

uniform vec3 sun_dir = vec3(0.30, 0.876, 0.38);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9137, 0.7686);
uniform float sun_energy = 0.9;
uniform vec3 amb_up = vec3(0.57, 0.46, 0.97);
uniform vec3 amb_side = vec3(0.44, 0.27, 0.86);
uniform vec3 amb_down = vec3(0.05, 0.20, 1.0);
uniform vec3 light_ref = vec3(1.3, 1.1, 1.45);    // the light of an average lit slope (more than a flat face: the sun is turned towards the camera); see candy_backdrop.gdshader
uniform float world_scale = 1.0;
uniform float sun_follow = 0.75;
uniform float sea_y = 0.0;                    // world height of the sea (foam band)
uniform float contour_step = 22.0;            // m of height between two contour lines
uniform float line_alpha = 0.6;
uniform vec3 swirl_color : source_color = vec3(0.86, 0.96, 0.62);
uniform vec3 line_color : source_color = vec3(0.97, 0.98, 0.82);
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float foam_width = 1.1;               // m (full-size world) on each side of the waterline
uniform sampler2D shore_tex : filter_linear, repeat_disable;   // signed metres to the waterline, negative on the slime
uniform vec2 shore_origin;
uniform vec2 shore_size;
uniform float fog_mul = 0.7;                  // the far meadow fades into the haze a little slower than the mountains: a far island keeps its lime instead of going grey-green
uniform vec3 slope_color : source_color = vec3(0.40, 0.70, 0.12);   // the terraces' faces and the hills' slopes (CandyWorld._terrain sets it: a slightly deeper lime, not a dark green)
uniform float relief = 1.8;                    // how much the slopes' tilt is exaggerated for the lighting: gentle rolling light and shade

varying vec3 wpos;
varying vec3 wnor;
varying vec2 local;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// 1 on a line at every integer of `v`, 0.5 px wide at least, fading out when the lines would be thinner than the pixels (no shimmer).
float lines(float v, float width) {
	float aa = fwidth(v);
	float d = abs(fract(v + 0.5) - 0.5);
	float w = max(width, aa * 0.9);
	float l = 1.0 - smoothstep(w * 0.55, w, d);
	return l * (1.0 - smoothstep(0.18, 0.5, aa));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local = VERTEX.xz;
}

void fragment() {
	vec2 hs = texture(shore_tex, (local - shore_origin) / shore_size).rg;       // height over the slime and its slope
	float to_water = clamp(hs.r / max(hs.g, 0.02), -96.0, 96.0);                 // metres from the waterline: the exact contour of a smooth field
	if (to_water < 0.0) discard;                                                // on the slime: the sea draws it
	vec3 c = COLOR.rgb;
	vec2 p = wpos.xz / world_scale;
	float h = (wpos.y - sea_y) / world_scale;
	vec3 n = normalize(wnor);
	c = mix(c, slope_color, smoothstep(0.01, 0.09, 1.0 - n.y));   // pale lime tops, a slightly deeper lime on the slopes and ledge faces (the darker lip of a terrace)
	float near_lines = 1.0 - 0.8 * smoothstep(200.0, 700.0, -VERTEX.z / world_scale);   // the far meadow has fewer lines (the terraces' foreshortened ledges would hatch it)
	float contour = lines(h / contour_step + (vnoise(p * 0.012) - 0.5) * 1.8, 0.016) * near_lines;   // loose, winding contour lines
	float swirl_field = vnoise(p * 0.0036 + 11.0) * 0.65 + vnoise(p * 0.009 + 3.0) * 0.35;
	float swirl = lines(swirl_field * 3.2, 0.05) * near_lines;
	c = mix(c, swirl_color, swirl * 0.3);
	c = mix(c, line_color, clamp(contour * line_alpha, 0.0, 1.0));
	float lip = smoothstep(9.0, 1.5, to_water);                               // the meadow's edge above the water: a darker green lip
	c *= mix(vec3(1.0), vec3(0.8, 0.88, 0.84), lip);
	vec2 to_eye = CAMERA_POSITION_WORLD.xz - wpos.xz;
	vec3 amb = n.y >= 0.0 ? mix(amb_side, amb_up, n.y) : mix(amb_side, amb_down, -n.y);
	vec2 across = to_eye / max(length(to_eye), 0.001) * sqrt(max(1.0 - sun_dir.y * sun_dir.y, 0.0));
	vec3 sun_l = normalize(mix(sun_dir, vec3(across.x, sun_dir.y, across.y), sun_follow));
	vec3 n_lit = normalize(vec3(n.x * relief, n.y, n.z * relief));
	vec3 lit = c * (amb + sun_col * sun_energy * max(dot(n_lit, sun_l), 0.0)) / light_ref;
	float aa = fwidth(to_water);
	float fw = max(foam_width, aa * 2.0);
	float foam = 1.0 - smoothstep(fw - aa * 1.6, fw + aa * 1.6, to_water);     // the land half of the crisp foam line: pure white like the sea's half, never lit
	ALBEDO = mix(candy_fog(lit, -VERTEX.z * fog_mul), candy_fog(foam_color, -VERTEX.z), foam);
}
