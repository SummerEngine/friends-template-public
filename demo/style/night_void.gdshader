shader_type spatial;
// The floor of the void far under a night course (style/night_backdrop.gd): a near-black plane with a faint grid of the accent's dim tone that
// fades into the dark with distance (one plane, unlit, no textures). The lines keep one pixel of width, so they never shimmer.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 base : source_color = vec3(0.004);
uniform vec3 line_color : source_color = vec3(0.4, 0.25, 0.1);
uniform float cell = 40.0;
uniform float strength = 0.35;
uniform float fade_distance = 500.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = world.xz / cell;
	vec2 w = fwidth(q) + 1e-5;
	vec2 g = abs(fract(q - 0.5) - 0.5) / w;
	float line = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float dist = length(world - CAMERA_POSITION_WORLD);
	float near = exp(-dist / fade_distance);
	float thin = smoothstep(2.0, 8.0, 1.0 / w.x); // a cell smaller than a few pixels melts into the base
	ALBEDO = base + line_color * line * strength * near * thin;
}
