shader_type spatial;
// The little things of the party backdrop (style/party_backdrop.gd): confetti falling and turning (`fall` > 0: a column of that many metres,
// every piece on its own phase, shrinking to nothing at both ends so none pops in or out) and bunting swaying in the wind (`sway`).
// Unlit, vertex colour (the instance colour), two-sided. All motion is here, nothing runs on the CPU per frame.
// The night look (style/night_backdrop.gd) uses the same shader for its embers (`rise` 1: they climb instead of falling) and light blades (`fade_down`: the
// colour fades to black towards the lower end of the piece, `boost` > 1 makes the lit part bloom).
render_mode unshaded, cull_disabled, fog_disabled;

uniform float fall = 0.0;
uniform float sway = 0.0;
uniform float rise = 0.0;
uniform float fade_down = 0.0;
uniform float boost = 1.0;

varying float lit;

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	lit = fade_down > 0.0 ? clamp(1.0 + VERTEX.y * fade_down, 0.0, 1.0) : 1.0;
	float seed = fract(sin(dot(anchor.xz, vec2(12.9898, 78.233)) + anchor.y * 0.37) * 43758.5453);
	if (fall > 0.0) {
		float speed = 0.9 + seed * 0.9;
		float drop = mod(TIME * speed + seed * fall, fall);
		float life = drop / fall;
		float grow = smoothstep(0.0, 0.06, life) * (1.0 - smoothstep(0.94, 1.0, life));
		float spin = TIME * (1.5 + seed * 3.0) + seed * 6.2831;
		float c = cos(spin);
		float s = sin(spin);
		vec3 v = VERTEX * grow;
		v = vec3(v.x * c - v.z * s, v.y, v.x * s + v.z * c);
		v = vec3(v.x, v.y * cos(spin * 0.7) - v.z * sin(spin * 0.7), v.y * sin(spin * 0.7) + v.z * cos(spin * 0.7));
		VERTEX = v + vec3(sin(TIME * 0.8 + seed * 20.0) * 1.2, -drop * (rise > 0.5 ? -1.0 : 1.0), cos(TIME * 0.7 + seed * 17.0) * 1.2);
	} else if (sway > 0.0) {
		float hang = -VERTEX.y;
		VERTEX.z += sin(TIME * 2.2 + anchor.x * 0.9 + anchor.z * 0.9 + seed * 6.0) * sway * hang;
	}
}

void fragment() {
	// Decor never fills the lens: anything within 1.6 m of the camera is not drawn (a flag or a piece of confetti beside the shoulder camera).
	if (length(VERTEX) < 1.6) discard;
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * lit * boost; // the colours are sRGB
}
