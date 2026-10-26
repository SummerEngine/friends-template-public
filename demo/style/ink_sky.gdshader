shader_type sky;
// Style "ink": cream paper, a halftone gradient and ink-drawn clouds. No sun disc: the 2D sun
// with rays read as silly. The light direction only shows as a warm halftone glow;
// the clouds live on a plane above the camera, so they shrink towards the horizon (perspective),
// get an ink outline and a halftone-dotted underside like the rest of the ink world.
#include "res://style/calm_palette.gdshaderinc"
uniform vec3 paper : source_color = vec3(0.965, 0.925, 0.82);
uniform vec3 tint : source_color = vec3(0.60, 0.74, 1.0);
uniform vec3 ink : source_color = vec3(0.106, 0.114, 0.227);
uniform vec3 sun_dir = vec3(-0.30, 0.34, -0.89);
uniform vec3 sun_color : source_color = vec3(1.0, 0.82, 0.25);
uniform float cloud_edge = 0.56;
uniform float cloud_scale = 0.75;
uniform float drift = 0.004;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// screen-ish halftone dot grid at 45 degrees: 1 inside a dot of the given radius (0..0.7)
float dots(vec2 uv, float radius) {
	uv = vec2(uv.x * 0.7071 + uv.y * 0.7071, -uv.x * 0.7071 + uv.y * 0.7071);
	vec2 g = fract(uv) - 0.5;
	return 1.0 - smoothstep(radius - 0.08, radius + 0.08, length(g));
}

void sky() {
	vec3 paper_c = calm_color(paper);
	vec3 tint_c = calm_color(tint);
	vec3 sun_c = calm_color(sun_color);
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = paper_c;
	// halftone gradient, bigger dots towards the zenith
	vec2 uv = vec2(atan(d.x, -d.z), h) * 90.0;
	float amount = smoothstep(0.02, 0.9, h);
	col = mix(col, tint_c, dots(uv, amount * 0.55) * step(0.01, h));
	// warm glow towards the light, drawn as yellow halftone dots (no disc, no rays)
	float toward = dot(d, normalize(sun_dir));
	float glow = smoothstep(0.90, 0.995, toward);
	col = mix(col, sun_c, dots(uv * 0.55, glow * 0.50) * step(0.02, glow));
	// clouds on a plane above the camera
	if (h > 0.02) {
		vec2 p = d.xz / (h + 0.10) * cloud_scale + vec2(TIME * drift, 0.0);
		float c = fbm(p);
		float fade = smoothstep(0.02, 0.20, h);
		float body = smoothstep(cloud_edge, cloud_edge + 0.004, c) * fade;
		// outline: constant width on screen (the plane is stretched towards the horizon)
		float w = clamp(fwidth(c) * 1.5, 0.0008, 0.02);
		float ring = (smoothstep(cloud_edge - w, cloud_edge - w * 0.8, c) - smoothstep(cloud_edge, cloud_edge + w * 0.2, c)) * fade;
		// underside: where the cloud is missing a little towards the horizon
		float lit = fbm(p + vec2(0.0, 0.07 / (1.0 + 4.0 * (1.0 - h))));
		float under = body * (1.0 - smoothstep(cloud_edge, cloud_edge + 0.03, lit));
		col = mix(col, paper_c, body);
		col = mix(col, tint_c * 0.9, under * dots(uv * 0.5, 0.45));
		col = mix(col, ink, ring);
	}
	COLOR = col;
}
