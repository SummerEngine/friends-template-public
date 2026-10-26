shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;
// The podium room's night (style/podium_room.gd `_dome`): the inside of a big sphere, a dark violet dome over a blue floor of haze, with star specks. Unshaded and static (no TIME): the colours are
// SCENE-LINEAR light of the screen colours (CandyLook.scene_linear, set through `source_color` uniforms the way style/candy_world.gd does it), so the picture's grade lands on them. Above the
// horizon `horizon` -> `mid` (12 degrees) -> `zenith` (50 degrees); under it `below` -> `deep` (30 degrees down), with a soft seam about the horizon. Stars: one cell of `cell` degrees in azimuth and
// elevation holds at most one star (`density` of the cells do), a speck of one or two pixels (its radius follows the pixel's own angle, so it is the same few pixels at every resolution and lens), in
// one of four pale colours; under the horizon they are dimmer (the blue is the stage's glassy floor reflecting them).
uniform vec3 zenith : source_color = vec3(0.04, 0.02, 0.12);
uniform vec3 mid : source_color = vec3(0.06, 0.03, 0.16);
uniform vec3 horizon : source_color = vec3(0.10, 0.06, 0.22);
uniform vec3 below : source_color = vec3(0.07, 0.10, 0.25);
uniform vec3 deep : source_color = vec3(0.05, 0.20, 0.40);
uniform vec3 star_a : source_color = vec3(1.0, 0.97, 0.85);
uniform vec3 star_b : source_color = vec3(0.75, 0.93, 1.0);
uniform vec3 star_c : source_color = vec3(1.0, 0.78, 0.93);
uniform vec3 star_d : source_color = vec3(1.0, 0.89, 0.48);
uniform float cell = 3.4;
uniform float density = 0.8;
uniform float star_size = 2.4;

varying vec3 dir;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	float el = degrees(asin(clamp(d.y, -1.0, 1.0)));
	vec3 up = mix(horizon, mid, smoothstep(0.0, 12.0, el));
	up = mix(up, zenith, smoothstep(12.0, 50.0, el));
	vec3 down = mix(below, deep, smoothstep(0.0, 30.0, -el));
	vec3 col = mix(down, up, smoothstep(-3.0, 3.0, el));
	float az = degrees(atan(d.x, -d.z)); // 0 straight ahead of the stage's camera (-z); the seam is behind it
	vec2 g = vec2(az, el) / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float present = step(hash(id), density);
	vec2 at = 0.2 + 0.6 * vec2(hash(id + 7.3), hash(id + 19.1));
	vec2 delta = (f - at) * cell;
	delta.x *= cos(radians(el));
	float px = fwidth(el) + 0.00001;
	float r = px * (0.7 + 1.1 * hash(id + 3.7)) * star_size;
	float s = (1.0 - smoothstep(r * 0.25, r * 1.25, length(delta))) * present;
	float pick = hash(id + 11.9);
	vec3 tint = pick < 0.4 ? star_a : (pick < 0.65 ? star_b : (pick < 0.85 ? star_c : star_d));
	float dim = mix(0.45, 1.0, smoothstep(-3.0, 3.0, el));
	col = mix(col, tint, clamp(s * dim, 0.0, 1.0));
	ALBEDO = col;
}
