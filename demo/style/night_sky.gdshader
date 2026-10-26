shader_type sky;
// The sky of the night look (style/night_look.gd `light`, built by levels/level_environment.gd): a deep gradient from a near-black zenith to a warm,
// dim horizon with a glow band, stars, a metal sun (a silver disc with twelve spikes and a halo in the accent, after the logo) and a planet with a lit
// rim. The stars, the sun and the planet are not drawn into the reflection and ambient cube maps (AT_CUBEMAP_PASS), only seen. No textures, no
// clouds, nothing animated (a sky shader that reads TIME makes the engine redraw its radiance map every frame): a few dozen ALU operations per pixel, cheap on a phone.
uniform vec3 zenith : source_color = vec3(0.01, 0.01, 0.015);
uniform vec3 horizon : source_color = vec3(0.07, 0.04, 0.02);
uniform vec3 below : source_color = vec3(0.005, 0.005, 0.008);
uniform vec3 glow_color : source_color = vec3(1.0, 0.7, 0.35);
uniform vec3 disc_core : source_color = vec3(0.85, 0.85, 0.85);
uniform vec3 disc_dir = vec3(0.28, 0.2, -1.0);
uniform vec3 planet_dir = vec3(-0.75, 0.36, -0.55);
uniform float star_cells = 64.0;      // star cells along the unit sphere: the fewer, the bigger and sparser the stars

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 d) {
	vec3 p = d * star_cells;
	vec3 cell = floor(p);
	float chance = hash13(cell);
	if (chance > 0.075) return 0.0;
	vec3 centre = cell + 0.25 + 0.5 * vec3(hash13(cell + 7.1), hash13(cell + 13.7), hash13(cell + 29.3));
	float dist = length(p - centre);
	float size = 0.1 + 0.12 * hash13(cell + 3.3);
	return smoothstep(size, size * 0.2, dist) * (0.35 + 0.65 * hash13(cell + 1.9));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = h >= 0.0 ? mix(horizon, zenith, pow(h, 0.42)) : mix(horizon, below, smoothstep(0.0, 0.25, -h));
	vec3 sun_d = normalize(disc_dir);
	vec2 flat_sun = normalize(sun_d.xz);
	float toward = dot(normalize(d.xz + vec2(1e-5)), flat_sun);
	col += glow_color * exp(-abs(h) * 12.0) * (0.05 + 0.1 * smoothstep(-0.3, 1.0, toward));
	if (!AT_CUBEMAP_PASS) {
		col += vec3(0.85, 0.9, 1.0) * stars(d) * smoothstep(-0.02, 0.18, h);
		// the metal sun: halo, twelve spikes, a silver disc
		float a = dot(d, sun_d);
		if (a > 0.9) {
			vec3 right = normalize(cross(sun_d, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(right, sun_d);
			vec2 q = vec2(dot(d, right), dot(d, up));
			float r = length(q);
			float angle = atan(q.y, q.x);
			float halo = exp(-r * 16.0) * 0.55;
			float spikes = pow(abs(cos(angle * 6.0)), 14.0) * smoothstep(0.17, 0.05, r) * smoothstep(0.055, 0.075, r);
			float disc = smoothstep(0.058, 0.052, r);
			float shade = 0.75 + 0.25 * dot(normalize(vec3(q / 0.058, 1.0)), normalize(vec3(-0.4, 0.5, 0.8)));
			col += glow_color * (halo + spikes * 0.9);
			col = mix(col, disc_core * shade, disc);
		}
		// the planet: a dark body, a lit rim on the side towards the sun
		vec3 pd = normalize(planet_dir);
		float pa = dot(d, pd);
		if (pa > 0.9) {
			vec3 right = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(right, pd);
			vec2 q = vec2(dot(d, right), dot(d, up)) / 0.16;
			float r = length(q);
			if (r < 1.0) {
				vec3 n = vec3(q, sqrt(1.0 - r * r));
				vec3 to_sun = normalize(vec3(dot(sun_d, right), dot(sun_d, up), 0.35));
				float lit = clamp(dot(n, to_sun), 0.0, 1.0);
				vec3 body = mix(zenith * 4.0, horizon * 2.0, 0.5) + glow_color * (pow(lit, 3.0) * 0.55 + pow(1.0 - n.z, 3.0) * lit * 0.8);
				col = mix(col, body, smoothstep(1.0, 0.96, r));
			}
		}
	}
	COLOR = col;
}
