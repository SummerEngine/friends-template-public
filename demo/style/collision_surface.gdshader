shader_type spatial;
// Collision look: a level drawn from its own collision shapes (style/collision_look.gd). Flat toon colours, no textures, no lights:
// every face takes one of three tones from the direction it faces (a fixed sun: tops lightest, the two sides lit and away darker),
// and its colour from its ROLE so a glance tells the parts of a level apart:
//   role 0  ground and low slabs: cream top, warm tan sides, the top's free border (a band along every drop-off) in a darker ochre;
//   role 1  walls and tall blocks you bump into: teal everywhere, light diagonal hatching on the sides;
//   role 2  hop blocks (knee to head high): teal sides, cream top with the ochre rim band;
//   role 3  ice: pale blue top and sides (the top's free border a little deeper);
//   hazard  red/orange warning stripes on every face.
// Anything far from the level's route (vertex or uniform "background" 0..1) is pulled toward a dark, cool, low-contrast slate.
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec4 floor_top : source_color = vec4(1.0, 0.965, 0.86, 1.0);
uniform vec4 ground_side_0 : source_color = vec4(0.82, 0.72, 0.54, 1.0);
uniform vec4 ground_side_1 : source_color = vec4(0.72, 0.62, 0.45, 1.0);
uniform vec4 ground_side_2 : source_color = vec4(0.6, 0.5, 0.36, 1.0);
uniform vec4 rim_color : source_color = vec4(0.72, 0.5, 0.27, 1.0);
uniform float rim_width = 0.3;
uniform vec4 wall_top : source_color = vec4(0.62, 0.8, 0.82, 1.0);
uniform vec4 wall_side_0 : source_color = vec4(0.36, 0.62, 0.68, 1.0);
uniform vec4 wall_side_1 : source_color = vec4(0.28, 0.5, 0.57, 1.0);
uniform vec4 wall_side_2 : source_color = vec4(0.2, 0.37, 0.45, 1.0);
uniform vec4 hatch_color : source_color = vec4(0.7, 0.86, 0.87, 1.0);
uniform vec4 ice_top : source_color = vec4(0.62, 0.84, 1.0, 1.0);
uniform vec4 ice_side_0 : source_color = vec4(0.42, 0.7, 0.95, 1.0);
uniform vec4 ice_side_1 : source_color = vec4(0.34, 0.58, 0.88, 1.0);
uniform vec4 ice_side_2 : source_color = vec4(0.25, 0.44, 0.74, 1.0);
uniform vec4 stripe_a : source_color = vec4(1.0, 0.35, 0.21, 1.0);
uniform vec4 stripe_b : source_color = vec4(1.0, 0.64, 0.12, 1.0);
uniform vec4 background_tone : source_color = vec4(0.36, 0.35, 0.51, 1.0);
uniform vec3 sun = vec3(-0.5, 0.78, 0.38);
uniform bool hazard = false;
uniform bool vertex_data = true;      // false: the mesh has no data, role_uniform / background_uniform stand for it
uniform float role_uniform = 1.0;
uniform float background_uniform = 0.0;
varying vec3 lpos;
varying vec3 lscale;
varying vec3 wnrm;
varying vec3 wpos;
varying vec3 rim;
varying vec2 info;

void vertex() {
	lpos = VERTEX;
	lscale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (vertex_data) {
		rim = CUSTOM0.xyz * ((lscale.x + lscale.y + lscale.z) / 3.0); // metres to the nearest free border of the top, per edge
		info = COLOR.rg;                                                  // x: background 0..1, y: role / 3
	} else {
		rim = vec3(1000.0);
		info = vec2(background_uniform, role_uniform / 3.0);
	}
}

void fragment() {
	vec3 n = normalize(wnrm);
	float lit = dot(n, normalize(sun));
	int band = lit > 0.62 ? 0 : (lit > 0.12 ? 1 : 2);
	float top = smoothstep(0.55, 0.75, n.y);
	float role = info.y * 3.0;
	vec3 col;
	if (hazard) {
		vec3 m = lpos * lscale;
		float s = step(0.5, fract((m.x + m.y + m.z) * 0.9));
		col = mix(stripe_a.rgb, stripe_b.rgb, s) * (band == 0 ? 1.0 : (band == 1 ? 0.86 : 0.7));
	} else {
		vec3 ground = band == 0 ? ground_side_0.rgb : (band == 1 ? ground_side_1.rgb : ground_side_2.rgb);
		vec3 wall = band == 0 ? wall_side_0.rgb : (band == 1 ? wall_side_1.rgb : wall_side_2.rgb);
		float d = min(rim.x, min(rim.y, rim.z));
		float soft = fwidth(d) * 1.5 + 0.01;
		float on_rim = 1.0 - smoothstep(rim_width - soft, rim_width, d);
		bool ice = role > 2.5;
		bool wall_role = role > 0.5 && !ice;
		vec3 up = (wall_role && role < 1.5) ? wall_top.rgb : mix(floor_top.rgb, rim_color.rgb, on_rim);
		if (role > 1.5) up = mix(floor_top.rgb, rim_color.rgb, on_rim);
		if (ice) {
			ground = band == 0 ? ice_side_0.rgb : (band == 1 ? ice_side_1.rgb : ice_side_2.rgb);
			up = mix(ice_top.rgb, rim_color.rgb * 0.35 + ice_side_1.rgb * 0.65, on_rim);
		}
		col = mix(wall_role ? wall : ground, up, top);
		if (wall_role) {
			// light diagonal hatching on the sides of what you bump into
			float h = ((wpos.x + wpos.z) * 0.7071 + wpos.y) * 3.4;
			float w = fwidth(h) * 1.2;
			float line = 1.0 - smoothstep(0.035, 0.035 + w, abs(fract(h) - 0.5));
			line *= (1.0 - top) * (1.0 - smoothstep(0.25, 0.6, w)) * (band == 2 ? 0.55 : 1.0);
			col = mix(col, hatch_color.rgb, line * 0.42);
		}
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		vec3 cool = background_tone.rgb * (0.45 + 0.65 * lum);
		col = mix(col, cool, info.x * 0.85);
	}
	ALBEDO = col;
}
