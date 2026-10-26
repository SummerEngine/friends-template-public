shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
// The candy world's hand-lit backdrop pieces (style/candy_world.gd): cloud wall, puff clouds, foliage and mountains. Unshaded: a hemisphere ambient plus one sun term from the
// look's own numbers (style/candy_look.gd, SPEC 7.3) and the exp2 fog of the daylight look (candy_fog.gdshaderinc). No texture, no TIME: everything is static.
//   kind 0  flat or vertex colour (cloud wall, puffs)  | kind 1  foliage: vertex alpha < 0.75 marks the trunk (flat `trunk_color`), the rest takes the instance colour
//   kind 2  mountains: the vertex colour's r is the height inside the visible dome (0 foot, 1 tip) and picks the bands (`ramp0..4`: green foot, pink body, pale stripe, deep pink under the snow, snow); lit by its own normal with a key light on the left of the view (shadow side deeper rose / lavender), the foot hazed
#include "res://style/candy_fog.gdshaderinc"

uniform int kind = 0;
uniform vec3 albedo : source_color = vec3(1.0);
uniform bool use_vertex_color = true;
uniform vec3 ramp0 : source_color = vec3(0.54, 0.82, 0.19);
uniform vec3 ramp1 : source_color = vec3(0.91, 0.83, 0.82);
uniform vec3 ramp2 : source_color = vec3(0.98, 0.83, 0.86);
uniform vec3 ramp3 : source_color = vec3(0.98, 0.96, 0.96);
uniform vec3 ramp4 : source_color = vec3(0.98, 0.97, 0.97);
uniform vec3 wramp1 : source_color = vec3(0.96, 0.73, 0.81);   // the white meringue ramp (the vertex colour's g = 1): a pink foot band ...
uniform vec3 wramp2 : source_color = vec3(0.99, 0.95, 0.96);   // ... the white body ...
uniform vec3 wramp3 : source_color = vec3(0.96, 0.85, 0.91);   // ... a faint pink band ...
uniform vec3 wramp4 : source_color = vec3(0.96, 0.87, 0.93);   // ... and the pale tone under the cap
uniform float cap_at = 0.85;         // t of the snow cap's edge (CandyWorld.CAP_AT); its lobes droop up to 0.1 under it
uniform vec3 haze_color : source_color = vec3(0.86, 0.97, 0.99);   // what the feet of the mountains fade into: the cloud wall's pale band
uniform vec3 shadow_tint = vec3(0.66, 0.46, 0.74);     // the pink body's shadow side: a deeper rose with a lavender cast
uniform vec3 snow_shadow = vec3(0.78, 0.80, 0.95);     // the snow's shadow side: pale lavender blue
uniform vec3 white_shadow = vec3(0.74, 0.70, 0.90);    // the white body's shadow side: soft lavender grey
uniform vec3 trunk_color : source_color = vec3(0.62, 0.4, 0.32);
uniform vec3 sun_dir = vec3(0.30, 0.876, 0.38);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9137, 0.7686);
uniform float sun_energy = 0.9;
uniform vec3 amb_up = vec3(0.57, 0.46, 0.97);
uniform vec3 amb_side = vec3(0.44, 0.27, 0.86);
uniform vec3 amb_down = vec3(0.05, 0.20, 1.0);
uniform float sun_follow = 0.75;   // 0 = the sun's own azimuth, 1 = the sun stands behind the camera (every piece shows its lit face to the course)
uniform vec3 light_ref = vec3(1.1, 0.88, 1.25);   // the hemisphere + sun light of an average face: a colour authored as its screen colour shows it there
uniform float shade = 1.0;   // 0 = flat colour (cloud wall), 1 = lit by the hemisphere and the sun
uniform float lift = 0.0;    // puff clouds +0.6
uniform float fog_mul = 1.0;       // > 1: the piece fades into the haze faster (far mountains)
uniform float fog_amount = 1.0;   // how much of the exp2 fog the piece takes (the cloud wall stays paler than the haze)

varying vec3 wnor;
varying vec3 wpos;
varying vec3 lpos;
varying float flag;

void vertex() {
	wnor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
	flag = COLOR.a;
}

void fragment() {
	vec3 c = albedo;
	float sh = shade;
	float lf = lift;
	if (kind == 2) {
		// shaded dome (t: 0 at the dome's foot to 1 at its tip; the camera's horizon cuts it near 0.28): a green foot hazed into the cloud wall, a body (salmon pink with one pale and one deep thin band, or white meringue
		// with a pink foot band and a faint pink band) with a deeper tone under the snow cap whose lower edge droops in rounded lobes (the arc length round the diorama drives them). The lit side is the right of
		// the view (the sun of the course), the shadow side the left.
		float t = COLOR.r;
		float wm = COLOR.g;
		float arc = atan(lpos.z, lpos.x) * 1500.0;   // metres round the diorama's middle at the mountains' distance (the mesh's own space: the same for any world scale)
		float lobe = 0.6 * abs(sin(arc / 34.0 + 1.0)) + 0.4 * abs(sin(arc / 19.0 + 0.4));
		float edge = cap_at - 0.10 * lobe;
		float wave = sin(wpos.x * 0.012 + wpos.z * 0.007) * 0.5 + sin(wpos.x * 0.031 - wpos.z * 0.023 + 1.3) * 0.5;
		float tb = t + wave * 0.01;
		float w = 0.006;
		vec3 body = mix(ramp1, mix(wramp1, wramp2, smoothstep(0.3, 0.5, tb)), wm);
		c = mix(ramp0, body, smoothstep(0.12, 0.3, tb));
		float pale = smoothstep(0.36 - w, 0.36, tb) - smoothstep(0.405, 0.405 + w, tb);
		float deep = smoothstep(0.455 - w, 0.455, tb) - smoothstep(0.47, 0.47 + w, tb);
		c = mix(c, mix(ramp2, wramp3, wm), pale * mix(0.5, 0.35, wm));
		c = mix(c, mix(ramp3, wramp3, wm), deep * 0.45);
		c = mix(c, mix(ramp3, wramp4, wm), smoothstep(edge - 0.1, edge - 0.01, tb) * mix(0.8, 0.9, wm));   // the deeper tone under the cap
		float snow = smoothstep(edge - 0.006, edge + 0.006, t);
		vec3 body_c = c;
		vec3 n_m = normalize(wnor);
		vec2 to_cam = CAMERA_POSITION_WORLD.xz - wpos.xz;
		vec2 e = to_cam / max(length(to_cam), 0.001);
		vec3 key_l = normalize(vec3(e.x * 0.5 + e.y * 0.8, 0.55, e.y * 0.5 - e.x * 0.8));   // up, a little behind the camera, to the right
		float lam = dot(n_m, key_l);
		float lit_k = smoothstep(-0.1, 0.45, lam);
		vec3 tint = mix(mix(shadow_tint, white_shadow, wm), vec3(1.04, 1.02, 1.0), lit_k);
		vec3 snow_tint = mix(snow_shadow, vec3(1.0), lit_k);
		c = mix(body_c * tint, ramp4 * snow_tint, snow);
		c = mix(c, haze_color, (1.0 - smoothstep(0.05, 0.22, t)) * 0.3);
		sh = 0.0;   // lit above: only the fog is left to do
		lf = lift;
	} else if (kind == 1) {
		c = flag < 0.75 ? trunk_color : COLOR.rgb / max(flag, 0.001);
	} else if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	vec3 n = normalize(wnor);
	vec3 amb = n.y >= 0.0 ? mix(amb_side, amb_up, n.y) : mix(amb_side, amb_down, -n.y);
	vec2 to_eye = CAMERA_POSITION_WORLD.xz - wpos.xz;
	vec2 across = to_eye / max(length(to_eye), 0.001) * sqrt(max(1.0 - sun_dir.y * sun_dir.y, 0.0));
	vec3 sun_l = normalize(mix(sun_dir, vec3(across.x, sun_dir.y, across.y), sun_follow));
	vec3 light = amb + sun_col * sun_energy * max(dot(n, sun_l), 0.0);
	vec3 lit = mix(c, c * light / light_ref, sh) + vec3(lf);
	ALBEDO = mix(lit, candy_fog(lit, -VERTEX.z * fog_mul), fog_amount);
}
