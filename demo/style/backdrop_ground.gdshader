shader_type spatial;
// The ground of the far-below world (style/backdrop.gd): one big quad, the map is drawn here from the world position, no mesh per street or field.
// kind 0 streets and lots on a grid (city, building site), 1 fields, hedges and a river (park), 3 cloud sea in halftone bands.
// Patterns fade to their average colour where one pixel covers more than a few metres (no shimmer), then into the horizon haze.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;
#include "res://style/backdrop_motion.gdshaderinc"
uniform int kind = 0;
uniform vec2 origin = vec2(0.0);
uniform float cell = 44.0;
uniform float road = 10.0;
uniform float seed = 1.0;
uniform vec3 c0 : source_color = vec3(0.7);
uniform vec3 c1 : source_color = vec3(0.65);
uniform vec3 c2 : source_color = vec3(0.6);
uniform vec3 c3 : source_color = vec3(0.55);
uniform vec3 c4 : source_color = vec3(0.4);
uniform vec3 c5 : source_color = vec3(0.8);
uniform vec3 line_color : source_color = vec3(0.1, 0.11, 0.23);
varying vec3 vworld;

void vertex() {
	vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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

vec3 pick(float r) {
	if (r < 0.25) return c0;
	if (r < 0.5) return c1;
	if (r < 0.75) return c2;
	return c3;
}

void fragment() {
	vec2 p = vworld.xz - origin;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = length(vworld - cam);
	float footprint = length(fwidth(p));
	vec3 col;
	vec3 average;
	if (kind == 0) {
		vec2 q = p / cell;
		vec2 id = floor(q + 0.5);
		vec2 m = (q - id) * cell;
		float half_lot = (cell - road) * 0.5;
		vec2 am = abs(m);
		bool lot = am.x < half_lot && am.y < half_lot;
		average = mix(c0, c4, 0.3);
		if (lot) {
			col = pick(hash21(id + seed));
			float curb = half_lot - max(am.x, am.y);
			col = mix(c5, col, smoothstep(0.0, 1.0, curb - 1.4));
			col = mix(line_color, col, smoothstep(0.0, 0.5, curb));
		} else {
			col = c4;
			float dx = cell * 0.5 - am.x;
			float dy = cell * 0.5 - am.y;
			bool vroad = dx < 0.3 && dy > road * 0.5 + 0.5;
			bool hroad = dy < 0.3 && dx > road * 0.5 + 0.5;
			if ((vroad && fract(p.y / 7.0) < 0.5) || (hroad && fract(p.x / 7.0) < 0.5)) {
				col = c5;
			}
		}
	} else if (kind == 1) {
		vec2 patch_id = floor(p / 90.0);
		float r = hash21(patch_id + seed);
		vec2 dir = normalize(vec2(hash21(patch_id + 3.0) - 0.5, hash21(patch_id + 7.0) - 0.5) + vec2(0.001));
		float rows = step(0.5, fract(dot(p, dir) / 5.0));
		col = pick(r) * (0.96 + 0.07 * rows);
		vec2 inner = abs(fract(p / 90.0) - 0.5) * 90.0;
		float edge = 45.0 - max(inner.x, inner.y);
		col = mix(c5, col, smoothstep(0.4, 1.2, edge));
		float river = abs(p.y - 140.0 * sin(p.x * 0.005 + seed) - 60.0 * sin(p.x * 0.013) - 40.0);
		float water = 1.0 - smoothstep(18.0, 20.0, river);
		float wave = step(0.9, sin(p.x * 0.5 + river * 0.8 + seed) * 0.5 + 0.5);
		col = mix(col, c4 * (1.0 + 0.12 * wave), water);
		average = mix(c0, c2, 0.5) * 0.97;
	} else {
		float n = vnoise(p * 0.010 + seed) * 0.62 + vnoise(p * 0.027 + seed * 3.0) * 0.38;
		float bands = n * 4.0;
		float band = floor(bands);
		col = band < 1.5 ? (band < 0.5 ? c3 : c2) : (band < 2.5 ? c1 : c0);
		float dots = 1.0 - smoothstep(0.28, 0.40, length(fract(p * 0.12) - 0.5));
		col = mix(col, c5, dots * step(band, 1.5) * 0.4);
		average = c1;
	}
	float fade = smoothstep(2.0, 9.0, footprint);
	col = mix(col, average, fade);
	col = calm_color(col);
	ALBEDO = mix(col, haze_color(), haze_amount(d));
}
